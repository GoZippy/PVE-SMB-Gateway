Ext.define('PVE.SMBGatewaySettings', {
    extend: 'Ext.panel.Panel',
    xtype: 'pveSMBGatewaySettings',
    
    title: gettext('SMB Gateway Settings'),
    iconCls: 'fa fa-cog',
    
    layout: 'border',
    
    initComponent: function() {
        var me = this;
        
        me.items = [
            {
                xtype: 'panel',
                region: 'west',
                width: 250,
                split: true,
                title: gettext('Settings Categories'),
                items: [
                    {
                        xtype: 'treepanel',
                        rootVisible: false,
                        useArrows: true,
                        border: false,
                        store: {
                            root: {
                                expanded: true,
                                children: [
                                    {
                                        text: gettext('General'),
                                        iconCls: 'fa fa-cog',
                                        leaf: true,
                                        id: 'general'
                                    },
                                    {
                                        text: gettext('Security'),
                                        iconCls: 'fa fa-shield',
                                        leaf: true,
                                        id: 'security'
                                    },
                                    {
                                        text: gettext('Performance'),
                                        iconCls: 'fa fa-tachometer',
                                        leaf: true,
                                        id: 'performance'
                                    },
                                    {
                                        text: gettext('Backup'),
                                        iconCls: 'fa fa-download',
                                        leaf: true,
                                        id: 'backup'
                                    },
                                    {
                                        text: gettext('Monitoring'),
                                        iconCls: 'fa fa-chart-line',
                                        leaf: true,
                                        id: 'monitoring'
                                    },
                                    {
                                        text: gettext('High Availability'),
                                        iconCls: 'fa fa-server',
                                        leaf: true,
                                        id: 'ha'
                                    },
                                    {
                                        text: gettext('Active Directory'),
                                        iconCls: 'fa fa-users',
                                        leaf: true,
                                        id: 'ad'
                                    },
                                    {
                                        text: gettext('Logging'),
                                        iconCls: 'fa fa-file-text',
                                        leaf: true,
                                        id: 'logging'
                                    }
                                ]
                            }
                        },
                        listeners: {
                            selectionchange: function(tree, selected) {
                                if (selected.length > 0) {
                                    me.showSettingsPanel(selected[0].get('id'));
                                }
                            }
                        }
                    }
                ]
            },
            {
                xtype: 'panel',
                region: 'center',
                id: 'settings-content',
                items: [
                    {
                        xtype: 'panel',
                        title: gettext('Select a category from the left menu'),
                        html: '<div style="padding: 20px; text-align: center; color: #666;">' +
                              '<i class="fa fa-arrow-left" style="font-size: 48px; margin-bottom: 20px;"></i><br>' +
                              gettext('Choose a settings category to configure') +
                              '</div>'
                    }
                ]
            }
        ];
        
        me.callParent();
    },
    
    showSettingsPanel: function(category) {
        var me = this;
        var contentPanel = me.down('#settings-content');
        
        contentPanel.removeAll();
        
        switch(category) {
            case 'general':
                contentPanel.add(me.createGeneralSettings());
                break;
            case 'security':
                contentPanel.add(me.createSecuritySettings());
                break;
            case 'performance':
                contentPanel.add(me.createPerformanceSettings());
                break;
            case 'backup':
                contentPanel.add(me.createBackupSettings());
                break;
            case 'monitoring':
                contentPanel.add(me.createMonitoringSettings());
                break;
            case 'ha':
                contentPanel.add(me.createHASettings());
                break;
            case 'ad':
                contentPanel.add(me.createADSettings());
                break;
            case 'logging':
                contentPanel.add(me.createLoggingSettings());
                break;
        }
    },
    
    createGeneralSettings: function() {
        return {
            xtype: 'form',
            title: gettext('General Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Default Values'),
                    items: [
                        {
                            xtype: 'textfield',
                            name: 'default_quota',
                            fieldLabel: gettext('Default Quota'),
                            emptyText: gettext('e.g., 10G'),
                            allowBlank: true
                        },
                        {
                            xtype: 'textfield',
                            name: 'default_path',
                            fieldLabel: gettext('Default Path'),
                            value: '/srv/smb',
                            allowBlank: false
                        },
                        {
                            xtype: 'combo',
                            name: 'default_mode',
                            fieldLabel: gettext('Default Mode'),
                            store: [['lxc','LXC'],['native','Native'],['vm','VM']],
                            value: 'lxc',
                            editable: false
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Behavior'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'auto_start_shares',
                            fieldLabel: gettext('Auto Start'),
                            boxLabel: gettext('Automatically start shares on boot'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'enable_quotas',
                            fieldLabel: gettext('Quotas'),
                            boxLabel: gettext('Enable quota enforcement'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'enable_audit',
                            fieldLabel: gettext('Audit'),
                            boxLabel: gettext('Enable audit logging'),
                            checked: true
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('general');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('general');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createSecuritySettings: function() {
        return {
            xtype: 'form',
            title: gettext('Security Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('SMB Protocol'),
                    items: [
                        {
                            xtype: 'combo',
                            name: 'smb_version',
                            fieldLabel: gettext('SMB Version'),
                            store: [['3.1.1','SMB 3.1.1'],['3.0','SMB 3.0'],['2.1','SMB 2.1']],
                            value: '3.1.1',
                            editable: false
                        },
                        {
                            xtype: 'checkbox',
                            name: 'encryption_required',
                            fieldLabel: gettext('Encryption'),
                            boxLabel: gettext('Require SMB encryption'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'signing_required',
                            fieldLabel: gettext('Signing'),
                            boxLabel: gettext('Require SMB signing'),
                            checked: true
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Access Control'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'guest_access',
                            fieldLabel: gettext('Guest Access'),
                            boxLabel: gettext('Allow guest access'),
                            checked: false
                        },
                        {
                            xtype: 'textfield',
                            name: 'allowed_hosts',
                            fieldLabel: gettext('Allowed Hosts'),
                            emptyText: gettext('e.g., 192.168.1.0/24,10.0.0.0/8'),
                            allowBlank: true
                        },
                        {
                            xtype: 'numberfield',
                            name: 'max_connections',
                            fieldLabel: gettext('Max Connections'),
                            value: 100,
                            minValue: 1,
                            maxValue: 1000
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('security');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('security');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createPerformanceSettings: function() {
        return {
            xtype: 'form',
            title: gettext('Performance Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Resource Limits'),
                    items: [
                        {
                            xtype: 'numberfield',
                            name: 'max_memory',
                            fieldLabel: gettext('Max Memory (MB)'),
                            value: 2048,
                            minValue: 512,
                            maxValue: 32768
                        },
                        {
                            xtype: 'numberfield',
                            name: 'max_cpu',
                            fieldLabel: gettext('Max CPU Cores'),
                            value: 2,
                            minValue: 1,
                            maxValue: 32
                        },
                        {
                            xtype: 'numberfield',
                            name: 'io_priority',
                            fieldLabel: gettext('I/O Priority'),
                            value: 0,
                            minValue: -20,
                            maxValue: 19
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Caching'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'enable_cache',
                            fieldLabel: gettext('File Cache'),
                            boxLabel: gettext('Enable file caching'),
                            checked: true
                        },
                        {
                            xtype: 'numberfield',
                            name: 'cache_size',
                            fieldLabel: gettext('Cache Size (MB)'),
                            value: 512,
                            minValue: 64,
                            maxValue: 8192
                        },
                        {
                            xtype: 'numberfield',
                            name: 'cache_ttl',
                            fieldLabel: gettext('Cache TTL (seconds)'),
                            value: 300,
                            minValue: 60,
                            maxValue: 3600
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('performance');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('performance');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createBackupSettings: function() {
        return {
            xtype: 'form',
            title: gettext('Backup Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Automatic Backups'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'auto_backup',
                            fieldLabel: gettext('Auto Backup'),
                            boxLabel: gettext('Enable automatic backups'),
                            checked: true
                        },
                        {
                            xtype: 'combo',
                            name: 'backup_schedule',
                            fieldLabel: gettext('Schedule'),
                            store: [['daily','Daily'],['weekly','Weekly'],['monthly','Monthly']],
                            value: 'daily',
                            editable: false
                        },
                        {
                            xtype: 'numberfield',
                            name: 'backup_retention',
                            fieldLabel: gettext('Retention (days)'),
                            value: 30,
                            minValue: 1,
                            maxValue: 365
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Backup Storage'),
                    items: [
                        {
                            xtype: 'textfield',
                            name: 'backup_path',
                            fieldLabel: gettext('Backup Path'),
                            value: '/var/lib/pve/smbgateway/backups',
                            allowBlank: false
                        },
                        {
                            xtype: 'checkbox',
                            name: 'compress_backups',
                            fieldLabel: gettext('Compression'),
                            boxLabel: gettext('Compress backup files'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'encrypt_backups',
                            fieldLabel: gettext('Encryption'),
                            boxLabel: gettext('Encrypt backup files'),
                            checked: false
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('backup');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('backup');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createMonitoringSettings: function() {
        return {
            xtype: 'form',
            title: gettext('Monitoring Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Metrics Collection'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'enable_metrics',
                            fieldLabel: gettext('Metrics'),
                            boxLabel: gettext('Enable metrics collection'),
                            checked: true
                        },
                        {
                            xtype: 'numberfield',
                            name: 'metrics_interval',
                            fieldLabel: gettext('Collection Interval (seconds)'),
                            value: 60,
                            minValue: 30,
                            maxValue: 300
                        },
                        {
                            xtype: 'numberfield',
                            name: 'metrics_retention',
                            fieldLabel: gettext('Retention (days)'),
                            value: 90,
                            minValue: 1,
                            maxValue: 365
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Alerts'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'enable_alerts',
                            fieldLabel: gettext('Alerts'),
                            boxLabel: gettext('Enable alert notifications'),
                            checked: true
                        },
                        {
                            xtype: 'numberfield',
                            name: 'quota_alert_threshold',
                            fieldLabel: gettext('Quota Alert Threshold (%)'),
                            value: 80,
                            minValue: 50,
                            maxValue: 95
                        },
                        {
                            xtype: 'textfield',
                            name: 'alert_email',
                            fieldLabel: gettext('Alert Email'),
                            emptyText: gettext('admin@example.com'),
                            allowBlank: true
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('monitoring');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('monitoring');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createHASettings: function() {
        return {
            xtype: 'form',
            title: gettext('High Availability Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('CTDB Configuration'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'ha_enabled',
                            fieldLabel: gettext('HA Enabled'),
                            boxLabel: gettext('Enable high availability'),
                            checked: false
                        },
                        {
                            xtype: 'textfield',
                            name: 'ctdb_vip',
                            fieldLabel: gettext('CTDB VIP'),
                            emptyText: gettext('e.g., 192.168.1.100'),
                            allowBlank: true
                        },
                        {
                            xtype: 'textfield',
                            name: 'ha_nodes',
                            fieldLabel: gettext('HA Nodes'),
                            emptyText: gettext('Comma-separated node names'),
                            allowBlank: true
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Failover'),
                    items: [
                        {
                            xtype: 'numberfield',
                            name: 'failover_timeout',
                            fieldLabel: gettext('Failover Timeout (seconds)'),
                            value: 30,
                            minValue: 10,
                            maxValue: 300
                        },
                        {
                            xtype: 'checkbox',
                            name: 'auto_failback',
                            fieldLabel: gettext('Auto Failback'),
                            boxLabel: gettext('Automatically failback when possible'),
                            checked: true
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('ha');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('ha');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createADSettings: function() {
        return {
            xtype: 'form',
            title: gettext('Active Directory Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Domain Configuration'),
                    items: [
                        {
                            xtype: 'textfield',
                            name: 'ad_domain',
                            fieldLabel: gettext('Domain'),
                            emptyText: gettext('e.g., example.com'),
                            allowBlank: true
                        },
                        {
                            xtype: 'textfield',
                            name: 'ad_servers',
                            fieldLabel: gettext('Domain Controllers'),
                            emptyText: gettext('e.g., dc1.example.com,dc2.example.com'),
                            allowBlank: true
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Authentication'),
                    items: [
                        {
                            xtype: 'checkbox',
                            name: 'ad_kerberos',
                            fieldLabel: gettext('Kerberos'),
                            boxLabel: gettext('Use Kerberos authentication'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'ad_fallback',
                            fieldLabel: gettext('Local Fallback'),
                            boxLabel: gettext('Allow local authentication fallback'),
                            checked: true
                        },
                        {
                            xtype: 'numberfield',
                            name: 'ad_timeout',
                            fieldLabel: gettext('Timeout (seconds)'),
                            value: 30,
                            minValue: 5,
                            maxValue: 300
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('ad');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('ad');
                    },
                    scope: this
                }
            ]
        };
    },
    
    createLoggingSettings: function() {
        return {
            xtype: 'form',
            title: gettext('Logging Settings'),
            bodyPadding: 20,
            items: [
                {
                    xtype: 'fieldset',
                    title: gettext('Log Levels'),
                    items: [
                        {
                            xtype: 'combo',
                            name: 'log_level',
                            fieldLabel: gettext('Log Level'),
                            store: [['debug','Debug'],['info','Info'],['warning','Warning'],['error','Error']],
                            value: 'info',
                            editable: false
                        },
                        {
                            xtype: 'checkbox',
                            name: 'log_smb',
                            fieldLabel: gettext('SMB Logs'),
                            boxLabel: gettext('Log SMB protocol details'),
                            checked: true
                        },
                        {
                            xtype: 'checkbox',
                            name: 'log_audit',
                            fieldLabel: gettext('Audit Logs'),
                            boxLabel: gettext('Log access and security events'),
                            checked: true
                        }
                    ]
                },
                {
                    xtype: 'fieldset',
                    title: gettext('Log Rotation'),
                    items: [
                        {
                            xtype: 'numberfield',
                            name: 'log_max_size',
                            fieldLabel: gettext('Max Size (MB)'),
                            value: 100,
                            minValue: 10,
                            maxValue: 1000
                        },
                        {
                            xtype: 'numberfield',
                            name: 'log_keep_days',
                            fieldLabel: gettext('Keep Days'),
                            value: 30,
                            minValue: 1,
                            maxValue: 365
                        },
                        {
                            xtype: 'checkbox',
                            name: 'log_compress',
                            fieldLabel: gettext('Compress'),
                            boxLabel: gettext('Compress rotated logs'),
                            checked: true
                        }
                    ]
                }
            ],
            buttons: [
                {
                    text: gettext('Save'),
                    handler: function() {
                        this.saveSettings('logging');
                    },
                    scope: this
                },
                {
                    text: gettext('Reset'),
                    handler: function() {
                        this.resetSettings('logging');
                    },
                    scope: this
                }
            ]
        };
    },
    
    saveSettings: function(category) {
        var form = this.down('form');
        var values = form.getValues();
        
        PVE.Utils.API2Request({
            url: '/nodes/' + PVE.Utils.getNodeName() + '/storage/smbgateway/settings/' + category,
            method: 'POST',
            params: values,
            success: function(response) {
                Ext.Msg.alert(gettext('Success'), gettext('Settings saved successfully'));
            },
            failure: function(response) {
                Ext.Msg.alert(gettext('Error'), gettext('Failed to save settings'));
            }
        });
    },
    
    resetSettings: function(category) {
        Ext.Msg.confirm(gettext('Reset Settings'), 
            gettext('Are you sure you want to reset all settings for this category?'),
            function(btn) {
                if (btn === 'yes') {
                    // Reset form to defaults
                    var form = this.down('form');
                    form.reset();
                }
            },
            this
        );
    }
}); 