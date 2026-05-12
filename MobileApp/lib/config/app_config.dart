class AppConfig {
  static const String _defaultApiBaseUrl =
      'https://reddihelp-backend.onrender.com/api';
  static const String _defaultSocketBaseUrl =
      'https://reddihelp-backend.onrender.com';

  static final String apiBaseUrl = _normalizeApiBaseUrl(
    const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultApiBaseUrl,
    ),
  );

  static final String socketBaseUrl = _normalizeSocketBaseUrl(
    const String.fromEnvironment('SOCKET_BASE_URL', defaultValue: ''),
    apiBaseUrl,
  );

  static String _normalizeApiBaseUrl(String rawValue) {
    var value = rawValue.trim();
    if (value.isEmpty) value = _defaultApiBaseUrl;

    value = value.replaceAll(RegExp(r'/+$'), '');
    if (!value.endsWith('/api')) {
      value = '$value/api';
    }

    return value;
  }

  static String _normalizeSocketBaseUrl(
    String rawValue,
    String normalizedApiBaseUrl,
  ) {
    var value = rawValue.trim();

    if (value.isEmpty) {
      value = normalizedApiBaseUrl.replaceAll(RegExp(r'/api$'), '');
    }

    value = value.replaceAll(RegExp(r'/+$'), '');
    if (value.isEmpty) value = _defaultSocketBaseUrl;

    return value;
  }
}
