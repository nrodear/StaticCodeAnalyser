unit uRdxMagicFixes;

// reDelphix - Quick-Fix SCA014 MagicNumber "Lokale Konstante einfuehren"
// (Charge Q14, Entscheid E28), OHNE ToolsAPI und ohne Parser (laeuft auch
// im FPC-Pruefstand). Aus 'if Count > 200 then' wird
//     const MagicNr01 = 200;
//     if Count > MagicNr01 then
// - die Inline-Konstante als eigene Anweisung direkt vor der Anweisung mit
// dem Literal (E26), ein Zweig ohne begin bekommt begin..end (Nico, Fall
// 3). WAS geschrieben wird, rechnet die Code-Aktion "Lokale Konstante
// einfuehren" (uRdxIntroPlan/uRdxIntroEdits, 1:1 aus dem Labor
// VarNameProject): TargetAt mit dem Literal als Caret, IntroduceEdits.
// Anders als im Labor (E28): KEINE Sync-Edit-Sitzung - die Hilfe schreibt
// nur die Ersetzung, ueber den Schreibweg der Tabelle (PlanByteEdits, ein
// Undo-Schritt); umbenennen kann man danach selbst (Strg+Umschalt+J oder
// von Hand). Und nur DAS eine Literal des Funds, nicht alle gleichen der
// Zeile (E28: "nur eines, sonst sperren").
//
// WAS DER DETEKTOR MELDET (uMagicNumbers gelesen): nur in if-Bedingungen,
// je if hoechstens EINEN Fund, auf der Zeile des 'if'. Er sucht im
// Bedingungstext (Token mit Leerzeichen getrennt, ohne Kommentare, Strings
// geblankt) einen Vergleich ('>=', '<=', '<>', '>', '<', '=' - in dieser
// Reihenfolge, nicht nach Spalte) und dahinter eine Ganzzahl, die nicht
// trivial ist. Nie: Hex ('$FF' - keine Ziffer), Float ('3.5', '1e3' -
// uebersprungen), ein Vorzeichen ('-5': der Lexer trennt '-' ab, im
// Bedingungstext steht '- 5') und ein Literal in Klammern ('> (200)').
// Bei '200_000' meldet er "200" (der Lexer liest '_000' als Bezeichner) -
// das Literal heisst dann anders, die Hilfe findet es nicht.
//
// ZIEL AUS DEM FUND (der Planer prueft nach, statt dem Detektor zu
// glauben): die Zahl aus der Meldung; auf der Fundzeile jede if-Bedingung
// vom 'if' bis zu ihrem 'then' (auch ueber Folgezeilen); darin die
// Zahl-Token mit genau diesem Text, direkt hinter einem Vergleich (kein
// Teil von '200.5', '$200', '#200', '-200', '200_000'). Genau einer: das
// Ziel. Keiner: Zeile verschoben. Mehrere: mehrdeutig (gesperrt - der
// Detektor meldete danach den naechsten, und welches er meinte, sagt die
// Meldung nicht). Steht der eine in einer Folgezeile der Bedingung: die
// Konstante gehoerte vor die if-Zeile, die Code-Aktion setzt sie vor die
// Zeile des Literals - gesperrt.
//
// SPERREN dazu: alle der Code-Aktion (TargetAt: mehrzeilige Strings und
// Kommentare, asm, initialization, FPC-Weiche, Direktiven, Kopf-
// Fortsetzungen, case-Zweig/Sprungmarke/on-Handler, 'else if' u. a. -
// was der Zeilen-Leser nicht sicher abgrenzt). Dazu, weil eine Inline-
// Konstante erst ab Delphi 10.3 uebersetzt und FPC 3.2 sie gar nicht
// kennt - eine Datei, die ein anderer Compiler baut, braeche:
//   * Skript-Units ohne implementation-Teil (xEdit, JvInterpreter) und
//     Spuren von Compilern vor 10.3 in der Datei (uRdxCompilerTraces,
//     FLOOR_INLINE_DECL) - hier im Planer;
//   * was nur die Platte weiss, im Check der Tabelle (MagicCheck): eine
//     Lazarus-Dateiart bzw. ein Lazarus-Projekt oder -Paket neben der Unit
//     (FileReason) und FPC-Weichen oder alte Spuren in den Includes, auch
//     ein Include, das nicht neben der Unit liegt (IncludeReason).
// Korpus Q14 (5.036 Funde): FPC-Weiche in der Datei 1.724, alte Spur 1.275,
// in einem Include 63 + 108, Include fehlt 55, Lazarus-Projekt 88, Skript
// 18 - ohne Skript- und Plattenpruefung waeren es 1.024 statt 696
// Angebote gewesen.
//
// NAME: MagicNr01, MagicNr02 ... - der erste, der in der Datei nicht als
// ganzes Wort vorkommt (uRdxIntroPlan.NextFreeName, wie im Labor; auch
// Kommentare und Strings zaehlen - strenger als noetig).

interface

uses
  uRdxBufferMath, uRdxCodeMap;

const
  // Der Name der Konstante ohne Nummer (wie im Labor: MagicNr01 ...).
  MAGIC_NAME_BASE = 'MagicNr';

type
  // Ergebnis des Planers (uRdxFixTable: MagicForm im Geruest TRdxFixFrame).
  //   Value  die Zahl aus der Meldung - Name im Menuetext; schon gesetzt,
  //          wenn der Planer danach ablehnt
  //   Name   der Name der Konstante (MagicNr01 ...) - fuer den Hinweis
  //   Line, Col  das ersetzte Literal (1-basiert, Zeichen)
  //   Wrap   der Zweig bekommt begin..end
  //   Edits  genau eine Ersetzung: von Spalte 1 der ersten geaenderten
  //          Zeile bis hinter das Literal bzw. (Wrap) bis zum Anfang der
  //          Zeile nach der Anweisung
  TRdxMagicPlan = record
    Value : string;
    Name  : string;
    Line  : Integer;
    Col   : Integer;
    Wrap  : Boolean;
    Edits : TArray<TRdxEdit>;
  end;

  // Der Planer der Charge Q14 und seine Bausteine (s. Kopf).
  TRdxMagicFixes = class
  public
    // Die Zahl aus der Meldung 'Magic number "200" in if condition - ...'
    // (zwischen den ersten beiden '"'): Ziffern, hoechstens ein '-' davor;
    // '' sonst.
    class function NumberOf(const AMessage: string): string; static;

    // Das Literal AValue als Vergleichswert in den if-Bedingungen, die auf
    // ALine beginnen (s. Kopf "Ziel aus dem Fund"): '' und seine Spalte in
    // ACol, sonst der Grund.
    class function LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
      const AValue: string; out ACol: Integer): string; static;

    // SCA014: der Plan zum Fund auf ALine mit der Meldung AMessage - True,
    // oder False mit dem Grund. Form TRdxPlannerOf<TRdxMagicPlan>.
    class function MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxMagicPlan;
      out AReason: string): Boolean; static;

    // Was nur die Platte weiss (der Check in uRdxFixTable, nach dem
    // Planer): eine Lazarus-/FPC-Dateiart (.pp, .lpr) oder ein Lazarus-
    // Projekt bzw. -Paket (.lpi, .lpk, .lpr) im Verzeichnis der Unit oder
    // bis LAZARUS_LEVELS darueber - die Unit baut dann wohl auch mit FPC
    // (Korpus: doublecmd ohne jede FPC-Weiche in der Unit, der Modus steht
    // im Projekt). '' oder der Grund. Die FPC-Weiche IN der Datei prueft
    // schon TargetAt.
    class function FileReason(const AFileName: string): string; static;

    // Die Include-Dateien der Unit AFileName (alle {$I} in AMap, auch die
    // im Kopf - dort stehen die Compiler-Weichen: jvcl.inc,
    // mormot.defines.inc ...) lesen, verschachtelte ebenso
    // (uRdxRoutineFixes.IncludeChainReason): '' oder der Grund - eine
    // FPC-Weiche oder Spur aelterer Compiler darin, oder ein Include, das
    // nicht neben der Unit liegt (seine Weichen sieht die Hilfe nicht).
    class function IncludeReason(const AFileName: string;
      AMap: TRdxCodeMap): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,       // TStrings (TRdxIncludeTest)
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxIntroPlan,        // CharColOfByte, LineLooksFpcAware
  uRdxIntroEdits,       // TextOf, TargetAt, IntroduceEdits, ApplyIntroEdits
  uRdxRoutineFixes,     // IncludeChainReason
  uRdxCompilerTraces;   // OldCompilerTrace, ScriptReason, FLOOR_INLINE_DECL

const
  SPAN_MAGIC = 'magic';
  KW_IF   = 'if';
  KW_THEN = 'then';
  KW_END  = 'end';
  // Davor steht der Vergleichswert (uMagicNumbers.ExtractMagicNumber).
  COMPARE_OPS: array[0..5] of string = ('>=', '<=', '<>', '>', '<', '=');
  // So weit liest die Hilfe eine Bedingung ueber Folgezeilen (der
  // Detektor bis zum 'then'; ein fehlendes 'then' heisst kaputter Text).
  MAX_COND_LINES = 40;
  // Lazarus-/FPC-Dateiarten - Delphi oeffnet sie nicht als Unit.
  FPC_EXTENSIONS: array[0..1] of string = ('.pp', '.lpr');
  // Lazarus-Projekt, -Paket, -Programm (FileReason) ...
  LAZARUS_EXTENSIONS: array[0..2] of string = ('.lpi', '.lpk', '.lpr');
  // ... im Verzeichnis der Unit und so vielen darueber (Korpus: doublecmd-
  // Plugins eine Ebene, CnWizards_L4.lpk zwei Ebenen ueber den Units).
  LAZARUS_LEVELS = 2;
  // Was nur der Compiler kennt (ScriptReason).
  FEATURE_INLINE = 'eine Inline-Konstante';
  R_MOVED = 'Zeile verschoben? Datei neu pruefen';
  R_INC_UNSEEN = 'Include %s %s - seine Compiler-Weichen (FPC, aeltere '
    + 'Delphi) sieht die Hilfe nicht';

{ ---- Ziel aus dem Fund ---- }

class function TRdxMagicFixes.NumberOf(const AMessage: string): string;
var
  P, Q   : Integer;
  Digits : string;
  C      : Char;
begin
  Result := '';
  P := Pos('"', AMessage);
  if P = 0 then Exit;
  Q := Pos('"', AMessage, P + 1);
  if Q <= P + 1 then Exit;
  Result := Copy(AMessage, P + 1, Q - P - 1);
  Digits := Result;
  if Digits[1] = '-' then
    Delete(Digits, 1, 1);
  if Digits = '' then
    Exit('');
  for C in Digits do
    if not CharInSet(C, ['0'..'9']) then
      Exit('');
end;

// Ist T ein Vergleichswert - davor ein Vergleich, dahinter kein Bruchteil
// ('200.5': das Token endet am '.')?
function IsComparedValue(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  L : string;
  E : Integer;
begin
  Result := InList(Before(AMap, T).Low, COMPARE_OPS);
  if not Result then Exit;
  L := AMap.Raw(T.Line);
  E := T.EndCol;
  Result := not ((E < Length(L)) and (L[E] = '.')
    and CharInSet(L[E + 1], ['0'..'9']));
end;

// Ein Schluesselwort AWord an T (nicht '&If', 'X.Then')?
function IsKeyword(AMap: TRdxCodeMap; const T: TRdxToken;
  const AWord: string): Boolean;
begin
  Result := (T.Low = AWord) and IsKeywordAfter(T, Before(AMap, T));
end;

// Die Vergleichswerte AValue in der Bedingung hinter AIf bis zu ihrem
// 'then' (bzw. 'end', Dateiende, MAX_COND_LINES): ihre Zahl, der letzte
// in AHit.
function CountInCondition(AMap: TRdxCodeMap; const AIf: TRdxToken;
  const AValue: string; var AHit: TRdxToken): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := After(AMap, AIf);
  while (T.Low <> '') and (T.Line <= AIf.Line + MAX_COND_LINES)
     and not IsKeyword(AMap, T, KW_THEN) and not IsKeyword(AMap, T, KW_END) do
  begin
    if (T.Low = AValue) and IsComparedValue(AMap, T) then
    begin
      Inc(Result);
      AHit := T;
    end;
    T := After(AMap, T);
  end;
end;

class function TRdxMagicFixes.LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
  const AValue: string; out ACol: Integer): string;
var
  T, Hit : TRdxToken;
  Ifs, N : Integer;
begin
  ACol := 0;
  Ifs := 0;
  N := 0;
  Hit := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsKeyword(AMap, T, KW_IF) then
    begin
      Inc(Ifs);
      Inc(N, CountInCondition(AMap, T, AValue, Hit));
    end;
    T := After(AMap, T);
  end;
  if Ifs = 0 then
    Result := Format('Zeile %d traegt kein if - %s', [ALine, R_MOVED])
  else if N = 0 then
    Result := Format('keine if-Bedingung auf Zeile %d vergleicht mit %s - %s',
      [ALine, AValue, R_MOVED])
  else if N > 1 then
    Result := Format('die if-Bedingung auf Zeile %d vergleicht %d-mal mit %s '
      + '- mehrdeutig; die Hilfe ersetzt genau ein Literal', [ALine, N, AValue])
  else if Hit.Line <> ALine then
    Result := Format('%s steht in Zeile %d, einer Folgezeile der if-Bedingung '
      + '- die Konstante gehoerte vor die if-Zeile (nicht unterstuetzt)',
      [AValue, Hit.Line])
  else
  begin
    Result := '';
    ACol := Hit.Col;
  end;
end;

{ ---- Der Text fuer die Code-Aktion und zurueck ---- }

// Die Zeilen der Code-Sicht als Puffer der Code-Aktion (uRdxIntroEdits.
// TextOf): mit LF verbunden - die Zeilen sind dieselben wie in ALines
// (ein einzelnes CR trennt dort schon), Zeilenenden setzt erst
// PlanByteEdits (das des Puffers).
function IntroTextOf(AMap: TRdxCodeMap): TRdxIntroText;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to AMap.LineCount do
    begin
      if i > 1 then SB.Append(#10);
      SB.Append(AMap.Raw(i));
    end;
    Result := TextOf(TEncoding.UTF8.GetBytes(SB.ToString));
  finally
    SB.Free;
  end;
end;

// Nur das Literal in Spalte ACol der Anweisungszeile (E28) - der Plan der
// Code-Aktion nennt alle gleichen Literale der Zeile. False, wenn ACol
// nicht darunter ist.
function KeepOnlyLiteral(const AText: TRdxIntroText;
  var ATarget: TRdxIntroTarget; ACol: Integer): Boolean;
var
  C : Integer;
  L : string;
begin
  Result := False;
  for C in ATarget.Plan.OldCols do
    Result := Result or (C = ACol);
  if not Result then Exit;
  L := AText.Lines[ATarget.SourceRow - 1];
  ATarget.Plan.OldCols := [ACol];
  ATarget.Plan.NewCols := [ACol];
  ATarget.Plan.NewUseLine := Copy(L, 1, ACol - 1) + ATarget.Name
    + Copy(L, ACol + Length(ATarget.Plan.Literal), MaxInt);
end;

// Die Zeile (1-basiert), in der Byte AOffset liegt.
function RowOfByte(const AText: TRdxIntroText; AOffset: Integer): Integer;
begin
  Result := Length(AText.Starts);
  while (Result > 1) and (AText.Starts[Result - 1] > AOffset) do
    Dec(Result);
end;

// Die Ersetzungen der Code-Aktion (Bytes, aufsteigend) als EINE Ersetzung
// fuer PlanByteEdits: von Spalte 1 der Zeile der ersten bis hinter die
// letzte; Expected und NewText aus den Bytes vor und nach ApplyIntroEdits
// (Zeilenenden #10 wie SpanText).
function AsOneEdit(const AText: TRdxIntroText;
  const AEdits: TRdxIntroByteEdits): TRdxEdit;
var
  OldBytes, NewBytes : TBytes;
  First, Last, E     : Integer;
  Row1, Row2         : Integer;
  Delta              : Integer;
  B                  : TRdxIntroByteEdit;
begin
  OldBytes := TEncoding.UTF8.GetBytes(AText.Text);
  NewBytes := ApplyIntroEdits(OldBytes, AEdits);
  First := MaxInt;
  Last := 0;
  for B in AEdits do
  begin
    if B.Offset < First then First := B.Offset;
    E := B.Offset + B.Len;
    if E > Last then Last := E;
  end;
  Row1 := RowOfByte(AText, First);
  Row2 := RowOfByte(AText, Last);
  First := AText.Starts[Row1 - 1];
  Delta := Length(NewBytes) - Length(OldBytes);
  Result.Span := TRefactorSpan.Make(SPAN_MAGIC, Row1, 1, Row2,
    CharColOfByte(AText.Lines[Row2 - 1], Last - AText.Starts[Row2 - 1]));
  Result.Expected := TEncoding.UTF8.GetString(OldBytes, First, Last - First);
  Result.NewText := TEncoding.UTF8.GetString(NewBytes, First,
    Last + Delta - First);
end;

{ ---- Der Planer ---- }

// Was die Datei als Ganzes verbietet: Spuren von Compilern vor Delphi 10.3.
function CompilerReason(AMap: TRdxCodeMap): string;
var
  Li : Integer;
  S  : string;
begin
  Result := '';
  S := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
  if S <> '' then
    Result := Format('eine Inline-Konstante gibt es erst ab Delphi 10.3 - die '
      + 'Datei traegt Spuren aelterer Compiler (%s, Zeile %d); von Hand', [S, Li]);
end;

class function TRdxMagicFixes.MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxMagicPlan;
  out AReason: string): Boolean;
var
  Col    : Integer;
  Text   : TRdxIntroText;
  Target : TRdxIntroTarget;
begin
  Result := False;
  Col := 0;
  APlan := Default(TRdxMagicPlan);
  APlan.Value := NumberOf(AMessage);
  if APlan.Value = '' then
    AReason := 'die Meldung nennt keine Zahl ("Magic number "N" ...")'
  else if APlan.Value[1] = '-' then
    AReason := Format('die Meldung nennt %s - mit Vorzeichen meldet der '
      + 'Detektor nicht, das Literal ist ohne; nicht unterstuetzt', [APlan.Value])
  else
    AReason := LiteralAt(AMap, ALine, APlan.Value, Col);
  if AReason <> '' then Exit;
  Text := IntroTextOf(AMap);
  Target := TargetAt(Text, ALine, Col, MAGIC_NAME_BASE);
  if not Target.Plan.Ok then
    AReason := Target.Plan.Reason
  else if (Target.Plan.Literal <> APlan.Value)
     or not KeepOnlyLiteral(Text, Target, Col) then
    AReason := Format('am Literal in Spalte %d liest die Code-Aktion "%s" '
      + 'statt %s - %s', [Col, Target.Plan.Literal, APlan.Value, R_MOVED])
  else
    AReason := ScriptReason(AMap, FEATURE_INLINE);
  if AReason = '' then
    AReason := CompilerReason(AMap);
  if AReason <> '' then Exit;
  APlan.Name := Target.Name;
  APlan.Line := ALine;
  APlan.Col := Col;
  APlan.Wrap := Target.Plan.Wrap;
  AddEdit(APlan.Edits, AsOneEdit(Text, IntroduceEdits(Text, Target)));
  Result := True;
end;

{ ---- Was nur die Platte weiss ---- }

// Eine Lazarus-Projekt- oder -Paketdatei (LAZARUS_EXTENSIONS) in ADir: ihr
// Name, sonst ''.
function LazarusFileIn(const ADir: string): string;
var
  SR : TSearchRec;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*.lp?', faAnyFile, SR) <> 0
  then
    Exit;
  try
    repeat
      if InList(LowerCase(ExtractFileExt(SR.Name)), LAZARUS_EXTENSIONS) then
        Exit(SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

class function TRdxMagicFixes.FileReason(const AFileName: string): string;
var
  Ext, Dir, Up, Found : string;
  Level               : Integer;
begin
  Result := '';
  if AFileName = '' then Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if InList(Ext, FPC_EXTENSIONS) then
    Exit(Format('Lazarus-/FPC-Datei (%s) - eine Inline-Konstante gibt es in '
      + 'FPC 3.2 nicht', [Ext]));
  Dir := ExtractFileDir(AFileName);
  for Level := 0 to LAZARUS_LEVELS do
  begin
    if Dir = '' then Exit;
    Found := LazarusFileIn(Dir);
    if Found <> '' then
      Exit(Format('Lazarus-Projekt/-Paket %s im Verzeichnis %s - die Unit '
        + 'baut wohl auch mit FPC, und eine Inline-Konstante gibt es in FPC '
        + '3.2 nicht', [Found, Dir]));
    Up := ExtractFileDir(Dir);
    if Up = Dir then Exit;
    Dir := Up;
  end;
end;

// Alle Include-Dateien der Datei, der Reihe nach (auch im Kopf).
function AllIncludes(AMap: TRdxCodeMap): TArray<string>;
var
  Li, Co : Integer;
  F      : string;
begin
  Result := nil;
  for Li := 1 to AMap.LineCount do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if CharInSet(AMap.Raw(Li)[Co], ['{', '('])
         and OpensDirective(AMap, Li, Co) then
      begin
        F := IncludeFileAt(AMap, Li, Co);
        if F <> '' then
          Result := Result + [F];
      end;
end;

// Die Pruefung eines Includes (TRdxIncludeTest): eine FPC-Weiche oder eine
// Spur aelterer Compiler darin - '' oder der Grund.
function CompilerInInclude(const AFile: string; ALines: TStrings;
  AMap: TRdxCodeMap; const AArg: string): string;
var
  Li : Integer;
  S  : string;
begin
  Result := '';
  for Li := 0 to ALines.Count - 1 do
    if LineLooksFpcAware(ALines[Li]) then
      Exit(Format('das Include %s traegt eine FPC-Weiche (Zeile %d) - eine '
        + 'Inline-Konstante gibt es in FPC 3.2 nicht', [AFile, Li + 1]));
  S := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
  if S <> '' then
    Result := Format('das Include %s traegt Spuren aelterer Compiler (%s, '
      + 'Zeile %d) - eine Inline-Konstante gibt es erst ab Delphi 10.3; von '
      + 'Hand', [AFile, S, Li]);
end;

class function TRdxMagicFixes.IncludeReason(const AFileName: string;
  AMap: TRdxCodeMap): string;
var
  Check : TRdxIncludeCheck;
begin
  Check.Test := CompilerInInclude;
  Check.Arg := '';
  Check.MissingFmt := R_INC_UNSEEN;
  Result := IncludeChainReason(AFileName, AllIncludes(AMap), Check);
end;

end.
