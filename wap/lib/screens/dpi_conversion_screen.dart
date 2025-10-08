import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wap/theme/app_theme.dart';
import 'package:wap/widgets/custom_card.dart';
import 'package:wap/widgets/section_header.dart';
import 'package:wap/services/python_service.dart';

class DpiConversionScreen extends StatefulWidget {
  const DpiConversionScreen({super.key});

  @override
  State<DpiConversionScreen> createState() => _DpiConversionScreenState();
}

class _DpiConversionScreenState extends State<DpiConversionScreen> {
  String _sourceDir = '';
  String _outputDir = '';
  int _targetDpi = 200;
  final TextEditingController _dpiController = TextEditingController();
  bool _isProcessing = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _dpiController.text = _targetDpi.toString();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _processTimeoutTimer?.cancel();
    _dpiController.dispose();
    super.dispose();
  }

  void _updateDpiFromTextField() {
    final text = _dpiController.text;
    if (text.isNotEmpty) {
      final value = int.tryParse(text);
      if (value != null && value >= 72 && value <= 600) {
        setState(() {
          _targetDpi = value;
        });
      } else {
        // Reset to current value if invalid
        _dpiController.text = _targetDpi.toString();
      }
    }
  }

  Future<void> _selectSourceDirectory() async {
    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select source folder with images',
    );
    
    if (selectedDir != null) {
      setState(() {
        _sourceDir = selectedDir;
      });
    }
  }

  Future<void> _selectOutputDirectory() async {
    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select output folder for DPI-converted images',
    );
    
    if (selectedDir != null) {
      setState(() {
        _outputDir = selectedDir;
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

      setState(() => _progress = progress);

      final current = progress['current'] as int? ?? 0;
      final total = progress['total'] as int? ?? 0;
      final isProcessing = progress['is_processing'] as bool? ?? true;
      
      final bool isComplete = !isProcessing || (total > 0 && current >= total);

      if (isComplete) {
        _progressSubscription?.cancel();
        _processTimeoutTimer?.cancel();
        
        final completionError = progress['error']?.toString();
        if (completionError != null && completionError.isNotEmpty) {
          _showError('Processing Failed', completionError);
        } else {
          _showSuccess('Success', 'DPI conversion completed! $current/$total images processed');
        }
        
        setState(() => _isProcessing = false);
      }
    }, onError: (error) {
      _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
    });
  }

  Future<void> _startDpiConversion() async {
    if (_sourceDir.isEmpty || _outputDir.isEmpty) {
      _showError('Error', 'Please select both source and output directories');
      return;
    }

    // Validate DPI input
    _updateDpiFromTextField();
    if (_targetDpi < 72 || _targetDpi > 600) {
      _showError('Invalid DPI', 'Please enter a DPI value between 72 and 600');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = {};
      _processStartTime = DateTime.now();
    });

    _processTimeoutTimer = Timer(const Duration(minutes: 15), () {
      if (_isProcessing) {
        _progressSubscription?.cancel();
        _showError('Timeout', 'DPI conversion took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final startResult = await PythonService.startDpiConversion(
        sourceDir: _sourceDir,
        outputDir: _outputDir,
        targetDpi: _targetDpi,
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
        content: Text(message),
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
        title: Text(title, style: const TextStyle(color: AppTheme.textSelected)),
        content: Text(message),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DPI Conversion'),
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
            // Source Directory Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Source Directory',
                      subtitle: 'Select your source directory'
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sourceDir.isEmpty ? 'No directory selected' : _sourceDir,
                            style: TextStyle(
                              color: _sourceDir.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isProcessing ? null : _selectSourceDirectory,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Output Directory',
                      subtitle: 'Select your destination directory'
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _outputDir.isEmpty ? 'No directory selected' : _outputDir,
                            style: TextStyle(
                              color: _outputDir.isEmpty ? AppTheme.textSecondary : AppTheme.primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isProcessing ? null : _selectOutputDirectory,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ),

            const SizedBox(height: 16),

            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'DPI Settings',
                    subtitle: 'Adjust the target DPI for conversion',
                  ),

                  Text(
                    '$_targetDpi DPI',
                    style: AppTheme.heading3.copyWith(color: AppTheme.textSelected),
                  ),
                  const SizedBox(height: 16),

                  Slider(
                    value: _targetDpi.toDouble(),
                    min: 50,
                    max: 600,
                    divisions: (600 - 50) ~/ 10,
                    label: '$_targetDpi DPI',
                    onChanged: _isProcessing ? null : (value) {
                      setState(() {
                        _targetDpi = value.round();
                        _dpiController.text = _targetDpi.toString();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50 DPI', style: AppTheme.bodySmall,),
                      Text('300 DPI', style: AppTheme.bodySmall,),
                      Text('600 DPI', style: AppTheme.bodySmall,),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Text('Custom DPI', style: AppTheme.bodyMedium),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _dpiController,
                          keyboardType: TextInputType.number,
                          enabled: !_isProcessing,
                          decoration: AppTheme.textInputDecoration,
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null && parsed >= 50 && parsed <= 600) {
                              setState(() {
                                (() {
                                  _targetDpi = parsed;
                                });
                              });
                            }
                          },
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 16),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [50, 100, 150, 200, 300, 400, 600].map((dpi) {
                      final isSelected = _targetDpi == dpi;
                      return ChoiceChip(
                        label: Text(
                          '$dpi DPI', 
                          style: AppTheme.bodyMedium.copyWith(
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: _isProcessing ? null : (bool selected) {
                          if (selected) {
                            setState(() {
                              _targetDpi = dpi;
                              _dpiController.text = dpi.toString();
                            });
                          }
                        },
                        backgroundColor: AppTheme.backgroundColorInactive.shade100,
                        selectedColor: AppTheme.primaryColor.shade100, // Solid color
                        checkmarkColor: AppTheme.primaryColor,
                        elevation: isSelected ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      );
                    }).toList(),
                  ),
                ],
              )
            ),

            const SizedBox(height: 24),

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startDpiConversion,
              icon: const Icon(Icons.photo_size_select_large),
              label: const Text('Start DPI Conversion'),
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
                        _progress['message']?.toString() ?? 'Converting DPI...',
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
                            (_progress['total'] as int? ?? 0) > 0 
                                ? '${_progress['current'] as int? ?? 0} / ${_progress['total'] as int? ?? 0} images'
                                : 'Starting...',
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
                    Text('• Select source folder containing images'),
                    Text('• Select output folder for DPI-converted images'),
                    Text('• Choose target DPI using any method:'),
                    Text('  - Type directly in the text field'),
                    Text('  - Use quick select buttons for common values'),
                    Text('  - Use the slider for fine control'),
                    Text('• Images will be resized to maintain physical dimensions'),
                    Text('• Supports: JPG, JPEG, PNG, TIFF, BMP'),
                    SizedBox(height: 8),
                    Text(
                      'Note: Higher DPI means larger file sizes but better print quality',
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