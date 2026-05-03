unit uFormatMismatch;

// AST-basierter Detektor für Format()-Argument-Fehler (Sonar-Regel #9).
//
// Erkennt nkCall-Knoten vom Typ Format(...) bei denen die Anzahl der
// Platzhalter im Format-String nicht mit der Anzahl der Array-Argumente
// übereinstimmt.
//
// Erkannte Platzhalter: %s %d %i %u %e %f %g %n %m %p %c %x
//   %% wird als Escape behandelt (zählt NICHT als Argument)
//
// Beispiele:
//   Format('%s = %d', [name])         → 2 Platzhalter, 1 Argument  → Fehler
//   Format('%s', [a, b])              → 1 Platzhalter, 2 Argumente → Fehler
//   Format('%s = %d', [name, value])  → kein Befund
//   Format('Keine Platzhalter')       → kein Befund (0 = 0)
//
// Hinweis: Positionale Parameter (%0:s) werden als einfache %- Zählung behandelt.
//   Für übliche sequenzielle Aufrufe ist das Ergebnis korrekt.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TFormatMismatchDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Prüft ob CallName ein Format()-Aufruf ist und extrahiert den Format-String.
    // FmtEnd zeigt auf die Position im CallName direkt nach dem schließenden Quote.
    class function TryExtractFormatString(const CallName: string;
      out FmtStr: string; out FmtEnd: Integer): Boolean; static;

    // Zählt Platzhalter im Format-String (%s, %d, … aber nicht %%).
    class function CountPlaceholders(const FmtStr: string): Integer; static;

    // Zählt die Argumente im Delphi-Open-Array ab Position StartPos.
    // Erwartet '[arg1,arg2,...]' im Text.
    class function CountArrayArgs(const Text: string;
      StartPos: Integer): Integer; static;
  end;

implementation

{ ---- Hilfsfunktionen ---- }

class function TFormatMismatchDetector.TryExtractFormatString(
  const CallName: string; out FmtStr: string; out FmtEnd: Integer): Boolean;
var
  Low  : string;
  Pos_ : Integer;
  i    : Integer;
begin
  Result := False;
  FmtStr := '';
  FmtEnd := 0;

  Low  := CallName.ToLower;
  Pos_ := Pos('format(', Low);
  if Pos_ = 0 then Exit;

  // Vorgaenger-Pruefung: Format( darf nicht Teil eines laengeren Bezeichners
  // sein (z.B. 'MyFormat(' oder 'StringFormat('). Alles was KEIN Identifier-
  // Char ist, ist erlaubt - das deckt sowohl 'SysUtils.Format' (Punkt davor)
  // als auch ' Format' (nach Whitespace / := / +) und 'Result(Format(...))'
  // (verschachtelt, klamerumgeben).
  // Vorher: Filter erlaubte NUR '.' als Vorgaenger - 'Result := Format(...)'
  // wurde uebersehen.
  // IsIdentChar via TDetectorUtils ist case-insensitive - sollte das Original
  // mal nicht mehr per ToLower normalisiert werden, bleibt der Filter korrekt.
  if Pos_ > 1 then
    if TDetectorUtils.IsIdentChar(Low[Pos_ - 1]) then Exit;

  i := Pos_ + 7; // direkt nach 'format('
  while (i <= Length(CallName)) and (CallName[i] = ' ') do Inc(i);

  // Erster Aufruf-Parameter muss ein Stringliteral sein (opening ')
  if (i > Length(CallName)) or (CallName[i] <> '''') then Exit;

  Inc(i); // skip opening '
  while i <= Length(CallName) do
  begin
    if CallName[i] = '''' then
    begin
      // Doppeltes '' = escaped quote innerhalb des Strings
      if (i < Length(CallName)) and (CallName[i + 1] = '''') then
      begin
        FmtStr := FmtStr + '''';
        Inc(i, 2);
      end
      else
      begin
        FmtEnd := i + 1; // Position nach dem schließenden '
        Exit(True);
      end;
    end
    else
    begin
      FmtStr := FmtStr + CallName[i];
      Inc(i);
    end;
  end;
  // kein schließendes ' gefunden → Format-String nicht vollständig erfasst
end;

class function TFormatMismatchDetector.CountPlaceholders(
  const FmtStr: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  i      := 1;
  while i <= Length(FmtStr) do
  begin
    if FmtStr[i] = '%' then
    begin
      if (i < Length(FmtStr)) and (FmtStr[i + 1] = '%') then
        Inc(i, 2) // %% = kein Platzhalter
      else
      begin
        Inc(Result); // %X = ein Argument
        Inc(i);
        // Restliche Zeichen des Specifiers überspringen (%8.2f, %0:s, …)
        while (i <= Length(FmtStr)) and
              not CharInSet(FmtStr[i], ['s','d','f','e','g','n','m','u',
                                        'c','x','p','i','S','D','F','E',
                                        'G','N','M','U','C','X','P','I']) do
          Inc(i);
        if i <= Length(FmtStr) then Inc(i); // Specifier-Buchstabe überspringen
      end;
    end
    else
      Inc(i);
  end;
end;

class function TFormatMismatchDetector.CountArrayArgs(const Text: string;
  StartPos: Integer): Integer;
var
  i         : Integer;
  Depth     : Integer;
  IsEmpty   : Boolean;
  CommaCount: Integer;
begin
  Result := 0;

  // '[' suchen ab StartPos
  i := StartPos;
  while (i <= Length(Text)) and (Text[i] <> '[') do Inc(i);
  if i > Length(Text) then Exit; // kein Array gefunden → 0 Argumente

  Inc(i); // skip '['
  Depth      := 0;
  IsEmpty    := True;
  CommaCount := 0;

  while i <= Length(Text) do
  begin
    case Text[i] of
      '[', '(' : Inc(Depth);
      ')' : if Depth > 0 then Dec(Depth);
      ']' :
        begin
          if Depth = 0 then
          begin
            if not IsEmpty then
              Result := CommaCount + 1;
            Exit;
          end;
          Dec(Depth);
        end;
      ',' :
        if Depth = 0 then
        begin
          Inc(CommaCount);
          IsEmpty := False;
        end;
    else
      if (Depth = 0) and not CharInSet(Text[i], [' ', #9, #13, #10]) then
        IsEmpty := False;
    end;
    Inc(i);
  end;
end;

{ ---- Öffentliche API ---- }

class procedure TFormatMismatchDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls       : TList<TAstNode>;
  N           : TAstNode;
  FmtStr      : string;
  FmtEnd      : Integer;
  PlaceCount  : Integer;
  ArgCount    : Integer;
  F           : TLeakFinding;
begin
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      if not TryExtractFormatString(N.Name, FmtStr, FmtEnd) then Continue;

      PlaceCount := CountPlaceholders(FmtStr);
      ArgCount   := CountArrayArgs(N.Name, FmtEnd);

      if PlaceCount = ArgCount then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format('Format: %d Platzhalter, %d Argumente',
                             [PlaceCount, ArgCount]);
      F.Severity   := lsError;
      F.Kind       := fkFormatMismatch;
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

class procedure TFormatMismatchDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
