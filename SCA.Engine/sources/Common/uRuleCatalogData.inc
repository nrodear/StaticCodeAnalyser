// ==========================================================================
// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.
// Quelle: rules/sca-rules.json  (dort aendern, dann Generator laufen lassen)
//
// Zweck: Katalog-Texte einkompiliert, damit TRuleCatalog auch OHNE gefundene
// rules/sca-rules.json vollstaendige Metadaten liefert. Ohne das zeigten die
// 19 Kinds ohne uFixHint-Hand-Branch (SCA167-SCA184, SCA194) im IDE-Plugin
// GAR KEINEN Vorher/Nachher-Hinweis: die Plugin-BPL liegt im Embarcadero-
// BPL-Verzeichnis, das Repo auf einem anderen Laufwerk - der Aufwaertswalk
// der Pfadsuche erreicht die JSON dort nie.
// ==========================================================================

const
  // Index == Ord(TFindingKind) - die JSON ist positionsgleich zum Enum
  // (Test RuleIDMatchesOrdinal sichert das ab).
  RULE_CATALOG_DATA : array[0..194] of TRuleFallbackData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Object created without try/finally';
      ShortDesc: 'Object created but never freed (potential memory leak)';
      BadEx    : 'list := TStringList.Create;' + #13#10 + 'DoStuff(list);   // <-- exception here leaks list';
      GoodEx   : 'list := TStringList.Create;' + #13#10 + 'try' + #13#10 + '  DoStuff(list);' + #13#10 +
        'finally' + #13#10 + '  list.Free;' + #13#10 + 'end;'
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Empty except block';
      ShortDesc: 'Empty except block silently swallows every exception';
      BadEx    : 'try DoStuff except end;';
      GoodEx   : 'try DoStuff except on E: Exception do LogError(E.Message); end;'
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'SQL string built via concatenation';
      ShortDesc: 'SQL string concatenated with ''+'' from user-controllable input (injection risk)';
      BadEx    : 'Query.SQL.Text := ''SELECT * FROM Users WHERE Name='''''' + UserName + '''''''';';
      GoodEx   : 'Query.SQL.Text := ''SELECT * FROM Users WHERE Name=:n'';' + #13#10 +
        'Query.ParamByName(''n'').AsString := UserName;'
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Hardcoded credential / API token';
      ShortDesc: 'Password / API key / token as string literal in source code';
      BadEx    : 'Password := ''admin123'';';
      GoodEx   : 'Password := GetEnvironmentVariable(''DB_PASSWORD'');'
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format() placeholder count mismatch';
      ShortDesc: 'Format() / FormatUtf8() placeholder count does not match argument count';
      BadEx    : 'Format(''%s is %d'', [Name]);   // <-- Age missing';
      GoodEx   : 'Format(''%s is %d'', [Name, Age]);'
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'File could not be read or parsed';
      ShortDesc: 'Parser/IO error - source file unreadable or syntactically broken';
      BadEx    : '(file is not valid UTF-8 or has lexer-breaking content)';
      GoodEx   : '(check encoding, fix syntax)'
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Unused unit in uses clause';
      ShortDesc: 'Uses-entry possibly unused (no identifier from it referenced)';
      BadEx    : 'uses ..., MyUnusedHelper, ...;';
      GoodEx   : '(remove if truly unused; otherwise add a comment why it stays)'
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'Possible nil-dereference';
      ShortDesc: 'Access to a variable that may be nil at this point';
      BadEx    : 'obj := FindObject(id);' + #13#10 + 'obj.DoStuff;   // <-- AV if FindObject returns nil';
      GoodEx   : 'obj := FindObject(id);' + #13#10 + 'if Assigned(obj) then obj.DoStuff;'
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Object created without protective try/finally';
      ShortDesc: '.Create call without surrounding try/finally - leak risk on exception';
      BadEx    : 'obj := TFoo.Create;' + #13#10 + 'obj.DoStuff;' + #13#10 + 'obj.Free;';
      GoodEx   : 'obj := TFoo.Create;' + #13#10 + 'try obj.DoStuff finally obj.Free end;'
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'Possible division by zero';
      ShortDesc: 'Division by a variable / expression that may be zero';
      BadEx    : 'result := total / count;';
      GoodEx   : 'if count <> 0 then result := total / count;'
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Code after Exit/Raise is unreachable';
      ShortDesc: 'Statement after Exit, raise, or Halt is dead code';
      BadEx    : 'Exit;' + #13#10 + 'WriteLn(''never reached'');';
      GoodEx   : '(remove the unreachable line)'
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'Method exceeds line-count threshold';
      ShortDesc: 'Method longer than configured maximum (default 80 lines)';
      BadEx    : '(150-line procedure doing parsing + validation + persistence)';
      GoodEx   : '(extract into ParseInput, Validate, Persist helper methods)'
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Too many parameters';
      ShortDesc: 'Method has more parameters than configured maximum (default 7)';
      BadEx    : 'procedure SaveOrder(id, customer, address, city, zip, country, total, tax, shipping: ...);';
      GoodEx   : 'procedure SaveOrder(const Order: TOrder);'
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Numeric literal without named constant';
      ShortDesc: 'Numeric literal in expression - extract to a named constant';
      BadEx    : 'if RetryCount > 3 then ...';
      GoodEx   : 'const MAX_RETRIES = 3;' + #13#10 + 'if RetryCount > MAX_RETRIES then ...'
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'String literal repeated across multiple sites';
      ShortDesc: 'Same string literal appears N+ times - extract to constant';
      BadEx    : 'ShowMessage(''File not found'');' + #13#10 + '... ' + #13#10 +
        'LogError(''File not found'');';
      GoodEx   : 'const MSG_FILE_NOT_FOUND = ''File not found'';' + #13#10 +
        'ShowMessage(MSG_FILE_NOT_FOUND);'
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Filesystem path as string literal';
      ShortDesc: 'Hardcoded C:\ / UNC / Linux path in source';
      BadEx    : 'LogFile := ''C:\Logs\app.log'';';
      GoodEx   : 'LogFile := TPath.Combine(GetEnvironmentVariable(''LOGDIR''), ''app.log'');'
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage in production code';
      ShortDesc: 'Debug output statement found in production unit';
      BadEx    : 'WriteLn(''here #3'');';
      GoodEx   : 'Logger.Debug(''reached step 3'');'
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'Block nesting exceeds threshold';
      ShortDesc: 'Nested if/for/while depth higher than configured maximum (default 4)';
      BadEx    : 'if a then' + #13#10 + '  if b then' + #13#10 + '    if c then' + #13#10 +
        '      if d then DoStuff;';
      GoodEx   : 'if not a then Exit;' + #13#10 + 'if not b then Exit;' + #13#10 + 'if not c then Exit;' +
        #13#10 + 'if d then DoStuff;'
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'TODO/FIXME marker in comment';
      ShortDesc: 'Open TODO / FIXME / HACK / XXX marker - resolve before release';
      BadEx    : '// TODO: handle the case where input is empty';
      GoodEx   : '(implement the case OR file an issue and reference it)'
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Empty method body';
      ShortDesc: 'Method body has no statements';
      BadEx    : 'procedure DoStuff;' + #13#10 + 'begin' + #13#10 + 'end;';
      GoodEx   : 'procedure DoStuff;' + #13#10 + 'begin' + #13#10 +
        '  raise ENotImplemented.Create(''...'');' + #13#10 + 'end;'
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Duplicated code block';
      ShortDesc: 'Multiple identical code blocks (>= configured minimum lines)';
      BadEx    : '(20 lines of validation code copy-pasted across 3 methods)';
      GoodEx   : '(extract into a single ValidateXxx procedure)'
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'Method exceeds McCabe complexity threshold';
      ShortDesc: 'Cyclomatic Complexity > configured threshold (default 10)';
      BadEx    : '(method with 15+ if/case/for branches in one body)';
      GoodEx   : '(extract decision groups into named helper methods)'
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'User-defined custom rule';
      ShortDesc: 'Pattern matched by a rule loaded from analyser-rules.yml';
      BadEx    : '(pattern from analyser-rules.yml matches)';
      GoodEx   : '(fix per the custom rule''s message)'
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Component with default name';
      ShortDesc: 'Component left at wizard-default name (Button1, Edit3, Panel2 ...)';
      BadEx    : 'object Button1: TButton' + #13#10 + '  Caption = ''Save''' + #13#10 + 'end';
      GoodEx   : 'object btnSave: TButton' + #13#10 + '  Caption = ''Save''' + #13#10 + 'end'
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Hardcoded UI text in DFM';
      ShortDesc: 'Caption / Hint / Text property as literal in DFM, not via i18n layer';
      BadEx    : 'object btnSave: TButton' + #13#10 + '  Caption = ''Speichern''' + #13#10 + 'end';
      GoodEx   : 'btnSave.Caption := _(''btn.save'');  // i18n at runtime'
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Hardcoded DB credentials in DFM';
      ShortDesc: 'Plaintext Password / ConnectionString with Pwd= on a DB component';
      BadEx    : 'object FDConnection1: TFDConnection' + #13#10 +
        '  Params.Strings = (''Password=admin123'' ''User_Name=sa'')' + #13#10 + 'end';
      GoodEx   : 'FDConnection1.Params.Values[''Password''] := GetEnvironmentVariable(''DB_PWD'');'
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Duplicate (DataSource, DataField) binding';
      ShortDesc: 'Two or more controls bind the same (DataSource, DataField) pair';
      BadEx    : 'DBEdit1.DataField = ''NAME''' + #13#10 +
        'DBEdit2.DataField = ''NAME''   // same DataSource';
      GoodEx   : '(bind ''NAME'' to exactly one control)'
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'DFM event handler references missing method';
      ShortDesc: 'OnClick / On... points to a method that does not exist in the form class';
      BadEx    : 'object btnSave: TButton' + #13#10 + '  OnClick = btnSaveClick   // method removed in .pas' +
        #13#10 + 'end';
      GoodEx   : '(restore the method or clear OnClick in the designer)'
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Orphan event handler';
      ShortDesc: 'Published TNotifyEvent-shaped method has no DFM binding';
      BadEx    : 'procedure TForm1.btnOldClick(Sender: TObject);  // nothing binds this' + #13#10 + 'begin' +
        #13#10 + '  ...' + #13#10 + 'end;';
      GoodEx   : '(remove the method or bind it from a control)'
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Empty bound event handler';
      ShortDesc: 'Event is wired in DFM, method exists, body is empty';
      BadEx    : 'procedure TForm1.btnSaveClick(Sender: TObject);' + #13#10 + 'begin' + #13#10 + 'end;';
      GoodEx   : '(implement the handler or clear OnClick in the designer)'
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'DFM component without published field';
      ShortDesc: 'Component in DFM has no matching published field in the form class - stale DFM entry (schema drift)';
      BadEx    : '// .dfm contains object btnSave: TButton, but TForm1 has no btnSave: TButton field';
      GoodEx   : '(add the field to the published section of TForm1, or remove the stale component from the .dfm)'
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Circular DataSource / Master-Detail loop';
      ShortDesc: 'Cycle in DataSource.DataSet / DataSet.MasterSource edges';
      BadEx    : 'QA.MasterSource = dsB   QB.MasterSource = dsA   // cycle';
      GoodEx   : '(make one query the parent, the other the detail)'
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'SQL property built from UI input';
      ShortDesc: 'Query.SQL assembled from form-control Text / Caption properties';
      BadEx    : 'FDQuery1.SQL.Text := ''SELECT * FROM U WHERE Name='''''' + EdName.Text + '''''''';';
      GoodEx   : 'FDQuery1.SQL.Text := ''SELECT * FROM U WHERE Name=:n'';' + #13#10 +
        'FDQuery1.ParamByName(''n'').AsString := EdName.Text;'
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Required field has no UI binding';
      ShortDesc: 'TField with Required=True has no bound input control';
      BadEx    : 'FieldDefs: Email Required=True   // no DBEdit / DBLookup bound to it';
      GoodEx   : '(bind a DBEdit to the Email field)'
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Required field only on hidden controls';
      ShortDesc: 'TField with Required=True is bound only to Visible=False controls';
      BadEx    : 'DBEdit1.DataField = ''Email''   DBEdit1.Visible = False';
      GoodEx   : '(make the control visible or remove Required=True)'
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'UI control type mismatched with TField';
      ShortDesc: 'DB control class does not match TField.DataType (TDBEdit for TBooleanField)';
      BadEx    : 'DBEdit1.DataField = ''IsActive''   // TBooleanField';
      GoodEx   : 'DBCheckBox1.DataField = ''IsActive'''
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'Duplicate TabOrder among siblings';
      ShortDesc: 'Two sibling controls in the same parent share the same TabOrder value';
      BadEx    : 'EdA.TabOrder = 0' + #13#10 + 'EdB.TabOrder = 0   // same parent';
      GoodEx   : 'EdA.TabOrder = 0' + #13#10 + 'EdB.TabOrder = 1'
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Component uses forbidden class';
      ShortDesc: 'Component class is in the project''s ForbiddenClasses list';
      BadEx    : 'object Query1: TQuery   // ForbiddenClasses=TQuery';
      GoodEx   : 'object FDQuery1: TFDQuery'
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'DB component on UI form';
      ShortDesc: 'TFDQuery / TFDConnection directly on a TForm/TFrame instead of a DataModule';
      BadEx    : 'object frmInvoice: TForm' + #13#10 + '  object FDQuery1: TFDQuery ...';
      GoodEx   : 'object dmInvoice: TDataModule' + #13#10 + '  object FDQuery1: TFDQuery ...'
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Cross-form field access';
      ShortDesc: 'Code in Form1 reads / writes Form2.<published_field> directly';
      BadEx    : 'Form2.EdName.Text := ''x'';';
      GoodEx   : 'Form2.UserName := ''x'';   // property on Form2'
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Input control directly on TForm';
      ShortDesc: 'Input control sits on the form instead of being embedded in a TPanel / TGroupBox';
      BadEx    : 'object frmEdit: TForm' + #13#10 + '  object EdName: TEdit  // direct child of form';
      GoodEx   : 'object frmEdit: TForm' + #13#10 + '  object pnlBody: TPanel' + #13#10 +
        '    object EdName: TEdit'
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'God event handler';
      ShortDesc: 'Single method wired to >= N component events (default N=5)';
      BadEx    : 'btn1.OnClick = HandleEverything' + #13#10 + 'btn2.OnClick = HandleEverything' + #13#10 +
        'btn3.OnClick = HandleEverything' + #13#10 + 'btn4.OnClick = HandleEverything' + #13#10 +
        'btn5.OnClick = HandleEverything';
      GoodEx   : '(one handler per logical action)'
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Component has Action + OnClick';
      ShortDesc: 'Action and OnClick both set - Action wins, OnClick is dead code';
      BadEx    : 'object btnSave: TButton' + #13#10 + '  Action = actSave' + #13#10 +
        '  OnClick = btnSaveClick   // never fires' + #13#10 + 'end';
      GoodEx   : '(remove OnClick or remove Action)'
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Long string concat - prefer Format()';
      ShortDesc: 'Multi-segment string concatenation - extract to a Format() call';
      BadEx    : 'Msg := ''User '' + Name + '' has '' + IntToStr(N) + '' open tickets'';';
      GoodEx   : 'Msg := Format(''User %s has %d open tickets'', [Name, N]);'
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'with statement - scope-shadowing trap the compiler does not warn about';
      BadEx    : 'with Customer do' + #13#10 + 'begin' + #13#10 +
        '  Name := SomeName;   // Customer.Name? or local Name?' + #13#10 + 'end;';
      GoodEx   : 'C := Customer;' + #13#10 + 'C.Name := SomeName;'
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - missing downto';
      ShortDesc: 'for i := 10 to 1 do - loop body never executes';
      BadEx    : 'for i := 10 to 1 do DoStuff(i);';
      GoodEx   : 'for i := 10 downto 1 do DoStuff(i);'
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Self-assignment - no-op or copy-paste typo';
      BadEx    : 'Customer.Name := Customer.Name;';
      GoodEx   : 'Customer.Name := NewName;'
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Virtual call in constructor';
      ShortDesc: 'Virtual method invoked from constructor - subclass override sees half-initialised Self';
      BadEx    : 'constructor TBase.Create;' + #13#10 + 'begin' + #13#10 + '  Configure;   // virtual' +
        #13#10 + 'end;';
      GoodEx   : 'constructor TBase.Create;' + #13#10 + 'begin' + #13#10 + '  // skip virtual call' + #13#10 +
        'end;' + #13#10 + 'procedure TBase.AfterConstruction;' + #13#10 + 'begin' + #13#10 +
        '  Configure;' + #13#10 + 'end;'
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N without guard';
      ShortDesc: 'Length / .Count with subtraction - native-uint underflow when empty';
      BadEx    : 'Last := s[Length(s) - 1];';
      GoodEx   : 'if Length(s) >= 2 then Last := s[Length(s) - 1];'
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Public member could be unit-private';
      ShortDesc: 'Public member is referenced only within the current unit - Delphi-classic `private` (unit-scope) suffices';
      BadEx    : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  public' + #13#10 + '    procedure Helper;' +
        #13#10 + '  end;' + #13#10 + '  TBar = class' + #13#10 +
        '    procedure Run;  // calls Foo.Helper - same unit' + #13#10 + '  end;';
      GoodEx   : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  private' + #13#10 + '    procedure Helper;' +
        #13#10 + '  end;' + #13#10 +
        '// Same-unit access stays legal under Delphi-classic `private`.'
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Public member could be protected';
      ShortDesc: 'Public member referenced only from subclasses, never externally';
      BadEx    : 'public' + #13#10 + '  procedure HookForSubclasses; virtual;';
      GoodEx   : 'protected' + #13#10 + '  procedure HookForSubclasses; virtual;'
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Unused public member (dead API)';
      ShortDesc: 'Public member is never referenced from any subclass or cross-unit path';
      BadEx    : 'public' + #13#10 + '  procedure NeverCalled;';
      GoodEx   : '(remove or document why it stays)'
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Unused local variable';
      ShortDesc: 'Local var declared but never referenced in method body';
      BadEx    : 'var' + #13#10 + '  Tmp: Integer;   // never used' + #13#10 + 'begin' + #13#10 +
        '  DoStuff;' + #13#10 + 'end;';
      GoodEx   : '(remove the variable)'
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Unused method parameter';
      ShortDesc: 'Method parameter is never used in the body';
      BadEx    : 'procedure Process(const Data: TData; Mode: Integer);  // Mode never referenced';
      GoodEx   : 'procedure Process(const Data: TData);'
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Tautological boolean expression';
      ShortDesc: 'Binary operator with identical LHS and RHS: x = x, a and a, (p <> p)';
      BadEx    : 'if (a = a) then ...';
      GoodEx   : 'if (a = b) then ...'
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Master-Detail without MasterFields';
      ShortDesc: 'TDataSet has MasterSource set but no MasterFields / IndexFieldNames';
      BadEx    : 'QDetail.MasterSource = dsMaster   // MasterFields = '''' (empty)';
      GoodEx   : 'QDetail.MasterSource = dsMaster   QDetail.MasterFields = ''OrderID'''
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Form has many DB components - split DataModule';
      ShortDesc: 'Aggregated hint: form holds >= N DB components';
      BadEx    : '(TForm with 5+ TFDQuery/TFDConnection components)';
      GoodEx   : '(move all DB components to a TDataModule)'
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE without WHERE';
      ShortDesc: 'SQL statement modifies every row - missing WHERE clause';
      BadEx    : 'Q.SQL.Text := ''UPDATE Users SET Active=0'';';
      GoodEx   : 'Q.SQL.Text := ''UPDATE Users SET Active=0 WHERE Id=:id'';'
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format() float spec without TFormatSettings';
      ShortDesc: '%.2f / %.3f without explicit TFormatSettings - comma vs dot decimal trap';
      BadEx    : 'S := Format(''%.2f'', [Price]);';
      GoodEx   : 'S := Format(''%.2f'', [Price], TFormatSettings.Invariant);'
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'goto statement';
      ShortDesc: '`goto` weakens structured control flow';
      BadEx    : 'label MyExit;' + #13#10 + 'begin' + #13#10 + '  if Failed then goto MyExit;' + #13#10 +
        '  ...' + #13#10 + '  MyExit:' + #13#10 + 'end;';
      GoodEx   : 'if Failed then Exit;' + #13#10 + '...'
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tab character in source';
      ShortDesc: 'Tab characters render inconsistently across editors - use spaces';
      BadEx    : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '<TAB>DoStuff;' + #13#10 + 'end;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  DoStuff;' + #13#10 + 'end;'
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Source line too long';
      ShortDesc: 'Line exceeds 120 characters - wrap or extract subexpression';
      BadEx    : 'result := SomeReallyLongFunction(ArgumentOne, ArgumentTwo, ArgumentThree, ArgumentFour, ArgumentFive);';
      GoodEx   : 'result := SomeReallyLongFunction(' + #13#10 + '  ArgumentOne, ArgumentTwo,' + #13#10 +
        '  ArgumentThree, ArgumentFour, ArgumentFive);'
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Trailing whitespace';
      ShortDesc: 'Line ends with space or tab - hygiene for diffs';
      BadEx    : '  DoStuff;   <-- trailing spaces';
      GoodEx   : '  DoStuff;'
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Pascal keyword not lowercase';
      ShortDesc: 'Pascal keywords (`begin`/`end`/`procedure`/...) should be lowercase';
      BadEx    : 'Procedure Foo;' + #13#10 + 'Begin' + #13#10 + '  If X then DoStuff;' + #13#10 + 'End;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  if X then DoStuff;' + #13#10 + 'end;'
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'NOSONAR suppression marker';
      ShortDesc: '`// NOSONAR` marker should not silence findings - audit usage';
      BadEx    : 'Dispose(P); // NOSONAR - we know about this';
      GoodEx   : '// noinspection - covered by integration test' + #13#10 + 'Dispose(P);'
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Empty argument list';
      ShortDesc: '`Foo()` should be `Foo;` - drop empty parens';
      BadEx    : 'MyProc();' + #13#10 + 'Result := MyFunc();';
      GoodEx   : 'MyProc;' + #13#10 + 'Result := MyFunc;'
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Inline assembly block';
      ShortDesc: '`asm...end` block - prefer Pascal + compiler intrinsics';
      BadEx    : 'function Cpuid: Cardinal;' + #13#10 + 'asm' + #13#10 + '  XOR EAX, EAX' + #13#10 +
        '  CPUID' + #13#10 + 'end;';
      GoodEx   : 'function Cpuid: Cardinal;' + #13#10 + 'begin' + #13#10 + '  Result := GetCpuFeatures;' +
        #13#10 + 'end;'
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Trailing comma in argument list';
      ShortDesc: '`Foo(A, B,)` - drop the comma or add the missing argument';
      BadEx    : 'WriteLn(''A'', ''B'', );' + #13#10 + 'DoStuff(Param1, Param2,);';
      GoodEx   : 'WriteLn(''A'', ''B'');' + #13#10 + 'DoStuff(Param1, Param2);'
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Integer literal without digit grouping';
      ShortDesc: 'Large integer literals should use `_` separator';
      BadEx    : 'const TIMEOUT_MS = 1800000;' + #13#10 + 'const MAX_BYTES = 10485760;';
      GoodEx   : 'const TIMEOUT_MS = 1_800_000;' + #13#10 + 'const MAX_BYTES = 10_485_760;'
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Commented-out code';
      ShortDesc: 'Comment looks like Pascal code - delete or document';
      BadEx    : '// X := 42;' + #13#10 + '// if Active then Process;';
      GoodEx   : '// TODO: re-enable once issue #123 is fixed - see history'
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Unit-level keyword not at column 1';
      ShortDesc: '`unit`/`interface`/`implementation`/`initialization`/`finalization` should start at column 1';
      BadEx    : '  implementation' + #13#10 + #13#10 + '  procedure Foo; ...';
      GoodEx   : 'implementation' + #13#10 + #13#10 + 'procedure Foo; ...'
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : 'Redundant boolean comparison';
      ShortDesc: '`X = True` should be `X` (and `X <> False` likewise)';
      BadEx    : 'if Active = True then ...' + #13#10 + 'if Disabled <> False then ...';
      GoodEx   : 'if Active then ...' + #13#10 + 'if Disabled then ...'
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'Empty interface declaration';
      ShortDesc: 'Interface with no methods/properties carries no contract';
      BadEx    : 'type IServiceMarker = interface end;';
      GoodEx   : 'type ServiceMarkerAttribute = class(TCustomAttribute) end;'
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert without message';
      ShortDesc: '`Assert(cond);` - add a `''why''` message for diagnosis';
      BadEx    : 'Assert(Items.Count > 0);';
      GoodEx   : 'Assert(Items.Count > 0, ''caller must ensure non-empty Items'');'
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'Explicit TObject inheritance';
      ShortDesc: '`class(TObject)` is redundant - drop the parens';
      BadEx    : 'type TFoo = class(TObject) ... end;';
      GoodEx   : 'type TFoo = class ... end;'
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'Grouped variable / field / parameter declaration';
      ShortDesc: 'Split `A, B: Type` into one declaration per line';
      BadEx    : 'var A, B, C: Integer;' + #13#10 + 'field FX, FY: TPoint;';
      GoodEx   : 'var A: Integer;' + #13#10 + '    B: Integer;' + #13#10 + '    C: Integer;'
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Empty begin..end block';
      ShortDesc: 'Empty `begin..end` - delete it or fill in the statement';
      BadEx    : 'if Active then begin end;';
      GoodEx   : 'if Active then Activate;'
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Catch-all on root Exception class';
      ShortDesc: '`on E: Exception do` swallows everything including AV/OOM';
      BadEx    : 'try Foo; except on E: Exception do Log(E.Message); end;';
      GoodEx   : 'try Foo; except on E: EDatabaseError do Log(E.Message); end;'
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Consecutive const/type/var section';
      ShortDesc: 'Two `const`/`type`/`var` blocks in a row should be merged';
      BadEx    : 'const A = 1;' + #13#10 + 'const B = 2;';
      GoodEx   : 'const' + #13#10 + '  A = 1;' + #13#10 + '  B = 2;'
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : 'Redundant Exit/Continue/Break before end';
      ShortDesc: '`Exit;` / `Continue;` / `Break;` directly before `end` is a no-op';
      BadEx    : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  DoStuff;' + #13#10 + '  Exit;' + #13#10 +
        'end;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  DoStuff;' + #13#10 + 'end;'
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Multiple class declarations in one file';
      ShortDesc: 'One class per unit makes refactoring easier';
      BadEx    : 'type' + #13#10 + '  TFoo = class ... end;' + #13#10 + '  TBar = class ... end;';
      GoodEx   : '// uFoo.pas' + #13#10 + 'type TFoo = class ... end;' + #13#10 + '// uBar.pas' + #13#10 +
        'type TBar = class ... end;'
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Double semicolon';
      ShortDesc: '`;;` - drop the extra semicolon';
      BadEx    : 'DoStuff;;';
      GoodEx   : 'DoStuff;'
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Empty finally block';
      ShortDesc: '`try ... finally end;` has no cleanup - either add it or drop the finally';
      BadEx    : 'Stream := TFileStream.Create(P);' + #13#10 + 'try' + #13#10 + '  ...' + #13#10 + 'finally' +
        #13#10 + 'end;';
      GoodEx   : 'Stream := TFileStream.Create(P);' + #13#10 + 'try' + #13#10 + '  ...' + #13#10 + 'finally' +
        #13#10 + '  Stream.Free;' + #13#10 + 'end;'
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : 'Redundant Assigned + nil check';
      ShortDesc: '`Assigned(X) and (X <> nil)` - drop the nil check';
      BadEx    : 'if Assigned(Obj) and (Obj <> nil) then ...';
      GoodEx   : 'if Assigned(Obj) then ...'
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; should be FreeAndNil(X)';
      ShortDesc: 'Use `FreeAndNil(X)` instead of `X.Free; X := nil;`';
      BadEx    : 'Obj.Free;' + #13#10 + 'Obj := nil;';
      GoodEx   : 'FreeAndNil(Obj);'
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : 'Avoid out parameter modifier';
      ShortDesc: 'Prefer `var` over `out` (out has surprising semantics)';
      BadEx    : 'procedure Foo(out S: string);';
      GoodEx   : 'procedure Foo(var S: string);'
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Empty visibility section in class';
      ShortDesc: '`public`/`private`/... section header with no members';
      BadEx    : 'type TFoo = class' + #13#10 + '  public' + #13#10 + '  private' + #13#10 +
        '    FX: Integer;' + #13#10 + '  end;';
      GoodEx   : 'type TFoo = class' + #13#10 + '  private' + #13#10 + '    FX: Integer;' + #13#10 + '  end;'
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Legacy unit-init begin..end.';
      ShortDesc: 'Use `initialization..end.` instead of legacy `begin..end.`';
      BadEx    : '// at end of unit:' + #13#10 + 'begin' + #13#10 + '  RegisterClass(TFoo);' + #13#10 +
        'end.';
      GoodEx   : 'initialization' + #13#10 + '  RegisterClass(TFoo);' + #13#10 + 'end.'
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Public field in class';
      ShortDesc: 'Public field breaks encapsulation - use a property';
      BadEx    : 'type TFoo = class' + #13#10 + '  public' + #13#10 + '    Count: Integer;' + #13#10 +
        '  end;';
      GoodEx   : 'type TFoo = class' + #13#10 + '  private' + #13#10 + '    FCount: Integer;' + #13#10 +
        '  public' + #13#10 + '    property Count: Integer read FCount write FCount;' + #13#10 +
        '  end;'
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Nested try block';
      ShortDesc: 'Nested `try..end` - consider extracting inner try into a method';
      BadEx    : 'try' + #13#10 + '  try' + #13#10 + '    DoStuff;' + #13#10 + '  finally' + #13#10 +
        '    Cleanup;' + #13#10 + '  end;' + #13#10 + 'except' + #13#10 + '  Log;' + #13#10 + 'end;';
      GoodEx   : 'ProtectedDoStuff;  // helper wraps the inner try'
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Large case statement';
      ShortDesc: '`case` with >= 10 branches - consider polymorphism / dispatch table';
      BadEx    : 'case Op of' + #13#10 + '  opA: ...; opB: ...; opC: ...; opD: ...; opE: ...;' + #13#10 +
        '  opF: ...; opG: ...; opH: ...; opI: ...; opJ: ...;' + #13#10 + 'end;';
      GoodEx   : 'FOperations[Op].Execute;  // dispatch table'
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit contains no declarations';
      ShortDesc: 'Unit has no type/const/var/procedure/function - delete or fill in';
      BadEx    : 'unit X;' + #13#10 + 'interface' + #13#10 + 'implementation' + #13#10 + 'end.';
      GoodEx   : '// delete the file'
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Multiple inherited calls in one method';
      ShortDesc: 'Two or more `inherited;` in the same method - parent side-effects run twice';
      BadEx    : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  inherited;' + #13#10 + '  DoStuff;' +
        #13#10 + '  inherited;' + #13#10 + 'end;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'begin' + #13#10 + '  inherited;' + #13#10 + '  DoStuff;' +
        #13#10 + 'end;'
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : 'Redundant double parentheses';
      ShortDesc: '`((Ident))` - drop the outer parens';
      BadEx    : 'if ((Active)) then ...' + #13#10 + 'Result := ((42));';
      GoodEx   : 'if Active then ...' + #13#10 + 'Result := 42;'
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Consecutive visibility section';
      ShortDesc: 'Same `public`/`private`/etc. section appears twice in one class';
      BadEx    : 'type TFoo = class' + #13#10 + '  private FX: Integer;' + #13#10 + '  public procedure A;' +
        #13#10 + '  private FY: Integer;' + #13#10 + '  end;';
      GoodEx   : 'type TFoo = class' + #13#10 + '  private' + #13#10 + '    FX, FY: Integer;' + #13#10 +
        '  public procedure A;' + #13#10 + '  end;'
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Constructor without inherited call';
      ShortDesc: 'Constructor missing `inherited Create` - parent stays uninitialized';
      BadEx    : 'constructor TFoo.Create;' + #13#10 + 'begin' + #13#10 + '  FX := 0;' + #13#10 + 'end;';
      GoodEx   : 'constructor TFoo.Create;' + #13#10 + 'begin' + #13#10 + '  inherited;' + #13#10 +
        '  FX := 0;' + #13#10 + 'end;'
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destructor without inherited call';
      ShortDesc: 'Destructor missing `inherited Destroy` - parent cleanup is skipped (leak risk)';
      BadEx    : 'destructor TFoo.Destroy;' + #13#10 + 'begin' + #13#10 + '  FreeAndNil(FBar);' + #13#10 +
        'end;';
      GoodEx   : 'destructor TFoo.Destroy;' + #13#10 + 'begin' + #13#10 + '  FreeAndNil(FBar);' + #13#10 +
        '  inherited;' + #13#10 + 'end;'
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : 'Redundant conditional assignment';
      ShortDesc: '`if Cond then X := True else X := False` should be `X := Cond`';
      BadEx    : 'if Active then Result := True else Result := False;';
      GoodEx   : 'Result := Active;'
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'Asymmetric begin/end in if/else';
      ShortDesc: 'then-branch uses `begin..end` but else-branch is a single statement';
      BadEx    : 'if Active then' + #13#10 + 'begin' + #13#10 + '  DoA;' + #13#10 + '  DoB;' + #13#10 + 'end' +
        #13#10 + 'else' + #13#10 + '  DoC;';
      GoodEx   : 'if Active then' + #13#10 + 'begin' + #13#10 + '  DoA;' + #13#10 + '  DoB;' + #13#10 + 'end' +
        #13#10 + 'else' + #13#10 + 'begin' + #13#10 + '  DoC;' + #13#10 + 'end;'
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Pointer type alias not prefixed with P';
      ShortDesc: '`Foo = ^Bar` should be `PBar = ^Bar` (P-prefix convention)';
      BadEx    : 'type TIntPtr = ^Integer;';
      GoodEx   : 'type PInteger = ^Integer;'
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Branch without begin..end block';
      ShortDesc: '`then`/`else`/`do <stmt>` - prefer explicit `begin..end`';
      BadEx    : 'if Active then DoStuff;';
      GoodEx   : 'if Active then' + #13#10 + 'begin' + #13#10 + '  DoStuff;' + #13#10 + 'end;'
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Nested routine inside another method';
      ShortDesc: 'Local nested procedure/function - extract to unit-level';
      BadEx    : 'procedure Outer;' + #13#10 + '  procedure Inner; begin DoX; end;' + #13#10 + 'begin' +
        #13#10 + '  Inner;' + #13#10 + 'end;';
      GoodEx   : 'procedure Inner; begin DoX; end;' + #13#10 + 'procedure Outer;' + #13#10 + 'begin' + #13#10 +
        '  Inner;' + #13#10 + 'end;'
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Class field not prefixed with F';
      ShortDesc: 'Class fields should follow `F<Name>` convention';
      BadEx    : 'type TFoo = class' + #13#10 + '  private' + #13#10 + '    Counter: Integer;' + #13#10 +
        '  end;';
      GoodEx   : 'type TFoo = class' + #13#10 + '  private' + #13#10 + '    FCounter: Integer;' + #13#10 +
        '  end;'
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Class/record type not prefixed with T';
      ShortDesc: 'Class and record type aliases should start with `T`';
      BadEx    : 'type Counter = class' + #13#10 + '  ...' + #13#10 + '  end;';
      GoodEx   : 'type TCounter = class' + #13#10 + '  ...' + #13#10 + '  end;'
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Interface type not prefixed with I';
      ShortDesc: 'Interface aliases should start with `I` (`IFoo = interface`)';
      BadEx    : 'type Service = interface [''{...}''] end;';
      GoodEx   : 'type IService = interface [''{...}''] end;'
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'Method not in PascalCase';
      ShortDesc: 'Methods should start with an uppercase letter (PascalCase)';
      BadEx    : 'procedure doStuff;';
      GoodEx   : 'procedure DoStuff;'
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Public member could be strict private';
      ShortDesc: 'Public member is referenced ONLY by methods of its declaring class - `strict private` reaches the strongest encapsulation';
      BadEx    : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  public' + #13#10 +
        '    procedure Helper;       // only TFoo.Run calls it' + #13#10 + '    procedure Run;' +
        #13#10 + '  end;';
      GoodEx   : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  strict private' + #13#10 +
        '    procedure Helper;' + #13#10 + '  public' + #13#10 + '    procedure Run;' + #13#10 +
        '  end;'
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize from destructor';
      ShortDesc: 'Synchronize() called from destructor Destroy - classic deadlock between worker and UI thread';
      BadEx    : 'destructor TWorker.Destroy;' + #13#10 + 'begin' + #13#10 +
        '  Synchronize(procedure begin Form1.Log(''done'') end);  // deadlock' + #13#10 +
        '  inherited;' + #13#10 + 'end;';
      GoodEx   : '// Move the notify outside the destructor:' + #13#10 +
        '// trigger an OnTerminate handler that runs BEFORE TThread.Destroy waits.' + #13#10 +
        'FOnDone := procedure begin Form1.Log(''done'') end;' + #13#10 + 'OnTerminate := FOnDone;' +
        #13#10 + '// destructor stays Synchronize-free.'
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Lock acquired without try/finally release';
      ShortDesc: 'TCriticalSection / Monitor / WinAPI lock taken without enclosing try..finally - exception leaves the lock held';
      BadEx    : 'FLock.Enter;' + #13#10 + 'DoWork;     // exception here leaves FLock held forever' + #13#10 +
        'FLock.Leave;';
      GoodEx   : 'FLock.Enter;' + #13#10 + 'try' + #13#10 + '  DoWork;' + #13#10 + 'finally' + #13#10 +
        '  FLock.Leave;' + #13#10 + 'end;'
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'String concatenation in loop';
      ShortDesc: '`s := s + x` inside for/while/repeat - quadratic reallocations';
      BadEx    : 'for i := 0 to High(Names) do' + #13#10 + '  s := s + Names[i] + '', '';';
      GoodEx   : 'var SB := TStringBuilder.Create;' + #13#10 + 'try' + #13#10 +
        '  for i := 0 to High(Names) do' + #13#10 + '    SB.Append(Names[i]).Append('', '');' +
        #13#10 + '  s := SB.ToString;' + #13#10 + 'finally SB.Free; end;'
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) called in loop';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` inside a loop - linear lookup per iteration';
      BadEx    : 'for i := 0 to High(Ids) do begin' + #13#10 + '  Q.ParamByName(''id'').AsInteger := Ids[i];' +
        #13#10 + '  Q.ExecSQL;' + #13#10 + 'end;';
      GoodEx   : 'var P := Q.ParamByName(''id'');' + #13#10 + 'for i := 0 to High(Ids) do begin' + #13#10 +
        '  P.AsInteger := Ids[i];' + #13#10 + '  Q.ExecSQL;' + #13#10 + 'end;'
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) called in loop';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` inside a loop - linear lookup per row';
      BadEx    : 'while not Q.Eof do begin' + #13#10 +
        '  Total := Total + Q.FieldByName(''Amount'').AsCurrency;' + #13#10 + '  Q.Next;' + #13#10 +
        'end;';
      GoodEx   : 'var Amt := Q.FieldByName(''Amount'');' + #13#10 + 'while not Q.Eof do begin' + #13#10 +
        '  Total := Total + Amt.AsCurrency;' + #13#10 + '  Q.Next;' + #13#10 + 'end;'
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume is deprecated';
      ShortDesc: '`MyThread.Resume` - use `MyThread.Start` (since Delphi 2010)';
      BadEx    : 'MyThread := TWorker.Create(True);' + #13#10 + 'MyThread.Resume;';
      GoodEx   : 'MyThread := TWorker.Create(True);' + #13#10 + 'MyThread.Start;'
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread destroyed without Terminate+WaitFor';
      ShortDesc: '`FreeAndNil(MyThread)` without prior `Terminate; WaitFor` - worker may still run';
      BadEx    : '// inside an OnClick:' + #13#10 + 'FreeAndNil(FWorker);  // FWorker.Execute still running?';
      GoodEx   : 'FWorker.Terminate;' + #13#10 + 'FWorker.WaitFor;' + #13#10 + 'FreeAndNil(FWorker);'
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'Plaintext HTTP URL';
      ShortDesc: '`''http://...''` literal for a remote endpoint - MITM-vulnerable';
      BadEx    : 'Url := ''http://api.example.com/v1/users'';';
      GoodEx   : 'Url := ''https://api.example.com/v1/users'';'
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'TLS verification disabled';
      ShortDesc: 'Empty `SecureProtocols`, `IgnoreCertificateErrors := True`, or `OnVerifyPeer := nil`';
      BadEx    : 'Client.SecureProtocols := [];' + #13#10 + 'Client.IgnoreCertificateErrors := True;';
      GoodEx   : 'Client.SecureProtocols := [TLSv1_2, TLSv1_3];' + #13#10 +
        'Client.OnVerifyPeer := VerifyPinnedFingerprint;'
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Public member missing doc comment';
      ShortDesc: 'Public method or property in `interface` section with no doc comment directly above';
      BadEx    : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  public' + #13#10 + '    procedure Run;' +
        #13#10 + '  end;';
      GoodEx   : 'type' + #13#10 + '  TFoo = class' + #13#10 + '  public' + #13#10 +
        '    /// <summary>Starts the worker.</summary>' + #13#10 + '    procedure Run;' + #13#10 +
        '  end;'
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Exception class without `E` prefix';
      ShortDesc: '`class(Exception)`-Descendant should follow Delphi-RTL `E<Name>` convention';
      BadEx    : 'type' + #13#10 + '  MyError = class(Exception);';
      GoodEx   : 'type' + #13#10 + '  EMyError = class(Exception);'
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Local constant not in UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` inside a method - prefer UPPER_SNAKE_CASE for numeric constants';
      BadEx    : 'procedure Foo;' + #13#10 + 'const' + #13#10 + '  MaxRetries = 3;' + #13#10 +
        'begin ... end;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'const' + #13#10 + '  MAX_RETRIES = 3;' + #13#10 +
        'begin ... end;'
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception constructed but never raised';
      ShortDesc: '`EFoo.Create(''msg'');` allocates an exception object without `raise` - the error path is silently skipped';
      BadEx    : 'procedure Validate(x: Integer);' + #13#10 + 'begin' + #13#10 + '  if x < 0 then' + #13#10 +
        '    EArgumentOutOfRangeException.Create(''x negative'');  // never raised!' + #13#10 +
        'end;';
      GoodEx   : 'procedure Validate(x: Integer);' + #13#10 + 'begin' + #13#10 + '  if x < 0 then' + #13#10 +
        '    raise EArgumentOutOfRangeException.Create(''x negative'');' + #13#10 + 'end;'
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'Function never assigns Result';
      ShortDesc: 'Function body finishes without writing `Result` (or `<FunctionName> := ...`) - return value is undefined';
      BadEx    : 'function GetCount(L: TList): Integer;' + #13#10 + 'begin' + #13#10 + '  if L = nil then' +
        #13#10 + '    LogMessage(''nil list'');' + #13#10 + '  // Result never set -> garbage' +
        #13#10 + 'end;';
      GoodEx   : 'function GetCount(L: TList): Integer;' + #13#10 + 'begin' + #13#10 + '  Result := 0;' +
        #13#10 + '  if L <> nil then' + #13#10 + '    Result := L.Count;' + #13#10 + 'end;'
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Re-raise of bound exception variable';
      ShortDesc: '`on E: T do ... raise E;` discards the original stack trace - use bare `raise;` to keep it';
      BadEx    : 'try' + #13#10 + '  RiskyCall;' + #13#10 + 'except' + #13#10 + '  on E: EDivByZero do' +
        #13#10 + '  begin' + #13#10 + '    Log(E.Message);' + #13#10 +
        '    raise E;          // loses original trace' + #13#10 + '  end;' + #13#10 + 'end;';
      GoodEx   : 'try' + #13#10 + '  RiskyCall;' + #13#10 + 'except' + #13#10 + '  on E: EDivByZero do' +
        #13#10 + '  begin' + #13#10 + '    Log(E.Message);' + #13#10 +
        '    raise;            // preserves trace' + #13#10 + '  end;' + #13#10 + 'end;'
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Type-cast immediately before Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - the type-cast has no effect on which Destroy runs (Destroy is virtual)';
      BadEx    : 'procedure Cleanup(L: TObject);' + #13#10 + 'begin' + #13#10 +
        '  TStringList(L).Free;     // cast has no effect on dispatch' + #13#10 + 'end;';
      GoodEx   : 'procedure Cleanup(L: TObject);' + #13#10 + 'begin' + #13#10 +
        '  L.Free;                  // virtual Destroy resolves at runtime' + #13#10 + 'end;'
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Constructor invoked on instance instead of class';
      ShortDesc: '`obj.Create` - invokes constructor as method on an existing instance, skips allocation and re-runs field initialisation over live data';
      BadEx    : 'procedure Reset;' + #13#10 + 'var list: TStringList;' + #13#10 + 'begin' + #13#10 +
        '  list := TStringList.Create;' + #13#10 + '  ...' + #13#10 +
        '  list.Create;            // no allocation, re-initialises the existing object' + #13#10 +
        'end;';
      GoodEx   : 'procedure Reset;' + #13#10 + 'var list: TStringList;' + #13#10 + 'begin' + #13#10 +
        '  list := TStringList.Create;' + #13#10 + '  ...' + #13#10 +
        '  list.Clear;             // or FreeAndNil + new TStringList.Create' + #13#10 + 'end;'
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Override whose entire body is `inherited;`';
      ShortDesc: 'An override that only forwards to the parent serves no purpose - remove it';
      BadEx    : 'procedure TFooSubclass.AfterConstruction; override;' + #13#10 + 'begin' + #13#10 +
        '  inherited;     // adds nothing - drop this whole override' + #13#10 + 'end;';
      GoodEx   : '// Remove the override entirely. The parent''s AfterConstruction will' + #13#10 +
        '// be invoked by the normal virtual dispatch.'
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Use Assigned() instead of `= nil` / `<> nil`';
      ShortDesc: 'Pascal convention: `Assigned(x)` and `not Assigned(x)` are the canonical nil-checks';
      BadEx    : 'if Obj = nil then' + #13#10 + '  Exit;' + #13#10 + 'if Obj <> nil then' + #13#10 +
        '  Obj.DoStuff;';
      GoodEx   : 'if not Assigned(Obj) then' + #13#10 + '  Exit;' + #13#10 + 'if Assigned(Obj) then' + #13#10 +
        '  Obj.DoStuff;'
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Raise the bare `Exception` base class instead of a specific subclass';
      ShortDesc: '`raise Exception.Create(''...'')` - the base class carries no semantic information, callers cannot filter selectively';
      BadEx    : 'if x < 0 then' + #13#10 + '  raise Exception.Create(''x is negative'');';
      GoodEx   : 'if x < 0 then' + #13#10 +
        '  raise EArgumentOutOfRangeException.CreateFmt(''x = %d'', [x]);'
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Locale-dependent format call without explicit TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` etc. without TFormatSettings depend on the system locale - breaks across machines / users';
      BadEx    : 'var d := StrToDate(UserInput);     // breaks under EN locale' + #13#10 +
        'WriteLn(DateToStr(Now));';
      GoodEx   : 'var FS := TFormatSettings.Invariant;' + #13#10 + 'var d := StrToDate(UserInput, FS);' +
        #13#10 + 'WriteLn(DateToStr(Now, FS));'
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'Cast from string to 8-bit string type without explicit encoding';
      ShortDesc: '`AnsiString(s)` / `UTF8String(s)` / `RawByteString(s)` silently drops characters outside the active code page';
      BadEx    : 'var u: UnicodeString;' + #13#10 + 'u := ''Smiley: '' + #$1F600;' + #13#10 +
        'logStream.WriteString(AnsiString(u));   // smiley becomes ''?''';
      GoodEx   : 'var u: UnicodeString;' + #13#10 + 'u := ''Smiley: '' + #$1F600;' + #13#10 +
        'logStream.WriteString(UTF8Encode(u));   // explicit, full Unicode'
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Cast of Char value to PChar reinterprets codepoint as pointer';
      ShortDesc: '`PChar(''A'')` is not `PChar("A")` - the cast treats the 16-bit codepoint as a raw memory address';
      BadEx    : 'var p: PChar;' + #13#10 + 'p := PChar(''A'');           // p = $00000041 (not a string)' +
        #13#10 + 'ShowMessage(p);              // access violation';
      GoodEx   : 'var p: PChar;' + #13#10 + 'p := PChar(string(''A''));    // explicit string wrap' + #13#10 +
        'ShowMessage(p);'
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() evaluates both branches - no short-circuit';
      ShortDesc: '`Math.IfThen(cond, A(), B())` / `StrUtils.IfThen` are normal functions - both arms run before the function is called';
      BadEx    : 'x := Math.IfThen(IsCacheHit, FetchFromCache, FetchFromDb);' + #13#10 +
        '//                            both calls run every time';
      GoodEx   : 'if IsCacheHit then' + #13#10 + '  x := FetchFromCache' + #13#10 + 'else' + #13#10 +
        '  x := FetchFromDb;'
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception catches every error';
      ShortDesc: '`on E: Exception do ...` catches the base class and therefore every descendant, including system exceptions that should not be silenced (EOutOfMemory, EAccessViolation, EAbort)';
      BadEx    : 'try' + #13#10 + '  ParseConfig(s);' + #13#10 + 'except' + #13#10 +
        '  on E: Exception do        // swallows EOutOfMemory / EAbort / ...' + #13#10 +
        '    Log(E.Message);' + #13#10 + 'end;';
      GoodEx   : 'try' + #13#10 + '  ParseConfig(s);' + #13#10 + 'except' + #13#10 +
        '  on E: EConvertError do' + #13#10 + '    Log(E.Message);' + #13#10 +
        '  on E: EFileNotFoundException do' + #13#10 + '    Log(E.Message);' + #13#10 + 'end;'
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'Bare raise outside an except/on handler';
      ShortDesc: '`raise;` without an exception expression only works *inside* an except handler (re-raise) - outside it raises NIL and produces an Access Violation';
      BadEx    : 'procedure Foo(x: Integer);' + #13#10 + 'begin' + #13#10 + '  if x < 0 then' + #13#10 +
        '    raise;             // <- no current exception -> AV inside System._Raise' + #13#10 +
        'end;';
      GoodEx   : 'procedure Foo(x: Integer);' + #13#10 + 'begin' + #13#10 + '  if x < 0 then' + #13#10 +
        '    raise EArgumentException.CreateFmt(''x = %d (must be >= 0)'', [x]);' + #13#10 + 'end;'
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable used after Free / FreeAndNil';
      ShortDesc: 'Dereferencing a variable after `Free` or `FreeAndNil` reads a dangling pointer and produces an Access Violation';
      BadEx    : 'L := TStringList.Create;' + #13#10 + 'L.Free;' + #13#10 +
        'L.Add(''x'');           // <- dangling pointer';
      GoodEx   : 'L := TStringList.Create;' + #13#10 + 'try' + #13#10 + '  L.Add(''x'');' + #13#10 +
        'finally' + #13#10 + '  FreeAndNil(L);     // any subsequent L.Method crashes loudly' +
        #13#10 + 'end;'
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Concrete subclass inherits an abstract method without override';
      ShortDesc: 'Class derives from a base with an `abstract` method but does not override it - calling the method on the subclass instance raises EAbstractError at runtime';
      BadEx    : 'type' + #13#10 + '  TBase = class' + #13#10 + '    procedure DoWork; virtual; abstract;' +
        #13#10 + '  end;' + #13#10 + '  TDerived = class(TBase)' + #13#10 +
        '    // DoWork not overridden -> EAbstractError on call' + #13#10 + '  end;';
      GoodEx   : 'type' + #13#10 + '  TDerived = class(TBase)' + #13#10 + '    procedure DoWork; override;' +
        #13#10 + '  end;'
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Constructor allocates fields and raises without try/except';
      ShortDesc: 'Constructor assigns fields with `<Class>.Create` and raises later - partially initialised fields leak on the exception path';
      BadEx    : 'constructor TFoo.Create;' + #13#10 + 'begin' + #13#10 + '  FList := TStringList.Create;' +
        #13#10 + '  FOther := TOther.Create;' + #13#10 + '  if not Valid then' + #13#10 +
        '    raise EInvalidOp.Create(''bad'');     // <- FList + FOther leak' + #13#10 + 'end;';
      GoodEx   : 'constructor TFoo.Create;' + #13#10 + 'begin' + #13#10 + '  FList := TStringList.Create;' +
        #13#10 + '  try' + #13#10 + '    FOther := TOther.Create;' + #13#10 +
        '    if not Valid then' + #13#10 + '      raise EInvalidOp.Create(''bad'');' + #13#10 +
        '  except' + #13#10 + '    FreeAndNil(FOther);' + #13#10 + '    FreeAndNil(FList);' + #13#10 +
        '    raise;' + #13#10 + '  end;' + #13#10 + 'end;'
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Int64 target receives product of two 32-bit operands';
      ShortDesc: '`<Int64-var> := <a> * <b>` evaluates the multiplication in 32-bit before widening - overflow truncates silently';
      BadEx    : 'var' + #13#10 + '  BytesTotal: Int64;' + #13#10 + '  SectorCount, SectorSize: Integer;' +
        #13#10 + 'begin' + #13#10 +
        '  BytesTotal := SectorCount * SectorSize;   // <- 32-bit overflow, then widen';
      GoodEx   : 'BytesTotal := Int64(SectorCount) * SectorSize;' + #13#10 +
        '// Cast one operand; the other is auto-promoted; multiplication is 64-bit.'
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'Class has too many methods or fields';
      ShortDesc: 'A class with more than 20 methods or more than 15 instance fields concentrates too many responsibilities - hard to test, hard to evolve, hard to review';
      BadEx    : 'TUiController = class             // 60 methods, 80 fields' + #13#10 +
        '  FToolbar, FFilters, FGrid, ...: ...;' + #13#10 + '  procedure BuildToolbar;' + #13#10 +
        '  procedure FilterChange(...);' + #13#10 + '  procedure GridDrawCell(...);' + #13#10 +
        '  // 50 more methods mixing concerns' + #13#10 + 'end;';
      GoodEx   : 'TToolbarSlots    = record ... end;' + #13#10 + 'TFilterController = class ... end;' +
        #13#10 + 'TGridRenderer    = class ... end;' + #13#10 + #13#10 +
        'TUiController = class                // ~10 methods, ~5 fields' + #13#10 +
        '  FToolbar: TToolbarSlots;' + #13#10 + '  FFilter:  TFilterController;' + #13#10 +
        '  FGrid:    TGridRenderer;' + #13#10 + '  procedure Setup;' + #13#10 + 'end;'
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free without subsequent nil-out';
      ShortDesc: '`obj.Free;` without `obj := nil;` (or using FreeAndNil) leaves a dangling pointer - any subsequent use is Use-After-Free';
      BadEx    : 'L := TStringList.Create;' + #13#10 + 'try' + #13#10 + '  L.Add(''x'');' + #13#10 +
        'finally' + #13#10 + '  L.Free;             // <- L still points at freed memory' + #13#10 +
        'end;' + #13#10 + 'WriteLn(L.Count);     // Use-After-Free';
      GoodEx   : 'L := TStringList.Create;' + #13#10 + 'try' + #13#10 + '  L.Add(''x'');' + #13#10 +
        'finally' + #13#10 + '  FreeAndNil(L);      // L is nil; further use raises loudly' + #13#10 +
        'end;'
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'Method has too many Exit statements';
      ShortDesc: 'A method with more than 3 Exit calls has too many return paths - hard to read, hard to test, easy to miss one';
      BadEx    : 'function Find(Id: Integer): TUser;' + #13#10 + 'begin' + #13#10 +
        '  if Id < 0 then begin Result := nil; Exit; end;' + #13#10 +
        '  if not Db.Connected then begin Result := nil; Exit; end;' + #13#10 +
        '  if not Cache.Has(Id) then begin Result := DbLoad(Id); Exit; end;' + #13#10 +
        '  Result := Cache.Get(Id);' + #13#10 + '  Exit;                              // 4. Exit' +
        #13#10 + 'end;';
      GoodEx   : 'function Find(Id: Integer): TUser;' + #13#10 + 'begin' + #13#10 + '  Result := nil;' +
        #13#10 + '  if (Id < 0) or not Db.Connected then Exit;' + #13#10 + '  if Cache.Has(Id) then' +
        #13#10 + '    Result := Cache.Get(Id)' + #13#10 + '  else' + #13#10 +
        '    Result := DbLoad(Id);' + #13#10 + 'end;'
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'Class implementation exceeds 500 lines';
      ShortDesc: 'A class whose declaration + implementation methods span more than 500 lines has too many responsibilities';
      BadEx    : '// TMainForm with 800 lines of business logic mixed with UI handlers,' + #13#10 +
        '// database calls and report generation.';
      GoodEx   : '// Extract verticals into focused classes:' + #13#10 +
        'TReportRunner   = class ... end;     // own unit' + #13#10 +
        'TDataController = class ... end;     // own unit' + #13#10 + #13#10 +
        'TMainForm = class(TForm)' + #13#10 + '  FReport: TReportRunner;' + #13#10 +
        '  FData:   TDataController;' + #13#10 + 'end;'
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'uses clause is not in alphabetical order';
      ShortDesc: 'Entries in a `uses` clause are not in alphabetical order - merges become non-deterministic and review harder';
      BadEx    : 'uses' + #13#10 + '  System.SysUtils,' + #13#10 + '  System.Classes,' + #13#10 +
        '  System.IOUtils,                    // <- order broken' + #13#10 + '  System.JSON;';
      GoodEx   : 'uses' + #13#10 + '  System.Classes,' + #13#10 + '  System.IOUtils,' + #13#10 +
        '  System.JSON,' + #13#10 + '  System.SysUtils;'
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'Unit has no descriptive header comment';
      ShortDesc: 'Unit starts with `interface` directly, without an explaining comment block between `unit ...;` and `interface`';
      BadEx    : 'unit MyUnit;' + #13#10 + #13#10 + 'interface' + #13#10 + #13#10 + 'uses ...;';
      GoodEx   : 'unit MyUnit;' + #13#10 + #13#10 +
        '// Database-connection pool: wraps FireDAC TFDConnection setup' + #13#10 +
        '// for the report subsystem. Thread-safe; single instance per app.' + #13#10 + #13#10 +
        'interface' + #13#10 + #13#10 + 'uses ...;'
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Float equality / inequality comparison';
      ShortDesc: '`a = b` or `a <> b` between Single/Double/Extended operands is unreliable due to IEEE-754 rounding - use SameValue/Math.IsZero';
      BadEx    : 'var Ratio: Double;' + #13#10 + '...' + #13#10 +
        'if Ratio = 0.5 then DoStuff;     // <- IEEE-754: almost never true after arithmetic';
      GoodEx   : 'uses System.Math;' + #13#10 + '...' + #13#10 +
        'if SameValue(Ratio, 0.5, 1e-9) then DoStuff;'
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'Raise inside destructor without try/except';
      ShortDesc: 'An unprotected `raise` in a destructor aborts the cleanup chain - inherited Destroy and subsequent FreeAndNil calls are skipped, state stays inconsistent';
      BadEx    : 'destructor TFoo.Destroy;' + #13#10 + 'begin' + #13#10 + '  FList.Free;' + #13#10 +
        '  if Bad then raise EInvalidOp.Create(''oops'');   // <- inherited never runs' + #13#10 +
        '  inherited;' + #13#10 + 'end;';
      GoodEx   : 'destructor TFoo.Destroy;' + #13#10 + 'begin' + #13#10 + '  try' + #13#10 +
        '    FList.Free;' + #13#10 + '    if Bad then raise EInvalidOp.Create(''oops'');' + #13#10 +
        '  except' + #13#10 + '    Log(''cleanup error'');' + #13#10 + '  end;' + #13#10 +
        '  inherited;' + #13#10 + 'end;'
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Boolean parameter used as internal branching flag';
      ShortDesc: 'A Boolean parameter whose value selects between two completely different code paths is a hidden Strategy - prefer two methods with descriptive names';
      BadEx    : 'procedure SendNotification(const Msg: string; IsError: Boolean);' + #13#10 + 'begin' +
        #13#10 + '  if IsError then Notify(Msg, clRed) else Notify(Msg, clBlack);' + #13#10 + 'end;' +
        #13#10 + '// Caller: SendNotification(s, True);     // True = ???';
      GoodEx   : 'procedure SendErrorNotification(const Msg: string);' + #13#10 +
        'begin Notify(Msg, clRed); end;' + #13#10 + #13#10 +
        'procedure SendInfoNotification(const Msg: string);' + #13#10 +
        'begin Notify(Msg, clBlack); end;' + #13#10 + '// Caller: SendErrorNotification(s);'
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'Private method has no caller in the unit';
      ShortDesc: 'A private method that is never referenced from any other method in the same unit is dead code - delete it or wire it up';
      BadEx    : 'TFoo = class' + #13#10 + 'private' + #13#10 +
        '  procedure HelperA;            // <- never called' + #13#10 + 'public' + #13#10 +
        '  procedure DoStuff;' + #13#10 + 'end;';
      GoodEx   : 'TFoo = class' + #13#10 + 'public' + #13#10 + '  procedure DoStuff;' + #13#10 + 'end;' +
        #13#10 + '// or call HelperA from DoStuff to make the dependency explicit'
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'Instance method never accesses Self - could be a class method';
      ShortDesc: 'A method that uses only its parameters (no Self, no instance fields, no virtual chain) is functionally a class method - mark it as such to express the stateless intent';
      BadEx    : 'function TMath.Add(A, B: Integer): Integer;' + #13#10 + 'begin' + #13#10 +
        '  Result := A + B;          // only uses params, no Self' + #13#10 + 'end;';
      GoodEx   : 'class function TMath.Add(A, B: Integer): Integer;' + #13#10 + 'begin' + #13#10 +
        '  Result := A + B;' + #13#10 + 'end;' + #13#10 +
        '// Caller: TMath.Add(1, 2)   // no instance needed'
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'Method shadows a virtual parent method without `override`';
      ShortDesc: 'A method redeclared in a subclass with the same name as a virtual/dynamic parent method, but without the `override` directive, breaks polymorphism - the compiler issues warning W1010';
      BadEx    : 'TBase = class' + #13#10 + '  procedure DoWork; virtual;' + #13#10 + 'end;' + #13#10 +
        #13#10 + 'TDerived = class(TBase)' + #13#10 +
        '  procedure DoWork;          // <- shadows TBase.DoWork (W1010)' + #13#10 + 'end;';
      GoodEx   : 'TDerived = class(TBase)' + #13#10 + '  procedure DoWork; override;' + #13#10 + 'end;'
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'Boolean comparison is always true / always false';
      ShortDesc: 'Comparisons like `Length(s) >= 0` are tautologies - the Length result is never negative, so the condition can never be false';
      BadEx    : 'if Length(s) >= 0 then DoStuff;   // <- always True' + #13#10 +
        'if Length(s) < 0 then DoOther;    // <- always False';
      GoodEx   : 'if Length(s) > 0 then DoStuff;    // non-empty check' + #13#10 +
        'if Length(s) = 0 then DoOther;    // empty check'
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'Function always returns the same literal';
      ShortDesc: 'All paths in the function assign the same literal value to Result - the conditional logic adds no behavioural difference, replace the function with a constant';
      BadEx    : 'function GetTimeout: Integer;' + #13#10 + 'begin' + #13#10 + '  if SlowMode then' + #13#10 +
        '    Result := 30' + #13#10 + '  else' + #13#10 + '    Result := 30;       // <- always 30' +
        #13#10 + 'end;';
      GoodEx   : 'const DEFAULT_TIMEOUT = 30;' + #13#10 + #13#10 + 'function GetTimeout: Integer;' + #13#10 +
        'begin' + #13#10 + '  Result := DEFAULT_TIMEOUT;' + #13#10 + 'end;'
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'User-visible string assigned as literal';
      ShortDesc: 'Caption/Hint/Text assignments and ShowMessage/MessageDlg calls with literal text bypass resourcestring / i18n - the string cannot be translated or replaced for localisation';
      BadEx    : 'Form1.Caption := ''Mein Programm'';' + #13#10 + 'Button1.Hint  := ''Klick mich'';' + #13#10 +
        'ShowMessage(''Daten gespeichert'');';
      GoodEx   : 'resourcestring' + #13#10 + '  SAppCaption = ''Mein Programm'';' + #13#10 +
        '  SBtnHint    = ''Klick mich'';' + #13#10 + '  SSavedMsg   = ''Daten gespeichert'';' +
        #13#10 + #13#10 + 'Form1.Caption := SAppCaption;' + #13#10 + 'Button1.Hint  := SBtnHint;' +
        #13#10 + 'ShowMessage(SSavedMsg);'
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Lock/Unlock pair without try/finally';
      ShortDesc: '<ident>.Lock / EnterCriticalSection / TMonitor.Enter followed by a matching UnLock/Leave/Exit in the same routine without an enclosing try/finally - exception path leaks the lock and deadlocks the next caller';
      BadEx    : 'FLocker.Lock;' + #13#10 + 'DoStuff;' + #13#10 + 'FLocker.UnLock;';
      GoodEx   : 'FLocker.Lock;' + #13#10 + 'try' + #13#10 + '  DoStuff;' + #13#10 + 'finally' + #13#10 +
        '  FLocker.UnLock;' + #13#10 + 'end;'
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar with SizeOf(pointer-type)';
      ShortDesc: 'Move, FillChar, CopyMemory, or ZeroMemory called with SizeOf(PXxx) where PXxx is a pointer type - copies only 4/8 bytes (the pointer size) instead of the intended buffer';
      BadEx    : 'var Buf: array[0..255] of Byte; P: PByte;' + #13#10 +
        'Move(Src^, P^, SizeOf(PByte));        // copies 8 bytes (pointer), not the buffer' + #13#10 +
        'FillChar(P^, SizeOf(PInteger), 0);    // zeroes 8 bytes, not the integer';
      GoodEx   : 'Move(Src^, P^, SizeOf(Byte) * Count);  // explicit element count' + #13#10 +
        'FillChar(V, SizeOf(V), 0);             // matches the variable''s size'
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'with statement on multiple targets';
      ShortDesc: '`with A, B do` (two or more comma-separated receivers) makes member lookup ambiguous - adding a method to either A or B silently changes the meaning of the body';
      BadEx    : 'with Form1, List1 do' + #13#10 + '  DoStuff;     // From Form1 or List1?';
      GoodEx   : 'Form1.DoStuff;' + #13#10 + 'List1.Sort;'
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem without try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem followed by a matching FreeMem in the same routine without an enclosing try/finally - exception path leaks the buffer permanently';
      BadEx    : 'GetMem(P, 1024);' + #13#10 + 'DoStuff(P);' + #13#10 + 'FreeMem(P);';
      GoodEx   : 'GetMem(P, 1024);' + #13#10 + 'try' + #13#10 + '  DoStuff(P);' + #13#10 + 'finally' + #13#10 +
        '  FreeMem(P);' + #13#10 + 'end;'
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) inside a loop';
      ShortDesc: 'Dynamic-array grow-by-one (or grow-by-N) inside a for/while/repeat loop - quadratic reallocation cost; grow once before the loop or use a block-grow strategy';
      BadEx    : 'for i := 0 to Source.Count - 1 do' + #13#10 + 'begin' + #13#10 +
        '  SetLength(Dest, Length(Dest) + 1);  // O(n*n)' + #13#10 +
        '  Dest[High(Dest)] := Source[i];' + #13#10 + 'end;';
      GoodEx   : 'SetLength(Dest, Source.Count);' + #13#10 + 'for i := 0 to Source.Count - 1 do' + #13#10 +
        '  Dest[i] := Source[i];'
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- offset without empty-check';
      ShortDesc: '`PChar(s) + n`, `PAnsiChar(s) + n`, or `PWideChar(s) + n` without a prior empty-check on `s` - PChar('''') optimizes to NIL, so arithmetic on the result is a latent Access Violation';
      BadEx    : 'p := PChar(s) + 5;       // if s='''' then PChar(s)=nil -> AV at $00000005';
      GoodEx   : 'if s <> '''' then' + #13#10 + '  p := PChar(s) + 5;'
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Typed exception handler with empty body';
      ShortDesc: '`on E: SomeException do ;` (or `on E: ... do begin end;`) silently swallows a specific exception class - worse than a bare `except end` because the typed annotation looks intentional';
      BadEx    : 'try DoStuff; except' + #13#10 + '  on E: EDatabaseError do ;' + #13#10 + 'end;';
      GoodEx   : 'try DoStuff; except' + #13#10 + '  on E: EDatabaseError do' + #13#10 + '  begin' + #13#10 +
        '    Logger.Error(E.Message);' + #13#10 + '    raise;' + #13#10 + '  end;' + #13#10 + 'end;'
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'String cast from raw pointer';
      ShortDesc: '`string(P)` / `AnsiString(P)` / `UTF8String(P)` / `RawByteString(P)` cast from a P-prefixed pointer assumes a null-terminator that may not exist - heap overread';
      BadEx    : 's := string(Buf);    // PByte cast assumes null-terminator';
      GoodEx   : 'SetString(s, PChar(Buf), Len);   // explicit length'
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Pointer subtraction via 32-bit cast';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (or Integer / LongWord / LongInt variants) truncates the upper 32 bits of a 64-bit pointer on Win64 - difference is intermittently wrong';
      BadEx    : 'Diff := Cardinal(P1) - Cardinal(P2);   // upper 32 bits lost on Win64';
      GoodEx   : 'Diff := PtrUInt(P1) - PtrUInt(P2);     // pointer-wide cast'
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Use of weak / deprecated cryptographic algorithm';
      ShortDesc: 'Algorithm name (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') or wrapper class (THashMD5, TIdHashSHA1, ...) referenced - vulnerable to collision / known-plaintext attacks';
      BadEx    : 'algo := ''MD5'';' + #13#10 + 'Hash := THashMD5.GetHashString(Input);';
      GoodEx   : 'algo := ''SHA256'';' + #13#10 + 'Hash := THashSHA2.GetHashString(Input);'
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'Shell API called with string concatenation in argument';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec with `+` in the arguments - if any operand is user-controlled it becomes a command-injection vector';
      BadEx    : 'ShellExecute(0, ''open'', PChar(''cmd /c '' + UserInput), nil, nil, SW_SHOW);';
      GoodEx   : '// Validate UserInput against a strict whitelist, then:' + #13#10 +
        'ShellExecute(0, ''open'', ''cmd.exe'', PChar(''/c safe_command''), nil, SW_SHOW);'
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Top-level routine never called';
      ShortDesc: 'Standalone procedure/function in the implementation section is never called from anywhere in the unit and is not exported via the interface section - dead code';
      BadEx    : 'implementation' + #13#10 + 'procedure InternalHelper;     // never called' + #13#10 +
        'begin' + #13#10 + '  WriteLn(''hi'');' + #13#10 + 'end;' + #13#10 + 'end.';
      GoodEx   : 'implementation' + #13#10 + '// remove InternalHelper, or call it from somewhere,' + #13#10 +
        '// or move it to interface if it should be exported'
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Unused noinspection marker';
      ShortDesc: 'A `// noinspection X` marker does not suppress any finding at its target line - either the detector improved (suppression no longer needed) or the suppression target was wrong';
      BadEx    : '// noinspection MemoryLeak' + #13#10 +
        'WriteLn(''hello'');   // no leak here - suppression never fires';
      GoodEx   : '// (Marker entfernt - das Tool flaggt diese Zeile nicht mehr.)' + #13#10 +
        'WriteLn(''hello'');'
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Uninitialised local variable';
      ShortDesc: 'Local variable read before being assigned on every code path through the method';
      BadEx    : 'procedure Foo;' + #13#10 + 'var L: TStringList;' + #13#10 + 'begin' + #13#10 +
        '  if Cond then L := TStringList.Create;' + #13#10 +
        '  L.Add(''x'');   // L undefined if Cond was false -> AV' + #13#10 + 'end;';
      GoodEx   : 'procedure Foo;' + #13#10 + 'var L: TStringList;' + #13#10 + 'begin' + #13#10 +
        '  L := TStringList.Create;' + #13#10 + '  try' + #13#10 + '    L.Add(''x'');' + #13#10 +
        '  finally' + #13#10 + '    L.Free;' + #13#10 + '  end;' + #13#10 + 'end;'
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Random call without prior Randomize';
      ShortDesc: 'Random / RandomRange / RandomFrom used without Randomize - Seed=0 yields a deterministic sequence on every run';
      BadEx    : 'procedure DealCards;' + #13#10 + 'var i: Integer;' + #13#10 + 'begin' + #13#10 +
        '  for i := 1 to 5 do' + #13#10 + '    Players[i].Card := Random(52);' + #13#10 + 'end;';
      GoodEx   : 'procedure DealCards;' + #13#10 + 'var i: Integer;' + #13#10 + 'begin' + #13#10 +
        '  Randomize;   // once, at startup' + #13#10 + '  for i := 1 to 5 do' + #13#10 +
        '    Players[i].Card := Random(52);' + #13#10 + 'end;'
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'case statement without else branch';
      ShortDesc: 'case statement has no else branch - unhandled values fall through silently';
      BadEx    : 'case Status of' + #13#10 + '  stNew    : DoNew;' + #13#10 + '  stActive : DoActive;' +
        #13#10 + 'end;';
      GoodEx   : 'case Status of' + #13#10 + '  stNew    : DoNew;' + #13#10 + '  stActive : DoActive;' +
        #13#10 + 'else' + #13#10 + '  raise EProgrammerError.Create(''Unhandled status'');' + #13#10 +
        'end;'
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'Assert argument contains a function call with side effects';
      ShortDesc: 'Assert(SomeCall) - the call disappears in Release builds and its side effect is silently lost';
      BadEx    : 'Assert(InitializeSubsystem);   // Release build skips Init entirely';
      GoodEx   : 'var Ok := InitializeSubsystem;' + #13#10 + 'Assert(Ok, ''subsystem init failed'');'
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'string parameter without const modifier';
      ShortDesc: 'string parameter declared without const - causes refcount bump on every call';
      BadEx    : 'function Hash(s: string): Integer;';
      GoodEx   : 'function Hash(const s: string): Integer;'
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Compiler switch OFF without matching ON in same file';
      ShortDesc: '{$WARNINGS OFF} (or HINTS/RANGECHECKS/...) without a closing ON - leaks into following units';
      BadEx    : '{$WARNINGS OFF}' + #13#10 + 'procedure Foo;' + #13#10 + 'begin' + #13#10 + 'end;';
      GoodEx   : '{$WARNINGS OFF}' + #13#10 + 'procedure Foo;' + #13#10 + 'begin' + #13#10 + 'end;' + #13#10 +
        '{$WARNINGS ON}'
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Boolean property without Is / Has / Can / Should prefix';
      ShortDesc: 'Boolean property name reads as a noun - prefer a verb prefix that scans as a question';
      BadEx    : 'property Ready: Boolean;';
      GoodEx   : 'property IsReady: Boolean;'
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant in performance-sensitive method (contains a loop)';
      ShortDesc: 'Variant variable inside a method that contains a loop - each Variant operation pays a 10-100x COM dispatch tax';
      BadEx    : 'procedure SumRows;' + #13#10 + 'var v: Variant; i: Integer;' + #13#10 + 'begin' + #13#10 +
        '  for i := 0 to N do v := v + Rows[i];' + #13#10 + 'end;';
      GoodEx   : 'procedure SumRows;' + #13#10 + 'var s: Double; i: Integer;' + #13#10 + 'begin' + #13#10 +
        '  s := 0;' + #13#10 + '  for i := 0 to N do s := s + Rows[i];' + #13#10 + 'end;'
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> filled with T.Create - items leak when list is freed';
      ShortDesc: 'TList<TFoo>.Create + Add(TFoo.Create) - the list does not own its items, every TFoo instance leaks';
      BadEx    : 'L := TList<TFoo>.Create;' + #13#10 + 'L.Add(TFoo.Create);' + #13#10 +
        'L.Free; // TFoo instance leaks';
      GoodEx   : 'L := TObjectList<TFoo>.Create; // OwnsObjects=True default' + #13#10 +
        'L.Add(TFoo.Create);' + #13#10 + 'L.Free; // item freed'
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'Anonymous method captures for-loop variable by reference';
      ShortDesc: 'Anonymous method inside `for i := ... do` references i - all closures see the same final value';
      BadEx    : 'for i := 0 to 9 do' + #13#10 + '  TThread.CreateAnonymousThread(procedure' + #13#10 +
        '  begin WriteLn(i); end).Start;';
      GoodEx   : 'for i := 0 to 9 do' + #13#10 + 'begin' + #13#10 + '  var Captured := i;' + #13#10 +
        '  TThread.CreateAnonymousThread(procedure' + #13#10 +
        '  begin WriteLn(Captured); end).Start;' + #13#10 + 'end;'
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'Method has high cognitive complexity (nested control flow)';
      ShortDesc: 'Sonar-style cognitive-complexity exceeds 15 - nested if/for/while/case is hard to follow mentally';
      BadEx    : 'procedure ProcessOrder(const AOrder: TOrder);' + #13#10 + 'begin' + #13#10 +
        '  if AOrder.IsValid and AOrder.HasItems then        // +1 (depth 0), +1 ''and''  = 2' +
        #13#10 +
        '    for var I := 0 to AOrder.Count - 1 do           // +1+1 (depth 1)          = 2' +
        #13#10 +
        '      while AOrder[I].NeedsRetry do                 // +1+2 (depth 2)          = 3' +
        #13#10 +
        '        if AOrder[I].InStock or AllowBackorder then // +1+3 (depth 3), +1 ''or'' = 5' +
        #13#10 +
        '          case AOrder[I].Kind of                    // +1+4 (depth 4)          = 5' +
        #13#10 + '            ikPhysical:' + #13#10 +
        '              if AOrder[I].Weight > 0 then          // +1+5 (depth 5)          = 6' +
        #13#10 + '                Ship(AOrder[I]);' + #13#10 + '          end;' + #13#10 + 'end;' +
        #13#10 + '// Cognitive complexity = 2+2+3+5+5+6 = 23 (limit 15)';
      GoodEx   : 'procedure ShipItem(const AItem: TOrderItem);' + #13#10 + 'begin' + #13#10 +
        '  if not (AItem.InStock or AllowBackorder) then Exit;  // +1, +1 ''or'' = 2' + #13#10 +
        '  if AItem.Kind <> ikPhysical then Exit;               // +1' + #13#10 +
        '  if AItem.Weight <= 0 then Exit;                      // +1' + #13#10 + '  Ship(AItem);' +
        #13#10 + 'end;' + #13#10 + #13#10 + 'procedure ProcessOrder(const AOrder: TOrder);' + #13#10 +
        'begin' + #13#10 + '  if not AOrder.IsValid then Exit;                     // +1' + #13#10 +
        '  if not AOrder.HasItems then Exit;                    // +1' + #13#10 +
        '  for var I := 0 to AOrder.Count - 1 do                // +1 (depth 0)' + #13#10 +
        '    while AOrder[I].NeedsRetry do                      // +1+1 (depth 1)' + #13#10 +
        '      ShipItem(AOrder[I]);' + #13#10 + 'end;' + #13#10 +
        '// ShipItem = 4, ProcessOrder = 5 - beide klar unter 15'
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Thread variable accessed after FreeOnTerminate := True';
      ShortDesc: 'After T.FreeOnTerminate := True, any subsequent T.Field/T.Method access risks Access-Violation if the thread has already self-destructed';
      BadEx    : 'T := TMyThread.Create(True);' + #13#10 + 'T.FreeOnTerminate := True;' + #13#10 + 'T.Start;' +
        #13#10 + 'T.Resume;   // T may be freed';
      GoodEx   : 'T := TMyThread.Create(True);' + #13#10 + 'T.FreeOnTerminate := True;' + #13#10 + 'T.Start;' +
        #13#10 + 'T := nil;   // drop reference'
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'File-open API receives concatenated user input';
      ShortDesc: 'File-open call (TFileStream.Create, AssignFile, ...) with a path expression that concatenates user input (Edit.Text, Request.Params, ...) - path-traversal risk';
      BadEx    : 'Stream := TFileStream.Create(BaseDir + edPath.Text, fmOpenRead);';
      GoodEx   : 'var SafePath := TPath.Combine(BaseDir, TPath.GetFileName(edPath.Text));' + #13#10 +
        'Stream := TFileStream.Create(SafePath, fmOpenRead);'
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'DUnitX [Ignore] attribute without reason argument';
      ShortDesc: '[Ignore] (no string arg) skips the test silently - add a message explaining why the test is disabled';
      BadEx    : '[Ignore]' + #13#10 + 'procedure SomeTest;';
      GoodEx   : '[Ignore(''TBD ticket #1234 - flaky on CI'')]' + #13#10 + 'procedure SomeTest;'
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Same attribute applied twice to one member';
      ShortDesc: 'Two identical [X] attributes on the same member - copy-paste leftover, no effect';
      BadEx    : '[Test]' + #13#10 + '[Test]' + #13#10 + 'procedure Foo;';
      GoodEx   : '[Test]' + #13#10 + 'procedure Foo;'
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'DUnitX [Category] without category-name string';
      ShortDesc: '[Category] (no arg) is a compile-time error in DUnitX - always pass a category name';
      BadEx    : '[Category]' + #13#10 + 'procedure Foo;';
      GoodEx   : '[Category(''Slow'')]' + #13#10 + 'procedure Foo;'
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : '[TestFixture] class without any [Test] method';
      ShortDesc: 'Class is marked [TestFixture] but contains no [Test] methods - zombie fixture visible in TestInsight but executes nothing';
      BadEx    : '[TestFixture]' + #13#10 + 'TFooTests = class' + #13#10 + '  procedure Helper;' + #13#10 +
        'end;';
      GoodEx   : '[TestFixture]' + #13#10 + 'TFooTests = class' + #13#10 + '  [Test] procedure DoesX;' +
        #13#10 + 'end;'
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribute with blank line before target member';
      ShortDesc: 'Attribute line followed by a blank line - visually loose, often a refactoring leftover';
      BadEx    : '[Test]' + #13#10 + #13#10 + 'procedure Foo;';
      GoodEx   : '[Test]' + #13#10 + 'procedure Foo;'
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Unused DFM component';
      ShortDesc: 'DFM component is never referenced in code, other units, or the DFM itself - possibly a refactoring leftover';
      BadEx    : 'object btnOld: TButton  // removed from code, left in the DFM' + #13#10 + 'end';
      GoodEx   : '(remove the leftover component from the .dfm)'
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'UTF-8 source file without BOM';
      ShortDesc: 'UTF-8 file without BOM + non-ASCII - compiler reads it as ANSI (mojibake)';
      BadEx    : '// file saved as UTF-8 WITHOUT BOM, with non-ASCII text' + #13#10 +
        'ShowMessage(''...non-ASCII...'');  // compiler reads ANSI -> mojibake at runtime';
      GoodEx   : '// same file saved as UTF-8 WITH BOM (EF BB BF), or build --codepage:65001' + #13#10 +
        'ShowMessage(''...non-ASCII...'');'
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'Invalid UTF-8 sequence in source file';
      ShortDesc: 'Malformed UTF-8 (overlong / surrogate / out-of-range) under a UTF-8 BOM';
      BadEx    : '(UTF-8 BOM present, but bytes contain an overlong or surrogate sequence)';
      GoodEx   : '(re-encode the file as valid UTF-8)'
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'NUL or control byte in source file';
      ShortDesc: 'NUL / disallowed control byte - binary file or mis-detected encoding';
      BadEx    : '(file contains 0x00 bytes - e.g. BOM-less UTF-16)';
      GoodEx   : '(save the file as UTF-8 with BOM)'
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Bidirectional override control character (Trojan Source)';
      ShortDesc: 'Bidi override/isolate control char - source reads differently than it compiles';
      BadEx    : '// a comment containing U+202E can visually reorder the code that follows';
      GoodEx   : '// no bidirectional control characters anywhere in source'
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'ANSI source file with non-ASCII content';
      ShortDesc: '8-bit source (no BOM, not valid UTF-8) - code-page-dependent, non-portable';
      BadEx    : '// file saved as Windows-1252 (ANSI) with non-ASCII text, no BOM';
      GoodEx   : '// save the file as UTF-8 with BOM (EF BB BF)'
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'UTF-16 source file';
      ShortDesc: 'UTF-16 source - compiles, but unusual and text-tool-unfriendly';
      BadEx    : '(file saved as UTF-16 LE / BE)';
      GoodEx   : '(save the file as UTF-8 with BOM)'
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'UTF-32 / UCS-4 source file';
      ShortDesc: 'UTF-32 source - Delphi compiler rejects it with fatal error F2438';
      BadEx    : '(file saved as UTF-32 LE / BE - will not compile, F2438)';
      GoodEx   : '(convert to UTF-8 with BOM)'
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Invisible / zero-width character in source';
      ShortDesc: 'Zero-width/invisible Unicode char - hidden-text / homoglyph abuse vector';
      BadEx    : '// an identifier or string with an embedded U+200B is not what it looks like';
      GoodEx   : '// no zero-width / invisible characters in source'
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Non-ASCII character in identifier';
      ShortDesc: 'Identifier contains a non-ASCII letter - homoglyph / confusable risk';
      BadEx    : 'var Login: string;  // one letter is a Cyrillic homoglyph (U+043E), not Latin ''o''';
      GoodEx   : 'var Login: string;  // all-ASCII identifier'
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Source file not part of the project';
      ShortDesc: 'A .pas/.dfm file lies in the project folder but is not referenced by the project (.dproj/.groupproj) - likely an orphaned / dead source file';
      BadEx    : 'MyProject.dproj references uMain, uData - but the folder also contains uOldHelper.pas (not referenced) -> flagged';
      GoodEx   : 'Remove uOldHelper.pas, add it to the project, or move it out of the project folder'
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit used by the project but not included in it';
      ShortDesc: 'A .pas file is referenced via uses by project units (it compiles through the search path) but is not listed in the project file (.dproj/.groupproj) - add it to the project';
      BadEx    : 'MyProject.dproj references uMain - uMain uses uHelper, but uHelper.pas is not in the .dproj -> flagged: add uHelper.pas to the project';
      GoodEx   : 'Every unit reachable via uses from project units is listed as a DCCReference in the .dproj'
    )
  );

