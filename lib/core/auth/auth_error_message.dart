import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns whatever sign-in / sign-up threw into a short, translated
/// message a user can act on — never the raw exception (which reads like
/// `AuthApiException(message: Invalid login credentials, statusCode: 400,
/// code: invalid_credentials)`).
///
/// Matches on Supabase's stable error `code`s first, falling back to the
/// HTTP status, so wording changes on the server don't break it.
String authErrorMessage(Object error) {
  // No dart:io here (the app also builds for web), so offline errors are
  // recognised by type where possible, by name otherwise.
  final raw = error.toString();
  if (error is AuthRetryableFetchException ||
      error is TimeoutException ||
      raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('ClientException')) {
    return 'auth_error_network'.tr();
  }

  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'auth_error_invalid_credentials'.tr();
      case 'email_not_confirmed':
        return 'auth_error_email_not_confirmed'.tr();
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'auth_error_rate_limited'.tr();
      case 'user_already_exists':
      case 'email_exists':
        return 'auth_error_user_exists'.tr();
      case 'weak_password':
        return 'auth_error_weak_password'.tr();
      case 'email_address_invalid':
      case 'validation_failed':
        return 'auth_error_invalid_email'.tr();
    }
    // Older GoTrue versions don't always send a code.
    if (error.statusCode == '429') return 'auth_error_rate_limited'.tr();
    if (error.statusCode == '400' &&
        error.message.toLowerCase().contains('invalid login')) {
      return 'auth_error_invalid_credentials'.tr();
    }
  }

  return 'auth_error_generic'.tr();
}
