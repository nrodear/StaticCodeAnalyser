unit uLoopBoundScan;

// LoopPastHighBound - der reine Scanner, ohne AST, ohne Datei und ohne
// Typwissen (Charge A3, Q2, 2026-10-23).
//
// Eine for-Schleife, deren Grenze einen Index HINTER dem letzten Element
// liefert, und deren Rumpf DIESELBE Sammlung mit dem UNVERSCHOBENEN
// Schleifenindex liest oder schreibt:
//
//   for i := 0 to List.Count do  List[i] ...        (lbvCount)
//   for i := 1 to List.Count do  List[i] ...        (lbvCountFromOne)
//   for i := 0 to Length(A) do   A[i] ...           (lbvLength)
//   for i := Low(A) to Length(A) do A[i] ...        (lbvLowLength)
//   for i := 0 to High(A) + 1 do A[i] ...           (lbvHighPlusOne,
//                                                    auch Low(A) to ..)
//   for i := 1 to Length(S) + 1 do S[i] ...         (lbvStringPlusOne)
//
// Der Compiler meldet nichts; zur Laufzeit gibt es mit {$R+} einen
// ERangeError, bei TList/TStrings EArgumentOutOfRangeException bzw.
// EStringListError, sonst liest oder schreibt der letzte Durchlauf still
// hinter das Ende (Speicher eines Nachbarn).
//
// Gleiche Sammlung heisst gleiche Kette ('Memo1.Lines' = 'memo1.lines'),
// nicht vorne angehaengt ('Self.X' ist eine andere Kette als 'X', '.X'
// gehoert zu einem anderen Objekt). Zugriff heisst 'X[i]' oder 'X[i, ..]'
// (erster Index), bei .Count auch 'X.Items[i]', 'X.Strings[i]' und
// 'X.Objects[i]'. 'X[i - 1]', 'X[i + 1]', 'X[(i)]' und 'X.Insert(i, ..)'
// (Einfuegen ist bis Count gueltig) sind kein Zugriff.
//
// Nicht gemeldet (Rueckgabe ohne Treffer):
//   * die Schleifenvariable wird im Rumpf zugewiesen, Inc(i)/Dec(i);
//   * ein Waechter: eine if-/while-/case-/until-Bedingung im Rumpf VOR oder
//     MIT dem ersten Zugriff nennt i ausserhalb eines Zugriffs-Index
//     ('if i < List.Count then', 'if i = Length(A) then .. else A[i]') -
//     die Schleife laeuft dann bewusst einen Schritt weiter;
//   * downto, andere Untergrenzen, Grenzen mit weiterem Ausdruck
//     ('List.Count - 1', 'Length(A) - 1', 'Pred(..)').
// Merkmale fuer den Detektor (Warning statt Error, auch mit Typbeweis):
//   * Escapes: break/exit/continue/raise/goto/halt/abort VOR dem ersten
//     Zugriff - der Rumpf verlaesst den Durchlauf vielleicht vorher (nur
//     bedingt, bewusst nicht bewiesen);
//   * Grows: der Rumpf vergroessert oder ersetzt die Sammlung (Add, Insert,
//     Append, AddObject, Assign, Text :=, LoadFrom.., SetLength, X :=) -
//     die Grenze wurde VOR der Schleife ausgewertet;
//   * Deferred: eine anonyme Methode im Rumpf (laeuft vielleicht spaeter).
//
// Die Eingabe ist Quelltext; Kommentare und Strings ueberliest der Scanner
// selbst. Der Detektor gibt ihm die Code-Sicht aus
// TDetectorUtils.StripStringsAndCommentsCached (Kommentare entfernt,
// Strings ausgefuellt) - beides liefert dieselben Treffer. Ohne
// Generics und Inline-Variablen: der Korpus-Harness uebersetzt die Unit
// mit FPC 3.2.2 (Pruefstand-Muster wie uParamNameScan).

interface

uses
  System.SysUtils;

type
  TLoopBoundVariant = (
    lbvCount,          // 0 to X.Count
    lbvCountFromOne,   // 1 to X.Count (mit X[i], nicht X[i - 1])
    lbvLength,         // 0 to Length(A)
    lbvLowLength,      // Low(A) to Length(A)
    lbvHighPlusOne,    // 0 to High(A) + 1 bzw. Low(A) to High(A) + 1
    lbvStringPlusOne   // 1 to Length(S) + 1
  );

  // Was der Typbeweis des Detektors ueber die Sammlung weiss.
  TLoopBoundTypeKind = (
    ltkUnknown,        // kein Beweis (Kette, Property, fremde Unit)
    ltkList,           // TList, TObjectList, TStrings, TStringList, ...
    ltkArray,          // 'array ...' (dynamisch, offen ODER statisch)
    ltkDynArray,       // benannter dynamischer Array-Typ (TBytes, TArray<T>)
    ltkString,         // string, AnsiString, UnicodeString, ... (1-basiert)
    ltkShortString,    // ShortString, string[N]: S[0] ist das Laengenbyte
    ltkPChar,          // PChar & Co.: P[Length] ist die abschliessende #0
    ltkMap,            // TDictionary & Co.: X[i] ist ein Schluessel
    ltkOther           // ein anderer bekannter Typ
  );

  TLoopBoundVerdict = (lbdSkip, lbdError, lbdWarning);

  TLoopBoundHit = record
    Variant    : TLoopBoundVariant;
    ForPos     : Integer;   // 1-basiert: das 'f' von 'for' im Text
    LoopVar    : string;    // wie geschrieben
    LowText    : string;    // '0', '1', 'Low(A)'
    HighText   : string;    // 'List.Count', 'Length(A)', 'High(A) + 1'
    Collection : string;    // die Kette wie geschrieben, z. B. 'Memo1.Lines'
    Access     : string;    // erster Zugriff, z. B. 'List[i]', 'L.Objects[i]'
    Escapes    : Boolean;
    Grows      : Boolean;
    Deferred   : Boolean;
  end;

  TLoopBoundHits = array of TLoopBoundHit;

  TLoopBoundScan = class
  public
    // Alle Treffer im Text, in Textreihenfolge.
    class function ScanText(const AText: string): TLoopBoundHits; static;

    // Der Treffer zur for-Schleife, deren 'for' bei APos (1-basiert) steht.
    class function ScanForAt(const AText: string; APos: Integer;
      out AHit: TLoopBoundHit): Boolean; static;

    // Der nackte, kleine Typname (uTypeResolver.ReduceToDeclaredTypeLow:
    // 'tlist', 'array', 'string', 'shortstring', '') -> Typart.
    class function KindOfType(const ABareTypeLow: string): TLoopBoundTypeKind;
      static;

    // Error, Warning oder nicht melden - nach Variante, Typbeweis und den
    // Merkmalen des Rumpfs.
    class function Verdict(const AHit: TLoopBoundHit;
      AKind: TLoopBoundTypeKind): TLoopBoundVerdict; static;

    // Die Meldung: 'Loop past the last index: i := 0 to List.Count with
    // List[i] - <Rat>'. Kopf und Zugriff stehen woertlich darin - der
    // Planer in reDelphix vergleicht sie mit dem Puffer.
    class function MessageOf(const AHit: TLoopBoundHit;
      AKind: TLoopBoundTypeKind): string; static;
  end;

const
  // Feste Teile der Meldung (englisch wie alle Detektor-Meldungen). Der
  // Planer in reDelphix (uRdxLoopBoundFix) haelt Kopien dieser Texte -
  // wer sie aendert, aendert beide.
  LPB_PREFIX       = 'Loop past the last index: ';
  LPB_WITH         = ' with ';
  LPB_ADVICE_SEP   = ' - ';
  LPB_ADV_LAST     = 'the last pass is out of range; the bound should be ';
  LPB_ADV_FROM_ONE = 'the last pass is out of range; index %s[%s - 1] or '
    + 'bound %s.Count - 1';
  LPB_ADV_STR_ZERO = 'strings start at 1; the loop should run 1 to Length(%s)';
  LPB_ADV_STR_PLUS = 'strings end at Length(%s); the bound should be '
    + 'Length(%s)';
  LPB_ADV_UNKNOWN  = 'the last pass is out of range; the bound should be '
    + 'High(%s) - for a string the loop should run 1 to Length(%s)';
  // '0 to High(S) + 1': ein String ist an beiden Enden falsch, ohne
  // Typbeweis bleibt offen, ob es einer ist.
  LPB_ADV_STR_HIGH = 'strings start at 1; the loop should run 1 to High(%s)';
  LPB_ADV_UNK_HIGH = 'the last pass is out of range; the bound should be '
    + 'High(%s) - for a string the loop should run 1 to High(%s)';

implementation

const
  MAX_HEAD_TOKENS = 40;      // reicht fuer jeden Kopf der Regel
  MAX_BODY_TOKENS = 20000;   // Rumpf-Fenster je Schleife

  // Methoden, die die Sammlung vergroessern oder ersetzen (Grows).
  GROW_WORDS: array[0..14] of string = (
    'add', 'insert', 'append', 'addobject', 'addstrings', 'addpair',
    'assign', 'loadfromfile', 'loadfromstream', 'settext', 'text',
    'commatext', 'delimitedtext', 'addrange', 'insertrange');
  // Verlassen den Durchlauf (Escapes).
  ESCAPE_WORDS: array[0..6] of string = (
    'break', 'exit', 'continue', 'raise', 'goto', 'halt', 'abort');
  // Indizierte Properties einer Liste (nur bei .Count).
  MEMBER_WORDS: array[0..2] of string = ('items', 'strings', 'objects');
  // Oeffnen einen Block, den ein 'end' schliesst.
  OPEN_WORDS: array[0..4] of string = ('begin', 'case', 'try', 'asm',
    'record');
  // Beenden eine einzelne Anweisung (ohne verbraucht zu werden).
  STOP_WORDS: array[0..3] of string = ('end', 'until', 'finally', 'except');

  LIST_TYPES: array[0..19] of string = (
    'tlist', 'tobjectlist', 'tcomponentlist', 'tclasslist', 'tinterfacelist',
    'tstrings', 'tstringlist', 'thashedstringlist', 'twidestringlist',
    'tunicodestringlist', 'tcollection', 'townedcollection', 'tfplist',
    'tfpobjectlist', 'tfpglist', 'tfpgobjectlist',
    'tfpginterfacedobjectlist', 'tmenuitem', 'tlistitems', 'ttreenodes');
  DYN_ARRAY_TYPES: array[0..19] of string = (
    'tbytes', 'tarray', 'tstringdynarray', 'tintegerdynarray',
    'tbytedynarray', 'tworddynarray', 'tcardinaldynarray',
    'tint64dynarray', 'tdoubledynarray', 'tsingledynarray',
    'tbooleandynarray', 'tshortintdynarray', 'tsmallintdynarray',
    'tlongworddynarray', 'tuint64dynarray', 'textendeddynarray',
    'tpointerdynarray', 'tnativeintdynarray', 'twidestringdynarray',
    'tansistringdynarray');
  STRING_TYPES: array[0..6] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'rawbytestring',
    'utf8string', 'rawutf8');
  PCHAR_TYPES: array[0..3] of string = ('pchar', 'pansichar', 'pwidechar',
    'putf8char');
  MAP_TYPES: array[0..4] of string = ('tdictionary', 'tobjectdictionary',
    'tfpgmap', 'tfpgmapobject', 'tfpgmapinterfacedobjectdata');

type
  TLbTokKind = (ltWord, ltNumber, ltString, ltSym);

  TLbTok = record
    Kind : TLbTokKind;
    Text : string;   // wie geschrieben
    Low  : string;   // klein (Woerter), sonst = Text
    Pos  : Integer;  // 1-basiert
  end;

  TLbToks = array of TLbTok;

  // Welche Fassung einer Kette ChainText liefert.
  TLbChainForm = (cfLow, cfAsWritten);

  // Kopf einer Schleife (Indizes in die Token-Liste).
  TLbHead = record
    VarTok  : Integer;
    Chain   : array of string;   // Kette der Sammlung, klein
    ChainAt : Integer;           // erstes Token der Kette im Kopf
    ChainN  : Integer;
    DoTok   : Integer;
  end;

  // Was der Kopf ueber die Grenzen weiss (ParseHead).
  TLbBounds = record
    Lo        : string;    // '0', '1', 'low'
    LoChainAt : Integer;   // -1 ohne Low(..)
    LoChainN  : Integer;
    Fn        : string;    // 'count', 'length', 'high'
    Plus1     : Boolean;
  end;

  // Der Rumpf beim Scan (ScanBody, Guarded).
  TLbBody = record
    B0, B1   : Integer;    // erstes Token, Index hinter dem Rumpf
    VarLow   : string;
    First    : Integer;    // erstes Token des ersten Zugriffs, -1 ohne
    EscapeAt : Integer;    // erster Ausstieg, -1 ohne
    Idx      : array of Integer;   // Token der Zugriffs-Indizes
    IdxN     : Integer;
  end;

function InList(const S: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  for i := Low(AList) to High(AList) do
    if AList[i] = S then
      Exit(True);
  Result := False;
end;

function IsWordStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '&']) or (Ord(C) > 127);
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '0'..'9']) or
    (Ord(C) > 127);
end;

{ ---- Tokenizer ---- }

// Index hinter einem Kommentar, der bei P beginnt; P selbst, wenn dort
// keiner beginnt.
function CommentEnd(const S: string; P: Integer): Integer;
var
  N : Integer;
begin
  N := Length(S);
  Result := P;
  if S[P] = '{' then
  begin
    Result := P + 1;
    while (Result <= N) and (S[Result] <> '}') do Inc(Result);
    Inc(Result);
  end
  else if (S[P] = '(') and (P < N) and (S[P + 1] = '*') then
  begin
    Result := P + 2;
    while (Result < N) and not ((S[Result] = '*') and (S[Result + 1] = ')')) do
      Inc(Result);
    Inc(Result, 2);
  end
  else if (S[P] = '/') and (P < N) and (S[P + 1] = '/') then
  begin
    Result := P;
    while (Result <= N) and (S[Result] <> #10) and (S[Result] <> #13) do
      Inc(Result);
  end;
end;

// Leerraum und Kommentare ab P ueberlesen.
procedure SkipBlank(const S: string; var P: Integer);
var
  Q : Integer;
begin
  while P <= Length(S) do
  begin
    if (S[P] <= ' ') or (S[P] = #$FEFF) then
    begin
      Inc(P);
      Continue;
    end;
    Q := CommentEnd(S, P);
    if Q = P then Exit;
    P := Q;
  end;
end;

// Index hinter dem '..'-Teil eines Literals ab dem oeffnenden Hochkomma Q;
// eine Zeile schliesst ein offenes Literal.
function QuotedEnd(const S: string; Q: Integer): Integer;
var
  N : Integer;
begin
  N := Length(S);
  Result := Q + 1;
  while Result <= N do
  begin
    if (S[Result] = #10) or (S[Result] = #13) then Exit;
    if S[Result] <> '''' then
      Inc(Result)
    else if (Result < N) and (S[Result + 1] = '''') then
      Inc(Result, 2)
    else
      Exit(Result + 1);
  end;
end;

// Index hinter einem String-Literal samt #nn-Folgen ab P.
function StringEnd(const S: string; P: Integer): Integer;
begin
  Result := P;
  while (Result <= Length(S)) and CharInSet(S[Result], ['''', '#']) do
    if S[Result] = '''' then
      Result := QuotedEnd(S, Result)
    else
    begin
      Inc(Result);
      if (Result <= Length(S)) and (S[Result] = '$') then Inc(Result);
      while (Result <= Length(S)) and IsWordChar(S[Result]) do Inc(Result);
    end;
end;

function WordEnd(const S: string; P: Integer): Integer;
begin
  Result := P + 1;
  while (Result <= Length(S)) and IsWordChar(S[Result]) do Inc(Result);
end;

function SymEnd(const S: string; P: Integer): Integer;
var
  Two : string;
begin
  Two := Copy(S, P, 2);
  if (Two = ':=') or (Two = '..') or (Two = '<=') or (Two = '>=') or
     (Two = '<>') then
    Result := P + 2
  else
    Result := P + 1;
end;

// Ein Token ab P (Kommentare und Leerraum davor ueberlesen). False am Ende.
function NextTok(const S: string; var P: Integer; out ATok: TLbTok): Boolean;
var
  Q : Integer;
  C : Char;
begin
  ATok := Default(TLbTok);
  SkipBlank(S, P);
  if P > Length(S) then Exit(False);
  Result := True;
  ATok.Pos := P;
  C := S[P];
  if CharInSet(C, ['''', '#']) then
  begin
    Q := StringEnd(S, P);
    ATok.Kind := ltString;
  end
  else if CharInSet(C, ['0'..'9', '$']) then
  begin
    Q := WordEnd(S, P);
    ATok.Kind := ltNumber;
  end
  else if IsWordStart(C) then
  begin
    Q := WordEnd(S, P);
    ATok.Kind := ltWord;
  end
  else
  begin
    Q := SymEnd(S, P);
    ATok.Kind := ltSym;
  end;
  ATok.Text := Copy(S, P, Q - P);
  if (ATok.Kind = ltWord) and (ATok.Text[1] = '&') then
    ATok.Text := Copy(ATok.Text, 2, MaxInt);
  if ATok.Kind in [ltWord, ltNumber] then
    ATok.Low := LowerCase(ATok.Text)
  else
    ATok.Low := ATok.Text;
  P := Q;
end;

// Token ab APos, hoechstens AMax.
function TokensFrom(const S: string; APos, AMax: Integer): TLbToks;
var
  P, Cnt : Integer;
  T      : TLbTok;
begin
  Result := nil;
  SetLength(Result, 64);
  Cnt := 0;
  P := APos;
  while (Cnt < AMax) and NextTok(S, P, T) do
  begin
    if Cnt = Length(Result) then
      SetLength(Result, Cnt * 2);
    Result[Cnt] := T;
    Inc(Cnt);
  end;
  SetLength(Result, Cnt);
end;

function TokLow(const T: TLbToks; K: Integer): string;
begin
  if (K >= 0) and (K < Length(T)) then
    Result := T[K].Low
  else
    Result := '';
end;

function IsWordAt(const T: TLbToks; K: Integer): Boolean;
begin
  Result := (K >= 0) and (K < Length(T)) and (T[K].Kind = ltWord);
end;

{ ---- Ketten ---- }

// Kette Wort(.Wort)* ab K; AEnd = Index hinter der Kette, ACount = Woerter.
function ReadChain(const T: TLbToks; K: Integer; out AEnd,
  ACount: Integer): Boolean;
begin
  AEnd := K;
  ACount := 0;
  if not IsWordAt(T, K) then Exit(False);
  ACount := 1;
  AEnd := K + 1;
  while (TokLow(T, AEnd) = '.') and IsWordAt(T, AEnd + 1) do
  begin
    Inc(ACount);
    Inc(AEnd, 2);
  end;
  Result := True;
end;

// Die Kette ab AStart ('Memo1.Lines') klein oder wie geschrieben.
function ChainText(const T: TLbToks; AStart, ACount: Integer;
  AForm: TLbChainForm): string;
var
  Sb : TStringBuilder;
  j  : Integer;
begin
  Sb := TStringBuilder.Create;
  try
    for j := 0 to ACount - 1 do
    begin
      if j > 0 then
        Sb.Append('.');
      if AForm = cfLow then
        Sb.Append(T[AStart + 2 * j].Low)
      else
        Sb.Append(T[AStart + 2 * j].Text);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

// Steht bei K die Kette AChain (klein)?
function ChainAt(const T: TLbToks; K: Integer;
  const AChain: array of string): Boolean;
var
  j : Integer;
begin
  for j := 0 to High(AChain) do
  begin
    if not IsWordAt(T, K + 2 * j) or (T[K + 2 * j].Low <> AChain[j]) then
      Exit(False);
    if (j > 0) and (TokLow(T, K + 2 * j - 1) <> '.') then
      Exit(False);
  end;
  Result := True;
end;

{ ---- Kopf ---- }

// 'Name(Kette)' ab K (K = Name); AEnd hinter ')'.
function ReadCallOfChain(const T: TLbToks; K: Integer; out AEnd, AChainN:
  Integer): Boolean;
begin
  Result := (TokLow(T, K + 1) = '(') and ReadChain(T, K + 2, AEnd, AChainN)
    and (TokLow(T, AEnd) = ')');
  if Result then Inc(AEnd);
end;

// Untergrenze ab K: 0, 1 oder Low(Kette). K steht danach dahinter.
function ReadLowBound(const T: TLbToks; var K: Integer; var ABounds: TLbBounds;
  var AHit: TLoopBoundHit): Boolean;
var
  E : Integer;
begin
  ABounds.LoChainAt := -1;
  if (K < Length(T)) and (T[K].Kind = ltNumber) and
     ((T[K].Low = '0') or (T[K].Low = '1')) then
  begin
    ABounds.Lo := T[K].Low;
    AHit.LowText := T[K].Text;
    Inc(K);
    Exit(True);
  end;
  Result := (TokLow(T, K) = 'low') and ReadCallOfChain(T, K, E, ABounds.LoChainN);
  if not Result then Exit;
  ABounds.Lo := 'low';
  ABounds.LoChainAt := K + 2;
  AHit.LowText := T[K].Text + '(' +
    ChainText(T, K + 2, ABounds.LoChainN, cfAsWritten) + ')';
  K := E;
end;

// Obergrenze ab K: Kette.Count, Length(Kette) [+ 1], High(Kette) [+ 1].
function ReadHighBound(const T: TLbToks; var K: Integer; var AHead: TLbHead;
  var ABounds: TLbBounds; var AHit: TLoopBoundHit): Boolean;
var
  E, N : Integer;
begin
  ABounds.Fn := TokLow(T, K);
  if (ABounds.Fn = 'length') or (ABounds.Fn = 'high') then
  begin
    Result := ReadCallOfChain(T, K, E, N);
    if not Result then Exit;
    AHead.ChainAt := K + 2;
    AHead.ChainN := N;
    AHit.HighText := T[K].Text + '(' + ChainText(T, K + 2, N, cfAsWritten) + ')';
    K := E;
    ABounds.Plus1 := (TokLow(T, K) = '+') and (TokLow(T, K + 1) = '1');
    if ABounds.Plus1 then
    begin
      AHit.HighText := AHit.HighText + ' + ' + T[K + 1].Text;
      Inc(K, 2);
    end;
    Exit;
  end;
  Result := ReadChain(T, K, E, N) and (N >= 2) and (T[E - 1].Low = 'count');
  if not Result then Exit;
  ABounds.Fn := 'count';
  AHead.ChainAt := K;
  AHead.ChainN := N - 1;
  AHit.HighText := ChainText(T, K, N, cfAsWritten);
  K := E;
end;

// Die Variante aus den Grenzen; False fuer jede andere Form ('High(A)'
// ohne + 1 ist richtig, '1 to Length(S)' auch).
function VariantOf(const ABounds: TLbBounds; const ALoLow, ARLow: string;
  out AVariant: TLoopBoundVariant): Boolean;
var
  SameLow : Boolean;
begin
  Result := True;
  AVariant := lbvCount;
  SameLow := (ABounds.Lo = 'low') and (ALoLow = ARLow);
  if ABounds.Fn = 'count' then
  begin
    if ABounds.Lo = '0' then
      AVariant := lbvCount
    else if ABounds.Lo = '1' then
      AVariant := lbvCountFromOne
    else
      Result := False;
  end
  else if (ABounds.Fn = 'length') and not ABounds.Plus1 then
  begin
    if ABounds.Lo = '0' then
      AVariant := lbvLength
    else if SameLow then
      AVariant := lbvLowLength
    else
      Result := False;
  end
  else if ABounds.Fn = 'length' then
  begin
    AVariant := lbvStringPlusOne;
    Result := ABounds.Lo = '1';
  end
  else
  begin
    AVariant := lbvHighPlusOne;
    Result := ABounds.Plus1 and ((ABounds.Lo = '0') or SameLow);
  end;
end;

// Der Kopf ab T[0] = 'for'. AHit bekommt Variante und Texte.
function ParseHead(const T: TLbToks; out AHead: TLbHead;
  var AHit: TLoopBoundHit): Boolean;
var
  K, j : Integer;
  B    : TLbBounds;
  LoLow : string;
begin
  Result := False;
  AHead := Default(TLbHead);
  B := Default(TLbBounds);
  K := 1;
  if TokLow(T, K) = 'var' then Inc(K);
  if not IsWordAt(T, K) then Exit;
  AHead.VarTok := K;
  Inc(K);
  if TokLow(T, K) = ':' then
    while (K < Length(T)) and (TokLow(T, K) <> ':=') and
          (TokLow(T, K) <> 'do') and (TokLow(T, K) <> ';') do
      Inc(K);
  if TokLow(T, K) <> ':=' then Exit;
  Inc(K);
  if not ReadLowBound(T, K, B, AHit) then Exit;
  if TokLow(T, K) <> 'to' then Exit;
  Inc(K);
  if not ReadHighBound(T, K, AHead, B, AHit) then Exit;
  if TokLow(T, K) <> 'do' then Exit;
  AHead.DoTok := K;
  LoLow := '';
  if B.LoChainAt >= 0 then
    LoLow := ChainText(T, B.LoChainAt, B.LoChainN, cfLow);
  if not VariantOf(B, LoLow, ChainText(T, AHead.ChainAt, AHead.ChainN, cfLow),
    AHit.Variant) then
    Exit;
  SetLength(AHead.Chain, AHead.ChainN);
  for j := 0 to AHead.ChainN - 1 do
    AHead.Chain[j] := T[AHead.ChainAt + 2 * j].Low;
  AHit.Collection := ChainText(T, AHead.ChainAt, AHead.ChainN, cfAsWritten);
  AHit.LoopVar := T[AHead.VarTok].Text;
  Result := True;
end;

{ ---- Rumpfgrenze ---- }

// Ende eines Blocks, der bei K mit begin anfaengt: der Index hinter
// seinem schliessenden end.
function BlockEnd(const T: TLbToks; K: Integer): Integer;
var
  D : Integer;
begin
  D := 0;
  while K < Length(T) do
  begin
    if (T[K].Kind = ltWord) and InList(T[K].Low, OPEN_WORDS) then
      Inc(D)
    else if (T[K].Kind = ltWord) and (T[K].Low = 'end') then
    begin
      Dec(D);
      if D = 0 then Exit(K + 1);
    end;
    Inc(K);
  end;
  Result := K;
end;

// Beendet das Wort W auf Blocktiefe 0 eine einzelne Anweisung? AIfs zaehlt
// die offenen if, deren else noch kommen kann.
function EndsStatement(const W: string; var AIfs: Integer): Boolean;
begin
  Result := False;
  if InList(W, STOP_WORDS) then
    Exit(True);
  if W = 'if' then
    Inc(AIfs)
  else if W = 'else' then
  begin
    if AIfs = 0 then Exit(True);
    Dec(AIfs);
  end;
end;

// Ist W eine Klammer? Dann zaehlt APar die Tiefe mit.
function IsBracket(const W: string; var APar: Integer): Boolean;
begin
  Result := True;
  if (W = '(') or (W = '[') then
    Inc(APar)
  else if (W = ')') or (W = ']') then
    Dec(APar)
  else
    Result := False;
end;

// Ein Wort einer einzelnen Anweisung: ADepth zaehlt die Bloecke (begin,
// case, try ..); True, wenn W auf Tiefe 0 die Anweisung beendet.
function WordEndsStatement(const W: string; var ADepth, AIfs: Integer): Boolean;
begin
  Result := False;
  if InList(W, OPEN_WORDS) then
    Inc(ADepth)
  else if (W = 'end') and (ADepth > 0) then
    Dec(ADepth)
  else if ADepth = 0 then
    Result := EndsStatement(W, AIfs);
end;

// Index des Tokens, das eine einzelne Anweisung ab K beendet (';', 'end',
// 'else' ohne offenes if, until/finally/except) - nicht mitgezaehlt.
function StatementEnd(const T: TLbToks; K: Integer): Integer;
var
  D, Par, Ifs : Integer;
begin
  D := 0;
  Par := 0;
  Ifs := 0;
  while K < Length(T) do
  begin
    if not IsBracket(T[K].Low, Par) then
    begin
      if (T[K].Kind = ltSym) and (T[K].Low = ';') and (D = 0) and
         (Par <= 0) then
        Exit(K);
      if (T[K].Kind = ltWord) and WordEndsStatement(T[K].Low, D, Ifs) then
        Exit(K);
    end;
    Inc(K);
  end;
  Result := K;
end;

// Index hinter dem Rumpf, der bei K beginnt.
function BodyEnd(const T: TLbToks; K: Integer): Integer;
begin
  if K >= Length(T) then
    Result := K
  else if T[K].Low = 'begin' then
    Result := BlockEnd(T, K)
  else
    Result := StatementEnd(T, K);
end;

{ ---- Rumpf ---- }

function EndWordOf(const AWord: string): string;
begin
  if AWord = 'if' then
    Result := 'then'
  else if AWord = 'while' then
    Result := 'do'
  else if AWord = 'case' then
    Result := 'of'
  else
    Result := ';';   // until
end;

function IsIndexToken(const ABody: TLbBody; K: Integer): Boolean;
var
  j : Integer;
begin
  for j := 0 to ABody.IdxN - 1 do
    if ABody.Idx[j] = K then
      Exit(True);
  Result := False;
end;

// Nennt die Bedingung des if/while/case/until bei K die Schleifenvariable
// ausserhalb eines Zugriffs-Index?
function ConditionNamesVar(const T: TLbToks; K: Integer;
  const ABody: TLbBody): Boolean;
var
  J, Par : Integer;
  EndW, TJ : string;
begin
  EndW := EndWordOf(T[K].Low);
  Par := 0;
  J := K + 1;
  while J < ABody.B1 do
  begin
    TJ := T[J].Low;
    if not IsBracket(TJ, Par) and (Par <= 0) and
       ((TJ = EndW) or ((EndW = ';') and (TJ = 'end'))) then
      Exit(False);
    if (T[J].Kind = ltWord) and (TJ = ABody.VarLow) and
       not IsIndexToken(ABody, J) and (TokLow(T, J - 1) <> '.') then
      Exit(True);
    Inc(J);
  end;
  Result := False;
end;

// Ein Waechter: eine Bedingung vor oder mit dem ersten Zugriff nennt die
// Schleifenvariable ausserhalb eines Zugriffs-Index.
function Guarded(const T: TLbToks; const ABody: TLbBody): Boolean;
var
  K : Integer;
begin
  K := ABody.B0;
  while (K < ABody.B1) and (K <= ABody.First) do
  begin
    if (T[K].Kind = ltWord) and
       ((T[K].Low = 'if') or (T[K].Low = 'while') or (T[K].Low = 'case') or
        (T[K].Low = 'until')) and ConditionNamesVar(T, K, ABody) then
      Exit(True);
    Inc(K);
  end;
  Result := False;
end;

// Veraendert das Wort bei K die Schleifenvariable (V :=, Inc(V), Dec(V))?
function ChangesLoopVar(const T: TLbToks; K: Integer; const V: string): Boolean;
var
  W : string;
begin
  W := T[K].Low;
  if (W = V) and (TokLow(T, K - 1) <> '.') and (TokLow(T, K + 1) = ':=') then
    Exit(True);
  Result := ((W = 'inc') or (W = 'dec')) and (TokLow(T, K + 1) = '(') and
    (TokLow(T, K + 2) = V) and
    ((TokLow(T, K + 3) = ',') or (TokLow(T, K + 3) = ')'));
end;

// Der Zugriffs-Index hinter der Kette, die bei E endet: 'X[i' oder (bei
// .Count) 'X.Items[i' / '.Strings[' / '.Objects['; -1 sonst.
function AccessIndex(const T: TLbToks; E: Integer;
  AVariant: TLoopBoundVariant; const V: string): Integer;
begin
  Result := -1;
  if TokLow(T, E) = '[' then
    Result := E + 1
  else if (AVariant in [lbvCount, lbvCountFromOne]) and (TokLow(T, E) = '.') and
          InList(TokLow(T, E + 1), MEMBER_WORDS) and
          (TokLow(T, E + 2) = '[') then
    Result := E + 3;
  if (Result >= 0) and not (IsWordAt(T, Result) and (T[Result].Low = V) and
     ((TokLow(T, Result + 1) = ']') or (TokLow(T, Result + 1) = ','))) then
    Result := -1;
end;

// Die Kette der Sammlung beginnt bei K: Wachstum und Zugriff festhalten.
procedure NoteChainUse(const T: TLbToks; K: Integer; const AHead: TLbHead;
  var ABody: TLbBody; var AHit: TLoopBoundHit);
var
  E, Idx : Integer;
begin
  E := K + 2 * AHead.ChainN - 1;   // hinter der Kette
  if (TokLow(T, E) = ':=') or ((TokLow(T, E) = '.') and
     InList(TokLow(T, E + 1), GROW_WORDS)) then
    AHit.Grows := True;
  Idx := AccessIndex(T, E, AHit.Variant, ABody.VarLow);
  if Idx < 0 then Exit;
  if ABody.IdxN = Length(ABody.Idx) then
    SetLength(ABody.Idx, ABody.IdxN * 2 + 8);
  ABody.Idx[ABody.IdxN] := Idx;
  Inc(ABody.IdxN);
  if ABody.First >= 0 then Exit;
  ABody.First := K;
  AHit.Access := ChainText(T, K, AHead.ChainN, cfAsWritten);
  if Idx <> E + 1 then
    AHit.Access := AHit.Access + '.' + T[E + 1].Text;
  AHit.Access := AHit.Access + '[' + T[Idx].Text + ']';
end;

// Ein Wort des Rumpfs: Merkmale, Zugriffe. False = Veto (Schleifenvariable
// veraendert).
function NoteWord(const T: TLbToks; K: Integer; const AHead: TLbHead;
  var ABody: TLbBody; var AHit: TLoopBoundHit): Boolean;
var
  W : string;
begin
  Result := not ChangesLoopVar(T, K, ABody.VarLow);
  if not Result then Exit;
  W := T[K].Low;
  if (ABody.EscapeAt < 0) and InList(W, ESCAPE_WORDS) then
    ABody.EscapeAt := K;
  if (W = 'procedure') or (W = 'function') then
    AHit.Deferred := True;
  if (W = 'setlength') and (TokLow(T, K + 1) = '(') and
     ChainAt(T, K + 2, AHead.Chain) then
    AHit.Grows := True;
  if (TokLow(T, K - 1) <> '.') and ChainAt(T, K, AHead.Chain) then
    NoteChainUse(T, K, AHead, ABody, AHit);
end;

// Der Rumpf: Zugriff, Merkmale; False ohne Zugriff oder bei Veto.
function ScanBody(const T: TLbToks; const AHead: TLbHead;
  var AHit: TLoopBoundHit): Boolean;
var
  Body : TLbBody;
  K    : Integer;
begin
  Result := False;
  Body := Default(TLbBody);
  Body.B0 := AHead.DoTok + 1;
  Body.B1 := BodyEnd(T, Body.B0);
  Body.VarLow := T[AHead.VarTok].Low;
  Body.First := -1;
  Body.EscapeAt := -1;
  for K := Body.B0 to Body.B1 - 1 do
    if (T[K].Kind = ltWord) and not NoteWord(T, K, AHead, Body, AHit) then
      Exit;
  if (Body.First < 0) or Guarded(T, Body) then Exit;
  AHit.Escapes := (Body.EscapeAt >= 0) and (Body.EscapeAt < Body.First);
  Result := True;
end;

{ TLoopBoundScan }

class function TLoopBoundScan.ScanForAt(const AText: string; APos: Integer;
  out AHit: TLoopBoundHit): Boolean;
var
  T    : TLbToks;
  Head : TLbHead;
begin
  Result := False;
  AHit := Default(TLoopBoundHit);
  AHit.ForPos := APos;
  // Erst nur der Kopf (billig), dann der Rumpf.
  T := TokensFrom(AText, APos, MAX_HEAD_TOKENS);
  if (Length(T) = 0) or (T[0].Low <> 'for') then Exit;
  if not ParseHead(T, Head, AHit) then Exit;
  T := TokensFrom(AText, APos, MAX_BODY_TOKENS);
  AHit := Default(TLoopBoundHit);
  AHit.ForPos := APos;
  if not ParseHead(T, Head, AHit) then Exit;
  Result := ScanBody(T, Head, AHit);
end;

// Beginnt bei P das Wort 'for' (nicht hinter '.', '&' oder einem
// Wortzeichen)?
function ForWordAt(const S: string; P: Integer): Boolean;
begin
  Result := (P + 2 <= Length(S)) and CharInSet(S[P], ['f', 'F']) and
    CharInSet(S[P + 1], ['o', 'O']) and CharInSet(S[P + 2], ['r', 'R']) and
    ((P + 3 > Length(S)) or not IsWordChar(S[P + 3])) and
    ((P = 1) or not (IsWordChar(S[P - 1]) or CharInSet(S[P - 1], ['.', '&'])));
end;

class function TLoopBoundScan.ScanText(const AText: string): TLoopBoundHits;
var
  P, Cnt : Integer;
  Hit : TLoopBoundHit;
begin
  Result := nil;
  Cnt := 0;
  P := 1;
  while P <= Length(AText) - 2 do
  begin
    if ForWordAt(AText, P) then
    begin
      if ScanForAt(AText, P, Hit) then
      begin
        SetLength(Result, Cnt + 1);
        Result[Cnt] := Hit;
        Inc(Cnt);
      end;
      Inc(P, 3);
    end
    else
      Inc(P);
  end;
end;

class function TLoopBoundScan.KindOfType(
  const ABareTypeLow: string): TLoopBoundTypeKind;
begin
  if ABareTypeLow = '' then
    Result := ltkUnknown
  else if ABareTypeLow = 'array' then
    Result := ltkArray
  else if ABareTypeLow = 'shortstring' then
    Result := ltkShortString
  else if InList(ABareTypeLow, STRING_TYPES) then
    Result := ltkString
  else if InList(ABareTypeLow, PCHAR_TYPES) then
    Result := ltkPChar
  else if InList(ABareTypeLow, LIST_TYPES) then
    Result := ltkList
  else if InList(ABareTypeLow, DYN_ARRAY_TYPES) then
    Result := ltkDynArray
  else if InList(ABareTypeLow, MAP_TYPES) then
    Result := ltkMap
  else
    Result := ltkOther;
end;

// Beweist die Typart die Variante? False in AReport = nicht melden.
function ProofOf(AVariant: TLoopBoundVariant; AKind: TLoopBoundTypeKind;
  out AReport: Boolean): Boolean;
begin
  AReport := True;
  case AVariant of
    // 1 to X.Count mit X[i]: ohne Beweis koennte X 1-basiert sein
    // (COM-Sammlungen wie Excel Sheets/Range); in einer Map ist X[i] ein
    // Schluessel.
    lbvCount, lbvCountFromOne:
      begin
        Result := AKind = ltkList;
        AReport := (AKind <> ltkMap) and
          (Result or (AVariant = lbvCount));
      end;
    // ShortString: S[0] ist das Laengenbyte, S[Length] das letzte Zeichen -
    // kein Zugriff ausserhalb. PChar: P[Length] ist die #0.
    lbvLength:
      begin
        Result := AKind in [ltkString, ltkArray, ltkDynArray];
        AReport := not (AKind in [ltkShortString, ltkPChar]);
      end;
    // Nur ein dynamisches Array beginnt sicher bei 0; ein statisches
    // 'array[1..N]' laeuft mit Low(A) to Length(A) richtig, ein String
    // auch (Low(S) = 1).
    lbvLowLength:
      begin
        Result := AKind = ltkDynArray;
        AReport := Result;
      end;
    lbvHighPlusOne:
      begin
        Result := AKind in [ltkString, ltkShortString, ltkArray, ltkDynArray];
        AReport := AKind <> ltkPChar;
      end;
  else // lbvStringPlusOne
    Result := AKind = ltkString;
    AReport := Result;
  end;
end;

class function TLoopBoundScan.Verdict(const AHit: TLoopBoundHit;
  AKind: TLoopBoundTypeKind): TLoopBoundVerdict;
var
  Proven, Report : Boolean;
begin
  Proven := ProofOf(AHit.Variant, AKind, Report);
  if not Report then
    Result := lbdSkip
  else if Proven and not (AHit.Escapes or AHit.Grows or AHit.Deferred) then
    Result := lbdError
  else
    Result := lbdWarning;
end;

// Der Rat zu 'High(A) + 1' und 'Low(A) to Length(A)': High(A) - ausser ab
// 0 ueber einen String (oder einen Typ, der einer sein kann), der auch bei
// 1 beginnen muss.
function HighAdvice(const AHit: TLoopBoundHit;
  AKind: TLoopBoundTypeKind): string;
var
  C : string;
begin
  C := AHit.Collection;
  if (AHit.Variant <> lbvHighPlusOne) or (AHit.LowText <> '0') or
     (AKind in [ltkShortString, ltkArray, ltkDynArray]) then
    Result := LPB_ADV_LAST + 'High(' + C + ')'
  else if AKind = ltkString then
    Result := Format(LPB_ADV_STR_HIGH, [C])
  else
    Result := Format(LPB_ADV_UNK_HIGH, [C, C]);
end;

class function TLoopBoundScan.MessageOf(const AHit: TLoopBoundHit;
  AKind: TLoopBoundTypeKind): string;
var
  C, Advice : string;
begin
  C := AHit.Collection;
  case AHit.Variant of
    lbvCount:
      Advice := LPB_ADV_LAST + C + '.Count - 1';
    lbvCountFromOne:
      Advice := Format(LPB_ADV_FROM_ONE, [C, AHit.LoopVar, C]);
    lbvLength:
      if AKind = ltkString then
        Advice := Format(LPB_ADV_STR_ZERO, [C])
      else if AKind in [ltkArray, ltkDynArray] then
        Advice := LPB_ADV_LAST + 'High(' + C + ')'
      else
        Advice := Format(LPB_ADV_UNKNOWN, [C, C]);
    lbvStringPlusOne:
      Advice := Format(LPB_ADV_STR_PLUS, [C, C]);
  else // lbvLowLength, lbvHighPlusOne
    Advice := HighAdvice(AHit, AKind);
  end;
  Result := LPB_PREFIX + AHit.LoopVar + ' := ' + AHit.LowText + ' to ' +
    AHit.HighText + LPB_WITH + AHit.Access + LPB_ADVICE_SEP + Advice;
end;

end.
