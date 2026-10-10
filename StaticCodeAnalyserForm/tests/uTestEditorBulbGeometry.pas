unit uTestEditorBulbGeometry;

// Tests fuer uEditorBulbGeometry (Konzept_GluehbirneAnzeige_2026-10-08,
// Arbeitsplan Stufe 1): wo die Gluehbirne an der Caret-Zeile sitzt und wann sie
// gar nicht erscheint. Die Faelle stammen aus dem FPC-Pruefstand des
// Prototyps EditorLamp (14/14).
//
// UNGEDECKT bleibt die IDE-Seite (uIDEFindingBulb: Editorzustand,
// Hilfsfenster, Menue) - sie ist im Prototyp gemessen und wird mit dem
// Produktivcode nachgemessen, nicht getestet.

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

initialization
  TDUnitX.RegisterTestFixture(TTestEditorBulbGeometry);

end.
