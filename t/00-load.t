#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

# Test that the SMBGateway module loads correctly
BEGIN { use_ok('PVE::Storage::Custom::SMBGateway') }

# Test basic module functionality
my $module = 'PVE::Storage::Custom::SMBGateway';

# Test type method
is($module->type, 'smbgateway', 'type() returns correct storage type');

# Test plugindata method
my $plugindata = $module->plugindata;
ok(ref($plugindata) eq 'HASH', 'plugindata() returns a hash reference');
ok(exists($plugindata->{content}), 'plugindata contains content key');
ok(ref($plugindata->{content}) eq 'ARRAY', 'content is an array reference');

# Test properties method
my $properties = $module->properties;
ok(ref($properties) eq 'HASH', 'properties() returns a hash reference');
ok(exists($properties->{mode}), 'properties contains mode');
ok(exists($properties->{sharename}), 'properties contains sharename');
ok(exists($properties->{path}), 'properties contains path');

# Test that mode enum contains expected values
my $mode_enum = $properties->{mode}->{enum};
ok(ref($mode_enum) eq 'ARRAY', 'mode enum is an array reference');
ok(grep(/^native$/, @$mode_enum), 'mode enum contains native');
ok(grep(/^lxc$/, @$mode_enum), 'mode enum contains lxc');
ok(grep(/^vm$/, @$mode_enum), 'mode enum contains vm');

done_testing(); 