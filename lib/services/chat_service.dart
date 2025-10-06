import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';
import 'firestore_refs.dart';

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
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('message cannot be empty');
    }
    return sendTypedMessage(
      communityId: communityId,
      senderUid: senderUid,
      receiverUid: receiverUid,
      type: ChatMessageType.text,
      text: trimmed,
      previewText: trimmed,
    );
  }

  /// Sends a message with arbitrary [type] and [metadata]. Text may be empty
  /// for system events or ledger notifications.
  Future<void> sendTypedMessage({
    required String communityId,
    required String senderUid,
    required String receiverUid,
    required ChatMessageType type,
    String? text,
    Map<String, dynamic>? metadata,
    String? previewText,
  }) async {
    if (type == ChatMessageType.text) {
      final trimmed = (text ?? '').trim();
      if (trimmed.isEmpty) {
        throw ArgumentError('Text message cannot be empty');
      }
      text = trimmed;
    }

    final threadId = buildThreadId(senderUid, receiverUid);
    final threadRef = _threads(communityId).doc(threadId);
    final messageRef = _messages(communityId, threadId).doc();
    final membershipDocId = FirestoreRefs.membershipId(communityId, senderUid);

    final sanitizedMetadata =
        Map<String, dynamic>.from((metadata ?? const <String, dynamic>{}));

    try {
      await _firestore.runTransaction((transaction) async {
        final threadSnap = await transaction.get(threadRef);
        List<String> participants;

        transaction.set(messageRef, {
          'type': type.name,
          'text': text,
          'metadata': sanitizedMetadata,
          'senderUid': senderUid,
          'receiverUid': receiverUid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        final now = FieldValue.serverTimestamp();
        final unreadCounts = <String, int>{};
        final lastMessagePreview = _buildPreview(
          type: type,
          text: text,
          previewText: previewText,
          metadata: sanitizedMetadata,
        );

        if (threadSnap.exists) {
          final data = threadSnap.data() ?? <String, dynamic>{};
          final existingParticipants = List<String>.from(
            (data['participants'] as List?)?.map((e) => e as String) ??
                const <String>[],
          );
          final participantSet =
              <String>{...existingParticipants, senderUid, receiverUid};
          if (participantSet.length > 2) {
            throw StateError('Conversation threads support up to two participants');
          }
          participants = participantSet.toList()..sort();
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
            'lastMessage': lastMessagePreview,
            'lastSenderUid': senderUid,
            'lastMessageType': type.name,
            'lastMessageMetadata': sanitizedMetadata,
            'unreadCounts': unreadCounts,
          });
        } else {
          participants = [senderUid, receiverUid]..sort();
          for (final uid in participants) {
            unreadCounts[uid] = uid == senderUid ? 0 : 1;
          }

          transaction.set(threadRef, {
            'participants': participants,
            'createdAt': now,
            'updatedAt': now,
            'lastMessage': lastMessagePreview,
            'lastSenderUid': senderUid,
            'lastMessageType': type.name,
            'lastMessageMetadata': sanitizedMetadata,
            'unreadCounts': unreadCounts,
          });
        }
      });
    } on FirebaseException catch (e, stack) {
      if (e.code == 'permission-denied') {
        bool membershipExists = false;
        Object? membershipCheckError;
        try {
          final membershipSnap = await _firestore
              .collection('memberships')
              .doc(membershipDocId)
              .get();
          membershipExists = membershipSnap.exists;
        } catch (error) {
          membershipCheckError = error;
        }
        final message = StringBuffer()
          ..write('permission-denied when writing community_chats/')
          ..write(communityId)
          ..write('/threads/')
          ..write(threadId)
          ..write('/messages/')
          ..write(messageRef.id)
          ..write('; membershipDoc=')
          ..write(membershipDocId)
          ..write(' exists=')
          ..write(membershipExists);
        if (membershipCheckError != null) {
          message
            ..write('; membershipCheckError=')
            ..write(membershipCheckError);
        }
        if (e.message != null && e.message!.isNotEmpty) {
          message
            ..write('; originalMessage=')
            ..write(e.message);
        }
        throw FirebaseException(
          plugin: e.plugin,
          code: e.code,
          message: message.toString(),
          stackTrace: stack ?? e.stackTrace,
        );
      }
      rethrow;
    }
  }

  String _buildPreview({
    required ChatMessageType type,
    String? text,
    String? previewText,
    Map<String, dynamic>? metadata,
  }) {
    if (previewText != null && previewText.trim().isNotEmpty) {
      return previewText.trim();
    }
    switch (type) {
      case ChatMessageType.transfer:
        final amount = metadata?['amount'];
        final currency = metadata?['currency'];
        if (amount != null && currency != null) {
          return '送金 $amount $currency';
        }
        return '送金が行われました';
      case ChatMessageType.request:
        final amount = metadata?['amount'];
        final currency = metadata?['currency'];
        if (amount != null && currency != null) {
          return '請求 $amount $currency';
        }
        return '請求が作成されました';
      case ChatMessageType.split:
        return '割り勘リクエスト';
      case ChatMessageType.task:
        final title = metadata?['title'];
        if (title is String && title.isNotEmpty) {
          return 'タスク: $title';
        }
        return 'タスクが共有されました';
      case ChatMessageType.system:
        return text ?? 'システム通知';
      case ChatMessageType.text:
      default:
        return (text ?? '').trim();
    }
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
