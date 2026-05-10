class AppLinks {
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

  static Uri? get privacyPolicyUri => uriFrom(privacyPolicyUrl);

  static Uri? uriFrom(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }
}
