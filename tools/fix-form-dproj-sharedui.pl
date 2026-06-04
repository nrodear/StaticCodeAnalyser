#!/usr/bin/perl
# Einmal-Skript fuer SharedUI-Sprint Schritt 6: biegt die 10
# DCCReference-Eintraege im Form-dproj von sources\UI/Common
# auf ..\SCA.SharedUI\sources um.
use strict;
use warnings;

my $file = shift @ARGV or die "usage: $0 <dproj-file>\n";
open my $fh, '<', $file or die "cannot read $file: $!";
local $/;
my $c = <$fh>;
close $fh;

my @units_ui     = qw(uAnalyserPalette uAnalyserTheme uFindingGridRenderer uFindingFilter uIDEStatsTiles uIDEHelpPanel uIDEToolbar uExportMenu);
my @units_common = qw(uIDEColors uRecentPaths);

for my $u (@units_ui) {
    my $old = 'Include="sources\\UI\\' . $u . '.pas"';
    my $new = 'Include="..\\SCA.SharedUI\\sources\\' . $u . '.pas"';
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  UI $u: $n\n" if $n;
}
for my $u (@units_common) {
    my $old = 'Include="sources\\Common\\' . $u . '.pas"';
    my $new = 'Include="..\\SCA.SharedUI\\sources\\' . $u . '.pas"';
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  Common $u: $n\n" if $n;
}

open my $out, '>', $file or die "cannot write $file: $!";
print $out $c;
close $out;
print "wrote $file\n";
