import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/community.dart';
import '../services/chat_service.dart';
import 'central_bank_screen.dart';
import 'member_chat_screen.dart';

DateTime? _chatReadTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

int _chatCompareJoinedDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _chatReadTimestamp(a['joinedAt']);
  final bDate = _chatReadTimestamp(b['joinedAt']);
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
String? _formatChatTimestamp(DateTime? time) {
  if (time == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  if (target == today) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  return '${time.month}/${time.day}';
}

class CommunityChatScreen extends StatelessWidget {
=======
String _formatChatTimestamp(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final now = DateTime.now();
  final hours = local.hour.toString().padLeft(2, '0');
  final minutes = local.minute.toString().padLeft(2, '0');
  final time = '$hours:$minutes';
  final isSameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (isSameDay) {
    return time;
  }
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$month/$day $time';
}

class CommunityChatScreen extends StatefulWidget {
>>>>>>> theirs
=======
class CommunityChatScreen extends StatelessWidget {
>>>>>>> theirs
=======
class CommunityChatScreen extends StatelessWidget {
>>>>>>> theirs
=======
class CommunityChatScreen extends StatelessWidget {
>>>>>>> theirs
=======
class CommunityChatScreen extends StatelessWidget {
>>>>>>> theirs
  const CommunityChatScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.user,
  });

  final String communityId;
  final String communityName;
  final User user;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required User user,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityChatScreen(
          communityId: communityId,
          communityName: communityName,
          user: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
=======
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
    final membersStream = FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: communityId)
        .snapshots();

<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
    final threadsStream = FirebaseFirestore.instance
        .collection('community_chats')
        .doc(communityId)
        .collection('threads')
        .where('participants', arrayContains: user.uid)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
=======
    return DefaultTabController(
      length: 2,
      child: Scaffold(
>>>>>>> theirs
=======
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
>>>>>>> theirs
=======
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
>>>>>>> theirs
=======
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
>>>>>>> theirs
=======
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
>>>>>>> theirs
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          communityName,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'ウォレットで中央銀行を開く',
            icon: const Icon(Icons.account_balance, color: Colors.black87),
            onPressed: () {
              CentralBankScreen.open(
                context,
                communityId: communityId,
                communityName: communityName,
                user: user,
              );
            },
          )
        ],
      ),
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: membersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('メンバーを取得できませんでした: ${snapshot.error}'),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          final members = docs
              .map((doc) => doc.data())
              .where((data) {
                final uid = data['uid'];
                if (uid is! String || uid.isEmpty) return false;
                if (uid == user.uid) return false;
                if (uid == kCentralBankUid) return false;
                return true;
              })
              .toList();

          if (members.isEmpty) {
            return const Center(child: Text('他のメンバーがまだいません'));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: threadsStream,
            builder: (context, threadsSnap) {
              final threadDocs = threadsSnap.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final previews = <String, _ThreadPreview>{};
              for (final doc in threadDocs) {
                final data = doc.data();
                final participants = List<String>.from(
                    (data['participants'] as List?) ?? const <String>[]);
                final otherUid = participants.firstWhere(
                  (uid) => uid != user.uid,
                  orElse: () => '',
                );
                if (otherUid.isEmpty) continue;
                final updatedAt = _chatReadTimestamp(data['updatedAt']);
                final unreadMap = Map<String, dynamic>.from(
                    (data['unreadCounts'] as Map?) ?? const {});
                final unreadRaw = unreadMap[user.uid];
                final unreadCount = unreadRaw is num ? unreadRaw.toInt() : 0;
                previews[otherUid] = _ThreadPreview(
                  id: doc.id,
                  lastMessage: (data['lastMessage'] as String?)?.trim(),
                  lastSenderUid: (data['lastSenderUid'] as String?) ?? '',
                  updatedAt: updatedAt,
                  unreadCount: unreadCount,
                );
              }

              members.sort((a, b) {
                final uidA = a['uid'] as String?;
                final uidB = b['uid'] as String?;
                final threadA = uidA == null ? null : previews[uidA];
                final threadB = uidB == null ? null : previews[uidB];
                if (threadA != null && threadB != null) {
                  final timeA = threadA.updatedAt;
                  final timeB = threadB.updatedAt;
                  if (timeA != null && timeB != null) {
                    return timeB.compareTo(timeA);
                  }
                  if (timeA != null) return -1;
                  if (timeB != null) return 1;
                }
                if (threadA != null) return -1;
                if (threadB != null) return 1;
                return _chatCompareJoinedDesc(a, b);
              });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'メンバーとトーク',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'メンバー一覧から選択して個別チャットを開始できます。',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final data = members[index];
                        final uid = data['uid'] as String? ?? '';
                        final role = (data['role'] as String?) ?? 'member';
                        final thread = previews[uid];
                        final threadId = ChatService.buildThreadId(user.uid, uid);
                        return _MemberChatTile(
                          communityId: communityId,
                          communityName: communityName,
                          currentUser: user,
                          memberUid: uid,
                          memberRole: role,
                          threadId: thread?.id ?? threadId,
                          threadPreview: thread,
                        );
                      },
=======
    );
  }

  Widget _buildMembersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'メンバー',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
=======
=======
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'メンバーとトーク',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'メンバーを選択してチャットを開始します。チャット機能は近日アップデート予定です。',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: membersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('メンバーを取得できませんでした: ${snapshot.error}'),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                final sortedDocs = docs.toList()
                  ..sort((a, b) => _chatCompareJoinedDesc(a.data(), b.data()));
                if (sortedDocs.isEmpty) {
                  return const Center(child: Text('メンバーがまだいません'));
                }
                return ListView.builder(
                  itemCount: sortedDocs.length,
                  itemBuilder: (context, index) {
                    final data = sortedDocs[index].data();
                    final uid = (data['uid'] as String?) ?? 'unknown';
                    final role = (data['role'] as String?) ?? 'member';
                    final displayName = uid == user.uid ? 'あなた' : uid;
                    final isCentralBank = uid == kCentralBankUid;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          displayName.characters.first.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(_roleLabel(role, isCentralBank)),
                      trailing: const Icon(Icons.chat_bubble_outline),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$displayName とのチャットは準備中です'),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x11000000))),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: 'メッセージ機能は準備中です',
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
>>>>>>> theirs
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ThreadPreview {
  const _ThreadPreview({
    required this.id,
    this.lastMessage,
    required this.lastSenderUid,
    this.updatedAt,
    required this.unreadCount,
  });

  final String id;
  final String? lastMessage;
  final String lastSenderUid;
  final DateTime? updatedAt;
  final int unreadCount;
}

class _MemberChatTile extends StatelessWidget {
  const _MemberChatTile({
    required this.communityId,
    required this.communityName,
    required this.currentUser,
    required this.memberUid,
    required this.memberRole,
    required this.threadId,
    this.threadPreview,
  });

  final String communityId;
  final String communityName;
  final User currentUser;
  final String memberUid;
  final String memberRole;
  final String threadId;
  final _ThreadPreview? threadPreview;

  @override
  Widget build(BuildContext context) {
    final userDocStream = FirebaseFirestore.instance
        .doc('users/$memberUid')
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final rawName = (data?['displayName'] as String?)?.trim();
        final displayName =
            rawName != null && rawName.isNotEmpty ? rawName : memberUid;
        final photoUrl = (data?['photoUrl'] as String?)?.trim();
        final lastMessage = threadPreview?.lastMessage;
        final lastSender = threadPreview?.lastSenderUid;
        final previewText = (lastMessage == null || lastMessage.isEmpty)
            ? 'メッセージはまだありません'
            : (lastSender == currentUser.uid
                ? 'あなた: $lastMessage'
                : lastMessage);
        final timeLabel =
            _formatChatTimestamp(threadPreview?.updatedAt) ?? '';
        final unreadCount = threadPreview?.unreadCount ?? 0;

        return ListTile(
          leading: _MemberAvatar(name: displayName, photoUrl: photoUrl),
          title: Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            previewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeLabel.isNotEmpty)
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
<<<<<<< ours
              if (unreadCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
=======
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
>>>>>>> theirs
=======
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
>>>>>>> theirs
=======
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
>>>>>>> theirs
=======
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
>>>>>>> theirs
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: () {
            MemberChatScreen.open(
              context,
              communityId: communityId,
              communityName: communityName,
              currentUser: currentUser,
              partnerUid: memberUid,
              partnerDisplayName: displayName,
              partnerPhotoUrl: photoUrl,
              threadId: threadId,
              memberRole: memberRole,
            );
          },
        );
      },
=======
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'メッセージを送信',
                  icon: const Icon(Icons.send, color: Colors.grey),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('チャット機能は開発中です')),
                    );
                  },
                ),
              ],
            ),
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
          ),
        )
      ],
>>>>>>> theirs
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

<<<<<<< ours
  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return CircleAvatar(
      backgroundColor: Colors.blue.shade100,
      backgroundImage:
          photoUrl == null || photoUrl!.isEmpty ? null : NetworkImage(photoUrl!),
      child: photoUrl == null || photoUrl!.isEmpty
          ? Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          : null,
    );
=======
  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メッセージを入力してください')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection('community_chats')
          .doc(widget.communityId)
          .collection('messages')
          .add({
        'cid': widget.communityId,
        'senderUid': widget.user.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollToLatest();
    }
  }

  void _scrollToLatest() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    _messagesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
=======
          )
        ],
      ),
>>>>>>> theirs
=======
          )
        ],
      ),
>>>>>>> theirs
=======
          )
        ],
      ),
>>>>>>> theirs
=======
          )
        ],
      ),
>>>>>>> theirs
    );
  }

  static String _roleLabel(String role, bool isCentralBank) {
    if (isCentralBank) return '中央銀行';
    return switch (role) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
>>>>>>> theirs
  }
}
