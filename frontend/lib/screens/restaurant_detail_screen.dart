import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../providers/restaurant_provider.dart';

class RestaurantDetailScreen extends ConsumerWidget {
  final String restaurantId;
  final VoidCallback? onBack;
  final ScrollController? scrollController;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurantId,
    this.onBack,
    this.scrollController,
  });

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.deepOrange[700],
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(MenuItem menu) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              menu.name,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '..................................................',
              maxLines: 1,
              style: TextStyle(color: Colors.black26, letterSpacing: 2),
              overflow: TextOverflow.clip,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            menu.price,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(restaurantDetailProvider(restaurantId));
    final cachedRestaurants =
        ref.watch(restaurantProvider).value ?? const <Restaurant>[];
    Restaurant? cachedRestaurant;
    for (final restaurant in cachedRestaurants) {
      if (restaurant.id == restaurantId) {
        cachedRestaurant = restaurant;
        break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: detailAsync.when(
        loading: () =>
            _buildBody(context, ref, cachedRestaurant, isLoading: true),
        error: (error, stackTrace) {
          if (cachedRestaurant != null) {
            return _buildBody(context, ref, cachedRestaurant);
          }
          return const Center(child: Text('식당 정보를 불러올 수 없습니다.'));
        },
        data: (restaurant) => _buildBody(context, ref, restaurant),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Restaurant? restaurant, {
    bool isLoading = false,
  }) {
    if (restaurant == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final gradeLabel = _gradeLabel(restaurant.grade);
    final addressParts = [
      if (restaurant.roadAddress.isNotEmpty) restaurant.roadAddress,
      restaurant.category,
      if (restaurant.distance > 0)
        '${restaurant.distance.toStringAsFixed(1)}km',
    ];

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverAppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              if (onBack != null) {
                onBack!();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          expandedHeight: 60,
          floating: false,
          pinned: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: Container(
            margin: const EdgeInsets.only(bottom: 20),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 20, right: 20),
              child: IconButton(
                icon: Icon(
                  restaurant.isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: restaurant.isFavorite ? Colors.red : Colors.grey,
                  size: 28,
                ),
                onPressed: () {
                  ref
                      .read(restaurantProvider.notifier)
                      .toggleFavorite(restaurant.id);
                },
              ),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        restaurant.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _gradeColor(restaurant.grade).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_gradeIcon(restaurant.grade)} $gradeLabel',
                        style: TextStyle(
                          color: _gradeColor(restaurant.grade),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  addressParts.join(' · '),
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                if (isLoading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 20),
                if (restaurant.recommendationTags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: restaurant.recommendationTags
                        .map((tag) => _buildTag('#$tag'))
                        .toList(),
                  ),
                const SizedBox(height: 20),
                const Text(
                  '매장 정보',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                if (restaurant.roadAddress.isNotEmpty)
                  _buildInfoRow(Icons.location_on, restaurant.roadAddress),
                if (restaurant.hours != null &&
                    restaurant.hours!.weekly.isNotEmpty)
                  _buildInfoRow(
                    Icons.access_time,
                    restaurant.hours!.weekly
                        .map((hour) => '${hour.date} ${hour.hours}')
                        .join('\n'),
                  ),
                if (restaurant.phone.isNotEmpty)
                  _buildInfoRow(Icons.phone, restaurant.phone),
                const SizedBox(height: 45),
                const Text(
                  '대표 메뉴',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                if (restaurant.menus.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: restaurant.menus
                          .take(5)
                          .map((menu) => _buildMenuItem(menu))
                          .toList(),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        '메뉴 정보가 준비되지 않았습니다.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  String _gradeIcon(String grade) {
    return switch (grade.toLowerCase()) {
      'gold' => '🥇',
      'silver' => '🥈',
      'bronze' => '🥉',
      _ => '•',
    };
  }

  String _gradeLabel(String grade) {
    return switch (grade.toLowerCase()) {
      'gold' => 'Gold',
      'silver' => 'Silver',
      'bronze' => 'Bronze',
      _ => 'Grade',
    };
  }

  Color _gradeColor(String grade) {
    return switch (grade.toLowerCase()) {
      'gold' => const Color(0xFFC99700),
      'silver' => const Color(0xFF7E8794),
      'bronze' => const Color(0xFF9C6A3A),
      _ => Colors.deepOrange,
    };
  }
}
