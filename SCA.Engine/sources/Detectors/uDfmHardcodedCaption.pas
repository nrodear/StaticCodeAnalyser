unit uDfmHardcodedCaption;

// Detektor: Hardcodierte UI-Strings im DFM.
//
// Findet String-Literale in UI-Text-Properties (Caption, Hint, Text)
// von Komponenten im DFM. Solche Strings umgehen den Lokalisierungs-Layer
// (dxgettext / gnugettext / uLocalization) und sind in mehrsprachigen
// Projekten ein typischer Lokalisierungs-Smell.
//
// Heuristik bewusst pragmatisch:
//   * Nur Properties aus einer kurzen Whitelist (Caption, Hint, Text).
//   * Nur pvkString-Werte (nicht z.B. Ident, der koennte eine Variable
//     oder Konstante sein).
//   * Leerer / nur-Whitespace-Wert ist kein Befund (Designer setzt
//     Caption = '' um Default-Text auszuschalten).
//
// Aktivierung ist heute global: der Detektor laeuft fuer jede DFM-Datei
// im Analyse-Lauf. Wenn ein Projekt komplett ohne Lokalisierung arbeitet,
// koennen die Befunde via Suppression-Kommentar oder ignore.txt
// ausgeschlossen werden. Spaeter (Phase 2): Aktivierung an die Existenz
// von 'uLocalization'/'gnugettext' in den Form-uses koppeln, um stillen
// Lauf in Projekten ohne i18n zu sparen.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell (siehe KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmHardcodedCaptionDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeClassMethod, ConsecutiveSection, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Default-Whitelist der UI-Text-Properties. Konfigurierbar machen in
  // Phase 2 via analyser.ini ([Components] CaptionProperties=...). Aktuell
  // bewusst kurz, damit der Detektor wenige False Positives erzeugt;
  // 'Text' ist bei TEdit auch User-Input, dort aber Designer-typisch leer.
  CAPTION_PROPS: array[0..2] of string = ('Caption', 'Hint', 'Text');

function IsNonTranslatable(const S: string): Boolean;
// True wenn die Caption KEINEN Buchstaben enthaelt und rein ASCII ist - also
// reine Symbole/Ziffern/Interpunktion ('-', '...', '>>', '|', '123', '/').
// Solche Captions umgehen keinen Lokalisierungs-Layer (es gibt nichts zu
// uebersetzen) -> kein i18n-Smell (dominante DfmHardcodedCaption-FP-Klasse,
// Real-World 2026-06-28). Unicode-Zeichen (Ord > 127, z.B. CJK/kyrillisch/
// akzentuiert) werden NICHT geskippt - das ist uebersetzbarer Text.
var
  C : Char;
  HasLetter, AllAscii : Boolean;
begin
  HasLetter := False;
  AllAscii  := True;
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z']) then HasLetter := True;
    if Ord(C) > 127 then AllAscii := False;
  end;
  Result := (not HasLetter) and AllAscii;
end;

class procedure TDfmHardcodedCaptionDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All : TList<TComponentNode>;
  N   : TComponentNode;
  V   : TPropValue;
  P   : string;
  F   : TLeakFinding;
begin
  if Graph = nil then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      for P in CAPTION_PROPS do
      begin
        if not N.TryGetProperty(P, V) then Continue;
        if V.Kind <> pvkString          then Continue;
        if Trim(V.RawValue) = ''        then Continue;
        // Reine Symbol-/Ziffern-Captions ('-', '...', '123') sind nicht
        // lokalisierbar -> kein i18n-Smell.
        if IsNonTranslatable(Trim(V.RawValue)) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(V.Line);
        F.MissingVar := Format('%s.%s = ''%s''', [N.Name, P, V.RawValue]);
        F.SetKind(fkDfmHardcodedCaption);
        Results.Add(F);
      end;
    end;
  finally
    All.Free;
  end;
end;

end.
