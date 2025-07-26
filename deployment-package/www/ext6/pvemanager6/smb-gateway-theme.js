/**
 * PVE SMB Gateway - Theme Management System
 * Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
 * Dual-licensed under AGPL-3.0 and Commercial License
 */

Ext.define('PVE.SMBGatewayThemeManager', {
    singleton: true,
    
    // Theme configuration
    config: {
        currentTheme: 'light',
        availableThemes: ['light', 'dark', 'auto'],
        transitionDuration: 300,
        enableAnimations: true,
        highContrast: false,
        reducedMotion: false
    },
    
    // Theme definitions
    themes: {
        light: {
            name: 'Light',
            icon: 'fa fa-sun-o',
            variables: {
                // Dashboard
                '--dashboard-bg': '#f5f5f5',
                '--sidebar-bg': '#ffffff',
                '--sidebar-header-bg': '#f8f9fa',
                '--sidebar-header-color': '#333333',
                
                // Panels
                '--panel-bg': '#ffffff',
                '--panel-border': '#e0e0e0',
                '--panel-shadow': '0 1px 3px rgba(0, 0, 0, 0.1)',
                
                // Metrics
                '--metric-panel-bg': '#ffffff',
                '--metric-header-bg': '#f8f9fa',
                '--metric-header-color': '#333333',
                '--metric-value-color': '#2c3e50',
                
                // Charts
                '--chart-panel-bg': '#ffffff',
                '--chart-bg': '#fafafa',
                '--chart-border': '#e0e0e0',
                
                // Alerts
                '--alerts-panel-bg': '#ffffff',
                '--alerts-sidebar-bg': '#ffffff',
                '--alert-bg': '#f8f9fa',
                '--alert-critical-bg': 'rgba(231, 76, 60, 0.1)',
                '--alert-warning-bg': 'rgba(243, 156, 18, 0.1)',
                '--alert-info-bg': 'rgba(52, 152, 219, 0.1)',
                
                // Logs
                '--logs-panel-bg': '#ffffff',
                '--log-bg': '#1e1e1e',
                '--log-text': '#d4d4d4',
                
                // Monitoring
                '--monitoring-panel-bg': '#ffffff',
                
                // General
                '--border-color': '#e0e0e0',
                '--text-primary': '#333333',
                '--text-secondary': '#666666',
                '--text-muted': '#6c757d',
                '--accent-color': '#667eea',
                '--accent-hover-color': '#5a6fd8',
                '--success-color': '#28a745',
                '--warning-color': '#ffc107',
                '--danger-color': '#dc3545',
                '--info-color': '#17a2b8'
            }
        },
        
        dark: {
            name: 'Dark',
            icon: 'fa fa-moon-o',
            variables: {
                // Dashboard
                '--dashboard-bg': '#1a1a1a',
                '--sidebar-bg': '#2d2d2d',
                '--sidebar-header-bg': '#3d3d3d',
                '--sidebar-header-color': '#ffffff',
                
                // Panels
                '--panel-bg': '#2d2d2d',
                '--panel-border': '#404040',
                '--panel-shadow': '0 1px 3px rgba(0, 0, 0, 0.3)',
                
                // Metrics
                '--metric-panel-bg': '#2d2d2d',
                '--metric-header-bg': '#3d3d3d',
                '--metric-header-color': '#ffffff',
                '--metric-value-color': '#ffffff',
                
                // Charts
                '--chart-panel-bg': '#2d2d2d',
                '--chart-bg': '#1a1a1a',
                '--chart-border': '#404040',
                
                // Alerts
                '--alerts-panel-bg': '#2d2d2d',
                '--alerts-sidebar-bg': '#2d2d2d',
                '--alert-bg': '#3d3d3d',
                '--alert-critical-bg': 'rgba(231, 76, 60, 0.2)',
                '--alert-warning-bg': 'rgba(243, 156, 18, 0.2)',
                '--alert-info-bg': 'rgba(52, 152, 219, 0.2)',
                
                // Logs
                '--logs-panel-bg': '#2d2d2d',
                '--log-bg': '#0d1117',
                '--log-text': '#c9d1d9',
                
                // Monitoring
                '--monitoring-panel-bg': '#2d2d2d',
                
                // General
                '--border-color': '#404040',
                '--text-primary': '#ffffff',
                '--text-secondary': '#cccccc',
                '--text-muted': '#888888',
                '--accent-color': '#667eea',
                '--accent-hover-color': '#5a6fd8',
                '--success-color': '#28a745',
                '--warning-color': '#ffc107',
                '--danger-color': '#dc3545',
                '--info-color': '#17a2b8'
            }
        }
    },
    
    init: function() {
        var me = this;
        
        // Initialize theme system
        me.initThemeSystem();
        
        // Set up event listeners
        me.setupEventListeners();
        
        // Apply initial theme
        me.applyTheme(me.getCurrentTheme());
    },
    
    // Initialize theme system
    initThemeSystem: function() {
        var me = this;
        
        // Check for saved theme preference
        var savedTheme = localStorage.getItem('smbgateway-theme');
        if (savedTheme && me.themes[savedTheme]) {
            me.setCurrentTheme(savedTheme);
        }
        
        // Check for system preference
        if (me.getCurrentTheme() === 'auto') {
            me.setCurrentTheme(me.detectSystemTheme());
        }
        
        // Check for accessibility preferences
        me.checkAccessibilityPreferences();
    },
    
    // Detect system theme preference
    detectSystemTheme: function() {
        if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            return 'dark';
        }
        return 'light';
    },
    
    // Check accessibility preferences
    checkAccessibilityPreferences: function() {
        var me = this;
        
        // Check for reduced motion preference
        if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
            me.setReducedMotion(true);
            me.setTransitionDuration(0);
        }
        
        // Check for high contrast preference
        if (window.matchMedia && window.matchMedia('(prefers-contrast: high)').matches) {
            me.setHighContrast(true);
        }
    },
    
    // Set up event listeners
    setupEventListeners: function() {
        var me = this;
        
        // Listen for system theme changes
        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
                if (me.getCurrentTheme() === 'auto') {
                    me.applyTheme(e.matches ? 'dark' : 'light');
                }
            });
        }
        
        // Listen for accessibility preference changes
        if (window.matchMedia) {
            window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', function(e) {
                me.setReducedMotion(e.matches);
                me.setTransitionDuration(e.matches ? 0 : 300);
            });
            
            window.matchMedia('(prefers-contrast: high)').addEventListener('change', function(e) {
                me.setHighContrast(e.matches);
                me.applyTheme(me.getCurrentTheme());
            });
        }
    },
    
    // Apply theme to the application
    applyTheme: function(themeName) {
        var me = this;
        
        if (!me.themes[themeName]) {
            console.error('Theme not found:', themeName);
            return;
        }
        
        var theme = me.themes[themeName];
        var root = document.documentElement;
        
        // Apply CSS variables with transition
        if (me.getEnableAnimations() && !me.getReducedMotion()) {
            root.style.transition = 'all ' + me.getTransitionDuration() + 'ms ease';
        }
        
        // Apply theme variables
        Object.keys(theme.variables).forEach(function(variable) {
            root.style.setProperty(variable, theme.variables[variable]);
        });
        
        // Apply theme class to body
        document.body.classList.remove('light-theme', 'dark-theme');
        document.body.classList.add(themeName + '-theme');
        
        // Update current theme
        me.setCurrentTheme(themeName);
        
        // Save preference
        localStorage.setItem('smbgateway-theme', themeName);
        
        // Fire theme change event
        me.fireThemeChangeEvent(themeName);
        
        // Remove transition after animation completes
        if (me.getEnableAnimations() && !me.getReducedMotion()) {
            setTimeout(function() {
                root.style.transition = '';
            }, me.getTransitionDuration());
        }
    },
    
    // Fire theme change event
    fireThemeChangeEvent: function(themeName) {
        var event = new CustomEvent('smbgateway-theme-change', {
            detail: {
                theme: themeName,
                timestamp: new Date().toISOString()
            }
        });
        document.dispatchEvent(event);
    },
    
    // Toggle between light and dark themes
    toggleTheme: function() {
        var me = this;
        var currentTheme = me.getCurrentTheme();
        var newTheme = currentTheme === 'light' ? 'dark' : 'light';
        me.applyTheme(newTheme);
    },
    
    // Set specific theme
    setTheme: function(themeName) {
        var me = this;
        me.applyTheme(themeName);
    },
    
    // Get current theme information
    getCurrentThemeInfo: function() {
        var me = this;
        var themeName = me.getCurrentTheme();
        return {
            name: themeName,
            displayName: me.themes[themeName] ? me.themes[themeName].name : themeName,
            icon: me.themes[themeName] ? me.themes[themeName].icon : 'fa fa-question',
            variables: me.themes[themeName] ? me.themes[themeName].variables : {}
        };
    },
    
    // Get available themes
    getAvailableThemes: function() {
        var me = this;
        return Object.keys(me.themes).map(function(themeName) {
            return {
                name: themeName,
                displayName: me.themes[themeName].name,
                icon: me.themes[themeName].icon
            };
        });
    },
    
    // Create theme selector component
    createThemeSelector: function() {
        var me = this;
        
        return {
            xtype: 'container',
            layout: 'hbox',
            margin: '10',
            items: [
                {
                    xtype: 'label',
                    text: gettext('Theme:'),
                    margin: '0 10 0 0'
                },
                {
                    xtype: 'combo',
                    itemId: 'theme-selector',
                    width: 150,
                    store: me.getAvailableThemes(),
                    valueField: 'name',
                    displayField: 'displayName',
                    value: me.getCurrentTheme(),
                    listeners: {
                        change: function(combo, newValue) {
                            me.setTheme(newValue);
                        }
                    }
                },
                {
                    xtype: 'button',
                    text: gettext('Toggle'),
                    margin: '0 0 0 10',
                    handler: function() {
                        me.toggleTheme();
                        var combo = this.up('container').down('#theme-selector');
                        if (combo) {
                            combo.setValue(me.getCurrentTheme());
                        }
                    }
                }
            ]
        };
    },
    
    // Create theme settings panel
    createThemeSettingsPanel: function() {
        var me = this;
        
        return {
            xtype: 'panel',
            title: gettext('Theme Settings'),
            items: [
                me.createThemeSelector(),
                {
                    xtype: 'checkbox',
                    name: 'enable_animations',
                    fieldLabel: gettext('Enable Animations'),
                    checked: me.getEnableAnimations(),
                    listeners: {
                        change: function(checkbox, newValue) {
                            me.setEnableAnimations(newValue);
                        }
                    }
                },
                {
                    xtype: 'numberfield',
                    name: 'transition_duration',
                    fieldLabel: gettext('Transition Duration (ms)'),
                    value: me.getTransitionDuration(),
                    minValue: 0,
                    maxValue: 1000,
                    step: 50,
                    listeners: {
                        change: function(field, newValue) {
                            me.setTransitionDuration(newValue);
                        }
                    }
                }
            ]
        };
    },
    
    // Apply theme to specific component
    applyThemeToComponent: function(component, themeName) {
        var me = this;
        
        if (!me.themes[themeName]) {
            return;
        }
        
        var theme = me.themes[themeName];
        var el = component.getEl ? component.getEl() : component;
        
        if (el && el.dom) {
            // Apply theme variables to component
            Object.keys(theme.variables).forEach(function(variable) {
                el.dom.style.setProperty(variable, theme.variables[variable]);
            });
            
            // Apply theme class
            el.removeCls('light-theme', 'dark-theme');
            el.addCls(themeName + '-theme');
        }
    },
    
    // Register component for theme updates
    registerComponent: function(component) {
        var me = this;
        
        // Listen for theme change events
        component.on('destroy', function() {
            // Cleanup when component is destroyed
        });
        
        // Apply current theme to component
        me.applyThemeToComponent(component, me.getCurrentTheme());
    },
    
    // Get theme-aware color
    getThemeColor: function(colorName) {
        var me = this;
        var theme = me.themes[me.getCurrentTheme()];
        
        if (theme && theme.variables['--' + colorName + '-color']) {
            return theme.variables['--' + colorName + '-color'];
        }
        
        // Fallback colors
        var fallbackColors = {
            'accent': '#667eea',
            'success': '#28a745',
            'warning': '#ffc107',
            'danger': '#dc3545',
            'info': '#17a2b8',
            'primary': '#007bff',
            'secondary': '#6c757d'
        };
        
        return fallbackColors[colorName] || '#000000';
    },
    
    // Create theme-aware button
    createThemedButton: function(config) {
        var me = this;
        
        var defaultConfig = {
            cls: 'modern-button',
            enableToggle: false,
            toggleGroup: null
        };
        
        return Ext.apply(defaultConfig, config, {
            listeners: {
                render: function(button) {
                    me.registerComponent(button);
                }
            }
        });
    },
    
    // Create theme-aware panel
    createThemedPanel: function(config) {
        var me = this;
        
        var defaultConfig = {
            cls: 'themed-panel'
        };
        
        return Ext.apply(defaultConfig, config, {
            listeners: {
                render: function(panel) {
                    me.registerComponent(panel);
                }
            }
        });
    }
});

// Initialize theme manager when document is ready
Ext.onReady(function() {
    PVE.SMBGatewayThemeManager.init();
});

// Export for global access
window.PVE.SMBGatewayThemeManager = PVE.SMBGatewayThemeManager; 