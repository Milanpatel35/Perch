# Loads PerchMediaRemote.dylib into Apple's own perl and runs one of its two
# entry points. See PerchMediaRemote.m and ADR 0010.
#
#   perl perch-mediaremote.pl <path to dylib> stream
#   PERCH_COMMAND=next perl perch-mediaremote.pl <path to dylib> command
use strict;
use warnings;
use DynaLoader;

my ($library, $mode) = @ARGV;
die "usage: perch-mediaremote.pl <dylib> stream|command\n" unless $library && $mode;

my %entry = (stream => "perch_stream", command => "perch_command");
my $name = $entry{$mode} or die "unknown mode: $mode\n";

my $handle = DynaLoader::dl_load_file($library, 0)
    or die "could not load $library: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, $name)
    or die "no $name in $library\n";
DynaLoader::dl_install_xsub("main::run", $symbol);
run();
