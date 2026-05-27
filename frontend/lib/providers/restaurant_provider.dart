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
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  () => SearchQueryNotifier(),
);

class RestaurantNotifier extends AsyncNotifier<List<Restaurant>> {
  @override
  Future<List<Restaurant>> build() {
    return _loadRestaurants(defaultLat, defaultLng);
  }

  Future<List<Restaurant>> _loadRestaurants(double lat, double lng) async {
    final restaurants = await YumapApiService.fetchRestaurants(
      lat: lat,
      lng: lng,
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
    state = await AsyncValue.guard(() => _loadRestaurants(lat, lng));
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
  final category = ref.watch(categoryProvider);
  final searchQuery = ref.watch(searchQueryProvider);

  return asyncRestaurants.whenData((restaurants) {
    return restaurants.where((restaurant) {
      if (category.isNotEmpty && !_matchesCategory(restaurant, category)) {
        return false;
      }
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

bool _matchesCategory(Restaurant restaurant, String category) {
  final groups = {
    '일식': ['일식', '초밥', '돈카츠', '돈까스', '사케동', '일본가정식', '일식당', '소바', '해산물'],
    '한식': [
      '한식',
      '막국수',
      '보리밥정식',
      '옹심이',
      '닭갈비',
      '알탕',
      '나물',
      '곤이',
      '돼지갈비',
      '한우',
      '칼국수',
      '소고기',
      '한정식',
      '설렁탕',
      '순두부',
      '메밀칼국수',
      '보쌈',
      '밥집',
      '고깃집',
      '국물요리',
    ],
    '중식': ['중식', '짬뽕', '만두', '군만두'],
    '양식': ['양식', '브런치', '이탈리안', '패스트푸드', '멕시칸', '파스타'],
    '분식': ['분식', '떡볶이', '김밥'],
    '카페': ['카페', '핸드드립', '빵', '디저트'],
    '아시안': ['아시안', '태국음식', '베트남음식', '쌀국수'],
  };
  final targets = groups[category] ?? [category];
  return restaurant.categories.any((item) => targets.contains(item)) ||
      restaurant.mealTypes.any((item) => targets.contains(item)) ||
      restaurant.recommendationTags.any((item) => targets.contains(item));
}

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
