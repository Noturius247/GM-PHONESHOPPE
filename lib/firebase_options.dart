import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyABcGA7FlA-YNfZmSlEJDaHQaFsRtg9crg',
    appId: '1:71583971266:web:cf8a208760bfa99aa2485b',
    messagingSenderId: '71583971266',
    projectId: 'gmphoneshoppe-f0420',
    authDomain: 'gmphoneshoppe-f0420.firebaseapp.com',
    databaseURL: 'https://gmphoneshoppe-f0420-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gmphoneshoppe-f0420.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyABcGA7FlA-YNfZmSlEJDaHQaFsRtg9crg',
    appId: '1:71583971266:android:31af82b2bbec8263a2485b',
    messagingSenderId: '71583971266',
    projectId: 'gmphoneshoppe-f0420',
    databaseURL: 'https://gmphoneshoppe-f0420-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gmphoneshoppe-f0420.firebasestorage.app',
  );

  // Placeholder for iOS - configure in Firebase Console if needed
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyABcGA7FlA-YNfZmSlEJDaHQaFsRtg9crg',
    appId: '1:71583971266:ios:YOUR_IOS_APP_ID',
    messagingSenderId: '71583971266',
    projectId: 'gmphoneshoppe-f0420',
    databaseURL: 'https://gmphoneshoppe-f0420-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gmphoneshoppe-f0420.firebasestorage.app',
    iosBundleId: 'com.example.gmPhoneshoppe',
  );

  // Placeholder for macOS - configure in Firebase Console if needed
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyABcGA7FlA-YNfZmSlEJDaHQaFsRtg9crg',
    appId: '1:71583971266:macos:YOUR_MACOS_APP_ID',
    messagingSenderId: '71583971266',
    projectId: 'gmphoneshoppe-f0420',
    databaseURL: 'https://gmphoneshoppe-f0420-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gmphoneshoppe-f0420.firebasestorage.app',
    iosBundleId: 'com.example.gmPhoneshoppe',
  );

  // Placeholder for Windows - configure in Firebase Console if needed
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyABcGA7FlA-YNfZmSlEJDaHQaFsRtg9crg',
    appId: '1:71583971266:web:cf8a208760bfa99aa2485b',
    messagingSenderId: '71583971266',
    projectId: 'gmphoneshoppe-f0420',
    authDomain: 'gmphoneshoppe-f0420.firebaseapp.com',
    databaseURL: 'https://gmphoneshoppe-f0420-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gmphoneshoppe-f0420.firebasestorage.app',
  );
}
