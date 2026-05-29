// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';
import '../widgets/category_item.dart';
import '../theme/app_colors.dart';
import '../providers/restaurant_provider.dart';
import '../services/yumap_api_service.dart';
import 'restaurant_detail_screen.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../screens/map_screen.dart';
import 'dart:js' as js;
import 'dart:convert';

class _ChatMessage {
  final bool isUser;
  final String text;
  final List<ChatRestaurantResult> restaurants;

  const _ChatMessage.user(this.text) : isUser = true, restaurants = const [];

  const _ChatMessage.bot(this.text, {this.restaurants = const []})
      : isUser = false;
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with TickerProviderStateMixin {
  String? _detailRestaurantId;
  String? _selectedRestaurantId;
  bool _isDetailOpen = false;
  FocusNode? _searchFocusNode;
  Position? _myPosition;
  bool _isLoadingLocation = true;
  bool _isKeepMode = false;
  bool _isFirstLocationUpdate = true;
  bool _isCategoryExpanded = false;
  TextEditingController? _autoCompleteController;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late AnimationController _animationController;

  final FocusNode _chatFocusNode = FocusNode();
  final TextEditingController _chatInputController = TextEditingController();
  bool _isChatActive = false;
  final List<_ChatMessage> _chatMessages = [];
  bool _isChatSending = false;

  @override
  void initState() {
    super.initState();
    _initApp();

    js.context['onMarkerClicked'] = (String clickedId) {
      final displayList = _isKeepMode
          ? (ref
                    .read(filteredRestaurantsProvider)
                    .value
                    ?.where((r) => r.isFavorite)
                    .toList() ??
                [])
          : (ref.read(filteredRestaurantsProvider).value ?? []);

      final clickedRestaurant = displayList.firstWhere(
        (r) => r.id == clickedId,
      );

      setState(() {
        _detailRestaurantId = clickedId;
        _selectedRestaurantId = clickedId;
        _isDetailOpen = true;
      });

      _syncMarkers();

      js.context.callMethod('moveMap', [
        clickedRestaurant.latitude,
        clickedRestaurant.longitude,
        3,
      ]);

      Future.delayed(const Duration(milliseconds: 50), () {
        if (_sheetController.isAttached) {
          _sheetController.animateTo(
            0.65,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    };
  }

  void _initApp() async {
    const fallbackLat = 37.3422;
    const fallbackLng = 127.9202;

    try {
      _myPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      _myPosition = null;
    }

    final initialLat = _myPosition?.latitude ?? fallbackLat;
    final initialLng = _myPosition?.longitude ?? fallbackLng;
    js.context.callMethod('setInitialLocation', [initialLat, initialLng]);

    setState(() {
      _isLoadingLocation = false;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      final initialRestaurants = ref.read(filteredRestaurantsProvider).value;

      if (initialRestaurants != null && initialRestaurants.isNotEmpty) {
        final markerData = initialRestaurants
            .map(
              (r) => {
                'id': r.id,
                'latitude': r.latitude,
                'longitude': r.longitude,
                'name': r.name,
                'grade': r.grade,
              },
            )
            .toList();

        js.context.callMethod('setRestaurantMarkers', [
          json.encode(markerData),
        ]);

        js.context.callMethod('moveMap', [initialLat, initialLng]);
      }
    });

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      _myPosition = position;
      js.context.callMethod('updateUserMarker', [
        position.latitude,
        position.longitude,
      ]);

      if (_isFirstLocationUpdate) {
        _isFirstLocationUpdate = false;
        js.context.callMethod('moveMap', [
          position.latitude,
          position.longitude,
        ]);
      }
    }, onError: (_) {});
  }

  void _syncMarkers() {
    final restaurants = ref.read(filteredRestaurantsProvider).value ?? [];
    if (restaurants.isEmpty) {
      js.context.callMethod('setRestaurantMarkers', ['[]']);
      return;
    }

    List<Restaurant> displayList = _isKeepMode
        ? restaurants.where((r) => r.isFavorite).toList()
        : restaurants;

    if (_isDetailOpen && _detailRestaurantId != null) {
      displayList = displayList
          .where((r) => r.id == _detailRestaurantId)
          .toList();
    }

    final markerData = displayList
        .map(
          (r) => {
            'id': r.id,
            'latitude': r.latitude,
            'longitude': r.longitude,
            'name': r.name,
            'grade': r.grade,
            'isSelected':
                (r.id == _selectedRestaurantId || r.id == _detailRestaurantId),
          },
        )
        .toList();

    js.context.callMethod('setRestaurantMarkers', [json.encode(markerData)]);
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _chatFocusNode.dispose();
    _chatInputController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isChatSending) return;

    setState(() {
      _chatMessages.add(_ChatMessage.user(trimmed));
      _isChatSending = true;
    });

    _chatInputController.clear();
    _chatFocusNode.requestFocus();

    try {
      final response = await YumapApiService.sendChat(
        message: trimmed,
        lat: _myPosition?.latitude,
        lng: _myPosition?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          _ChatMessage.bot(
            response.answer.isNotEmpty
                ? response.answer
                : response.displayAnswer,
            restaurants: response.restaurants,
          ),
        );
        _isChatSending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          const _ChatMessage.bot('답변을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        );
        _isChatSending = false;
      });
    }
  }

  Widget _buildChatMessage(_ChatMessage message) {
    if (message.isUser || message.restaurants.isEmpty) {
      return Text(
        message.text,
        style: TextStyle(
          color: message.isUser ? Colors.white : AppColors.textPrimary,
          fontSize: 14,
          height: 1.35,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        ...message.restaurants.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final restaurant = entry.value;
          final distance = restaurant.distanceLabel != null
              ? ' 거리: ${restaurant.distanceLabel}'
              : '';
          return InkWell(
            onTap: () => _openRestaurantFromChat(restaurant),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        '$index. ${restaurant.name}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (restaurant.gradeIcon != null)
                        Text(restaurant.gradeIcon!),
                      if (distance.isNotEmpty)
                        Text(
                          distance,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    restaurant.reason,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _openRestaurantFromChat(ChatRestaurantResult result) {
    Restaurant? matched;
    final restaurants = ref.read(restaurantProvider).value ?? [];
    for (final restaurant in restaurants) {
      if (restaurant.id == result.rid) {
        matched = restaurant;
        break;
      }
    }

    setState(() {
      _detailRestaurantId = result.rid;
      _selectedRestaurantId = result.rid;
      _isDetailOpen = true;
      _isChatActive = false;
    });
    _chatFocusNode.unfocus();
    _syncMarkers();

    if (matched != null) {
      js.context.callMethod('moveMap', [
        matched.latitude,
        matched.longitude,
        3,
      ]);
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.65,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _animateToMyLocation() {
    if (_myPosition != null) {
      js.context.callMethod('clearSearchMarker');
      js.context.callMethod('moveMap', [
        _myPosition!.latitude,
        _myPosition!.longitude,
      ]);

      ref.read(searchQueryProvider.notifier).clearQuery();

      setState(() {
        _isDetailOpen = false;
      });
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.45,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _handleSearch(String keyword) async {
    FocusScope.of(context).unfocus();
    if (keyword.trim().isEmpty) return;

    setState(() {
      _selectedRestaurantId = null;
      _detailRestaurantId = null;
      _isDetailOpen = false;
    });

    final allRestaurants = ref.read(restaurantProvider).value ?? [];

    bool matchesSearch(Restaurant restaurant, String query) {
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

    final matchedRestaurants = allRestaurants
        .where((r) => matchesSearch(r, keyword))
        .toList();

    if (matchedRestaurants.isNotEmpty) {
      ref.read(searchQueryProvider.notifier).updateQuery(keyword);

      if (matchedRestaurants.length > 1) {
        final markerData = matchedRestaurants
            .map((r) => {
                  'latitude': r.latitude,
                  'longitude': r.longitude,
                })
            .toList();
        js.context.callMethod('setBoundsToRestaurants', [json.encode(markerData)]);
      } else {
        final targetRestaurant = matchedRestaurants.first;
        js.context.callMethod('moveMap', [
          targetRestaurant.latitude,
          targetRestaurant.longitude,
          3,
        ]);
      }

      _syncMarkers();

      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _sheetController.isAttached) {
          _sheetController.animateTo(
            0.45,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } else {
      final result = await YumapApiService.searchPlace(keyword);

      if (result != null) {
        js.context.callMethod('moveMap', [result.lat, result.lng, 5]);

        ref.read(searchQueryProvider.notifier).clearQuery();
        ref.read(categoryProvider.notifier).toggleCategory('');
        _autoCompleteController?.clear();

        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _sheetController.isAttached) {
            _sheetController.animateTo(
              0.45,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('"$keyword" 위치를 찾을 수 없어요.')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filteredRestaurantsProvider, (previous, next) {
      _syncMarkers();
    });

    final selectedCategory = ref.watch(categoryProvider);
    final asyncCategories = ref.watch(categorySummariesProvider);
    final asyncDisplayedRestaurants = ref.watch(filteredRestaurantsProvider);
    Widget buildSheetHeader(int count) {
      Widget buildGradeButton(String grade, String label) {
        final selectedGrade = ref.watch(gradeFilterProvider);
        final isSelected = selectedGrade == grade;
        return GestureDetector(
          onTap: () {
            ref.read(gradeFilterProvider.notifier).toggleGrade(grade);
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryLight : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isSelected ? 0.08 : 0.03),
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textPrimary.withOpacity(0.8),
                ),
              ),
            ),
          ),
        );
      }

      final gradeWidgets = [
        buildGradeButton('GOLD', '🥇 Gold'),
        buildGradeButton('SILVER', '🥈 Silver'),
        buildGradeButton('BRONZE', '🥉 Bronze'),
      ];

      final verticalDivider = Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: 1.5,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );

      final categoryNames = asyncCategories.maybeWhen(
        data: (categories) => categories
            .map((category) => category.name)
            .where((name) => name.isNotEmpty)
            .toList(),
        orElse: () => const <String>[],
      );

      final categoryWidgets = categoryNames.map((name) {
        return CategoryItem(
          title: name,
          isSelected: selectedCategory == name,
          onTap: () {
            ref.read(searchQueryProvider.notifier).clearQuery();
            _autoCompleteController?.clear();
            ref.read(categoryProvider.notifier).toggleCategory(name);
          },
        );
      }).toList();

      return GestureDetector(
        onVerticalDragUpdate: (details) {
          final screenHeight = MediaQuery.of(context).size.height;
          double newSize =
              _sheetController.size - (details.primaryDelta! / screenHeight);
          _sheetController.jumpTo(newSize.clamp(0.22, 0.87));

          if (details.primaryDelta! > 0 && _isCategoryExpanded) {
            setState(() {
              _isCategoryExpanded = false;
            });
          }
        },
        onVerticalDragEnd: (details) {
          final currentSize = _sheetController.size;
          final velocity = details.primaryVelocity ?? 0;

          if (velocity < -100) {
            _sheetController.animateTo(
              0.87,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuart,
            );
          } else if (velocity > 100) {
            if (_isCategoryExpanded) {
              setState(() {
                _isCategoryExpanded = false;
              });
            }
            _sheetController.animateTo(
              0.22,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuart,
            );
          } else {
            const snapSizes = [0.22, 0.45, 0.87];
            double closest = snapSizes.reduce(
              (a, b) =>
                  (a - currentSize).abs() < (b - currentSize).abs() ? a : b,
            );

            if (closest != 0.87 && _isCategoryExpanded) {
              setState(() {
                _isCategoryExpanded = false;
              });
            }
            _sheetController.animateTo(
              closest,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuart,
            );
          }
        },
        child: Container(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 15, bottom: 15),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _isKeepMode
                            ? 'keep list 💖'
                            : (selectedCategory.isEmpty
                                  ? '근처 추천 맛집'
                                  : '✨ 추천 $selectedCategory 맛집'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    Row(
                      children: [
                        Text(
                          '총 $count곳',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isCategoryExpanded = !_isCategoryExpanded;
                            });
                            if (_isCategoryExpanded &&
                                _sheetController.isAttached) {
                              _sheetController.animateTo(
                                0.87,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          child: AnimatedRotation(
                            turns: _isCategoryExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_down,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                firstCurve: Curves.easeOutCubic,
                secondCurve: Curves.easeOutCubic,
                sizeCurve: Curves.easeOutCubic,
                crossFadeState: _isCategoryExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,

                firstChild: Container(
                  padding: const EdgeInsets.only(bottom: 15),
                  width: double.infinity,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ...gradeWidgets,
                          verticalDivider,
                          ...categoryWidgets,
                        ],
                      ),
                    ),
                  ),
                ),

                secondChild: Container(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.of(context).size.height * 0.3).clamp(
                      100.0,
                      180.0,
                    ),
                  ),
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 15,
                  ),
                  width: double.infinity,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ...gradeWidgets,
                        ...categoryWidgets,
                      ],
                    ),
                  ),
                ),
              ),

              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: _isLoadingLocation
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    top: _isDetailOpen ? -150 : 0,
                    bottom: _isDetailOpen ? 150 : 0,
                    left: 0,
                    right: 0,
                    child: const MapScreen(),
                  ),

                  AnimatedBuilder(
                    animation: _sheetController,
                    builder: (context, child) {
                      final mediaQuery = MediaQuery.of(context);
                      final safeAreaHeight = mediaQuery.size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;

                      double currentSheetSize = 0.45;
                      if (_sheetController.isAttached) {
                        currentSheetSize = _sheetController.size;
                      } else if (_isDetailOpen) {
                        currentSheetSize = 0.65;
                      }

                      final bottomOffset = safeAreaHeight * currentSheetSize;
                      final showFloatingButtons = currentSheetSize < 0.8 && !_isChatActive;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            bottom: bottomOffset + 82,
                            right: 20,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: showFloatingButtons ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !showFloatingButtons,
                                child: PointerInterceptor(
                                  child: FloatingActionButton(
                                    heroTag: 'my_location_fab',
                                    backgroundColor: AppColors.background,
                                    mini: true,
                                    elevation: 4,
                                    onPressed: _animateToMyLocation,
                                    child: const Icon(
                                      Icons.my_location,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: bottomOffset + 12,
                            right: 20,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: showFloatingButtons ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !showFloatingButtons,
                                child: PointerInterceptor(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FloatingActionButton(
                                        heroTag: 'llm_chat_fab',
                                        onPressed: () {
                                          setState(() {
                                            _isChatActive = true;
                                          });
                                          Future.delayed(
                                            const Duration(milliseconds: 400),
                                            () => _chatFocusNode.requestFocus(),
                                          );
                                        },
                                        backgroundColor: AppColors.background,
                                        mini: true,
                                        elevation: 4,
                                        child: ShaderMask(
                                          shaderCallback: (bounds) => const LinearGradient(
                                            colors: [
                                              Colors.blue,
                                              Colors.purple,
                                              Colors.orange,
                                            ],
                                          ).createShader(bounds),
                                          child: const Icon(
                                            Icons.auto_awesome,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.65),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'AI 챗',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  Positioned(
                    top: 20,
                    left: 20,
                    child: PointerInterceptor(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                        width: _isDetailOpen
                            ? 50
                            : MediaQuery.of(context).size.width - 110,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              switchInCurve: Curves.easeIn,
                              switchOutCurve: Curves.easeOut,
                              child: _isDetailOpen
                                  ? SizedBox(
                                      key: const ValueKey('search_btn_morph'),
                                      width: 50,
                                      height: 50,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.search,
                                          color: Colors.black87,
                                          size: 24,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isDetailOpen = false;
                                          });
                                          Future.delayed(
                                            const Duration(milliseconds: 50),
                                            () {
                                              if (_sheetController.isAttached) {
                                                _sheetController.animateTo(
                                                  0.45,
                                                  duration: const Duration(
                                                    milliseconds: 400,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                );
                                              }
                                            },
                                          );
                                          Future.delayed(
                                            const Duration(milliseconds: 300),
                                            () {
                                              _searchFocusNode?.requestFocus();
                                            },
                                          );
                                        },
                                      ),
                                    )
                                  : SizedBox(
                                      key: const ValueKey('search_bar_morph'),
                                      width:
                                          MediaQuery.of(context).size.width - 110,
                                      height: 50,
                                      child: Autocomplete<String>(
                                        initialValue: TextEditingValue(
                                          text: ref.read(searchQueryProvider),
                                        ),
                                        optionsBuilder:
                                            (TextEditingValue textEditingValue) {
                                              final query = textEditingValue.text
                                                  .trim();
                                              if (query.isEmpty) {
                                                return const Iterable<
                                                  String
                                                >.empty();
                                              }
                                              final restaurants =
                                                  ref
                                                      .read(restaurantProvider)
                                                      .value ??
                                                  const <Restaurant>[];
                                              return restaurants
                                                  .map(
                                                    (restaurant) =>
                                                        restaurant.name,
                                                  )
                                                  .where(
                                                    (name) =>
                                                        name.contains(query),
                                                  )
                                                  .take(8);
                                            },
                                        onSelected: (String selection) {
                                          _handleSearch(selection);
                                        },
                                        fieldViewBuilder:
                                            (
                                              BuildContext context,
                                              TextEditingController
                                              textEditingController,
                                              FocusNode focusNode,
                                              VoidCallback onFieldSubmitted,
                                            ) {
                                              _searchFocusNode = focusNode;
                                              _autoCompleteController =
                                                  textEditingController;

                                              return Container(
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  color: AppColors.background,
                                                  borderRadius:
                                                      BorderRadius.circular(25),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.1),
                                                      blurRadius: 10,
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  children: [
                                                    const SizedBox(width: 15),
                                                    const Icon(
                                                      Icons.search,
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: TextField(
                                                        controller:
                                                            textEditingController,
                                                        focusNode: focusNode,
                                                        textAlignVertical:
                                                            TextAlignVertical
                                                                .center,
                                                        onTap: () {
                                                          if (_isDetailOpen ||
                                                              _selectedRestaurantId !=
                                                                  null) {
                                                            setState(() {
                                                              _isDetailOpen =
                                                                  false;
                                                              _detailRestaurantId =
                                                                  null;
                                                              _selectedRestaurantId =
                                                                  null;
                                                            });

                                                            _syncMarkers();

                                                            if (_sheetController
                                                                .isAttached) {
                                                              _sheetController.animateTo(
                                                                0.45,
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          300,
                                                                    ),
                                                                curve: Curves
                                                                    .easeOutCubic,
                                                              );
                                                            }
                                                          }
                                                        },
                                                        onChanged: (value) {
                                                          ref
                                                              .read(
                                                                searchQueryProvider
                                                                    .notifier,
                                                              )
                                                              .updateQuery(value);
                                                        },
                                                        onSubmitted: (value) {
                                                          _handleSearch(value);
                                                        },
                                                        decoration: InputDecoration(
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 12,
                                                              ),
                                                          hintText: '음식점, 주소 검색',
                                                          hintStyle:
                                                              const TextStyle(
                                                                color: AppColors
                                                                    .textSecondary,
                                                                fontSize: 14,
                                                              ),
                                                          border: InputBorder.none,
                                                          suffixIcon:
                                                              textEditingController
                                                                  .text
                                                                  .isNotEmpty
                                                              ? IconButton(
                                                                  icon: const Icon(
                                                                    Icons.cancel,
                                                                    color: Colors
                                                                        .grey,
                                                                    size: 20,
                                                                  ),
                                                                  onPressed: () {
                                                                    textEditingController
                                                                        .clear();
                                                                    ref
                                                                        .read(
                                                                          searchQueryProvider
                                                                              .notifier,
                                                                        )
                                                                        .clearQuery();
                                                                    ref
                                                                        .read(
                                                                          categoryProvider
                                                                              .notifier,
                                                                        )
                                                                        .toggleCategory(
                                                                          '',
                                                                        );
                                                                    _syncMarkers();
                                                                  },
                                                                )
                                                              : null,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                        optionsViewBuilder:
                                            (
                                              BuildContext context,
                                              AutocompleteOnSelected<String>
                                              onSelected,
                                              Iterable<String> options,
                                            ) {
                                              return Align(
                                                alignment: Alignment.topLeft,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {},
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            top: 8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.background,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withOpacity(0.1),
                                                            blurRadius: 10,
                                                            offset: const Offset(
                                                              0,
                                                              4,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      constraints: BoxConstraints(
                                                        maxHeight: 200,
                                                        maxWidth:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.width -
                                                            110,
                                                      ),
                                                      child: ListView.builder(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 8,
                                                            ),
                                                        shrinkWrap: true,
                                                        itemCount: options.length,
                                                        itemBuilder:
                                                            (
                                                              BuildContext
                                                              context,
                                                              int index,
                                                            ) {
                                                              final String
                                                              option = options
                                                                  .elementAt(
                                                                    index,
                                                                  );
                                                              return InkWell(
                                                                onTap: () =>
                                                                    onSelected(
                                                                      option,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      10,
                                                                    ),
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            20,
                                                                        vertical:
                                                                            12,
                                                                      ),
                                                                  child: Row(
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .search,
                                                                        size: 16,
                                                                        color: AppColors
                                                                            .textSecondary,
                                                                      ),
                                                                      const SizedBox(
                                                                        width: 10,
                                                                      ),
                                                                      Text(
                                                                        option,
                                                                        style: const TextStyle(
                                                                          color: AppColors
                                                                              .textPrimary,
                                                                          fontSize:
                                                                              14,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 20,
                    right: 20,
                    child: PointerInterceptor(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isKeepMode = !_isKeepMode;

                            if (_isKeepMode) {
                              _isDetailOpen = false;
                            }
                          });
                          _syncMarkers();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 50,
                          width: 60,
                          decoration: BoxDecoration(
                            color: _isKeepMode
                                ? AppColors.error
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 5,
                              ),
                            ],
                            border: Border.all(
                              color: _isKeepMode
                                  ? Colors.transparent
                                  : AppColors.error.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.favorite,
                                color: _isKeepMode
                                    ? Colors.white
                                    : AppColors.error,
                                size: 20,
                              ),
                              Text(
                                'keep',
                                style: TextStyle(
                                  color: _isKeepMode
                                      ? Colors.white
                                      : AppColors.error,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  DraggableScrollableSheet(
                    key: const ValueKey('bottom_sheet_key'),
                    controller: _sheetController,
                    initialChildSize: 0.45,
                    minChildSize: 0.22,
                    maxChildSize: _isDetailOpen ? 1.0 : 0.87,
                    snap: true,
                    snapSizes: _isDetailOpen
                        ? const [0.22, 0.65, 1.0]
                        : const [0.22, 0.45, 0.87],
                    builder: (BuildContext context, ScrollController scrollController) {
                      return PointerInterceptor(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),

                            child: Stack(
                              children: [
                                Container(
                                  child: asyncDisplayedRestaurants.when(
                                    loading: () => Column(
                                      children: [
                                        buildSheetHeader(0),
                                        const Expanded(
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    error: (err, stack) => SingleChildScrollView(
                                      controller: scrollController,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: Container(
                                        height: 300,
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                          '앗! 데이터를 못 불러왔어요.\n\n이유: $err',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                    data: (restaurants) {
                                      final displayList = _isKeepMode
                                          ? restaurants
                                                .where((r) => r.isFavorite)
                                                .toList()
                                          : restaurants;

                                      return Column(
                                        children: [
                                          buildSheetHeader(displayList.length),

                                          Expanded(
                                            child: displayList.isEmpty
                                                ? SingleChildScrollView(
                                                    controller: !_isDetailOpen
                                                        ? scrollController
                                                        : null,
                                                    physics:
                                                        const AlwaysScrollableScrollPhysics(),
                                                    child: Container(
                                                      height: 300,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        _isKeepMode
                                                            ? '보관한 맛집이 없습니다 텅~ 💔\n마음에 드는 식당에 하트를 눌러보세요!'
                                                            : '검색 결과가 없습니다 텅~ 🍃\n다른 키워드로 검색해보세요!',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 16,
                                                          height: 1.5,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : ListView.builder(
                                                    controller: !_isDetailOpen
                                                        ? scrollController
                                                        : null,
                                                    key: const PageStorageKey(
                                                      'restaurant_list',
                                                    ),
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 100,
                                                        ),
                                                    itemExtent: 85.0,
                                                    itemCount:
                                                        displayList.length,
                                                    itemBuilder: (context, index) {
                                                      Restaurant restaurant =
                                                          displayList[index];
                                                      bool isSelected =
                                                          _selectedRestaurantId ==
                                                          restaurant.id;

                                                      return Container(
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? AppColors
                                                                    .primary
                                                                    .withOpacity(
                                                                      0.1,
                                                                    )
                                                              : Colors
                                                                    .transparent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                15,
                                                              ),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? AppColors
                                                                      .primary
                                                                      .withOpacity(
                                                                        0.5,
                                                                      )
                                                                : Colors
                                                                      .transparent,
                                                            width: 1.5,
                                                          ),
                                                        ),
                                                        child: ListTile(
                                                          onTap: () {
                                                            if (isSelected) {
                                                              setState(() {
                                                                _detailRestaurantId =
                                                                    restaurant
                                                                        .id;
                                                                _isDetailOpen =
                                                                    true;
                                                              });
                                                              _syncMarkers();

                                                              js.context.callMethod(
                                                                'moveMap',
                                                                [
                                                                  restaurant
                                                                      .latitude,
                                                                  restaurant
                                                                      .longitude,
                                                                  3,
                                                                ],
                                                              );

                                                              Future.delayed(
                                                                const Duration(
                                                                  milliseconds:
                                                                      50,
                                                                ),
                                                                () {
                                                                  if (_sheetController
                                                                      .isAttached) {
                                                                    _sheetController.animateTo(
                                                                      0.65,
                                                                      duration: const Duration(
                                                                        milliseconds:
                                                                            400,
                                                                      ),
                                                                      curve: Curves
                                                                          .easeOutCubic,
                                                                    );
                                                                  }
                                                                },
                                                              );
                                                            } else {
                                                              setState(
                                                                () => _selectedRestaurantId =
                                                                    restaurant
                                                                        .id,
                                                              );

                                                              _syncMarkers();

                                                              js.context.callMethod(
                                                                'moveMap',
                                                                [
                                                                  restaurant
                                                                      .latitude,
                                                                  restaurant
                                                                      .longitude,
                                                                  3,
                                                                ],
                                                              );

                                                              if (_sheetController
                                                                  .isAttached) {
                                                                _sheetController.animateTo(
                                                                  0.45,
                                                                  duration:
                                                                      const Duration(
                                                                        milliseconds:
                                                                            300,
                                                                      ),
                                                                  curve: Curves
                                                                      .easeOutCubic,
                                                                );
                                                              }

                                                              final targetIndex =
                                                                  displayList.indexWhere(
                                                                    (r) =>
                                                                        r.id ==
                                                                        restaurant
                                                                            .id,
                                                                  );

                                                              if (targetIndex !=
                                                                  -1) {
                                                                Future.delayed(
                                                                  const Duration(
                                                                    milliseconds:
                                                                        300,
                                                                  ),
                                                                  () {
                                                                    if (scrollController
                                                                        .hasClients) {
                                                                      scrollController.animateTo(
                                                                        targetIndex *
                                                                            85.0,
                                                                        duration: const Duration(
                                                                          milliseconds:
                                                                              400,
                                                                        ),
                                                                        curve: Curves
                                                                            .easeOutCubic,
                                                                      );
                                                                    }
                                                                  },
                                                                );
                                                              }
                                                            }
                                                          },
                                                          title: Text(
                                                            restaurant.name,
                                                            style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: AppColors
                                                                  .textPrimary,
                                                            ),
                                                          ),

                                                          subtitle: Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  top: 4.0,
                                                                ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Text(
                                                                  restaurant.grade
                                                                              .toUpperCase() ==
                                                                          'GOLD'
                                                                      ? '🥇'
                                                                      : restaurant.grade.toUpperCase() ==
                                                                            'SILVER'
                                                                      ? '🥈'
                                                                      : restaurant.grade.toUpperCase() ==
                                                                            'BRONZE'
                                                                      ? '🥉'
                                                                      : '🏅',

                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            14,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  restaurant
                                                                      .grade
                                                                      .toUpperCase(),
                                                                  style: const TextStyle(
                                                                    color: AppColors
                                                                        .textSecondary,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          trailing: IconButton(
                                                            icon: Icon(
                                                              restaurant
                                                                      .isFavorite
                                                                  ? Icons
                                                                        .favorite
                                                                  : Icons
                                                                        .favorite_border,
                                                              color:
                                                                  restaurant
                                                                          .isFavorite
                                                                      ? AppColors
                                                                          .error
                                                                      : AppColors
                                                                          .divider,
                                                            ),
                                                            onPressed: () => ref
                                                                .read(
                                                                  restaurantProvider
                                                                      .notifier,
                                                                )
                                                                .toggleFavorite(
                                                                  restaurant.id,
                                                                ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),

                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  top: 0,
                                  bottom: 0,
                                  left: _isDetailOpen
                                      ? 0
                                      : MediaQuery.of(context).size.width,
                                  right: _isDetailOpen
                                      ? 0
                                      : -MediaQuery.of(context).size.width,
                                  child: Container(
                                    color: AppColors.background,
                                    child: _detailRestaurantId != null
                                        ? RestaurantDetailScreen(
                                            key: ValueKey(_detailRestaurantId),
                                            restaurantId: _detailRestaurantId!,
                                            scrollController: _isDetailOpen
                                                ? scrollController
                                                : null,
                                            onBack: () {
                                              setState(() {
                                                _isDetailOpen = false;
                                                _detailRestaurantId = null;
                                                _selectedRestaurantId = null;
                                              });
                                              _syncMarkers();
                                              Future.delayed(
                                                const Duration(
                                                  milliseconds: 50,
                                                ),
                                                () {
                                                  if (_sheetController
                                                      .isAttached) {
                                                    _sheetController.animateTo(
                                                      0.45,
                                                      duration: const Duration(
                                                        milliseconds: 400,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                    );
                                                  }
                                                },
                                              );
                                            },
                                          )
                                        : const SizedBox(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    top: _isChatActive ? 0 : MediaQuery.of(context).size.height,
                    bottom: _isChatActive
                        ? 0
                        : -MediaQuery.of(context).size.height,
                    left: 0,
                    right: 0,
                    child: PointerInterceptor(
                      child: GestureDetector(
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => _isChatActive = false);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          color: Colors.transparent,
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          alignment: const Alignment(0, -0.25),
                          child: GestureDetector(
                            onTap: () {},
                            child: Container(
                              constraints: const BoxConstraints(
                                maxHeight: 550,
                              ),
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height * 0.55,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 15,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'AI 맛잘알 챗봇 🤖',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: AppColors.textPrimary,
                                            size: 22,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            FocusManager.instance.primaryFocus
                                                ?.unfocus();
                                            setState(
                                              () => _isChatActive = false,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      reverse: true,
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _chatMessages.length + (_isChatSending ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (_isChatSending && index == 0) {
                                          return Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(15).copyWith(
                                                  bottomLeft: const Radius.circular(0),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        AppColors.primary,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    '답변을 생각하고 있어요...',
                                                    style: TextStyle(
                                                      color: AppColors.textPrimary,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }

                                        final messageIndex = _isChatSending ? index - 1 : index;
                                        final msg =
                                            _chatMessages[_chatMessages.length -
                                                1 -
                                                messageIndex];
                                        final isMe = msg.isUser;
                                        return Align(
                                          alignment: isMe
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? AppColors.primary
                                                  : Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    15,
                                                  ).copyWith(
                                                    bottomRight: isMe
                                                        ? const Radius.circular(
                                                            0,
                                                          )
                                                        : const Radius.circular(
                                                            15,
                                                          ),
                                                    bottomLeft: !isMe
                                                        ? const Radius.circular(
                                                            0,
                                                          )
                                                        : const Radius.circular(
                                                            15,
                                                          ),
                                                  ),
                                            ),
                                            child: _buildChatMessage(msg),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 45,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: TextField(
                                              controller: _chatInputController,
                                              focusNode: _chatFocusNode,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                              onSubmitted: (text) =>
                                                  _sendMessage(text),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                hintText: '맛집을 물어보세요!',
                                                hintStyle: TextStyle(
                                                  fontSize: 14,
                                                ),
                                                border: InputBorder.none,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => _sendMessage(
                                            _chatInputController.text,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.send,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    bottom: -100,
                    right: 20,
                    child: PointerInterceptor(
                      child: FloatingActionButton(
                        onPressed: () {},
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        highlightElevation: 0,
                        hoverElevation: 0,
                        focusElevation: 0,
                        child: const SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
