import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/community.dart';
import '../models/ledger_entry.dart';
import '../models/membership.dart';
import 'firestore_refs.dart';

class LedgerService {
  LedgerService({FirebaseFirestore? firestore})
      : refs = FirestoreRefs(firestore ?? FirebaseFirestore.instance);

  final FirestoreRefs refs;

  /// Records a transfer within a community using double-entry bookkeeping.
  Future<LedgerEntry> recordTransfer({
    required String communityId,
    required String fromUid,
    required String toUid,
    required num amount,
    String? memo,
    required String createdBy,
    String? idempotencyKey,
    String visibility = 'community',
    bool enforceSufficientFunds = false,
    String? requestId,
    String? taskId,
    String? splitGroupId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero');
    }
    if (fromUid == toUid) {
      throw ArgumentError('Cannot transfer to the same user');
    }

    final ledgerRef = refs.ledgerEntries(communityId).doc();
    final ledgerId = ledgerRef.id;
    final idKey = idempotencyKey ?? ledgerId;
    final idempotencyRef = refs.ledgerIdempotency(communityId).doc(idKey);

    String? existingEntryId;
    final isCentralBankPayer = fromUid == kCentralBankUid;
    if (toUid == kCentralBankUid) {
      throw ArgumentError('中央銀行を受取側に指定することはできません');
    }

    await refs.raw.runTransaction((tx) async {
      final idempotencySnap = await tx.get(idempotencyRef);
      if (idempotencySnap.exists) {
        existingEntryId =
            (idempotencySnap.data()?['entryId'] as String?) ?? ledgerId;
        return;
      }

      DocumentReference<Membership>? fromRef;
      if (!isCentralBankPayer) {
        fromRef = refs.membershipDoc(communityId, fromUid);
      }
      final toRef = refs.membershipDoc(communityId, toUid);
      final toSnap = await tx.get(toRef);
      if (!toSnap.exists) {
        throw StateError('Recipient is not a member of this community');
      }
      if (!isCentralBankPayer) {
        final fromSnap = await tx.get(fromRef!);
        if (!fromSnap.exists) {
          throw StateError('Sender is not a member of this community');
        }
        final fromBalance = fromSnap.data()?.balance ?? 0;
        if (enforceSufficientFunds && fromBalance < amount) {
          throw StateError('Insufficient balance');
        }
        tx.update(fromRef!, {'balance': FieldValue.increment(-amount)});
      }

      tx.update(toRef, {'balance': FieldValue.increment(amount)});

      final entryType = isCentralBankPayer ? 'central_bank' : 'transfer';
      tx.set(ledgerRef, {
        'cid': communityId,
        'type': entryType,
        'fromUid': fromUid,
        'toUid': toUid,
        'amount': amount,
        'memo': memo,
        'status': 'posted',
        'lines': [
          {'uid': fromUid, 'delta': -amount, 'role': 'debit'},
          {'uid': toUid, 'delta': amount, 'role': 'credit'},
        ],
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'postedAt': FieldValue.serverTimestamp(),
        'idempotencyKey': idKey,
        'visibility': visibility,
        'requestRef': requestId,
        'taskRef': taskId,
        'splitGroupId': splitGroupId,
      });

      tx.set(idempotencyRef, {
        'entryId': ledgerId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
      });
    });

    final docId = existingEntryId ?? ledgerId;
    final snap = await refs.ledgerEntries(communityId).doc(docId).get();
    final entry = snap.data();
    if (entry == null) {
      throw StateError('Ledger entry not found after transaction');
    }
    return entry;
  }

  /// Reverses a ledger entry by writing a compensating entry.
  Future<LedgerEntry> reverseEntry({
    required String communityId,
    required String entryId,
    required String performedBy,
    String? reason,
  }) async {
    final entrySnap = await refs.ledgerEntries(communityId).doc(entryId).get();
    final entry = entrySnap.data();
    if (entry == null) {
      throw StateError('Entry $entryId not found');
    }
    if (entry.status == 'reversed') {
      return entry;
    }

    final reversed = await recordTransfer(
      communityId: communityId,
      fromUid: entry.toUid ?? '',
      toUid: entry.fromUid ?? '',
      amount: entry.amount,
      memo: 'Reversal of $entryId${reason == null ? '' : ': $reason'}',
      createdBy: performedBy,
      visibility: entry.visibility,
      idempotencyKey: 'reverse_$entryId',
      enforceSufficientFunds: false,
    );

    await refs.ledgerEntries(communityId).doc(entryId).update({
      'status': 'reversed',
      'reversedBy': performedBy,
      'reversedAt': FieldValue.serverTimestamp(),
    });

    return reversed;
  }
}
