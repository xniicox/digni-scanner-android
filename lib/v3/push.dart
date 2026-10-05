import 'package:firebase_core/firebase_core.dart';

// The public Firebase client identifiers are supplied at build time by the
// DIGNI-owned project. Service-account credentials stay only on WordPress.
const firebaseProjectId = String.fromEnvironment('DIGNI_FIREBASE_PROJECT_ID');
const firebaseAppId = String.fromEnvironment('DIGNI_FIREBASE_APP_ID');
const firebaseApiKey = String.fromEnvironment('DIGNI_FIREBASE_API_KEY');
const firebaseSenderId = String.fromEnvironment('DIGNI_FIREBASE_SENDER_ID');

Future<void> initializeDigniFirebase() async {
  if (firebaseProjectId.isEmpty || firebaseAppId.isEmpty ||
      firebaseApiKey.isEmpty || firebaseSenderId.isEmpty) return;
  try {
    await Firebase.initializeApp(options: const FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseSenderId,
      projectId: firebaseProjectId,
    ));
  } catch (_) {
    // The authenticated in-app pending list remains usable when FCM is down.
  }
}

bool get digniFirebaseReady => Firebase.apps.isNotEmpty;
