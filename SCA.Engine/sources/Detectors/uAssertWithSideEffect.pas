unit uAssertWithSideEffect;

// Detektor: Assert(SomeCall) wo SomeCall einen Seiteneffekt hat.
//
// Hintergrund: der Compiler entfernt Assert-Aufrufe komplett in Release-
// Builds (kein DCC_Assertions). Damit verschwindet auch der Side-Effect
// des Arguments - wenn der Side-Effect wichtig war (Init, State-Change),
// kracht's nur im Release-Build.
//
// Pattern:
//   Assert(InitializeSubsystem);   // BUG: keine Init in Release
//   Assert(Counter.Increment);     // BUG: kein Increment in Release
//
// Erkennung (AST):
//   * nkCall mit Name='Assert' (qualifier-strip: System.Assert zaehlt auch).
//   * Pruefen ob das Argument (im TypeRef-String der nkCall) ein
//     Function-Call-Pattern enthaelt: `\b\w+\s*\(` AFTER dem oeffnenden
//     'Assert('. Heuristik: wenn das Argument nur ein Identifier/Vergleich
//     ohne Call ist (`Assert(x > 0)`), kein Side-Effect. Mit Call drin
//     ist's verdaechtig.
//
// Whitelist (Funktionen die KEINEN Side-Effect haben):
//   Length, High, Low, SizeOf, Assigned, Trim, UpperCase, LowerCase,
//   IntToStr, StrToInt, IsNumeric, Pos, Copy, Random (read-only RNG-call,
//   selber Det-Pfad), TryStrToXxx, Format, Concat.
//
// FP-Risiko: pure Funktionen die nicht in der Whitelist sind, werden
// als Side-Effect angesehen. Suppression-Marker bei FP. Severity Warning.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAssertWithSideEffectDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function ArgContainsCall(const Arg: string): Boolean; static;
  end;

implementation

uses
  System.RegularExpressions;

const
  // Whitelist pure-Funktion-Namen die KEINEN Side-Effect haben.
  // Lowercase fuer Vergleich.
  PURE_FUNCS : array[0..18] of string = (
    'length', 'high', 'low', 'sizeof', 'assigned',
    'trim', 'uppercase', 'lowercase',
    'inttostr', 'strtoint', 'strtointdef',
    'pos', 'copy', 'concat', 'format',
    'isnumeric', 'trystrtoint', 'trystrtofloat',
    'odd'
  );

class function TAssertWithSideEffectDetector.ArgContainsCall(
  const Arg: string): Boolean;
// True wenn Arg verdaechtig nach Side-Effect aussieht. BEIDE Pfade
// verlangen jetzt einen Side-Effect-Verb-Praefix am Funktions-Namen:
//   * Funktion-Call-Pattern `\b\w+\s*\(` dessen Name mit einem Mutations-
//     Verb beginnt (Init*, Setup*, Reset*, ...) und NICHT auf der
//     PURE_FUNCS-Whitelist steht, ODER
//   * Bare-Identifier (kein '(', kein Operator) mit selbem Verb-Praefix.
//     Hintergrund: `Assert(InitializeSubsystem)` ohne () wird vom
//     Parser als bare-identifier-arg ausgegeben - der Compiler ruft
//     trotzdem die Funktion.
//
// FP-Fix (Real-World 2026-06-21): vorher flaggte Pfad 1 JEDEN nicht-
// gewhitelisteten Call - reine Conversion-Funktionen (FloatToStr,
// DateToStr, VarToStr ... in Test-Asserts) wurden faelschlich gemeldet.
// Die Verb-Praefix-Gate eliminiert diese FP-Klasse; verbleibende FN
// (mutierender Call mit unverdaechtigem Namen) ist der akzeptierte
// Tradeoff.
const
  CALL_RE         = '\b(\w+)\s*\(';
  BARE_IDENT_RE   = '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*$';
  SIDE_EFFECT_RE  = '^(init|setup|teardown|reset|create|destroy|free|' +
                    'register|unregister|allocate|open|close|mutate|update|' +
                    'apply|commit|rollback|start|stop|increment|decrement)';
var
  M, BareM : TMatch;
  Name : string;
  P    : string;
  IsPure : Boolean;
begin
  Result := False;
  // Pfad 1: Funktion-Call dessen Name nach Mutation aussieht.
  for M in TRegEx.Matches(Arg, CALL_RE) do
  begin
    Name := LowerCase(M.Groups[1].Value);
    IsPure := False;
    for P in PURE_FUNCS do
      if Name = P then begin IsPure := True; Break; end;
    if (not IsPure) and TRegEx.IsMatch(Name, SIDE_EFFECT_RE) then
      Exit(True);
  end;
  // Pfad 2: bare-Identifier mit Side-Effect-Praefix.
  BareM := TRegEx.Match(Arg, BARE_IDENT_RE);
  if BareM.Success then
  begin
    Name := LowerCase(BareM.Groups[1].Value);
    if TRegEx.IsMatch(Name, SIDE_EFFECT_RE) then
      Exit(True);
  end;
end;

class procedure TAssertWithSideEffectDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Calls : TList<TAstNode>;
  N     : TAstNode;
  Bare  : string;
  DotP  : Integer;
  Arg   : string;
  ParenP, ParenE : Integer;
  F     : TLeakFinding;
begin
  Calls := UnitNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      // uParser2 packt die GANZE Call-Expression in nkCall.Name -
      // also `Assert(InitializeSubsystem)`, nicht nur `Assert`. Wir
      // pruefen auf das Identifier-Prefix bis zum '(' und matchen
      // dann das letzte Punkt-Segment fuer Qualifier-Toleranz.
      Bare := LowerCase(N.Name);
      ParenP := Pos('(', Bare);
      if ParenP <= 1 then Continue;
      // Identifier-Teil = alles vor dem '('
      Bare := Copy(Bare, 1, ParenP - 1);
      DotP := LastDelimiter('.', Bare);
      if DotP > 0 then Bare := Copy(Bare, DotP + 1, MaxInt);
      if Bare <> 'assert' then Continue;

      // Argument-String aus N.Name extrahieren (zwischen erstem '(' und
      // dem letzten ')').
      ParenP := Pos('(', N.Name);
      ParenE := LastDelimiter(')', N.Name);
      if (ParenP <= 0) or (ParenE <= ParenP) then Continue;
      Arg := Copy(N.Name, ParenP + 1, ParenE - ParenP - 1);

      if not ArgContainsCall(Arg) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := 'Assert argument contains a function call - the call ' +
                      'has a side effect that disappears in Release builds ' +
                      '(Assert is compiled out without DCC_Assertions). ' +
                      'Move the call outside Assert.';
      F.SetKind(fkAssertWithSideEffect);
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

end.
