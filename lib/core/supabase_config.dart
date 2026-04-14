class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const instance = SupabaseConfig(
    url: String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
  );
}
