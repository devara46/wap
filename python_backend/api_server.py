from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import geopandas as gpd
import pandas as pd
import numpy as np
import os
import logging
from pathlib import Path
from typing import Optional, Tuple
from PIL import Image
import tempfile
import threading
import time
import atexit
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

# Your original functions
def decode_qr_code(image: np.ndarray, annotate: bool = False) -> tuple[str, str]:
    """Your existing decode_qr_code function"""
    detector = cv2.QRCodeDetector()
    data, vertices, _ = detector.detectAndDecode(image)
    if vertices is not None:
        if annotate:
            vertices = vertices[0]
            for i in range(len(vertices)):
                pt1 = tuple(map(int, vertices[i]))
                pt2 = tuple(map(int, vertices[(i + 1) % 4]))
                cv2.line(image, pt1, pt2, (0, 255, 0), 3)
        return data, 'Detected'
    return '', 'Not detected'

def rotate_image(image: np.ndarray, angle: int) -> np.ndarray:
    """Your existing rotate_image function"""
    if angle == 180:
        return cv2.rotate(image, cv2.ROTATE_180)
    elif angle == 90:
        return cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    elif angle == 270:
        return cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return image

def infer_rotation(row: int, col: int) -> Optional[int]:
    """Your existing infer_rotation function"""
    if (row, col) == (0, 0):
        return 180
    elif (row, col) == (4, 0):
        return 270
    elif (row, col) == (0, 2):
        return 90
    elif (row, col) == (1, 0):
        return 270
    elif (row, col) == (0, 1):
        return 180
    elif (row, col) == (1, 4):
        return 90
    return None

def split_image_and_detect_qr(image_path: str, rotate: bool) -> Tuple[str, np.ndarray]:
    """Your existing split_image_and_detect_qr function"""
    LOGGER.info(f'Processing image: {image_path}')
    image = cv2.imread(image_path)
    if image is None:
        LOGGER.error(f"Failed to read image: {image_path}")
        return '', np.array([])
        
    height, width, _ = image.shape

    orientation = 'landscape' if width > height else 'portrait'
    rows, cols = (3, 5) if orientation == 'landscape' else (5, 3)
    part_h, part_w = height // rows, width // cols

    rotate_angle = None
    found_qr = None

    for row in range(rows):
        for col in range(cols):
            part = image[row * part_h:(row + 1) * part_h, col * part_w:(col + 1) * part_w]
            data, location = decode_qr_code(part)
            if location == 'Detected' and len(data) >= 10:
                angle = infer_rotation(row, col)
                if angle:
                    rotate_angle = angle
                found_qr = data
                LOGGER.info(f'QR detected in part ({row},{col}) with data: {data.split(chr(10))[0]}')

    result_image = rotate_image(image, rotate_angle) if rotate and rotate_angle else image
    return found_qr or '', result_image

def find_images_in_folder(folder_path: str) -> list[Path]:
    """Your existing find_images_in_folder function"""
    image_extensions = ('.jpg', '.jpeg', '.png')
    folder = Path(folder_path)
    return [f for f in folder.rglob('*') if f.suffix.lower() in image_extensions]

def search_off_point(point_path: str, polygon_path: str, fname: str, level: str):
    """Your existing search_off_point function"""
    LOGGER.info(f'Checking point-polygon consistency for {point_path} against {polygon_path}')
    try:
        point = gpd.read_file(point_path)
        polygon = gpd.read_file(polygon_path)

        colname = 'iddesa' if level=='Desa' else 'idsls'
        gdf = gpd.sjoin(point, polygon[[colname, 'geometry']], lsuffix='pt', rsuffix='ea')
        offside = gdf.loc[gdf[f'{colname}_pt']!=gdf[f'{colname}_ea']]
        LOGGER.info(f'Found {len(offside)} points outside their polygon')

        result = offside[[f'{colname}_pt', 'nama', 'wid']].groupby(f'{colname}_pt', as_index=False).agg(
            count=('nama', 'count'),
            list_id=('wid', lambda x: ', '.join(x))
        ).rename({f'{colname}_pt': colname}, axis='columns')

        result.to_excel(fname, index=False)
        LOGGER.info(f'Saved off-point report to {fname}')

    except Exception as e:
        LOGGER.error(f'Error in search_off_point: {str(e)}')
        raise
    
# Add this function to your existing api_server.py
def change_dpi_and_resize(path_in, path_out, target_dpi=(300, 300)):
    """Change DPI and resize image while maintaining physical dimensions"""
    try:
        img = Image.open(path_in)

        # Get current DPI from metadata (default to 150 if not available)
        current_dpi = img.info.get("dpi", (150, 150))
        print(f"Current DPI: {current_dpi}")

        # Compute physical size in inches (based on current DPI)
        width_inch = img.width / current_dpi[0]
        height_inch = img.height / current_dpi[1]

        # Compute new pixel dimensions based on target DPI
        new_width = int(width_inch * target_dpi[0])
        new_height = int(height_inch * target_dpi[1])

        # Resize image
        img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)

        # Create output directory if it doesn't exist
        os.makedirs(os.path.dirname(path_out), exist_ok=True)

        # Save with new DPI
        img_resized.save(path_out, dpi=target_dpi)

        return True, f"Saved {path_out} with new DPI: {target_dpi}"
    except Exception as e:
        return False, f"Error processing {path_in}: {str(e)}"

def batch_convert_dpi(source_dir, dest_dir, target_dpi=(200, 200)):
    """Batch convert DPI for all images in a directory"""
    try:
        # Supported image extensions
        image_extensions = ('.jpg', '.jpeg', '.png', '.tiff', '.bmp')
        source_path = Path(source_dir)
        
        # Find all image files
        image_files = [f for f in source_path.rglob('*') if f.suffix.lower() in image_extensions]
        
        if not image_files:
            return False, "No image files found in source directory"

        results = {
            'processed': 0,
            'failed': 0,
            'errors': [],
            'total': len(image_files)
        }

        for image_path in image_files:
            # Create output path maintaining directory structure
            relative_path = image_path.relative_to(source_path)
            output_path = Path(dest_dir) / relative_path
            
            success, message = change_dpi_and_resize(
                str(image_path), 
                str(output_path), 
                target_dpi
            )
            
            if success:
                results['processed'] += 1
            else:
                results['failed'] += 1
                results['errors'].append(message)

        return True, results
        
    except Exception as e:
        return False, f"Batch processing error: {str(e)}"

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
        
        images = find_images_in_folder(source)
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
            qr_code_data, result_image = split_image_and_detect_qr(str(image_path), rotate)
            
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
            success, message = change_dpi_and_resize(
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
        search_off_point(point_path, polygon_path, output_filename, level)
        
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