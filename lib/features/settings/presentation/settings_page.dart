import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:seogodong/features/authentication/presentation/login_page.dart';
import 'package:seogodong/app/root_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _logout() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {}
    await firebase_auth.FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootPage()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('앱에서 로그아웃하시겠습니까?', style: TextStyle(fontSize: 18)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await _logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = user != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader('계정'),
          if (isLoggedIn)
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
              onTap: _confirmLogout,
            )
          else
            ListTile(
              leading: const Icon(Icons.login, color: Colors.blue),
              title: const Text('로그인', style: TextStyle(color: Colors.blue)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoginPage(
                      onLoginSuccess: () async {
                        Navigator.pop(context);
                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          const Divider(),
          _buildSectionHeader('정보'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 버전'),
            trailing: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
