unit uTestConfidencePipeline;

// Audit 2026-07 Stufe 3 (CRITICAL): Der alte Test-Harness (FindingsOf/
// FindingsOfFile) ruft Detektoren DIREKT und umgeht die Produktions-
// Post-Filter. Folge: alle per KindDefaultConfidence=fcLow demoteten Kinds
// hatten gruene Positiv-Tests, lieferten im ausgelieferten Default
// (FindingMinConfidence=fcMedium) aber NULL Funde - "Test gruen, Produktion
// leer" blieb systematisch unbemerkt.
//
// Diese Fixture prueft JEDES fcLow-Kind ueber den vollen Pipeline-Weg
// (TFindingHelper.FindingsViaPipeline -> uEngineApi -> alle Post-Filter):
//   (a) mit MinConfidence=fcLow ist der Befund SICHTBAR
//       -> der Detektor selbst lebt (faengt versehentliches Ausbauen),
//   (b) mit dem Auslieferungs-Default fcMedium ist er GEFILTERT
//       -> die bewusste Demotion ist dokumentiert und regressionssicher
//       (eine spaetere Confidence-Promotion muss DIESEN Test anfassen).
//
// Die 19 Quell-Snippets sind empirisch gegen die gebaute Engine validiert
// (Scan mit MinConfidence=low, 2026-07-04): jedes Snippet feuert genau
// sein Ziel-Kind. Aenderungen an Detektor-Heuristiken koennen Snippets
// entwerten - Test (a) meldet das dann als Fehlschlag mit Kind-Namen.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

type
  TKindSnippet = record
    Kind : TFindingKind;
    Src  : string;
  end;

  [TestFixture]
  TTestConfidencePipeline = class
  private
    function GetSnips: TArray<TKindSnippet>;
  public
    // (a) Detektor lebt: Befund sichtbar sobald der Confidence-Filter aus ist.
    [Test]
    procedure FcLowKinds_VisibleAtLowThreshold;
    // (b) Demotion wirkt: im Auslieferungs-Default (fcMedium) gefiltert.
    [Test]
    procedure FcLowKinds_FilteredAtDefaultThreshold;
    // Gegenprobe: ein fcHigh-Kind ueberlebt den Default-Filter im selben
    // Pipeline-Weg (beweist, dass (b) nicht an einer leeren Pipeline liegt).
    [Test]
    procedure HighConfidenceKind_SurvivesDefaultThreshold;
  end;

implementation

const
  LB = sLineBreak;

function TTestConfidencePipeline.GetSnips: TArray<TKindSnippet>;

  function S(AKind: TFindingKind; const ASrc: string): TKindSnippet;
  begin
    Result.Kind := AKind;
    Result.Src  := ASrc;
  end;

begin
  Result := [
    // SCA148: Instanz-Methode ohne Self-Zugriff.
    S(fkCanBeClassMethod,
      'unit Snip1;' + LB + 'interface' + LB +
      'type TCalc = class public function AddNums(A, B: Integer): Integer; end;' + LB +
      'implementation' + LB +
      'function TCalc.AddNums(A, B: Integer): Integer;' + LB +
      'begin Result := A + B; end;' + LB + 'end.'),
    // SCA170: string-Parameter ohne const.
    S(fkConstStringParameter,
      'unit Snip2;' + LB + 'interface' + LB +
      'type TPrinter = class public procedure Show(Msg: string); end;' + LB +
      'implementation' + LB +
      'procedure TPrinter.Show(Msg: string);' + LB +
      'begin if Msg <> '''' then Writeln(Msg); end;' + LB + 'end.'),
    // Public-Member nur unit-intern genutzt.
    S(fkCanBeUnitPrivate,
      'unit Snip3;' + LB + 'interface' + LB +
      'type THelper = class public procedure OnlyUsedHere; end;' + LB +
      'procedure Drive;' + LB +
      'implementation' + LB +
      'procedure THelper.OnlyUsedHere; begin Writeln(''x''); end;' + LB +
      'procedure Drive;' + LB +
      'var H: THelper;' + LB +
      'begin H := THelper.Create; try H.OnlyUsedHere; finally H.Free; end; end;' + LB +
      'end.'),
    // Public-Member nur von eigener + Sub-Klasse genutzt.
    S(fkCanBeProtected,
      'unit Snip4;' + LB + 'interface' + LB +
      'type' + LB +
      '  TBase = class public procedure Hook; end;' + LB +
      '  TChild = class(TBase) public procedure Run; end;' + LB +
      'implementation' + LB +
      'procedure TBase.Hook; begin Writeln(''h''); end;' + LB +
      'procedure TChild.Run; begin Hook; end;' + LB + 'end.'),
    // Public-Member nur von Methoden der EIGENEN Klasse genutzt.
    S(fkCanBeStrictPrivate,
      'unit Snip5;' + LB + 'interface' + LB +
      'type TBox = class public procedure Bump; procedure Api; end;' + LB +
      'implementation' + LB +
      'procedure TBox.Bump; begin Writeln(''b''); end;' + LB +
      'procedure TBox.Api; begin Bump; end;' + LB + 'end.'),
    // Public-Member in der Unit nirgends gerufen.
    S(fkUnusedPublicMember,
      'unit Snip6;' + LB + 'interface' + LB +
      'type TThing = class public procedure NeverCalledAnywhere; end;' + LB +
      'implementation' + LB +
      'procedure TThing.NeverCalledAnywhere; begin Writeln(''n''); end;' + LB +
      'end.'),
    // SCA134: Zugriff nach Free.
    S(fkUseAfterFree,
      'unit Snip7;' + LB + 'interface' + LB + 'procedure Go;' + LB +
      'implementation' + LB + 'uses System.Classes;' + LB +
      'procedure Go;' + LB + 'var L: TStringList;' + LB +
      'begin L := TStringList.Create; L.Add(''a''); L.Free; L.Add(''b''); end;' + LB +
      'end.'),
    // SCA135: konkrete Subklasse erbt abstrakte Methode ohne Override.
    S(fkAbstractNotImpl,
      'unit Snip8;' + LB + 'interface' + LB +
      'type' + LB +
      '  TShape = class public procedure Draw; virtual; abstract; end;' + LB +
      '  TCircle = class(TShape) public procedure Extra; end;' + LB +
      'procedure Use;' + LB +
      'implementation' + LB +
      'procedure TCircle.Extra; begin Writeln(''e''); end;' + LB +
      'procedure Use;' + LB + 'var C: TCircle;' + LB +
      'begin C := TCircle.Create; try C.Extra; finally C.Free; end; end;' + LB +
      'end.'),
    // SCA078: except on E: Exception (Catch-All auf Root-Klasse).
    S(fkExceptOnException,
      'unit Snip9;' + LB + 'interface' + LB + 'procedure Risky;' + LB +
      'implementation' + LB + 'uses System.SysUtils;' + LB +
      'procedure Risky;' + LB +
      'begin try Writeln(''w''); except on E: Exception do Writeln(E.Message); end; end;' + LB +
      'end.'),
    // SCA049: Length(s) - N (N>1) ohne Guard.
    S(fkLengthUnderflow,
      'unit Snip10;' + LB + 'interface' + LB +
      'function NextToLast(const S: string): Char;' + LB +
      'implementation' + LB +
      'function NextToLast(const S: string): Char;' + LB +
      'begin Result := S[Length(S) - 2]; end;' + LB + 'end.'),
    // SCA158: PChar(s) + Offset.
    S(fkPointerArithmeticOnString,
      'unit Snip11;' + LB + 'interface' + LB +
      'function SecondChar(const S: string): PChar;' + LB +
      'implementation' + LB +
      'function SecondChar(const S: string): PChar;' + LB +
      'begin Result := PChar(S) + 1; end;' + LB + 'end.'),
    // Welle-4-Formatierer: Zeile > Limit.
    S(fkTooLongLine,
      'unit Snip12;' + LB + 'interface' + LB + 'implementation' + LB +
      'procedure LongLine;' + LB +
      'begin Writeln(''' + StringOfChar('a', 130) + '''); end;' + LB + 'end.'),
    // Trailing-Whitespace am Zeilenende.
    S(fkTrailingWhitespace,
      'unit Snip13;' + LB + 'interface' + LB + 'implementation' + LB +
      'procedure T;' + LB + 'begin' + LB +
      '  Writeln(1);   ' + LB + 'end;' + LB + 'end.'),
    // Echtes Tab-Zeichen im Source.
    S(fkTabulationCharacter,
      'unit Snip14;' + LB + 'interface' + LB + 'implementation' + LB +
      'procedure T;' + LB + 'begin' + LB +
      #9'Writeln(2);' + LB + 'end;' + LB + 'end.'),
    // Keyword nicht lowercase.
    S(fkLowercaseKeyword,
      'unit Snip15;' + LB + 'interface' + LB + 'implementation' + LB +
      'procedure K;' + LB + 'BEGIN' + LB + '  Writeln(3);' + LB +
      'END;' + LB + 'end.'),
    // Integer-Literal ohne Zifferngruppierung.
    S(fkDigitGrouping,
      'unit Snip16;' + LB + 'interface' + LB +
      'const BIG_NUMBER = 10000000;' + LB +
      'implementation' + LB + 'end.'),
    // Gruppierte Deklaration `A, B: Integer`.
    S(fkGroupedDeclaration,
      'unit Snip17;' + LB + 'interface' + LB + 'implementation' + LB +
      'procedure G;' + LB + 'var A, B: Integer;' + LB +
      'begin A := 1; B := 2; Writeln(A + B); end;' + LB + 'end.'),
    // Zwei aufeinanderfolgende var-Sections.
    S(fkConsecutiveSection,
      'unit Snip18;' + LB + 'interface' + LB + 'implementation' + LB +
      'var GOne: Integer;' + LB + 'var GTwo: Integer;' + LB + 'end.'),
    // uses nicht alphabetisch.
    S(fkUnsortedUses,
      'unit Snip19;' + LB + 'interface' + LB +
      'uses System.SysUtils, System.Classes;' + LB +
      'implementation' + LB +
      'procedure U;' + LB + 'var L: TStringList;' + LB +
      'begin L := TStringList.Create; try Writeln(Trim('' x '')); finally L.Free; end; end;' + LB +
      'end.')
  ];
end;

procedure TTestConfidencePipeline.FcLowKinds_VisibleAtLowThreshold;
var
  Snip   : TKindSnippet;
  F      : TObjectList<TLeakFinding>;
  Misses : string;
begin
  Misses := '';
  for Snip in GetSnips do
  begin
    F := TFindingHelper.FindingsViaPipeline(Snip.Src, fcLow);
    try
      if TFindingHelper.Count(F, Snip.Kind) = 0 then
        Misses := Misses + KindName(Snip.Kind) + ' ';
    finally
      F.Free;
    end;
  end;
  Assert.AreEqual('', Misses,
    'fcLow-Kinds OHNE Befund trotz MinConfidence=low (Detektor tot oder ' +
    'Snippet entwertet): ' + Misses);
end;

procedure TTestConfidencePipeline.FcLowKinds_FilteredAtDefaultThreshold;
var
  Snip  : TKindSnippet;
  F     : TObjectList<TLeakFinding>;
  Leaks : string;
begin
  Leaks := '';
  for Snip in GetSnips do
  begin
    F := TFindingHelper.FindingsViaPipeline(Snip.Src, fcMedium);
    try
      if TFindingHelper.Count(F, Snip.Kind) > 0 then
        Leaks := Leaks + KindName(Snip.Kind) + ' ';
    finally
      F.Free;
    end;
  end;
  Assert.AreEqual('', Leaks,
    'fcLow-Kinds SICHTBAR im Auslieferungs-Default fcMedium (Demotion ' +
    'aufgehoben? Dann diesen Test bewusst anpassen): ' + Leaks);
end;

procedure TTestConfidencePipeline.HighConfidenceKind_SurvivesDefaultThreshold;
var
  F : TObjectList<TLeakFinding>;
const
  // SCA132 ExceptionTooGeneral ist fcHigh und feuert auf demselben Snippet
  // wie SCA078 (das im Default gefiltert wird) - ideale Gegenprobe.
  SRC = 'unit SnipHigh;' + sLineBreak +
        'interface' + sLineBreak + 'procedure Risky;' + sLineBreak +
        'implementation' + sLineBreak + 'uses System.SysUtils;' + sLineBreak +
        'procedure Risky;' + sLineBreak +
        'begin try Writeln(''w''); except on E: Exception do Writeln(E.Message); end; end;' + sLineBreak +
        'end.';
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcMedium);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkExceptionTooGeneral) > 0,
      'fcHigh-Kind (ExceptionTooGeneral) muss den Default-Filter ueberleben');
    Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptOnException),
      'fcLow-Kind (ExceptOnException) muss im selben Lauf gefiltert sein');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConfidencePipeline);

end.
