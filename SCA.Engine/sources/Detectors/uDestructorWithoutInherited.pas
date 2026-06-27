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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TDestructorWithoutInheritedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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
  LineNo: Integer; AContext: TAnalyzeContext): Boolean;
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
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
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

// True wenn der Method-Body effektiv leer ist (`begin end;` ohne
// irgendein Statement). Wird fuer den PScript-Stub-File-Skip benutzt.
function IsEffectivelyEmptyBody(MethodNode: TAstNode): Boolean;
var
  Child : TAstNode;
  GrandChild : TAstNode;
begin
  Result := True;
  for Child in MethodNode.Children do
  begin
    case Child.Kind of
      nkBlock:
        for GrandChild in Child.Children do
          if GrandChild.Kind in [nkAssign, nkCall, nkIfStmt, nkCaseStmt,
                                  nkForStmt, nkWhileStmt, nkRepeatStmt,
                                  nkTryExcept, nkTryFinally, nkRaise, nkExit,
                                  nkBreak, nkContinue, nkInherited] then
            Exit(False);
      nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt, nkWhileStmt,
      nkRepeatStmt, nkTryExcept, nkTryFinally, nkRaise, nkExit,
      nkBreak, nkContinue, nkInherited:
        Exit(False);
    end;
  end;
end;

class procedure TDestructorWithoutInheritedDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
// Real-World-Sweep 2026-06-13: cnwizards/Bin/PSDeclEx/CnWizClasses.pas
// 6 SCA097 FPs - alle leere Destructor-Bodies in PScript-Bridge-Stubs.
// Gleiche Heuristik wie uRoutineResultAssigned: wenn >=5 effektiv-
// leere Method-Bodies UND >70% empty/total Ratio in der Unit, dann
// PScript-Stub-File und keine Findings emittieren.
const
  STUB_FILE_MIN_EMPTY   = 5;
  STUB_FILE_RATIO_LIMIT = 0.7;
var
  Methods           : TList<TAstNode>;
  M                 : TAstNode;
  F                 : TLeakFinding;
  EmptyCount, Total : Integer;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    EmptyCount := 0;
    Total      := 0;
    for M in Methods do
    begin
      if FindBodyBlock(M) = nil then Continue;
      Inc(Total);
      if IsEffectivelyEmptyBody(M) then Inc(EmptyCount);
    end;
    if (EmptyCount >= STUB_FILE_MIN_EMPTY) and (Total > 0) and
       (EmptyCount / Total > STUB_FILE_RATIO_LIMIT) then
      Exit;  // PScript-Stub-File - keine Findings emittieren

    for M in Methods do
    begin
      if not IsDestructor(M) then Continue;
      // Nur echte Implementierungen pruefen - Forward-Decls in Class-Bodies
      // haben kein nkBlock und wuerden sonst falsch-positiv anschlagen.
      if FindBodyBlock(M) = nil then Continue;
      // Source-Line-Fallback: Parser verfehlt manchmal die ';class'-
      // Markierung bei impl-level class-destructors (MVCFramework.Commons
      // TMVCSqids.Destroy). Direkt am Source pruefen.
      if IsClassDestructorByLine(FileName, M.Line, AContext) then Continue;
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
