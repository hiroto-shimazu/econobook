import 'package:cloud_firestore/cloud_firestore.dart';

/// Service responsible for direct member-to-member chat handling within a
/// community.
class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Generates a deterministic thread id for a pair of users.
  static String buildThreadId(String uidA, String uidB) {
    final pair = [uidA, uidB]..sort();
    return pair.join('_');
  }

  CollectionReference<Map<String, dynamic>> _threads(String communityId) {
    return _firestore
        .collection('community_chats')
        .doc(communityId)
        .collection('threads');
  }

  CollectionReference<Map<String, dynamic>> _messages(
      String communityId, String threadId) {
    return _threads(communityId).doc(threadId).collection('messages');
  }

  /// Sends a chat [message] from [senderUid] to [receiverUid] within the
  /// specified [communityId].
  Future<void> sendMessage({
    required String communityId,
    required String senderUid,
    required String receiverUid,
    required String message,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('message cannot be empty');
    }

    final threadId = buildThreadId(senderUid, receiverUid);
    final threadRef = _threads(communityId).doc(threadId);
    final messageRef = _messages(communityId, threadId).doc();
    final participants = [senderUid, receiverUid]..sort();

    await _firestore.runTransaction((transaction) async {
      final threadSnap = await transaction.get(threadRef);

      transaction.set(messageRef, {
        'text': trimmed,
        'senderUid': senderUid,
        'receiverUid': receiverUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final now = FieldValue.serverTimestamp();
      final unreadCounts = <String, int>{};

      if (threadSnap.exists) {
        final data = threadSnap.data() ?? <String, dynamic>{};
        final existingUnread = Map<String, dynamic>.from(
            (data['unreadCounts'] as Map?) ?? const <String, dynamic>{});

        for (final uid in participants) {
          final currentValue = existingUnread[uid];
          final currentCount = currentValue is num ? currentValue.toInt() : 0;
          if (uid == senderUid) {
            unreadCounts[uid] = 0;
          } else {
            unreadCounts[uid] = currentCount + 1;
          }
        }

        transaction.update(threadRef, {
          'participants': participants,
          'updatedAt': now,
          'lastMessage': trimmed,
          'lastSenderUid': senderUid,
          'unreadCounts': unreadCounts,
        });
      } else {
        for (final uid in participants) {
          unreadCounts[uid] = uid == senderUid ? 0 : 1;
        }

        transaction.set(threadRef, {
          'participants': participants,
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': trimmed,
          'lastSenderUid': senderUid,
          'unreadCounts': unreadCounts,
        });
      }
    });
  }

  /// Marks a thread as read for [userUid] by clearing the unread counter.
  Future<void> markThreadAsRead({
    required String communityId,
    required String threadId,
    required String userUid,
  }) async {
    final threadRef = _threads(communityId).doc(threadId);
    await threadRef.set({
      'unreadCounts': {userUid: 0},
      'readAt': {userUid: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  /// Stream of messages ordered by creation time ascending.
  Stream<QuerySnapshot<Map<String, dynamic>>> messageStream({
    required String communityId,
    required String threadId,
  }) {
    return _messages(communityId, threadId)
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  /// Stream of a thread document containing metadata such as unread counts.
  Stream<DocumentSnapshot<Map<String, dynamic>>> threadStream({
    required String communityId,
    required String threadId,
  }) {
    return _threads(communityId).doc(threadId).snapshots();
  }
}
