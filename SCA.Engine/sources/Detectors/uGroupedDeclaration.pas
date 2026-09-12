unit uGroupedDeclaration;

// Detektor fuer gruppierte Deklarationen `A, B: Type;`.
//
// SonarDelphi-Aequivalent: communitydelphi:GroupedFieldDeclaration,
// :GroupedVariableDeclaration. GroupedParameterDeclaration ist
// BEWUSST NICHT abgedeckt - gruppierte Parameter `F(A, B: Integer)` sind
// idiomatische Delphi-Syntax und produzierten in einem Self-Test 660+
// FPs auf realem Code. Implementiert via ParenDepth-Filter unten.
//
// Hintergrund: `A, B, C: Integer;` macht Diffs unklar (eine neue Variable
// einzufuegen aendert eine bestehende Zeile statt eine eigene), und
// erschwert per-Variable-Kommentare bzw. Refactorings wie Type-Wechsel
// (nur eine Variable soll dann anderen Typ haben).
//
// Erkennung: per-Zeile-Scan. Match auf Pattern
//   <Ident> ( `,` `<Ident>` )+ `:` <Type>
// also: zwei oder mehr Identifier durch Komma getrennt, dann Doppelpunkt
// gefolgt von Typ. String-/Kommentar-Awareness aktiv.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TGroupedDeclarationDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdentStart(C: Char): Boolean; inline;
begin
  // Voll-Review 2026-09-12: Zeichenklasse zentralisiert - die lokale
  // Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentStartChar (A..Z, a..z, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentStartChar(C);
end;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Liefert Spalte des ersten Identifier wenn die Zeile ein gruppiertes
// `Id1, Id2[, Id3...]: Type;`-Pattern enthaelt, sonst 0.
//
// ParenDepth: 0 = nicht in '('...')'. > 0 = innerhalb eines Klammer-Blocks
// (Parameter-Liste oder Index-Liste). Gruppierte Parameter `(const A, B: T)`
// sind LEGITIME Pascal-Syntax und kein Style-Defekt - die Regel betrifft nur
// var/field/const-Sektionen (depth=0). Caller fuehrt ParenDepth UEBER Zeilen
// hinweg fort, damit mehrzeilige Method-Header korrekt behandelt werden.
// Blockwort-Zaehlung fuer das case-Gate: 'case' oeffnet, 'end'
// schliesst - Bloecke INNERHALB des case (begin/try/record) werden
// gegengezaehlt, damit deren 'end' nicht das case beendet.
// GRENZE (dokumentiert, akzeptiert): ein case IN einem begin-Block IN
// einem aeusseren case verwechselt beim inneren end die Ebene - das
// Gate endet dann zu frueh und der alte FP bleibt in diesem Exoten.
// Vor dem Gate meldete JEDE case-Label-Liste (Voll-Review 2026-09-12,
// Blocker).
type
  // Die zwei Zaehler des case-Gates als EIN Zustand - sie reisen immer
  // gemeinsam ueber die Zeilen (und halten FindGroupedDecl unter der
  // eigenen SCA013-Parametergrenze).
  TCaseGate = record
    CaseDepth  : Integer;
    InnerDepth : Integer;
  end;

procedure ZaehleBlockwort(const W: string; var Gate: TCaseGate);
begin
  if W = 'case' then
    Inc(Gate.CaseDepth)
  else if (W = 'begin') or (W = 'try') or (W = 'record') then
  begin
    if Gate.CaseDepth > 0 then Inc(Gate.InnerDepth);
  end
  else if W = 'end' then
  begin
    if Gate.CaseDepth = 0 then Exit;
    if Gate.InnerDepth > 0 then Dec(Gate.InnerDepth)
    else Dec(Gate.CaseDepth);
  end;
end;

function FindGroupedDecl(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean; var ParenDepth: Integer;
  var Gate: TCaseGate): Integer;
type
  TStateKind = (skScan, skAfterIdent, skExpectId2);
var
  i, n, j  : Integer;
  InStr    : Boolean;
  pClose   : Integer;
  c        : Char;
  State    : TStateKind;
  FirstCol : Integer;
  IdCount  : Integer;
  Wort     : string;
begin
  Result   := 0;
  InStr    := False;
  i := 1;
  n := Length(Line);
  State := skScan;
  FirstCol := 0;
  IdCount  := 0;
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    // ParenDepth-Tracking: '(' / ')' ausserhalb von Strings/Kommentaren.
    // '[' / ']' werden NICHT gezaehlt (Array-Typ-Decl ist depth-0).
    if c = '(' then begin Inc(ParenDepth); Inc(i); State := skScan; FirstCol := 0; IdCount := 0; Continue; end;
    if c = ')' then
    begin
      if ParenDepth > 0 then Dec(ParenDepth);
      Inc(i); State := skScan; FirstCol := 0; IdCount := 0; Continue;
    end;
    // Innerhalb eines Klammer-Blocks (Parameter-Liste) wird NICHT geflaggt -
    // gruppierte Parameter sind legitim. Wir tracken nur die Klammern, der
    // State-Machine-Lauf bleibt aus.
    if ParenDepth > 0 then begin Inc(i); Continue; end;
    case State of
      skScan:
        begin
          if IsIdentStart(c) then
          begin
            FirstCol := i;
            IdCount  := 1;
            while (i <= n) and IsIdent(Line[i]) do Inc(i);
            // case-Gate: Blockwoerter zaehlen; INNERHALB eines case
            // ist 'label1, label2: Anweisung' Syntax, kein Stilmangel.
            Wort := LowerCase(Copy(Line, FirstCol, i - FirstCol));
            ZaehleBlockwort(Wort, Gate);
            if Gate.CaseDepth > 0 then
            begin
              State := skScan;
              FirstCol := 0; IdCount := 0;
              Continue;
            end;
            State := skAfterIdent;
            Continue;
          end;
          Inc(i);
        end;
      skAfterIdent:
        begin
          if CharInSet(c, [' ', #9]) then
          begin Inc(i); Continue; end;
          if c = ',' then
          begin
            State := skExpectId2;
            Inc(i); Continue;
          end;
          if c = ':' then
          begin
            // Doppelpunkt, aber nur >= 2 Idents zaehlt als gruppiert
            if IdCount >= 2 then
            begin
              // Stelle sicher, dass weiterer Identifier (Typ) folgt
              j := i + 1;
              while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
              if (j <= n) and IsIdentStart(Line[j]) then
              begin
                Result := FirstCol;
                Exit;
              end;
            end;
            // Reset; aktuelles `:` ist konsumiert.
            State := skScan;
            Inc(i);
            FirstCol := 0; IdCount := 0;
            Continue;
          end;
          // Anderes Zeichen (z.B. `;`, `(`, Identifier-Start) -> Reset.
          // KEIN Inc(i): das aktuelle Zeichen soll im skScan-State neu
          // betrachtet werden, sonst werden Identifier wie `Foo` in
          // `procedure Foo; var A, B: Type` uebersprungen.
          State := skScan;
          FirstCol := 0; IdCount := 0;
        end;
      skExpectId2:
        begin
          if CharInSet(c, [' ', #9]) then
          begin Inc(i); Continue; end;
          if IsIdentStart(c) then
          begin
            j := i;
            while (i <= n) and IsIdent(Line[i]) do Inc(i);
            Wort := LowerCase(Copy(Line, j, i - j));
            ZaehleBlockwort(Wort, Gate);
            if Gate.CaseDepth > 0 then
            begin
              State := skScan;
              FirstCol := 0; IdCount := 0;
              Continue;
            end;
            Inc(IdCount);
            State := skAfterIdent;
            Continue;
          end;
          // Komma war doch nicht Teil einer Gruppen-Deklaration.
          // Wie oben: kein Inc, damit das aktuelle Zeichen erneut im
          // skScan-State verarbeitet wird.
          State := skScan;
          FirstCol := 0; IdCount := 0;
        end;
    end;
  end;
end;

class procedure TGroupedDeclarationDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  ParenDepth : Integer;
  Gate       : TCaseGate;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    ParenDepth := 0;
    Gate := Default(TCaseGate);
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindGroupedDecl(Lines[i], InBlk, InParen, ParenDepth, Gate);
      if Col <= 0 then Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('Grouped declaration at column %d (`A, B: Type`) - split ' +
               'into one variable per line for clearer diffs and refactoring.',
          [Col]),
        fkGroupedDeclaration));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
