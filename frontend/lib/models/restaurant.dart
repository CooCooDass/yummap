class MenuItem {
  final String name;
  final String price;
  final String? description;

  const MenuItem({required this.name, required this.price, this.description});

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      name: json['name']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      description: json['description']?.toString(),
    );
  }
}

class WeeklyHour {
  final String date;
  final String hours;

  const WeeklyHour({required this.date, required this.hours});

  factory WeeklyHour.fromJson(Map<String, dynamic> json) {
    return WeeklyHour(
      date: json['date']?.toString() ?? '',
      hours: json['hours']?.toString() ?? '',
    );
  }
}

class RestaurantHours {
  final List<WeeklyHour> weekly;
  final List<String> lastOrders;

  const RestaurantHours({this.weekly = const [], this.lastOrders = const []});

  factory RestaurantHours.fromJson(Map<String, dynamic> json) {
    return RestaurantHours(
      weekly: json['weekly'] is List
          ? (json['weekly'] as List)
                .whereType<Map>()
                .map(
                  (item) =>
                      WeeklyHour.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      lastOrders: json['last_orders'] is List
          ? List<String>.from(
              json['last_orders'].map((item) => item.toString()),
            )
          : const [],
    );
  }
}

class Restaurant {
  final String id;
  final String name;
  final String roadAddress;
  final String jibunAddress;
  final String phone;
  final RestaurantHours? hours;
  final List<MenuItem> menus;
  final double latitude;
  final double longitude;
  final String grade;
  final List<String> categories;
  final List<String> mealTypes;
  final List<String> recommendationTags;
  final double distance;
  final bool isFavorite;

  String get category => categories.isNotEmpty ? categories.first : '음식점';

  const Restaurant({
    required this.id,
    required this.name,
    required this.roadAddress,
    required this.jibunAddress,
    required this.phone,
    this.hours,
    required this.menus,
    required this.latitude,
    required this.longitude,
    required this.grade,
    required this.categories,
    required this.mealTypes,
    required this.recommendationTags,
    this.distance = 0.0,
    this.isFavorite = false,
  });

  Restaurant copyWith({
    bool? isFavorite,
    List<MenuItem>? menus,
    double? distance,
    String? roadAddress,
    String? jibunAddress,
    String? phone,
    RestaurantHours? hours,
    List<String>? categories,
    List<String>? mealTypes,
    List<String>? recommendationTags,
  }) {
    return Restaurant(
      id: id,
      name: name,
      roadAddress: roadAddress ?? this.roadAddress,
      jibunAddress: jibunAddress ?? this.jibunAddress,
      phone: phone ?? this.phone,
      hours: hours ?? this.hours,
      menus: menus ?? this.menus,
      latitude: latitude,
      longitude: longitude,
      grade: grade,
      categories: categories ?? this.categories,
      mealTypes: mealTypes ?? this.mealTypes,
      recommendationTags: recommendationTags ?? this.recommendationTags,
      distance: distance ?? this.distance,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['rid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      roadAddress: json['road_address']?.toString() ?? '',
      jibunAddress: json['jibun_address']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      hours: json['hours'] is Map
          ? RestaurantHours.fromJson(Map<String, dynamic>.from(json['hours']))
          : null,
      menus: json['menus'] is List
          ? (json['menus'] as List)
                .whereType<Map>()
                .map(
                  (item) => MenuItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade']?.toString() ?? '',
      categories: _stringList(json['categories']),
      mealTypes: _stringList(json['meal_types']),
      recommendationTags: _stringList(json['recommendation_tags']),
      distance: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
