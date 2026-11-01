unit uRdxMethodNameFix;

// reDelphix - Editorhilfe fuer SCA106 MethodName, OHNE ToolsAPI und ohne
// Parser: der erste Buchstabe einer Methode wird gross geschrieben ('doWork'
// -> 'DoWork') - im Kopf der Deklaration im Klassenrumpf UND im Kopf
// 'TKlasse.doWork' der Implementierung derselben Datei, in EINEM
// Undo-Schritt (bis zu zwei Ersetzungen in TRdxMethodNamePlan.Edits, wie
// SCA147 Deklaration und Implementierung in uRdxRoutineFixes).
//
// DER FUND: uMethodName meldet je (Besitzertyp, Name) EINMAL, auf der Zeile
// des Routinenworts (nkMethod.Line - procedure, function, constructor ...,
// nicht 'class' davor) des ERSTEN Knotens in Dokumentreihenfolge; bei einer
// Methode ist das die Deklaration im Klassenrumpf. Die Meldung nennt nur den
// Namen ('Method `doWork` should be PascalCase (start with uppercase
// letter).'), nicht die Klasse: der Planer sucht die Klasse um die
// Deklaration selbst (ClassAround). Steht die Implementierung vor jeder
// Deklaration (Klasse in einem Include), meldet der Detektor den Kopf
// 'procedure TFoo.doWork' - keine Hilfe. Den Kopf 'procedure TFoo.doWork'
// meldet er auch, wenn die Deklaration schon gross geschrieben ist
// ('procedure DoWork;' besteht die Pruefung, die Implementierung nicht):
// dann gleicht die Hilfe NUR den Implementierungskopf an die Schreibweise
// der Deklaration an (ImplSpellingPlan; Realwelt-Test rwE29, cnwizards
// DCURecs.pas:7864 'TDispPropDecl.visit' zu 'Visit') - der Laufzeit-Name
// kommt aus der Deklaration und bleibt. Beginnt auch die Deklaration klein,
// geht die Hilfe den Weg ueber die Deklaration (rwE30 Stufe 2).
//
// FREIE ROUTINEN (rwE30 Stufe 2, FreeRoutinePlan): eine Routine ausserhalb
// jedes Typs bekommt die Hilfe in allen ihren Koepfen (Deklaration im
// interface-Teil bzw. forward und Rumpf) - Aufrufe auch anderer Units binden
// ohne Gross/klein. Gesperrt, sobald ein Linker, eine Bibliothek oder C-Code
// den genauen Namen braucht (external, export, public, alias, {$L}, exports,
// eine Direktive mit dem Namen, cdecl/stdcall ... an einem Kopf im
// interface-Teil), bei einem String-Literal mit dem Namen und bei mehr als
// einem Paar Koepfe - ausser bei Overloads: dann alle Koepfe (rwE31 Stufe 3).
//
// BEDEUTUNGSGLEICH: Delphi vergleicht Bezeichner ohne Gross/klein. Aufrufe,
// Property-Accessoren ('read doWork'), Methodenzuweisungen und
// Ueberschreibungen in Nachfahren binden nach der Hilfe unveraendert; die
// Hilfe schreibt sie NICHT um (kein Muss - der Hinweis sagt es). Eine
// published Methode, die eine .dfm/.fmx/.lfm als Ereignis bindet ('OnClick
// = doWork'), bindet weiter: TReader findet sie ueber TObject.MethodAddress,
// und das vergleicht ohne Gross/klein (System.pas: UTF8IdentIdentCompare) -
// die Formdatei behaelt ihre Schreibweise, ohne Schaden. Was sich aendert,
// ist nur der Laufzeit-Name: RTTI (TRttiMethod.Name) und TObject.MethodName
// nennen danach 'DoWork'. Wer diese Namen mit Gross/klein vergleicht, sieht
// den Unterschied - der Hinweis nennt es. Nennt ein String-Literal der Datei
// den Namen (Aufruf per Name), sperrt die Hilfe (s. unten); ebenso unter
// 'published': die published-Methodentabelle ist genau die Liste, die
// Frameworks per Name durchsuchen (Realwelt-Test rwE29: Double Commander
// TFormCommands.GetMethodsList filtert sie mit StrBegins(Name, 'cm_'),
// case-sensitiv - nach 'Cm_Start' verschwand das Kommando).
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - die Meldung nennt keinen Namen mit kleinem Anfangsbuchstaben,
//   - kein Kopf der Methode auf der gemeldeten Zeile oder mehr als einer;
//     die Deklaration ist schon anders geschrieben (Zeile verschoben, Fund
//     veraltet) - Kommentare und Strings sind nie Code (Code-Sicht),
//   - die Deklaration steht im Rumpf eines anderen Typs (record,
//     Interface) oder einer Klasse in einem Include,
//   - sie steht unter 'published' (Methodentabelle, s. oben; der Abschnitt
//     ohne Wort - published in TPersistent-Erben, dort stehen die
//     Ereignis-Methoden der Formulare - bleibt eine Hilfe),
//   - keine oder mehr als eine Implementierung in der Datei (abstract,
//     external, Include, $IFDEF-Zwillinge) - bei 'overload' oder mehr als
//     einer Deklaration in Klassen dieses Namens ($IFDEF-Zwillinge) gilt
//     die Hilfe seit rwE31 Stufe 3 fuer ALLE Deklarationen und
//     Implementierungen (AllHeadsPlan), gesperrt nur ohne Implementierung,
//     unter published oder mit Include,
//   - ein {$I}-Include im Klassenrumpf,
//   - ein String-Literal der Datei nennt den Namen (Aufruf per Name ueber
//     RTTI, MethodAddress, Skript - ein Vergleich dort kann Gross/klein
//     beachten); nicht als letztes Glied eines reinen Punktpfads
//     ('Unit.TKlasse.name' - eine Log-Kennung, LiteralNames, rwE30) und
//     nicht als Wort eines Satzes (IsProseFor, rwE31 Stufe 3).
//
// FPC-TAUGLICH: nur Textlogik auf der Code-Sicht (uRdxCodeMap, uRdxBlocks,
// uRdxBufferMath, uRdxText, uRefactorInfo - alle im FPC-Pruefstand). Den
// Adapter fuer die Tabelle (PlanMethodName ueber TRdxFixFrame) traegt
// uRdxFixTable (Hausregel dort): die Unit bindet weder uEngineApi noch
// uMethodd12 noch die Laeufer.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_MN_NO_NAME = 'the message names no method with a lowercase first letter';
  R_MN_NO_HEAD = 'no declaration of "%s" on the reported line';
  R_MN_MANY_HEADS = 'the reported line declares "%s" more than once';
  R_MN_IMPL_ONLY = 'the reported line holds the implementation of "%s", not '
    + 'its declaration - no class of this file declares it before';
  R_MN_SPELLING = 'the declaration is spelled "%s", the finding names "%s"';
  R_MN_NO_CLASS = '"%s" is not declared in the body of a class of this file '
    + '(free routine, record, interface, or the class sits in an include)';
  R_MN_DECL = 'the declaration of "%s" cannot be read safely';
  R_MN_OVERLOAD = '"%s" is overloaded - the help does not pick one of the '
    + 'declarations';
  R_MN_DECLS = '%d declarations of "%s" in classes named %s - overload or '
    + 'conditional twin?';
  R_MN_NO_IMPL = 'no implementation %s.%s in this file (abstract, external '
    + 'or in an include)';
  R_MN_IMPLS = '%d implementations of %s.%s in this file - overload or '
    + 'conditional twin?';
  R_MN_INCLUDE = 'include directive in the class body (line %d) - it can '
    + 'declare more of the class';
  R_MN_LITERAL = 'a string literal names "%s" (line %d) - a lookup by name '
    + '(RTTI, MethodAddress, script) may compare case-sensitively';
  R_MN_PUBLISHED = '"%s" is published - its name is in the method table, '
    + 'code that looks it up by name (RTTI, MethodName, a command list) may '
    + 'compare case-sensitively';
  // Freie Routinen (rwE30 Stufe 2, FreeRoutinePlan).
  R_MN_FREE_HEADS = '%d headers of a free routine "%s" - overload or '
    + 'conditional twin?';
  R_MN_FREE_PAIR = 'the headers of "%s" are not one declaration (interface '
    + 'or forward) and one implementation';
  R_MN_FREE_HEAD = 'the header of "%s" in line %d cannot be read safely';
  R_MN_FREE_BOUND = '"%s" is "%s" - a linker, a library or C code binds the '
    + 'routine by its exact name';
  R_MN_FREE_LINK = 'the unit links an object file ({$L} in line %d) - C code '
    + 'may call "%s" by its exact name';
  R_MN_FREE_EXPORTS = 'the exports clause names "%s" (line %d) - the exported '
    + 'name keeps the spelling';
  R_MN_FREE_DIRECTIVE = 'a compiler directive names "%s" (line %d)';
  R_MN_FREE_API = '"%s" is written like a C or platform API name (underscore, '
    + 'no capital letter or a k constant) - a capital first letter does not '
    + 'make it PascalCase; rename it by hand or suppress the finding';

type
  // Ergebnis des Planers: die Ersetzungen (EIN Undo-Schritt; die der
  // Implementierung fehlt, wenn ihr Name schon gross beginnt) und der neue
  // Name fuer den Menuetext - schon aus der Meldung, auch wenn abgelehnt
  // wird.
  TRdxMethodNamePlan = record
    Edits : TArray<TRdxEdit>;
    Name  : string;
  end;

  // Der Planer auf der Code-Sicht in der Form TRdxPlannerOf<TPlan>
  // (uRdxFixTable): True genau dann, wenn AReason = ''.
  TRdxMethodNameFix = class
  public
    // SCA106: den Namen der Meldung in Deklaration (Kopf auf ALine) und
    // Implementierung gross beginnen (s. Kopf der Unit).
    class function Capitalize(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxMethodNamePlan;
      out AReason: string): Boolean; static;
  end;

// Der Name der Meldung ('Method `doWork` should ...' -> 'doWork'); '' ohne.
function MethodNameOf(const AMessage: string): string;
// AName mit grossem ersten Buchstaben (nur ASCII; sonst unveraendert).
function PascalName(const AName: string): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // TRdxBlocks (Finder), EnclosingClass, ClassEnd

const
  SPAN_106 = 'sca106';
  QUOTE_NAME = '`';
  KW_CLASS = 'class';
  DIR_OVERLOAD = 'overload';
  VIS_PUBLISHED = 'published';
  // Hier endet die Suche nach der Klasse um die Deklaration ('interface'
  // auch als Typ 'IFoo = interface': eine Deklaration darin hat keine
  // Klasse).
  UNIT_WORDS: array[0..4] of string = ('interface', 'implementation', 'unit',
    'program', 'library');
  // Freie Routinen (FreeRoutinePlan): die Direktiven hinter dem Kopf ...
  FREE_DIRECTIVES: array[0..33] of string = ('overload', 'inline',
    'assembler', 'register', 'pascal', 'cdecl', 'stdcall', 'safecall',
    'winapi', 'varargs', 'forward', 'external', 'export', 'far', 'near',
    'public', 'alias', 'interrupt', 'compilerproc', 'rtlproc', 'internproc',
    'weakexternal', 'deprecated', 'platform', 'experimental', 'library',
    'noreturn', 'local', 'nostackframe', 'iocheck', 'vectorcall', 'unsafe',
    'static', 'mwpascal');
  // ... und die, mit denen ein Linker, eine Bibliothek oder C-Code die
  // Routine beim genauen Namen bindet (Import/Export, FPC-Symbolnamen; '['
  // = FPC-Modifikatoren in eckigen Klammern). Bis rwE31 Stufe 3 standen
  // hier auch 'overload' (s. FreeHeadsReason) und die C-Aufrufkonventionen
  // (FREE_CALLCONV).
  FREE_BOUND: array[0..10] of string = ('external', 'export', 'public',
    'alias', 'varargs', 'interrupt', 'compilerproc', 'rtlproc', 'internproc',
    'weakexternal', '[');
  // Eine C-Aufrufkonvention bindet keinen Namen - die Routine geht als
  // Adresse an C-Code ('luaP_register(L, ''X'', @luaX)', rwE31 Stufe 3:
  // doublecmd uluapas.pas:233/389). Den Namen braucht C-Code nur, wenn er
  // sie ueber den Linker findet: eine {$L}-Objektdatei dieser Unit
  // (FreeFileReason) oder einer anderen, die den interface-Teil sieht
  // (Abbrevia AbCrtl.pas 'isdigit ... cdecl' fuer bzlib.obj) - darum sperrt
  // sie nur bei einem Kopf im interface-Teil.
  FREE_CALLCONV: array[0..3] of string = ('cdecl', 'stdcall', 'safecall',
    'winapi');
  // Hier beginnt hinter einem Routinenkopf ohne ';' schon der Rumpf.
  FREE_HEAD_BREAKS: array[0..5] of string = ('begin', 'asm', 'var', 'const',
    'type', 'label');
  LINK_WORDS: array[0..1] of string = ('l', 'link');
  WORD_FORWARD = 'forward';

function MethodNameOf(const AMessage: string): string;
begin
  Result := QuotedText(AMessage, QUOTE_NAME);
end;

function PascalName(const AName: string): string;
begin
  Result := UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
end;

// Beginnt S mit einem Kleinbuchstaben a..z (wie der Detektor prueft)?
function StartsLower(const S: string): Boolean;
begin
  Result := (S <> '') and CharInSet(S[1], ['a'..'z']);
end;

// Die Ersetzung, die das Wort T mit grossem ersten Buchstaben schreibt.
function CapEdit(AMap: TRdxCodeMap; const T: TRdxToken): TRdxEdit;
var
  S : string;
begin
  S := TokText(AMap, T);
  Result := Default(TRdxEdit);
  Result.Span := TRefactorSpan.Make(SPAN_106, T.Line, T.Col, T.Line, T.EndCol);
  Result.Expected := S;
  Result.NewText := PascalName(S);
end;

// Die Ersetzung, die das Wort T als ASpelling schreibt (dieselbe Zeichen-
// folge bis auf Gross/klein).
function SpellEdit(AMap: TRdxCodeMap; const T: TRdxToken;
  const ASpelling: string): TRdxEdit;
begin
  Result := Default(TRdxEdit);
  Result.Span := TRefactorSpan.Make(SPAN_106, T.Line, T.Col, T.Line, T.EndCol);
  Result.Expected := TokText(AMap, T);
  Result.NewText := ASpelling;
end;

// Traegt ALine einen qualifizierten Kopf 'procedure TFoo.AName' - eine
// Implementierung, die der Detektor meldet, weil keine Deklaration davor
// steht (Klasse in einem Include)?
function ImplHeadOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ALowName: string): Boolean;
var
  T, N : TRdxToken;
begin
  Result := False;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsRoutineHead(AMap, T) then
    begin
      N := NameAfter(AMap, T);
      if SameIdent(N.Low, ALowName) and not SameTok(N, After(AMap, T)) then
        Exit(True);
    end;
    T := After(AMap, T);
  end;
end;

// Der eine Kopf der Methode AName auf ALine (Anfang: 'class' davor oder das
// Routinenwort, HeadStart). '' oder der Grund; AImplOnly: die Zeile traegt
// statt der Deklaration nur die Implementierung (Grund R_MN_IMPL_ONLY).
function HeadOnLine(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  out AHead: TRdxToken; out AImplOnly: Boolean): string;
var
  T, Hit  : TRdxToken;
  n       : Integer;
  LowName : string;
begin
  AHead := Default(TRdxToken);
  AImplOnly := False;
  Hit := Default(TRdxToken);
  LowName := LowerCase(AName);
  n := 0;
  if (ALine >= 1) and (ALine <= AMap.LineCount) then
  begin
    T := NextToken(AMap, ALine, 1);
    while (T.Low <> '') and (T.Line = ALine) do
    begin
      if IsHeadNamed(AMap, T, LowName) then
      begin
        Inc(n);
        Hit := T;
      end;
      T := After(AMap, T);
    end;
  end;
  if (n = 0) and (ALine >= 1) and (ALine <= AMap.LineCount)
     and ImplHeadOnLine(AMap, ALine, LowName) then
  begin
    AImplOnly := True;
    Exit(_(R_MN_IMPL_ONLY, [AName]));
  end;
  if n = 0 then
    Exit(MsgMovedSuffix(_(R_MN_NO_HEAD, [AName])));
  if n > 1 then
    Exit(_(R_MN_MANY_HEADS, [AName]));
  AHead := HeadStart(AMap, Hit);
  Result := '';
end;

// Steht an T der Kopf 'T [<..>] = [packed] class' einer Klasse mit Rumpf
// (wie ClassHeadAt in uRdxBlocks, ohne den Namen vorher zu kennen)?
function IsClassHead(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  if not T.IsWord then Exit;
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  N := After(AMap, N);
  if N.Low = 'packed' then
    N := After(AMap, N);
  Result := (N.Low = KW_CLASS) and TypeHasBody(AMap, N);
end;

// Die innerste Klasse dieser Datei, deren Rumpf AHead auf Tiefe 1 traegt:
// von AHead rueckwaerts der erste Klassenkopf, fuer den EnclosingClass
// (uRdxBlocks) das bestaetigt - eine verschachtelte Klasse, die vor AHead
// endet, besteht die Probe nicht, die Suche geht weiter. Ein Abschnittswort
// (UNIT_WORDS) beendet die Suche ohne Klasse.
function ClassAround(AMap: TRdxCodeMap; const AHead: TRdxToken;
  out AClass: TRdxClassHead): Boolean;
var
  T, P : TRdxToken;
begin
  AClass := Default(TRdxClassHead);
  T := Before(AMap, AHead);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if InList(T.Low, UNIT_WORDS) and IsKeywordAfter(T, P) then
      Break;
    if IsClassHead(AMap, T) and EnclosingClass(AMap, AHead, T.Low, AClass)
       and SameTok(AClass.NameTok, T) then
      Exit(True);
    T := P;
  end;
  AClass := Default(TRdxClassHead);
  Result := False;
end;

// Ein {$I}-Include im Rumpf der Klasse AClass: '' oder der Grund.
function ClassIncludeReason(AMap: TRdxCodeMap;
  const AClass: TRdxClassHead): string;
var
  Stop          : TRdxToken;
  IncLine, Last : Integer;
begin
  Result := '';
  Stop := ClassEnd(AMap, AClass.ClassTok);
  Last := AMap.LineCount;
  if Stop.Low <> '' then
    Last := Stop.Line;
  IncLine := IncludeInLines(AMap, AClass.ClassTok.Line, Last);
  if IncLine > 0 then
    Result := _(R_MN_INCLUDE, [IncLine]);
end;

// Die Deklaration an AHead: im Rumpf einer Klasse dieser Datei (AClass),
// lesbar (ADecl), geschrieben wie in der Meldung, kein Include im
// Klassenrumpf. AMany: sie traegt 'overload' oder ist nicht die einzige in
// Klassen dieses Namens - dann gilt AllHeadsPlan. '' oder der Grund.
function DeclReason(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const AName: string; out AClass: TRdxClassHead;
  out ADecl: TRdxRoutine; out AMany: Boolean): string;
var
  Spelled, ClsName, W : string;
begin
  ADecl := Default(TRdxRoutine);
  AMany := False;
  if not ClassAround(AMap, AHead, AClass) then
    Exit(_(R_MN_NO_CLASS, [AName]));
  if AClass.Vis = VIS_PUBLISHED then
    Exit(_(R_MN_PUBLISHED, [AName]));
  if TRdxBlocks.MethodDecl(AMap, AHead, ADecl) <> '' then
    Exit(_(R_MN_DECL, [AName]));
  Spelled := TokText(AMap, ADecl.NameTok);
  if Spelled <> AName then
    Exit(MsgStaleSuffix(_(R_MN_SPELLING, [Spelled, AName])));
  ClsName := TokText(AMap, AClass.NameTok);
  AMany := HasDirective(ADecl, [DIR_OVERLOAD], W)
    or (Length(TRdxBlocks.FindMethodDecls(AMap, ClsName, AName)) <> 1);
  Result := ClassIncludeReason(AMap, AClass);
end;

// Overload oder bedingte Zwillinge (rwE31 Stufe 3: jvcl JvGnugettext.pas:413
// 'dgettext' zweimal overload, einmal in {$ifndef UNICODE}; CEF4Delphi
// uCEFOLEDragAndDrop.pas:106 'dUnadvise' im {$IFNDEF FPC}-Zweig, der FPC-
// Zwilling schreibt schon 'DUnadvise'): eine reine Gross/klein-Aenderung
// muss keine Deklaration auswaehlen - sie trifft ALLE Deklarationen in
// Klassen namens AClass und ALLE Implementierungen 'AClass.Name' der Datei,
// Aufrufe binden weiter. Jede Deklaration steht in einer Klasse dieser
// Datei, nicht unter published, ohne Include im Klassenrumpf; mindestens
// eine Implementierung. Die Ersetzungen nur fuer Koepfe, die klein beginnen.
// '' oder der Grund.
function AllHeadsPlan(AMap: TRdxCodeMap; const AClass: TRdxClassHead;
  const AName: string; var APlan: TRdxMethodNamePlan): string;
var
  ClsName : string;
  Heads   : TArray<TRdxToken>;
  H, K, N : TRdxToken;
  C       : TRdxClassHead;
  D       : TRdxRoutine;
begin
  Result := '';
  ClsName := TokText(AMap, AClass.NameTok);
  Heads := TRdxBlocks.FindMethodDecls(AMap, ClsName, AName);
  for H in Heads do
  begin
    if not ClassAround(AMap, H, C) then
      Exit(_(R_MN_NO_CLASS, [AName]));
    if C.Vis = VIS_PUBLISHED then
      Exit(_(R_MN_PUBLISHED, [AName]));
    if TRdxBlocks.MethodDecl(AMap, H, D) <> '' then
      Exit(_(R_MN_DECL, [AName]));
    Result := ClassIncludeReason(AMap, C);
    if Result <> '' then
      Exit;
    if StartsLower(TokText(AMap, D.NameTok)) then
      AddEdit(APlan.Edits, CapEdit(AMap, D.NameTok));
  end;
  Heads := TRdxBlocks.FindMethodImpls(AMap, ClsName, AName);
  if Length(Heads) = 0 then
    Exit(_(R_MN_NO_IMPL, [ClsName, AName]));
  for K in Heads do
  begin
    N := K;
    if N.Low = KW_CLASS then
      N := After(AMap, N);
    N := NameAfter(AMap, N);
    if not SameIdent(N.Low, LowerCase(AName)) then
      Exit(_(R_MN_NO_IMPL, [ClsName, AName]));
    if StartsLower(TokText(AMap, N)) then
      AddEdit(APlan.Edits, CapEdit(AMap, N));
  end;
end;

// Die eine Implementierung 'AClassName.AName' hinter implementation (auch
// 'TOuter.TInner.AName', 'TFoo<T>.AName', 'class procedure'): das Token
// ihres Namens (letztes Glied) in AImpl. '' oder der Grund.
function ImplReason(AMap: TRdxCodeMap; const AClassName, AName: string;
  out AImpl: TRdxToken): string;
var
  Heads : TArray<TRdxToken>;
  K     : TRdxToken;
begin
  AImpl := Default(TRdxToken);
  Heads := TRdxBlocks.FindMethodImpls(AMap, AClassName, AName);
  if Length(Heads) = 0 then
    Exit(_(R_MN_NO_IMPL, [AClassName, AName]));
  if Length(Heads) > 1 then
    Exit(_(R_MN_IMPLS, [Length(Heads), AClassName, AName]));
  K := Heads[0];
  if K.Low = KW_CLASS then
    K := After(AMap, K);
  AImpl := NameAfter(AMap, K);
  if not SameIdent(AImpl.Low, LowerCase(AName)) then
    Exit(_(R_MN_NO_IMPL, [AClassName, AName]));
  Result := '';
end;

// Ist das Zeichen an AIndex von S ein Rand eines Worts im Fliesstext -
// Anfang/Ende, Leerraum, Anfuehrungszeichen bzw. (ABehind) ein Satzzeichen,
// ein Punkt nur am Ende oder vor Leerraum ('name.x' ist ein Pfad)?
function ProseEdge(const S: string; AIndex: Integer; ABehind: Boolean): Boolean;
begin
  if (AIndex < 1) or (AIndex > Length(S)) then
    Exit(True);
  if CharInSet(S[AIndex], [' ', #9, '"', '`']) then
    Exit(True);
  Result := ABehind and (CharInSet(S[AIndex], [',', ':', '!', '?'])
    or ((S[AIndex] = '.') and ((AIndex = Length(S))
        or CharInSet(S[AIndex + 1], [' ', #9]))));
end;

// Ein Wort der Sprache: nur a..z, mindestens zwei Zeichen ('is', 'and').
function IsLanguageWord(const AWord: string): Boolean;
var
  i : Integer;
begin
  Result := Length(AWord) >= 2;
  for i := 1 to Length(AWord) do
    if not CharInSet(AWord[i], ['a'..'z']) then
      Exit(False);
end;

// Ist AInner (Inhalt eines Literals) Fliesstext, der ALowName nur als Wort
// eines Satzes nennt (rwE31 Stufe 3: gexperts GX_ProofReaderDM.pas:312
// 'PrivateProofReader is nil in dmProofReader', doublecmd uoauth2auth.pas:
// 125 '.. in Safari and authorize Double Commander to access. ')? Mindestens
// drei Woerter, eines davon ein Wort der Sprache (IsLanguageWord, nicht der
// Name), und jedes Vorkommen des Namens als Wort steht zwischen Leerraum
// bzw. Satzzeichen (ProseEdge). Ein Skript ('begin doWork; end',
// 'obj.doWork()') oder eine Liste von Namen ('doA doB doC') ist kein
// Fliesstext - eine Suche per Name bleibt moeglich.
function IsProseFor(const AInner, ALowName: string): Boolean;
var
  Text, Low, W : string;
  i, P, E      : Integer;
  Words        : Integer;
  Language     : Boolean;
begin
  Result := False;
  // Die Woerter in der Schreibweise des Literals: 'Double' ist kein Wort
  // der Sprache, 'is' schon.
  Text := AInner + ' ';
  Words := 0;
  Language := False;
  W := '';
  for i := 1 to Length(Text) do
    if CharInSet(Text[i], [' ', #9]) then
    begin
      while (W <> '')
         and CharInSet(W[Length(W)], ['.', ',', ':', '!', '?']) do
        SetLength(W, Length(W) - 1);
      if W <> '' then
        Inc(Words);
      if (LowerCase(W) <> ALowName) and IsLanguageWord(W) then
        Language := True;
      W := '';
    end
    else
      W := W + Text[i];
  if (Words < 3) or not Language then Exit;
  Low := LowerCase(AInner);
  P := Pos(ALowName, Low);
  while P > 0 do
  begin
    E := P + Length(ALowName);
    // Teil eines laengeren Worts ('dmProofReaderX') zaehlt nicht.
    if not (((P > 1) and IsIdentChar(Low[P - 1]))
       or ((E <= Length(Low)) and IsIdentChar(Low[E]))) then
      if not (ProseEdge(Low, P - 1, False) and ProseEdge(Low, E, True)) then
        Exit;
    P := Pos(ALowName, Low, E);
  end;
  Result := True;
end;

// Nennt das String-Literal ALit (samt Quotes) ALowName als Wort - ausser
// als letztes Glied eines reinen Punktpfads ('Unit.TKlasse.name', nur
// Bezeichner und Punkte, mindestens zwei Glieder, der Name nur dort)?
// Solch ein Pfad ist eine Log- oder Diagnose-Kennung (rwE30 Stufe 2:
// Alcinoe.FMX.ScrollEngine.pas:1690 ALLog('Alcinoe.FMX.ScrollEngine.
// TALImpulseVelocityTrackerStrategy.getVelocity', ..), CEF4Delphi
// uCEFCookieVisitor.pas:189 CustomExceptionHandler('TCefCustomCookieVisitor.
// visit', e)), keine Suche per Name: RTTI, MethodAddress und Skripte fragen
// den blossen Namen; ein Ausdruck ('obj.name()') ist kein reiner Pfad.
// Ebenso nicht: der Name als Wort eines Satzes (IsProseFor, rwE31 Stufe 3).
function LiteralNames(const ALit, ALowName: string): Boolean;
var
  Inner : string;
  i     : Integer;
  Pure  : Boolean;
begin
  Result := HasIdentWord(LowerCase(ALit), ALowName);
  if not Result then Exit;
  Inner := ALit;
  if (Length(Inner) >= 2) and (Inner[1] = '''')
     and (Inner[Length(Inner)] = '''') then
    Inner := Copy(Inner, 2, Length(Inner) - 2);
  if IsProseFor(Inner, ALowName) then
    Exit(False);
  if (Inner = '') or (Pos('.', Inner) = 0) or not IsIdentStart(Inner[1]) then
    Exit;
  Pure := True;
  for i := 1 to Length(Inner) do
    if Inner[i] = '.' then
    begin
      if (i = Length(Inner)) or not IsIdentStart(Inner[i + 1]) then
        Pure := False;
    end
    else if not IsIdentChar(Inner[i]) then
      Pure := False;
  if Pure and SameIdent(LowerCase(LastPart(Inner)), ALowName)
     and not HasIdentWord(LowerCase(Copy(Inner, 1,
       LastDelimiter('.', Inner) - 1)), ALowName) then
    Result := False;
end;

// Die erste Zeile, auf der ein String-Literal ALowName (klein) als Wort
// nennt (LiteralNames); 0 ohne. Vorfilter je Zeile ueber HasWordNoCase
// (ohne Kopie der Zeile), dann je Lauf von String-Zeichen (Klasse 's' der
// Code-Sicht).
function LiteralLine(AMap: TRdxCodeMap; const ALowName: string): Integer;
var
  Li, Co, E : Integer;
  L         : string;
begin
  Result := 0;
  for Li := 1 to AMap.LineCount do
  begin
    L := AMap.Raw(Li);
    if not HasWordNoCase(L, ALowName) then Continue;
    Co := 1;
    while Co <= Length(L) do
    begin
      if AMap.ClassAt(Li, Co) = 's' then
      begin
        E := Co;
        while AMap.ClassAt(Li, E + 1) = 's' do
          Inc(E);
        if LiteralNames(Copy(L, Co, E - Co + 1), ALowName) then
          Exit(Li);
        Co := E + 1;
      end
      else
        Inc(Co);
    end;
  end;
end;

{ ---- Freie Routinen (rwE30 Stufe 2) ---- }

// Die Koepfe freier Routinen namens ALowName (je das Routinenwort): Name
// ohne Qualifizierung, ausserhalb jedes Typs (InsideTypeBody).
function FreeHeads(AMap: TRdxCodeMap; const ALowName: string): TArray<TRdxToken>;
var
  T, K : TRdxToken;
begin
  Result := nil;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALowName);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, ALowName) then
    begin
      K := Before(AMap, T);
      if IsRoutineHead(AMap, K) and SameTok(NameAfter(AMap, K), T)
         and (After(AMap, T).Low <> '.')
         and not InsideTypeBody(AMap, HeadStart(AMap, K)) then
        AddToken(Result, K);
    end;
    T := NextTokenOnLineWith(AMap, T, ALowName);
  end;
end;

// Das ';' auf Klammertiefe 0 ab T (T selbst eingeschlossen); Low = '' ohne.
function SemicolonFrom(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  Depth : Integer;
begin
  Result := T;
  Depth := 0;
  while Result.Low <> '' do
  begin
    if (Result.Low = '(') or (Result.Low = '[') then
      Inc(Depth)
    else if ((Result.Low = ')') or (Result.Low = ']')) and (Depth > 0) then
      Dec(Depth)
    else if (Depth = 0) and (Result.Low = ';') then
      Exit;
    Result := After(AMap, Result);
  end;
end;

// Die Direktiven hinter dem Kopf ab dem Routinenwort AKw (klein; '[' fuer
// FPC-Modifikatoren in eckigen Klammern). False, wenn der Kopf nicht bis zu
// seinem ';' zu lesen ist.
function FreeHeadDirectives(AMap: TRdxCodeMap; const AKw: TRdxToken;
  out AWords: TArray<string>): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  AWords := nil;
  Result := False;
  Depth := 0;
  P := AKw;
  T := After(AMap, AKw);
  while T.Low <> '' do
  begin
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Depth)
    else if ((T.Low = ')') or (T.Low = ']')) and (Depth > 0) then
      Dec(Depth)
    else if Depth = 0 then
    begin
      if T.Low = ';' then
        Break;
      if IsKeywordAfter(T, P) and InList(T.Low, FREE_HEAD_BREAKS) then
        Exit;
    end;
    P := T;
    T := After(AMap, T);
  end;
  if T.Low <> ';' then Exit;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if T.Low = '[' then
    begin
      AddText(AWords, '[');
      Break;
    end;
    if not (T.IsWord and InList(T.Low, FREE_DIRECTIVES)) then
      Break;
    AddText(AWords, T.Low);
    T := SemicolonFrom(AMap, After(AMap, T));
    if T.Low = '' then Exit;
    T := After(AMap, T);
  end;
  Result := True;
end;

// Die Zeile des Schluesselworts 'implementation'; 0 ohne (Programm).
function ImplementationLine(AMap: TRdxCodeMap): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'implementation');
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T.Line);
    T := NextTokenOnLineWith(AMap, T, 'implementation');
  end;
end;

// Was die Datei sonst ueber den Namen sagt: {$L}/{$LINK} (C-Code ruft beim
// genauen Namen), eine Direktive, die ihn nennt ({$EXTERNALSYM ..},
// {$HPPEMIT ..}), eine exports-Klausel mit ihm. '' oder der Grund.
function FreeFileReason(AMap: TRdxCodeMap; const ALowName,
  AName: string): string;
var
  Li, Co : Integer;
  Arg    : Boolean;
  T      : TRdxToken;
begin
  Result := '';
  for Li := 1 to AMap.LineCount do
  begin
    if Pos('$', AMap.Raw(Li)) = 0 then Continue;
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co) then
      begin
        if InList(DirectiveWord(AMap, Li, Co, Arg), LINK_WORDS) and Arg then
          Exit(_(R_MN_FREE_LINK, [Li, AName]));
        if HasIdentWord(LowerCase(DirectiveArgs(AMap, Li, Co)), ALowName) then
          Exit(_(R_MN_FREE_DIRECTIVE, [AName, Li]));
      end;
  end;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'exports');
  while T.Low <> '' do
  begin
    if (T.Low = 'exports') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      T := After(AMap, T);
      while (T.Low <> '') and (T.Low <> ';') do
      begin
        if SameIdent(T.Low, ALowName) then
          Exit(_(R_MN_FREE_EXPORTS, [AName, T.Line]));
        T := After(AMap, T);
      end;
    end;
    if T.Low = '' then Break;
    T := NextTokenOnLineWith(AMap, T, 'exports');
  end;
end;

// Die Form der Koepfe AHeads: einer (der Rumpf hinter implementation bzw.
// im Programm) oder zwei - Deklaration im interface-Teil bzw. forward, dann
// der Rumpf; keiner traegt eine bindende Direktive (FREE_BOUND, eine
// Aufrufkonvention im interface-Teil: FREE_CALLCONV). Mit 'overload' (rwE31
// Stufe 3: TES5Edit wbDataFormatNif.pas:3552, wbDataFormatNifTypes.pas:65,
// wbInterface.pas:9354): beliebig viele Koepfe - eine Gross/klein-Aenderung
// trifft alle gleich, Aufrufe binden weiter; jede Deklaration (interface-
// Teil, forward) braucht dann einen Rumpf in der Datei. '' oder der Grund.
function FreeHeadsReason(AMap: TRdxCodeMap; const AHeads: TArray<TRdxToken>;
  const AName: string): string;
var
  Words              : TArray<string>;
  W                  : string;
  i, Impl            : Integer;
  Decls, Bodies      : Integer;
  InIntf, Overloaded : Boolean;
  Forwards           : TArray<Boolean>;
begin
  Result := '';
  if Length(AHeads) = 0 then
    Exit(_(R_MN_FREE_HEADS, [Length(AHeads), AName]));
  Impl := ImplementationLine(AMap);
  SetLength(Forwards, Length(AHeads));
  Overloaded := False;
  Decls := 0;
  for i := 0 to High(AHeads) do
  begin
    if not FreeHeadDirectives(AMap, AHeads[i], Words) then
      Exit(_(R_MN_FREE_HEAD, [AName, AHeads[i].Line]));
    InIntf := (Impl > 0) and (AHeads[i].Line < Impl);
    for W in Words do
      if InList(W, FREE_BOUND) or (InIntf and InList(W, FREE_CALLCONV)) then
        Exit(_(R_MN_FREE_BOUND, [AName, W]));
    Forwards[i] := InList(WORD_FORWARD, Words);
    if InList(DIR_OVERLOAD, Words) then
      Overloaded := True;
    if Forwards[i] or InIntf then
      Inc(Decls);
  end;
  if Overloaded then
  begin
    Bodies := Length(AHeads) - Decls;
    if (Bodies = 0) or (Decls > Bodies) then
      Result := _(R_MN_FREE_PAIR, [AName]);
    Exit;
  end;
  if Length(AHeads) > 2 then
    Exit(_(R_MN_FREE_HEADS, [Length(AHeads), AName]));
  if Length(AHeads) = 1 then
  begin
    // Ein Kopf im interface-Teil ohne Rumpf hier (Include, external ...).
    if (Impl > 0) and (AHeads[0].Line < Impl) then
      Result := _(R_MN_FREE_PAIR, [AName]);
    Exit;
  end;
  if Forwards[1] or ((Impl > 0) and (AHeads[1].Line < Impl))
     or not (Forwards[0] or ((Impl > 0) and (AHeads[0].Line < Impl))) then
    Result := _(R_MN_FREE_PAIR, [AName]);
end;

// Ist AName im Stil einer C- oder Plattform-API geschrieben - mit '_'
// (lua_tocstring, hmac_update), ohne Grossbuchstaben (kdf3, dgettext) oder
// als k-Konstante (kFIRUserPropertySignUpMethod)? Solche freien Routinen
// spiegeln eine Fremd-API oder eine Namensfamilie (rwE30 Stufe 2: die KI
// hielt dort die Sperre fuer richtig); 'Lua_tocstring' waere ohnehin kein
// PascalCase.
function ApiStyleName(const AName: string): Boolean;
var
  i     : Integer;
  Upper : Boolean;
begin
  if Pos('_', AName) > 0 then
    Exit(True);
  if (Length(AName) >= 2) and (AName[1] = 'k')
     and CharInSet(AName[2], ['A'..'Z']) then
    Exit(True);
  Upper := False;
  for i := 1 to Length(AName) do
    if CharInSet(AName[i], ['A'..'Z']) then
      Upper := True;
  Result := not Upper;
end;

// SCA106 fuer eine freie Routine (rwE30 Stufe 2, 12 unnoetige Sperren: DCU32
// DAsmUtil.pas:43 'imPtr', op.pas:919 'readSRM', Double Commander
// dcstrutils.pas:250 'mbCompareStr', uluapas.pas:233 'luaMatchesMaskList'
// ...): Delphi und FPC binden auch freie Routinen ohne Gross/klein - jeder
// Aufruf, auch aus einer anderen Unit, und '@Name' binden nach der Hilfe
// unveraendert; RTTI und MethodAddress kennen keine freien Routinen. Den
// genauen Namen brauchen nur Linker und Bibliotheken: external/export/
// public/alias, C-Aufrufkonventionen, {$L}-Objektdateien, exports,
// Direktiven ({$EXTERNALSYM}) - das alles sperrt, ebenso ein String-
// Literal (LiteralLine), ein Kopf in einem Typ (record, Interface - dort
// R_MN_NO_CLASS wie bisher) und mehr als ein Paar Koepfe. Alle Koepfe
// bekommen die neue Schreibweise. '' oder der Grund.
function FreeRoutinePlan(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const AName: string; var APlan: TRdxMethodNamePlan): string;
var
  Heads    : TArray<TRdxToken>;
  NameTok  : TRdxToken;
  LowName  : string;
  Spelled  : string;
  i, Li    : Integer;
begin
  Result := '';
  if InsideTypeBody(AMap, AHead) then
    Exit(_(R_MN_NO_CLASS, [AName]));
  if ApiStyleName(AName) then
    Exit(_(R_MN_FREE_API, [AName]));
  LowName := LowerCase(AName);
  Heads := FreeHeads(AMap, LowName);
  Result := FreeHeadsReason(AMap, Heads, AName);
  if Result = '' then
    Result := FreeFileReason(AMap, LowName, AName);
  if Result <> '' then Exit;
  Li := LiteralLine(AMap, LowName);
  if Li > 0 then
    Exit(_(R_MN_LITERAL, [AName, Li]));
  Spelled := PascalName(AName);
  for i := 0 to High(Heads) do
  begin
    NameTok := NameAfter(AMap, Heads[i]);
    if TokText(AMap, NameTok) <> Spelled then
      AddEdit(APlan.Edits, SpellEdit(AMap, NameTok, Spelled));
  end;
  APlan.Name := Spelled;
end;

// Der Weg ueber die Deklaration an AHead (Kopf auf der Fundzeile bzw. die
// Deklaration zu einem gemeldeten Implementierungskopf): in einer Klasse
// dieser Datei Deklaration, Implementierung und Literal pruefen, dann beide
// Koepfe gross beginnen; ausserhalb jeder Klasse die freie Routine
// (FreeRoutinePlan). '' oder der Grund.
function DeclPathPlan(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const AName: string; var APlan: TRdxMethodNamePlan): string;
var
  C    : TRdxClassHead;
  D    : TRdxRoutine;
  Impl : TRdxToken;
  Li   : Integer;
  Many : Boolean;
begin
  if not ClassAround(AMap, AHead, C) then
    Exit(FreeRoutinePlan(AMap, AHead, AName, APlan));
  Result := DeclReason(AMap, AHead, AName, C, D, Many);
  if (Result = '') and not Many then
    Result := ImplReason(AMap, TokText(AMap, C.NameTok), AName, Impl);
  if Result = '' then
  begin
    Li := LiteralLine(AMap, LowerCase(AName));
    if Li > 0 then
      Result := _(R_MN_LITERAL, [AName, Li]);
  end;
  if Result <> '' then Exit;
  if Many then
    Exit(AllHeadsPlan(AMap, C, AName, APlan));
  AddEdit(APlan.Edits, CapEdit(AMap, D.NameTok));
  if StartsLower(TokText(AMap, Impl)) then
    AddEdit(APlan.Edits, CapEdit(AMap, Impl));
end;

// Nur der Implementierungskopf auf ALine ('procedure TFoo.doWork'), die
// Deklaration in der Klasse dieser Datei ist schon gross geschrieben: der
// Name der Implementierung bekommt die Schreibweise der Deklaration (EINE
// Ersetzung, APlan.Name = diese Schreibweise). Gesperrt ohne lesbaren Kopf
// oder ohne Deklaration (der bisherige Grund R_MN_IMPL_ONLY), bei mehr als
// einer Deklaration bzw. Implementierung, overload oder einer Deklaration,
// die selbst klein beginnt. '' oder der Grund.
function ImplSpellingPlan(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string; var APlan: TRdxMethodNamePlan): string;
var
  T, N      : TRdxToken;
  R, D      : TRdxRoutine;
  ClassPath : string;
  Spelled   : string;
  W         : string;
  Decls     : TArray<TRdxToken>;
  ImplCount : Integer;
  Found     : Boolean;
begin
  Result := _(R_MN_IMPL_ONLY, [AName]);
  Found := False;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) and not Found do
  begin
    if IsRoutineHead(AMap, T) then
    begin
      N := NameAfter(AMap, T);
      Found := SameIdent(N.Low, LowerCase(AName))
        and not SameTok(N, After(AMap, T));
    end;
    if not Found then
      T := After(AMap, T);
  end;
  if not Found or (TRdxBlocks.ReadRoutine(AMap, HeadStart(AMap, T), R) <> '')
     or (Pos('.', R.Name) = 0) then
    Exit;
  ClassPath := Copy(R.Name, 1, LastDelimiter('.', R.Name) - 1);
  Decls := TRdxBlocks.FindMethodDecls(AMap, ClassPath, AName);
  if Length(Decls) = 0 then
    Exit;
  if Length(Decls) > 1 then
    Exit(_(R_MN_DECLS, [Length(Decls), AName, LastPart(ClassPath)]));
  if TRdxBlocks.MethodDecl(AMap, Decls[0], D) <> '' then
    Exit(_(R_MN_DECL, [AName]));
  Spelled := TokText(AMap, D.NameTok);
  // Auch die Deklaration beginnt klein (rwE30 Stufe 2: cnwizards DCURecs.pas:
  // 7438 'visitUnitImpDef', skia4delphi System.Skia.pas:6204
  // 'compile_error_proc' - der Detektor meldete den Implementierungskopf,
  // der Grund nannte zweimal denselben Namen und vermutete einen veralteten
  // Fund; doublecmd fviewer.pas:4163 'cm_GotoLine' bekommt so den
  // richtigen Grund published): derselbe Weg wie ein Fund auf der
  // Deklaration - beide Koepfe gross.
  if Spelled = AName then
  begin
    APlan.Name := PascalName(AName);
    Exit(DeclPathPlan(AMap, Decls[0], AName, APlan));
  end;
  if StartsLower(Spelled) then
    Exit(MsgStaleSuffix(_(R_MN_SPELLING, [Spelled, AName])));
  if HasDirective(D, [DIR_OVERLOAD], W) then
    Exit(_(R_MN_OVERLOAD, [AName]));
  ImplCount := Length(TRdxBlocks.FindMethodImpls(AMap, ClassPath, AName));
  if ImplCount <> 1 then
    Exit(_(R_MN_IMPLS, [ImplCount, ClassPath, AName]));
  APlan.Name := Spelled;
  AddEdit(APlan.Edits, SpellEdit(AMap, R.NameTok, Spelled));
  Result := '';
end;

{ TRdxMethodNameFix }

class function TRdxMethodNameFix.Capitalize(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxMethodNamePlan;
  out AReason: string): Boolean;
var
  Name     : string;
  Head     : TRdxToken;
  ImplOnly : Boolean;
begin
  APlan := Default(TRdxMethodNamePlan);
  ImplOnly := False;
  Head := Default(TRdxToken);
  Name := MethodNameOf(AMessage);
  APlan.Name := PascalName(Name);
  if not StartsLower(Name) then
    AReason := _(R_MN_NO_NAME)
  else
    AReason := HeadOnLine(AMap, ALine, Name, Head, ImplOnly);
  // Nur die Implementierung gemeldet: ist die Deklaration schon gross,
  // gleicht die Hilfe die Implementierung an (rwE29).
  if ImplOnly then
  begin
    AReason := ImplSpellingPlan(AMap, ALine, Name, APlan);
    Exit(AReason = '');
  end;
  if AReason = '' then
    AReason := DeclPathPlan(AMap, Head, Name, APlan);
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

end.
