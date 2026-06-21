unit uThreadFreeOnTerminateWithRef;

// Detektor: TThread mit FreeOnTerminate=True + spaeterer Zugriff durch
// den Caller -> Access-Violation (Thread kann jederzeit beendet sein).
//
// Pattern (Concurrency-Crash):
//   T := TMyThread.Create(True);
//   T.FreeOnTerminate := True;
//   T.Start;
//   T.Resume;          // BUG: T koennte schon freigegeben sein
//   T.WaitFor;         // BUG: T koennte schon freigegeben sein
//   if T.Finished ...  // BUG: T koennte schon freigegeben sein
//
// Korrekt:
//   T := TMyThread.Create(True);
//   T.FreeOnTerminate := True;
//   T.Start;
//   T := nil;          // sofort weg, kein weiterer Zugriff
//   // ODER: kein FreeOnTerminate, manuell verwalten.
//
// Erkennung (per-Method-Scope-Walk):
//   * Pass 1: Walk nkAssign, finde `<var>.FreeOnTerminate := True`
//     Variante. Sammle Var-Namen mit Zeile.
//   * Pass 2: Walk nkAssign + nkCall, finde subsequent (Line > Pass-1-
//     Line) `<var>.<anything>`-Zugriffe. Pro Match ein Finding.
//
// FP-Tradeoff:
//   * Cross-Method-Reference (`T` aus Field gehalten + spaeter Access)
//     wird nicht erkannt - per-Method-Scope.
//   * Var = nil zwischen FreeOnTerminate und Access wird NICHT als
//     Sicherheits-Massnahme erkannt - FP wenn User das macht.
//     Suppression-Marker als Escape.
//   * FreeOnTerminate := False (explizit) wird NICHT geflagt.
//
// Severity: lsError, Type: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TThreadFreeOnTerminateWithRefDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Liefert den Var-Namen wenn LHS `<var>.FreeOnTerminate` ist,
    // sonst leerstring. Case-insensitive.
    class function MatchFreeOnTerminateLHS(const LHS: string): string; static;
    // True wenn RHS (TypeRef) `True` ist (case-insensitive, getrimmt).
    class function IsTrueLiteral(const RHS: string): Boolean; static;
    // True wenn Expr `<var>.<sub>` Pattern enthaelt UND sub NICHT auf
    // der Lifecycle-Whitelist {Start, Resume, Execute} steht. Diese
    // Calls sind in dieser Reihenfolge erwartet (FoT vor Start ist
    // die Standard-Delphi-Idiom).
    class function HasDangerousMemberAccess(const Expr, VarName: string): Boolean; static;
    // True wenn Expr ein Aktivierungs-Call `<var>.Start` / `<var>.Resume`
    // ist - der Punkt ab dem der Thread LEBT (und sich selbst zerstoeren
    // kann). Resume ist der pre-XE2-Start.
    class function IsActivationCall(const Expr, VarName: string): Boolean; static;
  end;

implementation

uses
  System.RegularExpressions;

class function TThreadFreeOnTerminateWithRefDetector.MatchFreeOnTerminateLHS(
  const LHS: string): string;
var
  M : TMatch;
begin
  Result := '';
  M := TRegEx.Match(LHS, '^([A-Za-z_]\w*)\.FreeOnTerminate$', [roIgnoreCase]);
  if M.Success then Result := M.Groups[1].Value;
end;

class function TThreadFreeOnTerminateWithRefDetector.IsTrueLiteral(
  const RHS: string): Boolean;
begin
  Result := SameText(Trim(RHS), 'True');
end;

class function TThreadFreeOnTerminateWithRefDetector.HasDangerousMemberAccess(
  const Expr, VarName: string): Boolean;
// True wenn `<VarName>.<ident>` im Expr vorkommt UND ident NICHT auf
// der Lifecycle-Whitelist {Start, Execute} steht. Start ist der ERWARTETE
// Init-Call nach FoT, Execute ist der Inner-Thread-Body. Resume ist
// deprecated und nach FoT genauso gefaehrlich wie ein generischer
// Member-Access -> NICHT auf der Whitelist.
const
  // 'resume' jetzt auf der Whitelist: pre-XE2 ist Resume DER Start-Call,
  // kein gefaehrlicher Post-Mortem-Zugriff (Real-World-FP 2026-06-21).
  WHITELIST : array[0..2] of string = ('start', 'execute', 'resume');
var
  Pat   : string;
  M     : TMatch;
  Sub   : string;
  Allow : string;
  IsAllowed : Boolean;
begin
  Result := False;
  Pat := '\b' + VarName + '\s*\.\s*(\w+)';
  for M in TRegEx.Matches(Expr, Pat, [roIgnoreCase]) do
  begin
    Sub := LowerCase(M.Groups[1].Value);
    IsAllowed := False;
    for Allow in WHITELIST do
      if Sub = Allow then begin IsAllowed := True; Break; end;
    if not IsAllowed then Exit(True);
  end;
end;

class function TThreadFreeOnTerminateWithRefDetector.IsActivationCall(
  const Expr, VarName: string): Boolean;
var
  M : TMatch;
  Sub : string;
begin
  Result := False;
  M := TRegEx.Match(Expr, '\b' + VarName + '\s*\.\s*(\w+)', [roIgnoreCase]);
  if not M.Success then Exit;
  Sub := LowerCase(M.Groups[1].Value);
  Result := (Sub = 'start') or (Sub = 'resume');
end;

class procedure TThreadFreeOnTerminateWithRefDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Assigns, Calls : TList<TAstNode>;
  M, N    : TAstNode;
  // Var-Name -> Line der FreeOnTerminate-Zuweisung
  FoTLine : TDictionary<string, Integer>;
  // Var-Name -> Line des Start/Resume-Calls (Thread wird ab hier "lebendig")
  ActLine : TDictionary<string, Integer>;
  VarName : string;
  Pair    : TPair<string, Integer>;
  GateLine: Integer;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      FoTLine := TDictionary<string, Integer>.Create;
      ActLine := TDictionary<string, Integer>.Create;
      try
        // Pass 1: FreeOnTerminate := True finden.
        Assigns := M.FindAll(nkAssign);
        try
          for N in Assigns do
          begin
            VarName := MatchFreeOnTerminateLHS(N.Name);
            if VarName = '' then Continue;
            if not IsTrueLiteral(N.TypeRef) then Continue;
            FoTLine.AddOrSetValue(LowerCase(VarName), N.Line);
          end;
        finally
          Assigns.Free;
        end;
        if FoTLine.Count = 0 then Continue;

        // Pass 1b: Aktivierungs-Call (Start/Resume) pro Var finden -
        // FRUEHESTE Zeile. Erst NACH dem Start ist ein Zugriff gefaehrlich;
        // Config-Assignments + Reads VOR dem Start sind harmlos (Thread
        // laeuft noch nicht). Real-World-FP 2026-06-21.
        Calls := M.FindAll(nkCall);
        try
          for N in Calls do
            for Pair in FoTLine do
              if IsActivationCall(N.Name, Pair.Key) then
                if (not ActLine.ContainsKey(Pair.Key))
                   or (N.Line < ActLine[Pair.Key]) then
                  ActLine.AddOrSetValue(Pair.Key, N.Line);
        finally
          Calls.Free;
        end;

        // Pass 2: subsequent Access auf VarName NACH dem Start.
        // Ohne Start im selben Method-Scope: kein Finding (per-Method-FN).
        for Pair in FoTLine do
        begin
          if not ActLine.TryGetValue(Pair.Key, GateLine) then Continue;
          Assigns := M.FindAll(nkAssign);
          try
            for N in Assigns do
            begin
              if N.Line <= GateLine then Continue;
              // Nur RHS-Reads (N.TypeRef) flaggen - LHS-Property-Assignments
              // (`<var>.Name := x`) sind Config, kein gefaehrlicher Read.
              if HasDangerousMemberAccess(N.TypeRef, Pair.Key) then
              begin
                F            := TLeakFinding.Create;
                F.FileName   := FileName;
                F.MethodName := M.Name;
                F.LineNumber := IntToStr(N.Line);
                F.MissingVar := 'Access on "' + Pair.Key + '" after ' +
                                'FreeOnTerminate:=True (set at line ' +
                                IntToStr(Pair.Value) + ') - the thread may ' +
                                'have already self-destructed. Set the ' +
                                'reference to nil right after Start.';
                F.SetKind(fkThreadFreeOnTerminateWithRef);
                Results.Add(F);
              end;
            end;
          finally
            Assigns.Free;
          end;
          Calls := M.FindAll(nkCall);
          try
            for N in Calls do
            begin
              if N.Line <= GateLine then Continue;
              if HasDangerousMemberAccess(N.Name, Pair.Key) then
              begin
                F            := TLeakFinding.Create;
                F.FileName   := FileName;
                F.MethodName := M.Name;
                F.LineNumber := IntToStr(N.Line);
                F.MissingVar := 'Call on "' + Pair.Key + '" after ' +
                                'FreeOnTerminate:=True (set at line ' +
                                IntToStr(Pair.Value) + ') - thread may have ' +
                                'self-destructed.';
                F.SetKind(fkThreadFreeOnTerminateWithRef);
                Results.Add(F);
              end;
            end;
          finally
            Calls.Free;
          end;
        end;
      finally
        FoTLine.Free;
        ActLine.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
