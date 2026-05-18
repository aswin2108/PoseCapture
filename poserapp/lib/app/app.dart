import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class PoseCamApp extends StatelessWidget {
  const PoseCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PoseCam',
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
