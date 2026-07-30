import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api_config.dart';
import 'models/nudge_model.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/pairing_provider.dart';
import 'screens/alarm_ring_screen.dart';
import 'screens/home_screen.dart';
import 'screens/incoming_nudge_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pair_screen.dart';
import 'services/alarm_service.dart';
import 'services/api_service.dart';
import 'services/background_service.dart';
import 'services/battery_service.dart';
import 'services/fcm_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.black,
      systemNavigationBarColor: AppColors.black,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  Object? startupError;
  try {
    await _initializeAppServices();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
    startupError = error;
  }

  runApp(ProviderScope(child: SyncApp(startupError: startupError)));
}

Future<void> _initializeAppServices() async {
  ApiConfig.validate();
  await ApiService.initialize();

  tzdata.initializeTimeZones();
  String detectedTz = 'UTC';
  try {
    final dynamic tzObj = await FlutterTimezone.getLocalTimezone();
    final String tzName = tzObj is String ? tzObj : (tzObj.name ?? tzObj.toString());
    detectedTz = tzName;
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('UTC'));
  }

  // These are device integrations rather than prerequisites for rendering
  // the login screen. A platform-specific failure must not strand users on
  // Android's native launch screen in a release build.
  try {
    await AlarmService.instance.initialize();
    await AlarmService.instance.requestBatteryOptimizationExemption();
  } catch (_) {
    // The app can still render without local alarm setup for this launch.
  }
  Alarm.ringStream.stream.listen(_onNativeAlarmFire);
  try {
    BatteryService.instance.initialize();
  } catch (_) {
    // Battery reporting is best-effort and not part of app startup.
  }

  // FCM must be initialised after ApiService (we need the current user
  // id to save the device token on profiles.fcm_token) but before
  // runApp so the root widget can subscribe to [FcmService.syncEvents].
  await FcmService.instance.initialize();

  // Start foreground service to keep the app alive in background.
  try {
    await BackgroundService.instance.start();
  } catch (_) {
    // Background service is best-effort; app works without it.
  }
}

void _onNativeAlarmFire(AlarmSettings settings) {
  final payload = AlarmRingPayload.fromAlarmSettings(settings);
  final navigatorKey = SyncApp.navigatorKey;
  if (payload != null && navigatorKey.currentState != null) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => AlarmRingScreen(initial: payload)),
    );
  }
}

class SyncApp extends ConsumerStatefulWidget {
  const SyncApp({super.key, this.startupError});

  final Object? startupError;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  ConsumerState<SyncApp> createState() => _SyncAppState();
}

class _SyncAppState extends ConsumerState<SyncApp> {
  AppLifecycleListener? _lifecycle;
  static const _channel = MethodChannel('syncalarm/deeplink');
  StreamSubscription<Map<String, dynamic>>? _fcmSub;
  @override
  void initState() {
    super.initState();
    if (widget.startupError != null) return;

    _lifecycle = AppLifecycleListener(
      onResume: _refresh,
      onPause: _persistBattery,
    );

    // Listen for deep link callbacks (OAuth code exchange)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'handleAuthCallback') {
        final code = call.arguments as String?;
        if (code != null && code.isNotEmpty) {
          await ref.read(authProvider.notifier).handleAuthCode(code);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      await FcmService.instance.replayInitialMessage();
    });

    // Subscribe to FCM foreground messages for nudge/announcement push.
    _fcmSub = FcmService.instance.syncEvents.listen(_handleFcmEvent);
  }

  void _handleFcmEvent(Map<String, dynamic> data) {
    final navContext = SyncApp.navigatorKey.currentContext;
    if (navContext == null) return;

    final type = data['type'] as String?;
    if (type == 'nudge') {
      try {
        // Try full parse first (WebSocket path sends complete nudge data).
        final nudge = NudgeModel.fromMap(data);
        IncomingNudgeScreen.show(navContext, nudge);
      } catch (_) {
        // FCM data payload may have different field names — try FCM-specific parser.
        final parsed = FcmService.parseNudgeFromFcmData(data);
        if (parsed != null) {
          try {
            final nudge = NudgeModel.fromMap(parsed);
            IncomingNudgeScreen.show(navContext, nudge);
          } catch (_) {}
        }
      }
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Use the actual local timezone, not the provider which may be stale.
    final tzName = tz.local.name;
    ref.read(deviceTimezoneProvider.notifier).state = tzName;
    final userId = ApiService.instance.currentUserId;
    if (userId == null) return;
    try {
      await ApiService.instance.updateProfile(
        userId,
        {'timezone': tzName},
      );
    } catch (_) {}
    ref.read(batteryProvider.notifier).refresh();
  }

  Future<void> _persistBattery() async {
    await ref.read(batteryProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: SyncApp.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'SYNC',
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: widget.startupError == null
              ? const _AuthGate()
              : const _StartupFailure(),
        );
      },
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SYNC', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              const Text(
                'This build is not configured correctly. Please contact the '
                'app publisher.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    return _Routing(auth: auth);
  }
}

class _Routing extends ConsumerWidget {
  const _Routing({required this.auth});
  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing = ref.watch(pairingProvider);

    if (pairing.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.white),
        ),
      );
    }

    if (pairing.pairing == null || !pairing.pairing!.isAccepted) {
      return const PairScreen();
    }

    return const HomeScreen();
  }
}
