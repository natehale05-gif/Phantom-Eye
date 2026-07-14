import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// First-run screen for entering the Cesium ion access token.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onSubmit,
    this.errorMessage,
  });

  final ValueChanged<String> onSubmit;
  final String? errorMessage;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  late String? _error = widget.errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Please paste a token to continue.');
      return;
    }
    widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: PhantomColors.background,
      child: Stack(
        children: [
          const _AuroraBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: GlassPanel(
                    radius: 28,
                    padding: const EdgeInsets.fromLTRB(32, 40, 32, 30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.globe,
                          size: 54,
                          color: PhantomColors.text,
                        ),
                        const SizedBox(height: 18),
                        const Text('Phantom Eye', style: PhantomText.largeTitle),
                        const SizedBox(height: 10),
                        const Text(
                          'The planet in photorealistic 3D — offline and online. '
                          'Bring your Cesium ion key to begin.',
                          textAlign: TextAlign.center,
                          style: PhantomText.dim,
                        ),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoTextField(
                                controller: _controller,
                                obscureText: true,
                                autocorrect: false,
                                placeholder: 'Paste your Cesium ion token',
                                placeholderStyle: const TextStyle(
                                  color: PhantomColors.textFaint,
                                ),
                                style: PhantomText.body,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x40000000),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: PhantomColors.glassStroke,
                                  ),
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              color: PhantomColors.accent,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: _submit,
                              child: const Text('Launch'),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: PhantomText.dim.copyWith(
                              color: PhantomColors.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Get a free token at ion.cesium.com/tokens',
                          style: PhantomText.dim,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.8),
          radius: 1.2,
          colors: [Color(0x380A84FF), PhantomColors.background],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, 0.9),
            radius: 1.1,
            colors: [Color(0x2C7A5AFF), Color(0x00000000)],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}
