unit uVariantTypeMisuse;

// Detektor: Variant-Typ in Performance-relevantem Kontext (Methode die
// einen Loop enthaelt).
//
// Hintergrund:
//   Jede Operation auf Variant geht durch den COM-VarType-Dispatcher
//   (VarCmp/VarAdd/etc), ~10-100x langsamer als typed-Operationen.
//   In einer Hot-Loop summiert sich das schnell zu wahrnehmbarem
//   Performance-Tax. Akzeptable Use-Cases (COM/OLE-Bridges, DB-Field-
//   Werte, Excel-Automation) sind die Ausnahme.
//
// Erkennung (AST):
//   * Walk nkMethod.
//   * In den Method-Children: pruefe ob ein Loop-Statement
//     (nkForStmt/nkWhileStmt/nkRepeatStmt) existiert.
//   * Wenn ja: walk nkLocalVar im selben Method - flag jeden Variant-
//     typed-Local-Var. Auch nkParam mit Variant-Typ als Hint melden.
//
// FP-Tradeoff:
//   * Seit der Autopsie 2026-08-26 (Gate A) wird zusaetzlich geprueft,
//     ob der Variant-NAME in einem der Loop-Teilbaeume der Methode
//     vorkommt (Wortgrenzen-Match auf den flachen Node-Texten). Die
//     alte Fassung meldete jeden Variant in jeder Methode mit
//     irgendeinem Loop - 18 der 19 Stichproben-FPs und ALLE 14
//     Audit-FPs vom 15.08. waren "Variant wird in keinem Loop benutzt"
//     (Nutzung nur vor/nach dem Loop). GEMESSEN: 282 der 613
//     rw14-Funde fallen, 0/21 TP-Verlust in der Stichprobe.
//   * Grenzen des Gates, bewusst konservativ gehalten:
//     - Methoden mit nested Routinen (nkNestedRange-Marker) werden
//       NICHT gegated: deren Ruempfe sind im AST verworfen, die
//       Loop-Sicht ist dort blind (36 Guard-Keeps enthalten belegte
//       TPs, JvDBUtils-KeyValues-Familie - Guard nicht lockern).
//     - until-Bedingungen stehen nicht im AST (geparst-verworfen,
//       uParser2 ParseRepeatStmt) - eine Nutzung NUR dort waere
//       unsichtbar; am Referenzkorpus 0 solcher Faelle (Skeptiker-
//       Gegenzaehlung 2026-08-26).
//   * COM-/OLE-Code wo Variant unvermeidbar ist (Excel/Word-Automation)
//     wird gemeldet - Suppression-Marker bei expliziter Akzeptanz.
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TVariantTypeMisuseDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function IsVariantType(const TypeRef: string): Boolean; static;
    class function HasLoopChild(Method: TAstNode): Boolean; static;
    class function UsedInAnyLoop(Method: TAstNode;
      const NameLow: string): Boolean; static;
  end;

implementation

uses
  uConstStringParameter;  // MethodHasDirective = Wortgrenzen-Match

function SubtreeMentionsIdent(N: TAstNode; const IdentLow: string): Boolean;
// Wortgrenzen-Suche des Idents in den flachen Text-Repraesentationen
// des Teilbaums. Argumente von Calls stehen in nkCall.NAME (nicht
// TypeRef - Gegenpruefungs-Befund 2026-08-26), darum beide Felder.
var
  C : TAstNode;
begin
  if MethodHasDirective(LowerCase(N.Name), IdentLow) or
     MethodHasDirective(LowerCase(N.TypeRef), IdentLow) then Exit(True);
  for C in N.Children do
    if SubtreeMentionsIdent(C, IdentLow) then Exit(True);
  Result := False;
end;

class function TVariantTypeMisuseDetector.IsVariantType(
  const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(TypeRef));
  Result := (Low = 'variant') or (Low = 'olevariant');
end;

class function TVariantTypeMisuseDetector.HasLoopChild(
  Method: TAstNode): Boolean;
begin
  Result := Method.HasDescendant(nkForStmt) or
            Method.HasDescendant(nkWhileStmt) or
            Method.HasDescendant(nkRepeatStmt);
end;

class function TVariantTypeMisuseDetector.UsedInAnyLoop(Method: TAstNode;
  const NameLow: string): Boolean;
// Gate A (Autopsie 2026-08-26): kommt der Variant-Name in einem der
// Loop-Teilbaeume vor? FindAllRef liefert die non-owning Cache-Liste
// (uAstNode P6) - NICHT freigeben.
var
  Kind  : TNodeKind;
  Loops : TList<TAstNode>;
  L     : TAstNode;
begin
  for Kind in [nkForStmt, nkWhileStmt, nkRepeatStmt] do
  begin
    Loops := Method.FindAllRef(Kind);
    for L in Loops do
      if SubtreeMentionsIdent(L, NameLow) then Exit(True);
  end;
  Result := False;
end;

class procedure TVariantTypeMisuseDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M, Ch   : TAstNode;

  procedure Emit(Line: Integer; const VarName, TypeRef, MethodName: string);
  var L: TLeakFinding;
  begin
    L            := TLeakFinding.Create;
    L.FileName   := FileName;
    L.MethodName := MethodName;
    L.LineNumber := IntToStr(Line);
    L.MissingVar := 'Variant "' + VarName + ': ' + TypeRef +
                    '" inside a method that contains a loop - each Variant ' +
                    'operation goes through COM-VarType-dispatch (~10-100x ' +
                    'slower than typed). Use a typed local variable for ' +
                    'hot-path computation.';
    L.SetKind(fkVariantTypeMisuse);
    Results.Add(L);
  end;

begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not HasLoopChild(M) then Continue;
      // Gate-A-Guard: nested Routinen sind im AST verworfen - die
      // Loop-Sicht ist blind, konservativ ALLE Kandidaten melden.
      var NestedBlind := M.HasDescendant(nkNestedRange);
      // Variant Locals + Params dieser Methode melden, wenn ihr Name
      // in einem Loop-Teilbaum vorkommt (Gate A).
      for Ch in M.Children do
      begin
        if not ((Ch.Kind in [nkLocalVar, nkParam]) and
                IsVariantType(Ch.TypeRef)) then Continue;
        if NestedBlind or (Ch.Name = '') or
           UsedInAnyLoop(M, LowerCase(Ch.Name)) then
          Emit(Ch.Line, Ch.Name, Ch.TypeRef, M.Name);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
