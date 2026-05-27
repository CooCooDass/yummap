import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/restaurant.dart';

class YumapApiService {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001',
  );

  static Uri _uri(String path) {
    final base = _apiBaseUrl.endsWith('/')
        ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
        : _apiBaseUrl;
    return Uri.parse('$base$path');
  }

  static Uri _uriWithQuery(String path, Map<String, String> query) {
    final uri = _uri(path);
    return uri.replace(queryParameters: query.isEmpty ? null : query);
  }

  static Future<List<Restaurant>> fetchRestaurants({
    double? lat,
    double? lng,
    int limit = 2000,
  }) async {
    final response = await http.get(
      _uriWithQuery('/restaurants', {
        'limit': limit.toString(),
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
      }),
    );
    final payload = _decodeResponse(response);
    if (payload is! List) {
      throw const YumapApiException('식당 목록 응답 형식이 올바르지 않습니다.');
    }
    return payload
        .whereType<Map>()
        .map((item) => Restaurant.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<CategorySummary>> fetchCategories() async {
    final response = await http.get(_uri('/categories'));
    final payload = _decodeResponse(response);
    if (payload is! List) {
      throw const YumapApiException('카테고리 목록 응답 형식이 올바르지 않습니다.');
    }
    return payload
        .whereType<Map>()
        .map(
          (item) => CategorySummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static Future<List<Restaurant>> fetchCategoryRestaurants({
    required String category,
    double? lat,
    double? lng,
    int limit = 100,
  }) async {
    final encodedCategory = Uri.encodeComponent(category);
    final response = await http.get(
      _uriWithQuery('/categories/$encodedCategory/restaurants', {
        'limit': limit.toString(),
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
      }),
    );
    final payload = _decodeResponse(response);
    if (payload is! Map || payload['restaurants'] is! List) {
      throw const YumapApiException('카테고리 식당 응답 형식이 올바르지 않습니다.');
    }
    return (payload['restaurants'] as List)
        .whereType<Map>()
        .map((item) => Restaurant.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<Restaurant> fetchRestaurantDetail(
    String rid, {
    double? lat,
    double? lng,
  }) async {
    final response = await http.get(
      _uriWithQuery('/restaurants/$rid', {
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
      }),
    );
    final payload = _decodeResponse(response);
    if (payload is! Map) {
      throw const YumapApiException('식당 상세 응답 형식이 올바르지 않습니다.');
    }
    return Restaurant.fromJson(Map<String, dynamic>.from(payload));
  }

  static Future<PlaceSearchResult?> searchPlace(String keyword) async {
    final response = await http.get(
      _uriWithQuery('/places/search', {'q': keyword}),
    );
    if (response.statusCode == 404 || response.statusCode == 503) {
      return null;
    }
    final payload = _decodeResponse(response);
    if (payload is! Map) {
      throw const YumapApiException('장소 검색 응답 형식이 올바르지 않습니다.');
    }
    return PlaceSearchResult.fromJson(Map<String, dynamic>.from(payload));
  }

  static Future<ChatApiResponse> sendChat({
    required String message,
    double? lat,
    double? lng,
  }) async {
    final response = await http.post(
      _uri('/chat'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: json.encode({
        'message': message,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      }),
    );

    final payload = _decodeResponse(response);
    if (payload is! Map) {
      throw const YumapApiException('채팅 응답 형식이 올바르지 않습니다.');
    }
    return ChatApiResponse.fromJson(Map<String, dynamic>.from(payload));
  }

  static dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YumapApiException('API ${response.statusCode}: ${response.body}');
    }
    return json.decode(utf8.decode(response.bodyBytes));
  }
}

class CategorySummary {
  final String name;
  final String query;
  final int totalCount;
  final int? mainPageIndex;

  const CategorySummary({
    required this.name,
    required this.query,
    required this.totalCount,
    this.mainPageIndex,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> json) {
    return CategorySummary(
      name: json['name']?.toString() ?? '',
      query: json['query']?.toString() ?? '',
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      mainPageIndex: (json['main_page_index'] as num?)?.toInt(),
    );
  }
}

class PlaceSearchResult {
  final double lat;
  final double lng;
  final String name;

  const PlaceSearchResult({
    required this.lat,
    required this.lng,
    required this.name,
  });

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    return PlaceSearchResult(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class ChatApiResponse {
  final String answer;
  final String displayAnswer;
  final List<ChatRestaurantResult> restaurants;

  const ChatApiResponse({
    required this.answer,
    required this.displayAnswer,
    required this.restaurants,
  });

  factory ChatApiResponse.fromJson(Map<String, dynamic> json) {
    return ChatApiResponse(
      answer: json['answer'] ?? '',
      displayAnswer: json['display_answer'] ?? json['answer'] ?? '',
      restaurants: json['restaurants'] is List
          ? (json['restaurants'] as List)
                .whereType<Map>()
                .map(
                  (item) => ChatRestaurantResult.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class ChatRestaurantResult {
  final String rid;
  final String name;
  final String? grade;
  final String? gradeIcon;
  final String? distanceLabel;
  final String reason;
  final String detailPath;

  const ChatRestaurantResult({
    required this.rid,
    required this.name,
    this.grade,
    this.gradeIcon,
    this.distanceLabel,
    required this.reason,
    required this.detailPath,
  });

  factory ChatRestaurantResult.fromJson(Map<String, dynamic> json) {
    return ChatRestaurantResult(
      rid: json['rid'] ?? '',
      name: json['name'] ?? '',
      grade: json['grade'],
      gradeIcon: json['grade_icon'],
      distanceLabel: json['distance_label'],
      reason: json['reason'] ?? '',
      detailPath: json['detail_path'] ?? '',
    );
  }
}

class YumapApiException implements Exception {
  final String message;

  const YumapApiException(this.message);

  @override
  String toString() => message;
}
