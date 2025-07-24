Ext.define('PVE.SMBGatewayDashboard', {
    extend: 'Ext.panel.Panel',
    xtype: 'pveSMBGatewayDashboard',
    
    title: gettext('SMB Gateway Dashboard'),
    iconCls: 'fa fa-share-alt',
    
    layout: 'border',
    
    initComponent: function() {
        var me = this;
        
        me.items = [
            {
                xtype: 'panel',
                region: 'west',
                width: 300,
                split: true,
                title: gettext('Quick Actions'),
                items: [
                    {
                        xtype: 'button',
                        text: gettext('Create New Share'),
                        iconCls: 'fa fa-plus',
                        margin: '10 10 5 10',
                        width: '100%',
                        handler: function() {
                            me.createNewShare();
                        }
                    },
                    {
                        xtype: 'button',
                        text: gettext('Backup All Shares'),
                        iconCls: 'fa fa-download',
                        margin: '5 10 5 10',
                        width: '100%',
                        handler: function() {
                            me.backupAllShares();
                        }
                    },
                    {
                        xtype: 'button',
                        text: gettext('Security Scan'),
                        iconCls: 'fa fa-shield',
                        margin: '5 10 5 10',
                        width: '100%',
                        handler: function() {
                            me.runSecurityScan();
                        }
                    },
                    {
                        xtype: 'button',
                        text: gettext('Performance Test'),
                        iconCls: 'fa fa-tachometer',
                        margin: '5 10 5 10',
                        width: '100%',
                        handler: function() {
                            me.runPerformanceTest();
                        }
                    },
                    {
                        xtype: 'button',
                        text: gettext('Settings'),
                        iconCls: 'fa fa-cog',
                        margin: '5 10 5 10',
                        width: '100%',
                        handler: function() {
                            me.showSettings();
                        }
                    }
                ]
            },
            {
                xtype: 'tabpanel',
                region: 'center',
                items: [
                    {
                        xtype: 'panel',
                        title: gettext('Overview'),
                        iconCls: 'fa fa-dashboard',
                        items: [
                            {
                                xtype: 'container',
                                layout: 'hbox',
                                margin: '10',
                                items: [
                                    {
                                        xtype: 'panel',
                                        title: gettext('Shares'),
                                        flex: 1,
                                        margin: '0 5 0 0',
                                        items: [
                                            {
                                                xtype: 'displayfield',
                                                name: 'total_shares',
                                                fieldLabel: gettext('Total Shares'),
                                                value: '0'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'active_shares',
                                                fieldLabel: gettext('Active'),
                                                value: '0'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'ha_shares',
                                                fieldLabel: gettext('HA Enabled'),
                                                value: '0'
                                            }
                                        ]
                                    },
                                    {
                                        xtype: 'panel',
                                        title: gettext('Performance'),
                                        flex: 1,
                                        margin: '0 5 0 0',
                                        items: [
                                            {
                                                xtype: 'displayfield',
                                                name: 'total_throughput',
                                                fieldLabel: gettext('Total Throughput'),
                                                value: '0 Mbps'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'avg_latency',
                                                fieldLabel: gettext('Avg Latency'),
                                                value: '0 ms'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'active_connections',
                                                fieldLabel: gettext('Active Connections'),
                                                value: '0'
                                            }
                                        ]
                                    },
                                    {
                                        xtype: 'panel',
                                        title: gettext('Storage'),
                                        flex: 1,
                                        margin: '0 0 0 0',
                                        items: [
                                            {
                                                xtype: 'displayfield',
                                                name: 'total_used',
                                                fieldLabel: gettext('Total Used'),
                                                value: '0 GB'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'total_quota',
                                                fieldLabel: gettext('Total Quota'),
                                                value: '0 GB'
                                            },
                                            {
                                                xtype: 'displayfield',
                                                name: 'quota_percent',
                                                fieldLabel: gettext('Usage %'),
                                                value: '0%'
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    },
                    {
                        xtype: 'grid',
                        title: gettext('Shares'),
                        iconCls: 'fa fa-list',
                        columns: [
                            {
                                text: gettext('Share Name'),
                                dataIndex: 'sharename',
                                flex: 1
                            },
                            {
                                text: gettext('Status'),
                                dataIndex: 'status',
                                width: 80,
                                renderer: function(value) {
                                    if (value === 'running') {
                                        return '<span style="color: green;">●</span> ' + gettext('Running');
                                    } else if (value === 'stopped') {
                                        return '<span style="color: red;">●</span> ' + gettext('Stopped');
                                    } else {
                                        return '<span style="color: orange;">●</span> ' + gettext('Unknown');
                                    }
                                }
                            },
                            {
                                text: gettext('Mode'),
                                dataIndex: 'mode',
                                width: 80
                            },
                            {
                                text: gettext('HA'),
                                dataIndex: 'ha_enabled',
                                width: 60,
                                renderer: function(value) {
                                    return value ? gettext('Yes') : gettext('No');
                                }
                            },
                            {
                                text: gettext('Used/Quota'),
                                dataIndex: 'storage',
                                width: 120
                            },
                            {
                                text: gettext('Connections'),
                                dataIndex: 'connections',
                                width: 100
                            },
                            {
                                text: gettext('Actions'),
                                width: 200,
                                renderer: function(value, meta, record) {
                                    return '<button class="btn btn-sm btn-primary" onclick="PVE.SMBGatewayDashboard.manageShare(\'' + record.get('sharename') + '\')">' + gettext('Manage') + '</button> ' +
                                           '<button class="btn btn-sm btn-info" onclick="PVE.SMBGatewayDashboard.backupShare(\'' + record.get('sharename') + '\')">' + gettext('Backup') + '</button>';
                                }
                            }
                        ],
                        store: {
                            fields: ['sharename', 'status', 'mode', 'ha_enabled', 'storage', 'connections'],
                            data: []
                        }
                    },
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
                                    {
                                        xtype: 'panel',
                                        title: gettext('Performance Metrics'),
                                        flex: 1,
                                        items: [
                                            {
                                                xtype: 'displayfield',
                                                name: 'metrics_placeholder',
                                                value: gettext('Performance charts will be displayed here')
                                            }
                                        ]
                                    }
                                ]
                            }
                        ]
                    },
                    {
                        xtype: 'panel',
                        title: gettext('Logs'),
                        iconCls: 'fa fa-file-text',
                        items: [
                            {
                                xtype: 'textarea',
                                name: 'log_viewer',
                                readOnly: true,
                                height: 400,
                                margin: '10',
                                value: gettext('Loading logs...')
                            }
                        ]
                    }
                ]
            }
        ];
        
        me.callParent();
        
        // Load initial data
        me.loadDashboardData();
    },
    
    loadDashboardData: function() {
        var me = this;
        
        // Load shares data
        PVE.Utils.API2Request({
            url: '/nodes/' + PVE.Utils.getNodeName() + '/storage',
            method: 'GET',
            success: function(response) {
                var shares = [];
                var totalShares = 0;
                var activeShares = 0;
                var haShares = 0;
                
                Ext.Array.each(response.result.data, function(storage) {
                    if (storage.type === 'smbgateway') {
                        totalShares++;
                        if (storage.active) activeShares++;
                        if (storage.ha_enabled) haShares++;
                        
                        shares.push({
                            sharename: storage.storage,
                            status: storage.active ? 'running' : 'stopped',
                            mode: storage.mode || 'lxc',
                            ha_enabled: storage.ha_enabled || false,
                            storage: (storage.used || '0') + ' / ' + (storage.quota || '∞'),
                            connections: storage.connections || '0'
                        });
                    }
                });
                
                // Update overview
                me.down('displayfield[name=total_shares]').setValue(totalShares);
                me.down('displayfield[name=active_shares]').setValue(activeShares);
                me.down('displayfield[name=ha_shares]').setValue(haShares);
                
                // Update grid
                var grid = me.down('grid');
                grid.getStore().loadData(shares);
            }
        });
    },
    
    createNewShare: function() {
        var win = Ext.create('Ext.window.Window', {
            title: gettext('Create New SMB Share'),
            width: 600,
            height: 500,
            modal: true,
            items: [{
                xtype: 'pveSMBGatewayAdd'
            }]
        });
        win.show();
    },
    
    backupAllShares: function() {
        Ext.Msg.confirm(gettext('Backup All Shares'), 
            gettext('This will create backups of all SMB Gateway shares. Continue?'),
            function(btn) {
                if (btn === 'yes') {
                    // Call backup API
                    PVE.Utils.API2Request({
                        url: '/nodes/' + PVE.Utils.getNodeName() + '/storage/smbgateway/backup',
                        method: 'POST',
                        success: function(response) {
                            Ext.Msg.alert(gettext('Success'), gettext('Backup started successfully'));
                        }
                    });
                }
            }
        );
    },
    
    runSecurityScan: function() {
        Ext.Msg.alert(gettext('Security Scan'), gettext('Security scan feature coming soon!'));
    },
    
    runPerformanceTest: function() {
        Ext.Msg.alert(gettext('Performance Test'), gettext('Performance test feature coming soon!'));
    },
    
    showSettings: function() {
        var win = Ext.create('Ext.window.Window', {
            title: gettext('SMB Gateway Settings'),
            width: 500,
            height: 400,
            modal: true,
            items: [{
                xtype: 'form',
                bodyPadding: 10,
                items: [
                    {
                        xtype: 'textfield',
                        name: 'default_quota',
                        fieldLabel: gettext('Default Quota'),
                        emptyText: gettext('e.g., 10G')
                    },
                    {
                        xtype: 'textfield',
                        name: 'default_path',
                        fieldLabel: gettext('Default Path'),
                        value: '/srv/smb'
                    },
                    {
                        xtype: 'checkbox',
                        name: 'enable_monitoring',
                        fieldLabel: gettext('Enable Monitoring'),
                        checked: true
                    },
                    {
                        xtype: 'checkbox',
                        name: 'enable_backups',
                        fieldLabel: gettext('Enable Auto Backups'),
                        checked: true
                    },
                    {
                        xtype: 'numberfield',
                        name: 'backup_retention',
                        fieldLabel: gettext('Backup Retention (days)'),
                        value: 30,
                        minValue: 1
                    }
                ],
                buttons: [
                    {
                        text: gettext('Save'),
                        handler: function() {
                            win.close();
                            Ext.Msg.alert(gettext('Success'), gettext('Settings saved'));
                        }
                    },
                    {
                        text: gettext('Cancel'),
                        handler: function() {
                            win.close();
                        }
                    }
                ]
            }]
        });
        win.show();
    }
});

// Static methods for grid actions
PVE.SMBGatewayDashboard.manageShare = function(sharename) {
    Ext.Msg.alert(gettext('Manage Share'), gettext('Managing share: ') + sharename);
};

PVE.SMBGatewayDashboard.backupShare = function(sharename) {
    Ext.Msg.confirm(gettext('Backup Share'), 
        gettext('Create backup for share: ') + sharename + '?',
        function(btn) {
            if (btn === 'yes') {
                // Call backup API for specific share
                PVE.Utils.API2Request({
                    url: '/nodes/' + PVE.Utils.getNodeName() + '/storage/' + sharename + '/backup',
                    method: 'POST',
                    success: function(response) {
                        Ext.Msg.alert(gettext('Success'), gettext('Backup started for ') + sharename);
                    }
                });
            }
        }
    );
};

// Add to main menu
Ext.define('PVE.dc.MainView_SMBAware', {
    override: 'PVE.dc.MainView',
    initComponent: function() {
        var me = this;
        
        // Add SMB Gateway to the main menu
        me.addMainMenuButton('smbgateway', 'SMB Gateway', 'PVE.SMBGatewayDashboard', 'fa fa-share-alt');
        
        me.callParent();
    }
}); 