#!/usr/bin/perl
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
# Adapted from Vorssaint 794608a Resources/now-playing.pl for Tinycast's watch entry point.
use strict;
use warnings;
use DynaLoader;

$| = 1;
my ($library, $mode) = @ARGV;
die "usage: now-playing.pl <adapter library> watch\n"
    unless defined $library && -f $library && defined $mode && $mode eq 'watch';
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "now-playing: cannot load adapter: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, 'tinycast_now_playing_watch')
    or die "now-playing: adapter entry point missing: " . DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub('main::tinycast_now_playing_run', $symbol);
tinycast_now_playing_run();
