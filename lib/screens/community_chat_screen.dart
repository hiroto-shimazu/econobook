import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/community.dart';
import 'central_bank_screen.dart';

class CommunityChatScreen extends StatelessWidget {
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
    final membersStream = FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: communityId)
        .orderBy('joinedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'メンバーとトーク',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
                if (docs.isEmpty) {
                  return const Center(child: Text('メンバーがまだいません'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
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
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
                ),
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
          )
        ],
      ),
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
  }
}
