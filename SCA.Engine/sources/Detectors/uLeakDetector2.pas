unit uLeakDetector2;

// AST-basierter Speicherleck-Detektor (Sonar-Regel #1).
//
// Erkannte Muster:
//   lsError   – Objekt per .Create erzeugt, nie freigegeben
//   lsWarning – Free außerhalb des finally-Blocks (obwohl try/finally vorhanden)
//   lsWarning – Objekt von Funktion zurückbekommen, nie freigegeben
//
// Ownership-Transfer (kein Befund):
//   Result := var                Funktion gibt Ownership ab
//   var.Parent := winControl     VCL: Parent gibt Children frei (Controls[])
//   var := X.Add(...)            Borrowed-Return aus Tree-/Container-API
//   var := X.AddChild(...)        (AST/XML/DOM/TreeView - Item lebt in
//   var := X.AddNode(...)         Container.OwnsObjects-Liste)
//   var := X.AppendChild(...)
//   FField := var                Var-zu-Feld: Method-Scope abgegeben
//   FField := var as ISomething   (Interface-Refcount uebernimmt Lifetime)
//   inherited Create(var, …)    Elternkonstruktor übernimmt
//   AnyClass.Create(var, …)     anderer Konstruktor übernimmt
//   Container.Add(...var...)     TObjectList/TObjectDictionary/...
//   Container.AddObject(t, var)  TStringList mit Objekten
//                                AUSNAHME (2026-07-31): '<X>.Items/.Lines/
//                                .Objects/.Strings/.Data/.Nodes.AddObject(...)'
//                                ist KEIN Transfer - TStrings besitzt Objects[]
//                                nie, TTreeNode.Data ist ein roher Pointer.
//   Container.Insert(i, var)     TList.Insert
//   Container.Push(var)          TStack.Push
//   Container.Enqueue(var)       TQueue.Enqueue
//   TKlasse.Create(Self|Owner|AOwner|Application)
//                                Owner-Konvention: Owner gibt frei (2026-07-04)
//
// Kein Objekt (kein Befund, 2026-07-04):
//   var := socket(...)/accept(...)/CreateFile(...)/...
//                                OS-Handle-APIs liefern Integer-Handles,
//                                keine Delphi-Objekt-Allokationen
//
// Korrektheitsprinzip:
//   Alle Namensvergleiche prüfen Wortgrenzen auf BEIDEN Seiten,
//   um false positives durch Teilstring-Übereinstimmungen zu verhindern
//   (z. B. 'list' ≠ 'blacklist', 'list.Free' ≠ 'blacklist.Free').

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils, uAnalyzeContext,
  uFileTextCache, uTypeIndex;

type
  TLeakDetector2 = class
  public
    // TD-1 Inkrement 2c (2026-07-06): AContext durchgereicht bis in IsLeakyType
    // (LeakyClasses aus dem Scan-Context). Default =nil -> Tests/Single-File
    // (direkte Aufrufe) lesen weiter den uSCAConsts-Global. AddD (statt AddD3)
    // in uStaticAnalyzer2 reicht den Scan-Ctx an AnalyzeUnit durch.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    // ACHTUNG, SCHWAECHERE ZUSAGE ALS AnalyzeUnit: dieser Einstieg
    // analysiert EINE Methode ohne den unit-weiten Kontext, den
    // AnalyzeUnit vorher aufbaut. Konkret geht verloren:
    //   UnitNode wird zwar mit uebergeben, AContext aber nicht -
    //   damit fehlen Konfiguration, Post-Filter und die Liste der
    //   leaky classes aus der INI. Der Detektor faellt auf seine
    //   eingebauten Voreinstellungen zurueck.
    // Der Parameter hat einen nil-Default - wer ihn weglaesst,
    // bekommt also stillschweigend das schwaechere Ergebnis. Der
    // Regelbetrieb laeuft ueber AnalyzeUnit; dieser Einstieg ist
    // fuer Tests und punktuelle Aufrufe gedacht.
    class procedure AnalyzeMethod(UnitNode, MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      AContext: TAnalyzeContext = nil);

  // Hilfsmethoden (public fuer Wiederverwendung in anderen Detektoren)
  public
    class function IsIdentChar(C: Char): Boolean; static; inline;
    class function IsWholeWord(const Str, Pattern: string;
      Pos_: Integer): Boolean; static;
    // AContext (TD-1 2c): scannt LeakyClasses aus dem Scan-Context; =nil faellt
    // auf den uSCAConsts-Global zurueck (via CtxLeakyClasses).
    class function IsLeakyType(const TypeRef: string;
      AContext: TAnalyzeContext = nil): Boolean; static;
    // Erkennt einen Konstruktor-Aufruf in der RHS einer Zuweisung:
    // sowohl `.Create(...)` als auch CamelCase-Varianten wie `.CreateUtf8`,
    // `.CreateFmt`, `.CreateFromFile`, `.CreateAfterAttach` (mORMot- / RTL-
    // gebraeuchlich). Verb-Formen `.creates` / `.created` werden bewusst
    // ausgeschlossen - die fortsetzenden Kleinbuchstaben unterscheiden
    // Identifier-Suffix (Verb) von CamelCase-Suffix (Konstruktor).
    // ATypeRef ist die original-Case-Form (TypeRef wie aus dem AST),
    // ATypeLow ist `ATypeRef.ToLower` (vorberechnet vom Caller).
    class function MatchesCreate(const ATypeRef, ATypeLow: string;
      out CreatePos: Integer): Boolean; static;
    class function CreateRhsIsBorrowedOrLiteral(
      const RhsLow: string): Boolean; static;
    class function HasCreateAssign(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function HasFunctionCallAssign(UnitNode, MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // Liefert die Quell-Zeile des ERSTEN `var := X.Create(...)`. Wird
    // genutzt um die Befund-Position auf die echte Create-Zeile zu legen
    // statt auf die var-Deklaration - bessere UX (Klick im Grid springt
    // zur Allokation), und macht inline `// noinspection`-Marker ueber
    // dem Create-Aufruf wirksam (Suppression-Map vergleicht 1:1 die
    // Finding-Line gegen die Marker-Target-Line). 0 wenn kein passender
    // Assign gefunden - Caller faellt dann auf die var-Decl-Line zurueck.
    class function FindCreateLine(MethodNode: TAstNode;
      const VarNameLow: string): Integer; static;
    class function FindFuncCallAssignLine(MethodNode: TAstNode;
      const VarNameLow: string): Integer; static;
    class function IsReturnedAsResult(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // Zweiter kanonischer Rueckgabeweg neben Result (T3-Backlog,
    // 2026-08-01) - siehe Implementations-Kommentar.
    class function IsAssignedToOutParam(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // AUnitNode (2026-07-31, Parser-Gate-Backlog 4e/2) ist OPTIONAL und
    // steuert AUSSCHLIESSLICH die Alias-Aufloesung des Add-Empfaengers in
    // AddReceiverOwnsItems. Default nil = exakt das bisherige Verhalten -
    // wichtig, weil TMissingFinallyDetector (SCA009) diese Funktion mitbenutzt
    // und sich NICHT bewegen darf. Nur TLeakDetector2.AnalyzeMethod (SCA001)
    // reicht den Unit-Knoten durch.
    class function IsPassedToOwner(MethodNode: TAstNode;
      const VarNameLow: string; AUnitNode: TAstNode = nil): Boolean; static;
    // FP-Gate (2026-07-04): os-handle - True wenn die RHS ein Aufruf einer
    // bekannten OS-Handle-API ist (socket/accept/CreateFile/CreateEvent/...).
    // Deren Rueckgaben sind Integer-Handles (ggf. in Handle-Wrapper wie
    // TNetSocket gecastet), KEINE Delphi-Objekt-Allokationen - Free waere
    // sogar falsch (closesocket/CloseHandle sind zustaendig).
    class function IsOsHandleApiCall(const RhsLow: string): Boolean; static;
    // FP-Gate (2026-07-04): owner-parameter - True wenn die Variable per
    // `TKlasse.Create(Self|Owner|AOwner|Application)` erzeugt wird
    // (TComponent-Owner-Konvention: der Owner gibt das Objekt in seinem
    // Destroy ueber die Components[]-Liste frei). Create(nil) zaehlt
    // bewusst NICHT - da muss der Aufrufer selbst freigeben.
    class function IsOwnerParamCreate(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function SearchFree(Node: TAstNode; const VarNameLow: string;
      InFinally: Boolean; out FoundInFinally: Boolean): Boolean; static;
    class function HasTryFinallyBlock(MethodNode: TAstNode): Boolean; static;
    // FP-Gate Prio 5 (2026-07-06, Real-World-Audit): das Idiom
    //   try ... except VarName.Free; raise; end
    // gibt VarName auf dem Ausnahme-Pfad frei und wirft weiter - fuer die
    // Leak-Analyse aequivalent zu einem finally-Free (schuetzt gegen Leak
    // bei Exception). Der Detektor kannte bisher nur try/finally und meldete
    // faelschlich "Free ausserhalb finally". True wenn ein except-Handler
    // SOWOHL einen Free von VarName ALS AUCH ein raise (Re-Raise) enthaelt.
    class function HasExceptFreeRaise(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    class function HasDescendantKind(Node: TAstNode;
      Kind: TNodeKind): Boolean; static;
    // True wenn der Receiver eines '.Add(item)'-Aufrufs ein ownership-
    // bewusster Container ist (TObjectList, TObjectDictionary, ...) -
    // ODER wenn der Typ unbekannt ist (Default permissiv, vermeidet
    // Regression bei FList.Add-Mustern). False nur wenn der Typ
    // aufloesbar ist UND nicht zur Whitelist passt (TList, TStringList,
    // TSynList etc. haben kein OwnsObjects).
    // AUnitNode (2026-07-31, Parser-Gate-Backlog 4e/2 - der REGRESSIONSFALL):
    // ist der Empfaengertyp aufloesbar, aber nur weil die Unit ihn als ALIAS
    // bzw. ABLEITUNG eines besitzenden Containers deklariert
    // ('TPeople = TObjectList<TPerson>' / 'TPeople = class(TObjectList<TPerson>)'),
    // dann trifft er die Whitelist nicht und das Gate veto-te faelschlich -
    // mehr Typwissen (Parser-Fix) machte das Ergebnis SCHLECHTER. Mit
    // AUnitNode wird die Unit-lokale Deklarationskette aufgeloest. Default nil
    // = bisheriges Verhalten (SCA008-Pfad bleibt unberuehrt).
    class function AddReceiverOwnsItems(MethodNode: TAstNode;
      const ReceiverNameLow: string; AUnitNode: TAstNode = nil): Boolean; static;
    // finally-Mis-Attachment-Fix (2026-07-13): Source-basierter finally-Schutz-
    // Check. True wenn eine Freigabe von VarName in der QUELLE innerhalb einer
    // finally-Region liegt (unabhaengig von der AST-Attachierung des .Free).
    // NUR fuer den lsWarning-Zweig - kann nie einen Leak (lsError) maskieren.
    class function FreeInFinallyRegionBySource(MethodNode: TAstNode;
      const StrippedLines: TArray<string>; const VarNameLow: string): Boolean; static;
    // SCA001-Inkr.2 (Gross-Triage 2026-07-19, iface-cast-Bucket 15/101): das
    // Objekt wird per Interface-Cast an die Refcount abgegeben ('v := IFoo(b)'
    // bzw. 'Intf := b as IFoo') - der Release gibt es frei, kein Leak.
    // Konvention: Interface-Ident = 'I' + Grossbuchstabe im ORIGINAL-Case
    // (schliesst 'IntToStr(b)' aus).
    class function IsHandedToInterface(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // 'E := ECustom.Create; ... raise E;' - raise uebernimmt Ownership, die
    // RTL gibt das Exception-Objekt im Handler frei (Gross-Triage Batch 8).
    class function IsRaisedAsException(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
    // factory-Bucket 13/101: '<instanz>.CreateXxx(...)' ist eine FACTORY-
    // Methode (Receiver = lokale Var/Param-INSTANZ oder '(x as IFoo)'-Ausdruck),
    // keine direkte Konstruktion - das Result ist typisch fremd-owned. True
    // wenn ALLE Create-Assigns der Var solche Instanz-Factories sind; die Var
    // laeuft dann ueber Pfad 2 ('Rueckgabewert', lsWarning) statt Pfad 1
    // (lsError). bare '.Create' und Metaclass-Receiver (TypeLow endet auf
    // 'class': TFormClass.CreateNew) bleiben Pfad 1.
    class function AllCreatesAreInstanceFactory(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CanBeStrictPrivate, ConsecutiveSection, ConsecutiveVisibility, GroupedDeclaration, MultipleExit, RedundantJump, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uAstSpans;   // Stufe B/I3: Teilbaum-Maximum, vormals lokal als SubtreeMaxLine
    // Bewusst implementation-seitig: das Primitiv wird nur im Rumpf von
    // FreeInFinallyRegionBySource gebraucht, die interface-Huelle dieser Unit
    // muss dafuer nicht wachsen. uAstSpans haengt nur an uAstNode, das die
    // interface-uses hier ohnehin schon fuehrt - kein Zyklus.

// Forward auf die FP-Gates vom 2026-07-31 (Definitionen weiter unten, direkt
// vor der oeffentlichen API). HasFunctionCallAssign braucht den Sink-Matcher
// bereits hier oben fuer das Factory-Gate. AScope = Routine, in der der
// Receiver-Typ aufgeloest wird (darf nil sein -> kein Receiver-Veto).
function SinkCallPassesVar(AScope: TAstNode;
  const ATextOrig, VarNameLow: string): Boolean; forward;

// Ebenfalls weiter unten definiert: prueft, ob NameLow in AScope als lokale
// Variable oder Parameter DEKLARIERT ist. IsPassedToOwner braucht das fuer
// das Zuweisungs-Senken-Gate (Fremdspeicher gegen eigenen Stack-Frame),
// steht aber ueber der Definition.
function ScopeDeclaresIdent(AScope: TAstNode;
  const NameLow: string): Boolean; forward;

// True, wenn ASegLow ein kanonisch NICHT besitzender Container-Zugang ist
// (Items/Objects/Lines/Strings/Data/Nodes). Liest dieselbe Liste wie das
// Receiver-Veto des Aufruf-Pfades - eine Quelle, zwei Nutzer.
function IsNonOwningAccessorSeg(const ASegLow: string): Boolean; forward;

{ ---- Wortgrenz-Hilfsfunktionen ---- }

class function TLeakDetector2.IsIdentChar(C: Char): Boolean;
begin
  // Delegation auf zentralen Helper. Klassen-Wrapper bleibt erhalten, damit
  // bestehende Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

class function TLeakDetector2.IsWholeWord(const Str, Pattern: string;
  Pos_: Integer): Boolean;
var
  pRight: Integer;
begin
  Result := False;
  if Pos_ <= 0 then Exit;
  // Linke Grenze
  if (Pos_ > 1) and IsIdentChar(Str[Pos_ - 1]) then Exit;
  // Rechte Grenze
  pRight := Pos_ + Length(Pattern);
  if (pRight <= Length(Str)) and IsIdentChar(Str[pRight]) then Exit;
  Result := True;
end;

{ ---- Typ-Check ---- }

class function TLeakDetector2.IsLeakyType(const TypeRef: string;
  AContext: TAnalyzeContext): Boolean;
// LeakyClasses ist seit der Konvertierung auf TStringList eine sortierte,
// case-insensitive Liste -> IndexOf liefert >= 0 wenn die Klasse bekannt ist.
// Plus: LeakyClassExcludes-Check als zweites Sicherheitsnetz - falls eine
// Klasse trotz Exclude in LeakyClasses gelandet ist (z.B. durch Discovery
// in einer alten Plugin-Version), wird sie hier nochmal gefiltert.
// TD-1 Inkrement 2c (2026-07-06): die getrackte Liste kommt jetzt via
// CtxLeakyClasses aus dem Scan-Context (inkl. AutoDiscovery-Funde); AContext=nil
// (Tests/Single-File) faellt auf den uSCAConsts-Global zurueck - byte-identisch,
// weil Ctx.LeakyClasses zum Scan-Start == Global-Baseline ist und dieselben
// List-Settings hat. LeakyClassExcludes bleibt vorerst Global (nur LeakyClasses
// ist scan-zeit-mutiert -> Scope von Inkrement 2c).
var
  Clean : string;
  lt    : Integer;
begin
  Result := False;
  // CtxLeakyClasses inline statt lokaler TStringList-Variable: ein geborgter
  // Listen-Verweis in einer lokalen TStringList-Var laesst den Leak-Detektor
  // (dieser hier!) einen MemoryLeak-FP auf die Var melden. Der Helfer ist
  // billig (nil-Check + Feld-Read), Doppelaufruf daher unkritisch.
  if not Assigned(CtxLeakyClasses(AContext)) then Exit;

  Clean := Trim(TypeRef);
  lt    := Pos('<', Clean);
  if lt > 0 then
    Clean := Trim(Copy(Clean, 1, lt - 1));
  if Clean = '' then Exit;

  // Erst Exclude-Check, dann Match-Check
  if Assigned(LeakyClassExcludes) and
     (LeakyClassExcludes.IndexOf(Clean) >= 0) then Exit;

  Result := CtxLeakyClasses(AContext).IndexOf(Clean) >= 0;
end;

{ ---- Create-Erkennung ---- }

class function TLeakDetector2.MatchesCreate(const ATypeRef, ATypeLow: string;
  out CreatePos: Integer): Boolean;
var
  pRight : Integer;
begin
  Result    := False;
  CreatePos := 0;
  CreatePos := Pos('.create', ATypeLow);
  if CreatePos <= 0 then Exit;
  pRight := CreatePos + 7;          // direkt hinter 'create'
  // Fall A: '.Create' am Ende des Ausdrucks (kein Folge-Token)
  if pRight > Length(ATypeLow) then Exit(True);
  // Fall B: '.Create(' / '.Create ' / '.Create;' - non-Ident-Char hinter create
  if not IsIdentChar(ATypeLow[pRight]) then Exit(True);
  // Fall C: '.CreateXxx' - Folge-Zeichen ist im Original-Case ein
  // Grossbuchstabe -> CamelCase-Suffix -> Konstruktor-Variante.
  // Fall D: '.created'/'.creates' - Folge-Zeichen lowercase -> Verb-Form,
  // kein Konstruktor. ATypeRef und ATypeLow haben gleiche Laenge.
  if pRight > Length(ATypeRef) then Exit;          // defensive
  Result := CharInSet(ATypeRef[pRight], ['A'..'Z']);
end;

class function TLeakDetector2.IsOsHandleApiCall(const RhsLow: string): Boolean;
// FP-Gate (2026-07-04): os-handle - Real-World-Audit Sektion 3.2 (6 Faelle):
// mormot.net.sock.pas:2835/3106/3122 `s := socket(...)`, :3230
// `sock := doaccept(...)`, DMVC.Expert.Forms.NewProjectWizard.pas:1039
// `LSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)`. Diese Funktionen
// liefern OS-Handles (Integer/THandle), keine Delphi-Objekte - SCA001 darf
// nur echte Objekt-Konstruktionen melden. Exakter Namensvergleich (kein
// Prefix-Match), damit lokale Factories wie `CreateFileList(...)` weiter
// als potentielles Leak gelten.
const
  // Alle lowercase; Qualifier (`Winapi.Winsock2.socket`) wird vor dem
  // Vergleich abgestreift. A/W-Suffixe der WinAPI explizit gelistet.
  OS_HANDLE_APIS : array[0..38] of string = (
    // BSD-/WinSock-/FPC-Socket-Familie
    'socket', 'accept', 'doaccept', 'wsasocket', 'wsasocketw', 'wsaaccept',
    'fpsocket', 'fpaccept', 'socketpair',
    // Kernel-Objekt-Handles
    'createfile', 'createfilew', 'createfilea',
    'createevent', 'createeventw', 'createeventa',
    'createmutex', 'createmutexw', 'createmutexa',
    'createsemaphore', 'createsemaphorew', 'createsemaphorea',
    'createfilemapping', 'createfilemappingw', 'createfilemappinga',
    'createnamedpipe', 'createnamedpipew', 'createnamedpipea',
    'createiocompletionport',
    'createprocess', 'createprocessw', 'createprocessa',
    'createthread', 'createremotethread',
    'openprocess', 'openthread', 'openevent', 'openmutex', 'openfilemapping',
    // Modul-Handles (HMODULE)
    'loadlibrary');
var
  ParenPos, DotPos, i : Integer;
  Name : string;
begin
  Result := False;
  ParenPos := Pos('(', RhsLow);
  if ParenPos <= 1 then Exit;
  Name := Trim(Copy(RhsLow, 1, ParenPos - 1));
  // Qualifizierten Prefix abschneiden: 'winapi.winsock2.socket' -> 'socket'.
  DotPos := LastDelimiter('.', Name);
  if DotPos > 0 then
    Name := Trim(Copy(Name, DotPos + 1, MaxInt));
  if Name = '' then Exit;
  for i := Low(OS_HANDLE_APIS) to High(OS_HANDLE_APIS) do
    if Name = OS_HANDLE_APIS[i] then Exit(True);
  // 'loadlibraryex'/'loadlibraryexw'/... ueber Prefix, da Suffix-Varianten
  // zahlreich sind und kein Objekt-Konstruktor je so heisst.
  if StartsStr('loadlibrary', Name) then Exit(True);
end;

class function TLeakDetector2.IsOwnerParamCreate(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// FP-Gate (2026-07-04): owner-parameter - Real-World-Audit Sektion 3.2:
// doublecmd foptionshotkeys.pas:687 `CommandsFormClass.Create(Application)`.
// TComponent-Konvention: ein nicht-nil Owner-Argument uebernimmt die
// Freigabe (Components[]-Liste im Owner-Destroy) -> kein Leak-Befund.
// Bewusst eng gefasst: das GESAMTE Argument muss exakt einer der
// kanonischen Owner-Bezeichner sein. Damit fallen keine TPs:
//   TSQLQuery.Create(nil)                -> nil-Owner, Caller muss freigeben
//   TFileStream.Create(Datei, fmOpenRead) -> Parameter sind kein Owner
//   TStringBuilder.Create(8 * Self.Degree) -> Ausdruck, kein Owner-Ident
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  TypeLow : string;
  CreatePos, idx, depth, ArgStart : Integer;
  ArgLow  : string;
begin
  Result  := False;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    TypeLow := A.TypeRef.ToLower;
    if not MatchesCreate(A.TypeRef, TypeLow, CreatePos) then Continue;
    // Hinter '.create' evtl. CamelCase-Suffix ('createnew') ueberspringen,
    // dann Whitespace - danach muss die Argumentklammer folgen.
    idx := CreatePos + 7;  // direkt hinter 'create'
    while (idx <= Length(TypeLow)) and IsIdentChar(TypeLow[idx]) do Inc(idx);
    while (idx <= Length(TypeLow)) and (TypeLow[idx] = ' ') do Inc(idx);
    if (idx > Length(TypeLow)) or (TypeLow[idx] <> '(') then Continue;
    // Argumentliste bis zur passenden schliessenden Klammer extrahieren
    // (Tiefenzaehlung, bounds-safe; unbalancierte RHS -> kein Match).
    ArgStart := idx + 1;
    depth    := 1;
    Inc(idx);
    while (idx <= Length(TypeLow)) and (depth > 0) do
    begin
      if TypeLow[idx] = '(' then Inc(depth)
      else if TypeLow[idx] = ')' then Dec(depth);
      if depth > 0 then Inc(idx);
    end;
    if depth <> 0 then Continue;
    ArgLow := Trim(Copy(TypeLow, ArgStart, idx - ArgStart));
    // Owner steht per TComponent-Konvention an ERSTER Stelle:
    // Create(AOwner[, weitere Args]). Frueher wurde das GESAMTE Argument
    // exakt verglichen -> 'Create(self, id, caption)' (Multi-Arg-Ctor)
    // rutschte durch = FP. Jetzt nur das ERSTE Top-Level-Argument.
    // TP-sicher: dieselbe TComponent-Owner-Annahme wie im Single-Arg-Fall,
    // nur auf Multi-Arg-Konstruktoren erweitert. Verifiziert an
    // TBrowserTab.Create(AOwner: TComponent; id; caption)
    // (class(TTabSheet) -> TComponent -> Owner verwaltet das Lifetime).
    // Erstes Arg extrahieren (Top-Level-Komma; Klammern-Tiefe zaehlen, damit
    // 'Create(TFoo.Create(a,b), c)' nicht am inneren Komma splittet).
    var FirstArg := ArgLow;
    var cp := 1; var d2 := 0;
    while cp <= Length(ArgLow) do
    begin
      if ArgLow[cp] = '(' then Inc(d2)
      else if ArgLow[cp] = ')' then Dec(d2)
      else if (ArgLow[cp] = ',') and (d2 = 0) then
      begin
        FirstArg := Trim(Copy(ArgLow, 1, cp - 1));
        Break;
      end;
      Inc(cp);
    end;
    // Kanonische Owner-Bezeichner - exakter Vergleich des ersten Arguments,
    // damit Teilausdruecke ('8 * self.degree', 'self.owner.tag', 'datei')
    // NICHT matchen.
    if (FirstArg = 'self') or (FirstArg = 'owner') or (FirstArg = 'aowner') or
       (FirstArg = 'application') or (FirstArg = 'self.owner') then
      Exit(True);
  end;
end;

class function TLeakDetector2.CreateRhsIsBorrowedOrLiteral(
  const RhsLow: string): Boolean;
// Autopsie 2026-08-26, Klasse 4 (15 Drops gezaehlt; GETEILT mit SCA009
// via HasCreateAssign - dort inhaltlich identisch richtig: es wird
// kein Objekt des Aufrufers allokiert, also braucht es kein finally):
// (a) anonymes Methoden-Literal ('X := procedure ... end;') - das
//     Closure ist refcount-verwaltet, Free waere ein Compilefehler;
// (b) '.asobject'-Kette (TRttiContext.Create.GetType(..).GetValue(..)
//     .AsObject as TList): der Record-Ctor allokiert nichts, die
//     AsObject-Referenz ist per Definition GEBORGT - Free waere ein
//     Bug im Fremdobjekt. Bewusst eng auf '.asobject' zugeschnitten,
//     KEIN generisches '.create.<Kette>'-Gate: Fluent-APIs
//     (TStringBuilder.Create.Append(...)) BESITZEN ihr Result.
var
  T : string;
  p : Integer;
begin
  T := TrimLeft(RhsLow);
  if (Copy(T, 1, 9) = 'procedure') and
     ((Length(T) = 9) or not TDetectorUtils.IsIdentChar(T[10])) then
    Exit(True);
  if (Copy(T, 1, 8) = 'function') and
     ((Length(T) = 8) or not TDetectorUtils.IsIdentChar(T[9])) then
    Exit(True);
  // Ketten-TAIL-Zuschnitt (Gegenpruefung 2026-08-26 MINOR): '.asobject'
  // gated nur, wenn danach das Statement endet oder ein ' as '-Cast
  // folgt. '.AsObject' INNERHALB von Argumenten
  // ('TWrapper.Create(V.AsObject)' - dort folgt ')') allokiert real;
  // Vorkommen in String-Literalen folgt meist weiterer Text/Quote.
  p := Pos('.asobject', T);
  Result := (p > 0) and
            ((p + 9 > Length(T)) or CharInSet(T[p + 9], [' ', ';']));
end;

class function TLeakDetector2.HasCreateAssign(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Assigns  : TList<TAstNode>;
  A        : TAstNode;
  TypeLow  : string;
  Dummy    : Integer;
begin
  Result  := False;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    // Exakter Namensvergleich (A.Name ist immer der vollständige LHS-Ausdruck)
    if A.Name.ToLower <> VarNameLow then Continue;
    TypeLow := A.TypeRef.ToLower;
    if CreateRhsIsBorrowedOrLiteral(TypeLow) then Continue;
    if MatchesCreate(A.TypeRef, TypeLow, Dummy) then
      Exit(True);
  end;
end;

class function TLeakDetector2.FindCreateLine(MethodNode: TAstNode;
  const VarNameLow: string): Integer;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  TypeLow : string;
begin
  Result  := 0;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    TypeLow := A.TypeRef.ToLower;
    // Geschwisterpfad zu HasCreateAssign - Gate identisch, sonst
    // zeigte die Befund-Zeile auf einen gegateten Nicht-Fund.
    if CreateRhsIsBorrowedOrLiteral(TypeLow) then Continue;
    var Dummy : Integer;
    if MatchesCreate(A.TypeRef, TypeLow, Dummy) then
    begin
      Result := A.Line;
      Exit;
    end;
  end;
end;

class function TLeakDetector2.FindFuncCallAssignLine(MethodNode: TAstNode;
  const VarNameLow: string): Integer;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RHS     : string;
begin
  Result  := 0;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    RHS := A.TypeRef.ToLower;
    if Pos('.create', RHS) > 0 then Continue;
    if (RHS = 'nil') or (RHS = '') then Continue;
    // FP-Gate (2026-07-04): os-handle - dieselben Assigns ueberspringen,
    // die HasFunctionCallAssign nicht als Fund wertet, damit die
    // Befund-Zeile konsistent auf dem echten Ausloeser landet.
    if IsOsHandleApiCall(RHS) then Continue;
    if Pos('(', RHS) > 0 then
    begin
      Result := A.Line;
      Exit;
    end;
  end;
end;

class function TLeakDetector2.HasFunctionCallAssign(UnitNode, MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  ThisClassLow : string;

  // True wenn CalleeLow eine parameterlose Schwester-FUNKTION DERSELBEN
  // Klasse ist, deren Body direkt `Result := <Typ>.Create` macht - also
  // eine echte Factory (Caller bekommt Ownership). Damit wird der
  // klammerlose Aufruf `list := MeineFactory;` als Leak erkannt, OHNE
  // geliehene Property-/Field-Zuweisungen (`list := obj.FList`) oder
  // externe/lazy Getter zu treffen: aufgeloest wird nur exakt
  // `<DieseKlasse>.<Callee>`, und der Body muss DIREKT in Result allokieren
  // (Lazy-Getter `Result := FList` mit `FList := X.Create` matcht NICHT).
  function IsLocalFactory(const CalleeLow: string): Boolean;
  var
    Methods, Assigns : TList<TAstNode>;
    Mth, A           : TAstNode;
    TargetLow, LhsLow: string;
  begin
    Result := False;
    if (ThisClassLow = '') or (CalleeLow = '') then Exit;
    TargetLow := ThisClassLow + '.' + CalleeLow;
    Methods := UnitNode.FindAllRef(nkMethod);
    for Mth in Methods do
    begin
      if Mth.Name.ToLower <> TargetLow then Continue;
      Assigns := Mth.FindAllRef(nkAssign);
      for A in Assigns do
      begin
        LhsLow := A.Name.ToLower;
        if (LhsLow = 'result') or (LhsLow = CalleeLow) then
          if Pos('.create', A.TypeRef.ToLower) > 0 then Exit(True);
      end;
    end;
  end;

  function IsBorrowedReferenceCall(const RhsLower: string): Boolean;
  // Non-Ownership-Prefix-Liste: Calls deren Name mit diesen Prefixen
  // beginnt liefern per Konvention SHARED-Refs (Cache-Getter, Lookups,
  // Finders) und der Caller darf NICHT free-en. Audit-Trigger:
  // TAstNode.FindAll -> 'Source := EnsureCacheFor(AKind);' wurde als
  // Leak gemeldet, obwohl EnsureCacheFor eine geteilte Cache-Liste
  // zurueckgibt.
  // Real-World-Sweep 2026-06-13: 'popup' fuer VCL-Pattern wie
  // PopupComponent(Sender) (TPopupMenu-Property-Lookup, kein Allocator).
  // Real-World-Sweep iter 6: 't<klassenname>' als Type-Cast-Konvention
  // erkennen - `TList<string>(X.AsObject)` ist semantisch identisch zu
  // `X.AsObject as TList<string>`, also Borrow nicht Alloc. Trigger:
  // delphimvcframework Serializer.JsonDataObjects 8 SCA001 FPs.
  const
    BORROWED_PREFIXES : array[0..7] of string =
      ('ensure', 'get', 'find', 'lookup', 'peek', 'cached', 'fetch', 'popup');
  var
    Name : string;
    DotPos, ParenPos, i : Integer;
  begin
    Result := False;
    ParenPos := Pos('(', RhsLower);
    if ParenPos = 0 then Exit;
    // Indexed-Element-Zugriff als Ergebnis borgt das Element - kein Ownership.
    // Real-World 2026-06-26: cnwizards `(AComp as TWinControl).Controls[I]`,
    // `TComponent(FSelection[0])`. Ein `]` am Ausdruck-Ende = Collection-Item.
    if EndsStr(']', TrimRight(RhsLower)) then Exit(True);
    // qualified prefix abschneiden: 'self.ensurecachefor' -> 'ensurecachefor'
    DotPos := LastDelimiter('.', Copy(RhsLower, 1, ParenPos - 1));
    if DotPos > 0 then
      Name := Trim(Copy(RhsLower, DotPos + 1, ParenPos - DotPos - 1))
    else
      Name := Trim(Copy(RhsLower, 1, ParenPos - 1));
    for i := Low(BORROWED_PREFIXES) to High(BORROWED_PREFIXES) do
      if StartsStr(BORROWED_PREFIXES[i], Name) then Exit(True);
    // Pascal-Konvention: `TFoo(X.Field)` ist Type-Cast (semantisch
    // `X.Field as TFoo`), kein Allocator. Heuristik: Name beginnt mit 't'
    // UND ist >= 2 chars UND zweiter char ist Buchstabe UND das Argument
    // enthaelt einen '.' (Property-/Field-Access). Trigger:
    // delphimvcframework Serializer.JsonDataObjects 8 SCA001 FPs auf
    // `lList := TMVCListOfString(AElementValue.AsObject);`.
    if (Length(Name) >= 2) and (Name[1] = 't') and
       CharInSet(Name[2], ['a'..'z']) then
    begin
      var Args := Trim(Copy(RhsLower, ParenPos + 1, Length(RhsLower) - ParenPos));
      // Ein Typecast borgt IMMER eine bestehende Referenz (er allokiert nie).
      // Borrowed wenn das Cast-Argument ein Field-/Property-Access ('.'), ein
      // Collection-Item ('[') ODER ein Accessor-Aufruf ist (Arg beginnt mit
      // get/find/...). Real-World 2026-06-26: cnwizards
      // TComponent(GetComponent(0)), TFont(GetOrdValue), TComponent(FSelection[0]).
      if (Pos('.', Args) > 0) or (Pos('[', Args) > 0) then Exit(True);
      // Bare-Identifier-Argument ('TMVCListOfInteger(AObject)', 'TButton(Comp)')
      // = Cast einer bestehenden Variable/Param -> Borrow, kein Allocator (ein
      // Typecast allokiert nie). Real-World 2026-06-28: delphimvcframework
      // 'lList := TMVCListOfInteger(AObject);'.
      // Args enthaelt noch die schliessende ')' (z.B. 'aobject)') - daher bis
      // zur ersten ')' pruefen, ob das Cast-Argument ein bare Identifier ist.
      var ArgInner := Trim(Copy(Args, 1, Pos(')', Args + ')') - 1));
      var IsBareIdent := ArgInner <> '';
      for var ci := 1 to Length(ArgInner) do
        if not CharInSet(ArgInner[ci], ['a'..'z', '0'..'9', '_']) then
        begin IsBareIdent := False; Break; end;
      if IsBareIdent then Exit(True);
      for i := Low(BORROWED_PREFIXES) to High(BORROWED_PREFIXES) do
        if StartsStr(BORROWED_PREFIXES[i], Args) then Exit(True);
    end;
  end;

  function IsCleanIdent(const S: string): Boolean;
  var i: Integer;
  begin
    Result := S <> '';
    for i := 1 to Length(S) do
      if not CharInSet(S[i], ['a'..'z', '0'..'9', '_']) then Exit(False);
  end;

  // SCA001-Gross-Triage 2026-07-18 ('other'-Bucket, 3x MakePath): die
  // 'Rueckgabewert'-Heuristik meldete Aufrufe von IN-UNIT-Funktionen, deren
  // Return-Typ ein WERT-Typ ist (TFileName=String) - Werttypen koennen nie
  // leaken. Loest den Callee gegen die Unit-Signaturen auf (nkMethod.TypeRef
  // Format 'kind[:ret];dir..', uParser2 ~Z.1180) und prueft den Return-Typ
  // gegen die Werttyp-Liste. Konservativ: nur unqualifizierte/Self-Callees;
  // bei Overloads muessen ALLE Treffer Werttypen liefern; nicht aufloesbar
  // -> False (Fund bleibt). TP-safe-by-construction.
  function ReturnsValueType(const RhsLower: string): Boolean;
    function IsValueTypeName(const R: string): Boolean;
    const
      // EXPLIZITE Listen statt EndsStr('string',..): eine KLASSE 'TMyString'
      // endet auch auf 'string' und wuerde faelschlich als Wert gelten ->
      // maskierter Leak (Review-Fang 2026-07-18). Exotische Aliase (tbtstring)
      // bleiben dann eben gemeldet - FP statt FN, richtiger Trade auf error-Tier.
      VALS : array[0..32] of string = (
        'integer','cardinal','int64','uint64','boolean','byte','word',
        'smallint','shortint','longint','longword','nativeint','nativeuint',
        'single','double','extended','currency','real',
        'tdatetime','tdate','ttime','char','widechar','variant','tfilename',
        'string','ansistring','widestring','unicodestring',
        'rawbytestring','utf8string','shortstring','openstring');
    var i : Integer;
    begin
      if R = '' then Exit(False);
      for i := Low(VALS) to High(VALS) do
        if R = VALS[i] then Exit(True);
      Result := False;
    end;
  var
    Head, Callee, TRef, Ret : string;
    pp, dp, cp, sp : Integer;
    Methods : TList<TAstNode>;
    Mth : TAstNode;
    Found : Boolean;
  begin
    Result := False;
    pp := Pos('(', RhsLower);
    if pp <= 1 then Exit;
    Head := Trim(Copy(RhsLower, 1, pp - 1));
    dp := LastDelimiter('.', Head);
    if dp > 0 then
    begin
      // Nur 'self.'-Qualifier zulassen - fremd-qualifizierte Calls koennten
      // eine gleichnamige Funktion einer ANDEREN Unit meinen (Fehl-Resolve).
      if Copy(Head, 1, dp - 1) <> 'self' then Exit;
      Callee := Copy(Head, dp + 1, MaxInt);
    end
    else
      Callee := Head;
    if not IsCleanIdent(Callee) then Exit;
    Found := False;
    Methods := UnitNode.FindAllRef(nkMethod);
    for Mth in Methods do
    begin
      var MLow := Mth.Name.ToLower;
      if (MLow <> Callee) and not EndsStr('.' + Callee, MLow) then Continue;
      TRef := Mth.TypeRef.ToLower;
      cp := Pos(':', TRef);
      if cp = 0 then Continue;                 // procedure-Homonym: kein Ret-Typ
      sp := Pos(';', TRef);
      if sp = 0 then sp := Length(TRef) + 1;
      if sp <= cp then Continue;               // ':' gehoert zu Direktiven-Teil
      Ret := Trim(Copy(TRef, cp + 1, sp - cp - 1));
      if IsValueTypeName(Ret) then
        Found := True
      else
        Exit(False);                           // Objekt-Overload existiert -> unsicher
    end;
    Result := Found;
  end;

  // FP-Gate (borrowed-reference, 2026-07-11, Real-World-Audit): die
  // "Rueckgabewert"-Heuristik wertete JEDEN Funktionsaufruf mit '(' als
  // Ownership-Return und meldete ihn als potentielles Leak. Getter wie
  // CnOtaGetRootComponentFromEditor(...) oder Images.Bitmap(...) liefern
  // aber GEBORGTE Objekte (IDE-Form-Root, ImageList-Cache), deren Free ein
  // Bug waere. Ownership gibt nur ab, wer konstruktor-artig heisst (Wurzel
  // Create/New/Clone/Make/Acquire - exakt, als CamelCase-Prefix 'MakeList'
  // oder als CamelCase-Suffix 'DoCreate') ODER eine bewiesene lokale Factory
  // ist (Body allokiert direkt in Result). Direkte '.Create' laufen ueber
  // HasCreateAssign/Pfad 1 und bleiben Fund (die realen TPs sind alle .Create).
  // RhsOrig ist die Original-Case-RHS (A.TypeRef) - die CamelCase-Grenze
  // laesst sich nur im Original erkennen ('NewsFeed' != 'NewFeed').
  function OwningReturnCall(const RhsOrig: string): Boolean;
  const
    ROOTS : array[0..4] of string = ('create', 'new', 'clone', 'make', 'acquire');
  var
    pp, dp, rl, sp : Integer;
    Head, Callee, CalleeLow, root : string;
  begin
    Result := False;
    pp := Pos('(', RhsOrig);
    if pp <= 1 then Exit;
    // Callee-Identifier (Original-Case) vor der ersten '(' isolieren;
    // qualifizierten Prefix abstreifen ('images.bitmap(' -> 'bitmap').
    Head := Copy(RhsOrig, 1, pp - 1);
    dp := LastDelimiter('.', Head);
    if dp > 0 then
      Callee := Trim(Copy(Head, dp + 1, MaxInt))
    else
      Callee := Trim(Head);
    CalleeLow := Callee.ToLower;
    if CalleeLow = '' then Exit;
    // (a) konstruktor-artiger Name: Wurzel exakt, als CamelCase-Prefix
    //     ('MakeList'/'NewFoo') oder als CamelCase-Suffix ('DoCreate').
    //     Die Grossbuchstaben-Grenze im Original schuetzt vor Substring-
    //     Zufaellen ('NewsFeed', 'Remake') die keine echten Konstruktoren sind.
    for root in ROOTS do
    begin
      rl := Length(root);
      if CalleeLow = root then Exit(True);
      if (Length(CalleeLow) > rl) and StartsStr(root, CalleeLow) and
         CharInSet(Callee[rl + 1], ['A'..'Z', '0'..'9']) then
        Exit(True);
      if (Length(CalleeLow) > rl) and EndsStr(root, CalleeLow) then
      begin
        sp := Length(Callee) - rl + 1;
        if (sp >= 1) and CharInSet(Callee[sp], ['A'..'Z']) then
          Exit(True);
      end;
    end;
    // (b) bewiesene lokale Factory DERSELBEN Klasse (Body: Result := X.Create).
    //     Erhaelt die TP-Erkennung fuer named Factories die MIT Klammern
    //     aufgerufen werden ('list := BuildList()' mit Result := TFoo.Create).
    if IsCleanIdent(CalleeLow) and IsLocalFactory(CalleeLow) then
      Exit(True);
  end;

  // FP-Gate (2026-07-31, FP-Klasse 2 'Factory-Rueckgaben', 30%-Real-World-Audit):
  // Callee-Name (lowercase, ohne Qualifier) aus einer RHS mit Klammern.
  function CalleeNameLow(const RhsLower: string): string;
  var
    pp, dp : Integer;
  begin
    Result := '';
    pp := Pos('(', RhsLower);
    if pp <= 1 then Exit;
    Result := Trim(Copy(RhsLower, 1, pp - 1));
    dp := LastDelimiter('.', Result);
    if dp > 0 then Result := Trim(Copy(Result, dp + 1, MaxInt));
  end;

  // FP-Gate (2026-07-31, FP-Klasse 2 'Factory-Rueckgaben', 5/24 im Sample):
  // eine Factory DERSELBEN Unit gibt KEIN Ownership ab, wenn sie
  //   (a) ihr Result selbst in eine besitzende Struktur haengt
  //       ('Insert(i, Result)' in TProc.AddMemData - cnwizards DasmProc.pas:238),
  //       ODER
  //   (b) einen Owner-Parameter fuehrt und die Aufrufstelle dort kein nil
  //       uebergibt ('CreateDBFieldControl(..., AControl, ...)' -
  //       jvcl JvDynControlEngineDB.pas:515; VCL-Owner raeumt auf).
  // Genau EINE Ebene, kein transitives Inlining. Monoton: kann den Fund nur
  // unterdruecken, nie einen neuen erzeugen.
  //
  // Review-Fund 2026-07-31 ("loest den Callee klassenuebergreifend auf und
  // nimmt den ERSTEN Treffer - bei Homonymen in Fremdklassen falsch"): frueher
  // genuegte IRGENDEINE gleichnamige Methode der Unit; 'TWidgetFactory.
  // CreateWidget(AOwner: TComponent)' konnte den Fund fuer den Aufruf von
  // 'TDataFactory.CreateWidget' stillstellen. Jetzt wird der Callee ZUERST in
  // der EIGENEN Klasse gesucht (Klassen-Qualifikation, gleiche Regel wie
  // IsLocalFactory); nur wenn die eigene Klasse den Namen nicht kennt, zaehlt
  // eine unitweit EINDEUTIGE Aufloesung. Mehrere Kandidaten (Homonym in einer
  // Fremdklasse, Overloads) = konservativ NICHT gaten.
  // Kandidat muss einen Rumpf haben (nkBlock): sonst wuerde die
  // Interface-Signatur derselben Routine als zweiter Kandidat zaehlen und die
  // Eindeutigkeit immer scheitern lassen.
  function CalleeKeepsOwnership(const CalleeLow, RhsLower: string): Boolean;

    function HasBody(ANode: TAstNode): Boolean;
    var
      Ch : TAstNode;
    begin
      Result := False;
      for Ch in ANode.Children do
        if Ch.Kind = nkBlock then Exit(True);
    end;

  var
    Methods         : TList<TAstNode>;
    Mth, Cand, P, N, C : TAstNode;
    Stack           : TList<TAstNode>;
    MLow, TargetLow, PName, PType : string;
    CandCount       : Integer;
    HasOwnerParam   : Boolean;
  begin
    Result := False;
    if (CalleeLow = '') or (UnitNode = nil) then Exit;
    Methods   := UnitNode.FindAllRef(nkMethod);
    Cand      := nil;
    CandCount := 0;
    // Stufe 1: Implementierung DERSELBEN Klasse ('tmeineklasse.callee').
    if ThisClassLow <> '' then
    begin
      TargetLow := ThisClassLow + '.' + CalleeLow;
      for Mth in Methods do
        if (Mth.Name.ToLower = TargetLow) and HasBody(Mth) then
        begin
          Inc(CandCount);
          Cand := Mth;
        end;
    end;
    // Stufe 2: eigene Klasse kennt den Namen nicht -> unitweite Aufloesung,
    // aber nur wenn sie EINDEUTIG ist.
    if CandCount = 0 then
      for Mth in Methods do
      begin
        MLow := Mth.Name.ToLower;
        if (MLow <> CalleeLow) and not EndsStr('.' + CalleeLow, MLow) then Continue;
        if not HasBody(Mth) then Continue;
        Inc(CandCount);
        Cand := Mth;
      end;
    if (CandCount <> 1) or (Cand = nil) then Exit;

    // (a) Body haengt das eigene Result in eine besitzende Struktur.
    Stack := TList<TAstNode>.Create;
    try
      Stack.Add(Cand);
      while Stack.Count > 0 do
      begin
        N := Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if SinkCallPassesVar(Cand, N.Name, 'result') or
           SinkCallPassesVar(Cand, N.TypeRef, 'result') then
          Exit(True);            // finally gibt Stack frei
        for C in N.Children do Stack.Add(C);
      end;
    finally
      Stack.Free;
    end;
    // (b) Owner-Parameter in der Signatur. Die Aufrufstelle darf kein 'nil'
    //     enthalten - sonst ist der Owner moeglicherweise leer und der
    //     Aufrufer doch zustaendig (konservativ: Gate feuert dann nicht).
    if TDetectorUtils.ContainsWholeWordLower('nil', RhsLower) then Exit;
    HasOwnerParam := False;
    // NUR direkte Kinder: FindAllRef waere subtree-weit und wuerde die
    // Parameter verschachtelter Routinen mitzaehlen (Fehl-Suppression).
    for P in Cand.Children do
    begin
      if P.Kind <> nkParam then Continue;
      PName := P.Name.ToLower;
      for var Mod_ in ['var ', 'const ', 'out '] do
        if StartsStr(Mod_, PName) then
          PName := Trim(Copy(PName, Length(Mod_) + 1, MaxInt));
      PType := Trim(P.TypeRef.ToLower);
      if (PName = 'aowner') or (PName = 'owner') or (PType = 'tcomponent') then
      begin
        HasOwnerParam := True;
        Break;
      end;
    end;
    Result := HasOwnerParam;
  end;

var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RHS     : string;
begin
  Result  := False;
  // Klasse der analysierten Methode ('tmeineklasse.foo' -> 'tmeineklasse').
  // Vorletztes Segment, nicht alles-vor-dem-letzten-Punkt: bei nested types
  // ('TOuter.TInner.DoIt') ergaebe Letzteres den gepunkteten Key
  // 'touter.tinner', der gegen keinen Typnamen matcht - der darauf gestuetzte
  // Ownership-Guard fiele still aus (2026-07-27).
  ThisClassLow := TDetectorUtils.OwnerTypeNameLower(MethodNode.Name);

  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    RHS := A.TypeRef.ToLower;
    if Pos('.create', RHS) > 0 then Continue;  // durch HasCreateAssign abgedeckt
    if (RHS = 'nil') or (RHS = '') then Continue;
    // Expliziter Aufruf mit Klammern: GetList()
    if Pos('(', RHS) > 0 then
    begin
      // Non-Ownership-Calls (Ensure*/Get*/Find*/...) ueberspringen.
      if IsBorrowedReferenceCall(RHS) then Continue;
      // FP-Gate (2026-07-04): os-handle - socket()/accept()/CreateFile()
      // & Co. liefern OS-Handles, keine Delphi-Objekte -> kein SCA001.
      if IsOsHandleApiCall(RHS) then Continue;
      // Werttyp-Return (Gross-Triage 2026-07-18): in-unit-Funktion liefert
      // String/Ordinal/Record-Wert ('MakePath: TFileName') - kann nie leaken.
      if ReturnsValueType(RHS) then Continue;
      // FP-Gate (borrowed-reference, 2026-07-11): nur konstruktor-artige
      // Callees / bewiesene lokale Factories geben Ownership ab; geborgte
      // Getter (CnOtaGetRootComponentFromEditor, Images.Bitmap) NICHT.
      if OwningReturnCall(A.TypeRef) then
      begin
        // FP-Gate (2026-07-31): same-unit-Factory behaelt das Ownership
        // (Result landet in einer eigenen Liste / Owner-Parameter).
        if CalleeKeepsOwnership(CalleeNameLow(RHS), RHS) then Continue;
        Exit(True);
      end;
      Continue;
    end;
    // Ohne '(': normalerweise geliehene Referenz ('list := obj.FList'
    // / 'list := SomeProperty') - KEIN Ownership-Transfer. AUSNAHME:
    // ein klammerloser Aufruf einer parameterlosen Schwester-FACTORY
    // DERSELBEN Klasse ('list := MeineFactory;' mit
    // `Result := TFoo.Create` im Body) IST ein Leak. Wir loesen nur
    // bare bzw. `Self.`-qualifizierte Identifier auf (eindeutig eigene
    // Klasse); echte Fields/Properties/externe Getter matchen nicht.
    var RhsId := Trim(RHS);
    if StartsStr('self.', RhsId) then RhsId := Copy(RhsId, 6, MaxInt);
    if IsCleanIdent(RhsId) and IsLocalFactory(RhsId) then
    begin
      // FP-Gate (2026-07-31): auch die klammerlose Schwester-Factory kann das
      // Ownership behalten (Result wird intern in eine Liste gehaengt).
      if CalleeKeepsOwnership(RhsId, RHS) then Continue;
      Exit(True);
    end;
  end;
end;

{ ---- Ownership-Transfer-Erkennung ---- }

class function TLeakDetector2.IsReturnedAsResult(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// Akzeptiert:
//   'Result := varname'         (moderner Stil)
//   'Result := varname as ITyp' (explicit cast)
//   '<funcname> := varname'     (legacy Delphi/Pascal: Funktionsname
//                                als implizite Ergebnis-Variable)
//
// Vorher: Wortgrenzen-Substring-Check matched auch 'Result := L.Count'
// (L ist drin, aber als Receiver, NICHT als Result-Wert) und unterdrueckte
// damit echte Leaks (Parser_IfdefDuplicatedHeaders / Real-World-Code).
// Falls jemand 'Result := SomeWrapper(L)' nutzt: das matched nicht mehr,
// L wird als Leak gemeldet - bewusster Tradeoff (besser ein False-Positive
// auf wrap-then-return als ein verstecktes Leak).
//
// FP-Fix (doublecmd torrent/BDecode.pas:bdecodeHash): legacy Pascal-Code
// nutzt 'bdecodeHash := r;' statt 'Result := r;'. Detector hat das
// vorher als Leak gemeldet weil nur 'Result :=' anerkannt war.
var
  Assigns        : TList<TAstNode>;
  A              : TAstNode;
  LhsLow         : string;
  Trimmed        : string;
  FuncNameLow    : string;

  function IsResultLhs(const ALhsLow: string): Boolean;
  begin
    // 'Result' oder Funktionsname selbst (legacy Pascal-Return).
    Result := (ALhsLow = 'result') or
              ((FuncNameLow <> '') and (ALhsLow = FuncNameLow));
  end;

begin
  Result      := False;
  FuncNameLow := '';
  if MethodNode <> nil then
  begin
    // Method.Name kann 'TFoo.Bar' sein - rightmost Identifier extrahieren.
    FuncNameLow := MethodNode.Name.ToLower;
    var DotPos := -1;
    for var i := Length(FuncNameLow) downto 1 do
      if FuncNameLow[i] = '.' then begin DotPos := i; Break; end;
    if DotPos > 0 then
      FuncNameLow := Copy(FuncNameLow, DotPos + 1, MaxInt);
  end;

  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    LhsLow := A.Name.ToLower;
    if not IsResultLhs(LhsLow) then Continue;
    Trimmed := Trim(A.TypeRef.ToLower);
    // Exakter Match: 'Result := varname'
    if Trimmed = VarNameLow then Exit(True);
    // Explicit cast: 'Result := varname as IFoo' (mit/ohne Whitespace
    // - JoinTokInto produziert ' as ', aber legacy-Parser-Output kann
    // weiterhin 'asIFoo' liefern - beide tolerieren).
    if Trimmed.StartsWith(VarNameLow + ' as ') then Exit(True);
    if Trimmed.StartsWith(VarNameLow) and
       (Length(Trimmed) >= Length(VarNameLow) + 3) and
       (Trimmed[Length(VarNameLow) + 1] = 'a') and
       (Trimmed[Length(VarNameLow) + 2] = 's') and
       CharInSet(Trimmed[Length(VarNameLow) + 3], ['a'..'z', '_']) then
      Exit(True);
  end;

  // A: modernes 'Exit(varname)' = Result-Transfer + Sprung. Parser legt
  // das als nkExit ab (uParser2 Zeile ~1170), Argument in TypeRef.
  // Quelle: doublecmd-Audit, 825 Exit-Calls.
  var Exits : TList<TAstNode>;
  var ArgLow : string;
  Exits := MethodNode.FindAllRef(nkExit);
  for A in Exits do
  begin
    ArgLow := LowerCase(Trim(A.TypeRef));
    if ArgLow = '' then Continue;  // 'Exit;' ohne Argument
    if ArgLow = VarNameLow then Exit(True);
    // Exit(list as IFoo) - explicit cast wie bei Result := list as IFoo
    if ArgLow.StartsWith(VarNameLow + ' as ') then Exit(True);
  end;
end;

class function TLeakDetector2.IsAssignedToOutParam(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// ZWEITER KANONISCHER RUECKGABEWEG (T3-Backlog, belegt an Alcinoe:4628
// 'out TArray<TItem>'): eine Prozedur gibt das erzeugte Objekt nicht ueber
// Result zurueck, sondern ueber einen out-/var-Parameter.
//
//   procedure BuildItems(out AItems: TObjectList<TItem>);
//   begin
//     AItems := TObjectList<TItem>.Create;   // <- kein Leck, der Aufrufer
//   end;                                     //    besitzt es danach
//
// Akzeptiert beide Formen:
//   'AParam := L'        direkte Rueckgabe
//   'AParam[i] := L'     Einhaengen in einen Rueckgabe-Container
//
// STRIKT NUR out/var. Bei einem const- oder Wertparameter bleibt die
// Referenz beim Aufgerufenen - dort WAERE es ein echtes Leck, und genau
// deshalb darf das Gate die Modifier nicht ignorieren. Der Parser legt sie
// als Namens-PRAEFIX ab ('out AItems'), nicht im TypeRef.
//
// Korpus-Messung after126: 29 der 1.116 SCA001-Funde (2,6 %) - klein, aber
// Error-Tier: ein falscher Leak-Befund kostet mehr Vertrauen als ein
// falscher Hint.
var
  OutParams : TStringList;
  Params    : TList<TAstNode>;
  Assigns   : TList<TAstNode>;
  P, A      : TAstNode;
  Nm, LhsLow, RhsLow, Base : string;
  SpaceIdx, BrIdx : Integer;
begin
  Result := False;
  if MethodNode = nil then Exit;
  OutParams := TStringList.Create;
  Params    := MethodNode.FindAll(nkParam);
  try
    for P in Params do
    begin
      Nm := Trim(P.Name);
      // 'out X' / 'var X' - alles andere (const, Wert) ist KEIN Rueckgabeweg.
      if not (Nm.ToLower.StartsWith('out ') or Nm.ToLower.StartsWith('var ')) then
        Continue;
      SpaceIdx := LastDelimiter(' ', Nm);
      if SpaceIdx <= 0 then Continue;
      OutParams.Add(LowerCase(Copy(Nm, SpaceIdx + 1, MaxInt)));
    end;
    if OutParams.Count = 0 then Exit;

    Assigns := MethodNode.FindAllRef(nkAssign);
    for A in Assigns do
    begin
      RhsLow := Trim(A.TypeRef.ToLower);
      if RhsLow <> VarNameLow then Continue;
      LhsLow := Trim(A.Name.ToLower);
      // 'AItems[i]' -> 'aitems'
      Base   := LhsLow;
      BrIdx  := Pos('[', Base);
      if BrIdx > 0 then Base := Trim(Copy(Base, 1, BrIdx - 1));
      if OutParams.IndexOf(Base) >= 0 then Exit(True);
    end;
  finally
    // Assigns wird NICHT freigegeben und auch nicht genullt: FindAllRef
    // liefert eine GELIEHENE Liste (der Knoten besitzt sie), anders als
    // FindAll bei Params. Ein `Assigns := nil` hier waere eine tote
    // Zuweisung - der Compiler weist sie zu Recht ab (H2077).
    Params.Free;
    OutParams.Free;
  end;
end;

{ ---- Ownership-Container: Whitelist + Unit-lokale Alias-Aufloesung -------- }

const
  // Ownership-bewusste RTL-/VCL-Container - die Default-Container, die
  // wirklich Free auf ihre Items rufen. Bis 2026-07-31 lokal in
  // AddReceiverOwnsItems; hochgezogen, damit die Alias-Aufloesung
  // (UnitTypeIsOwningContainer) GENAU DIESELBE Liste benutzt.
  OWNING_PREFIXES : array[0..6] of string = (
    'tobjectlist',         // TObjectList<T>(True), TObjectList(True)
    'tobjectdictionary',   // TObjectDictionary
    'tobjectqueue',
    'tobjectstack',
    'tcomponentlist',      // VCL
    'townedcollection',    // VCL
    'tinterfacelist'       // refcount-managed - effektiv ownership-aequiv
  );

function OwningContainerTypeLow(const TypeLow: string): Boolean;
// Strenge Word-Boundary-Pruefung: 'tobjectlist' matched 'tobjectlist',
// 'tobjectlist<tfoo>' und 'tobjectlist(true)' aber NICHT 'tobjectlistview'
// oder 'tobjectlisthelper' (gibt es z.B. in Spring4D / mORMot Erweiterungen).
// Vorher Pos-Match-am-Anfang ohne Boundary -> false-positive Ownership-
// Annahme bei jeder Klasse die mit Prefix anfaengt.
var
  prefix : string;
  pLen   : Integer;
  NextCh : Char;
begin
  Result := False;
  for prefix in OWNING_PREFIXES do
  begin
    if Pos(prefix, TypeLow) <> 1 then Continue;
    pLen := Length(prefix);
    if Length(TypeLow) = pLen then Exit(True); // exakter Match
    NextCh := TypeLow[pLen + 1];
    // Nach dem Prefix muss ein Nicht-Identifier-Char stehen (Generic-
    // Bracket, Klammer, Whitespace, etc.) - sonst ist's ein laengerer
    // Klassenname.
    if not CharInSet(NextCh, ['a'..'z', '0'..'9', '_']) then
      Exit(True);
  end;
end;

// Erstes Ident einer Typ-Referenz, lowercase, ohne Unit-Qualifier und ohne
// Generic-Suffix. Deckt BEIDE Ablageformen des Parsers ab:
//   * nkTypeAlias.TypeRef  = space-separierte IDENT-Kette der rechten Seite
//     ('TPeople = TObjectList<TPerson>' -> 'TObjectList TPerson'),
//   * nkClass.TypeRef      = space-separierte Elternliste, Basisklasse zuerst
//     ('class(TObjectList<TPerson>)' -> 'TObjectList'; Generic-Args liegen im
//     additiven nkGenericArgs-Marker, nicht im TypeRef).
// REICHWEITENGRENZE: bei einem QUALIFIZIERTEN Alias
// ('TPeople = System.Generics.Collections.TObjectList<TPerson>') verwirft der
// Parser die Punkte, das erste Ident ist dann der Unit-Qualifier - die
// Aufloesung scheitert und der Fund bleibt stehen (FN-freundlich, nie ein
// zusaetzlicher Fund).
function FirstTypeIdentLow(const ATypeRef: string): string;
var
  p : Integer;
begin
  Result := Trim(ATypeRef);
  p := Pos('<', Result);
  if p > 0 then Result := Trim(Copy(Result, 1, p - 1));
  p := Pos(' ', Result);
  if p > 0 then Result := Trim(Copy(Result, 1, p - 1));
  p := LastDelimiter('.', Result);
  if p > 0 then Result := Trim(Copy(Result, p + 1, MaxInt));
  Result := Result.ToLower;
end;

// True wenn ANameLow in DIESER Unit (transitiv, max. ADepth Stufen) auf einen
// besitzenden Container zurueckgefuehrt werden kann - egal ob per Alias
// ('X = TObjectList<T>') oder per Ableitung ('X = class(TObjectList<T>)').
//
// HOMONYME: nur Deklarationen DER GESCANNTEN UNIT zaehlen (kein
// TTypeIndex - der ist korpusweit und 'TPeople' existiert dort dreifach:
// Alias, class(TObjectList<TPerson>), class(TMVCActiveRecord)). Innerhalb
// einer Unit ist der Name eindeutig; sollte eine Unit ihn dennoch mehrfach
// fuehren (IFDEF-Zwillinge), genuegt EIN besitzender Treffer - das ist die
// konservativ-permissive Richtung des Gates (mehr Unterdrueckung, nie ein
// zusaetzlicher Fund).
function UnitTypeIsOwningContainer(AUnitNode: TAstNode;
  const ANameLow: string; ADepth: Integer): Boolean;
const
  DECL_KINDS : array[0..1] of TNodeKind = (nkTypeAlias, nkClass);
var
  Lst  : TList<TAstNode>;
  N    : TAstNode;
  Base : string;
  k    : Integer;
begin
  Result := False;
  if (AUnitNode = nil) or (ANameLow = '') or (ADepth <= 0) then Exit;
  for k := Low(DECL_KINDS) to High(DECL_KINDS) do
  begin
    Lst := AUnitNode.FindAllRef(DECL_KINDS[k]);
    for N in Lst do
    begin
      if N.Name.ToLower <> ANameLow then Continue;
      Base := FirstTypeIdentLow(N.TypeRef);
      if (Base = '') or (Base = ANameLow) then Continue;   // Selbstbezug
      if OwningContainerTypeLow(Base) then Exit(True);
      if UnitTypeIsOwningContainer(AUnitNode, Base, ADepth - 1) then Exit(True);
    end;
  end;
end;

class function TLeakDetector2.AddReceiverOwnsItems(MethodNode: TAstNode;
  const ReceiverNameLow: string; AUnitNode: TAstNode): Boolean;
// Pflicht-Whitelist: Receiver-Typ matched einen ownership-bewussten
// Container (OWNING_PREFIXES) ODER loest in der Unit auf einen solchen auf.

  function FindReceiverType(Kind: TNodeKind; out TypeLow: string): Boolean;
  var
    Lst : TList<TAstNode>;
    N   : TAstNode;
    NameLow, NameRaw : string;
  begin
    Result := False;
    TypeLow := '';
    Lst := MethodNode.FindAllRef(Kind);
    for N in Lst do
    begin
      NameRaw := N.Name;
      // Param-Knoten koennen 'var x'/'const x'/'out x' als Name haben.
      // Wir wollen den nackten Identifier vergleichen.
      for var Mod_ in ['var ', 'const ', 'out '] do
        if NameRaw.ToLower.StartsWith(Mod_) then
          NameRaw := Copy(NameRaw, Length(Mod_) + 1, MaxInt);
      NameLow := NameRaw.ToLower;
      if NameLow = ReceiverNameLow then
      begin
        TypeLow := N.TypeRef.ToLower;
        Exit(True);
      end;
    end;
  end;

var
  TypeLow : string;
begin
  // Default permissiv: Typ unbekannt -> alte Behavior beibehalten
  // (Add gilt als ownership-Transfer). Verhindert Regression bei
  // FList.Add-Mustern wo der Field-Typ nicht in MethodNode steht.
  Result := True;

  // Typ aus Local-Var oder Parameter aufloesen.
  if FindReceiverType(nkLocalVar, TypeLow) or
     FindReceiverType(nkParam, TypeLow) then
  begin
    if TypeLow = '' then Exit;                    // sollte nicht passieren, defensiv
    Result := OwningContainerTypeLow(TypeLow);    // strikte Pruefung gegen Whitelist
    // REGRESSIONSFALL 2026-07-31 (Parser-Gate-Backlog 4e/2): der Typ ist
    // aufloesbar, matcht die Whitelist aber nicht, weil die Unit ihn als
    // Alias/Ableitung eines besitzenden Containers fuehrt
    // ('TPeople = TObjectList<TPerson>', delphimvcframework DAL.pas).
    // Vor dem Parser-Fix war der Typ unbekannt -> permissiver Pfad -> kein
    // Fund; erst das MEHR an Typwissen erzeugte den FP. Nur bei uebergebenem
    // Unit-Knoten (SCA001-Pfad), damit SCA008 unveraendert bleibt.
    if not Result then
      Result := UnitTypeIsOwningContainer(AUnitNode,
                  FirstTypeIdentLow(TypeLow), 6);
  end;
end;

class function TLeakDetector2.IsPassedToOwner(MethodNode: TAstNode;
  const VarNameLow: string; AUnitNode: TAstNode): Boolean;
var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  Inh     : TList<TAstNode>;
  N       : TAstNode;
  NameLow : string;
  pCreate : Integer;
  ParentLHS : string;

  function VarInArgs(const CallName: string; AfterPos: Integer): Boolean;
  // Prüft ob VarNameLow als Wort nach Position AfterPos in CallName vorkommt.
  // Inkr.3-Fix: ALLE Substring-Treffer pruefen, nicht nur den ersten - bei
  // 'insertnode(..., pfileinfo(fi))' liegt der erste 'fi'-Treffer INNERHALB
  // von 'pfileinfo' (keine Wortgrenze) und das echte Cast-Arg '(fi)' wurde
  // verpasst. Nur in Ownership-Gates genutzt -> mehr Treffer = nur mehr
  // Suppression (monoton).
  var
    p: Integer;
  begin
    Result := False;
    p := PosEx(VarNameLow, CallName, AfterPos);
    while p > 0 do
    begin
      if IsWholeWord(CallName, VarNameLow, p) then Exit(True);
      p := PosEx(VarNameLow, CallName, p + 1);
    end;
  end;

  function IsForeignIndexedTarget(const ALhsOrig: string): Boolean;
  // Ist die linke Seite EXAKT die Form 'X[..]' - ein indiziertes Ziel, das
  // den eigenen Stack-Frame verlaesst? Nur dann ist die Index-Zuweisung
  // eine Ownership-Abgabe.
  //
  // VERANKERT an der LETZTEN Klammergruppe und am ']'-Ende (Review-Blocker
  // 2026-08-18): die erste Fassung nahm die ERSTE Klammer und verlangte
  // kein ']' am Schluss. Damit unterdrueckte sie auch
  //   'Pages[i].PopupMenu := pm'        (Property-Zuweisung an ein
  //                                      indiziertes Element - kein Transfer)
  // und sah bei
  //   'Grid.Rows[i].Objects[j] := Obj'  (echter Empfaenger: Objects)
  // nie das Veto-Segment der letzten Gruppe - ausgerechnet den Kanal, ueber
  // den laut A/B-Messung ALLE 14 Korpus-Rueckkehrer liefen. Beides
  // maskierte Error-Tier-Lecks.
  //
  // Entscheidung jetzt in vier Schritten:
  //   1. Form: endet auf ']', letzte Gruppe rueckwaerts balanciert.
  //   2. Veto: das letzte Punkt-Segment VOR dieser Gruppe (ohne Cast-/
  //      Klammeranteile) darf kein kanonisch nicht-besitzender Zugang sein
  //      (Items/Objects/Lines/Strings/Data/Nodes).
  //   3. Punktkette oder Cast im Praefix -> dereferenziert -> fremd.
  //   4. Blanke Wurzel: 'Var[i] := Var' und lokale Arrays (auch
  //      'arr[i][j]') bleiben Funde - der Frame stirbt mitsamt Array.
  var
    S       : string;
    Prefix  : string;
    SegLow  : string;
    RootLow : string;
    Depth   : Integer;
    OpenPos : Integer;
    i, p    : Integer;
  begin
    Result := False;
    // Token-Abstaende normalisieren (Review-Verdacht: JoinTokInto kann
    // Leerraum zwischen Tokens einfuegen; 'arr [0]' ist dieselbe Form).
    S := LowerCase(Trim(ALhsOrig));
    S := StringReplace(S, ' [', '[', [rfReplaceAll]);
    S := StringReplace(S, '[ ', '[', [rfReplaceAll]);
    S := StringReplace(S, ' ]', ']', [rfReplaceAll]);
    S := StringReplace(S, ' .', '.', [rfReplaceAll]);
    S := StringReplace(S, '. ', '.', [rfReplaceAll]);

    // 1. Form: 'X[..]' - mindestens 'a[x]', und die Zuweisung geht IN die
    // Klammergruppe, nicht an eine Property dahinter.
    if (Length(S) < 4) or (S[Length(S)] <> ']') then Exit;
    Depth := 0;
    OpenPos := 0;
    for i := Length(S) downto 1 do
      case S[i] of
        ']': Inc(Depth);
        '[': begin
               Dec(Depth);
               if Depth = 0 then
               begin
                 OpenPos := i;
                 Break;
               end;
             end;
      end;
    if OpenPos < 2 then Exit;         // unbalanciert oder kein Wurzelname
    Prefix := Copy(S, 1, OpenPos - 1);

    // 2. Veto auf dem Empfaenger der LETZTEN Gruppe.
    SegLow := Prefix;
    p := LastDelimiter('.', SegLow);
    if p > 0 then SegLow := Copy(SegLow, p + 1, MaxInt);
    p := Pos('[', SegLow);
    if p > 0 then SegLow := Copy(SegLow, 1, p - 1);
    p := Pos('(', SegLow);
    if p > 0 then SegLow := Copy(SegLow, 1, p - 1);
    if SegLow = '' then Exit;
    if IsNonOwningAccessorSeg(SegLow) then Exit;

    // 3. Punktkette/Cast: das Ziel liegt hinter einer Dereferenzierung -
    // fremder Speicher, egal ob die Wurzel Lokale, Parameter oder Feld ist.
    //
    // GRENZE (Review 2026-08-18, bewusst offen): fuer eine lokale RECORD-
    // Wurzel stimmt das nicht - 'LRec.Slots[i] := Obj' schreibt in den
    // eigenen Stack-Frame, der Punkt ist hier kein Zeiger-Sprung. Der Fall
    // maskiert also ein echtes Leck. Er bleibt stehen, weil ihn nur
    // Typwissen von einer Objekt-Wurzel unterscheidet (W1 TTypeResolver);
    // am Korpus ist er nicht belegt, waehrend die Objekt-Wurzel der
    // Normalfall ist.
    if Pos('.', Prefix) > 0 then Exit(True);
    if Pos('(', Prefix) > 0 then Exit(True);

    // 4. Blanke (ggf. selbst indizierte) Wurzel: 'items[hashval]' oder
    // 'arr[i][j]'. Nur wenn die Wurzel KEINE Lokale/Parameter ist, ist es
    // eine Property bzw. ein Feld von Self (implizites Self).
    RootLow := Prefix;
    p := Pos('[', RootLow);
    if p > 0 then RootLow := Copy(RootLow, 1, p - 1);
    if RootLow = '' then Exit;
    if RootLow = VarNameLow then Exit;  // 'Var[i] := Var' - keine Abgabe
    Result := not ScopeDeclaresIdent(MethodNode, RootLow);
  end;

  function VarItselfInArgs(const CallName: string; AfterPos: Integer): Boolean;
  // Wie VarInArgs, aber die Variable muss SELBST uebergeben werden - nicht
  // ein Member von ihr. Belegt am Korpus (after141):
  //   Ini := TIniFile.Create(Files.Strings[i]);
  // Hier uebergibt der Aufrufer einen STRING, kein Objekt; 'Files' behaelt
  // seine Ownership. VarInArgs sieht nur die Wortgrenze und haette den
  // Fund faelschlich stillgelegt.
  // Folgt dem Treffer ein '.' oder '[', ist es ein Member-Zugriff und
  // zaehlt nicht. Wird NUR vom Ctor-Argument-Gate benutzt; der aeltere
  // nkCall-Zweig behaelt bewusst sein permissiveres VarInArgs, damit diese
  // Aenderung keine bestehenden Unterdrueckungen aufhebt.
  var
    p, q: Integer;
  begin
    Result := False;
    p := PosEx(VarNameLow, CallName, AfterPos);
    while p > 0 do
    begin
      if IsWholeWord(CallName, VarNameLow, p) then
      begin
        q := p + Length(VarNameLow);
        if (q > Length(CallName))
           or not CharInSet(CallName[q], ['.', '[']) then Exit(True);
      end;
      p := PosEx(VarNameLow, CallName, p + 1);
    end;
  end;

  function CondPassesToOwnerAdd(const CondLow: string): Boolean;
  // A2/Ownership-Sink (Core-Audit 2026-07-18): Container-Add im BEDINGUNGS-
  // Kontext. Der Parser legt Calls INNERHALB einer if/while-Bedingung NICHT als
  // nkCall ab, sondern als Flachtext in <Stmt>.TypeRef -> der nkCall-Arg-Fall
  // unten verpasst sie. Muster: `if not FTree.AddNode(aNode) then aNode.Free`
  // (aNode ist entweder im Baum registriert = owned, ODER im else/then per Free
  // freigegeben - kein Leak). Nur die EINDEUTIG ownership-uebernehmenden Tree/
  // DOM-Add-Methoden (.addnode/.addchild/.appendchild) + dieselbe Receiver-
  // Ownership-Pruefung wie im nkCall-Fall. '.add(' bewusst NICHT (mehrdeutig -
  // TList.Add uebernimmt kein Ownership und liefert einen Index, kein Bool, taucht
  // in Bedingungen praktisch nicht auf) -> monoton + kein neues TP-Risiko.
  var
    Compact, AddMarker, receiverLow : string;
    pAdd, rs : Integer;
  begin
    Result := False;
    // WICHTIG: ParseIfStmt legt die Bedingung mit einem Space um JEDES Token ab
    // ('not ftree . addnode ( anode )'), waehrend ParseWhileStmt via JoinTokInto
    // nur an Wortgrenzen trennt ('not ftree.addnode(anode)'). Damit der Marker
    // '.addnode(' in BEIDEN Formen matcht, den Whitespace komplett entfernen.
    // VarInArgs' Wortgrenzen-Pruefung bleibt gueltig ('anode' ist von '('/')'
    // begrenzt); der Receiver-Rueckwaerts-Scan liefert bei if 'notftree' - ein
    // unaufloesbares Feld -> permissiver AddReceiverOwnsItems-Pfad, wie gehabt.
    Compact := StringReplace(CondLow, ' ', '', [rfReplaceAll]);
    for AddMarker in ['.addnode(', '.addchild(', '.appendchild('] do
    begin
      pAdd := Pos(AddMarker, Compact);
      if (pAdd > 0) and VarInArgs(Compact, pAdd + Length(AddMarker)) then
      begin
        // Receiver = ident/dot-Kette unmittelbar vor dem AddMarker.
        rs := pAdd;
        while (rs > 1) and
              CharInSet(Compact[rs - 1], ['a'..'z', '0'..'9', '_', '.']) do
          Dec(rs);
        receiverLow := Copy(Compact, rs, pAdd - rs);
        if receiverLow.StartsWith('self.') then
          receiverLow := Copy(receiverLow, 6, MaxInt);
        if AddReceiverOwnsItems(MethodNode, receiverLow, AUnitNode) then
          Exit(True);
      end;
    end;
  end;

begin
  Result := False;

  // VCL-Parent-Zuweisung: varName.Parent := WinControl
  // Wer als Child eines TWinControl angemeldet wird, wird beim Destroy
  // des Parents automatisch freigegeben (Controls[]-Liste). Ownership
  // ist damit ans Parent abgegeben - kein Free im Caller noetig.
  // Standard-Pattern in jedem TFrame-/TForm-Konstruktor:
  //   Btn := TButton.Create(Self);
  //   Btn.Parent := PanelTop;       // <- DIESE Zeile gibt Ownership ab
  // Vorher: jede solche Zeile -> False-Positive "MemoryLeak".
  //
  // Plus: Borrowed-Return aus Tree-/Container-API:
  //   var := someContainer.Add(...)         TObjectList<T>(True)-basiert
  //   var := someParent.AddChild(...)       AST-/DOM-Trees
  //   var := someTree.AddNode(...)          TTreeView etc.
  //   var := someParent.AppendChild(...)    XML-DOM
  // In allen Faellen registriert die Add/AddChild/AddNode/AppendChild-Methode
  // das neue Item intern in einer OwnsObjects-Liste des Containers - das
  // Result ist eine geliehene Referenz, kein Ownership-Transfer. Ein Free
  // durch den Caller wuerde Double-Free im Container-Destroy verursachen.
  // Beispiel: ENode := Parent.Add(nkX, ...) im AST-Builder.
  ParentLHS := VarNameLow + '.parent';
  Assigns := MethodNode.FindAllRef(nkAssign);
  for N in Assigns do
  begin
    // Parent-Assign: LHS-Match
    if N.Name.ToLower = ParentLHS then
      Exit(True);
    // Self-freeing Thread (explizit): 'X.FreeOnTerminate := True' -> der Thread
    // gibt sich nach Execute selbst frei; ein Free durch den Caller waere ein
    // Use-after-free. Analog zum CreateAnonymousThread-Fall unten (der liefert
    // implizit einen FreeOnTerminate-Thread). NUR literal 'true' (nicht eine
    // Bedingung) -> konservativ. Real-World: Discovery-Residuum 2026-07-16,
    // Alcinoe/mORMot Benchmark-Threads in Loops ('LThread.FreeOnTerminate:=True').
    if (N.Name.ToLower = VarNameLow + '.freeonterminate') and
       (Trim(N.TypeRef.ToLower) = 'true') then
      Exit(True);
    // Borrowed-Return: LHS == VarName, RHS enthaelt eine der Tree-API-
    // Patterns. Pattern endet auf '(' damit '.add(' nicht in '.address('
    // o.ae. matched (rechte Wortgrenze ist garantiert).
    if N.Name.ToLower = VarNameLow then
    begin
      var TypeLow := N.TypeRef.ToLower;
      if (Pos('.add(',         TypeLow) > 0) or
         (Pos('.addchild(',    TypeLow) > 0) or
         (Pos('.addnode(',     TypeLow) > 0) or
         (Pos('.appendchild(', TypeLow) > 0) then
        Exit(True);
      // Self-freeing thread: 'var := TThread.CreateAnonymousThread(...)' liefert
      // einen FreeOnTerminate-Thread, der sich nach Ausfuehrung selbst freigibt -
      // ein try/finally-Free durch den Caller waere ein Use-after-free-Bug.
      // Allgemeine RTL-Tatsache (nicht framework-spezifisch). Real-World-FP-
      // Audit 2026-07-10 (DMVC RESTClient th := TThread.CreateAnonymousThread).
      if Pos('.createanonymousthread', TypeLow) > 0 then
        Exit(True);
    end;
    // Konstruktor-Aufruf in der Zuweisungs-RHS, unsere Var als Argument:
    //   other := TFoo.Create(..., varName, ...)
    // Der nkCall-Zweig weiter unten wertet genau diese Form schon aus
    // ('AnyClass.Create(varName, …)'), sieht sie hier aber NICHT: Aufrufe in
    // einer Zuweisungs-RHS legt der Parser als Flachtext in nkAssign.TypeRef
    // ab, nicht als nkCall-Knoten (s. Kommentar am Kopf dieser Routine).
    // Damit hing das Verhalten bisher davon ab, ob derselbe Konstruktoraufruf
    // freistehend oder als Zuweisung geschrieben ist - und ausgerechnet die
    // haeufigere Zuweisungsform war blind.
    // Beleg (Korpus after140): Alcinoe dwsJSONConnector.pas:614 meldet
    // 'connType', obwohl Z.617 'connSym := TJSONConnectorSymbol.Create(
    // SYS_JSONVARIANT, connType)' die Ownership uebergibt.
    // Die Permissivitaet ist bewusst dieselbe wie im nkCall-Zweig (jeder
    // Konstruktor, der unsere Var als Argument nimmt, gilt als uebernehmend) -
    // dieser Fix stellt Gleichbehandlung her, er fuehrt keine neue Politik ein.
    // NUR fuer SCA001 (2026-08-05, Review-Fund): AUnitNode ist der in
    // dieser Datei dokumentierte Diskriminator - nil bedeutet "Aufruf aus
    // TMissingFinallyDetector, Verhalten muss unveraendert bleiben" (s.
    // Kopfkommentar dieser Routine und die Notiz bei den unit-lokalen
    // Gates). Ohne die Klammer hat dieses Inkrement ZWEI Regeln bewegt:
    // das Korpus-Gate zeigte SCA009 -14, obwohl nur SCA001 angekuendigt
    // war, und die Regel-Attribution im gemeinsamen Gate war damit nicht
    // mehr eindeutig. Genau davor warnt die Datei an zwei Stellen.
    if Assigned(AUnitNode) then
    begin
      var RhsLowCtor := N.TypeRef.ToLower;
      var pRhsCreate := Pos('.create(', RhsLowCtor);
      if (pRhsCreate > 0) and VarItselfInArgs(RhsLowCtor, pRhsCreate + 8) then
        Exit(True);
    end;
    // Var-zu-Field-Transfer:
    //   FField := varName              -> Klassen-Feld haelt jetzt Ownership
    //   FField := varName as ISome     -> Interface-Refcount haelt Lifetime
    //   Self.FField := varName         -> mit explizitem Self-Praefix
    // In allen Faellen verlaesst die Ownership den Method-Scope. Ob das
    // Feld spaeter freigegeben wird, ist Aufgabe des FieldLeakDetectors.
    // Heuristik fuer "ist LHS ein Feld": Delphi-Konvention F<Grossbuchstabe>
    // oder explizites 'self.'-Praefix. Lokale Variablen heissen klein/
    // camelCase, daher kein Match.
    //
    // Parser inseriert seit JoinTokInto Spaces zwischen Identifier-
    // Tokens, daher 'notifier as IInterface' -> 'notifier as iinterface'.
    // Wir akzeptieren beide Varianten (mit/ohne Whitespace) damit der
    // Detektor robust gegen Parser-Aenderungen bleibt.
    var RHSLow := Trim(N.TypeRef.ToLower);
    var IsTransferShape := False;
    if RHSLow = VarNameLow then
      IsTransferShape := True
    else if RHSLow.StartsWith(VarNameLow) then
    begin
      var Rest := Trim(Copy(RHSLow, Length(VarNameLow) + 1, MaxInt));
      // 'as <typename>' ODER 'as<typename>' (legacy Parser-Output).
      if Rest.StartsWith('as ') then
        IsTransferShape := True
      else if (Length(Rest) >= 3) and (Rest[1] = 'a') and (Rest[2] = 's') and
              CharInSet(Rest[3], ['a'..'z', '_']) then
        IsTransferShape := True;
    end;
    if IsTransferShape then
    begin
      var LHSOrig := N.Name;
      var IsFieldShape :=
        SameText(Copy(LHSOrig, 1, 5), 'self.') or
        ((Length(LHSOrig) >= 2) and (LHSOrig[1] = 'F') and
         (LHSOrig[2] >= 'A') and (LHSOrig[2] <= 'Z'));
      if IsFieldShape then
      begin
        // BLANKE Feld-Form ('FField := Var', 'Self.FField := Var'): die
        // Ownership verlaesst den Methoden-Scope, der FieldLeakDetector
        // uebernimmt. Unveraendert.
        //
        // INDIZIERTE Feld-Form ('FCombo.Items.Objects[i] := Var') ist etwas
        // anderes und faellt seit 2026-08-19 durch zum Index-Gate, damit das
        // Empfaenger-Veto sie sieht (Review-Major): das F-Praefix bezeichnet
        // nur die WURZEL der Kette - ob der Container am ENDE die Ownership
        // uebernimmt, entscheidet sein letztes Segment. Bei
        // Items/Objects/Lines/Strings/Data/Nodes tut er es nicht, und der
        // frueher Exit(True) maskierte dort echte Lecks.
        //
        // NUR fuer SCA001. Bei AUnitNode = nil (SCA009) bleibt der alte
        // Weg, sonst bewegt sich die zweite Regel - derselbe Vertrag, an
        // dem das Index-Gate schon einmal gescheitert ist.
        if (not Assigned(AUnitNode)) or (Pos('[', LHSOrig) = 0) then
          Exit(True);
      end;
      // BEWUSST NICHT erweitert auf beliebige Zuweisungsziele (Versuch vom
      // 2026-08-05, nach zwei roten Bestandstests zurueckgenommen):
      // 'LOther := LItem' sieht wie eine Weitergabe aus, ist aber keine -
      // wird KEINE der beiden Variablen freigegeben, leckt das Objekt.
      // Leak_PlainLocalAssign_StillReported und
      // Leak_AssignedToOtherVarFreedViaOther_OriginalLeaks halten genau das
      // fest. Ein Feld (F<Gross>/self.) ueberlebt den Methoden-Scope und ist
      // deshalb etwas anderes als eine zweite lokale Variable.
      // Die beiden Korpus-Faelle, die den Versuch ausgeloest hatten
      // (mormot 'CurrDict := v', jcl 'Stream := SA') brauchen Typwissen -
      // Schleifen-/Interface-Variable statt Nachbar-Local - und bleiben
      // damit offen.
      //
      // ---- INDIZIERTES Ziel in FREMDEM Speicher (2026-08-18) -------------
      // Das ist NICHT die oben verworfene Erweiterung: verworfen wurde
      // "beliebiges Zuweisungsziel" (die blanke Nachbar-Lokale). Hier zaehlt
      // ausschliesslich die Form 'X[..] := Var', und nur wenn das Ziel den
      // Stack-Frame verlaesst - Details und Veto in IsForeignIndexedTarget.
      //
      // NUR fuer SCA001: der Vertrag an der Deklaration dieser Funktion
      // (AUnitNode, s.o.) sagt ausdruecklich, dass sich SCA009
      // (TMissingFinallyDetector, ruft mit Default nil) NICHT bewegen darf.
      // Die erste Fassung stand vor dieser Klammer und bewegte SCA009 mit -
      // und zwar auch dort, wo ein lokales 'L.Free' die Transfer-Annahme
      // gerade widerlegt (Free vorhanden, nur ungeschuetzt: exakt der
      // SCA009-Fund). Der Ctor-RHS-Zweig weiter oben respektiert dieselbe
      // Klammer aus demselben Grund (Review-Fund 2026-08-05).
      //
      // Belegte Korpus-Faelle, die das Gate unterdrueckt:
      //   ADest.FBuckets[I] := NewBucket         (JCL HashMaps/HashSets, 4x)
      //   fComponentsSchemas.O[AName] := lSchema (DMVC OpenAPI3)
      //   TJSONObject(aJSON).O[Name] := o        (TES5Edit)
      // NICHT unterdrueckt, weil das Empfaenger-Veto greift (bewusster
      // Preis, s. IsForeignIndexedTarget):
      //   Items[HashVal] := HashStrings          (JVCL JvSALHashList)
      //   DataList.Objects[I] := Info
      if Assigned(AUnitNode) and IsForeignIndexedTarget(LHSOrig) then
        Exit(True);
    end;
  end;

  // inherited Create(varName, …) — Elternkonstruktor übernimmt Ownership
  Inh := MethodNode.FindAllRef(nkInherited);
  for N in Inh do
  begin
    NameLow := N.Name.ToLower;
    if (Pos('create', NameLow) > 0) and
       VarInArgs(NameLow, 1) then
      Exit(True);
  end;

  Calls := MethodNode.FindAllRef(nkCall);
  for N in Calls do
  begin
    NameLow := N.Name.ToLower;

    // AnyClass.Create(varName, …)
    pCreate := Pos('.create(', NameLow);
    if (pCreate > 0) and VarInArgs(NameLow, pCreate + 8) then
      Exit(True);

    // Container.Add(varName) bzw. Container.Add(key, varName)
    // Vorher: jede '.add('-Methode wurde als ownership-uebernehmend
    // gewertet. Das produzierte False-Negatives auf legitime Leaks
    // bei TList.Add / TStringList.Add / TSynList.Add (mORMot) -
    // diese Listen uebernehmen KEIN Ownership.
    //
    // Jetzt: nur dann ownership annehmen, wenn entweder
    //   (a) der Receiver-Typ aus Local-Var/Parameter-Deklaration
    //       bekannt ist und auf ein ownership-bewusstes Container-
    //       Pattern matched (TObjectList, TObjectDictionary, ...),
    //   (b) der Typ NICHT aufloesbar ist (Field, dotted access,
    //       inferred var) - hier bleibt das alte permissive
    //       Verhalten als Default, damit keine Regression in den
    //       haeufigen Frame-FList.Add(item)-Mustern entsteht.
    // A2 2026-07-16: neben '.add(' auch die uebrigen Container-Add-Methoden
    // im ARG-Fall behandeln. '.addnode/.addchild/.appendchild(' galten bereits
    // im borrowed-RETURN-Fall oben (~Z.908) als ownership-uebernehmend, fehlten
    // aber hier -> 'FTree.AddNode(node)' auf custom Bin-Trees/Pools war ein
    // Discovery-FP (X lokal erzeugt, an Container uebergeben, Container besitzt).
    // Receiver-Ownership-Pruefung (AddReceiverOwnsItems) bleibt identisch:
    // aufloesbarer Typ -> RTL-Whitelist; Field/unaufloesbar -> permissiv (wie
    // beim bestehenden '.add(' - keine neue TP-Annahme).
    for var AddMarker in ['.add(', '.addnode(', '.addchild(', '.appendchild('] do
    begin
      var pAdd := Pos(AddMarker, NameLow);
      if (pAdd > 0) and VarInArgs(NameLow, pAdd + Length(AddMarker)) then
      begin
        var receiverLow := Copy(NameLow, 1, pAdd - 1);
        // 'self.flist' -> 'flist': Self-Praefix abstreifen, sonst matched der
        // Receiver-Name nie ein Local-Var/Param. Dotted Sub-Expressions
        // ('foo.bar.add') bleiben intentional unaufloesbar (Default permissiv).
        if receiverLow.StartsWith('self.') then
          receiverLow := Copy(receiverLow, 6, MaxInt);
        if AddReceiverOwnsItems(MethodNode, receiverLow, AUnitNode) then
          Exit(True);
      end;
    end;

    // TStringList.AddObject(text, obj) - klassisches Object-Owner-Pattern
    // (var-Deklaration hier: der fruehere gemeinsame 'pAdd' ist seit A2 in den
    // Add-Familie-for-Loop gewandert und dort scope-lokal.)
    var pAdd := Pos('.addobject(', NameLow);
    if (pAdd > 0) and VarInArgs(NameLow, pAdd + 11) then
      Exit(True);

    // #5 (Konzept_EngineArch): konfigurierbare Ownership-Sinks aus
    // [Detectors] OwnershipSinks. Aufruf einer Sink-Routine mit unserer Var
    // als Argument = Ownership-Transfer -> kein Leak. Leerer Default => keine
    // Iteration => byte-/TP-identisch (nur ini-opt-in wirkt). Wortgrenze links
    // (Start/Nicht-Ident) verhindert Substring-Treffer ('add' in 'myadd(').
    if Assigned(uSCAConsts.OwnershipSinks) then
      for var si := 0 to uSCAConsts.OwnershipSinks.Count - 1 do
      begin
        var sinkLow := LowerCase(uSCAConsts.OwnershipSinks[si]);
        if sinkLow = '' then Continue;
        var pS := Pos(sinkLow + '(', NameLow);
        if (pS > 0) and
           ((pS = 1) or not IsIdentChar(NameLow[pS - 1])) and
           VarInArgs(NameLow, pS + Length(sinkLow) + 1) then
          Exit(True);
      end;

    // Inkr.3 (Gross-Triage add-call-Bucket 27/101, groesster Rest): CUSTOM
    // Add-/Insert-/Put-Familie - 'Cfg.AddOption(sl)', 'Enc.AddStream(...,s,..)',
    // 'Tree.InsertNode(..., PFileInfo(fi))', 'Cont.Put(key, obj)'. Der Consumer
    // registriert das Objekt in einer eigenen owning-Struktur (Triage: 27/27
    // solcher Uebergaben fremd-owned). Marker: '.add'/'.insert'/'.put' +
    // optionales CamelCase-Suffix - der Buchstabe DIREKT nach dem Praefix muss
    // im ORIGINAL-Case GROSS sein ('.AddStream' ja, '.address(' nein) - dann
    // '(' + Var als bare Wort-Arg (VarInArgs matcht auch in Cast-Argumenten
    // 'PFileInfo(fi)'). Receiver-Pruefung identisch permissiv wie '.add('.
    for var Fam in ['.add', '.insert', '.put'] do
    begin
      var pF := Pos(Fam, NameLow);
      while pF > 0 do
      begin
        var sf := pF + Length(Fam);
        var ef := sf;
        if (sf <= Length(NameLow)) and IsIdentChar(NameLow[sf]) then
        begin
          if CharInSet(N.Name[sf], ['A'..'Z']) then
          begin
            while (ef <= Length(NameLow)) and IsIdentChar(NameLow[ef]) do Inc(ef);
          end
          else
            ef := 0;      // lowercase-Fortsetzung ('.address') -> keine Familie
        end;
        if (ef > 0) and (ef <= Length(NameLow)) and (NameLow[ef] = '(')
           and VarInArgs(NameLow, ef + 1) then
        begin
          var recvLow := Copy(NameLow, 1, pF - 1);
          if recvLow.StartsWith('self.') then
            recvLow := Copy(recvLow, 6, MaxInt);
          if AddReceiverOwnsItems(MethodNode, recvLow, AUnitNode) then
            Exit(True);
        end;
        pF := PosEx(Fam, NameLow, pF + 1);
      end;
    end;

    // mORMot-kuratiert: 'ObjArrayAdd(fOwnedList, x)' haengt x an ein dyn-Array,
    // dessen Owner es freigibt (Triage Batch 3: Rtti.ObjArrayAdd(fOwnedRtti)).
    if (Pos('objarrayadd(', NameLow) > 0) and
       VarInArgs(NameLow, Pos('objarrayadd(', NameLow) + 12) then
      Exit(True);

    // TList/TQueue/TStack.Insert(index, item) - Ownership-Transfer
    pAdd := Pos('.insert(', NameLow);
    if (pAdd > 0) and VarInArgs(NameLow, pAdd + 8) then
      Exit(True);

    // TStack.Push(item) / TQueue.Enqueue(item) - Ownership-Transfer
    pAdd := Pos('.push(', NameLow);
    if (pAdd > 0) and VarInArgs(NameLow, pAdd + 6) then
      Exit(True);
    pAdd := Pos('.enqueue(', NameLow);
    if (pAdd > 0) and VarInArgs(NameLow, pAdd + 9) then
      Exit(True);
  end;

  // Container-Add im BEDINGUNGS-Kontext (if/while): Calls INNERHALB einer
  // Bedingung sind keine nkCall-Knoten, sondern Flachtext in <Stmt>.TypeRef.
  // Deckt 'if not FTree.AddNode(aNode) then aNode.Free' (Core-Audit 2026-07-18).
  for var CondKind in [nkIfStmt, nkWhileStmt] do
  begin
    var Conds := MethodNode.FindAllRef(CondKind);
    for N in Conds do
      if CondPassesToOwnerAdd(N.TypeRef.ToLower) then
        Exit(True);
  end;
end;

{ ---- Free-Suche ---- }

class function TLeakDetector2.SearchFree(Node: TAstNode;
  const VarNameLow: string; InFinally: Boolean;
  out FoundInFinally: Boolean): Boolean;
var
  Child        : TAstNode;
  NameLow      : string;
  ChildInFin   : Boolean;
  ChildFinFlag : Boolean;
  pMatch       : Integer;
begin
  Result         := False;
  FoundInFinally := False;

  if not Assigned(Node) then Exit;

  if Node.Kind = nkCall then
  begin
    NameLow := Node.Name.ToLower;

    // varName.Free   (mit und ohne Klammern: list.Free / list.Free())
    pMatch := Pos(VarNameLow + '.free', NameLow);
    if pMatch > 0 then
    begin
      // Linke Wortgrenze: Zeichen vor varName darf kein Bezeichner sein
      if (pMatch = 1) or not IsIdentChar(NameLow[pMatch - 1]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // varName.Destroy
    pMatch := Pos(VarNameLow + '.destroy', NameLow);
    if pMatch > 0 then
    begin
      if (pMatch = 1) or not IsIdentChar(NameLow[pMatch - 1]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // varName.DisposeOf - ARC-/NextGen-Idiom, auf Classic-Compilern Alias fuer
    // Free. SCA001-Gross-Triage 2026-07-18 (free-missed-Bucket 22/101): 2 reale
    // Faelle (FMX LBitmap.DisposeOf / Str.DisposeOf) als "nie freigegeben"
    // gemeldet, weil SearchFree DisposeOf nicht kannte.
    pMatch := Pos(VarNameLow + '.disposeof', NameLow);
    if pMatch > 0 then
    begin
      if (pMatch = 1) or not IsIdentChar(NameLow[pMatch - 1]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // Typecast-Free: 'TStringList(FParams).Free' / '(varName).Destroy' - der
    // Cast schiebt ')' zwischen Var-Namen und '.free', das 'varname.free'-
    // Muster oben verfehlt das (Gross-Triage: JvUIB TStringList(FParams).Free
    // im Destroy -> FP "nie freigegeben"). Linke Grenze '(' garantiert, dass
    // varName das GANZE Cast-Argument ist (kein 'foo(x.varname)'). ZUSATZ-
    // Guard: der Kopf vor '(' muss ein TYP sein (t-Praefix-Konvention) -
    // 'GetWrapper(list).Free' gibt das RESULT frei, nicht list (waere FN).
    // Dokumentiertes Rest-Risiko: t-praefixierte FUNKTIONEN ('Transform(x).Free')
    // passieren den Guard (selten; SearchFree hat keinen AContext fuer einen
    // echten Typ-Check via TTypeIndex - bewusst akzeptiert).
    pMatch := Pos('(' + VarNameLow + ').free', NameLow);
    if pMatch = 0 then pMatch := Pos('(' + VarNameLow + ').destroy', NameLow);
    if pMatch = 0 then pMatch := Pos('(' + VarNameLow + ').disposeof', NameLow);
    if pMatch > 1 then
    begin
      // Kopf-Ident vor der '(' rueckwaerts einsammeln; muss mit 't' beginnen.
      var hS := pMatch - 1;
      while (hS >= 1) and IsIdentChar(NameLow[hS]) do Dec(hS);
      if (hS + 1 < pMatch) and (NameLow[hS + 1] = 't') then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // 'with varName do ... Free' - der Parser legt with als nkCall(withExpr)
    // ab und haengt den Body-Block als SUBTREE darunter (uParser2 tkKwWith-
    // Zweig; 'begin..end' erzeugt einen nkBlock-Zwischenknoten). Ein bare
    // 'Free'/'Destroy'/'DisposeOf'-Call in diesem Subtree meint das with-
    // Objekt. Nur wenn der Node-Name EXAKT der Var-Name ist (single-target-
    // with; ein gewoehnlicher Call-nkCall traegt Klammern im Namen und hat
    // keine Children). Iterativer Walk (Hardening-v4-Stil).
    // (Gross-Triage: DropTarget 'with bm do ... free' -> FP.)
    if (NameLow = VarNameLow) and (Node.Children.Count > 0) then
    begin
      var WStack := TList<TAstNode>.Create;
      // A2 (SCA009-Triage 2026-07-24): finally-Kontext JE STACK-EINTRAG
      // mitfuehren. Vorher galt fuer bare Free im with-Subtree pauschal der
      // Kontext des WITH-Knotens (auf Methodenebene False) - beim Idiom
      // 'with L do try .. finally Free end' kam FoundInFinally=False zurueck
      // und uMissingFinally meldete trotz korrektem Schutz (FP). Alle
      // Konsumenten nutzen FoundInFinally nur zur Unterdrueckung -> monoton.
      var WFins := TList<Boolean>.Create;
      try
        for Child in Node.Children do
        begin
          WStack.Add(Child);
          WFins.Add(InFinally or (Child.Kind = nkFinallyBlock));
        end;
        while WStack.Count > 0 do
        begin
          var W    := WStack[WStack.Count - 1];
          var WFin := WFins[WFins.Count - 1];
          WStack.Delete(WStack.Count - 1);
          WFins.Delete(WFins.Count - 1);
          if W.Kind = nkCall then
          begin
            var WLow := W.Name.ToLower;
            if (WLow = 'free') or (WLow = 'free()')
               or (WLow = 'destroy') or (WLow = 'disposeof') then
            begin
              Result := True; FoundInFinally := WFin;
              Exit;   // finally gibt WStack/WFins frei
            end;
            // NESTED with ('with bm do with other do Free') NICHT betreten:
            // dessen bare Free gehoert zum INNEREN Objekt, nicht zu varName
            // (Review-Fang 2026-07-18: sonst maskierter Leak von varName).
            // Ein inneres with sieht aus wie dieses: klammerloser nicht-leerer
            // nkCall MIT Children. nkBlock-Zwischenknoten sind kein nkCall
            // und werden normal betreten.
            if (W.Children.Count > 0) and (W.Name <> '')
               and (Pos('(', W.Name) = 0) then
              Continue;
          end;
          for var WC in W.Children do
          begin
            WStack.Add(WC);
            WFins.Add(WFin or (WC.Kind = nkFinallyBlock));
          end;
        end;
      finally
        WStack.Free;
        WFins.Free;
      end;
    end;

    // FreeAndNil(varName) und FreeAndNil(Self.varName) - Match auf beide
    // Varianten. Rechte Grenze: kein Bezeichner-Zeichen nach varName.
    pMatch := Pos('freeandnil(' + VarNameLow, NameLow);
    if pMatch > 0 then
    begin
      var pRight := pMatch + 11 + Length(VarNameLow); // 11 = len('freeandnil(')
      if (pRight > Length(NameLow)) or not IsIdentChar(NameLow[pRight]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;
    pMatch := Pos('freeandnil(self.' + VarNameLow, NameLow);
    if pMatch > 0 then
    begin
      var pRight := pMatch + 16 + Length(VarNameLow); // 16 = len('freeandnil(self.')
      if (pRight > Length(NameLow)) or not IsIdentChar(NameLow[pRight]) then
      begin
        Result := True; FoundInFinally := InFinally; Exit;
      end;
    end;

    // Custom-Cleanup-Pattern: Funktion deren Name auf 'release'/'dispose'/
    // 'return'/'recycle' endet und varName als Argument bekommt
    // (Acquire/Release-Pool-Pattern wie AcquireLines/ReleaseLines).
    // Match nur wenn varName als bare Argument im Klammerausdruck steht.
    pMatch := Pos('(' + VarNameLow, NameLow);
    if pMatch > 0 then
    begin
      var pRight := pMatch + 1 + Length(VarNameLow);
      var BoundaryOK := (pRight > Length(NameLow)) or
                       (NameLow[pRight] = ',') or
                       (NameLow[pRight] = ')') or
                       (NameLow[pRight] = ' ');
      if BoundaryOK then
      begin
        // Funktionsnamen-Teil vor '(' extrahieren und auf Cleanup-Marker pruefen.
        // Akzeptiere sowohl 'Release' als Praefix ('ReleaseLines', 'ReleaseBuffer')
        // als auch als Suffix ('MyRelease', 'BufferRelease'). Beide Konventionen
        // sind in Delphi-Code praesent.
        var FnName := Copy(NameLow, 1, pMatch - 1);
        if FnName.StartsWith('release') or FnName.EndsWith('release') or
           FnName.StartsWith('dispose') or FnName.EndsWith('dispose') or
           FnName.StartsWith('return')  or FnName.EndsWith('return')  or
           FnName.StartsWith('recycle') or FnName.EndsWith('recycle') or
           // Custom-Free-Wrapper: Funktionsname ENTHAELT 'free'
           // (ALFreeAndNil, ALFreeObjectList, FreeObject, FreeThenNil ...).
           // 'enthaelt' statt Praefix/Suffix, weil 'alfreeandnil' weder
           // mit 'free' beginnt noch endet. Real-World-FP 2026-06-21.
           (Pos('free', FnName) > 0) then
        begin
          Result := True; FoundInFinally := InFinally; Exit;
        end;
      end;
    end;
  end;

  for Child in Node.Children do
  begin
    ChildInFin := InFinally or (Child.Kind = nkFinallyBlock);
    if SearchFree(Child, VarNameLow, ChildInFin, ChildFinFlag) then
    begin
      Result := True; FoundInFinally := ChildFinFlag; Exit;
    end;
  end;
end;

class function TLeakDetector2.HasTryFinallyBlock(MethodNode: TAstNode): Boolean;
begin
  Result := MethodNode.HasChild(nkTryFinally);
end;

class function TLeakDetector2.HasDescendantKind(Node: TAstNode;
  Kind: TNodeKind): Boolean;
var
  Child : TAstNode;
begin
  Result := False;
  if not Assigned(Node) then Exit;
  for Child in Node.Children do
    if (Child.Kind = Kind) or HasDescendantKind(Child, Kind) then
      Exit(True);
end;

class function TLeakDetector2.HasExceptFreeRaise(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// Prio-5-Gate: sucht einen except-Handler (nkExceptBlock; on-Handler liegen
// als nkOnHandler DARIN und werden von SearchFree/HasDescendantKind rekursiv
// miterfasst), der SOWOHL einen Free von VarName ALS AUCH ein raise enthaelt.
// Beides im selben Handler = das Cleanup-und-weiterwerfen-Idiom; ein Free ganz
// ohne Re-Raise wird bewusst NICHT als Schutz gewertet (konservativ).
var
  Handlers : TList<TAstNode>;
  H        : TAstNode;
  DummyFin : Boolean;
begin
  Result := False;
  Handlers := MethodNode.FindAllRef(nkExceptBlock);
  for H in Handlers do
    if HasDescendantKind(H, nkRaise) and
       SearchFree(H, VarNameLow, False, DummyFin) then
      Exit(True);
end;

class function TLeakDetector2.FreeInFinallyRegionBySource(MethodNode: TAstNode;
  const StrippedLines: TArray<string>; const VarNameLow: string): Boolean;
// Source-basierte finally-Regionen. ANKER SEIT 2026-07-19: die 'finally'-
// Schluesselwoerter in der (gestrippten) QUELLE innerhalb der Methoden-Zeilen-
// spanne - NICHT mehr die AST-nkFinallyBlock-Knoten. Grund (Auto-Runde-Triage):
// bei Mis-Parse des AEUSSEREN try/finally (nested try im Body / {$IFDEF} /
// 'F:=nil;try') FEHLT der aeussere nkFinallyBlock im Method-Subtree - der
// fruehere AST-verankerte Scan fand die Region dann NIE; der Port aus 4ae5e7a
// war fuer die realen Faelle (CnFeedWizard:1020/1021, CnObjInspectorCommentFrm:
// 1192, CnSrcEditorBlockTools:1485) ein No-Op. Der Source-Anker ist von der
// AST-Attachierung unabhaengig. Region-Ende per Vorwaerts-Balancierung ab der
// finally-Zeile (TryEndLine unveraendert), auf die Methodenspanne geklammert
// (TAstSpans.SubtreeMaxLine). Monoton (nur zusaetzliche Suppression); TP-safe: greift nur
// bei bewiesenem VarName-Free innerhalb einer balancierten finally..end-Region
// INNERHALB der Methode. StrippedLines: Index k-1 == Quellzeile k.
var
  StartL, EndL, li, MethStart, MethEnd : Integer;
  WithTryLine : Integer;   // A2: Zeile des einzigen 'with <var> do try' (0 = Gate aus)

  function TryEndLine(FinLine1: Integer): Integer;
  const
    OPENERS : array[0..5] of string = ('begin','try','case','asm','record','object');
  var
    depth, k, j, p, len : Integer;
    low, w : string;
    isOpener : Boolean;
    oi : Integer;
  begin
    depth := 0;
    for k := FinLine1 to Length(StrippedLines) do
    begin
      low := LowerCase(StrippedLines[k - 1]);
      len := Length(low);
      j := 1;
      while j <= len do
      begin
        if CharInSet(low[j], ['a'..'z','_']) then
        begin
          p := j;
          while (j <= len) and CharInSet(low[j], ['a'..'z','0'..'9','_']) do Inc(j);
          w := Copy(low, p, j - p);
          isOpener := False;
          for oi := 0 to High(OPENERS) do
            if w = OPENERS[oi] then begin isOpener := True; Break; end;
          if isOpener then Inc(depth)
          else if w = 'end' then
          begin
            Dec(depth);
            if depth < 0 then Exit(k);   // dieses 'end' schliesst das try
          end;
        end
        else
          Inc(j);
      end;
    end;
    Result := Length(StrippedLines);      // Fallback: bis Dateiende
  end;

  function BoundedLeft(const Low, Needle: string; NeedRightBreak: Boolean): Boolean;
  var q, rr : Integer;
  begin
    Result := False;
    q := Pos(Needle, Low);
    while q > 0 do
    begin
      if (q = 1) or not TLeakDetector2.IsIdentChar(Low[q - 1]) then
      begin
        if NeedRightBreak then
        begin
          rr := q + Length(Needle);
          if (rr > Length(Low)) or not TLeakDetector2.IsIdentChar(Low[rr]) then Exit(True);
        end
        else
          Exit(True);
      end;
      q := PosEx(Needle, Low, q + 1);
    end;
  end;

  function LineFreesVar(const S: string): Boolean;
  var Low : string;
  begin
    Low := LowerCase(S);
    Result := BoundedLeft(Low, VarNameLow + '.free', False)
           or BoundedLeft(Low, VarNameLow + '.destroy', False)
           or BoundedLeft(Low, 'freeandnil(' + VarNameLow, True)
           or BoundedLeft(Low, 'freeandnil(self.' + VarNameLow, True);
  end;

  // A2 (SCA009-Triage 2026-07-24): das klassische Dialog-Idiom
  //   L := TDlg.Create(nil); with L do try ... finally Free; end;
  // schreibt den Free OHNE Receiver - 'varname.free' verfehlt ihn. Gate:
  // genau EIN 'with' in der Methodenspanne, dessen Ziel EXAKT VarName ist
  // und dessen Body ein try-Statement ist ('do try' auf derselben oder
  // 'try' auf der naechsten nicht-leeren Zeile). Liefert die with-Zeile,
  // sonst 0. Streng nach Triage-Spez ("genau EIN with"), damit ein bare
  // Free nie einem fremden with-Objekt oder Self zugerechnet wird.
  function SingleWithDoTryLine: Integer;
  var
    k, p, rr, nk2 : Integer;
    Low, T : string;
    Cnt, CandLine : Integer;
  begin
    Result := 0; Cnt := 0; CandLine := 0;
    for k := MethStart to MethEnd do
    begin
      Low := LowerCase(StrippedLines[k - 1]);
      p := Pos('with', Low);
      while p > 0 do
      begin
        if ((p = 1) or not IsIdentChar(Low[p - 1])) and
           ((p + 4 > Length(Low)) or not IsIdentChar(Low[p + 4])) then
        begin
          Inc(Cnt);
          if Cnt > 1 then Exit(0);
          rr := p + 4;
          while (rr <= Length(Low)) and (Low[rr] = ' ') do Inc(rr);
          if Copy(Low, rr, Length(VarNameLow)) = VarNameLow then
          begin
            rr := rr + Length(VarNameLow);
            if (rr > Length(Low)) or not IsIdentChar(Low[rr]) then
            begin
              while (rr <= Length(Low)) and (Low[rr] = ' ') do Inc(rr);
              if (Copy(Low, rr, 2) = 'do') and
                 ((rr + 2 > Length(Low)) or not IsIdentChar(Low[rr + 2])) then
              begin
                rr := rr + 2;
                while (rr <= Length(Low)) and (Low[rr] = ' ') do Inc(rr);
                if rr > Length(Low) then
                begin
                  // 'do' am Zeilenende -> 'try' muss die naechste nicht-leere
                  // Zeile eroeffnen ('tryxyz'-Idents via Wortgrenze verworfen).
                  nk2 := k + 1;
                  while (nk2 <= MethEnd) and (Trim(StrippedLines[nk2 - 1]) = '') do
                    Inc(nk2);
                  if nk2 <= MethEnd then
                  begin
                    T := LowerCase(Trim(StrippedLines[nk2 - 1]));
                    if (T = 'try') or ((Copy(T, 1, 3) = 'try') and
                       (Length(T) > 3) and not IsIdentChar(T[4])) then
                      CandLine := k;
                  end;
                end
                else if (Copy(Low, rr, 3) = 'try') and
                        ((rr + 3 > Length(Low)) or not IsIdentChar(Low[rr + 3])) then
                  CandLine := k;
              end;
            end;
          end;
        end;
        p := PosEx('with', Low, p + 1);
      end;
    end;
    if Cnt = 1 then Result := CandLine;
  end;

  // A2: bare 'Free'/'Free()' als eigenes Statement - Wortgrenzen beidseits,
  // und davor darf (auch ueber Leerraum) kein '.' stehen ('X.Free' gehoert
  // zu X, nicht zum with-Objekt). 'freeandnil(' faellt durch die rechte
  // Wortgrenze ('a' ist Ident-Zeichen).
  function LineHasBareFree(const S: string): Boolean;
  var
    Low : string;
    p, q, rr : Integer;
  begin
    Result := False;
    Low := LowerCase(S);
    p := Pos('free', Low);
    while p > 0 do
    begin
      if (p = 1) or not IsIdentChar(Low[p - 1]) then
      begin
        q := p - 1;
        while (q >= 1) and (Low[q] = ' ') do Dec(q);
        if (q < 1) or (Low[q] <> '.') then
        begin
          rr := p + 4;
          if (rr < Length(Low)) and (Low[rr] = '(') and (Low[rr + 1] = ')') then
            Inc(rr, 2);
          if (rr > Length(Low)) or not IsIdentChar(Low[rr]) then
            Exit(True);
        end;
      end;
      p := PosEx('free', Low, p + 1);
    end;
  end;

  // 'finally' als eigenstaendiges Wort in einer (gestrippten) Zeile?
  function LineHasFinally(const S: string): Boolean;
  var
    Low : string;
    p, rr : Integer;
  begin
    Result := False;
    Low := LowerCase(S);
    p := Pos('finally', Low);
    while p > 0 do
    begin
      if (p = 1) or not IsIdentChar(Low[p - 1]) then
      begin
        rr := p + 7;                          // hinter 'finally'
        if (rr > Length(Low)) or not IsIdentChar(Low[rr]) then
          Exit(True);
      end;
      p := PosEx('finally', Low, p + 1);
    end;
  end;

begin
  Result := False;
  if (MethodNode = nil) or (Length(StrippedLines) = 0) then Exit;

  MethStart := MethodNode.Line;
  if MethStart < 1 then MethStart := 1;
  // Obergrenze der Scan-Spanne - verhindert, dass finally-Regionen NACH der
  // Methode (naechste Routine) mitgescannt werden. Die lokale Fassung
  // SubtreeMaxLine war zeichengleich zum Primitiv (Start bei 0, nil -> 0,
  // iterativer nicht-besitzender Stapel, Wurzel mitgezaehlt) - der Tausch
  // ist wertgleich, nicht nur ergebnisgleich.
  MethEnd := TAstSpans.SubtreeMaxLine(MethodNode);
  if MethEnd > Length(StrippedLines) then MethEnd := Length(StrippedLines);
  if MethEnd < MethStart then Exit;

  WithTryLine := SingleWithDoTryLine;

  for StartL := MethStart to MethEnd do
  begin
    if not LineHasFinally(StrippedLines[StartL - 1]) then Continue;
    EndL := TryEndLine(StartL);
    if EndL > MethEnd then EndL := MethEnd;    // Region auf die Methode klammern
    for li := StartL to EndL do
      if (li >= 1) and (li <= Length(StrippedLines)) then
      begin
        if LineFreesVar(StrippedLines[li - 1]) then Exit(True);
        // A2: bare 'Free' zaehlt NUR unter dem strengen with-Gate (genau EIN
        // with in der Methode, Ziel = VarName, Body ist ein try) und nur in
        // finally-Regionen NACH der with-Zeile - dann ist der Receiver
        // beweisbar das with-Objekt. Rest-Risiko Self.Free in einem SPAETEREN
        // fremden finally derselben Methode: braeuchte zusaetzlich das
        // do-try-Idiom auf genau dieser Var - bewusst akzeptiert.
        if (WithTryLine > 0) and (StartL > WithTryLine)
           and LineHasBareFree(StrippedLines[li - 1]) then
          Exit(True);
      end;
  end;
end;

class function TLeakDetector2.IsHandedToInterface(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// Scannt nkAssign.TypeRef (RHS) und nkCall.Name im ORIGINAL-Case nach
//   '<IIdent>(varname)'   - Interface-Hard-Cast  (IBoxedJSONValue(b))
//   'varname as I<Ident>' - as-Cast              (obj as IMyIntf)
// I-Konvention nur im Original-Case pruefbar: 'I' + GROSSBUCHSTABE
// ('IntToStr(b)' hat 'n' klein -> kein Interface). Ein Interface-Cast gibt
// das Objekt an die Refcount ab - der letzte Release gibt es frei.
var
  Nodes : TList<TAstNode>;
  N : TAstNode;

  function TextHands(const Orig: string): Boolean;
  var
    Low : string;
    p, pr, hS : Integer;
  begin
    Result := False;
    if Orig = '' then Exit;
    Low := Orig.ToLower;
    // Muster 1: '<IIdent>(varname' mit rechter Wortgrenze
    p := Pos('(' + VarNameLow, Low);
    while p > 0 do
    begin
      pr := p + 1 + Length(VarNameLow);
      if (pr > Length(Low)) or not IsIdentChar(Low[pr]) then
      begin
        hS := p - 1;
        while (hS >= 1) and IsIdentChar(Low[hS]) do Dec(hS);
        if (hS + 2 <= p - 1) and (Orig[hS + 1] = 'I')
           and CharInSet(Orig[hS + 2], ['A'..'Z']) then
          Exit(True);
      end;
      p := PosEx('(' + VarNameLow, Low, p + 1);
    end;
    // Muster 2: 'varname as i<ident>' mit linker Wortgrenze
    p := Pos(VarNameLow + ' as i', Low);
    while p > 0 do
    begin
      if (p = 1) or not IsIdentChar(Low[p - 1]) then
      begin
        pr := p + Length(VarNameLow) + 4;   // Position des 'i' hinter ' as '
        if (pr < Length(Orig)) and (Orig[pr] = 'I')
           and CharInSet(Orig[pr + 1], ['A'..'Z']) then
          Exit(True);
      end;
      p := PosEx(VarNameLow + ' as i', Low, p + 1);
    end;
  end;

begin
  Result := False;
  Nodes := MethodNode.FindAllRef(nkAssign);
  for N in Nodes do
    if TextHands(N.TypeRef) then Exit(True);
  Nodes := MethodNode.FindAllRef(nkCall);
  for N in Nodes do
    if TextHands(N.Name) then Exit(True);
end;

class function TLeakDetector2.IsRaisedAsException(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// 'raise E;' -> nkRaise.Name = geraister Ausdruck (uParser2 ParseRaiseStmt).
// Exakter Var-Match: raise uebernimmt Ownership, die RTL gibt das Objekt im
// Exception-Handler frei.
var
  Raises : TList<TAstNode>;
  R : TAstNode;
begin
  Result := False;
  Raises := MethodNode.FindAllRef(nkRaise);
  for R in Raises do
    if Trim(R.Name.ToLower) = VarNameLow then Exit(True);
end;

class function TLeakDetector2.AllCreatesAreInstanceFactory(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Assigns, Decls : TList<TAstNode>;
  A, D : TAstNode;
  LocalTypes : TDictionary<string, string>;   // name-low -> typ-low (1. Wort)
  TypeLow, RecvLow, DeclType : string;
  CreatePos, pRight, i : Integer;
  CreateCount, FactoryCount : Integer;
  IsClean : Boolean;

  function FirstWordLow(const S: string): string;
  var T: string; k: Integer;
  begin
    T := Trim(LowerCase(S)); Result := '';
    for k := 1 to Length(T) do
      if IsIdentChar(T[k]) then Result := Result + T[k] else Break;
  end;

  function LastWordLow(const S: string): string;
  var T: string; sp: Integer;
  begin
    T := Trim(LowerCase(S));
    sp := LastDelimiter(' ', T);
    if sp > 0 then Result := Copy(T, sp + 1, MaxInt) else Result := T;
  end;

begin
  // Result wird am Ende unbedingt aus CreateCount/FactoryCount gesetzt -
  // keine Vorab-Initialisierung noetig (H2077).
  CreateCount := 0; FactoryCount := 0;
  LocalTypes := TDictionary<string, string>.Create;
  try
    Decls := MethodNode.FindAllRef(nkLocalVar);
    for D in Decls do
      LocalTypes.AddOrSetValue(Trim(D.Name.ToLower), FirstWordLow(D.TypeRef));
    Decls := MethodNode.FindAllRef(nkParam);
    for D in Decls do
      LocalTypes.AddOrSetValue(LastWordLow(D.Name), FirstWordLow(D.TypeRef));

    Assigns := MethodNode.FindAllRef(nkAssign);
    for A in Assigns do
    begin
      if A.Name.ToLower <> VarNameLow then Continue;
      TypeLow := A.TypeRef.ToLower;
      if not MatchesCreate(A.TypeRef, TypeLow, CreatePos) then Continue;
      Inc(CreateCount);
      // Nur 'CreateXxx' (nicht-leeres CamelCase-Suffix) kann Factory sein -
      // bare '.Create' ist IMMER eine Konstruktion (auch Metaclass-Local).
      pRight := CreatePos + 7;
      if (pRight > Length(TypeLow)) or not IsIdentChar(TypeLow[pRight]) then
        Continue;
      RecvLow := Trim(Copy(TypeLow, 1, CreatePos - 1));
      if RecvLow = '' then Continue;
      // Fall b: '(x as IFoo)'-Ausdrucks-Receiver = sicher eine Instanz
      // (Metaclass-Casts 'TComponentClass(arr[i])' enthalten KEIN ' as ').
      if (RecvLow[Length(RecvLow)] = ')') and (Pos(' as ', RecvLow) > 0) then
      begin
        Inc(FactoryCount);
        Continue;
      end;
      // Fall a: einfacher Ident, der eine bekannte Local/Param-INSTANZ ist
      // und dessen Typname nicht auf 'class' endet (Metaclass-Konvention
      // TFormClass/TComponentClass -> deren CreateXxx ist echte Konstruktion).
      IsClean := True;
      for i := 1 to Length(RecvLow) do
        if not IsIdentChar(RecvLow[i]) then begin IsClean := False; Break; end;
      if IsClean and LocalTypes.TryGetValue(RecvLow, DeclType)
         and (DeclType <> '') and not EndsStr('class', DeclType) then
        Inc(FactoryCount);
    end;
  finally
    LocalTypes.Free;
  end;
  Result := (CreateCount > 0) and (CreateCount = FactoryCount);
end;

{ ---- FP-Gates 30%-Real-World-Audit 2026-07-31 ------------------------------ }
//
// BEWUSST UNIT-LOKAL (keine class function von TLeakDetector2): uMissingFinally
// (SCA002) konsumiert die public Ownership-Helfer dieser Unit (IsPassedToOwner /
// IsOwnerParamCreate). Wuerden die neuen Gates dort einhaengen, verschoeben sich
// zwei Regeln gleichzeitig und die Regel-Attribution im gemeinsamen Korpus-Gate
// waere nicht mehr eindeutig. Die Gates hier wirken ausschliesslich auf SCA001
// und werden nur aus TLeakDetector2.AnalyzeMethod / HasFunctionCallAssign
// gerufen. Alle Gates sind MONOTON: sie koennen einen Fund nur unterdruecken.

// Zerlegt eine Argumentliste (ohne die aeusseren Klammern) an TOP-LEVEL-Kommas.
// Klammer-/Klammeraffen-Tiefe und String-Literale ('a,b') werden respektiert,
// damit 'Add(''x,y'', obj)' nicht am Komma IM Literal splittet.
function SinkSplitTopLevelArgs(const S: string): TArray<string>;
var
  Acc   : TList<string>;
  i, depth, start : Integer;
  inStr : Boolean;
begin
  Acc := TList<string>.Create;
  try
    depth := 0; start := 1; inStr := False;
    for i := 1 to Length(S) do
    begin
      if S[i] = '''' then
        inStr := not inStr
      else if not inStr then
      begin
        if CharInSet(S[i], ['(', '[']) then Inc(depth)
        else if CharInSet(S[i], [')', ']']) then Dec(depth)
        else if (S[i] = ',') and (depth = 0) then
        begin
          Acc.Add(Trim(Copy(S, start, i - start)));
          start := i + 1;
        end;
      end;
    end;
    Acc.Add(Trim(Copy(S, start, Length(S) - start + 1)));
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

// True wenn eines der TOP-LEVEL-Argumente EXAKT die Variable ist: direkt
// ('Add(obj)'), als ECHTER Typecast ('InsertNode(i, PFileInfo(fi))'), geklammert
// ('Add((obj))') oder als as-Cast ('Add(obj as TFoo)'). Ein blosses Vorkommen
// IM Ausdruck ('Add(obj.Items[0])') zaehlt bewusst NICHT - dort wird nicht das
// Objekt selbst uebergeben, ein Gate darauf waere ein maskiertes Leak.
//
// Review-Fund 2026-07-31 ("SinkArgIsVar packt beliebige '<ident>(...)'-Koepfe
// aus, nicht nur Typecasts"): frueher galt JEDER Identifier-Kopf als Cast, also
// auch eine Helferfunktion - 'FLog.Add(Describe(Result))' liess das Gate feuern,
// obwohl nur ein String uebergeben wird und das Objekt weiter dem Aufrufer
// gehoert. Ausgepackt wird jetzt nur noch
//   * die reine Klammerung ('(obj)') und
//   * ein Kopf in Typ-Konvention: 'T'/'I'/'P' + GROSSbuchstabe im ORIGINAL-Case
//     ('TFoo(x)', 'IFoo(x)', 'PFileInfo(x)').
// AArgsAny wird deshalb im ORIGINAL-Case erwartet. Bekommt die Funktion nur
// lowercase-Text (fehlende Index-Paritaet beim Aufrufer), greift ausschliesslich
// die Klammer-Regel - konservativ, das Gate feuert dann seltener.
// Reichweitengrenze: Cast-Koepfe ohne Grossbuchstaben an zweiter Stelle
// ('TdmMain(x)', 'TfrmFoo(x)') gelten nicht als Cast -> der Fund bleibt stehen.
function SinkArgIsVar(const AArgsAny, VarNameLow: string): Boolean;
var
  Args : TArray<string>;
  A, Cur, Head : string;
  guard, p, ap : Integer;

  function IsTypecastHead(const AHead: string): Boolean;
  var
    hi : Integer;
  begin
    Result := False;
    if AHead = '' then Exit(True);          // reine Klammerung '(obj)'
    for hi := 1 to Length(AHead) do
      if not TLeakDetector2.IsIdentChar(AHead[hi]) then Exit;
    Result := (Length(AHead) >= 2) and
              CharInSet(AHead[1], ['T', 'I', 'P']) and
              CharInSet(AHead[2], ['A'..'Z']);
  end;

begin
  Result := False;
  if (Trim(AArgsAny) = '') or (VarNameLow = '') then Exit;
  Args := SinkSplitTopLevelArgs(AArgsAny);
  for A in Args do
  begin
    Cur   := Trim(A);
    guard := 0;
    while (Cur <> '') and (guard < 4) do
    begin
      Inc(guard);
      // 'obj as TFoo' -> 'obj'
      ap := Pos(' as ', Cur.ToLower);
      if ap > 0 then
      begin
        Cur := Trim(Copy(Cur, 1, ap - 1));
        Continue;
      end;
      // '(inner)' bzw. 'TFoo(inner)' auspacken - NUR echte Casts.
      if Cur[Length(Cur)] = ')' then
      begin
        p := Pos('(', Cur);
        if p > 0 then
        begin
          Head := Trim(Copy(Cur, 1, p - 1));
          if IsTypecastHead(Head) then
          begin
            Cur := Trim(Copy(Cur, p + 1, Length(Cur) - p - 1));
            Continue;
          end;
        end;
      end;
      Break;
    end;
    if Cur.ToLower = VarNameLow then Exit(True);
  end;
end;

// FP-Klasse 1 (Ownership-Transfer an besitzende Senken, 10/24 im Sample):
// Sink-Familien. Der Empfaenger registriert das Objekt per Konvention in einer
// eigenen besitzenden Struktur - Add/AddObject/AddPair/AddChild/AddMenuItem,
// Insert/InsertNode, Append/AppendChild, Push, Enqueue/EnqueueLogItem.
// CamelCase-Suffixe zaehlen nur, wenn der Folgebuchstabe im ORIGINAL-Case GROSS
// ist ('.AddPair(' ja, '.address(' / '.appendix(' / '.inserted(' nein).
// NICHT enthalten: framework-spezifische Senken ohne Namenskonvention
// (DMVC '.Body(', fpjson-Sonderformen) - dafuer ist die konfigurierbare
// OwnershipSinks-Registry da; ein globaler Seed wurde 2026-07-xx bewusst
// verworfen (RTL-Namen wie LoadFromStream maskieren echte Leaks).
const
  SINK_FAMS : array[0..4] of string = ('add', 'insert', 'append', 'push', 'enqueue');

// Kanonisch NICHT-besitzende Container-Zugaenge. Das LETZTE Segment einer
// gepunkteten Empfaengerkette ('AlarmListBox.Items', 'Memo.Lines',
// 'Node.Data'). Diese Properties liefern Container, die ein uebergebenes
// Objekt per Definition NICHT besitzen:
//   * TStrings.Objects[] - AddObject/InsertObject speichern nur die Referenz,
//     TStrings.Destroy raeumt sie NIE ab (deshalb die verbreiteten
//     'for i := 0 to Count-1 do Objects[i].Free'-Schleifen in Clear/Destroy).
//   * TTreeNodes / TTreeNode.Data - untypisierter Pointer, ebenfalls ohne
//     Ownership.
const
  NONOWNING_ACCESSORS : array[0..5] of string = (
    'items', 'objects', 'lines', 'strings', 'data', 'nodes');

// True wenn ReceiverNameLow in AScope als Local-Var oder Parameter DEKLARIERT
// ist (Typ egal). Spiegelt exakt die Namensaufloesung von
// AddReceiverOwnsItems.FindReceiverType inkl. der 'var '/'const '/'out '-
// Praefixe, die der Parser an Parameter-Namen haengt.
function ScopeDeclaresIdent(AScope: TAstNode; const NameLow: string): Boolean;
var
  Kind    : TNodeKind;
  N       : TAstNode;
  NameRaw : string;
begin
  Result := False;
  if (AScope = nil) or (NameLow = '') then Exit;
  for Kind in [nkLocalVar, nkParam] do
    for N in AScope.FindAllRef(Kind) do
    begin
      NameRaw := N.Name;
      for var Mod_ in ['var ', 'const ', 'out '] do
        if NameRaw.ToLower.StartsWith(Mod_) then
          NameRaw := Copy(NameRaw, Length(Mod_) + 1, MaxInt);
      if NameRaw.ToLower = NameLow then Exit(True);
    end;
end;

// ZUSATZHUERDE 2026-07-31 (TP-Verlust-Cluster SCA001 aus dem Drop-Sampling
// after119->after120, 7 belegte Error-Tier-Lecks):
//   AlarmListBox.ItemIndex := AlarmListBox.Items.AddObject('New', TObject(Al));
//   Result := ATreeView.Items.AddChildObject(ParentNode, S, ATreeMenuItem);
// Beides sind ECHTE Lecks (keine Freigabe in der ganzen Unit), wurden aber vom
// Sink-Gate stillgestellt: eine gepunktete Kette ist in der Routine nie
// aufloesbar -> permissiver Pfad -> die Senke galt als besitzend. Genau dort
// liegt das Gate aber systematisch falsch, denn '<X>.Items/.Lines/.Objects'
// sind die kanonisch NICHT besitzenden VCL/LCL-Container.
//
// Das Veto greift nur bei BEIDEN Merkmalen zugleich:
//   (1) letztes Empfaenger-Segment ist ein nicht-besitzender Container-Zugang,
//   (2) der Sink-Name gehoert zur *Object*-Familie (AddObject, AddChildObject,
//       InsertObject, ...). Nur diese Ueberladungen nehmen ueberhaupt ein
//       OBJEKT entgegen - 'Items.Add(S)'/'Lines.Add(S)' nehmen einen String.
// Huerde (2) ist nicht kosmetisch, sondern haelt einen belegten korrekten Drop:
// mORMot src/ui/mormot.ui.report.pas:5191 ('M2 := NewPopupMenuItem(...)') wird
// ueber den Callee-Rumpf TGdiPages.NewPopupMenuItem (Z.5051) gedroppt, und der
// endet auf 'PopupMenu.Items.Add(result)'. Dort ist 'Items' ein TMenuItem, der
// seine Kinder sehr wohl freigibt - und der Ctor 'TMenuItem.Create(PopupMenu)'
// hat den Owner ohnehin schon gesetzt. Mit einer reinen Receiver-Regel ohne
// Huerde (2) waere dieser korrekte Drop als FP zurueckgekommen.
//
// Bei einem BAREN Empfaenger ('Items.AddObject(...)' als Self-Property) wird
// zuvor geprueft, ob der Name doch eine Local/Param ist - dann entscheidet
// weiterhin allein die RTL-Ownership-Whitelist ('Data: TObjectList' bleibt
// besitzend). Gepunktete Ketten koennen per Konstruktion nie aufloesen.
//
// BEWUSST NICHT UMGESETZT (geprueft, verworfen): den Typecast-Auspack-Pfad in
// SinkArgIsVar fuer 'TObject(...)' generell zu sperren. Am Korpus bringt das
// NULL zusaetzliche Rueckkehrer (alle 6 TObject-Cast-Faelle sind schon ueber
// das Receiver-Veto abgedeckt), waehrend 'ObjList.Add(TObject(x))' auf einem
// nachweislich besitzenden TObjectList dadurch faelschlich wieder gemeldet
// wuerde - reines FP-Risiko ohne Ertrag.
function IsNonOwningAccessorSeg(const ASegLow: string): Boolean;
// Reiner Listentest ohne Scope- und ohne Sink-Namen-Bedingung. Der
// Aufruf-Pfad (ReceiverIsNonOwningAccessor) braucht beide zusaetzlich, weil
// 'Items.Add(S)' einen STRING nimmt und deshalb kein Objekt verlieren kann.
// Bei einer ZUWEISUNG 'X.Objects[i] := Obj' steht dagegen zweifelsfrei ein
// Objekt auf der rechten Seite - dort entscheidet das Segment allein.
begin
  Result := MatchStr(ASegLow, NONOWNING_ACCESSORS);
end;

function ReceiverIsNonOwningAccessor(AScope: TAstNode;
  const ReceiverNameLow, SinkNameLow: string): Boolean;
var
  Seg : string;
  dp  : Integer;
begin
  Result := False;
  if (ReceiverNameLow = '') or (Pos('object', SinkNameLow) = 0) then Exit;
  dp := LastDelimiter('.', ReceiverNameLow);
  if dp > 0 then
    Seg := Copy(ReceiverNameLow, dp + 1, MaxInt)
  else
  begin
    Seg := ReceiverNameLow;
    // Barer Empfaenger: koennte eine echte Local/Param sein - dann bleibt die
    // strikte RTL-Whitelist zustaendig.
    if ScopeDeclaresIdent(AScope, Seg) then Exit;
  end;
  // Listentest ueber die gemeinsame Funktion statt eines zweiten
  // MatchStr-Aufrufs (Review-Minor 2026-08-18): die Liste hat jetzt genau
  // einen Leser, und der Unterschied zwischen den beiden Pfaden liegt
  // sichtbar in den Vorbedingungen darueber, nicht im Test selbst.
  Result := IsNonOwningAccessorSeg(Seg);
end;

// Receiver-Veto fuer die Sink-Familien.
//
// Review-Fund 2026-07-31 ("ReceiverIsProvenNonOwning kehrt die bisherige strikte
// Receiver-Policy um"): die urspruengliche Fassung dieses Gates veto'te nur
// gegen eine 9-Namen-Sperrliste (tlist/tstrings/...). Damit galt JEDER andere
// aufloesbare Empfaenger als besitzende Senke - TFPList, TStringBuilder oder
// TCustomImageList (jvcl JvImageList.pas: 'TempImageList.Add(Bmp, MaskBmp)',
// TImageList KOPIERT die Bitmap und besitzt sie nicht) haetten echte Leaks
// stillgestellt.
//
// Wiederhergestellt ist deshalb die per Test festgeschriebene STRIKTE Richtung
// von AddReceiverOwnsItems (Leak_TListAddNonOwning_ReportsError):
//   * Receiver-Typ in DIESER Routine aufloesbar (Local/Param) -> er muss die
//     RTL-Ownership-Whitelist treffen (TObjectList/TObjectDictionary/...),
//     sonst Veto -> der Fund bleibt.
//   * Receiver NICHT aufloesbar (Feld, dotted Kette, leerer Self-Aufruf) ->
//     kein Veto, altes permissives Verhalten wie im bestehenden '.add('-Pfad.
// Framework-eigene besitzende Senken ohne RTL-Konvention (TJSONObject.AddPair,
// fpjson) sind damit bewusst NICHT mehr pauschal abgedeckt - dafuer ist die
// konfigurierbare OwnershipSinks-Registry ([Detectors] OwnershipSinks) da; ein
// globaler Seed wurde 2026-07 bewusst verworfen.
//
// 2026-07-31 ZUSATZHUERDE: der bisher permissive Zweig (Receiver nicht
// aufloesbar) bekommt eine Ausnahme - ist der Empfaenger ein nachweislich
// nicht-besitzender Container-Zugang UND die Senke eine *Object*-Ueberladung,
// wird trotzdem veto't (siehe ReceiverIsNonOwningAccessor). Das Gate wird
// dadurch ausschliesslich ENGER: es kann nur noch WENIGER Funde unterdruecken.
function ReceiverVetoesSink(AScope: TAstNode;
  const ReceiverNameLow, SinkNameLow: string): Boolean;
begin
  // Leerer Empfaenger = unqualifizierter Aufruf der eigenen Klasse; der ist
  // per Definition nicht aufloesbar -> kein Veto (und kein Fehl-Match gegen
  // einen namenlosen Deklarationsknoten).
  Result := (AScope <> nil) and (ReceiverNameLow <> '') and
            (ReceiverIsNonOwningAccessor(AScope, ReceiverNameLow, SinkNameLow) or
             not TLeakDetector2.AddReceiverOwnsItems(AScope, ReceiverNameLow));
end;

// True wenn ATextOrig einen Sink-Aufruf enthaelt, der VarNameLow als eigenes
// Argument uebergibt UND dessen Empfaenger NICHT die Variable selbst ist
// ('obj.Add(x)' zaehlt fuer obj nicht - da fuellt obj sich selbst).
function SinkCallPassesVar(AScope: TAstNode;
  const ATextOrig, VarNameLow: string): Boolean;
var
  Low, Orig, fam, recv, argsAny, sinkName : string;
  p, ef, ce, depth, argStart, rs : Integer;
  ok : Boolean;
begin
  Result := False;
  if (ATextOrig = '') or (VarNameLow = '') then Exit;
  Low  := ATextOrig.ToLower;
  // Index-Paritaet (2026-07-31): alle Positionen werden auf Low berechnet und
  // fuer die Original-Case-Pruefungen (CamelCase-Suffix, Typecast-Kopf in
  // SinkArgIsVar) 1:1 auf Orig angewandt. Bei abweichender Laenge (exotische
  // Unicode-Faltung) faellt Orig auf Low zurueck - dann greift nur die
  // konservative Teilmenge der Regeln.
  Orig := ATextOrig;
  if Length(Orig) <> Length(Low) then Orig := Low;
  for fam in SINK_FAMS do
  begin
    p := Pos(fam, Low);
    while p > 0 do
    begin
      // Linke Wortgrenze: Start, '.', '(' oder Whitespace - nie mitten in
      // einem laengeren Identifier ('myadd(' matcht nicht).
      if (p = 1) or not TLeakDetector2.IsIdentChar(Low[p - 1]) then
      begin
        ef := p + Length(fam);
        ok := False;
        if ef <= Length(Low) then
        begin
          if Low[ef] = '(' then
            ok := True
          else if TLeakDetector2.IsIdentChar(Low[ef]) and
                  CharInSet(Orig[ef], ['A'..'Z']) then
          begin
            while (ef <= Length(Low)) and TLeakDetector2.IsIdentChar(Low[ef]) do
              Inc(ef);
            ok := (ef <= Length(Low)) and (Low[ef] = '(');
          end;
        end;
        if ok then
        begin
          // Voller Senken-Bezeichner ab der Familie bis vor die '(' -
          // 'add', 'addobject', 'addchildobject', 'insertobject', ...
          // (2026-07-31: das Receiver-Veto unterscheidet die *Object*-
          // Ueberladungen von den String-Ueberladungen.)
          sinkName := Copy(Low, p, ef - p);
          // Argumentliste balanciert einlesen (bounds-safe; unbalanciert -> skip)
          argStart := ef + 1;
          depth    := 1;
          ce       := argStart;
          while (ce <= Length(Low)) and (depth > 0) do
          begin
            if Low[ce] = '(' then Inc(depth)
            else if Low[ce] = ')' then Dec(depth);
            if depth > 0 then Inc(ce);
          end;
          if depth = 0 then
          begin
            // Original-Case: SinkArgIsVar unterscheidet Typecast von
            // Helferfunktion nur am Grossbuchstaben (Review-Fund 2026-07-31).
            argsAny := Copy(Orig, argStart, ce - argStart);
            // Empfaenger = ident/dot-Kette unmittelbar vor der Familie.
            // Leerer Empfaenger = unqualifizierter Aufruf (Self-Methode,
            // z.B. 'Add(FileTemplate)' in TFileTemplates) - ebenfalls Senke.
            rs := p;
            while (rs > 1) and
                  CharInSet(Low[rs - 1], ['a'..'z', '0'..'9', '_', '.']) do
              Dec(rs);
            recv := Copy(Low, rs, p - rs);
            if EndsStr('.', recv) then SetLength(recv, Length(recv) - 1);
            if StartsStr('self.', recv) then recv := Copy(recv, 6, MaxInt);
            if (recv <> VarNameLow) and not StartsStr(VarNameLow + '.', recv) and
               not ReceiverVetoesSink(AScope, recv, sinkName) and
               SinkArgIsVar(argsAny, VarNameLow) then
              Exit(True);
          end;
        end;
      end;
      p := PosEx(fam, Low, p + 1);
    end;
  end;
end;

// FP-Klasse 1/2: Uebergabe an einen Konstruktor INNERHALB eines Ausdrucks
// ('Worker := TFileListBuilder.Create(..., DisplayFilesHashed);' - doublecmd
// ufileview.pas:2166, der Ctor uebernimmt die Var per var-Parameter). Der
// nkCall-Zweig in IsPassedToOwner sieht nur FREISTEHENDE Calls; Konstruktoren
// in einer Zuweisungs-RHS sind nkAssign.TypeRef und fehlten dort komplett.
function CtorCallPassesVar(const ATextOrig, VarNameLow: string): Boolean;
var
  Low, Orig, recv, argsAny : string;
  p, ef, ce, depth, argStart, rs : Integer;
  ok : Boolean;
begin
  Result := False;
  if (ATextOrig = '') or (VarNameLow = '') then Exit;
  Low  := ATextOrig.ToLower;
  // Index-Paritaet wie in SinkCallPassesVar (2026-07-31).
  Orig := ATextOrig;
  if Length(Orig) <> Length(Low) then Orig := Low;
  p := Pos('.create', Low);
  while p > 0 do
  begin
    ef := p + 7;                       // direkt hinter '.create'
    ok := False;
    if ef <= Length(Low) then
    begin
      if Low[ef] = '(' then
        ok := True
      else if TLeakDetector2.IsIdentChar(Low[ef]) and
              CharInSet(Orig[ef], ['A'..'Z']) then
      begin
        // CamelCase-Konstruktor ('.CreateFmt(') - '.created'/'.creates'
        // (Kleinbuchstaben-Fortsetzung) sind Verbformen, kein Ctor.
        while (ef <= Length(Low)) and TLeakDetector2.IsIdentChar(Low[ef]) do
          Inc(ef);
        ok := (ef <= Length(Low)) and (Low[ef] = '(');
      end;
    end;
    if ok then
    begin
      argStart := ef + 1;
      depth    := 1;
      ce       := argStart;
      while (ce <= Length(Low)) and (depth > 0) do
      begin
        if Low[ce] = '(' then Inc(depth)
        else if Low[ce] = ')' then Dec(depth);
        if depth > 0 then Inc(ce);
      end;
      if depth = 0 then
      begin
        argsAny := Copy(Orig, argStart, ce - argStart);
        rs := p;
        while (rs > 1) and
              CharInSet(Low[rs - 1], ['a'..'z', '0'..'9', '_', '.']) do
          Dec(rs);
        recv := Copy(Low, rs, p - rs);
        if StartsStr('self.', recv) then recv := Copy(recv, 6, MaxInt);
        if (recv <> VarNameLow) and not StartsStr(VarNameLow + '.', recv) and
           SinkArgIsVar(argsAny, VarNameLow) then
          Exit(True);
      end;
    end;
    p := PosEx('.create', Low, p + 1);
  end;
end;

// FP-Klasse 1 (Kern-Gate): der LETZTE Use der Variablen im Methodenrumpf ist
// die Uebergabe an eine besitzende Senke bzw. an einen fremden Konstruktor.
// "Letzter Use" = groesste Quellzeile aller Knoten, deren Name oder TypeRef die
// Variable als GANZES WORT enthaelt. Die Last-Use-Bedingung ist der
// Praezisions-Anker: wird das Objekt nach der Uebergabe noch benutzt
// ('L.Add(o); o.Free;'), greift das Gate nicht.
// Reichweitengrenze: mehrzeilige Aufrufe, deren Argument-Zeile groesser ist als
// die Zeile des tragenden Knotens, fallen aus dem Gate (Fund bleibt) - bewusst
// FN-freundlich statt raten.
function LastUseIsOwnershipTransfer(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
var
  Stack : TList<TAstNode>;
  N, C  : TAstNode;
  LastLine : Integer;

  function Touches(const AText: string): Boolean;
  begin
    Result := (AText <> '') and
      TDetectorUtils.ContainsWholeWordLower(VarNameLow, AText.ToLower);
  end;

begin
  Result := False;
  if (MethodNode = nil) or (VarNameLow = '') then Exit;
  LastLine := 0;
  Stack := TList<TAstNode>.Create;
  try
    // Lauf 1: letzte Zeile mit einem Vorkommen der Variablen bestimmen.
    Stack.Add(MethodNode);
    while Stack.Count > 0 do
    begin
      N := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (N.Line > LastLine) and (Touches(N.Name) or Touches(N.TypeRef)) then
        LastLine := N.Line;
      for C in N.Children do Stack.Add(C);
    end;
    if LastLine <= 0 then Exit;
    // Lauf 2: nur Knoten AUF dieser Zeile duerfen die Uebergabe tragen.
    Stack.Clear;
    Stack.Add(MethodNode);
    while Stack.Count > 0 do
    begin
      N := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (N.Line = LastLine) and
         (SinkCallPassesVar(MethodNode, N.Name, VarNameLow) or
          SinkCallPassesVar(MethodNode, N.TypeRef, VarNameLow) or
          CtorCallPassesVar(N.Name, VarNameLow) or
          CtorCallPassesVar(N.TypeRef, VarNameLow)) then
        Exit(True);
      for C in N.Children do Stack.Add(C);
    end;
  finally
    Stack.Free;
  end;
end;

// True wenn S ein reiner Objekt-Ausdruck ist: Identifier oder dotted chain
// ('fpanel', 'righttabs.activepage', 'result'). Literale, nil, Zahlen,
// Operatoren und Klammerausdruecke sind ausgeschlossen.
function IsPlainObjectExprLow(const S: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if S = '' then Exit;
  if (S = 'nil') or (S = 'true') or (S = 'false') then Exit;
  if not CharInSet(S[1], ['a'..'z', '_']) then Exit;
  if S[Length(S)] = '.' then Exit;
  for i := 1 to Length(S) do
    if not CharInSet(S[i], ['a'..'z', '0'..'9', '_', '.']) then Exit;
  Result := True;
end;

// Zerlegt eine RHS in Klassenname (lowercase, ohne Unit-Qualifier) und das
// ERSTE Top-Level-Argument eines '<Typ>.Create(...)'-Aufrufs. Das Argument wird
// zusaetzlich im ORIGINAL-Case geliefert - die Komponenten-Namenskonvention
// ('Self.', 'F<Gross>') laesst sich nur dort pruefen (2026-07-31).
function SplitCreateCall(const ATypeRefOrig: string;
  out AClassLow, AFirstArgLow, AFirstArgOrig: string): Boolean;
var
  Low, Orig, Head, argsLow, argsOrig : string;
  CreatePos, idx, depth, argStart, dp : Integer;
  Args, ArgsO : TArray<string>;
begin
  Result        := False;
  AClassLow     := '';
  AFirstArgLow  := '';
  AFirstArgOrig := '';
  Low  := ATypeRefOrig.ToLower;
  Orig := ATypeRefOrig;
  // Index-Paritaet: alle Positionen werden auf Low berechnet.
  if Length(Orig) <> Length(Low) then Orig := Low;
  if not TLeakDetector2.MatchesCreate(ATypeRefOrig, Low, CreatePos) then Exit;
  Head := Trim(Copy(Low, 1, CreatePos - 1));
  dp := LastDelimiter('.', Head);
  if dp > 0 then Head := Trim(Copy(Head, dp + 1, MaxInt));
  AClassLow := Head;
  // Hinter '.create' evtl. CamelCase-Suffix, dann muss '(' folgen.
  idx := CreatePos + 7;
  while (idx <= Length(Low)) and TLeakDetector2.IsIdentChar(Low[idx]) do Inc(idx);
  while (idx <= Length(Low)) and (Low[idx] = ' ') do Inc(idx);
  if (idx > Length(Low)) or (Low[idx] <> '(') then Exit;
  argStart := idx + 1;
  depth    := 1;
  Inc(idx);
  while (idx <= Length(Low)) and (depth > 0) do
  begin
    if Low[idx] = '(' then Inc(depth)
    else if Low[idx] = ')' then Dec(depth);
    if depth > 0 then Inc(idx);
  end;
  if depth <> 0 then Exit;
  argsLow  := Trim(Copy(Low,  argStart, idx - argStart));
  argsOrig := Trim(Copy(Orig, argStart, idx - argStart));
  Args  := SinkSplitTopLevelArgs(argsLow);
  ArgsO := SinkSplitTopLevelArgs(argsOrig);
  if Length(Args)  > 0 then AFirstArgLow  := Trim(Args[0]);
  if Length(ArgsO) > 0 then AFirstArgOrig := Trim(ArgsO[0]);
  Result := True;
end;

// FP-Klasse 2 (TComponent-/Owner-Ownership, 5/24 im Sample):
//   aFileView := TBriefFileView.Create(FRightTabs.ActivePage, FrameRight);
//   Btn       := TButton.Create(Self.FPanel);
// Ein nicht-nil Objekt-Ausdruck als ERSTES Ctor-Argument ist die TComponent-
// Owner-Konvention - der Owner gibt das Objekt in DestroyComponents frei.
// IsOwnerParamCreate deckt nur die kanonischen Bezeichner (Self/Owner/AOwner/
// Application) ab; hier kommen beliebige Owner-Ausdruecke dazu.
//
// STUFE 1 (beweisend): der Cross-Unit-Typindex loest die Ctor-Klasse ODER den
// deklarierten Var-Typ auf und belegt eine TComponent-Ahnenlinie. Loest der
// Index die Klasse auf und ist sie KEIN TComponent-Nachfahre (z.B. TStringList
// -> TStrings -> TPersistent), greift das Gate nicht.
// STUFE 2 (Reichweitengrenze, nur wenn der Index den Typ NICHT kennt - z.B.
// Single-File-Analyse oder Klasse ausserhalb des Scan-Scope): drei Huerden
// gleichzeitig -
//   (1) das erste Argument ist ein DOTTED Feld-/Property-Ausdruck
//       ('Self.FPanel', 'FRightTabs.ActivePage'); blanke Identifier bleiben
//       aussen vor, sonst wuerde 'TFileStream.Create(FileName, fmOpenRead)'
//       als Owner-Ctor gelten und ein ganzer TP-Block verschwinden,
//   (2) die Ctor-Klasse ist keine bekannte Datenklasse (DATA_CLASSES),
//   (3) der Ausdruck sieht SELBST nach einer Komponente aus (Self./F-Praefix/
//       Owner-/Parent-Segment) ODER die Ctor-Klasse steht in der kurzen Liste
//       bekannter VCL-Komponentenklassen.
// Huerde (3) ist der Review-Fund 2026-07-31 ("wertet JEDES dotted erste
// Ctor-Argument als Owner"): ohne sie galten 'TRegIniFile.Create(Cfg.Section)',
// 'TSynLogFile.Create(Ctxt.FileName)' oder
// 'TDictionary<string,TObject>.Create(TIStringComparer.Ordinal)' als
// Component-Ownership und stellten echte Leaks still.
// REICHWEITENGRENZE (bewusst FN-freundlich): Owner-Ausdruecke ohne Konvention -
// insbesondere published Form-Felder ohne F-Praefix wie
// 'RightTabs.ActivePage' - fallen ohne Typindex aus Stufe 2 heraus; der Fund
// bleibt dann stehen. Mit gefuelltem TTypeIndex greift Stufe 1 und deckt sie ab.
function IsComponentOwnerCreate(MethodNode: TAstNode;
  const VarNameLow, VarTypeLow: string; AContext: TAnalyzeContext): Boolean;
const
  // Stufe-2-Sperrliste: RTL-Klassen, deren erstes Ctor-Argument DATEN sind
  // (Dateiname, Quellstream, Text) und nie ein Owner. Nur fuer den
  // unaufgeloesten Fallback relevant.
  DATA_CLASSES : array[0..18] of string = (
    'tfilestream', 'tstringstream', 'tmemorystream', 'tbytesstream',
    'tresourcestream', 'tbufferedfilestream', 'thandlestream',
    'tstringlist', 'tstringbuilder', 'tinifile', 'tmeminifile',
    'tregistryinifile', 'tstreamreader', 'tstreamwriter',
    'tbinaryreader', 'tbinarywriter', 'tzipfile', 'tencoding',
    'tregistry');
  // Stufe-2-Positivliste: RTL-/VCL-Klassen, deren erster Ctor-Parameter per
  // Definition AOwner: TComponent ist. Kurz gehalten - der Regelfall ist
  // Stufe 1 (Typindex); die Liste traegt nur die Single-File-Analyse.
  COMPONENT_CLASSES : array[0..17] of string = (
    'tform', 'tcustomform', 'tframe', 'tdatamodule', 'tpanel', 'tbutton',
    'ttimer', 'tmenuitem', 'tpopupmenu', 'tmainmenu', 'taction',
    'tactionlist', 'timagelist', 'ttabsheet', 'tpagecontrol',
    'ttoolbutton', 'ttreeview', 'tlistview');

  function ArgLooksLikeComponent(const AArgOrig: string): Boolean;
  // Namenskonvention eines Owner-Ausdrucks im ORIGINAL-Case.
  var
    Segs : TArray<string>;
    Seg  : string;
  begin
    Result := False;
    if AArgOrig = '' then Exit;
    if StartsText('self.', AArgOrig) then Exit(True);
    // Delphi-Feldkonvention 'F' + Grossbuchstabe auf dem ERSTEN Segment.
    if (Length(AArgOrig) >= 2) and (AArgOrig[1] = 'F') and
       CharInSet(AArgOrig[2], ['A'..'Z']) then Exit(True);
    Segs := AArgOrig.ToLower.Split(['.']);
    for Seg in Segs do
      if MatchStr(Trim(Seg), ['owner', 'aowner', 'fowner',
                              'parent', 'aparent', 'fparent']) then
        Exit(True);
  end;

var
  Assigns  : TList<TAstNode>;
  A        : TAstNode;
  ClassLow, FirstArg, FirstArgOrig, dc : string;
  TI       : TTypeIndex;
  IsData, IsComp : Boolean;
begin
  Result := False;
  if MethodNode = nil then Exit;
  TI := CtxTypeIndex(AContext);
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    if not SplitCreateCall(A.TypeRef, ClassLow, FirstArg, FirstArgOrig) then Continue;
    if not IsPlainObjectExprLow(FirstArg) then Continue;
    if (FirstArg = VarNameLow) or StartsStr(VarNameLow + '.', FirstArg) then Continue;
    // Stufe 1: Typindex beweist (oder widerlegt) die TComponent-Ahnenlinie.
    if (TI <> nil) and not TI.IsEmpty then
    begin
      if TI.IsDescendantOf(ClassLow, 'tcomponent') or
         TI.IsDescendantOf(VarTypeLow, 'tcomponent') then Exit(True);
      if (TI.TypeKindOf(ClassLow) <> tkiUnknown) or (TI.ParentOf(ClassLow) <> '') then
        Continue;      // aufloesbar und KEIN TComponent -> kein Gate
    end;
    // Stufe 2: konservativer Fallback ohne Typwissen.
    if Pos('.', FirstArg) = 0 then Continue;
    IsData := False;
    for dc in DATA_CLASSES do
      if ClassLow = dc then begin IsData := True; Break; end;
    if IsData then Continue;
    IsComp := False;
    for dc in COMPONENT_CLASSES do
      if ClassLow = dc then begin IsComp := True; Break; end;
    if IsComp or ArgLooksLikeComponent(FirstArgOrig) then Exit(True);
  end;
end;

{ ---- FP-Gate Parser-Gate-Backlog 2026-07-31 (4e/1) ------------------------ }
//
// "Der Ctor registriert sich beim Parent".
//   InspCat := TJvInspectorCustomCategoryItem.Create(Self.Root, nil);
//   ...
//   constructor TJvCustomInspectorItem.Create(const AParent: ...);
//   begin
//     ...
//     if AParent <> nil then AParent.Add(Self);     // <-- Ownership-Uebergabe
//   end;
// (jvcl JvInspector.pas 4130 und 11876 plus die zwei vendorierten Zwillinge.)
// Das Objekt haengt nach dem Konstruktoraufruf in der besitzenden Liste des
// Parents; TJvCustomInspectorItem.BeforeDestruction/Destroy des Parents raeumt
// es ab. Weder IsOwnerParamCreate (kennt nur Self/Owner/AOwner/Application)
// noch IsComponentOwnerCreate (verlangt TComponent-Linie; die Inspector-Items
// sind TPersistent) koennen das sehen.
//
// STRENGE:
//   (1) erstes Ctor-Argument ist ein nicht-nil OBJEKT-Ausdruck (Ident oder
//       dotted Kette) und nicht die Variable selbst,
//   (2) der Callee-Ctor wird in DIESER Unit aufgeloest - entweder direkt oder
//       ueber die in DIESER Unit deklarierte Ahnenkette (max. 8 Stufen).
//       Cross-Unit gibt es keinen Rumpf, also auch keinen Beweis -> Fund
//       bleibt (die 6 Instanzen in JvInspectorDemo/InspectorExampleMain.pas
//       sind genau dieser dokumentierte Rest),
//   (3) der Ctor muss auf dieser Aufloesungsstufe EINDEUTIG sein (Overloads =
//       kein Beweis, welche Ueberladung gemeint war),
//   (4) im Ctor-Rumpf steht '<ErsterParameter>.Add/Insert/AddChild/AddNode(
//       ... Self ...)' - Self als GANZES Wort in der balanciert gelesenen
//       Argumentliste.
// Monoton: das Gate kann einen Fund nur unterdruecken.

// True wenn AArgsLow das ganze Wort 'self' enthaelt - und zwar SELF SELBST,
// nicht ein Member davon.
//
// REVIEW-BLOCKER 2026-07-31: TDetectorUtils.ContainsWholeWordLower reicht hier
// NICHT. Dessen Wortgrenze prueft ausschliesslich IsIdentChar, und '.' ist kein
// Identifier-Zeichen - fuer 'self.fcaption' galt die rechte Grenze als erfuellt
// und der Treffer zaehlte. Damit haette
//   AItems.Add(Self.FCaption)
// als "der Ctor haengt Self in die besitzende Liste" gegolten; uebergeben wird
// aber ein FELD von Self. Folge waere gewesen: 'C := TColumn.Create(MyList)'
// stillgestellt, obwohl es ein echtes Leck ist.
//
// Erhalten bleiben muessen (alle drei sind echte Selbstregistrierungen):
//   '.add(self)'            - Self als Einzelargument,
//   '.add(self,x)' / '(0,self)' - Self in einer Argumentliste,
//   '.add(tfoo(self))'      - Typecast.
// Regel: links kein Identifier-Zeichen, rechts kein Identifier-Zeichen UND
// kein '.'. AArgsLow ist bereits lowercase und whitespace-frei (Compact).
function ArgsContainBareSelf(const AArgsLow: string): Boolean;
const
  SELF_LEN = 4;   // Length('self')
var
  p, rightIdx : Integer;
  LeftOK, RightOK : Boolean;
begin
  Result := False;
  if AArgsLow = '' then Exit;
  p := Pos('self', AArgsLow);
  while p > 0 do
  begin
    LeftOK   := (p = 1) or not TLeakDetector2.IsIdentChar(AArgsLow[p - 1]);
    rightIdx := p + SELF_LEN;
    RightOK  := (rightIdx > Length(AArgsLow)) or
                (not TLeakDetector2.IsIdentChar(AArgsLow[rightIdx]) and
                 (AArgsLow[rightIdx] <> '.'));
    if LeftOK and RightOK then Exit(True);
    p := PosEx('self', AArgsLow, p + 1);
  end;
end;

// True wenn AText einen Aufruf '<AParamLow>.<Add-Familie>(... self ...)'
// enthaelt. Whitespace wird entfernt, weil der Parser Bedingungs- und
// Anweisungstexte unterschiedlich normalisiert (ParseIfStmt setzt Spaces um
// jedes Token, JoinTokInto nur an Wortgrenzen) - dieselbe Vorsichtsmassnahme
// wie in CondPassesToOwnerAdd.
function RegisterCallPassesSelf(const AText, AParamLow: string): Boolean;
const
  REG_MARKERS : array[0..3] of string = (
    '.add(', '.insert(', '.addchild(', '.addnode(');
var
  Compact, Marker, Needle, ArgsLow : string;
  p, i, depth, argStart : Integer;
begin
  Result := False;
  if (AText = '') or (AParamLow = '') then Exit;
  Compact := StringReplace(AText.ToLower, ' ', '', [rfReplaceAll]);
  for Marker in REG_MARKERS do
  begin
    Needle := AParamLow + Marker;
    p := Pos(Needle, Compact);
    while p > 0 do
    begin
      // Linke Wortgrenze: 'faparent.add(' darf nicht fuer 'aparent' zaehlen.
      if (p = 1) or not TLeakDetector2.IsIdentChar(Compact[p - 1]) then
      begin
        argStart := p + Length(Needle);
        i        := argStart;
        depth    := 1;
        while (i <= Length(Compact)) and (depth > 0) do
        begin
          if Compact[i] = '(' then Inc(depth)
          else if Compact[i] = ')' then Dec(depth);
          if depth > 0 then Inc(i);
        end;
        if depth = 0 then
        begin
          ArgsLow := Copy(Compact, argStart, i - argStart);
          // NICHT ContainsWholeWordLower - das zaehlte 'self.fcaption' mit
          // (Review-Blocker 2026-07-31), siehe ArgsContainBareSelf.
          if ArgsContainBareSelf(ArgsLow) then
            Exit(True);
        end;
      end;
      p := PosEx(Needle, Compact, p + 1);
    end;
  end;
end;

function CtorSetsFreeOnTerminate(AUnitNode, MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
// Autopsie 2026-08-26, Klasse 5 (4 Drops gezaehlt, u.a. IdDNSServer,
// uCEFApplicationCore): der Thread setzt 'FreeOnTerminate := True' im
// EIGENEN Konstruktor DERSELBEN Unit - er raeumt sich selbst ab, der
// Aufrufer darf gar nicht freigeben. Beweis-Anforderungen (streng,
// analog CtorRegistersSelfWithFirstArg): (1) das Create-Assign nennt
// die Klasse woertlich, (2) genau EIN Instanz-Ctor '<Klasse>.Create'
// in dieser Unit (Overloads = keine Aussage), (3) in dessen Teilbaum
// steht die FreeOnTerminate-True-Zuweisung. KEIN Vorfahren-Klettern.
var
  Assigns  : TList<TAstNode>;
  A, N, CA : TAstNode;
  ClassLow : string;
  TR       : string;
  Ctor     : TAstNode;
  Cnt, cp  : Integer;
begin
  Result := False;
  if AUnitNode = nil then Exit;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    TR := A.TypeRef.ToLower;
    cp := Pos('.create', TR);
    if cp <= 1 then Continue;
    // Wortgrenze hinter '.create' (Gegenpruefung 2026-08-26 MAJOR):
    // 'TWorker.CreateFromFile' darf NICHT nach dem schlichten Ctor
    // 'TWorker.Create' beurteilt werden - Vorbild MatchesCreate/
    // SplitCreateCall pruefen das Folgezeichen ebenfalls.
    if (cp + 7 <= Length(TR)) and TDetectorUtils.IsIdentChar(TR[cp + 7]) then
      Continue;
    ClassLow := Trim(Copy(TR, 1, cp - 1));
    if (ClassLow = '') or (Pos('.', ClassLow) > 0) or
       (Pos('(', ClassLow) > 0) then Continue;
    // Eindeutigen Instanz-Ctor dieser Unit suchen.
    Ctor := nil; Cnt := 0;
    for N in AUnitNode.FindAllRef(nkMethod) do
      if StartsStr('constructor', N.TypeRef.ToLower) and
         (Pos(';class', N.TypeRef.ToLower) = 0) and
         (N.Name.ToLower = ClassLow + '.create') then
      begin
        Inc(Cnt);
        Ctor := N;
      end;
    if (Cnt <> 1) or (Ctor = nil) then Continue;
    for CA in Ctor.FindAllRef(nkAssign) do
      if CA.TypeRef.ToLower.Trim.Equals('true') then
      begin
        TR := CA.Name.ToLower;
        // NUR das eigene Flag (Gegenpruefung 2026-08-26 MAJOR): ein
        // generisches '.freeonterminate'-Suffix traefe auch FREMDE
        // Empfaenger ('FWatcher.FreeOnTerminate := True' im Ctor,
        // JvCommStatus-Muster) - dann gaebe der Ctor eines Hosts,
        // der einen selbstfreigebenden KIND-Thread startet, das Leak
        // des Hosts selbst frei.
        if (TR = 'freeonterminate') or (TR = 'self.freeonterminate') then
          Exit(True);
      end;
  end;
end;

function CtorRegistersSelfWithFirstArg(AUnitNode, MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
const
  MAX_ANCESTOR_HOPS = 8;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  ClassLow, FirstArg, FirstArgOrig : string;

  function ClassParentLow(const AClassLow: string): string;
  var
    Lst : TList<TAstNode>;
    N   : TAstNode;
  begin
    Result := '';
    Lst := AUnitNode.FindAllRef(nkClass);
    for N in Lst do
      if (N.Name.ToLower = AClassLow) and (Trim(N.TypeRef) <> '') then
        Exit(FirstTypeIdentLow(N.TypeRef));
  end;

  function CtorOf(const AClassLow: string; out AAmbiguous: Boolean): TAstNode;
  // Ctor-IMPLEMENTIERUNG '<Klasse>.Create' dieser Unit, TRI-STATE:
  //   Result <> nil                 - genau ein Ctor, aufgeloest,
  //   Result = nil, AAmbiguous=False - kein Ctor auf dieser Stufe (der
  //                                    Aufrufer darf zum Vorfahren klettern),
  //   Result = nil, AAmbiguous=True  - Overloads; welche Ueberladung gemeint
  //                                    war, ist nicht entscheidbar.
  // REVIEW-BLOCKER 2026-07-31: vorher lieferte die Funktion in BEIDEN nil-
  // Faellen dasselbe, und die Aufrufschleife kletterte auch bei Overloads zum
  // Vorfahren weiter. Eine Klasse mit ueberladenen Konstruktoren wurde dann
  // nach dem registrierenden Ctor des VORFAHREN beurteilt - genau das, was
  // Strenge-Regel (3) ausschliessen soll.
  // Class-Konstruktoren (Parser-Marker ';class' im TypeRef) sind KEINE
  // Instanz-Ctoren: 'TFoo.Create(AParent)' kann sie nie meinen, sie duerfen
  // die Aufloesung also weder tragen noch mehrdeutig machen.
  var
    Lst : TList<TAstNode>;
    N   : TAstNode;
    TR  : string;
    Cnt : Integer;
  begin
    Result     := nil;
    AAmbiguous := False;
    Cnt        := 0;
    Lst := AUnitNode.FindAllRef(nkMethod);
    for N in Lst do
    begin
      TR := N.TypeRef.ToLower;
      if StartsStr('constructor', TR) and (Pos(';class', TR) = 0) and
         (N.Name.ToLower = AClassLow + '.create') then
      begin
        Inc(Cnt);
        Result := N;
      end;
    end;
    if Cnt <> 1 then
    begin
      AAmbiguous := Cnt > 1;
      Result     := nil;
    end;
  end;

  function FirstParamNameLow(ACtor: TAstNode): string;
  var
    P   : TAstNode;
    S   : string;
    Mod_: string;
  begin
    Result := '';
    // NUR direkte Kinder - FindAllRef waere subtree-weit und fischte die
    // Parameter verschachtelter Routinen mit.
    for P in ACtor.Children do
    begin
      if P.Kind <> nkParam then Continue;
      S := Trim(P.Name.ToLower);
      for Mod_ in ['var ', 'const ', 'out '] do
        if StartsStr(Mod_, S) then S := Trim(Copy(S, Length(Mod_) + 1, MaxInt));
      Exit(S);
    end;
  end;

  function CtorHandsSelfToFirstParam(const AClassLow: string): Boolean;
  var
    Cur, ParamLow : string;
    Ctor, N, C    : TAstNode;
    Stack         : TList<TAstNode>;
    hop           : Integer;
    Ambiguous     : Boolean;
  begin
    Result := False;
    Cur    := AClassLow;
    // KEIN `Ctor := nil` hier - der Compiler weist es als tote Zuweisung ab
    // (H2077, 2026-08-01). Begruendung, die beim Aendern gelten muss:
    // MAX_ANCESTOR_HOPS ist 8, die Schleife laeuft also mindestens einmal und
    // setzt Ctor VOR jedem Lesen. Die beiden Exits darin (leerer Vorfahre,
    // Overload-Mehrdeutigkeit) lesen Ctor nicht. Wer die Konstante auf 0
    // setzt, muss die Initialisierung zurueckholen - dann liest `if Ctor = nil`
    // unten eine uninitialisierte Referenz.
    for hop := 1 to MAX_ANCESTOR_HOPS do
    begin
      if Cur = '' then Exit;
      Ctor := CtorOf(Cur, Ambiguous);
      // Overloads auf DIESER Stufe: Abbruch statt Klettern. Der Vorfahren-Ctor
      // beweist nichts ueber die hier gewaehlte Ueberladung -> kein Gate, der
      // Fund bleibt stehen (konservative Richtung).
      if Ambiguous then Exit;
      if Ctor <> nil then Break;
      Cur := ClassParentLow(Cur);
    end;
    if Ctor = nil then Exit;
    ParamLow := FirstParamNameLow(Ctor);
    if ParamLow = '' then Exit;
    Stack := TList<TAstNode>.Create;
    try
      Stack.Add(Ctor);
      while Stack.Count > 0 do
      begin
        N := Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if RegisterCallPassesSelf(N.Name, ParamLow) or
           RegisterCallPassesSelf(N.TypeRef, ParamLow) then
          Exit(True);                  // finally gibt Stack frei
        for C in N.Children do Stack.Add(C);
      end;
    finally
      Stack.Free;
    end;
  end;

begin
  Result := False;
  if (AUnitNode = nil) or (MethodNode = nil) then Exit;
  Assigns := MethodNode.FindAllRef(nkAssign);
  for A in Assigns do
  begin
    if A.Name.ToLower <> VarNameLow then Continue;
    if not SplitCreateCall(A.TypeRef, ClassLow, FirstArg, FirstArgOrig) then Continue;
    if ClassLow = '' then Continue;
    if not IsPlainObjectExprLow(FirstArg) then Continue;
    if (FirstArg = VarNameLow) or StartsStr(VarNameLow + '.', FirstArg) then Continue;
    if CtorHandsSelfToFirstParam(ClassLow) then Exit(True);
  end;
end;

{ ---- Öffentliche API ---- }

class procedure TLeakDetector2.AnalyzeMethod(UnitNode, MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);

  // ARC-HINWEIS (2026-08-28, aus der SCA001-Vollzaehlung): erbt der
  // DEKLARATIONSTYP der Variablen von TInterfacedObject, KANN die
  // Referenzzaehlung das Objekt freigeben - der letzte Release ruft
  // Destroy. Ein fehlendes Free ist dann kein BEWIESENES Leck mehr.
  //
  // WARUM NUR EIN DEMOTE UND KEIN DROP - am Korpus gemessen, nicht
  // angenommen: von 568 SCA001-Funden erben 28 von TInterfacedObject,
  // und 26 davon sind tatsaechlich Fehlalarme. Einer ist es NICHT:
  // jcl .../Dummy/DummyRevisionProvider.pas:39 haelt einen
  // TStreamAdapter (erbt TInterfacedObject) in einer OBJEKT-Variablen,
  // uebergibt ihn nirgends an eine Interface-Referenz und gibt ihn nie
  // frei - der Refcount bleibt 0, das Leck ist echt.
  //
  // Der Grund ist die Delphi-Regel selbst: die Referenzzaehlung greift
  // erst, wenn das Objekt an eine INTERFACE-Referenz gebunden wird.
  //     var X: TFoo;  X := TFoo.Create;   // Refcount 0 -> LECK
  //     var X: IFoo;  X := TFoo.Create;   // Refcount 1 -> frei
  // Beide Zeilen erben von TInterfacedObject; nur die zweite ist
  // harmlos. Bemerkenswert: in ALLEN 28 Korpusfaellen ist die Variable
  // OBJEKT-typisiert - die 26 harmlosen sind es nur deshalb, weil das
  // Objekt SPAETER an einen Interface-Parameter geht. Genau das kann
  // dieser Detektor dateilokal nicht sehen (die Signatur der gerufenen
  // Routine liegt meist in einer fremden Unit).
  //
  // Deshalb: Konfidenz herunter statt Fund weg. Der Befund verlaesst
  // ueber die Evidenz-Politik den Error-Tier ("Error = bewiesen"),
  // bleibt aber sichtbar - ein echtes Leck wie das oben genannte geht
  // nicht verloren.
  function InheritsFromInterfacedObject(const ATypeRef: string): Boolean;
  var
    TI  : TTypeIndex;
    Low : string;
  begin
    Result := False;
    TI := CtxTypeIndex(AContext);
    // Single-File-Pfad: kein Index -> kein Hinweis, Verhalten wie bisher.
    if (TI = nil) or TI.IsEmpty then Exit;
    Low := Trim(ATypeRef).ToLower;
    if Low = '' then Exit;
    // IsDescendantOf ist homonym-fest (AddKindStrong-Muster im Index) -
    // das ist hier keine Kuer: TStringBuilder gibt es im Korpus ZWEIMAL,
    // einmal als RTL-Klasse und einmal als class(TInterfacedObject,
    // IStringBuilder) in einer JVCL-Hilfsunit. Eine namensbasierte
    // Hierarchie wirft beide zusammen.
    Result := TI.IsDescendantOf(Low, 'tinterfacedobject');
  end;

  procedure AddFinding(const MissingVar: string; Sev: TLeakSeverity;
    VLine: Integer; ARefCounted: Boolean = False);
  var
    F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(VLine);
    F.MissingVar := MissingVar;
    F.Severity   := Sev;
    F.Kind       := fkMemoryLeak;
    if ARefCounted then
      F.Confidence := fcMedium          // s. InheritsFromInterfacedObject
    else
      F.Confidence := KindDefaultConfidence(fkMemoryLeak);
    Results.Add(F);
  end;

var
  LocalVars    : TList<TAstNode>;
  V            : TAstNode;
  VarNameLow   : string;
  FreeFound    : Boolean;
  FreeInFin    : Boolean;
  HasFinally   : Boolean;
  StrippedLines: TArray<string>;   // finally-Mis-Attachment-Fix (lazy)
  StrippedReady: Boolean;
  SrcLines     : TStringList;
  SrcOwned     : Boolean;

  procedure EnsureStripped;
  // Lazy: erst wenn eine lsWarning ('Free ausserhalb finally') anstehen wuerde.
  // Nutzt den geteilten Strip-Cache (einmal pro Datei) und splittet in Zeilen.
  var
    Code    : string;
    LineFor : TArray<Integer>;
  begin
    if StrippedReady then Exit;
    StrippedReady := True;   // auch bei Fehlschlag nicht erneut versuchen
    SrcLines := AcquireLines(FileName, SrcOwned, CtxFileTextCache(AContext));
    if SrcLines = nil then Exit;
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      SrcLines, LineFor, AContext, FileName, ' ');
    StrippedLines := Code.Split([#10]);
  end;

begin
  StrippedReady := False;
  SrcLines      := nil;
  SrcOwned      := False;
  LocalVars := MethodNode.FindAllRef(nkLocalVar);
  try
    HasFinally := HasTryFinallyBlock(MethodNode);  // schleifeninvariant: einmal vor der Schleife statt pro Var
    for V in LocalVars do
    begin
      if not IsLeakyType(V.TypeRef, AContext) then Continue;

      // Werttyp-Gate (Gross-Triage 2026-07-18): eine record-typisierte Local
      // ('sz := TSizeF.Create(..)' / TRegEx) ist ein WERT auf dem Stack -
      // Record-Konstruktoren allokieren nichts Freigebbares -> kann nie leaken.
      // Cross-unit via TTypeIndex (tkiRecord, inkl. RTL-Seeds); TI=nil im
      // Single-File -> No-Op. TP-safe-by-construction, monoton.
      var TI := CtxTypeIndex(AContext);
      if (TI <> nil) and (not TI.IsEmpty) and
         (TI.TypeKindOf(Trim(V.TypeRef.ToLower)) = tkiRecord) then Continue;

      VarNameLow := V.Name.ToLower;

      // ── Pfad 1: direkte .Create-Zuweisung ──────────────────────────────────
      // Inkr.2: Instanz-Factory ('mgr.CreateOptionFromFile' / '(x as IFoo).
      // CreateY') ist KEINE direkte Konstruktion. Pfad 2 skippt '.create'-RHS
      // ebenfalls -> die Var wird komplett uebersprungen (Triage: 13/13
      // Instanz-Factory-Results waren fremd-owned; IDE/Container besitzen).
      if HasCreateAssign(MethodNode, VarNameLow)
         and not AllCreatesAreInstanceFactory(MethodNode, VarNameLow) then
      begin
        if IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
        // Zweiter Rueckgabeweg: out-/var-Parameter (2026-08-01).
        if IsAssignedToOutParam(MethodNode, VarNameLow) then Continue;
        // UnitNode (2026-07-31): schaltet die Unit-lokale Alias-Aufloesung des
        // Add-Empfaengers frei (Regressionsfall 'TPeople = TObjectList<TPerson>').
        if IsPassedToOwner(MethodNode, VarNameLow, UnitNode) then Continue;
        // FP-Gate (2026-07-04): owner-parameter - TKlasse.Create(Self/
        // Owner/AOwner/Application) uebergibt Ownership an den Owner
        // (TComponent-Konvention) -> kein Fund. Create(nil) meldet weiter.
        if IsOwnerParamCreate(MethodNode, VarNameLow) then Continue;
        // Inkr.2: Interface-Cast-Uebergabe / raise-Ownership (Gross-Triage
        // iface-cast-Bucket 15/101 + Batch 8 'raise LException').
        if IsHandedToInterface(MethodNode, VarNameLow) then Continue;
        if IsRaisedAsException(MethodNode, VarNameLow) then Continue;
        // FP-Gate (2026-07-31, FP-Klasse 2 'TComponent-/Owner-Ownership'):
        // 'TFoo.Create(<Owner-Ausdruck>, ...)' mit nicht-nil Objekt-Ident als
        // erstem Argument = Component-Ownership, der Owner raeumt ab.
        if IsComponentOwnerCreate(MethodNode, VarNameLow,
             Trim(V.TypeRef.ToLower), AContext) then Continue;
        // FP-Gate (2026-07-31, Parser-Gate-Backlog 4e/1): der Callee-Ctor
        // DERSELBEN Unit haengt sich per '<ErsterParam>.Add(Self)' in eine
        // besitzende Liste des uebergebenen Parents (jvcl JvInspector).
        if CtorRegistersSelfWithFirstArg(UnitNode, MethodNode, VarNameLow) then
          Continue;
        // FP-Gate (Autopsie 2026-08-26, Klasse 5): selbstfreigebender
        // Thread - FreeOnTerminate := True im eigenen Ctor dieser Unit.
        if CtorSetsFreeOnTerminate(UnitNode, MethodNode, VarNameLow) then
          Continue;

        FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

        // Befund auf der Create-Zeile melden statt auf der var-Decl-Zeile.
        // Bessere UX (Klick im Grid -> Allokation), und macht inline
        // // noinspection-Marker direkt ueber dem Create wirksam.
        var ReportLine := FindCreateLine(MethodNode, VarNameLow);
        if ReportLine = 0 then ReportLine := V.Line;

        if not FreeFound then
        begin
          // FP-Gate (2026-07-31, FP-Klasse 1 'Ownership-Transfer an Senken'):
          // letzter Use ist die Uebergabe an eine besitzende Senke bzw. an einen
          // fremden Konstruktor. Bewusst ERST hier (nicht bei den uebrigen
          // Gates): der Subtree-Walk laeuft dann nur fuer Variablen, die
          // tatsaechlich gemeldet wuerden - Hot-Path-Schutz.
          if not LastUseIsOwnershipTransfer(MethodNode, VarNameLow) then
            AddFinding(V.Name, lsError, ReportLine,
                       InheritsFromInterfacedObject(V.TypeRef));
        end
        else if not FreeInFin and HasFinally
             and not HasExceptFreeRaise(MethodNode, VarNameLow) then
        begin
          // Prio-5-Gate: der Free steckt in einem re-raisenden except-Handler
          // (try..except VarName.Free; raise; end) - Ausnahme-Pfad-Cleanup,
          // aequivalent zu finally -> kein "Free ausserhalb finally"-Befund.
          // finally-Mis-Attachment-Fix (2026-07-13): der AST sagt "nicht im
          // finally", aber in der QUELLE liegt der Free doch in einer finally-
          // Region (nested-/cond-comp-/'F:=nil;try'-Parser-Fehlattachierung) ->
          // dann ebenfalls kein Befund. NUR dieser lsWarning-Zweig; der Leak-
          // (lsError-)Pfad oben ist unberuehrt -> kann nie einen Leak maskieren.
          EnsureStripped;
          if not FreeInFinallyRegionBySource(MethodNode, StrippedLines, VarNameLow)
             and not LastUseIsOwnershipTransfer(MethodNode, VarNameLow) then
            AddFinding(V.Name, lsWarning, ReportLine);
        end;

        Continue;
      end;

      // ── Pfad 2: Funktionsaufruf-Zuweisung — list := BuildList(...) ──────────
      if not HasFunctionCallAssign(UnitNode, MethodNode, VarNameLow) then Continue;

      if IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
      if IsAssignedToOutParam(MethodNode, VarNameLow) then Continue;
      if IsPassedToOwner(MethodNode, VarNameLow, UnitNode) then Continue;
      // Inkr.2: Interface-Cast-Uebergabe / raise-Ownership auch fuer den
      // Rueckgabewert-Pfad (dasselbe Ownership-Argument).
      if IsHandedToInterface(MethodNode, VarNameLow) then Continue;
      if IsRaisedAsException(MethodNode, VarNameLow) then Continue;

      FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

      if not FreeFound then
      begin
        // FP-Gate (2026-07-31, FP-Klasse 1): identisch zum Create-Pfad - der
        // letzte Use gibt das Objekt an eine besitzende Senke ab
        // ('Item := NewItem(...); ... AddMenuItem(Item);' - JvMRUList.pas:424).
        if LastUseIsOwnershipTransfer(MethodNode, VarNameLow) then Continue;
        var ReportLine := FindFuncCallAssignLine(MethodNode, VarNameLow);
        if ReportLine = 0 then ReportLine := V.Line;
        AddFinding(V.Name + ' - R'#$FC'ckgabewert', lsWarning, ReportLine);
      end;
    end;
  finally
    if SrcLines <> nil then ReleaseLines(SrcLines, SrcOwned);
  end;
end;

class procedure TLeakDetector2.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methods  : TList<TAstNode>;
  M        : TAstNode;
  Seen     : TDictionary<string, Boolean>;
  StartIdx : Integer;
  i        : Integer;
  Key      : string;
begin
  // Geltungsbereich-Gate (2026-08-05, ausdrueckliche Produktentscheidung):
  // Funde in Test-, Sample- und Demo-Pfaden werden nicht gemeldet.
  //
  // Das ist bewusst KEINE Korrektheitsaussage - ein Leck leckt auch im Test.
  // Es ist eine Entscheidung ueber den Geltungsbereich der Regel: der
  // Nutzer soll Lecks in seinem PRODUKTIONSCODE sehen, nicht in Fixtures,
  // Beispielen und Archivstaenden fremder Bibliotheken. Beim Anziehen des
  // Gates ist bekannt und in Kauf genommen, dass echte Lecks in solchen
  // Pfaden mit wegfallen (in einer Stichprobe von zehn Funden waren drei
  // davon echt).
  //
  // GEMESSEN vor dem Bau (Korpus after140, 1093 Funde): 386 Treffer = 35 %,
  // ueber Verzeichnis-Segmente - 'tests' 191, 'samples' 76, 'unittests' 47,
  // 'demos' 37, 'test' 35.
  //
  // Muster kommen aus der projektweiten Definition, KEINE eigene Liste
  // (Fund 3, Restschulden-Audit 2026-07-26).
  //
  // Stufe tplFixtureDir = NUR Verzeichnis-Segmente, KEINE Dateinamen.
  // Zwei Gruende, beide gemessen:
  //   * Von den 386 Treffern kam KEINER ueber ein Basename-Muster - die
  //     Basename-Regeln ('*Sample.pas', '*Demo.pas', ...) haetten also
  //     nichts gebracht, aber im Kundencode jede Datei mit solchem Namen
  //     stillgelegt.
  //   * Der Test-Harness uebergibt den blossen Platzhalter 'sample.pas'
  //     ohne Pfad. Mit Basename-Matching war der Detektor im GESAMTEN
  //     Harness stumm - alle Leak-Tests fielen auf 0 Funde (2026-08-05).
  //     Ohne Segmente im Pfad greift das Gate jetzt nicht mehr.
  // Verankert an der Scanwurzel: nur Segmente UNTERHALB zaehlen als
  // Testverzeichnis. Unverankert traf das Gate auch Segmente des
  // Checkout-Pfads (C:/Users/test/..., D:/Demos/...) und legte den
  // Detektor fuer komplette Produktionsprojekte still. Ohne Kontext
  // ('' - Tests, Direktaufrufe) gilt das dokumentierte Alt-Verhalten.
  if TDetectorUtils.IsTestFixturePath(FileName,
       CtxScanRoot(AContext), tplFixtureDir) then Exit;

  StartIdx := Results.Count;
  Methods := UnitNode.FindAllRef(nkMethod);
  for M in Methods do
    AnalyzeMethod(UnitNode, M, FileName, Results, AContext);

  // Dedup (2026-07-04): Bei conditional-compilation-lastigen Units (z.B.
  // Synapse blcksock mit {$IFDEF CIL}) verschachtelt der Parser Methoden
  // ineinander. Dann sammelt AnalyzeMethod's FindAll(nkLocalVar) REKURSIV
  // dieselbe lokale Variable aus eingebetteten Methoden mehrfach ein, und
  // AnalyzeUnit's FindAll(nkMethod) analysiert verschachtelte Methoden ein
  // zweites Mal -> identischer Leak-Fund (gleiche Zeile + Variable) N-fach.
  // Zwei Funde mit gleicher (Zeile|MissingVar) betreffen dieselbe
  // Allokation und sind per Definition redundant -> nur den ersten behalten.
  Seen := TDictionary<string, Boolean>.Create;
  try
    i := StartIdx;
    while i < Results.Count do
    begin
      Key := Results[i].LineNumber + '|' + Results[i].MissingVar;
      if Seen.ContainsKey(Key) then
        Results.Delete(i)          // TObjectList(True) -> gibt den Fund frei
      else
      begin
        Seen.Add(Key, True);
        Inc(i);
      end;
    end;
  finally
    Seen.Free;
  end;
end;

end.
