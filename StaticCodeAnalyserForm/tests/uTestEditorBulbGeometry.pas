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
    // PickCaretLineTop - wenn nicht anders genannt: Zeilenzustand 100,
    // Zeilenabstand 18, Zeichenrechteck 18 hoch, oberste Zeile bei 0.
    // Gleiche Oberkante: Zeichenrechteck, 0 Zeilen verschoben.
    [Test] procedure SameTopPicksCharPos;
    // Um ganze Zeilen versetzt (+3, -2).
    [Test] procedure ThreeLinesDownPicksCharPos;
    [Test] procedure TwoLinesUpPicksCharPos;
    // Innenrand: ein paar Pixel daneben runden auf ganze Zeilen.
    [Test] procedure InnerMarginRoundsToWholeLines;
    // Mehr als eine halbe Zeile daneben: die naechste ganze Zeile.
    [Test] procedure PartLineRoundsToNearestLine;
    // Genau eine halbe Zeile: von null weg; knapp darunter: 0 Zeilen.
    [Test] procedure HalfLineRoundsAwayFromZero;
    // Leeres oder verkehrtes Zeichenrechteck: Zeilenzustand.
    [Test] procedure EmptyCharPosKeepsLineState;
    // Zeilenabstand 0 oder negativ: Zeilenzustand (und keine Division
    // durch 0).
    [Test] procedure NoPitchKeepsLineState;
    // Oberste Zeile weit unten (Bildschirmzeilen ab 1 gezaehlt):
    // Zeilenzustand.
    [Test] procedure FirstLineFarOffKeepsLineState;
    // Oberste Zeile im obersten Band (17, -17): Zeichenrechteck ...
    [Test] procedure FirstLineInsideTopBandPicksCharPos;
    // ... auf der Bandgrenze (18, -18): Zeilenzustand.
    [Test] procedure FirstLineOnBandEdgeKeepsLineState;
    // Leeres oder verkehrtes Rechteck der obersten Zeile: Zeilenzustand.
    [Test] procedure EmptyFirstLineKeepsLineState;
    // Ergebnis ausserhalb von Integer: Zeilenzustand statt Bereichsfehler.
    [Test] procedure HugeOffsetKeepsLineState;
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

// Rechteck eines Zeichens (Spalte 64..73); fuer PickCaretLineTop zaehlen
// nur Top und Bottom.
function CharRect(ATop, ABottom: Integer): TRect;
begin
  Result := Rect(64, ATop, 73, ABottom);
end;

// Zeichenzelle, 18 hoch ab ATop.
function Cell(ATop: Integer): TRect;
begin
  Result := CharRect(ATop, ATop + 18);
end;

// Der Regelfall: Zeilenzustand 100, Zeilenabstand 18, oberste Zeile bei 0,
// das Zeichen der Caret-Zeile ab ACharTop.
function PickAt(ACharTop: Integer): TCaretLineTop;
begin
  Result := PickCaretLineTop(100, Cell(ACharTop), Cell(0), 18);
end;

// Quelle, Oberkante und Zeilenzahl eines Ergebnisses; AWhat nennt den Fall.
procedure ExpectPick(const AGot: TCaretLineTop; ASource: TCaretLineTopSource;
  ATop, ARows: Integer; const AWhat: string);
begin
  Assert.AreEqual<Integer>(Ord(ASource), Ord(AGot.Source), 'Quelle, ' + AWhat);
  Assert.AreEqual<Integer>(ATop, AGot.Top, 'Oberkante, ' + AWhat);
  Assert.AreEqual<Integer>(ARows, AGot.Rows, 'Zeilen, ' + AWhat);
end;

procedure TTestEditorBulbGeometry.SameTopPicksCharPos;
begin
  // d = 100 - 100 = 0 -> 0 Zeilen, Oberkante 100, Quelle Zeichenrechteck.
  ExpectPick(PickAt(100), ltsCharPos, 100, 0, 'T=100');
end;

procedure TTestEditorBulbGeometry.ThreeLinesDownPicksCharPos;
begin
  // d = 154 - 100 = 54 = 3 * 18 -> 3 Zeilen, 100 + 54 = 154.
  ExpectPick(PickAt(154), ltsCharPos, 154, 3, 'T=154');
end;

procedure TTestEditorBulbGeometry.TwoLinesUpPicksCharPos;
begin
  // d = 64 - 100 = -36 = -2 * 18 -> -2 Zeilen, 100 - 36 = 64.
  ExpectPick(PickAt(64), ltsCharPos, 64, -2, 'T=64');
end;

procedure TTestEditorBulbGeometry.InnerMarginRoundsToWholeLines;
begin
  // d = 57 (3 Zeilen und 3 px): 57 / 18 = 3,17 -> 3 Zeilen, 154.
  ExpectPick(PickAt(157), ltsCharPos, 154, 3, 'T=157');
  // d = 51 (3 Zeilen weniger 3 px): 2,83 -> 3 Zeilen, 154.
  ExpectPick(PickAt(151), ltsCharPos, 154, 3, 'T=151');
  // d = 7: 0,39 -> 0 Zeilen, 100 - die Quelle ist trotzdem das
  // Zeichenrechteck (bis 2026-11-14 galt hier der Zeilenzustand).
  ExpectPick(PickAt(107), ltsCharPos, 100, 0, 'T=107');
end;

procedure TTestEditorBulbGeometry.PartLineRoundsToNearestLine;
begin
  // d = 75 - 100 = -25: -1,39 -> -1 Zeile, 100 - 18 = 82.
  ExpectPick(PickAt(75), ltsCharPos, 82, -1, 'T=75');
end;

procedure TTestEditorBulbGeometry.HalfLineRoundsAwayFromZero;
begin
  // d = 9, genau eine halbe Zeile -> von null weg: 1 Zeile, 118.
  ExpectPick(PickAt(109), ltsCharPos, 118, 1, 'T=109');
  // d = -9 -> -1 Zeile, 82.
  ExpectPick(PickAt(91), ltsCharPos, 82, -1, 'T=91');
  // Knapp darunter, d = 8 und -8: 0 Zeilen, 100.
  ExpectPick(PickAt(108), ltsCharPos, 100, 0, 'T=108');
  ExpectPick(PickAt(92), ltsCharPos, 100, 0, 'T=92');
end;

procedure TTestEditorBulbGeometry.EmptyCharPosKeepsLineState;
begin
  // Bottom = Top: leer, obwohl Top 154 genau 3 Zeilen daneben laege.
  ExpectPick(PickCaretLineTop(100, CharRect(154, 154), Cell(0), 18),
    ltsLineState, 100, 0, 'leer');
  // Bottom 136 < Top 154: verkehrt, ebenso leer.
  ExpectPick(PickCaretLineTop(100, CharRect(154, 136), Cell(0), 18),
    ltsLineState, 100, 0, 'verkehrt');
end;

procedure TTestEditorBulbGeometry.NoPitchKeepsLineState;
begin
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(0), 0),
    ltsLineState, 100, 0, 'Pitch 0');
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(0), -18),
    ltsLineState, 100, 0, 'Pitch -18');
end;

procedure TTestEditorBulbGeometry.FirstLineFarOffKeepsLineState;
begin
  // 8982 = 499 * 18: dort laege die oberste Zeile, zaehlte GetCharacterPosPx
  // Bildschirmzeilen ab 1 und stuende TopLine auf 500. Ohne die Pruefung
  // gaelte T=154 als 3 Zeilen.
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(8982), 18),
    ltsLineState, 100, 0, 'First.Top 8982');
end;

procedure TTestEditorBulbGeometry.FirstLineInsideTopBandPicksCharPos;
begin
  // |17| < 18: im obersten Band -> wie T=154 sonst, 3 Zeilen, 154.
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(17), 18),
    ltsCharPos, 154, 3, 'First.Top 17');
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(-17), 18),
    ltsCharPos, 154, 3, 'First.Top -17');
end;

procedure TTestEditorBulbGeometry.FirstLineOnBandEdgeKeepsLineState;
begin
  // |18| >= 18: nicht mehr im obersten Band -> Zeilenzustand.
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(18), 18),
    ltsLineState, 100, 0, 'First.Top 18');
  ExpectPick(PickCaretLineTop(100, Cell(154), Cell(-18), 18),
    ltsLineState, 100, 0, 'First.Top -18');
end;

procedure TTestEditorBulbGeometry.EmptyFirstLineKeepsLineState;
begin
  ExpectPick(PickCaretLineTop(100, Cell(154), CharRect(0, 0), 18),
    ltsLineState, 100, 0, 'First leer');
  ExpectPick(PickCaretLineTop(100, Cell(154), CharRect(0, -18), 18),
    ltsLineState, 100, 0, 'First verkehrt');
end;

procedure TTestEditorBulbGeometry.HugeOffsetKeepsLineState;
begin
  // d = (High(Integer) - 1) - 5 = 2147483641 -> 119304647 Zeilen (Rest 13,
  // aufgerundet); Top = 5 + 2147483646 = 2147483651 > High(Integer).
  ExpectPick(PickCaretLineTop(5, CharRect(High(Integer) - 1, High(Integer)),
    Cell(0), 18), ltsLineState, 5, 0, 'Top zu gross');
  // Zeilenabstand 1: Top = 2147483646 passt, Rows = d = 4294967293 nicht.
  ExpectPick(PickCaretLineTop(-High(Integer), CharRect(High(Integer) - 1,
    High(Integer)), CharRect(0, 1), 1), ltsLineState, -High(Integer), 0,
    'Rows zu gross');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorBulbGeometry);

end.
