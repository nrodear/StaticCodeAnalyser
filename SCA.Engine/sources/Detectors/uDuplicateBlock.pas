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
// Pro dupliziertem Block wird genau EINMAL gemeldet, mit dem Bereich ueber
// den GANZEN Block (TLeakFinding.LineNumber = erste Zeile, .EndLine =
// letzte). "Derselbe Block" heisst dabei: gleiche Vorkommens-Signatur -
// zwei Duplikat-Gruppen, deren Erst-Vorkommen sich zufaellig ueberlappen,
// bleiben zwei Befunde.
//
// ACHTUNG, historisch: dieser Satz stand hier schon, war aber bis 2026-08-02
// FALSCH. Das Fenster wandert Zeile fuer Zeile durch den Block; jede
// Position ist ein anderer Hash und meldete an ihrer eigenen Anfangszeile.
// Ein duplizierter Block von K Zeilen erzeugte damit K - MinBlk + 1
// Befunde. Der damalige Reported-Filter war nach der Anfangszeile
// verschluesselt und konnte das prinzipiell nicht fangen. Erst Pass 3c
// (sortieren, dann ueberlappende Fenster verschmelzen) macht die Zusage
// wahr - siehe Kommentar dort.
//
// Suppression via // noinspection wird vom uSuppression-Modul automatisch
// nachgelagert.
//
// Schwelle: DetectorMinBlockLines = 8 normalisierte Zeilen. Das filtert Standard-
// Boilerplate (Property-Getter o.ae.) zuverlaessig aus.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults,          // TComparer fuer die Kandidaten-Sortierung
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

type
  // Ein Fenster-Treffer VOR dem Verschmelzen (Pass 3a -> 3c).
  TDupCandidate = record
    FirstLine : Integer;   // erste Original-Zeile des Fensters
    EndLine   : Integer;   // letzte Original-Zeile des Fensters
    Occurs    : Integer;   // wie oft dieses Fenster in der Datei vorkommt
    // Abstaende der weiteren Vorkommen zum ersten, als Text. Identisch
    // fuer alle Fenster DESSELBEN duplizierten Blocks, verschieden fuer
    // andere Duplikat-Gruppen - siehe Pass 3a.
    Sig       : string;
  end;

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

function DupGroupSignature(Indices: TList<Integer>): string;
// Gruppen-Signatur: die ABSTAENDE der Vorkommen zum ersten.
//
// Wandert das Fenster um t Positionen durch EINEN duplizierten Block,
// verschieben sich ALLE seine Vorkommen um dasselbe t - die Abstaende
// bleiben also identisch. Gleiche Signatur heisst damit beweisbar
// "Verschiebung desselben Blocks"; unterschiedliche Signatur heisst
// "andere Duplikat-Gruppe", auch wenn die Zeilen sich ueberlappen.
var
  SB : TStringBuilder;
  m  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for m := 1 to Indices.Count - 1 do
    begin
      SB.Append(Indices[m] - Indices[0]);
      SB.Append(',');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure DupMergeRuns(Cands, Runs: TList<TDupCandidate>);
// Verschmilzt die Fenster EINES Blocks zu je einem Lauf.
//
// ZWEI Bedingungen, nicht eine:
//   1. gleiche SIGNATUR - es ist derselbe duplizierte Block
//   2. Zeilen-UEBERLAPPUNG - die Fenster liegen wirklich ineinander
//
// Bedingung 1 ist nicht optional. Ein rein geometrisches Verschmelzen
// schluckt eigenstaendige Duplikat-Gruppen, deren Erst-Vorkommen zufaellig
// ineinander liegen: deren Partnerstellen stehen woanders in der Datei und
// verschwinden dann komplett aus dem Bericht. Ausserdem gilt Occurs des
// Ankers dann nicht mehr fuer den ganzen Lauf - gemessen an Unit1.pas
// verschmolz ein Lauf drei Gruppen mit 2/9/10 Vorkommen und meldete "2x".
// Mit Signatur-Gleichheit haben alle Mitglieder eines Laufs per
// Konstruktion dieselbe Vorkommenszahl, und der unveraenderte Meldetext
// des Ankers bleibt korrekt (SARIF-Fingerprint-Stabilitaet).
//
// Cands MUSS nach (Sig, FirstLine) sortiert sein.
var
  i, k : Integer;
begin
  i := 0;
  while i < Cands.Count do
  begin
    var AccFirst := Cands[i].FirstLine;
    var AccEnd   := Cands[i].EndLine;
    var AccSig   := Cands[i].Sig;
    var AccOccurs := Cands[i].Occurs;
    k := i + 1;
    while (k < Cands.Count) and (Cands[k].Sig = AccSig)
          and (Cands[k].FirstLine <= AccEnd) do
    begin
      if Cands[k].EndLine > AccEnd then AccEnd := Cands[k].EndLine;
      Inc(k);
    end;

    var R : TDupCandidate;
    R.FirstLine := AccFirst;
    R.EndLine   := AccEnd;
    R.Occurs    := AccOccurs;
    R.Sig       := '';
    Runs.Add(R);

    i := k;
  end;
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
  // Kandidaten VOR dem Verschmelzen. Ersetzt den frueheren Reported-Filter,
  // der ueberlappende Folge-Fenster nicht fangen konnte (Pass 3c).
  Cands       : TList<TDupCandidate>;
  // Verschmolzene Laeufe - je Lauf genau ein Befund (Pass 3c -> 3d).
  Runs        : TList<TDupCandidate>;
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
  Cands    := TList<TDupCandidate>.Create;
  Runs     := TList<TDupCandidate>.Create;
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

    // Pass 3a: Kandidaten sammeln. Ein Fenster kommt nur durch, wenn es
    // mehrfach vorkommt und keines der beiden Boilerplate-Gates greift.
    for Pair in Hashes do
    begin
      if Pair.Value.Count < 2 then Continue;

      FirstLine := LineIndex[Pair.Value[0]];

      // Original-Zeilenbereich des Erst-Vorkommens ermitteln und auf
      // if/end-Anteil pruefen. Bei zu viel Boilerplate skippen.
      var EndIdx := Pair.Value[0] + MinBlk - 1;
      if EndIdx >= NCount then EndIdx := NCount - 1;
      var OrigEndLine := LineIndex[EndIdx];
      if IsBranchingBoilerplate(Lines, FirstLine, OrigEndLine) then Continue;
      // Deklarations-Boilerplate (Audit 2026-07-31): property-Listen und
      // Parameterlisten im Routinenkopf sind sprachlich erzwungen.
      if IsDeclarationBoilerplate(Lines, FirstLine, OrigEndLine) then Continue;

      var C : TDupCandidate;
      C.FirstLine := FirstLine;
      C.EndLine   := OrigEndLine;
      C.Occurs    := Pair.Value.Count;
      // Gruppen-Signatur: die ABSTAENDE der Vorkommen zum ersten Vorkommen.
      //
      // Wandert das Fenster um t Positionen durch EINEN duplizierten Block,
      // verschieben sich ALLE seine Vorkommen um dasselbe t - die Abstaende
      // bleiben also identisch. Zwei Fenster mit gleicher Signatur sind
      // damit garantiert Verschiebungen DESSELBEN Blocks; unterschiedliche
      // Signatur heisst: andere Duplikat-Gruppe, auch wenn die Zeilen sich
      // ueberlappen.
      //
      // Genau daran haengt, dass beim Verschmelzen kein fremdes Duplikat
      // verschluckt wird und dass Occurs des Ankers fuer den ganzen Lauf
      // gilt - alle Mitglieder eines Laufs haben per Konstruktion dieselbe
      // Vorkommenszahl.
      C.Sig := DupGroupSignature(Pair.Value);
      Cands.Add(C);
    end;

    // Pass 3b: nach (Signatur, Anfangszeile) sortieren. ZWINGEND vor dem
    // Verschmelzen: die Iteration ueber Hashes ist ungeordnet, ein
    // Verschmelzen in Hash-Reihenfolge waere von Lauf zu Lauf verschieden -
    // und damit die Ausgabe nicht reproduzierbar. Die Signatur gruppiert
    // zusaetzlich die Fenster EINES Blocks zusammen.
    Cands.Sort(TComparer<TDupCandidate>.Construct(
      function(const A, B: TDupCandidate): Integer
      begin
        Result := CompareStr(A.Sig, B.Sig);
        if Result = 0 then Result := A.FirstLine - B.FirstLine;
        if Result = 0 then Result := A.EndLine - B.EndLine;
      end));

    // Pass 3c: die Fenster EINES Blocks zu EINEM Befund verschmelzen.
    //
    // Bis hierher erzeugte ein duplizierter Block von K Zeilen genau
    // K - MinBlk + 1 Befunde: das Fenster wandert Zeile fuer Zeile durch
    // den Block, jede Position ist ein anderer Hash und meldet an ihrer
    // eigenen Anfangszeile. Der alte Reported-Filter war nach FirstLine
    // verschluesselt und konnte das nicht fangen - er verhinderte nur, dass
    // zwei VERSCHIEDENE Hashes mit DERSELBEN Anfangszeile doppelt melden.
    // Der Kopfkommentar behauptete trotzdem, Folge-Fenster wuerden
    // unterdrueckt.
    //
    // Gemessen an Alcinoe/ALDatabaseBenchmark/Unit1.pas: 218 Befunde, davon
    // 193 (89 %) blosse Fensterverschiebungen. Eine einzige Klassen-
    // Deklaration trug 18 Hinweise uebereinander.
    //
    // ZWEI Bedingungen, nicht eine:
    //   1. gleiche SIGNATUR - es ist derselbe duplizierte Block
    //   2. Zeilen-UEBERLAPPUNG - die Fenster liegen wirklich ineinander
    //
    // Bedingung 1 ist nicht optional. Ein rein geometrisches Verschmelzen
    // ("Zeilen ueberlappen sich") schluckt eigenstaendige Duplikat-Gruppen,
    // deren Erst-Vorkommen zufaellig ineinander liegen: deren Partnerstellen
    // stehen ganz woanders in der Datei und verschwinden dann komplett aus
    // dem Bericht. Ausserdem gilt Occurs des Ankers dann nicht mehr fuer den
    // ganzen Lauf - ein Block, der 12x vorkommt, wuerde als "2x" gemeldet,
    // weil das linkeste Fenster zufaellig nur zwei Vorkommen hat. Mit
    // Signatur-Gleichheit haben alle Mitglieder eines Laufs per Konstruktion
    // dieselbe Vorkommenszahl.
    //
    // Ein Duplikat ist EIN Befund ueber den GANZEN Block. Der Anker bleibt
    // die erste Zeile, der Bereich waechst bis zum Ende des letzten
    // ueberlappenden Fensters derselben Gruppe.
    DupMergeRuns(Cands, Runs);

    // Pass 3d: Befunde in Datei-Reihenfolge ausgeben. Nach Signatur
    // gruppiert liegen die Laeufe sonst in Hash-Reihenfolge im Ergebnis -
    // fachlich egal, aber die Ausgabereihenfolge soll nachvollziehbar der
    // Datei folgen und zwischen Laeufen stabil sein.
    Runs.Sort(TComparer<TDupCandidate>.Construct(
      function(const A, B: TDupCandidate): Integer
      begin
        Result := A.FirstLine - B.FirstLine;
        if Result = 0 then Result := A.EndLine - B.EndLine;
      end));

    for i := 0 to Runs.Count - 1 do
    begin
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Runs[i].FirstLine);
      // Ein Duplikat ist per Definition ein BLOCK - der Befund umfasst
      // FirstLine..EndLine, nicht nur die Anfangszeile.
      F.EndLine    := Runs[i].EndLine;
      // Der Text nennt jetzt den ECHTEN Quelltext-Bereich.
      //
      // Vorher stand dort nur "(%d lines)" mit MinBlk - der Fenstergroesse
      // im NORMALISIERTEN Strom, aus dem Leerzeilen und Kommentare bereits
      // entfernt sind. Der markierte Bereich ist deshalb immer groesser,
      // und die Meldung widersprach sichtbar der Markierung: "8 lines" bei
      // 21 markierten Zeilen.
      //
      // PREIS, bewusst bezahlt: der SARIF-Fingerprint ist ein Hash ueber
      // RuleID + Pfad + Zeile + MELDUNG. Alle 9.148 SCA021-Funde des
      // Referenzkorpus bekommen damit einen neuen Fingerprint und laufen in
      // bestehenden Baselines einmalig als "neu" auf. Das gehoert in die
      // Release-Notes, nicht in einen Nebensatz.
      F.MissingVar := Format(
        'Code block (lines %d-%d, %d matched lines) appears %dx in file - ' +
        'consider extracting a method',
        [Runs[i].FirstLine, Runs[i].EndLine, MinBlk, Runs[i].Occurs]);
      F.SetKind(fkDuplicateBlock);
      Results.Add(F);
    end;
  finally
    Hashes.Free;     // doOwnsValues: gibt alle TList<Integer> mit frei
    Cands.Free;
    Runs.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
