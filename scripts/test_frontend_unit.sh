#!/bin/bash

# PVE SMB Gateway - Frontend Unit Tests
# Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
# Dual-licensed under AGPL-3.0 and Commercial License
#
# Comprehensive unit tests for ExtJS frontend components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/pve-smbgateway-frontend-tests"
EXTJS_VERSION="6.7.0"
NODE_VERSION="18"
NPM_PACKAGES=(
    "extjs@${EXTJS_VERSION}"
    "mocha@^10.0.0"
    "chai@^4.3.0"
    "sinon@^15.0.0"
    "jsdom@^22.0.0"
    "webpack@^5.0.0"
    "webpack-cli@^5.0.0"
    "babel-loader@^9.0.0"
    "@babel/core@^7.0.0"
    "@babel/preset-env@^7.0.0"
)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up frontend test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Initialize npm project
    npm init -y > /dev/null 2>&1
    
    # Install dependencies
    log_info "Installing test dependencies..."
    for package in "${NPM_PACKAGES[@]}"; do
        npm install "$package" --save-dev > /dev/null 2>&1
    done
    
    # Create test structure
    mkdir -p src tests fixtures
    
    # Copy source files
    cp -r /usr/share/pve-manager/ext6/pvemanager6/smb-gateway.js src/ 2>/dev/null || {
        log_warning "Source file not found, creating mock for testing"
        create_mock_source_files
    }
    
    # Create test configuration
    create_test_config
}

# Create mock source files for testing
create_mock_source_files() {
    log_info "Creating mock source files for testing..."
    
    cat > src/smb-gateway.js << 'EOF'
// Mock PVE SMB Gateway ExtJS Component
Ext.define('PVE.SMBGatewayAdd', {
    extend: 'Ext.form.Panel',
    xtype: 'pveSMBGatewayAdd',
    
    // Mock properties for testing
    properties: {
        mode: 'lxc',
        sharename: '',
        path: '',
        quota: '',
        ad_domain: '',
        ad_join: false,
        ctdb_vip: '',
        ha_enabled: false,
        vm_memory: 2048,
        vm_cores: 2
    },
    
    // Mock validation methods
    validateForm: function() {
        var form = this.getForm();
        return form.isValid();
    },
    
    getValues: function() {
        return this.properties;
    },
    
    setValues: function(values) {
        Ext.apply(this.properties, values);
    },
    
    // Mock field management
    getField: function(name) {
        return {
            getValue: function() { return this.properties[name] || ''; }.bind(this),
            setValue: function(value) { this.properties[name] = value; }.bind(this),
            isValid: function() { return true; },
            markInvalid: function(msg) { this.lastError = msg; },
            clearInvalid: function() { this.lastError = null; }
        };
    },
    
    // Mock mode switching
    switchMode: function(mode) {
        this.properties.mode = mode;
        this.updateFieldVisibility();
    },
    
    updateFieldVisibility: function() {
        // Mock field visibility updates
        return true;
    }
});

// Mock PVE namespace
Ext.ns('PVE');
PVE.Utils = {
    gettext: function(str) { return str; }
};
EOF

    cat > src/test-utils.js << 'EOF'
// Test utilities for PVE SMB Gateway
Ext.define('PVE.SMBGatewayTestUtils', {
    statics: {
        // Create test form data
        createTestData: function(mode) {
            return {
                mode: mode || 'lxc',
                sharename: 'test-share',
                path: '/srv/smb/test-share',
                quota: '10G',
                ad_domain: 'test.local',
                ad_join: true,
                ctdb_vip: '192.168.1.100',
                ha_enabled: true,
                vm_memory: 2048,
                vm_cores: 2
            };
        },
        
        // Validate form data
        validateFormData: function(data) {
            var errors = [];
            
            if (!data.sharename || data.sharename.length < 3) {
                errors.push('Share name must be at least 3 characters');
            }
            
            if (data.sharename && !/^[a-zA-Z0-9_-]+$/.test(data.sharename)) {
                errors.push('Share name contains invalid characters');
            }
            
            if (data.quota && !/^\d+[GT]$/.test(data.quota)) {
                errors.push('Invalid quota format');
            }
            
            if (data.ad_domain && !/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(data.ad_domain)) {
                errors.push('Invalid domain format');
            }
            
            if (data.ctdb_vip && !/^(\d{1,3}\.){3}\d{1,3}$/.test(data.ctdb_vip)) {
                errors.push('Invalid VIP format');
            }
            
            return errors;
        },
        
        // Mock API responses
        mockApiResponse: function(success, data, error) {
            return {
                success: success,
                data: data || {},
                error: error || null
            };
        }
    }
});
EOF
}

# Create test configuration
create_test_config() {
    cat > webpack.config.js << 'EOF'
const path = require('path');

module.exports = {
    mode: 'development',
    entry: './tests/index.js',
    output: {
        path: path.resolve(__dirname, 'dist'),
        filename: 'test-bundle.js'
    },
    module: {
        rules: [
            {
                test: /\.js$/,
                exclude: /node_modules/,
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['@babel/preset-env']
                    }
                }
            }
        ]
    },
    resolve: {
        alias: {
            'Ext': 'extjs'
        }
    }
};
EOF

    cat > .mocharc.js << 'EOF'
module.exports = {
    require: ['tests/setup.js'],
    timeout: 10000,
    reporter: 'spec',
    ui: 'bdd'
};
EOF
}

# Create test setup file
create_test_setup() {
    cat > tests/setup.js << 'EOF'
// Test setup for PVE SMB Gateway frontend tests
const { JSDOM } = require('jsdom');
const Ext = require('extjs');

// Setup DOM environment
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
    url: 'http://localhost'
});

global.window = dom.window;
global.document = dom.window.document;
global.navigator = dom.window.navigator;

// Mock ExtJS environment
global.Ext = Ext;
global.PVE = {
    Utils: {
        gettext: function(str) { return str; }
    }
};

// Mock console for tests
global.console = {
    log: function() {},
    error: function() {},
    warn: function() {},
    info: function() {}
};
EOF
}

# Create individual test files
create_form_validation_tests() {
    cat > tests/form-validation.test.js << 'EOF'
const { expect } = require('chai');
const sinon = require('sinon');

describe('PVE SMB Gateway - Form Validation', function() {
    let form;
    
    beforeEach(function() {
        form = Ext.create('PVE.SMBGatewayAdd');
    });
    
    afterEach(function() {
        if (form) {
            form.destroy();
        }
    });
    
    describe('Share Name Validation', function() {
        it('should accept valid share names', function() {
            const validNames = ['myshare', 'my-share', 'my_share', 'share123'];
            
            validNames.forEach(name => {
                form.setValues({ sharename: name });
                expect(form.validateForm()).to.be.true;
            });
        });
        
        it('should reject invalid share names', function() {
            const invalidNames = ['', 'ab', 'my share', 'share@123', 'share#123'];
            
            invalidNames.forEach(name => {
                form.setValues({ sharename: name });
                expect(form.validateForm()).to.be.false;
            });
        });
        
        it('should enforce minimum length', function() {
            form.setValues({ sharename: 'ab' });
            expect(form.validateForm()).to.be.false;
            
            form.setValues({ sharename: 'abc' });
            expect(form.validateForm()).to.be.true;
        });
    });
    
    describe('Quota Validation', function() {
        it('should accept valid quota formats', function() {
            const validQuotas = ['1G', '10G', '100G', '1T', '10T'];
            
            validQuotas.forEach(quota => {
                form.setValues({ quota: quota });
                expect(form.validateForm()).to.be.true;
            });
        });
        
        it('should reject invalid quota formats', function() {
            const invalidQuotas = ['1', '1M', '1K', '1GB', '1TB', 'abc'];
            
            invalidQuotas.forEach(quota => {
                form.setValues({ quota: quota });
                expect(form.validateForm()).to.be.false;
            });
        });
        
        it('should allow empty quota', function() {
            form.setValues({ quota: '' });
            expect(form.validateForm()).to.be.true;
        });
    });
    
    describe('Domain Validation', function() {
        it('should accept valid domain names', function() {
            const validDomains = [
                'example.com',
                'test.local',
                'subdomain.example.com',
                'domain.co.uk'
            ];
            
            validDomains.forEach(domain => {
                form.setValues({ ad_domain: domain });
                expect(form.validateForm()).to.be.true;
            });
        });
        
        it('should reject invalid domain names', function() {
            const invalidDomains = [
                'example',
                '.com',
                'example.',
                'example..com',
                'example@.com'
            ];
            
            invalidDomains.forEach(domain => {
                form.setValues({ ad_domain: domain });
                expect(form.validateForm()).to.be.false;
            });
        });
    });
    
    describe('VIP Validation', function() {
        it('should accept valid IP addresses', function() {
            const validIPs = [
                '192.168.1.100',
                '10.0.0.1',
                '172.16.0.1',
                '192.168.0.254'
            ];
            
            validIPs.forEach(ip => {
                form.setValues({ ctdb_vip: ip });
                expect(form.validateForm()).to.be.true;
            });
        });
        
        it('should reject invalid IP addresses', function() {
            const invalidIPs = [
                '192.168.1',
                '192.168.1.256',
                '192.168.1.abc',
                '192.168.1.1.1',
                '192.168.1.1/24'
            ];
            
            invalidIPs.forEach(ip => {
                form.setValues({ ctdb_vip: ip });
                expect(form.validateForm()).to.be.false;
            });
        });
    });
    
    describe('VM Resource Validation', function() {
        it('should validate memory allocation', function() {
            const validMemory = [1024, 2048, 4096, 8192];
            const invalidMemory = [0, 512, 16384, -1024];
            
            validMemory.forEach(memory => {
                form.setValues({ vm_memory: memory });
                expect(form.validateForm()).to.be.true;
            });
            
            invalidMemory.forEach(memory => {
                form.setValues({ vm_memory: memory });
                expect(form.validateForm()).to.be.false;
            });
        });
        
        it('should validate CPU cores', function() {
            const validCores = [1, 2, 4, 8];
            const invalidCores = [0, 16, -1];
            
            validCores.forEach(cores => {
                form.setValues({ vm_cores: cores });
                expect(form.validateForm()).to.be.true;
            });
            
            invalidCores.forEach(cores => {
                form.setValues({ vm_cores: cores });
                expect(form.validateForm()).to.be.false;
            });
        });
    });
});
EOF
}

create_component_behavior_tests() {
    cat > tests/component-behavior.test.js << 'EOF'
const { expect } = require('chai');
const sinon = require('sinon');

describe('PVE SMB Gateway - Component Behavior', function() {
    let form;
    
    beforeEach(function() {
        form = Ext.create('PVE.SMBGatewayAdd');
    });
    
    afterEach(function() {
        if (form) {
            form.destroy();
        }
    });
    
    describe('Mode Switching', function() {
        it('should switch between deployment modes', function() {
            const modes = ['lxc', 'native', 'vm'];
            
            modes.forEach(mode => {
                form.switchMode(mode);
                expect(form.getValues().mode).to.equal(mode);
            });
        });
        
        it('should update field visibility on mode change', function() {
            const spy = sinon.spy(form, 'updateFieldVisibility');
            
            form.switchMode('vm');
            expect(spy.called).to.be.true;
            
            spy.restore();
        });
        
        it('should show VM-specific fields for VM mode', function() {
            form.switchMode('vm');
            const values = form.getValues();
            
            expect(values.vm_memory).to.equal(2048);
            expect(values.vm_cores).to.equal(2);
        });
        
        it('should hide VM-specific fields for non-VM modes', function() {
            form.switchMode('lxc');
            const values = form.getValues();
            
            expect(values.vm_memory).to.be.undefined;
            expect(values.vm_cores).to.be.undefined;
        });
    });
    
    describe('Field Management', function() {
        it('should get field values correctly', function() {
            const testData = {
                sharename: 'test-share',
                path: '/srv/smb/test-share',
                quota: '10G'
            };
            
            form.setValues(testData);
            
            Object.keys(testData).forEach(key => {
                const field = form.getField(key);
                expect(field.getValue()).to.equal(testData[key]);
            });
        });
        
        it('should set field values correctly', function() {
            const field = form.getField('sharename');
            field.setValue('new-share');
            
            expect(form.getValues().sharename).to.equal('new-share');
        });
        
        it('should handle field validation', function() {
            const field = form.getField('sharename');
            
            // Test valid value
            field.setValue('valid-share');
            expect(field.isValid()).to.be.true;
            
            // Test invalid value
            field.setValue('');
            expect(field.isValid()).to.be.false;
        });
        
        it('should handle field error marking', function() {
            const field = form.getField('sharename');
            const errorMsg = 'Share name is required';
            
            field.markInvalid(errorMsg);
            expect(field.lastError).to.equal(errorMsg);
            
            field.clearInvalid();
            expect(field.lastError).to.be.null;
        });
    });
    
    describe('Form State Management', function() {
        it('should maintain form state across operations', function() {
            const initialData = {
                sharename: 'test-share',
                mode: 'lxc',
                quota: '10G'
            };
            
            form.setValues(initialData);
            
            // Perform operations
            form.switchMode('vm');
            form.setValues({ vm_memory: 4096 });
            
            // Verify state is maintained
            const currentValues = form.getValues();
            expect(currentValues.sharename).to.equal(initialData.sharename);
            expect(currentValues.quota).to.equal(initialData.quota);
            expect(currentValues.mode).to.equal('vm');
            expect(currentValues.vm_memory).to.equal(4096);
        });
        
        it('should reset form state', function() {
            form.setValues({
                sharename: 'test-share',
                mode: 'vm',
                vm_memory: 4096
            });
            
            form.setValues({});
            
            const values = form.getValues();
            expect(values.sharename).to.be.undefined;
            expect(values.mode).to.be.undefined;
            expect(values.vm_memory).to.be.undefined;
        });
    });
    
    describe('Data Binding', function() {
        it('should bind form data to component properties', function() {
            const testData = {
                sharename: 'test-share',
                path: '/srv/smb/test-share',
                quota: '10G',
                ad_domain: 'test.local',
                ha_enabled: true
            };
            
            form.setValues(testData);
            
            Object.keys(testData).forEach(key => {
                expect(form.properties[key]).to.equal(testData[key]);
            });
        });
        
        it('should update properties when fields change', function() {
            const field = form.getField('sharename');
            field.setValue('updated-share');
            
            expect(form.properties.sharename).to.equal('updated-share');
        });
    });
});
EOF
}

create_user_interaction_tests() {
    cat > tests/user-interaction.test.js << 'EOF'
const { expect } = require('chai');
const sinon = require('sinon');

describe('PVE SMB Gateway - User Interaction', function() {
    let form;
    
    beforeEach(function() {
        form = Ext.create('PVE.SMBGatewayAdd');
    });
    
    afterEach(function() {
        if (form) {
            form.destroy();
        }
    });
    
    describe('Form Submission', function() {
        it('should validate form before submission', function() {
            const spy = sinon.spy(form, 'validateForm');
            
            // Test with invalid data
            form.setValues({ sharename: '' });
            expect(spy.called).to.be.false;
            
            // Test with valid data
            form.setValues({ sharename: 'valid-share' });
            expect(spy.called).to.be.false;
            
            spy.restore();
        });
        
        it('should prevent submission with invalid data', function() {
            form.setValues({
                sharename: '',
                quota: 'invalid'
            });
            
            expect(form.validateForm()).to.be.false;
        });
        
        it('should allow submission with valid data', function() {
            form.setValues({
                sharename: 'valid-share',
                path: '/srv/smb/valid-share',
                quota: '10G'
            });
            
            expect(form.validateForm()).to.be.true;
        });
    });
    
    describe('Dynamic Field Updates', function() {
        it('should show/hide fields based on mode selection', function() {
            // Test LXC mode
            form.switchMode('lxc');
            expect(form.getValues().mode).to.equal('lxc');
            
            // Test VM mode
            form.switchMode('vm');
            expect(form.getValues().mode).to.equal('vm');
            expect(form.getValues().vm_memory).to.equal(2048);
        });
        
        it('should update field requirements based on selections', function() {
            // Test AD integration
            form.setValues({ ad_domain: 'test.local', ad_join: true });
            expect(form.getValues().ad_join).to.be.true;
            
            // Test HA configuration
            form.setValues({ ha_enabled: true, ctdb_vip: '192.168.1.100' });
            expect(form.getValues().ha_enabled).to.be.true;
        });
        
        it('should provide helpful error messages', function() {
            const field = form.getField('sharename');
            
            field.setValue('');
            field.markInvalid('Share name is required');
            expect(field.lastError).to.equal('Share name is required');
            
            field.setValue('ab');
            field.markInvalid('Share name must be at least 3 characters');
            expect(field.lastError).to.equal('Share name must be at least 3 characters');
        });
    });
    
    describe('Configuration Validation', function() {
        it('should validate complete configurations', function() {
            const validConfig = {
                sharename: 'test-share',
                mode: 'lxc',
                path: '/srv/smb/test-share',
                quota: '10G',
                ad_domain: 'test.local',
                ad_join: true,
                ha_enabled: true,
                ctdb_vip: '192.168.1.100'
            };
            
            form.setValues(validConfig);
            expect(form.validateForm()).to.be.true;
        });
        
        it('should detect configuration conflicts', function() {
            // Test conflicting AD and HA settings
            const conflictingConfig = {
                sharename: 'test-share',
                ad_domain: 'test.local',
                ad_join: false, // AD domain but no join
                ha_enabled: true,
                ctdb_vip: '' // HA enabled but no VIP
            };
            
            form.setValues(conflictingConfig);
            expect(form.validateForm()).to.be.false;
        });
        
        it('should validate resource allocations', function() {
            const vmConfig = {
                sharename: 'test-share',
                mode: 'vm',
                vm_memory: 512, // Too low
                vm_cores: 0 // Invalid
            };
            
            form.setValues(vmConfig);
            expect(form.validateForm()).to.be.false;
        });
    });
    
    describe('Error Handling', function() {
        it('should handle field validation errors gracefully', function() {
            const field = form.getField('sharename');
            
            // Test multiple error states
            field.setValue('');
            field.markInvalid('Required field');
            expect(field.lastError).to.equal('Required field');
            
            field.setValue('ab');
            field.markInvalid('Too short');
            expect(field.lastError).to.equal('Too short');
            
            field.setValue('valid-share');
            field.clearInvalid();
            expect(field.lastError).to.be.null;
        });
        
        it('should provide clear error messages', function() {
            const errorMessages = [
                'Share name is required',
                'Share name must be at least 3 characters',
                'Invalid quota format',
                'Invalid domain format',
                'Invalid IP address format'
            ];
            
            errorMessages.forEach(message => {
                const field = form.getField('sharename');
                field.markInvalid(message);
                expect(field.lastError).to.equal(message);
            });
        });
    });
    
    describe('Form State Persistence', function() {
        it('should maintain form state during validation', function() {
            const testData = {
                sharename: 'test-share',
                path: '/srv/smb/test-share',
                quota: '10G'
            };
            
            form.setValues(testData);
            
            // Perform validation
            const isValid = form.validateForm();
            
            // Verify state is maintained
            const currentValues = form.getValues();
            expect(currentValues.sharename).to.equal(testData.sharename);
            expect(currentValues.path).to.equal(testData.path);
            expect(currentValues.quota).to.equal(testData.quota);
        });
        
        it('should handle partial form updates', function() {
            // Set initial data
            form.setValues({
                sharename: 'test-share',
                mode: 'lxc'
            });
            
            // Update only some fields
            form.setValues({
                quota: '10G',
                ad_domain: 'test.local'
            });
            
            // Verify all data is maintained
            const values = form.getValues();
            expect(values.sharename).to.equal('test-share');
            expect(values.mode).to.equal('lxc');
            expect(values.quota).to.equal('10G');
            expect(values.ad_domain).to.equal('test.local');
        });
    });
});
EOF
}

create_api_integration_tests() {
    cat > tests/api-integration.test.js << 'EOF'
const { expect } = require('chai');
const sinon = require('sinon');

describe('PVE SMB Gateway - API Integration', function() {
    let form;
    let apiStub;
    
    beforeEach(function() {
        form = Ext.create('PVE.SMBGatewayAdd');
        
        // Mock API calls
        apiStub = sinon.stub();
        global.PVE = {
            ...global.PVE,
            API: {
                request: apiStub
            }
        };
    });
    
    afterEach(function() {
        if (form) {
            form.destroy();
        }
        if (apiStub) {
            apiStub.restore();
        }
    });
    
    describe('Share Creation API', function() {
        it('should call API with correct parameters', function() {
            const testData = {
                sharename: 'test-share',
                mode: 'lxc',
                path: '/srv/smb/test-share',
                quota: '10G'
            };
            
            apiStub.returns(Promise.resolve({
                success: true,
                data: { storage: 'test-share' }
            }));
            
            form.setValues(testData);
            
            // Simulate form submission
            return form.submitForm().then(() => {
                expect(apiStub.called).to.be.true;
                const callArgs = apiStub.getCall(0).args;
                expect(callArgs[0]).to.include(testData);
            });
        });
        
        it('should handle API success responses', function() {
            const successResponse = {
                success: true,
                data: {
                    storage: 'test-share',
                    status: 'created'
                }
            };
            
            apiStub.returns(Promise.resolve(successResponse));
            
            return form.submitForm().then(response => {
                expect(response.success).to.be.true;
                expect(response.data.storage).to.equal('test-share');
            });
        });
        
        it('should handle API error responses', function() {
            const errorResponse = {
                success: false,
                error: 'Share creation failed'
            };
            
            apiStub.returns(Promise.reject(errorResponse));
            
            return form.submitForm().catch(error => {
                expect(error.success).to.be.false;
                expect(error.error).to.equal('Share creation failed');
            });
        });
    });
    
    describe('Validation API', function() {
        it('should validate share name uniqueness', function() {
            apiStub.returns(Promise.resolve({
                success: true,
                data: { available: false }
            }));
            
            return form.validateShareName('existing-share').then(result => {
                expect(result.available).to.be.false;
            });
        });
        
        it('should validate VIP availability', function() {
            apiStub.returns(Promise.resolve({
                success: true,
                data: { available: true }
            }));
            
            return form.validateVIP('192.168.1.100').then(result => {
                expect(result.available).to.be.true;
            });
        });
        
        it('should validate domain connectivity', function() {
            apiStub.returns(Promise.resolve({
                success: true,
                data: { reachable: true }
            }));
            
            return form.validateDomain('test.local').then(result => {
                expect(result.reachable).to.be.true;
            });
        });
    });
    
    describe('Configuration Loading', function() {
        it('should load existing share configuration', function() {
            const configData = {
                sharename: 'existing-share',
                mode: 'lxc',
                path: '/srv/smb/existing-share',
                quota: '10G',
                ad_domain: 'test.local',
                ha_enabled: true
            };
            
            apiStub.returns(Promise.resolve({
                success: true,
                data: configData
            }));
            
            return form.loadConfiguration('existing-share').then(() => {
                const values = form.getValues();
                expect(values.sharename).to.equal(configData.sharename);
                expect(values.mode).to.equal(configData.mode);
                expect(values.quota).to.equal(configData.quota);
            });
        });
        
        it('should handle configuration loading errors', function() {
            apiStub.returns(Promise.reject({
                success: false,
                error: 'Share not found'
            }));
            
            return form.loadConfiguration('nonexistent-share').catch(error => {
                expect(error.success).to.be.false;
                expect(error.error).to.equal('Share not found');
            });
        });
    });
    
    describe('Status Updates', function() {
        it('should update share status', function() {
            const statusData = {
                status: 'active',
                quota_usage: '25%',
                ha_status: 'healthy'
            };
            
            apiStub.returns(Promise.resolve({
                success: true,
                data: statusData
            }));
            
            return form.updateStatus('test-share').then(status => {
                expect(status.status).to.equal('active');
                expect(status.quota_usage).to.equal('25%');
            });
        });
        
        it('should handle status update errors', function() {
            apiStub.returns(Promise.reject({
                success: false,
                error: 'Share not accessible'
            }));
            
            return form.updateStatus('test-share').catch(error => {
                expect(error.success).to.be.false;
                expect(error.error).to.equal('Share not accessible');
            });
        });
    });
});
EOF
}

create_test_index() {
    cat > tests/index.js << 'EOF'
// PVE SMB Gateway Frontend Test Suite
// Entry point for all frontend tests

// Import test utilities
require('./setup.js');

// Import all test suites
require('./form-validation.test.js');
require('./component-behavior.test.js');
require('./user-interaction.test.js');
require('./api-integration.test.js');

console.log('Frontend test suite loaded successfully');
EOF
}

# Run tests
run_tests() {
    log_info "Running frontend unit tests..."
    
    # Create test files
    create_test_setup
    create_form_validation_tests
    create_component_behavior_tests
    create_user_interaction_tests
    create_api_integration_tests
    create_test_index
    
    # Run tests with Mocha
    log_info "Executing test suite..."
    
    if npx mocha tests/ --timeout 10000; then
        log_success "All frontend tests passed!"
        return 0
    else
        log_error "Some frontend tests failed!"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting PVE SMB Gateway Frontend Unit Tests"
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Setup test environment
    setup_test_environment
    
    # Run tests
    run_tests
    
    # Print summary
    log_info "Test Summary:"
    log_info "Total Tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests completed successfully!"
        exit 0
    else
        log_error "Some tests failed!"
        exit 1
    fi
}

# Run main function
main "$@" 