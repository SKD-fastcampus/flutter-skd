import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:seogodong/core/config/constants.dart';
import 'package:seogodong/app/root_page.dart';
import 'package:seogodong/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } else {
    await Firebase.initializeApp();
  }

  if (kIsWeb) {
    if (kakaoJavaScriptAppKey.isNotEmpty) {
      KakaoSdk.init(javaScriptAppKey: kakaoJavaScriptAppKey);
    }
  } else if (kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }

  runApp(const SeogodongApp());
  if (!kIsWeb) {
    _printKakaoKeyHash();
  }
}

Future<void> _printKakaoKeyHash() async {
  try {
    String keyHash = await KakaoSdk.origin;
    debugPrint('현재 앱의 Kakao Key Hash: $keyHash');
  } catch (e) {
    debugPrint('Kakao Key Hash를 가져오는 중 오류 발생: $e');
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
