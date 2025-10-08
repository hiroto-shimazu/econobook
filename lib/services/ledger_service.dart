import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_index_link_copy.dart';

import '../constants/community.dart';
import '../utils/error_normalizer.dart';
import '../models/community.dart';
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
    String? entryType,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero');
    }
    if (fromUid == toUid) {
      throw ArgumentError('Cannot transfer to the same user');
    }

  final ledgerEntriesRaw = refs.ledgerEntriesRaw(communityId);
  final ledgerDocRaw = ledgerEntriesRaw.doc();
  final ledgerId = ledgerDocRaw.id;
    final idKey = idempotencyKey ?? ledgerId;
    final idempotencyRef = refs.ledgerIdempotency(communityId).doc(idKey);

    String? existingEntryId;
    final isCentralBankPayer = fromUid == kCentralBankUid;
    final isCentralBankReceiver = toUid == kCentralBankUid;
    if (isCentralBankPayer && isCentralBankReceiver) {
      throw ArgumentError('中央銀行同士の取引は無効です');
    }

    try {
      await refs.raw.runTransaction((tx) async {
        try {
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
          DocumentReference<Membership>? toRef;
          if (!isCentralBankReceiver) {
            toRef = refs.membershipDoc(communityId, toUid);
          }

          if (!isCentralBankReceiver) {
            final toSnap = await tx.get(toRef!);
            if (!toSnap.exists) {
              throw StateError('Recipient is not a member of this community');
            }
          }
          if (!isCentralBankPayer) {
            final fromSnap = await tx.get(fromRef!);
            if (!fromSnap.exists) {
              throw StateError('Sender is not a member of this community');
            }
            final fromBalance = fromSnap.data()?.balance ?? 0;
            final shouldEnforce = !isCentralBankPayer || enforceSufficientFunds;
            if (shouldEnforce && fromBalance < amount) {
              throw StateError('Insufficient balance');
            }
          }

          final communityDoc = refs.communityDoc(communityId);
          if (isCentralBankPayer || isCentralBankReceiver) {
            final communitySnap = await tx.get(communityDoc);
            final treasury = communitySnap.data()?.treasury ??
                const CommunityTreasury(
                  balance: 0,
                  initialGrant: 0,
                  dualApprovalEnabled: false,
                );
            if (isCentralBankPayer && treasury.balance < amount) {
              throw StateError('中央銀行の残高が不足しています');
            }
          }

          if (!isCentralBankPayer) {
            tx.update(fromRef!, {'balance': FieldValue.increment(-amount)});
          }
          if (!isCentralBankReceiver) {
            tx.update(toRef!, {'balance': FieldValue.increment(amount)});
          }

          if (isCentralBankPayer) {
            tx.update(communityDoc, {
              'treasury.balance': FieldValue.increment(-amount),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          if (isCentralBankReceiver) {
            tx.update(communityDoc, {
              'treasury.balance': FieldValue.increment(amount),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

      final resolvedType = entryType ??
        (isCentralBankPayer || isCentralBankReceiver
          ? 'central_bank'
          : 'transfer');
      tx.set(ledgerDocRaw, {
            'cid': communityId,
            'type': resolvedType,
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
        } catch (innerE, innerSt) {
          // If an error occurs inside the transaction callback, convert it
          // immediately to a FirebaseException with context so the message
          // is more likely to survive web boxing and be readable on the
          // client/console.
          final innerCtx = 'recordTransfer(inner) community=$communityId from=$fromUid to=$toUid amount=$amount idempotency=$idKey';
          // Try to normalize for better inner message
          String innerSummary;
          try {
            final normalized = normalizeError(innerE);
            final innerMessage = normalized.message?.trim();
            final innerRaw = normalized.raw?.trim();
            final innerType = normalized.error.runtimeType.toString();
            final pieces = <String>[];
            if (innerMessage != null && innerMessage.isNotEmpty) {
              pieces.add(innerMessage);
            }
            pieces.add('innerType=$innerType');
            if (innerRaw != null && innerRaw.isNotEmpty) {
              const maxLen = 600;
              final snippet = innerRaw.length > maxLen
                  ? innerRaw.substring(0, maxLen) + '…'
                  : innerRaw;
              pieces.add('innerRaw=$snippet');
            }
            innerSummary = pieces.join(' | ');
            // ignore: avoid_print
            print('LedgerService.recordTransfer(inner) normalized raw: $innerRaw');
          } catch (_) {
            innerSummary = innerE.toString();
          }
          // ignore: avoid_print
          print('LedgerService.recordTransfer(inner) failed: $innerCtx; error: $innerSummary\nstack: $innerSt');
          throw FirebaseException(
              plugin: 'econobook',
              message: 'Transfer failed ($innerCtx): $innerSummary\n${innerSt.toString()}');
        }
      });
    } catch (e, st) {
      // Add minimal context so web-boxed errors include actionable info
      final ctx = 'recordTransfer community=$communityId from=$fromUid to=$toUid amount=$amount idempotency=$idKey';
      // Attempt to normalize/unpack boxed JS errors (web) so the thrown
      // FirebaseException message contains the underlying Dart error
      // instead of the generic "Dart exception thrown from converted Future".
      String innerSummary;
      try {
        final normalized = normalizeError(e);
        final innerMessage = normalized.message?.trim();
        final innerRaw = normalized.raw?.trim();
        final innerType = normalized.error.runtimeType.toString();
        final pieces = <String>[];
        if (innerMessage != null && innerMessage.isNotEmpty) {
          pieces.add(innerMessage);
        }
        pieces.add('innerType=$innerType');
        if (innerRaw != null && innerRaw.isNotEmpty) {
          const maxLen = 600;
          final snippet = innerRaw.length > maxLen
              ? innerRaw.substring(0, maxLen) + '…'
              : innerRaw;
          pieces.add('innerRaw=$snippet');
        }
        innerSummary = pieces.join(' | ');
        // Log normalized raw for debugging as well
        // ignore: avoid_print
        print('LedgerService.recordTransfer normalized error: $innerRaw');
      } catch (_) {
        innerSummary = e.toString();
      }

      // Log full details for developers (console/logs) including stack trace
      // Avoid leaking sensitive data in exception messages in production
      // but keep enough context for debugging.
      // ignore: avoid_print
      print('LedgerService.recordTransfer failed: $ctx; error: $innerSummary\nstack: $st');
      // Rethrow a FirebaseException-like error to preserve SDK expectations
      throw FirebaseException(
          plugin: 'econobook',
          message: 'Transfer failed ($ctx): $innerSummary\n${st.toString()}');
    }

    final docId = existingEntryId ?? ledgerId;
  final snap = await withIndexLinkCopyForService(() => refs.ledgerEntries(communityId).doc(docId).get());
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
  final entrySnap = await withIndexLinkCopyForService(() => refs.ledgerEntries(communityId).doc(entryId).get());
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
