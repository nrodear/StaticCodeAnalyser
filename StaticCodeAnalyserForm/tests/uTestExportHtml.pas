unit uTestExportHtml;

// Tests fuer TExporterHtml (Infrastructure/uExportHtml.pas).
// Fokus: FR-i18n-Unicode-Escapes (Bug Doku_06_CLI_LSP_Reporting.md #21).
// Delphi-Strings kennen kein Backslash-Escaping - ein '\\u00e9' im
// Pascal-Literal landet als Doppel-Backslash im generierten JS und wird
// dort zum literalen Text '\u00e9' statt zum Akzentzeichen.
// Strategie: Report in eine Temp-Datei schreiben, als UTF-8 zuruecklesen
// und den JS-I18N-Block auf korrekte Escapes pruefen (Datei-Harness,
// da TExporterHtml.Run direkt auf Datei schreibt).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts, uExportHtml;

type
  [TestFixture]
  TTestExportHtml = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
    function RenderReport: string;
  public
    // Fix-Test: FR-Block emittiert \uXXXX mit genau EINEM Backslash.
    [Test] procedure FrI18nEscapesHaveSingleBackslash;
    // TP-Gegenprobe: legitime JS-Escapes (\" fuer Anfuehrungszeichen im
    // JS-String) bleiben vom Fix unberuehrt.
    [Test] procedure JsQuoteEscapesStayIntact;
  end;

implementation

uses
  System.IOUtils;

function TTestExportHtml.MakeFinding(Kind: TFindingKind; const Path: string;
  Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName   := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MissingVar := Msg;
  Result.MethodName := 'TestMethod';
end;

function TTestExportHtml.RenderReport: string;
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 42, 'list1 not freed'));
    Fn := TPath.Combine(TPath.GetTempPath,
      'sca-test-html-' + TGUID.NewGuid.ToString + '.html');
    try
      TExporterHtml.Run(Findings, 'src\Foo.pas', Fn);
      Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
    finally
      if TFile.Exists(Fn) then
        TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportHtml.FrI18nEscapesHaveSingleBackslash;
var
  Html : string;
begin
  Html := RenderReport;
  // Positiv: FR-Uebersetzung mit einfachem Backslash-Escape vorhanden
  // ('\u00e9' ist hier ein 6-Zeichen-ASCII-Literal, kein Escape).
  Assert.IsTrue(Pos('M\u00e9thode', Html) > 0,
    'FR-I18N-Block muss "M\u00e9thode" mit einfachem Backslash enthalten');
  // Negativ: kein Doppel-Backslash vor uXXXX mehr im gesamten Report -
  // der wuerde im Browser als literaler Text "\u00e9" gerendert.
  Assert.AreEqual(0, Pos('\\u00e9', Html),
    'Doppel-Backslash-Escape \\u00e9 darf nicht mehr vorkommen');
  Assert.AreEqual(0, Pos('\\u00a0', Html),
    'Doppel-Backslash-Escape \\u00a0 darf nicht mehr vorkommen');
end;

procedure TTestExportHtml.JsQuoteEscapesStayIntact;
var
  Html : string;
begin
  Html := RenderReport;
  // Gegenprobe: \" (escaptes Anfuehrungszeichen IN einem JS-String) ist
  // ein legitimer Einfach-Backslash-Escape und muss erhalten bleiben -
  // der FR-i18n-Fix betraf ausschliesslich \\u vor 4 Hex-Ziffern.
  Assert.IsTrue(Pos('class=\"td-qf\"', Html) > 0,
    'Legitimes JS-Quote-Escape class=\"td-qf\" muss erhalten bleiben');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportHtml);

end.
