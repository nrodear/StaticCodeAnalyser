unit uSynchronizeInDestructor;

// Detektor fuer Synchronize im Destruktor (SCA108, Warning):
//   - destructor Destroy ruft TThread.Synchronize(...) auf
//   - laeuft der Destruktor im Hauptthread, ruft Synchronize die Methode
//     einfach direkt auf - kein Problem
//   - laeuft er im Worker selbst (der uebliche Fall bei FreeOnTerminate,
//     der Thread gibt sich nach Execute selbst frei), blockiert
//     Synchronize den Worker, bis der Hauptthread den Aufruf ausfuehrt
//   - fuehrt der Hauptthread ihn nicht aus (wartet per
//     WaitForSingleObject statt TThread.WaitFor, oder die Anwendung wird
//     beendet), warten beide aufeinander -> Hang
// Der frueher behauptete Deadlock mit WaitFor/.Free im Hauptthread trifft
// nicht zu: TThread.WaitFor im Hauptthread arbeitet Synchronize-Anfragen
// ab, und ein Free aus dem Hauptthread fuehrt den Destruktor dort aus.
// Daher Warning, und der Meldetext beschreibt das enge Szenario, nicht
// einen sicheren Hang.
//
// Beispiel:
//   destructor TWorker.Destroy;
//   begin
//     Synchronize(procedure begin Form1.Log('done') end);  // blockt den Worker
//     inherited;
//   end;
//
// Fix:
//   - die Benachrichtigung in einen OnTerminate-Handler verlegen (laeuft
//     im Hauptthread, bevor das Thread-Objekt freigegeben wird) oder ans
//     Ende von Execute
//
// Grenze: der Detektor prueft weder FreeOnTerminate noch, ob die Klasse
// von TThread erbt - er meldet jedes Synchronize in einem Destruktor.
// Deshalb formuliert der Meldetext das Szenario als Bedingung.
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
          // Der Text nennt das Szenario als Bedingung, weil der Detektor
          // FreeOnTerminate nicht prueft: haengen kann es nur, wenn der
          // Destruktor im Worker laeuft und der Hauptthread den Aufruf
          // nicht ausfuehrt (Katalogtext SCA108). Geht in Baseline-
          // Fingerprint und SARIF-Line-Hash ein - Aenderung = neue Identitaet.
          F.MissingVar :=
            Format('Synchronize() called from destructor %s - if the ' +
                   'destructor runs in the worker thread (FreeOnTerminate), ' +
                   'the call blocks it until the main thread runs it, and ' +
                   'hangs if the main thread does not. Move the ' +
                   'notification to OnTerminate or the end of Execute.',
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
