import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Tailwind slate-900
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Tailwind indigo-500
          brightness: Brightness.dark,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF10B981), // Tailwind emerald-500
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF1E293B), // Tailwind slate-800
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
  String _appVersion = '1.0.0';
  String _buildNumber = '1';

  // GitHub repository configuration for updates checking
  // Users can edit this in the UI to match their own repository
  String _githubOwner = 'your-github-username';
  String _githubRepo = 'your-repo-name';

  @override
  void initState() {
    super.initState();
    _loadAllInfo();
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

      // Platform channel calls
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

  Map<String, dynamic> _collectExportData() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'app_version': '$_appVersion+$_buildNumber',
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
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest'),
      );

      // Dismiss loading indicator
      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final latestTag = json['tag_name'] as String; // e.g., "v1.0.1" or "v1.0.0"
        final latestVersion = latestTag.replaceAll(RegExp(r'[^\d\.]'), ''); // extract digits and dots

        // Simple version comparison
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
      } else if (response.statusCode == 404) {
        _showErrorDialog('Repository or releases not found. Ensure the owner and repository names are configured correctly.');
      } else {
        _showErrorDialog('Failed to check for updates. GitHub API responded with status ${response.statusCode}');
      }
    } catch (e) {
      // Dismiss loading indicator if it's still showing
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
        title: const Text('Update Available! 🚀'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $tag is available (Current: v$_appVersion).'),
            const SizedBox(height: 12),
            if (releaseNotes.isNotEmpty) ...[
              const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                maxHeight: 120,
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: Text(releaseNotes, style: const TextStyle(fontSize: 12)),
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
            child: const Text('Download APK'),
          ),
        ],
      ),
    );
  }

  void _showNoUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Up to Date'),
        content: Text('You are already running the latest version (v$_appVersion).'),
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
        title: const Text('Update Check Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showRepoConfigDialog() {
    final ownerController = TextEditingController(text: _githubOwner);
    final repoController = TextEditingController(text: _githubRepo);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure Updater GitHub Repo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ownerController,
              decoration: const InputDecoration(
                labelText: 'GitHub Owner (username/org)',
                hintText: 'e.g., octocat',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repoController,
              decoration: const InputDecoration(
                labelText: 'Repository Name',
                hintText: 'e.g., my-flutter-app',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _githubOwner = ownerController.text.trim();
                _githubRepo = repoController.text.trim();
              });
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
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
            tooltip: 'Configure GitHub Repo',
            onPressed: _showRepoConfigDialog,
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
                        // App Version and Repo Header Card
                        _buildHeaderCard(),
                        const SizedBox(height: 8),

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
                        
                        // Actions Section
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
          fontSize: 16,
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
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)], // deep indigo
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
            'Local Diagnostics Utility',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Target Updates Repo: $_githubOwner/$_githubRepo',
            style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
          ),
        ],
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
              valueColor: isLowMem ? Colors.redAccent : Colors.emerald,
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
              valueColor: health == 'Good' ? Colors.emerald : Colors.orangeAccent,
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
