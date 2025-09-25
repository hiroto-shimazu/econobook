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
  final CommunityService _communityService = CommunityService();
  Set<String> _myCommunityIds = <String>{};
  late final Query<Map<String, dynamic>> _talkThreadsQuery;
  late final Stream<int> _pendingRequestsCountStream;
  _TalkFilter? _selectedTalkFilter = _TalkFilter.unread;
  _TalkSort _selectedTalkSort = _TalkSort.unreadFirst;
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

  Widget _buildTalkTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _talkThreadsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorNotice('トークを取得できませんでした: ${snapshot.error}');
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildTalkScaffold(children: [_talkEmptyState()]);
        }

        return FutureBuilder<List<_TalkEntry?>>(
          future: Future.wait(docs.map(_buildTalkEntry)),
          builder: (context, metaSnap) {
            if (metaSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (metaSnap.hasError) {
              return _errorNotice('トークを処理できませんでした: ${metaSnap.error}');
            }
            final entries =
                (metaSnap.data ?? const <_TalkEntry?>[]).whereType<_TalkEntry>().toList();
            if (entries.isEmpty) {
              return _buildTalkScaffold(children: [_talkEmptyState()]);
            }

            final filtered = _applyTalkFilters(entries);
            if (filtered.isEmpty) {
              return _buildTalkScaffold(
                children: [
                  _talkEmptyState(message: '条件に一致するトークがありません'),
                ],
              );
            }

            final pinned = filtered.where((e) => e.isPinned).toList();
            final unread =
                filtered.where((e) => !e.isPinned && e.unreadCount > 0).toList();
            final recent =
                filtered.where((e) => !e.isPinned && e.unreadCount == 0).toList();

            _applyTalkSort(pinned);
            _applyTalkSort(unread);
            _applyTalkSort(recent);

            final content = <Widget>[
              StreamBuilder<int>(
                stream: _pendingRequestsCountStream,
                builder: (context, requestSnap) {
                  final count = requestSnap.data ?? 0;
                  if (count <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PendingRequestBanner(
                        count: count,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('承認待ちリクエスト画面は準備中です')),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              _buildTalkFilters(),
            ];

            void addSection(String title, List<_TalkEntry> items) {
              if (items.isEmpty) return;
              content
                ..add(const SizedBox(height: 24))
                ..add(_sectionHeader(title))
                ..add(const SizedBox(height: 8));
              for (final entry in items) {
                content
                  ..add(_TalkThreadTile(
                    entry: entry,
                    timeLabel: _formatTalkTime(entry.updatedAt),
                    onTap: () => _openThread(context, entry),
                    onTogglePin: () => _togglePin(entry, context),
                  ))
                  ..add(const SizedBox(height: 12));
              }
            }

            addSection('ピン留め', pinned);
            addSection('未読', unread);
            addSection('最近', recent);

            if (pinned.isEmpty && unread.isEmpty && recent.isEmpty) {
              content
                ..add(const SizedBox(height: 32))
                ..add(_talkEmptyState(message: '条件に一致するトークがありません'));
            }

            return _buildTalkScaffold(children: content);
          },
        );
      },
    );
  }

  Widget _buildTalkScaffold({required List<Widget> children}) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      children: children,
    );
  }

  List<_TalkEntry> _applyTalkFilters(List<_TalkEntry> entries) {
    final keyword = _searchKeyword.toLowerCase();
    final filter = _selectedTalkFilter;
    return [
      for (final entry in entries)
        if ((keyword.isEmpty ||
                ('${entry.communityName} ${entry.partnerDisplayName} '
                        '${entry.previewText}')
                    .toLowerCase()
                    .contains(keyword)) &&
            _matchesTalkFilter(filter, entry))
          entry
    ];
  }

  bool _matchesTalkFilter(_TalkFilter? filter, _TalkEntry entry) {
    if (filter == null) return true;
    return switch (filter) {
      _TalkFilter.unread => entry.unreadCount > 0,
      _TalkFilter.mention => entry.hasMention,
      _TalkFilter.active => true,
      _TalkFilter.pinned => entry.isPinned,
    };
  }

  void _applyTalkSort(List<_TalkEntry> entries) {
    switch (_selectedTalkSort) {
      case _TalkSort.unreadFirst:
        entries.sort((a, b) {
          final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
          if (unreadCompare != 0) return unreadCompare;
          final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
        break;
      case _TalkSort.recent:
        entries.sort((a, b) {
          final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
        break;
      case _TalkSort.name:
        entries.sort((a, b) => a.partnerDisplayName
            .toLowerCase()
            .compareTo(b.partnerDisplayName.toLowerCase()));
        break;
    }
  }

  List<_TalkFilterChipData> get _talkFilterChips => const [
        _TalkFilterChipData(
          label: '未読',
          filter: _TalkFilter.unread,
          color: kBrandBlue,
        ),
        _TalkFilterChipData(
          label: 'メンション',
          filter: _TalkFilter.mention,
          color: kAccentOrange,
        ),
        _TalkFilterChipData(
          label: '参加中',
          filter: _TalkFilter.active,
          color: kBrandBlue,
        ),
        _TalkFilterChipData(
          label: 'ピン留め',
          filter: _TalkFilter.pinned,
          color: kBrandBlue,
        ),
      ];

  Widget _buildTalkFilters() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final chip in _talkFilterChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _TalkFilterChip(
                      label: chip.label,
                      isActive: _selectedTalkFilter == chip.filter,
                      color: chip.color,
                      onTap: () {
                        setState(() {
                          if (_selectedTalkFilter == chip.filter) {
                            _selectedTalkFilter = null;
                          } else {
                            _selectedTalkFilter = chip.filter;
                          }
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButton<_TalkSort>(
              value: _selectedTalkSort,
              icon: const Icon(Icons.expand_more, size: 20, color: kTextSub),
              items: const [
                DropdownMenuItem(
                  value: _TalkSort.unreadFirst,
                  child: Text('未読優先'),
                ),
                DropdownMenuItem(
                  value: _TalkSort.recent,
                  child: Text('最近更新'),
                ),
                DropdownMenuItem(
                  value: _TalkSort.name,
                  child: Text('名前順'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedTalkSort = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _talkEmptyState({String message = 'まだトークはありません'}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kBrandBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.chat_bubble_outline, color: kBrandBlue),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: kTextMain,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'メンバーとコミュニケーションを始めましょう。',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextSub),
          ),
        ],
      ),
    );
  }

  Future<_TalkEntry?> _buildTalkEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    try {
      final parentCommunity = doc.reference.parent.parent;
      if (parentCommunity == null) {
        return null;
      }
      final data = doc.data();
      final communityId = parentCommunity.id;
      final communitySnap = await parentCommunity.get();
      final communityData = communitySnap.data() ?? <String, dynamic>{};
      final communityName =
          (communityData['name'] as String?) ?? communityId;
      final communityCover = (communityData['coverUrl'] as String?)?.trim();

      final participants = List<String>.from(
          (data['participants'] as List?) ?? const <String>[]);
      final otherUid = participants.firstWhere(
        (uid) => uid != widget.user.uid,
        orElse: () => '',
      );
      if (otherUid.isEmpty) {
        return null;
      }

      final userSnap =
          await FirebaseFirestore.instance.doc('users/$otherUid').get();
      final userData = userSnap.data() ?? <String, dynamic>{};
      final rawName = (userData['displayName'] as String?)?.trim();
      final displayName =
          (rawName != null && rawName.isNotEmpty) ? rawName : otherUid;
      final photoUrl = (userData['photoUrl'] as String?)?.trim();

      final unreadMap = Map<String, dynamic>.from(
          (data['unreadCounts'] as Map?) ?? const <String, dynamic>{});
      final unreadRaw = unreadMap[widget.user.uid];
      final unread = unreadRaw is num ? unreadRaw.toInt() : 0;

      final pinnedBy = List<String>.from((data['pinnedBy'] as List?) ?? const []);
      final updatedAt = _readTimestamp(data['updatedAt']);
      final lastMessage = (data['lastMessage'] as String?)?.trim() ?? '';
      final lastSenderUid = (data['lastSenderUid'] as String?) ?? '';
      final hasMention = _detectMention(lastMessage, lastSenderUid);

      final previewText = lastMessage.isEmpty
          ? 'メッセージはまだありません'
          : (lastSenderUid == widget.user.uid
              ? 'あなた: $lastMessage'
              : '$displayName: $lastMessage');

      return _TalkEntry(
        threadId: doc.id,
        communityId: communityId,
        communityName: communityName,
        communityCoverUrl: communityCover,
        partnerUid: otherUid,
        partnerDisplayName: displayName,
        partnerPhotoUrl: photoUrl,
        previewText: previewText,
        unreadCount: unread,
        updatedAt: updatedAt,
        hasMention: hasMention,
        isPinned: pinnedBy.contains(widget.user.uid),
      );
    } catch (e) {
      return null;
    }
  }

  bool _detectMention(String message, String senderUid) {
    if (message.isEmpty || senderUid == widget.user.uid) return false;
    final lowerMessage = message.toLowerCase();
    final displayName = widget.user.displayName;
    if (displayName == null || displayName.trim().isEmpty) {
      return lowerMessage.contains('@${widget.user.uid.toLowerCase()}');
    }
    final nameLower = displayName.toLowerCase();
    return lowerMessage.contains('@$nameLower') ||
        lowerMessage.contains('@${widget.user.uid.toLowerCase()}');
  }

  Future<void> _togglePin(_TalkEntry entry, BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('community_chats')
          .doc(entry.communityId)
          .collection('threads')
          .doc(entry.threadId)
          .set({
        'pinnedBy': entry.isPinned
            ? FieldValue.arrayRemove([widget.user.uid])
            : FieldValue.arrayUnion([widget.user.uid]),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ピン留めを変更できませんでした: $e')),
      );
    }
  }

  Future<void> _openThread(BuildContext context, _TalkEntry entry) async {
    try {
      final memberSnap = await FirebaseFirestore.instance
          .doc('memberships/${entry.communityId}_${entry.partnerUid}')
          .get();
      final role = (memberSnap.data()?['role'] as String?) ?? 'member';
      if (!mounted) return;
      await MemberChatScreen.open(
        context,
        communityId: entry.communityId,
        communityName: entry.communityName,
        currentUser: widget.user,
        partnerUid: entry.partnerUid,
        partnerDisplayName: entry.partnerDisplayName,
        partnerPhotoUrl: entry.partnerPhotoUrl,
        threadId: entry.threadId,
        memberRole: role,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットを開けませんでした: $e')),
      );
    }
  }

  String? _formatTalkTime(DateTime? time) {
    if (time == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(time.year, time.month, time.day);
    if (target == today) {
      final hours = time.hour.toString().padLeft(2, '0');
      final minutes = time.minute.toString().padLeft(2, '0');
      return '$hours:$minutes';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (target == yesterday) {
      return '昨日';
    }
    if (now.year == time.year) {
      return '${time.month}/${time.day}';
    }
    return '${time.year}/${time.month}/${time.day}';
  }

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
                    _buildTalkTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== UI Parts =====
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

  Widget _loadingState() {
    return Column(
      children: [
        for (int i = 0; i < 2; i++) ...[
          Container(
            margin: EdgeInsets.only(bottom: i == 1 ? 0 : 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCardWhite,
              borderRadius: BorderRadius.circular(20),
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
          ),
        ]
      ],
    );
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
            child: Text(
              message,
              style: const TextStyle(color: kTextSub),
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

  Widget _discoverCard(Map<String, dynamic> c,
      {required VoidCallback onRequest}) {
    final title = (c['name'] as String?) ?? (c['id'] as String? ?? 'Community');
    final members = (c['membersCount'] as num?)?.toInt();
    final cover = (c['coverUrl'] as String?);
    final description = (c['description'] as String?)?.trim();

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover != null && cover.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  members == null ? 'メンバー数 —' : 'メンバー ${members}人',
                  style: const TextStyle(color: kTextSub, fontSize: 13),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(color: kTextSub, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onRequest,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBrandBlue, width: 1.5),
              foregroundColor: kBrandBlue,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('申請'),
          ),
        ],
      ),
    );
  }

  Widget _coverFallback(String title) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: kTextMain,
        ),
      ),
    );
  }

  Widget _emptyMyCommunities(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kLightGray,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.groups_outlined,
                size: 36, color: kTextSub),
          ),
          const SizedBox(height: 20),
          const Text(
            'まだコミュニティがありません',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kTextMain,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '招待コードで参加するか、新しくコミュニティを作成しましょう。',
            style: TextStyle(color: kTextSub),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kBrandBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => _joinCommunityDialog(context),
              child: const Text('招待コードを入力'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE2E8F0),
                foregroundColor: kTextMain,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => _createCommunity(context),
              child: const Text('新しいコミュニティを作成'),
            ),
          ),
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
            final membershipHasBankPermission =
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
                final canManageBank =
                    membershipHasBankPermission || ownerUid == widget.user.uid;

                Future<void> handleBankSettings() async {
                  if (canManageBank) {
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
                            canManageBank: canManageBank,
                          ),
                          const SizedBox(height: 24),
                          const _SectionHeader(title: '通貨・中央銀行設定'),
                          const SizedBox(height: 8),
                          _CentralBankLinkCard(
                            currency: currency,
                            requiresApproval: policy.requiresApproval,
                            allowMinting: currency.allowMinting,
                            onOpen: handleBankSettings,
                            canManage: canManageBank,
                          ),
                          if (!canManageBank) ...[
                            const SizedBox(height: 8),
                            const Text(
                              '中央銀行の設定はコミュニティから管理できます。必要な場合は変更をリクエストしてください。',
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

enum _TalkFilter { unread, mention, active, pinned }

enum _TalkSort { unreadFirst, recent, name }

class _TalkFilterChipData {
  const _TalkFilterChipData({
    required this.label,
    required this.filter,
    required this.color,
  });

  final String label;
  final _TalkFilter filter;
  final Color color;
}

class _TalkFilterChip extends StatelessWidget {
  const _TalkFilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final background = isActive ? color : Colors.white;
    final textColor = isActive ? Colors.white : kTextMain;
    final borderColor = isActive ? color : const Color(0xFFE2E8F0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingRequestBanner extends StatelessWidget {
  const _PendingRequestBanner({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBrandBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBrandBlue.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kBrandBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.info_outline,
              color: kBrandBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: '$count件',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kTextMain,
                ),
                children: const [
                  TextSpan(
                    text: 'の承認待ち依頼があります。',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13, color: kTextMain),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: kBrandBlue,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('確認する'),
          ),
        ],
      ),
    );
  }
}

class _TalkEntry {
  const _TalkEntry({
    required this.threadId,
    required this.communityId,
    required this.communityName,
    this.communityCoverUrl,
    required this.partnerUid,
    required this.partnerDisplayName,
    this.partnerPhotoUrl,
    required this.previewText,
    required this.unreadCount,
    this.updatedAt,
    required this.hasMention,
    required this.isPinned,
  });

  final String threadId;
  final String communityId;
  final String communityName;
  final String? communityCoverUrl;
  final String partnerUid;
  final String partnerDisplayName;
  final String? partnerPhotoUrl;
  final String previewText;
  final int unreadCount;
  final DateTime? updatedAt;
  final bool hasMention;
  final bool isPinned;
}

class _TalkThreadTile extends StatelessWidget {
  const _TalkThreadTile({
    required this.entry,
    required this.timeLabel,
    required this.onTap,
    required this.onTogglePin,
  });

  final _TalkEntry entry;
  final String? timeLabel;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = entry.isPinned
        ? kBrandBlue.withOpacity(0.1)
        : entry.unreadCount > 0
            ? kBrandBlue.withOpacity(0.08)
            : kCardWhite;
    final borderColor = entry.isPinned
        ? kBrandBlue.withOpacity(0.4)
        : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: entry.isPinned || entry.unreadCount > 0
                ? [
                    BoxShadow(
                      color: kBrandBlue.withOpacity(0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TalkAvatar(
                name: entry.partnerDisplayName,
                photoUrl: entry.partnerPhotoUrl,
                fallbackBackground: entry.communityCoverUrl,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            entry.communityName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kTextSub,
                            ),
                          ),
                        ),
                        if (timeLabel != null)
                          Text(
                            timeLabel!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: kTextSub,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.partnerDisplayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kTextMain,
                            ),
                          ),
                        ),
                        if (entry.hasMention)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: kAccentOrange,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '@',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: kTextSub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onTogglePin,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    icon: Icon(
                      entry.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 20,
                      color: entry.isPinned ? kBrandBlue : kTextSub,
                    ),
                  ),
                  if (entry.unreadCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kBrandBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        entry.unreadCount > 99
                            ? '99+'
                            : entry.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TalkAvatar extends StatelessWidget {
  const _TalkAvatar({
    required this.name,
    this.photoUrl,
    this.fallbackBackground,
  });

  final String name;
  final String? photoUrl;
  final String? fallbackBackground;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    DecorationImage? image;
    if (hasPhoto) {
      image = DecorationImage(
        image: NetworkImage(photoUrl!),
        fit: BoxFit.cover,
      );
    } else if (fallbackBackground != null && fallbackBackground!.isNotEmpty) {
      image = DecorationImage(
        image: NetworkImage(fallbackBackground!),
        fit: BoxFit.cover,
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: kBrandBlue.withOpacity(0.1),
        image: image,
      ),
      child: (image == null)
          ? Center(
              child: Text(
                name.isNotEmpty
                    ? name.characters.first.toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: kBrandBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
    );
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
    final (Color bg, Color textColor) = switch (role) {
      'owner' => (const Color(0xFFE2E8F0), kTextMain),
      'admin' => (const Color(0xFFE2E8F0), kTextSub),
      'mediator' => (const Color(0xFFEDE9FE), Color(0xFF6D28D9)),
      'pending' => (kAccentOrange.withOpacity(0.15), kAccentOrange),
      _ => (const Color(0xFFE2E8F0), kTextSub),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
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
                canManageBank ? '中央銀行（コミュニティ）' : '中央銀行を見る',
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
        canManage ? '中央銀行を開く' : 'コミュニティで中央銀行を見る';
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
        final sortedDocs = docs.toList()
          ..sort((a, b) => _compareJoinedAtDesc(a.data(), b.data()));
        if (sortedDocs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('メンバーがまだいません'),
          );
        }
        return Column(
          children: [
            for (final doc in sortedDocs)
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
