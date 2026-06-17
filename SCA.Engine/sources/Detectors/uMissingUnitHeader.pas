unit uMissingUnitHeader;

// Detektor: Unit beginnt ohne erklaerenden Kommentar-Block.
//
// Pattern (Code Smell, Sonar-50 #48):
//   unit MyUnit;
//
//   interface                       // <-- direkt zur Sache, kein Kommentar
//
//   uses ...;
//
// Korrekt:
//   unit MyUnit;
//
//   // Diese Unit verwaltet die Verbindung zur Datenbank. Sie kapselt
//   // die FireDAC-Connection-Pool-Logik und liefert eine schmale API
//   // fuer hoehere Layer.
//
//   interface
//
// Erkennung (Lexer/Lines):
//   * Lies Zeilen bis zum ersten `interface`-Keyword.
//   * Erwarte mindestens EINE nicht-leere Kommentarzeile (`//` oder
//     `{ ... }` oder `(* ... *)`) zwischen `unit X;` und `interface`.
//   * Falls keine Kommentarzeile -> Finding auf Zeile 1.
//
// Limitierungen:
//   * Multi-line block-comments mit { kombiniert mit Code in einer Zeile
//     werden grob erkannt - kein voller Lexer.
//   * Generated-code-Marker (`{ ... do not edit ... }`) zaehlen mit.
//
// Schweregrad: lsHint - Empfehlung, viele Legacy-Units haben kein Header.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMissingUnitHeaderDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CyclomaticComplexity, GroupedDeclaration, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

function LineHasComment(const ALine: string): Boolean;
var
  T : string;
begin
  T := Trim(ALine);
  Result := (T <> '')
            and ((Copy(T, 1, 2) = '//')
                 or (Copy(T, 1, 1) = '{')
                 or (Copy(T, 1, 2) = '(*'));
end;

function LineIsUnitDecl(const ALine: string): Boolean;
var
  T : string;
begin
  T := LowerCase(Trim(ALine));
  Result := Copy(T, 1, 5) = 'unit ';
end;

function LineIsInterface(const ALine: string): Boolean;
var
  T : string;
begin
  T := LowerCase(Trim(ALine));
  Result := (T = 'interface') or (Copy(T, 1, 10) = 'interface ');
end;

class procedure TMissingUnitHeaderDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  Cached : Boolean;
  i, UnitLine, IfaceLine : Integer;
  HasComment : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    UnitLine  := -1;
    IfaceLine := -1;
    for i := 0 to Lines.Count - 1 do
    begin
      if (UnitLine < 0) and LineIsUnitDecl(Lines[i]) then
        UnitLine := i;
      if LineIsInterface(Lines[i]) then
      begin
        IfaceLine := i;
        Break;
      end;
    end;
    if (UnitLine < 0) or (IfaceLine < 0) then Exit;

    HasComment := False;
    for i := UnitLine + 1 to IfaceLine - 1 do
      if LineHasComment(Lines[i]) then
      begin
        HasComment := True;
        Break;
      end;
    if HasComment then Exit;

    Results.Add(TLeakFinding.New(FileName, '', UnitLine + 1,
      'Unit has no descriptive header comment between `unit ...;` and `interface`',
      fkMissingUnitHeader));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
