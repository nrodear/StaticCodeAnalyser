unit uEditorBulbGeometry;

// Editor-Gluehbirne - reine Geometrie, ohne VCL und ohne ToolsAPI
// (Konzept_GluehbirneAnzeige_2026-10-08, Arbeitsplan Stufe 1).
//
// Aus der Lage der Caret-Zeile im Editor wird das Rechteck der Birne:
// quadratisch, senkrecht mittig in der Zeile, im Gutter rechtsbuendig vor
// dem Code (dort steht sie nie ueber Text oder Caret). Passt sie nicht
// ganz in den sichtbaren Bereich, wird sie nicht gezeigt - eine halb
// abgeschnittene Birne am Rand sieht nach Fehler aus.
//
// Uebernommen aus dem Prototyp EditorLamp (mess/editor-bulb f8917083), dort
// in der IDE gemessen: C2/C3/C7/C8 gruen (Nico 2026-10-08). Getestet in
// TestProject (uTestEditorBulbGeometry).
//
// OBERKANTE DER CARET-ZEILE (PickCaretLineTop, 2026-11-14): beim schnellen
// Mausrad blieb die Birne auf ihrer Bildschirmhoehe stehen, waehrend die
// Zeile wegscrollte. Vermutung, noch ungemessen: der Editor schiebt beim
// Scrollen den Inhalt per GDI-Blit und malt die Caret-Zeile nicht neu - ihr
// Zeilenzustand (LogicalLineState[..].WholeRect) nennt dann die Lage der
// LETZTEN Malung, also die alte Hoehe. GetCharacterPosPx rechnet die Lage
// eines Zeichens vermutlich aus dem aktuellen Bildausschnitt.
//
// Die Regel verschiebt den Zeilenzustand nur um GANZE Zeilen - um so viele,
// wie das Zeichenrechteck der Caret-Zeile daneben liegt, auf die naechste
// ganze Zeile gerundet. Die Pixellage innerhalb der Zeile bleibt die des
// Zeilenzustands.
//   * Erstzeilen-Pruefung: das Zeichenrechteck der OBERSTEN sichtbaren
//     Zeile (GetCharacterPosPx(LeftColumn, TopLine)) muss im obersten
//     Zeilenband beginnen, |Top| < Zeilenabstand. Zaehlte die Funktion die
//     Zeilen ab der obersten Bildschirmzeile (1, 2, ...) statt wie
//     EditorLineNum, oder lieferte sie Bildschirmkoordinaten, laege dieser
//     Wert weit daneben, und es gilt der Zeilenzustand. Ohne die Pruefung
//     gaelte im ersten Fall ein Versatz von (TopLine - 1) ganzen Zeilen -
//     die Birne verschwaende nach dem Scrollen.
//   * Rundung: ein fester Abstand zwischen Zeichen- und Zeilenrechteck
//     (Innenrand) unter einer halben Zeile kostet nichts; bei genau einer
//     halben Zeile wird von null weg gerundet.
//   * NICHT erkannt: ein Innenrand ab einer halben Zeile (die Birne sitzt
//     dann eine Zeile daneben); ein anderer Zeilenabstand in
//     GetCharacterPosPx als im Zeilenzustand (der Fehler waechst mit dem
//     Abstand zur obersten Zeile); Bildschirmkoordinaten bei einem Editor,
//     der weniger als eine Zeile unter dem oberen Bildschirmrand beginnt;
//     ein Zeichenrechteck, das genauso veraltet ist wie der Zeilenzustand
//     (dann 0 Zeilen - kein Gewinn, kein Schaden).
// Faellt eine Pruefung durch, gilt der Zeilenzustand wie bis 2026-11-13,
// ebenso bei einem Ergebnis ausserhalb von Integer (nur bei wilden Werten;
// unter $R+ waere es sonst ein Bereichsfehler).

interface

uses
  System.Types;

const
  // Kantenlaenge der Birne bei 96 DPI; skaliert wird mit ScaleBulbSize.
  BULB_SIZE_96 = 14;
  // Abstand zur Code-Kante (Pixel bei 96 DPI).
  BULB_GAP_96 = 2;
  // Kleiner als das ist keine Gluehbirne mehr zu erkennen - dann lieber gar
  // keine Birne.
  BULB_MIN_VISIBLE = 6;
  // Untergrenze der skalierten Kantenlaenge.
  BULB_MIN_SCALED = 8;

type
  TEditorBulbInput = record
    LineTop      : Integer;  // Oberkante der Caret-Zeile im Client; < 0 = nicht sichtbar
    LineHeight   : Integer;  // Zeilenhoehe in Pixeln
    GutterLeft   : Integer;  // X-Bereich des Gutters im Client
    GutterRight  : Integer;  // erste Spalte HINTER dem Gutter (= Code-Kante)
    ClientHeight : Integer;  // Hoehe des Editors
    BulbSize     : Integer;  // gewuenschte Kantenlaenge (schon skaliert)
    Gap          : Integer;  // Abstand zur Code-Kante (schon skaliert)
  end;

  // Woher die Oberkante der Caret-Zeile stammt (PickCaretLineTop).
  TCaretLineTopSource = (
    ltsLineState,   // Zeilenzustand (WholeRect.Top) - das Verhalten bis 2026-11-13
    ltsCharPos      // Zeilenzustand, um Rows ganze Zeilen nach GetCharacterPosPx verschoben
  );

  TCaretLineTop = record
    Top    : Integer;              // Oberkante der Caret-Zeile im Client
    Source : TCaretLineTopSource;  // ... und woher sie stammt
    Rows   : Integer;              // um so viele Zeilen verschoben (0 bei ltsLineState)
  end;

// Pixel bei 96 DPI -> Pixel bei APPI (kaufmaennisch gerundet); APPI <= 0
// gilt als 96.
function ScaleBulbValue(AValue96, APPI: Integer): Integer;

// Kantenlaenge fuer eine Bildschirmdichte; nie kleiner als BULB_MIN_SCALED.
function ScaleBulbSize(ABase96, APPI: Integer): Integer;

// True und das Rechteck, wenn die Birne ganz sichtbar Platz hat.
function BulbBounds(const AIn: TEditorBulbInput; out ARect: TRect): Boolean;

// Oberkante der Caret-Zeile (s. Kopf): ALineStateTop ist die Oberkante laut
// Zeilenzustand, ACharPosRect das Rechteck eines Zeichens der Caret-Zeile,
// AFirstLineRect das eines Zeichens der obersten sichtbaren Zeile (beide
// GetCharacterPosPx), APitch der Zeilenabstand. Es gilt der Zeilenzustand
// (Top = ALineStateTop, Rows = 0), wenn ACharPosRect oder AFirstLineRect
// leer ist (Bottom <= Top), APitch <= 0 oder |AFirstLineRect.Top| >= APitch.
// Sonst ist Rows = (ACharPosRect.Top - ALineStateTop) / APitch, auf die
// naechste ganze Zahl gerundet (genau halb: von null weg), Top =
// ALineStateTop + Rows * APitch und Source = ltsCharPos - ausser Top oder
// Rows passen nicht in Integer.
function PickCaretLineTop(ALineStateTop: Integer; const ACharPosRect,
  AFirstLineRect: TRect; APitch: Integer): TCaretLineTop;

implementation

const
  PPI_DEFAULT = 96;

function ScaleBulbValue(AValue96, APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := PPI_DEFAULT;
  Result := (AValue96 * APPI + PPI_DEFAULT div 2) div PPI_DEFAULT;
end;

function ScaleBulbSize(ABase96, APPI: Integer): Integer;
begin
  Result := ScaleBulbValue(ABase96, APPI);
  if Result < BULB_MIN_SCALED then Result := BULB_MIN_SCALED;
end;

function BulbBounds(const AIn: TEditorBulbInput; out ARect: TRect): Boolean;
var
  Size, X, Y : Integer;
begin
  ARect := Rect(0, 0, 0, 0);
  Result := False;
  if (AIn.LineTop < 0) or (AIn.LineHeight <= 0) or (AIn.ClientHeight <= 0) then
    Exit;
  if AIn.GutterRight <= AIn.GutterLeft then
    Exit;

  // Nie hoeher als die Zeile, nie breiter als der Gutter.
  Size := AIn.BulbSize;
  if Size > AIn.LineHeight then Size := AIn.LineHeight;
  if Size > AIn.GutterRight - AIn.GutterLeft then
    Size := AIn.GutterRight - AIn.GutterLeft;
  if Size < BULB_MIN_VISIBLE then
    Exit;

  // Rechtsbuendig vor der Code-Kante; reicht der Platz fuer den Abstand
  // nicht, buendig an den linken Gutter-Rand.
  X := AIn.GutterRight - AIn.Gap - Size;
  if X < AIn.GutterLeft then
    X := AIn.GutterLeft;

  Y := AIn.LineTop + (AIn.LineHeight - Size) div 2;
  if (Y < 0) or (Y + Size > AIn.ClientHeight) then
    Exit;

  ARect := Rect(X, Y, X + Size, Y + Size);
  Result := True;
end;

function PickCaretLineTop(ALineStateTop: Integer; const ACharPosRect,
  AFirstLineRect: TRect; APitch: Integer): TCaretLineTop;
// Gerechnet wird in Int64: auch wilde Rechtecke laufen nicht ueber ($Q+ in
// den Paketen), und was am Ende nicht in Integer passt, gilt nicht ($R+).
var
  D, Rows, Top : Int64;
begin
  Result.Top    := ALineStateTop;
  Result.Source := ltsLineState;
  Result.Rows   := 0;
  if ACharPosRect.Bottom <= ACharPosRect.Top then
    Exit;
  if APitch <= 0 then
    Exit;
  if AFirstLineRect.Bottom <= AFirstLineRect.Top then
    Exit;
  if Abs(Int64(AFirstLineRect.Top)) >= APitch then
    Exit;
  // Naechste ganze Zeilenzahl, genau halb von null weg. div schneidet gegen
  // null ab - deshalb wird ein negativer Abstand als Betrag gerundet.
  D := Int64(ACharPosRect.Top) - ALineStateTop;
  if D >= 0 then
    Rows := (D + APitch div 2) div APitch
  else
    Rows := -((APitch div 2 - D) div APitch);
  Top := ALineStateTop + Rows * APitch;
  if (Top < Low(Integer)) or (Top > High(Integer))
     or (Rows < Low(Integer)) or (Rows > High(Integer)) then
    Exit;
  Result.Top    := Top;
  Result.Source := ltsCharPos;
  Result.Rows   := Rows;
end;

end.
