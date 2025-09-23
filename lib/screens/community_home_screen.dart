import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/community.dart';
import 'central_bank_screen.dart';
import 'community_activity_screen.dart';
import 'community_chat_screen.dart';
import 'community_links_screen.dart';
import 'community_loan_screen.dart';
import 'transactions/transaction_flow_screen.dart';

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
          .orderBy('joinedAt', descending: true)
          .limit(6)
          .snapshots();

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
                      userName: widget.user.displayName ?? 'メンバー',
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
                    Text('ショートカット',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _ActionGrid(
                      onSend: () => _openSend(context),
                      onRequest: () => _openRequest(context),
                      onHistory: () => _openHistory(context, communitySymbol),
                      onMessages: () => _openMessages(context, communityName),
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
                    Text('メンバー',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _membersStream,
                      builder: (context, snapshot) {
                        final members = snapshot.data?.docs ?? [];
                        if (members.isEmpty) {
                          return const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('メンバー情報を取得できませんでした'),
                            ),
                          );
                        }
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: members.map((doc) {
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

  Future<void> _openSend(BuildContext context) async {
    await TransactionFlowScreen.open(
      context,
      user: widget.user,
      communityId: widget.communityId,
      initialKind: TransactionKind.transfer,
    );
  }

  Future<void> _openRequest(BuildContext context) async {
    await TransactionFlowScreen.open(
      context,
      user: widget.user,
      communityId: widget.communityId,
      initialKind: TransactionKind.request,
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

  Future<void> _openMessages(BuildContext context, String communityName) async {
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

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onSend,
    required this.onRequest,
    required this.onHistory,
    required this.onMessages,
    required this.onLinks,
    required this.onBorrow,
  });

  final VoidCallback onSend;
  final VoidCallback onRequest;
  final VoidCallback onHistory;
  final VoidCallback onMessages;
  final VoidCallback onLinks;
  final VoidCallback onBorrow;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionCard(
          title: '送金する',
          icon: Icons.send,
          color: Colors.blue,
          onTap: onSend,
        ),
        _ActionCard(
          title: '請求する',
          icon: Icons.request_page,
          color: Colors.pink,
          onTap: onRequest,
        ),
        _ActionCard(
          title: '履歴',
          icon: Icons.receipt_long,
          color: Colors.orange,
          onTap: onHistory,
        ),
        _ActionCard(
          title: 'メッセージ',
          icon: Icons.chat_bubble_outline,
          color: Colors.green,
          onTap: onMessages,
        ),
        _ActionCard(
          title: 'リンク送金',
          icon: Icons.link,
          color: Colors.indigo,
          onTap: onLinks,
        ),
        _ActionCard(
          title: '借入する',
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.teal,
          onTap: onBorrow,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
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
