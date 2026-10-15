import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth})
    : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Currently signed-in user.
  User? get currentUser => _auth.currentUser;

  /// Emits authentication changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register a new user with email and password.
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.updateDisplayName(displayName.trim());
    await credential.user?.reload();

    return credential;
  }

  /// Sign in an existing user.
  Future<UserCredential> login({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sign out the current user.
  Future<void> logout() => _auth.signOut();
}
