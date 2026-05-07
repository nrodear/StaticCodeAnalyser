unit uIDEMessages;

// Sendet Befunde an die "Messages"-Toolbar der Delphi-IDE.
//
// Verhalten:
//   * Pro Befund eine Zeile in der Messages-Toolbar (Tool-Message).
//   * Doppelklick im Messages-Pane springt zur Datei + Zeile (das macht
//     die IDE selbst, sobald wir Datei + Zeilennummer mitgeben).
//   * Severity wird als Prefix-String mitgegeben ("Error", "Warning",
//     "Hint") - zeigt sich in der Anzeige vor der Datei. Strings via
//     _() lokalisiert (dxgettext / SetLanguage).
//   * Pro Lauf wird ein Title-Message-Trenner mit Zeitstempel gesetzt
//     ("=== Static Code Analysis (hh:mm:ss) ==="). Vorherige Befunde
//     bleiben oberhalb des neuen Trenners stehen - so kann man auch
//     vorherige Laeufe vergleichen.
//
// Vorteil gegenueber Custom-Line-Highlighting:
//   * Kein View-Notifier-Lifecycle (kein AV beim Projekt-Schliessen)
//   * Native IDE-UI, vom User gewohnt von Compiler-Errors
//   * Persistent: bleibt auch nach Editor-Wechsel sichtbar
//
// Hinweis: Die ToolsAPI in Delphi 12 hat keine 8-Argument-Variante von
// AddToolMessage mit Group-Parameter. Wir nutzen die 5-Argument-Variante
// + AddTitleMessage fuer den Trenner - das ist die portable Loesung.

interface

uses
  System.Generics.Collections,
  uMethodd12, uSCAConsts;

type
  TIDEMessages = class
  public
    // Befunde an die Messages-Toolbar senden. Akzeptiert TList als Basis -
    // TObjectList<T> erbt von TList<T>, somit kompatibel zu beiden Typen.
    class procedure ReportFindings(Findings: TList<TLeakFinding>); static;
  end;

implementation

uses
  System.SysUtils, ToolsAPI,
  uLocalization;  // _() Macro - sonst englische Default-Strings

function SeverityPrefix(S: TLeakSeverity): string;
begin
  // Strings durch _() leiten, damit sie ueber dxgettext / die zentrale
  // SetLanguage-Settings lokalisierbar sind. Ohne dxgettext bleibt es bei
  // der englischen Source-Form.
  case S of
    lsError   : Result := _('Error');
    lsWarning : Result := _('Warning');
    lsHint    : Result := _('Hint');
  else
    Result := _('Info');
  end;
end;

class procedure TIDEMessages.ReportFindings(Findings: TList<TLeakFinding>);
var
  MsgServices : IOTAMessageServices;
  F           : TLeakFinding;
  Line        : Integer;
  MsgText     : string;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, MsgServices) then Exit;
  if Findings = nil then Exit;

  // Vor jedem Scan komplett leeren - auch Compiler-Output verschwindet.
  // Ist beim Start einer Analyse das gewuenschte Verhalten: frischer Reset
  // damit nur die aktuellen Befunde sichtbar sind.
  MsgServices.ClearAllMessages;

  // Header mit Zeitstempel als visueller Trenner.
  MsgServices.AddTitleMessage(Format('=== Static Code Analysis (%s) ===',
    [FormatDateTime('hh:nn:ss', Now)]));

  for F in Findings do
  begin
    Line := StrToIntDef(F.LineNumber, 0);
    if Line <= 0 then Line := 1;

    MsgText := F.MissingVar;
    if F.MethodName <> '' then
      MsgText := F.MethodName + ': ' + MsgText;

    // 5-Argument-Variante: FileName, MsgText, PrefixStr, Line, Column.
    // Klick im Messages-Pane springt durch die IDE zur Datei + Zeile.
    MsgServices.AddToolMessage(F.FileName, MsgText, SeverityPrefix(F.Severity),
      Line, 1);
  end;
end;

end.
