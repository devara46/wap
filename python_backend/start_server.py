#!/usr/bin/env python3
"""
Simple server startup script
Handles configuration and error handling
"""
import os
import sys
from api_server import app

def check_dependencies():
    """Check if required packages are installed"""
    try:
        import flask
        import cv2
        import geopandas
        print("✓ All dependencies are available")
    except ImportError as e:
        print(f"✗ Missing dependency: {e}")
        print("Please run: pip install -r requirements.txt")
        sys.exit(1)

def create_directories():
    """Create necessary directories"""
    directories = ['uploads', 'results', 'logs']
    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f"✓ Created directory: {directory}")

def main():
    """Main startup function"""
    print("Starting Python-Flutter API Server...")
    print("=" * 50)
    
    # Check dependencies
    check_dependencies()
    
    # Create directories
    create_directories()
    
    # Start the server
    print("✓ Server starting on http://localhost:5000")
    print("✓ Press Ctrl+C to stop the server")
    print("=" * 50)
    
    try:
        app.run(host='0.0.0.0', port=5000, debug=False)
    except KeyboardInterrupt:
        print("\nServer stopped by user")
    except Exception as e:
        print(f"Error starting server: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()