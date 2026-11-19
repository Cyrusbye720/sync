import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pairing_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

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
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
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
        const SnackBar(content: Text('Enter your partner\'s 6-digit code.')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await ref.read(pairingProvider.notifier).acceptInvite(code);
    if (ok && mounted) _goHome();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PairingState>(pairingProvider, (_, next) {
      if (next.pairing?.isAccepted == true && mounted) _goHome();
    });
    final state = ref.watch(pairingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Two of you')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Start your shared mornings',
              style: TextStyle(fontSize: 28, height: 1.15,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pair once, then create alarms for either of you.',
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 28),
            _PairCard(
              icon: Icons.favorite_outline_rounded,
              title: 'Invite your partner',
              subtitle: 'Create a code and share it with them.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_generatedCode != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.creamStrong,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _generatedCode!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w800,
                          color: AppColors.cocoa,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(_generatedCode == null
                        ? 'Create invite code'
                        : 'Create another code'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PairCard(
              icon: Icons.numbers_rounded,
              title: 'I have a code',
              subtitle: 'Enter the code your partner sent.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _codeCtl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '000000',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _accept,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.coralDark,
                      side: const BorderSide(color: AppColors.peach),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Join my partner'),
                  ),
                ],
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              Text(state.error!,
                  style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.creamStrong,
                foregroundColor: AppColors.coralDark,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
