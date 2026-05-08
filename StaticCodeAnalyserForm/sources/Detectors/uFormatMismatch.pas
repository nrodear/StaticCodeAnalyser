unit uFormatMismatch;

// AST-basierter Detektor für Format()-Argument-Fehler (Sonar-Regel #9).
//
// Erkennt nkCall-Knoten zu Format-aequivalenten Funktionen (Format,
// FormatUtf8, FormatString - konfigurierbar via INI [Detectors]
// FormatFunctions) bei denen die Anzahl der Platzhalter im Format-
// String nicht mit der Anzahl der Array-Argumente uebereinstimmt.
//
// Erkannte Platzhalter: %s %d %i %u %e %f %g %n %m %p %c %x
//   %% wird als Escape behandelt (zaehlt NICHT als Argument)
//
// Format-String-Quellen:
//   1. Direktes Stringliteral als 1. Argument:
//        Format('%s = %d', [name, value])
//   2. Identifier-Argument der auf eine Konstante in der gleichen Unit
//      mit String-Wert verweist:
//        const MSG_INVALID = 'invalid %s';
//        Format(MSG_INVALID, [val])
//      Konstanten werden via UnitNode.FindAll(nkConstSection) > nkField
//      aufgeloest, der Wert kommt aus TypeRef nach dem '='-Separator
//      (siehe ParseVarLikeSection).
//
// Beispiele:
//   Format('%s = %d', [name])         -> 2 Platzhalter, 1 Argument  -> Fehler
//   Format('%s', [a, b])              -> 1 Platzhalter, 2 Argumente -> Fehler
//   Format(MSG_INVALID, [a])          -> aufgeloest gegen Const-Tabelle
//   Format('Keine Platzhalter')       -> kein Befund (0 = 0)
//
// Hinweis: Positionale Parameter (%0:s) werden als einfache %-Zaehlung
// behandelt. Fuer uebliche sequenzielle Aufrufe ist das Ergebnis korrekt.

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
      Results: TObjectList<TLeakFinding>;
      ConstTable: TDictionary<string, string>);
  private
    // Prueft ob CallName einen Aufruf einer Format-aequivalenten Funktion
    // enthaelt (siehe DetectorFormatFunctions). Setzt FuncEnd auf die Pos
    // direkt nach der oeffnenden '(' und liefert den ersten Argument-Token
    // (Stringliteral inklusive Anfuehrungszeichen, oder Identifier).
    class function TryExtractCall(const CallName: string;
      out FirstArg: string; out FuncEnd: Integer;
      out ArgsStart: Integer): Boolean; static;

    // Versucht aus dem ersten Argument den Format-String zu rekonstruieren.
    // FirstArg kann sein:
    //   * '...'  - Stringliteral (mit Anfuehrungszeichen) -> direkt
    //              extrahieren (incl. ''-Escape).
    //   * Ident  - Identifier -> in ConstTable nachschlagen, Wert ist
    //              wieder ein '...'-Literal.
    // Liefert False wenn nicht aufloesbar (z.B. Variable, Funktionsaufruf,
    // dynamisch komponiert).
    class function ResolveFormatString(const FirstArg: string;
      ConstTable: TDictionary<string, string>;
      out FmtStr: string): Boolean; static;

    // Zaehlt Platzhalter im Format-String (%s, %d, ... aber nicht %%).
    class function CountPlaceholders(const FmtStr: string): Integer; static;

    // Zaehlt die Argumente im Delphi-Open-Array ab Position StartPos.
    // Erwartet '[arg1,arg2,...]' im Text.
    class function CountArrayArgs(const Text: string;
      StartPos: Integer): Integer; static;

    // Sammelt unit-weite Konstanten mit Stringliteral-Wert in eine Map
    // <name, fmtstr-without-quotes>. Nur untypisierte Consts mit
    // Stringliteral-Initializer; alles andere ignoriert. ConstTable wird
    // vom Caller (AnalyzeUnit) erstellt und freigegeben.
    class procedure CollectStringConstants(UnitNode: TAstNode;
      ConstTable: TDictionary<string, string>); static;

    // Liefert die Lower-Case-Liste der konfigurierten Format-Funktionen
    // (Defaults aus uSCAConsts.DetectorFormatFunctions, falls leer
    // Fallback ['format'] damit der Detektor immer was zu pruefen hat).
    class function FormatFunctionList: TArray<string>; static;
  end;

implementation

{ ---- Hilfsfunktionen ---- }

class function TFormatMismatchDetector.FormatFunctionList: TArray<string>;
var
  i : Integer;
begin
  if Assigned(uSCAConsts.DetectorFormatFunctions) and
     (uSCAConsts.DetectorFormatFunctions.Count > 0) then
  begin
    SetLength(Result, uSCAConsts.DetectorFormatFunctions.Count);
    for i := 0 to uSCAConsts.DetectorFormatFunctions.Count - 1 do
      Result[i] := uSCAConsts.DetectorFormatFunctions[i].ToLower;
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := 'format';
  end;
end;

class function TFormatMismatchDetector.TryExtractCall(
  const CallName: string; out FirstArg: string; out FuncEnd: Integer;
  out ArgsStart: Integer): Boolean;
// Sucht den groessten Match unter allen FormatFunctionList-Eintraegen mit
// nachfolgendem '('. Pflicht-Pruefung links: vor dem Funktionsnamen darf
// kein Identifier-Char stehen (sonst wuerde 'MyFormat(' false-positiv
// matchen). Punkt davor (z.B. SysUtils.Format) ist erlaubt.
//
// Returns True wenn ein Match gefunden + erstes Argument extrahiert
// (Stringliteral mit Quotes ODER Identifier-Token).
var
  Low      : string;
  FuncName : string;
  pCall    : Integer;
  i, j     : Integer;
begin
  Result    := False;
  FirstArg  := '';
  FuncEnd   := 0;
  ArgsStart := 0;
  Low := CallName.ToLower;

  for FuncName in FormatFunctionList do
  begin
    pCall := Pos(FuncName + '(', Low);
    if pCall = 0 then Continue;
    // Linke Wortgrenze: kein Ident-Char vor dem Funktionsnamen.
    if (pCall > 1) and TDetectorUtils.IsIdentChar(Low[pCall - 1]) then
      Continue;

    FuncEnd := pCall + Length(FuncName) + 1; // direkt nach '('
    i := FuncEnd;
    // fuehrenden Whitespace ueberspringen
    while (i <= Length(CallName)) and CharInSet(CallName[i], [' ', #9]) do Inc(i);
    if i > Length(CallName) then Exit;

    if CallName[i] = '''' then
    begin
      // Stringliteral - bis schliessenden Quote sammeln (incl. ''-Escape)
      FirstArg := '''';
      Inc(i);
      while i <= Length(CallName) do
      begin
        if CallName[i] = '''' then
        begin
          if (i < Length(CallName)) and (CallName[i + 1] = '''') then
          begin
            FirstArg := FirstArg + ''''''; // escaped quote
            Inc(i, 2);
          end
          else
          begin
            FirstArg := FirstArg + '''';
            Inc(i);
            ArgsStart := i;
            Exit(True);
          end;
        end
        else
        begin
          FirstArg := FirstArg + CallName[i];
          Inc(i);
        end;
      end;
      // kein schliessendes ' - Fehler.
      Exit(False);
    end
    else if TDetectorUtils.IsIdentChar(CallName[i]) and
            not CharInSet(CallName[i], ['0'..'9']) then
    begin
      // Identifier (muss mit Buchstabe oder _ anfangen).
      j := i;
      while (j <= Length(CallName)) and
            TDetectorUtils.IsIdentChar(CallName[j]) do
        Inc(j);
      FirstArg  := Copy(CallName, i, j - i);
      ArgsStart := j;
      Exit(True);
    end;
    // Andere Tokens (Klammer, Operator, ...) -> nicht aufloesbar
    Exit(False);
  end;
end;

class function TFormatMismatchDetector.ResolveFormatString(
  const FirstArg: string; ConstTable: TDictionary<string, string>;
  out FmtStr: string): Boolean;
var
  Inner : string;
  i     : Integer;
begin
  Result := False;
  FmtStr := '';
  if FirstArg = '' then Exit;

  if FirstArg[1] = '''' then
  begin
    // Stringliteral '...': Inhalt extrahieren + ''-Escapes ersetzen.
    if (Length(FirstArg) < 2) or (FirstArg[Length(FirstArg)] <> '''') then
      Exit;
    Inner := Copy(FirstArg, 2, Length(FirstArg) - 2);
    i := 1;
    while i <= Length(Inner) do
    begin
      if (Inner[i] = '''') and (i < Length(Inner)) and
         (Inner[i + 1] = '''') then
      begin
        FmtStr := FmtStr + '''';
        Inc(i, 2);
      end
      else
      begin
        FmtStr := FmtStr + Inner[i];
        Inc(i);
      end;
    end;
    Result := True;
  end
  else if Assigned(ConstTable) then
  begin
    // Identifier - in der Const-Tabelle nachschlagen.
    Result := ConstTable.TryGetValue(FirstArg.ToLower, FmtStr);
  end;
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
        // Restliche Zeichen des Specifiers ueberspringen (%8.2f, %0:s, ...)
        while (i <= Length(FmtStr)) and
              not CharInSet(FmtStr[i], ['s','d','f','e','g','n','m','u',
                                        'c','x','p','i','S','D','F','E',
                                        'G','N','M','U','C','X','P','I']) do
          Inc(i);
        if i <= Length(FmtStr) then Inc(i); // Specifier-Buchstabe ueberspringen
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
  if i > Length(Text) then Exit; // kein Array gefunden -> 0 Argumente

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

class procedure TFormatMismatchDetector.CollectStringConstants(
  UnitNode: TAstNode; ConstTable: TDictionary<string, string>);
// Walked alle nkConstSection-Knoten in der Unit. Pro nkField-Kind:
// TypeRef hat das Format 'TypeName=initValue' oder '=initValue' (untyped)
// oder 'TypeName' (uninitialized). Wir interessieren uns nur fuer die
// Fall-2 (untyped) mit String-Literal-Wert.
var
  Sections : TList<TAstNode>;
  Sec      : TAstNode;
  i, eqPos : Integer;
  Field    : TAstNode;
  Ref, Val : string;
  ValTrim  : string;
  Inner    : string;
  k        : Integer;
  Decoded  : string;
begin
  if (UnitNode = nil) or (ConstTable = nil) then Exit;
  Sections := UnitNode.FindAll(nkConstSection);
  try
    for Sec in Sections do
    begin
      for i := 0 to Sec.Children.Count - 1 do
      begin
        Field := Sec.Children[i];
        if Field.Kind <> nkField then Continue;
        Ref := Field.TypeRef;
        eqPos := Pos('=', Ref);
        if eqPos = 0 then Continue;
        Val := Copy(Ref, eqPos + 1, MaxInt);
        ValTrim := Trim(Val);
        if (Length(ValTrim) < 2) or (ValTrim[1] <> '''') or
           (ValTrim[Length(ValTrim)] <> '''') then
          Continue; // kein einfaches '...'-Literal
        Inner := Copy(ValTrim, 2, Length(ValTrim) - 2);
        // ''-Escape-Sequenzen aufloesen.
        Decoded := '';
        k := 1;
        while k <= Length(Inner) do
        begin
          if (Inner[k] = '''') and (k < Length(Inner)) and
             (Inner[k + 1] = '''') then
          begin
            Decoded := Decoded + '''';
            Inc(k, 2);
          end
          else
          begin
            Decoded := Decoded + Inner[k];
            Inc(k);
          end;
        end;
        ConstTable.AddOrSetValue(Field.Name.ToLower, Decoded);
      end;
    end;
  finally
    Sections.Free;
  end;
end;

{ ---- Oeffentliche API ---- }

class procedure TFormatMismatchDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  ConstTable: TDictionary<string, string>);
var
  Reported : TDictionary<string, Boolean>;

  procedure CheckCallText(const CallText: string; Line: Integer);
  var
    FirstArg   : string;
    FuncEnd    : Integer;
    ArgsStart  : Integer;
    FmtStr     : string;
    PlaceCount : Integer;
    ArgCount   : Integer;
    F          : TLeakFinding;
    Key        : string;
  begin
    if not TryExtractCall(CallText, FirstArg, FuncEnd, ArgsStart) then Exit;
    if not ResolveFormatString(FirstArg, ConstTable, FmtStr) then Exit;
    PlaceCount := CountPlaceholders(FmtStr);
    ArgCount   := CountArrayArgs(CallText, ArgsStart);
    if PlaceCount = ArgCount then Exit;
    // Dedup: nkCall + nkAssign-Walk koennen denselben Format-Call doppelt
    // sehen (z.B. 'Result := someFunc(Format(...))' - nkAssign hat den
    // ganzen RHS, ein evtl. emittierter nkCall fuer someFunc enthaelt
    // ebenfalls 'format(' im Namen). Key = Line + Format-String:
    Key := IntToStr(Line) + ':' + FmtStr;
    if Reported.ContainsKey(Key) then Exit;
    Reported.Add(Key, True);

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format('Format: %d placeholders, %d arguments',
                           [PlaceCount, ArgCount]);
    F.Severity   := lsError;
    F.Kind       := fkFormatMismatch;
    Results.Add(F);
  end;

var
  Calls   : TList<TAstNode>;
  Assigns : TList<TAstNode>;
  N       : TAstNode;
begin
  Reported := TDictionary<string, Boolean>.Create;
  try
    // Walk nkCall (eigenstaendige Format-Aufrufe wie 'Format(...)').
    Calls := MethodNode.FindAll(nkCall);
    try
      for N in Calls do
        CheckCallText(N.Name, N.Line);
    finally
      Calls.Free;
    end;

    // Walk nkAssign (Format inside Zuweisung wie 's := Format(''%s'', [a, b])'
    // oder 'Result := FormatUtf8(...)'). Der Format-Call lebt da im
    // TypeRef (RHS-String), nicht als eigene nkCall-Node.
    Assigns := MethodNode.FindAll(nkAssign);
    try
      for N in Assigns do
        CheckCallText(N.TypeRef, N.Line);
    finally
      Assigns.Free;
    end;
  finally
    Reported.Free;
  end;
end;

class procedure TFormatMismatchDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods    : TList<TAstNode>;
  M          : TAstNode;
  ConstTable : TDictionary<string, string>;
begin
  ConstTable := TDictionary<string, string>.Create;
  try
    CollectStringConstants(UnitNode, ConstTable);
    Methods := UnitNode.FindAll(nkMethod);
    try
      for M in Methods do
        AnalyzeMethod(M, FileName, Results, ConstTable);
    finally
      Methods.Free;
    end;
  finally
    ConstTable.Free;
  end;
end;

end.
