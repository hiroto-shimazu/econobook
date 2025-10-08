import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/budget.dart';
import '../models/community.dart';
import '../models/community_post.dart';
import '../models/community_task.dart';
import '../models/ledger_entry.dart';
import '../models/membership.dart';
import '../models/payment_request.dart';

/// Centralized Firestore references with converters for typed access.
class FirestoreRefs {
  FirestoreRefs(this._firestore);

  final FirebaseFirestore _firestore;

  FirebaseFirestore get raw => _firestore;

  CollectionReference<AppUser> users() =>
      _firestore.collection('users').withConverter<AppUser>(
            fromFirestore: (snap, _) => AppUser.fromSnapshot(snap),
            toFirestore: (obj, _) => obj.toMap(),
          );

  CollectionReference<Community> communities() =>
      _firestore.collection('communities').withConverter<Community>(
            fromFirestore: (snap, _) => Community.fromSnapshot(snap),
            toFirestore: (obj, _) => obj.toMap(),
          );

  DocumentReference<Community> communityDoc(String communityId) =>
      communities().doc(communityId);

  CollectionReference<Membership> memberships() =>
      _firestore.collection('memberships').withConverter<Membership>(
            fromFirestore: (snap, _) => Membership.fromSnapshot(snap),
            toFirestore: (obj, _) => obj.toMap(),
          );

  DocumentReference<Membership> membershipDoc(
          String communityId, String userId) =>
      memberships().doc(_membershipId(communityId, userId));

  CollectionReference<LedgerEntry> ledgerEntries(String communityId) =>
      _firestore
          .collection('ledger')
          .doc(communityId)
          .collection('entries')
          .withConverter<LedgerEntry>(
            fromFirestore: (snap, _) => LedgerEntry.fromSnapshot(snap),
            toFirestore: (obj, _) => obj.toMap(),
          );

  CollectionReference<Map<String, dynamic>> ledgerEntriesRaw(
          String communityId) =>
      _firestore
          .collection('ledger')
          .doc(communityId)
          .collection('entries');

  CollectionReference<Map<String, dynamic>> ledgerIdempotency(
          String communityId) =>
      _firestore
          .collection('ledger')
          .doc(communityId)
          .collection('idempotency');

  CollectionReference<PaymentRequest> paymentRequests(String communityId) =>
      _firestore
          .collection('requests')
          .doc(communityId)
          .collection('items')
          .withConverter<PaymentRequest>(
            fromFirestore: (snap, _) => PaymentRequest.fromSnapshot(snap),
            toFirestore: (obj, _) => obj.toMap(),
          );

  CollectionReference<CommunityTask> tasks(String communityId) => _firestore
      .collection('tasks')
      .doc(communityId)
      .collection('items')
      .withConverter<CommunityTask>(
        fromFirestore: (snap, _) => CommunityTask.fromSnapshot(snap),
        toFirestore: (obj, _) => obj.toMap(),
      );

  /// Raw (Map-based) tasks collection reference (no converter).
  CollectionReference<Map<String, dynamic>> tasksRaw(String communityId) =>
      _firestore.collection('tasks').doc(communityId).collection('items');

  CollectionReference<Map<String, dynamic>> bankSettingRequests(
          String communityId) =>
      _firestore
          .collection('bank_setting_requests')
          .doc(communityId)
          .collection('items');

  CollectionReference<CommunityPost> posts(String communityId) => _firestore
      .collection('news')
      .doc(communityId)
      .collection('posts')
      .withConverter<CommunityPost>(
        fromFirestore: (snap, _) => CommunityPost.fromSnapshot(snap),
        toFirestore: (obj, _) => obj.toMap(),
      );

  CollectionReference<Budget> budgets(String communityId) => _firestore
      .collection('budgets')
      .doc(communityId)
      .collection('items')
      .withConverter<Budget>(
        fromFirestore: (snap, _) => Budget.fromSnapshot(snap),
        toFirestore: (obj, _) => obj.toMap(),
      );

  /// Public deterministic membership doc id, matching `memberships/{cid_uid}` pattern.
  static String membershipId(String communityId, String userId) =>
      '${communityId}_$userId';

  /// Deterministic membership doc id, matching `memberships/{cid_uid}` pattern.
  static String _membershipId(String communityId, String userId) =>
      '${communityId}_$userId';
}
