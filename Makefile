# Makefile for Proxmox SMB Gateway Plugin

.PHONY: help lint test deb clean install

# Default target
help:
	@echo "Available targets:"
	@echo "  lint    - Run linting checks (Perl & JavaScript)"
	@echo "  test    - Run unit tests"
	@echo "  deb     - Build .deb package"
	@echo "  clean   - Remove build artifacts"
	@echo "  install - Install the plugin (requires sudo)"

# Linting
lint: lint-perl lint-js

lint-perl:
	@echo "Linting Perl code..."
	@if command -v perltidy >/dev/null 2>&1; then \
		perltidy -q -i=4 PVE/Storage/Custom/SMBGateway.pm; \
	else \
		echo "Warning: perltidy not found, skipping Perl linting"; \
	fi
	@if command -v perlcritic >/dev/null 2>&1; then \
		perlcritic -1 PVE/Storage/Custom/SMBGateway.pm; \
	else \
		echo "Warning: perlcritic not found, skipping Perl critic"; \
	fi

lint-js:
	@echo "Linting JavaScript code..."
	@if command -v eslint >/dev/null 2>&1; then \
		eslint www/ext6/pvemanager6/smb-gateway.js; \
	else \
		echo "Warning: eslint not found, skipping JavaScript linting"; \
	fi

# Testing
test:
	@echo "Running unit tests..."
	@if command -v prove >/dev/null 2>&1; then \
		prove -v t/; \
	else \
		echo "Warning: prove not found, running tests manually"; \
		perl t/00-load.t; \
		perl t/10-create-share.t; \
	fi

# Package building
deb:
	@echo "Building .deb package..."
	@./scripts/build_package.sh

# Cleaning
clean:
	@echo "Cleaning build artifacts..."
	rm -f debian/*.deb
	rm -f debian/*.changes
	rm -f debian/*.buildinfo
	rm -f debian/*.dsc
	rm -f debian/*.tar.gz
	rm -f ../pve-plugin-smbgateway_*.deb
	rm -f ../pve-plugin-smbgateway_*.changes
	rm -f ../pve-plugin-smbgateway_*.buildinfo
	rm -f ../pve-plugin-smbgateway_*.dsc
	rm -f ../pve-plugin-smbgateway_*.tar.gz
	rm -rf debian/tmp
	rm -rf .build

# Installation
install: deb
	@echo "Installing plugin..."
	@if [ -f ../pve-plugin-smbgateway_*.deb ]; then \
		sudo dpkg -i ../pve-plugin-smbgateway_*.deb; \
		sudo systemctl restart pveproxy; \
		echo "Plugin installed successfully!"; \
	else \
		echo "Error: No .deb package found. Run 'make deb' first."; \
		exit 1; \
	fi

# Development helpers
dev-setup:
	@echo "Setting up development environment..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y build-essential devscripts perltidy perlcritic; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y gcc make rpm-build perl-Tidy perl-Perl-Critic; \
	else \
		echo "Warning: Unsupported package manager for automatic dependency installation"; \
	fi

# Quick test in a development environment
quick-test:
	@echo "Running quick smoke test..."
	@perl -c PVE/Storage/Custom/SMBGateway.pm
	@echo "Perl syntax check passed"
	@if [ -f t/00-load.t ]; then \
		perl t/00-load.t; \
		echo "Basic functionality test passed"; \
	else \
		echo "Warning: No tests found"; \
	fi 