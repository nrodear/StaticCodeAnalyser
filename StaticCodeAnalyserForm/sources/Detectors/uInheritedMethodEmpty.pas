unit uInheritedMethodEmpty;

// Detektor: override-Methode deren gesamter Body nur `inherited;` ist.
//
// Pattern (Code-Smell):
//   procedure TFoo.Bar; override;
//   begin
//     inherited;   // <-- nichts weiter
//   end;
//
// Korrekt: Override komplett LOESCHEN. Wenn die abgeleitete Klasse keine
// eigene Logik hat, ist das Override nur Dispatch-Slot-Verbrauch ohne
// Mehrwert. Der Compiler ruft die Parent-Methode ohnehin direkt.
//
// Folge:
//   * VMT-Slot-Verbrauch ohne Gegenleistung
//   * Ein Reader denkt "da steht ein Override, also passiert hier etwas
//     Wichtiges" - liest den Code, sieht aber nur den Bypass. Verlangsamt
//     Code-Reviews.
//   * Beim Refactoring der Parent-Klasse muss man trotzdem alle leeren
//     Overrides anschauen ob noch sie noch Sinn machen - obwohl sie
//     nichts tun.
//
// Erkennung (AST-basiert, single-method):
//   * MNode.TypeRef enthaelt ';override' (case-insensitive)
//   * Skip bodyless (abstract/forward/external) - das sind keine
//     Definitionen.
//   * Nicht-Param-Children des MNode bilden den Body. Wenn genau EIN
//     Body-Statement existiert UND das ist nkInherited mit leerem
//     Argument-Namen ODER mit Argument-Name == Method-Name -> Finding.
//
// Bewusst NICHT Finding:
//   * `inherited;` plus weitere Statements (Method tut auch etwas Eigenes).
//   * `inherited Foo(SomethingDifferent);` (rufed bewusst andere Variante
//     des Parent auf - das ist ein Use-Case fuer Method-Hijacking).
//   * Leerer Body (kein inherited) - faengt EmptyRoutineCheck.
//
// Sonar-Pendant: InheritedMethodWithNoCodeCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   InheritedMethodWithNoCodeCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInheritedMethodEmptyDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// Hat das Method-TypeRef ';override' als Direktive?
function IsOverride(const TypeRef: string): Boolean;
begin
  Result := Pos(';override', LowerCase(TypeRef)) > 0;
end;

// Bodyless = abstract / forward / external / dispid - keine Implementation.
function IsBodyless(const TypeRef: string): Boolean;
var Low: string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';abstract', Low) > 0) or
            (Pos(';forward',  Low) > 0) or
            (Pos(';external', Low) > 0) or
            (Pos(';dispid',   Low) > 0);
end;

// Unqualifiziertes Letzt-Segment - 'TFoo.Bar' -> 'Bar'.
function UnqualifiedName(const MethName: string): string;
var i: Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

// Liefert den ersten Identifier aus einem Call-Ausdruck.
// 'Foo' -> 'Foo'; 'Foo(args)' -> 'Foo'; '' -> ''.
function FirstIdent(const Expr: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(Expr) do
  begin
    case Expr[i] of
      'A'..'Z', 'a'..'z', '_', '0'..'9':
        Result := Result + Expr[i];
    else
      Exit;
    end;
  end;
end;

class procedure TInheritedMethodEmptyDetector.AnalyzeMethod(
  MethodNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  TypeRef     : string;
  i           : Integer;
  Child       : TAstNode;
  BodyCount   : Integer;
  TheOnly     : TAstNode;
  InheritArg  : string;
  MethShort   : string;
  F           : TLeakFinding;
begin
  TypeRef := MethodNode.TypeRef;
  if not IsOverride(TypeRef) then Exit;
  if IsBodyless(TypeRef) then Exit;

  // Body-Statements zaehlen (alles ausser nkParam).
  BodyCount := 0;
  TheOnly   := nil;
  for i := 0 to MethodNode.Children.Count - 1 do
  begin
    Child := MethodNode.Children[i];
    if Child.Kind = nkParam then Continue;
    Inc(BodyCount);
    TheOnly := Child;
    if BodyCount > 1 then Break;  // mehr als 1 Statement -> nicht relevant
  end;

  if BodyCount <> 1 then Exit;
  if TheOnly.Kind <> nkInherited then Exit;

  // inherited mit leerem Argument ODER inherited <selber Method-Name>:
  // beides bedeutet "nur Bypass".
  InheritArg := Trim(TheOnly.Name);
  MethShort  := UnqualifiedName(MethodNode.Name);
  if InheritArg <> '' then
  begin
    var ArgIdent := FirstIdent(InheritArg);
    if not SameText(ArgIdent, MethShort) then Exit;
  end;

  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethodNode.Name;
  F.LineNumber := IntToStr(MethodNode.Line);
  F.MissingVar := Format(
    'Override %s contains only "inherited" - remove the override entirely',
    [MethShort]);
  F.SetKind(fkInheritedMethodEmpty);
  Results.Add(F);
end;

class procedure TInheritedMethodEmptyDetector.AnalyzeUnit(UnitNode: TAstNode;
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
