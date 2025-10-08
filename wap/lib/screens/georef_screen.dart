import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wap/theme/app_theme.dart';
import 'package:wap/widgets/custom_card.dart';
import 'package:wap/widgets/section_header.dart';
import 'package:wap/services/python_service.dart';

class GeorefScreen extends StatefulWidget {
  const GeorefScreen({super.key});

  @override
  State<GeorefScreen> createState() => _GeorefScreenState();
}

class _GeorefScreenState extends State<GeorefScreen> {
  String _geoFilePath = '';
  String _outputDir = '';
  String _fileExtension = 'jgw';
  double _expandPercentage = 5.0;
  int _targetDpi = 200;
  int _landscapeWidth = 3307;
  int _landscapeHeight = 2338;
  int _portraitWidth = 2338;
  int _portraitHeight = 3307;
  bool _isProcessing = false;
  bool _showAdvanced = false; // Advanced settings toggle
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;

  final List<String> _fileExtensions = ['jgw', 'pgw', 'tfw', 'gfw'];
  final List<String> _supportedFormats = ['geojson', 'json', 'gpkg', 'shp', 'dbf', 'shx', 'prj'];

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _processTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectGeoFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedFormats,
      dialogTitle: 'Select Geographic Data File',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _geoFilePath = result.files.single.path!;
      });
    }
  }

  Future<void> _selectOutputDirectory() async {
    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select output folder for world files',
    );
    
    if (selectedDir != null) {
      setState(() {
        _outputDir = selectedDir;
      });
    }
  }

  String _getFileTypeIcon() {
    if (_geoFilePath.isEmpty) return '📁';
    
    final ext = _geoFilePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'geojson':
      case 'json':
        return '📊';
      case 'gpkg':
        return '🗄️';
      case 'shp':
        return '🗺️';
      default:
        return '📁';
    }
  }

  String _getFileTypeText() {
    if (_geoFilePath.isEmpty) return 'No file selected';
    
    final ext = _geoFilePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'geojson':
      case 'json':
        return 'GeoJSON File';
      case 'gpkg':
        return 'GeoPackage File';
      case 'shp':
        return 'Shapefile';
      default:
        return 'Geographic Data File';
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
          final expandUsed = progress['expand_percentage_used'] ?? _expandPercentage / 100;
          final dpiUsed = progress['dpi_used'] ?? _targetDpi;
          _showSuccess('Success', 'World file creation completed! $current world files created with ${(expandUsed * 100).toStringAsFixed(1)}% expansion and $dpiUsed DPI');
        }
        
        setState(() => _isProcessing = false);
      }
    }, onError: (error) {
      _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
    });
  }

  Future<void> _startWorldFileCreation() async {
    if (_geoFilePath.isEmpty || _outputDir.isEmpty) {
      _showError('Error', 'Please select both geographic data file and output directory');
      return;
    }

    // Validate parameters
    if (_expandPercentage < 0 || _expandPercentage > 100) {
      _showError('Error', 'Expand percentage must be between 0 and 100');
      return;
    }

    if (_targetDpi <= 0) {
      _showError('Error', 'DPI must be positive');
      return;
    }

    if (_landscapeWidth <= 0 || _landscapeHeight <= 0 || _portraitWidth <= 0 || _portraitHeight <= 0) {
      _showError('Error', 'All dimensions must be positive');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = {};
      _processStartTime = DateTime.now();
    });

    _processTimeoutTimer = Timer(const Duration(minutes: 10), () {
      if (_isProcessing) {
        _progressSubscription?.cancel();
        _showError('Timeout', 'World file creation took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final startResult = await PythonService.createWorldFiles(
        geojsonPath: _geoFilePath,
        outputDir: _outputDir,
        fileExtension: _fileExtension,
        expandPercentage: _expandPercentage / 100,
        targetDpi: _targetDpi,
        landscapeWidth: _landscapeWidth,
        landscapeHeight: _landscapeHeight,
        portraitWidth: _portraitWidth,
        portraitHeight: _portraitHeight,
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

  String _getElapsedTime() {
    if (_processStartTime == null) return '0s';
    final duration = DateTime.now().difference(_processStartTime!);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }

  Widget _buildExpandPercentageSlider() {
    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Expand Percentage',
              subtitle: 'Adjust the expand percentage based on your layout',
            ),
            const SizedBox(height: 8),
            Text(
              '${_expandPercentage.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _expandPercentage,
              min: 0,
              max: 50,
              divisions: 100,
              label: _expandPercentage.toStringAsFixed(1),
              onChanged: _isProcessing ? null : (double value) {
                setState(() {
                  _expandPercentage = value;
                });
              },
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: TextStyle(fontSize: 12)),
                Text('25%', style: TextStyle(fontSize: 12)),
                Text('50%', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Expands the bounds of each polygon by ${_expandPercentage.toStringAsFixed(1)}% to ensure proper coverage.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButtons() {
    final List<Map<String, dynamic>> presets = [
      {'label': 'No Expansion', 'value': 0.0},
      {'label': 'Small (2%)', 'value': 2.0},
      {'label': 'Default (5%)', 'value': 5.0},
      {'label': 'Medium (10%)', 'value': 10.0},
      {'label': 'Large (20%)', 'value': 20.0},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((preset) {
        return FilterChip(
          label: Text(preset['label']),
          selected: _expandPercentage == preset['value'],
          onSelected: _isProcessing ? null : (bool selected) {
            if (selected) {
              setState(() {
                _expandPercentage = preset['value'];
              });
            }
          },
          backgroundColor: AppTheme.backgroundColorInactive.shade100,
          selectedColor: AppTheme.primaryColor.shade100,
          checkmarkColor: AppTheme.primaryColor,
          labelStyle: TextStyle(
            color: _expandPercentage == preset['value'] ? AppTheme.primaryColor : AppTheme.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDpiSettings() {
    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'DPI Settings',
              subtitle: 'Adjust the target DPI for conversion',
            ),
            const SizedBox(height: 8),
            
            // DPI Slider
            Text(
              '$_targetDpi DPI',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _targetDpi.toDouble(),
              min: 50, // Start from 50
              max: 600,
              divisions: (600 - 50) ~/ 10, // Calculate divisions for 10-step increments
              label: '$_targetDpi DPI',
              onChanged: _isProcessing ? null : (double value) {
                setState(() {
                  _targetDpi = value.round();
                });
              },
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('50 DPI', style: TextStyle(fontSize: 12)),
                Text('300 DPI', style: TextStyle(fontSize: 12)),
                Text('600 DPI', style: TextStyle(fontSize: 12)),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // DPI Input and Presets
            Row(
              children: [
                const Text('Custom DPI:'),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _targetDpi.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) {
                      final dpi = int.tryParse(value);
                      if (dpi != null && dpi >= 50 && dpi <= 600) {
                        setState(() {
                          _targetDpi = dpi;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // DPI Presets - Updated to include lower values
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [50, 100, 150, 200, 300, 400, 600].map((dpi) {
                return FilterChip(
                  label: Text('$dpi DPI'),
                  selected: _targetDpi == dpi,
                  onSelected: _isProcessing ? null : (bool selected) {
                    if (selected) {
                      setState(() {
                        _targetDpi = dpi;
                      });
                    }
                  },
                  backgroundColor: AppTheme.backgroundColorInactive.shade100,
                  selectedColor: AppTheme.primaryColor.shade100,
                  checkmarkColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: _targetDpi == dpi ? AppTheme.primaryColor : AppTheme.textPrimary,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionSettings() {
    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Image Dimensions (pixels)',
              subtitle: 'Adjust to your image dimensions',
            ),
            const SizedBox(height: 8),
            
            // Landscape Dimensions
            const Text('Landscape Orientation:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _landscapeWidth.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final width = int.tryParse(value);
                      if (width != null && width > 0) {
                        setState(() {
                          _landscapeWidth = width;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _landscapeHeight.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final height = int.tryParse(value);
                      if (height != null && height > 0) {
                        setState(() {
                          _landscapeHeight = height;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Portrait Dimensions
            const Text('Portrait Orientation:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _portraitWidth.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final width = int.tryParse(value);
                      if (width != null && width > 0) {
                        setState(() {
                          _portraitWidth = width;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _portraitHeight.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final height = int.tryParse(value);
                      if (height != null && height > 0) {
                        setState(() {
                          _portraitHeight = height;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            Text(
              'Current settings: Landscape $_landscapeWidth×$_landscapeHeight, Portrait $_portraitWidth×$_portraitHeight',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedToggle() {
    return CustomCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.settings, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            const Expanded(
              child: SectionHeader(
                title: 'Advanced Settings',
                subtitle: 'Turn on to use custom settings',
              ),
            ),
            Switch(
              value: _showAdvanced,
              onChanged: _isProcessing ? null : (bool value) {
                setState(() {
                  _showAdvanced = value;
                });
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create World Files'),
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
            // Geographic File Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Geographic Data File',
                      subtitle: 'Select your source directory',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _getFileTypeIcon(),
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getFileTypeText(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _geoFilePath.isEmpty ? AppTheme.backgroundColorInactive : AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _geoFilePath.isEmpty ? 'No file selected' : _geoFilePath,
                                style: TextStyle(
                                  color: _geoFilePath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectGeoFile,
                          child: const Text('Select File'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Output Directory Input
            CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Output Directory',
                      subtitle: 'Select your destination directory',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _outputDir.isEmpty ? 'No directory selected' : _outputDir,
                            style: TextStyle(
                              color: _outputDir.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectOutputDirectory,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Advanced Settings Toggle
            _buildAdvancedToggle(),

            // Advanced Settings (only show when toggle is on)
            if (_showAdvanced) ...[
              const SizedBox(height: 16),

              // Expand Percentage Slider
              _buildExpandPercentageSlider(),

              const SizedBox(height: 8),

              // Preset Buttons for Expand Percentage
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildPresetButtons(),
              ),

              const SizedBox(height: 16),

              // DPI Settings
              _buildDpiSettings(),

              const SizedBox(height: 16),

              // Dimension Settings
              _buildDimensionSettings(),

              const SizedBox(height: 16),

              // File Extension Selection
              CustomCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                        title: 'World File Extension',
                        subtitle: 'Select in accordance to your image extension',
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _fileExtension,
                        items: _fileExtensions.map((String extension) {
                          return DropdownMenuItem<String>(
                            value: extension,
                            child: Text('.$extension'),
                          );
                        }).toList(),
                        onChanged: _isProcessing ? null : (String? newValue) {
                          setState(() {
                            _fileExtension = newValue!;
                          });
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startWorldFileCreation,
              icon: const Icon(Icons.create),
              label: const Text('Create World Files'),
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
                        _progress['message']?.toString() ?? 'Creating world files...',
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
                                ? '${_progress['current'] as int? ?? 0} / ${_progress['total'] as int? ?? 0} files'
                                : 'Starting...',
                          ),
                          Text(
                            'Elapsed: ${_getElapsedTime()}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                      if (_expandPercentage > 0 || _targetDpi != 200)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Using ${_expandPercentage.toStringAsFixed(1)}% expansion and $_targetDpi DPI',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSelected),
                          ),
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
                    Text('• Select a geographic data file (GeoJSON, GPKG, or SHP)'),
                    Text('• File must contain polygon geometry and "idsls" column'),
                    Text('• Select output folder for world files'),
                    Text('• Use advanced settings for custom DPI, dimensions, and expansion'),
                    Text('• World files will be created for each polygon feature'),
                    SizedBox(height: 8),
                    Text(
                      'Default settings: 200 DPI, 5% expansion, standard dimensions',
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