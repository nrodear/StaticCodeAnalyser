unit uRdxGotoExitFix;

// reDelphix - Editorhilfe fuer SCA060 GotoStatement, OHNE ToolsAPI und ohne
// Parser: 'goto L' wird zu 'Exit', wenn die Marke L das Ende der Routine
// ist. Das betrifft etwa ein Viertel der Funde; alle anderen 'goto' (Sprung
// nach hinten, in die Mitte, aus einer Schleife in Code, der weiterlaeuft)
// haben keine einfache Umformung und bekommen keine Hilfe.
//
// DER FUND: uGotoStatement meldet auf der Zeile des ERSTEN 'goto' der Zeile,
// die Meldung nennt die Spalte als '(col N)'. Die Marke steht nicht in der
// Meldung; der Planer liest sie hinter dem 'goto'.
//
// BEDEUTUNGSGLEICH, wenn
//   - die Marke L die LETZTE Anweisung der innersten Routine um das 'goto'
//     ist: 'L:' (optional ';' dahinter) steht unmittelbar vor dem 'end' des
//     Rumpfs, davor ein ';' oder das 'begin'. Dann fuehrt 'goto L' ans
//     Routinenende, genau wie 'Exit'. try..finally-Bloecke zwischen Sprung
//     und Ende laufen in beiden Faellen ab; Result einer Funktion bleibt in
//     beiden Faellen wie es ist. Das bleibt also KEINE Sperre.
//   - die Zeile genau ein 'goto' traegt und die Marke dahinter auf derselben
//     Zeile steht.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - mehr als ein 'goto' auf der Zeile, kein 'goto' an der gemeldeten
//     Spalte (Zeile verschoben), Kommentar zwischen 'goto' und Marke, Marke
//     auf der Folgezeile oder keine einfache Form 'goto Marke;',
//   - keine Routine mit begin..end-Rumpf um die Zeile (Hauptblock des
//     Programms, initialization, asm) oder die Grenzen der naechsten
//     Routine sind nicht sicher lesbar,
//   - die Marke ist NICHT die letzte Anweisung (Code dahinter wuerde
//     uebersprungen, 'Exit' taete etwas anderes),
//   - der Rumpf traegt eine Compiler-Direktive (bedingter Code kann die
//     Marke verschieben) oder eine anonyme Methode (dort verlaesst 'Exit'
//     nur die Methode; die Hilfe prueft nicht, wo das 'goto' steht),
//   - die Datei deklariert einen eigenen Bezeichner 'Exit' (dann ist es
//     nicht die RTL-Prozedur).
//
// HINWEIS: die Marke bleibt stehen. Gibt es danach kein 'goto' mehr zu ihr,
// meldet Delphi die ungenutzte Marke (Hinweis/Warnung, kein Fehler), und die
// Marke samt 'label'-Eintrag kann von Hand entfallen. Die Hilfe aendert nur
// das gemeldete 'goto'.
//
// OHNE ToolsAPI. Der Adapter PlanGotoExit hat die Form von TRdxFixPlanner
// (uRdxFixTable); die Unit bindet uRdxFixTable bewusst nicht ein.

interface

uses
  System.Classes,        // TStrings
  uEngineApi,            // TSourcePlaces
  uMethodd12,            // TLeakFinding
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap,           // TRdxCodeMap
  uRdxRecipeRunner;      // TRdxFixOutcome

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_GOTO_MOVED = 'no "goto" at the reported place';
  R_GOTO_MANY = 'the line has more than one "goto"';
  R_GOTO_FORM = 'the "goto" is not of the form "goto Label;" on one line';
  R_GOTO_COMMENT = 'comment inside "goto <label>"';
  R_GOTO_NO_ROUTINE = 'no routine with a begin..end body around the "goto"';
  R_GOTO_BOUNDS = 'the bounds of the routine around the "goto" are not '
    + 'safe to read';
  R_GOTO_DIRECTIVE = 'compiler directive in the routine - conditional code '
    + 'could move the label';
  R_GOTO_ANON = 'the routine contains an anonymous method - "Exit" would '
    + 'leave only that method if the "goto" sits in it';
  R_GOTO_NOT_LAST = 'label "%s" is not the last statement of the routine - '
    + '"Exit" would skip the code after it';
  R_GOTO_SHADOW = 'the file declares its own "Exit" - it is not the '
    + 'procedure of the RTL';

type
  TRdxGotoExitFix = class
  public
    // SCA060: 'goto L' -> 'Exit', wenn L die letzte Anweisung der Routine
    // ist. Spalte aus der Meldung ('(col N)').
    class function GotoToExit(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Die '(col N)' einer Meldung des Detektors; 0 = nicht vorhanden.
function GotoColumn(const AMessage: string): Integer;

// Der Adapter fuer FIX_ROWS (Form TRdxFixPlanner); APlaces und AUsesNames
// braucht die Hilfe nicht.
function PlanGotoExit(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks,       // TRdxBlocks.HeadBefore, TRdxRoutine
  uRdxFixRunner;    // MapFix

const
  SPAN_060 = 'sca060';
  KEY_COL = '(col ';
  // Hier endet die Suche nach der Routine um das 'goto'.
  UNIT_BOUNDS: array[0..6] of string = ('implementation', 'interface',
    'initialization', 'finalization', 'unit', 'program', 'library');
  // Dahinter endet die Anweisung 'goto L'.
  GOTO_FOLLOW: array[0..5] of string = (';', 'end', 'else', 'until',
    'finally', 'except');
  // Davor beginnt eine Anweisung (die Marke steht am Anfang einer).
  LABEL_PREV: array[0..1] of string = (';', 'begin');
  // Davor wird ein Name deklariert (Variable, Parameter, Member).
  EXIT_DECL_PREV: array[0..5] of string = ('var', 'const', 'property',
    'procedure', 'function', ',');

function GotoColumn(const AMessage: string): Integer;
var
  p, i : Integer;
begin
  Result := 0;
  p := Pos(KEY_COL, AMessage);
  if p = 0 then
    Exit;
  i := p + Length(KEY_COL);
  while (i <= Length(AMessage)) and CharInSet(AMessage[i], ['0'..'9']) do
  begin
    Result := Result * 10 + Ord(AMessage[i]) - Ord('0');
    Inc(i);
  end;
end;

// Wie viele 'goto' stehen im Code von ALine?
function GotosOnLine(AMap: TRdxCodeMap; ALine: Integer): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.Low = 'goto' then
      Inc(Result);
    T := After(AMap, T);
  end;
end;

// Ist T eine Marke: ein Bezeichner oder eine Zahl?
function IsLabelToken(const T: TRdxToken): Boolean;
var
  i : Integer;
begin
  Result := T.IsWord;
  if Result or (T.Low = '') then
    Exit;
  Result := True;
  for i := 1 to Length(T.Low) do
    if not CharInSet(T.Low[i], ['0'..'9']) then
      Exit(False);
end;

// Das 'goto' an (ALine, ACol) und seine Marke dahinter; '' oder der Grund.
function ReadGoto(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AGoto, ALabel: TRdxToken): string;
var
  L    : string;
  Next : TRdxToken;
begin
  Result := '';
  AGoto := Default(TRdxToken);
  ALabel := Default(TRdxToken);
  L := AMap.Raw(ALine);
  if (ACol > Length(L)) or not AMap.IsCode(ALine, ACol) then
    Exit(MsgMovedSuffix(_(R_GOTO_MOVED)));
  AGoto := TokenAt(AMap, ALine, ACol);
  if (AGoto.Low <> 'goto') or (AGoto.Col <> ACol)
     or not IsKeywordAfter(AGoto, Before(AMap, AGoto)) then
    Exit(MsgMovedSuffix(_(R_GOTO_MOVED)));
  if GotosOnLine(AMap, ALine) <> 1 then
    Exit(_(R_GOTO_MANY));
  ALabel := After(AMap, AGoto);
  if (ALabel.Line <> ALine) or not IsLabelToken(ALabel) then
    Exit(_(R_GOTO_FORM));
  Next := After(AMap, ALabel);
  if not InList(Next.Low, GOTO_FOLLOW) then
    Exit(_(R_GOTO_FORM));
  if AMap.HasComment(ALine, AGoto.EndCol, ALabel.Col - 1) then
    Exit(_(R_GOTO_COMMENT));
end;

// Die innerste Routine mit begin..end-Rumpf um AAt: von AAt rueckwaerts der
// erste Kopf, dessen Rumpf AAt umfasst. Ein Kopf mit unsicheren Grenzen
// beendet die Suche (er koennte der gesuchte sein). '' oder der Grund.
function EnclosingRoutine(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): string;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) do
  begin
    if S.Stop then
      Break;
    if S.Reason <> '' then
      Exit(_(R_GOTO_BOUNDS));
    if (S.Routine.Body.Low = 'begin')
       and TokBefore(S.Routine.Body, AAt)
       and TokBefore(AAt, S.Routine.EndTok) then
    begin
      ARoutine := S.Routine;
      Exit('');
    end;
  end;
  Result := _(R_GOTO_NO_ROUTINE);
end;

// Was im Rumpf steht, das die Hilfe nicht liest: eine Direktive oder eine
// anonyme Methode. '' oder der Grund.
function BodyReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  if DirectiveBetween(AMap, ARoutine.Body, ARoutine.EndTok.Line,
       ARoutine.EndTok.Col) then
    Exit(_(R_GOTO_DIRECTIVE));
  P := ARoutine.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARoutine.EndTok) do
  begin
    if InList(T.Low, ROUTINE_WORDS) and IsKeywordAfter(T, P) then
      Exit(_(R_GOTO_ANON));
    P := T;
    T := After(AMap, T);
  end;
end;

// Steht die Marke ALabel als letzte Anweisung vor dem end der Routine?
// 'L:' oder 'L: ;' unmittelbar davor, die Marke am Anfang einer Anweisung.
function LabelIsLast(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const ALabel: TRdxToken): Boolean;
var
  P, Lab : TRdxToken;
begin
  P := Before(AMap, ARoutine.EndTok);
  if P.Low = ';' then
    P := Before(AMap, P);
  Result := False;
  if P.Low <> ':' then
    Exit;
  Lab := Before(AMap, P);
  Result := (Lab.Low = ALabel.Low) and IsLabelToken(Lab)
    and InList(Before(AMap, Lab).Low, LABEL_PREV);
end;

// Deklariert die Datei einen eigenen Bezeichner 'Exit' (Variable, Parameter,
// Member, Routine, Marke)? Dann ist 'Exit' dort nicht die RTL-Prozedur.
function ExitIsShadowed(AMap: TRdxCodeMap): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'exit');
  while T.Low <> '' do
  begin
    if (T.Low = 'exit')
       and ((After(AMap, T).Low = ':')
            or InList(Before(AMap, T).Low, EXIT_DECL_PREV)) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, 'exit');
  end;
end;

class function TRdxGotoExitFix.GotoToExit(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Col        : Integer;
  G, Lab     : TRdxToken;
  Routine    : TRdxRoutine;
  L          : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := GotoColumn(AMessage);
  if Col <= 0 then
  begin
    AReason := MsgNoColumn;
    Exit;
  end;
  AReason := ReadGoto(AMap, ALine, Col, G, Lab);
  if AReason = '' then
    AReason := EnclosingRoutine(AMap, G, Routine);
  if AReason = '' then
    AReason := BodyReason(AMap, Routine);
  if AReason <> '' then
    Exit;
  if not LabelIsLast(AMap, Routine, Lab) then
  begin
    AReason := _(R_GOTO_NOT_LAST, [TokText(AMap, Lab)]);
    Exit;
  end;
  if ExitIsShadowed(AMap) then
  begin
    AReason := _(R_GOTO_SHADOW);
    Exit;
  end;
  L := AMap.Raw(ALine);
  AEdit.Span := TRefactorSpan.Make(SPAN_060, ALine, G.Col, ALine, Lab.EndCol);
  AEdit.Expected := Copy(L, G.Col, Lab.EndCol - G.Col);
  AEdit.NewText := 'Exit';
  Result := True;
end;

function PlanGotoExit(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxGotoExitFix.GotoToExit);
end;

end.
