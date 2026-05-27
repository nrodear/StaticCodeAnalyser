unit uIDEAnalyseProgress;

// Bundle der "Analyse-laeuft"-UI-Logik des Analyser-Frames:
//   * Running/Cancelled-Flags (vorher 2 separate Frame-Felder)
//   * Buttons enable/disable (Start/Current/Changed AUS, Cancel AN)
//   * Progressbar zuruecksetzen + Max setzen
//   * Mauszeiger-Wechsel (crAppStart waehrend Analyse)
//
// Vorher: SetAnalyseUiBusy (~30 Zeilen) plus CancelAnalyseClick (~5)
// im Frame, plus zwei Boolean-Felder. Jetzt zentral gebuendelt.
//
// Lifecycle:
//   * Frame-Ctor: Buttons + Progressbar erstellen, dann Controller
//     mit Referenzen darauf erstellen (haelt nur weak Pointers - die
//     Widgets bleiben Besitz des Frames).
//   * BeginRun(Total): Buttons -> aus, Cancel -> an, Progress reset.
//   * EndRun: alles zurueck, Cursor wieder Default.
//   * RequestCancel: setzt Cancelled-Flag - die Worker-Callbacks
//     pollen Cancelled und werfen EAbort.
//
// Defensiv: alle Widget-Zugriffe sind Assigned-gepruefte (die Widgets
// koennen waehrend Frame-Teardown bereits weg sein, der Controller
// wird via FreeAndNil davor freigegeben - aber unter ProcessMessages-
// Reentry kann jeder Pfad mit halbzerlegtem Zustand kollidieren).

interface

uses
  System.Classes,
  Vcl.StdCtrls, Vcl.ComCtrls;

type
  TAnalyseProgressController = class(TComponent)
  private
    FRunning   : Boolean;
    FCancelled : Boolean;
    FProgress  : TProgressBar;
    FBtnCancel : TButton;
    FBtnsRun   : TArray<TButton>;
  public
    // Buttons + Progressbar werden vom Frame erstellt; der Controller
    // nimmt Referenzen entgegen (kein Ownership). ABtnsRun ist die Liste
    // der Buttons die waehrend der Analyse blockiert werden (Start/Current/
    // Changed); ABtnCancel ist der Gegenpart der waehrenddessen aktiv wird.
    constructor Create(AOwner: TComponent;
      AProgress: TProgressBar; ABtnCancel: TButton;
      const ABtnsRun: array of TButton); reintroduce;

    // Setzt UI in den "Analyse-laeuft"-Modus. ATotal=0 bedeutet
    // "Anzahl noch unbekannt" (Progressbar Max=100, Position pulst
    // ueber Current mod 100 vom Worker-Callback).
    procedure BeginRun(ATotal: Integer = 0);

    // Setzt UI zurueck nach Analyse-Ende (egal ob normal, Fehler oder
    // Cancel). Cursor zurueck auf crDefault.
    procedure EndRun;

    // Vom Cancel-Button-OnClick aufgerufen: markiert die Analyse zum
    // Abbruch. No-op wenn keine Analyse laeuft (verhindert spurious
    // Cancel-Marker bei Doppelklick nach EndRun).
    procedure RequestCancel;

    // Read-only Status. Worker-Callbacks pollen Cancelled, der Cancel-
    // Click-Handler prueft Running.
    property Running   : Boolean read FRunning;
    property Cancelled : Boolean read FCancelled;
  end;

implementation

uses
  Vcl.Controls,  // crAppStart, crDefault
  Vcl.Forms;     // Screen

constructor TAnalyseProgressController.Create(AOwner: TComponent;
  AProgress: TProgressBar; ABtnCancel: TButton;
  const ABtnsRun: array of TButton);
var
  i: Integer;
begin
  inherited Create(AOwner);
  FProgress  := AProgress;
  FBtnCancel := ABtnCancel;
  SetLength(FBtnsRun, Length(ABtnsRun));
  for i := 0 to High(ABtnsRun) do
    FBtnsRun[i] := ABtnsRun[i];
end;

procedure TAnalyseProgressController.BeginRun(ATotal: Integer);
var
  Btn: TButton;
begin
  FRunning   := True;
  FCancelled := False;

  for Btn in FBtnsRun do
    if Assigned(Btn) then Btn.Enabled := False;
  if Assigned(FBtnCancel) then
    FBtnCancel.Enabled := True;

  // Layout-stabil: Cancel-Button + Progressbar werden NICHT ein-/
  // ausgeblendet (Visible bleibt konstant True). Nur Enabled/Position/
  // Style wechseln - die UI bleibt waehrend der Analyse ruhig.
  //
  // Style-Wahl haengt davon ab, ob Total schon bekannt ist:
  //   * ATotal > 0  -> Normal-Mode mit fertigem Max (Single-File-Analyse,
  //                    Branch-Changes mit vorab gezaehlter Liste).
  //   * ATotal = 0  -> Total noch unbekannt, Worker zaehlt erst beim Scan.
  //                    Direkt mit pbstMarquee starten, NICHT zuerst leerer
  //                    Normal-Mode-Bar mit Pos=0. Sonst sieht der User:
  //                    "leere Bar -> Marquee-Animation -> wieder leere Bar
  //                    beim Marquee->Normal-Uebergang -> Progress" - die
  //                    zwei leeren Bars wirken wie "Bar faengt zweimal
  //                    bei 0 an".
  if Assigned(FProgress) then
  begin
    FProgress.Position := 0;
    if ATotal > 0 then
    begin
      FProgress.Style := pbstNormal;
      FProgress.Max   := ATotal;
    end
    else
    begin
      FProgress.Max   := 100;
      FProgress.Style := pbstMarquee;
    end;
  end;

  Screen.Cursor := crAppStart;
end;

procedure TAnalyseProgressController.EndRun;
var
  Btn: TButton;
begin
  FRunning   := False;
  FCancelled := False;

  for Btn in FBtnsRun do
    if Assigned(Btn) then Btn.Enabled := True;
  if Assigned(FBtnCancel) then
    FBtnCancel.Enabled := False;

  if Assigned(FProgress) then
  begin
    // Defensive Style-Reset: bei Cancel mid-Scan-Phase steckt Style
    // noch auf pbstMarquee. Naechster BeginRun macht das auch nochmal,
    // aber hier ist's schon clean fuer "Bar zeigt Ruhe-Zustand".
    FProgress.Style := pbstNormal;
    FProgress.Position := 0;
  end;

  Screen.Cursor := crDefault;
end;

procedure TAnalyseProgressController.RequestCancel;
begin
  if not FRunning then Exit;
  FCancelled := True;
  // Cancel-Button sofort sperren - verhindert Doppelklick-Spam
  // bevor der Worker den naechsten Cancel-Poll durchfuehrt.
  if Assigned(FBtnCancel) then
    FBtnCancel.Enabled := False;
end;

end.
