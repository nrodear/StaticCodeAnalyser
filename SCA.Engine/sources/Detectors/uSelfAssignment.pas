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
// Geschwiegen wird bei Property-Zielen, bei Member-Pfaden (`a.b`, `p^.f`,
// `a[i]`) und bei Namen, die in dieser Unit nicht aufloesbar sind - dort
// ist 'kein No-op' ohne projektweites Wissen nicht widerlegbar. Der Preis
// sind bewusste False Negatives (geerbte Properties mit trivialem Setter,
// Record-Felder hinter einem Member-Pfad); die Fehlrichtung ist die
// harmlose.
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

function TargetIsProvableSlot(const ANormLhs: string;
  AScope, AUnitProps, AUnitFields: TStringList): Boolean;
var
  Nm : string;
begin
  Nm := StripSelfPrefix(ANormLhs);
  if HasMemberPath(Nm) then Exit(False);
  if Assigned(AScope) and (AScope.IndexOf(Nm) >= 0) then Exit(True);
  // Property gewinnt bei Namensgleichheit mit einem Feld einer anderen
  // Klasse - bewusst konservativ, jede Property-Zuweisung kann einen Setter
  // fahren.
  if Assigned(AUnitProps) and (AUnitProps.IndexOf(Nm) >= 0) then Exit(False);
  if Assigned(AUnitFields) and (AUnitFields.IndexOf(Nm) >= 0) then Exit(True);
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

class procedure TSelfAssignmentDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AUnitProps: TStringList; AUnitFields: TStringList);
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
      end;
      if not TargetIsProvableSlot(Lhs, Scope, AUnitProps, AUnitFields) then
        Continue;

      Results.Add(TLeakFinding.New(FileName, MethodNode.Name, N.Line,
        Format('Self-assignment: %s := %s (no-op or copy-paste)',
          [N.Name, N.TypeRef]),
        fkSelfAssignment));
    end;
  finally
    Assigns.Free;
    Scope.Free;
  end;
end;

class procedure TSelfAssignmentDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Props   : TStringList;
  Fields  : TStringList;
  M       : TAstNode;
begin
  Methods := nil;
  Props   := nil;
  Fields  := nil;
  try
    Props   := CollectUnitMemberNames(UnitNode, nkProperty);
    Fields  := CollectUnitMemberNames(UnitNode, nkField);
    Methods := UnitNode.FindAll(nkMethod);
    for M in Methods do
    begin
      AnalyzeMethod(M, FileName, Results, Props, Fields);
    end;
  finally
    Methods.Free;
    Fields.Free;
    Props.Free;
  end;
end;

end.
