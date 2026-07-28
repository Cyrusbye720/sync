import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized Supabase configuration.
///
/// Reads from a `.env` file at app start. The keys exposed here are
/// intentionally public (anon key) — RLS in Postgres is the security boundary.
class SupabaseConfig {
  SupabaseConfig._();

  static String get url {
    final value = dotenv.env['SUPABASE_URL'];
    if (value == null || value.isEmpty) {
      throw StateError(
        'SUPABASE_URL is not set. Define it in .env or pass --dart-define.',
      );
    }
    return value;
  }

  static String get anonKey {
    final value = dotenv.env['SUPABASE_ANON_KEY'];
    if (value == null || value.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is not set. Define it in .env or pass --dart-define.',
      );
    }
    return value;
  }

  /// Used by `signInWithOAuth` so the OS returns the user to the app.
  static const String oauthRedirect = 'io.supabase.syncalarm://login-callback/';
}
