unit uTestRdxHomoglyphFix;

// Editorhilfe SCA193 SourceNonAsciiIdentifier (uRdxHomoglyphFix): ein
// Bezeichner mit Buchstaben, die nur wie lateinische aussehen, wird an
// allen Vorkommen in ASCII geschrieben.
//   Fixture 1 (Text, ohne Parser und Detektor, FPC-tauglich): der Planer
//   auf der Code-Sicht - lokale Variable, Parameter, globale Variable und
//   Routine des implementation-Teils, inline-Variable, griechisches My und
//   mehrere Homoglyphen, Kommentare bleiben; die Tabelle; die Sperren
//   (verschobene Zeile, unbekannter Buchstabe, keine lateinische Schrift,
//   keine Unit, interface, keine Deklaration, andere Schreibweise, Nutzung
//   ausserhalb der Routine, Name vergeben oder reserviert, with, String
//   und Direktive, unsichere Routinengrenzen, initialization).
//   Fixture 2 (nur Delphi): der ECHTE Detektor (uSourceEncoding, S3) auf
//   einer UTF-8-Datei mit BOM meldet die Zeile; die Hilfe ueber den
//   Einstieg der Tabelle (TRdxFixTable.FixFor via PlanFixIn/FixAllWith,
//   Adapter PlanHomoglyph) behebt Fund fuer Fund, bis der Detektor schweigt.
// Quelltext reines ASCII: die Homoglyphen entstehen ueber #$xxxx.
// Die Units haben den Kopf 'unit t;', 'interface', 'implementation'
// (Zeilen 1-3); der implementation-Teil beginnt auf Zeile 4.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxHomoglyphFix = class
  public
    // ---- Umformung ----
    [Test] procedure LocalVar_AllUsesRenamed;
    [Test] procedure Parameter_Renamed;
    [Test] procedure GlobalVarAndRoutine_Renamed;
    [Test] procedure GreekMyAndSeveralLetters_Renamed;
    [Test] procedure InlineVar_Renamed;
    [Test] procedure CommentsAndSentences_Kept;
    [Test] procedure Table_KnownPairsOnly;
    // ---- Gegenproben ----
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure UnknownLetter_NoHelp;
    [Test] procedure NoLatinLetter_NoHelp;
    [Test] procedure NotAUnit_NoHelp;
    [Test] procedure InterfaceName_NoHelp;
    [Test] procedure NotDeclaredHere_NoHelp;
    [Test] procedure OtherSpelling_NoHelp;
    [Test] procedure UsedOutsideRoutine_NoHelp;
    [Test] procedure NameTakenOrReserved_NoHelp;
    [Test] procedure WithStatement_NoHelp;
    [Test] procedure LiteralOrDirective_NoHelp;
    [Test] procedure UnsafeRoutineBounds_NoHelp;
    [Test] procedure Initialization_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxHomoglyphDetector = class
  public
    [Test] procedure Detector_ReportsLineOfFirstLetter;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoNames_OneByOne;
    [Test] procedure Detector_GreekMy_RoundTrip;
    [Test] procedure Detector_Umlaut_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxHomoglyphFix,
  uRdxText,          // _(), MsgMovedSuffix
  uTestRdxTextKit    // Apply, NewMap
{$IFNDEF FPC}
  , System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uSourceEncoding,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit    // TSeen, PlanFixIn, FixAllWith
{$ENDIF}
  ;

const
  Q = '''';
  // Kyrillisch: a, o, e, P, C (gross), O (gross), s-Laut 'c'.
  CYR_A = #$0430;
  CYR_O = #$043E;
  CYR_E = #$0435;
  CYR_C = #$0441;
  CYR_CAP_ER = #$0420;
  CYR_CAP_ES = #$0421;
  CYR_CAP_O = #$041E;
  CYR_CAP_VE = #$0412;
  CYR_TE = #$0442;     // kein Doppelgaenger in der Tabelle
  // Griechisch: My gross (Korpusfund pyscripter), Omikron klein.
  GRK_MU = #$039C;
  GRK_OMICRON = #$03BF;
  // Kein Homoglyph: Umlaute.
  UML_A = #$00E4;
  UML_O = #$00F6;
  // 'Login' mit kyrillischem o.
  LOGIN_H = 'L' + CYR_O + 'gin';

// ---- Helfer ----

// FPC 3.2: TStringList haelt AnsiString - mit UTF-8 als Systemcodepage
// bleiben die Zeichen erhalten (Vorbild uTestRdxBidiOverrideFix). Unter
// Delphi ist TStringList Unicode - nichts zu tun.
function Utf8CodePage: Integer;
begin
  Result := DefaultSystemCodePage;
  {$IFDEF FPC}
  DefaultSystemCodePage := CP_UTF8;
  {$ENDIF}
end;

procedure RestoreCodePage(AOld: Integer);
begin
  DefaultSystemCodePage := AOld;
end;

// Zeilen mit CRLF verbunden - selbst verkettet (Join baut unter FPC einen
// AnsiString und verloere die Zeichen).
function Lines(const ALines: array of string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
  begin
    if i > 0 then
      Result := Result + #13#10;
    Result := Result + ALines[i];
  end;
end;

// Eine Unit: Kopf (Zeilen 1-3), AImpl ab Zeile 4, 'end.'.
function UnitSrc(const AImpl: array of string): string;
begin
  Result := Lines(['unit t;', 'interface', 'implementation']) + #13#10
    + Lines(AImpl) + #13#10 + 'end.';
end;

// Der Planer fuer Zeile ALine.
function PlanOf(const ASource: string; ALine: Integer;
  out APlan: TRdxHomoglyphPlan; out AReason: string): Boolean;
var
  Map   : TRdxCodeMap;
  OldCp : Integer;
begin
  OldCp := Utf8CodePage;
  Map := nil;
  try
    Map := NewMap(ASource);
    Result := TRdxHomoglyphFix.ToAscii(Map, ALine, '', APlan, AReason);
  finally
    Map.Free;
    RestoreCodePage(OldCp);
  end;
end;

// Die Hilfe fuer Zeile ALine, angewandt wie der Editor; sie muss gelten.
function Fixed(const ASource: string; ALine: Integer): string;
var
  P     : TRdxHomoglyphPlan;
  R     : string;
  OldCp : Integer;
begin
  Assert.IsTrue(PlanOf(ASource, ALine, P, R), R);
  OldCp := Utf8CodePage;
  try
    Result := Apply(ASource, P.Edits);
  finally
    RestoreCodePage(OldCp);
  end;
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  P : TRdxHomoglyphPlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(ASource, ALine, P, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

// Die lokale Variable LOGIN_H in Foo: Deklaration Zeile 6, Nutzungen 8, 9.
function LocalSrc(const AName: string): string;
begin
  Result := UnitSrc(['procedure Foo;', 'var', '  ' + AName + ': string;',
    'begin', '  ' + AName + ' := ' + Q + 'x' + Q + ';', '  Show(' + AName + ');',
    'end;']);
end;

// ---- Umformung ----

procedure TTestRdxHomoglyphFix.LocalVar_AllUsesRenamed;
var
  P : TRdxHomoglyphPlan;
  R : string;
begin
  Assert.AreEqual(LocalSrc('Login'), Fixed(LocalSrc(LOGIN_H), 6));
  // Eine Ersetzung je Vorkommen, alle in EINEM Plan.
  Assert.IsTrue(PlanOf(LocalSrc(LOGIN_H), 6, P, R), R);
  Assert.AreEqual<Integer>(3, Length(P.Edits), 'drei Vorkommen');
  Assert.AreEqual('Login', P.Name);
  Assert.AreEqual(LOGIN_H, P.Edits[2].Expected);
  Assert.AreEqual<Integer>(9, P.Edits[2].Span.StartLine);
  Assert.AreEqual<Integer>(8, P.Edits[2].Span.StartCol);
end;

procedure TTestRdxHomoglyphFix.Parameter_Renamed;
var
  V : string;
begin
  V := 'V' + CYR_A + 'lue';
  Assert.AreEqual(UnitSrc(['procedure Foo(Value: Integer);', 'begin',
    '  Show(Value);', 'end;']),
    Fixed(UnitSrc(['procedure Foo(' + V + ': Integer);', 'begin',
      '  Show(' + V + ');', 'end;']), 4));
end;

procedure TTestRdxHomoglyphFix.GlobalVarAndRoutine_Renamed;
var
  C, D : string;
begin
  // Eine globale Variable des implementation-Teils.
  C := 'C' + CYR_O + 'unter';
  Assert.AreEqual(UnitSrc(['var', '  Counter: Integer;', 'procedure Foo;',
    'begin', '  Inc(Counter);', 'end;']),
    Fixed(UnitSrc(['var', '  ' + C + ': Integer;', 'procedure Foo;', 'begin',
      '  Inc(' + C + ');', 'end;']), 5));
  // Eine Routine des implementation-Teils und ihr Aufruf.
  D := 'D' + CYR_O + 'Work';
  Assert.AreEqual(UnitSrc(['procedure DoWork;', 'begin', 'end;',
    'procedure Foo;', 'begin', '  DoWork;', 'end;']),
    Fixed(UnitSrc(['procedure ' + D + ';', 'begin', 'end;', 'procedure Foo;',
      'begin', '  ' + D + ';', 'end;']), 4));
end;

procedure TTestRdxHomoglyphFix.GreekMyAndSeveralLetters_Renamed;
var
  M, Pm, S : string;
begin
  // Der Korpusfund (pyscripter): griechisches My statt 'M'. Dazu ein Name
  // aus drei Homoglyphen. Die Hilfe nimmt je Fund den ersten Namen der
  // Zeile; der zweite Name kommt mit dem naechsten Fund.
  M := GRK_MU + 'ask';
  Pm := CYR_CAP_ER + CYR_A + 'r' + CYR_A + 'm';
  S := UnitSrc(['procedure Foo;', 'var', '  ' + M + ', ' + Pm + ': Integer;',
    'begin', '  ' + M + ' := ' + Pm + ';', 'end;']);
  S := Fixed(S, 6);
  Assert.AreEqual(UnitSrc(['procedure Foo;', 'var',
    '  Mask, ' + Pm + ': Integer;', 'begin', '  Mask := ' + Pm + ';',
    'end;']), S);
  Assert.AreEqual(UnitSrc(['procedure Foo;', 'var', '  Mask, Param: Integer;',
    'begin', '  Mask := Param;', 'end;']), Fixed(S, 6));
end;

procedure TTestRdxHomoglyphFix.InlineVar_Renamed;
var
  C : string;
begin
  C := 'C' + GRK_OMICRON + 'unt';
  Assert.AreEqual(UnitSrc(['procedure Foo;', 'begin', '  var Count := 1;',
    '  Show(Count);', 'end;']),
    Fixed(UnitSrc(['procedure Foo;', 'begin', '  var ' + C + ' := 1;',
      '  Show(' + C + ');', 'end;']), 6));
end;

procedure TTestRdxHomoglyphFix.CommentsAndSentences_Kept;
begin
  // Kommentare liest der Compiler nicht - sie bleiben. Ein String mit
  // Leerzeichen ist ein Satz, kein Name, den jemand nachschlaegt.
  Assert.AreEqual(
    UnitSrc(['procedure Foo;', 'var',
      '  Login: string; // ' + LOGIN_H + ' of the user', 'begin',
      '  Login := ' + Q + 'Login failed' + Q + ';', 'end;']),
    Fixed(UnitSrc(['procedure Foo;', 'var',
      '  ' + LOGIN_H + ': string; // ' + LOGIN_H + ' of the user', 'begin',
      '  ' + LOGIN_H + ' := ' + Q + 'Login failed' + Q + ';', 'end;']), 6));
end;

procedure TTestRdxHomoglyphFix.Table_KnownPairsOnly;
var
  N, R : string;
begin
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(CYR_A) = 'a', 'U+0430');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(CYR_E) = 'e', 'U+0435');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(CYR_C) = 'c', 'U+0441');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(CYR_CAP_ES) = 'C', 'U+0421');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(GRK_MU) = 'M', 'U+039C');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(GRK_OMICRON) = 'o', 'U+03BF');
  // Kein Doppelgaenger: Umlaut, kyrillisches te, ASCII selbst.
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(UML_A) = #0, 'U+00E4');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf(CYR_TE) = #0, 'U+0442');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiOf('a') = #0, 'ASCII');
  Assert.IsTrue(TRdxHomoglyphFix.AsciiName(LOGIN_H, N, R), R);
  Assert.AreEqual('Login', N);
  Assert.IsFalse(TRdxHomoglyphFix.AsciiName('D' + CYR_A + CYR_TE + 'a', N, R));
  Assert.AreEqual(_(R_HG_UNKNOWN, ['U+0442']), R);
  Assert.AreEqual('', N);
end;

// ---- Gegenproben ----

procedure TTestRdxHomoglyphFix.MovedLine_NoHelp;
var
  R : string;
begin
  R := MsgMovedSuffix(_(R_HG_NONE));
  AssertRefused(LocalSrc(LOGIN_H), 5, R);
  AssertRefused(LocalSrc(LOGIN_H), 0, R);
  AssertRefused(LocalSrc(LOGIN_H), 99, R);
  // Nicht-ASCII nur im String und im Kommentar: kein Bezeichner im Code.
  AssertRefused(UnitSrc(['procedure Foo;', 'begin',
    '  S := ' + Q + LOGIN_H + Q + '; // ' + LOGIN_H, 'end;']), 6, R);
end;

procedure TTestRdxHomoglyphFix.UnknownLetter_NoHelp;
var
  P : TRdxHomoglyphPlan;
  R : string;
begin
  // Ein Umlaut kann gewollt sein - kein Homoglyph.
  AssertRefused(LocalSrc('Gr' + UML_O + 'sse'), 6, _(R_HG_UNKNOWN, ['U+00F6']));
  // Ein Homoglyph neben einem unbekannten Zeichen: auch keine Teilhilfe.
  AssertRefused(LocalSrc('L' + CYR_O + 'g' + UML_A), 6,
    _(R_HG_UNKNOWN, ['U+00E4']));
  Assert.IsFalse(PlanOf(LocalSrc('Gr' + UML_O + 'sse'), 6, P, R));
  Assert.AreEqual('', P.Name, 'ohne neuen Namen');
end;

procedure TTestRdxHomoglyphFix.NoLatinLetter_NoHelp;
begin
  // Nur kyrillische Buchstaben (alle mit Doppelgaenger): ein Name in einer
  // anderen Schrift, kein eingeschmuggelter Buchstabe.
  AssertRefused(LocalSrc(CYR_CAP_ES + CYR_O + CYR_C), 6, _(R_HG_NO_LATIN));
end;

procedure TTestRdxHomoglyphFix.NotAUnit_NoHelp;
begin
  // Programm, Include-Datei ohne Kopf, Unit mit exports.
  AssertRefused(Lines(['program p;', 'var', '  ' + LOGIN_H + ': Integer;',
    'begin', 'end.']), 3, _(R_HG_NOT_UNIT));
  AssertRefused(Lines(['var', '  ' + LOGIN_H + ': Integer;']), 2,
    _(R_HG_NOT_UNIT));
  AssertRefused(UnitSrc(['procedure ' + LOGIN_H + ';', 'begin', 'end;',
    'exports', '  ' + LOGIN_H + ';']), 4, _(R_HG_NOT_UNIT));
end;

procedure TTestRdxHomoglyphFix.InterfaceName_NoHelp;
begin
  AssertRefused(Lines(['unit t;', 'interface', 'procedure ' + LOGIN_H + ';',
    'implementation', 'procedure ' + LOGIN_H + ';', 'begin', 'end;', 'end.']),
    3, _(R_HG_INTERFACE, [3]));
end;

procedure TTestRdxHomoglyphFix.NotDeclaredHere_NoHelp;
begin
  // Zuerst genutzt, nicht deklariert: der Name kommt aus einer anderen Unit.
  AssertRefused(UnitSrc(['procedure Foo;', 'begin', '  ' + LOGIN_H + ' := 1;',
    'end;']), 6, _(R_HG_NOT_DECLARED, [6]));
  // Als Typ einer Variablen.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  X: TF' + CYR_O + 'o;',
    'begin', 'end;']), 6, _(R_HG_NOT_DECLARED, [6]));
  // Als Unit in uses.
  AssertRefused(UnitSrc(['uses', '  F' + CYR_O + 'o;']), 5,
    _(R_HG_NOT_DECLARED, [5]));
end;

procedure TTestRdxHomoglyphFix.OtherSpelling_NoHelp;
begin
  // Gross mit kyrillischem O: Delphi kann es fuer denselben Namen halten;
  // die Hilfe kennt nur eine Schreibweise.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  L' + CYR_CAP_O + 'GIN := ' + Q + Q + ';', 'end;']), 6,
    _(R_HG_SPELLING, [8]));
end;

procedure TTestRdxHomoglyphFix.UsedOutsideRoutine_NoHelp;
begin
  // Lokal in Foo, genutzt in Bar - dort ist eine andere Deklaration gemeint.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  ' + LOGIN_H + ' := ' + Q + Q + ';', 'end;', 'procedure Bar;',
    'begin', '  ' + LOGIN_H + ' := ' + Q + Q + ';', 'end;']), 6,
    _(R_HG_OUTSIDE, [12]));
end;

procedure TTestRdxHomoglyphFix.NameTakenOrReserved_NoHelp;
begin
  // 'Login' steht schon im Code: die Stelle bindete danach um.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  ' + LOGIN_H + ' := Login;', 'end;']), 6,
    _(R_HG_TAKEN, ['Login', 8]));
  // 'Begin' ist reserviert.
  AssertRefused(LocalSrc(CYR_CAP_VE + 'egin'), 6, _(R_HG_KEYWORD, ['Begin']));
end;

procedure TTestRdxHomoglyphFix.WithStatement_NoHelp;
begin
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  with Edit1 do', '    ' + LOGIN_H + ' := Text;', 'end;']), 6,
    _(R_HG_WITH, [8, 'Login']));
end;

procedure TTestRdxHomoglyphFix.LiteralOrDirective_NoHelp;
begin
  // Ein Name im String: ein Zugriff per Name (RTTI, FieldByName) aenderte
  // sich - der neue wie der alte.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  Show(' + LOGIN_H + ', ' + Q + 'Login' + Q + ');', 'end;']), 6,
    _(R_HG_LITERAL, ['Login', 8]));
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  Show(' + LOGIN_H + ', ' + Q + 'TUser.' + LOGIN_H + Q + ');',
    'end;']), 6, _(R_HG_LITERAL, [LOGIN_H, 8]));
  // Eine Direktive nennt den Namen.
  AssertRefused(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
    'begin', '  {$IF Declared(' + LOGIN_H + ')}', '  Show(' + LOGIN_H + ');',
    '  {$IFEND}', 'end;']), 6, _(R_HG_DIRECTIVE, [LOGIN_H, 8]));
end;

procedure TTestRdxHomoglyphFix.UnsafeRoutineBounds_NoHelp;
var
  C : string;
begin
  // Ein lokaler Klassentyp davor: die Grenzen dieser Routine liest
  // uRdxBlocks nicht sicher - sie koennte die Deklaration umfassen.
  C := 'C' + CYR_O + 'unter';
  AssertRefused(UnitSrc(['procedure Bar;', 'type', '  TLocal = class',
    '  end;', 'begin', 'end;', 'var', '  ' + C + ': Integer;',
    'procedure Foo;', 'begin', '  Inc(' + C + ');', 'end;']), 11,
    _(R_HG_BOUNDS, [11]));
end;

procedure TTestRdxHomoglyphFix.Initialization_NoHelp;
begin
  AssertRefused(UnitSrc(['initialization', '  ' + LOGIN_H + ' := 1;']), 5,
    _(R_HG_NOT_DECLARED, [5]));
end;

{$IFNDEF FPC}

// ---- Fixture 2: mit dem echten Detektor (nur Delphi) ----

// ASource als UTF-8 mit BOM in eine neue .pas-Datei (der Detektor urteilt
// nur bei verlaesslicher Dekodierung; WriteText schriebe ANSI).
function WriteUtf8(const ASource: string): string;
var
  Pre, Body, All : TBytes;
begin
  Result := TempName('rdx_s193_', '.pas');
  Pre := TEncoding.UTF8.GetPreamble;
  Body := TEncoding.UTF8.GetBytes(ASource);
  SetLength(All, Length(Pre) + Length(Body));
  if Length(Pre) > 0 then
    Move(Pre[0], All[0], Length(Pre));
  if Length(Body) > 0 then
    Move(Body[0], All[Length(Pre)], Length(Body));
  TFile.WriteAllBytes(Result, All);
end;

// Zahl der SCA193-Funde in ASource; ALine/AMsg der erste (0/'' ohne).
function Detect(const ASource: string; out ALine: Integer;
  out AMsg: string): Integer;
var
  Path    : string;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
begin
  Result := 0;
  ALine := 0;
  AMsg := '';
  Path := WriteUtf8(ASource);
  Results := nil;
  try
    Results := TObjectList<TLeakFinding>.Create(True);
    TSourceEncodingDetector.AnalyzeUnit(nil, Path, Results);
    for F in Results do
      if F.Kind = fkSourceNonAsciiIdentifier then
      begin
        if Result = 0 then
        begin
          ALine := F.LineInt;
          AMsg := F.Message;
        end;
        Inc(Result);
      end;
  finally
    Results.Free;
    DeleteFile(Path);
  end;
end;

// Der erste Fund in der Form TDetectFunc (FixAllWith) - je Datei meldet
// der Detektor ohnehin nur einen.
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
var
  S : TSeen;
begin
  Result := nil;
  S := Default(TSeen);
  if Detect(ASource, S.Line, S.Msg) > 0 then
    Result := TArray<TSeen>.Create(S);
end;

// Die Hilfe zum ersten Fund ueber den Einstieg der Tabelle (PlanFixIn:
// TRdxFixTable.FixFor, Adapter PlanHomoglyph; Zeile und Meldung aus dem
// Fund).
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := DetectKind(ASource, fkSourceNonAsciiIdentifier);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Result := PlanFixIn(ASource, 't.pas', fkSourceNonAsciiIdentifier, Seen[0]);
end;

// Fund fuer Fund ueber die Tabelle (je Datei meldet der Detektor nur den
// ersten), bis der Detektor schweigt (FixAllWith).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkSourceNonAsciiIdentifier, DetectKind);
end;

procedure TTestRdxHomoglyphDetector.Detector_ReportsLineOfFirstLetter;
var
  Line : Integer;
  Msg  : string;
begin
  // Ein Fund je Datei, auf der Zeile des ersten Nicht-ASCII-Buchstabens im
  // Code - der Kommentar davor zaehlt nicht.
  Assert.AreEqual<Integer>(1, Detect(UnitSrc(['// ' + LOGIN_H,
    'procedure Foo;', 'var', '  ' + LOGIN_H + ': string;', 'begin',
    '  ' + LOGIN_H + ' := ' + Q + Q + ';', 'end;']), Line, Msg));
  Assert.AreEqual<Integer>(7, Line);
  Assert.IsTrue(Pos('homoglyph', Msg) > 0, Msg);
end;

procedure TTestRdxHomoglyphDetector.Detector_RoundTrip;
var
  Fixed, Msg : string;
  Line       : Integer;
  O          : TRdxFixOutcome;
begin
  // Tabellenzeile: Name = der neue ASCII-Name (Menuetext), Hinweis der
  // Zeile, bedeutungsgleich.
  O := PlanFirst(LocalSrc(LOGIN_H));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Login', O.Name);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.IsTrue(Pos('Kommentare', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('Login',
    TRdxFixTable.CaptionFor(fkSourceNonAsciiIdentifier, O)) > 0,
    'der Menuetext nennt den neuen Namen');
  Fixed := FixAll(LocalSrc(LOGIN_H));
  Assert.AreEqual(LocalSrc('Login'), Fixed);
  Assert.AreEqual<Integer>(0, Detect(Fixed, Line, Msg), 'der Detektor schweigt');
end;

procedure TTestRdxHomoglyphDetector.Detector_TwoNames_OneByOne;
var
  PassName, Msg : string;
  Line          : Integer;
begin
  PassName := 'P' + CYR_A + 'ss';
  // Erst Login (Zeile 6), dann Pass (Zeile 7).
  Assert.AreEqual<Integer>(1, Detect(UnitSrc(['procedure Foo;', 'var',
    '  ' + LOGIN_H + ': string;', '  ' + PassName + ': string;', 'begin',
    '  ' + LOGIN_H + ' := ' + PassName + ';', 'end;']), Line, Msg));
  Assert.AreEqual<Integer>(6, Line);
  Assert.AreEqual(UnitSrc(['procedure Foo;', 'var', '  Login: string;',
    '  Pass: string;', 'begin', '  Login := Pass;', 'end;']),
    FixAll(UnitSrc(['procedure Foo;', 'var', '  ' + LOGIN_H + ': string;',
      '  ' + PassName + ': string;', 'begin',
      '  ' + LOGIN_H + ' := ' + PassName + ';', 'end;'])));
end;

procedure TTestRdxHomoglyphDetector.Detector_GreekMy_RoundTrip;
var
  M : string;
begin
  // Die Form des Korpusfunds (pyscripter): ein Feld-artiger Name mit
  // griechischem My, hier als globale Variable des implementation-Teils.
  M := GRK_MU + 'ask';
  Assert.AreEqual(UnitSrc(['var', '  Mask: Integer;', 'procedure Foo;',
    'begin', '  Mask := 0;', 'end;']),
    FixAll(UnitSrc(['var', '  ' + M + ': Integer;', 'procedure Foo;', 'begin',
      '  ' + M + ' := 0;', 'end;'])));
end;

procedure TTestRdxHomoglyphDetector.Detector_Umlaut_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet jeden Nicht-ASCII-Buchstaben - auch einen gewollten
  // Umlaut; die Hilfe lehnt ab.
  O := PlanFirst(LocalSrc('Gr' + UML_O + 'sse'));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_HG_UNKNOWN, ['U+00F6']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxHomoglyphFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxHomoglyphDetector);
{$ENDIF}

end.
