unit uTestSourcePlacesTypes;

// Tests fuer P9 des Quellstellen-Dienstes (AH12, 2026-10-05):
// TSourcePlaces.DeclaredTypeOf und die Typaufloesung der Operanden in
// ChainOf/CallOf. Eigene Unit, weil sie den ECHTEN Parser und den
// TTypeResolver brauchen - der FPC-Pruefstand faehrt uTestSourcePlaces
// mit einem Parser-Stub ohne Deklarationen und bliebe hier rot.
//
// Anlass: im IDE-Package war "Format() aus Verkettung bilden" bei
// 'Text := Marker + ...' ausgegraut ("Operand 'Marker': Typ unbekannt"),
// obwohl 'Marker: string' zwei Zeilen darueber deklariert ist. Ohne
// Typaufloesung waren am Korpus nur 2 % der SCA044-Funde fix-sicher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSourcePlacesTypes = class
  public
    [Test] procedure DeclaredTypeOf_ParamLocalFieldUnknown;
    [Test] procedure DeclaredTypeOf_Unopened_Empty;
    [Test] procedure ChainOf_ResolvesPlainIdentifierOperands;
    [Test] procedure ChainOf_CharOperand_IsString;
    [Test] procedure ChainOf_NeverDowngradesKnownCalls;
    // Die Kette ist die LETZTE Anweisung der Routine und geht ueber drei
    // Zeilen: der Resolver begrenzt die Routine ueber die letzte
    // Knoten-Zeile, die Fortsetzungszeilen liegen dahinter. Aufgeloest
    // wird deshalb an der Ankerzeile der Anweisung (reDelphix.Test,
    // Rewrite_MultiLineChain_Enabled, rot am 2026-10-06).
    [Test] procedure ChainOf_MultiLineLastStatement_ResolvesLaterLines;
    // OpenSource (AH15): derselbe Text aus dem Speicher statt von der
    // Platte liefert dieselben Bereiche und Typen - der IDE-Puffer ist
    // fuer reDelphix die Wahrheit, nicht die gespeicherte Datei.
    [Test] procedure OpenSource_MatchesOpenFromFile;
    // P10 (AH19): Abschnittszeilen und Zeilentext - fuer ein Modul, das
    // eine uses-Klausel anlegen muss.
    [Test] procedure SectionLine_AndLineText;
    // P11 (AH22): Kommentar nur im gefragten Bereich - ein Modul, das
    // einen Teil der Anweisung ersetzt, prueft genau den Teil.
    [Test] procedure SpanHasComment_OnlyInsideSpan;
    // Review reDelphiX 2026-10-07, strittiger Minor 1: im with-Block kann
    // s an Rec.s binden - die Typaufloesung beweist dort nichts (P12).
    [Test] procedure ChainOf_WithBlockShadowing_StaysUnknown;
    // Review strittiger Minor 3: eine Funktion der Unit verdeckt den
    // gleichnamigen RTL-Namen - der Name beweist dann keinen String.
    [Test] procedure ChainOf_LocalFuncShadowsKnownCall_NotFixSafe;
  end;

  // Review reDelphiX 2026-10-07, Minor 3 und Minor 11: die Sicht, in der
  // der Dienst parst und Typen aufloest. Eigene Klasse, weil beide den
  // echten Parser brauchen und TTestSourcePlacesTypes sonst ueber die
  // Klassen-Laengengrenze (SCA141) wuechse.
  [TestFixture]
  TTestSourcePlacesViews = class
  public
    // Minor 11: 'string[N]' ist ein ShortString - lokal, inline,
    // Unit-Global und Klassenfeld.
    [Test] procedure DeclaredTypeOf_StringN_IsShortString;
    // Gegenprobe zu Minor 11: ohne Opt-in bleibt der Resolver, wie die
    // Detektoren ihn kennen ('string').
    [Test] procedure TypeResolver_ShortStringOnlyOptIn;
    // Minor 3: der Dienst parst in seiner EIGENEN Sicht, nicht in der
    // prozessweiten, die ein laufender Scan gerade gesetzt hat.
    [Test] procedure OpenSource_IgnoresGlobalIfdefView;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uAstNode, uLexer, uParser2, uTypeResolver,
  uRefactorInfo, uSourcePlaces;

const
  // Lokale, Parameter (auch const), Klassenfeld, ein Integer, ein Char.
  SRC_TYPES =
    'unit t; interface'#13#10 +
    'type TFoo = class'#13#10 +
    '  FName: string;'#13#10 +
    '  procedure Bar(Id: Integer; const Tag: string);'#13#10 +
    'end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Bar(Id: Integer; const Tag: string);'#13#10 +
    'var Marker: string; n: Integer; c: Char; r: string;'#13#10 +
    'begin'#13#10 +
    '  r := Marker + ''id:'' + IntToStr(Id) + Tag;'#13#10 +
    '  r := Marker + ''n:'' + n + FName;'#13#10 +
    '  r := ''x'' + c + ''y'' + QuotedStr(Tag);'#13#10 +
    'end;'#13#10 +
    'end.';

function WriteTemp(const ASource: string): string;
var
  SL : TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'sca_places_types_' + FormatDateTime('hhnnsszzz', Now)
    + IntToStr(Random(1000000)) + '.pas';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Result);
  finally
    SL.Free;
  end;
end;

function LineOf(const ASource, AMarker: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

function ColOf(const ASource, AMarker: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(Pos(AMarker, SL[i]));
  finally
    SL.Free;
  end;
end;

procedure TTestSourcePlacesTypes.DeclaredTypeOf_ParamLocalFieldUnknown;
var
  P    : TSourcePlaces;
  Path : string;
  L    : Integer;
begin
  Path := WriteTemp(SRC_TYPES);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    L := LineOf(SRC_TYPES, 'r := Marker + ''id:''');
    Assert.AreEqual('string',  P.DeclaredTypeOf(L, 'Marker'), 'lokale Variable');
    Assert.AreEqual('integer', P.DeclaredTypeOf(L, 'Id'),     'Parameter');
    Assert.AreEqual('string',  P.DeclaredTypeOf(L, 'Tag'),    'const-Parameter');
    Assert.AreEqual('string',  P.DeclaredTypeOf(L, 'FName'),  'Klassenfeld');
    Assert.AreEqual('char',    P.DeclaredTypeOf(L, 'c'),      'Char');
    Assert.AreEqual('',        P.DeclaredTypeOf(L, 'Nix'),    'unbekannt bleibt leer');
    Assert.AreEqual('',        P.DeclaredTypeOf(L, ''),       'leerer Name');
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.DeclaredTypeOf_Unopened_Empty;
var
  P : TSourcePlaces;
begin
  P := TSourcePlaces.Create;
  try
    Assert.AreEqual('', P.DeclaredTypeOf(1, 'Marker'), 'total: ohne Datei leer');
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_ResolvesPlainIdentifierOperands;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  Path := WriteTemp(SRC_TYPES);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    // Kette 1: Marker (string) + Literal + IntToStr(Id) + Tag (const string)
    Info := P.ChainOf(LineOf(SRC_TYPES, 'r := Marker + ''id:'''),
      ColOf(SRC_TYPES, 'r := Marker + ''id:'''), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(5, Length(Info.Parts));
      Assert.IsTrue(Info.Parts[1].ValueType = rvString, 'Marker: string');
      Assert.AreEqual('string', Info.Parts[1].Resolved, 'Resolved traegt den Typ');
      Assert.IsTrue(Info.Parts[4].ValueType = rvString, 'Tag: const string');
      Assert.IsTrue(Info.FixSafe, 'alle Terme beweisbar String');
    finally
      Info.Free;
    end;
    // Kette 2: n ist Integer -> rvNonString, FName (Feld) ist String
    Info := P.ChainOf(LineOf(SRC_TYPES, 'r := Marker + ''n:'''),
      ColOf(SRC_TYPES, 'r := Marker + ''n:'''), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[3].ValueType = rvNonString, 'n: Integer');
      Assert.AreEqual('integer', Info.Parts[3].Resolved);
      Assert.IsTrue(Info.Parts[4].ValueType = rvString, 'FName: string (Feld)');
      Assert.IsFalse(Info.FixSafe, 'ein Nicht-String-Term sperrt');
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_CharOperand_IsString;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  // Format nimmt ein Char fuer %s - der Typ-Resolver fuehrt Char unter
  // den Ordinalen, hier zaehlt es als String.
  Path := WriteTemp(SRC_TYPES);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.ChainOf(LineOf(SRC_TYPES, 'r := ''x'' + c'),
      ColOf(SRC_TYPES, 'r := ''x'' + c'), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[2].ValueType = rvString, 'c: Char');
      Assert.AreEqual('char', Info.Parts[2].Resolved);
      Assert.IsTrue(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_NeverDowngradesKnownCalls;
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
begin
  // IntToStr(Id)/QuotedStr(Tag) sind schon vom Zerleger rvString; die
  // Typaufloesung fasst nur blosse Bezeichner an.
  Path := WriteTemp(SRC_TYPES);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.ChainOf(LineOf(SRC_TYPES, 'r := ''x'' + c'),
      ColOf(SRC_TYPES, 'r := ''x'' + c'), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[4].ValueType = rvString, 'QuotedStr(Tag)');
      Assert.AreEqual('', Info.Parts[4].Resolved, 'kein Bezeichner, kein Typname');
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_MultiLineLastStatement_ResolvesLaterLines;
const
  SRC =
    'unit t; interface'#13#10 +
    'type TFoo = class'#13#10 +
    '  procedure Bar(Id: Integer; const Tag: string);'#13#10 +
    'end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Bar(Id: Integer; const Tag: string);'#13#10 +
    'var Marker, r: string;'#13#10 +
    'begin'#13#10 +
    '  r := Marker + '' a '''#13#10 +
    '    + IntToStr(Id) + '' b '''#13#10 +
    '    + Tag;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P    : TSourcePlaces;
  Path : string;
  Info : TRefactorInfo;
  Last : Integer;
begin
  Path := WriteTemp(SRC);
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path));
    Info := P.ChainOf(LineOf(SRC, 'r := Marker'), ColOf(SRC, 'r := Marker'), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Last := High(Info.Parts);
      Assert.AreEqual('Tag', P.TextOf(Info.Parts[Last]));
      Assert.IsTrue(Info.Parts[Last].StartLine > Info.Span.StartLine,
        'der Term liegt auf einer Fortsetzungszeile');
      Assert.IsTrue(Info.Parts[Last].ValueType = rvString,
        'Tag auf der Fortsetzungszeile ist der const-Parameter');
      Assert.AreEqual('string', Info.Parts[Last].Resolved);
      Assert.IsTrue(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    P.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.OpenSource_MatchesOpenFromFile;
var
  P, Q         : TSourcePlaces;
  Path         : string;
  InfoP, InfoQ : TRefactorInfo;
  L, C, i      : Integer;
begin
  Path := WriteTemp(SRC_TYPES);
  P := TSourcePlaces.Create;
  Q := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.Open(Path), 'von der Platte');
    Assert.IsTrue(Q.OpenSource('puffer.pas', SRC_TYPES), 'aus dem Text');
    Assert.AreEqual('puffer.pas', Q.FileName);
    Assert.AreEqual<Integer>(P.LineCount, Q.LineCount);
    L := LineOf(SRC_TYPES, 'r := Marker + ''id:''');
    C := ColOf(SRC_TYPES, 'r := Marker + ''id:''');
    InfoP := P.ChainOf(L, C, 'r');
    InfoQ := Q.ChainOf(L, C, 'r');
    try
      Assert.IsTrue(Assigned(InfoP) and Assigned(InfoQ));
      Assert.AreEqual<Integer>(Length(InfoP.Parts), Length(InfoQ.Parts));
      for i := 0 to High(InfoP.Parts) do
      begin
        Assert.AreEqual(P.TextOf(InfoP.Parts[i]), Q.TextOf(InfoQ.Parts[i]));
        Assert.IsTrue(InfoP.Parts[i].ValueType = InfoQ.Parts[i].ValueType,
          'Typ von Teil ' + IntToStr(i));
      end;
      Assert.IsTrue(InfoP.FixSafe = InfoQ.FixSafe);
      Assert.AreEqual(P.HashOf(InfoP.Span), Q.HashOf(InfoQ.Span));
    finally
      InfoP.Free;
      InfoQ.Free;
    end;
    Assert.IsFalse(Q.OpenSource('leer.pas', ''), 'leerer Text oeffnet nichts');
    Assert.IsFalse(Q.IsOpen);
  finally
    P.Free;
    Q.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestSourcePlacesTypes.SectionLine_AndLineText;
var
  P : TSourcePlaces;
begin
  P := TSourcePlaces.Create;
  try
    Assert.AreEqual<Integer>(0, P.SectionLine(TUsesSection.usInterface), 'ohne Datei 0');
    Assert.AreEqual('', P.LineText(1), 'ohne Datei leer');

    Assert.IsTrue(P.OpenSource('t.pas', SRC_TYPES));
    Assert.AreEqual<Integer>(1, P.SectionLine(TUsesSection.usInterface),
      'interface steht auf Zeile 1 (hinter unit t;)');
    Assert.AreEqual<Integer>(6, P.SectionLine(TUsesSection.usImplementation));
    Assert.AreEqual<Integer>(0, P.SectionLine(TUsesSection.usAny), 'usAny liefert 0');
    Assert.AreEqual('implementation', P.LineText(6));
    Assert.AreEqual('', P.LineText(0));
    Assert.AreEqual('', P.LineText(999));

    Assert.IsTrue(P.OpenSource('p.dpr', 'program p;'#13#10'begin'#13#10'end.'));
    Assert.AreEqual<Integer>(0, P.SectionLine(TUsesSection.usImplementation),
      'ein Programm hat keinen implementation-Abschnitt');
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlacesTypes.SpanHasComment_OnlyInsideSpan;
const
  SRC =
    'unit c; interface implementation'#13#10 +
    'procedure P; var r, a: string; begin'#13#10 +
    '  r := a + { alt } ''x'';'#13#10 +
    '  r := ''y'';  // Ende'#13#10 +
    'end; end.';
var
  P : TSourcePlaces;
begin
  P := TSourcePlaces.Create;
  try
    Assert.IsFalse(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 3, 1, 3, 10)),
      'ohne Datei False');
    Assert.IsTrue(P.OpenSource('c.pas', SRC));
    Assert.IsTrue(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 3, 1, 3, 24)),
      'ganze Zeile 3 traegt den Blockkommentar');
    Assert.IsFalse(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 3, 1, 3, 10)),
      '''r := a'' liegt vor dem Kommentar');
    Assert.IsFalse(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 3, 19, 3, 24)),
      '''''x''; liegt hinter dem Kommentar');
    Assert.IsFalse(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 4, 1, 4, 12)),
      'Zeile 4 bis vor den Zeilenkommentar');
    Assert.IsTrue(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 4, 1, 4, 22)),
      'Zeile 4 mit Zeilenkommentar');
    Assert.IsFalse(P.SpanHasComment(TRefactorSpan.Make(ROLE_STATEMENT, 90, 1, 91, 2)),
      'ausserhalb der Datei False');
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_WithBlockShadowing_StaysUnknown;
const
  SRC =
    'unit w; interface'#13#10 +
    'type TRec = record s: Variant; end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var s, r: string; Rec: TRec;'#13#10 +
    'begin'#13#10 +
    '  with Rec do'#13#10 +
    '    r := ''a'' + s + ''b'' + s;'#13#10 +
    '  r := ''c'' + s + ''d'' + s;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P         : TSourcePlaces;
  InL, OutL : Integer;
  Info      : TRefactorInfo;
begin
  InL  := LineOf(SRC, 'r := ''a''');
  OutL := LineOf(SRC, 'r := ''c''');
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.OpenSource('w.pas', SRC));
    Assert.IsTrue(P.InWithBlock(InL), 'Zeile im Rumpf des with');
    Assert.IsTrue(P.InWithBlock(LineOf(SRC, 'with Rec do')),
      'die Zeile des with-Kopfs zaehlt mit');
    Assert.IsFalse(P.InWithBlock(OutL), 'hinter dem with');
    Assert.IsFalse(P.InWithBlock(LineOf(SRC, 'var s, r')));

    Info := P.ChainOf(InL, ColOf(SRC, 'r := ''a'''), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('s', P.TextOf(Info.Parts[2]));
      Assert.IsTrue(Info.Parts[2].ValueType = rvUnknown,
        'der Compiler bindet s an Rec.s (Variant) - nichts bewiesen');
      Assert.AreEqual('string', Info.Parts[2].Resolved,
        'Resolved bleibt der Typ der gefundenen Deklaration');
      Assert.IsFalse(Info.FixSafe);
    finally
      Info.Free;
    end;

    Info := P.ChainOf(OutL, ColOf(SRC, 'r := ''c'''), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[2].ValueType = rvString,
        'Gegenprobe: ohne with ist s die lokale string-Variable');
      Assert.IsTrue(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlacesTypes.ChainOf_LocalFuncShadowsKnownCall_NotFixSafe;
const
  SRC =
    'unit f; interface'#13#10 +
    'function Trim(const S: string): Variant;'#13#10 +
    'implementation'#13#10 +
    'function Trim(const S: string): Variant;'#13#10 +
    'begin'#13#10 +
    '  Result := S;'#13#10 +
    'end;'#13#10 +
    'procedure P(const x, y: string);'#13#10 +
    'var r: string;'#13#10 +
    'begin'#13#10 +
    '  r := ''a'' + Trim(x) + ''b'' + Trim(y);'#13#10 +
    '  r := ''a'' + SysUtils.Trim(x) + ''b'' + QuotedStr(y);'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P    : TSourcePlaces;
  Info : TRefactorInfo;
begin
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.OpenSource('f.pas', SRC));
    Info := P.ChainOf(LineOf(SRC, 'Trim(x) + ''b'' + Trim(y)'),
      ColOf(SRC, 'r := ''a'' + Trim'), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('Trim(x)', P.TextOf(Info.Parts[2]));
      Assert.IsTrue(Info.Parts[2].ValueType = rvUnknown,
        'Trim ist hier die Funktion der Unit (Variant), nicht SysUtils.Trim');
      Assert.IsTrue(Info.Parts[4].ValueType = rvUnknown);
      Assert.IsFalse(Info.FixSafe);
    finally
      Info.Free;
    end;
    Info := P.ChainOf(LineOf(SRC, 'SysUtils.Trim(x)'),
      ColOf(SRC, 'r := ''a'' + SysUtils'), 'r');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[2].ValueType = rvString,
        'qualifiziert: die RTL ist gemeint');
      Assert.IsTrue(Info.Parts[4].ValueType = rvString,
        'QuotedStr verdeckt die Unit nicht');
      Assert.IsTrue(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    P.Free;
  end;
end;

const
  // Minor 11: ShortString-Deklarationen in allen Formen, die der Resolver
  // sieht, dazu zwei 'string' als Gegenprobe. Die inline-var legt der
  // Parser als 'string [ 16 ]' ab, die uebrigen als 'string[N]'.
  SRC_SHORT =
    'unit s; interface'#13#10 +
    'type TFoo = class'#13#10 +
    '  FBuf: string[10];'#13#10 +
    '  procedure Bar;'#13#10 +
    'end;'#13#10 +
    'var GBuf: string[20]; GStr: string;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Bar;'#13#10 +
    'var Buf: string[8]; S: string; Sh: ShortString;'#13#10 +
    'begin'#13#10 +
    '  var Tmp: string[16];'#13#10 +
    '  S := Buf + Tmp + GBuf + GStr + FBuf + Sh;'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestSourcePlacesViews.DeclaredTypeOf_StringN_IsShortString;
var
  P : TSourcePlaces;
  L : Integer;
begin
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.OpenSource('s.pas', SRC_SHORT));
    L := LineOf(SRC_SHORT, 'S := Buf');
    Assert.AreEqual('shortstring', P.DeclaredTypeOf(L, 'Buf'), 'lokal string[8]');
    Assert.AreEqual('shortstring', P.DeclaredTypeOf(L, 'Tmp'),
      'inline-var string [ 16 ]');
    Assert.AreEqual('shortstring', P.DeclaredTypeOf(L, 'GBuf'),
      'Unit-Global string[20]');
    Assert.AreEqual('shortstring', P.DeclaredTypeOf(L, 'FBuf'),
      'Klassenfeld string[10]');
    Assert.AreEqual('shortstring', P.DeclaredTypeOf(L, 'Sh'), 'ShortString');
    Assert.AreEqual('string', P.DeclaredTypeOf(L, 'S'), 'Gegenprobe lokal');
    Assert.AreEqual('string', P.DeclaredTypeOf(L, 'GStr'), 'Gegenprobe global');
  finally
    P.Free;
  end;
end;

procedure TTestSourcePlacesViews.TypeResolver_ShortStringOnlyOptIn;
var
  Parser : TParser2;
  Root   : TAstNode;
  R      : TTypeResolver;
  L      : Integer;
begin
  L := LineOf(SRC_SHORT, 'S := Buf');
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC_SHORT);
    try
      R := TTypeResolver.Create(Root);
      try
        Assert.AreEqual('string', R.ResolveTypeAt('buf', L),
          'Vorgabe: der Resolver der Detektoren bleibt unveraendert');
        Assert.AreEqual('string', R.ResolveTypeAt('gbuf', L));
      finally
        R.Free;
      end;
      R := TTypeResolver.Create(Root, True);
      try
        Assert.AreEqual('shortstring', R.ResolveTypeAt('buf', L));
        Assert.AreEqual('string', R.ResolveTypeAt('s', L));
      finally
        R.Free;
      end;
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
  Assert.AreEqual('string', ReduceToBareTypeLow('string[8]'),
    'ReduceToBareTypeLow bleibt, wie es war');
  Assert.AreEqual('shortstring', ReduceToDeclaredTypeLow('string[8]'));
  Assert.AreEqual('shortstring', ReduceToDeclaredTypeLow('String [ 8 ]'));
  Assert.AreEqual('string', ReduceToDeclaredTypeLow('string'));
  Assert.AreEqual('string', ReduceToDeclaredTypeLow('string=''x'''),
    'typisierte Konstante: kein ShortString');
  Assert.AreEqual('ansistring', ReduceToDeclaredTypeLow('AnsiString(1252)'));
  Assert.AreEqual('', ReduceToDeclaredTypeLow(''));
end;

procedure TTestSourcePlacesViews.OpenSource_IgnoresGlobalIfdefView;
const
  SRC =
    'unit v; interface implementation'#13#10 +
    'procedure P;'#13#10 +
    'var A, B: Integer;'#13#10 +
    'begin'#13#10 +
    '  {$IFDEF FOO}'#13#10 +
    '  A := 1;'#13#10 +
    '  {$ELSE}'#13#10 +
    '  B := 2;'#13#10 +
    '  {$ENDIF}'#13#10 +
    'end;'#13#10 +
    'end.';
var
  P       : TSourcePlaces;
  OldSkip : Boolean;
  OldDefs : TArray<string>;
  Defs    : TArray<string>;
  D       : string;
  LA, LB  : Integer;
begin
  LA := LineOf(SRC, 'A := 1');
  LB := LineOf(SRC, 'B := 2');
  // Prozessweite Sicht sichern - der Testprozess ist resident.
  OldSkip := gLexerIfdefSkipEnabled;
  OldDefs := nil;
  if Assigned(gLexerIfdefDefines) then
    OldDefs := gLexerIfdefDefines.ToStringArray;
  P := TSourcePlaces.Create;
  try
    // So setzt ein laufender Scan die Sicht: Ein-Zweig mit FOO.
    LexerIfdefClear;
    LexerIfdefAddDefine('FOO');
    gLexerIfdefSkipEnabled := True;
    Assert.IsTrue(P.OpenSource('v.pas', SRC));
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LA, [nkAssign])), 'FOO-Zweig');
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LB, [nkAssign])),
      'auch der ELSE-Zweig: der Dienst bleibt in seiner Doppelzweig-Sicht');

    // Eigene Ein-Zweig-Sicht ohne FOO: nur der ELSE-Zweig.
    Defs := ['BAR'];
    P.SetIfdefDefines(Defs);
    Assert.IsTrue(P.OpenSource('v.pas', SRC));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(LA, [nkAssign])),
      'FOO ist in der Sicht des Dienstes nicht definiert');
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LB, [nkAssign])));

    // Eigene Sicht mit FOO, die prozessweite ist aus.
    LexerIfdefClear;
    gLexerIfdefSkipEnabled := False;
    Defs := ['FOO'];
    P.SetIfdefDefines(Defs);
    Defs[0] := 'BAR';   // die Sicht ist eine Kopie
    Assert.IsTrue(P.OpenSource('v.pas', SRC));
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LA, [nkAssign])));
    Assert.AreEqual<Integer>(0, Length(P.NodesAt(LB, [nkAssign])),
      'der ELSE-Zweig ist aus');

    // Zurueck zur Vorgabe.
    P.SetIfdefDefines(nil);
    Assert.IsTrue(P.OpenSource('v.pas', SRC));
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LA, [nkAssign])));
    Assert.AreEqual<Integer>(1, Length(P.NodesAt(LB, [nkAssign])));
  finally
    P.Free;
    LexerIfdefClear;
    for D in OldDefs do
      LexerIfdefAddDefine(D);
    gLexerIfdefSkipEnabled := OldSkip;
  end;
end;

initialization
  Randomize;
  TDUnitX.RegisterTestFixture(TTestSourcePlacesTypes);
  TDUnitX.RegisterTestFixture(TTestSourcePlacesViews);

end.
