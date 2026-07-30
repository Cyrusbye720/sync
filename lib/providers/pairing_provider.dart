import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pairing_model.dart';
import '../models/profile_model.dart';
import '../services/api_service.dart';

/// Active pairing for the current user (or null if unpaired).
class PairingState {
  final PairingModel? pairing; // raw row (user_a's view)
  final ProfileModel? partner;
  final bool isLoading;
  final String? error;

  const PairingState({
    required this.pairing,
    required this.partner,
    required this.isLoading,
    required this.error,
  });

  const PairingState.initial()
      : pairing = null,
        partner = null,
        isLoading = true,
        error = null;

  PairingState copyWith({
    PairingModel? pairing,
    ProfileModel? partner,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearPair = false,
    bool clearPartner = false,
  }) {
    return PairingState(
      pairing: clearPair ? null : (pairing ?? this.pairing),
      partner: clearPartner ? null : (partner ?? this.partner),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PairingNotifier extends StateNotifier<PairingState> {
  PairingNotifier(this._service) : super(const PairingState.initial()) {
    _bootstrap();
    _service.authState.listen((_) => _bootstrap());
  }

  final ApiService _service;
  Timer? _pollTimer;

  Future<void> _bootstrap() async {
    final me = _service.currentUserId;
    if (me == null) {
      state = const PairingState.initial();
      _pollTimer?.cancel();
      return;
    }
    // 1. Load cached state instantly from disk (0ms)
    await _loadCache();

    // 2. Fetch fresh state from backend
    await _refresh();

    // Poll every 15 seconds for pairing changes
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refresh(),
    );
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pairJson = prefs.getString('cache_pairing');
      final partnerJson = prefs.getString('cache_partner');

      PairingModel? cachedPair;
      ProfileModel? cachedPartner;

      if (pairJson != null && pairJson.isNotEmpty) {
        cachedPair =
            PairingModel.fromMap(jsonDecode(pairJson) as Map<String, dynamic>);
      }
      if (partnerJson != null && partnerJson.isNotEmpty) {
        cachedPartner = ProfileModel.fromMap(
            jsonDecode(partnerJson) as Map<String, dynamic>);
      }

      if (cachedPair != null) {
        state = state.copyWith(
          pairing: cachedPair,
          partner: cachedPartner,
          isLoading: false,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Pairing]_loadCache error: $e');
    }
  }

  Future<void> _saveCache(PairingModel? pairing, ProfileModel? partner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pairing == null) {
        await prefs.remove('cache_pairing');
        await prefs.remove('cache_partner');
      } else {
        await prefs.setString('cache_pairing', jsonEncode(pairing.toMap()));
        if (partner != null) {
          await prefs.setString('cache_partner', jsonEncode(partner.toMap()));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Pairing]_saveCache error: $e');
    }
  }

  Future<void> _refresh() async {
    try {
      final me = _service.currentUserId;
      if (me == null) return;
      final pairing = await _service.fetchMyPairing(me);
      if (pairing == null) {
        state = state.copyWith(
          clearPair: true,
          clearPartner: true,
          isLoading: false,
        );
        await _saveCache(null, null);
        return;
      }
      ProfileModel? partner;
      if (pairing.userB != null && pairing.isAccepted) {
        partner = await _service.fetchPartnerProfile();
      }
      final effectivePartner = partner ?? state.partner;
      state = state.copyWith(
        pairing: pairing,
        partner: effectivePartner,
        isLoading: false,
        clearError: true,
      );
      await _saveCache(pairing, effectivePartner);
    } catch (e) {
      // Offline / network failure: keep cached pairing state intact!
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load pairing.',
      );
      if (kDebugMode) debugPrint('[Pairing]_refresh error: $e');
    }
  }

  /// Generates a fresh 6-digit invite code by calling the RPC.
  /// Returns the visible code on success, null on failure.
  Future<String?> generateInviteCode() async {
    try {
      final me = _service.currentUserId!;
      final pairing = await _service.createPairingInvite(me);
      state = state.copyWith(pairing: pairing, clearError: true);
      await _refresh();
      return pairing.inviteCode;
    } catch (e) {
      state = state.copyWith(error: 'Could not generate code.');
      if (kDebugMode) debugPrint('[Pairing]_generate $e');
      return null;
    }
  }

  Future<bool> acceptInvite(String code) async {
    try {
      final me = _service.currentUserId!;
      await _service.claimPairingByCode(me, code);
      await _refresh();
      return state.pairing?.isAccepted == true;
    } catch (e) {
      state = state.copyWith(error: 'Invalid code.');
      return false;
    }
  }

  Future<void> unpair() async {
    final pair = state.pairing;
    if (pair == null) return;
    await _service.deletePairing(pair.id);
    state = state.copyWith(clearPair: true, clearPartner: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier(ApiService.instance);
});

/// Helper: derive the partner user's id from auth + pairing state. Returns
/// null when the user is not yet paired.
String? currentPartnerId(WidgetRef ref) {
  final profile = ref.read(pairingProvider).partner;
  return profile?.id;
}
