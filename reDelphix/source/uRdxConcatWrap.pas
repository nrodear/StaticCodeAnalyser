unit uRdxConcatWrap;

// reDelphix - Code-Aktion OHNE Fund "Verkettungen im Formatter-Bereich nach
// jedem '+' umbrechen" (ckWrapConcat, uRdxContextRunner; Nico-Entscheide
// 2026-11-07), OHNE ToolsAPI und ohne Parser (laeuft auch im FPC-
// Pruefstand). Der Formatter der Delphi-IDE (Strg+D, bis Delphi 12) kennt
// die Marker '{(*}' .. '{*)}' nicht und zieht von Hand umbrochene
// Verkettungen darin in eine Zeile; diese Unit stellt das Layout wieder her.
// Sie kennt keine Marker: den Bereich gibt der Aufrufer vor
// (uRdxFormatterMarkerFix.MarkerRegionAt) - ein spaeteres "ueberall" (E7)
// laesst nur diesen Filter weg.
//
// DER UMBRUCH (E2, E3): hinter jedem binaeren '+' der Kettenebene, dem auf
// derselben Zeile noch ein Operand folgt, endet die Zeile; das '+' bleibt am
// Zeilenende, der Leerraum dahinter faellt weg, der naechste Operand beginnt
// die neue Zeile hinter dem Einzug. Einzug = der fuehrende Leerraum der
// ersten Anweisungszeile woertlich (Tabs bleiben Tabs) plus genau zwei
// Leerzeichen - fuer Zuweisung, Konstante und Aufruf gleich. Eine schon
// vorhandene Fortsetzungszeile behaelt ihren Einzug; bricht sie selbst noch
// um, bekommen ihre neuen Zeilen ihren eigenen fuehrenden Leerraum. Links
// vom '+' bleibt der Text, wie er ist ('a'+'b' wird 'a'+ / 'b'). Es aendert
// sich nur Leerraum zwischen Token im Code - Pascal ist dort formatfrei;
// String-Inhalte und Kommentare bleiben byte-gleich, darum bedeutungsgleich.
//
// DIE KANDIDATEN: jede Anweisung, die GANZ im Bereich liegt (eine, die vor
// dem Bereich beginnt oder hinter ihm endet, zaehlt nicht), in einer dieser
// Formen:
//   Zuweisung, auch Inline-Variable ('var S: string := ..'): die Kette steht
//             hinter ':=' - auf Tiefe 0 oder als ein Argument eines Aufrufs
//             dort ('S := Trim('a' + 'b')');
//   Konstante ('X = ..', 'X: string = ..'): hinter '=' - die Anweisung
//             beginnt mit einem Bezeichner, dann '=' oder ':' (als Anweisung
//             im Code unmoeglich, also eindeutig eine Deklaration, E8);
//   Aufruf    ('Q.SQL.Add('a' + B)', 'raise E.Create(..)'): in EINEM
//             Argument des Aufrufs.
// Kettenebene ist die flachste Klammertiefe der Anweisung mit einem
// binaeren '+'; alle '+' dieser Tiefe stehen in derselben Klammer und
// darin im selben Argument (sonst kein Kandidat: 'F('a' + 'b', 'c' + 'd')').
// Auf dieser Ebene steht mindestens ein String- oder Zeichenliteral ('a',
// #13#10) und mindestens ein Umbruchpunkt (E4: Schwelle 1). Binaer ist ein
// '+' hinter einem Operanden: String, Bezeichner (kein Schluesselwort aus
// KEYWORDS), Zahl, ')', ']', '^'. Ein '+' tiefer als die Kettenebene
// ('IntToStr(A + B)') gehoert zu seinem Operanden und bleibt.
// Kein Kandidat sind Anweisungen, die mit if, while, for, case, with, until
// oder einem Routinen- bzw. Property-Kopf beginnen, und eine Anweisung mit
// ';', begin oder end in einer Klammer (anonyme Methode).
//
// GESPERRT (der Grund steht im ausgegrauten Eintrag): ein mehrzeiliger
// String in der Anweisung; ein Block-Kommentar oder eine Direktive in der
// Kette (wohin er nach dem Umbruch gehoert, weiss nur der Autor - ein
// '//'-Kommentar am Zeilenende wandert ans Ende der letzten neuen Zeile);
// ein '+' am Zeilenanfang in der Anweisung (dort gilt der andere Stil, keine
// Mischung); eine umzubrechende Zeile mit einer weiteren Anweisung; ein
// Kommentar hinter dem ersten Umbruchpunkt einer Zeile mit einem
// Unterdrueckmarker ('noinspection', 'NOSONAR') - er gaelte danach einer
// anderen Zeile.
//
// DIE ERSETZUNGEN: je umzubrechende Zeile eine, die die ganze Zeile
// ersetzt (Spalte 1 bis Zeilenende - eine solche Zeile ist nie leer),
// Expected = die Zeile wie gelesen, NewText mit #10 (der Schreibweg setzt
// das Zeilenende des Puffers). Alle zusammen sind EIN Undo-Schritt (E5).
// Nach der Anwendung steht hinter keinem '+' der Kettenebene mehr ein
// Operand auf derselben Zeile - kein Kandidat mehr, kein Eintrag
// (idempotent).

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Sperre als englische msgids (die Tests pruefen sie mit
  // _()); Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po.
  R_CW_COMMENT = 'a comment or directive inside the concatenation - where '
    + 'it belongs after the line break, only the author knows';
  R_CW_TWO_STATEMENTS = 'the line holds more than one statement';
  R_CW_LEADING_PLUS = 'the statement already puts "+" at the start of its '
    + 'lines';
  R_CW_MULTI_LINE = 'a multi-line string in the statement';
  R_CW_SUPPRESSION = 'the comment at the end of the line suppresses a '
    + 'finding - it would move to another line';

type
  // Das Ergebnis fuer einen Bereich.
  //   Wrapped  Anweisungen, die umbrochen werden (je eine oder mehrere
  //            Ersetzungen in Edits)
  //   Skipped  gesperrte Kandidaten (bleiben, wie sie sind)
  //   Edits    die Ersetzungen aller umbrochenen Anweisungen, nach Zeilen
  //            aufsteigend (ein Undo-Schritt, uRdxEditor.ReplaceSpans)
  //   Reason   ohne Wrapped: der Grund des gesperrten Kandidaten, der der
  //            Caret-Zeile am naechsten steht (uebersetzt, uRdxText)
  TRdxWrapPlan = record
    Wrapped : Integer;
    Skipped : Integer;
    Edits   : TArray<TRdxEdit>;
    Reason  : string;
  end;

  // Der Planer der Code-Aktion ckWrapConcat.
  TRdxConcatWrap = class
  public
    // Plant den Umbruch aller Kandidaten im Bereich [AFromLine/AFromCol,
    // AToLine/AToCol) - Zeichenspalten, das Ende exklusiv (bei der Aktion
    // das Innere eines Formatter-Bereichs). ACaretLine waehlt nur den Grund
    // (Reason), wenn alles gesperrt ist. True, wenn es mindestens einen
    // Kandidaten gibt (APlan.Wrapped + APlan.Skipped > 0); False ohne
    // Kandidat - dann gibt es keinen Eintrag.
    class function PlanRange(AMap: TRdxCodeMap; AFromLine, AFromCol,
      AToLine, AToCol, ACaretLine: Integer;
      out APlan: TRdxWrapPlan): Boolean; static;
  end;

implementation

uses
  System.SysUtils,     // LowerCase
  uRefactorInfo,       // TRefactorSpan.Make
  uRdxText;            // _(): in die reDelphix-Sprache (E29)

const
  SPAN_WRAP = 'wrapconcat';
  // So viel kommt hinter den Einzug der ersten Anweisungszeile (E3).
  CONT_STEP = '  ';
  // Diese Woerter beenden auf Tiefe 0 eine Anweisung und gehoeren zu
  // keiner (Anweisungslisten, Abschnitte, case-Zweige).
  STOP_WORDS: array[0..17] of string = ('begin', 'end', 'then', 'else', 'do',
    'try', 'finally', 'except', 'repeat', 'of', 'type', 'uses', 'label',
    'interface', 'implementation', 'initialization', 'finalization',
    'otherwise');
  // Diese Woerter beginnen auf Tiefe 0 eine neue Anweisung und gehoeren zu
  // ihr. 'until' beendet die Schleife und beginnt ihre Bedingung; 'asm' und
  // die Koepfe sind nie ein Kandidat (NO_CHAIN_LEADS).
  LEAD_WORDS: array[0..17] of string = ('until', 'if', 'while', 'for',
    'case', 'with', 'raise', 'asm', 'procedure', 'function', 'constructor',
    'destructor', 'operator', 'property', 'class', 'var', 'const',
    'resourcestring');
  // Kopf einer Deklaration: steht das naechste Token auf derselben Zeile,
  // beginnt er die Anweisung ('var S: string := ..', 'const X = ..'); sonst
  // ist er ein Abschnittskopf und gehoert zu keiner Anweisung.
  DECL_HEADS: array[0..3] of string = ('var', 'const', 'resourcestring',
    'threadvar');
  // Damit beginnt keine Zuweisung, keine Konstante und kein Aufruf.
  NO_CHAIN_LEADS: array[0..13] of string = ('until', 'if', 'while', 'for',
    'case', 'with', 'asm', 'procedure', 'function', 'constructor',
    'destructor', 'operator', 'property', 'class');
  // In einer Klammer (wie ein ';' dort): eine anonyme Methode - die
  // Anweisung ist keine einfache Kette.
  BLOCK_IN_PARENS: array[0..3] of string = ('begin', 'end', 'procedure',
    'function');
  // Unterdrueckmarker eines Kommentars hinter einem Umbruchpunkt
  // (R_CW_SUPPRESSION): der des Analysers (klein verglichen) und der von
  // SonarQube (Wort, gross).
  SUPPRESS_ANALYSER = 'noinspection';
  SUPPRESS_SONAR    = 'NOSONAR';

type
  // Ein Token der Anweisung: die Klammertiefe davor (relativ zum Anfang der
  // Anweisung) und ob im Spalt davor ein String-Literal steht - die
  // Token-Leser der Code-Sicht ueberspringen Strings.
  TWrapTok = record
    Tok    : TRdxToken;
    Depth  : Integer;
    StrGap : Boolean;
  end;

  // Eine Anweisung des Bereichs. Toks endet mit ihrem Abschluss: dem ';'
  // (gehoert dazu) oder dem Wort, das die naechste beginnt bzw. die Liste
  // beendet (gehoert nicht dazu, sein Spalt schon). Last ist der Index des
  // letzten eigenen Tokens. Bad: Klammern gehen nicht auf, oder in einer
  // Klammer steht ein Block (BLOCK_IN_PARENS).
  TWrapStmt = record
    Toks : TArray<TWrapTok>;
    Last : Integer;
    Bad  : Boolean;
  end;

  // Die Kette einer Anweisung: Kettenebene, Bereich (Index des Tokens vor
  // dem ersten und des Tokens hinter dem letzten Operanden), alle '+' der
  // Ebene und die Umbruchpunkte darunter.
  TWrapChain = record
    Depth  : Integer;
    Before : Integer;
    Behind : Integer;
    Pluses : TArray<Integer>;
    Breaks : TArray<Integer>;
  end;

// ---- Kleine Helfer ----

procedure AddIndex(var AList: TArray<Integer>; AIndex: Integer);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AIndex;
end;

// Liegt (ALine, ACol) vor (AToLine, AToCol)?
function PosBefore(ALine, ACol, AToLine, AToCol: Integer): Boolean;
begin
  Result := (ALine < AToLine) or ((ALine = AToLine) and (ACol < AToCol));
end;

// Steht zwischen (AFromLine, AFromCol) und (AToLine, AToCol) exklusiv ein
// Zeichen eines String-Literals?
function StringBetween(AMap: TRdxCodeMap; AFromLine, AFromCol, AToLine,
  AToCol: Integer): Boolean;
var
  L, C, Stop : Integer;
begin
  Result := False;
  for L := AFromLine to AToLine do
  begin
    C := 1;
    if L = AFromLine then
      C := AFromCol;
    Stop := Length(AMap.Raw(L)) + 1;
    if L = AToLine then
      Stop := AToCol;
    while C < Stop do
    begin
      if AMap.ClassAt(L, C) = 's' then
        Exit(True);
      Inc(C);
    end;
  end;
end;

// T ist ein Wort der Liste und als Schluesselwort gemeint (nicht hinter
// '.', '&', '@').
function IsWordOf(const T, APrev: TRdxToken;
  const AList: array of string): Boolean;
begin
  Result := IsKeywordAfter(T, APrev) and InList(T.Low, AList);
end;

// ---- Anweisungen des Bereichs ----

// Beginnt hinter APrev (dem Token vor dem Bereich) eine Anweisung? Sonst
// ist die erste Anweisung des Bereichs der Rest einer laengeren.
function StartsFresh(AMap: TRdxCodeMap; const APrev: TRdxToken): Boolean;
var
  P2 : TRdxToken;
begin
  if (APrev.Low = '') or (APrev.Low = ';') then
    Exit(True);
  P2 := PrevToken(AMap, APrev.Line, APrev.Col);
  Result := IsWordOf(APrev, P2, STOP_WORDS) or IsWordOf(APrev, P2, DECL_HEADS);
end;

procedure AddTok(var AStmt: TWrapStmt; const AW: TWrapTok);
begin
  SetLength(AStmt.Toks, Length(AStmt.Toks) + 1);
  AStmt.Toks[High(AStmt.Toks)] := AW;
end;

type
  // Zustand der Zerlegung (SplitStatements): die fertigen Anweisungen, die
  // offene, ob sie zaehlt (die erste nicht, wenn sie vor dem Bereich begann)
  // und ob ein asm-Block offen ist (seine Zeilen sind kein Pascal-Ausdruck).
  TSplitState = record
    List  : TArray<TWrapStmt>;
    Cur   : TWrapStmt;
    Keep  : Boolean;
    InAsm : Boolean;
  end;

// Schliesst die offene Anweisung ab: AIncluded, wenn ihr letztes Token (das
// ';') zu ihr gehoert; sonst ist es nur ihr Abschluss.
procedure CloseStmt(var AState: TSplitState; AIncluded: Boolean);
begin
  AState.Cur.Last := High(AState.Cur.Toks);
  if not AIncluded then
    Dec(AState.Cur.Last);
  if AState.Keep and (AState.Cur.Last >= 0) then
  begin
    SetLength(AState.List, Length(AState.List) + 1);
    AState.List[High(AState.List)] := AState.Cur;
  end;
  AState.Keep := True;
  AState.Cur := Default(TWrapStmt);
  AState.Cur.Bad := AState.InAsm;
end;

// Die Rolle von T auf Tiefe 0 fuer die Zerlegung: 0 gewoehnlich, 1 beendet
// die Anweisung und gehoert zu keiner, 2 beginnt die naechste.
function BoundaryOf(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Integer;
begin
  Result := 0;
  if IsWordOf(T, APrev, DECL_HEADS)
     and (After(AMap, T).Line <> T.Line) then
    Exit(1);   // Abschnittskopf
  if IsWordOf(T, APrev, STOP_WORDS) then
    Exit(1);
  if IsWordOf(T, APrev, LEAD_WORDS) or IsWordOf(T, APrev, DECL_HEADS) then
    Result := 2;
end;

// Zerlegt den Bereich in Anweisungen. Eine Anweisung, die am Ende des
// Bereichs noch offen ist, kreuzt den End-Marker und faellt weg; die erste
// faellt weg, wenn sie vor dem Bereich begann (StartsFresh).
function SplitStatements(AMap: TRdxCodeMap; AFromLine, AFromCol, AToLine,
  AToCol: Integer): TArray<TWrapStmt>;
var
  T, Prev : TRdxToken;
  W       : TWrapTok;
  St      : TSplitState;
  GapLine : Integer;
  GapCol  : Integer;
  Role    : Integer;
begin
  St := Default(TSplitState);
  Prev := PrevToken(AMap, AFromLine, AFromCol);
  St.Keep := StartsFresh(AMap, Prev);
  GapLine := AFromLine;
  GapCol := AFromCol;
  T := NextToken(AMap, AFromLine, AFromCol);
  while (T.Low <> '') and PosBefore(T.Line, T.Col, AToLine, AToCol) do
  begin
    W.Tok := T;
    W.StrGap := StringBetween(AMap, GapLine, GapCol, T.Line, T.Col);
    W.Depth := 0;
    if Length(St.Cur.Toks) > 0 then
      W.Depth := St.Cur.Toks[High(St.Cur.Toks)].Depth
        + ParenDelta(St.Cur.Toks[High(St.Cur.Toks)].Tok);
    // Eine Klammer zu viel (der Rest einer Anweisung vor dem Bereich):
    // die Anweisung taugt nicht, die Zerlegung zaehlt ab Tiefe 0 weiter.
    if W.Depth < 0 then
    begin
      St.Cur.Bad := True;
      W.Depth := 0;
    end;
    Role := 0;
    if W.Depth = 0 then
      Role := BoundaryOf(AMap, T, Prev)
    else if (T.Low = ';') or IsWordOf(T, Prev, BLOCK_IN_PARENS) then
      St.Cur.Bad := True;
    if Role > 0 then
    begin
      // Der Abschluss traegt den Spalt davor (ein String am Ende der Kette).
      AddTok(St.Cur, W);
      if T.Low = 'end' then
        St.InAsm := False;
      CloseStmt(St, False);
      if Role = 2 then
      begin
        // Das asm-Wort selbst ist nie ein Kandidat (NO_CHAIN_LEADS); erst
        // die Anweisungen dahinter traegt CloseStmt als Bad.
        St.InAsm := St.InAsm or (T.Low = 'asm');
        AddTok(St.Cur, W);
      end;
    end
    else
    begin
      AddTok(St.Cur, W);
      if (T.Low = ';') and (W.Depth = 0) then
        CloseStmt(St, True);
    end;
    GapLine := T.Line;
    GapCol := T.EndCol;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := St.List;
end;

// ---- Kette einer Anweisung ----

// Ist das Token an AIndex ein binaeres '+'? Davor steht ein Operand: ein
// String im Spalt, ')', ']', '^', eine Zahl oder ein Bezeichner, der kein
// Schluesselwort ist.
function IsBinaryPlus(const S: TWrapStmt; AIndex: Integer): Boolean;
var
  P, P2 : TRdxToken;
begin
  Result := False;
  if S.Toks[AIndex].Tok.Low <> '+' then Exit;
  if S.Toks[AIndex].StrGap then Exit(True);
  if AIndex = 0 then Exit;
  P := S.Toks[AIndex - 1].Tok;
  if (P.Low = ')') or (P.Low = ']') or (P.Low = '^') then Exit(True);
  if CharInSet(P.Low[1], ['0'..'9']) then Exit(True);
  if not P.IsWord then Exit;
  P2 := Default(TRdxToken);
  if AIndex >= 2 then
    P2 := S.Toks[AIndex - 2].Tok;
  Result := not IsWordOf(P, P2, KEYWORDS);
end;

// Der Index des ersten Tokens der rechten Seite: hinter ':=' (Zuweisung)
// bzw. hinter '=' (Konstante); 0 fuer einen Aufruf (ACall). -1, wenn die
// Anweisung keine der drei Formen hat.
function RightSideOf(const S: TWrapStmt; out ACall: Boolean): Integer;
var
  i, h : Integer;
  P    : TRdxToken;
begin
  ACall := False;
  P := Default(TRdxToken);
  if IsWordOf(S.Toks[0].Tok, P, NO_CHAIN_LEADS) then
    Exit(-1);
  for i := 0 to S.Last do
    if (S.Toks[i].Depth = 0) and (S.Toks[i].Tok.Low = ':=') then
      Exit(i + 1);
  // Konstante: [Kopf] Bezeichner, dann '=' oder ':'; die rechte Seite
  // hinter dem ersten '=' auf Tiefe 0.
  h := 0;
  if IsWordOf(S.Toks[0].Tok, P, DECL_HEADS) then
    h := 1;
  if (h + 1 <= S.Last) and S.Toks[h].Tok.IsWord
     and not InList(S.Toks[h].Tok.Low, KEYWORDS)
     and ((S.Toks[h + 1].Tok.Low = '=') or (S.Toks[h + 1].Tok.Low = ':')) then
  begin
    for i := h + 1 to S.Last do
      if (S.Toks[i].Depth = 0) and (S.Toks[i].Tok.Low = '=') then
        Exit(i + 1);
    Exit(-1);
  end;
  ACall := True;
  Result := 0;
end;

// Die Klammer, in der das Token an AIndex auf Tiefe ADepth steht: Index
// ihres Oeffners (-1 auf Tiefe 0) und die Zahl der Kommas davor auf dieser
// Tiefe (das Argument).
function OpenerOf(const S: TWrapStmt; AIndex, ADepth: Integer;
  out ACommas: Integer): Integer;
var
  j : Integer;
begin
  Result := -1;
  ACommas := 0;
  for j := AIndex - 1 downto 0 do
    if (S.Toks[j].Depth = ADepth - 1) and (ParenDelta(S.Toks[j].Tok) = 1) then
      Exit(j)
    else if (S.Toks[j].Depth = ADepth) and (S.Toks[j].Tok.Low = ',') then
      Inc(ACommas);
end;

// Das Ende des Arguments ab AFrom auf Tiefe ADepth: das ',' bzw. die
// schliessende Klammer dahinter.
function ArgumentEnd(const S: TWrapStmt; AFrom, ADepth: Integer): Integer;
var
  k : Integer;
begin
  Result := High(S.Toks);
  for k := AFrom to High(S.Toks) do
    if (S.Toks[k].Depth = ADepth)
       and ((S.Toks[k].Tok.Low = ',') or (ParenDelta(S.Toks[k].Tok) = -1)) then
      Exit(k);
end;

// Ist der Oeffner an AOpen die Klammer eines Aufrufs (davor ein Bezeichner,
// kein Schluesselwort) und steht er auf der rechten Seite?
function IsCallParen(const S: TWrapStmt; AOpen, ARight: Integer): Boolean;
var
  P2 : TRdxToken;
begin
  Result := False;
  if (AOpen < 1) or (AOpen < ARight) or (S.Toks[AOpen].Tok.Low <> '(') then
    Exit;
  if not S.Toks[AOpen - 1].Tok.IsWord then Exit;
  P2 := Default(TRdxToken);
  if AOpen >= 2 then
    P2 := S.Toks[AOpen - 2].Tok;
  Result := not IsWordOf(S.Toks[AOpen - 1].Tok, P2, KEYWORDS);
end;

// Steht auf der Kettenebene ein String- oder Zeichenliteral? Die Spalte vor
// dem Token i liegt auf dessen Tiefe; ein '#' beginnt ein Zeichenliteral.
function HasLiteral(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): Boolean;
var
  i, F, E : Integer;
begin
  Result := False;
  for i := AChain.Before + 1 to AChain.Behind do
    if S.Toks[i].Depth = AChain.Depth then
    begin
      if S.Toks[i].StrGap then Exit(True);
      if (S.Toks[i].Tok.Low = '#')
         and (LiteralContaining(AMap, S.Toks[i].Tok.Line, S.Toks[i].Tok.Col,
           F, E) = lkChar) then
        Exit(True);
    end;
end;

// Folgt dem Token T auf seiner Zeile noch etwas anderes als Leerraum oder
// ein '//'-Kommentar? (Ein Block-Kommentar dahinter zaehlt - die Sperre
// R_CW_COMMENT nennt ihn.)
function CodeFollowsOnLine(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  L : string;
  c : Integer;
begin
  L := AMap.Raw(T.Line);
  c := SkipBlanks(L, T.EndCol);
  Result := (c <= Length(L)) and (c <> AMap.LineCommentCol(T.Line));
end;

// Sammelt die '+' der Kettenebene in ADepth und prueft, dass sie in EINER
// Klammer und EINEM Argument stehen; setzt den Bereich der Kette.
function ChainAtDepth(const S: TWrapStmt; ARight: Integer; ACall: Boolean;
  ADepth: Integer; var AChain: TWrapChain): Boolean;
var
  i, Open, Commas, FirstOpen, FirstCommas : Integer;
begin
  Result := False;
  FirstOpen := -2;
  FirstCommas := 0;
  for i := ARight to S.Last do
    if (S.Toks[i].Depth = ADepth) and IsBinaryPlus(S, i) then
    begin
      Open := OpenerOf(S, i, ADepth, Commas);
      if FirstOpen = -2 then
      begin
        FirstOpen := Open;
        FirstCommas := Commas;
      end
      else if (Open <> FirstOpen) or (Commas <> FirstCommas) then
        Exit;   // zwei Ketten in einer Anweisung (G3)
      AddIndex(AChain.Pluses, i);
    end;
  AChain.Depth := ADepth;
  if ADepth = 0 then
  begin
    if ACall then Exit;   // ein Aufruf traegt die Kette in einer Klammer
    AChain.Before := ARight - 1;
    AChain.Behind := High(S.Toks);
    Exit(True);
  end;
  if not IsCallParen(S, FirstOpen, ARight) then Exit;
  // Das Argument: hinter dem Oeffner bzw. dem FirstCommas-ten Komma.
  AChain.Before := FirstOpen;
  i := FirstOpen + 1;
  while FirstCommas > 0 do
  begin
    AChain.Before := ArgumentEnd(S, i, ADepth);
    i := AChain.Before + 1;
    Dec(FirstCommas);
  end;
  AChain.Behind := ArgumentEnd(S, i, ADepth);
  Result := True;
end;

// Die Kette der Anweisung S mit mindestens einem Umbruchpunkt - sonst False
// (kein Kandidat).
function ChainOf(AMap: TRdxCodeMap; const S: TWrapStmt;
  out AChain: TWrapChain): Boolean;
var
  Right, i, D : Integer;
  Call        : Boolean;
begin
  Result := False;
  AChain := Default(TWrapChain);
  if S.Bad then Exit;
  Right := RightSideOf(S, Call);
  if Right < 0 then Exit;
  D := MaxInt;
  for i := Right to S.Last do
    if IsBinaryPlus(S, i) and (S.Toks[i].Depth < D) then
      D := S.Toks[i].Depth;
  if (D = MaxInt) or not ChainAtDepth(S, Right, Call, D, AChain)
     or not HasLiteral(AMap, S, AChain) then
    Exit;
  for i in AChain.Pluses do
    if CodeFollowsOnLine(AMap, S.Toks[i].Tok) then
      AddIndex(AChain.Breaks, i);
  Result := Length(AChain.Breaks) > 0;
end;

// ---- Sperren ----

// Wird Zeile ALine umbrochen (traegt sie einen Umbruchpunkt)? AFirstCol:
// die Spalte des ersten '+' dort.
function WrapsLine(const S: TWrapStmt; const AChain: TWrapChain;
  ALine: Integer; out AFirstCol: Integer): Boolean;
var
  i : Integer;
begin
  AFirstCol := 0;
  for i in AChain.Breaks do
    if S.Toks[i].Tok.Line = ALine then
    begin
      AFirstCol := S.Toks[i].Tok.Col;
      Exit(True);
    end;
  Result := False;
end;

// Ein mehrzeiliger String in der Anweisung: eine ihrer Zeilen beginnt in
// einem String, der auf der Zeile davor (als String) endet. Gelesen wird
// bis zum Abschluss - ein String als letzter Operand steht hinter dem
// letzten eigenen Token.
function HasMultiLineString(AMap: TRdxCodeMap; const S: TWrapStmt): Boolean;
var
  L : Integer;
  P : string;
begin
  Result := False;
  for L := S.Toks[0].Tok.Line + 1 to S.Toks[High(S.Toks)].Tok.Line do
    if AMap.StartsInside(L) then
    begin
      P := AMap.Raw(L - 1);
      if (P <> '') and (AMap.ClassAt(L - 1, Length(P)) = 's') then
        Exit(True);
    end;
end;

// Ein Block-Kommentar oder eine Direktive zwischen dem Token vor dem ersten
// und dem hinter dem letzten Operanden (ein '//'-Kommentar am Zeilenende
// zaehlt nicht - er wandert mit).
function HasCommentInChain(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): Boolean;
var
  A, B          : TRdxToken;
  L, Lo, Hi, CC : Integer;
begin
  Result := False;
  A := S.Toks[AChain.Before].Tok;
  B := S.Toks[AChain.Behind].Tok;
  for L := A.Line to B.Line do
  begin
    Lo := 1;
    if L = A.Line then
      Lo := A.EndCol;
    Hi := Length(AMap.Raw(L));
    if L = B.Line then
      Hi := B.Col - 1;
    CC := AMap.LineCommentCol(L);
    if (CC > 0) and (CC <= Hi) then
      Hi := CC - 1;
    if AMap.HasComment(L, Lo, Hi) then
      Exit(True);
  end;
end;

// Ein '+' der Kettenebene am Zeilenanfang (Stil "+ 'b'").
function HasLeadingPlus(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): Boolean;
var
  i : Integer;
  T : TRdxToken;
begin
  Result := False;
  for i in AChain.Pluses do
  begin
    T := S.Toks[i].Tok;
    if SkipBlanks(AMap.Raw(T.Line), 1) = T.Col then
      Exit(True);
  end;
end;

// Teilt eine umzubrechende Zeile die Anweisung mit einer anderen: Code vor
// dem Anfang auf der ersten bzw. hinter dem Ende auf der letzten Zeile.
function SharesWrappedLine(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): Boolean;
var
  First, Last, P, N : TRdxToken;
  Col               : Integer;
begin
  First := S.Toks[0].Tok;
  Last := S.Toks[S.Last].Tok;
  P := PrevToken(AMap, First.Line, First.Col);
  Result := WrapsLine(S, AChain, First.Line, Col) and (P.Low <> '')
    and (P.Line = First.Line);
  if Result then Exit;
  N := After(AMap, Last);
  Result := WrapsLine(S, AChain, Last.Line, Col) and (N.Low <> '')
    and (N.Line = Last.Line);
end;

// Ein Kommentar hinter dem ersten Umbruchpunkt einer umzubrechenden Zeile
// traegt einen Unterdrueckmarker - er wanderte auf eine andere Zeile.
function MovesSuppression(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): Boolean;
var
  i, c, Col : Integer;
  L, Txt    : string;
  Line      : Integer;
begin
  Result := False;
  for i in AChain.Breaks do
  begin
    Line := S.Toks[i].Tok.Line;
    WrapsLine(S, AChain, Line, Col);
    L := AMap.Raw(Line);
    Txt := '';
    for c := Col to Length(L) do
      if AMap.ClassAt(Line, c) = 'k' then
        Txt := Txt + L[c];
    if (Pos(SUPPRESS_ANALYSER, LowerCase(Txt)) > 0)
       or HasAsciiWord(Txt, SUPPRESS_SONAR) then
      Exit(True);
  end;
end;

// Der Grund, die Kette nicht umzubrechen, oder '' (frei).
function RefusalOf(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain): string;
begin
  Result := '';
  if HasMultiLineString(AMap, S) then
    Result := _(R_CW_MULTI_LINE)
  else if HasCommentInChain(AMap, S, AChain) then
    Result := _(R_CW_COMMENT)
  else if HasLeadingPlus(AMap, S, AChain) then
    Result := _(R_CW_LEADING_PLUS)
  else if SharesWrappedLine(AMap, S, AChain) then
    Result := _(R_CW_TWO_STATEMENTS)
  else if MovesSuppression(AMap, S, AChain) then
    Result := _(R_CW_SUPPRESSION);
end;

// ---- Ersetzungen ----

// Die Zeile ALine umbrochen hinter ihren Umbruchpunkten; AIndent ist der
// Einzug der neuen Zeilen.
function WrappedLine(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain; ALine: Integer; const AIndent: string): string;
var
  L    : string;
  i, P : Integer;
  T    : TRdxToken;
begin
  L := AMap.Raw(ALine);
  Result := '';
  P := 1;
  for i in AChain.Breaks do
  begin
    T := S.Toks[i].Tok;
    if T.Line <> ALine then Continue;
    if P > 1 then
      Result := Result + #10 + AIndent;
    Result := Result + Copy(L, P, T.EndCol - P);
    P := SkipBlanks(L, T.EndCol);
  end;
  Result := Result + #10 + AIndent + Copy(L, P, MaxInt);
end;

// Haengt die Ersetzungen der Anweisung S an AEdits an: je Zeile mit
// Umbruchpunkt die ganze Zeile.
procedure AddWrapEdits(AMap: TRdxCodeMap; const S: TWrapStmt;
  const AChain: TWrapChain; var AEdits: TArray<TRdxEdit>);
var
  i, Line, Done : Integer;
  Indent        : string;
  E             : TRdxEdit;
begin
  Done := 0;
  for i in AChain.Breaks do
  begin
    Line := S.Toks[i].Tok.Line;
    if Line = Done then Continue;
    Done := Line;
    // E3: die erste Anweisungszeile + 2, eine Fortsetzungszeile ihr eigener
    // Einzug.
    Indent := IndentOf(AMap.Raw(Line));
    if Line = S.Toks[0].Tok.Line then
      Indent := Indent + CONT_STEP;
    E := Default(TRdxEdit);
    E.Span := TRefactorSpan.Make(SPAN_WRAP, Line, 1, Line,
      Length(AMap.Raw(Line)) + 1);
    E.Expected := AMap.Raw(Line);
    E.NewText := WrappedLine(AMap, S, AChain, Line, Indent);
    AddEdit(AEdits, E);
  end;
end;

// Abstand der Zeile ALine zu den Zeilen der Anweisung S (0 darin).
function DistanceTo(const S: TWrapStmt; ALine: Integer): Integer;
var
  A, B : Integer;
begin
  A := S.Toks[0].Tok.Line;
  B := S.Toks[S.Last].Tok.Line;
  Result := 0;
  if ALine < A then
    Result := A - ALine
  else if ALine > B then
    Result := ALine - B;
end;

{ TRdxConcatWrap }

class function TRdxConcatWrap.PlanRange(AMap: TRdxCodeMap; AFromLine,
  AFromCol, AToLine, AToCol, ACaretLine: Integer;
  out APlan: TRdxWrapPlan): Boolean;
var
  Stmts : TArray<TWrapStmt>;
  Chain : TWrapChain;
  Why   : string;
  i     : Integer;
  Best  : Integer;
begin
  APlan := Default(TRdxWrapPlan);
  Best := MaxInt;
  Stmts := SplitStatements(AMap, AFromLine, AFromCol, AToLine, AToCol);
  for i := 0 to High(Stmts) do
  begin
    if not ChainOf(AMap, Stmts[i], Chain) then Continue;
    Why := RefusalOf(AMap, Stmts[i], Chain);
    if Why = '' then
    begin
      Inc(APlan.Wrapped);
      AddWrapEdits(AMap, Stmts[i], Chain, APlan.Edits);
    end
    else
    begin
      Inc(APlan.Skipped);
      // Der Grund des Caret-naechsten gesperrten Kandidaten (der erste bei
      // gleichem Abstand).
      if DistanceTo(Stmts[i], ACaretLine) < Best then
      begin
        Best := DistanceTo(Stmts[i], ACaretLine);
        APlan.Reason := Why;
      end;
    end;
  end;
  if APlan.Wrapped > 0 then
    APlan.Reason := '';
  Result := APlan.Wrapped + APlan.Skipped > 0;
end;

end.
