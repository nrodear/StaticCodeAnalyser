unit uFloatLiteralIdeCrash;

// Detektor FloatLiteralIdeCrash (SCA208, 2026-11-25): eine Unit mit einem
// Gleitkomma-Literal ('4.90', '0.5', '1e5', '1.5E-3') kann Delphi 12 zum
// Absturz bringen, sobald sie im Editor angezeigt wird. Der IDE-Parser fuer
// Code-Faltung und Error Insight JIT-kompiliert dabei
// Borland.Delphi.Scanner.GetReal; dort entsteht eine unmaskierte
// Gleitkomma-Ausnahme, und die IDE endet mit einem Stapelueberlauf in
// clr.dll (0xC00000FD). Ob es passiert, haengt zusaetzlich am x87-
// Steuerwort der IDE auf dem jeweiligen Rechner - die Regel findet daher
// nur Risiko-Dateien. Gemessen an Delphi 12.1 Community Edition, vor und
// nach Patch 1 (der verwaltete Parser Borland.Delphi.dll bleibt
// 29.0.51961.7529); bei Delphi 13 in einer Einzelbeobachtung nicht
// gesehen. Der Code der Datei ist korrekt: Hint, Code Smell,
// Konfidenz fcMedium (KindDefaultConfidence, wie SCA207: ob es bricht,
// entscheidet der Rechner). Standardmaessig AUS: nicht im Profil default,
// nur in strict und style (rules/sca-rules.json, Fallback uRuleCatalog).
//
// VERTRAG: hoechstens EIN Fund je Datei, an Zeile und Spalte des ERSTEN
// zaehlenden Literals (Zeile im Fund, Spalte 1-basiert in FixArgs.Col); die
// Meldung traegt das Literal wie geschrieben (englisch, Teil der Fund-
// Identitaet, wie die Format-Meldungen von SCA206/SCA207). Methode leer
// (Datei-Ebene).
//
// ERKENNUNG: die Token des SCA-Lexers (uLexer), Art tkFloatLit - NICHT
// tkFloat, das ist System.TTypeKind (Falle, s. uParser2). Damit gelten die
// Regeln von TLexer.ReadNumber: '1..5' ist Integer, '..', Integer; '$FF'
// ist ein Hex-Integer; '49 / 10' sind zwei Integer; Zahlen in Kommentaren
// und Zeichenketten ('4.90' in StrToFloat('4.90')) sind gar keine Token.
//
// "ZAEHLT DIESES TOKEN?" steht an EINER Stelle: LiteralCounts. Die Fakten
// dafuer (TFloatLiteralFacts) rechnet der Lauf je Kandidat aus. Die drei
// Randfaelle sind gegen die echte IDE gemessen (2026-11-25, 17 Laeufe, jeder
// "kein Absturz" mit Positivkontrolle in derselben Sitzung):
//   R1 Literal in einem {$IFDEF}-Zweig, den die Ein-Zweig-Sicht des Scans
//      abschaltet (Fakt InInactiveBranch): ZAEHLT - Absturz gemessen, mit
//      einer Ganzzahl im selben Zweig keiner. Der Editor zeigt jeden Zweig.
//      Ohne Ein-Zweig-Sicht (Doppelzweig, --no-ifdef-aware) ist der Fakt
//      immer False.
//   R2 Include-Dateien. Ein Literal, das nur in einer per {$I}/{$INCLUDE}
//      eingebundenen Datei steht (InIncludedFile), ZAEHLT fuer die
//      einbindende Unit - Absturz gemessen, wenn die UNIT angezeigt wird.
//      Der Fund steht an der Direktive, die Meldung nennt Literal, Datei
//      und Zeile. Ist die gescannte Datei selbst eine Include-Datei
//      (ScannedFileIsInclude), zaehlt NICHTS in ihr, auch nichts aus von
//      ihr eingebundenen Dateien: sie selbst anzuzeigen ist harmlos
//      (gemessen), das Risiko traegt die einbindende Unit. Include-Datei
//      heisst hier: Endung .inc - eine andere Endung erkennt die Regel
//      nicht als Include-Datei (eine per {$I} eingebundene .pas wird wie
//      eine Unit gemeldet).
//   R3 Methodenaufruf auf einem Ganzzahl-Literal ('5.ToString',
//      '5.Equals(5)'): der Lexer liest '5.' bzw. '5.E' als tkFloatLit
//      (er prueft hinter dem Punkt auf e/E). ZAEHLT NICHT - kein Absturz
//      gemessen. Kriterium: hinter dem Punkt keine Ziffer
//      (DotWithoutDigits) und direkt ab dem Punkt beginnt ein Bezeichner
//      (IdentAfterDot). '1.' ohne Bezeichner dahinter ('X := 1.;') ist
//      UNGEMESSEN und wird gemeldet; ebenso ungemessen ist '5.E5' (nach
//      dem Kriterium ein Aufruf, also nicht gemeldet).
// Aendert sich ein Befund, ist das eine Zeile in LiteralCounts; die Tests
// R1-R3 in uTestFloatLiteralIdeCrash ziehen dann mit.
//
// REIHENFOLGE: "erstes Literal" heisst in Leserichtung der gescannten
// Datei, eine Include-Direktive steht dabei fuer den Inhalt ihrer Datei.
//
// KOSTEN: ein Lexer-Lauf je Datei. Nur wenn ein Kandidat auftaucht UND der
// Scan eine Ein-Zweig-Sicht hat, kommt ein zweiter Lauf mit Zweig-Auswahl
// dazu (Fakt R1); Include-Dateien werden nur gelesen, wenn die Datei
// '$I' enthaelt und eine Direktive vor dem ersten zaehlenden Literal steht.
//
// GRENZEN (bewusst):
//   G1 Include-Dateien werden nur relativ zum Verzeichnis der einbindenden
//      Datei gesucht (ohne Endung zusaetzlich mit '.pas'), nicht ueber den
//      Suchpfad des Projekts; Tiefe hoechstens 3, Dateien ueber 1 MB
//      nicht (beides wie TLexer.ProcessIncludeDefines). Nicht gefunden =
//      nicht gemeldet.
//   G2 R1 rechnet mit den Defines der Scan-Sicht (gLexerIfdefDefines) je
//      Datei: ein {$DEFINE} aus einer Include-Datei wirkt nicht, und eine
//      Include-Datei sieht die Defines der einbindenden Datei nicht. Eine
//      Direktive in einem abgeschalteten Zweig vererbt den Fakt an alle
//      Literale ihrer Datei; das gilt nur fuer einzeilige Direktiven
//      (eine mehrzeilige gilt als aktiv).
//   G3 Delphi-12-Mehrzeilenstrings liest der Lexer als Zeichenkette - eine
//      Zahl darin zaehlt nicht.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  // Was ueber ein Gleitkomma-Literal bekannt ist, bevor LiteralCounts
  // entscheidet. Jeder Fakt gehoert zu einem Randfall (s. Kopf).
  TFloatLiteralFacts = record
    InInactiveBranch     : Boolean;  // R1: Zweig ist in der Scan-Sicht abgeschaltet
    InIncludedFile       : Boolean;  // R2: stammt aus einer per {$I} eingebundenen Datei
    ScannedFileIsInclude : Boolean;  // R2: die gescannte Datei ist selbst eine .inc
    DotWithoutDigits     : Boolean;  // R3: hinter dem Punkt keine Ziffer ('5.', '5.E')
    IdentAfterDot        : Boolean;  // R3: direkt ab dem Punkt beginnt ein Bezeichner
  end;

  // Der erste zaehlende Treffer einer Datei.
  TFloatLiteralHit = record
    Line        : Integer;   // 1-basiert, in der gescannten Datei (bei R2: die Direktive)
    Col         : Integer;   // 1-basiert, ebenso
    Text        : string;    // das Literal wie geschrieben
    Facts       : TFloatLiteralFacts;
    IncludeName : string;    // '' = direkt in der Datei; sonst Dateiname wie in der Direktive
    IncludeLine : Integer;   // Zeile des Literals in der Include-Datei (0 ohne Include)
  end;

  TFloatLiteralIdeCrashDetector = class
  public
    // DIE Entscheidung "zaehlt dieses Token?" - Ausnahmen fuer R1-R3 gehoeren
    // hierher und nirgends sonst.
    class function LiteralCounts(const AText: string;
      const AFacts: TFloatLiteralFacts): Boolean; static;
    // Erstes zaehlendes Literal von ASource (Inhalt von AFileName; dessen
    // Verzeichnis ist die Basis der {$I}-Aufloesung, dessen Endung der
    // Fakt ScannedFileIsInclude). False = kein zaehlendes Literal, kein Fund.
    class function FindFirstLiteral(const ASource, AFileName: string;
      out AHit: TFloatLiteralHit; AContext: TAnalyzeContext = nil): Boolean;
      static;
    // Meldung zum Treffer (englisch, Fund-Identitaet).
    class function MessageOf(const AHit: TFloatLiteralHit): string; static;
    // UnitNode bleibt ungenutzt (Dateitext-Detektor); die Signatur folgt
    // den anderen Detektoren.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.StrUtils, System.IOUtils,
  uLexer,           // TLexer/TToken (tkFloatLit), gLexerIfdef* = Ein-Zweig-Sicht
  uFileTextCache,
  uDetectorUtils,   // LinesTextCached - Ganztext aus dem Context-Slot
  uStaticFiles,     // IsUnitLikeFile - Dialekt-Endungen (.pp/.lpr bei dlFpc)
  uCrashDiag;       // IsFatalScanException (E3)

const
  // Wie TLexer.ProcessIncludeDefines: Include in Include hoechstens drei
  // Ebenen tief, Include-Dateien bis 1 MB.
  MAX_INCLUDE_DEPTH = 3;
  MAX_INCLUDE_CHARS = 1024 * 1024;
  // Platzhalter-Bezeichner fuer Include-Direktiven im Zweig-Lauf (R1).
  SENTINEL_CHAR = 'Z';
  MSG_TAIL = 'Delphi 12 may crash while showing this unit ' +
    '(IDE parser fault, clr.dll 0xC00000FD)';

type
  // Eine {$I}-/{$INCLUDE}-Direktive der Quelle.
  TIncludeRef = record
    Line     : Integer;   // Position der oeffnenden Klammer, 1-basiert
    Col      : Integer;
    StartIdx : Integer;   // 1-basierter Index der Klammer in der Quelle
    Len      : Integer;   // Laenge der Direktive samt Klammern
    Probed   : Boolean;   // einzeilig: im Zweig-Lauf durch einen Platzhalter vertreten
    Name     : string;    // Dateiname wie geschrieben, ohne Apostrophe
  end;

function PosKey(ALine, ACol: Integer): Int64;
begin
  Result := (Int64(ALine) shl 32) or Int64(Cardinal(ACol));
end;

function IsIncludeExt(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.inc');
end;

// Endungs-Gate wie SCA206 (uFormatterMarker.HasSourceExt).
function HasSourceExt(const AFileName: string): Boolean;
var
  Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc')
    or TStaticFiles.IsUnitLikeFile(AFileName);
end;

// Dateiname einer {$I}-/{$INCLUDE}-Direktive, '' fuer jede andere. ABody ist
// der Kommentarinhalt ohne Klammern und beginnt mit '$'. Keine Datei sind
// (wie bei TLexer) der IO-Pruefschalter {$I+}/{$I-}, FPC-Info-Includes
// {$I %DATE%} und Masken.
function IncludeNameOf(const ABody: string): string;
var
  k    : Integer;
  Verb : string;
begin
  Result := '';
  k := 2;
  while (k <= Length(ABody)) and CharInSet(ABody[k], ['A'..'Z', 'a'..'z']) do
    Inc(k);
  Verb := UpperCase(Copy(ABody, 2, k - 2));
  if (Verb <> 'I') and (Verb <> 'INCLUDE') then
    Exit;
  Result := Trim(Copy(ABody, k, MaxInt));
  if (Result = '') or CharInSet(Result[1], ['+', '-', '%', '*']) then
    Exit('');
  if (Length(Result) >= 2) and (Result[1] = '''')
     and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

// Alle Include-Direktiven der Quelle in Dateireihenfolge. Kommentar- und
// String-Regeln wie TLexer: '..' mit '' als Apostroph (auch ueber
// Zeilenenden, wie ReadString), // bis Zeilenende, { } bis zum ersten },
// (* *) bis zum ersten *). Ein offener Kommentar am Dateiende ist keine
// Direktive.
function FindIncludes(const ASource: string): TArray<TIncludeRef>;
var
  Refs                     : TArray<TIncludeRef>;
  Count, i, j, n           : Integer;
  Line, LineStart          : Integer;

  // Setzt i auf AStop (hoechstens hinter das Dateiende) und zaehlt die
  // Zeilenwechsel dazwischen.
  procedure MoveTo(AStop: Integer);
  begin
    if AStop > n + 1 then
      AStop := n + 1;
    while i < AStop do
    begin
      if ASource[i] = #10 then
      begin
        Inc(Line);
        LineStart := i + 1;
      end;
      Inc(i);
    end;
  end;

  // Kommentar ab i (Laenge ALen, Inhalt ab ABodyStart mit ABodyLen Zeichen):
  // eine Include-Direktive wird notiert.
  procedure Note(ALen, ABodyStart, ABodyLen: Integer);
  var
    Ref : TIncludeRef;
  begin
    if (ABodyLen < 1) or (ASource[ABodyStart] <> '$') then
      Exit;
    Ref.Name := IncludeNameOf(Copy(ASource, ABodyStart, ABodyLen));
    if Ref.Name = '' then
      Exit;
    Ref.Line     := Line;
    Ref.Col      := i - LineStart + 1;
    Ref.StartIdx := i;
    Ref.Len      := ALen;
    Ref.Probed   := Pos(#10, Copy(ASource, i, ALen)) = 0;
    if Count = Length(Refs) then
      SetLength(Refs, Count * 2 + 4);
    Refs[Count] := Ref;
    Inc(Count);
  end;

begin
  Refs  := nil;
  Count := 0;
  n     := Length(ASource);
  i     := 1;
  Line  := 1;
  LineStart := 1;
  while i <= n do
    case ASource[i] of
      #10:
        MoveTo(i + 1);
      '''':
        begin
          j := i + 1;
          while j <= n do
            if ASource[j] <> '''' then
              Inc(j)
            else if (j < n) and (ASource[j + 1] = '''') then
              Inc(j, 2)
            else
              Break;
          MoveTo(j + 1);
        end;
      '/':
        if (i < n) and (ASource[i + 1] = '/') then
        begin
          j := PosEx(#10, ASource, i);
          if j = 0 then
            j := n + 1;
          MoveTo(j);                 // das #10 zaehlt der naechste Schritt
        end
        else
          Inc(i);
      '{':
        begin
          j := PosEx('}', ASource, i + 1);
          if j = 0 then
            MoveTo(n + 1)
          else
          begin
            Note(j - i + 1, i + 1, j - i - 1);
            MoveTo(j + 1);
          end;
        end;
      '(':
        if (i < n) and (ASource[i + 1] = '*') then
        begin
          j := PosEx('*)', ASource, i + 2);
          if j = 0 then
            MoveTo(n + 1)
          else
          begin
            Note(j - i + 2, i + 2, j - i - 2);
            MoveTo(j + 2);
          end;
        end
        else
          Inc(i);
    else
      Inc(i);
    end;
  SetLength(Refs, Count);
  Result := Refs;
end;

function IsSentinel(const AValue: string): Boolean;
var
  C : Char;
begin
  Result := AValue <> '';
  for C in AValue do
    if C <> SENTINEL_CHAR then
      Exit(False);
end;

// Positionen (PosKey) der Gleitkomma-Literale und Include-Direktiven, die in
// der Ein-Zweig-Sicht des Scans aktiv sind; nil, wenn der Scan keine
// Ein-Zweig-Sicht hat (dann ist nichts abgeschaltet). Eine Direktive ist ein
// Kommentar und liefert kein Token: fuer diesen Lauf steht an ihrer Stelle
// ' ZZZ..Z ' in gleicher Laenge - ein Bezeichner, den der Lexer im aktiven
// Zweig liefert und im abgeschalteten uebergeht. Alle anderen Positionen
// bleiben unveraendert.
function ActivePositions(const ASource: string;
  const AIncs: TArray<TIncludeRef>): TDictionary<Int64, Boolean>;
var
  Probe : string;
  Ref   : TIncludeRef;
  k     : Integer;
  Lex   : TLexer;
  Tok   : TToken;
begin
  Result := nil;
  if not gLexerIfdefSkipEnabled then
    Exit;
  Probe := ASource;
  for Ref in AIncs do
    if Ref.Probed and (Ref.Len >= 3) then
    begin
      Probe[Ref.StartIdx] := ' ';
      for k := Ref.StartIdx + 1 to Ref.StartIdx + Ref.Len - 2 do
        Probe[k] := SENTINEL_CHAR;
      Probe[Ref.StartIdx + Ref.Len - 1] := ' ';
    end;
  Result := TDictionary<Int64, Boolean>.Create;
  try
    Lex := TLexer.Create(Probe);
    try
      if gLexerIfdefDefines <> nil then
        for k := 0 to gLexerIfdefDefines.Count - 1 do
          Lex.AddDefine(gLexerIfdefDefines[k]);
      Lex.EnableConditionalSkipping;
      Tok := Lex.Next;
      while Tok.Kind <> tkEof do
      begin
        if (Tok.Kind = tkFloatLit)
           or ((Tok.Kind = tkIdent) and IsSentinel(Tok.Value)) then
          Result.AddOrSetValue(PosKey(Tok.Line, Tok.Col), True);
        Tok := Lex.Next;
      end;
    finally
      Lex.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Pfad der Include-Datei, '' wenn nicht auffindbar (G1). Ein kaputter
// Direktiven-Inhalt im gescannten Fremdcode ist Nutzdaten, kein Grund zum
// Scan-Abbruch - nur Stapel/Speicher brechen ab (E3).
function ResolveInclude(const AFromFile, AName: string): string;
var
  Dir, P : string;
begin
  Result := '';
  Dir := ExtractFilePath(AFromFile);
  if Dir = '' then
    Exit;                        // In-Memory-Quelle ohne Verzeichnis
  try
    P := TPath.Combine(Dir, AName);
    if FileExists(P) then
      Exit(P);
    // Ohne Endung nimmt Delphi fuer {$I} '.pas' an.
    if ExtractFileExt(AName) = '' then
    begin
      P := P + '.pas';
      if FileExists(P) then
        Exit(P);
    end;
  except
    if IsFatalScanException(ExceptObject) then
      raise;
    Result := '';
  end;
end;

// Text der Include-Datei ueber den Datei-Cache (Encoding-Erkennung wie fuer
// die gescannte Datei); '' wenn unlesbar oder groesser als 1 MB.
function LoadIncludeText(const APath: string; AContext: TAnalyzeContext): string;
var
  Lines  : TStringList;
  Cached : Boolean;
begin
  Result := '';
  Lines := AcquireLines(APath, Cached, CtxFileTextCache(AContext));
  if Lines = nil then
    Exit;
  try
    Result := Lines.Text;
  finally
    ReleaseLines(Lines, Cached);
  end;
  if Length(Result) > MAX_INCLUDE_CHARS then
    Result := '';
end;

// R3: Index des Punkts im Literal (0 = keiner); True, wenn ein Punkt da ist
// und im Literal keine Ziffer auf ihn folgt ('5.', '5.E').
function DotWithoutDigits(const AText: string; out ADotIdx: Integer): Boolean;
begin
  ADotIdx := Pos('.', AText);
  Result := (ADotIdx > 0) and ((ADotIdx = Length(AText))
    or not CharInSet(AText[ADotIdx + 1], ['0'..'9']));
end;

// Startindex jeder Zeile (Index = Zeilennummer, 1-basiert; [0] unbenutzt).
// Zeilen wie im Lexer: jedes #10 beginnt die naechste.
function LineStartsOf(const ASource: string): TArray<Integer>;
var
  i, n : Integer;
begin
  n := 1;
  for i := 1 to Length(ASource) do
    if ASource[i] = #10 then
      Inc(n);
  SetLength(Result, n + 1);
  Result[0] := 0;
  Result[1] := 1;
  n := 1;
  for i := 1 to Length(ASource) do
    if ASource[i] = #10 then
    begin
      Inc(n);
      Result[n] := i + 1;
    end;
end;

// Erstes zaehlendes Literal von ASource in Leserichtung; ADepth = Include-
// Tiefe (0 = die gescannte Datei), AParentInactive = die einbindende
// Direktive steht in einem abgeschalteten Zweig, ARootIsInclude = die
// gescannte Datei (Tiefe 0) ist selbst eine Include-Datei (R2).
function ScanSource(const ASource, AFileName: string; ADepth: Integer;
  AParentInactive, ARootIsInclude: Boolean; AContext: TAnalyzeContext;
  out AHit: TFloatLiteralHit): Boolean;
var
  Incs       : TArray<TIncludeRef>;
  Active     : TDictionary<Int64, Boolean>;
  ActiveDone : Boolean;
  LineStarts : TArray<Integer>;
  Lex        : TLexer;
  Tok        : TToken;
  Facts      : TFloatLiteralFacts;
  DotIdx     : Integer;
  k          : Integer;

  // R3: beginnt direkt hinter dem Punkt des Tokens ein Bezeichner? Liest
  // die Quelle, nicht das Token - bei '5.ToString' endet das Token am
  // Punkt, bei '5.Equals' hat der Lexer das 'E' schon hineingenommen.
  function IdentAfterDot(const ATok: TToken; ADot: Integer): Boolean;
  var
    p : Integer;
  begin
    if LineStarts = nil then
      LineStarts := LineStartsOf(ASource);
    Result := False;
    if (ATok.Line < 1) or (ATok.Line >= Length(LineStarts)) then
      Exit;
    p := LineStarts[ATok.Line] + ATok.Col - 1 + ADot;
    Result := (p <= Length(ASource))
      and CharInSet(ASource[p], ['A'..'Z', 'a'..'z', '_']);
  end;

  // R1: liegt die Position in einem abgeschalteten Zweig? Der Zweig-Lauf
  // kommt erst beim ersten Kandidaten.
  function Inactive(ALine, ACol: Integer): Boolean;
  begin
    if not ActiveDone then
    begin
      Active     := ActivePositions(ASource, Incs);
      ActiveDone := True;
    end;
    Result := AParentInactive
      or ((Active <> nil) and not Active.ContainsKey(PosKey(ALine, ACol)));
  end;

  // Die Include-Datei hinter ARef, als stuende ihr Text an der Direktive.
  function TryInclude(const ARef: TIncludeRef): Boolean;
  var
    Path, Text : string;
    Sub        : TFloatLiteralHit;
    DirOff     : Boolean;
  begin
    Result := False;
    if ADepth >= MAX_INCLUDE_DEPTH then
      Exit;
    Path := ResolveInclude(AFileName, ARef.Name);
    if Path = '' then
      Exit;
    Text := LoadIncludeText(Path, AContext);
    if Text = '' then
      Exit;
    // Der Platzhalter beginnt eine Spalte hinter der Klammer (G2: eine
    // mehrzeilige Direktive hat keinen und gilt als aktiv).
    if ARef.Probed then
      DirOff := Inactive(ARef.Line, ARef.Col + 1)
    else
      DirOff := AParentInactive;
    if not ScanSource(Text, Path, ADepth + 1, DirOff, ARootIsInclude,
      AContext, Sub) then
      Exit;
    AHit      := Sub;
    AHit.Line := ARef.Line;
    AHit.Col  := ARef.Col;
    if Sub.IncludeName = '' then
    begin
      AHit.IncludeName := ARef.Name;
      AHit.IncludeLine := Sub.Line;
    end;
    Result := True;
  end;

begin
  Result     := False;
  AHit       := Default(TFloatLiteralHit);
  Active     := nil;
  ActiveDone := False;
  LineStarts := nil;
  // Nur Dateien mit '$I' koennen eine Include-Direktive tragen.
  if (Pos('$I', ASource) > 0) or (Pos('$i', ASource) > 0) then
    Incs := FindIncludes(ASource)
  else
    Incs := nil;
  Lex := TLexer.Create(ASource);    // alle Zweige, wie der Editor sie zeigt
  try
    k := 0;
    repeat
      Tok := Lex.Next;
      // Direktiven vor dem Token kommen in Leserichtung zuerst.
      while (k < Length(Incs)) and ((Tok.Kind = tkEof)
        or (Incs[k].Line < Tok.Line)
        or ((Incs[k].Line = Tok.Line) and (Incs[k].Col < Tok.Col))) do
      begin
        if TryInclude(Incs[k]) then
          Exit(True);
        Inc(k);
      end;
      if Tok.Kind = tkFloatLit then
      begin
        Facts.InInactiveBranch     := Inactive(Tok.Line, Tok.Col);
        Facts.InIncludedFile       := ADepth > 0;
        Facts.ScannedFileIsInclude := ARootIsInclude;
        Facts.DotWithoutDigits     := DotWithoutDigits(Tok.Value, DotIdx);
        Facts.IdentAfterDot        := Facts.DotWithoutDigits
          and IdentAfterDot(Tok, DotIdx);
        if TFloatLiteralIdeCrashDetector.LiteralCounts(Tok.Value, Facts) then
        begin
          AHit.Line  := Tok.Line;
          AHit.Col   := Tok.Col;
          AHit.Text  := Tok.Value;
          AHit.Facts := Facts;
          Exit(True);
        end;
      end;
    until Tok.Kind = tkEof;
  finally
    Lex.Free;
    Active.Free;
  end;
end;

{ TFloatLiteralIdeCrashDetector }

class function TFloatLiteralIdeCrashDetector.LiteralCounts(const AText: string;
  const AFacts: TFloatLiteralFacts): Boolean;
// Stand der IDE-Messung 2026-11-25 (s. Kopf). Es zaehlt jedes tkFloatLit
// ausser:
//   R2 in einer gescannten Include-Datei (sie anzuzeigen ist harmlos);
//   R3 Methodenaufruf auf einem Ganzzahl-Literal ('5.ToString', '5.Equals').
// R1 (AFacts.InInactiveBranch) und R2 ueber die einbindende Unit
// (AFacts.InIncludedFile) zaehlen - Absturz gemessen. '1.' ohne Bezeichner
// dahinter ist ungemessen und zaehlt.
begin
  if AFacts.ScannedFileIsInclude then
    Exit(False);
  if AFacts.DotWithoutDigits and AFacts.IdentAfterDot then
    Exit(False);
  Result := AText <> '';
end;

class function TFloatLiteralIdeCrashDetector.FindFirstLiteral(const ASource,
  AFileName: string; out AHit: TFloatLiteralHit;
  AContext: TAnalyzeContext): Boolean;
begin
  Result := ScanSource(ASource, AFileName, 0, False, IsIncludeExt(AFileName),
    AContext, AHit);
end;

class function TFloatLiteralIdeCrashDetector.MessageOf(
  const AHit: TFloatLiteralHit): string;
begin
  if AHit.IncludeName = '' then
    Result := Format('Floating-point literal `%s`: %s', [AHit.Text, MSG_TAIL])
  else
    Result := Format('Floating-point literal `%s` in include file %s, ' +
      'line %d: %s', [AHit.Text, AHit.IncludeName, AHit.IncludeLine, MSG_TAIL]);
end;

class procedure TFloatLiteralIdeCrashDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Source : string;
  Hit    : TFloatLiteralHit;
begin
  if not HasSourceExt(FileName) then
    Exit;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then
    Exit;
  try
    Source := TDetectorUtils.LinesTextCached(Lines, AContext, FileName);
  finally
    ReleaseLines(Lines, Cached);
  end;
  if FindFirstLiteral(Source, FileName, Hit, AContext) then
    Results.Add(TLeakFinding.New(FileName, '', Hit.Line, MessageOf(Hit),
      fkFloatLiteralIdeCrash).WithFixCol(Hit.Col));
end;

end.
