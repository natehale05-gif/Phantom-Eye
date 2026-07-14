import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'screens/globe_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/connectivity_service.dart';
import 'services/token_store.dart';
import 'theme.dart';

/// Port for the bundled asset server that serves the CesiumJS map locally
/// (so the app shell works with no network).
const int kMapServerPort = 8752;
const String kMapUrl =
    'http://localhost:$kMapServerPort/assets/webmap/index.html';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Serve the bundled web map over localhost so relative paths and web
  // workers load correctly, and so the app shell is available offline.
  final server = InAppLocalhostServer(port: kMapServerPort);
  await server.start();

  final connectivity = ConnectivityService();
  await connectivity.start();

  runApp(PhantomEyeApp(connectivity: connectivity));
}

class PhantomEyeApp extends StatelessWidget {
  const PhantomEyeApp({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Phantom Eye',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: PhantomColors.accent,
        scaffoldBackgroundColor: PhantomColors.background,
      ),
      home: RootScreen(connectivity: connectivity),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.connectivity});
  final ConnectivityService connectivity;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _tokenStore = TokenStore();

  String? _token;
  bool _loading = true;
  String? _onboardingError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _tokenStore.read();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  Future<void> _onTokenSubmitted(String token) async {
    await _tokenStore.save(token);
    if (!mounted) return;
    setState(() {
      _token = token;
      _onboardingError = null;
    });
  }

  Future<void> _onTokenRejected() async {
    await _tokenStore.clear();
    if (!mounted) return;
    setState(() {
      _token = null;
      _onboardingError = 'That token was rejected. Please check it and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CupertinoPageScaffold(
        backgroundColor: PhantomColors.background,
        child: Center(
          child: CupertinoActivityIndicator(color: PhantomColors.text),
        ),
      );
    }

    final token = _token;
    if (token == null) {
      return OnboardingScreen(
        onSubmit: _onTokenSubmitted,
        errorMessage: _onboardingError,
      );
    }

    return GlobeScreen(
      key: ValueKey(token),
      token: token,
      mapUrl: kMapUrl,
      connectivity: widget.connectivity,
      onTokenRejected: _onTokenRejected,
    );
  }
}
