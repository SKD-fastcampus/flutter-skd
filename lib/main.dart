import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:seogodong/config/constants.dart';
import 'package:seogodong/screens/root_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }

  runApp(const SeogodongApp());
  _printKakaoKeyHash();
}

Future<void> _printKakaoKeyHash() async {
  try {
    String keyHash = await KakaoSdk.origin;
    print('현재 앱의 Kakao Key Hash: $keyHash');
  } catch (e) {
    print('Kakao Key Hash를 가져오는 중 오류 발생: $e');
  }
}

class SeogodongApp extends StatelessWidget {
  const SeogodongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seogodong Link Check',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const RootPage(),
    );
  }
}
