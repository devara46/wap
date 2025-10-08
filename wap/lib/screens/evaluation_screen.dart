import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wap/theme/app_theme.dart';
import 'package:wap/widgets/custom_card.dart';
import 'package:wap/widgets/section_header.dart';
import 'package:wap/services/python_service.dart';

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key});

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  String _sipwFilePath = '';
  String _polygonFilePath = '';
  String _outputPath = 'Evaluation_Result.xlsx';
  bool _isProcessing = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;
  Map<String, dynamic>? _statistics;

  final List<String> _supportedPolygonFormats = ['geojson', 'json', 'gpkg', 'shp'];
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

  Future<void> _selectPolygonFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedPolygonFormats,
      dialogTitle: 'Select Polygon File',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _polygonFilePath = result.files.single.path!;
      });
    }
  }

  Future<void> _selectOutputFile() async {
    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Evaluation Report As',
      fileName: _outputPath,
      allowedExtensions: ['xlsx'],
    );
    
    if (selectedPath != null) {
      setState(() {
        _outputPath = selectedPath.endsWith('.xlsx') ? selectedPath : '$selectedPath.xlsx';
      });
    }
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
          _showSuccess('Success', 'Evaluation completed successfully! Report saved to $_outputPath');
        }
        
        setState(() => _isProcessing = false);
      }
    }, onError: (error) {
      _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
    });
  }

  Future<void> _startEvaluation() async {
    if (_sipwFilePath.isEmpty || _polygonFilePath.isEmpty) {
      _showError('Error', 'Please select both SiPW file and polygon file');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = {};
      _statistics = null;
      _processStartTime = DateTime.now();
    });

    _processTimeoutTimer = Timer(const Duration(minutes: 5), () {
      if (_isProcessing) {
        _progressSubscription?.cancel();
        _showError('Timeout', 'Evaluation took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final startResult = await PythonService.evaluateSipw(
        sipwPath: _sipwFilePath,
        polygonPath: _polygonFilePath,
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
                  'Evaluation Summary:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('• Total SiPW Records: ${_statistics!['total_sipw']}'),
                Text('• Total Polygon Records: ${_statistics!['total_polygon']}'),
                Text('• Duplicated IDs: ${_statistics!['duplicates']}'),
                Text('• SiPW Only Records: ${_statistics!['sipw_only']}'),
                Text('• Polygon Only Records: ${_statistics!['polygon_only']}'),
                Text('• Name Differences: ${_statistics!['name_differences']}'),
                Text('• Records Without Geometry: ${_statistics!['no_geometry']}'),
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

    return Card(
      color: AppTheme.primaryColor.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evaluation Summary',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildStatItem('Total SiPW Records', _statistics!['total_sipw'].toString()),
            _buildStatItem('Total Polygon Records', _statistics!['total_polygon'].toString()),
            _buildStatItem('Duplicated IDs', _statistics!['duplicates'].toString(), isWarning: true),
            _buildStatItem('SiPW Only Records', _statistics!['sipw_only'].toString(), isWarning: true),
            _buildStatItem('Polygon Only Records', _statistics!['polygon_only'].toString(), isWarning: true),
            _buildStatItem('Name Differences', _statistics!['name_differences'].toString(), isWarning: true),
            _buildStatItem('No Geometry Records', _statistics!['no_geometry'].toString(), isWarning: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isWarning && int.parse(value) > 0 ? AppTheme.errorColor : AppTheme.successColor,
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
        title: const Text('Wilkerstat Evaluation'),
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
                      subtitle: 'Please select your SiPW export file',
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

            // Polygon File Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Polygon File',
                      subtitle: 'Please select you polygon file',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _polygonFilePath.isEmpty ? 'No file selected' : _polygonFilePath.split('/').last,
                            style: TextStyle(
                              color: _polygonFilePath.isEmpty ? AppTheme.textSecondary : AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectPolygonFile,
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
                      subtitle: 'Select your output destination',
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

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startEvaluation,
              icon: const Icon(Icons.analytics),
              label: const Text('Start Evaluation'),
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
                        _progress['message']?.toString() ?? 'Evaluating data...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: (_progress['total'] as int? ?? 0) > 0 
                            ? (_progress['current'] as int? ?? 0) / (_progress['total'] as int? ?? 1) 
                            : null,
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
                      title: 'Instructions:',
                    ),
                    SizedBox(height: 8),
                    Text('• Select SiPW Excel file (export_sipw_*.xlsx)'),
                    Text('• Select polygon file (GeoJSON, Shapefile, or GeoPackage)'),
                    Text('• Choose output location for evaluation report'),
                    Text('• Click "Start Evaluation" to begin analysis'),
                    SizedBox(height: 8),
                    Text(
                      'The evaluation will check for:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('• Duplicated sub-SLS IDs in polygon data'),
                    Text('• Records that exist only in SiPW or only in polygon'),
                    Text('• Name differences between SiPW and polygon'),
                    Text('• Polygon records without geometry'),
                    SizedBox(height: 8),
                    Text(
                      'Output will be an Excel file with multiple sheets containing detailed results.',
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