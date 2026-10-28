unit uEditorFindingStore;

// Speicher der Editor-Funde: Kopien der Funde der letzten Silent-Laeufe,
// JE DATEI, fuer Editor-Kontextmenue und Gluehbirne (AH10, 2026-10-05).
// Der Silent-Lauf gibt seine Liste nach dem Markieren frei; die Kopien
// tragen ALLE Felder (TLeakFinding.Clone). Bis 2026-10-28 nur die, von
// denen man annahm, ein Anbieter lese sie - LeakVariant fehlte, reDelphix
// sperrte den SCA001-Fix "Free ausserhalb finally" (Befund B1).
//
// Ohne VCL und ohne ToolsAPI (Review Woche 2026-10-21, G04-06): bis dahin
// standen Speicher und Verdraengung in uIDEAnalyserForm (TEditorFindingsCopy,
// GEditorFindings, DropOldestEditorFindings) und waren nur in der IDE
// pruefbar. uIDEAnalyserForm reicht jetzt nur Schluessel (NormalizePathForKey
// der Datei) und Generation (NextFindingsGeneration) herein. Getestet in
// TestProject (uTestEditorFindingStore). Nicht im FPC-Pruefstand
// (SCA.SharedUI/tools/run_fpc_pure.sh): TLeakFinding kommt aus SCA.Engine.
//
// Regeln:
//   * Je Schluessel EINE Kopie; ein neuer Lauf derselben Datei ersetzt sie
//     samt Generation (mit nur einem Platz nahmen Birne und Kontextmenue
//     nach einem Tab-Wechsel A->B->A fuer A wieder die alten Dock-Zeilen,
//     Review 2026-10-14, MAJOR 3).
//   * Hoechstens Capacity Dateien. Kommt eine NEUE Datei zu einem vollen
//     Speicher, faellt die Kopie mit der KLEINSTEN Generation weg - nicht die
//     zuerst eingefuegte: ein Ersetzen macht eine Datei wieder juenger. Der
//     naechste Tab-Wechsel auf die verdraengte Datei scannt ohnehin neu.
//   * Der Speicher besitzt die Kopien und ihre Funde. Ein Ersetzen oder
//     Verdraengen gibt die alte Kopie frei; ein Zeiger aus TryGet gilt also
//     nur bis zum naechsten Keep.

interface

uses
  System.Generics.Collections,
  uMethodd12;                   // TLeakFinding

type
  // Die Kopien EINER Datei aus EINEM Silent-Lauf.
  TEditorFindingsCopy = class
  public
    Gen   : UInt64;                       // Generation des Silent-Laufs
    Items : TObjectList<TLeakFinding>;    // die Kopien (Eigentum)
    constructor Create;
    destructor Destroy; override;
  end;

  TEditorFindingStore = class
  private
    FCapacity : Integer;
    FCopies   : TObjectDictionary<string, TEditorFindingsCopy>;
    procedure DropOldest;
  protected
    // Kopie EINES Funds mit allen Feldern (TLeakFinding.Clone). Virtuell
    // nur fuer den Test: er zaehlt die Freigaben der Kopien und laesst das
    // Kopieren mitten in einem Lauf scheitern.
    function CopyOf(AFinding: TLeakFinding): TLeakFinding; virtual;
  public
    // ACapacity: hoechstens so viele Dateien (>= 1).
    constructor Create(ACapacity: Integer);
    destructor Destroy; override;
    // Legt Kopien der Funde unter AKey mit der Generation AGen ab; nil-
    // Eintraege werden uebersprungen, eine nil-Liste ergibt eine leere
    // Kopie. Wirft das Kopieren, bleibt der alte Stand unter AKey stehen,
    // und nichts leckt.
    procedure Keep(const AKey: string; AFindings: TList<TLeakFinding>;
      AGen: UInt64);
    // Die Kopie unter AKey (gehoert dem Speicher); False und nil ohne.
    function TryGet(const AKey: string; out ACopy: TEditorFindingsCopy): Boolean;
    function Count: Integer;
    property Capacity: Integer read FCapacity;
  end;

implementation

uses
  System.SysUtils;              // FreeAndNil

constructor TEditorFindingsCopy.Create;
begin
  inherited Create;
  Items := TObjectList<TLeakFinding>.Create(True);
end;

destructor TEditorFindingsCopy.Destroy;
begin
  FreeAndNil(Items);
  inherited;
end;

constructor TEditorFindingStore.Create(ACapacity: Integer);
begin
  inherited Create;
  FCapacity := ACapacity;
  FCopies := TObjectDictionary<string, TEditorFindingsCopy>.Create(
    [doOwnsValues]);
end;

destructor TEditorFindingStore.Destroy;
begin
  FreeAndNil(FCopies);
  inherited;
end;

function TEditorFindingStore.CopyOf(AFinding: TLeakFinding): TLeakFinding;
begin
  Result := AFinding.Clone;
end;

// Die Kopie mit der kleinsten Generation weicht.
procedure TEditorFindingStore.DropOldest;
var
  Pair   : TPair<string, TEditorFindingsCopy>;
  Oldest : string;
  Gen    : UInt64;
begin
  Oldest := '';
  Gen    := High(UInt64);
  for Pair in FCopies do
    if Pair.Value.Gen < Gen then
    begin
      Gen    := Pair.Value.Gen;
      Oldest := Pair.Key;
    end;
  if Oldest <> '' then
    FCopies.Remove(Oldest);
end;

procedure TEditorFindingStore.Keep(const AKey: string;
  AFindings: TList<TLeakFinding>; AGen: UInt64);
var
  F, C   : TLeakFinding;
  Kept   : TEditorFindingsCopy;
  Stored : TEditorFindingsCopy;
begin
  // Verdraengt wird nur fuer eine NEUE Datei - ein Ersetzen braucht keinen
  // Platz.
  if not FCopies.ContainsKey(AKey) and (FCopies.Count >= FCapacity) then
    DropOldest;
  Kept := TEditorFindingsCopy.Create;
  // Kept gehoert bis zum AddOrSetValue niemandem: wirft das Kopieren
  // (EOutOfMemory), gaebe sonst niemand Kept samt der schon kopierten Funde
  // frei (Review Woche G04-07). Steht Kept schon im Dictionary (beim
  // Ersetzen wirft erst die Freigabe der alten Kopie), besitzt es Kept -
  // dann kein Free. Kept lebt beim Vergleich noch: keine
  // Adress-Wiederverwendung.
  try
    Kept.Gen := AGen;
    if Assigned(AFindings) then
      for F in AFindings do
      begin
        if not Assigned(F) then Continue;
        // C geht SOFORT in die Liste: das Free von Kept gibt es dann mit
        // frei.
        C := CopyOf(F);
        try
          Kept.Items.Add(C);
        except
          C.Free;
          raise;
        end;
      end;
    FCopies.AddOrSetValue(AKey, Kept);
  except
    if not FCopies.TryGetValue(AKey, Stored) or (Stored <> Kept) then
      Kept.Free;
    raise;
  end;
end;

function TEditorFindingStore.TryGet(const AKey: string;
  out ACopy: TEditorFindingsCopy): Boolean;
begin
  Result := FCopies.TryGetValue(AKey, ACopy);
end;

function TEditorFindingStore.Count: Integer;
begin
  Result := FCopies.Count;
end;

end.
