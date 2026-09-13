unit uTestExceptOnException;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExceptOnException = class
  public
    [Test] procedure SpecificException_NoFinding;
    [Test] procedure OnException_Reported;
    [Test] procedure OnEDatabaseError_NotReported;
    [Test] procedure ExceptOnException_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 63): anonyme und qualifizierte Form
    [Test] procedure AnonymousOnException_Reported;
    [Test] procedure OnSpecificClass_Anonymous_NoFinding;
    // Testluecke 150: die State-Machine von FindOnException
    [Test] procedure OnExceptionInComment_NoFinding;
    [Test] procedure OnExceptionInStringLiteral_NoFinding;
    [Test] procedure QualifiedExceptionType_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExceptOnException.SpecificException_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: EFOpenError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnException_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: Exception do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnEDatabaseError_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; except'#13#10 +
  '    on E: EDatabaseError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptOnException));
  finally F.Free; end;
end;

procedure TTestExceptOnException.ExceptOnException_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; try except on E: Exception do Log(E.Message); end; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkExceptOnException then
      begin
        Assert.AreEqual<TFindingKind>(fkExceptOnException, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkExceptOnException finding');
  finally F.Free; end;
end;

procedure TTestExceptOnException.AnonymousOnException_Reported;
// Voll-Review 2026-09-12 (Major 63): 'on Exception do' faengt die
// Wurzelklasse ohne Binding-Variable - der Scanner verlangte zwingend
// 'Ident : Exception' und lieferte 0 (Bestands-Exe: 0, empirisch
// belegt, eo1.pas).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Tu;'#13#10 +
  '  except'#13#10 +
  '    on Exception do'#13#10 +
  '      Terminate;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptOnException),
    'die anonyme Form faengt die Wurzelklasse genauso');
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnSpecificClass_Anonymous_NoFinding;
// Gegenrichtung: 'on EConvertError do' ist eine SPEZIFISCHE Klasse -
// ein anonymer Zweig, der jedes on ohne ':' meldet, waere hier rot.
// Fixture layoutvariiert gegen den Anonymous-Zwilling (DuplicateBlock).
const SRC =
  'unit t;'#13#10'interface'#13#10'implementation'#13#10 +
  'procedure Q;'#13#10'begin'#13#10 +
  '  try'#13#10'    Rechne;'#13#10'  except'#13#10 +
  '    on EConvertError do'#13#10'      Melde;'#13#10 +
  '  end;'#13#10'end;'#13#10'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptOnException),
    'spezifische Klasse ohne Binding ist in Ordnung');
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnExceptionInComment_NoFinding;
// Testluecke 150 (Voll-Review 2026-09-12): FindOnException ist zu
// rund siebzig Zeilen eine Zustandsmaschine fuer Strings und
// Kommentare - und kein Test beruehrte sie. Kommentare zaehlen im
// ganzen Werkzeug nie als Code (Projektregel); hier steht es jetzt
// auch als Waechter.
//
// Die Fixture enthaelt einen ECHTEN, spezifischen Handler, damit der
// except-Block ueberhaupt geparst wird - die zu ignorierende
// Zeichenfolge steht im Kommentar darueber.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '// hier steht on E: Exception do nur als Text'#13#10 +
  'procedure NurKommentar;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoIt;'#13#10 +
  '  except'#13#10 +
  '    on E: EFoo do'#13#10 +
  '      Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkExceptOnException),
    'im Kommentar ist kein Handler');
  finally F.Free; end;
end;

procedure TTestExceptOnException.OnExceptionInStringLiteral_NoFinding;
// Die zweite Haelfte derselben Zustandsmaschine. Getrennt vom
// Kommentar-Test, weil es zwei verschiedene Zustaende sind: wer nur
// einen von beiden bricht, soll genau einen roten Test sehen.
// Am gebauten Stand nachgemessen: 0 Funde.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure NurString;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoIt;'#13#10 +
  '  except'#13#10 +
  '    on E: EFoo do'#13#10 +
  '      Log(''on E: Exception do ist hier nur Text'');'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkExceptOnException),
    'im String-Literal ist kein Handler');
  finally F.Free; end;
end;

procedure TTestExceptOnException.QualifiedExceptionType_Reported;
// Der qualifizierte Typname war weder dokumentiert noch getestet -
// 'on E: SysUtils.Exception do' faengt dieselbe Wurzelklasse und
// wird gemeldet. Der Test haelt das fest, damit eine kuenftige
// Verschaerfung der Namenspruefung ihn nicht stillschweigend
// verliert. Am gebauten Stand nachgemessen: 1 Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Qualifiziert;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoIt;'#13#10 +
  '  except'#13#10 +
  '    on E: SysUtils.Exception do'#13#10 +
  '      Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkExceptOnException),
    'der Unit-Qualifizierer aendert die gefangene Klasse nicht');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptOnException);

end.
