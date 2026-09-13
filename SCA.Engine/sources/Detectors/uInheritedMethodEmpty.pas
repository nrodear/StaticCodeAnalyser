unit uInheritedMethodEmpty;

// Detektor: override-Methode deren gesamter Body nur `inherited;` ist.
//
// Pattern (Code-Smell):
//   procedure TFoo.Bar; override;
//   begin
//     inherited;   // <-- nichts weiter
//   end;
//
// Korrekt: Override komplett LOESCHEN. Wenn die abgeleitete Klasse keine
// eigene Logik hat, ist das Override nur Dispatch-Slot-Verbrauch ohne
// Mehrwert. Der Compiler ruft die Parent-Methode ohnehin direkt.
//
// Folge:
//   * VMT-Slot-Verbrauch ohne Gegenleistung
//   * Ein Reader denkt "da steht ein Override, also passiert hier etwas
//     Wichtiges" - liest den Code, sieht aber nur den Bypass. Verlangsamt
//     Code-Reviews.
//   * Beim Refactoring der Parent-Klasse muss man trotzdem alle leeren
//     Overrides anschauen ob noch sie noch Sinn machen - obwohl sie
//     nichts tun.
//
// Erkennung (AST-basiert, single-method):
//   * MNode.TypeRef enthaelt ';override' (case-insensitive)
//   * Skip bodyless (abstract/forward/external) - das sind keine
//     Definitionen.
//   * Nicht-Param-Children des MNode bilden den Body. Wenn genau EIN
//     Body-Statement existiert UND das ist nkInherited mit leerem
//     Argument-Namen ODER mit Argument-Name == Method-Name -> Finding.
//
// Bewusst NICHT Finding:
//   * `inherited;` plus weitere Statements (Method tut auch etwas Eigenes).
//   * `inherited Foo(SomethingDifferent);` (rufed bewusst andere Variante
//     des Parent auf - das ist ein Use-Case fuer Method-Hijacking).
//   * Leerer Body (kein inherited) - faengt EmptyRoutineCheck.
//
// Sonar-Pendant: InheritedMethodWithNoCodeCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   InheritedMethodWithNoCodeCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInheritedMethodEmptyDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeStrictPrivate, CyclomaticComplexity, LongMethod, MultipleExit, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;  // UnqualifiedNameLast (Restschulden-Audit 2026-07-26)

// Hat das Method-TypeRef ';override' als Direktive?
function IsOverride(const TypeRef: string): Boolean;
begin
  Result := Pos(';override', LowerCase(TypeRef)) > 0;
end;

// Bodyless = abstract / forward / external / dispid - keine Implementation.
function IsBodyless(const TypeRef: string): Boolean;
begin
  // Voll-Review 2026-09-12: zentral (Method-TypeRef-Vertragssektion
  // in uDetectorUtils). Wrapper bleibt fuer die lokalen Aufrufer.
  Result := TDetectorUtils.IsBodylessTypeRef(TypeRef);
end;

// Restschulden-Audit 2026-07-26: lokale UnqualifiedName-Kopie entfernt -
// jetzt TDetectorUtils.UnqualifiedNameLast (war in 8 Detektoren dupliziert,
// eine Kopie mit abweichender Semantik). Verhalten hier unveraendert.

// True wenn die Argumentliste des inherited-Aufrufs die Parameter der
// Methode EXAKT 1:1 durchreicht: gleiche Anzahl, gleiche Reihenfolge,
// jedes Argument ist der pure Parameter-Name (wie das Sonar-Pendant
// InheritedMethodWithNoCodeCheck).
//
// Voll-Review 2026-09-12 (Major 71): vorher wurde die Argumentliste
// komplett IGNORIERT - `inherited Create(nil)` (reparentet auf nil)
// und `inherited SetName(Trim(S))` (transformiert das Argument)
// bekamen die Empfehlung 'remove the override entirely'; wer ihr
// folgt, aendert das Verhalten. Ohne Klammerteil (`inherited Create;`)
// bleibt der Vertrag des Vorgaengers unveraendert bestehen.
//
// nkParam.Name traegt den Modifier als Praefix ('const S') - fuer den
// Vergleich zaehlt das letzte Leerraum-getrennte Wort.
function ArgsSindExakteDurchreichung(MethodNode: TAstNode;
  const InheritArg: string): Boolean;
var
  OpenP, CloseP, i, k : Integer;
  Args                : TArray<string>;
  ParamNames          : TList<string>;
  Child               : TAstNode;
  PName               : string;
  SpacePos            : Integer;
begin
  Result := False;
  OpenP := Pos('(', InheritArg);
  if OpenP = 0 then Exit(True);   // kein Klammerteil: Vorgaenger-Vertrag
  CloseP := Length(InheritArg);
  while (CloseP > OpenP) and (InheritArg[CloseP] <> ')') do Dec(CloseP);
  if CloseP <= OpenP then Exit;   // unbalanciert - konservativ kein Fund

  ParamNames := TList<string>.Create;
  try
    for i := 0 to MethodNode.Children.Count - 1 do
    begin
      Child := MethodNode.Children[i];
      if Child.Kind <> nkParam then Continue;
      PName := Child.Name;
      SpacePos := LastDelimiter(' ', PName);
      if SpacePos > 0 then
        PName := Copy(PName, SpacePos + 1, MaxInt);
      ParamNames.Add(PName);
    end;

    Args := TDetectorUtils.SplitTopLevelArgs(
      Copy(InheritArg, OpenP + 1, CloseP - OpenP - 1));
    // 'Destroy()' liefert genau ein leeres Teil - das ist die leere
    // Argumentliste, keine Ein-Argument-Liste.
    if (Length(Args) = 1) and (Trim(Args[0]) = '') then
      Exit(ParamNames.Count = 0);

    if Length(Args) <> ParamNames.Count then Exit;
    for k := 0 to High(Args) do
      if not SameText(Trim(Args[k]), ParamNames[k]) then Exit;
    Result := True;
  finally
    ParamNames.Free;
  end;
end;

// Liefert den ersten Identifier aus einem Call-Ausdruck.
// 'Foo' -> 'Foo'; 'Foo(args)' -> 'Foo'; '' -> ''.
function FirstIdent(const Expr: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(Expr) do
  begin
    case Expr[i] of
      'A'..'Z', 'a'..'z', '_', '0'..'9':
        Result := Result + Expr[i];
    else
      Exit;
    end;
  end;
end;

class procedure TInheritedMethodEmptyDetector.AnalyzeMethod(
  MethodNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  TypeRef     : string;
  i           : Integer;
  Child       : TAstNode;
  BodyCount   : Integer;
  TheOnly     : TAstNode;
  InheritArg  : string;
  MethShort   : string;
  F           : TLeakFinding;
begin
  TypeRef := MethodNode.TypeRef;
  if not IsOverride(TypeRef) then Exit;
  if IsBodyless(TypeRef) then Exit;

  // Body-Statements zaehlen (alles ausser nkParam). Der Parser kapselt
  // `begin ... end` in ein nkBlock-Kind - wenn das das einzige Kind ist,
  // muessen wir EINE Ebene tiefer schauen, sonst sehen wir nkBlock statt
  // dem nkInherited darin. Audit V5 / 2026-05-30.
  BodyCount := 0;
  TheOnly   := nil;
  for i := 0 to MethodNode.Children.Count - 1 do
  begin
    Child := MethodNode.Children[i];
    if Child.Kind = nkParam then Continue;
    Inc(BodyCount);
    TheOnly := Child;
    if BodyCount > 1 then Break;  // mehr als 1 Statement -> nicht relevant
  end;

  // Single-Block-Unwrap: wenn das einzige non-Param-Kind ein nkBlock ist,
  // gehen wir eine Ebene tiefer und zaehlen dort.
  if (BodyCount = 1) and Assigned(TheOnly) and (TheOnly.Kind = nkBlock) then
  begin
    var Block := TheOnly;
    BodyCount := 0;
    TheOnly   := nil;
    for i := 0 to Block.Children.Count - 1 do
    begin
      Child := Block.Children[i];
      if Child.Kind = nkParam then Continue;
      Inc(BodyCount);
      TheOnly := Child;
      if BodyCount > 1 then Break;
    end;
  end;

  if BodyCount <> 1 then Exit;
  if TheOnly.Kind <> nkInherited then Exit;

  // inherited mit leerem Argument ODER inherited <selber Method-Name>
  // mit EXAKT durchgereichten Argumenten: beides bedeutet "nur Bypass".
  // Ein anderer NAME meint eine andere Methode; TRANSFORMIERTE
  // Argumente (`inherited Create(nil)`, `inherited SetName(Trim(S))`)
  // sind seit Voll-Review 2026-09-12 (Major 71) ebenfalls KEIN Bypass -
  // die Empfehlung 'remove the override' wuerde dort Verhalten aendern.
  InheritArg := Trim(TheOnly.Name);
  MethShort  := TDetectorUtils.UnqualifiedNameLast(MethodNode.Name);
  if InheritArg <> '' then
  begin
    var ArgIdent := FirstIdent(InheritArg);
    if not SameText(ArgIdent, MethShort) then Exit;
    if not ArgsSindExakteDurchreichung(MethodNode, InheritArg) then Exit;
  end;

  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethodNode.Name;
  F.LineNumber := IntToStr(MethodNode.Line);
  F.MissingVar := Format(
    'Override %s contains only "inherited" - remove the override entirely',
    [MethShort]);
  F.SetKind(fkInheritedMethodEmpty);
  Results.Add(F);
end;

class procedure TInheritedMethodEmptyDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
