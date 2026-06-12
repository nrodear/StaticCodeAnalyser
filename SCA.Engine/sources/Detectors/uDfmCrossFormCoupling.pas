unit uDfmCrossFormCoupling;

// Detektor: Code in einer Form referenziert published Felder einer ANDEREN
// Form ueber deren globalen Form-Singleton.
//
// Beispiel (Kapselungsbruch):
//   uMainForm.pas
//     procedure TMainForm.btnSync;
//     begin
//       Form2.InternesEdit.Text := 'foo';   // <-- Cross-Form-Zugriff
//     end;
//
// Form2's published Field 'InternesEdit' ist nur deshalb published, weil
// DFM-Streaming es so will - es ist nicht als public API gedacht. Wenn
// Form1 sich dort einklinkt, verriegelt es interne Layout-Aenderungen
// auf Form2 (Field umbenannt -> stille Compile-Zeit-Fehler in Form1).
//
// Erkennung:
//   1. Der globale Repo-Index (uDfmRepoIndex) sagt: 'Form2' -> 'TForm2'.
//   2. Im Pascal-AST der aktuellen Unit suchen wir nkAssign / nkCall mit
//      Pattern '<VarName>.<Member>...'.
//   3. VarName ist eine im Repo-Index registrierte Form-Variable UND
//      gehoert nicht zur aktuell analysierten Form.
//   4. Befund mit Position der referenzierenden Stelle.
//
// Schweregrad: lsWarning, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uFormBinder, uDfmRepoIndex;

type
  TDfmCrossFormCouplingDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; Index: TDfmRepoIndex;
      const FileName: string; Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, MultipleExit, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function FirstIdent(const Expr: string): string;
// Extrahiert den ersten Identifier eines qualifizierten Pfads.
// 'Form2.Edit1.Text' -> 'Form2'. Funktioniert robust auf den
// String-Repraesentationen, die TParser2 in nkAssign.Name / nkCall.Name
// ablegt (vereinfachter "Primary"-Output ohne Whitespace).
var
  I, N : Integer;
begin
  Result := '';
  N := Length(Expr);
  if N = 0 then Exit;
  // Erstes Identifier-Zeichen finden (skipped fuehrende Klammern oder
  // Operatoren falls vorhanden).
  I := 1;
  while (I <= N) and not CharInSet(Expr[I], ['A'..'Z','a'..'z','_']) do
    Inc(I);
  if I > N then Exit;

  // Ident-Zeichen ansammeln, bis nicht-Ident-Zeichen kommt.
  while (I <= N) and CharInSet(Expr[I], ['A'..'Z','a'..'z','0'..'9','_']) do
  begin
    Result := Result + Expr[I];
    Inc(I);
  end;
end;

class procedure TDfmCrossFormCouplingDetector.Analyze(Binding: TFormBinding;
  Index: TDfmRepoIndex; const FileName: string;
  Results: TObjectList<TLeakFinding>);

  function IsCurrentFormVar(const VarName: string): Boolean;
  // 'Form2' und 'TForm2' beide als 'aktuelle Form' werten, damit Self-
  // referenzierung ueber die Singleton-Var nicht als Cross-Form gemeldet
  // wird. Falls Form-Klasse 'TMainForm', dann ist 'MainForm' die Var.
  var
    OwnClass: string;
  begin
    Result := False;
    if (Binding = nil) or (Binding.FormClass = nil) then Exit;
    OwnClass := Binding.FormClass.Name;
    // 'TMainForm' -> 'MainForm'
    if StartsText('T', OwnClass) then
      Result := SameText(VarName, Copy(OwnClass, 2, MaxInt));
  end;

  procedure CheckNode(Node: TAstNode; const Expr: string);
  var
    Ident   : string;
    Info    : TFormVarInfo;
    F       : TLeakFinding;
  begin
    Ident := FirstIdent(Expr);
    if Ident = '' then Exit;
    if IsCurrentFormVar(Ident) then Exit;

    if not Index.TryGetVarType(Ident, Info) then Exit;

    // Eigene Klasse? (Falls Form-Var in derselben Unit deklariert ist und
    // der Code im interface-Teil auf sich selbst referenziert.)
    if (Binding <> nil) and (Binding.FormClass <> nil)
       and SameText(Info.ClassRef, Binding.FormClass.Name) then Exit;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Node.Line);
    F.MissingVar := Format(
      'cross-form access: %s (%s, declared in %s) referenced as "%s"',
      [Info.VarName, Info.ClassRef, ExtractFileName(Info.Unitname), Expr]);
    F.SetKind(fkDfmCrossFormCoupling);
    Results.Add(F);
  end;

var
  All  : TList<TAstNode>;
  Node : TAstNode;
begin
  if Binding = nil then Exit;
  if Binding.UnitNode = nil then Exit;
  if (Index = nil) or (Index.VarCount = 0) then Exit;

  // nkAssign: LHS analysieren (z.B. 'Form2.Edit1.Text := X').
  All := Binding.UnitNode.FindAll(nkAssign);
  try
    for Node in All do
      // Cross-Form-Zugriff sieht typisch dotted aus. Reiner Ident-Assign
      // ('X := 1') ist hier nicht relevant.
      if Pos('.', Node.Name) > 0 then
        CheckNode(Node, Node.Name);
  finally
    All.Free;
  end;

  // nkCall: ganzen Call-Ausdruck analysieren (z.B. 'Form2.Refresh()').
  All := Binding.UnitNode.FindAll(nkCall);
  try
    for Node in All do
      if Pos('.', Node.Name) > 0 then
        CheckNode(Node, Node.Name);
  finally
    All.Free;
  end;
end;

end.
