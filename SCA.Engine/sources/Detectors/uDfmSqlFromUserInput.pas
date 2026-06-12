unit uDfmSqlFromUserInput;

// Detektor: SQL-Property einer DB-Query wird aus einer UI-Input-Komponente
// konkateniert. Klassische SQL-Injection ueber Form-Field.
//
// Beispiel:
//   uMainForm.dfm:
//     object qFind: TADOQuery end
//     object edName: TEdit end
//   uMainForm.pas:
//     qFind.SQL.Text := 'SELECT * FROM users WHERE name=''' + edName.Text + '''';
//
// Der bestehende Pascal-Detektor 'uSQLInjection' sieht die String-Konkat,
// hat aber kein Wissen ueber die Komponenten-Typen. Mit dem FormBinder
// koennen wir Quelle (UI-Input) und Ziel (DB-Query) eindeutig
// identifizieren - hoehere Confidence, klarerer Befundtext.
//
// Heuristik (Phase 1 dieses Detektors):
//   1. Aus den published Fields der Form-Klasse die DB-Query-Felder
//      sammeln (TypeRef in einer Klassen-Whitelist).
//   2. Ebenso die UI-Input-Felder (TEdit, TMemo, ...).
//   3. Im Pascal-AST nach Assignments und Calls suchen, deren LHS bzw.
//      Call-Pfad eine SQL-Property auf einem DB-Query-Field ist.
//   4. Wenn der RHS / die Argument-Liste eine '+'-Konkat enthaelt und
//      darin ein '<UI-Field>.Text'-aehnliches Token vorkommt - Befund.
//
// Pragmatische Wahl: der Pascal-Parser legt nkAssign.Name (LHS-Pfad) und
// nkAssign.TypeRef (vollstaendige RHS-Expression als String) sowie
// nkCall.Name (kompletter Call inkl. Args) ab. Substring-Pattern-Matching
// reicht damit aus - kein eigenes Expression-Walking notwendig.
//
// Schweregrad: lsError, FindingType: ftVulnerability.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uFormBinder;

type
  TDfmSqlFromUserInputDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConsecutiveSection, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

const
  // DB-Komponenten mit SQL-aehnlicher Property. Bewusst auf Connection-
  // freie Klassen begrenzt (TADOConnection.Execute wuerde hier rauschen).
  DB_QUERY_CLASSES: array[0..6] of string = (
    'TADOQuery', 'TADOCommand', 'TADOStoredProc',
    'TFDQuery', 'TFDCommand',
    'TQuery', 'TSQLQuery'
  );

  // UI-Komponenten, deren Text-Property User-Input traegt.
  UI_INPUT_CLASSES: array[0..5] of string = (
    'TEdit', 'TLabeledEdit', 'TMemo', 'TRichEdit',
    'TComboBox', 'TMaskEdit'
  );

  // SQL-aehnliche Property-Suffixe auf einer DB-Query-Komponente.
  // '.SQL' deckt 'SQL.Text', 'SQL.Strings' und 'SQL.Add' (in nkCall).
  SQL_PROP_SUFFIXES: array[0..2] of string = (
    '.SQL', '.CommandText', '.MacroText'
  );

  // Text-aehnliche Property-Suffixe auf einer UI-Komponente.
  UI_TEXT_SUFFIXES: array[0..4] of string = (
    '.Text', '.Lines.Text', '.Caption', '.SelText', '.Value'
  );

class procedure TDfmSqlFromUserInputDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  function IsInList(const S: string; const Arr: array of string): Boolean;
  var X: string;
  begin
    for X in Arr do
      if SameText(S, X) then Exit(True);
    Result := False;
  end;

  function FindFieldHit(const Haystack: string; FieldList: TList<string>;
    const Suffixes: array of string; out HitName: string): Boolean;
  // Sucht <Field>+Suffix als Substring im Haystack. Liefert den
  // Original-Field-Namen (case-empfindlich, weil der Code typisch im
  // Original-Casing geschrieben ist).
  var
    Q, TP: string;
  begin
    Result := False;
    HitName := '';
    for Q in FieldList do
      for TP in Suffixes do
        if ContainsText(Haystack, Q + TP) then
        begin
          HitName := Q;
          Exit(True);
        end;
  end;

  procedure AddFinding(Node: TAstNode; const DbName, UiName, Why: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Binding.FormClass.Name;
    F.LineNumber := IntToStr(Node.Line);
    F.MissingVar := Format('%s (%s): %s built from %s.Text - parameterize instead',
                            [DbName, Why, DbName, UiName]);
    F.SetKind(fkDfmSqlFromUserInput);
    Results.Add(F);
  end;

var
  DbFields, UiFields : TList<string>;
  Pair               : TPair<string, TAstNode>;
  Field              : TAstNode;
  All                : TList<TAstNode>;
  Node               : TAstNode;
  Lhs, Rhs           : string;
  DbHit, UiHit       : string;
begin
  if Binding = nil then Exit;
  if Binding.FormClass = nil then Exit;
  if Binding.UnitNode = nil then Exit;

  DbFields := TList<string>.Create;
  UiFields := TList<string>.Create;
  try
    for Pair in Binding.PublishedFields do
    begin
      Field := Pair.Value;
      if IsInList(Trim(Field.TypeRef), DB_QUERY_CLASSES) then
        DbFields.Add(Field.Name)
      else if IsInList(Trim(Field.TypeRef), UI_INPUT_CLASSES) then
        UiFields.Add(Field.Name);
    end;

    if (DbFields.Count = 0) or (UiFields.Count = 0) then Exit;

    // ---- nkAssign: <Q>.SQL.Text := 'x' + edFoo.Text ----
    All := Binding.UnitNode.FindAll(nkAssign);
    try
      for Node in All do
      begin
        Lhs := Node.Name;
        Rhs := Node.TypeRef;

        if not FindFieldHit(Lhs, DbFields, SQL_PROP_SUFFIXES, DbHit) then Continue;
        if Pos('+', Rhs) = 0 then Continue;
        if not FindFieldHit(Rhs, UiFields, UI_TEXT_SUFFIXES, UiHit) then Continue;

        AddFinding(Node, DbHit, UiHit, 'SQL assignment');
      end;
    finally
      All.Free;
    end;

    // ---- nkCall: <Q>.SQL.Add('...' + edFoo.Text) ----
    All := Binding.UnitNode.FindAll(nkCall);
    try
      for Node in All do
      begin
        Lhs := Node.Name;
        // Bei Calls steht der ganze Aufruf-Ausdruck im Name-Feld inkl.
        // Argumenten - daher reicht ein einziger Substring-Test.
        if not FindFieldHit(Lhs, DbFields, SQL_PROP_SUFFIXES, DbHit) then Continue;
        if Pos('+', Lhs) = 0 then Continue;
        if not FindFieldHit(Lhs, UiFields, UI_TEXT_SUFFIXES, UiHit) then Continue;

        AddFinding(Node, DbHit, UiHit, 'SQL method call');
      end;
    finally
      All.Free;
    end;
  finally
    UiFields.Free;
    DbFields.Free;
  end;
end;

end.
