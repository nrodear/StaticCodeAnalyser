unit uTestFieldName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFieldName = class
  public
    [Test] procedure FPrefix_NoFinding;
    [Test] procedure NoFPrefix_Reported;
    [Test] procedure MethodInClass_NoFinding;
    [Test] procedure UnitLevelVar_NoFinding;
    [Test] procedure FieldName_KindAndSeverity;
    [Test] procedure MultilineHeaderMiddleParam_NotReported;
    [Test] procedure TypedClassConst_NotReported;
    [Test] procedure VarAfterConstSection_FieldReportedAgain;
    // Testluecke 153: strict-Sektionen, record, nested class
    [Test] procedure StrictPrivateField_Reported;
    [Test] procedure StrictPublicIsNotAThing_PublicStaysUnchecked;
    [Test] procedure RecordPrivateSection_Reported;
    [Test] procedure NestedClassOwnField_Reported;
    [Test] procedure FieldAfterNestedClassEnd_KnownGap_OnlyInnerReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFieldName.FPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FCount: Integer;'#13#10 +
  '    FName: string;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.NoFPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.MethodInClass_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '    function GetX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.UnitLevelVar_NoFinding;
// Unit-level Variables sind keine Klassen-Felder.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'var'#13#10 +
  '  Counter: Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.FieldName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkFieldName then
      begin
        Assert.AreEqual<TFindingKind>(fkFieldName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFieldName finding');
  finally Findings.Free; end;
end;

procedure TTestFieldName.MultilineHeaderMiddleParam_NotReported;
// Voll-Review 2026-09-12 (Blocker): die Mittelzeile 'B: string;' eines
// dreizeiligen Methodenkopfs hat weder ')' noch einen Modifier-Prefix
// und passierte alle Guards -> FP 'Field B does not follow F<Name>'.
// Jetzt haelt die Klammerbilanz die offene Parameterliste fest.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure Foo(A: Integer;'#13#10 +
  '      B: string;'#13#10 +
  '      C: Boolean);'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.TypedClassConst_NotReported;
// Zweite FP-Klasse des Blockers: die 'const'-Zeile schaltete nur SICH
// SELBST stumm, die typisierte Konstante danach wurde als Feld
// geflaggt. Jetzt traegt die const-Untersektion bis zum naechsten
// Abschnitts-Keyword.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    const'#13#10 +
  '      Timeout: Integer = 500;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.VarAfterConstSection_FieldReportedAgain;
// Gegenrichtung zum const-Untersektions-Gate: 'var' beendet die
// Untersektion, das Feld dahinter wird weiter gemeldet. Assert auf
// EXAKT 1 ist beidseitig scharf - die Bestandsfassung meldete hier 2
// (Timeout faelschlich mit), eine uebergriffige Untersektion 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    const'#13#10 +
  '      Timeout: Integer = 500;'#13#10 +
  '    var'#13#10 +
  '      Speed: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.StrictPrivateField_Reported;
// Testluecke 153 (Voll-Review 2026-09-12) - und der Test deckte einen
// FALSCH NEGATIVEN auf, nicht nur eine Luecke.
//
// Das erste Wort der Zeile 'strict private' ist 'strict'. Die
// Sichtbarkeits-Verzweigung kannte nur die Einwort-Formen und hat die
// Zeile bloss uebersprungen - InCheckVis blieb False, und JEDES Feld
// einer strict-Sektion war fuer diese Regel unsichtbar. Der Unit-Kopf
// verspricht 'private/protected', und strict private IST private.
//
// Am gebauten Stand VOR dem Fix nachgemessen: 0 Funde. Nach dem Fix
// muss es 1 sein - diese Zeile ist der Beleg.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TStrikt = class'#13#10 +
  '  strict private'#13#10 +
  '    zaehler: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName),
    'ein Feld in strict private ist ein Feld');
  finally F.Free; end;
end;

procedure TTestFieldName.StrictPublicIsNotAThing_PublicStaysUnchecked;
// Die Gegenprobe zum Fix, und sie prueft die ENGE der neuen Regel:
// nur 'strict private' und 'strict protected' schalten die Pruefung
// ein. Ein normales public bleibt ungeprueft wie bisher - dort leben
// die vom Form-Designer verwalteten Felder, die die F-Konvention
// nicht erfuellen koennen (Begruendung im Detektor).
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOffen = class'#13#10 +
  '  public'#13#10 +
  '    zaehler: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName),
    'public bleibt ungeprueft - der strict-Fix darf das nicht kippen');
  finally F.Free; end;
end;

procedure TTestFieldName.RecordPrivateSection_Reported;
// Ein record mit private-Sektion verhaelt sich wie eine Klasse. Das
// funktionierte schon, war aber nicht festgehalten.
// Am gebauten Stand nachgemessen: 1 Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  RMitPrivat = record'#13#10 +
  '  private'#13#10 +
  '    zaehler: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName),
    'auch im record gilt die Konvention');
  finally F.Free; end;
end;

procedure TTestFieldName.NestedClassOwnField_Reported;
// Das Feld der INNEREN Klasse wird gemeldet. Positiv-Kontrolle fuer
// den Test darunter: ohne sie waere dessen Null auch dann erklaerbar,
// wenn der Detektor an nested classes gar nichts findet.
//
// Die Fixture ist mit der des naechsten Tests bis auf zwei Zeilen
// identisch ('var' + 'aussenfeld') - genau diese zwei Zeilen sind der
// Prueffall. Der Selbstscan meldet dafuer einen DuplicateBlock; in
// Testunits per Profil-Politik kein Mangel, und ein Generator wuerde
// verstecken, worum es geht.
// Am gebauten Stand nachgemessen: 1 Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TAussen = class'#13#10 +
  '  private'#13#10 +
  '    type'#13#10 +
  '      TInnen = class'#13#10 +
  '      private'#13#10 +
  '        innenfeld: Integer;'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName),
    'das Feld der inneren Klasse zaehlt');
  finally F.Free; end;
end;

procedure TTestFieldName.FieldAfterNestedClassEnd_KnownGap_OnlyInnerReported;
// BEKANNTE GRENZE, als Ist-Zustand festgenagelt: gemeldet wird nur
// 'innenfeld'. Dass 'aussenfeld' fehlt, ist ein FALSCH NEGATIVER.
//
// Das 'end' der INNEREN Klasse setzt InClass auf False - der Zaehler
// kennt keine Schachtelungstiefe. Alles, was danach noch im AEUSSEREN
// Klassenrumpf steht, ist fuer die Regel unsichtbar; hier trifft es
// 'aussenfeld'.
//
// Nicht mit dem strict-Fix zusammen behoben: das braucht eine echte
// Tiefenzaehlung ueber class/record/end und beruehrt damit den
// gesamten Zustandsautomaten - Posten 9006. Wer sie einbaut, sieht
// hier rot und stellt die Erwartung auf 1.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TAussen = class'#13#10 +
  '  private'#13#10 +
  '    type'#13#10 +
  '      TInnen = class'#13#10 +
  '      private'#13#10 +
  '        innenfeld: Integer;'#13#10 +
  '      end;'#13#10 +
  '    var'#13#10 +
  '      aussenfeld: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var
  F         : TObjectList<TLeakFinding>;
  Fnd       : TLeakFinding;
  HatInnen  : Boolean;
  HatAussen : Boolean;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    HatInnen  := False;
    HatAussen := False;
    for Fnd in F do
      if Fnd.Kind = fkFieldName then
      begin
        if Pos('innenfeld',  Fnd.MissingVar) > 0 then HatInnen  := True;
        if Pos('aussenfeld', Fnd.MissingVar) > 0 then HatAussen := True;
      end;
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName),
      'genau ein Fund - der der inneren Klasse');
    Assert.IsTrue(HatInnen,
      'das innere Feld muss gemeldet sein');
    Assert.IsFalse(HatAussen,
      'BEKANNTE GRENZE: nach dem inneren end ist der Zaehler blind, '
      + 'aussenfeld entgeht der Regel');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFieldName);

end.
