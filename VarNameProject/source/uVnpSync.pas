unit uVnpSync;

// VarNameProject - was rund um die Sync-Edit-Sitzungen der IDE gebraucht
// wird, ohne der Ablauf selbst zu sein (der steht in uVnpIntroduce): der
// Prozess-Merker nach einer Zugriffsverletzung und die Sonde N1.
//
// Was die Laeufe 1-6 (2026-10-11) ueber die Sync-API gezeigt haben:
//   * IOTACodeTemplateServices.CreateClass liefert fuer die Sync-Punkt-
//     Interfaces nil (Sonde M21). Eigene Punkt-Klassen starten zwar eine
//     Sitzung (SyncMode 2), aber die IDE liest ihre Offsets als UTF-8-BYTES
//     (Lauf 3: aus 'Count * MagicNr01' wurde 'CounMagicNr01Nr01'), und die
//     Objekte bleiben in Sitzung und Undo-Liste der IDE. Variante B1 ist
//     deshalb entfallen; den Template-Modus erreicht D1 mit IDE-eigenen
//     Objekten.
//   * Die Laeufe 1, 4 und 5 stuerzten in TSyncEditManager.SendSyncEvent
//     (Lesen von Adresse 0 direkt nach TInterfaceList.Get). Wahrscheinlichste
//     Erklaerung, NICHT bewiesen (H1): IOTAEditBlock.RemoveNotifier laesst
//     einen nil-Eintrag in der Notifier-Liste stehen, und SendSyncEvent
//     prueft nicht darauf - die Pakete e75bfeba..294336a3 meldeten Notifier
//     an und ab. Im frischen Prozess ohne Notifier lief C1 sechsmal stabil
//     (Lauf 6). Dieses Projekt meldet deshalb KEINEN IOTASyncEditNotifier
//     an - ausser der Sonde N1, die genau H1 prueft.

interface

// '' oder der Grund, warum dieser IDE-Prozess keine Sitzung mehr starten
// soll: gesetzt nach einer Zugriffsverletzung in einem Lauf. Der Merker ist
// eine Umgebungsvariable des Prozesses (VNP_SYNC_POISONED): er uebersteht
// das Neuinstallieren des Pakets und verschwindet mit dem Prozess - wie ein
// vergifteter Eintrag in der Notifier-Liste.
function VnpPoisonReason: string;
procedure VnpSetPoison(const AWhy: string);

// Sonde N1 (Gutachten 2026-10-11, Abschnitt 1), prueft H1: N1On meldet am
// Block der obersten Ansicht einen Notifier an, der jedes Ereignis NUR in
// die Datei schreibt; N1Off meldet ihn wieder ab. Stimmt H1, steht danach
// ein nil-Eintrag in der Liste, und die naechste Sync-Edit-Sitzung stuerzt
// ab - schon in einer anderen Datei: die Liste gilt fuer den ganzen
// Prozess; nur in derselben: je Ansicht; nirgends: H1 widerlegt.
// ZERSTOERT DEN PROZESS, wenn H1 stimmt - nur als letzter Test, danach die
// IDE beenden.
procedure N1On;
procedure N1Off;
// Abbau: einen noch angemeldeten N1-Notifier abmelden; idempotent, nur
// Datei-Protokoll.
procedure N1Release;

implementation

uses
  Winapi.Windows, System.SysUtils, ToolsAPI, uVnpLog;

const
  ENV_POISON = 'VNP_SYNC_POISONED';

type
  // Der Notifier der Sonde N1: schreibt nur die Datei, nie die
  // Meldungsansicht, und fasst die uebergebenen Objekte nicht an.
  TVnpN1Notifier = class(TInterfacedObject, IOTASyncEditNotifier)
  private
    procedure OnPoint(const APoint: IOTASyncEditPoint;
      const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
    procedure OnSyncEdit(const APoints: IOTASyncEditPoints;
      EventType: TOTASyncEditPointEventType);
  end;

var
  // Wo N1 haengt: Block der Ansicht, Index fuer RemoveNotifier, Datei.
  GN1Block : IOTAEditBlock = nil;
  GN1Index : Integer = -1;
  GN1File  : string = '';

function VnpPoisonReason: string;
begin
  Result := System.SysUtils.GetEnvironmentVariable(ENV_POISON);
end;

procedure VnpSetPoison(const AWhy: string);
begin
  Winapi.Windows.SetEnvironmentVariable(PChar(ENV_POISON),
    PChar(Format('%s (PID %d, %s)', [AWhy, GetCurrentProcessId,
    FormatDateTime('hh:nn:ss', Now, TFormatSettings.Invariant)])));
end;

{ TVnpN1Notifier }

// Name des Ereignisses; die Zahl steht immer dabei, falls die IDE einen
// Wert ausserhalb der Aufzaehlung liefert.
function EventName(AEvent: TOTASyncEditPointEventType): string;
begin
  case AEvent of
    sepEnter: Result := 'Enter';
    sepLeave: Result := 'Leave';
    sepExit:  Result := 'Exit';
  else
    Result := '?';
  end;
  Result := Format('%s (%d)', [Result, Ord(AEvent)]);
end;

procedure TVnpN1Notifier.OnPoint(const APoint: IOTASyncEditPoint;
  const APoints: IOTASyncEditPoints; EventType: TOTASyncEditPointEventType);
begin
  VnpLogFileOnly('N1-Ereignis OnPoint %s, Punkt uebergeben: %s',
    [EventName(EventType), BoolToStr(APoint <> nil, True)]);
end;

procedure TVnpN1Notifier.OnSyncEdit(const APoints: IOTASyncEditPoints;
  EventType: TOTASyncEditPointEventType);
begin
  VnpLogFileOnly('N1-Ereignis OnSyncEdit %s, Punkte uebergeben: %s',
    [EventName(EventType), BoolToStr(APoints <> nil, True)]);
end;

{ N1 }

// Die oberste Editoransicht oder nil.
function TopView: IOTAEditView;
var
  Svc : IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Svc) then
    Result := Svc.TopView;
  if (Result <> nil) and (Result.Buffer = nil) then
    Result := nil;
end;

procedure N1On;
var
  View : IOTAEditView;
  N    : IOTASyncEditNotifier;
begin
  VnpLog('=== N1 an: Dummy-Notifier (Test fuer H1, nur als letzter Test) ===');
  if GN1Block <> nil then
  begin
    VnpLog('Abbruch: N1 haengt schon (Index %d an %s)', [GN1Index, GN1File]);
    Exit;
  end;
  if VnpPoisonReason <> '' then
  begin
    VnpLog('Abbruch: dieser Prozess hatte schon eine Zugriffsverletzung '
      + '(%s) - N1 nur in einer frisch gestarteten IDE', [VnpPoisonReason]);
    Exit;
  end;
  View := TopView;
  if View = nil then
  begin
    VnpLog('Abbruch: keine Editoransicht');
    Exit;
  end;
  if View.Block.SyncMode <> smNone then
  begin
    // Nicht "mit Esc beenden": Esc zerstoert im Sync Edit der IDE Text
    // (UI-Test 2026-10-11); die Sitzung endet mit dem Knopf im Rand.
    VnpLog('Abbruch: Sync-Sitzung laeuft - erst beenden (Knopf im Rand; '
      + 'nicht Esc, das zerstoert Text)');
    Exit;
  end;
  // Erst in eine Interface-Variable: ein frisch erzeugtes Objekt direkt
  // als const-Parameter haette waehrend des Aufrufs Referenzzaehler 0.
  N := TVnpN1Notifier.Create;
  GN1Block := View.Block;
  GN1File := View.Buffer.FileName;
  GN1Index := GN1Block.AddNotifier(N);
  VnpLog('N1 angemeldet: Index %d am Block von %s', [GN1Index, GN1File]);
  VnpLog('Weiter: Zeilen markieren, Strg+Umschalt+J, die Sitzung mit dem '
    + 'Knopf im Rand beenden (nicht Esc: zerstoert Text) - die Ereignisse '
    + 'stehen nur in der Protokolldatei; danach "N1 ab"');
end;

procedure N1Off;
var
  View : IOTAEditView;
begin
  VnpLog('=== N1 ab ===');
  if GN1Block = nil then
  begin
    VnpLog('Abbruch: N1 ist nicht angemeldet');
    Exit;
  end;
  View := TopView;
  if (View = nil) or not SameFileName(View.Buffer.FileName, GN1File) then
  begin
    VnpLog('Abbruch: erst wieder %s nach vorn holen - N1 haengt an deren '
      + 'Block', [GN1File]);
    Exit;
  end;
  GN1Block.RemoveNotifier(GN1Index);
  VnpLog('N1 abgemeldet (Index %d). Stimmt H1, steht dort jetzt ein '
    + 'nil-Eintrag.', [GN1Index]);
  VnpLog('Weiter: in VarNameDemoUmlaut.pas die Funktion Greeting markieren, '
    + '2 s warten, Strg+Umschalt+J. Ohne Absturz danach in %s die Zeilen '
    + '17-21 markieren, Strg+Umschalt+J.', [ExtractFileName(GN1File)]);
  GN1Block := nil;
  GN1Index := -1;
  GN1File := '';
end;

procedure N1Release;
begin
  if GN1Block = nil then
    Exit;
  VnpLogFileOnly('  N1 haengt noch (Index %d an %s) - abmelden',
    [GN1Index, GN1File]);
  try
    GN1Block.RemoveNotifier(GN1Index);
    GN1Block := nil;
  except
    // Den Block kann es beim Schliessen der IDE nicht mehr geben: dann die
    // Referenz OHNE _Release fallen lassen.
    // noinspection ExceptionTooGeneral
    on E: Exception do
    begin
      Pointer(GN1Block) := nil;
      VnpLogFileOnly('  N1 abmelden: %s: %s', [E.ClassName, E.Message]);
    end;
  end;
  GN1Index := -1;
  GN1File := '';
end;

end.
