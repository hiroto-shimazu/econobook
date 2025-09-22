import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_up_screen.dart';
import 'reset_password_screen.dart';
import 'contact_form_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmailPassword() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      _toast('メールアドレスとパスワードを入力してください');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);
      // 成功時は AuthGate が Home に切り替え
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'メールアドレスの形式が正しくありません',
        'user-disabled' => 'このユーザーは無効化されています',
        'user-not-found' => 'ユーザーが見つかりません',
        'wrong-password' => 'パスワードが違います',
        'too-many-requests' => '試行回数が多すぎます。しばらくして再試行してください',
        _ => 'ログインに失敗しました (${e.code})',
      };
      _toast(msg);
    } catch (e) {
      _toast('ログインに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogleWeb() async {
    setState(() => _loading = true);
    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      _toast('Googleログインに失敗: ${e.code}');
    } catch (e) {
      _toast('Googleログインに失敗: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openContact() async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactFormScreen()),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
                    // ロゴ画像（赤→青グラデ）
                    Image.asset(
                      'assets/logo/econobook_grad_red_to_blue_lr_transparent.png',
                      width: 200,
                      fit: BoxFit.contain,
                      // もしアセット未読込みでもUIを壊さないフォールバック
                      errorBuilder: (_, __, ___) => const Text(
                        'EconoBook',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: brandBlue),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // メール
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'メールアドレス',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) =>
                                const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFFE53935),
                                Color(0xFF0D80F2)
                              ], // 赤→青
                            ).createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: const Icon(Icons.email,
                                size: 22, color: Colors.white),
                          ),
                        ),
                        // アイコンの表示領域を確保（潰れ防止）
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: brandBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // パスワード
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'パスワード',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) =>
                                const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFFE53935),
                                Color(0xFF0D80F2)
                              ], // 赤→青
                            ).createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: const Icon(Icons.lock,
                                size: 22, color: Colors.white),
                          ),
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: brandBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ResetPasswordScreen()),
                                );
                              },
                        child: const Text('パスワードをお忘れですか？'),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ログインボタン（背景を赤→青グラデーション）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0xFFE53935),
                              Color(0xFF0D80F2)
                            ], // 赤→青
                          ),
                          borderRadius:
                              BorderRadius.circular(28), // height/2 と同じ
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
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            onPressed:
                                _loading ? null : _signInWithEmailPassword,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('ログイン'),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // アカウント作成ボックス（白背景＋グラデ枠）
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0xFFE53935),
                              Color(0xFF0D80F2)
                            ], // 赤→青
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2), // ← 枠線の太さ（2px）
                          child: Material(
                            color: Colors.white,
                            shape: const StadiumBorder(),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(28),
                              onTap: _loading
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const SignUpScreen()),
                                      );
                                    },
                              child: const Center(
                                child: Text(
                                  'アカウントを作成',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child:
                              Text('または', style: TextStyle(color: Colors.grey)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Googleでログイン
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _signInWithGoogleWeb,
                      icon: Image.network(
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuB7_dG36PMz-QycJ2aSlMvoBFhKgUNCYMfLCb6SUVkWNScZUgT2PcE2Lvq2PB-MucrqJxnGNJ6fb629xiUYx9qoBIXeghkm60g0i9iTwgZ-c3b0v_A104kwxgbNXF9S_B6m4htpUEJxxwn9f9LukpOEugd84THjlFC1fjZlaO4-YWZCVe7QOrQMQmcTqAc_c_MI92b5McG90u4uL7_2ab5_JoWZx9P6YkCfZJhCXes9k1VUlbPn_AjNuXGGdKv6vPMn1sdfOepS8Oke',
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                      label: const Text('Googleでログイン'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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
