unit uRdxCompilerTraces;

// reDelphix - Spuren alter Compiler in einer Datei, OHNE ToolsAPI und ohne
// Parser (laeuft auch im FPC-Pruefstand). Ein Baustein fuer Hilfen, die
// Sprachmittel schreiben, die es erst ab einer Compilerversion gibt:
//   SCA121 Default(T)              ab Delphi 2009 bzw. FPC 3.0
//                                  (FLOOR_DEFAULT_FN, uRdxResultFixes)
//   SCA014 Inline-Konstante        ab Delphi 10.3 Rio, in FPC 3.2 gar
//          'const X = 42;' im Rumpf nicht (FLOOR_INLINE_DECL,
//                                  uRdxMagicFixes, Charge Q14)
// Eine Datei, die nach einer aelteren Version fragt, baut auch mit ihr -
// dort braeche die eingefuegte Form den Bau.
//
// WARUM eine eigene Unit (Charge Q14): bis dahin stand die Heuristik in
// uRdxResultFixes, fest auf Delphi 2009 (Gegen-Review H5, Minor 4: 96 der
// 132 SCA121-Angebote lagen in JVCL/CnWizards, die ab Delphi 5/6 bauen).
// SCA014 braucht dieselbe Suche mit einer hoeheren Schwelle; eine zweite
// Kopie mit anderen Zahlen waere die naechste Drift. Die Schwelle ist
// jetzt ein Record (TRdxCompilerFloor), die Suche ist eine.
//
// WAS als Spur zaehlt - je in einer Direktive (Kommentare und Strings nicht):
//   * ein Include der Kits, die vor beiden Schwellen bauen: JEDI/JCL/JVCL,
//     CnPack/CnWizards, Indy (KIT_INCLUDES; der Dateiname ohne Pfad);
//   * in einer Bedingung ({$IFDEF}, {$IFNDEF}, {$IF}, {$ELSEIF}) ein
//     Versionssymbol bis zur Schwelle (VERnnn, DELPHIn, DELPHI20nn,
//     COMPILERn, BCBn, RTLnnn) oder ein Vergleich 'CompilerVersion|
//     RTLVersion <op> n' bzw. 'FPC_FULLVERSION <op> n' bis zur Schwelle.
//     Wer nach Version n fragt, unterscheidet sie von der davor - die Datei
//     baut also auch mit einer Version bis n. Deshalb zaehlt die Schwelle
//     SELBST mit ('CompilerVersion >= 33' schuetzt gerade die Inline-
//     Deklaration fuer aeltere Compiler), nur VERnnn nicht (ein
//     '{$IFDEF VER330}' nennt die Version, die die Form kennt) - so schon
//     bei SCA121 (VER200, CompilerVersion 20).
// Ein Treffer zu viel kostet nur ein Angebot (lieber keine Hilfe als eine
// falsche). Die Schwelle 10.3 sperrt mehr als die von Delphi 2009: auch
// DELPHIn bis 26 (JEDI zaehlt DELPHI26 = 10.3; DELPHI10_3_UP, DELPHI11 und
// DELPHI12 anderer Bibliotheken fallen mit darunter - vorsichtig) und die
// Namen XE..XE8, SEATTLE..RIO. Korpus Q14: 1.275 SCA014-Funde in Dateien
// mit Spur (jvcl.inc 552, jedi.inc 236, IdCompilerDefines.inc 199 ...),
// dazu 108 ueber ein Include (dmvcframework.inc 86: 'CompilerVersion <=
// 29' - DMVC baut ab Delphi 10.0).
//
// Dazu ScriptReason: eine Datei, die kein Compiler uebersetzt.

interface

uses
  uRdxCodeMap;

type
  // Bis zu welcher Version eine Spur "alt" ist (s. Kopf). VERnnn zaehlt
  // UNTER Ver, alle anderen Zahlen bis einschliesslich.
  //   Ver          VERnnn            (200 = Delphi 2009, 330 = 10.3)
  //   Version      CompilerVersion/RTLVersion (20 bzw. 33)
  //   Compiler     COMPILERn und BCBn der JEDI-Zaehlung (12 bzw. 26)
  //   DelphiNumber DELPHIn der JEDI-Zaehlung, ab 1 (8 bzw. 26 - JEDI
  //                zaehlt nach DELPHI8 als DELPHI9 = 2005 weiter, andere
  //                Bibliotheken nennen Delphi 10/11/12 so; bis 26 ist
  //                beides aelter als 10.3 oder sperrt nur vorsichtig)
  //   DelphiYear   DELPHI2005..DELPHIn (2009 bzw. 2010)
  //   Rtl          RTLnnn            (200 bzw. 330)
  //   FpcFull      FPC_FULLVERSION UNTER diesem Wert (30000; MaxInt: jede
  //                FPC-Version ist alt)
  //   XeNames      dazu die Namen DELPHIXE.. (XE bis XE8),
  //                DELPHIX_SEATTLE/BERLIN/TOKYO/RIO und
  //                CONDITIONALEXPRESSIONS (fragt nach Delphi 6) - fuer
  //                SCA121 aus (dort nie gemessen, die Angebote sollen sich
  //                mit dieser Unit nicht bewegen)
  //   ProjectVersion  die <ProjectVersion> einer .dproj in Zehnteln, UNTER
  //                der ein Projekt alt ist (Delphi 2009 = 12.0, 10.3 =
  //                18.5). Nur der Plattenblick von SCA014 liest sie
  //                (uRdxMagicFixes.FileReason, Gegen-Review Q14, Major 3);
  //                SCA121 hat keinen - der braeuchte eine eigene Messung.
  TRdxCompilerFloor = record
    Ver            : Integer;
    Version        : Integer;
    Compiler       : Integer;
    DelphiNumber   : Integer;
    DelphiYear     : Integer;
    Rtl            : Integer;
    FpcFull        : Integer;
    XeNames        : Boolean;
    ProjectVersion : Integer;
  end;

const
  // SCA121 Default(T): Delphi 2009 (VER200, CompilerVersion 20, COMPILER12,
  // RTL200), FPC 3.0 - genau die Zahlen, die bis Charge Q14 fest in
  // uRdxResultFixes standen.
  FLOOR_DEFAULT_FN: TRdxCompilerFloor = (Ver: 200; Version: 20; Compiler: 12;
    DelphiNumber: 8; DelphiYear: 2009; Rtl: 200; FpcFull: 30000;
    XeNames: False; ProjectVersion: 120);
  // SCA014 Inline-Konstante: Delphi 10.3 Rio (VER330, CompilerVersion 33,
  // COMPILER26/DELPHI26 der JEDI-Zaehlung, RTL330); FPC kennt keine.
  FLOOR_INLINE_DECL: TRdxCompilerFloor = (Ver: 330; Version: 33; Compiler: 26;
    DelphiNumber: 26; DelphiYear: 2010; Rtl: 330; FpcFull: MaxInt;
    XeNames: True; ProjectVersion: 185);

// Die erste Spur alter Compiler (bis AFloor) in den Direktiven der Datei:
// das Symbol, der Vergleich ('COMPILERVERSION >= 33') bzw. der Name der
// Include-Datei, ALine ihre Zeile; '' und 0 ohne Spur.
function OldCompilerTrace(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  out ALine: Integer): string;

// Uebersetzt ein Compiler die Datei? Skript-Units ('unit X;' ohne
// implementation-Teil: xEdit-Skripte, JvInterpreter-Beispiele) und
// Include-Dateien nicht - ihre Interpreter kennen AFeature ('Default()',
// 'eine Inline-Konstante') nicht. '' oder der Grund. Bis Charge Q14 in
// uRdxResultFixes (SCA121); SCA014 braucht dieselbe Sperre (Korpus: die
// xEdit-Skripte unter 'Edit Scripts'). AFeature kommt schon uebersetzt
// (Code wie 'Default()' bleibt, wie er ist) und steht als %s im Satz -
// der Aufrufer uebersetzt, was er uebergibt (Entscheid E29; ein _(AFeature)
// hier haette keine msgid).
function ScriptReason(AMap: TRdxCodeMap; const AFeature: string): string;

implementation

uses
  System.SysUtils,
  uRdxText;             // _ (Gruende in der Sprache der SCA, E29)

const
  // Die Includes der Kits, die vor beiden Schwellen bauen (JEDI/JCL/JVCL,
  // CnPack/CnWizards, Indy) ...
  KIT_INCLUDES: array[0..5] of string = ('jedi.inc', 'jvcl.inc', 'jcl.inc',
    'cnpack.inc', 'cnwizards.inc', 'idcompilerdefines.inc');
  // ... und die Bedingungen, in denen ein Versionssymbol steht.
  CONDITION_WORDS: array[0..3] of string = ('ifdef', 'ifndef', 'if',
    'elseif');
  FIRST_DELPHI_YEAR = 2005;   // DELPHI2005: ab hier Jahreszahlen
  // XeNames: Delphi XE bis XE8 und 10 bis 10.3 mit Namen (jedi.inc und
  // andere), dazu die D6-Frage CONDITIONALEXPRESSIONS.
  XE_PREFIX = 'DELPHIXE';
  NAMED_PREFIXES: array[0..4] of string = ('DELPHIX_SEATTLE',
    'DELPHIX_BERLIN', 'DELPHIX_TOKYO', 'DELPHIX_RIO',
    'CONDITIONALEXPRESSIONS');
  // ConditionTokens: Zeichen eines Worts bzw. eines Vergleichs.
  WORD_CHARS: TSysCharSet = ['A'..'Z', '0'..'9', '_', '.'];
  COMPARE_CHARS: TSysCharSet = ['<', '>', '='];
  // Damit beginnt eine Datei, die der Compiler uebersetzt (ScriptReason).
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');

// Die Zahl direkt hinter APrefix am Anfang von AUpper ('DELPHI2007_UP',
// 'DELPHI' -> 2007); -1 ohne Ziffer dahinter.
function NumberAfter(const AUpper, APrefix: string): Integer;
var
  i : Integer;
begin
  Result := -1;
  if Copy(AUpper, 1, Length(APrefix)) <> APrefix then Exit;
  i := Length(APrefix) + 1;
  while (i <= Length(AUpper)) and CharInSet(AUpper[i], ['0'..'9']) do
    Inc(i);
  if i > Length(APrefix) + 1 then
    Result := StrToIntDef(Copy(AUpper, Length(APrefix) + 1,
      i - Length(APrefix) - 1), -1);
end;

// Ein Name aus XeNames (DELPHIXE.., DELPHIX_SEATTLE.., CONDITIONALEXPRESSIONS)
// - auch mit Zusatz ('DELPHIXE2_UP', 'DELPHIX_TOKYO_UP').
function OldNamedWord(const AUpper: string): Boolean;
var
  P : string;
begin
  Result := Copy(AUpper, 1, Length(XE_PREFIX)) = XE_PREFIX;
  for P in NAMED_PREFIXES do
    Result := Result or (Copy(AUpper, 1, Length(P)) = P);
end;

// Ein Versionssymbol bis zur Schwelle AFloor (s. TRdxCompilerFloor):
// VERnnn, DELPHIn, DELPHI2005.., COMPILERn, BCBn, RTLnnn, mit XeNames
// dazu die Namen - wer danach fragt, baut auch mit dem aelteren Compiler.
function OldVersionWord(const AUpper: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  N : Integer;
begin
  N := NumberAfter(AUpper, 'DELPHI');
  Result := ((N >= 1) and (N <= AFloor.DelphiNumber))
    or ((N >= FIRST_DELPHI_YEAR) and (N <= AFloor.DelphiYear));
  N := NumberAfter(AUpper, 'VER');
  Result := Result or ((N >= 0) and (N < AFloor.Ver));
  N := NumberAfter(AUpper, 'COMPILER');
  Result := Result or ((N >= 0) and (N <= AFloor.Compiler));
  N := NumberAfter(AUpper, 'BCB');
  Result := Result or ((N >= 0) and (N <= AFloor.Compiler));
  N := NumberAfter(AUpper, 'RTL');
  Result := Result or ((N >= 0) and (N <= AFloor.Rtl));
  if AFloor.XeNames then
    Result := Result or OldNamedWord(AUpper);
end;

// Die Woerter und Vergleichszeichen eines Bedingungstexts, gross
// ('CompilerVersion >= 20.0' -> COMPILERVERSION, >=, 20.0).
function ConditionTokens(const AArgs: string): TArray<string>;
var
  U       : string;
  i, j, N : Integer;
  Chars   : TSysCharSet;
begin
  U := UpperCase(AArgs);
  SetLength(Result, Length(U));
  N := 0;
  i := 1;
  while i <= Length(U) do
  begin
    Chars := WORD_CHARS;
    if CharInSet(U[i], COMPARE_CHARS) then
      Chars := COMPARE_CHARS;
    j := i;
    while (j <= Length(U)) and CharInSet(U[j], Chars) do
      Inc(j);
    if j > i then
    begin
      Result[N] := Copy(U, i, j - i);
      Inc(N);
      i := j;
    end
    else
      Inc(i);
  end;
  SetLength(Result, N);
end;

// Die Zahl vor dem ersten '.' von AWord ('20.0' -> 20); -1 ohne Zahl.
function LeadingNumber(const AWord: string): Integer;
var
  P : Integer;
begin
  P := Pos('.', AWord + '.');
  Result := StrToIntDef(Copy(AWord, 1, P - 1), -1);
end;

// Ein Vergleich 'CompilerVersion|RTLVersion <op> n' mit n bis
// AFloor.Version bzw. 'FPC_FULLVERSION <op> n' mit n unter AFloor.FpcFull
// an AToks[i]?
function OldComparisonAt(const AToks: TArray<string>; i: Integer;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  N : Integer;
begin
  Result := False;
  if (i + 2 > High(AToks)) or not CharInSet(AToks[i + 1][1], ['<', '>', '='])
  then
    Exit;
  N := LeadingNumber(AToks[i + 2]);
  if (AToks[i] = 'COMPILERVERSION') or (AToks[i] = 'RTLVERSION') then
    Result := (N >= 0) and (N <= AFloor.Version)
  else if AToks[i] = 'FPC_FULLVERSION' then
    Result := (N >= 0) and (N < AFloor.FpcFull);
end;

// Eine Spur alter Compiler im Bedingungstext AArgs ('{$IFDEF DELPHI2007_UP}',
// '{$IF CompilerVersion < 20}') - das Symbol bzw. der Vergleich; '' ohne.
function OldSymbolIn(const AArgs: string;
  const AFloor: TRdxCompilerFloor): string;
var
  Toks : TArray<string>;
  i    : Integer;
begin
  Result := '';
  Toks := ConditionTokens(AArgs);
  for i := 0 to High(Toks) do
    if OldVersionWord(Toks[i], AFloor) then
      Exit(Toks[i])
    else if OldComparisonAt(Toks, i, AFloor) then
      Exit(Toks[i] + ' ' + Toks[i + 1] + ' ' + Toks[i + 2]);
end;

// Die Spur alter Compiler in der Direktive an (ALine, ACol): ein
// Kit-Include (KIT_INCLUDES, klein ohne Pfad) oder ein Versionssymbol in
// einer Bedingung; '' ohne.
function OldTraceAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  const AFloor: TRdxCompilerFloor): string;
var
  W   : string;
  Arg : Boolean;
begin
  Result := '';
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  if InList(W, INCLUDE_WORDS) then
  begin
    Result := LowerCase(IncludeFileAt(AMap, ALine, ACol));
    Result := Copy(Result, LastDelimiter('\/', Result) + 1, MaxInt);
    if not InList(Result, KIT_INCLUDES) then
      Result := '';
  end
  else if InList(W, CONDITION_WORDS) then
    Result := OldSymbolIn(DirectiveArgs(AMap, ALine, ACol), AFloor);
end;

function OldCompilerTrace(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  out ALine: Integer): string;
var
  Li, Co : Integer;
  L      : string;
begin
  Result := '';
  ALine := 0;
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if CharInSet(L[Co], ['{', '(']) and OpensDirective(AMap, Li, Co) then
      begin
        Result := OldTraceAt(AMap, Li, Co, AFloor);
        if Result <> '' then
        begin
          ALine := Li;
          Exit;
        end;
      end;
  end;
end;

function ScriptReason(AMap: TRdxCodeMap; const AFeature: string): string;
var
  T, P : TRdxToken;
begin
  T := NextToken(AMap, 1, 1);
  if InList(T.Low, PROGRAM_WORDS) then
    Exit('');
  if T.Low <> 'unit' then
    Exit(_('the file does not start with unit/program/library (include or '
      + 'script?) - only the compiler knows %s', [AFeature]));
  P := T;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit('');
    P := T;
    T := After(AMap, T);
  end;
  Result := _('unit without an implementation part (script?) - only the '
    + 'compiler knows %s', [AFeature]);
end;

end.
