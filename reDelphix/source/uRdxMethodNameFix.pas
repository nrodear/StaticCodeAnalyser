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
// Deklaration (Klasse in einem Include) oder ist es eine freie Routine,
// meldet der Detektor den Kopf 'procedure TFoo.doWork' bzw. 'procedure
// doWork' - beides bekommt keine Hilfe. Den Kopf 'procedure TFoo.doWork'
// meldet er auch, wenn die Deklaration schon gross geschrieben ist
// ('procedure DoWork;' besteht die Pruefung, die Implementierung nicht):
// dann gleicht die Hilfe NUR den Implementierungskopf an die Schreibweise
// der Deklaration an (ImplSpellingPlan; Realwelt-Test rwE29, cnwizards
// DCURecs.pas:7864 'TDispPropDecl.visit' zu 'Visit') - der Laufzeit-Name
// kommt aus der Deklaration und bleibt.
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
//   - die Deklaration steht nicht im Rumpf einer Klasse dieser Datei:
//     freie Routine, record, Interface, Klasse in einem Include,
//   - sie steht unter 'published' (Methodentabelle, s. oben; der Abschnitt
//     ohne Wort - published in TPersistent-Erben, dort stehen die
//     Ereignis-Methoden der Formulare - bleibt eine Hilfe),
//   - 'overload' oder mehr als eine Deklaration in Klassen dieses Namens
//     ($IFDEF-Zwillinge, gleichnamige Klassen),
//   - keine oder mehr als eine Implementierung in der Datei (abstract,
//     external, Include, $IFDEF-Zwillinge),
//   - ein {$I}-Include im Klassenrumpf,
//   - ein String-Literal der Datei nennt den Namen (Aufruf per Name ueber
//     RTTI, MethodAddress, Skript - ein Vergleich dort kann Gross/klein
//     beachten).
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

// Die Deklaration an AHead: im Rumpf einer Klasse dieser Datei (AClass),
// lesbar (ADecl), geschrieben wie in der Meldung, ohne 'overload', die
// einzige in Klassen dieses Namens, kein Include im Klassenrumpf. '' oder
// der Grund.
function DeclReason(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const AName: string; out AClass: TRdxClassHead;
  out ADecl: TRdxRoutine): string;
var
  Spelled, ClsName, W : string;
  Decls               : TArray<TRdxToken>;
  Stop                : TRdxToken;
  IncLine, Last       : Integer;
begin
  ADecl := Default(TRdxRoutine);
  if not ClassAround(AMap, AHead, AClass) then
    Exit(_(R_MN_NO_CLASS, [AName]));
  if AClass.Vis = VIS_PUBLISHED then
    Exit(_(R_MN_PUBLISHED, [AName]));
  if TRdxBlocks.MethodDecl(AMap, AHead, ADecl) <> '' then
    Exit(_(R_MN_DECL, [AName]));
  Spelled := TokText(AMap, ADecl.NameTok);
  if Spelled <> AName then
    Exit(MsgStaleSuffix(_(R_MN_SPELLING, [Spelled, AName])));
  if HasDirective(ADecl, [DIR_OVERLOAD], W) then
    Exit(_(R_MN_OVERLOAD, [AName]));
  ClsName := TokText(AMap, AClass.NameTok);
  Decls := TRdxBlocks.FindMethodDecls(AMap, ClsName, AName);
  if Length(Decls) <> 1 then
    Exit(_(R_MN_DECLS, [Length(Decls), AName, ClsName]));
  Stop := ClassEnd(AMap, AClass.ClassTok);
  Last := AMap.LineCount;
  if Stop.Low <> '' then
    Last := Stop.Line;
  IncLine := IncludeInLines(AMap, AClass.ClassTok.Line, Last);
  if IncLine > 0 then
    Exit(_(R_MN_INCLUDE, [IncLine]));
  Result := '';
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

// Die erste Zeile, auf der ein String-Literal ALowName (klein) als Wort
// nennt; 0 ohne. Vorfilter je Zeile ueber HasWordNoCase (ohne Kopie der
// Zeile), dann je Lauf von String-Zeichen (Klasse 's' der Code-Sicht).
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
        if HasIdentWord(LowerCase(Copy(L, Co, E - Co + 1)), ALowName) then
          Exit(Li);
        Co := E + 1;
      end
      else
        Inc(Co);
    end;
  end;
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
  Name : string;
  Head : TRdxToken;
  Impl : TRdxToken;
  C    : TRdxClassHead;
  D    : TRdxRoutine;
  Li   : Integer;
  ImplOnly : Boolean;
begin
  APlan := Default(TRdxMethodNamePlan);
  ImplOnly := False;
  Head := Default(TRdxToken);
  Impl := Default(TRdxToken);
  C := Default(TRdxClassHead);
  D := Default(TRdxRoutine);
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
    AReason := DeclReason(AMap, Head, Name, C, D);
  if AReason = '' then
    AReason := ImplReason(AMap, TokText(AMap, C.NameTok), Name, Impl);
  if AReason = '' then
  begin
    Li := LiteralLine(AMap, LowerCase(Name));
    if Li > 0 then
      AReason := _(R_MN_LITERAL, [Name, Li]);
  end;
  if AReason = '' then
  begin
    AddEdit(APlan.Edits, CapEdit(AMap, D.NameTok));
    if StartsLower(TokText(AMap, Impl)) then
      AddEdit(APlan.Edits, CapEdit(AMap, Impl));
  end;
  Result := AReason = '';
end;

end.
