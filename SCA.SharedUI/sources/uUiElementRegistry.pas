unit uUiElementRegistry;

// Verzeichnis der UI-Elemente eines Plugins.
//
// WOZU
//   Bis 2026-08-10 verteilten sich elf RegisterXxx/UnregisterXxx-Paare auf
//   drei Anmelde- und drei Abmeldeorte, sechs davon versteckt in einer
//   Routine namens RegisterAnalyserDockableForm. Es gab keine Stelle, an
//   der man sah, woraus die Oberflaeche besteht - und die eine bekannte
//   Abhaengigkeit stand als Prosakommentar, den der Compiler nicht prueft.
//   Diese Liste IST die Uebersicht.
//
// WARUM HIER UND NICHT IM PLUGIN-PAKET
//   Die Registry kennt keine ToolsAPI - sie haelt eine geordnete Liste und
//   ruft zwei Methoden. Damit liegt sie im Suchpfad des Testprojekts und
//   ist pruefbar. Genau das ist der belegte Vorteil von DelphiLints
//   IIDEServices-Fassade gegenueber GExperts und CnWizards: dort laesst
//   sich die Abbausymmetrie testen, hier nur lesen. Die Elemente selbst
//   bleiben im Plugin, wo sie hingehoeren.
//
// ENTWURFSENTSCHEIDUNGEN, alle aus dem Fremdvergleich
//   * REIHENFOLGE IST EIGENSCHAFT DES ELEMENTS (SortKey), nicht eine
//     Sortiertabelle im Rahmenwerk. GExperts und CnWizards registrieren in
//     initialization, damit ist die Reihenfolge die uses-Reihenfolge - und
//     BEIDE mussten sie nachtraeglich kuenstlich korrigieren, eines mit
//     einem hartkodierten Array, das andere durch Umsortieren per
//     Klassennamen-String.
//   * ABMELDEN RUECKWAERTS, und zwar aus der Datenstruktur statt von Hand.
//     Gemessen am 2026-08-10 laeuft der Abbau des Plugins ueberwiegend
//     VORWAERTS; vier Elemente wechseln beim Umstellen ihre Position.
//   * JEDES ELEMENT EINZELN GEKAPSELT, an- wie abmeldend. Ein defektes
//     Element darf die uebrigen nicht mitreissen.
//   * DIAGNOSE IMMER SICHTBAR, nie hinter {$IFDEF DEBUG}. Bei CnWizards
//     verschwindet im Release ein Element, dessen Konstruktor scheitert,
//     spurlos.
//
// WAS SIE NICHT TUT
//   Sie kennt weder ToolsAPI noch INI noch VCL. Ob ein Element aktiv ist,
//   beantwortet das Element selbst (IsEnabled) - die Registry fragt nur.

interface

uses
  System.Generics.Collections,
  System.Generics.Defaults,   // TComparer - steht NICHT in .Collections
  System.Math,                // CompareValue - ueberlaufsicherer Vergleich
  System.SysUtils;

type
  /// <summary>
  ///   Ein einzelnes UI-Element des Plugins (Menuepunkt, Dockfenster,
  ///   Options-Seite, Editor-Dekoration, ...).
  /// </summary>
  IIDEUiElement = interface
    ['{6B1F4C2E-9A77-4D3B-8E15-2C4A7F0B9D31}']
    /// <summary>
    ///   Stabiler, technischer Name. Dient als Anzeigename in Protokollen
    ///   UND als Grundlage des Not-Aus-Schluessels - er darf sich deshalb
    ///   nicht aendern, ohne dass die Einstellung der Anwender verfaellt.
    /// </summary>
    function Name: string;

    /// <summary>
    ///   Position in der Anmeldereihenfolge. Kleiner zuerst; abgemeldet
    ///   wird in genau umgekehrter Folge.
    /// </summary>
    /// <remarks>
    ///   Bewusst eine Eigenschaft des Elements: wer eine Abhaengigkeit hat,
    ///   traegt sie an sich selbst und begruendet sie in seinem eigenen
    ///   Quelltext. Eine Sortiertabelle im Rahmenwerk waere der Weg, den
    ///   zwei etablierte Plugins gegangen und dann korrigiert haben.
    /// </remarks>
    function SortKey: Integer;

    /// <summary>
    ///   False laesst die Registry dieses Element ueberspringen - es wird
    ///   weder an- noch abgemeldet.
    /// </summary>
    function IsEnabled: Boolean;

    /// <summary> Meldet das Element bei der IDE an. </summary>
    procedure RegisterElement;

    /// <summary> Meldet es wieder ab. Muss mehrfach aufrufbar sein. </summary>
    procedure UnregisterElement;
  end;

  /// <summary>
  ///   Empfaengt Diagnosemeldungen der Registry (ein Element uebersprungen,
  ///   eine Ausnahme geschluckt). nil = keine Ausgabe.
  /// </summary>
  TUiRegistryLogProc = reference to procedure(const AMessage: string);

  /// <summary> An-/Abmelde-Schritt eines delegierten Elements. </summary>
  TUiElementProc = reference to procedure;

  /// <summary> Liefert, ob ein delegiertes Element aktiv ist. </summary>
  TUiElementEnabledFunc = reference to function: Boolean;

  /// <summary>
  ///   Wiederverwendbarer Adapter: macht aus zwei vorhandenen Prozeduren
  ///   ein IIDEUiElement, ohne dass je Element eine eigene Klasse
  ///   entsteht.
  /// </summary>
  /// <remarks>
  ///   Fuer den Umbau eines Bestands ist das die passende Form: die elf
  ///   RegisterXxx/UnregisterXxx-Rumpfe des Plugins bleiben unangetastet,
  ///   der Adapter traegt nur Name, Position und die beiden Verweise.
  ///   Eine Klasse je Element (wie bei GExperts/CnWizards) lohnt erst,
  ///   wenn Elemente eigenes Verhalten bekommen.
  ///
  ///   nil ist an zwei Stellen ein gueltiger Wert mit definierter
  ///   Bedeutung: AUnregisterProc=nil heisst "nichts abzubauen" (z. B.
  ///   ein reiner Warmlade-Schritt), AEnabledFunc=nil heisst "immer an"
  ///   (z. B. der PackageWizard, an dem der Abbau aller anderen haengt).
  ///   ARegisterProc=nil ergibt ein totes Element und wirft deshalb schon
  ///   im Konstruktor - nicht erst still beim Anmelden.
  ///
  ///   Wirft die EnabledFunc, gilt das Element als AN: ein kaputter
  ///   Not-Aus-Schalter darf ein UI-Element nicht stilllegen. Der Fehler
  ///   wird nicht verschluckt, sondern von der Registry protokolliert.
  /// </remarks>
  TDelegatedUiElement = class(TInterfacedObject, IIDEUiElement)
  private
    FName           : string;
    FSortKey        : Integer;
    FRegisterProc   : TUiElementProc;
    FUnregisterProc : TUiElementProc;
    FEnabledFunc    : TUiElementEnabledFunc;
  public
    constructor Create(const AName: string; ASortKey: Integer;
      const ARegisterProc: TUiElementProc;
      const AUnregisterProc: TUiElementProc;
      const AEnabledFunc: TUiElementEnabledFunc = nil);
    /// <summary> Siehe IIDEUiElement. </summary>
    function Name: string;
    /// <summary> Siehe IIDEUiElement. </summary>
    function SortKey: Integer;
    /// <summary> nil-Funktion oder werfende Funktion = an. </summary>
    function IsEnabled: Boolean;
    /// <summary> Ruft die Register-Prozedur. </summary>
    procedure RegisterElement;
    /// <summary> Ruft die Unregister-Prozedur; nil = no-op. </summary>
    procedure UnregisterElement;
  end;

  /// <summary>
  ///   Geordnetes Verzeichnis der UI-Elemente. Nicht threadsicher - alle
  ///   Aufrufe laufen im VCL-Thread beim Laden und Entladen des Pakets.
  /// </summary>
  TUiElementRegistry = class
  private
    FItems      : TList<IIDEUiElement>;
    FRegistered : TList<IIDEUiElement>;
    FOnLog      : TUiRegistryLogProc;
    procedure Log(const AText: string);
    // Elemente aufsteigend nach SortKey. Eine Stelle, an der die
    // Anmeldereihenfolge entsteht - RegisterAll und NamesInRegisterOrder
    // muessen dieselbe liefern, sonst zeigt das Protokoll etwas anderes
    // als der Code tut.
    function SortedItems: TArray<IIDEUiElement>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    ///   Nimmt ein Element auf. Die Aufrufreihenfolge spielt keine Rolle -
    ///   sortiert wird beim Anmelden nach SortKey.
    /// </summary>
    procedure Add(const AElement: IIDEUiElement);

    /// <summary>
    ///   Meldet alle aktiven Elemente aufsteigend nach SortKey an.
    /// </summary>
    /// <remarks>
    ///   Jedes Element einzeln gekapselt: wirft eines beim Anmelden, wird
    ///   das protokolliert, das Element gilt als nicht angemeldet, und die
    ///   uebrigen laufen weiter. Nur tatsaechlich angemeldete Elemente
    ///   landen in der Abmeldeliste - ein halb angemeldetes wieder
    ///   abzumelden waere geraten.
    /// </remarks>
    procedure RegisterAll;

    /// <summary>
    ///   Meldet in EXAKT umgekehrter Reihenfolge ab und leert die
    ///   Abmeldeliste. Mehrfach aufrufbar.
    /// </summary>
    procedure UnregisterAll;

    /// <summary> Anzahl aufgenommener Elemente. </summary>
    function Count: Integer;

    /// <summary>
    ///   Namen in Anmeldereihenfolge - fuer Protokoll und Test.
    /// </summary>
    function NamesInRegisterOrder: TArray<string>;

    /// <summary>
    ///   Namen der tatsaechlich angemeldeten Elemente in der Folge, in der
    ///   UnregisterAll sie abmelden wuerde.
    /// </summary>
    function NamesInUnregisterOrder: TArray<string>;

    /// <summary>
    ///   Empfaenger der Diagnosemeldungen. nil = still. Bewusst ein Haken
    ///   und kein fester Ausgabeweg: die Registry soll weder OutputDebugString
    ///   noch eine Protokolldatei kennen muessen - im Test haengt hier eine
    ///   Liste, im Plugin die Fehlerausgabe.
    /// </summary>
    property OnLog: TUiRegistryLogProc read FOnLog write FOnLog;
  end;

/// <summary>
///   Leitet aus dem Elementnamen den INI-Schluessel des Not-Aus ab.
/// </summary>
/// <remarks>
///   Eine Stelle, damit Leser und Schreiber nicht auseinanderlaufen -
///   zwei Literale fuer denselben Schluessel sind die Falle, in der ein
///   Merkmal STUMM ausfaellt: kein Compiler-Fehler, keine Meldung, es tut
///   nur nichts. Genau so ist es 2026-08-09 beim Nur-Text-Hint passiert.
///
///   Alles ausser Buchstaben und Ziffern faellt weg, damit der Schluessel
///   in einer INI-Zeile nichts zerlegt. Leerer oder unbrauchbarer Name
///   liefert einen leeren String - der Aufrufer behandelt das als "kein
///   Schluessel, Element bleibt an".
/// </remarks>
function UiElementEnabledKey(const AName: string): string;

implementation

// noinspection-file ClassPerFile
// Schnittstelle, Registry und ihr Standard-Adapter (TDelegatedUiElement)
// bilden EIN Modul: der Adapter existiert nur, damit Elemente ohne eigene
// Klasse in die Registry kommen - ihn in eine eigene Unit zu verbannen
// wuerde jeden Verwender zwingen, zwei Units zu importieren, die nie
// getrennt auftreten.

function UiElementEnabledKey(const AName: string): string;
// Vertrag steht an der Deklaration.
var
  C : Char;
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for C in AName do
    begin
      if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
        SB.Append(C);
    end;
    if SB.Length = 0 then
    begin
      Exit('');
    end;
    Result := 'Element.' + SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TUiElementRegistry }

constructor TUiElementRegistry.Create;
begin
  inherited Create;
  FItems      := TList<IIDEUiElement>.Create;
  FRegistered := TList<IIDEUiElement>.Create;
end;

destructor TUiElementRegistry.Destroy;
begin
  // Nicht automatisch abmelden: der Zeitpunkt der Freigabe gehoert dem
  // Aufrufer, und ein Abmelden waehrend des Paket-Teardowns kann in
  // bereits zerstoerte IDE-Dienste laufen. Wer abmelden will, ruft
  // UnregisterAll - sichtbar und an einer Stelle, die er kontrolliert.
  FreeAndNil(FRegistered);
  FreeAndNil(FItems);
  inherited;
end;

procedure TUiElementRegistry.Log(const AText: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AText);
  end;
end;

procedure TUiElementRegistry.Add(const AElement: IIDEUiElement);
begin
  if not Assigned(AElement) then
  begin
    Exit;
  end;
  FItems.Add(AElement);
end;

function TUiElementRegistry.SortedItems: TArray<IIDEUiElement>;
// Vertrag steht an der Deklaration.
begin
  Result := FItems.ToArray;
  TArray.Sort<IIDEUiElement>(Result,
    TComparer<IIDEUiElement>.Construct(
      function(const A, B: IIDEUiElement): Integer
      begin
        // CompareValue statt der naheliegenden Subtraktion: bei weit
        // auseinander liegenden SortKeys kann die Differenz ueberlaufen,
        // und ein Vergleichsergebnis mit falschem Vorzeichen bringt jede
        // Sortierung durcheinander.
        Result := CompareValue(A.SortKey, B.SortKey);
      end));
end;

procedure TUiElementRegistry.RegisterAll;
// Vertrag steht an der Deklaration.
var
  E       : IIDEUiElement;
  Enabled : Boolean;
begin
  for E in SortedItems do
  begin
    // Eigener Fang um den Schalter, getrennt vom Anmelden: ein werfender
    // IsEnabled darf weder die Schleife toeten noch als "Anmelden
    // fehlgeschlagen" im Protokoll stehen - das waere die falsche
    // Diagnose. Kaputter Schalter = Element gilt als AN; ein Not-Aus,
    // der kaputt ist, darf nichts stilllegen.
    Enabled := True;
    try
      Enabled := E.IsEnabled;
    except
      // noinspection ExceptionTooGeneral
      on Ex: Exception do
      begin
        Log(Format('IsEnabled wirft, Element gilt als an: %s (%s: %s)',
                   [E.Name, Ex.ClassName, Ex.Message]));
      end;
    end;
    if not Enabled then
    begin
      Log(Format('uebersprungen (abgeschaltet): %s', [E.Name]));
      Continue;
    end;

    try
      E.RegisterElement;
      // ERST nach erfolgreichem Anmelden vormerken. Ein Element, dessen
      // Anmeldung geworfen hat, ist in unbekanntem Zustand - es hinterher
      // abzumelden waere geraten.
      FRegistered.Add(E);
    except
      // Breit gefangen, und das ist der Zweck der Uebung: WELCHE Ausnahme
      // ein fremdes UI-Element wirft, weiss die Registry nicht und darf es
      // nicht wissen muessen. Sie darf nur nicht abbrechen.
      // noinspection ExceptionTooGeneral
      on Ex: Exception do
      begin
        Log(Format('Anmelden fehlgeschlagen: %s (%s: %s)',
                   [E.Name, Ex.ClassName, Ex.Message]));
      end;
    end;
  end;
end;

procedure TUiElementRegistry.UnregisterAll;
// Vertrag steht an der Deklaration.
var
  i : Integer;
  E : IIDEUiElement;
begin
  for i := FRegistered.Count - 1 downto 0 do
  begin
    E := FRegistered[i];
    try
      E.UnregisterElement;
    except
      // Breit gefangen, und das ist der Zweck der Uebung: WELCHE Ausnahme
      // ein fremdes UI-Element wirft, weiss die Registry nicht und darf es
      // nicht wissen muessen. Sie darf nur nicht abbrechen.
      // noinspection ExceptionTooGeneral
      on Ex: Exception do
      begin
        // Weitermachen ist hier Pflicht, nicht Nachlaessigkeit: bricht der
        // Abbau in der Mitte ab, bleiben die uebrigen Elemente an der IDE
        // haengen - und das ist der Zustand, der abstuerzt.
        Log(Format('Abmelden fehlgeschlagen: %s (%s: %s)',
                   [E.Name, Ex.ClassName, Ex.Message]));
      end;
    end;
  end;
  FRegistered.Clear;
end;

function TUiElementRegistry.Count: Integer;
begin
  Result := FItems.Count;
end;

function TUiElementRegistry.NamesInRegisterOrder: TArray<string>;
var
  Sorted : TArray<IIDEUiElement>;
  i      : Integer;
begin
  Sorted := SortedItems;
  SetLength(Result, Length(Sorted));
  for i := 0 to High(Sorted) do
  begin
    Result[i] := Sorted[i].Name;
  end;
end;

function TUiElementRegistry.NamesInUnregisterOrder: TArray<string>;
var
  i : Integer;
begin
  SetLength(Result, FRegistered.Count);
  for i := 0 to FRegistered.Count - 1 do
  begin
    Result[i] := FRegistered[FRegistered.Count - 1 - i].Name;
  end;
end;

{ TDelegatedUiElement }

constructor TDelegatedUiElement.Create(const AName: string;
  ASortKey: Integer; const ARegisterProc: TUiElementProc;
  const AUnregisterProc: TUiElementProc;
  const AEnabledFunc: TUiElementEnabledFunc);
begin
  inherited Create;
  // Frueh und laut statt spaet und still: ein Element ohne
  // Register-Prozedur kann nie etwas anmelden - der Fehler liegt am
  // AUFRUFORT des Konstruktors, also soll er auch dort knallen und nicht
  // erst als Protokollzeile beim Plugin-Start auftauchen.
  if not Assigned(ARegisterProc) then
  begin
    raise EArgumentNilException.Create(
      'TDelegatedUiElement.Create: ARegisterProc ist nil (' + AName + ')');
  end;
  FName           := AName;
  FSortKey        := ASortKey;
  FRegisterProc   := ARegisterProc;
  FUnregisterProc := AUnregisterProc;
  FEnabledFunc    := AEnabledFunc;
end;

function TDelegatedUiElement.Name: string;
begin
  Result := FName;
end;

function TDelegatedUiElement.SortKey: Integer;
begin
  Result := FSortKey;
end;

function TDelegatedUiElement.IsEnabled: Boolean;
// nil = immer an. Wirft die Funktion, faengt das die REGISTRY (eigener
// Fang um den Schalter in RegisterAll) und wertet es als an - hier nicht
// doppelt fangen, sonst verschwaende der Fehler ohne Protokollzeile.
begin
  if Assigned(FEnabledFunc) then
  begin
    Result := FEnabledFunc;
  end
  else
  begin
    Result := True;
  end;
end;

procedure TDelegatedUiElement.RegisterElement;
begin
  FRegisterProc;
end;

procedure TDelegatedUiElement.UnregisterElement;
// nil = "nichts abzubauen" - ein gueltiger Zustand (z. B. reiner
// Warmlade-Schritt), kein Fehler.
begin
  if Assigned(FUnregisterProc) then
  begin
    FUnregisterProc;
  end;
end;

end.
