import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'contact_form_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openContact() async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactFormScreen()),
    );
  }

  Future<void> _sendReset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _toast('メールアドレスを入力してください');
      return;
    }
    setState(() => _loading = true);
    try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (!mounted) return;
        Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResetPasswordSentScreen()),
        );
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email'  => 'メールアドレスの形式が正しくありません',
        'user-not-found' => 'このメールアドレスのユーザーは見つかりませんでした',
        'missing-email'  => 'メールアドレスを入力してください',
        _                => '送信に失敗しました (${e.code})',
      };
      _toast(msg);
    } catch (e) {
      _toast('送信に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0D80F2);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: '戻る',
          onPressed: () => Navigator.pop(context),
          icon: ShaderMask(
            shaderCallback: (Rect bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          ),
        ),
        centerTitle: true,
        title: const Text(''),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // ロゴ
                    Image.asset(
                      'assets/logo/econobook_grad_red_to_blue_lr_transparent.png',
                      width: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'パスワードの再設定',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ご登録のメールアドレス宛に、パスワード再設定用のリンクをお送りします。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),

                    // メール入力
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'メールアドレス',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                            ).createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: const Icon(Icons.email, size: 22, color: Colors.white),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: brandBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 送信ボタン（ログイン画面と同じスタイル）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            onPressed: _loading ? null : _sendReset,
                            child: _loading
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('送信'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // フッター：お問い合わせ
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('お困りですか？'),
                    TextButton(
                      onPressed: _openContact,
                      child: const Text('お問い合わせ'),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordSentScreen extends StatelessWidget {
  const ResetPasswordSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0D80F2);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // ロゴ（ログイン画面と同じ）
                    Image.asset(
                      'assets/logo/econobook_grad_red_to_blue_lr_transparent.png',
                      width: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        'EconoBook',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: brandBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      'メールを送信しました',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'パスワード再設定用のメールを送信しました。メールをご確認ください。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),

                    // ホームに戻る（ログイン画面と同じグラデボタン表現）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xFFE53935), Color(0xFF0D80F2)], // 赤→青
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            onPressed: () {
                              // 最初の画面（通常はサインイン/ホーム）まで戻る
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },
                            child: const Text('ホームに戻る'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // （必要ならフッターの「お困りですか？ お問い合わせ」も追加できます）
          ],
        ),
      ),
    );
  }
}