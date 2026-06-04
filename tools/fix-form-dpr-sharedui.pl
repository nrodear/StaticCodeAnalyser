#!/usr/bin/perl
# Einmal-Skript fuer SharedUI-Sprint Schritt 6: biegt die 10
# UI/Common-Refs im Form-dpr von 'sources\UI\X.pas' und
# 'sources\Common\X.pas' auf '..\SCA.SharedUI\sources\X.pas' um.
use strict;
use warnings;

my $file = shift @ARGV or die "usage: $0 <dpr-file>\n";
open my $fh, '<', $file or die "cannot read $file: $!";
local $/;
my $c = <$fh>;
close $fh;

my @units_ui     = qw(uAnalyserPalette uAnalyserTheme uFindingGridRenderer uFindingFilter uIDEStatsTiles uIDEHelpPanel uIDEToolbar uExportMenu);
my @units_common = qw(uIDEColors uRecentPaths);

for my $u (@units_ui) {
    my $old = "in 'sources\\UI\\$u.pas'";
    my $new = "in '..\\SCA.SharedUI\\sources\\$u.pas'";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $u: $n replaced\n" if $n;
}
for my $u (@units_common) {
    my $old = "in 'sources\\Common\\$u.pas'";
    my $new = "in '..\\SCA.SharedUI\\sources\\$u.pas'";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $u: $n replaced\n" if $n;
}

open my $out, '>', $file or die "cannot write $file: $!";
print $out $c;
close $out;
print "wrote $file\n";
