import 'dart:async';

/// Push delivery is optional. SYNC remains functional through its local
/// exact-alarm engine; implementations may add ntfy, UnifiedPush, or another
/// open push transport without changing alarm or pairing behavior.
abstract class PushProvider {
  Future<void> initialize();
  Future<void> refreshToken();
  Stream<Map<String, dynamic>> get events;
  Future<void> replayInitialMessage();
  Future<void> dispose();
}

class LocalPushProvider implements PushProvider {
  LocalPushProvider._();
  static final instance = LocalPushProvider._();
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshToken() async {}

  @override
  Future<void> replayInitialMessage() async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
