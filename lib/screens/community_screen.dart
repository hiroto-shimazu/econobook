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
import 'community_member_select_screen.dart';
import 'community_create_screen.dart';
import 'community_leader_settings_screen.dart';
import 'member_chat_screen.dart';
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

// ====== Inserted enums, data classes, and widgets for community_screen ======
enum _TalkFilter { unread, mention, active, pinned }
enum _TalkSort { unreadFirst, recent, name }

class _TalkFilterChipData {
  final String label;
  final _TalkFilter filter;
  final Color color;
  const _TalkFilterChipData({
    required this.label,
    required this.filter,
    required this.color,
  });
}

class _TalkEntry {
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

  const _TalkEntry({
    required this.threadId,
    required this.communityId,
    required this.communityName,
    required this.communityCoverUrl,
    required this.partnerUid,
    required this.partnerDisplayName,
    required this.partnerPhotoUrl,
    required this.previewText,
    required this.unreadCount,
    required this.updatedAt,
    required this.hasMention,
    required this.isPinned,
  });
}

class _TalkFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;
  const _TalkFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.12) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? color : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isActive ? color : kTextSub,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _TalkThreadTile extends StatelessWidget {
  final _TalkEntry entry;
  final String? timeLabel;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  const _TalkThreadTile({
    super.key,
    required this.entry,
    required this.timeLabel,
    required this.onTap,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _avatar(entry),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.partnerDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kTextMain,
                              ),
                            ),
                          ),
                          if (timeLabel != null)
                            Text(
                              timeLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kTextSub,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: kTextSub,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (entry.isPinned)
                            const Icon(Icons.push_pin, size: 14, color: kTextSub),
                          if (entry.isPinned) const SizedBox(width: 8),
                          if (entry.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kBrandBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${entry.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              entry.isPinned ? Icons.star : Icons.star_border,
                              size: 20,
                              color: entry.isPinned ? kAccentOrange : kTextSub,
                            ),
                            onPressed: onTogglePin,
                            tooltip: entry.isPinned ? 'ピンを外す' : 'ピン留め',
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

  Widget _avatar(_TalkEntry e) {
    if (e.partnerPhotoUrl != null && e.partnerPhotoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          e.partnerPhotoUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kBrandBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.person_outline, color: kBrandBlue),
    );
  }
}

class _PendingRequestBanner extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;
  const _PendingRequestBanner({super.key, required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, color: kAccentOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '承認待ちのリクエストが ${count} 件あります',
              style: const TextStyle(
                color: kTextMain,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            child: const Text('確認する'),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      'owner' => 'リーダー',
      'admin' => '管理',
      'member' => 'メンバー',
      _ => role,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kBrandBlue,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ====== End of inserted enums, data classes, and widgets ======

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
  bool _leaving = false;
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

  // ====== Inserted instance methods for UI ======
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

  Widget _discoverCard(
    Map<String, dynamic> c, {
    required VoidCallback onRequest,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onRequest,
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
        ),
      ),
    );
  }
}