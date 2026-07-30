import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm_model.dart';
import '../models/announcement_model.dart';
import '../models/nudge_model.dart';
import '../models/profile_model.dart';
import '../providers/alarm_provider.dart';
import '../providers/announcement_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/nudge_provider.dart';
import '../providers/pairing_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alarm_card.dart';
import '../widgets/monochrome_button.dart';
import '../widgets/partner_header.dart';
import '../widgets/stats_card.dart';
import 'alarm_form_screen.dart';
import 'incoming_nudge_screen.dart';
import 'pair_screen.dart';
import 'reactions_screen.dart';

/// Home screen — partner header, alarm tabs, stats, reactions, and NUDGE.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(alarmStatsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _nudge() async {
    final partner = ref.read(pairingProvider).partner;
    if (partner == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Worker handles insert + FCM push + WebSocket fan-out in one call.
      await ApiService.instance.sendNudge(partner.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Nudge sent. They will see it now.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nudge failed: $e')),
      );
    }
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: AppColors.white, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
        ),
        title: const Text(
          'UNPAIR?',
          style: TextStyle(color: AppColors.white, fontFamily: 'RobotoMono'),
        ),
        content: const Text(
          'Existing alarms will remain, but live sync stops.',
          style: TextStyle(color: AppColors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL',
                style: TextStyle(color: AppColors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('UNPAIR',
                style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(pairingProvider.notifier).unpair();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const PairScreen()),
        (_) => false,
      );
    }
  }

  void _openAlarmForm({required String ownerId, AlarmModel? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlarmFormScreen(ownerId: ownerId, existing: existing),
      ),
    );
  }

  void _maybeShowIncomingNudge(List<NudgeModel> list) {
    for (final n in list) {
      if (n.readAt != null) continue;
      IncomingNudgeScreen.show(context, n);
    }
  }

  /// Compute the current time as observed in the partner's timezone.
  DateTime _partnerTime(ProfileModel partner) {
    try {
      final loc = tz.getLocation(partner.timezone);
      return tz.TZDateTime.now(loc);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<NudgeModel>>>(nudgeStreamProvider, (_, next) {
      next.whenOrNull(data: _maybeShowIncomingNudge);
    });

    final auth = ref.watch(authProvider);
    final pairing = ref.watch(pairingProvider);
    final alarms = ref.watch(alarmListProvider);
    final stats = ref.watch(alarmStatsProvider);

    final me = auth.userId;
    final partner = pairing.partner;
    final partnerId = me != null && pairing.pairing != null
        ? pairing.pairing!.partnerId(me)
        : null;

    if (partner == null || pairing.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.white)),
      );
    }

    final partnerTime = _partnerTime(partner);
    final myAlarms =
        alarms.where((a) => a.ownerId == me).toList(growable: false);
    final theirAlarms =
        alarms.where((a) => a.createdBy == me).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text('SYNC',
            style: TextStyle(fontSize: 16.sp, letterSpacing: 4)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: AppColors.white),
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Column(
            children: [
              PartnerHeader(
                partner: partner,
                isAwake: partner.isAwake,
                localTime: partnerTime,
                batteryPercent: partner.batteryPercent,
                unpair: _confirmUnpair,
              ),
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: 'YOU (${myAlarms.length})'),
                  Tab(text: 'THEM (${theirAlarms.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (ref.watch(announcementProvider).valueOrNull?.isNotEmpty == true)
            _AnnouncementBanner(
              announcement: ref.watch(announcementProvider).value!.first,
            ),
          // Large NUDGE button row (spec 7.B).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: MonochromeButton(
              label: 'WAKE THEM',
              icon: Icons.notifications_active,
              variant: MonoVariant.primary,
              onPressed: partnerId == null ? null : _nudge,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _AlarmList(
                  alarms: myAlarms,
                  isMine: true,
                  onAdd: me == null ? null : () => _openAlarmForm(ownerId: me),
                  onToggle: (a, v) =>
                      ref.read(alarmListProvider.notifier).toggle(a.id, v),
                  onEdit: (a) => _openAlarmForm(ownerId: a.ownerId, existing: a),
                  onDelete: (a) =>
                      ref.read(alarmListProvider.notifier).delete(a.id),
                ),
                _AlarmList(
                  alarms: theirAlarms,
                  isMine: false,
                  creatorName: auth.profile?.username,
                  onAdd: partnerId == null
                      ? null
                      : () => _openAlarmForm(ownerId: partnerId),
                  onToggle: (a, v) =>
                      ref.read(alarmListProvider.notifier).toggle(a.id, v),
                  onEdit: (a) => _openAlarmForm(ownerId: a.ownerId, existing: a),
                  onDelete: (a) =>
                      ref.read(alarmListProvider.notifier).delete(a.id),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(stats: stats),
    );
  }
}

class _AlarmList extends ConsumerWidget {
  const _AlarmList({
    required this.alarms,
    required this.isMine,
    required this.onAdd,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.creatorName,
  });

  final List<AlarmModel> alarms;
  final bool isMine;
  final String? creatorName;
  final VoidCallback? onAdd;
  final void Function(AlarmModel, bool) onToggle;
  final void Function(AlarmModel) onEdit;
  final void Function(AlarmModel) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (alarms.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.black,
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Column(
              children: [
                Text(
                  isMine
                      ? 'YOU HAVE NO ALARMS SET.'
                      : "YOU HAVEN'T SET ANYTHING FOR THEM YET.",
                  style: const TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap below to add one.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        else
          ...alarms.map(
            (a) => AlarmCard(
              alarm: a,
              isMine: isMine,
              creatorName: creatorName,
              onToggle: (v) => onToggle(a, v),
              onEdit: () => onEdit(a),
              onDelete: () => onDelete(a),
            ),
          ),
        const SizedBox(height: 16),
        if (onAdd != null)
          MonochromeButton(
            label: isMine ? 'Add Alarm' : 'Wake Them Up',
            icon: Icons.add,
            variant: MonoVariant.outline,
            onPressed: onAdd,
          ),
      ],
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.stats});
  final AlarmStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            StatsCard(stats: stats),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: MonochromeButton(
                      label: 'Reactions',
                      icon: Icons.emoji_emotions_outlined,
                      variant: MonoVariant.ghost,
                      compact: true,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ReactionsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MonochromeButton(
                      label: 'Refresh',
                      icon: Icons.refresh,
                      variant: MonoVariant.ghost,
                      compact: true,
                      onPressed: () {
                        ref.read(alarmStatsProvider.notifier).refresh();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({required this.announcement});
  final AnnouncementModel announcement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.black,
        border: Border.all(color: AppColors.white, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign, color: AppColors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w800,
                    fontSize: 12.sp,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  announcement.body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'RobotoMono',
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
