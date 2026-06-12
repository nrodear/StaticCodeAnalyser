unit uGotoStatement;

// Detektor fuer das `goto`-Statement in Delphi/Pascal-Code.
//
// Warum gemeldet:
//   `goto` und Labels machen den Control-Flow nicht-strukturell - Schleifen,
//   Verschachtelungen und Try-Finally-Bloecke werden schwer auf einen Blick
//   nachvollziehbar. Dijkstra-Argument seit 1968; SonarDelphi-Rule
//   `GotoStatement` ist die direkte Entsprechung. Moderne Delphi-Code-Basen
//   haben praktisch nie einen rechtfertigten goto-Einsatz - selbst
//   "mehrstufiger Break" laesst sich durch eigene Funktion + Exit loesen.
//
// Erkennung:
//   File-basierter Scan analog uWithStatement. Der Parser fasst `goto` aktuell
//   als nkCall + Identifier zusammen, daher zeilenweises Lexen:
//     * Pascal-String-Literale ueberspringen ('...'-Quotes inkl. ''-Escape)
//     * //-Zeilenkommentar ueberspringen
//     * {...}- und (*...*)-Blockkommentare ueberspringen (mehrzeilig)
//     * Match auf `goto` als ganzes Wort (linke + rechte Wortgrenze)
//
// Schweregrad: lsWarning. Kein Bug per se aber starker Maintainability-
// Schmerz. Suppression ueber `// noinspection` direkt vor der Zeile.
//
// SonarDelphi-Mapping: communitydelphi:GotoStatement (legacy MAJOR /
// MQR MAINTAINABILITY-MEDIUM).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TGotoStatementDetector = class
  public
    // UnitNode wird nicht verwendet - File-Scan. Signatur bleibt aus
    // Konsistenz mit den anderen Detektoren (RunAllDetectors-Closure).
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,                 // PosEx
  uFileTextCache;

const
  KW           = 'goto';
  KW_LEN       = 4;
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Findet die 1-basierte Spalte des ersten top-level `goto`-Keywords in der
// Zeile (ausserhalb String-Literal, ausserhalb {..}/(*..*)/// und mit
// beidseitiger Wortgrenze). 0 wenn keines.
//
// InBlockComm + InParenStarComm werden vom Caller ueber Zeilen hinweg
// mitgefuehrt - True wenn die Zeile innerhalb eines noch offenen {...} bzw.
// (*...*) startet bzw. am Zeilenende noch offen bleibt.
function FindGoto(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n   : Integer;
  InStr  : Boolean;
  pClose : Integer;
  c, nx  : Char;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    // {...}-Blockkommentar offen -> bis '}' skippen
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;          // bleibt offen
      InBlockComm := False;
      i := pClose + 1;
      Continue;
    end;
    // (*...*)-Blockkommentar offen -> bis '*)' skippen
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2;
      Continue;
    end;
    c := Line[i];
    // String-Literal: '...' mit ''-Escape
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then
          Inc(i, 2)
        else
        begin
          InStr := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
      Continue;
    end;
    if c = '''' then
    begin
      InStr := True;
      Inc(i);
      Continue;
    end;
    // //-Zeilenkommentar -> Rest der Zeile ignorieren
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    // {-Blockkommentar
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then
      begin
        InBlockComm := True;
        Exit;
      end;
      i := pClose + 1;
      Continue;
    end;
    // (*-Blockkommentar
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then
      begin
        InParenStarComm := True;
        Exit;
      end;
      i := pClose + 2;
      Continue;
    end;
    // `goto`-Match: case-insensitive, beidseitige Wortgrenze.
    // CharInSet statt c in [...] - WideChar (= Char in Unicode-Delphi) waere
    // sonst implizit auf ByteChar verkuerzt (W1050).
    if CharInSet(c, ['g','G']) and (i + KW_LEN - 1 <= n) and
       SameText(Copy(Line, i, KW_LEN), KW) then
    begin
      // Linke Wortgrenze: vorheriges Zeichen nicht-ident
      if (i > 1) and IsIdent(Line[i - 1]) then
      begin
        Inc(i);
        Continue;
      end;
      // Rechte Wortgrenze: nachfolgendes Zeichen nicht-ident
      if (i + KW_LEN <= n) then
      begin
        nx := Line[i + KW_LEN];
        if IsIdent(nx) then
        begin
          Inc(i);
          Continue;
        end;
      end;
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TGotoStatementDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines   : TStringList;
  i, Col  : Integer;
  InBlk, InParen : Boolean;
  F       : TLeakFinding;
  Cached  : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindGoto(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        '`goto` weakens structured control flow - refactor to early-Exit, ' +
        'extracted helper, or state-machine instead (col %d).', [Col]);
      F.SetKind(fkGotoStatement);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
