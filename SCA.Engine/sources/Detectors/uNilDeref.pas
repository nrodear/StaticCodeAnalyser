unit uNilDeref;

// Detektor fuer potentielle Nil-Dereferenzierungen (Sonar-Regel #3).
//
// Erkennt Variablen, die explizit auf nil gesetzt werden und danach
// ohne zwischenzeitliche Neuzuweisung oder Guard-Pruefung mit einem
// Punkt-Zugriff (Methode/Property) verwendet werden.
//
// Erkannte Guards:
//   - obj := TFoo.Create;        (Neuzuweisung)
//   - if Assigned(obj) then ...  (in If-Bedingung)
//   - if obj <> nil then ...     (in If-Bedingung)
//   - if obj = nil then Exit;    (Early-Exit-Guard)
//   - .Free / .Destroy           (TObject.Free ist nil-safe)
//   - Foo(obj) / x := Foo(obj)   (Uebergabe als Argument = potentielle
//                                 var/out-Zuweisung, beendet nil-Zustand)
//   - for obj in ... / for obj := (Schleife weist obj zu)
//
// Nicht erkannt (bewusst):
//   - obj.field := nil           (Cleanup-Muster)
//   - Selbstreferenzen (Self.X)

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TNilDerefDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Pruefung ob ein If-Block der Methode einen Guard fuer VarLow enthaelt
    class function HasGuardingIf(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
    // Erkennt ob ein Call ein nil-sicherer Aufruf ist (.Free, .Destroy)
    class function IsNilSafeCall(const CallNameLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - VarLow kommt in TextLow als
    // eigenstaendiges Argument nach einer oeffnenden Klammer vor
    class function HasBareArgUse(const TextLow,
      VarLow: string): Boolean; static;
    // FP-Gate (2026-07-04): out-param-assign - Uebergabe als Argument
    // zwischen nil-Zuweisung und Zugriff zaehlt als Zuweisung
    class function IsPassedAsArgBetween(MethodNode: TAstNode;
      Calls, Assigns: TList<TAstNode>;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
    // FP-Gate (2026-07-04): for-in-loop-assign - Schleifenkopf weist VarLow zu
    class function IsForLoopAssigned(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
  end;

implementation

// noinspection-file CanBeStrictPrivate, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, LongMethod, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{ Hilfsfunktion: prueft ob in der Bedingung ein Guard fuer varname steht.
  Verwendet TDetectorUtils.ContainsWholeWordLower fuer korrekte Wortgrenzen -
  vorher matchten 'assigned MyVar' faelschlich auch 'assigned MyVarOld'. }
function CondHasGuard(const CondLow, VarLow: string): Boolean;
const
  PATTERNS: array[0..7] of string = (
    // Assigned-Varianten
    'assigned(%s)',
    'assigned( %s )',
    'assigned (%s)',
    'assigned ( %s )',
    'assigned %s',
    // Vergleich mit nil (links und rechts)
    '%s <> nil',
    '%s<>nil',
    'nil <> %s'
  );
var
  Pat: string;
begin
  Result := False;
  for Pat in PATTERNS do
    if TDetectorUtils.ContainsWholeWordLower(Format(Pat, [VarLow]), CondLow) then
      Exit(True);
  // Sonderfall ohne Whitespaces - 'nil<>' braucht keine eigene Wortgrenze rechts
  // weil VarLow direkt folgt; ContainsWholeWord prueft trotzdem den Rand am Ende.
  if TDetectorUtils.ContainsWholeWordLower('nil<>' + VarLow, CondLow) then
    Result := True;
end;

class function TNilDerefDetector.HasGuardingIf(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer): Boolean;
var
  Ifs : TList<TAstNode>;
  IfN : TAstNode;
  Low : string;
begin
  Result := False;
  Ifs := MethodNode.FindAll(nkIfStmt);
  try
    for IfN in Ifs do
    begin
      // Nur If-Statements zwischen den relevanten Zeilen
      if IfN.Line < AfterLine then Continue;
      if IfN.Line > BeforeLine then Continue;
      Low := IfN.TypeRef.ToLower;
      if Low = '' then Continue;
      if CondHasGuard(Low, VarLow) then Exit(True);
    end;
  finally
    Ifs.Free;
  end;
end;

class function TNilDerefDetector.IsNilSafeCall(
  const CallNameLow, VarLow: string): Boolean;
// .Free und .Destroy sind nil-sicher (TObject.Free prueft Self <> nil)
// FreeAndNil(varname) ist ebenfalls nil-sicher.
// Wortgrenzen wichtig: 'x.free' soll NICHT 'x.freedom' matchen.
begin
  Result :=
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.free',         CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.destroy',      CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil(' + VarLow,   CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil( ' + VarLow,  CallNameLow);
end;

{ FP-Gate (2026-07-04): out-param-assign - prueft ob VarLow in TextLow als
  eigenstaendiges Argument vorkommt: nach der ersten oeffnenden Klammer, mit
  Identifier-Wortgrenzen und OHNE angrenzenden Punkt (x.var / var.y sind
  Member-Zugriffe, keine Argument-Uebergabe). String-Literale werden vorab
  entfernt, damit 'Log(''lst kaputt'')' nicht als Uebergabe von lst zaehlt
  (Real-World-Audit 2026-07-04, z.B. LoadJson(l, ...) in test.core.data). }
class function TNilDerefDetector.HasBareArgUse(const TextLow,
  VarLow: string): Boolean;
var
  Code   : string;
  ParenP : Integer;
  p, L   : Integer;
  PrevCh : Char;
  NextCh : Char;
begin
  Result := False;
  if (VarLow = '') or (TextLow = '') then Exit;
  Code   := TDetectorUtils.StripStringLiterals(TextLow);
  ParenP := Pos('(', Code);
  if ParenP = 0 then Exit; // ohne Klammer keine Argumentliste
  L := Length(VarLow);
  p := PosEx(VarLow, Code, ParenP + 1);
  while p > 0 do
  begin
    if p > 1 then PrevCh := Code[p - 1] else PrevCh := #0;
    if p + L <= Length(Code) then NextCh := Code[p + L] else NextCh := #0;
    // Wortgrenzen beidseitig; '.' zusaetzlich ausgeschlossen, damit weder
    // 'rec.varname' noch 'varname.prop' (Deref!) als Uebergabe gelten.
    if (not CharInSet(PrevCh, ['a'..'z', '0'..'9', '_', '.'])) and
       (not CharInSet(NextCh, ['a'..'z', '0'..'9', '_', '.'])) then
      Exit(True);
    p := PosEx(VarLow, Code, p + 1);
  end;
end;

{ FP-Gate (2026-07-04): out-param-assign - jede Uebergabe der Variable als
  blankes Argument an einen Aufruf zwischen nil-Zuweisung und Punkt-Zugriff
  zaehlt als Zuweisung (var/out-Parameter wie LoadJson(l, ...) oder
  TInterfaceStub.Create(TypeInfo(...), I) fuellen die Variable). Bewusst
  konservativ-grosszuegig: SCA008 hatte im Real-World-Audit 2026-07-04
  0 TPs bei 21 FPs, davon 7 aus genau diesem Muster. Gescannt werden
  sowohl Call-Statements als auch RHS-Ausdruecke fremder Zuweisungen
  (Stub := TFoo.Create(..., I)). FreeAndNil ist ausgenommen - es laesst
  die Variable nil. }
class function TNilDerefDetector.IsPassedAsArgBetween(MethodNode: TAstNode;
  Calls, Assigns: TList<TAstNode>; const VarLow: string;
  AfterLine, BeforeLine: Integer): Boolean;
var
  N       : TAstNode;
  TextLow : string;
  Kind    : TNodeKind;
  Conds   : TList<TAstNode>;
begin
  Result := False;
  for N in Calls do
  begin
    if N.Line <= AfterLine then Continue;
    if N.Line >= BeforeLine then Continue;
    TextLow := N.Name.ToLower;
    // FreeAndNil(x) setzt x auf nil - beendet den nil-Zustand NICHT
    if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
      Continue;
    if HasBareArgUse(TextLow, VarLow) then Exit(True);
  end;
  for N in Assigns do
  begin
    if N.Line <= AfterLine then Continue;
    if N.Line >= BeforeLine then Continue;
    // Neuzuweisungen an die Variable selbst behandelt der Reassigned-Check
    if N.Name.ToLower = VarLow then Continue;
    TextLow := N.TypeRef.ToLower;
    if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
      Continue;
    if HasBareArgUse(TextLow, VarLow) then Exit(True);
  end;

  // FP-Gate (Real-World-FP-Audit 2026-07-10): out-param-Finder-Aufrufe in
  // BEDINGUNGEN ('if FindProcessorByURLSegment(..., lProcessor) then') sind
  // keine nkCall-Knoten, sondern TypeRef-Strings des nkIfStmt/nkWhileStmt/
  // nkCaseStmt. Der Deref steht dann im if-true-Zweig -> die Variable IST vom
  // Finder gefuellt. Dominante SCA008-FP-Klasse 'out-param-assignment-guarded'.
  if MethodNode <> nil then
    for Kind in [nkIfStmt, nkWhileStmt, nkCaseStmt] do
    begin
      Conds := MethodNode.FindAll(Kind);
      try
        for N in Conds do
        begin
          if N.Line <= AfterLine then Continue;
          if N.Line >= BeforeLine then Continue;
          TextLow := N.TypeRef.ToLower;
          if TDetectorUtils.ContainsWholeWordLower('freeandnil', TextLow) then
            Continue;
          if HasBareArgUse(TextLow, VarLow) then Exit(True);
        end;
      finally
        Conds.Free;
      end;
    end;
end;

{ FP-Gate (2026-07-04): for-in-loop-assign - 'for X in ...' weist X bei
  jedem Durchlauf zu, 'for X := a to b' ebenso. Der Header steht seit
  ParseForStmt als Token-Join in TypeRef ('x in <expr>' / 'x := a to b').
  nil-Inits vor solchen Schleifen dienen typisch nur dem except-Handler
  (Real-World-Audit 2026-07-04, z.B. MVCFramework.Serializer.URLEncoded).
  Konservativ: auch ein Deref NACH der Schleife wird unterdrueckt (leere
  Collection waere der einzige Restfall - 0 TPs auf dem Korpus). }
class function TNilDerefDetector.IsForLoopAssigned(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer): Boolean;
var
  Fors : TList<TAstNode>;
  FN   : TAstNode;
  Head : string;
begin
  Result := False;
  Fors := MethodNode.FindAll(nkForStmt);
  try
    for FN in Fors do
    begin
      if FN.Line <= AfterLine then Continue;
      if FN.Line > BeforeLine then Continue; // Deref darf im Loop-Body liegen
      Head := FN.TypeRef.ToLower;
      if Head.StartsWith(VarLow + ' in ') or
         Head.StartsWith(VarLow + ' := ') then
        Exit(True);
    end;
  finally
    Fors.Free;
  end;
end;

class procedure TNilDerefDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  NA      : TAstNode;
  VarLow  : string;
  F       : TLeakFinding;
begin
  Assigns := nil;
  Calls   := nil;
  try
    Assigns := MethodNode.FindAll(nkAssign);
    Calls   := MethodNode.FindAll(nkCall);
    for NA in Assigns do
    begin
      // Nur direkte nil-Zuweisungen: 'varname := nil'
      if NA.TypeRef.ToLower <> 'nil' then Continue;
      // Feldwerte (obj.field := nil) ueberspringen – Cleanup-Muster
      if Pos('.', NA.Name) > 0 then Continue;

      VarLow := NA.Name.ToLower;
      if VarLow = '' then Continue;
      // Self oder Result als Variablenname ueberspringen
      if (VarLow = 'self') or (VarLow = 'result') then Continue;

      for var C in Calls do
      begin
        if C.Line <= NA.Line then Continue;

        var NameLow := C.Name.ToLower;
        // Punkt-Zugriff 'varname.' im Call-Namen?
        // Wortgrenze pruefen: muss am Anfang oder nach Nicht-Bezeichner stehen
        var p := Pos(VarLow + '.', NameLow);
        if p = 0 then Continue;
        if p > 1 then
        begin
          var Prev := NameLow[p - 1];
          if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
        end;

        // .Free / .Destroy sind nil-sicher
        if IsNilSafeCall(NameLow, VarLow) then Continue;

        // Neuzuweisung zwischen nil und Zugriff?
        var Reassigned := False;
        for var A in Assigns do
        begin
          if A = NA then Continue;
          if A.Line <= NA.Line then Continue;
          if A.Line >= C.Line  then Break;
          if A.Name.ToLower <> VarLow then Continue;
          if A.TypeRef.ToLower <> 'nil' then
          begin
            Reassigned := True;
            Break;
          end;
        end;
        if Reassigned then Continue;

        // Guard via If-Bedingung zwischen nil und Zugriff?
        if HasGuardingIf(MethodNode, VarLow, NA.Line, C.Line) then Continue;

        // FP-Gate (2026-07-04): out-param-assign - Variable wurde zwischen
        // nil und Zugriff als Argument uebergeben (var/out-Zuweisung)?
        if IsPassedAsArgBetween(MethodNode, Calls, Assigns, VarLow, NA.Line, C.Line) then
          Continue;

        // FP-Gate (2026-07-04): for-in-loop-assign - Variable ist
        // Schleifenvariable eines for zwischen nil und Zugriff?
        if IsForLoopAssigned(MethodNode, VarLow, NA.Line, C.Line) then
          Continue;

        // Befund: nil-Zuweisung ohne Guard, dann Punkt-Zugriff
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(C.Line);
        F.MissingVar := NA.Name + ' := nil (line ' + IntToStr(NA.Line) + ')';
        F.SetKind(fkNilDeref);
        Results.Add(F);
        Break; // Pro nil-Zuweisung nur einmal melden
      end;
    end;
  finally
    Assigns.Free;
    Calls.Free;
  end;
end;

class procedure TNilDerefDetector.AnalyzeUnit(UnitNode: TAstNode;
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
