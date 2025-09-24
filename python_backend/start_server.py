import os
import sys

# Add embedded Python to path
current_dir = os.path.dirname(os.path.abspath(__file__))
embedded_python_dir = os.path.join(current_dir, "..", "embedded_python")
embedded_lib = os.path.join(embedded_python_dir, "Lib")
embedded_site_packages = os.path.join(embedded_lib, "site-packages")

# Add paths to sys.path
sys.path.insert(0, current_dir)
sys.path.insert(0, embedded_site_packages)
sys.path.insert(0, embedded_lib)

print("=== Starting Python Server ===")
print(f"Python: {sys.executable}")
print(f"Working dir: {os.getcwd()}")

# List files in current directory for debugging
print("Files in current directory:")
for file in os.listdir(current_dir):
    if file.endswith('.py'):
        print(f"  - {file}")

try:
    # Try different import methods
    try:
        # Method 1: Regular import
        from api_server import app
        print("API server imported using regular import")
    except ImportError:
        # Method 2: Absolute import
        import importlib.util
        spec = importlib.util.spec_from_file_location("api_server", os.path.join(current_dir, "api_server.py"))
        api_server = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(api_server)
        app = api_server.app
        print("API server imported using absolute path")
    
    print("Starting server on http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=False)
        
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
    input("Press Enter to exit...")