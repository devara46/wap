import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/python_service.dart';
import 'rename_screen.dart';
import 'rotate_screen.dart';
import 'dpi_conversion_screen.dart';
import 'geo_analysis_screen.dart';
import 'georef_screen.dart';
import 'organize_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isServerConnected = false;
  String _status = 'Checking backend connection...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServerConnection();
  }

  @override
  void dispose() {
    _shutdownPythonServer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app background/close events
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      _shutdownPythonServer();
    }
  }

  Future<void> _shutdownPythonServer() async {
    try {
      final client = HttpClient();
      // Set timeout on the client instead of the request
      client.connectionTimeout = const Duration(seconds: 2);
      
      final request = await client.postUrl(Uri.parse('http://localhost:5000/shutdown'));
      await request.close();
      print('Python server shutdown requested');
    } catch (e) {
      print('Error shutting down Python server: $e');
      // Fallback: kill python processes
      if (Platform.isWindows) {
        Process.run('taskkill', ['/f', '/im', 'python.exe']);
      }
    }
  }

  Future<void> _checkServerConnection() async {
    setState(() {
      _status = 'Checking server...';
    });

    final result = await PythonService.testConnection();
    
    setState(() {
      _isServerConnected = result['success'] ?? false;
      _status = result['success'] ? 'Backend connected!' : result['error'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Python-Flutter Integration'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServerConnection,
            tooltip: 'Check Backend Connection',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Server Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isServerConnected ? Icons.check_circle : Icons.error,
                          color: _isServerConnected ? Colors.green : Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isServerConnected ? 'Backend Connected' : 'Backend Offline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _isServerConnected ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Navigation Cards
            Card(
              child: ListTile(
                leading: const Icon(Icons.drive_file_rename_outline, color: Colors.blue),
                title: const Text('Batch Rename Images'),
                subtitle: const Text('Rename images based on QR codes'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RenameScreen())),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.rotate_right, color: Colors.orange),
                title: const Text('Batch Rotate Images'),
                subtitle: const Text('Auto-rotate images based on QR position'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RotateScreen())),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.photo_size_select_large, color: Colors.purple),
                title: const Text('DPI Conversion'),
                subtitle: const Text('Convert image DPI for print quality'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DpiConversionScreen())),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.map, color: Colors.green),
                title: const Text('Create World Files'),
                subtitle: const Text('Generate georeferencing world files from GeoJSON'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GeorefScreen())),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.folder, color: Colors.orange),
                title: const Text('Organize Files by ID'),
                subtitle: const Text('Organize files into folders based on their IDs'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrganizeScreen())),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.map, color: Colors.green),
                title: const Text('Geographic Analysis'),
                subtitle: const Text('Check points outside polygons'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GeoAnalysisScreen())),
              ),
            ),

            const SizedBox(height: 30),

            // Instructions
            const Card(
              color: Colors.blue,
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
                    Text('1. Start Python server first'),
                    Text('2. Ensure server is running on http://localhost:5000'),
                    Text('3. Select a function from the options above'),
                    Text('4. Follow the instructions in each screen'),
                    SizedBox(height: 8),
                    Text(
                      'Note: Processing may take several minutes for large folders',
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