unit uTestPublicField;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPublicField = class
  public
    [Test] procedure PrivateFieldOnly_NoFinding;
    [Test] procedure PublicField_Reported;
    [Test] procedure PublicMethod_NoFinding;
    [Test] procedure PublicProperty_NoFinding;
    [Test] procedure PublicField_KindAndSeverity;
    // Autopsie 2026-08-26: Klammer-Balance, Kommentar-Zustand,
    // record/object-Tracking (Fix A/C/B).
    [Test] procedure MultiLineSignatureParams_NoFinding;
    [Test] procedure FuncPointerFieldHead_ReportedOnce;
    [Test] procedure PublishedInBlockComment_NoFinding;
    [Test] procedure RecordPublicField_NoFinding;
    // rw12-A/B-Fund: FPC-Export-Direktive '{$ifdef FPC} public name ...'
    // darf nach dem Kommentar-Strip keine Sektion schalten.
    [Test] procedure FpcPublicNameDirective_NoFinding;
    // rw13-A/B-Fund: 'public class var' ist ein echter Sektionskopf -
    // die Allein-Wort-Regel verlor 4 Klassenfeld-TPs (vcl.skia u.a.).
    [Test] procedure PublicClassVarField_Reported;
    // Autopsie 2026-08-27, G2 ('='-Gate, -39) und G1 (published, -37).
    [Test] procedure PublicNestedTypeAlias_NoFinding;
    [Test] procedure PublicTypedConstant_NoFinding;
    [Test] procedure PublishedComponentField_NoFinding;
    [Test] procedure PublishedThenPublic_FieldReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPublicField.PrivateFieldOnly_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicField_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    Count: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicMethod_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicProperty_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Count: Integer read FCount;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField));
  finally F.Free; end;
end;

procedure TTestPublicField.PublicField_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  'public'#13#10 +
  '  Count: Integer;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkPublicField then
      begin
        Assert.AreEqual<TFindingKind>(fkPublicField, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkPublicField finding');
  finally F.Free; end;
end;

procedure TTestPublicField.MultiLineSignatureParams_NoFinding;
// Autopsie 2026-08-26, Fix A (Klammer-Balance): die mittlere Zeile
// einer mehrzeiligen Signatur sah aus wie eine Feld-Deklaration -
// die groesste FP-Klasse des Katalogs (korpusweit -2.056 gemessen).
//
// 2026-08-27 NACHGESCHAERFT: das neue '='-Gate (G2) haette diesen Test
// entwertet - beide alten Fortsetzungszeilen haben einen Default-Wert
// ('= 30' / '= 1'), die letzte zusaetzlich ein ')'. Der Test waere also
// auch bei kaputtem Fix A gruen geblieben. Gemessen an der Replik:
// ohne Fix A meldet die alte Fassung 0, die neue 'aOwner'. Die
// defaultfreie Zeile 'aOwner: TObject;' haengt DESHALB drin - sie hat
// weder '=' noch ')' und wird einzig von der Klammer-Balance gehalten.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TFoo = class'#13#10+
  '  public'#13#10+
  '    function Reg(const aName: string;'#13#10+
  '      aOwner: TObject;'#13#10+
  '      aTimeout: Integer = 30;'#13#10+
  '      aMode: Byte = 1): Boolean;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField),
      'Parameter-Fortsetzungszeilen sind keine Felder');
  finally F.Free; end;
end;

procedure TTestPublicField.FuncPointerFieldHead_ReportedOnce;
// Gegenprobe Fix A: die KOPFZEILE eines Funktionszeiger-Feldes ist
// ein echtes oeffentliches Feld (mormot odbc ColAttributeW) - sie
// oeffnet die Klammer erst fuer ihre Fortsetzungen.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TLib = class'#13#10+
  '  public'#13#10+
  '    ColAttr: function(H: SmallInt;'#13#10+
  '      Col: Word): Integer; stdcall;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
      'Kopfzeile meldet genau einmal, Fortsetzung schweigt');
  finally F.Free; end;
end;

procedure TTestPublicField.PublishedInBlockComment_NoFinding;
// Autopsie 2026-08-26, Fix C (GPL-Header-Falle): "published by the
// Free Software Foundation" im Blockkommentar darf InPublic nicht
// schalten - Kommentare zaehlen nie (Hausinvariante).
const SRC =
  'unit t; interface'#13#10+
  '{ This program is free software; you can redistribute it'#13#10+
  '  published by the Free Software Foundation }'#13#10+
  'type'#13#10+
  '  TFrm = class'#13#10+
  '    lblName: TObject;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField),
      'Kommentar-Keyword schaltet keine Sektion');
  finally F.Free; end;
end;

procedure TTestPublicField.RecordPublicField_NoFinding;
// Autopsie 2026-08-26, Fix B: oeffentliche Felder sind bei record/
// object das Idiom - die Kapselungs-Empfehlung gilt nur fuer Klassen.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TCfg = record'#13#10+
  '  public'#13#10+
  '    Timeout: Integer;'#13#10+
  '  end;'#13#10+
  '  TBox = class'#13#10+
  '  public'#13#10+
  '    Value: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
      'record-Feld schweigt, das Klassen-Feld danach meldet');
  finally F.Free; end;
end;

procedure TTestPublicField.FpcPublicNameDirective_NoFinding;
// rw12-A/B (62 Adds): mormot.lib.static deklariert FPC-Exporte als
// '{$ifdef FPC} public name ''__udivdi3''; {$endif}' hinter dem
// Funktionskopf. Der Kommentar-Strip legte das 'public' frei und
// schaltete mitten in der Implementation eine Sektion an - lokale
// Vars wurden als Felder gemeldet. Der Schalter verlangt jetzt eine
// Allein-Wort-Zeile.
const SRC =
  'unit t; interface'#13#10 +
  'implementation'#13#10 +
  'function udivdi3(num, den: Int64): Int64; cdecl;'#13#10 +
  '  {$ifdef FPC} public name ''''__udivdi3''''; {$endif}'#13#10 +
  'var'#13#10 +
  '  q: Integer;'#13#10 +
  'begin'#13#10 +
  '  q := 1; Result := q;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField),
    'FPC-Export-Direktive schaltet keine Sektion - q ist kein Feld');
  finally F.Free; end;
end;
procedure TTestPublicField.PublicClassVarField_Reported;
// rw13-A/B: die Allein-Wort-Verengung (FPC-Export-Fix) nahm auch
// 'public class var' den Schalter - dabei ist das ein ECHTER
// Sektionskopf und FrameRate ein oeffentliches Klassenfeld
// (vcl.skia.pas:367). Die Zusatzliste laesst die bekannten
// Sektions-Formen wieder zu; 'public name' bleibt ausgesperrt.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TAni = class'#13#10 +
  '  public class var'#13#10 +
  '    FrameRate: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
    'class-var-Feld unter public class var ist ein Fund');
  finally F.Free; end;
end;

procedure TTestPublicField.PublicNestedTypeAlias_NoFinding;
// Autopsie 2026-08-27, G2 ('='-Gate): ein Nested-Type-Alias unter
// 'public type' hat ':' und ';' und keine ')' - er sah damit exakt wie
// eine Feld-Deklaration aus. Korpus: 18 Funde dieser Bauart, 17 davon
// in Alcinoe ('TCreateInstanceFunc = function: TALBroadcastReceiver;',
// Alcinoe.BroadcastReceiver.pas:26 u.a.), einer in mormot.core.threads.
// TP-Gegenprobe im selben public-Block: das echte Feld darunter meldet
// weiter - und zwar auf SEINER Zeile, nicht auf der des Alias.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TSvc = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TCreateInstanceFunc = function: TSvc;'#13#10 +
  '    Cache: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
      'Type-Alias schweigt, das Feld daneben meldet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Cache: Integer'),
      TFindingHelper.FirstOf(F, fkPublicField).LineNumber,
      'Fund haengt an der Feldzeile, nicht am Alias');
  finally F.Free; end;
end;

procedure TTestPublicField.PublicTypedConstant_NoFinding;
// Autopsie 2026-08-27, G2: eine typisierte Konstante unter einer
// NACKTEN 'const'-Zeile loest den 'const '-Praefixtest nicht aus - die
// Zeile war ein Fund (delphimvcframework MVCFramework.JWT:99 ff.,
// 7 Konstanten x 3 Repo-Kopien = 21 im Korpus). Nach dem String-Strip
// bleibt 'Issuer: string = ;' stehen: das '=' traegt die Entscheidung,
// nicht der Literal-Text.
// TP-Gegenprobe: das echte Feld ueber der const-Zeile meldet weiter.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TJwt = class'#13#10 +
  '  public'#13#10 +
  '    Cache: Integer;'#13#10 +
  '    const'#13#10 +
  '    Issuer: string = ''iss'';'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
      'typisierte Konstante schweigt, das Feld darueber meldet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Cache: Integer'),
      TFindingHelper.FirstOf(F, fkPublicField).LineNumber,
      'Fund haengt an der Feldzeile, nicht an der Konstanten');
  finally F.Free; end;
end;

procedure TTestPublicField.PublishedComponentField_NoFinding;
// Autopsie 2026-08-27, G1: published-Felder sind kein Kapselungsfehler,
// sondern die einzige Form, die der DFM-Streamer laden kann -
// TComponent.SetReference sucht das Feld ueber Owner.FieldAddress im
// Feld-Table, und der Compiler emittiert dieses Table nur fuer
// published. Korpus: 37 Funde unter explizitem 'published', alle 37
// DFM-Komponentenfelder; Vorlage issrc IDE.ImagesModule.pas:20.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TImages = class'#13#10 +
  '  published'#13#10 +
  '    LightBuildImageList: TImageList;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPublicField),
    'published-Komponentenfeld ist die vorgeschriebene Form, kein Fund');
  finally F.Free; end;
end;

procedure TTestPublicField.PublishedThenPublic_FieldReported;
// TP-Gegenprobe zu G1: der published-Zustand wird ZUGEWIESEN, nicht nur
// gesetzt - ein 'public' danach meldet wieder. Vorlage ist der einzige
// Korpus-Fall dieser Bauart, mORMot2-Beispiel rgmain.pas:76-90: der Typ
// wechselt published -> public -> published, und HelpMenu/
// HelpAboutMenuItem stehen im public-Block dazwischen. GEZAEHLT: eine
// Setzen-ohne-Loeschen-Fassung kostet genau diese 2 TPs.
// Inhaltlich ist das auch richtig - was der Autor aus published
// herausnimmt, bindet der Streamer nicht mehr (FieldAddress findet es
// nicht), also greift die Kapselungs-Empfehlung wieder.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TMain = class'#13#10 +
  '  published'#13#10 +
  '    ReportsMenu: TMenuItem;'#13#10 +
  '  public'#13#10 +
  '    HelpMenu: TMenuItem;'#13#10 +
  '  published'#13#10 +
  '    TopPanel: TPanel;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPublicField),
      'beide published-Bloecke schweigen, der public-Block dazwischen meldet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'HelpMenu: TMenuItem'),
      TFindingHelper.FirstOf(F, fkPublicField).LineNumber,
      'Fund haengt am public-Feld, nicht an einem published-Feld');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPublicField);

end.
