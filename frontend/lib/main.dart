// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/main_screen.dart';

const String kakaoJavascriptKey = String.fromEnvironment(
  'KAKAO_JAVASCRIPT_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadKakaoSdk();

  ui_web.platformViewRegistry.registerViewFactory('kakao-map-view', (
    int viewId,
  ) {
    final div = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%';

    Future.delayed(const Duration(milliseconds: 100), () {
      js.context.callMethod('initKakaoMap', [div]);
    });

    return div;
  });

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _loadKakaoSdk() async {
  if (kakaoJavascriptKey.isEmpty || js.context.hasProperty('kakao')) {
    return;
  }

  final script = html.ScriptElement()
    ..id = 'kakao-map-sdk'
    ..type = 'text/javascript'
    ..src =
        'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoJavascriptKey&autoload=false';

  html.document.head?.append(script);
  try {
    await script.onLoad.first.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    script.remove();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yumap',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Noto Sans KR',
      ),
      home: const MainScreen(),
    );
  }
}
