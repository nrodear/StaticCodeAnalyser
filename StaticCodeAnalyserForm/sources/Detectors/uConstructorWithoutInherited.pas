unit uConstructorWithoutInherited;

// Detektor fuer Konstruktoren ohne `inherited`-Aufruf.
//
// SonarDelphi-Aequivalent: communitydelphi:ConstructorWithoutInherited.
// Ein Konstruktor MUSS in der Regel `inherited Create` oder `inherited;`
// aufrufen, damit die Parent-Klasse korrekt initialisiert wird. Fehlt
// der Aufruf, bleibt das geerbte State undefiniert (zumeist mit nil-
// Feldern oder Default-Werten, was zu Folgefehlern fuehrt).
//
// Ausnahmen:
//   * Konstruktoren mit `override`-Direktive die explizit den Parent
//     NICHT aufrufen wollen sind selten - im Zweifel auf Suppression
//     ueber `// noinspection` umschalten.
//   * `class constructor`-Class-Initialisierungs-Mechanismus (TypeRef
//     traegt `;class`-Suffix) - hat keine inheritance-chain.
//   * Top-level standalone constructor ausserhalb einer Klasse
//     (z.B. in Demo-/Fixture-Files) - Methoden-Name ist unqualifiziert
//     (kein '.'), es gibt schlicht keine Parent-Klasse. Compiler-Code
//     ist solche Konstruktion ohnehin invalid, aber Parser ist permissiv;
//     wir schweigen statt FP zu produzieren.
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten mit TypeRef
// `constructor ...` pruefen, ob im Body `nkInherited` vorkommt.
//
// Schweregrad: lsWarning - Bug-Risiko aber kein sofortiger Crash.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConstructorWithoutInheritedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsWarning;

function IsConstructor(MethodNode: TAstNode): Boolean; inline;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  // `class constructor` ist ein Klassen-Initialisierungs-Mechanismus (laeuft
  // einmal pro Klasse beim Modul-Initialize) - hat KEINE inheritance chain
  // und braucht daher KEIN `inherited`. Parser markiert die mit ';class'-
  // Suffix im TypeRef (sowohl in der Class-Body- als auch in der
  // Implementation-Section). Skip wenn dieser Marker vorhanden.
  if Pos(';class', TR) > 0 then Exit(False);
  Result := TR.StartsWith('constructor');
end;

// Liefert den Body-Block (nkBlock) oder nil wenn die Methode nur eine
// Forward-Decl (Class-Body-Signatur) ist. Pattern aus uEmptyMethod.
function FindBodyBlock(MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then Exit(Child);
end;

function HasInheritedCall(Node: TAstNode): Boolean;
var
  Child : TAstNode;
begin
  Result := False;
  if Node = nil then Exit;
  if Node.Kind = nkInherited then Exit(True);
  for Child in Node.Children do
    if HasInheritedCall(Child) then Exit(True);
end;

class procedure TConstructorWithoutInheritedDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      if not IsConstructor(M) then Continue;
      // Top-level Standalone-Konstruktor (kein Dot im Name) hat keine
      // Parent-Klasse - `inherited` waere syntaktisch unsinnig. Klassen-
      // Methoden-Implementierungen tragen den Klassen-Qualifier mit Punkt
      // (z.B. 'TFoo.Create'), die werden weiter geprueft.
      if Pos('.', M.Name) = 0 then Continue;
      // Nur echte Implementierungen pruefen - Forward-Decls (Class-Body-
      // Signatur) haben kein nkBlock, dort gehoert `inherited` nicht hin.
      if FindBodyBlock(M) = nil then Continue;
      if HasInheritedCall(M) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := 'Constructor has no `inherited` call - parent ' +
        'class is not initialized. Add `inherited Create(...)` or ' +
        '`inherited;` (use // noinspection if intentional).';
      F.SetKind(fkConstructorWithoutInherited);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
