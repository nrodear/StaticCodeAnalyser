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
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uLocalization;

type
  TFixHint = record
    Description : string;   // Einzeilige Problembeschreibung (lokalisiert)
    Before      : string;   // Code-Beispiel "Vorher" (Englisch)
    After       : string;   // Code-Beispiel "Nachher" (Englisch)
  end;

  TFixHintResolver = class
  private
    // Memoize-Cache: Key = (Ord(Kind) shl 8) or Ord(Severity).
    // Notwendig fuer IDE-Plugin auf Riesen-Scans (>100k Findings):
    // HighlightAllFindingsInFile rief FixHint() pro Finding, jedes Mal
    // mit _() Gettext-Lookup + ~3 KB String-Allokation -> Win32-OOM.
    // Mit Cache: 165 unique Slots statt N-mal-Allokation; Result-Strings
    // sind ref-counted, downstream-Entries teilen sich Heap-Speicher.
    class var FCache : TDictionary<Integer, TFixHint>;
    class function Build(const Finding: TLeakFinding): TFixHint; static;
  public
    class function FixHint(const Finding: TLeakFinding): TFixHint; static;
  end;

implementation

// noinspection-file DateFormatSettings, HttpInsteadOfHttps, LargeClass, StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function TFixHintResolver.FixHint(const Finding: TLeakFinding): TFixHint;
var
  Key : Integer;
begin
  if FCache = nil then
    FCache := TDictionary<Integer, TFixHint>.Create;
  Key := (Ord(Finding.Kind) shl 8) or Ord(Finding.Severity);
  if FCache.TryGetValue(Key, Result) then Exit;
  Result := Build(Finding);
  FCache.AddOrSetValue(Key, Result);
end;

class function TFixHintResolver.Build(const Finding: TLeakFinding): TFixHint;
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

    fkCanBeUnitPrivate:
    begin
      Result.Description := _('Public member is referenced only within the current unit - Delphi-classic `private` (unit-scope) suffices');
      Result.Before :=
        'unit U;'#13#10 +
        ''#13#10 +
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Helper;'#13#10 +
        '  end;'#13#10 +
        '  TBar = class'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure TBar.Run;'#13#10 +
        'begin'#13#10 +
        '  // Sibling-class call inside the SAME unit'#13#10 +
        '  FFoo.Helper;'#13#10 +
        'end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private                  // Delphi-classic: unit-scope'#13#10 +
        '    procedure Helper;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// TBar.Run still compiles - `private` allows access from any'#13#10 +
        '// code in the SAME unit, not just the declaring class.'#13#10 +
        '// Single-file scan: if a foreign unit consumes Helper, the'#13#10 +
        '// compiler will surface E2361 and you revert the change.'#13#10 +
        ''#13#10 +
        '// Suppress with: // noinspection CanBeUnitPrivate';
    end;

    fkCanBeStrictPrivate:
    begin
      Result.Description := _('Public member is used only by methods of its own class - `strict private` reaches the strongest encapsulation');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Helper;       // ONLY TFoo.Run calls Helper'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure TFoo.Run; begin Helper; end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  strict private          // D2007+: class-scope, not unit-scope'#13#10 +
        '    procedure Helper;'#13#10 +
        '  public'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// `strict private` blocks sibling classes / helpers / top-level'#13#10 +
        '// code in the same unit from reaching Helper. Stronger than'#13#10 +
        '// Delphi-classic `private` and the cleanest signal of intent.'#13#10 +
        ''#13#10 +
        '// Suppress with: // noinspection CanBeStrictPrivate';
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

    // -------- SonarDelphi-Import (SCA060 ff.) --------

    fkGotoStatement:
    begin
      Result.Description := _('goto weakens structured control flow');
      Result.Before :=
        'label MyExit;'#13#10 +
        'begin'#13#10 +
        '  if Failed then goto MyExit;'#13#10 +
        '  DoMoreWork;'#13#10 +
        '  MyExit:'#13#10 +
        'end;';
      Result.After :=
        'begin'#13#10 +
        '  if Failed then Exit;'#13#10 +
        '  DoMoreWork;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// For multi-level break: extract an inner procedure and Exit from it.';
    end;

    fkTabulationCharacter:
    begin
      Result.Description := _('Tab character in source - use spaces for indentation');
      Result.Before :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '<TAB>DoStuff;          // <-- tab indent'#13#10 +
        'end;';
      Result.After :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  DoStuff;             // 2-space indent (Delphi convention)'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// IDE: Tools > Options > Editor > Source Options > Use tab character = off.';
    end;

    fkTooLongLine:
    begin
      Result.Description := _('Source line exceeds 120 characters - wrap or extract');
      Result.Before :=
        'Result := SomeReallyLongFunction(ArgumentOne, ArgumentTwo, ArgumentThree, ArgumentFour, ArgumentFive);';
      Result.After :=
        'Result := SomeReallyLongFunction('#13#10 +
        '  ArgumentOne, ArgumentTwo,'#13#10 +
        '  ArgumentThree, ArgumentFour, ArgumentFive);'#13#10 +
        ''#13#10 +
        '// Side-by-side diff is 2*120+gutter; longer lines break review tools.';
    end;

    fkTrailingWhitespace:
    begin
      Result.Description := _('Line ends with whitespace - diff hygiene');
      Result.Before :=
        '  DoStuff;...   <-- trailing spaces/tabs'#13#10 +
        '  AndMore;...';
      Result.After :=
        '  DoStuff;'#13#10 +
        '  AndMore;'#13#10 +
        ''#13#10 +
        '// IDE: Tools > Options > Editor > Save > Trim trailing whitespace.';
    end;

    fkLowercaseKeyword:
    begin
      Result.Description := _('Pascal keyword not in lowercase');
      Result.Before :=
        'Procedure Foo;'#13#10 +
        'Begin'#13#10 +
        '  If X then DoStuff;'#13#10 +
        'End;';
      Result.After :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  if X then DoStuff;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Delphi convention (DocWiki, Marco Cantu, SonarDelphi):'#13#10 +
        '// keywords lowercase, identifiers PascalCase.';
    end;

    fkNoSonarMarker:
    begin
      Result.Description := _('// NOSONAR suppression marker found - audit it');
      Result.Before :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM users WHERE id = '' + Id; // NOSONAR';
      Result.After :=
        '// Either fix the underlying issue:'#13#10 +
        'Query.SQL.Text := ''SELECT * FROM users WHERE id = :id'';'#13#10 +
        'Query.ParamByName(''id'').AsInteger := Id;'#13#10 +
        ''#13#10 +
        '// Or document WHY the suppression is justified:'#13#10 +
        '// NOSONAR: id is a constant from an enum, no user input.'#13#10 +
        ''#13#10 +
        '// The detector is a reminder, not a verdict - it surfaces every'#13#10 +
        '// // NOSONAR so each one can be re-reviewed periodically.';
    end;

    fkEmptyArgumentList:
    begin
      Result.Description := _('Empty argument list "()" - drop the parentheses');
      Result.Before :=
        'DoStuff();'#13#10 +
        'Result := FCalculator.Run();';
      Result.After :=
        'DoStuff;'#13#10 +
        'Result := FCalculator.Run;'#13#10 +
        ''#13#10 +
        '// In Pascal a parameterless call has no parentheses, unlike C/Java.'#13#10 +
        '// Exception: pointer-to-method types (@Foo()) - those keep the ().';
    end;

    fkInlineAssembly:
    begin
      Result.Description := _('asm..end block - platform-specific, hard to port');
      Result.Before :=
        'function FastCount(P: PByte; Len: Integer): Integer;'#13#10 +
        'asm'#13#10 +
        '  // Win32-only inline asm'#13#10 +
        '  ...'#13#10 +
        'end;';
      Result.After :=
        '// Prefer a pure-Pascal version unless a profiler proves'#13#10 +
        '// the asm is needed. If asm is unavoidable:'#13#10 +
        '//   * isolate it behind {$IFDEF CPUX86} / {$IFDEF CPUX64}'#13#10 +
        '//   * write a portable Pascal fallback'#13#10 +
        '//   * benchmark before assuming the asm is faster (modern compilers'#13#10 +
        '//     often beat hand-rolled 32-bit asm).';
    end;

    fkTrailingCommaArgList:
    begin
      Result.Description := _('Trailing comma in argument list');
      Result.Before :=
        'Logger.Info(''ctx=%s'', [Ctx,]);   // <-- stray comma'#13#10 +
        'CallFoo(A, B,);                  // <-- ditto';
      Result.After :=
        'Logger.Info(''ctx=%s'', [Ctx]);'#13#10 +
        'CallFoo(A, B);'#13#10 +
        ''#13#10 +
        '// Unlike Python/JS, Pascal does not allow trailing commas in calls.'#13#10 +
        '// Usually a leftover from copy-paste or comment-out of last arg.';
    end;

    fkDigitGrouping:
    begin
      Result.Description := _('Large integer literal without digit grouping');
      Result.Before :=
        'const'#13#10 +
        '  MAX_TIMEOUT_MS = 30000;'#13#10 +
        '  ONE_MILLION   = 1000000;     // <-- hard to read';
      Result.After :=
        'const'#13#10 +
        '  MAX_TIMEOUT_MS = 30_000;'#13#10 +
        '  ONE_MILLION   = 1_000_000;'#13#10 +
        ''#13#10 +
        '// Underscores in integer literals are Delphi 10.4+. Use them for'#13#10 +
        '// any number with >= 5 digits to disambiguate magnitude at a glance.';
    end;

    fkCommentedOutCode:
    begin
      Result.Description := _('Comment contains Pascal-code markers - delete it or restore it');
      Result.Before :=
        '// FOldDb.Connect(Host, User);'#13#10 +
        '// FOldDb.Open;'#13#10 +
        '// if not FOldDb.IsOpen then'#13#10 +
        '//   raise EOldDbError.Create(''cannot open'');';
      Result.After :=
        '// Delete the dead block - git history keeps it forever.'#13#10 +
        ''#13#10 +
        '// If the code is intentionally kept as a reference,'#13#10 +
        '// move it to a `{ remarks ... }` doc-comment with a why-explanation,'#13#10 +
        '// or extract a private procedure with a meaningful name.';
    end;

    fkUnitLevelKeywordIndent:
    begin
      Result.Description := _('Unit-level keyword not at column 1');
      Result.Before :=
        '  unit uFoo;       // <-- indented'#13#10 +
        ''#13#10 +
        '  interface        // <-- indented'#13#10 +
        '  uses System.SysUtils;';
      Result.After :=
        'unit uFoo;'#13#10 +
        ''#13#10 +
        'interface'#13#10 +
        ''#13#10 +
        'uses'#13#10 +
        '  System.SysUtils;'#13#10 +
        ''#13#10 +
        '// unit/interface/implementation/initialization/finalization/end'#13#10 +
        '// start at column 1; nested code is indented within them.';
    end;

    fkRedundantBoolean:
    begin
      Result.Description := _('Boolean compared to True/False - redundant');
      Result.Before :=
        'if IsActive = True then ...'#13#10 +
        'if IsClosed <> False then ...'#13#10 +
        'while (Done = False) do ...';
      Result.After :=
        'if IsActive then ...'#13#10 +
        'if IsClosed then ...'#13#10 +
        'while not Done do ...'#13#10 +
        ''#13#10 +
        '// Boolean expression evaluates to a Boolean already -'#13#10 +
        '// "= True" is a no-op that hurts readability and makes'#13#10 +
        '// the buggy "if (x = True)" pattern more likely to slip in.';
    end;

    fkEmptyInterface:
    begin
      Result.Description := _('Interface declaration has no methods');
      Result.Before :=
        'type'#13#10 +
        '  IPlugin = interface'#13#10 +
        '    [''{1234-...}'']'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  IPlugin = interface'#13#10 +
        '    [''{1234-...}'']'#13#10 +
        '    procedure Initialize;'#13#10 +
        '    procedure Shutdown;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Empty interface adds no behaviour and no type safety -'#13#10 +
        '// any class satisfies it. Either give it methods (real contract)'#13#10 +
        '// or use a tag attribute / class-helper class-method as marker.';
    end;

    fkAssertMessage:
    begin
      Result.Description := _('Assert() without explanatory message');
      Result.Before :=
        'Assert(List <> nil);'#13#10 +
        'Assert(Index < Count);';
      Result.After :=
        'Assert(List <> nil, ''List must be initialized before Process'');'#13#10 +
        'Assert(Index < Count, Format(''Index %d out of range [0..%d)'','#13#10 +
        '  [Index, Count]));'#13#10 +
        ''#13#10 +
        '// The message is what the developer reads when the assertion fires.'#13#10 +
        '// Without it, the message is just the source line - useless if'#13#10 +
        '// the binary is in production / a customer environment.';
    end;

    fkExplicitTObjectInheritance:
    begin
      Result.Description := _('class(TObject) - TObject is the default base, drop it');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class(TObject)'#13#10 +
        '    ...'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '    ...'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// "class" without a parent is equivalent to "class(TObject)" -'#13#10 +
        '// the explicit form adds noise without adding meaning.';
    end;

    fkGroupedDeclaration:
    begin
      Result.Description := _('Grouped variable/field declaration - one per line');
      Result.Before :=
        'var'#13#10 +
        '  A, B, C: Integer;'#13#10 +
        ''#13#10 +
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '    FX, FY: Double;'#13#10 +
        '  end;';
      Result.After :=
        'var'#13#10 +
        '  A: Integer;'#13#10 +
        '  B: Integer;'#13#10 +
        '  C: Integer;'#13#10 +
        ''#13#10 +
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '    FX: Double;'#13#10 +
        '    FY: Double;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// One declaration per line: easier diffs, individual comments,'#13#10 +
        '// XML-Doc per field. Exception: parameter lists keep grouping'#13#10 +
        '// (procedure Foo(const A, B: Integer)).';
    end;

    fkEmptyBlock:
    begin
      Result.Description := _('Empty begin..end block');
      Result.Before :=
        'if Condition then'#13#10 +
        'begin'#13#10 +
        '  // TODO'#13#10 +
        'end'#13#10 +
        'else'#13#10 +
        '  DoStuff;';
      Result.After :=
        'if not Condition then'#13#10 +
        '  DoStuff;'#13#10 +
        ''#13#10 +
        '// An empty begin..end is either dead code (delete) or unfinished'#13#10 +
        '// (track it). Empty METHOD bodies are handled by uEmptyMethod;'#13#10 +
        '// this detector only flags bare begin..end inside if/while/...';
    end;

    fkExceptOnException:
    begin
      Result.Description := _('on E: Exception catches everything - too broad');
      Result.Before :=
        'try'#13#10 +
        '  DoDbWork;'#13#10 +
        'except'#13#10 +
        '  on E: Exception do'#13#10 +
        '    LogError(E.Message);'#13#10 +
        'end;';
      Result.After :=
        'try'#13#10 +
        '  DoDbWork;'#13#10 +
        'except'#13#10 +
        '  on E: EDatabaseError do'#13#10 +
        '    LogError(''DB: '' + E.Message);'#13#10 +
        '  on E: ETimeoutError do'#13#10 +
        '    LogError(''Timeout: '' + E.Message);'#13#10 +
        '  // anything else falls through to the caller'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Catching Exception swallows EAccessViolation/EOutOfMemory.'#13#10 +
        '// Catch the specific classes you can really recover from.';
    end;

    fkConsecutiveSection:
    begin
      Result.Description := _('Two consecutive const/type/var sections - merge them');
      Result.Before :=
        'const'#13#10 +
        '  TIMEOUT = 30;'#13#10 +
        ''#13#10 +
        'const'#13#10 +
        '  MAX_TRIES = 3;'#13#10 +
        ''#13#10 +
        'var'#13#10 +
        '  Counter: Integer;'#13#10 +
        ''#13#10 +
        'var'#13#10 +
        '  Total: Int64;';
      Result.After :=
        'const'#13#10 +
        '  TIMEOUT   = 30;'#13#10 +
        '  MAX_TRIES = 3;'#13#10 +
        ''#13#10 +
        'var'#13#10 +
        '  Counter : Integer;'#13#10 +
        '  Total   : Int64;'#13#10 +
        ''#13#10 +
        '// A single section per kind makes scanning faster and lets the'#13#10 +
        '// IDE outline collapse all-at-once.';
    end;

    fkRedundantJump:
    begin
      Result.Description := _('Exit/Continue/Break directly before end - redundant');
      Result.Before :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  DoStuff;'#13#10 +
        '  Exit;       // <-- redundant, end follows anyway'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'for i := 0 to N do'#13#10 +
        'begin'#13#10 +
        '  if Bad(i) then Continue;  // <-- redundant if at end of loop'#13#10 +
        'end;';
      Result.After :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  DoStuff;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'for i := 0 to N do'#13#10 +
        '  if not Bad(i) then'#13#10 +
        '    Process(i);';
    end;

    fkClassPerFile:
    begin
      Result.Description := _('Multiple class declarations in one unit');
      Result.Before :=
        '// uForms.pas'#13#10 +
        'type'#13#10 +
        '  TMainForm = class(TForm) ... end;'#13#10 +
        '  TDetailForm = class(TForm) ... end;'#13#10 +
        '  TLoginForm  = class(TForm) ... end;';
      Result.After :=
        '// uMainForm.pas       <-- TMainForm'#13#10 +
        '// uDetailForm.pas     <-- TDetailForm'#13#10 +
        '// uLoginForm.pas      <-- TLoginForm'#13#10 +
        ''#13#10 +
        '// One public class per unit makes file = symbol, browsing, blame'#13#10 +
        '// and IDE Class Completion straightforward. Private helper classes'#13#10 +
        '// next to the main class are fine; the rule targets multiple'#13#10 +
        '// EQUAL-WEIGHT public classes in one unit.';
    end;

    fkSuperfluousSemicolon:
    begin
      Result.Description := _('Double semicolon ";;" - one is enough');
      Result.Before :=
        'DoStuff;;'#13#10 +
        'Result := X + Y;;';
      Result.After :=
        'DoStuff;'#13#10 +
        'Result := X + Y;'#13#10 +
        ''#13#10 +
        '// The Pascal grammar allows it (empty statement), but the second'#13#10 +
        '// semicolon is dead. Usually leftover from rearranging code.';
    end;

    fkEmptyFinallyBlock:
    begin
      Result.Description := _('Empty finally block - either drop the try or add cleanup');
      Result.Before :=
        'Obj := TFoo.Create;'#13#10 +
        'try'#13#10 +
        '  DoWork(Obj);'#13#10 +
        'finally'#13#10 +
        '  // TODO: free Obj'#13#10 +
        'end;';
      Result.After :=
        'Obj := TFoo.Create;'#13#10 +
        'try'#13#10 +
        '  DoWork(Obj);'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(Obj);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// An empty finally is almost always a forgotten cleanup. If you'#13#10 +
        '// really need only exception handling, use try..except (not finally).';
    end;

    fkAssignedAndAssignedNil:
    begin
      Result.Description := _('Assigned(X) and (X <> nil) - one check is enough');
      Result.Before :=
        'if Assigned(Obj) and (Obj <> nil) then'#13#10 +
        '  Obj.Run;';
      Result.After :=
        'if Assigned(Obj) then'#13#10 +
        '  Obj.Run;'#13#10 +
        ''#13#10 +
        '// Assigned(X) is exactly "X <> nil" for object references and'#13#10 +
        '// dynamic arrays. Writing both is redundant and signals confusion'#13#10 +
        '// about ownership semantics.';
    end;

    fkFreeAndNilHint:
    begin
      Result.Description := _('X.Free; X := nil; -> use FreeAndNil(X)');
      Result.Before :=
        'FCache.Free;'#13#10 +
        'FCache := nil;';
      Result.After :=
        'FreeAndNil(FCache);'#13#10 +
        ''#13#10 +
        '// FreeAndNil is atomic for the field assignment and clearer in'#13#10 +
        '// intent. Especially important in destructors / shared state where'#13#10 +
        '// a re-entrant call could see Free''d-but-not-nil''d.';
    end;

    fkAvoidOut:
    begin
      Result.Description := _('out parameter - prefer Result or var');
      Result.Before :=
        'procedure ParseUser(const Raw: string; out User: TUser);'#13#10 +
        'begin'#13#10 +
        '  User.Id   := ...;'#13#10 +
        '  User.Name := ...;'#13#10 +
        'end;';
      Result.After :=
        'function ParseUser(const Raw: string): TUser;'#13#10 +
        'begin'#13#10 +
        '  Result.Id   := ...;'#13#10 +
        '  Result.Name := ...;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// out has counter-intuitive semantics: the existing value is'#13#10 +
        '// CLEARED before the call (managed types finalized). Most uses'#13#10 +
        '// are better as a function Result or, if multiple outputs are'#13#10 +
        '// needed, a record return type. Reserve out for COM-style APIs.';
    end;

    fkEmptyVisibilitySection:
    begin
      Result.Description := _('Empty visibility section in class - delete it');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    // (empty)'#13#10 +
        '  public'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  public'#13#10 +
        '    procedure Run;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// An empty visibility keyword is just noise. Common after'#13#10 +
        '// refactoring moved all members of a section elsewhere.';
    end;

    fkLegacyInitializationSection:
    begin
      Result.Description := _('Unit ends with begin..end. - use initialization section');
      Result.Before :=
        'unit uOld;'#13#10 +
        'interface'#13#10 +
        '...'#13#10 +
        'implementation'#13#10 +
        '...'#13#10 +
        'begin'#13#10 +
        '  RegisterClasses([TFoo, TBar]);'#13#10 +
        'end.';
      Result.After :=
        'unit uOld;'#13#10 +
        'interface'#13#10 +
        '...'#13#10 +
        'implementation'#13#10 +
        '...'#13#10 +
        'initialization'#13#10 +
        '  RegisterClasses([TFoo, TBar]);'#13#10 +
        ''#13#10 +
        'finalization'#13#10 +
        '  // matching cleanup if needed'#13#10 +
        ''#13#10 +
        'end.'#13#10 +
        ''#13#10 +
        '// The bare begin..end. is Turbo-Pascal-era; modern Delphi has'#13#10 +
        '// initialization/finalization for symmetric unit lifecycle.';
    end;

    fkPublicField:
    begin
      Result.Description := _('Public field - expose a property instead');
      Result.Before :=
        'type'#13#10 +
        '  TPerson = class'#13#10 +
        '  public'#13#10 +
        '    Name: string;     // <-- public field'#13#10 +
        '    Age:  Integer;    // <-- public field'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TPerson = class'#13#10 +
        '  private'#13#10 +
        '    FName : string;'#13#10 +
        '    FAge  : Integer;'#13#10 +
        '  public'#13#10 +
        '    property Name: string  read FName write FName;'#13#10 +
        '    property Age:  Integer read FAge  write FAge;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Properties allow later getter/setter logic, validation, RTTI,'#13#10 +
        '// and DFM streaming without breaking callers. Plain fields lock'#13#10 +
        '// the API to direct memory access.';
    end;

    fkNestedTry:
    begin
      Result.Description := _('Nested try block - consider extracting a procedure');
      Result.Before :=
        'try'#13#10 +
        '  OpenFile;'#13#10 +
        '  try'#13#10 +
        '    ProcessFile;'#13#10 +
        '    try'#13#10 +
        '      WriteResults;'#13#10 +
        '    finally CloseResults; end;'#13#10 +
        '  finally CloseFile; end;'#13#10 +
        'except'#13#10 +
        '  on E: Exception do LogError(E);'#13#10 +
        'end;';
      Result.After :=
        '// Extract each owned resource into its own routine.'#13#10 +
        'procedure ProcessFileSafely;'#13#10 +
        'begin'#13#10 +
        '  OpenFile;'#13#10 +
        '  try'#13#10 +
        '    ProcessAndWrite;   // owns its own try/finally'#13#10 +
        '  finally'#13#10 +
        '    CloseFile;'#13#10 +
        '  end;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'try'#13#10 +
        '  ProcessFileSafely;'#13#10 +
        'except'#13#10 +
        '  on E: Exception do LogError(E);'#13#10 +
        'end;';
    end;

    fkCaseStatementSize:
    begin
      Result.Description := _('case statement has many branches - consider dispatch table');
      Result.Before :=
        'case Cmd of'#13#10 +
        '  cmdOpen   : DoOpen;'#13#10 +
        '  cmdClose  : DoClose;'#13#10 +
        '  cmdSave   : DoSave;'#13#10 +
        '  cmdSaveAs : DoSaveAs;'#13#10 +
        '  // ... 10+ more branches'#13#10 +
        'end;';
      Result.After :=
        '// Dispatch table indexed by command enum.'#13#10 +
        'type TCmdProc = procedure of object;'#13#10 +
        'var Handlers: array[TCmd] of TCmdProc;'#13#10 +
        ''#13#10 +
        'initialization'#13#10 +
        '  Handlers[cmdOpen]  := DoOpen;'#13#10 +
        '  Handlers[cmdClose] := DoClose;'#13#10 +
        '  ...'#13#10 +
        ''#13#10 +
        '// dispatch:'#13#10 +
        'if Assigned(Handlers[Cmd]) then Handlers[Cmd]();'#13#10 +
        ''#13#10 +
        '// 10+ case branches = the code reads as data, not control flow.'#13#10 +
        '// A table or polymorphic dispatch scales better.';
    end;

    fkEmptyFile:
    begin
      Result.Description := _('Unit has no declarations - delete it or fill it');
      Result.Before :=
        'unit uPlaceholder;'#13#10 +
        ''#13#10 +
        'interface'#13#10 +
        ''#13#10 +
        'implementation'#13#10 +
        ''#13#10 +
        'end.';
      Result.After :=
        '// Either delete the unit (and remove from .dpr/.dproj contains)'#13#10 +
        '// or add the planned declarations. An empty unit shows up in'#13#10 +
        '// uses-clauses without buying anything.';
    end;

    fkTwiceInheritedCalls:
    begin
      Result.Description := _('Method calls inherited more than once');
      Result.Before :=
        'procedure TDerived.Update;'#13#10 +
        'begin'#13#10 +
        '  inherited;       // <-- first call'#13#10 +
        '  Recompute;'#13#10 +
        '  inherited;       // <-- second call: double side effects!'#13#10 +
        'end;';
      Result.After :=
        'procedure TDerived.Update;'#13#10 +
        'begin'#13#10 +
        '  inherited;'#13#10 +
        '  Recompute;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Calling the same parent twice in one method runs the base-class'#13#10 +
        '// logic - including event triggers, refcount changes, logging -'#13#10 +
        '// twice. Almost always a copy-paste artefact.';
    end;

    fkRedundantParentheses:
    begin
      Result.Description := _('Doubled parentheses around a simple expression');
      Result.Before :=
        'if ((Counter)) > 0 then ...'#13#10 +
        'Result := ((FCache.Value));';
      Result.After :=
        'if Counter > 0 then ...'#13#10 +
        'Result := FCache.Value;'#13#10 +
        ''#13#10 +
        '// Use parentheses where they clarify operator precedence:'#13#10 +
        '//   Result := (A or B) and C;'#13#10 +
        '// not where they only add visual noise.';
    end;

    fkConsecutiveVisibility:
    begin
      Result.Description := _('Two visibility sections with the same keyword - merge them');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    FA: Integer;'#13#10 +
        '  private              // <-- duplicate private'#13#10 +
        '    FB: Integer;'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    FA: Integer;'#13#10 +
        '    FB: Integer;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// One visibility section per kind. Common after merging field'#13#10 +
        '// blocks from two parts of the class.';
    end;

    fkConstructorWithoutInherited:
    begin
      Result.Description := _('Constructor does not call inherited - parent state uninitialized');
      Result.Before :=
        'constructor TDerived.Create(AOwner: TComponent);'#13#10 +
        'begin'#13#10 +
        '  // missing: inherited Create(AOwner);'#13#10 +
        '  FList := TStringList.Create;'#13#10 +
        'end;';
      Result.After :=
        'constructor TDerived.Create(AOwner: TComponent);'#13#10 +
        'begin'#13#10 +
        '  inherited Create(AOwner);'#13#10 +
        '  FList := TStringList.Create;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Without inherited, the parent never runs its own constructor:'#13#10 +
        '// for TComponent that means FComponents, FName, owner-tracking'#13#10 +
        '// are never initialized -> crashes on first use.';
    end;

    fkDestructorWithoutInherited:
    begin
      Result.Description := _('Destructor does not call inherited - resource leak');
      Result.Before :=
        'destructor TDerived.Destroy;'#13#10 +
        'begin'#13#10 +
        '  FreeAndNil(FList);'#13#10 +
        '  // missing: inherited Destroy;'#13#10 +
        'end;';
      Result.After :=
        'destructor TDerived.Destroy;'#13#10 +
        'begin'#13#10 +
        '  FreeAndNil(FList);'#13#10 +
        '  inherited Destroy;        // <-- always last'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Without inherited, the parent destructor never runs:'#13#10 +
        '// TComponent.Destroy never frees its components, TObject never'#13#10 +
        '// runs its cleanup. Pattern: own resources first, inherited last.';
    end;

    fkRedundantConditional:
    begin
      Result.Description := _('if X then Y := True else Y := False - assign expression directly');
      Result.Before :=
        'if Counter > 0 then'#13#10 +
        '  HasItems := True'#13#10 +
        'else'#13#10 +
        '  HasItems := False;';
      Result.After :=
        'HasItems := Counter > 0;'#13#10 +
        ''#13#10 +
        '// The if-form is verbose and obscures that the right-hand side'#13#10 +
        '// is itself a Boolean. Same applies to'#13#10 +
        '//   Result := if X then A else B    (Delphi: use IfThen).';
    end;

    fkIfElseBegin:
    begin
      Result.Description := _('Asymmetric begin/end in if/else - format consistently');
      Result.Before :=
        'if Condition then'#13#10 +
        '  DoOne'#13#10 +
        'else'#13#10 +
        'begin'#13#10 +
        '  DoTwo;'#13#10 +
        '  DoThree;'#13#10 +
        'end;';
      Result.After :=
        'if Condition then'#13#10 +
        'begin'#13#10 +
        '  DoOne;'#13#10 +
        'end'#13#10 +
        'else'#13#10 +
        'begin'#13#10 +
        '  DoTwo;'#13#10 +
        '  DoThree;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Mixed forms invite the classic "dangling else" misread.'#13#10 +
        '// Pick one style for the branch and apply both ways.';
    end;

    fkPointerName:
    begin
      Result.Description := _('Pointer type alias should start with "P"');
      Result.Before :=
        'type'#13#10 +
        '  RecordPtr = ^TRecord;        // <-- no P-prefix'#13#10 +
        '  FooHandle = ^TFoo;           // <-- no P-prefix';
      Result.After :=
        'type'#13#10 +
        '  PRecord = ^TRecord;'#13#10 +
        '  PFoo    = ^TFoo;'#13#10 +
        ''#13#10 +
        '// Delphi convention: pointer aliases start with P (PChar, PRecord,'#13#10 +
        '// PByte, ...). The prefix makes it instantly visible that the type'#13#10 +
        '// is indirect at every call site.';
    end;

    fkBeginEndRequired:
    begin
      Result.Description := _('Branch body without begin..end - add explicit block');
      Result.Before :=
        'if Condition then'#13#10 +
        '  DoOne;'#13#10 +
        ''#13#10 +
        'for i := 0 to N - 1 do'#13#10 +
        '  Process(i);';
      Result.After :=
        'if Condition then'#13#10 +
        'begin'#13#10 +
        '  DoOne;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'for i := 0 to N - 1 do'#13#10 +
        'begin'#13#10 +
        '  Process(i);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Always-begin..end is debatable in Delphi (compact form is widely'#13#10 +
        '// used), but enforcing it prevents the goto-fail bug: adding a'#13#10 +
        '// second statement under "if X then" silently misindents otherwise.';
    end;

    fkNestedRoutine:
    begin
      Result.Description := _('Nested procedure/function - consider extracting');
      Result.Before :=
        'procedure TFoo.Run;'#13#10 +
        ''#13#10 +
        '  procedure Helper(X: Integer);'#13#10 +
        '  begin'#13#10 +
        '    ...'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'begin'#13#10 +
        '  Helper(1); Helper(2);'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.Helper(X: Integer);'#13#10 +
        'begin'#13#10 +
        '  ...'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'procedure TFoo.Run;'#13#10 +
        'begin'#13#10 +
        '  Helper(1); Helper(2);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Nested routines are testable only via their parent and surprise'#13#10 +
        '// the IDE Class Completion. Extract to private class methods or'#13#10 +
        '// to a unit-private function unless closure over parent locals is'#13#10 +
        '// the whole point.';
    end;

    fkFieldName:
    begin
      Result.Description := _('Class field without "F" prefix');
      Result.Before :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    Counter : Integer;     // <-- no F-prefix'#13#10 +
        '    Name    : string;      // <-- no F-prefix'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TFoo = class'#13#10 +
        '  private'#13#10 +
        '    FCounter : Integer;'#13#10 +
        '    FName    : string;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Delphi convention (Embarcadero DocWiki + community): private'#13#10 +
        '// fields start with F. Makes "FCounter" visually distinct from'#13#10 +
        '// the "Counter" property/parameter at every assignment.';
    end;

    fkTypeName:
    begin
      Result.Description := _('Class/record type without "T" prefix');
      Result.Before :=
        'type'#13#10 +
        '  Person = class                 // <-- no T-prefix'#13#10 +
        '    ...'#13#10 +
        '  end;'#13#10 +
        '  Point = record X, Y: Integer end;';
      Result.After :=
        'type'#13#10 +
        '  TPerson = class'#13#10 +
        '    ...'#13#10 +
        '  end;'#13#10 +
        '  TPoint = record X, Y: Integer end;'#13#10 +
        ''#13#10 +
        '// Delphi RTL convention: T = type, P = pointer, I = interface,'#13#10 +
        '// E = exception. Prefix tells readers what kind of identifier'#13#10 +
        '// they''re looking at without jumping to the declaration.';
    end;

    fkInterfaceName:
    begin
      Result.Description := _('Interface type without "I" prefix');
      Result.Before :=
        'type'#13#10 +
        '  Plugin = interface           // <-- no I-prefix'#13#10 +
        '    [''{1234-...}'']'#13#10 +
        '    procedure Initialize;'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  IPlugin = interface'#13#10 +
        '    [''{1234-...}'']'#13#10 +
        '    procedure Initialize;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Delphi convention since Delphi 3 / COM: interfaces start with I.'#13#10 +
        '// Without the prefix, "var P: Plugin" reads like a value type.';
    end;

    fkMethodName:
    begin
      Result.Description := _('Method name not in PascalCase');
      Result.Before :=
        'procedure TFoo.do_stuff;       // <-- snake_case'#13#10 +
        'procedure TFoo.runFast;        // <-- camelCase'#13#10 +
        'procedure TFoo.RUN_NOW;        // <-- UPPER_SNAKE_CASE';
      Result.After :=
        'procedure TFoo.DoStuff;'#13#10 +
        'procedure TFoo.RunFast;'#13#10 +
        'procedure TFoo.RunNow;'#13#10 +
        ''#13#10 +
        '// Delphi standard: PascalCase for routines and properties.'#13#10 +
        '// Reserve snake_case for C-API imports (where the name has to'#13#10 +
        '// match the foreign symbol) and tag those with the {$EXTERNAL...}.';
    end;

    // -------- Concurrency-Detektoren (SCA108 ff.) --------

    fkSynchronizeInDestructor:
    begin
      Result.Description := _('Synchronize() in a destructor - worker and UI thread deadlock each other');
      Result.Before :=
        'destructor TWorker.Destroy;'#13#10 +
        'begin'#13#10 +
        '  // UI-Thread wartet typischerweise schon auf WaitFor / .Free,'#13#10 +
        '  // dieser Aufruf blockt den Worker auf eben diesen UI-Thread.'#13#10 +
        '  Synchronize('#13#10 +
        '    procedure'#13#10 +
        '    begin'#13#10 +
        '      Form1.Log(''worker done'');'#13#10 +
        '    end);'#13#10 +
        '  inherited;'#13#10 +
        'end;';
      Result.After :=
        '// Notify VOR der Zerstoerung - OnTerminate laeuft im UI-Thread'#13#10 +
        '// nachdem der Worker Execute verlassen hat, aber BEVOR der'#13#10 +
        '// Destruktor anlaeuft. Kein Synchronize noetig.'#13#10 +
        'Worker := TWorker.Create(True);'#13#10 +
        'Worker.OnTerminate :='#13#10 +
        '  procedure(Sender: TObject)'#13#10 +
        '  begin'#13#10 +
        '    Form1.Log(''worker done'');'#13#10 +
        '  end;'#13#10 +
        'Worker.Start;'#13#10 +
        ''#13#10 +
        '// Destruktor bleibt Synchronize-frei.'#13#10 +
        ''#13#10 +
        '// Suppression: // noinspection SynchronizeInDestructor'#13#10 +
        '// (nur wenn DU SICHER bist, dass das Free niemals vom UI-Thread kommt).';
    end;

    fkLockWithoutTryFinally:
    begin
      Result.Description := _('Lock acquired without try..finally release - exception leaves the lock held');
      Result.Before :=
        'FLock := TCriticalSection.Create;'#13#10 +
        '...'#13#10 +
        'FLock.Enter;'#13#10 +
        'DoWork;            // <- Exception hier'#13#10 +
        'FLock.Leave;       //    erreicht Leave nie';
      Result.After :=
        'FLock.Enter;'#13#10 +
        'try'#13#10 +
        '  DoWork;'#13#10 +
        'finally'#13#10 +
        '  FLock.Leave;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Selbe Regel fuer: TCriticalSection.Acquire/Release,'#13#10 +
        '// TMonitor.Enter/Exit, TMREWSync.BeginWrite/EndWrite,'#13#10 +
        '// EnterCriticalSection/LeaveCriticalSection (WinAPI).'#13#10 +
        ''#13#10 +
        '// Suppression: // noinspection LockWithoutTryFinally'#13#10 +
        '// (sehr selten - meist heisst es nur, dass DoWork niemals wirft,'#13#10 +
        '//  was du nicht wirklich beweisen kannst).';
    end;

    // -------- Performance-Hotspots (SCA110-112) --------

    fkStringConcatInLoop:
    begin
      Result.Description := _('String concatenation in loop - quadratic reallocations');
      Result.Before :=
        'for i := 0 to High(Items) do'#13#10 +
        '  s := s + Items[i] + '', '';';
      Result.After :=
        'var SB := TStringBuilder.Create;'#13#10 +
        'try'#13#10 +
        '  for i := 0 to High(Items) do'#13#10 +
        '    SB.Append(Items[i]).Append('', '');'#13#10 +
        '  s := SB.ToString;'#13#10 +
        'finally'#13#10 +
        '  SB.Free;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Alternative: TStringList nutzen, am Ende .DelimitedText / .Text auslesen.';
    end;

    fkParamByNameInLoop:
    begin
      Result.Description := _('ParamByName in loop - cache the TParam reference outside');
      Result.Before :=
        'for i := 0 to High(Ids) do'#13#10 +
        'begin'#13#10 +
        '  Q.ParamByName(''id'').AsInteger := Ids[i];'#13#10 +
        '  Q.ExecSQL;'#13#10 +
        'end;';
      Result.After :=
        'var P := Q.ParamByName(''id'');'#13#10 +
        'for i := 0 to High(Ids) do'#13#10 +
        'begin'#13#10 +
        '  P.AsInteger := Ids[i];'#13#10 +
        '  Q.ExecSQL;'#13#10 +
        'end;';
    end;

    fkFieldByNameInLoop:
    begin
      Result.Description := _('FieldByName in loop - cache the TField reference outside');
      Result.Before :=
        'while not Q.Eof do'#13#10 +
        'begin'#13#10 +
        '  Total := Total + Q.FieldByName(''Amount'').AsCurrency;'#13#10 +
        '  Q.Next;'#13#10 +
        'end;';
      Result.After :=
        'var FldAmount := Q.FieldByName(''Amount'');'#13#10 +
        'while not Q.Eof do'#13#10 +
        'begin'#13#10 +
        '  Total := Total + FldAmount.AsCurrency;'#13#10 +
        '  Q.Next;'#13#10 +
        'end;';
    end;

    // -------- Concurrency-Familie erweitert (SCA113-114) --------

    fkThreadResumeDeprecated:
    begin
      Result.Description := _('TThread.Resume is deprecated - use TThread.Start (since Delphi 2010)');
      Result.Before :=
        'MyThread := TWorker.Create(True);  // CreateSuspended=True'#13#10 +
        'MyThread.Resume;                    // deprecated';
      Result.After :=
        'MyThread := TWorker.Create(True);'#13#10 +
        'MyThread.Start;                    // since D2010'#13#10 +
        ''#13#10 +
        '// Oder direkt unsuspended:'#13#10 +
        'MyThread := TWorker.Create(False);'#13#10 +
        ''#13#10 +
        '// Suppression: // noinspection ThreadResumeDeprecated'#13#10 +
        '// (wenn .Resume eine Custom-Methode ist, nicht TThread.Resume).';
    end;

    fkTThreadDestroyWithoutTerminate:
    begin
      Result.Description := _('TThread destroyed without Terminate+WaitFor - worker may still be running');
      Result.Before :=
        '// inside an OnClick or destructor:'#13#10 +
        'FreeAndNil(FWorker);';
      Result.After :=
        'FWorker.Terminate;'#13#10 +
        'FWorker.WaitFor;'#13#10 +
        'FreeAndNil(FWorker);'#13#10 +
        ''#13#10 +
        '// Worker selbst muss Terminated regelmaessig pruefen:'#13#10 +
        '//   while not Terminated do DoStep;'#13#10 +
        ''#13#10 +
        '// Alternative: FreeOnTerminate := True;'#13#10 +
        '//   - dann NIEMALS manuell Free aufrufen'#13#10 +
        '//   - der Thread ist nach Execute selber weg.';
    end;

    // -------- REST/HTTP-Security (SCA115-116) --------

    fkHttpInsteadOfHttps:
    begin
      Result.Description := _('Plaintext HTTP URL - prefer https:// for remote endpoints');
      Result.Before :=
        'const'#13#10 +
        '  API_URL = ''http://api.example.com/v1/users'';';
      Result.After :=
        'const'#13#10 +
        '  API_URL = ''https://api.example.com/v1/users'';'#13#10 +
        ''#13#10 +
        '// Localhost-URLs (http://localhost, 127.x.x.x, [::1])'#13#10 +
        '// werden vom Detektor ignoriert - kein Befund.'#13#10 +
        '// XML-Namespace-URLs (xmlns=, w3.org, schemas) auch.';
    end;

    fkDisabledTlsVerification:
    begin
      Result.Description := _('TLS verification disabled - MITM-attack surface');
      Result.Before :=
        'Client.SecureProtocols := [];'#13#10 +
        'Client.IgnoreCertificateErrors := True;'#13#10 +
        'Client.OnVerifyPeer := nil;';
      Result.After :=
        'Client.SecureProtocols := [TLSv1_2, TLSv1_3];'#13#10 +
        '// IgnoreCertificateErrors NIE auf True setzen - System-CA'#13#10 +
        '// store macht Validierung; Self-Signed: Custom-CA via Stores.'#13#10 +
        'Client.OnVerifyPeer := VerifyPinnedFingerprint;'#13#10 +
        ''#13#10 +
        '// Bei legitimen Dev-Setups mit Self-Signed-Cert: Cert ins'#13#10 +
        '// Windows-Cert-Store importieren statt Validierung deaktivieren.';
    end;

    // -------- Doc-Luecken (SCA117) --------

    fkPublicMemberWithoutDoc:
    begin
      Result.Description := _('Public member missing doc comment');
      Result.Before :=
        'type'#13#10 +
        '  TWorker = class'#13#10 +
        '  public'#13#10 +
        '    procedure Run;       // <- keine Doku'#13#10 +
        '    property Active: Boolean read FActive;'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TWorker = class'#13#10 +
        '  public'#13#10 +
        '    /// <summary>Starts the worker thread.</summary>'#13#10 +
        '    /// <remarks>Idempotent; calling on a running worker is a no-op.</remarks>'#13#10 +
        '    procedure Run;'#13#10 +
        ''#13#10 +
        '    // True wenn Execute laeuft und Terminated noch nicht gesetzt ist.'#13#10 +
        '    property Active: Boolean read FActive;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Akzeptierte Formate: ///-XMLDoc, { ... }, (* ... *), oder einfach'#13#10 +
        '// einzeilige //-Kommentare direkt darueber.';
    end;

    // -------- Naming-Familie erweitert (SCA118-119) --------

    fkExceptionName:
    begin
      Result.Description := _('Exception class without E-prefix');
      Result.Before :=
        'type'#13#10 +
        '  MyParseError = class(Exception);';
      Result.After :=
        'type'#13#10 +
        '  EMyParseError = class(Exception);'#13#10 +
        ''#13#10 +
        '// Delphi-RTL-Konvention: Exception-Klassen starten mit E.'#13#10 +
        '// EAbort, EConvertError, EAccessViolation, EDivByZero, ...';
    end;

    fkLocalConstantName:
    begin
      Result.Description := _('Local constant should be UPPER_SNAKE_CASE');
      Result.Before :=
        'procedure Foo;'#13#10 +
        'const'#13#10 +
        '  MaxRetries = 3;     // <- PascalCase = sieht aus wie Variable'#13#10 +
        '  BufferSize = 4096;'#13#10 +
        'begin ... end;';
      Result.After :=
        'procedure Foo;'#13#10 +
        'const'#13#10 +
        '  MAX_RETRIES = 3;'#13#10 +
        '  BUFFER_SIZE = 4096;'#13#10 +
        'begin ... end;'#13#10 +
        ''#13#10 +
        '// String-/Char-Konstanten und sehr kurze Namen (<=2 Zeichen)'#13#10 +
        '// werden vom Detektor uebersprungen.';
    end;

    // ---- SonarDelphi-Pendants SCA120..SCA131 (12 Detektoren) ---------------

    fkMissingRaise:
    begin
      Result.Description := _('Exception is constructed but never raised');
      Result.Before :=
        'if x < 0 then'#13#10 +
        '  EArgumentOutOfRangeException.Create(''x negative'');'#13#10 +
        '// ^ creates the object, throws nothing - error path is silently skipped.';
      Result.After :=
        'if x < 0 then'#13#10 +
        '  raise EArgumentOutOfRangeException.Create(''x negative'');'#13#10 +
        ''#13#10 +
        '// "raise" hands the constructed exception to the runtime;'#13#10 +
        '// without it the object is allocated, immediately collected (ARC)'#13#10 +
        '// or leaked (classic TObject), and the caller never notices.';
    end;

    fkRoutineResultUnassigned:
    begin
      Result.Description := _('Function never assigns Result - return value undefined');
      Result.Before :=
        'function GetCount(L: TList): Integer;'#13#10 +
        'begin'#13#10 +
        '  if L = nil then'#13#10 +
        '    LogMessage(''nil list'');'#13#10 +
        '  // Result is never set -> register garbage in Release builds.'#13#10 +
        'end;';
      Result.After :=
        'function GetCount(L: TList): Integer;'#13#10 +
        'begin'#13#10 +
        '  Result := 0;          // default for every reachable path'#13#10 +
        '  if L <> nil then'#13#10 +
        '    Result := L.Count;'#13#10 +
        'end;';
    end;

    fkReRaiseException:
    begin
      Result.Description := _('Re-raise of bound variable loses the original stack trace');
      Result.Before :=
        'try'#13#10 +
        '  RiskyCall;'#13#10 +
        'except'#13#10 +
        '  on E: EDivByZero do'#13#10 +
        '  begin'#13#10 +
        '    Log(E.Message);'#13#10 +
        '    raise E;            // <- starts new propagation,'#13#10 +
        '                        //    original trace gone'#13#10 +
        '  end;'#13#10 +
        'end;';
      Result.After :=
        'try'#13#10 +
        '  RiskyCall;'#13#10 +
        'except'#13#10 +
        '  on E: EDivByZero do'#13#10 +
        '  begin'#13#10 +
        '    Log(E.Message);'#13#10 +
        '    raise;              // <- bare "raise" keeps the trace,'#13#10 +
        '                        //    crash reports still point at the fault'#13#10 +
        '  end;'#13#10 +
        'end;';
    end;

    fkCastAndFree:
    begin
      Result.Description := _('Type-cast before Free / Destroy has no effect (Destroy is virtual)');
      Result.Before :=
        'procedure Cleanup(L: TObject);'#13#10 +
        'begin'#13#10 +
        '  TStringList(L).Free;   // <- cast is redundant or misleading;'#13#10 +
        '                         //    Destroy is virtual, dispatches on runtime type'#13#10 +
        'end;';
      Result.After :=
        'procedure Cleanup(L: TObject);'#13#10 +
        'begin'#13#10 +
        '  L.Free;                // virtual Destroy resolves to TStringList.Destroy'#13#10 +
        '                         // automatically, no cast required'#13#10 +
        'end;';
    end;

    fkInstanceInvokedConstructor:
    begin
      Result.Description := _('Constructor invoked on instance - no allocation, fields re-initialised over live data');
      Result.Before :=
        'procedure Reset;'#13#10 +
        'var list: TStringList;'#13#10 +
        'begin'#13#10 +
        '  list := TStringList.Create;'#13#10 +
        '  ...'#13#10 +
        '  list.Create;           // <- bypasses TObject.NewInstance;'#13#10 +
        '                         //    just re-runs the constructor body on'#13#10 +
        '                         //    the existing object, overwriting fields'#13#10 +
        'end;';
      Result.After :=
        'procedure Reset;'#13#10 +
        'var list: TStringList;'#13#10 +
        'begin'#13#10 +
        '  list := TStringList.Create;'#13#10 +
        '  ...'#13#10 +
        '  list.Clear;            // or: FreeAndNil(list) + create new'#13#10 +
        'end;';
    end;

    fkInheritedMethodEmpty:
    begin
      Result.Description := _('Override whose body is just "inherited" adds nothing');
      Result.Before :=
        'procedure TFooSubclass.AfterConstruction; override;'#13#10 +
        'begin'#13#10 +
        '  inherited;             // <- empty override, wastes a VMT slot'#13#10 +
        '                         //    and forces every reader to verify'#13#10 +
        'end;';
      Result.After :=
        '// Remove the override entirely. Virtual dispatch falls'#13#10 +
        '// through to the parent automatically when no override exists.'#13#10 +
        ''#13#10 +
        '// (Different parent method intentionally?  Keep it but document why:'#13#10 +
        '//  inherited Initialise;  // hijack: call the parent of the parent)';
    end;

    fkNilComparison:
    begin
      Result.Description := _('Prefer Assigned() over "= nil" / "<> nil"');
      Result.Before :=
        'if Obj = nil then'#13#10 +
        '  Exit;'#13#10 +
        ''#13#10 +
        'if Obj <> nil then'#13#10 +
        '  Obj.DoStuff;';
      Result.After :=
        'if not Assigned(Obj) then'#13#10 +
        '  Exit;'#13#10 +
        ''#13#10 +
        'if Assigned(Obj) then'#13#10 +
        '  Obj.DoStuff;'#13#10 +
        ''#13#10 +
        '// Assigned() works for object refs, method pointers and Variants;'#13#10 +
        '// "= nil" silently breaks for method pointers.';
    end;

    fkRaisingRawException:
    begin
      Result.Description := _('Raise a specific exception class, not the base Exception');
      Result.Before :=
        'if x < 0 then'#13#10 +
        '  raise Exception.Create(''x is negative'');'#13#10 +
        '//      ^^^^^^^^^ callers cannot tell apart from any other failure;'#13#10 +
        '//                they must catch "on E: Exception" and swallow everything';
      Result.After :=
        'if x < 0 then'#13#10 +
        '  raise EArgumentOutOfRangeException.CreateFmt('#13#10 +
        '    ''x = %d (must be >= 0)'', [x]);'#13#10 +
        ''#13#10 +
        '// Specific subclass + format string -> caller can filter,'#13#10 +
        '// monitoring tools can group, crash report tells you which contract broke.';
    end;

    fkDateFormatSettings:
    begin
      Result.Description := _('Locale-dependent conversion without explicit TFormatSettings');
      Result.Before :=
        'd := StrToDate(UserInput);     // <- DE-machine: ''01.05.2026'' works.'#13#10 +
        '                               //    EN-machine: same call throws EConvertError.'#13#10 +
        's := DateToStr(Now);           //    Output flips between . and / by locale.'#13#10 +
        'x := StrToFloat(''3.14'');      //    DE machine expects ''3,14''.';
      Result.After :=
        'var FS: TFormatSettings;'#13#10 +
        'FS := TFormatSettings.Invariant;     // for machine-readable IO'#13#10 +
        ''#13#10 +
        'd := StrToDate(UserInput, FS);'#13#10 +
        's := DateToStr(Now,       FS);'#13#10 +
        'x := StrToFloat(''3.14'',   FS);'#13#10 +
        ''#13#10 +
        '// For UI: snapshot the user-locale once on form create:'#13#10 +
        '// FS := TFormatSettings.Create(LOCALE_USER_DEFAULT);';
    end;

    fkUnicodeToAnsiCast:
    begin
      Result.Description := _('8-bit string cast silently drops non-codepage characters');
      Result.Before :=
        'var u: UnicodeString;'#13#10 +
        'u := ''Smiley: '' + #$1F600;'#13#10 +
        ''#13#10 +
        'logStream.WriteString(AnsiString(u));'#13#10 +
        '//                    ^^^^^^^^^ smiley becomes ''?'';'#13#10 +
        '//                              umlauts on EN-locale machines too.';
      Result.After :=
        '// Pick an explicit encoding for the wire/disk format:'#13#10 +
        'var utf8: UTF8String;'#13#10 +
        'utf8 := UTF8Encode(u);'#13#10 +
        'logStream.WriteString(utf8);                       // full Unicode'#13#10 +
        '// or write the raw bytes via the standard TEncoding helper:'#13#10 +
        'var bytes: TBytes;'#13#10 +
        'bytes := TEncoding.UTF8.GetBytes(u);'#13#10 +
        'logStream.WriteBuffer(bytes[0], Length(bytes));'#13#10 +
        ''#13#10 +
        '// If a real AnsiString is required and ASCII-only is acceptable,'#13#10 +
        '// keep the cast but document the constraint at the call site.';
    end;

    fkCharToCharPointerCast:
    begin
      Result.Description := _('PChar(Char) reinterprets the codepoint as a pointer - undefined behaviour');
      Result.Before :=
        'var p: PChar;'#13#10 +
        'p := PChar(''A'');'#13#10 +
        '//   ^^^^^   p = $00000041 (the codepoint of ''A''),'#13#10 +
        '//           NOT a null-terminated 1-character string.'#13#10 +
        'ShowMessage(p);          // -> access violation';
      Result.After :=
        'var p: PChar;'#13#10 +
        'p := PChar(string(''A''));     // wrap into a real string first'#13#10 +
        '// or, for a literal use case:'#13#10 +
        'p := ''A'';                    // direct assignment, compiler builds the buffer'#13#10 +
        ''#13#10 +
        '// Same pitfall for PWideChar(Char) and PAnsiChar(AnsiChar).';
    end;

    fkIfThenShortCircuit:
    begin
      Result.Description := _('IfThen() evaluates both branches - no short-circuit semantics');
      Result.Before :=
        'x := Math.IfThen(IsCacheHit, FetchFromCache, FetchFromDb);'#13#10 +
        '//   ^^^^^^^^^^^ both FetchFromCache AND FetchFromDb run, every call;'#13#10 +
        '//               side effects + cost of both branches always paid.';
      Result.After :=
        'if IsCacheHit then'#13#10 +
        '  x := FetchFromCache'#13#10 +
        'else'#13#10 +
        '  x := FetchFromDb;'#13#10 +
        ''#13#10 +
        '// if/then/else has short-circuit semantics:'#13#10 +
        '// only the selected branch runs. Same applies to StrUtils.IfThen.';
    end;

    fkExceptionTooGeneral:
    begin
      Result.Description := _('except on E: Exception catches every error - prefer a specific subclass');
      Result.Before :=
        'try'#13#10 +
        '  ParseConfig(s);'#13#10 +
        'except'#13#10 +
        '  on E: Exception do          // <- swallows EOutOfMemory,'#13#10 +
        '    Log(E.Message);           //    EAbort, EAccessViolation, ...'#13#10 +
        'end;';
      Result.After :=
        'try'#13#10 +
        '  ParseConfig(s);'#13#10 +
        'except'#13#10 +
        '  on E: EConvertError do      // expected, recoverable'#13#10 +
        '    Log(E.Message);'#13#10 +
        '  on E: EFileNotFoundException do'#13#10 +
        '    Log(E.Message);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// System exceptions (EOutOfMemory, EAbort, ...) propagate'#13#10 +
        '// up to the global handler where they belong.';
    end;

    fkRaiseOutsideExcept:
    begin
      Result.Description := _('Bare raise; outside an except/on handler raises NIL - Access Violation');
      Result.Before :=
        'procedure Foo(x: Integer);'#13#10 +
        'begin'#13#10 +
        '  if x < 0 then'#13#10 +
        '    raise;                    // <- no current exception ->'#13#10 +
        'end;                          //    System._Raise gets NIL -> AV';
      Result.After :=
        'procedure Foo(x: Integer);'#13#10 +
        'begin'#13#10 +
        '  if x < 0 then'#13#10 +
        '    raise EArgumentException.CreateFmt('#13#10 +
        '      ''x = %d (must be >= 0)'', [x]);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Bare "raise;" is only valid INSIDE except / on handler'#13#10 +
        '// (re-raise the currently caught exception).';
    end;

    fkUseAfterFree:
    begin
      Result.Description := _('Variable used after Free / FreeAndNil - dangling pointer, AV likely');
      Result.Before :=
        'L := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  L.Add(''x'');'#13#10 +
        'finally'#13#10 +
        '  L.Free;'#13#10 +
        'end;'#13#10 +
        'L.Add(''y'');                  // <- L is dangling -> Access Violation';
      Result.After :=
        'L := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  L.Add(''x'');'#13#10 +
        '  L.Add(''y'');                 // use BEFORE Free'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(L);              // FreeAndNil so further use crashes loudly'#13#10 +
        'end;';
    end;

    fkAbstractNotImpl:
    begin
      Result.Description := _('Class inherits an abstract method but does not override it - EAbstractError');
      Result.Before :=
        'type'#13#10 +
        '  TBase = class'#13#10 +
        '    procedure DoWork; virtual; abstract;'#13#10 +
        '  end;'#13#10 +
        '  TDerived = class(TBase)'#13#10 +
        '    procedure SomethingElse;'#13#10 +
        '    // DoWork not overridden -> EAbstractError on call'#13#10 +
        '  end;';
      Result.After :=
        'type'#13#10 +
        '  TDerived = class(TBase)'#13#10 +
        '    procedure DoWork; override;     // implement contract'#13#10 +
        '    procedure SomethingElse;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Alternative: mark TDerived itself "class abstract" if it should'#13#10 +
        '// remain an intermediate base.';
    end;

    fkLeakInConstructor:
    begin
      Result.Description := _('Constructor allocates fields and raises - partially-initialized fields leak');
      Result.Before :=
        'constructor TFoo.Create;'#13#10 +
        'begin'#13#10 +
        '  FList := TStringList.Create;'#13#10 +
        '  FOther := TOtherThing.Create;'#13#10 +
        '  if not Valid then'#13#10 +
        '    raise EInvalidOp.Create(''bad'');     // <- FList + FOther leak'#13#10 +
        'end;';
      Result.After :=
        'constructor TFoo.Create;'#13#10 +
        'begin'#13#10 +
        '  FList := TStringList.Create;'#13#10 +
        '  try'#13#10 +
        '    FOther := TOtherThing.Create;'#13#10 +
        '    if not Valid then'#13#10 +
        '      raise EInvalidOp.Create(''bad'');'#13#10 +
        '  except'#13#10 +
        '    FreeAndNil(FOther);'#13#10 +
        '    FreeAndNil(FList);'#13#10 +
        '    raise;                              // preserve original exception'#13#10 +
        '  end;'#13#10 +
        'end;';
    end;

    fkIntegerOverflow:
    begin
      Result.Description := _('Int64 target gets product of two ints - multiplication overflows in 32-bit');
      Result.Before :=
        'var'#13#10 +
        '  BytesTotal: Int64;'#13#10 +
        '  SectorCount, SectorSize: Integer;'#13#10 +
        'begin'#13#10 +
        '  BytesTotal := SectorCount * SectorSize;'#13#10 +
        '  // <- multiplication runs in 32-bit, THEN widens to Int64;'#13#10 +
        '  //    product > MaxInt is silently truncated';
      Result.After :=
        'BytesTotal := Int64(SectorCount) * SectorSize;'#13#10 +
        ''#13#10 +
        '// Cast ONE operand to Int64 - the other is auto-promoted, then'#13#10 +
        '// multiplication runs in 64-bit and the result is exact.'#13#10 +
        '// Equivalent: declare one of the operands as Int64 from the start.';
    end;

    fkFreeWithoutNil:
    begin
      Result.Description := _('Free without nil-out - prefer FreeAndNil for dangling-pointer safety');
      Result.Before :=
        'L := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  L.Add(''x'');'#13#10 +
        'finally'#13#10 +
        '  L.Free;          // <- L still points at freed memory'#13#10 +
        'end;'#13#10 +
        '// any further L.Method call is Use-After-Free.';
      Result.After :=
        'L := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  L.Add(''x'');'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(L);   // L is nil afterwards; further use raises clearly'#13#10 +
        'end;';
    end;

    fkMultipleExit:
    begin
      Result.Description := _('Method has too many Exit statements - consolidate guards / single return');
      Result.Before :=
        'function Find(Id: Integer): TUser;'#13#10 +
        'begin'#13#10 +
        '  if Id < 0 then begin Result := nil; Exit; end;'#13#10 +
        '  if not Db.Connected then begin Result := nil; Exit; end;'#13#10 +
        '  if not Cache.Has(Id) then begin Result := DbLoad(Id); Exit; end;'#13#10 +
        '  Result := Cache.Get(Id);'#13#10 +
        '  Exit;                                       // 4. Exit'#13#10 +
        'end;';
      Result.After :=
        'function Find(Id: Integer): TUser;'#13#10 +
        'begin'#13#10 +
        '  Result := nil;'#13#10 +
        '  if (Id < 0) or not Db.Connected then Exit;'#13#10 +
        '  if Cache.Has(Id) then'#13#10 +
        '    Result := Cache.Get(Id)'#13#10 +
        '  else'#13#10 +
        '    Result := DbLoad(Id);'#13#10 +
        'end;'#13#10 +
        '// One early exit for guard conditions, then a single linear flow.';
    end;

    fkLargeClass:
    begin
      Result.Description := _('Class spans too many lines - split responsibilities into focused units');
      Result.Before :=
        '// TForm with 800 lines of business logic mixed with UI handlers,'#13#10 +
        '// database calls and report generation.'#13#10 +
        'TMainForm = class(TForm)'#13#10 +
        '  procedure btnRunClick(Sender: TObject);'#13#10 +
        '  // ... 60 more methods, 800 lines of impl ...'#13#10 +
        'end;';
      Result.After :=
        '// Extract verticals into focused classes:'#13#10 +
        'TReportRunner   = class ... end;     // own unit'#13#10 +
        'TDataController = class ... end;     // own unit'#13#10 +
        ''#13#10 +
        'TMainForm = class(TForm)'#13#10 +
        '  FReport: TReportRunner;'#13#10 +
        '  FData:   TDataController;'#13#10 +
        '  procedure btnRunClick(Sender: TObject);'#13#10 +
        'end;';
    end;

    fkUnsortedUses:
    begin
      Result.Description := _('uses clause is not in alphabetical order');
      Result.Before :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.Classes,'#13#10 +
        '  System.IOUtils,                   // <- alphabetical order broken'#13#10 +
        '  System.JSON;';
      Result.After :=
        'uses'#13#10 +
        '  System.Classes,'#13#10 +
        '  System.IOUtils,'#13#10 +
        '  System.JSON,'#13#10 +
        '  System.SysUtils;'#13#10 +
        ''#13#10 +
        '// Alphabetical order keeps merges deterministic + simplifies code review.';
    end;

    fkMissingUnitHeader:
    begin
      Result.Description := _('Unit has no descriptive header comment');
      Result.Before :=
        'unit MyUnit;'#13#10 +
        ''#13#10 +
        'interface                            // <- straight to code'#13#10 +
        ''#13#10 +
        'uses ...;';
      Result.After :=
        'unit MyUnit;'#13#10 +
        ''#13#10 +
        '// Database-connection pool: wraps FireDAC TFDConnection setup'#13#10 +
        '// for the report subsystem. Thread-safe; single instance per app.'#13#10 +
        ''#13#10 +
        'interface'#13#10 +
        ''#13#10 +
        'uses ...;';
    end;

    fkFloatEquality:
    begin
      Result.Description := _('Float equality is unreliable due to IEEE-754 rounding - use SameValue/Math.IsZero');
      Result.Before :=
        'var Ratio: Double;'#13#10 +
        '...'#13#10 +
        'if Ratio = 0.5 then              // <- almost never true after arithmetic'#13#10 +
        '  DoStuff;';
      Result.After :=
        'uses System.Math;                  // SameValue + IsZero'#13#10 +
        '...'#13#10 +
        'if SameValue(Ratio, 0.5, 1e-9) then'#13#10 +
        '  DoStuff;'#13#10 +
        ''#13#10 +
        '// SameValue accepts a tolerance; IsZero(x) is shorthand for'#13#10 +
        '// SameValue(x, 0). Both live in System.Math.';
    end;

    fkExceptInDestructor:
    begin
      Result.Description := _('Raise inside destructor without try/except - cleanup is aborted');
      Result.Before :=
        'destructor TFoo.Destroy;'#13#10 +
        'begin'#13#10 +
        '  FList.Free;'#13#10 +
        '  if Bad then'#13#10 +
        '    raise EInvalidOp.Create(''oops'');     // <- inherited Destroy never runs'#13#10 +
        '  inherited;'#13#10 +
        'end;';
      Result.After :=
        'destructor TFoo.Destroy;'#13#10 +
        'begin'#13#10 +
        '  try'#13#10 +
        '    FList.Free;'#13#10 +
        '    if Bad then raise EInvalidOp.Create(''oops'');'#13#10 +
        '  except'#13#10 +
        '    Log(''cleanup error - propagating'');'#13#10 +
        '    // Optional: raise; - aber dann ist inherited weiter offen'#13#10 +
        '  end;'#13#10 +
        '  inherited;'#13#10 +
        'end;';
    end;

    fkUnusedPrivateMethod:
    begin
      Result.Description := _('Private method has no caller in the unit - dead code');
      Result.Before :=
        'TFoo = class'#13#10 +
        'private'#13#10 +
        '  procedure HelperA;       // <- never called'#13#10 +
        'public'#13#10 +
        '  procedure DoStuff;'#13#10 +
        'end;';
      Result.After :=
        '// Either delete the method, or call it from DoStuff /'#13#10 +
        '// another method to make the dependency explicit:'#13#10 +
        'TFoo = class'#13#10 +
        'public'#13#10 +
        '  procedure DoStuff;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// If kept for RTTI/published reflection, mark with'#13#10 +
        '// // noinspection UnusedPrivateMethod';
    end;

    fkCanBeClassMethod:
    begin
      Result.Description := _('Method never accesses Self or instance fields - could be `class function`');
      Result.Before :=
        'TMath = class'#13#10 +
        '  function Add(A, B: Integer): Integer;     // instance method'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'function TMath.Add(A, B: Integer): Integer;'#13#10 +
        'begin'#13#10 +
        '  Result := A + B;          // only uses params, no Self'#13#10 +
        'end;';
      Result.After :=
        'TMath = class'#13#10 +
        '  class function Add(A, B: Integer): Integer; static;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'class function TMath.Add(A, B: Integer): Integer;'#13#10 +
        'begin'#13#10 +
        '  Result := A + B;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Caller: TMath.Add(1, 2)   // no instance needed';
    end;

    fkBoolAlwaysTrue:
    begin
      Result.Description := _('Boolean comparison is always true / always false');
      Result.Before :=
        'if Length(s) >= 0 then       // <- Length is never negative -> always True'#13#10 +
        '  DoStuff;'#13#10 +
        ''#13#10 +
        'if Length(s) < 0 then        // <- always False; dead code in branch'#13#10 +
        '  DoOtherStuff;';
      Result.After :=
        '// Wahrscheinlich wolltest du das schreiben:'#13#10 +
        'if Length(s) > 0 then DoStuff;       // non-empty check'#13#10 +
        'if Length(s) = 0 then DoOtherStuff;  // empty check';
    end;

    fkConstantReturn:
    begin
      Result.Description := _('Function always returns the same literal on every code path');
      Result.Before :=
        'function GetTimeout: Integer;'#13#10 +
        'begin'#13#10 +
        '  if SlowMode then'#13#10 +
        '    Result := 30'#13#10 +
        '  else'#13#10 +
        '    Result := 30;          // <- alle Pfade -> immer 30'#13#10 +
        'end;';
      Result.After :=
        'const DEFAULT_TIMEOUT = 30;'#13#10 +
        ''#13#10 +
        'function GetTimeout: Integer;'#13#10 +
        'begin'#13#10 +
        '  Result := DEFAULT_TIMEOUT;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// oder: die Konstante direkt am Aufrufer nutzen,'#13#10 +
        '// die Function komplett entfernen.';
    end;

    fkHardcodedString:
    begin
      Result.Description := _('User-visible string is hardcoded - move to resourcestring / i18n');
      Result.Before :=
        'Form1.Caption := ''Mein Programm'';        // not translatable'#13#10 +
        'Button1.Hint  := ''Klick mich'';'#13#10 +
        'ShowMessage(''Daten gespeichert'');';
      Result.After :=
        'resourcestring'#13#10 +
        '  SAppCaption = ''Mein Programm'';'#13#10 +
        '  SBtnHint    = ''Klick mich'';'#13#10 +
        '  SSavedMsg   = ''Daten gespeichert'';'#13#10 +
        ''#13#10 +
        'Form1.Caption := SAppCaption;'#13#10 +
        'Button1.Hint  := SBtnHint;'#13#10 +
        'ShowMessage(SSavedMsg);'#13#10 +
        ''#13#10 +
        '// oder ueber dxgettext: _(''Mein Programm'')';
    end;

    fkMissingOverride:
    begin
      Result.Description := _('Method shadows a virtual parent method - add `override` directive');
      Result.Before :=
        'TBase = class'#13#10 +
        '  procedure DoWork; virtual;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'TDerived = class(TBase)'#13#10 +
        '  procedure DoWork;          // <- shadows TBase.DoWork (W1010)'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Base := Derived;'#13#10 +
        '// Base.DoWork;              // -> calls TBase.DoWork, not TDerived';
      Result.After :=
        'TDerived = class(TBase)'#13#10 +
        '  procedure DoWork; override;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Now Base.DoWork dispatches polymorphically to TDerived.DoWork.'#13#10 +
        '// Alternative: if the shadowing is intentional, use `reintroduce`.';
    end;

    fkBooleanParam:
    begin
      Result.Description := _('Boolean parameter drives internal branching - consider two methods with descriptive names');
      Result.Before :=
        'procedure SendNotification(const Msg: string; IsError: Boolean);'#13#10 +
        'begin'#13#10 +
        '  if IsError then Notify(Msg, clRed) else Notify(Msg, clBlack);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Caller: SendNotification(s, True);  // True = ???';
      Result.After :=
        'procedure SendErrorNotification(const Msg: string);'#13#10 +
        'begin Notify(Msg, clRed); end;'#13#10 +
        ''#13#10 +
        'procedure SendInfoNotification(const Msg: string);'#13#10 +
        'begin Notify(Msg, clBlack); end;'#13#10 +
        ''#13#10 +
        '// Caller: SendErrorNotification(s);   // intent obvious';
    end;

    fkGodClass:
    begin
      Result.Description := _('Class has too many methods or fields - split into focused units');
      Result.Before :=
        'TUiController = class             // 60 methods, 80 fields'#13#10 +
        '  FToolbar: ...;'#13#10 +
        '  FFilters: ...;'#13#10 +
        '  FGrid: ...;'#13#10 +
        '  // ... 50 more F* fields ...'#13#10 +
        '  procedure BuildToolbar;'#13#10 +
        '  procedure FilterChange(...);'#13#10 +
        '  procedure GridDrawCell(...);'#13#10 +
        '  // ... 50 more methods - mixing concerns'#13#10 +
        'end;';
      Result.After :=
        '// Extract concerns into focused records / helper classes:'#13#10 +
        'TToolbarSlots = record FBtnRun, FBtnStop, ...: TButton; end;'#13#10 +
        'TFilterController = class ... end;'#13#10 +
        'TGridRenderer    = class ... end;'#13#10 +
        ''#13#10 +
        'TUiController = class                // now ~10 methods, ~5 fields'#13#10 +
        '  FToolbar: TToolbarSlots;'#13#10 +
        '  FFilter:  TFilterController;'#13#10 +
        '  FGrid:    TGridRenderer;'#13#10 +
        '  procedure Setup;'#13#10 +
        'end;';
    end;

    fkUnpairedLock:
    begin
      Result.Description := _('Lock acquired without try/finally - an exception leaks the lock and deadlocks the next caller');
      Result.Before :=
        'FLocker.Lock;'#13#10 +
        'DoStuff;        // <- exception here'#13#10 +
        'FLocker.UnLock; // <- never reached, lock stays held forever'#13#10 +
        ''#13#10 +
        '// EnterCriticalSection / TSynLocker.Lock / TMonitor.Enter:'#13#10 +
        '// any exception between acquire and release deadlocks the app.'#13#10 +
        '// Next thread to touch the same lock waits forever.';
      Result.After :=
        'FLocker.Lock;'#13#10 +
        'try'#13#10 +
        '  DoStuff;'#13#10 +
        'finally'#13#10 +
        '  FLocker.UnLock; // always executes'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// EnterCriticalSection -> LeaveCriticalSection'#13#10 +
        '// TMonitor.Enter      -> TMonitor.Exit'#13#10 +
        '// TSynLocker.Lock     -> TSynLocker.UnLock'#13#10 +
        '// Always pair acquire/release in a try/finally block.';
    end;

    fkMoveSizeOfPointer:
    begin
      Result.Description := _('Move / FillChar uses SizeOf(pointer-type) - copies only 4/8 bytes, not the target buffer');
      Result.Before :=
        'var Buf: array[0..255] of Byte;'#13#10 +
        '    P:   PByte;'#13#10 +
        'P := @Buf;'#13#10 +
        'Move(Src^, P^, SizeOf(PByte));    // <- copies 8 bytes (pointer), not 256'#13#10 +
        'FillChar(P^, SizeOf(PInteger), 0); // <- zeroes 8 bytes, not the integer'#13#10 +
        ''#13#10 +
        '// Pattern: SizeOf(PXxx) returns the size of the POINTER (4/8 bytes),'#13#10 +
        '// not the size of the pointed-to data. Almost always a bug - the'#13#10 +
        '// caller meant SizeOf(Xxx) or Length(Buf) or a count*ElementSize.';
      Result.After :=
        '// Option 1: take SizeOf of the value type, not the pointer type.'#13#10 +
        'Move(Src^, P^, SizeOf(Byte) * Count);   // explicit count'#13#10 +
        'FillChar(P^, SizeOf(Integer), 0);       // zero the integer'#13#10 +
        ''#13#10 +
        '// Option 2: use a typed variable and let the compiler size it.'#13#10 +
        'var V: Integer;'#13#10 +
        'FillChar(V, SizeOf(V), 0);              // safe - matches V''s size'#13#10 +
        ''#13#10 +
        '// Option 3: copy whole arrays via the array variable, not the pointer.'#13#10 +
        'Move(Src[0], Buf[0], Length(Buf));      // copies all elements';
    end;

    fkGetMemWithoutFreeMem:
    begin
      Result.Description := _('GetMem / AllocMem without try/finally - an exception leaks the heap buffer');
      Result.Before :=
        'var P: PByte;'#13#10 +
        'begin'#13#10 +
        '  GetMem(P, 1024);'#13#10 +
        '  FillBuffer(P);    // <- exception here'#13#10 +
        '  ProcessBuffer(P); // <- never reached'#13#10 +
        '  FreeMem(P);       // <- never reached, buffer leaked'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// GetMem / AllocMem / ReallocMem allocate raw heap memory.'#13#10 +
        '// Any exception between allocation and FreeMem leaks the'#13#10 +
        '// buffer permanently. mORMot uses this idiom for high-'#13#10 +
        '// performance buffer manipulation in core/ - every'#13#10 +
        '// missing try/finally is a production leak.';
      Result.After :=
        'var P: PByte;'#13#10 +
        'begin'#13#10 +
        '  GetMem(P, 1024);'#13#10 +
        '  try'#13#10 +
        '    FillBuffer(P);'#13#10 +
        '    ProcessBuffer(P);'#13#10 +
        '  finally'#13#10 +
        '    FreeMem(P); // always executes'#13#10 +
        '  end;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// The allocation line goes OUTSIDE the try.'#13#10 +
        '// If GetMem itself fails (out-of-memory), there is'#13#10 +
        '// no buffer to free.'#13#10 +
        ''#13#10 +
        '// Pairings:'#13#10 +
        '//   GetMem / AllocMem / ReallocMem  -> FreeMem'#13#10 +
        '//   New(p)                           -> Dispose(p)'#13#10 +
        '//   StrAlloc                         -> StrDispose';
    end;

    fkSetLengthAppendInLoop:
    begin
      Result.Description := _('SetLength growing by 1 inside a loop - O(n^2) reallocation; grow once before the loop');
      Result.Before :=
        'var i: Integer;'#13#10 +
        '    Dest: TArray<Integer>;'#13#10 +
        'begin'#13#10 +
        '  for i := 0 to Source.Count - 1 do'#13#10 +
        '  begin'#13#10 +
        '    SetLength(Dest, Length(Dest) + 1); // <- realloc EVERY iteration'#13#10 +
        '    Dest[High(Dest)] := Source[i];'#13#10 +
        '  end;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Realloc on every iteration copies n*(n+1)/2 elements'#13#10 +
        '// instead of n. At 10_000 items: 50 million ops vs. 10_000'#13#10 +
        '// - 5000x slower. Quadratic scaling trap that only shows'#13#10 +
        '// up under real-world load.';
      Result.After :=
        '// Option 1: grow once when the size is known.'#13#10 +
        'SetLength(Dest, Source.Count);'#13#10 +
        'for i := 0 to Source.Count - 1 do'#13#10 +
        '  Dest[i] := Source[i];'#13#10 +
        ''#13#10 +
        '// Option 2: grow in blocks if the final size is unknown.'#13#10 +
        'const BLOCK = 64;'#13#10 +
        'Used := 0;'#13#10 +
        'SetLength(Dest, BLOCK);'#13#10 +
        'while More do'#13#10 +
        'begin'#13#10 +
        '  if Used >= Length(Dest) then'#13#10 +
        '    SetLength(Dest, Length(Dest) + BLOCK); // doubling/blocked'#13#10 +
        '  Dest[Used] := NextItem;'#13#10 +
        '  Inc(Used);'#13#10 +
        'end;'#13#10 +
        'SetLength(Dest, Used); // trim to actual size'#13#10 +
        ''#13#10 +
        '// Option 3: use TList<T> which amortizes growth internally.';
    end;

    fkPointerArithmeticOnString:
    begin
      Result.Description := _('PChar(s) arithmetic without empty-check - PChar('''') is nil, arithmetic triggers AV');
      Result.Before :=
        'procedure Foo(const s: string);'#13#10 +
        'var p: PChar;'#13#10 +
        'begin'#13#10 +
        '  p := PChar(s) + 5;       // <- if s='''' then PChar(s) = nil'#13#10 +
        '  while p^ <> #0 do Inc(p);// <- AV at address $00000005'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Delphi optimizes PChar('''') to NIL (not a pointer to #0).'#13#10 +
        '// Any arithmetic on the result without a prior empty-check'#13#10 +
        '// is a latent Access Violation: nil + 5 is dereferenced'#13#10 +
        '// as a real address. mORMot internals avoid this with'#13#10 +
        '// explicit `if s <> '''' then` guards; user code copying'#13#10 +
        '// the idiom often skips the guard.';
      Result.After :=
        '// Option 1: empty-check before arithmetic.'#13#10 +
        'procedure Foo(const s: string);'#13#10 +
        'var p: PChar;'#13#10 +
        'begin'#13#10 +
        '  if s = '''' then Exit;'#13#10 +
        '  p := PChar(s) + 5;'#13#10 +
        '  while p^ <> #0 do Inc(p);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Option 2: length-check makes the offset safe explicitly.'#13#10 +
        'if Length(s) >= 6 then'#13#10 +
        '  p := PChar(s) + 5;'#13#10 +
        ''#13#10 +
        '// Option 3: use higher-level helpers that take a string'#13#10 +
        '// (Copy / TStringHelper.Substring) so PChar arithmetic'#13#10 +
        '// stays out of the call site entirely.';
    end;

    fkEmptyOnHandler:
    begin
      Result.Description := _('Typed exception handler is empty - swallows a specific exception silently');
      Result.Before :=
        'try'#13#10 +
        '  RiskyCall;'#13#10 +
        'except'#13#10 +
        '  on E: EDatabaseError do ;       // <- DB error gone, no log'#13#10 +
        '  on E: EFileNotFound do'#13#10 +
        '  begin'#13#10 +
        '  end;                            // <- equally silent'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Worse than `except end` because the typed `on E:`'#13#10 +
        '// gives the impression of deliberate handling. The'#13#10 +
        '// failure becomes invisible in production - no log,'#13#10 +
        '// no UI feedback, no telemetry.';
      Result.After :=
        'try'#13#10 +
        '  RiskyCall;'#13#10 +
        'except'#13#10 +
        '  on E: EDatabaseError do'#13#10 +
        '  begin'#13#10 +
        '    Logger.Error(''DB failed: %s'', [E.Message]);'#13#10 +
        '    raise; // or specific recovery'#13#10 +
        '  end;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// At minimum: log. Better: handle the case explicitly'#13#10 +
        '// (recovery, fallback, user message) and re-raise if'#13#10 +
        '// nothing can be done locally.'#13#10 +
        ''#13#10 +
        '// If silent swallowing is genuinely correct (cleanup'#13#10 +
        '// path, optional resource), say so with a comment so'#13#10 +
        '// the next reader does not "fix" it.';
    end;

    fkStringFromPointer:
    begin
      Result.Description := _('String cast from raw pointer assumes a null-terminator - heap overread if missing');
      Result.Before :=
        'procedure Foo(Buf: PByte);'#13#10 +
        'var s: string;'#13#10 +
        'begin'#13#10 +
        '  s := string(Buf);              // reads until next #0 -'#13#10 +
        '                                 // may walk past the buffer end'#13#10 +
        '  s := UTF8String(SomePointer);  // same bug, UTF-8 flavor'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Delphi treats the PChar-style cast as null-terminated'#13#10 +
        '// and reads memory until the next #0. On a buffer without'#13#10 +
        '// a terminator this reads past the heap-block boundary -'#13#10 +
        '// silent heap overread, occasional AV.';
      Result.After :=
        '// Always pass an explicit length when constructing'#13#10 +
        '// a string from raw memory.'#13#10 +
        'SetString(s, PChar(Buf), Len);   // bounded by Len'#13#10 +
        ''#13#10 +
        '// For UTF-8:'#13#10 +
        'SetString(s, PAnsiChar(Buf), Len);'#13#10 +
        '// or UTF8DecodeToString(Buf, Len, s) for explicit decode'#13#10 +
        ''#13#10 +
        '// mORMot helpers like FastSetString / FastSetStringCp'#13#10 +
        '// take Length explicitly and avoid this trap.';
    end;

    fkInsecureCryptoAlgorithm:
    begin
      Result.Description := _('Weak/deprecated crypto algorithm in use');
      // noinspection InsecureCryptoAlgorithm
      // FP: 'MD5'/'tls10' im Hint-Beispiel als BEFORE-Code; kein realer Crypto-Use.
      Result.Before :=
        'algo := ''MD5'';                       // <- broken since 2004'#13#10 +
        'Hash := THashMD5.GetHashString(Input); // <- wrapper class'#13#10 +
        ''#13#10 +
        '// SSL/TLS context:'#13#10 +
        'Client.SecureProtocols := [tls10, tls11]; // <- deprecated'#13#10 +
        ''#13#10 +
        '// Why this is dangerous:'#13#10 +
        '//   MD5  - practical collisions, not safe for signatures'#13#10 +
        '//   SHA1 - chosen-prefix collision (SHAttered 2017)'#13#10 +
        '//   DES  - 56-bit key, brute-forceable'#13#10 +
        '//   3DES - Sweet32 CBC collision (CVE-2016-2183)'#13#10 +
        '//   RC4  - statistical biases, prohibited by RFC 7465'#13#10 +
        '//   TLS 1.0/1.1 - RFC 8996 deprecated (BEAST, POODLE)'#13#10 +
        '//   SSLv3 - POODLE (CVE-2014-3566)';
      Result.After :=
        'algo := ''SHA256'';                    // collision-resistant'#13#10 +
        'Hash := THashSHA2.GetHashString(Input);'#13#10 +
        ''#13#10 +
        '// For password hashing prefer Argon2 / bcrypt / scrypt -'#13#10 +
        '// SHA-256 alone is still too fast for brute-force defence.'#13#10 +
        ''#13#10 +
        '// Symmetric encryption: AES-GCM or AES-CCM (authenticated).'#13#10 +
        '// TLS: minimum 1.2, prefer 1.3:'#13#10 +
        'Client.SecureProtocols := [tls12, tls13];';
    end;

    fkUnusedRoutine:
    begin
      Result.Description := _('Top-level routine appears unused (dead code)');
      Result.Before :=
        'implementation'#13#10 +
        ''#13#10 +
        'procedure InternalHelper;   // <- never called from anywhere'#13#10 +
        'begin'#13#10 +
        '  WriteLn(''hi'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'procedure DoWork;'#13#10 +
        'begin'#13#10 +
        '  // ... no call to InternalHelper here ...'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        'end.'#13#10 +
        ''#13#10 +
        '// Single-file scope: cross-unit callers of interface-section'#13#10 +
        '// routines are NOT tracked, so this rule only fires for routines'#13#10 +
        '// that are implementation-only (no forward declaration).';
      Result.After :=
        '// Option 1: delete the routine.'#13#10 +
        ''#13#10 +
        '// Option 2: call it from somewhere - the call site that you'#13#10 +
        '// forgot during the refactoring.'#13#10 +
        ''#13#10 +
        '// Option 3: promote it to the interface section if it is meant'#13#10 +
        '// to be exported - this rule then steps back automatically.'#13#10 +
        'interface'#13#10 +
        '  procedure InternalHelper;'#13#10 +
        'implementation'#13#10 +
        '  procedure InternalHelper;'#13#10 +
        '  begin'#13#10 +
        '    WriteLn(''hi'');'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        '// Option 4: suppress for RTTI / attribute / plugin-loaded routines:'#13#10 +
        '// noinspection UnusedRoutine'#13#10 +
        'procedure CalledByPluginLoader;'#13#10 +
        'begin'#13#10 +
        '  ...'#13#10 +
        'end;';
    end;

    fkCommandInjection:
    begin
      Result.Description := _('Shell API called with string concatenation in arguments');
      Result.Before :=
        'ShellExecute(0, ''open'','#13#10 +
        '  PChar(''cmd /c '' + UserInput),     // <- injection vector'#13#10 +
        '  nil, nil, SW_SHOW);'#13#10 +
        ''#13#10 +
        '// If UserInput is "harmless & rmdir /s /q C:\Data", the shell'#13#10 +
        '// parses the & as a command separator and runs both commands.'#13#10 +
        ''#13#10 +
        '// CWE-78: Improper Neutralization of Special Elements used'#13#10 +
        '// in an OS Command (''OS Command Injection'').';
      Result.After :=
        '// Option 1: Hand args via the structured array (no concat).'#13#10 +
        'var SEI: TShellExecuteInfo;'#13#10 +
        'FillChar(SEI, SizeOf(SEI), 0);'#13#10 +
        'SEI.cbSize     := SizeOf(SEI);'#13#10 +
        'SEI.lpVerb     := ''open'';'#13#10 +
        'SEI.lpFile     := ''cmd.exe'';'#13#10 +
        'SEI.lpParameters := PChar(''/c '' + SafeWhitelistedCommand);'#13#10 +
        'SEI.nShow      := SW_SHOW;'#13#10 +
        'ShellExecuteEx(@SEI);'#13#10 +
        ''#13#10 +
        '// Option 2: whitelist user input first.'#13#10 +
        'if MatchesWhitelist(UserInput) then'#13#10 +
        '  // ... proceed'#13#10 +
        'else'#13#10 +
        '  raise EArgumentException.Create(''Invalid command'');';
    end;

    fkPointerSubtraction:
    begin
      Result.Description := _('Cardinal/Integer subtraction on pointers truncates upper 32 bits on Win64');
      Result.Before :=
        'procedure Foo(P1, P2: Pointer);'#13#10 +
        'var Diff: Integer;'#13#10 +
        'begin'#13#10 +
        '  Diff := Cardinal(P1) - Cardinal(P2);   // <- Win64 truncation'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// On Win64 a Pointer is 64-bit, but Cardinal / Integer /'#13#10 +
        '// LongWord / LongInt are 32-bit. The cast drops the upper'#13#10 +
        '// four bytes of the address. The resulting difference is'#13#10 +
        '// wrong whenever the allocator hands out high addresses -'#13#10 +
        '// works on Win32, intermittently wrong on Win64.';
      Result.After :=
        'procedure Foo(P1, P2: Pointer);'#13#10 +
        'var Diff: NativeInt;            // 32 on Win32, 64 on Win64'#13#10 +
        'begin'#13#10 +
        '  Diff := PtrUInt(P1) - PtrUInt(P2);     // pointer-wide cast'#13#10 +
        '  // or NativeUInt for an unsigned result'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Pointer-width integer types in Delphi:'#13#10 +
        '//   NativeInt / PtrInt   - signed, pointer-sized'#13#10 +
        '//   NativeUInt / PtrUInt - unsigned, pointer-sized'#13#10 +
        '// Always use these for arithmetic on pointer addresses.';
    end;

    fkWithMultipleTargets:
    begin
      Result.Description := _('with statement names multiple targets - ambiguous member lookup');
      Result.Before :=
        'with Form1, List1 do'#13#10 +
        '  DoStuff;'#13#10 +
        ''#13#10 +
        '// Where does DoStuff come from? Form1 or List1? Whichever the'#13#10 +
        '// compiler picks today, a new method added to either object'#13#10 +
        '// silently changes the meaning tomorrow. Maintenance trap.'#13#10 +
        ''#13#10 +
        '// Renames (F2 / IDE refactor) miss these references because the'#13#10 +
        '// target object is not named at the call site.';
      Result.After :=
        '// Replace with explicit qualifications.'#13#10 +
        'Form1.DoStuff;        // intent obvious'#13#10 +
        'List1.Sort;'#13#10 +
        ''#13#10 +
        '// Or, if you really need a short alias, introduce a local var:'#13#10 +
        'var L: TList; F: TForm1;'#13#10 +
        'L := List1; F := Form1;'#13#10 +
        'F.DoStuff;'#13#10 +
        'L.Sort;'#13#10 +
        ''#13#10 +
        '// Rule of thumb: avoid with entirely. Code-reviews, refactoring'#13#10 +
        '// tools, and future readers all benefit from explicit receivers.';
    end;

    fkUninitVar:
    begin
      Result.Description := _('Local variable read before its first assignment - undefined value (garbage / AV)');
      Result.Before :=
        'procedure DoIt(N: Integer);'#13#10 +
        'var'#13#10 +
        '  Total: Integer;'#13#10 +
        'begin'#13#10 +
        '  if N > 0 then'#13#10 +
        '    Total := N * 2;'#13#10 +
        '  // N=0 oder N<0 -> Total NIE zugewiesen!'#13#10 +
        '  WriteLn(Total);    // <- liest Stack-Garbage'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Bei nicht-managed Typen (Integer, Boolean, Pointer, record,'#13#10 +
        '// class instance) startet die Variable mit undefiniertem Inhalt.'#13#10 +
        '// Lesen vor Schreiben liefert Garbage oder loest AV aus.';
      Result.After :=
        'procedure DoIt(N: Integer);'#13#10 +
        'var'#13#10 +
        '  Total: Integer;'#13#10 +
        'begin'#13#10 +
        '  Total := 0;        // <- explicit default vor jedem Read'#13#10 +
        '  if N > 0 then'#13#10 +
        '    Total := N * 2;'#13#10 +
        '  WriteLn(Total);    // safe: hat IMMER definierten Wert'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Alternativen:'#13#10 +
        '//   * Total := Default(Integer);'#13#10 +
        '//   * jeden if-Pfad zuweisen lassen (auch else)'#13#10 +
        '//   * FillChar(rec, SizeOf(rec), 0) fuer records'#13#10 +
        '//   * Managed-Typen (string, dynamic array) sind auto-init,'#13#10 +
        '//     hier nicht relevant.'#13#10 +
        ''#13#10 +
        '// Suppress mit: // noinspection UninitVar';
    end;

    fkUnusedSuppression:
    begin
      Result.Description := _('Suppression marker has no matching finding - probably stale after fix');
      Result.Before :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  // noinspection MemoryLeak'#13#10 +
        '  DoSomething;             // <- der zugehoerige Leak wurde gefixt,'#13#10 +
        'end;                       //    der Marker is jetzt Toter Code';
      Result.After :=
        'procedure Foo;'#13#10 +
        'begin'#13#10 +
        '  DoSomething;             // Marker geloescht - Code-Hygiene'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Stale-Suppression-Marker akkumulieren ueber Zeit und'#13#10 +
        '// verschleiern echte Befunde. Aufraeumen wie ungenutzten Code.';
    end;

  end;
end;

initialization
finalization
  TFixHintResolver.FCache.Free;

end.
