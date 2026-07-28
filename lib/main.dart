import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/pairing_provider.dart';
import 'screens/alarm_ring_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pair_screen.dart';
import 'services/alarm_service.dart';
import 'services/battery_service.dart';
import 'services/fcm_service.dart';
import 'services/supabase_service.dart';
import 'supabase_config.dart';
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

  // Load environment from .env before initializing Supabase.
  await dotenv.load(fileName: '.env');
  await SupabaseService.initialize();

  tzdata.initializeTimeZones();
  try {
    final tzName = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('UTC'));
  }

  await AlarmService.instance.initialize();
  Alarm.ringStream.stream.listen(_onNativeAlarmFire);
  await FcmService.instance.initialize();
  BatteryService.instance.initialize();

  runApp(const ProviderScope(child: SyncApp()));
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
  const SyncApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  ConsumerState<SyncApp> createState() => _SyncAppState();
}

class _SyncAppState extends ConsumerState<SyncApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _refresh,
      onPause: _persistBattery,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final tzName = ref.read(deviceTimezoneProvider);
    final userId = SupabaseService.instance.currentUserId;
    if (userId == null) return;
    try {
      await SupabaseService.instance.updateProfile(
        userId,
        {'timezone': tzName},
      );
      ref.read(deviceTimezoneProvider.notifier).state = tzName;
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
          // OAuth deep-links are handled by supabase_flutter's built-in
          // route handling combined with the AndroidManifest scheme filter.
          // We intentionally do not register onGenerateRoute / named
          // routes — all navigation uses Navigator.push(MaterialPageRoute).
          home: const _AuthGate(),
        );
      },
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

    if (pairing.isLoading && pairing.pairing == null) {
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
