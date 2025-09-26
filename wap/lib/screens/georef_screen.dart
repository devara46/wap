import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/python_service.dart';

class GeorefScreen extends StatefulWidget {
  const GeorefScreen({super.key});

  @override
  State<GeorefScreen> createState() => _GeorefScreenState();
}

class _GeorefScreenState extends State<GeorefScreen> {
  String _geoFilePath = '';
  String _outputDir = '';
  String _fileExtension = 'jgw';
  double _expandPercentage = 5.0; // Default to 5%
  bool _isProcessing = false;
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
          _showSuccess('Success', 'World file creation completed! $current world files created with ${(expandUsed * 100).toStringAsFixed(1)}% expansion');
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

    // Validate expand percentage
    if (_expandPercentage < 0 || _expandPercentage > 100) {
      _showError('Error', 'Expand percentage must be between 0 and 100');
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
        expandPercentage: _expandPercentage / 100, // Convert to decimal
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
        title: Text(title, style: const TextStyle(color: Colors.green)),
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

  Widget _buildExpandPercentageSlider() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expand Percentage',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '${_expandPercentage.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
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
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
          backgroundColor: Colors.grey[200],
          selectedColor: Colors.blue[100],
          checkmarkColor: Colors.blue,
          labelStyle: TextStyle(
            color: _expandPercentage == preset['value'] ? Colors.blue : Colors.black,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create World Files'),
        backgroundColor: Colors.green,
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Geographic Data File',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                      color: _geoFilePath.isEmpty ? Colors.grey : Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _geoFilePath.isEmpty ? 'No file selected' : _geoFilePath,
                                style: TextStyle(
                                  color: _geoFilePath.isEmpty ? Colors.grey : Colors.black54,
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Output Directory',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _outputDir.isEmpty ? 'No directory selected' : _outputDir,
                            style: TextStyle(
                              color: _outputDir.isEmpty ? Colors.grey : Colors.black,
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

            // Expand Percentage Slider
            _buildExpandPercentageSlider(),

            const SizedBox(height: 8),

            // Preset Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: _buildPresetButtons(),
            ),

            const SizedBox(height: 16),

            // File Extension Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'World File Extension',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

            const SizedBox(height: 24),

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startWorldFileCreation,
              icon: const Icon(Icons.create),
              label: const Text('Create World Files'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // Progress display
            if (_isProcessing)
              Card(
                color: Colors.green[50],
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
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (_expandPercentage > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Using ${_expandPercentage.toStringAsFixed(1)}% expansion',
                            style: const TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Instructions
            const Card(
              color: Color.fromARGB(255, 210, 255, 210),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text('• Select a geographic data file (GeoJSON, GPKG, or SHP)'),
                    Text('• File must contain polygon geometry and "idsls" column'),
                    Text('• Select output folder for world files'),
                    Text('• Adjust expansion percentage as needed'),
                    Text('• Choose appropriate world file extension'),
                    Text('• World files will be created for each polygon feature'),
                    SizedBox(height: 8),
                    Text(
                      'Expand Percentage: Increases bounds to ensure full coverage. Use higher values for irregular shapes.',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                    Text(
                      'Supported formats: GeoJSON (.geojson, .json), GeoPackage (.gpkg), Shapefile (.shp)',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                    Text(
                      'Supported extensions: .jgw (JPEG), .pgw (PNG), .tfw (TIFF), .gfw (GIF)',
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