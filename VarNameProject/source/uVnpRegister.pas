unit uVnpRegister;

// VarNameProject - Einstieg des IDE-Pakets: ein Untermenue
// Tools > VarNameProject mit je einem Eintrag pro Variante (uVnpIntroduce),
// "Letzte Variante wiederholen" (Strg+Alt+Umschalt+M) und dem Protokoll.
// Die Aktionen haengen in der ActionList der IDE (sonst gilt das
// Tastenkuerzel nicht - Erfahrung aus uIDEExpert); die finalization raeumt
// Menue und Aktionen wieder ab.

interface

procedure Register;

implementation

// Die Menuetexte sind deutsch - das Testprojekt hat keine Uebersetzung.
// noinspection-file HardcodedString

uses
  System.SysUtils, System.Classes, Vcl.Menus, Vcl.ActnList, ToolsAPI,
  uVnpIntroduce, uVnpProbe, uVnpLog;

const
  MENU_NAME   = 'VarNameProjectMenu';
  CATEGORY    = 'VarNameProject';
  TAG_REPEAT  = 100;
  TAG_SHOWLOG = 101;
  TAG_OPENLOG = 102;
  TAG_CLEAR   = 103;
  TAG_PROBE_CARET = 104;
  TAG_PROBE_CLASS = 105;

type
  TVnpMenuHandler = class
  private
    FLast : TVnpVariant;
  public
    procedure Run(Sender: TObject);
  end;

var
  GHandler : TVnpMenuHandler = nil;
  GRoot    : TMenuItem = nil;
  GActions : TList = nil;

procedure OpenLogInEditor;
var
  Svc : IOTAActionServices;
begin
  if Supports(BorlandIDEServices, IOTAActionServices, Svc) then
    Svc.OpenFile(VnpLogFile);
end;

procedure TVnpMenuHandler.Run(Sender: TObject);
var
  Tag : Integer;
begin
  Tag := (Sender as TComponent).Tag;
  case Tag of
    TAG_REPEAT:
      RunIntroduce(FLast);
    TAG_SHOWLOG:
      VnpShowLog;
    TAG_OPENLOG:
      OpenLogInEditor;
    TAG_CLEAR:
      VnpClearLog;
    TAG_PROBE_CARET:
      ProbeCaret;
    TAG_PROBE_CLASS:
      ProbeCreateClass;
  else
    FLast := TVnpVariant(Tag);
    RunIntroduce(FLast);
  end;
end;

function FindToolsMenu(AMain: TMainMenu): TMenuItem;
var
  i : Integer;
begin
  Result := nil;
  if AMain = nil then Exit;
  for i := 0 to AMain.Items.Count - 1 do
    if SameText(AMain.Items[i].Name, 'ToolsMenu') then
      Exit(AMain.Items[i]);
end;

procedure AddItem(const ANTA: INTAServices; const ACaption: string;
  ATag: Integer; AShortCut: TShortCut);
var
  Act  : TAction;
  Item : TMenuItem;
begin
  Act := TAction.Create(nil);
  Act.ActionList := ANTA.ActionList;
  Act.Category := CATEGORY;
  Act.Caption := ACaption;
  Act.Tag := ATag;
  Act.ShortCut := AShortCut;
  Act.OnExecute := GHandler.Run;
  GActions.Add(Act);
  Item := TMenuItem.Create(GRoot);
  Item.Action := Act;
  GRoot.Add(Item);
end;

procedure AddSeparator;
var
  Item : TMenuItem;
begin
  Item := TMenuItem.Create(GRoot);
  Item.Caption := '-';
  GRoot.Add(Item);
end;

procedure Register;
var
  NTA   : INTAServices;
  Tools : TMenuItem;
  V     : TVnpVariant;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTA) then Exit;
  Tools := FindToolsMenu(NTA.MainMenu);
  if Tools = nil then
  begin
    VnpLog('VarNameProject: Menue "ToolsMenu" nicht gefunden - kein Eintrag');
    Exit;
  end;
  GHandler := TVnpMenuHandler.Create;
  GActions := TList.Create;
  GRoot := TMenuItem.Create(NTA.MainMenu);
  GRoot.Name := MENU_NAME;
  GRoot.Caption := 'VarNameProject';
  Tools.Add(GRoot);
  AddItem(NTA, 'Letzte Variante wiederholen (Start: A1)', TAG_REPEAT,
    ShortCut(Ord('M'), [ssCtrl, ssAlt, ssShift]));
  AddSeparator;
  for V := Low(TVnpVariant) to High(TVnpVariant) do
    AddItem(NTA, VARIANT_CAPTIONS[V], Ord(V), 0);
  AddSeparator;
  AddItem(NTA, 'Sonde: CharIndex am Caret (M10)', TAG_PROBE_CARET, 0);
  AddItem(NTA, 'Sonde: CreateClass (M21)', TAG_PROBE_CLASS, 0);
  AddSeparator;
  AddItem(NTA, 'Protokoll in der Meldungsansicht', TAG_SHOWLOG, 0);
  AddItem(NTA, 'Protokolldatei im Editor oeffnen', TAG_OPENLOG, 0);
  AddItem(NTA, 'Protokoll leeren', TAG_CLEAR, 0);
  VnpLog('VarNameProject geladen - Protokoll: %s', [VnpLogFile]);
end;

procedure Unregister;
var
  i : Integer;
begin
  // Erst das Menue (die Eintraege zeigen auf die Aktionen), dann die
  // Aktionen, zuletzt der Handler, auf den ihr OnExecute zeigt.
  FreeAndNil(GRoot);
  if GActions <> nil then
    for i := GActions.Count - 1 downto 0 do
      TObject(GActions[i]).Free;
  FreeAndNil(GActions);
  FreeAndNil(GHandler);
end;

initialization

finalization
  Unregister;

end.
