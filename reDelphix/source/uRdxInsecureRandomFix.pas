unit uRdxInsecureRandomFix;

// reDelphix - Editorhilfe SCA167 InsecureRandom, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, Zeile SCA167:
// "bedingt"):
//   'Randomize;' in den initialization-Abschnitt der Unit - als erste
//   Anweisung eines vorhandenen, sonst ein neuer Abschnitt vor 'end.' (bzw.
//   vor einem finalization ohne initialization, FPC).
// AENDERT DAS VERHALTEN (Changes: True): die Zufallsfolge ist danach bei
// jedem Lauf eine andere.
//
// WAS DER DETEKTOR MELDET (uInsecureRandom): jeden Aufruf von Random,
// RandomRange oder RandomFrom (unqualifiziert, System./Math./Self.), wenn
// die Unit NIRGENDS Randomize nennt (Aufruf im AST oder das Wort im Code
// ohne Kommentare und Strings). Meldung '<Aufruf>(...) without prior
// Randomize - deterministic sequence (Seed=0 until Randomize)', Zeile der
// Anweisung, ohne Spalte. Gemeint ist die WIEDERHOLBARE Folge (Seed 0 bei
// jedem Start), nicht kryptographische Sicherheit - die prueft der Detektor
// ausdruecklich nicht (Kopf dort, fullDescription in rules/sca-rules.json).
// Dafuer ist Randomize genau der Fix; fuer Token, Salze und Passwoerter
// bleibt Random auch danach ungeeignet - das sagt der Hinweis.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * die Meldung nennt keinen Random-Aufruf, oder auf der Zeile (und den
//     Folgezeilen der Anweisung) steht keiner als Code - Zeile verschoben;
//   * die Datei ruft Randomize schon (Fund veraltet) oder setzt RandSeed
//     (Korpus: 9 von 134 Dateien setzen den Startwert bewusst -
//     reproduzierbare Folge; der Detektor sieht das nicht);
//   * keine Unit (program/library/package: Randomize gehoert an den Anfang
//     des Hauptblocks - von Hand; Include-Datei oder Skript ohne 'unit'),
//     kein bzw. mehr als ein implementation,
//     mehr als ein initialization bzw. finalization, kein 'end.';
//   * die Unit endet mit 'begin .. end.' (SCA088-Form) - erst die Hilfe zu
//     SCA088;
//   * die Einfuegestelle liegt in einem offenen {$IF}/{$IFDEF}-Block oder
//     teilt ihre Zeile (das 'end.' bzw. finalization nicht allein am
//     Zeilenanfang, die Zeile beginnt in einem Kommentar).
// Eine Anwendung erledigt alle Funde der Datei.
//
// Die Unit bindet nur Textlogik (FPC-Pruefstand); den Adapter der Tabelle
// (PlanInsecureRandom ueber MapFix) bekommt uRdxFixTable bei der
// Integration.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_RND_NO_CALL     = 'the message names no call of Random, RandomRange or '
    + 'RandomFrom';
  R_RND_MOVED       = 'no call of %s on the reported line';
  R_RND_HAS_RANDOMIZE = 'the file already calls Randomize';
  R_RND_RANDSEED    = 'the file sets RandSeed (line %d) - a fixed seed may be '
    + 'intended (reproducible sequence)';
  R_RND_NOT_UNIT    = 'not a unit - in a program or library Randomize belongs '
    + 'at the start of the main block; %s';
  R_RND_NO_UNIT     = 'the file does not start with unit (include file or '
    + 'script?) - the help does not find its end';
  R_RND_NO_IMPL     = 'no single implementation part - the end of the unit is '
    + 'not provable';
  R_RND_MANY        = '%d sections "%s" - ambiguous';
  R_RND_NO_END      = 'no "end." at the end of the unit';
  R_RND_LEGACY      = 'the unit ends with "begin ... end." (SCA088) - turn '
    + 'the begin into initialization first';
  R_RND_CONDITIONAL = 'the place for Randomize lies in a conditional '
    + 'compilation block';
  R_RND_LINE_FORM   = '"%s" does not stand at the start of its own line';

type
  // Der Planer von SCA167 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxInsecureRandomFix = class
  public
    // Der Aufruf aus der Meldung ('System.Random(...) without prior
    // Randomize ...' -> 'System.Random'); '' ohne diese Form oder wenn sein
    // letztes Glied nicht Random, RandomRange oder RandomFrom ist.
    class function CallOf(const AMessage: string): string; static;

    // ALine ist die Zeile der Anweisung mit dem Aufruf. Liefert die eine
    // Einfuegung von 'Randomize;' (s. Kopf) oder den Grund.
    class function AddRandomize(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_167      = 'sca167';
  KEY_CALL      = '(...) without prior Randomize';
  KW_RANDOMIZE  = 'randomize';
  KW_RANDSEED   = 'randseed';
  KW_INIT       = 'initialization';
  KW_FINAL      = 'finalization';
  KW_IMPL       = 'implementation';
  NEW_STMT      = 'Randomize;';
  // Die Aufrufe, die der Detektor meldet ...
  RANDOM_CALLS: array[0..2] of string = ('random', 'randomrange', 'randomfrom');
  // ... und die Qualifizierer, die er als RTL-Random zaehlt.
  RTL_QUALIFIERS: array[0..2] of string = ('system', 'math', 'self');
  // So viele Zeilen hinter der gemeldeten traegt die Anweisung den Aufruf
  // noch ('X :=' auf der einen, 'Random(6);' auf der naechsten).
  CALL_LOOKAHEAD = 4;
  // Woerter, mit denen eine Datei beginnt, die keine Unit ist.
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');
  // Bedingte Uebersetzung: oeffnet bzw. schliesst einen Block.
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');

// Den Leerraum am Zeilenanfang liefert uRdxCodeMap.IndentOf (bis zur
// Hygiene-Welle H1 hier byte-gleich kopiert).

// AWord in der Schreibweise von AModel: ganz gross, gross am Anfang oder
// klein.
function CaseLike(const AModel, AWord: string): string;
begin
  Result := LowerCase(AWord);
  if AModel = '' then Exit;
  if (AModel = UpperCase(AModel)) and (Length(AModel) > 1) then
    Result := UpperCase(AWord)
  else if AModel[1] = UpperCase(AModel[1]) then
    Result := UpperCase(Copy(AWord, 1, 1)) + Copy(Result, 2, MaxInt);
end;

// Die Tiefe der bedingten Uebersetzung vor (ALine, ACol) - dieselbe Regel
// wie in uRdxThreadResumeFix (privat; Kandidat fuer uRdxCodeMap).
function ConditionalDepthAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Integer;
var
  Li, Co, Last : Integer;
  Arg          : Boolean;
  W            : string;
begin
  Result := 0;
  for Li := 1 to ALine do
  begin
    Last := Length(AMap.Raw(Li));
    if Li = ALine then
      Last := ACol - 1;
    for Co := 1 to Last do
      if OpensDirective(AMap, Li, Co) then
      begin
        W := DirectiveWord(AMap, Li, Co, Arg);
        if InList(W, COND_OPEN) then
          Inc(Result)
        else if InList(W, COND_CLOSE) and (Result > 0) then
          Dec(Result);
      end;
  end;
end;

// Das Wort ALow (klein) im Code der Datei: die Zahl der Token, das erste in
// AFirst. AKeyword: nur als Schluesselwort (nicht hinter '.', '@', '&') -
// fuer die Abschnitte; Randomize und RandSeed zaehlen auch qualifiziert
// ('System.Randomize'), wie beim Detektor das ganze Wort.
function CountWord(AMap: TRdxCodeMap; const ALow: string; AKeyword: Boolean;
  out AFirst: TRdxToken): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  AFirst := Default(TRdxToken);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if (T.Low = ALow)
       and (not AKeyword or IsKeywordAfter(T, Before(AMap, T))) then
    begin
      if Result = 0 then
        AFirst := T;
      Inc(Result);
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Steht der Aufruf ALowCall (letztes Glied, klein) als Code auf ALine oder
// den Folgezeilen der Anweisung - unqualifiziert oder hinter System./
// Math./Self. wie beim Detektor?
function CallOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ALowCall: string): Boolean;
var
  T, Dot : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line >= ALine)
        and (T.Line <= ALine + CALL_LOOKAHEAD) do
  begin
    if T.Low = ALowCall then
    begin
      Dot := Before(AMap, T);
      if (Dot.Low <> '.')
         or InList(Before(AMap, Dot).Low, RTL_QUALIFIERS) then
        Exit(True);
    end;
    // Die Anweisung endet am ';' - die Zeilen danach gehoeren nicht dazu.
    if (T.Low = ';') and (T.Line > ALine) then
      Exit;
    T := After(AMap, T);
  end;
end;

// Weder Randomize noch RandSeed im Code der Datei. '' oder der Grund.
function SeedReason(AMap: TRdxCodeMap): string;
var
  T : TRdxToken;
begin
  Result := '';
  if CountWord(AMap, KW_RANDOMIZE, False, T) > 0 then
    Exit(MsgStaleSuffix(_(R_RND_HAS_RANDOMIZE)));
  if CountWord(AMap, KW_RANDSEED, False, T) > 0 then
    Result := _(R_RND_RANDSEED, [T.Line]);
end;

// Das 'end' vor dem letzten '.' der Datei; Low = '' ohne.
function UnitEnd(AMap: TRdxCodeMap): TRdxToken;
var
  Li : Integer;
  T  : TRdxToken;
begin
  Result := Default(TRdxToken);
  for Li := AMap.LineCount downto 1 do
  begin
    if not HasWordNoCase(AMap.Raw(Li), 'end') then Continue;
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      if (T.Low = 'end') and (After(AMap, T).Low = '.') then
        Result := T;
      T := After(AMap, T);
    end;
    if Result.Low <> '' then Exit;
  end;
end;

// Endet die Unit mit 'begin .. end.' (SCA088)? Rueckwaerts von AEnd bis
// zum naechsten Routinenkopf bzw. implementation: schliesst die end-Bilanz
// eines begin an AEnd?
function LegacyBody(AMap: TRdxCodeMap; const AEnd: TRdxToken): Boolean;
var
  T, P, EndTok, Last : TRdxToken;
begin
  Result := False;
  T := Before(AMap, AEnd);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if IsRoutineHeadAfter(T, P) or ((T.Low = KW_IMPL) and IsKeywordAfter(T, P))
    then
      Exit;
    if (T.Low = 'begin') and IsKeywordAfter(T, P) then
    begin
      BlockEnd(AMap, T, nil, EndTok, Last);
      if SameTok(EndTok, AEnd) then
        Exit(True);
    end;
    T := P;
  end;
end;

// Vorhandenes initialization AInit: 'Randomize;' als erste Anweisung - in
// einer neuen Zeile darunter (eine Stufe tiefer, die Stufe aus der Zeile
// danach), oder direkt dahinter, wenn auf der Zeile Code oder eine
// Direktive folgt.
procedure IntoSection(AMap: TRdxCodeMap; const AInit: TRdxToken;
  out AEdit: TRdxEdit);
var
  L, Indent, Kw : string;
  N             : TRdxToken;
  Col           : Integer;
begin
  AEdit := Default(TRdxEdit);
  L := AMap.Raw(AInit.Line);
  Kw := TokText(AMap, AInit);
  N := After(AMap, AInit);
  if ((N.Low = '') or (N.Line > AInit.Line))
     and TailIsQuiet(AMap, AInit.Line, AInit.EndCol - 1)
     and CanAppendLine(AMap, AInit.Line, AInit.EndCol - 1) then
  begin
    // Am Zeilenende anhaengen: ein Kommentar hinter initialization bleibt
    // auf seiner Zeile. Das letzte Zeichen ist nie leer (die Zeile traegt
    // das Schluesselwort).
    Indent := IndentOf(L);
    if N.Low <> '' then
      Indent := Indent + IndentStep(Indent, AMap.Raw(N.Line))
    else
      Indent := Indent + IndentStep(Indent, '');
    Col := Length(L);
    AEdit.Span := TRefactorSpan.Make(SPAN_167, AInit.Line, Col, AInit.Line,
      Col + 1);
    AEdit.Expected := Copy(L, Col, 1);
    AEdit.NewText := AEdit.Expected + #10 + Indent + NEW_STMT;
  end
  else
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_167, AInit.Line, AInit.Col,
      AInit.Line, AInit.EndCol);
    AEdit.Expected := Kw;
    AEdit.NewText := Kw + ' ' + NEW_STMT;
  end;
end;

// Neuer Abschnitt vor ABefore ('end' des 'end.' bzw. finalization): das
// Wort steht allein am Zeilenanfang; davor kommen 'initialization', die
// Anweisung eine Stufe tiefer und eine Leerzeile.
procedure NewSection(AMap: TRdxCodeMap; const ABefore: TRdxToken;
  out AEdit: TRdxEdit);
var
  Indent, Kw : string;
begin
  AEdit := Default(TRdxEdit);
  Indent := IndentOf(AMap.Raw(ABefore.Line));
  Kw := TokText(AMap, ABefore);
  AEdit.Span := TRefactorSpan.Make(SPAN_167, ABefore.Line, ABefore.Col,
    ABefore.Line, ABefore.EndCol);
  AEdit.Expected := Kw;
  AEdit.NewText := CaseLike(Kw, KW_INIT) + #10 + Indent
    + IndentStep(Indent, '') + NEW_STMT + #10 + #10 + Indent + Kw;
end;

// Wo der Aufruf hingehoert: das initialization (AInit, Low = '' ohne) bzw.
// das Wort, vor das ein neuer Abschnitt kommt (ABefore). '' oder der Grund.
function PlaceReason(AMap: TRdxCodeMap; out AInit, ABefore: TRdxToken): string;
var
  Impl, Fin, EndTok : TRdxToken;
  n                 : Integer;
begin
  ABefore := Default(TRdxToken);
  AInit := Default(TRdxToken);
  if InList(NextToken(AMap, 1, 1).Low, PROGRAM_WORDS) then
    Exit(_(R_RND_NOT_UNIT, [MsgByHand]));
  if NextToken(AMap, 1, 1).Low <> 'unit' then
    Exit(_(R_RND_NO_UNIT));
  if CountWord(AMap, KW_IMPL, True, Impl) <> 1 then
    Exit(_(R_RND_NO_IMPL));
  EndTok := UnitEnd(AMap);
  if (EndTok.Low = '') or not TokBefore(Impl, EndTok) then
    Exit(_(R_RND_NO_END));
  n := CountWord(AMap, KW_INIT, True, AInit);
  if n > 1 then
    Exit(_(R_RND_MANY, [n, KW_INIT]));
  if n = 1 then
  begin
    if ConditionalDepthAt(AMap, AInit.Line, AInit.Col) > 0 then
      Exit(_(R_RND_CONDITIONAL));
    Exit('');
  end;
  n := CountWord(AMap, KW_FINAL, True, Fin);
  if n > 1 then
    Exit(_(R_RND_MANY, [n, KW_FINAL]));
  if n = 1 then
    ABefore := Fin
  else if LegacyBody(AMap, EndTok) then
    Exit(_(R_RND_LEGACY))
  else
    ABefore := EndTok;
  if not FirstOnLine(AMap, ABefore) or AMap.StartsInside(ABefore.Line) then
    Exit(_(R_RND_LINE_FORM, [TokText(AMap, ABefore)]));
  if ConditionalDepthAt(AMap, ABefore.Line, ABefore.Col) > 0 then
    Exit(_(R_RND_CONDITIONAL));
  Result := '';
end;

{ TRdxInsecureRandomFix }

class function TRdxInsecureRandomFix.CallOf(const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos(KEY_CALL, AMessage);
  if P <= 1 then Exit;
  Result := Trim(Copy(AMessage, 1, P - 1));
  if not InList(LowerCase(LastPart(Result)), RANDOM_CALLS) then
    Result := '';
end;

class function TRdxInsecureRandomFix.AddRandomize(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Call         : string;
  Init, Target : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Call := CallOf(AMessage);
  if Call = '' then
  begin
    AReason := _(R_RND_NO_CALL);
    Exit;
  end;
  if not CallOnLine(AMap, ALine, LowerCase(LastPart(Call))) then
  begin
    AReason := MsgMovedSuffix(_(R_RND_MOVED, [Call]));
    Exit;
  end;
  AReason := SeedReason(AMap);
  if AReason = '' then
    AReason := PlaceReason(AMap, Init, Target);
  if AReason <> '' then
    Exit;
  if Init.Low <> '' then
    IntoSection(AMap, Init, AEdit)
  else
    NewSection(AMap, Target, AEdit);
  Result := True;
end;

end.
