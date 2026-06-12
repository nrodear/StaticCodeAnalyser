unit uFormatMismatch;

// AST-basierter Detektor für Format()-Argument-Fehler (Sonar-Regel #9).
//
// Erkennt nkCall-Knoten zu Format-aequivalenten Funktionen (Format,
// FormatUtf8, FormatString - konfigurierbar via INI [Detectors]
// FormatFunctions) bei denen die Anzahl der Platzhalter im Format-
// String nicht mit der Anzahl der Array-Argumente uebereinstimmt.
//
// Zwei Placeholder-Stile werden unterschieden (per Funktionsname):
//   * Standard (RTL Format): %s %d %i %u %e %f %g %n %m %p %c %x
//     %% wird als Escape behandelt (zaehlt NICHT als Argument).
//   * Bare-% (mORMot FormatUtf8/FormatString/StringFormatUtf8): nur '%'
//     allein - Typ wird zur Laufzeit aus dem Variant-Argument abgeleitet.
//     %% bleibt Escape. Kollidiert NICHT mit Standard-Style weil Bare-%
//     Funktionen keinen Type-Letter erwarten.
// Liste der Bare-%-Funktionen: BARE_STYLE_FUNCS (hardcoded, mORMot-
// spezifisch). Falls weitere Bare-Style-Funktionen auftauchen, dort ergaenzen.
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
      out ArgsStart: Integer; out MatchedFunc: string): Boolean; static;

    // True wenn der Funktionsname zur mORMot-Familie gehoert die '%' allein
    // als Platzhalter nutzt (kein Type-Letter wie %s/%d).
    class function IsBareStyle(const FuncName: string): Boolean; static;

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

    // Zaehlt Platzhalter im Format-String. ABareStyle=False -> RTL-Style
    // (%s/%d/... mit Type-Letter, %% Escape). ABareStyle=True -> mORMot-
    // Style (jedes nicht-escape '%' ist ein Platzhalter, %% bleibt Escape).
    class function CountPlaceholders(const FmtStr: string;
      ABareStyle: Boolean): Integer; static;

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

// noinspection-file ConcatToFormat, StringConcatInLoop
// Detector arbeitet auf Token-Strings - kurze Concat-Patterns fuer Param-
// und Argument-List-Reconstruction, kein O(n^2)-Risiko.

const
  // mORMot-Familie: Funktionen die '%' allein als Platzhalter nutzen
  // (Typ wird zur Laufzeit aus dem Variant-Argument abgeleitet, kein
  // Type-Letter wie %s/%d). Lower-Case fuer case-insensitive Vergleich.
  // Erweitern wenn weitere Bare-Style-Funktionen auftauchen (z.B.
  // mORMot's StringFormatBuffer, FormatShort, FormatToShort, ...).
  BARE_STYLE_FUNCS : array[0..2] of string =
    ('formatutf8', 'formatstring', 'stringformatutf8');

{ ---- Hilfsfunktionen ---- }

class function TFormatMismatchDetector.IsBareStyle(
  const FuncName: string): Boolean;
var
  Low : string;
  Name : string;
begin
  Low := FuncName.ToLower;
  for Name in BARE_STYLE_FUNCS do
    if Name = Low then Exit(True);
  Result := False;
end;

procedure SkipSpaces(const S: string; var I: Integer);
begin
  while (I <= Length(S)) and CharInSet(S[I], [' ', #9, #13, #10]) do
    Inc(I);
end;

function IsInsideStringLiteral(const S: string; Position: Integer): Boolean;
// True wenn S[Position] sich INNERHALB eines Pascal-String-Literals
// '...' befindet. Walked S von 1 bis Position-1 mit Toggle-Logik;
// verdoppelte '' werden als Escape behandelt (toggeln NICHT den State).
// FP-Schutz fuer den Detector: wenn 'format(' im RHS-Text auftaucht aber
// innerhalb eines String-Literals (z.B. Quickfix-Template
//   Result.After := 'Msg := Format(''%s'', [Name])'
// ), ist es kein echter Format-Call, sondern ein Pascal-Code-Zitat.
var
  i, n  : Integer;
  InStr : Boolean;
begin
  Result := False;
  InStr  := False;
  n := Length(S);
  i := 1;
  while (i < Position) and (i <= n) do
  begin
    if S[i] = '''' then
    begin
      if InStr and (i + 1 <= n) and (S[i + 1] = '''') then
        Inc(i, 2)        // '' = Escape, kein Toggle
      else
      begin
        InStr := not InStr;
        Inc(i);
      end;
    end
    else
      Inc(i);
  end;
  Result := InStr;
end;

function ReadStringLiteral(const S: string; var I: Integer;
  var Inner: string): Boolean;
// Liest ab S[I] (muss '' sein) ein Pascal-String-Literal '...' und haengt
// den Inhalt (mit ''-Escape-Sequenzen erhalten) an Inner an. Advanced I
// auf die Position direkt NACH dem schliessenden '. Liefert False bei
// nicht-terminiertem Literal oder falschem Startzeichen.
begin
  if (I > Length(S)) or (S[I] <> '''') then Exit(False);
  Inc(I); // opening '
  while I <= Length(S) do
  begin
    if S[I] = '''' then
    begin
      if (I < Length(S)) and (S[I + 1] = '''') then
      begin
        // ''-Escape: doppeltes '' im String. Beide ans Inner haengen damit
        // ResolveFormatString sie spaeter zu einem ' decoded.
        Inner := Inner + '''''';
        Inc(I, 2);
      end
      else
      begin
        Inc(I); // closing '
        Exit(True);
      end;
    end
    else
    begin
      Inner := Inner + S[I];
      Inc(I);
    end;
  end;
  Exit(False); // nicht-terminiert
end;

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
  out ArgsStart: Integer; out MatchedFunc: string): Boolean;
// Sucht den groessten Match unter allen FormatFunctionList-Eintraegen mit
// nachfolgendem '('. Pflicht-Pruefung links: vor dem Funktionsnamen darf
// kein Identifier-Char stehen (sonst wuerde 'MyFormat(' false-positiv
// matchen). Punkt davor (z.B. SysUtils.Format) ist erlaubt.
//
// Returns True wenn ein Match gefunden + erstes Argument extrahiert
// (Stringliteral mit Quotes ODER Identifier-Token). MatchedFunc liefert
// den Lower-Case-Namen zurueck damit Caller den Placeholder-Stil
// (Standard vs Bare-%) bestimmen kann.
var
  Low      : string;
  FuncName : string;
  pCall    : Integer;
  i, j     : Integer;
  savedI   : Integer;
  Inner    : string;
begin
  Result      := False;
  FirstArg    := '';
  FuncEnd     := 0;
  ArgsStart   := 0;
  MatchedFunc := '';
  Low := CallName.ToLower;

  for FuncName in FormatFunctionList do
  begin
    pCall := Pos(FuncName + '(', Low);
    if pCall = 0 then Continue;
    // Linke Wortgrenze: kein Ident-Char vor dem Funktionsnamen.
    if (pCall > 1) and TDetectorUtils.IsIdentChar(Low[pCall - 1]) then
      Continue;
    // FP-Schutz: 'format(' INNERHALB eines Pascal-String-Literals des
    // CallText (typischer Quickfix-Template-Pattern in uFixHint.pas:
    //   Result.After := 'Msg := Format(''%s'', [Name])')
    // ist kein echter Call sondern ein zitiertes Code-Beispiel.
    if IsInsideStringLiteral(CallName, pCall) then
      Continue;

    MatchedFunc := FuncName;
    FuncEnd := pCall + Length(FuncName) + 1; // direkt nach '('
    i := FuncEnd;
    // fuehrenden Whitespace ueberspringen
    while (i <= Length(CallName)) and CharInSet(CallName[i], [' ', #9]) do Inc(i);
    if i > Length(CallName) then Exit;

    if CallName[i] = '''' then
    begin
      // Stringliteral - bis schliessenden Quote sammeln. Anschliessend
      // pruefen ob ' + ''-fortgesetzte Konkatenation folgt (typisch fuer
      // mehrzeilige SQL-Strings: 'SELECT...' + 'WHERE %=...').
      // Inner = der ZUSAMMENGESETZTE Inhalt (ohne aeussere Quotes); FirstArg
      // wird am Ende einmalig mit Quotes gerahmt damit ResolveFormatString
      // weiterhin damit umgehen kann.
      Inner := '';
      if not ReadStringLiteral(CallName, i, Inner) then Exit(False);
      // Konkatenation 'a' + 'b' + ... mergen.
      while True do
      begin
        // Position vor dem '+' merken um bei Fehlversuch zurueckzuspringen.
        savedI := i;
        SkipSpaces(CallName, i);
        if (i > Length(CallName)) or (CallName[i] <> '+') then
        begin
          i := savedI; // kein '+', ArgsStart soll direkt nach Literal stehen
          Break;
        end;
        Inc(i); // '+' ueberspringen
        SkipSpaces(CallName, i);
        if (i > Length(CallName)) or (CallName[i] <> '''') then
        begin
          // '+' aber kein weiteres Literal (z.B. + Ident, + IntToStr(x))
          // -> Format-String nicht vollstaendig statisch aufloesbar.
          // Wir liefern was wir haben, der Detector macht keinen Befund
          // wenn ResolveFormatString unsicher ist.
          i := savedI;
          Break;
        end;
        if not ReadStringLiteral(CallName, i, Inner) then Exit(False);
      end;
      FirstArg := '''' + Inner + '''';
      ArgsStart := i;
      Exit(True);
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
    // Defensive: leerer aufgeloester Wert -> als nicht-aufloesbar behandeln.
    // 0 placeholders vs N args wuerde sonst sicher als FP feuern, wenn die
    // Const an dem Identifier extern (andere Unit) oder im Parser-Misread
    // versteckt liegt. Lieber kein Finding als ein False-Positive auf einer
    // Code-Stelle die der Detector nur teilweise versteht.
    if Result and (FmtStr = '') then Result := False;
  end;
end;

class function TFormatMismatchDetector.CountPlaceholders(
  const FmtStr: string; ABareStyle: Boolean): Integer;
// WICHTIG (Bare-Style/mORMot): TFormatUtf8.Parse in mormot.core.text macht
// KEIN '%%'-Escape. Jedes '%' konsumiert ein Argument. '%%' = zwei aufein-
// anderfolgende Args ohne Trenner. Das ist absichtlich (mORMot-Code nutzt
// das z.B. um Where-Clauses zu kettenkonkatenieren: FormatUtf8('%%>=:(%):...
// , [Where, FieldName, ...]) - Where + FieldName ohne Trenner).
//
// Standard-Style (RTL Format): '%%' IST Escape (literales '%').
var
  i: Integer;
begin
  Result := 0;
  i      := 1;
  while i <= Length(FmtStr) do
  begin
    if FmtStr[i] = '%' then
    begin
      if ABareStyle then
      begin
        // mORMot: jedes '%' = ein Argument, KEIN Escape, kein Type-Letter.
        Inc(Result);
        Inc(i);
      end
      else if (i < Length(FmtStr)) and (FmtStr[i + 1] = '%') then
        Inc(i, 2) // RTL-Format: %% = literales '%' (Escape)
      else
      begin
        Inc(Result); // %X = ein Argument
        Inc(i);
        // Restliche Zeichen des Specifiers ueberspringen (%8.2f, %0:s, ...).
        // Wichtig: '*' im Specifier konsumiert ein EXTRA Argument
        // (Width oder Precision wird via Argument geliefert), z.B.
        // '%1.*n' nimmt 2 Args (Precision + Value), '%*.*d' nimmt 3 Args.
        // Audit-Trigger: Clipper.pas L657 'format(''%1.*n,%1.*n, '', [decimals,
        // p[i].X, decimals, p[i].Y])' - 4 Args fuer 2 %-Specs mit je '*'.
        while (i <= Length(FmtStr)) and
              not CharInSet(FmtStr[i], ['s','d','f','e','g','n','m','u',
                                        'c','x','p','i','S','D','F','E',
                                        'G','N','M','U','C','X','P','I']) do
        begin
          if FmtStr[i] = '*' then Inc(Result);
          Inc(i);
        end;
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

// Locale-Hint-Helper: True wenn FmtStr ein Float-Format-Spec enthaelt
// (%f, %.Nf, %g, %e, %m, %n) - das sind die einzigen, deren Output von
// TFormatSettings abhaengt (Dezimal-Trenner Komma vs. Punkt).
function HasFloatSpec(const FmtStr: string): Boolean;
var
  i, n : Integer;
  c : Char;
begin
  Result := False;
  n := Length(FmtStr);
  i := 1;
  while i <= n do
  begin
    if FmtStr[i] = '%' then
    begin
      // %% -> nicht relevant, skip
      if (i < n) and (FmtStr[i+1] = '%') then
      begin
        Inc(i, 2);
        Continue;
      end;
      // Optionale Width/Precision-Spec ueberspringen
      Inc(i);
      while (i <= n) and CharInSet(FmtStr[i], ['0'..'9', '.', '-', '*']) do
        Inc(i);
      if i > n then Exit;
      c := UpCase(FmtStr[i]);
      if CharInSet(c, ['F', 'G', 'E', 'M', 'N']) then Exit(True);
    end;
    Inc(i);
  end;
end;

// Zaehlt Top-Level-Kommas in einem Argument-Bereich (depth-tracking
// (...)/[...]). CallText vom Aufrufer ist `<fn-args-bis-zum-)`.
function CountTopLevelArgs(const CallText: string; StartIdx: Integer): Integer;
var
  i, n : Integer;
  Depth : Integer;
begin
  Result := 1;
  Depth := 1;     // wir sind bereits IN den Format-Argumenten (nach `(`)
  n := Length(CallText);
  i := StartIdx;
  while i <= n do
  begin
    case CallText[i] of
      '(', '[': Inc(Depth);
      ')', ']':
        begin
          Dec(Depth);
          if Depth = 0 then Exit;
        end;
      ',':
        if Depth = 1 then Inc(Result);
    end;
    Inc(i);
  end;
end;

{ ---- Oeffentliche API ---- }

class procedure TFormatMismatchDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  ConstTable: TDictionary<string, string>);
var
  // noinspection UninitVar
  // Reported wird im outer-body initialisiert; CheckCallText (nested)
  // greift erst nach dem Create darauf zu - FP des Nested-Closure-Pattern.
  Reported : TDictionary<string, Boolean>;

  procedure CheckCallText(const CallText: string; Line: Integer);
  var
    FirstArg    : string;
    FuncEnd     : Integer;
    ArgsStart   : Integer;
    MatchedFunc : string;
    FmtStr      : string;
    PlaceCount  : Integer;
    ArgCount    : Integer;
    F           : TLeakFinding;
    Key         : string;
  begin
    if not TryExtractCall(CallText, FirstArg, FuncEnd, ArgsStart, MatchedFunc) then Exit;
    if not ResolveFormatString(FirstArg, ConstTable, FmtStr) then Exit;
    PlaceCount := CountPlaceholders(FmtStr, IsBareStyle(MatchedFunc));
    ArgCount   := CountArrayArgs(CallText, ArgsStart);

    // Locale-Hint: Float-Spec im Format-String + kein TFormatSettings-Arg
    // (= weniger als 3 Top-Level-Args: FmtStr + [args], ohne FmtSettings).
    if HasFloatSpec(FmtStr) and (CountTopLevelArgs(CallText, ArgsStart) <= 2) then
    begin
      Key := IntToStr(Line) + ':locale:' + FmtStr;
      if not Reported.ContainsKey(Key) then
      begin
        Reported.Add(Key, True);
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(Line);
        F.MissingVar := Format(
          'Format: float spec %s without TFormatSettings - locale-dependent '
          + '(comma vs. dot decimal separator)', [FmtStr]);
        F.SetKind(fkFormatLocaleHint);
        Results.Add(F);
      end;
    end;

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
    F.SetKind(fkFormatMismatch);
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
