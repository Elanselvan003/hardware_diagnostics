import 'dart:async';
import 'dart:io';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';

class ScreenRecordingService {
  static bool _isRecording = false;
  static Timer? _timer;
  static int _recordedSeconds = 0;
  static String? _lastVideoPath;

  static bool get isRecording => _isRecording;
  static int get recordedSeconds => _recordedSeconds;
  static String? get lastVideoPath => _lastVideoPath;

  static final StreamController<int> _timerStreamController = StreamController<int>.broadcast();
  static Stream<int> get timerStream => _timerStreamController.stream;

  static Future<bool> startRecording({bool audio = true}) async {
    if (_isRecording) return false;

    try {
      final String fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}';
      bool started = false;

      if (audio) {
        started = await FlutterScreenRecording.startRecordScreenAndAudio(
          fileName,
          titleNotification: "Diagnostics Screen Recording",
          messageNotification: "Recording screen and audio...",
        );
      } else {
        started = await FlutterScreenRecording.startRecordScreen(
          fileName,
          titleNotification: "Diagnostics Screen Recording",
          messageNotification: "Recording screen...",
        );
      }

      if (started) {
        _isRecording = true;
        _recordedSeconds = 0;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordedSeconds++;
          _timerStreamController.add(_recordedSeconds);
        });
        return true;
      }
      return false;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }

  static Future<File?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      _timer?.cancel();
      _timer = null;
      _isRecording = false;

      final String path = await FlutterScreenRecording.stopRecordScreen;
      if (path.isNotEmpty) {
        _lastVideoPath = path;
        final file = File(path);
        if (await file.exists()) {
          return file;
        }
      }
      return null;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }
}
