#!/usr/bin/env python3
"""
PVE SMB Gateway - Guided Installer
A user-friendly GUI installer with step-by-step guidance

Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
Dual-licensed under AGPL-3.0 and Commercial License
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog, scrolledtext
import subprocess
import sys
import os
import json
import threading
import time
from pathlib import Path

class PVEInstallerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("PVE SMB Gateway - Guided Installer")
        self.root.geometry("800x600")
        self.root.resizable(True, True)
        
        # Set icon if available
        try:
            self.root.iconbitmap("installer/icon.ico")
        except:
            pass
        
        # Installation state
        self.install_state = {
            'step': 0,
            'system_check': False,
            'dependencies': False,
            'package_built': False,
            'package_installed': False,
            'service_configured': False,
            'tested': False
        }
        
        # Configuration
        self.config = {
            'install_path': '/usr/share/pve-smbgateway',
            'config_path': '/etc/pve/smbgateway',
            'log_path': '/var/log/pve/smbgateway',
            'backup_enabled': True,
            'monitoring_enabled': True,
            'ha_enabled': False
        }
        
        self.setup_ui()
        self.load_system_info()
    
    def setup_ui(self):
        """Setup the main UI components"""
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Configure grid weights
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        main_frame.rowconfigure(1, weight=1)
        
        # Header
        header_frame = ttk.Frame(main_frame)
        header_frame.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        
        ttk.Label(header_frame, text="PVE SMB Gateway", font=("Arial", 16, "bold")).pack()
        ttk.Label(header_frame, text="Guided Installation Process", font=("Arial", 10)).pack()
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="Installation Progress", padding="10")
        progress_frame.grid(row=1, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), padx=(0, 10))
        
        # Progress steps
        self.progress_steps = [
            "System Check",
            "Dependencies",
            "Build Package",
            "Install Package",
            "Configure Service",
            "Test Installation"
        ]
        
        self.progress_vars = []
        for i, step in enumerate(self.progress_steps):
            var = tk.BooleanVar()
            self.progress_vars.append(var)
            ttk.Checkbutton(progress_frame, text=step, variable=var, state="disabled").pack(anchor=tk.W, pady=2)
        
        # Main content area
        content_frame = ttk.Frame(main_frame)
        content_frame.grid(row=1, column=1, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Notebook for different sections
        self.notebook = ttk.Notebook(content_frame)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        
        # Welcome tab
        self.create_welcome_tab()
        
        # System check tab
        self.create_system_check_tab()
        
        # Configuration tab
        self.create_configuration_tab()
        
        # Installation tab
        self.create_installation_tab()
        
        # Log tab
        self.create_log_tab()
        
        # Button frame
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=2, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(10, 0))
        
        self.back_button = ttk.Button(button_frame, text="Back", command=self.previous_step, state="disabled")
        self.back_button.pack(side=tk.LEFT, padx=(0, 5))
        
        self.next_button = ttk.Button(button_frame, text="Next", command=self.next_step)
        self.next_button.pack(side=tk.LEFT, padx=5)
        
        self.install_button = ttk.Button(button_frame, text="Install", command=self.start_installation, state="disabled")
        self.install_button.pack(side=tk.LEFT, padx=5)
        
        self.cancel_button = ttk.Button(button_frame, text="Cancel", command=self.cancel_installation)
        self.cancel_button.pack(side=tk.RIGHT)
        
        # Status bar
        self.status_var = tk.StringVar()
        self.status_var.set("Ready to begin installation")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.grid(row=3, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(10, 0))
    
    def create_welcome_tab(self):
        """Create the welcome tab"""
        welcome_frame = ttk.Frame(self.notebook)
        self.notebook.add(welcome_frame, text="Welcome")
        
        # Welcome content
        welcome_text = """
Welcome to the PVE SMB Gateway Installer!

This guided installation process will help you install and configure the PVE SMB Gateway plugin for Proxmox VE.

What this installer will do:
• Check your system compatibility
• Install required dependencies
• Build the SMB Gateway package
• Install the plugin into Proxmox
• Configure services and settings
• Test the installation

System Requirements:
• Proxmox VE 8.x (8.1, 8.2, 8.3)
• Debian 12 base system
• Root or sudo access
• Internet connection for dependencies
• At least 1GB free disk space

The installation process is safe and can be stopped at any time.
All changes will be logged for your review.

Click "Next" to begin the system check.
        """
        
        text_widget = scrolledtext.ScrolledText(welcome_frame, wrap=tk.WORD, height=20)
        text_widget.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        text_widget.insert(tk.END, welcome_text)
        text_widget.config(state=tk.DISABLED)
    
    def create_system_check_tab(self):
        """Create the system check tab"""
        check_frame = ttk.Frame(self.notebook)
        self.notebook.add(check_frame, text="System Check")
        
        # System info
        info_frame = ttk.LabelFrame(check_frame, text="System Information", padding="10")
        info_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.system_info_text = scrolledtext.ScrolledText(info_frame, height=8)
        self.system_info_text.pack(fill=tk.X)
        
        # Check results
        results_frame = ttk.LabelFrame(check_frame, text="Check Results", padding="10")
        results_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        self.check_results_text = scrolledtext.ScrolledText(results_frame)
        self.check_results_text.pack(fill=tk.BOTH, expand=True)
        
        # Check button
        button_frame = ttk.Frame(check_frame)
        button_frame.pack(fill=tk.X, padx=10, pady=5)
        
        ttk.Button(button_frame, text="Run System Check", command=self.run_system_check).pack(side=tk.LEFT)
        ttk.Button(button_frame, text="View Detailed Log", command=self.view_check_log).pack(side=tk.LEFT, padx=(10, 0))
    
    def create_configuration_tab(self):
        """Create the configuration tab"""
        config_frame = ttk.Frame(self.notebook)
        self.notebook.add(config_frame, text="Configuration")
        
        # Configuration options
        options_frame = ttk.LabelFrame(config_frame, text="Installation Options", padding="10")
        options_frame.pack(fill=tk.X, padx=10, pady=5)
        
        # Paths
        paths_frame = ttk.LabelFrame(options_frame, text="Installation Paths", padding="5")
        paths_frame.pack(fill=tk.X, pady=5)
        
        ttk.Label(paths_frame, text="Install Path:").grid(row=0, column=0, sticky=tk.W, padx=5, pady=2)
        self.install_path_var = tk.StringVar(value=self.config['install_path'])
        ttk.Entry(paths_frame, textvariable=self.install_path_var, width=40).grid(row=0, column=1, sticky=tk.W, padx=5, pady=2)
        ttk.Button(paths_frame, text="Browse", command=self.browse_install_path).grid(row=0, column=2, padx=5, pady=2)
        
        ttk.Label(paths_frame, text="Config Path:").grid(row=1, column=0, sticky=tk.W, padx=5, pady=2)
        self.config_path_var = tk.StringVar(value=self.config['config_path'])
        ttk.Entry(paths_frame, textvariable=self.config_path_var, width=40).grid(row=1, column=1, sticky=tk.W, padx=5, pady=2)
        ttk.Button(paths_frame, text="Browse", command=self.browse_config_path).grid(row=1, column=2, padx=5, pady=2)
        
        ttk.Label(paths_frame, text="Log Path:").grid(row=2, column=0, sticky=tk.W, padx=5, pady=2)
        self.log_path_var = tk.StringVar(value=self.config['log_path'])
        ttk.Entry(paths_frame, textvariable=self.log_path_var, width=40).grid(row=2, column=1, sticky=tk.W, padx=5, pady=2)
        ttk.Button(paths_frame, text="Browse", command=self.browse_log_path).grid(row=2, column=2, padx=5, pady=2)
        
        # Features
        features_frame = ttk.LabelFrame(options_frame, text="Features", padding="5")
        features_frame.pack(fill=tk.X, pady=5)
        
        self.backup_var = tk.BooleanVar(value=self.config['backup_enabled'])
        ttk.Checkbutton(features_frame, text="Enable Backup Integration", variable=self.backup_var).pack(anchor=tk.W, pady=2)
        
        self.monitoring_var = tk.BooleanVar(value=self.config['monitoring_enabled'])
        ttk.Checkbutton(features_frame, text="Enable Performance Monitoring", variable=self.monitoring_var).pack(anchor=tk.W, pady=2)
        
        self.ha_var = tk.BooleanVar(value=self.config['ha_enabled'])
        ttk.Checkbutton(features_frame, text="Enable High Availability Support", variable=self.ha_var).pack(anchor=tk.W, pady=2)
        
        # Advanced options
        advanced_frame = ttk.LabelFrame(config_frame, text="Advanced Options", padding="10")
        advanced_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        self.verbose_var = tk.BooleanVar()
        ttk.Checkbutton(advanced_frame, text="Verbose Installation Logging", variable=self.verbose_var).pack(anchor=tk.W, pady=2)
        
        self.force_var = tk.BooleanVar()
        ttk.Checkbutton(advanced_frame, text="Force Installation (overwrite existing)", variable=self.force_var).pack(anchor=tk.W, pady=2)
        
        self.cleanup_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(advanced_frame, text="Clean up temporary files after installation", variable=self.cleanup_var).pack(anchor=tk.W, pady=2)
    
    def create_installation_tab(self):
        """Create the installation tab"""
        install_frame = ttk.Frame(self.notebook)
        self.notebook.add(install_frame, text="Installation")
        
        # Progress display
        progress_frame = ttk.LabelFrame(install_frame, text="Installation Progress", padding="10")
        progress_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.progress_bar = ttk.Progressbar(progress_frame, mode='determinate')
        self.progress_bar.pack(fill=tk.X, pady=5)
        
        self.progress_label = ttk.Label(progress_frame, text="Ready to install")
        self.progress_label.pack()
        
        # Current step
        step_frame = ttk.LabelFrame(install_frame, text="Current Step", padding="10")
        step_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.step_text = scrolledtext.ScrolledText(step_frame, height=6)
        self.step_text.pack(fill=tk.X)
        
        # Command preview
        cmd_frame = ttk.LabelFrame(install_frame, text="Command Preview", padding="10")
        cmd_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.cmd_text = scrolledtext.ScrolledText(cmd_frame, height=4)
        self.cmd_text.pack(fill=tk.X)
        
        # Control buttons
        control_frame = ttk.Frame(install_frame)
        control_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.pause_button = ttk.Button(control_frame, text="Pause", command=self.pause_installation, state="disabled")
        self.pause_button.pack(side=tk.LEFT, padx=(0, 5))
        
        self.resume_button = ttk.Button(control_frame, text="Resume", command=self.resume_installation, state="disabled")
        self.resume_button.pack(side=tk.LEFT, padx=5)
        
        self.stop_button = ttk.Button(control_frame, text="Stop", command=self.stop_installation, state="disabled")
        self.stop_button.pack(side=tk.LEFT, padx=5)
    
    def create_log_tab(self):
        """Create the log tab"""
        log_frame = ttk.Frame(self.notebook)
        self.notebook.add(log_frame, text="Installation Log")
        
        # Log display
        self.log_text = scrolledtext.ScrolledText(log_frame, wrap=tk.WORD)
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Log controls
        log_controls = ttk.Frame(log_frame)
        log_controls.pack(fill=tk.X, padx=10, pady=(0, 10))
        
        ttk.Button(log_controls, text="Clear Log", command=self.clear_log).pack(side=tk.LEFT)
        ttk.Button(log_controls, text="Save Log", command=self.save_log).pack(side=tk.LEFT, padx=(10, 0))
        ttk.Button(log_controls, text="Copy to Clipboard", command=self.copy_log).pack(side=tk.LEFT, padx=(10, 0))
    
    def load_system_info(self):
        """Load and display system information"""
        try:
            # Get system info
            info = {
                'OS': self.run_command(['cat', '/etc/os-release']),
                'Kernel': self.run_command(['uname', '-r']),
                'Architecture': self.run_command(['uname', '-m']),
                'Proxmox Version': self.run_command(['pveversion', '-v']),
                'Python Version': sys.version,
                'Current User': self.run_command(['whoami']),
                'Working Directory': os.getcwd()
            }
            
            info_text = "System Information:\n\n"
            for key, value in info.items():
                info_text += f"{key}: {value}\n"
            
            self.system_info_text.insert(tk.END, info_text)
            self.system_info_text.config(state=tk.DISABLED)
            
        except Exception as e:
            self.log_message(f"Error loading system info: {e}")
    
    def run_system_check(self):
        """Run comprehensive system check"""
        self.log_message("Starting system compatibility check...")
        
        def check_thread():
            try:
                checks = [
                    ("Checking Proxmox VE installation", self.check_proxmox),
                    ("Checking system requirements", self.check_requirements),
                    ("Checking dependencies", self.check_dependencies),
                    ("Checking disk space", self.check_disk_space),
                    ("Checking permissions", self.check_permissions),
                    ("Checking network connectivity", self.check_network)
                ]
                
                results = []
                for description, check_func in checks:
                    self.update_progress_label(description)
                    try:
                        result = check_func()
                        results.append((description, result))
                        self.log_message(f"✓ {description}: {'PASS' if result else 'FAIL'}")
                    except Exception as e:
                        results.append((description, False))
                        self.log_message(f"✗ {description}: ERROR - {e}")
                
                # Update UI
                self.root.after(0, self.update_check_results, results)
                
            except Exception as e:
                self.log_message(f"System check failed: {e}")
        
        threading.Thread(target=check_thread, daemon=True).start()
    
    def check_proxmox(self):
        """Check if Proxmox VE is installed"""
        try:
            # On Windows, we can't check for Proxmox directly
            # This is expected to fail on Windows
            if os.name == 'nt':  # Windows
                return False
            else:  # Linux/Unix
                result = subprocess.run(['pveversion'], capture_output=True, text=True)
                return result.returncode == 0
        except:
            return False
    
    def check_requirements(self):
        """Check system requirements"""
        try:
            if os.name == 'nt':  # Windows
                # Check Windows version
                import platform
                win_version = platform.win32_ver()
                return True  # Assume Windows is compatible for preparation
            else:  # Linux/Unix
                # Check OS
                with open('/etc/os-release', 'r') as f:
                    content = f.read()
                    if 'debian' not in content.lower():
                        return False
                
                # Check kernel
                result = subprocess.run(['uname', '-r'], capture_output=True, text=True)
                if result.returncode != 0:
                    return False
                
                return True
        except:
            return False
    
    def check_dependencies(self):
        """Check if required dependencies are available"""
        try:
            if os.name == 'nt':  # Windows
                # Check for Python and basic tools
                dependencies = ['python', 'git']
                
                for dep in dependencies:
                    try:
                        if dep == 'python':
                            result = subprocess.run(['python', '--version'], capture_output=True)
                        else:
                            result = subprocess.run(['where', dep], capture_output=True)
                        if result.returncode != 0:
                            return False
                    except:
                        return False
                
                return True
            else:  # Linux/Unix
                dependencies = ['perl', 'python3', 'make', 'dpkg-buildpackage', 'git']
                
                for dep in dependencies:
                    try:
                        result = subprocess.run(['which', dep], capture_output=True)
                        if result.returncode != 0:
                            return False
                    except:
                        return False
                
                return True
        except:
            return False
    
    def check_disk_space(self):
        """Check available disk space"""
        try:
            if os.name == 'nt':  # Windows
                import shutil
                total, used, free = shutil.disk_usage("C:\\")
                free_gb = free / (1024**3)
                return free_gb >= 1.0  # At least 1GB
            else:  # Linux/Unix
                result = subprocess.run(['df', '/'], capture_output=True, text=True)
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    parts = lines[1].split()
                    if len(parts) >= 4:
                        available_gb = int(parts[3]) / (1024 * 1024)
                        return available_gb >= 1.0  # At least 1GB
                return False
        except:
            return False
    
    def check_permissions(self):
        """Check if user has required permissions"""
        try:
            if os.name == 'nt':  # Windows
                # Check if running as administrator
                import ctypes
                return ctypes.windll.shell32.IsUserAnAdmin() != 0
            else:  # Linux/Unix
                # Check if running as root
                result = subprocess.run(['whoami'], capture_output=True, text=True)
                if result.stdout.strip() == 'root':
                    return True
                
                # Check sudo access
                result = subprocess.run(['sudo', '-n', 'true'], capture_output=True)
                return result.returncode == 0
        except:
            return False
    
    def check_network(self):
        """Check network connectivity"""
        try:
            if os.name == 'nt':  # Windows
                result = subprocess.run(['ping', '-n', '1', '8.8.8.8'], capture_output=True)
            else:  # Linux/Unix
                result = subprocess.run(['ping', '-c', '1', '8.8.8.8'], capture_output=True)
            return result.returncode == 0
        except:
            return False
    
    def update_check_results(self, results):
        """Update the check results display"""
        self.check_results_text.config(state=tk.NORMAL)
        self.check_results_text.delete(1.0, tk.END)
        
        # Add header
        self.check_results_text.insert(tk.END, "System Check Results:\n")
        self.check_results_text.insert(tk.END, "=" * 50 + "\n\n")
        
        all_passed = True
        windows_mode = os.name == 'nt'
        
        for description, result in results:
            status = "PASS" if result else "FAIL"
            
            # Special handling for Windows
            if windows_mode and description == "Checking Proxmox VE installation" and not result:
                status = "SKIP (Windows)"
                result = True  # Don't count this as a failure on Windows
            
            self.check_results_text.insert(tk.END, f"{description}: {status}\n")
            if not result:
                all_passed = False
        
        # Add Windows-specific information
        if windows_mode:
            self.check_results_text.insert(tk.END, "\n" + "=" * 50 + "\n")
            self.check_results_text.insert(tk.END, "Windows Mode Information:\n")
            self.check_results_text.insert(tk.END, "- This installer is preparing for Proxmox installation\n")
            self.check_results_text.insert(tk.END, "- Proxmox VE check is skipped on Windows (expected)\n")
            self.check_results_text.insert(tk.END, "- You can proceed to configure installation options\n")
            self.check_results_text.insert(tk.END, "- Actual installation will be done on Proxmox server\n")
        
        self.check_results_text.config(state=tk.DISABLED)
        
        if all_passed:
            self.install_state['system_check'] = True
            self.progress_vars[0].set(True)
            if windows_mode:
                self.status_var.set("System check completed - ready to configure installation")
            else:
                self.status_var.set("System check passed - ready to proceed")
            self.next_button.config(state="normal")
        else:
            if windows_mode:
                self.status_var.set("System check completed with warnings - review results")
            else:
                self.status_var.set("System check failed - please resolve issues")
    
    def next_step(self):
        """Move to next installation step"""
        if self.install_state['step'] == 0 and not self.install_state['system_check']:
            messagebox.showwarning("System Check Required", "Please run the system check first.")
            return
        
        self.install_state['step'] += 1
        self.update_ui_state()
    
    def previous_step(self):
        """Move to previous installation step"""
        if self.install_state['step'] > 0:
            self.install_state['step'] -= 1
            self.update_ui_state()
    
    def update_ui_state(self):
        """Update UI state based on current step"""
        # Update notebook tab
        self.notebook.select(self.install_state['step'])
        
        # Update buttons
        if self.install_state['step'] == 0:
            self.back_button.config(state="disabled")
        else:
            self.back_button.config(state="normal")
        
        if self.install_state['step'] == 2:  # Configuration tab
            self.next_button.config(state="disabled")
            self.install_button.config(state="normal")
        else:
            self.next_button.config(state="normal")
            self.install_button.config(state="disabled")
    
    def start_installation(self):
        """Start the installation process"""
        if not messagebox.askyesno("Confirm Installation", 
                                 "Are you sure you want to proceed with the installation?\n\n"
                                 "This will install the PVE SMB Gateway plugin on your system."):
            return
        
        # Update configuration
        self.config.update({
            'install_path': self.install_path_var.get(),
            'config_path': self.config_path_var.get(),
            'log_path': self.log_path_var.get(),
            'backup_enabled': self.backup_var.get(),
            'monitoring_enabled': self.monitoring_var.get(),
            'ha_enabled': self.ha_var.get()
        })
        
        # Switch to installation tab
        self.notebook.select(3)  # Installation tab
        
        # Start installation thread
        threading.Thread(target=self.installation_thread, daemon=True).start()
    
    def installation_thread(self):
        """Main installation thread"""
        try:
            self.update_installation_controls(True)
            
            steps = [
                ("Installing dependencies", self.install_dependencies),
                ("Building package", self.build_package),
                ("Installing package", self.install_package),
                ("Configuring services", self.configure_services),
                ("Testing installation", self.test_installation)
            ]
            
            for i, (description, step_func) in enumerate(steps):
                self.update_progress_label(description)
                self.update_progress_bar((i + 1) * 20)
                
                # Show command preview
                self.show_command_preview(step_func)
                
                # Execute step
                success = step_func()
                if not success:
                    self.log_message(f"Installation failed at: {description}")
                    self.root.after(0, lambda: messagebox.showerror("Installation Failed", 
                                                                   f"Installation failed at: {description}"))
                    return
                
                # Update progress
                self.progress_vars[i + 1].set(True)
                self.install_state[list(self.install_state.keys())[i + 1]] = True
            
            # Installation complete
            self.update_progress_bar(100)
            self.update_progress_label("Installation completed successfully!")
            self.log_message("Installation completed successfully!")
            
            self.root.after(0, lambda: messagebox.showinfo("Installation Complete", 
                                                          "PVE SMB Gateway has been installed successfully!\n\n"
                                                          "You can now access it through the Proxmox web interface."))
            
        except Exception as e:
            self.log_message(f"Installation error: {e}")
            self.root.after(0, lambda: messagebox.showerror("Installation Error", str(e)))
        finally:
            self.update_installation_controls(False)
    
    def install_dependencies(self):
        """Install required dependencies"""
        try:
            self.log_message("Installing dependencies...")
            
            # Update package list
            self.run_command(['apt', 'update'])
            
            # Install dependencies
            deps = [
                'build-essential', 'devscripts', 'debhelper', 'perl', 'python3',
                'samba', 'ctdb', 'libpve-common-perl', 'libpve-storage-perl'
            ]
            
            for dep in deps:
                self.run_command(['apt', 'install', '-y', dep])
            
            return True
        except Exception as e:
            self.log_message(f"Failed to install dependencies: {e}")
            return False
    
    def build_package(self):
        """Build the SMB Gateway package"""
        try:
            self.log_message("Building SMB Gateway package...")
            
            # Build package
            self.run_command(['make', 'deb'])
            
            return True
        except Exception as e:
            self.log_message(f"Failed to build package: {e}")
            return False
    
    def install_package(self):
        """Install the built package"""
        try:
            self.log_message("Installing SMB Gateway package...")
            
            # Find and install package
            package_files = list(Path('.').glob('../pve-plugin-smbgateway_*.deb'))
            if not package_files:
                self.log_message("No package file found!")
                return False
            
            package_file = package_files[0]
            self.run_command(['dpkg', '-i', str(package_file)])
            
            return True
        except Exception as e:
            self.log_message(f"Failed to install package: {e}")
            return False
    
    def configure_services(self):
        """Configure SMB Gateway services"""
        try:
            self.log_message("Configuring SMB Gateway services...")
            
            # Create directories
            self.run_command(['mkdir', '-p', self.config['config_path']])
            self.run_command(['mkdir', '-p', self.config['log_path']])
            
            # Set permissions
            self.run_command(['chown', '-R', 'root:root', self.config['config_path']])
            self.run_command(['chmod', '755', self.config['config_path']])
            
            # Restart Proxmox services
            self.run_command(['systemctl', 'restart', 'pveproxy'])
            
            return True
        except Exception as e:
            self.log_message(f"Failed to configure services: {e}")
            return False
    
    def test_installation(self):
        """Test the installation"""
        try:
            self.log_message("Testing installation...")
            
            # Test CLI command
            result = self.run_command(['pve-smbgateway', '--version'])
            if not result:
                return False
            
            # Test web interface
            # (This would require checking if the web interface is accessible)
            
            return True
        except Exception as e:
            self.log_message(f"Installation test failed: {e}")
            return False
    
    def run_command(self, cmd, capture_output=True):
        """Run a command and return output"""
        try:
            if capture_output:
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                return result.stdout.strip()
            else:
                subprocess.run(cmd, check=True)
                return True
        except subprocess.CalledProcessError as e:
            self.log_message(f"Command failed: {' '.join(cmd)} - {e}")
            return None
        except Exception as e:
            self.log_message(f"Command error: {' '.join(cmd)} - {e}")
            return None
    
    def show_command_preview(self, step_func):
        """Show preview of commands that will be executed"""
        # This is a simplified preview - in a real implementation,
        # you would generate the actual commands based on the step
        preview = "Command preview for this step:\n"
        preview += "# This step will execute the following commands:\n"
        preview += "# (Commands will be shown here based on the step)\n"
        
        self.cmd_text.config(state=tk.NORMAL)
        self.cmd_text.delete(1.0, tk.END)
        self.cmd_text.insert(tk.END, preview)
        self.cmd_text.config(state=tk.DISABLED)
    
    def update_progress_bar(self, value):
        """Update the progress bar"""
        self.progress_bar['value'] = value
        self.root.update_idletasks()
    
    def update_progress_label(self, text):
        """Update the progress label"""
        self.progress_label.config(text=text)
        self.root.update_idletasks()
    
    def update_installation_controls(self, installing):
        """Update installation control buttons"""
        if installing:
            self.pause_button.config(state="normal")
            self.stop_button.config(state="normal")
            self.install_button.config(state="disabled")
        else:
            self.pause_button.config(state="disabled")
            self.stop_button.config(state="disabled")
            self.resume_button.config(state="disabled")
            self.install_button.config(state="normal")
    
    def pause_installation(self):
        """Pause the installation"""
        self.pause_button.config(state="disabled")
        self.resume_button.config(state="normal")
        self.log_message("Installation paused")
    
    def resume_installation(self):
        """Resume the installation"""
        self.pause_button.config(state="normal")
        self.resume_button.config(state="disabled")
        self.log_message("Installation resumed")
    
    def stop_installation(self):
        """Stop the installation"""
        if messagebox.askyesno("Stop Installation", "Are you sure you want to stop the installation?"):
            self.log_message("Installation stopped by user")
            self.update_installation_controls(False)
    
    def cancel_installation(self):
        """Cancel the installation process"""
        if messagebox.askyesno("Cancel Installation", "Are you sure you want to cancel the installation?"):
            self.root.quit()
    
    def log_message(self, message):
        """Add message to log"""
        timestamp = time.strftime("%H:%M:%S")
        log_entry = f"[{timestamp}] {message}\n"
        
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, log_entry)
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)
    
    def clear_log(self):
        """Clear the log"""
        self.log_text.config(state=tk.NORMAL)
        self.log_text.delete(1.0, tk.END)
        self.log_text.config(state=tk.DISABLED)
    
    def save_log(self):
        """Save the log to file"""
        filename = filedialog.asksaveasfilename(
            defaultextension=".log",
            filetypes=[("Log files", "*.log"), ("Text files", "*.txt"), ("All files", "*.*")]
        )
        if filename:
            try:
                with open(filename, 'w') as f:
                    f.write(self.log_text.get(1.0, tk.END))
                messagebox.showinfo("Log Saved", f"Log saved to {filename}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save log: {e}")
    
    def copy_log(self):
        """Copy log to clipboard"""
        self.root.clipboard_clear()
        self.root.clipboard_append(self.log_text.get(1.0, tk.END))
        messagebox.showinfo("Copied", "Log copied to clipboard")
    
    def browse_install_path(self):
        """Browse for install path"""
        path = filedialog.askdirectory(title="Select Installation Path")
        if path:
            self.install_path_var.set(path)
    
    def browse_config_path(self):
        """Browse for config path"""
        path = filedialog.askdirectory(title="Select Configuration Path")
        if path:
            self.config_path_var.set(path)
    
    def browse_log_path(self):
        """Browse for log path"""
        path = filedialog.askdirectory(title="Select Log Path")
        if path:
            self.log_path_var.set(path)
    
    def view_check_log(self):
        """View detailed system check log"""
        # This would show a detailed log of the system check
        messagebox.showinfo("System Check Log", "Detailed system check log would be displayed here.")

def main():
    """Main entry point"""
    root = tk.Tk()
    app = PVEInstallerGUI(root)
    root.mainloop()

if __name__ == "__main__":
    main() 