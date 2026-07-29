import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nudge_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Watch the current user's incoming nudges via Worker WebSocket.
/// Re-emits whenever a nudge event arrives over the WebSocket.
/// Keeps at most 50 recent nudges to prevent unbounded memory growth.
final nudgeStreamProvider = StreamProvider<List<NudgeModel>>((ref) {
  final auth = ref.watch(authProvider);
  final userId = auth.userId;
  if (userId == null) {
    return const Stream<List<NudgeModel>>.empty();
  }

  final nudges = <NudgeModel>[];
  return ApiService.instance.connectNudgeStream().map((nudge) {
    nudges.add(nudge);
    // Keep only the most recent 50 nudges
    if (nudges.length > 50) {
      nudges.removeRange(0, nudges.length - 50);
    }
    return List<NudgeModel>.unmodifiable(nudges);
  });
});