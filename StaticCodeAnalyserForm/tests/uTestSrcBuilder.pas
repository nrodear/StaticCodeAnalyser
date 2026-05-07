unit uTestSrcBuilder;

// Helper zur Generierung von Pascal-Quelltext fuer Detektor-Tests.
//
// Vorher: ~280 inline `const SRC = 'unit t; ...'#13#10+...` Strings in
// uTestAnalyserChecks. Jeder Pascal-Apostroph musste verdoppelt werden,
// jeder Zeilenwechsel als `'#13#10+` separator. Refactoren eines Tests
// hiess: manuelle String-Surgery mit hohem Risiko fuer Quote-Fehler
// (siehe FormatMismatch-Quote-Fix-Story).
//
// Mit den Helpern hier:
//   - Src(['line1', 'line2']) = 'line1'#13#10'line2' - Zeilen ohne #13#10-Joining
//   - ProcInUnit('TFoo.Bar', 'L: TStringList', ['L := TStringList.Create;']) =
//     komplette Mini-Unit mit Methode + var-Sektion + Body
//
// Zur schrittweisen Adoption: bestehende Tests bleiben gueltig, neue
// Tests sollten die Helper nutzen. Wer einen alten Test aendert kann
// im selben Aufwasch konvertieren.

interface

type
  // Convenient Alias - vermeidet das `array of string`-Boilerplate
  // an jeder Aufrufstelle.
  TSrcLines = array of string;

// Joins lines with CRLF. Ersetzt das `'foo'#13#10+`-Pattern.
function Src(const Lines: TSrcLines): string;

// High-Level: erzeugt eine minimale Unit mit einer Methode.
//   unit t; implementation
//   procedure <Name>;
//   var <Vars>;        (nur wenn Vars <> '')
//   begin
//     <Body[i]>        (jede Zeile mit 2-Space-Einrueckung)
//   end;
function ProcInUnit(const Name, Vars: string;
                    const Body: TSrcLines): string; overload;

// Variante ohne var-Sektion.
function ProcInUnit(const Name: string;
                    const Body: TSrcLines): string; overload;

implementation

uses
  System.SysUtils;

function Src(const Lines: TSrcLines): string;
begin
  Result := string.Join(#13#10, Lines);
end;

function ProcInUnit(const Name, Vars: string;
                    const Body: TSrcLines): string;
var
  All : TSrcLines;
  Idx : Integer;
  i   : Integer;
begin
  // Layout: 'unit t;' + Sig + (var) + 'begin' + Body + 'end;'
  if Vars <> '' then
    SetLength(All, 4 + Length(Body) + 1)
  else
    SetLength(All, 3 + Length(Body) + 1);

  All[0] := 'unit t; implementation';
  All[1] := Format('procedure %s;', [Name]);
  Idx := 2;
  if Vars <> '' then
  begin
    All[Idx] := 'var ' + Vars + ';';
    Inc(Idx);
  end;
  All[Idx] := 'begin';
  Inc(Idx);
  for i := 0 to High(Body) do
  begin
    All[Idx] := '  ' + Body[i];
    Inc(Idx);
  end;
  All[Idx] := 'end;';
  Result := Src(All);
end;

function ProcInUnit(const Name: string;
                    const Body: TSrcLines): string;
begin
  Result := ProcInUnit(Name, '', Body);
end;

end.
