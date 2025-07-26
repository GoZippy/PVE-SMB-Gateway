/**
 * PVE SMB Gateway - Customizable Widgets System
 * Copyright (C) 2025 Eric Henderson <eric@gozippy.com>
 * Dual-licensed under AGPL-3.0 and Commercial License
 */

Ext.define('PVE.SMBGatewayWidgetManager', {
    singleton: true,
    
    // Widget configuration
    config: {
        enableDragDrop: true,
        enableResize: true,
        enableSnap: true,
        snapGrid: 10,
        widgetSpacing: 10,
        maxWidgets: 20
    },
    
    // Widget registry
    widgetRegistry: {},
    
    // Widget instances
    widgetInstances: {},
    
    // Widget layout storage
    widgetLayouts: {},
    
    init: function() {
        var me = this;
        
        // Initialize widget system
        me.initWidgetSystem();
        
        // Load saved layouts
        me.loadWidgetLayouts();
        
        // Register default widgets
        me.registerDefaultWidgets();
    },
    
    // Initialize widget system
    initWidgetSystem: function() {
        var me = this;
        
        // Set up drag and drop
        if (me.getEnableDragDrop()) {
            me.initDragDrop();
        }
        
        // Set up resize functionality
        if (me.getEnableResize()) {
            me.initResize();
        }
    },
    
    // Initialize drag and drop
    initDragDrop: function() {
        var me = this;
        
        // ExtJS drag and drop configuration
        me.dragDropConfig = {
            ddGroup: 'widgets',
            enableDrag: true,
            enableDrop: true,
            dragText: gettext('Moving widget...')
        };
    },
    
    // Initialize resize functionality
    initResize: function() {
        var me = this;
        
        // ExtJS resize configuration
        me.resizeConfig = {
            resizable: true,
            resizeHandles: 'all',
            minWidth: 200,
            minHeight: 150,
            maxWidth: 800,
            maxHeight: 600
        };
    },
    
    // Load widget layouts from localStorage
    loadWidgetLayouts: function() {
        var me = this;
        
        try {
            var savedLayouts = localStorage.getItem('smbgateway-widget-layouts');
            if (savedLayouts) {
                me.widgetLayouts = JSON.parse(savedLayouts);
            }
        } catch (e) {
            console.error('Failed to load widget layouts:', e);
            me.widgetLayouts = {};
        }
    },
    
    // Save widget layouts to localStorage
    saveWidgetLayouts: function() {
        var me = this;
        
        try {
            localStorage.setItem('smbgateway-widget-layouts', JSON.stringify(me.widgetLayouts));
        } catch (e) {
            console.error('Failed to save widget layouts:', e);
        }
    },
    
    // Register default widgets
    registerDefaultWidgets: function() {
        var me = this;
        
        // Register metric widgets
        me.registerWidget('metric', {
            name: 'Metric Widget',
            description: 'Display a single metric value',
            icon: 'fa fa-chart-bar',
            category: 'metrics',
            configurable: true,
            createWidget: me.createMetricWidget.bind(me)
        });
        
        // Register chart widgets
        me.registerWidget('chart', {
            name: 'Chart Widget',
            description: 'Display data in chart format',
            icon: 'fa fa-chart-line',
            category: 'charts',
            configurable: true,
            createWidget: me.createChartWidget.bind(me)
        });
        
        // Register alert widgets
        me.registerWidget('alerts', {
            name: 'Alerts Widget',
            description: 'Display recent alerts',
            icon: 'fa fa-exclamation-triangle',
            category: 'monitoring',
            configurable: true,
            createWidget: me.createAlertsWidget.bind(me)
        });
        
        // Register log widgets
        me.registerWidget('logs', {
            name: 'Logs Widget',
            description: 'Display recent log entries',
            icon: 'fa fa-file-text',
            category: 'monitoring',
            configurable: true,
            createWidget: me.createLogsWidget.bind(me)
        });
        
        // Register quick action widgets
        me.registerWidget('quick-actions', {
            name: 'Quick Actions',
            description: 'Common actions and shortcuts',
            icon: 'fa fa-bolt',
            category: 'actions',
            configurable: true,
            createWidget: me.createQuickActionsWidget.bind(me)
        });
        
        // Register system status widgets
        me.registerWidget('system-status', {
            name: 'System Status',
            description: 'System health and status indicators',
            icon: 'fa fa-heartbeat',
            category: 'monitoring',
            configurable: true,
            createWidget: me.createSystemStatusWidget.bind(me)
        });
    },
    
    // Register a widget type
    registerWidget: function(widgetType, config) {
        var me = this;
        
        me.widgetRegistry[widgetType] = Ext.apply({
            type: widgetType,
            defaultConfig: {},
            defaultSize: { width: 300, height: 200 }
        }, config);
    },
    
    // Create a widget instance
    createWidget: function(widgetType, config, container) {
        var me = this;
        
        if (!me.widgetRegistry[widgetType]) {
            console.error('Widget type not found:', widgetType);
            return null;
        }
        
        var widgetConfig = me.widgetRegistry[widgetType];
        var widgetId = 'widget_' + widgetType + '_' + Date.now();
        
        // Merge configurations
        var finalConfig = Ext.apply({}, widgetConfig.defaultConfig, config, {
            itemId: widgetId,
            widgetType: widgetType,
            cls: 'dashboard-widget',
            layout: 'fit',
            margin: me.getWidgetSpacing(),
            listeners: {
                render: function(widget) {
                    me.onWidgetRender(widget);
                },
                destroy: function(widget) {
                    me.onWidgetDestroy(widget);
                }
            }
        });
        
        // Create widget using the registered create function
        var widget = widgetConfig.createWidget(finalConfig, container);
        
        if (widget) {
            me.widgetInstances[widgetId] = widget;
            me.saveWidgetLayout(widgetId, widget);
        }
        
        return widget;
    },
    
    // Create metric widget
    createMetricWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('Metric'),
            items: [{
                xtype: 'displayfield',
                name: 'metric_value',
                value: config.value || '0',
                cls: 'metric-widget-value',
                fieldStyle: 'font-size: 2em; font-weight: bold; text-align: center;'
            }, {
                xtype: 'displayfield',
                name: 'metric_label',
                value: config.label || gettext('Metric Label'),
                cls: 'metric-widget-label',
                fieldStyle: 'text-align: center; color: #666;'
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Create chart widget
    createChartWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('Chart'),
            items: [{
                xtype: 'component',
                itemId: 'chart-container',
                cls: 'chart-widget-container',
                height: config.height || 150
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Create alerts widget
    createAlertsWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('Recent Alerts'),
            items: [{
                xtype: 'grid',
                itemId: 'alerts-grid',
                height: config.height || 150,
                columns: [{
                    text: gettext('Severity'),
                    dataIndex: 'severity',
                    width: 80,
                    renderer: function(value) {
                        var cls = 'alert-' + value;
                        return '<span class="' + cls + '">' + value + '</span>';
                    }
                }, {
                    text: gettext('Message'),
                    dataIndex: 'message',
                    flex: 1
                }, {
                    text: gettext('Time'),
                    dataIndex: 'timestamp',
                    width: 100
                }],
                store: {
                    fields: ['severity', 'message', 'timestamp'],
                    data: []
                }
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Create logs widget
    createLogsWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('Recent Logs'),
            items: [{
                xtype: 'textarea',
                name: 'logs-content',
                readOnly: true,
                height: config.height || 150,
                cls: 'logs-widget-content',
                value: gettext('Loading logs...')
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Create quick actions widget
    createQuickActionsWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('Quick Actions'),
            items: [{
                xtype: 'container',
                layout: 'vbox',
                padding: 10,
                items: [{
                    xtype: 'button',
                    text: gettext('Create Share'),
                    iconCls: 'fa fa-plus',
                    cls: 'modern-button primary',
                    margin: '0 0 5 0',
                    handler: function() {
                        // Trigger create share action
                        me.triggerAction('create-share');
                    }
                }, {
                    xtype: 'button',
                    text: gettext('Backup All'),
                    iconCls: 'fa fa-download',
                    cls: 'modern-button secondary',
                    margin: '0 0 5 0',
                    handler: function() {
                        // Trigger backup action
                        me.triggerAction('backup-all');
                    }
                }, {
                    xtype: 'button',
                    text: gettext('Security Scan'),
                    iconCls: 'fa fa-shield',
                    cls: 'modern-button warning',
                    margin: '0 0 5 0',
                    handler: function() {
                        // Trigger security scan
                        me.triggerAction('security-scan');
                    }
                }]
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Create system status widget
    createSystemStatusWidget: function(config, container) {
        var me = this;
        
        return Ext.create('Ext.panel.Panel', Ext.apply({
            title: config.title || gettext('System Status'),
            items: [{
                xtype: 'container',
                layout: 'vbox',
                padding: 10,
                items: [{
                    xtype: 'displayfield',
                    name: 'cpu-status',
                    fieldLabel: gettext('CPU'),
                    value: '0%',
                    cls: 'status-widget-field'
                }, {
                    xtype: 'displayfield',
                    name: 'memory-status',
                    fieldLabel: gettext('Memory'),
                    value: '0%',
                    cls: 'status-widget-field'
                }, {
                    xtype: 'displayfield',
                    name: 'disk-status',
                    fieldLabel: gettext('Disk'),
                    value: '0%',
                    cls: 'status-widget-field'
                }, {
                    xtype: 'displayfield',
                    name: 'network-status',
                    fieldLabel: gettext('Network'),
                    value: '0 Mbps',
                    cls: 'status-widget-field'
                }]
            }],
            tools: [{
                type: 'gear',
                tooltip: gettext('Configure Widget'),
                handler: function() {
                    me.configureWidget(config.itemId);
                }
            }, {
                type: 'close',
                tooltip: gettext('Remove Widget'),
                handler: function() {
                    me.removeWidget(config.itemId);
                }
            }]
        }, config));
    },
    
    // Widget render handler
    onWidgetRender: function(widget) {
        var me = this;
        
        // Apply drag and drop if enabled
        if (me.getEnableDragDrop()) {
            me.applyDragDrop(widget);
        }
        
        // Apply resize if enabled
        if (me.getEnableResize()) {
            me.applyResize(widget);
        }
        
        // Load widget data
        me.loadWidgetData(widget);
    },
    
    // Widget destroy handler
    onWidgetDestroy: function(widget) {
        var me = this;
        
        // Remove from instances
        delete me.widgetInstances[widget.getItemId()];
        
        // Remove from layouts
        delete me.widgetLayouts[widget.getItemId()];
        
        // Save layouts
        me.saveWidgetLayouts();
    },
    
    // Apply drag and drop to widget
    applyDragDrop: function(widget) {
        var me = this;
        
        if (widget.getEl()) {
            // Make widget draggable
            widget.setDraggable({
                ddGroup: me.dragDropConfig.ddGroup,
                dragText: me.dragDropConfig.dragText
            });
            
            // Make widget a drop target
            widget.setDropTarget({
                ddGroup: me.dragDropConfig.ddGroup,
                notifyDrop: function(source, e, data) {
                    me.handleWidgetDrop(widget, source, e, data);
                    return true;
                }
            });
        }
    },
    
    // Apply resize to widget
    applyResize: function(widget) {
        var me = this;
        
        if (widget.getEl()) {
            widget.setResizable(me.resizeConfig);
        }
    },
    
    // Handle widget drop
    handleWidgetDrop: function(targetWidget, sourceWidget, e, data) {
        var me = this;
        
        // Reorder widgets in container
        var container = targetWidget.up('container');
        if (container) {
            var targetIndex = container.items.indexOf(targetWidget);
            var sourceIndex = container.items.indexOf(sourceWidget);
            
            if (targetIndex !== -1 && sourceIndex !== -1) {
                container.move(sourceIndex, targetIndex);
                me.saveWidgetLayouts();
            }
        }
    },
    
    // Load widget data
    loadWidgetData: function(widget) {
        var me = this;
        
        var widgetType = widget.widgetType;
        
        switch (widgetType) {
            case 'metric':
                me.loadMetricData(widget);
                break;
            case 'chart':
                me.loadChartData(widget);
                break;
            case 'alerts':
                me.loadAlertsData(widget);
                break;
            case 'logs':
                me.loadLogsData(widget);
                break;
            case 'system-status':
                me.loadSystemStatusData(widget);
                break;
        }
    },
    
    // Load metric data
    loadMetricData: function(widget) {
        // API call to get metric data
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/metrics',
            method: 'GET',
            success: function(response) {
                var metricField = widget.down('displayfield[name=metric_value]');
                if (metricField) {
                    metricField.setValue(response.data.value || '0');
                }
            }
        });
    },
    
    // Load chart data
    loadChartData: function(widget) {
        // Initialize chart if D3.js is available
        if (typeof d3 !== 'undefined') {
            var chartContainer = widget.down('#chart-container');
            if (chartContainer) {
                // Create chart
                me.createWidgetChart(chartContainer, widget.widgetConfig);
            }
        }
    },
    
    // Load alerts data
    loadAlertsData: function(widget) {
        // API call to get alerts data
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/alerts',
            method: 'GET',
            success: function(response) {
                var alertsGrid = widget.down('#alerts-grid');
                if (alertsGrid && response.data.alerts) {
                    alertsGrid.getStore().loadData(response.data.alerts);
                }
            }
        });
    },
    
    // Load logs data
    loadLogsData: function(widget) {
        // API call to get logs data
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/logs',
            method: 'GET',
            success: function(response) {
                var logsField = widget.down('textarea[name=logs-content]');
                if (logsField && response.data.logs) {
                    logsField.setValue(response.data.logs.join('\n'));
                }
            }
        });
    },
    
    // Load system status data
    loadSystemStatusData: function(widget) {
        // API call to get system status
        PVE.Utils.API2Request({
            url: '/nodes/localhost/smbgateway/system/status',
            method: 'GET',
            success: function(response) {
                var data = response.data;
                
                var cpuField = widget.down('displayfield[name=cpu-status]');
                if (cpuField) cpuField.setValue((data.cpu || 0) + '%');
                
                var memoryField = widget.down('displayfield[name=memory-status]');
                if (memoryField) memoryField.setValue((data.memory || 0) + '%');
                
                var diskField = widget.down('displayfield[name=disk-status]');
                if (diskField) diskField.setValue((data.disk || 0) + '%');
                
                var networkField = widget.down('displayfield[name=network-status]');
                if (networkField) networkField.setValue((data.network || 0) + ' Mbps');
            }
        });
    },
    
    // Save widget layout
    saveWidgetLayout: function(widgetId, widget) {
        var me = this;
        
        var layout = {
            type: widget.widgetType,
            config: widget.initialConfig,
            position: {
                x: widget.getX(),
                y: widget.getY()
            },
            size: {
                width: widget.getWidth(),
                height: widget.getHeight()
            }
        };
        
        me.widgetLayouts[widgetId] = layout;
        me.saveWidgetLayouts();
    },
    
    // Configure widget
    configureWidget: function(widgetId) {
        var me = this;
        
        var widget = me.widgetInstances[widgetId];
        if (!widget) return;
        
        var widgetType = widget.widgetType;
        var widgetConfig = me.widgetRegistry[widgetType];
        
        if (!widgetConfig || !widgetConfig.configurable) return;
        
        // Show configuration dialog
        Ext.create('Ext.window.Window', {
            title: gettext('Configure Widget: ') + widgetConfig.name,
            width: 400,
            height: 300,
            modal: true,
            items: [{
                xtype: 'form',
                bodyPadding: 10,
                items: [{
                    xtype: 'textfield',
                    name: 'title',
                    fieldLabel: gettext('Widget Title'),
                    value: widget.getTitle()
                }, {
                    xtype: 'numberfield',
                    name: 'width',
                    fieldLabel: gettext('Width'),
                    value: widget.getWidth(),
                    minValue: 200,
                    maxValue: 800
                }, {
                    xtype: 'numberfield',
                    name: 'height',
                    fieldLabel: gettext('Height'),
                    value: widget.getHeight(),
                    minValue: 150,
                    maxValue: 600
                }],
                buttons: [{
                    text: gettext('Save'),
                    handler: function() {
                        var form = this.up('form');
                        var values = form.getValues();
                        
                        widget.setTitle(values.title);
                        widget.setSize(values.width, values.height);
                        
                        me.saveWidgetLayout(widgetId, widget);
                        this.up('window').close();
                    }
                }, {
                    text: gettext('Cancel'),
                    handler: function() {
                        this.up('window').close();
                    }
                }]
            }]
        }).show();
    },
    
    // Remove widget
    removeWidget: function(widgetId) {
        var me = this;
        
        var widget = me.widgetInstances[widgetId];
        if (widget) {
            widget.destroy();
        }
    },
    
    // Trigger action
    triggerAction: function(action) {
        var me = this;
        
        // Fire action event
        var event = new CustomEvent('smbgateway-widget-action', {
            detail: {
                action: action,
                timestamp: new Date().toISOString()
            }
        });
        document.dispatchEvent(event);
    },
    
    // Get available widgets
    getAvailableWidgets: function() {
        var me = this;
        
        return Object.keys(me.widgetRegistry).map(function(widgetType) {
            var config = me.widgetRegistry[widgetType];
            return {
                type: widgetType,
                name: config.name,
                description: config.description,
                icon: config.icon,
                category: config.category
            };
        });
    },
    
    // Create widget selector
    createWidgetSelector: function(container) {
        var me = this;
        
        return Ext.create('Ext.window.Window', {
            title: gettext('Add Widget'),
            width: 500,
            height: 400,
            modal: true,
            items: [{
                xtype: 'grid',
                itemId: 'widget-selector-grid',
                columns: [{
                    text: gettext('Widget'),
                    dataIndex: 'name',
                    flex: 1
                }, {
                    text: gettext('Category'),
                    dataIndex: 'category',
                    width: 100
                }, {
                    text: gettext('Description'),
                    dataIndex: 'description',
                    flex: 2
                }],
                store: {
                    fields: ['type', 'name', 'description', 'icon', 'category'],
                    data: me.getAvailableWidgets()
                },
                listeners: {
                    itemdblclick: function(grid, record) {
                        me.createWidget(record.get('type'), {}, container);
                        this.up('window').close();
                    }
                }
            }],
            buttons: [{
                text: gettext('Add Selected'),
                handler: function() {
                    var grid = this.up('window').down('#widget-selector-grid');
                    var selection = grid.getSelectionModel().getSelection();
                    
                    if (selection.length > 0) {
                        var record = selection[0];
                        me.createWidget(record.get('type'), {}, container);
                        this.up('window').close();
                    }
                }
            }, {
                text: gettext('Cancel'),
                handler: function() {
                    this.up('window').close();
                }
            }]
        });
    }
});

// Initialize widget manager when document is ready
Ext.onReady(function() {
    PVE.SMBGatewayWidgetManager.init();
});

// Export for global access
window.PVE.SMBGatewayWidgetManager = PVE.SMBGatewayWidgetManager; 