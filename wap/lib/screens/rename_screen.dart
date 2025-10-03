import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/python_service.dart';

class RenameScreen extends StatefulWidget {
  const RenameScreen({super.key});

  @override
  State<RenameScreen> createState() => _RenameScreenState();
}

class _RenameScreenState extends State<RenameScreen> {
  String _sourceDir = '';
  String _outputDir = '';
  bool _isProcessing = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _processTimeoutTimer?.cancel();
    super.dispose();
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
      dialogTitle: 'Select output folder for renamed images',
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
          _showSuccess('Success', 'Renaming completed! $current/$total images processed');
        }
        
        setState(() => _isProcessing = false);
      }
    }, onError: (error) {
      _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
    });
  }

  Future<void> _startRenaming() async {
    if (_sourceDir.isEmpty || _outputDir.isEmpty) {
      _showError('Error', 'Please select both source and output directories');
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
        _showError('Timeout', 'Renaming took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final startResult = await PythonService.startBatchRename(
        sourceDir: _sourceDir,
        outputDir: _outputDir,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Rename Images'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue,
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Source Directory',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sourceDir.isEmpty ? 'No directory selected' : _sourceDir,
                            style: TextStyle(
                              color: _sourceDir.isEmpty ? Colors.grey : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectSourceDirectory,
                          child: const Text('Browse'),
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

            const SizedBox(height: 24),

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startRenaming,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Renaming'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // Progress display
            if (_isProcessing)
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _progress['message']?.toString() ?? 'Renaming images...',
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
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Instructions
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text('• Select source folder containing images with QR codes'),
                    Text('• Select output folder for renamed images'),
                    Text('• Images will be renamed based on detected QR code content'),
                    Text('• Original files remain unchanged'),
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