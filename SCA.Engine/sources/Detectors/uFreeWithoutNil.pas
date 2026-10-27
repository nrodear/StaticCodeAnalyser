unit uFreeWithoutNil;

// Detektor: <ident>.Free ohne nachfolgendes <ident> := nil (oder
// FreeAndNil(<ident>) statt der Zwei-Schritt-Variante).
//
// Pattern (Code Smell, Sonar-50 #25):
//   procedure Foo;
//   var L: TStringList;
//   begin
//     L := TStringList.Create;
//     try
//       ...
//     finally
//       L.Free;                 // <-- ohne L := nil; -> dangling pointer
//     end;
//     // L ist hier nicht nil, jeder Folge-Use ist Use-After-Free
//   end;
//
// Korrekt:
//   FreeAndNil(L);
//
// Heuristik (AST):
//   * Walk nkCall mit Name passend zu `<ident>.Free` (oder `.Destroy`).
//   * Schaue im SELBEN Method-Body nach einer Folge-Anweisung
//     `<ident> := nil` ODER `FreeAndNil(<ident>)`. Wenn vorhanden -> OK.
//   * Das Free als LETZTER Aufruf (IsLastStmtOfMethod, "kein Folge-Use
//     moeglich") entlastet nur noch in FREIEN Routinen (ohne Klassen-
//     praefix) - dort ist der Empfaenger ein globales Objekt, und die
//     Routine raeumt typischerweise am Programm- bzw. Skriptende auf
//     (Finalisierungs-Helfer, xEdit-'Finalize'). Steht dahinter ein
//     'raise', gilt auch das nicht: das Programm laeuft weiter.
//     In METHODEN gilt die Ausnahme nicht (2026-10-22): das Objekt lebt
//     ueber die Methode hinaus - TearDown/Reset/FormClose lassen das Feld
//     auf freigegebenem Speicher stehen, ein spaeteres Assigned() oder der
//     Destruktor greift darauf zu; im Konstruktor ruft Delphi bei JEDER
//     Ausnahme den Destruktor ('try .. except FA.Free; FB.Free; raise;
//     end;' = Double Free). Vorher meldete SCA139 von 'FA.Free; FB.Free;'
//     am Methodenende nur FA (xml-as-html-final, mvc-database).
//     Korpus-Stichprobe der Erweiterung (30 Adds, 2026-10-22): 15 echt,
//     13 FP - 7 Globale in freien Routinen (darum die Ausnahme dort),
//     2 Parameter mit Modifier (const: jetzt lokal; out bleibt Befund - die
//     Variable des Aufrufers haengt), 2 Inline-const, 1 BeforeDestruction
//     (unten behoben), 1 sich selbst aushaengende Liste
//     ('while FNext <> nil do FNext.Free', seit U12 entlastet).
//
// U12 (2026-10-27), zwei weitere Restklassen, beide als letzte Gates vor
// dem Melden: (W) Free im Rumpf von 'while X <> nil' / 'while
// Assigned(X)' - FreeInNilTestedLoop; (A) X ist Local oder Parameter
// einer anonymen Methode, deren Rumpf der Parser in die umgebende Methode
// gekippt hatte. (A) war ein Quelltext-Gate; seit der Parser-Charge P2
// (2026-10-27) bleibt der Rumpf einer anonymen Methode mit var-Sektion
// RHS-Text wie jede andere anonyme Methode, das Gate griff danach auf
// keinen Korpusfund mehr (rw 632 = 632 mit und ohne Gate) und ist entfernt.
// BEWUSST NICHT entlastet: Neubelegung ueber einen Property-Setter
// ('FX.Free; X := TFoo.Create'). Der Setter liest bzw. gibt das alte Feld
// typischerweise selbst frei ('if FX = Value', 'FX.Assign(Value)',
// 'FX.Free; FX := Value') - nach einem Free ohne nil-Out ist das UAF oder
// Double Free. Einziger Referenzfall (Lazarus menuintf.pas
// CreateNewMenuItem) ist nur dank eines OnDestroy-Handlers heil.
//
// Limitierung: einfache lexische Heuristik, keine Path-Analysis. False
// Positives bei try/finally L.Free; end mit `Exit;`/`raise;` direkt
// nach Free werden ggf. trotzdem gemeldet.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TFreeWithoutNilDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, GroupedDeclaration, LengthUnderflow, NestedTry, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

// Letzte Segment-Komponente vor `.Free`/`.Destroy` extrahieren.
// `L.Free` -> `L`; `Self.FList.Free` -> `FList`; `'foo'` -> ''.
function ExtractFreeReceiver(const CallName: string): string;
var
  Low : string;
  i, DotPos, EndPos : Integer;
begin
  Result := '';
  Low := LowerCase(CallName);
  // Suche das ".free" oder ".destroy" am Ende.
  if EndsText('.free', Low) then
    EndPos := Length(CallName) - 5
  else if EndsText('.destroy', Low) then
    EndPos := Length(CallName) - 8
  else
    Exit;
  if EndPos <= 0 then Exit;

  // Identifier links vom letzten '.' bis Whitespace/Operator zurueck.
  DotPos := 0;
  for i := EndPos downto 1 do
    if CallName[i] = '.' then begin DotPos := i; Break; end;

  if DotPos > 0 then
    Result := Trim(Copy(CallName, DotPos + 1, EndPos - DotPos))
  else
    Result := Trim(Copy(CallName, 1, EndPos));
end;

function FreeReceiverRootLow(const CallName: string): string;
// WURZEL-Segment (erster Identifier) des Free-Receivers, lowercased:
//   PushStack.Pop.Free -> 'pushstack'  (Methoden-Ergebnis-Free)
//   Slot.DataTags.Free -> 'slot'       (Feld eines lokalen Records)
//   Findings.Free      -> 'findings'
//   FField.Free        -> 'ffield'
//   Self.FField.Free   -> 'self'
// Erlaubt zu erkennen, ob der Free an einer method-scoped Wurzel (lokale Var
// ODER Parameter) haengt - dann ist Nil-Out sinnlos/unmoeglich (FP).
var
  Low, Recv : string;
  i, sI, EndPos : Integer;
begin
  Result := '';
  Low := LowerCase(CallName);
  if EndsText('.free', Low) then EndPos := Length(CallName) - 5
  else if EndsText('.destroy', Low) then EndPos := Length(CallName) - 8
  else Exit;
  if EndPos <= 0 then Exit;
  Recv := Copy(CallName, 1, EndPos);
  i := 1;
  while (i <= Length(Recv)) and
        not CharInSet(Recv[i], ['A'..'Z', 'a'..'z', '_']) do Inc(i);
  sI := i;
  while (i <= Length(Recv)) and
        CharInSet(Recv[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(i);
  Result := LowerCase(Copy(Recv, sI, i - sI));
end;

function IsNilAssignTo(const N: TAstNode; const IdentLow: string): Boolean;
// True wenn N ein nkAssign der Form `<ident> := nil` oder `<owner>.<ident> := nil` ist.
var
  Lhs, LhsLow, RhsLow : string;
begin
  Result := False;
  if N.Kind <> nkAssign then Exit;
  Lhs := N.Name;
  LhsLow := LowerCase(Lhs);
  // Akzeptiere `ident`, `self.ident`, `foo.ident` als LHS-Variante.
  if (LhsLow = IdentLow)
     or EndsText('.' + IdentLow, LhsLow) then
  begin
    // RHS-Text liegt im TypeRef (uParser2 ParseStatement Z. 1618:
    // Node.TypeRef := FullRHS). Children sind in der Regel leer.
    RhsLow := LowerCase(Trim(N.TypeRef));
    if RhsLow = 'nil' then Exit(True);
    // Defensiv fuer aeltere AST-Formen.
    for var Child in N.Children do
      if SameText(Trim(Child.Name), 'nil') then Exit(True);
  end;
end;

function IsFreeAndNilOf(const N: TAstNode; const IdentLow: string): Boolean;
// True wenn N ein nkCall `FreeAndNil(<ident>)` ist.
begin
  Result := False;
  if N.Kind <> nkCall then Exit;
  if not StartsText('freeandnil(', LowerCase(Trim(N.Name))) then Exit;
  Result := Pos('(' + IdentLow + ')', LowerCase(N.Name.Replace(' ', ''))) > 0;
end;

function MentionsIdent(const S, IdentLow: string): Boolean;
// True wenn IdentLow als GANZES Wort (nicht Teil eines laengeren Bezeichners)
// im flachen Text S vorkommt. Wort-Grenze = alles ausser [a-z0-9_].
// Verhindert dass 'l' in 'flist'/'nil' matcht und 'list' in 'flist'.
var
  Low : string;
  P, StartI, LenId, LenS : Integer;
  BeforeOk, AfterOk : Boolean;
begin
  Result := False;
  if (S = '') or (IdentLow = '') then Exit;
  Low := LowerCase(S);
  LenId := Length(IdentLow);
  LenS := Length(Low);
  StartI := 1;
  while True do
  begin
    P := PosEx(IdentLow, Low, StartI);
    if P = 0 then Exit;
    BeforeOk := (P = 1) or
      not CharInSet(Low[P - 1], ['a'..'z', '0'..'9', '_']);
    AfterOk := (P + LenId > LenS) or
      not CharInSet(Low[P + LenId], ['a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Exit(True);
    StartI := P + 1;
  end;
end;

// ---------------------------------------------------------------------------
// U12 (2026-10-27) - zwei Restklassen der Stichprobe vom 22.10.
// ---------------------------------------------------------------------------

const
  IDENT_LOW = ['a'..'z', '0'..'9', '_'];

function IsIdentCharLow(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, IDENT_LOW);
end;

function ContainsBounded(const S, Pat: string;
  const AStopAfter: TSysCharSet): Boolean;
// Pat in S, davor kein Identzeichen ('.' davor ist erlaubt: 'self.x'),
// dahinter keines aus AStopAfter. Fuer 'nil<>x' gehoert '.' dazu
// ('nil<>x.next' prueft x.next, nicht x). Endet Pat selbst auf ein
// Nicht-Identzeichen (')'), gibt es dahinter keine Wortgrenze zu pruefen:
// der Parser klebt 'Assigned(X)and' ohne Leerzeichen an.
var
  P, E    : Integer;
  CheckAt : Boolean;
begin
  Result := False;
  CheckAt := (Pat <> '') and IsIdentCharLow(Pat[Length(Pat)]);
  P := Pos(Pat, S);
  while P > 0 do
  begin
    E := P + Length(Pat);
    if ((P = 1) or not IsIdentCharLow(S[P - 1])) and
       (not CheckAt or (E > Length(S)) or not CharInSet(S[E], AStopAfter)) then
      Exit(True);
    P := Pos(Pat, S, P + 1);
  end;
end;

function CondTestsNil(const ACond, AIdentLow: string): Boolean;
// U12-W: testet die while-Bedingung (nkWhileStmt.TypeRef) den Receiver auf
// nil? Erkannt: 'x<>nil', 'nil<>x', 'Assigned(x)', 'Assigned(Self.x)',
// kleingeschrieben. Leerzeichen muessen nicht weg: der Parser fuegt die
// Bedingung per JoinTokInto zusammen und setzt ein Leerzeichen NUR
// zwischen zwei Bezeichnern ('X <> nil' steht als 'X<>nil' im TypeRef,
// 'X<>nil and Y' behaelt seine Wortgrenze). Bewusst NUR der Nil-Test:
// 'while X.Count > 0 do X.Free' laeuft nach dem ersten Free auf
// freigegebenem Speicher weiter und bleibt Befund.
var
  C : string;
begin
  Result := False;
  if (ACond = '') or (AIdentLow = '') then Exit;
  C := LowerCase(ACond);
  Result := ContainsBounded(C, AIdentLow + '<>nil', IDENT_LOW)
         or ContainsBounded(C, 'nil<>' + AIdentLow, IDENT_LOW + ['.'])
         or ContainsBounded(C, 'assigned(' + AIdentLow + ')', IDENT_LOW)
         or ContainsBounded(C, 'assigned(self.' + AIdentLow + ')', IDENT_LOW);
end;

function SubtreeContains(ARoot, ATarget: TAstNode): Boolean;
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := False;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(ARoot);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur = ATarget then Exit(True);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function FreeInNilTestedLoop(MethodNode, FreeCall: TAstNode;
  const IdentLow: string): Boolean;
// U12-W - sich selbst aushaengende Liste (Lazarus-Baeume):
//   while FFirstChild <> nil do FFirstChild.Free;
// Die Schleife endet nur, weil der Destruktor den Knoten aushaengt und
// FFirstChild weiterschaltet; danach IST das Feld nil. 'Free ohne nil-Out'
// stimmt dort nicht (Referenz perfS184: 8 Funde, alle laz, alle so).
// Der Parser haengt den Schleifenrumpf als Kind an den nkWhileStmt-Knoten
// (ParseWhileStmt -> ParseStatement(WhileNode)), die Bedingung steht im
// TypeRef - beides ohne Quelltext entscheidbar.
var
  Loops : TList<TAstNode>;
  W     : TAstNode;
begin
  Result := False;
  Loops := MethodNode.FindAllRef(nkWhileStmt);
  for W in Loops do
    if (W.Line <= FreeCall.Line) and CondTestsNil(W.TypeRef, IdentLow)
       and SubtreeContains(W, FreeCall) then
      Exit(True);
end;

function IsAssignLhs(const N: TAstNode; const IdentLow: string): Boolean;
// True wenn N ein nkAssign ist, dessen LHS der Ident selbst
// (`<ident> := ...`) oder eine Feld-Kette darauf (`<owner>.<ident> := ...`) ist.
var
  LhsLow : string;
begin
  Result := False;
  if N.Kind <> nkAssign then Exit;
  LhsLow := LowerCase(N.Name);
  Result := (LhsLow = IdentLow) or EndsText('.' + IdentLow, LhsLow);
end;

class procedure TFreeWithoutNilDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Calls   : TList<TAstNode>;
  N       : TAstNode;
  Recv    : string;
  RecvLow : string;
  RootLow : string;
  F       : TLeakFinding;

  function HasNilOutAfter(MethodNode, FreeCall: TAstNode;
    const IdentLow: string): Boolean;
  // Ehemals: `if S = FreeCall then AfterFree := True` - das konnte nie
  // matchen weil Stmts nur nkAssign sammelt und FreeCall ein nkCall ist
  // (Reference-Equality scheitert an Kind-Mismatch). Daher Line-basiert:
  // Statement mit Line > FreeCall.Line gilt als "nach dem Free".
  var
    Stmts : TList<TAstNode>;
    S     : TAstNode;
  begin
    Result := False;
    // STRIKT '<', nicht '<=' (Voll-Review 2026-09-12, Blocker): beim
    // Einzeiler-Idiom 'FTimer.Free; FTimer := nil; RestartUI;' traegt
    // das nil-Assign DIESELBE Zeile wie der Free-Call - '<=' sprang
    // darueber und meldete das Muster, das die Regel selbst empfiehlt.
    // Restrisiko 'FFoo := nil; FFoo.Free;' (nil-Assign VOR dem Free
    // derselben Zeile) ist bewusst akzeptiert - der Parser liefert
    // keine Spalten, und dieser Code waere ohnehin ein anderer Fund.
    Stmts := MethodNode.FindAllRef(nkAssign);
    for S in Stmts do
    begin
      if S.Line < FreeCall.Line then Continue;
      if IsNilAssignTo(S, IdentLow) then Exit(True);
    end;
    Stmts := MethodNode.FindAllRef(nkCall);
    for S in Stmts do
    begin
      if S.Line < FreeCall.Line then Continue;
      if IsFreeAndNilOf(S, IdentLow) then Exit(True);
    end;
  end;

  function HasSafeReassignAfter(MethodNode, FreeCall: TAstNode;
    const IdentLow: string): Boolean;
  // Real-World-FP-Audit 2026-07-11 (reassigned-after-free, dominante FP-Klasse):
  //   FPopUpBitmap.Free;
  //   FPopUpBitmap := TBitmap.Create(width, height);   // Reassign statt := nil
  // Das Feld wird vor jedem Read neu belegt -> KEIN Dangling-Pointer, das
  // FreeAndNil waere hier redundant. Wir akzeptieren daher eine beliebige
  // Zuweisung `<ident> := <expr>` nach dem Free als Abschluss - ABER nur wenn
  // zwischen Free und Reassignment (und in der Reassignment-RHS selbst) KEIN
  // Read des Idents steht. Steht dort ein Read, ist es potentiell ein echtes
  // Use-After-Free -> Befund bleibt (TP-sicher, konservativ).
  var
    Nodes : TList<TAstNode>;
    S     : TAstNode;
    ReLine : Integer;
    Kinds : array[0..10] of TNodeKind;
    K     : TNodeKind;
  begin
    Result := False;
    // 1) Fruehste sichere Reassignment nach dem Free finden.
    ReLine := MaxInt;
    Nodes := MethodNode.FindAllRef(nkAssign);
    for S in Nodes do
    begin
      if S.Line <= FreeCall.Line then Continue;
      if not IsAssignLhs(S, IdentLow) then Continue;
      // RHS darf den freigegebenen Ident nicht selbst lesen
      // (z.B. `L := L.Next` -> Use-After-Free, kein sicherer Reassign).
      if MentionsIdent(S.TypeRef, IdentLow) then Continue;
      if S.Line < ReLine then ReLine := S.Line;
    end;
    if ReLine = MaxInt then Exit; // keine Reassignment -> Standard-Pfad

    // 2) Kein Read des Idents zwischen Free (exkl.) und Reassignment (exkl.)?
    //    Breite Statement-/Bedingungs-Menge scannen; Bedingungstexte von
    //    if/for/while/case liegen in deren TypeRef (uParser2). Mehr geprueft
    //    heisst weniger Unterdrueckung -> TP-sicher.
    Kinds[0] := nkCall;      Kinds[1] := nkAssign;
    Kinds[2] := nkIfStmt;    Kinds[3] := nkElseBranch;
    Kinds[4] := nkCaseStmt;  Kinds[5] := nkCaseArm;
    Kinds[6] := nkForStmt;   Kinds[7] := nkWhileStmt;
    Kinds[8] := nkRepeatStmt; Kinds[9] := nkRaise;
    Kinds[10] := nkExit;
    for K in Kinds do
    begin
      Nodes := MethodNode.FindAllRef(K);
      for S in Nodes do
      begin
        if (S.Line <= FreeCall.Line) or (S.Line >= ReLine) then Continue;
        if MentionsIdent(S.Name, IdentLow)
           or MentionsIdent(S.TypeRef, IdentLow) then Exit; // Read dazwischen
      end;
    end;
    Result := True;
  end;


  function IsLastStmtOfMethod(MethodNode, FreeCall: TAstNode): Boolean;
  var
    AllCalls : TList<TAstNode>;
  begin
    Result := False;
    AllCalls := MethodNode.FindAllRef(nkCall);
    // Wenn Free der letzte nkCall im Method-Body ist, kein Folge-Use moeglich.
    if (AllCalls.Count > 0) and (AllCalls[AllCalls.Count - 1] = FreeCall) then
      Result := True;
  end;

  // Steht ein 'raise' hinter dem Free (gleiche oder spaetere Zeile)? Dann
  // endet die Routine mit einer Ausnahme, und das Programm laeuft weiter -
  // "letzter Aufruf" schuetzt nichts. 'raise' ist kein nkCall,
  // IsLastStmtOfMethod sieht es nicht.
  function RaiseFollows(MethodNode, FreeCall: TAstNode): Boolean;
  var
    Raises : TList<TAstNode>;
    S      : TAstNode;
  begin
    Result := False;
    Raises := MethodNode.FindAllRef(nkRaise);
    for S in Raises do
      if S.Line >= FreeCall.Line then Exit(True);
  end;

  // Zeigt X nach dem Free nachweislich auf nichts Freigegebenes mehr?
  //  * sicher neu belegt (HasSafeReassignAfter, Audit 2026-07-11)
  //  * U12-W: 'while X <> nil do X.Free' - der Destruktor haengt X aus,
  //    nach der Schleife ist X nil (FreeInNilTestedLoop)
  // (Das U12-A-Gate fuer Locals anonymer Methoden ist seit der Parser-
  // Charge P2 entfallen, s. Kopf.) Ein Aufruf statt zwei Gates im Rumpf
  // von AnalyzeUnit: die Schleife dort ist schon tief verschachtelt.
  function NoDanglingAfterFree(MethodNode, FreeCall: TAstNode;
    const IdentLow: string): Boolean;
  begin
    Result := HasSafeReassignAfter(MethodNode, FreeCall, IdentLow)
      or FreeInNilTestedLoop(MethodNode, FreeCall, IdentLow);
  end;

  // Ist der Parameter eine LOKALE Kopie der Referenz? Ohne Modifier, 'const'
  // und 'constref' ja - nil-Setzen erreicht den Aufrufer ohnehin nicht. 'var'
  // und 'out' sind die Variable des Aufrufers: dort bleibt der Fund (und
  // FreeAndNil die Hilfe). Der Parser legt den Modifier als Namenspraefix ab
  // ('const AList', uParser2 nkParam); bis 2026-10-22 verglich der Skip den
  // ganzen Namen, ein const-Parameter kam nie in LocalNames (Korpus:
  // delphimvcframework Render(const ACollection ..)). AIdentLow ist der
  // Bezeichner ohne Modifier.
  function IsLocalCopyParam(const AName: string; out AIdentLow: string): Boolean;
  var
    SpaceIdx : Integer;
    Modifier : string;
  begin
    AIdentLow := LowerCase(Trim(AName));
    Modifier := '';
    SpaceIdx := LastDelimiter(' ', AIdentLow);
    if SpaceIdx > 0 then
    begin
      Modifier := Trim(Copy(AIdentLow, 1, SpaceIdx - 1));
      AIdentLow := Copy(AIdentLow, SpaceIdx + 1, MaxInt);
    end;
    Result := (Modifier = '') or (Modifier = 'const')
      or (Modifier = 'constref');
  end;

var
  LocalNames : TDictionary<string, Boolean>;
  LV         : TAstNode;
  LVs        : TList<TAstNode>;
  Sec        : TAstNode;
  PIdent     : string;
begin
  Methods := UnitNode.FindAllRef(nkMethod);
  for M in Methods do
  begin
    // Destruktor: Free eines Feldes braucht KEIN Nil-Out - das Objekt
    // selbst wird gerade zerstoert, die Felder sterben mit ihm. Real-
    // World-FP-Cluster (2026-06-21): ein einziger Destruktor mit 8
    // Field.Free erzeugte 8 Findings. Komplett skippen.
    //
    // Real-World-FP-Audit 2026-07-10 (SCA139 97% FP): auch 'class destructor'
    // (TypeRef 'class destructor', vom exakten SameText verfehlt) UND
    // OnDestroy-Handler ('FormDestroy'/'DataModuleDestroy'/'<X>.Destroy',
    // ein normales procedure) zerstoeren die Instanz -> Nil-Out wirkungslos,
    // keine UAF-Flaeche. TearDown/Reset-Methoden (enden NICHT auf 'destroy')
    // bleiben bewusst Befund (dort kann ein spaeterer nil-Branch dangling sein).
    if Pos('destructor', LowerCase(M.TypeRef)) > 0 then Continue;
    var MNameLow := LowerCase(M.Name);
    var MDotPos := LastDelimiter('.', MNameLow);
    if MDotPos > 0 then MNameLow := Copy(MNameLow, MDotPos + 1, MaxInt);
    if EndsText('destroy', MNameLow) then Continue;
    // BeforeDestruction laeuft unmittelbar vor dem Destruktor - die Instanz
    // stirbt wie dort (Korpus 2026-10-22: JvID3v2Base FList.Free). Ebenso
    // DoFree (Lazarus-Muster: der Destruktor-Rumpf als Methode, idedebugger
    // TWatchResultTypeStruct) und FinalizeClass (Klassen-Teardown aus der
    // finalization, ZXing-Port) - Korpus-Stichprobe 2026-10-22.
    if (MNameLow = 'beforedestruction') or (MNameLow = 'dofree')
       or (MNameLow = 'finalizeclass') then Continue;
    // Freie Routine (kein Klassenpraefix): der Empfaenger ist kein Feld,
    // die Ausnahme "letzter Aufruf" gilt hier weiter (s. Kopf).
    var IsFreeRoutine := MDotPos = 0;
    // Eine freie Routine 'Finalize*' raeumt Globale am Programm- bzw.
    // Skriptende ab (xEdit-Skripte 'Finalize', VirtualTrees
    // FinalizeGlobalStructures aus der finalization) - auch mitten im Rumpf
    // ist dort nichts mehr zu schuetzen. Eine METHODE 'Finalize' bleibt
    // Befund: sie ist ein Schritt im Lebenszyklus, das Objekt lebt weiter
    // (doublecmd TFileSourceOperation.Finalize).
    if IsFreeRoutine and StartsText('finaliz', MNameLow) then Continue;

    // Lokale Var-Namen einmal pro Methode sammeln. Free-Calls auf Locals
    // sind harmlos, weil die Variable beim Method-Ende sowieso aus dem
    // Scope faellt - kein Dangling-Pointer-Risiko. FreeAndNil ist primaer
    // fuer FELDER relevant (cross-method state). Self-Test fand
    // ~100 FPs durch Locals (uAbstractNotImpl.Methods, uDetectorUtils.Chars, etc).
    LocalNames := TDictionary<string, Boolean>.Create;
    try
      LVs := M.FindAllRef(nkLocalVar);
      for LV in LVs do
        if LV.Name <> '' then
          LocalNames.AddOrSetValue(LowerCase(Trim(LV.Name)), True);
      // Parameter zaehlen wie Locals: method-scoped, Nil-Out beim
      // Method-Ende sinnlos. `Findings.Free` (Param der Ownership uebernimmt)
      // ist kein Free-Without-Nil-Smell. Nur lokale Kopien - var/out bleiben
      // Befund (IsLocalCopyParam).
      LVs := M.FindAllRef(nkParam);
      for LV in LVs do
        if (LV.Name <> '') and IsLocalCopyParam(LV.Name, PIdent) then
          LocalNames.AddOrSetValue(PIdent, True);
      // Lokale und Inline-Konstanten ('const L = TList.Create;', Delphi
      // 10.3+): der Parser legt sie als nkConstSection mit nkField-Kindern
      // ab, nicht als nkLocalVar - sie fallen wie Locals aus dem Scope.
      LVs := M.FindAllRef(nkConstSection);
      for Sec in LVs do
        for LV in Sec.Children do
          if (LV.Kind = nkField) and (LV.Name <> '') then
            LocalNames.AddOrSetValue(LowerCase(Trim(LV.Name)), True);

      Calls := M.FindAllRef(nkCall);
      for N in Calls do
      begin
        Recv := ExtractFreeReceiver(N.Name);
        if Recv = '' then Continue;
        RecvLow := LowerCase(Recv);
        // Indexed-Element (Objects[i].Free / Items[i].Free / Controls[i].Free)
        // oder Typecast/Call (TFoo(FItems[i]).Free / TObject(List[i]).Free):
        // kein simpler Var/Field-Receiver -> die "var := nil"-Empfehlung
        // trifft nicht zu (Collection-Item-Free-Idiom bzw. Cast, oft im
        // Clear/Destroy-Loop). Real-World-FP 2026-06-23 (~100+ Treffer).
        //
        // Real-World-FP-Audit 2026-07-11 (non-lvalue-receiver): bei
        // Typecast eines Index-/Ergebnis-Ausdrucks liefert der Parser den
        // Receiver als Fragment MIT schliessender Klammer/Bracket, z.B.
        //   TCnWizMenuAction(FWizMenuActions[i]).Free -> Recv 'Count])'
        //   TCnCompDirectivePair(FStack.Pop).Free     -> Recv 'Pop)'
        // Das oeffnende '('/'[' faellt dabei aus dem letzten Segment heraus,
        // die schliessende ')'/']' bleibt. Ein sauberes zuweisbares lvalue
        // (reiner Ident / Feld-Kette) enthaelt NIE eine dieser vier Klammern
        // -> FreeAndNil ist syntaktisch unmoeglich, daher ueberspringen.
        if (Pos('[', Recv) > 0) or (Pos('(', Recv) > 0)
           or (Pos(']', Recv) > 0) or (Pos(')', Recv) > 0) then Continue;
        // Receiver darf kein Self/Result/Inherited sein - Free auf Self
        // wird selten von Nil-Out gefolgt (Owner-Pattern).
        if (RecvLow = 'self') or (RecvLow = 'result')
           or (RecvLow = 'inherited') then Continue;
        // WURZEL des Receivers pruefen statt nur des letzten Segments:
        // ist sie eine lokale Var ODER ein Parameter, faellt das Objekt
        // beim Method-Ende aus dem Scope -> Nil-Out sinnlos/unmoeglich.
        // Deckt ab: bare Local (L.Free), Methoden-Ergebnis
        // (PushStack.Pop.Free -> Wurzel pushstack), lokales Record-Feld
        // (Slot.DataTags.Free -> Wurzel slot), Parameter (Findings.Free).
        // Echte Feld-Frees (FField.Free / Self.FField.Free) haben eine
        // Nicht-Local-Wurzel und bleiben Befund.
        RootLow := FreeReceiverRootLow(N.Name);
        if (RootLow <> '') and LocalNames.ContainsKey(RootLow) then Continue;

        // Real-World-FP-Audit 2026-07-18 (non-lvalue Methoden-/Member-Ergebnis-
        // Receiver): FMsgQueue.Pop.Free / FIfStack.Pop.Free / FProcStack.Pop.Free.
        // Ein MEHRSEGMENTIGER, klammerloser Receiver (>=2 Punkte im Call-Namen)
        // friert das ERGEBNIS eines Member-/Methodenaufrufs auf einer Nicht-
        // Local-Wurzel ein - KEIN zuweisbares lvalue: 'FMsgQueue.Pop := nil' /
        // FreeAndNil(FMsgQueue.Pop) sind syntaktisch unmoeglich -> Empfehlung
        // sinnlos, ueberspringen. Der Detektor legt hier ohnehin nur das letzte
        // Segment (Recv='Pop') als Nil-Out-Ident ab -> falsch adressierte Meldung.
        // Cast/Index sind oben (Recv-Check '('/'['/')'/']') bereits raus; das
        // einsegmentige Feld 'FList.Free' hat genau 1 Punkt und bleibt Befund.
        // AUSNAHME 'self': 'Self.FField.Free' ist ein echtes nil-outbares Feld
        // (Self.FField := nil legal) -> bleibt Befund.
        var DotCount := 0;
        for var ci := 1 to Length(N.Name) do
          if N.Name[ci] = '.' then Inc(DotCount);
        if (DotCount >= 2) and (RootLow <> 'self') then Continue;

        if HasNilOutAfter(M, N, RecvLow) then Continue;
        // Reassigned-after-free (FPopUpBitmap.Free; FPopUpBitmap := TBitmap.Create):
        // Feld vor jedem Read neu belegt -> kein Dangling-Pointer. Seit U12
        // im selben Aufruf: Nil-Test-Schleife (NoDanglingAfterFree).
        if NoDanglingAfterFree(M, N, RecvLow) then Continue;
        if IsFreeRoutine and IsLastStmtOfMethod(M, N)
           and not RaiseFollows(M, N) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(N.Line);
        F.MissingVar := Format(
          '%s.Free without subsequent %s := nil - prefer FreeAndNil(%s)',
          [Recv, Recv, Recv]);
        F.SetKind(fkFreeWithoutNil);
        Results.Add(F);
      end;
    finally
      LocalNames.Free;
    end;
  end;
end;

end.
