import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth})
    : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  bool _facebookSignInInProgress = false;

  User? get currentUser => _auth.currentUser;

  /// Contract: emits the signed-in user's UID, or null.
  Stream<String?> authStateChanges() {
    return _auth.authStateChanges().map((user) => user?.uid);
  }

  /// Contract-compatible signup.
  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Existing signup screen: preserves display name.
  Future<UserCredential> signUpWithProfile({
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

  /// Contract-compatible sign in.
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Existing login screen: preserves its current API.
  Future<UserCredential> login({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential?> signInWithFacebook() async {
    if (_facebookSignInInProgress) {
      throw FirebaseAuthException(code: 'facebook-login-in-progress');
    }

    _facebookSignInInProgress = true;
    try {
      final result = await FacebookAuth.instance.login(
        permissions: const ['email', 'public_profile'],
        loginTracking: LoginTracking.enabled,
      );

      if (result.status == LoginStatus.cancelled) {
        return null;
      }
      if (result.status == LoginStatus.operationInProgress) {
        throw FirebaseAuthException(code: 'facebook-login-in-progress');
      }
      if (result.status != LoginStatus.success) {
        throw FirebaseAuthException(code: 'facebook-login-failed');
      }

      final accessToken = result.accessToken;
      if (accessToken == null || accessToken.tokenString.isEmpty) {
        throw FirebaseAuthException(code: 'facebook-missing-access-token');
      }

      final credential = FacebookAuthProvider.credential(
        accessToken.tokenString,
      );
      return await _auth.signInWithCredential(credential);
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase().contains('network')
          ? 'network-request-failed'
          : 'facebook-login-failed';
      throw FirebaseAuthException(code: code);
    } finally {
      _facebookSignInInProgress = false;
    }
  }

  /// Contract-compatible sign out.
  Future<void> signOut() => _auth.signOut();

  /// Existing profile screen API.
  Future<void> logout() => signOut();
}
