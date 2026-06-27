unit uVisibilityCheck;

// Detektoren: fkCanBeUnitPrivate / fkCanBeStrictPrivate / fkCanBeProtected /
//             fkUnusedPublicMember.
//
// Pruefen, ob ein `public`-Member einer Klasse seine public-Sichtbarkeit
// ueberhaupt braucht. Klassische Code-Smells:
//   * `fkCanBeStrictPrivate`   - Member wird AUSSCHLIESSLICH von Methoden
//                                der eigenen Klasse referenziert -> echtes
//                                `strict private` reicht (D2007+).
//   * `fkCanBeUnitPrivate`     - Member wird innerhalb der aktuellen Unit
//                                referenziert (eigene Klasse ODER Sibling-
//                                Klassen/Top-Level-Code), aber nicht von
//                                Sub-Klassen -> Delphi-klassisches `private`
//                                (unit-scope) reicht.
//   * `fkCanBeProtected`       - Member wird in eigener Klasse + Sub-
//                                Klassen genutzt -> protected reicht.
//   * `fkUnusedPublicMember`   - Member wird in der aktuellen Unit
//                                nirgends gerufen. Single-file-Hint:
//                                kann False-Positive sein wenn eine
//                                fremde Unit konsumiert - der Compiler
//                                bricht den Refactor mit E2361 ab.
//
// Single-File-Modus (kein gSymbolRefIndex):
//   Alle vier Varianten arbeiten ausschliesslich auf dem AST der aktuellen
//   Datei. Begruendung: globaler Cross-Unit-Scan lieferte in der Praxis
//   zu viele False-Positives (RTTI-/DFM-Streaming, Plugin-APIs in
//   Sibling-`.dproj`/.dpk`, Generic-Instanziierungen, ...). Der Detektor
//   ist eine HINT-Empfehlung: User wendet sie an, Compiler verifiziert
//   per E2361 ob ein versteckter Cross-Unit-Caller existiert. Schneller
//   Feedback-Loop ohne Index-Overhead.
//
// Skip-Regeln:
//   * Severity = lsHint (kein Bug, nur Encapsulation-Empfehlung)
//   * `published`-Members werden komplett ausgeklammert (DFM-/RTTI-
//     Reflection braucht sie sichtbar)
//   * VCL-Form-/Frame-/DataModule-Klassen werden komplett uebersprungen
//     (DFM-Bindung haengt an public published-API)
//   * Methoden mit `virtual`/`abstract`/`override`/`dynamic`-Direktive
//     werden uebersprungen (Vererbungs-Hook fuer externe Subklassen)
//   * Konstruktoren/Destruktoren (Create/Destroy) bleiben per Konvention
//     public, auch wenn intern nicht direkt gerufen
//
// Erkennung:
//   1. Sammle public-Methoden + -Felder + -Properties pro Klasse.
//   2. Sammle alle Sub-Klassen in dieser Unit (anhand TypeRef).
//   3. Pro Member:
//      a. Cross-Unit: HasExternalRefs? -> sofort durchwinken (public bleibt).
//      b. Textsuche im AST nach Referenzen.
//         - Eigene Klasse:        Self.M / M(...) in <ClassName>.<MethName>
//         - Sub-Klassen:          analog in <SubClass>.<MethName>
//         - Andere (Unit-Code):   ansonsten
//   4. Klassifiziere wie oben beschrieben + emittiere Quick-Fix-Hint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TVisibilityCheckDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, NestedRoutine, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uSymbolReferenceIndex;

const
  EMIT_SEVERITY = lsHint;

  // Klassen-Familien, die wegen RTTI/DFM/Streaming public bleiben muessen
  RTTI_DRIVEN_BASES: array[0..3] of string = (
    'tform', 'tframe', 'tdatamodule', 'tcomponent'
  );

function IsRttiDriven(const Parents: string): Boolean;
var
  Lower : string;
  B : string;
begin
  Result := False;
  Lower := LowerCase(Parents);
  for B in RTTI_DRIVEN_BASES do
    if Pos(B, Lower) > 0 then Exit(True);
end;

function NormalizeIdent(const S: string): string;
begin
  Result := LowerCase(Trim(S));
end;

// Liefert die Methoden-Implementations als TList<TAstNode>, gefiltert auf
// solche, deren Name mit ClassPrefix beginnt (case-insensitiv).
procedure CollectMethodImplsFor(UnitNode: TAstNode;
  const ClassPrefix: string; Dest: TList<TAstNode>);
var
  All : TList<TAstNode>;
  M : TAstNode;
  PrefixLow : string;
begin
  PrefixLow := LowerCase(ClassPrefix) + '.';
  All := UnitNode.FindAll(nkMethod);
  try
    for M in All do
      if LowerCase(M.Name).StartsWith(PrefixLow) then
        Dest.Add(M);
  finally
    All.Free;
  end;
end;

// True, wenn Body irgendeine Referenz auf MemberLow enthaelt (nkCall,
// nkAssign-LHS-Anteil, nkAssign-RHS in TypeRef).
function BodyReferences(Body: TAstNode; const MemberLow: string): Boolean;
var
  Nodes : TList<TAstNode>;
  N : TAstNode;
  Text : string;

  function ContainsIdent(const Hay, Needle: string): Boolean;
  // Naive Wort-Grenzen-Suche (case-insensitiv, Body schon lowercase).
  var
    P, NL, HL : Integer;
    Before, After : Char;
  begin
    Result := False;
    NL := Length(Needle);
    HL := Length(Hay);
    if (NL = 0) or (HL < NL) then Exit;
    P := 1;
    while True do
    begin
      P := Pos(Needle, Hay, P);
      if P = 0 then Exit;
      Before := #0;
      if P > 1 then Before := Hay[P - 1];
      After := #0;
      if P + NL - 1 < HL then After := Hay[P + NL];
      if not CharInSet(Before, ['a'..'z','0'..'9','_']) and
         not CharInSet(After,  ['a'..'z','0'..'9','_']) then
        Exit(True);
      P := P + NL;
    end;
  end;

begin
  Result := False;
  if Body = nil then Exit;
  Nodes := Body.FindAll(nkCall);
  try
    for N in Nodes do
    begin
      Text := LowerCase(N.Name);
      if ContainsIdent(Text, MemberLow) then Exit(True);
    end;
  finally
    Nodes.Free;
  end;
  Nodes := Body.FindAll(nkAssign);
  try
    for N in Nodes do
    begin
      Text := LowerCase(N.Name);
      if ContainsIdent(Text, MemberLow) then Exit(True);
      Text := LowerCase(N.TypeRef);
      if ContainsIdent(Text, MemberLow) then Exit(True);
    end;
  finally
    Nodes.Free;
  end;
end;

class procedure TVisibilityCheckDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Classes : TList<TAstNode>;
  ClassNode, Vis, Member : TAstNode;
  PublicMembers : TList<TAstNode>;
  ClassNameByLow : TDictionary<string, TAstNode>;
  ChildrenOf : TDictionary<string, TList<string>>;
  OtherCls : TAstNode;
  ParentName, ChildName : string;
  Parents : TStringList;
  i : Integer;
  AllUnitMethods : TList<TAstNode>;
  RefIdx : TSymbolReferenceIndex;
  DescendantsCache : TObjectDictionary<string, TList<string>>;

  function DescendantsOfCached(const ClassLow: string): TList<string>;
  // Memoized BFS ueber den Vererbungs-Graphen. Cache lebt fuer die Dauer
  // von AnalyzeUnit - bei N public-Members und M Other-Methods wuerde
  // DescendantsOf sonst O(N x M)-mal mit jeweils neuer TQueue+TDictionary
  // alloziert.
  var
    Q : TQueue<string>;
    Visited : TDictionary<string, Boolean>;
    Cur, Sub : string;
    Subs : TList<string>;
  begin
    if DescendantsCache.TryGetValue(ClassLow, Result) then Exit;

    Result := TList<string>.Create;
    Q := TQueue<string>.Create;
    Visited := TDictionary<string, Boolean>.Create;
    try
      Q.Enqueue(ClassLow);
      Visited.AddOrSetValue(ClassLow, True);
      while Q.Count > 0 do
      begin
        Cur := Q.Dequeue;
        if not ChildrenOf.TryGetValue(Cur, Subs) then Continue;
        for Sub in Subs do
          if not Visited.ContainsKey(Sub) then
          begin
            Visited.AddOrSetValue(Sub, True);
            Result.Add(Sub);
            Q.Enqueue(Sub);
          end;
      end;
    finally
      Visited.Free;
      Q.Free;
    end;
    DescendantsCache.Add(ClassLow, Result);
  end;

  // True wenn die Klasse das klassische Utility-/Namespace-Container-
  // Pattern hat: keine Instanz-Felder, keine Properties, kein Konstruktor,
  // UND alle Methoden sind class-Methoden (`class function`/`class
  // procedure`, vom Parser im TypeRef mit ';class' markiert). Solche
  // Klassen leben davon, dass ihre Methoden von AUSSEN gerufen werden -
  // CanBePrivate ist da semantisch falsch (Beispiel: TDetectorUtils mit
  // lauter `class function`s).
  //
  // Wichtig: eine Klasse mit Instanz-Methoden (`procedure Foo;` ohne
  // `class`-Praefix) ist KEIN Utility-Container, auch wenn keine Felder
  // da sind - sie wartet nur darauf, dass jemand instanziiert. Deshalb
  // explizit ueber den class-Marker entscheiden statt nur "keine Felder".
  function IsUtilityClass(const ClassN: TAstNode): Boolean;
  var
    V, M : TAstNode;
    i, j : Integer;
    HasAnyMethod : Boolean;
  begin
    Result := False;
    HasAnyMethod := False;
    for i := 0 to ClassN.Children.Count - 1 do
    begin
      V := ClassN.Children[i];
      if V.Kind <> nkVisibilitySection then Continue;
      for j := 0 to V.Children.Count - 1 do
      begin
        M := V.Children[j];
        if M.Kind = nkField then Exit;
        if M.Kind = nkProperty then Exit;
        if M.Kind = nkMethod then
        begin
          if NormalizeIdent(M.Name) = 'create' then Exit;
          if Pos(';class', LowerCase(M.TypeRef)) = 0 then Exit;
          HasAnyMethod := True;
        end;
      end;
    end;
    // Leere Klassen (Marker-Interfaces, abstrakte Stubs ohne Methoden)
    // sind keine Utility-Container.
    Result := HasAnyMethod;
  end;

  function IsInheritanceHook(const M: TAstNode): Boolean;
  // Virtual/abstract/override/dynamic-Methoden duerfen nicht private werden -
  // selbst wenn unsere Unit den Member nirgends ruft, kann eine externe
  // Subklasse das Override nutzen. Parser haengt die Direktiven seit dem
  // 🅳-Refactor an TypeRef an (Format: 'kind[:ret];dir1;dir2').
  var
    Lower : string;
  begin
    Result := False;
    if M.Kind <> nkMethod then Exit;
    Lower := LowerCase(M.TypeRef);
    Result := (Pos(';virtual',  Lower) > 0)
           or (Pos(';override', Lower) > 0)
           or (Pos(';abstract', Lower) > 0)
           or (Pos(';dynamic',  Lower) > 0);
  end;

  procedure ClassifyMember(const ClassNode: TAstNode; const Member: TAstNode);
  var
    MemberLow, ClassLow : string;
    OwnRefs, SubRefs, OtherRefs : Integer;
    ImplList : TList<TAstNode>;
    Impl : TAstNode;
    Descendants : TList<string>;
    SubLow : string;
    K : TFindingKind;
    F : TLeakFinding;
    Msg : string;
  begin
    MemberLow := NormalizeIdent(Member.Name);
    ClassLow  := NormalizeIdent(ClassNode.Name);
    if (MemberLow = '') or (ClassLow = '') then Exit;
    if MemberLow = 'create' then Exit;       // Konstruktor ist Default-public
    if MemberLow = 'destroy' then Exit;      // Destruktor analog
    if IsInheritanceHook(Member) then Exit;  // virtual/override/abstract/dynamic

    // Single-file-Modus: keine Konsultation eines globalen Symbol-Index.
    // Cross-Unit-Callers sind unsichtbar - der Detektor liefert einen Hint,
    // der Compiler verifiziert die Annahme bei der Anwendung (E2361 falls
    // ein fremder Konsument existiert).

    OwnRefs   := 0;
    SubRefs   := 0;
    OtherRefs := 0;

    // 1. Referenzen in Methods der eigenen Klasse
    ImplList := TList<TAstNode>.Create;
    try
      CollectMethodImplsFor(UnitNode, ClassNode.Name, ImplList);
      for Impl in ImplList do
      begin
        if Impl = Member then Continue;      // Eigene Methode zaehlt nicht
        if BodyReferences(Impl, MemberLow) then Inc(OwnRefs);
      end;
    finally
      ImplList.Free;
    end;

    // 2. Referenzen in Sub-Klassen-Methods. Descendants kommt aus dem
    //    Memoizer (kein .Free - Cache besitzt die Liste).
    Descendants := DescendantsOfCached(ClassLow);
    for SubLow in Descendants do
    begin
      if not ClassNameByLow.TryGetValue(SubLow, OtherCls) then Continue;
      ImplList := TList<TAstNode>.Create;
      try
        CollectMethodImplsFor(UnitNode, OtherCls.Name, ImplList);
        for Impl in ImplList do
          if BodyReferences(Impl, MemberLow) then Inc(SubRefs);
      finally
        ImplList.Free;
      end;
    end;

    // 3. Sonstige Unit-Referenzen (in Methoden, die nicht zur Klasse oder
    //    einer Sub-Klasse gehoeren). AllUnitMethods + Descendants kommen
    //    aus den AnalyzeUnit-Caches - kein FindAll/BFS pro Member.
    for Impl in AllUnitMethods do
    begin
      if Impl = Member then Continue;
      var Lower := NormalizeIdent(Impl.Name);
      // Skippen wenn zur eigenen Klasse oder einem Descendant
      if Lower.StartsWith(ClassLow + '.') then Continue;
      var Skip := False;
      for SubLow in Descendants do
        if Lower.StartsWith(SubLow + '.') then
        begin
          Skip := True;
          Break;
        end;
      if Skip then Continue;
      if BodyReferences(Impl, MemberLow) then Inc(OtherRefs);
    end;

    // Klassifikation. Alle Empfehlungen sind single-file-stark - bei
    // Cross-Unit-Konsumenten meckert der Compiler beim Refactor.
    const SingleFileSuffix =
      ' (single-file scan - verify no cross-unit caller before refactoring)';

    if (OwnRefs = 0) and (SubRefs = 0) and (OtherRefs = 0) then
    begin
      // Phase-4 A.3 minimal: nur fuer fkUnusedPublicMember den Cross-Unit-
      // Index konsultieren. Wenn der Index vorhanden + nicht-leer ist und
      // eine externe Unit den Member referenziert -> kein "dead public API"-
      // Finding (typischer FP: API-Surface eines Plugins / Helper-Klasse).
      // Single-File-Modus (Index leer): Fallback auf alte Heuristik mit
      // SingleFileSuffix-Caveat. Die anderen 3 Kinds (CanBe*) bleiben
      // unangetastet bis Audit ihrer FP-Cluster.
      //
      // FileName MUSS der volle Pfad sein - der Index speichert intern
      // LowerCase(FromUnit) mit Vollpfad (siehe uSymbolReferenceIndex.
      // AddReference). Wer hier nur den Basename uebergibt, vergleicht
      // "name.pas" gegen "d:\...\name.pas" und der Self-Match schlaegt nie
      // an -> Self-Refs wuerden als extern gewertet -> A.3 wird permissiver
      // als beabsichtigt.
      RefIdx := CtxSymbolRefIndex(AContext);
      if Assigned(RefIdx) and not RefIdx.IsEmpty
         and RefIdx.HasExternalRefs(MemberLow, FileName) then
        Exit;
      // Niemand in dieser Datei ruft den Member. Echt tot ODER fremde Unit
      // konsumiert ihn (typischer single-file-FP: API-Surface eines Plugins).
      K := fkUnusedPublicMember;
      Msg := Format('Dead public API: %s.%s is not called anywhere in this unit. '
        + 'Quick-Fix: delete the declaration + implementation, run build.%s',
        [ClassNode.Name, Member.Name, SingleFileSuffix]);
    end
    else if SubRefs > 0 then
    begin
      // Sub-Klassen-Methode ruft den Member -> protected reicht.
      K := fkCanBeProtected;
      Msg := Format('Tighten encapsulation: %s.%s is used by '
        + 'subclasses only - move from `public` to `protected`. '
        + 'Quick-Fix: move declaration into a `protected` section of %s.%s',
        [ClassNode.Name, Member.Name, ClassNode.Name, SingleFileSuffix]);
    end
    else if OtherRefs > 0 then
    begin
      // Sibling-Klasse oder Top-Level-Code in derselben Unit ruft den
      // Member. `strict private` waere zu eng (verbietet diese Zugriffe),
      // aber Delphi-`private` ist unit-scope und reicht.
      K := fkCanBeUnitPrivate;
      Msg := Format('Tighten encapsulation: %s.%s is referenced only from '
        + 'within the current unit - move from `public` to `private` '
        + '(Delphi-classic, unit-scope). '
        + 'Quick-Fix: move declaration into a `private` section of %s.%s',
        [ClassNode.Name, Member.Name, ClassNode.Name, SingleFileSuffix]);
    end
    else
    begin
      // Ausschliesslich Methoden der eigenen Klasse rufen den Member.
      // `strict private` ist die strengste sichere Empfehlung.
      K := fkCanBeStrictPrivate;
      Msg := Format('Tighten encapsulation: %s.%s is used only by methods of '
        + '%s itself - move from `public` to `strict private` (class-scope, '
        + 'D2007+). Quick-Fix: move declaration into a `strict private` '
        + 'section of %s.%s',
        [ClassNode.Name, Member.Name, ClassNode.Name, ClassNode.Name,
         SingleFileSuffix]);
    end;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Member.Name;
    F.LineNumber := IntToStr(Member.Line);
    F.MissingVar := Msg;
    F.SetKind(K);
    Results.Add(F);
  end;

begin
  Classes := UnitNode.FindAll(nkClass);
  PublicMembers := TList<TAstNode>.Create;
  ClassNameByLow := TDictionary<string, TAstNode>.Create;
  ChildrenOf := TDictionary<string, TList<string>>.Create;
  // Perf: einmal pro Unit holen statt pro public-Member (heute ~10-50
  // Member/Klasse × ~20 Klassen → bis zu 1000× TList-Alloc + Tree-Walk
  // pro Datei).
  AllUnitMethods := UnitNode.FindAll(nkMethod);
  // Perf: DescendantsOf pro ClassLow memoizen - im A.3-Pfad wurde es
  // pro Member UND pro Other-Method gerufen (= O(members × methods)
  // mit jeweils TQueue+TDictionary-Allokation).
  DescendantsCache := TObjectDictionary<string, TList<string>>.Create(
    [doOwnsValues]);
  try
    // Phase 1: Klassen-Index + Vererbungs-Graph
    for ClassNode in Classes do
    begin
      if ClassNode.Name = '' then Continue;
      ClassNameByLow.AddOrSetValue(NormalizeIdent(ClassNode.Name), ClassNode);
    end;
    for ClassNode in Classes do
    begin
      if ClassNode.TypeRef = '' then Continue;
      Parents := TStringList.Create;
      try
        Parents.Delimiter := ' ';
        Parents.StrictDelimiter := True;
        Parents.DelimitedText := ClassNode.TypeRef;
        for i := 0 to Parents.Count - 1 do
        begin
          ParentName := NormalizeIdent(Parents[i]);
          if ParentName = '' then Continue;
          if not ChildrenOf.ContainsKey(ParentName) then
            ChildrenOf.Add(ParentName, TList<string>.Create);
          ChildName := NormalizeIdent(ClassNode.Name);
          ChildrenOf[ParentName].Add(ChildName);
        end;
      finally
        Parents.Free;
      end;
    end;

    // Phase 2: Public-Member sammeln
    for ClassNode in Classes do
    begin
      if ClassNode.Name = '' then Continue;
      if IsRttiDriven(ClassNode.TypeRef) then Continue;
      // Utility-/Namespace-Klassen ueberspringen: keine Instanz-Felder,
      // keine Properties, kein Konstruktor -> sie leben davon, dass ihre
      // (class) Methoden von AUSSEN gerufen werden. CanBePrivate waere
      // hier semantisch falsch (typisches Beispiel: TDetectorUtils mit
      // lauter `class function`s).
      if IsUtilityClass(ClassNode) then Continue;

      for i := 0 to ClassNode.Children.Count - 1 do
      begin
        Vis := ClassNode.Children[i];
        if Vis.Kind <> nkVisibilitySection then Continue;
        if NormalizeIdent(Vis.Name) <> 'public' then Continue;
        for var j := 0 to Vis.Children.Count - 1 do
        begin
          Member := Vis.Children[j];
          // FELDER ueberspringen: fuer public/published Fields ist
          // uPublicField (SCA089) der kanonische Detektor mit dem
          // staerkeren Vorschlag ("Property statt Feld"). Vorher haben
          // beide Detektoren auf der gleichen Zeile gefeuert; jetzt
          // bleibt VisibilityCheck auf Methoden + Properties.
          if Member.Kind = nkField then Continue;
          if Member.Kind in [nkMethod, nkProperty] then
            ClassifyMember(ClassNode, Member);
        end;
      end;
    end;
  finally
    for var ChildList in ChildrenOf.Values do
      ChildList.Free;
    ChildrenOf.Free;
    ClassNameByLow.Free;
    PublicMembers.Free;
    Classes.Free;
    AllUnitMethods.Free;
    DescendantsCache.Free;     // doOwnsValues -> innere TList<string> mit weg
  end;
end;

end.
