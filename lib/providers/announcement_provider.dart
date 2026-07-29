import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api_config.dart';
import '../models/announcement_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Streams announcements via WebSocket and stores them in-memory.
/// Also fetches announcements from the API on connection.
final announcementProvider =
    StreamNotifierProvider<AnnouncementNotifier, List<AnnouncementModel>>(
  AnnouncementNotifier.new,
);

class AnnouncementNotifier extends StreamNotifier<List<AnnouncementModel>> {
  WebSocketChannel? _wsChannel;
  final List<AnnouncementModel> _announcements = [];

  @override
  Stream<List<AnnouncementModel>> build() async* {
    final auth = ref.watch(authProvider);
    if (auth.userId == null) return;

    // Fetch stored announcements from API
    try {
      final stored = await ApiService.instance.fetchAnnouncements();
      _announcements.addAll(stored);
    } catch (_) {}

    yield List.unmodifiable(_announcements);

    // Listen for live announcements via WebSocket
    final controller = StreamController<List<AnnouncementModel>>();

    final wsUrl = ApiConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final token = ApiService.instance.currentToken;
    if (token == null) return;

    final uri = Uri.parse('$wsUrl/v1/events?token=$token');
    _wsChannel = WebSocketChannel.connect(uri);

    _wsChannel!.stream.listen(
      (event) {
        if (event is! String) return;
        try {
          final msg = jsonDecode(event) as Map<String, dynamic>;
          if (msg['type'] == 'announcement') {
            final data = msg['data'] as Map<String, dynamic>;
            final announcement = AnnouncementModel.fromMap(data);
            _announcements.insert(0, announcement);
            // Keep at most 50
            if (_announcements.length > 50) {
              _announcements.removeRange(0, _announcements.length - 50);
            }
            controller.add(List.unmodifiable(_announcements));
          }
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {
        controller.close();
      },
    );

    yield* controller.stream;

    ref.onDispose(() {
      _wsChannel?.sink.close();
      _wsChannel = null;
    });
  }
}
