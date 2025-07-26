Ext.define('PVE.SMBGatewayModernDashboard', {
    extend: 'Ext.panel.Panel',
    xtype: 'pveSMBGatewayModernDashboard',
    
    title: gettext('SMB Gateway Dashboard'),
    iconCls: 'fa fa-share-alt',
    cls: 'modern-dashboard',
    
    layout: 'border',
    
    // Modern dashboard configuration
    config: {
        darkMode: false,
        autoRefresh: true,
        refreshInterval: 30000, // 30 seconds
        enableAnimations: true,
        showAlerts: true
    },
    
    initComponent: function() {
        var me = this;
        
        // Initialize WebSocket connection for real-time updates
        me.initWebSocket();
        
        // Initialize theme
        me.initTheme();
        
        me.items = [
            // Enhanced Sidebar with modern design
            {
                xtype: 'panel',
                region: 'west',
                width: 320,
                split: true,
                cls: 'dashboard-sidebar',
                title: gettext('Quick Actions'),
                items: [
                    {
                        xtype: 'container',
                        layout: 'vbox',
                        margin: '10',
                        items: [
                            // Enhanced Create Share Button
                            {
                                xtype: 'button',
                                text: gettext('Create New Share'),
                                iconCls: 'fa fa-plus',
                                cls: 'modern-button primary',
                                margin: '0 0 10 0',
                                width: '100%',
                                handler: function() {
                                    me.createNewShare();
                                }
                            },
                            // Enhanced Backup Button
                            {
                                xtype: 'button',
                                text: gettext('Backup All Shares'),
                                iconCls: 'fa fa-download',
                                cls: 'modern-button secondary',
                                margin: '0 0 10 0',
                                width: '100%',
                                handler: function() {
                                    me.backupAllShares();
                                }
                            },
                            // Enhanced Security Button
                            {
                                xtype: 'button',
                                text: gettext('Security Scan'),
                                iconCls: 'fa fa-shield',
                                cls: 'modern-button warning',
                                margin: '0 0 10 0',
                                width: '100%',
                                handler: function() {
                                    me.runSecurityScan();
                                }
                            },
                            // Enhanced Performance Button
                            {
                                xtype: 'button',
                                text: gettext('Performance Test'),
                                iconCls: 'fa fa-tachometer',
                                cls: 'modern-button info',
                                margin: '0 0 10 0',
                                width: '100%',
                                handler: function() {
                                    me.runPerformanceTest();
                                }
                            },
                            // Enhanced Settings Button
                            {
                                xtype: 'button',
                                text: gettext('Settings'),
                                iconCls: 'fa fa-cog',
                                cls: 'modern-button default',
                                margin: '0 0 10 0',
                                width: '100%',
                                handler: function() {
                                    me.showSettings();
                                }
                            },
                            // Theme Toggle Button
                            {
                                xtype: 'button',
                                text: gettext('Toggle Theme'),
                                iconCls: 'fa fa-moon-o',
                                cls: 'modern-button theme-toggle',
                                margin: '10 0 0 0',
                                width: '100%',
                                handler: function() {
                                    me.toggleTheme();
                                }
                            }
                        ]
                    }
                ]
            },
            // Enhanced Main Content Area
            {
                xtype: 'tabpanel',
                region: 'center',
                cls: 'dashboard-main',
                items: [
                    // Enhanced Overview Tab
                    {
                        xtype: 'panel',
                        title: gettext('Overview'),
                        iconCls: 'fa fa-dashboard',
                        items: [
                            {
                                xtype: 'container',
                                layout: 'vbox',
                                margin: '10',
                                items: [
                                    // Real-time Metrics Row
                                    {
                                        xtype: 'container',
                                        layout: 'hbox',
                                        margin: '0 0 10 0',
                                        items: [
                                            // Enhanced Shares Panel
                                            {
                                                xtype: 'panel',
                                                title: gettext('Shares'),
                                                flex: 1,
                                                margin: '0 5 0 0',
                                                cls: 'metric-panel',
                                                items: [
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'total_shares',
                                                        fieldLabel: gettext('Total Shares'),
                                                        value: '0',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'active_shares',
                                                        fieldLabel: gettext('Active Shares'),
                                                        value: '0',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'total_storage',
                                                        fieldLabel: gettext('Total Storage'),
                                                        value: '0 GB',
                                                        cls: 'metric-value'
                                                    }
                                                ]
                                            },
                                            // Enhanced Performance Panel
                                            {
                                                xtype: 'panel',
                                                title: gettext('Performance'),
                                                flex: 1,
                                                margin: '0 5 0 0',
                                                cls: 'metric-panel',
                                                items: [
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'total_throughput',
                                                        fieldLabel: gettext('Total Throughput'),
                                                        value: '0 Mbps',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'avg_latency',
                                                        fieldLabel: gettext('Avg Latency'),
                                                        value: '0 ms',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'active_connections',
                                                        fieldLabel: gettext('Active Connections'),
                                                        value: '0',
                                                        cls: 'metric-value'
                                                    }
                                                ]
                                            },
                                            // Enhanced System Panel
                                            {
                                                xtype: 'panel',
                                                title: gettext('System'),
                                                flex: 1,
                                                margin: '0 0 0 5',
                                                cls: 'metric-panel',
                                                items: [
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'cpu_usage',
                                                        fieldLabel: gettext('CPU Usage'),
                                                        value: '0%',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'memory_usage',
                                                        fieldLabel: gettext('Memory Usage'),
                                                        value: '0%',
                                                        cls: 'metric-value'
                                                    },
                                                    {
                                                        xtype: 'displayfield',
                                                        name: 'disk_usage',
                                                        fieldLabel: gettext('Disk Usage'),
                                                        value: '0%',
                                                        cls: 'metric-value'
                                                    }
                                                ]
                                            }
                                        ]
                                    },
                                    // Interactive Charts Row
                                    {
                                        xtype: 'container',
                                        layout: 'hbox',
                                        margin: '0 0 10 0',
                                        items: [
                                            // Throughput Chart
                                            {
                                                xtype: 'panel',
                                                title: gettext('Throughput Over Time'),
                                                flex: 1,
                                                margin: '0 5 0 0',
                                                cls: 'chart-panel',
                                                items: [
                                                    {
                                                        xtype: 'component',
                                                        itemId: 'throughput-chart',
                                                        cls: 'chart-container',
                                                        height: 200
                                                    }
                                                ]
                                            },
                                            // Latency Chart
                                            {
                                                xtype: 'panel',
                                                title: gettext('Latency Over Time'),
                                                flex: 1,
                                                margin: '0 0 0 5',
                                                cls: 'chart-panel',
                                                items: [
                                                    {
                                                        xtype: 'component',
                                                        itemId: 'latency-chart',
                                                        cls: 'chart-container',
                                                        height: 200
                                                    }
                                                ]
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    },
                    // Enhanced Monitoring Tab
                    {
                        xtype: 'panel',
                        title: gettext('Monitoring'),
                        iconCls: 'fa fa-chart-line',
                        items: [
                            {
                                xtype: 'container',
                                layout: 'vbox',
                                margin: '10',
                                items: [
                                    // Real-time Performance Metrics
                                    {
                                        xtype: 'panel',
                                        title: gettext('Performance Metrics'),
                                        flex: 1,
                                        cls: 'monitoring-panel',
                                        items: [
                                            {
                                                xtype: 'component',
                                                itemId: 'performance-chart',
                                                cls: 'chart-container',
                                                height: 300
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    },
                    // Enhanced Alerts Tab
                    {
                        xtype: 'panel',
                        title: gettext('Alerts'),
                        iconCls: 'fa fa-exclamation-triangle',
                        items: [
                            {
                                xtype: 'container',
                                layout: 'vbox',
                                margin: '10',
                                items: [
                                    // Alert Center
                                    {
                                        xtype: 'panel',
                                        title: gettext('Active Alerts'),
                                        flex: 1,
                                        cls: 'alerts-panel',
                                        items: [
                                            {
                                                xtype: 'grid',
                                                itemId: 'alerts-grid',
                                                cls: 'alerts-grid',
                                                columns: [
                                                    {
                                                        text: gettext('Severity'),
                                                        dataIndex: 'severity',
                                                        width: 80,
                                                        renderer: function(value) {
                                                            var cls = '';
                                                            switch(value) {
                                                                case 'critical': cls = 'alert-critical'; break;
                                                                case 'warning': cls = 'alert-warning'; break;
                                                                case 'info': cls = 'alert-info'; break;
                                                            }
                                                            return '<span class="' + cls + '">' + value + '</span>';
                                                        }
                                                    },
                                                    {
                                                        text: gettext('Message'),
                                                        dataIndex: 'message',
                                                        flex: 1
                                                    },
                                                    {
                                                        text: gettext('Time'),
                                                        dataIndex: 'timestamp',
                                                        width: 150
                                                    },
                                                    {
                                                        text: gettext('Actions'),
                                                        width: 100,
                                                        renderer: function(value, meta, record) {
                                                            return '<button class="alert-action-btn">Acknowledge</button>';
                                                        }
                                                    }
                                                ],
                                                store: {
                                                    fields: ['severity', 'message', 'timestamp'],
                                                    data: []
                                                }
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    },
                    // Enhanced Logs Tab
                    {
                        xtype: 'panel',
                        title: gettext('Logs'),
                        iconCls: 'fa fa-file-text',
                        items: [
                            {
                                xtype: 'container',
                                layout: 'vbox',
                                margin: '10',
                                items: [
                                    // Enhanced Log Viewer
                                    {
                                        xtype: 'panel',
                                        title: gettext('System Logs'),
                                        flex: 1,
                                        cls: 'logs-panel',
                                        items: [
                                            {
                                                xtype: 'textarea',
                                                name: 'log_viewer',
                                                readOnly: true,
                                                height: 400,
                                                cls: 'log-viewer',
                                                value: gettext('Loading logs...')
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    }
                ]
            },
            // Enhanced Alert Panel
            {
                xtype: 'panel',
                region: 'east',
                width: 280,
                split: true,
                cls: 'dashboard-alerts',
                title: gettext('Quick Alerts'),
                items: [
                    {
                        xtype: 'container',
                        layout: 'vbox',
                        margin: '10',
                        items: [
                            {
                                xtype: 'component',
                                itemId: 'quick-alerts',
                                cls: 'quick-alerts-container',
                                html: '<div class="no-alerts">No active alerts</div>'
                            }
                        ]
                    }
                ]
            }
        ];
        
        me.callParent();
        
        // Initialize real-time updates
        me.initRealTimeUpdates();
        
        // Initialize charts
        me.initCharts();
        
        // Load initial data
        me.loadDashboardData();
    },
    
    // Initialize WebSocket connection
    initWebSocket: function() {
        var me = this;
        
        // WebSocket connection for real-time updates
        me.websocket = null;
        
        try {
            // Initialize WebSocket connection
            me.websocket = new WebSocket('ws://localhost:8006/api2/json/nodes/localhost/smbgateway/websocket');
            
            me.websocket.onopen = function() {
                console.log('WebSocket connected for real-time updates');
            };
            
            me.websocket.onmessage = function(event) {
                var data = JSON.parse(event.data);
                me.handleRealTimeUpdate(data);
            };
            
            me.websocket.onerror = function(error) {
                console.error('WebSocket error:', error);
                // Fallback to polling
                me.initPolling();
            };
            
            me.websocket.onclose = function() {
                console.log('WebSocket disconnected');
                // Fallback to polling
                me.initPolling();
            };
        } catch (e) {
            console.log('WebSocket not available, using polling');
            me.initPolling();
        }
    },
    
    // Initialize polling fallback
    initPolling: function() {
        var me = this;
        
        if (me.getAutoRefresh()) {
            me.pollingInterval = setInterval(function() {
                me.loadDashboardData();
            }, me.getRefreshInterval());
        }
    },
    
    // Initialize theme
    initTheme: function() {
        var me = this;
        
        // Use the theme manager
        if (PVE.SMBGatewayThemeManager) {
            // Register this component with the theme manager
            PVE.SMBGatewayThemeManager.registerComponent(me);
        }
    },
    
    // Apply theme to dashboard (deprecated - use theme manager)
    applyTheme: function() {
        var me = this;
        
        if (PVE.SMBGatewayThemeManager) {
            PVE.SMBGatewayThemeManager.applyThemeToComponent(me, PVE.SMBGatewayThemeManager.getCurrentTheme());
        }
    },
    
    // Toggle theme
    toggleTheme: function() {
        var me = this;
        
        if (PVE.SMBGatewayThemeManager) {
            PVE.SMBGatewayThemeManager.toggleTheme();
            
            // Update theme toggle button
            var themeBtn = me.down('button[cls*="theme-toggle"]');
            if (themeBtn) {
                var currentTheme = PVE.SMBGatewayThemeManager.getCurrentTheme();
                themeBtn.setIconCls(currentTheme === 'dark' ? 'fa fa-sun-o' : 'fa fa-moon-o');
                themeBtn.setText(currentTheme === 'dark' ? gettext('Light Mode') : gettext('Dark Mode'));
            }
        }
    },
    
    // Initialize real-time updates
    initRealTimeUpdates: function() {
        var me = this;
        
        // Set up real-time update handlers
        me.realTimeHandlers = {
            'metrics': me.updateMetrics.bind(me),
            'alerts': me.updateAlerts.bind(me),
            'logs': me.updateLogs.bind(me)
        };
    },
    
    // Handle real-time updates
    handleRealTimeUpdate: function(data) {
        var me = this;
        
        if (data.type && me.realTimeHandlers[data.type]) {
            me.realTimeHandlers[data.type](data);
        }
    },
    
    // Initialize charts
    initCharts: function() {
        var me = this;
        
        // Initialize D3.js charts if available
        if (typeof d3 !== 'undefined') {
            me.initD3Charts();
        } else {
            // Fallback to simple charts
            me.initSimpleCharts();
        }
    },
    
    // Initialize D3.js charts
    initD3Charts: function() {
        var me = this;
        
        // Throughput chart
        var throughputChart = me.down('#throughput-chart');
        if (throughputChart) {
            me.createD3Chart(throughputChart.el.dom, 'throughput');
        }
        
        // Latency chart
        var latencyChart = me.down('#latency-chart');
        if (latencyChart) {
            me.createD3Chart(latencyChart.el.dom, 'latency');
        }
        
        // Performance chart
        var performanceChart = me.down('#performance-chart');
        if (performanceChart) {
            me.createD3Chart(performanceChart.el.dom, 'performance');
        }
    },
    
    // Create D3.js chart
    createD3Chart: function(container, type) {
        // D3.js chart implementation
        var width = container.clientWidth;
        var height = container.clientHeight;
        
        var svg = d3.select(container)
            .append('svg')
            .attr('width', width)
            .attr('height', height);
        
        // Chart implementation based on type
        switch(type) {
            case 'throughput':
                this.createThroughputChart(svg, width, height);
                break;
            case 'latency':
                this.createLatencyChart(svg, width, height);
                break;
            case 'performance':
                this.createPerformanceChart(svg, width, height);
                break;
        }
    },
    
    // Create throughput chart
    createThroughputChart: function(svg, width, height) {
        // D3.js throughput chart implementation
        var margin = {top: 20, right: 20, bottom: 30, left: 40};
        var chartWidth = width - margin.left - margin.right;
        var chartHeight = height - margin.top - margin.bottom;
        
        var chart = svg.append('g')
            .attr('transform', 'translate(' + margin.left + ',' + margin.top + ')');
        
        // Chart implementation
        // ... (D3.js chart code)
    },
    
    // Create latency chart
    createLatencyChart: function(svg, width, height) {
        // D3.js latency chart implementation
        // ... (D3.js chart code)
    },
    
    // Create performance chart
    createPerformanceChart: function(svg, width, height) {
        // D3.js performance chart implementation
        // ... (D3.js chart code)
    },
    
    // Initialize simple charts (fallback)
    initSimpleCharts: function() {
        var me = this;
        
        // Simple chart implementation using ExtJS components
        // ... (Simple chart code)
    },
    
    // Load dashboard data
    loadDashboardData: function() {
        var me = this;
        
        // Load metrics data
        me.loadMetricsData();
        
        // Load alerts data
        me.loadAlertsData();
        
        // Load logs data
        me.loadLogsData();
    },
    
    // Load metrics data
    loadMetricsData: function() {
        var me = this;
        
        // API call to get metrics
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/metrics',
            method: 'GET',
            success: function(response) {
                me.updateMetrics(response.data);
            },
            failure: function(response) {
                console.error('Failed to load metrics:', response);
            }
        });
    },
    
    // Load alerts data
    loadAlertsData: function() {
        var me = this;
        
        // API call to get alerts
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/alerts',
            method: 'GET',
            success: function(response) {
                me.updateAlerts(response.data);
            },
            failure: function(response) {
                console.error('Failed to load alerts:', response);
            }
        });
    },
    
    // Load logs data
    loadLogsData: function() {
        var me = this;
        
        // API call to get logs
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/logs',
            method: 'GET',
            success: function(response) {
                me.updateLogs(response.data);
            },
            failure: function(response) {
                console.error('Failed to load logs:', response);
            }
        });
    },
    
    // Update metrics display
    updateMetrics: function(data) {
        var me = this;
        
        // Update share metrics
        if (data.shares) {
            me.updateField('total_shares', data.shares.total || 0);
            me.updateField('active_shares', data.shares.active || 0);
            me.updateField('total_storage', (data.shares.storage || 0) + ' GB');
        }
        
        // Update performance metrics
        if (data.performance) {
            me.updateField('total_throughput', (data.performance.throughput || 0) + ' Mbps');
            me.updateField('avg_latency', (data.performance.latency || 0) + ' ms');
            me.updateField('active_connections', data.performance.connections || 0);
        }
        
        // Update system metrics
        if (data.system) {
            me.updateField('cpu_usage', (data.system.cpu || 0) + '%');
            me.updateField('memory_usage', (data.system.memory || 0) + '%');
            me.updateField('disk_usage', (data.system.disk || 0) + '%');
        }
        
        // Update charts if available
        if (typeof d3 !== 'undefined') {
            me.updateCharts(data);
        }
    },
    
    // Update alerts display
    updateAlerts: function(data) {
        var me = this;
        
        // Update alerts grid
        var alertsGrid = me.down('#alerts-grid');
        if (alertsGrid && data.alerts) {
            alertsGrid.getStore().loadData(data.alerts);
        }
        
        // Update quick alerts
        me.updateQuickAlerts(data.alerts || []);
    },
    
    // Update logs display
    updateLogs: function(data) {
        var me = this;
        
        var logViewer = me.down('textarea[name=log_viewer]');
        if (logViewer && data.logs) {
            logViewer.setValue(data.logs.join('\n'));
        }
    },
    
    // Update field value with animation
    updateField: function(fieldName, value) {
        var me = this;
        
        var field = me.down('displayfield[name=' + fieldName + ']');
        if (field) {
            if (me.getEnableAnimations()) {
                // Animate value change
                me.animateValueChange(field, value);
            } else {
                field.setValue(value);
            }
        }
    },
    
    // Animate value change
    animateValueChange: function(field, newValue) {
        var oldValue = field.getValue();
        
        // Simple animation effect
        field.addCls('value-changing');
        field.setValue(newValue);
        
        setTimeout(function() {
            field.removeCls('value-changing');
        }, 300);
    },
    
    // Update quick alerts
    updateQuickAlerts: function(alerts) {
        var me = this;
        
        var quickAlerts = me.down('#quick-alerts');
        if (quickAlerts) {
            if (alerts.length === 0) {
                quickAlerts.setHtml('<div class="no-alerts">No active alerts</div>');
            } else {
                var html = '';
                alerts.slice(0, 5).forEach(function(alert) {
                    html += '<div class="quick-alert ' + alert.severity + '">' +
                           '<span class="alert-icon">' + me.getAlertIcon(alert.severity) + '</span>' +
                           '<span class="alert-message">' + alert.message + '</span>' +
                           '</div>';
                });
                quickAlerts.setHtml(html);
            }
        }
    },
    
    // Get alert icon
    getAlertIcon: function(severity) {
        switch(severity) {
            case 'critical': return 'fa fa-exclamation-circle';
            case 'warning': return 'fa fa-exclamation-triangle';
            case 'info': return 'fa fa-info-circle';
            default: return 'fa fa-info-circle';
        }
    },
    
    // Update charts
    updateCharts: function(data) {
        var me = this;
        
        // Update D3.js charts with new data
        // ... (Chart update implementation)
    },
    
    // Enhanced action methods
    createNewShare: function() {
        var me = this;
        
        // Show enhanced share creation wizard
        Ext.create('PVE.SMBGatewaySmartWizard', {
            title: gettext('Create New Share'),
            modal: true,
            width: 900,
            height: 700
        }).show();
    },
    
    backupAllShares: function() {
        var me = this;
        
        // Show backup confirmation dialog
        Ext.Msg.confirm(
            gettext('Backup All Shares'),
            gettext('Are you sure you want to backup all shares? This may take some time.'),
            function(btn) {
                if (btn === 'yes') {
                    me.performBackup();
                }
            }
        );
    },
    
    performBackup: function() {
        var me = this;
        
        // Show progress dialog
        var progressDialog = Ext.create('Ext.window.Window', {
            title: gettext('Backup Progress'),
            width: 400,
            height: 200,
            modal: true,
            items: [{
                xtype: 'progressbar',
                itemId: 'backup-progress',
                text: gettext('Starting backup...')
            }]
        });
        
        progressDialog.show();
        
        // Perform backup
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/backup',
            method: 'POST',
            success: function(response) {
                progressDialog.close();
                Ext.Msg.alert(gettext('Success'), gettext('Backup completed successfully.'));
            },
            failure: function(response) {
                progressDialog.close();
                Ext.Msg.alert(gettext('Error'), gettext('Backup failed: ') + response.statusText);
            }
        });
    },
    
    runSecurityScan: function() {
        var me = this;
        
        // Show security scan dialog
        Ext.Msg.confirm(
            gettext('Security Scan'),
            gettext('Run a comprehensive security scan on all shares?'),
            function(btn) {
                if (btn === 'yes') {
                    me.performSecurityScan();
                }
            }
        );
    },
    
    performSecurityScan: function() {
        var me = this;
        
        // Security scan implementation
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/security/scan',
            method: 'POST',
            success: function(response) {
                Ext.Msg.alert(gettext('Security Scan Complete'), 
                    gettext('Scan completed. Found ') + response.data.issues + ' issues.');
            },
            failure: function(response) {
                Ext.Msg.alert(gettext('Error'), gettext('Security scan failed: ') + response.statusText);
            }
        });
    },
    
    runPerformanceTest: function() {
        var me = this;
        
        // Show performance test dialog
        Ext.Msg.confirm(
            gettext('Performance Test'),
            gettext('Run performance tests on all shares? This may impact performance temporarily.'),
            function(btn) {
                if (btn === 'yes') {
                    me.performPerformanceTest();
                }
            }
        );
    },
    
    performPerformanceTest: function() {
        var me = this;
        
        // Performance test implementation
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/performance/test',
            method: 'POST',
            success: function(response) {
                Ext.Msg.alert(gettext('Performance Test Complete'), 
                    gettext('Test completed. Average throughput: ') + response.data.throughput + ' Mbps');
            },
            failure: function(response) {
                Ext.Msg.alert(gettext('Error'), gettext('Performance test failed: ') + response.statusText);
            }
        });
    },
    
    showSettings: function() {
        var me = this;
        
        // Show enhanced settings dialog
        Ext.create('PVE.SMBGatewaySettings', {
            title: gettext('SMB Gateway Settings'),
            modal: true,
            width: 800,
            height: 600
        }).show();
    },
    
    // Cleanup on destroy
    onDestroy: function() {
        var me = this;
        
        // Close WebSocket connection
        if (me.websocket) {
            me.websocket.close();
        }
        
        // Clear polling interval
        if (me.pollingInterval) {
            clearInterval(me.pollingInterval);
        }
        
        me.callParent();
    }
});

// Register the enhanced dashboard component
Ext.define('PVE.SMBGatewayDashboard', {
    extend: 'PVE.SMBGatewayModernDashboard'
}); 