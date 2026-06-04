#!/usr/bin/perl
# Biegt 'in <oldPrefix>\<sub>\unit.pas' im IDE-dpk auf
# 'in <newPrefix>\<sub>\unit.pas' um. Ausnahmen: uIDEColors, uRecentPaths
# bleiben in StaticCodeAnalyserForm/sources/Common, uLocalization +
# uAnalyserTypes wandern von UI nach SCA.Engine/Common.
#
# Aufruf: tools\fix-dpk-paths.pl <dpk-file>
#         (nur fuer IDE-dpk; Form-dpr nutzt fix-dpr-paths.pl mit
#         anderem alten Pfad-Prefix)
use strict;
use warnings;

my $file = shift @ARGV or die "usage: $0 <dpk-file>\n";
open my $fh, '<', $file or die "cannot read $file: $!";
local $/;
my $c = <$fh>;
close $fh;

# Mass-replace: ..\StaticCodeAnalyserForm\sources\X\ -> ..\SCA.Engine\sources\X\
for my $sub (qw(Detectors Parsing Infrastructure Output Common)) {
    my $old = "in '..\\StaticCodeAnalyserForm\\sources\\$sub\\";
    my $new = "in '..\\SCA.Engine\\sources\\$sub\\";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $sub: $n replaced\n" if $n;
}
# uLocalization + uAnalyserTypes wanderten von UI nach Engine\Common
for my $special (qw(uLocalization uAnalyserTypes)) {
    my $old = "in '..\\StaticCodeAnalyserForm\\sources\\UI\\$special.pas'";
    my $new = "in '..\\SCA.Engine\\sources\\Common\\$special.pas'";
    my $n = () = $c =~ /\Q$old\E/g;
    $c =~ s/\Q$old\E/$new/g;
    print "  $special: $n replaced\n" if $n;
}
# Ausnahmen zurueck: uIDEColors + uRecentPaths bleiben in Form/Common
for my $keep (qw(uIDEColors uRecentPaths)) {
    my $bad = "in '..\\SCA.Engine\\sources\\Common\\$keep.pas'";
    my $good = "in '..\\StaticCodeAnalyserForm\\sources\\Common\\$keep.pas'";
    my $n = () = $c =~ /\Q$bad\E/g;
    $c =~ s/\Q$bad\E/$good/g;
    print "  restored $keep: $n\n" if $n;
}

open my $out, '>', $file or die "cannot write $file: $!";
print $out $c;
close $out;
print "wrote $file\n";
