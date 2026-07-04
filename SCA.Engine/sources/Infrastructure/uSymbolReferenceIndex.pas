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

    procedure ScanUnitForMembers(const PasFileName: string);
    procedure ScanUnitForRefs(const PasFileName: string);
    procedure CollectPublicMembersFrom(RootNode: TAstNode);
    procedure AddRefsFromNode(RootNode: TAstNode; const SourceUnit: string);
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
begin
  if Path = '' then Exit('');
  Result := LowerCase(ExpandFileName(Path));
end;

procedure TSymbolReferenceIndex.AddReference(const MemberName,
  FromUnit: string);
var
  Key, UnitLow : string;
  L : TStringList;
begin
  Key := LowerCase(Trim(MemberName));
  if Key = '' then Exit;
  UnitLow := NormalizeUnitPath(FromUnit);
  if UnitLow = '' then Exit;
  if not FRefs.TryGetValue(Key, L) then
  begin
    L := TStringList.Create;
    L.CaseSensitive := False;
    L.Sorted        := True;
    L.Duplicates    := dupIgnore;
    FRefs.Add(Key, L);
  end;
  L.Add(UnitLow);
end;

procedure TSymbolReferenceIndex.AddRefsFromNode(RootNode: TAstNode;
  const SourceUnit: string);

  function ExtractRightOfDot(const S: string): string;
  // Bei 'Obj.Member(args)' -> 'Member'. Bei 'Bare(args)' -> 'Bare'.
  // Bei 'Obj.A.B' -> 'B' (tiefster Member-Access).
  var
    Trimmed : string;
    ParenPos, LastDot : Integer;
  begin
    Trimmed := Trim(S);
    ParenPos := Pos('(', Trimmed);
    if ParenPos > 0 then
      Trimmed := Copy(Trimmed, 1, ParenPos - 1);
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
  var
    i, L, StartSecond : Integer;
    MemberName : string;
  begin
    L := Length(Expr);
    i := 1;
    while i <= L do
    begin
      if not IsIdentCharLocal(Expr[i]) then
      begin
        Inc(i);
        Continue;
      end;
      // Erstes Ident (potentielles 'Obj')
      while (i <= L) and IsIdentCharLocal(Expr[i]) do Inc(i);
      if (i > L) or (Expr[i] <> '.') then Continue;
      Inc(i);  // skip '.'
      if (i > L) or not IsIdentCharLocal(Expr[i]) then Continue;
      // Zweites Ident (potentielles 'Member' = Property/Field/Method)
      StartSecond := i;
      while (i <= L) and IsIdentCharLocal(Expr[i]) do Inc(i);
      MemberName := Copy(Expr, StartSecond, i - StartSecond);
      AddReference(MemberName, SourceUnit);
    end;
  end;

var
  Calls, Assigns, Ifs, Whiles, Cases, Fors : TList<TAstNode>;
  N : TAstNode;
  Target : string;
begin
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
        AddReference(Target, SourceUnit);
      end
      else
      begin
        Target := ExtractRightOfDot(N.Name);  // strippt nur '(args)'
        if (Target <> '') and FPublicMembers.Contains(LowerCase(Target)) then
          AddReference(Target, SourceUnit);
      end;
    end;
  finally
    Calls.Free;
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
        AddReference(Target, SourceUnit);
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
// Default-Visibility ist 'published' (siehe uParser2 Zeile 740).
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
        // Nur 'public' und 'published' interessieren. 'private',
        // 'protected', 'strictprivate', 'strictprotected' sind per
        // Definition nicht extern aufrufbar -> kein bare-Call von
        // ausserhalb der eigenen Unit moeglich.
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
  OwnLow := NormalizeUnitPath(OwnUnit);
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
