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
//     Der Wert 0 ist fakUnset, die SICHERE Vorgabe (Review 2026-10-14):
//     ein Anbieter, der Kind nicht setzt (SetLength, Default), bekommt
//     eine Aktion, die Kontextmenue und Dock-Grid wie angegeben zeigen,
//     die aber nie in der Gluehbirne steht und die keine Taste
//     (Ctrl+Alt+F, Ctrl+Alt+S) ungesehen ausfuehrt. Bis dahin war 0 =
//     fakFix: eine vergessene Zuweisung machte aus jeder Aktion eine
//     Hilfe, die Ctrl+Alt+F blind ausfuehrte. Wer eine Hilfe meint, setzt
//     fakFix ausdruecklich (reDelphix tut das in TRdxProvider.Add).
//   * fakSuppress unterdrueckt den Fund (`// noinspection`-Marker). Das
//     ist KEINE Hilfe: die Gluehbirne erscheint deswegen nicht, zeigt es
//     aber unter den Hilfen, wenn es zu dem Fund eine gibt (Nico
//     2026-10-08, Editorhilfen E1). Kontextmenue und Dock-Grid zeigen es
//     immer. Ein Menue setzt die Unterdrueck-Eintraege mit einem Trenner ab.
//   * fakRefactor ist ein Umbau an der STELLE, der den Fund nicht behebt
//     (reDelphix: uses-Eintraege qualifizieren auf einer Fundzeile). Die
//     Gluehbirne zeigt ihn nie; Kontextmenue und Dock-Grid zeigen ihn,
//     und zwar je Menue nur einmal: gleichlautende fakRefactor-Eintraege
//     (gleiche Caption) mehrerer Funde derselben Zeile erscheinen beim
//     ersten Fund (Review reDelphiX nach Bereichen 2026-10-10, Minor 13
//     und 14).
//   * Ein Host fragt fuer EIN Menue hoechstens MAX_FINDINGS_PER_MENU Funde
//     ab (uFindingActionMenu.BuildFindingMenuModel; der Rest erscheint als
//     Hinweiszeile). Ein Anbieter, der seine Aktionsobjekte haelt, muss die
//     Objekte von deutlich MEHR Abfragen am Leben halten: zwischen Aufbau
//     und Klick koennen weitere laufen (die Gluehbirne prueft im Hinter-
//     grund). reDelphix haelt 8 x MAX_FINDINGS_PER_MENU Chargen
//     (Review reDelphiX 2026-10-07, Blocker 2: bei 33 Funden auf einer
//     Zeile zeigten Menuepunkte auf freigegebene Objekte).
//
// CODE-AKTIONEN OHNE FUND (Charge B, Entscheide Nico 2026-10-23, E14/E16)
//
//   * Eine Kontextaktion haengt nicht an einem Fund, sondern an der
//     Caret-Stelle im Editor (TEditorContext: Datei, Zeile, Zeichen-
//     Spalte, optional die Auswahl, dazu die Funde der Zeile). Ein
//     Kontext-Anbieter (TContextActionProvider) meldet sich mit
//     RegisterContext an; der Host fragt beim Oeffnen des Editor-
//     Kontextmenues EINMAL ContextActionsFor (nicht je Fund). Einstieg ist
//     das bestehende Kontextmenue des Plugins - nicht die Gluehbirne,
//     keine Taste (E15).
//   * Alles, was ContextActionsFor liefert, traegt Kind = fakContext - die
//     Registry setzt es selbst, ein Anbieter kann es nicht vergessen und
//     keine Kontextaktion als fakFix in die Gluehbirne oder unter eine
//     Taste schmuggeln. fakContext steht nie in der Gluehbirne
//     (moAvailableFixesOnly laesst sie weg) und laeuft nie per Taste
//     (FirstRunnable fragt nur fakFix bzw. fakSuppress).
//   * Gleichlautende Captions von Fund- und Kontextaktion stehen im Menue
//     nur einmal, und zwar am Fund (uFindingActionMenu.
//     AppendContextActions); ebenso gleichlautende zweier Kontext-Anbieter.
//   * Der Anbieter liest den Text selbst, wie bei den Fund-Aktionen
//     (reDelphix: Editor-Puffer, sonst Platte). Der Kontext traegt keinen
//     Text: der Host muesste sonst bei jedem Rechtsklick den Puffer lesen,
//     auch wenn kein Anbieter etwas anbietet.
//   * Tokens kommen aus demselben Zaehler wie die der Fund-Anbieter;
//     Unregister meldet beide Arten ab. ProviderCount zaehlt NUR die
//     Fund-Anbieter (Gluehbirne und Tasten haengen daran),
//     ContextProviderCount die Kontext-Anbieter.
//   * Lebensdauer der Aktionsobjekte: wie oben, ein Kontextmenue fragt
//     einmal je Oeffnen; dazwischen koennen weitere Abfragen laufen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12;

const
  // Hoechstzahl der Funde, deren Aktionen EIN Menue erfragt (VERTRAG oben).
  MAX_FINDINGS_PER_MENU = 16;

type
  // Was eine Aktion ist (siehe VERTRAG oben). fakUnset MUSS Ordnungszahl 0
  // bleiben - es ist der Wert, den Default(TFindingAction) und SetLength
  // liefern; neue Arten nur hinten anhaengen. fakContext (Charge B): eine
  // Code-Aktion an der Caret-Stelle ohne Fund, gesetzt von
  // ContextActionsFor (VERTRAG "CODE-AKTIONEN OHNE FUND" oben).
  TFindingActionKind = (fakUnset, fakFix, fakNavigate, fakSuppress,
    fakRefactor, fakContext);

  TFindingAction = record
    Caption : string;        // Menuetext, bereits lokalisiert
    Hint    : string;        // was passiert bzw. warum nicht (Enabled = False)
    Enabled : Boolean;
    Execute : TNotifyEvent;  // nil bei Enabled = False erlaubt
    Kind    : TFindingActionKind;
    // Die Aktion kann das Verhalten des Programms aendern (Konzept
    // Editorhilfen, Entscheid E2) - der Menuetext sagt es. Ein Tastendruck,
    // der die erste Hilfe ungesehen ausfuehrt (Ctrl+Alt+F im Plugin),
    // laesst sie aus. Vorgabe False (Default(TFindingAction)) - das ist
    // bewusst so belassen (Review 2026-10-14): die Sperre gegen eine
    // VERGESSENE Kennzeichnung sitzt in Kind (fakUnset laeuft nie per
    // Taste); wer eine Aktion ausdruecklich als fakFix meldet, hat ueber
    // ChangesBehavior entschieden. Ein Boolean kennt keinen dritten Wert
    // "nicht gesetzt", und eine Umkehr (SafeForKey) haette jeden
    // Anbieter angefasst.
    ChangesBehavior : Boolean;
  end;

  // Liefert die Aktionen eines Anbieters zu einem Fund; leer, wenn der
  // Anbieter fuer diesen Fund nichts anzubieten hat.
  TFindingActionProvider = function(
    const AFinding: TLeakFinding): TArray<TFindingAction> of object;

  // Die Caret-Stelle im Editor, an der der Benutzer das Kontextmenue
  // oeffnet. Zeilen und Spalten sind 1-basiert und zaehlen wie
  // TRefactorSpan (uRefactorInfo): ZEICHEN der dekodierten Zeile
  // (UTF-16-Index eines Delphi-Strings, ein Tabulator ist EIN Zeichen) -
  // nicht die Anzeigespalte des Editors und nicht UTF-8-Bytes; die
  // Umrechnung macht der Host. Kein TRefactorSpan, weil Common-Units den
  // Quellstellen-Dienst nicht kennen duerfen (places_dep_gate, Regel 2).
  // Die Auswahl ist ein Zeichenbereich wie TRefactorSpan: SelEndCol zeigt
  // HINTER das letzte Zeichen; ein Spaltenblock ist keine Auswahl (der
  // Host laesst HasSelection dann False).
  TEditorContext = record
    FileName     : string;    // wie TLeakFinding.FileName: absoluter Pfad
    Line         : Integer;   // Caret-Zeile, 1-basiert
    Col          : Integer;   // Caret-Zeichen-Spalte, 1-basiert
    HasSelection : Boolean;   // nur dann gelten die vier Sel*-Felder
    SelStartLine : Integer;
    SelStartCol  : Integer;
    SelEndLine   : Integer;
    SelEndCol    : Integer;   // hinter dem letzten Zeichen (exklusiv)
    // Die Funde der Caret-Zeile, wie der Host sie fuer das Menue hat. Der
    // Host besitzt sie; ein Anbieter liest sie nur (z. B. um nichts
    // anzubieten, was eine Fund-Aktion schon bietet) und haelt keine
    // Referenz ueber den Aufruf hinaus.
    Findings     : TArray<TLeakFinding>;
    // Kontext ohne Auswahl und ohne Funde.
    class function At(const AFileName: string;
      ALine, ACol: Integer): TEditorContext; static;
    // Setzt die Auswahl, wenn sie wohlgeformt und nicht leer ist (Start
    // >= 1/1, Ende hinter dem Start); sonst bleibt HasSelection False.
    // Liefert HasSelection.
    function SetSelection(AStartLine, AStartCol, AEndLine,
      AEndCol: Integer): Boolean;
    // Datei gesetzt, Zeile und Spalte >= 1.
    function IsValid: Boolean;
    // True, wenn eine Auswahl gesetzt ist und in einer Zeile liegt.
    function SelectionIsSingleLine: Boolean;
  end;

  // Liefert die Code-Aktionen eines Anbieters an der Caret-Stelle; leer,
  // wenn er dort nichts anzubieten hat. Kind setzt die Registry
  // (fakContext), Enabled/Hint/Execute/ChangesBehavior wie bei Fund-
  // Aktionen.
  TContextActionProvider = function(
    const AContext: TEditorContext): TArray<TFindingAction> of object;

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
    // Meldet den Anbieter mit diesem Token ab - Fund- wie Kontext-
    // Anbieter (ein Zaehler fuer beide). Unbekanntes Token: no-op.
    class procedure Unregister(AToken: Integer); static;
    // Alle Aktionen aller Anbieter zu diesem Fund, in Anmeldereihenfolge.
    // nil-Fund: leer.
    class function ActionsFor(const AFinding: TLeakFinding): TArray<TFindingAction>;
      static;
    // Zahl der FUND-Anbieter (ohne Kontext-Anbieter).
    class function ProviderCount: Integer; static;
    // Meldet einen Kontext-Anbieter an (Code-Aktionen ohne Fund). Token wie
    // Register (> 0, 0 = nicht angemeldet); abgemeldet wird mit Unregister.
    class function RegisterContext(AProvider: TContextActionProvider): Integer;
      static;
    // Alle Code-Aktionen aller Kontext-Anbieter an dieser Stelle, in
    // Anmeldereihenfolge, jede mit Kind = fakContext. Ungueltiger Kontext
    // (TEditorContext.IsValid): leer. Wirft, was ein Anbieter wirft (wie
    // ActionsFor) - das Menuemodell faengt es.
    class function ContextActionsFor(
      const AContext: TEditorContext): TArray<TFindingAction>; static;
    // Zahl der Kontext-Anbieter.
    class function ContextProviderCount: Integer; static;
  end;

implementation

uses
  System.SyncObjs;

type
  TEntry = record
    Token    : Integer;
    Provider : TFindingActionProvider;
  end;

  TContextEntry = record
    Token    : Integer;
    Provider : TContextActionProvider;
  end;

var
  GLock     : TCriticalSection = nil;
  GEntries  : TList<TEntry> = nil;
  GContexts : TList<TContextEntry> = nil;
  GNext     : Integer = 0;   // ein Zaehler fuer beide Listen

{ TEditorContext }

class function TEditorContext.At(const AFileName: string;
  ALine, ACol: Integer): TEditorContext;
begin
  Result := Default(TEditorContext);
  Result.FileName := AFileName;
  Result.Line     := ALine;
  Result.Col      := ACol;
end;

function TEditorContext.SetSelection(AStartLine, AStartCol, AEndLine,
  AEndCol: Integer): Boolean;
begin
  HasSelection := (AStartLine >= 1) and (AStartCol >= 1)
    and ((AEndLine > AStartLine)
         or ((AEndLine = AStartLine) and (AEndCol > AStartCol)));
  if HasSelection then
  begin
    SelStartLine := AStartLine;
    SelStartCol  := AStartCol;
    SelEndLine   := AEndLine;
    SelEndCol    := AEndCol;
  end
  else
  begin
    SelStartLine := 0;
    SelStartCol  := 0;
    SelEndLine   := 0;
    SelEndCol    := 0;
  end;
  Result := HasSelection;
end;

function TEditorContext.IsValid: Boolean;
begin
  Result := (FileName <> '') and (Line >= 1) and (Col >= 1);
end;

function TEditorContext.SelectionIsSingleLine: Boolean;
begin
  Result := HasSelection and (SelStartLine = SelEndLine);
end;

{ TFindingActions }

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
  if (GLock = nil) or (GEntries = nil) or (GContexts = nil) then Exit;
  GLock.Enter;
  try
    for i := GEntries.Count - 1 downto 0 do
      if GEntries[i].Token = AToken then
        GEntries.Delete(i);
    for i := GContexts.Count - 1 downto 0 do
      if GContexts[i].Token = AToken then
        GContexts.Delete(i);
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

class function TFindingActions.RegisterContext(
  AProvider: TContextActionProvider): Integer;
var
  E : TContextEntry;
begin
  Result := 0;
  if not Assigned(AProvider) then Exit;
  if (GLock = nil) or (GContexts = nil) then Exit;
  GLock.Enter;
  try
    Inc(GNext);
    E.Token    := GNext;
    E.Provider := AProvider;
    GContexts.Add(E);
    Result := E.Token;
  finally
    GLock.Leave;
  end;
end;

class function TFindingActions.ContextActionsFor(
  const AContext: TEditorContext): TArray<TFindingAction>;
var
  Providers : TArray<TContextActionProvider>;
  i, k      : Integer;
  Part      : TArray<TFindingAction>;
  Count     : Integer;
begin
  Result := nil;
  if not AContext.IsValid or (GLock = nil) or (GContexts = nil) then Exit;
  // Wie ActionsFor: Liste unter dem Lock kopieren, Anbieter ohne Lock rufen.
  GLock.Enter;
  try
    SetLength(Providers, GContexts.Count);
    for i := 0 to GContexts.Count - 1 do
      Providers[i] := GContexts[i].Provider;
  finally
    GLock.Leave;
  end;
  Count := 0;
  for i := 0 to High(Providers) do
  begin
    if not Assigned(Providers[i]) then Continue;
    Part := Providers[i](AContext);
    if Length(Part) = 0 then Continue;
    SetLength(Result, Count + Length(Part));
    for k := 0 to High(Part) do
    begin
      Result[Count + k] := Part[k];
      // Die Art setzt die Registry (VERTRAG): keine Kontextaktion kommt
      // als fakFix in die Gluehbirne oder unter eine Taste.
      Result[Count + k].Kind := fakContext;
    end;
    Inc(Count, Length(Part));
  end;
end;

class function TFindingActions.ContextProviderCount: Integer;
begin
  Result := 0;
  if (GLock = nil) or (GContexts = nil) then Exit;
  GLock.Enter;
  try
    Result := GContexts.Count;
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock     := TCriticalSection.Create;
  GEntries  := TList<TEntry>.Create;
  GContexts := TList<TContextEntry>.Create;

finalization
  FreeAndNil(GContexts);
  FreeAndNil(GEntries);
  FreeAndNil(GLock);

end.
