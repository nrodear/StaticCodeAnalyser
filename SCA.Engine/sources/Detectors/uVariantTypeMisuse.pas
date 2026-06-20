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
//   * Wir flaggen Variant in JEDER Methode mit Loop, ohne zu pruefen ob
//     die Variant-Variable tatsaechlich im Loop genutzt wird. Variant-
//     Vars die nur einmal vor dem Loop gelesen werden sind kein
//     Performance-Problem - akzeptierter FP fuer einfache Detection.
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
  end;

implementation

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

class procedure TVariantTypeMisuseDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M, Ch   : TAstNode;
  F       : TLeakFinding;

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
      // Variant Locals + Params dieser Methode melden.
      for Ch in M.Children do
      begin
        if (Ch.Kind = nkLocalVar) and IsVariantType(Ch.TypeRef) then
          Emit(Ch.Line, Ch.Name, Ch.TypeRef, M.Name);
        if (Ch.Kind = nkParam) and IsVariantType(Ch.TypeRef) then
          Emit(Ch.Line, Ch.Name, Ch.TypeRef, M.Name);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
