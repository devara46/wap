import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wap/theme/app_theme.dart';
import 'package:wap/widgets/custom_card.dart';
import 'package:wap/widgets/section_header.dart';
import 'package:wap/services/python_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _sipwFilePath = '';
  String _outputPath = 'SIPW_Report.xlsx';
  bool _isProcessing = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;
  Map<String, dynamic>? _statistics;

  final List<String> _supportedSipwFormats = ['xlsx', 'xls'];

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _processTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectSipwFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedSipwFormats,
      dialogTitle: 'Select SiPW Excel File',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _sipwFilePath = result.files.single.path!;
      });
    }
  }

  Future<void> _selectOutputFile() async {
    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Report As',
      fileName: _getSafeFileName(_outputPath),
      allowedExtensions: ['xlsx'],
    );
    
    if (selectedPath != null) {
      setState(() {
        _outputPath = selectedPath.endsWith('.xlsx') ? selectedPath : '$selectedPath.xlsx';
      });
    }
  }

  String _getSafeFileName(String path) {
    // Extract just the file name from the path
    String fileName = path.split(RegExp(r'[\\/]')).last;
    
    // Remove or replace reserved characters
    final reservedChars = RegExp(r'[<>:"/\\|?*]');
    fileName = fileName.replaceAll(reservedChars, '_');
    
    // Ensure the file name is not empty
    if (fileName.isEmpty) {
      fileName = 'SIPW_Report.xlsx';
    }
    
    return fileName;
  }

  void _listenForProgress() {
    _progressSubscription = PythonService.getProgress().listen((progress) {
      final errorMessage = progress['error']?.toString();
      if (errorMessage != null && errorMessage.isNotEmpty) {
        _showError('Progress Error', errorMessage);
        _progressSubscription?.cancel();
        setState(() => _isProcessing = false);
        _processTimeoutTimer?.cancel();
        return;
      }

      setState(() {
        _progress = progress;
        _statistics = progress['statistics'];
      });

      final isProcessing = progress['is_processing'] as bool? ?? true;
      
      if (!isProcessing) {
        _progressSubscription?.cancel();
        _processTimeoutTimer?.cancel();
        
        final completionError = progress['error']?.toString();
        if (completionError != null && completionError.isNotEmpty) {
          _showError('Processing Failed', completionError);
        } else {
          _showSuccess('Success', 'Report generated successfully! Saved to $_outputPath');
        }
        
        setState(() => _isProcessing = false);
      }
    }, onError: (error) {
      _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
    });
  }

  Future<void> _generateReport() async {
    if (_sipwFilePath.isEmpty) {
      _showError('Error', 'Please select SiPW file');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = {};
      _statistics = null;
      _processStartTime = DateTime.now();
    });

    _processTimeoutTimer = Timer(const Duration(minutes: 3), () {
      if (_isProcessing) {
        _progressSubscription?.cancel();
        _showError('Timeout', 'Report generation took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final startResult = await PythonService.generateSipwReport(
        sipwPath: _sipwFilePath,
        outputPath: _outputPath,
      );

      if (startResult.containsKey('error')) {
        _showError('Failed to start', startResult['error']?.toString() ?? 'Unknown error');
        setState(() => _isProcessing = false);
        _processTimeoutTimer?.cancel();
        return;
      }

      _listenForProgress();

    } catch (e) {
      _processTimeoutTimer?.cancel();
      setState(() => _isProcessing = false);
      _showError('Error', e.toString());
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: AppTheme.successColor)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (_statistics != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Report Summary:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('• Total Kecamatan: ${_statistics!['total_kecamatan']}'),
                Text('• Total SLS: ${_statistics!['total_sls']}'),
                Text('• Total Sub-SLS: ${_statistics!['total_subsls']}'),
                if (_statistics!.containsKey('total_muatan'))
                  Text('• Total Muatan: ${_statistics!['total_muatan']?.toStringAsFixed(0)}'),
                if (_statistics!.containsKey('mean_muatan'))
                  Text('• Rata-rata Muatan: ${_statistics!['mean_muatan']?.toStringAsFixed(2)}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getElapsedTime() {
    if (_processStartTime == null) return '0s';
    final duration = DateTime.now().difference(_processStartTime!);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }

  Widget _buildStatisticsCard() {
    if (_statistics == null) return const SizedBox();

    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Report Summary',
            ),
            const SizedBox(height: 12),
            _buildStatItem('Total Kecamatan', _statistics!['total_kecamatan'].toString()),
            _buildStatItem('Total SLS', _statistics!['total_sls'].toString()),
            _buildStatItem('Total Sub-SLS', _statistics!['total_subsls'].toString()),
            if (_statistics!.containsKey('total_muatan'))
              _buildStatItem('Total Muatan', _statistics!['total_muatan']?.toStringAsFixed(0) ?? '0'),
            if (_statistics!.containsKey('mean_muatan'))
              _buildStatItem('Rata-rata Muatan', _statistics!['mean_muatan']?.toStringAsFixed(2) ?? '0'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.successColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SiPW Report Generator'),
        foregroundColor: AppTheme.backgroundColor,
        backgroundColor: AppTheme.primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SiPW File Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'SiPW Excel File',
                      subtitle: 'Select your SiPW export file for analysis',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sipwFilePath.isEmpty ? 'No file selected' : _sipwFilePath.split('/').last,
                            style: TextStyle(
                              color: _sipwFilePath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectSipwFile,
                          child: const Text('Select File'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Output File Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Output File',
                      subtitle: 'Select destination for the generated report',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _outputPath,
                            style: const TextStyle(
                              color: AppTheme.textSelected,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectOutputFile,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Generate Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _generateReport,
              icon: const Icon(Icons.summarize),
              label: const Text('Generate Report'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: AppTheme.backgroundColor,
              ),
            ),

            const SizedBox(height: 20),

            // Progress display
            if (_isProcessing)
              Card(
                color: AppTheme.primaryColor.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _progress['message']?.toString() ?? 'Generating report...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: (_progress['total'] as int? ?? 0) > 0 
                            ? (_progress['current'] as int? ?? 0) / (_progress['total'] as int? ?? 1) 
                            : null,
                        color: AppTheme.primaryColor,
                        backgroundColor: AppTheme.primaryColor.shade100,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Processing...',
                            style: TextStyle(
                              color: AppTheme.primaryColor.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Elapsed: ${_getElapsedTime()}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Statistics Display
            _buildStatisticsCard(),

            const SizedBox(height: 20),

            // Instructions
            const InstructionCard(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'Report Contents:',
                    ),
                    SizedBox(height: 8),
                    Text('• Jumlah SLS/Sub-SLS: Rekapitulasi jumlah SLS dan Sub-SLS per kecamatan'),
                    Text('• Statistik Muatan: Total dan rata-rata muatan per kecamatan'),
                    Text('• Konsentrasi Ekonomi: Distribusi kategori ekonomi dominan per kecamatan'),
                    SizedBox(height: 8),
                    Text(
                      'Supported Analysis:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('• Analisis jumlah SLS dan Sub-SLS'),
                    Text('• Statistik muatan total dan usaha'),
                    Text('• Distribusi kategori ekonomi dominan (1-13)'),
                    Text('• Rekapitulasi per kecamatan'),
                    SizedBox(height: 8),
                    Text(
                      'The report will be generated as an Excel file with multiple sheets.',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}