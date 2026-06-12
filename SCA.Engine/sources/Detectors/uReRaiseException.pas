unit uReRaiseException;

// Detektor: `except on E: Exception do raise E;` - re-raise der gebundenen
// Variable statt eines bare `raise;`.
//
// Pattern (Bug):
//   try
//     RiskyCall;
//   except
//     on E: EDivByZero do
//     begin
//       Log(E.Message);
//       raise E;            // <-- verliert den Original-Stack-Trace
//     end;
//   end;
//
// Korrekt:
//   try
//     RiskyCall;
//   except
//     on E: EDivByZero do
//     begin
//       Log(E.Message);
//       raise;              // <-- behaelt Stack-Trace, kein Re-Wrap
//     end;
//   end;
//
// Folge: `raise E` startet eine neue Exception-Propagation mit der
// jetzigen Code-Stelle als Origin. Der ursprueliche Stack-Trace zu der
// Stelle wo die Exception ENTSTANDEN ist (z.B. tief in RiskyCall) wird
// ueberschrieben. Debugging wird massiv erschwert; in Crash-Reports
// zeigt der Trace nur den re-raise-Punkt, nicht den eigentlichen
// Fehler-Ort.
//
// Erkennung (AST-basiert, deterministisch):
//   * Finde alle nkOnHandler mit Name <> '' (= 'on E: T do', wobei E
//     die gebundene Variable ist - nkOnHandler.Name = 'E').
//   * Im Subtree dieses OnHandlers: suche nkRaise-Knoten.
//   * Wenn nkRaise.Name (case-insensitive, getrimmt) gleich dem
//     OnHandler.Name ist -> Finding.
//
// Bewusst NICHT Finding:
//   * `raise;` (Name leer) - korrektes re-raise.
//   * `raise E.NewWith(...);` - User wrappt mit Side-Daten, technisch
//     auch Stack-Verlust, aber Intent ist klar. Sonar's Original-Check
//     verlangt ebenfalls exakten Match auf die gebundene Variable.
//   * `raise OtherE;` - andere Variable; entweder anderer Handler oder
//     Bug, in beiden Faellen nicht der Re-Raise-Pattern.
//   * `on Exception do` (kein Bind-Var, OnHandler.Name = '') - kein
//     Re-Raise moeglich, weil die Exception nicht referenziert werden kann.
//
// Sonar-Pendant: ReRaiseExceptionCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   ReRaiseExceptionCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TReRaiseExceptionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeStrictPrivate, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TReRaiseExceptionDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Handlers   : TList<TAstNode>;
  H          : TAstNode;
  Raises     : TList<TAstNode>;
  R          : TAstNode;
  HandlerVar : string;
  RaiseExpr  : string;
  F          : TLeakFinding;
begin
  Handlers := MethodNode.FindAll(nkOnHandler);
  try
    for H in Handlers do
    begin
      HandlerVar := Trim(H.Name);
      if HandlerVar = '' then Continue;     // 'on Exception do' ohne Var

      Raises := H.FindAll(nkRaise);
      try
        for R in Raises do
        begin
          RaiseExpr := Trim(R.Name);
          if RaiseExpr = '' then Continue;  // bare `raise;` - korrekt
          if not SameText(RaiseExpr, HandlerVar) then Continue;

          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := MethodNode.Name;
          F.LineNumber := IntToStr(R.Line);
          F.MissingVar := Format(
            'Re-raise of bound variable "%s" loses the original stack trace - use bare `raise;` instead',
            [HandlerVar]);
          F.SetKind(fkReRaiseException);
          Results.Add(F);
        end;
      finally
        Raises.Free;
      end;
    end;
  finally
    Handlers.Free;
  end;
end;

class procedure TReRaiseExceptionDetector.AnalyzeUnit(UnitNode: TAstNode;
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
