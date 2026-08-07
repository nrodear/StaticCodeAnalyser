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
      const FileName, PasFileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, MultipleExit, NestedTry, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses
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
  Index: TDfmRepoIndex; const FileName, PasFileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Shadow : TDictionary<string, Boolean>;

  // Haertung 2026-08-09 (Stichprobe nach dem Erwecken: 2/6 FP): der
  // Repo-Index ist NAMENS-basiert - jede lokale Variable/jeder Parameter,
  // der zufaellig wie irgendeine Form-Var im Korpus heisst ('List',
  // 'Frm', ...), wurde als Kopplung gemeldet. Unit-weites Shadow-Set
  // aus allen nkLocalVar/nkParam/nkField-Namen: was hier deklariert
  // ist, bindet lokal und ist NIE die fremde Global-Instanz.
  // (Konservativ Richtung Praezision: eine echte Cross-Form-Var, die
  // gleichnamig zu irgendeiner Lokalen ist, faellt als FN weg.)
  procedure CollectShadow(Kind: TNodeKind);
  var
    L : TList<TAstNode>;
    N : TAstNode;
    S : string;
    P : Integer;
  begin
    L := Binding.UnitNode.FindAll(Kind);
    try
      for N in L do
      begin
        // nkParam.Name kann Modifier tragen ('out X', 'var X') -
        // letztes Wort ist der Name.
        S := Trim(N.Name);
        P := LastDelimiter(' ', S);
        if P > 0 then S := Copy(S, P + 1, MaxInt);
        if S <> '' then Shadow.AddOrSetValue(LowerCase(S), True);
      end;
    finally
      L.Free;
    end;
  end;

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
    // Lokal deklarierte Namen binden lokal - nie die fremde Instanz.
    if Shadow.ContainsKey(LowerCase(Ident)) then Exit;

    if not Index.TryGetVarType(Ident, Info) then Exit;

    // Eigene Klasse? (Falls Form-Var in derselben Unit deklariert ist und
    // der Code im interface-Teil auf sich selbst referenziert.)
    if (Binding <> nil) and (Binding.FormClass <> nil)
       and SameText(Info.ClassRef, Binding.FormClass.Name) then Exit;

    // In der EIGENEN Unit deklarierte Var (z.B. zweite Form-Instanz der
    // selben Datei) ist keine CROSS-Form-Kopplung.
    if (PasFileName <> '') and
       SameText(ExtractFileName(Info.Unitname), ExtractFileName(PasFileName)) then Exit;

    F            := TLeakFinding.Create;
    // Anker auf die .pas: der Zugriff steht im CODE, nicht in der DFM
    // (Haertung 2026-08-09; vorher zeigten Funde auf DFM-Zeilennummern).
    if PasFileName <> '' then
      F.FileName := PasFileName
    else
      F.FileName := FileName;
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

  Shadow := TDictionary<string, Boolean>.Create;
  try
    CollectShadow(nkLocalVar);
    CollectShadow(nkParam);
    CollectShadow(nkField);

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
  finally
    Shadow.Free;
  end;
end;

end.
