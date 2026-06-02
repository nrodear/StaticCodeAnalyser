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
  System.SysUtils,
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
    class function ContextHashFor(const FileName: string; LineNo: Integer;
      Radius: Integer = CONTEXT_HASH_RADIUS): string; static;

    // Normalisierungs-Helper (public fuer Tests):
    // Tabs -> Space, kollabiert Whitespace-Runs zu einem Space, trim,
    // verwirft leere Zeilen.
    class function Normalize(const Snippet: string): string; static;
  end;

implementation

uses
  System.Classes, System.Hash, System.StrUtils,
  uFileTextCache;

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
var
  SL    : TStringList;
  Out_  : TStringList;
  i, j  : Integer;
  Line  : string;
  Sb    : TStringBuilder;
  C     : Char;
  PrevWs: Boolean;
begin
  if Snippet = '' then Exit('');
  SL := TStringList.Create;
  Out_ := TStringList.Create;
  try
    SL.Text := Snippet;
    for i := 0 to SL.Count - 1 do
    begin
      // Tabs zu Space + WS-Run-Kollabierung
      Sb := TStringBuilder.Create;
      try
        PrevWs := True; // suppress leading WS
        Line := SL[i];
        for j := 1 to Length(Line) do
        begin
          C := Line[j];
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
        Line := Sb.ToString;
      finally
        Sb.Free;
      end;
      // Trailing-Space von Single-Trailing-Append abschneiden
      Line := TrimRight(Line);
      if Line <> '' then
        Out_.Add(Line);
    end;
    Result := string.Join(#10, Out_.ToStringArray);
  finally
    SL.Free;
    Out_.Free;
  end;
end;

class function TFindingFingerprint.ContextHashFor(const FileName: string;
  LineNo, Radius: Integer): string;
var
  Lines : TStringList;
  Cached: Boolean;
  Sb    : TStringBuilder;
  i, Lo, Hi : Integer;
  Snippet, Norm : string;
begin
  Result := '';
  if (FileName = '') or (LineNo < 1) or (Radius < 0) then Exit;

  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    if Lines.Count = 0 then Exit;
    Lo := LineNo - 1 - Radius;          // TStringList ist 0-basiert
    Hi := LineNo - 1 + Radius;
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

end.
