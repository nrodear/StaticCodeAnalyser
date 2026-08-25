unit uTestInterfaceGuid;

// Tests fuer SCA197 (Interface ohne GUID) und SCA198 (GUID doppelt).
//
// Der Einzeldatei-Harness (FindingsOfFile) laeuft OHNE Scan-Index. SCA198
// vergleicht dann nur innerhalb der Datei - genau das ist hier pruefbar.
// Die projektweite Seite (uInterfaceGuidIndex.Build ueber mehrere Dateien)
// hat eigene Tests weiter unten, die den Index direkt fuellen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInterfaceGuid = class
  public
    // --- SCA197: GUID fehlt ---------------------------------------------
    [Test] procedure InterfaceWithoutGuid_Reported;
    [Test] procedure InterfaceWithGuid_NotReported;
    [Test] procedure InterfaceWithAncestorAndGuid_NotReported;
    [Test] procedure GenericInterfaceWithoutGuid_Reported;
    // Eine Vorwaertsdeklaration DARF keine GUID tragen - der Compiler
    // laesst es nicht zu. Sie zu melden hiesse, zu nicht uebersetzbarem
    // Code zu raten.
    [Test] procedure ForwardDeclaration_NotReported;
    // 'dispinterface' endet auf 'interface'. Ohne Wortgrenze links liefe
    // der Scanner darauf - und dispinterfaces gehoeren nicht zu dieser
    // Regel.
    [Test] procedure DispInterface_NotReported;
    // Das Unit-Schluesselwort 'interface' hat kein '=' links.
    [Test] procedure UnitInterfaceSection_NotReported;
    // Auskommentiertes zaehlt nie als Code.
    [Test] procedure CommentedOutInterface_NotReported;
    // Eckige Klammern mit Nicht-GUID-Inhalt: weder "fehlt" noch "doppelt"
    // ist entscheidbar, also schweigt die Regel.
    [Test] procedure NonGuidBracket_NotReported;
    // REGRESSIONSANKER (Review 2026-08-25, Blocker): der Kommentar-Strip
    // laesst Strings stehen - er MUSS, sonst waere die GUID selbst weg.
    // Ohne die Anfuehrungszeichen-Pruefung sah der Scanner jedes
    // 'IFoo = interface' in einem Literal als Deklaration. Gemessen:
    // 85 solcher Phantome in 13 Dateien dieses Repos, darunter
    // uFixHint.pas. Der Bestandsdetektor uEmptyInterface hat die Luecke
    // heute noch (5 Funde im tests-Verzeichnis) - hier nicht mehr.
    [Test] procedure InterfaceInStringLiteral_NotReported;
    [Test] procedure GuidInStringLiteral_NoDuplicate;
    [Test] procedure Sca197_KindAndSeverity;

    // --- SCA198: GUID doppelt -------------------------------------------
    [Test] procedure SameGuidTwiceInFile_ReportedAtBoth;
    [Test] procedure DifferentGuids_NotReported;
    // Gross-/Kleinschreibung ist bei GUIDs bedeutungslos - wer sie von
    // Hand abtippt, macht daraus leicht zwei Schreibweisen derselben GUID.
    [Test] procedure SameGuidDifferentCase_Reported;
    // Die Meldung muss den ANDEREN Ort nennen; ohne ihn faengt die Suche
    // bei null an, und genau die ist die eigentliche Arbeit.
    [Test] procedure DuplicateMessageNamesTheOtherSite;
    // GLEICHNAMIGKEITS-GATE (Korpusmessung 2026-08-25): dieselbe GUID am
    // GLEICHEN Namen ist dieselbe Deklaration zweimal im Baum, nicht ein
    // zweites Interface. 1.505 der 1.705 Korpusfunde waren von der Art -
    // und der Rat "erzeuge eine neue GUID" waere dort schaedlich, er
    // machte die beiden Kopien unvertraeglich.
    [Test] procedure SameNameSameGuid_NotReported;

    // --- Der Index selbst ------------------------------------------------
    [Test] procedure NormalizeGuid_AcceptsCanonicalForm;
    [Test] procedure NormalizeGuid_RejectsNonGuid;
    [Test] procedure ScanFile_ReadsNameLineAndGuid;
  end;

implementation

// noinspection-file DuplicateString, LegacyInitializationSection
// DuplicateString: die Testquellen sind FIXTURES. "unit t;",
// "interface", "end." und die Beispiel-GUID stehen bewusst in jedem
// Fall woertlich da - wer sie zu Konstanten zusammenzieht, muss beim
// Lesen eines Tests wieder nach oben springen, um zu sehen, was
// eigentlich gescannt wird. Genau das soll ein Fixture nicht.

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uInterfaceGuidIndex,
  uTestFindingHelper;

function Quelltext(const AZeilen: array of string): string;
// Baut eine Unit aus Zeilen. Spart in jedem Test die #13#10-Kette und
// macht die Zeilennummern im Test ablesbar (Zeile 1 = erstes Element).
var
  i : Integer;
begin
  Result := '';
  for i := Low(AZeilen) to High(AZeilen) do
    Result := Result + AZeilen[i] + #13#10;
end;

{ ------------------------------------------------------------- SCA197 }

procedure TTestInterfaceGuid.InterfaceWithoutGuid_Reported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.InterfaceWithGuid_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.InterfaceWithAncestorAndGuid_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface(IInterface)',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.GenericInterfaceWithoutGuid_Reported;
// `IList<T> = interface` - der Name steht links von '<', nicht direkt
// links vom '='. Ohne die Klammer-Rueckwaertssuche fiele der Fund aus.
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IList<T> = interface',
    '    procedure Add(const AItem: T);',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'generisches Interface ohne GUID nicht erkannt');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.ForwardDeclaration_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface;',
    '  IBar = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Foo: IFoo;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'Vorwaertsdeklaration gemeldet - sie DARF keine GUID tragen');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.DispInterface_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = dispinterface',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'dispinterface gemeldet - die linke Wortgrenze greift nicht');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.UnitInterfaceSection_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface',
    'procedure Foo;',
    'implementation',
    'procedure Foo; begin end;',
    'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.CommentedOutInterface_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  // IFoo = interface',
    '  //   procedure Bar;',
    '  // end;',
    '  TFoo = class end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'Kommentar als Code gewertet');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.NonGuidBracket_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface',
    '    [SOME_GUID_CONST]',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'Klammer ohne GUID-Form: weder fehlt noch doppelt ist entscheidbar');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.InterfaceInStringLiteral_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'const',
    '  TEMPLATE =',
    '    ''IFoo = interface''#13#10 +',
    '    ''  procedure Bar;''#13#10 +',
    '    ''end;'';',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid),
      'Pascal in einem String-Literal ist kein Code');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.GuidInStringLiteral_NoDuplicate;
// Der teurere Fall derselben Luecke: ein Code-Generator, der zwei
// Interface-Vorlagen mit DERSELBEN Beispiel-GUID als Strings fuehrt,
// haette einen SCA198-Fund auf Error-Stufe erzeugt - fuer Text, der nie
// uebersetzt wird.
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'const',
    '  VORLAGE_A = ''IReader = interface [''''{2A3B4C5D-1111-2222-3333-444455556666}'''']'';',
    '  VORLAGE_B = ''IWriter = interface [''''{2A3B4C5D-1111-2222-3333-444455556666}'''']'';',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkDuplicateInterfaceGuid),
      'zwei Vorlagen-Strings sind keine zwei Interfaces');
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkInterfaceWithoutGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.Sca197_KindAndSeverity;
var
  F : TObjectList<TLeakFinding>;
  i : Integer;
  Gefunden : Boolean;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IFoo = interface',
    '    procedure Bar;',
    '  end;',
    'implementation', 'end.']));
  try
    Gefunden := False;
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkInterfaceWithoutGuid then
      begin
        Gefunden := True;
        Assert.AreEqual('4', F[i].LineNumber,
          'Fund muss auf der Zeile des Interface-Namens sitzen');
        Assert.IsTrue(Pos('IFoo', F[i].MissingVar) > 0,
          'Meldung nennt das Interface nicht: ' + F[i].MissingVar);
        Assert.AreEqual<TLeakSeverity>(lsWarning, F[i].Severity,
          'SCA197 ist eine Warning (KIND_META)');
      end;
    Assert.IsTrue(Gefunden, 'kein SCA197-Fund');
  finally F.Free; end;
end;

{ ------------------------------------------------------------- SCA198 }

procedure TTestInterfaceGuid.SameGuidTwiceInFile_ReportedAtBoth;
// Beide Stellen werden gemeldet. Nur eine zu melden hiesse, willkuerlich
// eine davon zur richtigen zu erklaeren - welche das ist, weiss nur der
// Autor.
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IReader = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '  IWriter = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    procedure Write(const S: string);',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(2,
      TFindingHelper.Count(F, fkDuplicateInterfaceGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.DifferentGuids_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IReader = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '  IWriter = interface',
    '    [''{9B7E30C4-2D18-4A55-8F61-70E5C2A4193D}'']',
    '    procedure Write(const S: string);',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkDuplicateInterfaceGuid));
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.SameGuidDifferentCase_Reported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IReader = interface',
    '    [''{2a3b4c5d-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '  IWriter = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    procedure Write(const S: string);',
    '  end;',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(2,
      TFindingHelper.Count(F, fkDuplicateInterfaceGuid),
      'Schreibweise darf keinen Unterschied machen');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.DuplicateMessageNamesTheOtherSite;
var
  F : TObjectList<TLeakFinding>;
  i : Integer;
  Text : string;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IReader = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '  IWriter = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    procedure Write(const S: string);',
    '  end;',
    'implementation', 'end.']));
  try
    Text := '';
    for i := 0 to F.Count - 1 do
      if (F[i].Kind = fkDuplicateInterfaceGuid) and (F[i].LineNumber = '4') then
        Text := F[i].MissingVar;
    Assert.IsNotEmpty(Text, 'kein SCA198-Fund auf Zeile 4');
    Assert.IsTrue(Pos('IWriter', Text) > 0,
      'Meldung nennt die andere Stelle nicht: ' + Text);
    Assert.IsTrue(Pos(':8', Text) > 0,
      'Meldung nennt die Zeile der anderen Stelle nicht: ' + Text);
  finally F.Free; end;
end;

{ -------------------------------------------------------------- Index }

procedure TTestInterfaceGuid.SameNameSameGuid_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;', 'interface', 'type',
    '  IReader = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '{$IFDEF ZWEITE_KOPIE}',
    '  IReader = interface',
    '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
    '    function Read: string;',
    '  end;',
    '{$ENDIF}',
    'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkDuplicateInterfaceGuid),
      'gleicher Name = dieselbe Deklaration, kein GUID-Diebstahl');
  finally F.Free; end;
end;

procedure TTestInterfaceGuid.NormalizeGuid_AcceptsCanonicalForm;
begin
  Assert.AreEqual('2A3B4C5D-1111-2222-3333-444455556666',
    TInterfaceGuidIndex.NormalizeGuid('''{2a3b4c5d-1111-2222-3333-444455556666}'''),
    'kanonische Form mit Klammern und Anfuehrungszeichen');
  Assert.AreEqual('2A3B4C5D-1111-2222-3333-444455556666',
    TInterfaceGuidIndex.NormalizeGuid('  {2A3B4C5D-1111-2222-3333-444455556666}  '),
    'Leerraum drumherum');
end;

procedure TTestInterfaceGuid.NormalizeGuid_RejectsNonGuid;
// Die Form wird geprueft, nicht nur die Laenge. Sonst gaelte jede
// Konstante als GUID und zwei gleichnamige Konstanten als Duplikat.
begin
  Assert.AreEqual('', TInterfaceGuidIndex.NormalizeGuid('SOME_CONST'),
    'Bezeichner');
  Assert.AreEqual('', TInterfaceGuidIndex.NormalizeGuid(''),
    'leer');
  Assert.AreEqual('',
    TInterfaceGuidIndex.NormalizeGuid('{2A3B4C5D-1111-2222-3333-44445555666}'),
    'letzte Gruppe zu kurz');
  Assert.AreEqual('',
    TInterfaceGuidIndex.NormalizeGuid('{2A3B4C5X-1111-2222-3333-444455556666}'),
    'X ist keine Hexziffer');
  Assert.AreEqual('',
    TInterfaceGuidIndex.NormalizeGuid('{2A3B4C5D111122223333444455556666}'),
    'ohne Bindestriche');
end;

procedure TTestInterfaceGuid.ScanFile_ReadsNameLineAndGuid;
var
  L     : TStringList;
  Decls : TArray<TInterfaceDecl>;
begin
  L := TStringList.Create;
  try
    L.Text := Quelltext([
      'unit t;', 'interface', 'type',
      '  IFoo = interface',
      '    [''{2A3B4C5D-1111-2222-3333-444455556666}'']',
      '    procedure Bar;',
      '  end;',
      '  IOhne = interface',
      '    procedure Baz;',
      '  end;',
      'implementation', 'end.']);
    Decls := TInterfaceGuidIndex.ScanFile('t.pas', L);

    Assert.AreEqual<Integer>(2, Length(Decls), 'zwei Deklarationen erwartet');
    Assert.AreEqual('IFoo', Decls[0].Name);
    Assert.AreEqual<Integer>(4, Decls[0].Line);
    Assert.AreEqual('2A3B4C5D-1111-2222-3333-444455556666', Decls[0].Guid);
    Assert.AreEqual('IOhne', Decls[1].Name);
    Assert.AreEqual<Integer>(8, Decls[1].Line);
    Assert.AreEqual('', Decls[1].Guid);
    Assert.IsFalse(Decls[1].GuidUnparsed,
      'keine Klammern != unlesbare Klammern');
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInterfaceGuid);

end.
