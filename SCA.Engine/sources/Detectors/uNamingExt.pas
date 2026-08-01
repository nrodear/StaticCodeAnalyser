unit uNamingExt;

// Naming-Familie erweitert (SCA118-119).
//
//   * fkExceptionName        - Exception-Descendant ohne E-Prefix
//                              (z.B. MyError statt EMyError)
//   * fkLocalConstantName    - const im Methoden-Body sollte UPPER_SNAKE
//                              (z.B. MAX_RETRIES); PascalCase = Smell
//
// Beide AST-basiert: ExceptionName auf nkClass-Knoten mit Exception-
// Vererbung; LocalConstantName auf nkConst innerhalb von nkMethod.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNamingExtDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsExceptionDescendant(const TypeRef: string): Boolean;
// True wenn das TypeRef-Feld eines Class-Nodes auf einer Exception-Klasse
// basiert. Match auf 'Exception' oder klassische E-prefixed Vorfahren.
var
  Lower : string;
begin
  Lower := LowerCase(TypeRef);
  Result :=
    (Pos('exception',         Lower) > 0) or
    (Pos('eaborterror',       Lower) > 0) or
    (Pos('eaccessviolation',  Lower) > 0) or
    (Pos('eexternal',         Lower) > 0);
end;

// TypeRef-Format eines Konstanten-nkField (uParser2.ParseVarLikeSection):
//   'Typ=Wert'  bei 'const X: Integer = 5;'
//   '=Wert'     bei 'const X = 5;'
// Liefert False, wenn gar kein '=' vorkommt - siehe Gate 1 unten.
function SplitConstRef(const ATypeRef: string;
  out ATypePartLow, AValue: string): Boolean;
var
  p : Integer;
begin
  ATypePartLow := '';
  AValue       := '';
  p := Pos('=', ATypeRef);
  Result := p > 0;
  if not Result then Exit;
  ATypePartLow := LowerCase(Trim(Copy(ATypeRef, 1, p - 1)));
  AValue       := Trim(Copy(ATypeRef, p + 1, MaxInt));
end;

// KONSTANTEN-GATES (30%-Real-World-Audit 2026-07-31: 5.526 Funde, 71 % FP).
//
// Alle vier Pruefungen unterdruecken nur - der bestehende String/Char-Skip auf
// dem VOLLEN TypeRef bleibt daneben unveraendert stehen (er greift auch, wenn
// der Wert das Wort 'string' enthaelt; ihn auf den Typteil zu verengen waere
// praeziser, wuerde aber Funde HINZUFUEGEN und die Monotonie brechen).
function ConstIsExemptFromNaming(const ATypeRef: string): Boolean;
var
  TypeLow, Val : string;
  i, Depth     : Integer;
begin
  Result := True;

  // GATE 1: kein '=' im TypeRef -> das ist keine Konstanten-Deklaration.
  // Eine gueltige Pascal-Konstante MUSS initialisiert sein, der Parser haengt
  // den Wert also immer an. Fehlt er, stammt der Knoten aus einem
  // Initialisierer: der Wert-Scan in ParseVarLikeSection ist nicht
  // klammerbalanciert und bricht am ersten ';' ab - auch wenn das INNERHALB
  // der Klammern steht. Aus
  //   Zones: array[..] of TZone = ((TimeZone:'NST'; Offset:'-0330'), ...);
  // wird ab dem ';' ein neuer Durchlauf, und 'Offset' landet als eigene
  // "Konstante". Der Parser-Fix dazu liegt bewusst ausserhalb dieser Serie
  // (er veraendert die Sichtweite anderer Detektoren); hier faellt der
  // Phantom-Knoten am fehlenden '=' auf.
  if not SplitConstRef(ATypeRef, TypeLow, Val) then Exit;

  // GATE 2: ueberzaehlige schliessende Klammer im Typteil - zweite Signatur
  // desselben Phantoms, falls der Wert-Scan doch noch ein '=' eingesammelt hat.
  Depth := 0;
  for i := 1 to Length(TypeLow) do
  begin
    if TypeLow[i] = '(' then Inc(Depth)
    else if TypeLow[i] = ')' then
    begin
      Dec(Depth);
      if Depth < 0 then Exit;
    end;
  end;

  // GATE 3: strukturierte Konstante. Die Regel empfiehlt UPPER_SNAKE_CASE
  // ausdruecklich fuer 'numeric constants'; ein Array-/Record-Konstanten-
  // Aggregat ist keine. Erkennbar am Klammer-Aggregat als Wert oder am
  // Typnamen (Tokens stehen ohne Trenner aneinander: 'array[boolean]ofdword').
  if (Val <> '') and (Val[1] = '(') then Exit;
  if (Pos('array',  TypeLow) > 0) or
     (Pos('record', TypeLow) > 0) or
     (Pos('setof',  TypeLow) > 0) then Exit;

  // GATE 4: String-/Char-Konstante OHNE Typannotation. Der bestehende Skip
  // sieht nur den deklarierten Typ; 'cItemField = ''ItemField''' hat keinen,
  // deshalb hier der Literal-Typ des Initialisierers. '#80' ist ein
  // Char-Literal, ''...''' ein String - beides faellt nicht unter die Regel.
  if (Val <> '') and CharInSet(Val[1], ['''', '#']) then Exit;

  Result := False;
end;

function IsUpperSnake(const Name: string): Boolean;
// True wenn Name nur aus A-Z, 0-9, _ besteht (klassisches Konstanten-
// Naming wie MAX_RETRIES).
var
  i : Integer;
begin
  Result := False;
  if Name = '' then Exit;
  for i := 1 to Length(Name) do
    if not CharInSet(Name[i], ['A'..'Z', '0'..'9', '_']) then
      Exit(False);
  Result := True;
end;

class procedure TNamingExtDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes : TList<TAstNode>;
  Methods : TList<TAstNode>;
  C, M, K : TAstNode;
  F       : TLeakFinding;
  i       : Integer;
begin
  // ExceptionName: nkClass mit Exception-Parent, Name ohne E-Prefix
  Classes := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
    begin
      if C.Name = '' then Continue;
      if not IsExceptionDescendant(C.TypeRef) then Continue;
      // Skip Eigenname startet mit 'E' (case-sensitive)
      if (Length(C.Name) >= 2) and (C.Name[1] = 'E') and
         CharInSet(C.Name[2], ['A'..'Z']) then Continue;
      // Skip 'Exception' selbst (Delphi-RTL-Klasse, nicht User-Code)
      if SameText(C.Name, 'Exception') then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := C.Name;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar :=
        Format('Exception class %s should start with ''E'' prefix ' +
               '(Delphi-RTL convention: EAbort, EDivByZero, EMyError). ' +
               'Suggested: E%s',
               [C.Name, C.Name]);
      F.SetKind(fkExceptionName);
      Results.Add(F);
    end;
  finally
    Classes.Free;
  end;

  // LocalConstantName: nkConstSection-Children (nkField) innerhalb eines
  // nkMethod-Knotens. Der Parser legt lokale const X = Wert; Eintraege
  // als nkField unter einer nkConstSection ab (siehe uParser2.pas:386 +
  // uFormatMismatch.pas:420 fuer das Muster).
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      // NUR die const-Sektion des DEKLARATIONSTEILS (direktes Kind der
      // Methode), nicht rekursiv. Seit der Inline-const-Unterstuetzung
      // (2026-07-26, uParser2.ParseInlineConstStmt) legt der Parser auch
      // 'const X = 42;' MITTEN IM RUMPF als nkConstSection ab - die liegt
      // aber im nkBlock, also tiefer. FindAll haette sie mitgezaehlt:
      // im Real-World-Korpus schlug das mit +523 Funden auf (deltaT,
      // interpolated, CPartBase ...). Inline-Konstanten schreibt man in
      // Delphi 10.3+ wie lokale Variablen (camelCase/PascalCase);
      // UPPER_SNAKE_CASE ist die Konvention der Unit-/Klassen-Ebene, auf
      // die diese Regel zielt. Sie hier zu fordern waere reines Rauschen.
      var Sections := TList<TAstNode>.Create;
      try
        for var Cand in M.Children do
          if Cand.Kind = nkConstSection then Sections.Add(Cand);
        for var Section in Sections do
          for i := 0 to Section.Children.Count - 1 do
          begin
            K := Section.Children[i];
            if K.Kind <> nkField then Continue;
            if K.Name = '' then Continue;
            // Sehr kurze Konst-Namen (z.B. 'i' als Loop-Counter) ueberspringen
            if Length(K.Name) <= 2 then Continue;
            if IsUpperSnake(K.Name) then Continue;
            // Strings / Chars sind oft Localisierte UI-Labels, wo
            // PascalCase OK ist - skip. (Heuristik via TypeRef-Inhalt.)
            if (K.TypeRef <> '') and
               ((Pos('string', LowerCase(K.TypeRef)) > 0) or
                (Pos('char',   LowerCase(K.TypeRef)) > 0)) then Continue;
            // Konstanten-Gates (Audit 2026-07-31): Phantom-Knoten aus
            // Initialisiererlisten, strukturierte Konstanten und
            // String-/Char-Literale ohne Typannotation. Reine Unterdrueckung.
            if ConstIsExemptFromNaming(K.TypeRef) then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := M.Name;
            F.LineNumber := IntToStr(K.Line);
            F.MissingVar :=
              Format('Local const %s in %s - consider UPPER_SNAKE_CASE ' +
                     '(MAX_RETRIES, BUFFER_SIZE) for numeric constants. ' +
                     'Helps reader distinguish constants from variables at ' +
                     'a glance.',
                     [K.Name, M.Name]);
            F.SetKind(fkLocalConstantName);
            Results.Add(F);
          end;
      finally
        Sections.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
