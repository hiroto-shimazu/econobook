// lib/screens/community_member_select_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/community.dart';
import '../models/membership.dart';

const Color _kMainBlue = Color(0xFF2563EB);
const Color _kSubGreen = Color(0xFF16A34A);
const Color _kAccentOrange = Color(0xFFF59E0B);
const Color _kBgLight = Color(0xFFF8FAFC);
const Color _kTextMain = Color(0xFF0F172A);
const Color _kTextSub = Color(0xFF64748B);

/// 表示中のメンバーに適用するフィルター条件。
enum MemberFilter {
  all,
  admin,
  pending,
  bankManagers,
  minors,
}

/// 表示順の選択肢。
enum MemberSortOption {
  recent,
  name,
  balance,
  trust,
}

enum _CommunityDashboardTab {
  overview,
  talk,
  wallet,
  members,
  settings,
  bank,
}

extension _CommunityDashboardTabLabel on _CommunityDashboardTab {
  String get label {
    switch (this) {
      case _CommunityDashboardTab.overview:
        return '概要';
      case _CommunityDashboardTab.talk:
        return 'トーク';
      case _CommunityDashboardTab.wallet:
        return 'ウォレット';
      case _CommunityDashboardTab.members:
        return 'メンバー';
      case _CommunityDashboardTab.settings:
        return 'コミュ設定';
      case _CommunityDashboardTab.bank:
        return 'バンク';
    }
  }

  IconData get icon {
    switch (this) {
      case _CommunityDashboardTab.overview:
        return Icons.dashboard_outlined;
      case _CommunityDashboardTab.talk:
        return Icons.forum_outlined;
      case _CommunityDashboardTab.wallet:
        return Icons.account_balance_wallet_outlined;
      case _CommunityDashboardTab.members:
        return Icons.groups_2_outlined;
      case _CommunityDashboardTab.settings:
        return Icons.settings_outlined;
      case _CommunityDashboardTab.bank:
        return Icons.account_balance_outlined;
    }
  }
}

class CommunityMemberSelectScreen extends StatefulWidget {
  const CommunityMemberSelectScreen({
    super.key,
    required this.communityId,
    required this.currentUserUid,
    this.initialCommunityName,
    this.currentUserRole,
  });

  final String communityId;
  final String currentUserUid;
  final String? initialCommunityName;
  final String? currentUserRole;

  /// シンプルに `Navigator` で画面を開くためのヘルパー。
  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required String currentUserUid,
    String? communityName,
    String? currentUserRole,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityMemberSelectScreen(
          communityId: communityId,
          currentUserUid: currentUserUid,
          initialCommunityName: communityName,
          currentUserRole: currentUserRole,
        ),
      ),
    );
  }

  @override
  State<CommunityMemberSelectScreen> createState() =>
      _CommunityMemberSelectScreenState();
}

class _CommunityMemberSelectScreenState
    extends State<CommunityMemberSelectScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _communitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _membersSubscription;

  Community? _community;
  String? _communityError;

  List<_SelectableMember> _members = <_SelectableMember>[];
  String? _membersError;
  bool _membersLoading = true;
  int _membersUpdateToken = 0;

  MemberFilter _activeFilter = MemberFilter.all;
  MemberSortOption _sortOption = MemberSortOption.recent;
  String _searchQuery = '';
  final Set<String> _selectedUids = <String>{};

  final Map<_CommunityDashboardTab, GlobalKey> _sectionKeys = {
    for (final tab in _CommunityDashboardTab.values) tab: GlobalKey(),
  };
  _CommunityDashboardTab _activeDashboardTab =
      _CommunityDashboardTab.overview;


  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() => _searchQuery = query);
      }
    });
    _subscribeCommunity();
    _subscribeMembers();
  }

  @override
  void dispose() {
    _communitySubscription?.cancel();
    _membersSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDashboardTabSelected(_CommunityDashboardTab tab) {
    if (_activeDashboardTab != tab) {
      setState(() => _activeDashboardTab = tab);
    }
    _scrollToSection(tab);
  }

  void _scrollToSection(_CommunityDashboardTab tab) {
    final targetKey = _sectionKeys[tab];
    final context = targetKey?.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToSection(tab);
        }
      });
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      alignment: 0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  Widget _buildOverviewSection(num selectedBalance, String currencyCode) {
    final totalMembers = _members.length;
    final selectedCount = _selectedUids.length;
    final minorCount =
        _members.where((member) => member.profile?.minor == true).length;
    final pendingCount = _pendingCount;
    final selectionText = selectedCount > 0
        ? '選択中: $selectedCount人 · 合計残高 ${selectedBalance.toStringAsFixed(2)} $currencyCode'
        : 'まだメンバーは選択されていません。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.dashboard_customize_outlined,
          title: 'コミュニティ概要',
        ),
        const SizedBox(height: 16),
        _OverviewCards(
          totalMembers: totalMembers,
          pendingCount: pendingCount,
          bankManagerCount: _bankManagerCount,
          minorCount: minorCount,
        ),
        const SizedBox(height: 20),
        _InfoPanel(
          icon: Icons.calendar_month,
          title: '今月のまとめ',
          lines: [
            'メンバー総数: ${totalMembers}人',
            selectionText,
            '中央銀行権限: ${_bankManagerCount}人 · 未成年: ${minorCount}人',
          ],
        ),
        const SizedBox(height: 16),
        _InfoPanel(
          icon: Icons.pending_actions,
          iconColor: _kAccentOrange,
          backgroundColor: _kAccentOrange.withOpacity(0.12),
          title: '承認待ちステータス',
          lines: [
            if (pendingCount > 0)
              '承認待ちリクエストが${pendingCount}件あります。'
            else
              '現在承認待ちの依頼はありません。',
            '承認キューからレビューや承認を実行できます。',
          ],
          actionLabel: pendingCount > 0 ? 'キューを開く' : null,
          onAction: pendingCount > 0
              ? () => _showNotImplemented('承認キュー')
              : null,
        ),
        const SizedBox(height: 16),
        _InfoPanel(
          icon: Icons.timeline,
          iconColor: _kSubGreen,
          backgroundColor: _kSubGreen.withOpacity(0.12),
          title: '最近のトーク / 取引',
          lines: const [
            '最新のトピックや取引の概要を下のタブから確認できます。',
            '詳しく見るには「トーク」「ウォレット」タブをタップしてください。',
          ],
          actionLabel: 'トークへ移動',
          onAction: () =>
              _handleDashboardTabSelected(_CommunityDashboardTab.talk),
        ),
      ],
    );
  }

  Widget _buildTalkSection() {
    const talkItems = [
      _TalkItem(
        channel: '#general',
        snippet: '鈴木: 今日のランチどうしますか？',
        timeLabel: '10:24',
        unreadCount: 3,
      ),
      _TalkItem(
        channel: '#settlement',
        snippet: '@佐藤: 会費の承認お願いします',
        timeLabel: '昨日',
      ),
      _TalkItem(
        channel: '#research',
        snippet: '田中: 新しい論文ドラフトを共有しました。',
        timeLabel: '2日前',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.forum_outlined,
          title: 'トーク',
          color: _kMainBlue,
        ),
        const SizedBox(height: 16),
        for (final item in talkItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(
              leading: const _RoundIcon(
                icon: Icons.tag,
                backgroundColor: Color(0xFFF1F5F9),
                foregroundColor: _kTextSub,
              ),
              title: Text(
                item.channel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kTextMain,
                ),
              ),
              subtitle: Text(
                item.snippet,
                style: const TextStyle(
                  fontSize: 13,
                  color: _kTextSub,
                ),
              ),
              trailing: _TalkTrailing(
                timeLabel: item.timeLabel,
                unreadCount: item.unreadCount,
              ),
              onTap: () => _showNotImplemented('チャンネル ${item.channel}'),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _showNotImplemented('トーク'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('トーク一覧を開く'),
          ),
        ),
      ],
    );
  }

  Widget _buildWalletSection(String currencyCode) {
    final walletItems = [
      _WalletItem(
        title: '研究会会費',
        counterparty: '山田太郎',
        amount: 2500.0,
        timeLabel: '今日 09:12',
        type: WalletActivityType.deposit,
      ),
      _WalletItem(
        title: '備品購入',
        counterparty: '佐藤花子',
        amount: 1200.0,
        timeLabel: '昨日',
        type: WalletActivityType.withdrawal,
      ),
      _WalletItem(
        title: '部室ドリンク補充',
        counterparty: '小林',
        amount: 800.0,
        timeLabel: '3日前',
        type: WalletActivityType.withdrawal,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.account_balance_wallet_outlined,
          title: 'ウォレット',
          color: _kSubGreen,
        ),
        const SizedBox(height: 16),
        for (final item in walletItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(
              leading: _RoundIcon(
                icon: item.type == WalletActivityType.deposit
                    ? Icons.south_west
                    : Icons.north_east,
                backgroundColor: item.type == WalletActivityType.deposit
                    ? const Color(0xFFE0F2FE)
                    : const Color(0xFFFFE4E6),
                foregroundColor: item.type == WalletActivityType.deposit
                    ? _kMainBlue
                    : const Color(0xFFDC2626),
              ),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kTextMain,
                ),
              ),
              subtitle: Text(
                '${item.counterparty} · ${item.timeLabel}',
                style: const TextStyle(fontSize: 13, color: _kTextSub),
              ),
              trailing: Text(
                '${item.type == WalletActivityType.deposit ? '+' : '-'}${item.amount.toStringAsFixed(0)} $currencyCode',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: item.type == WalletActivityType.deposit
                      ? _kSubGreen
                      : const Color(0xFFDC2626),
                ),
              ),
              onTap: () => _showNotImplemented(item.title),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _showNotImplemented('ウォレット'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('ウォレットを開く'),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    const settings = [
      _SettingsItem(
        icon: Icons.edit_outlined,
        title: 'コミュニティプロフィール',
        description: 'カバー画像や説明文、タグを編集します。',
      ),
      _SettingsItem(
        icon: Icons.admin_panel_settings_outlined,
        title: 'メンバー権限',
        description: '管理者・中央銀行権限・モデレーターを設定。',
      ),
      _SettingsItem(
        icon: Icons.notifications_active_outlined,
        title: '通知ルール',
        description: '承認待ちや重大トピックの通知を調整します。',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.settings_outlined,
          title: 'コミュ設定',
          color: _kTextSub,
        ),
        const SizedBox(height: 16),
        for (final item in settings)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(
              leading: _RoundIcon(
                icon: item.icon,
                backgroundColor: const Color(0xFFF1F5F9),
                foregroundColor: _kTextMain,
              ),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kTextMain,
                ),
              ),
              subtitle: Text(
                item.description,
                style: const TextStyle(fontSize: 13, color: _kTextSub),
              ),
              trailing: const Icon(Icons.chevron_right, color: _kTextSub),
              onTap: () => _showNotImplemented(item.title),
            ),
          ),
      ],
    );
  }

  Widget _buildBankSection(String currencyCode) {
    const bankActions = [
      _BankAction(
        icon: Icons.payments_outlined,
        title: '一括送金リクエスト',
        description: '選択したメンバーへボーナスや報酬をまとめて送金。',
      ),
      _BankAction(
        icon: Icons.lock_reset,
        title: '残高調整 / 凍結',
        description: '規約違反時の残高調整やウォレット凍結を実施。',
      ),
      _BankAction(
        icon: Icons.bar_chart_outlined,
        title: '経済インサイト',
        description: '取引量や貯蓄額の推移を可視化します。',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.account_balance_outlined,
          title: 'バンク',
          color: _kMainBlue,
        ),
        const SizedBox(height: 16),
        Text(
          '通貨: $currencyCode',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _kTextSub,
          ),
        ),
        const SizedBox(height: 12),
        for (final action in bankActions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(
              leading: _RoundIcon(
                icon: action.icon,
                backgroundColor: const Color(0xFFEFF6FF),
                foregroundColor: _kMainBlue,
              ),
              title: Text(
                action.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kTextMain,
                ),
              ),
              subtitle: Text(
                action.description,
                style: const TextStyle(fontSize: 13, color: _kTextSub),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: _kTextSub),
              onTap: () => _showNotImplemented(action.title),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _showNotImplemented('バンクダッシュボード'),
            icon: const Icon(Icons.account_balance),
            label: const Text('中央銀行ダッシュボード'),
          ),
        ),
      ],
    );
  }

  void _subscribeCommunity() {
    _communitySubscription = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.communityId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (!snap.exists) return;
      try {
        final community = Community.fromSnapshot(snap);
        setState(() {
          _community = community;
          _communityError = null;
        });
      } catch (e, stack) {
        debugPrint('Failed to parse community snapshot: $e\n$stack');
        setState(() =>
            _communityError = 'コミュニティ情報の取得に失敗しました (${e.toString()})');
      }
    }, onError: (error) {
      if (!mounted) return;
      setState(() =>
          _communityError = 'コミュニティ情報の取得に失敗しました (${error.toString()})');
    });
  }

  void _subscribeMembers() {
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    final query = FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: widget.communityId);
    _membersSubscription = query.snapshots().listen(
      (snapshot) => _handleMembersSnapshot(snapshot.docs),
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _membersError = 'メンバーを取得できませんでした (${error.toString()})';
          _membersLoading = false;
        });
      },
    );
  }

  Future<void> _handleMembersSnapshot(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final token = ++_membersUpdateToken;
    final memberships = docs
        .map((doc) => Membership.fromMap(id: doc.id, data: doc.data()))
        .toList();

    setState(() {
      _membersLoading = true;
      _membersError = null;
    });

    try {
      final profiles = await _loadProfiles(
        memberships.map((m) => m.userId).where((id) => id.isNotEmpty).toSet(),
      );
      if (!mounted || token != _membersUpdateToken) {
        return;
      }
      final members = memberships
          .map((membership) => _SelectableMember(
                membership: membership,
                profile: profiles[membership.userId],
              ))
          .toList();
      setState(() {
        _members = members;
        _membersLoading = false;
        _selectedUids
            .removeWhere((uid) => !members.any((m) => m.membership.userId == uid));
      });
    } catch (e, stack) {
      debugPrint('Failed to load member profiles: $e\n$stack');
      if (!mounted || token != _membersUpdateToken) {
        return;
      }
      setState(() {
        _membersError = 'メンバー情報の取得に失敗しました (${e.toString()})';
        _membersLoading = false;
      });
    }
  }

  Future<Map<String, AppUser>> _loadProfiles(Set<String> uids) async {
    if (uids.isEmpty) return <String, AppUser>{};
    final firestore = FirebaseFirestore.instance;
    final List<String> list = uids.toList();
    final result = <String, AppUser>{};
    const chunkSize = 10; // Firestore whereIn の制限に合わせる
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, min(i + chunkSize, list.length));
      try {
        final snap = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          try {
            result[doc.id] = AppUser.fromSnapshot(doc);
          } catch (e) {
            debugPrint('Failed to parse user profile ${doc.id}: $e');
          }
        }
      } on FirebaseException catch (e) {
        debugPrint('Failed to load user chunk: $e');
      }
    }
    return result;
  }

  List<_SelectableMember> get _visibleMembers {
    final query = _searchQuery.toLowerCase();
    final filtered = _members.where((member) {
      if (!_applyFilter(member)) return false;
      if (query.isEmpty) return true;
      final text = '${member.displayName} ${member.membership.userId}'
          .toLowerCase();
      return text.contains(query);
    }).toList();
    filtered.sort(_sortComparator);
    return filtered;
  }

  bool _applyFilter(_SelectableMember member) {
    switch (_activeFilter) {
      case MemberFilter.all:
        return true;
      case MemberFilter.admin:
        return member.isAdmin;
      case MemberFilter.pending:
        return member.isPending;
      case MemberFilter.bankManagers:
        return member.membership.canManageBank;
      case MemberFilter.minors:
        return member.profile?.minor == true;
    }
  }

  int _sortComparator(_SelectableMember a, _SelectableMember b) {
    switch (_sortOption) {
      case MemberSortOption.recent:
        final aDate = a.membership.joinedAt;
        final bDate = b.membership.joinedAt;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      case MemberSortOption.name:
        return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
      case MemberSortOption.balance:
        return b.membership.balance.compareTo(a.membership.balance);
      case MemberSortOption.trust:
        return b.trustScore.compareTo(a.trustScore);
    }
  }

  List<_SelectableMember> get _selectedMembers => _members
      .where((member) => _selectedUids.contains(member.membership.userId))
      .toList();

  int get _pendingCount =>
      _members.where((member) => member.isPending).length;

  int get _bankManagerCount =>
      _members.where((member) => member.membership.canManageBank).length;

  Future<void> _refresh() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('memberships')
          .where('cid', isEqualTo: widget.communityId)
          .get();
      await _handleMembersSnapshot(snapshot.docs);
    } catch (e, stack) {
      debugPrint('Refresh failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最新のメンバーを取得できませんでした: $e')),
      );
    }
  }

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  void _selectAllVisible() {
    final visible = _visibleMembers;
    setState(() {
      for (final member in visible) {
        _selectedUids.add(member.membership.userId);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedUids.clear());
  }

  void _changeFilter(MemberFilter filter) {
    setState(() => _activeFilter = filter);
  }

  void _changeSort(MemberSortOption option) {
    setState(() => _sortOption = option);
  }

  void _showMemberDetail(_SelectableMember member) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final joinedAt = member.membership.joinedAt;
        final currencyCode =
            _community?.currency.code ?? member.membership.communityId;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MemberAvatar(member: member, size: 52),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _kTextMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${member.membership.userId}',
                            style: const TextStyle(color: _kTextSub),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '選択状態を切り替え',
                      icon: Icon(
                        _selectedUids.contains(member.membership.userId)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _selectedUids.contains(member.membership.userId)
                            ? _kMainBlue
                            : _kTextSub,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _toggleSelection(member.membership.userId);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _buildMemberChips(member),
                ),
                const SizedBox(height: 16),
                _DetailTile(
                  icon: Icons.event,
                  title: '参加日',
                  value: joinedAt == null
                      ? '不明'
                      : _formatDate(joinedAt),
                ),
                _DetailTile(
                  icon: Icons.account_balance_wallet,
                  title: '残高',
                  value:
                      '${member.membership.balance.toStringAsFixed(2)} $currencyCode',
                ),
                _DetailTile(
                  icon: Icons.shield_moon,
                  title: '信頼スコア',
                  value: '${member.trustScore.toStringAsFixed(0)}%',
                ),
                _DetailTile(
                  icon: Icons.task_alt,
                  title: '完了率',
                  value: '${(member.profile?.completionRate ?? 0).toStringAsFixed(0)}%',
                ),
                _DetailTile(
                  icon: Icons.report_problem,
                  title: 'トラブル率',
                  value: '${(member.profile?.disputeRate ?? 0).toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _toggleSelection(member.membership.userId);
                        },
                        child: Text(
                          _selectedUids.contains(member.membership.userId)
                              ? '選択を解除'
                              : 'このメンバーを選択',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${member.displayName} への連絡は近日対応予定です。',
                              ),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _kMainBlue,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('直接連絡'),
                      ),
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

  void _showBulkActionSheet() {
    if (_selectedUids.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '一括アクション (${_selectedUids.length}名)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kTextMain,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('選択中メンバーにメッセージ'),
                  subtitle: const Text('近日中に個別チャットへ飛べるようにする予定です'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showNotImplemented('メッセージ送信');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user),
                  title: const Text('中央銀行権限の付与'),
                  subtitle: const Text('権限変更フローは近日対応予定です'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showNotImplemented('中央銀行権限の変更');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1),
                  title: const Text('コミュニティから外す'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showNotImplemented('メンバー削除');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNotImplemented(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature は現在準備中です。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final communityName = _community?.name ??
        widget.initialCommunityName ??
        widget.communityId;
    final members = _visibleMembers;
    final selectedMembers = _selectedMembers;
    final selectedBalance = selectedMembers.fold<num>(
        0, (sum, m) => sum + m.membership.balance);
    final currencyCode = _community?.currency.code ?? 'PTS';

    return Scaffold(
      backgroundColor: _kBgLight,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeaderSection(
                      community: _community,
                      communityNameFallback: communityName,
                      currentRole: widget.currentUserRole,
                      memberCount: _members.length,
                      pendingCount: _pendingCount,
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildFilterSection(theme)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTabHeaderDelegate(
                      activeTab: _activeDashboardTab,
                      onSelected: _handleDashboardTabSelected,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.overview],
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child:
                          _buildOverviewSection(selectedBalance, currencyCode),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.talk],
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: _buildTalkSection(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.wallet],
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: _buildWalletSection(currencyCode),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.members],
                      child: _buildFilterSection(theme),
                    ),
                  ),
                  if (_membersLoading && _members.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (_membersError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                        child: _ErrorCard(
                          message: _membersError!,
                          onRetry: _refresh,
                        ),
                      ),
                    )
                  else if (members.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 48, 20, 120),
                        child: _EmptyState(),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final member = members[index];
                          final selected =
                              _selectedUids.contains(member.membership.userId);
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: _MemberCard(
                              member: member,
                              selected: selected,
                              currencyCode: currencyCode,
                              onTap: () => _toggleSelection(
                                  member.membership.userId),
                              onTap: () =>
                                  _toggleSelection(member.membership.userId),

                              onDetail: () => _showMemberDetail(member),
                            ),
                          );
                        },
                        childCount: members.length,
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.settings],
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                      child: _buildSettingsSection(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      key: _sectionKeys[_CommunityDashboardTab.bank],
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                      child: _buildBankSection(currencyCode),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 140)),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SelectionSummaryBar(
                selectedCount: _selectedUids.length,
                totalMembers: _members.length,
                totalBalance: selectedBalance,
                currencyCode: currencyCode,
                onSelectAll: _selectAllVisible,
                onClear: _clearSelection,
                onBulkAction: _showBulkActionSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'メンバーを検索',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in MemberFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(filter)),
                      selected: _activeFilter == filter,
                      onSelected: (_) => _changeFilter(filter),
                      selectedColor: _kMainBlue.withOpacity(0.12),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _activeFilter == filter
                            ? _kMainBlue
                            : _kTextSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<MemberSortOption>(
                  tooltip: '表示順',
                  onSelected: _changeSort,
                  itemBuilder: (context) => [
                    for (final option in MemberSortOption.values)
                      PopupMenuItem(
                        value: option,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_sortOption == option)
                              const Icon(Icons.check, size: 18)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(_sortLabel(option)),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 18, color: _kTextSub),
                        const SizedBox(width: 6),
                        Text(
                          _sortLabel(_sortOption),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _kTextMain,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _OverviewCards(
            totalMembers: _members.length,
            pendingCount: _pendingCount,
            bankManagerCount: _bankManagerCount,
            minorCount:
                _members.where((m) => m.profile?.minor == true).length,
          ),
        ],
      ),
    );
  }

  String _filterLabel(MemberFilter filter) {
    switch (filter) {
      case MemberFilter.all:
        return 'すべて';
      case MemberFilter.admin:
        return '管理者';
      case MemberFilter.pending:
        return '承認待ち';
      case MemberFilter.bankManagers:
        return '中央銀行権限';
      case MemberFilter.minors:
        return '未成年';
    }
  }

  String _sortLabel(MemberSortOption option) {
    switch (option) {
      case MemberSortOption.recent:
        return '新しい順';
      case MemberSortOption.name:
        return '名前順';
      case MemberSortOption.balance:
        return '残高が多い順';
      case MemberSortOption.trust:
        return '信頼度が高い順';
    }
  }
}

class _SelectableMember {
  const _SelectableMember({required this.membership, this.profile});

  final Membership membership;
  final AppUser? profile;

  String get displayName {
    final name = profile?.displayName.trim();
    if (name != null && name.isNotEmpty) return name;
    return membership.userId;
  }

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    if (name.length >= 2) {
      return name.substring(0, 2).toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  bool get isPending => membership.pending || membership.role == 'pending';

  bool get isAdmin =>
      membership.role == 'owner' || membership.role == 'admin';

  double get trustScore => profile?.trustScore ?? 0;
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.community,
    required this.communityNameFallback,
    required this.currentRole,
    required this.memberCount,
    required this.pendingCount,
  });

  final Community? community;
  final String communityNameFallback;
  final String? currentRole;
  final int memberCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final coverUrl = community?.coverUrl;
    final iconLetter = (community?.name.isNotEmpty == true)
        ? community!.name.characters.first
        : communityNameFallback.characters.first;
    final currency = community?.currency.code ?? 'PTS';
    final roleLabel = _roleLabel(currentRole ?? 'member');
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  image: coverUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(coverUrl),
                          fit: BoxFit.cover,
                        ),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black45],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black26,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ],
          ),
          Container(
            transform: Matrix4.translationValues(0, -48, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      iconLetter,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _kMainBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  community?.name ?? communityNameFallback,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _kTextMain,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'メンバー $memberCount人',
                      style: const TextStyle(color: _kTextSub),
                    ),
                    const SizedBox(width: 8),
                    const Text('·', style: TextStyle(color: _kTextSub)),
                    const SizedBox(width: 8),
                    Text('役割: $roleLabel',
                        style: const TextStyle(color: _kTextSub)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    Chip(
                      backgroundColor: _kMainBlue.withOpacity(0.1),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.monetization_on,
                              size: 16, color: _kMainBlue),
                          const SizedBox(width: 6),
                          Text('$currency 通貨'),
                        ],
                      ),
                    ),
                    if (pendingCount > 0)
                      Chip(
                        backgroundColor: _kAccentOrange.withOpacity(0.12),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending_actions,
                                size: 16, color: _kAccentOrange),
                            const SizedBox(width: 6),
                            Text('承認待ち $pendingCount件'),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('招待リンクの共有は近日対応予定です。')),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _kMainBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      label: const Text('メンバーを招待'),
                    ),
                    const SizedBox(width: 12),
                    _HeaderIconButton(
                      icon: Icons.notifications_outlined,
                      tooltip: '承認キューを開く',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('承認キューは現在ベータ版です。')),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _HeaderIconButton(
                      icon: Icons.search,
                      tooltip: 'メンバーを検索',
                      onTap: () {
                        Scrollable.ensureVisible(
                          context,
                          duration: const Duration(milliseconds: 300),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(String role) {
    return switch (role) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          width: 44,
          height: 44,
          child: Icon(icon, color: _kTextSub),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.color = _kMainBlue,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kTextMain,
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.lines,
    this.iconColor = _kMainBlue,
    this.backgroundColor = Colors.white,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Color iconColor;
  final Color backgroundColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kTextMain,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 8),
              child: Text(
                lines[i],
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _kTextMain,
                ),
              ),
            ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: iconColor,
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    subtitle!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.centerRight,
                child: trailing!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: foregroundColor),
    );
  }
}

class _TalkTrailing extends StatelessWidget {
  const _TalkTrailing({
    required this.timeLabel,
    this.unreadCount,
  });

  final String timeLabel;
  final int? unreadCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          timeLabel,
          style: const TextStyle(
            fontSize: 11,
            color: _kTextSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (unreadCount != null && unreadCount! > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kMainBlue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              unreadCount!.toString(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TalkItem {
  const _TalkItem({
    required this.channel,
    required this.snippet,
    required this.timeLabel,
    this.unreadCount,
  });

  final String channel;
  final String snippet;
  final String timeLabel;
  final int? unreadCount;
}

enum WalletActivityType { deposit, withdrawal }

class _WalletItem {
  const _WalletItem({
    required this.title,
    required this.counterparty,
    required this.amount,
    required this.timeLabel,
    required this.type,
  });

  final String title;
  final String counterparty;
  final double amount;
  final String timeLabel;
  final WalletActivityType type;
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _BankAction {
  const _BankAction({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _DashboardTabBar extends StatelessWidget {
  const _DashboardTabBar({
    required this.activeTab,
    required this.onSelected,
  });

  final _CommunityDashboardTab activeTab;
  final ValueChanged<_CommunityDashboardTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            for (final tab in _CommunityDashboardTab.values)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _DashboardTabButton(
                  tab: tab,
                  isActive: activeTab == tab,
                  onTap: () => onSelected(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTabButton extends StatelessWidget {
  const _DashboardTabButton({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  final _CommunityDashboardTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? _kMainBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? _kMainBlue : const Color(0xFFE2E8F0),
          ),
          boxShadow: isActive
              ? const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: isActive ? Colors.white : _kTextSub,
            ),
            const SizedBox(width: 8),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? Colors.white : _kTextMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabHeaderDelegate({
    required this.activeTab,
    required this.onSelected,
  });

  final _CommunityDashboardTab activeTab;
  final ValueChanged<_CommunityDashboardTab> onSelected;

  @override
  double get minExtent => 68;

  @override
  double get maxExtent => 68;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        boxShadow: overlapsContent
            ? const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: _DashboardTabBar(
        activeTab: activeTab,
        onSelected: onSelected,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabHeaderDelegate oldDelegate) {
    return oldDelegate.activeTab != activeTab;
  }
}


class _OverviewCards extends StatelessWidget {
  const _OverviewCards({
    required this.totalMembers,
    required this.pendingCount,
    required this.bankManagerCount,
    required this.minorCount,
  });

  final int totalMembers;
  final int pendingCount;
  final int bankManagerCount;
  final int minorCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 480;
        final children = [
          _OverviewTile(
            title: '合計メンバー',
            value: '$totalMembers人',
            icon: Icons.groups,
            color: _kMainBlue,
          ),
          _OverviewTile(
            title: '承認待ち',
            value: '$pendingCount件',
            icon: Icons.pending_actions,
            color: _kAccentOrange,
          ),
          _OverviewTile(
            title: '中央銀行権限',
            value: '$bankManagerCount人',
            icon: Icons.account_balance,
            color: _kSubGreen,
          ),
          _OverviewTile(
            title: '未成年メンバー',
            value: '$minorCount人',
            icon: Icons.family_restroom,
            color: Colors.purple,
          ),
        ];
        if (isWide) {
          return Row(
            children: [
              for (final child in children)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: child,
                  ),
                ),
            ],
          );
        }
        return Column(
          children: [
            for (final child in children)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kTextSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _kTextMain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.selected,
    required this.currencyCode,
    required this.onTap,
    required this.onDetail,
  });

  final _SelectableMember member;
  final bool selected;
  final String currencyCode;
  final VoidCallback onTap;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? _kMainBlue : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemberAvatar(member: member, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              member.displayName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _kTextMain,
                              ),
                            ),
                          ),
                          Checkbox.adaptive(
                            value: selected,
                            onChanged: (_) => onTap(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${member.membership.userId}',
                        style:
                            const TextStyle(fontSize: 13, color: _kTextSub),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            size: 16,
                            color: _kTextSub,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${member.membership.balance.toStringAsFixed(2)} $currencyCode',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kTextMain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.shield_moon,
                              size: 16, color: _kTextSub),
                          const SizedBox(width: 4),
                          Text(
                            '${member.trustScore.toStringAsFixed(0)}% 信頼',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kTextMain,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buildMemberChips(member),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDetail,
                icon: const Icon(Icons.more_horiz),
                label: const Text('詳細'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _buildMemberChips(_SelectableMember member) {
  final chips = <Widget>[
    _InfoChip(
      text: _roleLabel(member.membership.role),
      color: _roleColor(member.membership.role),
      foreground: _roleForeground(member.membership.role),
      icon: Icons.shield_outlined,
    ),
  ];
  if (member.membership.canManageBank) {
    chips.add(const _InfoChip(
      text: '中央銀行権限',
      color: Color(0xFFD1FAE5),
      foreground: _kSubGreen,
      icon: Icons.account_balance,
    ));
  }
  if (member.membership.balanceVisible) {
    chips.add(const _InfoChip(
      text: '残高公開',
      color: Color(0xFFE0E7FF),
      foreground: _kMainBlue,
      icon: Icons.visibility,
    ));
  }
  if (member.isPending) {
    chips.add(const _InfoChip(
      text: '承認待ち',
      color: Color(0xFFFFEFD5),
      foreground: _kAccentOrange,
      icon: Icons.schedule,
    ));
  }
  if (member.profile?.minor == true) {
    chips.add(const _InfoChip(
      text: '未成年',
      color: Color(0xFFE9D5FF),
      foreground: Color(0xFF7C3AED),
      icon: Icons.cake_outlined,
    ));
  }
  final joinedAt = member.membership.joinedAt;
  if (joinedAt != null) {
    chips.add(_InfoChip(
      text: '${_formatDate(joinedAt)} 参加',
      color: const Color(0xFFF1F5F9),
      foreground: _kTextSub,
      icon: Icons.event_available,
    ));
  }
  return chips;
}

String _roleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'オーナー';
    case 'admin':
      return '管理者';
    case 'mediator':
      return '仲介';
    case 'pending':
      return '承認待ち';
    default:
      return 'メンバー';
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'owner':
      return const Color(0xFFE0F2FE);
    case 'admin':
      return const Color(0xFFE9D5FF);
    case 'mediator':
      return const Color(0xFFFFF7ED);
    case 'pending':
      return const Color(0xFFFFEDD5);
    default:
      return const Color(0xFFF1F5F9);
  }
}

Color _roleForeground(String role) {
  switch (role) {
    case 'owner':
      return _kMainBlue;
    case 'admin':
      return const Color(0xFF7C3AED);
    case 'mediator':
      return const Color(0xFFEA580C);
    case 'pending':
      return _kAccentOrange;
    default:
      return _kTextSub;
  }
}

String _formatDate(DateTime value) {
  final twoDigits = (int n) => n.toString().padLeft(2, '0');
  return '${value.year}/${twoDigits(value.month)}/${twoDigits(value.day)}';
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, required this.size});

  final _SelectableMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photoUrl = member.profile?.photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(size / 2),
        image: photoUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              ),
      ),
      child: photoUrl == null
          ? Center(
              child: Text(
                member.initials,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
            )
          : null,
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.text,
    required this.color,
    required this.foreground,
    required this.icon,
  });

  final String text;
  final Color color;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionSummaryBar extends StatelessWidget {
  const _SelectionSummaryBar({
    required this.selectedCount,
    required this.totalMembers,
    required this.totalBalance,
    required this.currencyCode,
    required this.onSelectAll,
    required this.onClear,
    required this.onBulkAction,
  });

  final int selectedCount;
  final int totalMembers;
  final num totalBalance;
  final String currencyCode;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onBulkAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedCount > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -8),
          ),
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSelection
                          ? '選択中: $selectedCount / $totalMembers 名'
                          : 'メンバー総数: $totalMembers 名',
                      style: theme.textTheme.titleMedium!
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSelection
                          ? '合計残高: ${totalBalance.toStringAsFixed(2)} $currencyCode'
                          : 'メンバーを選択すると一括アクションが利用できます',
                      style: const TextStyle(color: _kTextSub, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: hasSelection ? onClear : onSelectAll,
                child: Text(hasSelection ? '全て解除' : '全員選択'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSelectAll,
                  icon: const Icon(Icons.select_all),
                  label: const Text('表示中をすべて選択'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasSelection ? onBulkAction : null,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('一括アクション'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kMainBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(
            color: Color(0xFFE2E8F0),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_search, size: 48, color: _kTextSub),
        ),
        const SizedBox(height: 24),
        const Text(
          '該当するメンバーが見つかりません',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _kTextMain,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '検索条件やフィルターを調整して、もう一度お試しください。',
          textAlign: TextAlign.center,
          style: TextStyle(color: _kTextSub),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.error_outline, color: _kAccentOrange),
              SizedBox(width: 8),
              Text(
                'メンバーの読み込みに失敗しました',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: _kTextSub),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: _kMainBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: _kTextSub),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: _kTextSub,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _kTextMain,
            ),
          ),
        ],
      ),
    );
  }
}
