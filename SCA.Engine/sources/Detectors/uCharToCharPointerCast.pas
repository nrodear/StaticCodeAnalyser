unit uCharToCharPointerCast;

// Detektor: `PChar(<Char>)` / `PWideChar(<Char>)` / `PAnsiChar(<Char>)`
// Cast - Char-Wert wird als Pointer reinterpretiert.
//
// Pattern (Bug, undefined behavior):
//   var c: Char;
//   var p: PChar;
//   begin
//     c := 'A';
//     p := PChar(c);          // <-- BAD: p zeigt auf Adresse $00000041
//     ShowMessage(p);         //     vermutlich Access-Violation
//   end;
//
//   p := PChar('A');          // <-- BAD: identisch zum Variablen-Cast
//
// Korrekt:
//   p := PChar(string(c));    // expliziter String-Wrap
//   p := PChar('A' + #0);     // null-terminierter 1-Zeichen-String
//
// Warum:
//   * `PChar(stringExpr)` ist die uebliche Form - Pointer auf Char-Buffer
//     einer Pascal-String, garantiert null-terminiert.
//   * `PChar(charExpr)` reinterpretiert den 16-bit-Char-Wert als Pointer.
//     Die "Adresse" ist also der Codepoint des Zeichens (z.B. $41 fuer 'A').
//     Jeder Deref liest aus zufaelligem Process-Memory.
//
// Erkennung (AST-basiert, heuristisch):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn `PChar(`/`PWideChar(`/`PAnsiChar(` IRGENDWO im Text
//     mit linker Wortgrenze steht - nicht nur am Anfang. Der Parser
//     legt fuer ein Call-Statement EINEN nkCall mit dem flachen
//     Gesamttext an; bei `StrPCopy(Buf, PChar('A'))` steht der Cast
//     in Argument-Position, und der alte Praefix-Match sah ihn nie
//     (Voll-Review 2026-09-12, Blocker). Gesucht wird im
//     positionserhaltend GEBLANKTEN Text (Cast in einem
//     String-Literal zaehlt nicht), das Argument kommt aus dem
//     ORIGINAL an derselben Position - es ist ja selbst ein Literal.
//   * Argument-Heuristik (innerhalb der Klammern):
//     - 1-Zeichen-Literal: `'X'` (3 Zeichen Quotes inklusive)
//     - Char-Ordinal: `#<digits>` (z.B. `#65`, `#$41`)
//     - `Chr(...)`-Call: liefert Char
//   * String-Literale (`'AB'`, `'hello'`) sind als String getypt -> skip.
//   * Identifier-Argumente (`PChar(someVar)`) - unbekannter Typ ohne
//     Resolver - skip (false-negative bewusst).
//
// Sonar-Pendant: CharacterToCharacterPointerCastCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   CharacterToCharacterPointerCastCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCharToCharPointerCastDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, MagicNumber, MultipleExit, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,               // PosEx
  uDetectorUtils;                // IsIdentChar, BlankStringLiterals

const
  CAST_PREFIXES: array of string = [
    'pchar(', 'pwidechar(', 'pansichar('
  ];

// Naechstes Cast-Vorkommen ab AFrom im GEBLANKTEN, gesenkten Text.
// Liefert die Position des Praefix-Starts (0 = keins), den Cast-Namen
// und die Position der oeffnenden Klammer. Linke Wortgrenze Pflicht -
// sonst matchte 'MyPChar(' oder 'GetPAnsiChar(' mit.
//
// Ersetzt den alten reinen PRAEFIX-Match (Voll-Review 2026-09-12,
// Blocker): der sah nur die Zuweisungsform 'p := PChar(...)'; jeder
// Cast in Argument-Position eines Calls war unsichtbar, obwohl der
// Kommentar an CheckCastText genau diesen Fall versprach.
function NextPCharCast(const BlankLower: string; AFrom: Integer;
  out CastType: string; out OpenParen: Integer): Integer;
var
  P    : string;
  ix   : Integer;
  best : Integer;
begin
  Result := 0; CastType := ''; OpenParen := 0;
  for P in CAST_PREFIXES do
  begin
    ix := PosEx(P, BlankLower, AFrom);
    while ix > 0 do
    begin
      if (ix = 1) or not TDetectorUtils.IsIdentChar(BlankLower[ix - 1]) then
        Break;
      ix := PosEx(P, BlankLower, ix + 1);
    end;
    if ix > 0 then
    begin
      best := Result;
      if (best = 0) or (ix < best) then
      begin
        Result    := ix;
        CastType  := Copy(P, 1, Length(P) - 1);
        OpenParen := ix + Length(P) - 1;
      end;
    end;
  end;
end;

// Argument-Text zwischen der Klammer bei AOpenParen und ihrer
// BALANCIERTEN Gegenklammer - aus dem ORIGINAL-Text, denn das Argument
// ist typisch selbst ein Literal. Klammern INNERHALB von
// Apostroph-Literalen zaehlen nicht (Quote-Zustand wird verfolgt).
// Der alte Weg ('letzte )' der Zeile) griff bei einem Cast mitten im
// Statement die falsche Klammer.
function BalancedCastArg(const Text: string; AOpenParen: Integer): string;
var
  i, Depth : Integer;
  InStr    : Boolean;
begin
  Result := '';
  if (AOpenParen <= 0) or (AOpenParen > Length(Text)) or
     (Text[AOpenParen] <> '(') then Exit;
  Depth := 0; InStr := False;
  // Flach gehalten (Guard-Stil): jede Bedingung eine Ebene - die
  // verschachtelte Erstfassung riss die eigene SCA176-Schwelle.
  for i := AOpenParen to Length(Text) do
  begin
    if Text[i] = '''' then
    begin
      InStr := not InStr;
      Continue;
    end;
    if InStr then Continue;
    if Text[i] = '(' then Inc(Depth);
    if Text[i] <> ')' then Continue;
    Dec(Depth);
    if Depth = 0 then
      Exit(Trim(Copy(Text, AOpenParen + 1, i - AOpenParen - 1)));
  end;
end;

// True wenn Arg ein Single-Char-Literal ist: `'X'` (3 Zeichen, Quotes drumherum).
// Doppelte Anfuehrungszeichen `''''` (= einzelnes Apostroph) sind 4 Zeichen.
function IsSingleCharLiteral(const Arg: string): Boolean;
begin
  Result := False;
  // Format 'X' (3 Zeichen)
  if (Length(Arg) = 3) and (Arg[1] = '''') and (Arg[3] = '''') and
     (Arg[2] <> '''') then
    Exit(True);
  // Format '''' (4 Zeichen) = escaped apostrophe
  if Arg = '''''''' then Exit(True);
end;

// True wenn Arg ein Char-Ordinal-Literal `#<digits>` oder `#$<hex>` ist.
function IsCharOrdinal(const Arg: string): Boolean;
var
  i : Integer;
  C : Char;
begin
  Result := False;
  if Length(Arg) < 2 then Exit;
  if Arg[1] <> '#' then Exit;
  // Rest muss Digits oder $<hex> sein.
  i := 2;
  if Arg[i] = '$' then Inc(i);
  if i > Length(Arg) then Exit;
  while i <= Length(Arg) do
  begin
    C := Arg[i];
    if not (((C >= '0') and (C <= '9')) or
            ((C >= 'A') and (C <= 'F')) or
            ((C >= 'a') and (C <= 'f'))) then
      Exit;
    Inc(i);
  end;
  Result := True;
end;

// True wenn Arg ein `Chr(...)`-Call ist (case-insensitive).
function IsChrCall(const Arg: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(Arg);
  Result := (Length(Lower) >= 5) and (Copy(Lower, 1, 4) = 'chr(') and
            (Lower[Length(Lower)] = ')');
end;

function ArgLooksLikeChar(const Arg: string): Boolean;
begin
  Result := IsSingleCharLiteral(Arg) or
            IsCharOrdinal(Arg) or
            IsChrCall(Arg);
end;

// Pruefen ob `Text` (Call-Name oder Assign-TypeRef) einen Char->PChar-Cast
// enthaelt; bei Treffer Befund anlegen. Wird sowohl fuer nkCall (bare call,
// z.B. SomeProc(PChar('A'))) als auch fuer nkAssign.TypeRef (typischer
// Fall: p := PChar('A')) aufgerufen - der Parser packt die RHS einer
// Zuweisung in TypeRef statt einen separaten nkCall-Knoten anzulegen.
procedure CheckCastText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  MethName   : string;
  CastType   : string;
  Arg        : string;
  BlankLower : string;
  P, OpenIx  : Integer;
begin
  // ALLE Vorkommen pruefen, nicht nur das erste: ein harmloser Cast
  // weiter vorn (PChar(stringVar)) darf einen char-Cast dahinter nicht
  // maskieren - die Erste-Treffer-Falle war eine eigene Blocker-Klasse
  // des Voll-Reviews. Gemeldet wird EIN Fund je Statement (gleiche
  // Zeile, gleiche Aussage - Doppelmeldungen truegen nur die Zahlen).
  BlankLower := LowerCase(TDetectorUtils.BlankStringLiterals(Text));
  P := 1;
  repeat
    P := NextPCharCast(BlankLower, P, CastType, OpenIx);
    if P = 0 then Exit;
    Arg := BalancedCastArg(Text, OpenIx);
    if ArgLooksLikeChar(Arg) then
    begin
      if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
      else MethName := '';
      Results.Add(TLeakFinding.New(FileName, MethName, Node.Line,
        Format('%s(Char) reinterprets codepoint as pointer - undefined behavior',
          [CastType]),
        fkCharToCharPointerCast));
      Exit;
    end;
    P := OpenIx + 1;
  until False;
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS mit Frame-Tracking. Verhindert
// STACK_OVERFLOW bei tief verschachteltem AST (siehe Audit_jvcl_segfault).
type
  TFrame = record
    N : TAstNode;
    M : TAstNode;   // CurrentMethod fuer diesen Knoten
  end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.M := CurrentMethod;
    Stack.Add(F);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case Cur.N.Kind of
        nkCall:
          CheckCastText(Cur.N.Name, Cur.N, Cur.M, FileName, Results);
        nkAssign:
          CheckCastText(Cur.N.TypeRef, Cur.N, Cur.M, FileName, Results);
      end;
      // Sub-Method-Boundary: nkMethod-Knoten startet eigenen Method-Scope
      var NextMeth : TAstNode;
      if Cur.N.Kind = nkMethod then NextMeth := Cur.N else NextMeth := Cur.M;
      for i := Cur.N.Children.Count - 1 downto 0 do
      begin
        F.N := Cur.N.Children[i]; F.M := NextMeth;
        Stack.Add(F);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TCharToCharPointerCastDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
