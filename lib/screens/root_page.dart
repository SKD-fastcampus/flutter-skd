import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:seogodong/screens/login_page.dart';
import 'package:seogodong/screens/share_check_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool _isReady = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadLoginState();
  }

  Future<void> _loadLoginState() async {
    final firebase_auth.User? user =
        firebase_auth.FirebaseAuth.instance.currentUser;
    bool isValid = false;
    if (user != null) {
      try {
        await user.getIdToken();
        isValid = true;
      } catch (_) {
        await firebase_auth.FirebaseAuth.instance.signOut();
      }
    }
    setState(() {
      _isLoggedIn = isValid;
      _isReady = true;
    });
  }

  Future<void> _markLoggedIn() async {
    if (!mounted) return;
    setState(() {
      _isLoggedIn = true;
    });
  }

  Future<void> _logout() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {}
    await firebase_auth.FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isLoggedIn) {
      return ShareCheckPage(onLogout: _logout);
    }
    return LoginPage(onLoginSuccess: _markLoggedIn);
  }
}
