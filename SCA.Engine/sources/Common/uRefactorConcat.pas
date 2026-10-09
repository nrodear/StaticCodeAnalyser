unit uRefactorConcat;

// Zerlegt eine Zuweisung mit '+'-Kette in ihre Teilbereiche und haengt
// die Fakten daran (B2, B3, B4 der Refactoring-Schnittstelle).
// Konzept_Todo_RefactorInfo 2026-10-01, Inkrement 3.
//
//   Ziel := 'Hallo ' + Name + ', du bist ' + IntToStr(Age);
//   ^^^^    ^^^^^^^^   ^^^^   ^^^^^^^^^^^^   ^^^^^^^^^^^^^
//   target  literal    operand literal       operand (rvString)
//
// WER DAS BENUTZT
//
// Einziger Nutzer ist der Quellstellen-Dienst: TSourcePlaces.ChainOf und
// .CallOf (uSourcePlaces, Pull-Modell). Ein Konsument wie reDelphix hat
// zu einem SCA044-/SCA003-Fund nur Zeile und Knoten - der AST traegt die
// rechte Seite nur als abgeflachten String (TAstNode.TypeRef), daraus
// lassen sich keine Spalten gewinnen. Diese Unit liest die Quellzeilen
// ueber den uRefactorInfoBuilder und zerlegt auf dessen spaltentreuer
// Code-Sicht. Detektoren importieren diese Unit NICHT (das Push-Modell
// des Vorgaengers ag-refactorinfo ist verworfen); tools/places_dep_gate.py
// haelt die Richtung.
//
// DIESELBE ZAEHLUNG WIE ScanConcat
//
// Ein '+' trennt nur auf Klammertiefe 0 ('(' und '['), ausserhalb von
// Strings und Kommentaren - exakt die Regel von
// TConcatToFormatDetector.ScanConcat. Ein Aufrufer, der eine eigene
// Zaehlung hat (etwa aus TNodeRef.TypeRef des Knotens), gibt sie als
// AExpectedPlus mit; weicht die Zaehlung hier davon ab, kommt nil
// zurueck. Zwei Zaehlungen, die sich widersprechen, beschreiben nicht
// dieselbe Kette - dann wird nichts geliefert statt geraten.
// AExpectedPlus ist optional: ohne Zahl (ANY_PLUS_COUNT) sichert nur
// TargetMatches ab, dass Beschreibung und Knoten dieselbe Anweisung
// meinen. TSourcePlaces.ChainOf reicht die Zahl durch, wenn der
// Konsument sie mitgibt.
//
// WAS ALS STRING GILT (ValueType = rvString)
//
//   * ein String-Literal, auch mit Steuerzeichen ('a'#13#10),
//   * der Aufruf einer RTL-Funktion aus KNOWN_STRING_FUNCS, unqualifiziert
//     oder mit SysUtils./StrUtils. davor, dessen Klammer den Term
//     abschliesst,
//   * ein Term, der auf .ToString bzw. .ToString() endet.
// Alles andere bleibt rvUnknown. rvNonString wird hier NIE vergeben: ohne
// Typaufloesung ist "kein String" nicht beweisbar.
// ANNAHME bei den beiden Namensregeln: der unqualifizierte Name meint die
// RTL-Routine bzw. den Helper. Eine gleichnamige Funktion der Unit ohne
// String-Ergebnis ('function Trim(..): Variant') oder ein with-Block
// koennte ihn verdecken - das sieht diese Unit ohne AST nicht.
// TSourcePlaces prueft es gegen den AST und nimmt rvString dann zurueck
// (Review reDelphiX 2026-10-07, strittiger Minor 3).
//
// WANN FixSafe
//
// Nur wenn JEDER Term rvString ist, kein Term einen Operator auf oberster
// Ebene traegt ('=', '<', '-', 'and', ... - dann waere die rechte Seite
// keine reine Kette) und der Bereich weder einen Kommentar enthaelt noch
// in einem {$IFDEF}-Bereich liegt. Mehrzeiligkeit allein verhindert
// FixSafe NICHT: ein Zeilenumbruch hat in Pascal keine Bedeutung, und
// rfMultiLine steht fuer den Konsumenten gesondert in Flags.
//
// HINWEISE FUER KONSUMENTEN
//
//   * Ein '%' in einem Literal muss beim Bau eines Format-Strings zu '%%'
//     werden. Das ist Sache des Umschreibers, nicht dieser Beschreibung.
//   * FixSafe sagt nur: die Kette laesst sich verlustfrei umformen. Es
//     sagt NICHT, dass keine andere Regel dieselbe Anweisung meldet.
//     SCA044 klammert SQL nur ueber die linke Seite aus; baut eine lokale
//     Variable SQL zusammen, kann SCA003 dieselbe Anweisung melden (die
//     Beschreibung ist dieselbe - FixSafe weiss von dem zweiten Fund
//     nichts). Wer umschreibt, prueft deshalb vor dem Schreiben, ob ein
//     SCA003-Fund denselben Bereich trifft, und
//     laesst die Anweisung dann stehen - sonst formt ein Automat Code um,
//     der unter Sicherheits-Review steht, und der SCA003-Fund kann sich
//     dabei bewegen (aus der '+'-Heuristik in die Format-Heuristik).

interface

uses
  System.Classes,
  uAstNode, uRefactorInfo;

type
  TRefactorConcat = class
  public
    const
      // AExpectedPlus: die '+'-Zahl nicht gegenpruefen.
      ANY_PLUS_COUNT = -1;

    // Beschreibt die Zuweisung, die an (ALine, ACol) beginnt. Teilbereiche
    // in Quelltext-Reihenfolge: ROLE_TARGET, danach je Term ROLE_LITERAL
    // oder ROLE_OPERAND. Liefert nil, wenn die Anweisung keine Zuweisung
    // ist, sich nicht sauber zerlegen laesst oder die '+'-Zahl nicht zu
    // AExpectedPlus passt. Der Aufrufer besitzt das Ergebnis.
    class function TryDescribeAssign(AUnitNode: TAstNode; ALines: TStrings;
      ALine, ACol: Integer;
      AExpectedPlus: Integer = ANY_PLUS_COUNT): TRefactorInfo; static;

    // Wie TryDescribeAssign, aber fuer einen AUFRUF mit GENAU EINEM
    // Argument:  Query.SQL.Add('SELECT ' + x);
    // ROLE_TARGET ist dann der Aufrufkopf ('Query.SQL.Add'), die Terme sind
    // die der Kette im Argument. Liefert nil bei mehreren Argumenten, bei
    // leerer Argumentliste und wenn hinter der schliessenden Klammer noch
    // etwas anderes als ';' steht (der Aufruf ist dann Teil eines
    // groesseren Ausdrucks, kein eigenes Statement).
    class function TryDescribeCall(AUnitNode: TAstNode; ALines: TStrings;
      ALine, ACol: Integer): TRefactorInfo; static;

    // Aufruf mit BELIEBIG vielen Argumenten:  ExecuteFmt('..', [a, b]);
    // ROLE_TARGET ist der Aufrufkopf, je Argument ein ROLE_ARGUMENT-Bereich
    // (keine Zerlegung in Terme, ValueType rvUnknown, FixSafe False).
    // Liefert nil ohne Klammer, bei leerer Argumentliste und wenn hinter
    // der schliessenden Klammer mehr als ';' steht.
    class function TryDescribeCallArgs(AUnitNode: TAstNode; ALines: TStrings;
      ALine, ACol: Integer): TRefactorInfo; static;

    // Gegenprobe gegen den AST-Knoten: True wenn der ROLE_TARGET-Teilbereich
    // von AInfo - ohne Leerraum, ohne Gross/Klein - gleich AExpected ist.
    // Ein Aufrufer, der KEINE '+'-Zahl zum Gegenpruefen hat, sichert damit
    // ab, dass Beschreibung und Knoten dieselbe Anweisung meinen.
    class function TargetMatches(ALines: TStrings; AInfo: TRefactorInfo;
      const AExpected: string): Boolean; static;

    // Die vier Einzelfragen arbeiten auf der Code-Sicht EINES Terms
    // (Strings/Kommentare sind TRefactorInfoBuilder.VIEW_FILL).
    // True fuer ein reines String-Literal inkl. #13 / #$0D-Teilen.
    class function IsLiteralView(const AViewText: string): Boolean; static;
    // True wenn auf Klammertiefe 0 ein Operator oder Operator-Wort steht.
    class function HasTopLevelOperator(const AViewText: string): Boolean;
      static;
    // True fuer den Aufruf einer bekannten String-Funktion der RTL, dessen
    // Klammer den ganzen Term abschliesst.
    class function IsKnownStringCall(const AViewText: string): Boolean;
      static;
    class function EndsWithToString(const AViewText: string): Boolean;
      static;
  private
    class function ViewTextOf(const AView: TArray<string>;
      const ASpan, APart: TRefactorSpan): string; static;
    // Legt ROLE_TARGET und je Term einen (vorlaeufigen) ROLE_OPERAND an.
    // ACallMode = False: Ziel endet am ':=', Terme auf Klammertiefe 0.
    // ACallMode = True:  Ziel endet an der ersten '(', Terme auf Tiefe 1
    //                    bis zur zugehoerigen ')'.
    class function SplitChain(const AView: TArray<string>;
      AInfo: TRefactorInfo; ACallMode: Boolean;
      out APlusCount: Integer): Boolean; static;
    class procedure ClassifyParts(const AView: TArray<string>;
      AInfo: TRefactorInfo); static;
    // Kopf + je Argument ein ROLE_ARGUMENT; ',' trennt auf Tiefe 1.
    class function SplitArguments(const AView: TArray<string>;
      AInfo: TRefactorInfo): Boolean; static;
    // Zerlegt und klassifiziert auf einer schon gebauten AInfo.
    class function FillChain(AInfo: TRefactorInfo; ALines: TStrings;
      ACallMode: Boolean; AExpectedPlus: Integer): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, DeepNesting, MultipleExit, UnusedPublicMember
// Zeichenweiser Zerleger: die fruehen Ausstiege und die Verzweigung je
// Zeichenklasse sind hier die Sache selbst. Die vier Einzelfragen sind
// oeffentlich, weil die Tests sie einzeln festpinnen.

uses
  System.SysUtils,
  uRefactorInfoBuilder;

const
  // RTL-Funktionen, deren Ergebnis ein String ist. Bewusst kurz und nur
  // Namen aus System.SysUtils / System.StrUtils - keine Projekt-Namen.
  KNOWN_STRING_FUNCS: array[0..23] of string = (
    'inttostr', 'uinttostr', 'inttohex', 'floattostr', 'floattostrf',
    'formatfloat', 'currtostr', 'booltostr', 'datetostr', 'timetostr',
    'datetimetostr', 'formatdatetime', 'quotedstr', 'ansiquotedstr',
    'uppercase', 'lowercase', 'ansiuppercase', 'ansilowercase',
    'trim', 'trimleft', 'trimright', 'stringofchar', 'dupestring',
    'syserrormessage'
  );

  // Qualifizierer, hinter denen ein Name aus KNOWN_STRING_FUNCS wirklich
  // die RTL-Funktion ist. 'Obj.Trim(' gilt NICHT - das ist eine Methode
  // unbekannten Typs.
  KNOWN_UNIT_QUALIFIERS: array[0..3] of string = (
    'sysutils', 'system.sysutils', 'strutils', 'system.strutils'
  );

  // Woerter, die einen Term zu mehr machen als einem Operanden.
  OPERATOR_WORDS: array[0..19] of string = (
    'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is',
    'as', 'begin', 'end', 'case', 'try', 'asm', 'procedure', 'function',
    'if', 'then'
  );

function InList(const AValue: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(AList) to High(AList) do
    if AList[i] = AValue then
      Exit(True);
end;

function EndsWithText(const AText, ASuffix: string): Boolean;
begin
  Result := (Length(AText) >= Length(ASuffix))
    and (Copy(AText, Length(AText) - Length(ASuffix) + 1, Length(ASuffix))
         = ASuffix);
end;

{ ---- Einzelfragen auf der Code-Sicht eines Terms ---- }

class function TRefactorConcat.IsLiteralView(
  const AViewText: string): Boolean;
var
  i, n   : Integer;
  Digits : Integer;
begin
  Result := False;
  n := Length(AViewText);
  if n = 0 then Exit;
  i := 1;
  while i <= n do
  begin
    if AViewText[i] = TRefactorInfoBuilder.VIEW_FILL then
      Inc(i)
    else if AViewText[i] = '#' then
    begin
      // Steuerzeichen-Teil: #13 oder #$0D
      Inc(i);
      Digits := 0;
      if (i <= n) and (AViewText[i] = '$') then
      begin
        Inc(i);
        while (i <= n)
          and CharInSet(AViewText[i], ['0'..'9', 'A'..'F', 'a'..'f']) do
        begin
          Inc(i);
          Inc(Digits);
        end;
      end
      else
        while (i <= n) and CharInSet(AViewText[i], ['0'..'9']) do
        begin
          Inc(i);
          Inc(Digits);
        end;
      if Digits = 0 then Exit;
    end
    else
      Exit;
  end;
  Result := True;
end;

class function TRefactorConcat.HasTopLevelOperator(
  const AViewText: string): Boolean;
var
  i, k, n : Integer;
  Depth   : Integer;
  C       : Char;
  PrevSig : Char;
begin
  Result  := False;
  Depth   := 0;
  PrevSig := #0;
  n := Length(AViewText);
  i := 1;
  while i <= n do
  begin
    C := AViewText[i];
    if C <= ' ' then
    begin
      Inc(i);
      Continue;
    end;
    if TRefactorInfoBuilder.IsIdentStart(C) then
    begin
      k := i;
      while (k <= n) and TRefactorInfoBuilder.IsIdentChar(AViewText[k]) do
        Inc(k);
      // Hinter '.', '&', '$', '#' ist ein Wort kein Operator-Wort.
      if (Depth = 0) and not CharInSet(PrevSig, ['.', '&', '$', '#'])
         and InList(LowerCase(Copy(AViewText, i, k - i)), OPERATOR_WORDS) then
        Exit(True);
      PrevSig := AViewText[k - 1];
      i := k;
      Continue;
    end;
    if (C = '(') or (C = '[') then
      Inc(Depth)
    else if (C = ')') or (C = ']') then
    begin
      if Depth > 0 then Dec(Depth);
    end
    else if (Depth = 0)
         and CharInSet(C, ['=', '<', '>', '-', '*', '/', ';', ':', ',']) then
      Exit(True);
    PrevSig := C;
    Inc(i);
  end;
end;

class function TRefactorConcat.IsKnownStringCall(
  const AViewText: string): Boolean;
var
  T        : string;
  Head     : string;
  FuncName : string;
  P, i     : Integer;
  Dot      : Integer;
  Depth    : Integer;
  ClosePos : Integer;
begin
  Result := False;
  T := Trim(AViewText);
  P := Pos('(', T);
  if P <= 1 then Exit;
  Head := Trim(Copy(T, 1, P - 1));
  if Head = '' then Exit;
  Dot := 0;
  for i := 1 to Length(Head) do
    if Head[i] = '.' then
      Dot := i
    else if not TRefactorInfoBuilder.IsIdentChar(Head[i]) then
      Exit;
  FuncName := LowerCase(Copy(Head, Dot + 1, MaxInt));
  if not InList(FuncName, KNOWN_STRING_FUNCS) then Exit;
  if (Dot > 0)
     and not InList(LowerCase(Copy(Head, 1, Dot - 1)), KNOWN_UNIT_QUALIFIERS) then
    Exit;
  // Die bei P geoeffnete Klammer muss den Term abschliessen - sonst ist
  // es 'IntToStr(a).Foo' oder aehnliches.
  Depth    := 0;
  ClosePos := 0;
  for i := P to Length(T) do
    if T[i] = '(' then
      Inc(Depth)
    else if T[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        ClosePos := i;
        Break;
      end;
    end;
  Result := ClosePos = Length(T);
end;

class function TRefactorConcat.EndsWithToString(
  const AViewText: string): Boolean;
var
  T : string;
begin
  T := LowerCase(Trim(AViewText));
  Result := EndsWithText(T, '.tostring') or EndsWithText(T, '.tostring()');
end;

{ ---- Zerlegung ---- }

class function TRefactorConcat.ViewTextOf(const AView: TArray<string>;
  const ASpan, APart: TRefactorSpan): string;
var
  SB          : TStringBuilder;
  Li          : Integer;
  First, Last : Integer;
begin
  Result := '';
  First := APart.StartLine - ASpan.StartLine;
  Last  := APart.EndLine - ASpan.StartLine;
  if (First < 0) or (Last > High(AView)) or (Last < First) then Exit;
  if First = Last then
    Exit(Copy(AView[First], APart.StartCol, APart.EndCol - APart.StartCol));
  SB := TStringBuilder.Create;
  try
    SB.Append(Copy(AView[First], APart.StartCol, MaxInt));
    for Li := First + 1 to Last - 1 do
    begin
      SB.Append(' ');
      SB.Append(AView[Li]);
    end;
    SB.Append(' ');
    SB.Append(Copy(AView[Last], 1, APart.EndCol - 1));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRefactorConcat.SplitChain(const AView: TArray<string>;
  AInfo: TRefactorInfo; ACallMode: Boolean;
  out APlusCount: Integer): Boolean;
var
  Li, J      : Integer;
  LineNo     : Integer;
  V          : string;
  C          : Char;
  Depth      : Integer;
  BaseDepth  : Integer;   // Tiefe, auf der die Kette liegt (0 bzw. 1)
  Closed     : Boolean;   // Aufruf-Modus: schliessende Klammer gesehen
  SeenAssign : Boolean;   // Ziel abgeschlossen (':=' bzw. oeffnende '(')
  HaveSig    : Boolean;
  SigLine    : Integer;   // letztes signifikantes Zeichen
  SigCol     : Integer;
  TermOpen   : Boolean;
  TermLine   : Integer;
  TermCol    : Integer;

  procedure CloseTerm;
  begin
    AInfo.AddPart(TRefactorSpan.Make(ROLE_OPERAND, TermLine, TermCol,
      SigLine, SigCol + 1));
    TermOpen := False;
  end;

begin
  Result     := False;
  APlusCount := 0;
  Depth      := 0;
  BaseDepth  := 0;
  Closed     := False;
  SeenAssign := False;
  HaveSig    := False;
  SigLine    := 0;
  SigCol     := 0;
  TermOpen   := False;
  TermLine   := 0;
  TermCol    := 0;

  for Li := 0 to High(AView) do
  begin
    V := AView[Li];
    LineNo := AInfo.Span.StartLine + Li;
    J := 1;
    if Li = 0 then J := AInfo.Span.StartCol;
    while J <= Length(V) do
    begin
      C := V[J];
      if C <= ' ' then
      begin
        Inc(J);
        Continue;
      end;

      if (Depth = 0) and (C = ';') then
      begin
        // Erlaubt ist nur das ABSCHLIESSENDE Semikolon des Bereichs. Ein
        // frueheres auf Tiefe 0 gehoert zu einem Rumpf (anonyme Methode
        // ohne Klammer) - das ist keine einfache Kette.
        if (Li < High(AView)) or (J < Length(V)) then Exit;
        Inc(J);
        Continue;
      end;

      // Aufruf-Modus: hinter der schliessenden Klammer darf nur noch das
      // abschliessende ';' stehen (oben behandelt). Alles andere heisst:
      // der Aufruf ist Teil eines groesseren Ausdrucks.
      if Closed then Exit;

      if (Depth = 0) and (not SeenAssign) and (not ACallMode) and (C = ':')
         and (J < Length(V)) and (V[J + 1] = '=') then
      begin
        if not HaveSig then Exit;   // nichts vor dem ':='
        AInfo.AddPart(TRefactorSpan.Make(ROLE_TARGET, AInfo.Span.StartLine,
          AInfo.Span.StartCol, SigLine, SigCol + 1));
        SeenAssign := True;
        Inc(J, 2);
        Continue;
      end;

      if (Depth = 0) and (not SeenAssign) and ACallMode and (C = '(') then
      begin
        if not HaveSig then Exit;   // nichts vor der Klammer
        AInfo.AddPart(TRefactorSpan.Make(ROLE_TARGET, AInfo.Span.StartLine,
          AInfo.Span.StartCol, SigLine, SigCol + 1));
        SeenAssign := True;
        Depth      := 1;
        BaseDepth  := 1;
        Inc(J);
        Continue;
      end;

      if SeenAssign and (Depth = BaseDepth) and (C = '+') then
      begin
        if not TermOpen then Exit;  // leerer Term / unaeres Plus
        CloseTerm;
        Inc(APlusCount);
        Inc(J);
        Continue;
      end;

      if SeenAssign and ACallMode and (Depth = 1) then
      begin
        if C = ',' then Exit;       // mehrere Argumente
        if C = ')' then
        begin
          if not TermOpen then Exit;   // leere Argumentliste
          CloseTerm;
          Depth  := 0;
          Closed := True;
          Inc(J);
          Continue;
        end;
      end;

      if (C = '(') or (C = '[') then
        Inc(Depth)
      else if (C = ')') or (C = ']') then
      begin
        if Depth = 0 then Exit;
        Dec(Depth);
      end;
      if SeenAssign and not TermOpen then
      begin
        TermOpen := True;
        TermLine := LineNo;
        TermCol  := J;
      end;
      HaveSig := True;
      SigLine := LineNo;
      SigCol  := J;
      Inc(J);
    end;
  end;

  if ACallMode then
    // Der letzte Term wurde an der schliessenden Klammer abgeschlossen.
    Exit(Closed);
  if (not SeenAssign) or (not TermOpen) or (Depth <> 0) then Exit;
  CloseTerm;
  Result := True;
end;

class function TRefactorConcat.SplitArguments(const AView: TArray<string>;
  AInfo: TRefactorInfo): Boolean;
var
  Li, J    : Integer;
  LineNo   : Integer;
  V        : string;
  C        : Char;
  Depth    : Integer;
  SeenOpen : Boolean;   // oeffnende Klammer des Aufrufs gesehen
  Closed   : Boolean;   // schliessende Klammer gesehen
  HaveSig  : Boolean;
  SigLine  : Integer;
  SigCol   : Integer;
  ArgOpen  : Boolean;
  ArgLine  : Integer;
  ArgCol   : Integer;

  procedure CloseArg;
  begin
    AInfo.AddPart(TRefactorSpan.Make(ROLE_ARGUMENT, ArgLine, ArgCol,
      SigLine, SigCol + 1));
    ArgOpen := False;
  end;

begin
  Result   := False;
  Depth    := 0;
  SeenOpen := False;
  Closed   := False;
  HaveSig  := False;
  SigLine  := 0;
  SigCol   := 0;
  ArgOpen  := False;
  ArgLine  := 0;
  ArgCol   := 0;

  for Li := 0 to High(AView) do
  begin
    V := AView[Li];
    LineNo := AInfo.Span.StartLine + Li;
    J := 1;
    if Li = 0 then J := AInfo.Span.StartCol;
    while J <= Length(V) do
    begin
      C := V[J];
      if C <= ' ' then
      begin
        Inc(J);
        Continue;
      end;

      if (Depth = 0) and (C = ';') then
      begin
        if (Li < High(AView)) or (J < Length(V)) then Exit;
        Inc(J);
        Continue;
      end;
      if Closed then Exit;   // hinter ')' darf nur noch ';' stehen

      if (not SeenOpen) and (Depth = 0) and (C = '(') then
      begin
        if not HaveSig then Exit;   // kein Kopf vor der Klammer
        AInfo.AddPart(TRefactorSpan.Make(ROLE_TARGET, AInfo.Span.StartLine,
          AInfo.Span.StartCol, SigLine, SigCol + 1));
        SeenOpen := True;
        Depth    := 1;
        Inc(J);
        Continue;
      end;

      if SeenOpen and (Depth = 1) then
      begin
        if C = ',' then
        begin
          if not ArgOpen then Exit;   // leeres Argument
          CloseArg;
          Inc(J);
          Continue;
        end;
        if C = ')' then
        begin
          if not ArgOpen then Exit;   // leere Argumentliste
          CloseArg;
          Depth  := 0;
          Closed := True;
          Inc(J);
          Continue;
        end;
      end;

      if (C = '(') or (C = '[') then
        Inc(Depth)
      else if (C = ')') or (C = ']') then
      begin
        if Depth = 0 then Exit;
        Dec(Depth);
      end;
      if SeenOpen and not ArgOpen then
      begin
        ArgOpen := True;
        ArgLine := LineNo;
        ArgCol  := J;
      end;
      HaveSig := True;
      SigLine := LineNo;
      SigCol  := J;
      Inc(J);
    end;
  end;
  Result := Closed;
end;

class procedure TRefactorConcat.ClassifyParts(const AView: TArray<string>;
  AInfo: TRefactorInfo);
var
  i         : Integer;
  Text      : string;
  AllString : Boolean;
  PureChain : Boolean;
begin
  AllString := True;
  PureChain := True;
  for i := 0 to High(AInfo.Parts) do
  begin
    if AInfo.Parts[i].Role = ROLE_TARGET then Continue;
    Text := ViewTextOf(AView, AInfo.Span, AInfo.Parts[i]);
    if IsLiteralView(Text) then
    begin
      AInfo.Parts[i].Role      := ROLE_LITERAL;
      AInfo.Parts[i].ValueType := rvString;
    end
    else if HasTopLevelOperator(Text) then
      PureChain := False
    else if IsKnownStringCall(Text) or EndsWithToString(Text) then
      AInfo.Parts[i].ValueType := rvString;
    if AInfo.Parts[i].ValueType <> rvString then
      AllString := False;
  end;
  AInfo.FixSafe := PureChain and AllString
    and not (rfHasComment in AInfo.Flags)
    and not (rfInConditional in AInfo.Flags);
end;

{ ---- Oeffentlicher Einstieg ---- }

class function TRefactorConcat.FillChain(AInfo: TRefactorInfo;
  ALines: TStrings; ACallMode: Boolean; AExpectedPlus: Integer): Boolean;
var
  View      : TArray<string>;
  PlusCount : Integer;
begin
  Result := False;
  View := TRefactorInfoBuilder.CodeViewOf(ALines, AInfo.Span);
  if Length(View) = 0 then Exit;
  if not SplitChain(View, AInfo, ACallMode, PlusCount) then Exit;
  if (AExpectedPlus <> ANY_PLUS_COUNT) and (PlusCount <> AExpectedPlus) then
    Exit;
  ClassifyParts(View, AInfo);
  Result := True;
end;

class function TRefactorConcat.TryDescribeAssign(AUnitNode: TAstNode;
  ALines: TStrings; ALine, ACol: Integer;
  AExpectedPlus: Integer): TRefactorInfo;
begin
  Result := TRefactorInfoBuilder.TryBuildForStatement(AUnitNode, ALines,
    ALine, ACol);
  if Assigned(Result) and not FillChain(Result, ALines, False,
    AExpectedPlus) then
    FreeAndNil(Result);
end;

class function TRefactorConcat.TryDescribeCall(AUnitNode: TAstNode;
  ALines: TStrings; ALine, ACol: Integer): TRefactorInfo;
begin
  Result := TRefactorInfoBuilder.TryBuildForStatement(AUnitNode, ALines,
    ALine, ACol);
  if Assigned(Result) and not FillChain(Result, ALines, True,
    ANY_PLUS_COUNT) then
    FreeAndNil(Result);
end;

class function TRefactorConcat.TryDescribeCallArgs(AUnitNode: TAstNode;
  ALines: TStrings; ALine, ACol: Integer): TRefactorInfo;
var
  View : TArray<string>;
begin
  Result := TRefactorInfoBuilder.TryBuildForStatement(AUnitNode, ALines,
    ALine, ACol);
  if not Assigned(Result) then Exit;
  View := TRefactorInfoBuilder.CodeViewOf(ALines, Result.Span);
  if (Length(View) = 0) or not SplitArguments(View, Result) then
    FreeAndNil(Result);
  // FixSafe bleibt False: ohne Zerlegung der Argumente ist nichts bewiesen.
end;

class function TRefactorConcat.TargetMatches(ALines: TStrings;
  AInfo: TRefactorInfo; const AExpected: string): Boolean;

  // Ohne Leerraum, klein geschrieben, Indexinhalte zu '[]' - der AST-
  // Knoten traegt das Ziel als zusammengefuegte Token und jeden Index als
  // '[]' (uParser2.ParsePrimary), der Quelltext mit beliebigem Leerraum
  // und dem echten Index. 'StatusBar1.Panels[1].Text' blieb so bis AH22
  // unbeschreibbar (53 von 2.363 SCA044-Korpusstellen).
  function Squeeze(const S: string): string;
  var
    i, n  : Integer;
    Depth : Integer;
  begin
    SetLength(Result, Length(S));
    n := 0;
    Depth := 0;
    for i := 1 to Length(S) do
    begin
      if S[i] = '[' then
      begin
        Inc(Depth);
        if Depth > 1 then Continue;
      end
      else if S[i] = ']' then
      begin
        if Depth > 0 then Dec(Depth);
        if Depth > 0 then Continue;
      end
      else if (Depth > 0) or (S[i] <= ' ') then
        Continue;
      Inc(n);
      Result[n] := S[i];
    end;
    SetLength(Result, n);
    Result := LowerCase(Result);
  end;

begin
  Result := Assigned(AInfo) and (Length(AInfo.Parts) > 0)
    and (AInfo.Parts[0].Role = ROLE_TARGET)
    and (Squeeze(TRefactorInfoBuilder.SpanText(ALines, AInfo.Parts[0]))
         = Squeeze(AExpected))
    and (Squeeze(AExpected) <> '');
end;

end.
