class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const instance = SupabaseConfig(
    url: 'https://zvwgnduuumksuqazpvsf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp2d2duZHV1dW1rc3VxYXpwdnNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYwMDY4NDAsImV4cCI6MjA5MTU4Mjg0MH0.j-o4PW9fEZOPqOtC3AzShBd3l5uJqH4xNCDiJEtHULg',
  );
}
