unit uIDEExportMenu;

// Export-Popup-Menue des Analyser-Frame-Plugins:
// HTML-Report, JSON, CSV (alle drei via Save-Dialog) plus Jira-Wiki-
// Markup und Plain-Text-Befunde in die Zwischenablage.
//
// Vorher: 6 Click-Handler (~210 Zeilen) + ~16 Zeilen Menu-Setup direkt
// in der God-Class TAnalyserFrame, plus die Frame-Methode CurrentFocusFile
// die nur von Jira/Clipboard-Export gebraucht wurde.
//
// Jetzt: alles gekapselt in TFindingExportMenu. Frame haelt nur noch
// einen Field-Reference + ruft AttachToButton beim UI-Setup. Die
// Findings-Listen + das Grid werden by-reference durchgereicht (kein
// Ownership-Transfer); StatusMode + GetBaseDir sind Method-References
// auf den Frame, sodass Live-Werte gelesen werden, nicht eingefroren
// zur Construct-Zeit.

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Menus, Vcl.StdCtrls, Vcl.Grids,
  uMethodd12;

type
  // Callback-Signaturen fuer die Frame-Anbindung.
  TStatusProc = procedure(const Msg: string) of object;
  TStringFunc = function: string of object;
  TGridFunc   = function: TStringGrid of object;

  TFindingExportMenu = class(TComponent)
  private
    FPopup       : TPopupMenu;
    FAll         : TObjectList<TLeakFinding>; // ref - Frame ist Owner
    FDisplayed   : TList<TLeakFinding>;       // ref - Frame ist Owner
    FGetGrid     : TGridFunc;                 // liefert FResultGrid live -
                                              // braucht Getter weil das
                                              // Grid erst NACH dem Menu im
                                              // Constructor erzeugt wird
    FOnStatus    : TStatusProc;               // Frame.StatusMode
    FGetBaseDir  : TStringFunc;               // liefert FCurrentBaseDir live

    function CurrentFocusFile: string;

    procedure DoExportCsv(Sender: TObject);
    procedure DoExportJson(Sender: TObject);
    procedure DoExportJira(Sender: TObject);
    procedure DoCopyClipboard(Sender: TObject);
    procedure DoExportHtml(Sender: TObject);
    procedure DoExportSonarGeneric(Sender: TObject);
    procedure DoExportSonarSingleIssue(Sender: TObject);
    procedure DoButtonClick(Sender: TObject);
  public
    // AOwner          - Komponenten-Owner (typisch der Frame, fuer auto-Free).
    // AAllFindings    - alle Befunde (vor Filter); fuer Jira/Clipboard/HTML.
    // ADisplayed      - sichtbare Befunde (nach Filter); fuer CSV/JSON.
    // AGetGrid        - liefert das Result-Grid live (nicht zur Construct-
    //                   Zeit gecached, weil das Grid spaeter im Frame-
    //                   Constructor erzeugt wird).
    // AStatus         - Status-Bar-Update-Callback.
    // AGetBaseDir     - liefert den aktuellen Base-Directory-String live
    //                   (= FCurrentBaseDir des Frames).
    constructor Create(AOwner: TComponent;
                       AAllFindings: TObjectList<TLeakFinding>;
                       ADisplayed: TList<TLeakFinding>;
                       AGetGrid: TGridFunc;
                       AStatus: TStatusProc;
                       AGetBaseDir: TStringFunc); reintroduce;

    // Verbindet das Popup-Menu mit dem Export-Button und haengt den
    // OnClick-Handler an, der das Popup direkt unterhalb des Buttons
    // aufklappt (statt nur per Rechtsklick).
    procedure AttachToButton(Btn: TButton);
    // Oeffnet das Export-Popup an einer beliebigen Bildschirm-Koordinate.
    // Wird vom Hamburger-Menu genutzt, wenn der Export-Button im NARROW-
    // Layout hidden ist - das Item triggert weiterhin denselben Popup.
    procedure PopupAt(X, Y: Integer);
  end;

implementation

uses
  System.SysUtils, System.Types, Vcl.Dialogs, Vcl.Clipbrd,
  uExport, uSCAConsts, uLocalization, uSonarPush, Vcl.Dialogs;

constructor TFindingExportMenu.Create(AOwner: TComponent;
  AAllFindings: TObjectList<TLeakFinding>;
  ADisplayed: TList<TLeakFinding>;
  AGetGrid: TGridFunc;
  AStatus: TStatusProc;
  AGetBaseDir: TStringFunc);
var
  Mi : TMenuItem;
begin
  inherited Create(AOwner);
  FAll        := AAllFindings;
  FDisplayed  := ADisplayed;
  FGetGrid    := AGetGrid;
  FOnStatus   := AStatus;
  FGetBaseDir := AGetBaseDir;

  FPopup := TPopupMenu.Create(Self);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := _('HTML report (all findings)...');
    Mi.OnClick := DoExportHtml;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := 'JSON...';
    Mi.OnClick := DoExportJson;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := 'CSV...';
    Mi.OnClick := DoExportCsv;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := '-';
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := _('Jira markup -> Clipboard');
    Mi.OnClick := DoExportJira;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := _('Plain text -> Clipboard');
    Mi.OnClick := DoCopyClipboard;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := '-';
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := _('Sonar: write Generic Issue report...');
    Mi.OnClick := DoExportSonarGeneric;
    FPopup.Items.Add(Mi);
  Mi := TMenuItem.Create(FPopup);
    Mi.Caption := _('Sonar: send selected as external issue');
    Mi.OnClick := DoExportSonarSingleIssue;
    FPopup.Items.Add(Mi);
end;

procedure TFindingExportMenu.AttachToButton(Btn: TButton);
begin
  Btn.PopupMenu := FPopup;
  Btn.OnClick   := DoButtonClick;
end;

procedure TFindingExportMenu.PopupAt(X, Y: Integer);
begin
  FPopup.Popup(X, Y);
end;

function TFindingExportMenu.CurrentFocusFile: string;
// Welche Datei ist aktuell "im Fokus"? Bevorzugt der ausgewaehlte Grid-
// Eintrag, sonst wenn alle sichtbaren Befunde aus derselben Datei
// stammen, diese - sonst leer (= Aufrufer muss Datei abfragen).
var
  row, idx : Integer;
  refFile  : string;
  F        : TLeakFinding;
  Grid     : TStringGrid;
begin
  Result := '';
  // 1) Aktive Auswahlzeile (Grid ist erst NACH dem Menu im Frame-Constructor
  //    erzeugt - daher Live-Lookup ueber Getter, kein Direkt-Field-Cache).
  Grid := nil;
  if Assigned(FGetGrid) then Grid := FGetGrid();
  if Assigned(Grid) then
  begin
    row := Grid.Row;
    idx := row - 1;
    if (idx >= 0) and (idx < FDisplayed.Count) then
      Exit(FDisplayed[idx].FileName);
  end;
  // 2) Alle sichtbaren Befunde gehoeren zur selben Datei
  refFile := '';
  for F in FDisplayed do
  begin
    if refFile = '' then
      refFile := F.FileName
    else if not SameText(F.FileName, refFile) then
      Exit('');
  end;
  Result := refFile;
end;

// ---- Status-Helper ----
procedure TFindingExportMenu.DoButtonClick(Sender: TObject);
// Klappt das Popup-Menu direkt unterhalb des Buttons auf, sodass es
// auch ohne Rechtsklick aktiviert wird.
var
  Btn : TControl;
  Pt  : TPoint;
begin
  if not (Sender is TControl) then Exit;
  Btn := TControl(Sender);
  Pt  := Btn.ClientToScreen(Point(0, Btn.Height));
  FPopup.Popup(Pt.X, Pt.Y);
end;

procedure TFindingExportMenu.DoExportCsv(Sender: TObject);
var
  Dlg : TSaveDialog;
  Lst : TObjectList<TLeakFinding>;
begin
  if FDisplayed.Count = 0 then
  begin
    FOnStatus(_('Nothing to export - filter returns 0 entries.'));
    Exit;
  end;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title    := _('CSV export');
    Dlg.Filter   := _('CSV file (*.csv)|*.csv');
    Dlg.DefaultExt := 'csv';
    Dlg.FileName := 'analyse-befunde.csv';
    if not Dlg.Execute then Exit;

    Lst := TObjectList<TLeakFinding>.Create(False);
    try
      for var F in FDisplayed do Lst.Add(F);
      try
        TExporter.ExportCsv(Lst, Dlg.FileName);
        FOnStatus(Format(_('CSV saved: %s (%d entries)'),
          [ExtractFileName(Dlg.FileName), Lst.Count]));
      except
        on E: Exception do
          FOnStatus(_('CSV export failed: ') + E.Message);
      end;
    finally
      Lst.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFindingExportMenu.DoExportJson(Sender: TObject);
var
  Dlg : TSaveDialog;
  Lst : TObjectList<TLeakFinding>;
begin
  if FDisplayed.Count = 0 then
  begin
    FOnStatus(_('Nothing to export - filter returns 0 entries.'));
    Exit;
  end;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title    := _('JSON export');
    Dlg.Filter   := _('JSON file (*.json)|*.json');
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'analyse-befunde.json';
    if not Dlg.Execute then Exit;

    Lst := TObjectList<TLeakFinding>.Create(False);
    try
      for var F in FDisplayed do Lst.Add(F);
      try
        TExporter.ExportJson(Lst, Dlg.FileName);
        FOnStatus(Format(_('JSON saved: %s (%d entries)'),
          [ExtractFileName(Dlg.FileName), Lst.Count]));
      except
        on E: Exception do
          FOnStatus(_('JSON export failed: ') + E.Message);
      end;
    finally
      Lst.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFindingExportMenu.DoExportJira(Sender: TObject);
// Jira-Wiki-Markup fuer die fokussierte Datei in die Zwischenablage.
var
  src       : string;
  jiraText  : string;
  filterSet : TSeverityFilter;
begin
  src := CurrentFocusFile;
  if src = '' then
  begin
    FOnStatus(_('Jira export: please select a row first (file not unambiguous).'));
    Exit;
  end;
  // Standard: Fehler + Warnungen. Hinweise sind oft zu viel fuer ein Ticket.
  filterSet := [lsError, lsWarning];
  jiraText := TExporter.BuildJiraText(FAll, src, filterSet);
  Clipboard.AsText := jiraText;
  FOnStatus(Format(
    _('Jira wiki markup for %s copied to clipboard (errors+warnings).'),
    [ExtractFileName(src)]));
end;

procedure TFindingExportMenu.DoCopyClipboard(Sender: TObject);
// Plain-Text der Fehler+Warnungen einer Datei in die Zwischenablage.
var
  src  : string;
  text : string;
begin
  src := CurrentFocusFile;
  if src = '' then
  begin
    FOnStatus(_('Clipboard: please select a row first (file not unambiguous).'));
    Exit;
  end;
  text := TExporter.BuildClipboardText(FAll, src, [lsError, lsWarning]);
  Clipboard.AsText := text;
  FOnStatus(Format(
    _('Errors+warnings for %s copied to clipboard.'),
    [ExtractFileName(src)]));
end;

procedure TFindingExportMenu.DoExportSonarGeneric(Sender: TObject);
// Schreibt einen Generic-Issue-Report mit ALLEN sichtbaren Findings.
// User waehlt das Output-File - default sca-findings.json.
var
  Dlg     : TSaveDialog;
  BaseDir : string;
  Written : string;
begin
  if Assigned(FGetBaseDir) then BaseDir := FGetBaseDir() else BaseDir := '';
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter     := 'Sonar Generic Issue Format (*.json)|*.json';
    Dlg.DefaultExt := 'json';
    Dlg.FileName   := 'sca-findings.json';
    if BaseDir <> '' then Dlg.InitialDir := BaseDir;
    Dlg.Options    := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    try
      var Bulk := TObjectList<TLeakFinding>.Create(False);
      try
        for var Fnd in FDisplayed do Bulk.Add(Fnd);
        Written := TSonarPush.WriteBulk(Bulk, BaseDir, Dlg.FileName);
      finally
        Bulk.Free;
      end;
      FOnStatus(Format(_('Sonar report saved: %s'),
        [ExtractFileName(Written)]));
    except
      on E: Exception do
        FOnStatus(_('Sonar export failed: ') + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFindingExportMenu.DoExportSonarSingleIssue(Sender: TObject);
// Schreibt das aktuell markierte Finding (oder die markierten Findings bei
// Multi-Select) als einzelne JSON-Files in <baseDir>\.sonar\external\.
// Sonar-Scanner sammelt die automatisch via
//   sonar.externalIssuesReportPaths=.sonar/external/
var
  BaseDir  : string;
  Grid     : TStringGrid;
  Sel      : TArray<TLeakFinding>;
  Row, Idx : Integer;
  Cnt      : Integer;
begin
  if Assigned(FGetBaseDir) then BaseDir := FGetBaseDir() else BaseDir := '';
  if BaseDir = '' then
  begin
    FOnStatus(_('Sonar push needs a project directory (run analysis first).'));
    Exit;
  end;
  Grid := FGetGrid;
  if (Grid = nil) or (Grid.RowCount <= 1) then Exit;

  // Multi-Selection: alle markierten Zeilen sammeln. Fallback: Grid.Row.
  SetLength(Sel, 0);
  if (goRangeSelect in Grid.Options) and (Grid.Selection.Top > 0) then
  begin
    for Row := Grid.Selection.Top to Grid.Selection.Bottom do
    begin
      Idx := Row - 1;  // Header-Zeile abziehen
      if (Idx >= 0) and (Idx < FDisplayed.Count) then
      begin
        SetLength(Sel, Length(Sel) + 1);
        Sel[High(Sel)] := FDisplayed[Idx];
      end;
    end;
  end
  else
  begin
    Idx := Grid.Row - 1;
    if (Idx >= 0) and (Idx < FDisplayed.Count) then
    begin
      SetLength(Sel, 1);
      Sel[0] := FDisplayed[Idx];
    end;
  end;

  if Length(Sel) = 0 then
  begin
    FOnStatus(_('Sonar push: select at least one finding first.'));
    Exit;
  end;

  try
    Cnt := TSonarPush.WriteIndividual(Sel, BaseDir, BaseDir);
    FOnStatus(Format(_('Sonar push: wrote %d issue file(s) to .sonar\external\'),
      [Cnt]));
  except
    on E: Exception do
      FOnStatus(_('Sonar push failed: ') + E.Message);
  end;
end;

procedure TFindingExportMenu.DoExportHtml(Sender: TObject);
// HTML-Report enthaelt IMMER alle Befunde - sortiert und gefiltert wird
// im erzeugten HTML clientseitig per JS (Header-Klick, Severity-Badge,
// Datei-Dropdown).
var
  Dlg     : TSaveDialog;
  defName : string;
  baseDir : string;
begin
  if Assigned(FGetBaseDir) then
    baseDir := FGetBaseDir()
  else
    baseDir := '';
  defName := TExporter.DefaultHtmlFileName('', baseDir);

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter      := _('HTML file (*.html)|*.html');
    Dlg.DefaultExt  := 'html';
    Dlg.FileName    := ExtractFileName(defName);
    if baseDir <> '' then
      Dlg.InitialDir := baseDir;
    Dlg.Options     := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;

    try
      // SourceFile = '' -> alle Befunde im Report
      TExporter.ExportHtml(FAll, '', Dlg.FileName);
      FOnStatus(Format(_('HTML report saved: %s'),
        [ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do
        FOnStatus(_('HTML export failed: ') + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

end.
