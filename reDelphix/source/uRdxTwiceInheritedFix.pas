unit uRdxTwiceInheritedFix;

// reDelphix - Editorhilfe fuer SCA093 TwiceInheritedCalls, OHNE ToolsAPI und
// ohne Parser: zwei gleiche 'inherited'-Aufrufe in einem Rumpf - einer
// entfaellt. ZWEI Eintraege (Konzept Editorhilfen, Regelliste): der
// Hauptweg loescht den zweiten Aufruf, der zweite Eintrag (Alt, Variant = 1)
// den ersten. Beide aendern das Verhalten (die Elternmethode laeuft nur noch
// einmal) und tragen die Kennzeichnung (E2).
//
// DER FUND: uTwiceInheritedCalls meldet auf der Zeile des METHODENKOPFS
// (nkMethod.Line), nicht auf einem Aufruf, und die Meldung nennt nur die
// Zahl. Der Planer sucht die Aufrufe darum selbst, wie der Detektor: im
// Rumpf-Block der Routine auf oberster Ebene (Anweisungen, die dort auf ';'
// oder das begin folgen), qualifizierend sind 'inherited;' und 'inherited
// <SelbeMethode>(...);'. Aufrufe in if, case, try oder verschachtelten
// begin..end zaehlt er nicht (der Detektor zaehlt dort je Block; die Hilfe
// beschraenkt sich auf den Rumpf).
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Keine
// Hilfe, wenn
//   - die Zeile keinen Routinenkopf traegt (verschoben) oder vor dem begin
//     eine verschachtelte Routine, asm oder external steht,
//   - auf oberster Ebene nicht GENAU zwei qualifizierende Aufrufe stehen,
//   - einer nicht lesbar ist (Argumente ueber mehrere Zeilen, ohne ';' vor
//     dem end, 'inherited Name := ..'),
//   - zwischen den Aufrufen etwas steht - eine Anweisung (ob sie vom ersten
//     Aufruf abhaengt, entscheidet nur der Mensch; auch das Beispiel des
//     Katalogs 'inherited; DoStuff; inherited;' bekommt deshalb keine Hilfe),
//     ein Kommentar oder eine Direktive,
//   - die Aufrufe nicht textgleich sind (Argumente, Schreibweise der Strings),
//   - ein Aufruf die Zeile mit anderem Code oder einem Kommentar teilt (es
//     wird die ganze Zeile geloescht).
// Kommentare und Strings sind nie Code (Code-Sicht, uRdxCodeMap).

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Gruende (deutsch wie die der Nachbarn; Tests pinnen sie ueber diese
  // Konstanten).
  R_TWICE_HEAD_MOVED = 'kein Routinenkopf auf der gemeldeten Zeile - Zeile '
    + 'verschoben? Datei neu pruefen';
  R_TWICE_BODY = 'kein einfacher Rumpf zum Routinenkopf (verschachtelte '
    + 'Routine, asm, external oder Typ vor dem begin) - von Hand';
  R_TWICE_COUNT = 'auf oberster Ebene des Rumpfs stehen %d gleichartige '
    + 'inherited-Aufrufe statt zwei - Aufrufe in if, case oder try und mehr '
    + 'als zwei loescht die Hilfe nicht';
  R_TWICE_UNREADABLE = 'ein inherited-Aufruf ist nicht von der Form '
    + '"inherited;" oder "inherited Name(...);" auf einer Zeile - von Hand';
  R_TWICE_NOT_ADJACENT = 'zwischen den beiden Aufrufen steht anderer Code - '
    + 'ob er vom ersten Aufruf abhaengt, entscheidet nur der Mensch';
  R_TWICE_BETWEEN = 'zwischen den beiden Aufrufen steht ein Kommentar oder '
    + 'eine Direktive';
  R_TWICE_DIFFERENT = 'die beiden Aufrufe sind nicht textgleich';
  R_TWICE_SHARED = 'ein Aufruf teilt die Zeile mit anderem Code oder einem '
    + 'Kommentar - die Hilfe loescht ganze Zeilen';
  // Die Hinweise beider Eintraege (R_TWICE_HINT, R_TWICE_ALT_HINT) stehen
  // mit den Adaptern in der Tabelle (uRdxFixTable).

type
  // Die Planer auf der Code-Sicht (Form TRdxMapPlanner, uRdxFixRunner): die
  // Meldung braucht keiner (sie nennt nur die Zahl), ALine ist der Kopf.
  TRdxTwiceInheritedFix = class
  public
    // Hauptweg: der zweite der beiden Aufrufe, ganze Zeile.
    class function DeleteSecond(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Zweiter Eintrag: der erste der beiden Aufrufe, ganze Zeile.
    class function DeleteFirst(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;     // TRefactorSpan.Make

const
  SPAN_093 = 'sca093';
  // Davor ist kein Rumpf-begin mehr zu erwarten (BodyBegin): ein Wort, das
  // eine Deklaration oder eine zweite Routine einleitet.
  STOP_BEFORE_BODY: array[0..7] of string = ('end', 'asm', 'record', 'type',
    'implementation', 'interface', 'forward', 'external');
  // Vor einem Aufruf, der eine Anweisung beginnt.
  STMT_START_PREV: array[0..1] of string = (';', 'begin');

type
  // Ein qualifizierender Aufruf auf oberster Ebene: von 'inherited' bis zum
  // ';', beide auf einer Zeile; Text wie im Quelltext.
  TInhCall = record
    Start : TRdxToken;
    Stop  : TRdxToken;
    Text  : string;
  end;

  // Was an einem 'inherited' steht (CallForm).
  TCallForm = (cfOther, cfPlain, cfUnreadable);

{ ---- Kopf und Rumpf ---- }

// Der Routinenkopf auf ALine (optional 'class' davor; constructor,
// destructor, procedure, function - kein operator) und der letzte Namensteil
// klein. '' oder der Grund. Ein generischer Kopf ('TFoo<T>.Bar') liefert den
// Namen des Typs; die benannten Aufrufe zaehlen dann nicht, es bleibt bei
// keiner Hilfe (Richtung: weniger Angebot).
function HeadReason(AMap: TRdxCodeMap; ALine: Integer; out AHead: TRdxToken;
  out AName: string): string;
var
  T, N : TRdxToken;
begin
  Result := '';
  AHead := Default(TRdxToken);
  AName := '';
  T := NextToken(AMap, ALine, 1);
  if (T.Line = ALine) and (T.Low = 'class') then
    T := After(AMap, T);
  if (T.Line <> ALine) or not InList(T.Low, ROUTINE_WORDS)
     or (T.Low = 'operator') or not IsKeywordAfter(T, Before(AMap, T)) then
    Exit(R_TWICE_HEAD_MOVED);
  N := NameAfter(AMap, T);
  if not N.IsWord then
    Exit(R_TWICE_HEAD_MOVED);
  AHead := T;
  AName := N.Low;
end;

// Das begin des Rumpfs hinter dem Kopf. Stoesst die Suche vorher auf eine
// verschachtelte Routine oder eine Deklaration, die sie nicht liest, ist es
// nicht sicher das eigene: Grund. '' oder der Grund.
function BodyBegin(AMap: TRdxCodeMap; const AHead: TRdxToken;
  out ABegin: TRdxToken): string;
var
  T, Prev : TRdxToken;
begin
  Result := R_TWICE_BODY;
  ABegin := Default(TRdxToken);
  Prev := AHead;
  T := After(AMap, AHead);
  while T.Low <> '' do
  begin
    if IsKeywordAfter(T, Prev) then
    begin
      if T.Low = 'begin' then
      begin
        ABegin := T;
        Exit('');
      end;
      if InList(T.Low, STOP_BEFORE_BODY) or InList(T.Low, ROUTINE_WORDS)
         or (T.Low = 'class') then
        Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
end;

{ ---- Die Aufrufe ---- }

// Die Form des 'inherited' an T: ';' dahinter (bare) oder der Name der
// Routine, danach ';' oder Argumente in Klammern auf derselben Zeile und
// ';' (cfPlain, AStop das ';'); ein anderer Name ist ein anderer Aufruf, der
// nicht zaehlt (cfOther - wie im Detektor, der nur die SELBE Parent-Methode
// zaehlt); alles andere, was zaehlt, aber nicht lesbar ist, ist cfUnreadable.
function CallForm(AMap: TRdxCodeMap; const T: TRdxToken; const AName: string;
  out AStop: TRdxToken): TCallForm;
var
  N1, N2, Close : TRdxToken;
begin
  AStop := Default(TRdxToken);
  N1 := After(AMap, T);
  if N1.Low = ';' then
  begin
    AStop := N1;
    Exit(cfPlain);
  end;
  // 'inherited' als letzte Anweisung ohne ';'.
  if N1.Low = 'end' then
    Exit(cfUnreadable);
  if not (N1.IsWord and SameIdent(N1.Low, AName)) then
    Exit(cfOther);
  N2 := After(AMap, N1);
  if N2.Low = '(' then
  begin
    Close := MatchClose(AMap, N2, 0);
    if Close.Low <> '' then
      N2 := After(AMap, Close);
  end;
  if N2.Low = ';' then
  begin
    AStop := N2;
    Exit(cfPlain);
  end;
  Result := cfUnreadable;
end;

// Die qualifizierenden Aufrufe auf oberster Ebene des Rumpfs (hinter ABegin)
// bis zum end, das ihn schliesst. '' oder der Grund (ein nicht lesbarer
// Aufruf, kein end).
function CollectCalls(AMap: TRdxCodeMap; const ABegin: TRdxToken;
  const AName: string; out ACalls: TArray<TInhCall>): string;
var
  T, Prev, Stop : TRdxToken;
  Depth         : Integer;
  Form          : TCallForm;
  C             : TInhCall;
begin
  Result := '';
  ACalls := nil;
  Depth := 1;
  Prev := ABegin;
  T := After(AMap, ABegin);
  while (T.Low <> '') and (Depth > 0) do
  begin
    if IsKeywordAfter(T, Prev) then
    begin
      // repeat..until schliesst wie ein end: seine Anweisungen stehen nicht
      // auf oberster Ebene (der Detektor zaehlt dort nicht).
      if IsEndOpener(T.Low) or (T.Low = 'repeat') then
        Inc(Depth)
      else if (T.Low = 'end') or (T.Low = 'until') then
        Dec(Depth)
      else if (Depth = 1) and (T.Low = 'inherited')
              and InList(Prev.Low, STMT_START_PREV) then
      begin
        Form := CallForm(AMap, T, AName, Stop);
        if Form = cfUnreadable then
          Exit(R_TWICE_UNREADABLE);
        if Form = cfPlain then
        begin
          C.Start := T;
          C.Stop := Stop;
          C.Text := '';
          if Stop.Line = T.Line then
            C.Text := Copy(AMap.Raw(T.Line), T.Col, Stop.EndCol - T.Col);
          SetLength(ACalls, Length(ACalls) + 1);
          ACalls[High(ACalls)] := C;
        end;
      end;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if Depth > 0 then
    Result := R_TWICE_BODY;
end;

// Steht der Aufruf allein auf seiner Zeile - davor nur Leerraum, dahinter
// nur Leerraum, kein Kommentar, keine Direktive? '' oder der Grund.
function AloneReason(AMap: TRdxCodeMap; const C: TInhCall): string;
var
  L : string;
begin
  Result := '';
  L := AMap.Raw(C.Start.Line);
  if (C.Stop.Line <> C.Start.Line) or AMap.StartsInside(C.Start.Line)
     or (SkipBlanks(L, 1) <> C.Start.Col)
     or (SkipBlanks(L, C.Stop.EndCol) <= Length(L))
     or AMap.HasComment(C.Start.Line, 1, Length(L)) then
    Result := R_TWICE_SHARED;
end;

// Sind die beiden Aufrufe textgleich? Gross/klein egal, solange kein String
// im Aufruf steht (ein Literal 'A' ist nicht 'a').
function SameCall(const A, B: TInhCall): Boolean;
begin
  Result := (A.Text = B.Text)
    or ((Pos('''', A.Text) = 0) and SameText(A.Text, B.Text));
end;

// Die beiden Aufrufe als Paar prueft: genau zwei, lesbar, unmittelbar
// hintereinander (nichts zwischen ihnen ausser Leerzeilen), textgleich, je
// allein auf der Zeile. '' oder der Grund.
function PairReason(AMap: TRdxCodeMap; const ACalls: TArray<TInhCall>): string;
var
  i : Integer;
begin
  Result := '';
  if Length(ACalls) <> 2 then
    Exit(Format(R_TWICE_COUNT, [Length(ACalls)]));
  if (ACalls[0].Text = '') or (ACalls[1].Text = '') then
    Exit(R_TWICE_UNREADABLE);
  if not SameTok(Before(AMap, ACalls[1].Start), ACalls[0].Stop) then
    Exit(R_TWICE_NOT_ADJACENT);
  if not SameCall(ACalls[0], ACalls[1]) then
    Exit(R_TWICE_DIFFERENT);
  Result := AloneReason(AMap, ACalls[0]);
  if Result = '' then
    Result := AloneReason(AMap, ACalls[1]);
  if Result <> '' then
    Exit;
  for i := ACalls[0].Stop.Line + 1 to ACalls[1].Start.Line - 1 do
    if Trim(AMap.Raw(i)) <> '' then
      Exit(R_TWICE_BETWEEN);
end;

{ ---- Die Planer ---- }

// Der Planer beider Wege: AFirst loescht den ersten, sonst den zweiten
// Aufruf - die ganze Zeile samt Zeilenende (Expected wie bei SCA087).
function PlanDelete(AMap: TRdxCodeMap; ALine: Integer; AFirst: Boolean;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Head, Body   : TRdxToken;
  Name         : string;
  Calls        : TArray<TInhCall>;
  Target, Line : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := HeadReason(AMap, ALine, Head, Name);
  if AReason = '' then
    AReason := BodyBegin(AMap, Head, Body);
  if AReason = '' then
    AReason := CollectCalls(AMap, Body, Name, Calls);
  if AReason = '' then
    AReason := PairReason(AMap, Calls);
  if AReason <> '' then
    Exit;
  Target := 1;
  if AFirst then
    Target := 0;
  Line := Calls[Target].Start.Line;
  // Heute unerreichbar: CollectCalls sammelt nur Aufrufe VOR dem end des
  // Rumpfs, und der Aufruf steht allein auf seiner Zeile - das end folgt
  // also auf einer spaeteren. Die Wache bleibt, weil der Bereich die
  // Zeile Line + 1 braucht.
  if Line >= AMap.LineCount then
  begin
    AReason := R_TWICE_BODY;
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_093, Line, 1, Line + 1, 1);
  AEdit.Expected := AMap.Raw(Line) + #10;
  AEdit.NewText := '';
  Result := True;
end;

class function TRdxTwiceInheritedFix.DeleteSecond(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanDelete(AMap, ALine, False, AEdit, AReason);
end;

class function TRdxTwiceInheritedFix.DeleteFirst(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := PlanDelete(AMap, ALine, True, AEdit, AReason);
end;

end.
