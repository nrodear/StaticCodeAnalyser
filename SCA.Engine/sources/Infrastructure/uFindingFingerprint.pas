unit uFindingFingerprint;

// Context-Hash fuer Findings - stabilisiert SARIF-partialFingerprints und
// Baseline-Matching gegen Code-Refactors.
//
// Phase-1-Quick-Win C.2 aus Konzept_ScannerQualitaet:
//
// Problem: heutiger Baseline-Fingerprint (uBaseline.Fingerprint) nutzt
// File+Kind+Method+Detail. Methoden-Rename, Verschieben in andere Methode
// oder ein Detail-Wording-Change -> Baseline matched nicht mehr -> Finding
// zaehlt als "neu" trotz identischem Bug.
//
// Loesung: zusaetzlicher Hash ueber den CODE-KONTEXT um die Fund-Stelle
// (+/- Radius Zeilen, whitespace-normalisiert). Whitespace-Normalisierung
// macht den Hash unempfindlich gegen Re-Indent / Trailing-WS-Cleanup.
//
// Verwendung:
//   - uExportSARIF schreibt partialFingerprints.contextHash/v1
//   - uBaseline schreibt zusaetzlich contextHash pro Finding und matched
//     beim Apply EITHER contextHash OR legacy-Fingerprint (backward-compat)
//
// Wenn Datei nicht lesbar / LineNumber 0 / Radius 0 -> liefert '' (kein
// Hash). Caller faellt dann auf den Legacy-Fingerprint zurueck.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uMethodd12;

const
  CONTEXT_HASH_VERSION = 'v1';
  CONTEXT_HASH_RADIUS  = 3;          // +/- Zeilen um die Fund-Stelle

type
  TFindingFingerprint = class
  public
    // Liefert SHA256 ueber den normalisierten Code-Snippet rund um die
    // Fund-Stelle. Leerer String wenn kein Snippet gebildet werden konnte
    // (Datei fehlt, LineNumber unparsbar, leere Datei, ...).
    class function ContextHash(const F: TLeakFinding;
      Radius: Integer = CONTEXT_HASH_RADIUS): string; static;

    // Variante mit expliziten Parametern - fuer Tests + direkte Aufrufer.
    // AForceStat: Default True (mtime+Size-Recheck pro Zugriff) - Kontrakt
    // fuer Baseline-Drift-Matching ueber Datei-Ueberschreibungen hinweg.
    // Perf P3 (Konzept_Performance25, 2026-07-19): der SARIF-Export im
    // Scan-Prozess (Dateien seit dem Einlesen unveraendert) darf False
    // uebergeben und den Cache-Snapshot nutzen (spart 2 Syscalls pro
    // Finding-Zeile, ~0,6-1 Mio Stats pro Korpus-Export).
    class function ContextHashFor(const FileName: string; LineNo: Integer;
      Radius: Integer = CONTEXT_HASH_RADIUS;
      AForceStat: Boolean = True): string; static;

    // Perf (2026-07-05): P3 ContextHash-Memo - memoisierte Variante fuer
    // Schleifen ueber viele Findings (SARIF-Export, Baseline Write/Apply).
    // AMemo ist ein CALLER-SCOPED Dictionary (kein Global, kein Lifecycle-
    // Problem): Key ist LowerCase(Datei)+'|'+Zeile, Value der fertige Hash.
    // Mehrere Findings auf derselben (Datei,Zeile) bezahlen Snippet-Join +
    // Normalize + SHA256 (und im kalten Cache den File-Read) nur einmal;
    // auch '' (Datei nicht lesbar) wird memoisiert. Gilt nur fuer den
    // DEFAULT-Radius. AMemo=nil faellt auf ContextHash(F) zurueck.
    // Verhaltensneutral: ContextHashFor ist deterministisch in
    // (Datei,Zeile) bei stabilem Datei-Inhalt - dieselbe Annahme, die der
    // bestehende gFileTextCache-Snapshot bereits macht.
    // AForceStat wird an ContextHashFor durchgereicht (siehe dort);
    // Baseline Write/Apply lassen den Default True, SARIF-Export gibt
    // False (Perf P3).
    class function ContextHashMemo(const F: TLeakFinding;
      AMemo: TDictionary<string, string>;
      AForceStat: Boolean = True): string; static;

    // Normalisierungs-Helper (public fuer Tests):
    // Tabs -> Space, kollabiert Whitespace-Runs zu einem Space, trim,
    // verwirft leere Zeilen.
    class function Normalize(const Snippet: string): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ConcatToFormat, CyclomaticComplexity, GroupedDeclaration, MultipleExit, NestedTry, NilComparison, TooLongLine
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes, System.Hash, System.StrUtils,
  uFileTextCache;

function CollapseWhitespace(const Line: string; Sb: TStringBuilder): string;
// '   a\tb   c ' -> 'a b c'
// Tabs zu Space, Runs kollabiert, leading + trailing WS weg.
// Sb wird vom Caller wiederverwendet (Performance: spart Allocation
// pro Zeile bei langen Snippet-Listen).
var
  i      : Integer;
  C      : Char;
  PrevWs : Boolean;
begin
  Sb.Clear;
  PrevWs := True;                        // suppress leading WS
  for i := 1 to Length(Line) do
  begin
    C := Line[i];
    if (C = ' ') or (C = #9) then
    begin
      if not PrevWs then Sb.Append(' ');
      PrevWs := True;
    end
    else
    begin
      Sb.Append(C);
      PrevWs := False;
    end;
  end;
  Result := TrimRight(Sb.ToString);
end;

class function TFindingFingerprint.Normalize(const Snippet: string): string;
// In: roher Snippet aus mehreren Zeilen
// Out: jede Zeile getrimmt + Whitespace-Runs auf 1 Space kollabiert,
//      leere Zeilen verworfen, Zeilen mit LF verbunden.
//
// Damit ist der Hash stabil gegen:
//   - Re-Indent (Leading-WS aendert sich)
//   - Tab/Space-Mix-Aenderung
//   - Trailing-WS-Cleanup
//   - Leerzeilen-Cleanup
//   - CRLF vs LF
// Perf P9 (Konzept_Performance25, 2026-07-19): direkter Ein-Pass-Split statt
// 2x TStringList + ToStringArray + Join pro Aufruf (~300-500k Aufrufe pro
// Korpus-Export). Byte-identisch zum frueheren TStringList.Text-Split:
// CR, LF und CRLF trennen Zeilen; Randfaelle (LF+CR, trailing Umbruch)
// erzeugen dort nur zusaetzliche LEERE Zeilen - und leere Zeilen werden
// hier ohnehin verworfen.
var
  OutSb : TStringBuilder;
  Sb    : TStringBuilder;
  i, n  : Integer;
  s     : Integer;
  Line  : string;
begin
  if Snippet = '' then Exit('');
  Sb    := TStringBuilder.Create;
  OutSb := TStringBuilder.Create;
  try
    n := Length(Snippet);
    i := 1;
    while i <= n do
    begin
      s := i;
      while (i <= n) and (Snippet[i] <> #10) and (Snippet[i] <> #13) do
        Inc(i);
      Line := CollapseWhitespace(Copy(Snippet, s, i - s), Sb);
      if Line <> '' then
      begin
        if OutSb.Length > 0 then OutSb.Append(#10);
        OutSb.Append(Line);
      end;
      // Zeilenumbruch konsumieren: CRLF zaehlt als EIN Umbruch.
      if (i <= n) and (Snippet[i] = #13) then
      begin
        Inc(i);
        if (i <= n) and (Snippet[i] = #10) then Inc(i);
      end
      else if (i <= n) and (Snippet[i] = #10) then
        Inc(i);
    end;
    Result := OutSb.ToString;
  finally
    OutSb.Free;
    Sb.Free;
  end;
end;

function LineToZeroIndex(LineNo: Integer): Integer; inline;
// 1-basierte Compiler/Editor-Zeilen -> 0-basierter TStringList-Index.
begin
  Result := LineNo - 1;
end;

class function TFindingFingerprint.ContextHashFor(const FileName: string;
  LineNo, Radius: Integer; AForceStat: Boolean): string;
var
  Lines     : TStringList;
  Cached    : Boolean;
  Sb        : TStringBuilder;
  i, Lo, Hi : Integer;
  Snippet   : string;
  Norm      : string;
begin
  Result := '';
  if (FileName = '') or (LineNo < 1) or (Radius < 0) then Exit;

  // AForceStat=True (Default): der contextHash MUSS auf dem AKTUELLEN
  // Datei-Inhalt rechnen - Baseline-Drift-Matching vergleicht Kontexte
  // UEBER Datei-Ueberschreibungen hinweg, auch ohne zwischenzeitliches
  // Cache-Clear (Kontrakt-Test: Baseline_MatchesViaContextHashAfterLine-
  // Drift). Nur der SARIF-Export im Scan-Prozess reicht False durch
  // (Perf P3) - dort sind die Dateien seit dem Einlesen unveraendert.
  Lines := AcquireLines(FileName, Cached, nil, AForceStat);
  if Lines = nil then Exit;
  try
    if Lines.Count = 0 then Exit;
    Lo := LineToZeroIndex(LineNo) - Radius;
    Hi := LineToZeroIndex(LineNo) + Radius;
    if Lo < 0 then Lo := 0;
    if Hi > Lines.Count - 1 then Hi := Lines.Count - 1;
    Sb := TStringBuilder.Create;
    try
      for i := Lo to Hi do
      begin
        if Sb.Length > 0 then Sb.Append(#10);
        Sb.Append(Lines[i]);
      end;
      Snippet := Sb.ToString;
    finally
      Sb.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;

  Norm := Normalize(Snippet);
  if Norm = '' then Exit;
  Result := CONTEXT_HASH_VERSION + ':' +
            THashSHA2.GetHashString(Norm);
end;

class function TFindingFingerprint.ContextHash(const F: TLeakFinding;
  Radius: Integer): string;
var
  LineNo : Integer;
begin
  if F = nil then Exit('');
  if not TryStrToInt(F.LineNumber, LineNo) then LineNo := 0;
  Result := ContextHashFor(F.FileName, LineNo, Radius);
end;

class function TFindingFingerprint.ContextHashMemo(const F: TLeakFinding;
  AMemo: TDictionary<string, string>; AForceStat: Boolean): string;
// Perf (2026-07-05): P3 ContextHash-Memo - siehe Interface-Kommentar.
// Key-Bildung: LineNumber wird wie in ContextHash geparst (unparsbar -> 0,
// liefert dann wie bisher ''), damit '7' und '07' denselben Eintrag
// treffen. LowerCase auf den Pfad: Windows-FS ist case-insensitiv, gleiche
// Datei in anderer Schreibweise soll nicht doppelt gelesen werden.
var
  LineNo : Integer;
  Key    : string;
begin
  if F = nil then Exit('');
  if AMemo = nil then Exit(ContextHash(F));
  if not TryStrToInt(F.LineNumber, LineNo) then LineNo := 0;
  Key := LowerCase(F.FileName) + '|' + IntToStr(LineNo);
  if AMemo.TryGetValue(Key, Result) then Exit;
  Result := ContextHashFor(F.FileName, LineNo, CONTEXT_HASH_RADIUS, AForceStat);
  AMemo.Add(Key, Result);
end;

end.
