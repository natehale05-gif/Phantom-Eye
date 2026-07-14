import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../models/geo_point.dart';
import '../models/place.dart';
import 'core_providers.dart';

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

/// Debounced (350ms) search results, biased toward [biasPoint] (the current
/// map center) — matches the brief's "debounce, categories, recents" spec.
final searchResultsProvider = FutureProvider.autoDispose.family<List<Place>, GeoPoint?>((ref, biasPoint) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return [];
  await Future<void>.delayed(const Duration(milliseconds: 350));
  final service = ref.read(geocodingServiceProvider);
  return service.search(query, bias: biasPoint);
});

class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.read(localStoreProvider).getStringList(StoreKeys.recentSearches);

  void add(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = [trimmed, ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase())];
    state = updated.take(10).toList();
    ref.read(localStoreProvider).setStringList(StoreKeys.recentSearches, state);
  }

  void clear() {
    state = [];
    ref.read(localStoreProvider).setStringList(StoreKeys.recentSearches, []);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearchesNotifier, List<String>>(RecentSearchesNotifier.new);

enum SearchCategory { all, food, gas, parking, lodging, trailhead, campground }

extension SearchCategoryX on SearchCategory {
  String get label => switch (this) {
        SearchCategory.all => 'All',
        SearchCategory.food => 'Food',
        SearchCategory.gas => 'Gas',
        SearchCategory.parking => 'Parking',
        SearchCategory.lodging => 'Lodging',
        SearchCategory.trailhead => 'Trailheads',
        SearchCategory.campground => 'Campgrounds',
      };

  PlaceCategory? get placeCategory => switch (this) {
        SearchCategory.all => null,
        SearchCategory.food => PlaceCategory.food,
        SearchCategory.gas => PlaceCategory.gas,
        SearchCategory.parking => PlaceCategory.parking,
        SearchCategory.lodging => PlaceCategory.lodging,
        SearchCategory.trailhead => PlaceCategory.trailhead,
        SearchCategory.campground => PlaceCategory.campground,
      };
}

class SearchCategoryNotifier extends Notifier<SearchCategory> {
  @override
  SearchCategory build() => SearchCategory.all;
  void set(SearchCategory value) => state = value;
}

final searchCategoryProvider =
    NotifierProvider<SearchCategoryNotifier, SearchCategory>(SearchCategoryNotifier.new);
