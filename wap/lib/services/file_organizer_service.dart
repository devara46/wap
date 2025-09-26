import 'dart:io';
import 'dart:async';

class FileOrganizerService {
  static final FileOrganizerService _instance = FileOrganizerService._internal();
  factory FileOrganizerService() => _instance;
  FileOrganizerService._internal();

  // Stream controllers for progress updates
  final StreamController<Map<String, dynamic>> _progressController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  // Check if string is numeric
  bool _isNumeric(String str) {
    if (str.isEmpty) return false;
    return double.tryParse(str) != null;
  }

  // Organize files by ID pattern
  Future<Map<String, dynamic>> organizeFilesByID({
    required String folderPath,
    bool recursive = true,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    
    // Initialize progress
    _progressController.add({
      'isProcessing': true,
      'current': 0,
      'total': 0,
      'message': 'Scanning files...',
      'error': null,
    });

    try {
      final directory = Directory(folderPath);
      
      // Check if directory exists
      if (!await directory.exists()) {
        final errorResult = {
          'success': false,
          'error': 'Directory does not exist: $folderPath',
          'processedFiles': 0,
          'movedFiles': 0,
          'errorCount': 1,
        };
        _progressController.add({
          'isProcessing': false,
          'error': errorResult['error'],
        });
        completer.complete(errorResult);
        return completer.future;
      }

      // Get all files
      final List<FileSystemEntity> allEntities = await directory.list(recursive: recursive).toList();
      final List<File> allFiles = allEntities.whereType<File>().toList();

      if (allFiles.isEmpty) {
        final errorResult = {
          'success': false,
          'error': 'No files found in the specified folder',
          'processedFiles': 0,
          'movedFiles': 0,
          'errorCount': 0,
        };
        _progressController.add({
          'isProcessing': false,
          'error': errorResult['error'],
        });
        completer.complete(errorResult);
        return completer.future;
      }

      _progressController.add({
        'isProcessing': true,
        'current': 0,
        'total': allFiles.length,
        'message': 'Found ${allFiles.length} files to process',
        'error': null,
      });

      int processedCount = 0;
      int movedCount = 0;
      int errorCount = 0;
      final List<String> errors = [];
      final List<String> processedIDs = [];

      // Process each file
      for (final file in allFiles) {
        try {
          final filename = File(file.path).uri.pathSegments.last;
          final filePath = file.path;

          // Skip if already in subfolder structure (more than 2 levels deep from root)
          final relativePath = filePath.replaceFirst(folderPath, '');
          final pathDepth = relativePath.split(Platform.pathSeparator).length - 1;
          
          if (pathDepth > 2) {
            processedCount++;
            _updateProgress(processedCount, allFiles.length, 'Skipping (already organized): $filename');
            continue;
          }

          // Extract IDs from filename (first 7 and first 10 characters)
          final idKecamatan = filename.length >= 7 ? filename.substring(0, 7) : '';
          final idDesa = filename.length >= 10 ? filename.substring(0, 10) : '';

          // Check if first 10 characters are numeric
          final bool isNumericID = _isNumeric(idDesa);

          if (isNumericID && idKecamatan.length == 7 && idDesa.length == 10) {
            final targetDir = Directory('$folderPath${Platform.pathSeparator}$idKecamatan${Platform.pathSeparator}$idDesa');
            
            // Create directory if it doesn't exist
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
            }

            final targetPath = '${targetDir.path}${Platform.pathSeparator}$filename';

            // Only move if not already in correct location
            if (filePath != targetPath) {
              try {
                await file.rename(targetPath);
                movedCount++;
                if (!processedIDs.contains(idDesa)) {
                  processedIDs.add(idDesa);
                }
                _updateProgress(processedCount, allFiles.length, 'Moved: $filename → $idKecamatan/$idDesa/');
              } catch (e) {
                // If rename fails (across devices), try copy + delete
                try {
                  await File(filePath).copy(targetPath);
                  await file.delete();
                  movedCount++;
                  if (!processedIDs.contains(idDesa)) {
                    processedIDs.add(idDesa);
                  }
                  _updateProgress(processedCount, allFiles.length, 'Moved (copy+delete): $filename → $idKecamatan/$idDesa/');
                } catch (e2) {
                  errorCount++;
                  errors.add('Failed to move $filename: $e2');
                  _updateProgress(processedCount, allFiles.length, 'Error moving: $filename');
                }
              }
            } else {
              _updateProgress(processedCount, allFiles.length, 'Already in place: $filename');
              if (!processedIDs.contains(idDesa)) {
                processedIDs.add(idDesa);
              }
            }
          } else {
            String reason = 'Skipping: $filename';
            if (!isNumericID) {
              reason += ' (first 10 chars not numeric: "$idDesa")';
            } else if (idDesa.length < 10) {
              reason += ' (filename too short: ${filename.length} chars)';
            } else {
              reason += ' (invalid pattern)';
            }
            _updateProgress(processedCount, allFiles.length, reason);
          }

          processedCount++;
          
          // Small delay to prevent UI blocking
          await Future.delayed(const Duration(milliseconds: 10));
          
        } catch (e) {
          errorCount++;
          errors.add('Error processing ${file.path}: $e');
          processedCount++;
          _updateProgress(processedCount, allFiles.length, 'Error processing file');
        }
      }

      // Final result
      final result = {
        'success': true,
        'message': 'Organized $movedCount files into ${processedIDs.length} unique Desa folders',
        'processedFiles': processedCount,
        'movedFiles': movedCount,
        'errorCount': errorCount,
        'totalFiles': allFiles.length,
        'uniqueDesaCount': processedIDs.length,
        'processedDesaIDs': processedIDs.take(10).toList(), // Show first 10 IDs
      };

      if (errors.isNotEmpty) {
        result['errors'] = errors.take(5).toList(); // Limit to first 5 errors
        result['errorMessage'] = 'Completed with $errorCount errors';
      }

      _progressController.add({
        'isProcessing': false,
        'current': processedCount,
        'total': allFiles.length,
        'message': result['message'],
        'error': errors.isNotEmpty ? result['errorMessage'] : null,
      });

      completer.complete(result);
      
    } catch (e) {
      final errorResult = {
        'success': false,
        'error': 'Error organizing files: $e',
        'processedFiles': 0,
        'movedFiles': 0,
        'errorCount': 1,
      };
      
      _progressController.add({
        'isProcessing': false,
        'error': errorResult['error'],
      });
      
      completer.complete(errorResult);
    }

    return completer.future;
  }

  // Helper method to update progress
  void _updateProgress(int current, int total, String message) {
    _progressController.add({
      'isProcessing': true,
      'current': current,
      'total': total,
      'message': message,
      'error': null,
    });
  }

  // Cancel current operation
  void cancel() {
    _progressController.add({
      'isProcessing': false,
      'message': 'Operation cancelled',
      'error': 'Cancelled by user',
    });
  }

  // Dispose the service
  void dispose() {
    _progressController.close();
  }
}