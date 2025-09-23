import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/community.dart';
import '../models/community.dart';
import '../models/membership.dart';
import 'firestore_refs.dart';
import 'ledger_service.dart';

class CommunityService {
  CommunityService({FirebaseFirestore? firestore})
      : refs = FirestoreRefs(firestore ?? FirebaseFirestore.instance);

  final FirestoreRefs refs;

  /// Creates a community with the given parameters and registers the owner membership.
  Future<Community> createCommunity({
    required String name,
    required String symbol,
    required String ownerUid,
    bool discoverable = true,
    String? description,
    String? coverUrl,
    CommunityCurrency? currency,
    CommunityPolicy? policy,
    CommunityVisibility? visibility,
    CommunityTreasury? treasury,
  }) async {
    final firestore = refs.raw;
    // Use raw doc so we can set server timestamps in a single batch.
    final communityRef = firestore.collection('communities').doc();
    final generatedInvite = _generateInviteCode();
    final timestamp = FieldValue.serverTimestamp();

    final community = Community(
      id: communityRef.id,
      name: name,
      symbol: symbol,
      description: description,
      coverUrl: coverUrl,
      discoverable: discoverable,
      ownerUid: ownerUid,
      adminUids: [ownerUid],
      membersCount: 1,
      inviteCode: generatedInvite,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      currency: currency ??
          const CommunityCurrency(
            name: 'Community Points',
            code: 'PTS',
            precision: 2,
            supplyModel: 'unlimited',
            txFeeBps: 0,
            expireDays: null,
            creditLimit: 0,
            interestBps: 0,
            maxSupply: null,
            allowMinting: true,
            borrowLimitPerMember: null,
          ),
      policy: policy ??
          const CommunityPolicy(
            enableRequests: true,
            enableSplitBill: true,
            enableTasks: true,
            enableMediation: false,
            minorsRequireGuardian: true,
            postVisibilityDefault: 'community',
            requiresApproval: false,
          ),
      visibility: visibility ?? const CommunityVisibility(balanceMode: 'private'),
      treasury: treasury ?? const CommunityTreasury(balance: 0, initialGrant: 0),
    );

    final membership = Membership(
      id: FirestoreRefs.membershipId(communityRef.id, ownerUid),
      communityId: communityRef.id,
      userId: ownerUid,
      role: 'owner',
      balance: 0,
      joinedAt: DateTime.now(),
      pending: false,
      lastStatementAt: null,
      monthlySummary: const {},
      canManageBank: true,
      balanceVisible: true,
    );

    final batch = firestore.batch();
    batch.set(communityRef, {
      ...community.toMap(),
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
    final membershipRef = firestore
        .collection('memberships')
        .doc(FirestoreRefs.membershipId(communityRef.id, ownerUid));
    batch.set(membershipRef, {
      'cid': communityRef.id,
      'uid': ownerUid,
      'role': 'owner',
      'balance': 0,
      'joinedAt': timestamp,
      'pending': false,
      'monthlySummary': const <String, dynamic>{},
      'canManageBank': true,
      'balanceVisible': true,
    });

    await batch.commit();

    return community;
  }

  /// Join a community using invite code or explicit community id.
  /// Returns true when immediately joined, false when approval request created.
  Future<bool> joinCommunity({
    required String userId,
    String? inviteCode,
    String? communityId,
    bool requireApproval = false,
    bool ignoreApprovalPolicy = false,
  }) async {
    final normalizedInvite = inviteCode?.trim().toUpperCase();
    final normalizedCommunityId = communityId?.trim();

    assert(normalizedInvite != null || normalizedCommunityId != null,
        'Either inviteCode or communityId is required');

    final query = normalizedInvite == null
        ? refs.communityDoc(normalizedCommunityId!).get()
        : refs
            .communities()
            .where('inviteCode', isEqualTo: normalizedInvite)
            .limit(1)
            .get();

    final snap = await query;
    final Community community;
    if (snap is DocumentSnapshot<Community>) {
      final doc = snap;
      if (!doc.exists) {
        throw StateError('Community not found');
      }
      community = doc.data()!;
    } else if (snap is QuerySnapshot<Community>) {
      if (snap.docs.isEmpty) {
        throw StateError('Invite code not found');
      }
      community = snap.docs.first.data();
    } else {
      throw StateError('Unexpected Firestore response');
    }

    final memberRef = refs.raw
        .collection('memberships')
        .doc(FirestoreRefs.membershipId(community.id, userId));
    final existing = await memberRef.get();
    if (existing.exists) {
      // Already joined. respect pending flag.
      return true;
    }

    final approvalRequired = !ignoreApprovalPolicy &&
        (community.policy.requiresApproval || requireApproval);
    if (approvalRequired) {
      await _createJoinRequest(community.id, userId);
      return false;
    }

    final batch = refs.raw.batch();
    final initialGrant = community.treasury.initialGrant;
    num memberInitialBalance = 0;
    DocumentReference<Map<String, dynamic>>? treasuryRef;
    if (initialGrant > 0) {
      treasuryRef = refs.raw.collection('communities').doc(community.id);
      batch.update(treasuryRef, {
        'treasury.balance': FieldValue.increment(-initialGrant),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      memberInitialBalance = initialGrant;
    }

    batch.set(memberRef, {
      'cid': community.id,
      'uid': userId,
      'role': 'member',
      'balance': memberInitialBalance,
      'pending': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'monthlySummary': const <String, dynamic>{},
      'canManageBank': false,
      'balanceVisible': community.visibility.balanceMode == 'everyone',
    });
    final communityDoc = refs.raw.collection('communities').doc(community.id);
    batch.update(communityDoc, {
      'membersCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return true;
  }

  Future<void> approveJoinRequest({
    required String communityId,
    required String requesterUid,
    required String approvedBy,
  }) async {
    final requestRef = refs.raw
        .collection('join_requests')
        .doc(communityId)
        .collection('items')
        .doc(requesterUid);

    await refs.raw.runTransaction((tx) async {
      final reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists) {
        throw StateError('Join request not found');
      }

      final membershipRef = refs.raw
          .collection('memberships')
          .doc(FirestoreRefs.membershipId(communityId, requesterUid));
      final membershipSnap = await tx.get(membershipRef);
      if (membershipSnap.exists) {
        tx.delete(requestRef);
        return;
      }
      tx.set(membershipRef, {
        'cid': communityId,
        'uid': requesterUid,
        'role': 'member',
        'balance': 0,
        'pending': false,
        'joinedAt': FieldValue.serverTimestamp(),
        'approvedBy': approvedBy,
        'monthlySummary': const <String, dynamic>{},
        'canManageBank': false,
      });

      final communityDoc = refs.raw.collection('communities').doc(communityId);
      tx.update(communityDoc, {
        'membersCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.delete(requestRef);
    });
  }

  Future<void> rejectJoinRequest({
    required String communityId,
    required String requesterUid,
  }) async {
    final requestRef = refs.raw
        .collection('join_requests')
        .doc(communityId)
        .collection('items')
        .doc(requesterUid);
    final data = await requestRef.get();
    if (!data.exists) return;
    await requestRef.delete();
  }

  Future<void> setBankManagementPermission({
    required String communityId,
    required String targetUid,
    required bool enabled,
    required String updatedBy,
  }) async {
    final updaterSnap = await refs.membershipDoc(communityId, updatedBy).get();
    final updater = updaterSnap.data();
    if (updater == null || updater.role != 'owner') {
      throw StateError('権限を変更できるのはコミュニティ作成者のみです');
    }
    if (targetUid == updatedBy && !enabled) {
      throw StateError('コミュニティ作成者の権限は無効化できません');
    }

    final targetRef = refs.membershipDoc(communityId, targetUid);
    final targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw StateError('メンバーが見つかりません');
    }

    await targetRef.update({
      'canManageBank': enabled,
      'bankPermissionUpdatedAt': FieldValue.serverTimestamp(),
      'bankPermissionUpdatedBy': updatedBy,
    });
  }

  Future<void> submitBankSettingRequest({
    required String communityId,
    required String requesterUid,
    String? message,
  }) async {
    final membershipSnap =
        await refs.membershipDoc(communityId, requesterUid).get();
    if (!membershipSnap.exists) {
      throw StateError('コミュニティメンバーのみリクエストできます');
    }

    final requests = refs.bankSettingRequests(communityId);
    await requests.add({
      'cid': communityId,
      'requesterUid': requesterUid,
      'message': message,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveBankSettingRequest({
    required String communityId,
    required String requestId,
    required String resolvedBy,
    required bool approved,
  }) async {
    final resolverSnap =
        await refs.membershipDoc(communityId, resolvedBy).get();
    final resolver = resolverSnap.data();
    if (resolver == null ||
        (resolver.role != 'owner' && resolver.canManageBank != true)) {
      throw StateError('設定を操作できるメンバーのみ処理できます');
    }

    final requestRef = refs.bankSettingRequests(communityId).doc(requestId);
    final requestSnap = await requestRef.get();
    if (!requestSnap.exists) {
      throw StateError('リクエストが見つかりません');
    }

    await requestRef.update({
      'status': approved ? 'approved' : 'rejected',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': resolvedBy,
    });
  }

  Future<void> _createJoinRequest(String communityId, String userId) async {
    final joinRef = refs.raw
        .collection('join_requests')
        .doc(communityId)
        .collection('items')
        .doc(userId);
    final existing = await joinRef.get();
    if (existing.exists) {
      return;
    }
    await joinRef.set({
      'cid': communityId,
      'uid': userId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePolicy({
    required String communityId,
    CommunityPolicy? policy,
    CommunityCurrency? currency,
  }) async {
    final data = <String, Object?>{};
    if (policy != null) {
      data['policy'] = policy.toMap();
    }
    if (currency != null) {
      data['currency'] = currency.toMap();
    }
    if (data.isEmpty) return;
    data['updatedAt'] = FieldValue.serverTimestamp();
    await refs.communityDoc(communityId).update(data);
  }

  Future<void> updateCurrencyAndPolicy({
    required String communityId,
    required CommunityCurrency currency,
    CommunityPolicy? policy,
  }) async {
    final data = <String, Object?>{
      'currency': currency.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (policy != null) {
      data['policy'] = policy.toMap();
    }
    await refs.communityDoc(communityId).update(data);
  }

  Future<Membership?> fetchMembership(String communityId, String userId) async {
    final snap = await refs.membershipDoc(communityId, userId).get();
    return snap.data();
  }

  Future<void> ensureMemberExists(String communityId, String userId) async {
    final doc = await refs.membershipDoc(communityId, userId).get();
    if (!doc.exists) {
      throw StateError('User $userId is not part of community $communityId');
    }
  }

  String _generateInviteCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<void> updateVisibilitySettings({
    required String communityId,
    required CommunityVisibility visibility,
  }) async {
    await refs.communityDoc(communityId).update({
      'visibility': visibility.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final members = await refs.raw
        .collection('memberships')
        .where('cid', isEqualTo: communityId)
        .get();
    final batch = refs.raw.batch();
    for (final doc in members.docs) {
      final visible = switch (visibility.balanceMode) {
        'everyone' => true,
        'private' => false,
        'custom' => visibility.customMembers.contains(doc['uid']),
        _ => false,
      };
      batch.update(doc.reference, {'balanceVisible': visible});
    }
    await batch.commit();
  }

  Future<void> setMemberBalanceVisibility({
    required String communityId,
    required String memberUid,
    required bool visible,
  }) async {
    final communityDoc = refs.communityDoc(communityId);
    await refs.raw.runTransaction((tx) async {
      final communitySnap = await tx.get(communityDoc);
      final community = communitySnap.data();
      final visibility = community?.visibility ??
          const CommunityVisibility(balanceMode: 'private');
      final updated = Set<String>.from(visibility.customMembers);
      if (visible) {
        updated.add(memberUid);
      } else {
        updated.remove(memberUid);
      }
      tx.update(communityDoc, {
        'visibility.customMembers': updated.toList(),
        'visibility.balanceMode': 'custom',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final memberRef = refs.raw
          .collection('memberships')
          .doc(FirestoreRefs.membershipId(communityId, memberUid));
      tx.update(memberRef, {'balanceVisible': visible});
    });
  }

  Future<void> updateTreasurySettings({
    required String communityId,
    num? initialGrant,
  }) async {
    final updates = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (initialGrant != null) {
      updates['treasury.initialGrant'] = initialGrant;
    }
    if (updates.length > 1) {
      await refs.communityDoc(communityId).update(updates);
    }
  }

  Future<void> adjustTreasuryBalance({
    required String communityId,
    required num delta,
  }) async {
    final doc = await refs.communityDoc(communityId).get();
    final data = doc.data();
    final current = data?.treasury.balance ?? 0;
    final next = current + delta;
    if (next < 0) {
      throw StateError('中央銀行の残高が不足しています');
    }
    await refs.communityDoc(communityId).update({
      'treasury.balance': FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createLoan({
    required String communityId,
    required String borrowerUid,
    required num amount,
    String? memo,
    required LedgerService ledger,
    required String createdBy,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive');
    }

    final loanRef = refs.raw
        .collection('loans')
        .doc(communityId)
        .collection('items')
        .doc();

    await refs.raw.runTransaction((tx) async {
      final communityDoc = refs.communityDoc(communityId);
      final snap = await tx.get(communityDoc);
      final community = snap.data();
      final balance = community?.treasury.balance ?? 0;
      if (balance < amount) {
        throw StateError('中央銀行の残高が不足しています');
      }
      tx.update(communityDoc, {
        'treasury.balance': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(loanRef, {
        'cid': communityId,
        'borrowerUid': borrowerUid,
        'amount': amount,
        'memo': memo,
        'status': 'pending_transfer',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
      });
    });

    final entry = await ledger.recordTransfer(
      communityId: communityId,
      fromUid: kCentralBankUid,
      toUid: borrowerUid,
      amount: amount,
      memo: memo ?? '中央銀行貸出',
      createdBy: createdBy,
    );

    await loanRef.update({'status': 'active', 'ledgerEntryId': entry.id});
  }
}
