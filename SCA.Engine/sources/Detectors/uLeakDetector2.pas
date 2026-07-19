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
    class function IsPassedToOwner(MethodNode: TAstNode;
      const VarNameLow: string): Boolean; static;
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
    class function AddReceiverOwnsItems(MethodNode: TAstNode;
      const ReceiverNameLow: string): Boolean; static;
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

var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RHS     : string;
  DotP    : Integer;
begin
  Result  := False;
  // Klasse der analysierten Methode ('tmeineklasse.foo' -> 'tmeineklasse').
  ThisClassLow := '';
  DotP := LastDelimiter('.', MethodNode.Name);
  if DotP > 0 then ThisClassLow := LowerCase(Copy(MethodNode.Name, 1, DotP - 1));

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
      if OwningReturnCall(A.TypeRef) then Exit(True);
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
      Exit(True);
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

class function TLeakDetector2.AddReceiverOwnsItems(MethodNode: TAstNode;
  const ReceiverNameLow: string): Boolean;
// Pflicht-Whitelist: Receiver-Typ matched einen ownership-bewussten
// Container. Liste praktisch begrenzt - die Default-RTL-Container
// die wirklich Free auf Items rufen.
const
  OWNING_PREFIXES : array[0..6] of string = (
    'tobjectlist',         // TObjectList<T>(True), TObjectList(True)
    'tobjectdictionary',   // TObjectDictionary
    'tobjectqueue',
    'tobjectstack',
    'tcomponentlist',      // VCL
    'townedcollection',    // VCL
    'tinterfacelist'       // refcount-managed - effektiv ownership-aequiv
  );

  function TypeMatches(const TypeLow: string): Boolean;
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
    if TypeLow = '' then Exit;       // sollte nicht passieren, defensiv
    Result := TypeMatches(TypeLow);  // strikte Pruefung gegen Whitelist
  end;
end;

class function TLeakDetector2.IsPassedToOwner(MethodNode: TAstNode;
  const VarNameLow: string): Boolean;
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
        if AddReceiverOwnsItems(MethodNode, receiverLow) then
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
      if SameText(Copy(LHSOrig, 1, 5), 'self.') then
        Exit(True);
      if (Length(LHSOrig) >= 2) and (LHSOrig[1] = 'F') and
         (LHSOrig[2] >= 'A') and (LHSOrig[2] <= 'Z') then
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
        if AddReceiverOwnsItems(MethodNode, receiverLow) then
          Exit(True);
      end;
    end;

    // TStringList.AddObject(text, obj) - klassisches Object-Owner-Pattern
    // (var-Deklaration hier: der fruehere gemeinsame 'pAdd' ist seit A2 in den
    // Add-Familie-for-Loop gewandert und dort scope-lokal.)
    var pAdd := Pos('.addobject(', NameLow);
    if (pAdd > 0) and VarInArgs(NameLow, pAdd + 11) then
      Exit(True);

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
          if AddReceiverOwnsItems(MethodNode, recvLow) then
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
      try
        for Child in Node.Children do WStack.Add(Child);
        while WStack.Count > 0 do
        begin
          var W := WStack[WStack.Count - 1];
          WStack.Delete(WStack.Count - 1);
          if W.Kind = nkCall then
          begin
            var WLow := W.Name.ToLower;
            if (WLow = 'free') or (WLow = 'free()')
               or (WLow = 'destroy') or (WLow = 'disposeof') then
            begin
              Result := True; FoundInFinally := InFinally;
              Exit;   // finally gibt WStack frei
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
          for var WC in W.Children do WStack.Add(WC);
        end;
      finally
        WStack.Free;
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
// (SubtreeMaxLine). Monoton (nur zusaetzliche Suppression); TP-safe: greift nur
// bei bewiesenem VarName-Free innerhalb einer balancierten finally..end-Region
// INNERHALB der Methode. StrippedLines: Index k-1 == Quellzeile k.
var
  StartL, EndL, li, MethStart, MethEnd : Integer;

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

  // Groesste Quellzeile im Method-Subtree (iterative DFS, Hardening-v4-Stil).
  // Obergrenze der Scan-Spanne - verhindert, dass finally-Regionen NACH der
  // Methode (naechste Routine) mitgescannt werden.
  function SubtreeMaxLine(Root: TAstNode): Integer;
  var
    Stack : TList<TAstNode>;
    N, C : TAstNode;
  begin
    Result := 0;
    if Root = nil then Exit;
    Stack := TList<TAstNode>.Create;
    try
      Stack.Add(Root);
      while Stack.Count > 0 do
      begin
        N := Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if N.Line > Result then Result := N.Line;
        for C in N.Children do Stack.Add(C);
      end;
    finally
      Stack.Free;
    end;
  end;

begin
  Result := False;
  if (MethodNode = nil) or (Length(StrippedLines) = 0) then Exit;

  MethStart := MethodNode.Line;
  if MethStart < 1 then MethStart := 1;
  MethEnd := SubtreeMaxLine(MethodNode);
  if MethEnd > Length(StrippedLines) then MethEnd := Length(StrippedLines);
  if MethEnd < MethStart then Exit;

  for StartL := MethStart to MethEnd do
  begin
    if not LineHasFinally(StrippedLines[StartL - 1]) then Continue;
    EndL := TryEndLine(StartL);
    if EndL > MethEnd then EndL := MethEnd;    // Region auf die Methode klammern
    for li := StartL to EndL do
      if (li >= 1) and (li <= Length(StrippedLines))
         and LineFreesVar(StrippedLines[li - 1]) then
        Exit(True);
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
  Result := False;
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

{ ---- Öffentliche API ---- }

class procedure TLeakDetector2.AnalyzeMethod(UnitNode, MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);

  procedure AddFinding(const MissingVar: string; Sev: TLeakSeverity;
    VLine: Integer);
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
        if IsPassedToOwner(MethodNode, VarNameLow)    then Continue;
        // FP-Gate (2026-07-04): owner-parameter - TKlasse.Create(Self/
        // Owner/AOwner/Application) uebergibt Ownership an den Owner
        // (TComponent-Konvention) -> kein Fund. Create(nil) meldet weiter.
        if IsOwnerParamCreate(MethodNode, VarNameLow) then Continue;
        // Inkr.2: Interface-Cast-Uebergabe / raise-Ownership (Gross-Triage
        // iface-cast-Bucket 15/101 + Batch 8 'raise LException').
        if IsHandedToInterface(MethodNode, VarNameLow) then Continue;
        if IsRaisedAsException(MethodNode, VarNameLow) then Continue;

        FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

        // Befund auf der Create-Zeile melden statt auf der var-Decl-Zeile.
        // Bessere UX (Klick im Grid -> Allokation), und macht inline
        // // noinspection-Marker direkt ueber dem Create wirksam.
        var ReportLine := FindCreateLine(MethodNode, VarNameLow);
        if ReportLine = 0 then ReportLine := V.Line;

        if not FreeFound then
          AddFinding(V.Name, lsError, ReportLine)
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
          if not FreeInFinallyRegionBySource(MethodNode, StrippedLines, VarNameLow) then
            AddFinding(V.Name, lsWarning, ReportLine);
        end;

        Continue;
      end;

      // ── Pfad 2: Funktionsaufruf-Zuweisung — list := BuildList(...) ──────────
      if not HasFunctionCallAssign(UnitNode, MethodNode, VarNameLow) then Continue;

      if IsReturnedAsResult(MethodNode, VarNameLow) then Continue;
      if IsPassedToOwner(MethodNode, VarNameLow)    then Continue;
      // Inkr.2: Interface-Cast-Uebergabe / raise-Ownership auch fuer den
      // Rueckgabewert-Pfad (dasselbe Ownership-Argument).
      if IsHandedToInterface(MethodNode, VarNameLow) then Continue;
      if IsRaisedAsException(MethodNode, VarNameLow) then Continue;

      FreeFound := SearchFree(MethodNode, VarNameLow, False, FreeInFin);

      if not FreeFound then
      begin
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
