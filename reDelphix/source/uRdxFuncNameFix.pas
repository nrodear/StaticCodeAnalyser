unit uRdxFuncNameFix;

// reDelphix - Editorhilfe SCA204 FunctionNameAsResult (Charge N / FN,
// 2026-10-25), OHNE ToolsAPI und ohne Parser: 'GetCount := FCount;' wird
// 'Result := FCount;'. Links vom ':=' sind der Funktionsname und Result
// dieselbe Variable - die Hilfe ist BEDEUTUNGSGLEICH.
//
// DER FUND (uFunctionNameResult, Scanner uFuncNameResultScan): ein Fund je
// Zeile, die Meldung nennt den Namen wie geschrieben ('Result assigned
// through the function name: ''GetCount :=''...'). Der Planer liest ihn
// dort und ersetzt JEDE Zuweisung an ihn am Anweisungsanfang auf den
// Code-Spalten der gemeldeten Zeile ('if A then F := 1 else F := 2;' ->
// beide) - eine Spanne vom ersten bis hinter den letzten Namen.
//
// NICHT geaendert: Lesestellen des Namens auf derselben Zeile ('Total :=
// Total + I' wird 'Result := Total + I'). Rechts ist der Name ein
// rekursiver Aufruf (SCA205, eigener Fund ohne Hilfe: ob Result oder
// Total() gemeint war, weiss nur der Autor) - die Hilfe aendert daran
// nichts, sie bleibt bedeutungsgleich.
//
// GESPERRT (lieber keine Hilfe als eine falsche; der Detektor prueft
// dasselbe, der Puffer kann seit dem Scan anders sein):
//   - die Meldung nennt keinen Namen, auf der Zeile steht keine Zuweisung
//     an ihn am Anweisungsanfang (Zeile verschoben, schon korrigiert),
//     Kommentar/Direktive zwischen Name und ':=';
//   - es gibt kein Result: {$mode fpc|tp|macpas|iso|extendedpascal} (auch
//     mit {$modeswitch result} - die Hilfe liest den Schalter nicht),
//     {$X-}, {$EXTENDEDSYNTAX OFF}; oder die Unit wird auch mit Free Pascal
//     uebersetzt ({$IFDEF FPC}, FPC_..) und setzt selbst keinen Modus
//     delphi/delphiunicode/objfpc - dann haengt Result am Modus des
//     Projekts (fpc und tp kennen keins; Korpus: die Krypto-Units von
//     W. Ehrhardt in doublecmd bleiben bewusst TP-tauglich);
//   - die innerste Routine um die Zeile ist keine Funktion dieses Namens
//     (in einer geschachtelten Routine waere Result deren Ergebnis) oder
//     ihre Grenzen sind nicht sicher lesbar;
//   - Kopf oder Deklarationsteil nennen den Namen noch einmal (Parameter,
//     lokale Variable, geschachtelte Routine) oder deklarieren Result;
//   - vor der Zeile steht im Rumpf ein 'with' oder eine anonyme Methode
//     (ein Element gleichen Namens bzw. ein anderes Result) - strenger als
//     der Detektor, der nur die Spanne ausblendet.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanFuncNameResult (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Kopien der festen Teile der Meldung aus uFuncNameResultScan
  // (FNR_ASSIGN_PREFIX/_MID) - wer sie aendert, aendert beide.
  FNR_ASSIGN_PREFIX = 'Result assigned through the function name: ''';
  FNR_ASSIGN_MID    = ' :=''';

  // Die Gruende der Ablehnung als englische msgids (die Tests suchen die
  // ASCII-Kennungen in Anfuehrung, die in en/de/fr gleich bleiben).
  R_FN_MESSAGE = 'the message names no function ("Name :=")';
  R_FN_MOVED = 'no assignment "%s :=" at the start of a statement on the '
    + 'reported line';
  R_FN_NONCODE = 'a comment or directive stands between "%s" and ":="';
  R_FN_NO_RESULT = '%s in line %d - there is no Result there';
  R_FN_FPC_MODE = 'the unit is also compiled with Free Pascal ({$IFDEF FPC} '
    + 'in line %d) and sets no {$mode} - whether Result exists depends on '
    + 'the mode of the project';
  R_FN_NO_ROUTINE = 'no routine with a begin..end body around the line';
  R_FN_BOUNDS = 'the bounds of the routine around the line are not safe to '
    + 'read';
  R_FN_OTHER_ROUTINE = 'the line belongs to %s, not to the function %s - '
    + 'there "Result" would be another result';
  R_FN_SHADOW = 'the head or the declarations of %s name "%s" again '
    + '(parameter, local, nested routine) - it may not be the result';
  R_FN_RESULT_DECL = 'the head or the declarations of %s declare "Result"';
  R_FN_WITH = 'a "with" or an anonymous method in %s before the line - '
    + '"%s" may mean something else there';

type
  TRdxFuncNameFix = class
  public
    // SCA204: 'Name :=' -> 'Result :=' fuer jede Zuweisung an den Namen aus
    // AMessage am Anweisungsanfang auf ALine (Form TRdxMapPlanner).
    class function ResultAssign(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Der Name aus der Meldung ('GetCount'), '' ohne.
    class function NameOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // BeginBodyAround, TRdxRoutine

const
  SPAN_204 = 'sca204';
  NEW_NAME = 'Result';
  // Modi ohne Result (FPC); mit diesen Modi hat die Unit eins.
  NO_RESULT_MODES: array[0..4] of string = ('fpc', 'tp', 'macpas', 'iso',
    'extendedpascal');
  RESULT_MODES: array[0..2] of string = ('delphi', 'delphiunicode',
    'objfpc');
  COND_WORDS: array[0..4] of string = ('ifdef', 'ifndef', 'if', 'elseif',
    'ifopt');
  DIRECTIVE_MODE_FMT = '{$mode %s}';
  DIRECTIVE_X_OFF = '{$X-}';
  DIRECTIVE_EXT_OFF = '{$EXTENDEDSYNTAX OFF}';

class function TRdxFuncNameFix.NameOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(FNR_ASSIGN_PREFIX, AMessage);
  if P <> 1 then Exit;
  Q := Pos(FNR_ASSIGN_MID, AMessage);
  if Q <= Length(FNR_ASSIGN_PREFIX) + 1 then Exit;
  Result := Copy(AMessage, Length(FNR_ASSIGN_PREFIX) + 1,
    Q - Length(FNR_ASSIGN_PREFIX) - 1);
  if (Result = '') or not IsIdentStart(Result[1]) then
    Result := '';
end;

// Die Direktive an (ALine, ACol) ohne Result? '' oder der Grund. AHasMode:
// ein Modus mit Result; AFpcLine: erste Zeile einer Bedingung auf FPC.
function DirectiveReason(AMap: TRdxCodeMap; ALine, ACol: Integer;
  var AHasMode: Boolean; var AFpcLine: Integer): string;
var
  W, Args, Sw : string;
  Arg : Boolean;
begin
  Result := '';
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  Args := LowerCase(Trim(DirectiveArgs(AMap, ALine, ACol)));
  if (W = 'mode') and InList(Args, NO_RESULT_MODES) then
    Exit(_(R_FN_NO_RESULT, [Format(DIRECTIVE_MODE_FMT, [Args]), ALine]));
  if (W = 'extendedsyntax') and (Copy(Args, 1, 3) = 'off') then
    Exit(_(R_FN_NO_RESULT, [DIRECTIVE_EXT_OFF, ALine]));
  Sw := ',' + StringReplace(W + Args, ' ', '', [rfReplaceAll]) + ',';
  if (Length(W) = 1) and (Pos(',x-,', Sw) > 0) then
    Exit(_(R_FN_NO_RESULT, [DIRECTIVE_X_OFF, ALine]));
  if (W = 'mode') and InList(Args, RESULT_MODES) then
    AHasMode := True;
  if (AFpcLine = 0) and InList(W, COND_WORDS) and
     (HasIdentWord(Args, 'fpc') or (Pos('fpc_', Args) > 0)) then
    AFpcLine := ALine;
end;

// Gibt es in der Unit Result? '' oder der Grund. Der Lauf ueber alle
// Direktiven: NextDirective (uRdxCodeMap).
function ResultReason(AMap: TRdxCodeMap): string;
var
  Li, Co, FpcLine : Integer;
  HasMode : Boolean;
begin
  Li := 1;
  Co := 1;
  FpcLine := 0;
  HasMode := False;
  while NextDirective(AMap, Li, Co) do
  begin
    Result := DirectiveReason(AMap, Li, Co, HasMode, FpcLine);
    if Result <> '' then Exit;
    Inc(Co);
  end;
  if (FpcLine > 0) and not HasMode then
    Result := _(R_FN_FPC_MODE, [FpcLine])
  else
    Result := '';
end;

// Die Zuweisungen an ALow am Anweisungsanfang auf den Code-Spalten von
// ALine: das Token des Namens je Treffer.
function AssignsOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ALow: string): TArray<TRdxToken>;
var
  T : TRdxToken;
  N : Integer;
begin
  Result := nil;
  N := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.IsWord and SameIdent(T.Low, ALow) and (After(AMap, T).Low = ':=')
       and StartsStatement(AMap, T) then
    begin
      if N = Length(Result) then
        SetLength(Result, N * 2 + 2);
      Result[N] := T;
      Inc(N);
    end;
    T := After(AMap, T);
  end;
  SetLength(Result, N);
end;

// Die Funktion um AAt: innerste Routine mit begin..end-Rumpf, eine
// Funktion namens AName. '' oder der Grund.
function OwnFunction(AMap: TRdxCodeMap; const AAt: TRdxToken;
  const AName: string; out ARoutine: TRdxRoutine): string;
begin
  case BeginBodyAround(AMap, AAt, ARoutine) of
    rbfUnsure: Exit(_(R_FN_BOUNDS));
    rbfNone:   Exit(_(R_FN_NO_ROUTINE));
  else
    Result := '';
  end;
  if (ARoutine.Keyword.Low <> 'function') or
     not SameIdent(LowerCase(LastPart(ARoutine.Name)), LowerCase(AName)) then
    Result := _(R_FN_OTHER_ROUTINE, [ARoutine.Name, AName]);
end;

// Kopf und Deklarationsteil (hinter dem Namen bis vor das begin): nennen
// sie den Namen noch einmal oder Result? '' oder der Grund.
function DeclReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AName: string): string;
var
  T : TRdxToken;
  Low : string;
begin
  Result := '';
  Low := LowerCase(AName);
  T := After(AMap, R.NameTok);
  while (T.Low <> '') and TokBefore(T, R.Body) do
  begin
    if T.IsWord and SameIdent(T.Low, Low) then
      Exit(_(R_FN_SHADOW, [R.Name, AName]));
    if T.IsWord and (T.Low = 'result') then
      Exit(_(R_FN_RESULT_DECL, [R.Name]));
    T := After(AMap, T);
  end;
end;

// Steht im Rumpf vor AAt ein 'with' oder eine anonyme Methode? '' oder der
// Grund.
function BodyReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AAt: TRdxToken; const AName: string): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := R.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    if ((T.Low = 'with') or InList(T.Low, ROUTINE_WORDS)) and
       IsKeywordAfter(T, P) then
      Exit(_(R_FN_WITH, [R.Name, AName]));
    P := T;
    T := After(AMap, T);
  end;
end;

// Kommentar oder Direktive zwischen einem Namen und seinem ':='? '' oder
// der Grund.
function NonCodeReason(AMap: TRdxCodeMap; ALine: Integer;
  const AHits: TArray<TRdxToken>; const AName: string): string;
var
  T : TRdxToken;
begin
  Result := '';
  for T in AHits do
    if (After(AMap, T).Line <> ALine) or
       AMap.HasNonCode(ALine, T.EndCol, After(AMap, T).Col - 1) then
      Exit(_(R_FN_NONCODE, [AName]));
end;

// Die Spanne vom ersten bis hinter den letzten Namen, jeder Name durch
// Result ersetzt (von rechts, damit die Spalten davor stimmen).
procedure BuildEdit(AMap: TRdxCodeMap; ALine: Integer;
  const AHits: TArray<TRdxToken>; out AEdit: TRdxEdit);
var
  L, S : string;
  First, Stop, i : Integer;
begin
  L := AMap.Raw(ALine);
  First := AHits[0].Col;
  Stop := AHits[High(AHits)].EndCol;
  S := Copy(L, First, Stop - First);
  for i := High(AHits) downto 0 do
  begin
    Delete(S, AHits[i].Col - First + 1, AHits[i].Len);
    Insert(NEW_NAME, S, AHits[i].Col - First + 1);
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_204, ALine, First, ALine, Stop);
  AEdit.Expected := Copy(L, First, Stop - First);
  AEdit.NewText := S;
end;

class function TRdxFuncNameFix.ResultAssign(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Name : string;
  Hits : TArray<TRdxToken>;
  R    : TRdxRoutine;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  R := Default(TRdxRoutine);
  Name := NameOf(AMessage);
  if Name = '' then
  begin
    AReason := _(R_FN_MESSAGE);
    Exit;
  end;
  Hits := AssignsOnLine(AMap, ALine, LowerCase(Name));
  if Length(Hits) = 0 then
  begin
    AReason := MsgMovedSuffix(_(R_FN_MOVED, [Name]));
    Exit;
  end;
  AReason := NonCodeReason(AMap, ALine, Hits, Name);
  if AReason = '' then
    AReason := ResultReason(AMap);
  if AReason = '' then
    AReason := OwnFunction(AMap, Hits[0], Name, R);
  if AReason = '' then
    AReason := DeclReason(AMap, R, Name);
  if AReason = '' then
    AReason := BodyReason(AMap, R, Hits[0], Name);
  if AReason <> '' then Exit;
  BuildEdit(AMap, ALine, Hits, AEdit);
  Result := True;
end;

end.
