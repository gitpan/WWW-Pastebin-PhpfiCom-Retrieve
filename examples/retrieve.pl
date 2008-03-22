#!/usr/bin/env perl

use strict;
use warnings;

die "Usage: perl retrieve.pl <paste_ID_or_URI>\n"
    unless @ARGV;

my $Paste = shift;

use lib '../lib';
use WWW::Pastebin::PhpfiCom::Retrieve;

my $paster = WWW::Pastebin::PhpfiCom::Retrieve->new;

my $results_ref = $paster->retrieve( $Paste )
    or die $paster->error;

printf "Paste %s was posted %s by %s, it is written in %s "
            . "and was viewed %s time(s)\n%s\n",
            $paster->uri, @$results_ref{ qw(age name lang hits content) };