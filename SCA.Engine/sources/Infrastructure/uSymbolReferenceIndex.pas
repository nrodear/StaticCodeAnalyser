unit uSymbolReferenceIndex;

// Repo-weiter Index ueber Cross-Unit-Referenzen auf Klassen-Member.
// Wird von Visibility-Detektor `uVisibilityCheck` konsultiert (siehe
// HasExternalRefs-Aufrufe dort) - wenn ein Member extern referenziert
// ist, unterdrueckt der Detektor das Finding.
//
// Aufbau-Modell (analog uDfmRepoIndex), 2-Pass:
//   * Aufrufer (TStaticAnalyzer2) ruft Build(FileList) einmal pro Scan.
//   * Pass 1: alle Public-/Published-Member-Namen aus Klassen-
//     Deklarationen sammeln in FPublicMembers (Set).
//   * Pass 2: pro File AddRefsFromNode - sammelt:
//       - dotted nkCall + nkAssign LHS (Pattern Obj.Member)
//       - dotted Refs in TypeRef-Strings von if/while/case/assign/for
//         (Conditions) - A.3+ Phase 1
//       - dotted Property-Reads ohne Klammern (F.SeverityText) -
//         A.3+ Punkt 1
//       - BARE nkCall WENN Name in FPublicMembers - A.3+ Punkt 3
//         (verhindert FP-Explosion bei RTL-Standardfunktionen)
//       - dotted Refs in den ARGUMENTEN von nkCall/nkRaise/nkInherited
//         (Charge D2, 2026-10-24) - jedes Kettenglied, Stringliterale
//         uebersprungen
//   * Grenze: bare Bezeichner in Ausdruecken ('with O do Show(Name)',
//     geerbter Member in einer Unterklasse einer fremden Unit) und
//     'Exit(O.Name)' werden nicht erfasst.
//   * Lookup pro Detektor-Lauf: "Wird MemberLow ausserhalb der eigenen
//     Unit referenziert?"
//
// Bewusste Vereinfachung:
//   * Wir tracken NUR den Member-Namen, nicht die volle Klassen-Qualifikation.
//     Das bedeutet: bei homonymen Member-Namen in mehreren Klassen
//     ueberzaehlen wir. Akzeptabler False-Negative-Bias (= Detector
//     schweigt wo er triggern koennte) -> reduziert False-Positives, weil
//     unsere Aufgabe "ist NICHT extern referenziert" ist; Ueberzaehlen
//     blockiert den Befund, nicht zu Unrecht.
//   * Wir filtern auf rein lowercase-Identifier-Tokens (mit Wortgrenzen),
//     damit textuelle Vorkommen in Strings/Kommentaren rausfallen - der
//     AST liefert das schon ohne diese Layer.
//
// Single-File-Pfad: wenn Build nie aufgerufen wird oder es keine externen
// Files gibt, sind alle Lookups leer. Der Detektor faellt dann auf die
// Single-Unit-Heuristik zurueck (alte Logik, mit Caveat-Text).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uCompatSet,  // D11: THashSet<T>-Ersatz (D12: leere Unit, natives THashSet)
  uAstNode, uAstFileCache;

type
  TSymbolReferenceIndex = class
  private
    // member-name-lowercase -> Set von Unit-Dateinamen, die ihn referenzieren
    FRefs : TDictionary<string, TStringList>;
    // A.3+ Punkt 3: Set aller public/published Member-Namen (lowercase).
    // Wird in Pass 1 vor AddRefsFromNode gefuellt - dient als Filter fuer
    // bare nkCall-Knoten, damit nicht jeder RTL-Aufruf (WriteLn, Inc, ...)
    // als hypothetischer Member-Ref zaehlt.
    FPublicMembers : THashSet<string>;
    // Per-Scan-AST-Cache (D.2.3 Infra): von Build statt gAstFileCache-Global.
    FAstCache : TAstFileCache;
    // Perf (2026-07-05): P9-symbolrefindex - 1-Slot-Memo fuer die OwnUnit-
    // Normalisierung in ExternalReferencingUnitCount. Der Visibility-
    // Detektor fragt pro Member derselben Datei mit identischem OwnUnit an;
    // ExpandFileName+LowerCase laeuft nur noch bei Datei-Wechsel.
    // Per-Instanz-State, Lifecycle = Index-Lebensdauer (per Scan gebaut).
    FOwnUnitRaw  : string;
    FOwnUnitNorm : string;

    procedure ScanUnitForMembers(const PasFileName: string);
    procedure ScanUnitForRefs(const PasFileName: string);
    procedure CollectPublicMembersFrom(RootNode: TAstNode);
    procedure AddRefsFromNode(RootNode: TAstNode; const SourceUnit: string);
    // Perf (2026-07-05): P9-symbolrefindex - Hot-Path-Variante ohne Pfad-
    // Re-Normalisierung; FromUnitNorm MUSS bereits durch NormalizeUnitPath
    // gelaufen sein (AddRefsFromNode normalisiert einmal pro Datei).
    procedure AddReferenceNormalized(const MemberName, FromUnitNorm: string);
  public
    constructor Create;
    destructor  Destroy; override;

    // Repo-weiten Scan ueber alle Pas-Dateien durchfuehren.
    procedure Build(FileList: TStringList; ACache: TAstFileCache = nil);

    // Manuelles Hinzufuegen (fuer Tests + spezielle Pipeline-Varianten).
    procedure AddReference(const MemberName, FromUnit: string);

    // Liefert die Anzahl unterschiedlicher Units, die MemberLow referenzieren -
    // ausschliesslich der eigenen Unit (case-insensitive).
    function ExternalReferencingUnitCount(const MemberLow,
      OwnUnit: string): Integer;

    // True, wenn MemberLow ueberhaupt von einer anderen Unit gerufen wird.
    function HasExternalRefs(const MemberLow, OwnUnit: string): Boolean;

    // Reports-Quick-Check: ist der Index leer (= Single-File-Mode)?
    function IsEmpty: Boolean;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeUnitPrivate, ConsecutiveSection, DuplicateBlock, FreeWithoutNil, GroupedDeclaration, LowercaseKeyword, NestedRoutine, NestedTry, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uParser2;

constructor TSymbolReferenceIndex.Create;
begin
  inherited;
  FRefs := TDictionary<string, TStringList>.Create;
  FPublicMembers := THashSet<string>.Create;
end;

destructor TSymbolReferenceIndex.Destroy;
var
  L : TStringList;
begin
  if Assigned(FRefs) then
  begin
    for L in FRefs.Values do
      L.Free;
    FRefs.Free;
  end;
  FPublicMembers.Free;
  inherited;
end;

// Konsistente Pfad-Normalisierung fuer den Vergleich zwischen "diese Unit"
// und "fremde Unit". Build laeuft mit absoluten Pfaden (ScanUnit bekommt
// PasFileName aus dem File-Listing); wenn der Detector-Aufrufer aber nur
// einen relativen oder bare Basename liefert, wuerde der Self-Filter in
// ExternalReferencingUnitCount nicht matchen und das eigene File faelschlich
// als externe Referenz zaehlen. ExpandFileName loest auf einen absoluten
// kanonischen Pfad auf; LowerCase ist case-insensitive (Windows-FS).
function NormalizeUnitPath(const Path: string): string;
// Dritte Normalisierung im Projekt, dritter Zweck: absoluter
// kanonischer Pfad. Die beiden anderen tauschen nur Trennzeichen -
// uPathOverrides.NormalizePath ("\" -> "/", Glob) und
// SCA.SharedUI/uPathNormalize ("/" -> "\", Cache-Schluessel).
begin
  if Path = '' then Exit('');
  Result := LowerCase(ExpandFileName(Path));
end;

procedure TSymbolReferenceIndex.AddReference(const MemberName,
  FromUnit: string);
begin
  // Oeffentlicher Pfad (Tests + spezielle Pipeline-Varianten): normalisiert
  // selbst - Verhalten unveraendert.
  AddReferenceNormalized(MemberName, NormalizeUnitPath(FromUnit));
end;

procedure TSymbolReferenceIndex.AddReferenceNormalized(const MemberName,
  FromUnitNorm: string);
// Perf (2026-07-05): P9-symbolrefindex - AddRefsFromNode ruft pro Datei
// tausendfach mit konstantem SourceUnit; ExpandFileName+LowerCase liefe
// dabei identisch pro Referenz. Hier keine Re-Normalisierung mehr;
// nebenbei landet dieselbe String-Instanz (refcounted) im Index statt
// je Aufruf einer frischen Kopie.
var
  Key : string;
  L : TStringList;
begin
  Key := LowerCase(Trim(MemberName));
  if Key = '' then Exit;
  if FromUnitNorm = '' then Exit;
  if not FRefs.TryGetValue(Key, L) then
  begin
    L := TStringList.Create;
    L.CaseSensitive := False;
    L.Sorted        := True;
    L.Duplicates    := dupIgnore;
    FRefs.Add(Key, L);
  end;
  L.Add(FromUnitNorm);
end;

procedure TSymbolReferenceIndex.AddRefsFromNode(RootNode: TAstNode;
  const SourceUnit: string);
var
  // Perf (2026-07-05): P9-symbolrefindex - SourceUnit ist fuer ALLE Refs
  // dieser Datei konstant; einmal normalisieren statt pro AddReference
  // (ExpandFileName+LowerCase liefen sonst pro Referenz, repo-weit
  // millionenfach). Deklaration VOR den nested Routinen, damit
  // ScanExprForDottedRefs sie sieht.
  SrcNorm : string;

  function ExtractRightOfDot(const S: string): string;
  // Bei 'Obj.Member(args)' -> 'Member'. Bei 'Bare(args)' -> 'Bare'.
  // Bei 'Obj.A.B' -> 'B' (tiefster Member-Access).
  // T3 (Review 2026-07-31): zusaetzlich am '<' kappen - seit dem
  // Generic-Suffix-Zweig traegt ein Statement-Call den Namen
  // 'TJsonUtil.Deserialize<TCustomer>(S)'; ohne den Cut entstuende der
  // tote Key 'deserialize<tcustomer>' und die einzige externe Referenz
  // des Members verschwaende aus dem Index (SCA052-Familie meldete
  // faelschlich 'Dead public API').
  var
    Trimmed : string;
    ParenPos, LtPos, LastDot : Integer;
  begin
    Trimmed := Trim(S);
    ParenPos := Pos('(', Trimmed);
    if ParenPos > 0 then
      Trimmed := Copy(Trimmed, 1, ParenPos - 1);
    LtPos := Pos('<', Trimmed);
    if LtPos > 0 then
      Trimmed := Copy(Trimmed, 1, LtPos - 1);
    LastDot := -1;
    for var i := Length(Trimmed) downto 1 do
      if Trimmed[i] = '.' then
      begin
        LastDot := i;
        Break;
      end;
    if LastDot > 0 then
      Result := Trim(Copy(Trimmed, LastDot + 1, MaxInt))
    else
      Result := Trim(Trimmed);
  end;

  function HasLhsBeforeDot(const S: string): Boolean;
  // True wenn da ein '.' vor dem Member ist (also Obj.Member-Pattern).
  var
    Trimmed : string;
  begin
    Trimmed := Trim(S);
    var ParenPos := Pos('(', Trimmed);
    if ParenPos > 0 then
      Trimmed := Copy(Trimmed, 1, ParenPos - 1);
    Result := Pos('.', Trimmed) > 0;
  end;

  // AUSNAHME von der Zentralisierung (Backlog-Welle 1, 2026-07-26): diese
  // Unit behaelt den lokalen Rumpf. Delegieren an TDetectorUtils.IsIdentChar
  // wuerde H2445 ausloesen (eine inline-Routine kann keine Inline-Funktion
  // expandieren, deren Unit nur implementation-seitig sichtbar ist), und der
  // uebliche Ausweg - uDetectorUtils in die interface-uses - scheidet hier
  // aus: uDetectorUtils zieht ueber uAnalyzeContext genau diese Unit wieder
  // herein, das waere ein zirkulaerer Unit-Verweis (F2047). Ohne Expansion
  // waere es ein echter Aufruf pro Zeichen - und das hier ist der heisseste
  // Scanner im Projekt (jeder Ausdruck jeder Datei).
  function IsIdentCharLocal(C: Char): Boolean; inline;
  begin
    Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;

  procedure ScanExprForDottedRefs(const Expr: string);
  // A.3+ Phase 1+2: TypeRef-Strings von nkIfStmt/nkWhileStmt/nkCaseStmt/
  // nkAssign/nkForStmt enthalten Member-Accesses die der Parser NICHT
  // als nkCall ablegt. Wir scannen die Strings nach 'Obj.Member'
  // Pattern und registrieren 'Member' als Cross-Unit-Reference.
  //
  // Erfasst BEIDES: Calls 'Obj.Method(...)' UND Property/Field-Reads
  // 'F.SeverityText' ohne Klammern. Bare Calls wie 'WriteLn(...)'
  // werden bewusst NICHT erfasst (kein Dot), sonst FP-Explosion bei
  // jedem RTL-Function-Aufruf.
  //
  // Trade-off: kann zu Under-Reporting bei Visibility-Detektoren
  // fuehren wenn ein TP-Member zufaellig denselben Namen hat wie ein
  // bare 'Obj.Field' irgendwo - bewusst akzeptiert (A.3-Audit).
  //
  // Links vom Punkt zaehlt auch das Ende eines AUSDRUCKS: ']' (A[i].Count),
  // ')' (Foo(x).Count, TFoo(P).Next) und '^' (P^.Next). Vorher stand dort
  // nur ein Bezeichner-Ende; die drei Formen fehlten in Bedingungen und
  // RHS, und SCA050-052/107/184 hielten einen extern benutzten Member fuer
  // unbenutzt (FP; Review Woche G03-18). Registriert wird wie immer nur
  // der Member rechts.
  //
  // Stringliterale zaehlen nicht (Charge D2, 2026-10-24): der Parser legt
  // sie in RHS, Bedingungen und Aufruf-Argumenten mit QuoteStrLit ab
  // ('...', inneres ' verdoppelt). Ohne den Sprung registrierte
  // 'Format(''%s.Name'', [X])' den Member 'Name' aus dem Text. Der for-
  // Kopf traegt Literale roh (ParseForStmt) - dort greift der Sprung nicht.
  //
  // Jedes Kettenglied zaehlt (Charge D2): 'A.B.C' registrierte bis
  // 2026-10-24 nur B - nach B lief der Scan ueber den Punkt hinweg und las
  // C als neuen KOPF, dem kein Punkt mehr folgte. In 'A.B.C.D' kamen so nur
  // B und D an. Jetzt wird das gerade registrierte Glied selbst zum Kopf.
  var
    i, L, StartSecond : Integer;
    MemberName : string;
  begin
    L := Length(Expr);
    i := 1;
    while i <= L do
    begin
      if Expr[i] = '''' then
      begin
        // Literal ueberspringen; '' im Inneren ist ein escaptes Apostroph.
        Inc(i);
        while i <= L do
        begin
          if Expr[i] = '''' then
          begin
            if (i < L) and (Expr[i + 1] = '''') then
            begin
              Inc(i, 2);
              Continue;
            end;
            Break;
          end;
          Inc(i);
        end;
        Inc(i);  // schliessendes '
        Continue;
      end;
      if CharInSet(Expr[i], [']', ')', '^']) then
        Inc(i)   // Ausdrucksende: weiter wie hinter einem Bezeichner
      else if not IsIdentCharLocal(Expr[i]) then
      begin
        Inc(i);
        Continue;
      end
      else
        // Erstes Ident (potentielles 'Obj')
        while (i <= L) and IsIdentCharLocal(Expr[i]) do Inc(i);
      // Leerraum um den Punkt ueberspringen: die if-Bedingung steht mit
      // einem Leerzeichen nach jedem Token im AST ('Obj . Member'), while/
      // case/for kompakt - beide Formen muessen den Member melden (sonst FP
      // VisibilityCheck, Review Bereich C Major 14; Bau 2026-10-14).
      while (i <= L) and (Expr[i] = ' ') do Inc(i);
      if (i > L) or (Expr[i] <> '.') then Continue;
      Inc(i);  // skip '.'
      while (i <= L) and (Expr[i] = ' ') do Inc(i);
      if (i > L) or not IsIdentCharLocal(Expr[i]) then Continue;
      // Zweites Ident (potentielles 'Member' = Property/Field/Method)
      StartSecond := i;
      while (i <= L) and IsIdentCharLocal(Expr[i]) do Inc(i);
      MemberName := Copy(Expr, StartSecond, i - StartSecond);
      AddReferenceNormalized(MemberName, SrcNorm);
      // Glied als neuen Kopf lesen (Kettenglieder, s.o.). Terminiert: der
      // naechste Durchlauf liest das Glied ganz und steht dann dahinter.
      i := StartSecond;
    end;
  end;

  procedure ScanArgsOf(const CallText: string);
  // Charge D2 (2026-10-24): die Argumente einer Aufruf-Anweisung legt
  // ParsePrimary VOLLSTAENDIG im Knotennamen ab ('Show(P.Summary(O))'),
  // registriert wurde aber nur der Kopf vor der ersten '(' ueber
  // ExtractRightOfDot. Ein Member, den eine fremde Unit nur als Argument
  // benutzt - 'ShowMessage(Calc.PriceLabel(Order.Customer))', 'Lines.Add(
  // ''x'' + O.CustomerCity)', 'Format(''%d'', [Imp.Stats.Imported])' -
  // fehlte im Index, und SCA052 meldete ihn als tote API (ShowcaseDemo:
  // Summary, PriceLabel, Stats, Customer, CustomerCity). Gescannt wird ab
  // der ersten '(' - der Kopf bleibt bei der bisherigen Regel (nur das
  // rechteste Glied, Test Build_NestedDottedAccess_RightmostIndexed).
  var
    ParenPos : Integer;
  begin
    ParenPos := Pos('(', CallText);
    if ParenPos > 0 then
      ScanExprForDottedRefs(Copy(CallText, ParenPos, MaxInt));
  end;

var
  Calls, Assigns, Ifs, Whiles, Cases, Fors, Raises, Inherits : TList<TAstNode>;
  N : TAstNode;
  Target : string;
begin
  // Perf (2026-07-05): P9-symbolrefindex - einmal pro Datei normalisieren.
  SrcNorm := NormalizeUnitPath(SourceUnit);

  // nkCall: jeder Call-Name ist ein Member-Aufruf. Wir extrahieren den
  // rightmost Identifier nach optionalem 'Obj.'.
  // A.3+ Punkt 3: bare-Calls werden registriert WENN ihr Name als
  // public/published Member irgendwo im Repo deklariert ist (FPublic-
  // Members aus Pass 1). RTL-Funktionen wie WriteLn/Inc/Length sind
  // nicht in dem Set -> kein FP-Explosion.
  Calls := RootNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      if HasLhsBeforeDot(N.Name) then
      begin
        Target := ExtractRightOfDot(N.Name);
        AddReferenceNormalized(Target, SrcNorm);
      end
      else
      begin
        Target := ExtractRightOfDot(N.Name);  // strippt nur '(args)'
        if (Target <> '') and FPublicMembers.Contains(LowerCase(Target)) then
          AddReferenceNormalized(Target, SrcNorm);
      end;
      ScanArgsOf(N.Name);
    end;
  finally
    Calls.Free;
  end;

  // Charge D2: dieselbe Argument-Luecke bei 'raise E.CreateFmt(.., [O.Name])'
  // und 'inherited Create(O.Owner)' - beide Knotennamen stammen ebenfalls
  // aus ParsePrimary (Literale gequotet). Der Kopf zaehlt hier NICHT: der
  // Exception-Konstruktor bzw. die geerbte Methode ist kein Fremdzugriff,
  // den der Index bisher kannte - nur die Argumente kommen neu dazu.
  // NICHT erfasst: 'Exit(O.Name)' - nkExit traegt sein Argument mit ROHEN
  // Stringliteralen in TypeRef, ein Text in Anfuehrungszeichen waere dort
  // von Code nicht zu unterscheiden.
  Raises := RootNode.FindAll(nkRaise);
  try
    for N in Raises do
      ScanArgsOf(N.Name);
  finally
    Raises.Free;
  end;
  Inherits := RootNode.FindAll(nkInherited);
  try
    for N in Inherits do
      ScanArgsOf(N.Name);
  finally
    Inherits.Free;
  end;

  // nkAssign: LHS kann 'Obj.Field' sein -> wir indexieren das Field.
  // PLUS A.3+ Phase 1: RHS-Text (TypeRef) nach dotted Calls scannen.
  Assigns := RootNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      if HasLhsBeforeDot(N.Name) then
      begin
        Target := ExtractRightOfDot(N.Name);
        AddReferenceNormalized(Target, SrcNorm);
      end;
      // RHS-Calls: 'X := Obj.GetValue()' -> 'GetValue' indexieren.
      if N.TypeRef <> '' then
        ScanExprForDottedRefs(N.TypeRef);
    end;
  finally
    Assigns.Free;
  end;

  // A.3+ Phase 1: nkIfStmt/nkWhileStmt/nkCaseStmt/nkForStmt enthalten
  // Conditions/Ranges als TypeRef-String. Dotted Calls darin auch
  // registrieren - sonst sieht der Visibility-Detektor SCA052 Members
  // wie 'TConfigFilter.ApplyToFindings(L, c)' nicht als extern referenziert.
  Ifs := RootNode.FindAll(nkIfStmt);
  try
    for N in Ifs do
      if N.TypeRef <> '' then ScanExprForDottedRefs(N.TypeRef);
  finally
    Ifs.Free;
  end;
  Whiles := RootNode.FindAll(nkWhileStmt);
  try
    for N in Whiles do
      if N.TypeRef <> '' then ScanExprForDottedRefs(N.TypeRef);
  finally
    Whiles.Free;
  end;
  Cases := RootNode.FindAll(nkCaseStmt);
  try
    for N in Cases do
      if N.TypeRef <> '' then ScanExprForDottedRefs(N.TypeRef);
  finally
    Cases.Free;
  end;
  Fors := RootNode.FindAll(nkForStmt);
  try
    for N in Fors do
      if N.TypeRef <> '' then ScanExprForDottedRefs(N.TypeRef);
  finally
    Fors.Free;
  end;
end;

procedure TSymbolReferenceIndex.CollectPublicMembersFrom(RootNode: TAstNode);
// Pass 1: alle public/published Member-Namen einer Unit ins Set
// FPublicMembers eintragen. Struktur im AST:
//   nkClass -> nkVisibilitySection (Name='published'/'public'/...)
//             -> nkMethod / nkField / nkProperty
// Default-Visibility ist 'published' (siehe TParser2.ParseClassBody).
var
  ClassNodes : TList<TAstNode>;
  CN, VisSection, Member : TAstNode;
  VisLow : string;
  i, j : Integer;
begin
  if RootNode = nil then Exit;
  ClassNodes := RootNode.FindAll(nkClass);
  try
    for CN in ClassNodes do
    begin
      for i := 0 to CN.Children.Count - 1 do
      begin
        VisSection := CN.Children[i];
        if VisSection.Kind <> nkVisibilitySection then Continue;
        VisLow := LowerCase(VisSection.Name);
        // Nur 'public' und 'published' interessieren. 'private' und
        // 'protected' sind per Definition nicht extern aufrufbar -> kein
        // bare-Call von ausserhalb der eigenen Unit moeglich. 'strict'
        // verwirft der Parser: 'strict private' heisst im AST 'private'
        // (T.Value in ParseClassBody), einen Sektionsnamen 'strictprivate'
        // gibt es nicht.
        if (VisLow <> 'public') and (VisLow <> 'published') then Continue;
        for j := 0 to VisSection.Children.Count - 1 do
        begin
          Member := VisSection.Children[j];
          if Member.Kind in [nkMethod, nkField, nkProperty] then
          begin
            // Bei Method kann der Name 'Outer.Inner' sein (qualified im
            // Type) - wir wollen nur den rightmost Identifier.
            var Nm := Member.Name;
            var DotPos := -1;
            for var k := Length(Nm) downto 1 do
              if Nm[k] = '.' then begin DotPos := k; Break; end;
            if DotPos > 0 then Nm := Copy(Nm, DotPos + 1, MaxInt);
            if Nm <> '' then
              FPublicMembers.Add(LowerCase(Trim(Nm)));
          end;
        end;
      end;
    end;
  finally
    ClassNodes.Free;
  end;
end;

procedure TSymbolReferenceIndex.ScanUnitForMembers(const PasFileName: string);
// Pass 1 pro File: parse + CollectPublicMembersFrom. FileCache greift
// in Pass 2 wieder fuer denselben Parse-Output.
var
  Parser  : TParser2;
  Root    : TAstNode;
  OwnsRoot: Boolean;
begin
  if not FileExists(PasFileName) then Exit;
  OwnsRoot := False;

  if Assigned(FAstCache) then
    Root := FAstCache.Acquire(PasFileName)
  else
  begin
    Parser := TParser2.Create;
    try
      try
        Root := Parser.ParseFile(PasFileName);
        OwnsRoot := True;
      except
        Exit;
      end;
    finally
      Parser.Free;
    end;
  end;

  if Root = nil then Exit;
  try
    CollectPublicMembersFrom(Root);
  finally
    if OwnsRoot then Root.Free;
  end;
end;

procedure TSymbolReferenceIndex.ScanUnitForRefs(const PasFileName: string);
// Cache-Pfad: wenn gAstFileCache assigned, einmaliger Parse pro Repo-Lauf
// (perf_analyse.md Hot-Spot 🅐). Cache besitzt das Root - NICHT free.
var
  Parser  : TParser2;
  Root    : TAstNode;
  OwnsRoot: Boolean;
begin
  if not FileExists(PasFileName) then Exit;
  OwnsRoot := False;

  if Assigned(FAstCache) then
    Root := FAstCache.Acquire(PasFileName)
  else
  begin
    Parser := TParser2.Create;
    try
      try
        Root := Parser.ParseFile(PasFileName);
        OwnsRoot := True;
      except
        // Defekte .pas - silent skip, wie bei uDfmRepoIndex
        Exit;
      end;
    finally
      Parser.Free;
    end;
  end;

  if Root = nil then Exit;
  try
    AddRefsFromNode(Root, PasFileName);
  finally
    if OwnsRoot then Root.Free;
  end;
end;

procedure TSymbolReferenceIndex.Build(FileList: TStringList; ACache: TAstFileCache);
// 2-Pass-Build:
//   Pass 1 sammelt alle Public-/Published-Member-Namen ueber alle Files
//          (FPublicMembers Set) - noetig fuer A.3+ Punkt 3 (bare-Call-
//          Filter).
//   Pass 2 ScanUnitForRefs befuellt FRefs. Bare nkCall werden nur dann
//          registriert wenn der Name als Public-Member bekannt ist.
// FileCache greift in Pass 2 -> kein doppelter Parse, nur doppelter Walk.
var
  i : Integer;
begin
  FAstCache := ACache;
  if FileList = nil then Exit;
  for i := 0 to FileList.Count - 1 do
    ScanUnitForMembers(FileList[i]);
  for i := 0 to FileList.Count - 1 do
    ScanUnitForRefs(FileList[i]);
end;

function TSymbolReferenceIndex.ExternalReferencingUnitCount(const MemberLow,
  OwnUnit: string): Integer;
var
  L : TStringList;
  OwnLow : string;
  i : Integer;
begin
  Result := 0;
  if not FRefs.TryGetValue(LowerCase(MemberLow), L) then Exit;
  // Selber Normalisierungs-Pfad wie AddReference - sonst zaehlt die
  // eigene Unit faelschlich als externe Referenz wenn Build mit absolutem
  // Pfad indizierte und der Caller einen relativen uebergibt.
  // Perf (2026-07-05): P9-symbolrefindex - 1-Slot-Memo: uVisibilityCheck
  // ruft pro Member derselben Datei mit identischem OwnUnit (Vollpfad,
  // siehe Doku dort); nur bei Wechsel neu normalisieren.
  // Perf Stufe 2 (2026-07-25): Memo unter TMonitor - der Index wird im
  // Parallel-Modus von mehreren Worker-Threads gleichzeitig abgefragt
  // (der uebrige Index-State ist nach Build read-only, nur dieses 1-Slot-
  // Memo mutiert im Query-Pfad). Seriell unkontent -> kostenneutral.
  TMonitor.Enter(Self);
  try
    if OwnUnit <> FOwnUnitRaw then
    begin
      FOwnUnitRaw  := OwnUnit;
      FOwnUnitNorm := NormalizeUnitPath(OwnUnit);
    end;
    OwnLow := FOwnUnitNorm;
  finally
    TMonitor.Exit(Self);
  end;
  for i := 0 to L.Count - 1 do
    if L[i] <> OwnLow then Inc(Result);
end;

function TSymbolReferenceIndex.HasExternalRefs(const MemberLow,
  OwnUnit: string): Boolean;
begin
  Result := ExternalReferencingUnitCount(MemberLow, OwnUnit) > 0;
end;

function TSymbolReferenceIndex.IsEmpty: Boolean;
begin
  Result := FRefs.Count = 0;
end;

initialization

finalization

end.
