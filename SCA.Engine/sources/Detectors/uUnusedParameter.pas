unit uUnusedParameter;

// Detector: Method-Parameter, der im Body nirgendwo referenziert wird.
//
// Skip-Regeln (sonst zu viel Rauschen):
//   * Methode ist `override`/`virtual`/`abstract` -> Signature-Konformitaet
//     wichtig, Param-Existenz kann von Basisklasse vorgegeben sein.
//   * Methode hat genau einen `Sender: TObject`-Param (Event-Handler-Pattern).
//   * Body enthaelt bare `inherited;` oder klammerloses `inherited Foo;` ->
//     Delphi reicht die aktuellen Parameter implizit an die Elternmethode weiter
//     (Signatur vom Parent vorgegeben, Param nicht wirklich ungenutzt).
//   * Param-Name beginnt mit `_` (intentional convention).
//   * Body ist asm-Block oder leer.
//
// Erkennung:
//   * MethodNode.FindAll(nkParam) → Liste der Param-Knoten
//   * Body-Tokens einsammeln (rekursiv Name+TypeRef aller Children)
//   * Pro Param: zaehle case-insensitive Wortgrenzen-Vorkommen im Body
//   * Wenn 0 -> Finding
//
// Severity: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils, uFileTextCache;

type
  TUnusedParameterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(UnitNode, MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, NestedRoutine, NestedTry, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsHint;

function IsIdentChar(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Modifier-Check via TypeRef-Format aus Parser (siehe 🅳-Fix):
//   'kind[:ret];dir1;dir2'
function HasModifier(MethodNode: TAstNode; const Dir: string): Boolean;
begin
  Result := Pos(';' + LowerCase(Dir), LowerCase(MethodNode.TypeRef)) > 0;
end;

// Methodennamen `TFoo.Bar` -> Klasse `TFoo`, MethodenName `Bar`.
//
// Bis 2026-07-27 wurde am ERSTEN Punkt getrennt. Bei nested types
// ('TOuter.TInner.PaintBackground') ergab das Klasse='TOuter' und Name=
// 'TInner.PaintBackground'; FindDeclaration suchte danach in der AEUSSEREN
// Klasse nach einer woertlich so heissenden Methode und fand nie etwas. Der
// override/virtual-Skip in IsInheritanceHook lief damit ins Leere - still,
// ohne Fehler. Sauberer A/B-Beleg im selben File (Vcl.Styles.Utils.ComCtrls):
// die Methode mit zwei Qualifizierern wurde gemeldet, die daneben liegende
// mit einem und identisch leerem Rumpf nicht.
function SplitQualified(const MethodName: string;
  out ClassName, BareName: string): Boolean;
begin
  ClassName := TDetectorUtils.OwnerTypeName(MethodName);
  BareName  := TDetectorUtils.UnqualifiedNameLast(MethodName);
  Result    := ClassName <> '';
end;

// Sucht im Unit-Tree die Class-Declaration, die zu einer Implementation
// gehoert. Liefert deren nkMethod-Knoten (die HAT die Modifier in TypeRef)
// oder nil.
function FindDeclaration(UnitNode: TAstNode; const ClassName,
  BareName: string): TAstNode;
var
  Classes : TList<TAstNode>;
  Cls : TAstNode;
  Methods : TList<TAstNode>;
  M : TAstNode;
  LowClassWanted, LowBareWanted : string;
begin
  Result := nil;
  if (UnitNode = nil) or (ClassName = '') then Exit;
  LowClassWanted := LowerCase(ClassName);
  LowBareWanted  := LowerCase(BareName);
  Classes := UnitNode.FindAll(nkClass);
  try
    for Cls in Classes do
    begin
      if LowerCase(Cls.Name) <> LowClassWanted then Continue;
      Methods := Cls.FindAll(nkMethod);
      try
        for M in Methods do
          if LowerCase(M.Name) = LowBareWanted then
            Exit(M);
      finally
        Methods.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

// T2 (2026-07-29): Besitzertyp einer nested-type-Methode im Unit-Baum
// finden (nkClass ODER nkRecord - nested records mit Methoden existieren).
// Liefert False, wenn KEIN Typknoten mit dem Besitzernamen existiert -
// oder MEHRERE (Review 2026-07-29): nested types existieren gerade,
// damit Namen wiederverwendbar sind; ein Top-Level-Homonym wuerde den
// echten Besitzer shadowen und den Interface-Skip fehlleiten (FP auf
// compiler-erzwungenen Delegate-Parametern). Ambiguitaet -> defensiv
// False, der Aufrufer schweigt dann wie beim Nicht-Finden.
function TryFindOwnerType(UnitNode: TAstNode; const MethName: string;
  out OwnerCls: TAstNode): Boolean;
var
  OwnerLow : string;
  Kind     : TNodeKind;
  L        : TList<TAstNode>;
  C        : TAstNode;
begin
  Result   := False;
  OwnerCls := nil;
  OwnerLow := TDetectorUtils.OwnerTypeNameLower(MethName);
  if OwnerLow = '' then Exit;
  for Kind in [nkClass, nkRecord] do
  begin
    L := UnitNode.FindAllRef(Kind);
    for C in L do
      if LowerCase(C.Name) = OwnerLow then
      begin
        if OwnerCls <> nil then
        begin
          OwnerCls := nil;          // Homonym - nicht entscheidbar
          Exit(False);
        end;
        OwnerCls := C;
      end;
  end;
  Result := OwnerCls <> nil;
end;

// True wenn die class(...)-Liste des Knotens Interfaces traegt.
// ParseClassBody legt die Eltern space-getrennt in TypeRef ab (gepunktete
// Namen bleiben EIN Eintrag; Generic-Argumente werden seit T2b
// balanciert uebersprungen - 'class(TObjectList<TItem>)' ist wieder EIN
// Eintrag 'TObjectList', die fruehere Generics-FN-Restklasse aus
// Review 2026-07-29 ist damit geschlossen). VERBLIEBENE UNSCHAERFE
// (bewusste FN-Restklasse): IFDEF-Twins emittieren beide Zweige
// ('TX TY') und werden hier faelschlich als Basis+Interface gelesen
// -> Skip (kein Fund). Nur-FN-Richtung, nie FP; Twin-Adoption ist ein
// T3-Backlog-Posten (Twin-Kopf mergen statt skippen). Gleiches gilt fuer
// die I-Gross-Konvention beim Ein-Eintrag-Fall (IPCServer/IOThread
// waeren falsch-positiv fuer den SKIP, also ebenfalls nur-FN). Zusaetzlich der
// Ein-Eintrag-Fall 'class(IFoo)' (implizite TObject-Basis): dort
// entscheidet die I-Grossbuchstabe-Konvention - 'IdFtp...' (Indy) faellt
// durch das Kleinbuchstaben-d nicht darauf herein.
function OwnerHasInterfaceParents(OwnerCls: TAstNode): Boolean;
var
  P : string;
begin
  Result := False;
  if OwnerCls = nil then Exit;
  P := Trim(OwnerCls.TypeRef);
  if P = '' then Exit;
  if Pos(' ', P) > 0 then Exit(True);      // Basis + mind. ein Interface
  // Einziger Eintrag: Interface nach Namenskonvention I<Gross>?
  // Unit-Qualifizierer abstreifen (System.IInterface -> IInterface).
  P := TDetectorUtils.UnqualifiedNameLast(P);
  Result := (Length(P) >= 2) and (P[1] = 'I') and
            CharInSet(P[2], ['A'..'Z']);
end;

// Inheritance-Hook-Check: an der Implementation selbst (selten) ODER an
// ihrer zugehoerigen Class-Declaration (Default-Fall - Parser legt die
// Modifier nur an der Declaration ab).
function IsInheritanceHook(UnitNode, MethodNode: TAstNode): Boolean;

  function CheckOne(N: TAstNode): Boolean;
  begin
    // Hinweis: 'message' ist KEINE vom Parser erkannte Method-Direktive
    // (IsMethodDirective/IsMethodDirectiveIdent kennen sie nicht; 'message N'
    // mit Konstanten-Arg landet nicht als ';message' im TypeRef). Message-
    // Handler-Erkennung braucht daher einen Parser-Followup, nicht HasModifier.
    Result := (N <> nil) and
              (HasModifier(N, 'override')
            or HasModifier(N, 'virtual')
            or HasModifier(N, 'abstract')
            or HasModifier(N, 'dynamic'));
  end;

var
  ClassName, BareName : string;
  Decl : TAstNode;
begin
  Result := CheckOne(MethodNode);
  if Result then Exit;

  if SplitQualified(MethodNode.Name, ClassName, BareName) then
  begin
    Decl := FindDeclaration(UnitNode, ClassName, BareName);
    Result := CheckOne(Decl);
  end;
end;

// Event-Handler-Konvention: der ERSTE Parameter ist 'Sender' (bzw. *Sender)
// oder vom Typ TObject. Solche Methoden bindet der Form-Designer per DFM an
// Component-Events; ihre Signatur ist durch den Event-Typ vorgegeben, daher
// sind ungenutzte Parameter unvermeidbar (kein Finding).
//
// Erfasst BEWUSST auch Multi-Param-Handler (OnKeyPress(Sender; var Key),
// OnDrawCell(Sender; ACol, ARow, Rect, State), OnFilter(Sender; Item; Accept)).
// Frueher nur Single-`Sender` -> FP bei jedem Mehr-Param-Handler mit einem
// ungenutzten Pflicht-Param (Real-World 2026-06-28: dominante SCA054-FP-Klasse).
function IsLikelyEventHandler(MethodNode: TAstNode): Boolean;
var
  Params : TList<TAstNode>;
  LowName, LowType : string;
begin
  Result := False;
  Params := MethodNode.FindAll(nkParam);
  try
    if Params.Count = 0 then Exit;
    LowName := LowerCase(Trim(Params[0].Name));   // Modifier-Prefix stoert EndsWith nicht
    LowType := LowerCase(Params[0].TypeRef);
    Result := (LowName = 'sender') or LowName.EndsWith('sender')
              or (Pos('tobject', LowType) > 0);
  finally
    Params.Free;
  end;
end;

// True, wenn der Body ein parameter-implizit-weiterreichendes 'inherited'
// enthaelt. Delphi reicht die AKTUELLEN Methodenparameter automatisch an die
// Elternmethode weiter bei
//   * bare  'inherited;'      -> Parser: nkInherited mit LEEREM Name
//   * klammerlos 'inherited Foo;' -> nkInherited.Name = 'Foo' (kein '(')
// In beiden Formen ist ein "ungenutzter" Parameter in Wahrheit weitergeleitet
// (Signatur vom Parent vorgegeben) -> KEIN echter unused-Param. Nur
// 'inherited Foo(args)' (Name enthaelt '(') reicht NICHT implizit weiter, dort
// kann ein Param genuin ungenutzt sein -> nicht skippen.
// Wichtig: der Parser konsumiert das Keyword 'inherited' und speichert nur den
// Call-Ausdruck als Name; ein Text-Scan nach "inherited" wuerde daher genau den
// dominanten bare-Fall (leerer Name) verfehlen -> Erkennung MUSS ueber den
// nkInherited-Knotentyp laufen. (Core-Audit 2026-07-18, Welle 1 5%-FP-Konzept:
// ~7.950 FP, groesste absolute FP-Klasse, monoton + TP-safe.)
function ForwardsParamsViaInherited(MethodNode: TAstNode): Boolean;
var
  Inh : TList<TAstNode>;
  N : TAstNode;
begin
  Result := False;
  Inh := MethodNode.FindAll(nkInherited);
  try
    for N in Inh do
      if Pos('(', N.Name) = 0 then   // '' (bare) oder 'Name' ohne Klammern
        Exit(True);
  finally
    Inh.Free;
  end;
end;

procedure CollectAllTokens(Root: TAstNode; SB: TStringBuilder);
var
  Stack : TStack<TAstNode>;
  Cur : TAstNode;
  i : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeMethod(UnitNode, MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Params : TList<TAstNode>;
  P : TAstNode;
  Name, LowName : string;
  BodySB : TStringBuilder;
  BodyLow : string;
  RefCount : Integer;
  F : TLeakFinding;
  OwnerCls : TAstNode;   // T2: Besitzertyp fuer den Interface-Skip
  // Ist-Messung 2026-07-18 (SCA054-FP-Klasse 'nested-routine-Nutzung', 3/5 der
  // Sample-FPs): der Parser verwirft nested-routine-Bodies aus dem Method-AST
  // (nur nkNestedRange-Marker bleiben, Line=Start/TypeRef=EndLine) -> ein Param,
  // der NUR in einer nested proc gelesen wird, war unsichtbar. Lazy-Fallback:
  // die Quell-Zeilen der Marker-Ranges (kommentar-/string-gestrippt - Kommentare
  // zaehlen NIE als Use) wort-gebunden nach dem Param-Namen scannen. Monoton
  // (nur zusaetzlicher Skip). Rest-Risiko Shadowing (gleichnamige nested-lokale
  // Var) unterdrueckt einen echten Fund - akzeptiert fuer lsHint, konsistent
  // mit der Text-Zaehlung des Detektors.
  NestedMarks   : TList<TAstNode>;
  StrippedLines : TArray<string>;
  StrippedReady : Boolean;
  SrcLines      : TStringList;
  SrcOwned      : Boolean;

  procedure EnsureStripped;
  var
    Code    : string;
    LineFor : TArray<Integer>;
  begin
    if StrippedReady then Exit;
    StrippedReady := True;
    SrcLines := AcquireLines(FileName, SrcOwned, nil);
    if SrcLines = nil then Exit;
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      SrcLines, LineFor, nil, FileName, ' ');
    StrippedLines := Code.Split([#10]);
  end;

  function UsedInNestedRanges(const NameLow: string): Boolean;
  var
    M : TAstNode;
    li, EndL, q, NL : Integer;
    L : string;
  begin
    Result := False;
    if NestedMarks.Count = 0 then Exit;
    EnsureStripped;
    if Length(StrippedLines) = 0 then Exit;
    NL := Length(NameLow);
    for M in NestedMarks do
    begin
      EndL := StrToIntDef(M.TypeRef, M.Line);
      for li := M.Line to EndL do
      begin
        if (li < 1) or (li > Length(StrippedLines)) then Continue;
        L := LowerCase(StrippedLines[li - 1]);
        q := Pos(NameLow, L);
        while q > 0 do
        begin
          if ((q = 1) or not IsIdentChar(L[q - 1])) and
             ((q + NL > Length(L)) or not IsIdentChar(L[q + NL])) then
            Exit(True);
          q := Pos(NameLow, L, q + 1);
        end;
      end;
    end;
  end;

begin
  // Declarations (in nkClass) skippen - die haben keinen Body und keine
  // sinnvolle Reference-Count. Ihre Modifier konsultieren wir aber von
  // der zugehoerigen Implementation aus (siehe IsInheritanceHook).
  if not MethodNode.HasChild(nkBlock) then Exit;

  if IsInheritanceHook(UnitNode, MethodNode) then Exit;

  // Methoden verschachtelter Typen (T2-Guards-Ruecknahme 2026-07-29):
  // Seit der Parser nested types als eigene nkClass-/nkRecord-Knoten fuehrt
  // (tkKwType-Zweig, 8d36052), ist die Vorfahrenliste auswertbar und der
  // fruehere Blanket-Exit einem PRAEZISEN Skip gewichen:
  //
  //   * Besitzertyp implementiert Interfaces (2.+ Eintrag der
  //     class(...)-Liste - Delphi kennt keine Klassen-Mehrfachvererbung,
  //     alles nach dem ersten Eintrag ist ein Interface): Signatur ist
  //     potenziell compiler-erzwungen (E2291), 'unused parameter' dort
  //     nicht behebbar. Das ist das Bridge-Delegate-Muster
  //     (class(TOCLocal, WKNavigationDelegate) / class(TJavaLocal,
  //     JALWebViewListener)) - 259 von 282 FPs der Korpus-Messung
  //     2026-07-27.
  //   * Besitzertyp nicht auffindbar: defensiv schweigen (sollte seit dem
  //     tkKwType-Zweig nicht mehr vorkommen).
  //   * Sonst - nested class ohne Interfaces, nested record - laeuft die
  //     normale Analyse: das holt die bewusst geopferten ECHTEN Funde
  //     zurueck (3x Shift-Parameter in Alcinoe.FMX.Dynamic.ListBox,
  //     TP-belegt in der ADD-Stichprobe).
  //
  // BEWUSST nur fuer nested-type-Methoden: ein Interface-Skip fuer ALLE
  // Klassen wuerde bestehende Funde normaler Klassen korpusweit droppen -
  // eigenes Vorhaben mit eigenem A/B, nicht Beifang dieser Ruecknahme.
  if TDetectorUtils.IsNestedTypeMethodName(MethodNode.Name) then
  begin
    if not TryFindOwnerType(UnitNode, MethodNode.Name, OwnerCls) then Exit;
    if (OwnerCls.Kind = nkClass) and OwnerHasInterfaceParents(OwnerCls) then
      Exit;
  end;

  if IsLikelyEventHandler(MethodNode) then Exit;
  if ForwardsParamsViaInherited(MethodNode) then Exit;
  // Track B1 (2026-07-12): der SCA028-Follow-up-Guard (IsKeywordRoutineName)
  // ist entfernt - der Parser-Fix (Write/Read-Statement-Dispatch) haengt jetzt
  // die Bodies keyword-benannter Methoden korrekt an, Param-Uses sind sichtbar.

  StrippedReady := False;
  SrcLines      := nil;
  SrcOwned      := False;
  NestedMarks   := TList<TAstNode>.Create;
  Params := MethodNode.FindAll(nkParam);
  BodySB := TStringBuilder.Create;
  try
    if Params.Count = 0 then Exit;
    // nkNestedRange-Marker der verworfenen nested routines einsammeln
    // (direkte MethodNode-Children, siehe uParser2 ~Z.1319).
    for var NR in MethodNode.Children do
      if NR.Kind = nkNestedRange then NestedMarks.Add(NR);
    CollectAllTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);

    for P in Params do
    begin
      // Parser legt Modifier `var/const/out` als Name-Praefix ab
      // ('const X' statt nur 'X'); Param-Name = letztes Wort.
      Name := Trim(P.Name);
      if Name = '' then Continue;
      var SpaceIdx := LastDelimiter(' ', Name);
      if SpaceIdx > 0 then
        Name := Copy(Name, SpaceIdx + 1, MaxInt);
      if Name.StartsWith('_') then Continue;

      LowName := LowerCase(Name);

      // Param-Deklaration ist EIN Vorkommen. Mindestens 2 noetig fuer "genutzt".
      RefCount := 0;
      var Pos1 := 1;
      while True do
      begin
        Pos1 := Pos(LowName, BodyLow, Pos1);
        if Pos1 = 0 then Break;
        var Before : Char := #0;
        if Pos1 > 1 then Before := BodyLow[Pos1 - 1];
        var After  : Char := #0;
        if Pos1 + Length(LowName) - 1 < Length(BodyLow) then
          After := BodyLow[Pos1 + Length(LowName)];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
          Inc(RefCount);
        Pos1 := Pos1 + Length(LowName);
      end;

      if RefCount <= 1 then
      begin
        // Nested-Routine-Fallback (s. Kommentar oben): Param wird in einer vom
        // Parser verworfenen nested proc gelesen -> benutzt, kein Fund.
        if UsedInNestedRanges(LowName) then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.Line);
        F.MissingVar := Format(
          'Unused parameter: %s (never read in method body)', [Name]);
        F.SetKind(fkUnusedParameter);
        Results.Add(F);
      end;
    end;
  finally
    BodySB.Free;
    Params.Free;
    NestedMarks.Free;
    if SrcLines <> nil then ReleaseLines(SrcLines, SrcOwned);
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(UnitNode, M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
