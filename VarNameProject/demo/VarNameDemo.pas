unit VarNameDemo;

// VarNameProject - Uebungsdatei: im Editor oeffnen, den Caret auf eine der
// markierten Zahlen setzen und Tools > VarNameProject > Variante waehlen
// (bzw. Strg+Alt+Umschalt+M). Die Datei muss nicht uebersetzt werden;
// nach dem Test mit Strg+Z zuruecksetzen oder die Datei verwerfen.

interface

function Scale(Value: Integer): Integer;
function Clamp(Value: Integer): Integer;
function Area(Width, Height: Double): Double;
function Mask(Value: Cardinal): Cardinal;

implementation

function Scale(Value: Integer): Integer;
begin
  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.
  Result := Value * 42 + 42;
end;

function Clamp(Value: Integer): Integer;
begin
  Result := Value;
  // Fall 2: Caret auf 1000 in der if-Zeile -> angeboten.
  if Result > 1000 then
    // Fall 3: Caret auf 999 -> ABGELEHNT (die Zeile darueber endet mit
    // then; die Deklaration wuerde zum Zweig).
    Result := 999;
end;

function Area(Width, Height: Double): Double;
begin
  // Fall 4: Bruchzahl.
  Result := Width * Height * 0.5;
end;

function Mask(Value: Cardinal): Cardinal;
begin
	// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.
	Result := Value and $FF00;
end;

end.
