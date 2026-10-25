unit uTestLoopBoundScanText;

// Tests fuer TLoopBoundScan.ScanText (SCA203, Scanner ohne AST): die
// Randfaelle des Tempo-Umbaus Charge Q5 (2026-10-25) - 'for'-Suche nur an
// 'f'/'F', Zwei-Zeichen-Symbole ohne Kopie, Kleinform ohne zweite
// Allokation. Die Detektor-Tests stehen in uTestLoopPastHighBound.

interface

uses
  DUnitX.TestFramework,
  uLoopBoundScan;

type
  [TestFixture]
  TTestLoopBoundScanText = class
  public
    // 'FOR'/'For' in jeder Schreibweise, Kopfwoerter gross - dieselben
    // Treffer wie klein; 'xfor', '.for', '&for' beginnen keine Schleife.
    [Test] procedure ScanText_AnyCase_SameHit;
    // ':=' im Kopf ist EIN Symbol; ein einzelnes ':' oder '<' am Textende
    // bricht nichts.
    [Test] procedure ScanText_TwoCharSymbols_AndTextEnd;
  end;

implementation

const
  LOWER_SRC = 'for i := 0 to List.Count do List[i] := 0;';

procedure TTestLoopBoundScanText.ScanText_AnyCase_SameHit;
var
  H : TLoopBoundHits;
begin
  H := TLoopBoundScan.ScanText(LOWER_SRC);
  Assert.AreEqual<Integer>(1, Length(H), 'klein: ein Treffer');
  Assert.AreEqual('List.Count', H[0].HighText, 'klein: HighText');

  H := TLoopBoundScan.ScanText('FOR I := 0 TO LIST.COUNT DO LIST[I] := 0;');
  Assert.AreEqual<Integer>(1, Length(H), 'gross: ein Treffer');
  Assert.AreEqual('LIST.COUNT', H[0].HighText, 'gross: HighText wie geschrieben');
  Assert.AreEqual('LIST', H[0].Collection, 'gross: Collection wie geschrieben');
  Assert.AreEqual('I', H[0].LoopVar, 'gross: LoopVar wie geschrieben');
  Assert.AreEqual('LIST[I]', H[0].Access, 'gross: Access wie geschrieben');

  H := TLoopBoundScan.ScanText('For i := 0 To Length(A) Do A[i] := 0;');
  Assert.AreEqual<Integer>(1, Length(H), 'gemischt: ein Treffer');
  Assert.AreEqual<Integer>(Ord(lbvLength), Ord(H[0].Variant), 'gemischt: Variante');
  Assert.AreEqual<Integer>(1, H[0].ForPos, 'gemischt: ForPos am F');

  // Gegenproben: kein Schleifenanfang.
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText(
    'xfor i := 0 to List.Count do List[i] := 0;')), 'xfor');
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText(
    'a.for i := 0 to List.Count do List[i] := 0;')), '.for');
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText(
    '&for i := 0 to List.Count do List[i] := 0;')), '&for');
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText(
    'forx i := 0 to List.Count do List[i] := 0;')), 'forx');
end;

procedure TTestLoopBoundScanText.ScanText_TwoCharSymbols_AndTextEnd;
var
  H : TLoopBoundHits;
begin
  // Ein Treffer an der zweiten Schleife: ForPos zaehlt ab dem Textanfang.
  H := TLoopBoundScan.ScanText('x := a <> b;'#10 + LOWER_SRC + #10'y :');
  Assert.AreEqual<Integer>(1, Length(H), 'Symbol am Textende: ein Treffer');
  Assert.AreEqual<Integer>(14, H[0].ForPos, 'ForPos der Schleife');
  Assert.AreEqual<Integer>(1, Length(TLoopBoundScan.ScanText(LOWER_SRC + ' <')),
    '< am Textende');
  // ': =' getrennt ist keine Zuweisung - kein Kopf.
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText(
    'for i : = 0 to List.Count do List[i] := 0;')), ': = ist kein :=');
  // 'for' als letztes Wort des Textes.
  Assert.AreEqual<Integer>(0, Length(TLoopBoundScan.ScanText('x := 1; for')),
    'for am Textende');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLoopBoundScanText);

end.
