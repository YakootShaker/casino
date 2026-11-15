class AppConstants {
  AppConstants._();

  // Timing & Game Rules
  static const int turnDurationSeconds = 10;
  static const int roomTtlHours = 4;
  static const int targetWinScore = 5;
  static const int clockSyncIntervalSeconds = 30;
  static const int turnExpireToleranceMs = 250;

  // Touch arbitration layout
  static const double consoleGutterWidth = 12.0;

  // Audio Assets
  static const String buzzerSfxPath = 'assets/audio/buzz.wav';

  // Trivia Categories
  static const List<String> availableCategories = [
    'General Knowledge',
    'Science',
    'History',
    'Geography',
    'Entertainment',
    'Art',
    'Music',
  ];

  // Default Supabase Configuration (Overridable via environment)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );
}
