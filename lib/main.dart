import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'services/privacy_manager.dart';
import 'services/location_service.dart';
import 'services/screen_recording_service.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hardware Diagnostics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF10B981),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          elevation: 4,
          margin: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      home: const DiagnosticsDashboard(),
    );
  }
}

class DiagnosticsDashboard extends StatefulWidget {
  const DiagnosticsDashboard({super.key});

  @override
  State<DiagnosticsDashboard> createState() => _DiagnosticsDashboardState();
}

class _DiagnosticsDashboardState extends State<DiagnosticsDashboard> {
  static const platform = MethodChannel('com.example.hardware_diagnostics/info');

  // Specs data
  Map<String, dynamic>? _cpuInfo;
  Map<String, dynamic>? _ramInfo;
  Map<String, dynamic>? _storageInfo;
  Map<String, dynamic>? _batteryInfo;
  bool _isLoading = true;
  String _errorMessage = '';

  // App version
  String _appVersion = '1.2.0';
  String _buildNumber = '3';

  // GitHub repository configuration
  String _githubOwner = 'Elanselvan003';
  String _githubRepo = 'hardware_diagnostics';

  // Feature 1: Location Tracking State
  bool _isLocationEnabled = false;
  bool _isLocationLoading = false;
  LocationDataModel? _currentLocation;

  // Feature 2: Screen Recording State
  bool _isRecording = false;
  bool _recordAudio = true;
  int _recordedSeconds = 0;
  bool _isUploadingVideo = false;
  double _videoUploadProgress = 0.0;

  // Feature 3: Live Ephemeral Monitor State (Zero Disk Storage)
  bool _isLiveMonitorActive = false;
  Timer? _liveTelemetryTimer;
  int _liveStreamUpdatesCount = 0;

  // Support API & Retry Queue State
  String _apiBaseUrl = '';
  String _apiToken = '';
  int _queuedPayloads = 0;
  bool _isSyncingApi = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _liveTelemetryTimer?.cancel();
    LocationService.stopBackgroundLocationUpdates();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadAllInfo();
    await _loadPrivacyPreferences();
    await _loadApiSettings();
    _checkQueuedPayloads();
  }

  Future<void> _loadPrivacyPreferences() async {
    final locationGranted = await PrivacyManager.isLocationConsentGranted();
    setState(() {
      _isLocationEnabled = locationGranted;
    });

    if (_isLocationEnabled) {
      _fetchLocation();
    }
  }

  Future<void> _loadApiSettings() async {
    final url = await ApiService.getApiBaseUrl();
    final token = await ApiService.getAuthToken();
    setState(() {
      _apiBaseUrl = url;
      _apiToken = token;
    });
  }

  Future<void> _checkQueuedPayloads() async {
    final count = await ApiService.getQueuedPayloadCount();
    setState(() {
      _queuedPayloads = count;
    });
  }

  Future<void> _loadAllInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;

      final cpu = await platform.invokeMethod('getCPUInfo');
      final ram = await platform.invokeMethod('getRAMInfo');
      final storage = await platform.invokeMethod('getStorageInfo');
      final battery = await platform.invokeMethod('getBatteryInfo');

      setState(() {
        _cpuInfo = cpu != null ? Map<String, dynamic>.from(cpu) : null;
        _ramInfo = ram != null ? Map<String, dynamic>.from(ram) : null;
        _storageInfo = storage != null ? Map<String, dynamic>.from(storage) : null;
        _batteryInfo = battery != null ? Map<String, dynamic>.from(battery) : null;
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Platform Exception: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected Error: $e';
        _isLoading = false;
      });
    }
  }

  // Live Ephemeral Stream Mode (Memory Only - No Disk Storage)
  Future<void> _toggleLiveMonitor(bool value) async {
    if (value) {
      final consent = await PrivacyManager.isLocationConsentGranted();
      if (!consent) {
        final agreed = await PrivacyManager.showConsentDialog(
          context: context,
          title: 'Live Stream Privacy Consent',
          description: 'Enable live in-memory telemetry streaming to monitor GPS, address, RAM, CPU, and Battery status in real time. NO data or logs are saved to device disk storage.',
          featureName: 'Live Monitoring',
        );

        if (!agreed) return;
        await PrivacyManager.setLocationConsent(true);
        setState(() {
          _isLocationEnabled = true;
        });
      }

      setState(() {
        _isLiveMonitorActive = true;
        _liveStreamUpdatesCount = 0;
      });

      // Start high-frequency in-memory GPS stream
      LocationService.startLiveLocationStream((location) {
        if (mounted) {
          setState(() {
            _currentLocation = location;
            _liveStreamUpdatesCount++;
          });
        }

        // Transmit live in-memory telemetry to support server (no disk queuing)
        ApiService.buildTelemetryData(
          locationData: location,
          cpuInfo: _cpuInfo,
          appVersion: '$_appVersion+$_buildNumber',
        ).then((payload) {
          ApiService.sendLiveEphemeralTelemetry(payload);
        });
      });

      // Periodically refresh hardware stats in RAM every 2 seconds
      _liveTelemetryTimer?.cancel();
      _liveTelemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_isLiveMonitorActive) {
          final ram = await platform.invokeMethod('getRAMInfo');
          final battery = await platform.invokeMethod('getBatteryInfo');
          if (mounted) {
            setState(() {
              _ramInfo = ram != null ? Map<String, dynamic>.from(ram) : null;
              _batteryInfo = battery != null ? Map<String, dynamic>.from(battery) : null;
            });
          }
        }
      });
    } else {
      _liveTelemetryTimer?.cancel();
      _liveTelemetryTimer = null;
      LocationService.stopBackgroundLocationUpdates();
      setState(() {
        _isLiveMonitorActive = false;
      });
    }
  }

  // Location Operations
  Future<void> _toggleLocationConsent(bool value) async {
    if (value) {
      final agreed = await PrivacyManager.showConsentDialog(
        context: context,
        title: 'Location Tracking Permission',
        description: 'Allow Hardware Diagnostics to collect precise GPS coordinates and reverse-geocode your address. Data is processed in memory and sent to your private support team API.',
        featureName: 'Location',
      );

      if (agreed) {
        await PrivacyManager.setLocationConsent(true);
        setState(() {
          _isLocationEnabled = true;
        });
        await _fetchLocation();
      }
    } else {
      await PrivacyManager.setLocationConsent(false);
      LocationService.stopBackgroundLocationUpdates();
      setState(() {
        _isLocationEnabled = false;
        _isLiveMonitorActive = false;
        _currentLocation = null;
      });
    }
  }

  Future<void> _fetchLocation() async {
    if (!_isLocationEnabled) return;

    setState(() {
      _isLocationLoading = true;
    });

    final loc = await LocationService.getCurrentLocation();
    setState(() {
      _currentLocation = loc;
      _isLocationLoading = false;
    });
  }

  // Screen Recording Operations
  Future<void> _toggleScreenRecording() async {
    if (_isRecording) {
      final videoFile = await ScreenRecordingService.stopRecording();
      setState(() {
        _isRecording = false;
      });

      if (videoFile != null && await videoFile.exists()) {
        _showVideoUploadDialog(videoFile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screen recording stopped.')),
        );
      }
    } else {
      final consent = await PrivacyManager.isRecordingConsentGranted();
      if (!consent) {
        final agreed = await PrivacyManager.showConsentDialog(
          context: context,
          title: 'Screen Recording Consent',
          description: 'Allow Hardware Diagnostics to record your screen and microphone. Video is compressed and uploaded to your support team API.',
          featureName: 'Screen Recording',
        );

        if (!agreed) return;
        await PrivacyManager.setRecordingConsent(true);
      }

      final started = await ScreenRecordingService.startRecording(audio: _recordAudio);
      if (started) {
        setState(() {
          _isRecording = true;
          _recordedSeconds = 0;
        });

        ScreenRecordingService.timerStream.listen((seconds) {
          if (mounted) {
            setState(() {
              _recordedSeconds = seconds;
            });
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start screen recording. Check system permissions.')),
        );
      }
    }
  }

  void _showVideoUploadDialog(File videoFile) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Upload Screen Recording', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recording file: ${videoFile.path.split('/').last}', style: const TextStyle(color: Color(0xFF94A3B8))),
              const SizedBox(height: 12),
              if (_isUploadingVideo) ...[
                LinearProgressIndicator(
                  value: _videoUploadProgress,
                  backgroundColor: const Color(0xFF334155),
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 8),
                Text('${(_videoUploadProgress * 100).toStringAsFixed(1)}% uploaded...', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ] else ...[
                const Text('Would you like to upload this recording to your support team website API?', style: TextStyle(color: Color(0xFF94A3B8))),
              ]
            ],
          ),
          actions: _isUploadingVideo
              ? []
              : [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Keep Local', style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('Upload to API'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                    onPressed: () async {
                      setDialogState(() {
                        _isUploadingVideo = true;
                        _videoUploadProgress = 0.0;
                      });

                      final success = await ApiService.uploadScreenRecording(
                        videoFile,
                        appVersion: _appVersion,
                        onProgress: (p) {
                          setDialogState(() {
                            _videoUploadProgress = p;
                          });
                        },
                      );

                      setDialogState(() {
                        _isUploadingVideo = false;
                      });

                      if (mounted) Navigator.of(ctx).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success
                              ? 'Screen recording uploaded successfully to support API!'
                              : 'Upload failed. File saved locally.'),
                          backgroundColor: success ? Colors.green : Colors.redAccent,
                        ),
                      );
                    },
                  ),
                ],
        ),
      ),
    );
  }

  // Telemetry API Operations
  Future<void> _sendTelemetryData() async {
    setState(() {
      _isSyncingApi = true;
    });

    final payload = await ApiService.buildTelemetryData(
      locationData: _currentLocation,
      cpuInfo: _cpuInfo,
      appVersion: '$_appVersion+$_buildNumber',
    );

    final success = await ApiService.sendTelemetryPayload(payload);
    await _checkQueuedPayloads();

    setState(() {
      _isSyncingApi = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Telemetry & Location payload sent successfully to support API!'
            : 'API unreachable. Payload queued for automatic retry.'),
        backgroundColor: success ? Colors.green : Colors.orangeAccent,
      ),
    );
  }

  Future<void> _retryPendingQueue() async {
    setState(() {
      _isSyncingApi = true;
    });

    final sentCount = await ApiService.retryQueuedPayloads();
    await _checkQueuedPayloads();

    setState(() {
      _isSyncingApi = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Retried queue: $sentCount payloads sent successfully.'),
        backgroundColor: Colors.indigoAccent,
      ),
    );
  }

  // Standard JSON & Update Actions
  Map<String, dynamic> _collectExportData() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'app_version': '$_appVersion+$_buildNumber',
      'location': _currentLocation != null ? _currentLocation!.toJson() : null,
      'device': {
        'model': _cpuInfo?['model'] ?? 'Unknown',
        'hardware': _cpuInfo?['hardware'] ?? 'Unknown',
        'board': _cpuInfo?['board'] ?? 'Unknown',
        'abis': _cpuInfo?['abis'] ?? [],
      },
      'cpu': {
        'cores': _cpuInfo?['cores'] ?? 0,
        'model': _cpuInfo?['model'] ?? 'Unknown',
      },
      'ram': {
        'total_bytes': _ramInfo?['total'] ?? 0,
        'available_bytes': _ramInfo?['avail'] ?? 0,
        'low_memory': _ramInfo?['lowMemory'] == 1,
      },
      'storage': {
        'total_bytes': _storageInfo?['total'] ?? 0,
        'available_bytes': _storageInfo?['avail'] ?? 0,
      },
      'battery': {
        'level': _batteryInfo?['level'] ?? 0,
        'charging': _batteryInfo?['isCharging'] ?? false,
        'temperature_celsius': _batteryInfo?['temperature'] ?? 0.0,
        'health': _batteryInfo?['health'] ?? 'Unknown',
      }
    };
  }

  Future<void> _exportData() async {
    try {
      final data = _collectExportData();
      final encoder = const JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(data);

      await Share.shareXFiles(
        [
          XFile.fromData(
            utf8.encode(jsonString),
            name: 'hardware_specs.json',
            mimeType: 'application/json',
          )
        ],
        subject: 'Hardware Specifications Export',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export data: $e')),
      );
    }
  }

  Future<void> _checkUpdates() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest'),
      );

      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final latestTag = json['tag_name'] as String;
        final latestVersion = latestTag.replaceAll(RegExp(r'[^\d\.]'), '');

        if (_isNewerVersion(_appVersion, latestVersion)) {
          final assets = json['assets'] as List<dynamic>;
          String? downloadUrl;
          for (var asset in assets) {
            if (asset['name'].toString().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String;
              break;
            }
          }
          downloadUrl ??= json['html_url'] as String;

          _showUpdateAvailableDialog(latestTag, json['body'] ?? '', downloadUrl);
        } else {
          _showNoUpdateDialog();
        }
      } else {
        _showErrorDialog('Failed to check for updates. Status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Network error checking updates: $e');
    }
  }

  bool _isNewerVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length; i++) {
      int currentPart = i < currentParts.length ? currentParts[i] : 0;
      if (latestParts[i] > currentPart) return true;
      if (latestParts[i] < currentPart) return false;
    }
    return false;
  }

  void _showUpdateAvailableDialog(String tag, String releaseNotes, String downloadUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Update Available! 🚀', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $tag is available (Current: v$_appVersion).', style: const TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 12),
            if (releaseNotes.isNotEmpty) ...[
              const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: Text(releaseNotes, style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            child: const Text('Download APK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNoUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Up to Date', style: TextStyle(color: Colors.white)),
        content: Text('You are running the latest version (v$_appVersion).', style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Error', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.redAccent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final ownerController = TextEditingController(text: _githubOwner);
    final repoController = TextEditingController(text: _githubRepo);
    final apiBaseUrlController = TextEditingController(text: _apiBaseUrl);
    final apiTokenController = TextEditingController(text: _apiToken);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Support & API Configuration', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SUPPORT REST API ENDPOINTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
              const SizedBox(height: 8),
              TextField(
                controller: apiBaseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Support API Base URL',
                  hintText: 'e.g., https://support.domain.com/api/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Authorization Token',
                  hintText: 'e.g., Bearer token_secret_123',
                ),
              ),
              const SizedBox(height: 20),
              const Text('GITHUB RELEASES UPDATER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
              const SizedBox(height: 8),
              TextField(
                controller: ownerController,
                decoration: const InputDecoration(
                  labelText: 'GitHub Owner (username)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoController,
                decoration: const InputDecoration(
                  labelText: 'Repository Name',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _githubOwner = ownerController.text.trim();
                _githubRepo = repoController.text.trim();
                _apiBaseUrl = apiBaseUrlController.text.trim();
                _apiToken = apiTokenController.text.trim();
              });

              await ApiService.setApiBaseUrl(_apiBaseUrl);
              await ApiService.setAuthToken(_apiToken);

              if (mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            child: const Text('Save Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(2)} ${suffixes[i]}';
  }

  String _formatTimer(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Diagnostics Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.indigoAccent),
            tooltip: 'Configure Support API & GitHub Repo',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadAllInfo,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllInfo,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Card
                        _buildHeaderCard(),
                        const SizedBox(height: 8),

                        // Live Monitoring Mode (No Disk Storage)
                        _buildLiveMonitorCard(),

                        // Feature 1: Location Tracking Card
                        _buildSectionHeader('Location Tracking & GPS'),
                        _buildLocationCard(),

                        // Feature 2: Screen Recorder Control Card
                        _buildSectionHeader('Screen Recording & Support Upload'),
                        _buildScreenRecordingCard(),

                        // Support REST API Telemetry Card
                        _buildSectionHeader('Support API Sync & Retry Queue'),
                        _buildApiSyncCard(),

                        // System Spec Cards
                        _buildSectionHeader('Processor (CPU)'),
                        _buildCPUCard(),

                        _buildSectionHeader('Memory (RAM)'),
                        _buildRAMCard(),

                        _buildSectionHeader('Storage Space'),
                        _buildStorageCard(),

                        _buildSectionHeader('Battery Details'),
                        _buildBatteryCard(),

                        const SizedBox(height: 24),
                        
                        // Actions
                        ElevatedButton.icon(
                          onPressed: _exportData,
                          icon: const Icon(Icons.share, color: Colors.white),
                          label: const Text('Export Specifications (JSON)', style: TextStyle(fontSize: 16, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _checkUpdates,
                          icon: const Icon(Icons.system_update_alt, color: Colors.indigoAccent),
                          label: const Text('Check for Updates (OTA)', style: TextStyle(fontSize: 16, color: Colors.indigoAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.indigoAccent, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.indigoAccent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4338CA), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SYSTEM MONITORED',
                style: TextStyle(
                  color: Color(0xFF818CF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'v$_appVersion+$_buildNumber',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Support Diagnostics Utility',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Target Support API: ${_apiBaseUrl.isEmpty ? 'Not Configured' : _apiBaseUrl}',
            style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMonitorCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isLiveMonitorActive ? const Color(0xFF0F2942) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isLiveMonitorActive ? const Color(0xFF10B981) : const Color(0xFF334155),
          width: _isLiveMonitorActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sensors,
                    color: _isLiveMonitorActive ? const Color(0xFF10B981) : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  const Text('Live Ephemeral Monitor Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              Switch(
                value: _isLiveMonitorActive,
                activeColor: const Color(0xFF10B981),
                onChanged: _toggleLiveMonitor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: const [
              Icon(Icons.shield, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                'Memory-only live stream. NO location logs saved to disk.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          if (_isLiveMonitorActive) ...[
            const Divider(color: Color(0xFF334155), height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                      SizedBox(width: 6),
                      Text('LIVE STREAMING', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
                const Spacer(),
                Text('Updates: $_liveStreamUpdatesCount', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.location_on, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text('GPS Location Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Switch(
                  value: _isLocationEnabled,
                  activeColor: const Color(0xFF10B981),
                  onChanged: _toggleLocationConsent,
                ),
              ],
            ),
            const Divider(color: Color(0xFF334155)),
            if (!_isLocationEnabled) ...[
              const Text(
                'Location tracking is disabled. Enable to send GPS coordinates and reverse-geocoded address to your support team.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ] else if (_isLocationLoading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_currentLocation != null) ...[
              _buildSpecRow(Icons.my_location, 'Latitude', _currentLocation!.latitude.toStringAsFixed(6)),
              const Divider(color: Color(0xFF334155)),
              _buildSpecRow(Icons.explore, 'Longitude', _currentLocation!.longitude.toStringAsFixed(6)),
              const Divider(color: Color(0xFF334155)),
              _buildSpecRow(Icons.gps_fixed, 'Accuracy', '±${_currentLocation!.accuracy.toStringAsFixed(1)} m'),
              const Divider(color: Color(0xFF334155)),
              _buildSpecRow(Icons.home, 'Address', _currentLocation!.address),
              const Divider(color: Color(0xFF334155)),
              _buildSpecRow(Icons.flag, 'Country', _currentLocation!.country),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _fetchLocation,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh GPS Position'),
                ),
              ),
            ] else ...[
              const Text('Unable to retrieve location. Please check device GPS settings.', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScreenRecordingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.videocam, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Screen & Audio Recorder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                if (_isRecording)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 12),
                        const SizedBox(width: 4),
                        Text(_formatTimer(_recordedSeconds), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(color: Color(0xFF334155)),
            Row(
              children: [
                const Text('Include Microphone Audio', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                const Spacer(),
                Checkbox(
                  value: _recordAudio,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: _isRecording
                      ? null
                      : (val) {
                          setState(() {
                            _recordAudio = val ?? true;
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleScreenRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, color: Colors.white),
                label: Text(_isRecording ? 'Stop Recording & Upload' : 'Start Screen Recording', style: const TextStyle(fontSize: 15, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.redAccent : const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiSyncCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.cloud_sync, color: Color(0xFF6366F1)),
                    SizedBox(width: 8),
                    Text('Support Website Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                if (_queuedPayloads > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$_queuedPayloads Pending', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const Divider(color: Color(0xFF334155)),
            const Text(
              'Transmits location coordinates, device specifications, and battery telemetry directly to your support team REST API endpoint.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncingApi ? null : _sendTelemetryData,
                    icon: const Icon(Icons.send, size: 16, color: Colors.white),
                    label: const Text('Send Telemetry', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                  ),
                ),
                if (_queuedPayloads > 0) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isSyncingApi ? null : _retryPendingQueue,
                    icon: const Icon(Icons.replay, size: 16, color: Colors.orangeAccent),
                    label: const Text('Retry Queue', style: TextStyle(color: Colors.orangeAccent)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orangeAccent)),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCPUCard() {
    final abis = _cpuInfo?['abis'] as List<dynamic>? ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSpecRow(Icons.memory, 'CPU Model', _cpuInfo?['model'] ?? 'Unknown'),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.developer_board, 'Cores', '${_cpuInfo?['cores'] ?? 0} Cores'),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.architecture, 'Board / Hardware', '${_cpuInfo?['board']} / ${_cpuInfo?['hardware']}'),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.settings_suggest, 'Supported ABIs', abis.isEmpty ? 'Unknown' : abis.join(', ')),
          ],
        ),
      ),
    );
  }

  Widget _buildRAMCard() {
    final total = _ramInfo?['total'] as num? ?? 0;
    final avail = _ramInfo?['avail'] as num? ?? 0;
    final used = total - avail;
    final pctUsed = total > 0 ? (used / total) : 0.0;
    final isLowMem = _ramInfo?['lowMemory'] == 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSpecRow(Icons.storage, 'Total Memory', _formatBytes(total)),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.check_circle_outline, 'Available', _formatBytes(avail)),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(
              Icons.warning_amber_rounded,
              'Low Memory Alert',
              isLowMem ? 'ACTIVE' : 'NORMAL',
              valueColor: isLowMem ? Colors.redAccent : Colors.green,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: pctUsed,
              backgroundColor: const Color(0xFF334155),
              color: isLowMem ? Colors.redAccent : Colors.indigoAccent,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Used: ${_formatBytes(used)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Text('${(pctUsed * 100).toStringAsFixed(1)}% Used', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStorageCard() {
    final total = _storageInfo?['total'] as num? ?? 0;
    final avail = _storageInfo?['avail'] as num? ?? 0;
    final used = total - avail;
    final pctUsed = total > 0 ? (used / total) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSpecRow(Icons.disc_full, 'Total Space', _formatBytes(total)),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.cloud_queue, 'Free Space', _formatBytes(avail)),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: pctUsed,
              backgroundColor: const Color(0xFF334155),
              color: const Color(0xFF10B981),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Used: ${_formatBytes(used)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Text('${(pctUsed * 100).toStringAsFixed(1)}% Used', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard() {
    final level = _batteryInfo?['level'] as int? ?? 0;
    final isCharging = _batteryInfo?['isCharging'] as bool? ?? false;
    final temp = _batteryInfo?['temperature'] as double? ?? 0.0;
    final health = _batteryInfo?['health'] as String? ?? 'Unknown';

    Color batteryColor = Colors.green;
    if (level <= 20) {
      batteryColor = Colors.redAccent;
    } else if (level <= 50) {
      batteryColor = Colors.orangeAccent;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSpecRow(
              isCharging ? Icons.battery_charging_full : Icons.battery_std,
              'Battery Level',
              '$level%',
              valueColor: batteryColor,
            ),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.power, 'Charging Status', isCharging ? 'Charging' : 'Discharging'),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(Icons.thermostat, 'Temperature', '${temp.toStringAsFixed(1)} °C'),
            const Divider(color: Color(0xFF334155)),
            _buildSpecRow(
              Icons.healing,
              'Health Status',
              health,
              valueColor: health == 'Good' ? Colors.green : Colors.orangeAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF818CF8)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
