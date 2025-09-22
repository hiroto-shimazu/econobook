import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)],
);

class MonthlySummarySheet extends StatefulWidget {
  const MonthlySummarySheet(
      {super.key, required this.communityId, required this.communityName});

  final String communityId;
  final String communityName;

  static Future<void> show(BuildContext context,
      {required String communityId, required String communityName}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => MonthlySummarySheet(
          communityId: communityId,
          communityName: communityName,
        ),
      ),
    );
  }

  @override
  State<MonthlySummarySheet> createState() => _MonthlySummarySheetState();
}

class _MonthlySummarySheetState extends State<MonthlySummarySheet> {
  late Future<_MonthlySummaryData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadSummary();
  }

  Future<_MonthlySummaryData> _loadSummary() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    final communitySnap = await FirebaseFirestore.instance
        .doc('communities/${widget.communityId}')
        .get();
    final communityData = communitySnap.data();
    final symbol = (communityData?['symbol'] as String?) ?? 'PTS';

    final membershipSnap = await FirebaseFirestore.instance
        .collection('memberships')
        .where('cid', isEqualTo: widget.communityId)
        .get();

    final memberIds = <String>[];
    for (final doc in membershipSnap.docs) {
      final data = doc.data();
      final uid = data['uid'] as String?;
      if (uid == null) continue;
      memberIds.add(uid);
    }

    final names = <String, String>{};
    final userSnaps = await Future.wait(
      memberIds
          .map((uid) => FirebaseFirestore.instance.doc('users/$uid').get()),
    );
    for (final snap in userSnaps) {
      final data = snap.data();
      final uid = snap.id;
      names[uid] = (data?['displayName'] as String?) ?? uid;
    }

    final entriesSnap = await FirebaseFirestore.instance
        .collection('ledger')
        .doc(widget.communityId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();

    final netByUser = <String, double>{};
    for (final doc in entriesSnap.docs) {
      final data = doc.data();
      final createdAtTs = data['createdAt'];
      DateTime? createdAt;
      if (createdAtTs is Timestamp) createdAt = createdAtTs.toDate();
      if (createdAtTs is DateTime) createdAt = createdAtTs;
      if (createdAt == null || createdAt.isBefore(monthStart)) continue;
      final status = data['status'] as String?;
      if (status != 'posted') continue;
      final lines = data['lines'];
      if (lines is! List) continue;
      for (final line in lines) {
        if (line is! Map) continue;
        final uid = line['uid'] as String?;
        final delta = (line['delta'] as num?)?.toDouble() ?? 0;
        if (uid == null) continue;
        netByUser.update(uid, (value) => value + delta, ifAbsent: () => delta);
      }
    }

    final balances = <_UserBalance>[];
    for (final uid in memberIds) {
      final balance = netByUser[uid] ?? 0;
      balances.add(_UserBalance(
        uid: uid,
        displayName: names[uid] ?? uid,
        balance: balance,
      ));
    }

    balances.sort((a, b) => b.balance.compareTo(a.balance));

    final totalPositive = balances
        .where((b) => b.balance > 0)
        .fold<double>(0, (sum, b) => sum + b.balance);
    final totalNegative = balances
        .where((b) => b.balance < 0)
        .fold<double>(0, (sum, b) => sum + b.balance.abs());

    return _MonthlySummaryData(
      monthStart: monthStart,
      symbol: symbol,
      balances: balances,
      totalReceivable: totalPositive,
      totalPayable: totalNegative,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MonthlySummaryData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('月次まとめの取得に失敗しました: ${snapshot.error}'),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: Text('データがまだありません'));
        }
        return _SummaryContent(data: data, communityName: widget.communityName);
      },
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.data, required this.communityName});

  final _MonthlySummaryData data;
  final String communityName;

  @override
  Widget build(BuildContext context) {
    final monthLabel = '${data.monthStart.year}年${data.monthStart.month}月';
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(communityName,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('$monthLabel のまとめ',
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ),
                DecoratedBox(
                  decoration: const BoxDecoration(
                      gradient: kBrandGrad,
                      borderRadius: BorderRadius.all(Radius.circular(999))),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(data.symbol,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SummaryCard(
                    label: '受取見込み',
                    value: data.totalReceivable,
                    symbol: data.symbol,
                    positive: true,
                  ),
                  _SummaryCard(
                    label: '支払見込み',
                    value: data.totalPayable,
                    symbol: data.symbol,
                    positive: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: data.balances.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = data.balances[index];
                  return ListTile(
                    title: Text(item.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(item.balance >= 0 ? '受け取り' : '支払い'),
                    trailing: Text(
                      _formatAmount(item.balance, data.symbol),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: item.balance >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('※ 当月の投稿済み取引（posted）のみ集計しています。'),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double value, String symbol) {
    final amount = value.abs().toStringAsFixed(2);
    return value >= 0 ? '+$amount $symbol' : '-$amount $symbol';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.symbol,
      required this.positive});

  final String label;
  final double value;
  final String symbol;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final display = value.toStringAsFixed(2);
    final color = positive ? Colors.green : Colors.red;
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.black54, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          (positive ? '+' : '-') + display,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        Text(symbol, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}

class _MonthlySummaryData {
  _MonthlySummaryData({
    required this.monthStart,
    required this.symbol,
    required this.balances,
    required this.totalReceivable,
    required this.totalPayable,
  });

  final DateTime monthStart;
  final String symbol;
  final List<_UserBalance> balances;
  final double totalReceivable;
  final double totalPayable;
}

class _UserBalance {
  const _UserBalance(
      {required this.uid, required this.displayName, required this.balance});

  final String uid;
  final String displayName;
  final double balance;
}
