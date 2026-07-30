import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/announcement_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Streams announcements: fetches stored announcements from the API on startup,
/// then listens for live announcements via the shared WebSocket in ApiService.
final announcementProvider =
    StreamNotifierProvider<AnnouncementNotifier, List<AnnouncementModel>>(
  AnnouncementNotifier.new,
);

class AnnouncementNotifier extends StreamNotifier<List<AnnouncementModel>> {
  final List<AnnouncementModel> _announcements = [];
  final Set<String> _seenIds = {};
  StreamSubscription<AnnouncementModel>? _wsSub;

  @override
  Stream<List<AnnouncementModel>> build() async* {
    final auth = ref.watch(authProvider);
    if (auth.userId == null) return;

    // Fetch stored announcements from API
    try {
      final stored = await ApiService.instance.fetchAnnouncements();
      for (final a in stored) {
        if (_seenIds.add(a.id.toString())) {
          _announcements.add(a);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AnnouncementProvider] fetchAnnouncements failed: $e');
      }
    }

    yield List.unmodifiable(_announcements);

    // Listen for live announcements via shared WebSocket
    final controller = StreamController<List<AnnouncementModel>>();

    _wsSub = ApiService.instance.announcementStream.listen(
      (announcement) {
        if (!_seenIds.add(announcement.id.toString())) return;
        _announcements.insert(0, announcement);
        // Keep at most 50
        if (_announcements.length > 50) {
          final removed = _announcements.removeLast();
          _seenIds.remove(removed.id.toString());
        }
        controller.add(List.unmodifiable(_announcements));
      },
      onError: (_) {},
      onDone: () => controller.close(),
    );

    ref.onDispose(() {
      _wsSub?.cancel();
      _wsSub = null;
    });

    yield* controller.stream;
  }
}
