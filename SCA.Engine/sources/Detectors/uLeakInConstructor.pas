unit uLeakInConstructor;

// Detektor: Constructor weist Felder via .Create zu UND raised - bei raise
// nach partieller Initialisierung leaken die schon erzeugten Felder.
//
// Pattern (Bug, Sonar-50 #12):
//   constructor TFoo.Create;
//   begin
//     FA := TStringList.Create;
//     FB := TOtherThing.Create;     // angenommen wirft hier
//     if not Valid then
//       raise EInvalidInput.Create('bad');   // <-- FA leakt
//   end;
//
// Korrekt:
//   constructor TFoo.Create;
//   begin
//     FA := TStringList.Create;
//     try
//       FB := TOtherThing.Create;
//       if not Valid then
//         raise EInvalidInput.Create('bad');
//     except
//       FreeAndNil(FA);
//       raise;
//     end;
//   end;
//
// Alternative: Delphi UND FPC rufen Destroy auf der halb-konstruierten
// Instanz, wenn der Constructor wirft. Ein Destructor, der die Felder
// freigibt, faengt den Exception-Pfad also vollstaendig ab (siehe
// Destruktor-Gate unten).
//
// Erkennung (within-method, heuristisch):
//   * Pro Constructor-Implementierung (TypeRef startet mit 'constructor',
//     KEIN ';class'-Marker).
//   * Body enthaelt mindestens einen nkAssign mit LHS = `F<Name>` oder
//     `Self.F<Name>` und RHS = `<Class>.Create(...)`.
//   * Body enthaelt mindestens einen nkRaise auf/nach der ersten Allokation.
//   * Body enthaelt KEIN nkTryExcept (Heuristik: dann vertrauen wir dem
//     Author - kein Befund).
//
// FP-GATES (2026-07-31, 30%-Real-World-Audit sca-rw-after119; 86% FP im
// Sample, Error-Tier):
//   [G1] Destruktor-Deckung: hat die Klasse in DIESER Unit einen Destruktor,
//        der ALLE im Ctor allokierten F-Felder freigibt, raeumt der
//        RTL-Auto-Destroy den raise-Pfad vollstaendig auf -> kein Fund.
//        Belege: JvBouncingLabel.pas:130, Alcinoe.FMX.StdCtrls.pas:4148,
//        mormot.db.rad.nexusdb.pas:351, uwayland.pas:131, JvCabFile.pas:141,
//        MVCFramework.Serializer.Commons.pas:1228, JclParseUses.pas:845, ...
//        (11 von 14 im Sample). Deckt der Destruktor auch nur EIN Feld nicht
//        ab, bleibt der Fund.
//   [G1a] TP-Ausnahme "Destruktor ist nicht nil-tolerant": dereferenziert der
//        Destruktor ein allokiertes Feld per 'FFoo.Member := ...' OHNE
//        Nil-Guard, laeuft er nach einem Ctor-raise in eine AV BEVOR die
//        Freigabe kommt -> Fund bleibt (Alcinoe.FMX.VideoPlayer.pas:2069).
//   [G1b] TP-Ausnahme "inherited Create erst nach dem raise" beim
//        TThread-Muster (Alcinoe.FMX.WebRTC.pas:1244) -> Fund bleibt. Eng
//        gefasst: nur benanntes 'inherited Create...' UND Thread-Evidenz
//        (FreeOnTerminate im Ctor bzw. Terminate/WaitFor im Destruktor);
//        ein blosses 'inherited;' am Ctor-Ende zaehlt NICHT (sonst waere
//        Alcinoe.FMX.Styles.pas:26991 wieder ein FP).
//   [G2] Werttyp-Factory: 'TRec.Create(...)' auf einem RECORD allokiert
//        nichts Freigebbares. Erkannt werden Records dieser Unit plus eine
//        kuratierte RTL-Seed-Liste (TPointF/TRectF/...; Beleg
//        Alcinoe.FMX.Dynamic.Controls.pas:675 'FScale := TPointF.Create(1,1)').
//   [G3] Static-Factory mit Create-SUFFIX ('TwbFileID.CreateLight(...)',
//        wbImplementation.pas:3323): ist der '.create'-Treffer NIE ein
//        echter 'Create'-Aufruf UND wird das Feld in der ganzen Unit nirgends
//        freigegeben, ist es kein besitzendes Heap-Feld -> kein Fund.
//
// Warum kein TTypeIndex (Cross-Unit-Werttyp-Aufloesung wie in SCA001):
// SCA136 ist in uStaticAnalyzer2 als 3-Parameter-Detektor (AddD3) ohne
// TAnalyzeContext registriert - CtxTypeIndex ist hier schlicht nicht
// erreichbar. G2/G3 sind der single-unit-Ersatz.
//
// Limitierungen:
//   * Keine echte Flow-Analyse.
//   * try/except, das nur einen Teil der Felder schuetzt, wird als
//     "schuetzt alles" interpretiert.
//   * Freigabe ueber einen Destruktor-HELFER ('flCloseFile;') wird nicht
//     erkannt - der Fund bleibt (konservativ Richtung FP, nicht FN).
//
// Schweregrad: lsError - leak im Exception-Pfad ist real.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLeakInConstructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils, uDetectorUtils;

const
  // [G2] Kuratierte RTL-Value-Type-Records mit 'Create'-Factory. Spiegelt die
  // Seed-Liste aus uTypeIndex.SeedKnownTypes (dort fuer denselben Zweck) plus
  // die drei Integer-Varianten aus System.Types. Lokale Kopie, weil der
  // Cross-Unit-Index von hier nicht erreichbar ist (siehe Datei-Kopf).
  RTL_VALUE_RECORDS : array[0..11] of string = (
    'tregex',          // System.RegularExpressions
    'tnamevaluepair',  // System.Classes
    'trtticontext',    // System.Rtti
    'tvalue',          // System.Rtti
    'tstopwatch',      // System.Diagnostics
    'tguid',           // System
    'tsizef',          // System.Types
    'tpointf',         // System.Types
    'trectf',          // System.Types
    'tsize',           // System.Types
    'tpoint',          // System.Types
    'trect'            // System.Types
  );

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

// Ganzwort-Suche in bereits gelowertem Text: 'ftimer' matcht 'ftimer.free'
// und 'freeandnil(ftimer)', aber NICHT 'ftimer2' oder 'xftimer'.
function ContainsIdent(const HaystackLow, IdentLow: string): Boolean;
var
  P, Start, L : Integer;
begin
  Result := False;
  L := Length(IdentLow);
  if (L = 0) or (HaystackLow = '') then Exit;
  Start := 1;
  repeat
    P := PosEx(IdentLow, HaystackLow, Start);
    if P = 0 then Exit;
    if ((P = 1) or not IsIdentChar(HaystackLow[P - 1])) and
       ((P + L > Length(HaystackLow)) or not IsIdentChar(HaystackLow[P + L])) then
      Exit(True);
    Start := P + 1;
  until False;
end;

// 'Self.FFoo' -> 'ffoo'; 'Self.FFoo.Bar' -> 'ffoo.bar'. Trim + lowercase.
function LhsWithoutSelf(const Lhs: string): string;
begin
  Result := LowerCase(Trim(Lhs));
  if Result.StartsWith('self.') then Result := Copy(Result, 6, MaxInt);
end;

// Fuehrende Ident-Zeichen: 'ffoo.bar' -> 'ffoo', 'ffoo[]' -> 'ffoo'.
function BareIdentPrefix(const S: string): string;
var
  i : Integer;
begin
  i := 0;
  while (i < Length(S)) and IsIdentChar(S[i + 1]) do Inc(i);
  Result := Copy(S, 1, i);
end;

// 'TALCustomTrack.TThumb.Create' -> 'talcustomtrack.tthumb' (alles vor dem
// LETZTEN Punkt; deckt verschachtelte Typen mit ab). '' wenn unqualifiziert.
function OwnerTypeLow(const MethodName: string): string;
var
  P : Integer;
begin
  P := LastDelimiter('.', MethodName);
  if P <= 1 then Exit('');
  Result := LowerCase(Copy(MethodName, 1, P - 1));
end;

function IsConstructorImpl(MethodNode: TAstNode): Boolean;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  Result := TR.StartsWith('constructor') and (Pos(';class', TR) = 0);
end;

function IsDestructorImpl(MethodNode: TAstNode): Boolean;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  Result := TR.StartsWith('destructor') and (Pos(';class', TR) = 0);
end;

function HasBlockChild(MethodNode: TAstNode): Boolean;
var
  Child : TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then Exit(True);
end;

function HasBodyBlock(MethodNode: TAstNode): Boolean;
const
  STMT_KINDS = [nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt,
                nkWhileStmt, nkRepeatStmt, nkTryExcept, nkTryFinally,
                nkRaise, nkExit, nkInherited, nkLocalVar];
var
  Child, Inner : TAstNode;
begin
  // Body-Detection: irgendein Statement-artiger Descendant. Forward-Decls
  // im Class-Body haben keinen Body.
  // Parser wickelt `begin ... end` in ein nkBlock-Kind ein - eine Ebene
  // tiefer schauen, sonst sehen wir bei impl-Bodies nur nkBlock und
  // verpassen den Body komplett (Audit V5, 2026-05-30).
  Result := False;
  for Child in MethodNode.Children do
  begin
    if Child.Kind in STMT_KINDS then Exit(True);
    if Child.Kind = nkBlock then
      for Inner in Child.Children do
        if Inner.Kind in STMT_KINDS then Exit(True);
  end;
end;

function HasRaise(MethodNode: TAstNode): Boolean;
var
  Raises : TList<TAstNode>;
begin
  Raises := MethodNode.FindAllRef(nkRaise);
  Result := (Raises <> nil) and (Raises.Count > 0);
end;

function HasProtectingTryExcept(MethodNode: TAstNode): Boolean;
var
  Tries : TList<TAstNode>;
begin
  Tries := MethodNode.FindAllRef(nkTryExcept);
  Result := (Tries <> nil) and (Tries.Count > 0);
end;

// Fix (Audit 2026-06-07): klassisches Validate-then-Allocate-Pattern
//   constructor TFoo.Create(N: Integer);
//   begin
//     if N < 1 then raise Exception.Create('bad');
//     FList := TList.Create;   // erst HIER allokiert
//   end;
// Wenn ALLE raises VOR dem ersten Field-.Create kommen, ist nichts zum
// Leak-en. Audit-Trigger: LoggerPro.MemoryAppender, MVCFramework.
function HasRaiseAtOrAfter(MethodNode: TAstNode; Line: Integer): Boolean;
var
  Raises : TList<TAstNode>;
  R      : TAstNode;
begin
  Result := False;
  if Line = MaxInt then Exit;
  Raises := MethodNode.FindAllRef(nkRaise);
  if Raises = nil then Exit;
  for R in Raises do
    if R.Line >= Line then Exit(True);
end;

// ---------------------------------------------------------------------------
// [G2]/[G3]: Werttyp- und Static-Factory-Erkennung auf dem RHS-Text.
// RHS landet im Parser direkt in nkAssign.TypeRef (Audit V5 / 2026-05-30 -
// siehe uParser2.pas:2649/2650); der Parser erzeugt KEIN nkCall-Kind fuer
// Assignment-RHS.
// ---------------------------------------------------------------------------

// Liefert den Typnamen vor dem ERSTEN '.create' (letztes Ident-Segment, ohne
// Generic-Argumente) und setzt ExactCreate=True, wenn IRGENDEIN '.create'-
// Vorkommen ein echter 'Create'-Aufruf ist (danach kein Ident-Zeichen).
//   'taltexture.create'                -> 'taltexture', Exact=True
//   'tdictionary<string,integer>.create'-> 'tdictionary', Exact=True
//   'twbfileid.createlight(1)'         -> 'twbfileid',  Exact=False
function CreateCallTypeLow(const RhsLow: string; out ExactCreate: Boolean): string;
const
  DOT_CREATE = '.create';
var
  P, Start, L, K, LtPos : Integer;
  Seg : string;
begin
  Result      := '';
  ExactCreate := False;
  L := Length(RhsLow);
  Start := 1;
  repeat
    P := PosEx(DOT_CREATE, RhsLow, Start);
    if P = 0 then Break;
    if (P + Length(DOT_CREATE) > L) or
       not IsIdentChar(RhsLow[P + Length(DOT_CREATE)]) then
      ExactCreate := True;
    if Result = '' then
    begin
      Seg := Copy(RhsLow, 1, P - 1);
      LtPos := Pos('<', Seg);
      if LtPos > 0 then Seg := Copy(Seg, 1, LtPos - 1);
      K := Length(Seg);
      while (K >= 1) and IsIdentChar(Seg[K]) do Dec(K);
      Result := Copy(Seg, K + 1, MaxInt);
    end;
    Start := P + Length(DOT_CREATE);
  until False;
end;

function IsKnownValueRecord(const TypeLow: string): Boolean;
var
  S : string;
begin
  Result := False;
  if TypeLow = '' then Exit;
  for S in RTL_VALUE_RECORDS do
    if S = TypeLow then Exit(True);
end;

function IsUnitRecordType(UnitNode: TAstNode; const TypeLow: string): Boolean;
var
  Recs : TList<TAstNode>;
  N    : TAstNode;
begin
  Result := False;
  if TypeLow = '' then Exit;
  Recs := UnitNode.FindAllRef(nkRecord);
  if Recs = nil then Exit;
  for N in Recs do
    if LowerCase(Trim(N.Name)) = TypeLow then Exit(True);
end;

// ---------------------------------------------------------------------------
// [G1]: Destruktor-Deckung.
// ---------------------------------------------------------------------------

function LooksLikeFreeCall(const NameLow: string): Boolean;
// Deckt Free / FreeAndNil / ALFreeAndNil / DisposeOf / Release / _Release ab.
begin
  Result := (Pos('free', NameLow) > 0)
         or (Pos('disposeof', NameLow) > 0)
         or (Pos('release', NameLow) > 0)
         or (Pos('.destroy', NameLow) > 0);
end;

// True wenn im Subtree von Node das Feld FieldLow freigegeben wird.
// Wird sowohl auf Destruktor-Rumpfe [G1] als auch auf den ganzen Unit-Knoten
// [G3] angewandt.
function BodyFreesField(Node: TAstNode; const FieldLow: string): Boolean;
var
  Nodes : TList<TAstNode>;
  N     : TAstNode;
  S     : string;
begin
  Result := False;
  Nodes := Node.FindAllRef(nkCall);
  if Nodes <> nil then
    for N in Nodes do
    begin
      // Review-MEDIUM 2026-08-09: Literale blanken - 'free'/Feldname in einem
      // String-Literal (z.B. Log('failed to free fconn')) ist keine Freigabe.
      S := TDetectorUtils.BlankStringLiterals(LowerCase(N.Name));
      if LooksLikeFreeCall(S) and ContainsIdent(S, FieldLow) then Exit(True);
    end;
  // Interface-Felder werden per 'FFoo := nil' freigegeben (_Release).
  Nodes := Node.FindAllRef(nkAssign);
  if Nodes <> nil then
    for N in Nodes do
      if (LhsWithoutSelf(N.Name) = FieldLow) and
         (LowerCase(Trim(N.TypeRef)) = 'nil') then Exit(True);
end;

// [G1a] True wenn der Destruktor 'FFoo.Member := ...' schreibt, ohne dass es
// irgendwo im Destruktor einen if-Guard auf FFoo gibt. Nach einem Ctor-raise
// kann FFoo noch nil sein -> AV vor der Freigabe der uebrigen Felder.
function DtorDerefsFieldUnguarded(DtorNode: TAstNode; const FieldLow: string): Boolean;
var
  Nodes : TList<TAstNode>;
  N     : TAstNode;
  Found : Boolean;
begin
  Result := False;
  Found  := False;
  Nodes := DtorNode.FindAllRef(nkAssign);
  if Nodes <> nil then
    for N in Nodes do
      if LhsWithoutSelf(N.Name).StartsWith(FieldLow + '.') then
      begin
        Found := True;
        Break;
      end;
  if not Found then Exit;
  Nodes := DtorNode.FindAllRef(nkIfStmt);
  if Nodes <> nil then
    for N in Nodes do
      if ContainsIdent(LowerCase(N.TypeRef), FieldLow) then Exit(False);
  Result := True;
end;

// Thread-Evidenz: der Ctor setzt FreeOnTerminate ODER ein Destruktor faehrt
// den Thread herunter (Terminate/WaitFor). Nur dann ist ein spaetes
// 'inherited Create' wirklich toedlich (siehe InheritedCreateAfterRaise).
function LooksLikeThreadClass(Ctor: TAstNode; Dtors: TList<TAstNode>): Boolean;
var
  Nodes : TList<TAstNode>;
  N, D  : TAstNode;
  S     : string;
begin
  Result := False;
  Nodes := Ctor.FindAllRef(nkAssign);
  if Nodes <> nil then
    for N in Nodes do
      if LhsWithoutSelf(N.Name) = 'freeonterminate' then Exit(True);
  for D in Dtors do
  begin
    Nodes := D.FindAllRef(nkCall);
    if Nodes = nil then Continue;
    for N in Nodes do
    begin
      S := LowerCase(N.Name);
      if ContainsIdent(S, 'terminate') or ContainsIdent(S, 'waitfor') then
        Exit(True);
    end;
  end;
end;

// [G1b] TThread-Muster (Beleg Alcinoe.FMX.WebRTC.pas:1244): ein EXPLIZITES
// 'inherited Create(...)' steht erst NACH dem raise - die Basis ist beim
// Unwind nie konstruiert worden und der Auto-Destroy laeuft auf kaputtem
// Zustand (Terminate/WaitFor auf einem nie gestarteten Thread), raeumt also
// NICHT auf. Zwei Einschraenkungen halten die Regel eng:
//   * nur ein benanntes 'inherited Create...' zaehlt. Ein blosses
//     'inherited;' am Ctor-Ende ist harmlos (Beleg Alcinoe.FMX.Styles.pas:
//     26991 TALStyleManager - im Audit klar als FP bewertet).
//   * die Klasse muss thread-artig sein (LooksLikeThreadClass).
function InheritedCreateAfterRaise(Ctor: TAstNode; Dtors: TList<TAstNode>): Boolean;
var
  Nodes      : TList<TAstNode>;
  N          : TAstNode;
  FirstRaise : Integer;
  LateCreate : Boolean;
begin
  Result     := False;
  FirstRaise := MaxInt;
  Nodes := Ctor.FindAllRef(nkRaise);
  if Nodes = nil then Exit;
  for N in Nodes do
    if N.Line < FirstRaise then FirstRaise := N.Line;
  if FirstRaise = MaxInt then Exit;

  LateCreate := False;
  Nodes := Ctor.FindAllRef(nkInherited);
  if Nodes = nil then Exit;
  for N in Nodes do
    if (N.Line > FirstRaise) and
       LowerCase(Trim(N.Name)).StartsWith('create') then
    begin
      LateCreate := True;
      Break;
    end;
  if not LateCreate then Exit;

  Result := LooksLikeThreadClass(Ctor, Dtors);
end;

// Sammelt die im Ctor allokierten F-Feldnamen (lowercase, dedupliziert) und
// liefert die Zeile der ERSTEN Allokation (MaxInt wenn keine).
// Hier greifen [G2] und [G3].
function CollectAllocatedFields(UnitNode, MethodNode: TAstNode;
  Fields: TList<string>): Integer;
var
  Assigns : TList<TAstNode>;
  N       : TAstNode;
  LhsLow, RhsLow, TypeLow, FieldLow : string;
  Exact   : Boolean;
begin
  Result := MaxInt;
  Assigns := MethodNode.FindAllRef(nkAssign);
  if Assigns = nil then Exit;
  for N in Assigns do
  begin
    // 90%-Variante: Identifier (optional Self.-Prefix) der mit 'f' beginnt.
    LhsLow := LhsWithoutSelf(N.Name);
    if (Length(LhsLow) < 2) or (LhsLow[1] <> 'f') then Continue;
    // Review-MEDIUM 2026-08-09: Literale blanken - '.create' INNERHALB eines
    // String-Literals (z.B. Format('%s.Create failed',..)) ist keine Allokation.
    RhsLow := TDetectorUtils.BlankStringLiterals(LowerCase(N.TypeRef));
    if Pos('.create', RhsLow) = 0 then Continue;

    FieldLow := BareIdentPrefix(LhsLow);
    if FieldLow = '' then Continue;
    // Schon erfasst (Mehrfach-Allokation desselben Feldes in verschiedenen
    // Zweigen): nur die Zeile nachziehen, die Gates nicht erneut fahren.
    if Fields.IndexOf(FieldLow) >= 0 then
    begin
      if N.Line < Result then Result := N.Line;
      Continue;
    end;

    TypeLow := CreateCallTypeLow(RhsLow, Exact);
    // [G2] Werttyp-Factory: Records allokieren nichts Freigebbares.
    if IsKnownValueRecord(TypeLow) or IsUnitRecordType(UnitNode, TypeLow) then
      Continue;
    // [G3] Static-Factory mit Create-Suffix, deren Feld unit-weit nie
    // freigegeben wird -> kein besitzendes Heap-Feld.
    if (not Exact) and not BodyFreesField(UnitNode, FieldLow) then Continue;

    Fields.Add(FieldLow);
    if N.Line < Result then Result := N.Line;
  end;
end;

// [G1] True wenn ein Destruktor DERSELBEN Klasse in DIESER Unit alle
// allokierten Felder freigibt und keine der TP-Ausnahmen greift.
function DestructorCoversAllFields(Methods: TList<TAstNode>; Ctor: TAstNode;
  Fields: TList<string>): Boolean;
var
  ClassLow : string;
  Dtors    : TList<TAstNode>;
  N        : TAstNode;
  Fld      : string;
  Covered  : Boolean;
begin
  Result := False;
  ClassLow := OwnerTypeLow(Ctor.Name);
  if ClassLow = '' then Exit;

  Dtors := TList<TAstNode>.Create;
  try
    for N in Methods do
      if IsDestructorImpl(N) and HasBlockChild(N) and
         (OwnerTypeLow(N.Name) = ClassLow) then
        Dtors.Add(N);
    if Dtors.Count = 0 then Exit;   // (a) kein Destruktor -> Fund bleibt

    for Fld in Fields do
    begin
      Covered := False;
      for N in Dtors do
        if BodyFreesField(N, Fld) then
        begin
          Covered := True;
          Break;
        end;
      if not Covered then Exit;     // (b) Feld ungedeckt -> Fund bleibt
    end;

    // Alle Felder gedeckt - jetzt die beiden TP-Ausnahmen.
    for N in Dtors do
      for Fld in Fields do
        if DtorDerefsFieldUnguarded(N, Fld) then Exit;   // [G1a]
    if InheritedCreateAfterRaise(Ctor, Dtors) then Exit; // [G1b]

    Result := True;
  finally
    Dtors.Free;
  end;
end;

class procedure TLeakInConstructorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods         : TList<TAstNode>;
  M               : TAstNode;
  F               : TLeakFinding;
  Fields          : TList<string>;
  FirstCreateLine : Integer;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    Fields := TList<string>.Create;
    try
      for M in Methods do
      begin
        if not IsConstructorImpl(M) then Continue;
        if not HasBodyBlock(M) then Continue;
        if not HasRaise(M) then Continue;
        if HasProtectingTryExcept(M) then Continue;

        Fields.Clear;
        FirstCreateLine := CollectAllocatedFields(UnitNode, M, Fields);
        if Fields.Count = 0 then Continue;
        // Validate-then-Allocate-Pattern: alle Raises VOR allen Field-Creates
        // -> raise feuert vor jeder Allocation -> nichts zum leaken.
        if not HasRaiseAtOrAfter(M, FirstCreateLine) then Continue;
        // [G1] Auto-Destroy raeumt den Exception-Pfad vollstaendig auf.
        if DestructorCoversAllFields(Methods, M, Fields) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(M.Line);
        F.MissingVar :=
          'Constructor allocates fields and raises without try/except - ' +
          'partially-initialized fields leak on the exception path';
        F.SetKind(fkLeakInConstructor);
        Results.Add(F);
      end;
    finally
      Fields.Free;
    end;
  finally
    Methods.Free;
  end;
end;

end.
