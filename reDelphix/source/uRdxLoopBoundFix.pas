unit uRdxLoopBoundFix;

// reDelphix - Editorhilfe zu LoopPastHighBound (Charge A3 / Q2,
// 2026-10-23), OHNE ToolsAPI und ohne Parser: die for-Schleife laeuft einen
// Index zu weit ('for i := 0 to List.Count do .. List[i]'). Der Detektor
// (uLoopPastHighBound, Scanner uLoopBoundScan) meldet die Zeile des for und
// schreibt Kopf, Zugriff und Rat woertlich in die Meldung:
//   'Loop past the last index: i := 0 to List.Count with List[i] - <Rat>'
// Der Planer liest Variable, Unter- und Obergrenze und Rat aus der Meldung,
// sucht DENSELBEN Kopf auf der gemeldeten Zeile (gleicher Text, ganz auf
// der Zeile) und korrigiert genau eine Stelle:
//   '0 to X.Count'          -> '0 to X.Count - 1'
//   '0 to Length(A)'        -> '0 to High(A)'         (Array bewiesen)
//   'Low(A) to Length(A)'   -> 'Low(A) to High(A)'    (dyn. Array bewiesen)
//   '0 to Length(S)'        -> '1 to Length(S)'       (String bewiesen)
//   '.. to High(A) + 1'     -> '.. to High(A)'        (Rat: High(A))
//   '1 to Length(S) + 1'    -> '1 to Length(S)'       (String bewiesen)
// Welche Form gilt, sagt der Rat der Meldung (die Typart kennt nur der
// Detektor). Ohne passenden Rat keine Hilfe: '1 to X.Count' (X[i - 1] oder
// Count - 1 entscheidet der Mensch), 'Length(A)' ohne Typbeweis (Array:
// High, String: 1 to Length), '0 to High(S) + 1' ueber einen String.
// Gesperrt mit Grund: eine Direktive in der Zeile des Kopfs, ein Kopf ueber
// mehrere Zeilen, ein Kommentar oder String im Kopf, kein oder mehr als ein
// passender Kopf auf der Zeile.
// Die Hilfe AENDERT DAS VERHALTEN (Kennzeichnung in der Tabelle): die
// Schleife laeuft einmal weniger bzw. beginnt bei 1.
// Die festen Texte der Meldung sind Kopien aus uLoopBoundScan - wer sie
// dort aendert, aendert sie hier.

interface

uses
  uRdxBufferMath,     // TRdxEdit
  uRdxCodeMap;        // TRdxCodeMap

const
  // Die Gruende als englische msgids (E29), uebersetzt mit _() aus
  // uRdxText; Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po.
  // Menuetext und Hinweis stehen mit dem Adapter in der Tabelle
  // (uRdxFixTable). R_LOOPB_OTHER bekommt sein Ende von MsgMovedSuffix.
  R_LOOPB_MESSAGE   = 'the message does not name the loop head - analyse '
    + 'the file again';
  R_LOOPB_FROM_ONE  = 'the loop runs from 1 to Count - whether the index '
    + 'should be i - 1 or the bound Count - 1 is for you to decide';
  R_LOOPB_TYPE      = 'the type is not proven - an array needs High(), a '
    + 'string has to run from 1';
  R_LOOPB_MANY      = 'the reported line carries %d for headers with this '
    + 'range - ambiguous';
  R_LOOPB_OTHER     = 'the for header on the line has another range than '
    + 'the finding';
  R_LOOPB_LINES     = 'the for header goes over more than one line';
  R_LOOPB_DIRECTIVE = 'compiler directive in the line of the for header';
  R_LOOPB_NONCODE   = 'comment or string in the for header';
  R_LOOPB_BOTH_ENDS = 'a string from 0 to High() + 1 is wrong at both ends '
    + '- correct the range by hand';

type
  // Was die Hilfe am Kopf tut (aus Meldung und Rat).
  TRdxLoopBoundAction = (
    lbaNone,          // keine Hilfe (Grund in der Meldungspruefung)
    lbaMinusOne,      // 'X.Count' -> 'X.Count - 1'
    lbaLengthToHigh,  // 'Length(A)' -> 'High(A)'
    lbaLowToOne,      // Untergrenze '0' -> '1'
    lbaDropPlusOne    // '.. + 1' weg
  );

  // Der Kopf laut Meldung.
  TRdxLoopBoundHead = record
    LoopVar : string;   // 'i'
    LowText : string;   // '0', '1', 'Low(A)'
    HiText  : string;   // 'List.Count', 'Length(A)', 'High(A) + 1'
    Advice  : string;   // der Rat hinter ' - '
  end;

  TRdxLoopBoundFix = class
  public
    // Die Teile der Meldung 'Loop past the last index: V := LO to HI with
    // ZUGRIFF - RAT'; False, wenn eines fehlt.
    class function HeadOf(const AMessage: string;
      out AHead: TRdxLoopBoundHead): Boolean; static;

    // Was die Hilfe tut; lbaNone mit dem Grund in AReason (uebersetzt).
    class function ActionOf(const AHead: TRdxLoopBoundHead;
      out AReason: string): TRdxLoopBoundAction; static;

    // Der Bereich nach der Hilfe ('0 to List.Count - 1') fuer den
    // Menuetext; '' ohne Hilfe.
    class function RangeAfter(const AMessage: string): string; static;

    // Der Planer (TRdxMapPlanner-Form, MapFix oeffnet die Code-Sicht):
    // eine Ersetzung im einen passenden Kopf auf ALine, sonst der Grund.
    class function LastIndex(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(), MsgMovedSuffix (E29)

const
  SPAN_LOOPB = 'loopbound';
  // Kopien der festen Teile aus uLoopBoundScan (s. Kopf).
  KEY_PREFIX   = 'Loop past the last index: ';
  KEY_ASSIGN   = ' := ';
  KEY_TO       = ' to ';
  KEY_WITH     = ' with ';
  KEY_ADVICE   = ' - ';
  KEY_PLUS_ONE = ' + 1';
  ADV_LAST     = 'the last pass is out of range; the bound should be ';
  ADV_STR_ZERO = 'strings start at 1; the loop should run 1 to Length(%s)';
  ADV_STR_PLUS = 'strings end at Length(%s); the bound should be Length(%s)';
  ADV_STR_HIGH = 'strings start at 1; the loop should run 1 to High(%s)';

type
  // Ein for-Kopf auf der Code-Sicht: die Token, die die Hilfe braucht, und
  // die Texte wie in der Meldung.
  TRdxLoopSite = record
    ForTok   : TRdxToken;
    LowFirst : TRdxToken;   // erstes Token der Untergrenze
    HiFirst  : TRdxToken;   // erstes Token der Obergrenze
    HiWord   : TRdxToken;   // 'Count' bzw. 'Length'/'High'
    Close    : TRdxToken;   // ')' von Length(..)/High(..)
    Plus     : TRdxToken;   // '+' von ' + 1', leer ohne
    One      : TRdxToken;   // '1' von ' + 1'
    DoTok    : TRdxToken;
    Head     : TRdxLoopBoundHead;   // ohne Advice
    OneLine  : Boolean;     // alle Token auf der Zeile des for
  end;

{ ---- Meldung ---- }

// Der Text zwischen AFrom und dem naechsten AKey ab APos; APos steht danach
// hinter AKey. False ohne AKey.
function TakeUntil(const S, AKey: string; var APos: Integer;
  out APart: string): Boolean;
var
  P : Integer;
begin
  P := Pos(AKey, Copy(S, APos, MaxInt));
  Result := P > 0;
  if not Result then
  begin
    APart := '';
    Exit;
  end;
  APart := Copy(S, APos, P - 1);
  APos := APos + P - 1 + Length(AKey);
end;

// Endet S auf AKey (gleich geschrieben)?
function EndsWithKey(const S, AKey: string): Boolean;
begin
  Result := (Length(S) >= Length(AKey)) and
    (Copy(S, Length(S) - Length(AKey) + 1, Length(AKey)) = AKey);
end;

// Die Sammlung der Obergrenze: 'List' aus 'List.Count', 'A' aus
// 'Length(A)' / 'High(A) + 1'.
function CollectionOf(const AHi: string): string;
var
  H : string;
  P : Integer;
begin
  H := AHi;
  if EndsWithKey(H, KEY_PLUS_ONE) then
    H := Copy(H, 1, Length(H) - Length(KEY_PLUS_ONE));
  P := Pos('(', H);
  if (P > 0) and EndsWithKey(H, ')') then
    Exit(Copy(H, P + 1, Length(H) - P - 1));
  if SameText(Copy(H, Length(H) - 5, 6), '.Count') then
    Exit(Copy(H, 1, Length(H) - 6));
  Result := '';
end;

// Beginnt AHi mit dem Funktionsnamen AName ('Length(', 'High(')?
function StartsWithCall(const AHi, AName: string): Boolean;
begin
  Result := SameText(Copy(AHi, 1, Length(AName) + 1), AName + '(');
end;

// 'High' in der Schreibweise von AModel ('LENGTH' -> 'HIGH', 'length' ->
// 'high', sonst 'High').
function HighLike(const AModel: string): string;
begin
  if (Length(AModel) > 1) and (AModel = UpperCase(AModel)) then
    Result := 'HIGH'
  else if (AModel <> '') and (AModel = LowerCase(AModel)) then
    Result := 'high'
  else
    Result := 'High';
end;

// Die Aktion fuer die Obergrenze 'Length(C)' ohne + 1.
function LengthAction(const AHead: TRdxLoopBoundHead; const C: string;
  out AReason: string): TRdxLoopBoundAction;
begin
  Result := lbaNone;
  AReason := '';
  if AHead.Advice = ADV_LAST + 'High(' + C + ')' then
    Result := lbaLengthToHigh
  else if (AHead.LowText = '0') and
          (AHead.Advice = Format(ADV_STR_ZERO, [C])) then
    Result := lbaLowToOne
  else
    AReason := _(R_LOOPB_TYPE);
end;

{ ---- Code-Sicht ---- }

// Kette Wort(.Wort)* ab T; ALast = ihr letztes Token, AText wie
// geschrieben. False ohne Wort.
function ReadChain(AMap: TRdxCodeMap; const T: TRdxToken;
  out ALast: TRdxToken; out AText: string): Boolean;
var
  Dot   : TRdxToken;
  Parts : TArray<string>;
begin
  ALast := T;
  AText := '';
  Result := T.IsWord;
  if not Result then Exit;
  Parts := nil;
  AddText(Parts, TokText(AMap, T));
  Dot := After(AMap, T);
  while (Dot.Low = '.') and After(AMap, Dot).IsWord do
  begin
    ALast := After(AMap, Dot);
    AddText(Parts, TokText(AMap, ALast));
    Dot := After(AMap, ALast);
  end;
  AText := JoinStrings(Parts, '.');
end;

// 'Name(Kette)' ab T (T = Name): AClose = ')', AText = 'Name(Kette)'.
function ReadCall(AMap: TRdxCodeMap; const T: TRdxToken;
  out AClose: TRdxToken; out AText: string): Boolean;
var
  Open, Last : TRdxToken;
  Inner      : string;
begin
  Open := After(AMap, T);
  Result := (Open.Low = '(') and ReadChain(AMap, After(AMap, Open), Last,
    Inner);
  if not Result then Exit;
  AClose := After(AMap, Last);
  Result := AClose.Low = ')';
  AText := TokText(AMap, T) + '(' + Inner + ')';
end;

// Untergrenze ab T: '0', '1' oder 'Low(Kette)'; ALast = ihr letztes Token.
function ReadLow(AMap: TRdxCodeMap; const T: TRdxToken; out ALast: TRdxToken;
  out AText: string): Boolean;
begin
  ALast := T;
  AText := TokText(AMap, T);
  if (T.Low = '0') or (T.Low = '1') then
    Exit(True);
  Result := (T.Low = 'low') and ReadCall(AMap, T, ALast, AText);
end;

// Obergrenze ab ASite.HiFirst: 'Kette.Count', 'Length(Kette)' oder
// 'High(Kette)' mit optionalem ' + 1'; ALast = ihr letztes Token.
function ReadHigh(AMap: TRdxCodeMap; var ASite: TRdxLoopSite;
  out ALast: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  T := ASite.HiFirst;
  if (T.Low = 'length') or (T.Low = 'high') then
  begin
    ASite.HiWord := T;
    Result := ReadCall(AMap, T, ASite.Close, ASite.Head.HiText);
    if not Result then Exit;
    ALast := ASite.Close;
    ASite.Plus := After(AMap, ASite.Close);
    ASite.One := After(AMap, ASite.Plus);
    if (ASite.Plus.Low = '+') and (ASite.One.Low = '1') then
    begin
      ASite.Head.HiText := ASite.Head.HiText + KEY_PLUS_ONE;
      ALast := ASite.One;
    end
    else
      ASite.Plus := Default(TRdxToken);
    Exit;
  end;
  Result := ReadChain(AMap, T, ALast, ASite.Head.HiText) and
    (ALast.Low = 'count') and not SameTok(ALast, T);
  ASite.HiWord := ALast;
end;

// Der Kopf ab AFor: for, optional var, die Variable (auch mit Typ), ':=',
// Unter- und Obergrenze, do.
function ReadSite(AMap: TRdxCodeMap; const AFor: TRdxToken;
  out ASite: TRdxLoopSite): Boolean;
var
  T, Last : TRdxToken;
begin
  ASite := Default(TRdxLoopSite);
  ASite.ForTok := AFor;
  T := After(AMap, AFor);
  if T.Low = 'var' then
    T := After(AMap, T);
  Result := T.IsWord;
  if not Result then Exit;
  ASite.Head.LoopVar := TokText(AMap, T);
  T := After(AMap, T);
  if T.Low = ':' then
    while (T.Low <> '') and (T.Low <> ':=') and (T.Low <> 'do') and
          (T.Low <> ';') do
      T := After(AMap, T);
  ASite.LowFirst := After(AMap, T);
  Result := (T.Low = ':=') and ReadLow(AMap, ASite.LowFirst, Last,
    ASite.Head.LowText) and (After(AMap, Last).Low = 'to');
  if not Result then Exit;
  ASite.HiFirst := After(AMap, After(AMap, Last));
  Result := ReadHigh(AMap, ASite, Last);
  if not Result then Exit;
  ASite.DoTok := After(AMap, Last);
  Result := ASite.DoTok.Low = 'do';
  ASite.OneLine := ASite.DoTok.Line = AFor.Line;
end;

// Steht an T ein for-Kopf mit dem Bereich AArg ('I'#1'LO'#1'HI')? Ein Kopf
// ueber mehrere Zeilen zaehlt nur, wenn AArg mit #2 beginnt (Probe fuer
// den Grund R_LOOPB_LINES).
function IsHeadOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  S     : TRdxLoopSite;
  Want  : string;
  Lines : Boolean;
begin
  Result := False;
  if (T.Low <> 'for') or not IsKeywordAfter(T, Before(AMap, T)) then Exit;
  if not ReadSite(AMap, T, S) then Exit;
  Lines := (AArg <> '') and (AArg[1] = #2);
  Want := AArg;
  if Lines then
    Want := Copy(AArg, 2, MaxInt);
  Result := (S.OneLine <> Lines) and (Want = S.Head.LoopVar + #1 +
    S.Head.LowText + #1 + S.Head.HiText);
end;

// Der eine passende Kopf auf ALine; '' oder der Grund.
function FindSite(AMap: TRdxCodeMap; ALine: Integer;
  const AHead: TRdxLoopBoundHead; out ASite: TRdxLoopSite): string;
var
  Arg : string;
  Hit : TRdxToken;
  N   : Integer;
begin
  ASite := Default(TRdxLoopSite);
  Arg := AHead.LoopVar + #1 + AHead.LowText + #1 + AHead.HiText;
  N := CountTokensOnLine(AMap, ALine, IsHeadOf, Arg, Hit);
  if N > 1 then
    Exit(_(R_LOOPB_MANY, [N]));
  if N = 0 then
  begin
    if CountTokensOnLine(AMap, ALine, IsHeadOf, #2 + Arg, Hit) > 0 then
      Exit(_(R_LOOPB_LINES));
    Exit(MsgMovedSuffix(_(R_LOOPB_OTHER)));
  end;
  ReadSite(AMap, Hit, ASite);
  if DirectiveInLines(AMap, ALine, ALine) then
    Result := _(R_LOOPB_DIRECTIVE)
  else if AMap.HasNonCode(ALine, ASite.ForTok.Col, ASite.DoTok.EndCol - 1) then
    Result := _(R_LOOPB_NONCODE)
  else
    Result := '';
end;

// Die Ersetzung eines Tokens bzw. einer Spanne auf ALine.
function EditOf(AMap: TRdxCodeMap; ALine, AFromCol, AToCol: Integer;
  const ANewText: string): TRdxEdit;
begin
  Result := Default(TRdxEdit);
  Result.Span := TRefactorSpan.Make(SPAN_LOOPB, ALine, AFromCol, ALine,
    AToCol);
  Result.Expected := Copy(AMap.Raw(ALine), AFromCol, AToCol - AFromCol);
  Result.NewText := ANewText;
end;

{ TRdxLoopBoundFix }

class function TRdxLoopBoundFix.HeadOf(const AMessage: string;
  out AHead: TRdxLoopBoundHead): Boolean;
var
  P      : Integer;
  Access : string;
begin
  AHead := Default(TRdxLoopBoundHead);
  Result := Copy(AMessage, 1, Length(KEY_PREFIX)) = KEY_PREFIX;
  if not Result then Exit;
  P := Length(KEY_PREFIX) + 1;
  Result := TakeUntil(AMessage, KEY_ASSIGN, P, AHead.LoopVar) and
    TakeUntil(AMessage, KEY_TO, P, AHead.LowText) and
    TakeUntil(AMessage, KEY_WITH, P, AHead.HiText) and
    TakeUntil(AMessage, KEY_ADVICE, P, Access);
  if Result then
    AHead.Advice := Copy(AMessage, P, MaxInt);
  Result := Result and (AHead.LoopVar <> '') and (AHead.LowText <> '') and
    (AHead.HiText <> '') and (Access <> '') and (AHead.Advice <> '');
end;

class function TRdxLoopBoundFix.ActionOf(const AHead: TRdxLoopBoundHead;
  out AReason: string): TRdxLoopBoundAction;
var
  C : string;
begin
  Result := lbaNone;
  AReason := '';
  C := CollectionOf(AHead.HiText);
  if C = '' then
    AReason := _(R_LOOPB_MESSAGE)
  else if not EndsWithKey(AHead.HiText, KEY_PLUS_ONE) and
          not StartsWithCall(AHead.HiText, 'Length') then
  begin
    // X.Count
    if AHead.LowText = '1' then
      AReason := _(R_LOOPB_FROM_ONE)
    else if AHead.Advice = ADV_LAST + C + '.Count - 1' then
      Result := lbaMinusOne
    else
      AReason := _(R_LOOPB_MESSAGE);
  end
  else if not EndsWithKey(AHead.HiText, KEY_PLUS_ONE) then
    Result := LengthAction(AHead, C, AReason)
  else if (AHead.Advice = ADV_LAST + 'High(' + C + ')') or
          (AHead.Advice = Format(ADV_STR_PLUS, [C, C])) then
    Result := lbaDropPlusOne
  else if AHead.Advice = Format(ADV_STR_HIGH, [C]) then
    AReason := _(R_LOOPB_BOTH_ENDS)
  else
    AReason := _(R_LOOPB_TYPE);
end;

class function TRdxLoopBoundFix.RangeAfter(const AMessage: string): string;
var
  H      : TRdxLoopBoundHead;
  Reason : string;
  Hi     : string;
begin
  Result := '';
  if not HeadOf(AMessage, H) then Exit;
  Hi := H.HiText;
  case ActionOf(H, Reason) of
    lbaMinusOne:
      Result := H.LowText + KEY_TO + Hi + ' - 1';
    lbaLengthToHigh:
      Result := H.LowText + KEY_TO + HighLike(Copy(Hi, 1, 6)) +
        Copy(Hi, 7, MaxInt);
    lbaLowToOne:
      Result := '1' + KEY_TO + Hi;
    lbaDropPlusOne:
      Result := H.LowText + KEY_TO +
        Copy(Hi, 1, Length(Hi) - Length(KEY_PLUS_ONE));
  else // lbaNone: keine Hilfe, kein Bereich
    Result := '';
  end;
end;

class function TRdxLoopBoundFix.LastIndex(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Head   : TRdxLoopBoundHead;
  Action : TRdxLoopBoundAction;
  Site   : TRdxLoopSite;
  W      : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if not HeadOf(AMessage, Head) then
  begin
    AReason := _(R_LOOPB_MESSAGE);
    Exit;
  end;
  Action := ActionOf(Head, AReason);
  if Action = lbaNone then Exit;
  AReason := FindSite(AMap, ALine, Head, Site);
  if AReason <> '' then Exit;
  case Action of
    lbaMinusOne:
      begin
        W := TokText(AMap, Site.HiWord);
        AEdit := EditOf(AMap, ALine, Site.HiWord.Col, Site.HiWord.EndCol,
          W + ' - 1');
      end;
    lbaLengthToHigh:
      AEdit := EditOf(AMap, ALine, Site.HiWord.Col, Site.HiWord.EndCol,
        HighLike(TokText(AMap, Site.HiWord)));
    lbaLowToOne:
      AEdit := EditOf(AMap, ALine, Site.LowFirst.Col, Site.LowFirst.EndCol,
        '1');
  else // lbaDropPlusOne
    AEdit := EditOf(AMap, ALine, Site.Close.Col, Site.One.EndCol, ')');
  end;
  Result := True;
end;

end.
