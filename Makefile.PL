
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Perl module to control Onkyo/Integra AV equipment",
  "AUTHOR" => "Mark Hindess <soft-cpan\@temporalanomaly.com>",
  "BUILD_REQUIRES" => {
    "Test::More" => 0,
    "Test::Requires" => 0,
    "Test::SharedFork" => 0,
    "base" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Device-Onkyo",
  "EXE_FILES" => [
    "bin/onkyo"
  ],
  "LICENSE" => "perl",
  "NAME" => "Device::Onkyo",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Device::SerialPort" => 0,
    "Fcntl" => 0,
    "Getopt::Long" => 0,
    "IO::Select" => 0,
    "IO::Socket::INET" => 0,
    "Pod::Usage" => 0,
    "Socket" => 0,
    "Symbol" => 0,
    "Time::HiRes" => 0,
    "constant" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "1.130211",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



