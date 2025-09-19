import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ---- Local brand tokens (duplicated to avoid circular import) ----
const Color kBrandBlue = Color(0xFF0D80F2);
const Color kLightGray = Color(0xFFF0F2F5);
const LinearGradient kBrandGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
);

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.user});
  final User user;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.doc('users/${widget.user.uid}');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = (data['name'] as String?) ?? (widget.user.displayName ?? '未設定');
        final handle = (data['handle'] as String?) ?? '@${(widget.user.uid).substring(0, 6)}';
        final score = (data['score'] is Map ? (data['score']['trust'] as num?) : null) ?? 700;

        final settings = (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final notifications = (settings['notifications'] as Map?)?.cast<String, dynamic>() ?? {};
        final minorMode = (settings['minorMode'] as Map?)?.cast<String, dynamic>() ?? {};
        final developer = (settings['developer'] as Map?)?.cast<String, dynamic>() ?? {};

        final txNoti = notifications['transactions'] as bool? ?? true;
        final taskNoti = notifications['tasks'] as bool? ?? true;
        final newsNoti = notifications['news'] as bool? ?? false;

        final minorEnabled = minorMode['enabled'] as bool? ?? false;

        final expFlags = developer['experiments'] as bool? ?? false;
        final sandbox = developer['sandbox'] as bool? ?? false;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _sectionHeader('プロフィール'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: kLightGray,
                  child: Text(
                    (name.isNotEmpty ? name[0] : '?'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                subtitle: Text(handle, style: const TextStyle(color: Colors.black54)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editProfileDialog(data),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('信用スコア'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: kLightGray, borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: _gradientIcon(Icons.verified_user)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$score', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(_gradeForScore(score), style: const TextStyle(color: Colors.green)),
                    ],
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('スコアの計算式'),
                          content: const Text('遅延・完了率・通報率・相互評価などから算出（将来公開予定）。'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
                        ),
                      );
                    },
                    icon: const Icon(Icons.help_outline),
                    label: const Text('説明'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('未成年モード'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _settingsSwitchTile(
                    title: '未成年モードを有効にする',
                    subtitle: '日次・月次の上限や夜間投稿制限を適用します。',
                    value: minorEnabled,
                    onChanged: (v) => _updateSetting('settings.minorMode.enabled', v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('通知'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _settingsSwitchTile(
                    title: '取引',
                    value: txNoti,
                    onChanged: (v) => _updateSetting('settings.notifications.transactions', v),
                  ),
                  const Divider(height: 1),
                  _settingsSwitchTile(
                    title: 'タスク・期限',
                    value: taskNoti,
                    onChanged: (v) => _updateSetting('settings.notifications.tasks', v),
                  ),
                  const Divider(height: 1),
                  _settingsSwitchTile(
                    title: 'ニュース・アップデート',
                    value: newsNoti,
                    onChanged: (v) => _updateSetting('settings.notifications.news', v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('セキュリティ'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: _gradientIcon(Icons.devices_other),
                    title: const Text('端末とセッションの管理'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('準備中：最近のログイン端末を表示します')),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: _gradientIcon(Icons.shield_moon_outlined),
                    title: const Text('自動リスク制御'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('準備中：異常検知の設定画面')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('連携'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: _gradientIcon(Icons.qr_code_2),
                    title: const Text('PayPay 連携'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('外部送金リンクの既定を設定（準備中）')),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: _gradientIcon(Icons.mail_outline),
                    title: const Text('メール・Google 連携'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('認証連携の管理（準備中）')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('データ管理'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x22000000)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: _gradientIcon(Icons.file_upload_outlined),
                    title: const Text('データを書き出す'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('CSV/JSONエクスポート（準備中）')),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('アカウント削除', style: TextStyle(color: Colors.red)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.red),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('アカウント削除'),
                          content: const Text('この操作は取り消せません。続行しますか？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除する')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          await FirebaseAuth.instance.currentUser?.delete();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('削除には再ログインが必要な場合があります')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: kBrandGrad, borderRadius: BorderRadius.circular(24)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async => FirebaseAuth.instance.signOut(),
                    child: const Text('ログアウト'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---- Helpers ----
  Widget _gradientIcon(IconData data) {
    return ShaderMask(
      shaderCallback: (Rect b) => kBrandGrad.createShader(b),
      blendMode: BlendMode.srcIn,
      child: Icon(data, color: Colors.white),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
    );
  }

  Widget _settingsSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: Colors.black54)),
      activeColor: kBrandBlue,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Future<void> _updateSetting(String fieldPath, dynamic value) async {
    try {
      await FirebaseFirestore.instance.doc('users/${widget.user.uid}').set(
        {fieldPath: value},
        SetOptions(merge: true),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    }
  }

  Future<void> _editProfileDialog(Map<String, dynamic> userDoc) async {
    final nameCtrl = TextEditingController(text: (userDoc['name'] as String?) ?? (widget.user.displayName ?? ''));
    final handleCtrl = TextEditingController(text: (userDoc['handle'] as String?) ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('プロフィールを編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名前')),
            TextField(controller: handleCtrl, decoration: const InputDecoration(labelText: 'ハンドル（任意）')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () async {
              await FirebaseFirestore.instance.doc('users/${widget.user.uid}').set({
                'name': nameCtrl.text.trim(),
                'handle': handleCtrl.text.trim(),
              }, SetOptions(merge: true));
              if (context.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _gradeForScore(num score) {
    if (score >= 800) return 'とても良い';
    if (score >= 700) return '良い';
    if (score >= 600) return '普通';
    return '要注意';
  }
}
