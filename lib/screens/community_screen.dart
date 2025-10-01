import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/community.dart';
import '../models/community.dart';
import 'central_bank_screen.dart';
import 'community_member_select_screen.dart';
import 'community_create_screen.dart';
import 'community_leader_settings_screen.dart';
import 'member_chat_screen.dart';
import 'transactions/transaction_flow_screen.dart';

part 'communities/talk_tab.dart';
part '../widgets/talk/talk_thread_tile.dart';
part '../widgets/talk/talk_filter_chip.dart';
part '../widgets/talk/role_chip.dart';
part '../widgets/talk/empty_loading_error_cards.dart';

// ---- Brand tokens (アプリ全体と統一) ----
const Color kBrandBlue = Color(0xFF2563EB);
const Color kLightGray = Color(0xFFF1F5F9);
const Color kBgLight = Color(0xFFF8FAFC);
const Color kCardWhite = Color(0xFFFFFFFF);
const Color kTextMain = Color(0xFF0F172A);
const Color kTextSub = Color(0xFF64748B);
const Color kAccentOrange = Color(0xFFF59E0B);
const LinearGradient kBrandGrad = LinearGradient(
  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
);

Widget _sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: kTextMain,
      ),
    ),
  );
}

DateTime? _readTimestamp(dynamic value) {
  if (value == null) return null;
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
                for (final doc in sortedDocs) ...[
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .doc('communities/${doc.data()['cid']}')
                        .get(),
                    builder: (context, communitySnap) {
                      if (communitySnap.connectionState ==
                          ConnectionState.waiting) {
                        return _communityCardSkeleton();
                      }
                      final communityData =
                          communitySnap.data?.data() ?? <String, dynamic>{};
                      final title = (communityData['name'] as String?) ??
                          (doc.data()['cid'] as String? ?? 'Community');
                      final members =
                          (communityData['membersCount'] as num?)?.toInt();
                      final coverUrl =
                          (communityData['coverUrl'] as String?)?.trim();
                      final role = (doc.data()['role'] as String?) ?? 'member';
                      return _communityCard(
                        title: title,
                        subtitle: members == null
                            ? 'メンバー数 —'
                            : 'メンバー ${members}人',
                        coverUrl: coverUrl.isEmptyOrNull ? null : coverUrl,
                        role: role,
                        onTap: () => _openCommunitySheet(
                          context,
                          doc.data()['cid'] as String,
                          doc.data(),
                          widget.user,
                          communityData,
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
                  _discoverCard(d.data(), onRequest: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('参加申請は準備中です')),
                    );
                  }),
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
            '招待コードで参加するか、新しいコミュニティを作成してみましょう。',
            style: TextStyle(color: kTextSub),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _createCommunity(context),
                icon: const Icon(Icons.add),
                label: const Text('コミュニティを作成'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _communityCardSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kLightGray,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: kLightGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: kLightGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inviteInputRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inviteCtrl,
            decoration: InputDecoration(
              hintText: '招待コードを入力',
              hintStyle: const TextStyle(color: kTextSub),
              filled: true,
              fillColor: kCardWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kLightGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kLightGray),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBrandBlue, width: 2),
              ),
            ),
            onSubmitted: (code) async {
              await _joinCommunityWithCode(context, code);
            },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_searchKeyword.isNotEmpty) {
      return Scaffold(
        backgroundColor: kBgLight,
        appBar: AppBar(
          title: const Text('コミュニティ'),
          backgroundColor: kBgLight,
          foregroundColor: kTextMain,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'コミュニティを検索',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _searchCtrl.clear();
                    },
                    icon: const Icon(Icons.clear),
                  ),
                  filled: true,
                  fillColor: kCardWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Center(
          child: Text(
            '検索機能は準備中です',
            style: TextStyle(color: kTextSub),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _createCommunity(context);
          },
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      );
    }

    final membershipsQuery = FirebaseFirestore.instance
        .collection('memberships')
        .where('uid', isEqualTo: widget.user.uid);
    final discoverQuery = FirebaseFirestore.instance
        .collection('communities')
        .where('publiclyVisible', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(20);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBgLight,
        appBar: AppBar(
          title: const Text('コミュニティ'),
          backgroundColor: kBgLight,
          foregroundColor: kTextMain,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'コミュニティを検索',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: kCardWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'コミュニティ'),
                    Tab(text: 'トーク'),
                  ],
                  labelColor: kBrandBlue,
                  unselectedLabelColor: kTextSub,
                  indicatorColor: kBrandBlue,
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
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
    required VoidCallback onTap,
  }) {
    Widget leading;
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: kTextMain,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (role != null) ...[
                            const SizedBox(width: 8),
                            _RoleChip(role: role),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: kTextSub,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: kTextSub,
                ),
              ],
            ),
          ),
        ),
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
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
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
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text('コミュニティを開く'),
                  ),
                ),
              ),
            ],
          ),
        ),
      },
    );
  }

  Future<void> _createCommunity(BuildContext context) async {
    final created = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        builder: (_) => CommunityCreateScreen(user: widget.user),
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コミュニティを作成しました')),
      );
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

  Future<void> _joinCommunityWithCode(BuildContext context, String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コードを入力してください')),
      );
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('招待コード機能は準備中です')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    }
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
    required VoidCallback onRequest,
  }) {
    final title = (c['name'] as String?) ?? (c['id'] as String? ?? 'Community');
    final members = (c['membersCount'] as num?)?.toInt();
    final coverUrl = (c['coverUrl'] as String?)?.trim();

    Widget leading;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
                      _tagChip(
                        members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                        backgroundColor: const Color(0xFFF1F5F9),
                        textColor: kTextSub,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 40,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kBrandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onRequest,
                        child: const Text('参加をリクエスト'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String? {
  bool get isEmptyOrNull => this == null || this!.isEmpty;
}