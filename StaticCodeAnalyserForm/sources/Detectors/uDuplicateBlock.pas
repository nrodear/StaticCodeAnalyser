unit uDuplicateBlock;

// Detektor fuer duplizierte Code-Bloecke innerhalb einer Datei.
//
// Algorithmus (zeilenbasiert, sliding window):
//   1. Datei zeilenweise einlesen
//   2. Jede Zeile normalisieren: trim, lowercase, mehrfaches Whitespace
//      auf ein Leerzeichen reduzieren
//   3. Triviale Zeilen ueberspringen: leer, 'begin', 'end', 'end;', 'else',
//      'try', 'finally', 'except', reine //- oder { }-Kommentare
//   4. Sliding-Window von DetectorMinBlockLines Zeilen, jedes Fenster als
//      Schluessel in einer Hash-Map sammeln
//   5. Schluessel mit >= 2 Vorkommen sind Duplikate -> melden
//
// Pro Block wird nur EINMAL gemeldet (Erst-Vorkommen, nicht ueberlappende
// Folge-Fenster). Suppression via // noinspection wird vom uSuppression-
// Modul automatisch nachgelagert.
//
// Schwelle: DetectorMinBlockLines = 8 normalisierte Zeilen. Das filtert Standard-
// Boilerplate (Property-Getter o.ae.) zuverlaessig aus.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDuplicateBlockDetector = class
  public
    // UnitNode wird nicht verwendet, der Detektor liest die Datei selbst.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function NormalizeLine(const S: string): string; static;
    class function IsTrivial(const NormalizedLine: string): Boolean; static;
    // True wenn der Block aus zu viel if/end-Boilerplate besteht
    // (Branching-Code mit wenig Substanz - kein lohnenswerter Refactor).
    class function IsBranchingBoilerplate(Lines: TStringList;
      OriginalFromLine, OriginalToLine: Integer): Boolean; static;
  end;

implementation

// Min-Block-Lines kommt aus uSCAConsts.DetectorMinBlockLines
// (analyser.ini -> DuplicateBlockMinLines). Default 8.

const
  TRIVIAL_LINES : array[0..11] of string = (
    '', 'begin', 'end', 'end;', 'else', 'then', 'do',
    'try', 'finally', 'except', 'repeat', 'until'
  );

class function TDuplicateBlockDetector.NormalizeLine(const S: string): string;
// trim + lowercase + whitespace-Kollaps in einem Pass.
var
  i        : Integer;
  PrevSp   : Boolean;
  c        : Char;
  SB       : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    PrevSp := True; // unterdrueckt fuehrendes Whitespace
    for i := 1 to Length(S) do
    begin
      c := S[i];
      if (c = #9) or (c = ' ') then
      begin
        if not PrevSp then
        begin
          SB.Append(' ');
          PrevSp := True;
        end;
      end
      else
      begin
        if (c >= 'A') and (c <= 'Z') then
          c := Char(Ord(c) + 32);
        SB.Append(c);
        PrevSp := False;
      end;
    end;
    Result := SB.ToString;
    // trailing space wegtrimmen (kann vorkommen wenn die Zeile mit Whitespace endet)
    if (Length(Result) > 0) and (Result[Length(Result)] = ' ') then
      SetLength(Result, Length(Result) - 1);
  finally
    SB.Free;
  end;
end;

class function TDuplicateBlockDetector.IsTrivial(
  const NormalizedLine: string): Boolean;
var
  T: string;
begin
  for T in TRIVIAL_LINES do
    if NormalizedLine = T then Exit(True);
  // Reine Kommentar-Zeilen sind ebenfalls trivial fuer die Block-Erkennung
  if NormalizedLine.StartsWith('//') then Exit(True);
  if NormalizedLine.StartsWith('{') and NormalizedLine.EndsWith('}') then
    Exit(True);
  Result := False;
end;

class function TDuplicateBlockDetector.IsBranchingBoilerplate(
  Lines: TStringList; OriginalFromLine, OriginalToLine: Integer): Boolean;
// Pruefen ob mehr als IF_END_RATIO der Original-Zeilen reines if/end sind.
// Solche Bloecke sind typische Defensive-Code-Boilerplate (Validations-Kette,
// Switch-Stub) - wertlos zu extrahieren, weil die Logik PRO Methode anders ist.
const
  IF_END_RATIO = 0.5; // ab 50% if/end-Anteil ueberspringen
var
  i, Total, IfEnd : Integer;
  Norm            : string;
begin
  Total := 0;
  IfEnd := 0;
  for i := OriginalFromLine - 1 to OriginalToLine - 1 do
  begin
    if (i < 0) or (i >= Lines.Count) then Continue;
    Norm := NormalizeLine(Lines[i]);
    if Norm = '' then Continue; // Leerzeilen nicht zaehlen
    Inc(Total);
    if Norm.StartsWith('if ') or
       Norm.StartsWith('else if ') or
       (Norm = 'else') or
       (Norm = 'end') or
       (Norm = 'end;') or
       Norm.StartsWith('end ') or
       Norm.StartsWith('end;') then
      Inc(IfEnd);
  end;
  if Total = 0 then Exit(False);
  Result := (IfEnd / Total) >= IF_END_RATIO;
end;

class procedure TDuplicateBlockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Normalized  : TArray<string>;
  LineIndex   : TArray<Integer>;
  // TObjectDictionary mit doOwnsValues raeumt die TList<Integer>-Values
  // automatisch beim Free auf - keine eigene Cleanup-Schleife noetig.
  Hashes      : TObjectDictionary<string, TList<Integer>>;
  Reported    : TDictionary<Integer, Boolean>;
  i, NCount   : Integer;
  Window      : string;
  Indices     : TList<Integer>;
  Pair        : TPair<string, TList<Integer>>;
  F           : TLeakFinding;
  FirstLine   : Integer;
  Norm        : string;
begin
  if not FileExists(FileName) then Exit;

  Lines    := TStringList.Create;
  Hashes   := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  Reported := TDictionary<Integer, Boolean>.Create;
  try
    try
      Lines.LoadFromFile(FileName, TEncoding.UTF8);
    except
      try Lines.LoadFromFile(FileName); except Exit; end;
    end;

    if Lines.Count < DetectorMinBlockLines * 2 then Exit;

    // Pass 1: Normalisieren + triviale Zeilen rausfiltern
    SetLength(Normalized, Lines.Count);
    SetLength(LineIndex,  Lines.Count);
    NCount := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      Norm := NormalizeLine(Lines[i]);
      if IsTrivial(Norm) then Continue;
      Normalized[NCount] := Norm;
      LineIndex[NCount]  := i + 1; // 1-basierte Zeilennummer
      Inc(NCount);
    end;

    if NCount < DetectorMinBlockLines * 2 then Exit;

    // Pass 2: Sliding window, Hash je DetectorMinBlockLines-Tupel
    for i := 0 to NCount - DetectorMinBlockLines do
    begin
      Window := '';
      for var j := 0 to DetectorMinBlockLines - 1 do
        Window := Window + Normalized[i + j] + #10;

      if not Hashes.TryGetValue(Window, Indices) then
      begin
        Indices := TList<Integer>.Create;
        Hashes.Add(Window, Indices);
      end;
      Indices.Add(i);
    end;

    // Pass 3: Duplikate melden, dabei ueberlappende Folge-Fenster
    // unterdruecken (nur Erst-Vorkommen pro Block) UND Bloecke skippen
    // die ueberwiegend aus if/end-Boilerplate bestehen.
    for Pair in Hashes do
    begin
      if Pair.Value.Count < 2 then Continue;

      FirstLine := LineIndex[Pair.Value[0]];
      if Reported.ContainsKey(FirstLine) then Continue;
      Reported.Add(FirstLine, True);

      // Original-Zeilenbereich des Erst-Vorkommens ermitteln und auf
      // if/end-Anteil pruefen. Bei zu viel Boilerplate skippen.
      var EndIdx := Pair.Value[0] + DetectorMinBlockLines - 1;
      if EndIdx >= NCount then EndIdx := NCount - 1;
      var OrigEndLine := LineIndex[EndIdx];
      if IsBranchingBoilerplate(Lines, FirstLine, OrigEndLine) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(FirstLine);
      F.MissingVar := Format(
        'Code block (%d lines) appears %dx in file - consider extracting a method',
        [DetectorMinBlockLines, Pair.Value.Count]);
      F.Severity   := lsHint;
      F.Kind       := fkDuplicateBlock;
      Results.Add(F);
    end;
  finally
    Hashes.Free;     // doOwnsValues: gibt alle TList<Integer> mit frei
    Reported.Free;
    Lines.Free;
  end;
end;

end.
