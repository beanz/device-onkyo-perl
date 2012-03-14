use strict;
use warnings;
package Device::Onkyo;

use Carp qw/croak carp/;
use Device::SerialPort qw/:PARAM :STAT 0.07/;
use Fcntl;
use IO::Select;
use Socket;
use Symbol qw(gensym);
use Time::HiRes;

use constant {
  DEBUG => $ENV{DEVICE_ONKYO_DEBUG},
};

# ABSTRACT: To control Onkyo/Intregra AV equipment

=head1 SYNOPSIS

  my $onkyo = Device::Onkyo->new(device => '/dev/ttyS0');
  $onkyo->write('PWR01'); # switch on
  while (1) {
    my $message = $onkyo->read();
    print $message, "\n";
  }

  $onkyo = Device::Onkyo->new(device => 'hostname:port');
  $onkyo->write('PWR01'); # switch on

  $onkyo = Device::Onkyo->new(device => 'discover');
  $onkyo->write('PWR01'); # switch on

=head1 DESCRIPTION

Module for controlling Onkyo/Intregra AV equipment.

B<IMPORTANT:> This is an early release and the API is still subject to
change. The serial port usage is entirely untested.

=cut

sub new {
  my ($pkg, %p) = @_;
  my $self = bless {
                    _buf => '',
                    _q => [],
                    type => 'eISCP',
                    port => 60128,
                    baud => 9600,
                    discard_timeout => 1,
                    %p
                   }, $pkg;
  unless (exists $p{filehandle}) {
    croak $pkg.q{->new: 'device' parameter is required}
      unless (exists $p{device});
    $self->_open();
  }
  $self;
}

sub baud { shift->{baud} }

sub port { shift->{port} }

sub filehandle { shift->{filehandle} }

sub _open {
  my $self = shift;
  if ($self->{device} =~ m![/\\]!) {
    $self->_open_serial_port(@_);
  } else {
    if ($self->{device} eq 'discover') {
      $self->{device} = $self->discover;
    }
    $self->_open_tcp_port(@_);
  }
}

sub _open_tcp_port {
  my $self = shift;
  my $dev = $self->{device};
  print STDERR "Opening $dev as tcp socket\n" if DEBUG;
  require IO::Socket::INET; import IO::Socket::INET;
  if ($dev =~ s/:(\d+)$//) {
    $self->{port} = $1;
  }
  my $fh = IO::Socket::INET->new($dev.':'.$self->port) or
    croak "TCP connect to '$dev' failed: $!";
  return $self->{filehandle} = $fh;
}

sub _open_serial_port {
  my $self = shift;
  $self->{type} = 'ISCP';
  my $fh = gensym();
  my $s = tie (*$fh, 'Device::SerialPort', $self->{device}) ||
    croak "Could not tie serial port to file handle: $!\n";
  $s->baudrate($self->baud);
  $s->databits(8);
  $s->parity("none");
  $s->stopbits(1);
  $s->datatype("raw");
  $s->write_settings();

  sysopen($fh, $self->{device}, O_RDWR|O_NOCTTY|O_NDELAY) or
    croak "open of '".$self->{device}."' failed: $!\n";
  $fh->autoflush(1);
  return $self->{filehandle} = $fh;
}

sub read {
  my ($self, $timeout) = @_;
  my $res = $self->read_one(\$self->{_buf});
  return $res if (defined $res);
  $self->_discard_buffer_check(\$self->{_buf}) if ($self->{_buf} ne '');
  my $fh = $self->filehandle;
  my $sel = IO::Select->new($fh);
  do {
    my $start = $self->_time_now;
    $sel->can_read($timeout) or return;
    my $bytes = sysread $fh, $self->{_buf}, 2048, length $self->{_buf};
    $self->{_last_read} = $self->_time_now;
    $timeout -= $self->{_last_read} - $start if (defined $timeout);
    croak defined $bytes ? 'closed' : 'error: '.$! unless ($bytes);
    $res = $self->read_one(\$self->{_buf});
    $self->_write_now() if (defined $res);
    return $res if (defined $res);
  } while (1);
}

sub read_one {
  my ($self, $rbuf) = @_;
  return unless ($$rbuf);

  print STDERR "rbuf=", (unpack "H*", $$rbuf), "\n" if DEBUG;

  if ($self->{type} eq 'eISCP') {
    my $length = length $$rbuf;
    return unless ($length >= 16);
    my ($magic, $header_size,
        $data_size, $version, $res1, $res2, $res3) = unpack 'a4 N N C4', $$rbuf;
    croak "Unexpected magic: expected 'ISCP', got '$magic'\n"
      unless ($magic eq 'ISCP');
    return unless ($length >= $header_size+$data_size);
    substr $$rbuf, 0, $header_size, '';
    carp(sprintf "Unexpected version: expected '0x01', got '0x%02x'\n",
                 $version) unless ($version == 0x01);
    carp(sprintf "Unexpected header size: expected '0x10', got '0x%02x'\n",
                 $header_size) unless ($header_size == 0x10);
    my $body = substr $$rbuf, 0, $data_size, '';
    my $sd = substr $body, 0, 2, '';
    my $command = substr $body, 0, 3, '';
    $body =~ s/[\032\r\n]+$//;
    carp "Unexpected start/destination: expected '!1', got '$sd'\n"
      unless ($sd eq '!1');
    $self->_write_now;
    return [ $command, $body ];
  } else {
    return unless ($$rbuf =~ s/^(..)(...)(.*?)[\032\r\n]+//);
    my ($sd, $command, $body) = ($1, $2, $3);
    carp "Unexpected start/destination: expected '!1', got '$sd'\n"
      unless ($sd eq '!1');
    $self->_write_now;
    return [ $command, $body ];
  }
}

sub _time_now {
  Time::HiRes::time
}

# 4953 4350 0000 0010 0000 000b 0100 0000  ISCP............
# 2178 4543 4e51 5354 4e0d 0a              !xECNQSTN\r\n

sub discover {
  my $self = shift;
  my $s;
  socket $s, PF_INET, SOCK_DGRAM, getprotobyname('udp');
  setsockopt $s, SOL_SOCKET, SO_BROADCAST, 1;
  binmode $s;
  bind $s, sockaddr_in(0, inet_aton('0.0.0.0'));
  send($s,
       pack("a* N N N a*",
            'ISCP', 0x10, 0xb, 0x01000000, "!xECNQSTN\r\n"),
       0,
       sockaddr_in($self->port, inet_aton('255.255.255.255')));
  my $sel = IO::Select->new($s);
  $sel->can_read(10) or die;
  my $sender = recv $s, my $buf, 2048, 0;
  croak 'error: '.$! unless (defined $sender);

  my ($port, $addr) = sockaddr_in($sender);
  my $ip = inet_ntoa($addr);
  my $b = $buf;
  my $msg = $self->read_one(\$b);
  my ($cmd, $arg) = @$msg;
  ($port) = ($arg =~ m!/(\d{5})/../[0-9a-f]{12}$!i);
  print STDERR "discovered: $ip:$port (@$msg)\n" if DEBUG;
  $self->{port} = $port;
  return $ip.':'.$port;
}

sub write {
  my $self = shift;
  push @{$self->{_q}}, \@_;
  $self->_write_now unless ($self->{_waiting});
  1;
}

sub _write_now {
  my $self = shift;
  my $rec = shift @{$self->{_q}};
  my $wait_rec = delete $self->{_waiting};
  if ($wait_rec) {
    $wait_rec->[1]->() if ($wait_rec->[1]);
  }
  return unless (defined $rec);
  $self->_real_write($rec);
  $self->{waiting} = [ $self->_time_now, $rec ];
}

sub _real_write {
  my ($self, $rec) = @_;
  my $str = $self->pack(@$rec);
  print STDERR "sending: ", (unpack "H*", $str), "\n" if DEBUG;
  syswrite $self->filehandle, $str, length $str;
}

sub pack {
  my $self = shift;
  my $d = '!1'.$_[0];
  if ($self->{type} eq 'eISCP') {
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 4d56 4c32 381a 0d0a                !1MVL28...
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 4d56 4c32 381a 0d0a
    $d .= "\r";
    pack("a* N N N a*",
         'ISCP', 0x10, (length $d), 0x01000000, $d);
  } else {
    $d .= "\r\n";
  }
}

sub volume {
  my ($self, $percent, $cb) = @_;
  if ($percent =~ /^(?:up|\+)$/i) {
    $self->write('MVLUP' => $cb);
  } elsif ($percent =~ /^(?:down|-)$/i) {
    $self->write('MVLDOWN' => $cb);
  } elsif ($percent =~ /^(100|[0-9][0-9]?)%?$/) {
    my $cmd = sprintf 'MVL%02x', $1;
    $self->write($cmd => $cb);
  } elsif ($percent =~ /^(?:QSTN|\?)$/i) {
    $self->write('MVLQSTN' => $cb);
  } else {
    croak "volume: argument should be up/down/percentage/? not '$percent'";
  }
}

sub power {
  my ($self, $cmd, $cb) = @_;
  my $str = { on => '01', off => '00',
              '?' => 'QSTN', qstn => 'QSTN' }->{lc $cmd};
  if (defined $str) {
    $self->write('PWR'.$str => $cb);
  } else {
    croak "power: argument should be on/off/? not '$cmd'";
  }
}

1;
