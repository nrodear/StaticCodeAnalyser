unit uParser2;

// Rekursiver Abstiegs-Parser für Delphi-Quelltexte.
// Erzeugt einen TAstNode-Baum (uAstNode) aus einem Token-Stream (uLexer).
// Unbekannte Konstrukte werden übersprungen – kein unkontrollierter Absturz.

interface

uses
  System.SysUtils, System.Classes,
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

{ Methoden-Direktiven nach dem Semikolon }
function IsMethodDirective(K: TTokenKind): Boolean;
begin
  Result := K in [tkKwOverride, tkKwVirtual, tkKwAbstract, tkKwOverload,
                  tkKwReintroduce, tkKwForward, tkKwDeprecated, tkKwStatic,
                  tkKwInline, tkKwExternal, tkKwRead, tkKwWrite];
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
  try
    FNextCount := 0; // Watchdog pro Datei zuruecksetzen
    Root := TAstNode.Create(nkUnit, '', 1, 1);
    try
      try
        ParseUnit(Root);
      except
        on E: Exception do
          // Parser-Fehler nie nach aussen lassen, aber den Aufrufer informieren
          // wenn die Watchdog-Bremse griff (sonst wuerde der Detector mit
          // unvollstaendigem AST weitermachen, was zusaetzliche Crashes geben kann).
          if Pos('Parser-Watchdog', E.Message) > 0 then
            raise;
      end;
    except
      // Watchdog (oder andere durchgereichte Exception): unvollstaendigen
      // AST-Baum freigeben, sonst leakt der bei jedem Watchdog-Treffer.
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
      tkKwEnd : begin Next; Eat(tkDot); Exit; end;
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
      tkKwInitialization, tkKwFinalization,
      tkKwEnd, tkEof                        : Exit;
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
        var AliasContent := '';
        while not (Tok.Kind in [tkSemicolon, tkKwEnd, tkEof]) do
        begin
          if Tok.Kind = tkIdent then
          begin
            if AliasContent <> '' then AliasContent := AliasContent + ' ';
            AliasContent := AliasContent + Tok.Value;
          end;
          Next;
        end;
        var ANode := SecNode.Add(nkTypeAlias, Name, T.Line, T.Col);
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
        if Parents <> '' then Parents := Parents + ' ';
        Parents := Parents + Tok.Value;
      end;
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
  T        := Next; // procedure / function / constructor / destructor
  MethKind := T.Value;
  MethName := '';

  if Tok.Kind = tkIdent then
  begin
    MethName := Next.Value;
    // Klassen-Generic-Param zwischen Klassen-Name und Methoden-Name:
    //   procedure TFoo<T>.Bar;     <- nach 'TFoo' kommt '<T>' vor '.'
    SkipGenericParams;
    if Tok.Kind = tkDot then
    begin
      Next;
      if Tok.Kind = tkIdent then
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
            PType := PType + Tok.Value;
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
      RetType := RetType + Tok.Value;
      Next;
    end;
    MNode.TypeRef := MethKind + ':' + RetType;
  end;

  Eat(tkSemicolon);
  ParseMethodDirectives(MNode);
end;

{ ---- Methoden-Direktiven überspringen ---- }

procedure TParser2.ParseMethodDirectives(MNode: TAstNode);
// Konsumiert alle Method-Direktiven (virtual, abstract, override, ...).
// Wenn MNode gegeben ist, werden die Direktiven case-erhaltend an
// MNode.TypeRef angehaengt - im Format `'kind[:ret];dir1;dir2'`.
// Detektoren (uVirtualCallInCtor) lesen das via SplitDirectives.
var
  DirKind : TTokenKind;
begin
  while IsMethodDirective(Tok.Kind) do
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

procedure TParser2.ParseMethodImpl(Parent: TAstNode);
var
  MNode : TAstNode;
begin
  ParseMethodSignature(Parent);

  if Parent.Children.Count = 0 then Exit;
  MNode := Parent.Children.Last;
  if MNode.Kind <> nkMethod then Exit;

  ParseLocalVarSection(MNode);

  if Tok.Kind = tkKwBegin then
    ParseBlock(MNode)
  else if Tok.Kind = tkKwAsm then
  begin
    Next;
    SkipTo([tkKwEnd, tkEof]);
    Eat(tkKwEnd);
    Eat(tkSemicolon);
  end
  else if Tok.Kind in [tkKwProcedure, tkKwFunction,
                       tkKwConstructor, tkKwDestructor,
                       tkKwOperator] then
  begin
    // Headless-Method ohne begin/asm direkt vor naechstem Method-Header:
    // klassischer IFDEF-Konditional-Pattern wie
    //   {$IFDEF FPC} function F: integer;
    //   {$ELSE}      function F: string;
    //   {$ENDIF}
    //   begin
    //     ...
    //   end;
    // Der Parser sieht beide Header (Lexer skippt nur Comments). Den
    // ersten Headless-Knoten entfernen, sonst erscheint die Methode
    // doppelt im AST und Detektoren melden Phantom-Duplikate.
    var Idx := Parent.Children.IndexOf(MNode);
    if Idx >= 0 then Parent.Children.Delete(Idx);
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
        while not (Tok.Kind in [tkKwVar, tkKwConst, tkKwBegin, tkKwAsm,
                                 tkKwEnd, tkEof]) do
        begin
          var SkipStart := FNextCount;
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
                              tkKwBegin, tkKwAsm, tkKwEnd, tkEof]) do
      begin
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
          SkipTo([tkRParen, tkSemicolon, tkEof]);
          Eat(tkRParen);
        end;
        Eat(tkSemicolon);
        ENode.Name := 'exit'; // verhindert Hint "ENode assigned but never used"
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
          if Tok.Kind = tkIdent then
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

    tkKwEnd, tkKwElse, tkKwExcept, tkKwFinally,
    tkKwUntil, tkEof: ; // Blockgrenzen – nichts tun

  else
    if T.Kind in [tkIdent, tkKwResult] then
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

  while not (Tok.Kind in [tkKwEnd, tkKwElse, tkKwExcept, tkKwFinally,
                          tkKwUntil, tkEof]) do
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
    while not (Tok.Kind in [tkKwEnd, tkKwExcept, tkKwFinally,
                            tkKwUntil, tkEof]) do
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

  SkipTo([tkKwDo, tkEof]);
  Eat(tkKwDo);
  ParseStatement(ForNode);
end;

{ ---- while ---- }

procedure TParser2.ParseWhileStmt(Parent: TAstNode);
var
  T         : TToken;
  WhileNode : TAstNode;
begin
  T         := Next; // 'while'
  WhileNode := Parent.Add(nkWhileStmt, 'while', T.Line, T.Col);
  SkipTo([tkKwDo, tkEof]);
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
  while not (Tok.Kind in [tkKwUntil, tkKwEnd, tkKwElse,
                           tkKwExcept, tkKwFinally, tkEof]) do
  begin
    BodyStart := FNextCount;
    ParseStatement(RepeatNode);
    GuardAdvance(BodyStart);
  end;
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
    while not (Tok.Kind in [tkKwExcept, tkKwFinally,
                             tkKwEnd, tkKwElse, tkKwUntil, tkEof]) do
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

      while not (Tok.Kind in [tkKwEnd, tkKwElse, tkKwFinally,
                               tkKwUntil, tkEof]) do
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
    end
    else if Tok.Kind = tkKwFinally then
    begin
      TryNode := Parent.Add(nkTryFinally, 'try', T.Line, T.Col);
      TryNode.AdoptChildrenFrom(TmpBlk);

      var FinTok  := Next; // 'finally' – Zeile des finally-Schlüsselworts
      var FinNode := TryNode.Add(nkFinallyBlock, 'finally', FinTok.Line, FinTok.Col);
      while not (Tok.Kind in [tkKwEnd, tkKwElse, tkKwExcept,
                               tkKwUntil, tkEof]) do
      begin
        var FinStart := FNextCount;
        ParseStatement(FinNode);
        GuardAdvance(FinStart);
      end;
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
          tkLParen, tkLBracket, tkKwBegin : Inc(NestDepth);
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
var
  T    : TToken;
  LHS  : string;
  Node : TAstNode;
begin
  T   := Tok;
  LHS := ParsePrimary;

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
        tkLParen, tkLBracket, tkKwBegin : Inc(NestDepth);
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
                  tkKwNil, tkKwTrue, tkKwFalse, tkKwString] then
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
          while not FLex.AtEnd do
          begin
            var ArgTok := Tok;
            if ArgTok.Kind = tkLParen then
            begin
              Inc(Depth);
              Args := Args + ArgTok.Value;
              Next;
            end
            else if ArgTok.Kind = tkRParen then
            begin
              Dec(Depth);
              if Depth = 0 then begin Next; Break; end;
              Args := Args + ArgTok.Value;
              Next;
            end
            else
            begin
              if ArgTok.Kind = tkStrLit then
                Args := Args + QuoteStrLit(ArgTok.Value)
              else
                Args := Args + ArgTok.Value;
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
