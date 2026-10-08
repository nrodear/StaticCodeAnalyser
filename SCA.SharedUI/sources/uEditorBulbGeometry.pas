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

// Pixel bei 96 DPI -> Pixel bei APPI (kaufmaennisch gerundet); APPI <= 0
// gilt als 96.
function ScaleBulbValue(AValue96, APPI: Integer): Integer;

// Kantenlaenge fuer eine Bildschirmdichte; nie kleiner als BULB_MIN_SCALED.
function ScaleBulbSize(ABase96, APPI: Integer): Integer;

// True und das Rechteck, wenn die Birne ganz sichtbar Platz hat.
function BulbBounds(const AIn: TEditorBulbInput; out ARect: TRect): Boolean;

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

end.
