import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/chat_service.dart';
import 'central_bank_screen.dart';
import 'community_activity_screen.dart';
import 'community_chat_screen.dart';
import 'community_links_screen.dart';
import 'community_loan_screen.dart';
import 'community_member_select_screen.dart';
import 'member_chat_screen.dart';
import 'transactions/transaction_flow_screen.dart';

DateTime? _homeReadTimestamp(dynamic value) {
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

int _homeCompareJoinedDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _homeReadTimestamp(a['joinedAt']);
  final bDate = _homeReadTimestamp(b['joinedAt']);
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

class CommunityHomeScreen extends StatefulWidget {
  const CommunityHomeScreen({
    super.key,
    required this.communityId,
    required this.user,
    required this.initialCommunity,
    required this.initialMembership,
  });

  final String communityId;
  final User user;
  final Map<String, dynamic>? initialCommunity;
  final Map<String, dynamic>? initialMembership;

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    required User user,
    Map<String, dynamic>? communityPreview,
    Map<String, dynamic>? membershipData,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityHomeScreen(
          communityId: communityId,
          user: user,
          initialCommunity: communityPreview,
          initialMembership: membershipData,
        ),
      ),
    );
  }

  @override
  State<CommunityHomeScreen> createState() => _CommunityHomeScreenState();
}

class _CommunityHomeScreenState extends State<CommunityHomeScreen> {
  bool _showBalance = true;
  late Future<List<_QuickShortcutMember>> _shortcutMembersFuture;
  _QuickShortcutMember? _selectedShortcutMember;

  @override
  void initState() {
    super.initState();
    _shortcutMembersFuture = _loadShortcutMembers();
  }

  @override
  void didUpdateWidget(covariant CommunityHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.communityId != widget.communityId) {
      _shortcutMembersFuture = _loadShortcutMembers();
      _selectedShortcutMember = null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _communityStream =>
      FirebaseFirestore.instance.doc('communities/${widget.communityId}').snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _membershipStream =>
      FirebaseFirestore.instance
          .doc('memberships/${widget.communityId}_${widget.user.uid}')
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pendingRequestsStream =>
      FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.communityId)
          .collection('items')
          .where('toUid', isEqualTo: widget.user.uid)
          .where('status', whereIn: ['pending', 'processing'])
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _membersStream =>
      FirebaseFirestore.instance
          .collection('memberships')
          .where('cid', isEqualTo: widget.communityId)
          .limit(6)
          .snapshots();

  Future<List<_QuickShortcutMember>> _loadShortcutMembers() async {
    final membershipSnap = await FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: widget.communityId)
        .get();

    final futures = membershipSnap.docs.map((doc) async {
      final data = doc.data();
      final uid = data['uid'] as String?;
      if (uid == null || uid.isEmpty || uid == widget.user.uid) {
        return null;
      }
      final role = (data['role'] as String?) ?? 'member';
      final userSnap =
          await FirebaseFirestore.instance.doc('users/$uid').get();
      final userData = userSnap.data();
      final rawName = (userData?['displayName'] as String?)?.trim();
      final displayName =
          (rawName != null && rawName.isNotEmpty) ? rawName : uid;
      final photoUrl = (userData?['photoUrl'] as String?)?.trim();
      return _QuickShortcutMember(
        uid: uid,
        displayName: displayName,
        photoUrl: (photoUrl != null && photoUrl.isNotEmpty)
            ? photoUrl
            : null,
        role: role,
      );
    });

    final members = <_QuickShortcutMember>[];
    for (final future in futures) {
      final member = await future;
      if (member != null) {
        members.add(member);
      }
    }
    members.sort((a, b) => a.displayName.compareTo(b.displayName));
    return members;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _communityStream,
      builder: (context, communitySnap) {
        final communityData = communitySnap.data?.data() ?? widget.initialCommunity ?? {};
        final communityCurrency = CommunityCurrency.fromMap(
          (communityData['currency'] as Map<String, dynamic>?) ?? const {},
        );
        final communityName = (communityData['name'] as String?) ?? widget.communityId;
        final communitySymbol = (communityData['symbol'] as String?) ?? communityCurrency.code;
        final inviteCode = (communityData['inviteCode'] as String?) ?? '';

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _membershipStream,
          builder: (context, membershipSnap) {
            final membershipData =
                membershipSnap.data?.data() ?? widget.initialMembership ?? <String, dynamic>{};
            final balance = (membershipData['balance'] as num?) ?? 0;
            final role = (membershipData['role'] as String?) ?? 'member';

            return Scaffold(
              backgroundColor: const Color(0xFFF6F3EE),
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: Text(communityName,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                actions: [
                  IconButton(
                    tooltip: '中央銀行',
                    icon: const Icon(Icons.account_balance, color: Colors.black87),
                    onPressed: () => _openCentralBank(context, communityName),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HomeHeader(
                      userName: FirebaseAuth.instance.currentUser?.displayName ?? widget.user.displayName ?? 'メンバー',
                      role: role,
                      communitySymbol: communitySymbol,
                      inviteCode: inviteCode,
                    ),
                    const SizedBox(height: 12),
                    _BalanceCard(
                      balance: balance,
                      symbol: communitySymbol,
                      showBalance: _showBalance,
                      onToggle: () => setState(() => _showBalance = !_showBalance),
                    ),
                    const SizedBox(height: 20),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _pendingRequestsStream,
                      builder: (context, snapshot) {
                        final requests = snapshot.data?.docs ?? [];
                        if (requests.isEmpty) return const SizedBox.shrink();
                        final now = DateTime.now();
                        int overdue = 0;
                        for (final doc in requests) {
                          final data = doc.data();
                          final createdAt = data['createdAt'];
                          DateTime? created;
                          if (createdAt is Timestamp) {
                            created = createdAt.toDate();
                          } else if (createdAt is DateTime) {
                            created = createdAt;
                          }
                          if (created != null && now.difference(created) >= const Duration(seconds: 30)) {
                            overdue++;
                          }
                        }
                        return _PendingBanner(
                          total: requests.length,
                          overdue: overdue,
                          onTap: () => _openCentralBank(context, communityName),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _ShortcutSection(
                      membersFuture: _shortcutMembersFuture,
                      selectedMember: _selectedShortcutMember,
                      onMemberSelected: (member) =>
                          setState(() => _selectedShortcutMember = member),
                      onReloadMembers: () => setState(
                          () => _shortcutMembersFuture = _loadShortcutMembers()),
                      onSend: () => _openSend(
                        context,
                        targetUid: _selectedShortcutMember?.uid,
                      ),
                      onRequest: () => _openRequest(
                        context,
                        targetUid: _selectedShortcutMember?.uid,
                      ),
                      onHistory: () => _openHistory(context, communitySymbol),
                      onMessages: () => _openMessages(
                        context,
                        communityName,
                        target: _selectedShortcutMember,
                      ),
                      onLinks: () => _openLinks(context),
                      onBorrow: () => _openBorrow(context, communityName),
                    ),
                    const SizedBox(height: 28),
                    Text('最近のアクティビティ',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    CommunityActivityPreview(communityId: widget.communityId),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('メンバー',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .copyWith(fontWeight: FontWeight.w700)),
                        TextButton.icon(
                          onPressed: () => CommunityMemberSelectScreen.open(
                            context,
                            communityId: widget.communityId,
                            communityName: communityName,
                            currentUserUid: widget.user.uid,
                            currentUserRole: role,
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('メンバーを選択'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _membersStream,
                      builder: (context, snapshot) {
                        final members = snapshot.data?.docs ?? [];
                        final sortedMembers = members.toList()
                          ..sort((a, b) =>
                              _homeCompareJoinedDesc(a.data(), b.data()));
                        if (sortedMembers.isEmpty) {
                          return const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('メンバーがまだいません'),
                            ),
                          );
                        }
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: sortedMembers.map((doc) {
                            final data = doc.data();
                            final uid = (data['uid'] as String?) ?? 'unknown';
                            final roleLabel = data['role'] as String? ?? 'member';
                            return _AsyncMemberChip(
                              communityId: widget.communityId,
                              uid: uid,
                              isCurrentUser: uid == widget.user.uid,
                              role: roleLabel,
                              onTap: () => CommunityChatScreen.open(
                                context,
                                communityId: widget.communityId,
                                communityName: communityName,
                                user: widget.user,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                    Text('中央銀行',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _CentralBankSummaryCard(
                      currency: communityCurrency,
                      requiresApproval: CommunityPolicy.fromMap(
                              (communityData['policy'] as Map<String, dynamic>?) ??
                                  const {})
                          .requiresApproval,
                      onOpen: () => _openCentralBank(context, communityName),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSend(BuildContext context, {String? targetUid}) async {
    await TransactionFlowScreen.open(
      context,
      user: widget.user,
      communityId: widget.communityId,
      initialKind: TransactionKind.transfer,
      initialMemberUid: targetUid,
    );
  }

  Future<void> _openRequest(BuildContext context, {String? targetUid}) async {
    await TransactionFlowScreen.open(
      context,
      user: widget.user,
      communityId: widget.communityId,
      initialKind: TransactionKind.request,
      initialMemberUid: targetUid,
    );
  }

  Future<void> _openHistory(BuildContext context, String symbol) async {
    await CommunityActivityScreen.open(
      context,
      communityId: widget.communityId,
      symbol: symbol,
      user: widget.user,
    );
  }

  Future<void> _openMessages(
    BuildContext context,
    String communityName, {
    _QuickShortcutMember? target,
  }) async {
    if (target != null) {
      final threadId =
          ChatService.buildThreadId(widget.user.uid, target.uid);
      await MemberChatScreen.open(
        context,
        communityId: widget.communityId,
        communityName: communityName,
        currentUser: widget.user,
        partnerUid: target.uid,
        partnerDisplayName: target.displayName,
        partnerPhotoUrl: target.photoUrl,
        threadId: threadId,
        memberRole: target.role,
      );
      return;
    }
    await CommunityChatScreen.open(
      context,
      communityId: widget.communityId,
      communityName: communityName,
      user: widget.user,
    );
  }

  Future<void> _openLinks(BuildContext context) async {
    await CommunityLinksScreen.open(
      context,
      communityId: widget.communityId,
      user: widget.user,
    );
  }

  Future<void> _openBorrow(BuildContext context, String communityName) async {
    await CommunityLoanScreen.open(
      context,
      communityId: widget.communityId,
      communityName: communityName,
      user: widget.user,
    );
  }

  Future<void> _openCentralBank(BuildContext context, String communityName) async {
    await CentralBankScreen.open(
      context,
      communityId: widget.communityId,
      user: widget.user,
      communityName: communityName,
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.userName,
    required this.role,
    required this.communitySymbol,
    required this.inviteCode,
  });

  final String userName;
  final String role;
  final String communitySymbol;
  final String inviteCode;

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(role);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Colors.blueGrey.shade100,
          child: const Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(userName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('役割: $roleLabel', style: Theme.of(context).textTheme.bodySmall),
              if (inviteCode.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('招待コード: $inviteCode',
                    style:
                        Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.grey)),
              ],
            ],
          ),
        ),
        Chip(
          label: Text(communitySymbol),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ],
    );
  }

  String _roleLabel(String value) {
    return switch (value) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.symbol,
    required this.showBalance,
    required this.onToggle,
  });

  final num balance;
  final String symbol;
  final bool showBalance;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('預金残高', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 6),
                Text(
                  showBalance
                      ? balance.toStringAsFixed(2)
                      : '******',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                Text(symbol,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: Colors.grey.shade600)),
              ],
            ),
            IconButton(
              onPressed: onToggle,
              icon: Icon(showBalance ? Icons.visibility_off : Icons.visibility),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({
    required this.total,
    required this.overdue,
    required this.onTap,
  });

  final int total;
  final int overdue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: overdue > 0 ? const Color(0xFFFFE5E5) : const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(overdue > 0 ? Icons.warning_amber : Icons.notifications,
                color: overdue > 0 ? Colors.redAccent : Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                overdue > 0
                    ? '$overdue 件の請求が期限を超えています'
                    : '$total 件の未処理の請求があります',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: onTap,
              child: const Text('詳細'),
            )
          ],
        ),
      ),
    );
  }
}

class _QuickShortcutMember {
  const _QuickShortcutMember({
    required this.uid,
    required this.displayName,
    required this.role,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String role;
  final String? photoUrl;

  String get roleLabel {
    return switch (role) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
  }
}

class _ShortcutSection extends StatelessWidget {
  const _ShortcutSection({
    required this.membersFuture,
    required this.selectedMember,
    required this.onMemberSelected,
    required this.onReloadMembers,
    required this.onSend,
    required this.onRequest,
    required this.onHistory,
    required this.onMessages,
    required this.onLinks,
    required this.onBorrow,
  });

  final Future<List<_QuickShortcutMember>> membersFuture;
  final _QuickShortcutMember? selectedMember;
  final ValueChanged<_QuickShortcutMember?> onMemberSelected;
  final VoidCallback onReloadMembers;
  final VoidCallback onSend;
  final VoidCallback onRequest;
  final VoidCallback onHistory;
  final VoidCallback onMessages;
  final VoidCallback onLinks;
  final VoidCallback onBorrow;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700) ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ショートカット', style: titleStyle),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      _ShortcutActionButton(
                        icon: Icons.send,
                        label: '送金',
                        color: Colors.blue,
                        onTap: onSend,
                      ),
                      _ShortcutActionButton(
                        icon: Icons.request_page,
                        label: '請求',
                        color: Colors.pink,
                        onTap: onRequest,
                      ),
                      _ShortcutActionButton(
                        icon: Icons.receipt_long,
                        label: '履歴',
                        color: Colors.orange,
                        onTap: onHistory,
                      ),
                      _ShortcutActionButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'メッセ',
                        color: Colors.green,
                        onTap: onMessages,
                      ),
                      _ShortcutActionButton(
                        icon: Icons.link,
                        label: 'リンク',
                        color: Colors.indigo,
                        onTap: onLinks,
                      ),
                      _ShortcutActionButton(
                        icon: Icons.account_balance_wallet_outlined,
                        label: '借入',
                        color: Colors.teal,
                        onTap: onBorrow,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (selectedMember != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InputChip(
                  avatar: _ShortcutMemberAvatar(
                    name: selectedMember!.displayName,
                    photoUrl: selectedMember!.photoUrl,
                    radius: 14,
                  ),
                  label: Text(selectedMember!.displayName),
                  onDeleted: () => onMemberSelected(null),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FutureBuilder<List<_QuickShortcutMember>>(
            future: membersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'メンバーを読み込めませんでした: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onReloadMembers,
                        icon: const Icon(Icons.refresh),
                        label: const Text('再試行'),
                      ),
                    ),
                  ],
                );
              }
              final members = snapshot.data ?? const [];
              if (members.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'メンバーがまだいません',
                    style: TextStyle(color: Colors.black54),
                  ),
                );
              }
              return _ShortcutMemberSelector(
                members: members,
                selectedMember: selectedMember,
                onSelected: onMemberSelected,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutActionButton extends StatelessWidget {
  const _ShortcutActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Material(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutMemberSelector extends StatefulWidget {
  const _ShortcutMemberSelector({
    required this.members,
    required this.selectedMember,
    required this.onSelected,
  });

  final List<_QuickShortcutMember> members;
  final _QuickShortcutMember? selectedMember;
  final ValueChanged<_QuickShortcutMember?> onSelected;

  @override
  State<_ShortcutMemberSelector> createState() =>
      _ShortcutMemberSelectorState();
}

class _ShortcutMemberSelectorState extends State<_ShortcutMemberSelector> {
  late List<_QuickShortcutMember> _filteredMembers;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredMembers = List<_QuickShortcutMember>.from(widget.members);
    _searchCtrl.addListener(_handleSearchChanged);
  }

  @override
  void didUpdateWidget(covariant _ShortcutMemberSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.members, widget.members)) {
      setState(() {
        _filteredMembers = _applyFilter(widget.members, _searchCtrl.text);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {
      _filteredMembers = _applyFilter(widget.members, _searchCtrl.text);
    });
  }

  List<_QuickShortcutMember> _applyFilter(
    List<_QuickShortcutMember> base,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return List<_QuickShortcutMember>.from(base);
    }
    return base
        .where((member) =>
            member.displayName.toLowerCase().contains(normalized) ||
            member.uid.toLowerCase().contains(normalized))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = Colors.black.withOpacity(0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'メンバーを検索',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: const Color(0xFFF0F2F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              if (widget.selectedMember != null) ...[
                ListTile(
                  onTap: () => widget.onSelected(null),
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade200,
                    child: const Icon(Icons.close, color: Colors.black87),
                  ),
                  title: const Text('選択を解除'),
                ),
                const Divider(height: 1),
              ],
              if (_filteredMembers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '該当するメンバーがいません',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredMembers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = _filteredMembers[index];
                    final isSelected =
                        widget.selectedMember?.uid == member.uid;
                    return ListTile(
                      onTap: () => widget.onSelected(
                        isSelected ? null : member,
                      ),
                      leading: _ShortcutMemberAvatar(
                        name: member.displayName,
                        photoUrl: member.photoUrl,
                      ),
                      title: Text(
                        member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        member.roleLabel,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary)
                          : null,
                      selected: isSelected,
                      selectedTileColor:
                          theme.colorScheme.primary.withOpacity(0.08),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortcutMemberAvatar extends StatelessWidget {
  const _ShortcutMemberAvatar({
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final background = primary.withOpacity(0.15);
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
      child: photoUrl == null
          ? Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primary,
                fontSize: radius,
              ),
            )
          : null,
    );
  }
}

class _AsyncMemberChip extends StatelessWidget {
  const _AsyncMemberChip({
    required this.communityId,
    required this.uid,
    required this.isCurrentUser,
    required this.role,
    required this.onTap,
  });

  final String communityId;
  final String uid;
  final bool isCurrentUser;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isCurrentUser) {
      return _MemberChip(name: 'あなた', role: role, onTap: onTap);
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.doc('users/$uid').get(),
      builder: (context, snapshot) {
        final name = snapshot.data?.data()?['displayName'] as String? ?? uid;
        return _MemberChip(name: name, role: role, onTap: onTap);
      },
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.name,
    required this.role,
    required this.onTap,
  });

  final String name;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const CircleAvatar(child: Icon(Icons.person, size: 16)),
      label: Text('$name • ${_roleLabel(role)}'),
      onPressed: onTap,
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'owner' => 'オーナー',
      'admin' => '管理者',
      'mediator' => '仲介',
      'pending' => '承認待ち',
      _ => 'メンバー',
    };
  }
}

class _CentralBankSummaryCard extends StatelessWidget {
  const _CentralBankSummaryCard({
    required this.currency,
    required this.requiresApproval,
    required this.onOpen,
  });

  final CommunityCurrency currency;
  final bool requiresApproval;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${currency.name} (${currency.code})',
                style:
                    Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('小数点以下 ${currency.precision} 桁 / メンバー発行: '
                '${currency.allowMinting ? '許可' : '制限'}'),
            Text('参加承認: ${requiresApproval ? '必要' : '不要'}'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onOpen,
                child: const Text('中央銀行を開く'),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class CommunityActivityPreview extends StatelessWidget {
  const CommunityActivityPreview({super.key, required this.communityId});

  final String communityId;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('ledger')
        .doc(communityId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('まだアクティビティがありません'),
            ),
          );
        }
        return Column(
          children: [
            for (final doc in docs) _ActivityTile(data: doc.data()),
          ],
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final amount = (data['amount'] as num?) ?? 0;
    final memo = (data['memo'] as String?) ?? '';
    final createdAtRaw = data['createdAt'];
    DateTime? createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    }
    final createdLabel = createdAt == null
        ? ''
        : '${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
        title: Text('${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(memo.isEmpty ? 'メモなし' : memo),
        trailing: Text(createdLabel,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.grey)),
      ),
    );
  }
}
