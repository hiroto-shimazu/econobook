import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommunityActivityScreen extends StatelessWidget {
  const CommunityActivityScreen({
    super.key,
    required this.communityId,
    required this.symbol,
    required this.user,
  });

  final String communityId;
  final String symbol;
  final User user;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required String symbol,
    required User user,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityActivityScreen(
          communityId: communityId,
          symbol: symbol,
          user: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('ledger')
        .doc(communityId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('取引履歴'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('履歴を取得できませんでした: ${snapshot.error}'),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('取引履歴はまだありません')); 
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final type = data['type'] as String? ?? 'transfer';
              final amount = (data['amount'] as num?) ?? 0;
              final memo = (data['memo'] as String?) ?? '';
              final createdAtRaw = data['createdAt'];
              DateTime? createdAt;
              if (createdAtRaw is Timestamp) {
                createdAt = createdAtRaw.toDate();
              } else if (createdAtRaw is DateTime) {
                createdAt = createdAtRaw;
              }
              final fromUid = (data['fromUid'] as String?) ?? '';
              final toUid = (data['toUid'] as String?) ?? '';
              final formattedDate = createdAt == null
                  ? ''
                  : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')} '
                    '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

              final isIncoming = toUid == user.uid;
              final displayAmount =
                  '${isIncoming ? '+' : '-'}${amount.toStringAsFixed(2)} $symbol';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueGrey.shade50,
                  child: Icon(
                    type == 'request'
                        ? Icons.receipt_long
                        : type == 'central_bank'
                            ? Icons.account_balance
                            : Icons.swap_horiz,
                    color: Colors.blueGrey,
                  ),
                ),
                title: Text(displayAmount,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  memo.isEmpty ? '$fromUid → $toUid' : memo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  formattedDate,
                  style:
                      Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.grey),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
