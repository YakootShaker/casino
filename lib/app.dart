import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants/app_colors.dart';
import 'routes/app_router.dart';

class QuizBuzzerApp extends ConsumerWidget {
  const QuizBuzzerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    final baseTheme = ThemeData.dark(useMaterial3: true);

    return MaterialApp.router(
      title: 'Quiz Buzzer',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: baseTheme.colorScheme.copyWith(
          primary: AppColors.player1,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.rubikTextTheme(baseTheme.textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: true,
        ),
      ),
    );
  }
}
