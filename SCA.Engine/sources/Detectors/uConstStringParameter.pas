unit uConstStringParameter;

// Detektor: string-Parameter ohne const-Modifier.
//
// Hintergrund (Delphi-Compiler-Semantik):
//   procedure Foo(s: string);          // ohne const: Refcount-Bump beim
//                                      // Caller + ggf. Copy bei Mutation
//   procedure Foo(const s: string);    // mit const: kein Refcount-Bump,
//                                      // pure Reference. Schneller.
// Ausserdem ist `s := ...` im Body ohne const eine LOKALE Aenderung
// (Caller sieht nichts), MIT const ein Compiler-Fehler -> klare Semantik.
//
// Erkennung (AST):
//   * nkParam mit TypeRef in {'string','ansistring','unicodestring',
//     'widestring','rawbytestring','shortstring'}.
//   * Modifier-Prefix steckt in Name als 'const X' / 'var X' / 'out X' /
//     'array of X' (uParser2 setzt das so). Wenn KEIN 'const ', 'var ',
//     'out ' Prefix vorhanden -> Finding.
//   * 'var' und 'out' sind explizite Mutability-Signaturen, daher kein
//     Finding (User WILL Mutation).
//
// FP-Reduktion:
//   * `result: string` als nkParam? uParser2 macht das ueber den Method-
//     Header-Return-Type, nicht ueber nkParam. Sollte keinen FP geben.
//   * Eventuelle 'array of string': moeglicherweise wuerde array of string
//     ohne const auch geflagt - tolerierbar (Performance-Hinweis bleibt).
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConstStringParameterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function IsStringType(const TypeRef: string): Boolean; static;
    class function HasMutModifier(const Name: string): Boolean; static;
  end;

implementation

const
  STRING_TYPES : array[0..5] of string = (
    'string', 'ansistring', 'unicodestring',
    'widestring', 'rawbytestring', 'shortstring'
  );

class function TConstStringParameterDetector.IsStringType(
  const TypeRef: string): Boolean;
var
  Low : string;
  T   : string;
begin
  Result := False;
  Low := LowerCase(Trim(TypeRef));
  for T in STRING_TYPES do
    if Low = T then Exit(True);
end;

class function TConstStringParameterDetector.HasMutModifier(
  const Name: string): Boolean;
// True wenn Name mit 'const ', 'var ', 'out ' beginnt (uParser2-Konvention).
var
  Low : string;
begin
  Low := LowerCase(Name);
  Result := Low.StartsWith('const ') or
            Low.StartsWith('var ')   or
            Low.StartsWith('out ');
end;

class procedure TConstStringParameterDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M, P    : TAstNode;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      for P in M.Children do
      begin
        if P.Kind <> nkParam then Continue;
        if not IsStringType(P.TypeRef) then Continue;
        if HasMutModifier(P.Name) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(P.Line);
        F.MissingVar := 'Parameter "' + P.Name + ': ' + P.TypeRef +
                        '" should be declared as `const` - avoids the ' +
                        'refcount bump on each call and clarifies that the ' +
                        'method does not mutate the argument.';
        F.SetKind(fkConstStringParameter);
        Results.Add(F);
      end;
  finally
    Methods.Free;
  end;
end;

end.
