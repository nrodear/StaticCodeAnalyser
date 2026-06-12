unit uDetectorUtils;

// Gemeinsame Helfer fuer Detektoren. Vor allem Pattern-Matching mit echten
// Wortgrenzen statt naivem Pos() - mehrere Detektoren hatten False-Positives
// weil 'sql' auch 'sqlnot' und 'assigned MyVar' auch 'assigned MyVarOld'
// matchen wuerde.
//
// Konvention:
//   - "Lower" als Suffix bedeutet: Aufrufer hat bereits ToLower angewendet,
//     wir sparen die Konvertierung pro Aufruf.
//   - "WholeWord" bedeutet: links und rechts vom Match steht KEIN Identifier-
//     Zeichen (Buchstabe, Ziffer, Underscore, Punkt-Qualifier).

interface

uses
  System.Classes, System.Generics.Collections; // TStrings, TList<>

type
  // Container fuer extrahierte Function-Calls aus Expression-Strings
  // (siehe TDetectorUtils.ParseCallsInExpr).
  TExprCall = record
    FuncNameLow : string;
    ArgsRaw     : string;
  end;

  // Mitgefuehrter Block-Kommentar-Zustand fuer ScanCodeLine. Zeilenstrings
  // und `//`-Zeilenkommentare beginnen/enden IMMER innerhalb einer Zeile -
  // nur `{ ... }` und `(* ... *)` koennen ueber Zeilengrenzen laufen, daher
  // wird nur deren Zustand zwischen ScanCodeLine-Aufrufen getragen.
  TCommentScanState = record
    InBraceComment : Boolean;   // innerhalb { ... }
    InParenComment : Boolean;   // innerhalb (* ... *)
  end;

  TDetectorUtils = class
     public
      // True, wenn Ch zu einem Identifier gehoert (a..z, 0..9, _).
    // Punkt zaehlt NICHT mit - 'sql' in 'mytable.sql' soll trotzdem als
    // Wortgrenze rechts vom Punkt erkannt werden.
    class function IsIdentChar(Ch: Char): Boolean; static; inline;

    // True wenn FileName auf ein bekanntes Test-/Demo-Fixture-Pattern
    // matched. Konsumenten (CLI, IDE-Filter) koennen Findings aus solchen
    // Files optional ausblenden - die enthalten meist absichtliche Bugs
    // fuer Detektor-Tests bzw. Demo-Code mit nicht-produktiven Patterns.
    //
    // Patterns:
    //   * Basename matched 'uTest*.pas', '*_Test.pas', '*_Tests.pas',
    //     '*TestSuite*.pas', '*Sample.pas', '*Demo.pas', '*Sample_*.pas',
    //     '*_Demo_*.pas'
    //   * Pfad-Komponente innerhalb der REPO-RELATIVEN Pfad-Segmente
    //     (relativ zu BaseDir) ist 'test', 'tests', 'unittest', 'samples',
    //     'demos', 'resources'. Wenn BaseDir leer ist, faellt der
    //     Detektor auf eine konservative Substring-Suche zurueck mit
    //     dem Caveat dass externe Pfade ('D:\projects\company-tests\...')
    //     dann auch matchen koennen.
    //   * Spezifische bekannte Demo-Files: 'MeineUnit.pas', 'uOrderForm.pas',
    //     'uCustomerForm.pas' (im SCA-Repo intentionally-buggy Beispiele)
    //
    // Komplementaer zu TIgnoreList.IsTestPath (nur Test-Files): erweitert
    // um Demo-/Sample-Patterns und ist als Post-Filter-Heuristik gedacht,
    // NICHT als Scan-Exclusion-Mechanismus (TIgnoreList).
    class function IsTestFixturePath(const FileName: string;
      const BaseDir: string = ''): Boolean; static;

    // Sucht Needle in Haystack, beide bereits lower-case, mit Wortgrenzen-
    // Pruefung links UND rechts. Liefert 1-basierte Position oder 0.
    // Beispiele:
    //   FindWholeWordLower('sql', '.sqlnot') -> 0  (rechts steht 'n')
    //   FindWholeWordLower('sql', 'my.sql=') -> 4  (rechts steht '=')
    //   FindWholeWordLower('assigned x', 'assigned xa') -> 0
    class function FindWholeWordLower(const Needle, HaystackLower: string)
      : Integer; static;


    // True, wenn Needle als ganzes Wort in HaystackLower vorkommt.
    class function ContainsWholeWordLower(const Needle, HaystackLower: string)
      : Boolean; static; inline;

    // Entfernt Pascal-String-Literale aus einem Ausdrucks-Text.
    // Pascal escaped einfache Apostrophe in Strings durch Verdoppelung
    // (`'don''t'`), aber der Parser-AST hat sie bereits als zusammenhaengen-
    // den Literal-Token konsumiert; die Funktion arbeitet daher auf einer
    // Toggle-Logik: jedes Apostrophe schaltet "in-string"-Modus um.
    // Verwendet von Detektoren, die nach Operator-Pattern (z.B. `= nil`,
    // `IfThen(...,A(),B())`) suchen und dabei Treffer in String-Literalen
    // ('= nil als String') ausschliessen muessen.
    class function StripStringLiterals(const S: string): string; static;

    // === ZEILEN-SCANNER (Strings + Kommentare) =========================
    // Single source of truth fuer die String-/Kommentar-Zustandsmaschine.
    // Frueher hatten uFloatEquality und uNoSonarMarker je eine eigene Kopie
    // mit subtilen Abweichungen - jede Abweichung = potenzieller
    // False-Positive (Match im String-Literal / Kommentar).

    // Verarbeitet GENAU EINE Zeile. Liefert den Code-Anteil zurueck, wobei:
    //   * String-Literal-Inhalte (inkl. der Quotes) durch FillCh ersetzt
    //     werden - Position bleibt erhalten, aber `\w`/`\s`-Regex matchen
    //     nicht mehr ueber den Ex-String hinweg (Default '~': weder \w noch \s).
    //   * `{ ... }` / `(* ... *)`-Kommentar-Inhalte ENTFERNT werden.
    //   * bei einem `//`-Zeilenkommentar der Rest der Zeile abgeschnitten und
    //     LineCommentCol auf die 1-basierte Spalte des ersten `/` gesetzt wird
    //     (0 wenn kein Zeilenkommentar).
    // State traegt offene `{`/`(*`-Bloecke ueber Zeilengrenzen.
    class function ScanCodeLine(const Line: string; var State: TCommentScanState;
      out LineCommentCol: Integer; FillCh: Char = '~'): string; static;

    // Strippt Strings + Kommentare ueber den GESAMTEN Quelltext (Mehrzeilen-
    // Bloecke korrekt). Ergebnis ist EIN String, Zeilen mit #10 getrennt.
    // LineForChar[k] liefert den 0-basierten Quell-Zeilenindex des Zeichens
    // Result[k+1] - damit kann ein Detektor von einer Match-Position im
    // gestrippten Text auf die Quellzeile zurueckrechnen.
    class function StripStringsAndComments(Lines: TStrings;
      out LineForChar: TArray<Integer>; FillCh: Char = '~'): string; static;

    // Faltet Pascal-Konkatenations-Sequenzen von String-Literalen zu einem
    // einzigen virtuellen Literal zusammen:
    //   'foo' + 'bar'       -> 'foobar'
    //   'foo'+'bar'         -> 'foobar'
    //   'foo' + 'bar' + 'b' -> 'foobarb'  (Ketten)
    // Verdoppelte Apostrophen ('') innerhalb eines Literals bleiben als
    // Escape erhalten; alles ausserhalb der Literale wird unveraendert
    // durchgereicht.
    //
    // Zweck: Pattern-basierte SQL-Detektoren (uSqlDangerousStatement,
    // uSQLInjection) scannen String-Literale via Substring-Suche
    // (z.B. ' WHERE '). Wenn das SQL ueber Pascal-'+' konkateniert ist
    // (`'UPDATE ... ' + 'WHERE ...'`), trennt zwischen Daten und WHERE
    // ein `'+'`-Block die Suche - der Match schlaegt fehl, obwohl das
    // Statement zur Laufzeit ein valides WHERE hat. Nach diesem Merge
    // sieht der Detektor das SQL so, wie der Compiler es zusammenfuegt.
    class function MergeAdjacentStringLiterals(const S: string): string;
      static;

    // === EXPRESSION-CALL-EXTRAKTION ===================================
    // Aus einem Pascal-Expression-String (z.B. nkIfStmt.TypeRef oder
    // nkAssign.TypeRef oder nkCall.Name) alle Function-Call-Pattern
    // 'name(args)' extrahieren. Nested-paren-aware via Depth-Counting.
    // Whitespace zwischen 'name' und '(' wird toleriert - der Parser
    // packt Conditions oft mit JoinTokInto + Space-Separator.
    //
    // Verwendung: uUninitVar Phase 2.2-2.6 (Call-Detection in TypeRef-
    // Strings die der Parser NICHT als nkCall-Knoten abgelegt hat).
    // Bewusst List-basiert statt anonymous-method-Callback - anonymous
    // procs in Delphi koennen Nested-Procedures der enclosing Method
    // nicht erfassen (E2555).
    class procedure ParseCallsInExpr(const Expr: string;
      Calls: TList<TExprCall>); static;

    // Funktions-Name aus nkCall.Name extrahieren ('ReadLn(n)' -> 'readln').
    // Greift den Teil rechts vom letzten Punkt vor '(' (oder den ganzen
    // Ident wenn kein Punkt vorhanden).
    class function ExtractCallFunctionName(const CallExpr: string):
      string; static;

    // Roh-Args-String zwischen erster '(' und matching ')'.
    // Nested-paren-aware; Result leer wenn keine '(' vorhanden.
    class function ExtractCallArgsRaw(const CallExpr: string):
      string; static;
  end;


implementation

// noinspection-file MultipleExit, StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils,               // TStringBuilder
  System.Masks,                  // MatchesMask fuer Test-Fixture-Patterns
  System.StrUtils;               // PosEx

class function TDetectorUtils.IsIdentChar(Ch: Char): Boolean;
begin
  Result := ((Ch >= 'a') and (Ch <= 'z'))
         or ((Ch >= 'A') and (Ch <= 'Z'))
         or ((Ch >= '0') and (Ch <= '9'))
         or (Ch = '_');
end;

class function TDetectorUtils.IsTestFixturePath(const FileName: string;
  const BaseDir: string): Boolean;
const
  // Basename-Globs - matcht den File-Namen ohne Pfad.
  FIXTURE_FILE_PATTERNS : array[0..9] of string = (
    'uTest*.pas',       // DUnit-Tests
    '*_Test.pas',
    '*_Tests.pas',
    '*TestSuite*.pas',
    '*Sample.pas',      // Sample-Demos
    '*_Sample_*.pas',
    '*Demo.pas',        // Generische Demos
    '*_Demo_*.pas',
    'MeineUnit.pas',    // SCA-Repo intentionally-buggy demo
    '*Demo.dfm'         // Form-Designer-Demos
  );
  // Pfad-Substring (normalisiert mit /), case-insensitive.
  FIXTURE_DIR_PARTS : array[0..6] of string = (
    'test',          // Singular: /test/
    'tests',         // Plural: /tests/
    'unittest',
    'unittests',
    'samples',
    'demos',
    'resources'      // /resources/-Folder enthalten Form-Templates
  );
var
  Bare, FullLow, BaseLow, RelLow : string;
  Pat, DirPart, Segment          : string;
  Segments                       : TArray<string>;
begin
  Result := False;
  if FileName = '' then Exit;
  Bare := ExtractFileName(FileName);

  // 1. Basename-Pattern matched unabhaengig vom Pfad-Anchoring -
  //    'uTest*.pas' ist projekt-uebergreifend ein Test-File-Indikator.
  for Pat in FIXTURE_FILE_PATTERNS do
    if MatchesMask(Bare, Pat) then Exit(True);

  // 2. Pfad-Komponenten-Match. Wenn BaseDir gegeben, matchen wir NUR
  //    Segmente des Pfads RELATIV zu BaseDir - so wird '/test/' in einem
  //    externen Repo-Pfad wie 'D:\projects\company-tests\src\auth.pas'
  //    nicht mehr als Fixture erkannt. Ohne BaseDir fallen wir auf die
  //    alte volle Pfad-Substring-Suche zurueck (mit dem dokumentierten
  //    Caveat).
  FullLow := FileName.Replace('\', '/').ToLower;
  if BaseDir <> '' then
  begin
    BaseLow := IncludeTrailingPathDelimiter(BaseDir)
                 .Replace('\', '/').ToLower;
    if FullLow.StartsWith(BaseLow) then
      RelLow := Copy(FullLow, Length(BaseLow) + 1, MaxInt)
    else
      RelLow := '';
    if RelLow <> '' then
    begin
      Segments := RelLow.Split(['/']);
      for Segment in Segments do
        for DirPart in FIXTURE_DIR_PARTS do
          if Segment = DirPart then Exit(True);
    end;
  end
  else
  begin
    for DirPart in FIXTURE_DIR_PARTS do
      if Pos('/' + DirPart + '/', FullLow) > 0 then Exit(True);
  end;
end;

class function TDetectorUtils.FindWholeWordLower(const Needle,
  HaystackLower: string): Integer;
var
  Start, NLen, HLen, i: Integer;
  LeftOK, RightOK     : Boolean;
begin
  Result := 0;
  NLen   := Length(Needle);
  HLen   := Length(HaystackLower);
  if (NLen = 0) or (HLen < NLen) then Exit;

  // Pos() ist die Schleife - wir starten ab Position 1 und springen weiter
  // wenn der Match keine echten Wortgrenzen hat.
  Start := 1;
  while True do
  begin
    i := PosEx(Needle, HaystackLower, Start);
    if i = 0 then Exit;

    // Linke Grenze: Zeichen vor dem Match darf KEIN Identifier-Char sein.
    LeftOK := (i = 1) or not IsIdentChar(HaystackLower[i - 1]);

    // Rechte Grenze: Zeichen nach dem Match darf KEIN Identifier-Char sein.
    RightOK := (i + NLen - 1 >= HLen)
            or not IsIdentChar(HaystackLower[i + NLen]);

    if LeftOK and RightOK then Exit(i);

    Inc(Start, 1); // weiter suchen
    if Start > HLen - NLen + 1 then Exit;
  end;
end;

class function TDetectorUtils.ContainsWholeWordLower(const Needle,
  HaystackLower: string): Boolean;
begin
  Result := FindWholeWordLower(Needle, HaystackLower) > 0;
end;

class function TDetectorUtils.StripStringLiterals(const S: string): string;
var
  i     : Integer;
  C     : Char;
  InStr : Boolean;
begin
  Result := '';
  InStr := False;
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C = '''' then
      InStr := not InStr
    else if not InStr then
      Result := Result + C;
  end;
end;

class function TDetectorUtils.ScanCodeLine(const Line: string;
  var State: TCommentScanState; out LineCommentCol: Integer;
  FillCh: Char): string;
var
  Buf    : TStringBuilder;
  j, n   : Integer;
  c      : Char;
  InStr  : Boolean;   // String-Literale spannen nie ueber Zeilen -> lokal
  pClose : Integer;
begin
  LineCommentCol := 0;
  InStr := False;
  n := Length(Line);
  Buf := TStringBuilder.Create;
  try
    j := 1;
    while j <= n do
    begin
      if State.InBraceComment then
      begin
        pClose := PosEx('}', Line, j);
        if pClose = 0 then Break;             // Block laeuft in naechste Zeile
        State.InBraceComment := False;
        j := pClose + 1; Continue;
      end;
      if State.InParenComment then
      begin
        pClose := PosEx('*)', Line, j);
        if pClose = 0 then Break;
        State.InParenComment := False;
        j := pClose + 2; Continue;
      end;
      c := Line[j];
      if InStr then
      begin
        Buf.Append(FillCh);
        if c = '''' then
        begin
          // Verdoppeltes Apostroph = escaptes Quote, bleibt im String.
          if (j < n) and (Line[j + 1] = '''') then
          begin Buf.Append(FillCh); Inc(j, 2); end
          else begin InStr := False; Inc(j); end;
        end
        else Inc(j);
        Continue;
      end;
      if c = '''' then
      begin Buf.Append(FillCh); InStr := True; Inc(j); Continue; end;
      if (c = '/') and (j < n) and (Line[j + 1] = '/') then
      begin LineCommentCol := j; Break; end;  // Rest = Zeilenkommentar
      if c = '{' then
      begin
        pClose := PosEx('}', Line, j + 1);
        if pClose = 0 then begin State.InBraceComment := True; Break; end;
        j := pClose + 1; Continue;
      end;
      if (c = '(') and (j < n) and (Line[j + 1] = '*') then
      begin
        pClose := PosEx('*)', Line, j + 2);
        if pClose = 0 then begin State.InParenComment := True; Break; end;
        j := pClose + 2; Continue;
      end;
      Buf.Append(c);
      Inc(j);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

class function TDetectorUtils.StripStringsAndComments(Lines: TStrings;
  out LineForChar: TArray<Integer>; FillCh: Char): string;
var
  Buf   : TStringBuilder;
  Chars : TList<Integer>;
  State : TCommentScanState;
  i, k  : Integer;
  Part  : string;
  Dummy : Integer;
begin
  Buf   := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      Part := ScanCodeLine(Lines[i], State, Dummy, FillCh);
      Buf.Append(Part);
      for k := 1 to Length(Part) do
        Chars.Add(i);
      // Zeilenumbruch ebenfalls auf die Quellzeile mappen, damit `\s`-Regex
      // ueber das Zeilenende hinweg konsistent positioniert bleibt.
      Buf.Append(#10);
      Chars.Add(i);
    end;
    Result      := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free;
    Buf.Free;
  end;
end;

class function TDetectorUtils.MergeAdjacentStringLiterals(
  const S: string): string;
// State-Machine: ausserhalb eines String-Literals durchreichen, am
// schliessenden Apostroph LOOKAHEAD - wenn Whitespace + '+' + Whitespace
// + Apostroph folgen, sind beide Literale eine logische Konkatenation;
// wir ueberspringen das Schliess-Quote, den '+'-Block und das Oeffnungs-
// Quote und bleiben "in-string". Doppelte '' innerhalb des Literals
// werden als Escape behandelt (nicht das Ende).
var
  Sb   : TStringBuilder;
  i, n : Integer;
  j, k : Integer;
  InStr: Boolean;
begin
  Sb := TStringBuilder.Create;
  try
    n := Length(S);
    InStr := False;
    i := 1;
    while i <= n do
    begin
      if not InStr then
      begin
        Sb.Append(S[i]);
        if S[i] = '''' then InStr := True;
        Inc(i);
        Continue;
      end;
      // InStr: pruefen ob '' (Escape) oder echtes End.
      if S[i] = '''' then
      begin
        if (i < n) and (S[i + 1] = '''') then
        begin
          // Verdoppeltes Apostroph: Escape, beide Zeichen ausgeben, im
          // String bleiben.
          Sb.Append(S[i]); Sb.Append(S[i + 1]);
          Inc(i, 2);
          Continue;
        end;
        // Lookahead: Whitespace* '+' Whitespace* ''' ?
        j := i + 1;
        while (j <= n) and CharInSet(S[j], [' ', #9, #13, #10]) do
          Inc(j);
        if (j <= n) and (S[j] = '+') then
        begin
          k := j + 1;
          while (k <= n) and CharInSet(S[k], [' ', #9, #13, #10]) do
            Inc(k);
          if (k <= n) and (S[k] = '''') then
          begin
            // Konkatenation - Schliess-Quote, '+'-Block, Oeffnungs-Quote
            // ueberspringen, InStr beibehalten.
            i := k + 1;
            Continue;
          end;
        end;
        // Echtes Literal-Ende.
        Sb.Append(S[i]);
        InStr := False;
        Inc(i);
        Continue;
      end;
      // Normales String-Zeichen.
      Sb.Append(S[i]);
      Inc(i);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

// === EXPRESSION-CALL-EXTRAKTION ===========================================

class function TDetectorUtils.ExtractCallFunctionName(
  const CallExpr: string): string;
var
  S : string;
  ParenPos, DotPos : Integer;
begin
  S := Trim(CallExpr);
  ParenPos := Pos('(', S);
  if ParenPos > 0 then
    S := Trim(Copy(S, 1, ParenPos - 1));
  DotPos := LastDelimiter('.', S);
  if DotPos > 0 then
    S := Trim(Copy(S, DotPos + 1, MaxInt));
  Result := S;
end;

class function TDetectorUtils.ExtractCallArgsRaw(
  const CallExpr: string): string;
var
  S : string;
  ParenPos, Depth, i : Integer;
begin
  Result := '';
  S := CallExpr;
  ParenPos := Pos('(', S);
  if ParenPos = 0 then Exit;
  Depth := 1;
  for i := ParenPos + 1 to Length(S) do
  begin
    if S[i] = '(' then Inc(Depth)
    else if S[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Result := Copy(S, ParenPos + 1, i - ParenPos - 1);
        Exit;
      end;
    end;
  end;
  // Kein matching ')' - alles ab '(' nehmen.
  Result := Copy(S, ParenPos + 1, MaxInt);
end;

class procedure TDetectorUtils.ParseCallsInExpr(const Expr: string;
  Calls: TList<TExprCall>);

  function IsIdentStart(C: Char): Boolean; inline;
  begin
    Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
  end;

var
  T          : string;
  i, NameStart, NameEnd, Depth, ArgsStart : Integer;
  Entry      : TExprCall;
begin
  if Calls = nil then Exit;
  T := Expr;
  i := 1;
  while i <= Length(T) do
  begin
    if not IsIdentStart(T[i]) then
    begin
      Inc(i);
      Continue;
    end;
    NameStart := i;
    while (i <= Length(T)) and IsIdentChar(T[i]) do Inc(i);
    NameEnd := i - 1;
    while (i <= Length(T)) and (T[i] = ' ') do Inc(i);
    // Generic-Type-Parameter '<T>' bzw. '<K, V>' zwischen Name und '('
    // ueberspringen. Pattern: 'TryGet<TestFixtureAttribute>(attrib)'.
    // Disambiguation gegen '<' als Operator (z.B. 'x < 5'): wir
    // versuchen einen balancierten Skip und rollen zurueck wenn danach
    // KEIN '(' folgt (dann war's tatsaechlich ein Operator).
    if (i <= Length(T)) and (T[i] = '<') then
    begin
      var SaveI : Integer := i;
      var GDepth : Integer := 1;
      Inc(i);
      while (i <= Length(T)) and (GDepth > 0) do
      begin
        if T[i] = '<' then Inc(GDepth)
        else if T[i] = '>' then Dec(GDepth);
        Inc(i);
      end;
      while (i <= Length(T)) and (T[i] = ' ') do Inc(i);
      if (i > Length(T)) or (T[i] <> '(') then
      begin
        // War kein Generic-Call - Rewind, der Outer-Loop wird das
        // '<' als Non-IdentStart skippen.
        i := SaveI;
        Continue;
      end;
    end;
    if (i > Length(T)) or (T[i] <> '(') then Continue;
    // OK - 'name(' Pattern; Args bis matching ')' extrahieren.
    Inc(i);                                   // hinter '('
    ArgsStart := i;
    Depth := 1;
    while (i <= Length(T)) and (Depth > 0) do
    begin
      if T[i] = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Break;
      end;
      Inc(i);
    end;
    Entry.FuncNameLow := LowerCase(Copy(T, NameStart, NameEnd - NameStart + 1));
    Entry.ArgsRaw     := Copy(T, ArgsStart, i - ArgsStart);
    Calls.Add(Entry);
    if (i <= Length(T)) and (T[i] = ')') then Inc(i);
  end;
end;

end.
