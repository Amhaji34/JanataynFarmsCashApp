import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase config for this app, generated from the Android
/// `google-services.json` downloaded from the Firebase console (project
/// "janatain-27510"). Android-only — this app doesn't ship on iOS/web,
/// so other platforms just throw if ever hit.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBJfyR8YaFuD1chqI4Tz3JygXBIjsdNncA',
    appId: '1:864129709472:android:bcfff82a0a87526444a0c5',
    messagingSenderId: '864129709472',
    projectId: 'janatain-27510',
    storageBucket: 'janatain-27510.firebasestorage.app',
  );
}
