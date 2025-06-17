import logging
from logging import Logger
from typing import Optional
import os
import time


    
def logger(name: Optional[str] = None) -> Logger:
    """
    Configures and returns a logger with both file and stream handlers.
    Prevents duplicate handlers and supports named loggers.

    Args:
        name (str, optional): Name of the logger. Defaults to module name.

    Returns:
        Logger: A configured logger instance.
    """
    logger_name = name if name else __name__
    log = logging.getLogger(logger_name)
    
    if not log.handlers:  # Prevent adding handlers multiple times
        log.setLevel(logging.INFO)

        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )

        # File Handler
        file_handler = logging.FileHandler('app.log')
        file_handler.setFormatter(formatter)
        log.addHandler(file_handler)

        # Stream Handler (console)
        stream_handler = logging.StreamHandler()
        stream_handler.setFormatter(formatter)
        log.addHandler(stream_handler)

    return log



def clean_old_logs(log_dir: str = '.', pattern: str = 'app.log', days: int = 7):
    """
    Deletes log files older than a given number of days.

    Args:
        log_dir (str): Directory containing log files. Defaults to current directory.
        pattern (str): Name or prefix of log files to delete.
        days (int): Number of days to retain logs. Older logs will be deleted.
    """
    now = time.time()
    cutoff = now - days * 86400  # 86400 seconds in a day

    for filename in os.listdir(log_dir):
        if filename.startswith(pattern):
            file_path = os.path.join(log_dir, filename)
            if os.path.isfile(file_path):
                file_mtime = os.path.getmtime(file_path)
                if file_mtime < cutoff:
                    try:
                        os.remove(file_path)
                        print(f'Deleted old log file: {file_path}')
                    except Exception as e:
                        print(f'Failed to delete {file_path}: {e}')