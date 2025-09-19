import 'package:flutter/material.dart';

// ---- Brand tokens（他画面と統一）----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  // フィルタ（チップ）
  final List<String> _cats = const ['すべて', '不正', '価格', '納期', '一般トラブル', '成功事例'];
  String _selected = 'すべて';

  // ダミー記事データ（後でFirestore/HTTPに差し替え可）
  final List<_CaseItem> _cases = const [
    _CaseItem(
      title: 'ケーススタディ：納期のジレンマ',
      description: '非現実的な納期と計画不足で失敗したプロジェクトの詳細分析。',
      category: '納期',
      image:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuD4X6srpzTDfF70eLZ_U4yP5Xy4XWbAFIvTAKrqFMkxJG4eDyYZ2iwU2LHTEMXk6XKrdLdHikMPW7F65ObdXhlBqV_UHWX4DoPFMNs2Ut9C5t9c1lJQltJBiatFxTHiY0d0LyTDGJU_3EinZ2qgB0V22ctb5Q7SmpF_qZvEVaBDmb0eG9JKhz3bVRjBPKz4R2le929195ns3jgqVPPnKFb6TKN89o-b5LINNBXbrRK9x_09C4qDH2_AlPjKK4QJHqzLCe2T7ELb18w',
    ),
    _CaseItem(
      title: 'ケーススタディ：価格の綱引き',
      description: '価格交渉の難航を乗り越え成功した案件の要因を検証。',
      category: '価格',
      image:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCb1kExjDcF0pSZFMSFDB_7RU6viwhlAeS43jeHteJPEcFUiJsKrVaW0n4mtAJ2l9EIQW1TavGjlibDZ0r7xiK49LjScwPuej6nr0O1l6H1mvF7rEJ5YHQMO3dwTxt0GN0-Fyj_MCgkeuzPgwanvWlUFJzlINwi6sbMGJWvc-H1FRQcKPn6n2oxEcHAAXyN3N7WKT-nVZrIXX-vXPkmxOZrpGshAWtP1wIOPFutMbyenr_vR243fbpc6GQXgOSbRHmjPcoRK5zqIGE',
    ),
  ];

  final List<_CardItem> _arbitrations = const [
    _CardItem(
      title: '仲裁を依頼する',
      description: '案件を提出して、経験ある第三者メディエーターとつながりましょう。',
      image:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuB1cTK3puHd2HFx7JJBW-Bm4oFNSjKaTr_XdlAycl2NAbWArjq1ACcMEqv9Sie2grzEcsB9V5IiOD80OgodZq58Et8FflXw0_bvwAfG2V5t1ZYPNCJdJ60xxulAA-tHtjwGzmXnleuhcolw5kvWb6GqmF1Ffu_8cJk5PK_e4LknddBzVGKinzM1Rav7fVoz1nsQaxSl5nix7Ep0RqSV3oXk6JAK9XHoGQkP7bAIt_iT3ZF5H2v3oGfB2zAAljjUSDnZKpQc4dVnt0U',
    ),
    _CardItem(
      title: '仲裁人として応募',
      description: 'コミュニティの紛争解決をサポートする仲裁人として参加しましょう。',
      image:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBVTYAfSdchw00bSc64V2_5taVH-OYkVk0kvYXPreaI3RLjTUTz2PyJaDtWeHUjoBG1OhA2ymfFVZlYLe_oHfmGMQsStRI3Y1hPwxTaH1nTlLxOrfXDK4jxkwHgqEsG3aX2ir6e8H2QVFGRWJ4HJnjoR33aeTNtKotpYSkmgigcAA6iGm6B25aKBhZy0Tv6_-KeGZADf9P8eksyl3WM7KVSQm1w8nj8QzRCCHppe3PQXQ8SzuM8uUr0lqowLciByQXv0ND7ZmUcPOY',
    ),
  ];

  final List<String> _safety = const [
    '未成年モード',
    '禁止事項',
    '偽装請負（違法な雇用形態）',
    '著作権・研究倫理',
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selected == 'すべて'
        ? _cases
        : _cases.where((e) => e.category == _selected).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('ニュース', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          // ===== Case Studies =====
          _sectionTitle('事例'),
          const SizedBox(height: 8),
          _categoryChips(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final it in filtered) ...[
                  _caseCard(it),
                  const SizedBox(height: 12),
                ]
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ===== Arbitration =====
          _sectionTitle('仲裁'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final it in _arbitrations) ...[
                  _imageCard(it),
                  const SizedBox(height: 12),
                ]
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ===== Safety Center =====
          _sectionTitle('セーフティセンター'),
          const SizedBox(height: 4),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0x22000000)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _safety.length; i++) ...[
                  ListTile(
                    title: Text(_safety[i]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _toast(context, '「${_safety[i]}」は準備中です'),
                  ),
                  if (i != _safety.length - 1) const Divider(height: 1),
                ]
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ===== Updates & Release Notes =====
          _sectionTitle('アップデート & リリースノート'),
          const SizedBox(height: 4),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0x22000000)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: _gradIcon(Icons.article),
              title: const Text('v2.3.1 — バグ修正とパフォーマンス改善'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _toast(context, 'リリースノート（準備中）'),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ===== UI parts =====
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final label = _cats[i];
          final selected = _selected == label;
          return _FilterChipGrad(
            label: label,
            selected: selected,
            onTap: () => setState(() => _selected = label),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _cats.length,
      ),
    );
  }

  Widget _caseCard(_CaseItem it) {
    return _ImageRightCard(
      title: it.title,
      description: it.description,
      imageUrl: it.image,
      onTap: () => _toast(context, 'ケーススタディ（準備中）'),
    );
  }

  Widget _imageCard(_CardItem it) {
    return _ImageRightCard(
      title: it.title,
      description: it.description,
      imageUrl: it.image,
      onTap: () => _toast(context, it.title),
    );
  }

  Widget _gradIcon(IconData icon) {
    return ShaderMask(
      shaderCallback: (Rect b) => kBrandGrad.createShader(b),
      blendMode: BlendMode.srcIn,
      child: Icon(icon, color: Colors.white),
    );
  }

  void _toast(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

// ===== Small components =====
class _FilterChipGrad extends StatelessWidget {
  const _FilterChipGrad({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: kBrandGrad,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: DefaultTextStyle(
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              child: Text(''), // placeholder; replaced below
            ),
          ),
        ),
      );
    } else {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kBrandBlue),
          foregroundColor: kBrandBlue,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
  }
}

// NOTE: Selected chip needs the label text; wrap with Stack to paint white text cleanly
extension on _FilterChipGrad {
  Widget build(BuildContext context) {
    if (!selected) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kBrandBlue),
          foregroundColor: kBrandBlue,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(gradient: kBrandGrad, borderRadius: BorderRadius.all(Radius.circular(999))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

class _ImageRightCard extends StatelessWidget {
  const _ImageRightCard({
    required this.title,
    required this.description,
    required this.imageUrl,
    this.onTap,
  });

  final String title;
  final String description;
  final String imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 90, height: 90, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 90, height: 90,
          decoration: BoxDecoration(color: kLightGray, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (Rect b) => kBrandGrad.createShader(b),
                      blendMode: BlendMode.srcIn,
                      child: const Text('', style: TextStyle(color: Colors.white)), // keep structure stable
                    ),
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: Colors.black54),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Image on right
              image,
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Data models ----
class _CaseItem {
  final String title;
  final String description;
  final String category;
  final String image;
  const _CaseItem({
    required this.title,
    required this.description,
    required this.category,
    required this.image,
  });
}

class _CardItem {
  final String title;
  final String description;
  final String image;
  const _CardItem({
    required this.title,
    required this.description,
    required this.image,
  });
}