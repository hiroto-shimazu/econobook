import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/community_service.dart';
import '../services/transaction_event_bus.dart';
import 'central_bank_screen.dart';
import 'community_create_screen.dart';
import 'news_screen.dart';
import 'transactions/monthly_summary_sheet.dart';
import 'transactions/transaction_flow_screen.dart';

// ---- Brand tokens（他画面と統一）----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

DateTime? _walletReadTimestamp(dynamic value) {
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

int _walletCompareJoinedDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _walletReadTimestamp(a['joinedAt']);
  final bDate = _walletReadTimestamp(b['joinedAt']);
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.user});
  final User user;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final TextEditingController _search = TextEditingController();
  int _tabIndex = 0; // 0: 入金, 1: 出金
  int _refreshTick = 0;
  late final VoidCallback _busListener;
  final CommunityService _communityService = CommunityService();

  @override
  void initState() {
    super.initState();
    _busListener = () {
      if (!mounted) return;
      setState(() {
        _refreshTick++;
      });
    };
    TransactionEventBus.instance.counter.addListener(_busListener);
  }

  @override
  void dispose() {
    TransactionEventBus.instance.counter.removeListener(_busListener);
    _search.dispose();
    super.dispose();
  }

  String _formatAmount(num n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _buildEmptyCommunitiesCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: kBrandGrad,
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'コミュニティを作成・参加してポイントのやり取りを始めましょう',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Talkタブからでも後で操作できますが、ここからすぐにセットアップすることもできます。',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _promptJoinCommunity(context),
                  child: const Text('招待コードで参加'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kBrandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const CommunityCreateScreen(),
                      ),
                    );
                    if (created == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('コミュニティを作成しました')),
                      );
                    }
                  },
                  child: const Text('コミュニティを作る'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptJoinCommunity(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('招待コードで参加'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '招待コードまたはコミュニティID',
              hintText: 'L7Q9X0 や family 等',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim().toUpperCase()),
              child: const Text('参加'),
            ),
          ],
        );
      },
    );
    if (code == null || code.trim().isEmpty) return;

    final trimmed = code.trim().toUpperCase();
    try {
      final joined = await _communityService.joinCommunity(
        userId: widget.user.uid,
        inviteCode: trimmed,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(joined
              ? '招待コード「$trimmed」で参加しました'
              : '招待コード「$trimmed」で参加申請を送信しました'),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加に失敗しました: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final membershipsQuery = FirebaseFirestore.instance
        .collection('memberships')
        .where('uid', isEqualTo: widget.user.uid);

    return DefaultTabController(
      length: 2,
      initialIndex: _tabIndex,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('ウォレット',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file, color: Colors.black87),
              tooltip: 'エクスポート',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('エクスポート（準備中）')),
              ),
            ),
          ],
        ),
        floatingActionButton: _FabGradient(
          icon: Icons.add,
          onPressed: () async {
            final result =
                await TransactionFlowScreen.open(context, user: widget.user);
            if (result == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('取引を作成しました')),
              );
            }
          },
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          key: ValueKey(_refreshTick),
          stream: membershipsQuery.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('読み込みエラー: ${snap.error}'));
            }
            final docs = snap.data?.docs ?? [];
            final sortedDocs = docs.toList()
              ..sort((a, b) => _walletCompareJoinedDesc(a.data(), b.data()));
            num total = 0;
            for (final d in sortedDocs) {
              total += (d.data()['balance'] as num?) ?? 0;
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // ===== サマリー（総残高 / ポイント）=====
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: '総残高',
                          value: _formatAmount(total),
                          highlight: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'ポイント',
                          value: _formatAmount(total), // 将来は別指標に差し替え可
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                _PendingRequestsCard(userId: widget.user.uid),

                // ===== コミュニティ残高 =====
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('コミュニティ残高',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
                ),
                if (sortedDocs.isEmpty)
                  _buildEmptyCommunitiesCard(context)
                else ...[
                  for (final m in sortedDocs) _communityBalanceTile(m),
                  const SizedBox(height: 8),
                ],

                const Divider(height: 24),

                // ===== 検索 + 入金/出金タブ =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: '取引を検索',
                      filled: true,
                      fillColor: kLightGray,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: ShaderMask(
                        shaderCallback: (Rect b) => kBrandGrad.createShader(b),
                        blendMode: BlendMode.srcIn,
                        child: const Icon(Icons.search, color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: kBrandBlue, width: 2),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TabBar(
                    onTap: (i) => setState(() => _tabIndex = i),
                    labelColor: kBrandBlue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: kBrandBlue,
                    tabs: const [
                      Tab(text: '入金'),
                      Tab(text: '出金'),
                    ],
                  ),
                ),

                // ===== 取引（ダミー：将来 Firestore に接続）=====
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      if (_tabIndex == 0) ...[
                        _TxItemRow(
                          positive: true,
                          title: 'Community A から受取',
                          memo: 'メモ: 週末のご飯',
                          amount: '+5,000',
                          time: '9/10',
                        ),
                        _TxItemRow(
                          positive: true,
                          title: 'Community B から受取',
                          memo: 'メモ: 交通費',
                          amount: '+800',
                          time: '9/08',
                        ),
                      ] else ...[
                        _TxItemRow(
                          positive: false,
                          title: 'Community B へ支払',
                          memo: 'メモ: 家賃立替',
                          amount: '-12,000',
                          time: '9/05',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // コミュニティ単位の残高行（名前やカバーを補完）
  Widget _communityBalanceTile(QueryDocumentSnapshot<Map<String, dynamic>> m) {
    final data = m.data();
    final cid = data['cid'] as String? ?? 'unknown';
    final balance = (data['balance'] as num?) ?? 0;
    final role = (data['role'] as String?) ?? 'member';
    final membershipHasPermission =
        role == 'owner' || data['canManageBank'] == true;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.doc('communities/$cid').get(),
      builder: (context, snap) {
        final c = snap.data?.data() ?? <String, dynamic>{};
        final name = (c['name'] as String?) ?? cid;
        final cover = (c['coverUrl'] as String?);
        final isOwner = (c['ownerUid'] as String?) == widget.user.uid;
        final canManageBank = membershipHasPermission || isOwner;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0x22000000)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: _coverOrEmoji(name, cover),
            title:
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('残高: ${_formatAmount(balance)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '中央銀行ページ',
                  icon: const Icon(Icons.account_balance),
                  color: canManageBank ? kBrandBlue : Colors.black45,
                  onPressed: () => CentralBankScreen.open(
                    context,
                    communityId: cid,
                    communityName: name,
                    user: widget.user,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => MonthlySummarySheet.show(
              context,
              communityId: cid,
              communityName: name,
            ),
          ),
        );
      },
    );
  }

  Widget _coverOrEmoji(String name, String? coverUrl) {
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Image.network(
          coverUrl,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverFallback(name),
        ),
      );
    }
    return _coverFallback(name);
  }

  Widget _coverFallback(String title) {
    return Container(
      width: 44,
      height: 44,
      decoration:
          const BoxDecoration(color: kLightGray, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ===== UI Parts =====
class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.title, required this.value, this.highlight = false});
  final String title;
  final String value;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final numberStyle = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: highlight ? kBrandBlue : Colors.black,
    );
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
          Text(value, style: numberStyle),
          const SizedBox(height: 4),
          const Text('',
              style: TextStyle(fontSize: 0)), // レイアウト安定用の小ワークアラウンド（行高さブレ防止）
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TxItemRow extends StatelessWidget {
  const _TxItemRow({
    required this.positive,
    required this.title,
    required this.memo,
    required this.amount,
    required this.time,
  });
  final bool positive;
  final String title;
  final String memo;
  final String amount;
  final String time;

  @override
  Widget build(BuildContext context) {
    final color = positive ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration:
                const BoxDecoration(color: kLightGray, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(positive ? Icons.arrow_downward : Icons.arrow_upward,
                color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(memo,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (positive ? '+' : '-') +
                    amount.replaceAll(RegExp(r'^[+-]'), ''),
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              Text(time,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FabGradient extends StatelessWidget {
  const _FabGradient({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: 56,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: kBrandGrad,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: ClipOval(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: Center(child: Icon(icon, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingRequestsCard extends StatelessWidget {
  const _PendingRequestsCard({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collectionGroup('items')
        .where('toUid', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(20)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('リクエストを取得できませんでした: ${snapshot.error}'),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final count = docs.length;
        final latest = docs.first.data();
        final amount = (latest['amount'] as num?) ?? 0;
        final currency = latest['symbol'] as String? ?? 'PTS';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0x22000000)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: kLightGray,
                child: const Icon(Icons.receipt_long, color: kBrandBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('承認待ちのリクエストが$count件あります',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.black)),
                    const SizedBox(height: 4),
                    Text('最新: ${amount.toStringAsFixed(2)} $currency',
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NewsScreen()),
                  );
                },
                child: const Text('Newsを開く'),
              ),
            ],
          ),
        );
      },
    );
  }
}
