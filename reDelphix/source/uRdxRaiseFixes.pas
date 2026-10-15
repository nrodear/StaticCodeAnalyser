unit uRdxRaiseFixes;

// reDelphix - Editorhilfen an Ausnahmen und leeren Rumpfen, OHNE ToolsAPI
// und ohne Parser (Konzept_Editorhilfen_2026-10-08, Abschnitt 4.4):
//   SCA020 EmptyMethod: in den leeren Rumpf (a) einen Absichtskommentar
//          (bedeutungsgleich - uEmptyMethod wertet ihn als konform) oder
//          (b) 'raise ENotImplemented.Create(''<Name>'');' (aendert das
//          Verhalten) - zwei Eintraege wie bei SCA168.
//   SCA120 MissingRaise: 'raise ' vor 'EFoo.Create(..)', das als ganze
//          Anweisung steht (aendert das Verhalten: das ist der Fix).
//   SCA122 ReRaiseException: 'raise E;' -> 'raise;' im Handler 'on E: ..
//          do' (bedeutungsgleich bis auf den Stack-Trace - solange E im
//          Handler nicht neu zugewiesen wird).
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

const
  // SCA020 (b): %s ist der Name der Methode wie im Kopf.
  RAISE_NOT_IMPLEMENTED = 'raise ENotImplemented.Create(''%s'');';
  // SCA020 (a): erkennt uEmptyMethod als Absicht (Buchstaben, kein ';').
  INTENT_LINE   = '// intentionally empty';
  INTENT_INLINE = '{ intentionally empty }';

type
  // Die Planer an Ausnahmen und leeren Rumpfen (SCA020, SCA120, SCA122):
  // reine Textlogik auf der Code-Sicht. Die uses-Ergaenzung (SysUtils fuer
  // ENotImplemented) und die Kennzeichnung "aendert Verhalten" setzt der
  // Aufrufer (uRdxRecipeRunner, uRdxFixTable).
  TRdxRaiseFixes = class
  public
    // SCA020: der leere Rumpf der Methode, deren Kopf auf ALine beginnt
    // (Meldung 'Method body is empty'). AStatementFmt = '': der
    // Absichtskommentar; sonst diese Anweisung (Format mit dem Namen der
    // Methode, RAISE_NOT_IMPLEMENTED). Stehen begin und end auf eigenen
    // Zeilen, kommt sie in eine eigene Zeile dazwischen (eine Stufe
    // tiefer), sonst inline hinter das begin. Keine Hilfe bei lokalen
    // Routinen zwischen Kopf und Rumpf, bei asm, wenn der Rumpf nicht leer
    // ist, und - nur mit Anweisung - bei constructor/destructor (eine
    // Exception dort hinterliesse ein halbes Objekt).
    class function EmptyBody(AMap: TRdxCodeMap; ALine: Integer;
      const AStatementFmt: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA120: 'EFoo.Create(..)' auf ALine (EFoo aus der Meldung 'Exception
    // EFoo.Create(...) is constructed ...') als ganze Anweisung - davor ein
    // Anweisungsanfang, hinter der ')' ihr Ende - bekommt 'raise ' davor.
    class function MissingRaise(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA122: 'raise E' auf ALine (E aus der Meldung 'Re-raise of bound
    // variable "E" ...') -> 'raise'. Nur, wenn rueckwaerts der eigene
    // Handler 'on E: T do' kommt, bevor ein except/finally oder eine
    // anonyme Methode: im except eines inneren try wuerfe 'raise;' die
    // innere Exception weiter. Und nicht, wenn E dazwischen neu zugewiesen
    // wird ('E := EWrapped.Create(..)'): 'raise E' wirft dann das neue
    // Objekt, 'raise;' die urspruengliche Exception (Review R3, Charge FC).
    // GRENZE: eine Uebergabe als var-/out-Argument ('Wrap(E)') aendert E
    // ebenso - die sieht der Planer nicht.
    class function ReRaise(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxStructFixes;   // StartsStatementAt (SCA120: kein bedingter Ausdruck),
                     // CommentInRange

const
  SPAN_020 = 'sca020';
  SPAN_120 = 'sca120';
  SPAN_122 = 'sca122';
  // Hier endet eine Anweisung.
  STATEMENT_ENDS: array[0..5] of string = (';', 'end', 'else', 'until',
    'except', 'finally');
  KEY_EXCEPTION = 'Exception ';
  KEY_CREATE    = '.Create';
  // Wie uMissingRaise.CreateSuffixOk: nur diese Create-Varianten meldet der
  // Detektor ('CreateAndRaise' nicht).
  CREATE_SUFFIXES: array[0..7] of string = ('', 'fmt', 'res', 'help',
    'resfmt', 'reshelp', 'fmthelp', 'resfmthelp');

{ ---- SCA020 ---- }

type
  // Kopf und Rumpf einer Methode (EmptyBody).
  TRdxMethodBody = record
    Keyword  : TRdxToken;   // procedure, function, constructor ...
    Name     : string;      // wie im Kopf ('TFoo.DoStuff')
    BeginTok : TRdxToken;
    EndTok   : TRdxToken;
  end;

// Ein Routinen-Wort als Schluesselwort (OneTokenOnLine, HeaderOn).
function IsRoutineWord(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := IsKeywordAfter(T, Before(AMap, T)) and InList(T.Low, ROUTINE_WORDS);
end;

// Das eine Routinen-Wort auf ALine. Zwei Koepfe auf einer Zeile
// ('procedure P1; begin end; procedure P2; ...') heissen mehrdeutig - der
// Fund koennte jeden meinen (Gegen-Review Ausnahme-Hilfen, Major 3).
// '' oder der Grund.
function HeaderOn(AMap: TRdxCodeMap; ALine: Integer;
  out AKeyword: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  S := Default(TRdxLineSearch);
  S.Test    := IsRoutineWord;
  S.What    := 'kein Methodenkopf';
  S.ManyFmt := '%d Routinenkoepfe';
  Result := OneTokenOnLine(AMap, ALine, S, AKeyword);
end;

// Der Name hinter dem Routinen-Wort bis vor '(' ':' ';' oder bis zum
// Zeilenende (die Parameter auf der Folgezeile) - als TEXT, mit allen
// Gliedern ('TFoo.Bar'). '' ohne Name. Bis Charge B2S-a hiess sie
// NameAfter wie uRdxSimpleFixes.NameAfter, die das letzte Glied als TOKEN
// liefert (Review R3-05).
function HeaderNameText(AMap: TRdxCodeMap; const AKeyword: TRdxToken): string;
var
  First, T : TRdxToken;
  L        : string;
  Stop     : Integer;
begin
  Result := '';
  First := After(AMap, AKeyword);
  if (First.Line <> AKeyword.Line) or not First.IsWord then Exit;
  L := AMap.Raw(AKeyword.Line);
  T := First;
  while (T.Low <> '') and (T.Line = AKeyword.Line)
     and not InList(T.Low, ['(', ':', ';']) do
    T := After(AMap, T);
  Stop := Length(L) + 1;
  if T.Line = AKeyword.Line then
    Stop := T.Col
  else if AMap.LineCommentCol(AKeyword.Line) > 0 then
    Stop := AMap.LineCommentCol(AKeyword.Line);
  Result := Trim(Copy(L, First.Col, Stop - First.Col));
end;

// Ab dem Kopf das begin des Rumpfs - ohne lokale Routine dazwischen
// (deren begin waere es nicht sicher) und ohne asm. '' oder der Grund.
// Bewusst nicht der Baustein ReadRoutine (uRdxRoutineFixes, Gegen-Review
// H3, Major 2): SCA020 braucht nur den LEEREN Rumpf direkt hinter dem Kopf
// und lehnt eine lokale Routine und asm mit eigenem Grund ab; ReadRoutine
// liest beides und lehnt anderes ab (lokaler Klassentyp, nichts Neues
// hinter dem end) - der Wechsel aenderte Angebote und Gruende von SCA020.
// Zweite Kopie eines Routinen-Lesers nach Rule of Three vertretbar.
function BodyBegin(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  out ABegin: TRdxToken): string;
var
  T, Prev : TRdxToken;
begin
  ABegin := Default(TRdxToken);
  Prev := AKeyword;
  T := After(AMap, AKeyword);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Prev) and (T.Low = 'begin') then
    begin
      ABegin := T;
      Exit('');
    end;
    if IsKeywordAfter(T, Prev) and InList(T.Low, ROUTINE_WORDS) then
      Exit('lokale Routine zwischen Kopf und Rumpf - welches begin gemeint '
        + 'ist, ist nicht sicher');
    if IsKeywordAfter(T, Prev) and (T.Low = 'asm') then
      Exit('asm-Rumpf');
    Prev := T;
    T := After(AMap, T);
  end;
  Result := 'kein Rumpf zur Methode gefunden';
end;

// Kopf, Name und der leere Rumpf der Methode auf ALine. '' oder der Grund.
function MethodBodyOn(AMap: TRdxCodeMap; ALine: Integer;
  out ABody: TRdxMethodBody): string;
begin
  ABody := Default(TRdxMethodBody);
  Result := HeaderOn(AMap, ALine, ABody.Keyword);
  if Result <> '' then Exit;
  ABody.Name := HeaderNameText(AMap, ABody.Keyword);
  Result := BodyBegin(AMap, ABody.Keyword, ABody.BeginTok);
  if Result <> '' then Exit;
  ABody.EndTok := After(AMap, ABody.BeginTok);
  if ABody.EndTok.Low <> 'end' then
    Result := 'der Rumpf ist nicht leer - Code unter einer Direktive bzw. ein '
      + 'asm-Block (der Detektor sieht nur den aktiven Zweig) oder Fund '
      + 'veraltet'
  // Ein Kommentar im Rumpf ist keine Absicht (sonst schwiege der Detektor):
  // auskommentierter Code (SCA070) - der Absichtskommentar verdeckte ihn,
  // und ein schon eingefuegter Kommentar kaeme doppelt (Gegen-Review,
  // Minor 4/5). Zwischen begin und end (CommentInRange - bis Charge B2S-a
  // als CommentBetween kopiert, derselbe Lauf mit Token statt Bereich).
  else if CommentInRange(AMap, TRefactorSpan.Make(SPAN_020,
    ABody.BeginTok.Line, ABody.BeginTok.EndCol, ABody.EndTok.Line,
    ABody.EndTok.Col)) then
    Result := 'im Rumpf steht schon ein Kommentar ohne Absicht - '
      + 'auskommentierter Code (SCA070)? Von Hand entscheiden';
end;

// Die Ersetzung fuer das begin: AText inline dahinter oder (begin und end
// auf eigenen Zeilen, hinter dem begin nichts) in einer eigenen Zeile eine
// Stufe tiefer. '' oder der Grund.
function BodyEdit(AMap: TRdxCodeMap; const ABody: TRdxMethodBody;
  const AText, AInlineText: string; out AEdit: TRdxEdit): string;
var
  L, Indent : string;
  B         : TRdxToken;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  B := ABody.BeginTok;
  L := AMap.Raw(B.Line);
  AEdit.Span := TRefactorSpan.Make(SPAN_020, B.Line, B.Col, B.Line, B.EndCol);
  AEdit.Expected := Copy(L, B.Col, B.Len);
  if ABody.EndTok.Line = B.Line then
  begin
    AEdit.NewText := AEdit.Expected + ' ' + AInlineText;
    Exit;
  end;
  if SkipBlanks(L, B.EndCol) <= Length(L) then
    Exit('hinter dem begin steht noch etwas - eine eigene Zeile passte nicht');
  if AMap.StartsInside(B.Line + 1) then
    Exit('hinter dem begin beginnt ein Kommentar ueber Zeilen');
  // Eingerueckt wie die Zeile des end - das begin kann auf der Kopfzeile
  // stehen ('procedure P; begin').
  L := AMap.Raw(ABody.EndTok.Line);
  Indent := Copy(L, 1, SkipBlanks(L, 1) - 1);
  AEdit.NewText := AEdit.Expected + #10 + Indent + IndentStep(Indent, '')
    + AText;
end;

class function TRdxRaiseFixes.EmptyBody(AMap: TRdxCodeMap; ALine: Integer;
  const AStatementFmt: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Body : TRdxMethodBody;
  Stmt : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := MethodBodyOn(AMap, ALine, Body);
  if (AReason = '') and (AStatementFmt <> '')
     and InList(Body.Keyword.Low, ['constructor', 'destructor']) then
    AReason := Format('%s - eine Exception dort hinterliesse ein halbes '
      + 'Objekt bzw. keinen Destruktor', [Body.Keyword.Low]);
  if (AReason = '') and (AStatementFmt <> '') and (Body.Name = '') then
    AReason := 'Name der Methode nicht auf der Kopfzeile';
  if AReason <> '' then Exit;
  if AStatementFmt = '' then
    AReason := BodyEdit(AMap, Body, INTENT_LINE, INTENT_INLINE, AEdit)
  else
  begin
    Stmt := Format(AStatementFmt, [StringReplace(Body.Name, '''', '''''',
      [rfReplaceAll])]);
    AReason := BodyEdit(AMap, Body, Stmt, Stmt, AEdit);
  end;
  Result := AReason = '';
end;

{ ---- SCA120 ---- }

// EFoo aus 'Exception EFoo.Create(...) is constructed but never raised'.
function CreateTargetOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(KEY_EXCEPTION, AMessage);
  Q := Pos(KEY_CREATE, AMessage);
  if (P = 1) and (Q > P + Length(KEY_EXCEPTION)) then
    Result := Copy(AMessage, P + Length(KEY_EXCEPTION),
      Q - P - Length(KEY_EXCEPTION));
end;

// Steht an T 'ATarget.Create..' als ganze Anweisung? Dann True; AWhole
// False, wenn es nur Teil eines Ausdrucks ist.
function CreateAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ATarget: string; out AWhole: Boolean): Boolean;
var
  Dot, C, N : TRdxToken;
begin
  AWhole := False;
  Result := False;
  if not SameText(T.Low, ATarget) or InList(APrev.Low, IDENT_PREFIXES) then
    Exit;
  Dot := After(AMap, T);
  C := After(AMap, Dot);
  if (Dot.Low <> '.') or (Copy(C.Low, 1, 6) <> 'create')
     or not InList(Copy(C.Low, 7, MaxInt), CREATE_SUFFIXES) then
    Exit;
  Result := True;
  N := After(AMap, C);
  if N.Low = '(' then
    N := AfterClose(AMap, N);
  // Ein then-Zweig ist nur dann eine Anweisung, wenn sein if eine ist -
  // in 'Foo(if C then EFoo.Create(..) else nil)' waere raise E2029
  // (Gegen-Review Ausnahme-Hilfen, Major 2).
  AWhole := InList(N.Low, STATEMENT_ENDS)
    and TRdxStructFixes.StartsStatementAt(AMap, T);
end;

// 'AArg.Create..' an T (OneTokenOnLine, MissingRaise) - ob als ganze
// Anweisung, prueft der Aufrufer am einen Treffer noch einmal.
function IsCreateOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  Whole : Boolean;
begin
  Result := CreateAt(AMap, T, Before(AMap, T), AArg, Whole);
end;

class function TRdxRaiseFixes.MissingRaise(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Target : string;
  Hit    : TRdxToken;
  Whole  : Boolean;
  S      : TRdxLineSearch;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Target := CreateTargetOf(AMessage);
  if Target = '' then
  begin
    AReason := 'Exception-Klasse fehlt in der Meldung';
    Exit;
  end;
  S := Default(TRdxLineSearch);
  S.Test    := IsCreateOf;
  S.Arg     := Target;
  S.What    := 'kein ' + Target + '.Create';
  S.ManyFmt := '%d-mal ' + Target + '.Create';
  AReason := OneTokenOnLine(AMap, ALine, S, Hit);
  if (AReason = '') and CreateAt(AMap, Hit, Before(AMap, Hit), Target, Whole)
     and not Whole then
    AReason := Format('%s.Create(..) steht nicht als ganze Anweisung - '
      + 'Teil eines Ausdrucks?', [Target]);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_120, ALine, Hit.Col, ALine, Hit.EndCol);
  AEdit.Expected := Copy(AMap.Raw(ALine), Hit.Col, Hit.Len);
  AEdit.NewText := 'raise ' + AEdit.Expected;
  Result := True;
end;

{ ---- SCA122 ---- }

// Ist ADo das 'do' eines Handlers 'on Name: T do' (bzw. 'on T do', dann
// AName = '')? Typ auch mit Punkten ('SysUtils.EFoo').
function HandlerOf(AMap: TRdxCodeMap; const ADo: TRdxToken;
  out AName: string): Boolean;
var
  T, P : TRdxToken;
begin
  AName := '';
  T := Before(AMap, ADo);
  P := Before(AMap, T);
  while (P.Low = '.') and T.IsWord do
  begin
    T := Before(AMap, P);
    P := Before(AMap, T);
  end;
  Result := T.IsWord and (P.Low = 'on');
  if Result then Exit;
  if not T.IsWord or (P.Low <> ':') then Exit;
  T := Before(AMap, P);
  Result := T.IsWord and (Before(AMap, T).Low = 'on');
  if Result then
    AName := Copy(AMap.Raw(T.Line), T.Col, T.Len);
end;

// Ein Schritt rueckwaerts auf oberster Ebene (ReRaiseReason): rsFound am
// eigenen Handler, rsStop mit AReason, sonst rsGoOn.
function HandlerStep(AMap: TRdxCodeMap; const T: TRdxToken;
  const AName: string; out AReason: string): TRdxStep;
var
  Bound : string;
begin
  Result := rsGoOn;
  AReason := '';
  if (T.Low = 'except') or (T.Low = 'finally') then
  begin
    AReason := 'raise steht im except/finally eines inneren try - "raise;" '
      + 'wuerde dort eine andere Exception weiterwerfen';
    Exit(rsStop);
  end;
  if InList(T.Low, ['procedure', 'function']) then
  begin
    AReason := 'anonyme Methode im Handler (das raise darin oder eine davor) '
      + '- nicht sicher pruefbar';
    Exit(rsStop);
  end;
  // 'with H do raise E': E kann ein Member von H sein - 'raise;' wuerfe
  // dann eine andere Exception (Gegen-Review Ausnahme-Hilfen, Blocker 1).
  if T.Low = 'with' then
  begin
    AReason := 'with-Anweisung zwischen Handler und raise - der Name koennte '
      + 'ein Member sein';
    Exit(rsStop);
  end;
  if (T.Low <> 'do') or not HandlerOf(AMap, T, Bound) then Exit;
  if SameText(Bound, AName) then
    Exit(rsFound);
  AReason := Format('raise steht im Handler von "%s", nicht von "%s"',
    [Bound, AName]);
  Result := rsStop;
end;

// Ein Schritt rueckwaerts (ReRaiseReason): ganze Bloecke (end..begin,
// until..repeat) ueberspringen, auf oberster Ebene HandlerStep. Auf jeder
// Tiefe sperrt eine Zuweisung an die gebundene Variable ('E := ..', nicht
// 'Obj.E := ..'): 'raise E' wirft danach das neue Objekt, 'raise;' die
// urspruengliche Exception - nicht nur ein anderer Stack-Trace, eine andere
// Exception (Review R3, verpasst, Charge FC; FPC-Probe: 'aussen: ersetzt'
// mit raise E gegen 'aussen: innen' mit raise;). Ein inneres 'on E: ..',
// das E verdeckt, sperrt dabei mit - lieber keine Hilfe.
function RaiseBackStep(AMap: TRdxCodeMap; const T: TRdxToken;
  const AName: string; var ABlock: Integer; out AReason: string): TRdxStep;
var
  P : TRdxToken;
begin
  Result := rsGoOn;
  AReason := '';
  P := Before(AMap, T);
  if SameText(T.Low, AName) and not InList(P.Low, IDENT_PREFIXES)
     and (After(AMap, T).Low = ':=') then
  begin
    AReason := Format('%s wird zwischen Handler und raise neu zugewiesen - '
      + '"raise %s;" wirft dann ein anderes Objekt als "raise;"', [AName, AName]);
    Exit(rsStop);
  end;
  // Satzzeichen und Bezeichner zaehlen nicht.
  if not IsKeywordAfter(T, P) then Exit;
  if (T.Low = 'end') or (T.Low = 'until') then
    Inc(ABlock)
  else if (IsEndOpener(T.Low) or (T.Low = 'repeat')) and (ABlock > 0) then
    Dec(ABlock)
  else if ABlock = 0 then
    Result := HandlerStep(AMap, T, AName, AReason);
end;

// Rueckwaerts vom raise bis zum Handler 'on AName: T do'. '' oder der
// Grund.
function ReRaiseReason(AMap: TRdxCodeMap; const ARaise: TRdxToken;
  const AName: string): string;
var
  T     : TRdxToken;
  Block : Integer;
begin
  Block := 0;
  T := Before(AMap, ARaise);
  while T.Low <> '' do
  begin
    if RaiseBackStep(AMap, T, AName, Block, Result) <> rsGoOn then Exit;
    T := Before(AMap, T);
  end;
  Result := Format('kein Handler "on %s: ... do" vor dem raise gefunden',
    [AName]);
end;

// 'raise AArg' vor dem Ende der Anweisung an T (OneTokenOnLine, RaiseOn).
function IsRaiseOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  Result := (T.Low = 'raise') and SameText(N.Low, AArg)
    and InList(After(AMap, N).Low, STATEMENT_ENDS);
end;

// Das eine 'raise AName' (vor dem Ende der Anweisung) auf ALine, raise und
// Name auf derselben Zeile ohne Kommentar dazwischen. '' oder der Grund.
function RaiseOn(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  out AHit, AVar: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  AVar := Default(TRdxToken);
  S := Default(TRdxLineSearch);
  S.Test    := IsRaiseOf;
  S.Arg     := AName;
  S.What    := 'kein "raise ' + AName + '"';
  S.ManyFmt := '%d-mal "raise ' + AName + '"';
  Result := OneTokenOnLine(AMap, ALine, S, AHit);
  if Result <> '' then Exit;
  AVar := After(AMap, AHit);
  if (AVar.Line <> AHit.Line)
     or AMap.HasNonCode(AHit.Line, AHit.Col, AVar.EndCol - 1) then
    Result := 'Kommentar oder Zeilenumbruch zwischen raise und Name';
end;

class function TRdxRaiseFixes.ReRaise(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Name          : string;
  Hit, BoundTok : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  // E aus 'Re-raise of bound variable "E" loses ...' (bis Charge B2S-a
  // eine eigene Kopie BoundNameOf).
  Name := QuotedText(AMessage, '"');
  if Name = '' then
    AReason := 'Name der Variablen fehlt in der Meldung'
  else
    AReason := RaiseOn(AMap, ALine, Name, Hit, BoundTok);
  if AReason = '' then
    AReason := ReRaiseReason(AMap, Hit, Name);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_122, Hit.Line, Hit.Col, BoundTok.Line,
    BoundTok.EndCol);
  AEdit.Expected := Copy(AMap.Raw(Hit.Line), Hit.Col, BoundTok.EndCol - Hit.Col);
  AEdit.NewText := Copy(AEdit.Expected, 1, Hit.Len);
  Result := True;
end;

end.
