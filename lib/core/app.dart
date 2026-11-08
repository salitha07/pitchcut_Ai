import 'package:flutter/material.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class PitchCutApp extends StatelessWidget {
  const PitchCutApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'PitchCut AI',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    routerConfig: appRouter,
  );
}
