unit uBooleanParam;

// Detektor: Boolean-Parameter wird intern als Branching-Flag genutzt.
//
// Pattern (Code Smell, Sonar-50 #33):
//   procedure SendNotification(const Msg: string; IsError: Boolean);
//   begin
//     if IsError then
//       Notify(Msg, clRed)
//     else
//       Notify(Msg, clBlack);
//   end;
//
// Korrekt: zwei dedizierte Methoden mit sprechenden Namen.
//   procedure SendErrorNotification(const Msg: string);
//   begin Notify(Msg, clRed); end;
//
//   procedure SendInfoNotification(const Msg: string);
//   begin Notify(Msg, clBlack); end;
//
// Begruendung: Boolean-Parameter, dessen Wert die Methode in zwei
// vollkommen verschiedene Verhalten teilt, ist ein verstecktes "Strategy
// Pattern" - der Aufrufer muss dokumentieren / kommentieren was True/False
// bedeutet. Separater Methodenname macht das Sicht ganz ohne Doku.
//
// Erkennung (AST, heuristisch):
//   * nkMethod-Knoten, dessen Body mindestens EIN if-Statement mit
//     dem Boolean-Parameter als Condition enthaelt.
//   * Property-Setter (SetXxx-Pattern) sind ausgenommen - VCL-Konvention.
//   * Event-Handler-Signatur (Sender: TObject ...) sind ausgenommen.
//
// Limitierungen:
//   * Boolean-Parameter, die NUR an andere Funktionen weitergereicht werden
//     (kein internes if), werden NICHT geflaggt - das ist legitim.
//   * Identifier-Vergleich case-insensitive ueber Name + NameTrim.
//
// Schweregrad: lsHint - Stil-Empfehlung, kein Bug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TBooleanParamDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, NestedRoutine, NestedTry, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function IsBooleanType(const TypeText: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(TypeText));
  Result := (Low = 'boolean') or (Low = 'longbool') or (Low = 'wordbool')
            or (Low = 'bytebool');
end;

// Property-Setter erkennen: Method-Name endet auf SetXxx (klassische
// VCL-Konvention) oder beginnt mit `Set` (case-insensitive).
function LooksLikeSetter(const MethodName: string): Boolean;
var
  Tail : string;
  i : Integer;
begin
  Tail := MethodName;
  for i := Length(MethodName) downto 1 do
    if MethodName[i] = '.' then
    begin
      Tail := Copy(MethodName, i + 1, MaxInt);
      Break;
    end;
  Result := StartsText('set', Tail);
end;

function IfStmtRefersToIdent(IfNode: TAstNode; const IdentLow: string): Boolean;
// Der Parser legt die if-Condition als FLACHEN Text in IfNode.TypeRef ab
// (uParser2.pas ParseIfStmt:1269). Children = Then/Else-Branches, NICHT
// die Condition. Wir matchen daher den Identifier word-bounded in TypeRef.
//
// Word-boundary haendisch: Vor- und Nach-Char muessen non-Identifier sein
// (kein A-Z, a-z, 0-9, _). Damit matched 'IsError' nicht in 'WasIsErrorSet'.
var
  Cond : string;
  pIx  : Integer;
  Before, After : Char;
  function IsIdentChar(c: Char): Boolean;
  begin
    Result := CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;
begin
  Result := False;
  Cond := LowerCase(IfNode.TypeRef);
  if Cond = '' then Exit;
  pIx := Pos(IdentLow, Cond);
  while pIx > 0 do
  begin
    if pIx = 1 then Before := ' ' else Before := Cond[pIx - 1];
    if pIx + Length(IdentLow) > Length(Cond) then
      After := ' '
    else
      After := Cond[pIx + Length(IdentLow)];
    if (not IsIdentChar(Before)) and (not IsIdentChar(After)) then
      Exit(True);
    pIx := PosEx(IdentLow, Cond, pIx + 1);
  end;
end;

class procedure TBooleanParamDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Params  : TList<TAstNode>;
  P       : TAstNode;
  IfStmts : TList<TAstNode>;
  I       : TAstNode;
  IdentLow : string;
  Hit     : Boolean;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if LooksLikeSetter(M.Name) then Continue;
      Params := M.FindAll(nkParam);
      try
        for P in Params do
        begin
          if not IsBooleanType(P.TypeRef) then Continue;
          if P.Name = '' then Continue;
          IdentLow := LowerCase(P.Name);
          // Spezial-Skips: typische VCL-Event-Handler-Booleans wie
          // 'CanShow', 'Handled' werden ueber API-Konventionen erwartet
          // und sind keine selbstgewaehlte Flag-API.
          if (IdentLow = 'handled') or (IdentLow = 'canshow')
             or (IdentLow = 'shift') then Continue;

          // Pruefe ob ein if-Statement im Method-Body diesen Identifier referenziert.
          Hit := False;
          IfStmts := M.FindAll(nkIfStmt);
          try
            for I in IfStmts do
              if IfStmtRefersToIdent(I, IdentLow) then
              begin
                Hit := True;
                Break;
              end;
          finally
            IfStmts.Free;
          end;
          if not Hit then Continue;

          Results.Add(TLeakFinding.New(FileName, M.Name, M.Line,
            Format('Boolean parameter %s of %s drives internal branching - ' +
                   'consider two methods with descriptive names',
              [P.Name, M.Name]),
            fkBooleanParam));
        end;
      finally
        Params.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
