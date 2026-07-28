import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/alarm_log_model.dart';
import '../models/alarm_model.dart';
import '../models/pairing_model.dart';
import '../models/profile_model.dart';
import '../supabase_config.dart';

/// Thin wrapper around the Supabase client.
///
/// All Supabase calls in the rest of the codebase should go through this
/// service so we have a single place to handle errors and stream cleanup.
class SupabaseService {
  SupabaseService._(this._client);

  static SupabaseService? _instance;
  final SupabaseClient _client;

  SupabaseClient get client => _client;

  static Future<SupabaseService> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _instance = SupabaseService._(Supabase.instance.client);
    return _instance!;
  }

  static SupabaseService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'SupabaseService.initialize() must be called before use.',
      );
    }
    return inst;
  }

  // ---------------- Auth helpers ----------------

  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;

  Stream<AuthState> get authState => _client.auth.onAuthStateChange;

  Future<void> signInWithDiscord() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.discord,
      redirectTo: SupabaseConfig.oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithGitHub() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: SupabaseConfig.oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ---------------- Profiles ----------------

  Future<ProfileModel?> fetchProfile(String userId) async {
    final res =
        await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (res == null) return null;
    return ProfileModel.fromMap(res);
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> patch) async {
    await _client.from('profiles').update(patch).eq('id', userId);
  }

  Stream<List<ProfileModel>> watchProfilesByIds(List<String> ids) {
    if (ids.isEmpty) return const Stream.empty();
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .inFilter('id', ids)
        .map((rows) => rows.map(ProfileModel.fromMap).toList(growable: false));
  }

  Future<ProfileModel?> findProfileById(String id) async {
    final res =
        await _client.from('profiles').select().eq('id', id).maybeSingle();
    if (res == null) return null;
    return ProfileModel.fromMap(res);
  }

  // ---------------- Pairings ----------------

  Future<PairingModel?> fetchMyPairing(String userId) async {
    final res = await _client
        .from('pairings')
        .select()
        .or('user_a.eq.$userId,user_b.eq.$userId')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res == null) return null;
    return PairingModel.fromMap(res);
  }

  /// Create a new pending invite via the server-side RPC. The function
  /// returns the pairing row whose `invite_code` is filled in.
  Future<PairingModel> createPairingInvite(String userId) async {
    final res = await _client.rpc(
      'create_pairing_invite',
      params: {'p_inviter': userId},
    );
    return PairingModel.fromMap(res as Map<String, dynamic>);
  }

  /// Atomically claim a pending invite by code. RPC sets `user_b` to the
  /// caller and flips status to `accepted`.
  Future<PairingModel> claimPairingByCode(String userId, String code) async {
    final res = await _client.rpc('claim_pairing_by_code', params: {
      'p_user_id': userId,
      'p_code': code,
    });
    return PairingModel.fromMap(res as Map<String, dynamic>);
  }

  Stream<List<PairingModel>> watchMyPairings(String userId) {
    return _client
        .from('pairings')
        .stream(primaryKey: ['id'])
        .or('user_a.eq.$userId,user_b.eq.$userId')
        .map((rows) =>
            rows.map(PairingModel.fromMap).toList(growable: false));
  }

  Future<void> deletePairing(String pairingId) async {
    await _client.from('pairings').delete().eq('id', pairingId);
  }

  // ---------------- Alarms ----------------

  Future<List<AlarmModel>> fetchAlarmsFor(String userId) async {
    final res = await _client
        .from('alarms')
        .select()
        .or('owner_id.eq.$userId,created_by.eq.$userId')
        .order('hour')
        .order('minute');
    return (res as List<dynamic>)
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
    final res = await _client.from('alarms').insert({
      'owner_id': ownerId,
      'created_by': createdBy,
      'label': label,
      'message': message,
      'hour': hour,
      'minute': minute,
      'days_of_week': daysOfWeek,
      'is_active': isActive,
      'vibrate': vibrate,
      'sound_name': soundName,
      'snooze_minutes': snoozeMinutes,
    }).select().single();
    return AlarmModel.fromMap(res);
  }

  Future<AlarmModel> updateAlarm(
      String alarmId, Map<String, dynamic> patch) async {
    final res = await _client
        .from('alarms')
        .update(patch)
        .eq('id', alarmId)
        .select()
        .single();
    return AlarmModel.fromMap(res);
  }

  Future<void> deleteAlarm(String alarmId) async {
    await _client.from('alarms').delete().eq('id', alarmId);
  }

  Stream<List<AlarmModel>> watchAlarmsFor(String userId) {
    return _client
        .from('alarms')
        .stream(primaryKey: ['id'])
        .or('owner_id.eq.$userId,created_by.eq.$userId')
        .map((rows) =>
            rows.map(AlarmModel.fromMap).toList(growable: false));
  }

  // ---------------- Alarm logs ----------------

  Future<AlarmLogModel> insertAlarmLog({
    required String alarmId,
    required String action,
    String? reaction,
    String? actedBy,
  }) async {
    final res = await _client.from('alarm_logs').insert({
      'alarm_id': alarmId,
      'action': action,
      'reaction': reaction,
      'acted_by': actedBy,
    }).select().single();
    return AlarmLogModel.fromMap(res);
  }

  Future<List<AlarmLogModel>> fetchLogsForAlarm(String alarmId,
      {int limit = 50}) async {
    final res = await _client
        .from('alarm_logs')
        .select()
        .eq('alarm_id', alarmId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List<dynamic>)
        .map((e) => AlarmLogModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<AlarmLogModel>> fetchLogsForPair(List<String> alarmIds,
      {int limit = 100}) async {
    if (alarmIds.isEmpty) return const <AlarmLogModel>[];
    final res = await _client
        .from('alarm_logs')
        .select()
        .inFilter('alarm_id', alarmIds)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List<dynamic>)
        .map((e) => AlarmLogModel.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AlarmLogModel> updateAlarmLogReaction(
      String logId, String reaction) async {
    final res = await _client
        .from('alarm_logs')
        .update({'reaction': reaction})
        .eq('id', logId)
        .select()
        .single();
    return AlarmLogModel.fromMap(res);
  }
}
