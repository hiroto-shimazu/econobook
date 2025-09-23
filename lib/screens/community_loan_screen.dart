import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/community_service.dart';
import '../services/ledger_service.dart';

class CommunityLoanScreen extends StatefulWidget {
  const CommunityLoanScreen({
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
        builder: (_) => CommunityLoanScreen(
          communityId: communityId,
          communityName: communityName,
          user: user,
        ),
      ),
    );
  }

  @override
  State<CommunityLoanScreen> createState() => _CommunityLoanScreenState();
}

class _CommunityLoanScreenState extends State<CommunityLoanScreen> {
  final CommunityService _communityService = CommunityService();
  final LedgerService _ledgerService = LedgerService();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .doc('communities/${widget.communityId}')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('中央銀行から借入'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final treasury = CommunityTreasury.fromMap(
              (data['treasury'] as Map<String, dynamic>?) ?? const {});
          final policy = CommunityPolicy.fromMap(
              (data['policy'] as Map<String, dynamic>?) ?? const {});
          final maxLoan = treasury.balance;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.communityName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('中央銀行残高: ${maxLoan.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('初期配布金額: ${treasury.initialGrant.toStringAsFixed(2)}'),
                        Text('借入許可: ${policy.enableRequests ? '可能' : '設定による'}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '借入金額',
                    hintText: '例) 5000',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _memoCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'メモ (任意)',
                    hintText: '用途などを入力',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _submitLoan(context, maxLoan),
                  icon: const Icon(Icons.account_balance_wallet),
                  label: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('借入を確定'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitLoan(BuildContext context, num treasuryBalance) async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      _showSnack('金額を正しく入力してください');
      return;
    }
    if (amount > treasuryBalance) {
      _showSnack('中央銀行の残高が不足しています');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _communityService.createLoan(
        communityId: widget.communityId,
        borrowerUid: widget.user.uid,
        amount: amount,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        ledger: _ledgerService,
        createdBy: widget.user.uid,
      );
      if (!mounted) return;
      _showSnack('借入を記録しました');
      Navigator.of(context).pop();
    } catch (e) {
      _showSnack('借入に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
