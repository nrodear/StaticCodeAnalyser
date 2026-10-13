unit uFindingSourcePick;

{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}

// Aus welcher Quelle Editor-Kontextmenue und Gluehbirne die Funde einer
// Datei nehmen - reine Regel, ohne VCL und ohne ToolsAPI (Review
// 2026-10-14, MAJOR "Logik ohne Tests"; vorher der UseDock-Ausdruck in
// uIDEAnalyserForm.FindingsAtEditorLine). Getestet in TestProject
// (uTestFindingSourcePick) und im FPC-Pruefstand
// (SCA.SharedUI/tools/run_fpc_pure.sh).
//
// Zwei Quellen (Review reDelphiX nach Bereichen 2026-10-10, Minor 19):
//   * das Dock-Fenster, wenn es Funde dieser Datei haelt - mit dem Stand
//     (Generation) seiner Voll-Befuellung bzw. des juengeren Watch-Laufs
//     auf dieser Datei;
//   * die Kopien des letzten Silent-/Auto-Scans dieser Datei mit dem
//     Stand jenes Laufs.
// Je Datei gilt EINE Quelle, die juengere - zeilenweise gemischt zeigten
// Birne und Kontextmenue nach einem Silent-Scan alte Dock-Zeilen neben
// neuen Marken. Das Dock gewinnt bei Gleichstand (es ist die Quelle, die
// der Benutzer sieht); ohne beide Quellen gibt es keine Funde.

interface

type
  TFindingSource = (fsNone, fsDock, fsSilent);

  // Was der Aufrufer ueber die beiden Quellen weiss. Generationen sind
  // Werte eines gemeinsamen Zaehlers (NextFindingsGeneration), hoeher =
  // juenger; ohne Quelle ist die Generation ohne Bedeutung.
  TFindingSourceState = record
    DockHasFile   : Boolean;  // das Dock haelt Funde dieser Datei
    DockGen       : UInt64;   // Stand des Docks fuer diese Datei
    SilentHasFile : Boolean;  // Silent-Kopien dieser Datei liegen vor
    SilentGen     : UInt64;   // Stand des Silent-Laufs
  end;

// Die Quelle der Funde nach der Regel im Kopf.
function PickFindingSource(const AState: TFindingSourceState): TFindingSource;

// Stand des Docks fuer EINE Datei: die Voll-Befuellung, oder der Watch-
// Lauf auf dieser Datei, wenn er juenger ist (AFileGen > 0 heisst: es gab
// einen).
function DockGenerationFor(AFullGen, AFileGen: UInt64): UInt64;

implementation

function PickFindingSource(const AState: TFindingSourceState): TFindingSource;
begin
  if AState.DockHasFile
     and not (AState.SilentHasFile and (AState.SilentGen > AState.DockGen)) then
    Result := fsDock
  else if AState.SilentHasFile then
    Result := fsSilent
  else
    Result := fsNone;
end;

function DockGenerationFor(AFullGen, AFileGen: UInt64): UInt64;
begin
  Result := AFullGen;
  if AFileGen > Result then
    Result := AFileGen;
end;

end.
