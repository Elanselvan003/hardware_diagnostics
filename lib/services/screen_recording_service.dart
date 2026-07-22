import 'dart:async';
import 'dart:io';
import 'package:ed_screen_recorder/ed_screen_recorder.dart';
import 'package:path_provider/path_provider.dart';

class ScreenRecordingService {
  static final EdScreenRecorder _recorder = EdScreenRecorder();
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
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String folderPath = '${appDir.path}/Recordings';
      final Directory folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final String fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}';

      final RecordOutput? result = await _recorder.startRecordScreen(
        fileName: fileName,
        dirPathToSave: folderPath,
        audioEnable: audio,
        addTimeCode: true,
      );

      if (result != null) {
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

      final RecordOutput? result = await _recorder.stopRecord();
      if (result != null && result.file != null) {
        _lastVideoPath = result.file!.path;
        return result.file;
      }
      return null;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }
}
