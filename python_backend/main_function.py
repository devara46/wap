import cv2 # type: ignore
import geopandas as gpd # type: ignore
import pandas as pd # type: ignore
import numpy as np # type: ignore
import os
from PIL import Image

from pathlib import Path
from typing import Optional, Tuple
from shapely.geometry import box



def decode_qr_code(
    image: np.ndarray, annotate: bool = False
) -> tuple[str, str]:
    """
    Detects and decodes a QR code in the given image.
    Optionally draws a bounding box around the QR code if annotate is True.

    Args:
        image (np.ndarray): The input image in which to detect the QR code.
        annotate (bool): Whether to draw a bounding box around the detected
                         QR code.

    Returns:
        tuple[str, str]: A tuple containing the decoded QR code data (str),
                         and a status string ('Detected' or 'Not detected').
    """
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



def rotate_image(image:np.ndarray, angle:int) -> np.ndarray:
    """
    Rotates image by 90, 180, or 270 degrees.
    
    Args:
        image (np.ndarray): input image to be rotated
        angle (int): The angle in which the image needs to be rotated 
    
    Return:
        np.ndarray: The rotated image
    """
    if angle == 180:
        return cv2.rotate(image, cv2.ROTATE_180)
    elif angle == 90:
        return cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    elif angle == 270:
        return cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return image



def infer_rotation(row: int, col: int) -> Optional[int]:
    """
    Infers the required rotation angle for the image based on the 
    QR code's position (row, col) and the image orientation.

    Args:
        row (int): The row index of the detected QR code part.
        col (int): The column index of the detected QR code part.

    Returns:
        Optional[int]: The rotation angle in degrees (90, 180, 270), 
                       or None if no rotation is needed or matched.
    """
    # Landscape
    if (row, col) == (0, 0):
        return 180
    elif (row, col) == (4, 0):
        return 270
    elif (row, col) == (0, 2):
        return 90
    # Portrait
    elif (row, col) == (1, 0):
        return 270
    elif (row, col) == (0, 1):
        return 180
    elif (row, col) == (1, 4):
        return 90
    return None



def split_image_and_detect_qr(
    image_path: str, rotate: bool
) -> Tuple[str, np.ndarray]:
    """
    Splits an image into a grid based on orientation, detects QR codes in each 
    part, and determines if rotation is needed based on QR code location. If a
    valid QR code is found, the image is rotated accordingly.

    Args:
        image_path (str): Path to the image file.
        rotate (bool): Whether the image will be rotated or not.

    Returns:
        Tuple[str, np.ndarray]: 
            - The decoded QR code data as a string (empty if not found).
            - The (possibly rotated) image as a NumPy ndarray.
    """
    image = cv2.imread(image_path)
    height, width, _ = image.shape

    orientation = 'landscape' if width > height else 'portrait'
    rows, cols = (3, 5) if orientation == 'landscape' else (5, 3)
    part_h, part_w = height // rows, width // cols

    qr_data = {}
    rotate_angle = None
    found_qr = None

    for row in range(rows):
        for col in range(cols):
            part = image[
                row * part_h:(row + 1) * part_h, col * part_w:(col + 1) * part_w
            ]
            key = f'part_{row + 1}_{col + 1}'
            data, location = decode_qr_code(part)

            qr_data[key] = {'data': data, 'location': location}

            if location == 'Detected' and len(data) >= 10:
                angle = infer_rotation(row, col)
                if angle:
                    rotate_angle = angle
                found_qr = data

    result_image = rotate_image(
        image, rotate_angle
    ) if rotate and rotate_angle else image

    return found_qr or '', result_image



def find_images_in_folder(folder_path: str) -> list[Path]:
    """
    Recursively finds all image files in a folder.

    Args:
        folder_path (str): Path to the folder.

    Returns:
        list[Path]: List of image file paths.
    """
    image_extensions = ('.jpg', '.jpeg', '.png')
    folder = Path(folder_path)
    return [
        f for f in folder.rglob('*')
        if f.suffix.lower() in image_extensions
    ]



def search_off_point(
    point_path: str, polygon_path: str, fname: str, level :str
):
    """
    Read point and polygon geometry then check for points outside of the
    polygon.
    
    Args:
        point_path (str): Path to the point file.
        polygon_path (str): Path to the polygon file.
        fname (bool): Path to save the result file.
    """
    try:
        point = gpd.read_file(point_path)
        polygon = gpd.read_file(polygon_path)
    except Exception as e:
        print(f'Error reading files: {e}')
        return

    colname = 'iddesa' if level=='Desa' else 'idsls'
    
    if colname not in point.columns:
        print(f'Column {colname} was not found in point file')

    if colname not in polygon.columns:
        print(f'Column {colname} was not found in polygon file')

    gdf = gpd.sjoin(
        point,
        polygon[[colname, 'geometry']],
        lsuffix='pt',
        rsuffix='ea'
    )
    offside = gdf.loc[gdf[f'{colname}_pt']!=gdf[f'{colname}_ea']]

    result = offside[[
        f'{colname}_pt', 'nama', 'wid'
    ]].groupby(f'{colname}_pt', as_index=False).agg(
        count=('nama', 'count'),
        list_id=('wid', lambda x: ', '.join(x))
    ).rename({f'{colname}_pt': colname}, axis='columns')
    
    result.to_excel(fname, index=False)
    
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

def create_world_files_from_geojson(geojson_path: str, output_dir: str, file_extension: str = 'jgw', expand_percentage: float = 0.05):
    """
    Create world files from geographic data (GeoJSON, GPKG, SHP) with proper georeferencing.
    
    Args:
        geojson_path (str): Path to the geographic data file (GeoJSON, GPKG, SHP)
        output_dir (str): Directory to save the world files
        file_extension (str): File extension for world files (default: 'jgw')
        expand_percentage (float): Percentage to expand bounds (default: 0.05 for 5%)
    
    Returns:
        dict: Results containing count of created files and any errors
    """
    try:
        import geopandas as gpd
        from shapely.geometry import box
        import pandas as pd
        import os
        
        # Validate expand_percentage
        if not isinstance(expand_percentage, (int, float)) or expand_percentage < 0:
            return {
                'success': False,
                'error': f'Invalid expand percentage: {expand_percentage}. Must be a non-negative number.',
                'created_files': [],
                'total_files': 0
            }
        
        # Determine file type and load accordingly
        file_ext = os.path.splitext(geojson_path)[1].lower()
        
        if file_ext == '.geojson' or file_ext == '.json':
            gdf = gpd.read_file(geojson_path)
        elif file_ext == '.gpkg':
            gdf = gpd.read_file(geojson_path)
        elif file_ext == '.shp':
            gdf = gpd.read_file(geojson_path)
        else:
            return {
                'success': False,
                'error': f'Unsupported file format: {file_ext}. Supported formats: .geojson, .gpkg, .shp',
                'created_files': [],
                'total_files': 0
            }
        
        # Check if the file contains geometry data
        if gdf.empty:
            return {
                'success': False,
                'error': 'The selected file contains no geometry data',
                'created_files': [],
                'total_files': 0
            }
        
        # Check for required column
        if 'idsls' not in gdf.columns:
            return {
                'success': False,
                'error': 'Required column "idsls" not found in the data',
                'created_files': [],
                'total_files': 0
            }
        
        os.makedirs(output_dir, exist_ok=True)

        # Use user-provided expand percentage with default of 5%
        target_ratio_landscape = (324, 272)
        target_ratio_portrait = (278, 315)

        landscape_ratio = target_ratio_landscape[0]/target_ratio_landscape[1]
        portrait_ratio = target_ratio_portrait[0]/target_ratio_portrait[1]

        landscape_margins = {
            "upper": 14/272,
            "lower": 11/272,
            "left": 9.839/324,
            "right": 86.161/324
        }
        portrait_margins = {
            "upper": 15/315,
            "lower": 90/315,
            "left": 9.839/278,
            "right": 9.161/278
        }

        df = pd.DataFrame()

        # Iterate over each polygon
        for index, row in gdf.iterrows():
            polygon = row['geometry']
            
            # Skip if geometry is not a polygon
            if not hasattr(polygon, 'bounds'):
                continue
                
            xmin, ymin, xmax, ymax = polygon.bounds

            width = xmax - xmin
            height = ymax - ymin

            # Use user-provided expand percentage
            expand_amount = max(width, height) * expand_percentage

            if width > height:
                # --- Landscape ---
                xmin -= expand_amount
                xmax += expand_amount
                width = xmax - xmin
                height = ymax - ymin

                poly_ratio = width/height

                # Adjust to target ratio (landscape)
                if poly_ratio > landscape_ratio:
                    new_height = width * (target_ratio_landscape[1] / target_ratio_landscape[0])
                    delta = (new_height - height) / 2
                    ymin -= delta
                    ymax += delta
                else:
                    new_width = height * (target_ratio_landscape[0] / target_ratio_landscape[1])
                    delta = (new_width - width) / 2
                    xmin -= delta
                    xmax += delta

                # Apply margins
                width = xmax - xmin
                height = ymax - ymin
                xmin -= width * landscape_margins["left"]
                xmax += width * landscape_margins["right"]
                ymin -= height * landscape_margins["lower"]
                ymax += height * landscape_margins["upper"]

            else:
                # --- Portrait ---
                ymin -= expand_amount
                ymax += expand_amount
                width = xmax - xmin
                height = ymax - ymin

                poly_ratio = width/height

                # Adjust to target ratio (portrait)
                if poly_ratio > portrait_ratio:
                    new_height = width * (target_ratio_portrait[1] / target_ratio_portrait[0])
                    delta = (new_height - height) / 2
                    ymin -= delta
                    ymax += delta
                else:
                    new_width = height * (target_ratio_portrait[0] / target_ratio_portrait[1])
                    delta = (new_width - width) / 2
                    xmin -= delta
                    xmax += delta

                # Apply margins
                width = xmax - xmin
                height = ymax - ymin
                xmin -= width * portrait_margins["left"]
                xmax += width * portrait_margins["right"]
                ymin -= height * portrait_margins["lower"]
                ymax += height * portrait_margins["upper"]

            temp = pd.DataFrame({
                'idsls': [row['idsls']],
                'xmin': [xmin],
                'xmax': [xmax],
                'ymin': [ymin],
                'ymax': [ymax]
            })

            df = pd.concat([df, temp], ignore_index=True)

        # Check if we have any valid geometries
        if df.empty:
            return {
                'success': False,
                'error': 'No valid polygon geometries found in the file',
                'created_files': [],
                'total_files': 0
            }

        gdf_bounds = gpd.GeoDataFrame(
            df,
            geometry=[box(xmin, ymin, xmax, ymax) for xmin, ymin, xmax, ymax in zip(df.xmin, df.ymin, df.xmax, df.ymax)],
            crs=gdf.crs
        )

        # Reproject to EPSG:4326
        gdf_bounds_4326 = gdf_bounds.to_crs(epsg=4326)

        # Extract the transformed bounds
        df[["xmin", "ymin", "xmax", "ymax"]] = gdf_bounds_4326.bounds[["minx", "miny", "maxx", "maxy"]].values

        def create_world_file_from_bounds(output_path, xmin, ymin, xmax, ymax, is_landscape=True):
            """
            Create world file using actual image dimensions
            """
            # Use actual image dimensions
            if is_landscape:
                img_width, img_height = 3307, 2338  # Landscape orientation
            else:
                img_width, img_height = 2338, 3307  # Portrait orientation
            
            # Calculate pixel sizes
            x_scale = (xmax - xmin) / img_width
            y_scale = (ymin - ymax) / img_height  # Negative for north-up
            
            # Upper left corner coordinates (center of first pixel)
            upper_left_x = xmin + (x_scale / 2)
            upper_left_y = ymax + (y_scale / 2)
            
            with open(output_path, 'w') as f:
                f.write(f"{x_scale:.12f}\n")
                f.write("0.000000000000\n")
                f.write("0.000000000000\n")
                f.write(f"{y_scale:.12f}\n")
                f.write(f"{upper_left_x:.12f}\n")
                f.write(f"{upper_left_y:.12f}\n")

        # Create world files
        created_files = []
        for index, row in df.iterrows():
            filename = f"{row['idsls']}_WS.{file_extension}"
            output_path = os.path.join(output_dir, filename)
            
            # Determine orientation based on final bounds
            width = row['xmax'] - row['xmin']
            height = row['ymax'] - row['ymin']
            is_landscape = width > height
            
            create_world_file_from_bounds(
                output_path=output_path,
                xmin=row['xmin'],
                ymin=row['ymin'],
                xmax=row['xmax'],
                ymax=row['ymax'],
                is_landscape=is_landscape
            )
            created_files.append(filename)
        
        return {
            'success': True,
            'message': f'Successfully created {len(created_files)} world files from {os.path.basename(geojson_path)} with {expand_percentage*100}% expansion',
            'created_files': created_files,
            'total_files': len(created_files),
            'file_type': file_ext,
            'expand_percentage_used': expand_percentage
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Error creating world files: {str(e)}',
            'created_files': [],
            'total_files': 0
        }