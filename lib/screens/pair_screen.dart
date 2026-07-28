import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../providers/pairing_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/monochrome_button.dart';
import '../widgets/monochrome_input.dart';
import 'home_screen.dart';

/// Pairing screen — generates a 6-digit code or accepts an inbound code.
///
/// Once a pairing transitions to `accepted`, RTC pushes update the
/// `pairingProvider` and we route to `HomeScreen`.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  final _codeCtl = TextEditingController();
  String? _generatedCode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoRoute());
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoRoute() async {
    final pairing = ref.read(pairingProvider).pairing;
    if (pairing != null && pairing.isAccepted && mounted) {
      _goHome();
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final code = await ref.read(pairingProvider.notifier).generateInviteCode();
    if (code != null) {
      setState(() => _generatedCode = code);
      await Clipboard.setData(ClipboardData(text: code));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _accept() async {
    final code = _codeCtl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code must be 6 digits.')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await ref.read(pairingProvider.notifier).acceptInvite(code);
    if (ok) {
      _goHome();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PairingState>(pairingProvider, (prev, next) {
      final pairing = next.pairing;
      if (pairing != null && pairing.isAccepted && mounted) {
        _goHome();
      }
    });

    final state = ref.watch(pairingProvider);
    final error = state.error;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text('PAIR', style: TextStyle(fontSize: 14.sp, letterSpacing: 2)),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'BUILT FOR TWO PEOPLE.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'RobotoMono',
                  fontSize: 11.sp,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pair with the one who matters.',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.black,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CREATE INVITE LINK',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.sp,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share with your partner so they can connect.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.sp,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_generatedCode != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(
                              color: AppColors.white, width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _generatedCode!,
                              style: TextStyle(
                                color: AppColors.white,
                                fontFamily: 'RobotoMono',
                                fontSize: 28.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 4,
                              ),
                            ),
                            const Icon(Icons.copy,
                                color: AppColors.white, size: 18),
                          ],
                        ),
                      ),
                    MonochromeButton(
                      label: _generatedCode == null
                          ? 'Create Invite'
                          : 'Make a New One',
                      icon: Icons.refresh,
                      variant: MonoVariant.primary,
                      loading: _busy,
                      onPressed: _generate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.black,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ENTER A CODE',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.sp,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your partner shared a 6-digit code? Enter it here.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.sp,
                      ),
                    ),
                    const SizedBox(height: 14),
                    MonochromeInput(
                      controller: _codeCtl,
                      icon: Icons.numbers,
                      keyboardType: TextInputType.number,
                      hint: '6-digit code',
                      maxLines: 1,
                    ),
                    const SizedBox(height: 14),
                    MonochromeButton(
                      label: 'Join',
                      icon: Icons.check,
                      variant: MonoVariant.outline,
                      loading: _busy,
                      onPressed: _accept,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Text(
                  error.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontSize: 11.sp,
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
