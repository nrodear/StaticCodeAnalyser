unit uVisibilityCheck;

// Detektoren: fkCanBePrivate / fkCanBeProtected / fkUnusedPublicMember.
//
// Pruefen, ob ein `public`-Member einer Klasse seine public-Sichtbarkeit
// ueberhaupt braucht. Klassische Code-Smells:
//   * `fkCanBePrivate`         - Member wird nur innerhalb der eigenen
//                                Klasse benutzt -> sollte private sein
//   * `fkCanBeProtected`       - Member wird in eigener Klasse + Sub-
//                                Klassen genutzt -> protected reicht
//   * `fkUnusedPublicMember`   - Member wird nirgendwo gerufen
//
// Cross-Unit-Modus:
//   Wenn `gSymbolRefIndex` (Build-Time aufgebaut von TStaticAnalyzer2 bei
//   AnalyzeLeaksRecursive) verfuegbar ist, konsultiert der Detektor ihn:
//   sobald irgendeine ANDERE Unit den Member referenziert, wird kein
//   Befund mehr emittiert (Encapsulation-Argument hinfaellig).
//   Single-File-Pfad (z.B. CLI-AnalyzeLeaks(File) oder Tests): Index
//   bleibt nil, der Detektor laeuft nur auf der einzelnen Unit - der
//   Hint-Text weist dann auf den fehlenden Cross-Unit-Check hin.
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
  uAstNode, uSCAConsts, uMethodd12,
  uSymbolReferenceIndex;

type
  TVisibilityCheckDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

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
  const FileName: string; Results: TObjectList<TLeakFinding>);
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

  function DescendantsOf(const ClassLow: string): TList<string>;
  var
    Q : TQueue<string>;
    Visited : TDictionary<string, Boolean>;
    Cur, Sub : string;
    Subs : TList<string>;
  begin
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
    AllMethods : TList<TAstNode>;
    K : TFindingKind;
    F : TLeakFinding;
    Msg : string;
    HasCrossUnitRefs : Boolean;
  begin
    MemberLow := NormalizeIdent(Member.Name);
    ClassLow  := NormalizeIdent(ClassNode.Name);
    if (MemberLow = '') or (ClassLow = '') then Exit;
    if MemberLow = 'create' then Exit;       // Konstruktor ist Default-public
    if MemberLow = 'destroy' then Exit;      // Destruktor analog
    if IsInheritanceHook(Member) then Exit;  // virtual/override/abstract/dynamic

    // Cross-Unit-Check: wenn der Index aufgebaut ist und eine fremde Unit
    // den Member referenziert, ist `public` legitim - kein Befund.
    HasCrossUnitRefs := False;
    if Assigned(gSymbolRefIndex) and (not gSymbolRefIndex.IsEmpty) then
      HasCrossUnitRefs := gSymbolRefIndex.HasExternalRefs(MemberLow, FileName);
    if HasCrossUnitRefs then Exit;

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

    // 2. Referenzen in Sub-Klassen-Methods
    Descendants := DescendantsOf(ClassLow);
    try
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
    finally
      Descendants.Free;
    end;

    // 3. Sonstige Unit-Referenzen (in Methoden, die nicht zur Klasse oder
    //    einer Sub-Klasse gehoeren).
    AllMethods := UnitNode.FindAll(nkMethod);
    try
      for Impl in AllMethods do
      begin
        if Impl = Member then Continue;
        var Lower := NormalizeIdent(Impl.Name);
        // Skippen wenn zur eigenen Klasse oder einem Descendant
        if Lower.StartsWith(ClassLow + '.') then Continue;
        var Skip := False;
        Descendants := DescendantsOf(ClassLow);
        try
          for SubLow in Descendants do
            if Lower.StartsWith(SubLow + '.') then begin Skip := True; Break; end;
        finally
          Descendants.Free;
        end;
        if Skip then Continue;
        if BodyReferences(Impl, MemberLow) then Inc(OtherRefs);
      end;
    finally
      AllMethods.Free;
    end;

    // Klassifikation. Sobald OtherRefs > 0 ist, ist `public` korrekt.
    if OtherRefs > 0 then Exit;

    // Cross-Unit-Modus-Indikator fuer den Hint-Text: wenn der Index nicht
    // gebaut war, sind alle Aussagen nur Single-File-stark und wir markieren
    // das im Text.
    var Suffix := '';
    if (gSymbolRefIndex = nil) or gSymbolRefIndex.IsEmpty then
      Suffix := ' (single-file scan - verify no cross-unit caller before refactoring)';

    if (OwnRefs = 0) and (SubRefs = 0) then
    begin
      K := fkUnusedPublicMember;
      Msg := Format('Dead public API: %s.%s is not called anywhere. '
        + 'Quick-Fix: delete the declaration + implementation, run build.%s',
        [ClassNode.Name, Member.Name, Suffix]);
    end
    else if SubRefs > 0 then
    begin
      K := fkCanBeProtected;
      Msg := Format('Tighten encapsulation: %s.%s is used by '
        + 'subclasses only - move from `public` to `protected`. '
        + 'Quick-Fix: move declaration into a `protected` section of %s.%s',
        [ClassNode.Name, Member.Name, ClassNode.Name, Suffix]);
    end
    else
    begin
      K := fkCanBePrivate;
      Msg := Format('Tighten encapsulation: %s.%s is used only inside %s - '
        + 'move from `public` to `private`. '
        + 'Quick-Fix: move declaration into a `private` section of %s.%s',
        [ClassNode.Name, Member.Name, ClassNode.Name, ClassNode.Name, Suffix]);
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

      for i := 0 to ClassNode.Children.Count - 1 do
      begin
        Vis := ClassNode.Children[i];
        if Vis.Kind <> nkVisibilitySection then Continue;
        if NormalizeIdent(Vis.Name) <> 'public' then Continue;
        for var j := 0 to Vis.Children.Count - 1 do
        begin
          Member := Vis.Children[j];
          if Member.Kind in [nkMethod, nkField, nkProperty] then
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
  end;
end;

end.
