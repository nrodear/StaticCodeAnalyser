#!/usr/bin/perl
# Einmal-Skript: biegt 'in sources\Folder\unit.pas' im Form-dpr auf
# Engine-Pfade um. Ausnahmen: uIDEColors, uRecentPaths bleiben lokal.
use strict;
use warnings;

my $file = shift @ARGV or die "usage: $0 <dpr-file>\n";
open my $fh, '<', $file or die "cannot read $file: $!";
local $/;
my $c = <$fh>;
close $fh;

# Mass-replace fuer alle Engine-Folder
for my $sub (qw(Detectors Parsing Infrastructure Output Common)) {
    my $old = "in 'sources\\$sub\\";
    my $new = "in '..\\SCA.Engine\\sources\\$sub\\";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $sub: $n replaced\n" if $n;
}
# uLocalization + uAnalyserTypes wanderten von UI nach Engine\Common
for my $special (qw(uLocalization uAnalyserTypes)) {
    my $old = "in 'sources\\UI\\$special.pas'";
    my $new = "in '..\\SCA.Engine\\sources\\Common\\$special.pas'";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $special: $n replaced\n" if $n;
}
# Ausnahmen zurueck: uIDEColors + uRecentPaths bleiben lokal
for my $keep (qw(uIDEColors uRecentPaths)) {
    my $bad = "in '..\\SCA.Engine\\sources\\Common\\$keep.pas'";
    my $good = "in 'sources\\Common\\$keep.pas'";
    my $n = () = $c =~ /\Q$bad\E/g;
    $c =~ s/\Q$bad\E/$good/g;
    print "  restored $keep: $n\n" if $n;
}

open my $out, '>', $file or die "cannot write $file: $!";
print $out $c;
close $out;
print "wrote $file\n";
