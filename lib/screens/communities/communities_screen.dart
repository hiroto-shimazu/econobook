import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/community.dart';
import '../../models/community.dart';
import '../central_bank_screen.dart';
import '../community_member_select_screen.dart';
import '../community_create_screen.dart';
import '../community_leader_settings_screen.dart';
import '../member_chat_screen.dart';
import '../transactions/transaction_flow_screen.dart';
import '../../services/community_service.dart';

part 'talk_tab.dart';
part '../../widgets/talk/talk_thread_tile.dart';
part '../../widgets/talk/talk_filter_chip.dart';
part '../../widgets/talk/role_chip.dart';
part '../../widgets/talk/empty_loading_error_cards.dart';

// ---- Brand tokens (アプリ全体と統一) ----
const Color kBrandBlue = Color(0xFF2563EB);
const Color kLightGray = Color(0xFFF1F5F9);
const Color kBgLight = Color(0xFFF8FAFC);
const Color kCardWhite = Color(0xFFFFFFFF);
const Color kTextMain = Color(0xFF0F172A);
const Color kTextSub = Color(0xFF64748B);
const Color kAccentOrange = Color(0xFFF59E0B);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
);

Widget _sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kTextMain,
      ),
    ),
  );
}

DateTime? _readTimestamp(dynamic value) {
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

int _compareJoinedAtDesc(
    Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _readTimestamp(a['joinedAt']);
  final bDate = _readTimestamp(b['joinedAt']);
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}


class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key, required this.user});
  final User user;

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final TextEditingController _inviteCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  Set<String> _myCommunityIds = <String>{};
  late final Query<Map<String, dynamic>> _talkThreadsQuery;
  late final Stream<int> _pendingRequestsCountStream;
  String _searchKeyword = '';
  final CommunityService _communityService = CommunityService();
  String? _processingJoinCommunityId;

  @override
  void initState() {
    super.initState();
    _talkThreadsQuery = FirebaseFirestore.instance
        .collectionGroup('threads')
        .where('participants', arrayContains: widget.user.uid);
    _pendingRequestsCountStream = FirebaseFirestore.instance
        .collectionGroup('items')
        .where('toUid', isEqualTo: widget.user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.size);
    _searchCtrl.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final keyword = _searchCtrl.text.trim();
    if (keyword == _searchKeyword) {
      return;
    }
    setState(() => _searchKeyword = keyword);
  }

  Widget _buildCommunityList(
    BuildContext context,
    Query<Map<String, dynamic>> membershipsQuery,
    Query<Map<String, dynamic>> discoverQuery,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        _sectionHeader('参加中のコミュニティ'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: membershipsQuery.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _loadingState();
            }
            if (snap.hasError) {
              return _errorNotice('読み込みエラー: ${snap.error}');
            }
            final docs = snap.data?.docs ?? [];
            final sortedDocs = docs.toList()
              ..sort((a, b) => _compareJoinedAtDesc(a.data(), b.data()));
            final newSet = <String>{
              for (final doc in sortedDocs)
                if (doc.data()['cid'] is String) doc.data()['cid'] as String
            };
            if (!setEquals(_myCommunityIds, newSet)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _myCommunityIds = newSet);
                }
              });
            }
            if (sortedDocs.isEmpty) {
              return _emptyMyCommunities(context);
            }
            return Column(
              children: [
                for (final m in sortedDocs) ...[
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
                      final role =
                          (membershipData['role'] as String?) ?? 'member';
                      final currency =
                          (community['currency'] as Map<String, dynamic>?) ??
                              const <String, dynamic>{};
                      final currencyName =
                          (currency['name'] as String?) ?? '独自通貨';
                      return _communityCard(
                        title: name,
                        subtitle: members == null
                            ? 'メンバー数 —'
                            : 'メンバー ${members}人',
                        coverUrl: cover,
                        role: role,
                        currencyName: currencyName,
                        onTap: () => CommunityMemberSelectScreen.open(
                          context,
                          communityId: cid,
                          currentUserUid: widget.user.uid,
                          communityName: name,
                          currentUserRole: role,
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
                  const SizedBox(height: 12),
                ]
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _sectionHeader('招待コードで参加'),
        const SizedBox(height: 8),
        _inviteInputRow(context),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'または',
            style: TextStyle(color: kTextSub.withOpacity(0.8)),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader('公開コミュニティを探す'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: discoverQuery.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _loadingState();
            }
            if (snap.hasError) {
              return _errorNotice('読み込みエラー: ${snap.error}');
            }
            final docs = snap.data?.docs ?? [];
            final filtered = [
              for (final d in docs)
                if (!_myCommunityIds.contains(d.id)) d
            ];
            if (filtered.isEmpty) {
              return _emptyDiscoverCard();
            }
            return Column(
              children: [
                for (final d in filtered) ...[
                  StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('join_requests')
                        .doc(d.id)
                        .collection('items')
                        .doc(widget.user.uid)
                        .snapshots(),
                    builder: (context, requestSnap) {
                      final communityData = d.data();
                      final requestData = requestSnap.data?.data();
                      final status = requestData == null
                          ? null
                          : (requestData['status'] as String?);
                      final isPending = status == 'pending';
                      final isProcessing =
                          _processingJoinCommunityId == d.id;
                      return _discoverCard(
                        communityData,
                        isPending: isPending,
                        isProcessing: isProcessing,
                        onRequest: isPending
                            ? null
                            : () => _requestJoinCommunity(context, d.id),
                        onViewDetail: () =>
                            _showDiscoverCommunityDetail(context, communityData),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ]
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _emptyMyCommunities(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'まだ所属コミュニティがありません',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: kTextMain,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'コミュニティを作成するか、招待コードで参加できます。',
            style: TextStyle(color: kTextSub),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _createCommunity(context),
                  child: const Text('コミュニティを作成'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kBrandBlue,
                    side: const BorderSide(color: kBrandBlue),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final code = await showDialog<String>(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('招待コードを入力'),
                          content: TextField(
                            controller: ctrl,
                            decoration: const InputDecoration(hintText: '例: ABC123'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                              child: const Text('参加'),
                            ),
                          ],
                        );
                      },
                    );
                    if (code != null && code.isNotEmpty) {
                      await _joinCommunityWithCode(context, code);
                    }
                  },
                  child: const Text('招待コードで参加'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openCommunitySheet(
    BuildContext context,
    String communityId,
    Map<String, dynamic> membershipData,
    dynamic currentUser,
    Map<String, dynamic> community,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final name = (community['name'] as String?) ?? communityId;
        final role = (membershipData['role'] as String?) ?? 'member';
        final members = (community['membersCount'] as num?)?.toInt();
        final currency = (community['currency'] as Map<String, dynamic>?) ?? const {};
        final currencyName = (currency['name'] as String?)?.trim();

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'コミュニティ情報',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kTextMain,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('名前: $name', style: const TextStyle(color: kTextMain)),
              const SizedBox(height: 8),
              if (members != null)
                Text('メンバー数: $members', style: const TextStyle(color: kTextMain)),
              if (currencyName != null && currencyName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('通貨: $currencyName', style: const TextStyle(color: kTextMain)),
              ],
              const SizedBox(height: 8),
              Text('あなたの権限: $role', style: const TextStyle(color: kTextMain)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _createCommunity(context);
                      },
                      child: const Text('新しいコミュニティを作成'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

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

  Future<void> _requestJoinCommunity(
    BuildContext context,
    String communityId,
  ) async {
    setState(() => _processingJoinCommunityId = communityId);
    try {
      final joined = await _communityService.joinCommunity(
        userId: widget.user.uid,
        communityId: communityId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            joined ? 'コミュニティに参加しました' : '参加リクエストを送信しました',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加リクエストを送信できませんでした: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加リクエストを送信できませんでした: $e')),
      );
    } finally {
      if (mounted && _processingJoinCommunityId == communityId) {
        setState(() => _processingJoinCommunityId = null);
      }
    }
  }

  Widget _coverFallback(String title) {
    final t = title.trim();
    final initial = t.isEmpty ? '?' : t[0].toUpperCase();
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: kBrandBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: kBrandBlue,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _showDiscoverCommunityDetail(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final name = (data['name'] as String?) ?? 'コミュニティ';
    final description = (data['description'] as String?)?.trim();
    final members = (data['membersCount'] as num?)?.toInt();
    final currency = (data['currency'] as Map<String, dynamic>?) ?? const {};
    final currencyName = (currency['name'] as String?)?.trim();
    final policy = (data['policy'] as Map<String, dynamic>?) ?? const {};
    final requiresApproval = policy['requiresApproval'] == true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: kTextMain,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (description != null && description.isNotEmpty) ...[
                  Text(
                    description,
                    style: const TextStyle(color: kTextMain),
                  ),
                  const SizedBox(height: 16),
                ],
                if (members != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_outlined, color: kTextSub),
                        const SizedBox(width: 8),
                        Text(
                          'メンバー数: ${members}人',
                          style: const TextStyle(color: kTextMain),
                        ),
                      ],
                    ),
                  ),
                if (currencyName != null && currencyName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_exchange, color: kTextSub),
                        const SizedBox(width: 8),
                        Text(
                          '利用通貨: $currencyName',
                          style: const TextStyle(color: kTextMain),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, color: kTextSub),
                    const SizedBox(width: 8),
                    Text(
                      requiresApproval
                          ? '参加には承認が必要です'
                          : '参加リクエストは自動承認されます',
                      style: const TextStyle(color: kTextMain),
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

  Future<void> _joinCommunityWithCode(BuildContext context, String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コードを入力してください')),
      );
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.doc('communities/$trimmed').get();
      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コミュニティが見つかりませんでした')),
        );
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};
      final name = (data['name'] as String?) ?? trimmed;
      if (!mounted) return;
      await CommunityMemberSelectScreen.open(
        context,
        communityId: trimmed,
        currentUserUid: widget.user.uid,
        communityName: name,
        currentUserRole: 'member',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加に失敗しました: $e')),
      );
    }
  }
  // ====== End of inserted instance methods for UI ======

  @override
  Widget build(BuildContext context) {
    final membershipsQuery = FirebaseFirestore.instance
        .collection('memberships')
        .where('uid', isEqualTo: widget.user.uid);

    // Discover（公開コミュ）: まずは単純に最新順。将来 where('discoverable', isEqualTo: true) を追加
    final discoverQuery =
        FirebaseFirestore.instance.collection('communities').limit(10);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBgLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'コミュニティ',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kTextMain,
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _createCommunity(context),
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(Icons.add, color: kTextMain, size: 26),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'コミュ名・メンバーで検索',
                    prefixIcon: const Icon(Icons.search, color: kTextSub),
                    filled: true,
                    fillColor: kCardWhite,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: kBrandBlue, width: 2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TabBar(
                  labelColor: kBrandBlue,
                  unselectedLabelColor: kTextSub,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  indicatorColor: kBrandBlue,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: '一覧'),
                    Tab(text: 'トーク'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildCommunityList(
                        context, membershipsQuery, discoverQuery),
                    _TalkTab(
                      user: widget.user,
                      talkThreadsQuery: _talkThreadsQuery,
                      pendingRequestsCountStream: _pendingRequestsCountStream,
                      searchKeyword: _searchKeyword,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagChip(String label,
      {Color backgroundColor = const Color(0xFFE0E7FF),
      Color textColor = kBrandBlue}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _communityCard({
    required String title,
    required String subtitle,
    String? coverUrl,
    String? role,
    String? currencyName,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: kTextMain,
                              ),
                            ),
                          ),
                          if (onInfo != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: InkResponse(
                                onTap: onInfo,
                                radius: 20,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE2E8F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: kBrandBlue,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: kTextSub),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (currencyName != null && currencyName.isNotEmpty)
                            _tagChip(currencyName),
                          if (role != null)
                            _RoleChip(role: role),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.people_alt_rounded,
                                size: 16, color: kTextSub),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                  color: kTextSub,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inviteInputRow(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inviteCtrl,
              decoration: InputDecoration(
                hintText: '招待コード / コミュニティID を入力',
                filled: true,
                fillColor: kLightGray,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kBrandBlue, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kBrandBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _joinCommunityWithCode(
                  context, _inviteCtrl.text.trim()),
              child: const Text('参加'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyDiscoverCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '公開中のコミュニティはまだありません',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: kTextMain,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'まずは身近なメンバーとコミュニティを作成してみましょう。',
            style: TextStyle(color: kTextSub),
          ),
        ],
      ),
    );
  }

  Widget _discoverCard(
    Map<String, dynamic> c, {
    required VoidCallback onViewDetail,
    VoidCallback? onRequest,
    required bool isPending,
    required bool isProcessing,
  }) {
    final title = (c['name'] as String?) ?? (c['id'] as String? ?? 'Community');
    final members = (c['membersCount'] as num?)?.toInt();
    final coverUrl = (c['coverUrl'] as String?)?.trim();
    final currency = (c['currency'] as Map<String, dynamic>?) ?? const {};
    final currencyName = (currency['name'] as String?)?.trim();

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

    final requestEnabled =
        onRequest != null && !isPending && !isProcessing;
    final requestBackgroundColor = isProcessing
        ? kBrandBlue
        : requestEnabled
            ? kBrandBlue
            : kLightGray;
    final requestForegroundColor =
        requestEnabled || isProcessing ? Colors.white : kTextSub;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onViewDetail,
        child: Ink(
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kTextMain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (currencyName != null && currencyName.isNotEmpty)
                            _tagChip(currencyName),
                          _tagChip(
                            members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                            backgroundColor: const Color(0xFFF1F5F9),
                            textColor: kTextSub,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kBrandBlue,
                                  side: const BorderSide(color: kBrandBlue),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: onViewDetail,
                                child: const Text('詳細を見る'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: requestBackgroundColor,
                                  foregroundColor: requestForegroundColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: requestEnabled ? onRequest : null,
                                child: isProcessing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        isPending
                                            ? '承認待ち'
                                            : '参加をリクエスト',
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _errorNotice(String message) {
  return Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kCardWhite,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withOpacity(0.2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText.rich(
            _linkifyText(message),
            style: const TextStyle(color: kTextSub),
          ),
        ),
        IconButton(
          tooltip: 'コピー',
          icon: const Icon(Icons.copy_rounded, color: Colors.redAccent),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            // Note: ScaffoldMessenger is not available here, so no snackbar
          },
        ),
      ],
    ),
  );
}

TextSpan _linkifyText(String message) {
  final baseStyle = const TextStyle(color: kTextSub);
  final linkStyle = const TextStyle(
    color: Colors.blue,
    decoration: TextDecoration.underline,
    fontWeight: FontWeight.w600,
  );

  final spans = <InlineSpan>[];
  final urlPattern = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
  int start = 0;
  for (final match in urlPattern.allMatches(message)) {
    if (match.start > start) {
      spans.add(TextSpan(
        text: message.substring(start, match.start),
        style: baseStyle,
      ));
    }
    final matchText = match.group(0)!;
    final trimmed = matchText.replaceFirst(RegExp(r'[,.;)\]]+$'), '');
    final trailing = matchText.substring(trimmed.length);
    spans.add(TextSpan(
      text: trimmed,
      style: linkStyle,
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(trimmed);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
    ));
    if (trailing.isNotEmpty) {
      spans.add(TextSpan(text: trailing, style: baseStyle));
    }
    start = match.end;
  }
  if (start < message.length) {
    spans.add(TextSpan(text: message.substring(start), style: baseStyle));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: message, style: baseStyle));
  }
  return TextSpan(children: spans);
}
