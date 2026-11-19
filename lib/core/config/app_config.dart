/// Build-time configuration. Pass values with --dart-define (see README).
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const appName = 'EZ POS';
  static const currencySymbol = '\u09F3';
  static const currencyCode = 'BDT';
  static const listPageSize = 60;
}
