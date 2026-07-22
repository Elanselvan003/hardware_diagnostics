import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class PrivacyManager {
  static const String _keyLocationConsent = 'privacy_location_consent';
  static const String _keyRecordingConsent = 'privacy_recording_consent';
  static const String _keyDeviceId = 'privacy_device_id';

  static Future<bool> isLocationConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLocationConsent) ?? false;
  }

  static Future<void> setLocationConsent(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLocationConsent, granted);
  }

  static Future<bool> isRecordingConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRecordingConsent) ?? false;
  }

  static Future<void> setRecordingConsent(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRecordingConsent, granted);
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final host = Platform.operatingSystem;
      deviceId = 'device_${host}_$timestamp';
      await prefs.setString(_keyDeviceId, deviceId);
    }
    return deviceId;
  }

  static Future<bool> showConsentDialog({
    required BuildContext context,
    required String title,
    required String description,
    required String featureName,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.lock_outline, size: 20, color: Color(0xFF10B981)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your data is transmitted securely to your private support website API and is NEVER made public.',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Agree & Enable $featureName', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
