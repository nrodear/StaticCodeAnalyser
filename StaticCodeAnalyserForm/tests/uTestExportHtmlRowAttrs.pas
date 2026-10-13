unit uTestExportHtmlRowAttrs;

// Tests fuer TExporterHtml (Infrastructure/uExportHtml.pas), Review
// 2026-10-13: zwei Attribute der Fundzeile, die bis dahin kein Test
// deckte - data-qf (1 fuer Regeln mit Code-Aktion, Katalogfeld editorHelp,
// sonst 0) und data-line des Quellauszugs (normalisiert wie data-sort).
// Eigene Fixture neben uTestExportHtml (34 Vertragsfaelle in einer Klasse).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts, uExportHtml;

type
  [TestFixture]
  TTestExportHtmlRowAttrs = class
  strict private
    FDir : string;   // Temp-Verzeichnis fuer den Quellauszug
    function RenderFindings(Findings: TObjectList<TLeakFinding>): string;
    function AttrAfter(const AHtml, AAnchor, AAttr: string): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DataQf_EditorHelpKind_One_OtherKind_Zero;
    [Test] procedure DataLine_SnippetHeader_NormalisedNumber;
    [Test] procedure DataLine_PlainNumber_Unchanged;
  end;

implementation

uses
  System.IOUtils,
  uRuleCatalog;   // GetRuleCanonical(...).EditorHelp - Vorbedingung des QF-Bits

const
  // Vier Zeilen Quelltext - genug fuer einen Auszug um Zeile 2.
  SOURCE_TEXT = 'unit Foo;'#13#10'interface'#13#10'implementation'#13#10'end.';

procedure TTestExportHtmlRowAttrs.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_htmlrow_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestExportHtmlRowAttrs.TearDown;
begin
  try
    if TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  // noinspection EmptyExcept
  except
    // Aufraeumen darf keinen Testlauf kippen (gesperrte Datei o.ae.).
  end;
end;

function TTestExportHtmlRowAttrs.RenderFindings(Findings: TObjectList<TLeakFinding>): string;
// Repo-Modus (SourceFile leer), Bericht in Temp, zurueckgelesen. Die
// Liste gehoert dem Aufrufer.
var
  Fn : string;
begin
  Fn := TPath.Combine(FDir, 'report.html');
  var Opts: THtmlReportOptions;
  TExporterHtml.Run(Findings, Fn, Opts);
  Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
end;

function TTestExportHtmlRowAttrs.AttrAfter(const AHtml, AAnchor, AAttr: string): string;
// Wert von AAttr="..." hinter dem ersten Vorkommen von AAnchor; '' wenn
// Anker oder Attribut fehlen. Exakt ausschneiden statt Fenster - die
// Attribute einer Zeile stehen in fester Reihenfolge hintereinander.
var
  P, E : Integer;
begin
  Result := '';
  P := Pos(AAnchor, AHtml);
  if P = 0 then Exit;
  P := Pos(AAttr + '="', AHtml, P);
  if P = 0 then Exit;
  Inc(P, Length(AAttr) + 2);
  E := Pos('"', AHtml, P);
  if E > P then
    Result := Copy(AHtml, P, E - P);
end;

function NewFinding(AKind: TFindingKind; const APath, ALine: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(AKind);
  Result.FileName   := APath;
  Result.LineNumber := ALine;
  Result.MissingVar := 'probe';
  Result.MethodName := 'TestMethod';
end;

procedure TTestExportHtmlRowAttrs.DataQf_EditorHelpKind_One_OtherKind_Zero;
var
  L    : TObjectList<TLeakFinding>;
  Html : string;
begin
  // SCA007 UnusedUses traegt editorHelp (Code-Aktion seit 2026-10-10),
  // SCA001 MemoryLeak nicht - das QF-Badge haengt an genau diesem Bit.
  Assert.IsTrue(TRuleCatalog.GetRuleCanonical(fkUnusedUses).EditorHelp, 'Vorbedingung: SCA007 editorHelp');
  Assert.IsFalse(TRuleCatalog.GetRuleCanonical(fkMemoryLeak).EditorHelp, 'Vorbedingung: SCA001 ohne');
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(NewFinding(fkUnusedUses, 'src\uA.pas', '3'));
    L.Add(NewFinding(fkMemoryLeak, 'src\uB.pas', '4'));
    Html := RenderFindings(L);
  finally
    L.Free;
  end;
  Assert.AreEqual('1', AttrAfter(Html, 'data-rule="UnusedUses"', 'data-qf'), 'SCA007: data-qf=1');
  Assert.AreEqual('0', AttrAfter(Html, 'data-rule="MemoryLeak"', 'data-qf'), 'SCA001: data-qf=0');
end;

procedure TTestExportHtmlRowAttrs.DataLine_SnippetHeader_NormalisedNumber;
var
  L    : TObjectList<TLeakFinding>;
  Pas  : string;
  Html : string;
begin
  // '$2' parst StrToIntDef als 2 - der Auszug entsteht also, und das
  // Attribut traegt die Zahl, nicht den Rohtext (vorher stand dort '$2').
  Pas := TPath.Combine(FDir, 'Foo.pas');
  TFile.WriteAllText(Pas, SOURCE_TEXT, TEncoding.UTF8);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(NewFinding(fkMemoryLeak, Pas, '$2'));
    Html := RenderFindings(L);
  finally
    L.Free;
  end;
  Assert.IsTrue(Pos('class="src-snippet-hdr"', Html) > 0, 'Vorbedingung: Auszug vorhanden');
  Assert.AreEqual('2', AttrAfter(Html, 'class="src-snippet-hdr"', 'data-line'), 'data-line normalisiert');
  Assert.AreEqual<Integer>(0, Pos('data-line="$2"', Html), 'kein Rohtext im Attribut');
end;

procedure TTestExportHtmlRowAttrs.DataLine_PlainNumber_Unchanged;
var
  L    : TObjectList<TLeakFinding>;
  Pas  : string;
  Html : string;
begin
  // Die Klammer: eine normale Zeilennummer steht unveraendert im Attribut.
  Pas := TPath.Combine(FDir, 'Foo.pas');
  TFile.WriteAllText(Pas, SOURCE_TEXT, TEncoding.UTF8);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(NewFinding(fkMemoryLeak, Pas, '3'));
    Html := RenderFindings(L);
  finally
    L.Free;
  end;
  Assert.AreEqual('3', AttrAfter(Html, 'class="src-snippet-hdr"', 'data-line'));
  Assert.IsTrue(Pos(', Zeile 3</div>', Html) > 0, 'Anzeige: Zeile 3');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportHtmlRowAttrs);

end.
