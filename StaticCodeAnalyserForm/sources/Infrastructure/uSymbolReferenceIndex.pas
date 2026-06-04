unit uSymbolReferenceIndex;

// Repo-weiter Index ueber Cross-Unit-Referenzen auf Klassen-Member.
// HINWEIS: seit dem Visibility-Detektor-Refactor (single-file-only)
// liest `uVisibilityCheck` diesen Index NICHT mehr. Index bleibt fuer
// zukuenftige Konsumenten und kann durch Build() noch befuellt werden;
// uVisibilityCheck.AnalyzeUnit ignoriert ihn jedoch.
// Frueher: Visibility-Detektoren (fkCanBePrivate, fkCanBeProtected,
// fkUnusedPublicMember) konsultierten ihn, um Cross-Unit-Konsumenten
// zu sehen.
//
// Aufbau-Modell (analog uDfmRepoIndex):
//   * Aufrufer (TStaticAnalyzer2) ruft Build(FileList) einmal pro Scan.
//   * Build geht ueber alle .pas-Dateien, parst sie und sammelt:
//       - Welche Member-Namen tauchen in welchen Units als nkCall- oder
//         nkAssign-Referenzen auf?
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
  uAstNode;

type
  TSymbolReferenceIndex = class
  private
    // member-name-lowercase -> Set von Unit-Dateinamen, die ihn referenzieren
    FRefs : TDictionary<string, TStringList>;

    procedure ScanUnit(const PasFileName: string);
    procedure AddRefsFromNode(RootNode: TAstNode; const SourceUnit: string);
  public
    constructor Create;
    destructor  Destroy; override;

    // Repo-weiten Scan ueber alle Pas-Dateien durchfuehren.
    procedure Build(FileList: TStringList);

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

var
  // Global Index analog gDfmRepoIndex. Wird von TStaticAnalyzer2 in
  // AnalyzeLeaksRecursive aufgebaut und am Ende freigegeben.
  gSymbolRefIndex : TSymbolReferenceIndex = nil;

implementation

uses
  uParser2, uAstFileCache;

constructor TSymbolReferenceIndex.Create;
begin
  inherited;
  FRefs := TDictionary<string, TStringList>.Create;
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
  inherited;
end;

procedure TSymbolReferenceIndex.AddReference(const MemberName,
  FromUnit: string);
var
  Key, UnitLow : string;
  L : TStringList;
begin
  Key := LowerCase(Trim(MemberName));
  if Key = '' then Exit;
  UnitLow := LowerCase(FromUnit);
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
  Calls := RootNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      // Wir indexieren NUR Object.Member-Calls (mit Dot) - bare Calls auf
      // unqualifizierte Funktionen sind meist top-level oder same-class-
      // intern und wuerden zu viele False-Positives ergeben (jeder
      // 'Writeln' wuerde als Cross-Unit-Ref fuer einen hypothetischen
      // public Writeln-Member zaehlen).
      if not HasLhsBeforeDot(N.Name) then Continue;
      Target := ExtractRightOfDot(N.Name);
      AddReference(Target, SourceUnit);
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

procedure TSymbolReferenceIndex.ScanUnit(const PasFileName: string);
// Cache-Pfad: wenn gAstFileCache assigned, einmaliger Parse pro Repo-Lauf
// (perf_analyse.md Hot-Spot 🅐). Cache besitzt das Root - NICHT free.
var
  Parser  : TParser2;
  Root    : TAstNode;
  OwnsRoot: Boolean;
begin
  if not FileExists(PasFileName) then Exit;
  OwnsRoot := False;

  if Assigned(gAstFileCache) then
    Root := gAstFileCache.Acquire(PasFileName)
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

procedure TSymbolReferenceIndex.Build(FileList: TStringList);
var
  i : Integer;
begin
  if FileList = nil then Exit;
  for i := 0 to FileList.Count - 1 do
    ScanUnit(FileList[i]);
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
  OwnLow := LowerCase(OwnUnit);
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
  if Assigned(gSymbolRefIndex) then
    FreeAndNil(gSymbolRefIndex);

end.
