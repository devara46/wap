package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

type AppConfig struct {
	AppName       string
	BinDir        string
	AppExe        string
	PythonDir     string
	PythonExe     string
	BackendDir    string
	BackendScript string
	DataDir       string
	FlutterDLL    string
}

func main() {
	config := &AppConfig{
		AppName: "WAP Application",
	}

	// Setup paths
	exePath, err := os.Executable()
	if err != nil {
		showError("Cannot get executable path", err)
		return
	}

	exeDir := filepath.Dir(exePath)
	config.BinDir = filepath.Join(exeDir, "bin")
	config.AppExe = filepath.Join(config.BinDir, "wap.exe")
	config.PythonDir = filepath.Join(config.BinDir, "embedded_python")
	config.PythonExe = filepath.Join(config.PythonDir, "python.exe")
	config.BackendDir = filepath.Join(config.BinDir, "python_backend")
	config.BackendScript = filepath.Join(config.BackendDir, "start_server.py")
	config.DataDir = filepath.Join(config.BinDir, "data")
	config.FlutterDLL = filepath.Join(config.BinDir, "flutter_windows.dll")

	// Validate all required files
	if !validateEnvironment(config) {
		return
	}

	// Start Python backend server
	pythonProcess, err := startPythonBackend(config)
	if err != nil {
		showError("Failed to start Python backend", err)
		return
	}

	// Wait a moment for the Python server to start
	fmt.Println("Waiting for Python server to start...")
	time.Sleep(3 * time.Second)

	// Start the Flutter application
	if err := startFlutterApplication(config, pythonProcess); err != nil {
		showError("Failed to start Flutter application", err)
		// Try to kill Python process if Flutter fails
		if pythonProcess != nil {
			pythonProcess.Process.Kill()
		}
		return
	}
}

func validateEnvironment(config *AppConfig) bool {
	requiredFiles := []struct {
		path string
		name string
	}{
		{config.AppExe, "Main application (wap.exe)"},
		{config.FlutterDLL, "Flutter DLL (flutter_windows.dll)"},
		{config.PythonExe, "Python executable"},
		{config.BackendScript, "Python backend script (start_server.py)"},
		{config.PythonDir, "Python backend"},
		{config.DataDir, "Data directory"},
	}

	fmt.Println("Checking required files...")
	allValid := true

	for _, file := range requiredFiles {
		if _, err := os.Stat(file.path); os.IsNotExist(err) {
			fmt.Printf("❌ %s not found: %s\n", file.name, file.path)
			allValid = false
		} else {
			fmt.Printf("✓ %s found\n", file.name)
		}
	}

	return allValid
}

func startPythonBackend(config *AppConfig) (*exec.Cmd, error) {
	fmt.Printf("\nStarting Python backend server...\n")
	fmt.Printf("Python executable: %s\n", config.PythonExe)
	
	// Use start_server.py instead of api_server.py
	startScript := filepath.Join(config.BackendDir, "start_server.py")
	fmt.Printf("Start script: %s\n", startScript)

	// Check if start_server.py exists
	if _, err := os.Stat(startScript); os.IsNotExist(err) {
		return nil, fmt.Errorf("start_server.py not found at: %s", startScript)
	}

	cmd := exec.Command(config.PythonExe, "start_server.py")
	cmd.Dir = config.BackendDir
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP,
	}

	// Hide the console window
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow: true,  // This hides the console window
	}


	// Create log file for Python backend
	pythonLogFile, err := os.Create(filepath.Join(config.BinDir, "python_server.log"))
	if err != nil {
		return nil, fmt.Errorf("failed to create log file: %w", err)
	}

	cmd.Stdout = pythonLogFile
	cmd.Stderr = pythonLogFile

	fmt.Printf("Executing: %s start_server.py\n", config.PythonExe)
	fmt.Printf("Working directory: %s\n", cmd.Dir)

	err = cmd.Start()
	if err != nil {
		pythonLogFile.Close()
		return nil, fmt.Errorf("failed to start Python backend: %w", err)
	}

	fmt.Printf("✓ Python backend started (PID: %d)\n", cmd.Process.Pid)
	fmt.Printf("✓ Python server log: %s\\python_server.log\n", config.BinDir)

	return cmd, nil
}

func startFlutterApplication(config *AppConfig, pythonProcess *exec.Cmd) error {
	fmt.Printf("\nStarting Flutter application...\n")
	fmt.Printf("Application: %s\n", config.AppExe)
	fmt.Printf("Working directory: %s\n", config.BinDir)

	cmd := exec.Command(config.AppExe)
	cmd.Dir = config.BinDir
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP,
	}

	// Create log file for Flutter app
	flutterLogFile, err := os.Create(filepath.Join(config.BinDir, "flutter_app.log"))
	if err != nil {
		return fmt.Errorf("failed to create log file: %w", err)
	}
	defer flutterLogFile.Close()

	cmd.Stdout = flutterLogFile
	cmd.Stderr = flutterLogFile

	err = cmd.Start()
	if err != nil {
		return fmt.Errorf("failed to start Flutter application: %w", err)
	}

	fmt.Printf("✓ Flutter application started (PID: %d)\n", cmd.Process.Pid)
	fmt.Printf("✓ Flutter app log: %s\\flutter_app.log\n", config.BinDir)
	fmt.Println("✓ Both Python server and Flutter app are running...")
	fmt.Println("✓ Application should be available shortly...")

	// Wait for the Flutter app to exit
	err = cmd.Wait()
	if err != nil {
		fmt.Printf("Flutter application exited with error: %v\n", err)
	} else {
		fmt.Println("Flutter application exited successfully")
	}

	// Cleanup: Kill Python process when Flutter app closes
	if pythonProcess != nil {
		fmt.Println("Shutting down Python backend...")
		pythonProcess.Process.Kill()
		pythonProcess.Wait()
		fmt.Println("Python backend stopped")
	}

	return nil
}

func showError(title string, err error) {
	fmt.Printf("\nERROR: %s\n", title)
	if err != nil {
		fmt.Printf("Details: %v\n", err)
	}
	fmt.Println("\nPress Enter to exit...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}