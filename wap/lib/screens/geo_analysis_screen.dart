import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/python_service.dart';

class GeoAnalysisScreen extends StatefulWidget {
  const GeoAnalysisScreen({super.key});

  @override
  State<GeoAnalysisScreen> createState() => _GeoAnalysisScreenState();
}

class _GeoAnalysisScreenState extends State<GeoAnalysisScreen> {
  String _pointFile = '';
  String _polygonFile = '';
  String _level = 'Desa';
  bool _isProcessing = false;

  Future<void> _selectPointFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['shp', 'geojson', 'kml'],
      dialogTitle: 'Select point file',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pointFile = result.files.single.path!;
      });
    }
  }

  Future<void> _selectPolygonFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['shp', 'geojson', 'kml'],
      dialogTitle: 'Select polygon file',
    );
    
    if (result != null && result.files.single.path != null) {
      setState(() {
        _polygonFile = result.files.single.path!;
      });
    }
  }

  Future<void> _startAnalysis() async {
    if (_pointFile.isEmpty || _polygonFile.isEmpty) {
      _showError('Error', 'Please select both point and polygon files');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await PythonService.checkOffPoints(
        pointFile: _pointFile,
        polygonFile: _polygonFile,
        level: _level,
        outputFile: 'off_points_report.xlsx',
      );

      if (result.containsKey('error')) {
        _showError('Analysis Failed', result['error']);
      } else {
        _showSuccess('Analysis Complete', 'Off-point analysis completed successfully!');
      }
    } catch (e) {
      _showError('Error', e.toString());
    } finally {
      setState(() => _isProcessing = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geographic Analysis'),
        foregroundColor: Colors.white,
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
            // Point File Input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Point File',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _pointFile.isEmpty ? 'No file selected' : _pointFile,
                            style: TextStyle(
                              color: _pointFile.isEmpty ? Colors.grey : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectPointFile,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Polygon File Input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Polygon File',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _polygonFile.isEmpty ? 'No file selected' : _polygonFile,
                            style: TextStyle(
                              color: _polygonFile.isEmpty ? Colors.grey : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _selectPolygonFile,
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Level Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Analysis Level',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _level,
                      items: const [
                        DropdownMenuItem(value: 'Desa', child: Text('Desa')),
                        DropdownMenuItem(value: 'SLS', child: Text('SLS')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _level = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Run Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startAnalysis,
              icon: const Icon(Icons.analytics),
              label: const Text('Start Analysis'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // Instructions
            Card(
              color: Colors.green[50],
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
                    Text('• Select point file (SHP, GeoJSON, or KML)'),
                    Text('• Select polygon file (SHP, GeoJSON, or KML)'),
                    Text('• Choose analysis level (Desa or SLS)'),
                    Text('• Analysis will check for points outside their polygons'),
                    Text('• Results will be saved as Excel report'),
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