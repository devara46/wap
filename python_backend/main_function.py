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

def create_world_files_from_geojson(
    geojson_path: str, 
    output_dir: str, 
    file_extension: str = 'jgw', 
    expand_percentage: float = 0.05,
    target_dpi: int = 200,
    landscape_width: int = 3307,
    landscape_height: int = 2338,
    portrait_width: int = 2338,
    portrait_height: int = 3307
):
    """
    Create world files from geographic data with configurable DPI and dimensions.
    
    Args:
        geojson_path (str): Path to the geographic data file
        output_dir (str): Directory to save the world files
        file_extension (str): File extension for world files
        expand_percentage (float): Percentage to expand bounds
        target_dpi (int): Target DPI for the output images (default: 200)
        landscape_width (int): Pixel width for landscape orientation (default: 3307)
        landscape_height (int): Pixel height for landscape orientation (default: 2338)
        portrait_width (int): Pixel width for portrait orientation (default: 2338)
        portrait_height (int): Pixel height for portrait orientation (default: 3307)
    """
    try:
        import geopandas as gpd
        from shapely.geometry import box
        import pandas as pd
        import os
        
        # Validate parameters
        if not isinstance(expand_percentage, (int, float)) or expand_percentage < 0:
            return {
                'success': False,
                'error': f'Invalid expand percentage: {expand_percentage}. Must be non-negative.',
                'created_files': [],
                'total_files': 0
            }
        
        if target_dpi <= 0:
            return {
                'success': False,
                'error': f'Invalid DPI: {target_dpi}. Must be positive.',
                'created_files': [],
                'total_files': 0
            }
        
        # Validate dimensions
        for dim_name, dim_value in [
            ('landscape_width', landscape_width),
            ('landscape_height', landscape_height),
            ('portrait_width', portrait_width),
            ('portrait_height', portrait_height)
        ]:
            if not isinstance(dim_value, int) or dim_value <= 0:
                return {
                    'success': False,
                    'error': f'Invalid {dim_name}: {dim_value}. Must be positive integer.',
                    'created_files': [],
                    'total_files': 0
                }
        
        print(f"Using DPI: {target_dpi}")
        print(f"Landscape dimensions: {landscape_width} x {landscape_height}")
        print(f"Portrait dimensions: {portrait_width} x {portrait_height}")
        
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
            Create world file using user-provided image dimensions
            """
            # Use user-provided dimensions
            if is_landscape:
                img_width = landscape_width
                img_height = landscape_height
            else:
                img_width = portrait_width
                img_height = portrait_height
            
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
            'message': f'Successfully created {len(created_files)} world files with {target_dpi} DPI',
            'created_files': created_files,
            'total_files': len(created_files),
            'file_type': file_ext,
            'expand_percentage_used': expand_percentage,
            'dpi_used': target_dpi,
            'dimensions_used': {
                'landscape': f'{landscape_width}x{landscape_height}',
                'portrait': f'{portrait_width}x{portrait_height}'
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Error creating world files: {str(e)}',
            'created_files': [],
            'total_files': 0
        }
        
def find_overlapping_polygons(gdf_a, gdf_b, id_col='idsls', overlap_threshold=0.5):
    """
    Compare two GeoDataFrames and return polygons that overlap >= threshold 
    with different IDs.
    
    Args
    ----------
    gdf_a, gdf_b : GeoDataFrame
        The two GeoDataFrames to compare.
    id_col : str
        The column name that contains polygon IDs (e.g., 'idsls').
    overlap_threshold : float
        Minimum overlap ratio (0–1) to consider as significant.
    
    Returns
    -------
    GeoDataFrame
        Contains intersecting polygons with:
        - idsls_baru, idsls_lama: polygon IDs from each dataset
        - area_baru, area_lama: original areas
        - area_intersection: overlapping area
        - ratio_baru, ratio_lama: overlap ratios relative to each polygon
    """
    try:
        import geopandas as gpd
        
        # Reproject to metric CRS for area calculations
        gdf_a = gdf_a.to_crs('EPSG:3857')
        gdf_b = gdf_b.to_crs('EPSG:3857')

        # Compute areas for each polygon
        gdf_a = gdf_a.copy()
        gdf_b = gdf_b.copy()
        gdf_a['area_baru'] = gdf_a.geometry.area
        gdf_b['area_lama'] = gdf_b.geometry.area

        # Compute intersections (keep all geometry types)
        intersections = gpd.overlay(gdf_a, gdf_b, how='intersection', keep_geom_type=False)

        # Filter only polygon-like results
        intersections = intersections[intersections.geometry.geom_type.isin(['Polygon', 'MultiPolygon'])]

        # Compute intersection area
        intersections['area_intersection'] = intersections.geometry.area

        # Compute ratios
        intersections['ratio_baru'] = intersections['area_intersection'] / intersections['area_baru']
        intersections['ratio_lama'] = intersections['area_intersection'] / intersections['area_lama']

        # Rename ID columns for clarity
        intersections = intersections.rename(columns={
            f'{id_col}_1': 'idsls_baru',
            f'{id_col}_2': 'idsls_lama'
        })

        # Filter by overlap threshold and different IDs
        mask = ((intersections['ratio_baru'] >= overlap_threshold) | 
                (intersections['ratio_lama'] >= overlap_threshold)) & \
               (intersections['idsls_baru'] != intersections['idsls_lama'])
        result = intersections.loc[mask].copy()

        # Keep relevant columns
        cols = ['idsls_baru', 'idsls_lama', 'area_baru', 'area_lama', 'area_intersection', 'ratio_baru', 'ratio_lama']
        result = result[cols].drop_duplicates()

        return result
        
    except Exception as e:
        print(f"Error in overlap analysis: {e}")
        return None
        
def evaluate_sipw_polygon(sipw_path: str, current_polygon_path: str, output_path: str = 'Evaluation Result.xlsx', 
                         original_polygon_path: str = None, overlap_threshold: float = 0.5) -> dict:
    """
    Evaluate SiPW data against polygon data and generate comparison report.
    
    Args:
        sipw_path (str): Path to the SiPW Excel file
        current_polygon_path (str): Path to the current polygon file
        output_path (str): Path for the output Excel file
        original_polygon_path (str): Optional path to original polygon for overlap analysis
        overlap_threshold (float): Threshold for overlap analysis (0-1)
    
    Returns:
        dict: Results containing evaluation statistics and any errors
    """
    try:
        import geopandas as gpd
        import pandas as pd
        import os
        
        # Check if files exist
        if not os.path.exists(sipw_path):
            return {
                'success': False,
                'error': f'SiPW file does not exist: {sipw_path}',
                'output_file': None
            }
        
        if not os.path.exists(current_polygon_path):
            return {
                'success': False,
                'error': f'Current polygon file does not exist: {current_polygon_path}',
                'output_file': None
            }
        
        # Read data
        sipw = pd.read_excel(sipw_path, dtype=str)
        sls_current = gpd.read_file(current_polygon_path)  # Current polygon
        
        # Ensure required columns exist
        if 'idsls' not in sipw.columns:
            return {
                'success': False,
                'error': 'Required column "idsls" not found in SiPW file',
                'output_file': None
            }
        
        if 'idsls' not in sls_current.columns:
            return {
                'success': False,
                'error': 'Required column "idsls" not found in current polygon file',
                'output_file': None
            }
        
        # Add missing columns if needed
        if 'kdsubsls' not in sls_current.columns:
            sls_current['kdsubsls'] = '00'
        if 'idsubsls' not in sls_current.columns:
            sls_current['idsubsls'] = sls_current['idsls'] + sls_current['kdsubsls']
        
        # Perform evaluations
        # 1. No geometry
        nogeo = sls_current.loc[sls_current['geometry'].isnull(), ['idsubsls', 'nmkec', 'nmdesa', 'nmsls']].copy()
        
        # 2. Duplicates
        duplicate = sls_current.loc[sls_current.duplicated('idsubsls', keep=False), ['idsubsls', 'nmkec', 'nmdesa', 'nmsls']].copy()
        
        # 3. Get common kecamatan codes
        list_kec = sls_current['kdkec'].unique()
        
        # 4. Find differences between SiPW and polygon
        sipw_ids = set(sipw.loc[sipw['kdkec'].isin(list_kec), 'id_subsls']) if 'id_subsls' in sipw.columns else set()
        poly_ids = set(sls_current['idsubsls'])
        
        only_sipw = sipw_ids - poly_ids
        only_poly = poly_ids - sipw_ids
        
        # 5. Create dataframes for differences
        sipw_df = sipw.loc[sipw['id_subsls'].isin(only_sipw), ['id_subsls', 'nmkec', 'nmdesa', 'nama_sls']].copy() if 'id_subsls' in sipw.columns else pd.DataFrame()
        poly_df = sls_current.loc[sls_current['idsubsls'].isin(only_poly), ['idsubsls', 'nmkec', 'nmdesa', 'nmsls']].copy()
        
        # 6. Compare names
        compare = pd.merge(
            sipw[['idsls', 'nama_sls']] if 'nama_sls' in sipw.columns else pd.DataFrame(),
            sls_current[['idsls', 'nmsls']],
            on='idsls',
            how='inner'
        )
        
        if not compare.empty and 'nama_sls' in compare.columns:
            compare = compare.loc[compare['nama_sls'] != compare['nmsls']]
            compare = compare.rename({'nama_sls': 'nmsls_sipw', 'nmsls': 'nmsls_poly'}, axis=1)
        else:
            compare = pd.DataFrame()
        
        # 7. Overlap analysis (if original polygon provided)
        overlap_df = pd.DataFrame()
        if original_polygon_path and os.path.exists(original_polygon_path):
            try:
                sls_original = gpd.read_file(original_polygon_path)
                overlap_result = find_overlapping_polygons(sls_current, sls_original, id_col='idsls', overlap_threshold=overlap_threshold)
                if overlap_result is not None:
                    overlap_df = overlap_result
                    print(f"Found {len(overlap_df)} overlapping polygons")
            except Exception as e:
                print(f"Overlap analysis failed: {e}")
                overlap_df = pd.DataFrame()
        
        # Create description
        description_data = [
            ['Evaluation Report - SiPW vs Polygon', ''],
            ['Generated on', pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')],
            ['', ''],
            ['Sheet Name', 'Description'],
            ['Duplicate', 'Contains list of duplicated idsubsls in current polygon data'],
            ['SiPW Only', 'Contains list of subsls that only exist in SiPW data'],
            ['Polygon Only', 'Contains list of subsls that only exist in current polygon data'],
            ['Name Differences', 'Contains list of SLS with name differences between SiPW and current Polygon'],
            ['No Geometry', 'Contains list of subsls without geometry in current polygon data'],
        ]
        
        if not overlap_df.empty:
            description_data.extend([
                ['Overlap Analysis', 'Contains overlapping polygons between current and original polygon data'],
            ])
        
        description_data.extend([
            ['', ''],
            ['Summary Statistics', ''],
            ['Total SiPW Records', len(sipw)],
            ['Total Current Polygon Records', len(sls_current)],
            ['Duplicated IDs', len(duplicate)],
            ['SiPW Only Records', len(sipw_df)],
            ['Polygon Only Records', len(poly_df)],
            ['Name Differences', len(compare)],
            ['Records Without Geometry', len(nogeo)]
        ])
        
        if not overlap_df.empty:
            description_data.append(['Overlapping Polygons', len(overlap_df)])
        
        description = pd.DataFrame(description_data)
        
        # Write to Excel
        with pd.ExcelWriter(output_path, engine='openpyxl') as writer:
            # Description sheet
            description.to_excel(writer, sheet_name='Description', index=False, header=False)
            
            # Data sheets
            if not duplicate.empty:
                duplicate.to_excel(writer, sheet_name='Duplicate', index=False)
            if not sipw_df.empty:
                sipw_df.to_excel(writer, sheet_name='SiPW Only', index=False)
            if not poly_df.empty:
                poly_df.to_excel(writer, sheet_name='Polygon Only', index=False)
            if not compare.empty:
                compare.to_excel(writer, sheet_name='Name Differences', index=False)
            if not nogeo.empty:
                nogeo.to_excel(writer, sheet_name='No Geometry', index=False)
            if not overlap_df.empty:
                overlap_df.to_excel(writer, sheet_name='Overlap Analysis', index=False)
        
        # Return results
        result_stats = {
            'total_sipw': len(sipw),
            'total_polygon': len(sls_current),
            'duplicates': len(duplicate),
            'sipw_only': len(sipw_df),
            'polygon_only': len(poly_df),
            'name_differences': len(compare),
            'no_geometry': len(nogeo)
        }
        
        if not overlap_df.empty:
            result_stats['overlapping_polygons'] = len(overlap_df)
        
        return {
            'success': True,
            'message': f'Evaluation completed successfully. Report saved to: {output_path}',
            'output_file': output_path,
            'statistics': result_stats
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Error during evaluation: {str(e)}',
            'output_file': None
        }