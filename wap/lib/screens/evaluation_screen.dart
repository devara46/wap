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
  String _currentPolygonFilePath = '';
  String _originalPolygonFilePath = '';
  String _outputPath = 'Evaluation_Result.xlsx';
  double _overlapThreshold = 0.5;
  double _sameIdThreshold = 0.1;
  bool _isProcessing = false;
  bool _includeOriginalPolygon = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;
  Map<String, dynamic>? _statistics;

  final TextEditingController _overlapController = TextEditingController();
  final TextEditingController _sameIdController = TextEditingController();

  final List<String> _supportedPolygonFormats = ['geojson', 'json', 'gpkg', 'shp'];
  final List<String> _supportedSipwFormats = ['xlsx', 'xls'];

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current values
    _overlapController.text = (_overlapThreshold * 100).toStringAsFixed(0);
    _sameIdController.text = (_sameIdThreshold * 100).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _overlapController.dispose();
    _sameIdController.dispose();
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

  Future<void> _selectCurrentPolygonFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedPolygonFormats,
      dialogTitle: 'Select Current Polygon File',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _currentPolygonFilePath = result.files.single.path!;
      });
    }
  }

  Future<void> _selectOriginalPolygonFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedPolygonFormats,
      dialogTitle: 'Select Original Polygon File',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _originalPolygonFilePath = result.files.single.path!;
      });
    }
  }

  Future<void> _selectOutputFile() async {
    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Evaluation Report As',
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
    if (_sipwFilePath.isEmpty || _currentPolygonFilePath.isEmpty) {
      _showError('Error', 'Please select both SiPW file and current polygon file');
      return;
    }

    if (_includeOriginalPolygon && _originalPolygonFilePath.isEmpty) {
      _showError('Error', 'Please select original polygon file or disable the option');
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
        polygonPath: _currentPolygonFilePath,
        outputPath: _outputPath,
        comparePolygonPath: _includeOriginalPolygon ? _originalPolygonFilePath : null,
        overlapThreshold: _overlapThreshold,
        sameIdThreshold: _sameIdThreshold, // Add new parameter
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
                if (_statistics!.containsKey('overlapping_polygons_diff'))
                  Text('• Overlapping Polygons (Different IDs): ${_statistics!['overlapping_polygons_diff']}'),
                if (_statistics!.containsKey('overlapping_polygons_same'))
                  Text('• Polygons with Shape Changes (Same ID): ${_statistics!['overlapping_polygons_same']}'),
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

  Widget _buildOriginalPolygonToggle() {
    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.compare_arrows, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compare to Original Polygon',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Compare with original polygon for overlap analysis',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: _includeOriginalPolygon,
              onChanged: _isProcessing ? null : (bool value) {
                setState(() {
                  _includeOriginalPolygon = value;
                });
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOriginalPolygonInput() {
    if (!_includeOriginalPolygon) return const SizedBox();

    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Original Polygon File',
              subtitle: 'Select original polygon for comparison',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _originalPolygonFilePath.isEmpty ? 'No file selected' : _originalPolygonFilePath.split('/').last,
                    style: TextStyle(
                      color: _originalPolygonFilePath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _selectOriginalPolygonFile,
                  child: const Text('Select File'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlapSettings() {
    if (!_includeOriginalPolygon) return const SizedBox();

    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Overlap Analysis Settings',
              subtitle: 'Configure overlap detection sensitivity',
            ),
            const SizedBox(height: 20),

            // Overlap Threshold (Different IDs)
            _buildThresholdSection(
              title: 'Overlap Threshold (Different IDs)',
              subtitle: 'Minimum overlap ratio to detect overlapping polygons with different IDs',
              currentValue: _overlapThreshold,
              onChanged: (value) {
                setState(() {
                  _overlapThreshold = value;
                  _overlapController.text = (_overlapThreshold * 100).toStringAsFixed(0);
                });
              },
              isProcessing: _isProcessing,
              controller: _overlapController,
              min: 0.01,
              max: 1.0,
              quickSelectValues: [0.1, 0.3, 0.5, 0.7, 0.9], // 10%, 30%, 50%, 70%, 90%
            ),

            const SizedBox(height: 24),

            // Same ID Threshold
            _buildThresholdSection(
              title: 'Shape Change Threshold (Same IDs)',
              subtitle: 'Minimum area change ratio to detect shape changes in polygons with same IDs',
              currentValue: _sameIdThreshold,
              onChanged: (value) {
                setState(() {
                  _sameIdThreshold = value;
                  _sameIdController.text = (_sameIdThreshold * 100).toStringAsFixed(0);
                });
              },
              isProcessing: _isProcessing,
              controller: _sameIdController,
              min: 0.01,
              max: 1.0,
              quickSelectValues: [0.05, 0.1, 0.2, 0.3, 0.5], // 5%, 10%, 20%, 30%, 50%
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdSection({
    required String title,
    required String subtitle,
    required double currentValue,
    required ValueChanged<double> onChanged,
    required bool isProcessing,
    required TextEditingController controller,
    required double min,
    required double max,
    required List<double> quickSelectValues,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        
        // Current value display
        Text(
          '${(currentValue * 100).toStringAsFixed(0)}%',
          style: AppTheme.heading3.copyWith(color: AppTheme.textSelected),
        ),
        const SizedBox(height: 16),

        // Slider
        Slider(
          value: currentValue,
          min: min,
          max: max,
          divisions: (max * 100 - min * 100).round(), // 1% increments
          label: '${(currentValue * 100).toStringAsFixed(0)}%',
          onChanged: isProcessing ? null : onChanged,
          activeColor: AppTheme.primaryColor,
          inactiveColor: AppTheme.primaryColor.shade100,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(min * 100).toStringAsFixed(0)}%', style: AppTheme.bodySmall),
            Text('${((min + max) / 2 * 100).toStringAsFixed(0)}%', style: AppTheme.bodySmall),
            Text('${(max * 100).toStringAsFixed(0)}%', style: AppTheme.bodySmall),
          ],
        ),

        const SizedBox(height: 16),

        // Quick select buttons
        Text('Quick Select:', style: AppTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickSelectValues.map((value) {
            return ElevatedButton(
              onPressed: isProcessing ? null : () {
                onChanged(value);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: currentValue == value 
                    ? AppTheme.primaryColor 
                    : AppTheme.primaryColor.shade100,
                foregroundColor: currentValue == value 
                    ? AppTheme.backgroundColor 
                    : AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text('${(value * 100).toStringAsFixed(0)}%'),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Manual input
        Row(
          children: [
            const Text('Custom Value:', style: AppTheme.bodyMedium),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                enabled: !isProcessing,
                decoration: AppTheme.textInputDecoration.copyWith(
                  suffixText: '%',
                  hintText: 'Enter percentage',
                ),
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed >= min * 100 && parsed <= max * 100) {
                    onChanged(parsed / 100);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
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
            const SectionHeader(
              title: 'Evaluation Summary',
            ),
            const SizedBox(height: 12),
            _buildStatItem('Total SiPW Records', _statistics!['total_sipw'].toString()),
            _buildStatItem('Total Polygon Records', _statistics!['total_polygon'].toString()),
            _buildStatItem('Duplicated IDs', _statistics!['duplicates'].toString(), isWarning: true),
            _buildStatItem('SiPW Only Records', _statistics!['sipw_only'].toString(), isWarning: true),
            _buildStatItem('Polygon Only Records', _statistics!['polygon_only'].toString(), isWarning: true),
            _buildStatItem('Name Differences', _statistics!['name_differences'].toString(), isWarning: true),
            _buildStatItem('No Geometry Records', _statistics!['no_geometry'].toString(), isWarning: true),
            if (_statistics!.containsKey('overlapping_polygons_diff'))
              _buildStatItem('Overlapping Polygons (Different IDs)', _statistics!['overlapping_polygons_diff'].toString(), isWarning: true),
            if (_statistics!.containsKey('overlapping_polygons_same'))
              _buildStatItem('Polygons with Shape Changes (Same ID)', _statistics!['overlapping_polygons_same'].toString(), isWarning: true),
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
          Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
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

            // Current Polygon File Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Polygon File',
                      subtitle: 'Please select your polygon file',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _currentPolygonFilePath.isEmpty ? 'No file selected' : _currentPolygonFilePath.split('/').last,
                            style: TextStyle(
                              color: _currentPolygonFilePath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectCurrentPolygonFile,
                          child: const Text('Select File'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Original Polygon Toggle
            _buildOriginalPolygonToggle(),

            const SizedBox(height: 8),

            // Original Polygon Input (conditional)
            _buildOriginalPolygonInput(),

            const SizedBox(height: 8),

            // Overlap Settings (conditional)
            _buildOverlapSettings(),

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
                      if (_includeOriginalPolygon)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Including overlap analysis with ${(_overlapThreshold * 100).toStringAsFixed(0)}% threshold',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor),
                          ),
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
                    Text('• Select current polygon file (GeoJSON, Shapefile, or GeoPackage)'),
                    Text('• Enable "Include Original Polygon" for overlap analysis'),
                    Text('• Select output location for evaluation report'),
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
                    Text('• Overlapping polygons between current and original data (if enabled)'),
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