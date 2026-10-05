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
  end;

implementation

uses
  System.SysUtils, System.Classes,
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

initialization
  Randomize;
  TDUnitX.RegisterTestFixture(TTestSourcePlacesTypes);

end.
