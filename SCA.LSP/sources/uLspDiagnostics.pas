unit uLspDiagnostics;

// =============================================================================
// SCA.LSP - Inkrement 0: Adapter Quelltext -> Engine -> LSP-Diagnostics.
//
// Reuse-Pfad laut Doku_06_CLI_LSP_Reporting.md: der LSP-Server ist der vierte
// Consumer auf uEngineApi - KEINE Detektor-Logik hier. Ein Buffer-Inhalt wird
// per TAnalysisSession.Run mit Scope ssSource analysiert (In-Memory-Pfad der
// Engine, volle Per-File-Pipeline inkl. Suppression); die TLeakFinding-Liste
// wird 1:1 in LSP-Diagnostic-JSON-Objekte gemappt.
//
// BEKANNTE LUECKE E3 (dokumentiert, hier NICHT geloest):
//   TLeakFinding hat KEIN Spaltenfeld (StartCol/EndCol/EndLine) - Doku_06,
//   Punkt "E3 - Spaltenfeld in TLeakFinding". Bis E3 umgesetzt ist, liefert
//   dieser Adapter die Spalte konstant 1 (LSP character 0) und markiert
//   die GANZE Zeile als Range (Ganz-Zeilen-Range, wie im MVP-Konzept
//   vorgesehen). Sobald echte Spalten kommen: UTF-16-Code-Unit-Offsets
//   beachten (LSP < 3.17 kennt nur utf-16 als positionEncoding).
// =============================================================================

interface

uses
  System.SysUtils, System.JSON;

// file:///-URI -> lokaler Windows-Pfad (minimal: Prefix ab, %XX decodieren,
// '/' -> '\'). Nicht-file-URIs werden unveraendert zurueckgegeben - der Pfad
// dient nur als LOGISCHER Name fuer die Findings (ssSource + Req.Path).
function UriToLogicalPath(const AUri: string): string;

// Analysiert AText (kompletter Buffer-Inhalt) und liefert das fertige
// LSP-"diagnostics"-Array. Der Aufrufer uebernimmt die Ownership.
function BuildDiagnostics(const AUri, AText: string): TJSONArray;

const
  // Analyse-Profil fuer den On-Type-Pfad. Doku_06: on-type 'ide-fast'
  // (schnelle Detektor-Teilmenge); per Setting steuerbar erst in einem
  // spaeteren Inkrement (workspace/configuration).
  LSP_PROFILE = 'ide-fast';

  // Diagnostics-Quelle (erscheint im Editor neben der Meldung).
  LSP_SOURCE  = 'sca';

implementation

uses
  uEngineApi,    // TAnalysisSession, TScanRequest, ssSource
  uMethodd12,    // TLeakFinding
  uSCAConsts;    // TLeakSeverity

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else        Result := -1;
  end;
end;

function PercentDecode(const S: string): string;
var
  SB   : TStringBuilder;
  i    : Integer;
  H, L : Integer;
  Bytes: TBytes;
  N    : Integer;
begin
  // %XX-Sequenzen sind UTF-8-Bytes -> erst Bytes sammeln, dann dekodieren.
  Bytes := nil;
  N := 0;
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= Length(S) do
    begin
      if (S[i] = '%') and (i + 2 <= Length(S)) then
      begin
        H := HexVal(S[i + 1]);
        L := HexVal(S[i + 2]);
        if (H >= 0) and (L >= 0) then
        begin
          SetLength(Bytes, N + 1);
          Bytes[N] := Byte(H * 16 + L);
          Inc(N);
          Inc(i, 3);
          Continue;
        end;
      end;
      if N > 0 then
      begin
        SB.Append(TEncoding.UTF8.GetString(Bytes, 0, N));
        N := 0;
        SetLength(Bytes, 0);
      end;
      SB.Append(S[i]);
      Inc(i);
    end;
    if N > 0 then
      SB.Append(TEncoding.UTF8.GetString(Bytes, 0, N));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function UriToLogicalPath(const AUri: string): string;
var
  S : string;
begin
  Result := AUri;
  if not AUri.StartsWith('file://', True) then Exit;
  S := Copy(AUri, Length('file://') + 1, MaxInt);
  // file:///d:/x -> fuehrenden '/' vor dem Laufwerksbuchstaben strippen
  if (Length(S) >= 3) and (S[1] = '/') and (S[3] = ':') then
    Delete(S, 1, 1)
  else if (Length(S) >= 4) and (S[1] = '/') and (S[2] = '/') then
    ; // UNC (file://server/share) - '//' bleibt, wird unten zu '\\'
  S := PercentDecode(S);
  Result := StringReplace(S, '/', '\', [rfReplaceAll]);
end;

function SeverityToLsp(ASev: TLeakSeverity): Integer;
begin
  // LSP DiagnosticSeverity: 1=Error, 2=Warning, 3=Information, 4=Hint.
  case ASev of
    lsError:   Result := 1;
    lsWarning: Result := 2;
  else         Result := 4;   // lsHint -> Hint
  end;
end;

function BuildDiagnostics(const AUri, AText: string): TJSONArray;
var
  Req   : TScanRequest;
  Ses   : TAnalysisSession;
  Res   : TScanResult;
  F     : TLeakFinding;
  Diag  : TJSONObject;
  Range : TJSONObject;
  SPos  : TJSONObject;
  EPos  : TJSONObject;
  L     : Integer;
begin
  // Result erst NACH gelungenem Engine-Lauf anlegen: wirft Ses.Run
  // (z.B. volles %TEMP% beim ssSource-Tempfile), propagiert die
  // Exception - ein hier schon erzeugtes Array waere verwaist. Der
  // LSP-Server ist der einzige Consumer, der wochenlang im selben
  // Prozess lebt, und der Server faengt und loggt nur: das Leck kaeme
  // PRO TASTENDRUCK wieder (G7-4).
  Result := nil;

  Req := TScanRequest.Init;
  Req.Scope   := ssSource;
  Req.Source  := AText;
  Req.Path    := UriToLogicalPath(AUri);  // logischer Name der Findings
  Req.Profile := LSP_PROFILE;

  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    Result := TJSONArray.Create;   // ab hier besitzt der Aufrufer
    try
      for F in Res.Findings do
      begin
        // LSP ist 0-basiert; Engine-Zeilen sind 1-basiert (LineNumber '0'
        // nur bei Datei-Level-Findings wie fkFileReadError -> Zeile 0).
        L := F.LineInt - 1;
        if L < 0 then L := 0;

        // TODO E3: Spalte konstant 1 (character 0) - TLeakFinding hat noch
        // kein StartCol/EndCol (Doku_06, Engine-Aenderung E3, groesster
        // Einzel-Hebel fuer LSP-Qualitaet). Bis dahin Ganz-Zeilen-Range:
        // end.character = 2147483647 laesst den Client die Range am
        // tatsaechlichen Zeilenende clippen (uebliche LSP-Konvention).
        SPos := TJSONObject.Create;
        SPos.AddPair('line',      TJSONNumber.Create(L));
        SPos.AddPair('character', TJSONNumber.Create(0));
        EPos := TJSONObject.Create;
        EPos.AddPair('line',      TJSONNumber.Create(L));
        EPos.AddPair('character', TJSONNumber.Create(2147483647));
        Range := TJSONObject.Create;
        Range.AddPair('start', SPos);
        Range.AddPair('end',   EPos);

        Diag := TJSONObject.Create;
        Diag.AddPair('range',    Range);
        Diag.AddPair('severity', TJSONNumber.Create(SeverityToLsp(F.Severity)));
        Diag.AddPair('code',     F.ResolvedRuleId);   // SCAxxx bzw. Custom-ID
        Diag.AddPair('source',   LSP_SOURCE);
        Diag.AddPair('message',  F.MissingVar);       // = F.Message (Alias)
        Result.Add(Diag);
      end;
    finally
      Res.Free;
    end;
  finally
    Ses.Free;
  end;
end;

end.
