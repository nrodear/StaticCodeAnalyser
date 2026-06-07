unit uDestructorWithoutInherited;

// Detektor fuer Destruktoren ohne `inherited`-Aufruf.
//
// SonarDelphi-Aequivalent: communitydelphi:DestructorWithoutInherited.
// Ein Destruktor MUSS `inherited Destroy` (oder `inherited;`) aufrufen,
// damit die Parent-Klasse aufraeumen kann (eigene Felder freigeben,
// notify-Handler abmelden, Refcounting korrekt). Vergessen -> Speicher-
// und Resource-Leaks.
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten mit TypeRef `destructor`
// pruefen ob `nkInherited` im Body vorkommt.
//
// Schweregrad: lsError - vergessenes `inherited` im Destruktor ist
// fast immer ein Leak.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDestructorWithoutInheritedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.Classes, System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

function IsDestructor(MethodNode: TAstNode): Boolean; inline;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  // `class destructor` ist ein Klassen-Initialisierungs-Mechanismus (laeuft
  // einmal pro Klasse beim Modul-Unload) - hat KEINE inheritance chain und
  // braucht daher KEIN `inherited`. Parser markiert die mit ';class'-Suffix
  // im TypeRef (sowohl in der Class-Body- als auch in der Implementation-
  // Section). Skip wenn dieser Marker vorhanden.
  if Pos(';class', TR) > 0 then Exit(False);
  Result := TR.StartsWith('destructor');
end;

function IsClassDestructorByLine(const FileName: string;
  LineNo: Integer): Boolean;
// Fallback wenn der Parser die ';class'-Markierung verfehlt
// (z.B. MVCFramework.Commons.pas TMVCSqids.Destroy). Liest die Source-Zeile
// und prueft auf 'class destructor' am linken Rand (Whitespace egal).
var
  Lines : TStringList;
  Cached : Boolean;
  Line : string;
  Trimmed : string;
begin
  Result := False;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    if (LineNo < 1) or (LineNo > Lines.Count) then Exit;
    Line := Lines[LineNo - 1];
    Trimmed := LowerCase(TrimLeft(Line));
    Result := StartsStr('class destructor', Trimmed);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

// Liefert den Body-Block (nkBlock) der Methode oder nil wenn keiner da
// ist. Forward-Deklarationen in Class-Bodies (`destructor Destroy;
// override;`) sind nkMethod-Knoten ohne nkBlock - wir muessen die
// ausnehmen, sonst feuert der Detektor auf der Signatur statt auf der
// Implementierung. Pattern aus uEmptyMethod uebernommen.
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

class procedure TDestructorWithoutInheritedDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      if not IsDestructor(M) then Continue;
      // Nur echte Implementierungen pruefen - Forward-Decls in Class-Bodies
      // haben kein nkBlock und wuerden sonst falsch-positiv anschlagen.
      if FindBodyBlock(M) = nil then Continue;
      // Source-Line-Fallback: Parser verfehlt manchmal die ';class'-
      // Markierung bei impl-level class-destructors (MVCFramework.Commons
      // TMVCSqids.Destroy). Direkt am Source pruefen.
      if IsClassDestructorByLine(FileName, M.Line) then Continue;
      if HasInheritedCall(M) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := 'Destructor has no `inherited` call - parent ' +
        'class cleanup is skipped, likely leak. Add `inherited Destroy;` ' +
        'or `inherited;` at the end of the body.';
      F.SetKind(fkDestructorWithoutInherited);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
