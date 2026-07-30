import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_model.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';

/// Auth state tracked by Riverpod.
@immutable
class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final ProfileModel? profile;
  final String? error;

  const AuthState({
    required this.isAuthenticated,
    required this.userId,
    required this.profile,
    required this.error,
  });

  const AuthState.initial()
      : isAuthenticated = false,
        userId = null,
        profile = null,
        error = null;

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    ProfileModel? profile,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      profile: profile ?? this.profile,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Riverpod notifier that mirrors Worker session auth state.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._service) : super(const AuthState.initial()) {
    _bootstrap();
    _service.authState.listen(_onAuthEvent);
  }

  final ApiService _service;

  void _bootstrap() {
    if (_service.isAuthenticated) {
      state = state.copyWith(
        isAuthenticated: true,
        userId: _service.currentUserId,
      );
      _loadProfile(_service.currentUserId!);
    }
  }

  Future<void> _onAuthEvent(bool authenticated) async {
    if (authenticated && _service.currentUserId != null) {
      state = state.copyWith(
        isAuthenticated: true,
        userId: _service.currentUserId,
        clearError: true,
      );
      await _loadProfile(_service.currentUserId!);
    } else {
      state = const AuthState.initial();
    }
  }

  Future<void> _loadProfile(String userId) async {
    try {
      // Wait briefly if the Postgres trigger hasn't fired yet.
      var profile = await _service.fetchProfile(userId);
      var attempts = 0;
      while (profile == null && attempts < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        profile = await _service.fetchProfile(userId);
        attempts += 1;
      }
      if (profile != null) {
        state = state.copyWith(profile: profile);
        FcmService.instance.refreshFcmToken();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthNotifier] load profile: $e');
    }
  }

  Future<void> signInWithDiscord() async {
    try {
      await _service.signInWithDiscord();
    } catch (e) {
      state = state.copyWith(error: _readableError(e));
    }
  }

  Future<void> signInWithGitHub() async {
    try {
      await _service.signInWithGitHub();
    } catch (e) {
      state = state.copyWith(error: _readableError(e));
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
    state = const AuthState.initial();
  }

  Future<void> refreshProfile() async {
    final id = state.userId;
    if (id == null) return;
    final profile = await _service.fetchProfile(id);
    if (profile != null) state = state.copyWith(profile: profile);
  }

  /// Handle deep link code exchange after OAuth callback.
  Future<void> handleAuthCode(String code) async {
    try {
      await _service.exchangeCode(code);
    } catch (e) {
      state = state.copyWith(error: _readableError(e));
    }
  }

  String _readableError(Object e) {
    final msg = e.toString();
    if (msg.contains('No network connection')) {
      return 'No network connection.';
    }
    return 'Sign-in failed. Please try again.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ApiService.instance);
});
