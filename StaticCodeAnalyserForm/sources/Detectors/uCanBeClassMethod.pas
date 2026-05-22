unit uCanBeClassMethod;

// Detektor: Instance-Methode greift weder auf Self noch auf Instanz-Felder
// zu - waere als `class function` / `class procedure` sauberer.
//
// Pattern (Code Smell, Sonar-50 #50):
//   TMath = class
//     function Add(A, B: Integer): Integer;
//   end;
//
//   function TMath.Add(A, B: Integer): Integer;
//   begin
//     Result := A + B;          // nutzt nur Parameter, kein Self
//   end;
//
// Korrekt:
//   TMath = class
//     class function Add(A, B: Integer): Integer; static;
//   end;
//
// Begruendung: eine Methode ohne Zugriff auf den Instanz-State braucht
// keinen impliziten Self-Parameter. Class-Method spart einen Pointer-
// Pass, macht den "stateless"-Charakter explizit, und kann ohne Objekt-
// Instanz aufgerufen werden.
//
// Erkennung (AST):
//   * nkMethod-Knoten mit echtem Body (kein Forward).
//   * Skip wenn TypeRef ';class' (schon class method).
//   * Skip wenn TypeRef ';virtual'/';abstract'/';override'/';dynamic'
//     - virtual-Methoden haben Polymorphismus-Vertrag, dort macht
//     class-method-Refactoring keinen Sinn.
//   * Walk descendants: Identifier 'self' kommt vor -> ist Instance-
//     Methode legitim. ODER ein Field-Read/-Write der Form 'F<Name>'
//     oder 'F<Name>.<X>' -> ebenfalls Instance.
//   * Sonst: Finding.
//
// Limitierungen:
//   * Cross-method-Aufruf wie `Self.Bar(...)` auf eine Sibling-Methode
//     muss als Self-Zugriff erkannt werden - wir matchen jeden Identifier
//     namens 'self' (case-insensitive). Property-Read `MyProp` ohne
//     Self.-Prefix wird als legitimer Instance-Zugriff via Property
//     erkannt - der Property-Lookup-Zugriff laeuft ueber das Instance-
//     Layout, also implizit ueber Self. Heuristik: das pruefen wir
//     nicht; FP-Risiko bei Properties ohne Self.-Prefix.
//   * Methoden-Aufruf `Foo` ohne Self. (in Pascal legal) - kann sowohl
//     class als auch instance methods rufen. Wir flaggen das nicht,
//     wenn Self ansonsten gar nicht vorkommt.
//
// Schweregrad: lsHint - Refactoring-Hinweis, kein Bug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCanBeClassMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils;

function IsAlreadyClassMethod(MethodNode: TAstNode): Boolean;
begin
  Result := Pos(';class', LowerCase(MethodNode.TypeRef)) > 0;
end;

function IsPolymorphicMethod(MethodNode: TAstNode): Boolean;
var
  Low : string;
begin
  Low := LowerCase(MethodNode.TypeRef);
  Result := (Pos(';virtual',  Low) > 0)
         or (Pos(';override', Low) > 0)
         or (Pos(';dynamic',  Low) > 0)
         or (Pos(';abstract', Low) > 0);
end;

function HasBodyBlock(MethodNode: TAstNode): Boolean;
// Methode hat einen Body wenn entweder
//   * nkBlock als direktes Child (ParseBlock-Wrapper um `begin..end`), oder
//   * eine Body-Statement-Kind direkt darin steht (defensiv, alte AST-Form).
// Forward-Declarations ohne `begin` haben keinen nkBlock und werden
// korrekt geskippt.
var Child: TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
    if (Child.Kind = nkBlock) or
       (Child.Kind in [nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt,
                       nkWhileStmt, nkRepeatStmt, nkTryExcept, nkTryFinally,
                       nkRaise, nkExit, nkInherited, nkLocalVar]) then
      Exit(True);
end;

// True wenn IRGENDWO im Subtree der Identifier 'self' (case-insensitive)
// vorkommt oder ein Field-Reference der Form 'F<Buchstabe>' (klassische
// Delphi-Konvention fuer Felder).
function HasSelfOrFieldAccess(N: TAstNode): Boolean;
var
  Child : TAstNode;
  NameLow : string;
begin
  NameLow := LowerCase(N.Name);
  if NameLow = 'self' then Exit(True);
  // Field-Konvention: 'F' + Grossbuchstabe + Rest, OHNE Punkt
  // (dann waere es ein Method-Receiver wie 'TFoo.Bar').
  if (Length(N.Name) >= 2) and (N.Name[1] = 'F')
     and CharInSet(N.Name[2], ['A'..'Z'])
     and (Pos('.', N.Name) = 0) then
    Exit(True);
  // Field-Zugriff mit Self.<Field>-Prefix
  if StartsText('self.', N.Name) then Exit(True);
  // Inherited zaehlt als Polymorphie-Indikator (sollte vorher bereits
  // ueber TypeRef geskippt sein, hier defensiv).
  if N.Kind = nkInherited then Exit(True);
  for Child in N.Children do
    if HasSelfOrFieldAccess(Child) then Exit(True);
  Result := False;
end;

// Method-Header gehoert zu einer Klasse wenn der Name ein Punkt enthaelt:
// 'TFoo.Bar' -> ja. Standalone procedures ohne Owner-Klasse haben keinen
// Punkt und sind nicht refactorbar.
function BelongsToClass(MethodNode: TAstNode): Boolean;
begin
  Result := Pos('.', MethodNode.Name) > 0;
end;

class procedure TCanBeClassMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not BelongsToClass(M) then Continue;
      if IsAlreadyClassMethod(M) then Continue;
      if IsPolymorphicMethod(M) then Continue;
      if not HasBodyBlock(M) then Continue;
      // Skip Constructor/Destructor - die haben implizit anderen Vertrag.
      if LowerCase(Trim(M.TypeRef)).StartsWith('constructor') then Continue;
      if LowerCase(Trim(M.TypeRef)).StartsWith('destructor')  then Continue;
      if HasSelfOrFieldAccess(M) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        'Method %s never accesses Self or instance fields - could be declared as `class function`',
        [M.Name]);
      F.SetKind(fkCanBeClassMethod);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
