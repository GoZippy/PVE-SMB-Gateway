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
                store: [['lxc','LXC (Recommended)'],['native','Native Host'],['vm','VM (Coming Soon)']],
                value: 'lxc',
                editable: false
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
                xtype: 'textfield',
                name: 'ad_domain',
                fieldLabel: gettext('AD Domain'),
                allowBlank: true,
                emptyText: gettext('e.g., example.com')
            },
            {
                xtype: 'textfield',
                name: 'ctdb_vip',
                fieldLabel: gettext('CTDB VIP'),
                allowBlank: true,
                emptyText: gettext('e.g., 192.168.1.100'),
                regex: /^(\d{1,3}\.){3}\d{1,3}$/,
                regexText: gettext('Valid IP address required')
            },
            {
                xtype: 'displayfield',
                name: 'info',
                fieldLabel: gettext('Info'),
                value: gettext('LXC mode creates lightweight containers. Native mode installs Samba directly on the host.')
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
