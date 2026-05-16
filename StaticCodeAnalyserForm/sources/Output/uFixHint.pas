unit uFixHint;

// Loesungs-Hinweise pro Befund-Typ.
//
// Liefert pro TLeakFinding eine kurze Beschreibung sowie zwei Code-Beispiele
// (Vorher / Nachher). Wird sowohl vom IDE-Hilfe-Panel als auch vom Export
// (Jira / Clipboard / HTML) verwendet, daher in eigener Unit.
//
// Sprache:
//   * Description ist mit _() lokalisiert (dxgettext) — wird im IDE-Hover-
//     Overlay und Hilfe-Panel in der UI-Sprache angezeigt.
//   * Before / After (Code-Beispiele) bleiben grundsaetzlich Englisch:
//     Code-Reviews, Jira-Tickets und Claude-AI-Prompts sind in der Praxis
//     englisch, eine Lokalisierung wuerde nur das Mischmasch zwischen
//     Quellcode-Beispielen und Erklaertext erhoehen.

interface

uses
  System.SysUtils,
  uSCAConsts, uMethodd12, uLocalization;

type
  TFixHint = record
    Description : string;   // Einzeilige Problembeschreibung (lokalisiert)
    Before      : string;   // Code-Beispiel "Vorher" (Englisch)
    After       : string;   // Code-Beispiel "Nachher" (Englisch)
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
        Result.Description := _('Object created but never freed (memory leak)');
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
        Result.Description := _('Function return value is not freed by the caller');
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
        Result.Description := _('Free is outside the protecting finally block');
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
      Result.Description := _('Empty except block silently swallows every exception');
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
      Result.Description := _('SQL command built with "+" - SQL injection risk');
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
      Result.Description := _('Password / token literal in source code');
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
      Result.Description := _('Format() placeholder count does not match argument count');
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
      Result.Description := _('File could not be read or parsed');
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
      Result.Description := _('Nil dereference: access through a possibly nil reference');
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
      Result.Description := _('Create without try/finally - exception path leaks the object');
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
      Result.Description := _('Division by zero: EZeroDivide or EDivByZero possible');
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
      Result.Description := _('Dead code: statements after Exit / raise are unreachable');
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
      Result.Description := _('Method too long - splitting it improves readability and testability');
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
      Result.Description := _('Too many parameters - introduce a parameter object / record');
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
      Result.Description := _('Magic number - replace literal with a named constant');
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
      Result.Description := _('String literal repeated - extract to a constant or resourcestring');
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
      Result.Description := _('Multiple identical code blocks - extract a method (DRY)');
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
      Result.Description := _('Hardcoded path - load it from configuration instead');
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
      Result.Description := _('Debug output left in production code');
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
      Result.Description := _('Nesting too deep - use early exit (guard clauses) or extract a method');
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
      Result.Description := _('Cyclomatic complexity too high - too many branches; extract methods or simplify conditions');
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
      Result.Description := _('Uses entry may be unused - remove to reduce coupling');
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
      Result.Description := _('Open marker (TODO / FIXME / HACK / XXX) - resolve before release');
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
      Result.Description := _('Method body is empty - forgotten stub or unintentional?');
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

    fkDfmOrphanHandler:
    begin
      Result.Description := _('Published method looks like an event handler but no component binds it');
      Result.Before :=
        '// uMainForm.pas'#13#10 +
        'type'#13#10 +
        '  TMainForm = class(TForm)'#13#10 +
        '    procedure btnOldFeatureClick(Sender: TObject);'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// The component btnOldFeature was removed from the .dfm but the'#13#10 +
        '// handler stayed - dead code that drags in dependencies and'#13#10 +
        '// confuses readers searching for callers.';
      Result.After :=
        '// Option 1: if the feature is really gone, delete the method.'#13#10 +
        '// Option 2: if a component should still call it, wire it up'#13#10 +
        '//           via the form designer (OnClick = btnOldFeatureClick)'#13#10 +
        '//           or assign at runtime in FormCreate.'#13#10 +
        ''#13#10 +
        '// Tip: methods that are intentional hooks (e.g. for descendant'#13#10 +
        '// classes) should be marked virtual and named clearly so they'#13#10 +
        '// do not pattern-match as Sender-handlers.';
    end;

    fkDfmEmptyBoundEvent:
    begin
      Result.Description := _('Component event is wired but the handler body is empty');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  OnClick = btnSaveClick'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.btnSaveClick(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// User clicks Save and... nothing happens. A bound handler with'#13#10 +
        '// an empty body is almost always a forgotten implementation.';
      Result.After :=
        '// Option 1: implement the action.'#13#10 +
        'procedure TMainForm.btnSaveClick(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  SaveDocument(FActiveFile);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: if the click should genuinely do nothing today,'#13#10 +
        '//           remove the OnClick line from the .dfm so the form'#13#10 +
        '//           does not pretend to be interactive.';
    end;

    fkDfmSchemaMismatch:
    begin
      Result.Description := _('DFM declares a component but the form class has no published field for it');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object MainForm: TMainForm'#13#10 +
        '  object btnLegacy: TButton'#13#10 +
        '    Caption = ''Old'''#13#10 +
        '  end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas - btnLegacy was removed from the class decl'#13#10 +
        'type'#13#10 +
        '  TMainForm = class(TForm)'#13#10 +
        '    // btnLegacy: TButton;  <- deleted'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Streamer creates the button at form-load but it has no Pascal'#13#10 +
        '// reference. Memory is owned by the form, but the code cannot'#13#10 +
        '// see or modify the button. Usually a half-finished cleanup.';
      Result.After :=
        '// Pick a side based on intent:'#13#10 +
        '//   * if btnLegacy is no longer needed -> delete it from the .dfm'#13#10 +
        '//   * if you still need it -> restore the field in the class decl'#13#10 +
        ''#13#10 +
        '// Use the IDE form designer to make changes - it keeps .dfm and'#13#10 +
        '// .pas in sync automatically.';
    end;

    fkDfmDeadEvent:
    begin
      Result.Description := _('Event handler in DFM points to a method that no longer exists');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  OnClick = btnSaveClick'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas - method was renamed to SaveClick'#13#10 +
        'type'#13#10 +
        '  TMainForm = class(TForm)'#13#10 +
        '    procedure SaveClick(Sender: TObject);'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// DFM still references btnSaveClick - streaming crashes at'#13#10 +
        '// form-create with "is not a method" - and the compiler never'#13#10 +
        '// saw the mismatch.';
      Result.After :=
        '// Pick one side as the source of truth.'#13#10 +
        '// Option 1: keep the new method name, fix the DFM.'#13#10 +
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  OnClick = SaveClick'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Option 2: keep the old DFM reference, restore the method.'#13#10 +
        'procedure TMainForm.btnSaveClick(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  Save;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Tip: rename through the IDE refactor (F2) -> both .dfm and'#13#10 +
        '// .pas get updated atomically.';
    end;

    fkDfmHardcodedDbCreds:
    begin
      Result.Description := _('Database credentials sit in the form file - move them out');
      Result.Before :=
        '// uDataModule.dfm'#13#10 +
        'object dmMain: TDataModule'#13#10 +
        '  object Conn: TADOConnection'#13#10 +
        '    ConnectionString = '#13#10 +
        '      ''Provider=SQLOLEDB.1;User ID=admin;Password=s3cret;Data Source=db1'''#13#10 +
        '    LoginPrompt = False'#13#10 +
        '    Connected = True'#13#10 +
        '  end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// The password is in the .dfm -> in version control,'#13#10 +
        '// in the compiled binary, visible to anyone with read access.';
      Result.After :=
        '// uDataModule.dfm: keep the property empty in the form file.'#13#10 +
        'object Conn: TADOConnection'#13#10 +
        '  LoginPrompt = False'#13#10 +
        '  Connected = False'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uDataModule.pas: build the string at runtime from a secret store.'#13#10 +
        'procedure TdmMain.DataModuleCreate(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  Conn.ConnectionString := BuildConnectionString('#13#10 +
        '    GetSecret(''db.user''), GetSecret(''db.password''));'#13#10 +
        '  Conn.Connected := True;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Sources for secrets (in increasing order of safety):'#13#10 +
        '//   .env / config file outside the repo'#13#10 +
        '//   OS keyring / Windows Credential Manager'#13#10 +
        '//   HashiCorp Vault / Azure Key Vault / AWS Secrets Manager';
    end;

    fkDfmLayerViolation:
    begin
      Result.Description := _('Input control sits directly on the form - wrap it in a panel');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object frmOrder: TOrderForm'#13#10 +
        '  object edName  : TEdit ... end'#13#10 +
        '  object edEmail : TEdit ... end'#13#10 +
        '  object btnSave : TButton ... end'#13#10 +
        '  object btnCancel : TButton ... end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Flat layout - hard to reorganize, hard to reuse,'#13#10 +
        '// align/anchors become awkward as the form grows.';
      Result.After :=
        'object frmOrder: TOrderForm'#13#10 +
        '  object pnlInputs: TPanel'#13#10 +
        '    object edName: TEdit ... end'#13#10 +
        '    object edEmail: TEdit ... end'#13#10 +
        '  end'#13#10 +
        '  object pnlButtons: TPanel'#13#10 +
        '    object btnSave   : TButton ... end'#13#10 +
        '    object btnCancel : TButton ... end'#13#10 +
        '  end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Grouping by purpose makes Align/Anchor straightforward'#13#10 +
        '// and lets you swap whole sections without re-layouting all'#13#10 +
        '// children individually.';
    end;

    fkDfmGodHandler:
    begin
      Result.Description := _('A single method handles too many component events - split it up');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave   : TButton OnClick = MainClick end'#13#10 +
        'object btnLoad   : TButton OnClick = MainClick end'#13#10 +
        'object btnDelete : TButton OnClick = MainClick end'#13#10 +
        'object btnExport : TButton OnClick = MainClick end'#13#10 +
        'object btnImport : TButton OnClick = MainClick end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.MainClick(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  if Sender = btnSave   then ...'#13#10 +
        '  else if Sender = btnLoad   then ...'#13#10 +
        '  else if Sender = btnDelete then ...'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// One method that dispatches on Sender is a manual switch'#13#10 +
        '// statement that grows linearly with every new button.';
      Result.After :=
        '// Give each button its own handler.'#13#10 +
        'procedure TMainForm.btnSaveClick  (Sender: TObject); begin ... end;'#13#10 +
        'procedure TMainForm.btnLoadClick  (Sender: TObject); begin ... end;'#13#10 +
        'procedure TMainForm.btnDeleteClick(Sender: TObject); begin ... end;'#13#10 +
        ''#13#10 +
        '// Refactor toward TAction: the Action describes WHAT happens'#13#10 +
        '// (caption, hint, enabled state), the button just triggers it.'#13#10 +
        '// IDE: drop a TActionList, define actions, assign Button.Action.';
    end;

    fkDfmActionMismatch:
    begin
      Result.Description := _('Component has both Action and OnClick - the OnClick handler is dead code');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  Action  = ActSave'#13#10 +
        '  OnClick = btnSaveClick      // <- never called'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// When Action is set, the VCL routes the click through'#13#10 +
        '// ActSave.OnExecute. btnSaveClick stays in the code but'#13#10 +
        '// is never reached - silently rotting dead code.';
      Result.After :=
        '// Pick exactly one driver:'#13#10 +
        ''#13#10 +
        '// Option 1: keep the Action, drop OnClick (and the orphan method).'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  Action = ActSave'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Option 2: keep OnClick, drop the Action.'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  OnClick = btnSaveClick'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Tip: Actions are usually the right answer because they'#13#10 +
        '// centralize enabled/caption/hint state across multiple'#13#10 +
        '// triggers (button + menu + shortcut).';
    end;

    fkDfmCrossFormCoupling:
    begin
      Result.Description := _('Code reaches into another form''s published fields - tight coupling');
      Result.Before :=
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.SyncOrder;'#13#10 +
        'begin'#13#10 +
        '  Form2.edTotal.Text := FormatFloat(''0.00'', FTotal);'#13#10 +
        '  Form2.qOrder.Refresh;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// edTotal/qOrder are published on Form2 only so the DFM streamer'#13#10 +
        '// can find them. Form1 reaching across breaks that encapsulation:'#13#10 +
        '// a rename inside Form2 silently breaks Form1, and Form2 cannot'#13#10 +
        '// reorganize its UI without breaking remote callers.';
      Result.After :=
        '// Option 1: give Form2 a public API for the operation.'#13#10 +
        '// uForm2.pas'#13#10 +
        'public'#13#10 +
        '  procedure SetTotal(const AValue: Currency);'#13#10 +
        '  procedure RefreshOrder;'#13#10 +
        ''#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.SyncOrder;'#13#10 +
        'begin'#13#10 +
        '  Form2.SetTotal(FTotal);'#13#10 +
        '  Form2.RefreshOrder;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: lift the dataset out of Form2 into a DataModule so'#13#10 +
        '//           both forms share it without form-to-form references.';
    end;

    fkDfmTabOrderConflict:
    begin
      Result.Description := _('Two sibling controls share the same TabOrder - tab navigation is undefined');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object pnlInput: TPanel'#13#10 +
        '  object edName: TEdit'#13#10 +
        '    TabOrder = 0'#13#10 +
        '  end'#13#10 +
        '  object edEmail: TEdit'#13#10 +
        '    TabOrder = 0          // <- same!'#13#10 +
        '  end'#13#10 +
        '  object edPhone: TEdit'#13#10 +
        '    TabOrder = 1'#13#10 +
        '  end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Tab from Name goes to ... maybe Email, maybe Phone. The VCL'#13#10 +
        '// uses creation order as tie-breaker, which is unstable across'#13#10 +
        '// designer edits.';
      Result.After :=
        '// Renumber so every sibling has a unique TabOrder.'#13#10 +
        'object edName  : TEdit TabOrder = 0 end'#13#10 +
        'object edEmail : TEdit TabOrder = 1 end'#13#10 +
        'object edPhone : TEdit TabOrder = 2 end'#13#10 +
        ''#13#10 +
        '// IDE designer can do this for you: select the controls,'#13#10 +
        '// right-click -> Tab Order, drag into the desired sequence.';
    end;

    fkDfmForbiddenClass:
    begin
      Result.Description := _('Component class is on the project-defined forbidden list');
      Result.Before :=
        '// analyser.ini'#13#10 +
        '[Components]'#13#10 +
        'ForbiddenClasses=TLabel,TQuery'#13#10 +
        ''#13#10 +
        '// uMainForm.dfm'#13#10 +
        'object lblTitle: TLabel'#13#10 +
        '  Caption = ''Hello'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Project policy says use TcxLabel for themed labels;'#13#10 +
        '// plain TLabel is reserved for legacy forms only.';
      Result.After :=
        '// Switch to the approved replacement.'#13#10 +
        'object lblTitle: TcxLabel'#13#10 +
        '  Caption = ''Hello'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// If the rule was added too late and you need to keep this'#13#10 +
        '// occurrence, suppress it via the project ignore file rather'#13#10 +
        '// than weakening the rule for everyone.';
    end;

    fkDfmDbInUiForm:
    begin
      Result.Description := _('Database component sits on a Form/Frame - move to a TDataModule');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object frmOrder: TOrderForm'#13#10 +
        '  object conn: TADOConnection ... end'#13#10 +
        '  object qOrders: TADOQuery ... end'#13#10 +
        '  object pnlList: TPanel ... end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Closing the form takes down the database connection.'#13#10 +
        '// Two forms accessing the same data each open their own'#13#10 +
        '// connection -> no pool, slow startup, two transactions.';
      Result.After :=
        '// uOrderDM.dfm'#13#10 +
        'object dmOrder: TOrderDataModule'#13#10 +
        '  object conn: TADOConnection ... end'#13#10 +
        '  object qOrders: TADOQuery ... end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uOrderForm.dfm - keep only UI components.'#13#10 +
        'object frmOrder: TOrderForm'#13#10 +
        '  object pnlList: TPanel ... end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// In code: Order.qOrders.SQL.Text := ''SELECT ...'';'#13#10 +
        '// The DataModule lives for the whole app, connections are'#13#10 +
        '// shared, forms become testable without a DB at compile time.';
    end;

    fkDfmRequiredFieldUnbound:
    begin
      Result.Description := _('Required dataset field has no DB-control binding it');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object qOrder: TADOQuery'#13#10 +
        '  object qOrderTotal: TFloatField'#13#10 +
        '    FieldName = ''Total'''#13#10 +
        '    Required = True'#13#10 +
        '  end'#13#10 +
        'end'#13#10 +
        'object dsOrder: TDataSource DataSet = qOrder end'#13#10 +
        '// no TDBEdit ever references dsOrder + Total'#13#10 +
        ''#13#10 +
        '// The user has no way to enter Total - Post raises'#13#10 +
        '// EDatabaseError (Field "Total" must have a value).';
      Result.After :=
        '// Bind a control to the field via the form designer:'#13#10 +
        'object edTotal: TDBEdit'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''Total'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Or, if the field is meant to be filled in code,'#13#10 +
        '// remove Required=True so the dataset accepts NULL'#13#10 +
        '// (and document why the field is invisible-by-design).';
    end;

    fkDfmRequiredFieldNotVisible:
    begin
      Result.Description := _('Required field is bound only to invisible controls');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object qOrderTotal: TFloatField'#13#10 +
        '  FieldName = ''Total'''#13#10 +
        '  Required = True'#13#10 +
        'end'#13#10 +
        'object edTotal: TDBEdit'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''Total'''#13#10 +
        '  Visible = False             // <- only binding, hidden'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// User cannot see or fill the field, but Post enforces it.'#13#10 +
        '// Usually a leftover from a layout refactor.';
      Result.After :=
        '// Pick one:'#13#10 +
        '//   * Show the control (Visible = True)'#13#10 +
        '//   * Set the value in code (FormCreate, AfterInsert, ...)'#13#10 +
        '//   * Drop Required=True if NULL is genuinely OK'#13#10 +
        ''#13#10 +
        '// Tip: Phase 1 only checks Visible on the control itself;'#13#10 +
        '// a control on a hidden TTabSheet/TPanel is NOT yet flagged.';
    end;

    fkDfmFieldTypeMismatch:
    begin
      Result.Description := _('DB-control class does not fit the field data type');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object qOrderIsPaid: TBooleanField'#13#10 +
        '  FieldName = ''IsPaid'''#13#10 +
        'end'#13#10 +
        'object edIsPaid: TDBEdit'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''IsPaid'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// TDBEdit on a boolean field shows "True" / "False" as text -'#13#10 +
        '// users type random strings, Post crashes.';
      Result.After :=
        'object cbIsPaid: TDBCheckBox'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''IsPaid'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Rule of thumb:'#13#10 +
        '//   Boolean      -> TDBCheckBox'#13#10 +
        '//   Memo / Blob  -> TDBMemo / TDBRichEdit / TDBImage'#13#10 +
        '//   Date / Time  -> TDBDateTimePicker';
    end;

    fkDfmSqlFromUserInput:
    begin
      Result.Description := _('SQL query is built from a UI input field - parameterize instead of concatenating');
      Result.Before :=
        '// uSearch.pas'#13#10 +
        'procedure TSearchForm.btnFindClick(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  qFind.SQL.Text :='#13#10 +
        '    ''SELECT * FROM users WHERE name='''''' +'#13#10 +
        '    edName.Text + '''''''';'#13#10 +
        '  qFind.Open;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// edName.Text comes straight from the user. Any quote, semicolon'#13#10 +
        '// or DROP statement entered into the edit will be executed as SQL.'#13#10 +
        '// This is the textbook SQL-injection setup.';
      Result.After :=
        '// Parameterize the query - placeholders are escaped by the driver.'#13#10 +
        'qFind.SQL.Text := ''SELECT * FROM users WHERE name = :n'';'#13#10 +
        'qFind.Parameters.ParamByName(''n'').Value := edName.Text;'#13#10 +
        '// (FireDAC: qFind.Params.ParamByName(''n'').AsString := edName.Text;)'#13#10 +
        'qFind.Open;'#13#10 +
        ''#13#10 +
        '// Rule of thumb: every value that depends on user input becomes a'#13#10 +
        '// parameter. Static literals (column names, ORDER BY direction)'#13#10 +
        '// stay inline - but never concatenate user-controlled text.';
    end;

    fkDfmCircularDataSource:
    begin
      Result.Description := _('Master-detail wiring forms a cycle - opening the dataset will loop endlessly');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object dsOrder: TDataSource'#13#10 +
        '  DataSet = qOrder'#13#10 +
        'end'#13#10 +
        'object qOrder: TADOQuery'#13#10 +
        '  MasterSource = dsOrder      // points right back -> cycle'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// On qOrder.Open, the master-detail refresh re-evaluates'#13#10 +
        '// dsOrder, which re-evaluates qOrder, ... UI hangs at startup,'#13#10 +
        '// usually with no exception (just a frozen window).';
      Result.After :=
        '// MasterSource is meant for SUB-dataset binding only:'#13#10 +
        '//   qDetail.MasterSource = dsMaster'#13#10 +
        '// The "master" side is a different dataset than the dataset'#13#10 +
        '// that the DataSource points at.'#13#10 +
        ''#13#10 +
        '// Fix: clear MasterSource on the self-referencing dataset, or'#13#10 +
        '//      wire it to a different (parent) dataset.'#13#10 +
        'object qOrder: TADOQuery'#13#10 +
        '  // MasterSource removed - qOrder is the master.'#13#10 +
        'end';
    end;

    fkDfmDuplicateBinding:
    begin
      Result.Description := _('Multiple components bind the same DataSource and DataField');
      Result.Before :=
        '// uOrderForm.dfm'#13#10 +
        'object dsOrder: TDataSource end'#13#10 +
        'object edTotal: TDBEdit'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''Total'''#13#10 +
        'end'#13#10 +
        'object edTotalCopy: TDBEdit'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''Total'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Two editors writing to the same dataset field.'#13#10 +
        '// Last writer wins on Post; values can diverge on screen.';
      Result.After :=
        '// Option 1: drop one of the duplicates (most common cause is'#13#10 +
        '//           a copy-pasted editor that was never finished).'#13#10 +
        ''#13#10 +
        '// Option 2: if both views are needed, make one read-only.'#13#10 +
        'object edTotalDisplay: TDBText'#13#10 +
        '  DataSource = dsOrder'#13#10 +
        '  DataField = ''Total'''#13#10 +
        'end'#13#10 +
        '// TDBText is read-only and cannot cause an update conflict.';
    end;

    fkDfmHardcodedCaption:
    begin
      Result.Description := _('UI text in DFM is a literal string - route it through the localization layer');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  Caption = ''Save'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// The text "Save" sits in the form file. dxgettext / gnugettext'#13#10 +
        '// will not pick it up - the button stays English in every language.';
      Result.After :=
        '// Option 1: leave the .dfm empty and assign at runtime via _()'#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.FormCreate(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  btnSave.Caption := _(''Save'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: keep DFM caption but translate it on form create'#13#10 +
        'procedure TMainForm.FormCreate(Sender: TObject);'#13#10 +
        'begin'#13#10 +
        '  TranslateComponent(Self);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Tip: covers Caption, Hint, Text (and Lines/Items where used).'#13#10 +
        '// Empty captions in the DFM are not flagged.';
    end;

    fkDfmDefaultName:
    begin
      Result.Description := _('Component uses the IDE default name - rename for clarity');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object Button1: TButton'#13#10 +
        '  Caption = ''Save'''#13#10 +
        '  OnClick = Button1Click'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.Button1Click(Sender: TObject);'#13#10 +
        '// Reader has no clue what Button1 does without scrolling'#13#10 +
        '// to the form. Refactoring "rename Button1 -> btnSave"'#13#10 +
        '// touches both .dfm and .pas - easy to miss one side.';
      Result.After :=
        '// uMainForm.dfm'#13#10 +
        'object btnSave: TButton'#13#10 +
        '  Caption = ''Save'''#13#10 +
        '  OnClick = btnSaveClick'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.pas'#13#10 +
        'procedure TMainForm.btnSaveClick(Sender: TObject);'#13#10 +
        ''#13#10 +
        '// Common prefixes by component class:'#13#10 +
        '//   btn, edt, lbl, pnl, mem, cbo, lst, grd, tab, img';
    end;

    fkCustomRule:
    begin
      Result.Description := _('Custom rule defined in analyser-rules.yml matched this code');
      Result.Before :=
        '// Triggered when a regex/AST rule from analyser-rules.yml hit.'#13#10 +
        '// The MissingVar field of the finding shows the rule ID + matched text.'#13#10 +
        ''#13#10 +
        '// Example custom rule (analyser-rules.yml):'#13#10 +
        '//   id: BAN-WRITELN'#13#10 +
        '//   pattern: WriteLn'#13#10 +
        '//   severity: warning'#13#10 +
        '//   message: WriteLn forbidden in production code';
      Result.After :=
        '// Either:'#13#10 +
        '//   * Adjust the code to satisfy the rule, or'#13#10 +
        '//   * If the rule is wrong, edit analyser-rules.yml, or'#13#10 +
        '//   * Suppress this one finding with:  // noinspection CustomRule';
    end;

    fkConcatToFormat:
    begin
      Result.Description := _('Long string concatenation - prefer Format() for readability');
      Result.Before :=
        '// Long concat chain - hard to read, easy to miss a separator'#13#10 +
        'Msg := ''Hallo '' + Name + '', du bist '' + IntToStr(Age) +'#13#10 +
        '       '' Jahre alt und wohnst in '' + City + ''.'''#13#10 +
        '// More than two ''+'' with mixed literals + variables ->'#13#10 +
        '// Format() is usually clearer.';
      Result.After :=
        'Msg := Format(''Hallo %s, du bist %d Jahre alt und wohnst in %s.'','#13#10 +
        '              [Name, Age, City]);'#13#10 +
        '// Benefits:'#13#10 +
        '//   * Format-string and arguments are visually separated'#13#10 +
        '//   * Translation-friendly (one string, no concat splits)'#13#10 +
        '//   * IntToStr no longer needed - %d does the conversion';
    end;

    fkWithStatement:
    begin
      Result.Description := _('with statement can silently rebind identifiers - avoid it');
      Result.Before :=
        'with FCustomer do'#13#10 +
        'begin'#13#10 +
        '  Name := ''Mueller'';'#13#10 +
        '  Age  := 42;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Problem: if a future refactoring adds a "Name" field to the'#13#10 +
        '// surrounding class, the assignment silently changes target.'#13#10 +
        '// Compiler emits no warning - subtle, hard-to-diagnose bug.';
      Result.After :=
        '// Option A: explicit variable'#13#10 +
        'C := FCustomer;'#13#10 +
        'C.Name := ''Mueller'';'#13#10 +
        'C.Age  := 42;'#13#10 +
        ''#13#10 +
        '// Option B: explicit qualifier'#13#10 +
        'FCustomer.Name := ''Mueller'';'#13#10 +
        'FCustomer.Age  := 42;';
    end;

    fkReversedForRange:
    begin
      Result.Description := _('for-loop range is reversed - the loop body never runs');
      Result.Before :=
        'for i := 10 to 1 do'#13#10 +
        '  ProcessItem(i);'#13#10 +
        ''#13#10 +
        '// From > To in a forward "to" loop: zero iterations.'#13#10 +
        '// Typical bug: meant "downto" but wrote "to".';
      Result.After :=
        'for i := 10 downto 1 do'#13#10 +
        '  ProcessItem(i);'#13#10 +
        ''#13#10 +
        '// Or if forward iteration was intended:'#13#10 +
        'for i := 1 to 10 do'#13#10 +
        '  ProcessItem(i);';
    end;

    fkSelfAssignment:
    begin
      Result.Description := _('Self-assignment is a no-op - usually a copy-paste mistake');
      Result.Before :=
        'procedure TFoo.Init(const Source: TFoo);'#13#10 +
        'begin'#13#10 +
        '  FName := FName;        // <-- meant Source.FName?'#13#10 +
        '  FAge  := Source.FAge;'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.Init(const Source: TFoo);'#13#10 +
        'begin'#13#10 +
        '  FName := Source.FName;'#13#10 +
        '  FAge  := Source.FAge;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Rare exception: property setter with side effects'#13#10 +
        '//   Visible := Visible;   // forces repaint in legacy VCL code'#13#10 +
        '// Suppress with:  // noinspection SelfAssignment';
    end;

    fkVirtualCallInCtor:
    begin
      Result.Description := _('Virtual method called from constructor - override sees half-initialized Self');
      Result.Before :=
        'type'#13#10 +
        '  TBase = class'#13#10 +
        '    constructor Create;'#13#10 +
        '    procedure Init; virtual;'#13#10 +
        '  end;'#13#10 +
        '  TDerived = class(TBase)'#13#10 +
        '    FCache: TList;'#13#10 +
        '    procedure Init; override;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'constructor TBase.Create;'#13#10 +
        'begin'#13#10 +
        '  Init;       // <-- calls TDerived.Init, FCache is still nil!'#13#10 +
        'end;';
      Result.After :=
        '// Option A: defer initialization to a separate method the caller invokes'#13#10 +
        'constructor TBase.Create;'#13#10 +
        'begin'#13#10 +
        '  // no virtual calls here'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'procedure TBase.AfterConstruction;'#13#10 +
        'begin'#13#10 +
        '  inherited;'#13#10 +
        '  Init;       // safe: Self is fully constructed now'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option B: make Init non-virtual + call a virtual ConfigureDefaults inside';
    end;

    fkLengthUnderflow:
    begin
      Result.Description := _('Length()/.Count minus a constant can underflow on empty input');
      Result.Before :=
        'k := Length(s) - 4;'#13#10 +
        'Move(s[1], buf, k);'#13#10 +
        ''#13#10 +
        '// When Length(s) < 4, k becomes negative (or huge as NativeUInt).'#13#10 +
        '// Move with bogus count -> AV / data corruption.';
      Result.After :=
        'if Length(s) >= 4 then'#13#10 +
        'begin'#13#10 +
        '  k := Length(s) - 4;'#13#10 +
        '  Move(s[1], buf, k);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// The classic idiom "for i := 0 to Length(s) - 1" is fine:'#13#10 +
        '// -1 produces an empty range (0 iterations) for empty strings.';
    end;

    fkCanBePrivate:
    begin
      Result.Description := _('Public member is used only inside its declaring class - tighten visibility');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Helper;'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure TFoo.Helper; begin ... end;'#13#10 +
        'procedure TFoo.Run; begin Helper; end;'#13#10 +
        '// Helper is only called from Run - public is too lax.';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    procedure Helper;'#13#10 +
        '  public'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Encapsulation tightened: Helper is now an implementation detail.';
    end;

    fkCanBeProtected:
    begin
      Result.Description := _('Public member is used only by subclasses - protected is tighter');
      Result.Before :=
        'type'#13#10 +
        '  TBase = class'#13#10 +
        '  public'#13#10 +
        '    procedure Hook;'#13#10 +
        '  end;'#13#10 +
        '  TSub = class(TBase)'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure TSub.Run; begin Hook; end;'#13#10 +
        '// Hook is only called from subclasses - protected is enough.';
      Result.After :=
        'type'#13#10 +
        '  TBase = class'#13#10 +
        '  protected'#13#10 +
        '    procedure Hook;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Hook stays accessible from TSub + future subclasses,'#13#10 +
        '// but is now hidden from unrelated callers.';
    end;

    fkUnusedLocalVar:
    begin
      Result.Description := _('Local variable declared but never read or written');
      Result.Before :=
        'procedure TFoo.Run;'#13#10 +
        'var'#13#10 +
        '  result: Integer;       // <-- never used'#13#10 +
        '  count: Integer;'#13#10 +
        'begin'#13#10 +
        '  count := Length(FList);'#13#10 +
        '  DoStuff(count);'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.Run;'#13#10 +
        'var'#13#10 +
        '  count: Integer;'#13#10 +
        'begin'#13#10 +
        '  count := Length(FList);'#13#10 +
        '  DoStuff(count);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// If the var name starts with _ (e.g., _ignored), the detector skips'#13#10 +
        '// it - convention for "intentionally unused".';
    end;

    fkUnusedParameter:
    begin
      Result.Description := _('Parameter never read in method body');
      Result.Before :=
        'procedure TFoo.Process(const Data: TBytes; LogLevel: Integer);'#13#10 +
        'begin'#13#10 +
        '  HandleBytes(Data);     // LogLevel is never used'#13#10 +
        'end;';
      Result.After :=
        '// Option A: drop the parameter entirely (changes signature)'#13#10 +
        'procedure TFoo.Process(const Data: TBytes);'#13#10 +
        'begin'#13#10 +
        '  HandleBytes(Data);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option B: signature must match a virtual / interface contract -'#13#10 +
        '// rename to leading-underscore so the detector skips it:'#13#10 +
        '//   procedure TFoo.Process(const Data: TBytes; _LogLevel: Integer);'#13#10 +
        ''#13#10 +
        '// Event handlers (single Sender: TObject param) are auto-skipped.';
    end;

    fkSqlDangerousStatement:
    begin
      Result.Description := _('UPDATE/DELETE/TRUNCATE without WHERE - affects ALL rows');
      Result.Before :=
        'qry.SQL.Text := ''UPDATE customers SET locked=1'';'#13#10 +
        'qry.ExecSQL;'#13#10 +
        ''#13#10 +
        '// Folge: JEDER Kunde wird gesperrt - kein Filter.'#13#10 +
        '// Production-Disaster: nicht mehr rueckgaengig zu machen,'#13#10 +
        '// ausser via DB-Backup.';
      Result.After :=
        'qry.SQL.Text := ''UPDATE customers SET locked=1 WHERE id=:id'';'#13#10 +
        'qry.Params.ParamByName(''id'').AsInteger := UserId;'#13#10 +
        'qry.ExecSQL;'#13#10 +
        ''#13#10 +
        '// Tipp: in Migrations-Skripten WHERE 1=1 explizit annotieren,'#13#10 +
        '//       wenn JEDE Zeile gewollt ist (Audit-Trail).';
    end;

    fkFormatLocaleHint:
    begin
      Result.Description := _('Float format spec without TFormatSettings - locale-dependent decimal separator');
      Result.Before :=
        'Result := Format(''Price: %.2f EUR'', [Amount]);'#13#10 +
        ''#13#10 +
        '// Default-Locale entscheidet ueber Komma vs. Punkt:'#13#10 +
        '//   DE: ''Price: 19,99 EUR'''#13#10 +
        '//   EN: ''Price: 19.99 EUR'''#13#10 +
        '// Beim Einlesen via JSON / API-Call -> Parser-Fehler.';
      Result.After :=
        '// Option A: invariant culture (immer Punkt)'#13#10 +
        'Result := Format(''Price: %.2f EUR'', [Amount],'#13#10 +
        '                 TFormatSettings.Invariant);'#13#10 +
        ''#13#10 +
        '// Option B: explizit deutsche Lokalisierung (immer Komma)'#13#10 +
        'var FS := TFormatSettings.Create(''de-DE'');'#13#10 +
        'Result := Format(''Price: %.2f EUR'', [Amount], FS);'#13#10 +
        ''#13#10 +
        '// Faustregel: wenn der Output JEMALS an eine API oder ein'#13#10 +
        '// File geht, IMMER mit TFormatSettings.Invariant.';
    end;

    fkDfmMasterDetailUnlinked:
    begin
      Result.Description := _('MasterSource set without MasterFields/IndexFieldNames - silent cross-join');
      Result.Before :=
        'object qOrders: TFDQuery'#13#10 +
        '  MasterSource = dsCustomers'#13#10 +
        '  // MasterFields fehlt!'#13#10 +
        '  // IndexFieldNames fehlt!'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Folge: bei jedem Master-Recordwechsel feuert ein'#13#10 +
        '// "open Detail without join" -> Cartesian-Cross-Join,'#13#10 +
        '// Detail-Grid haengt unsichtbar bei realer Datenmenge.';
      Result.After :=
        'object qOrders: TFDQuery'#13#10 +
        '  MasterSource = dsCustomers'#13#10 +
        '  MasterFields = ''CustomerID'''#13#10 +
        '  // oder alternativ:'#13#10 +
        '  // IndexFieldNames = ''CustomerID'''#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Tipp: bei mehreren Feldern Semikolon als Trenner:'#13#10 +
        '//   MasterFields = ''CustomerID;Region''';
    end;

    fkDfmDataModuleSplitHint:
    begin
      Result.Description := _('Many DB components on one form - extract into a TDataModule');
      Result.Before :=
        '// uMainForm.dfm'#13#10 +
        'object MainForm: TMainForm'#13#10 +
        '  object Conn: TADOConnection end'#13#10 +
        '  object qCustomers: TADOQuery end'#13#10 +
        '  object qOrders: TADOQuery end'#13#10 +
        '  object dsCustomers: TDataSource end'#13#10 +
        '  object dsOrders: TDataSource end'#13#10 +
        '  // ... weitere DB-Komponenten ...'#13#10 +
        '  object Edit1: TEdit end'#13#10 +
        '  object Button1: TButton end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Probleme: Connection bindet an Form-Lifecycle, kein'#13#10 +
        '// Sharing zwischen Forms, Test-Setup erfordert UI.';
      Result.After :=
        '// uDataMod.dfm (neu)'#13#10 +
        'object DataMod: TDataModule'#13#10 +
        '  object Conn: TADOConnection end'#13#10 +
        '  object qCustomers: TADOQuery end'#13#10 +
        '  object qOrders: TADOQuery end'#13#10 +
        '  object dsCustomers: TDataSource end'#13#10 +
        '  object dsOrders: TDataSource end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// uMainForm.dfm (jetzt schlank)'#13#10 +
        'object MainForm: TMainForm'#13#10 +
        '  object Edit1: TEdit end'#13#10 +
        '  object Button1: TButton end'#13#10 +
        'end'#13#10 +
        ''#13#10 +
        '// Tipp: Singleton-Zugriff via global DataMod-Var (uDataMod.pas),'#13#10 +
        '// damit alle Forms denselben Connection-Pool teilen.';
    end;

    fkTautologicalBoolExpr:
    begin
      Result.Description := _('Binary expression has identical left and right side - copy-paste bug?');
      Result.Before :=
        'if (UserId = UserId) then'#13#10 +
        '  AllowAccess := True;'#13#10 +
        ''#13#10 +
        '// Probably meant: UserId = SessionUserId, or'#13#10 +
        '//                arr[i] = arr[j], with j accidentally typed as i.';
      Result.After :=
        'if (UserId = SessionUserId) then'#13#10 +
        '  AllowAccess := True;'#13#10 +
        ''#13#10 +
        '// The detector catches: =, <>, <, >, <=, >=, and, or, xor with'#13#10 +
        '// identical left and right (whitespace + case ignored).'#13#10 +
        '// Mathematical operators (+, -, *) are intentionally NOT flagged'#13#10 +
        '//   - x + x and a * a are legitimate idioms.';
    end;

    fkUnusedPublicMember:
    begin
      Result.Description := _('Public member has no callers anywhere - dead API');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Orphan;        // <-- never called'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// If the member was kept "just in case", delete it -'#13#10 +
        '// version control keeps the history.'#13#10 +
        '// If it is plugin/RTTI surface (rare in single-unit code),'#13#10 +
        '// suppress with:  // noinspection UnusedPublicMember';
    end;

  end;
end;

end.
