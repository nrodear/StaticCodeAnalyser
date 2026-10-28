program RdxActionProbe;

// reDelphix - Realworld-Probe der Editorhilfen (Entscheid E3, 2026-10-28).
//
// Ermittelt fuer eine Liste von Fundstellen genau das, was die Gluehbirne
// bzw. das Kontextmenue im Editor anbieten wuerde - ohne IDE, ueber
// DENSELBEN Kern wie das Package (uRdxActionCore.TRdxActionCore.Describe):
// je Fund und je Eintrag angeboten ja/nein, Grund der Sperre, Menuetext,
// Kennzeichnung (aendert Verhalten), die Ersetzungen und der Text vorher/
// nachher. Das Ergebnis pruefen danach KI-Agenten.
//
//   RdxActionProbe <sites.tsv> <out.csv> [--lang de|en] [--profile NAME]
//
// sites.tsv (UTF-8, z. B. von sites_sample.py), je Zeile
//   Datei<TAB>Zeile<TAB>RuleId[<TAB>Meldung<TAB>EndLine<TAB>variant<TAB>confidence]
// - die vier hinteren Spalten sind die SARIF-Felder des Funds (message.text,
// region.endLine, properties.variant/confidence; leer = nicht im SARIF),
// kodiert wie die Textspalten der CSV, dazu TAB als \t. Leere Zeilen und
// Zeilen mit '#' am Anfang zaehlen nicht.
//
// ABLAUF JE DATEI
//
// Die Stellen werden nach Datei gruppiert. Jede Datei scannt die Probe
// selbst mit der Engine (uEngineApi, TAnalysisSession.Run mit ssSingleFile
// - der Weg der CLI fuer --file, aber ohne analyser.ini: Direkt-Modus mit
// Profil --profile (Vorgabe strict), Mindestschwere hint, Konfidenz ab
// low, UsesCheck, Dialekt Delphi, IFDEF-Sicht DefaultIfdefDefines) und
// ruft den Kern mit den Zeilen der Datei, gelesen wie der Scan
// (LoadFileSmart) - genau der Weg des Anbieters fuer eine Datei, die nicht
// im Editor offen ist (txDisk).
//
// WELCHER FUND (Spalte Quelle)
//
// scan:  der echte TLeakFinding des Einzeldatei-Scans - gleiche Regel und
//        Zeile, noch nicht von einer anderen Stelle genommen; unter
//        mehreren der mit derselben Meldung wie im SARIF (sonst der erste).
// sarif: liefert der Scan keinen (Funde ueber Projekt-Index, Querverweise
//        oder analyser.ini des Referenzlaufs - die Unused-Familie SCA007/
//        SCA053/SCA054/SCA147/SCA164 u. a.), baut die Probe den Fund aus
//        den SARIF-Feldern: Kind ueber den Katalog aus der RuleId, Zeile,
//        EndLine, Meldung (MissingVar), LeakVariant, Confidence (fehlt sie
//        im SARIF: fcHigh wie TLeakFinding.Create). Was das SARIF nicht
//        traegt, bleibt leer: MethodName, RelatedLines, StructureChain,
//        RuleID (Custom-Regeln), Severity/OriginalSeverity, Spalte - die
//        Planer und Rezepte lesen heute nur FileName, LineInt, Message/
//        MissingVar, Kind, LeakVariant/MemoryLeakVariant (SCA001) und
//        Confidence (SCA144). Eine leere Meldung schreibt der SARIF-Export
//        als Kurzbeschreibung der Regel - dann sieht der Planer diese.
// Ohne SARIF-Spalten (altes Format) bzw. mit unbekannter RuleId bleibt es
// bei "Fund nicht reproduziert".
//
// CSV (UTF-8 mit BOM, ';'-getrennt, RFC 4180: eine Zelle mit ';', '"',
// Zeilenumbruch oder Leerraum am Rand steht in "...", '"' darin doppelt),
// je Hilfe-Eintrag eine Zeile:
//   Datei;Zeile;Regel;Eintrag;Kind;Menuetext;angeboten;aendert;Grund;
//   Edits;VorherZeilen;NachherZeilen;Meldung;Hinweis;Quelle
// Quelle: scan / sarif (s. oben), '-' bei einer Stelle ohne Fund.
// Eintrag: 1 / 2 (erster bzw. zweiter Eintrag der einfachen Hilfe),
// rezept:<Name> (ShowSpan, FormatCall, SqlTemplate, UsesActions,
// RemoveMarker), diagnose ("reDelphix: <Grund>"), '-' bei einer Stelle
// ohne Eintrag (nicht reproduziert, Scan- oder Lesefehler, Ausnahme).
// Kind: fix, navigate, refactor, context, unset (fakSuppress steht nicht
// in der CSV, nur im Zaehler). angeboten: ja / nein / nicht geprueft
// (uses-Umbau ohne Projekt-Units). Grund: der Grund der Sperre; bei einem
// angebotenen Eintrag leer, ausser die Ersetzung laesst sich nicht
// anwenden ("Ersetzung scheitert: ...") oder die Regel ist SCA197 (frische
// GUID - der Ersatztext ist je Lauf ein anderer). Edits: Zahl und Bereiche
// (Zeile:Spalte-Zeile:Spalte, Spalten in Zeichen, Ende exklusiv) samt dem
// Zeilenfenster; "Zwischenablage" bei der SQL-Vorlage. VorherZeilen/
// NachherZeilen: die betroffenen Zeilen (erste bis letzte Zeile der
// Ersetzungen, je 2 Zeilen Kontext) vor und nach dem Anwenden ueber
// PlanByteEdits/ApplyByteEdits (derselbe Weg wie der Editor); bei der
// SQL-Vorlage nachher die Vorlage; bei einem gesperrten Eintrag und bei
// "Stelle zeigen" vorher die Fundzeile mit 2 Zeilen Kontext. Meldung: die
// Meldung des Funds; Hinweis: der Hinweis eines angebotenen Eintrags.
// In den Textspalten (Menuetext, Grund, Vorher, Nachher, Meldung,
// Hinweis) steht ein Zeilenumbruch als \n, ein einzelnes CR als \r und
// ein Backslash als \\ - umkehrbar, der Text bleibt wortgetreu. Die
// Spalten Datei, Regel, Eintrag und Edits bleiben unkodiert.
//
// Am Ende eine Zusammenfassung nach stdout: je Regel und Eintrag
// angeboten/gesperrt getrennt nach Quelle scan und sarif, gesperrt nach
// Grund-Kategorie (Ziffern maskiert wie MaskDigits in RdxCorpusProbe),
// dazu Stellen je Quelle und Regel, nicht reproduzierte Stellen,
// Unterdruecken-Eintraege und Ausnahmen.
//
// ROBUSTHEIT
//
// Eine Ausnahme kostet nur die Datei (Scan, Lesen) bzw. den Fund (Kern),
// nie den Lauf; die CSV wird je Datei geschrieben. Nach einer Ausnahme im
// Kern entsteht ein frischer Kern (die faul gebauten Teile des Dienstes
// koennten halb stehen). Ein erschoepfter Stapel (EStackExhausted) wird
// ebenso nur gezaehlt - Windows stellt die Guard-Page danach nicht wieder
// her, ein zweiter Ueberlauf beendet den Prozess; der Lauf bekommt deshalb
// den 32-MB-Stapel (tools\patch-stack-size.ps1). EAbort laeuft weiter.
//
// SPRACHE: Menuetexte und Gruende in --lang (Vorgabe en) ueber
// SetRdxLanguageOverride - redelphix.ini wird weder gelesen noch angelegt,
// analyser.ini liest der Direkt-Modus des Scans nicht.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Diagnostics,
  System.Generics.Collections,
  uCrashDiag,      // EStackExhausted, DescribeException
  uEngineApi,       // TScanRequest, TAnalysisSession
  uMethodd12,       // TLeakFinding
  uSCAConsts,       // lsHint, fcLow, dlDelphi
  uFindingActions,  // TFindingActionKind
  uFileTextCache,   // LoadFileSmart: dieselbe Dekodierung wie der Scan
  uRuleCatalog,     // GetRuleByIDCanonical: Kind zur RuleId (Quelle sarif)
  uRdxText in '..\..\source\uRdxText.pas',
  uRdxBufferMath in '..\..\source\uRdxBufferMath.pas',
  uRdxCodeMap in '..\..\source\uRdxCodeMap.pas',
  uRdxMagicFixes in '..\..\source\uRdxMagicFixes.pas',
  uRdxActionCore in '..\..\source\uRdxActionCore.pas';

const
  CONTEXT_LINES   = 2;
  DEFAULT_PROFILE = 'strict';
  DEFAULT_LANG    = 'en';
  RULE_FRESH_GUID = 'SCA197';
  MAX_LINES_LISTED = 8;     // Zeilen gleicher Regel bei "nicht reproduziert"
  MAX_CATEGORY    = 100;    // Zeichen einer Grund-Kategorie
  CSV_HEADER =
    'Datei;Zeile;Regel;Eintrag;Kind;Menuetext;angeboten;aendert;Grund;'
    + 'Edits;VorherZeilen;NachherZeilen;Meldung;Hinweis;Quelle';
  SOURCE_SCAN  = 'scan';
  SOURCE_SARIF = 'sarif';
  KIND_NAMES : array[TFindingActionKind] of string =
    ('unset', 'fix', 'navigate', 'suppress', 'refactor', 'context');

type
  TSite = record
    FileName   : string;
    Line       : Integer;
    RuleId     : string;
    // Die SARIF-Felder (sites.tsv, Spalten 4-7; dekodiert). HasSarif:
    // die Zeile traegt sie - nur dann baut die Probe einen Fund daraus.
    HasSarif   : Boolean;
    Msg        : string;
    EndLine    : Integer;
    Variant    : string;
    Confidence : string;
  end;

  // Die Felder einer CSV-Zeile ausser Datei, Zeile und Regel.
  TRow = record
    Entry   : string;
    Kind    : string;
    Caption : string;
    Offered : string;
    Changes : string;
    Reason  : string;
    Edits   : string;
    Before  : string;
    After   : string;
    Msg     : string;
    Hint    : string;
    Source  : string;   // scan / sarif / '-'
  end;

  TCounter = TDictionary<string, Integer>;

  TProbe = class
  private
    FOut      : TStreamWriter;
    FCore     : TRdxActionCore;
    FDisk     : TRdxDiskReasonCache;
    FProfile  : string;
    FOffered  : TCounter;   // Regel|Eintrag|Quelle
    FBlocked  : TCounter;   // Regel|Eintrag|Quelle
    FReasons  : TCounter;   // Regel|Eintrag|Kategorie
    FNotRepro : TCounter;   // Regel
    FSuppress : TCounter;   // Regel
    FFailures : TCounter;   // Kategorie (Scan, Lesen, Ausnahme)
    FBySource : TCounter;   // Regel|Quelle: Stellen je Quelle
    FSource   : string;     // Quelle des Funds, den ProbeSite gerade prueft
    FSites    : Integer;
    FFiles    : Integer;
    FRows     : Integer;
    procedure Bump(ACounter: TCounter; const AKey: string);
    procedure RenewCore;
    procedure WriteRow(const ASite: TSite; const ARow: TRow);
    // Eine Zeile fuer eine Stelle ohne Eintrag (Eintrag '-').
    procedure SiteProblem(const ASite: TSite; const AReason, AMsg: string);
    function Scan(const AFile: string): TObjectList<TLeakFinding>;
    procedure ProbeEntry(const ASite: TSite; AFinding: TLeakFinding;
      const AEntry: TRdxActionEntry; ALines: TStrings; const AText: string);
    // ASource: SOURCE_SCAN oder SOURCE_SARIF (Spalte Quelle, Zaehler).
    procedure ProbeSite(const ASite: TSite; AFinding: TLeakFinding;
      ALines: TStrings; const AText, ASource: string);
    procedure ProbeFile(const AFile: string; ASites: TList<TSite>);
  public
    constructor Create(const AOutFile, AProfile: string);
    destructor Destroy; override;
    procedure Run(const ASitesFile: string);
    procedure Summary(AElapsedMs: Int64);
  end;

{ ---- Text der Zellen ---- }

// Umkehrung der Kodierung von sites.tsv (sites_sample.tsv_enc): \\ -> \,
// \n -> LF, \r -> CR, \t -> TAB; ein anderes Zeichen hinter \ bleibt.
function Unesc(const S: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create(Length(S));
  try
    i := 1;
    while i <= Length(S) do
    begin
      if (S[i] = '\') and (i < Length(S)) then
      begin
        Inc(i);
        case S[i] of
          'n': SB.Append(#10);
          'r': SB.Append(#13);
          't': SB.Append(#9);
        else
          SB.Append(S[i]);
        end;
      end
      else
        SB.Append(S[i]);
      Inc(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Ein Fund aus den SARIF-Feldern der Stelle (Quelle sarif, s. Kopf); nil,
// wenn die Stelle keine traegt oder der Katalog die RuleId nicht kennt.
// Der Aufrufer gibt frei.
function FindingFromSarif(const ASite: TSite): TLeakFinding;
var
  Meta : TRuleMeta;
begin
  Result := nil;
  if not ASite.HasSarif then Exit;
  if not TRuleCatalog.GetRuleByIDCanonical(ASite.RuleId, Meta) then Exit;
  // New setzt ueber SetKind Confidence := fcHigh - die SARIF-Konfidenz
  // danach (fehlt sie, gilt wie bei TLeakFinding.Create fcHigh).
  Result := TLeakFinding.New(ASite.FileName, '', ASite.Line, ASite.Msg,
    Meta.Kind);
  if ASite.EndLine > ASite.Line then
    Result.EndLine := ASite.EndLine;
  Result.LeakVariant := ASite.Variant;
  if ASite.Confidence <> '' then
    Result.Confidence := ParseConfidence(ASite.Confidence, fcHigh);
end;

// Zeilenumbruch -> \n, einzelnes CR -> \r, Backslash -> \\ (umkehrbar).
function Esc(const S: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create(Length(S) + 8);
  try
    i := 1;
    while i <= Length(S) do
    begin
      case S[i] of
        '\': SB.Append('\\');
        #10: SB.Append('\n');
        #13:
          begin
            if (i < Length(S)) and (S[i + 1] = #10) then
            begin
              SB.Append('\n');
              Inc(i);
            end
            else
              SB.Append('\r');
          end;
      else
        SB.Append(S[i]);
      end;
      Inc(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// RFC 4180 mit ';' als Trenner: in "..." bei ';', '"', CR/LF oder
// Leerraum am Rand (eingerueckter Code), '"' darin doppelt. Sonst
// unveraendert.
function Cell(const S: string): string;
var
  Quote : Boolean;
begin
  Quote := (S <> '') and ((Pos(';', S) > 0) or (Pos('"', S) > 0)
    or (Pos(#13, S) > 0) or (Pos(#10, S) > 0)
    or CharInSet(S[1], [' ', #9]) or CharInSet(S[Length(S)], [' ', #9]));
  if Quote then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

// Jede Ziffernfolge -> 'N' (wie RdxCorpusProbe.MaskDigits): Zeilen,
// Spalten und Zahlen im Grund machten sonst aus jeder Stelle eine eigene
// Kategorie.
function MaskDigits(const S: string): string;
var
  i, n  : Integer;
  InNum : Boolean;
begin
  SetLength(Result, Length(S));
  n     := 0;
  InNum := False;
  for i := 1 to Length(S) do
  begin
    if (S[i] >= '0') and (S[i] <= '9') then
    begin
      if InNum then Continue;
      InNum := True;
      Inc(n);
      Result[n] := 'N';
    end
    else
    begin
      InNum := False;
      Inc(n);
      Result[n] := S[i];
    end;
  end;
  SetLength(Result, n);
end;

// Grund -> Kategorie fuer die Zusammenfassung: Ziffern maskiert, eine
// Zeile, hoechstens MAX_CATEGORY Zeichen. Bei Parser- und anderen
// Ausnahmen bleibt nur die Klasse ('<Praefix>: <Klasse>').
function CategoryOf(const AReason: string): string;
const
  PREFIXES : array[0..2] of string = (DIAG_PREFIX + 'Parser: ', 'Ausnahme: ',
    'Scan: ');
var
  P    : string;
  Rest : string;
  Q    : Integer;
begin
  for P in PREFIXES do
    if AReason.StartsWith(P) then
    begin
      Rest := Copy(AReason, Length(P) + 1, MaxInt);
      Q := Pos(':', Rest);
      if Q > 0 then Rest := Copy(Rest, 1, Q - 1);
      Exit(P + Rest);
    end;
  Result := MaskDigits(StringReplace(StringReplace(AReason, #13, ' ',
    [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > MAX_CATEGORY then
    Result := Copy(Result, 1, MAX_CATEGORY) + '...';
end;

// '1'/'2' fuer die einfache Hilfe, 'diagnose', sonst 'rezept:<Name>'.
function EntryName(const AEntry: TRdxActionEntry): string;
begin
  if AEntry.Recipe = 'SimpleFix' then
    Result := IntToStr(AEntry.Variant + 1)
  else if (AEntry.Recipe = 'Diagnosis') or (AEntry.Recipe = 'Open') then
    Result := 'diagnose'
  else
    Result := 'rezept:' + AEntry.Recipe;
end;

function YesNo(AValue: Boolean): string;
begin
  if AValue then Result := 'ja' else Result := 'nein';
end;

// Die Zeilen AFirst..ALast (1-basiert, begrenzt auf ALines), mit #10
// verbunden; '' bei leerem Fenster.
function LinesText(ALines: TStrings; AFirst, ALast: Integer): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  Result := '';
  AFirst := Max(AFirst, 1);
  ALast  := Min(ALast, ALines.Count);
  if ALast < AFirst then Exit;
  SB := TStringBuilder.Create;
  try
    for i := AFirst to ALast do
    begin
      if i > AFirst then SB.Append(#10);
      SB.Append(ALines[i - 1]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Bereiche der Ersetzungen: 'n: Z:S-Z:S | Z:S-Z:S'.
function EditsText(const AEdits: TArray<TRdxEdit>): string;
var
  i : Integer;
begin
  Result := IntToStr(Length(AEdits)) + ':';
  for i := 0 to High(AEdits) do
  begin
    if i > 0 then Result := Result + ' |';
    Result := Result + Format(' %d:%d-%d:%d', [AEdits[i].Span.StartLine,
      AEdits[i].Span.StartCol, AEdits[i].Span.EndLine, AEdits[i].Span.EndCol]);
  end;
end;

// Vorher/Nachher wie der Editor: PlanByteEdits auf den UTF-8-Bytes von
// AText, ApplyByteEdits, dann das Zeilenfenster erste bis letzte Zeile der
// Ersetzungen +-CONTEXT_LINES (nachher um die Zeilendifferenz verschoben).
// False mit AError, wenn der Plan scheitert.
function Preview(const AText: string; ALines: TStrings;
  const AEdits: TArray<TRdxEdit>; out ABefore, AAfter, AWindow,
  AError: string): Boolean;
var
  Bytes     : TBytes;
  NewBytes  : TBytes;
  Plan      : TArray<TRdxByteEdit>;
  After     : TStringList;
  E         : TRdxEdit;
  MinLine   : Integer;
  MaxLine   : Integer;
  First     : Integer;
  LastB     : Integer;
  LastA     : Integer;
begin
  ABefore := '';
  AAfter  := '';
  AWindow := '';
  AError  := '';
  MinLine := MaxInt;
  MaxLine := 0;
  for E in AEdits do
  begin
    MinLine := Min(MinLine, E.Span.StartLine);
    MaxLine := Max(MaxLine, E.Span.EndLine);
  end;
  if MaxLine = 0 then
    MinLine := 1;
  First := Max(1, MinLine - CONTEXT_LINES);
  LastB := Min(ALines.Count, MaxLine + CONTEXT_LINES);
  ABefore := LinesText(ALines, First, LastB);
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Result := PlanByteEdits(Bytes, AEdits, Plan, AError);
  if not Result then Exit;
  After := TStringList.Create;
  try
    // Kein GetString auf einem leeren Array (wie PlanByteEdits): eine
    // Ersetzung kann die ganze Datei leeren.
    NewBytes := ApplyByteEdits(Bytes, Plan);
    if Length(NewBytes) > 0 then
      After.Text := TEncoding.UTF8.GetString(NewBytes);
    LastA := Min(After.Count, LastB + (After.Count - ALines.Count));
    AAfter := LinesText(After, First, LastA);
    AWindow := Format('Zeilen %d-%d (nachher %d-%d)',
      [First, LastB, First, LastA]);
  finally
    After.Free;
  end;
end;

{ TProbe }

constructor TProbe.Create(const AOutFile, AProfile: string);
begin
  inherited Create;
  FProfile  := AProfile;
  FOffered  := TCounter.Create;
  FBlocked  := TCounter.Create;
  FReasons  := TCounter.Create;
  FNotRepro := TCounter.Create;
  FSuppress := TCounter.Create;
  FFailures := TCounter.Create;
  FBySource := TCounter.Create;
  FDisk     := TRdxDiskReasonCache.Create;
  RenewCore;
  // UTF-8 mit BOM (wie RdxCorpusProbe ueber TStringList.SaveToFile) -
  // Excel und Python (utf-8-sig) lesen beides.
  FOut := TStreamWriter.Create(AOutFile, False, TEncoding.UTF8);
  FOut.WriteLine(CSV_HEADER);
end;

destructor TProbe.Destroy;
begin
  FOut.Free;
  FCore.Free;
  FDisk.Free;
  FBySource.Free;
  FFailures.Free;
  FSuppress.Free;
  FNotRepro.Free;
  FReasons.Free;
  FBlocked.Free;
  FOffered.Free;
  inherited;
end;

procedure TProbe.Bump(ACounter: TCounter; const AKey: string);
var
  N : Integer;
begin
  if not ACounter.TryGetValue(AKey, N) then N := 0;
  ACounter.AddOrSetValue(AKey, N + 1);
end;

procedure TProbe.RenewCore;
begin
  FreeAndNil(FCore);
  // Ohne Scope-Tabelle und ohne Lieferanten der Projekt-Units: der
  // uses-Umbau entfaellt (UsesSkipped, Zeile 'nicht geprueft').
  FCore := TRdxActionCore.Create(nil);
  FCore.Logging := False;
end;

procedure TProbe.WriteRow(const ASite: TSite; const ARow: TRow);
begin
  FOut.WriteLine(Cell(ASite.FileName) + ';' + IntToStr(ASite.Line) + ';'
    + Cell(ASite.RuleId) + ';' + Cell(ARow.Entry) + ';' + Cell(ARow.Kind)
    + ';' + Cell(Esc(ARow.Caption)) + ';' + Cell(ARow.Offered) + ';'
    + Cell(ARow.Changes) + ';' + Cell(Esc(ARow.Reason)) + ';'
    + Cell(ARow.Edits) + ';' + Cell(Esc(ARow.Before)) + ';'
    + Cell(Esc(ARow.After)) + ';' + Cell(Esc(ARow.Msg)) + ';'
    + Cell(Esc(ARow.Hint)) + ';' + Cell(ARow.Source));
  Inc(FRows);
end;

procedure TProbe.SiteProblem(const ASite: TSite; const AReason, AMsg: string);
var
  R : TRow;
begin
  R := Default(TRow);
  R.Entry   := '-';
  R.Kind    := '-';
  R.Offered := 'nein';
  R.Changes := '-';
  R.Reason  := AReason;
  R.Msg     := AMsg;
  R.Source  := '-';
  WriteRow(ASite, R);
end;

function TProbe.Scan(const AFile: string): TObjectList<TLeakFinding>;
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
  Res : TScanResult;
begin
  // Der Weg der CLI fuer --file (ssSingleFile), im Direkt-Modus: nur die
  // Felder dieses Requests, keine analyser.ini (TScanRequest.ApplyRepoIni
  // False). Init setzt DefaultIfdefDefines und Include-Defines.
  Req := TScanRequest.Init;
  Req.Scope         := ssSingleFile;
  Req.Path          := AFile;
  Req.Profile       := FProfile;
  Req.MinSeverity   := lsHint;
  Req.MinConfidence := fcLow;
  Req.UsesCheck     := True;
  Req.Dialect       := dlDelphi;
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try
      Result := Res.ReleaseFindings;
    finally
      Res.Free;
    end;
  finally
    Ses.Free;
  end;
end;

procedure TProbe.ProbeEntry(const ASite: TSite; AFinding: TLeakFinding;
  const AEntry: TRdxActionEntry; ALines: TStrings; const AText: string);
var
  R      : TRow;
  Key    : string;
  Window : string;
  Err    : string;
begin
  if AEntry.Kind = fakSuppress then
  begin
    Bump(FSuppress, ASite.RuleId);   // nur gezaehlt (Auftrag E3)
    Exit;
  end;
  R := Default(TRow);
  R.Entry   := EntryName(AEntry);
  R.Kind    := KIND_NAMES[AEntry.Kind];
  R.Caption := AEntry.Caption;
  R.Offered := YesNo(AEntry.Enabled);
  R.Changes := YesNo(AEntry.ChangesBehavior);
  R.Msg     := AFinding.Message;
  R.Source  := FSource;
  Key := ASite.RuleId + '|' + R.Entry;
  if AEntry.Enabled then
  begin
    R.Hint := AEntry.Hint;
    if SameText(ASite.RuleId, RULE_FRESH_GUID) then
      R.Reason := 'nicht deterministisch (frische GUID)';
  end
  else
    R.Reason := AEntry.Hint;
  if AEntry.HasAction and (AEntry.Action.Kind = akReplace) then
  begin
    if not Preview(AText, ALines, AEntry.Action.Edits, R.Before, R.After,
         Window, Err) then
    begin
      R.Reason := Trim(R.Reason + ' ' + 'Ersetzung scheitert: ' + Err);
      Bump(FReasons, Key + '|ANGEBOTEN, Ersetzung scheitert: '
        + CategoryOf(Err));
    end;
    R.Edits := EditsText(AEntry.Action.Edits);
    if Window <> '' then
      R.Edits := R.Edits + ' - ' + Window;
  end
  else
  begin
    // Navigation, gesperrter Eintrag, SQL-Vorlage: die Fundzeile mit
    // Kontext; die Vorlage ist das "nachher" (Zwischenablage).
    R.Before := LinesText(ALines, ASite.Line - CONTEXT_LINES,
      ASite.Line + CONTEXT_LINES);
    if AEntry.HasAction and (AEntry.Action.Kind = akSqlTemplate) then
    begin
      R.Edits := 'Zwischenablage';
      R.After := AEntry.Action.Template;
    end;
  end;
  if AEntry.Enabled then
    Bump(FOffered, Key + '|' + FSource)
  else
  begin
    Bump(FBlocked, Key + '|' + FSource);
    Bump(FReasons, Key + '|' + CategoryOf(AEntry.Hint));
  end;
  WriteRow(ASite, R);
end;

procedure TProbe.ProbeSite(const ASite: TSite; AFinding: TLeakFinding;
  ALines: TStrings; const AText, ASource: string);
var
  Why     : string;
  Entries : TArray<TRdxActionEntry>;
  Entry   : TRdxActionEntry;
  R       : TRow;
begin
  FSource := ASource;
  Bump(FBySource, ASite.RuleId + '|' + ASource);
  Why := TRdxActionCore.FindingDiagnosis(AFinding);
  if Why <> '' then
  begin
    // Wie TRdxProvider.Provide vor dem Lesen: nur der Diagnose-Eintrag.
    R := Default(TRow);
    R.Entry   := 'diagnose';
    R.Kind    := KIND_NAMES[fakFix];
    R.Caption := DIAG_PREFIX + Why;
    R.Offered := 'nein';
    R.Changes := 'nein';
    R.Reason  := Why;
    R.Msg     := AFinding.Message;
    R.Source  := ASource;
    Bump(FBlocked, ASite.RuleId + '|diagnose|' + ASource);
    Bump(FReasons, ASite.RuleId + '|diagnose|' + CategoryOf(Why));
    WriteRow(ASite, R);
    Exit;
  end;
  try
    Entries := FCore.Describe(AFinding, ALines, txDisk, AText);
  except
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Auch ein erschoepfter Stapel kostet nur diesen Fund (s. Kopf); der
    // Kern wird neu angelegt, wie der Anbieter mit FSource.Forget.
    on E: Exception do
    begin
      Bump(FFailures, 'Ausnahme: ' + E.ClassName);
      SiteProblem(ASite, 'Ausnahme: ' + DescribeException(E),
        AFinding.Message);
      RenewCore;
      Exit;
    end;
  end;
  for Entry in Entries do
    ProbeEntry(ASite, AFinding, Entry, ALines, AText);
  if FCore.UsesSkipped then
  begin
    R := Default(TRow);
    R.Entry   := 'rezept:UsesActions';
    R.Kind    := KIND_NAMES[fakRefactor];
    R.Offered := 'nicht geprueft';
    R.Changes := '-';
    R.Reason  := 'uses-Umbau nicht geprueft: die Probe hat keine '
      + 'Projekt-Units (IDE: TRdxEditor.ProjectUnits)';
    R.Msg     := AFinding.Message;
    R.Source  := ASource;
    Bump(FReasons, ASite.RuleId + '|rezept:UsesActions|nicht geprueft');
    WriteRow(ASite, R);
  end;
end;

// Der Fund des Einzeldatei-Scans zu ASite (gleiche Regel, gleiche Zeile);
// -1 ohne Treffer. Reihenfolge der Durchgaenge:
//   0  noch nicht benutzt, Meldung wie im SARIF (nur mit SARIF-Feldern)
//   1  noch nicht benutzt
//   2  schon benutzt, Meldung wie im SARIF (dieselbe Stelle zweimal in der
//      Liste; nur mit SARIF-Feldern)
//   3  irgendeiner (nur OHNE SARIF-Feldern - mit ihnen baut die Probe
//      lieber den Fund aus dem SARIF, als einen fremden doppelt zu nehmen)
function PickFinding(AFindings: TObjectList<TLeakFinding>;
  const AUsed: TArray<Boolean>; const ASite: TSite): Integer;
var
  Pass : Integer;
  i    : Integer;
  F    : TLeakFinding;
begin
  Result := -1;
  for Pass := 0 to 3 do
  begin
    // Mit SARIF-Feldern die Durchgaenge 0-2, ohne sie 1 und 3.
    if ASite.HasSarif and (Pass = 3) then Continue;
    if not ASite.HasSarif and not Odd(Pass) then Continue;
    for i := 0 to AFindings.Count - 1 do
    begin
      F := AFindings[i];
      if (F.LineInt <> ASite.Line)
         or not SameText(F.ResolvedRuleId, ASite.RuleId) then Continue;
      if (Pass <= 1) and AUsed[i] then Continue;
      if (Pass = 2) and not AUsed[i] then Continue;
      if not Odd(Pass) and (F.Message <> ASite.Msg) then Continue;
      Exit(i);
    end;
  end;
end;

procedure TProbe.ProbeFile(const AFile: string; ASites: TList<TSite>);
var
  Findings : TObjectList<TLeakFinding>;
  Used     : TArray<Boolean>;
  Lines    : TRdxMappedLines;
  Text     : string;
  Site     : TSite;
  Hit      : Integer;
  F        : TLeakFinding;
  Own      : TLeakFinding;
  Same     : TStringList;
  ScanFail : string;
  Why      : string;
  PrevDisk : TRdxDiskReasonCache;
begin
  Inc(FFiles);
  if not FileExists(AFile) then
  begin
    for Site in ASites do
    begin
      Bump(FFailures, 'Datei nicht gefunden');
      SiteProblem(Site, 'Datei nicht gefunden', '');
    end;
    Exit;
  end;
  Findings := nil;
  Lines := nil;
  ScanFail := '';
  try
    // Ohne die Zeilen gibt es weder einen Scan- noch einen SARIF-Fund.
    Lines := TRdxMappedLines.Create;
    if not LoadFileSmart(AFile, Lines) then
    begin
      Bump(FFailures, 'Datei nicht lesbar');
      for Site in ASites do
        SiteProblem(Site, 'Datei nicht lesbar', '');
      Exit;
    end;
    try
      Findings := Scan(AFile);
    except
      on EAbort do raise;
      // noinspection ExceptionTooGeneral
      // Ein Scan-Fehler kostet nur die Scan-Funde dieser Datei: Stellen
      // mit SARIF-Feldern laufen mit Quelle sarif weiter.
      on E: Exception do
      begin
        ScanFail := 'Scan: ' + DescribeException(E);
        Bump(FFailures, CategoryOf(ScanFail));
      end;
    end;
    if Findings = nil then
      Findings := TObjectList<TLeakFinding>.Create(True);
    Text := Lines.Text;
    SetLength(Used, Findings.Count);
    FDisk.Clear;
    PrevDisk := TRdxMagicFixes.UseDiskCache(FDisk);
    try
      for Site in ASites do
      begin
        Hit := PickFinding(Findings, Used, Site);
        if Hit >= 0 then
        begin
          Used[Hit] := True;
          ProbeSite(Site, Findings[Hit], Lines, Text, SOURCE_SCAN);
          Continue;
        end;
        // Der Scan liefert ihn nicht (Projekt-Index, Querverweise, ini des
        // Referenzlaufs): der Fund aus den SARIF-Feldern (s. Kopf).
        Own := FindingFromSarif(Site);
        if Own <> nil then
        begin
          try
            ProbeSite(Site, Own, Lines, Text, SOURCE_SARIF);
          finally
            Own.Free;
          end;
          Continue;
        end;
        Bump(FNotRepro, Site.RuleId);
        if ScanFail <> '' then
          Why := ScanFail
        else
        begin
          Same := TStringList.Create;
          try
            for F in Findings do
              if SameText(F.ResolvedRuleId, Site.RuleId)
                 and (Same.Count < MAX_LINES_LISTED) then
                Same.Add(IntToStr(F.LineInt));
            if Same.Count = 0 then
              Why := 'Fund nicht reproduziert (keiner dieser Regel in der '
                + 'Datei)'
            else
              Why := 'Fund nicht reproduziert (Regel in der Datei auf Zeile '
                + Same.CommaText + ')';
          finally
            Same.Free;
          end;
        end;
        if not Site.HasSarif then
          Why := Why + ' - sites.tsv ohne SARIF-Felder'
        else
          Why := Why + ' - RuleId ' + Site.RuleId + ' im Katalog unbekannt';
        SiteProblem(Site, Why, Site.Msg);
      end;
    finally
      TRdxMagicFixes.UseDiskCache(PrevDisk);
    end;
  finally
    Lines.Free;
    Findings.Free;
    // Der Text-Cache der Engine waechst sonst ueber alle Dateien des Laufs.
    TAnalysisSession.ReleaseTransientCaches;
    FOut.Flush;
  end;
end;

procedure TProbe.Run(const ASitesFile: string);
var
  Raw    : TStringList;
  Groups : TObjectDictionary<string, TList<TSite>>;
  Order  : TStringList;
  List   : TList<TSite>;
  Row    : string;
  Parts  : TArray<string>;
  Site   : TSite;
  i      : Integer;
  Key    : string;
begin
  Raw := TStringList.Create;
  Order := TStringList.Create;
  Groups := TObjectDictionary<string, TList<TSite>>.Create([doOwnsValues]);
  try
    Raw.LoadFromFile(ASitesFile, TEncoding.UTF8);
    for i := 0 to Raw.Count - 1 do
    begin
      Row := Raw[i];
      if (Trim(Row) = '') or Row.StartsWith('#') then Continue;
      Parts := Row.Split([#9]);
      if Length(Parts) < 2 then Continue;
      Site := Default(TSite);
      Site.FileName := Parts[0];
      Site.Line     := StrToIntDef(Trim(Parts[1]), 0);
      if Length(Parts) > 2 then
        Site.RuleId := Trim(Parts[2]);
      // Die SARIF-Felder (sites_sample.py): Meldung, EndLine, variant,
      // confidence - kodiert wie die Textspalten (Unesc).
      if Length(Parts) > 3 then
      begin
        Site.HasSarif   := True;
        Site.Msg        := Unesc(Parts[3]);
        if Length(Parts) > 4 then
          Site.EndLine  := StrToIntDef(Trim(Parts[4]), 0);
        if Length(Parts) > 5 then
          Site.Variant  := Unesc(Parts[5]);
        if Length(Parts) > 6 then
          Site.Confidence := Trim(Unesc(Parts[6]));
      end;
      if Site.Line < 1 then Continue;
      Inc(FSites);
      Key := AnsiUpperCase(Site.FileName);
      if not Groups.TryGetValue(Key, List) then
      begin
        List := TList<TSite>.Create;
        Groups.Add(Key, List);
        Order.Add(Key);
      end;
      List.Add(Site);
    end;
    for i := 0 to Order.Count - 1 do
    begin
      List := Groups[Order[i]];
      try
        ProbeFile(List[0].FileName, List);
      except
        on EAbort do raise;
        // noinspection ExceptionTooGeneral
        // Letzte Linie: was ProbeFile nicht selbst faengt (Schreibfehler
        // der Zeilen einer Stelle ...), kostet nur diese Datei.
        on E: Exception do
        begin
          Bump(FFailures, 'Ausnahme: ' + E.ClassName);
          Writeln(ErrOutput, List[0].FileName, ': ', DescribeException(E));
        end;
      end;
      if (i + 1) mod 100 = 0 then
        Writeln(ErrOutput, Format('%d/%d Dateien', [i + 1, Order.Count]));
    end;
  finally
    Groups.Free;
    Order.Free;
    Raw.Free;
  end;
end;

function SortedKeys(ACounter: TCounter): TArray<string>;
begin
  Result := ACounter.Keys.ToArray;
  TArray.Sort<string>(Result);
end;

// Zaehler zu AKey, 0 ohne Eintrag.
function CountOf(ACounter: TCounter; const AKey: string): Integer;
begin
  if not ACounter.TryGetValue(AKey, Result) then Result := 0;
end;

// 'Regel|Eintrag' aus 'Regel|Eintrag|Quelle'.
function WithoutSource(const AKey: string): string;
var
  P : Integer;
begin
  P := AKey.LastIndexOf('|');
  if P > 0 then
    Result := Copy(AKey, 1, P)
  else
    Result := AKey;
end;

procedure TProbe.Summary(AElapsedMs: Int64);
var
  Keys    : TStringList;
  Rules   : TStringList;
  K       : string;
  Reason  : string;
  Parts   : TArray<string>;
  Total   : Integer;
  Sup     : Integer;
  NScan   : Integer;
  NSarif  : Integer;
begin
  Total := 0;
  for K in FNotRepro.Keys do Inc(Total, FNotRepro[K]);
  Sup := 0;
  for K in FSuppress.Keys do Inc(Sup, FSuppress[K]);
  NScan := 0;
  NSarif := 0;
  for K in FBySource.Keys do
    if K.EndsWith('|' + SOURCE_SCAN) then
      Inc(NScan, FBySource[K])
    else
      Inc(NSarif, FBySource[K]);
  Writeln(Format('Stellen: %d  Dateien: %d  CSV-Zeilen: %d  Quelle scan: %d  '
    + 'Quelle sarif: %d  nicht reproduziert: %d  Unterdruecken-Eintraege '
    + '(nicht in der CSV): %d  Zeit: %.1f s', [FSites, FFiles, FRows, NScan,
      NSarif, Total, Sup, AElapsedMs / 1000]));
  // Stellen je Regel und Quelle.
  Rules := TStringList.Create;
  try
    Rules.Sorted := True;
    Rules.Duplicates := dupIgnore;
    for K in FBySource.Keys do Rules.Add(WithoutSource(K));
    for K in FNotRepro.Keys do Rules.Add(K);
    Writeln(Format('%-10s %8s %8s %8s', ['Regel', 'scan', 'sarif',
      'fehlt']));
    for K in Rules do
      Writeln(Format('%-10s %8d %8d %8d', [K,
        CountOf(FBySource, K + '|' + SOURCE_SCAN),
        CountOf(FBySource, K + '|' + SOURCE_SARIF), CountOf(FNotRepro, K)]));
  finally
    Rules.Free;
  end;
  // Je Regel und Eintrag angeboten/gesperrt getrennt nach Quelle, darunter
  // die Kategorien (beide Quellen zusammen).
  Keys := TStringList.Create;
  try
    Keys.Sorted := True;
    Keys.Duplicates := dupIgnore;
    for K in FOffered.Keys do Keys.Add(WithoutSource(K));
    for K in FBlocked.Keys do Keys.Add(WithoutSource(K));
    for K in Keys do
    begin
      Writeln(Format('%-28s scan: angeboten %6d gesperrt %6d   sarif: '
        + 'angeboten %6d gesperrt %6d', [StringReplace(K, '|', ' ', []),
        CountOf(FOffered, K + '|' + SOURCE_SCAN),
        CountOf(FBlocked, K + '|' + SOURCE_SCAN),
        CountOf(FOffered, K + '|' + SOURCE_SARIF),
        CountOf(FBlocked, K + '|' + SOURCE_SARIF)]));
      for Reason in SortedKeys(FReasons) do
        if Reason.StartsWith(K + '|') then
          Writeln(Format('      %6d  %s', [FReasons[Reason],
            Copy(Reason, Length(K) + 2, MaxInt)]));
    end;
    // uses ohne Projekt-Units (nur Kategorien, keine angeboten/gesperrt).
    for Reason in SortedKeys(FReasons) do
    begin
      Parts := Reason.Split(['|']);
      if (Length(Parts) >= 3) and (Parts[1] = 'rezept:UsesActions')
         and (Keys.IndexOf(Parts[0] + '|' + Parts[1]) < 0) then
        Writeln(Format('%-28s %6d  %s', [Parts[0] + ' ' + Parts[1],
          FReasons[Reason], Parts[2]]));
    end;
  finally
    Keys.Free;
  end;
  if FNotRepro.Count > 0 then
  begin
    Writeln('Nicht reproduziert je Regel:');
    for K in SortedKeys(FNotRepro) do
      Writeln(Format('  %-10s %6d', [K, FNotRepro[K]]));
  end;
  if FSuppress.Count > 0 then
  begin
    Writeln('Unterdruecken-Eintraege je Regel (nicht in der CSV):');
    for K in SortedKeys(FSuppress) do
      Writeln(Format('  %-10s %6d', [K, FSuppress[K]]));
  end;
  if FFailures.Count > 0 then
  begin
    Writeln('Fehler (Datei bzw. Fund, Lauf ging weiter):');
    for K in SortedKeys(FFailures) do
      Writeln(Format('  %6d  %s', [FFailures[K], K]));
  end;
end;

procedure Usage;
begin
  Writeln('RdxActionProbe <sites.tsv> <out.csv> [--lang de|en] '
    + '[--profile NAME]');
  Writeln('  sites.tsv: Datei<TAB>Zeile<TAB>RuleId je Zeile (UTF-8)');
  Writeln('  --lang     Sprache der Menuetexte und Gruende (Vorgabe '
    + DEFAULT_LANG + ')');
  Writeln('  --profile  Profil des Einzeldatei-Scans (Vorgabe '
    + DEFAULT_PROFILE + ')');
end;

var
  Probe   : TProbe;
  Lang    : string;
  Profile : string;
  Arg     : string;
  a       : Integer;
  Watch   : TStopwatch;
begin
  if ParamCount < 2 then
  begin
    Usage;
    Halt(2);
  end;
  Lang    := DEFAULT_LANG;
  Profile := DEFAULT_PROFILE;
  a := 3;
  while a <= ParamCount do
  begin
    Arg := ParamStr(a);
    if SameText(Arg, '--lang') and (a < ParamCount) then
    begin
      Lang := ParamStr(a + 1);
      Inc(a, 2);
    end
    else if SameText(Arg, '--profile') and (a < ParamCount) then
    begin
      Profile := ParamStr(a + 1);
      Inc(a, 2);
    end
    else
    begin
      Writeln(ErrOutput, 'unbekannter Schalter: ', Arg);
      Usage;
      Halt(2);
    end;
  end;
  if not FileExists(ParamStr(1)) then
  begin
    Writeln(ErrOutput, 'nicht lesbar: ', ParamStr(1));
    Halt(2);
  end;
  // Feste Sprache: keine redelphix.ini (Override), keine analyser.ini.
  SetRdxLanguageOverride(Lang);
  Watch := TStopwatch.StartNew;
  try
    Probe := TProbe.Create(ParamStr(2), Profile);
    try
      Probe.Run(ParamStr(1));
      Probe.Summary(Watch.ElapsedMilliseconds);
    finally
      Probe.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Abbruch: ', DescribeException(E));
      Halt(1);
    end;
  end;
end.
