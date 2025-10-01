// lib/screens/community_member_select_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dev/dev_seed.dart';
import '../dev/dev_users.dart';
import '../models/app_user.dart';
import '../models/community.dart';
import '../models/membership.dart';
import '../models/payment_request.dart';
import '../models/split_rounding_mode.dart';
import '../services/chat_service.dart';
import '../services/community_service.dart';
import '../services/firestore_refs.dart';
import '../services/request_service.dart';
import '../services/task_service.dart';
import '../constants/community.dart';
import 'community_join_requests_screen.dart';
import 'member_chat_screen.dart';
import 'transactions/transaction_flow_screen.dart';
import 'wallet_screen.dart';

// ---- Membership convenience extension (status) ----
extension _MembershipStatusX on Membership {
  // Treat pending flag as a status string for uniform filtering.
  String? get status => pending ? 'pending' : role;
}

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

enum _TalkFilterOption { all, unread, mention, active }

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
  final TextEditingController _talkSearchController = TextEditingController();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _communitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _membersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _joinRequestsSubscription;

  Community? _community;
  String? _communityError;

  List<_SelectableMember> _members = <_SelectableMember>[];
  String? _membersError;
  bool _membersLoading = true;
  int _membersUpdateToken = 0;
  int _pendingJoinRequestCount = 0;
  bool _joinRequestInitialized = false;

  MemberFilter _activeFilter = MemberFilter.all;
  MemberSortOption _sortOption = MemberSortOption.recent;
  String _searchQuery = '';
  final Set<String> _selectedUids = <String>{};
  _CommunityDashboardTab _activeDashboardTab =
      _CommunityDashboardTab.talk;
  bool _requireApprovalSetting = true;
  bool _isDiscoverableSetting = false;
  bool _dualApprovalEnabled = true;
  String _talkSearchQuery = '';
  _TalkFilterOption _talkFilter = _TalkFilterOption.all;
  final ChatService _chatService = ChatService();
  final Set<String> _pinningThreads = <String>{};
  final Set<String> _markingReadThreads = <String>{};
  final RequestService _requestService = RequestService();
  final TaskService _taskService = TaskService();
  final CommunityService _communityService = CommunityService();
  String? _processingRequestId;
  bool _bulkActionInProgress = false;
  bool _updatingApprovalSetting = false;
  bool _updatingDiscoverableSetting = false;
  bool _leavingCommunity = false;
  bool _deletingCommunity = false;
  bool _minting = false;
  bool _burning = false;
  bool _dualApprovalUpdating = false;
  String? _bankPermissionUpdatingUid;
  bool _addingBankManager = false;

  // ---- Derived counts ----
  int get _pendingCount => _members
    .where((_SelectableMember member) => (member.membership.status ?? '') == 'pending')
    .length;

  int get _bankManagerCount => _members
    .where((_SelectableMember member) => member.membership.canManageBank == true)
    .length;

  // Total approvals waiting: member pending + join request pending
  int get pendingApprovals => _pendingCount + _pendingJoinRequestCount;

  @override
  void initState() {
    super.initState();
    if (isDev && widget.currentUserUid.isNotEmpty) {
      setActiveDevUid(widget.currentUserUid);
    }
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() => _searchQuery = query);
      }
    });
    _talkSearchController.addListener(_handleTalkSearchChanged);
    _subscribeCommunity();
    _subscribeMembers();
  }

  @override
  void dispose() {
    _communitySubscription?.cancel();
    _membersSubscription?.cancel();
    _joinRequestsSubscription?.cancel();
    _searchController.dispose();
    _talkSearchController.removeListener(_handleTalkSearchChanged);
    _talkSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDashboardTabSelected(_CommunityDashboardTab tab) {
    if (_activeDashboardTab == tab) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => _activeDashboardTab = tab);
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _showDevMenu() {
    if (!isDev) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _DevMenuSheet(
          communityId: widget.communityId,
          currentUid: widget.currentUserUid,
          onReopenRequested: (String uid) {
            Navigator.of(sheetContext).pop();
            _reopenAsDevUser(uid);
          },
          onSeedRequested: () async {
            Navigator.of(sheetContext).pop();
            await seedDevData(widget.communityId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Devシードを投入しました')),
            );
          },
          onAddPendingRequested: () async {
            Navigator.of(sheetContext).pop();
            await addPendingMembers(widget.communityId, count: 3);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('承認待ちメンバーを3件追加しました')),
            );
          },
        );
      },
    );
  }

  Future<void> _reopenAsDevUser(String uid) async {
    if (!mounted) return;
    rememberDevUser(uid);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CommunityMemberSelectScreen(
          communityId: widget.communityId,
          currentUserUid: uid,
          initialCommunityName: widget.initialCommunityName,
          currentUserRole: widget.currentUserRole,
        ),
      ),
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
    final pendingCount = _pendingCount + _pendingJoinRequestCount;
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
    final pendingCount = _pendingJoinRequestCount;
    const filters = [
      _FilterChipConfig(
        label: 'すべて',
        value: _TalkFilterOption.all,
        isPrimary: true,
      ),
      _FilterChipConfig(
        label: '未読',
        value: _TalkFilterOption.unread,
      ),
      _FilterChipConfig(
        label: 'メンション',
        value: _TalkFilterOption.mention,
        trailingBadge: '@',
      ),
      _FilterChipConfig(
        label: '参加中',
        value: _TalkFilterOption.active,
      ),
    ];

    final threadQuery = FirebaseFirestore.instance
        .collection('community_chats')
        .doc(widget.communityId)
        .collection('threads')
        .where('participants', arrayContains: widget.currentUserUid)
        .orderBy('updatedAt', descending: true);

    final children = <Widget>[];
    if (pendingCount > 0) {
      children
        ..add(
          _HighlightBanner(
            icon: Icons.info_outline,
            backgroundColor: _kAccentOrange.withOpacity(0.1),
            iconColor: _kAccentOrange,
            message: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '承認待ち依頼が '),
                  TextSpan(
                    text: '$pendingCount件',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' あります。'),
                ],
              ),
              style: const TextStyle(fontSize: 13, color: _kTextMain),
            ),
            actionLabel: '一覧へ',
            onAction: _openJoinRequests,
          ),
        )
        ..add(const SizedBox(height: 16));
    }

    children
      ..add(
        _DashboardSearchField(
          controller: _talkSearchController,
          hintText: 'チャンネル・メッセージ検索',
        ),
      )
      ..add(const SizedBox(height: 12))
      ..add(
        _ScrollableFilterRow(
          filters: filters,
          activeValue: _talkFilter,
          onFilterTap: (chip) {
            final value = chip.value as _TalkFilterOption?;
            final next = value ?? _TalkFilterOption.all;
            if (next == _talkFilter) return;
            setState(() => _talkFilter = next);
          },
        ),
      )
      ..add(const SizedBox(height: 20))
      ..add(
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: threadQuery.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _TalkMessageCard(
                message: 'トークを取得できませんでした: ${snapshot.error}',
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const _TalkMessageCard(message: 'まだトークがありません。');
            }
            return FutureBuilder<List<_TalkChannelEntry?>>(
              future: Future.wait(docs.map(_createTalkEntry)),
              builder: (context, entriesSnapshot) {
                if (entriesSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (entriesSnapshot.hasError) {
                  return _TalkMessageCard(
                    message: 'トークを処理できませんでした: ${entriesSnapshot.error}',
                  );
                }
                final entries =
                    (entriesSnapshot.data ?? const <_TalkChannelEntry?>[])
                        .whereType<_TalkChannelEntry>()
                        .toList();
                if (entries.isEmpty) {
                  return const _TalkMessageCard(message: 'トークがありません。');
                }
                final filtered = _filterTalkEntries(entries);
                if (filtered.isEmpty) {
                  return const _TalkMessageCard(
                    message: '条件に一致するトークがありません。',
                  );
                }

                final pinned = filtered.where((e) => e.isPinned).toList();
                final unread = filtered
                    .where((e) => !e.isPinned && e.unreadCount > 0)
                    .toList();
                final recent = filtered
                    .where((e) => !e.isPinned && e.unreadCount == 0)
                    .toList();

                _sortTalkEntries(pinned);
                _sortUnreadEntries(unread);
                _sortTalkEntries(recent);

                final sections = <Widget>[];

                void addSection(String title, List<_TalkChannelEntry> items) {
                  if (items.isEmpty) return;
                  if (sections.isNotEmpty) {
                    sections.add(const SizedBox(height: 16));
                  }
                  sections.add(
                    _TalkChannelGroup(
                      title: title,
                      entries: items,
                      onTapChannel: _openTalkThread,
                      onTogglePin: _toggleTalkPin,
                      pinningThreadIds: _pinningThreads,
                    ),
                  );
                }

                addSection('ピン留め', pinned);
                addSection('未読', unread);
                addSection('最近', recent);

                if (sections.isEmpty) {
                  return const _TalkMessageCard(
                    message: '条件に一致するトークがありません。',
                  );
                }

                return Column(children: sections);
              },
            );
          },
        ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildWalletSection(String currencyCode) {
    final membership = _findMemberByUid(widget.currentUserUid)?.membership;
    final balance = membership?.balance ?? 0;
    final userUid = widget.currentUserUid;

    final pendingQuery = FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.communityId)
        .collection('items')
        .where('status', isEqualTo: 'pending')
        .where('toUid', isEqualTo: userUid);

    final ledgerQuery = FirebaseFirestore.instance
        .collection('ledger')
        .doc(widget.communityId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(50);

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
        backgroundColor: Color(0xFFFFEDD5),
        foregroundColor: _kAccentOrange,
      ),
    ];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingQuery.snapshots(),
      builder: (context, pendingSnapshot) {
        if (pendingSnapshot.connectionState == ConnectionState.waiting &&
            !pendingSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (pendingSnapshot.hasError) {
          return _WalletMessageCard(
            message: '承認リクエストを取得できませんでした: ${pendingSnapshot.error}',
          );
        }

        final pendingDocs = pendingSnapshot.data?.docs ?? const [];
        final paymentRequests = <PaymentRequest>[];
        for (final doc in pendingDocs) {
          try {
            paymentRequests.add(
              PaymentRequest.fromMap(id: doc.id, data: doc.data()),
            );
          } catch (e, stack) {
            debugPrint('Failed to parse payment request ${doc.id}: $e\n$stack');
          }
        }
        paymentRequests.sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ledgerQuery.snapshots(),
          builder: (context, ledgerSnapshot) {
            if (ledgerSnapshot.connectionState == ConnectionState.waiting &&
                !ledgerSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (ledgerSnapshot.hasError) {
              return _WalletMessageCard(
                message: '取引履歴を取得できませんでした: ${ledgerSnapshot.error}',
              );
            }

            final ledgerDocs = ledgerSnapshot.data?.docs ?? const [];
            final transactions = <_WalletTransaction>[];
            num monthlyInflow = 0;
            num monthlyOutflow = 0;
            final now = DateTime.now();

            for (final doc in ledgerDocs) {
              final data = doc.data();
              final fromUid = (data['fromUid'] as String?) ?? '';
              final toUid = (data['toUid'] as String?) ?? '';
              if (fromUid != userUid && toUid != userUid) {
                continue;
              }
              final amount = (data['amount'] as num?) ?? 0;
              final createdAt = _parseTimestamp(data['createdAt']);
              final memo = (data['memo'] as String?)?.trim();
              final isDeposit = toUid == userUid;
              final counterpartyUid = isDeposit ? fromUid : toUid;
              final counterpartyName = _displayNameFor(counterpartyUid);
              final title = memo != null && memo.isNotEmpty
                  ? memo
                  : isDeposit
                      ? '$counterpartyName から受け取り'
                      : '$counterpartyName へ送金';
              final subtitle = _formatWalletTimestamp(createdAt);
              final adjustedAmount = isDeposit ? amount : -amount;

              if (createdAt != null &&
                  createdAt.year == now.year &&
                  createdAt.month == now.month) {
                if (isDeposit) {
                  monthlyInflow += amount;
                } else {
                  monthlyOutflow += amount.abs();
                }
              }

              transactions.add(
                _WalletTransaction(
                  title: title,
                  subtitle: subtitle,
                  amount: adjustedAmount,
                  type: isDeposit
                      ? WalletActivityType.deposit
                      : WalletActivityType.withdrawal,
                  timestamp: createdAt,
                  counterpartyUid: counterpartyUid,
                ),
              );
            }

            transactions.sort((a, b) {
              final at = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });

            final recentTransactions = transactions.take(5).toList();
            final pendingCount = paymentRequests.length;
            final pendingRequest =
                paymentRequests.isEmpty ? null : paymentRequests.first;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WalletBalanceCard(
                  currencyCode: currencyCode,
                  balance: balance,
                  monthlyInflow: monthlyInflow,
                  monthlyOutflow: monthlyOutflow,
                  pendingCount: pendingCount,
                ),
                const SizedBox(height: 16),
                _WalletActionGrid(
                  actions: quickActions,
                  onTap: (label) => _handleWalletAction(label, currencyCode),
                ),
                const SizedBox(height: 16),
                if (pendingRequest != null)
                  _WalletApprovalCard(
                    requester: _displayNameFor(pendingRequest.fromUid),
                    amount: pendingRequest.amount,
                    currencyCode: currencyCode,
                    memo: pendingRequest.memo ?? 'メモなし',
                    processing: _processingRequestId == pendingRequest.id,
                    onApprove: () =>
                        _handleApproveRequest(pendingRequest, currencyCode),
                    onReject: () => _handleRejectRequest(pendingRequest),
                  )
                else
                  const _WalletMessageCard(
                    message: '現在、承認待ちのリクエストはありません。',
                  ),
                const SizedBox(height: 16),
                _WalletTransactionList(
                  transactions: recentTransactions,
                  currencyCode: currencyCode,
                  onViewAll: () => _openWalletScreen(currencyCode),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsSection() {
    final communityName = _community?.name ?? 'コミュニティ';
    final notificationMode =
        _notificationModeLabel(_community?.notificationDefault ?? '@mentions');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SettingsSectionTitle('基本情報'),
        const SizedBox(height: 8),
        _SettingsListTile(
          icon: Icons.edit_outlined,
          title: 'コミュニティ名',
          subtitle: communityName,
          onTap: _editCommunityName,
        ),
        const SizedBox(height: 12),
        _SettingsListTile(
          icon: Icons.photo_library_outlined,
          title: 'アイコンとカバー',
          subtitle: '変更',
          onTap: _editCommunityImages,
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('通知・表示'),
        const SizedBox(height: 8),
        _SettingsListTile(
          icon: Icons.notifications_active_outlined,
          title: '通知の既定',
          subtitle: notificationMode,
          onTap: _changeNotificationDefault,
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('参加設定'),
        const SizedBox(height: 8),
        _SettingsToggleTile(
          icon: Icons.verified_user_outlined,
          title: '参加承認',
          description: '参加に管理者の承認を必要とする',
          value: _requireApprovalSetting,
          onChanged: _toggleApprovalSetting,
          enabled: !_updatingApprovalSetting,
          loading: _updatingApprovalSetting,
        ),
        const SizedBox(height: 12),
        _SettingsToggleTile(
          icon: Icons.travel_explore_outlined,
          title: '公開設定',
          description: 'コミュニティを検索可能にする',
          value: _isDiscoverableSetting,
          onChanged: _toggleDiscoverableSetting,
          enabled: !_updatingDiscoverableSetting,
          loading: _updatingDiscoverableSetting,
        ),
        const SizedBox(height: 24),
        const _SettingsSectionTitle('Danger Zone'),
        const SizedBox(height: 8),
        _DangerZoneTile(
          title: 'コミュニティから退出する',
          description: 'この操作は元に戻せません。',
          onTap: _confirmLeaveCommunity,
          enabled: !_leavingCommunity,
          loading: _leavingCommunity,
        ),
        const SizedBox(height: 12),
        _DangerZoneTile(
          title: 'コミュニティを削除する',
          description: 'すべてのデータが完全に削除されます。',
          onTap: _confirmDeleteCommunity,
          enabled: !_deletingCommunity,
          loading: _deletingCommunity,
        ),
      ],
    );
  }

  Widget _buildBankSection(String currencyCode) {
    final treasury = _community?.treasury;
    final balance = treasury?.balance ?? 0;
    final reserve = treasury?.initialGrant ?? 0;
    final allowMinting = _community?.currency.allowMinting ?? true;
    final isOwner = _community?.ownerUid == widget.currentUserUid;
    final permissionMembers = [
      for (final member in _members)
        if (member.membership.canManageBank)
          _BankPermissionMember(
            uid: member.membership.userId,
            name: member.displayName,
            role: member.membership.role,
            avatarUrl: _MemberAvatar._tryGetAvatarUrl(member.profile),
            locked: member.membership.role.toLowerCase() == 'owner',
          ),
    ]
      ..sort((a, b) => a.name.compareTo(b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BankSummaryGrid(
          balance: balance,
          reserve: reserve,
          currencyCode: currencyCode,
          allowMinting: allowMinting,
        ),
        const SizedBox(height: 16),
        _BankPrimaryActions(
          onMint: () => _handleMint(currencyCode),
          onBurn: () => _handleBurn(currencyCode),
          minting: _minting,
          burning: _burning,
        ),
        const SizedBox(height: 16),
        _BankCurrencyList(
          currencyCode: currencyCode,
          currencyName: _community?.currency.name ?? '既定通貨',
        ),
        const SizedBox(height: 16),
        _BankPolicyCard(
          dualApprovalEnabled: _dualApprovalEnabled,
          onToggleDualApproval: _toggleDualApproval,
          mintRolesLabel: 'Owner, BankAdmin',
          dailyLimit: '100,000 $currencyCode',
          processing: _dualApprovalUpdating,
        ),
        const SizedBox(height: 16),
        _BankPermissionCard(
          members: permissionMembers,
          onAddMember: _handleAddBankManager,
          onRemoveMember: _handleRemoveBankManager,
          canModify: isOwner,
          adding: _addingBankManager,
          updatingUid: _bankPermissionUpdatingUid,
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
          _isDiscoverableSetting = community.discoverable;
          _dualApprovalEnabled = community.treasury.dualApprovalEnabled;
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

    final joinRequestsQuery = FirebaseFirestore.instance
        .collection('join_requests')
        .doc(widget.communityId)
        .collection('items')
        .where('status', isEqualTo: 'pending');
    _joinRequestsSubscription = joinRequestsQuery.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        final newCount = snapshot.docs.length;
        final shouldNotify =
            _joinRequestInitialized && newCount > _pendingJoinRequestCount;
        setState(() {
          _pendingJoinRequestCount = newCount;
          _joinRequestInitialized = true;
        });
        if (shouldNotify) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('新しい参加申請が届きました')),
            );
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        if (!_joinRequestInitialized) {
          setState(() {
            _pendingJoinRequestCount = 0;
            _joinRequestInitialized = true;
          });
        }
      },
    );
  }

  void _handleTalkSearchChanged() {
    final query = _talkSearchController.text.trim();
    if (query == _talkSearchQuery) {
      return;
    }
    setState(() => _talkSearchQuery = query);
  }

  _SelectableMember? _findMemberByUid(String uid) {
    for (final member in _members) {
      if (member.membership.userId == uid) {
        return member;
      }
    }
    return null;
  }

  String? get _currentUserDisplayName {
    final self = _findMemberByUid(widget.currentUserUid);
    if (self != null) {
      return self.displayName;
    }
    return FirebaseAuth.instance.currentUser?.displayName;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  bool _detectMention(String message, String senderUid) {
    if (message.isEmpty || senderUid == widget.currentUserUid) {
      return false;
    }
    final lower = message.toLowerCase();
    final displayName = _currentUserDisplayName?.toLowerCase();
    if (displayName != null && displayName.isNotEmpty) {
      if (lower.contains('@$displayName')) {
        return true;
      }
    }
    return lower.contains('@${widget.currentUserUid.toLowerCase()}');
  }

  Future<_TalkChannelEntry?> _createTalkEntry(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      final data = doc.data();
      final participants =
          (data['participants'] as List<dynamic>?)?.cast<String>() ?? const [];
      final partnerUid = participants
          .firstWhere((uid) => uid != widget.currentUserUid, orElse: () => '');
      if (partnerUid.isEmpty) return null;

      final member = _findMemberByUid(partnerUid);
      String displayName = member?.displayName ?? partnerUid;
      String? photoUrl = _MemberAvatar._tryGetAvatarUrl(member?.profile);
      String memberRole = member?.membership.role ?? 'member';

      if (member == null) {
        final userSnap =
            await FirebaseFirestore.instance.doc('users/$partnerUid').get();
        final userData = userSnap.data();
        if (userData != null) {
          final candidate = (userData['displayName'] as String?)?.trim();
          if (candidate != null && candidate.isNotEmpty) {
            displayName = candidate;
          }
          for (final key in const [
            'photoUrl',
            'photoURL',
            'avatarUrl',
            'imageUrl',
            'iconUrl'
          ]) {
            final value = (userData[key] as String?)?.trim();
            if (value != null && value.isNotEmpty) {
              photoUrl = value;
              break;
            }
          }
        }

        final membershipSnap = await FirebaseFirestore.instance
            .doc('memberships/${FirestoreRefs.membershipId(widget.communityId, partnerUid)}')
            .get();
        final membershipData = membershipSnap.data();
        if (membershipData != null) {
          final role = (membershipData['role'] as String?)?.trim();
          if (role != null && role.isNotEmpty) {
            memberRole = role;
          }
        }
      }

      final lastMessage = (data['lastMessage'] as String?) ?? '';
      final lastSenderUid = (data['lastSenderUid'] as String?) ?? '';
      final unreadMap =
          (data['unreadCounts'] as Map<String, dynamic>?) ?? const {};
      final unreadValue = unreadMap[widget.currentUserUid];
      final unread = unreadValue is num ? unreadValue.toInt() : 0;
      final updatedAt = _parseTimestamp(data['updatedAt']);

      final preview = lastMessage.isEmpty
          ? 'メッセージはまだありません'
          : (lastSenderUid == widget.currentUserUid
              ? 'あなた: $lastMessage'
              : '$displayName: $lastMessage');

      final pinnedBy =
          (data['pinnedBy'] as List<dynamic>?)?.cast<String>() ?? const [];
      final hasMention = _detectMention(lastMessage, lastSenderUid);
      final communityName =
          _community?.name ?? widget.initialCommunityName ?? widget.communityId;

      return _TalkChannelEntry(
        threadId: doc.id,
        communityId: widget.communityId,
        communityName: communityName,
        partnerUid: partnerUid,
        partnerDisplayName: displayName,
        previewText: preview,
        updatedAt: updatedAt,
        unreadCount: unread,
        hasMention: hasMention,
        isPinned: pinnedBy.contains(widget.currentUserUid),
        partnerPhotoUrl: photoUrl,
        memberRole: memberRole,
      );
    } catch (e, stack) {
      debugPrint('Failed to build talk entry: $e\n$stack');
      return null;
    }
  }

  List<_TalkChannelEntry> _filterTalkEntries(List<_TalkChannelEntry> entries) {
    final query = _talkSearchQuery.toLowerCase();
    return [
      for (final entry in entries)
        if (_matchesTalkFilter(entry) &&
            (query.isEmpty ||
                ('${entry.partnerDisplayName} ${entry.previewText} ${entry.communityName}')
                    .toLowerCase()
                    .contains(query)))
          entry
    ];
  }

  bool _matchesTalkFilter(_TalkChannelEntry entry) {
    switch (_talkFilter) {
      case _TalkFilterOption.all:
        return true;
      case _TalkFilterOption.unread:
        return entry.unreadCount > 0;
      case _TalkFilterOption.mention:
        return entry.hasMention;
      case _TalkFilterOption.active:
        return _isTalkEntryActive(entry);
    }
  }

  bool _isTalkEntryActive(_TalkChannelEntry entry) {
    if (entry.unreadCount > 0) {
      return true;
    }
    final updated = entry.updatedAt;
    if (updated == null) {
      return false;
    }
    return updated.isAfter(DateTime.now().subtract(const Duration(days: 7)));
  }

  void _sortTalkEntries(List<_TalkChannelEntry> entries) {
    entries.sort((a, b) {
      final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return timeB.compareTo(timeA);
    });
  }

  void _sortUnreadEntries(List<_TalkChannelEntry> entries) {
    entries.sort((a, b) {
      final unreadDiff = b.unreadCount.compareTo(a.unreadCount);
      if (unreadDiff != 0) {
        return unreadDiff;
      }
      final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return timeB.compareTo(timeA);
    });
  }

  Future<void> _openTalkThread(_TalkChannelEntry entry) async {
    if (_markingReadThreads.contains(entry.threadId)) {
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のユーザー情報を確認できませんでした。')),
      );
      return;
    }
    setState(() => _markingReadThreads.add(entry.threadId));
    try {
      await _chatService.markThreadAsRead(
        communityId: entry.communityId,
        threadId: entry.threadId,
        userUid: widget.currentUserUid,
      );
    } catch (e) {
      debugPrint('Failed to mark thread as read: $e');
    } finally {
      if (mounted) {
        setState(() => _markingReadThreads.remove(entry.threadId));
      }
    }

    if (!mounted) return;
    try {
      await MemberChatScreen.open(
        context,
        communityId: entry.communityId,
        communityName: entry.communityName,
        currentUser: currentUser,
        partnerUid: entry.partnerUid,
        partnerDisplayName: entry.partnerDisplayName,
        partnerPhotoUrl: entry.partnerPhotoUrl,
        threadId: entry.threadId,
        memberRole: entry.memberRole,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットを開けませんでした: $e')),
      );
    }
  }

  Future<void> _toggleTalkPin(_TalkChannelEntry entry) async {
    if (_pinningThreads.contains(entry.threadId)) {
      return;
    }
    setState(() => _pinningThreads.add(entry.threadId));
    try {
      await FirebaseFirestore.instance
          .collection('community_chats')
          .doc(entry.communityId)
          .collection('threads')
          .doc(entry.threadId)
          .set(
        {
          'pinnedBy': entry.isPinned
              ? FieldValue.arrayRemove([widget.currentUserUid])
              : FieldValue.arrayUnion([widget.currentUserUid]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ピン留めを変更できませんでした: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pinningThreads.remove(entry.threadId));
      }
    }
  }

  Future<void> _startDirectChat(_SelectableMember member) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のユーザー情報を確認できませんでした。')),
      );
      return;
    }
    final partnerUid = member.membership.userId;
    if (partnerUid == widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自分自身にはメッセージを送信できません。')),
      );
      return;
    }
    final communityName =
        _community?.name ?? widget.initialCommunityName ?? widget.communityId;
    final threadId = ChatService.buildThreadId(currentUser.uid, partnerUid);
    final photoUrl = _MemberAvatar._tryGetAvatarUrl(member.profile);
    try {
      await MemberChatScreen.open(
        context,
        communityId: widget.communityId,
        communityName: communityName,
        currentUser: currentUser,
        partnerUid: partnerUid,
        partnerDisplayName: member.displayName,
        partnerPhotoUrl: photoUrl,
        threadId: threadId,
        memberRole: member.membership.role,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットを開けませんでした: $e')),
      );
    }
  }

  String _displayNameFor(String? uid) {
    if (uid == null || uid.isEmpty) {
      return '不明な相手';
    }
    if (uid == widget.currentUserUid) {
      return 'あなた';
    }
    if (uid == kCentralBankUid) {
      return '中央銀行';
    }
    final member = _findMemberByUid(uid);
    if (member != null) {
      return member.displayName;
    }
    return uid;
  }

  Future<void> _handleWalletAction(String label, String currencyCode) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のユーザー情報を確認できませんでした。')),
      );
      return;
    }
    try {
      switch (label) {
        case '送る':
          await TransactionFlowScreen.open(
            context,
            user: currentUser,
            communityId: widget.communityId,
            initialKind: TransactionKind.transfer,
          );
          break;
        case '請求':
          await TransactionFlowScreen.open(
            context,
            user: currentUser,
            communityId: widget.communityId,
            initialKind: TransactionKind.request,
          );
          break;
        case '割り勘':
          await TransactionFlowScreen.open(
            context,
            user: currentUser,
            communityId: widget.communityId,
            initialKind: TransactionKind.split,
          );
          break;
        case 'タスク':
          await _showCreateTaskDialog(currencyCode);
          break;
        default:
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作に失敗しました: $e')),
      );
    }
  }

  Future<void> _openWalletScreen(String currencyCode) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のユーザー情報を確認できませんでした。')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletScreen(user: currentUser),
      ),
    );
  }

  Future<void> _handleApproveRequest(
      PaymentRequest request, String currencyCode) async {
    if (_processingRequestId != null) {
      return;
    }
    setState(() => _processingRequestId = request.id);
    try {
      await _requestService.approveRequest(
        communityId: request.communityId,
        requestId: request.id,
        approvedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      final requester = _displayNameFor(request.fromUid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$requester の請求を承認しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('承認に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingRequestId = null);
      }
    }
  }

  Future<void> _handleRejectRequest(PaymentRequest request) async {
    if (_processingRequestId != null) {
      return;
    }
    setState(() => _processingRequestId = request.id);
    try {
      await _requestService.rejectRequest(
        communityId: request.communityId,
        requestId: request.id,
        rejectedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      final requester = _displayNameFor(request.fromUid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$requester の請求を却下しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('却下に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingRequestId = null);
      }
    }
  }

  Future<void> _showCreateTaskDialog(String currencyCode) async {
    final titleCtrl = TextEditingController();
    final rewardCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          bool submitting = false;
          return StatefulBuilder(
            builder: (context, setState) {
              Future<void> submit() async {
                final title = titleCtrl.text.trim();
                final rewardValue = rewardCtrl.text.trim();
                final reward = num.tryParse(rewardValue);
                if (title.isEmpty || reward == null || reward <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('タイトルと正しい金額を入力してください。')),
                  );
                  return;
                }
                setState(() => submitting = true);
                try {
                  await _taskService.createTask(
                    communityId: widget.communityId,
                    title: title,
                    description: memoCtrl.text.trim().isEmpty
                        ? null
                        : memoCtrl.text.trim(),
                    reward: reward,
                    createdBy: widget.currentUserUid,
                  );
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('タスク「$title」を作成しました ($reward $currencyCode)'),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('タスクの作成に失敗しました: $e')),
                  );
                } finally {
                  if (mounted) {
                    setState(() => submitting = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('新しいタスクを作成'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'タイトル'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: rewardCtrl,
                        decoration:
                            InputDecoration(labelText: '報酬 ($currencyCode)'),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: false,
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: memoCtrl,
                        decoration: const InputDecoration(labelText: 'メモ (任意)'),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('作成'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleCtrl.dispose();
      rewardCtrl.dispose();
      memoCtrl.dispose();
    }
  }

  Future<void> _handleBulkRequest(String currencyCode) async {
    final targets = _selectedUids
        .where((uid) => uid != widget.currentUserUid)
        .toList(growable: false);
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自分以外のメンバーを選択してください。')),
      );
      return;
    }
    final input = await _showBulkRequestDialog(currencyCode);
    if (input == null) {
      return;
    }
    final precision = _community?.currency.precision ?? 0;
    setState(() => _bulkActionInProgress = true);
    try {
      await _requestService.createSplitRequests(
        communityId: widget.communityId,
        requesterUid: widget.currentUserUid,
        targetUids: targets,
        totalAmount: input.totalAmount,
        precision: precision,
        roundingMode: SplitRoundingMode.even,
        memo: input.memo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '選択した${targets.length}人に${input.totalAmount.toStringAsFixed(0)} $currencyCode を請求しました'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('まとめて請求に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkActionInProgress = false);
      }
    }
  }

  Future<_SplitRequestInput?> _showBulkRequestDialog(
      String currencyCode) async {
    final amountCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    try {
      return await showDialog<_SplitRequestInput>(
        context: context,
        builder: (dialogContext) {
          bool submitting = false;
          return StatefulBuilder(
            builder: (context, setState) {
              Future<void> submit() async {
                final total = num.tryParse(amountCtrl.text.trim());
                if (total == null || total <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('正しい金額を入力してください。')),
                  );
                  return;
                }
                setState(() => submitting = true);
                Navigator.of(dialogContext).pop(
                  _SplitRequestInput(
                    totalAmount: total,
                    memo: memoCtrl.text.trim().isEmpty
                        ? null
                        : memoCtrl.text.trim(),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('まとめて請求'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountCtrl,
                        decoration: InputDecoration(
                          labelText: '合計金額 ($currencyCode)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: memoCtrl,
                        decoration: const InputDecoration(labelText: 'メモ (任意)'),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('請求'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      amountCtrl.dispose();
      memoCtrl.dispose();
    }
  }

  Future<void> _handleBulkMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != widget.currentUserUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のユーザー情報を確認できませんでした。')),
      );
      return;
    }
    if (_selectedUids.isEmpty) {
      return;
    }
    final message = await _showBulkMessageDialog();
    if (message == null || message.trim().isEmpty) {
      return;
    }
    setState(() => _bulkActionInProgress = true);
    try {
      for (final uid in _selectedUids) {
        if (uid == widget.currentUserUid) continue;
        await _chatService.sendMessage(
          communityId: widget.communityId,
          senderUid: currentUser.uid,
          receiverUid: uid,
          message: message,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('選択したメンバーにメッセージを送信しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージ送信に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkActionInProgress = false);
      }
    }
  }

  Future<String?> _showBulkMessageDialog() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('一括メッセージ'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'メッセージ内容',
                hintText: '全員に送るメッセージ',
              ),
              maxLines: 4,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('送信'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  String _notificationModeLabel(String value) {
    switch (value) {
      case 'all':
        return 'すべての通知';
      case 'none':
        return '通知しない';
      default:
        return '@メンションのみ';
    }
  }

  Future<void> _editCommunityName() async {
    final controller = TextEditingController(text: _community?.name ?? '');
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('コミュニティ名を編集'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'コミュニティ名'),
              textInputAction: TextInputAction.done,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
      if (name == null) {
        return;
      }
      if (name.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名称を入力してください。')),
        );
        return;
      }
      await _communityService.updateCommunityName(
        communityId: widget.communityId,
        name: name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('コミュニティ名を「$name」に更新しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('コミュニティ名の更新に失敗しました: $e')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editCommunityImages() async {
    final iconCtrl = TextEditingController(text: _community?.iconUrl ?? '');
    final coverCtrl = TextEditingController(text: _community?.coverUrl ?? '');
    try {
      final result = await showDialog<Map<String, String?>>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('アイコン / カバーを更新'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: iconCtrl,
                    decoration: const InputDecoration(
                      labelText: 'アイコンURL',
                      hintText: 'https://example.com/icon.png',
                    ),
                  ),
                  TextField(
                    controller: coverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'カバー画像URL',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop({
                  'icon': iconCtrl.text.trim().isEmpty
                      ? null
                      : iconCtrl.text.trim(),
                  'cover': coverCtrl.text.trim().isEmpty
                      ? null
                      : coverCtrl.text.trim(),
                }),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
      if (result == null) return;
      await _communityService.updateCommunityImages(
        communityId: widget.communityId,
        iconUrl: result['icon'],
        coverUrl: result['cover'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画像設定を更新しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像設定の更新に失敗しました: $e')),
      );
    } finally {
      iconCtrl.dispose();
      coverCtrl.dispose();
    }
  }

  Future<void> _changeNotificationDefault() async {
    final currentValue = _community?.notificationDefault ?? '@mentions';
    final options = {
      'all': 'すべての通知',
      '@mentions': '@メンションのみ',
      'none': '通知しない',
    };
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('通知の既定を選択'),
              ),
              for (final entry in options.entries)
                RadioListTile<String>(
                  value: entry.key,
                  groupValue: currentValue,
                  title: Text(entry.value),
                  onChanged: (value) => Navigator.of(context).pop(value),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == currentValue) {
      return;
    }
    try {
      await _communityService.updateNotificationDefault(
        communityId: widget.communityId,
        notificationDefault: selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通知設定を「${options[selected]}」に更新しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通知設定の更新に失敗しました: $e')),
      );
    }
  }

  Future<void> _toggleApprovalSetting(bool value) async {
    if (_updatingApprovalSetting) return;
    setState(() {
      _updatingApprovalSetting = true;
      _requireApprovalSetting = value;
    });
    try {
      await _communityService.updateJoinApproval(
        communityId: widget.communityId,
        requiresApproval: value,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _requireApprovalSetting = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加承認設定の更新に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingApprovalSetting = false);
      }
    }
  }

  Future<void> _toggleDiscoverableSetting(bool value) async {
    if (_updatingDiscoverableSetting) return;
    setState(() {
      _updatingDiscoverableSetting = true;
      _isDiscoverableSetting = value;
    });
    try {
      await _communityService.updateDiscoverable(
        communityId: widget.communityId,
        discoverable: value,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDiscoverableSetting = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('公開設定の更新に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingDiscoverableSetting = false);
      }
    }
  }

  Future<void> _confirmLeaveCommunity() async {
    if (_leavingCommunity) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('コミュニティから退出しますか？'),
          content: const Text('この操作は元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('退出する'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    setState(() => _leavingCommunity = true);
    try {
      await _communityService.leaveCommunity(
        communityId: widget.communityId,
        userId: widget.currentUserUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コミュニティから退出しました')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('退出に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _leavingCommunity = false);
      }
    }
  }

  Future<void> _confirmDeleteCommunity() async {
    if (_deletingCommunity) return;
    final controller = TextEditingController();
    final name = _community?.name ?? widget.communityId;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('コミュニティを削除しますか？'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('この操作は取り消せません。削除するには "$name" と入力してください。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '確認のために入力',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () {
                  final input = controller.text.trim();
                  Navigator.of(dialogContext).pop(input == name);
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('削除する'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
      setState(() => _deletingCommunity = true);
      await _communityService.deleteCommunity(
        communityId: widget.communityId,
        performedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コミュニティを削除しました')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingCommunity = false);
      }
      controller.dispose();
    }
  }

  Future<void> _handleMint(String currencyCode) async {
    final amount = await _promptAmountDialog('発行 (Mint)', currencyCode);
    if (amount == null) return;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1以上の金額を入力してください。')),
      );
      return;
    }
    setState(() => _minting = true);
    try {
      await _communityService.adjustTreasuryBalance(
        communityId: widget.communityId,
        delta: amount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${amount.toStringAsFixed(0)} $currencyCode を発行しました'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('発行に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _minting = false);
      }
    }
  }

  Future<void> _handleBurn(String currencyCode) async {
    final amount = await _promptAmountDialog('回収 (Burn)', currencyCode);
    if (amount == null) return;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1以上の金額を入力してください。')),
      );
      return;
    }
    setState(() => _burning = true);
    try {
      await _communityService.adjustTreasuryBalance(
        communityId: widget.communityId,
        delta: -amount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${amount.toStringAsFixed(0)} $currencyCode を回収しました'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回収に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _burning = false);
      }
    }
  }

  Future<void> _handleAddBankManager() async {
    if (_addingBankManager) return;
    final candidates = _members
        .where((member) =>
            !member.membership.canManageBank && !member.membership.pending)
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追加できるメンバーがいません。')),
      );
      return;
    }
    final selectedUid = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('権限を付与するメンバーを選択'),
              ),
              for (final member in candidates)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(member.displayName.characters.first),
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(member.membership.role),
                  onTap: () => Navigator.of(context).pop(member.membership.userId),
                ),
            ],
          ),
        );
      },
    );
    if (selectedUid == null) return;
    setState(() => _addingBankManager = true);
    try {
      await _communityService.setBankManagementPermission(
        communityId: widget.communityId,
        targetUid: selectedUid,
        enabled: true,
        updatedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      final member = candidates.firstWhere((m) => m.membership.userId == selectedUid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.displayName} を権限メンバーに追加しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('権限の付与に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _addingBankManager = false);
      }
    }
  }

  Future<void> _handleRemoveBankManager(String uid) async {
    if (_bankPermissionUpdatingUid != null) return;
    setState(() => _bankPermissionUpdatingUid = uid);
    try {
      await _communityService.setBankManagementPermission(
        communityId: widget.communityId,
        targetUid: uid,
        enabled: false,
        updatedBy: widget.currentUserUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('権限を解除しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('権限の解除に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bankPermissionUpdatingUid = null);
      }
    }
  }

  Future<void> _toggleDualApproval(bool value) async {
    if (_dualApprovalUpdating) return;
    setState(() {
      _dualApprovalUpdating = true;
      _dualApprovalEnabled = value;
    });
    try {
      await _communityService.updateTreasurySettings(
        communityId: widget.communityId,
        dualApprovalEnabled: value,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _dualApprovalEnabled = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('二重承認設定の更新に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _dualApprovalUpdating = false);
      }
    }
  }

  Future<num?> _promptAmountDialog(String title, String currencyCode) async {
    final controller = TextEditingController();
    try {
      return await showDialog<num>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration:
                  InputDecoration(labelText: '金額 ($currencyCode)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () {
                  final value = num.tryParse(controller.text.trim());
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('実行'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
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
    final filtered = _members.where((_SelectableMember member) {
      if (!_applyFilter(member)) return false;
      if (query.isEmpty) return true;
      final display = (member.profile?.displayName ?? member.membership.userId);
      final text = '$display ${member.membership.userId}'.toLowerCase();
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
        return member.membership.canManageBank == true ||
            ((member.membership.role).toLowerCase() == 'owner') ||
            ((member.membership.role).toLowerCase() == 'admin');
      case MemberFilter.pending:
        return (member.membership.status ?? '') == 'pending';
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

  // (Old derived getters replaced by versions near field declarations)

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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final media = MediaQuery.of(context);
        final joinedAt = member.membership.joinedAt;
        final currencyCode =
            _community?.currency.code ?? member.membership.communityId;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              24 + media.viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * 0.9,
              ),
              child: SingleChildScrollView(
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
                      value:
                          '${(member.profile?.completionRate ?? 0).toStringAsFixed(0)}%',
                    ),
                    _DetailTile(
                      icon: Icons.report_problem,
                      title: 'トラブル率',
                      value:
                          '${(member.profile?.disputeRate ?? 0).toStringAsFixed(0)}%',
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
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _startDirectChat(member);
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


  void _openJoinRequests() {
    if (!mounted) return;
    final communityName =
        _community?.name ?? widget.initialCommunityName ?? widget.communityId;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityJoinRequestsScreen(
          communityId: widget.communityId,
          communityName: communityName,
          currentUserUid: widget.currentUserUid,
        ),
      ),
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
    0, (num sum, _SelectableMember m) => sum + (m.membership.balance));
  final currencyCode = _community?.currency.code ?? 'PTS';

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _HeaderSection(
          community: _community,
          communityNameFallback: communityName,
          currentRole: widget.currentUserRole,
          memberCount: _members.length,
          pendingCount: pendingApprovals,
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
    ];

    switch (_activeDashboardTab) {
      case _CommunityDashboardTab.overview:
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: _buildOverviewSection(selectedBalance, currencyCode),
            ),
          ),
        );
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
        break;
      case _CommunityDashboardTab.talk:
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: _buildTalkSection(),
            ),
          ),
        );
        break;
      case _CommunityDashboardTab.wallet:
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              child: _buildWalletSection(currencyCode),
            ),
          ),
        );
        break;
      case _CommunityDashboardTab.members:
        slivers.add(
          SliverToBoxAdapter(
            child: _buildFilterSection(theme),
          ),
        );
        if (_membersLoading && _members.isEmpty) {
          slivers.add(
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        } else if (_membersError != null) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                child: _ErrorCard(
                  message: _membersError!,
                  onRetry: _refresh,
                ),
              ),
            ),
          );
        } else if (members.isEmpty) {
          slivers.add(
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 48, 20, 120),
                child: _EmptyState(),
              ),
            ),
          );
        } else {
          slivers.add(
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
          );
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 140)));
        break;
      case _CommunityDashboardTab.settings:
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: _buildSettingsSection(),
            ),
          ),
        );
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
        break;
      case _CommunityDashboardTab.bank:
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: _buildBankSection(currencyCode),
            ),
          ),
        );
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
        break;
    }

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
                slivers: slivers,
              ),
            ),
            if (_activeDashboardTab == _CommunityDashboardTab.talk)
              Positioned(
                right: 20,
                bottom: 32 + MediaQuery.of(context).padding.bottom,
                child: _DashboardFab(
                  icon: Icons.add,
                  tooltip: '新しいトークを開始',
                  onPressed: () => _showNotImplemented('新しいトーク'),
                ),
              ),
            if (_activeDashboardTab == _CommunityDashboardTab.members)
              Positioned(
                right: 20,
                bottom: 32 + MediaQuery.of(context).padding.bottom,
                child: _DashboardFab(
                  icon: Icons.person_add_alt_1,
                  tooltip: 'メンバーを招待',
                  onPressed: () => _showNotImplemented('メンバー招待'),
                ),
              ),
            if (isDev)
              Positioned(
                right: 20,
                bottom: 92 + MediaQuery.of(context).padding.bottom,
                child: _DashboardFab(
                  icon: Icons.science_outlined,
                  tooltip: 'Devメニュー',
                  onPressed: _showDevMenu,
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
            pendingCount: pendingApprovals,
            onTap: () => _openJoinRequests(),
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
    final coverUrl = community?.coverUrl?.trim();
    final hasCoverImage = _MemberAvatar._isValidUrl(coverUrl);
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
                color: const Color(0xFFE2E8F0),
              ),
              if (hasCoverImage)
                SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              Positioned.fill(
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
    this.value,
    this.isPrimary = false,
    this.trailingBadge,
  });

  final String label;
  final Object? value;
  final bool isPrimary;
  final String? trailingBadge;
}

class _ScrollableFilterRow extends StatelessWidget {
  const _ScrollableFilterRow({
    required this.filters,
    this.activeValue,
    this.onFilterTap,
  });

  final List<_FilterChipConfig> filters;
  final Object? activeValue;
  final ValueChanged<_FilterChipConfig>? onFilterTap;

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
                onTap: () => onFilterTap?.call(filter),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isFilterActive(filter) ? _kMainBlue : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _isFilterActive(filter)
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
                          color: _isFilterActive(filter)
                              ? Colors.white
                              : _kTextMain,
                        ),
                      ),
                      if (filter.trailingBadge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: _isFilterActive(filter)
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

  bool _isFilterActive(_FilterChipConfig filter) {
    if (activeValue == null) {
      return filter.isPrimary;
    }
    return filter.value == activeValue;
  }
}

class _TalkChannelEntry {
  const _TalkChannelEntry({
    required this.threadId,
    required this.communityId,
    required this.communityName,
    required this.partnerUid,
    required this.partnerDisplayName,
    required this.previewText,
    required this.updatedAt,
    required this.unreadCount,
    required this.hasMention,
    required this.isPinned,
    required this.partnerPhotoUrl,
    required this.memberRole,
  });

  final String threadId;
  final String communityId;
  final String communityName;
  final String partnerUid;
  final String partnerDisplayName;
  final String previewText;
  final DateTime? updatedAt;
  final int unreadCount;
  final bool hasMention;
  final bool isPinned;
  final String? partnerPhotoUrl;
  final String memberRole;
}

class _TalkChannelGroup extends StatelessWidget {
  const _TalkChannelGroup({
    required this.title,
    required this.entries,
    required this.onTapChannel,
    required this.onTogglePin,
    this.pinningThreadIds = const <String>{},
  });

  final String title;
  final List<_TalkChannelEntry> entries;
  final ValueChanged<_TalkChannelEntry> onTapChannel;
  final ValueChanged<_TalkChannelEntry> onTogglePin;
  final Set<String> pinningThreadIds;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
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
              onTap: () => onTapChannel(entry),
              onTogglePin: () => onTogglePin(entry),
              pinInProgress: pinningThreadIds.contains(entry.threadId),
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
    required this.onTogglePin,
    this.pinInProgress = false,
  });

  final _TalkChannelEntry entry;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final bool pinInProgress;

  @override
  Widget build(BuildContext context) {
    final borderColor = entry.isPinned
        ? _kAccentOrange.withOpacity(0.4)
        : const Color(0xFFE2E8F0);
    final timeLabel = _formatTalkCardTime(entry.updatedAt);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _TalkAvatar(
              photoUrl: entry.partnerPhotoUrl,
              label: entry.partnerDisplayName,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.partnerDisplayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kTextMain,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.previewText,
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
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kTextSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.hasMention)
                      const _TalkBadge(
                        label: '@',
                        backgroundColor: _kAccentOrange,
                      ),
                    if (entry.unreadCount > 0) ...[
                      if (entry.hasMention) const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kMainBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${entry.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    IconButton(
                      icon: Icon(
                        entry.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                        color: entry.isPinned ? _kAccentOrange : _kTextSub,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: pinInProgress ? null : onTogglePin,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TalkAvatar extends StatelessWidget {
  const _TalkAvatar({required this.photoUrl, required this.label});

  final String? photoUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 24,
      backgroundColor: _kMainBlue.withOpacity(0.15),
      child: Text(
        _MemberAvatar._initials(label),
        style: const TextStyle(
          color: _kMainBlue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return fallback;
    }
    return CircleAvatar(
      radius: 24,
      backgroundImage: NetworkImage(url),
      onBackgroundImageError: (_, __) {},
    );
  }
}

String _formatTalkCardTime(DateTime? time) {
  if (time == null) {
    return '--:--';
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  if (target == today) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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

class _TalkMessageCard extends StatelessWidget {
  const _TalkMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _kTextSub),
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

class _WalletMessageCard extends StatelessWidget {
  const _WalletMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _kTextSub),
      ),
    );
  }
}

class _SplitRequestInput {
  const _SplitRequestInput({required this.totalAmount, this.memo});

  final num totalAmount;
  final String? memo;
}

class _BulkSelectionBar extends StatelessWidget {
  const _BulkSelectionBar({
    required this.count,
    required this.onRequest,
    required this.onMessage,
    required this.processing,
  });

  final int count;
  final VoidCallback onRequest;
  final VoidCallback onMessage;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${count}人 選択中',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _kTextMain,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: processing ? null : onMessage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('一括メッセージ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: processing ? null : onRequest,
                  icon: processing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.request_quote_outlined),
                  label: Text(processing ? '処理中...' : 'まとめて請求'),
                ),
              ),
            ],
          ),
        ],
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
    this.processing = false,
  });

  final String requester;
  final num amount;
  final String currencyCode;
  final String memo;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool processing;

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
                  onPressed: processing ? null : onReject,
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
                  onPressed: processing ? null : onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccentOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: processing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('承認'),
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
    required this.amount,
    required this.type,
    this.subtitle,
    this.timestamp,
    this.counterpartyUid,
  });

  final String title;
  final num amount;
  final WalletActivityType type;
  final String? subtitle;
  final DateTime? timestamp;
  final String? counterpartyUid;
}

String _formatWalletTimestamp(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  if (target == today) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final yesterday = today.subtract(const Duration(days: 1));
  if (target == yesterday) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '昨日 $hour:$minute';
  }
  if (now.year == time.year) {
    return '${time.month}/${time.day}';
  }
  return '${time.year}/${time.month}/${time.day}';
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
    if (transactions.isEmpty) {
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
          const _WalletMessageCard(message: '最近の取引はありません。'),
        ],
      );
    }
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
                  subtitle: transactions[i].subtitle ??
                      _formatWalletTimestamp(transactions[i].timestamp),
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
    required this.subtitle,
    required this.showDivider,
  });

  final _WalletTransaction transaction;
  final String currencyCode;
  final String subtitle;
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
                      subtitle,
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
    this.enabled = true,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool loading;

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
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
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
    this.enabled = true,
    this.loading = false,
  });

  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x33DC2626)),
          ),
          child: Row(
            children: [
              Expanded(
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
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                  ),
                ),
            ],
          ),
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
    this.minting = false,
    this.burning = false,
  });

  final VoidCallback onMint;
  final VoidCallback onBurn;
  final bool minting;
  final bool burning;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: minting ? null : onMint,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kMainBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: minting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('発行 (Mint)'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: burning ? null : onBurn,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0x33DC2626)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: burning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                    ),
                  )
                : const Text('回収 (Burn)'),
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
    this.processing = false,
  });

  final bool dualApprovalEnabled;
  final ValueChanged<bool> onToggleDualApproval;
  final String mintRolesLabel;
  final String dailyLimit;
  final bool processing;

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
              processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
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
    required this.uid,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.locked = false,
  });

  final String uid;
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
    this.canModify = true,
    this.adding = false,
    this.updatingUid,
  });

  final List<_BankPermissionMember> members;
  final VoidCallback onAddMember;
  final ValueChanged<String> onRemoveMember;
  final bool canModify;
  final bool adding;
  final String? updatingUid;

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
                onPressed: canModify && !adding ? onAddMember : null,
                child: adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('メンバーを追加'),
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
                canModify: canModify,
                removing: updatingUid == member.uid,
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
    required this.canModify,
    required this.removing,
  });

  final _BankPermissionMember member;
  final ValueChanged<String> onRemove;
  final bool canModify;
  final bool removing;

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
          Builder(
            builder: (context) {
              final rawUrl = member.avatarUrl;
              final url = rawUrl?.trim();
              final fallback = Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kMainBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  member.name.characters.first,
                  style: const TextStyle(
                    color: _kMainBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
              if (!_MemberAvatar._isValidUrl(url)) {
                return fallback;
              }
              return SizedBox(
                width: 44,
                height: 44,
                child: ClipOval(
                  child: Image.network(
                    url!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
                ),
              );
            },
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
              onPressed:
                  canModify && !removing ? () => onRemove(member.uid) : null,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626)),
              child: removing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('解除'),
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

class _DashboardFab extends StatelessWidget {
  const _DashboardFab({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: _kMainBlue,
      elevation: 6,
      shadowColor: _kMainBlue.withOpacity(0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
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
      onTap: onDetail,
      onLongPress: onSelectToggle,
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
                          IconButton(
                            onPressed: onDetail,
                            icon: const Icon(Icons.more_horiz),
                            tooltip: '詳細を開く',
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
  if ((member.membership.status ?? '') == 'pending') {
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
  const _MemberAvatar({required this.member, this.size = 40});
  final _SelectableMember member;
  final double size;

  // Try to read typical avatar url property names from AppUser without compile-time dependency.
  static String? _tryGetAvatarUrl(AppUser? p) {
    if (p == null) return null;
    try {
      final dyn = p as dynamic;
      final candidate = (dyn.avatarUrl ??
          dyn.photoUrl ??
          dyn.photoURL ??
          dyn.imageUrl ??
          dyn.iconUrl);
      if (candidate is String) return candidate as String;
    } catch (_) {/* ignore */}
    return null;
  }

  static bool _isValidUrl(String? s) {
    if (s == null) return false;
    final t = s.trim();
    if (t.isEmpty) return false;
    final u = Uri.tryParse(t);
    return u != null && (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;
  }

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '??';
    final runes = t.runes.toList();
    if (runes.length == 1) return String.fromCharCode(runes.first);
    final first = String.fromCharCode(runes.first);
    final second = String.fromCharCode(runes[1]);
    return (first + second).toUpperCase(); // harmless for CJK, useful for Latin
  }

  @override
  Widget build(BuildContext context) {
    final url = _tryGetAvatarUrl(member.profile);

    final fallback = CircleAvatar(
      radius: size / 2,
      child: Text(
        _initials(member.displayName),
        style: TextStyle(fontSize: size / 2.8),
      ),
    );

    if (!_isValidUrl(url)) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(
        url!.trim(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Guard against HTML/404/CORS returning non-image bytes:
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _DevMenuSheet extends StatefulWidget {
  const _DevMenuSheet({
    required this.communityId,
    required this.currentUid,
    required this.onReopenRequested,
    required this.onSeedRequested,
    required this.onAddPendingRequested,
  });

  final String communityId;
  final String currentUid;
  final ValueChanged<String> onReopenRequested;
  final Future<void> Function() onSeedRequested;
  final Future<void> Function() onAddPendingRequested;

  @override
  State<_DevMenuSheet> createState() => _DevMenuSheetState();
}

class _DevMenuSheetState extends State<_DevMenuSheet> {
  late final TextEditingController _uidCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _noteCtrl;
  bool _minor = false;
  bool _bankManager = false;
  bool _joinCommunity = true;
  bool _creating = false;
  String? _selectedUid;

  @override
  void initState() {
    super.initState();
    _uidCtrl = TextEditingController();
    _labelCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    final String defaultUid = getDefaultDevUid();
    _selectedUid = defaultUid.isNotEmpty ? defaultUid : widget.currentUid;
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final padding = EdgeInsets.only(bottom: media.viewInsets.bottom);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16) + padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Devメニュー（Debug専用）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<DevUserState>(
              valueListenable: devUserStateListenable,
              builder: (context, state, _) {
                final entries = state.entries;
                _alignSelection(entries, state);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '擬似ログイン対象 UID',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...entries.map(_buildDevUserTile),
                    if (_selectedUid != null && _selectedUid!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '選択中: ${_selectedUid!}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              onPressed: (_selectedUid ?? '').isEmpty
                  ? null
                  : () {
                      final uid = _selectedUid!;
                      widget.onReopenRequested(uid);
                    },
              label: const Text('このUIDで開き直す'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Firestore ショートカット',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.playlist_add),
              onPressed: () {
                FocusScope.of(context).unfocus();
                widget.onSeedRequested();
              },
              label: const Text('Devシードを投入（コミュ・ユーザー・メンバー）'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.pending_actions),
              onPressed: () {
                FocusScope.of(context).unfocus();
                widget.onAddPendingRequested();
              },
              label: const Text('承認待ちを3件追加'),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              '新しい開発用ユーザーを作成',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _uidCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'UID（必須）',
                hintText: '例: dev_taro',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '表示名（任意）',
                hintText: 'Firestore displayName に反映',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'メモ（任意）',
                hintText: '一覧に表示するメモ',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _minor,
                    title: const Text('未成年'),
                    onChanged: (value) => setState(() => _minor = value ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _bankManager,
                    title: const Text('バンク権限'),
                    onChanged: (value) => setState(() => _bankManager = value ?? false),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _joinCommunity,
              title: Text('コミュニティ ${widget.communityId} に参加させる'),
              onChanged: (value) => setState(() => _joinCommunity = value ?? true),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              onPressed: _creating ? null : _handleCreate,
              label: Text(_creating ? '作成中...' : '開発ユーザーを作成'),
            ),
            const SizedBox(height: 16),
            const Text(
              '開発メモ:\n- 「このUIDで開き直す」で擬似ログインできます。\n'
              '- kDebugMode 限定のため本番ビルドには影響しません。\n'
              '- Firestore Emulator 利用時は CLI で事前に起動してください。',
              style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevUserTile(DevUserEntry entry) {
    final bool selected = _selectedUid == entry.uid;
    final bool removable = canRemoveDevUser(entry.uid);
    final List<String> tags = <String>[];
    if (entry.uid == widget.currentUid) {
      tags.add('この画面');
    }
    if ((entry.note ?? '').isNotEmpty) {
      tags.add(entry.note!.trim());
    }
    if (entry.minor == true) {
      tags.add('未成年');
    }
    if (entry.canManageBank == true) {
      tags.add('バンク権限');
    }
    final String subtitleText = tags.isEmpty
        ? entry.uid
        : '${entry.uid} · ${tags.join(' / ')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<String>(
        value: entry.uid,
        groupValue: _selectedUid,
        onChanged: (value) {
          if (value == null) return;
          _selectUid(value);
        },
      ),
      title: Text(entry.displayLabel),
      subtitle: Text(
        subtitleText,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: removable
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'リストから削除',
              onPressed: () => _removeUid(entry.uid),
            )
          : null,
      selected: selected,
      onTap: () => _selectUid(entry.uid),
    );
  }

  void _alignSelection(List<DevUserEntry> entries, DevUserState state) {
    if (entries.isEmpty) return;
    final String? preferred = state.activeUid ?? state.lastUsedUid ?? entries.first.uid;
    if (preferred == null) return;
    if (_selectedUid == preferred) return;
    if (!entries.any((entry) => entry.uid == preferred)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedUid = preferred);
    });
  }

  void _selectUid(String uid) {
    setActiveDevUid(uid);
    setState(() => _selectedUid = uid);
    _showSnack('擬似ログイン対象を $uid に設定しました');
  }

  void _removeUid(String uid) {
    removeDevUser(uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entries = devUserState.entries;
      final String? fallback = devUserState.activeUid ??
          devUserState.lastUsedUid ??
          (entries.isNotEmpty ? entries.first.uid : null);
      setState(() => _selectedUid = fallback);
    });
    _showSnack('$uid をリストから削除しました');
  }

  Future<void> _handleCreate() async {
    final String uid = _uidCtrl.text.trim();
    if (uid.isEmpty) {
      _showSnack('UIDを入力してください');
      return;
    }
    setState(() => _creating = true);
    FocusScope.of(context).unfocus();
    try {
      await createDevUser(
        uid: uid,
        label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        minor: _minor,
        canManageBank: _bankManager,
        communityId: widget.communityId,
        joinCommunity: _joinCommunity,
      );
      if (!mounted) return;
      setState(() {
        _selectedUid = uid;
        _uidCtrl.clear();
        _labelCtrl.clear();
        _noteCtrl.clear();
        _minor = false;
        _bankManager = false;
        _joinCommunity = true;
      });
      _showSnack('開発ユーザー $uid を作成しました');
    } catch (error) {
      if (!mounted) return;
      _showSnack('ユーザー作成に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
