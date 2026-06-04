unit uEmptyMethod;

// Detektor fuer Methoden ohne Anweisungen.
// Erkennt Implementations-Methoden mit leerem begin..end-Rumpf:
//
//   procedure TFoo.DoNothing;
//   begin
//   end;
//
// Abstract / virtual-Deklarationen ohne Body sind im AST gar nicht als
// Methoden mit nkBlock-Kind vertreten und werden also nicht gemeldet.
// Methoden mit nur einem 'inherited;' werden ebenfalls nicht gemeldet,
// weil das ein nkInherited-Kind im Block erzeugt.
//
// Schweregrad: lsHint - kein Bug, sondern unbeabsichtigt vergessener Code
// oder uebrig gebliebener Stub.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function FindBodyBlock(MethodNode: TAstNode): TAstNode; static;
  end;

implementation

class function TEmptyMethodDetector.FindBodyBlock(
  MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then
      Exit(Child);
end;

class procedure TEmptyMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Block   : TAstNode;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Block := FindBodyBlock(M);
      // Kein Body-Block (Forward / Interface-Decl / abstract) - nichts melden
      if Block = nil then Continue;
      // Body hat mindestens eine Anweisung - nicht leer
      if Block.Children.Count > 0 then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := 'Method body is empty';
      F.SetKind(fkEmptyMethod);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
