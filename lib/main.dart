import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';
import 'package:soda_pulse/ui/screens/feed_screen.dart';
import 'package:soda_pulse/ui/theme/soda_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SodaPulseApp());
}

class SodaPulseApp extends StatefulWidget {
  const SodaPulseApp({super.key});

  @override
  State<SodaPulseApp> createState() => _SodaPulseAppState();
}

class _SodaPulseAppState extends State<SodaPulseApp> {
  late final AppStore _store;

  @override
  void initState() {
    super.initState();
    _store = AppStore();
    _store.init();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SodaPulse',
      debugShowCheckedModeBanner: false,
      theme: SodaTheme.buildDarkTheme(),
      home: FeedScreen(store: _store),
    );
  }
}
