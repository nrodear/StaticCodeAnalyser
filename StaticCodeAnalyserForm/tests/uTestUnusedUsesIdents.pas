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
    // D007 (2026-10-29): sichtbare Exporte statt Handauswahl
    [Test] procedure KnownIdents_D007_ReExporte_SindSichtbareBezeichner;
    [Test] procedure KnownIdents_D007_AuswahlRegel_HaeltGenerischeDraussen;
    [Test] procedure KnownIdents_Eintraege_KleinOhneLeerzeichenOhneDoppel;
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

function Hat(const UnitLow, Id: string): Boolean;
begin
  Result := Pos(',' + Id + ',',
    ',' + Joined(TUnusedUsesDetector.IdentsFor(UnitLow)) + ',') > 0;
end;

procedure TTestUnusedUsesIdents.KnownIdents_D007_ReExporte_SindSichtbareBezeichner;
// Vor D007 rot: keiner dieser Bezeichner stand in der Liste. Sie sind
// die Belege der KI-Realworld-FP (Vertrag d007) - fuer den Compiler
// Bezeichner der jeweiligen Unit, auch wo die Unit sie nur als Alias
// von System.UITypes neu fuehrt (mrOk, TModalResult, crHourGlass,
// fsBold, clNone). Beide Schreibweisen des Unitnamens.
const
  FAELLE: array[0..15] of array[0..1] of string = (
    ('controls', 'mrok'), ('vcl.controls', 'tmodalresult'),
    ('controls', 'crhourglass'), ('vcl.controls', 'timagelist'),
    ('controls', 'cm_mouseenter'), ('vcl.controls', 'cn_notify'),
    ('graphics', 'fsbold'), ('vcl.graphics', 'clnone'),
    ('graphics', 'psdot'), ('classes', 'tshortcut'),
    ('system.classes', 'tshiftstate'), ('math', 'inrange'),
    ('winapi.shlobj', 'csidl_personal'), ('shellapi', 'dragqueryfile'),
    ('forms', 'validparentform'), ('actnlist', 'tcustomaction'));
var
  i : Integer;
begin
  for i := Low(FAELLE) to High(FAELLE) do
    Assert.IsTrue(Hat(FAELLE[i][0], FAELLE[i][1]),
      FAELLE[i][1] + ' fehlt in der Liste von ' + FAELLE[i][0]);
end;

procedure TTestUnusedUsesIdents.KnownIdents_D007_AuswahlRegel_HaeltGenerischeDraussen;
// WAECHTER der Auswahlregel (vor und nach D007 gruen): diese Woerter
// exportiert die Unit zwar, sie beweisen aber nichts - IsAlwaysNeeded-
// Exporte (TRect, TPoint, INFINITE), Schluesselwoerter (Register),
// Allerweltswoerter (ToString, Mask, Text). Ein spaeterer Voll-Import
// der Exportliste wuerde hier rot.
const
  FAELLE: array[0..7] of array[0..1] of string = (
    ('classes', 'trect'), ('classes', 'tpoint'), ('classes', 'tostring'),
    ('classes', 'mask'), ('syncobjs', 'infinite'), ('controls', 'register'),
    ('math', 'ifthen'), ('fmx.controls', 'text'));
var
  i : Integer;
begin
  for i := Low(FAELLE) to High(FAELLE) do
    Assert.IsFalse(Hat(FAELLE[i][0], FAELLE[i][1]),
      FAELLE[i][1] + ' darf nicht in der Liste von ' + FAELLE[i][0] + ' stehen');
end;

procedure TTestUnusedUsesIdents.KnownIdents_Eintraege_KleinOhneLeerzeichenOhneDoppel;
// WAECHTER des Tabellenformats (PFLEGEHINWEIS an KnownIdents): H2
// vergleicht gegen den lowercase-Suchtext - ein Eintrag mit Gross-
// buchstaben oder Leerzeichen matcht nie und ist ein FP-Erzeuger.
// Doppelte Eintraege sind harmlos, deuten aber auf Copy-Fehler.
const
  UNITS: array[0..16] of string = (
    'classes', 'controls', 'graphics', 'forms', 'stdctrls', 'extctrls',
    'comctrls', 'math', 'shlobj', 'shellapi', 'commctrl', 'actnlist',
    'syncobjs', 'contnrs', 'fmx.controls', 'fmx.listbox', 'fmx.platform');
var
  U, Id : string;
  Seen  : TArray<string>;
begin
  for U in UNITS do
  begin
    Seen := [];
    for Id in TUnusedUsesDetector.KnownIdents(U) do
    begin
      Assert.AreEqual(Id.ToLower, Id, U + ': nicht lowercase: ' + Id);
      Assert.IsTrue((Id <> '') and (Pos(' ', Id) = 0),
        U + ': leer oder mit Leerzeichen: "' + Id + '"');
      Assert.IsFalse(Pos(',' + Id + ',', ',' + string.Join(',', Seen) + ',') > 0,
        U + ': doppelt: ' + Id);
      Seen := Seen + [Id];
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedUsesIdents);

end.
