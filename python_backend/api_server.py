from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import os
import logging
import main_function
from pathlib import Path

import threading
import time
import signal

# Setup logging
logging.basicConfig(level=logging.INFO)
LOGGER = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Global variables for progress tracking
processing_status = {
    'is_processing': False,
    'current': 0,
    'total': 0,
    'message': 'Ready',
    'error': None
}

# Global variable to control server shutdown
server_running = True

# Flask API endpoints
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'message': 'Python server is running'})

@app.route('/batch_process', methods=['POST'])
def batch_process_endpoint():
    """Start batch process and return immediately"""
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': 'Another process is already running'}), 400
    
    try:
        data = request.get_json()
        source = data.get('source')
        dest = data.get('dest', 'results')
        rotate = data.get('rotate', False)
        
        if not source:
            return jsonify({'error': 'Source directory required'}), 400
        
        # Reset processing status
        processing_status.update({
            'is_processing': True,
            'current': 0,
            'total': 0,
            'message': 'Starting...',
            'error': None
        })
        
        # Start processing in background thread
        thread = threading.Thread(
            target=run_batch_process_background,
            args=(source, dest, rotate),
            daemon=True
        )
        thread.start()
        
        return jsonify({
            'message': 'Batch processing started in background',
            'status': 'started'
        })
        
    except Exception as e:
        processing_status.update({
            'error': str(e),
            'is_processing': False
        })
        return jsonify({'error': str(e)}), 500

def run_batch_process_background(source, dest, rotate):
    """Run batch process in background with progress updates"""
    global processing_status
    
    try:
        print(f"Starting batch process: source={source}, dest={dest}, rotate={rotate}")
        
        images = main_function.find_images_in_folder(source)
        total_images = len(images)
        print(f"Found {total_images} images to process")
        
        processing_status.update({
            'total': total_images,
            'message': f'Found {total_images} images'
        })
        
        if total_images == 0:
            print("No images found in source directory")
            processing_status.update({
                'message': 'No images found',
                'is_processing': False
            })
            return
        
        # Create destination directory
        os.makedirs(dest, exist_ok=True)
        print(f"Created output directory: {dest}")
        
        processed_count = 0
        for idx, image_path in enumerate(images):
            print(f"Processing image {idx + 1}/{total_images}: {image_path.name}")
            
            processing_status.update({
                'current': idx + 1,
                'message': f'Processing {image_path.name}'
            })
            
            # Process each image
            qr_code_data, result_image = main_function.split_image_and_detect_qr(str(image_path), rotate)
            
            if qr_code_data:
                print(f"QR code detected: {qr_code_data.split(chr(10))[0]}")
                
                # Your filename logic here
                fname = qr_code_data.split('\n')[0]
                if len(fname) == 14:
                    suffix = '_WB' if fname[-1] in ('B', 'P') else '_WS'
                elif len(fname) == 10:
                    suffix = '_WA'
                else:
                    suffix = '_UNKNOWN'
                
                output_filename = os.path.join(dest, f'{fname}{suffix}{image_path.suffix}')
                success = cv2.imwrite(output_filename, result_image)
                if success:
                    processed_count += 1
                    print(f"Successfully saved: {output_filename}")
                else:
                    print(f"Failed to save: {output_filename}")
            else:
                print(f"No QR code found in: {image_path.name}")
            
            # Small delay
            time.sleep(0.1)
        
        print(f"Processing completed! {processed_count}/{total_images} images processed")
        processing_status.update({
            'message': f'Completed! {processed_count}/{total_images} images',
            'current': total_images,
            'is_processing': False
        })
        
    except Exception as e:
        print(f"Error in batch processing: {e}")
        import traceback
        traceback.print_exc()
        processing_status.update({
            'error': str(e),
            'is_processing': False
        })
        
@app.route('/batch_rename', methods=['POST'])
def batch_rename_endpoint():
    """Batch rename images without rotation"""
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': 'Another process is already running'}), 400
    
    try:
        data = request.get_json()
        source = data.get('source')
        dest = data.get('dest', 'results')
        
        if not source:
            return jsonify({'error': 'Source directory required'}), 400
        
        # Reset processing status
        processing_status = {
            'is_processing': True,
            'current': 0,
            'total': 0,
            'message': 'Starting renaming...',
            'error': None
        }
        
        # Start processing in background thread
        thread = threading.Thread(
            target=run_batch_process_background,
            args=(source, dest, False),  # rotate=False for renaming only
            daemon=True
        )
        thread.start()
        
        return jsonify({
            'message': 'Batch renaming started in background',
            'status': 'started'
        })
        
    except Exception as e:
        processing_status['error'] = str(e)
        processing_status['is_processing'] = False
        return jsonify({'error': str(e)}), 500

@app.route('/batch_rotate', methods=['POST'])
def batch_rotate_endpoint():
    """Batch rotate images without renaming"""
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': 'Another process is already running'}), 400
    
    try:
        data = request.get_json()
        source = data.get('source')
        dest = data.get('dest', 'results')
        
        if not source:
            return jsonify({'error': 'Source directory required'}), 400
        
        # Reset processing status
        processing_status = {
            'is_processing': True,
            'current': 0,
            'total': 0,
            'message': 'Starting rotation...',
            'error': None
        }
        
        # Start processing in background thread
        thread = threading.Thread(
            target=run_batch_process_background,
            args=(source, dest, True),  # rotate=True for rotation only
            daemon=True
        )
        thread.start()
        
        return jsonify({
            'message': 'Batch rotation started in background',
            'status': 'started'
        })
        
    except Exception as e:
        processing_status['error'] = str(e)
        processing_status['is_processing'] = False
        return jsonify({'error': str(e)}), 500

# Add this endpoint to your Flask app
@app.route('/convert_dpi', methods=['POST'])
def convert_dpi_endpoint():
    """Convert DPI for images"""
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': 'Another process is already running'}), 400

    try:
        data = request.get_json()
        source_dir = data.get('source_dir')
        dest_dir = data.get('dest_dir')
        target_dpi = data.get('target_dpi', 200)
        
        if not source_dir or not dest_dir:
            return jsonify({'error': 'Source and destination directories required'}), 400
        
        # Reset processing status
        processing_status = {
            'is_processing': True,
            'current': 0,
            'total': 0,
            'message': 'Starting DPI conversion...',
            'error': None
        }

        # Start processing in background thread
        thread = threading.Thread(
            target=run_dpi_conversion_background,
            args=(source_dir, dest_dir, target_dpi),
            daemon=True
        )
        thread.start()

        return jsonify({
            'message': 'DPI conversion started in background',
            'status': 'started'
        })

    except Exception as e:
        processing_status['error'] = str(e)
        processing_status['is_processing'] = False
        return jsonify({'error': str(e)}), 500

def run_dpi_conversion_background(source_dir, dest_dir, target_dpi):
    """Run DPI conversion in background with progress updates"""
    global processing_status
    
    try:
        # Supported image extensions
        image_extensions = ('.jpg', '.jpeg', '.png', '.tiff', '.bmp')
        source_path = Path(source_dir)
        
        # Find all image files
        image_files = [f for f in source_path.rglob('*') if f.suffix.lower() in image_extensions]
        
        processing_status['total'] = len(image_files)
        processing_status['message'] = f'Found {len(image_files)} images to process'
        
        if not image_files:
            processing_status['message'] = 'No image files found'
            processing_status['is_processing'] = False
            return
        
        # Create destination directory
        os.makedirs(dest_dir, exist_ok=True)
        
        processed_count = 0
        for idx, image_path in enumerate(image_files):
            processing_status['current'] = idx + 1
            processing_status['message'] = f'Processing {image_path.name}'
            
            # Create output path maintaining directory structure
            relative_path = image_path.relative_to(source_path)
            output_path = Path(dest_dir) / relative_path
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Process each image
            success, message = main_function.change_dpi_and_resize(
                str(image_path), 
                str(output_path), 
                (target_dpi, target_dpi)
            )
            
            if success:
                processed_count += 1
                print(f"✓ {image_path.name} -> DPI {target_dpi}")
            else:
                print(f"✗ {image_path.name}: {message}")
            
            # Small delay
            time.sleep(0.1)
        
        processing_status['message'] = f'DPI conversion completed! {processed_count}/{len(image_files)} images processed'
        processing_status['current'] = len(image_files)
        processing_status['is_processing'] = False
        
    except Exception as e:
        processing_status['error'] = str(e)
        processing_status['is_processing'] = False
        print(f"Error in DPI conversion: {e}")

@app.route('/progress', methods=['GET'])
def get_progress():
    """Get current processing progress"""
    return jsonify(processing_status)

@app.route('/search_off_point', methods=['POST'])
def search_off_point_endpoint():
    """Check points outside polygons"""
    try:
        data = request.get_json()
        point_path = data.get('point_path')
        polygon_path = data.get('polygon_path')
        level = data.get('level', 'Desa')
        
        if not point_path or not polygon_path:
            return jsonify({'error': 'Point and polygon paths required'}), 400
        
        output_filename = f'off_point_report_{level}.xlsx'
        main_function.search_off_point(point_path, polygon_path, output_filename, level)
        
        return jsonify({
            'message': 'Off-point analysis completed',
            'result_file': output_filename
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    
@app.route('/shutdown', methods=['POST'])
def shutdown_server():
    """Gracefully shutdown the Python server"""
    global server_running
    LOGGER.info("Received shutdown request")
    server_running = False
    return jsonify({'message': 'Server shutting down'})

def graceful_shutdown(signum, frame):
    """Handle shutdown signals"""
    global server_running
    LOGGER.info("Received shutdown signal")
    server_running = False
    
# Register signal handlers
signal.signal(signal.SIGINT, graceful_shutdown)
signal.signal(signal.SIGTERM, graceful_shutdown)

if __name__ == '__main__':
    print("Starting Python-Flutter API Server...")
    print("=" * 50)
    
    # Create directories
    directories = ['uploads', 'results', 'logs']
    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f"✓ Created directory: {directory}")
    
    print("✓ Server starting on http://localhost:5000")
    print("✓ Press Ctrl+C to stop the server")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, debug=False)
    
    # Run server with shutdown capability
    from werkzeug.serving import make_server
    
    class ServerThread(threading.Thread):
        def __init__(self):
            threading.Thread.__init__(self)
            self.server = make_server('0.0.0.0', 5000, app)
            self.ctx = app.app_context()
            self.ctx.push()
            
        def run(self):
            LOGGER.info("Server starting...")
            self.server.serve_forever()
            
        def shutdown(self):
            LOGGER.info("Server shutting down...")
            self.server.shutdown()
    
    # Start server thread
    server_thread = ServerThread()
    server_thread.start()
    
    # Keep main thread alive until shutdown requested
    try:
        while server_running:
            time.sleep(0.1)
    except KeyboardInterrupt:
        LOGGER.info("Keyboard interrupt received")
    finally:
        server_thread.shutdown()
        server_thread.join()
        LOGGER.info("Server stopped completely")