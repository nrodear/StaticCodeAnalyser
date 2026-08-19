unit uSelfAssignment;

// Detektor: `x := x;` - LHS textuell identisch zur RHS, und das Ziel ist
// beweisbar ein SPEICHER-SLOT.
//
// Die frueher hier behauptete Quote ('in ~95 % aller Faelle ein
// Copy-Paste-Bug') ist am Realworld-Korpus widerlegt: der reine
// Textvergleich lag bei 73 % FP (Audit Stufe 2, 2026-08-16). Ursache war
// immer dieselbe - eine Zuweisung an eine PROPERTY ist kein No-op, sondern
// ein Setter-Aufruf mit Wirkung:
//   * Clamp-/Re-Apply-Setter (`TopLine := TopLine` klemmt gegen die
//     inzwischen veraenderte Fensterhoehe und speichert einen ANDEREN Wert)
//   * Setter, der abhaengigen Zustand nachzieht oder in einen zweiten
//     Speicher schreibt (`inherited FilterIndex := Value`)
//   * Parse-/Format-Roundtrip (`Text := Text` laeuft ueber SetTextStr:
//     Clear + Neu-Parsen)
//
// Erkennung: nkAssign mit `Normalize(Name) = Normalize(TypeRef)` UND
// aufgeloestem Ziel. Gemeldet wird nur:
//   * lokale Variable, Parameter, `Result`, Zuweisung an den Funktionsnamen
//   * ein in DERSELBEN Unit deklariertes Feld
// Geschwiegen wird bei Property-Zielen, bei indizierten Pfaden (`a[i]`)
// und bei Namen, die in dieser Unit nicht aufloesbar sind - dort ist
// 'kein No-op' ohne projektweites Wissen nicht widerlegbar. Der Preis
// sind bewusste False Negatives (geerbte Properties mit trivialem
// Setter); die Fehlrichtung ist die harmlose.
//
// W2-Schaerfung (2026-08-19, Audit-Vorschlag WirkungFpArbeit): ein
// Member-Pfad (`Pt.Y`, `R^.iType`) WIRD gemeldet, wenn die Wurzel ein
// beweisbarer Slot ist UND jedes Segment ein BLANKES Record-Feld -
// aufgeloest ueber TTypeResolver plus per-Unit-Record-Tabellen plus
// eine kuratierte RTL-Whitelist (TPoint.X/Y, TRect.Left..Bottom, ...).
// Die Feld-Bedingung ist nicht verhandelbar: TRectF.Height ist eine
// Record-PROPERTY mit Setter (Bottom := Top + Value) und bleibt still.
//
// Der Parser legt LHS in Name, RHS-Tokens als flachen String in TypeRef
// ab (uParser2.ParseCallOrAssign).

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TSelfAssignmentDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    // AUnitProps/AUnitFields: die in DIESER Unit deklarierten Property- bzw.
    // Feldnamen (lowercase, sortiert). Ohne sie bleibt nur die Aufloesung im
    // Routinen-Scope - der Rest wird dann konservativ verschwiegen. AnalyzeUnit
    // baut beide Mengen einmal je Unit.
    class procedure AnalyzeMethod(MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      AUnitProps: TStringList = nil; AUnitFields: TStringList = nil);
  end;

implementation

uses
  uTypeResolver;   // W2-Schaerfung: Wurzel-Typ + Record-Feld-Aufloesung

// noinspection-file CanBeStrictPrivate, GroupedDeclaration, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsWarning;

function IsWordCh(const C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

function Normalize(const S: string): string;
// Whitespace raus + lowercase, damit `Obj . Field` und `Obj.Field` gleich
// sind. ABER (Core-Audit 2026-07-17, SCA047): eine echte Wortgrenze - ein
// Space ZWISCHEN ZWEI Bezeichner-Zeichen, z.B. das Space in `not SaxMode` -
// MUSS als EIN Space erhalten bleiben. Sonst kollabiert
// `NotSaxMode := not SaxMode;` zu `notsaxmode` = `notsaxmode` und der Detektor
// meldet eine falsche Selbstzuweisung (betrifft auch and/or/div/mod/in/as/
// shl/shr/xor an Wortgrenzen). Der Parser (JoinTokInto) setzt Spaces ohnehin
// nur genau an solchen Wortgrenzen; an `.`/`[`/`(` faellt das Space weg, womit
// die Dot-Aequivalenz (`Obj . Field` = `Obj.Field`) erhalten bleibt.
var
  i   : Integer;
  C   : Char;
  Nxt : Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    C := S[i];
    if C > ' ' then
    begin
      Result := Result + LowerCase(C);
      Inc(i);
    end
    else
    begin
      // Whitespace-Lauf ueberspringen; nur wenn er zwei Ident-Zeichen trennt,
      // ein einzelnes Space als Wortgrenze setzen.
      Nxt := i;
      while (Nxt <= Length(S)) and (S[Nxt] <= ' ') do
        Inc(Nxt);
      if (Result <> '') and (Nxt <= Length(S)) and
         IsWordCh(Result[Length(Result)]) and IsWordCh(S[Nxt]) then
        Result := Result + ' ';
      i := Nxt;
    end;
  end;
end;

// --- Zielaufloesung (FP-Audit Stufe 2, 2026-08-16) --------------------------
// Bis hierher war der Textvergleich die EINZIGE Bedingung des Detektors -
// daran haengen alle drei belegten FP-Klassen. Die folgenden Helfer
// beantworten die eine Frage, die der Vergleich nicht stellt: bezeichnet die
// linke Seite einen Speicher-Slot oder einen Setter-Aufruf?

function StripSelfPrefix(const ANormLhs: string): string;
// 'Self.BkColor' ist derselbe Zugriff wie 'BkColor' - das Praefix darf die
// Klassifikation nicht in den Member-Pfad-Zweig kippen.
begin
  Result := ANormLhs;
  if Result.StartsWith('self.') then
  begin
    Result := Copy(Result, Length('self.') + 1, MaxInt);
  end;
end;

function HasMemberPath(const ANormLhs: string): Boolean;
// '.', '^' oder '[' im Ziel: der eigentliche Schreibzugriff ist das LETZTE
// Pfadsegment, und ob das ein Feld oder eine Property ist, haengt am Typ des
// Praefixes - ohne Cross-Unit-Typaufloesung nicht bestimmbar. Bewusst
// pauschal: der Preis sind Record-Feld-No-ops (Pt.Y, R.Bottom), der Ertrag
// sind die Property-Retrigger (FCalcPanel.DisplayValue, Item.Visible).
begin
  Result := (Pos('.', ANormLhs) > 0) or (Pos('^', ANormLhs) > 0) or
            (Pos('[', ANormLhs) > 0);
end;

procedure CollectRoutineScope(MethodNode: TAstNode; ATarget: TStringList);
// Alles, was in dieser Routine beweisbar ein Slot ist: Locals (inklusive
// Inline-var und for-in-Laufvariable), Parameter, Result und der
// Funktionsname (klassische Ergebniszuweisung).
var
  N     : TAstNode;
  Nm    : string;
  p     : Integer;
begin
  ATarget.Add('result');
  Nm := TDetectorUtils.UnqualifiedNameLastLower(MethodNode.Name);
  if Nm <> '' then
  begin
    ATarget.Add(Nm);
  end;
  // FindAllRef: rein lesende Iteration ueber die Cache-Liste, kein Copy und
  // KEIN Free (Kontrakt siehe uAstNode).
  for N in MethodNode.FindAllRef(nkLocalVar) do
  begin
    ATarget.Add(LowerCase(Trim(N.Name)));
  end;
  for N in MethodNode.FindAllRef(nkParam) do
  begin
    // Der Parser praefigiert den Modifier ('const X', 'var Y', 'out Z').
    Nm := LowerCase(Trim(N.Name));
    p  := LastDelimiter(' ', Nm);
    if p > 0 then
    begin
      Nm := Copy(Nm, p + 1, MaxInt);
    end;
    if Nm <> '' then
    begin
      ATarget.Add(Nm);
    end;
  end;
end;

function TargetIsProvableSlot(const ANormLhs: string; ALine: Integer;
  const ACtx: TMemberCtx): Boolean;
var
  Nm : string;
begin
  Nm := StripSelfPrefix(ANormLhs);
  if HasMemberPath(Nm) then
  begin
    // W2-Schaerfung: nicht mehr pauschal aus - wenn der ganze Pfad
    // beweisbar aus Wurzel-Slot + blanken Record-Feldern besteht, ist
    // die Zuweisung ein echtes No-op. Ohne Resolver (Kompat-Einstieg
    // AnalyzeMethod) bleibt das Verhalten von vor 2026-08-19.
    if not Assigned(ACtx.Resolver) then Exit(False);
    Exit(MemberPathIsPlainRecordFields(Nm, ALine, ACtx));
  end;
  if Assigned(ACtx.Scope) and (ACtx.Scope.IndexOf(Nm) >= 0) then Exit(True);
  // Property gewinnt bei Namensgleichheit mit einem Feld einer anderen
  // Klasse - bewusst konservativ, jede Property-Zuweisung kann einen Setter
  // fahren.
  if Assigned(ACtx.UnitProps) and (ACtx.UnitProps.IndexOf(Nm) >= 0) then Exit(False);
  if Assigned(ACtx.UnitFields) and (ACtx.UnitFields.IndexOf(Nm) >= 0) then Exit(True);
  // In dieser Unit nicht deklariert: geerbtes oder fremdes Member. Ohne
  // Cross-Unit-Wissen ist 'kein No-op' nicht widerlegbar -> schweigen.
  Result := False;
end;

function CollectUnitMemberNames(UnitNode: TAstNode;
  AKind: TNodeKind): TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Sorted        := True;
  Result.Duplicates    := dupIgnore;
  for var N in UnitNode.FindAllRef(AKind) do   // non-owning, kein Free
  begin
    Result.Add(LowerCase(Trim(N.Name)));
  end;
end;

// --- W2-Schaerfung: member-genaue Pfad-Aufloesung (2026-08-19) --------------
// Der Audit-Vorschlag woertlich: Member-Pfad nicht pauschal verwerfen,
// wenn die Wurzel im Routinen-Scope oder in den Unit-Feldern aufloesbar
// ist UND alle Segmente auf blanke Record-Felder zeigen. Traeger:

type
  TMemberCtx = record
    Resolver   : TTypeResolver;                  // Ident -> Typ (scope-genau); nil = Member-Pfade aus
    RecMembers : TDictionary<string, string>;    // 'rec.feld' -> Feldtyp (bare, lower; '' = Skalar)
    RecProps   : TDictionary<string, Byte>;      // 'rec.prop' existiert
    RecNames   : TDictionary<string, Byte>;      // Records DIESER Unit
    PtrAlias   : TDictionary<string, string>;    // 'palias' -> Zieltyp ('^'-Aliase)
    // Aufloesungs-Umgebung, gebuendelt statt als Parameter-Schwanz
    // (LongParamList-Regel): Unit-Mengen einmal je Unit, Scope wird je
    // Methode von DoAnalyzeMethod gesetzt (Ctx ist ein Stack-Record der
    // AnalyzeUnit-Instanz - kein geteilter Zustand zwischen Units).
    UnitProps  : TStringList;
    UnitFields : TStringList;
    Scope      : TStringList;
  end;
  PMemberCtx = ^TMemberCtx;

const
  // Kuratierte RTL-/Winapi-Records, deren gelistete Member BLANKE Felder
  // sind (kein Setter). Bewusst NICHT gelistet: TRect(F).Width/Height/
  // TopLeft/... - das sind Properties mit Settern; TRectF.Height schreibt
  // Bottom (der Alcinoe-Fall aus dem Audit bleibt damit still).
  RTL_RECORD_FIELDS: array[0..17] of string = (
    'tpoint.x', 'tpoint.y', 'tpointf.x', 'tpointf.y',
    'tcoord.x', 'tcoord.y', 'tsize.cx', 'tsize.cy',
    'trect.left', 'trect.top', 'trect.right', 'trect.bottom',
    'trectf.left', 'trectf.top', 'trectf.right', 'trectf.bottom',
    'tagenhmetarecord.itype', 'tagenhmetarecord.nsize');
  RTL_RECORD_NAMES: array[0..6] of string = (
    'tpoint', 'tpointf', 'tcoord', 'tsize', 'trect', 'trectf',
    'tagenhmetarecord');
  // Pointer-Aliase der gelisteten Records (der mormot-Fall lauft ueber
  // einen Parameter 'R: PEnhMetaRecord' und dereferenziert mit '^').
  RTL_PTR_ALIAS: array[0..4, 0..1] of string = (
    ('ppoint', 'tpoint'), ('prect', 'trect'), ('psize', 'tsize'),
    ('pcoord', 'tcoord'), ('penhmetarecord', 'tagenhmetarecord'));

function RtlRecordName(const ATypeLow: string): Boolean;
var
  i : Integer;
begin
  for i := Low(RTL_RECORD_NAMES) to High(RTL_RECORD_NAMES) do
    if RTL_RECORD_NAMES[i] = ATypeLow then Exit(True);
  Result := False;
end;

function RtlRecordField(const AKeyLow: string): Boolean;
var
  i : Integer;
begin
  for i := Low(RTL_RECORD_FIELDS) to High(RTL_RECORD_FIELDS) do
    if RTL_RECORD_FIELDS[i] = AKeyLow then Exit(True);
  Result := False;
end;

function ResolvePtrTarget(const ATypeLow: string;
  const ACtx: TMemberCtx): string;
// Zieltyp hinter einem '^'-Zugriff: erst die Aliase dieser Unit,
// dann die RTL-Tabelle. '' = nicht aufloesbar -> Aufrufer schweigt.
var
  i : Integer;
begin
  if ACtx.PtrAlias.TryGetValue(ATypeLow, Result) then Exit;
  for i := Low(RTL_PTR_ALIAS) to High(RTL_PTR_ALIAS) do
    if RTL_PTR_ALIAS[i, 0] = ATypeLow then Exit(RTL_PTR_ALIAS[i, 1]);
  Result := '';
end;

function IsPureIdent(const S: string): Boolean;
// Nur Bezeichner-Zeichen: Casts, Klammern oder Operatoren im Segment
// ('pemrsetpixelv(r)^') sind keine aufloesbaren Pfade -> schweigen.
var
  i : Integer;
begin
  if S = '' then Exit(False);
  for i := 1 to Length(S) do
    if not IsWordCh(S[i]) then Exit(False);
  Result := True;
end;

function StripDerefs(var ASeg: string): Integer;
// Zaehlt und entfernt abschliessende '^' ('r^' -> 'r', 1 Hop).
begin
  Result := 0;
  while (ASeg <> '') and (ASeg[Length(ASeg)] = '^') do
  begin
    SetLength(ASeg, Length(ASeg) - 1);
    Inc(Result);
  end;
end;

function ApplyDerefHops(var ACurType: string; AHops: Integer;
  const ACtx: TMemberCtx): Boolean;
// '^'-Hops ueber aufloesbare Pointer-Aliase; False = nicht aufloesbar.
var
  h : Integer;
begin
  Result := True;
  for h := 1 to AHops do
  begin
    ACurType := ResolvePtrTarget(ACurType, ACtx);
    if ACurType = '' then
    begin
      Exit(False);
    end;
  end;
end;

function ResolveRootType(const ARootSeg: string; ALine: Integer;
  const ACtx: TMemberCtx; out ACurType: string): Boolean;
// Wurzel: Slot-Beweis wie beim nackten Namen (Property verliert),
// dann Typ ueber den Resolver, dann eventuelle '^'-Hops.
var
  Seg  : string;
  Hops : Integer;
begin
  Result   := False;
  ACurType := '';
  Seg  := ARootSeg;
  Hops := StripDerefs(Seg);
  if not IsPureIdent(Seg) then
  begin
    Exit;
  end;
  if Assigned(ACtx.UnitProps) and (ACtx.UnitProps.IndexOf(Seg) >= 0) then
  begin
    Exit;
  end;
  if not ((Assigned(ACtx.Scope) and (ACtx.Scope.IndexOf(Seg) >= 0)) or
          (Assigned(ACtx.UnitFields) and
           (ACtx.UnitFields.IndexOf(Seg) >= 0))) then
  begin
    Exit;
  end;
  ACurType := ACtx.Resolver.ResolveTypeAt(Seg, ALine);
  Result   := (ACurType <> '') and ApplyDerefHops(ACurType, Hops, ACtx);
end;

function ResolveFieldSegment(const ASeg: string; var ACurType: string;
  const ACtx: TMemberCtx): Boolean;
// EIN Pfad-Segment: blankes Record-Feld eines bekannten Record-Typs
// (Unit-Tabelle oder RTL-Whitelist); Properties und Unbekanntes
// verlieren. ACurType wird zum Feldtyp ('' = Skalar/terminal).
var
  Seg  : string;
  Hops : Integer;
  Key  : string;
begin
  Result := False;
  Seg  := ASeg;
  Hops := StripDerefs(Seg);
  if not IsPureIdent(Seg) then
  begin
    Exit;
  end;
  Key := ACurType + '.' + Seg;
  if ACtx.RecNames.ContainsKey(ACurType) then
  begin
    // Record dieser Unit: Property-Segment verliert, unbekanntes
    // Segment (Helper, visibility-Ecke) verliert konservativ auch.
    if ACtx.RecProps.ContainsKey(Key) or
       not ACtx.RecMembers.TryGetValue(Key, ACurType) then
    begin
      Exit;
    end;
  end
  else if RtlRecordName(ACurType) then
  begin
    if not RtlRecordField(Key) then
    begin
      Exit;
    end;
    ACurType := '';   // gelistete RTL-Felder sind Skalare (terminal)
  end
  else
  begin
    Exit;   // Typ unbekannt (cross-unit, Klasse, Alias) -> schweigen
  end;
  Result := ApplyDerefHops(ACurType, Hops, ACtx);
end;

function MemberPathIsPlainRecordFields(const ANormLhs: string;
  ALine: Integer; const ACtx: TMemberCtx): Boolean;
// True nur, wenn der KOMPLETTE Pfad beweisbar ein Speicher-Slot ist:
// Wurzel = Local/Param/Result oder Unit-FELD (Property verliert), jedes
// weitere Segment ein blankes Record-Feld (Unit-Record oder RTL-Liste),
// '^' nur ueber aufloesbare Pointer-Aliase. Alles andere: False -
// die Fehlrichtung bleibt die harmlose.
var
  Segs    : TArray<string>;
  CurType : string;
  i       : Integer;
begin
  Result := False;
  if Pos('[', ANormLhs) > 0 then
  begin
    Exit;   // indiziert: bleibt pauschal aus
  end;
  Segs := ANormLhs.Split(['.']);
  if (Length(Segs) < 2) or
     not ResolveRootType(Trim(Segs[0]), ALine, ACtx, CurType) then
  begin
    Exit;
  end;
  for i := 1 to High(Segs) do
  begin
    if not ResolveFieldSegment(Trim(Segs[i]), CurType, ACtx) then
    begin
      Exit;
    end;
    if (i < High(Segs)) and (CurType = '') then
    begin
      Exit;   // Skalar mitten im Pfad: kein weiterer Hop moeglich
    end;
  end;
  Result := True;
end;

procedure BuildMemberCtx(UnitNode: TAstNode; var ACtx: TMemberCtx);
// Einmal je Unit: Records mit Feld-/Property-Mengen und '^'-Aliase aus
// dem AST. Feldtyp wird mitgefuehrt, damit Rec-in-Rec-Pfade hoppen.
var
  RN, C : TAstNode;
  RecNm : string;
  Tr    : string;
begin
  ACtx.Resolver   := TTypeResolver.Create(UnitNode);
  ACtx.RecMembers := TDictionary<string, string>.Create;
  ACtx.RecProps   := TDictionary<string, Byte>.Create;
  ACtx.RecNames   := TDictionary<string, Byte>.Create;
  ACtx.PtrAlias   := TDictionary<string, string>.Create;
  for RN in UnitNode.FindAllRef(nkRecord) do
  begin
    RecNm := LowerCase(Trim(RN.Name));
    if RecNm = '' then Continue;
    ACtx.RecNames.AddOrSetValue(RecNm, 0);
    // Methoden/Operatoren/nested Types tragen nichts zur
    // Feld-/Property-Unterscheidung bei - nur die zwei Arten zaehlen.
    for C in RN.Children do
    begin
      if C.Kind = nkField then
      begin
        ACtx.RecMembers.AddOrSetValue(
          RecNm + '.' + LowerCase(Trim(C.Name)),
          ReduceToBareTypeLow(C.TypeRef));
      end
      else if C.Kind = nkProperty then
      begin
        ACtx.RecProps.AddOrSetValue(
          RecNm + '.' + LowerCase(Trim(C.Name)), 0);
      end;
    end;
  end;
  for RN in UnitNode.FindAllRef(nkTypeAlias) do
  begin
    Tr := Trim(RN.TypeRef);
    if (Tr <> '') and (Tr[1] = '^') then
    begin
      ACtx.PtrAlias.AddOrSetValue(LowerCase(Trim(RN.Name)),
        ReduceToBareTypeLow(Copy(Tr, 2, MaxInt)));
    end;
  end;
end;

procedure FreeMemberCtx(var ACtx: TMemberCtx);
begin
  ACtx.Resolver.Free;
  ACtx.RecMembers.Free;
  ACtx.RecProps.Free;
  ACtx.RecNames.Free;
  ACtx.PtrAlias.Free;
end;

procedure DoAnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  var ACtx: TMemberCtx);
var
  Assigns : TList<TAstNode>;
  Scope   : TStringList;
  N       : TAstNode;
  Lhs, Rhs: string;
begin
  Assigns := nil;
  Scope   := nil;
  try
    Assigns := MethodNode.FindAll(nkAssign);
    for N in Assigns do
    begin
      Lhs := Normalize(N.Name);
      Rhs := Normalize(N.TypeRef);
      if (Lhs = '') or (Rhs = '') then Continue;
      if Lhs <> Rhs then Continue;
      // Scope erst JETZT aufbauen: Selbstzuweisungen sind selten, die zwei
      // zusaetzlichen Teilbaum-Laeufe je Routine waeren sonst reine Last.
      if not Assigned(Scope) then
      begin
        Scope := TStringList.Create;
        Scope.CaseSensitive := False;
        Scope.Sorted        := True;
        Scope.Duplicates    := dupIgnore;
        CollectRoutineScope(MethodNode, Scope);
        ACtx.Scope := Scope;   // je Methode; unten wieder geloest
      end;
      if not TargetIsProvableSlot(Lhs, N.Line, ACtx) then
        Continue;

      Results.Add(TLeakFinding.New(FileName, MethodNode.Name, N.Line,
        Format('Self-assignment: %s := %s (no-op or copy-paste)',
          [N.Name, N.TypeRef]),
        fkSelfAssignment));
    end;
  finally
    ACtx.Scope := nil;   // Scope gehoert dieser Methode, nicht dem Ctx
    Assigns.Free;
    Scope.Free;
  end;
end;

class procedure TSelfAssignmentDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AUnitProps: TStringList; AUnitFields: TStringList);
// Kompat-Einstieg OHNE Member-Kontext (Resolver = nil): Member-Pfade
// bleiben hier pauschal still (Stand vor 2026-08-19). Der scharfe Weg
// laeuft ueber AnalyzeUnit, das den Kontext einmal je Unit baut.
var
  Ctx : TMemberCtx;
begin
  Ctx := Default(TMemberCtx);
  Ctx.UnitProps  := AUnitProps;
  Ctx.UnitFields := AUnitFields;
  DoAnalyzeMethod(MethodNode, FileName, Results, Ctx);
end;

class procedure TSelfAssignmentDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Props   : TStringList;
  Fields  : TStringList;
  M       : TAstNode;
  Ctx     : TMemberCtx;
begin
  Methods := nil;
  Props   := nil;
  Fields  := nil;
  Ctx     := Default(TMemberCtx);
  try
    Props   := CollectUnitMemberNames(UnitNode, nkProperty);
    Fields  := CollectUnitMemberNames(UnitNode, nkField);
    BuildMemberCtx(UnitNode, Ctx);
    Ctx.UnitProps  := Props;
    Ctx.UnitFields := Fields;
    Methods := UnitNode.FindAll(nkMethod);
    for M in Methods do
    begin
      DoAnalyzeMethod(M, FileName, Results, Ctx);
    end;
  finally
    FreeMemberCtx(Ctx);
    Methods.Free;
    Fields.Free;
    Props.Free;
  end;
end;

end.
