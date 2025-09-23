import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommunityLinksScreen extends StatelessWidget {
  const CommunityLinksScreen({
    super.key,
    required this.communityId,
    required this.user,
  });

  final String communityId;
  final User user;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required User user,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityLinksScreen(
          communityId: communityId,
          user: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('リンク送金'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'リンク送金は準備中です',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'コミュニティメンバーにURLを共有して送金・請求できる機能をサポート予定です。'
              '現時点では中央銀行ページからの送金・請求をご利用ください。',
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('戻る'),
            )
          ],
        ),
      ),
    );
  }
}
