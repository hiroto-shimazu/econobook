import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_index_link_copy.dart';

import '../constants/community.dart';
import '../models/ledger_entry.dart';
import '../models/payment_request.dart';
import '../models/split_rounding_mode.dart';
import 'firestore_refs.dart';
import 'ledger_service.dart';
import 'split_calculator.dart';

class RequestService {
  RequestService({FirebaseFirestore? firestore, LedgerService? ledgerService})
      : refs = FirestoreRefs(firestore ?? FirebaseFirestore.instance),
        ledger = ledgerService ?? LedgerService(firestore: firestore);

  final FirestoreRefs refs;
  final LedgerService ledger;

  Future<PaymentRequest> createRequest({
    required String communityId,
    required String fromUid,
    required String toUid,
    required num amount,
    String? memo,
    String visibility = 'community',
    DateTime? expireAt,
    required String createdBy,
    String type = 'request',
    String? linkedRequestId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('amount must be positive');
    }
    // Ensure users are members
    final isCentralBankSender = fromUid == kCentralBankUid;
    final fromMembership = isCentralBankSender
        ? null
  : await withIndexLinkCopyForService(() => refs.membershipDoc(communityId, fromUid).get());
    if (!isCentralBankSender && !(fromMembership?.exists ?? false)) {
      throw StateError('Requester is not a member');
    }
    final isCentralBankRecipient = toUid == kCentralBankUid;
    if (!isCentralBankRecipient) {
  final toMembership = await withIndexLinkCopyForService(() => refs.membershipDoc(communityId, toUid).get());
      if (!toMembership.exists) {
        throw StateError('Recipient is not a member');
      }
    }

    final requests = refs.paymentRequests(communityId);
    final docRef = requests.doc();
    final request = PaymentRequest(
      id: docRef.id,
      communityId: communityId,
      fromUid: fromUid,
      toUid: toUid,
      amount: amount,
      memo: memo,
      status: 'pending',
      expireAt: expireAt,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      visibility: visibility,
      type: type,
      linkedRequestId: linkedRequestId,
    );
    await docRef.set(request);
  return (await withIndexLinkCopyForService(() => docRef.get())).data()!;
  }

  Future<void> updateRequestDueDate({
    required String communityId,
    required String requestId,
    required String updatedBy,
    DateTime? dueDate,
  }) async {
    final docRef = refs.paymentRequests(communityId).doc(requestId);
    await docRef.update({
      'expireAt': dueDate == null ? FieldValue.delete() : Timestamp.fromDate(dueDate),
      'dueUpdatedBy': updatedBy,
      'dueUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<SplitCalculation> createSplitRequests({
    required String communityId,
    required String requesterUid,
    required List<String> targetUids,
    required num totalAmount,
    required int precision,
    required SplitRoundingMode roundingMode,
    String? memo,
    String visibility = 'community',
  }) async {
    if (targetUids.isEmpty) {
      throw ArgumentError('targetUids cannot be empty');
    }
    if (totalAmount <= 0) {
      throw ArgumentError('totalAmount must be positive');
    }

    final requesterMembership =
  await withIndexLinkCopyForService(() => refs.membershipDoc(communityId, requesterUid).get());
    if (!requesterMembership.exists) {
      throw StateError('Requester is not a member of this community');
    }

    for (final uid in targetUids) {
  final memberDoc = await withIndexLinkCopyForService(() => refs.membershipDoc(communityId, uid).get());
      if (!memberDoc.exists) {
        throw StateError('Target user $uid is not a member of this community');
      }
    }

    final calculation = calculateSplitAllocations(
      totalAmount: totalAmount,
      participantCount: targetUids.length,
      precision: precision,
      roundingMode: roundingMode,
    );

    await refs.raw.runTransaction((tx) async {
      for (var i = 0; i < targetUids.length; i++) {
        final targetUid = targetUids[i];
        final amount = calculation.amounts[i];
        final docRef = refs.paymentRequests(communityId).doc();
        final request = PaymentRequest(
          id: docRef.id,
          communityId: communityId,
          fromUid: requesterUid,
          toUid: targetUid,
          amount: amount,
          memo: memo,
          status: 'pending',
          expireAt: null,
          createdAt: DateTime.now(),
          createdBy: requesterUid,
          visibility: visibility,
          type: 'split',
        );
        tx.set(docRef, request);
      }
    });

    return calculation;
  }

  Future<PaymentRequest> approveRequest({
    required String communityId,
    required String requestId,
    required String approvedBy,
    String? memo,
  }) async {
    final requestRef = refs.paymentRequests(communityId).doc(requestId);

    bool alreadyHandled = false;
    await refs.raw.runTransaction((tx) async {
  final snap = await tx.get(requestRef);
      if (!snap.exists) {
        throw StateError('Request not found');
      }
      final data = snap.data()!;
      final status = data.status;
      if (status != 'pending' && status != 'processing') {
        alreadyHandled = true;
        return;
      }
      tx.update(requestRef, {
        'status': 'processing',
        'processedBy': approvedBy,
        'processedAt': FieldValue.serverTimestamp(),
      });
    });

    if (alreadyHandled) {
  final existing = await withIndexLinkCopyForService(() => requestRef.get());
      final data = existing.data();
      if (data == null) throw StateError('Request missing');
      return data;
    }

    late final LedgerEntry entry;
    try {
  final requestSnap = await withIndexLinkCopyForService(() => requestRef.get());
      final request = requestSnap.data();
      if (request == null) {
        throw StateError('Request disappeared');
      }
      entry = await ledger.recordTransfer(
        communityId: communityId,
        fromUid: request.toUid,
        toUid: request.fromUid,
        amount: request.amount,
        memo: memo ?? request.memo,
        createdBy: approvedBy,
        idempotencyKey: 'request_$requestId',
        visibility: request.visibility,
        requestId: requestId,
        entryType: request.type,
        enforceSufficientFunds: request.toUid != kCentralBankUid,
      );
    } catch (e) {
      await requestRef.update({
        'status': 'pending',
        'processedBy': FieldValue.delete(),
        'processedAt': FieldValue.delete(),
      });
      rethrow;
    }

    await requestRef.update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': approvedBy,
      'ledgerEntryId': entry.id,
    });

  final updated = await withIndexLinkCopyForService(() => requestRef.get());
    final result = updated.data();
    if (result == null) {
      throw StateError('Request update failed');
    }
    return result;
  }

  Future<PaymentRequest> rejectRequest({
    required String communityId,
    required String requestId,
    required String rejectedBy,
    String? reason,
  }) async {
    final requestRef = refs.paymentRequests(communityId).doc(requestId);
    await refs.raw.runTransaction((tx) async {
  final snap = await tx.get(requestRef);
      if (!snap.exists) {
        throw StateError('Request not found');
      }
      final data = snap.data()!;
      if (data.status != 'pending' && data.status != 'processing') {
        throw StateError('Request already handled');
      }
      tx.update(requestRef, {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': rejectedBy,
        'rejectionReason': reason,
      });
    });
  final updated = await withIndexLinkCopyForService(() => requestRef.get());
    final result = updated.data();
    if (result == null) throw StateError('Request missing');
    return result;
  }
}
