unit uSynchronizeInDestructor;

// Detektor fuer den klassischen Threading-Deadlock-Pfad:
//   - destructor Destroy ruft TThread.Synchronize(...) auf
//   - Synchronize blockiert den Worker-Thread bis der UI-Thread (Main)
//     den Closure-Aufruf abgeschlossen hat
//   - der UI-Thread haengt aber typischerweise selbst in TThread.WaitFor
//     oder Free (das implizit WaitFor ruft)
//   - -> beide warten aufeinander, Hang.
//
// Beispiel:
//   destructor TWorker.Destroy;
//   begin
//     Synchronize(procedure begin Form1.Log('done') end);  // Deadlock!
//     inherited;
//   end;
//
// Fix:
//   - Synchronize-Aufrufe aus dem Destruktor entfernen (last-call via
//     Queue oder Notify-Mechanismus VOR dem Free auf dem Worker-Thread)
//   - oder garantieren dass das Free niemals vom UI-Thread kommt
//
// Erkennung: AST-basiert. Walk durch nkMethod-Knoten, deren Name auf
// 'Destroy' endet. Im Body nach nkCall mit Name 'Synchronize' oder
// 'TThread.Synchronize' suchen.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TSynchronizeInDestructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsDestructor(const M: TAstNode): Boolean;
// Method-Name endet auf .Destroy (oder ist plain 'Destroy' im Interface-
// Header). TypeRef beginnt mit 'destructor' wenn der Parser den Marker
// preserved hat.
var
  N : string;
begin
  Result := False;
  if M.Kind <> nkMethod then Exit;
  N := LowerCase(M.Name);
  if N.EndsWith('.destroy') or (N = 'destroy') then Exit(True);
  if LowerCase(Trim(M.TypeRef)).StartsWith('destructor') then Exit(True);
end;

function ExtractCallTarget(const RawName: string): string;
// Aus 'Synchronize(LogDone)' -> 'Synchronize', aus 'TThread.Synchronize(nil,
// LogDone)' -> 'TThread.Synchronize'. uParser2.ParsePrimary baut den nkCall-
// Name als 'Bezeichner(Args)' zusammen - die Klammern + Argumente muessen
// weg, bevor wir auf 'synchronize'/'.synchronize' matchen.
var
  P : Integer;
begin
  Result := Trim(RawName);
  P := Pos('(', Result);
  if P > 0 then Result := Trim(Copy(Result, 1, P - 1));
end;

function IsSynchronizeCall(const C: TAstNode): Boolean;
// Match auf Aufruf-Namen: 'Synchronize', 'TThread.Synchronize', oder
// jede Variante die mit '.Synchronize' endet (z.B. 'Self.Synchronize').
var
  N : string;
begin
  Result := False;
  if C.Kind <> nkCall then Exit;
  N := LowerCase(ExtractCallTarget(C.Name));
  Result := (N = 'synchronize') or N.EndsWith('.synchronize');
end;

class procedure TSynchronizeInDestructorDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  M, C    : TAstNode;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not IsDestructor(M) then Continue;

      Calls := M.FindAll(nkCall);
      try
        for C in Calls do
        begin
          if not IsSynchronizeCall(C) then Continue;
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := M.Name;
          F.LineNumber := IntToStr(C.Line);
          F.MissingVar :=
            Format('Synchronize() called from destructor %s - classic ' +
                   'deadlock: worker blocks on UI thread which may be ' +
                   'waiting on this worker (WaitFor / .Free). Move ' +
                   'Synchronize-based cleanup out of the destructor.',
                   [M.Name]);
          F.SetKind(fkSynchronizeInDestructor);
          Results.Add(F);
        end;
      finally
        Calls.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
