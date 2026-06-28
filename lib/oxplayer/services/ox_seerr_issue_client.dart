import 'dart:convert';

import 'package:http/http.dart' as http;

/// POST /seerr/proxy/api/v1/issue through the OX API (Jellyfin session auth).
Future<Map<String, dynamic>> oxPostSeerrIssue({
  required String apiBaseUrl,
  required String accessToken,
  required int issueType,
  required String message,
  required int mediaId,
}) async {
  final base = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base/seerr/proxy/api/v1/issue');
  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'MediaBrowser Token="$accessToken"',
    },
    body: jsonEncode({
      'issueType': issueType,
      'message': message,
      'mediaId': mediaId,
    }),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw HttpException(
      'Issue report failed (${response.statusCode})',
      uri: uri,
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid issue response');
  }
  return decoded;
}

class HttpException implements Exception {
  HttpException(this.message, {this.uri});
  final String message;
  final Uri? uri;

  @override
  String toString() => message;
}
