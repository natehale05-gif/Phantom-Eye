import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../state/providers.dart';
import '../../theme/theme.dart';

/// First-run flow: a short pitch for each of the app's three pillars
/// (everyday nav, offroad/backcountry, Meshtastic friends) followed by the
/// location-permission prompt — Apple platforms want permission asks to
/// have clear, specific context, so we ask right after explaining why.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPageData(
      icon: Icons.map_rounded,
      title: 'Everyday navigation',
      body: 'Turn-by-turn driving, walking, and biking directions with live traffic-free routing '
          'and weather baked right into the map.',
      color: AppColors.accentEveryday,
    ),
    _OnboardPageData(
      icon: Icons.terrain_rounded,
      title: 'Offroad & backcountry',
      body: 'Topo basemaps, trail routing, track recording, and a custom route builder for when '
          'the road ends and the singletrack begins.',
      color: AppColors.accentOffroad,
    ),
    _OnboardPageData(
      icon: Icons.groups_rounded,
      title: 'Stay connected off-grid',
      body: 'Pair a Meshtastic radio to see where your friends are, even miles from cell service.',
      color: AppColors.accentOffroadSecondary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (context, i) => _OnboardPage(data: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: AppDurations.fast,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page ? _pages[i].color : context.glass.raised2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _page < _pages.length - 1 ? _nextPage : _finish,
                      child: Text(_page < _pages.length - 1 ? 'Next' : 'Get Started'),
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

  void _nextPage() {
    _pageController.nextPage(duration: AppDurations.medium, curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    await Geolocator.requestPermission();
    ref.read(onboardingCompleteProvider.notifier).complete();
    widget.onComplete();
  }
}

class _OnboardPageData {
  const _OnboardPageData({required this.icon, required this.title, required this.body, required this.color});
  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

class _OnboardPage extends StatelessWidget {
  const _OnboardPage({required this.data});
  final _OnboardPageData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: data.color.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(data.icon, size: 48, color: data.color),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(data.title, style: AppTypography.title1, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.body,
            style: AppTypography.body.copyWith(color: context.glass.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
