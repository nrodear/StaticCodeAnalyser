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
  uAstNode, uSCAConsts, uMethodd12;

type
  TFreeAndNilHintDetector = class
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

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
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
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  i        : Integer;
  Cached   : Boolean;
  Receiver : string;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 2 do
    begin
      Receiver := ExtractFreeReceiver(Lines[i]);
      if Receiver = '' then Continue;
      if not IsAssignNil(Lines[i + 1], Receiver) then Continue;
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
    ReleaseLines(Lines, Cached);
  end;
end;

end.
