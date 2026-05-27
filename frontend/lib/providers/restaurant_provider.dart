// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

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

final categorySummariesProvider = FutureProvider<List<CategorySummary>>((ref) {
  return YumapApiService.fetchCategories();
});

class RestaurantNotifier extends AsyncNotifier<List<Restaurant>> {
  double _lat = defaultLat;
  double _lng = defaultLng;

  @override
  Future<List<Restaurant>> build() {
    final category = ref.watch(categoryProvider);
    return _loadRestaurants(_lat, _lng, category);
  }

  Future<List<Restaurant>> _loadRestaurants(
    double lat,
    double lng,
    String category,
  ) async {
    _lat = lat;
    _lng = lng;
    final restaurants = category.isEmpty
        ? await YumapApiService.fetchRestaurants(lat: lat, lng: lng)
        : await YumapApiService.fetchCategoryRestaurants(
            category: category,
            lat: lat,
            lng: lng,
            limit: 100,
          );
    _sendMarkers(restaurants);
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
    state = await AsyncValue.guard(() => _loadRestaurants(lat, lng, category));
  }

  void toggleFavorite(String id) {
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

  void _sendMarkers(List<Restaurant> restaurants) {
    final markerData = restaurants
        .where(
          (restaurant) => restaurant.latitude != 0 && restaurant.longitude != 0,
        )
        .map(
          (restaurant) => {
            'id': restaurant.id,
            'latitude': restaurant.latitude,
            'longitude': restaurant.longitude,
            'name': restaurant.name,
            'grade': restaurant.grade,
          },
        )
        .toList();
    js.context.callMethod('setRestaurantMarkers', [json.encode(markerData)]);
  }
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

final filteredRestaurantsProvider = Provider<AsyncValue<List<Restaurant>>>((
  ref,
) {
  final asyncRestaurants = ref.watch(restaurantProvider);
  final searchQuery = ref.watch(searchQueryProvider);

  return asyncRestaurants.whenData((restaurants) {
    return restaurants.where((restaurant) {
      if (searchQuery.isNotEmpty && !_matchesSearch(restaurant, searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  });
});

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
