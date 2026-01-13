import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:seogodong/core/config/constants.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});

  final Future<void> Function() onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoggingIn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('게섯거라', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 84),
            InkWell(
              onTap: _isLoggingIn ? null : _handleKakaoLogin,
              child: Opacity(
                opacity: _isLoggingIn ? 0.6 : 1,
                child: Image.asset('kakao_login_large_wide.png', height: 56),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onLoginSuccess,
              child: const Text(
                '로그인 없이 둘러보기',
                style: TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 40),
            RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 16, height: 3.6),
                children: [
                  const TextSpan(text: '😈 메시지에 있는 수상한 링크, '),
                  const TextSpan(
                    text: '게섯거라',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '로 '),
                  const TextSpan(
                    text: '공유',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '하세요\n'),
                  const TextSpan(text: '🔍 '),
                  const TextSpan(
                    text: '게섯거라',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '가 위험한 링크인지 '),
                  const TextSpan(
                    text: '검사',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '해 드려요'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleKakaoLogin() async {
    if (kakaoNativeAppKey.isEmpty) {
      _showSnack('KAKAO_NATIVE_APP_KEY가 필요합니다.');
      return;
    }
    setState(() {
      _isLoggingIn = true;
    });
    try {
      final bool installed = await isKakaoTalkInstalled();
      final OAuthToken token = installed
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      final String? idToken = token.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Kakao idToken이 없습니다.');
      }
      final firebase_auth.OAuthProvider provider = firebase_auth.OAuthProvider(
        'oidc.seogodong',
      );
      final firebase_auth.OAuthCredential credential = provider.credential(
        idToken: idToken,
        accessToken: token.accessToken,
      );
      await firebase_auth.FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      await widget.onLoginSuccess();
      if (!mounted) return;
      _showSnack('카카오 로그인 성공!');
    } catch (error) {
      _showSnack('카카오 로그인 실패: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
