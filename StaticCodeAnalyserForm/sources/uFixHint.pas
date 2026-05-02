unit uFixHint;

// Loesungs-Hinweise pro Befund-Typ.
//
// Liefert pro TLeakFinding eine kurze Beschreibung sowie zwei Code-Beispiele
// (Vorher / Nachher). Wird sowohl vom IDE-Hilfe-Panel als auch vom Export
// (Jira / Clipboard / HTML) verwendet, daher in eigener Unit.

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
        Result.Description := 'Objekt erstellt, aber nie freigegeben (Speicherleck)';
        Result.Before :=
          'list := TStringList.Create;'#13#10 +
          'list.Add(''Eintrag'');'#13#10 +
          '// list.Free fehlt!'#13#10 +
          '// -> Speicherleck';
        Result.After :=
          'list := TStringList.Create;'#13#10 +
          'try'#13#10 +
          '  list.Add(''Eintrag'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list);'#13#10 +
          'end;';
      end
      else if Pos(' - R'#$FC'ckgabewert', Finding.MissingVar) > 0 then
      begin
        Result.Description := 'Funktionsr'#$FC'ckgabe wird nicht freigegeben';
        Result.Before :=
          '// Funktion gibt ein neues Objekt zur'#$FC'ck -'#13#10 +
          '// Aufrufer ist f'#$FC'r die Freigabe zust'#$E4'ndig.'#13#10 +
          ''#13#10 +
          'list := BuildList();'#13#10 +
          'list.Add(''x'');'#13#10 +
          '// list.Free fehlt!';
        Result.After :=
          'list := BuildList();'#13#10 +
          'try'#13#10 +
          '  list.Add(''x'');'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list);'#13#10 +
          'end;'#13#10 +
          ''#13#10 +
          '// Oder: Result := list;  (Ownership weitergeben)';
      end
      else
      begin
        Result.Description := 'Free liegt ausserhalb des finally-Blocks';
        Result.Before :=
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  other.Free;'#13#10 +
          'end;'#13#10 +
          'list.Free; // <- zu spaet!'#13#10 +
          '// Exception vor Free = Leck';
        Result.After :=
          'try'#13#10 +
          '  ...code...'#13#10 +
          'finally'#13#10 +
          '  FreeAndNil(list); // <- hier'#13#10 +
          '  other.Free;'#13#10 +
          'end;';
      end;

    fkEmptyExcept:
    begin
      Result.Description := 'Leerer except-Block verschluckt Exceptions';
      Result.Before :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  // leer'#13#10 +
        'end;'#13#10 +
        '// Fehler bleibt unsichtbar!';
      Result.After :=
        'try'#13#10 +
        '  DoSomething;'#13#10 +
        'except'#13#10 +
        '  on E: Exception do'#13#10 +
        '    LogError(E.Message);'#13#10 +
        '  // oder: raise;'#13#10 +
        'end;';
    end;

    fkSQLInjection:
    begin
      Result.Description := 'SQL-Befehl per "+" aufgebaut - SQL-Injection-Risiko';
      Result.Before :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM t'''#13#10 +
        '  + '' WHERE id = '' + Id;'#13#10 +
        ''#13#10 +
        '// Angreifer kann Id manipulieren!';
      Result.After :=
        'Query.SQL.Text :='#13#10 +
        '  ''SELECT * FROM t'''#13#10 +
        '  + '' WHERE id = :Id'';'#13#10 +
        'Query.ParamByName(''Id'')'#13#10 +
        '  .AsString := Id;';
    end;

    fkHardcodedSecret:
    begin
      Result.Description := 'Passwort / Token als Literal im Quellcode';
      Result.Before :=
        'FPassword := ''geheim123'';'#13#10 +
        'FToken    := ''sk-abc-xyz'';'#13#10 +
        ''#13#10 +
        '// Sichtbar im Quellcode,'#13#10 +
        '// Repository und Build-Logs!';
      Result.After :=
        '// Aus Konfigurationsdatei:'#13#10 +
        'FPassword := Ini.ReadString('#13#10 +
        '  ''Auth'', ''Password'', '''');'#13#10 +
        ''#13#10 +
        '// Oder Umgebungsvariable:'#13#10 +
        'FPassword := GetEnvironmentVariable(''APP_PWD'');';
    end;

    fkFormatMismatch:
    begin
      Result.Description := 'Format()-Platzhalter-Anzahl <> Argument-Anzahl';
      Result.Before :=
        '// 2 Platzhalter, 1 Argument'#13#10 +
        's := Format('#13#10 +
        '  ''%s ist %d Jahre alt'','#13#10 +
        '  [Name]); // <- Age fehlt!'#13#10 +
        ''#13#10 +
        '// Laufzeitfehler: EConvertError';
      Result.After :=
        '// 2 Platzhalter, 2 Argumente'#13#10 +
        's := Format('#13#10 +
        '  ''%s ist %d Jahre alt'','#13#10 +
        '  [Name, Age]); // <- korrekt'#13#10 +
        ''#13#10 +
        '// Tipp: %% fuer ein echtes %-Zeichen';
    end;

    fkFileReadError:
    begin
      Result.Description := 'Datei konnte nicht gelesen oder geparst werden';
      Result.Before :=
        '// Moegliche Ursachen:'#13#10 +
        '// - Unbekannte Datei-Kodierung'#13#10 +
        '// - Datei gesperrt / kein Lesezugriff'#13#10 +
        '// - Datei groesser als 5 MB'#13#10 +
        '// - Syntaxfehler beim Parsen';
      Result.After :=
        '// Loesungsansaetze:'#13#10 +
        '// - Datei in UTF-8 oder UTF-16 speichern'#13#10 +
        '// - Dateizugriff und Berechtigungen pruefen'#13#10 +
        '// - Sehr grosse oder generierte Dateien'#13#10 +
        '//   aus dem Projektpfad ausschliessen';
    end;

    fkNilDeref:
    begin
      Result.Description := 'Nil-Dereferenzierung: Zugriff auf moeglicherweise nil-Variable';
      Result.Before :=
        'obj := nil;'#13#10 +
        '// ... kein Create ...'#13#10 +
        'obj.DoSomething;  // EAccessViolation!';
      Result.After :=
        'obj := TFoo.Create;'#13#10 +
        'try'#13#10 +
        '  obj.DoSomething;'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(obj);'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Oder: if Assigned(obj) then obj.DoSomething;';
    end;

    fkMissingFinally:
    begin
      Result.Description := 'Create ohne try/finally: Exception kann Free verhindern';
      Result.Before :=
        'list := TStringList.Create;'#13#10 +
        'DoWork(list);   // Exception hier'#13#10 +
        'list.Free;      // wird nie erreicht!';
      Result.After :=
        'list := TStringList.Create;'#13#10 +
        'try'#13#10 +
        '  DoWork(list);'#13#10 +
        'finally'#13#10 +
        '  FreeAndNil(list); // immer ausgefuehrt'#13#10 +
        'end;';
    end;

    fkDivByZero:
    begin
      Result.Description := 'Division durch Null: EZeroDivide moeglich';
      Result.Before :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  Result := Sum div Count; // Count=0 -> EZeroDivide'#13#10 +
        'end;';
      Result.After :=
        'function Avg(Sum, Count: Integer): Double;'#13#10 +
        'begin'#13#10 +
        '  if Count = 0 then Exit(0);'#13#10 +
        '  Result := Sum div Count;'#13#10 +
        'end;';
    end;

    fkDeadCode:
    begin
      Result.Description := 'Toter Code: Anweisungen nach Exit/raise nie erreichbar';
      Result.Before :=
        'if Error then'#13#10 +
        'begin'#13#10 +
        '  raise Exception.Create(''Fehler'');'#13#10 +
        '  Cleanup;  // wird nie ausgefuehrt!'#13#10 +
        'end;';
      Result.After :=
        'if Error then'#13#10 +
        'begin'#13#10 +
        '  Cleanup;  // vor dem raise'#13#10 +
        '  raise Exception.Create(''Fehler'');'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Oder Cleanup in finally-Block auslagern';
    end;

    fkLongMethod:
    begin
      Result.Description := 'Methode zu lang - aufteilen erhoeht Lesbarkeit';
      Result.Before :=
        'procedure TFoo.DoEverything;'#13#10 +
        'begin'#13#10 +
        '  // 100+ Zeilen Logik...'#13#10 +
        '  // Validierung, Daten holen,'#13#10 +
        '  // verarbeiten, speichern, loggen'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.DoEverything;'#13#10 +
        'begin'#13#10 +
        '  if not Validate then Exit;'#13#10 +
        '  ProcessData;'#13#10 +
        '  Persist;'#13#10 +
        '  LogResult;'#13#10 +
        'end;';
    end;

    fkLongParamList:
    begin
      Result.Description := 'Zu viele Parameter - Parameter-Object verwenden';
      Result.Before :=
        'procedure CreateUser(AName, AEmail,'#13#10 +
        '  APhone, AAddress, ACity,'#13#10 +
        '  ACountry: string;'#13#10 +
        '  AAge: Integer);';
      Result.After :=
        'type'#13#10 +
        '  TUserData = record'#13#10 +
        '    Name, Email, Phone: string;'#13#10 +
        '    Age: Integer;'#13#10 +
        '  end;'#13#10 +
        ''#13#10 +
        'procedure CreateUser(const Data: TUserData);';
    end;

    fkMagicNumber:
    begin
      Result.Description := 'Magic Number - durch benannte Konstante ersetzen';
      Result.Before :=
        'if RetryCount > 100 then'#13#10 +
        '  raise Exception.Create(''Zu viele Versuche'');';
      Result.After :=
        'const'#13#10 +
        '  MAX_RETRIES = 100;'#13#10 +
        ''#13#10 +
        'if RetryCount > MAX_RETRIES then'#13#10 +
        '  raise Exception.Create(''Zu viele Versuche'');';
    end;

    fkDuplicateString:
    begin
      Result.Description := 'String-Literal mehrfach - als Konstante extrahieren';
      Result.Before :=
        'Logger.Warn(''Datenbank-Verbindung verloren'');'#13#10 +
        '// ... 30 Zeilen spaeter ...'#13#10 +
        'Logger.Error(''Datenbank-Verbindung verloren'');';
      Result.After :=
        'const'#13#10 +
        '  MSG_DB_LOST = ''Datenbank-Verbindung verloren'';'#13#10 +
        ''#13#10 +
        'Logger.Warn(MSG_DB_LOST);'#13#10 +
        'Logger.Error(MSG_DB_LOST);';
    end;

    fkDuplicateBlock:
    begin
      Result.Description := 'Mehrere identische Code-Bloecke - in Methode extrahieren';
      Result.Before :=
        '// in TFoo.LoadCustomer:'#13#10 +
        'try Conn.Open;'#13#10 +
        '  Logger.Info(''Loading...'');'#13#10 +
        '  Q.SQL.Text := ''SELECT...'';'#13#10 +
        '  ...'#13#10 +
        '// gleicher Block in TFoo.LoadOrder, TFoo.LoadInvoice ...';
      Result.After :=
        'procedure TFoo.RunQuery(const ASql: string);'#13#10 +
        'begin'#13#10 +
        '  Conn.Open;'#13#10 +
        '  Logger.Info(''Loading...'');'#13#10 +
        '  Q.SQL.Text := ASql;'#13#10 +
        '  ...'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Aufrufer: RunQuery(''SELECT...'');';
    end;

    fkHardcodedPath:
    begin
      Result.Description := 'Hardkodierter Pfad - aus Konfiguration laden';
      Result.Before :=
        'LogFile := ''C:\Logs\app.log'';'#13#10 +
        '// Laeuft nur auf einem Rechner!';
      Result.After :=
        'LogFile := IncludeTrailingPathDelimiter('#13#10 +
        '  TPath.GetDocumentsPath) + ''app.log'';'#13#10 +
        ''#13#10 +
        '// Oder aus Ini/Umgebungsvariable laden';
    end;

    fkDebugOutput:
    begin
      Result.Description := 'Debug-Ausgabe in Produktionscode';
      Result.Before :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  ShowMessage(''Wert: '' + IntToStr(X));'#13#10 +
        '  // wahrscheinlich vergessen!'#13#10 +
        'end;';
      Result.After :=
        'procedure TFoo.Bar;'#13#10 +
        'begin'#13#10 +
        '  Logger.Debug(''Wert: %d'', [X]);'#13#10 +
        '  // bzw. ganz entfernen wenn'#13#10 +
        '  // nicht mehr benoetigt'#13#10 +
        'end;';
    end;

    fkDeepNesting:
    begin
      Result.Description := 'Zu tiefe Verschachtelung - Early-Exit oder Methoden-Extraktion';
      Result.Before :=
        'if A then'#13#10 +
        '  if B then'#13#10 +
        '    if C then'#13#10 +
        '      if D then'#13#10 +
        '        if E then'#13#10 +
        '          DoIt;';
      Result.After :=
        'if not A then Exit;'#13#10 +
        'if not B then Exit;'#13#10 +
        'if not C then Exit;'#13#10 +
        'if not D then Exit;'#13#10 +
        'if not E then Exit;'#13#10 +
        'DoIt;';
    end;

    fkUnusedUses:
    begin
      Result.Description := 'Uses-Eintrag wird moeglicherweise nicht benoetigt';
      Result.Before :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.IniFiles,   // <- kein TIniFile im Code?'#13#10 +
        '  System.Classes;'#13#10 +
        ''#13#10 +
        '// Kompilierzeit + Laufzeit-Overhead'#13#10 +
        '// durch ungenutzte Abhaengigkeiten';
      Result.After :=
        'uses'#13#10 +
        '  System.SysUtils,'#13#10 +
        '  System.Classes;    // nur benoetigte Units'#13#10 +
        ''#13#10 +
        '// Tipp: Compiler-Hint [H2189]'#13#10 +
        '// "Unit X implicitly uses Y"'#13#10 +
        '// zeigt echte Abhaengigkeiten';
    end;

    fkTodoComment:
    begin
      Result.Description := 'Offener Marker im Kommentar - vor Release abarbeiten';
      Result.Before :=
        '// TODO: Tabelle persistieren'#13#10 +
        '// FIXME: race condition bei parallelem Save'#13#10 +
        '// HACK: workaround fuer Bug #4711'#13#10 +
        ''#13#10 +
        '// Marker bleiben sonst Jahre stehen';
      Result.After :=
        '// Variante 1: Aufgabe erledigen und Marker entfernen'#13#10 +
        ''#13#10 +
        '// Variante 2: in Issue-Tracker uebernehmen,'#13#10 +
        '// im Code referenzieren:'#13#10 +
        '// see JIRA-1234';
    end;

    fkEmptyMethod:
    begin
      Result.Description := 'Methodenrumpf ist leer - vergessener Stub oder unbeabsichtigt?';
      Result.Before :=
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Aufrufer denkt es passiert was -'#13#10 +
        '// passiert aber nichts.';
      Result.After :=
        '// Variante 1: Implementieren'#13#10 +
        'procedure TFoo.DoStuff;'#13#10 +
        'begin'#13#10 +
        '  FList.Sort;'#13#10 +
        'end;'#13#10 +
        ''#13#10 +
        '// Variante 2: Wenn als Hook gedacht,'#13#10 +
        '// virtual deklarieren:'#13#10 +
        '// procedure DoStuff; virtual;';
    end;

  end;
end;

end.
