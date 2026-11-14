unit uTestEditorBulbGeometry;

// Tests fuer uEditorBulbGeometry (Konzept_GluehbirneAnzeige_2026-10-08,
// Arbeitsplan Stufe 1): wo die Gluehbirne an der Caret-Zeile sitzt und wann sie
// gar nicht erscheint. Die Faelle stammen aus dem FPC-Pruefstand des
// Prototyps EditorLamp (14/14).
//
// UNGEDECKT bleibt die IDE-Seite (uIDEFindingBulb: Editorzustand,
// Hilfsfenster, Menue) - sie ist im Prototyp gemessen und wird mit dem
// Produktivcode nachgemessen, nicht getestet. Das gilt auch fuer
// PickCaretLineTop (2026-11-14): die Tests pruefen nur die Regel; ob
// GetCharacterPosPx in der IDE die frischere Lage liefert, zeigt die
// Diagnose-Spur in uIDEFindingBulb.

interface

uses
  DUnitX.TestFramework, uEditorBulbGeometry;

type
  [TestFixture]
  TTestEditorBulbGeometry = class
  private
    // Zeile 100..118, Gutter 0..60, Editor 500 hoch, Birne 14, Abstand 2;
    // jeder Test aendert nur, worum es ihm geht.
    function Base: TEditorBulbInput;
  public
    // Normalfall: rechtsbuendig vor der Code-Kante, senkrecht mittig.
    [Test] procedure NormalLineIsRightAlignedAndCentered;
    // Zeile niedriger als die Birne: die Birne schrumpft auf Zeilenhoehe.
    [Test] procedure LowLineShrinksBulbToLineHeight;
    // Caret-Zeile nicht sichtbar: keine Birne.
    [Test] procedure InvisibleLineHasNoBulb;
    // Unten abgeschnitten: keine halbe Birne.
    [Test] procedure ClippedAtBottomHasNoBulb;
    // Schmaler Gutter: Birne passt sich an, buendig links.
    [Test] procedure NarrowGutterShrinksAndAlignsLeft;
    // Kein Gutter: keine Birne.
    [Test] procedure NoGutterHasNoBulb;
    // Unter der Erkennbarkeitsgrenze: keine Birne.
    [Test] procedure TooSmallHasNoBulb;
    // DPI-Skalierung, Untergrenze und PPI 0.
    [Test] procedure ScalesWithPpiAndHasMinimum;
    // PickCaretLineTop - Zeilenzustand sagt Oberkante 100, Zeilenabstand
    // 18. Gleiche Oberkante: das Zeichenrechteck gilt.
    [Test] procedure SameTopPicksCharPos;
    // Um ganze Zeilen versetzt (+3, -2): das Zeichenrechteck gilt.
    [Test] procedure ThreeLinesDownPicksCharPos;
    [Test] procedure TwoLinesUpPicksCharPos;
    // Um einen Bruchteil einer Zeile versetzt: der Zeilenzustand gilt.
    [Test] procedure PartLineOffsetKeepsLineState;
    // Leeres oder verkehrtes Zeichenrechteck: der Zeilenzustand gilt, auch
    // wenn der Versatz ganzzahlig waere.
    [Test] procedure EmptyCharPosKeepsLineState;
    // Zeilenabstand 0 oder negativ: der Zeilenzustand gilt (und keine
    // Division durch 0).
    [Test] procedure NoPitchKeepsLineState;
  end;

implementation

uses
  System.Types;

function TTestEditorBulbGeometry.Base: TEditorBulbInput;
begin
  Result.LineTop      := 100;
  Result.LineHeight   := 18;
  Result.GutterLeft   := 0;
  Result.GutterRight  := 60;
  Result.ClientHeight := 500;
  Result.BulbSize     := 14;
  Result.Gap          := 2;
end;

procedure TTestEditorBulbGeometry.NormalLineIsRightAlignedAndCentered;
var
  R : TRect;
begin
  Assert.IsTrue(BulbBounds(Base, R));
  Assert.AreEqual(44, R.Left, 'Left = 60 - 2 - 14');
  Assert.AreEqual(58, R.Right);
  Assert.AreEqual(102, R.Top, 'Top = 100 + (18 - 14) div 2');
  Assert.AreEqual(116, R.Bottom);
end;

procedure TTestEditorBulbGeometry.LowLineShrinksBulbToLineHeight;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.LineTop    := 10;
  I.LineHeight := 12;
  Assert.IsTrue(BulbBounds(I, R));
  Assert.AreEqual(12, R.Bottom - R.Top);
  Assert.AreEqual(10, R.Top);
end;

procedure TTestEditorBulbGeometry.InvisibleLineHasNoBulb;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.LineTop := -1;
  Assert.IsFalse(BulbBounds(I, R));
end;

procedure TTestEditorBulbGeometry.ClippedAtBottomHasNoBulb;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.LineTop := 490;
  Assert.IsFalse(BulbBounds(I, R));
end;

procedure TTestEditorBulbGeometry.NarrowGutterShrinksAndAlignsLeft;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.LineTop     := 0;
  I.GutterRight := 10;
  Assert.IsTrue(BulbBounds(I, R));
  Assert.AreEqual(0, R.Left);
  Assert.AreEqual(10, R.Right);
end;

procedure TTestEditorBulbGeometry.NoGutterHasNoBulb;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.GutterLeft  := 20;
  I.GutterRight := 20;
  Assert.IsFalse(BulbBounds(I, R));
end;

procedure TTestEditorBulbGeometry.TooSmallHasNoBulb;
var
  I : TEditorBulbInput;
  R : TRect;
begin
  I := Base;
  I.LineHeight := BULB_MIN_VISIBLE - 2;
  Assert.IsFalse(BulbBounds(I, R));
end;

procedure TTestEditorBulbGeometry.ScalesWithPpiAndHasMinimum;
begin
  Assert.AreEqual(14, ScaleBulbSize(14, 96));
  Assert.AreEqual(21, ScaleBulbSize(14, 144));
  Assert.AreEqual(28, ScaleBulbSize(14, 192));
  Assert.AreEqual(BULB_MIN_SCALED, ScaleBulbSize(4, 96));
  Assert.AreEqual(14, ScaleBulbSize(14, 0), 'PPI 0 gilt als 96');
  Assert.AreEqual(3, ScaleBulbValue(2, 144));
end;

// Zeichenrechteck eines Zeichens (Spalte 64..73); fuer PickCaretLineTop
// zaehlen nur Top und Bottom.
function CharRect(ATop, ABottom: Integer): TRect;
begin
  Result := Rect(64, ATop, 73, ABottom);
end;

procedure TTestEditorBulbGeometry.SameTopPicksCharPos;
var
  P : TCaretLineTop;
begin
  // Versatz 100 - 100 = 0, 0 mod 18 = 0 -> Zeichenrechteck, Oberkante 100.
  P := PickCaretLineTop(100, CharRect(100, 118), 18);
  Assert.AreEqual<Integer>(Ord(ltsCharPos), Ord(P.Source), 'Quelle');
  Assert.AreEqual<Integer>(100, P.Top);
end;

procedure TTestEditorBulbGeometry.ThreeLinesDownPicksCharPos;
var
  P : TCaretLineTop;
begin
  // 154 = 100 + 3 * 18: Versatz 54, 54 mod 18 = 0 -> Zeichenrechteck.
  P := PickCaretLineTop(100, CharRect(154, 172), 18);
  Assert.AreEqual<Integer>(Ord(ltsCharPos), Ord(P.Source), 'Quelle');
  Assert.AreEqual<Integer>(154, P.Top, '100 + 3 * 18');
end;

procedure TTestEditorBulbGeometry.TwoLinesUpPicksCharPos;
var
  P : TCaretLineTop;
begin
  // 64 = 100 - 2 * 18: Versatz -36, -36 mod 18 = 0 -> Zeichenrechteck.
  P := PickCaretLineTop(100, CharRect(64, 82), 18);
  Assert.AreEqual<Integer>(Ord(ltsCharPos), Ord(P.Source), 'Quelle');
  Assert.AreEqual<Integer>(64, P.Top, '100 - 2 * 18');
end;

procedure TTestEditorBulbGeometry.PartLineOffsetKeepsLineState;
var
  P : TCaretLineTop;
begin
  // Versatz +7: 7 mod 18 = 7 -> Zeilenzustand, Oberkante 100.
  P := PickCaretLineTop(100, CharRect(107, 125), 18);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle bei +7');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante bei +7');
  // Versatz -25 (eine Zeile und 7 Pixel nach oben): -25 mod 18 = -7.
  P := PickCaretLineTop(100, CharRect(75, 93), 18);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle bei -25');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante bei -25');
end;

procedure TTestEditorBulbGeometry.EmptyCharPosKeepsLineState;
var
  P : TCaretLineTop;
begin
  // Top 154 waere um 3 ganze Zeilen versetzt - aber Bottom = Top: leer.
  P := PickCaretLineTop(100, CharRect(154, 154), 18);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle, leer');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante, leer');
  // Bottom 136 < Top 154: verkehrt, ebenso leer.
  P := PickCaretLineTop(100, CharRect(154, 136), 18);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle, verkehrt');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante, verkehrt');
end;

procedure TTestEditorBulbGeometry.NoPitchKeepsLineState;
var
  P : TCaretLineTop;
begin
  // Zeilenabstand 0: kein Versatztest (mod 0) -> Zeilenzustand.
  P := PickCaretLineTop(100, CharRect(154, 172), 0);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle bei 0');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante bei 0');
  // Zeilenabstand -18: 54 mod -18 = 0 bestuende den Versatztest, aber
  // nur ein positiver Abstand zaehlt -> Zeilenzustand.
  P := PickCaretLineTop(100, CharRect(154, 172), -18);
  Assert.AreEqual<Integer>(Ord(ltsLineState), Ord(P.Source), 'Quelle bei -18');
  Assert.AreEqual<Integer>(100, P.Top, 'Oberkante bei -18');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorBulbGeometry);

end.
