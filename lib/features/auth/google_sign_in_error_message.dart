import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

String googleSignInErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using another sign-in method.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'missing-google-id-token':
        return 'Google sign-in could not be completed. Please try again.';
      case 'google-login-in-progress':
        return 'Google sign-in is already in progress.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled in Firebase Authentication.';
      case 'invalid-credential':
        return 'Google could not verify this login. Please try again.';
      default:
        return 'Google sign-in failed. Please try again.';
    }
  }

  if (error is GoogleSignInException) {
    switch (error.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not configured correctly for this app.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in is unavailable right now. Please try again.';
      default:
        return 'Google sign-in failed. Please try again.';
    }
  }

  return 'Google sign-in failed. Check your connection and try again.';
}
