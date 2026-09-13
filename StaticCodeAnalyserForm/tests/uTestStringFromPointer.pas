unit uTestStringFromPointer;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStringFromPointer = class
  public
    [Test] procedure StringFromPByte_Reported;
    [Test] procedure UTF8StringFromPChar_Reported;
    [Test] procedure StringFromInteger_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure ManagedStringOperand_NotReported;
    [Test] procedure LpwstrPointerOperand_Reported;
    // Posten 274: String-Aliase und die Double-Cast-Grenze
    [Test] procedure TFileNameOperand_NotReported;
    [Test] procedure TCaptionOperand_NotReported;
    [Test] procedure DoubleCast_NotReported_KnownLimit;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 274: STRTYPES kennt jetzt TFileName und TCaption --- }
//
// STRTYPES listete nur die RTL-Kern-String-Typen. `type TFileName =
// string` (System.SysUtils) und `type TCaption = string`
// (Vcl.Controls) sind semantisch dasselbe - sie tragen einen
// Laengenpraefix, ein Cast daraus kann nicht ueberlesen.
//
// An der gebauten Exe gemessen: beide Fixturen liefern heute je 1
// Fund, nach der Ergaenzung 0. Am Korpus entfaellt keiner der 48
// Funde - fuer jeden wurde der deklarierte Operandentyp nachgesehen.

procedure TTestStringFromPointer.TFileNameOperand_NotReported;
// Heute 1 Fund, nach der Ergaenzung 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PName: TFileName; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PName);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringFromPointer),
      'TFileName ist ein String-Alias, kein Pointer');
  finally F.Free; end;
end;

procedure TTestStringFromPointer.TCaptionOperand_NotReported;
// Heute 1 Fund, nach der Ergaenzung 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PCap: TCaption; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PCap);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringFromPointer),
      'TCaption ist ein String-Alias, kein Pointer');
  finally F.Free; end;
end;

procedure TTestStringFromPointer.DoubleCast_NotReported_KnownLimit;
// BEKANNTE GRENZE, jetzt festgenagelt: der Kopf versprach frueher, ein
// 'string(PChar(x))' werde "zur Sicherheit auch geflaggt". Der Regex
// hat das nie getan - hinter dem Bezeichner verlangt er unmittelbar
// ein ")", ein inneres "(" bricht den Match ab.
// An der gebauten Exe gemessen: 0 Funde. Der Test haelt die Grenze
// fest, damit Kopf und Code nicht wieder auseinanderlaufen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: Pointer; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PChar(P));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkStringFromPointer),
      'BEKANNTE GRENZE: der Double-Cast bricht den Regex-Match ab');
  finally F.Free; end;
end;


procedure TTestStringFromPointer.StringFromPByte_Reported;
// Variable muss mit P+Grossbuchstabe beginnen (lex-Heuristik in uSCA160).
// Realistisches mORMot-Idiom: `var PBuf: PByte` oder direkter Cast `PByte(...)`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PBuf: PByte; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PBuf);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringFromPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestStringFromPointer.UTF8StringFromPChar_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PName: PChar; s: RawUTF8;'#13#10 +
  'begin'#13#10 +
  '  s := UTF8String(PName);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringFromPointer) >= 1);
  finally F.Free; end;
end;

procedure TTestStringFromPointer.StringFromInteger_NotReported;
// string(IntegerVar) ist eine andere Cast-Form (Integer->String), kein
// Pointer-Cast - kein P-Praefix -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(N: Integer);'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := IntToStr(N);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringFromPointer));
  finally F.Free; end;
end;

procedure TTestStringFromPointer.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var PBuf: PByte; s: string;'#13#10 +
  'begin'#13#10 +
  '  s := string(PBuf);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkStringFromPointer then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkStringFromPointer finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestStringFromPointer.ManagedStringOperand_NotReported;
// Real-World-FP-Audit 2026-07-10 (FP-Fix 07fe7e4): PrevS beginnt zufaellig mit
// 'P', ist aber als 'PrevS: string' deklariert. AnsiString(PrevS) ist eine
// sichere Managed-String-Wert-Konvertierung - kein Raw-Pointer, kein
// angenommener #0-Terminator, also kein Heap-Overread. Das neue Typ-Gate
// (OperandIsManagedString) loest den deklarierten Managed-Typ auf und
// unterdrueckt den Fund. Grundlage: cnwizards CnAICoderEngine.pas:846 (PrevS: string).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  PrevS: string;'#13#10 +
  '  a: AnsiString;'#13#10 +
  'begin'#13#10 +
  '  a := AnsiString(PrevS);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringFromPointer),
        'AnsiString(PrevS) mit PrevS: string ist Wert-Konvertierung, kein Pointer-Cast - kein Fund');
  finally F.Free; end;
end;

procedure TTestStringFromPointer.LpwstrPointerOperand_Reported;
// Must-stay TP (Real-World-FP-Audit 2026-07-10, FP-Fix 07fe7e4): pMimeTypeFromData
// ist als LPWSTR (Raw-Pointer) deklariert - AnsiString(pMimeTypeFromData) liest bis
// zum naechsten #0 und kann ueber die Buffer-Grenze hinaus lesen. Das Typ-Gate darf
// hier NICHT unterdruecken, weil LPWSTR kein Managed-String-Typ ist. Grundlage:
// Alcinoe ALWebSpider Unit1.pas:326 (pMimeTypeFromData: LPWSTR).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  pMimeTypeFromData: LPWSTR;'#13#10 +
  '  a: AnsiString;'#13#10 +
  'begin'#13#10 +
  '  a := AnsiString(pMimeTypeFromData);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringFromPointer) >= 1,
        'AnsiString(pMimeTypeFromData) mit LPWSTR-Pointer ist echter Heap-Overread - muss weiter melden');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestStringFromPointer);

end.
