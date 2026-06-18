unit uCommandInjection;

// Detektor: ShellExecute/CreateProcess/WinExec mit String-Konkatenation
// im Command-Argument (SCA163).
//
// Klassischer Command-Injection-Pfad in Delphi:
//   ShellExecute(0, 'open', PChar('cmd /c ' + UserInput), nil, nil, SW_SHOW);
// Wenn UserInput vom Nutzer kommt, kann er '... & rm -rf /' anhaengen.
//
// Heuristik (Confidence-Default fcLow, da ohne Taint-Tracking):
//   * AST-Walk auf nkCall.
//   * Methoden-Name endet (qualifiziert oder unqualifiziert) auf einer der
//     bekannten Shell-/Process-APIs:
//       ShellExecute, ShellExecuteEx, ShellExecuteW, ShellExecuteA,
//       CreateProcess, CreateProcessW, CreateProcessA,
//       WinExec
//   * Argument-Liste enthaelt mindestens ein '+' AUSSERHALB eines String-
//     Literals (also echter Concat-Operator, nicht Plus-Zeichen im Text).
//
// FP-/FN-Trade-off:
//   FP-Quelle: Konkatenation mit anderen Konstanten ist harmlos. Beispiel:
//     ShellExecute(0, 'open', PChar(EXE_DIR + '\app.exe'), ...);
//     Beide Operanden sind statisch -> in der Praxis kein Bug. Wir flaggen
//     trotzdem, weil ohne Symbol-Tabelle nicht entscheidbar ist. Confidence
//     fcLow markiert das nach aussen.
//   FN-Quelle: Variable wird VOR dem Call konkateniert
//     (cmd := 'cmd /c ' + UserInput; ShellExecute(0, ...PChar(cmd)...))
//     wird hier nicht erkannt - braucht Daten-Fluss-Analyse.
//
// Severity: lsError, Type: ftVulnerability (Schadenspotenzial = RCE).
// Confidence: fcLow -> Default-Profile zeigt es nur wenn FindingMinConfidence
//             auf fcLow gesetzt ist; im Standard-Profil (fcMedium) versteckt.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCommandInjectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // True wenn der Methoden-Name (vor erstem '(') auf eine der Shell-APIs
    // endet. Qualifizierte Aufrufe ('Winapi.ShellAPI.ShellExecute') matchen
    // genauso wie unqualifizierte ('ShellExecute').
    class function IsShellApiCall(const CallName: string;
      out ApiName: string): Boolean; static;
    // True wenn das Argument-Teil-String (nach erstem '(') mindestens ein
    // '+' enthaelt, das NICHT innerhalb eines '...'-Literals steht.
    class function HasConcatInArgs(const ArgsPart: string): Boolean; static;
    // 2026-06-18 (Audit_ErrorDetectors E-3 P1): Pseudo-Taint-Tracking.
    // Sammelt aus der Method alle nkAssign mit Concat-RHS - die LHS-
    // Identifier sind "tainted" (potenziell mit User-Input kontaminiert).
    // Bei Shell-API-Call ohne direkten Concat-Arg pruefen wir, ob ein
    // tainted Identifier als Argument durchgereicht wird.
    //   Vorher: nur ShellExecute('cmd ' + x) als FN-frei erkannt
    //   Jetzt:  c := 'cmd ' + x; ShellExecute(c)  - jetzt auch erkannt
    // Letztes Identifier-Segment (nach '.') wird als tainted-Key abgelegt.
    class procedure CollectTaintedVars(MethodNode: TAstNode;
      Tainted: TList<string>); static;
    // True wenn ein Identifier im ArgsPart mit irgendeinem Tainted-Eintrag
    // matcht. Identifier-Erkennung: \w+-Token ausserhalb String-Literalen.
    class function ArgsContainTaintedVar(const ArgsPart: string;
      Tainted: TList<string>): Boolean; static;
    // Liefert das letzte Identifier-Segment einer qualifizierten Name-
    // Expression: 'Self.FCmd' -> 'fcmd', 'Foo' -> 'foo'. Resultat ist
    // lowercase (case-insensitive Match in CollectTainted/ArgsContain).
    class function LastIdentSegment(const QualifiedName: string): string; static;
  end;

implementation

// noinspection-file CanBeClassMethod, CanBeStrictPrivate, ConsecutiveSection, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Wir matchen auf die WIN-API-Namen + Delphi-RTL-Pendants. Aufruf-Form ist
  // case-insensitive (Pascal). 2026-06-18 erweitert (Audit_ErrorDetectors
  // E-3 P1):
  //   * system / _popen / popen        - C-RTL-Pendants (Pascal-Bindings)
  //   * createprocessasuser            - elevated-Variante
  //   * jvcreateprocess                - JVCL-Wrapper
  //   * dsiexecuteandcapture           - OmniThreadLibrary
  //   * pythonexec / execstring        - TPythonEngine String-Eval (RCE!)
  SHELL_APIS: array[0..15] of string = (
    'shellexecute', 'shellexecuteex',
    'shellexecutea', 'shellexecutew',
    'createprocess', 'createprocessa', 'createprocessw',
    'createprocessasuser',
    'winexec',
    'system', '_popen', 'popen',
    'jvcreateprocess',
    'dsiexecuteandcapture',
    'pythonexec', 'execstring'
  );

class function TCommandInjectionDetector.IsShellApiCall(
  const CallName: string; out ApiName: string): Boolean;
// Wir lassen alles BIS zum ersten '(' als Methoden-Pfad uebrig und schauen
// ob das letzte Pfad-Segment einer Shell-API entspricht.
var
  Low      : string;
  LParen   : Integer;
  PathPart : string;
  DotPos   : Integer;
  LastSeg  : string;
  Api      : string;
begin
  Result  := False;
  ApiName := '';

  Low := LowerCase(CallName);
  LParen := Pos('(', Low);
  if LParen < 2 then Exit;  // kein '(' oder direkt am Anfang -> kein Call-Form

  PathPart := Copy(Low, 1, LParen - 1);

  // Letztes Segment nach '.'-Qualifier
  DotPos := -1;
  for var i := Length(PathPart) downto 1 do
    if PathPart[i] = '.' then begin DotPos := i; Break; end;
  if DotPos > 0 then
    LastSeg := Copy(PathPart, DotPos + 1, MaxInt)
  else
    LastSeg := PathPart;

  for Api in SHELL_APIS do
    if LastSeg = Api then
    begin
      ApiName := Api;
      Exit(True);
    end;
end;

class function TCommandInjectionDetector.HasConcatInArgs(
  const ArgsPart: string): Boolean;
// Walk Char-by-Char und tracke Apostroph-State. Pascal-Strings: ein
// Apostroph oeffnet/schliesst; '' (doppel-Apostroph) innerhalb eines
// Literals ist der Escape fuer ein einzelnes Apostroph - wir behandeln
// einen Apostroph-Toggle inklusive, dann checken wir gleich danach den
// naechsten Char: wenn auch Apostroph, ist es Escape -> wir toggeln zurueck.
//
// Ein '+' ausserhalb eines Literals = echter Concat-Operator.
var
  i, n   : Integer;
  InStr  : Boolean;
  C : Char;
begin
  Result := False;
  InStr  := False;
  i := 1;
  n := Length(ArgsPart);
  while i <= n do
  begin
    C := ArgsPart[i];
    if C = '''' then
    begin
      // Lookahead: '' im Literal-Modus ist Escape, kein End.
      if InStr and (i + 1 <= n) and (ArgsPart[i + 1] = '''') then
        Inc(i, 2)
      else
      begin
        InStr := not InStr;
        Inc(i);
      end;
      Continue;
    end;
    if (not InStr) and (C = '+') then Exit(True);
    Inc(i);
  end;
end;

class function TCommandInjectionDetector.LastIdentSegment(
  const QualifiedName: string): string;
var
  s : string;
  i : Integer;
begin
  s := Trim(QualifiedName);
  // Cut at first whitespace/bracket - LHS kann '.Foo := …' o.ä. nicht sein,
  // aber defensive.
  for i := 1 to Length(s) do
    if (s[i] <= ' ') or (s[i] = '[') or (s[i] = '(') then
    begin
      s := Copy(s, 1, i - 1);
      Break;
    end;
  // Letztes Segment nach '.'
  for i := Length(s) downto 1 do
    if s[i] = '.' then
    begin
      s := Copy(s, i + 1, MaxInt);
      Break;
    end;
  Result := LowerCase(s);
end;

class procedure TCommandInjectionDetector.CollectTaintedVars(
  MethodNode: TAstNode; Tainted: TList<string>);
var
  Assigns : TList<TAstNode>;
  N       : TAstNode;
  Key     : string;
begin
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      // RHS mit Concat? Dann LHS-Identifier als tainted markieren.
      if not HasConcatInArgs(N.TypeRef) then Continue;
      Key := LastIdentSegment(N.Name);
      if Key = '' then Continue;
      // Doppel-Eintraege akzeptiert - List.IndexOf ist O(N), bei typisch
      // wenigen Tainted-Vars pro Method (1-5) negligible.
      if Tainted.IndexOf(Key) < 0 then
        Tainted.Add(Key);
    end;
  finally
    Assigns.Free;
  end;
end;

class function TCommandInjectionDetector.ArgsContainTaintedVar(
  const ArgsPart: string; Tainted: TList<string>): Boolean;
// Scan: jeden Identifier (\w+) ausserhalb String-Literalen extrahieren
// und gegen Tainted-Set pruefen.
var
  i, n   : Integer;
  InStr  : Boolean;
  C      : Char;
  IdStart: Integer;
  Ident  : string;
begin
  Result := False;
  if Tainted.Count = 0 then Exit;
  InStr := False;
  i := 1;
  n := Length(ArgsPart);
  IdStart := 0;

  while i <= n do
  begin
    C := ArgsPart[i];
    // Apostroph-State pflegen (gleiche Logik wie HasConcatInArgs).
    if C = '''' then
    begin
      if InStr and (i + 1 <= n) and (ArgsPart[i + 1] = '''') then
      begin
        Inc(i, 2);
        Continue;
      end;
      InStr := not InStr;
      Inc(i);
      Continue;
    end;
    if InStr then begin Inc(i); Continue; end;

    // Identifier-Sammlung ausserhalb von Strings.
    if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or
       ((IdStart > 0) and CharInSet(C, ['0'..'9'])) then
    begin
      if IdStart = 0 then IdStart := i;
    end
    else
    begin
      if IdStart > 0 then
      begin
        Ident := LowerCase(Copy(ArgsPart, IdStart, i - IdStart));
        if Tainted.IndexOf(Ident) >= 0 then Exit(True);
        IdStart := 0;
      end;
    end;
    Inc(i);
  end;
  // Trailing-Ident (Args-Part endet ohne Trenner)
  if IdStart > 0 then
  begin
    Ident := LowerCase(Copy(ArgsPart, IdStart, n - IdStart + 1));
    if Tainted.IndexOf(Ident) >= 0 then Result := True;
  end;
end;

class procedure TCommandInjectionDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls    : TList<TAstNode>;
  Tainted  : TList<string>;
  N        : TAstNode;
  ApiName  : string;
  LParen   : Integer;
  ArgsPart : string;
  Reason   : string;
begin
  Tainted := TList<string>.Create;
  Calls   := MethodNode.FindAll(nkCall);
  try
    // Pass 1: Tainted-Vars sammeln (LHS von Concat-Assigns in dieser Method).
    CollectTaintedVars(MethodNode, Tainted);

    // Pass 2: pro Shell-API-Call entweder direkter Concat-Arg ODER
    // Tainted-Var im Arg.
    for N in Calls do
    begin
      if not IsShellApiCall(N.Name, ApiName) then Continue;

      // Args-Teil: nach erstem '(' bis Ende. Schliessende ')' kann fehlen
      // wenn der Parser den Call nur partiell abbildet - wir scannen den
      // Rest des Strings.
      LParen := Pos('(', N.Name);
      if LParen < 1 then Continue;
      ArgsPart := Copy(N.Name, LParen + 1, MaxInt);

      Reason := '';
      if HasConcatInArgs(ArgsPart) then
        Reason := 'string concatenation in arguments'
      else if ArgsContainTaintedVar(ArgsPart, Tainted) then
        Reason := 'tainted variable (concat-assigned earlier) passed as argument';

      if Reason = '' then Continue;

      Results.Add(TLeakFinding.New(FileName, MethodNode.Name, N.Line,
        Format('Potential command injection: %s called with %s',
          [UpperCase(ApiName[1]) + Copy(ApiName, 2, MaxInt), Reason]),
        fkCommandInjection, fcLow));
    end;
  finally
    Calls.Free;
    Tainted.Free;
  end;
end;

class procedure TCommandInjectionDetector.AnalyzeUnit(UnitNode: TAstNode;
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
