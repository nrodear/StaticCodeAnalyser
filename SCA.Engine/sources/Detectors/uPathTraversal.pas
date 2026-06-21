unit uPathTraversal;

// Detektor: Heuristik fuer Path-Traversal-Risiko.
// File-Open-Call mit Argument-Expression die ein User-Input-Token
// (Edit.Text, Memo.Lines.Text, Request.Params, Sender.Text, ...)
// enthaelt UND eine String-Concat (`+`) - klassisches
// "User input goes into file path"-Pattern.
//
// Pattern (Security):
//   Stream := TFileStream.Create(BaseDir + edPath.Text, fmOpenRead);
//   ^^^                                  ^^^^^^^^^^^^^
//   File-Open                            User-Input
//
//   Wenn edPath.Text z.B. '../../../etc/passwd' enthaelt: Path-Traversal.
//
// Erkennung (AST + Text-Heuristik, kein Taint-Tracking):
//   * Walk nkCall (Statement) + nkAssign (RHS).
//   * Pro Call/Assign-Expression: scanne ob es einen FILE_OPEN_API-Token
//     enthaelt (TFileStream.Create, TFile.OpenRead, AssignFile, ...).
//   * Wenn ja: pruefe ob der gleiche String einen USER_INPUT_SUFFIX
//     (.Text, .Lines, .Caption, .Value, Params[...], Sender.Text)
//     enthaelt + ein '+' fuer Concat.
//   * Wenn beide -> Finding (Severity Error, Confidence Medium).
//
// FP-Risiken:
//   * `TFileStream.Create(Sanitize(edPath.Text), ...)` mit Wrapper-Sanitize
//     wuerde geflagt - User suppressiert per Marker.
//   * `+` ohne user-input ist OK (kein Match), aber `+` mit ANDERER var-
//     Concat (z.B. `BaseDir + 'log.txt'`) wuerde nicht matchen weil
//     'log.txt' keine User-Input-Suffix.
//
// Severity: lsError, Type: ftVulnerability.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TPathTraversalDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function ContainsFileOpenAPI(const Expr: string;
      out HitAPI: string): Boolean; static;
    class function ContainsUserInputAndConcat(const Expr: string;
      out HitInput: string): Boolean; static;
  end;

implementation

uses
  uDetectorUtils;

const
  // File-Open-APIs (Substring-Match, case-insensitive Lower-Compare).
  FILE_OPEN_APIS : array[0..10] of string = (
    'tfilestream.create',
    'tfile.openread', 'tfile.opentext', 'tfile.openwrite',
    'tfile.readalltext', 'tfile.readallbytes',
    'tfile.writealltext', 'tfile.writeallbytes',
    'assignfile', 'fileopen', 'filecreate'
  );

  // User-Input-Suffix-Tokens (case-insensitive Substring-Match).
  USER_INPUT_TOKENS : array[0..9] of string = (
    '.text', '.lines.text', '.caption', '.value',
    'request.params', 'request.querystring',
    'sender.text', 'getcommandline',
    'paramstr(', 'paramcount'
  );

class function TPathTraversalDetector.ContainsFileOpenAPI(
  const Expr: string; out HitAPI: string): Boolean;
var
  Low : string;
  API : string;
  P   : Integer;
begin
  Result := False;
  HitAPI := '';
  Low := LowerCase(Expr);
  for API in FILE_OPEN_APIS do
  begin
    P := TDetectorUtils.FindTokenBoundedLower(API, Low);
    if P > 0 then
    begin
      HitAPI := Copy(Expr, P, Length(API));
      Exit(True);
    end;
  end;
end;

class function TPathTraversalDetector.ContainsUserInputAndConcat(
  const Expr: string; out HitInput: string): Boolean;
var
  Low : string;
  Tok : string;
  P   : Integer;
begin
  Result := False;
  HitInput := '';
  if Pos('+', Expr) = 0 then Exit;     // ohne Concat kein Pattern
  Low := LowerCase(Expr);
  for Tok in USER_INPUT_TOKENS do
  begin
    // FindTokenBoundedLower statt Pos: '.text' darf NICHT in
    // 'MediaType.TEXT_HTML' matchen (rechts steht '_' = Ident-Char).
    P := TDetectorUtils.FindTokenBoundedLower(Tok, Low);
    if P > 0 then
    begin
      HitInput := Copy(Expr, P, Length(Tok));
      Exit(True);
    end;
  end;
end;

class procedure TPathTraversalDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Calls, Assigns : TList<TAstNode>;
  N              : TAstNode;
  HitAPI, HitInp : string;
  F              : TLeakFinding;

  procedure Check(N: TAstNode; const Expr: string);
  var L: TLeakFinding;
  begin
    if not ContainsFileOpenAPI(Expr, HitAPI) then Exit;
    if not ContainsUserInputAndConcat(Expr, HitInp) then Exit;
    L            := TLeakFinding.Create;
    L.FileName   := FileName;
    L.MethodName := '';
    L.LineNumber := IntToStr(N.Line);
    L.MissingVar := 'Path-Traversal risk: "' + HitAPI + '" receives an ' +
                    'expression that concatenates user input ("' + HitInp +
                    '"). Validate / canonicalize the path; reject ".." ' +
                    'segments before passing to the API.';
    L.SetKind(fkPathTraversal);
    Results.Add(L);
  end;

begin
  Calls := UnitNode.FindAll(nkCall);
  try
    for N in Calls do Check(N, N.Name);
  finally
    Calls.Free;
  end;
  Assigns := UnitNode.FindAll(nkAssign);
  try
    for N in Assigns do Check(N, N.TypeRef);
  finally
    Assigns.Free;
  end;
end;

end.
