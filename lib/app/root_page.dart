import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:seogodong/features/authentication/presentation/login_page.dart';
import 'package:seogodong/features/dashboard/presentation/home_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    if (firebase_auth.FirebaseAuth.instance.currentUser != null) {
      _showHome = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showHome) {
      return const HomePage();
    }
    return LoginPage(
      onLoginSuccess: () async {
        if (!mounted) return;
        setState(() {
          _showHome = true;
        });
      },
    );
  }
}
