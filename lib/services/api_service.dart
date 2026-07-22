import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'privacy_manager.dart';

class ApiService {
  static const String _keyApiBaseUrl = 'support_api_base_url';
  static const String _keyAuthToken = 'support_api_auth_token';
  static const String _keyRetryQueue = 'support_api_retry_queue';

  static const String _defaultApiUrl = 'https://hardware-diagnostics.onrender.com/api/v1';

  static Future<String> getApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiBaseUrl) ?? _defaultApiUrl;
  }

  static Future<void> setApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, url.replaceAll(RegExp(r'/$'), ''));
  }

  static Future<String> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken) ?? '';
  }

  static Future<void> setAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthToken, token);
  }

  static Future<Map<String, dynamic>> buildTelemetryData({
    required LocationDataModel? locationData,
    required Map<String, dynamic>? cpuInfo,
    required String appVersion,
  }) async {
    final deviceId = await PrivacyManager.getOrCreateDeviceId();
    final now = DateTime.now().toIso8601String();

    return {
      "device_id": deviceId,
      "timestamp": now,
      "app_version": appVersion,
      "location": locationData != null
          ? locationData.toJson()
          : {
              "latitude": 0.0,
              "longitude": 0.0,
              "accuracy": 0.0,
              "address": "Location Disabled or Unavailable",
              "country": "Unknown"
            },
      "device_info": {
        "brand": cpuInfo?['hardware'] ?? 'Unknown',
        "model": cpuInfo?['model'] ?? 'Unknown',
        "os_version": Platform.operatingSystemVersion,
      }
    };
  }

  static Future<bool> sendTelemetryPayload(Map<String, dynamic> payload) async {
    try {
      final baseUrl = await getApiBaseUrl();
      final token = await getAuthToken();
      final uri = Uri.parse('$baseUrl/support/telemetry');

      final headers = {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
      };

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      } else {
        await _enqueueFailedPayload(payload);
        return false;
      }
    } catch (e) {
      await _enqueueFailedPayload(payload);
      return false;
    }
  }

  static Future<bool> sendLiveEphemeralTelemetry(Map<String, dynamic> payload) async {
    try {
      final baseUrl = await getApiBaseUrl();
      final token = await getAuthToken();
      final uri = Uri.parse('$baseUrl/support/telemetry/live');

      final headers = {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
      };

      // Direct in-memory request (no disk queuing if offline)
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> uploadScreenRecording(
    File videoFile, {
    required String appVersion,
    Function(double progress)? onProgress,
  }) async {
    try {
      final baseUrl = await getApiBaseUrl();
      final token = await getAuthToken();
      final uri = Uri.parse('$baseUrl/support/recordings');

      final request = http.MultipartRequest('POST', uri);
      if (token.isNotEmpty) {
        request.headers['Authorization'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
      }

      final deviceId = await PrivacyManager.getOrCreateDeviceId();
      request.fields['device_id'] = deviceId;
      request.fields['timestamp'] = DateTime.now().toIso8601String();
      request.fields['app_version'] = appVersion;

      final fileStream = videoFile.openRead();
      final length = await videoFile.length();

      int uploadedBytes = 0;
      final Stream<List<int>> streamWithProgress = fileStream.map((chunk) {
        uploadedBytes += chunk.length;
        if (onProgress != null && length > 0) {
          onProgress(uploadedBytes / length);
        }
        return chunk;
      });

      final multipartFile = http.MultipartFile(
        'file',
        streamWithProgress,
        length,
        filename: videoFile.path.split('/').last,
      );

      request.files.add(multipartFile);
      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  static Future<void> _enqueueFailedPayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_keyRetryQueue) ?? [];
    queue.add(jsonEncode(payload));
    await prefs.setStringList(_keyRetryQueue, queue);
  }

  static Future<int> getQueuedPayloadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_keyRetryQueue) ?? [];
    return queue.length;
  }

  static Future<int> retryQueuedPayloads() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_keyRetryQueue) ?? [];
    if (queue.isEmpty) return 0;

    final baseUrl = await getApiBaseUrl();
    final token = await getAuthToken();
    final uri = Uri.parse('$baseUrl/support/telemetry');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
    };

    final List<String> remaining = [];
    int successCount = 0;

    for (String item in queue) {
      try {
        final response = await http.post(
          uri,
          headers: headers,
          body: item,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          successCount++;
        } else {
          remaining.add(item);
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(_keyRetryQueue, remaining);
    return successCount;
  }
}
