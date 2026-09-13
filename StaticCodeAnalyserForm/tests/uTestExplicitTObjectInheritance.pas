unit uTestExplicitTObjectInheritance;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExplicitTObjectInheritance = class
  public
    [Test] procedure ImplicitInheritance_NoFinding;
    [Test] procedure OtherAncestor_NoFinding;
    [Test] procedure ExplicitTObject_Reported;
    [Test] procedure ExplicitTObjectWithWhitespace_Reported;
    [Test] procedure ExplicitTObjectInheritance_KindAndSeverity;
    // Testluecke 151: Interface-Liste, Wortgrenze, Kommentar/String
    [Test] procedure TObjectWithInterfaceList_NoFinding;
    [Test] procedure TObjectListDescendant_NoFinding;
    [Test] procedure TObjectInCommentAndString_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExplicitTObjectInheritance.ImplicitInheritance_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.OtherAncestor_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class(TComponent)'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObject_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class(TObject)'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObjectWithWhitespace_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class ( TObject )'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExplicitTObjectInheritance));
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.ExplicitTObjectInheritance_KindAndSeverity;
const SRC =
  'unit t; interface type TFoo = class(TObject) end; implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkExplicitTObjectInheritance then
      begin
        Assert.AreEqual<TFindingKind>(fkExplicitTObjectInheritance, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkExplicitTObjectInheritance finding');
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.TObjectWithInterfaceList_NoFinding;
// Testluecke 151 (Voll-Review 2026-09-12). Der wichtigste der drei:
// bei 'class(TObject, IThing)' ist das explizite TObject NOETIG -
// ohne Vorfahre laesst sich keine Interface-Liste schreiben. Wer die
// Regel auf ein blosses Vorkommen von TObject verkuerzt, produziert
// hier einen Rat, der nicht uebersetzt.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IThing = interface'#13#10 +
  '    procedure Tu;'#13#10 +
  '  end;'#13#10 +
  '  TMitIntf = class(TObject, IThing)'#13#10 +
  '    procedure Tu;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TMitIntf.Tu; begin DoIt; end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkExplicitTObjectInheritance),
    'mit Interface-Liste ist der Vorfahre nicht weglassbar');
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.TObjectListDescendant_NoFinding;
// Wortgrenze: 'TObjectList' faengt mit 'TObject' an, ist aber eine
// andere Klasse. Der Test deckt zugleich das TObject als
// GENERIC-ARGUMENT ab, das ebenfalls kein Vorfahre ist.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type'#13#10 +
  '  TAbleitung = class(TObjectList<TObject>)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkExplicitTObjectInheritance),
    'TObjectList ist nicht TObject');
  finally F.Free; end;
end;

procedure TTestExplicitTObjectInheritance.TObjectInCommentAndString_NoFinding;
// Kommentar- und String-Awareness in einer Fixture: 'class(TObject)'
// steht einmal als Kommentartext und einmal in einem Literal. Beide
// Zustaende gehoeren zu derselben Zeilen-Vorverarbeitung, deshalb
// hier zusammen - anders als bei uExceptOnException, wo zwei
// getrennte Zustaende der Zustandsmaschine gemeint sind.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  // class(TObject) steht hier nur als Text'#13#10 +
  '  TAusKommentar = class(TInterfacedObject)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure Zeig;'#13#10 +
  'begin'#13#10 +
  '  Log(''class(TObject) steht hier nur in einem String'');'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkExplicitTObjectInheritance),
    'weder Kommentar noch Literal sind eine Deklaration');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExplicitTObjectInheritance);

end.
