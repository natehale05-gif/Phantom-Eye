import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/places.dart';
import '../map/map_controller.dart';
import '../models/place.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';

class GlobeScreen extends StatefulWidget {
  const GlobeScreen({
    super.key,
    required this.token,
    required this.mapUrl,
    required this.connectivity,
    required this.onTokenRejected,
  });

  final String token;
  final String mapUrl;
  final ConnectivityService connectivity;
  final VoidCallback onTokenRejected;

  @override
  State<GlobeScreen> createState() => _GlobeScreenState();
}

class _GlobeScreenState extends State<GlobeScreen> {
  final _map = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  List<SearchResult> _results = const [];
  String? _activePlaceId;
  StreamSubscription<List<SearchResult>>? _resultsSub;
  StreamSubscription<({MapErrorKind kind, String message})>? _errorsSub;

  @override
  void initState() {
    super.initState();
    _map.queueToken(widget.token);
    _resultsSub = _map.searchResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });
    _errorsSub = _map.errors.listen(_onMapError);
    widget.connectivity.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _resultsSub?.cancel();
    _errorsSub?.cancel();
    widget.connectivity.removeListener(_onConnectivityChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() => setState(() {});

  void _onMapError(({MapErrorKind kind, String message}) e) {
    if (!mounted) return;
    if (e.kind == MapErrorKind.token) {
      widget.onTokenRejected();
    } else {
      _toast(
        e.kind == MapErrorKind.network
            ? "You're offline — showing cached areas where available."
            : 'Something went wrong loading the map.',
      );
    }
  }

  void _toast(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _map.search(value);
    });
  }

  void _selectPlace(Place p) {
    setState(() => _activePlaceId = p.id);
    _map.flyToPlace(p);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _results = const []);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return CupertinoPageScaffold(
      backgroundColor: PhantomColors.background,
      child: Stack(
        children: [
          _buildWebView(),
          const _Vignette(),
          _buildTopBar(media),
          _buildDestinations(media),
          _buildHomeButton(),
          _buildLoading(),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.mapUrl)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        cacheEnabled: true,
        clearCache: false,
        supportZoom: false,
        disableContextMenu: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        hardwareAcceleration: true,
        javaScriptEnabled: true,
      ),
      onWebViewCreated: _map.attach,
      onReceivedError: (controller, request, error) {
        debugPrint('WebView error: ${error.description}');
      },
      onConsoleMessage: (controller, msg) {
        debugPrint('WebView console: ${msg.message}');
      },
    );
  }

  Widget _buildTopBar(MediaQueryData media) {
    return Positioned(
      top: media.padding.top + 12,
      left: 18,
      right: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Brand(),
              const SizedBox(width: 10),
              _StatusPill(online: widget.connectivity.isOnline),
              const Spacer(),
              _buildModeToggle(),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearch(),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return ValueListenableBuilder<String>(
      valueListenable: _map.mode,
      builder: (context, mode, _) {
        return GlassPanel(
          radius: 999,
          padding: const EdgeInsets.all(3),
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: mode,
            backgroundColor: const Color(0x00000000),
            thumbColor: const Color(0x33FFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            children: const {
              'photoreal': Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text('Photoreal', style: PhantomText.body),
              ),
              'terrain': Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text('Terrain', style: PhantomText.body),
              ),
            },
            onValueChanged: (v) {
              if (v != null) _map.setMode(v);
            },
          ),
        );
      },
    );
  }

  Widget _buildSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Icon(CupertinoIcons.search,
                  size: 18, color: PhantomColors.textDim),
              Expanded(
                child: CupertinoTextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  placeholder: 'Search anywhere on Earth',
                  placeholderStyle:
                      const TextStyle(color: PhantomColors.textFaint),
                  style: PhantomText.body,
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 14),
                  onChanged: _onSearchChanged,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: _clearSearch,
                  child: const Icon(CupertinoIcons.clear_circled_solid,
                      size: 18, color: PhantomColors.textFaint),
                ),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GlassPanel(
              radius: 18,
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _results.length && i < 6; i++)
                    _SearchRow(
                      label: _results[i].displayName,
                      onTap: () {
                        _map.flyToResult(i);
                        _clearSearch();
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDestinations(MediaQueryData media) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: media.padding.bottom + 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 22, bottom: 10),
            child: Text('DESTINATIONS', style: PhantomText.overline),
          ),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: kPlaces.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final place = kPlaces[i];
                return _DestinationCard(
                  place: place,
                  active: place.id == _activePlaceId,
                  onTap: () => _selectPlace(place),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeButton() {
    return Positioned(
      right: 18,
      top: MediaQuery.of(context).size.height * 0.5 - 24,
      child: GestureDetector(
        onTap: () {
          setState(() => _activePlaceId = null);
          _map.flyHome();
        },
        child: const GlassPanel(
          radius: 999,
          padding: EdgeInsets.all(13),
          child: Icon(CupertinoIcons.globe, size: 22, color: PhantomColors.text),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return ValueListenableBuilder<bool>(
      valueListenable: _map.loading,
      builder: (context, loading, _) {
        return IgnorePointer(
          ignoring: !loading,
          child: AnimatedOpacity(
            opacity: loading ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: const Color(0x8C05070C),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 16, color: PhantomColors.text),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<String>(
                    valueListenable: _map.loadingLabel,
                    builder: (context, label, _) =>
                        Text(label, style: PhantomText.dim),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF6FB8FF), PhantomColors.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: PhantomColors.accent.withValues(alpha: 0.8),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Text('Phantom Eye', style: PhantomText.title),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? PhantomColors.online : PhantomColors.textFaint,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Offline',
            style: PhantomText.dim.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            const Icon(CupertinoIcons.location_solid,
                size: 15, color: PhantomColors.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhantomText.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.place,
    required this.active,
    required this.onTap,
  });

  final Place place;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: 152,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0x2A0A84FF) : PhantomColors.glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? PhantomColors.accent.withValues(alpha: 0.8)
                : PhantomColors.glassStroke,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name,
                style: PhantomText.body
                    .copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(place.region,
                style: PhantomText.dim.copyWith(fontSize: 12.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x4D000000), Color(0x00000000), Color(0x66000000)],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}
