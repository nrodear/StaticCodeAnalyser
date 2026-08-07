unit uManagedResultUninit;

// Detektor SCA196: `Result` eines verwalteten Return-Typs wird GELESEN,
// bevor es zugewiesen wurde.
//
// Semantik (RTL-verifiziert, System.Rtti.pas UseResultPointer): Functions
// mit verwaltetem Return-Typ (string-Familie, dynamische Arrays, Variant,
// Interface) geben ihr Ergebnis ueber einen VERSTECKTEN var-Parameter
// zurueck, der auf die Zielvariable des AUFRUFERS zeigt - inklusive deren
// ALTEM Inhalt. Result ist beim Eintritt also NICHT ''/nil/leer, sondern
// traegt den vorherigen Wert der Aufrufer-Variablen (System.SysUtils.pas
// TStringBuilder.ToString: "Result := ''; // prevent copying of existing
// data"). Der Compiler-Hinweis W1035 (NO_RETVAL) schweigt fuer genau
// diese Typen - deshalb dieser Detektor.
//
// Pattern (Bug):
//   function CollectNames(const L: TStrings): TArray<string>;
//   var i: Integer;
//   begin
//     for i := 0 to L.Count - 1 do
//       Result := Result + [L[i]];    // <-- liest ALTEN Aufrufer-Inhalt
//   end;
//   // Aufrufer: Names := CollectNames(A); Names := CollectNames(B);
//   // -> zweiter Aufruf haengt an die Ergebnisse des ersten an.
//
// Korrekt:
//   Result := [];                     // (oder nil / '' / SetLength(...,0))
//   for i := ... do Result := Result + [...];
//
// Erkennung (Variante 2, rein AST, KEIN CFG - User-Entscheid 2026-08-07):
//   * nkMethod ist Function; Return-Typ passiert IsResultPointerType
//     (bewusst ENGER als SCA121s Managed-Heuristik: Exakt-Liste + TArray</
//     *DynArray + I<Upper>-Interface; KEINE Records/Klassen - Record-
//     Feld-Writes sind legitime Teil-Initialisierung, Klassen deckt W1035).
//   * Body-Statements in Dokument-Reihenfolge walken; Zustand: "Result
//     schon geschrieben?". Erster Result-LESE-Zugriff VOR dem ersten
//     Schreib-Zugriff -> Finding an der Lese-Zeile, dann Methode fertig.
//   * LESEN: `Result := ...Result...` (RHS-Vorkommen), `Result[i] := ...`
//     (Element-Write in alten/nil-Puffer), `Result.X(...)` / `Result^`,
//     `Exit(...Result...)`, Result auf der RHS fremder Zuweisungen.
//   * SCHREIBEN (konservativ): `Result := ...`, `Exit(Wert)`,
//     Result/@Result als Call-Argument (SetLength, TryGetValue, out/var),
//     `P := @Result`.
//   * Skips: nicht-Function, bodyless (abstract/forward/external/dispid),
//     ';assembler', kein eigener nkBlock, `absolute Result`-Alias.
//   * String-Literale werden vor jedem Result-Wortmatch entfernt
//     ('...result...' in einem Literal zaehlt nicht).
//   * Bewusste False NEGATIVES (nie FPs): (1) Result in Call-ARGUMENT-
//     Position gilt IMMER als potentieller Write - auch by-value-Reads wie
//     `Result := Copy(Result, 1, N)` (lexisch nicht von TryGetValue(K,
//     Result) unterscheidbar); (2) reine Bedingungs-Reads (`if Result =
//     nil then`) - Bedingungen liegen nur als TypeRef-Strings vor und
//     werden ausschliesslich auf Pass-Muster geprueft.
//   * FnName-Alias NUR als ZUWEISUNGSZIEL (2. Korpus-Messung 2026-08-07):
//     in einem Delphi-AUSDRUCK ist der nackte Function-Name IMMER ein
//     (rekursiver/parameterloser) Aufruf - `Result := Put;` ruft die
//     parameterlose Ueberladung, liest nie Result. Der Alias existiert
//     nur links vom ':='. Lese-Erkennung laeuft daher ausschliesslich
//     ueber die 'result'-Needle; 'obj.result' (fremdes FELD, auch mit
//     Token-Spaces 'obj . result') zaehlt nicht.
//   * Parse-Artefakte entschaerft: IFDEF-Zwillings-Zuweisungen (zweites
//     `result :=` als Text in der RHS) gelten als Write; RHS-Texte mit
//     EINGEBETTETER anonymer Methode werden nicht als Lesen gewertet
//     (deren Result gehoert der anonymen Function); `Result[0] :=
//     Char(Api(@Result[1], N))` ist API-Puffer-Fuellung (Pass = Write).
//
// Warum praktisch FP-frei: VOR dem ersten textuellen Write gibt es keinen
// legalen Weg, wie Result definierten Inhalt haette - die einzigen
// Seitenkanaele (absolute-Alias, @Result, var/out-Durchreichung, asm)
// werden als Write bzw. Skip behandelt. Branch-Blindheit kostet nur
// False NEGATIVES (Write im then-Zweig VOR dem Lesen dahinter), nie FPs;
// Pfad-Analyse ist Variante 1 (spaeteres Inkrement, CFG).
//
// Kollisionsregel (User-Entscheid): wo SCA196 feuert, bleibt SCA121
// stumm - uRoutineResultAssigned fragt dazu WouldReport() ab (nur der
// Fall "Result wird NUR gelesen, nie geschrieben" ueberlappt).
//
// Schweregrad: lsWarning + fcLow (Start-Konfidenz bis zur Korpus-Messung).

interface

uses
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts;

type
  TManagedResultUninitDetector = class
  private
    class function TryFindReadBeforeWrite(MethodNode: TAstNode;
      out ReadLine: Integer; out ReadWhat, RetType: string): Boolean;
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    // Return-Typ-Gate, oeffentlich fuer die SCA121-Kollisionsregel.
    // ATypeRef = kompletter Method-TypeRef ('function:TArray<string>;...').
    class function IsResultPointerType(const ATypeRef: string): Boolean;
    // True wenn SCA196 fuer diese Methode melden wuerde (alle Gates
    // inklusive). uRoutineResultAssigned nutzt das als Stummschalter.
    class function WouldReport(MethodNode: TAstNode): Boolean;
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity
// Guard-Exit-Stil wie in den uebrigen Detektoren (uRoutineResultAssigned,
// uConstantReturn): einzeilige `if X then Exit;`-Gates sind hier idiomatisch.

uses
  System.StrUtils, System.SysUtils,
  uDetectorUtils;

const
  RESULT_IDENT = 'result';

type
  // Walker-Zustand: einmal pro Methode aufgesetzt, per var durchgereicht.
  TScanState = record
    FnNameLow     : string;  // unqualifizierter Function-Name, lowercased
    IsShortString : Boolean; // ShortString-Return: `Result[0] := Laenge` ist
                             // das INIT-Idiom (Korpus: 37 solcher FPs) ->
                             // Accessor-Writes zaehlen als Initialisierung
    Written       : Boolean; // Result wurde bereits (potentiell) geschrieben
    Found         : Boolean; // erster Lese-vor-Schreib-Zugriff gefunden
    ReadLine      : Integer;
    ReadWhat      : string;
  end;

  // Klassifikation der Result-Vorkommen eines Expression-Strings.
  TRhsUse = record
    Pass  : Boolean;         // Argument-Position/@Result -> potentieller Write
    Reads : Boolean;         // echtes Lesen
  end;

// Extrahiert den Return-Typ aus 'function:RetType[;direktive...]'
// (gleiche TypeRef-Konvention wie uRoutineResultAssigned).
function ExtractReturnType(const TypeRef: string): string;
var
  c, s : Integer;
begin
  Result := '';
  c := Pos(':', TypeRef);
  if c = 0 then Exit;
  Result := Copy(TypeRef, c + 1, MaxInt);
  s := Pos(';', Result);
  if s > 0 then Result := Copy(Result, 1, s - 1);
  Result := Trim(Result);
end;

function IsFunctionMethod(const TypeRef: string): Boolean;
var
  ColonPos, SemiPos : Integer;
begin
  ColonPos := Pos(':', TypeRef);
  if ColonPos = 0 then Exit(False);
  SemiPos := Pos(';', TypeRef);
  Result := (SemiPos = 0) or (ColonPos < SemiPos);
end;

function IsBodyless(const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';abstract',  Low) > 0) or
            (Pos(';forward',   Low) > 0) or
            (Pos(';external',  Low) > 0) or
            (Pos(';dispid',    Low) > 0);
end;

function HasOwnBodyBlock(N: TAstNode): Boolean;
var
  Child : TAstNode;
begin
  for Child in N.Children do
    if Child.Kind = nkBlock then Exit(True);
  Result := False;
end;

// 'absolute Result'-Alias: Schreibzugriffe laufen ueber den Alias-Namen,
// der Walker saehe nie einen Result-Write -> Methode skippen (Kopie der
// SCA121-Logik, dort seit Real-World 2026-06-28 zero-FN belegt).
function HasAbsoluteResultAlias(MethodNode: TAstNode): Boolean;
var
  LocalVars : TList<TAstNode>;
  LV  : TAstNode;
  Low : string;
  p, j : Integer;
begin
  Result := False;
  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    for LV in LocalVars do
    begin
      Low := LowerCase(LV.TypeRef);
      p := Pos('absolute', Low);
      if p = 0 then Continue;
      j := p + 8;
      while (j <= Length(Low)) and (Low[j] <= ' ') do Inc(j);
      if (Copy(Low, j, 6) = RESULT_IDENT)
         and ((j + 6 > Length(Low))
              or not CharInSet(Low[j + 6], ['a'..'z', '0'..'9', '_'])) then
        Exit(True);
    end;
  finally
    LocalVars.Free;
  end;
end;

// Entfernt '...'-String-Literale (ersetzt sie durch ein Leerzeichen, damit
// Wort-Grenzen erhalten bleiben). '' innerhalb eines Literals = escaped
// Quote. Verhindert, dass 'result' IN einem Literal als Zugriff zaehlt.
function StripStringLiterals(const S: string): string;
var
  i, n : Integer;
  SB   : TStringBuilder;
begin
  n := Length(S);
  if Pos('''', S) = 0 then Exit(S);
  SB := TStringBuilder.Create(n);
  try
    i := 1;
    while i <= n do
    begin
      if S[i] <> '''' then
      begin
        SB.Append(S[i]);
        Inc(i);
        Continue;
      end;
      // Literal ueberspringen.
      Inc(i);
      while i <= n do
      begin
        if S[i] = '''' then
        begin
          if (i < n) and (S[i + 1] = '''') then
          begin
            Inc(i, 2);                             // escaped '' -> weiter
          end
          else
          begin
            Inc(i);                                // Literal-Ende
            Break;
          end;
        end
        else
        begin
          Inc(i);
        end;
      end;
      SB.Append(' ');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Word-boundary-Lookup von Needle in Haystack (beide lowercased).
function ContainsIdentifier(const Haystack, Needle: string): Boolean;
var
  pIx           : Integer;
  Before, After : Char;
begin
  Result := False;
  if Needle = '' then Exit;
  pIx := Pos(Needle, Haystack);
  while pIx > 0 do
  begin
    if pIx = 1 then Before := ' ' else Before := Haystack[pIx - 1];
    if pIx + Length(Needle) > Length(Haystack) then After := ' '
    else After := Haystack[pIx + Length(Needle)];
    if (not TDetectorUtils.IsIdentChar(Before)) and
       (not TDetectorUtils.IsIdentChar(After)) then
      Exit(True);
    pIx := PosEx(Needle, Haystack, pIx + 1);
  end;
end;

// True wenn der (literal-bereinigte, lowercased) Ausdruck Result als
// eigenstaendigen Identifier enthaelt. BEWUSST ohne Function-Name: der
// nackte FnName ist im Ausdruckskontext ein Aufruf (s. ClassifyNeedle).
function ReadsResultIdent(const StrippedLow: string): Boolean;
begin
  Result := ContainsIdentifier(StrippedLow, RESULT_IDENT);
end;

// True wenn der Ausdruck '@Result' enthaelt (Adresse genommen -> der
// Callee schreibt durch den Zeiger; konservativ als Write werten).
function TakesResultAddress(const StrippedLow: string): Boolean;
var
  pIx, After : Integer;
begin
  Result := False;
  pIx := Pos('@result', StrippedLow);
  while pIx > 0 do
  begin
    After := pIx + 7;
    if (After > Length(StrippedLow)) or
       (not TDetectorUtils.IsIdentChar(StrippedLow[After])) then
      Exit(True);
    pIx := PosEx('@result', StrippedLow, pIx + 1);
  end;
end;

// Index des letzten Nicht-Whitespace-Zeichens <= i (0 wenn keins).
function PrevNonSpace(const S: string; i: Integer): Integer;
begin
  Result := i;
  while (Result >= 1) and (S[Result] <= ' ') do Dec(Result);
end;

// Klassifiziert EIN word-bounded Result-Vorkommen an Position pIx:
//   Pass = Argument-Position (nach ',' oder nach '(' dessen Aufrufziel
//          ein Ident/')'/']'/'>' ist) oder '@Result' davor,
//   Read = alles andere (echtes Lesen).
procedure ClassifyOccurrence(const S: string; pIx: Integer;
  var AUse: TRhsUse);
var
  j, k : Integer;
begin
  if (pIx > 1) and (S[pIx - 1] = '@') then
  begin
    AUse.Pass := True;
    Exit;
  end;
  j := PrevNonSpace(S, pIx - 1);
  if j < 1 then
  begin
    AUse.Reads := True;
    Exit;
  end;
  case S[j] of
    ',': AUse.Pass := True;
    '(': begin
           // '(' aus einem CALL (Ident/')'/']'/'>' davor) = Argument;
           // '(' aus reiner Gruppierung '(Result = nil)' = Lesen.
           k := PrevNonSpace(S, j - 1);
           if (k >= 1) and (TDetectorUtils.IsIdentChar(S[k]) or
                            CharInSet(S[k], [')', ']', '>'])) then
             AUse.Pass := True
           else
             AUse.Reads := True;
         end;
  else
    AUse.Reads := True;
  end;
end;

// True wenn vor dem Vorkommen (ueber Whitespace hinweg) ein '.' steht:
// 'obj.result' / 'FWebSession . SessionId' ist ein qualifizierter Zugriff
// auf ein FREMDES Symbol, nie der Result-Alias. Der Parser rekonstruiert
// Ausdruecke aus Tokens MIT Spaces um die Punkte - deshalb PrevNonSpace
// statt Direktzeichen (2. Korpus-Messung 2026-08-07, Exit-FP-Klasse).
function IsQualifiedAccess(const S: string; pIx: Integer): Boolean;
var
  j : Integer;
begin
  j := PrevNonSpace(S, pIx - 1);
  Result := (j >= 1) and (S[j] = '.');
end;

// Wort-Grenzen-Pruefung: kein Identifier-Zeichen direkt vor/nach dem
// Vorkommen der Laenge ALen an Position pIx.
function IsWordBoundedAt(const S: string; pIx, ALen: Integer): Boolean;
var
  Before, After : Char;
begin
  if pIx = 1 then Before := ' ' else Before := S[pIx - 1];
  if pIx + ALen > Length(S) then After := ' ' else After := S[pIx + ALen];
  Result := (not TDetectorUtils.IsIdentChar(Before)) and
            (not TDetectorUtils.IsIdentChar(After));
end;

// True wenn ab Position i (Whitespace uebersprungen) ein ':=' folgt.
function FollowedByAssign(const S: string; i: Integer): Boolean;
begin
  while (i <= Length(S)) and (S[i] <= ' ') do Inc(i);
  Result := (i < Length(S)) and (S[i] = ':') and (S[i + 1] = '=');
end;

// Alle word-bounded 'result'-Vorkommen klassifizieren.
//
// BEWUSST NUR die 'result'-Needle: der nackte FUNCTION-NAME ist in einem
// Delphi-AUSDRUCK immer ein (rekursiver/parameterloser) AUFRUF, nie der
// Result-Alias - der Alias existiert nur als ZUWEISUNGSZIEL links vom ':='
// (2. Korpus-Messung 2026-08-07: `Result := Put;` /
// `Result := GetCreateCode;` = Overload-Delegation, dazu Parameter, die
// den Funktionsnamen verschatten - alles FPs der FnName-Needle).
procedure ClassifyNeedle(const StrippedLow: string; var AUse: TRhsUse);
var
  pIx : Integer;
begin
  pIx := Pos(RESULT_IDENT, StrippedLow);
  while pIx > 0 do
  begin
    if IsWordBoundedAt(StrippedLow, pIx, Length(RESULT_IDENT)) and
       (not IsQualifiedAccess(StrippedLow, pIx)) then
      ClassifyOccurrence(StrippedLow, pIx, AUse);
    pIx := PosEx(RESULT_IDENT, StrippedLow, pIx + 1);
  end;
end;

// Klassifiziert die Result-Vorkommen eines (literal-bereinigten,
// lowercased) Expression-Strings:
//   APass = potentieller var/out-Write durch einen Callee. Konservativ
//           als Initialisierung gewertet (gleiche Richtung wie SCA121s
//           CallPassesResultAsArg; kostet FNs wie `Result :=
//           Copy(Result, ...)`, nie FPs).
//   ARead = Vorkommen ausserhalb solcher Positionen (echtes Lesen).
// Der Parser legt Bedingungs-Calls NUR als TypeRef-Strings ab (kein
// nkCall, vgl. uRoutineResultAssigned.ExprWritesOrPassesResult) - ohne
// diese String-Ebene waere `if not Map.TryGetValue(Key, Result) then`
// unsichtbar und die Folgezeile ein FP.
procedure ClassifyResultUses(const StrippedLow: string;
  out AUse: TRhsUse);
begin
  AUse.Pass  := False;
  AUse.Reads := False;
  ClassifyNeedle(StrippedLow, AUse);
end;

// IFDEF-Zwilling-Artefakt: behaelt der Parser beide Praeprozessor-Zweige
// einer semikolonlosen Zuweisung (`{$IFDEF} Result := A {$ELSE}
// Result := B {$ENDIF} else ...`), landet die ZWEITE Zuweisung als Text
// in der RHS der ersten ('... result := ...'). Das ist ein Parse-
// Artefakt, kein Lesen - die Zuweisungskette gilt als Write.
// (2. Korpus-Messung: JvBDEReg/mormot HttpGet.)
function ContainsAssignChainArtifact(const StrippedLow: string): Boolean;
var
  pIx : Integer;
begin
  Result := False;
  pIx := Pos(RESULT_IDENT, StrippedLow);
  while pIx > 0 do
  begin
    if IsWordBoundedAt(StrippedLow, pIx, Length(RESULT_IDENT)) and
       FollowedByAssign(StrippedLow, pIx + Length(RESULT_IDENT)) then
      Exit(True);
    pIx := PosEx(RESULT_IDENT, StrippedLow, pIx + 1);
  end;
end;

// True wenn der Expression-String eine EINGEBETTETE anonyme Methode
// enthaelt (`function(...): Integer begin Result := ... end`) - deren
// 'Result' gehoert der anonymen Function, nicht der umgebenden;
// Lese-Wertung dieses Textes waere ein FP (2. Korpus-Messung:
// TDelegatedComparer-Idiom in Swagger.Commons).
function ContainsAnonymousMethod(const StrippedLow: string): Boolean;
begin
  Result := ContainsIdentifier(StrippedLow, 'function') or
            ContainsIdentifier(StrippedLow, 'procedure');
end;

// Klassifiziert einen (NormalizeLhs-artigen) LHS-String:
//   'result' / '<fnname>'            -> bare Write-Ziel
//   'result.' / 'result[' / 'result^' -> Zugriff auf ALTEN Inhalt (Lesen)
function LhsHead(const LhsNormLow, Head: string): Integer;
// 0 = kein Result-LHS, 1 = bare, 2 = Accessor.
begin
  Result := 0;
  if Head = '' then Exit;
  if LhsNormLow = Head then Exit(1);
  if (Length(LhsNormLow) > Length(Head)) and
     (Copy(LhsNormLow, 1, Length(Head)) = Head) and
     CharInSet(LhsNormLow[Length(Head) + 1], ['.', '[', '^']) then
    Result := 2;
end;

// Lowercase + Whitespace raus (Semantik wie NormalizeLhs in
// uRoutineResultAssigned, hier ohne Konkat-Schleife: erst kompaktieren,
// dann einmal LowerCase).
function NormalizeLhs(const S: string): string;
var
  i, o : Integer;
begin
  SetLength(Result, Length(S));
  o := 0;
  for i := 1 to Length(S) do
    if S[i] > ' ' then
    begin
      Inc(o);
      Result[o] := S[i];
    end;
  SetLength(Result, o);
  Result := LowerCase(Result);
end;

// --- Dokument-Reihenfolge-Walker -------------------------------------------
// Zustand in TScanState (var): Written = Result wurde bereits geschrieben,
// Found = erster Lese-vor-Schreib-Zugriff gefunden (Walk stoppt dann).

procedure MarkRead(N: TAstNode; const AWhat: string; var St: TScanState);
begin
  St.Found    := True;
  St.ReadLine := N.Line;
  St.ReadWhat := AWhat;
end;

// Fall `Result := ...`: Pass dominiert Read - bei `Result := F(Key,
// Result)` kann F per var/out fuellen, kein Fund (FN-Richtung, nie FP).
procedure MarkBareAssign(N: TAstNode; const Rhs: TRhsUse;
  var St: TScanState);
begin
  if (not St.Written) and (not Rhs.Pass) and Rhs.Reads then
    MarkRead(N, 'Result appears on the right-hand side of its own first assignment', St);
  St.Written := True;
end;

// Fall `Result[i] / Result.X / Result^ := ...`: RPass = die RHS reicht
// Result/@Result an einen Callee durch - `Result[0] := Char(Api(
// @Result[1], N))` ist das API-Puffer-Fuell-Idiom, kein Lesen
// (2. Korpus-Messung: JvFileUtil).
procedure MarkAccessorAssign(N: TAstNode; const Rhs: TRhsUse;
  var St: TScanState);
begin
  if (not St.Written) and (not St.IsShortString) and (not Rhs.Pass) then
    MarkRead(N, 'element/member write into the not-yet-assigned Result', St);
  St.Written := True;                              // danach gilt es als beschrieben
end;

procedure HandleAssign(N: TAstNode; var St: TScanState);
var
  LhsNorm, RhsLow : string;
  HeadKind        : Integer;
  Rhs             : TRhsUse;
begin
  LhsNorm := NormalizeLhs(N.Name);
  RhsLow  := StripStringLiterals(LowerCase(N.TypeRef));

  // IFDEF-Zwilling: zweite Zuweisung als Text in der RHS = Parse-Artefakt,
  // die Kette ist ein Write.
  if ContainsAssignChainArtifact(RhsLow) then
  begin
    St.Written := True;
    Exit;
  end;

  ClassifyResultUses(RhsLow, Rhs);
  // Eingebettete anonyme Methode: deren 'Result' gehoert ihr selbst -
  // Lese-Wertung unterdruecken (Pass-Richtung bleibt: @Result als
  // weiteres Argument ist weiterhin ein Write).
  if Rhs.Reads and ContainsAnonymousMethod(RhsLow) then
    Rhs.Reads := False;

  HeadKind := LhsHead(LhsNorm, RESULT_IDENT);
  if (HeadKind = 0) and (St.FnNameLow <> '') then
    HeadKind := LhsHead(LhsNorm, St.FnNameLow);

  case HeadKind of
    1: MarkBareAssign(N, Rhs, St);
    2: MarkAccessorAssign(N, Rhs, St);
  else                                             // fremde LHS
    if Rhs.Pass then
      St.Written := True                           // P := @Result / Arg-Position
    else if (not St.Written) and Rhs.Reads then
      MarkRead(N, 'Result is read on a right-hand side', St);
  end;
end;

procedure HandleCall(N: TAstNode; var St: TScanState);
var
  CLow           : string;
  LParen, RParen : Integer;
  ArgsLow        : string;
begin
  CLow := StripStringLiterals(NormalizeLhs(N.Name));

  // Methoden-/Index-Zugriff AUF Result: Result.Add(x), Result[0].Foo, ...
  // Kein FnName-Pendant: `FnName.X` waere Member-Zugriff auf ein CALL-
  // Ergebnis (s. ClassifyNeedle-Kommentar).
  if LhsHead(Copy(CLow, 1, 7), RESULT_IDENT) = 2 then
  begin
    if (not St.Written) and (not St.IsShortString) then
      MarkRead(N, 'method/index access on the not-yet-assigned Result', St);
    Exit;
  end;

  // Result als Call-ARGUMENT (SetLength(Result, n), TryGetValue(k, Result),
  // Foo(@Result), ...) -> konservativ als Write werten (deckt out/var ab;
  // gleiche Richtung wie SCA121s CallPassesResultAsArg).
  LParen := Pos('(', CLow);
  if LParen = 0 then Exit;
  RParen := Length(CLow);
  while (RParen > LParen) and (CLow[RParen] <> ')') do Dec(RParen);
  if RParen <= LParen + 1 then Exit;
  ArgsLow := Copy(CLow, LParen + 1, RParen - LParen - 1);
  if ReadsResultIdent(ArgsLow) or TakesResultAddress(ArgsLow) then
    St.Written := True;
end;

procedure HandleExit(N: TAstNode; var St: TScanState);
var
  ArgLow : string;
  Arg    : TRhsUse;
begin
  if N.TypeRef = '' then Exit;                     // nacktes Exit
  ArgLow := StripStringLiterals(LowerCase(N.TypeRef));
  ClassifyResultUses(ArgLow, Arg);
  if Arg.Reads and ContainsAnonymousMethod(ArgLow) then
    Arg.Reads := False;
  if (not St.Written) and (not Arg.Pass) and Arg.Reads then
    MarkRead(N, 'Result is read inside the Exit(...) argument', St);
  St.Written := True;                              // Exit(Wert) schreibt Result
end;

// Nicht-Statement-Knoten (if/while/repeat/case/inline-var, ...): der Parser
// legt deren Expressions als TypeRef-STRING ab, nicht als nkCall-Kinder.
// Hier wird NUR die Pass-Richtung ausgewertet (Result als Call-Argument
// -> Initialisierung); reine LESE-Zugriffe in Bedingungen (`if Result =
// nil`) melden wir in Variante 2 bewusst NICHT (nur FN, nie FP - die
// Grauzone gehoert in die CFG-Variante 1).
procedure HandleExprText(N: TAstNode; var St: TScanState);
var
  SLow : string;
  Use  : TRhsUse;
begin
  if N.TypeRef = '' then Exit;
  SLow := StripStringLiterals(LowerCase(N.TypeRef));
  if Pos(RESULT_IDENT, SLow) = 0 then Exit;
  ClassifyResultUses(SLow, Use);
  if Use.Pass then
    St.Written := True;
end;

procedure WalkNode(N: TAstNode; var St: TScanState);
var
  Child : TAstNode;
begin
  case N.Kind of
    nkAssign: HandleAssign(N, St);
    nkCall:   HandleCall(N, St);
    nkExit:   HandleExit(N, St);
    nkMethod: Exit;                                // fremde (nested) Methode: nicht absteigen
  else
    HandleExprText(N, St);                         // Bedingungen etc. (nur Pass-Richtung)
  end;
  // Monotonie-Kurzschluss: nach dem ersten Write kann kein Fund mehr
  // entstehen (jedes spaetere Lesen ist legal), nach dem ersten Fund ist
  // die Methode entschieden - beides beendet den Walk.
  if St.Found or St.Written then Exit;
  for Child in N.Children do
  begin
    WalkNode(Child, St);
    if St.Found or St.Written then Exit;
  end;
end;

// ---------------------------------------------------------------------------

class function TManagedResultUninitDetector.IsResultPointerType(
  const ATypeRef: string): Boolean;
const
  // Exakt-Matches (LowerCase). Bewusst KEINE Prefixe (SCA121-Heuristik
  // matcht 'tbytes' auch auf TBytesStream-artige Namen; wir nicht).
  EXACT : array[0..14] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring', 'widestring',
    'shortstring', 'utf8string', 'rawutf8', 'rawjson', 'synunicode',
    'tbtstring', 'tbtwidestring', 'variant', 'olevariant', 'tbytes');
var
  RetType, Low, P : string;
begin
  Result := False;
  RetType := ExtractReturnType(ATypeRef);
  if RetType = '' then Exit;
  Low := LowerCase(RetType);
  if Low.StartsWith('system.') then
    Low := Copy(Low, 8, MaxInt);
  for P in EXACT do
    if Low = P then Exit(True);
  if Low.StartsWith('tarray<') or Low.StartsWith('string[') then Exit(True);
  // TIntegerDynArray & Co. - aber NICHT mormots TDynArray: das ist ein
  // RECORD-Wrapper, dessen `Result.Init(...)` legitime Initialisierung
  // ist (Korpus-Messung 2026-08-07: 5 FPs).
  if Low.EndsWith('dynarray') and (Low <> 'tdynarray') then Exit(True);
  // Interface-Heuristik wie SCA121: 'I' + Grossbuchstabe. KOMPLETT
  // grossgeschriebene Namen ausnehmen: ICONMETRICS/IMAGEINFO & Co. sind
  // Windows-API-RECORDS, keine Interfaces (Korpus-Messung 2026-08-07).
  if (Length(RetType) >= 2) and (RetType[1] = 'I') and
     CharInSet(RetType[2], ['A'..'Z']) and
     (RetType <> UpperCase(RetType)) then
    Exit(True);
end;

class function TManagedResultUninitDetector.TryFindReadBeforeWrite(
  MethodNode: TAstNode; out ReadLine: Integer;
  out ReadWhat, RetType: string): Boolean;
var
  TypeRef : string;
  St      : TScanState;
  Child   : TAstNode;
begin
  Result   := False;
  ReadLine := 0;
  ReadWhat := '';
  RetType  := '';

  // Gates in Billig-nach-teuer-Reihenfolge (String-Checks vor Node-Walks).
  TypeRef := MethodNode.TypeRef;
  if (not IsFunctionMethod(TypeRef)) or IsBodyless(TypeRef) or
     (Pos(';assembler', LowerCase(TypeRef)) > 0) or
     (not IsResultPointerType(TypeRef)) then Exit;
  if (not HasOwnBodyBlock(MethodNode)) or
     HasAbsoluteResultAlias(MethodNode) then Exit;

  RetType          := ExtractReturnType(TypeRef);
  St.FnNameLow     := LowerCase(TDetectorUtils.UnqualifiedNameLast(MethodNode.Name));
  St.IsShortString := SameText(RetType, 'shortstring') or
                      StartsText('string[', RetType);
  St.Written       := False;
  St.Found         := False;
  St.ReadLine      := 0;
  St.ReadWhat      := '';
  // Nur den Body-Block walken (Params/Locals-Deklarationen auslassen -
  // ein Default-Wert o.ae. enthaelt kein ausfuehrbares Result).
  for Child in MethodNode.Children do
  begin
    if Child.Kind <> nkBlock then Continue;
    WalkNode(Child, St);
    if St.Found or St.Written then Break;
  end;
  if not St.Found then Exit;
  ReadLine := St.ReadLine;
  ReadWhat := St.ReadWhat;
  Result   := True;
end;

class function TManagedResultUninitDetector.WouldReport(
  MethodNode: TAstNode): Boolean;
var
  DummyLine : Integer;
  DummyWhat, DummyType : string;
begin
  Result := TryFindReadBeforeWrite(MethodNode, DummyLine, DummyWhat, DummyType);
end;

class procedure TManagedResultUninitDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods  : TList<TAstNode>;
  M        : TAstNode;
  ReadLine : Integer;
  ReadWhat : string;
  RetType  : string;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not TryFindReadBeforeWrite(M, ReadLine, ReadWhat, RetType) then
        Continue;
      if ReadLine = 0 then ReadLine := M.Line;
      Results.Add(TLeakFinding.New(FileName, M.Name, ReadLine,
        Format('Function %s reads Result before assigning it (%s) - for ' +
               'return type %s, Result is a hidden var parameter aliasing ' +
               'the caller''s target variable and starts with its OLD ' +
               'content, not empty. Initialize Result first (e.g. ' +
               'Result := nil / Result := [] / Result := '''')',
          [TDetectorUtils.UnqualifiedNameLast(M.Name), ReadWhat, RetType]),
        fkManagedResultUninit));
    end;
  finally
    Methods.Free;
  end;
end;

end.
