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
  uCompatSet,  // D11: THashSet<T>-Ersatz (D12: leere Unit, natives THashSet)
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

uses
  System.StrUtils;

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

function MethodHasDirective(const TypeRefLow, Directive: string): Boolean;
// Wortgrenz-Match einer Methoden-Direktive (z.B. 'override') im (bereits
// lowercase) TypeRef. TypeRef-Formen variieren ('function: string; override',
// 'procedure;virtual') - daher Wortgrenze statt nacktem Pos.
var
  P, L, DL : Integer;
  Before, After : Char;
begin
  Result := False;
  DL := Length(Directive); L := Length(TypeRefLow);
  P := 1;
  while True do
  begin
    P := PosEx(Directive, TypeRefLow, P);
    if P = 0 then Exit;
    if P > 1 then Before := TypeRefLow[P - 1] else Before := #0;
    if P + DL - 1 < L then After := TypeRefLow[P + DL] else After := #0;
    if not CharInSet(Before, ['a'..'z', '0'..'9', '_']) and
       not CharInSet(After,  ['a'..'z', '0'..'9', '_']) then Exit(True);
    P := P + DL;
  end;
end;

function MethodHasAnyContractDirective(const TypeRefLow: string): Boolean;
// Polymorphe/Vertrags-Direktiven, die die Signatur fixieren -> string-Param
// kann nicht lokal auf const umgestellt werden (Basisklasse/Interface-Vertrag).
begin
  Result := MethodHasDirective(TypeRefLow, 'virtual')  or MethodHasDirective(TypeRefLow, 'override') or
            MethodHasDirective(TypeRefLow, 'dynamic')  or MethodHasDirective(TypeRefLow, 'message')  or
            MethodHasDirective(TypeRefLow, 'abstract') or MethodHasDirective(TypeRefLow, 'reintroduce');
end;

function UnqualifiedName(const N: string): string;
// 'TFoo.Bar' -> 'bar', 'Bar' -> 'bar' (lowercase, fuer Decl<->Impl-Matching).
var Dot : Integer;
begin
  Dot := LastDelimiter('.', N);
  if Dot > 0 then Result := LowerCase(Copy(N, Dot + 1, MaxInt))
             else Result := LowerCase(N);
end;

function IsEventHandlerMethod(M: TAstNode): Boolean;
// Event-Handler-Form: erster Param 'Sender' bzw. Typ TObject - per Event-Typ
// /DFM gebunden, Signatur nicht aenderbar.
var Child : TAstNode;
begin
  Result := False;
  for Child in M.Children do
  begin
    if Child.Kind <> nkParam then Continue;
    if SameText(Child.Name, 'Sender')
       or (Pos('tobject', LowerCase(Child.TypeRef)) > 0) then Exit(True);
    Break;                               // nur ersten Parameter pruefen
  end;
end;

class procedure TConstStringParameterDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods   : TList<TAstNode>;
  PolyNames : THashSet<string>;
  M, P      : TAstNode;
  F         : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  PolyNames := THashSet<string>.Create;
  try
    // 1. Durchlauf: Namen aller polymorphen Method-Decls sammeln. Die Direktive
    //    (virtual/override/...) steht i.d.R. nur auf der Interface-Decl, NICHT
    //    auf dem Implementierungs-Header (der die Params traegt) -> ueber den
    //    Namen matchen, damit beide Seiten als vertrags-fixiert gelten.
    for M in Methods do
      if MethodHasAnyContractDirective(LowerCase(M.TypeRef)) then
        PolyNames.Add(UnqualifiedName(M.Name));

    for M in Methods do
    begin
      // Vertrags-fixierte Signaturen (polymorph via Name-Match / Event-Handler)
      // ueberspringen - dort ist const nicht lokal umstellbar (dominante FP-Klasse).
      if PolyNames.Contains(UnqualifiedName(M.Name)) then Continue;
      if IsEventHandlerMethod(M) then Continue;
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
    end;
  finally
    PolyNames.Free;
    Methods.Free;
  end;
end;

end.
