import 'package:firebase_auth/firebase_auth.dart';

String facebookSignInErrorMessage(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Facebook sign-in failed. Check your Facebook app configuration and try again.';
  }

  switch (error.code) {
    case 'account-exists-with-different-credential':
    case 'email-already-in-use':
      return 'An account already exists with this email using another sign-in method. Sign in with that method first.';
    case 'credential-already-in-use':
      return 'This Facebook account is already linked to another PitchCut account.';
    case 'invalid-credential':
      return 'Facebook could not verify this login. Please try again.';
    case 'network-request-failed':
      return 'Check your internet connection and try again.';
    case 'operation-not-allowed':
      return 'Facebook sign-in is not enabled in Firebase Authentication yet.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support for help.';
    case 'facebook-login-in-progress':
      return 'Facebook sign-in is already in progress.';
    case 'facebook-login-failed':
    case 'facebook-missing-access-token':
      return 'Facebook sign-in could not be completed. Check the Facebook App ID, Client Token, and Android key hashes.';
    default:
      return 'Facebook sign-in failed. Please try again.';
  }
}
