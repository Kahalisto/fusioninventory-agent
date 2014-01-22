#!/usr/bin/perl

use strict;
use warnings;
use lib 't/lib';

use English qw(-no_match_vars);
use Test::Deep;
use Test::More;
use XML::TreePP;

use FusionInventory::Agent::Task::NetInventory;
use FusionInventory::Test::Utils;

plan tests => 15;

my ($out, $err, $rc);

($out, $err, $rc) = run_executable('fusioninventory-netinventory', '--help');
ok($rc == 0, '--help exit status');
like(
    $out,
    qr/^Usage:/,
    '--help stdout'
);
is($err, '', '--help stderr');

($out, $err, $rc) = run_executable('fusioninventory-netinventory', '--version');
ok($rc == 0, '--version exit status');
is($err, '', '--version stderr');
like(
    $out,
    qr/$FusionInventory::Agent::Task::NetInventory::VERSION/,
    '--version stdout'
);

($out, $err, $rc) = run_executable(
    'fusioninventory-netinventory',
    ''
);
ok($rc == 2, 'no target exit status');
like(
    $err,
    qr/no host nor file given, aborting/,
    'no target stderr'
);
is($out, '', 'no target stdout');

($out, $err, $rc) = run_executable(
    'fusioninventory-netinventory',
    '--file resources/walks/sample4.walk --model foobar'
);
ok($rc == 2, 'invalid model exit status');
like(
    $err,
    qr/invalid file/,
    'invalid model stderr'
);
is($out, '', 'invalid model stdout');

($out, $err, $rc) = run_executable(
    'fusioninventory-netinventory',
    '--file resources/walks/sample4.walk --model resources/models/sample1.xml'
);
ok($rc == 0, 'success exit status');

my $content = XML::TreePP->new()->parse($out);
ok($content, 'valid output');

my $result = XML::TreePP->new()->parsefile('resources/walks/sample4.result');
# expect current version
$result->{REQUEST}{CONTENT}{MODULEVERSION} =
    $FusionInventory::Agent::Task::NetInventory::VERSION;
# expect any agent id
$result->{REQUEST}{DEVICEID} = re('^\w+-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}');

cmp_deeply($content, $result, "expected output");
