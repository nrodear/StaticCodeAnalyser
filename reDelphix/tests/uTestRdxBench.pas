unit uTestRdxBench;

// Selbstpruefung des FPC-Pruefstands (tools\fpc-pruefstand\build.sh, Review
// reDelphix R6-03): der Pruefstand schreibt fuer FPC 3.2.2 Unitnamen
// (System.SysUtils -> SysUtils ...), 'Assert.AreEqual<Integer>(' und die
// Attribute [TestFixture]/[Test] um - nur AUSSERHALB von String-Literalen.
// Bis Charge FF schrieb er auch in Literalen um: ein Test, der einen
// qualifizierten Unitnamen oder ein Attribut als TEXT prueft, lief unter
// FPC mit anderen Daten als unter Delphi (uTestRdxStructFixes: aus
// '  System.Classes,' wurde '  Classes,'; uTestRdxDeclFixes: der
// SCA117-Fall mit '    [Test]' pruefte eine Leerzeile). Jeder Fall hier
// traegt den Text einmal als ganzes Literal und einmal zerteilt: schreibt
// der Pruefstand das ganze Literal um, sind beide verschieden.
// In reDelphix.Test laeuft die Unit trivial gruen - sie prueft den
// Pruefstand, nicht das Modul.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxBench = class
  public
    // Qualifizierte Unitnamen im Literal bleiben qualifiziert.
    [Test] procedure Literal_KeepsQualifiedUnitNames;
    // '[Test]' und '[TestFixture]' im Literal bleiben stehen, auch in einer
    // Zeile, die mit dem Literal beginnt (Liste ueber Zeilen).
    [Test] procedure Literal_KeepsAttributes;
    // 'Assert.AreEqual<Integer>(' im Literal bleibt stehen.
    [Test] procedure Literal_KeepsGenericAssert;
  end;

implementation

procedure TTestRdxBench.Literal_KeepsQualifiedUnitNames;
begin
  Assert.AreEqual('System.' + 'SysUtils', 'System.SysUtils');
  Assert.AreEqual('System.' + 'Classes', 'System.Classes');
  Assert.AreEqual('System.' + 'Hash', 'System.Hash');
  Assert.AreEqual('System.' + 'StrUtils', 'System.StrUtils');
  Assert.AreEqual('System.' + 'SyncObjs', 'System.SyncObjs');
  Assert.AreEqual('System.' + 'IOUtils', 'System.IOUtils');
  Assert.AreEqual('System.' + 'Generics.Collections',
    'System.Generics.Collections');
end;

procedure TTestRdxBench.Literal_KeepsAttributes;
var
  TestLine, FixtureLine : string;
begin
  Assert.AreEqual('[Te' + 'st]', '[Test]');
  Assert.AreEqual('[Test' + 'Fixture]', '[TestFixture]');
  TestLine :=
    '    [Test]';
  FixtureLine :=
    '  [TestFixture]';
  Assert.AreEqual('    [Te' + 'st]', TestLine);
  Assert.AreEqual('  [Test' + 'Fixture]', FixtureLine);
end;

procedure TTestRdxBench.Literal_KeepsGenericAssert;
begin
  Assert.AreEqual('Assert.AreEqual' + '<Integer>(',
    'Assert.AreEqual<Integer>(');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBench);

end.
