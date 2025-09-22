import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class PythonService {
  static const String baseUrl = 'http://localhost:5000';
  
  // Check if Python server is running
  static Future<bool> isServerRunning() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Start batch process (returns immediately)
  static Future<Map<String, dynamic>> startBatchProcess({
    required String sourceDir,
    required String outputDir,
    required bool shouldRotate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/batch_process'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'source': sourceDir,
          'dest': outputDir,
          'rotate': shouldRotate,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server error: ${response.statusCode}'};
      }
    } on TimeoutException {
      return {'error': 'Request timeout - Server took too long to respond'};
    } on SocketException {
      return {'error': 'Cannot connect to server'};
    } catch (e) {
      return {'error': 'Unexpected error: $e'};
    }
  }

  // Batch rename images (without rotation)
  static Future<Map<String, dynamic>> startBatchRename({
    required String sourceDir,
    required String outputDir,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/batch_rename'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'source': sourceDir,
          'dest': outputDir,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server error: ${response.statusCode}'};
      }
    } on TimeoutException {
      return {'error': 'Request timeout - Server took too long to respond'};
    } on SocketException {
      return {'error': 'Cannot connect to server'};
    } catch (e) {
      return {'error': 'Unexpected error: $e'};
    }
  }

  // Batch rotate images (without renaming)
  static Future<Map<String, dynamic>> startBatchRotate({
    required String sourceDir,
    required String outputDir,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/batch_rotate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'source': sourceDir,
          'dest': outputDir,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server error: ${response.statusCode}'};
      }
    } on TimeoutException {
      return {'error': 'Request timeout - Server took too long to respond'};
    } on SocketException {
      return {'error': 'Cannot connect to server'};
    } catch (e) {
      return {'error': 'Unexpected error: $e'};
    }
  }

  // Geo analysis - check off points
  static Future<Map<String, dynamic>> checkOffPoints({
    required String pointFile,
    required String polygonFile,
    required String level,
    required String outputFile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/search_off_point'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'point_path': pointFile,
          'polygon_path': polygonFile,
          'level': level,
          'output_file': outputFile,
        }),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'error': 'Server error: ${response.statusCode}'};
      }
    } on TimeoutException {
      return {'error': 'Request timeout - Analysis took too long'};
    } on SocketException {
      return {'error': 'Cannot connect to server'};
    } catch (e) {
      return {'error': 'Unexpected error: $e'};
    }
  }

  // Get progress updates
  static Stream<Map<String, dynamic>> getProgress() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final response = await http.get(Uri.parse('$baseUrl/progress'))
            .timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          yield json.decode(response.body);
        }
      } catch (e) {
        yield {'error': 'Failed to get progress: $e'};
        break;
      }
    }
  }

  // Test server connection
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      return {
        'success': true,
        'statusCode': response.statusCode,
        'message': 'Server is running'
      };
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Connection timeout - Server not responding'
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'Cannot connect to server - Check if Python server is running'
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Unexpected error: $e'
      };
    }
  }

  // Download result file
  static Future<File?> downloadFile(String filename) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/download/$filename'))
          .timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final directory = Directory.systemTemp;
        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}