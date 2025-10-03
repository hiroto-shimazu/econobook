import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/community.dart';
import '../services/community_service.dart';
import '../services/request_service.dart';

class BankSettingRequestsPanel extends StatelessWidget {
  const BankSettingRequestsPanel({
    super.key,
    required this.communityId,
    required this.service,
    required this.resolverUid,
    required this.onOpenSettings,
  });

  final String communityId;
  final CommunityService service;
  final String resolverUid;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('bank_setting_requests')
        .doc(communityId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              '設定リクエストの取得に失敗しました: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        final pending = [
          for (final doc in docs)
            if ((doc.data()['status'] as String? ?? 'pending') == 'pending') doc
        ];
        if (pending.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: '設定変更リクエスト'),
            const SizedBox(height: 8),
            for (final doc in pending)
              _BankSettingRequestTile(
                communityId: communityId,
                requestId: doc.id,
                data: doc.data(),
                service: service,
                resolverUid: resolverUid,
                onOpenSettings: onOpenSettings,
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _BankSettingRequestTile extends StatefulWidget {
  const _BankSettingRequestTile({
    required this.communityId,
    required this.requestId,
    required this.data,
    required this.service,
    required this.resolverUid,
    required this.onOpenSettings,
  });

  final String communityId;
  final String requestId;
  final Map<String, dynamic> data;
  final CommunityService service;
  final String resolverUid;
  final Future<void> Function() onOpenSettings;

  @override
  State<_BankSettingRequestTile> createState() =>
      _BankSettingRequestTileState();
}

class _BankSettingRequestTileState extends State<_BankSettingRequestTile> {
  bool _resolving = false;

  @override
  Widget build(BuildContext context) {
    final requesterUid = (widget.data['requesterUid'] as String?) ?? 'unknown';
    final message = (widget.data['message'] as String?)?.trim() ?? '';
    final createdRaw = widget.data['createdAt'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();
    if (createdRaw is DateTime) createdAt = createdRaw;
    final createdLabel = createdAt == null
        ? null
        : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.doc('users/$requesterUid').get(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
    final rawName = (userData?['displayName'] as String?)?.trim();
    final displayName =
      rawName != null && rawName.isNotEmpty ? rawName : '匿名ユーザー';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (createdLabel != null)
                  Text('申請日: $createdLabel',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _resolving
                          ? null
                          : () async {
                              await widget.onOpenSettings();
                            },
                      icon: const Icon(Icons.settings),
                      label: const Text('設定を開く'),
                    ),
                    FilledButton(
                      onPressed:
                          _resolving ? null : () => _resolve(context, true),
                      child: _resolving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('承認済みにする'),
                    ),
                    TextButton(
                      onPressed:
                          _resolving ? null : () => _resolve(context, false),
                      child: const Text('却下'),
                    )
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _resolve(BuildContext context, bool approved) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      await widget.service.resolveBankSettingRequest(
        communityId: widget.communityId,
        requestId: widget.requestId,
        resolvedBy: widget.resolverUid,
        approved: approved,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approved ? 'リクエストを完了としてマークしました' : 'リクエストを却下しました'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('処理に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }
}

class CentralBankRequestsPanel extends StatelessWidget {
  const CentralBankRequestsPanel({
    super.key,
    required this.communityId,
    required this.approverUid,
    required this.requestService,
  });

  final String communityId;
  final String approverUid;
  final RequestService requestService;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('requests')
        .doc(communityId)
        .collection('items')
        .where('toUid', isEqualTo: kCentralBankUid)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              '中央銀行宛の請求取得に失敗しました: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        final pending = [
          for (final doc in docs)
            if ((doc.data()['status'] as String? ?? 'pending') == 'pending') doc
        ]..sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aMillis = aTime is Timestamp
                ? aTime.millisecondsSinceEpoch
                : aTime is DateTime
                    ? aTime.millisecondsSinceEpoch
                    : 0;
            final bMillis = bTime is Timestamp
                ? bTime.millisecondsSinceEpoch
                : bTime is DateTime
                    ? bTime.millisecondsSinceEpoch
                    : 0;
            return bMillis.compareTo(aMillis);
          });
        if (pending.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: '中央銀行への請求'),
            const SizedBox(height: 8),
            for (final doc in pending)
              _CentralBankRequestTile(
                communityId: communityId,
                requestId: doc.id,
                data: doc.data(),
                requestService: requestService,
                approverUid: approverUid,
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _CentralBankRequestTile extends StatefulWidget {
  const _CentralBankRequestTile({
    required this.communityId,
    required this.requestId,
    required this.data,
    required this.requestService,
    required this.approverUid,
  });

  final String communityId;
  final String requestId;
  final Map<String, dynamic> data;
  final RequestService requestService;
  final String approverUid;

  @override
  State<_CentralBankRequestTile> createState() =>
      _CentralBankRequestTileState();
}

class _CentralBankRequestTileState extends State<_CentralBankRequestTile> {
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final requesterUid = (widget.data['fromUid'] as String?) ?? 'unknown';
    final amount = (widget.data['amount'] as num?) ?? 0;
    final memo = (widget.data['memo'] as String?)?.trim() ?? '';
    final createdRaw = widget.data['createdAt'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();
    if (createdRaw is DateTime) createdAt = createdRaw;
    final createdLabel = createdAt == null
        ? null
        : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.doc('users/$requesterUid').get(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
        final rawName = (userData?['displayName'] as String?)?.trim();
        final displayName =
            rawName != null && rawName.isNotEmpty ? rawName : requesterUid;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('請求者: $displayName',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('金額: ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.black87)),
                if (createdLabel != null)
                  Text('作成日: $createdLabel',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                if (memo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('メモ: $memo'),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _processing ? null : () => _approve(context),
                      child: _processing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('承認して送金'),
                    ),
                    TextButton(
                      onPressed: _processing ? null : () => _reject(context),
                      child: const Text('却下'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _approve(BuildContext context) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await widget.requestService.approveRequest(
        communityId: widget.communityId,
        requestId: widget.requestId,
        approvedBy: widget.approverUid,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('中央銀行からの支払いを承認しました')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('承認に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject(BuildContext context) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await widget.requestService.rejectRequest(
        communityId: widget.communityId,
        requestId: widget.requestId,
        rejectedBy: widget.approverUid,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請求を却下しました')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('却下に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }
}
