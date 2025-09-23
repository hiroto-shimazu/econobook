import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';

class MemberChatScreen extends StatefulWidget {
  const MemberChatScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.currentUser,
    required this.partnerUid,
    required this.partnerDisplayName,
    required this.threadId,
    this.partnerPhotoUrl,
    required this.memberRole,
  });

  final String communityId;
  final String communityName;
  final User currentUser;
  final String partnerUid;
  final String partnerDisplayName;
  final String threadId;
  final String? partnerPhotoUrl;
  final String memberRole;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required User currentUser,
    required String partnerUid,
    required String partnerDisplayName,
    required String threadId,
    String? partnerPhotoUrl,
    required String memberRole,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberChatScreen(
          communityId: communityId,
          communityName: communityName,
          currentUser: currentUser,
          partnerUid: partnerUid,
          partnerDisplayName: partnerDisplayName,
          partnerPhotoUrl: partnerPhotoUrl,
          threadId: threadId,
          memberRole: memberRole,
        ),
      ),
    );
  }

  @override
  State<MemberChatScreen> createState() => _MemberChatScreenState();
}

class _MemberChatScreenState extends State<MemberChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;
  bool _markingRead = false;

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _threadStream =>
      _chatService.threadStream(
        communityId: widget.communityId,
        threadId: widget.threadId,
      );

  Stream<QuerySnapshot<Map<String, dynamic>>> get _messagesStream =>
      _chatService.messageStream(
        communityId: widget.communityId,
        threadId: widget.threadId,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _markAsRead() async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await _chatService.markThreadAsRead(
        communityId: widget.communityId,
        threadId: widget.threadId,
        userUid: widget.currentUser.uid,
      );
    } catch (_) {
      // ignore errors for marking read
    } finally {
      _markingRead = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await _chatService.sendMessage(
        communityId: widget.communityId,
        senderUid: widget.currentUser.uid,
        receiverUid: widget.partnerUid,
        message: text,
      );
      _messageCtrl.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(widget.memberRole);
    final threadStream = _threadStream;
    final messagesStream = _messagesStream;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blueGrey.shade100,
              backgroundImage: widget.partnerPhotoUrl == null ||
                      widget.partnerPhotoUrl!.isEmpty
                  ? null
                  : NetworkImage(widget.partnerPhotoUrl!),
              child: widget.partnerPhotoUrl == null ||
                      widget.partnerPhotoUrl!.isEmpty
                  ? Text(
                      widget.partnerDisplayName
                          .characters
                          .first
                          .toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.partnerDisplayName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$roleLabel・${widget.communityName}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: threadStream,
        builder: (context, threadSnapshot) {
          final threadData = threadSnapshot.data?.data();
          final unreadMap = threadData == null
              ? const <String, dynamic>{}
              : Map<String, dynamic>.from(
                  (threadData['unreadCounts'] as Map?) ?? const {},
                );
          final unreadRaw = unreadMap[widget.currentUser.uid];
          final unreadCount = unreadRaw is num ? unreadRaw.toInt() : 0;
          if (threadSnapshot.data?.exists == true && unreadCount > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
          }

          return Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '${widget.partnerDisplayName}とのメッセージはまだありません。最初のメッセージを送ってみましょう。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final message = docs[index].data();
                        final sender = message['senderUid'] as String? ?? '';
                        final text = (message['text'] as String?) ?? '';
                        final createdAt =
                            _chatReadTimestamp(message['createdAt']);
                        final isMe = sender == widget.currentUser.uid;
                        return _MessageBubble(
                          text: text,
                          isMe: isMe,
                          createdAt: createdAt,
                        );
                      },
                    );
                  },
                ),
              ),
              _MessageInputBar(
                controller: _messageCtrl,
                sending: _sending,
                onSend: _sendMessage,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageInputBar extends StatelessWidget {
  const _MessageInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'メッセージを入力',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              onPressed: sending ? null : onSend,
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.createdAt,
  });

  final String text;
  final bool isMe;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final alignment =
        isMe ? Alignment.centerRight : Alignment.centerLeft;
    final backgroundColor =
        isMe ? const Color(0xFF4C7DFF) : Colors.grey.shade200;
    final textColor = isMe ? Colors.white : Colors.black87;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );
    final timeLabel = _formatMessageTime(createdAt);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(text, style: TextStyle(color: textColor)),
              if (timeLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

DateTime? _chatReadTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String _roleLabel(String role) {
  return switch (role) {
    'owner' => 'オーナー',
    'admin' => '管理者',
    'mediator' => '仲介',
    'pending' => '承認待ち',
    _ => 'メンバー',
  };
}

String? _formatMessageTime(DateTime? time) {
  if (time == null) return null;
  final hours = time.hour.toString().padLeft(2, '0');
  final minutes = time.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}
