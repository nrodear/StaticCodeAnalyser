unit uIDEFindingNav;

// IOTAKeyboardBinding fuer Ctrl+Alt+Down / Ctrl+Alt+Up: Springt im aktuellen
// Editor-Tab zur naechsten / vorherigen markierten Finding-Zeile.
//
// Quelle der Marken: GHighlighter.GetSortedLinesForFile(<aktuelles File>).
// Wenn die Datei keine Marken hat, geben wir den Key UNHANDLED zurueck -
// dann landet der Shortcut beim Default-Editor (oder einer anderen Bindung).
//
// Wrap-around: Down hinter der letzten Marke -> erste; Up vor der ersten ->
// letzte. Der Cursor wird zentriert (TIDEEditor.CenterCurrentViewOnLine),
// damit die Zielzeile garantiert sichtbar ist auch wenn sie vorher
// ausserhalb des Viewports lag.
//
// Singleton mit Self-Init: RegisterFindingNavBinding ist idempotent und
// wird aus RegisterAnalyserDockableForm gerufen; Unregister tut das
// Spiegelbild beim BPL-Unload.

interface

procedure RegisterFindingNavBinding;
procedure UnregisterFindingNavBinding;

implementation

// noinspection-file DebugOutput, EmptyExcept, ExceptionTooGeneral, ExceptOnException, MultipleExit
// IDE-Hotkey-Plugin: empty-except an OTAPI-API-Calls. ShowMessage-Usage als
// User-Feedback fuer Navigation-Aktionen (kein Production-Debug).

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Menus,
  ToolsAPI,
  uRepoSettings,
  uIDELineHighlighter, uIDEEditorIntegration;

function IsFindingNavEnabled: Boolean;
// Liest [Hotkeys] FindingNavEnabled UND ShortcutsEnabled aus analyser.ini
// bei jedem Tastendruck - beide muessen True sein damit die Hotkey
// feuert. ShortcutsEnabled ist der Master-Toggle ueber alle Shortcuts,
// FindingNavEnabled der Per-Feature-Toggle. Default beide True.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    Result := Settings.ShortcutsEnabled and Settings.FindingNavEnabled;
  finally
    Settings.Free;
  end;
end;

type
  TSCAFindingNavBinding = class(TNotifierObject, IOTAKeyboardBinding)
  protected
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
  private
    procedure NextFindingKeyProc(const Context: IOTAKeyContext;
      KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
    procedure PrevFindingKeyProc(const Context: IOTAKeyContext;
      KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
    // Liefert (CurrentLine, FileName) des Top-Views oder False wenn nichts offen.
    function TryGetCurrentEditorState(out AFile: string;
                                      out ACurLine: Integer): Boolean;
    // Findet die Zielzeile (wrap-around). Rueckgabe False heisst "keine
    // Marken in der Datei" -> Hotkey unhandled lassen.
    function FindTargetLine(const ASortedLines: TArray<Integer>;
                            ACurLine: Integer; AForward: Boolean;
                            out ATarget: Integer): Boolean;
  end;

var
  GNavBinding    : TSCAFindingNavBinding = nil;
  GNavBindingIfc : IOTAKeyboardBinding = nil;
  GNavBindingIdx : Integer = -1;

{ TSCAFindingNavBinding }

procedure TSCAFindingNavBinding.BindKeyboard(
  const BindingServices: IOTAKeyBindingServices);
// Zwei Bindings, beide konfigurierbar via analyser.ini [Hotkeys]
// FindingNavUpShortcut / FindingNavDownShortcut. Defaults Ctrl+Alt+Up
// und Ctrl+Alt+Down. Aenderung erfordert IDE-Neustart.
var
  Settings : TRepoSettings;
  ScUp, ScDown : TShortCut;
begin
  ScUp   := ShortCut(VK_UP,   [ssCtrl, ssAlt]);
  ScDown := ShortCut(VK_DOWN, [ssCtrl, ssAlt]);
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    if Trim(Settings.FindingNavUpShortcut) <> '' then
    begin
      var P := TextToShortCut(Settings.FindingNavUpShortcut);
      if P <> 0 then ScUp := P;
    end;
    if Trim(Settings.FindingNavDownShortcut) <> '' then
    begin
      var P := TextToShortCut(Settings.FindingNavDownShortcut);
      if P <> 0 then ScDown := P;
    end;
  finally
    Settings.Free;
  end;
  BindingServices.AddKeyBinding([ScDown], NextFindingKeyProc, nil);
  BindingServices.AddKeyBinding([ScUp],   PrevFindingKeyProc, nil);
end;

function TSCAFindingNavBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TSCAFindingNavBinding.GetDisplayName: string;
begin
  Result := 'Static Code Analyser: Finding Navigation';
end;

function TSCAFindingNavBinding.GetName: string;
begin
  Result := 'SCA.FindingNavigationBinding';
end;

function TSCAFindingNavBinding.TryGetCurrentEditorState(out AFile: string;
  out ACurLine: Integer): Boolean;
var
  EdSvc    : IOTAEditorServices;
  EditView : IOTAEditView;
begin
  AFile    := '';
  ACurLine := 0;
  Result   := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EdSvc) then Exit;
  EditView := EdSvc.TopView;
  if not Assigned(EditView) or not Assigned(EditView.Buffer) then Exit;
  AFile    := EditView.Buffer.FileName;
  ACurLine := EditView.CursorPos.Line;
  Result   := AFile <> '';
end;

function TSCAFindingNavBinding.FindTargetLine(
  const ASortedLines: TArray<Integer>; ACurLine: Integer; AForward: Boolean;
  out ATarget: Integer): Boolean;
var
  i, N : Integer;
begin
  ATarget := 0;
  N := Length(ASortedLines);
  if N = 0 then Exit(False);

  if AForward then
  begin
    // Erste Marke strikt > CurLine; sonst wrap-around zur ersten.
    for i := 0 to N - 1 do
      if ASortedLines[i] > ACurLine then
      begin
        ATarget := ASortedLines[i];
        Exit(True);
      end;
    ATarget := ASortedLines[0];
  end
  else
  begin
    // Letzte Marke strikt < CurLine; sonst wrap-around zur letzten.
    for i := N - 1 downto 0 do
      if ASortedLines[i] < ACurLine then
      begin
        ATarget := ASortedLines[i];
        Exit(True);
      end;
    ATarget := ASortedLines[N - 1];
  end;
  Result := True;
end;

procedure TSCAFindingNavBinding.NextFindingKeyProc(
  const Context: IOTAKeyContext; KeyCode: TShortcut;
  var BindingResult: TKeyBindingResult);
var
  CurFile  : string;
  CurLine  : Integer;
  Lines    : TArray<Integer>;
  Target   : Integer;
begin
  BindingResult := krUnhandled;
  if not IsFindingNavEnabled then Exit;
  if not Assigned(GHighlighter) then Exit;
  if not TryGetCurrentEditorState(CurFile, CurLine) then Exit;
  Lines := GHighlighter.GetSortedLinesForFile(CurFile);
  if Length(Lines) = 0 then Exit;
  if not FindTargetLine(Lines, CurLine, True, Target) then Exit;
  TIDEEditor.CenterCurrentViewOnLine(Target);
  BindingResult := krHandled;
end;

procedure TSCAFindingNavBinding.PrevFindingKeyProc(
  const Context: IOTAKeyContext; KeyCode: TShortcut;
  var BindingResult: TKeyBindingResult);
var
  CurFile  : string;
  CurLine  : Integer;
  Lines    : TArray<Integer>;
  Target   : Integer;
begin
  BindingResult := krUnhandled;
  if not IsFindingNavEnabled then Exit;
  if not Assigned(GHighlighter) then Exit;
  if not TryGetCurrentEditorState(CurFile, CurLine) then Exit;
  Lines := GHighlighter.GetSortedLinesForFile(CurFile);
  if Length(Lines) = 0 then Exit;
  if not FindTargetLine(Lines, CurLine, False, Target) then Exit;
  TIDEEditor.CenterCurrentViewOnLine(Target);
  BindingResult := krHandled;
end;

{ Register / Unregister }

procedure RegisterFindingNavBinding;
var
  KBSvc : IOTAKeyboardServices;
begin
  if Assigned(GNavBinding) then Exit;
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, KBSvc) then
  begin
    OutputDebugString('SCA: IOTAKeyboardServices not available - finding-nav hotkeys disabled');
    Exit;
  end;
  GNavBinding    := TSCAFindingNavBinding.Create;
  GNavBindingIfc := GNavBinding as IOTAKeyboardBinding;
  try
    GNavBindingIdx := KBSvc.AddKeyboardBinding(GNavBindingIfc);
    if GNavBindingIdx < 0 then
      OutputDebugString('SCA: AddKeyboardBinding (FindingNav) returned negative index - hotkeys may conflict');
  except
    on E: Exception do
    begin
      OutputDebugString(PChar(Format(
        'SCA: AddKeyboardBinding (FindingNav) failed: %s: %s',
        [E.ClassName, E.Message])));
      GNavBindingIfc := nil;
      GNavBinding    := nil;
      GNavBindingIdx := -1;
    end;
  end;
end;

procedure UnregisterFindingNavBinding;
var
  KBSvc : IOTAKeyboardServices;
begin
  if GNavBindingIdx >= 0 then
  begin
    try
      if Supports(BorlandIDEServices, IOTAKeyboardServices, KBSvc) then
        KBSvc.RemoveKeyboardBinding(GNavBindingIdx);
    except
    end;
    GNavBindingIdx := -1;
  end;
  GNavBindingIfc := nil;
  GNavBinding    := nil;
end;

end.
