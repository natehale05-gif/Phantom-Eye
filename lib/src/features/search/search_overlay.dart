import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/place.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../place/place_icons.dart';

/// Full-screen search: Photon geocoding with debounce, category filter
/// chips, and recent searches when the query is empty.
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key, required this.onPlaceSelected});

  final void Function(Place place) onPlaceSelected;

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final origin = ref.watch(currentGeoPointProvider);
    final category = ref.watch(searchCategoryProvider);
    final resultsAsync = ref.watch(searchResultsProvider(origin));
    final recents = ref.watch(recentSearchesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search places, addresses, trails…',
            border: InputBorder.none,
          ),
          onChanged: (value) => ref.read(searchQueryProvider.notifier).set(value),
          onSubmitted: (value) => ref.read(recentSearchesProvider.notifier).add(value),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              scrollDirection: Axis.horizontal,
              itemCount: SearchCategory.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final c = SearchCategory.values[i];
                return ChoiceChip(
                  label: Text(c.label),
                  selected: category == c,
                  onSelected: (_) => ref.read(searchCategoryProvider.notifier).set(c),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: query.trim().length < 2
                ? _RecentsList(
                    recents: recents,
                    onTap: (q) {
                      _controller.text = q;
                      ref.read(searchQueryProvider.notifier).set(q);
                    },
                    onClear: () => ref.read(recentSearchesProvider.notifier).clear(),
                  )
                : resultsAsync.when(
                    data: (results) {
                      final filtered = category.placeCategory == null
                          ? results
                          : results.where((p) => p.category == category.placeCategory).toList();
                      if (filtered.isEmpty) {
                        return const _EmptyState(message: 'No results found.');
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final place = filtered[i];
                          return ListTile(
                            leading: Icon(placeIconFor(place.category)),
                            title: Text(place.name),
                            subtitle: place.subtitle != null ? Text(place.subtitle!) : null,
                            onTap: () {
                              ref.read(recentSearchesProvider.notifier).add(query);
                              widget.onPlaceSelected(place);
                            },
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const _EmptyState(message: 'Search failed. Check your connection.'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentsList extends StatelessWidget {
  const _RecentsList({required this.recents, required this.onTap, required this.onClear});

  final List<String> recents;
  final void Function(String query) onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) {
      return const _EmptyState(message: 'Search for an address, business, or trailhead.');
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Row(
            children: [
              Text('Recent', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
        for (final q in recents)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            onTap: () => onTap(q),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
