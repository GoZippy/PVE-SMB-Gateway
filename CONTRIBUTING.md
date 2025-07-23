# Contributing to PVE SMB Gateway

Thank you for your interest in contributing to PVE SMB Gateway! This guide will help you get started with contributing to the project.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Setup](#development-setup)
3. [Coding Standards](#coding-standards)
4. [Testing](#testing)
5. [Documentation](#documentation)
6. [Pull Request Process](#pull-request-process)
7. [Issue Reporting](#issue-reporting)
8. [Community Guidelines](#community-guidelines)
9. [License Agreement](#license-agreement)

## Getting Started

### Prerequisites

- **Proxmox VE 8.x** environment for testing
- **Perl 5.36+** for backend development
- **Node.js 18+** for frontend development
- **Git** for version control
- **Basic knowledge** of SMB/CIFS protocols

### Quick Start

1. **Fork** the repository on GitHub
2. **Clone** your fork locally
3. **Set up** the development environment
4. **Make changes** and test them
5. **Submit** a pull request

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/pve-smb-gateway.git
cd pve-smb-gateway

# Set up development environment
./scripts/setup_dev_environment.sh

# Build and install
./scripts/build_package.sh
sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb
sudo systemctl restart pveproxy
```

## Development Setup

### Environment Setup

#### Automated Setup
```bash
# Run the automated setup script
./scripts/setup_dev_environment.sh
```

#### Manual Setup
```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y build-essential devscripts debhelper
sudo apt-get install -y perl-modules libpve-storage-perl
sudo apt-get install -y samba sqlite3 zfsutils-linux

# Install Perl modules
sudo cpanm Test::More Test::Exception Test::MockObject
sudo cpanm JSON::PP Time::HiRes File::Path

# Install Node.js dependencies (if working on frontend)
npm install
```

### Project Structure

```
pve-smb-gateway/
├── PVE/                          # Perl backend modules
│   ├── Storage/Custom/
│   │   └── SMBGateway.pm         # Main storage plugin
│   └── SMBGateway/
│       ├── Monitor.pm            # Performance monitoring
│       ├── Backup.pm             # Backup integration
│       ├── Security.pm           # Security features
│       └── CLI.pm                # Enhanced CLI
├── www/                          # Frontend files
│   └── ext6/pvemanager6/
│       └── smb-gateway.js        # ExtJS wizard
├── sbin/                         # CLI tools
│   ├── pve-smbgateway           # Basic CLI
│   └── pve-smbgateway-enhanced  # Enhanced CLI
├── scripts/                      # Build and test scripts
├── t/                           # Unit tests
├── docs/                        # Documentation
└── debian/                      # Package configuration
```

### Development Workflow

#### 1. Create Feature Branch
```bash
git checkout -b feature/your-feature-name
```

#### 2. Make Changes
- **Backend**: Edit Perl modules in `PVE/`
- **Frontend**: Edit JavaScript in `www/ext6/pvemanager6/`
- **CLI**: Edit CLI tools in `sbin/`
- **Tests**: Add tests in `t/`

#### 3. Test Changes
```bash
# Run unit tests
make test

# Run integration tests
./scripts/test_integration_comprehensive.sh

# Run specific test suites
./scripts/test_security.sh
./scripts/test_performance_benchmarks.sh
```

#### 4. Build and Install
```bash
# Build package
./scripts/build_package.sh

# Install for testing
sudo dpkg -i ../pve-plugin-smbgateway_*_all.deb
sudo systemctl restart pveproxy
```

#### 5. Manual Testing
- Test web interface functionality
- Test CLI commands
- Test all deployment modes
- Test error scenarios

## Coding Standards

### Perl Standards

#### Code Style
- **Indentation**: 4 spaces (no tabs)
- **Line Length**: 120 characters maximum
- **Naming**: `snake_case` for variables and functions
- **Comments**: Comprehensive inline documentation

#### Code Formatting
```bash
# Format Perl code
perltidy -q -i=4 PVE/Storage/Custom/SMBGateway.pm

# Check syntax
perl -c PVE/Storage/Custom/SMBGateway.pm
```

#### Example Perl Code
```perl
# Good example
sub create_share {
    my ($self, $share_name, $options) = @_;
    
    # Validate input parameters
    die "Share name is required" unless $share_name;
    
    # Create share with error handling
    eval {
        my $result = $self->_provision_share($share_name, $options);
        return $result;
    };
    
    if ($@) {
        $self->_log_error("Share creation failed: $@");
        die "Share creation failed: $@";
    }
}
```

### JavaScript Standards

#### Code Style
- **Indentation**: 2 spaces
- **Line Length**: 100 characters maximum
- **Naming**: `camelCase` for variables and functions
- **Comments**: JSDoc style documentation

#### Code Formatting
```bash
# Format JavaScript code
npm run lint
npm run format
```

#### Example JavaScript Code
```javascript
/**
 * Create a new SMB share
 * @param {Object} config - Share configuration
 * @returns {Promise} Promise that resolves when share is created
 */
Ext.define('PVE.SMBGateway.createShare', {
    createShare: function(config) {
        return new Promise((resolve, reject) => {
            // Validate configuration
            if (!config.name) {
                reject(new Error('Share name is required'));
                return;
            }
            
            // Create share
            this.callAPI('POST', '/nodes/' + config.node + '/storage', config)
                .then(resolve)
                .catch(reject);
        });
    }
});
```

### Documentation Standards

#### Code Comments
- **Function Documentation**: Purpose, parameters, return values
- **Complex Logic**: Explain business logic and algorithms
- **Error Handling**: Document error conditions and recovery
- **API Endpoints**: Document REST API endpoints

#### Example Documentation
```perl
=head2 create_share

Create a new SMB Gateway share with the specified configuration.

=over 4

=item B<share_name>

The unique identifier for the share (required).

=item B<options>

Hash reference containing share configuration options:
- mode: Deployment mode (lxc|native|vm)
- path: Storage path
- quota: Storage quota limit
- ad_domain: Active Directory domain
- ctdb_vip: CTDB VIP address

=back

=item B<Returns>

Hash reference containing:
- success: Boolean indicating success/failure
- share_id: The created share ID
- message: Success or error message

=item B<Throws>

Exception if share creation fails.

=cut
```

## Testing

### Test Structure

#### Unit Tests
- **Location**: `t/` directory
- **Naming**: `XX-description.t` (XX = test number)
- **Coverage**: All Perl modules and functions

#### Integration Tests
- **Location**: `scripts/` directory
- **Purpose**: End-to-end functionality testing
- **Coverage**: All deployment modes and features

### Running Tests

#### Unit Tests
```bash
# Run all unit tests
make test

# Run specific test file
perl t/10-basic.t

# Run tests with coverage
perl -MDevel::Cover t/10-basic.t
cover
```

#### Integration Tests
```bash
# Run comprehensive integration tests
./scripts/test_integration_comprehensive.sh

# Run specific test suites
./scripts/test_security.sh
./scripts/test_performance_benchmarks.sh
./scripts/test_enhanced_cli.sh
```

#### Performance Tests
```bash
# Run performance benchmarks
./scripts/test_performance_benchmarks.sh

# Run stress tests
./scripts/test_stress.sh
```

### Writing Tests

#### Unit Test Example
```perl
use strict;
use warnings;
use Test::More;
use Test::Exception;
use PVE::Storage::Custom::SMBGateway;

# Test share creation
subtest 'share_creation' => sub {
    my $plugin = PVE::Storage::Custom::SMBGateway->new();
    
    # Test valid share creation
    my $result = $plugin->create_share('testshare', {
        mode => 'lxc',
        path => '/tmp/test',
        quota => '1G'
    });
    
    is($result->{success}, 1, 'Share creation successful');
    is($result->{share_id}, 'testshare', 'Correct share ID returned');
    
    # Test invalid share name
    throws_ok {
        $plugin->create_share('', { mode => 'lxc' });
    } qr/Share name is required/, 'Empty share name rejected';
    
    done_testing();
};
```

#### Integration Test Example
```bash
#!/bin/bash
# Test LXC mode share creation

echo "Testing LXC mode share creation..."

# Create test share
pve-smbgateway create test-lxc \
  --mode lxc \
  --path /tmp/test-lxc \
  --quota 1G

# Verify share was created
if pve-smbgateway status test-lxc >/dev/null 2>&1; then
    echo "✅ LXC share creation successful"
else
    echo "❌ LXC share creation failed"
    exit 1
fi

# Clean up
pve-smbgateway delete test-lxc
```

## Documentation

### Documentation Types

#### User Documentation
- **README.md**: Project overview and quick start
- **docs/USER_GUIDE.md**: Comprehensive user guide
- **docs/INSTALLATION.md**: Installation instructions
- **docs/TROUBLESHOOTING.md**: Common issues and solutions

#### Developer Documentation
- **docs/DEV_GUIDE.md**: Development setup and guidelines
- **docs/ARCHITECTURE.md**: System architecture and design
- **docs/API.md**: REST API reference
- **docs/CONTRIBUTING.md**: This contribution guide

#### Technical Documentation
- **docs/IMPLEMENTATION_STATUS.md**: Feature implementation status
- **docs/ROADMAP.md**: Development roadmap
- **docs/PRD.md**: Product requirements document

### Writing Documentation

#### Documentation Standards
- **Clear Structure**: Use headers and sections
- **Code Examples**: Include working code examples
- **Screenshots**: Add screenshots for UI features
- **Cross-references**: Link to related documentation

#### Example Documentation
```markdown
# Feature Name

## Overview

Brief description of the feature and its purpose.

## Configuration

### Basic Configuration

```bash
# Example configuration
pve-smbgateway create myshare \
  --feature-enabled \
  --feature-option value
```

### Advanced Configuration

Detailed configuration options and examples.

## Usage

### Web Interface

1. Navigate to **Datacenter → Storage → Add → SMB Gateway**
2. Configure feature options
3. Click **Create**

### CLI Usage

```bash
# Enable feature
pve-smbgateway feature enable myshare

# Check feature status
pve-smbgateway feature status myshare
```

## Troubleshooting

Common issues and solutions.

## Related Documentation

- [User Guide](USER_GUIDE.md#feature-section)
- [API Documentation](API.md#feature-endpoints)
```

## Pull Request Process

### Before Submitting

1. **Test Thoroughly**: Run all tests and manual testing
2. **Update Documentation**: Update relevant documentation
3. **Check Code Style**: Ensure code follows standards
4. **Review Changes**: Self-review your changes

### Pull Request Guidelines

#### Title and Description
- **Clear Title**: Describe the change concisely
- **Detailed Description**: Explain what, why, and how
- **Related Issues**: Link to related issues
- **Testing**: Describe testing performed

#### Example Pull Request
```markdown
## Add Enhanced Quota Monitoring

### What
Adds real-time quota monitoring with trend analysis and alerts.

### Why
Users need better visibility into storage usage and predictive analytics.

### How
- Implement quota monitoring module
- Add trend analysis algorithms
- Create alerting system
- Update CLI and web interface

### Testing
- [x] Unit tests for quota monitoring
- [x] Integration tests for trend analysis
- [x] Manual testing of alerts
- [x] Performance testing

### Related Issues
Closes #123, Addresses #456
```

### Review Process

#### Code Review Checklist
- [ ] **Functionality**: Does the code work as intended?
- [ ] **Testing**: Are there adequate tests?
- [ ] **Documentation**: Is documentation updated?
- [ ] **Performance**: Are there performance implications?
- [ ] **Security**: Are there security considerations?
- [ ] **Standards**: Does code follow project standards?

#### Review Comments
- **Be Constructive**: Provide helpful feedback
- **Be Specific**: Point to specific lines or issues
- **Suggest Solutions**: Offer alternatives when possible
- **Ask Questions**: Clarify unclear code or decisions

## Issue Reporting

### Issue Types

#### Bug Reports
- **Clear Description**: What happened vs. what was expected
- **Steps to Reproduce**: Detailed reproduction steps
- **Environment**: Proxmox version, plugin version, etc.
- **Logs**: Relevant error logs and output

#### Feature Requests
- **Use Case**: Describe the problem being solved
- **Proposed Solution**: Suggest implementation approach
- **Priority**: Indicate importance and urgency
- **Alternatives**: Consider existing solutions

### Issue Template

```markdown
## Issue Type
- [ ] Bug report
- [ ] Feature request
- [ ] Documentation issue
- [ ] Performance issue

## Environment
- **Proxmox VE Version**: 8.2
- **Plugin Version**: 1.0.0
- **Deployment Mode**: LXC/Native/VM
- **Storage Backend**: ZFS/CephFS/RBD

## Description
Clear description of the issue or feature request.

## Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Logs
Relevant log output and error messages.

## Additional Information
Any other relevant information.
```

## Community Guidelines

### Communication

#### Be Respectful
- **Respect Others**: Treat all contributors with respect
- **Be Patient**: Allow time for responses and reviews
- **Be Helpful**: Offer assistance to other contributors
- **Be Professional**: Maintain professional communication

#### Communication Channels
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and community support
- **Proxmox Forum**: Community discussion and feedback
- **Email**: Direct support at eric@gozippy.com

### Contribution Areas

#### Code Contributions
- **Bug Fixes**: Fix reported issues
- **Feature Development**: Implement new features
- **Performance Improvements**: Optimize existing code
- **Security Enhancements**: Improve security features

#### Documentation Contributions
- **User Guides**: Improve user documentation
- **API Documentation**: Document REST API endpoints
- **Examples**: Add configuration examples
- **Translations**: Translate documentation

#### Testing Contributions
- **Test Coverage**: Add missing tests
- **Test Automation**: Improve test automation
- **Performance Testing**: Add performance benchmarks
- **Security Testing**: Add security test cases

#### Community Support
- **Issue Triage**: Help categorize and prioritize issues
- **Code Review**: Review pull requests
- **User Support**: Help users with questions
- **Documentation**: Improve documentation

## License Agreement

### Contributor License Agreement

By contributing to PVE SMB Gateway, you agree that your contributions will be dual-licensed under:

1. **AGPL-3.0**: GNU Affero General Public License v3.0
2. **Commercial License**: Commercial license for enterprise use

### Sign-off Process

#### DCO (Developer Certificate of Origin)
Include the following in your commit messages:
```
Signed-off-by: Your Name <your.email@example.com>
```

#### Example Commit
```bash
git commit -m "Add enhanced quota monitoring

- Implement real-time quota tracking
- Add trend analysis algorithms
- Create alerting system
- Update CLI and web interface

Closes #123

Signed-off-by: John Doe <john.doe@example.com>"
```

### License Terms

#### What You Grant
- **Copyright License**: Grant copyright license to your contributions
- **Patent License**: Grant patent license to your contributions
- **Dual Licensing**: Agree to dual licensing under AGPL-3.0 and Commercial License

#### What You Retain
- **Copyright**: You retain copyright to your contributions
- **Attribution**: You will be credited for your contributions
- **Use Rights**: You can use your contributions in other projects

### Commercial Licensing

#### Commercial Use
- **Enterprise Use**: Commercial license required for enterprise use
- **Redistribution**: Commercial license required for redistribution
- **OEM Bundling**: Commercial license required for product bundling

#### License Inquiries
For commercial licensing inquiries, contact: eric@gozippy.com

---

**Thank you for contributing to PVE SMB Gateway!** 🚀

Your contributions help make SMB storage management better for everyone in the Proxmox community. 