unit uFixHint;

// Loesungs-Hinweise pro Befund-Typ.
//
// Liefert pro TLeakFinding eine kurze Beschreibung sowie zwei Code-Beispiele
// (Vorher / Nachher). Wird sowohl vom IDE-Hilfe-Panel als auch vom Export
// (Jira / Clipboard / HTML) verwendet, daher in eigener Unit.
//
// Sprache: Hint-Texte (Description / Before / After) sind grundsaetzlich
// auf Englisch, unabhaengig von der UI-Sprache. Begruendung: Code-Reviews,
// Jira-Tickets und Claude-AI-Prompts sind in der Praxis englisch; eine
// Lokalisierung wuerde nur das Mischmasch zwischen Quellcode-Beispielen
// und Erklaertext erhoehen.

interface

uses
  System.SysUtils,
  uSCAConsts, uMethodd12;

type
  TFixHint = record
    Description : string;   // Einzeilige Problembeschreibung
    Before      : string;   // Code-Beispiel "Vorher"
    After       : string;   // Code-Beispiel "Nachher"
  end;

  TFixHintResolver = class
  public
    class function FixHint(const Finding: TLeakFinding): TFixHint; static;
  end;

implementation

class function TFixHintResolver.FixHint(const Finding: TLeakFinding): TFixHint;
begin
  Result.Description := '';
  Result.Before      := '';
  Result.After       := '';

  case Finding.Kind of

    fkMemoryLeak:
      if Finding.Severity = lsError then
      begin
        Result.Description := 'Object created but never freed (memory leak)';
        Result.Before :=
          'list := TStringList.Create;'#13#10 +
          'list.Add(''entry'');'#13#10 +
          '// list.Free is missing!'#13#10 +
          '// -> the instance is leaked on every call,'#13#10 +
          '//    visible as growing private bytes / FastMM report.';
        Result.After :=
          'list := TStringList.Create;'#13#10 +
          'try'#13#10 +
          '  list.Add(''entry'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list); // released even on exception'#13#10 +
          'end;'#13#10 +
          ''#13#10 +
          '// Tip: enable ReportMemoryLeaksOnShutdown := True'#13#10 +
          '//      during development to surface leaks at exit.';
      end
      else if Pos(' - R'#$FC'ckgabewert', Finding.MissingVar) > 0 then
      begin
        Result.Description := 'Function return value is not freed by the caller';
        Result.Before :=
          '// The function returns a freshly created object -'#13#10 +
          '// ownership is transferred to the caller, who must Free it.'#13#10 +
          ''#13#10 +
          'list := BuildList();'#13#10 +
          'list.Add(''x'');'#13#10 +
          '// list.Free is missing -> leak on every call!';
        Result.After :=
          '// Option 1: caller takes ownership and frees it.'#13#10 +
          'list := BuildList();'#13#10 +
          'try'#13#10 +
          '  list.Add(''x'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list);'#13#10 +
          'end;'#13#10 +
          ''#13#10 +
          '// Option 2: pass ownership on (Result := list)'#13#10 +
          '//           or use an interface (IList) so reference'#13#10 +
          '//           counting handles release automatically.';
      end
      else
      begin
        Result.Description := 'Free is outside the protecting finally block';
        Result.Before :=
          'list := TStringList.Create;'#13#10 +
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  other.Free;'#13#10 +
          'end;'#13#10 +
          'list.Free; // <- too late!'#13#10 +
          '// any exception inside the try block leaks list.';
        Result.After :=
          'list := TStringList.Create;'#13#10 +
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list); // <- moved into the finally'#13#10 +
          '  other.Free;'#13#10 +
          'end;'#13#10 +
          ''#13#10 +
          '// Rule of thumb: every Create has a matching Free,'#13#10 +
          '// and that Free lives in the finally block.';
      end;

    fkEmptyExcept:
    begin
      Result.Description := 'Empty except block silently swallows every exception';
      Result.Before :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  // empty - swallows EVERYTHING, including'#13#10 +
        '  // EAccessViolation, EOutOfMemory, ...'#13#10 +
        'end;'#13#10 +
        '// Failure becomes invisible: no log, no UI feedback,'#13#10 +
        '// no way for the caller to react. Hardest bug to find.';
      Result.After :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  on E: EDatabaseError do'#13#10 +
        '    Logger.Error(''DB failed: %s'', [E.Message]);'#13#10 +
        '  // re-raise anything else so the caller sees it:'#13#10 +
        '  on E: Exception do'#13#10 +
        '  begin'#13#10 +
        '    Logger.Error(E.Message);'#13#10 +
        '    raise;'#13#10 +
        '  end;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// At minimum: log the error. Better: handle the cases'#13#10 +
        '// you really expect and re-raise the rest.';
    end;

    fkSQLInjection:
    begin
      Result.Description := 'SQL command built with "+" - SQL injection risk';
      Result.Before :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM users'''#13#10 +
        '  + '' WHERE name = '''''' + UserInput + '''''''';'#13#10 +
        ''#13#10 +
        '// An attacker enters: '' OR ''1''=''1'' --'#13#10 +
        '// Result: every row of users is returned.'#13#10 +
        '// Worst case: DROP TABLE users; --';
      Result.After :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM users'''#13#10 +
        '  + '' WHERE name = :Name'';'#13#10 +
        'Query.ParamByName(''Name'').AsString := UserInput;'#13#10 +
        'Query.Open;'#13#10 +
        ''#13#10 +
        '// Parameters are sent separately from the SQL text;'#13#10 +
        '// the database engine treats them as data, never as code.'#13#10 +
        '// Also faster: the query plan can be cached.';
    end;

    fkHardcodedSecret:
    begin
      Result.Description := 'Password / token literal in source code';
      Result.Before :=
        'const'#13#10 +
        '  DB_PWD   = ''secret123'';     // visible in svn log'#13#10 +
        '  API_KEY  = ''sk-abc-xyz'';    // forever in git history'#13#10 +
        ''#13#10 +
        'FPassword := DB_PWD;'#13#10 +
        'FToken    := API_KEY;'#13#10 +
        ''#13#10 +
        '// Visible in:'#13#10 +
        '//   - source repository (every clone)'#13#10 +
        '//   - build artifacts and CI logs'#13#10 +
        '//   - decompiled .exe files';
      Result.After :=
        '// Option 1: ini / config file (gitignored)'#13#10 +
        'FPassword := Ini.ReadString(''Auth'', ''Password'', '''');'#13#10 +
        ''#13#10 +
        '// Option 2: environment variable'#13#10 +
        'FPassword := GetEnvironmentVariable(''APP_PWD'');'#13#10 +
        ''#13#10 +
        '// Option 3: OS credential store / vault'#13#10 +
        '// (Windows Credential Manager, HashiCorp Vault, ...)'#13#10 +
        ''#13#10 +
        '// If a secret was already committed: rotate it!'#13#10 +
        '// Removing it from history is not enough - assume leaked.';
    end;

    fkFormatMismatch:
    begin
      Result.Description := 'Format() placeholder count does not match argument count';
      Result.Before :=
        '// 2 placeholders, only 1 argument'#13#10 +
        's := Format('#13#10 +
        '  ''%s is %d years old'','#13#10 +
        '  [Name]); // <- Age missing!'#13#10 +
        ''#13#10 +
        '// Runtime: EConvertError "Format error".'#13#10 +
        '// Crashes only when this code path actually runs,'#13#10 +
        '// so it often slips through into production.';
      Result.After :=
        '// 2 placeholders, 2 arguments - matched'#13#10 +
        's := Format('#13#10 +
        '  ''%s is %d years old'','#13#10 +
        '  [Name, Age]);'#13#10 +
        ''#13#10 +
        '// Common pitfalls:'#13#10 +
        '//   %%   -> a literal percent sign (not a placeholder)'#13#10 +
        '//   %s   -> string,    %d -> integer,'#13#10 +
        '//   %f   -> float,     %x -> hex,'#13#10 +
        '//   %.2f -> float with two decimals'#13#10 +
        '// Type and count must match exactly.';
    end;

    fkFileReadError:
    begin
      Result.Description := 'File could not be read or parsed';
      Result.Before :=
        '// Possible causes:'#13#10 +
        '//   - unknown / mixed file encoding'#13#10 +
        '//   - file locked or no read permission'#13#10 +
        '//   - file larger than the configured limit (5 MB)'#13#10 +
        '//   - syntax error during parsing'#13#10 +
        '//   - file is generated and not real Pascal'#13#10 +
        '//     (e.g. a .pas produced by a code generator)';
      Result.After :=
        '// Things to try:'#13#10 +
        '//   - save the file as UTF-8 (with or without BOM)'#13#10 +
        '//     or UTF-16 LE'#13#10 +
        '//   - check the file is not held open by another tool'#13#10 +
        '//   - close the file in the IDE before re-running'#13#10 +
        '//   - exclude very large or generated files'#13#10 +
        '//     from the project path'#13#10 +
        '//   - if the parser is unhappy, inspect the line'#13#10 +
        '//     reported in the finding';
    end;

    fkNilDeref:
    begin
      Result.Description := 'Nil dereference: access through a possibly nil reference';
      Result.Before :=
        'obj := nil;'#13#10 +
        '// ... no Create / no assignment ...'#13#10 +
        'obj.DoSomething;  // EAccessViolation at $00000000'#13#10 +
        ''#13#10 +
        '// Or more subtle: function may return nil,'#13#10 +
        '// caller forgets to check:'#13#10 +
        'FindUser(''alice'').SendMail;  // nil if not found';
      Result.After :=
        '// Option 1: create before use'#13#10 +
        'obj := TFoo.Create;'#13#10 +
        'try'#13#10 +
        '  obj.DoSomething;'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(obj);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: defensive check at the call site'#13#10 +
        'if Assigned(obj) then'#13#10 +
        '  obj.DoSomething;'#13#10 +
        ''#13#10 +
        '// Option 3: never return nil - raise instead,'#13#10 +
        '// or return a Null Object that does nothing.';
    end;

    fkMissingFinally:
    begin
      Result.Description := 'Create without try/finally - exception path leaks the object';
      Result.Before :=
        'list := TStringList.Create;'#13#10 +
        'DoWork(list);   // <- exception here'#13#10 +
        'list.Free;      // <- never reached, list leaks'#13#10 +
        ''#13#10 +
        '// Even "obviously safe" code can raise:'#13#10 +
        '// EOutOfMemory, EAccessViolation, EInvalidOp, ...'#13#10 +
        '// Anywhere DoWork can throw, list is leaked.';
      Result.After :=
        'list := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  DoWork(list);'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(list); // always executes'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// The Create line goes OUTSIDE the try.'#13#10 +
        '// If Create itself raises, there is no instance to free.'#13#10 +
        ''#13#10 +
        '// Multiple objects: nest, or use ITP / managed records,'#13#10 +
        '// or wrap in a single try/finally with sequential Free.';
    end;

    fkDivByZero:
    begin
      Result.Description := 'Division by zero: EZeroDivide or EDivByZero possible';
      Result.Before :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  Result := Sum / Count;'#13#10 +
        '  // Count = 0 -> EZeroDivide'#13#10 +
        '  // Easy to hit on an empty list / filtered query.'#13#10 +
        'end;';
      Result.After :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  if Count = 0 then'#13#10 +
        '    Exit(0); // or raise a domain-specific exception'#13#10 +
        '  Result := Sum / Count;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// For floats, x / 0.0 yields Inf / NaN, not an exception,'#13#10 +
        '// unless FPU exceptions are enabled (Set8087CW).'#13#10 +
        '// Either way, validate the divisor before dividing.';
    end;

    fkDeadCode:
    begin
      Result.Description := 'Dead code: statements after Exit / raise are unreachable';
      Result.Before :=
        'if HasError then'#13#10 +
        'begin'#13#10 +
        '  raise Exception.Create(''failed'');'#13#10 +
        '  Cleanup;  // <- never executed'#13#10 +
        '  Logger.Info(''done''); // <- never executed'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Compiler warning W1011 "Return value might be undefined"'#13#10 +
        '// is closely related and worth enabling.';
      Result.After :=
        '// Option 1: reorder so cleanup runs before raise'#13#10 +
        'if HasError then'#13#10 +
        'begin'#13#10 +
        '  Cleanup;'#13#10 +
        '  raise Exception.Create(''failed'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: move cleanup into a finally block'#13#10 +
        '// so it runs whether or not we raise.'#13#10 +
        ''#13#10 +
        '// Option 3: just delete it, if the code'#13#10 +
        '// after Exit / raise is genuinely obsolete.';
    end;

    fkLongMethod:
    begin
      Result.Description := 'Method too long - splitting it improves readability and testability';
      Result.Before :=
        'procedure TOrderProcessor.ProcessOrder;'#13#10 +
        'begin'#13#10 +
        '  // 150+ lines:'#13#10 +
        '  //   - validate input'#13#10 +
        '  //   - load customer'#13#10 +
        '  //   - load price list'#13#10 +
        '  //   - apply discounts'#13#10 +
        '  //   - persist to db'#13#10 +
        '  //   - send confirmation mail'#13#10 +
        '  //   - update analytics'#13#10 +
        '  // Hard to follow, hard to unit-test in isolation.'#13#10 +
        'end;';
      Result.After :=
        'procedure TOrderProcessor.ProcessOrder;'#13#10 +
        'begin'#13#10 +
        '  if not Validate then Exit;'#13#10 +
        '  LoadContext;'#13#10 +
        '  CalculatePrice;'#13#10 +
        '  Persist;'#13#10 +
        '  Notify;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Each helper does one thing and can be tested alone.'#13#10 +
        '// Aim: a method body that fits on one screen and reads'#13#10 +
        '// like a table of contents.';
    end;

    fkLongParamList:
    begin
      Result.Description := 'Too many parameters - introduce a parameter object / record';
      Result.Before :=
        'procedure CreateUser('#13#10 +
        '  AName, AEmail, APhone,'#13#10 +
        '  AAddress, ACity, ACountry,'#13#10 +
        '  AZipCode: string;'#13#10 +
        '  AAge: Integer;'#13#10 +
        '  AActive: Boolean);'#13#10 +
        ''#13#10 +
        '// Caller has to remember the order of 9 arguments.'#13#10 +
        '// Easy to swap two strings of the same type'#13#10 +
        '// without the compiler noticing.';
      Result.After :=
        'type'#13#10 +
        '  TUserData = record'#13#10 +
        '    Name, Email, Phone : string;'#13#10 +
        '    Address, City      : string;'#13#10 +
        '    Country, ZipCode   : string;'#13#10 +
        '    Age                : Integer;'#13#10 +
        '    Active             : Boolean;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure CreateUser(const Data: TUserData);'#13#10 +
        ''#13#10 +
        '// Caller now writes Data.Name := ''...'' etc.,'#13#10 +
        '// reads better and tolerates new fields without'#13#10 +
        '// breaking every call site.';
    end;

    fkMagicNumber:
    begin
      Result.Description := 'Magic number - replace literal with a named constant';
      Result.Before :=
        'if RetryCount > 100 then'#13#10 +
        '  raise Exception.Create(''too many retries'');'#13#10 +
        ''#13#10 +
        'Sleep(86400);   // what is 86400?'#13#10 +
        'Buffer := 4096; // why 4096?'#13#10 +
        ''#13#10 +
        '// Reader has to guess what the number means'#13#10 +
        '// and where else the same value lives.';
      Result.After :=
        'const'#13#10 +
        '  MAX_RETRIES         = 100;'#13#10 +
        '  ONE_DAY_IN_SECONDS  = 24 * 60 * 60;'#13#10 +
        '  DEFAULT_BUFFER_SIZE = 4 * 1024; // 4 KB'#13#10 +
        ''#13#10 +
        'if RetryCount > MAX_RETRIES then'#13#10 +
        '  raise Exception.Create(''too many retries'');'#13#10 +
        ''#13#10 +
        'Sleep(ONE_DAY_IN_SECONDS);'#13#10 +
        'Buffer := DEFAULT_BUFFER_SIZE;'#13#10 +
        ''#13#10 +
        '// Self-documenting; one place to change.';
    end;

    fkDuplicateString:
    begin
      Result.Description := 'String literal repeated - extract to a constant or resourcestring';
      Result.Before :=
        'Logger.Warn(''Database connection lost'');'#13#10 +
        '// ... 30 lines later ...'#13#10 +
        'Logger.Error(''Database connection lost'');'#13#10 +
        '// ... in another unit ...'#13#10 +
        'StatusBar.SimpleText := ''Database connection lost'';'#13#10 +
        ''#13#10 +
        '// Three copies. Fix a typo in one, miss the others.'#13#10 +
        '// Translators have to translate the same text 3x.';
      Result.After :=
        '// For internal messages: const'#13#10 +
        'const'#13#10 +
        '  MSG_DB_LOST = ''Database connection lost'';'#13#10 +
        ''#13#10 +
        'Logger.Warn(MSG_DB_LOST);'#13#10 +
        'Logger.Error(MSG_DB_LOST);'#13#10 +
        'StatusBar.SimpleText := MSG_DB_LOST;'#13#10 +
        ''#13#10 +
        '// For user-visible text: resourcestring (or _() with'#13#10 +
        '// dxgettext) so the same string is translatable once.';
    end;

    fkDuplicateBlock:
    begin
      Result.Description := 'Multiple identical code blocks - extract a method (DRY)';
      Result.Before :=
        '// in TFoo.LoadCustomer:'#13#10 +
        'Conn.Open;'#13#10 +
        'Logger.Info(''Loading...'');'#13#10 +
        'Q.SQL.Text := ''SELECT * FROM customers'';'#13#10 +
        'Q.Open;'#13#10 +
        ''#13#10 +
        '// Same 4-line block in TFoo.LoadOrder, TFoo.LoadInvoice,'#13#10 +
        '// TFoo.LoadPayment, ... Five copies, one bugfix.'#13#10 +
        '// "Shotgun surgery": every change touches N call sites.';
      Result.After :=
        'procedure TFoo.RunQuery(const ASql: string);'#13#10 +
        'begin'#13#10 +
        '  Conn.Open;'#13#10 +
        '  Logger.Info(''Loading...'');'#13#10 +
        '  Q.SQL.Text := ASql;'#13#10 +
        '  Q.Open;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Callers shrink to one line:'#13#10 +
        'RunQuery(''SELECT * FROM customers'');'#13#10 +
        'RunQuery(''SELECT * FROM orders'');'#13#10 +
        ''#13#10 +
        '// Bonus: now there is exactly one place to add'#13#10 +
        '// timing, error handling, or instrumentation.';
    end;

    fkHardcodedPath:
    begin
      Result.Description := 'Hardcoded path - load it from configuration instead';
      Result.Before :=
        'LogFile := ''C:\Logs\app.log'';'#13#10 +
        'TempDir := ''C:\Temp\myapp\'';'#13#10 +
        'Share   := ''\\fileserver\reports\'';'#13#10 +
        ''#13#10 +
        '// Breaks on every other machine, every other OS,'#13#10 +
        '// and especially on locked-down user accounts'#13#10 +
        '// where C:\ is not writable.';
      Result.After :=
        '// Use the standard well-known folders:'#13#10 +
        'LogFile := IncludeTrailingPathDelimiter('#13#10 +
        '  TPath.GetDocumentsPath) + ''app.log'';'#13#10 +
        ''#13#10 +
        'TempDir := IncludeTrailingPathDelimiter('#13#10 +
        '  TPath.GetTempPath) + ''myapp\'';'#13#10 +
        ''#13#10 +
        '// Or read from configuration:'#13#10 +
        'Share := Ini.ReadString(''Paths'', ''Share'', '''');'#13#10 +
        ''#13#10 +
        '// Tip: TPath.Combine handles separators portably,'#13#10 +
        '// so the same code runs on Windows / Linux / macOS.';
    end;

    fkDebugOutput:
    begin
      Result.Description := 'Debug output left in production code';
      Result.Before :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  ShowMessage(''X = '' + IntToStr(X)); // forgotten?'#13#10 +
        '  WriteLn(''entered Bar'');             // -> nothing in GUI'#13#10 +
        '  OutputDebugString(''step 1'');        // dev-only'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// ShowMessage in production blocks the UI thread'#13#10 +
        '// and confuses end users. WriteLn in a GUI app'#13#10 +
        '// goes nowhere unless a console is attached.';
      Result.After :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  Logger.Debug(''X = %d'', [X]);'#13#10 +
        '  // or remove entirely if it was just a probe'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Better: a real logger with levels (debug / info /'#13#10 +
        '// warn / error) so verbose output can be turned off'#13#10 +
        '// in release builds via configuration.';
    end;

    fkDeepNesting:
    begin
      Result.Description := 'Nesting too deep - use early exit (guard clauses) or extract a method';
      Result.Before :=
        'if A then'#13#10 +
        '  if B then'#13#10 +
        '    if C then'#13#10 +
        '      if D then'#13#10 +
        '        if E then'#13#10 +
        '          DoIt;'#13#10 +
        ''#13#10 +
        '// Each level adds an "and what about the else?"'#13#10 +
        '// question. Reader loses the happy path completely.';
      Result.After :=
        '// Pattern: guard clauses - bail out early, then'#13#10 +
        '// the rest of the method runs at depth 0.'#13#10 +
        ''#13#10 +
        'if not A then Exit;'#13#10 +
        'if not B then Exit;'#13#10 +
        'if not C then Exit;'#13#10 +
        'if not D then Exit;'#13#10 +
        'if not E then Exit;'#13#10 +
        'DoIt;'#13#10 +
        ''#13#10 +
        '// Alternatively: combine the conditions'#13#10 +
        'if A and B and C and D and E then'#13#10 +
        '  DoIt;'#13#10 +
        ''#13#10 +
        '// If the body itself is large, extract it'#13#10 +
        '// into a method and call it once.';
    end;

    fkCyclomaticComplexity:
    begin
      Result.Description := 'Cyclomatic complexity too high - too many branches; extract methods or simplify conditions';
      Result.Before :=
        'function ProcessOrder(const O: TOrder): Boolean;'#13#10 +
        'begin'#13#10 +
        '  if (O.Status = osNew) and (O.Items.Count > 0)'#13#10 +
        '     and (O.Customer <> nil) and O.Customer.Active then'#13#10 +
        '  begin'#13#10 +
        '    case O.Type_ of'#13#10 +
        '      otStandard: ...;'#13#10 +
        '      otRush:     ...;'#13#10 +
        '      otBulk:     ...;'#13#10 +
        '      otGift:     ...;'#13#10 +
        '    end;'#13#10 +
        '    if O.Discount > 0 then ApplyDiscount(O);'#13#10 +
        '    if O.NeedsShipping then CalcShipping(O);'#13#10 +
        '    while O.PaymentRetries < 3 do TryPay(O);'#13#10 +
        '  end;'#13#10 +
        '  Result := True;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Cyclomatic ~ 12: viele Pfade, schwer zu testen.';
      Result.After :=
        '// Pattern: zerlege in kleinere Methoden mit klar'#13#10 +
        '// abgegrenzten Verantwortlichkeiten.'#13#10 +
        ''#13#10 +
        'function CanProcess(const O: TOrder): Boolean;'#13#10 +
        'begin'#13#10 +
        '  Result := (O.Status = osNew)'#13#10 +
        '        and (O.Items.Count > 0)'#13#10 +
        '        and (O.Customer <> nil)'#13#10 +
        '        and O.Customer.Active;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'function ProcessOrder(const O: TOrder): Boolean;'#13#10 +
        'begin'#13#10 +
        '  if not CanProcess(O) then Exit(False);'#13#10 +
        '  ProcessByType(O);'#13#10 +
        '  ApplyAdjustments(O);'#13#10 +
        '  Result := PayWithRetry(O);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// jede Sub-Methode hat CC ~3, viel besser testbar.'#13#10 +
        '// Threshold via [Detectors] CyclomaticMax in analyser.ini.';
    end;

    fkUnusedUses:
    begin
      Result.Description := 'Uses entry may be unused - remove to reduce coupling';
      Result.Before :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.IniFiles,   // <- no TIniFile / IniRead* used here'#13#10 +
        '  Vcl.Graphics,      // <- no TBitmap / TColor used here'#13#10 +
        '  System.Classes;'#13#10 +
        ''#13#10 +
        '// Each unused unit:'#13#10 +
        '//   - slows compilation (transitive deps loaded too)'#13#10 +
        '//   - hides the real dependencies of this unit'#13#10 +
        '//   - blocks reuse in trimmer projects';
      Result.After :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.Classes;'#13#10 +
        ''#13#10 +
        '// Tips:'#13#10 +
        '//   - turn on hint H2164 ("symbol is declared'#13#10 +
        '//     but never used") and H2169'#13#10 +
        '//   - the IDE refactoring "Find Unit" finds where'#13#10 +
        '//     a needed unit really lives'#13#10 +
        '//   - move VCL units (Vcl.*) to the implementation'#13#10 +
        '//     section if the interface section does not'#13#10 +
        '//     need them';
    end;

    fkTodoComment:
    begin
      Result.Description := 'Open marker (TODO / FIXME / HACK / XXX) - resolve before release';
      Result.Before :=
        '// TODO: persist this table'#13#10 +
        '// FIXME: race condition on parallel Save'#13#10 +
        '// HACK: workaround for vendor bug #4711'#13#10 +
        '// XXX: this is wrong but ships anyway'#13#10 +
        ''#13#10 +
        '// Markers tend to live for years. They make the'#13#10 +
        '// code look "in progress" without ever being'#13#10 +
        '// scheduled for actual work.';
      Result.After :=
        '// Option 1: just do the work and remove the marker.'#13#10 +
        ''#13#10 +
        '// Option 2: move it to the issue tracker and reference'#13#10 +
        '// the ticket from the code, with a date and an owner:'#13#10 +
        '// see JIRA-1234 (alice, 2026-05): retry on timeout'#13#10 +
        ''#13#10 +
        '// Option 3: delete the marker if it is obsolete'#13#10 +
        '// (the "fix" was done elsewhere and nobody noticed).'#13#10 +
        ''#13#10 +
        '// Tip: a CI step that fails on TODO/FIXME in changed'#13#10 +
        '// lines keeps the marker count from growing forever.';
    end;

    fkEmptyMethod:
    begin
      Result.Description := 'Method body is empty - forgotten stub or unintentional?';
      Result.Before :=
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Caller assumes something happens here -'#13#10 +
        '// nothing does. Looks like the implementation'#13#10 +
        '// was started, then left half-finished.';
      Result.After :=
        '// Option 1: implement it.'#13#10 +
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        '  FList.Sort;'#13#10 +
        '  Logger.Info(''sorted'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: if it is intentional (a hook for'#13#10 +
        '// subclasses), declare it virtual and add a comment'#13#10 +
        '// so the intent is explicit:'#13#10 +
        'procedure TFoo.OnAfterLoad; virtual;'#13#10 +
        '// Empty by design - subclasses override to react.'#13#10 +
        ''#13#10 +
        '// Option 3: if nothing should happen yet,'#13#10 +
        '// raise EAbstractError or ENotImplemented'#13#10 +
        '// so callers fail loudly instead of silently.';
    end;

  end;
end;

end.
