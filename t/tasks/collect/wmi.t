#!/usr/bin/perl

use strict;
use warnings;
use lib 't/lib';

use English qw(-no_match_vars);
use Test::Deep qw(cmp_deeply);
use Test::More;
use Test::MockModule;

use FusionInventory::Test::Utils;
use FusionInventory::Agent::Task::Collect;

# use mock modules for non-available ones
if ($OSNAME eq 'MSWin32') {
    push @INC, 't/lib/fake/unix';
} else {
    push @INC, 't/lib/fake/windows';
}

plan tests => 2;

my @results = FusionInventory::Agent::Task::Collect::_getFromWMI(
    class      => 'nowhere',
    properties => [ 'nothing' ]
);
ok(!@results, "_getFromWMI ignores missing WMI object");

my %tests = (
    7 => [
        {
            'Description' => 'WAN Miniport (SSTP)',
            'Index' => '0',
            'IPEnabled' => 'FALSE'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '1',
            'Description' => 'WAN Miniport (IKEv2)'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '2',
            'Description' => 'WAN Miniport (L2TP)'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '3',
            'Description' => 'WAN Miniport (PPTP)'
        },
        {
            'Description' => 'WAN Miniport (PPPOE)',
            'IPEnabled' => 'FALSE',
            'Index' => '4'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '5',
            'Description' => 'WAN Miniport (IPv6)'
        },
        {
            'Index' => '6',
            'IPEnabled' => 'FALSE',
            'Description' => 'WAN Miniport (Network Monitor)'
        },
        {
            'IPEnabled' => 'TRUE',
            'Index' => '7',
            'Description' => 'Realtek PCIe GBE Family Controller'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '8',
            'Description' => 'WAN Miniport (IP)'
        },
        {
            'Description' => 'Carte Microsoft ISATAP',
            'Index' => '9',
            'IPEnabled' => 'FALSE'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '10',
            'Description' => 'RAS Async Adapter'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '11',
            'Description' => 'Microsoft Teredo Tunneling Adapter'
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '12',
            'Description' => "P\x{e9}riph\x{e9}rique Bluetooth (r\x{e9}seau personnel)"
        },
        {
            'IPEnabled' => 'FALSE',
            'Index' => '13',
            'Description' => 'Carte Microsoft ISATAP'
        }
    ]
);

my $module = Test::MockModule->new(
    'FusionInventory::Agent::Tools::Win32'
);

foreach my $test (keys %tests) {
    $module->mock(
        'getWMIObjects',
        mockGetWMIObjects($test)
    );

    my @wmiResult = FusionInventory::Agent::Task::Collect::_getFromWMI(
        class      => 'Win32_NetworkAdapterConfiguration',
        properties => [ qw/Index Description IPEnabled/  ]
    );
    cmp_deeply(
        \@wmiResult,
        $tests{$test},
        "WMI query"
    );
}

