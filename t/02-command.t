#!#!/usr/bin/perl
#
# Copyright (C) 2012 by Mark Hindess

use strict;
use constant {
  DEBUG => $ENV{DEVICE_ONKYO_TEST_DEBUG}
};
use Test::More tests => 11;

{
  package My::Onkyo;
  use base 'Device::Onkyo';
  sub write {
    my $self = shift;
    push @{$self->{_calls}}, \@_;
    1;
  }
  sub calls {
    my $self = shift;
    delete $self->{_calls};
  }
  1;
}

my $log = '/dev/null';
open my $fh, $log or die "Failed to open $log: $!\n";

my $onkyo = My::Onkyo->new(filehandle => $fh);
ok $onkyo, 'object created';

my $cb = sub {};
$onkyo->volume('up' => $cb);
is_deeply $onkyo->calls, [['MVLUP', $cb]], '... volume up';

$onkyo->volume('down' => $cb);
is_deeply $onkyo->calls, [['MVLDOWN', $cb]], '... volume down';

$onkyo->volume('?' => $cb);
is_deeply $onkyo->calls, [['MVLQSTN', $cb]], '... volume query';

$onkyo->volume(100 => $cb);
is_deeply $onkyo->calls, [['MVL64', $cb]], '... volume 100%';

$onkyo->volume('10%' => $cb);
is_deeply $onkyo->calls, [['MVL0a', $cb]], '... volume 10%';

eval { $onkyo->volume('110%') };
like $@, qr!^volume: argument should be up/down/percentage/\? not '110%'!,
  '... volume error';

$onkyo->power(on => $cb);
is_deeply $onkyo->calls, [['PWR01', $cb]], '... power on';

$onkyo->power(off => $cb);
is_deeply $onkyo->calls, [['PWR00', $cb]], '... power off';

$onkyo->power(qstn => $cb);
is_deeply $onkyo->calls, [['PWRQSTN', $cb]], '... power query';

eval { $onkyo->power('up') };
like $@, qr!^power: argument should be on/off/\? not 'up'!, '... power error';
