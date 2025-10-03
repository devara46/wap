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

  // DPI conversion
  static Future<Map<String, dynamic>> startDpiConversion({
    required String sourceDir,
    required String outputDir,
    required int targetDpi,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/convert_dpi'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'source_dir': sourceDir,
          'dest_dir': outputDir,
          'target_dpi': targetDpi,
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

  static Future<Map<String, dynamic>> createWorldFiles({
    required String geojsonPath,
    required String outputDir,
    String fileExtension = 'jgw',
    double expandPercentage = 0.05,
    int targetDpi = 200, // Default to 200 DPI
    int landscapeWidth = 3307, // Default dimensions
    int landscapeHeight = 2338,
    int portraitWidth = 2338,
    int portraitHeight = 3307,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5000/create_world_files'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'geojson_path': geojsonPath,
          'output_dir': outputDir,
          'file_extension': fileExtension,
          'expand_percentage': expandPercentage,
          'target_dpi': targetDpi,
          'landscape_width': landscapeWidth,
          'landscape_height': landscapeHeight,
          'portrait_width': portraitWidth,
          'portrait_height': portraitHeight,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      return {
        'error': 'Failed to connect to server: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> evaluateSipw({
    required String sipwPath,
    required String polygonPath,
    String outputPath = 'Evaluation_Result.xlsx',
  }) async {
    try {
      print('Sending request to evaluate_sipw endpoint...');
      print('SiPW Path: $sipwPath');
      print('Polygon Path: $polygonPath');
      print('Output Path: $outputPath');

      // First, test the connection
      final testResponse = await http.get(
        Uri.parse('http://localhost:5000/health'),
        headers: {'Content-Type': 'application/json'},
      );

      if (testResponse.statusCode != 200) {
        return {
          'error': 'Server is not responding. Status: ${testResponse.statusCode}',
        };
      }

      final response = await http.post(
        Uri.parse('http://localhost:5000/evaluate_sipw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sipw_path': sipwPath,
          'polygon_path': polygonPath,
          'output_path': outputPath,
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print('Error in evaluateSipw: $e');
      return {
        'error': 'Failed to connect to server: $e',
      };
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