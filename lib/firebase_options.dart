import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured yet');
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDPL5A0Dwr9nq_YsXhaQ-IlFArEbS4M5V8',
    appId: '1:1049036800006:web:dd8d83fab04ccfe5230387',
    messagingSenderId: '1049036800006',
    projectId: 'purrsync-42b2c',
    authDomain: 'purrsync-42b2c.firebaseapp.com',
    storageBucket: 'purrsync-42b2c.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDPL5A0Dwr9nq_YsXhaQ-IlFArEbS4M5V8',
    appId: '1:1049036800006:android:dd8d83fab04ccfe5230387',
    messagingSenderId: '1049036800006',
    projectId: 'purrsync-42b2c',
    storageBucket: 'purrsync-42b2c.firebasestorage.app',
  );
}