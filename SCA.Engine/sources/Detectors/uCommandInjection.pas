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
  end;

implementation

const
  // Wir matchen auf die WIN-API-Namen + Delphi-RTL-Pendants. Aufruf-Form ist
  // case-insensitive (Pascal). Liste laesst sich erweitern (PowerShellExecute,
  // CreateProcessAsUser, ...) ohne weitere Logik-Aenderung.
  SHELL_APIS: array[0..7] of string = (
    'shellexecute', 'shellexecuteex',
    'shellexecutea', 'shellexecutew',
    'createprocess', 'createprocessa', 'createprocessw',
    'winexec'
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

class procedure TCommandInjectionDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls    : TList<TAstNode>;
  N        : TAstNode;
  F        : TLeakFinding;
  ApiName  : string;
  LParen   : Integer;
  ArgsPart : string;
begin
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      if not IsShellApiCall(N.Name, ApiName) then Continue;

      // Args-Teil: nach erstem '(' bis Ende. Schliessende ')' kann fehlen
      // wenn der Parser den Call nur partiell abbildet - wir scannen den
      // Rest des Strings.
      LParen := Pos('(', N.Name);
      if LParen < 1 then Continue;
      ArgsPart := Copy(N.Name, LParen + 1, MaxInt);

      if not HasConcatInArgs(ArgsPart) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        'Potential command injection: %s called with string concatenation in arguments',
        [UpperCase(ApiName[1]) + Copy(ApiName, 2, MaxInt)]);
      // Confidence-Override: ohne Taint-Tracking ist die Heuristik
      // explizit niedrig. Im Standard-Profil (Filter MinConfidence=Medium)
      // wird das Finding nicht angezeigt - User muss 'low' freischalten.
      // SetKind-mit-Confidence-Overload schuetzt vor Reihenfolge-Bug.
      F.SetKind(fkCommandInjection, fcLow);
      Results.Add(F);
    end;
  finally
    Calls.Free;
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
