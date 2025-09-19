// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'account_screen.dart';
import 'community_screen.dart';
import 'wallet_screen.dart';
import 'news_screen.dart';

// ---- Brand tokens (SignIn と統一) ----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});
  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0; // 0: Home, 1: Communities, 2: Wallet, 3: News, 4: Account ← 既定をホームに

  // ---- Home mock state ----
  final TextEditingController _search = TextEditingController();
  String _scope = 'all'; // all / internal / external

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ← 白ベースに統一
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, // ← SignInと同じフラット
        titleSpacing: 16,
        title: Image.asset(
          'assets/logo/econobook_grad_red_to_blue_lr_transparent.png',
          height: 100, // ← ロゴ拡大
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(
            'EconoBook',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kBrandBlue),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'Add',
            icon: ShaderMask(
              shaderCallback: (Rect b) => kBrandGrad.createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
          IconButton(
            onPressed: () {},
            tooltip: 'Settings',
            icon: ShaderMask(
              shaderCallback: (Rect b) => kBrandGrad.createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.settings, color: Colors.white),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _homeMock(context),                      // 0: Home (kept here)
          CommunitiesScreen(user: widget.user),    // 1: Communities
          WalletScreen(user: widget.user),         // 2: Wallet
          NewsScreen(),                            // 3: News
          AccountScreen(user: widget.user),        // 4: Account
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        unselectedItemColor: Colors.grey[600],
        items: _navItems(), // ← グラデ選択アイコン & ラベル統一
      ),
    );
  }

  // ---- BottomNav helpers (選択中はグラデ、未選択はグレー) ----
  List<BottomNavigationBarItem> _navItems() => [
        _navItem(Icons.home, 'ホーム', _index == 0),
        _navItem(Icons.groups, 'コミュニティ', _index == 1),
        _navItem(Icons.account_balance_wallet, 'ウォレット', _index == 2),
        _navItem(Icons.campaign, 'ニュース', _index == 3),
        _navItem(Icons.account_circle, 'アカウント', _index == 4),
      ];

  BottomNavigationBarItem _navItem(IconData icon, String label, bool selected) {
    final Widget iconWidget = selected
        ? ShaderMask(
            shaderCallback: (Rect b) => kBrandGrad.createShader(b),
            blendMode: BlendMode.srcIn,
            child: Icon(icon, size: 24, color: Colors.white),
          )
        : Icon(icon, size: 24, color: Colors.grey[600]);
    return BottomNavigationBarItem(icon: iconWidget, label: label);
  }

  // ========== HOME (Mock) ==========
  Widget _homeMock(BuildContext context) {
    // 白ベース / 赤→青グラデの現行トーンに合わせた Home
    final textColor = Theme.of(context).colorScheme.onSurface;
    final gray = Colors.black54;

    return ListView(
      children: [
        // Search（ログイン/サインアップと同じスタイル）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '取引・タスク・メンバーを検索',
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ShaderMask(
                  shaderCallback: (Rect b) => kBrandGrad.createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: const Icon(Icons.search, size: 22, color: Colors.white),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              filled: true,
              fillColor: kLightGray,
              contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
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

        // ===== To-Do =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: const [
              Text('やること', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // 領収書の確認
              _TodoCard(
                title: '領収書の確認',
                subtitle: 'レビューが必要な領収書 2 件',
                trailing: _AvatarStack(urls: [
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuA8kTlb1o0pI903Zq_QZGOBd2qpD8jyjxUVA3VqeyBN3fQ9Uxi8BFXU-JIqd2MTmzjKXra5K62xIXVX6LaeBfI6BCnQqPA8N72tpF1cyxLN3QJ6_cD4tmB6srh7kKogtuWVJx_lZ8dffN6HGmYZrknuXikYgpcWEN0g0Zf_DE2QgCFKrqOt9enXNNWTyjwTVsYejhECzbIaMceRS5MNeKLbJvd8O5p04uEVZVK4-c_rs0zpcVkdYr50UixHGiH30tOqyUtw2_f8VME',
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuAu42bZxSa4aahD92a23YBltpLHqofqK8G4vTDcEaoin5lPkI6BAAjRC7UanhPRPqI-0Wd3KrFTNI0wfE6SEjs81iQZYsF_pRE9-rpxy2Fz_l0a3FdlJEMIdkM6K13lvXzagL6JN7uuJ9Li2xJbI9blX_7q61M8w9bs1yuiElP515AWrfxDZfNs5V9eSndKgQ_zO4i9VcrGiPF7PjAej1qTPi7RmGBwjLLLEhpDHxqh__kBGByO-PXw56kOkMTHCb94ERwUekbpw2M',
                ]),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('領収書レビュー（準備中）')),
                ),
              ),
              const SizedBox(height: 12),
              // 承認待ち
              _TodoCard(
                title: '承認',
                subtitle: '承認が必要な項目 1 件',
                trailing: SizedBox(
                  height: 36,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: kBrandGrad,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('承認キュー（準備中）')),
                        ),
                        child: const Text('レビュー'),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 請求書の送付
              _TodoCard(
                title: '請求書',
                subtitle: '送付待ち 3 件',
                trailing: ShaderMask(
                  shaderCallback: (Rect b) => kBrandGrad.createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                ),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請求書（準備中）')),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // ===== 通知 =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: const [
              Text('通知', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundImage: NetworkImage(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuA-I8BUdwW3EU0pFK-jUu11ev_GylTgEEqJVJ2tiLjq9DQvd-bE-2RbjqEUs7mS8qDVUyUEZl6rToJIXx7eKLzPO2PfHeOYbWdoVQ1F20h8SiQs4f0IgzpFO1VF8_GWX_Yi5YbZgmdo0fPhSvnErVCqvlU0tpYr5hzvlzax3sWnNHYfYDDnNyTzCF1es9xwebRHxCE45TVlFNfZW-u0G3U-gmq71H5RiV82LE3YHCLQw4iTLN5r5WbnXe3n8wNHaK0vVjLPHvSptbI',
            ),
          ),
          title: const Text('Liam があなたの投稿にコメントしました'),
          subtitle: const Text('「良さそうなプランだね！」', style: TextStyle(color: Colors.black54)),
          onTap: () {},
        ),
        ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: kLightGray, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.schedule),
          ),
          title: const Text('請求書 #123 の期限が近づいています'),
          subtitle: const Text('2日後に期限 / 送付先: Acme Corp', style: TextStyle(color: Colors.black54)),
          onTap: () {},
        ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // ===== 最近のアクティビティ =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: const [
              Text('最近のアクティビティ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundImage: NetworkImage(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuAdZackmhBH4v-4unbN80FofXOsJXww06PxaQdvWVYrQmBqaMDdHX1SPVD49jAp4m5g45p3NGQbDYNnkmG3PoIqmMmjMpnqenS8l6BEJWRkUTH1pXexacv8jP_mgtiJy0zZ3wI13udNJTtcwfX04_HxY1vTCAza3tFQu2GbwGa0hkFDQqG6hhGgwNxiUcYaCQ5lNNNNJCNbyVyiLOw02iwdzU9GFFoGyVh15qkCFZmjCanXoHhv1A97QgP0kwNKhUkCHHpy-EZVTSE',
            ),
          ),
          title: const Text('Sophia が ¥3,800 のレシートを共有しました'),
          subtitle: const Text('「週末旅行」より', style: TextStyle(color: Colors.black54)),
          onTap: () {},
        ),
        ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: kLightGray, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.trending_down),
          ),
          title: const Text('信用スコアが 10 ポイント下がりました'),
          subtitle: const Text('新しい照会が登録されました', style: TextStyle(color: Colors.black54)),
          onTap: () {},
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // --- Home helpers ---
  // 重なったアバターを横並びで表示（幅を明示して Stack に有限サイズを与える）
  // ignore: non_constant_identifier_names
  static Widget _AvatarStack({required List<String> urls}) {
    final double base = 40; // 直径（36）+ 枠線2px*2 ≈ 40
    final double overlap = 24; // 重なり量
    final double width = urls.isEmpty ? base : base + (urls.length - 1) * overlap;

    return SizedBox(
      height: base,
      width: width, // ← これが重要。Stack に有限幅を与える
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < urls.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(urls[i]),
                  onBackgroundImageError: (_, __) {},
                ),
              ),
            ),
        ],
      ),
    );
  }




  Widget _segTab(String label, String value) {
    final selected = _scope == value;
    final color = selected ? kBrandBlue : Colors.grey[600];
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _scope = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? kBrandBlue : Colors.transparent, width: 2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
          ),
        ),
      ),
    );
  }

  Widget _homeListItem(BuildContext context, _TalkItem it) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big avatar
          CircleAvatar(
            radius: 28,
            backgroundImage: NetworkImage(it.avatarUrl),
            onBackgroundImageError: (_, __) {},
          ),
          const SizedBox(width: 12),
          // Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: title + amount
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Text('${_formatAmount(it.amount)} ${it.currency}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                // Bottom row: mini avatar + lines  /  time + unread
                Row(
                  children: [
                    // left
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundImage: NetworkImage(it.miniAvatarUrl),
                            onBackgroundImageError: (_, __) {},
                          ),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.line1, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                              Text(it.line2, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // right
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(it.time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        if (it.unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 22, height: 22,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text('${it.unread}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
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


  String _formatAmount(num n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// Simple card used in Home "やること"セクション
class _TodoCard extends StatelessWidget {
  const _TodoCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(color: Colors.black54)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

// 型定義（Homeの_listItemで使用）
class _TalkItem {
  final String avatarUrl;
  final String title;
  final num amount;
  final String currency;
  final String miniAvatarUrl;
  final String line1;
  final String line2;
  final String time;
  final int unread;

  const _TalkItem({
    required this.avatarUrl,
    required this.title,
    required this.amount,
    required this.currency,
    required this.miniAvatarUrl,
    required this.line1,
    required this.line2,
    required this.time,
    required this.unread,
  });
}
