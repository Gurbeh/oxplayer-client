/// Parses server geo / route-hint headers (health probe, 451 enforce).
abstract final class OxplayerRouteHints {
  static bool isIranRouteRequiredHeader(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'iran':
      case 'arvan':
        return true;
      default:
        return false;
    }
  }

  static bool headersRequireIranRoute(Map<String, String> headers) {
    final country = headers['x-ox-client-country'] ?? headers['X-Ox-Client-Country'];
    if (country != null && country.trim().toUpperCase() == 'IR') {
      return true;
    }
    final hint = headers['x-ox-route-required'] ?? headers['X-Ox-Route-Required'];
    return isIranRouteRequiredHeader(hint);
  }
}
