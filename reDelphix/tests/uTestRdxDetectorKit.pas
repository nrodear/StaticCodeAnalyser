unit uTestRdxDetectorKit;

// Testhilfen der Detektor-Rundlaeufe (nur Delphi, reDelphix.Test): Datei
// schreiben, den echten Detektor auf dem echten AST laufen lassen, die
// Hilfe ueber den Einstieg des Anbieters (TRdxFixTable.FixFor) planen und
// wie der Editor anwenden, Fund fuer Fund bis der Detektor schweigt. Bis
// Charge H3c stand das dreimal - in uTestRdxSimpleFixesDetector,
// uTestRdxCleanupDetector und uTestRdxRoutineFixesDetector (Gegen-Review
// H3, Minor 9); reine Verschiebung. Welcher Detektor zu welcher Art laeuft,
// bleibt in der Testunit (TDetectorRun) - die drei registrieren
// verschiedene Detektormengen.
// Join, Apply, WriteText und TempName stehen seit Review R6-08 in der
// FPC-tauglichen Hilfs-Unit uTestRdxTextKit (auch fuer die Testunits ohne
// Detektor) - hier bleibt, was Parser, Detektoren und Anbieter brauchen.

interface

uses
  System.Generics.Collections,
  uAstNode,           // TAstNode
  uMethodd12,         // TLeakFinding
  uSCAConsts,         // TFindingKind
  uRdxBufferMath,     // TRdxEdit
  uRdxRecipeRunner;   // TRdxFixOutcome

type
  // Was die Hilfe aus einem Fund liest - wie der Anbieter aus TLeakFinding.
  // Variant: TLeakFinding.LeakVariant (SCA001 - die Hilfe der Charge H4
  // gibt es nur fuer freed-outside-finally); '' bei allen anderen Regeln.
  TSeen = record
    Line    : Integer;
    Msg     : string;
    Variant : string;
  end;

  // Der Verteiler einer Testunit: ruft fuer AKind den echten Detektor auf
  // Root (Funde nach Results).
  TDetectorRun = procedure(AKind: TFindingKind; Root: TAstNode;
    const Path: string; Results: TObjectList<TLeakFinding>);

  // Detect einer Testunit: die Funde der Art AKind im Quelltext.
  TDetectFunc = function(const ASource: string;
    AKind: TFindingKind): TArray<TSeen>;

// Ein Katalog-Beispiel als Quelltext: Zeilenenden CRLF (JSON liefert #10,
// der eingebaute Katalog #13#10). uTestRdxSimpleFixesDetector laesst dazu
// '...' weg (eigene Snip).
function CatalogText(const AExample: string): string;
// ASource in eine neue .pas-Datei im TEMP-Verzeichnis (TempName,
// WriteText aus uTestRdxTextKit); ihr Name.
function WriteTemp(const APrefix, ASource: string): string;
// Funde der Art AKind in der Datei APath - ARun auf dem echten AST.
function DetectFile(const APath: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
// Dasselbe fuer einen Quelltext (Datei APrefix* im TEMP, danach geloescht).
function DetectSource(const APrefix, ASource: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
// Die Hilfe fuer EINEN Fund ueber den Einstieg des Anbieters: der Fund als
// TLeakFinding der Datei AFile, der Quellstellen-Dienst auf demselben Text.
function PlanFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
// Der zweite Eintrag (TRdxFixTable.AlternativeFixFor) fuer EINEN Fund - der
// Lauf wie PlanFixIn, ohne dessen Handles-Assert (eine Art ohne Zeile gibt
// den leeren Ausgang, wie der Anbieter). Bis zur Review Woche G07-27 stand
// er in uTestRdxSimpleFixesDetector (PlanAltFix) kopiert.
function PlanAltFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
// Dasselbe fuer 't.pas': True mit den Ersetzungen bzw. False mit dem Grund.
function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
// Fund fuer Fund, nach jeder Ersetzung neu gemeldet (wie der Benutzer es
// taete) und angewendet wie der Editor (uTestRdxTextKit.Apply), bis der
// Detektor (ADetect) schweigt. AAlt nimmt statt der Hilfe den zweiten
// Eintrag (PlanAltFixIn) - fuer die Rundlaeufe der Ausweichwege.
function FixAllWith(const ASource: string; AKind: TFindingKind;
  ADetect: TDetectFunc; AAlt: Boolean = False): string;
// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelpWith(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string; ADetect: TDetectFunc);
// Wie AssertNoHelpWith, aber fuer den Fund auf Zeile ALine; ohne Fund dort
// scheitert der Test (bis zur Review Woche G07-27 in
// uTestRdxSimpleFixesDetector).
procedure AssertNoHelpAt(const ASource: string; AKind: TFindingKind;
  ALine: Integer; const AReasonPart: string; ADetect: TDetectFunc);

const
  // Die Zeile des Eintrags AUnit in BranchUsesUnit (beide Formen).
  BRANCH_USES_LINE = 6;

// Fix-Runde 4 (AppendUses mit den Zeilen der Ersetzungen): eine Unit,
// deren interface-uses AUnit nur unter '{$IFDEF RDX_X}' traegt, hinter
// 'Foo.Abstract' - der Baum verliert den Eintrag (der Parser bricht die
// Klausel an diesem Glied ab, rwE29), der Text sieht ihn bedingt in Zeile
// BRANCH_USES_LINE. AInBranch: der Zweig umschliesst auch den
// implementation-Teil AImpl (wie gexperts '{$IFDEF GX_EII}' um die ganze
// Unit, rwE31); sonst endet er direkt hinter der Klausel.
function BranchUsesUnit(const AUnit, AImpl: string;
  AInBranch: Boolean): string;
// Die Hilfe (AAlt: der zweite Eintrag) fuer den ersten Fund der Art AKind
// in BranchUsesUnit(AUnit, AImpl, ..): im Zweig frei mit AEdits
// Ersetzungen, keine fuer uses (kein ' + uses' im Hinweis); ausserhalb
// gesperrt mit R_USES_CONDITIONAL fuer die Zeile des Eintrags (AQualified
// im Grund), ohne Ersetzung.
procedure AssertBranchUses(const AUnit, AQualified, AImpl: string;
  AKind: TFindingKind; AAlt: Boolean; AEdits: Integer; ADetect: TDetectFunc);

implementation

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uParser2,           // TParser2
  uEngineApi,         // TSourcePlaces
  uRdxFixTable,       // TRdxFixTable.FixFor
  uRdxPlacesRunner,   // R_USES_CONDITIONAL (AssertBranchUses)
  uRdxText,           // _, MsgByHand (AssertBranchUses)
  uTestRdxTextKit;    // TempName, WriteText, Apply (Review R6-08)

function CatalogText(const AExample: string): string;
begin
  Result := StringReplace(AExample, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

function WriteTemp(const APrefix, ASource: string): string;
begin
  Result := TempName(APrefix, '.pas');
  WriteText(Result, ASource);
end;

function DetectFile(const APath: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
var
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  n       : Integer;
begin
  Result := nil;
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(APath);
      try
        ARun(AKind, Root, APath, Results);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    SetLength(Result, Results.Count);
    n := 0;
    for F in Results do
      if F.Kind = AKind then
      begin
        Result[n].Line    := F.LineInt;
        Result[n].Msg     := F.Message;
        Result[n].Variant := F.LeakVariant;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    Results.Free;
  end;
end;

function DetectSource(const APrefix, ASource: string; AKind: TFindingKind;
  ARun: TDetectorRun): TArray<TSeen>;
var
  Path : string;
begin
  Path := WriteTemp(APrefix, ASource);
  try
    Result := DetectFile(Path, AKind, ARun);
  finally
    DeleteFile(Path);
  end;
end;

// Der Lauf beider Einstiege: der Fund als TLeakFinding der Datei AFile, der
// Quellstellen-Dienst auf demselben Text; AAlt waehlt AlternativeFixFor.
// Alle drei Objekte entstehen im try (Review Woche G01-17: scheitert ein
// spaeteres Create, raeumt das finally die frueheren ab).
function PlanEntry(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen; AAlt: Boolean): TRdxFixOutcome;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
begin
  SL := nil;
  Places := nil;
  Finding := nil;
  try
    SL := TStringList.Create;
    Places := TSourcePlaces.Create;
    Finding := TLeakFinding.New(AFile, '', ASeen.Line, ASeen.Msg, AKind);
    Finding.LeakVariant := ASeen.Variant;
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource(AFile, ASource), 'OpenSource');
    if AAlt then
      Result := TRdxFixTable.AlternativeFixFor(Places, SL, Finding,
        TRdxRecipeRunner.UsesNamesOf(Places))
    else
      Result := TRdxFixTable.FixFor(Places, SL, Finding,
        TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
end;

function PlanFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
begin
  Assert.IsTrue(TRdxFixTable.Handles(AKind), 'FixFor kennt die Art');
  Result := PlanEntry(ASource, AFile, AKind, ASeen, False);
end;

function PlanAltFixIn(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanEntry(ASource, AFile, AKind, ASeen, True);
end;

function PlanFix(const ASource: string; AKind: TFindingKind;
  const ASeen: TSeen; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  O : TRdxFixOutcome;
begin
  O := PlanFixIn(ASource, 't.pas', AKind, ASeen);
  AEdits  := O.Edits;
  AReason := O.Reason;
  Result  := O.Enabled;
end;

function FixAllWith(const ASource: string; AKind: TFindingKind;
  ADetect: TDetectFunc; AAlt: Boolean): string;
const
  MAX_PASSES = 10;
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
  O      : TRdxFixOutcome;
  Pass   : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := ADetect(Result, AKind);
    if Length(Seen) = 0 then Exit;
    if AAlt then
    begin
      O := PlanAltFixIn(Result, 't.pas', AKind, Seen[0]);
      Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
      Edits := O.Edits;
    end
    else
      Assert.IsTrue(PlanFix(Result, AKind, Seen[0], Edits, Reason),
        Format('Zeile %d: %s', [Seen[0].Line, Reason]));
    Result := Apply(Result, Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

procedure AssertNoHelpWith(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string; ADetect: TDetectFunc);
var
  Seen   : TArray<TSeen>;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := ADetect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Assert.IsFalse(PlanFix(ASource, AKind, Seen[0], Edits, Reason), 'keine Hilfe');
  Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
end;

procedure AssertNoHelpAt(const ASource: string; AKind: TFindingKind;
  ALine: Integer; const AReasonPart: string; ADetect: TDetectFunc);
var
  Seen   : TArray<TSeen>;
  S      : TSeen;
  Edits  : TArray<TRdxEdit>;
  Reason : string;
begin
  Seen := ADetect(ASource, AKind);
  for S in Seen do
    if S.Line = ALine then
    begin
      Assert.IsFalse(PlanFix(ASource, AKind, S, Edits, Reason), 'keine Hilfe');
      Assert.IsTrue(Pos(AReasonPart, Reason) > 0, Reason);
      Exit;
    end;
  Assert.Fail(Format('kein Fund auf Zeile %d', [ALine]));
end;

function BranchUsesUnit(const AUnit, AImpl: string;
  AInBranch: Boolean): string;
begin
  if AInBranch then
    Result := Join(['unit t;', '{$IFDEF RDX_X}', 'interface', 'uses',
      '  Foo.Abstract,', '  ' + AUnit + ';', 'implementation', AImpl,
      '{$ENDIF RDX_X}', 'end.'])
  else
    Result := Join(['unit t;', 'interface', '{$IFDEF RDX_X}', 'uses',
      '  Foo.Abstract,', '  ' + AUnit + ';', '{$ENDIF RDX_X}',
      'implementation', AImpl, 'end.']);
end;

// Die Hilfe fuer den ersten Fund in ASource (AAlt: der zweite Eintrag).
function PlanFirstIn(const ASource: string; AKind: TFindingKind;
  AAlt: Boolean; ADetect: TDetectFunc): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := ADetect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet: ' + ASource);
  if AAlt then
    Result := PlanAltFixIn(ASource, 't.pas', AKind, Seen[0])
  else
    Result := PlanFixIn(ASource, 't.pas', AKind, Seen[0]);
end;

procedure AssertBranchUses(const AUnit, AQualified, AImpl: string;
  AKind: TFindingKind; AAlt: Boolean; AEdits: Integer; ADetect: TDetectFunc);
var
  O : TRdxFixOutcome;
begin
  O := PlanFirstIn(BranchUsesUnit(AUnit, AImpl, True), AKind, AAlt, ADetect);
  Assert.IsTrue(O.Enabled, 'Stelle im Zweig des Eintrags: ' + O.Reason);
  Assert.AreEqual<Integer>(AEdits, Length(O.Edits), 'keine uses-Ersetzung');
  Assert.AreEqual<Integer>(0, Pos(' + uses', O.Hint), O.Hint);
  O := PlanFirstIn(BranchUsesUnit(AUnit, AImpl, False), AKind, AAlt, ADetect);
  Assert.IsFalse(O.Enabled, 'Stelle ausserhalb des Zweigs');
  Assert.AreEqual(_('%s is missing in uses: %s', [AQualified,
    _(R_USES_CONDITIONAL, [BRANCH_USES_LINE, MsgByHand])]), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

end.
