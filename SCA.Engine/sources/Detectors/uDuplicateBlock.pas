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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TDuplicateBlockDetector = class
  public
    // UnitNode wird nicht verwendet, der Detektor liest die Datei selbst.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    class function NormalizeLine(const S: string): string; static;
    class function IsTrivial(const NormalizedLine: string): Boolean; static;
    // True wenn der Block aus zu viel if/end-Boilerplate besteht
    // (Branching-Code mit wenig Substanz - kein lohnenswerter Refactor).
    class function IsBranchingBoilerplate(Lines: TStringList;
      OriginalFromLine, OriginalToLine: Integer): Boolean; static;
    // True wenn der Block DEKLARATIONS-Boilerplate ist, bei dem
    // 'extract a method' sprachlich unmoeglich ist - siehe
    // Implementations-Kommentar (30%-Audit 2026-07-31).
    class function IsDeclarationBoilerplate(Lines: TStringList;
      OriginalFromLine, OriginalToLine: Integer): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

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

// ===========================================================================
// DEKLARATIONS-BOILERPLATE (30%-Real-World-Audit 2026-07-31: 44.709 Funde,
// 12 % FP im Sample; die FP waren AUSNAHMSLOS diese beiden Klassen).
//
// Der Detektor arbeitet rein lexikalisch und kennt keinen Kontext. Zwei
// Sorten von Wiederholung sind in Delphi SPRACHLICH ERZWUNGEN - dort ist
// die Empfehlung 'extract a method' nicht bloss unpassend, sondern
// unmoeglich:
//
//   A) published-property-Redeklarationslisten in Komponentenklassen:
//        property Visible;
//        property OnClick;
//        property OnDblClick;
//      Das Wiederholen IST der Mechanismus, mit dem eine Ableitung
//      geerbte Properties published macht. Es gibt nichts zu extrahieren.
//
//   B) Parameterlisten im Routinen-KOPF. Delphi verlangt die Wiederholung
//      der vollstaendigen Liste in Deklaration UND Implementierung; bei
//      langen Listen verwandter Routinen erreichen die Zeilen die
//      Acht-Zeilen-Schwelle.
//
// Korpus-Messung (after128): A 2.757, B 508 von 44.709.
//
// BEWUSST NICHT GEGATET: Feld- und var-Listen (744 Funde). Die sehen wie
// B aus, stehen aber NICHT in einer offenen Klammer - zwei Klassen mit
// identischer Feldliste sind eine echte Copy-Paste-Spur, auch wenn der
// Fix-Vorschlag dort ebenfalls unpassend ist. Das Audit nennt sie nicht;
// ohne Beleg kein Gate. Genau deshalb steht die Klammerbilanz in der
// Bedingung und nicht bloss die Zeilenform.
// ===========================================================================

function DupIsPropertyLine(const Norm: string): Boolean;
begin
  Result := Norm.StartsWith('property ');
end;

function DupLooksLikeDeclLine(const Norm: string): Boolean;
// '<ident>[, <ident>]* : <typ>[;][)]', optional mit const/var/out davor.
// Kein ':=' (das waere Code), keine Klammer vor dem ':' (das waere ein
// Aufruf).
var
  S : string;
  p : Integer;
begin
  Result := False;
  S := Norm;
  if S.StartsWith('const ') then S := Copy(S, 7, MaxInt)
  else if S.StartsWith('var ') then S := Copy(S, 5, MaxInt)
  else if S.StartsWith('out ') then S := Copy(S, 5, MaxInt);
  if Pos(':=', S) > 0 then Exit;
  p := Pos(':', S);
  if p <= 1 then Exit;
  // Links vom ':' nur Bezeichner, Kommas und Leerzeichen.
  for var i := 1 to p - 1 do
    if not (CharInSet(S[i], ['a'..'z', '0'..'9', '_', ',', ' '])) then Exit;
  Result := True;
end;

function DupRoutineHeadAbove(Lines: TStringList;
  ABlockLine, ALookback: Integer): Integer;
// Index der naechsten Zeile oberhalb, die ein Routinen-Schluesselwort
// traegt; -1 wenn keine im Fenster liegt.
var
  i, StopIdx : Integer;
  Low        : string;
begin
  Result  := -1;
  StopIdx := ABlockLine - 1 - ALookback;
  if StopIdx < 0 then StopIdx := 0;
  for i := ABlockLine - 1 downto StopIdx do
  begin
    if (i < 0) or (i >= Lines.Count) then Continue;
    Low := LowerCase(Lines[i]);
    if (Pos('procedure', Low) > 0) or (Pos('function', Low) > 0) or
       (Pos('constructor', Low) > 0) or (Pos('destructor', Low) > 0) then
      Exit(i);
  end;
end;

procedure DupAddParens(const ALine: string; var ADepth: Integer);
// Klammerbilanz einer Zeile auf ADepth aufaddieren; nie unter null.
begin
  for var c in ALine do
    if c = '(' then Inc(ADepth)
    else if c = ')' then
    begin
      Dec(ADepth);
      if ADepth < 0 then ADepth := 0;
    end;
end;

function DupParenDepthBefore(Lines: TStringList; ABlockLine: Integer): Integer;
// Klammertiefe am Blockanfang, gerechnet ab dem naechsten Routinen-KOPF
// darueber (hoechstens 40 Zeilen zurueck). > 0 heisst: der Block steht
// INNERHALB einer Parameterliste.
//
// GRENZE DER HEURISTIK, bei der Messung 2026-08-01 gefunden: sie
// unterscheidet nicht zwischen einer Parameterliste und IRGENDEINEM
// geklammerten Bereich unterhalb eines Routinen-Schluesselworts. Im Korpus
// traf das genau zweimal zu - beide Male eine typisierte Konstanten-Tabelle
// (HeidiSQL dbstructures.mssql.pas, 'array of TDBDatatype = ((Index: ...;
// Name: ...), ...)'). Dort ist die Unterdrueckung inhaltlich RICHTIG
// (Datenzeilen, keine extrahierbare Methode), aber sie geschieht aus
// Zufall, nicht aus Absicht. Wer die Heuristik verschaerft, muss diese
// zwei Faelle bewusst mitnehmen - sonst kehren sie als FP zurueck.
const
  LOOKBACK = 40;
var
  i, StartIdx, Depth : Integer;
begin
  Result   := 0;
  StartIdx := DupRoutineHeadAbove(Lines, ABlockLine, LOOKBACK);
  if StartIdx < 0 then Exit;
  Depth := 0;
  for i := StartIdx to ABlockLine - 2 do
    if (i >= 0) and (i < Lines.Count) then
      DupAddParens(Lines[i], Depth);
  Result := Depth;
end;

procedure DupTallyLine(const ANorm: string;
  var ATotal, AProps, ADecls: Integer; var AHasCode: Boolean);
// Eine normalisierte Zeile in die vier Zaehler einsortieren. Ausgelagert,
// weil der eigene Detektor die Sammelschleife sonst mit Komplexitaet 18
// meldet (Limit 15) - Dogfooding.
begin
  Inc(ATotal);
  if DupIsPropertyLine(ANorm) then Inc(AProps);
  if DupLooksLikeDeclLine(ANorm) then Inc(ADecls);
  if (Pos(':=', ANorm) > 0) or ANorm.StartsWith('begin') then AHasCode := True;
end;

class function TDuplicateBlockDetector.IsDeclarationBoilerplate(
  Lines: TStringList; OriginalFromLine, OriginalToLine: Integer): Boolean;
const
  PROPERTY_RATIO = 0.5;    // Haelfte der Zeilen 'property ...'
  DECL_RATIO     = 0.75;   // drei Viertel Deklarationszeilen
var
  i, Total, Props, Decls : Integer;
  HasCode : Boolean;
  Norm    : string;
begin
  Result  := False;
  Total   := 0;
  Props   := 0;
  Decls   := 0;
  HasCode := False;
  for i := OriginalFromLine - 1 to OriginalToLine - 1 do
  begin
    if (i < 0) or (i >= Lines.Count) then Continue;
    Norm := NormalizeLine(Lines[i]);
    if IsTrivial(Norm) then Continue;
    DupTallyLine(Norm, Total, Props, Decls, HasCode);
  end;
  if Total = 0 then Exit;

  // A: published-property-Redeklaration.
  if (Props / Total) >= PROPERTY_RATIO then Exit(True);

  // B: Parameterliste im Routinenkopf - Zeilenform UND offene Klammer.
  if (not HasCode) and ((Decls / Total) >= DECL_RATIO) and
     (DupParenDepthBefore(Lines, OriginalFromLine) > 0) then
    Exit(True);
end;

class procedure TDuplicateBlockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  Cached      : Boolean;
  MinBlk      : Integer;   // TD-1: Schwelle per-Scan aus AContext.Config
begin
  // TD-1 (2026-07-06): Min-Block-Lines einmal aus dem Context lesen (byte-
  // identisch - scan-konstant) und in allen Fenster-/Format-Stellen nutzen.
  MinBlk := CfgMinBlockLines(AContext);
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  Hashes   := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  Reported := TDictionary<Integer, Boolean>.Create;
  try
    if Lines.Count < MinBlk * 2 then Exit;

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

    if NCount < MinBlk * 2 then Exit;

    // Pass 2: Sliding window, Hash je DetectorMinBlockLines-Tupel
    for i := 0 to NCount - MinBlk do
    begin
      Window := '';
      for var j := 0 to MinBlk - 1 do
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
      var EndIdx := Pair.Value[0] + MinBlk - 1;
      if EndIdx >= NCount then EndIdx := NCount - 1;
      var OrigEndLine := LineIndex[EndIdx];
      if IsBranchingBoilerplate(Lines, FirstLine, OrigEndLine) then Continue;
      // Deklarations-Boilerplate (Audit 2026-07-31): property-Listen und
      // Parameterlisten im Routinenkopf sind sprachlich erzwungen.
      if IsDeclarationBoilerplate(Lines, FirstLine, OrigEndLine) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(FirstLine);
      // Ein Duplikat ist per Definition ein BLOCK - der Befund umfasst
      // FirstLine..OrigEndLine, nicht nur die Anfangszeile. OrigEndLine
      // wird oben ohnehin schon fuer die beiden Boilerplate-Gates
      // gebraucht; hier wird sie nur nicht mehr weggeworfen.
      //
      // ACHTUNG: das bleibt EIN Fund. Der Bereich steuert nur, wieviele
      // Zeilen der Editor markiert (Konzept_MehrzeiligeFundmarkierung).
      F.EndLine    := OrigEndLine;
      F.MissingVar := Format(
        'Code block (%d lines) appears %dx in file - consider extracting a method',
        [MinBlk, Pair.Value.Count]);
      F.SetKind(fkDuplicateBlock);
      Results.Add(F);
    end;
  finally
    Hashes.Free;     // doOwnsValues: gibt alle TList<Integer> mit frei
    Reported.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
