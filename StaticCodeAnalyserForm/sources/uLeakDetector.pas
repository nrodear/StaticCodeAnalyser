unit uLeakDetector;

// Verbesserter Speicherleck-Detektor mit flow-basierter Analyse.
//
// Gegenueber dem einfachen String-Suche-Ansatz erkennt dieser Detektor:
//   1. Nur lokal erstellte Objekte (HasCreateCall) -- vermeidet false positives
//      bei Parametern und Feldern, die woanders erstellt wurden.
//   2. Ob das Free/FreeAndNil innerhalb eines try/finally-Blocks liegt:
//        lsError   = Objekt erstellt, aber nie freigegeben
//        lsWarning = Objekt freigegeben, aber NICHT in try/finally
//                    (Exception vor dem Free wuerde noch ein Leck verursachen)
//
// Algorithmus fuer try/finally-Erkennung (ExtractFinallyRanges):
//   - Fuer jede 'finally'-Zeile wird vorwaerts gescannt.
//   - Verschachtelung wird durch einen Tiefenzaehler verfolgt:
//     begin/try/case..of/repeat erhoehen die Tiefe,
//     end verringert sie (oder schliesst den finally-Block bei Tiefe 0).
//   - Inline-Kommentare werden vor der Auswertung entfernt.

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, uSCAConsts;

type
  // Zwischenergebnis des Detektors (pro Variable)
  TLeakResult = class
  public
    VarName:  string;
    Severity: TLeakSeverity;
  end;

  TLeakDetector = class
  public
    // Analysiert einen Methodenrumpf (body-Zeilen muessen lowercase sein).
    // Fuegt gefundene Lecks als TLeakResult-Objekte in results ein.
    class procedure Detect(
      const varName: string;
      body: TStringList;
      results: TObjectList<TLeakResult>
    );

    // Performance-Variante fuer mehrere Variablen desselben Methodenrumpfs:
    // ExtractFinallyRanges und body.Text werden nur EINMAL berechnet.
    class procedure DetectAll(
      const varNames: TStringList;
      body: TStringList;
      results: TObjectList<TLeakResult>
    );

    // Gibt alle (startIdx, endIdx)-Paare fuer finally-Bloecke zurueck.
    // Public damit ParseFilesAllClasses das Ergebnis cachen kann.
    class function ExtractFinallyRanges(body: TStringList):
      TArray<TPair<Integer, Integer>>;

    // Prueft ob 'line' mit dem Schluesselwort 'kw' beginnt (Wortgrenze)
    class function KwStart(const line, kw: string): Boolean; static; inline;

    // Prueft ob 'line' mit dem Schluesselwort 'kw' endet (Wortgrenze)
    class function KwEnd(const line, kw: string): Boolean; static; inline;

    // Entfernt '//' Inline-Kommentare (vereinfacht, ignoriert Strings)
    class function StripComment(const line: string): string; static; inline;

    // Prueft ob 'varName := SomeClass.Create' im body vorkommt
    class function HasCreateCall(const varName: string; body: TStringList): Boolean;

    // Prueft ob 'varName := SomeFunctionCall' (kein .create, kein Feldzugriff via '.')
    class function HasAssignFromCall(const varName: string; body: TStringList): Boolean;

    // Gibt den Zeilenindex der ersten Free/FreeAndNil-Zeile zurueck, -1 wenn nicht gefunden
    class function FindFreeLine(const varName: string; body: TStringList): Integer;

    // Prueft ob Zeile lineIdx innerhalb eines try/finally-Blocks liegt (body-Scan)
    class function IsInFinallyBlock(lineIdx: Integer; body: TStringList): Boolean;

    // Prueft ob lineIdx in vorberechneten Ranges liegt (ohne Body-Scan)
    class function IsInFinallyRange(lineIdx: Integer;
      const ranges: TArray<TPair<Integer, Integer>>): Boolean; static;

    // Kern-Logik mit uebergebenen Ranges + bodyText (kein Recompute)
    class procedure DetectCore(
      const lowerVar, origVar, bodyText: string;
      body: TStringList;
      const ranges: TArray<TPair<Integer, Integer>>;
      results: TObjectList<TLeakResult>);

    // Prueft ob varName als Argument an inherited Create oder eine
    // andere Create-Methode uebergeben wird (Ownership-Transfer).
    class function HasPassedToConstructor(const varName: string;
      body: TStringList): Boolean;

    // Prueft ob c ein Bezeichner-Zeichen ist (lowercase body)
    class function IsIdent(c: Char): Boolean; static; inline;
  end;

implementation

{ TLeakDetector }

class function TLeakDetector.IsIdent(c: Char): Boolean;
begin
  Result := CharInSet(c, ['a'..'z', '0'..'9', '_']);
end;

class function TLeakDetector.StripComment(const line: string): string;
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

class function TLeakDetector.KwStart(const line, kw: string): Boolean;
var
  kLen: Integer;
begin
  kLen := Length(kw);
  if Length(line) < kLen then
    Exit(False);
  if not CompareMem(PChar(line), PChar(kw), kLen * SizeOf(Char)) then
    Exit(False);
  if Length(line) = kLen then
    Exit(True);
  Result := not IsIdent(line[kLen + 1]);
end;

class function TLeakDetector.KwEnd(const line, kw: string): Boolean;
var
  kLen, lLen, startPos: Integer;
begin
  kLen := Length(kw);
  lLen := Length(line);
  if lLen < kLen then
    Exit(False);
  startPos := lLen - kLen + 1;
  if not CompareMem(PChar(line) + (startPos - 1) * SizeOf(Char),
                    PChar(kw), kLen * SizeOf(Char)) then
    Exit(False);
  if startPos = 1 then
    Exit(True);
  Result := not IsIdent(line[startPos - 1]);
end;

class function TLeakDetector.HasCreateCall(const varName: string;
  body: TStringList): Boolean;
var
  line          : string;
  posVar        : Integer;
  posAssign     : Integer;
  rightBound    : Integer;
begin
  Result := False;
  for line in body do
  begin
    posVar    := Pos(varName, line);
    if posVar = 0 then Continue;
    posAssign := Pos(':=', line);
    if (posAssign = 0) or (posAssign < posVar) then Continue;
    if Pos('.create', line) = 0 then Continue;
    // Wortgrenze links
    if (posVar > 1) and IsIdent(line[posVar - 1]) then Continue;
    // Wortgrenze rechts – verhindert false positives bei Präfixen (z. B. VarNamesOld)
    rightBound := posVar + Length(varName);
    if (rightBound <= Length(line)) and IsIdent(line[rightBound]) then Continue;
    Result := True;
    Exit;
  end;
end;

// Erkennt "varName := SomeFuncCall" oder "varName := SomeFuncCall(...)".
// RHS darf keinen '.' enthalten (kein Feldzugriff, kein direktes .Create).
// Liefert True wenn die Variable von einem moeglichen Funktionsaufruf befullt wird.
class function TLeakDetector.HasAssignFromCall(const varName: string;
  body: TStringList): Boolean;
var
  line, rhs  : string;
  posVar     : Integer;
  posAssign  : Integer;
  rightBound : Integer;
begin
  Result := False;
  for line in body do
  begin
    posVar := Pos(varName, line);
    if posVar = 0 then Continue;
    // Wortgrenze links
    if (posVar > 1) and IsIdent(line[posVar - 1]) then Continue;
    // Wortgrenze rechts
    rightBound := posVar + Length(varName);
    if (rightBound <= Length(line)) and IsIdent(line[rightBound]) then Continue;
    posAssign := Pos(':=', line);
    if (posAssign = 0) or (posAssign < posVar) then Continue;
    // RHS: alles nach ':=', fuehrendes/abschliessendes Whitespace + Semikolon
    rhs := Trim(Copy(line, posAssign + 2, MaxInt));
    if (rhs <> '') and (rhs[Length(rhs)] = ';') then
      rhs := Trim(Copy(rhs, 1, Length(rhs) - 1));
    if rhs = '' then Continue;
    // Kein Punkt im RHS = kein Feld-/Klassenzugriff (z.B. Self.FList)
    // '.create' waere bereits von HasCreateCall abgedeckt
    if Pos('.', rhs) > 0 then Continue;
    // Kein Array-Index im RHS (z.B. AList[i], FItems[0]) -- kein Ownership-Transfer
    if Pos('[', rhs) > 0 then Continue;
    // Mindestens ein Bezeichner-Zeichen -- sieht nach Funktionsaufruf aus
    if IsIdent(rhs[1]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TLeakDetector.FindFreeLine(const varName: string;
  body: TStringList): Integer;
var
  i     : Integer;
  line  : string;
  pFree : Integer;
begin
  Result := -1;
  for i := 0 to body.Count - 1 do
  begin
    line := body[i];

    // varName.Free / varName.Destroy — Wortgrenze links prüfen
    pFree := Pos(varName + '.free', line);
    if pFree > 0 then
    begin
      if (pFree = 1) or not IsIdent(line[pFree - 1]) then
      begin
        Result := i;
        Exit;
      end;
    end;

    pFree := Pos(varName + '.destroy', line);
    if pFree > 0 then
    begin
      if (pFree = 1) or not IsIdent(line[pFree - 1]) then
      begin
        Result := i;
        Exit;
      end;
    end;

    // FreeAndNil(varName) — exakte Wortgrenze durch Klammer gesichert
    if Pos('freeandnil(' + varName + ')', line) > 0 then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

class function TLeakDetector.ExtractFinallyRanges(body: TStringList):
  TArray<TPair<Integer, Integer>>;
var
  i, j, depth: Integer;
  line: string;
  ranges: TList<TPair<Integer, Integer>>;
begin
  ranges := TList<TPair<Integer, Integer>>.Create;
  try
    for i := 0 to body.Count - 1 do
    begin
      line := StripComment(Trim(body[i]));
      if not KwStart(line, 'finally') then Continue;

      // 'finally' gefunden -- passendes 'end' vorwaerts suchen
      depth := 0;
      for j := i + 1 to body.Count - 1 do
      begin
        line := StripComment(Trim(body[j]));

        // Tiefe erhoehen: begin (standalone oder am Zeilenende), try, case..of, repeat
        if KwStart(line, 'begin') or KwEnd(line, 'begin') or
           KwStart(line, 'try')   or
           KwStart(line, 'repeat') or
           (KwStart(line, 'case') and (Pos(' of', line) > 0)) then
          Inc(depth)

        // 'end' -- schliesst aktuellen Block
        else if KwStart(line, 'end') then
        begin
          if depth = 0 then
          begin
            ranges.Add(TPair<Integer, Integer>.Create(i, j));
            Break;
          end
          else
            Dec(depth);
        end

        // 'until' -- schliesst repeat-Block
        else if KwStart(line, 'until') then
        begin
          if depth > 0 then Dec(depth);
        end;
      end;
    end;
    Result := ranges.ToArray;
  finally
    ranges.Free;
  end;
end;

class function TLeakDetector.IsInFinallyBlock(lineIdx: Integer;
  body: TStringList): Boolean;
var
  ranges: TArray<TPair<Integer, Integer>>;
  r: TPair<Integer, Integer>;
begin
  Result := False;
  ranges := ExtractFinallyRanges(body);
  for r in ranges do
    if (lineIdx > r.Key) and (lineIdx < r.Value) then
      Exit(True);
end;

class function TLeakDetector.IsInFinallyRange(lineIdx: Integer;
  const ranges: TArray<TPair<Integer, Integer>>): Boolean;
var
  r: TPair<Integer, Integer>;
begin
  Result := False;
  for r in ranges do
    if (lineIdx > r.Key) and (lineIdx < r.Value) then
      Exit(True);
end;

// Kern-Logik: benutzt vorberechnete ranges + bodyText -- kein Body-Scan Recompute
class function TLeakDetector.HasPassedToConstructor(const varName: string;
  body: TStringList): Boolean;
var
  line     : string;
  pCreate  : Integer;
  pVar     : Integer;
  afterParen: string;
  absPos   : Integer;
begin
  // varName und body sind beide lowercase.
  Result := False;
  for line in body do
  begin
    // Muster 1: inherited create(varname ...)
    if (Pos('inherited', line) > 0) and (Pos('create(', line) > 0) then
    begin
      pCreate    := Pos('create(', line);
      afterParen := Copy(line, pCreate + 7, MaxInt);
      pVar       := Pos(varName, afterParen);
      if pVar > 0 then
      begin
        absPos := pCreate + 7 + pVar - 1;
        // Wortgrenze links
        if (absPos <= 1) or not IsIdent(line[absPos - 1]) then
          Exit(True);
      end;
    end;

    // Muster 2: AnyClass.Create(varname, ...) -- varname ist NICHT LHS
    //   z.B. TStreamWriter.Create(fileStream, ...)
    if Pos('.create(', line) > 0 then
    begin
      pCreate    := Pos('.create(', line);
      afterParen := Copy(line, pCreate + 8, MaxInt);
      pVar       := Pos(varName, afterParen);
      if pVar > 0 then
      begin
        absPos := pCreate + 8 + pVar - 1;
        // Wortgrenze links und rechts
        var leftOk  := (absPos <= 1) or not IsIdent(line[absPos - 1]);
        var rightEnd := absPos + Length(varName);
        var rightOk := (rightEnd > Length(line)) or not IsIdent(line[rightEnd]);
        if leftOk and rightOk then
        begin
          // Sicherstellen: varname steht nicht auf der LHS einer Zuweisung
          var posAssign := Pos(':=', line);
          var posVarAbs := Pos(varName, line);
          if (posAssign = 0) or (posVarAbs > posAssign) then
            Exit(True);
        end;
      end;
    end;
  end;
end;

class procedure TLeakDetector.DetectCore(
  const lowerVar, origVar, bodyText: string;
  body: TStringList;
  const ranges: TArray<TPair<Integer, Integer>>;
  results: TObjectList<TLeakResult>);
var
  freeLine: Integer;
  lr: TLeakResult;
begin
  // Ownership-Transfer 1: result := varName (Funktion gibt Ownership ab)
  if (Pos('result := ' + lowerVar + ';', bodyText) > 0) or
     (Pos('result:='  + lowerVar + ';', bodyText) > 0) then
    Exit;

  // Ownership-Transfer 2: varName wird an inherited Create oder eine
  // andere Create-Methode als Argument uebergeben
  if HasPassedToConstructor(lowerVar, body) then
    Exit;

  if HasCreateCall(lowerVar, body) then
  begin
    freeLine := FindFreeLine(lowerVar, body);
    if freeLine = -1 then
    begin
      lr := TLeakResult.Create;
      lr.VarName  := origVar;
      lr.Severity := lsError;
      results.Add(lr);
    end
    else if not IsInFinallyRange(freeLine, ranges) then
    begin
      // Warnung nur wenn die Methode ueberhaupt try/finally hat.
      // Hat die Methode kein try/finally, ist "Create → use → Free" ein
      // akzeptiertes Muster (z.B. Test-Methoden, einfache Hilfsfunktionen).
      if Length(ranges) > 0 then
      begin
        lr := TLeakResult.Create;
        lr.VarName  := origVar;
        lr.Severity := lsWarning;
        results.Add(lr);
      end;
    end;
  end
  else if HasAssignFromCall(lowerVar, body) then
  begin
    freeLine := FindFreeLine(lowerVar, body);
    if freeLine = -1 then
    begin
      lr := TLeakResult.Create;
      lr.VarName  := origVar;
      lr.Severity := lsWarning;
      results.Add(lr);
    end;
  end;
end;

class procedure TLeakDetector.Detect(const varName: string;
  body: TStringList; results: TObjectList<TLeakResult>);
begin
  // Kompatibilitaets-Wrapper: berechnet ranges + bodyText einmalig
  DetectCore(
    varName.ToLower, varName,
    body.Text,
    body,
    ExtractFinallyRanges(body),
    results);
end;

// Performance-Variante: ranges + bodyText werden nur EINMAL pro Methodenrumpf berechnet
class procedure TLeakDetector.DetectAll(const varNames: TStringList;
  body: TStringList; results: TObjectList<TLeakResult>);
var
  ranges  : TArray<TPair<Integer, Integer>>;
  bodyText: string;
  varName : string;
begin
  if varNames.Count = 0 then Exit;
  ranges   := ExtractFinallyRanges(body);  // einmalig
  bodyText := body.Text;                   // einmalig
  for varName in varNames do
    DetectCore(varName.ToLower, varName, bodyText, body, ranges, results);
end;

end.
