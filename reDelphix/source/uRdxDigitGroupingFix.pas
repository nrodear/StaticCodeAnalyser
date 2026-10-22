unit uRdxDigitGroupingFix;

// reDelphix - Editorhilfe fuer SCA069 DigitGrouping, OHNE ToolsAPI und ohne
// Parser: das gemeldete Ganzzahl-Literal bekommt Zifferntrenner in
// Dreiergruppen von rechts ('1800000' -> '1_800_000'). Bedeutungsgleich -
// der Compiler liest '_' in einem Zahl-Literal nicht.
//
// DER FUND (uDigitGrouping gelesen): je Zeile hoechstens EIN Fund, das
// erste Literal aus mindestens MIN_DIGITS Ziffern ohne '_' im Code (nicht in
// Strings und Kommentaren, nicht Teil eines Bezeichners, nicht hinter '$'
// oder '%', kein Float mit '.' oder Exponent - aber die linke Grenze von
// '10000..MAXBUF' schon). Die Meldung nennt die Spalte ('at column N',
// 1-basiert, ein Tab zaehlt als ein Zeichen). Der Detektor meldet auch ein
// Zeichenliteral wie '#65279' (Recherche-Tabelle 2026-10-11) - dort keine
// Hilfe.
//
// NUR AB DELPHI 11: Zifferntrenner kamen mit Delphi 11 Alexandria (der Kopf
// des Detektors nennt 10.4 - das ist zu frueh), FPC 3.2 kennt sie nicht.
// Eine Datei, die ein anderer Compiler baut, braeche danach. Deshalb hier
// (Textlogik, auch im FPC-Pruefstand):
//   * eine FPC-Weiche oder ein FPC-Modus irgendwo in der Datei
//     (uRdxIntroPlan.LineLooksFpcAware, wie SCA014),
//   * Spuren aelterer Compiler (uRdxCompilerTraces.OldCompilerTrace mit
//     FLOOR_DIGIT_SEP: VER350, CompilerVersion 35, COMPILER28/DELPHI28 der
//     JEDI-Zaehlung, RTL350; Kits wie jedi.inc),
//   * eine Datei, die kein Compiler uebersetzt (Include, Skript-Unit ohne
//     implementation-Teil),
//   * die Dateiart .pp/.lpr (FileNameReason - der Adapter fragt sie, der
//     Planer kennt den Dateinamen nicht).
// Was nur die Platte weiss (Lazarus-Projekt neben der Unit, alte .dproj,
// Weichen in den Includes), prueft der Adapter in uRdxFixTable mit dem
// Plattenblick von SCA014 (uRdxMagicFixes.FileReason/IncludeReason, seit
// der Integration QFI2 mit der Schwelle FLOOR_DIGIT_SEP und dem Grundtext
// der Zifferntrenner - lfDigitSeparator); ProjectReason liefert ihm den
// Grund dazu.
//
// GESPERRT ausserdem (lieber keine Hilfe als eine falsche):
//   * an der Spalte beginnt kein solches Literal (Zeile verschoben,
//     Kommentar, String, Teil eines Bezeichners, Hex, Binaer, Float),
//   * '#' davor (Zeichencode),
//   * eine Sprungmarke: die Zahl steht in einer label-Liste oder hinter
//     'goto' - irgendwo in der Datei, dann auch als '10000:',
//   * das Literal steht in einem asm-Block (der Assembler liest Zahlen
//     selbst).
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanDigitGrouping (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Ab so vielen Ziffern meldet der Detektor (uDigitGrouping.MIN_GROUP_LEN).
  MIN_DIGITS = 5;

  // Die Schwelle (Delphi 11 Alexandria, FPC nie) ist FLOOR_DIGIT_SEP in
  // uRdxCompilerTraces - bis zur Integration QFI2 stand sie hier; der
  // Plattenblick im Adapter (uRdxMagicFixes.FileReason/IncludeReason mit
  // lfDigitSeparator) liest sie jetzt auch.

  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_DIG_MOVED = 'no ungrouped integer literal at the reported column';
  R_DIG_CHAR = 'character code (#...) - digit separators are not allowed '
    + 'there';
  R_DIG_LABEL = 'the number %s is a label (label section or goto)';
  R_DIG_ASM = 'the literal is inside an asm block';
  R_DIG_FPC = 'the file carries an FPC switch or mode (line %d) - FPC 3.2 '
    + 'does not know digit separators';
  R_DIG_OLD = 'digit separators exist from Delphi 11 on - the file carries '
    + 'traces of older compilers (%s, line %d); by hand';
  R_DIG_SCRIPT = 'the file is no unit with an implementation part, program '
    + 'or library (include or script?) - only the compiler knows digit '
    + 'separators';
  R_DIG_FILE = 'Lazarus/FPC file (%s) - FPC 3.2 does not know digit '
    + 'separators';
  R_DIG_PROJECT = 'digit separators exist from Delphi 11 on and are unknown '
    + 'to FPC 3.2 - %s';

type
  TRdxDigitGroupingFix = class
  public
    // SCA069: das Literal an der Spalte der Meldung in Dreiergruppen; die
    // Ersetzung genau ueber den Ziffern. Sonst der Grund.
    class function Group(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // ADigits (nur Ziffern) mit '_' in Dreiergruppen von rechts
    // ('1800000' -> '1_800_000'); bis drei Ziffern unveraendert.
    class function Grouped(const ADigits: string): string; static;

    // Die Dateiart allein: .pp und .lpr sind Lazarus-/FPC-Dateien. '' oder
    // der Grund (fuer den Adapter; ohne Plattenzugriff).
    class function FileNameReason(const AFileName: string): string; static;

    // Der Grund des Adapters, wenn Projekt- oder Include-Dateien sagen, dass
    // ein anderer Compiler die Unit baut (ADetail: ihr Befund).
    class function ProjectReason(const ADetail: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxIntroPlan,    // LineLooksFpcAware
  uRdxCompilerTraces, // OldCompilerTrace, FLOOR_DIGIT_SEP
  uRdxText;         // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_069 = 'sca069';
  // Lazarus-/FPC-Dateiarten (wie uRdxMagicFixes.FPC_EXTENSIONS).
  FPC_EXTENSIONS: array[0..1] of string = ('.pp', '.lpr');
  // Damit beginnt eine Datei, die der Compiler ohne implementation-Teil
  // uebersetzt.
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');
  // Davor steht kein Literal, sondern ein Teil eines anderen: Hex, Binaer,
  // Oktal (FPC '&17').
  LITERAL_PREFIXES: TSysCharSet = ['$', '%', '&'];

function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

class function TRdxDigitGroupingFix.Grouped(const ADigits: string): string;
var
  i, n : Integer;
begin
  Result := '';
  n := Length(ADigits);
  for i := 1 to n do
  begin
    Result := Result + ADigits[i];
    if (i < n) and ((n - i) mod 3 = 0) then
      Result := Result + '_';
  end;
end;

class function TRdxDigitGroupingFix.FileNameReason(
  const AFileName: string): string;
var
  Ext : string;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(AFileName));
  if InList(Ext, FPC_EXTENSIONS) then
    Result := _(R_DIG_FILE, [Ext]);
end;

class function TRdxDigitGroupingFix.ProjectReason(
  const ADetail: string): string;
begin
  Result := _(R_DIG_PROJECT, [ADetail]);
end;

// Das Literal an (ALine, ACol): '' mit seiner Endspalte (hinter der letzten
// Ziffer) in AStop, sonst der Grund. Dieselben Grenzen wie der Detektor.
function LiteralAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AStop: Integer): string;
var
  L : string;
  E : Integer;
begin
  Result := '';
  AStop := 0;
  L := AMap.Raw(ALine);
  if (ACol < 1) or (ACol > Length(L)) or not IsDigit(L[ACol])
     or not AMap.IsCode(ALine, ACol) then
    Exit(MsgMovedSuffix(_(R_DIG_MOVED)));
  if ACol > 1 then
  begin
    if L[ACol - 1] = '#' then
      Exit(_(R_DIG_CHAR));
    // Mitten in einem Bezeichner oder einer Zahl, hinter '$'/'%'/'&', oder
    // der Bruchteil eines Floats ('1.23456' - aber '0..12345' ist eine
    // Bereichsgrenze).
    if IsIdentChar(L[ACol - 1]) or CharInSet(L[ACol - 1], LITERAL_PREFIXES)
       or ((L[ACol - 1] = '.') and not ((ACol > 2) and (L[ACol - 2] = '.'))) then
      Exit(MsgMovedSuffix(_(R_DIG_MOVED)));
  end;
  E := ACol;
  while (E <= Length(L)) and IsDigit(L[E]) do
    Inc(E);
  // Dahinter: '_' (schon gruppiert), ein Bezeichnerzeichen ('1e5', '12x'),
  // oder ein '.', das kein '..' ist (Float).
  if (E <= Length(L))
     and (IsIdentChar(L[E])
          or ((L[E] = '.') and not ((E < Length(L)) and (L[E + 1] = '.')))) then
    Exit(MsgMovedSuffix(_(R_DIG_MOVED)));
  if (E - ACol < MIN_DIGITS) or not AMap.IsCode(ALine, E - 1) then
    Exit(MsgMovedSuffix(_(R_DIG_MOVED)));
  AStop := E;
end;

// Steht die Zahl T in einer label-Liste ('label 10000, 20000;') oder hinter
// 'goto'?
function InLabelUse(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P : TRdxToken;
begin
  P := Before(AMap, T);
  if P.Low = 'goto' then
    Exit(True);
  while P.Low = ',' do
    P := Before(AMap, Before(AMap, P));
  Result := (P.Low = 'label') and IsKeywordAfter(P, Before(AMap, P));
end;

// Ist die Zahl ADigits irgendwo in der Datei eine Sprungmarke? Dann ist
// auch '10000:' eine Marke und kein case-Zweig.
function DeclaredLabel(AMap: TRdxCodeMap; const ADigits: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ADigits);
  while T.Low <> '' do
  begin
    if (T.Low = ADigits) and InLabelUse(AMap, T) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, ADigits);
  end;
end;

// Liegt AAt in einem asm-Block ('asm' bis zu seinem 'end' - ein asm-Block
// schachtelt nichts)?
function InsideAsm(AMap: TRdxCodeMap; const AAt: TRdxToken): Boolean;
var
  A, T : TRdxToken;
begin
  Result := False;
  A := NextTokenOnLineWith(AMap, Default(TRdxToken), 'asm');
  while (A.Low <> '') and TokBefore(A, AAt) do
  begin
    if (A.Low = 'asm') and IsKeywordAfter(A, Before(AMap, A)) then
    begin
      T := After(AMap, A);
      while (T.Low <> '') and not ((T.Low = 'end')
                                   and IsKeywordAfter(T, Before(AMap, T))) do
        T := After(AMap, T);
      if (T.Low = '') or TokBefore(AAt, T) then
        Exit(True);
      A := T;
    end;
    A := NextTokenOnLineWith(AMap, A, 'asm');
  end;
end;

// Uebersetzt ein Compiler die Datei - eine Unit mit implementation-Teil,
// ein Programm, eine Bibliothek, ein Paket? Sonst ist sie ein Include oder
// ein Skript, und wer sie liest, kennt keine Zifferntrenner.
function CompiledFile(AMap: TRdxCodeMap): Boolean;
var
  T : TRdxToken;
begin
  T := NextToken(AMap, 1, 1);
  if InList(T.Low, PROGRAM_WORDS) then
    Exit(True);
  Result := False;
  if T.Low <> 'unit' then
    Exit;
  T := NextTokenOnLineWith(AMap, T, 'implementation');
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, 'implementation');
  end;
end;

// Was die Datei als Ganzes verbietet: kein Compiler, FPC, alte Compiler.
// '' oder der Grund.
function FileReason(AMap: TRdxCodeMap): string;
var
  Li, TraceLine : Integer;
  S             : string;
begin
  Result := '';
  if not CompiledFile(AMap) then
    Exit(_(R_DIG_SCRIPT));
  for Li := 1 to AMap.LineCount do
    if LineLooksFpcAware(AMap.Raw(Li)) then
      Exit(_(R_DIG_FPC, [Li]));
  S := OldCompilerTrace(AMap, FLOOR_DIGIT_SEP, TraceLine);
  if S <> '' then
    Result := _(R_DIG_OLD, [S, TraceLine]);
end;

class function TRdxDigitGroupingFix.Group(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Col, Stop : Integer;
  Digits    : string;
  T         : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_DIG_MOVED));
    Exit;
  end;
  AReason := LiteralAt(AMap, ALine, Col, Stop);
  if AReason <> '' then
    Exit;
  Digits := Copy(AMap.Raw(ALine), Col, Stop - Col);
  T := TokenAt(AMap, ALine, Col);
  if InLabelUse(AMap, T) or DeclaredLabel(AMap, Digits) then
    AReason := _(R_DIG_LABEL, [Digits])
  else if InsideAsm(AMap, T) then
    AReason := _(R_DIG_ASM)
  else
    AReason := FileReason(AMap);
  if AReason <> '' then
    Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_069, ALine, Col, ALine, Stop);
  AEdit.Expected := Digits;
  AEdit.NewText := Grouped(Digits);
  Result := True;
end;

end.
