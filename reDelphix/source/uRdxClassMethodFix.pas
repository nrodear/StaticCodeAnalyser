unit uRdxClassMethodFix;

// reDelphix - Editorhilfe fuer SCA148 CanBeClassMethod, OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, "bedingt"): eine
// Methode ohne Bezug auf ihr Objekt wird statische Klassenmethode -
//   Deklaration:      'function Add(A, B: Integer): Integer;'
//                  -> 'class function Add(A, B: Integer): Integer; static;'
//   Implementierung:  'function TMath.Add(..'  -> 'class function TMath.Add(..'
// Eine statische Klassenmethode hat kein Self (Delphi wie FPC); Aufrufe
// 'Obj.Add(..)' und 'Add(..)' aus anderen Methoden der Klasse bleiben
// gueltig. Zwei Ersetzungen in EINEM Schritt (Deklaration, Kopf).
//
// WAS DER DETEKTOR MELDET (uCanBeClassMethod): je Implementierung
// 'TKlasse.Methode' mit Rumpf, die nicht schon 'class' und nicht polymorph
// ist (auch nicht ueber die Deklaration), kein Konstruktor/Destruktor und
// kein Ereignis-Handler (Sender), deren Rumpf weder 'Self', 'inherited',
// ein Feld nach der F-Konvention noch einen Member der Klasse (samt
// Vorfahren DIESER Datei) nennt. Gemeldet wird die Zeile des Kopfworts der
// Implementierung; die Meldung nennt 'Method TKlasse.Methode never accesses
// Self ...'. Er prueft keine Property-Accessoren, keine Methodenzeiger und
// keine Vorfahren ausserhalb der Datei - die Hilfe tut es, soweit der Text
// es beweist.
//
// BEDINGUNGEN (lieber keine Hilfe als eine falsche - ohne Typwissen nur, was
// am Text sicher ist):
//   * die Klasse steht in dieser Datei, genau einmal, nicht generisch, kein
//     Helper, und erbt NUR von TObject ('class' bzw. 'class(TObject)') -
//     dann kennt die Hilfe alle Member: die der Deklaration und die von
//     TObject. Damit implementiert sie auch kein Interface;
//   * die Methode ist eine procedure/function mit genau einer Deklaration
//     und einer Implementierung (kein overload), ohne virtual, dynamic,
//     abstract, override, reintroduce, message, final, dispid, static,
//     external, nicht published (auch nicht ohne Abschnitt unter {$M+}),
//     ohne Attribut, ohne asm-Rumpf;
//   * der Rumpf (samt lokaler Deklarationen und Routinen) nennt weder Self
//     noch inherited noch - unqualifiziert - einen Member der Klasse
//     (Feld, Property, Methode, Konstante) oder von TObject (Free,
//     ClassName ...); die Methode selbst (Rekursion) darf er nennen;
//   * die Klassendeklaration nennt den Methodennamen nur in seiner
//     Deklaration (sonst Property-Accessor) und traegt keine Direktive und
//     keinen geschachtelten Typ;
//   * in der Datei steht der Name sonst nur als Aufruf: mit '(' '.' '['
//     dahinter oder als ganze Anweisung - nie hinter '@', nicht als Wert
//     einer Zuweisung oder als Argument ohne Klammern (moeglicher
//     Methodenzeiger 'of object', der danach nicht mehr uebersetzt).
// GRENZE: andere Units sieht die Hilfe nicht - verwendet eine die Methode
// als Methodenzeiger, uebersetzt sie danach nicht mehr (der Hinweis der
// Tabelle sagt es).
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable - mit ZWEI
// Ersetzungen, darum nicht ueber MapFix (Integrationsnotiz).

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_CM_MESSAGE = 'class or method missing from the message';
  R_CM_NESTED_NAME = 'method of a nested type (%s)';
  R_CM_NO_HEAD = 'no header of the method %s';
  R_CM_MANY_HEADS = 'the line has more than one header of the method %s';
  R_CM_BOUNDS = 'the bounds of the method %s are not safe to read';
  R_CM_ALREADY = 'the method is already a class method';
  R_CM_KIND = '%s - only a procedure or function can become a class method';
  R_CM_ASM = 'assembler body - it can reach Self through a register';
  R_CM_NOT_IMPL = 'the header is not the one implementation of %s after '
    + '"implementation"';
  R_CM_IMPLS = '%d implementations of %s - overload?';
  R_CM_NO_CLASS = 'no class %s with a body in this file (record, other '
    + 'unit?)';
  R_CM_CLASSES = '%d classes named %s in this file';
  R_CM_GENERIC = 'the class is generic';
  R_CM_HELPER = 'the type is a class helper';
  R_CM_ATTR = 'attribute on the class or the method - RTTI could call the '
    + 'method on an object';
  R_CM_HERITAGE = 'the class has the ancestor list (%s) - only a direct '
    + 'descendant of TObject is checked';
  R_CM_CLASS_END = 'end of the class declaration not found';
  R_CM_CLASS_DIRECTIVE = 'compiler directive in the class declaration';
  R_CM_NESTED_TYPE = 'nested type in the class declaration';
  R_CM_DECLS = '%d declarations of %s in the class - overload?';
  R_CM_DECL_READ = 'the declaration of %s is not safe to read';
  R_CM_DECL_KIND = 'declaration and implementation of %s differ '
    + '(procedure/function)';
  R_CM_DIRECTIVE = 'directive "%s" on the declaration';
  R_CM_PUBLISHED = 'the method is published - the form designer can bind it '
    + 'to an event';
  R_CM_DEFAULT_VIS = 'the method stands before any visibility section and '
    + 'the file switches type information on ({$M+}) - it could be published';
  R_CM_IN_CLASS = '%s is named again in the class declaration (line %d) - '
    + 'property accessor?';
  R_CM_MEMBER = 'the body names %s (line %d) - Self, inherited or a member '
    + 'of the class or of TObject';
  R_CM_POINTER = '%s is used in line %d not as a call - possibly as a method '
    + 'pointer ("of object")';

type
  // Der Planer von SCA148. Form wie TRdxMapPlanner, aber mit ZWEI
  // Ersetzungen (Deklaration, Implementierungskopf).
  TRdxClassMethodFix = class
  public
    // ALine ist die Zeile des Kopfworts der Implementierung, AMessage die
    // Meldung ('Method TKlasse.Methode never accesses Self ...'). Liefert
    // die beiden Ersetzungen oder den Grund.
    class function MakeStatic(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdits: TArray<TRdxEdit>;
      out AReason: string): Boolean; static;
    // Der Methodenname aus der Meldung (Menuetext), '' ohne.
    class function MethodNameOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxBlocks,        // TRdxBlocks (Finder, ReadRoutine), TRdxRoutine
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_148 = 'sca148';
  KEY_METHOD = 'Method ';
  KEY_NEVER  = ' never accesses Self';
  KW_CLASS   = 'class';
  KW_STATIC  = ' static;';
  ANCESTOR_OK = 'tobject';
  // Nur diese Routinen werden Klassenmethoden.
  KINDS_OK: array[0..1] of string = ('procedure', 'function');
  // Direktiven der Deklaration, die die Hilfe sperren: Polymorphie,
  // Nachricht, schon statisch, extern, Overload-Geschwister.
  BLOCK_DIRECTIVES: array[0..10] of string = ('virtual', 'dynamic',
    'abstract', 'override', 'reintroduce', 'message', 'final', 'dispid',
    'static', 'external', 'overload');
  // Geschachtelte Typen im Klassenrumpf ('object' nur ohne 'of' davor).
  NESTED_WORDS: array[0..4] of string = ('record', 'object', 'interface',
    'dispinterface', 'type');
  // Vor einem Feld-, Variablen- oder Konstantennamen im Klassenrumpf.
  MEMBER_PREV: array[0..14] of string = (';', ',', 'var', 'const',
    'threadvar', 'private', 'protected', 'public', 'published', 'automated',
    ']', ')', 'class', 'sealed', 'abstract');
  // Hinter einem Namen, der deklariert wird.
  MEMBER_NEXT: array[0..2] of string = (':', ',', '=');
  // Die Member von TObject (Delphi und FPC) - unqualifiziert im Rumpf
  // hiesse jeder Self.X.
  TOBJECT_MEMBERS: array[0..31] of string = ('create', 'free', 'destroy',
    'disposeof', 'classname', 'classtype', 'classinfo', 'classparent',
    'classnameis', 'qualifiedclassname', 'unitname', 'unitscope',
    'instancesize', 'inheritsfrom', 'methodaddress', 'methodname',
    'fieldaddress', 'getinterface', 'getinterfaceentry', 'getinterfacetable',
    'safecallexception', 'afterconstruction', 'beforedestruction',
    'dispatch', 'defaulthandler', 'newinstance', 'freeinstance',
    'cleanupinstance', 'initinstance', 'tostring', 'equals', 'gethashcode');
  // Hier endet ein Bezeichner, der ein Methodenzeiger sein KANN (kein
  // Aufruf mit Klammern davor).
  POINTER_ENDS: array[0..8] of string = (';', ')', ',', ']', 'end', 'else',
    'until', 'except', 'finally');
  // Hinter diesen Woertern ist der Name ein Aufruf.
  CALL_NEXT: array[0..2] of string = ('(', '.', '[');
  // Direktiven, die Typinformation (published) einschalten koennen.
  TYPEINFO_WORDS: array[0..2] of string = ('m', 'typeinfo', 'methodinfo');

type
  // Was der Planer ueber die Methode weiss.
  TRdxCmCtx = record
    Full     : string;            // 'TMath.Add' wie in der Meldung
    Cls      : string;            // 'TMath'
    Meth     : string;            // 'Add'
    LowCls   : string;
    LowMeth  : string;
    Impl     : TRdxRoutine;       // die Implementierung
    Decl     : TRdxRoutine;       // die Deklaration im Klassenrumpf
    ClassTok : TRdxToken;         // 'class' des Klassenkopfs
    ClassEnd : TRdxToken;         // das end des Klassenrumpfs
    Members  : TArray<string>;    // Member der Klasse, klein
  end;

// 'TMath.Add' aus der Meldung; '' ohne diese Form.
function FullNameOf(const AMessage: string): string;
var
  E : Integer;
begin
  Result := '';
  E := Pos(KEY_NEVER, AMessage);
  if (Pos(KEY_METHOD, AMessage) = 1) and (E > Length(KEY_METHOD) + 1) then
    Result := Trim(Copy(AMessage, Length(KEY_METHOD) + 1,
      E - Length(KEY_METHOD) - 1));
end;

// Klasse und Methode aus der Meldung. '' oder der Grund.
function MessageReason(const AMessage: string; var C: TRdxCmCtx): string;
var
  P : Integer;
begin
  C.Full := FullNameOf(AMessage);
  P := Pos('.', C.Full);
  if (P <= 1) or (P = Length(C.Full)) then
    Exit(_(R_CM_MESSAGE));
  C.Cls := Copy(C.Full, 1, P - 1);
  C.Meth := Copy(C.Full, P + 1, MaxInt);
  if Pos('.', C.Meth) > 0 then
    Exit(_(R_CM_NESTED_NAME, [C.Full]));
  C.LowCls := LowerCase(C.Cls);
  C.LowMeth := LowerCase(C.Meth);
  Result := '';
end;

// Ein Name aus AList (klein)? Vergleich wie SameIdent.
function NamedIn(const ALow: string; const AList: TArray<string>): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AList do
    if SameIdent(ALow, S) then
      Exit(True);
end;

{ ---- Die Implementierung ---- }

// Der eine Kopf 'TKlasse.' auf ALine, gelesen bis zum Ende der Routine;
// die eine Implementierung der Methode hinter implementation. '' oder der
// Grund.
function ImplReason(AMap: TRdxCodeMap; ALine: Integer;
  var C: TRdxCmCtx): string;
var
  T, Hit : TRdxToken;
  n      : Integer;
  W      : string;
  Heads  : TArray<TRdxToken>;
begin
  n := 0;
  Hit := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsHeadNamed(AMap, T, C.LowCls) then
    begin
      Inc(n);
      Hit := T;
    end;
    T := After(AMap, T);
  end;
  if n = 0 then
    Exit(MsgMovedSuffix(_(R_CM_NO_HEAD, [C.Full])));
  if n > 1 then
    Exit(_(R_CM_MANY_HEADS, [C.Full]));
  if TRdxBlocks.ReadRoutine(AMap, HeadStart(AMap, Hit), C.Impl) <> '' then
    Exit(_(R_CM_BOUNDS, [C.Full]));
  if (Length(C.Impl.Parts) <> 2) or not SameIdent(C.Impl.Parts[0], C.LowCls)
     or not SameIdent(C.Impl.Parts[1], C.LowMeth) then
    Exit(MsgMovedSuffix(_(R_CM_NO_HEAD, [C.Full])));
  if C.Impl.Head.Low = KW_CLASS then
    Exit(MsgStaleSuffix(_(R_CM_ALREADY)));
  if not InList(C.Impl.Keyword.Low, KINDS_OK) then
    Exit(_(R_CM_KIND, [C.Impl.Keyword.Low]));
  if C.Impl.Body.Low = '' then
    Exit(_(R_CM_BOUNDS, [C.Full]));
  if (C.Impl.Body.Low = 'asm') or HasDirective(C.Impl, ['assembler'], W) then
    Exit(_(R_CM_ASM));
  Heads := TRdxBlocks.FindMethodImpls(AMap, C.Cls, C.Meth);
  if Length(Heads) > 1 then
    Exit(_(R_CM_IMPLS, [Length(Heads), C.Meth]));
  if (Length(Heads) = 0) or not SameTok(Heads[0], C.Impl.Head) then
    Exit(_(R_CM_NOT_IMPL, [C.Full]));
  Result := '';
end;

{ ---- Die Klasse ---- }

// Der eine Klassenkopf: nicht generisch, kein Helper, kein Attribut, nur
// TObject als Vorfahr, mit Ende und ohne Direktive. '' oder der Grund.
function ClassReason(AMap: TRdxCodeMap; var C: TRdxCmCtx): string;
var
  Heads    : TArray<TRdxToken>;
  Eq, Name : TRdxToken;
  N        : TRdxToken;
  Names    : TArray<string>;
begin
  Heads := TRdxBlocks.FindClassHeads(AMap, C.Cls);
  if Length(Heads) = 0 then
    Exit(_(R_CM_NO_CLASS, [C.Cls]));
  if Length(Heads) > 1 then
    Exit(_(R_CM_CLASSES, [Length(Heads), C.Cls]));
  C.ClassTok := Heads[0];
  Eq := Before(AMap, C.ClassTok);
  if Eq.Low = 'packed' then
    Eq := Before(AMap, Eq);
  Name := Before(AMap, Eq);
  if Name.Low = '>' then
    Exit(_(R_CM_GENERIC));
  if Before(AMap, Name).Low = ']' then
    Exit(_(R_CM_ATTR));
  N := After(AMap, C.ClassTok);
  while InList(N.Low, CLASS_MODIFIERS) do
    N := After(AMap, N);
  if N.Low = 'helper' then
    Exit(_(R_CM_HELPER));
  Names := TRdxBlocks.HeritageOf(AMap, C.ClassTok);
  if (Length(Names) > 1)
     or ((Length(Names) = 1) and (LowerCase(Names[0]) <> ANCESTOR_OK)) then
    Exit(_(R_CM_HERITAGE, [JoinStrings(Names, ', ')]));
  C.ClassEnd := ClassEnd(AMap, C.ClassTok);
  if C.ClassEnd.Low = '' then
    Exit(_(R_CM_CLASS_END));
  if DirectiveInLines(AMap, C.ClassTok.Line, C.ClassEnd.Line) then
    Exit(_(R_CM_CLASS_DIRECTIVE));
  Result := '';
end;

// Schaltet eine Direktive der Datei Typinformation ein ({$M+},
// {$TYPEINFO ON}, {$METHODINFO ON})? Jede Stellung zaehlt - eine Sperre zu
// viel, nie eine zu wenig.
function TypeInfoSwitched(AMap: TRdxCodeMap): Boolean;
var
  Li, Co : Integer;
  Arg    : Boolean;
begin
  Result := False;
  for Li := 1 to AMap.LineCount do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if OpensDirective(AMap, Li, Co)
         and InList(DirectiveWord(AMap, Li, Co, Arg), TYPEINFO_WORDS) then
        Exit(True);
end;

// Die eine Deklaration im Klassenrumpf: Art wie die Implementierung, keine
// sperrende Direktive, nicht published, kein Attribut. '' oder der Grund.
function DeclReason(AMap: TRdxCodeMap; var C: TRdxCmCtx): string;
var
  Heads : TArray<TRdxToken>;
  W     : string;
  Head  : TRdxClassHead;
begin
  Heads := TRdxBlocks.MemberHeads(AMap, C.ClassTok, C.Meth);
  if Length(Heads) <> 1 then
    Exit(_(R_CM_DECLS, [Length(Heads), C.Meth]));
  if TRdxBlocks.MethodDecl(AMap, Heads[0], C.Decl) <> '' then
    Exit(_(R_CM_DECL_READ, [C.Meth]));
  if C.Decl.Head.Low = KW_CLASS then
    Exit(MsgStaleSuffix(_(R_CM_ALREADY)));
  if C.Decl.Keyword.Low <> C.Impl.Keyword.Low then
    Exit(_(R_CM_DECL_KIND, [C.Meth]));
  if HasDirective(C.Decl, BLOCK_DIRECTIVES, W) then
    Exit(_(R_CM_DIRECTIVE, [W]));
  if Before(AMap, C.Decl.Head).Low = ']' then
    Exit(_(R_CM_ATTR));
  if not EnclosingClass(AMap, C.Decl.Head, C.LowCls, Head) then
    Exit(_(R_CM_DECL_READ, [C.Meth]));
  if Head.Vis = 'published' then
    Exit(_(R_CM_PUBLISHED));
  if (Head.Vis = '') and TypeInfoSwitched(AMap) then
    Exit(_(R_CM_DEFAULT_VIS));
  Result := '';
end;

// Der Klassenrumpf: kein geschachtelter Typ, der Methodenname nur in seiner
// Deklaration; die Member nach C.Members. '' oder der Grund.
function ClassBodyReason(AMap: TRdxCodeMap; var C: TRdxCmCtx): string;
var
  T, P, N : TRdxToken;
  Depth   : Integer;
begin
  C.Members := nil;
  Depth := 0;
  P := C.ClassTok;
  T := After(AMap, C.ClassTok);
  while (T.Low <> '') and not SameTok(T, C.ClassEnd) do
  begin
    if IsKeywordAfter(T, P)
       and ((InList(T.Low, NESTED_WORDS) and not ((T.Low = 'object') and (P.Low = 'of')))
            or ((T.Low = KW_CLASS) and (P.Low = '='))) then
      Exit(_(R_CM_NESTED_TYPE));
    if T.IsWord and SameIdent(T.Low, C.LowMeth)
       and not SameTok(T, C.Decl.NameTok) then
      Exit(_(R_CM_IN_CLASS, [TokText(AMap, T), T.Line]));
    if Depth = 0 then
    begin
      N := After(AMap, T);
      if IsRoutineHead(AMap, T)
         or ((T.Low = 'property') and IsKeywordAfter(T, P)) then
      begin
        if N.IsWord then
          AddText(C.Members, N.Low);
      end
      else if T.IsWord and InList(P.Low, MEMBER_PREV)
         and InList(N.Low, MEMBER_NEXT) then
        AddText(C.Members, T.Low);
    end;
    Inc(Depth, ParenDelta(T));
    P := T;
    T := After(AMap, T);
  end;
  Result := '';
end;

{ ---- Der Rumpf und die Verwendungen ---- }

// Der Rumpf der Implementierung (hinter dem Kopf bis zum letzten ';'):
// kein Self, kein inherited, kein unqualifizierter Member der Klasse oder
// von TObject - die Methode selbst ausgenommen. '' oder der Grund.
function BodyReason(AMap: TRdxCodeMap; const C: TRdxCmCtx): string;
var
  T : TRdxToken;
begin
  Result := '';
  T := After(AMap, C.Impl.HeaderEnd);
  while (T.Low <> '') and not SameTok(T, C.Impl.Last) do
  begin
    if T.IsWord and (Before(AMap, T).Low <> '.')
       and ((T.Low = 'self') or (T.Low = 'inherited')
            or InList(T.Low, TOBJECT_MEMBERS)
            or (NamedIn(T.Low, C.Members) and not SameIdent(T.Low, C.LowMeth))) then
      Exit(_(R_CM_MEMBER, [TokText(AMap, T), T.Line]));
    T := After(AMap, T);
  end;
end;

// Der Anfang der Kette 'A.B.Name' um T (T selbst ohne Kette).
function ChainStart(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  Dot, Prev : TRdxToken;
begin
  Result := T;
  Dot := Before(AMap, Result);
  while Dot.Low = '.' do
  begin
    Prev := Before(AMap, Dot);
    if not Prev.IsWord then
      Break;
    Result := Prev;
    Dot := Before(AMap, Result);
  end;
end;

// Steht T (Token davor AQ) am Anfang einer Anweisung?
function AtStatementStart(AMap: TRdxCodeMap; const AQ: TRdxToken): Boolean;
begin
  Result := InList(AQ.Low, STATEMENT_PREV)
    and (not AQ.IsWord or IsKeywordAfter(AQ, Before(AMap, AQ)));
end;

// Jedes andere Vorkommen des Namens in der Datei ist ein Aufruf: '(' '.'
// '[' dahinter oder eine ganze Anweisung; Koepfe gleichnamiger Routinen
// anderer Klassen und Properties zaehlen nicht. Nie hinter '@'. '' oder
// der Grund.
function UsesReason(AMap: TRdxCodeMap; const C: TRdxCmCtx): string;
var
  T, Q, N : TRdxToken;
begin
  Result := '';
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if T.IsWord and SameIdent(T.Low, C.LowMeth)
       and not SameTok(T, C.Decl.NameTok) and not SameTok(T, C.Impl.NameTok) then
    begin
      Q := Before(AMap, ChainStart(AMap, T));
      N := After(AMap, T);
      if Q.Low = '@' then
        Exit(_(R_CM_POINTER, [TokText(AMap, T), T.Line]));
      if not (IsRoutineHead(AMap, Q) or (Q.Low = 'property')
              or InList(N.Low, CALL_NEXT)
              or not InList(N.Low, POINTER_ENDS)
              or AtStatementStart(AMap, Q)) then
        Exit(_(R_CM_POINTER, [TokText(AMap, T), T.Line]));
    end;
    T := After(AMap, T);
  end;
end;

// Die beiden Ersetzungen: die Deklaration vom Kopfwort bis zu ihrem ';'
// bekommt 'class ' davor und ' static;' dahinter, das Kopfwort der
// Implementierung 'class ' davor.
function BuildEdits(AMap: TRdxCodeMap; const C: TRdxCmCtx): TArray<TRdxEdit>;
var
  E : TRdxEdit;
begin
  Result := nil;
  E := Default(TRdxEdit);
  E.Span := TRefactorSpan.Make(SPAN_148, C.Decl.Keyword.Line,
    C.Decl.Keyword.Col, C.Decl.HeaderEnd.Line, C.Decl.HeaderEnd.EndCol);
  E.Expected := RangeText(AMap, E.Span);
  E.NewText := KW_CLASS + ' ' + E.Expected + KW_STATIC;
  AddEdit(Result, E);
  E := Default(TRdxEdit);
  E.Span := TRefactorSpan.Make(SPAN_148, C.Impl.Keyword.Line,
    C.Impl.Keyword.Col, C.Impl.Keyword.Line, C.Impl.Keyword.EndCol);
  E.Expected := RangeText(AMap, E.Span);
  E.NewText := KW_CLASS + ' ' + E.Expected;
  AddEdit(Result, E);
end;

{ TRdxClassMethodFix }

class function TRdxClassMethodFix.MakeStatic(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  C : TRdxCmCtx;
begin
  AEdits := nil;
  C := Default(TRdxCmCtx);
  AReason := MessageReason(AMessage, C);
  if AReason = '' then
    AReason := ImplReason(AMap, ALine, C);
  if AReason = '' then
    AReason := ClassReason(AMap, C);
  if AReason = '' then
    AReason := DeclReason(AMap, C);
  if AReason = '' then
    AReason := ClassBodyReason(AMap, C);
  if AReason = '' then
    AReason := BodyReason(AMap, C);
  if AReason = '' then
    AReason := UsesReason(AMap, C);
  if AReason = '' then
    AEdits := BuildEdits(AMap, C);
  Result := AReason = '';
end;

class function TRdxClassMethodFix.MethodNameOf(const AMessage: string): string;
begin
  Result := LastPart(FullNameOf(AMessage));
end;

end.
