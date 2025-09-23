import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/services.dart';

import '../constants/community.dart';
import '../models/community.dart';
import '../services/community_service.dart';
import '../services/firestore_refs.dart';
import 'central_bank_screen.dart';
import 'community_home_screen.dart';
import 'community_create_screen.dart';
import 'community_leader_settings_screen.dart';
import 'transactions/transaction_flow_screen.dart';

// ---- Brand tokens (アプリ全体と統一) ----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key, required this.user});
  final User user;

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final TextEditingController _inviteCtrl = TextEditingController();
  final CommunityService _communityService = CommunityService();
  Set<String> _myCommunityIds = <String>{};

  @override
  void dispose() {
    _inviteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membershipsQuery = FirebaseFirestore.instance
        .collection('memberships')
        .where('uid', isEqualTo: widget.user.uid)
        .orderBy('joinedAt', descending: true);

    // Discover（公開コミュ）: まずは単純に最新順。将来 where('discoverable', isEqualTo: true) を追加
    final discoverQuery =
        FirebaseFirestore.instance.collection('communities').limit(10);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('コミュニティ',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'コミュニティを作成',
            onPressed: () => _createCommunity(context),
            icon: ShaderMask(
              shaderCallback: (Rect b) => kBrandGrad.createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ===== 自分のコミュニティ =====
          _sectionHeader('自分のコミュニティ'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: membershipsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('読み込みエラー: ${snap.error}'),
                );
              }
              final docs = snap.data?.docs ?? [];
              final newSet = <String>{
                for (final doc in docs)
                  if (doc.data()['cid'] is String) doc.data()['cid'] as String
              };
              if (!setEquals(_myCommunityIds, newSet)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _myCommunityIds = newSet);
                  }
                });
              }
              if (docs.isEmpty) {
                return _emptyMyCommunities(context);
              }
              return Column(
                children: [
                  for (final m in docs) ...[
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .doc('communities/${m['cid']}')
                          .get(),
                      builder: (context, cSnap) {
                        final membershipData = m.data();
                        final cid =
                            (membershipData['cid'] as String?) ?? 'unknown';
                        final community =
                            cSnap.data?.data() ?? <String, dynamic>{};
                        final name = (community['name'] as String?) ?? cid;
                        final members =
                            (community['membersCount'] as num?)?.toInt();
                        final cover = (community['coverUrl'] as String?);
                        return _communityCard(
                          title: name,
                          subtitle:
                              members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                          coverUrl: cover,
                          onTap: () => CommunityHomeScreen.open(
                            context,
                            communityId: cid,
                            communityPreview: community,
                            membershipData: membershipData,
                            user: widget.user,
                          ),
                          onInfo: () => _openCommunitySheet(
                            context,
                            cid,
                            membershipData,
                            widget.user,
                            community,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ]
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ===== 参加（招待コード） =====
          _sectionHeader('コミュニティに参加する'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inviteCtrl,
                  decoration: InputDecoration(
                    hintText: '招待コード / コミュニティID を入力',
                    filled: true,
                    fillColor: kLightGray,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBrandBlue, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                      gradient: kBrandGrad,
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () async => _joinCommunityWithCode(
                          context, _inviteCtrl.text.trim()),
                      child: const Text('参加'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Center(
              child: Text('または', style: TextStyle(color: Colors.grey))),

          const SizedBox(height: 12),
          _sectionHeader('探して参加申請'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: discoverQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('読み込みエラー: ${snap.error}'),
                );
              }
              final docs = snap.data?.docs ?? [];
              final filtered = [
                for (final d in docs)
                  if (!_myCommunityIds.contains(d.id)) d
              ];
              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('公開中のコミュニティはまだありません'),
                );
              }
              return Column(
                children: [
                  for (final d in filtered) ...[
                    _discoverCard(d.data(), onRequest: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('参加申請は準備中です')),
                      );
                    }),
                    const SizedBox(height: 8),
                  ]
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ===== UI Parts =====
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87)),
    );
  }

  Widget _communityCard({
    required String title,
    required String subtitle,
    String? coverUrl,
    VoidCallback? onTap,
    VoidCallback? onInfo,
  }) {
    Widget leading;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          coverUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverFallback(title),
        ),
      );
    } else {
      leading = _coverFallback(title);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.black54)),
        trailing: onInfo == null
            ? const Icon(Icons.chevron_right)
            : Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'コミュニティ情報',
                    onPressed: onInfo,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
        onTap: onTap,
      ),
    );
  }

  Widget _discoverCard(Map<String, dynamic> c,
      {required VoidCallback onRequest}) {
    final title = (c['name'] as String?) ?? (c['id'] as String? ?? 'Community');
    final members = (c['membersCount'] as num?)?.toInt();
    final cover = (c['coverUrl'] as String?);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            // cover
            if (cover != null && cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  cover,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverFallback(title),
                ),
              )
            else
              _coverFallback(title),
            const SizedBox(width: 12),
            // texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // request button
            OutlinedButton(
              onPressed: onRequest,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kBrandBlue),
                foregroundColor: kBrandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('申請'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback(String title) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
          color: kLightGray, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _emptyMyCommunities(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('まだコミュニティがありません',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: kBrandGrad,
                    borderRadius: BorderRadius.all(Radius.circular(999))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: () => _joinCommunityDialog(context),
                    icon: const Icon(Icons.group_add),
                    label: const Text('参加する'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: kBrandGrad,
                    borderRadius: BorderRadius.all(Radius.circular(999))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: () => _createCommunity(context),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('作成する'),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // ===== Actions =====
  Future<void> _joinCommunityWithCode(BuildContext context, String code) async {
    final invite = code.trim().toUpperCase();
    if (invite.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('コードを入力してください')));
      return;
    }
    try {
      final joined = await _communityService.joinCommunity(
        userId: widget.user.uid,
        inviteCode: invite,
      );
      if (!mounted) return;
      _inviteCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              joined ? '招待コード「$invite」で参加しました' : '招待コード「$invite」で参加申請を送信しました'),
        ),
      );
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加に失敗しました: ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('参加に失敗しました: $e')));
    }
  }

  Future<void> _joinCommunityDialog(BuildContext context) async {
    final controller = TextEditingController();
    final cid = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('コミュニティに参加'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Community ID (cid)',
              hintText: '例: lab, family, circle1',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('参加'),
            ),
          ],
        );
      },
    );
    if (cid == null || cid.isEmpty) return;
    await _joinCommunityWithCode(context, cid);
  }

  // 単一画面のコミュニティ作成へ遷移
  Future<void> _createCommunity(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CommunityCreateScreen()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コミュニティを作成しました')),
      );
    }
  }

  Future<void> _openCommunitySheet(
      BuildContext context,
      String communityId,
      Map<String, dynamic> membershipData,
      User user,
      Map<String, dynamic>? communityPreview) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _CommunityDetailSheet(
          communityId: communityId,
          membershipData: membershipData,
          user: user,
          communityPreview: communityPreview,
        );
      },
    );
    if (!context.mounted) return;
    if (result == 'left') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コミュニティを脱退しました')),
      );
    }
  }
}

class _CommunityDetailSheet extends StatefulWidget {
  const _CommunityDetailSheet({
    required this.communityId,
    required this.membershipData,
    required this.user,
    required this.communityPreview,
  });

  final String communityId;
  final Map<String, dynamic> membershipData;
  final User user;
  final Map<String, dynamic>? communityPreview;

  @override
  State<_CommunityDetailSheet> createState() => _CommunityDetailSheetState();
}

class _CommunityDetailSheetState extends State<_CommunityDetailSheet> {
  final CommunityService _communityService = CommunityService();
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final membershipStream = FirebaseFirestore.instance
        .doc(
            'memberships/${FirestoreRefs.membershipId(widget.communityId, widget.user.uid)}')
        .snapshots();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.6,
      builder: (ctx, controller) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: membershipStream,
          builder: (context, membershipSnap) {
            final membershipRaw =
                membershipSnap.data?.data() ?? widget.membershipData;
            final balance = (membershipRaw['balance'] as num?) ?? 0;
            final role = (membershipRaw['role'] as String?) ?? 'member';
            final hasBankPermission =
                role == 'owner' || (membershipRaw['canManageBank'] == true);

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .doc('communities/${widget.communityId}')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'コミュニティ情報の取得に失敗しました: ${snapshot.error}'),
                    ),
                  );
                }
                final rawData = snapshot.data?.data();
                final data = rawData ?? widget.communityPreview ?? {};
                final name = (data['name'] as String?) ?? widget.communityId;
                final currency = CommunityCurrency.fromMap(
                    (data['currency'] as Map<String, dynamic>?) ?? const {});
                final policy = CommunityPolicy.fromMap(
                    (data['policy'] as Map<String, dynamic>?) ?? const {});
                final description = (data['description'] as String?) ?? '';
                final symbol = (data['symbol'] as String?) ?? currency.code;
                final membersCount = (data['membersCount'] as num?)?.toInt();
                final inviteCode = (data['inviteCode'] as String?) ?? '';
                final discoverable = data['discoverable'] == true;
                final ownerUid = (data['ownerUid'] as String?) ?? '';

                Future<void> handleBankSettings() async {
                  if (hasBankPermission) {
                    await CentralBankScreen.open(
                      context,
                      communityId: widget.communityId,
                      communityName: name,
                      user: widget.user,
                    );
                    return;
                  }
                  final messageCtrl = TextEditingController();
                  final result = await showDialog<String>(
                    context: context,
                    builder: (dialogCtx) {
                      return AlertDialog(
                        title: const Text('設定変更をリクエスト'),
                        content: TextField(
                          controller: messageCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: '変更してほしい内容があれば記入してください',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('キャンセル'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dialogCtx)
                                .pop(messageCtrl.text.trim()),
                            child: const Text('送信'),
                          ),
                        ],
                      );
                    },
                  );
                  final message = result?.trim();
                  messageCtrl.dispose();
                  if (message == null) return;
                  try {
                    await _communityService.submitBankSettingRequest(
                      communityId: widget.communityId,
                      requesterUid: widget.user.uid,
                      message: message.isEmpty ? null : message,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('設定変更リクエストを送信しました')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('リクエスト送信に失敗しました: $e')),
                    );
                  }
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    rawData == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Material(
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _RoleChip(role: role),
                              if (membersCount != null)
                                Chip(
                                  label: Text('メンバー $membersCount人'),
                                  backgroundColor: kLightGray,
                                ),
                              if (discoverable)
                                const Chip(
                                  label: Text('一般公開'),
                                  backgroundColor: kLightGray,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _BalanceSummaryCard(
                            balance: balance,
                            currency: currency,
                            inviteCode:
                                inviteCode.isEmpty ? null : inviteCode,
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(description,
                                style:
                                    const TextStyle(color: Colors.black87)),
                          ],
                          const SizedBox(height: 24),
                          const _SectionHeader(title: 'ショートカット'),
                          const SizedBox(height: 8),
                          _QuickActions(
                            onSend: () {
                              Navigator.of(context).pop();
                              TransactionFlowScreen.open(
                                context,
                                user: widget.user,
                                communityId: widget.communityId,
                                initialKind: TransactionKind.transfer,
                              );
                            },
                            onRequest: () {
                              Navigator.of(context).pop();
                              TransactionFlowScreen.open(
                                context,
                                user: widget.user,
                                communityId: widget.communityId,
                                initialKind: TransactionKind.request,
                              );
                            },
                            onSplit: () {
                              Navigator.of(context).pop();
                              TransactionFlowScreen.open(
                                context,
                                user: widget.user,
                                communityId: widget.communityId,
                                initialKind: TransactionKind.split,
                              );
                            },
                            onTask: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('タスク募集は準備中です')),
                              );
                            },
                            onBankSettings: handleBankSettings,
                            canManageBank: hasBankPermission,
                          ),
                          const SizedBox(height: 24),
                          const _SectionHeader(title: '通貨・中央銀行設定'),
                          const SizedBox(height: 8),
                          _CentralBankLinkCard(
                            currency: currency,
                            requiresApproval: policy.requiresApproval,
                            allowMinting: currency.allowMinting,
                            onOpen: handleBankSettings,
                            canManage: hasBankPermission,
                          ),
                          if (!hasBankPermission) ...[
                            const SizedBox(height: 8),
                            const Text(
                              '中央銀行の設定はウォレットから管理できます。必要な場合は変更をリクエストしてください。',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: handleBankSettings,
                                icon: const Icon(Icons.outgoing_mail, size: 18),
                                label: const Text('変更をリクエスト'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (role == 'owner' || role == 'admin') ...[
                            const _SectionHeader(title: '参加申請'),
                            const SizedBox(height: 8),
                            _PendingJoinRequestsList(
                              communityId: widget.communityId,
                              service: _communityService,
                              approverUid: widget.user.uid,
                            ),
                            const SizedBox(height: 24),
                          ],
                          const _SectionHeader(title: '最近のタイムライン'),
                          const SizedBox(height: 8),
                          _CommunityActivityList(
                            communityId: widget.communityId,
                            symbol: symbol,
                            precision: currency.precision,
                            currentUid: widget.user.uid,
                          ),
                          const SizedBox(height: 24),
                          const _SectionHeader(title: 'タスク'),
                          const SizedBox(height: 8),
                          _CommunityTasksList(
                            communityId: widget.communityId,
                          ),
                          const SizedBox(height: 24),
                          const _SectionHeader(title: 'メンバー'),
                          const SizedBox(height: 8),
                          _CommunityMembersList(
                            communityId: widget.communityId,
                            service: _communityService,
                            currentUserUid: widget.user.uid,
                            currentUserRole: role,
                          ),
                          if (role == 'owner') ...[
                            const SizedBox(height: 24),
                            const _SectionHeader(title: 'リーダー設定'),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _openLeaderSettings(ownerUid),
                              icon: const Icon(Icons.manage_accounts),
                              label: const Text('リーダーを変更'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'リーダーは常に1人必要です。脱退する場合は別のメンバーにリーダー権限を渡してください。',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _LeaveCommunitySection(
                            isLeader: role == 'owner',
                            membersCount: membersCount ?? 0,
                            onLeave: () => _confirmLeave(
                              isLeader: role == 'owner',
                              membersCount: membersCount ?? 0,
                            ),
                            leaving: _leaving,
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openLeaderSettings(String ownerUid) async {
    if (ownerUid.isEmpty) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommunityLeaderSettingsScreen(
          communityId: widget.communityId,
          currentLeaderUid: ownerUid,
          currentUserUid: widget.user.uid,
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リーダー権限を移譲しました')),
      );
    }
  }

  Future<void> _confirmLeave({
    required bool isLeader,
    required int membersCount,
  }) async {
    if (_leaving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('コミュニティを脱退'),
          content: Text(
            isLeader && membersCount <= 1
                ? 'コミュニティを脱退すると、このコミュニティはメンバーがいなくなります。よろしいですか？'
                : 'コミュニティから脱退しますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('脱退する'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    setState(() => _leaving = true);
    try {
      await _communityService.leaveCommunity(
        communityId: widget.communityId,
        userId: widget.user.uid,
      );
      if (!mounted) return;
      Navigator.of(context).pop('left');
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('脱退に失敗しました: $e')),
      );
    }
  }
}

class _LeaveCommunitySection extends StatelessWidget {
  const _LeaveCommunitySection({
    required this.isLeader,
    required this.membersCount,
    required this.onLeave,
    required this.leaving,
  });

  final bool isLeader;
  final int membersCount;
  final VoidCallback onLeave;
  final bool leaving;

  @override
  Widget build(BuildContext context) {
    final canLeave = !isLeader || membersCount <= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: (!canLeave || leaving) ? null : onLeave,
          icon: const Icon(Icons.logout),
          label: Text(leaving ? '処理中…' : 'コミュニティを脱退'),
        ),
        if (isLeader && !canLeave)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'リーダーは別のメンバーにリーダー権限を渡してから脱退できます。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
    return Chip(
      label: Text(label),
      backgroundColor: kLightGray,
    );
  }
}

class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard({
    required this.balance,
    required this.currency,
    this.inviteCode,
  });

  final num balance;
  final CommunityCurrency currency;
  final String? inviteCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${currency.name} (${currency.code})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '残高: ${balance.toStringAsFixed(currency.precision)} ${currency.code}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect b) => kBrandGrad.createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.account_balance_wallet, size: 26),
              ),
            ],
          ),
          if (inviteCode != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.qr_code, size: 18, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('招待コード: $inviteCode',
                      style: const TextStyle(color: Colors.black54)),
                ),
                IconButton(
                  tooltip: 'コードをコピー',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inviteCode!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('招待コードをコピーしました')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              '参加リンク: https://econobook.app/join?code=$inviteCode',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final link = 'https://econobook.app/join?code=$inviteCode';
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('参加リンクをコピーしました')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_all, size: 18),
                label: const Text('リンクをコピー'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onSend,
    required this.onRequest,
    required this.onSplit,
    required this.onTask,
    this.onBankSettings,
    this.canManageBank = false,
  });

  final VoidCallback onSend;
  final VoidCallback onRequest;
  final VoidCallback onSplit;
  final VoidCallback onTask;
  final VoidCallback? onBankSettings;
  final bool canManageBank;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _QuickActionButton(
          icon: Icons.send,
          label: '送金',
          onTap: onSend,
        ),
        _QuickActionButton(
          icon: Icons.receipt_long,
          label: '請求',
          onTap: onRequest,
        ),
        _QuickActionButton(
          icon: Icons.calculate,
          label: '割り勘',
          onTap: onSplit,
        ),
        _QuickActionButton(
          icon: Icons.task_alt,
          label: 'タスク募集',
          onTap: onTask,
        ),
        if (onBankSettings != null)
          _QuickActionButton(
            icon: Icons.account_balance,
            label:
                canManageBank ? '中央銀行（ウォレット）' : '中央銀行を見る',
            onTap: onBankSettings!,
          ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: kBrandBlue,
          side: const BorderSide(color: kBrandBlue),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _CentralBankLinkCard extends StatelessWidget {
  const _CentralBankLinkCard({
    required this.currency,
    required this.requiresApproval,
    required this.allowMinting,
    required this.onOpen,
    required this.canManage,
  });

  final CommunityCurrency currency;
  final bool requiresApproval;
  final bool allowMinting;
  final VoidCallback onOpen;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final actionLabel =
        canManage ? '中央銀行を開く' : 'ウォレットで中央銀行を見る';
    final actionIcon = canManage ? Icons.account_balance : Icons.open_in_new;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('通貨', '${currency.name} (${currency.code})'),
          _infoRow('小数点以下桁数', '${currency.precision} 桁'),
          _infoRow(
            'メンバーによる発行',
            allowMinting ? '許可' : '管理者のみ',
          ),
          _infoRow('参加承認', requiresApproval ? '承認必須' : '自動参加'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.black87, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _PendingJoinRequestsList extends StatelessWidget {
  const _PendingJoinRequestsList({
    required this.communityId,
    required this.service,
    required this.approverUid,
  });

  final String communityId;
  final CommunityService service;
  final String approverUid;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('join_requests')
        .doc(communityId)
        .collection('items')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(20)
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
            child: Text('参加申請を取得できませんでした: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('未処理の申請はありません'),
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              _JoinRequestTile(
                communityId: communityId,
                data: doc.data(),
                requesterUid: doc.id,
                service: service,
                approverUid: approverUid,
              ),
          ],
        );
      },
    );
  }
}

class _JoinRequestTile extends StatefulWidget {
  const _JoinRequestTile({
    required this.communityId,
    required this.data,
    required this.requesterUid,
    required this.service,
    required this.approverUid,
  });

  final String communityId;
  final Map<String, dynamic> data;
  final String requesterUid;
  final CommunityService service;
  final String approverUid;

  @override
  State<_JoinRequestTile> createState() => _JoinRequestTileState();
}

class _JoinRequestTileState extends State<_JoinRequestTile> {
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final createdRaw = widget.data['createdAt'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();
    if (createdRaw is DateTime) createdAt = createdRaw;

    final createdLabel = createdAt == null
        ? ''
        : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(widget.requesterUid,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: createdLabel.isEmpty
            ? null
            : Text('申請日: $createdLabel',
                style: const TextStyle(color: Colors.black54)),
        trailing: _processing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _processing ? null : () => _approve(context),
                    child: const Text('承認'),
                  ),
                  TextButton(
                    onPressed: _processing ? null : () => _reject(context),
                    child: const Text('却下'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    setState(() => _processing = true);
    try {
      await widget.service.approveJoinRequest(
        communityId: widget.communityId,
        requesterUid: widget.requesterUid,
        approvedBy: widget.approverUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.requesterUid} を承認しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('承認に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject(BuildContext context) async {
    setState(() => _processing = true);
    try {
      await widget.service.rejectJoinRequest(
        communityId: widget.communityId,
        requesterUid: widget.requesterUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.requesterUid} を却下しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('却下に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}

class _CommunityActivityList extends StatelessWidget {
  const _CommunityActivityList({
    required this.communityId,
    required this.symbol,
    required this.precision,
    required this.currentUid,
  });

  final String communityId;
  final String symbol;
  final int precision;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('ledger')
        .doc(communityId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(15)
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
            child: Text('タイムラインを取得できませんでした: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('まだアクティビティがありません'),
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              _ActivityTile(
                data: doc.data(),
                symbol: symbol,
                precision: precision,
                currentUid: currentUid,
              ),
          ],
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.data,
    required this.symbol,
    required this.precision,
    required this.currentUid,
  });

  final Map<String, dynamic> data;
  final String symbol;
  final int precision;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final type = (data['type'] as String?) ?? 'transfer';
    final amount = (data['amount'] as num?) ?? 0;
    final fromUid = (data['fromUid'] as String?) ?? '';
    final toUid = (data['toUid'] as String?) ?? '';
    final memo = (data['memo'] as String?) ?? '';
    final createdRaw = data['createdAt'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();
    if (createdRaw is DateTime) createdAt = createdRaw;

    final icon = switch (type) {
      'task' => Icons.task_alt,
      'request' => Icons.receipt_long,
      'split' => Icons.calculate,
      'central_bank' => Icons.account_balance,
      _ => Icons.swap_horiz,
    };

    final amountText = '${amount.toStringAsFixed(precision)} $symbol';
    final fromDisplay = switch (fromUid) {
      kCentralBankUid => '中央銀行',
      '' => '—',
      _ => fromUid,
    };
    final toDisplay = switch (toUid) {
      kCentralBankUid => '中央銀行',
      '' => '—',
      _ => toUid,
    };
    final subtitle = memo.isNotEmpty ? memo : '$fromDisplay → $toDisplay';
    final dateLabel = createdAt == null
        ? ''
        : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: kLightGray,
        child: Icon(icon, color: kBrandBlue),
      ),
      title:
          Text(amountText, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty) Text(subtitle),
          if (dateLabel.isNotEmpty)
            Text(dateLabel,
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ],
      ),
    );
  }
}

class _CommunityTasksList extends StatelessWidget {
  const _CommunityTasksList({required this.communityId});

  final String communityId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('tasks')
        .doc(communityId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(10)
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
            child: Text('タスクを取得できませんでした: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('公開中のタスクはありません'),
          );
        }
        return Column(
          children: [
            for (final doc in docs) _TaskTile(data: doc.data()),
          ],
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?) ?? '無題のタスク';
    final reward = (data['reward'] as num?) ?? 0;
    final status = (data['status'] as String?) ?? 'open';
    final deadlineRaw = data['deadline'];
    DateTime? deadline;
    if (deadlineRaw is Timestamp) deadline = deadlineRaw.toDate();
    if (deadlineRaw is DateTime) deadline = deadlineRaw;

    final statusLabel = switch (status) {
      'open' => '募集',
      'taken' => '進行中',
      'submitted' => '承認待ち',
      'approved' => '完了',
      'rejected' => '却下',
      _ => status,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: kLightGray,
        child: const Icon(Icons.task, color: kBrandBlue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('報酬: $reward'),
          Text('状態: $statusLabel',
              style: const TextStyle(color: Colors.black54)),
          if (deadline != null)
            Text(
              '締切: ${deadline.year}/${deadline.month.toString().padLeft(2, '0')}/${deadline.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
        ],
      ),
    );
  }
}

class _CommunityMembersList extends StatelessWidget {
  const _CommunityMembersList({
    required this.communityId,
    required this.service,
    required this.currentUserUid,
    required this.currentUserRole,
  });

  final String communityId;
  final CommunityService service;
  final String currentUserUid;
  final String currentUserRole;

  bool get _canEditPermissions => currentUserRole == 'owner';

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: communityId)
        .orderBy('joinedAt', descending: true)
        .limit(20)
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
            child: Text('メンバーを取得できませんでした: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('メンバーがまだいません'),
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              _MemberTile(
                communityId: communityId,
                data: doc.data(),
                service: service,
                canEdit: _canEditPermissions,
                currentUserUid: currentUserUid,
              ),
          ],
        );
      },
    );
  }
}

class _MemberTile extends StatefulWidget {
  const _MemberTile({
    required this.communityId,
    required this.data,
    required this.service,
    required this.canEdit,
    required this.currentUserUid,
  });

  final String communityId;
  final Map<String, dynamic> data;
  final CommunityService service;
  final bool canEdit;
  final String currentUserUid;

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  late bool _hasPermission;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _hasPermission = widget.data['canManageBank'] == true;
  }

  @override
  void didUpdateWidget(covariant _MemberTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = widget.data['canManageBank'] == true;
    if (!_updating && newValue != _hasPermission) {
      setState(() => _hasPermission = newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = (widget.data['uid'] as String?) ?? 'unknown';
    final role = (widget.data['role'] as String?) ?? 'member';
    final balance = (widget.data['balance'] as num?) ?? 0;
    final canToggle =
        widget.canEdit && role != 'owner' && uid != widget.currentUserUid;

    String roleLabel(String value) {
      return switch (value) {
        'owner' => 'オーナー',
        'admin' => '管理者',
        'mediator' => '仲介',
        'pending' => '承認待ち',
        _ => 'メンバー',
      };
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: kLightGray,
        child: Text(uid.isNotEmpty ? uid.substring(0, 1).toUpperCase() : '?'),
      ),
      title: Text(uid, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('役割: ${roleLabel(role)}'
              '${_hasPermission ? ' • 設定権限あり' : ''}'),
          Text('残高: ${balance.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.black54)),
        ],
      ),
      trailing: canToggle
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updating)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Switch.adaptive(
                  value: _hasPermission,
                  onChanged: _updating ? null : _togglePermission,
                ),
              ],
            )
          : (_hasPermission
              ? const Icon(Icons.verified_user, color: kBrandBlue)
              : null),
    );
  }

  Future<void> _togglePermission(bool value) async {
    if (_updating) return;
    final targetUid = (widget.data['uid'] as String?) ?? '';
    if (targetUid.isEmpty) return;
    setState(() {
      _hasPermission = value;
      _updating = true;
    });
    try {
      await widget.service.setBankManagementPermission(
        communityId: widget.communityId,
        targetUid: targetUid,
        enabled: value,
        updatedBy: widget.currentUserUid,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? '$targetUid に中央銀行設定権限を付与しました'
              : '$targetUid の中央銀行設定権限を解除しました'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('権限の更新に失敗しました: $e')),
        );
      }
      if (mounted) {
        setState(() => _hasPermission = !value);
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}
