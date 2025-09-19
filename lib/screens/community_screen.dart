
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'community_create_screen.dart';

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
    final discoverQuery = FirebaseFirestore.instance
        .collection('communities')
        .limit(10);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('コミュニティ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
              if (docs.isEmpty) {
                return _emptyMyCommunities(context);
              }
              return Column(
                children: [
                  for (final m in docs) ...[
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance.doc('communities/${m['cid']}').get(),
                      builder: (context, cSnap) {
                        final c = cSnap.data?.data() ?? <String, dynamic>{};
                        final cid = (m['cid'] as String?) ?? 'unknown';
                        final name = (c['name'] as String?) ?? cid;
                        final members = (c['membersCount'] as num?)?.toInt();
                        final cover = (c['coverUrl'] as String?);
                        return _communityCard(
                          title: name,
                          subtitle: members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                          coverUrl: cover,
                          onTap: () => _openCommunitySheet(context, cid),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                  decoration: const BoxDecoration(gradient: kBrandGrad, borderRadius: BorderRadius.all(Radius.circular(12))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () async => _joinCommunityWithCode(context, _inviteCtrl.text.trim()),
                      child: const Text('参加'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Center(child: Text('または', style: TextStyle(color: Colors.grey))),

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
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('公開中のコミュニティはまだありません'),
                );
              }
              return Column(
                children: [
                  for (final d in docs) ...[
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
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
    );
  }

  Widget _communityCard({
    required String title,
    required String subtitle,
    String? coverUrl,
    VoidCallback? onTap,
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
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _discoverCard(Map<String, dynamic> c, {required VoidCallback onRequest}) {
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
      decoration: BoxDecoration(color: kLightGray, borderRadius: BorderRadius.circular(8)),
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
          const Text('まだコミュニティがありません', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(gradient: kBrandGrad, borderRadius: BorderRadius.all(Radius.circular(999))),
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
                decoration: const BoxDecoration(gradient: kBrandGrad, borderRadius: BorderRadius.all(Radius.circular(999))),
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
    final cid = code.trim();
    if (cid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コードを入力してください')));
      return;
    }
    try {
      await FirebaseFirestore.instance.doc('memberships/${cid}_${widget.user.uid}').set({
        'cid': cid,
        'uid': widget.user.uid,
        'balance': 0,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance.doc('communities/$cid').set({'name': cid}, SetOptions(merge: true));
      if (!mounted) return;
      _inviteCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$cid」に参加しました')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('参加に失敗しました: $e')));
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

  Future<void> _openCommunitySheet(BuildContext context, String cid) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DefaultTabController(
          length: 4,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                elevation: 0,
                title: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.doc('communities/$cid').get(),
                  builder: (context, snap) {
                    final name = snap.data?.data()?['name'] as String?;
                    return Text(name ?? cid, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold));
                  },
                ),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'フィード'),
                    Tab(text: 'タスク'),
                    Tab(text: 'トレジャリー'),
                    Tab(text: 'メンバー'),
                  ],
                  labelColor: kBrandBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: kBrandBlue,
                ),
              ),
              body: TabBarView(
                children: [
                  // Feed
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: const [SizedBox(height: 32), Center(child: Text('まだアクティビティがありません'))],
                  ),
                  // Tasks
                  _CommunityTasksTab(cid: cid),
                  // Treasury
                  _CommunityTreasuryTab(cid: cid),
                  // Members
                  _CommunityMembersTab(cid: cid),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---- Placeholder tabs（将来置き換え）----
class _CommunityTasksTab extends StatelessWidget {
  const _CommunityTasksTab({required this.cid});
  final String cid;
  @override
  Widget build(BuildContext context) => Center(child: Text('タスク（準備中）: $cid'));
}

class _CommunityTreasuryTab extends StatelessWidget {
  const _CommunityTreasuryTab({required this.cid});
  final String cid;
  @override
  Widget build(BuildContext context) => Center(child: Text('トレジャリー（準備中）: $cid'));
}

class _CommunityMembersTab extends StatelessWidget {
  const _CommunityMembersTab({required this.cid});
  final String cid;
  @override
  Widget build(BuildContext context) => Center(child: Text('メンバー（準備中）: $cid'));
}
