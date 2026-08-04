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
  // Gestrippte Quelle EINER Datei, ueber alle Methoden hinweg geteilt.
  // Ready wird gesetzt, sobald der Versuch gelaufen ist - auch wenn er
  // scheiterte, damit eine unlesbare Datei nicht je Methode erneut
  // geoeffnet wird.
  TStrippedUnit = record
    Ready : Boolean;
    Lines : TArray<string>;
  end;

  TUnusedParameterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(UnitNode, MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      var AStripped: TStrippedUnit);
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

// True wenn der Rumpf AUSSCHLIESSLICH aus einem `raise` besteht
// ('raise ENotImplemented.Create(...)', 'raise ENotSupportedException...').
//
// 30%-Real-World-Audit 2026-07-31: solche Ruempfe koennen ihre Parameter
// gar nicht lesen - die Signatur stammt von aussen (Interface, Vorfahr,
// Framework-Vertrag), der Rumpf ist bewusst leer. 'Unused parameter' ist
// dort nicht behebbar: den Parameter zu streichen bricht die Signatur.
// Korpus-Messung after126: 1.021 der 19.402 Funde (5,3 %).
function BodyIsRaiseOnly(MethodNode: TAstNode): Boolean;
var
  Blk, Ch : TAstNode;
  Cnt     : Integer;
begin
  Result := False;
  Blk := nil;
  for Ch in MethodNode.Children do
    if Ch.Kind = nkBlock then
    begin
      Blk := Ch;
      Break;
    end;
  if Blk = nil then Exit;
  Cnt := 0;
  for Ch in Blk.Children do
  begin
    Inc(Cnt);
    if Cnt > 1 then Exit;
    if Ch.Kind <> nkRaise then Exit;
  end;
  Result := Cnt = 1;
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

procedure EnsureUnitStripped(var AStripped: TStrippedUnit;
  const AFileName: string);
// Einmal je DATEI, nicht je Methode. Der Strip selbst ist ueber
// StripStringsAndCommentsCached ohnehin gecacht; das Split in Zeilen war es
// nicht, und genau das legte je Aufruf ein Array ueber die ganze Datei an.
var
  Code    : string;
  LineFor : TArray<Integer>;
  Src     : TStringList;
  Owned   : Boolean;
begin
  if AStripped.Ready then Exit;
  AStripped.Ready := True;
  Src := AcquireLines(AFileName, Owned, nil);
  if Src = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Src, LineFor, nil, AFileName, ' ');
    AStripped.Lines := Code.Split([#10]);
  finally
    ReleaseLines(Src, Owned);
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
  const FileName: string; Results: TObjectList<TLeakFinding>;
  var AStripped: TStrippedUnit);
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
  // Rumpf-Zeilenbereich fuer die Quell-Rueckfrage. Bewusst Locals der
  // umschliessenden Routine statt out-Parameter: der eigene Analyser
  // meldet out zu Recht als schwer lesbar (AvoidOut), und die
  // verschachtelte Funktion sieht die Locals ohnehin.
  BodyFrom      : Integer;
  BodyTo        : Integer;

  function BodyLineRangeFound: Boolean;
  // Von 'begin' bis zur groessten Zeilennummer im Teilbaum.
  //
  // ANFANG bewusst am nkBlock und nicht am Methodenkopf: in der SIGNATUR
  // steht der Parametername ja - von dort zu scannen hiesse, jeden
  // Parameter als benutzt zu sehen und die Regel abzuschalten.
  //
  // ENDE ueber max(Line) des Teilbaums. Das traegt, weil die Luecke im
  // INHALT der Knoten liegt, nicht in ihrer Existenz: jede Anweisung ist
  // ein Knoten mit Zeilennummer, auch wenn ihr Text unvollstaendig
  // abgelegt wurde. Genau das ist der Fall bei den beiden gemessenen
  // Formen (Index-Ausdruck links einer Zuweisung, Argumente hinter einem
  // as-Cast).
  var
    Blk   : TAstNode;
    Stack : TStack<TAstNode>;
    Cur   : TAstNode;
    I     : Integer;
  begin
    Result := False;
    Blk := MethodNode.FindFirstChild(nkBlock);
    if Blk = nil then Exit;
    BodyFrom := Blk.Line;
    BodyTo   := Blk.Line;
    Stack := TStack<TAstNode>.Create;
    try
      Stack.Push(MethodNode);
      while Stack.Count > 0 do
      begin
        Cur := Stack.Pop;
        if Cur.Line > BodyTo then BodyTo := Cur.Line;
        for I := 0 to Cur.Children.Count - 1 do
          Stack.Push(Cur.Children[I]);
      end;
    finally
      Stack.Free;
    end;
    Result := (BodyFrom > 0) and (BodyTo >= BodyFrom);
  end;

  function UsedInMethodSource(const NameLow: string): Boolean;
  // Letzte Rueckfrage vor dem Melden: steht der Name ueberhaupt im
  // Rumpf-QUELLTEXT? Strings und Kommentare sind gestrippt - ein Name im
  // Kommentar zaehlt NIE als Nutzung.
  //
  // MONOTON: kann nur Funde wegnehmen, nie welche erzeugen.
  //
  // RESTRISIKO Shadowing - eine gleichnamige lokale Variable laesst den
  // Parameter benutzt aussehen und unterdrueckt einen echten Fund. Exakt
  // dasselbe Risiko traegt UsedInNestedRanges seit 2026-07-18, dort
  // ausdruecklich akzeptiert: fuer einen Hint ist ein verschwiegener Fund
  // billiger als ein falscher.
  var
    li, q, NL_ : Integer;
    L : string;
  begin
    Result := False;
    if not BodyLineRangeFound then Exit;
    EnsureUnitStripped(AStripped, FileName);
    if Length(AStripped.Lines) = 0 then Exit;
    NL_ := Length(NameLow);
    for li := BodyFrom to BodyTo do
    begin
      if (li < 1) or (li > Length(AStripped.Lines)) then Continue;
      L := LowerCase(AStripped.Lines[li - 1]);
      // STARTZEILE NUR AB DEM begin-TOKEN (Review 2026-08-04): teilt die
      // SIGNATUR die Zeile mit dem begin - Einzeiler wie
      //   procedure TFoo.Bar(Sender: TObject); begin end;
      // oder eine umgebrochene Parameterliste mit '); begin' am Ende -
      // stuende der Parametername sonst im gescannten Bereich, und die
      // DEKLARATION zaehlte als Nutzung: echter Fund still unterdrueckt.
      // Der Strip ersetzt positions-erhaltend mit ' ', die Spalten der
      // gestrippten Zeile stimmen also mit der Quelle ueberein.
      if li = BodyFrom then
      begin
        q := Pos('begin', L);
        while (q > 0) and not
              (((q = 1) or not IsIdentChar(L[q - 1])) and
               ((q + 5 > Length(L)) or not IsIdentChar(L[q + 5]))) do
          q := Pos('begin', L, q + 1);
        if q > 0 then
          L := Copy(L, q + 5, MaxInt)
        else
          Continue;   // begin nicht auf dieser Zeile auffindbar - defensiv
      end;
      q := Pos(NameLow, L);
      while q > 0 do
      begin
        if ((q = 1) or not IsIdentChar(L[q - 1])) and
           ((q + NL_ > Length(L)) or not IsIdentChar(L[q + NL_])) then
          Exit(True);
        q := Pos(NameLow, L, q + 1);
      end;
    end;
  end;

  function UsedInNestedRanges(const NameLow: string): Boolean;
  var
    M : TAstNode;
    li, EndL, q, NL : Integer;
    L : string;
  begin
    Result := False;
    if NestedMarks.Count = 0 then Exit;
    EnsureUnitStripped(AStripped, FileName);
    if Length(AStripped.Lines) = 0 then Exit;
    NL := Length(NameLow);
    for M in NestedMarks do
    begin
      EndL := StrToIntDef(M.TypeRef, M.Line);
      for li := M.Line to EndL do
      begin
        if (li < 1) or (li > Length(AStripped.Lines)) then Continue;
        L := LowerCase(AStripped.Lines[li - 1]);
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
  end
  // ---- 2026-08-01: derselbe Skip fuer NICHT-verschachtelte Klassen ------
  // Der Kommentar oben kuendigt genau das als eigenes Vorhaben mit eigenem
  // A/B an - hier ist es. Das Audit vom 31.07. hat die Luecke als eigene
  // FP-Klasse belegt (4 von 24 Stichproben): der Interface-Skip griff nur
  // bei nested types, waehrend IMVCSerializer / IOTADebuggerNotifier /
  // IJclSingleList / IMVCAuthenticationHandler an ganz gewoehnlichen
  // Klassen haengen. Deren Signatur ist genauso compiler-erzwungen (E2291),
  // 'unused parameter' dort genauso wenig behebbar.
  //
  // UNTERSCHIED zum nested-Zweig: wird der Besitzertyp NICHT gefunden,
  // laeuft die Analyse normal weiter statt zu schweigen. Bei nested types
  // ist Nicht-Finden ein Hinweis auf ein Homonym (dort ist Schweigen
  // richtig); bei einer gewoehnlichen Klasse MUSS die Deklaration in
  // derselben Unit stehen, Nicht-Finden heisst also Parser-Aerger - und
  // daraus einen Blanket-Skip zu machen waere zu viel.
  //
  // BEWUSST NICHT umgesetzt: die Audit-Zusatzbedingung "und die Methode ist
  // public/protected". Die Sichtbarkeit haengt am nkVisibilitySection der
  // DEKLARATION, nicht an der Implementierung; der Weg dorthin ist ein
  // eigener Lookup. Ohne die Bedingung faellt auch die private Methode
  // einer interface-tragenden Klasse weg - Ueberreichweite, die als
  // FN-Restklasse hier notiert ist.
  else if TryFindOwnerType(UnitNode, MethodNode.Name, OwnerCls) and
          (OwnerCls.Kind = nkClass) and
          OwnerHasInterfaceParents(OwnerCls) then
    Exit;

  // Rumpf ist nur ein `raise` - die Parameter KOENNEN nicht gelesen werden.
  if BodyIsRaiseOnly(MethodNode) then Exit;

  if IsLikelyEventHandler(MethodNode) then Exit;
  if ForwardsParamsViaInherited(MethodNode) then Exit;
  // Track B1 (2026-07-12): der SCA028-Follow-up-Guard (IsKeywordRoutineName)
  // ist entfernt - der Parser-Fix (Write/Read-Statement-Dispatch) haengt jetzt
  // die Bodies keyword-benannter Methoden korrekt an, Param-Uses sind sichtbar.

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
        // Quell-Rueckfrage fuer den eigenen Rumpf (2026-08-03): der
        // AST-Flachtext ist eine Teilmenge der Quelle. Bevor wir Abwesenheit
        // BEHAUPTEN, fragen wir die Quelle. Am gebauten Stand reproduziert:
        // 'SystemPath[Kind] := x' und '(Obj as T).M(Index, 1)' - in beiden
        // Faellen fehlt der Bezeichner im AST-Text, steht aber im Rumpf.
        if UsedInMethodSource(LowName) then Continue;
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
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods  : TList<TAstNode>;
  M        : TAstNode;
  Stripped : TStrippedUnit;
begin
  // EINE gestrippte Fassung fuer alle Methoden dieser Datei. Wird erst
  // gefuellt, wenn die erste Methode sie wirklich braucht - Dateien ohne
  // Kandidaten zahlen gar nichts.
  Stripped.Ready := False;
  Stripped.Lines := nil;
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(UnitNode, M, FileName, Results, Stripped);
  finally
    Methods.Free;
  end;
end;

end.
