unit uExportSARIF;

// SARIF v2.1.0 Export.
//
// SARIF (Static Analysis Results Interchange Format) ist der OASIS-Standard
// fuer Static-Analysis-Tool-Output. Wird nativ verarbeitet von:
//   * GitHub Code-Scanning (Findings als PR-Annotationen)
//   * Azure DevOps Pipelines
//   * Visual Studio Code (mit SARIF-Extension)
//   * SonarCloud / SonarQube (via Plugin)
//
// Schema-Referenz: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
// JSON-Schema:     https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json
//
// Output-Struktur (Minimal-Variante, alle Pflichtfelder):
//   runs[0].tool.driver { name, version, informationUri, rules[] }
//   runs[0].results[]   { ruleId, level, message, locations[], partialFingerprints }
//
// `partialFingerprints` ist optional aber HOCHEMPFOHLEN: GitHub nutzt das
// fuer Cross-Commit-Deduplizierung, damit Findings nicht doppelt erscheinen
// wenn ein File auf einer Branch in mehreren Commits vorkommt.
//
// Perf (2026-07-05): P12-sarif-streaming - der Export baut KEINEN JSON-DOM
// (TJSONObject-Baum) plus Format(2)-Gesamtstring mehr, sondern streamt pro
// Rule/Finding direkt ueber einen Chunk-Puffer (Datei-Modus: Flush in den
// FileStream ab ~64K). Vorher lagen DOM + formatierter Gesamtstring +
// UTF8-Byte-Array gleichzeitig im Speicher - bei Real-World-Scans (770k
// Findings, ~900MB SARIF) mehrere GB Peak. Der Byte-Output ist EXAKT
// identisch zur alten System.JSON-Serialisierung, siehe TSarifJsonEmitter.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uMethodd12;

type
  TSARIFWriter = class
  public
    // Schreibt einen kompletten SARIF-Report nach FileName.
    //   AFindings   - die gefundenen Befunde (Caller behaelt Ownership)
    //   ABaseDir    - Wurzelverzeichnis fuer relative Datei-Pfade
    //                 (typisch: das --path-Argument). Pfade in den
    //                 Findings die NICHT mit ABaseDir beginnen, werden
    //                 als absolute Pfade ausgegeben (file:// URI).
    //   AToolVersion- Version-String fuer tool.driver.version
    //   AToolName   - Name-String fuer tool.driver.name
    class procedure WriteFile(const AFileName: string;
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AToolVersion, AToolName: string); static;

    // Variante die direkt einen JSON-String liefert (fuer Tests).
    class function ToJsonString(
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AToolVersion, AToolName: string): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ClassPerFile, ConcatToFormat, ConsecutiveSection, DuplicateString, GroupedDeclaration, LongMethod, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes, System.IOUtils, System.Hash, System.StrUtils,
  uSCAConsts, uRuleCatalog, uFindingFingerprint;

{ ---- Helpers ---- }

function SeverityToSarifLevel(S: TLeakSeverity; K: TFindingKind): string;
// SARIF level: "error" | "warning" | "note" | "none".
// FileReadError ist immer Error (Tool kommt nicht weiter).
begin
  if K = fkFileReadError then Exit('error');
  case S of
    lsError   : Result := 'error';
    lsWarning : Result := 'warning';
    lsHint    : Result := 'note';
  else
    Result := 'warning';
  end;
end;

function MakeRelative(const AFileName, ABaseDir: string): string;
// Liefert AFileName relativ zu ABaseDir wenn moeglich, sonst unveraendert.
// Forward-Slashes (SARIF-Konvention, GitHub erwartet das fuer File-Annotation).
var
  Base, Full, Rel : string;
begin
  if (ABaseDir = '') or (AFileName = '') then
    Exit(StringReplace(AFileName, '\', '/', [rfReplaceAll]));
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ABaseDir));
  Full := TPath.GetFullPath(AFileName);
  if SameText(Copy(Full, 1, Length(Base)), Base) then
    Rel := Copy(Full, Length(Base) + 1, MaxInt)
  else
    Rel := Full;
  Result := StringReplace(Rel, '\', '/', [rfReplaceAll]);
end;

function ParseLineNumber(const S: string): Integer;
// LineNumber kommt im TLeakFinding als String - SARIF braucht Integer.
// Bei Parse-Fehler 1 (SARIF erlaubt nicht 0).
begin
  if not TryStrToInt(S, Result) or (Result < 1) then
    Result := 1;
end;

function FingerprintHash(const RuleID, RelPath: string; LineNo: Integer;
  const Message: string): string;
// SHA256 ueber RuleID + Pfad + Zeile + Message - GitHub nutzt das fuer
// Cross-Commit-Dedup. Identische Findings auf demselben Pfad/Zeile
// werden nicht doppelt angezeigt.
var
  Bytes : TBytes;
  Hash  : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    RuleID + '|' + RelPath + '|' + IntToStr(LineNo) + '|' + Message);
  Hash := THashSHA2.GetHashString(TEncoding.UTF8.GetString(Bytes));
  Result := Hash;
end;

{ ---- Streaming-Emitter ---- }

const
  // Perf (2026-07-05): P12-sarif-streaming - Flush-Schwelle des Chunk-
  // Puffers im Datei-Modus (in Zeichen; UTF-8-Bytes koennen mehr sein).
  SARIF_FLUSH_CHARS = 64 * 1024;

type
  // Perf (2026-07-05): P12-sarif-streaming - Streaming-Serialisierer.
  // Bildet die Byte-Ausgabe von System.JSON `Root.Format(2)` EXAKT nach
  // (verifiziert gegen die Delphi-12-RTL-Quelle System.JSON.pas):
  //   * String-Escapes wie TJSONString.ToChars mit Options=[] (der Pfad,
  //     den TJSONValue.Format nimmt): NUR " \ / #8 #9 #10 #12 #13 werden
  //     zu \" \\ \/ \b \t \n \f \r. KEIN \uXXXX - andere Steuerzeichen
  //     und Nicht-ASCII bleiben roh. Gilt auch fuer Pair-NAMEN (deshalb
  //     steht im Output "contextHash\/v1" und "https:\/\/...").
  //   * Layout wie TJSONObject/TJSONArray.Format: '{' bzw. '[' + CRLF,
  //     Items mit 2 Spaces Einrueckung pro offener Ebene, ': ' nach dem
  //     Namen, Komma nach jedem Item ausser dem letzten, schliessende
  //     Klammer auf eigener Zeile mit Parent-Einrueckung. Leerer
  //     Container = '{' + CRLF + Parent-Einrueckung + '}'. CRLF kommt
  //     von TStringBuilder.AppendLine (sLineBreak) - wie im RTL-Pfad.
  //   * Zahlen wie TJSONNumber.Create(Integer) -> IntToStr.
  //   * Datei-Modus: Chunks werden mit TEncoding.UTF8.GetBytes kodiert.
  //     Chunk-Grenzen liegen immer auf Item-Grenzen (nie innerhalb eines
  //     Strings), daher kann kein Surrogat-Paar zerschnitten werden und
  //     die Byte-Folge ist identisch zur Ein-Stueck-Kodierung von
  //     TFile.WriteAllText.
  TSarifJsonEmitter = class
  private
    FSb      : TStringBuilder;   // Chunk-Puffer (String-Modus: Gesamttext)
    FStream  : TStream;          // nil => String-Modus (ToJsonString)
    FHasItem : TArray<Boolean>;  // pro offener Container-Ebene: schon Items?
    FDepth   : Integer;          // Anzahl offener Container
    // '"' + S mit den 8 RTL-Escapes + '"'. Unveraenderte Runs werden als
    // Substring-Block appended (kein Char-fuer-Char im Normalfall).
    procedure AppendEscaped(const S: string);
    // Vor jedem Item: [Komma] + CRLF + Einrueckung. Entspricht exakt der
    // RTL-Reihenfolge "Item, Komma-wenn-nicht-letztes, CRLF" - nur als
    // Praefix des Folge-Items statt Suffix des Vorgaengers formuliert
    // (gleiche Byte-Folge, aber ohne Lookahead moeglich).
    procedure ItemSeparator;
    procedure PushContainer;
    // CRLF + Parent-Einrueckung + '}' bzw. ']'.
    procedure CloseContainer(AClose: Char);
  public
    constructor Create(AStream: TStream);
    destructor Destroy; override;

    // '{' als Wert an aktueller Position (Root oder Array-Element).
    procedure BeginObjValue;
    // '"AName": {' - Objekt als Pair-Wert.
    procedure BeginObjPair(const AName: string);
    // '"AName": [' - Array als Pair-Wert.
    procedure BeginArrPair(const AName: string);
    procedure EndObj;
    procedure EndArr;
    // '"AName": "AValue"' (AValue escaped).
    procedure PairStr(const AName, AValue: string);
    // '"AName": 123' (wie TJSONNumber -> IntToStr).
    procedure PairInt(const AName: string; AValue: Integer);
    // String-Element in einem Array.
    procedure ArrStr(const AValue: string);
    // Datei-Modus: Puffer ab Schwelle (AForce: immer) UTF-8-kodiert in
    // den Stream schreiben. String-Modus: No-op.
    procedure FlushChunk(AForce: Boolean);
    // String-Modus: kompletter akkumulierter JSON-Text.
    function AsString: string;
  end;

constructor TSarifJsonEmitter.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
  FSb     := TStringBuilder.Create(SARIF_FLUSH_CHARS + 4096);
  SetLength(FHasItem, 16);
  FDepth  := 0;
end;

destructor TSarifJsonEmitter.Destroy;
begin
  FSb.Free;
  inherited;
end;

procedure TSarifJsonEmitter.AppendEscaped(const S: string);
var
  i, RunStart, L : Integer;
begin
  FSb.Append('"');
  L := Length(S);
  RunStart := 1;
  for i := 1 to L do
  begin
    case S[i] of
      '"', '\', '/', #8, #9, #10, #12, #13:
      begin
        // Unveraenderten Run vor dem Sonderzeichen als Block anhaengen
        // (StartIndex des Append-Overloads ist 0-basiert).
        if i > RunStart then
          FSb.Append(S, RunStart - 1, i - RunStart);
        case S[i] of
          '"' : FSb.Append('\"');
          '\' : FSb.Append('\\');
          '/' : FSb.Append('\/');
          #8  : FSb.Append('\b');
          #9  : FSb.Append('\t');
          #10 : FSb.Append('\n');
          #12 : FSb.Append('\f');
          #13 : FSb.Append('\r');
        end;
        RunStart := i + 1;
      end;
    end;
  end;
  if L >= RunStart then
    FSb.Append(S, RunStart - 1, L - RunStart + 1);
  FSb.Append('"');
end;

procedure TSarifJsonEmitter.ItemSeparator;
begin
  // Auf Root-Ebene (kein offener Container) steht kein Separator - der
  // Root-'{' ist das erste Byte des Dokuments (wie im RTL-Format).
  if FDepth > 0 then
  begin
    if FHasItem[FDepth - 1] then
      FSb.Append(',');
    FSb.AppendLine;
    FSb.Append(' ', FDepth * 2);       // LIdent = 2 Spaces je offener Ebene
    FHasItem[FDepth - 1] := True;
  end;
end;

procedure TSarifJsonEmitter.PushContainer;
begin
  if FDepth = Length(FHasItem) then
    SetLength(FHasItem, FDepth + 8);
  FHasItem[FDepth] := False;
  Inc(FDepth);
end;

procedure TSarifJsonEmitter.CloseContainer(AClose: Char);
begin
  Dec(FDepth);
  FSb.AppendLine;
  FSb.Append(' ', FDepth * 2);         // Parent-Einrueckung
  FSb.Append(AClose);
end;

procedure TSarifJsonEmitter.BeginObjValue;
begin
  ItemSeparator;
  FSb.Append('{');
  PushContainer;
end;

procedure TSarifJsonEmitter.BeginObjPair(const AName: string);
begin
  ItemSeparator;
  AppendEscaped(AName);
  FSb.Append(': ');
  FSb.Append('{');
  PushContainer;
end;

procedure TSarifJsonEmitter.BeginArrPair(const AName: string);
begin
  ItemSeparator;
  AppendEscaped(AName);
  FSb.Append(': ');
  FSb.Append('[');
  PushContainer;
end;

procedure TSarifJsonEmitter.EndObj;
begin
  CloseContainer('}');
end;

procedure TSarifJsonEmitter.EndArr;
begin
  CloseContainer(']');
end;

procedure TSarifJsonEmitter.PairStr(const AName, AValue: string);
begin
  ItemSeparator;
  AppendEscaped(AName);
  FSb.Append(': ');
  AppendEscaped(AValue);
end;

procedure TSarifJsonEmitter.PairInt(const AName: string; AValue: Integer);
begin
  ItemSeparator;
  AppendEscaped(AName);
  FSb.Append(': ');
  FSb.Append(IntToStr(AValue));
end;

procedure TSarifJsonEmitter.ArrStr(const AValue: string);
begin
  ItemSeparator;
  AppendEscaped(AValue);
end;

procedure TSarifJsonEmitter.FlushChunk(AForce: Boolean);
var
  Bytes : TBytes;
begin
  if (FStream = nil) or (FSb.Length = 0) then Exit;
  if AForce or (FSb.Length >= SARIF_FLUSH_CHARS) then
  begin
    Bytes := TEncoding.UTF8.GetBytes(FSb.ToString);
    if Length(Bytes) > 0 then
      FStream.WriteBuffer(Bytes, Length(Bytes));
    FSb.Clear;
  end;
end;

function TSarifJsonEmitter.AsString: string;
begin
  Result := FSb.ToString;
end;

{ ---- Dokument-Emission ---- }

procedure EmitSarifDocument(E: TSarifJsonEmitter;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AToolVersion, AToolName: string);
// Emittiert das komplette SARIF-Dokument in exakt der Pair-Reihenfolge,
// die vorher der TJSONObject-Aufbau (ToJsonString + BuildRulesArray +
// BuildResultsArray) erzeugt hat.
var
  F       : TLeakFinding;
  Meta    : TRuleMeta;
  RelPath : string;
  LineNo  : Integer;
  Msg     : string;
  RuleID  : string;
  CtxHash : string;
  CtxMemo : TDictionary<string, string>;
  // Perf P4 (Konzept_Performance25, 2026-07-19): MakeRelative machte 2x
  // TPath.GetFullPath PRO FINDING (~1,5 Mio Aufrufe bei 770k Findings),
  // obwohl ABaseDir konstant ist und nur ~10k eindeutige FileNames existieren.
  // Caller-scoped Memo FileName->RelPath (reine Funktion -> byte-identisch).
  RelMemo : TDictionary<string, string>;
begin
  E.BeginObjValue;                                     // Root {
  E.PairStr('$schema',
    'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json');
  E.PairStr('version', '2.1.0');
  E.BeginArrPair('runs');
  E.BeginObjValue;                                     // runs[0] {
  E.BeginObjPair('tool');
  E.BeginObjPair('driver');
  E.PairStr('name',
    IfThen(AToolName <> '', AToolName, TRuleCatalog.ToolName));
  E.PairStr('version',
    IfThen(AToolVersion <> '', AToolVersion, TRuleCatalog.ToolVersion));
  if TRuleCatalog.ToolUri <> '' then
    E.PairStr('informationUri', TRuleCatalog.ToolUri);

  // runs[0].tool.driver.rules[] - alle Catalog-Eintraege als SARIF-Rules.
  E.BeginArrPair('rules');
  TRuleCatalog.ForEach(
    procedure(M: TRuleMeta)
    var
      S : string;
    begin
      E.BeginObjValue;
      E.PairStr('id', M.ID);
      E.PairStr('name', IfThen(M.Name <> '', M.Name, KindName(M.Kind)));

      E.BeginObjPair('shortDescription');
      E.PairStr('text', IfThen(M.ShortDescription <> '',
                               M.ShortDescription, M.Name));
      E.EndObj;

      if M.FullDescription <> '' then
      begin
        E.BeginObjPair('fullDescription');
        E.PairStr('text', M.FullDescription);
        E.EndObj;
      end;

      // Default-Configuration: Severity-Level
      E.BeginObjPair('defaultConfiguration');
      E.PairStr('level', SeverityToSarifLevel(M.DefaultSeverity, M.Kind));
      E.EndObj;

      // Properties: tags + cwe + owasp
      E.BeginObjPair('properties');
      E.BeginArrPair('tags');
      for S in M.Tags  do E.ArrStr(S);
      for S in M.CWE   do E.ArrStr(S);
      for S in M.OWASP do E.ArrStr(S);
      E.EndArr;
      if M.DetectorUnit <> '' then
        E.PairStr('detectorUnit', M.DetectorUnit);
      if M.ConfigKey <> '' then
        E.PairStr('configKey', M.ConfigKey);
      E.EndObj;

      // Help-URI: GitHub zeigt das im Detail-Panel - Anker auf konsoli-
      // dierte docs/rules.md (per-file SCA001.md generiert tools/gen-rules-
      // docs.py wenn Python verfuegbar; bis dahin Anker-Links).
      E.PairStr('helpUri', Format('%s/blob/main/docs/rules.md#%s',
        [TRuleCatalog.ToolUri, LowerCase(M.ID)]));

      E.EndObj;
      E.FlushChunk(False);
    end);
  E.EndArr;                                            // rules
  E.EndObj;                                            // driver
  E.EndObj;                                            // tool

  // runs[0].results[] - pro Finding direkt streamen, kein DOM.
  E.BeginArrPair('results');
  // Perf (2026-07-05): P3 ContextHash-Memo - caller-scoped Memo fuer die
  // Dauer dieses Exports (kein Global): identische (Datei,Zeile) wird nur
  // einmal gelesen + gehasht.
  // RelMemo-Create INNERHALB des try: wirft es (OOM), freed das finally
  // CtxMemo trotzdem; Free auf RelMemo=nil ist no-op.
  RelMemo := nil;
  CtxMemo := TDictionary<string, string>.Create;
  try
    RelMemo := TDictionary<string, string>.Create;
    if Assigned(AFindings) then
      for F in AFindings do
      begin
        Meta    := TRuleCatalog.GetRule(F.Kind);
        if not RelMemo.TryGetValue(F.FileName, RelPath) then
        begin
          RelPath := MakeRelative(F.FileName, ABaseDir);
          RelMemo.Add(F.FileName, RelPath);
        end;
        LineNo  := ParseLineNumber(F.LineNumber);
        Msg     := F.MissingVar;
        if Msg = '' then
          Msg := Meta.ShortDescription;
        // Custom-Rule-IDs (z.B. 'PROJ001') gewinnen gegen Catalog-Lookup -
        // sonst built-in Rule-ID aus dem Catalog.
        if F.RuleID <> '' then RuleID := F.RuleID
        else RuleID := Meta.ID;

        E.BeginObjValue;                               // result {
        E.PairStr('ruleId', RuleID);
        E.PairStr('level', SeverityToSarifLevel(F.Severity, F.Kind));

        E.BeginObjPair('message');
        E.PairStr('text', Msg);
        E.EndObj;

        // physicalLocation/artifactLocation/region
        E.BeginArrPair('locations');
        E.BeginObjValue;
        E.BeginObjPair('physicalLocation');
        E.BeginObjPair('artifactLocation');
        E.PairStr('uri', RelPath);
        E.EndObj;
        E.BeginObjPair('region');
        E.PairInt('startLine', LineNo);
        E.EndObj;
        E.EndObj;                                      // physicalLocation
        E.EndObj;                                      // location
        E.EndArr;                                      // locations

        // partialFingerprints fuer GitHub-Dedup
        //   primaryLocationLineHash : line-dependent, fuer Cross-Commit-Dedup
        //   contextHash/v1          : Code-Snippet-basiert (Konzept C.2), stabil
        //                             gegen Line-Drift + Whitespace-Refactor
        E.BeginObjPair('partialFingerprints');
        E.PairStr('primaryLocationLineHash',
          FingerprintHash(RuleID, RelPath, LineNo, Msg));
        CtxHash := TFindingFingerprint.ContextHashMemo(F, CtxMemo);
        if CtxHash <> '' then
          E.PairStr('contextHash/' + CONTEXT_HASH_VERSION, CtxHash);
        E.EndObj;

        E.EndObj;                                      // result
        E.FlushChunk(False);
      end;
  finally
    CtxMemo.Free;
    RelMemo.Free;
  end;
  E.EndArr;                                            // results

  E.EndObj;                                            // runs[0]
  E.EndArr;                                            // runs
  E.EndObj;                                            // Root
  E.FlushChunk(True);
end;

{ ---- Public API ---- }

class function TSARIFWriter.ToJsonString(
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AToolVersion, AToolName: string): string;
var
  E : TSarifJsonEmitter;
begin
  E := TSarifJsonEmitter.Create(nil);                  // String-Modus
  try
    EmitSarifDocument(E, AFindings, ABaseDir, AToolVersion, AToolName);
    Result := E.AsString;
  finally
    E.Free;
  end;
end;

class procedure TSARIFWriter.WriteFile(const AFileName: string;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AToolVersion, AToolName: string);
var
  FS       : TFileStream;
  E        : TSarifJsonEmitter;
  Preamble : TBytes;
begin
  // Perf (2026-07-05): P12-sarif-streaming - direkt in den FileStream
  // statt Gesamtstring + TFile.WriteAllText. Byte-identisch zum alten
  // Verhalten: TFile.WriteAllText(..., TEncoding.UTF8) schrieb IMMER die
  // UTF-8-Preamble (BOM) vor den Inhalt (System.IOUtils DoWriteAllText,
  // WriteBOM=True) - der fruehere Kommentar "ohne BOM" war falsch.
  // Exception-Kontrakt wie TFile.WriteAllText erhalten (Review 2026-07-05):
  // dort kam bei nicht schreibbarem Pfad EInOutError an, TFileStream wirft
  // roh EFCreateError - fuer Aufrufer-Kompat auf die alte Klasse mappen.
  try
    FS := TFileStream.Create(AFileName, fmCreate);
  except
    on Ex: EFCreateError do
      raise EInOutError.Create(Ex.Message);
  end;
  try
    Preamble := TEncoding.UTF8.GetPreamble;
    if Length(Preamble) > 0 then
      FS.WriteBuffer(Preamble, Length(Preamble));
    E := TSarifJsonEmitter.Create(FS);
    try
      EmitSarifDocument(E, AFindings, ABaseDir, AToolVersion, AToolName);
    finally
      E.Free;
    end;
  finally
    FS.Free;
  end;
end;

end.
