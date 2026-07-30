import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api_config.dart';
import '../models/alarm_log_model.dart';
import '../models/alarm_model.dart';
import '../models/announcement_model.dart';
import '../models/nudge_model.dart';
import '../models/pairing_model.dart';
import '../models/profile_model.dart';

/// HTTP API client for the Cloudflare Worker backend.
///
/// Replaces the old `SupabaseService`. The app communicates exclusively
/// with the Worker over HTTPS using opaque session tokens. No Supabase
/// URL, anon key, or Firebase credentials exist in the app.
class ApiService {
  ApiService._();

  static ApiService? _instance;
  static const String _tokenKey = 'sync_session_token';
  static const String _userIdKey = 'sync_user_id';

  final http.Client _http = http.Client();
  String? _token;
  String? _userId;
  WebSocketChannel? _wsChannel;

  /// Auth state changes. Emits when session is created or destroyed.
  final StreamController<bool> _authController =
      StreamController<bool>.broadcast();
  Stream<bool> get authState => _authController.stream;

  String? get currentUserId => _userId;
  String? get currentToken => _token;
  bool get isAuthenticated => _token != null && _userId != null;

  static Future<ApiService> initialize() async {
    final instance = ApiService._();
    final prefs = await SharedPreferences.getInstance();
    instance._token = prefs.getString(_tokenKey);
    instance._userId = prefs.getString(_userIdKey);
    _instance = instance;
    return instance;
  }

  static ApiService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('ApiService.initialize() must be called before use.');
    }
    return inst;
  }

  // ─── Internal HTTP Helpers ──────────────────────────────────────────────

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  String _url(String path) => '${ApiConfig.baseUrl}$path';

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _http.get(Uri.parse(_url(path)), headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getList(String path) async {
    final res = await _http.get(Uri.parse(_url(path)), headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final res = await _http.post(
      Uri.parse(_url(path)),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode >= 400) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
    if (res.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _http.patch(
      Uri.parse(_url(path)),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
    if (res.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _delete(String path) async {
    final res = await _http.delete(Uri.parse(_url(path)), headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception('API error ${res.statusCode}: ${res.body}');
    }
  }

  // ─── Auth ──────────────────────────────────────────────────────────────

  Future<void> signInWithDiscord() async {
    final url = Uri.parse(_url('/v1/auth/discord'));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> signInWithGitHub() async {
    final url = Uri.parse(_url('/v1/auth/github'));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Called when the app receives the deep link callback with a one-time code.
  Future<void> exchangeCode(String code) async {
    final res = await _post('/v1/auth/exchange', {'code': code});
    _token = res['token'] as String;
    _userId = res['userId'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userIdKey, _userId!);
    _authController.add(true);
  }

  Future<void> signOut() async {
    try {
      await _post('/v1/auth/logout');
    } catch (_) {
      // Best-effort server-side cleanup
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    _token = null;
    _userId = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    _authController.add(false);
  }

  // ─── Profiles ──────────────────────────────────────────────────────────

  Future<ProfileModel?> fetchProfile(String userId) async {
    try {
      final res = await _get('/v1/profile');
      return ProfileModel.fromMap(res);
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiService] fetchProfile failed: $e');
      return null;
    }
  }

  Future<void> updateProfile(
    String userId,
    Map<String, dynamic> patch,
  ) async {
    await _patch('/v1/profile', patch);
  }

  Future<ProfileModel?> fetchPartnerProfile() async {
    try {
      final res = await _get('/v1/profile/partner');
      return ProfileModel.fromMap(res);
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiService] fetchPartnerProfile failed: $e');
      return null;
    }
  }

  // ─── Pairings ──────────────────────────────────────────────────────────

  Future<PairingModel?> fetchMyPairing(String userId) async {
    try {
      final res = await _http.get(
        Uri.parse(_url('/v1/pairings')),
        headers: _headers,
      );
      if (res.statusCode >= 400) return null;
      final decoded = jsonDecode(res.body);
      if (decoded == null) return null;
      return PairingModel.fromMap(decoded as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiService] fetchMyPairing failed: $e');
      return null;
    }
  }

  Future<PairingModel> createPairingInvite(String userId) async {
    final res = await _post('/v1/pairings/invite');
    return PairingModel.fromMap(res);
  }

  Future<PairingModel> claimPairingByCode(String userId, String code) async {
    final res = await _post('/v1/pairings/claim', {'code': code});
    return PairingModel.fromMap(res);
  }

  Future<void> deletePairing(String pairingId) async {
    await _delete('/v1/pairings/$pairingId');
  }

  // ─── Alarms ────────────────────────────────────────────────────────────

  Future<List<AlarmModel>> fetchAlarmsFor(String userId) async {
    final res = await _getList('/v1/alarms');
    return res
        .map((e) => AlarmModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AlarmModel> insertAlarm({
    required String ownerId,
    required String createdBy,
    required String label,
    required String message,
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
    required bool isActive,
    required bool vibrate,
    required int snoozeMinutes,
    String soundName = 'default',
  }) async {
    final res = await _post('/v1/alarms', {
      'owner_id': ownerId,
      'label': label,
      'message': message,
      'hour': hour,
      'minute': minute,
      'days_of_week': daysOfWeek,
      'is_active': isActive,
      'vibrate': vibrate,
      'sound_name': soundName,
      'snooze_minutes': snoozeMinutes,
    });
    return AlarmModel.fromMap(res);
  }

  Future<AlarmModel> updateAlarm(
    String alarmId,
    Map<String, dynamic> patch,
  ) async {
    final res = await _patch('/v1/alarms/$alarmId', patch);
    return AlarmModel.fromMap(res);
  }

  Future<void> deleteAlarm(String alarmId) async {
    await _delete('/v1/alarms/$alarmId');
  }

  // ─── Alarm Logs ────────────────────────────────────────────────────────

  Future<AlarmLogModel> insertAlarmLog({
    required String alarmId,
    required String action,
    String? reaction,
    String? actedBy,
  }) async {
    final payload = <String, dynamic>{
      'alarm_id': alarmId,
      'action': action,
    };
    if (reaction != null) payload['reaction'] = reaction;
    if (actedBy != null) payload['acted_by'] = actedBy;
    final res = await _post('/v1/alarms/logs', payload);
    return AlarmLogModel.fromMap(res);
  }

  Future<List<AlarmLogModel>> fetchLogsForPair(
    List<String> alarmIds, {
    int limit = 100,
  }) async {
    if (alarmIds.isEmpty) return const <AlarmLogModel>[];
    final ids = alarmIds.join(',');
    final res = await _getList('/v1/alarms/logs?alarm_ids=$ids&limit=$limit');
    return res
        .map((e) => AlarmLogModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AlarmLogModel> updateAlarmLogReaction(
    String logId,
    String reaction,
  ) async {
    final res = await _patch('/v1/alarms/logs/$logId', {
      'reaction': reaction,
    });
    return AlarmLogModel.fromMap(res);
  }

  // ─── Nudges ────────────────────────────────────────────────────────────

  Future<void> sendNudge(String toUserId) async {
    await _post('/v1/nudges', {'to_user_id': toUserId});
  }

  Future<List<NudgeModel>> fetchNudges({int limit = 50}) async {
    final res = await _getList('/v1/nudges?limit=$limit');
    return res
        .map((e) => NudgeModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> markNudgeRead(String nudgeId) async {
    await _patch('/v1/nudges/$nudgeId/read', {});
  }

  // ─── Announcements ─────────────────────────────────────────────────────

  Future<List<AnnouncementModel>> fetchAnnouncements({int limit = 20}) async {
    final res = await _getList('/v1/announcements?limit=$limit');
    return res
        .map((e) => AnnouncementModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ─── WebSocket (Realtime Events) ───────────────────────────────────────

  Timer? _wsReconnectTimer;
  bool _wsShouldReconnect = false;
  StreamController<NudgeModel>? _nudgeController;
  StreamController<AnnouncementModel>? _announcementController;
  Stream<NudgeModel>? _nudgeBroadcast;
  Stream<AnnouncementModel>? _announcementBroadcast;

  /// Broadcast stream of realtime nudge events from the shared WebSocket.
  Stream<NudgeModel> get nudgeStream {
    _ensureWsConnected();
    return _nudgeBroadcast!;
  }

  /// Broadcast stream of realtime announcement events from the shared WebSocket.
  Stream<AnnouncementModel> get announcementStream {
    _ensureWsConnected();
    return _announcementBroadcast!;
  }

  /// Ensure a single shared WebSocket connection exists.
  /// Subsequent calls are no-ops if already connected.
  void _ensureWsConnected() {
    if (_wsShouldReconnect && _nudgeController != null) return;
    _wsChannel?.sink.close();
    _wsReconnectTimer?.cancel();
    _nudgeController?.close();
    _announcementController?.close();
    _wsShouldReconnect = true;
    _nudgeController = StreamController<NudgeModel>.broadcast();
    _announcementController = StreamController<AnnouncementModel>.broadcast();
    _nudgeBroadcast = _nudgeController!.stream;
    _announcementBroadcast = _announcementController!.stream;
    _wsConnect();
  }

  /// Connect to the Worker's WebSocket endpoint for realtime nudge + announcement delivery.
  /// Automatically reconnects on disconnect (3s backoff).
  @Deprecated('Use nudgeStream / announcementStream instead')
  Stream<NudgeModel> connectNudgeStream() {
    _ensureWsConnected();
    return _nudgeBroadcast!;
  }

  void _wsConnect() {
    if (!_wsShouldReconnect || _token == null) return;

    final wsUrl = ApiConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse('$wsUrl/v1/events?token=$_token');
    _wsChannel = WebSocketChannel.connect(uri);

    _wsChannel!.stream.listen(
      (event) {
        if (event is! String) return;
        try {
          final msg = jsonDecode(event) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          if (type == 'nudge') {
            final nudge =
                NudgeModel.fromMap(msg['data'] as Map<String, dynamic>);
            _nudgeController?.add(nudge);
          } else if (type == 'announcement') {
            final announcement = AnnouncementModel.fromMap(
                msg['data'] as Map<String, dynamic>);
            _announcementController?.add(announcement);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[ApiService] WS parse error: $e');
        }
      },
      onError: (_) => _wsScheduleReconnect(),
      onDone: () => _wsScheduleReconnect(),
    );
  }

  void _wsScheduleReconnect() {
    if (!_wsShouldReconnect) return;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 3), _wsConnect);
  }

  /// Disconnect the WebSocket permanently (no reconnect).
  void disconnectEvents() {
    _wsShouldReconnect = false;
    _wsReconnectTimer?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _nudgeController?.close();
    _nudgeController = null;
    _announcementController?.close();
    _announcementController = null;
    _nudgeBroadcast = null;
    _announcementBroadcast = null;
  }
}
