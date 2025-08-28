import cv2 # type: ignore
import geopandas as gpd # type: ignore
import pandas as pd # type: ignore
import numpy as np # type: ignore

from logger import logger
from pathlib import Path
from typing import Optional, Tuple
from tkinter import messagebox, ttk


LOGGER = logger()



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
    LOGGER.info(f'Processing image: {image_path}')
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
                LOGGER.info(
                    f'QR detected in part ({row},{col})'
                    f'with data: {data.split('\n')[0]}'
                )
                
    if not found_qr:
        LOGGER.info(f'No valid QR code found in {image_path}')
    if rotate and rotate_angle:
        LOGGER.info(f'Rotating image by {rotate_angle} degrees')

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



def batch_process(
    source: str, dest: str, rotate: bool, progress:ttk.Progressbar = None
):
    """
    Batch process find_images_in_folder and use it to batch rename or rotate
    all image in a directory
    
    Args:
        source (str): Path to the source directory.
        dest (str): Path to the destination directory.
        rotate (bool): Batch rename if False, batch rotate if True.
    """
    LOGGER.info(
        f'Starting batch process on {source}'
        f'output to {dest}, rotate={rotate}'
    )
    images = find_images_in_folder(source)
    LOGGER.info(f'Found {len(images)} images to process.')
    
    total = len(images)
    for idx, image in enumerate(images):
        qr_code_data, result_image = split_image_and_detect_qr(image, rotate)
        
        if not qr_code_data:
            LOGGER.warning(f'No QR found for image: {image}')
            continue
        
        fname = qr_code_data.split('\n')[0]
        if len(fname) == 14:
            suffix = '_WB' if fname[-1] in ('B', 'P') else '_WS'
        elif len(fname) == 10:
            suffix = 'WA'
        
        fname = (
            f'{dest}/{fname}{suffix}{image.suffix}'
            if not rotate
            else f'{dest}/{Path(image).name}'
        )
        
        file_path = Path(fname)
        counter = 1
        
        while file_path.exists():
            file_path = file_path.with_name(
                f"{file_path.stem}_{counter}{file_path.suffix}"
            )
            counter += 1

        try:
            cv2.imwrite(str(file_path), result_image)
            LOGGER.info(f'Saved: {str(file_path)}')
        except Exception as e:
            LOGGER.info(f'Failed to save image {str(file_path)}: {e}')
            
        if progress:
            progress['value'] = ((idx + 1) / total) * 100
            progress.update_idletasks()

    if progress:
            progress['value'] = 0
            progress.update_idletasks()



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
    LOGGER.info(
        f'Checking point-polygon consistency for {point_path}'
        f'against {polygon_path}'
    )
    try:
        point = gpd.read_file(point_path)
        polygon = gpd.read_file(polygon_path)
    except Exception as e:
        LOGGER.error(f'Error reading files: {e}')
        return

    colname = 'iddesa' if level=='Desa' else 'idsls'
    
    if colname not in point.columns:
        messagebox.showerror(
            'Error',
            f'Column {colname} was not found in point file'
        )
        LOGGER.error(f'Column {colname} was not found in point file')

    if colname not in polygon.columns:
        messagebox.showerror(
            'Error',
            f'Column {colname} was not found in polygon file'
        )
        LOGGER.error(f'Column {colname} was not found in polygon file')

    gdf = gpd.sjoin(
        point,
        polygon[[colname, 'geometry']],
        lsuffix='pt',
        rsuffix='ea'
    )
    offside = gdf.loc[gdf[f'{colname}_pt']!=gdf[f'{colname}_ea']]
    LOGGER.info(f'Found {len(offside)} points outside their polygon')

    result = offside[[
        f'{colname}_pt', 'nama', 'wid'
    ]].groupby(f'{colname}_pt', as_index=False).agg(
        count=('nama', 'count'),
        list_id=('wid', lambda x: ', '.join(x))
    ).rename({f'{colname}_pt': colname}, axis='columns')
    
    result.to_excel(fname, index=False)
    LOGGER.info(f'Saved off-point report to {fname}')