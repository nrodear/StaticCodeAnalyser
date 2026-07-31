unit uTestEmptyInterface;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyInterface = class
  public
    [Test] procedure InterfaceWithMethods_NoFinding;
    [Test] procedure EmptyInterfaceMultiline_Reported;
    [Test] procedure EmptyInterfaceWithParent_Reported;
    [Test] procedure EmptyInterfaceWithGuid_Reported;
    [Test] procedure UnitInterfaceSection_NotReported;
    [Test] procedure EmptyInterface_KindAndSeverity;
    // --- Restschulden-Audit 2026-07-26: Strip-Zentralisierung ---
    // Der Detektor lief bis dahin auf einer gedrifteten lokalen Kopie
    // (StripCommentsFile) statt auf TDetectorUtils.
    // StripFileCommentsKeepStringsCached. Einzige beobachtbare Kante der
    // Kopie: eine Zeile, die KOMPLETT in einem mehrzeiligen
    // `{..}`/`(*..*)`-Block liegt (lokal: zusaetzliches Leerzeichen,
    // zentral: nichts). Beide Tests halten Fund UND Fundzeile fest.
    [Test] procedure EmptyInterfaceMultilineComment_Reported;
    [Test] procedure MultilineCommentInterfaceWithMethod_NotReported;
    // --- Ancestor-Gate (Real-World-Audit 2026-07-31) ---------------------
    // Ein leerer Rumpf UNTER einem benannten Vorfahren erbt dessen Vertrag;
    // die Regel-Praemisse "carries no contract" trifft dann nicht zu. Alle
    // sieben _NotReported-Tests waeren OHNE den Gate ROT (der Detektor sah
    // nur "keine Member zwischen interface und end").
    [Test] procedure ObjCBridgeGuidAncestor_NotReported;
    [Test] procedure JniBridgeJavaSignature_NotReported;
    [Test] procedure TlbDispatchAncestor_NotReported;
    [Test] procedure DerivedDiscriminatorAncestor_NotReported;
    [Test] procedure NestedTypeBridgeAncestor_NotReported;
    [Test] procedure GenericAncestor_NotReported;
    [Test] procedure NamedAncestorWithoutGuid_NotReported;
    // GEGENPROBEN zum Gate: IInterface/IUnknown sind KEINE benannten
    // Vorfahren (IInterface ist der implizite Default) - diese Funde
    // muessen den Gate ueberleben, sonst waere er ein Blanket-Skip fuer
    // "hat Klammern".
    [Test] procedure IInterfaceAncestorWithGuid_StillReported;
    [Test] procedure QualifiedIInterfaceAncestor_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyInterface.InterfaceWithMethods_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IFoo = interface'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceMultiline_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithParent_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IService = interface(IUnknown) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithGuid_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  '  [''{12345678-1234-1234-1234-123456789012}'']'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.UnitInterfaceSection_NotReported;
// Das Unit-Section-`interface` (vor `implementation`) darf NICHT als
// EmptyInterface gemeldet werden - es hat kein `=` davor.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterface_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyInterface then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyInterface, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyInterface finding');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceMultilineComment_Reported;
// FIX-TEST zur Strip-Zentralisierung (Restschulden-Audit 2026-07-26).
// Zwei DREIzeilige Blockkommentare - je die MITTLERE Zeile liegt komplett
// im Kommentar und trifft damit genau den Zweig, in dem die geloeschte
// lokale Kopie ein Extra-Leerzeichen ausgab:
//   * der erste Block liegt VOR dem Interface -> verschiebt alle
//     Folgepositionen und damit die LineFor-Map (Fundzeile muss stimmen),
//   * der zweite liegt IM Rumpf -> landet im Leer-Test zwischen
//     `interface` und `end` (Rumpf muss weiterhin als leer gelten).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  { Doku-Kommentar'#13#10 +
  '    ueber drei'#13#10 +
  '    Zeilen }'#13#10 +
  '  IMarker = interface'#13#10 +
  '    { auch im Rumpf'#13#10 +
  '      ueber mehrere'#13#10 +
  '      Zeilen }'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface),
      'Rumpf aus reinem Blockkommentar ist leer - genau 1 Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'IMarker = interface'),
      TFindingHelper.FirstOf(F, fkEmptyInterface).LineNumber,
      'Fundzeile muss trotz vorangehendem Mehrzeilen-Kommentar stimmen');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.MultilineCommentInterfaceWithMethod_NotReported;
// GEGENPROBE: identisches Kommentar-Layout, aber der Rumpf enthaelt einen
// echten Vertrag. Haette der Strip Kommentar-Inhalt stehen lassen oder die
// Methodenzeile mit-verschluckt, waere hier ein FP (bzw. bei der
// Fix-Variante ein FN) sichtbar.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  { Doku-Kommentar'#13#10 +
  '    ueber drei'#13#10 +
  '    Zeilen }'#13#10 +
  '  IMarker = interface'#13#10 +
  '    { auch im Rumpf'#13#10 +
  '      ueber mehrere'#13#10 +
  '      Zeilen }'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Interface mit Methode ist nicht leer - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.ObjCBridgeGuidAncestor_NotReported;
// FP-Klasse 1 (Kastri DW.*, 2685 Korpus-Funde): ObjC-Bruecken-Idiom. Der
// Vertrag liegt in NSObjectClass bzw. wird von TOCGenericImport zur Laufzeit
// geliefert; die Meldungsempfehlung (Attribut-Klasse) wuerde die Bindung
// brechen. Originalstelle: Kastri/API/DW.iOSapi.Intents.pas:6608.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  INDefaultCardTemplateClass = interface(NSObjectClass)'#13#10 +
  '    [''{8D2C7C80-060E-4A50-AD14-1F5571227731}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'ObjC-Bruecke erbt den Vertrag aus NSObjectClass - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.JniBridgeJavaSignature_NotReported;
// FP-Klasse 1b: JNI-Variante. Zusaetzlich abgesichert ist, dass das
// vorangestellte [JavaSignature(...)]-Attribut den Links-Kontext-Test
// (`=` vor `interface`) nicht stoert. Original: DW.Androidapi.JNI.Text.pas:78.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  [JavaSignature(''android/text/Html'')]'#13#10 +
  '  JHtml = interface(JObject)'#13#10 +
  '    [''{937D7A71-86A7-478B-A43E-299BDD1333E9}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'JNI-Bindung holt die Member ueber TJavaGenericImport - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.TlbDispatchAncestor_NotReported;
// FP-Klasse 2 (563 Korpus-Funde): generierter Typbibliotheks-Import. Der
// Automationsvertrag steckt in IDispatch, die Datei ist nicht editierbar.
// Original: jcl/jcl/source/windows/mscorlib_TLB.pas:13145.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  _Publisher = interface(IDispatch)'#13#10 +
  '    [''{77CCA693-ABF6-3773-BF58-C0B02701A744}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'IDispatch traegt den Automationsvertrag - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.DerivedDiscriminatorAncestor_NotReported;
// FP-Klasse 3 (Handschrift, nicht generiert): der leere Untertyp ist der
// Schluessel fuer `as`/Supports. Im Korpus belegt durch
// `aTargetFileSource as IFileSystemFileSource`
// (doublecmd-master/src/filesources/filesystem/ufilesystemcreatedirectoryoperation.pas:37)
// - loeschen oder in eine Attribut-Klasse wandeln bricht die Uebersetzung.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IFileSystemFileSource = interface(ILocalFileSource)'#13#10 +
  '    [''{7B0EE0A4-8B7B-4A54-9F09-1FDFDB3C8C61}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Leerer Untertyp als Laufzeit-Diskriminator - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.NestedTypeBridgeAncestor_NotReported;
// Gleicher Mechanismus, aber als verschachtelter Typ in einem
// `class public type`-Block - der Detektor arbeitet source-basiert, der
// Gate darf davon nicht abhaengen. Original:
// skia4delphi/Samples/Demo/FMX/Source/ThirdParty/MobileBars.Android.pas:210.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TAndroid10 = class'#13#10 +
  '  public type'#13#10 +
  '    JInsetsClass = interface(JObjectClass)'#13#10 +
  '      [''{BDB53B96-47AA-4A43-A08F-7648EE48A7D9}'']'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Verschachteltes Bruecken-Interface - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.GenericAncestor_NotReported;
// Der Vorfahrenname muss auch dann erkannt werden, wenn generische Argumente
// folgen - und wenn diese ein Komma enthalten (die Komma-Zerlegung in
// HasNamedAncestor darf daran nicht scheitern). Original:
// delphimvcframework/sources/MVCFramework.MultiMap.pas:64.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IMVCObjectMultiMap<TVal: class> = interface(IMVCMultiMap<String, TVal>)'#13#10 +
  '    [''{1E9C1E3E-1C2D-4B0C-9A5A-2C3D4E5F6A7B}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Generischer Vorfahr mit Komma im Argument - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.NamedAncestorWithoutGuid_NotReported;
// Der Gate haengt am VORFAHREN, nicht an der GUID: auch ohne GUID erbt der
// Typ den Vertrag. Original:
// doublecmd-master/src/filesources/ulocalfilesource.pas:13.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  ILocalFileSource = interface(IRealFileSource)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Benannter Vorfahr ohne GUID - kein Fund erlaubt');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.IInterfaceAncestorWithGuid_StillReported;
// GEGENPROBE: `interface(IInterface)` ist semantisch identisch zu
// `interface` - IInterface ist der implizite Default-Vorfahr und traegt
// keinen Vertrag. Der Fund muss den Gate ueberleben, sonst waere der Gate
// ein Blanket-Skip fuer "Klammern vorhanden". Der Fund existiert real:
// Kastri/Features/FilesSelector/DW.FilesSelector.iOS.pas:27.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IItemProviderHandler = interface(IInterface)'#13#10 +
  '    [''{667E818A-3BED-42E6-8A5A-EDEE4C332622}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface),
      'IInterface ist kein vertragstragender Vorfahr - Fund muss bleiben');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'IItemProviderHandler'),
      TFindingHelper.FirstOf(F, fkEmptyInterface).LineNumber,
      'Fundzeile darf sich durch den Gate nicht verschieben');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.QualifiedIInterfaceAncestor_StillReported;
// GEGENPROBE zur Unit-Qualifizierung: HasNamedAncestor schneidet den
// Unit-Praefix ab, damit `System.IInterface` genauso als trivial gilt wie
// `IInterface`. Ohne das Abschneiden waere dieser Fund faelschlich still.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IMarkerQ = interface(System.IInterface)'#13#10 +
  '    [''{2618CCC6-0C7D-47EE-9A91-7A7F5264385D}'']'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface),
    'System.IInterface ist trivial wie IInterface - Fund muss bleiben');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyInterface);

end.
