unit uFreeAndNilHint;

// Detektor fuer manuelles `X.Free; X := nil;` Pattern.
//
// SonarDelphi-Aequivalent: communitydelphi:FreeAndNil. `FreeAndNil(X)`
// macht beides atomar und ist die kanonische Delphi-Idiom. Manuelles
// `X.Free; X := nil;` ist:
//   * Zwei statt einer Zeile (mehr Diff-Noise)
//   * Falls dazwischen eine Exception fliegt (z.B. in destructor),
//     bleibt X nicht-nil aber zeigt auf invaliden Speicher.
//   * Spaetere Refactors verschieben das `:= nil` nicht mit -> Dangling-
//     Pointer-Risiko.
//
// Erkennung: zwei aufeinanderfolgende Statements auf benachbarten
// Zeilen, die `X.Free;` und `X := nil;` (gleicher Identifier `X`) zeigen.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TFreeAndNilHintDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LengthUnderflow, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  // Voll-Review 2026-09-12: Zeichenklasse zentralisiert - die lokale
  // Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentStartChar (A..Z, a..z, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentStartChar(C);
end;

// Extract the receiver of `<Receiver>.Free` from a line. Returns receiver
// name or empty if no match.
function ExtractFreeReceiver(const Line: string): string;
var
  trimmed : string;
  i, n    : Integer;
  Start   : Integer;
begin
  Result := '';
  trimmed := TrimLeft(Line);
  n := Length(trimmed);
  if n = 0 then Exit;
  if not IsIdentStart(trimmed[1]) then Exit;
  i := 1;
  Start := 1;
  while (i <= n) and IsIdent(trimmed[i]) do Inc(i);
  if (i > n) or (trimmed[i] <> '.') then Exit;
  var Receiver: string;
  Receiver := Copy(trimmed, Start, i - Start);
  Inc(i);
  // optional whitespace
  while (i <= n) and CharInSet(trimmed[i], [' ', #9]) do Inc(i);
  // expect "Free"
  if (i + 3 > n + 1) then Exit;
  if not SameText(Copy(trimmed, i, 4), 'Free') then Exit;
  if (i + 4 <= n) and IsIdent(trimmed[i + 4]) then Exit;
  Inc(i, 4);
  // optional whitespace then `;`
  while (i <= n) and CharInSet(trimmed[i], [' ', #9]) do Inc(i);
  if (i > n) or (trimmed[i] <> ';') then Exit;
  Result := Receiver;
end;

// Pruefe ob Line `<Receiver> := nil;` (mit optionalem Whitespace) ist.
function IsAssignNil(const Line, Receiver: string): Boolean;
var
  trimmed : string;
  i, n    : Integer;
  Word    : string;
begin
  Result := False;
  trimmed := TrimLeft(Line);
  n := Length(trimmed);
  if n = 0 then Exit;
  i := 1;
  while (i <= n) and IsIdent(trimmed[i]) do Inc(i);
  Word := Copy(trimmed, 1, i - 1);
  if not SameText(Word, Receiver) then Exit;
  while (i <= n) and CharInSet(trimmed[i], [' ', #9]) do Inc(i);
  if (i + 1 > n) then Exit;
  if (trimmed[i] <> ':') or (trimmed[i + 1] <> '=') then Exit;
  Inc(i, 2);
  while (i <= n) and CharInSet(trimmed[i], [' ', #9]) do Inc(i);
  if (i + 2 > n) then Exit;
  if not SameText(Copy(trimmed, i, 3), 'nil') then Exit;
  if (i + 3 <= n) and IsIdent(trimmed[i + 3]) then Exit;
  Result := True;
end;

class procedure TFreeAndNilHintDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Code     : TStringList;
  State    : TCommentScanState;
  DummyCol : Integer;
  i        : Integer;
  Cached   : Boolean;
  Receiver : string;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  Code := TStringList.Create;
  try
    // Auf KOMMENTARBEREINIGTEN Zeilen matchen (Voll-Review 2026-09-12,
    // Blocker): der Roh-Scan meldete das Muster auch in mehrzeilig
    // auskommentiertem Alt-Code ('{ Alte Version: FConn.Free; ... }').
    // ScanCodeLine blankt zudem String-Literale - 'FConn.Free' in
    // einem Log-Text zaehlt nicht. State traegt offene Bloecke ueber
    // Zeilen; die Zeilen-Indizes bleiben 1:1 erhalten.
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
      Code.Add(TDetectorUtils.ScanCodeLine(Lines[i], State, DummyCol));
    for i := 0 to Code.Count - 2 do
    begin
      Receiver := ExtractFreeReceiver(Code[i]);
      if Receiver = '' then Continue;
      if not IsAssignNil(Code[i + 1], Receiver) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        '`%s.Free; %s := nil;` - prefer `FreeAndNil(%s)` (atomic and ' +
        'avoids dangling pointer if Free raises).',
        [Receiver, Receiver, Receiver]);
      F.SetKind(fkFreeAndNilHint);
      Results.Add(F);
    end;
  finally
    Code.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
