unit uUnicodeToAnsiCast;

// Detektor: Cast auf einen 8-bit-String-Typ ohne expliziten Encoding-Aufruf.
//
// Pattern (Bug, stiller Datenverlust):
//   var u: UnicodeString;
//   var a: AnsiString;
//   begin
//     u := 'Grueessli von der ?üß-Front';
//     a := AnsiString(u);           // <-- Daten-Loss fuer Codepunkte > 127
//     SaveToFile(a);
//   end;
//
// Korrekt:
//   a := UTF8Encode(u);             // explizit UTF-8 als Transport
//   // oder
//   a := AnsiString(u);             // mit dokumentiertem Akzept dass nur
//                                   //   ASCII durchgeleitet wird
//
// Folge: Bei jeder Stelle wo `UnicodeString`-Inhalt in `AnsiString`,
// `UTF8String`, `RawByteString` oder `ShortString` gecastet wird, fuehrt
// die Default-Locale-Conversion zu Datenverlust fuer alle Zeichen ausser-
// halb der jeweiligen Codepage. Klassischer Datenbank-Migration-Bug:
// Umlaute kommen als '?' raus, Smileys verschwinden, Excel/CSV werden
// korrupt.
//
// Erkennung (AST-basiert, heuristisch):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn Call-Name mit einem der String-Typ-Casts beginnt
//     (case-insensitive): `AnsiString(`, `UTF8String(`, `RawByteString(`,
//     `ShortString(`
//   * Skip-Heuristik: Argument ist leerer String-Literal ('')
//
// Bewusste False-Positives (akzeptabel):
//   * `AnsiString(<expr>)` wenn <expr> bereits AnsiString ist (redundanter
//     Cast) - signalisiert Verwirrung oder Konversion zwischen Code-Pages.
//   * `UTF8String(<utf8expr>)` ditto.
//
// Sonar-Pendant: UnicodeToAnsiCastCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   UnicodeToAnsiCastCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnicodeToAnsiCastDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Bekannte 8-bit-String-Cast-Praefixe mit oeffnender Klammer.
  CAST_PREFIXES: array of string = [
    'ansistring(', 'utf8string(', 'rawbytestring(', 'shortstring('
  ];

  // Real-World-FP-Audit 2026-07-10: Operand-Praefixe bei denen KEIN
  // Codepage-Verlust moeglich ist, daher unterdruecken.
  //  * ASCII-only-Produzenten der RTL (IntToStr/IntToHex liefern nur
  //    Ziffern/Minus/Hex -> immer <=127).
  //  * Alcinoe-A-Suffix-Helfer (ALIntToStrA/... liefern bereits AnsiString
  //    aus reinen ASCII-Ziffern).
  //  * Operand ist bereits ein 8-bit-/byte-orientierter Typ (AnsiString,
  //    UTF8String, RawByteString, ShortString, PAnsiChar, AnsiChar) - der
  //    Cast ist dann ein No-op / Byte-Copy ohne DefaultSystemCodePage-
  //    Konversion (z.B. AnsiString(PAnsiChar(@x[0])), AnsiString(ALIntToStrA(n))).
  ASCII_SAFE_OPERAND_PREFIXES: array of string = [
    'inttostr(', 'inttohex(',
    'alinttostra(', 'alinttohexa(', 'aluinttostra(', 'aluinttohexa(',
    // Review-Fix 2026-07-11: nur echte Byte-No-Ops. utf8string(/rawbytestring(/
    // shortstring( ENTFERNT - AnsiString(UTF8String(u)) mit non-ASCII u IST eine
    // verlustbehaftete CP_ACP-Konversion, kein ASCII-No-Op (sonst FN).
    'ansistring(', 'pansichar(', 'ansichar(', 'pansistring('
  ];

// Liefert den Cast-Typ-Namen wenn der Call-Name mit einem der 8-bit-String-
// Casts beginnt, sonst leer.
function DetectAnsiCast(const CallName: string): string;
var
  Lower : string;
  P     : string;
begin
  Result := '';
  Lower := LowerCase(TrimLeft(CallName));
  for P in CAST_PREFIXES do
    if (Length(Lower) >= Length(P)) and (Copy(Lower, 1, Length(P)) = P) then
    begin
      Result := Copy(P, 1, Length(P) - 1); // ohne trailing '('
      Exit;
    end;
end;

// True wenn das einzige Argument des Casts ein leerer Pascal-String-Literal
// ist - dann ist kein Datenverlust moeglich und wir wollen kein Finding.
//
// `AnsiString('')` landet im Parser-Body als String mit zwei Apostrophen
// (`''` als 2 Zeichen, nicht als Pascal-Empty-Literal). Wir pruefen daher
// auf Body = '<apos><apos>' nach Trim.
function ArgIsEmptyLiteral(const CallName: string): Boolean;
var
  Body : string;
  L, P : Integer;
begin
  Result := False;
  P := Pos('(', CallName);
  if P <= 0 then Exit;
  // Inhalt zwischen '(' und ')' extrahieren, trailing ')' wegschneiden.
  Body := Copy(CallName, P + 1, Length(CallName) - P);
  L := Length(Body);
  while (L > 0) and ((Body[L] = ')') or (Body[L] = ';') or (Body[L] = ' ')) do
    Dec(L);
  Body := Trim(Copy(Body, 1, L));
  // Pascal-leerer-String-Literal: zwei Apostrophe direkt hintereinander.
  Result := (Length(Body) = 2) and (Body[1] = '''') and (Body[2] = '''');
end;

// Real-World-FP-Audit 2026-07-10: Extrahiert das Operand-Argument eines
// 8-bit-String-Casts, d.h. den Text zwischen der ersten oeffnenden Klammer
// und der zugehoerigen schliessenden Klammer (Klammer-Tiefe getrackt,
// String-Literale werden uebersprungen damit '(' / ')' darin nicht zaehlen).
function ExtractCastOperand(const CallText: string): string;
var
  i, n, depth, startIdx : Integer;
  inStr                 : Boolean;
  c                     : Char;
begin
  Result := '';
  n := Length(CallText);
  i := Pos('(', CallText);
  if i <= 0 then Exit;
  startIdx := i + 1;
  depth    := 1;
  inStr    := False;
  Inc(i);
  while i <= n do
  begin
    c := CallText[i];
    if inStr then
    begin
      if c = '''' then inStr := False;
    end
    else
    begin
      case c of
        '''': inStr := True;
        '(':  Inc(depth);
        ')':
          begin
            Dec(depth);
            if depth = 0 then
            begin
              Result := Trim(Copy(CallText, startIdx, i - startIdx));
              Exit;
            end;
          end;
      end;
    end;
    Inc(i);
  end;
  // Keine schliessende Klammer im Text -> Rest ab Operand-Start.
  Result := Trim(Copy(CallText, startIdx, n - startIdx + 1));
end;

// Real-World-FP-Audit 2026-07-10: True wenn der Operand ein reines
// String-Literal ist dessen Codepunkte alle <=127 sind. ASCII kann bei
// keiner Codepage verlorengehen -> kein Datenverlust, kein Finding.
// (Konservativ: Operand muss mit Apostroph beginnen UND enden; damit
// bleibt z.B. AnsiString('a' + UnicodeVar) - endet nicht auf Apostroph -
// als echter Befund erhalten.)
function IsAsciiStringLiteral(const Operand: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if Length(Operand) < 2 then Exit;
  if (Operand[1] <> '''') or (Operand[Length(Operand)] <> '''') then Exit;
  for i := 1 to Length(Operand) do
    if Ord(Operand[i]) > 127 then Exit;
  Result := True;
end;

// Real-World-FP-Audit 2026-07-10: True wenn der Operand mit einem
// ASCII-sicheren Praefix beginnt (RTL-Zahlkonversion, Alcinoe-A-Helfer
// oder bereits 8-bit-Typ). In diesen Faellen ist kein Codepage-Verlust
// moeglich.
function OperandIsAsciiSafe(const Operand: string): Boolean;
var
  Lower : string;
  P     : string;
begin
  Result := False;
  Lower := LowerCase(TrimLeft(Operand));
  for P in ASCII_SAFE_OPERAND_PREFIXES do
    if (Length(Lower) >= Length(P)) and (Copy(Lower, 1, Length(P)) = P) then
      Exit(True);
end;

// Pruefen ob `Text` einen AnsiString/AnsiChar/UTF8String/RawByteString/
// ShortString-Cast enthaelt und entsprechend Befund anlegen. Wird sowohl
// fuer nkCall (bare call) als auch nkAssign.TypeRef (typische Form
// `a := AnsiString(u)` - der Parser legt die RHS in TypeRef ab und
// erzeugt KEINEN separaten nkCall-Knoten, sonst silent miss).
// Audit V5, 2026-05-30.
procedure CheckCastText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  F        : TLeakFinding;
  MethName : string;
  CastType : string;
  Operand  : string;
begin
  CastType := DetectAnsiCast(Text);
  if CastType = '' then Exit;
  if ArgIsEmptyLiteral(Text) then Exit;
  // Real-World-FP-Audit 2026-07-10: Operand aufloesen und drei FP-Klassen
  // unterdruecken (ASCII-Literal / ASCII-Produzent / bereits-8-bit-Operand).
  // Loest der Operand nicht klar auf -> weiter melden (kein TP-Verlust).
  Operand := ExtractCastOperand(Text);
  if IsAsciiStringLiteral(Operand) then Exit;
  if OperandIsAsciiSafe(Operand) then Exit;
  if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
  else MethName := '';
  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethName;
  F.LineNumber := IntToStr(Node.Line);
  F.MissingVar := Format(
    '%s(...) cast loses characters outside the active code page - use UTF8Encode/explicit encoding',
    [CastType]);
  F.SetKind(fkUnicodeToAnsiCast);
  Results.Add(F);
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS - siehe Audit_jvcl_segfault.
type TFrame = record N, M: TAstNode; end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
  NextMeth : TAstNode;
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
        nkCall:   CheckCastText(Cur.N.Name,    Cur.N, Cur.M, FileName, Results);
        nkAssign: CheckCastText(Cur.N.TypeRef, Cur.N, Cur.M, FileName, Results);
      end;
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

class procedure TUnicodeToAnsiCastDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
