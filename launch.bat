@echo off
REM PVE SMB Gateway - Windows Launcher
REM Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
REM Dual-licensed under AGPL-3.0 and Commercial License

setlocal enabledelayedexpansion

REM Colors for output (Windows 10+)
set "BLUE=[94m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "PURPLE=[95m"
set "CYAN=[96m"
set "NC=[0m"

REM Script directory
set "SCRIPT_DIR=%~dp0"

REM Function to print colored output
:print_status
echo %BLUE%[INFO]%NC% %~1
goto :eof

:print_success
echo %GREEN%[SUCCESS]%NC% %~1
goto :eof

:print_warning
echo %YELLOW%[WARNING]%NC% %~1
goto :eof

:print_error
echo %RED%[ERROR]%NC% %~1
goto :eof

:print_header
echo %PURPLE%================================%NC%
echo %PURPLE%  PVE SMB Gateway Launcher%NC%
echo %PURPLE%================================%NC%
echo.
goto :eof

REM Function to show menu
:show_menu
echo Available Options:
echo.
echo %CYAN%1.%NC% Install PVE SMB Gateway (GUI Installer)
echo %CYAN%2.%NC% Install PVE SMB Gateway (Quick Install)
echo %CYAN%3.%NC% Validate All Modes (Comprehensive Testing)
echo %CYAN%4.%NC% Test LXC Mode Only
echo %CYAN%5.%NC% Test Native Mode Only
echo %CYAN%6.%NC% Test VM Mode Only
echo %CYAN%7.%NC% Build Package
echo %CYAN%8.%NC% Show Documentation
echo %CYAN%9.%NC% Show Help
echo %CYAN%0.%NC% Exit
echo.
goto :eof

REM Function to install via GUI
:install_gui
call :print_status "Starting GUI installer..."
if exist "%SCRIPT_DIR%installer\run-installer.ps1" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%installer\run-installer.ps1"
) else (
    call :print_error "GUI installer not found"
    call :print_status "Please ensure you're running from the project root directory"
    exit /b 1
)
goto :eof

REM Function to show documentation
:show_documentation
echo %CYAN%PVE SMB Gateway Documentation%NC%
echo.
echo %GREEN%Quick Start:%NC%
echo 1. Install the plugin: .\launch.bat (option 1 or 2)
echo 2. Create a share: Navigate to Datacenter ^>^> Storage ^>^> Add ^>^> SMB Gateway
echo 3. Access your share: \\your-proxmox-ip\sharename
echo.
echo %GREEN%Deployment Modes:%NC%
echo - %YELLOW%LXC Mode%NC%: Lightweight containers (~80MB RAM) - Recommended
echo - %YELLOW%Native Mode%NC%: Direct host installation - Best performance
echo - %YELLOW%VM Mode%NC%: Dedicated VMs - Maximum isolation
echo.
echo %GREEN%CLI Usage:%NC%
echo - List shares: pve-smbgateway list
echo - Create share: pve-smbgateway create myshare --mode lxc --path /srv/smb/myshare
echo - Check status: pve-smbgateway status myshare
echo - Delete share: pve-smbgateway delete myshare
echo.
echo %GREEN%Documentation Files:%NC%
echo - README.md - Main documentation
echo - docs\USER_GUIDE.md - Complete user guide
echo - docs\DEV_GUIDE.md - Developer guide
echo - docs\INSTALLER_GUIDE.md - Installer documentation
echo - ALPHA_RELEASE_NOTES.md - Release notes
echo.
echo %GREEN%Support:%NC%
echo - GitHub: https://github.com/GoZippy/PVE-SMB-Gateway
echo - Issues: https://github.com/GoZippy/PVE-SMB-Gateway/issues
echo - Email: eric@gozippy.com
echo.
goto :eof

REM Function to show help
:show_help
echo %CYAN%PVE SMB Gateway Launcher - Help%NC%
echo.
echo %GREEN%Usage:%NC%
echo     .\launch.bat [OPTION]
echo.
echo %GREEN%Options:%NC%
echo     %YELLOW%1%NC% - Install via GUI installer (recommended)
echo     %YELLOW%2%NC% - Quick install (command line)
echo     %YELLOW%3%NC% - Validate all deployment modes
echo     %YELLOW%4%NC% - Test LXC mode only
echo     %YELLOW%5%NC% - Test Native mode only
echo     %YELLOW%6%NC% - Test VM mode only
echo     %YELLOW%7%NC% - Build Debian package
echo     %YELLOW%8%NC% - Show documentation
echo     %YELLOW%9%NC% - Show this help
echo     %YELLOW%0%NC% - Exit
echo.
echo %GREEN%Examples:%NC%
echo     .\launch.bat 1          # Install via GUI
echo     .\launch.bat 2          # Quick install
echo     .\launch.bat 3          # Run all tests
echo     .\launch.bat 4          # Test LXC mode
echo.
echo %GREEN%Requirements:%NC%
echo     - Proxmox VE 8.x
echo     - Root or sudo access
echo     - Internet connection (for dependencies)
echo.
echo %GREEN%Note:%NC%
echo     This is alpha software. Test thoroughly before production use.
echo     See ALPHA_RELEASE_NOTES.md for important warnings.
echo.
goto :eof

REM Function to show Windows-specific info
:show_windows_info
call :print_warning "This installer is designed for Linux/Proxmox systems."
call :print_status "On Windows, this installer will help you:"
call :print_status "1. Check system compatibility"
call :print_status "2. Prepare for installation on a Proxmox server"
call :print_status "3. Generate installation scripts"
call :print_status "4. Provide documentation and guidance"
echo.
set /p response="Continue with Windows preparation mode? (Y/n): "
if /i "%response%"=="n" (
    call :print_status "Installation cancelled."
    exit /b 0
)
goto :eof

REM Main function
:main
call :print_header

REM Check if we're in the right directory
if not exist "%SCRIPT_DIR%README.md" (
    call :print_error "README.md not found. Please run this script from the project root directory."
    exit /b 1
)

REM Show Windows-specific information
call :show_windows_info

REM Parse command line arguments
if "%~1"=="" goto :interactive_mode

if "%~1"=="1" goto :install_gui
if "%~1"=="2" goto :install_quick
if "%~1"=="3" goto :validate_all
if "%~1"=="4" goto :test_lxc
if "%~1"=="5" goto :test_native
if "%~1"=="6" goto :test_vm
if "%~1"=="7" goto :build_package
if "%~1"=="8" goto :show_documentation
if "%~1"=="9" goto :show_help
if "%~1"=="0" goto :exit_script

call :print_error "Invalid option: %~1"
call :show_help
exit /b 1

:interactive_mode
:menu_loop
call :show_menu
set /p choice="Enter your choice (0-9): "

if "%choice%"=="1" goto :install_gui
if "%choice%"=="2" goto :install_quick
if "%choice%"=="3" goto :validate_all
if "%choice%"=="4" goto :test_lxc
if "%choice%"=="5" goto :test_native
if "%choice%"=="6" goto :test_vm
if "%choice%"=="7" goto :build_package
if "%choice%"=="8" goto :show_documentation
if "%choice%"=="9" goto :show_help
if "%choice%"=="0" goto :exit_script

call :print_error "Invalid choice. Please enter a number between 0 and 9."
goto :menu_loop

:install_gui
call :install_gui
goto :end

:install_quick
call :print_status "Quick install not available on Windows."
call :print_status "Please use option 1 for GUI installer or install on a Proxmox host."
goto :end

:validate_all
call :print_status "Validation not available on Windows."
call :print_status "Please run validation on a Proxmox host."
goto :end

:test_lxc
call :print_status "Testing not available on Windows."
call :print_status "Please run tests on a Proxmox host."
goto :end

:test_native
call :print_status "Testing not available on Windows."
call :print_status "Please run tests on a Proxmox host."
goto :end

:test_vm
call :print_status "Testing not available on Windows."
call :print_status "Please run tests on a Proxmox host."
goto :end

:build_package
call :print_status "Package building not available on Windows."
call :print_status "Please build packages on a Linux/Proxmox host."
goto :end

:show_documentation
call :show_documentation
goto :end

:show_help
call :show_help
goto :end

:exit_script
call :print_status "Exiting..."
exit /b 0

:end
pause
exit /b 0 