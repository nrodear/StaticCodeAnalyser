unit uIDEEditorIntegration;

// Zustandslose Huellen um die ToolsAPI fuer alles, was Dock-Fenster,
// Kontextmenue und Gluehbirne vom IDE-Editor brauchen:
//   * eine Datei im Editor oeffnen und zu einer Zeile springen
//     (OpenFileAtLine, ShowFileAtLine, CenterCurrentViewOnLine);
//   * die .pas der obersten Ansicht bestimmen (TryGetCurrentPasFile) und
//     Datei plus Caret-Zeile einer Ansicht lesen (ViewFileAndLine,
//     TopViewFileAndLine - EINE Fassung fuer Kontextmenue und Birne,
//     Review 2026-10-14, Punkt 10);
//   * Caret und Auswahl einer Ansicht in ZEICHEN-Spalten als
//     TEditorContext (ViewContext, TopViewContext - Charge B, V3: die
//     Code-Aktionen ohne Fund im Editor-Kontextmenue);
//   * das Verzeichnis des aktiven Projekts (GetCurrentProjectDir);
//   * eine Zeile VOR eine Pufferzeile schreiben (InsertLineAbove - der
//     Unterdrueck-Marker von Ctrl+Alt+S ohne Anbieter).
//
// Vorher: zwei Methoden + eine free function direkt in der God-Class
// TAnalyserFrame, alle drei mit `BorlandIDEServices as IOTAxxx`-Casts
// die `EIntfCastError` werfen wenn der Service in einem instabilen
// IDE-Zustand nicht verfuegbar ist (z.B. waehrend BPL-Reload).
//
// Hier saubere `Supports(...)`-Casts -> defensive failure-mode statt
// AV. Loest gleich zwei TODO-Items zu „OpenFileAtLine / Analyse
// CurrentFileClick AV-Pfade" und „RegisterDockableForm `as`-Cast".

interface

uses
  ToolsAPI,
  uFindingActions;   // TEditorContext (ViewContext)

type
  // Status-Code von TryGetCurrentPasFile - der Caller will pro Fehlerursache
  // eine andere Status-Bar-Meldung anzeigen (lokalisierter Text bleibt im
  // Caller, dieser hier ist UI-frei).
  TCurrentFileResult = (
    cfrOK,                 // .pas-Datei erfolgreich detektiert
    cfrNoEditorService,    // BorlandIDEServices ohne IOTAEditorServices
    cfrNoOpenView,         // kein offener Editor-View / Buffer
    cfrNotPascalFile       // Datei offen, aber kein .pas / .dfm
  );

  // Result-Code von OpenFileAtLine - damit der Aufrufer in der Status-Bar
  // den richtigen Hinweis zeigen kann.
  TOpenFileMode = (
    ofmRegular,         // .pas oder DFM-im-Code-Editor: alles normal
    ofmDfmAsText        // .dfm-Befund: .pas geschlossen, DFM jetzt als
                        // Text im Code-Editor sichtbar (Close-and-Reopen)
    // Ein dritter Wert ofmDfmFallbackPas ("Companion-.pas war modifiziert,
    // deshalb nur die .pas geoeffnet") stand hier bis 2026-08-18. Er wurde
    // NIE zugewiesen: OpenFileAtLine setzt ausschliesslich ofmRegular und
    // ofmDfmAsText, weil SafeCloseModule bewusst CloseModule(True)
    // (save-if-dirty) benutzt statt eines Modified-Checks. Der Wert hat
    // damit einen Fall beschrieben, den es im Code nicht gibt - samt
    // totem Vergleich, unerreichbarem case-Zweig beim Aufrufer und zwei
    // gepflegten Uebersetzungen.
  );

  TIDEEditor = class
  public
    // Versucht den Pfad der aktuell im Editor offenen .pas- oder .dfm-Datei
    // zu liefern. Bei OK enthaelt APath einen absoluten Pfad.
    // Bei einer .dfm wird automatisch auf die zugehoerige .pas umgeleitet
    // (gleicher Basename im gleichen Ordner), damit der DFM-Analyse-Runner
    // sie sauber als Pas-Input bekommt - er sucht intern selbst nach
    // der .dfm dazu.
    class function TryGetCurrentPasFile(out APath: string): TCurrentFileResult; static;

    // Datei und Caret-Zeile EINER Ansicht - ohne Umleitung auf die .pas:
    // auch .dpr/.dpk/.inc, und in der Textansicht eines Formulars die
    // .dfm selbst (deren Zeilen stehen nicht in der .pas; Review reDelphiX
    // nach Bereichen 2026-10-10, Minor 20). False ohne Ansicht, Puffer,
    // Dateinamen oder bei Zeile < 1. nil-sicher.
    class function ViewFileAndLine(const AView: IOTAEditView;
      out AFile: string; out ALine: Integer): Boolean; static;
    // Dasselbe fuer die oberste Ansicht (TopView) - der Weg des
    // Editor-Kontextmenues; die Gluehbirne nimmt die Ansicht IHRES
    // Editors (INTACodeEditorServices.GetViewForEditor) und ruft
    // ViewFileAndLine.
    class function TopViewFileAndLine(out AFile: string;
      out ALine: Integer): Boolean; static;

    // Datei, Caret (Zeile, ZEICHEN-Spalte 1-basiert) und Auswahl einer
    // Ansicht als TEditorContext (Charge B, V3). Datei und Zeile wie
    // ViewFileAndLine (auch .dfm in der Textansicht), False in denselben
    // Faellen. Die Spalten kommen aus IOTAEditView.ConvertPos: CharIndex
    // zaehlt ZEICHEN (0-basiert, Tab = 1; gemessen 2026-10-11) - keine
    // Byte-Rechnung, kein Puffertext. Auswahl nur aus einem gueltigen,
    // sichtbaren, nicht leeren Block; ein Spaltenblock ist keine Auswahl
    // (uEditorContextModel.ApplyEditorBlock). Findings bleibt leer (setzt
    // der Aufrufer). Protokolliert Rohwerte und Umrechnung per
    // OutputDebugString ('SCA: ctx ...', nur im DEBUG-Bau) - Messpunkt fuer
    // den UI-Test (btInclusive/btLine und das Blockende auf
    // Nicht-ASCII-Zeilen sind ungemessen). Reine Abfrage: kein Notifier,
    // kein Fenster. Nur mit GContextActionsOn gerufen - ohne den Schalter
    // nimmt das Kontextmenue TopViewFileAndLine wie bis Charge B.
    class function ViewContext(const AView: IOTAEditView;
      out ACtx: TEditorContext): Boolean; static;
    // Dasselbe fuer die oberste Ansicht - der Weg des Editor-Kontextmenues.
    class function TopViewContext(out ACtx: TEditorContext): Boolean; static;

    // Liefert das Verzeichnis des aktiven IDE-Projekts (ohne Trailing
    // PathDelimiter). Leer wenn kein Projekt geladen oder Service
    // nicht verfuegbar.
    class function GetCurrentProjectDir: string; static;

    // Oeffnet eine Datei im IDE-Editor (oder bringt sie nach vorne wenn
    // bereits offen) und positioniert den Cursor auf LineNumber.
    // No-op bei nicht-verfuegbaren Services.
    //
    // LineNumber <= 0 ist KEIN No-op, anders als es hier bis 2026-08-19
    // stand: die Companion-Behandlung unten laeuft davor, die Datei wird
    // also geoeffnet (und die Companion-.pas ggf. geschlossen und
    // gespeichert, s.u.) - nur der Cursor wird nicht gesetzt.
    //
    // Bei einer .dfm-Datei laeuft die Close-and-Reopen-Strategie: die
    // zugehoerige .pas wird geschlossen und die .dfm direkt geoeffnet -
    // sie landet als Text im Code-Editor (siehe DFMCheck/GExperts-Pattern).
    //
    // ACHTUNG, Nebenwirkung: geschlossen wird ueber SafeCloseModule, und
    // das ruft CloseModule(True) - save-if-dirty. Eine modifizierte
    // Companion-.pas wird also UNGEFRAGT GESPEICHERT und ihr Tab
    // geschlossen. Kein Datenverlust, aber ein halbfertiger Stand landet
    // auf der Platte. Das ist Absicht: ein expliziter Modified-Check ist
    // unter Delphi 12 unzuverlaessig (Begruendung an SafeCloseModule),
    // und ein Fallback-Pfad dafuer existierte nie - der Enum-Wert, der
    // ihn versprach, war toter Code.
    class function OpenFileAtLine(const AbsPath: string;
                                  LineNumber: Integer): TOpenFileMode; static;

    // Soft-Variante von OpenFileAtLine - KEIN Close-and-Reopen-Pattern
    // fuer die Companion-Datei. Sinnvoll wenn der User aus einer Findings-
    // Liste auf einen Befund klickt und die Datei bereits offen ist - die
    // Original-Methode schliesst auch normale Form-Module (da
    // FindModule(.dfm) das Foo-Modul liefert), was zu "Datei wird immer
    // wieder neu geoeffnet" fuehrt.
    // Wenn die Datei noch nicht offen ist: ActionSvc.OpenFile.
    // Bei .dfm-Befunden faellt der DFM-as-Text-Modus weg - die DFM wird im
    // Form-Designer angezeigt, der Caret laesst sich dort nicht setzen.
    // Liefert True wenn der Caret erfolgreich gesetzt wurde.
    class function ShowFileAtLine(const AbsPath: string;
                                  LineNumber: Integer): Boolean; static;

    // Bringt LineNumber im aktuellen Top-EditView in die Mitte des
    // Editor-Fensters und setzt den Cursor dorthin. No-op bei
    // LineNumber <= 0 oder fehlendem Editor-Service.
    //
    // Unterschied zu OpenFileAtLine.MoveViewToCursor: letzteres scrollt
    // nur das Minimum noetig, damit der Cursor sichtbar wird (haengt am
    // oberen oder unteren Rand). Hier rechnen wir die sichtbare Hoehe
    // aus BottomRow-TopRow aus und setzen SetTopLeft so dass die
    // Zielzeile vertikal mittig liegt - der User sieht den Befund
    // sofort ohne Augen-Tracking-Aufwand.
    class procedure CenterCurrentViewOnLine(LineNumber: Integer); static;

    // Fuegt eine neue Zeile DIREKT VOR der angegebenen LineNumber ein.
    // Wird vom Auto-Suppress benutzt: `// noinspection <RuleName>`
    // ueber der Befund-Zeile (Host und Zeile liefert
    // TSuppression.MarkerTargetFor - bei einem .dfm-Fund die .pas).
    // NewLine wird mit der Einrueckung der Befund-Zeile ausgerichtet
    // (lexikalisches Whitespace-Kopieren), damit der Marker visuell zur
    // Code-Zeile gehoert; das Zeilenende ist das des PUFFERS an dieser
    // Zeile (eine LF-Datei bekommt kein CRLF untergeschoben, Review
    // 2026-10-14), hinter der letzten Zeile ohne Zeilenende sLineBreak.
    //
    // Liefert True bei Erfolg, sonst False (Datei nicht in der IDE,
    // Zeile out-of-range, ...).
    class function InsertLineAbove(const AbsPath: string;
      LineNumber: Integer; const NewLine: string): Boolean; static;
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, DuplicateBlock, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows,        // OutputDebugString; VOR System.SysUtils (FindClose-Falle)
  System.SysUtils, System.IOUtils, System.StrUtils,
  uCrashDiag,            // EStackExhausted - nie verschlucken
  uEditorContextModel;   // ApplyEditorBlock, CharColOfIndex - der getestete Kern

function FirstSourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
// Der Pascal-Quelltext eines Moduls: der erste IOTASourceEditor unter den
// ModuleFileEditors - ein Form-Modul fuehrt dort auch den DFM-Editor, und
// nur der erste Quelltext-Editor ist die .pas. nil ohne Modul oder ohne
// Quelltext-Editor. Stand bis 2026-10-14 dreimal als Schleife in dieser
// Unit (OpenFileAtLine, ShowFileAtLine, TryGetEditPosition).
var
  i : Integer;
begin
  Result := nil;
  if not Assigned(AModule) then Exit;
  for i := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[i], IOTASourceEditor, Result) then
      Exit;
  Result := nil;
end;

class function TIDEEditor.TryGetCurrentPasFile(out APath: string): TCurrentFileResult;
var
  EditorSvc : IOTAEditorServices;
  EditView  : IOTAEditView;
  Path      : string;
  AsPas     : string;
begin
  APath := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then
    Exit(cfrNoEditorService);
  EditView := EditorSvc.TopView;
  if not Assigned(EditView) or not Assigned(EditView.Buffer) then
    Exit(cfrNoOpenView);
  Path := EditView.Buffer.FileName;
  if Path = '' then Exit(cfrNotPascalFile);

  if Path.EndsWith('.pas', True) then
  begin
    APath  := Path;
    Result := cfrOK;
    Exit;
  end;

  // Bei einer .dfm-Datei auf die zugehoerige .pas umleiten, falls sie im
  // gleichen Ordner existiert. Der Analyse-Runner sucht die .dfm dann
  // selbst wieder ueber TPath.ChangeExtension.
  //
  // A6/C10-INVENTUR-ABSCHLUSS (2026-09-18, autonom entschieden):
  // BEWUSST delphi-only. Das Plugin laeuft in der Delphi-IDE und
  // scannt deren AKTIVES Projekt - dlFpc-Funde (.lfm/.pp) entstehen
  // auf diesem Pfad nie; eine .lfm-Weiche hier waere toter Code.
  // Gleiches gilt fuer uIDEAnalyserForm (SafeClose-Designer-Schutz -
  // .lfm oeffnet keinen Delphi-Designer) und uIDEWatchMode
  // (CompanionOf). Damit sind alle 16 Stellen der A4-Paarungs-
  // Inventur behandelt: 12 Engine (A4/A5), 2 Form-UI (C9), 2 IDE
  // (dieser Entscheid).
  if Path.EndsWith('.dfm', True) then
  begin
    AsPas := TPath.ChangeExtension(Path, '.pas');
    if TFile.Exists(AsPas) then
    begin
      APath  := AsPas;
      Result := cfrOK;
      Exit;
    end;
  end;

  Result := cfrNotPascalFile;
end;

class function TIDEEditor.ViewFileAndLine(const AView: IOTAEditView;
  out AFile: string; out ALine: Integer): Boolean;
begin
  AFile  := '';
  ALine  := 0;
  Result := False;
  if not Assigned(AView) or not Assigned(AView.Buffer) then Exit;
  AFile := AView.Buffer.FileName;
  ALine := AView.CursorPos.Line;
  Result := (AFile <> '') and (ALine >= 1);
end;

class function TIDEEditor.TopViewFileAndLine(out AFile: string;
  out ALine: Integer): Boolean;
var
  EditorSvc : IOTAEditorServices;
begin
  AFile  := '';
  ALine  := 0;
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  Result := ViewFileAndLine(EditorSvc.TopView, AFile, ALine);
end;

procedure CtxLog(const AFormat: string; const AArgs: array of const);
// Messkanal von ViewContext (DebugView, Praefix 'SCA: ctx') - Rohwerte und
// Umrechnung fuer den UI-Test; eine Meldung im Editor waere lauter als der
// Nutzen. Nur im DEBUG-Bau (Konfiguration Debug des Plugin-Projekts, wie
// der Detector-Review-Filter in uIDEAnalyserForm): eine MESSUNG, keine
// Fehlerdiagnose - die bleibt immer sichtbar (uUiElementRegistry). Im
// Release-Bau ein leerer Aufruf (Review Charge B, Befund 3).
begin
  {$IFDEF DEBUG}
  // noinspection DebugOutput
  OutputDebugString(PChar('SCA: ctx ' + Format(AFormat, AArgs)));
  {$ENDIF}
end;

function BlockStyleOf(AStyle: TOTABlockType): TEditorBlockStyle;
// ToolsAPI-Blockart -> Spiegel in uEditorContextModel (gleiche Reihenfolge,
// aber per case - keine Ord-Gleichheit vorausgesetzt).
begin
  case AStyle of
    btInclusive    : Result := ebsInclusive;
    btLine         : Result := ebsLine;
    btColumn       : Result := ebsColumn;
    btNonInclusive : Result := ebsNonInclusive;
  else
    Result := ebsUnknown;
  end;
end;

function CharColAt(const AView: IOTAEditView; ALine, ADisplayCol: Integer): Integer;
// Anzeige-Spalte (TOTAEditPos.Col, Tabs expandiert) -> Zeichen-Spalte
// (1-basiert) ueber die IDE selbst: ConvertPos(True, ...) liefert
// TOTACharPos.CharIndex in ZEICHEN der Zeile (Rueckrichtung von reDelphix
// uRdxEditor.DisplayPosOf). TOTAEditPos.Col ist SmallInt - ein Block-Wert
// ausserhalb wird vorher gekappt (sonst ERangeError unter $R+).
var
  EP : TOTAEditPos;
  CP : TOTACharPos;
begin
  if ADisplayCol < 1 then
    ADisplayCol := 1
  else if ADisplayCol > High(SmallInt) then
    ADisplayCol := High(SmallInt);
  EP.Line      := ALine;
  EP.Col       := ADisplayCol;
  CP.Line      := ALine;
  CP.CharIndex := 0;
  AView.ConvertPos(True, EP, CP);
  Result := CharColOfIndex(CP.CharIndex);
end;

class function TIDEEditor.ViewContext(const AView: IOTAEditView;
  out ACtx: TEditorContext): Boolean;
var
  FileName : string;
  Line     : Integer;
  Caret    : TOTAEditPos;
  Block    : IOTAEditBlock;
  Raw      : TEditorBlockChars;
  {$IFDEF DEBUG}
  Buf      : IOTAEditBuffer;
  {$ENDIF}
begin
  ACtx   := Default(TEditorContext);
  Result := False;
  if not ViewFileAndLine(AView, FileName, Line) then Exit;
  Caret := AView.CursorPos;
  ACtx  := TEditorContext.At(FileName, Line, CharColAt(AView, Line, Caret.Col));
  CtxLog('caret %d:%d (display) -> char col %d', [Caret.Line, Caret.Col, ACtx.Col]);
  Block := AView.Block;
  if Assigned(Block) and Block.IsValid and Block.Visible and (Block.Size > 0) then
  begin
    Raw.Style     := BlockStyleOf(Block.Style);
    Raw.StartLine := Block.StartingRow;
    Raw.StartCol  := CharColAt(AView, Block.StartingRow, Block.StartingColumn);
    Raw.EndLine   := Block.EndingRow;
    Raw.EndCol    := CharColAt(AView, Block.EndingRow, Block.EndingColumn);
    ApplyEditorBlock(ACtx, Raw);
    // Messung (UI-Test) nur im DEBUG-Bau - auch die Lesezugriffe dafuer.
    {$IFDEF DEBUG}
    CtxLog('block style=%d size=%d '
      + 'display %d:%d..%d:%d -> chars %d:%d..%d:%d -> sel=%s %d:%d..%d:%d',
      [Ord(Block.Style), Block.Size,
       Block.StartingRow, Block.StartingColumn,
       Block.EndingRow, Block.EndingColumn,
       Raw.StartLine, Raw.StartCol, Raw.EndLine, Raw.EndCol,
       BoolToStr(ACtx.HasSelection, True),
       ACtx.SelStartLine, ACtx.SelStartCol, ACtx.SelEndLine, ACtx.SelEndCol]);
    // Nur Messung (nicht benutzt): die Blockgrenzen des Puffers als
    // TOTACharPos - ob deren CharIndex Zeichen oder Bytes zaehlt, ist
    // ungemessen (memory: SyncEditBlock liest das Blockende als Bytes).
    Buf := AView.Buffer;
    if Assigned(Buf) then
      CtxLog('buffer block start %d:%d after %d:%d (raw CharIndex)',
        [Buf.BlockStart.Line, Buf.BlockStart.CharIndex,
         Buf.BlockAfter.Line, Buf.BlockAfter.CharIndex]);
    {$ENDIF}
  end;
  Result := True;
end;

class function TIDEEditor.TopViewContext(out ACtx: TEditorContext): Boolean;
var
  EditorSvc : IOTAEditorServices;
begin
  ACtx   := Default(TEditorContext);
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  Result := ViewContext(EditorSvc.TopView, ACtx);
end;

class function TIDEEditor.GetCurrentProjectDir: string;
var
  ModSvc    : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  ProjGroup := ModSvc.MainProjectGroup;
  if Assigned(ProjGroup) then
    Result := ExcludeTrailingPathDelimiter(
      ExtractFilePath(ProjGroup.FileName));
end;

class function TIDEEditor.OpenFileAtLine(const AbsPath: string;
  LineNumber: Integer): TOpenFileMode;

  procedure SafeCloseModule(ModSvc: IOTAModuleServices; const APath: string);
  // Modul schliessen mit Save-if-Modified. In Delphi 12 ist sowohl
  // IOTAEditor.Modified als auch IOTAEditBuffer.IsModified direkt
  // nach OpenFile unzuverlaessig True (auch ohne User-Edit). Ein
  // expliziter Modified-Check rutscht damit fast immer in den Fallback
  // und blockiert den Close-and-Reopen-Trick.
  //
  // Pragma: CloseModule(True) ist idempotent wenn nichts wirklich
  // modifiziert wurde (max. LastWriteTime aendert sich) und schuetzt
  // gegen Datenverlust bei echten User-Edits. Pattern aus DFMCheck.
  //
  // Alle Interface-Refs explizit auf nil, sonst Refcount-Assert beim
  // IDE-internen Destroy ("TEditSource Refcount = 2").
  var
    Mod_: IOTAModule;
  begin
    Mod_ := ModSvc.FindModule(APath);
    if Mod_ = nil then Exit;
    Mod_.CloseModule(True);
    Mod_ := nil;
  end;

var
  ModuleSvc  : IOTAModuleServices;
  ActionSvc  : IOTAActionServices;
  Module     : IOTAModule;
  SrcEditor  : IOTASourceEditor;
  EditView   : IOTAEditView;
  EditPos    : TOTAEditPos;
  TargetPath : string;
  AsPas      : string;
  AsDfm      : string;
  IsDfm      : Boolean;
  // Gemerkt statt sofort nach Result geschrieben - gemeldet wird der Modus
  // erst, wenn das Modul wirklich offen ist.
  DfmAsText  : Boolean;
begin
  Result     := ofmRegular;
  DfmAsText  := False;
  IsDfm      := EndsText('.dfm', AbsPath);
  TargetPath := AbsPath;

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleSvc) then Exit;
  Supports(BorlandIDEServices, IOTAActionServices, ActionSvc);

  // Close-and-Reopen-Strategy:
  //   .dfm-Befund: zugehoerige .pas schliessen damit OpenFile(.dfm) als
  //                TEXT in den Code-Editor laedt (sonst Form-Designer).
  //   .pas-Befund: zugehoerige .dfm schliessen falls sie als generischer
  //                Text-Buffer offen ist (von einem vorherigen DFM-Doppel-
  //                klick), sonst wuerde OpenFile(.pas) sie in den Form-
  //                Designer "assimilieren".
  //
  // SafeCloseModule nutzt CloseModule(True) (save-if-dirty), weil
  // Modified-Checks in Delphi 12 nach OpenFile unzuverlaessig sind -
  // siehe Helper-Doku. Pattern aus DFMCheck.
  if IsDfm then
  begin
    AsPas := TPath.ChangeExtension(AbsPath, '.pas');
    if TFile.Exists(AsPas) then
      SafeCloseModule(ModuleSvc, AsPas);
    // Result erst NACH dem erfolgreichen Oeffnen setzen (Review-Minor
    // 2026-08-19): hier stand 'Result := ofmDfmAsText', und der Wert
    // ueberlebte auch den Exit bei nicht gefundenem Modul. Die Statuszeile
    // meldete dann "als Text geoeffnet", obwohl gar nichts offen war.
    DfmAsText := True;
  end
  else
  begin
    AsDfm := TPath.ChangeExtension(AbsPath, '.dfm');
    if TFile.Exists(AsDfm) then
      SafeCloseModule(ModuleSvc, AsDfm);
  end;

  // Modul suchen (bereits geoeffnet oder erst oeffnen).
  Module := ModuleSvc.FindModule(TargetPath);
  if not Assigned(Module) then
  begin
    if Assigned(ActionSvc) then
      ActionSvc.OpenFile(TargetPath);
    Module := ModuleSvc.FindModule(TargetPath);
  end;

  if not Assigned(Module) then Exit;
  // Ab hier ist das Modul offen - erst jetzt darf der DFM-als-Text-Modus
  // nach aussen gemeldet werden.
  if DfmAsText then
    Result := ofmDfmAsText;
  if LineNumber <= 0 then Exit;

  // IOTASourceEditor aus dem Modul holen.
  SrcEditor := FirstSourceEditorOf(Module);
  if not Assigned(SrcEditor) then Exit;

  // Editor-Tab in den Vordergrund bringen (wichtig wenn Datei bereits
  // geoeffnet war und nur ein anderer Tab aktiv ist).
  SrcEditor.Show;

  EditView := SrcEditor.GetEditView(0);
  if Assigned(EditView) then
  begin
    EditPos.Col  := 1;
    EditPos.Line := LineNumber;
    EditView.CursorPos := EditPos;
    EditView.MoveViewToCursor;
    EditView.Paint;
  end;
end;

class function TIDEEditor.ShowFileAtLine(const AbsPath: string;
  LineNumber: Integer): Boolean;
// Soft-Navigate. Kein SafeCloseModule auf den Companion - ein normales
// Form-Modul (Foo.pas + Foo.dfm) wuerde sonst beim Klick komplett
// geschlossen, weil FindModule(Foo.dfm) das Foo-Modul liefert.
var
  ModSvc    : IOTAModuleServices;
  ActSvc    : IOTAActionServices;
  Module    : IOTAModule;
  SrcEditor : IOTASourceEditor;
  EditView  : IOTAEditView;
  EditPos   : TOTAEditPos;
begin
  Result := False;
  if (AbsPath = '') or (LineNumber <= 0) then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  Module := ModSvc.FindModule(AbsPath);
  if not Assigned(Module) then
  begin
    if Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then
      ActSvc.OpenFile(AbsPath);
    Module := ModSvc.FindModule(AbsPath);
  end;
  if not Assigned(Module) then Exit;

  // SrcEditor aus dem Modul holen.
  SrcEditor := FirstSourceEditorOf(Module);
  if not Assigned(SrcEditor) then Exit;

  SrcEditor.Show;   // Tab nach vorne bringen

  EditView := SrcEditor.GetEditView(0);
  if not Assigned(EditView) then Exit;
  EditPos.Col  := 1;
  EditPos.Line := LineNumber;
  EditView.CursorPos := EditPos;
  EditView.MoveViewToCursor;
  EditView.Paint;
  Result := True;
end;

class procedure TIDEEditor.CenterCurrentViewOnLine(LineNumber: Integer);
const
  // Fallback wenn BottomRow/TopRow keine plausible Editor-Hoehe liefern
  // (z.B. View noch nicht gepaintet, IDE-Layout-Edge-Case). 24 entspricht
  // einer typischen Code-Editor-Hoehe; Half = 12 platziert die Zielzeile
  // ungefaehr in der vertikalen Mitte.
  FALLBACK_HALF_ROWS = 12;
var
  EditorSvc : IOTAEditorServices;
  EditView  : IOTAEditView;
  EditPos   : TOTAEditPos;
  Visible   : Integer;
  TopTarget : Integer;
begin
  if LineNumber <= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorSvc) then Exit;
  EditView := EditorSvc.TopView;
  if not Assigned(EditView) then Exit;

  // Cursor auf Zielzeile setzen (sichtbarer Caret + Edit-Hooks reagieren).
  EditPos.Col  := 1;
  EditPos.Line := LineNumber;
  EditView.CursorPos := EditPos;

  // Sichtbare Zeilen ausrechnen. BottomRow-TopRow+1 ist die Editor-Hoehe in
  // Zeilen. Bei nicht-plausiblen Werten (Edge-Case beim ersten Paint) auf
  // FALLBACK_HALF_ROWS*2 zurueckfallen.
  Visible := EditView.BottomRow - EditView.TopRow + 1;
  if Visible < 4 then
    Visible := FALLBACK_HALF_ROWS * 2;

  TopTarget := LineNumber - (Visible div 2);
  if TopTarget < 1 then TopTarget := 1;
  EditView.SetTopLeft(TopTarget, 1);
  EditView.Paint;
end;

function TryGetEditPosition(const AbsPath: string;
  out AEditPos: IOTAEditPosition): Boolean;
// Loest einen Dateipfad zur Cursor-API des IDE-Editors auf:
//   Modul finden (oder oeffnen) -> Source-Editor -> EditView -> Buffer
//   -> EditPosition
//
// Einziger Aufrufer ist seit 2026-10-10 InsertLineAbove (der zweite,
// ApplyLineReplacement fuer den alten uQuickFix-Weg, entfiel - Ctrl+Alt+F
// laeuft ueber die Anbieter-Registry). Die Routine bleibt eigenstaendig,
// weil sie der EINE Ort ist, an dem das Plugin einen Pfad in eine
// Schreibposition des Puffers uebersetzt: Modulwahl, Editorwahl und
// View-Wahl stehen hier, nicht im Schreiber.
//
// Der Source-Editor wird ueber die ModuleFileEditors gesucht und nicht
// ueber Index 0: ein Form-Modul liefert dort auch den DFM-Editor, und
// nur der erste IOTASourceEditor ist der Pascal-Quelltext.
//
// Bekannte Enge, bewusst uebernommen statt hier still geaendert:
// EditViews[0] ist nicht zwingend der AKTIVE View. Bei geteiltem Fenster
// editiert der Nutzer moeglicherweise in einem anderen. Es zu aendern ist
// eine Verhaltensfrage und gehoert in einen eigenen Schritt.
var
  ModSvc     : IOTAModuleServices;
  Module     : IOTAModule;
  SourceEdit : IOTASourceEditor;
  EditView   : IOTAEditView;
  EditBuffer : IOTAEditBuffer;
begin
  Result   := False;
  AEditPos := nil;
  if AbsPath = '' then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;

  Module := ModSvc.FindModule(AbsPath);
  if Module = nil then
  begin
    try
      Module := ModSvc.OpenModule(AbsPath);
    except
      on EStackExhausted do raise;
      on EAbort do raise;
      // noinspection ExceptionTooGeneral
      // Die IDE konnte das Modul nicht oeffnen (Datei weg, gesperrt,
      // fremder Dateityp - die OTA wirft dafuer keine eigene Klasse): fuer
      // den Aufrufer ist das "nicht schreibbar", er meldet es in der
      // Statuszeile; eine IDE-Meldung waere lauter als der Schaden.
      on Exception do Exit;
    end;
  end;
  if Module = nil then Exit;

  SourceEdit := FirstSourceEditorOf(Module);
  if SourceEdit = nil then Exit;
  if SourceEdit.EditViewCount = 0 then Exit;

  EditView := SourceEdit.EditViews[0];
  if EditView = nil then Exit;
  EditBuffer := EditView.Buffer;
  if EditBuffer = nil then Exit;
  AEditPos := EditBuffer.EditPosition;
  Result := AEditPos <> nil;
end;

function BufferLineBreakAt(const AEditPos: IOTAEditPosition): string;
// Zeilenende des Puffers an der Zeile der Position: Read hinter dem
// Zeilenende liefert die Umbruchzeichen selbst (CRLF, LF, CR). Keine
// (letzte Zeile ohne Umbruch) oder etwas anderes: sLineBreak wie bisher.
// Verschiebt die Position ans Zeilenende - der Aufrufer setzt sie neu.
var
  Tail : string;
begin
  Result := sLineBreak;
  AEditPos.MoveEOL;
  Tail := AEditPos.Read(2);
  if Tail.StartsWith(#13#10) then
    Result := #13#10
  else if (Tail <> '') and (Tail[1] = #10) then
    Result := #10
  else if (Tail <> '') and (Tail[1] = #13) then
    Result := #13;
end;

class function TIDEEditor.InsertLineAbove(const AbsPath: string;
  LineNumber: Integer; const NewLine: string): Boolean;
// Strategie:
//   1. Modul / Source-Editor ueber TryGetEditPosition
//   2. EditPosition.GotoLine(LineNumber); MoveBOL;
//   3. Read(MaxIndent) -> Einrueckungs-String der Befund-Zeile lesen
//   4. MoveEOL; Read(2) -> das Zeilenende des Puffers an dieser Zeile
//   5. EditPosition.GotoLine(LineNumber); MoveBOL; (zurueck nach Read)
//   6. InsertText(Indent + NewLine + Zeilenende);
//
// `Indent + NewLine` wird VOR der bestehenden Zeile eingefuegt - die
// alte Zeile rutscht eins runter. Ctrl+Z reverts.
const
  MAX_INDENT_LEN = 32; // 32 Leerzeichen Einrueckung sind schon viel.
var
  EditPos     : IOTAEditPosition;
  j           : Integer;
  LineHead    : string;
  Indent      : string;
  LineBreak   : string;
begin
  Result := False;
  if (LineNumber <= 0) or (AbsPath = '') or (NewLine = '') then Exit;
  // Schritt 1 der Strategie oben (TryGetEditPosition).
  if not TryGetEditPosition(AbsPath, EditPos) then Exit;

  try
    // Einrueckung der Befund-Zeile auslesen.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveBOL;
    LineHead := EditPos.Read(MAX_INDENT_LEN);
    Indent := '';
    for j := 1 to Length(LineHead) do
      if CharInSet(LineHead[j], [' ', #9]) then
        Indent := Indent + LineHead[j]
      else
        Break;

    // Zeilenende des Puffers an dieser Zeile (steht noch am Zeilenanfang).
    LineBreak := BufferLineBreakAt(EditPos);

    // Cursor zurueck an Zeilen-Anfang + neue Zeile davor einfuegen.
    EditPos.GotoLine(LineNumber);
    EditPos.MoveBOL;
    EditPos.InsertText(Indent + NewLine + LineBreak);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Die Puffer-API wirft bei einer Zeile hinter dem Ende, einem
    // schreibgeschuetzten Puffer oder einem Modul im Abbau - ohne eigene
    // Klasse dafuer: nicht geschrieben, der Aufrufer meldet es in der
    // Statuszeile.
    on Exception do Exit;
  end;

  Result := True;
end;

end.
