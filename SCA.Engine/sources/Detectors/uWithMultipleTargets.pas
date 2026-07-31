unit uWithMultipleTargets;

// Detektor: `with A, B do ...` mit komma-separierten Targets.
//
// Pattern (Code Smell, klassisches Delphi-Anti-Pattern):
//   with TForm.Create(Self), TStringList.Create do
//   begin
//     Caption := 'X';     // <-- welche Klasse? Reihenfolge entscheidet
//     Add('y');           // <-- TStringList? oder eine Property von TForm?
//   end;
//
// Korrekt: einzelnes with mit explizitem alias, oder ganz ohne with:
//   F := TForm.Create(Self);
//   L := TStringList.Create;
//   try
//     F.Caption := 'X';
//     L.Add('y');
//   finally
//     L.Free;
//     F.Free;
//   end;
//
// Folge: bei `with A, B do` werden Identifiers von rechts nach links
// aufgeloest - der spaeter genannte Operand schattet den frueheren.
// Refactoring-Schmerz: einer der Typen kriegt eine neue Property mit
// gleichem Namen, und plotzlich greift der `with`-Block auf das andere
// Objekt zu. Klassischer mORMot/Legacy-Code-Smell.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pattern: `^\s*with\s+<token>\s*,` - case-insensitive, mind. ein
//     Komma vor dem `do`.
//   * Wir matchen den ANFANG der with-Klausel. Komplexe Argumente
//     (Klammer, Index, Deref) werden tolerant gehandhabt durch
//     Pattern `with\s+[^,]+,[^d]*\bdo\b`.
//
// Klammer-Gate (2026-07-31, Real-World-Audit SCA155):
//   Die Regex allein trennt Targets stumpf am Komma. Damit war
//   `with CL.AddInterface(A, B, 'C') do` - EIN Ziel, dessen Argumentliste
//   Kommas enthaelt - nicht von `with A, B do` unterscheidbar; 8388 von
//   8818 Korpus-Funden waren genau das. Nachgeschaltet laeuft daher eine
//   Klammerbilanz ueber den Kopf der with-Klausel: als Target-Trenner
//   zaehlt nur ein Komma auf Tiefe 0 (runde UND eckige Klammern), und
//   generische Typargumente (`with TDict<K,V>.Create do`) werden als
//   Block uebersprungen. String-Literale sind zu diesem Zeitpunkt schon
//   ausgeblankt, `with Foo('a,b') do` kann also gar nicht mehr splitten.
//   Bleibt der Kopf unentscheidbar (kein `do` auf Tiefe 0 im Fenster,
//   unbalancierte Klammern), bleibt der Fund stehen - der Filter darf nur
//   entfernen, nie hinzufuegen.
//
// Limitierungen:
//   * Rein lexikalisch: die Klammerbilanz ersetzt keinen Parser, sie
//     entscheidet nur ueber die Kommas im with-Kopf.
//
// Schweregrad: lsHint - Stil-Empfehlung, kein direkter Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TWithMultipleTargetsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

function IsWordCh(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '&']);
end;

function SkipGenericArgs(const Code: string; StartPos, Limit: Integer): Integer;
// Code[StartPos] ist '<'. Liefert die Position NACH dem passenden '>',
// wenn der Bereich wie eine Typargumentliste aussieht (nur Bezeichner,
// Komma, Punkt, Index-Klammern, Whitespace, verschachtelte <>), sonst 0.
// Konservativ: im Zweifel 0, dann zaehlt das '<' als gewoehnliches Zeichen
// und ein folgendes Komma bleibt Target-Trenner (Fund bleibt stehen).
var
  i     : Integer;
  Depth : Integer;
  C     : Char;
begin
  Result := 0;
  Depth  := 0;
  i      := StartPos;
  while i <= Limit do
  begin
    C := Code[i];
    if C = '<' then
      Inc(Depth)
    else if C = '>' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(i + 1);
    end
    else if not (IsWordCh(C) or
                 CharInSet(C, [',', '.', '[', ']', ' ', #9, #10, #13])) then
      Exit(0);
    Inc(i);
  end;
end;

function HasTopLevelTargetComma(const Code: string;
  WithPos, Limit: Integer): Boolean;
// WithPos zeigt auf das 'w' von `with`. True = im Kopf der with-Klausel
// steht vor dem `do` ein Komma auf Klammertiefe 0 (= echtes Multi-Target)
// ODER der Kopf ist nicht entscheidbar (dann bleibt es beim alten
// Verhalten). False = genau ein Ziel, dessen Kommas in Argument-, Index-
// oder Typargumentlisten liegen.
var
  i, G  : Integer;
  Depth : Integer;
  N     : Integer;
  C     : Char;
begin
  Result := True;
  Depth  := 0;
  N      := Length(Code);
  i      := WithPos + 4;              // hinter das Schluesselwort `with`
  while i <= Limit do
  begin
    C := Code[i];
    if CharInSet(C, ['(', '[']) then
      Inc(Depth)
    else if CharInSet(C, [')', ']']) then
    begin
      // Eine ueberzaehlige schliessende Klammer darf die Tiefe nicht
      // negativ machen - sonst wuerde ein spaeteres Argument-Komma faelsch
      // als Trenner gelesen.
      if Depth > 0 then Dec(Depth);
    end
    else if (C = '<') and (Depth = 0) and (i > 1) and IsWordCh(Code[i - 1]) then
    begin
      G := SkipGenericArgs(Code, i, Limit);
      if G > 0 then
      begin
        i := G;
        Continue;
      end;
    end
    else if Depth = 0 then
    begin
      if C = ',' then Exit(True);     // echtes zweites Target
      if C = ';' then Exit(True);     // Kopf endet unerwartet -> unentschieden
      if CharInSet(C, ['d', 'D']) and (i < N) and
         CharInSet(Code[i + 1], ['o', 'O']) and
         ((i = 1) or not IsWordCh(Code[i - 1])) and
         ((i + 2 > N) or not IsWordCh(Code[i + 2])) then
        Exit(False);                  // `do` erreicht, kein Trenner gesehen
    end;
    Inc(i);
  end;
end;

class procedure TWithMultipleTargetsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  LineNo   : Integer;
  Limit    : Integer;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' ');

    // Pattern: `with <target>, <target> ... do` - mit mindestens einem
    // Komma zwischen den Targets vor dem do-Keyword. Wir limitieren den
    // Scan-Bereich vor dem `do` damit nicht ein Komma in nachfolgendem
    // Code matched. Multiline-Match aktiviert.
    RE := TRegEx.Create(
      '(?ism)\bwith\s+[^,;{}\r\n]{1,200},\s*[^;{}]{1,200}\bdo\b');
    for M in RE.Matches(Code) do
    begin
      // Klammer-Gate: Kommas in Argument-, Index- oder Typargumentlisten
      // sind keine Target-Trenner. Fenster = Regex-Treffer plus kleiner
      // Nachlauf; der Anker (M.Index) bleibt unberuehrt, es faellt nur weg.
      Limit := M.Index + M.Length + 16;
      if Limit > Length(Code) then Limit := Length(Code);
      if not HasTopLevelTargetComma(Code, M.Index, Limit) then Continue;

      LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar :=
        '`with A, B do` resolves identifiers right-to-left - shadowing changes silently if either type adds a member';
      F.SetKind(fkWithMultipleTargets);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
