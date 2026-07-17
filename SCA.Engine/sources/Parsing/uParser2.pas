unit uParser2;

// Rekursiver Abstiegs-Parser für Delphi-Quelltexte.
// Erzeugt einen TAstNode-Baum (uAstNode) aus einem Token-Stream (uLexer).
// Unbekannte Konstrukte werden übersprungen – kein unkontrollierter Absturz.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uLexer;

type
  TParser2 = class
  public
    constructor Create;
    // Lädt Datei, parst und gibt Root-Node (nkUnit) zurück.
    function ParseFile(const FileName: string): TAstNode;
    // Parst einen String direkt.
    function ParseSource(const Source: string): TAstNode;
  private
    FLex      : TLexer;
    FNextCount: Integer; // Watchdog: max. Token-Aufrufe pro Datei

    // IFDEF-Body-Recovery (2026-07-04, blcksock-Muster): Kontext fuer
    // Methoden-Header, die MITTEN in einem offenen Methoden-Body auftauchen
    // (zwei begin, ein end durch {$IFDEF}/{$ELSE}-Twin-Bodies). FImplNode
    // ist der aktuelle nkImplementation-Knoten - Ziel-Parent fuer die auf
    // Unit-Ebene recoverten Methoden. FResume* transportieren den von
    // ParseStatement bereits konsumierten Header-Prefix (Keyword + erster
    // Namens-Ident) zu ParseMethodSignature, das dort nahtlos ab dem '.'
    // weiterparst (der Lexer hat nur 1-Token-Peek, ein Multi-Lookahead
    // ohne Konsum ist nicht moeglich).
    FImplNode            : TAstNode;
    FResumeHeaderPending : Boolean;
    FResumeKwTok         : TToken;
    FResumeName1         : string;

    // ---- Lexer-Hilfsmethoden ----
    function  Tok: TToken;
    function  Next: TToken;
    function  Eat(K: TTokenKind): Boolean;
    procedure SkipTo(const Stops: array of TTokenKind);
    procedure SkipToSemicolon;
    procedure SkipBalanced;
    // Forward-Progress-Garantie: erzwingt einen Token-Konsum wenn seit
    // StartCount keine Bewegung war. Schuetzt Outer-Loops vor Endlos-Loops
    // wenn ein Sub-Parser keinen Token konsumiert hat.
    procedure GuardAdvance(StartCount: Integer);
    // Boundary-Recovery-Praedikat ({$ifdef}-Straddle-Merge, 2026-07-16):
    // True wenn Tok ein TOP-LEVEL-Routine-Header ist (Spalte 1). Im
    // Statement-Kontext ist das illegales Delphi -> der umgebende Block/Frame
    // wurde nie geschlossen. Alle Statement-Loops (ParseBlock/Case/Repeat/Try)
    // nutzen es als zusaetzliche Abbruch-Bedingung, damit die Recovery auch
    // durch offene try/case/repeat-Frames nach oben unwinden kann.
    function AtTopLevelRoutineHead: Boolean;
    // Konsumiert optionale Generic-Parameter `<...>` einschliesslich nested
    // Klammern (z.B. `<TList<TFoo>>`). Falls Tok nicht `<` ist: no-op.
    // Wird nach Typname (in ParseTypeSection) und nach Methodenname (in
    // ParseMethodSignature) gerufen, sodass Generics nicht den
    // nachfolgenden `=` bzw. `(` verschlucken.
    procedure SkipGenericParams;
    // Konsumiert die optionale Praeambel `helper for <type>` nach
    // `record` oder `class` in einer Typ-Deklaration.
    procedure SkipHelperFor;

    // ---- Grammatik-Regeln ----
    procedure ParseUnit(Root: TAstNode);
    procedure ParseInterfaceSection(Parent: TAstNode);
    procedure ParseImplementationSection(Parent: TAstNode);
    procedure ParseUses(Parent: TAstNode);
    procedure ParseTypeSection(Parent: TAstNode);
    procedure ParseVarLikeSection(Parent: TAstNode; AKind: TNodeKind);
    procedure ParseClassBody(ClassNode: TAstNode);
    procedure ParseMethodSignature(Parent: TAstNode);
    procedure ParseMethodDirectives(MNode: TAstNode = nil);
    procedure ParseMethodImpl(Parent: TAstNode);
    procedure ParseLocalVarSection(Parent: TAstNode);
    procedure ParseBlock(Parent: TAstNode);
    procedure ParseStatement(Parent: TAstNode);
    procedure ParseIfStmt(Parent: TAstNode);
    procedure ParseCaseStmt(Parent: TAstNode);
    procedure ParseForStmt(Parent: TAstNode);
    procedure ParseWhileStmt(Parent: TAstNode);
    procedure ParseRepeatStmt(Parent: TAstNode);
    procedure ParseTryStmt(Parent: TAstNode);
    procedure ParseRaiseStmt(Parent: TAstNode);
    procedure ParseInlineVarStmt(Parent: TAstNode);
    procedure ParseCallOrAssign(Parent: TAstNode);
    function  ParsePrimary: string;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeStrictPrivate, CaseStatementSize, CommentedOutCode, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DeepNesting, DuplicateBlock, ExceptionTooGeneral, ExceptOnException, GodClass, GroupedDeclaration, IfElseBegin, LargeClass, LongMethod, NestedTry, NilComparison, RaisingRawException, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses
// Token-Concat-Pattern fuer Identifier/TypeRef-Strings im AST-Build. Strings
// sind kurz (qualified name: max ~5 Dots, type-param-list ~5 Idents);
// Format()/TStringBuilder wuerden hier Overhead ohne Gewinn bringen.
// GodClass/LargeClass: Parser ist ein einziger Top-Down-Walker pro Datei,
// Method-pro-Statement-Kind = unvermeidbarer Fan-Out (~80 Parse-Methoden).

{ Methoden-Direktiven nach dem Semikolon }
function IsMethodDirective(K: TTokenKind): Boolean;
begin
  Result := K in [tkKwOverride, tkKwVirtual, tkKwAbstract, tkKwOverload,
                  tkKwReintroduce, tkKwForward, tkKwDeprecated, tkKwStatic,
                  tkKwInline, tkKwExternal, tkKwRead, tkKwWrite];
end;

// Calling-Conventions und andere Direktiven die als tkIdent geparst werden:
// 'stdcall', 'cdecl', 'register', 'pascal', 'safecall', 'winapi', 'export',
// 'varargs', 'assembler', plus User-/Lib-Conventions wie 'dcpcall' (DC-
// plugin) und 'mwpascal' (mORMot). Wenn diese nicht skipped werden,
// schlaegt ParseMethodImpl nach der Signatur fehl: Tok zeigt auf den
// Calling-Convention-Identifier, ParseLocalVarSection findet kein
// var/const/type, ParseBlock erwartet 'begin', also wird die Method-Body
// gar nicht geparst (sichtbar als Headless-Method-Pattern: nkMethod ohne
// nkBlock-Child, base64func.OpenArchiveW war der Audit-Trigger).
function IsMethodDirectiveIdent(const Value: string): Boolean;
const
  // 'noreturn' (Delphi 12) ist KEINE Calling-Convention, wird aber wie eine als
  // tkIdent geparst und MUSS hier stehen: sonst bleibt Tok auf 'noreturn' haengen
  // und die Routine wird headless (Body fehlt komplett im AST - genau das oben
  // beschriebene Muster). Real-World-Trigger: Alcinoe.JSONDoc
  // 'procedure AlJSONDocErrorA(const Msg: String); noreturn;' - deren `raise`
  // war unsichtbar, was u.a. SCA121-FPs bei den Aufrufern erzeugte.
  KnownConventions: array[0..15] of string = (
    'stdcall',  'cdecl',     'register',  'pascal',    'safecall',
    'winapi',   'delphicall','mwpascal',  'dcpcall',   'export',
    'varargs',  'assembler', 'local',     'far',       'near',
    'noreturn'
  );
var
  Lower : string;
  i     : Integer;
begin
  Result := False;
  Lower  := LowerCase(Value);
  for i := Low(KnownConventions) to High(KnownConventions) do
    if Lower = KnownConventions[i] then Exit(True);
end;

function IsMethodDirectiveTok(const T: TToken): Boolean;
begin
  if IsMethodDirective(T.Kind) then Exit(True);
  if T.Kind = tkIdent then Exit(IsMethodDirectiveIdent(T.Value));
  Result := False;
end;

// True wenn C ein Identifier-Zeichen ist (Buchstabe/Ziffer/Underscore).
// Lokaler Helper - der Parser haengt nicht von uDetectorUtils ab.
function ParserIsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Append-mit-Trennzeichen: fuegt Tok an FullRHS an. Wenn beide Seiten
// (letztes Zeichen von FullRHS, erstes Zeichen von Tok) Identifier-
// Zeichen sind, wird ein Space dazwischen gesetzt - sonst wuerden zwei
// Idents/Keywords zu einem zusammenkleben (z.B. '100 div 0' -> '100div0',
// 'list as IFoo' -> 'listasifoo'). Operatoren ('.', '+', '(' etc.) sind
// nicht-Ident, brauchen keinen Separator.
//
// Wichtig: Detektoren wie uDivByZero / uSQLInjection / uFormatMismatch
// pruefen via Pos(' div ', ...) / Pos(' as ', ...) auf den
// konkatenierten RHS-String. Ohne Separator schlagen alle diese Checks
// fehl. Vorher: ~25 Tests rot, nach Einfuehrung dieses Joiners gehen
// alle reine Whitespace-abhaengigen Detektoren wieder gruen.
procedure JoinTokInto(var FullRHS: string; const Tok: string); inline;
begin
  if (FullRHS <> '') and (Tok <> '') and
     ParserIsIdentChar(FullRHS[Length(FullRHS)]) and
     ParserIsIdentChar(Tok[1]) then
    FullRHS := FullRHS + ' ';
  FullRHS := FullRHS + Tok;
end;

function QuoteStrLit(const Value: string): string;
// Re-konstruiert die Pascal-Source-Form eines Stringliterals:
// outer '...' plus internal ' wieder verdoppelt.
//
// Hintergrund: TLexer.ReadString resolved schon waehrend des Lexings
// das `''`-Escape zu einem einzelnen `'` im Token-Value (Z. 329-330 in
// uLexer.pas). Wenn wir den Wert jetzt nur mit '...' umwickeln, wird
// jeder eingebettete `'` von Detektoren als Stringende interpretiert
// (z.B. uFormatMismatch verlor den `%s`-Platzhalter in
// `Format('foo ''bar'' baz: %s', [x])` weil das `'` direkt nach `foo `
// als closing quote gewertet wurde -> 0 Platzhalter, 1 Argument =
// False-Positive).
begin
  if Pos('''', Value) = 0 then
    Result := '''' + Value + ''''
  else
    Result := '''' + StringReplace(Value, '''', '''''', [rfReplaceAll]) + '''';
end;

constructor TParser2.Create;
begin
  inherited;
end;

function TParser2.ParseFile(const FileName: string): TAstNode;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(FileName);
    except
      try SL.LoadFromFile(FileName, TEncoding.UTF8);
      except
        try SL.LoadFromFile(FileName, TEncoding.Unicode);
        except
          try SL.LoadFromFile(FileName, TEncoding.GetEncoding(1252));
          except
            raise Exception.CreateFmt('Datei nicht lesbar: %s', [FileName]);
          end;
        end;
      end;
    end;
    Result      := ParseSource(SL.Text);
    Result.Name := FileName;
  finally
    SL.Free;
  end;
end;

function TParser2.ParseSource(const Source: string): TAstNode;
var
  Root: TAstNode;
begin
  Root := nil;
  FLex := TLexer.Create(Source);
  // A.5 Phase 1b-Wiring: globale CLI-Config auf den Lexer anwenden.
  // Wenn gLexerIfdefSkipEnabled gesetzt ist (via --ifdef-aware-Flag),
  // werden die globalen Defines uebernommen und Skip aktiviert.
  if gLexerIfdefSkipEnabled then
  begin
    if gLexerIfdefDefines <> nil then
      for var i := 0 to gLexerIfdefDefines.Count - 1 do
        FLex.AddDefine(gLexerIfdefDefines[i]);
    FLex.EnableConditionalSkipping;
  end;
  try
    FNextCount := 0; // Watchdog pro Datei zuruecksetzen
    // Recovery-Zustand pro Datei zuruecksetzen (2026-07-04): ein Parser-
    // Objekt kann mehrere Dateien nacheinander parsen; Reste einer
    // abgebrochenen Recovery duerfen nicht in die naechste Datei lecken.
    FImplNode            := nil;
    FResumeHeaderPending := False;
    FResumeName1         := '';
    Root := TAstNode.Create(nkUnit, '', 1, 1);
    try
      ParseUnit(Root);
      // Welle 2 (Core-Detektoren-Architektur): DEBUG-guarded {$IFDEF}-Quell-Ranges
      // als additive nkConditionalRange-Marker am Unit-Node ablegen (Line=Start,
      // TypeRef=EndLine). Rein additiv - nur opt-in-Detektoren (SCA017) lesen sie;
      // A/B byte-identisch bis zum Opt-in.
      for var Rg in FLex.ConditionalDebugRanges do
      begin
        var Nm := '';
        if Rg.Debug then Nm := 'DEBUG';  // SCA017 filtert auf 'DEBUG'; SCA011 nutzt alle
        Root.Add(nkConditionalRange, Nm, Rg.S, 0).TypeRef := IntToStr(Rg.E);
      end;
    except
      // Parser-Fehler NIE schlucken: frueher wurde nur die Watchdog-Exception
      // re-raised (per fragilem Pos('Parser-Watchdog')-Match), jeder echte
      // Parser-Bug aber verschluckt -> Detektoren liefen auf einem partiellen
      // AST weiter (falsche/fehlende Findings ohne Spur). Jetzt jede Exception
      // nach aussen reichen; den unvollstaendigen Baum vorher freigeben.
      // ParseLeaks faengt sie per-Datei ab und loggt PARSER-FEHLER.
      FreeAndNil(Root);
      raise;
    end;
  finally
    FreeAndNil(FLex);
  end;
  Result := Root;
end;

{ ---- Hilfsmethoden ---- }

function TParser2.Tok: TToken;
begin
  Result := FLex.Peek;
end;

function TParser2.Next: TToken;
const
  // 200k Token-Calls fangen einen Hang nach unter einer Sekunde ab.
  // Selbst grosse Quelldateien erzeugen typisch <50k Tokens; 200k laesst
  // genug Spielraum fuer SkipTo/SkipBalanced-Mehrlauf.
  MAX_NEXT_CALLS = 200 * 1000;
begin
  Inc(FNextCount);
  if FNextCount > MAX_NEXT_CALLS then
    raise Exception.CreateFmt(
      'Parser-Watchdog: ueber %d Token-Aufrufe - Datei wahrscheinlich ' +
      'pathologisch, Analyse abgebrochen.', [MAX_NEXT_CALLS]);
  Result := FLex.Next;
end;

procedure TParser2.GuardAdvance(StartCount: Integer);
// Wenn seit StartCount kein Token konsumiert wurde, einen forciert konsumieren.
// In Outer-Loops einsetzen, deren Sub-Parser theoretisch nicht advancen koennten.
begin
  if (FNextCount = StartCount) and not FLex.AtEnd then
    Next;
end;

function TParser2.AtTopLevelRoutineHead: Boolean;
// Boundary-Recovery ({$ifdef}-Straddle-Merge). Ein Routine-Header auf SPALTE 1
// kann im Statement-Kontext nicht legal auftreten: Routine-Header sind
// DEKLARATIONEN, keine Statements. Steht er trotzdem da, wurde der umgebende
// Block nie geschlossen - typisch wenn ein {$ifdef}/{$else} ein `begin`
// straddelt (Lexer emittiert BEIDE Zweige -> zwei `begin`, ein `end`).
//
// SPALTE-1-GATE (kritisch): anonyme Methoden (`x := procedure begin ... end`)
// und nested routines stehen EINGERUECKT und duerfen nie recovern - wuerden sie
// als Top-Level-Methoden gesurfacet, kostet das laut Messung +170k Findings
// (siehe ParseMethodImpl). Zusaetzlich erreichen sie den Statement-Kopf ohnehin
// nicht (ParseCallOrAssign schluckt sie per NestDepth; nested routines werden
// VOR dem Body konsumiert). Das Gate ist die zweite Sicherung.
//
// Fehlverhalten ist sicher: greift das Praedikat nicht, bleibt nur der bisherige
// Merge bestehen - es kann nichts abschneiden was vorher heil war.
var
  T : TToken;
begin
  T := Tok;
  Result := (T.Col <= 1) and
            (T.Kind in [tkKwProcedure, tkKwFunction, tkKwConstructor,
                        tkKwDestructor, tkKwOperator, tkKwClass]);
end;

procedure TParser2.SkipGenericParams;
// Konsumiert `<...>` mit Depth-Tracking fuer Nested-Generics (`<TList<T>>`).
// Wenn aktueller Token nicht `<` ist: no-op.
//
// Achtung: nur in TYPE-Kontext aufrufen (nach Typname / nach Methodenname),
// NICHT in Expression-Kontext - dort kann `<` ein Vergleichsoperator sein.
//
// EOF und Watchdog-Limit beenden den Loop garantiert; ein unbalanciertes `<`
// wuerde sonst bis EOF schlucken, das ist akzeptabel als Recovery.
var
  Depth: Integer;
begin
  if Tok.Kind <> tkLt then Exit;
  Next; // '<'
  Depth := 1;
  while (Depth > 0) and (Tok.Kind <> tkEof) do
  begin
    case Tok.Kind of
      tkLt   : Inc(Depth);
      tkGt   : Dec(Depth);
      tkGtEq :
        begin
          // `>=` taucht in Generic-Closures nicht legal auf - aber falls
          // ein Lexer-Edgecase das produziert (z.B. `T<U>=value`), brechen
          // wir kontrolliert ab statt endlos zu laufen.
          Dec(Depth);
        end;
    end;
    Next;
  end;
end;

procedure TParser2.SkipHelperFor;
// Konsumiert die optionale Praeambel `helper for <typename>` direkt nach
// `record` oder `class` (Aufrufer hat `record`/`class` schon konsumiert).
//
// Beispiele:
//   record helper for string         -> consume 'helper', 'for', 'string'
//   class helper for TFoo            -> consume 'helper', 'for', 'TFoo'
//   record helper for TUnit.TInner   -> consume 'helper', 'for',
//                                       'TUnit', '.', 'TInner'
//   record helper for array of Byte  -> consume 'helper', 'for',
//                                       'array', 'of', 'Byte'
//
// Wenn Tok nicht der `helper`-Ident ist: no-op (= normale class/record).
// Hinweis: `helper` ist in Delphi ein contextual keyword (Ident, kein Keyword).
begin
  if (Tok.Kind <> tkIdent) or not SameText(Tok.Value, 'helper') then Exit;
  Next; // 'helper'
  if not Eat(tkKwFor) then Exit; // syntax-Fehler -> Recovery, normal weitermachen

  // Target-Typname tokenweise konsumieren bis ein Token kommt das den
  // Class-Body einleitet (oder Forward-Decl beendet).
  while Tok.Kind in [tkIdent, tkKwString, tkDot,
                     tkKwArray, tkKwOf,
                     tkLBracket, tkRBracket, tkLt, tkGt, tkComma] do
    Next;
end;

function TParser2.Eat(K: TTokenKind): Boolean;
var
  Dummy: TToken;
begin
  Result := FLex.TryConsume(K, Dummy);
end;

procedure TParser2.SkipTo(const Stops: array of TTokenKind);
var
  K: TTokenKind;
  T: TToken;
begin
  while not FLex.AtEnd do
  begin
    T := Tok;
    for K in Stops do
      if T.Kind = K then Exit;
    if T.Kind in [tkLParen, tkLBracket, tkKwBegin] then
      SkipBalanced
    else
      Next;
  end;
end;

procedure TParser2.SkipToSemicolon;
begin
  // Auch an else/until/except/finally stoppen: das ';' nach einem THEN-Zweig
  // gehoert zur umschliessenden if-Anweisung, nicht zur Anweisung selbst.
  // Sonst wuerde z.B. "x := 1 else begin ... end;" das else-begin in die RHS
  // ziehen und das end;-Zaehlen verschieben.
  SkipTo([tkSemicolon, tkKwEnd, tkKwElse, tkKwUntil,
          tkKwExcept, tkKwFinally, tkEof]);
end;

procedure TParser2.SkipBalanced;
var
  OpenK, CloseK : TTokenKind;
  Depth         : Integer;
  T             : TToken;
begin
  case Tok.Kind of
    tkLParen   : begin OpenK := tkLParen;   CloseK := tkRParen;   end;
    tkLBracket : begin OpenK := tkLBracket; CloseK := tkRBracket; end;
    tkKwBegin  : begin OpenK := tkKwBegin;  CloseK := tkKwEnd;    end;
  else
    Next; Exit;
  end;
  Depth := 0;
  repeat
    T := Next;
    if      T.Kind = OpenK  then Inc(Depth)
    else if T.Kind = CloseK then
    begin
      Dec(Depth);
      if Depth = 0 then Exit;
    end
    else if T.Kind = tkEof then Exit;
  until False;
end;

{ ---- Top-Level ---- }

procedure TParser2.ParseUnit(Root: TAstNode);
var
  T: TToken;
begin
  if Eat(tkKwUnit) then
  begin
    if Tok.Kind = tkIdent then
    begin
      Root.Name := Next.Value;
      Eat(tkSemicolon);
    end;
  end;

  while not FLex.AtEnd do
  begin
    T := Tok;
    case T.Kind of
      tkKwInterface:
        begin
          var INode := Root.Add(nkInterface, 'interface', T.Line, T.Col);
          Next;
          ParseInterfaceSection(INode);
        end;
      tkKwImplementation:
        begin
          var INode := Root.Add(nkImplementation, 'implementation', T.Line, T.Col);
          Next;
          ParseImplementationSection(INode);
        end;
      // Top-Level Sektionen (zwischen 'unit X;' und 'interface') sind
      // syntaktisch nicht ganz korrekt, kommen aber in Test-Sources und
      // einigen real-world Units (z.B. ohne interface-Block) vor.
      // Ohne diese Branches werden uses/type/var/const-Bloecke ueber
      // dem 'else: Next'-Default verschluckt - Detektoren sehen die
      // Nodes nie. Fix: gleiche Behandlung wie in ParseInterfaceSection.
      tkKwUses:
        ParseUses(Root);
      tkKwType:
        begin Next; ParseTypeSection(Root); end;
      tkKwVar:
        begin Next; ParseVarLikeSection(Root, nkVarSection); end;
      tkKwConst:
        begin Next; ParseVarLikeSection(Root, nkConstSection); end;
      tkKwInitialization, tkKwFinalization:
        begin
          Next;
          SkipTo([tkKwEnd, tkEof]);
          Eat(tkKwEnd);
          Eat(tkDot);
          Exit;
        end;
      tkKwEnd :
        begin
          // Bug-A-Resync (2026-07-04): 'end' beendet die Unit nur als
          // 'end.' (oder am Dateiende). Ein einzelnes 'end' stammt aus
          // einem unbalancierten Konstrukt (z.B. nested type im Class-
          // Body: das innere 'end' schloss ParseClassBody, das aeussere
          // sickerte bis hierher durch) - frueher brach der Parse hier ab
          // und die KOMPLETTE Implementation fehlte im AST. Jetzt: stray
          // 'end' konsumieren und weiterparsen (Skip statt Truncation).
          Next; // 'end'
          if Tok.Kind = tkDot then begin Next; Exit; end;
          if Tok.Kind = tkEof then Exit;
        end;
      tkEof   : Exit;
    else
      Next;
    end;
  end;
end;

{ ---- Interface-Abschnitt ---- }

procedure TParser2.ParseInterfaceSection(Parent: TAstNode);
var
  T          : TToken;
  StartCount : Integer;
begin
  while not FLex.AtEnd do
  begin
    StartCount := FNextCount;
    T := Tok;
    case T.Kind of
      tkKwUses                              : ParseUses(Parent);
      tkKwType                              : begin Next; ParseTypeSection(Parent); end;
      tkKwVar                               : begin Next; ParseVarLikeSection(Parent, nkVarSection);   end;
      tkKwConst                             : begin Next; ParseVarLikeSection(Parent, nkConstSection); end;
      tkKwProcedure, tkKwFunction,
      tkKwConstructor, tkKwDestructor,
      tkKwOperator                          : ParseMethodSignature(Parent);
      tkKwImplementation, tkKwInitialization,
      tkKwFinalization, tkKwEnd, tkEof      : Exit;
    else
      Next;
    end;
    GuardAdvance(StartCount);
  end;
end;

{ ---- Implementation-Abschnitt ---- }

procedure TParser2.ParseImplementationSection(Parent: TAstNode);
var
  T          : TToken;
  StartCount : Integer;
begin
  // Ziel-Parent fuer die IFDEF-Body-Recovery merken (siehe ParseStatement,
  // Routine-Header-Branch): recoverte Methoden gehoeren auf Unit-Ebene.
  FImplNode := Parent;
  while not FLex.AtEnd do
  begin
    StartCount := FNextCount;
    T := Tok;
    case T.Kind of
      tkKwUses                              : ParseUses(Parent);
      tkKwType                              : begin Next; ParseTypeSection(Parent); end;
      tkKwVar                               : begin Next; ParseVarLikeSection(Parent, nkVarSection);   end;
      tkKwConst                             : begin Next; ParseVarLikeSection(Parent, nkConstSection); end;
      tkKwProcedure, tkKwFunction,
      tkKwConstructor, tkKwDestructor,
      tkKwOperator                          : ParseMethodImpl(Parent);
      tkKwClass                             :
        begin
          // `class procedure/function/constructor/destructor`-Impl: Parser
          // muss den class-Marker erhalten, sonst kann der DestructorWithout-
          // InheritedDetector den Class-Destruktor (der KEINE inheritance-
          // chain hat) nicht von einem Instance-Destruktor unterscheiden.
          // Pattern analog zum Class-Body-Pfad (ParseClassBody tkKwClass).
          Next; // 'class' konsumieren
          if Tok.Kind in [tkKwProcedure, tkKwFunction, tkKwConstructor,
                          tkKwDestructor, tkKwOperator] then
          begin
            var BeforeCount := Parent.Children.Count;
            ParseMethodImpl(Parent);
            if Parent.Children.Count > BeforeCount then
            begin
              // Review-Fix (2026-07-04): index-basiert statt .Last - feuert
              // waehrend des Bodys die IFDEF-Body-Recovery, haengen dahinter
              // RECOVERTE Methoden; .Last waere dann die falsche. Das Kind
              // an BeforeCount ist immer die hier geparste class-Methode
              // (auch im Twin-Dedup-Fall der verbliebene Twin).
              var First := Parent.Children[BeforeCount];
              if (First.Kind = nkMethod) and
                 (Pos(';class', LowerCase(First.TypeRef)) = 0) then
                First.TypeRef := First.TypeRef + ';class';
            end;
          end;
        end;
      tkKwInitialization, tkKwFinalization,
      tkEof                                 : Exit;
      tkKwEnd                               :
        begin
          // Bug-A-Resync (2026-07-04): 'end' ist auf Implementation-Ebene
          // nur als Unit-Terminator 'end.' legal. Ein einzelnes 'end'
          // stammt aus einem unbalancierten Konstrukt weiter oben (z.B.
          // nested type im Class-Body einer impl-lokalen type-Section) -
          // frueher beendete es die Section und der REST DER DATEI fehlte
          // im AST (Selbstscan-Repro: 20 -> 1 Findings). Jetzt: nur bei
          // echtem Datei-Ende terminieren, sonst konsumieren und weiter-
          // parsen. Einzelne Deklarationen des kaputten Konstrukts bleiben
          // unsichtbar - Skip ist strikt besser als Truncation.
          Next; // 'end'
          if Tok.Kind = tkDot then
          begin
            // Echtes 'end.': Rest der Datei ist per Sprachdefinition tot
            // (Dead-Code-Idiom 'end.' hochziehen, Alt-Kopien hinter end.).
            // Review-Fix (2026-07-04): explizit bis EOF verwerfen, sonst
            // wuerde der Impl-Loop von ParseUnit Trailing-Text als Live-
            // Code parsen -> Phantom-Findings auf totem Code.
            Next; // '.'
            SkipTo([tkEof]);
            Exit;
          end;
          if Tok.Kind = tkEof then Exit;                  // 'end<EOF>'
        end;
    else
      Next;
    end;
    GuardAdvance(StartCount);
  end;
end;

{ ---- Uses-Klausel ---- }

procedure TParser2.ParseUses(Parent: TAstNode);
var
  T        : TToken;
  UsesNode : TAstNode;
  Name     : string;
begin
  T        := Next; // 'uses'
  UsesNode := Parent.Add(nkUses, 'uses', T.Line, T.Col);

  while not FLex.AtEnd do
  begin
    T := Tok;
    if T.Kind = tkIdent then
    begin
      Name := Next.Value;
      while Tok.Kind = tkDot do
      begin
        Next;
        if Tok.Kind = tkIdent then
          Name := Name + '.' + Next.Value;
      end;
      UsesNode.Add(nkUsesItem, Name, T.Line, T.Col);
      if Tok.Kind = tkKwIn then // in 'path'
      begin
        Next;
        if Tok.Kind = tkStrLit then Next;
      end;
      Eat(tkComma);
    end
    else if T.Kind = tkSemicolon then
    begin
      Next; Break;
    end
    else
      Break;
  end;
end;

{ ---- Type-Abschnitt ---- }

procedure TParser2.ParseTypeSection(Parent: TAstNode);
var
  SecNode    : TAstNode;
  Name       : string;
  T          : TToken;
  StartCount : Integer;
begin
  SecNode := Parent.Add(nkTypeSection, 'type', Tok.Line, Tok.Col);

  while not FLex.AtEnd do
  begin
    StartCount := FNextCount;
    T := Tok;
    // tkKwType bewusst NICHT in Exit-Liste: lokale/wiederholte 'type'-Keywords
    // sollen die Section nicht beenden (sonst markiert der Watchdog die Datei
    // als unvollstaendig). Wird durch den 'not tkIdent' Continue-Branch unten
    // konsumiert; GuardAdvance garantiert Forward-Progress.
    if T.Kind in [tkKwVar, tkKwConst,
                  tkKwProcedure, tkKwFunction, tkKwConstructor, tkKwDestructor,
                  tkKwImplementation, tkKwInitialization, tkKwEnd, tkEof] then
      Exit;

    if T.Kind <> tkIdent then begin Next; Continue; end;

    Name := Next.Value;
    // Generic-Parameter direkt nach dem Typnamen konsumieren:
    //   TFoo<T> = class                  -> SkipGenericParams frisst <T>
    //   TFoo<K, V: class> = TObjectDictionary<K, V>
    SkipGenericParams;
    if not Eat(tkEq) then begin SkipToSemicolon; Eat(tkSemicolon); Continue; end;

    // Optionales `packed` vor record/class konsumieren
    Eat(tkKwPacked);

    T := Tok;
    case T.Kind of
      tkKwClass:
        begin
          Next;
          if Tok.Kind in [tkKwOf, tkSemicolon] then
          begin
            // Vorwärtsdeklaration: TFoo = class; oder class of T
            SkipToSemicolon;
            Eat(tkSemicolon);
          end
          else
          begin
            // class helper for TFoo - die Praeambel ueberspringen
            SkipHelperFor;
            var CNode := SecNode.Add(nkClass, Name, T.Line, T.Col);
            ParseClassBody(CNode);
            Eat(tkSemicolon);
          end;
        end;
      tkKwRecord:
        begin
          Next;
          // record helper for string - Praeambel ueberspringen
          SkipHelperFor;
          var RNode := SecNode.Add(nkRecord, Name, T.Line, T.Col);
          ParseClassBody(RNode);
          Eat(tkSemicolon);
        end;
      tkKwInterface:
        begin
          Next;
          if Tok.Kind = tkSemicolon then
          begin
            // Forward-Decl: IFoo = interface;
            Eat(tkSemicolon);
          end
          else
          begin
            // Interface-Typ wird als nkClass im AST gefuehrt - Detektoren
            // arbeiten auf Members (Methoden, Properties), kein
            // Spezial-Handling noetig. Die optionale GUID `['{...}']` und
            // die optionale Parent-Liste werden in ParseClassBody durch
            // den Else-Next-Pfad benignly geskippt.
            var INode := SecNode.Add(nkClass, Name, T.Line, T.Col);
            ParseClassBody(INode);
            Eat(tkSemicolon);
          end;
        end;
    else
      begin
        // Typaliase: Inhalt (Bezeichner) in TypeRef speichern damit
        // CollectText referenzierte Typen als Verwendungsnachweis zaehlt.
        // Beispiel: TMyEvent = TNotifyEvent  →  TypeRef = 'TNotifyEvent'
        //
        // Procedural-Type-Aliase wie
        //   TFTPStatus = procedure(Sender: TObject; Response: Boolean;
        //                          const Value: string) of object;
        //   TFn        = function(X: Integer): Integer;
        // enthalten Semicolons INNERHALB der Param-Liste. Ohne Paren-
        // Depth-Tracking stoppt die Loop dort und der Parser geraet komplett
        // durcheinander: das uebernaechste Token ('Response') wird als
        // neuer Typname interpretiert, der Outer-loop beendet die
        // type-Section sobald sie ein 'procedure' ausserhalb erwartet
        // wird - die GESAMTE Implementation einer Unit wird verloren
        // (Audit ftpsend.pas: 52 Method-Headers im Source -> 1 nkMethod
        // im AST).
        // Enumerationstyp erkennen: NUR ein Enum beginnt im Typ-Rumpf mit '('
        // ('TColor = (clRed, clGreen, ...)'). Proc-Typen ('procedure'/'function'),
        // Sets ('set of'), Arrays ('array'), Subranges ('a..b'), Pointer ('^T')
        // und Klartext-Aliase (Ident) beginnen anders -> tkLParen == Enum.
        // 2026-07-13: als nkEnumType statt nkTypeAlias emittieren, damit der
        // (bereits vorhandene) TTypeIndex-nkEnumType-Walk TypeKindOf=tkiEnum
        // liefert. Ripple ~0: KEIN Detektor konsumiert nkTypeAlias/tkiAlias,
        // und CollectText (uUnusedUses) addiert TypeRef fuer JEDE Knotenart
        // (nur nkUsesItem ausgenommen) -> Usage-Zaehlung unveraendert.
        var IsEnum       := (Tok.Kind = tkLParen);
        var AliasContent := '';
        var Depth        := 0;
        while not (Tok.Kind in [tkKwEnd, tkEof]) do
        begin
          if (Depth = 0) and (Tok.Kind = tkSemicolon) then Break;
          case Tok.Kind of
            tkLParen, tkLBracket: Inc(Depth);
            tkRParen, tkRBracket: if Depth > 0 then Dec(Depth);
          end;
          if Tok.Kind = tkIdent then
          begin
            if AliasContent <> '' then AliasContent := AliasContent + ' ';
            AliasContent := AliasContent + Tok.Value;
          end;
          Next;
        end;
        var AliasKind := nkTypeAlias;
        if IsEnum then AliasKind := nkEnumType;
        var ANode := SecNode.Add(AliasKind, Name, T.Line, T.Col);
        ANode.TypeRef := AliasContent;
        Eat(tkSemicolon);
      end;
    end;
    GuardAdvance(StartCount);
  end;
end;

{ ---- Var / Const -Abschnitt ---- }

procedure TParser2.ParseVarLikeSection(Parent: TAstNode; AKind: TNodeKind);
var
  SecNode    : TAstNode;
  Names      : TStringList;
  TypeName   : string;
  ConstValue : string;
  FullRef    : string;
  N, VN      : string;
  T          : TToken;
begin
  SecNode := Parent.Add(AKind, '', Tok.Line, Tok.Col);
  Names   := TStringList.Create;
  try
    while not FLex.AtEnd do
    begin
      T := Tok;
      if T.Kind in [tkKwType, tkKwVar, tkKwConst,
                    tkKwProcedure, tkKwFunction, tkKwConstructor, tkKwDestructor,
                    tkKwImplementation, tkKwEnd, tkEof,
                    tkKwBegin, tkKwAsm] then
        Exit;

      if T.Kind <> tkIdent then begin Next; Continue; end;

      Names.Clear;
      while Tok.Kind = tkIdent do
      begin
        Names.Add(Next.Value);
        if not Eat(tkComma) then Break;
      end;

      TypeName := '';
      if Eat(tkColon) then
        while not (Tok.Kind in [tkSemicolon, tkEq, tkKwEnd, tkEof]) do
        begin
          TypeName := TypeName + Tok.Value;
          Next;
        end;

      // Const-Initializer mitnehmen: 'const NAME = ...;' oder
      // 'const NAME: Type = ...;'. Wert wird in TypeRef nach dem Type-
      // Namen mit '=' separiert abgelegt (Format: 'Type=value' bzw.
      // '=value' wenn untypisiert). Brauchen wir z.B. fuer den
      // FormatMismatch-Detektor der Konstanten-basierte Format-Strings
      // aufloesen muss. Var-Sections lassen den Initializer wie bisher
      // unter den Tisch fallen - der Wert hat dort keinen Detector-
      // Mehrwert.
      ConstValue := '';
      if (AKind = nkConstSection) and Eat(tkEq) then
      begin
        while not (Tok.Kind in [tkSemicolon, tkKwEnd, tkEof]) do
        begin
          if Tok.Kind = tkStrLit then
            JoinTokInto(ConstValue, QuoteStrLit(Tok.Value))
          else
            JoinTokInto(ConstValue, Tok.Value);
          Next;
        end;
      end;

      FullRef := TypeName;
      if ConstValue <> '' then
        FullRef := FullRef + '=' + ConstValue;

      for N in Names do
      begin
        VN := N;
        SecNode.Add(nkField, VN, T.Line, T.Col).TypeRef := FullRef;
      end;

      SkipToSemicolon;
      Eat(tkSemicolon);
    end;
  finally
    Names.Free;
  end;
end;

{ ---- Klassen-Rumpf ---- }

procedure TParser2.ParseClassBody(ClassNode: TAstNode);
var
  VisNode    : TAstNode;
  T          : TToken;
  FName      : string;
  FType      : string;
  StartCount : Integer;
begin
  // Elternklasse(n): class(TForm) oder class(TObject, IInterface)
  // Bezeichner werden in ClassNode.TypeRef gespeichert, damit der
  // UnusedUses-Detektor sie als Verwendungsnachweis zaehlen kann.
  if Eat(tkLParen) then
  begin
    var Parents := '';
    while not (Tok.Kind in [tkRParen, tkKwEnd, tkEof]) do
    begin
      if Tok.Kind = tkIdent then
      begin
        // [16] (Core-Audit 2026-07-17): qualifizierte Basisklasse zusammen-
        // halten. 'class(Vcl.Forms.TForm)' liefert die Tokens Vcl . Forms .
        // TForm; frueher wurde der '.' verworfen und space-getrennt zu
        // 'Vcl Forms TForm' - BaseClassNameLow nahm dann 'Vcl' als Basisklasse
        // und IsDescendantOf brach an der Unit-Grenze ab. Jetzt: nach einem
        // '.' direkt anhaengen (dotted-Name), sonst neuer space-getrennter
        // Parent (Interfaces). BaseClassNameLow kappt den Unit-Qualifier.
        if (Parents <> '') and not Parents.EndsWith('.') then
          Parents := Parents + ' ';
        Parents := Parents + Tok.Value;
      end
      else if Tok.Kind = tkDot then
        Parents := Parents + '.';
      Next;
    end;
    if Parents <> '' then
      ClassNode.TypeRef := Parents;
    Eat(tkRParen);
  end;

  VisNode := ClassNode.Add(nkVisibilitySection, 'published', Tok.Line, Tok.Col);

  while not FLex.AtEnd do
  begin
    StartCount := FNextCount;
    T := Tok;
    case T.Kind of
      tkKwPublic, tkKwPrivate, tkKwProtected, tkKwPublished:
        begin
          Next;
          Eat(tkKwClass); // 'strict' kommt schon als Ident
          VisNode := ClassNode.Add(nkVisibilitySection, T.Value, T.Line, T.Col);
        end;
      tkKwProcedure, tkKwFunction,
      tkKwConstructor, tkKwDestructor, tkKwOperator:
        ParseMethodSignature(VisNode);
      tkKwClass:
        begin
          Next; // 'class' konsumieren
          // class procedure / class function / class operator: die folgende
          // Methoden-Signatur parsen und im TypeRef mit ';class' markieren.
          // Class-Var/-Const/-Property werden ignoriert (kein Methoden-
          // Knoten -> nichts zu markieren).
          if Tok.Kind in [tkKwProcedure, tkKwFunction, tkKwConstructor,
                          tkKwDestructor, tkKwOperator] then
          begin
            var BeforeCount := VisNode.Children.Count;
            ParseMethodSignature(VisNode);
            if VisNode.Children.Count > BeforeCount then
            begin
              var Last := VisNode.Children[VisNode.Children.Count - 1];
              if (Last.Kind = nkMethod) and
                 (Pos(';class', LowerCase(Last.TypeRef)) = 0) then
                Last.TypeRef := Last.TypeRef + ';class';
            end;
          end;
        end;
      tkKwProperty:
        begin
          Next;
          var PropName := '';
          if Tok.Kind = tkIdent then PropName := Next.Value;
          VisNode.Add(nkProperty, PropName, T.Line, T.Col);
          SkipToSemicolon;
          Eat(tkSemicolon);
        end;
      tkKwEnd :
        begin Next; Exit; end;
      tkIdent :
        begin
          // Feld-Deklaration
          FName := Next.Value;
          if Eat(tkComma) then
          begin
            // mehrere Felder in einer Zeile — einfach überspringen
            SkipToSemicolon;
            Eat(tkSemicolon);
            Continue;
          end;
          FType := '';
          if Eat(tkColon) then
            while not (Tok.Kind in [tkSemicolon, tkKwEnd, tkEof]) do
            begin
              // Anonymer inline-`record`-Typ als Feld-Typ:
              //   fContext: array of record A: Integer; B: TFoo; end;
              // Ohne Spezial-Behandlung bricht die Loop am ersten ';' im
              // Record-Body ab, und das innere 'end' wird vom Outer-Loop
              // als Class-End interpretiert -> Override-Methoden ab
              // Z216 landen ausserhalb der Klasse (Mustache-Audit, 4x4
              // SCA135 FPs). Mini-Parser bis matching `end`.
              if Tok.Kind = tkKwRecord then
              begin
                FType := FType + Tok.Value;
                Next;
                var Depth := 1;
                while (Depth > 0) and (Tok.Kind <> tkEof) do
                begin
                  case Tok.Kind of
                    tkKwRecord: Inc(Depth);
                    tkKwEnd:    Dec(Depth);
                  end;
                  FType := FType + Tok.Value;
                  Next;
                end;
                Continue;
              end;
              FType := FType + Tok.Value;
              Next;
            end;
          VisNode.Add(nkField, FName, T.Line, T.Col).TypeRef := FType;
          Eat(tkSemicolon);
        end;
    else
      Next;
    end;
    GuardAdvance(StartCount);
  end;
end;

{ ---- Methoden-Signatur (Deklaration ohne Rumpf) ---- }

function IsRoutineNameKeyword(Kind: TTokenKind): Boolean;
// Real-World-FP-Audit 2026-07-12 (SCA028): einige Standard-Routinen sind KEINE
// reservierten Woerter und duerfen Methoden-/Event-Handler-Namen sein (z.B.
// 'procedure Exit(Sender: TObject)'), werden vom Lexer aber als Keyword
// tokenisiert. An der Methoden-Namen-Position (direkt nach procedure/function)
// ist ein solches Token der NAME -> als Ident behandeln, damit der Binder die
// Methode findet (sonst SCA028-FP 'DFM-Event referenziert fehlende Methode').
// Nur nicht-reservierte Standard-Routinen; echte Keywords (begin/if/...) koennen
// an dieser Position in gueltigem Code nie stehen.
begin
  Result := Kind in [tkKwExit, tkKwResult, tkKwRead, tkKwWrite,
                     tkKwBreak, tkKwContinue];
end;

procedure TParser2.ParseMethodSignature(Parent: TAstNode);
var
  T        : TToken;
  MethKind : string;
  MethName : string;
  MNode    : TAstNode;
  PNames   : TStringList;
  PType    : string;
  PN, Modifier : string;
begin
  if FResumeHeaderPending then
  begin
    // IFDEF-Body-Recovery (2026-07-04): ParseStatement hat Keyword und
    // ersten Namens-Ident bereits konsumiert (der Lexer bietet nur
    // 1-Token-Peek, ein Lookahead ohne Konsum ist nicht moeglich).
    // Hier nahtlos ab dem '.' weiterparsen.
    FResumeHeaderPending := False;
    T        := FResumeKwTok;
    MethName := FResumeName1;
  end
  else
  begin
    T        := Next; // procedure / function / constructor / destructor
    MethName := '';
    if (Tok.Kind = tkIdent) or IsRoutineNameKeyword(Tok.Kind) then
      MethName := Next.Value;
  end;
  MethKind := T.Value;

  if MethName <> '' then
  begin
    // Klassen-Generic-Param zwischen Klassen-Name und Methoden-Name:
    //   procedure TFoo<T>.Bar;     <- nach 'TFoo' kommt '<T>' vor '.'
    SkipGenericParams;
    if Tok.Kind = tkDot then
    begin
      Next;
      if (Tok.Kind = tkIdent) or IsRoutineNameKeyword(Tok.Kind) then
        MethName := MethName + '.' + Next.Value;
      // Methoden-Generic-Param nach qualifiziertem Namen:
      //   procedure TFoo<T>.Bar<U>: U;
      SkipGenericParams;
    end;
  end;

  // Generic-Param nach unqualifiziertem Methoden-Name:
  //   function Get<T>: T;
  SkipGenericParams;

  MNode         := Parent.Add(nkMethod, MethName, T.Line, T.Col);
  MNode.TypeRef := MethKind;

  // Parameter-Liste
  if Eat(tkLParen) then
  begin
    PNames := TStringList.Create;
    try
      while not (Tok.Kind in [tkRParen, tkEof]) do
      begin
        var ParamStart := FNextCount;
        Modifier := '';
        if Tok.Kind in [tkKwVar, tkKwConst, tkKwOut] then
          Modifier := Next.Value;

        PNames.Clear;
        // Akzeptiere auch Keywords als Parameter-Namen (Result, String, ...).
        // Delphi erlaubt das obwohl sie reservierte Woerter sind - Code wie
        // 'procedure X(Result: Integer)' kommt in fremdem Code regelmaessig vor.
        while Tok.Kind in [tkIdent, tkKwResult, tkKwString] do
        begin
          PNames.Add(Next.Value);
          if not Eat(tkComma) then Break;
        end;

        PType := '';
        if Eat(tkColon) then
          while not (Tok.Kind in [tkSemicolon, tkRParen, tkEof]) do
          begin
            // JoinTokInto statt roher Konkatenation: Mehrwort-Typen wie
            // 'array of Integer' klebten sonst zu 'arrayofInteger' zusammen
            // (Audit 2026-07) - Wortgrenzen-Checks auf TypeRef liefen ins Leere.
            JoinTokInto(PType, Tok.Value);
            Next;
          end;

        for PN in PNames do
        begin
          var PNode     := MNode.Add(nkParam, PN, T.Line, T.Col);
          PNode.TypeRef := PType;
          if Modifier <> '' then
            PNode.Name := Modifier + ' ' + PN;
        end;
        Eat(tkSemicolon);
        // Forward-Progress: falls Tok in dieser Iteration keinen Branch matchte
        // (z.B. unbekanntes Keyword als Param-Name), forciere Konsum.
        GuardAdvance(ParamStart);
      end;
    finally
      PNames.Free;
    end;
    Eat(tkRParen);
  end;

  // Rückgabetyp
  if Eat(tkColon) then
  begin
    var RetType := '';
    while not (Tok.Kind in [tkSemicolon, tkKwEnd, tkEof]) do
    begin
      // JoinTokInto: 'function F: array of Integer' ergab sonst
      // TypeRef '...:arrayofInteger' (s. Param-Typ-Loop, Audit 2026-07).
      JoinTokInto(RetType, Tok.Value);
      Next;
    end;
    MNode.TypeRef := MethKind + ':' + RetType;
  end;

  Eat(tkSemicolon);
  ParseMethodDirectives(MNode);
end;

{ ---- Methoden-Direktiven überspringen ---- }

procedure TParser2.ParseMethodDirectives(MNode: TAstNode);
// Konsumiert alle Method-Direktiven (virtual, abstract, override, ...,
// plus Calling-Conventions wie stdcall/cdecl/dcpcall/export, siehe
// IsMethodDirectiveTok).
// Wenn MNode gegeben ist, werden die Direktiven case-erhaltend an
// MNode.TypeRef angehaengt - im Format `'kind[:ret];dir1;dir2'`.
// Detektoren (uVirtualCallInCtor) lesen das via SplitDirectives.
var
  DirKind : TTokenKind;
begin
  while IsMethodDirectiveTok(Tok) do
  begin
    DirKind := Tok.Kind;
    if MNode <> nil then
      MNode.TypeRef := MNode.TypeRef + ';' + LowerCase(Tok.Value);
    Next;
    if (DirKind = tkKwDeprecated) and (Tok.Kind = tkStrLit) then Next; // deprecated 'Nachricht'
    Eat(tkSemicolon);
  end;
end;

{ ---- Methoden-Implementierung ---- }

function MaxSubtreeLine(Node: TAstNode): Integer;
// Hoechste Zeilennummer ueber Node + alle Descendants (iterativ, stack-safe).
// Fuer die nkNestedRange-Marker-Endzeile beim Verwerfen nested routines.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := 0;
  if Node = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Node);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Line > Result then Result := Cur.Line;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

procedure TParser2.ParseMethodImpl(Parent: TAstNode);
var
  MNode : TAstNode;
begin
  ParseMethodSignature(Parent);

  if Parent.Children.Count = 0 then Exit;
  MNode := Parent.Children.Last;
  if MNode.Kind <> nkMethod then Exit;

  // Bug-A-Teilfix (2026-07-04): forward-/external-Deklarationen haben
  // weder Deklarationsteil noch Body - sofort zurueck zum Aufrufer.
  // Frueher lief ParseLocalVarSection trotzdem weiter und interpretierte
  // eine FOLGENDE impl-level type/const/var-Section als lokale Sektion
  // der Forward-Decl; eine type-Section mit record/class stoppte dabei
  // am inneren 'end' -> ParseImplementationSection hielt das fuer das
  // Unit-Ende, der Rest der Datei fehlte im AST. Jetzt parst der
  // Impl-Loop die Section regulaer (nkTypeSection/nkVarSection/...).
  // Hinweis: der Forward-Knoten bleibt als headless nkMethod stehen
  // (gleiches Muster wie eine Interface-Signatur); die echte
  // Implementierung erzeugt spaeter ihren eigenen nkMethod.
  // ';forward'/';external' stammen aus ParseMethodDirectives (lowercase);
  // in Return-Typ/Direktiven-Teil von TypeRef kann kein ';' aus
  // Nutzertext auftauchen - der Substring-Match ist eindeutig.
  if (Pos(';forward', MNode.TypeRef) > 0) or
     (Pos(';external', MNode.TypeRef) > 0) then
    Exit;

  ParseLocalVarSection(MNode);

  // Nested local routines: Delphi erlaubt `procedure`/`function`-Deklarationen
  // (mit eigenem Rumpf) im Deklarations-Abschnitt VOR dem `begin` der aeusseren
  // Methode, optional mit weiteren var/const/type-Sektionen dazwischen. Sie
  // werden hier rekursiv geparst, damit die Lexer-Position korrekt bis hinter
  // ihre Rumpf-`end;` laeuft und der ECHTE Outer-Body (mit `Result :=` /
  // Var-Writes) danach normal geparst wird. Frueher fraß ParseLocalVarSection
  // die nested routine als Pseudo-Local-Var und der Outer-Body ging verloren ->
  // SCA121/SCA166-False-Positives auf der aeusseren Methode.
  //
  // WICHTIG: nested routines werden NICHT als analysierbare nkMethod im AST
  // belassen. Der AST hat sie noch nie enthalten (der alte Headless-Branch
  // loeschte sie); der Smell wird vom LEXISCHEN uNestedRoutines-Detektor
  // (fkNestedRoutine, Hint) gemeldet. Wuerde man sie als Top-Level-Methoden
  // surfacen, feuerten could-be-class-method (SCA148), Complexity (SCA176),
  // uninit/Result u.a. massenhaft auf ihnen (Real-World-Messung: +170k
  // Findings, SCA148 +17k). Darum: parsen, dann verwerfen.
  //
  // Sonderfall IFDEF-Konditional-Twin: derselbe Method-Header erscheint zwei-
  // mal im Token-Stream (Lexer skippt nur Comments), z.B.
  //   {$IFDEF FPC} function F: integer;
  //   {$ELSE}      function F: string;  {$ENDIF}  begin ... end;
  // Der ZWEITE Header (gleicher Name) traegt den gemeinsamen Body. Der headless
  // erste Knoten (MNode) wird entfernt; der Twin bleibt als die eine echte
  // Methode MIT Body stehen (kein Phantom-Duplikat, Body bleibt erhalten).
  while Tok.Kind in [tkKwProcedure, tkKwFunction,
                     tkKwConstructor, tkKwDestructor, tkKwOperator] do
  begin
    var Before := Parent.Children.Count;
    ParseMethodImpl(Parent);                // nested/twin als Sibling parsen
    if Parent.Children.Count = Before then Break;  // Defensive: nichts geparst
    var Sub := Parent.Children[Before];     // die gerade geparste Routine

    if (MNode.Name <> '') and SameText(Sub.Name, MNode.Name) then
    begin
      // IFDEF-Twin: Sub ist die echte Methode (mit Body) -> headless MNode weg.
      Parent.Children.Remove(MNode);        // OwnsObjects=True -> gibt MNode frei
      Exit;
    end;

    // Echte nested routine: nur zur Positions-Findung geparst, jetzt verwerfen
    // (inkl. tiefer verschachtelter, die die Rekursion ebenfalls als Siblings
    // ab Index `Before` angehaengt hat). VORHER die exakte Quell-Range als
    // nkNestedRange-Marker an MNode haengen: Detektoren (SCA166) skippen damit
    // Reads in nested procs exakt - robuster als die line-basierte Heuristik.
    var NestStart := Sub.Line;
    var NestEnd   := Sub.Line;
    for var di := Before to Parent.Children.Count - 1 do
    begin
      var ML := MaxSubtreeLine(Parent.Children[di]);
      if ML > NestEnd then NestEnd := ML;
    end;
    if NestStart > 0 then
      MNode.Add(nkNestedRange, '', NestStart, 0).TypeRef := IntToStr(NestEnd);

    while Parent.Children.Count > Before do
      Parent.Children.Delete(Parent.Children.Count - 1);  // OwnsObjects -> Free

    // Weitere var/const/type-Sektionen koennen vor dem Outer-Body folgen.
    ParseLocalVarSection(MNode);
  end;

  if Tok.Kind = tkKwBegin then
    ParseBlock(MNode)
  else if Tok.Kind = tkKwAsm then
  begin
    Next;
    SkipTo([tkKwEnd, tkEof]);
    Eat(tkKwEnd);
    Eat(tkSemicolon);
  end;
end;

{ ---- Lokale Var/Const-Blöcke ---- }

procedure TParser2.ParseLocalVarSection(Parent: TAstNode);
var
  VarNames : TStringList;
  TypeName : string;
  T        : TToken;
  VN       : string;
begin
  VarNames := TStringList.Create;
  try
    while Tok.Kind in [tkKwVar, tkKwConst, tkKwType, tkKwLabel] do
    begin
      var SecKind := Tok.Kind;
      Next;

      if SecKind = tkKwLabel then
      begin
        // `label x, y, z;` - bis zum naechsten Semikolon skippen.
        // Wir tracken Goto-Labels nicht im AST, sie sind fuer Detektoren
        // unsichtbar. Wichtig: ohne diesen Branch endet die Outer-Loop
        // beim ersten `tkKwLabel` und ParseMethodImpl verliert den Body
        // (siehe TODO-Eintrag mORMot2-Performance-Pfade).
        SkipToSemicolon;
        Eat(tkSemicolon);
        Continue;
      end;

      if SecKind = tkKwType then
      begin
        // Skip-Loop bis zum naechsten Section/Body. Next garantiert
        // normalerweise Forward-Progress; GuardAdvance ist defensiv falls
        // Lexer in einem korrupten Zustand stecken bleibt.
        //
        // Bug-A-Fix (2026-07-04), zwei Ergaenzungen gegen Datei-Truncation:
        // 1) Lokale record-Typen (`TRec = record ... end;`) werden mit dem
        //    etablierten Mini-Parser bis zum matching `end` balanciert
        //    uebersprungen (nested records zaehlen mit). Frueher stoppte
        //    der Skip am ERSTEN `end` im record-Body; die Outer-Loops
        //    hielten es fuer das Methoden-/Unit-Ende -> der Rest der Datei
        //    fehlte im AST. Limitation: die Deklarationen der Section
        //    bleiben wie bisher unsichtbar (kein AST-Knoten) - nur die
        //    Lexer-Position muss hinter der Section stimmen.
        // 2) Ein Routine-Header NACH einer Deklaration (procedure/function
        //    mit vorangehendem ';') beendet den Skip: er leitet eine
        //    nested routine ein, die der nested-Routine-Pfad von
        //    ParseMethodImpl parst. Prozedurale Typaliase wie
        //    `TCb = procedure(...) of object;` folgen dagegen auf `=`
        //    (PrevKind <> ';') und werden weiterhin mitgeskippt.
        var PrevKind := tkKwType;
        while not (Tok.Kind in [tkKwVar, tkKwConst, tkKwBegin, tkKwAsm,
                                 tkKwEnd, tkEof]) do
        begin
          var SkipStart := FNextCount;
          if (Tok.Kind in [tkKwProcedure, tkKwFunction, tkKwConstructor,
                           tkKwDestructor, tkKwOperator]) and
             (PrevKind = tkSemicolon) then
            Break;
          if Tok.Kind = tkKwRecord then
          begin
            // record-Body balanciert konsumieren (inkl. schliessendem
            // `end`). Nur tkKwRecord zaehlt als Opener: `class`/`object`
            // waeren als lokale Typen ohnehin illegal, und `class` kommt
            // in record-Bodies als Modifier (`class function`) vor -
            // Depth-Zaehlung darauf wuerde ueberzaehlen.
            Next; // 'record'
            var Depth := 1;
            while (Depth > 0) and (Tok.Kind <> tkEof) do
            begin
              case Tok.Kind of
                tkKwRecord: Inc(Depth);
                tkKwEnd:    Dec(Depth);
              end;
              Next;
            end;
            PrevKind := tkKwEnd;
            Continue;
          end;
          PrevKind := Tok.Kind;
          Next;
          GuardAdvance(SkipStart);
        end;
        Continue;
      end;

      if SecKind = tkKwConst then
      begin
        // Lokale const-Sections wie unit-level behandeln: emittiere
        // nkConstSection mit nkField-Kindern (statt flacher nkLocalVar),
        // damit Detektoren (uNamingExt fkLocalConstantName, uFormatMismatch)
        // Konstanten von Variablen unterscheiden und an die Konstanten-Werte
        // kommen koennen. ParseVarLikeSection bricht jetzt auch an
        // tkKwBegin/tkKwAsm ab und ist damit body-safe.
        ParseVarLikeSection(Parent, nkConstSection);
        Continue;
      end;

      while not (Tok.Kind in [tkKwVar, tkKwConst, tkKwType,
                              tkKwProcedure, tkKwFunction, tkKwConstructor,
                              tkKwDestructor, tkKwOperator,
                              tkKwBegin, tkKwAsm, tkKwEnd, tkEof]) do
      begin
        // Routine-Keywords (procedure/function/...) beenden die Var-Section:
        // sie leiten eine NESTED routine ein, KEINE weitere Variable. Ohne
        // diesen Stop fraesse der Var-Parser `procedure Local` als Pseudo-
        // Local-Var (`Local` ohne Typ) und ParseMethodImpl wuerde danach den
        // Body der nested routine als Outer-Body fehlinterpretieren -> der
        // echte Outer-Body (mit `Result :=` / Var-Writes) ginge verloren
        // (Wurzel der SCA121/SCA166-False-Positives). ParseMethodImpl parst
        // die nested routine jetzt selbst als eigenes nkMethod-Child.
        // GuardAdvance schuetzt vor Endlos-Loop: SkipToSemicolon + Eat
        // koennen beide no-ops sein (z.B. wenn der nachfolgende Token ein
        // unerwartetes Schluesselwort ist), waehrend die Outer-Bedingung
        // diesen Token nicht als Section-Grenze akzeptiert.
        var SkipStart := FNextCount;
        T := Tok;
        if T.Kind <> tkIdent then begin Next; Continue; end;

        VarNames.Clear;
        while Tok.Kind = tkIdent do
        begin
          VarNames.Add(Next.Value);
          if not Eat(tkComma) then Break;
        end;

        TypeName := '';
        if Eat(tkColon) then
          while not (Tok.Kind in [tkSemicolon, tkEq, tkKwEnd, tkEof]) do
          begin
            // Anonymer inline-`record`-Typ als Var-Typ:
            //   var R: record A: Integer; B: Integer; end;
            // Ohne Spezial-Behandlung wuerde die Schleife beim ersten ';'
            // innerhalb des records abbrechen, der naechste Outer-Loop
            // wuerde das folgende `end` als Section-Grenze interpretieren
            // und ParseMethodImpl wuerde den Methodenrumpf verlieren.
            // Mini-Parser bis matching `end` (nested `record` zaehlt mit).
            if Tok.Kind = tkKwRecord then
            begin
              TypeName := TypeName + Tok.Value;
              Next;
              var Depth := 1;
              while (Depth > 0) and (Tok.Kind <> tkEof) do
              begin
                case Tok.Kind of
                  tkKwRecord: Inc(Depth);
                  tkKwEnd:    Dec(Depth);
                end;
                TypeName := TypeName + Tok.Value;
                Next;
              end;
              Continue;
            end;
            TypeName := TypeName + Tok.Value;
            Next;
          end;

        for VN in VarNames do
          Parent.Add(nkLocalVar, VN, T.Line, T.Col).TypeRef := TypeName;

        SkipToSemicolon;
        Eat(tkSemicolon);
        GuardAdvance(SkipStart);
      end;
    end;
  finally
    VarNames.Free;
  end;
end;

{ ---- begin ... end ---- }

procedure TParser2.ParseBlock(Parent: TAstNode);
var
  T          : TToken;
  Block      : TAstNode;
  StartCount : Integer;
begin
  T     := Tok;
  Eat(tkKwBegin);
  Block := Parent.Add(nkBlock, 'begin', T.Line, T.Col);

  while not FLex.AtEnd do
  begin
    StartCount := FNextCount;
    T := Tok;
    // Boundary-Recovery ({$ifdef}-Straddle-Merge, 2026-07-16): ein Top-Level-
    // Routine-Header auf Spalte 1 bedeutet, dass DIESER Block nie geschlossen
    // wurde (der Lexer emittiert beide {$ifdef}-Zweige -> zwei `begin`, ein
    // `end` -> der Body frisst sonst die Folge-Routinen, mormot FromVarUInt64
    // span 2407 statt ~35). Verlassen OHNE zu konsumieren: weil ParseBlock
    // REKURSIV ist, unwinden alle offenen Bloecke aufwaerts, danach parst
    // ParseImplementationSection die Routine regulaer. Begruendung + Spalte-1-
    // Gate (Schutz vor anonymen Methoden/nested routines): AtTopLevelRoutineHead.
    if AtTopLevelRoutineHead then Exit;
    case T.Kind of
      tkKwEnd                              : begin Next; Eat(tkSemicolon); Exit; end;
      tkKwElse, tkKwExcept, tkKwFinally,
      tkKwUntil, tkEof                     : Exit; // Blockgrenze – nicht konsumieren
    else
      ParseStatement(Block);
    end;
    GuardAdvance(StartCount);
  end;
end;

{ ---- Anweisung ---- }

procedure TParser2.ParseStatement(Parent: TAstNode);
// Forward-Progress-Garantie: Wenn keine der case-Branches einen Token
// konsumiert UND wir nicht an einer legitimen Block-Grenze stehen, machen
// wir am Ende einen Forced-Next. Das schuetzt vor Endlos-Loops bei
// pathologischen Eingaben (z.B. unbekannte Compiler-Direktiven mitten im
// Statement-Stream, exotische Operatoren), die sonst aus jeder ParseXxx-
// Methode unverbraucht zurueckkommen und den Aufrufer (ParseBlock,
// ParseRepeatStmt, ...) endlos schleifen lassen wuerden.
var
  T          : TToken;
  ENode      : TAstNode;
  StartCount : Integer;
begin
  StartCount := FNextCount;
  while Eat(tkSemicolon) do ; // leere Anweisungen
  T := Tok;

  case T.Kind of
    tkKwBegin    : ParseBlock(Parent);
    tkKwIf       : ParseIfStmt(Parent);
    tkKwCase     : ParseCaseStmt(Parent);
    tkKwFor      : ParseForStmt(Parent);
    tkKwWhile    : ParseWhileStmt(Parent);
    tkKwRepeat   : ParseRepeatStmt(Parent);
    tkKwTry      : ParseTryStmt(Parent);
    tkKwRaise    : ParseRaiseStmt(Parent);
    tkKwVar      : ParseInlineVarStmt(Parent);

    tkKwExit:
      begin
        ENode := Parent.Add(nkExit, 'exit', T.Line, T.Col);
        Next;
        if Eat(tkLParen) then
        begin
          // Exit(value) -> Argument-String in TypeRef ablegen.
          // Brauchen Detektoren wie TLeakDetector2.IsReturnedAsResult
          // um 'Exit(list)' als Ownership-Transfer-Return zu erkennen.
          var ExitArg := '';
          while not (Tok.Kind in [tkRParen, tkSemicolon, tkEof]) do
          begin
            if ExitArg <> '' then ExitArg := ExitArg + ' ';
            ExitArg := ExitArg + Tok.Value;
            Next;
          end;
          Eat(tkRParen);
          ENode.TypeRef := Trim(ExitArg);
        end;
        Eat(tkSemicolon);
      end;

    tkKwBreak:
      begin Parent.Add(nkBreak,    'break',    T.Line, T.Col); Next; Eat(tkSemicolon); end;
    tkKwContinue:
      begin Parent.Add(nkContinue, 'continue', T.Line, T.Col); Next; Eat(tkSemicolon); end;

    tkKwInherited:
      begin
        Next; // 'inherited' konsumieren
        // Aufrufausdruck nach 'inherited' vollstaendig erfassen, sodass
        // Detektoren z.B. 'inherited Create(self.f)' sehen koennen.
        // Parameterloses 'inherited;' bleibt mit leerem Namen.
        var CallExpr := '';
        if Tok.Kind in [tkIdent, tkKwResult] then
          CallExpr := ParsePrimary;
        Parent.Add(nkInherited, CallExpr, T.Line, T.Col);
        Eat(tkSemicolon);
      end;

    tkKwWith:
      begin
        var WithT := Next; // 'with' konsumieren
        // Ausdruck vor 'do' erfassen, damit Bezeichner im Corpus erscheinen.
        // Beispiel: with DataModule1.Query1 do  →  Node.Name = 'DataModule1 Query1'
        var WithExpr := '';
        while not (Tok.Kind in [tkKwDo, tkKwBegin, tkKwEnd, tkEof]) do
        begin
          // tkKwResult mit aufnehmen: 'Result' ist ein Keyword-Token, kein
          // tkIdent. Ohne das landet 'with Result do' mit leerem WithExpr im
          // AST und Detektoren (SCA121) sehen das Result-Write nicht.
          // Konsistent mit den uebrigen Parse-Stellen (tkIdent, tkKwResult).
          if Tok.Kind in [tkIdent, tkKwResult] then
          begin
            if WithExpr <> '' then WithExpr := WithExpr + ' ';
            WithExpr := WithExpr + Tok.Value;
          end;
          Next;
        end;
        Eat(tkKwDo);
        var WithNode := Parent.Add(nkCall, WithExpr, WithT.Line, WithT.Col);
        ParseStatement(WithNode);
      end;

    tkKwAsm:
      begin
        Next;
        // Defensiv analog zur Z. 736-Korrektur: Next advanct hier
        // theoretisch immer, GuardAdvance ist Versicherung falls der
        // Lexer in einem korrupten Zustand stecken bleibt.
        while not (Tok.Kind in [tkKwEnd, tkEof]) do
        begin
          var SkipStart := FNextCount;
          Next;
          GuardAdvance(SkipStart);
        end;
        Eat(tkKwEnd);
        Eat(tkSemicolon);
      end;

    tkKwProcedure, tkKwFunction,
    tkKwConstructor, tkKwDestructor, tkKwOperator:
      begin
        // IFDEF-Body-Recovery (2026-07-04, blcksock-Muster): {$IFDEF}/
        // {$ELSE}-Twin-Bodies erzeugen im Token-Stream zwei `begin` bei
        // nur einem `end` (der Lexer skippt Direktiven als Kommentare).
        // Das eine `end` schliesst dann nur den inneren Block, und der
        // Header der NAECHSTEN Top-Level-Methode taucht mitten im noch
        // offenen Body auf - frueher wurde er als Junk konsumiert und
        // saemtliche Folge-Methoden bis Dateiende landeten als Statements
        // im Body der ersten Methode (blcksock.pas InternalCanRead).
        //
        // Recovery: ein Header mit QUALIFIZIERTEM Namen (Ident '.' Ident)
        // ist als nested routine illegal - er kann nur eine neue Top-
        // Level-Implementierung sein. Also: neue Methode direkt auf
        // Unit-Ebene (FImplNode) parsen; die offenen Aufrufer-Loops
        // laufen nach dem Return am Folge-Token normal weiter.
        //
        // KEIN Recovery (Junk-Verhalten wie der fruehere else-Zweig):
        //  - unqualifizierte Namen (`procedure Foo;` - legale nested
        //    routines gehoeren dem Deklarationsteil-Pfad in
        //    ParseMethodImpl und kommen hier gar nicht vorbei),
        //  - anonyme Methoden (`procedure(...)` ohne Namen - stehen nur
        //    in Expression-Kontexten und werden dort von den RHS-/
        //    Argument-Scannern konsumiert, nie hier dispatcht),
        //  - `procedure(...)`-TYPEN in var-Deklarationen (stehen hinter
        //    ':' und werden von den TypeName-Loops konsumiert).
        // `class procedure TFoo.X`-Header verlieren auf diesem Weg ihr
        // 'class'-Praefix (wird vorher als Junk konsumiert) - die Methode
        // selbst wird trotzdem recovert, nur ohne ';class'-Marker.
        var KwTok := Next; // Routine-Keyword konsumieren (Lookahead-Ersatz)
        if (FImplNode <> nil) and (Tok.Kind = tkIdent) then
        begin
          var Name1 := Next.Value; // Klassen-Name-Kandidat
          if Tok.Kind = tkDot then
          begin
            FResumeHeaderPending := True;
            FResumeKwTok         := KwTok;
            FResumeName1         := Name1;
            ParseMethodImpl(FImplNode);
            Exit;
          end;
        end;
        Eat(tkSemicolon); // Junk-Pfad: Paritaet zum frueheren else-Zweig
      end;

    tkKwEnd, tkKwElse, tkKwExcept, tkKwFinally,
    tkKwUntil, tkEof: ; // Blockgrenzen – nichts tun

  else
    // Track B1 (Konzept_StrukturellePhase 2026-07-12): 'write'/'read' sind
    // Standard-Routinen die der Lexer als tkKwWrite/tkKwRead klassifiziert.
    // Am Statement-Anfang sind sie ein Call (Write(A,B,C);) - ohne Dispatch wurde
    // nur das erste Arg als Bogus-nkCall geparst, der Rest via SkipToSemicolon
    // verschluckt (Body-Attachment-Luecke -> SCA054/SCA166-Blindstellen).
    if T.Kind in [tkIdent, tkKwResult, tkKwWrite, tkKwRead] then
      ParseCallOrAssign(Parent)
    else
    begin
      Next; Eat(tkSemicolon);
    end;
  end;

  // Forward-Progress-Garantie: stagniert die Token-Position und stehen wir
  // nicht an einer legitimen Block-Grenze, einen Token zwangsweise konsumieren.
  // Verhindert Endlos-Loops in den ParseBlock/ParseRepeatStmt-while-Schleifen.
  if (FNextCount = StartCount) and
     not (Tok.Kind in [tkKwEnd, tkKwElse, tkKwExcept, tkKwFinally,
                       tkKwUntil, tkEof]) then
    Next;
end;

{ ---- if ... then ... else ---- }

procedure TParser2.ParseIfStmt(Parent: TAstNode);
var
  T        : TToken;
  IfNode   : TAstNode;
  CondText : string;
begin
  T      := Next; // 'if'
  IfNode := Parent.Add(nkIfStmt, 'if', T.Line, T.Col);

  // Bedingungstext zwischen 'if' und 'then' erfassen
  // (fuer Guards bei NilDeref / DivByZero noetig).
  CondText := '';
  while not (Tok.Kind in [tkKwThen, tkKwEnd, tkEof]) do
  begin
    if Tok.Kind = tkStrLit then
      CondText := CondText + '''' + Tok.Value + ''''
    else
      CondText := CondText + Tok.Value;
    CondText := CondText + ' ';
    Next;
  end;
  IfNode.TypeRef := Trim(CondText);

  Eat(tkKwThen);
  ParseStatement(IfNode);
  if Tok.Kind = tkKwElse then
  begin
    Next;
    var ElseNode := IfNode.Add(nkElseBranch, 'else', Tok.Line, Tok.Col);
    ParseStatement(ElseNode);
  end;
end;

{ ---- case ... of ---- }

procedure TParser2.ParseCaseStmt(Parent: TAstNode);
// Hang-Schutz: alle inneren Loops mit GuardAdvance UND vollstaendigen
// Block-Boundary-Stop-Sets. ParseStatement.Forward-Progress fasst tkKwEnd/
// tkKwElse/tkKwExcept/tkKwFinally/tkKwUntil/tkEof als "Block-Boundary" auf
// und verzichtet dort auf den forced Next - wenn die umgebende Schleife
// diese Boundaries nicht alle als Exit-Bedingung listet, spint sie ohne
// Next-Call (Watchdog feuert nicht). Fuer mORMot's geschachtelte
// case/if-else-Bloeke real reproduzierbar.
var
  T        : TToken;
  CaseNode : TAstNode;
  ArmNode  : TAstNode;
  ArmStart : Integer;
begin
  T        := Next; // 'case'
  CaseNode := Parent.Add(nkCaseStmt, 'case', T.Line, T.Col);
  SkipTo([tkKwOf, tkEof]);
  Eat(tkKwOf);

  // AtTopLevelRoutineHead: Boundary-Recovery muss auch durch einen offenen
  // case-Frame nach oben unwinden koennen (sonst greift sie bei {$ifdef}-
  // Straddle-Merges nicht, deren Body ein case enthaelt).
  while not ((Tok.Kind in [tkKwEnd, tkKwElse, tkKwExcept, tkKwFinally,
                           tkKwUntil, tkEof]) or AtTopLevelRoutineHead) do
  begin
    ArmStart := FNextCount;
    ArmNode := CaseNode.Add(nkCaseArm, '', Tok.Line, Tok.Col);
    SkipTo([tkColon, tkKwEnd, tkKwElse, tkEof]);
    Eat(tkColon);
    ParseStatement(ArmNode);
    GuardAdvance(ArmStart);
  end;

  if Eat(tkKwElse) then
  begin
    var ElseArm := CaseNode.Add(nkCaseArm, 'else', Tok.Line, Tok.Col);
    while not ((Tok.Kind in [tkKwEnd, tkKwExcept, tkKwFinally,
                             tkKwUntil, tkEof]) or AtTopLevelRoutineHead) do
    begin
      var ElseStart := FNextCount;
      ParseStatement(ElseArm);
      GuardAdvance(ElseStart);
    end;
  end;

  Eat(tkKwEnd);
  Eat(tkSemicolon);
end;

{ ---- for ---- }

procedure TParser2.ParseForStmt(Parent: TAstNode);
var
  T       : TToken;
  ForNode : TAstNode;
  Header  : string;
begin
  T       := Next; // 'for'
  ForNode := Parent.Add(nkForStmt, 'for', T.Line, T.Col);

  // Inline-Schleifenvariable: 'for var x[: T] in/:= ... do'
  // Damit auch leaky-Schleifenvariablen vom Detektor gesehen werden.
  if Tok.Kind = tkKwVar then
  begin
    Next; // 'var'
    if Tok.Kind = tkIdent then
    begin
      var VarTok  := Next;
      var VarType := '';
      if Eat(tkColon) then
        while not (Tok.Kind in [tkKwIn, tkAssign, tkKwDo, tkEof]) do
        begin
          if VarType <> '' then VarType := VarType + ' ';
          VarType := VarType + Tok.Value;
          Next;
        end;
      ForNode.Add(nkLocalVar, VarTok.Value,
        VarTok.Line, VarTok.Col).TypeRef := VarType;
    end;
  end;

  // Header-Tokens (Loop-Variable + Range) in TypeRef joinen analog zu
  // ParseWhileStmt - sonst sehen Detektoren wie uUnusedLocal die Loop-
  // Variable nicht und melden 'for k := ...' als unused-k.
  Header := ForNode.TypeRef;                           // ggf. von Inline-var
  while not (Tok.Kind in [tkKwDo, tkEof]) do
  begin
    if Header <> '' then Header := Header + ' ';
    Header := Header + Tok.Value;
    Next;
  end;
  ForNode.TypeRef := Header;

  Eat(tkKwDo);
  ParseStatement(ForNode);
end;

{ ---- while ---- }

procedure TParser2.ParseWhileStmt(Parent: TAstNode);
var
  T         : TToken;
  WhileNode : TAstNode;
  Cond      : string;
begin
  T         := Next; // 'while'
  WhileNode := Parent.Add(nkWhileStmt, 'while', T.Line, T.Col);
  // Frueher: `SkipTo([tkKwDo, tkEof])` - die Condition wurde verworfen
  // und stand im AST nirgends. Detektoren wie uNilComparison konnten
  // `while x <> nil do` nie finden. Jetzt joinen wir die Tokens zwischen
  // `while` und `do` in WhileNode.TypeRef - analog zur RHS-Behandlung
  // bei nkAssign (Z. 1611-1614).
  Cond := '';
  while not (Tok.Kind in [tkKwDo, tkEof]) do
  begin
    if Tok.Kind = tkStrLit then
      JoinTokInto(Cond, QuoteStrLit(Tok.Value))
    else
      JoinTokInto(Cond, Tok.Value);
    Next;
  end;
  WhileNode.TypeRef := Cond;
  Eat(tkKwDo);
  ParseStatement(WhileNode);
end;

{ ---- repeat ... until ---- }

procedure TParser2.ParseRepeatStmt(Parent: TAstNode);
var
  T          : TToken;
  RepeatNode : TAstNode;
  BodyStart  : Integer;
begin
  T          := Next; // 'repeat'
  RepeatNode := Parent.Add(nkRepeatStmt, 'repeat', T.Line, T.Col);
  // AtTopLevelRoutineHead: Boundary-Recovery auch durch einen offenen repeat-
  // Frame nach oben unwinden lassen (sonst greift sie bei Straddle-Merges nicht,
  // deren Body ein repeat enthaelt - z.B. mormot FromVarUInt64).
  while not ((Tok.Kind in [tkKwUntil, tkKwEnd, tkKwElse,
                           tkKwExcept, tkKwFinally, tkEof])
             or AtTopLevelRoutineHead) do
  begin
    BodyStart := FNextCount;
    ParseStatement(RepeatNode);
    GuardAdvance(BodyStart);
  end;
  // Boundary-Recovery: hat die Loop wegen AtTopLevelRoutineHead abgebrochen,
  // MUSS hier ohne Konsum raus. SkipToSemicolon stoppt NICHT an Routine-
  // Keywords und wuerde den recoverten Header samt halber Folge-Routine bis
  // zum naechsten ';' fressen -> die Routine verschwaende ganz aus dem AST
  // (schlechter als ohne Recovery). Der Aufrufer (ParseBlock/Frame-Loop)
  // sieht den Header dann selbst und unwindet weiter.
  if AtTopLevelRoutineHead then Exit;
  Eat(tkKwUntil);
  SkipToSemicolon;
  Eat(tkSemicolon);
end;

{ ---- try ... except / finally ---- }

procedure TParser2.ParseTryStmt(Parent: TAstNode);
var
  T       : TToken;
  TryNode : TAstNode;
  TmpBlk  : TAstNode;
begin
  T := Next; // 'try'

  // Try-Rumpf in temporären Block lesen
  TmpBlk := TAstNode.Create(nkBlock, '__try_body__', T.Line, T.Col);
  try
    // AtTopLevelRoutineHead: Boundary-Recovery muss auch durch einen offenen
    // try-Frame unwinden. Hinweis: feuert sie hier, folgt weder except noch
    // finally -> TmpBlk wird (wie bei jedem malformed try) verworfen. Das ist
    // akzeptiert: die Methode war durch den Straddle-Merge ohnehin kaputt, und
    // ohne Unwind wuerden ALLE Folge-Routinen mit-korrumpiert.
    while not ((Tok.Kind in [tkKwExcept, tkKwFinally,
                             tkKwEnd, tkKwElse, tkKwUntil, tkEof])
               or AtTopLevelRoutineHead) do
    begin
      var TryBodyStart := FNextCount;
      ParseStatement(TmpBlk);
      GuardAdvance(TryBodyStart);
    end;

    if Tok.Kind = tkKwExcept then
    begin
      TryNode := Parent.Add(nkTryExcept, 'try', T.Line, T.Col);
      TryNode.AdoptChildrenFrom(TmpBlk);

      var ExTok  := Next; // 'except' – Zeile des except-Schlüsselworts
      var ExNode := TryNode.Add(nkExceptBlock, 'except', ExTok.Line, ExTok.Col);

      while not ((Tok.Kind in [tkKwEnd, tkKwElse, tkKwFinally,
                               tkKwUntil, tkEof])
                 or AtTopLevelRoutineHead) do   // Boundary-Recovery unwinden
      begin
        var ExceptStart := FNextCount;
        if Tok.Kind = tkKwOn then
        begin
          var OnT    := Next;
          var OnNode := ExNode.Add(nkOnHandler, '', OnT.Line, OnT.Col);
          if Tok.Kind = tkIdent then
          begin
            var LabelOrType := Next.Value;
            if Eat(tkColon) then
            begin
              OnNode.Name    := LabelOrType;
              OnNode.TypeRef := '';
              while not (Tok.Kind in [tkKwDo, tkSemicolon, tkEof]) do
              begin
                OnNode.TypeRef := OnNode.TypeRef + Tok.Value;
                Next;
              end;
            end
            else
              OnNode.TypeRef := LabelOrType;
            Eat(tkKwDo);
            ParseStatement(OnNode);
          end;
          Eat(tkSemicolon);
        end
        else
          ParseStatement(ExNode);
        GuardAdvance(ExceptStart);
      end;
      // Real-World-FP-Audit 2026-07-12 (SCA133): der 'else'-Default-Handler eines
      // except-Blocks ('except on..do..; else <stmts> end') gehoert ZUM Handler -
      // die aktuelle Exception ist dort aktiv, ein bare 'raise;' ist ein gueltiger
      // Re-Raise. Frueher stoppte die Schleife bei tkKwElse -> die else-Statements
      // entkamen dem nkExceptBlock in den umschliessenden Block (InHandler=False
      // -> SCA133-FP + Folge-Fehlparse des 'end'). Jetzt als ExNode-Kinder parsen.
      if Tok.Kind = tkKwElse then
      begin
        Next;  // 'else'
        while not ((Tok.Kind in [tkKwEnd, tkKwFinally, tkKwUntil, tkEof])
                   or AtTopLevelRoutineHead) do   // Boundary-Recovery unwinden
        begin
          var ElseStart := FNextCount;
          ParseStatement(ExNode);
          GuardAdvance(ElseStart);
        end;
      end;
    end
    else if Tok.Kind = tkKwFinally then
    begin
      TryNode := Parent.Add(nkTryFinally, 'try', T.Line, T.Col);
      TryNode.AdoptChildrenFrom(TmpBlk);

      var FinTok  := Next; // 'finally' – Zeile des finally-Schlüsselworts
      var FinNode := TryNode.Add(nkFinallyBlock, 'finally', FinTok.Line, FinTok.Col);
      while not ((Tok.Kind in [tkKwEnd, tkKwElse, tkKwExcept,
                               tkKwUntil, tkEof])
                 or AtTopLevelRoutineHead) do   // Boundary-Recovery unwinden
      begin
        var FinStart := FNextCount;
        ParseStatement(FinNode);
        GuardAdvance(FinStart);
      end;
    end
    else
    begin
      // Weder except noch finally: der try-Frame ist abgebrochen - entweder
      // malformed try, oder (haeufiger) die Boundary-Recovery hat die Body-
      // Schleife wegen AtTopLevelRoutineHead verlassen. Die bereits geparsten
      // Body-Statements NICHT verwerfen, sondern in den umgebenden Block
      // adoptieren: sonst verschwindet realer Code aus dem AST und Statement-
      // Detektoren hoeren still auf zu feuern (A/B-Fund Runde 2: SCA139
      // 'List.Free' in CnWizIdeUtils.GetLibraryPath, SCA126 u.a. - der reine
      // Zaehler-Delta verdeckte das). Verlust ist immer schlechter als eine
      // ungenaue Zuordnung: die Statements sind real und gehoeren analysiert.
      Parent.AdoptChildrenFrom(TmpBlk);
    end;
  finally
    TmpBlk.Free;
  end;

  Eat(tkKwEnd);
  Eat(tkSemicolon);
end;

{ ---- raise ---- }

procedure TParser2.ParseRaiseStmt(Parent: TAstNode);
var
  T         : TToken;
  RaiseNode : TAstNode;
begin
  T         := Next; // 'raise'
  RaiseNode := Parent.Add(nkRaise, 'raise', T.Line, T.Col);
  if not (Tok.Kind in [tkSemicolon, tkKwEnd, tkKwElse, tkEof]) then
    RaiseNode.Name := ParsePrimary;
  Eat(tkSemicolon);
end;

{ ---- Inline-Var-Anweisung (Delphi 10.3+: 'var x[: T] [:= init];' im Rumpf) ---- }

procedure TParser2.ParseInlineVarStmt(Parent: TAstNode);
// Mid-block-var. Erzeugt fuer jeden deklarierten Bezeichner einen
// nkLocalVar-Knoten (mit Typ, falls angegeben). Der optionale Initializer
// wird zusaetzlich als nkAssign auf den ersten Bezeichner abgelegt - damit
// der Leak-Detektor 'var lst: TStringList := TStringList.Create;' analog zu
// klassischer Variablen-Sektion + Zuweisung sieht.
var
  T        : TToken;
  Names    : TStringList;
  TypeName : string;
  N        : string;
begin
  T := Next; // 'var' konsumieren

  Names := TStringList.Create;
  try
    while Tok.Kind = tkIdent do
    begin
      Names.Add(Next.Value);
      if not Eat(tkComma) then Break;
    end;

    // Optional ': Typname' - bis Init / Statement-Ende lesen
    TypeName := '';
    if Eat(tkColon) then
      while not (Tok.Kind in [tkAssign, tkSemicolon, tkKwEnd,
                              tkKwElse, tkKwUntil, tkKwExcept,
                              tkKwFinally, tkEof]) do
      begin
        if TypeName <> '' then TypeName := TypeName + ' ';
        TypeName := TypeName + Tok.Value;
        Next;
      end;

    // nkLocalVar pro Bezeichner anlegen (gleiche Position wie 'var').
    for N in Names do
      Parent.Add(nkLocalVar, N, T.Line, T.Col).TypeRef := TypeName;

    // Optionaler Initializer
    if Eat(tkAssign) then
    begin
      var FullRHS   := '';
      var NestDepth := 0;
      while not FLex.AtEnd do
      begin
        case Tok.Kind of
          // [8] (Core-Audit 2026-07-17): case/try/asm oeffnen einen mit 'end'
          // schliessenden Block und muessen wie 'begin' die Tiefe erhoehen -
          // sonst zieht ihr 'end' NestDepth unter die Block-Ebene und der
          // Initializer-Scan bricht bei anonymer Methode mit case/try-Body
          // vorzeitig ab (RHS-Truncation -> Folge-Tokens werden fehl-geparst).
          tkLParen, tkLBracket, tkKwBegin,
          tkKwCase, tkKwTry, tkKwAsm      : Inc(NestDepth);
          tkRParen, tkRBracket            : if NestDepth > 0 then Dec(NestDepth);
          tkKwEnd:
            if NestDepth > 0 then Dec(NestDepth) else Break;
          tkSemicolon, tkKwElse, tkKwUntil,
          tkKwExcept, tkKwFinally, tkEof:
            if NestDepth = 0 then Break;
        end;
        if Tok.Kind = tkStrLit then
          JoinTokInto(FullRHS, QuoteStrLit(Tok.Value))
        else
          JoinTokInto(FullRHS, Tok.Value);
        Next;
      end;

      if Names.Count > 0 then
      begin
        var ANode := Parent.Add(nkAssign, Names[0], T.Line, T.Col);
        ANode.TypeRef := FullRHS;
      end;
    end;

    Eat(tkSemicolon);
  finally
    Names.Free;
  end;
end;

{ ---- Zuweisung oder Prozeduraufruf ---- }

procedure TParser2.ParseCallOrAssign(Parent: TAstNode);

  function IsSimpleLabelName(const S: string): Boolean;
  // True wenn S ein reiner Label-Bezeichner ist (Ident oder Ganzzahl), also
  // KEIN Member-/Index-/Deref-/Call-Ausdruck (kein . [ ^ ( im Text). Nur dann
  // ist ein folgendes ':' ein Label-Target und keine andere Konstruktion.
  var i: Integer;
  begin
    Result := S <> '';
    for i := 1 to Length(S) do
      if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
        Exit(False);
  end;

var
  T    : TToken;
  LHS  : string;
  Node : TAstNode;
begin
  T   := Tok;
  LHS := ParsePrimary;

  // Track B2 (Konzept_StrukturellePhase, re-apply 5039b68): Label-Target
  // 'done:' / '1:' in Anweisungsposition. Sonst liefert ParsePrimary LHS='done',
  // Tok=tkColon (nicht tkAssign) -> else-Zweig macht nkCall('done') + das
  // folgende SkipToSemicolon verschluckt die MARKIERTE Folgeanweisung restlos
  // ('done: Result := X;' verliert 'Result := X' -> SCA121/166/011 feuern auf
  // gedroppter Sicht). Jetzt: ':' konsumieren, markierte Anweisung normal parsen.
  // Eindeutig: ':=' ist tkAssign; case-Arms laufen ueber ParseCaseStmt -> ein
  // tkColon nach reinem Ident/IntLit ist hier ein Label.
  if (Tok.Kind = tkColon) and IsSimpleLabelName(LHS) then
  begin
    Next;                    // ':' konsumieren
    ParseStatement(Parent);  // markierte Anweisung parsen (behandelt eigenes ';')
    Exit;
  end;

  if Tok.Kind = tkAssign then
  begin
    Next; // ':=' konsumieren
    // Gesamten RHS-Ausdruck bis zum nächsten ';' / 'end' erfassen.
    // Wichtig: '+'-Verkettungen, Klammern und Zeichenketten vollständig mitladen.
    var FullRHS := '';
    var NestDepth := 0;
    while not FLex.AtEnd do
    begin
      case Tok.Kind of
        // [8] (Core-Audit 2026-07-17): case/try/asm oeffnen einen mit 'end'
        // schliessenden Block - wie 'begin' Tiefe erhoehen, sonst bricht der
        // RHS-Scan bei anonymen Methoden mit case/try-Body vorzeitig ab
        // (das case-'end' zog NestDepth unter die begin-Ebene -> Truncation).
        tkLParen, tkLBracket, tkKwBegin,
        tkKwCase, tkKwTry, tkKwAsm      : Inc(NestDepth);
        tkRParen, tkRBracket            : if NestDepth > 0 then Dec(NestDepth);
        // 'end' schliesst entweder einen offenen Block (Anonyme Methode:
        //   x := function: T begin ... end;) oder beendet die RHS auf
        // oberster Ebene.
        tkKwEnd:
          if NestDepth > 0 then Dec(NestDepth) else Break;
        // RHS endet auch an else/until/except/finally - eine Zuweisung im
        // THEN-Zweig hat keinen ';' vor dem else, sonst wuerde der else-Zweig
        // verschluckt und das end;-Zaehlen geht schief.
        tkSemicolon, tkKwElse, tkKwUntil,
        tkKwExcept, tkKwFinally, tkEof:
          if NestDepth = 0 then Break;
      end;
      if Tok.Kind = tkStrLit then
        JoinTokInto(FullRHS, QuoteStrLit(Tok.Value))
      else
        JoinTokInto(FullRHS, Tok.Value);
      Next;
    end;
    Node         := Parent.Add(nkAssign, LHS, T.Line, T.Col);
    Node.TypeRef := FullRHS;
  end
  else
    Parent.Add(nkCall, LHS, T.Line, T.Col);

  SkipToSemicolon;
  Eat(tkSemicolon);
end;

{ ---- Primärausdruck (vereinfacht) ---- }

function TParser2.ParsePrimary: string;
var
  S: string;
begin
  S := '';

  if Tok.Kind in [tkIdent, tkKwResult, tkKwInherited,
                  tkKwNil, tkKwTrue, tkKwFalse, tkKwString,
                  tkKwWrite, tkKwRead] then   // Track B1: Write/Read als Call-Primary
    S := Next.Value
  else if Tok.Kind in [tkIntLit, tkFloatLit] then
    S := Next.Value
  else if Tok.Kind = tkStrLit then
    S := QuoteStrLit(Next.Value)
  else
  begin
    Result := '';
    Exit;
  end;

  // Member-Zugriff, Index, Dereferenz, Aufruf
  while True do
  begin
    case Tok.Kind of
      tkDot:
        begin
          Next;
          if Tok.Kind = tkIdent then
            S := S + '.' + Next.Value;
        end;
      tkLBracket:
        begin
          Next;
          SkipTo([tkRBracket, tkEof]);
          Eat(tkRBracket);
          S := S + '[]';
        end;
      tkCaret:
        begin Next; S := S + '^'; end;
      tkLParen:
        begin
          Next; // '(' konsumieren
          var Args  := '';
          var Depth := 1;
          // [7] (Core-Audit 2026-07-17): JoinTokInto statt roher Konkatenation.
          // Der RHS-Scanner in ParseCallOrAssign trennt Wortgrenzen korrekt,
          // dieser Argument-Scanner tat es NICHT - 'DoIt(a div b)' kollabierte
          // zu 'DoIt(adivb)', 'Check(x as IFoo)' zu 'Check(xasIFoo)'. Detektoren
          // die via Pos(' div ', ...) / Pos(' as ', ...) auf nkCall.Name pruefen
          // (uDivByZero/uSQLInjection) verloren dadurch den Treffer. JoinTokInto
          // setzt nur zwischen zwei Ident-Zeichen ein Space - Klammern/Operatoren
          // bleiben unveraendert, also identisch fuer die '('/')'-Tokens.
          while not FLex.AtEnd do
          begin
            var ArgTok := Tok;
            if ArgTok.Kind = tkLParen then
            begin
              Inc(Depth);
              JoinTokInto(Args, ArgTok.Value);
              Next;
            end
            else if ArgTok.Kind = tkRParen then
            begin
              Dec(Depth);
              if Depth = 0 then begin Next; Break; end;
              JoinTokInto(Args, ArgTok.Value);
              Next;
            end
            else
            begin
              if ArgTok.Kind = tkStrLit then
                JoinTokInto(Args, QuoteStrLit(ArgTok.Value))
              else
                JoinTokInto(Args, ArgTok.Value);
              Next;
            end;
          end;
          S := S + '(' + Args + ')';
        end;
    else
      Break;
    end;
  end;

  Result := S;
end;

end.
