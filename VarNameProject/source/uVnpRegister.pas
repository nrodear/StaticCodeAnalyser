unit uVnpRegister;

// VarNameProject - Einstieg des IDE-Pakets: ein Untermenue Tools >
// VarNameProject mit den Varianten (uVnpIntroduce), "Letzte Variante
// wiederholen" (Strg+Alt+Umschalt+M), den Sonden ("Sitzung jetzt":
// Strg+Alt+Umschalt+O), N1 und dem Protokoll. Die Aktionen haengen in der
// ActionList der IDE (sonst gilt das Tastenkuerzel nicht - Erfahrung aus
// uIDEExpert).
//
// ABBAU IM WIZARD-DESTRUKTOR (Gutachten 2026-10-11, H7): jeder IDE-Prozess,
// in dem VarNameProject lief, endete beim Schliessen mit einer AV in
// rtl290 - vermutlich, weil die finalization Menue und Aktionen freigab,
// die MainMenu und ActionList der IDE da schon selbst freigegeben hatten.
// Den per RegisterPackageWizard angemeldeten Wizard gibt die IDE frei,
// solange sie noch lebt (so baut auch SCA ab, uIDEExpert). Menue-Wurzel
// und Aktionen stehen ausserdem in einer TComponentList: gibt die IDE eines
// davon vorher frei, nimmt die Liste es per FreeNotification heraus - kein
// Objekt wird zweimal freigegeben. Die finalization ist nur das Netz, falls
// der Destruktor nie lief; jeder Abbauschritt steht in der Protokolldatei.

interface

procedure Register;

implementation

// Die Menuetexte sind deutsch - das Testprojekt hat keine Uebersetzung.
// noinspection-file HardcodedString

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes,
  System.Contnrs, Vcl.Menus, Vcl.ActnList, ToolsAPI, uVnpIntroduce,
  uVnpProbe, uVnpSync, uVnpLog;

const
  MENU_NAME         = 'VarNameProjectMenu';
  CATEGORY          = 'VarNameProject';
  WIZARD_ID         = 'NG.VarNameProject';
  TAG_REPEAT        = 100;
  TAG_SHOWLOG       = 101;
  TAG_OPENLOG       = 102;
  TAG_CLEAR         = 103;
  TAG_PROBE_CARET   = 104;
  TAG_PROBE_CLASS   = 105;
  TAG_PROBE_SESSION = 106;
  TAG_N1_ON         = 107;
  TAG_N1_OFF        = 108;

type
  TVnpMenuHandler = class
  private
    FLast : TVnpVariant;
  public
    procedure Run(Sender: TObject);
  end;

  // Nur fuer den Abbau: die IDE gibt den Wizard frei, solange sie lebt.
  TVnpWizard = class(TNotifierObject, IOTAWizard)
  public
    destructor Destroy; override;
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

  TVnpStep = procedure;

var
  GHandler  : TVnpMenuHandler = nil;
  GRoot     : TMenuItem = nil;
  // Menue-Wurzel und Aktionen. Gibt die IDE eines davon frei, nimmt die
  // Liste es selbst heraus (FreeNotification).
  GOwned    : TComponentList = nil;
  GTornDown : Boolean = False;

// Die Protokolldatei AUSSERHALB der IDE oeffnen (Standardprogramm fuer
// .log): im IDE-Editor waere sie die oberste Ansicht - die Sonde laese die
// falsche Datei -, und beim Weiterschreiben fragte die IDE nach dem
// Neuladen, ein Fokuswechsel mitten in der Sitzung (Review 2026-10-11,
// Befund 8).
procedure OpenLogOutside;
var
  Code : HINST;
begin
  Code := ShellExecute(0, 'open', PChar(VnpLogFile), nil, nil,
    SW_SHOWNORMAL);
  if Code <= 32 then
    VnpLog('Protokolldatei nicht geoeffnet (ShellExecute %d) - %s',
      [Code, VnpLogFile]);
end;

procedure TVnpMenuHandler.Run(Sender: TObject);
var
  Tag : Integer;
begin
  Tag := (Sender as TComponent).Tag;
  try
    case Tag of
      TAG_REPEAT:
        RunIntroduce(FLast);
      TAG_SHOWLOG:
        VnpShowLog;
      TAG_OPENLOG:
        OpenLogOutside;
      TAG_CLEAR:
        VnpClearLog;
      TAG_PROBE_CARET:
        ProbeCaret;
      TAG_PROBE_CLASS:
        ProbeCreateClass;
      TAG_PROBE_SESSION:
        ProbeSession;
      TAG_N1_ON:
        N1On;
      TAG_N1_OFF:
        N1Off;
    else
      FLast := TVnpVariant(Tag);
      RunIntroduce(FLast);
    end;
  except
    on EAbort do
      raise;
    // Nach einer Zugriffsverletzung nur die Datei (uVnpIntroduce.
    // AfterExternal); der Merker sperrt weitere Laeufe in diesem Prozess.
    on E: EExternal do
    begin
      VnpSetPoison(Format('%s im Menuepunkt %d: %s', [E.ClassName, Tag,
        E.Message]));
      VnpLogFileOnly('FEHLER %s im Menuepunkt %d: %s - Dateien sichern, IDE '
        + 'beenden', [E.ClassName, Tag, E.Message]);
    end;
    // Ein IDE-Plugin darf aus einem Menueklick keine Ausnahme in die IDE
    // werfen; jeder Fehler gehoert ins Protokoll (Messung).
    // noinspection ExceptionTooGeneral
    on E: Exception do
      VnpLog('FEHLER %s im Menuepunkt %d: %s', [E.ClassName, Tag, E.Message]);
  end;
end;

{ Abbau }

// Ein Abbauschritt: Anfang und Ende in die Datei; eine Ausnahme bricht nur
// diesen Schritt ab, nie den Abbau.
procedure RunStep(const AName: string; AStep: TVnpStep);
begin
  VnpLogFileOnly('  %s ...', [AName]);
  try
    AStep;
    VnpLogFileOnly('  %s: fertig', [AName]);
  except
    // Der Abbau darf nie eine Ausnahme in die IDE werfen.
    // noinspection ExceptionTooGeneral
    on E: Exception do
      VnpLogFileOnly('  %s: FEHLER %s: %s', [AName, E.ClassName, E.Message]);
  end;
end;

// Die Menue-Wurzel samt Eintraegen - nur, wenn die IDE sie nicht schon
// freigegeben hat (dann steht sie nicht mehr in GOwned).
procedure FreeMenu;
begin
  if (GRoot <> nil) and (GOwned <> nil) and (GOwned.IndexOf(GRoot) >= 0) then
    GRoot.Free
  else if GRoot <> nil then
    VnpLogFileOnly('  (die IDE hatte das Menue schon freigegeben)');
  GRoot := nil;
end;

// Die Aktionen, soweit noch da - die Liste besitzt sie.
procedure FreeActions;
begin
  if GOwned <> nil then
    VnpLogFileOnly('  noch %d Aktion(en) in der Liste', [GOwned.Count]);
  FreeAndNil(GOwned);
end;

procedure FreeHandler;
begin
  FreeAndNil(GHandler);
end;

// Idempotent: der zweite Aufruf (finalization nach dem Wizard-Destruktor)
// meldet nur, dass schon abgebaut ist.
procedure Teardown(const AWhere: string);
begin
  if GTornDown then
  begin
    VnpLogFileOnly('Abbau (%s): schon erledigt', [AWhere]);
    Exit;
  end;
  GTornDown := True;
  VnpLogFileOnly('Abbau (%s): Anfang', [AWhere]);
  RunStep('N1 abmelden', N1Release);
  RunStep('Template entfernen', ReleaseTemplate);
  RunStep('Menue freigeben', FreeMenu);
  RunStep('Aktionen freigeben', FreeActions);
  RunStep('Handler freigeben', FreeHandler);
  RunStep('Meldungsgruppe abmelden', VnpReleaseGroup);
  VnpLogFileOnly('Abbau (%s): Ende', [AWhere]);
end;

{ TVnpWizard }

destructor TVnpWizard.Destroy;
begin
  Teardown('Wizard-Destruktor');
  inherited Destroy;
end;

function TVnpWizard.GetIDString: string;
begin
  Result := WIZARD_ID;
end;

function TVnpWizard.GetName: string;
begin
  Result := 'VarNameProject';
end;

function TVnpWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TVnpWizard.Execute;
begin
  // Kein IOTAMenuWizard - die IDE ruft das nicht; nur zur Sicherheit.
  VnpLog('Wizard.Execute (ohne Funktion)');
end;

{ Menue }

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
  GOwned.Add(Act);
  Act.ActionList := ANTA.ActionList;
  Act.Category := CATEGORY;
  Act.Caption := ACaption;
  Act.Tag := ATag;
  Act.ShortCut := AShortCut;
  Act.OnExecute := GHandler.Run;
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
  VnpCountLoad;
  VnpLogHeader;
  if not Supports(BorlandIDEServices, INTAServices, NTA) then
  begin
    VnpLog('Abbruch: INTAServices fehlt - kein Menue');
    Exit;
  end;
  Tools := FindToolsMenu(NTA.MainMenu);
  if Tools = nil then
  begin
    VnpLog('Abbruch: Menue "ToolsMenu" nicht gefunden - kein Menue');
    Exit;
  end;
  GHandler := TVnpMenuHandler.Create;
  GOwned := TComponentList.Create(True);
  // Ohne Eigentuemer: freigeben duerfen sie nur der Abbau oder - als
  // Kind des Tools-Menues - die IDE; GOwned merkt beides.
  GRoot := TMenuItem.Create(nil);
  GOwned.Add(GRoot);
  GRoot.Name := MENU_NAME;
  GRoot.Caption := 'VarNameProject';
  Tools.Add(GRoot);
  AddItem(NTA, 'Letzte Variante wiederholen (Start: C1h)', TAG_REPEAT,
    ShortCut(Ord('M'), [ssCtrl, ssAlt, ssShift]));
  AddSeparator;
  for V := Low(TVnpVariant) to High(TVnpVariant) do
    AddItem(NTA, VARIANT_CAPTIONS[V], Ord(V), 0);
  AddSeparator;
  // Per Tastenkuerzel, damit kein Menueklick die Sitzung beendet. O statt
  // P: Strg+Alt+Umschalt+P ist in der Default-Belegung "Sync Prototypes",
  // und Tastenbindungen gehen Menuekuerzeln vor - die Sonde feuerte nie.
  AddItem(NTA, 'Sonde: Sitzung jetzt (nur Protokolldatei)',
    TAG_PROBE_SESSION, ShortCut(Ord('O'), [ssCtrl, ssAlt, ssShift]));
  AddItem(NTA, 'Sonde: CharIndex am Caret (M10)', TAG_PROBE_CARET, 0);
  AddItem(NTA, 'Sonde: CreateClass (M21)', TAG_PROBE_CLASS, 0);
  AddSeparator;
  AddItem(NTA, 'N1 an: Dummy-Notifier (Test fuer H1 - nur als letzter '
    + 'Test, zerstoert womoeglich den Prozess)', TAG_N1_ON, 0);
  AddItem(NTA, 'N1 ab', TAG_N1_OFF, 0);
  AddSeparator;
  AddItem(NTA, 'Protokoll in der Meldungsansicht', TAG_SHOWLOG, 0);
  AddItem(NTA, 'Protokolldatei ausserhalb der IDE oeffnen', TAG_OPENLOG, 0);
  AddItem(NTA, 'Protokoll leeren', TAG_CLEAR, 0);
  RegisterPackageWizard(TVnpWizard.Create);
  VnpLog('Menue steht, Wizard angemeldet - Abbau im Wizard-Destruktor');
end;

initialization

finalization
  // Netz: im Normalfall hat der Wizard-Destruktor laengst abgebaut, dann
  // steht hier nur "schon erledigt" in der Protokolldatei.
  Teardown('finalization');

end.
