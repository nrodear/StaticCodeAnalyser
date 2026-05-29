unit uLeakInConstructor;

// Detektor: Constructor weist Felder via .Create zu UND raised - bei raise
// nach partieller Initialisierung leaken die schon erzeugten Felder.
//
// Pattern (Bug, Sonar-50 #12):
//   constructor TFoo.Create;
//   begin
//     FA := TStringList.Create;
//     FB := TOtherThing.Create;     // angenommen wirft hier
//     if not Valid then
//       raise EInvalidInput.Create('bad');   // <-- FA leakt
//   end;
//
// Korrekt:
//   constructor TFoo.Create;
//   begin
//     FA := TStringList.Create;
//     try
//       FB := TOtherThing.Create;
//       if not Valid then
//         raise EInvalidInput.Create('bad');
//     except
//       FreeAndNil(FA);
//       raise;
//     end;
//   end;
//
// Alternative: das Delphi-RTL ruft Destroy auf der halb-konstruierten
// Instanz, wenn der Constructor wirft - aber NUR wenn `inherited Create`
// schon gelaufen ist. Field-Cleanup im Destructor faengt das auf, ist
// aber fehleranfaellig (Destructor muss nil-tolerant sein).
//
// Erkennung (within-method, heuristisch):
//   * Pro Constructor-Implementierung (TypeRef startet mit 'constructor',
//     KEIN ';class'-Marker).
//   * Body enthaelt mindestens einen nkAssign mit LHS = `F<Name>` oder
//     `Self.F<Name>` und RHS = `<Class>.Create(...)`.
//   * Body enthaelt mindestens einen nkRaise dessen Vorfahr KEIN
//     nkExceptBlock / nkOnHandler ist (also Raise auf Top-Level oder in
//     try/finally - beide problematisch wenn Field-Init davor lief).
//   * Body enthaelt KEIN nkTryExcept das die kritische Region umschliesst
//     (Heuristik: wenn nkTryExcept im Body vorkommt, vertrauen wir dem
//     Author - kein Befund).
//
// Limitierungen:
//   * Keine echte Flow-Analyse: 'raise BEVOR field-init' wird trotzdem
//     geflaggt.
//   * try/except, das nur einen Teil der Felder schuetzt, wird als
//     "schuetzt alles" interpretiert.
//   * `inherited Create(...)` als erste Zeile + raise danach: die RTL
//     ruft Destroy auf der halb-konstruierten Instanz; wir flaggen das
//     dennoch, weil ein Destructor-basierter Cleanup nicht garantiert ist.
//
// Schweregrad: lsError - leak im Exception-Pfad ist real.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLeakInConstructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

function IsConstructorImpl(MethodNode: TAstNode): Boolean;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  Result := TR.StartsWith('constructor') and (Pos(';class', TR) = 0);
end;

function HasBodyBlock(MethodNode: TAstNode): Boolean;
const
  STMT_KINDS = [nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt,
                nkWhileStmt, nkRepeatStmt, nkTryExcept, nkTryFinally,
                nkRaise, nkExit, nkInherited, nkLocalVar];
var
  Child, Inner : TAstNode;
begin
  // Body-Detection: irgendein Statement-artiger Descendant. Forward-Decls
  // im Class-Body haben keinen Body.
  // Parser wickelt `begin ... end` in ein nkBlock-Kind ein - eine Ebene
  // tiefer schauen, sonst sehen wir bei impl-Bodies nur nkBlock und
  // verpassen den Body komplett (Audit V5, 2026-05-30).
  Result := False;
  for Child in MethodNode.Children do
  begin
    if Child.Kind in STMT_KINDS then Exit(True);
    if Child.Kind = nkBlock then
      for Inner in Child.Children do
        if Inner.Kind in STMT_KINDS then Exit(True);
  end;
end;

function LooksLikeFieldCreate(N: TAstNode): Boolean;
// True wenn der nkAssign so aussieht: F<X> := <Class>.Create(...) oder
// Self.F<X> := <Class>.Create(...). Heuristik ueber LHS-Form + RHS-Substring.
var
  Lhs, Rhs : string;
begin
  Lhs := LowerCase(Trim(N.Name));
  // Strip whitespace / komplexe Indexer waeren overkill - wir matchen die
  // 90%-Variante: Identifier (optional Self.-Prefix) der mit 'f' beginnt.
  if Lhs.StartsWith('self.') then Lhs := Copy(Lhs, 6, MaxInt);
  if (Length(Lhs) < 2) or (Lhs[1] <> 'f') then Exit(False);
  // RHS ist im AST nicht direkt verfuegbar - wir koennen aber pruefen,
  // ob unter dem nkAssign ein nkCall mit Name endend auf '.create' liegt.
  // Walk descendants once.
  Rhs := '';
  for var Child in N.Children do
    if Child.Kind = nkCall then
    begin
      Rhs := LowerCase(Child.Name);
      Break;
    end;
  Result := (Rhs <> '') and (Pos('.create', Rhs) > 0);
end;

function HasFieldCreate(MethodNode: TAstNode): Boolean;
var
  Assigns : TList<TAstNode>;
  N       : TAstNode;
begin
  Result := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
      if LooksLikeFieldCreate(N) then Exit(True);
  finally
    Assigns.Free;
  end;
end;

function HasRaise(MethodNode: TAstNode): Boolean;
var
  Raises : TList<TAstNode>;
begin
  Raises := MethodNode.FindAll(nkRaise);
  try
    Result := Raises.Count > 0;
  finally
    Raises.Free;
  end;
end;

function HasProtectingTryExcept(MethodNode: TAstNode): Boolean;
var
  Tries : TList<TAstNode>;
begin
  Tries := MethodNode.FindAll(nkTryExcept);
  try
    Result := Tries.Count > 0;
  finally
    Tries.Free;
  end;
end;

class procedure TLeakInConstructorDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      if not IsConstructorImpl(M) then Continue;
      if not HasBodyBlock(M) then Continue;
      if not HasFieldCreate(M) then Continue;
      if not HasRaise(M) then Continue;
      if HasProtectingTryExcept(M) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar :=
        'Constructor allocates fields and raises without try/except - ' +
        'partially-initialized fields leak on the exception path';
      F.SetKind(fkLeakInConstructor);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
