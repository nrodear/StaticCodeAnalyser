unit uFindingActions;

// Erweiterungspunkt "Aktionen am Fund" (Konzept_SourceRefactor_Quellstellen
// 2026-10-02, Abschnitt 15 H1).
//
// WOZU
//
// Ein Host, der Funde anzeigt (das IDE-Plugin, die EXE), soll einem
// FREMDEN Package erlauben, am Fund Aktionen anzubieten - ohne dass der
// Host das Package kennt. Erster Konsument ist reDelphix: es haengt an
// SCA044-Funden "Format() aus Verkettung bilden" an, an SCA003 die
// parametrisierte Vorlage, dazu "Stelle zeigen". Der Host fragt beim
// Oeffnen des Kontextmenues nach und zeigt, was kommt.
//
// WARUM IN DER ENGINE UND NICHT IM PLUGIN
//
// reDelphix linkt gegen SCA.Engine, nicht gegen ein Plugin-Package. Der
// Treffpunkt muss also in der Engine liegen, damit Anbieter und Host
// dieselbe Registry sehen. Die Unit ist headless: Strings, ein Boolean
// und Methodenzeiger - kein VCL, kein ToolsAPI. Was eine Aktion TUT
// (Editor selektieren, Bereich ersetzen), lebt beim Anbieter.
//
// WARUM METHODENZEIGER UND KEINE ANONYMEN METHODEN
//
// Ein Anbieter ist ein Package mit Lebensdauer; seine Aktionen gehoeren
// zu einem Objekt, das beim Entladen verschwindet. Methodenzeiger
// ('of object') machen diese Bindung sichtbar; anonyme Methoden wuerden
// sie verstecken. Nebeneffekt: die Unit laesst sich im FPC-Pruefstand
// uebersetzen, der keine anonymen Methoden kennt.
//
// VERTRAG
//
//   * Ein Anbieter liefert zu einem Fund 0..n Aktionen. Enabled = False
//     heisst: anzeigen, aber ausgegraut - der Grund steht im Hint
//     ("Operand 'Name': Typ unbekannt"). Das ist Teil der Bedienung, kein
//     Fehlerfall.
//   * Execute laeuft im UI-Thread des Hosts, wenn der Benutzer klickt;
//     Sender ist der Host-Menuepunkt oder nil. Der Host faengt Exceptions
//     des Anbieters und zeigt sie an.
//   * Register liefert ein Token; der Anbieter meldet sich beim Entladen
//     mit Unregister ab (finalization seines Packages). Eine vergessene
//     Abmeldung hinterlaesst einen Anbieter, dessen Code nicht mehr
//     geladen ist - deshalb ist das Token Pflicht, nicht Komfort.
//   * Die Registry veraendert keinen Fund. Sie ist fuer Detektoren
//     unsichtbar und bewegt keine Fundzahl.
//   * Kind sagt, WAS eine Aktion ist: fakFix aendert den Code oder hilft
//     beim Aendern (Ersetzen, uses, Vorlage in die Zwischenablage),
//     fakNavigate fuehrt nur hin (Stelle zeigen). Die Gluehbirne im Editor
//     zeigt nur verfuegbare fakFix - der Benutzer steht dort schon an der
//     Stelle (Nico 2026-10-08); Kontextmenue und Dock-Grid zeigen alles.
//     Der Wert 0 ist fakFix: ein Anbieter, der Kind nicht setzt, bleibt
//     bei SetLength/Default(TFindingAction) eine Hilfe.
//   * fakSuppress unterdrueckt den Fund (`// noinspection`-Marker). Das
//     ist KEINE Hilfe: die Gluehbirne erscheint deswegen nicht, zeigt es
//     aber unter den Hilfen, wenn es zu dem Fund eine gibt (Nico
//     2026-10-08, Editorhilfen E1). Kontextmenue und Dock-Grid zeigen es
//     immer. Ein Menue setzt die Unterdrueck-Eintraege mit einem Trenner ab.
//   * Ein Host fragt fuer EIN Menue hoechstens MAX_FINDINGS_PER_MENU Funde
//     ab (uFindingActionMenu.BuildFindingMenuModel; der Rest erscheint als
//     Hinweiszeile). Ein Anbieter, der seine Aktionsobjekte haelt, muss die
//     Objekte von deutlich MEHR Abfragen am Leben halten: zwischen Aufbau
//     und Klick koennen weitere laufen (die Gluehbirne prueft im Hinter-
//     grund). reDelphix haelt 8 x MAX_FINDINGS_PER_MENU Chargen
//     (Review reDelphiX 2026-10-07, Blocker 2: bei 33 Funden auf einer
//     Zeile zeigten Menuepunkte auf freigegebene Objekte).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12;

const
  // Hoechstzahl der Funde, deren Aktionen EIN Menue erfragt (VERTRAG oben).
  MAX_FINDINGS_PER_MENU = 16;

type
  // Was eine Aktion ist (siehe VERTRAG oben). fakFix MUSS Ordnungszahl 0
  // bleiben; neue Arten nur hinten anhaengen.
  TFindingActionKind = (fakFix, fakNavigate, fakSuppress);

  TFindingAction = record
    Caption : string;        // Menuetext, bereits lokalisiert
    Hint    : string;        // was passiert bzw. warum nicht (Enabled = False)
    Enabled : Boolean;
    Execute : TNotifyEvent;  // nil bei Enabled = False erlaubt
    Kind    : TFindingActionKind;
  end;

  // Liefert die Aktionen eines Anbieters zu einem Fund; leer, wenn der
  // Anbieter fuer diesen Fund nichts anzubieten hat.
  TFindingActionProvider = function(
    const AFinding: TLeakFinding): TArray<TFindingAction> of object;

  TFindingActions = class
  public
    // Meldet einen Anbieter an. Liefert das Token fuer Unregister (> 0).
    // Token 0 = nicht angemeldet: nil-Anbieter (Assigned prueft den
    // Code-Zeiger) oder Registry schon abgebaut. Unregister(0) ist ein
    // No-Op. Ein nil-Anbieter zaehlte frueher in ProviderCount mit und
    // hielt so Kontextmenue und Gluehbirne des Hosts unnoetig wach
    // (Review reDelphiX 2026-10-07, Minor 7).
    class function Register(AProvider: TFindingActionProvider): Integer;
      static;
    // Meldet den Anbieter mit diesem Token ab. Unbekanntes Token: no-op.
    class procedure Unregister(AToken: Integer); static;
    // Alle Aktionen aller Anbieter zu diesem Fund, in Anmeldereihenfolge.
    // nil-Fund: leer.
    class function ActionsFor(const AFinding: TLeakFinding): TArray<TFindingAction>;
      static;
    class function ProviderCount: Integer; static;
  end;

implementation

uses
  System.SyncObjs;

type
  TEntry = record
    Token    : Integer;
    Provider : TFindingActionProvider;
  end;

var
  GLock    : TCriticalSection = nil;
  GEntries : TList<TEntry> = nil;
  GNext    : Integer = 0;

class function TFindingActions.Register(
  AProvider: TFindingActionProvider): Integer;
var
  E : TEntry;
begin
  Result := 0;
  if not Assigned(AProvider) then Exit;
  if (GLock = nil) or (GEntries = nil) then Exit;
  GLock.Enter;
  try
    Inc(GNext);
    E.Token    := GNext;
    E.Provider := AProvider;
    GEntries.Add(E);
    Result := E.Token;
  finally
    GLock.Leave;
  end;
end;

class procedure TFindingActions.Unregister(AToken: Integer);
var
  i : Integer;
begin
  if (GLock = nil) or (GEntries = nil) then Exit;
  GLock.Enter;
  try
    for i := GEntries.Count - 1 downto 0 do
      if GEntries[i].Token = AToken then
        GEntries.Delete(i);
  finally
    GLock.Leave;
  end;
end;

class function TFindingActions.ActionsFor(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  Providers : TArray<TFindingActionProvider>;
  i, k      : Integer;
  Part      : TArray<TFindingAction>;
  Count     : Integer;
begin
  Result := nil;
  if not Assigned(AFinding) or (GLock = nil) or (GEntries = nil) then Exit;
  // Anbieterliste unter dem Lock kopieren, die Anbieter OHNE Lock rufen -
  // ein Anbieter darf seinerseits Register/Unregister aufrufen.
  GLock.Enter;
  try
    SetLength(Providers, GEntries.Count);
    for i := 0 to GEntries.Count - 1 do
      Providers[i] := GEntries[i].Provider;
  finally
    GLock.Leave;
  end;
  Count := 0;
  for i := 0 to High(Providers) do
  begin
    if not Assigned(Providers[i]) then Continue;
    Part := Providers[i](AFinding);
    if Length(Part) = 0 then Continue;
    SetLength(Result, Count + Length(Part));
    for k := 0 to High(Part) do
      Result[Count + k] := Part[k];
    Inc(Count, Length(Part));
  end;
end;

class function TFindingActions.ProviderCount: Integer;
begin
  Result := 0;
  if (GLock = nil) or (GEntries = nil) then Exit;
  GLock.Enter;
  try
    Result := GEntries.Count;
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock    := TCriticalSection.Create;
  GEntries := TList<TEntry>.Create;

finalization
  FreeAndNil(GEntries);
  FreeAndNil(GLock);

end.
