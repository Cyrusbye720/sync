import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nudge_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Watch the current user's incoming nudges.
/// Seeds from GET /v1/nudges on startup, then merges realtime WebSocket events.
/// Keeps at most 50 recent nudges to prevent unbounded memory growth.
final nudgeStreamProvider = StreamProvider<List<NudgeModel>>((ref) {
  final auth = ref.watch(authProvider);
  final userId = auth.userId;
  if (userId == null) {
    return const Stream<List<NudgeModel>>.empty();
  }

  final controller = StreamController<List<NudgeModel>>();
  final nudges = <NudgeModel>[];
  final seenIds = <String>{};

  void addNudge(NudgeModel nudge) {
    if (seenIds.contains(nudge.id)) return;
    seenIds.add(nudge.id);
    nudges.insert(0, nudge);
    if (nudges.length > 50) {
      final removed = nudges.removeLast();
      seenIds.remove(removed.id);
    }
    controller.add(List<NudgeModel>.unmodifiable(nudges));
  }

  // Fetch historical nudges first
  ApiService.instance.fetchNudges().then((history) {
    for (final nudge in history) {
      if (!seenIds.contains(nudge.id)) {
        seenIds.add(nudge.id);
        nudges.add(nudge);
      }
    }
    if (nudges.length > 50) {
      for (final removed in nudges.sublist(50)) {
        seenIds.remove(removed.id);
      }
      nudges.removeRange(50, nudges.length);
    }
    controller.add(List<NudgeModel>.unmodifiable(nudges));
  }).catchError((Object e) {
    if (kDebugMode) debugPrint('[NudgeProvider] fetchNudges failed: $e');
    // Still emit empty list so UI isn't stuck loading
    controller.add(List<NudgeModel>.unmodifiable(nudges));
  });

  // Then listen for realtime nudges via shared WebSocket
  final sub = ApiService.instance.nudgeStream.listen(
    addNudge,
    onError: (_) {},
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});