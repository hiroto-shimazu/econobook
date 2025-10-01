// lib/dev/dev_seed.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Emulator/開発用にダミーデータを投入
Future<void> seedDevData(String communityId) async {
  final fs = FirebaseFirestore.instance;

  // communities
  await fs.collection('communities').doc(communityId).set({
    'name': 'EconoBook Dev',
    'currency': {'code': 'PTS', 'name': 'ポイント', 'allowMinting': true},
    'policy': {'requiresApproval': true},
    'visibility': {'balanceMode': 'private'},
    'treasury': {'balance': 120000, 'initialGrant': 100000},
  }, SetOptions(merge: true));

  // users
  final users = {
    'dev_alice': {
      'displayName': 'アリス',
      'minor': false,
      'completionRate': 95,
      'disputeRate': 2,
    },
    'dev_bob': {
      'displayName': 'ボブ',
      'minor': false,
      'completionRate': 88,
      'disputeRate': 4,
    },
    'dev_minor': {
      'displayName': 'ミノル',
      'minor': true,
      'completionRate': 70,
      'disputeRate': 1,
    },
  };
  for (final e in users.entries) {
    await fs.collection('users').doc(e.key).set(e.value, SetOptions(merge: true));
  }

  // memberships（承認待ちも混ぜる）
  Future<void> addMember(String uid, {bool bank = false, num bal = 0, bool pending = false}) {
    return fs.collection('memberships').add({
      'cid': communityId,
      'communityId': communityId,
      'userId': uid,
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': bal,
      'canManageBank': bank,
      'status': pending ? 'pending' : 'active',
      'role': bank ? 'admin' : 'member',
      'pending': pending,
    });
  }

  await addMember('dev_alice', bank: true, bal: 25800);
  await addMember('dev_bob', bal: 950);
  await addMember('dev_minor', pending: true, bal: 0);
}

/// 追加の承認待ちメンバーをN件作る（動線検証用）
Future<void> addPendingMembers(String communityId, {int count = 3}) async {
  final fs = FirebaseFirestore.instance;
  for (int i = 0; i < count; i++) {
    await fs.collection('memberships').add({
      'cid': communityId,
      'communityId': communityId,
      'userId': 'dev_pending_$i',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0,
      'canManageBank': false,
      'status': 'pending',
      'pending': true,
      'role': 'pending',
    });
  }
}
