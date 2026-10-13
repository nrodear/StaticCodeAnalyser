unit uTestUnusedUsesIdents;

// Tests fuer den KnownIdents-/IdentsFor-Vertrag von uUnusedUses (SCA007),
// Review 2026-10-13: leer heisst "nicht gemappt", der Kurznamen-Rueckfall
// gilt nur fuer RTL-Namespaces (IstRtlNamespace) und steht seitdem in
// EINER oeffentlichen Routine (IdentsFor) - die SCA007-Editorhilfe in
// reDelphix baute dieselbe Kette nach. Eigene Fixture, damit die
// Detektor-Fixture uTestUnusedUses nicht weiter waechst.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils;

type
  [TestFixture]
  TTestUnusedUsesIdents = class
  public
    [Test] procedure KnownIdents_FullAndShortName_SameList;
    [Test] procedure KnownIdents_UnknownUnit_Empty;
    [Test] procedure IdentsFor_RtlNamespace_FallsBackToShortName;
    [Test] procedure IdentsFor_ForeignNamespace_NoFallback;
  end;

implementation

uses
  uUnusedUses;

function Joined(const A: TArray<string>): string;
begin
  Result := string.Join(',', A);
end;

procedure TTestUnusedUsesIdents.KnownIdents_FullAndShortName_SameList;
begin
  // Beide Schreibweisen sind je Eintrag gelistet - der Vertrag der Tabelle.
  Assert.IsTrue(Length(TUnusedUsesDetector.KnownIdents('system.classes')) > 0,
    'system.classes ist gemappt');
  Assert.AreEqual(Joined(TUnusedUsesDetector.KnownIdents('system.classes')),
    Joined(TUnusedUsesDetector.KnownIdents('classes')),
    'voller Name und Kurzname liefern dieselbe Liste');
  Assert.IsTrue(Pos(',tstringlist,', ',' + Joined(TUnusedUsesDetector.KnownIdents('classes')) + ',') > 0,
    'tstringlist steht in der classes-Liste');
end;

procedure TTestUnusedUsesIdents.KnownIdents_UnknownUnit_Empty;
begin
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.KnownIdents('myapp.utils')),
    'nicht gemappt = leer, nicht "keine Bezeichner"');
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.KnownIdents('')),
    'leerer Name');
end;

procedure TTestUnusedUsesIdents.IdentsFor_RtlNamespace_FallsBackToShortName;
begin
  // 'fmx.styles' hat keinen eigenen Eintrag, 'styles' (VCL) schon - der
  // dokumentierte Nutz-Fall des Rueckfalls (TStyleManager-Nachweis).
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.KnownIdents('fmx.styles')),
    'Vorbedingung: fmx.styles selbst ist nicht gemappt');
  Assert.AreEqual(Joined(TUnusedUsesDetector.KnownIdents('styles')),
    Joined(TUnusedUsesDetector.IdentsFor('fmx.styles')),
    'IdentsFor faellt auf die Kurznamen-Liste zurueck');
  // Ein direkt gemappter Name braucht keinen Rueckfall.
  Assert.AreEqual(Joined(TUnusedUsesDetector.KnownIdents('vcl.stdctrls')),
    Joined(TUnusedUsesDetector.IdentsFor('vcl.stdctrls')),
    'gemappt: unveraendert');
end;

procedure TTestUnusedUsesIdents.IdentsFor_ForeignNamespace_NoFallback;
begin
  // C-Charge 2026-09-19: 'Alcinoe.FMX.StdCtrls' darf NICHT auf die
  // VCL-'stdctrls'-Liste fallen - sonst wird die Unit trotz Nutzung
  // ihrer eigenen Typen (TALButton) gemeldet.
  Assert.IsFalse(TUnusedUsesDetector.IstRtlNamespace('alcinoe.fmx.stdctrls'),
    'Vorbedingung: kein RTL-Namespace');
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.IdentsFor('alcinoe.fmx.stdctrls')),
    'fremder Namespace: leer, kein Rueckfall');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedUsesIdents);

end.
