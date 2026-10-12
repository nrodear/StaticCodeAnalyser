unit uHitCacheRepair;

{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}

// Nachfuellen des Hover-/Klick-Trefferspeichers im Editor - reine Logik,
// ohne VCL und ohne ToolsAPI (Fix F1 der Caret-Untersuchung 2026-10-12).
// Getestet in TestProject (uTestHitCacheRepair) und im FPC-Pruefstand.
// Der FPC-Modus ist delphiUNICODE und nicht delphi: so ist string hier
// derselbe Typ wie im Pruefstand (-Mdelphiunicode) und wie unter Delphi.
//
// WORUM ES GEHT: uIDELineHighlighter merkt sich je markierter Zeile das
// zuletzt gemalte Rechteck (FRenderedRects) und testet die Maus dagegen.
// Nach einem Mausrad-Scroll, bei dem EditorScrolled nicht zuverlaessig
// feuert, kann dieser Speicher veraltet sein. Seit 0fb46ff1 (2026-05-10)
// loeste deshalb JEDER Fehltreffer der Maus - gedrosselt auf einen je
// 500 ms - einen Voll-Repaint des sichtbaren Editors aus
// (InvalidateAllLines -> InvalidateTopEditor).
//
// WARUM DAS STOERT: jeder WM_PAINT des Editors laeuft ueber
// BeginPaint/EndPaint, und die verstecken und zeigen den System-Caret.
// Damit beginnt seine Blinkphase neu und ebenso das Fenster von etwa 5 s,
// nach dem Windows das Blinken anhaelt - auch wenn die neu gemalte Flaeche
// den Caret gar nicht beruehrt (Labor L8/L9). Solange sich die Maus ueber
// unmarkierten Zeilen, Fortsetzungszeilen eines Bereichsfunds oder dem
// Gutter bewegte (oder Windows ein WM_MOUSEMOVE synthetisierte, weil sich
// unter dem ruhenden Zeiger ein Fenster aenderte), wurde der Caret alle
// 500 ms an beliebiger Stelle seiner Phase neu gestartet: er blinkte
// unregelmaessig (Hypothese H1, Codestellen in der Gegenpruefung
// bestaetigt).
//
// WAS JETZT GILT: repariert wird nur, wenn sich der Sichtzustand seit der
// letzten BESTAETIGTEN Reparatur geaendert hat. Ein zweiter Voll-Repaint
// im selben Sichtzustand kann dem Speicher nichts hinzufuegen - er malt
// dieselben Zeilen an dieselben Stellen.
//   * Sichtzustand = Editorfenster, Datei, oberste Zeile, linke Spalte und
//     eine Generation. Die Generation zaehlt bei allem hoch, was den
//     Speicher leert oder veralten laesst, ohne die vier anderen Werte zu
//     aendern (Groesse, Faltung, verschobene Marken, ForceFullRepaint,
//     ResetState, Dateiwechsel im Paint, Zoom bzw. neue Editorschrift).
//   * Bestaetigt wird im EndPaint NACH einer Anforderung, und zwar mit dem
//     Sichtzustand ZU DIESEM Zeitpunkt, nicht mit dem der Anforderung.
//     Liefert die IDE den angeforderten Repaint mit ForceFullRepaint, zaehlt
//     BeginPaint die Generation hoch - ein Schluessel von vorher stimmte
//     dann nie, und jeder Fehltreffer reparierte wieder: genau H1.
//   * JEDER Voll-Repaint des Highlighters zaehlt als Anforderung
//     (Scroll-Settle, neue oder abgeraeumte Marken, Umfaerben). Sonst
//     folgte nach jedem Scroll beim ersten Fehltreffer eine ueberfluessige
//     Reparatur (Gegenpruefung 2.8, Ergaenzung 2).
//   * Ein Paint OHNE Anforderung bestaetigt nichts: ein partieller Paint
//     nach einem Scroll fuellt den Speicher nur fuer die neu gemalten
//     Zeilen und darf die Reparatur nicht verdecken.
//   * Die 500-ms-Drossel bleibt als Obergrenze und gilt auch fuer das
//     Nachsehen: der Aufrufer fragt den Sichtzustand (ToolsAPI) erst, wenn
//     IsThrottled False liefert, also hoechstens zweimal je Sekunde. Bleibt
//     der EndPaint aus (Editor verdeckt), darf nach Ablauf der Drossel
//     erneut repariert werden - wie bisher.
//   * Erreicht der Voll-Repaint den Editor gar nicht (der Highlighter kann
//     nur den OBERSTEN Editor neu malen lassen; geteilte Ansicht, zweites
//     Editorfenster), wird nicht repariert: der Repaint fuellte den Speicher
//     nicht und startete nur den Caret des anderen Editors neu. Die Pruefung
//     zaehlt trotzdem fuer die Drossel (NoteRepairUnreachable).
//
// Zeitbasis UInt64 (GetTickCount64): kein Abschneiden nach 49,7 Tagen. Die
// Uhr kommt als Parameter herein - die Tests laufen ohne Sleep.

interface

const
  // Mindestabstand zweier Pruefungen bzw. Anforderungen. Wert und
  // Vergleich ('erst NACH 500 ms') wie im alten Code.
  HIT_CACHE_THROTTLE_MS = 500;

type
  // Sichtzustand, fuer den der Trefferspeicher gilt.
  THitCacheViewKey = record
    Editor     : NativeUInt;  // HWND des EditControls
    FileName   : string;      // zuletzt gemalte Datei
    TopRow     : Integer;     // IOTAEditView.TopRow, -1 = unbekannt
    LeftColumn : Integer;     // IOTAEditView.LeftColumn, -1 = unbekannt
    Generation : Cardinal;    // Stand von THitCacheRepair beim Erzeugen
  end;

  // Zustand der Reparatur. Als Feld einer Klasse ist der Nullzustand
  // gueltig und gleich dem nach Reset; eine lokale Variable braucht Reset,
  // weil Delphi dort nur die verwalteten Felder vorbelegt.
  THitCacheRepair = record
  private
    FGeneration   : Cardinal;
    FLastTick     : UInt64;   // letzte Pruefung oder Anforderung
    FHasTick      : Boolean;
    FPending      : Boolean;  // angefordert, EndPaint steht aus
    FConfirmed    : Boolean;
    FConfirmedKey : THitCacheViewKey;
    procedure Touch(ANowMs: UInt64);
  public
    // Ausgangszustand: keine Bestaetigung, keine Drossel, Generation 0.
    procedure Reset;
    // Der Speicher kann veraltet sein, obwohl Editor, Datei, TopRow und
    // LeftColumn gleich geblieben sind.
    procedure BumpGeneration;
    // Schluessel mit der aktuellen Generation.
    function MakeKey(AEditor: NativeUInt; const AFileName: string;
      ATopRow, ALeftColumn: Integer): THitCacheViewKey;
    // True, solange seit der letzten Pruefung oder Anforderung hoechstens
    // HIT_CACHE_THROTTLE_MS vergangen sind. Billig - fuer den Aufrufer,
    // bevor er den Sichtzustand erfragt.
    function IsThrottled(ANowMs: UInt64): Boolean;
    // Fehltreffer der Maus: True heisst "jetzt EINEN Voll-Repaint
    // anfordern"; die Anforderung ist damit vorgemerkt.
    function ShouldRepair(const AKey: THitCacheViewKey;
      ANowMs: UInt64): Boolean;
    // Fehltreffer, den ein Voll-Repaint nicht beheben kann, weil er den
    // Editor nicht erreicht: Pruefung ohne Reparatur - drosselt die
    // naechste, merkt nichts vor und laesst eine offene Anforderung stehen.
    procedure NoteRepairUnreachable(ANowMs: UInt64);
    // Irgendein Voll-Repaint wurde angefordert - er fuellt den Speicher
    // genauso wie eine Reparatur.
    procedure NoteInvalidateAll(ANowMs: UInt64);
    // True zwischen einer Anforderung und dem bestaetigenden EndPaint.
    function HasPendingRequest: Boolean;
    // EndPaint des Editors mit dem Sichtzustand von jetzt. Bestaetigt nur,
    // wenn vorher angefordert wurde.
    procedure NotePaintCompleted(const AKey: THitCacheViewKey);
  end;

// Gleichheit aller fuenf Felder.
function SameHitCacheViewKey(const A, B: THitCacheViewKey): Boolean;

implementation

function SameHitCacheViewKey(const A, B: THitCacheViewKey): Boolean;
begin
  Result := (A.Editor = B.Editor) and (A.TopRow = B.TopRow)
        and (A.LeftColumn = B.LeftColumn) and (A.Generation = B.Generation)
        and (A.FileName = B.FileName);
end;

function ElapsedMs(ASince, ANow: UInt64): UInt64;
// Laeuft die Uhr rueckwaerts (GetTickCount64 tut das nicht, ein Aufrufer
// mit fremder Uhr vielleicht schon), gilt die Drossel als abgelaufen:
// lieber eine Reparatur zu viel als ein toter Hover. Ohne den Vergleich
// liefe die Subtraktion unter $Q+ in eine Ausnahme.
begin
  if ANow < ASince then
    Result := High(UInt64)
  else
    Result := ANow - ASince;
end;

procedure THitCacheRepair.Reset;
begin
  FGeneration   := 0;
  FLastTick     := 0;
  FHasTick      := False;
  FPending      := False;
  FConfirmed    := False;
  FConfirmedKey := Default(THitCacheViewKey);
end;

procedure THitCacheRepair.BumpGeneration;
begin
  // Ausdruecklich umlaufen statt Inc: die Pakete bauen mit $Q+.
  if FGeneration = High(Cardinal) then
    FGeneration := 0
  else
    FGeneration := FGeneration + 1;
end;

function THitCacheRepair.MakeKey(AEditor: NativeUInt;
  const AFileName: string; ATopRow, ALeftColumn: Integer): THitCacheViewKey;
begin
  Result.Editor     := AEditor;
  Result.FileName   := AFileName;
  Result.TopRow     := ATopRow;
  Result.LeftColumn := ALeftColumn;
  Result.Generation := FGeneration;
end;

procedure THitCacheRepair.Touch(ANowMs: UInt64);
begin
  FLastTick := ANowMs;
  FHasTick  := True;
end;

function THitCacheRepair.IsThrottled(ANowMs: UInt64): Boolean;
begin
  Result := FHasTick
        and (ElapsedMs(FLastTick, ANowMs) <= HIT_CACHE_THROTTLE_MS);
end;

function THitCacheRepair.ShouldRepair(const AKey: THitCacheViewKey;
  ANowMs: UInt64): Boolean;
begin
  Result := False;
  if IsThrottled(ANowMs) then Exit;
  // Auch eine Pruefung OHNE Reparatur setzt die Drossel neu - sonst fragte
  // der Aufrufer im bestaetigten Zustand bei jeder Mausnachricht die
  // ToolsAPI.
  Touch(ANowMs);
  if FConfirmed and SameHitCacheViewKey(AKey, FConfirmedKey) then Exit;
  FPending := True;
  Result := True;
end;

procedure THitCacheRepair.NoteRepairUnreachable(ANowMs: UInt64);
begin
  Touch(ANowMs);
end;

procedure THitCacheRepair.NoteInvalidateAll(ANowMs: UInt64);
begin
  Touch(ANowMs);
  FPending := True;
end;

function THitCacheRepair.HasPendingRequest: Boolean;
begin
  Result := FPending;
end;

procedure THitCacheRepair.NotePaintCompleted(const AKey: THitCacheViewKey);
begin
  if not FPending then Exit;
  FPending      := False;
  FConfirmed    := True;
  FConfirmedKey := AKey;
end;

end.
