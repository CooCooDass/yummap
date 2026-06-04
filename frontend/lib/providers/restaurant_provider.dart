// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../services/yumap_api_service.dart';

const double defaultLat = 37.33859;
const double defaultLng = 127.92599;

class CategoryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void toggleCategory(String category) {
    state = state == category ? '' : category;
  }
}

final categoryProvider = NotifierProvider<CategoryNotifier, String>(
  () => CategoryNotifier(),
);

class SearchQueryNotifier extends Notifier<String> {
  Timer? _timer;

  @override
  String build() => '';

  void updateQuery(String query) {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
    }
    _timer = Timer(const Duration(milliseconds: 300), () {
      state = query;
    });
  }

  void clearQuery() {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
    }
    state = '';
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  () => SearchQueryNotifier(),
);

final categorySummariesProvider = Provider<AsyncValue<List<CategorySummary>>>((
  ref,
) {
  final asyncRestaurants = ref.watch(restaurantProvider);
  return asyncRestaurants.when(
    data: (_) => AsyncValue.data(
      ref.read(restaurantProvider.notifier).categorySummaries,
    ),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
    loading: () => const AsyncValue.loading(),
  );
});

class RestaurantNotifier extends AsyncNotifier<List<Restaurant>> {
  double _lat = defaultLat;
  double _lng = defaultLng;
  BootstrapData? _bootstrap;
  final Set<String> _favoriteIds = {};

  @override
  Future<List<Restaurant>> build() {
    final category = ref.watch(categoryProvider);
    return _loadRestaurants(
      _lat,
      _lng,
      category,
      fetchBootstrap: _bootstrap == null,
    );
  }

  List<CategorySummary> get categorySummaries {
    return _bootstrap?.categories ?? const [];
  }

  List<Restaurant> get allRestaurants {
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      return const [];
    }
    final restaurants = bootstrap.restaurants
        .map(
          (restaurant) => _withDistance(
            restaurant.copyWith(
              isFavorite: _favoriteIds.contains(restaurant.id),
            ),
          ),
        )
        .toList();
    restaurants.sort(_compareFullList);
    return restaurants;
  }

  Future<List<Restaurant>> _loadRestaurants(
    double lat,
    double lng,
    String category, {
    required bool fetchBootstrap,
  }) async {
    _lat = lat;
    _lng = lng;
    if (_bootstrap == null || fetchBootstrap) {
      _bootstrap = await YumapApiService.fetchBootstrap(lat: lat, lng: lng);
    }

    final restaurants = _restaurantsForCategory(category);
    if (restaurants.isNotEmpty) {
      js.context.callMethod('moveMap', [
        restaurants.first.latitude,
        restaurants.first.longitude,
      ]);
    }
    return restaurants;
  }

  Future<Restaurant> fetchDetail(String id) {
    return YumapApiService.fetchRestaurantDetail(id);
  }

  Future<void> loadRestaurantsAt(double lat, double lng) async {
    state = const AsyncValue.loading();
    final category = ref.read(categoryProvider);
    state = await AsyncValue.guard(
      () => _loadRestaurants(
        lat,
        lng,
        category,
        fetchBootstrap: _bootstrap == null,
      ),
    );
  }

  void toggleFavorite(String id) {
    if (_favoriteIds.contains(id)) {
      _favoriteIds.remove(id);
    } else {
      _favoriteIds.add(id);
    }
    state.whenData((restaurants) {
      state = AsyncValue.data([
        for (final restaurant in restaurants)
          if (restaurant.id == id)
            restaurant.copyWith(isFavorite: !restaurant.isFavorite)
          else
            restaurant,
      ]);
    });
  }

  List<Restaurant> _restaurantsForCategory(String category) {
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      return const [];
    }

    final allRestaurants = bootstrap.restaurants
        .map(
          (restaurant) => _withDistance(
            restaurant.copyWith(
              isFavorite: _favoriteIds.contains(restaurant.id),
            ),
          ),
        )
        .toList();

    if (category.isEmpty) {
      allRestaurants.sort(_compareFullList);
      return allRestaurants;
    }

    BootstrapCategory? selectedCategory;
    for (final item in bootstrap.categories) {
      if (item.name == category) {
        selectedCategory = item;
        break;
      }
    }
    if (selectedCategory == null) {
      return const [];
    }

    final byRid = {
      for (final restaurant in allRestaurants) restaurant.id: restaurant,
    };
    final refs = List<CategoryRestaurantRef>.from(selectedCategory.restaurants)
      ..sort((a, b) => (a.rank ?? 999999).compareTo(b.rank ?? 999999));

    return [
      for (final ref in refs)
        if (byRid[ref.rid] != null)
          byRid[ref.rid]!.copyWith(categoryRank: ref.rank),
    ];
  }

  Restaurant _withDistance(Restaurant restaurant) {
    return restaurant.copyWith(
      distance: _haversineKm(
        _lat,
        _lng,
        restaurant.latitude,
        restaurant.longitude,
      ),
    );
  }
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  if (lat2 == 0 || lng2 == 0) {
    return 0.0;
  }
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return double.parse((earthRadiusKm * c).toStringAsFixed(2));
}

double _toRadians(double degrees) {
  return degrees * math.pi / 180;
}

int _compareFullList(Restaurant a, Restaurant b) {
  final aHasDistance = a.distance > 0;
  final bHasDistance = b.distance > 0;
  if (aHasDistance != bHasDistance) {
    return aHasDistance ? -1 : 1;
  }
  if (aHasDistance && bHasDistance && a.distance != b.distance) {
    return a.distance.compareTo(b.distance);
  }
  final pA = _gradePriority(a.grade);
  final pB = _gradePriority(b.grade);
  if (pA != pB) {
    return pA.compareTo(pB);
  }
  return a.name.compareTo(b.name);
}

final restaurantProvider =
    AsyncNotifierProvider<RestaurantNotifier, List<Restaurant>>(
      () => RestaurantNotifier(),
    );

final restaurantDetailProvider = FutureProvider.family<Restaurant, String>((
  ref,
  rid,
) {
  return YumapApiService.fetchRestaurantDetail(rid);
});

class GradeFilterNotifier extends Notifier<String> {
  @override
  String build() => 'ALL';

  void toggleGrade(String grade) {
    state = state == grade ? 'ALL' : grade;
  }
}

final gradeFilterProvider = NotifierProvider<GradeFilterNotifier, String>(
  () => GradeFilterNotifier(),
);

final filteredRestaurantsProvider = Provider<AsyncValue<List<Restaurant>>>((
  ref,
) {
  final asyncRestaurants = ref.watch(restaurantProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final selectedGrade = ref.watch(gradeFilterProvider);
  final selectedCategory = ref.watch(categoryProvider);

  return asyncRestaurants.whenData((restaurants) {
    final baseRestaurants = searchQuery.isEmpty
        ? restaurants
        : ref.read(restaurantProvider.notifier).allRestaurants;
    final filtered = baseRestaurants.where((restaurant) {
      if (searchQuery.isNotEmpty && !_matchesSearch(restaurant, searchQuery)) {
        return false;
      }
      if (selectedGrade != 'ALL' && selectedGrade.isNotEmpty) {
        if (restaurant.grade.toUpperCase() != selectedGrade.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();

    if (selectedCategory.isEmpty || searchQuery.isNotEmpty) {
      filtered.sort(_compareFullList);
    }

    return filtered;
  });
});

int _gradePriority(String grade) {
  switch (grade.toLowerCase()) {
    case 'gold':
      return 1;
    case 'silver':
      return 2;
    case 'bronze':
      return 3;
    default:
      return 4;
  }
}

final favoriteRestaurantsProvider = Provider<List<Restaurant>>((ref) {
  final asyncRestaurants = ref.watch(filteredRestaurantsProvider);
  return asyncRestaurants.maybeWhen(
    data: (restaurants) =>
        restaurants.where((restaurant) => restaurant.isFavorite).toList(),
    orElse: () => [],
  );
});

bool _matchesSearch(Restaurant restaurant, String query) {
  final normalized = query.toLowerCase().replaceAll(' ', '');
  final fields = [
    restaurant.name,
    restaurant.roadAddress,
    ...restaurant.categories,
    ...restaurant.mealTypes,
    ...restaurant.recommendationTags,
  ];
  return fields.any(
    (field) => field.toLowerCase().replaceAll(' ', '').contains(normalized),
  );
}
