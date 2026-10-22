unit uRdxSqlFacts;

// reDelphix - die Fakten am Quelltext zur SQL-Vorlage (Rezept 5.2, SCA003).
// Bis zur Folgewelle des Wochen-Reviews (G01-03) der hintere Teil von
// uRdxSqlTemplate. Reine Textlogik ohne ToolsAPI - laeuft im
// FPC-Pruefstand.
//
// VERTRAG
//   AddSqlFacts setzt die Fakten einer Anfrage (TRdxSqlRequest.Consts,
//   Binding, Prefix, ChainNames) aus dem Text der Datei (TRdxCodeMap).
//   BuildSqlTemplate liest nur die Anfrage und fragt den Quelltext nie.
//   Was die Fakten bedeuten, steht im Kopf von uRdxSqlTemplate - Punkt 2
//   (Konstanten und ihre Sichtbarkeit) und Punkt 3 (Ziel: FireDAC, ADO,
//   die Kette Q.SQL.Add); "uRdxSqlTemplate, Punkt N" in den Kommentaren
//   meint jenen Kopf. Ein Fakt steht nur, wenn er bewiesen ist: eine
//   Deklaration anderer Art, ein Lauf ueber MAX_WALK oder ein with-Block
//   lassen den Stand ohne Fakten: der Operand bleibt Operand, ExecSQL hat
//   keinen Kanal, ADO bekommt ParamByName, es gibt keine Kette. Ein
//   falscher Beweis waere schlimmer: ein geerbtes Member, das als
//   Konstante gilt, bliebe als Verkettung im SQL-Text.
//
// INHALT
//   Die Deklarationen eines Namens (DeclsOf), die Grenzen der Datei aus
//   EINEM Lauf (BuildScopes: Routinen mit Rumpf, Typrumpfe), die
//   Sichtbarkeit (ScopeOf, VisibleAt, geerbte Member InheritsForeign), der
//   Konstanten-Beweis (SqlConstOf), die Empfaenger-Nachweise
//   (FireDacConnectionProven, AdoObjectProven) und die Kette Q.SQL.Add
//   (ChainWith).
//
// WARUM DER SCHNITT HIER LIEGT
//   Der SQL-Leser in uRdxSqlTemplate arbeitet auf dem SQL-Text der Kette
//   (Literale, Token, Zustandsautomat); dieser Teil arbeitet auf dem
//   Pascal-Quelltext der Datei (Token-Laeufe, Bloecke, uRdxBlocks). Die
//   Schnittstelle trennte beides schon - BuildSqlTemplate nimmt fertige
//   Fakten, die Nachweise haben eigene Tests (uTestRdxSqlFacts). Wer die
//   Kette oder die Sichtbarkeit aendert, uebersetzt und prueft so den
//   Leser nicht mit, und der Konstanten- und Empfaenger-Beweis steht
//   anderen Rezepten offen. Die Abhaengigkeit laeuft in EINE Richtung:
//   uRdxSqlFacts nutzt uRdxSqlTemplate (die Anfrage, SqlPlaceholders,
//   SqlChainTextOf), nie umgekehrt. Den SQL-Text eines Kettenglieds rechnet
//   SqlChainTextOf in uRdxSqlTemplate, weil dessen Marke fuer einen
//   stehenden Ausdruck der Leser dort liest - Kodierer und Leser bleiben in
//   einer Unit.

interface

uses
  uRdxCodeMap,      // TRdxCodeMap: der Quelltext der Datei
  uRdxSqlTemplate;  // TRdxSqlRequest, TRdxSqlConst: was die Fakten fuellen

// Setzt AReq.Consts (je Operand SqlConstOf an seiner Zeile, nicht im
// with-Block; Routinen- und Typgrenzen einmal fuer alle), AReq.Binding
// (FireDacConnectionProven bei einem Aufruf, AdoObjectProven beim Query-
// Objekt - beides ausserhalb eines with-Blocks) und bei 'Q.SQL.Add(..)'
// AReq.Prefix/ChainNames (die Kette, uRdxSqlTemplate, Punkt 3) - alle vier
// zuerst zurueck auf den Stand ohne Fakten.
procedure AddSqlFacts(AMap: TRdxCodeMap; var AReq: TRdxSqlRequest);
// Ist AName (ein blosser Bezeichner) an ALine eine Konstante? Jede
// Deklaration des Namens in der Datei muss eine untypisierte Konstante
// sein ('Name = Wert;' in einer const-Section; ein Parameter, eine
// Variable - auch 'var Name := ..' und 'for var Name in ..' -, ein Feld,
// eine Property, 'on Name: E do', eine typisierte Konstante, eine
// Inline-Konstante im Rumpf, ein Typ oder eine Routine gleichen Namens
// irgendwo in der Datei - auch im inaktiven $IFDEF-Zweig - verwirft den
// Beweis); gelten muss eine, die vor ALine steht und dort sichtbar ist
// (uRdxSqlTemplate, Punkt 2: Unit-Ebene ab der Deklaration - nicht in einer
// Methode einer Klasse mit Vorfahr von ausserhalb, dort kann ein geerbtes
// Member den Namen tragen -, lokal bis zum Ende ihrer Routine,
// Klassenkonstante in den Methoden ihrer Klasse). Mehrere sichtbare mit
// verschiedenem Wert: sckKept.
function SqlConstOf(AMap: TRdxCodeMap; const AName: string;
  ALine: Integer): TRdxSqlConst;
// True, wenn die uses-Klauseln FireDAC.Comp.Client nennen und AReceiver
// (ein Bezeichner, 'Self.' davor erlaubt) in der Datei mindestens einmal
// und nur als TFDConnection deklariert ist (Feld, Variable, Parameter;
// eine Property gleichen Namens verwirft den Beweis - ihr Typ wird nicht
// gelesen, Gegen-Review S1, Minor 4).
function FireDacConnectionProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
// Dasselbe fuer ADO (Minor 11): die uses nennen Data.Win.ADODB oder
// ADODB, AReceiver ist ueberall als TADOQuery, TADOCommand, TADODataSet
// oder TADOStoredProc deklariert (auch qualifiziert).
function AdoObjectProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
// 'FConn' aus 'FConn.ExecSQL', sonst ''.
function ExecSqlReceiverOf(const ATarget: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,    // PosEx
  uRefactorInfo,      // ROLE_OPERAND
  uRdxRecipes,        // DecodeLiteral, IsPlainIdent, Query-Objekt des Ziels
  uRdxBlocks;         // ReadRoutine (lokale Konstanten), HeritageOf,
                      // TypeHasBody, CLASS_MODIFIERS

const
  // Obergrenze der Token-Laeufe am Quelltext (Schutz vor Endlosschleifen).
  MAX_WALK  = 200000;
  // So vielen Vorfahren folgt InheritsForeign (R2-05) - wie
  // STRICT_MAX_ANCESTORS des strengen Resolvers im Core.
  MAX_ANCESTORS = 32;
  KW_HELPER = 'helper';

  // Deklarationen am Quelltext (SqlConstOf, FireDacConnectionProven).
  // Davor beginnt 'Name:' bzw. 'Name, ..:' eine Deklaration (Variable,
  // Feld, Parameter, typisierte Konstante, die Variable eines
  // on-Handlers; auch eine Marke oder ein case-Zweig hinter ';' zaehlt -
  // das macht den Beweis nur vorsichtiger).
  DECL_LEADS: array[0..19] of string = (';', 'var', 'const', 'threadvar',
    '(', ',', ')', 'out', 'constref', ']', 'private', 'protected', 'public',
    'published', 'automated', 'strict', 'record', 'class', 'object', 'on');
  // Hinter 'var Name' bzw. 'for var Name' steht ohne Typ ':=' oder 'in' -
  // eine Inline-Variable mit abgeleitetem Typ (Gegen-Review S1, Blocker).
  INLINE_VAR_AFTER: array[0..1] of string = (':=', 'in');
  KW_VAR = 'var';
  // Davor beginnt 'Name =' eine Konstante oder einen Typ.
  CONST_LEADS: array[0..2] of string = (';', 'const', ']');
  // Rueckwaerts von einer Deklaration: hier beginnt ihre Section.
  SECTION_STOPS: array[0..14] of string = ('const', 'var', 'type',
    'threadvar', 'resourcestring', 'label', 'begin', 'interface',
    'implementation', 'initialization', 'finalization', 'program',
    'library', 'unit', 'uses');
  // Die Units und Typen der Nachweise (TypedReceiverProven): ein Typ steht
  // bloss oder mit einer dieser Units davor.
  FIREDAC_UNITS: array[0..0] of string = ('firedac.comp.client');
  FIREDAC_TYPES: array[0..0] of string = ('tfdconnection');
  ADO_UNITS: array[0..1] of string = ('data.win.adodb', 'adodb');
  ADO_TYPES: array[0..3] of string = ('tadoquery', 'tadocommand',
    'tadodataset', 'tadostoredproc');
  EXEC_SQL = '.execsql';
  SELF_PREFIX = 'self.';
  // Die Kette 'Q.SQL.Add' (ChainWith): die Glieder hinter dem Objekt ...
  CHAIN_SQL = '.sql.';
  CHAIN_ADD   = 'add';
  CHAIN_CLEAR = 'clear';
  CHAIN_TEXT  = 'text';
  // ... und so viele Zeilen weit sucht sie je Richtung.
  MAX_CHAIN_LINES = 200;
  // Diese Glieder hinter 'Q.SQL.' lesen nur - die Kette laeuft weiter.
  CHAIN_READS: array[0..3] of string = ('text', 'count', 'beginupdate',
    'endupdate');
  // Diese Woerter oeffnen hinter '=' bzw. 'packed' einen Typ mit Rumpf.
  TYPE_KINDS: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');
  TYPE_LEADS: array[0..1] of string = ('=', 'packed');
  // Hinter 'record' in einer Typ-Einschraenkung ('<T: record>').
  CONSTRAINT_FOLLOWERS: array[0..2] of string = ('>', ',', ';');
  KW_RECORD = 'record';
  KW_CASE   = 'case';
  KW_END    = 'end';

type
  // ---- Deklarationen am Quelltext ----

  TSqlDeclKind = (dkConst, dkTyped, dkOther);

  TSqlDecl = record
    Kind : TSqlDeclKind;
    Tok  : TRdxToken;   // der Name in der Deklaration
    Text : string;      // dkConst: Quelltext des Werts; dkTyped: Typ (klein)
  end;
  TSqlDecls = TArray<TSqlDecl>;

  // Eine Routine mit Rumpf (auch verschachtelt): Kopf, Rumpf (begin bzw.
  // asm) und ihr letztes ';'; ClassLow das Klassen-Glied des Namens
  // ('TFoo.P' -> 'tfoo'), '' ohne.
  TSqlRoutine = record
    Head     : TRdxToken;
    Body     : TRdxToken;
    Last     : TRdxToken;
    ClassLow : string;
  end;

  // Ein Typ mit Rumpf (class, record, object, interface): sein Oeffner,
  // sein end und sein Name (klein, ohne Typparameter; '' anonym).
  TSqlTypeBody = record
    Open    : TRdxToken;
    Close   : TRdxToken;
    NameLow : string;
  end;

  // Die Grenzen der Datei fuer die Sichtbarkeit (uRdxSqlTemplate, Punkt 2) -
  // einmal je Anfrage gerechnet (Built), erst wenn ein Name eine
  // Konstante ist.
  TSqlScopes = record
    Built    : Boolean;
    Complete : Boolean;   // der Lauf erreichte das Dateiende (MAX_WALK)
    Routines : TArray<TSqlRoutine>;
    Types    : TArray<TSqlTypeBody>;
    // nur beim Lauf (BuildScopes): ab hier liest er Routinen (BodyStart),
    // und die Routinen, deren Rumpf noch kommt
    Start    : TRdxToken;
    Jumps    : TArray<Integer>;
  end;

  // Wo eine Konstante gilt (ScopeOf).
  TSqlConstScope = (cvUnit, cvLocal, cvClass, cvInline);

  // Ein offener Block beim Lauf durch die Datei (BuildScopes): ein Typ mit
  // Rumpf (IsType; IsRecord: dort hat 'case' kein eigenes end) oder ein
  // begin/try/case/asm.
  TSqlFrame = record
    IsType   : Boolean;
    IsRecord : Boolean;
    Open     : TRdxToken;
    NameLow  : string;
  end;

  // Eine Suche in der Kette: das Objekt (klein, ohne 'Self.') mit '.sql.',
  // die Zeilen der Anweisung und was gefunden ist.
  TSqlChain = record
    Key    : string;
    First  : Integer;
    Last   : Integer;
    Frags  : TArray<string>;   // SQL-Text der frueheren Zeilen, rueckwaerts
    Names  : TArray<string>;
  end;

  // Was an einer Stelle 'Q.SQL.<Glied>' steht.
  TSqlChainStep = (chIgnore, chFragment, chFragmentStop, chStop);

{ ---- kleine Helfer ----
  Dieselben wie in uRdxSqlTemplate; eine gemeinsame Fassung in uRdxCodeMap
  ist Review Woche G01-02 (Folgewelle). }

function CharAt(const S: string; AIndex: Integer): Char;
begin
  if (AIndex >= 1) and (AIndex <= Length(S)) then
    Result := S[AIndex]
  else
    Result := #0;
end;

function JoinWith(const AItems: TArray<string>; const ASep: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AItems) do
    begin
      if i > 0 then
        SB.Append(ASep);
      SB.Append(AItems[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---- Deklarationen am Quelltext ---- }

// Naechste Spalte ab AFrom, an der ALow (klein) als ganzes Wort im Code
// steht; 0 ohne.
function WordCol(AMap: TRdxCodeMap; ALine: Integer; const ALow: string;
  AFrom: Integer): Integer;
var
  L : string;
  c : Integer;
begin
  Result := 0;
  L := LowerCase(AMap.Raw(ALine));
  c := PosEx(ALow, L, AFrom);
  while c > 0 do
  begin
    if AMap.IsCode(ALine, c) and not IsIdentChar(CharAt(L, c - 1))
       and not IsIdentChar(CharAt(L, c + Length(ALow))) then
      Exit(c);
    c := PosEx(ALow, L, c + 1);
  end;
end;

// Der Typ hinter ':' - ein Pfad ('TFDConnection', 'FireDAC.Comp.Client.
// TFDConnection'), klein; sonst das erste Token ('array', '^').
function TypeAfter(AMap: TRdxCodeMap; const AColon: TRdxToken): string;
var
  T, D  : TRdxToken;
  Parts : TArray<string>;
begin
  T := After(AMap, AColon);
  Result := T.Low;
  if not T.IsWord then Exit;
  Parts := nil;
  AddText(Parts, T.Low);
  D := After(AMap, T);
  while (D.Low = '.') and After(AMap, D).IsWord do
  begin
    T := After(AMap, D);
    AddText(Parts, T.Low);
    D := After(AMap, T);
  end;
  Result := JoinWith(Parts, '.');
end;

// 'Name:' bzw. 'Name, B, C:' hinter einem DECL_LEADS-Token: dkTyped mit
// dem Typ. False bei allem anderen (Argumente 'F(A, Name)').
function TypedDeclAt(AMap: TRdxCodeMap; const P, N: TRdxToken;
  var D: TSqlDecl): Boolean;
var
  C     : TRdxToken;
  Steps : Integer;
begin
  Result := False;
  if not InList(P.Low, DECL_LEADS) then Exit;
  C := N;
  Steps := 0;
  while (C.Low = ',') and (Steps < MAX_WALK) do
  begin
    C := After(AMap, C);
    if not C.IsWord then Exit;
    C := After(AMap, C);
    Inc(Steps);
  end;
  if C.Low <> ':' then Exit;
  D.Kind := dkTyped;
  D.Text := TypeAfter(AMap, C);
  Result := True;
end;

// Das Wort, das die Section um ANameTok eroeffnet (const, var, type ...):
// rueckwaerts ueber die Eintraege davor, Klammern zaehlen; '(' innerhalb
// einer offenen Klammer, '' ohne.
function SectionOf(AMap: TRdxCodeMap; const ANameTok: TRdxToken): string;
var
  T, P  : TRdxToken;
  Paren : Integer;
  n     : Integer;
begin
  Result := '';
  Paren := 0;
  T := Before(AMap, ANameTok);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    P := Before(AMap, T);
    if T.Low = ')' then
      Inc(Paren)
    else if T.Low = '(' then
    begin
      Dec(Paren);
      if Paren < 0 then Exit('(');
    end
    else if (Paren = 0) and IsKeywordAfter(T, P)
       and (InList(T.Low, SECTION_STOPS) or IsRoutineHeadAfter(T, P)) then
      Exit(T.Low);
    T := P;
  end;
end;

// Text der Zeilen ab (ALine1, ACol1) bis vor (ALine2, ACol2).
function RawBetween(AMap: TRdxCodeMap; ALine1, ACol1, ALine2,
  ACol2: Integer): string;
var
  Lines : TArray<string>;
  L     : Integer;
begin
  if ALine1 = ALine2 then
    Exit(Copy(AMap.Raw(ALine1), ACol1, ACol2 - ACol1));
  Lines := nil;
  AddText(Lines, Copy(AMap.Raw(ALine1), ACol1, MaxInt));
  for L := ALine1 + 1 to ALine2 - 1 do
    AddText(Lines, AMap.Raw(L));
  AddText(Lines, Copy(AMap.Raw(ALine2), 1, ACol2 - 1));
  Result := JoinWith(Lines, sLineBreak);
end;

// Der Quelltext des Werts hinter '=' bis vor das ';' auf Klammertiefe 0
// (Strings sind keine Token); '' ohne ';'.
function ValueTextAfter(AMap: TRdxCodeMap; const AEq: TRdxToken): string;
var
  T     : TRdxToken;
  Depth : Integer;
  Delta : Integer;
  n     : Integer;
begin
  Result := '';
  Depth := 0;
  T := After(AMap, AEq);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    Delta := ParenDelta(T);
    if Delta <> 0 then
      Inc(Depth, Delta)
    else if (T.Low = ';') and (Depth = 0) then
      Exit(Trim(RawBetween(AMap, AEq.Line, AEq.EndCol, T.Line, T.Col)));
    T := After(AMap, T);
  end;
end;

// Steht P ('(' bzw. ',' vor einem 'Name =') in der Klammer einer
// Aufzaehlung - vor ihrer oeffnenden '(' steht '=' ('TE = (A = 1, ..)')
// bzw. ':' ('V: (A = 1, ..)')? Rueckwaerts mit Klammerzaehlung; ein ';'
// beendet die Suche. Ein Vergleich in Klammern im Code ('if (FConn = nil)',
// 'F(A, Name = 1)') ist keine Deklaration - er verwarf sonst jeden
// Konstanten- und Typbeweis des Namens.
function InEnumList(AMap: TRdxCodeMap; const P: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Paren : Integer;
  n     : Integer;
begin
  Result := False;
  Paren := 0;
  T := P;
  for n := 1 to MAX_WALK do
  begin
    if (T.Low = '') or (T.Low = ';') then Exit;
    if T.Low = ')' then
      Inc(Paren)
    else if T.Low = '(' then
    begin
      if Paren = 0 then
      begin
        T := Before(AMap, T);
        Exit((T.Low = '=') or (T.Low = ':'));
      end;
      Dec(Paren);
    end;
    T := Before(AMap, T);
  end;
end;

// 'Name =': Konstante (const-Section), sonst Typ, Aufzaehlungswert oder
// resourcestring (dkOther); False bei einem Vergleich im Code - auch in
// Klammern (InEnumList).
function EqualsDeclAt(AMap: TRdxCodeMap; const T, P, N: TRdxToken;
  var D: TSqlDecl): Boolean;
begin
  Result := True;
  if (P.Low = '(') or (P.Low = ',') then
  begin
    Result := InEnumList(AMap, P);
    D.Kind := dkOther;
  end
  else if P.Low = 'type' then
    D.Kind := dkOther
  else if not InList(P.Low, CONST_LEADS) then
    Result := False
  else if SectionOf(AMap, T) = 'const' then
  begin
    D.Kind := dkConst;
    D.Text := ValueTextAfter(AMap, N);
  end
  else
    D.Kind := dkOther;
end;

// Ist das Wort T (der gesuchte Name) eine Deklaration? D: welche. Eine
// Inline-Variable mit abgeleitetem Typ ('var Name := ..', 'for var Name
// in ..' bzw. ':= ..') ist dkOther - bis Charge SQc sah DeclAt sie nicht,
// und eine Unit-Konstante gleichen Namens galt als bewiesen (Gegen-Review
// S1, Blocker).
function DeclAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out D: TSqlDecl): Boolean;
var
  P, N : TRdxToken;
begin
  D := Default(TSqlDecl);
  D.Tok := T;
  P := Before(AMap, T);
  if P.Low = '&' then
    P := Before(AMap, P);
  if (P.Low = '.') or (P.Low = '@') then
    Exit(False);   // Member eines anderen Ausdrucks, Adresse
  N := After(AMap, T);
  Result := True;
  if InList(P.Low, ROUTINE_WORDS) or (P.Low = 'property') then
    D.Kind := dkOther
  else if (P.Low = KW_VAR) and InList(N.Low, INLINE_VAR_AFTER) then
    D.Kind := dkOther
  else if (N.Low = ':') or (N.Low = ',') then
    Result := TypedDeclAt(AMap, P, N, D)
  else if N.Low = '=' then
    Result := EqualsDeclAt(AMap, T, P, N, D)
  else
    Result := False;
end;

procedure AddDecl(var ADecls: TSqlDecls; var ACount: Integer;
  const D: TSqlDecl);
begin
  if ACount = Length(ADecls) then
    SetLength(ADecls, ACount * 2 + 4);
  ADecls[ACount] := D;
  Inc(ACount);
end;

function DeclsOf(AMap: TRdxCodeMap; const AName: string): TSqlDecls;
var
  Low   : string;
  L     : Integer;
  c     : Integer;
  D     : TSqlDecl;
  Count : Integer;
begin
  Result := nil;
  Count := 0;
  Low := LowerCase(AName);
  for L := 1 to AMap.LineCount do
  begin
    c := WordCol(AMap, L, Low, 1);
    while c > 0 do
    begin
      if DeclAt(AMap, TokenAt(AMap, L, c), D) then
        AddDecl(Result, Count, D);
      c := WordCol(AMap, L, Low, c + Length(Low));
    end;
  end;
  SetLength(Result, Count);
end;

// Erstes Token hinter 'implementation' (Unit), sonst das erste der Datei
// (Programm, Bibliothek).
function BodyStart(AMap: TRdxCodeMap): TRdxToken;
var
  T, P : TRdxToken;
  n    : Integer;
begin
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  Result := T;
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Exit;
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit(After(AMap, T));
    P := T;
    T := After(AMap, T);
  end;
end;

{ ---- Grenzen der Datei (Sichtbarkeit, uRdxSqlTemplate, Punkt 2) ---- }

// Liegt T zwischen A und B (beide eingeschlossen)?
function TokWithin(const T, A, B: TRdxToken): Boolean;
begin
  Result := not TokBefore(T, A) and not TokBefore(B, T);
end;

// Oeffnet T (Schluesselwort, APrev davor) einen Typ mit Rumpf? 'record'
// immer, ausser als Einschraenkung ('<T: record>'); class, object,
// interface, dispinterface hinter '=' bzw. 'packed' mit Rumpf.
function OpensTypeBody(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
begin
  if T.Low = KW_RECORD then
    Exit(not InList(After(AMap, T).Low, CONSTRAINT_FOLLOWERS));
  Result := InList(T.Low, TYPE_KINDS) and InList(APrev.Low, TYPE_LEADS)
    and TypeHasBody(AMap, T);
end;

// Der Name des Typs, dessen Oeffner AKind ist ('TFoo = class', 'TFoo<T> =
// packed record'): klein, ohne Typparameter; '' ohne Namen (der record
// eines Felds).
function TypeNameBefore(AMap: TRdxCodeMap; const AKind: TRdxToken): string;
var
  T     : TRdxToken;
  Depth : Integer;
  n     : Integer;
begin
  Result := '';
  T := Before(AMap, AKind);
  if T.Low = 'packed' then
    T := Before(AMap, T);
  if T.Low <> '=' then Exit;
  T := Before(AMap, T);
  Depth := 0;
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '>' then
      Inc(Depth)
    else if T.Low = '<' then
      Dec(Depth);
    if (Depth = 0) and (T.Low <> '<') then
      Break;
    T := Before(AMap, T);
    if T.Low = '' then Exit;
  end;
  if (T.Low = '<') or (T.Low = '>') then Exit;
  if T.IsWord then
    Result := T.Low;
end;

procedure PushFrame(var AStack: TArray<TSqlFrame>; AIsType, AIsRecord: Boolean;
  const AOpen: TRdxToken; const ANameLow: string);
var
  n : Integer;
begin
  n := Length(AStack);
  SetLength(AStack, n + 1);
  AStack[n].IsType   := AIsType;
  AStack[n].IsRecord := AIsRecord;
  AStack[n].Open     := AOpen;
  AStack[n].NameLow  := ANameLow;
end;

function TopIs(const AStack: TArray<TSqlFrame>; AType: Boolean): Boolean;
begin
  Result := (Length(AStack) > 0) and (AStack[High(AStack)].IsType = AType);
end;

// 'end' schliesst den obersten Block; ein Typ wird zu AScopes.Types.
procedure PopFrame(var AStack: TArray<TSqlFrame>; const AEnd: TRdxToken;
  var AScopes: TSqlScopes);
var
  F : TSqlFrame;
  n : Integer;
begin
  if Length(AStack) = 0 then Exit;
  F := AStack[High(AStack)];
  SetLength(AStack, Length(AStack) - 1);
  if not F.IsType then Exit;
  n := Length(AScopes.Types);
  SetLength(AScopes.Types, n + 1);
  AScopes.Types[n].Open    := F.Open;
  AScopes.Types[n].Close   := AEnd;
  AScopes.Types[n].NameLow := F.NameLow;
end;

// Ein Schluesselwort beim Lauf (BuildScopes): Typ-Oeffner, end, case
// (im record ohne eigenes end), begin/try/asm.
procedure StepFrames(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  var AStack: TArray<TSqlFrame>; var AScopes: TSqlScopes);
begin
  if OpensTypeBody(AMap, T, APrev) then
    PushFrame(AStack, True, T.Low = KW_RECORD, T, TypeNameBefore(AMap, T))
  else if T.Low = KW_END then
    PopFrame(AStack, T, AScopes)
  else if T.Low = KW_CASE then
  begin
    if not (TopIs(AStack, True) and AStack[High(AStack)].IsRecord) then
      PushFrame(AStack, False, False, T, '');
  end
  else if IsEndOpener(T.Low) then
    PushFrame(AStack, False, False, T, '');
end;

// Die Routine mit Rumpf ab dem Kopf T (ReadRoutine) zu AScopes.Routines;
// ClassLow das Klassen-Glied ihres Namens. False ohne Rumpf.
function AddRoutineAt(AMap: TRdxCodeMap; const T: TRdxToken;
  var AScopes: TSqlScopes): Boolean;
var
  R : TRdxRoutine;
  n : Integer;
begin
  Result := (TRdxBlocks.ReadRoutine(AMap, T, R) = '') and (R.Body.Low <> '');
  if not Result then Exit;
  n := Length(AScopes.Routines);
  SetLength(AScopes.Routines, n + 1);
  AScopes.Routines[n].Head := R.Head;
  AScopes.Routines[n].Body := R.Body;
  AScopes.Routines[n].Last := R.Last;
  AScopes.Routines[n].ClassLow := '';
  if Length(R.Parts) >= 2 then
    AScopes.Routines[n].ClassLow := R.Parts[High(R.Parts) - 1];
end;

// Ein Schritt des Laufs (BuildScopes) am Schluesselwort T: eine Routine
// mit Rumpf merkt ihren Rumpf in AJumps (der Lauf springt dort hinter ihr
// letztes ';' - ihre Zeilen hat ReadRoutine schon gelesen, und im Rumpf
// steht keine benannte Routine und kein Typ), dann die Bloecke.
procedure StepKeyword(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  var AStack: TArray<TSqlFrame>; var AScopes: TSqlScopes);
var
  n : Integer;
begin
  if IsRoutineHeadAfter(T, APrev) and not TopIs(AStack, True)
     and not TokBefore(T, AScopes.Start) and AddRoutineAt(AMap, T, AScopes) then
  begin
    n := Length(AScopes.Jumps);
    SetLength(AScopes.Jumps, n + 1);
    AScopes.Jumps[n] := High(AScopes.Routines);
  end;
  StepFrames(AMap, T, APrev, AStack, AScopes);
end;

// Steht der Lauf am Rumpf der zuletzt gemerkten Routine? Dann ihr letztes
// ';' (der Lauf geht dahinter weiter); sonst T selbst. Gemerkte, deren
// Rumpf schon hinter dem Lauf liegt, fallen weg.
function JumpFrom(var AScopes: TSqlScopes; const T: TRdxToken): TRdxToken;
var
  R : Integer;
begin
  Result := T;
  while Length(AScopes.Jumps) > 0 do
  begin
    R := AScopes.Jumps[High(AScopes.Jumps)];
    if not TokBefore(AScopes.Routines[R].Body, T) then
    begin
      if SameTok(AScopes.Routines[R].Body, T) then
      begin
        Result := AScopes.Routines[R].Last;
        SetLength(AScopes.Jumps, Length(AScopes.Jumps) - 1);
      end;
      Exit;
    end;
    SetLength(AScopes.Jumps, Length(AScopes.Jumps) - 1);
  end;
end;

// EIN Lauf durch die Datei (Minor 6: bis Charge SQc je Operand neu): die
// Typen mit Rumpf und - ab BodyStart, nicht in einem Typrumpf - alle
// Routinen mit Rumpf, auch verschachtelte (Minor 5: die lokale Konstante
// einer inneren Routine galt bis dahin in der aeusseren).
procedure BuildScopes(AMap: TRdxCodeMap; var AScopes: TSqlScopes);
var
  T, P, J : TRdxToken;
  Stack   : TArray<TSqlFrame>;
  n       : Integer;
begin
  AScopes.Built := True;
  AScopes.Routines := nil;
  AScopes.Types := nil;
  AScopes.Jumps := nil;
  Stack := nil;
  AScopes.Start := BodyStart(AMap);
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  for n := 1 to MAX_WALK do
  begin
    if T.Low = '' then Break;
    J := JumpFrom(AScopes, T);
    if SameTok(J, T) then
    begin
      if IsKeywordAfter(T, P) then
        StepKeyword(AMap, T, P, Stack, AScopes);
      P := T;
    end
    else
      P := J;
    T := After(AMap, P);
  end;
  // Bricht der Lauf an MAX_WALK ab, fehlen Grenzen - dann ist keine
  // Konstante bewiesen (ConstOfName).
  AScopes.Complete := T.Low = '';
end;

// Umfasst die Routine I die Zeile ALine?
function RoutineHasLine(const AScopes: TSqlScopes; I, ALine: Integer): Boolean;
begin
  Result := (AScopes.Routines[I].Head.Line <= ALine)
    and (ALine <= AScopes.Routines[I].Last.Line);
end;

// Die innerste Routine (spaetester Kopf), die die Zeile ALine umfasst; -1
// ohne.
function InnermostAt(const AScopes: TSqlScopes; ALine: Integer): Integer;
var
  i : Integer;
begin
  Result := -1;
  for i := 0 to High(AScopes.Routines) do
    if RoutineHasLine(AScopes, i, ALine) and ((Result < 0)
       or TokBefore(AScopes.Routines[Result].Head, AScopes.Routines[i].Head)) then
      Result := i;
end;

// Die aeusserste Routine (fruehester Kopf), die die Zeile ALine umfasst;
// -1 ohne.
function OutermostAt(const AScopes: TSqlScopes; ALine: Integer): Integer;
var
  i : Integer;
begin
  Result := -1;
  for i := 0 to High(AScopes.Routines) do
    if RoutineHasLine(AScopes, i, ALine) and ((Result < 0)
       or TokBefore(AScopes.Routines[i].Head, AScopes.Routines[Result].Head)) then
      Result := i;
end;

// Die innerste Routine bzw. der innerste Typrumpf um ATok; -1 ohne. Eine
// Frage an den Index des einen Laufs (BuildScopes), mit dem Vertrag der
// Vorlage: die Routine umfasst ATok vom Kopf bis zum letzten ';' samt
// Deklarationsteil (lokale Konstanten). Die Rueckwaertssuche der anderen
// Planer (uRdxBlocks.TRdxBlocks.HeadBefore, Gegen-Review R5-03) fragt je
// Frage neu - hier kommen viele Fragen auf einen Lauf.
function InnermostRoutine(const AScopes: TSqlScopes; const ATok: TRdxToken): Integer;
var
  i : Integer;
begin
  Result := -1;
  for i := 0 to High(AScopes.Routines) do
    if TokWithin(ATok, AScopes.Routines[i].Head, AScopes.Routines[i].Last)
       and ((Result < 0) or TokBefore(AScopes.Routines[Result].Head,
         AScopes.Routines[i].Head)) then
      Result := i;
end;

function InnermostType(const AScopes: TSqlScopes; const ATok: TRdxToken): Integer;
var
  i : Integer;
begin
  Result := -1;
  for i := 0 to High(AScopes.Types) do
    if TokWithin(ATok, AScopes.Types[i].Open, AScopes.Types[i].Close)
       and ((Result < 0) or TokBefore(AScopes.Types[Result].Open,
         AScopes.Types[i].Open)) then
      Result := i;
end;

// Wo gilt die Konstante, deren Name an ATok deklariert ist? Im Typrumpf
// (AOwner: der Typ), im Rumpf einer Routine (Inline-Konstante), im
// Deklarationsteil einer Routine (ARoutine) oder auf Unit-Ebene.
function ScopeOf(const AScopes: TSqlScopes; const ATok: TRdxToken;
  out AOwner: string; out ARoutine: Integer): TSqlConstScope;
var
  Ty : Integer;
begin
  AOwner := '';
  ARoutine := InnermostRoutine(AScopes, ATok);
  Ty := InnermostType(AScopes, ATok);
  if (Ty >= 0) and ((ARoutine < 0)
     or TokBefore(AScopes.Routines[ARoutine].Head, AScopes.Types[Ty].Open)) then
  begin
    AOwner := AScopes.Types[Ty].NameLow;
    Exit(cvClass);
  end;
  if ARoutine < 0 then
    Exit(cvUnit);
  if TokBefore(ATok, AScopes.Routines[ARoutine].Body) then
    Result := cvLocal
  else
    Result := cvInline;
end;

// Gilt die Konstante D an ALine (uRdxSqlTemplate, Punkt 2)?
function VisibleAt(const AScopes: TSqlScopes; const D: TSqlDecl;
  ALine: Integer): Boolean;
var
  Owner : string;
  R     : Integer;
begin
  Result := False;
  if D.Tok.Line >= ALine then Exit;
  case ScopeOf(AScopes, D.Tok, Owner, R) of
    cvUnit  : Result := True;
    cvLocal : Result := ALine <= AScopes.Routines[R].Last.Line;
    cvClass :
      begin
        R := OutermostAt(AScopes, ALine);
        Result := (Owner <> '') and (R >= 0)
          and (AScopes.Routines[R].ClassLow = Owner);
      end;
  else
    Result := False;   // cvInline: nur in ihrem Block (ConstOfName)
  end;
end;

// Der Typrumpf mit dem Namen ANameLow - genau einer, sonst -1 (keiner, oder
// mehrere: {$IFDEF}-Zweige, gleichnamige geschachtelte Typen).
function TypeBodyNamed(const AScopes: TSqlScopes; const ANameLow: string): Integer;
var
  i : Integer;
begin
  Result := -1;
  for i := 0 to High(AScopes.Types) do
    if AScopes.Types[i].NameLow = ANameLow then
    begin
      if Result >= 0 then
        Exit(-1);
      Result := i;
    end;
end;

// Erbt die Klasse AClassLow Member von ausserhalb der Datei? Dann kann in
// ihren Methoden ein geerbtes Member ('Name' aus TComponent, 'Caption' aus
// TControl) einen gleichnamigen Namen der Unit verdecken: Delphi bindet ihn
// an Self, bevor es die Unit-Ebene fragt (Review FB, R2-05 - derselbe
// Grundsatz wie StrictMemberType im strengen Resolver des Cores). True fuer
// einen Vorfahr ohne eindeutigen Rumpf in der Datei (class(TForm), auch
// qualifiziert oder generisch), einen Helper ('class helper for ..', 'record
// helper for ..') und eine Kette ueber MAX_ANCESTORS; False fuer einen
// Record, eine Klasse ohne Vorfahr (TObject) und eine Kette, die ganz in der
// Datei liegt.
function InheritsForeign(AMap: TRdxCodeMap; const AScopes: TSqlScopes;
  const AClassLow: string): Boolean;
var
  Key      : string;
  Ty, Step : Integer;
  T, Nx    : TRdxToken;
  Names    : TArray<string>;
begin
  Key := AClassLow;
  for Step := 1 to MAX_ANCESTORS do
  begin
    Ty := TypeBodyNamed(AScopes, Key);
    if Ty < 0 then
      Exit(True);
    T := AScopes.Types[Ty].Open;
    Nx := After(AMap, T);
    while InList(Nx.Low, CLASS_MODIFIERS) do
      Nx := After(AMap, Nx);
    if Nx.Low = KW_HELPER then
      Exit(True);
    if T.Low = KW_RECORD then
      Exit(False);
    Names := TRdxBlocks.HeritageOf(AMap, T);
    if Length(Names) = 0 then
      Exit(False);
    Key := LowerCase(Names[0]);
    if Key = 'tobject' then
      Exit(False);
  end;
  Result := True;
end;

// Kann an ALine ein geerbtes Member fremder Herkunft einen Namen der Unit
// verdecken (InheritsForeign)? Massgeblich ist die aeusserste Routine um
// ALine - eine lokale Routine einer Methode sieht deren Member auch.
function UnitNamesShadowedAt(AMap: TRdxCodeMap; const AScopes: TSqlScopes;
  ALine: Integer): Boolean;
var
  R : Integer;
begin
  R := OutermostAt(AScopes, ALine);
  Result := (R >= 0) and (AScopes.Routines[R].ClassLow <> '')
    and InheritsForeign(AMap, AScopes, AScopes.Routines[R].ClassLow);
end;

// Ein Wert, wenn alle sichtbaren Konstanten dasselbe einfache Literal
// tragen; sonst sckKept.
function ConstOfValues(const AValues: TArray<string>): TRdxSqlConst;
var
  i     : Integer;
  Value : string;
begin
  Result := Default(TRdxSqlConst);
  Result.Kind := sckKept;
  for i := 0 to High(AValues) do
  begin
    if not TRdxRecipes.DecodeLiteral(AValues[i], Value) or (AValues[i] = '') then
      Exit;
    if (i > 0) and (Value <> Result.Value) then
      Exit;
    Result.Value := Value;
  end;
  Result.Kind := sckLiteral;
end;

// Die Werte der Deklarationen ADecls, die an ALine sichtbar sind
// (VisibleAt) - ohne Unit-Konstanten, wenn dort ein geerbtes Member
// fremder Herkunft den Namen tragen kann (UnitNamesShadowedAt, R2-05).
// False, wenn eine Inline-Konstante den Beweis verwirft: sie gilt nur in
// ihrem Block, wie eine Variable (Blocker, Minor 5).
function VisibleValues(AMap: TRdxCodeMap; const AScopes: TSqlScopes;
  const ADecls: TSqlDecls; ALine: Integer; out AValues: TArray<string>): Boolean;
var
  Owner    : string;
  i, R     : Integer;
  Scope    : TSqlConstScope;
  Shadowed : Boolean;
begin
  Result := False;
  AValues := nil;
  Shadowed := UnitNamesShadowedAt(AMap, AScopes, ALine);
  for i := 0 to High(ADecls) do
  begin
    Scope := ScopeOf(AScopes, ADecls[i].Tok, Owner, R);
    if Scope = cvInline then
      Exit;
    if ((Scope <> cvUnit) or not Shadowed)
       and VisibleAt(AScopes, ADecls[i], ALine) then
      AddText(AValues, ADecls[i].Text);
  end;
  Result := True;
end;

// SqlConstOf mit den Grenzen der Datei aus AScopes (erst gerechnet, wenn
// alle Deklarationen Konstanten sind).
function ConstOfName(AMap: TRdxCodeMap; var AScopes: TSqlScopes;
  const AName: string; ALine: Integer): TRdxSqlConst;
var
  Decls  : TSqlDecls;
  Values : TArray<string>;
  i      : Integer;
begin
  Result := Default(TRdxSqlConst);
  if not Assigned(AMap) or not TRdxRecipes.IsPlainIdent(Trim(AName)) then Exit;
  Decls := DeclsOf(AMap, Trim(AName));
  if Length(Decls) = 0 then Exit;
  for i := 0 to High(Decls) do
    if Decls[i].Kind <> dkConst then Exit;
  if not AScopes.Built then
    BuildScopes(AMap, AScopes);
  if not AScopes.Complete then Exit;
  if VisibleValues(AMap, AScopes, Decls, ALine, Values)
     and (Length(Values) > 0) then
    Result := ConstOfValues(Values);
end;

function SqlConstOf(AMap: TRdxCodeMap; const AName: string;
  ALine: Integer): TRdxSqlConst;
var
  Scopes : TSqlScopes;
begin
  Scopes := Default(TSqlScopes);
  Result := ConstOfName(AMap, Scopes, AName, ALine);
end;

{ ---- Ziel: FireDAC, ADO ---- }

function ExecSqlReceiverOf(const ATarget: string): string;
var
  T : string;
begin
  Result := '';
  T := Trim(ATarget);
  if (Length(T) > Length(EXEC_SQL))
     and (LowerCase(Copy(T, Length(T) - Length(EXEC_SQL) + 1, MaxInt)) = EXEC_SQL) then
    Result := Copy(T, 1, Length(T) - Length(EXEC_SQL));
end;

// Ist ATypeLow einer der Typen ATypes - bloss oder mit einer der Units
// AUnits davor ('firedac.comp.client.tfdconnection')?
function IsTypeOf(const ATypeLow: string; const AUnits,
  ATypes: array of string): Boolean;
var
  Dot : Integer;
begin
  Dot := LastDelimiter('.', ATypeLow);
  if Dot = 0 then
    Exit(InList(ATypeLow, ATypes));
  Result := InList(Copy(ATypeLow, Dot + 1, MaxInt), ATypes)
    and InList(Copy(ATypeLow, 1, Dot - 1), AUnits);
end;

// Nennen die uses eine der Units AUnits, und ist AReceiver (ein Bezeichner,
// 'Self.' davor erlaubt) in der Datei mindestens einmal und nur als einer
// der Typen ATypes deklariert?
function TypedReceiverProven(AMap: TRdxCodeMap; const AUsesNames: TArray<string>;
  const AUnits, ATypes: array of string; const AReceiver: string): Boolean;
var
  Name    : string;
  Decls   : TSqlDecls;
  i       : Integer;
  HasUnit : Boolean;
begin
  Result := False;
  Name := Trim(AReceiver);
  if SameText(Copy(Name, 1, Length(SELF_PREFIX)), SELF_PREFIX) then
    Delete(Name, 1, Length(SELF_PREFIX));
  if not Assigned(AMap) or not TRdxRecipes.IsPlainIdent(Name) then Exit;
  HasUnit := False;
  for i := 0 to High(AUsesNames) do
    HasUnit := HasUnit or InList(LowerCase(Trim(AUsesNames[i])), AUnits);
  if not HasUnit then Exit;
  Decls := DeclsOf(AMap, Name);
  if Length(Decls) = 0 then Exit;
  for i := 0 to High(Decls) do
    if (Decls[i].Kind <> dkTyped) or not IsTypeOf(Decls[i].Text, AUnits, ATypes) then
      Exit;
  Result := True;
end;

function FireDacConnectionProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
begin
  Result := TypedReceiverProven(AMap, AUsesNames, FIREDAC_UNITS, FIREDAC_TYPES,
    AReceiver);
end;

function AdoObjectProven(AMap: TRdxCodeMap;
  const AUsesNames: TArray<string>; const AReceiver: string): Boolean;
begin
  Result := TypedReceiverProven(AMap, AUsesNames, ADO_UNITS, ADO_TYPES,
    AReceiver);
end;

{ ---- Die Kette 'Q.SQL.Add' (uRdxSqlTemplate, Punkt 3) ---- }

// Was ein Glied hinter 'Q.SQL.' an AMember fuer die Kette bedeutet; AText
// der SQL-Text bei einem Bruchstueck.
function ChainStepAt(AMap: TRdxCodeMap; const AMember: TRdxToken;
  out AText: string): TSqlChainStep;
var
  N, Close : TRdxToken;
begin
  AText := '';
  N := After(AMap, AMember);
  if AMember.Low = CHAIN_CLEAR then
    Exit(chStop);
  if (AMember.Low = CHAIN_ADD) and (N.Low = '(') then
  begin
    Close := MatchClose(AMap, N);
    if Close.Low = '' then
      Exit(chStop);
    AText := SqlChainTextOf(RawBetween(AMap, N.Line, N.EndCol, Close.Line,
      Close.Col));
    Exit(chFragment);
  end;
  if (AMember.Low = CHAIN_TEXT) and (N.Low = ':=') then
  begin
    AText := SqlChainTextOf(ValueTextAfter(AMap, N));
    Exit(chFragmentStop);
  end;
  // Gelesen (ShowMessage(Q.SQL.Text), Count, BeginUpdate) aendert nichts;
  // jedes andere Glied (Insert, Delete, Assign, LoadFromFile ...) kann den
  // Text aendern - dort endet die Kette.
  if InList(AMember.Low, CHAIN_READS) then
    Result := chIgnore
  else
    Result := chStop;
end;

// Die Spalten, an denen AKey ('q.sql.') auf ALine im Code beginnt - als
// Glied eines Ausdrucks nur hinter 'Self.' ('Self.Q.SQL.').
function ChainColsOn(AMap: TRdxCodeMap; ALine: Integer;
  const AKey: string): TArray<Integer>;
var
  L    : string;
  c, n : Integer;
begin
  Result := nil;
  n := 0;
  L := LowerCase(AMap.Raw(ALine));
  c := PosEx(AKey, L, 1);
  while c > 0 do
  begin
    if AMap.IsCode(ALine, c) and not IsIdentChar(CharAt(L, c - 1))
       and ((CharAt(L, c - 1) <> '.')
         or (Copy(L, c - Length(SELF_PREFIX), Length(SELF_PREFIX)) = SELF_PREFIX)) then
    begin
      SetLength(Result, n + 1);
      Result[n] := c;
      Inc(n);
    end;
    c := PosEx(AKey, L, c + 1);
  end;
end;

// Der Schritt an der Stelle ACol von ALine (ChainColsOn).
function ChainStepOn(AMap: TRdxCodeMap; ALine, ACol: Integer;
  const AKey: string; out AText: string): TSqlChainStep;
begin
  Result := ChainStepAt(AMap, NextToken(AMap, ALine, ACol + Length(AKey)), AText);
end;

// Rueckwaerts von der Zeile vor der Anweisung bis zum Rumpfbeginn der
// Routine ARoutine: die Bruchstuecke bis Clear bzw. 'SQL.Text :='.
procedure ChainBack(AMap: TRdxCodeMap; const ARoutine: TSqlRoutine;
  var AChain: TSqlChain);
var
  L, k : Integer;
  Cols : TArray<Integer>;
  Step : TSqlChainStep;
  Text : string;
begin
  L := AChain.First - 1;
  while (L >= ARoutine.Body.Line) and (L >= AChain.First - MAX_CHAIN_LINES) do
  begin
    Cols := ChainColsOn(AMap, L, AChain.Key);
    for k := High(Cols) downto 0 do
    begin
      Step := ChainStepOn(AMap, L, Cols[k], AChain.Key, Text);
      if Step in [chFragment, chFragmentStop] then
        AddText(AChain.Frags, Text);
      if Step in [chFragmentStop, chStop] then
        Exit;
    end;
    Dec(L);
  end;
end;

// Vorwaerts von der Zeile hinter der Anweisung bis zum Ende der Routine:
// die Platzhalter der spaeteren Bruchstuecke bis Clear bzw. 'SQL.Text :='.
procedure ChainAhead(AMap: TRdxCodeMap; const ARoutine: TSqlRoutine;
  var AChain: TSqlChain);
var
  L, k : Integer;
  Cols : TArray<Integer>;
  Step  : TSqlChainStep;
  Text  : string;
  Name  : string;
  Found : TArray<string>;
begin
  L := AChain.Last + 1;
  while (L <= ARoutine.Last.Line) and (L <= AChain.Last + MAX_CHAIN_LINES) do
  begin
    Cols := ChainColsOn(AMap, L, AChain.Key);
    for k := 0 to High(Cols) do
    begin
      Step := ChainStepOn(AMap, L, Cols[k], AChain.Key, Text);
      // Ein lesendes Glied (BeginUpdate, Log(Q.SQL.Text)) aendert nichts -
      // wie in ChainBack laeuft die Kette weiter (Review Woche G01-12).
      if Step = chIgnore then
        Continue;
      if Step <> chFragment then
        Exit;
      Found := SqlPlaceholders(Text);
      for Name in Found do
        AddText(AChain.Names, Name);
    end;
    Inc(L);
  end;
end;

// Die Kette um die Anweisung AChain.First..Last in derselben Routine
// (uRdxSqlTemplate, Punkt 3): APrefix der SQL-Text der frueheren Zeilen (je
// mit #13#10) bis Clear bzw. 'SQL.Text :=', AChain.Names die Platzhalter
// der frueheren und spaeteren Zeilen (klein); ausserhalb einer Routine
// beides leer. Die Grenzen der Datei aus AScopes.
procedure ChainWith(AMap: TRdxCodeMap; var AScopes: TSqlScopes;
  var AChain: TSqlChain; out APrefix: string);
var
  R, i  : Integer;
  Name  : string;
  Found : TArray<string>;
  SB    : TStringBuilder;
begin
  APrefix := '';
  if not AScopes.Built then
    BuildScopes(AMap, AScopes);
  R := InnermostAt(AScopes, AChain.First);
  if R < 0 then Exit;
  ChainBack(AMap, AScopes.Routines[R], AChain);
  ChainAhead(AMap, AScopes.Routines[R], AChain);
  SB := TStringBuilder.Create;
  try
    for i := High(AChain.Frags) downto 0 do
    begin
      SB.Append(AChain.Frags[i]);
      SB.Append(#13#10);
      Found := SqlPlaceholders(AChain.Frags[i]);
      for Name in Found do
        AddText(AChain.Names, Name);
    end;
    APrefix := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Die Suche fuer das Objekt AObject (QueryObjectOf) auf den Zeilen
// AFirst..ALast.
function ChainFor(const AObject: string; AFirst, ALast: Integer): TSqlChain;
var
  Obj : string;
begin
  Result := Default(TSqlChain);
  Obj := LowerCase(Trim(AObject));
  if Copy(Obj, 1, Length(SELF_PREFIX)) = SELF_PREFIX then
    Delete(Obj, 1, Length(SELF_PREFIX));
  Result.Key := Obj + CHAIN_SQL;
  Result.First := AFirst;
  Result.Last := ALast;
end;

// Ist ATarget ein 'Q.SQL.Add' - das Glied der Kette?
function IsChainTarget(const ATarget: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(ATarget));
  Result := (Length(Low) > Length(CHAIN_SQL + CHAIN_ADD))
    and (Copy(Low, Length(Low) - Length(CHAIN_SQL + CHAIN_ADD) + 1, MaxInt)
      = CHAIN_SQL + CHAIN_ADD);
end;

// Die Zeilen der Anweisung: die erste und die letzte aus PartLines.
procedure StatementLines(const AReq: TRdxSqlRequest; out AFirst, ALast: Integer);
var
  L : Integer;
begin
  AFirst := MaxInt;
  ALast := 0;
  for L in AReq.PartLines do
    if L > 0 then
    begin
      if L < AFirst then AFirst := L;
      if L > ALast then ALast := L;
    end;
end;

procedure AddSqlFacts(AMap: TRdxCodeMap; var AReq: TRdxSqlRequest);
var
  i, First, Last : Integer;
  Scopes         : TSqlScopes;
  Chain          : TSqlChain;
begin
  // 'Setzt' gilt auch fuer eine wiederverwendete Anfrage: kein Fakt eines
  // frueheren Laufs bleibt stehen (Review Woche G01-13).
  AReq.Consts := nil;
  AReq.Binding := sbByTarget;
  AReq.Prefix := '';
  AReq.ChainNames := nil;
  Scopes := Default(TSqlScopes);
  SetLength(AReq.Consts, Length(AReq.Parts));
  for i := 0 to High(AReq.Parts) do
    if (AReq.Parts[i].Role = ROLE_OPERAND) and not AReq.Parts[i].InWith
       and not AReq.InWith and (i <= High(AReq.PartLines)) then
      AReq.Consts[i] := ConstOfName(AMap, Scopes, AReq.Parts[i].Text,
        AReq.PartLines[i]);
  // Im with-Block ist kein Name bewiesen - kein Kanal, keine Kette.
  if AReq.InWith or not Assigned(AMap) then Exit;
  if AReq.IsCall and FireDacConnectionProven(AMap, AReq.UsesNames,
       ExecSqlReceiverOf(AReq.Target)) then
    AReq.Binding := sbFireDacExecSql
  else if TRdxRecipes.HasQueryObject(AReq.Target)
     and AdoObjectProven(AMap, AReq.UsesNames,
       TRdxRecipes.QueryObjectOf(Trim(AReq.Target))) then
    AReq.Binding := sbAdoParameters;
  StatementLines(AReq, First, Last);
  if not AReq.IsCall or not IsChainTarget(AReq.Target) or (Last = 0) then
    Exit;
  Chain := ChainFor(TRdxRecipes.QueryObjectOf(Trim(AReq.Target)), First, Last);
  ChainWith(AMap, Scopes, Chain, AReq.Prefix);
  AReq.ChainNames := Chain.Names;
end;

end.
