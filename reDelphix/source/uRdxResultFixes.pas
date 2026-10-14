unit uRdxResultFixes;

// reDelphix - Quick-Fixes "Ergebnis und Konstruktoren", OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5
// Bausteine "Routinengrenzen" und "Result := Default(T)-Einfueger",
// Abschnitt 6 Charge H5):
//   SCA096 ConstructorWithoutInherited: als erste Anweisung des Rumpfs
//          (a) 'inherited Create;', wenn die Klasse in dieser Unit belegt
//              DIREKT von TObject erbt ('class', 'class(TObject)', als
//              erster Eintrag ein Interface der Unit) - TObject.Create ist
//              leer, gleiche Bedeutung. Nie nacktes 'inherited;': es
//              reichte die eigenen Parameter weiter, und TObject hat keinen
//              Konstruktor mit Parametern;
//          (b) 'inherited;', wenn die Deklaration 'override' traegt -
//              Delphi uebersetzt es gegen den ueberschriebenen Konstruktor
//              mit denselben Parametern; gekennzeichnet (E2): der
//              Elternkonstruktor laeuft danach.
//          Ein Eintrag je Fund; die Variante waehlt der Planer (wie SCA149
//          override/reintroduce in uRdxDeclFixes). Erbt die Klasse von
//          etwas anderem und fehlt 'override', ist die Wahl des
//          Elternkonstruktors Entwurf - keine Hilfe.
//   SCA097 DestructorWithoutInherited: 'inherited;' als letzte Anweisung
//          vor dem end des Rumpfs (fehlt der letzten Anweisung das ';',
//          kommt es mit). Nur mit 'override' an der Deklaration (sonst
//          verdeckt Destroy die virtuelle Methode - eigentlich SCA149).
//          Gekennzeichnet, ausser die Klasse erbt direkt von TObject
//          (TObject.Destroy ist leer).
//   SCA121 RoutineResultUnassigned: 'Result := Default(T);' als erste
//          Anweisung, T aus dem Kopf (Implementierungskopf ohne Signatur:
//          aus der Deklaration im Klassenrumpf). Gekennzeichnet: Result ist
//          danach definiert statt zufaellig; spaetere Zuweisungen gelten
//          weiter, die Einfuegung am Anfang ueberschreibt nichts.
//   SCA196 ManagedResultUninit: als erste Anweisung 'Result := '''';'
//          (string-Familie, ShortString), 'Result := nil;' (TArray<>,
//          TBytes, *DynArray, Interface) bzw. 'VarClear(Result);' (Variant,
//          OleVariant - fehlt Variants in uses, ergaenzt sie der Aufrufer,
//          uRdxFixTable). Die Meldung zeigt auf die LESE-Zeile; Kopf und
//          begin sucht der Planer (innerste Routine um die Zeile, Name und
//          Rueckgabetyp wie in der Meldung). Gekennzeichnet: Result haengt
//          danach nicht mehr am alten Inhalt der Zielvariable des Aufrufers.
//
// BAUSTEINE (geteilt mit spaeteren Hilfen):
//   FirstStatement  AStmt als erste Anweisung des begin-Rumpfs: eine eigene
//                   Zeile hinter der begin-Zeile, eingerueckt wie die erste
//                   Anweisung (beginnt sie eine eigene Zeile), sonst begin +
//                   eine Stufe (IndentStep). Steht hinter begin auf seiner
//                   Zeile Code oder eine Direktive - auch der Einzeiler
//                   'begin end;' -, kommt AStmt inline direkt hinter das
//                   begin ('begin inherited Create; end;'): bedeutungsgleich
//                   und ohne die Zeilen des Autors umzubrechen (wie SCA020
//                   mit '{ intentionally empty }').
//   LastStatement   AStmt als letzte Anweisung: eine eigene Zeile vor dem
//                   end, wenn es seine Zeile beginnt, sonst inline hinter
//                   der letzten Anweisung; fehlt ihr das ';', kommt es mit.
//                   Leerer Rumpf: wie FirstStatement.
// Die Routinengrenzen liest uRdxRoutineFixes.ReadRoutine (Kopf, lokale
// Abschnitte und Routinen, begin bzw. asm, passendes end), den Klassenkopf
// FindClassHeads/HeritageOf, die Deklaration FindMethodDecls/MethodDecl.
// Lokale Routinen zwischen Kopf und begin sperren deshalb NICHT mehr (das
// Konzept nannte sie, als nur MethodBodyOn fuer leere Rumpfe bestand):
// ReadRoutine ueberspringt sie, eingefuegt wird hinter dem begin der
// aeusseren Routine - vor jedem Aufruf einer lokalen.
//
// SPERREN (alle vier): kein begin-Rumpf (forward/external, asm-Rumpf), asm
// irgendwo im Rumpf (Register und Stapel sieht die Hilfe nicht), eine
// Compiler-Direktive zwischen Kopf und begin (Kopf oder Rumpf unter einem
// Zweig), zwei Koepfe auf der gemeldeten Zeile. SCA096/SCA097: 'class
// constructor/destructor', Kopf ohne Klasse, 'inherited' irgendwo im Text
// der Routine (inaktiver Zweig, Kommentar, lokale Routine - der Detektor
// sieht nur den aktiven AST), Klasse nicht (eindeutig) in der Unit,
// object-Typ, Record, class helper. SCA097 dazu: letzte Anweisung Exit/
// raise/Halt/Abort/goto (inherited liefe nie) und eine Direktive zwischen
// letzter Anweisung und end. SCA121/SCA196: FPC-Modus ohne Result (fpc, tp,
// macpas, iso), '{$X-}'; SCA121 dazu eine Datei ohne implementation-Teil
// (xEdit-/JvInterpreter-Skripte kennen Default() nicht) und ein
// Rueckgabetyp, der kein einfacher Typbezeichner ist (FPC 'specialize');
// SCA196 dazu 'absolute Result' und ein Typ, der weder String noch
// dynamisches Array, Interface oder Variant BEWIESEN ist.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap, uRdxRoutineFixes;

const
  // SCA096/SCA097: die Anweisungen (ohne ';'), zugleich Name im Menuetext.
  STMT_INHERITED_CREATE = 'inherited Create';
  STMT_INHERITED        = 'inherited';

type
  // Ergebnis der Planer: alle Ersetzungen (EIN Undo-Schritt), der Name fuer
  // den Menuetext und was der Aufrufer (uRdxFixTable) noch braucht.
  //   Name          SCA096: die Anweisung (STMT_*), SCA121: der Rueckgabe-
  //                 typ, SCA196: die Anweisung ohne ';' - schon gesetzt,
  //                 soweit bekannt, auch wenn der Planer ablehnt.
  //   Changes       Kennzeichnung (E2) nach dem Fund: SCA096 bei override,
  //                 SCA097 ausser bei direktem TObject-Erben.
  //   NeedsVariants SCA196 mit VarClear: Variants muss in uses stehen.
  TRdxResultPlan = record
    Edits         : TArray<TRdxEdit>;
    Name          : string;
    Changes       : Boolean;
    NeedsVariants : Boolean;
  end;

  // Die Form der Planer (uRdxFixTable: ResultFix).
  TRdxResultPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxResultPlan;
    out AReason: string): Boolean;

  // Die Planer der Charge H5 und ihre Bausteine (s. Kopf): auf dem
  // Puffertext ueber die Code-Sicht, ohne ToolsAPI und Parser (laeuft auch
  // im FPC-Pruefstand).
  TRdxResultFixes = class
  public
    // Baustein: AStmt (mit ';', ohne Zeilenende) als erste Anweisung des
    // begin-Rumpfs von R (s. Kopf). '' oder der Grund.
    class function FirstStatement(AMap: TRdxCodeMap; const R: TRdxRoutine;
      const AStmt: string; out AEdit: TRdxEdit): string; static;

    // Baustein: AStmt (mit ';') als letzte Anweisung vor dem end des
    // begin-Rumpfs von R - eine oder zwei Ersetzungen (das ';' der letzten
    // Anweisung). Gesperrt bei einer Direktive zwischen letzter Anweisung
    // und end. '' oder der Grund.
    class function LastStatement(AMap: TRdxCodeMap; const R: TRdxRoutine;
      const AStmt: string; out AEdits: TArray<TRdxEdit>): string; static;

    // SCA096: der Konstruktor mit Kopf auf ALine (Meldung 'Constructor has
    // no `inherited` call ...') - 'inherited Create;' bzw. 'inherited;'.
    class function ConstructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA097: der Destruktor mit Kopf auf ALine (Meldung 'Destructor has
    // no `inherited` call ...') - 'inherited;' am Ende.
    class function DestructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA121: die Funktion mit Kopf auf ALine (Meldung 'Function X never
    // assigns Result ...') - 'Result := Default(T);'.
    class function ResultDefault(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA196: die Funktion um die Lese-Zeile ALine (Meldung 'Function X
    // reads Result before assigning it (...) - for return type T, ...') -
    // 'Result := '''';', 'Result := nil;' bzw. 'VarClear(Result);'.
    class function ManagedResultInit(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxRtlTypes;      // IsRtlClassOrInterface (SCA196: Interface aus der RTL)

const
  SPAN_RESULT = 'result';
  KW_BEGIN    = 'begin';
  KW_END      = 'end';
  KW_CLASS    = 'class';
  KW_RESULT   = 'result';
  KW_OVERRIDE = 'override';
  KW_OVERLOAD = 'overload';
  KW_CONSTRUCTOR = 'constructor';
  KW_DESTRUCTOR  = 'destructor';
  KW_SELF     = 'self';
  WORD_INHERITED = 'inherited';
  // SCA096 (b): so beginnt der Name eines Konstruktors, an den der Rumpf
  // delegiert (DelegationReason).
  CREATE_PREFIX = 'create';
  // SCA096 (b): ein Aufruf, der abbricht (BlockedReason).
  RAISE_PREFIX = 'raise';
  KEY_CTOR    = 'Constructor has no `inherited` call';
  KEY_DTOR    = 'Destructor has no `inherited` call';
  KEY_FUNC    = 'Function ';
  KEY_NEVER   = ' never assigns Result';
  KEY_READS   = ' reads Result before';
  KEY_TYPE    = 'for return type ';
  KEY_TYPE_END = ', Result is';
  // Damit endet der Ablauf: ein inherited dahinter liefe nie (SCA097).
  DEAD_END_WORDS: array[0..4] of string = ('exit', 'raise', 'halt', 'abort',
    'goto');
  // FPC-Modi ohne Result (SCA121/SCA196).
  NO_RESULT_MODES: array[0..4] of string = ('fpc', 'tp', 'macpas', 'iso',
    'extendedpascal');
  // Damit beginnt eine Datei, die der Compiler uebersetzt (SCA121).
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');
  // SCA196: die Rueckgabetypen je Initialisierung - wie
  // uManagedResultUninit.IsResultPointerType (klein, ohne 'system.').
  STRING_TYPES: array[0..11] of string = ('string', 'unicodestring',
    'ansistring', 'rawbytestring', 'widestring', 'shortstring', 'utf8string',
    'rawutf8', 'rawjson', 'synunicode', 'tbtstring', 'tbtwidestring');
  VARIANT_TYPES: array[0..1] of string = ('variant', 'olevariant');
  // Die dynamischen Arrays der RTL (System.Types; FPC Types kennt dieselben
  // Namen) - ein '*DynArray' sonst nur mit 'Name = array of' in der Unit.
  RTL_DYN_ARRAYS: array[0..14] of string = ('tbooleandynarray',
    'tbytedynarray', 'tcardinaldynarray', 'tclassicbytedynarray',
    'tclassicstringdynarray', 'tdoubledynarray', 'tint64dynarray',
    'tintegerdynarray', 'tshortintdynarray', 'tsingledynarray',
    'tsmallintdynarray', 'tstringdynarray', 'tuint64dynarray',
    'twidestringdynarray', 'tworddynarray');
  INTERFACE_KINDS: array[0..1] of string = ('interface', 'dispinterface');
  OBJECT_KINDS: array[0..0] of string = ('object');
  RECORD_KINDS: array[0..0] of string = ('record');
  ARRAY_KINDS: array[0..1] of string = ('array', 'tarray');
  STMT_EMPTY_STRING = 'Result := ''''';
  STMT_NIL          = 'Result := nil';
  STMT_VARCLEAR     = 'VarClear(Result)';
  R_MOVED  = 'Zeile verschoben? Datei neu pruefen';
  R_BY_HAND = 'von Hand';
  // SCA196: als Konstante - ein Literal mit dem Wort im Exit-Argument
  // haelt der Detektor SCA196 selbst fuer ein Lesen von Result (Selbstscan
  // der Charge H5).
  R_NO_READ = 'kein Result auf der gemeldeten Zeile - ' + R_MOVED;

type
  // Die Klasse einer Methode (OwnerOf).
  TRdxOwner = record
    ClassTok      : TRdxToken;   // 'class' des Klassenkopfs
    Parent        : string;      // erster Vorfahr wie im Text; 'TObject' ohne Liste
    DirectTObject : Boolean;     // erbt direkt von TObject
  end;

  // SCA096/SCA097: der Konstruktor bzw. Destruktor und seine Klasse
  // (MethodCtxReason).
  TRdxMethodCtx = record
    R : TRdxRoutine;
    O : TRdxOwner;
  end;

  // SCA196: die Funktion um die Lese-Zeile und ihr Rueckgabetyp wie im
  // Quelltext (FuncCtxReason).
  TRdxFuncCtx = record
    R      : TRdxRoutine;
    TypeTx : string;
  end;

{ ---- Kleinkram ---- }

procedure AddEdit(var AList: TArray<TRdxEdit>; const AEdit: TRdxEdit);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AEdit;
end;

procedure AddToken(var AList: TArray<TRdxToken>; const T: TRdxToken);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := T;
end;

function TokText(AMap: TRdxCodeMap; const T: TRdxToken): string;
begin
  Result := Copy(AMap.Raw(T.Line), T.Col, T.Len);
end;

// Ersetzt das Token T durch ANewText.
function TokenEdit(AMap: TRdxCodeMap; const T: TRdxToken;
  const ANewText: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(SPAN_RESULT, T.Line, T.Col, T.Line,
    T.EndCol);
  Result.Expected := TokText(AMap, T);
  Result.NewText := ANewText;
end;

// Leerraum am Zeilenanfang.
function LeadingBlanks(const S: string): string;
begin
  Result := Copy(S, 1, SkipBlanks(S, 1) - 1);
end;

// 'TOuter.TInner.Create' -> 'TOuter.TInner' bzw. 'Create'.
function OwnerPathOf(const AName: string): string;
begin
  Result := Copy(AName, 1, LastDelimiter('.', AName) - 1);
end;

function ShortNameOf(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

// Der Text zwischen AKey und AStop in AMessage (Leerraum am Rand weg); ''
// ohne beide.
function TextBetween(const AMessage, AKey, AStop: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AKey, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(AKey));
  Q := Pos(AStop, AMessage, P);
  if Q > P then
    Result := Trim(Copy(AMessage, P, Q - P));
end;

// Steht T als erstes auf seiner Zeile - davor nur Leerraum, und die Zeile
// beginnt nicht in einem Kommentar oder mehrzeiligen String?
function FirstOnLine(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := (SkipBlanks(AMap.Raw(T.Line), 1) = T.Col)
    and not AMap.StartsInside(T.Line);
end;

// Beginnt zwischen dem Ende von A und dem Anfang von B eine Direktive?
function DirectiveBetween(AMap: TRdxCodeMap; const A, B: TRdxToken): Boolean;
var
  Li, Co, Stop : Integer;
begin
  Result := False;
  Co := A.EndCol;
  for Li := A.Line to B.Line do
  begin
    Stop := Length(AMap.Raw(Li));
    if Li = B.Line then
      Stop := B.Col - 1;
    while Co <= Stop do
    begin
      if OpensDirective(AMap, Li, Co) then
        Exit(True);
      Inc(Co);
    end;
    Co := 1;
  end;
end;

// Hinter dem Namen ANameTok: '[<..>] = [packed] <Art>' - das Token der Art;
// Low = '' ohne '='.
function KindAfterName(AMap: TRdxCodeMap; const ANameTok: TRdxToken): TRdxToken;
begin
  Result := After(AMap, ANameTok);
  if Result.Low = '<' then
    Result := AfterClose(AMap, Result);
  if Result.Low <> '=' then
    Exit(Default(TRdxToken));
  Result := After(AMap, Result);
  if Result.Low = 'packed' then
    Result := After(AMap, Result);
end;

// Gibt es 'ALowName [<..>] = [packed] <Art>' mit einer Art aus AKinds in
// der Datei? Das Token der Art (Low = '' ohne) - der erste Treffer.
function TypeDeclKind(AMap: TRdxCodeMap; const ALowName: string;
  const AKinds: array of string): TRdxToken;
var
  T, P : TRdxToken;
begin
  Result := Default(TRdxToken);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, ALowName) and IsKeywordAfter(T, P)
       and InList(KindAfterName(AMap, T).Low, AKinds) then
      Exit(KindAfterName(AMap, T));
    P := T;
    T := After(AMap, T);
  end;
end;

function DeclaredAs(AMap: TRdxCodeMap; const ALowName: string;
  const AKinds: array of string): Boolean;
begin
  Result := TypeDeclKind(AMap, ALowName, AKinds).Low <> '';
end;

{ ---- Kopf und Rumpf ---- }

// Praedikat fuer OneTokenOnLine: ein Routinenkopf, dessen Kopfwort in AArg
// steht ('constructor', 'function|operator').
function IsHeadOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := IsRoutineHead(AMap, T)
    and (Pos('|' + T.Low + '|', '|' + AArg + '|') > 0);
end;

// Die eine Routine, deren Kopf (Kopfwort aus AWords) auf ALine steht,
// gelesen bis zu ihrem Ende (ReadRoutine). '' oder der Grund.
function RoutineOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const AWords, AWhat: string; out R: TRdxRoutine): string;
var
  S : TRdxLineSearch;
  K : TRdxToken;
begin
  R := Default(TRdxRoutine);
  S := Default(TRdxLineSearch);
  S.Test := IsHeadOf;
  S.Arg := AWords;
  S.What := 'kein Kopf ' + AWhat;
  S.ManyFmt := '%d Koepfe ' + AWhat;
  Result := OneTokenOnLine(AMap, ALine, S, K);
  if Result = '' then
    Result := TRdxRoutineFixes.ReadRoutine(AMap, K, R);
end;

// Die Koepfe auf ALine (Kopfwort-Token, links nach rechts).
function HeadsOnLine(AMap: TRdxCodeMap; ALine: Integer): TArray<TRdxToken>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsRoutineHead(AMap, T) then
      AddToken(Result, T);
    T := After(AMap, T);
  end;
end;

// SCA196: die innerste Routine, deren begin..end die Zeile ALine umfasst -
// Koepfe von ALine aufwaerts, je Zeile von rechts (eine lokale Routine
// steht hinter dem Kopf ihrer aeusseren). Ein Kopf, dessen Grenzen nicht
// sicher zu lesen sind, beendet die Suche mit seinem Grund.
function EnclosingRoutine(AMap: TRdxCodeMap; ALine: Integer;
  out R: TRdxRoutine): string;
var
  Li, i : Integer;
  Heads : TArray<TRdxToken>;
begin
  for Li := ALine downto 1 do
  begin
    Heads := HeadsOnLine(AMap, Li);
    for i := High(Heads) downto 0 do
    begin
      Result := TRdxRoutineFixes.ReadRoutine(AMap, Heads[i], R);
      if Result <> '' then
        Exit(Format('Routine in Zeile %d: %s', [Li, Result]));
      if (R.Body.Low <> '') and (R.Body.Line <= ALine)
         and (ALine <= R.EndTok.Line) then
        Exit('');
    end;
  end;
  R := Default(TRdxRoutine);
  Result := 'keine Routine um die gemeldete Zeile - ' + R_MOVED;
end;

// Ein begin-Rumpf ohne asm, ohne Direktive zwischen Kopf und begin? '' oder
// der Grund.
function BodyReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  if R.Body.Low = '' then
    Exit('kein Rumpf (forward/external)');
  if R.Body.Low <> KW_BEGIN then
    Exit('asm-Rumpf - Register und Stapel sieht die Hilfe nicht; ' + R_BY_HAND);
  if DirectiveBefore(AMap, R.Head.Line, R.Body) then
    Exit('Compiler-Direktive zwischen Kopf und begin - Kopf oder Rumpf '
      + 'haengen an einem Zweig; ' + R_BY_HAND);
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if (T.Low = 'asm') and IsKeywordAfter(T, P) then
      Exit(Format('asm im Rumpf (Zeile %d) - Register und Stapel sieht die '
        + 'Hilfe nicht; %s', [T.Line, R_BY_HAND]));
    P := T;
    T := After(AMap, T);
  end;
  Result := '';
end;

// Die Einrueckung der Anweisungen im Rumpf von R: wie die erste Anweisung,
// wenn sie eine eigene Zeile beginnt; sonst begin + eine Stufe.
function BodyIndent(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  F : TRdxToken;
  B : string;
begin
  F := After(AMap, R.Body);
  if (F.Line > R.Body.Line) and not SameTok(F, R.EndTok)
     and FirstOnLine(AMap, F) then
    Exit(LeadingBlanks(AMap.Raw(F.Line)));
  B := LeadingBlanks(AMap.Raw(R.Body.Line));
  Result := B + IndentStep(B, '');
end;

// Steht hinter B auf seiner Zeile nur Leerraum oder ein Kommentar, der dort
// endet (kein Code, keine Direktive)? Dann bekommt die Einfuegung eine
// eigene Zeile.
function QuietAfter(AMap: TRdxCodeMap; const B: TRdxToken): Boolean;
var
  L : string;
  c : Integer;
begin
  L := AMap.Raw(B.Line);
  for c := B.EndCol to Length(L) do
    if not IsBlank(L[c])
       and (AMap.IsCode(B.Line, c) or OpensDirective(AMap, B.Line, c)) then
      Exit(False);
  Result := (B.Line >= AMap.LineCount) or not AMap.StartsInside(B.Line + 1);
end;

{ ---- Klasse und Deklaration (SCA096/SCA097, SCA121) ---- }

// SCA096/SCA097: ein Methodenkopf 'TKlasse.Name' ohne 'class' davor? ''
// oder der Grund.
function MethodHeadReason(const R: TRdxRoutine): string;
begin
  Result := '';
  if R.Head.Low = KW_CLASS then
    Result := Format('class %s - ohne Vererbungskette, inherited gehoert '
      + 'nicht hinein', [R.Keyword.Low])
  else if Length(R.Parts) < 2 then
    Result := Format('%s ohne Klasse (kein TKlasse.Name) - %s',
      [R.Keyword.Low, R_BY_HAND]);
end;

// Steht 'inherited' irgendwo im Text der Routine - auch in einem
// Kommentar, einem inaktiven $IFDEF-Zweig oder einer lokalen Routine? Dann
// hat ihn jemand gesetzt, verschoben oder auskommentiert, und der Detektor
// sah ihn nur nicht im AST. '' oder der Grund.
function InheritedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  Li : Integer;
begin
  Result := '';
  for Li := R.Head.Line to R.Last.Line do
    if HasIdentWord(LowerCase(AMap.Raw(Li)), WORD_INHERITED) then
      Exit(Format('"inherited" steht schon in Zeile %d (inaktiver Zweig, '
        + 'Kommentar oder lokale Routine) - %s', [Li, R_BY_HAND]));
end;

// Die Klasse AClassPath in der Unit: genau ein Kopf mit Rumpf, kein class
// helper; ihr erster Vorfahr. '' oder der Grund.
function OwnerOf(AMap: TRdxCodeMap; const AClassPath: string;
  out AOwner: TRdxOwner): string;
var
  Heads : TArray<TRdxToken>;
  Names : TArray<string>;
  Low   : string;
begin
  AOwner := Default(TRdxOwner);
  Low := LowerCase(ShortNameOf(AClassPath));
  Heads := TRdxRoutineFixes.FindClassHeads(AMap, AClassPath);
  if Length(Heads) = 0 then
  begin
    if DeclaredAs(AMap, Low, OBJECT_KINDS) then
      Exit('object-Typ (altes Objektmodell) - ' + R_BY_HAND);
    if DeclaredAs(AMap, Low, RECORD_KINDS) then
      Exit('Record - ohne Vererbung');
    Exit(Format('Klasse %s nicht in dieser Unit - der Vorfahr ist nicht '
      + 'beweisbar', [AClassPath]));
  end;
  if Length(Heads) > 1 then
    Exit(Format('%d Klassen namens %s in der Unit - mehrdeutig',
      [Length(Heads), ShortNameOf(AClassPath)]));
  AOwner.ClassTok := Heads[0];
  if After(AMap, Heads[0]).Low = 'helper' then
    Exit('class helper - inherited meint dort die erweiterte Klasse');
  Names := TRdxRoutineFixes.HeritageOf(AMap, Heads[0]);
  AOwner.Parent := 'TObject';
  if Length(Names) > 0 then
    AOwner.Parent := Names[0];
  // 'class(IFoo)': der erste Eintrag ist ein Interface - Vorfahr TObject.
  // Nur ein Interface DIESER Unit beweist das; ein fremdes 'IFoo' kann
  // eine Klasse sein.
  AOwner.DirectTObject := SameText(AOwner.Parent, 'TObject')
    or ((Length(Names) > 0)
        and DeclaredAs(AMap, LowerCase(Names[0]), INTERFACE_KINDS));
  Result := '';
end;

// Die Deklarationen der Methode R im Rumpf ihrer Klasse.
function DeclHeadsOf(AMap: TRdxCodeMap; const R: TRdxRoutine): TArray<TRdxToken>;
begin
  Result := TRdxRoutineFixes.FindMethodDecls(AMap, OwnerPathOf(R.Name),
    ShortNameOf(R.Name));
end;

// Die EINE Deklaration der Methode R. '' oder der Grund.
function DeclOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out D: TRdxRoutine): string;
var
  Heads : TArray<TRdxToken>;
begin
  D := Default(TRdxRoutine);
  Heads := DeclHeadsOf(AMap, R);
  if Length(Heads) = 0 then
    Exit(Format('keine Deklaration von %s im Rumpf der Klasse %s - %s',
      [ShortNameOf(R.Name), OwnerPathOf(R.Name), R_MOVED]));
  if Length(Heads) > 1 then
    Exit(Format('%d Deklarationen von %s in Klassen dieses Namens - '
      + 'Overload?', [Length(Heads), ShortNameOf(R.Name)]));
  Result := TRdxRoutineFixes.MethodDecl(AMap, Heads[0], D);
  if Result <> '' then
    Result := 'Deklaration: ' + Result;
end;

// Traegt D die Direktive AWord?
function HasDirectiveWord(const D: TRdxRoutine; const AWord: string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in D.Directives do
    if S = AWord then
      Exit(True);
end;

// SCA096 (b): die Deklaration traegt override (ohne overload). '' oder der
// Grund.
function CtorOverrideReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AOwner: TRdxOwner): string;
var
  D : TRdxRoutine;
begin
  Result := DeclOf(AMap, R, D);
  if Result <> '' then Exit;
  if not HasDirectiveWord(D, KW_OVERRIDE) then
    Exit(Format('Elternklasse %s und keine override-Deklaration - welcher '
      + 'Elternkonstruktor mit welchen Argumenten laufen soll, ist Entwurf; '
      + '%s', [AOwner.Parent, R_BY_HAND]));
  if HasDirectiveWord(D, KW_OVERLOAD) then
    Exit('override mit overload - welcher geerbte Konstruktor gemeint ist, '
      + 'ist nicht sicher; ' + R_BY_HAND);
end;

// SCA096 (b): bricht die erste Anweisung den Konstruktor ab - 'raise',
// 'Assert(False..)', ein Aufruf 'Raise..' ('EFoo.RaiseUtf8(..)',
// 'RaiseLastOSError')? Ein blockierter Konstruktor (Korpus: 'Assert(False);
// // Call constructor CreateWithManager') erzeugt nie ein Objekt; der
// Detektor kennt nur 'raise'. Der Elternkonstruktor davor liefe vergeblich
// und mit seinen Nebenwirkungen. '' oder der Grund.
function BlockedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T       : TRdxToken;
  Blocked : Boolean;
begin
  Result := '';
  T := After(AMap, R.Body);
  Blocked := (T.Low = 'raise')
    or ((T.Low = 'assert') and (After(AMap, T).Low = '(')
        and (After(AMap, After(AMap, T)).Low = 'false'));
  while not Blocked and (T.Low <> '') and not SameTok(T, R.EndTok)
    and not InList(T.Low, [';', '(']) do
  begin
    Blocked := T.IsWord and (Copy(T.Low, 1, Length(RAISE_PREFIX)) = RAISE_PREFIX);
    if not Blocked then
      T := After(AMap, T);
  end;
  if Blocked then
    Result := Format('der Konstruktor bricht mit seiner ersten Anweisung ab '
      + '(Zeile %d, blockierter Konstruktor) - inherited davor liefe '
      + 'vergeblich; %s', [After(AMap, R.Body).Line, R_BY_HAND]);
end;

// SCA096 (b): ruft der Rumpf als Anweisung einen Konstruktor der Klasse
// selbst - 'CreateNew(AOwner);', 'Self.CreateEx(..)'? Das ist eine
// Delegation, die der Detektor nur fuer 'Create(' kennt; der gerufene
// Konstruktor initialisiert die Elternklasse schon (TCustomForm.CreateNew
// laedt danach keine .dfm - 'inherited;' davor taete es und scheiterte).
// Erkannt am Namen 'Create..' in Anweisungsstellung; eine Routine wie
// 'CreateDir(..)' sperrt mit (lieber keine Hilfe). '' oder der Grund.
function DelegationReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if T.IsWord and (Copy(T.Low, 1, Length(CREATE_PREFIX)) = CREATE_PREFIX)
       and (InList(P.Low, STATEMENT_PREV)
            or ((P.Low = '.') and (Before(AMap, P).Low = KW_SELF))) then
      Exit(Format('Aufruf %s in Zeile %d - vielleicht ein anderer '
        + 'Konstruktor der Klasse (Delegation), der die Elternklasse schon '
        + 'initialisiert; inherited davor liefe doppelt; %s',
        [TokText(AMap, T), T.Line, R_BY_HAND]));
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: die Deklaration traegt override. '' oder der Grund.
function DtorOverrideReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  D : TRdxRoutine;
begin
  Result := DeclOf(AMap, R, D);
  if (Result = '') and not HasDirectiveWord(D, KW_OVERRIDE) then
    Result := 'die Deklaration traegt kein override - dann verdeckt der '
      + 'Destruktor die virtuelle Methode (SCA149); ' + R_BY_HAND;
end;

// SCA097: das erste Token der letzten Anweisung auf oberster Ebene des
// Rumpfs (hinter dem letzten ';' der Tiefe 0); Low = '' im leeren Rumpf.
function LastStatementStart(AMap: TRdxCodeMap; const R: TRdxRoutine): TRdxToken;
var
  T, P, N : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  P := R.Body;
  T := After(AMap, R.Body);
  if not SameTok(T, R.EndTok) then
    Result := T;
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if IsKeywordAfter(T, P) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and (T.Low = KW_END) then
      Dec(Depth)
    else if (Depth = 0) and (T.Low = ';') then
    begin
      N := After(AMap, T);
      if not SameTok(N, R.EndTok) then
        Result := N;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: endet der Rumpf mit Exit, raise, Halt, Abort oder goto? Dann
// liefe ein inherited dahinter nie. '' oder der Grund.
function DeadEndReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  S : TRdxToken;
begin
  Result := '';
  S := LastStatementStart(AMap, R);
  if InList(S.Low, DEAD_END_WORDS) then
    Result := Format('die letzte Anweisung ist %s (Zeile %d) - inherited '
      + 'dahinter liefe nie; %s', [TokText(AMap, S), S.Line, R_BY_HAND]);
end;

{ ---- Result (SCA121, SCA196) ---- }

// Gibt es Result? Nicht in den FPC-Modi fpc/tp/macpas/iso und nicht unter
// '{$X-}' bzw. '{$EXTENDEDSYNTAX OFF}' (auch in einer Schalterliste
// '{$H+,X-}'). '' oder der Grund.
function DirectiveResultReason(AMap: TRdxCodeMap; ALine, ACol: Integer): string;
var
  W, Args, Sw : string;
  Arg         : Boolean;
begin
  Result := '';
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  Args := LowerCase(Trim(DirectiveArgs(AMap, ALine, ACol)));
  if (W = 'mode') and InList(Args, NO_RESULT_MODES) then
    Exit(Format('{$mode %s} in Zeile %d - dort gibt es kein Result',
      [Args, ALine]));
  if (W = 'extendedsyntax') and (Copy(Args, 1, 3) = 'off') then
    Exit(Format('{$EXTENDEDSYNTAX OFF} in Zeile %d - dort gibt es kein '
      + 'Result', [ALine]));
  if Length(W) <> 1 then Exit;
  Sw := ',' + StringReplace(W + Args, ' ', '', [rfReplaceAll]) + ',';
  if Pos(',x-,', Sw) > 0 then
    Result := Format('{$X-} in Zeile %d - dort gibt es kein Result', [ALine]);
end;

function ResultModeReason(AMap: TRdxCodeMap): string;
var
  Li, Co : Integer;
  L      : string;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    for Co := 1 to Length(L) do
      if CharInSet(L[Co], ['{', '(']) and OpensDirective(AMap, Li, Co) then
      begin
        Result := DirectiveResultReason(AMap, Li, Co);
        if Result <> '' then Exit;
      end;
  end;
end;

// SCA121: Default() ist ein Compiler-Intrinsic (Delphi 2009, FPC 3.0) -
// Skript-Units ('unit X;' ohne implementation-Teil: xEdit-Skripte,
// JvInterpreter-Beispiele) und Include-Dateien uebersetzt kein Compiler,
// ihre Interpreter kennen es nicht. '' oder der Grund.
function ScriptReason(AMap: TRdxCodeMap): string;
var
  T, P : TRdxToken;
begin
  T := NextToken(AMap, 1, 1);
  if InList(T.Low, PROGRAM_WORDS) then
    Exit('');
  if T.Low <> 'unit' then
    Exit('die Datei beginnt nicht mit unit/program/library (Include oder '
      + 'Skript?) - Default() kennt nur der Compiler');
  P := T;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit('');
    P := T;
    T := After(AMap, T);
  end;
  Result := 'unit ohne implementation-Teil (Skript?) - Default() kennt nur '
    + 'der Compiler';
end;

// Hat R den Namen AName (letztes Glied, ohne Typparameter)? '' oder der
// Grund.
function NameReason(const R: TRdxRoutine; const AName: string): string;
var
  N : string;
begin
  Result := '';
  N := AName;
  if Pos('<', N) > 0 then
    N := Copy(N, 1, Pos('<', N) - 1);
  if not SameIdent(LowerCase(ShortNameOf(R.Name)), LowerCase(N)) then
    Result := Format('die Routine heisst %s, die Meldung nennt %s - %s',
      [R.Name, AName, R_MOVED]);
end;

// Der Rueckgabetyp hinter dem Namen von R: ':' hinter Typparametern und
// Parameterliste bis vor das ';' des Kopfs, wie im Quelltext. AType = ''
// ohne ':' (Implementierungskopf ohne Signatur). '' oder der Grund.
function TypeAfterHead(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AType: string): string;
var
  T : TRdxToken;
begin
  AType := '';
  Result := '';
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low = '(' then
    T := AfterClose(AMap, T);
  if T.Low <> ':' then Exit;
  if T.Line <> R.HeaderEnd.Line then
    Exit('Rueckgabetyp ueber mehrere Zeilen - ' + R_BY_HAND);
  if AMap.HasNonCode(T.Line, T.EndCol, R.HeaderEnd.Col - 1) then
    Exit('Kommentar oder Direktive im Rueckgabetyp - ' + R_BY_HAND);
  AType := Trim(Copy(AMap.Raw(T.Line), T.EndCol, R.HeaderEnd.Col - T.EndCol));
end;

// Der Rueckgabetyp von R - aus dem Kopf, bei einer Methode ohne Signatur
// aus ihrer Deklaration im Klassenrumpf. '' oder der Grund.
function ResultTypeOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AType: string): string;
var
  D : TRdxRoutine;
begin
  Result := TypeAfterHead(AMap, R, AType);
  if (Result <> '') or (AType <> '') then Exit;
  if Length(R.Parts) < 2 then
    Exit('Kopf ohne Rueckgabetyp, keine Methode - die Deklaration liest die '
      + 'Hilfe nicht; ' + R_BY_HAND);
  Result := DeclOf(AMap, R, D);
  if Result = '' then
    Result := TypeAfterHead(AMap, D, AType);
  if (Result = '') and (AType = '') then
    Result := 'auch die Deklaration nennt keinen Rueckgabetyp';
end;

// SCA121: passt AType in Default()? Ein Typbezeichner, Glieder mit '.',
// Typargumente '<..>' - kein FPC 'specialize', keine Klammern. '' oder der
// Grund.
function TypeTextReason(const AType: string): string;
var
  i : Integer;
begin
  Result := '';
  if HasAsciiWord(LowerCase(AType), 'specialize') then
    Exit('FPC "specialize" im Rueckgabetyp - Default() mit dem Typ von Hand');
  for i := 1 to Length(AType) do
    if not (IsIdentChar(AType[i]) or CharInSet(AType[i], ['.', '<', '>', ',', ' '])) then
      Exit(Format('Rueckgabetyp "%s" ist kein einfacher Typbezeichner - %s',
        [AType, R_BY_HAND]));
end;

// SCA196: gleicher Typ wie in der Meldung (ohne Leerraum, Gross/klein
// egal)?
function SameTypeText(const A, B: string): Boolean;
begin
  Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]),
    StringReplace(B, ' ', '', [rfReplaceAll]));
end;

// SCA196: 'X: T absolute Result' im Deklarationsteil - geschrieben wird
// ueber den Alias. '' oder der Grund.
function AbsoluteReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T : TRdxToken;
begin
  Result := '';
  T := After(AMap, R.HeaderEnd);
  while (T.Low <> '') and not SameTok(T, R.Body) do
  begin
    if (T.Low = 'absolute') and (After(AMap, T).Low = KW_RESULT) then
      Exit(Format('"absolute Result" in Zeile %d - Result wird ueber den '
        + 'Alias geschrieben; %s', [T.Line, R_BY_HAND]));
    T := After(AMap, T);
  end;
end;

// SCA196: steht Result auf der gemeldeten Lese-Zeile als Code (nicht als
// Member 'X.Result')?
function ReadsResultOn(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  P := Before(AMap, T);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = KW_RESULT) and (P.Low <> '.') then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA196: ein dynamisches Array? Die Namen der RTL oder 'Name = array of'
// bzw. 'Name = TArray<..>' in der Unit.
function DynArrayProven(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  K : TRdxToken;
begin
  if InList(ALow, RTL_DYN_ARRAYS) then
    Exit(True);
  K := TypeDeclKind(AMap, ALow, ARRAY_KINDS);
  Result := ((K.Low = 'array') and (After(AMap, K).Low = 'of'))
    or ((K.Low = 'tarray') and (After(AMap, K).Low = '<'));
end;

// SCA196: ein Interface? 'I' + Grossbuchstabe und als Interface in der
// Unit deklariert bzw. ein Typ der Delphi-Quellen (uRdxRtlTypes - dort
// stehen Klassen und Interfaces, die I-Schreibweise trennt sie).
function InterfaceProven(AMap: TRdxCodeMap; const AType: string): Boolean;
var
  Name : string;
begin
  Name := ShortNameOf(AType);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  Result := (Length(Name) >= 2) and (Name[1] = 'I')
    and CharInSet(Name[2], ['A'..'Z'])
    and (DeclaredAs(AMap, LowerCase(Name), INTERFACE_KINDS)
         or IsRtlClassOrInterface(LowerCase(Name)));
end;

// SCA196: die Initialisierung fuer den Rueckgabetyp AType (ohne ';'). ''
// oder der Grund; AVariants bei VarClear.
function StatementFor(AMap: TRdxCodeMap; const AType: string;
  out AStmt: string; out AVariants: Boolean): string;
var
  Low : string;
begin
  Result := '';
  AStmt := '';
  AVariants := False;
  Low := LowerCase(StringReplace(AType, ' ', '', [rfReplaceAll]));
  if Copy(Low, 1, 7) = 'system.' then
    Delete(Low, 1, 7);
  if InList(Low, STRING_TYPES) or (Copy(Low, 1, 7) = 'string[') then
    AStmt := STMT_EMPTY_STRING
  else if (Low = 'tbytes') or (Copy(Low, 1, 7) = 'tarray<') then
    AStmt := STMT_NIL
  else if InList(Low, VARIANT_TYPES) then
  begin
    AStmt := STMT_VARCLEAR;
    AVariants := True;
  end
  else if DynArrayProven(AMap, Low) or InterfaceProven(AMap, AType) then
    AStmt := STMT_NIL
  else
    Result := Format('Rueckgabetyp %s ist nicht als String, dynamisches '
      + 'Array, Interface oder Variant bewiesen - %s', [AType, R_BY_HAND]);
end;

{ ---- Gemeinsame Nachweise ---- }

// SCA096/SCA097: was beide Planer nachweisen - die Meldung, genau ein Kopf
// AWord ('constructor' bzw. 'destructor') auf ALine, eine Methode mit
// Klasse ohne 'class' davor, ein begin-Rumpf ohne asm und ohne Direktive
// davor, kein 'inherited' im Text der Routine und die Klasse in der Unit.
// '' oder der Grund.
function MethodCtxReason(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage, AWord: string; out ACtx: TRdxMethodCtx): string;
var
  Key, What : string;
begin
  ACtx := Default(TRdxMethodCtx);
  Key := KEY_DTOR;
  What := 'eines Destruktors';
  if AWord = KW_CONSTRUCTOR then
  begin
    Key := KEY_CTOR;
    What := 'eines Konstruktors';
  end;
  if Pos(Key, AMessage) = 0 then
    Exit(Format('Meldung unbekannt - kein "%s"', [Key]));
  Result := RoutineOnLine(AMap, ALine, AWord, What, ACtx.R);
  if Result = '' then
    Result := MethodHeadReason(ACtx.R);
  if Result = '' then
    Result := BodyReason(AMap, ACtx.R);
  if Result = '' then
    Result := InheritedReason(AMap, ACtx.R);
  if Result = '' then
    Result := OwnerOf(AMap, OwnerPathOf(ACtx.R.Name), ACtx.O);
end;

// SCA096: die Variante nach dem Vorfahren - (a) direkter TObject-Erbe:
// 'inherited Create' (die Deklaration muss es geben, sonst gehoert der
// Kopf nicht zu dieser Klasse; ein overload stoert nicht - 'inherited
// Create' meint immer TObject.Create); (b) override: 'inherited',
// gekennzeichnet, ohne Delegation und nicht blockiert. Setzt APlan.Name
// bzw. APlan.Changes. '' oder der Grund.
function CtorVariantReason(AMap: TRdxCodeMap; const ACtx: TRdxMethodCtx;
  var APlan: TRdxResultPlan): string;
begin
  if ACtx.O.DirectTObject then
  begin
    APlan.Name := STMT_INHERITED_CREATE;
    if Length(DeclHeadsOf(AMap, ACtx.R)) = 0 then
      Exit(Format('keine Deklaration von %s im Rumpf der Klasse %s - %s',
        [ShortNameOf(ACtx.R.Name), OwnerPathOf(ACtx.R.Name), R_MOVED]));
    Exit('');
  end;
  Result := CtorOverrideReason(AMap, ACtx.R, ACtx.O);
  APlan.Changes := Result = '';
  if Result = '' then
    Result := DelegationReason(AMap, ACtx.R);
  if Result = '' then
    Result := BlockedReason(AMap, ACtx.R);
end;

// SCA196: die Funktion um die Lese-Zeile ALine - auf der Zeile steht
// Result, die innerste Routine heisst AName, hat einen begin-Rumpf ohne
// asm, Result gibt es (Modus), ihr Rueckgabetyp ist AMsgType, kein
// 'absolute Result'. '' oder der Grund; ACtx.TypeTx wie im Quelltext.
function FuncCtxReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName, AMsgType: string; out ACtx: TRdxFuncCtx): string;
begin
  ACtx := Default(TRdxFuncCtx);
  if not ReadsResultOn(AMap, ALine) then
    Exit(R_NO_READ);
  Result := EnclosingRoutine(AMap, ALine, ACtx.R);
  if Result = '' then
    Result := NameReason(ACtx.R, AName);
  if Result = '' then
    Result := BodyReason(AMap, ACtx.R);
  if Result = '' then
    Result := ResultModeReason(AMap);
  if Result = '' then
    Result := ResultTypeOf(AMap, ACtx.R, ACtx.TypeTx);
  if (Result = '') and not SameTypeText(ACtx.TypeTx, AMsgType) then
    Result := Format('der Kopf nennt %s, die Meldung %s - %s',
      [ACtx.TypeTx, AMsgType, R_MOVED]);
  if Result = '' then
    Result := AbsoluteReason(AMap, ACtx.R);
end;

{ ---- Gemeinsamer Abschluss ---- }

// AReason = '': die Ersetzung in den Plan; sonst Ersetzungen leeren.
function Finish(var APlan: TRdxResultPlan; const AEdits: TArray<TRdxEdit>;
  const AReason: string): Boolean;
begin
  Result := AReason = '';
  if Result then
    APlan.Edits := AEdits
  else
    APlan.Edits := nil;
end;

// Der Rumpf von R mit AStmt als erster Anweisung (fuer Finish).
function FirstEdits(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AStmt: string; out AEdits: TArray<TRdxEdit>): string;
var
  E : TRdxEdit;
begin
  AEdits := nil;
  Result := TRdxResultFixes.FirstStatement(AMap, R, AStmt, E);
  if Result = '' then
    AddEdit(AEdits, E);
end;

{ TRdxResultFixes }

class function TRdxResultFixes.FirstStatement(AMap: TRdxCodeMap;
  const R: TRdxRoutine; const AStmt: string; out AEdit: TRdxEdit): string;
var
  B : TRdxToken;
  L : string;
begin
  AEdit := Default(TRdxEdit);
  B := R.Body;
  if B.Low <> KW_BEGIN then
    Exit('kein begin-Rumpf');
  L := AMap.Raw(B.Line);
  if QuietAfter(AMap, B) then
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_RESULT, B.Line, B.Col, B.Line,
      Length(L) + 1);
    AEdit.Expected := Copy(L, B.Col, MaxInt);
    AEdit.NewText := AEdit.Expected + #10 + BodyIndent(AMap, R) + AStmt;
  end
  else
    AEdit := TokenEdit(AMap, B, TokText(AMap, B) + ' ' + AStmt);
  Result := '';
end;

class function TRdxResultFixes.LastStatement(AMap: TRdxCodeMap;
  const R: TRdxRoutine; const AStmt: string;
  out AEdits: TArray<TRdxEdit>): string;
var
  Last, En : TRdxToken;
  E        : TRdxEdit;
  Semi     : string;
begin
  AEdits := nil;
  if R.Body.Low <> KW_BEGIN then
    Exit('kein begin-Rumpf');
  En := R.EndTok;
  Last := Before(AMap, En);
  if SameTok(Last, R.Body) then
    Exit(FirstEdits(AMap, R, AStmt, AEdits));
  if DirectiveBetween(AMap, Last, En) then
    Exit('Compiler-Direktive zwischen der letzten Anweisung und end - das '
      + 'Ende kann je Zweig anders aussehen; ' + R_BY_HAND);
  Semi := '';
  if Last.Low <> ';' then
    Semi := ';';
  if FirstOnLine(AMap, En) then
  begin
    if Semi <> '' then
      AddEdit(AEdits, TokenEdit(AMap, Last, TokText(AMap, Last) + Semi));
    E.Span := TRefactorSpan.Make(SPAN_RESULT, En.Line, 1, En.Line, En.EndCol);
    E.Expected := Copy(AMap.Raw(En.Line), 1, En.EndCol - 1);
    E.NewText := BodyIndent(AMap, R) + AStmt + #10 + E.Expected;
    AddEdit(AEdits, E);
  end
  else
    AddEdit(AEdits, TokenEdit(AMap, Last,
      TokText(AMap, Last) + Semi + ' ' + AStmt));
  Result := '';
end;

class function TRdxResultFixes.ConstructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_CONSTRUCTOR, Ctx);
  if AReason = '' then
    AReason := CtorVariantReason(AMap, Ctx, APlan);
  if AReason = '' then
    AReason := FirstEdits(AMap, Ctx.R, APlan.Name + ';', Edits);
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.DestructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  APlan.Changes := True;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_DESTRUCTOR, Ctx);
  if AReason = '' then
    AReason := DtorOverrideReason(AMap, Ctx.R);
  if AReason = '' then
    AReason := DeadEndReason(AMap, Ctx.R);
  if AReason = '' then
    AReason := LastStatement(AMap, Ctx.R, STMT_INHERITED + ';', Edits);
  // TObject.Destroy ist leer: bei direktem TObject-Erben gleiche Bedeutung.
  if AReason = '' then
    APlan.Changes := not Ctx.O.DirectTObject;
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.ResultDefault(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  R      : TRdxRoutine;
  Name   : string;
  TypeTx : string;
  Edits  : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  Edits := nil;
  TypeTx := '';
  AReason := '';
  Name := TextBetween(AMessage, KEY_FUNC, KEY_NEVER);
  if Name = '' then
    AReason := 'Name der Funktion fehlt in der Meldung';
  if AReason = '' then
    AReason := RoutineOnLine(AMap, ALine, 'function|operator',
      'einer Funktion', R);
  if AReason = '' then
    AReason := NameReason(R, Name);
  if AReason = '' then
    AReason := BodyReason(AMap, R);
  if AReason = '' then
    AReason := ScriptReason(AMap);
  if AReason = '' then
    AReason := ResultModeReason(AMap);
  if AReason = '' then
    AReason := ResultTypeOf(AMap, R, TypeTx);
  if AReason = '' then
  begin
    APlan.Name := TypeTx;
    AReason := TypeTextReason(TypeTx);
  end;
  if AReason = '' then
    AReason := FirstEdits(AMap, R, 'Result := Default(' + TypeTx + ');',
      Edits);
  Result := Finish(APlan, Edits, AReason);
end;

class function TRdxResultFixes.ManagedResultInit(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx     : TRdxFuncCtx;
  Name    : string;
  MsgType : string;
  Stmt    : string;
  Vars    : Boolean;
  Edits   : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  Edits := nil;
  AReason := '';
  Name := TextBetween(AMessage, KEY_FUNC, KEY_READS);
  MsgType := TextBetween(AMessage, KEY_TYPE, KEY_TYPE_END);
  if (Name = '') or (MsgType = '') then
    AReason := 'Funktion oder Rueckgabetyp fehlt in der Meldung'
  // Der Name im Menue schon aus der Meldung (der Beweis folgt).
  else if StatementFor(AMap, MsgType, Stmt, Vars) = '' then
    APlan.Name := Stmt;
  if AReason = '' then
    AReason := FuncCtxReason(AMap, ALine, Name, MsgType, Ctx);
  if AReason = '' then
    AReason := StatementFor(AMap, Ctx.TypeTx, Stmt, Vars);
  if AReason = '' then
  begin
    APlan.Name := Stmt;
    APlan.NeedsVariants := Vars;
    AReason := FirstEdits(AMap, Ctx.R, Stmt + ';', Edits);
  end;
  Result := Finish(APlan, Edits, AReason);
end;

end.
