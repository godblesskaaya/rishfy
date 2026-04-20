import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  final List<_Slide> _slides = const <_Slide>[
    _Slide(
      icon: Icons.directions_car_filled,
      title: 'Share your commute',
      body: 'Post your daily routes and fill empty seats with '
          'passengers going your way.',
    ),
    _Slide(
      icon: Icons.location_on,
      title: 'Find rides that match',
      body: 'Search routes by destination and book a seat with '
          'verified drivers in seconds.',
    ),
    _Slide(
      icon: Icons.verified_user,
      title: 'Safe and LATRA-compliant',
      body: 'Every driver is verified. Every trip is tracked. '
          'Tanzania\'s first licensed ride-sharing platform.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingComplete, true);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (_, int i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                _slides.length,
                (int i) => AnimatedContainer(
                  duration: AppConstants.animationFast,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _index == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _index == i
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                children: <Widget>[
                  PrimaryButton(
                    label: _index == _slides.length - 1 ? 'Get started' : 'Next',
                    onPressed: () {
                      if (_index == _slides.length - 1) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: AppConstants.animationNormal,
                          curve: Curves.easeOut,
                        );
                      }
                    },
                  ),
                  if (_index < _slides.length - 1)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
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

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
