unit uTestParamNameMismatch;

// Tests fuer SCA199 ParamNameMismatch.
//
// Zwei Ebenen:
//   * Scanner (uParamNameScan.ScanRoutine/PlaceholdersOf) direkt - jede
//     Regel des Vertrags einzeln, Ergebnis als kompakte Beschreibung
//     'A:Query.param@Zeile' / 'B:...' (A = ParamByName ohne Platzhalter,
//     B = Platzhalter ohne Zuweisung). Dieselben Faelle liefen vor dem
//     ersten Delphi-Bau im FPC-Pruefstand (54/54, 2026-10-07).
//   * Detektor ueber FindingsOfFile (echte Datei, AST fuer die
//     Routinengrenzen): Zeile, Kind, Schwere, geschachtelte Routinen,
//     mehrzeilige letzte Anweisung, initialization-Abschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestParamNameMismatch = class
  public
    // --- Platzhalter -------------------------------------------------------
    [Test] procedure Placeholders_Basic_CaseKeptDuplicatesOnce;
    [Test] procedure Placeholders_CastAssignPositionalTriggerSkipped;
    [Test] procedure Placeholders_InSqlStringsAndCommentsSkipped;
    // ADO/SQL Server ':@Name', Oracle '$'/'#', ':"Name mit Leerzeichen"'
    [Test] procedure Placeholders_AtDollarHashAndQuoted;

    // --- Scanner: melden ---------------------------------------------------
    [Test] procedure Scan_MatchingNames_Silent;
    [Test] procedure Scan_Typo_BothDirections;
    [Test] procedure Scan_ClearThenAdd_Judged;
    [Test] procedure Scan_TextAssign_NotCreated_NoUnassigned;
    [Test] procedure Scan_TwoQueries_KeptApart;
    [Test] procedure Scan_SqlWithoutPlaceholders_ParamByNameReported;
    [Test] procedure Scan_SelfPrefix_SameQuery;
    [Test] procedure Scan_Doa_SetVariableCountsAsAssigned;
    [Test] procedure Scan_LineBreakLiterals_Joined;
    [Test] procedure Scan_AdoParametersAndParamsParamByName;
    // Kundenkorpus 2026-10-07 (ACBr, TADOQuery): ':@CodigoBarras' war der
    // einzige Fehlalarm des ersten Messlaufs
    [Test] procedure Scan_AdoAtName_Silent;
    // Data.DB/ADODB lesen den Namen bis Leerzeichen/,/;/): ':a+1' -> 'a+1'
    [Test] procedure Scan_ParseSqlReading_Silent;
    [Test] procedure Scan_AtNameTypo_Reported;

    // --- Scanner: schweigen ------------------------------------------------
    [Test] procedure Scan_SqlFromDfmAppended_Silent;
    [Test] procedure Scan_NonLiteralSql_Silent;
    [Test] procedure Scan_With_Silent;
    [Test] procedure Scan_CastPrefix_Silent;
    [Test] procedure Scan_OpenWithSql_Silent;
    [Test] procedure Scan_PositionalParams_Silent;
    [Test] procedure Scan_Macro_Silent;
    [Test] procedure Scan_ReassignedFromOtherQuery_Silent;
    [Test] procedure Scan_Comments_Ignored;
    [Test] procedure Scan_ConditionalAdd_NamesMatch;
    [Test] procedure Scan_FindParamAndParamValues_NotReported;
    // (b) braucht die Gewissheit, dass hier gebunden wird
    [Test] procedure Scan_QueryPassedOn_Silent;
    [Test] procedure Scan_DynamicParams_NoUnassigned;
    [Test] procedure Scan_ParamNameFromVariable_NoUnassigned;

    // --- Verifikation 2026-10-07 (19 Befunde) ------------------------------
    [Test] procedure Scan_DeclaredLocalQuery_UnassignedReported;
    [Test] procedure Scan_FieldQueryWithOwnCall_Silent;
    [Test] procedure Scan_UnknownMethodWithArgs_Silent;
    [Test] procedure Scan_MasterSource_NoUnassigned;
    [Test] procedure Scan_ExecuteBlock_NoUnassigned;
    [Test] procedure Scan_PlaceholderOnlyInComment_NotUnknown;
    [Test] procedure Scan_OracleQQuote_Skipped;
    [Test] procedure Scan_CustomConstructor_NotCreated;
    [Test] procedure Scan_ParenStarComment_Closed;
    [Test] procedure Scan_ParamValues_CountsAsAssigned;
    [Test] procedure Scan_ParamsParamByNameTypo_Reported;

    // --- Detektor ----------------------------------------------------------
    [Test] procedure Detector_Typo_KindSeverityLine;
    [Test] procedure Detector_NestedRoutine_NotMixedIn;
    [Test] procedure Detector_MultiLineLastStatement_Seen;
    [Test] procedure Detector_InitializationSection_NotPartOfLastRoutine;
    // Verifikation 2026-10-07: 'Q: TFDQuery' im var-Abschnitt zaehlte als
    // Weitergabe der Query - (b) war fuer deklarierte Queries tot
    [Test] procedure Detector_DeclaredLocalQuery_UnassignedReported;
  end;

implementation

// noinspection-file GodClass, SQLInjection
// GodClass: ein Fixture je Regel, wie in den uebrigen Testunits; die
// Gruppen (Platzhalter, melden, schweigen, Detektor) stehen als
// Kommentarbloecke in der Deklaration. SQLInjection: die Unit besteht aus
// SQL-Fixtures in String-Literalen - genau das, was SCA003 sucht.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uParamNameScan, uTestFindingHelper;

// Zeilen mit AEnde verbinden, auch hinter der letzten.
function Zeilen(const A: array of string; const AEnde: string): string;
var
  Sb : TStringBuilder;
  k : Integer;
begin
  Sb := TStringBuilder.Create;
  try
    for k := 0 to High(A) do
      Sb.Append(A[k]).Append(AEnde);
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

// Routine fuer den Scanner (#10 wie im Detektor).
function L(const A: array of string): string;
begin
  Result := Zeilen(A, #10);
end;

// Unit fuer FindingsOfFile (Zeile 1 = erstes Element).
function Quelltext(const AZeilen: array of string): string;
begin
  Result := Zeilen(AZeilen, #13#10);
end;

// ScanRoutine mit erster Zeile 10 -> 'A:Q.x@15 | B:...'
function Scan(const ACode: string): string;
const
  KIND_TAG: array[TParamNameIssueKind] of string = ('A:', 'B:');
var
  R : TArray<TParamNameIssue>;
  Teile : TArray<string>;
  k : Integer;
begin
  R := TParamNameScan.ScanRoutine(ACode, 10);
  SetLength(Teile, Length(R));
  for k := 0 to High(R) do
    Teile[k] := Format('%s%s.%s@%d',
      [KIND_TAG[R[k].Kind], R[k].Query, R[k].Param, R[k].Line]);
  Result := string.Join(' | ', Teile);
end;

function Ph(const ASql: string): string;
begin
  Result := string.Join(',', TParamNameScan.PlaceholdersOf(ASql));
end;

{ --- Platzhalter ----------------------------------------------------------- }

procedure TTestParamNameMismatch.Placeholders_Basic_CaseKeptDuplicatesOnce;
begin
  Assert.AreEqual('a,B', Ph('select * from t where a = :a and b=:B'));
  Assert.AreEqual('a', Ph('where a = :a or b = :A'));
end;

procedure TTestParamNameMismatch.Placeholders_CastAssignPositionalTriggerSkipped;
begin
  Assert.AreEqual('p', Ph('select x::int, :p::text from t'), 'Postgres-Cast');
  Assert.AreEqual('res,x', Ph('begin :res := f(:x); y := 1; end;'), 'PL/SQL :=');
  Assert.AreEqual('b', Ph('where a = :1 and b = :b'), 'positional');
  Assert.AreEqual('seq', Ph('begin :new.id := :seq; :old.x := 1; end'), 'Trigger');
  Assert.AreEqual('z', Ph('select arr[lo:hi] from t where z = :z'), 'Arraygrenze');
end;

procedure TTestParamNameMismatch.Placeholders_InSqlStringsAndCommentsSkipped;
begin
  Assert.AreEqual('n', Ph('where t = ''12:30'' and n = :n'));
  Assert.AreEqual('x', Ph('select "a:b" from t where x = :x'));
  Assert.AreEqual('k', Ph('select 1 -- :nope'#10'from t /* :also */ where k=:k'));
  Assert.AreEqual('m', Ph('where n = ''O''''Brien:x'' and m = :m'));
end;

procedure TTestParamNameMismatch.Placeholders_AtDollarHashAndQuoted;
begin
  Assert.AreEqual('@x,y$1,z#', Ph('where a = :@x and b = :y$1 and c = :z#'));
  Assert.AreEqual('a b', Ph('where a = :"a b"'));
end;

{ --- Scanner: melden ------------------------------------------------------- }

procedure TTestParamNameMismatch.Scan_MatchingNames_Silent;
begin
  // der Fall vom Foto, richtig geschrieben; Gross/klein egal
  Assert.AreEqual('', Scan(L([
    'class function TLeQuery.Get(AId: Integer): string;',
    'var',
    '  mQuery: TOracleQuery;',
    'begin',
    '  Result := '''';',
    '  mQuery := TOracleQuery.Create(nil);',
    '  try',
    '    mQuery.SQL.Add(''SELECT name FROM t'');',
    '    mQuery.SQL.Add('' WHERE id = :id'');',
    '    mQuery.ParamByName(''ID'').AsInteger := AId;',
    '    mQuery.Execute;',
    '  finally',
    '    mQuery.Free;',
    '  end;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_Typo_BothDirections;
begin
  Assert.AreEqual('B:Q.customer_id@14 | A:Q.custid@15', Scan(L([
    'procedure P;',                                        // 10
    'begin',                                               // 11
    '  Q := TFDQuery.Create(nil);',                        // 12
    '  Q.SQL.Add(''select * from c'');',                   // 13
    '  Q.SQL.Add(''where customer_id = :customer_id'');',  // 14
    '  Q.ParamByName(''custid'').AsInteger := 1;',         // 15
    '  Q.Open;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_ClearThenAdd_Judged;
begin
  Assert.AreEqual('A:qryUser.id@14', Scan(L([
    'procedure P;',
    'begin',
    '  qryUser.SQL.Clear;',
    '  qryUser.SQL.Add(''select * from u where x = :x'');',
    '  qryUser.ParamByName(''id'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_TextAssign_NotCreated_NoUnassigned;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_TwoQueries_KeptApart;
begin
  Assert.AreEqual('A:Q2.x@15', Scan(L([
    'procedure P;',
    'begin',
    '  Q1.SQL.Text := ''select * from a where x = :x'';',
    '  Q2.SQL.Text := ''select * from b where y = :y'';',
    '  Q1.ParamByName(''x'').AsInteger := 1;',
    '  Q2.ParamByName(''x'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_SqlWithoutPlaceholders_ParamByNameReported;
begin
  Assert.AreEqual('A:Q.id@13', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t'';',
    '  Q.ParamByName(''id'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_SelfPrefix_SameQuery;
begin
  Assert.AreEqual('A:FQuery.b@13', Scan(L([
    'procedure P;',
    'begin',
    '  FQuery.SQL.Text := ''select * from t where a = :a'';',
    '  Self.FQuery.ParamByName(''b'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_Doa_SetVariableCountsAsAssigned;
begin
  Assert.AreEqual('B:OQ.b@14', Scan(L([
    'procedure P;',
    'begin',
    '  OQ := TOracleQuery.Create(nil);',
    '  OQ.SQL.Add(''select * from t where a = :a'');',
    '  OQ.SQL.Add(''and b = :b'');',
    '  OQ.DeclareVariable(''a'', otString);',
    '  OQ.SetVariable(''a'', ''x'');',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_LineBreakLiterals_Joined;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select *'' + sLineBreak + ''from t'' + #13#10 +',
    '    ''where a = :a'';',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_AdoParametersAndParamsParamByName;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.Parameters.ParamByName(''a'').Value := 1;',
    '  Q.Params.ParamByName(''b'').Value := 2;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_AdoAtName_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Clear;',
    '  Q.SQL.Add(''Select * from CadastroComandas where CodigoBarras=:@CodigoBarras'');',
    '  Q.Parameters.ParamByName(''@CodigoBarras'').Value := V;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_ParseSqlReading_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where k = :a+1'';',
    '  Q.ParamByName(''a+1'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_AtNameTypo_Reported;
begin
  Assert.AreEqual('A:Q.@Cod@14', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Clear;',
    '  Q.SQL.Add(''select * from t where c = :@Code'');',
    '  Q.Parameters.ParamByName(''@Cod'').Value := V;',
    'end;'])));
end;

{ --- Scanner: schweigen ---------------------------------------------------- }

procedure TTestParamNameMismatch.Scan_SqlFromDfmAppended_Silent;
begin
  // Add ohne Create/Clear davor haengt an SQL an, das wir nicht kennen
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  qryUser.SQL.Add(''and x = :x'');',
    '  qryUser.ParamByName(''id'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_NonLiteralSql_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := Format(''select * from %s where a = :a'', [T]);',
    '  Q.ParamByName(''zz'').AsString := ''x'';',
    'end;'])), 'Format');
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := Q.SQL.Text + '' and z = :z'';',
    '  Q.ParamByName(''y'').AsString := ''x'';',
    'end;'])), 'Anhaengen an sich selbst');
end;

procedure TTestParamNameMismatch.Scan_With_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  with Q do',
    '  begin',
    '    SQL.Text := ''select :a'';',
    '    ParamByName(''b'').AsString := ''x'';',
    '  end;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_CastPrefix_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  TFDQuery(X).SQL.Text := ''select :a'';',
    '  TFDQuery(X).ParamByName(''b'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_OpenWithSql_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select :a'';',
    '  Q.ParamByName(''zz'').AsString := ''x'';',
    '  Q.Open(''select * from t where k = :k'', [1]);',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_PositionalParams_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = ?'';',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_Macro_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from &tab where a = :a'';',
    '  Q.MacroByName(''tab'').AsRaw := ''t'';',
    '  Q.ParamByName(''b'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_ReassignedFromOtherQuery_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := DM.qryMain;',
    '  Q.SQL.Add(''and z = :z'');',
    '  Q.ParamByName(''y'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_Comments_Ignored;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Add(''select * from t -- :nope'');',
    '  Q.SQL.Add(''where a = :a'');',
    '  // Q.ParamByName(''zz'').AsString := ''x'';',
    '  { Q.ParamByName(''yy'') }',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_ConditionalAdd_NamesMatch;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Clear;',
    '  Q.SQL.Add(''select * from t where 1=1'');',
    '  if F then',
    '    Q.SQL.Add(''and f = :f'');',
    '  if F then',
    '    Q.ParamByName(''f'').AsInteger := 1;',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_FindParamAndParamValues_NotReported;
begin
  // FindParam wirft nicht - kein (a); als Zuweisung zaehlt es fuer (b)
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a'';',
    '  Q.FindParam(''zz'');',
    '  Q.FindParam(''a'').AsString := ''x'';',
    'end;'])), 'FindParam');
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamValues[''a;b''] := VarArrayOf([1, 2]);',
    'end;'])), 'ParamValues');
end;

procedure TTestParamNameMismatch.Scan_QueryPassedOn_Silent;
begin
  // BindRest(Q) bekommt die Query - es kann SQL und Parameter aendern:
  // kein Urteil (Verifikation 2026-10-07, frueher wurde (a) gemeldet)
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(''c'').AsString := ''x'';',
    '  BindRest(Q);',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_DynamicParams_NoUnassigned;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    '  Q.Params[1].AsString := ''y'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_ParamNameFromVariable_NoUnassigned;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(N).AsString := ''x'';',
    '  Q.ParamByName(''a'').AsString := ''x'';',
    'end;'])));
end;

procedure TTestParamNameMismatch.Scan_DeclaredLocalQuery_UnassignedReported;
begin
  Assert.AreEqual('B:Q.b@15', Scan(L([
    'procedure P;',
    'var',
    '  Q: TFDQuery;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    '  Q.Open;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_FieldQueryWithOwnCall_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure TForm1.Load;',
    'begin',
    '  qry.SQL.Clear;',
    '  qry.SQL.Add(''select * from t where a = :a and b = :b'');',
    '  qry.ParamByName(''zz'').AsInteger := 1;',
    '  BindFilter;',
    '  qry.Open;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_UnknownMethodWithArgs_Silent;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t'';',
    '  Q.AddWhere(''k = :k'');',
    '  Q.ParamByName(''k'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_MasterSource_NoUnassigned;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.MasterSource := dsMaster;',
    '  Q.SQL.Text := ''select * from d where m = :m and x = :x'';',
    '  Q.ParamByName(''x'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_ExecuteBlock_NoUnassigned;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''execute block (p int = :p) as declare v int; begin v = :p; end'';',
    '  Q.ParamByName(''p'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_PlaceholderOnlyInComment_NotUnknown;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t where a = :a /* and s = :s */'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    '  Q.ParamByName(''s'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_OracleQQuote_Skipped;
begin
  Assert.AreEqual('A:Q.x@15', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TOracleQuery.Create(nil);',
    '  Q.SQL.Text := ''select q''''[it''''''''s :x]'''' from t where a = :a'';',
    '  Q.SetVariable(''a'', 1);',
    '  Q.ParamByName(''x'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_CustomConstructor_NotCreated;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q := TMyQuery.CreateFor(''cust'');',
    '  Q.SQL.Add(''and k = :k'');',
    '  Q.ParamByName(''x'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_ParenStarComment_Closed;
begin
  Assert.AreEqual('', Scan(L([
    'procedure P;',
    'begin',
    '  (*) Q.ParamByName(''zz'') *)',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t where a = :a'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_ParamValues_CountsAsAssigned;
begin
  Assert.AreEqual('B:Q.c@13', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b and c = :c'';',
    '  Q.ParamValues[''a;b''] := VarArrayOf([1, 2]);',
    'end;'
    ])));
end;

procedure TTestParamNameMismatch.Scan_ParamsParamByNameTypo_Reported;
begin
  Assert.AreEqual('B:Q.b@13 | A:Q.bb@15', Scan(L([
    'procedure P;',
    'begin',
    '  Q := TFDQuery.Create(nil);',
    '  Q.SQL.Text := ''select * from t where a = :a and b = :b'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    '  Q.Params.ParamByName(''bb'').AsInteger := 2;',
    'end;'
    ])));
end;
{ --- Detektor -------------------------------------------------------------- }

procedure TTestParamNameMismatch.Detector_Typo_KindSeverityLine;
var
  F : TObjectList<TLeakFinding>;
  i, Anzahl : Integer;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;',                                            // 1
    'interface',                                          // 2
    'implementation',                                     // 3
    'procedure Load(Q: TFDQuery);',                       // 4
    'begin',                                              // 5
    '  Q.SQL.Clear;',                                     // 6
    '  Q.SQL.Add(''select * from c where id = :id'');',   // 7
    '  Q.ParamByName(''ident'').AsInteger := 1;',         // 8
    '  Q.ParamByName(''id'').AsInteger := 2;',            // 9
    '  Q.Open;',                                          // 10
    'end;',
    'end.']));
  try
    Anzahl := 0;
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkParamNameMismatch then
      begin
        Inc(Anzahl);
        Assert.AreEqual('8', F[i].LineNumber, 'Fund gehoert auf die ParamByName-Zeile');
        Assert.IsTrue(Pos('ident', F[i].MissingVar) > 0, F[i].MissingVar);
        Assert.IsTrue(Pos('(it has :id)', F[i].MissingVar) > 0,
          'Meldung nennt die vorhandenen Platzhalter: ' + F[i].MissingVar);
        Assert.AreEqual<TLeakSeverity>(lsWarning, F[i].Severity);
      end;
    Assert.AreEqual<Integer>(1, Anzahl);
  finally
    F.Free;
  end;
end;

procedure TTestParamNameMismatch.Detector_NestedRoutine_NotMixedIn;
var
  F : TObjectList<TLeakFinding>;
begin
  // Die innere Routine setzt Q2.ParamByName('x') ueber zwei Zeilen; die
  // Fortsetzungszeile liegt hinter dem Ende, das der AST fuer sie fuehrt.
  // Ohne Ausblenden (bis vor das 'begin' der aeusseren) saehe die aeussere
  // Routine 'x' und meldete (a) gegen ihr SQL mit :y. Mit Ausblenden
  // erwaehnt der ausgeblendete Text Q2 - dann wird Q2 nicht beurteilt.
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;',
    'interface',
    'implementation',
    'procedure Outer;',
    '  procedure Inner;',
    '  begin',
    '    Q2.ParamByName(',
    '      ''x'').AsInteger := 1;',
    '  end;',
    'begin',
    '  Q2 := TFDQuery.Create(nil);',
    '  Q2.SQL.Text := ''select * from t where y = :y'';',
    '  Q2.ParamByName(''y'').AsInteger := 1;',
    '  Inner;',
    'end;',
    'end.']));
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkParamNameMismatch));
  finally
    F.Free;
  end;
end;

procedure TTestParamNameMismatch.Detector_MultiLineLastStatement_Seen;
var
  F : TObjectList<TLeakFinding>;
begin
  // Der AST fuehrt die letzte Anweisung nur mit ihrer Startzeile; der
  // Name steht eine Zeile tiefer.
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;',
    'interface',
    'implementation',
    'procedure Load(Q: TFDQuery);',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    '  Q.ParamByName(',
    '    ''c'').AsInteger := 1;',
    'end;',
    'end.']));
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkParamNameMismatch));
  finally
    F.Free;
  end;
end;

procedure TTestParamNameMismatch.Detector_InitializationSection_NotPartOfLastRoutine;
var
  F : TObjectList<TLeakFinding>;
begin
  // Ohne die Kappung am Unit-Schwanz gehoerte das ParamByName im
  // initialization-Abschnitt zur letzten Routine.
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;',
    'interface',
    'implementation',
    'procedure Load(Q: TFDQuery);',
    'begin',
    '  Q.SQL.Text := ''select * from t where a = :a'';',
    '  Q.ParamByName(''a'').AsInteger := 1;',
    'end;',
    'initialization',
    '  Q.ParamByName(''zz'').AsInteger := 1;',
    'end.']));
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkParamNameMismatch));
  finally
    F.Free;
  end;
end;

procedure TTestParamNameMismatch.Detector_DeclaredLocalQuery_UnassignedReported;
var
  F : TObjectList<TLeakFinding>;
  i, Anzahl : Integer;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext([
    'unit t;',                                                   // 1
    'interface',                                                 // 2
    'implementation',                                            // 3
    'procedure Load;',                                           // 4
    'var',                                                       // 5
    '  Q: TFDQuery;',                                            // 6
    'begin',                                                     // 7
    '  Q := TFDQuery.Create(nil);',                              // 8
    '  try',                                                     // 9
    '    Q.SQL.Text := ''select * from t where a = :a and b = :b'';', // 10
    '    Q.ParamByName(''a'').AsInteger := 1;',                  // 11
    '    Q.Open;',
    '  finally',
    '    Q.Free;',
    '  end;',
    'end;',
    'end.']));
  try
    Anzahl := 0;
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkParamNameMismatch then
      begin
        Inc(Anzahl);
        Assert.AreEqual('10', F[i].LineNumber);
        Assert.IsTrue(Pos(':b', F[i].MissingVar) > 0, F[i].MissingVar);
      end;
    Assert.AreEqual<Integer>(1, Anzahl);
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParamNameMismatch);

end.
