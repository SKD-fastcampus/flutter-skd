import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get web => FirebaseOptions(
        apiKey: const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
        appId: const String.fromEnvironment('FIREBASE_WEB_APP_ID'),
        messagingSenderId:
            const String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID'),
        projectId: const String.fromEnvironment('FIREBASE_WEB_PROJECT_ID'),
        authDomain: const String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN'),
        storageBucket:
            const String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET'),
        measurementId:
            const String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID'),
      );
}
