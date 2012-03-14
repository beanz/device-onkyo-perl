#!/usr/bin/perl
#
# Copyright (C) 2012 by Mark Hindess

use strict;
use constant {
  DEBUG => $ENV{DEVICE_ONKYO_TEST_DEBUG}
};
use Test::More tests => 13;

use_ok 'Device::Onkyo';

my $log = 't/log/simple.log';
open my $fh, $log or die "Failed to open $log: $!\n";

my $onkyo = Device::Onkyo->new(filehandle => $fh, type => 'ISCP');
ok $onkyo, 'object created';

my $msg = $onkyo->read;
ok $msg, '... reading';
my ($command, $arg) = @$msg;
is $command, 'PWR', '... power';
is $arg, '01', '... power on';

$msg = $onkyo->read;
ok $msg, '... reading';
($command, $arg) = @$msg;
is $command, 'PWR', '... power';
is $arg, '00', '... power off';

eval { $onkyo->read };
like $@, qr/^closed /, '... closed';

$onkyo->{type} = 'eISCP';
$onkyo->{_buf} =
  pack 'A4 N N C4 A*', 'ISCP', 0x10, 0x08, 0x1, 0x0, 0x0, 0x0, "!1PWR01\n";

$msg = $onkyo->read;
ok $msg, '... reading nothing';
($command, $arg) = @$msg;
is $command, 'PWR', '... power';
is $arg, '01', '... power on';

eval { Device::Onkyo->new() };
like $@, qr/^Device::Onkyo->new: 'device' parameter is required /,
  'device is required';
