import logger
import main_function
import tkinter as tk
import threading

from tkinter import filedialog, messagebox, ttk



LOGGER = logger.logger()
logger.clean_old_logs(log_dir=".", pattern="app.log", days=7)



def browse_folder(entry: tk.Entry):
    """
    Opens a dialog window for the user to select a folder.
    Inserts the selected folder path into the provided entry widget.

    Args:
        entry (tk.Entry): The Tkinter entry widget to populate with the folder
                          path.
    """
    try:
        folder_path = filedialog.askdirectory(
            title='Select Folder'
        )
        if folder_path:
            entry.delete(0, tk.END)
            entry.insert(0, folder_path)
            LOGGER.info(f'Selected folder: {folder_path}')

    except Exception as e:
        LOGGER.error(f'Error selecting folder: {e}')



def browse_save(entry: tk.Entry):
    """
    Open windows to browse save file destination.
    
    Args:
        entry (tk.Entry): The Tkinter entry widget to populate with the folder
                          path.
    """
    try:
        filepath = filedialog.asksaveasfilename(
            title='Save File',
            defaultextension='.xlsx',  
            filetypes=[('Excel files', '*.xlsx'), ('CSV files', '*.csv')] 
        )
        if filepath:
            entry.delete(0, tk.END)
            entry.insert(0, filepath)
            LOGGER.info(f'Save file path selected: {filepath}')

    except Exception as e:
        LOGGER.error(f'Error selecting file path: {e}')



def browse_open(entry: tk.Entry):
    """
    Open windows to browse files to be opened.
    
    Args:
        entry (tk.Entry): The Tkinter entry widget to populate with the folder
                          path.
    """
    try:
        filepath = filedialog.askopenfilename(
            title='Open File',
            defaultextension='.gpkg',
            filetypes=[('QGIS files', '*.gpkg'), ('geojson files', '*.geojson')] 
        )
        if filepath:
            entry.delete(0, tk.END)
            entry.insert(0, filepath)
            LOGGER.info(f'Selected file to open: {filepath}')
    
    except Exception as e:
        LOGGER.error(f'Error opening file: {e}')



def run_process(
    source_entry: tk.Entry,
    result_entry: tk.Entry, 
    rotate: bool,
    progress: ttk.Progressbar
):
    """
    Retrieves paths from entry widgets and attempts to run a QR code renaming
    process.

    Args:
        rename_source_entry (tk.Entry): Entry widget containing the path to the
                                        image or folder to process.
        rename_result_entry (tk.Entry): Entry widget containing the destination
                                        or result path.

    Raises:
        Shows a messagebox error if any exception occurs during processing.
    """
    def worker():
        try:
            SOURCE = source_entry.get()
            RESULT = result_entry.get()

            main_function.batch_process(
                source=SOURCE,
                dest=RESULT,
                rotate=rotate,
                progress=progress
            )

            messagebox.showinfo(
                'Success', 
                'Process completed successfully.'
            )
            LOGGER.info('Batch process completed successfully.')

        except Exception as e:
            messagebox.showerror(
                'Error',
                f'An error occurred: {str(e)}'
            )
            LOGGER.error(f'Error in batch process: {e}')

    # Run in separate thread to keep UI responsive
    threading.Thread(target=worker).start()



def run_off_search(
    point_entry: tk.Entry,
    polygon_entry: tk.Entry,
    result_entry: tk.Entry,
    level_entry: ttk.Combobox
):
    """
    Retrieves paths from entry widgets and attempts to run a QR code renaming
    process.

    Args:
        point_entry (tk.Entry): Entry widget containing the path to the
                                point file to process.
        polygon_entry (tk.Entry): Entry widget containing the path to the
                                  polygon file to process.
        result_entry (tk.Entry): Entry widget containing the destination
                                 or result path.
        level (ttk.Combobox): Combobox widget containing the level where the
                              comparison was made.

    Raises:
        Shows a messagebox error if any exception occurs during processing.
    """
    try:
        POINT = point_entry.get()
        POLYGON = polygon_entry.get()
        RESULT = result_entry.get()
        LEVEL = level_entry.get()
        
        main_function.search_off_point(
            point_path=POINT,
            polygon_path=POLYGON,
            fname=RESULT,
            level=LEVEL
        )
        
        messagebox.showinfo(
            'Success', 
            'Process completed successfully.'
        )
        LOGGER.info('Searching off-points completed succesfully')

    except Exception as e:
        messagebox.showerror(
            'Error',
            f'An error occured: {str(e)}'
        )
        LOGGER.error(f'Error in searching off-points: {e}')



root = tk.Tk()
root.title('WAP')

notebook = ttk.Notebook(root)
notebook.pack(expand=True, fill='both')

tab1 = ttk.Frame(notebook)
tab2 = ttk.Frame(notebook)
tab3 = ttk.Frame(notebook)

notebook.add(tab1, text='Rename')
notebook.add(tab2, text='Rotate')
notebook.add(tab3, text='Off-point')



# tab1
tk.Label(
    tab1, text='Select the source folder', width=20, anchor='w'
).grid(
    row=0, column=0, padx=10, pady=10
)
rename_source_entry = tk.Entry(tab1, width=60)
rename_source_entry.grid(row=0, column=1, padx=10, sticky='we')
tk.Button(
    tab1, text='Browse', 
    command=lambda: browse_folder(rename_source_entry), width=10
).grid(
    row=0, column=2, padx=10
)

tk.Label(
    tab1, text='Select the result folder', width=20, anchor='w'
).grid(
    row=1, column=0, padx=10, pady=10
)
rename_result_entry = tk.Entry(tab1, width=60)
rename_result_entry.grid(row=1, column=1, padx=10, sticky='we')
tk.Button(
    tab1, text='Browse',
    command=lambda: browse_folder(rename_result_entry), width=10
).grid(
    row=1, column=2, padx=10
)

rename_progress_bar = ttk.Progressbar(
    tab1, orient='horizontal', mode='determinate', length=400
)
rename_progress_bar.grid(
    row=2, column=0, columnspan=3, padx=10, pady=10, sticky='we'
)

rename_run_button = tk.Button(
    tab1,
    text='Start',
    command=lambda: run_process(
        source_entry=rename_source_entry,
        result_entry=rename_result_entry,
        rotate=False,
        progress=rename_progress_bar
    ),
    width=20)
rename_run_button.grid(row=3, column=0, columnspan=3, pady=20)



# tab2
tk.Label(
    tab2, text='Select the source folder', width=20, anchor='w'
).grid(
    row=0, column=0, padx=10, pady=10
)
rotate_source_entry = tk.Entry(tab2, width=60)
rotate_source_entry.grid(row=0, column=1, padx=10, sticky='we')
tk.Button(
    tab2, text='Browse',
    command=lambda: browse_folder(rotate_source_entry), width=10
).grid(
    row=0, column=2, padx=10
)

tk.Label(
    tab2, text='Select the result folder', width=20, anchor='w'
).grid(
    row=1, column=0, padx=10, pady=10
)
rotate_result_entry = tk.Entry(tab2, width=60)
rotate_result_entry.grid(row=1, column=1, padx=10, sticky='we')
tk.Button(
    tab2, text='Browse',
    command=lambda: browse_folder(rotate_result_entry), width=10
).grid(
    row=1, column=2, padx=10
)

rotate_progress_bar = ttk.Progressbar(
    tab2, orient='horizontal', mode='determinate', length=400
)
rotate_progress_bar.grid(
    row=2, column=0, columnspan=3, padx=10, pady=10, sticky='we'
)

rotate_run_button = tk.Button(
    tab2,
    text='Start',
    command=lambda: run_process(
        source_entry=rotate_source_entry,
        result_entry=rotate_result_entry,
        rotate=True,
        progress=rotate_progress_bar
    ),
    width=20)
rotate_run_button.grid(row=3, column=0, columnspan=3, pady=20)



# tab3
tk.Label(
    tab3, text='Point file', width=20, anchor='w'
).grid(
    row=0, column=0, padx=10, pady=10
)
point_source_entry = tk.Entry(tab3, width=60)
point_source_entry.grid(row=0, column=1, padx=10, sticky='we')
tk.Button(
    tab3, text='Browse',
    command=lambda: browse_open(point_source_entry), width=10
).grid(
    row=0, column=2, padx=10
)

tk.Label(
    tab3, text='Polygon file', width=20, anchor='w'
).grid(
    row=1, column=0, padx=10, pady=10
)
polygon_source_entry = tk.Entry(tab3, width=60)
polygon_source_entry.grid(row=1, column=1, padx=10, sticky='we')
tk.Button(
    tab3, text='Browse',
    command=lambda: browse_open(polygon_source_entry), width=10
).grid(
    row=1, column=2, padx=10
)

tk.Label(
    tab3, text='Result file', width=20, anchor='w'
).grid(
    row=2, column=0, padx=10, pady=10
)
off_result_entry = tk.Entry(tab3, width=60)
off_result_entry.grid(row=2, column=1, padx=10, sticky='we')
tk.Button(
    tab3, text='Browse',
    command=lambda: browse_save(off_result_entry), width=10
).grid(
    row=2, column=2, padx=10
)

tk.Label(
    tab3, text='Level', width=20, anchor='w'
).grid(
    row=3, column=0, padx=10, pady=10
)
level = ['Desa', 'SLS']
level_entry = ttk.Combobox(tab3, values=level, width=50)
level_entry.set(level[0])
level_entry.grid(
    row=3, column=1, columnspan=2, padx=10, pady=10, sticky='we'
)

off_run_button = tk.Button(
    tab3,
    text='Start',
    command=lambda: run_off_search(
        point_entry=point_source_entry,
        polygon_entry=polygon_source_entry,
        result_entry=off_result_entry,
        level_entry=level_entry
    ),
    width=20)
off_run_button.grid(row=4, column=0, columnspan=3, pady=20)



root.mainloop()