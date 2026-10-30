import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'providers/app_state.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    FlutterError.onError = (d) => debugPrint('FlutterError: ${d.exception}');
    runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const DarkChessApp()));
  }, (e, s) => debugPrint('Uncaught: $e'));
}
