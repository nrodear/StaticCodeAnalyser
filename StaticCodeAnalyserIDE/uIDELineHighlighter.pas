unit uIDELineHighlighter;

// Editor-Line-Highlight via INTAEditViewNotifier (kanonische ToolsAPI-Loesung).
//
// LAZY-VARIANTE: Beim Plugin-Load passiert NICHTS in der ToolsAPI. Der
// Manager (Singleton GHighlighter) wird nur erzeugt. Erst wenn der User
// das erste Mal einen Befund klickt, attachen wir einen INTAEditView-
// Notifier an die aktuelle EditView. Damit ist der Plugin-Install
// risikofrei - kein AV-Pfad ueber INTAEditServicesNotifier-Registrierung
// waehrend einer evtl. laufenden IDE-Paint-Phase.
//
// CLEAN UNLOAD: Beim Plugin-Unload (Components -> Remove Package) leben
// die Editor-Views weiter. Wenn wir nur den Refcount sinken liessen,
// haetten die Views weiterhin Notifier-Slots auf entladenen Code -
// AV beim naechsten Repaint. Daher trackt der Manager pro Attach
// (Notifier-Klassenref + Index + View) und ruft im Destructor
// View.RemoveNotifier(Index) per Notifier (DetachIfNeeded) bevor er die
// Listen freigibt.
//
// Architektur:
//
//   TFindingHighlighter      - Singleton (GHighlighter). Haelt die aktuell
//                              vom User selektierte Befund-Stelle (Datei +
//                              Zeile). SetSelected attached lazy einen
//                              ViewNotifier an die TopView wenn deren
//                              Buffer.FileName matcht und forciert
//                              View.Paint.
//
//   TFindingViewNotifier     - Erbt von TNotifierObject und implementiert
//                              INTAEditViewNotifier. Pro Editor-View eine
//                              Instanz. PaintLine prueft den Manager und
//                              zeichnet eine rote Markierung wenn die
//                              Zeile getroffen wird. Speichert (View, Index)
//                              fuer DetachIfNeeded beim Plugin-Unload.
//                              IOTANotifier-Methoden (Destroyed/AfterSave/
//                              ...) kommen von TNotifierObject als
//                              virtuelle No-Ops.
//
// KRITISCH fuer Vermeidung des AV in coreide290.bpl/bds.exe:
//   * TNotifierObject als Basis (NICHT TInterfacedObject + manuelle
//     IOTANotifier-Implementierung). TNotifierObject bringt korrekt
//     gesetzte Interface-Slots mit.
//   * In der Klassendeklaration NUR das Leaf-Interface listen
//     (INTAEditViewNotifier). NICHT zusaetzlich IOTANotifier - das wuerde
//     zwei separate vtables erzeugen und Supports/QueryInterface gibt
//     einen anderen Pointer zurueck als der Method-Dispatch.
//   * Keine Notifier-Registrierung waehrend Plugin-Install/-Load.
//     EditSvc.AddNotifier wird ausschliesslich aus User-getriggerten
//     UI-Pfaden (GridSelectCell etc.) heraus aufgerufen, in einer Phase
//     in der die IDE garantiert stabil ist.

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, ToolsAPI,
  uMethodd12, uSCAConsts;

type
  // WICHTIG: Basisklasse TNotifierObject, NUR INTAEditViewNotifier listen
  // (keine separate IOTANotifier-Auflistung). Siehe Header-Doku oben.
  TFindingViewNotifier = class(TNotifierObject, INTAEditViewNotifier)
  private
    // Beim Attach gespeichert, beim Plugin-Unload gebraucht um sauber
    // RemoveNotifier zu rufen statt sich auf Refcount zu verlassen.
    FView     : IOTAEditView;
    FIndex    : Integer;
    FDetached : Boolean;
  protected
    // INTAEditViewNotifier
    procedure EditorIdle(const View: IOTAEditView);
    procedure BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
    procedure EndPaint(const View: IOTAEditView);
    procedure PaintLine(const View: IOTAEditView; LineNumber: Integer;
      const LineText: PAnsiChar; const TextWidth: Word;
      const LineAttributes: TOTAAttributeArray;
      const Canvas: TCanvas; const TextRect: TRect; const LineRect: TRect;
      const CellSize: TSize);
  public
    procedure RecordAttach(const AView: IOTAEditView; AIdx: Integer);
    procedure DetachIfNeeded;
  end;

  TFindingHighlighter = class
  private
    FSelectedFile : string;        // normalisiert (lower-case, '/' -> '\')
    FSelectedLine : Integer;       // 1-basiert; 0 = nichts markiert
    // Files an die wir bereits einen ViewNotifier gehaengt haben - per
    // Buffer.FileName-Heuristik. Verhindert Doppel-Attach beim mehrfachen
    // Klick auf die selbe Datei.
    FAttachedFiles : TStringList;
    // Parallele Listen fuer Lifecycle-Tracking:
    //   FAttachedClassRefs  - direkte Klassen-Pointer fuer DetachIfNeeded
    //                         Aufrufe (Interface->TObject-Cast wird dadurch
    //                         vermieden, was bei manchen Delphi-Versionen
    //                         zickig sein kann).
    //   FAttachedIntfRefs   - Interface-Refs, halten den Notifier am Leben
    //                         solange wir ihn brauchen. Wenn diese Liste
    //                         freigegeben wird und die IDE auch keine Ref
    //                         mehr haelt -> Notifier-Refcount auf 0 ->
    //                         automatische Freigabe.
    FAttachedClassRefs : TList<TFindingViewNotifier>;
    FAttachedIntfRefs  : TList<INTAEditViewNotifier>;
    function NormalizePath(const APath: string): string;
    procedure EnsureViewNotifier(const View: IOTAEditView);
  public
    constructor Create;
    destructor Destroy; override;

    // UI ruft das beim Klick auf einen Befund. Sucht die TopView, attached
    // bei Bedarf einen INTAEditViewNotifier, forciert Repaint.
    procedure SetSelected(const AFilePath: string; ALine: Integer);
    procedure Clear;

    // Vom View-Notifier in PaintLine aufgerufen. True wenn (Datei, Zeile)
    // der aktuell selektierten Stelle entspricht.
    function ShouldHighlight(const AFilePath: string; ALine: Integer): Boolean;

    // Vor Plugin-Unload: alle attachten Notifier sauber abmelden via
    // View.RemoveNotifier(Index). Nach diesem Aufruf darf kein PaintLine-
    // Trigger der IDE mehr in unseren Code einsteigen, weil unser BPL
    // gleich entladen wird.
    procedure DetachAll;
  end;

var
  GHighlighter : TFindingHighlighter = nil;

procedure RegisterLineHighlighter;
procedure UnregisterLineHighlighter;

implementation

const
  // Schmaler roter Stripe ganz links neben der Zeile - klar sichtbar,
  // beruehrt aber den Editor-Text und das Syntax-Highlighting nicht.
  CL_HIGHLIGHT_BAR = TColor($000020D0); // R=$D0 G=$20 B=$00 -> kraeftiges Rot
  STRIPE_WIDTH_PX  = 3;

{ ---- TFindingHighlighter ---- }

constructor TFindingHighlighter.Create;
begin
  inherited;
  FSelectedFile  := '';
  FSelectedLine  := 0;
  FAttachedFiles := TStringList.Create;
  FAttachedFiles.CaseSensitive := False;
  FAttachedFiles.Sorted        := True;
  FAttachedFiles.Duplicates    := dupIgnore;
  FAttachedClassRefs := TList<TFindingViewNotifier>.Create;
  FAttachedIntfRefs  := TList<INTAEditViewNotifier>.Create;
end;

destructor TFindingHighlighter.Destroy;
begin
  // Erst alle Notifier sauber abmelden (View.RemoveNotifier), DANN die
  // Listen freigeben. Nach DetachAll halten wir kein RemoveNotifier-Recht
  // mehr, und die IntfRefs-Liste droppt die letzten Refs auf die
  // Notifier-Objekte.
  DetachAll;
  FreeAndNil(FAttachedIntfRefs);
  FreeAndNil(FAttachedClassRefs);
  FreeAndNil(FAttachedFiles);
  inherited;
end;

procedure TFindingHighlighter.DetachAll;
var
  i : Integer;
begin
  if not Assigned(FAttachedClassRefs) then Exit;
  for i := 0 to FAttachedClassRefs.Count - 1 do
    if Assigned(FAttachedClassRefs[i]) then
      FAttachedClassRefs[i].DetachIfNeeded;
end;

function TFindingHighlighter.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TFindingHighlighter.EnsureViewNotifier(const View: IOTAEditView);
// Idempotenter View-Attach. Notifier-Refcount-Lifecycle:
//   1) TFindingViewNotifier.Create        -> ref=0
//   2) Notif := ... as INTAEditViewNotifier -> ref=1
//   3) View.AddNotifier(Notif)              -> IDE +1, ref=2
//   4) FAttachedIntfRefs.Add(Notif)         -> List +1, ref=3
// Beim Plugin-Unload: DetachAll ruft RemoveNotifier (IDE -1, ref=2) und
// danach werden die Listen freigegeben (-1, -1; ref=0 -> Notifier wird
// freigegeben).
var
  Key       : string;
  ClassRef  : TFindingViewNotifier;
  IntfRef   : INTAEditViewNotifier;
  Idx       : Integer;
begin
  if not Assigned(View) or not Assigned(View.Buffer) then Exit;
  Key := View.Buffer.FileName.ToLower;
  if Key = '' then Exit;
  if FAttachedFiles.IndexOf(Key) >= 0 then Exit;
  try
    ClassRef := TFindingViewNotifier.Create;
    IntfRef  := ClassRef as INTAEditViewNotifier;
    Idx      := View.AddNotifier(IntfRef);
    ClassRef.RecordAttach(View, Idx);
    FAttachedClassRefs.Add(ClassRef);
    FAttachedIntfRefs.Add(IntfRef);
    FAttachedFiles.Add(Key);
  except
    // Falls AddNotifier in einer instabilen IDE-Phase scheitert: Highlight
    // bleibt fuer diese View aus, kein Crash.
  end;
end;

procedure TFindingHighlighter.SetSelected(const AFilePath: string;
  ALine: Integer);
var
  EditSvc : IOTAEditorServices;
  View    : IOTAEditView;
begin
  if (AFilePath = '') or (ALine <= 0) then
  begin
    Clear;
    Exit;
  end;
  FSelectedFile := NormalizePath(AFilePath);
  FSelectedLine := ALine;

  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
    View := EditSvc.TopView;
    if not Assigned(View) then Exit;
    EnsureViewNotifier(View);
    View.Paint;
  except
    // ToolsAPI darf wegfallen ohne dass wir crashen.
  end;
end;

procedure TFindingHighlighter.Clear;
var
  EditSvc      : IOTAEditorServices;
  View         : IOTAEditView;
  HadSelection : Boolean;
begin
  HadSelection := FSelectedLine > 0;
  FSelectedFile := '';
  FSelectedLine := 0;
  if not HadSelection then Exit;
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
    View := EditSvc.TopView;
    if Assigned(View) then View.Paint;
  except end;
end;

function TFindingHighlighter.ShouldHighlight(const AFilePath: string;
  ALine: Integer): Boolean;
begin
  Result := (FSelectedLine > 0) and (FSelectedLine = ALine) and
            (NormalizePath(AFilePath) = FSelectedFile);
end;

{ ---- TFindingViewNotifier ---- }

// IOTANotifier (AfterSave/BeforeSave/Destroyed/Modified) -> kommt von
// TNotifierObject als virtuelle No-Ops. Wir muessen NICHTS ueberschreiben.

procedure TFindingViewNotifier.RecordAttach(const AView: IOTAEditView;
  AIdx: Integer);
begin
  FView  := AView;
  FIndex := AIdx;
end;

procedure TFindingViewNotifier.DetachIfNeeded;
// Wird vom Manager beim Plugin-Unload aufgerufen. Versucht die View vom
// Notifier abzukoppeln, damit nach BPL-Entladung kein toter Code mehr im
// Notifier-Slot der View haengt. Mehrere Schutzschichten:
//   * FDetached-Flag verhindert doppelten Aufruf
//   * Buffer-Pruefung filtert bereits halb-zerstoerte Views aus
//   * try/except faengt EAccessViolation aus coreide290.bpl wenn die
//     View intern bereits invalidiert wurde (Index nicht mehr gueltig)
begin
  if FDetached then Exit;
  FDetached := True;
  if not Assigned(FView) then Exit;
  try
    // Wenn die View noch lebt UND noch einen Buffer hat, kann RemoveNotifier
    // sicher gerufen werden. View.Buffer = nil -> View ist tot, ToolsAPI-
    // Aufrufe waeren UB.
    if Assigned(FView.Buffer) then
      FView.RemoveNotifier(FIndex);
  except
    // View bereits halb-zerstoert oder Index stale - wir geben einfach
    // unsere Ref auf und vertrauen dem Refcount-Mechanismus.
  end;
  FView := nil;
end;

procedure TFindingViewNotifier.EditorIdle(const View: IOTAEditView);    begin end;
procedure TFindingViewNotifier.EndPaint(const View: IOTAEditView);      begin end;

procedure TFindingViewNotifier.BeginPaint(const View: IOTAEditView;
  var FullRepaint: Boolean);
begin
  // Nichts zu tun - wir forcieren ueber View.Paint einen Repaint wenn
  // sich etwas geaendert hat.
end;

procedure TFindingViewNotifier.PaintLine(const View: IOTAEditView;
  LineNumber: Integer; const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
var
  FileName : string;
begin
  if not Assigned(GHighlighter) then Exit;
  if not Assigned(View) or not Assigned(View.Buffer) then Exit;
  FileName := View.Buffer.FileName;
  if FileName = '' then Exit;
  if not GHighlighter.ShouldHighlight(FileName, LineNumber) then Exit;

  // Schmaler 3px-Stripe ganz links neben der Zeile (LineRect.Left ist die
  // linke Kante des Editor-Bereichs nach dem Gutter). Text und Syntax-
  // Highlighting bleiben unangetastet.
  Canvas.Brush.Color := CL_HIGHLIGHT_BAR;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(Rect(LineRect.Left, LineRect.Top,
                       LineRect.Left + STRIPE_WIDTH_PX, LineRect.Bottom));
end;

{ ---- Public Register/Unregister ---- }

procedure RegisterLineHighlighter;
begin
  // KEINE ToolsAPI-Aufrufe hier - reine Manager-Erzeugung. Notifier
  // werden lazy von SetSelected aus angehaengt.
  if Assigned(GHighlighter) then Exit;
  GHighlighter := TFindingHighlighter.Create;
end;

procedure UnregisterLineHighlighter;
begin
  // Auch hier KEINE ToolsAPI-Aufrufe. ViewNotifier sterben automatisch
  // mit ihren Views; wir geben nur den Manager frei.
  if Assigned(GHighlighter) then
    FreeAndNil(GHighlighter);
end;

end.
