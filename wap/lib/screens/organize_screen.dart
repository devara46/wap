import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_organizer_service.dart';

class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({super.key});

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  String _sourceFolder = '';
  bool _isProcessing = false;
  StreamSubscription? _progressSubscription;
  Map<String, dynamic> _progress = {};
  DateTime? _processStartTime;
  Timer? _processTimeoutTimer;
  List<String> _processedIDs = [];
  bool _showSuccessDialog = false;

  final FileOrganizerService _organizerService = FileOrganizerService();

  @override
  void initState() {
    super.initState();
    _setupProgressListener();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _processTimeoutTimer?.cancel();
    // DON'T dispose the organizer service here - it's a singleton
    // _organizerService.dispose();
    super.dispose();
  }

  void _setupProgressListener() {
    _progressSubscription = _organizerService.progressStream.listen((progress) {
      if (!mounted) return;

      setState(() {
        _progress = progress;
        _isProcessing = progress['isProcessing'] ?? false;
      });

      // Update processed IDs if available
      if (progress.containsKey('processedDesaIDs')) {
        setState(() {
          _processedIDs = List<String>.from(progress['processedDesaIDs'] ?? []);
        });
      }

      final errorMessage = progress['error']?.toString();
      
      // Handle completion (when processing stops and no error)
      if (!_isProcessing && errorMessage == null) {
        _processTimeoutTimer?.cancel();
        
        final current = progress['current'] as int? ?? 0;
        final total = progress['total'] as int? ?? 0;
        
        // Only show success if we actually processed files and haven't shown the dialog yet
        if (current > 0 && total > 0 && !_showSuccessDialog) {
          _showSuccessDialog = true;
          final uniqueCount = _progress['uniqueDesaCount'] as int? ?? 0;
          final movedCount = _progress['movedFiles'] as int? ?? 0;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSuccess(
              'Success', 
              'File organization completed!\n\n'
              '• $movedCount files moved\n'
              '• $uniqueCount unique Desa folders\n'
              '• $current files processed in total'
            );
          });
        }
      }
      
      // Handle errors (only show if not already showing success)
      if (errorMessage != null && errorMessage.isNotEmpty && !_isProcessing) {
        if (!errorMessage.contains('Cancelled by user') && !_showSuccessDialog) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showError('Processing Error', errorMessage);
          });
        }
      }
    }, onError: (error) {
      if (!mounted) return;
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showError('Error', 'Failed to get progress updates: ${error.toString()}');
      });
      
      setState(() => _isProcessing = false);
      _processTimeoutTimer?.cancel();
      _showSuccessDialog = false;
    });
  }

  Future<void> _selectSourceFolder() async {
    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder containing files to organize',
    );
    
    if (selectedDir != null) {
      setState(() {
        _sourceFolder = selectedDir;
        _processedIDs.clear();
        _showSuccessDialog = false;
      });
    }
  }

  Future<void> _startOrganization() async {
    if (_sourceFolder.isEmpty) {
      _showError('Error', 'Please select a source folder');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = {};
      _processedIDs.clear();
      _processStartTime = DateTime.now();
      _showSuccessDialog = false;
    });

    _processTimeoutTimer = Timer(const Duration(minutes: 10), () {
      if (_isProcessing && mounted) {
        _organizerService.cancel();
        _showError('Timeout', 'File organization took too long and was cancelled');
        setState(() => _isProcessing = false);
      }
    });

    try {
      final result = await _organizerService.organizeFilesByID(
        folderPath: _sourceFolder,
        recursive: true,
      );

      // The progress stream will handle the UI updates
      // This just ensures we catch any immediate errors
      if (result['success'] != true && mounted && !_showSuccessDialog) {
        final error = result['error']?.toString() ?? 'Unknown error occurred';
        if (!error.contains('Cancelled by user')) {
          _showError('Processing Failed', error);
        }
      }
      
    } catch (e) {
      if (!mounted) return;
      
      _processTimeoutTimer?.cancel();
      setState(() => _isProcessing = false);
      _showSuccessDialog = false;
      _showError('Error', e.toString());
    }
  }

  void _cancelOrganization() {
    _organizerService.cancel();
    setState(() {
      _isProcessing = false;
      _showSuccessDialog = false;
    });
    _processTimeoutTimer?.cancel();
    _showInfo('Cancelled', 'File organization has been cancelled');
  }

  void _showError(String title, String message) {
    if (!mounted) return;
    
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
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.green)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (_processedIDs.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Processed Desa IDs:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _processedIDs.join(', '),
                  style: const TextStyle(fontSize: 12, fontFamily: 'Monospace'),
                ),
                if (_processedIDs.length > 10) 
                  Text(
                    '... and ${_processedIDs.length - 10} more',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
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

  void _showInfo(String title, String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.blue)),
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

  Widget _buildFolderStructure() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Folder Structure:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Source Folder/\n',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: '    ├── 1234567/          (Kecamatan)\n',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                  TextSpan(
                    text: '    │   └── 1234567890/  (Desa)\n',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                  TextSpan(
                    text: '    │       └── 1234567890_WS.jpg\n',
                    style: TextStyle(color: Colors.green[700]),
                  ),
                  TextSpan(
                    text: '    └── ...',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                ],
              ),
              style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilenameExamples() {
    return Card(
      color: Colors.green[50],
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filename Requirements:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text('• First 10 characters must be numeric'),
            Text('• Minimum filename length: 10 characters'),
            Text('• First 7 chars: Kecamatan ID'),
            Text('• First 10 chars: Desa ID'),
            SizedBox(height: 8),
            Text(
              'Valid Examples:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• 5206010001_WS.jpg'),
            Text('• 1234567890_map.png'),
            Text('• 9876543210_document.tiff'),
            SizedBox(height: 8),
            Text(
              'Invalid Examples:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• ABCDEFGHIJ_map.jpg (not numeric)'),
            Text('• 12345_file.png (too short)'),
            Text('• map_5206010001.jpg (wrong position)'),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_processedIDs.isEmpty || _isProcessing) return const SizedBox();

    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Processing Results:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text('Unique Desa folders created: ${_processedIDs.length}'),
            const SizedBox(height: 8),
            if (_processedIDs.isNotEmpty) ...[
              const Text(
                'Processed Desa IDs:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _processedIDs.take(15).map((id) => Chip(
                  label: Text(id),
                  backgroundColor: Colors.orange[100],
                  labelStyle: const TextStyle(fontSize: 10),
                )).toList(),
              ),
              if (_processedIDs.length > 15)
                Text(
                  '... and ${_processedIDs.length - 15} more',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organize Files by Numeric ID'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.orange,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        actions: [
          if (_isProcessing)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: _cancelOrganization,
              tooltip: 'Cancel Operation',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source Folder Input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Source Folder',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sourceFolder.isEmpty ? 'No folder selected' : _sourceFolder,
                            style: TextStyle(
                              color: _sourceFolder.isEmpty ? Colors.grey : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isProcessing ? null : _selectSourceFolder,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Folder Structure Preview
            _buildFolderStructure(),

            const SizedBox(height: 10),

            // Filename Examples
            _buildFilenameExamples(),

            const SizedBox(height: 10),

            // Results Display
            _buildResults(),

            const SizedBox(height: 24),

            // Action Buttons
            if (!_isProcessing)
              ElevatedButton.icon(
                onPressed: _startOrganization,
                icon: const Icon(Icons.folder_open),
                label: const Text('Organize Files'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelOrganization,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // Progress display
            if (_isProcessing)
              Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _progress['message']?.toString() ?? 'Organizing files...',
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
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Instructions
            const Card(
              color: Color.fromARGB(255, 255, 235, 210),
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
                    Text('• Select folder containing files to organize'),
                    Text('• First 10 characters of filename must be numeric'),
                    Text('• First 7 characters: Kecamatan ID'),
                    Text('• First 10 characters: Desa ID'),
                    Text('• Files will be moved to: KecamatanID/DesaID/'),
                    Text('• Only files with numeric prefixes will be processed'),
                    SizedBox(height: 8),
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