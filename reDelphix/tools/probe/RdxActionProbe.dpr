program RdxActionProbe;

// reDelphix - Realworld-Probe der Editorhilfen (Entscheid E3, 2026-10-28).
//
// Ermittelt fuer eine Liste von Fundstellen genau das, was die Gluehbirne
// bzw. das Kontextmenue im Editor anbieten wuerde - ohne IDE, ueber
// DENSELBEN Kern wie das Package (uRdxActionCore.TRdxActionCore.Describe):
// je Fund und je Eintrag angeboten ja/nein, Grund der Sperre, Menuetext,
// Kennzeichnung (aendert Verhalten), ob er in der Gluehbirne steht, die
// Ersetzungen und der Text vorher/nachher. Das Ergebnis pruefen danach
// KI-Agenten.
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
// im Editor offen ist (txDisk). Liefert der Scan nur Lesefehler (SCA006),
// gilt er als gescheitert ("Scan: Lesefehler ...").
//
// WELCHER FUND (Spalte Quelle)
//
// scan:  der echte TLeakFinding des Einzeldatei-Scans - gleiche Regel und
//        Zeile, noch nicht von einer anderen Stelle genommen; unter
//        mehreren der mit derselben Meldung wie im SARIF (PickFinding).
// sarif: liefert der Scan keinen (Funde ueber Projekt-Index, Querverweise
//        oder analyser.ini des Referenzlaufs - die Unused-Familie SCA007/
//        SCA053/SCA054/SCA147/SCA164 u. a. - oder der Scan scheiterte),
//        baut die Probe den Fund aus den SARIF-Feldern: Kind ueber den
//        Katalog aus der RuleId, Zeile, EndLine, Meldung (MissingVar),
//        LeakVariant, Confidence (fehlt sie im SARIF: fcHigh wie
//        TLeakFinding.Create). Was das SARIF nicht traegt, bleibt leer:
//        MethodName, RelatedLines, StructureChain, RuleID (Custom-Regeln),
//        Severity/OriginalSeverity, Spalte - die Planer und Rezepte lesen
//        heute nur FileName, LineInt, Message/MissingVar, Kind, LeakVariant/
//        MemoryLeakVariant (SCA001) und Confidence (SCA144). Eine leere
//        Meldung schreibt der SARIF-Export als Kurzbeschreibung der Regel -
//        dann sieht der Planer diese.
// Ohne SARIF-Spalten (altes Format) bzw. mit unbekannter RuleId bleibt es
// bei "Fund nicht reproduziert".
//
// CSV (UTF-8 mit BOM, ';'-getrennt, RFC 4180: eine Zelle mit ';', '"',
// Zeilenumbruch oder Leerraum am Rand steht in "...", '"' darin doppelt),
// je Hilfe-Eintrag eine Zeile:
//   Datei;Zeile;Regel;Eintrag;Kind;Menuetext;angeboten;aendert;Grund;
//   Edits;VorherZeilen;NachherZeilen;Meldung;Hinweis;Quelle;inBirne
// Quelle: scan / sarif (s. oben), '-' bei einer Stelle ohne Fund.
// Eintrag: 1 / 2 (erster bzw. zweiter Eintrag der einfachen Hilfe),
// rezept:<Name> (RECIPE_* in uRdxActionCore: ShowSpan, FormatCall,
// SqlTemplate, UsesActions, RemoveMarker), diagnose ("reDelphix: <Grund>"),
// '-' bei einer Stelle ohne Eintrag (nicht reproduziert, Scan- oder
// Lesefehler, Ausnahme, Abbruch nach Stapelueberlauf).
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
// inBirne: ja, wenn der Eintrag in der Gluehbirne stuende - nach den
// Regeln des Hosts selbst (uFindingActionMenu.BuildFindingMenuModelFrom mit
// moAvailableFixesOnly: nur verfuegbare fakFix, Unterdruecken nur neben
// einer solchen Hilfe, nie Stelle zeigen, Umbau oder Diagnose). Gefragt
// wird je Stelle nur ihr eigener Fund: dass die Birne je Zeile hoechstens
// MAX_FINDINGS_PER_MENU Funde fragt (Omitted) und gleichlautende Umbauten
// anderer Funde derselben Zeile wegfallen, bildet die Probe nicht nach -
// Umbauten stehen ohnehin nie in der Birne. '-' bei einer Stelle ohne
// Eintrag.
// In den Textspalten (Menuetext, Grund, Vorher, Nachher, Meldung,
// Hinweis) steht LF als \n, CR als \r (ein CRLF also als \r\n) und ein
// Backslash als \\ - umkehrbar, der Text bleibt wortgetreu. Die Spalten
// Datei, Regel, Eintrag und Edits bleiben unkodiert.
//
// Am Ende eine Zusammenfassung nach stdout: Stellen je Regel und Quelle
// (scan, sarif, nicht reproduziert), je Regel und Eintrag angeboten/
// gesperrt/in der Birne getrennt nach Quelle, gesperrt nach Grund-Kategorie
// (Ziffern maskiert wie MaskDigits in RdxCorpusProbe), dazu
// Unterdruecken-Eintraege und Fehler.
//
// ROBUSTHEIT
//
// Eine Ausnahme kostet nur die Datei (Scan, Lesen) bzw. die Stelle (Kern,
// Eintraege, Vorschau), nie den Lauf; die CSV wird je Datei geschrieben.
// Nach einer Ausnahme im Kern entsteht ein frischer Kern (die faul
// gebauten Teile des Dienstes koennten halb stehen). Ein erschoepfter
// Stapel (EStackExhausted) ist anders: Windows stellt die Guard-Page danach
// nicht wieder her, ein zweiter Ueberlauf beendete den Prozess still. Nach
// dem ersten prueft die Probe deshalb nichts mehr - die uebrigen Stellen
// stehen als "nicht geprueft: Abbruch nach Stapelueberlauf" in der CSV,
// die Zusammenfassung kommt, der Exit-Code ist 3. Der Lauf bekommt den
// 32-MB-Stapel (tools\patch-stack-size.ps1). EAbort laeuft weiter.
//
// Exit-Codes: 0 fertig, 1 Abbruch (Ausnahme ausserhalb einer Datei),
// 2 Aufruf, 3 Abbruch nach Stapelueberlauf.
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
  uCrashDiag,       // EStackExhausted, DescribeException
  uEngineApi,       // TScanRequest, TAnalysisSession
  uMethodd12,       // TLeakFinding
  uSCAConsts,       // lsHint, fcLow, dlDelphi, fkFileReadError
  uFindingActions,  // TFindingActionKind, TFindingAction
  uFindingActionMenu, // BuildFindingMenuModelFrom: die Regeln der Birne
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
    + 'Edits;VorherZeilen;NachherZeilen;Meldung;Hinweis;Quelle;inBirne';
  SOURCE_SCAN  = 'scan';
  SOURCE_SARIF = 'sarif';
  REASON_STACK_ABORT = 'nicht geprueft: Abbruch nach Stapelueberlauf';
  EXIT_STACK_ABORT = 3;
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
    InBulb  : string;   // ja / nein / '-'
  end;

  TCounter = TDictionary<string, Integer>;

  TProbe = class
  private
    FOut       : TStreamWriter;
    FCore      : TRdxActionCore;
    FDisk      : TRdxDiskReasonCache;
    FProfile   : string;
    FOffered   : TCounter;   // Regel|Eintrag|Quelle
    FBlocked   : TCounter;   // Regel|Eintrag|Quelle
    FInBulb    : TCounter;   // Regel|Eintrag|Quelle
    FReasons   : TCounter;   // Regel|Eintrag|Kategorie
    FNotRepro  : TCounter;   // Regel
    FSuppress  : TCounter;   // Regel
    FFailures  : TCounter;   // Kategorie (Scan, Lesen, Ausnahme)
    FBySource  : TCounter;   // Regel|Quelle: Stellen je Quelle
    FSource    : string;     // Quelle des Funds, den ProbeSite gerade prueft
    FSites     : Integer;
    FFiles     : Integer;
    FRows      : Integer;
    FStackHit  : Boolean;    // ein EStackExhausted - nichts mehr pruefen
    FSkipped   : Integer;    // Stellen, die danach ungeprueft blieben
    procedure Bump(ACounter: TCounter; const AKey: string);
    procedure RenewCore;
    // Zaehlt eine Ausnahme; ein erschoepfter Stapel setzt FStackHit.
    procedure NoteException(E: Exception);
    // Execute fuer die Birnen-Frage (nie aufgerufen): BuildFindingMenuModel-
    // From zaehlt eine Aktion nur mit Execute als verfuegbar.
    procedure NoExecute(Sender: TObject);
    procedure WriteRow(const ASite: TSite; const ARow: TRow);
    // Eine Zeile fuer eine Stelle ohne Eintrag (Eintrag '-').
    procedure SiteProblem(const ASite: TSite; const AReason, AMsg: string);
    function Scan(const AFile: string): TObjectList<TLeakFinding>;
    // Scan der Datei; AScanFail: '' oder der Grund, warum es keine
    // Scan-Funde gibt (Ausnahme, nur Lesefehler). Liefert nie nil.
    function ScanFile(const AFile: string;
      out AScanFail: string): TObjectList<TLeakFinding>;
    // Welche Eintraege die Birne zeigte: je Eintrag True/False.
    function BulbFlags(AFinding: TLeakFinding;
      const AEntries: TArray<TRdxActionEntry>): TArray<Boolean>;
    // Grundfelder der Zeile eines Eintrags (ohne Vorschau).
    function EntryRow(AFinding: TLeakFinding;
      const AEntry: TRdxActionEntry; AInBulb: Boolean): TRow;
    // Edits, Vorher, Nachher (und Grund, wenn die Ersetzung scheitert).
    procedure FillPreview(const ASite: TSite; const AEntry: TRdxActionEntry;
      ALines: TStrings; const AText, AKey: string; var ARow: TRow);
    procedure CountEntry(const AKey: string; const AEntry: TRdxActionEntry;
      AInBulb: Boolean);
    procedure ProbeEntry(const ASite: TSite; AFinding: TLeakFinding;
      const AEntry: TRdxActionEntry; AInBulb: Boolean; ALines: TStrings;
      const AText: string);
    procedure DiagnosisRow(const ASite: TSite; AFinding: TLeakFinding;
      const AWhy: string);
    procedure UsesSkippedRow(const ASite: TSite; AFinding: TLeakFinding);
    // ASource: SOURCE_SCAN oder SOURCE_SARIF (Spalte Quelle, Zaehler).
    procedure ProbeSite(const ASite: TSite; AFinding: TLeakFinding;
      ALines: TStrings; const AText, ASource: string);
    // ProbeSite, eine Ausnahme kostet nur die Stelle (Review E3, Minor 4).
    procedure SafeProbeSite(const ASite: TSite; AFinding: TLeakFinding;
      ALines: TStrings; const AText, ASource: string);
    procedure NotReproduced(const ASite: TSite;
      AFindings: TObjectList<TLeakFinding>; const AScanFail: string);
    // Eine Stelle: Fund des Scans, sonst aus dem SARIF, sonst nicht
    // reproduziert.
    procedure ProbeOneSite(const ASite: TSite;
      AFindings: TObjectList<TLeakFinding>; var AUsed: TArray<Boolean>;
      ALines: TStrings; const AText, AScanFail: string);
    procedure ProbeFile(const AFile: string; ASites: TList<TSite>);
    procedure SkipFile(ASites: TList<TSite>);
    procedure ReadSites(const ASitesFile: string;
      AGroups: TObjectDictionary<string, TList<TSite>>; AOrder: TStrings);
    procedure PrintSources;
    procedure PrintEntries;
    procedure PrintCounters;
  public
    constructor Create(const AOutFile, AProfile: string);
    destructor Destroy; override;
    procedure Run(const ASitesFile: string);
    procedure Summary(AElapsedMs: Int64);
    // Der Lauf brach nach einem erschoepften Stapel ab (Exit-Code 3).
    property StackAborted: Boolean read FStackHit;
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

// LF -> \n, CR -> \r (CRLF also \r\n), Backslash -> \\ - umkehrbar
// (Review E3, Minor 7: bis dahin wurde CRLF zu \n und war von LF nicht
// mehr zu unterscheiden).
function Esc(const S: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create(Length(S) + 8);
  try
    for i := 1 to Length(S) do
      case S[i] of
        '\': SB.Append('\\');
        #10: SB.Append('\n');
        #13: SB.Append('\r');
      else
        SB.Append(S[i]);
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
  if AEntry.Recipe = RECIPE_SIMPLE_FIX then
    Result := IntToStr(AEntry.Variant + 1)
  else if (AEntry.Recipe = RECIPE_DIAGNOSIS)
       or (AEntry.Recipe = RECIPE_OPEN) then
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

{ ---- Funde ---- }

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

// Der Fund des Einzeldatei-Scans zu ASite (gleiche Regel, gleiche Zeile);
// -1 ohne Treffer. Reihenfolge der Durchgaenge:
//   0  noch nicht benutzt, Meldung wie im SARIF (nur mit SARIF-Feldern)
//   1  noch nicht benutzt
//   2  schon benutzt, Meldung wie im SARIF (dieselbe Stelle zweimal in der
//      Liste; nur mit SARIF-Feldern)
//   3  irgendeiner (nur OHNE SARIF-Felder - mit ihnen baut die Probe
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

// True, wenn der Scan Funde, aber nur Lesefehler (SCA006) lieferte.
function OnlyReadErrors(AFindings: TObjectList<TLeakFinding>;
  out AFirst: string): Boolean;
var
  F : TLeakFinding;
begin
  AFirst := '';
  Result := AFindings.Count > 0;
  for F in AFindings do
    if F.Kind <> fkFileReadError then
      Exit(False)
    else if AFirst = '' then
      AFirst := F.Message;
end;

{ ---- Zaehler ---- }

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

{ TProbe }

constructor TProbe.Create(const AOutFile, AProfile: string);
begin
  inherited Create;
  FProfile  := AProfile;
  FOffered  := TCounter.Create;
  FBlocked  := TCounter.Create;
  FInBulb   := TCounter.Create;
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
  FInBulb.Free;
  FBlocked.Free;
  FOffered.Free;
  inherited;
end;

procedure TProbe.Bump(ACounter: TCounter; const AKey: string);
begin
  ACounter.AddOrSetValue(AKey, CountOf(ACounter, AKey) + 1);
end;

procedure TProbe.RenewCore;
begin
  FreeAndNil(FCore);
  // Ohne Scope-Tabelle und ohne Lieferanten der Projekt-Units: der
  // uses-Umbau entfaellt (UsesSkipped, Zeile 'nicht geprueft').
  FCore := TRdxActionCore.Create(nil);
  FCore.Logging := False;
end;

procedure TProbe.NoteException(E: Exception);
begin
  Bump(FFailures, 'Ausnahme: ' + E.ClassName);
  if E is EStackExhausted then
    FStackHit := True;
end;

procedure TProbe.NoExecute(Sender: TObject);
begin
  // Nie gerufen - nur die Marke "ausfuehrbar" fuer die Birnen-Frage.
end;

procedure TProbe.WriteRow(const ASite: TSite; const ARow: TRow);
begin
  FOut.WriteLine(Cell(ASite.FileName) + ';' + IntToStr(ASite.Line) + ';'
    + Cell(ASite.RuleId) + ';' + Cell(ARow.Entry) + ';' + Cell(ARow.Kind)
    + ';' + Cell(Esc(ARow.Caption)) + ';' + Cell(ARow.Offered) + ';'
    + Cell(ARow.Changes) + ';' + Cell(Esc(ARow.Reason)) + ';'
    + Cell(ARow.Edits) + ';' + Cell(Esc(ARow.Before)) + ';'
    + Cell(Esc(ARow.After)) + ';' + Cell(Esc(ARow.Msg)) + ';'
    + Cell(Esc(ARow.Hint)) + ';' + Cell(ARow.Source) + ';'
    + Cell(ARow.InBulb));
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
  R.InBulb  := '-';
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

function TProbe.ScanFile(const AFile: string;
  out AScanFail: string): TObjectList<TLeakFinding>;
var
  First : string;
begin
  AScanFail := '';
  Result := nil;
  try
    Result := Scan(AFile);
  except
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Ein Scan-Fehler kostet nur die Scan-Funde dieser Datei: Stellen
    // mit SARIF-Feldern laufen mit Quelle sarif weiter.
    on E: Exception do
    begin
      AScanFail := 'Scan: ' + DescribeException(E);
      NoteException(E);
    end;
  end;
  if Result = nil then
    Result := TObjectList<TLeakFinding>.Create(True)
  else if OnlyReadErrors(Result, First) then
  begin
    // Nur Lesefehler (SCA006): kein Fund ist "nicht reproduziert", der
    // Scan sah die Datei nicht (Review E3, Minor 5).
    AScanFail := 'Scan: Lesefehler (SCA006): ' + First;
    Bump(FFailures, 'Scan: Lesefehler (SCA006)');
  end;
end;

function TProbe.BulbFlags(AFinding: TLeakFinding;
  const AEntries: TArray<TRdxActionEntry>): TArray<Boolean>;
var
  Acts     : TArray<TFindingAction>;
  Findings : TArray<TLeakFinding>;
  PerFind  : TArray<TArray<TFindingAction>>;
  Model    : TFindingMenuModel;
  i, k     : Integer;
  Taken    : TArray<Boolean>;
begin
  // Die Eintraege als Menuepunkte wie im Anbieter (FindingActionOf, dazu
  // ein Execute bei Daten) und durch die Form der Gluehbirne des Hosts.
  SetLength(Acts, Length(AEntries));
  for i := 0 to High(AEntries) do
  begin
    Acts[i] := TRdxActionCore.FindingActionOf(AEntries[i]);
    if AEntries[i].HasAction then
      Acts[i].Execute := NoExecute;
  end;
  SetLength(Findings, 1);
  Findings[0] := AFinding;
  SetLength(PerFind, 1);
  PerFind[0] := Acts;
  Model := BuildFindingMenuModelFrom(Findings, PerFind,
    [moAvailableFixesOnly]);
  // Model.Actions: die Aktionen, die stehen blieben (Hilfen in ihrer
  // Reihenfolge, Unterdruecken dahinter) - je eine dem ersten gleichen
  // Eintrag zuordnen.
  SetLength(Result, Length(AEntries));
  SetLength(Taken, Length(AEntries));
  for k := 0 to High(Model.Actions) do
    for i := 0 to High(Acts) do
      if not Taken[i] and (Acts[i].Kind = Model.Actions[k].Kind)
         and (Acts[i].Caption = Model.Actions[k].Caption)
         and (Acts[i].Hint = Model.Actions[k].Hint) then
      begin
        Taken[i] := True;
        Result[i] := True;
        Break;
      end;
end;

function TProbe.EntryRow(AFinding: TLeakFinding;
  const AEntry: TRdxActionEntry; AInBulb: Boolean): TRow;
begin
  Result := Default(TRow);
  Result.Entry   := EntryName(AEntry);
  Result.Kind    := KIND_NAMES[AEntry.Kind];
  Result.Caption := AEntry.Caption;
  Result.Offered := YesNo(AEntry.Enabled);
  Result.Changes := YesNo(AEntry.ChangesBehavior);
  Result.Msg     := AFinding.Message;
  Result.Source  := FSource;
  Result.InBulb  := YesNo(AInBulb);
  if AEntry.Enabled then
    Result.Hint := AEntry.Hint
  else
    Result.Reason := AEntry.Hint;
end;

procedure TProbe.FillPreview(const ASite: TSite;
  const AEntry: TRdxActionEntry; ALines: TStrings; const AText, AKey: string;
  var ARow: TRow);
var
  Window : string;
  Err    : string;
begin
  if AEntry.HasAction and (AEntry.Action.Kind = akReplace) then
  begin
    if not Preview(AText, ALines, AEntry.Action.Edits, ARow.Before,
         ARow.After, Window, Err) then
    begin
      ARow.Reason := Trim(ARow.Reason + ' ' + 'Ersetzung scheitert: ' + Err);
      Bump(FReasons, AKey + '|ANGEBOTEN, Ersetzung scheitert: '
        + CategoryOf(Err));
    end;
    ARow.Edits := EditsText(AEntry.Action.Edits);
    if Window <> '' then
      ARow.Edits := ARow.Edits + ' - ' + Window;
    Exit;
  end;
  // Navigation, gesperrter Eintrag, SQL-Vorlage: die Fundzeile mit
  // Kontext; die Vorlage ist das "nachher" (Zwischenablage).
  ARow.Before := LinesText(ALines, ASite.Line - CONTEXT_LINES,
    ASite.Line + CONTEXT_LINES);
  if AEntry.HasAction and (AEntry.Action.Kind = akSqlTemplate) then
  begin
    ARow.Edits := 'Zwischenablage';
    ARow.After := AEntry.Action.Template;
  end;
end;

procedure TProbe.CountEntry(const AKey: string; const AEntry: TRdxActionEntry;
  AInBulb: Boolean);
begin
  if AEntry.Enabled then
    Bump(FOffered, AKey + '|' + FSource)
  else
  begin
    Bump(FBlocked, AKey + '|' + FSource);
    Bump(FReasons, AKey + '|' + CategoryOf(AEntry.Hint));
  end;
  if AInBulb then
    Bump(FInBulb, AKey + '|' + FSource);
end;

procedure TProbe.ProbeEntry(const ASite: TSite; AFinding: TLeakFinding;
  const AEntry: TRdxActionEntry; AInBulb: Boolean; ALines: TStrings;
  const AText: string);
var
  R   : TRow;
  Key : string;
begin
  if AEntry.Kind = fakSuppress then
  begin
    Bump(FSuppress, ASite.RuleId);   // nur gezaehlt (Auftrag E3)
    Exit;
  end;
  R := EntryRow(AFinding, AEntry, AInBulb);
  if AEntry.Enabled and SameText(ASite.RuleId, RULE_FRESH_GUID) then
    R.Reason := 'nicht deterministisch (frische GUID)';
  Key := ASite.RuleId + '|' + R.Entry;
  FillPreview(ASite, AEntry, ALines, AText, Key, R);
  CountEntry(Key, AEntry, AInBulb);
  WriteRow(ASite, R);
end;

procedure TProbe.DiagnosisRow(const ASite: TSite; AFinding: TLeakFinding;
  const AWhy: string);
var
  R : TRow;
begin
  // Wie TRdxProvider.Provide vor dem Lesen: nur der Diagnose-Eintrag.
  R := Default(TRow);
  R.Entry   := 'diagnose';
  R.Kind    := KIND_NAMES[fakFix];
  R.Caption := DIAG_PREFIX + AWhy;
  R.Offered := 'nein';
  R.Changes := 'nein';
  R.Reason  := AWhy;
  R.Msg     := AFinding.Message;
  R.Source  := FSource;
  R.InBulb  := 'nein';
  Bump(FBlocked, ASite.RuleId + '|diagnose|' + FSource);
  Bump(FReasons, ASite.RuleId + '|diagnose|' + CategoryOf(AWhy));
  WriteRow(ASite, R);
end;

procedure TProbe.UsesSkippedRow(const ASite: TSite; AFinding: TLeakFinding);
var
  R : TRow;
begin
  R := Default(TRow);
  R.Entry   := 'rezept:' + RECIPE_USES_ACTIONS;
  R.Kind    := KIND_NAMES[fakRefactor];
  R.Offered := 'nicht geprueft';
  R.Changes := '-';
  R.Reason  := 'uses-Umbau nicht geprueft: die Probe hat keine '
    + 'Projekt-Units (IDE: TRdxEditor.ProjectUnits)';
  R.Msg     := AFinding.Message;
  R.Source  := FSource;
  R.InBulb  := 'nein';   // ein Umbau steht nie in der Birne
  Bump(FReasons, ASite.RuleId + '|rezept:' + RECIPE_USES_ACTIONS
    + '|nicht geprueft');
  WriteRow(ASite, R);
end;

procedure TProbe.ProbeSite(const ASite: TSite; AFinding: TLeakFinding;
  ALines: TStrings; const AText, ASource: string);
var
  Why     : string;
  Entries : TArray<TRdxActionEntry>;
  Bulb    : TArray<Boolean>;
  i       : Integer;
begin
  FSource := ASource;
  Bump(FBySource, ASite.RuleId + '|' + ASource);
  Why := TRdxActionCore.FindingDiagnosis(AFinding);
  if Why <> '' then
  begin
    DiagnosisRow(ASite, AFinding, Why);
    Exit;
  end;
  try
    Entries := FCore.Describe(AFinding, ALines, txDisk, AText);
  except
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Auch ein erschoepfter Stapel kostet nur diesen Fund (danach prueft
    // der Lauf nichts mehr, s. Kopf); der Kern wird neu angelegt, wie der
    // Anbieter mit FSource.Forget.
    on E: Exception do
    begin
      NoteException(E);
      SiteProblem(ASite, 'Ausnahme: ' + DescribeException(E),
        AFinding.Message);
      RenewCore;
      Exit;
    end;
  end;
  Bulb := BulbFlags(AFinding, Entries);
  for i := 0 to High(Entries) do
    ProbeEntry(ASite, AFinding, Entries[i], Bulb[i], ALines, AText);
  if FCore.UsesSkipped then
    UsesSkippedRow(ASite, AFinding);
end;

procedure TProbe.SafeProbeSite(const ASite: TSite; AFinding: TLeakFinding;
  ALines: TStrings; const AText, ASource: string);
begin
  try
    ProbeSite(ASite, AFinding, ALines, AText, ASource);
  except
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Was ProbeSite nicht selbst faengt (Eintraege, Vorschau, Birne) kostet
    // nur diese Stelle (Review E3, Minor 4) - bereits geschriebene Zeilen
    // der Stelle bleiben stehen.
    on E: Exception do
    begin
      NoteException(E);
      SiteProblem(ASite, 'Ausnahme: ' + DescribeException(E),
        AFinding.Message);
      RenewCore;
    end;
  end;
end;

procedure TProbe.NotReproduced(const ASite: TSite;
  AFindings: TObjectList<TLeakFinding>; const AScanFail: string);
var
  F    : TLeakFinding;
  Same : TStringList;
  Why  : string;
begin
  Bump(FNotRepro, ASite.RuleId);
  if AScanFail <> '' then
    Why := AScanFail
  else
  begin
    Same := TStringList.Create;
    try
      for F in AFindings do
        if SameText(F.ResolvedRuleId, ASite.RuleId)
           and (Same.Count < MAX_LINES_LISTED) then
          Same.Add(IntToStr(F.LineInt));
      if Same.Count = 0 then
        Why := 'Fund nicht reproduziert (keiner dieser Regel in der Datei)'
      else
        Why := 'Fund nicht reproduziert (Regel in der Datei auf Zeile '
          + Same.CommaText + ')';
    finally
      Same.Free;
    end;
  end;
  if not ASite.HasSarif then
    Why := Why + ' - sites.tsv ohne SARIF-Felder'
  else
    Why := Why + ' - RuleId ' + ASite.RuleId + ' im Katalog unbekannt';
  SiteProblem(ASite, Why, ASite.Msg);
end;

procedure TProbe.ProbeOneSite(const ASite: TSite;
  AFindings: TObjectList<TLeakFinding>; var AUsed: TArray<Boolean>;
  ALines: TStrings; const AText, AScanFail: string);
var
  Hit : Integer;
  Own : TLeakFinding;
begin
  Hit := PickFinding(AFindings, AUsed, ASite);
  if Hit >= 0 then
  begin
    AUsed[Hit] := True;
    SafeProbeSite(ASite, AFindings[Hit], ALines, AText, SOURCE_SCAN);
    Exit;
  end;
  // Der Scan liefert ihn nicht (Projekt-Index, Querverweise, ini des
  // Referenzlaufs, Scan gescheitert): der Fund aus den SARIF-Feldern.
  Own := FindingFromSarif(ASite);
  if Own = nil then
  begin
    NotReproduced(ASite, AFindings, AScanFail);
    Exit;
  end;
  try
    SafeProbeSite(ASite, Own, ALines, AText, SOURCE_SARIF);
  finally
    Own.Free;
  end;
end;

procedure TProbe.SkipFile(ASites: TList<TSite>);
var
  Site : TSite;
begin
  for Site in ASites do
  begin
    Inc(FSkipped);
    SiteProblem(Site, REASON_STACK_ABORT, Site.Msg);
  end;
end;

procedure TProbe.ProbeFile(const AFile: string; ASites: TList<TSite>);
var
  Findings : TObjectList<TLeakFinding>;
  Used     : TArray<Boolean>;
  Lines    : TRdxMappedLines;
  Text     : string;
  Site     : TSite;
  ScanFail : string;
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
  Lines := TRdxMappedLines.Create;
  try
    // Ohne die Zeilen gibt es weder einen Scan- noch einen SARIF-Fund.
    if not LoadFileSmart(AFile, Lines) then
    begin
      Bump(FFailures, 'Datei nicht lesbar');
      for Site in ASites do
        SiteProblem(Site, 'Datei nicht lesbar', '');
      Exit;
    end;
    Findings := ScanFile(AFile, ScanFail);
    Text := Lines.Text;
    SetLength(Used, Findings.Count);
    FDisk.Clear;
    PrevDisk := TRdxMagicFixes.UseDiskCache(FDisk);
    try
      for Site in ASites do
        if FStackHit then
        begin
          // Nach einem Stapelueberlauf nichts mehr pruefen (s. Kopf).
          Inc(FSkipped);
          SiteProblem(Site, REASON_STACK_ABORT, Site.Msg);
        end
        else
          ProbeOneSite(Site, Findings, Used, Lines, Text, ScanFail);
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

procedure TProbe.ReadSites(const ASitesFile: string;
  AGroups: TObjectDictionary<string, TList<TSite>>; AOrder: TStrings);
var
  Raw   : TStringList;
  List  : TList<TSite>;
  Row   : string;
  Parts : TArray<string>;
  Site  : TSite;
  i     : Integer;
  Key   : string;
begin
  Raw := TStringList.Create;
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
      if not AGroups.TryGetValue(Key, List) then
      begin
        List := TList<TSite>.Create;
        AGroups.Add(Key, List);
        AOrder.Add(Key);
      end;
      List.Add(Site);
    end;
  finally
    Raw.Free;
  end;
end;

procedure TProbe.Run(const ASitesFile: string);
var
  Groups : TObjectDictionary<string, TList<TSite>>;
  Order  : TStringList;
  List   : TList<TSite>;
  i      : Integer;
begin
  Order := TStringList.Create;
  Groups := TObjectDictionary<string, TList<TSite>>.Create([doOwnsValues]);
  try
    ReadSites(ASitesFile, Groups, Order);
    for i := 0 to Order.Count - 1 do
    begin
      List := Groups[Order[i]];
      if FStackHit then
      begin
        SkipFile(List);
        Continue;
      end;
      try
        ProbeFile(List[0].FileName, List);
      except
        on EAbort do raise;
        // noinspection ExceptionTooGeneral
        // Letzte Linie: was ProbeFile nicht selbst faengt (Schreibfehler
        // ...), kostet nur diese Datei.
        on E: Exception do
        begin
          NoteException(E);
          Writeln(ErrOutput, List[0].FileName, ': ', DescribeException(E));
        end;
      end;
      if (i + 1) mod 100 = 0 then
        Writeln(ErrOutput, Format('%d/%d Dateien', [i + 1, Order.Count]));
    end;
    FOut.Flush;
  finally
    Groups.Free;
    Order.Free;
  end;
end;

procedure TProbe.PrintSources;
var
  Rules : TStringList;
  K     : string;
begin
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
end;

procedure TProbe.PrintEntries;
var
  Keys   : TStringList;
  K      : string;
  Reason : string;
  Parts  : TArray<string>;
begin
  // Je Regel und Eintrag angeboten/gesperrt/in der Birne getrennt nach
  // Quelle, darunter die Kategorien (beide Quellen zusammen).
  Keys := TStringList.Create;
  try
    Keys.Sorted := True;
    Keys.Duplicates := dupIgnore;
    for K in FOffered.Keys do Keys.Add(WithoutSource(K));
    for K in FBlocked.Keys do Keys.Add(WithoutSource(K));
    for K in Keys do
    begin
      Writeln(Format('%-28s scan: angeboten %6d gesperrt %6d Birne %6d   '
        + 'sarif: angeboten %6d gesperrt %6d Birne %6d',
        [StringReplace(K, '|', ' ', []),
         CountOf(FOffered, K + '|' + SOURCE_SCAN),
         CountOf(FBlocked, K + '|' + SOURCE_SCAN),
         CountOf(FInBulb, K + '|' + SOURCE_SCAN),
         CountOf(FOffered, K + '|' + SOURCE_SARIF),
         CountOf(FBlocked, K + '|' + SOURCE_SARIF),
         CountOf(FInBulb, K + '|' + SOURCE_SARIF)]));
      for Reason in SortedKeys(FReasons) do
        if Reason.StartsWith(K + '|') then
          Writeln(Format('      %6d  %s', [FReasons[Reason],
            Copy(Reason, Length(K) + 2, MaxInt)]));
    end;
    // uses ohne Projekt-Units (nur Kategorien, keine angeboten/gesperrt).
    for Reason in SortedKeys(FReasons) do
    begin
      Parts := Reason.Split(['|']);
      if (Length(Parts) >= 3) and (Parts[1] = 'rezept:' + RECIPE_USES_ACTIONS)
         and (Keys.IndexOf(Parts[0] + '|' + Parts[1]) < 0) then
        Writeln(Format('%-28s %6d  %s', [Parts[0] + ' ' + Parts[1],
          FReasons[Reason], Parts[2]]));
    end;
  finally
    Keys.Free;
  end;
end;

procedure TProbe.PrintCounters;
var
  K : string;
begin
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
    Writeln('Fehler (Datei bzw. Stelle, Lauf ging weiter):');
    for K in SortedKeys(FFailures) do
      Writeln(Format('  %6d  %s', [FFailures[K], K]));
  end;
  if FStackHit then
    Writeln(Format('ABBRUCH nach Stapelueberlauf: %d Stellen ungeprueft '
      + '(Exit-Code %d)', [FSkipped, EXIT_STACK_ABORT]));
end;

procedure TProbe.Summary(AElapsedMs: Int64);
var
  K      : string;
  Total  : Integer;
  Sup    : Integer;
  NScan  : Integer;
  NSarif : Integer;
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
  PrintSources;
  PrintEntries;
  PrintCounters;
end;

procedure Usage;
begin
  Writeln('RdxActionProbe <sites.tsv> <out.csv> [--lang de|en] '
    + '[--profile NAME]');
  Writeln('  sites.tsv: Datei<TAB>Zeile<TAB>RuleId[<TAB>Meldung<TAB>EndLine'
    + '<TAB>variant<TAB>confidence] je Zeile (UTF-8)');
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
  Code    : Integer;
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
  Code := 0;
  try
    Probe := TProbe.Create(ParamStr(2), Profile);
    try
      Probe.Run(ParamStr(1));
      Probe.Summary(Watch.ElapsedMilliseconds);
      if Probe.StackAborted then
        Code := EXIT_STACK_ABORT;
    finally
      Probe.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Abbruch: ', DescribeException(E));
      Code := 1;
    end;
  end;
  ExitCode := Code;
end.
