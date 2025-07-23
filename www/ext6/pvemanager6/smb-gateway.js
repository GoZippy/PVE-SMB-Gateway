Ext.define('PVE.SMBGatewayAdd', {
    extend: 'PVE.panel.InputPanel',
    xtype: 'pveSMBGatewayAdd',

    initComponent: function() {
        var me = this;

        me.column1 = [
            {
                xtype: 'textfield',
                name: 'sharename',
                fieldLabel: gettext('Share Name'),
                allowBlank: false,
                regex: /^[a-zA-Z0-9_-]+$/,
                regexText: gettext('Only letters, numbers, underscores, and hyphens allowed')
            },
            {
                xtype: 'combo',
                name: 'mode',
                fieldLabel: gettext('Mode'),
                store: [['lxc','LXC (Recommended)'],['native','Native Host'],['vm','VM']],
                value: 'lxc',
                editable: false,
                listeners: {
                    change: function(field, newValue, oldValue) {
                        var vmFields = ['vm_memory', 'vm_cores', 'vm_template'];
                        var form = field.up('form');
                        
                        vmFields.forEach(function(fieldName) {
                            var vmField = form.down('field[name=' + fieldName + ']');
                            if (vmField) {
                                vmField.setVisible(newValue === 'vm');
                                vmField.setDisabled(newValue !== 'vm');
                            }
                        });
                        
                        // Update info field
                        var infoField = form.down('displayfield[name=info]');
                        if (infoField) {
                            if (newValue === 'lxc') {
                                infoField.setValue(gettext('LXC mode creates lightweight containers with minimal resource usage.'));
                            } else if (newValue === 'native') {
                                infoField.setValue(gettext('Native mode installs Samba directly on the host. Simple but less isolated.'));
                            } else if (newValue === 'vm') {
                                infoField.setValue(gettext('VM mode creates dedicated virtual machines with complete isolation. Higher resource usage.'));
                            }
                        }
                    }
                }
            },
            {
                xtype: 'textfield',
                name: 'path',
                fieldLabel: gettext('Path'),
                allowBlank: true,
                emptyText: gettext('Auto-generated from share name')
            },
            {
                xtype: 'textfield',
                name: 'quota',
                fieldLabel: gettext('Quota'),
                allowBlank: true,
                emptyText: gettext('e.g., 10G, 1T'),
                regex: /^(\d+[GT])?$/,
                regexText: gettext('Format: number followed by G or T (e.g., 10G, 1T)')
            }
        ];

        me.column2 = [
            {
                xtype: 'fieldcontainer',
                fieldLabel: gettext('Active Directory'),
                layout: 'hbox',
                items: [
                    {
                        xtype: 'textfield',
                        name: 'ad_domain',
                        flex: 1,
                        emptyText: gettext('e.g., example.com'),
                        allowBlank: true,
                        margin: '0 10 0 0',
                        listeners: {
                            change: function(field, newValue) {
                                var form = field.up('form');
                                var adJoinField = form.down('field[name=ad_join]');
                                var adFields = ['ad_username', 'ad_password', 'ad_ou'];
                                
                                if (adJoinField) {
                                    adJoinField.setDisabled(!newValue);
                                    if (!newValue) {
                                        adJoinField.setValue(false);
                                    }
                                }
                                
                                adFields.forEach(function(fieldName) {
                                    var adField = form.down('field[name=' + fieldName + ']');
                                    if (adField) {
                                        adField.setDisabled(!newValue || !adJoinField.getValue());
                                    }
                                });
                            }
                        }
                    },
                    {
                        xtype: 'checkbox',
                        name: 'ad_join',
                        boxLabel: gettext('Join Domain'),
                        disabled: true,
                        margin: '0 0 0 0',
                        listeners: {
                            change: function(field, newValue) {
                                var form = field.up('form');
                                var adFields = ['ad_username', 'ad_password', 'ad_ou', 'ad_fallback'];
                                
                                adFields.forEach(function(fieldName) {
                                    var adField = form.down('field[name=' + fieldName + ']');
                                    if (adField) {
                                        adField.setDisabled(!newValue);
                                    }
                                });
                            }
                        }
                    }
                ]
            },
            {
                xtype: 'textfield',
                name: 'ad_username',
                fieldLabel: gettext('AD Username'),
                allowBlank: true,
                disabled: true,
                value: 'Administrator',
                emptyText: gettext('e.g., Administrator')
            },
            {
                xtype: 'textfield',
                name: 'ad_password',
                fieldLabel: gettext('AD Password'),
                allowBlank: true,
                disabled: true,
                inputType: 'password'
            },
            {
                xtype: 'textfield',
                name: 'ad_ou',
                fieldLabel: gettext('AD OU'),
                allowBlank: true,
                disabled: true,
                emptyText: gettext('e.g., OU=Servers,DC=example,DC=com')
            },
            {
                xtype: 'checkbox',
                name: 'ad_fallback',
                fieldLabel: gettext('AD Fallback'),
                disabled: true,
                checked: true,
                boxLabel: gettext('Enable local authentication fallback')
            },
            {
                xtype: 'fieldcontainer',
                fieldLabel: gettext('High Availability'),
                layout: 'hbox',
                items: [
                    {
                        xtype: 'checkbox',
                        name: 'ha_enabled',
                        boxLabel: gettext('Enable HA'),
                        value: false,
                        margin: '0 10 0 0',
                        listeners: {
                            change: function(field, newValue) {
                                var form = field.up('form');
                                var vipField = form.down('field[name=ctdb_vip]');
                                var nodesField = form.down('field[name=ha_nodes]');
                                
                                if (vipField) {
                                    vipField.setDisabled(!newValue);
                                }
                                if (nodesField) {
                                    nodesField.setDisabled(!newValue);
                                }
                            }
                        }
                    }
                ]
            },
            {
                xtype: 'textfield',
                name: 'ctdb_vip',
                fieldLabel: gettext('CTDB VIP'),
                allowBlank: true,
                disabled: true,
                emptyText: gettext('e.g., 192.168.1.100 or auto'),
                regex: /^(auto|(\d{1,3}\.){3}\d{1,3})$/,
                regexText: gettext('Valid IP address or "auto" required'),
                listeners: {
                    afterrender: function(field) {
                        var form = field.up('form');
                        var haField = form.down('field[name=ha_enabled]');
                        field.setDisabled(!haField || !haField.getValue());
                    }
                }
            },
            {
                xtype: 'textfield',
                name: 'ha_nodes',
                fieldLabel: gettext('HA Nodes'),
                allowBlank: true,
                disabled: true,
                emptyText: gettext('Comma-separated node names or "all"'),
                listeners: {
                    afterrender: function(field) {
                        var form = field.up('form');
                        var haField = form.down('field[name=ha_enabled]');
                        field.setDisabled(!haField || !haField.getValue());
                    }
                }
            },
            {
                xtype: 'numberfield',
                name: 'vm_memory',
                fieldLabel: gettext('VM Memory (MB)'),
                minValue: 512,
                maxValue: 65536,
                value: 2048,
                allowBlank: false,
                hidden: true,
                disabled: true
            },
            {
                xtype: 'numberfield',
                name: 'vm_cores',
                fieldLabel: gettext('VM Cores'),
                minValue: 1,
                maxValue: 64,
                value: 2,
                allowBlank: false,
                hidden: true,
                disabled: true
            },
            {
                xtype: 'textfield',
                name: 'vm_template',
                fieldLabel: gettext('VM Template'),
                allowBlank: true,
                emptyText: gettext('Auto-detect or create'),
                hidden: true,
                disabled: true
            },
            {
                xtype: 'displayfield',
                name: 'info',
                fieldLabel: gettext('Info'),
                value: gettext('LXC mode creates lightweight containers with minimal resource usage.')
            }
        ];

        me.callParent();
    },

    onGetValues: function(values) {
        var me = this;
        
        // Set default path if not provided
        if (!values.path) {
            values.path = '/srv/smb/' + values.sharename;
        }
        
        // Validate quota format
        if (values.quota && !values.quota.match(/^\d+[GT]$/)) {
            Ext.Msg.alert(gettext('Error'), gettext('Invalid quota format. Use format like 10G or 1T.'));
            return false;
        }
        
        // Handle HA configuration
        if (values.ha_enabled) {
            // If HA is enabled but no VIP is specified, use 'auto'
            if (!values.ctdb_vip) {
                values.ctdb_vip = 'auto';
            }
            
            // Store HA nodes if specified
            if (values.ha_nodes) {
                // Convert comma-separated list to array if needed
                if (values.ha_nodes !== 'all' && values.ha_nodes.indexOf(',') !== -1) {
                    var nodeList = values.ha_nodes.split(',').map(function(node) {
                        return node.trim();
                    }).filter(function(node) {
                        return node !== '';
                    });
                    values.ha_nodes = nodeList.join(',');
                }
            } else {
                // Default to 'all' if no nodes specified
                values.ha_nodes = 'all';
            }
        } else {
            // If HA is disabled, clear HA-related fields
            delete values.ctdb_vip;
            delete values.ha_nodes;
        }
        
        // Handle AD domain configuration
        if (values.ad_domain) {
            if (values.ad_join) {
                // Validate AD join parameters
                if (!values.ad_password) {
                    Ext.Msg.alert(gettext('Error'), gettext('AD password is required for domain join.'));
                    return false;
                }
            } else {
                // If not joining domain, clear AD join-related fields
                delete values.ad_username;
                delete values.ad_password;
                delete values.ad_ou;
            }
        } else {
            // If no AD domain, clear all AD-related fields
            delete values.ad_join;
            delete values.ad_username;
            delete values.ad_password;
            delete values.ad_ou;
        }
        
        // Validate VM-specific parameters if VM mode is selected
        if (values.mode === 'vm') {
            // Validate VM memory
            if (!values.vm_memory || values.vm_memory < 512) {
                values.vm_memory = 2048; // Default to 2GB if not specified or too small
            }
            
            // Validate VM cores
            if (!values.vm_cores || values.vm_cores < 1) {
                values.vm_cores = 2; // Default to 2 cores if not specified or invalid
            }
            
            // VM template is optional, will be auto-detected if not specified
        }
        
        return values;
    }
});

// Inject into storage add menu
Ext.define('PVE.dc.StorageView_SMBAware', {
    override: 'PVE.dc.StorageView',
    initComponent: function() {
        var me = this;
        me.addAddButton('smbgateway', 'SMB Gateway', 'PVE.SMBGatewayAdd');
        me.callParent();
    }
});
