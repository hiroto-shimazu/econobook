import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../utils/firestore_index_link_copy.dart';

class CommunityJoinRequestsScreen extends StatefulWidget {
  const CommunityJoinRequestsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.currentUserUid,
  });

  final String communityId;
  final String communityName;
  final String currentUserUid;

  @override
  State<CommunityJoinRequestsScreen> createState() =>
      _CommunityJoinRequestsScreenState();
}

class _CommunityJoinRequestsScreenState
    extends State<CommunityJoinRequestsScreen> {
  final CommunityService _communityService = CommunityService();
  String? _processingUid;
  bool _bulkProcessing = false;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('join_requests')
        .doc(widget.communityId)
        .collection('items')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text('${widget.communityName}の参加申請'),
            ),
            body: Center(
              child: Text('申請を取得できませんでした: ${snapshot.error}'),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        final pendingUids = <String>[
          for (final doc in docs)
            (doc.data()['uid'] as String?) ?? doc.id,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.communityName}の参加申請'),
            actions: [
              if (pendingUids.isNotEmpty)
                IconButton(
                  tooltip: 'すべて承認',
                  onPressed:
                      _bulkProcessing ? null : () => _approveAll(pendingUids),
                  icon: const Icon(Icons.done_all_outlined),
                ),
              if (pendingUids.isNotEmpty)
                IconButton(
                  tooltip: 'すべて却下',
                  onPressed:
                      _bulkProcessing ? null : () => _rejectAll(pendingUids),
                  icon: const Icon(Icons.clear_all_outlined),
                ),
            ],
          ),
          body: docs.isEmpty
              ? const _EmptyJoinRequests()
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final uid = (data['uid'] as String?) ?? doc.id;
                    final createdAt = data['createdAt'];
                    return _JoinRequestTile(
                      userId: uid,
                      createdAt: createdAt,
                      processing: _processingUid == uid,
                      onApprove: () => _handleApprove(uid),
                      onReject: () => _handleReject(uid),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: docs.length,
                ),
        );
      },
    );
  }

  Future<void> _handleApprove(String requesterUid) async {
    setState(() => _processingUid = requesterUid);
    try {
      await _communityService.approveJoinRequest(
        communityId: widget.communityId,
        requesterUid: requesterUid,
        approvedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加申請を承認しました ($requesterUid)')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('承認に失敗しました: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('承認に失敗しました: $e')),
      );
    } finally {
      if (mounted && _processingUid == requesterUid) {
        setState(() => _processingUid = null);
      }
    }
  }

  Future<void> _handleReject(String requesterUid) async {
    setState(() => _processingUid = requesterUid);
    try {
      await _communityService.rejectJoinRequest(
        communityId: widget.communityId,
        requesterUid: requesterUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加申請を却下しました ($requesterUid)')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('却下に失敗しました: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('却下に失敗しました: $e')),
      );
    } finally {
      if (mounted && _processingUid == requesterUid) {
        setState(() => _processingUid = null);
      }
    }
  }

  Future<void> _approveAll(List<String> uids) async {
    if (uids.isEmpty) return;
    setState(() => _bulkProcessing = true);
    try {
      for (final uid in uids) {
        await _communityService.approveJoinRequest(
          communityId: widget.communityId,
          requesterUid: uid,
          approvedBy: widget.currentUserUid,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${uids.length}件の申請を承認しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一括承認に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkProcessing = false);
      }
    }
  }

  Future<void> _rejectAll(List<String> uids) async {
    if (uids.isEmpty) return;
    setState(() => _bulkProcessing = true);
    try {
      for (final uid in uids) {
        await _communityService.rejectJoinRequest(
          communityId: widget.communityId,
          requesterUid: uid,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${uids.length}件の申請を却下しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一括却下に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkProcessing = false);
      }
    }
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    required this.userId,
    required this.createdAt,
    required this.processing,
    required this.onApprove,
    required this.onReject,
  });

  final String userId;
  final dynamic createdAt;
  final bool processing;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final createdAtLabel = _formatCreatedAt(createdAt);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future:
              withIndexLinkCopy(
                context,
                () => FirebaseFirestore.instance.doc('users/$userId').get(),
              ),
          builder: (context, snapshot) {
            final rawName = (snapshot.data?.data()?['displayName'] as String?)?.trim();
            final name = (rawName != null && rawName.isNotEmpty) ? rawName : '匿名ユーザー';
            final trimmedName = name.trim();
            final initial = trimmedName.isEmpty ? '?' : trimmedName[0];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Text(initial),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '申請日時: $createdAtLabel',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: processing ? null : onReject,
                        icon: const Icon(Icons.close),
                        label: const Text('却下'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ).copyWith(
                          backgroundColor: MaterialStateProperty.all(
                            Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: MaterialStateProperty.all(
                            Colors.white,
                          ),
                        ),
                        onPressed: processing ? null : onApprove,
                        icon: processing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(processing ? '処理中…' : '承認'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatCreatedAt(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is int) {
      date = DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (date == null) {
      return '不明';
    }
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final yy = local.year;
    final month = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yy/$month/$dd $hh:$mm';
  }
}

class _EmptyJoinRequests extends StatelessWidget {
  const _EmptyJoinRequests();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.verified_outlined, size: 48, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text('現在、承認待ちの参加申請はありません'),
        ],
      ),
    );
  }
}
