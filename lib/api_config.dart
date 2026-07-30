/// Build-time API configuration.
///
/// The single value `API_BASE_URL` can be injected via `--dart-define` by CI,
/// defaulting to the live Cloudflare Worker endpoint `https://sync-api.indsasuke59.workers.dev`.
/// This is the ONLY backend credential the app needs — all Supabase and
/// Firebase secrets live exclusively in the Cloudflare Worker.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sync-api.indsasuke59.workers.dev',
  );

  /// Deep-link scheme used for OAuth callback from the Worker.
  static const String authCallbackScheme = 'syncalarm';
  static const String authCallbackHost = 'auth-callback';

  static void validate() {
    final endpoint = Uri.tryParse(baseUrl);
    if (endpoint == null || endpoint.host.isEmpty) {
      throw StateError(
        'Missing or invalid API_BASE_URL. Configure the release build secrets.',
      );
    }
    // Allow http:// in debug builds (e.g. wrangler dev on localhost)
    const isDebug = bool.fromEnvironment('dart.vm.product') == false;
    if (!isDebug && endpoint.scheme != 'https') {
      throw StateError(
        'API_BASE_URL must use HTTPS in release builds.',
      );
    }
  }
}
