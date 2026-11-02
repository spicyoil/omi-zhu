import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Omi Zhu: uploads device-stored (offline) recordings to the user's own ARM
/// server instead of Omi's `/v2/sync-local-files`.
///
/// Privacy contract:
/// - Only the ARM bearer token (from `--dart-define=ARM_UPLOAD_TOKEN=...`) is
///   sent. No Omi/Firebase auth header, no Omi app headers.
/// - The token is never logged, printed, or included in exception messages.
///
/// A file counts as delivered only when the server answers HTTP 200 and lists
/// it with `stored: true` and the same sha256 the phone computed. Everything
/// else stays on the phone and is retried on the next sync.
class ArmOfflineUploader {
  ArmOfflineUploader._();

  static const String endpoint = 'https://arm.iot843.com/omi-offline';
  static const String _token = String.fromEnvironment('ARM_UPLOAD_TOKEN');

  static bool get isConfigured => _token.isNotEmpty;

  /// Uploads [files] in one multipart request. Returns the absolute paths the
  /// server confirmed (stored + matching sha256). Throws [ArmUploadException]
  /// on transport/HTTP/parse failure; nothing is confirmed in that case.
  static Future<ArmUploadResult> upload(List<File> files) async {
    if (!isConfigured) throw const ArmUploadException('ARM upload token not configured in this build');

    // One entry per distinct path; the server identifies files by basename, so
    // a second distinct path with the same basename waits for the next pass.
    final byName = <String, File>{};
    for (final file in files) {
      final name = _basename(file.path);
      if (!byName.containsKey(name)) byName[name] = file;
    }
    if (byName.isEmpty) return const ArmUploadResult({});

    final hashes = <String, String>{};
    var totalBytes = 0;
    for (final entry in byName.entries) {
      hashes[entry.key] = (await sha256.bind(entry.value.openRead()).first).toString();
      totalBytes += await entry.value.length();
    }

    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers['Authorization'] = 'Bearer $_token';
    request.headers['Accept'] = 'application/json';
    for (final entry in byName.entries) {
      request.files.add(await http.MultipartFile.fromPath('files', entry.value.path, filename: entry.key));
    }
    request.fields['sha256'] = byName.keys.map((name) => hashes[name]!).join(',');

    // 60s base + ~32 KB/s worst-case uplink, capped at 15 minutes.
    final seconds = (60 + totalBytes ~/ (32 * 1024)).clamp(60, 900);
    final client = http.Client();
    http.Response response;
    try {
      final streamed = await client.send(request).timeout(Duration(seconds: seconds));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const ArmUploadException('ARM upload timed out');
    } on SocketException catch (e) {
      throw ArmUploadException('ARM upload network error: ${e.osError?.message ?? e.message}');
    } on http.ClientException catch (e) {
      throw ArmUploadException('ARM upload client error: ${e.message}');
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      throw ArmUploadException('ARM upload HTTP ${response.statusCode}', statusCode: response.statusCode);
    }

    final confirmed = <String>{};
    try {
      final body = jsonDecode(response.body);
      final received = (body is Map) ? body['received'] : null;
      if (received is! List) throw const FormatException('missing received');
      for (final item in received) {
        if (item is! Map) continue;
        final name = item['filename'];
        final hash = item['sha256'];
        if (name is! String || hash is! String || item['stored'] != true) continue;
        final file = byName[name];
        final local = hashes[name];
        if (file == null || local == null || hash.toLowerCase() != local) continue;
        confirmed.add(file.path);
      }
    } on FormatException {
      throw const ArmUploadException('ARM upload: unparseable response');
    }
    return ArmUploadResult(confirmed);
  }

  static String _basename(String path) => path.split(Platform.pathSeparator).last;
}

class ArmUploadResult {
  const ArmUploadResult(this.confirmedPaths);

  /// Absolute file paths confirmed stored by the server with a matching sha256.
  final Set<String> confirmedPaths;
}

class ArmUploadException implements Exception {
  const ArmUploadException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ArmUploadException: $message';
}
