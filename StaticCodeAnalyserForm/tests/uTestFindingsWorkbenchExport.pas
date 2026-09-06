unit uTestFindingsWorkbenchExport;

// Vertragstests der Funde-Export-VARIANTE 2 (uFindingsWorkbenchExport,
// Nutzerauftrag 07.09.): Workbench-Architektur der Detektor-Info-Seite
// auf dem Scan-Bericht. Kernvertraege: ein tbody je Fund, Regel-Doku
// DEDUPLIZIERT (ein Template je vorkommender Regel - egal wie viele
// Funde sie hat), Suchblob AnsiLowerCase, Zeilenbudget mit Banner,
// UTF-8-BOM, Drawer-/JS-Geruest samt Init-Aufrufen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DUnitX.TestFramework,
  uSCAConsts, uMethodd12;

type
  [TestFixture]
  TTestFindingsWorkbenchExport = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
    function Render(Findings: TObjectList<TLeakFinding>;
      const ABaseDir: string = ''; AMaxRows: Integer = -1): string;
  public
    [Test] procedure OneTbodyPerFinding_TemplatesDeduplicated;
    [Test] procedure WorkbenchScaffolding_WiredCompletely;
    [Test] procedure SearchBlob_IsAnsiLowered;
    [Test] procedure MaxRows_TruncatesWithBanner_TilesKeepTotals;
    [Test] procedure FileReadError_NeutralBadgeAndOwnRank;
    [Test] procedure Run_WritesUtf8WithBom;
    [Test] procedure FindingFields_AreHtmlEscaped;
    [Test] procedure DataCopy_CarriesRealNewlines_NoBrTokens;
  end;

implementation

// noinspection-file DuplicateString, LargeClass
// Fixture-Ausnahme des Profils: HTML-Anker ('</template>', 'tpl-')
// wiederholen sich als Pruefgegenstand bewusst variiert.

uses
  System.IOUtils,
  uFindingsWorkbenchExport, uRuleCatalog,
  uExportHtml; // HtmlEscape - Erwartungsbau des data-copy-Vertrags

function TTestFindingsWorkbenchExport.MakeFinding(Kind: TFindingKind;
  const Path: string; Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName   := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MissingVar := Msg;
  Result.MethodName := 'TestMethod';
end;

function TTestFindingsWorkbenchExport.Render(
  Findings: TObjectList<TLeakFinding>;
  const ABaseDir: string; AMaxRows: Integer): string;
begin
  Result := TFindingsWorkbenchExport.BuildHtml(Findings, ABaseDir,
    AMaxRows);
end;

procedure TTestFindingsWorkbenchExport.OneTbodyPerFinding_TemplatesDeduplicated;
// DER V2-Kern: drei Funde, davon zwei derselben Regel -> drei tbodies,
// aber nur ZWEI Regel-Templates. In der V1 stuende die Regel-Doku
// dreimal im Dokument.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  MetaLeak : TRuleMeta;
  MetaDbg  : TRuleMeta;

  function Vorkommen(const Teil: string): Integer;
  var
    P : Integer;
  begin
    Result := 0;
    P := Pos(Teil, Html);
    while P > 0 do
    begin
      Inc(Result);
      P := Pos(Teil, Html, P + 1);
    end;
  end;

begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a not freed'));
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\B.pas', 20, 'b not freed'));
    Findings.Add(MakeFinding(fkDebugOutput, 'src\A.pas', 30, 'WriteLn'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  MetaLeak := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  MetaDbg  := TRuleCatalog.GetRule(fkDebugOutput, 'de');
  Assert.AreEqual<Integer>(3, Vorkommen('<tbody data-rid="'),
    'drei Funde muessen drei tbodies ergeben');
  Assert.AreEqual<Integer>(2,
    Vorkommen('<tbody data-rid="' + MetaLeak.ID + '"'),
    'beide MemoryLeak-Funde haengen an derselben Regel-ID');
  Assert.AreEqual<Integer>(1,
    Vorkommen('<template id="tpl-' + MetaLeak.ID + '">'),
    'Regel-Template MemoryLeak muss trotz zweier Funde EINMAL stehen');
  Assert.AreEqual<Integer>(1,
    Vorkommen('<template id="tpl-' + MetaDbg.ID + '">'),
    'Regel-Template DebugOutput fehlt');
  Assert.AreEqual<Integer>(2, Vorkommen('</template>'),
    'genau zwei Templates insgesamt (Deduplikation)');
  // Die Katalog-Abschnitte stehen im Template, nicht je Fund:
  Assert.AreEqual<Integer>(2, Vorkommen('<h3>Was wird erkannt?</h3>'),
    '"Was wird erkannt?" gehoert EINMAL je Regel-Template');
end;

procedure TTestFindingsWorkbenchExport.WorkbenchScaffolding_WiredCompletely;
// Chrome + JS-Geruest: Workbench-Kopf, Command-Bar, Chips (typ/sev/
// konf, KEIN prof - der Scan ist gelaufen), Kacheln, Drawer samt
// Fund-Kopf-Bauer, Tastatur, Deep-Link und die Init-AUFRUFE.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a not freed'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('--akzent:#1a5da6', Html) > 0,
    'Workbench-Tokens fehlen (uWorkbenchStyle nicht eingebunden)');
  Assert.IsTrue(Pos('<header class="kopf">', Html) > 0,
    'dunkler Workbench-Kopf fehlt');
  Assert.IsTrue(Pos('id="suche"', Html) > 0, 'Command-Bar-Suche fehlt');
  Assert.IsTrue(Pos('data-gruppe="typ"', Html) > 0, 'Typ-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="sev"', Html) > 0, 'Sev-Chips fehlen');
  Assert.IsTrue(Pos('data-gruppe="konf"', Html) > 0,
    'Konfidenz-Chips fehlen');
  Assert.AreEqual<Integer>(0, Pos('data-gruppe="prof"', Html),
    'Profil-Chips haben im Fund-Bericht nichts verloren');
  Assert.IsTrue(Pos('class="kachel"', Html) > 0,
    'Dashboard-Kacheln fehlen');
  Assert.IsTrue(Pos('<aside id="drawer" aria-label="Fund-Details">',
    Html) > 0, 'Drawer fehlt');
  Assert.IsTrue(Pos('function fundKopf(tb)', Html) > 0,
    'Fund-Kopf-Bauer fehlt (Ort/Detail/Hinweis im Drawer)');
  Assert.IsTrue(Pos('function oeffneDrawer(tb)', Html) > 0,
    'oeffneDrawer fehlt');
  Assert.IsTrue(Pos('korb.appendChild(fundKopf(tb));', Html) > 0,
    'Drawer setzt den Fund-Kopf nicht VOR das Regel-Template');
  Assert.IsTrue(Pos('ev.ctrlKey', Html) > 0, 'Strg+K fehlt');
  Assert.IsTrue(Pos('function deepLink()', Html) > 0, 'Deep-Link fehlt');
  Assert.IsTrue(Pos('suche();'#13#10'deepLink();', Html) > 0,
    'Init-Aufrufe fehlen (Definition allein filtert nichts)');
  Assert.IsTrue(Pos('id="leer"', Html) > 0, 'Empty-State fehlt');
end;

procedure TTestFindingsWorkbenchExport.SearchBlob_IsAnsiLowered;
// Wie Katalog und V1: der Blob muss Unicode-gesenkt sein, sonst sind
// Woerter mit grossen Umlauten in keiner Schreibweise findbar.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10,
      'PR'#$DC'FUNG offen'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('pr'#$FC'fung offen', Html) > 0,
    'Suchblob muss AnsiLowerCase nutzen (Umlaut-Senkung)');
  Assert.AreEqual<Integer>(0, Pos('PR'#$DC'FUNG offen',
    Copy(Html, Pos('data-search="', Html), 400)),
    'im Suchattribut darf der ungesenkte Text nicht stehen');
end;

procedure TTestFindingsWorkbenchExport.MaxRows_TruncatesWithBanner_TilesKeepTotals;
// Zeilenbudget-Vertrag der V2: Tabelle gekuerzt + Banner, aber die
// Funde-Kachel zaehlt weiterhin ALLE Funde.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  i        : Integer;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to 5 do
      Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', i,
        'x' + IntToStr(i)));
    Html := Render(Findings, '', 3);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Pos('id="gekuerzt"', Html) > 0,
    'Kuerzungsbanner fehlt');
  Assert.IsTrue(Pos('2 weitere Funde', Html) > 0,
    'Banner muss die Zahl der weggelassenen Funde nennen');
  Assert.IsTrue(
    Pos('<div class="zahl">5</div><div class="wofuer">Funde</div>',
      Html) > 0,
    'die Funde-Kachel zaehlt ALLE Funde, nicht die gerenderten');
end;

procedure TTestFindingsWorkbenchExport.FileReadError_NeutralBadgeAndOwnRank;
// Lesefehler sind kein Schweregrad der Skala: neutraler Badge,
// Sortier-Rang hinter den Hinweisen (Politik wie V1).
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, 'src\Kaputt.pas', 1,
      'read failed'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.IsTrue(
    Pos('<span class="badge typ ferr">Lesefehler</span>', Html) > 0,
    'Lesefehler brauchen den neutralen ferr-Badge');
  Assert.IsTrue(Pos('data-sev="3"', Html) > 0,
    'Lesefehler-Rang 3 (hinter lsHint) fehlt');
end;

procedure TTestFindingsWorkbenchExport.Run_WritesUtf8WithBom;
var
  Findings : TObjectList<TLeakFinding>;
  Fn       : string;
  Bytes    : TBytes;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Fn := TPath.Combine(TPath.GetTempPath,
      'sca-test-v2-' + TGUID.NewGuid.ToString + '.html');
    try
      TFindingsWorkbenchExport.Run(Findings, '', Fn);
      Bytes := TFile.ReadAllBytes(Fn);
    finally
      if TFile.Exists(Fn) then TFile.Delete(Fn);
    end;
  finally
    Findings.Free;
  end;
  Assert.IsTrue(Length(Bytes) > 3, 'Datei leer');
  Assert.AreEqual<Byte>($EF, Bytes[0], 'BOM-Byte 1');
  Assert.AreEqual<Byte>($BB, Bytes[1], 'BOM-Byte 2');
  Assert.AreEqual<Byte>($BF, Bytes[2], 'BOM-Byte 3');
end;

procedure TTestFindingsWorkbenchExport.FindingFields_AreHtmlEscaped;
// Skript-/Attribut-Sicherheit: boese Fund-Felder duerfen nirgends roh
// stehen (Datei, Methode, Detail landen in Zelle UND Suchattribut).
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Fnd      : TLeakFinding;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, 'src\<script>.pas', 10,
      '"boese" & <kaputt>');
    Fnd.MethodName := 'Do<Evil>';
    Findings.Add(Fnd);
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Assert.AreEqual<Integer>(0, Pos('<script>.pas', Html),
    'Dateiname mit Tag muss escaped sein');
  Assert.AreEqual<Integer>(0, Pos('Do<Evil>', Html),
    'Methodenname mit Tag muss escaped sein');
  Assert.AreEqual<Integer>(0, Pos('"boese" & <kaputt>', Html),
    'Detailtext muss escaped sein');
  Assert.IsTrue(Pos('Do&lt;Evil&gt;', Html) > 0,
    'escapter Methodenname fehlt - dann fehlt die Zeile selbst');
end;

procedure TTestFindingsWorkbenchExport.DataCopy_CarriesRealNewlines_NoBrTokens;
// Chargen-Review 07.09. (MAJOR): data-copy der Codekarten lief durch
// den Element-Escaper und trug '<br>'-Tokens statt Umbruechen - der
// Kopieren-Button schrieb Muell in die Zwischenablage. Vertrag jetzt:
// Umbrueche als '&#10;' im data-copy, waehrend der <pre>-INHALT
// weiter die '<br>'-Form des Element-Vertrags traegt.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Meta     : TRuleMeta;
  Erwartet : string;
begin
  Meta := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  Assert.IsTrue(Pos(#10, Meta.BadExample) > 0,
    'Vorbedingung: SCA001-Beispiel ist mehrzeilig');
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\A.pas', 10, 'a'));
    Html := Render(Findings);
  finally
    Findings.Free;
  end;
  Erwartet := StringReplace(TExporterHtml.HtmlEscape(Meta.BadExample),
    '<br>', '&#10;', [rfReplaceAll]);
  Assert.IsTrue(Pos('data-copy="' + Erwartet + '"', Html) > 0,
    'data-copy muss Umbrueche als &#10; tragen');
  Assert.AreEqual<Integer>(0,
    Pos('data-copy="' + TExporterHtml.HtmlEscape(Meta.BadExample) + '"',
      Html),
    'die alte <br>-Form darf nicht mehr emittiert werden');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingsWorkbenchExport);

end.
