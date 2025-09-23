import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/community_service.dart';

class CommunityLeaderSettingsScreen extends StatefulWidget {
  const CommunityLeaderSettingsScreen({
    super.key,
    required this.communityId,
    required this.currentLeaderUid,
    required this.currentUserUid,
  });

  final String communityId;
  final String currentLeaderUid;
  final String currentUserUid;

  @override
  State<CommunityLeaderSettingsScreen> createState() =>
      _CommunityLeaderSettingsScreenState();
}

class _CommunityLeaderSettingsScreenState
    extends State<CommunityLeaderSettingsScreen> {
  final CommunityService _service = CommunityService();
  String? _selectedLeader;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedLeader = widget.currentLeaderUid;
  }

  @override
  Widget build(BuildContext context) {
    final membersStream = FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: widget.communityId)
        .orderBy('joinedAt', descending: false)
        .limit(50)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('リーダー設定'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: membersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('メンバー一覧を取得できませんでした: ${snapshot.error}'),
              ),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('メンバーがいません'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text(
                'リーダーは常に1人必要です。新しくリーダーにしたいメンバーを選択してください。',
                style: TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ...docs.map((doc) {
                final data = doc.data();
                final uid = (data['uid'] as String?) ?? '';
                final role = (data['role'] as String?) ?? 'member';
                final pending = data['pending'] == true;
                final isSelectable = !pending;
                final joinedAt = data['joinedAt'];
                final joinedLabel = joinedAt is Timestamp
                    ? joinedAt.toDate().toLocal().toString()
                    : null;
                final subtitleParts = <String>[
                  _roleLabel(role),
                  if (pending) '承認待ち',
                  if (joinedLabel != null) '参加日: $joinedLabel',
                ];
                if (uid == widget.currentUserUid) {
                  subtitleParts.add('あなた');
                }
                return RadioListTile<String>(
                  value: uid,
                  groupValue: _selectedLeader,
                  onChanged: (!isSelectable || _saving)
                      ? null
                      : (value) => setState(() => _selectedLeader = value),
                  title: Text(uid.isEmpty ? '未設定ユーザー' : uid),
                  subtitle: Text(subtitleParts.join(' / ')),
                  secondary: uid == widget.currentLeaderUid
                      ? const Icon(Icons.star, color: Colors.amber)
                      : null,
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(_saving ? '更新中…' : 'リーダーを移譲'),
          ),
        ),
      ),
    );
  }

  bool get _canSubmit {
    return !_saving &&
        _selectedLeader != null &&
        _selectedLeader != widget.currentLeaderUid;
  }

  Future<void> _submit() async {
    final target = _selectedLeader;
    if (target == null || target == widget.currentLeaderUid) {
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.transferLeadership(
        communityId: widget.communityId,
        currentLeaderUid: widget.currentLeaderUid,
        newLeaderUid: target,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('リーダー権限の更新に失敗しました: $e')),
      );
    }
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return 'リーダー';
      case 'admin':
        return '管理者';
      case 'mediator':
        return '仲介役';
      default:
        return 'メンバー';
    }
  }
}
