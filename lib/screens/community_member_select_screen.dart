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
  }) async {
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
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
  bool _requireApprovalSetting = true;
  bool _isDiscoverableSetting = false;
  bool _dualApprovalEnabled = true;

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
    final community = _community;
    final communityName = community?.name ??
        widget.initialCommunityName ??
        widget.communityId;
    final currencyLabel = (community?.currency.name?.isNotEmpty ?? false)
        ? community!.currency.name
        : currencyCode;
    final totalMembers = _members.length;
    final selectedCount = _selectedUids.length;
    final minorCount =
        _members.where((member) => member.profile?.minor == true).length;
    final pendingCount = _pendingCount;
    final selectionText = selectedCount > 0
        ? '選択中: $selectedCount人 · 合計残高 ${selectedBalance.toStringAsFixed(2)} $currencyCode'
        : 'メンバーを選択すると、まとめてアクションを実行できます。';

    final metrics = [
      _OverviewMetric(
        icon: Icons.groups_rounded,
        label: 'メンバー',
        value: '$totalMembers人',
        caption: '参加者の合計',
        color: _kMainBlue,
      ),
      _OverviewMetric(
        icon: Icons.account_balance,
        label: '中央銀行権限',
        value: '${_bankManagerCount}人',
        caption: 'Owner / BankAdmin',
        color: _kSubGreen,
      ),
      _OverviewMetric(
        icon: Icons.pending_actions,
        label: '承認待ち',
        value: '$pendingCount件',
        caption: '招待・支払いの保留',
        color: _kAccentOrange,
      ),
      _OverviewMetric(
        icon: Icons.family_restroom,
        label: '未成年',
        value: '$minorCount人',
        caption: '追加承認が必要なメンバー',
        color: const Color(0xFF9333EA),
      ),
    ];

    final navItems = [
      _OverviewNavItem(
        tab: _CommunityDashboardTab.talk,
        title: 'トーク',
        description: '承認依頼やピン留めをチェック',
        icon: Icons.forum_outlined,
        accentColor: _kAccentOrange,
      ),
      _OverviewNavItem(
        tab: _CommunityDashboardTab.wallet,
        title: 'ウォレット',
        description: '残高・取引と保留中の請求を確認',
        icon: Icons.account_balance_wallet_outlined,
        accentColor: _kSubGreen,
      ),
      _OverviewNavItem(
        tab: _CommunityDashboardTab.members,
        title: 'メンバー',
        description: '検索や権限の管理を行う',
        icon: Icons.groups_2_outlined,
        accentColor: _kMainBlue,
      ),
      _OverviewNavItem(
        tab: _CommunityDashboardTab.settings,
        title: 'コミュ設定',
        description: '公開範囲と通知を調整',
        icon: Icons.settings_outlined,
        accentColor: const Color(0xFF6366F1),
      ),
      _OverviewNavItem(
        tab: _CommunityDashboardTab.bank,
        title: 'バンク',
        description: '発行/回収と権限をレビュー',
        icon: Icons.account_balance_outlined,
        accentColor: const Color(0xFFDC2626),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverviewHeroCard(
          communityName: communityName,
          currencyLabel: currencyLabel,
          currencyCode: currencyCode,
          memberCount: totalMembers,
          bankManagerCount: _bankManagerCount,
          pendingCount: pendingCount,
          minorCount: minorCount,
          selectionSummary: selectionText,
          hasSelection: selectedCount > 0,
          onNavigateApprovals:
              () => _handleDashboardTabSelected(_CommunityDashboardTab.talk),
          onNavigateMembers:
              () => _handleDashboardTabSelected(_CommunityDashboardTab.members),
        ),
        const SizedBox(height: 20),
        _OverviewMetricsGrid(metrics: metrics),
        const SizedBox(height: 20),
        _OverviewNavigationCard(
          items: navItems,
          onNavigate: _handleDashboardTabSelected,
        ),
        const SizedBox(height: 20),
        _OverviewInsightCard(
          icon: Icons.pending_actions,
          title: '承認待ちキュー',
          accentColor: _kAccentOrange,
          backgroundColor: _kAccentOrange.withOpacity(0.12),
          lines: [
            if (pendingCount > 0)
              '承認待ちリクエストが${pendingCount}件あります。今すぐレビューしましょう。'
            else
              '現在承認待ちの依頼はありません。',
            'キューは「トーク」タブの上部から確認できます。',
          ],
          actionLabel: 'トークを開く',
          onAction: () =>
              _handleDashboardTabSelected(_CommunityDashboardTab.talk),
        ),
        const SizedBox(height: 16),
        _OverviewInsightCard(
          icon: Icons.timeline,
          title: '最新のアクティビティ',
          accentColor: _kSubGreen,
          backgroundColor: _kSubGreen.withOpacity(0.12),
          lines: const [
            'ウォレットで最近の取引と承認履歴を振り返りましょう。',
            '詳細は「ウォレット」タブまたは「メンバー」タブで確認できます。',
          ],
          actionLabel: 'ウォレットを確認',
          onAction: () =>
              _handleDashboardTabSelected(_CommunityDashboardTab.wallet),
        ),
      ],
    );
  }

  Widget _buildTalkSection() {
    const pinnedChannels = [
      _TalkChannelEntry(
        title: 'settlement',
        subtitle: '佐藤: @あなた 会費の承認お願いします',
        timeLabel: '10:24',
        hasMention: true,
        highlightBadge: '@',
        mentionColor: _kAccentOrange,
        borderColor: Color(0x33F59E0B),
      ),
    ];
    const unreadChannels = [
      _TalkChannelEntry(
        title: 'general',
        subtitle: '鈴木: 今日のランチどうしますか？',
        timeLabel: '15:30',
        unreadCount: 3,
        highlightColor: Color(0xFFE5EDFF),
      ),
    ];
    const recentChannels = [
      _TalkChannelEntry(
        title: 'confidential',
        subtitle: '田中: 次回の予算について',
        timeLabel: '昨日',
        inlineIcon: Icons.folder_shared_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HighlightBanner(
          icon: Icons.info_outline,
          backgroundColor: _kAccentOrange.withOpacity(0.1),
          iconColor: _kAccentOrange,
          message: const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '承認待ち依頼が '),
                TextSpan(
                  text: '3件',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: ' あります。'),
              ],
            ),
            style: TextStyle(fontSize: 13, color: _kTextMain),
          ),
          actionLabel: '一覧へ',
          onAction: () => _showNotImplemented('承認待ち一覧'),
        ),
        const SizedBox(height: 16),
        const _DashboardSearchField(
          hintText: 'チャンネル・メッセージ検索',
        ),
        const SizedBox(height: 12),
        _ScrollableFilterRow(
          filters: const [
            _FilterChipConfig(label: 'すべて', isPrimary: true),
            _FilterChipConfig(label: '未読'),
            _FilterChipConfig(label: 'メンション', trailingBadge: '@'),
            _FilterChipConfig(label: '参加中'),
          ],
          onFilterTap: (label) => _showNotImplemented('フィルター: $label'),
        ),
        const SizedBox(height: 20),
        _TalkChannelGroup(
          title: 'ピン留め',
          entries: pinnedChannels,
          onTapChannel: _showNotImplemented,
        ),
        const SizedBox(height: 16),
        _TalkChannelGroup(
          title: '未読',
          entries: unreadChannels,
          onTapChannel: _showNotImplemented,
        ),
        const SizedBox(height: 16),
        _TalkChannelGroup(
          title: '最近',
          entries: recentChannels,
          onTapChannel: _showNotImplemented,
        ),
      ],
    );
  }

  Widget _buildWalletSection(String currencyCode) {
    const quickActions = [
      _WalletQuickAction(
        icon: Icons.north_east,
        label: '送る',
        backgroundColor: Color(0xFFEFF4FF),
        foregroundColor: _kMainBlue,
      ),
      _WalletQuickAction(
        icon: Icons.south_west,
        label: '請求',
        backgroundColor: Color(0xFFE6F6EF),
        foregroundColor: _kSubGreen,
      ),
      _WalletQuickAction(
        icon: Icons.grid_view_rounded,
        label: '割り勘',
        backgroundColor: Color(0xFFE2E8F0),
        foregroundColor: _kTextSub,
      ),
      _WalletQuickAction(
        icon: Icons.task_alt_outlined,
        label: 'タスク',
        backgroundColor: Color(0xFFE2E8F0),
        foregroundColor: _kTextSub,
      ),
    ];

    const transactions = [
      _WalletTransaction(
        title: '佐藤さんへ送金',
        subtitle: '9月24日 18:30',
        amount: -500,
        type: WalletActivityType.withdrawal,
      ),
      _WalletTransaction(
        title: '田中さんからの報酬',
        subtitle: '9月24日 15:00',
        amount: 2000,
        type: WalletActivityType.deposit,
      ),
      _WalletTransaction(
        title: '飲み会 割り勘',
        subtitle: '9月23日 21:00',
        amount: -950,
        type: WalletActivityType.withdrawal,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WalletBalanceCard(
          currencyCode: currencyCode,
          balance: 25800,
          monthlyInflow: 5200,
          monthlyOutflow: 1450,
          pendingCount: 3,
        ),
        const SizedBox(height: 16),
        _WalletActionGrid(
          actions: quickActions,
          onTap: (label) => _showNotImplemented('ウォレットアクション: $label'),
        ),
        const SizedBox(height: 16),
        _WalletApprovalCard(
          requester: '鈴木さん',
          amount: 300,
          currencyCode: currencyCode,
          memo: '先日のランチ代',
          onApprove: () => _showNotImplemented('請求承認'),
          onReject: () => _showNotImplemented('請求却下'),
        ),
        const SizedBox(height: 16),
        _WalletTransactionList(
          transactions: transactions,
          currencyCode: currencyCode,
          onViewAll: () => _showNotImplemented('取引履歴'),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    final communityName = _community?.name ?? 'コミュニティ';
    const notificationMode = '@メンションのみ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SettingsSectionTitle('基本情報'),
        const SizedBox(height: 8),
        _SettingsListTile(
          icon: Icons.edit_outlined,
          title: 'コミュニティ名',
          subtitle: communityName,
          onTap: () => _showNotImplemented('コミュニティ名編集'),
        ),
        const SizedBox(height: 12),
        _SettingsListTile(
          icon: Icons.photo_library_outlined,
          title: 'アイコンとカバー',
          subtitle: '変更',
          onTap: () => _showNotImplemented('アイコンとカバー設定'),
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('通知・表示'),
        const SizedBox(height: 8),
        _SettingsListTile(
          icon: Icons.notifications_active_outlined,
          title: '通知の既定',
          subtitle: notificationMode,
          onTap: () => _showNotImplemented('通知設定'),
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('参加設定'),
        const SizedBox(height: 8),
        _SettingsToggleTile(
          icon: Icons.verified_user_outlined,
          title: '参加承認',
          description: '参加に管理者の承認を必要とする',
          value: _requireApprovalSetting,
          onChanged: (value) => setState(() => _requireApprovalSetting = value),
        ),
        const SizedBox(height: 12),
        _SettingsToggleTile(
          icon: Icons.travel_explore_outlined,
          title: '公開設定',
          description: 'コミュニティを検索可能にする',
          value: _isDiscoverableSetting,
          onChanged: (value) => setState(() => _isDiscoverableSetting = value),
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('Danger Zone'),
        const SizedBox(height: 8),
        _DangerZoneTile(
          title: 'コミュニティから退出する',
          description: 'この操作は元に戻せません。',
          onTap: () => _showNotImplemented('コミュニティ退出'),
        ),
        const SizedBox(height: 12),
        _DangerZoneTile(
          title: 'コミュニティを削除する',
          description: 'すべてのデータが完全に削除されます。',
          onTap: () => _showNotImplemented('コミュニティ削除'),
        ),
      ],
    );
  }

  Widget _buildBankSection(String currencyCode) {
    final treasury = _community?.treasury;
    final balance = treasury?.balance ?? 0;
    final reserve = treasury?.initialGrant ?? 0;
    final circulation = balance - reserve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BankSummaryGrid(
          balance: balance,
          reserve: reserve,
          currencyCode: currencyCode,
          allowMinting: _community?.currency.allowMinting ?? true,
        ),
        const SizedBox(height: 16),
        _BankPrimaryActions(
          onMint: () => _showNotImplemented('Mint'),
          onBurn: () => _showNotImplemented('Burn'),
        ),
        const SizedBox(height: 16),
        _BankCurrencyList(
          currencyCode: currencyCode,
          currencyName: _community?.currency.name ?? '既定通貨',
        ),
        const SizedBox(height: 16),
        _BankPolicyCard(
          dualApprovalEnabled: _dualApprovalEnabled,
          onToggleDualApproval: (value) =>
              setState(() => _dualApprovalEnabled = value),
          mintRolesLabel: 'Owner, BankAdmin',
          dailyLimit: '100,000 $currencyCode',
        ),
        const SizedBox(height: 16),
        _BankPermissionCard(
          members: const [
            _BankPermissionMember(
              name: '田中',
              role: 'Owner',
              avatarUrl: null,
              locked: true,
            ),
            _BankPermissionMember(
              name: '鈴木',
              role: 'BankAdmin',
              avatarUrl: null,
              locked: false,
            ),
          ],
          onAddMember: () => _showNotImplemented('権限メンバー追加'),
          onRemoveMember: (name) =>
              _showNotImplemented('権限メンバー削除: $name'),
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
          _requireApprovalSetting = community.policy.requiresApproval;
          _isDiscoverableSetting =
              community.visibility.balanceMode != 'private';
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
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTabHeaderDelegate(
                      activeTab: _activeDashboardTab,
                      communityName: communityName,
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

                              onSelectToggle: () =>
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
    final totalMembers = _members.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MembersApprovalCard(
            pendingCount: _pendingCount,
            onTap: _pendingCount > 0
                ? () => _showNotImplemented('参加申請の承認')
                : null,
          ),
          const SizedBox(height: 16),
          _DashboardSearchField(
            controller: _searchController,
            hintText: 'メンバーを検索',
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _MembersFilterChip(
                  label: 'すべて ($totalMembers)',
                  isActive: _activeFilter == MemberFilter.all,
                  onTap: () => _changeFilter(MemberFilter.all),
                ),
                const SizedBox(width: 8),
                _MembersFilterChip(
                  label: '管理者',
                  isActive: _activeFilter == MemberFilter.admin,
                  onTap: () => _changeFilter(MemberFilter.admin),
                ),
                const SizedBox(width: 8),
                _MembersFilterChip(
                  label: '承認待ち',
                  isActive: _activeFilter == MemberFilter.pending,
                  onTap: () => _changeFilter(MemberFilter.pending),
                ),
                const SizedBox(width: 8),
                _MembersFilterChip(
                  label: _sortOption == MemberSortOption.recent
                      ? '最近アクティブ'
                      : '最近アクティブ',
                  isActive: _sortOption == MemberSortOption.recent,
                  onTap: () => _changeSort(MemberSortOption.recent),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<MemberSortOption>(
                  tooltip: 'その他の並び替え',
                  onSelected: _changeSort,
                  itemBuilder: (context) => [
                    for (final option in MemberSortOption.values)
                      PopupMenuItem(
                        value: option,
                        child: Row(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune, size: 18, color: _kTextSub),
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
                height: 132,
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
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xBF000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black38,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ],
          ),
          Container(
            transform: Matrix4.translationValues(0, -40, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
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
                const SizedBox(height: 14),
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
                      style:
                          const TextStyle(color: _kTextSub, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    const Text('·', style: TextStyle(color: _kTextSub)),
                    const SizedBox(width: 8),
                    Text(
                      '役割: $roleLabel',
                      style:
                          const TextStyle(color: _kTextSub, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _HeaderChip(
                      icon: Icons.monetization_on,
                      label: '$currency 独自通貨',
                      color: _kMainBlue,
                    ),
                    if (pendingCount > 0)
                      _HeaderChip(
                        icon: Icons.pending_actions,
                        label: '承認待ち $pendingCount件',
                        color: _kAccentOrange,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('招待リンクの共有は近日対応予定です。'),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _kMainBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        elevation: 3,
                      ),
                      child: const Text('招待する'),
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
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOut,
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard({
    required this.communityName,
    required this.currencyLabel,
    required this.currencyCode,
    required this.memberCount,
    required this.bankManagerCount,
    required this.pendingCount,
    required this.minorCount,
    required this.selectionSummary,
    required this.hasSelection,
    required this.onNavigateApprovals,
    required this.onNavigateMembers,
  });

  final String communityName;
  final String currencyLabel;
  final String currencyCode;
  final int memberCount;
  final int bankManagerCount;
  final int pendingCount;
  final int minorCount;
  final String selectionSummary;
  final bool hasSelection;
  final VoidCallback onNavigateApprovals;
  final VoidCallback onNavigateMembers;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '概要ダッシュボード',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            communityName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '独自通貨: $currencyLabel ($currencyCode)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverviewHeroChip(
                icon: Icons.groups_rounded,
                label: 'メンバー $memberCount人',
              ),
              _OverviewHeroChip(
                icon: Icons.account_balance,
                label: '中央銀行権限 $bankManagerCount人',
                highlightColor: _kSubGreen,
              ),
              _OverviewHeroChip(
                icon: Icons.pending_actions,
                label: '承認待ち $pendingCount件',
                highlightColor:
                    pendingCount > 0 ? _kAccentOrange : null,
              ),
              _OverviewHeroChip(
                icon: Icons.family_restroom,
                label: '未成年 $minorCount人',
                highlightColor: const Color(0xFF9333EA),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '現在の選択',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  selectionSummary,
                  style: TextStyle(
                    color: Colors.white.withOpacity(hasSelection ? 1 : 0.92),
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onNavigateApprovals,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kMainBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child:
                      Text(pendingCount > 0 ? '承認待ちを確認' : 'トークを開く'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onNavigateMembers,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('メンバーを見る'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewHeroChip extends StatelessWidget {
  const _OverviewHeroChip({
    required this.icon,
    required this.label,
    this.highlightColor,
  });

  final IconData icon;
  final String label;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final color = highlightColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlightColor != null
            ? highlightColor!.withOpacity(0.14)
            : Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlightColor != null
              ? highlightColor!.withOpacity(0.5)
              : Colors.white.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric {
  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;
}

class _OverviewMetricsGrid extends StatelessWidget {
  const _OverviewMetricsGrid({required this.metrics});

  final List<_OverviewMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 360 ? 2 : 1;
        final childAspectRatio = crossAxisCount > 1 ? 2.6 : 3.0;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            for (final metric in metrics)
              _OverviewMetricCard(metric: metric),
          ],
        );
      },
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({required this.metric});

  final _OverviewMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: metric.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: metric.color),
          ),
          const SizedBox(height: 12),
          Text(
            metric.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kTextSub,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const Spacer(),
          Text(
            metric.caption,
            style: const TextStyle(
              fontSize: 11,
              color: _kTextSub,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewNavItem {
  const _OverviewNavItem({
    required this.tab,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
  });

  final _CommunityDashboardTab tab;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
}

class _OverviewNavigationCard extends StatelessWidget {
  const _OverviewNavigationCard({
    required this.items,
    required this.onNavigate,
  });

  final List<_OverviewNavItem> items;
  final ValueChanged<_CommunityDashboardTab> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'タブショートカット',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _OverviewQuickLinkRow(
                  item: items[i],
                  onTap: () => onNavigate(items[i].tab),
                ),
                if (i != items.length - 1)
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewQuickLinkRow extends StatelessWidget {
  const _OverviewQuickLinkRow({
    required this.item,
    required this.onTap,
  });

  final _OverviewNavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.accentColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kTextMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kTextSub,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _kTextSub),
          ],
        ),
      ),
    );
  }
}

class _OverviewInsightCard extends StatelessWidget {
  const _OverviewInsightCard({
    required this.icon,
    required this.title,
    required this.accentColor,
    required this.backgroundColor,
    required this.lines,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final Color accentColor;
  final Color backgroundColor;
  final List<String> lines;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kTextMain,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: accentColor,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 6),
              child: Text(
                lines[i],
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _kTextMain,
                ),
              ),
            ),
        ],
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

class _HighlightBanner extends StatelessWidget {
  const _HighlightBanner({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final Widget message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: iconColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: message),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: iconColor),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardSearchField extends StatelessWidget {
  const _DashboardSearchField({
    this.controller,
    required this.hintText,
  });

  final TextEditingController? controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _kMainBlue),
        ),
      ),
    );
  }
}

class _FilterChipConfig {
  const _FilterChipConfig({
    required this.label,
    this.isPrimary = false,
    this.trailingBadge,
  });

  final String label;
  final bool isPrimary;
  final String? trailingBadge;
}

class _ScrollableFilterRow extends StatelessWidget {
  const _ScrollableFilterRow({
    required this.filters,
    this.onFilterTap,
  });

  final List<_FilterChipConfig> filters;
  final ValueChanged<String>? onFilterTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onFilterTap?.call(filter.label),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: filter.isPrimary ? _kMainBlue : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: filter.isPrimary
                      ? _kMainBlue
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: filter.isPrimary ? Colors.white : _kTextMain,
                    ),
                  ),
                  if (filter.trailingBadge != null) ...[
                    const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: filter.isPrimary
                                ? Colors.white.withOpacity(0.2)
                                : _kAccentOrange,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            filter.trailingBadge!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TalkChannelEntry {
  const _TalkChannelEntry({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    this.unreadCount,
    this.hasMention = false,
    this.highlightColor,
    this.borderColor,
    this.highlightBadge,
    this.mentionColor = _kMainBlue,
    this.inlineIcon,
    this.leadingIcon,
    this.leadingLabel = '#',
    this.leadingBackgroundColor = const Color(0xFFF1F5F9),
    this.leadingForegroundColor = _kTextSub,
  });

  final String title;
  final String subtitle;
  final String timeLabel;
  final int? unreadCount;
  final bool hasMention;
  final Color? highlightColor;
  final Color? borderColor;
  final String? highlightBadge;
  final Color mentionColor;
  final IconData? inlineIcon;
  final IconData? leadingIcon;
  final String leadingLabel;
  final Color leadingBackgroundColor;
  final Color leadingForegroundColor;
}

class _TalkChannelGroup extends StatelessWidget {
  const _TalkChannelGroup({
    required this.title,
    required this.entries,
    required this.onTapChannel,
  });

  final String title;
  final List<_TalkChannelEntry> entries;
  final ValueChanged<String> onTapChannel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TalkChannelCard(
              entry: entry,
              onTap: () => onTapChannel(entry.title),
            ),
          ),
      ],
    );
  }
}

class _TalkChannelCard extends StatelessWidget {
  const _TalkChannelCard({
    required this.entry,
    required this.onTap,
  });

  final _TalkChannelEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = entry.highlightColor ?? Colors.white;
    final borderColor = entry.borderColor ??
        (entry.highlightColor != null
            ? entry.highlightColor!.withOpacity(0.4)
            : const Color(0xFFE2E8F0));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: entry.leadingBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: entry.leadingIcon != null
                  ? Icon(entry.leadingIcon, color: entry.leadingForegroundColor)
                  : Center(
                      child: Text(
                        entry.leadingLabel,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: entry.leadingForegroundColor,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (entry.inlineIcon != null) ...[
                        Icon(entry.inlineIcon, size: 16, color: _kTextSub),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          entry.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kTextMain,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    style: const TextStyle(fontSize: 13, color: _kTextSub),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.timeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kTextSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.hasMention || entry.highlightBadge != null) ...[
                  const SizedBox(height: 8),
                  _TalkBadge(
                    label: entry.highlightBadge ?? '@',
                    backgroundColor: entry.mentionColor,
                  ),
                ],
                if (entry.unreadCount != null && entry.unreadCount! > 0) ...[
                  const SizedBox(height: 8),
                  _TalkBadge(
                    label: entry.unreadCount!.toString(),
                    backgroundColor: _kMainBlue,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TalkBadge extends StatelessWidget {
  const _TalkBadge({
    required this.label,
    required this.backgroundColor,
  });

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

enum WalletActivityType { deposit, withdrawal }

class _WalletQuickAction {
  const _WalletQuickAction({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _WalletActionGrid extends StatelessWidget {
  const _WalletActionGrid({
    required this.actions,
    required this.onTap,
  });

  final List<_WalletQuickAction> actions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == actions.length - 1 ? 0 : 12),
              child: _WalletActionButton(
                action: actions[i],
                onTap: () => onTap(actions[i].label),
              ),
            ),
          ),
      ],
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.action,
    required this.onTap,
  });

  final _WalletQuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: action.backgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(action.icon, color: action.foregroundColor),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kTextMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({
    required this.currencyCode,
    required this.balance,
    required this.monthlyInflow,
    required this.monthlyOutflow,
    required this.pendingCount,
  });

  final String currencyCode;
  final num balance;
  final num monthlyInflow;
  final num monthlyOutflow;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kMainBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '現在の残高 ($currencyCode)',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            balance.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今月の入金',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '+${monthlyInflow.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今月の出金',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '-${monthlyOutflow.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '保留: $pendingCount件',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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

class _WalletApprovalCard extends StatelessWidget {
  const _WalletApprovalCard({
    required this.requester,
    required this.amount,
    required this.currencyCode,
    required this.memo,
    required this.onApprove,
    required this.onReject,
  });

  final String requester;
  final num amount;
  final String currencyCode;
  final String memo;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kAccentOrange.withOpacity(0.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _kAccentOrange.withOpacity(0.1),
                child: Text(
                  requester.characters.first,
                  style: const TextStyle(
                    color: _kAccentOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$requesterからの請求',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextMain,
                      ),
                    ),
                    Text(
                      'メモ: $memo',
                      style: const TextStyle(fontSize: 12, color: _kTextSub),
                    ),
                  ],
                ),
              ),
              Text(
                '${amount.toStringAsFixed(0)} $currencyCode',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSub,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('却下'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccentOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('承認'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletTransaction {
  const _WalletTransaction({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
  });

  final String title;
  final String subtitle;
  final num amount;
  final WalletActivityType type;
}

class _WalletTransactionList extends StatelessWidget {
  const _WalletTransactionList({
    required this.transactions,
    required this.currencyCode,
    required this.onViewAll,
  });

  final List<_WalletTransaction> transactions;
  final String currencyCode;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '最近の取引',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _kTextMain,
              ),
            ),
            TextButton(
              onPressed: onViewAll,
              child: const Text('すべて表示'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < transactions.length; i++)
                _WalletTransactionTile(
                  transaction: transactions[i],
                  currencyCode: currencyCode,
                  showDivider: i != transactions.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile({
    required this.transaction,
    required this.currencyCode,
    required this.showDivider,
  });

  final _WalletTransaction transaction;
  final String currencyCode;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDeposit = transaction.type == WalletActivityType.deposit;
    final amountPrefix = isDeposit ? '+' : '-';
    final amountColor = isDeposit ? _kSubGreen : const Color(0xFFDC2626);
    final icon = isDeposit ? Icons.south_west : Icons.north_east;
    final iconBackground =
        isDeposit ? _kSubGreen.withOpacity(0.12) : const Color(0xFFFFE4E6);
    final iconColor = isDeposit ? _kSubGreen : const Color(0xFFDC2626);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transaction.subtitle,
                      style: const TextStyle(fontSize: 12, color: _kTextSub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$amountPrefix${transaction.amount.toStringAsFixed(0)} $currencyCode',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            color: Color(0xFFE2E8F0),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _MembersApprovalCard extends StatelessWidget {
  const _MembersApprovalCard({
    required this.pendingCount,
    this.onTap,
  });

  final int pendingCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kAccentOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.how_to_reg, color: _kAccentOrange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '参加申請の承認',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kTextMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pendingCount > 0
                      ? '新しい申請が${pendingCount}件あります'
                      : '最新の申請状況を確認しましょう',
                  style: const TextStyle(fontSize: 12, color: _kTextSub),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _kTextSub),
        ],
      ),
    );

    final badge = pendingCount > 0
        ? Positioned(
            right: 12,
            top: 12,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: _kAccentOrange,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                pendingCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
        : null;

    final card = onTap != null
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: content,
          )
        : content;

    return Stack(
      children: [
        card,
        if (badge != null) badge,
      ],
    );
  }
}

class _MembersFilterChip extends StatelessWidget {
  const _MembersFilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _kMainBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? _kMainBlue : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : _kTextMain,
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: _kTextSub,
      ),
    );
  }
}

class _SettingsListTile extends StatelessWidget {
  const _SettingsListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kMainBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _kMainBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTextMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: _kTextSub),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _kTextSub),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kAccentOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _kAccentOrange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _kTextMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: _kTextSub),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: _kSubGreen,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE2E8F0),
          ),
        ],
      ),
    );
  }
}

class _DangerZoneTile extends StatelessWidget {
  const _DangerZoneTile({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33DC2626)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankSummaryGrid extends StatelessWidget {
  const _BankSummaryGrid({
    required this.balance,
    required this.reserve,
    required this.currencyCode,
    required this.allowMinting,
  });

  final num balance;
  final num reserve;
  final String currencyCode;
  final bool allowMinting;

  @override
  Widget build(BuildContext context) {
    final circulation = balance - reserve;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 480;
        final cards = [
          _BankSummaryCard(
            title: '発行残高 ($currencyCode)',
            value: balance.toStringAsFixed(0),
            subtitle:
                '流通: ${circulation.toStringAsFixed(0)} / 予備: ${reserve.toStringAsFixed(0)}',
          ),
          _BankSummaryCard(
            title: 'システムステータス',
            value: allowMinting ? '稼働中' : '一時停止',
            subtitle:
                allowMinting ? '台帳検算: 正常 · アラート: 0件' : '発行は停止中です',
          ),
        ];
        if (isWide) {
          return Row(
            children: [
              for (final card in cards)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: card,
                  ),
                ),
            ],
          );
        }
        return Column(
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card,
              ),
          ],
        );
      },
    );
  }
}

class _BankSummaryCard extends StatelessWidget {
  const _BankSummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kTextSub,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: _kTextSub),
          ),
        ],
      ),
    );
  }
}

class _BankPrimaryActions extends StatelessWidget {
  const _BankPrimaryActions({
    required this.onMint,
    required this.onBurn,
  });

  final VoidCallback onMint;
  final VoidCallback onBurn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onMint,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kMainBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('発行 (Mint)'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: onBurn,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0x33DC2626)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('回収 (Burn)'),
          ),
        ),
      ],
    );
  }
}

class _BankCurrencyList extends StatelessWidget {
  const _BankCurrencyList({
    required this.currencyCode,
    required this.currencyName,
  });

  final String currencyCode;
  final String currencyName;

  @override
  Widget build(BuildContext context) {
    final currencies = [
      _BankCurrencyTile(
        code: currencyCode,
        description: currencyName,
        statusLabel: '既定通貨',
        statusColor: _kSubGreen,
        disabled: false,
      ),
      const _BankCurrencyTile(
        code: 'TICKET',
        description: 'イベント参加用の使い捨てチケット',
        statusLabel: '無効',
        statusColor: Color(0xFFDC2626),
        disabled: true,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '通貨一覧',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('通貨を追加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final currency in currencies)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: currency,
            ),
        ],
      ),
    );
  }
}

class _BankCurrencyTile extends StatelessWidget {
  const _BankCurrencyTile({
    required this.code,
    required this.description,
    required this.statusLabel,
    required this.statusColor,
    required this.disabled,
  });

  final String code;
  final String description;
  final String statusLabel;
  final Color statusColor;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final textColor = disabled ? _kTextSub.withOpacity(0.6) : _kTextMain;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: disabled ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      code,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: _kTextSub),
        ],
      ),
    );
  }
}

class _BankPolicyCard extends StatelessWidget {
  const _BankPolicyCard({
    required this.dualApprovalEnabled,
    required this.onToggleDualApproval,
    required this.mintRolesLabel,
    required this.dailyLimit,
  });

  final bool dualApprovalEnabled;
  final ValueChanged<bool> onToggleDualApproval;
  final String mintRolesLabel;
  final String dailyLimit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ポリシー設定',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('二重承認'),
              Switch(
                value: dualApprovalEnabled,
                onChanged: onToggleDualApproval,
                activeColor: Colors.white,
                activeTrackColor: _kSubGreen,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE2E8F0),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('発行権限ロール'),
              Text(
                mintRolesLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('日次総発行上限'),
              Text(
                dailyLimit,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankPermissionMember {
  const _BankPermissionMember({
    required this.name,
    required this.role,
    this.avatarUrl,
    this.locked = false,
  });

  final String name;
  final String role;
  final String? avatarUrl;
  final bool locked;
}

class _BankPermissionCard extends StatelessWidget {
  const _BankPermissionCard({
    required this.members,
    required this.onAddMember,
    required this.onRemoveMember,
  });

  final List<_BankPermissionMember> members;
  final VoidCallback onAddMember;
  final ValueChanged<String> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '権限とメンバー',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
              TextButton(
                onPressed: onAddMember,
                child: const Text('メンバーを追加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final member in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BankPermissionTile(
                member: member,
                onRemove: onRemoveMember,
              ),
            ),
        ],
      ),
    );
  }
}

class _BankPermissionTile extends StatelessWidget {
  const _BankPermissionTile({
    required this.member,
    required this.onRemove,
  });

  final _BankPermissionMember member;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _kMainBlue.withOpacity(0.1),
            backgroundImage:
                member.avatarUrl != null ? NetworkImage(member.avatarUrl!) : null,
            child: member.avatarUrl == null
                ? Text(
                    member.name.characters.first,
                    style: const TextStyle(
                      color: _kMainBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _kTextMain,
                  ),
                ),
                Text(
                  member.role,
                  style: const TextStyle(fontSize: 12, color: _kTextSub),
                ),
              ],
            ),
          ),
          if (member.locked)
            const Text(
              '変更不可',
              style: TextStyle(fontSize: 12, color: _kTextSub),
            )
          else
            TextButton(
              onPressed: () => onRemove(member.name),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
              child: const Text('解除'),
            ),
        ],
      ),
    );
  }
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
    final tabs = _CommunityDashboardTab.values;
    return SafeArea(
      bottom: false,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                _DashboardTabButton(
                  tab: tabs[i],
                  isActive: activeTab == tabs[i],
                  onTap: () => onSelected(tabs[i]),
                ),
                if (i != tabs.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? _kMainBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          tab.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
            color: isActive ? _kMainBlue : _kTextSub,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _PinnedTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabHeaderDelegate({
    required this.activeTab,
    required this.communityName,
    required this.onSelected,
  });

  final _CommunityDashboardTab activeTab;
  final String communityName;
  final ValueChanged<_CommunityDashboardTab> onSelected;

  @override
  double get minExtent => 104;

  @override
  double get maxExtent => 104;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final showCompactHeader = shrinkOffset > 4;
    return SizedBox(
      height: maxExtent,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          boxShadow: overlapsContent
              ? const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: IgnorePointer(
                ignoring: !showCompactHeader,
                child: AnimatedOpacity(
                  opacity: showCompactHeader ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Center(
                    child: Text(
                      communityName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _kTextMain,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: _DashboardTabBar(
                activeTab: activeTab,
                onSelected: onSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabHeaderDelegate oldDelegate) {
    return oldDelegate.activeTab != activeTab ||
        oldDelegate.communityName != communityName;
  }
}


class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.selected,
    required this.currencyCode,
    required this.onSelectToggle,
    required this.onDetail,
  });

  final _SelectableMember member;
  final bool selected;
  final String currencyCode;
  final VoidCallback onSelectToggle;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelectToggle,
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
                            onChanged: (_) => onSelectToggle(),
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
