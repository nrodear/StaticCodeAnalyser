unit uGroupedDeclaration;

// Detektor fuer gruppierte Deklarationen `A, B: Type;`.
//
// SonarDelphi-Aequivalent: communitydelphi:GroupedFieldDeclaration,
// :GroupedVariableDeclaration, :GroupedParameterDeclaration (in SCA
// als einzelne Regel zusammengefasst, separater Detektor pro Subkategorie
// folgt evtl. spaeter).
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
  uAstNode, uSCAConsts, uMethodd12;

type
  TGroupedDeclarationDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
end;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Liefert Spalte des ersten Identifier wenn die Zeile ein gruppiertes
// `Id1, Id2[, Id3...]: Type;`-Pattern enthaelt, sonst 0.
function FindGroupedDecl(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
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
    case State of
      skScan:
        begin
          if IsIdentStart(c) then
          begin
            FirstCol := i;
            IdCount  := 1;
            while (i <= n) and IsIdent(Line[i]) do Inc(i);
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
            while (i <= n) and IsIdent(Line[i]) do Inc(i);
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
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindGroupedDecl(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Grouped declaration at column %d (`A, B: Type`) - split into ' +
        'one variable per line for clearer diffs and refactoring.', [Col]);
      F.SetKind(fkGroupedDeclaration);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
