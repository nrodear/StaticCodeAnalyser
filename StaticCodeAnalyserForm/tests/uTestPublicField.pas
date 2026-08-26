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
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TFoo = class'#13#10+
  '  public'#13#10+
  '    function Reg(const aName: string;'#13#10+
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

initialization
  TDUnitX.RegisterTestFixture(TTestPublicField);

end.
