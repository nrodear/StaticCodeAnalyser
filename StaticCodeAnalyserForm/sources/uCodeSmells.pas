unit uCodeSmells;

// Erkennt Code-Smells jenseits von Speicherlecks.
//
// TEmptyExceptDetector:
//   Sucht nach leeren except-Bloecken, die Exceptions stillschweigend
//   verschlucken (Silent Exception Swallowing).
//
//   Als "leer" gilt ein except-Block wenn zwischen 'except' und dem
//   zugehoerigen 'end' ausschliesslich Kommentare oder Leerzeilen stehen.
//
//   Ergebnis: TSmellFinding mit Zeilennummer des 'except'-Tokens.

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, uSCAConsts;

type
  TSmellFinding = class
  public
    LineNumber: Integer;   // 1-basiert, Zeile des 'except'
    Description: string;
    Severity: TLeakSeverity;
  end;

  TEmptyExceptDetector = class
  public
    // Analysiert kompletten Dateiinhalt (lines, lowercased).
    // Fuegt TSmellFinding-Objekte fuer jeden leeren except-Block ein.
    class procedure Detect(lines: TStringList;
      results: TObjectList<TSmellFinding>);

  private
    class function StripComment(const line: string): string; static;
    class function IsIdent(c: Char): Boolean; static;
    class function KwStart(const line, kw: string): Boolean; static;
  end;

implementation

class function TEmptyExceptDetector.IsIdent(c: Char): Boolean;
begin
  Result := CharInSet(c, ['a'..'z', '0'..'9', '_']);
end;

class function TEmptyExceptDetector.StripComment(const line: string): string;
var
  p: Integer;
begin
  p := Pos('//', line);
  if p > 1 then
    Result := Trim(Copy(line, 1, p - 1))
  else if p = 1 then
    Result := ''
  else
    Result := line;
end;

class function TEmptyExceptDetector.KwStart(const line, kw: string): Boolean;
var
  kLen: Integer;
begin
  kLen := Length(kw);
  if Length(line) < kLen then Exit(False);
  if not CompareMem(PChar(line), PChar(kw), kLen * SizeOf(Char)) then Exit(False);
  if Length(line) = kLen then Exit(True);
  Result := not IsIdent(line[kLen + 1]);
end;

class procedure TEmptyExceptDetector.Detect(lines: TStringList;
  results: TObjectList<TSmellFinding>);
var
  i, j, depth: Integer;
  line: string;
  hasCode: Boolean;
  sf: TSmellFinding;
begin
  for i := 0 to lines.Count - 1 do
  begin
    line := StripComment(Trim(lines[i]));

    if not KwStart(line, 'except') then Continue;

    // 'except' gefunden -- vorwaerts scannen bis passendes 'end'
    depth   := 0;
    hasCode := False;

    for j := i + 1 to lines.Count - 1 do
    begin
      line := StripComment(Trim(lines[j]));
      if line = '' then Continue;

      // Tiefe erhoehen
      if KwStart(line, 'begin') or KwStart(line, 'try') or
         KwStart(line, 'repeat') or
         (KwStart(line, 'case') and (Pos(' of', line) > 0)) then
        Inc(depth)

      else if KwStart(line, 'end') then
      begin
        if depth = 0 then
          Break   // passendes end gefunden
        else
          Dec(depth);
      end

      else if KwStart(line, 'until') then
      begin
        if depth > 0 then Dec(depth);
      end

      // 'on E: Exception do ...' oder anderer except-Handler = nicht leer
      else if KwStart(line, 'on ') or KwStart(line, 'raise') or
              KwStart(line, 'else') then
        hasCode := True

      else
        hasCode := True;  // irgendeine Anweisung

      if hasCode then Break;
    end;

    if not hasCode then
    begin
      sf             := TSmellFinding.Create;
      sf.LineNumber  := i + 1;  // 1-basiert
      sf.Description := 'Leerer except-Block (Exception wird verschluckt)';
      sf.Severity    := lsWarning;
      results.Add(sf);
    end;
  end;
end;

end.
