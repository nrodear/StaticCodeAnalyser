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
// `RawByteString` oder `ShortString` gecastet wird, fuehrt die
// Default-Locale-Conversion zu Datenverlust fuer alle Zeichen ausserhalb
// der jeweiligen Codepage. Klassischer Datenbank-Migration-Bug: Umlaute
// kommen als '?' raus, Smileys verschwinden, Excel/CSV werden korrupt.
//
// NICHT gemeldet wird `UTF8String(...)`: UTF8String ist
// `type AnsiString(CP_UTF8)`, der Cast erzeugt exakt denselben Code wie
// UTF8Encode und ist verlustfrei (FP-Audit Stufe 2, 2026-08-16).
//
// Erkennung (AST-basiert, heuristisch):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn Call-Name mit einem der String-Typ-Casts beginnt
//     (case-insensitive): `AnsiString(`, `RawByteString(`, `ShortString(`
//   * Skip-Heuristik: Argument ist leerer String-Literal ('')
//
// PREFIX-MATCH: die FN-Klasse und warum sie (noch) steht
// (Voll-Review 2026-09-12, Major 85)
//   Der Match greift nur am ANFANG von nkCall.Name bzw. nkAssign.TypeRef.
//   Der Parser legt je Statement genau EINEN Knoten an und faltet
//   Argumente als Text in den Namen (ParseCallOrAssign / ParsePrimary),
//   es gibt also keine Unterknoten fuer Teilausdruecke. Damit sind zwei
//   haeufige Formen systematisch blind:
//     SaveToFile(AnsiString(u));        // Cast in ARGUMENT-Position
//     a := 'x' + AnsiString(u);         // Cast MITTEN im RHS
//   Beide sind an der Bestands-Exe als Nicht-Funde belegt, waehrend die
//   Zuweisungsform derselben Zeile gemeldet wird.
//
//   Das ist KEINE gute Grenze, nur eine bewusst noch nicht gezogene:
//   ein Substring-Scan mit linker Wortgrenze wuerde sie schliessen. Er
//   ist hier bewusst NICHT eingebaut, weil er ein RECALL-PAKET ist.
//
//   PAKET 9001 - DIE GEFORDERTE FP-STICHPROBE IST GEFAHREN (2026-09-15),
//   ERGEBNIS: NICHT UMSETZEN.
//
//   Zuerst die Zahlen dieses Absatzes selbst, sie waren falsch: hier
//   stand "16.023 Dateien, 881 am Anfang / 1.828 nicht". Die
//   Grundgesamtheit stimmt nicht - der rekursive Scan nimmt nur *.pas,
//   und davon hat der Korpus 13.419 (die 16.023 zaehlen .dpr/.inc/.dpk
//   mit, die nie gescannt werden). Neu gezaehlt, Kommentare und
//   String-Literale ausgeschlossen: 3.890 Cast-Vorkommen, davon 2.517
//   mit linker Wortgrenze. Dieselbe Falle wie in Paket 9008 - die
//   Einheit gehoert zur Aussage.
//
//   Was Variante b braechte: rund 550 zusaetzliche Funde (Korridor
//   390-735), die Regel ginge von 414 auf etwa 990. Drops null, der
//   Prefix-Match ist eine echte Teilmenge des Wortgrenzen-Matches.
//
//   Woran es scheitert, ist die FP-QUOTE DER ADDS. Vier unabhaengige
//   Handpruefungen mit unterschiedlichen Stichproben kommen auf 18 %,
//   29 %, 50 % und 64 %. Die Spanne ist so breit, weil die Adds stark
//   konzentriert liegen (Alcinoe allein stellt rund ein Drittel, und
//   genau dessen A-Suffix-Helfer fuellen die
//   ASCII_SAFE_OPERAND_PREFIXES-Liste). Verlaesslich ist daher nur die
//   Aussage, die ALLE vier teilen: die Quote liegt weit ueber dem, was
//   das Projekt fuer eine ganze neue Fundklasse traegt. Fuer eine Regel
//   auf Error-Tier ist das zu teuer.
//
//   ZWEI HARTE VORBEDINGUNGEN, falls es doch einmal jemand angeht:
//   (1) ExtractCastOperand (:189) und ArgIsEmptyLiteral (:167) holen den
//       Operanden ueber einen FESTEN Offset ab Position 1. Wird nur
//       DetectAnsiCast umgestellt, lesen beide ab der falschen Stelle -
//       Variante b ist dann nicht ungenau, sondern kaputt.
//   (2) Die Wortgrenze ist nicht optional, sondern konstitutiv. Ohne
//       sie steigen die Kandidaten von 822 auf 2.091; die 1.269
//       Mehrtreffer verteilen sich auf 123 gewoehnliche Bezeichner -
//       FastSetRawByteString (195x), FastNewRawByteString (132x),
//       PSGetAnsiString (119x), PShortString (54x) und so weiter.
//
//   NOCH EINE BLINDE STELLE, bei der Messung nebenbei gefunden und
//   bisher nirgends notiert: in if-, while-, until-, case-Bedingungen
//   und for-in-Ausdruecken entsteht gar kein besuchter Knoten. Dort
//   feuert der Detektor auch dann nicht, wenn der Cast in
//   Prefix-Position steht - an der Exe belegt. Variante b wuerde daran
//   nichts aendern; 84 der 822 Kandidaten liegen genau dort.
//
//   Die zwei Formen sind als dokumentierende Tests festgehalten
//   (ArgumentPositionCast_NotReported_KnownLimit,
//   MidRhsCast_NotReported_KnownLimit) - faellt die Grenze, werden sie
//   rot und muessen bewusst umgestellt werden.
//
// Bewusste False-Positives (akzeptabel):
//   * `AnsiString(<expr>)` wenn <expr> bereits AnsiString ist (redundanter
//     Cast) - signalisiert Verwirrung oder Konversion zwischen Code-Pages.
//
// Sonar-Pendant: UnicodeToAnsiCastCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   UnicodeToAnsiCastCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnicodeToAnsiCastDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, RedundantJump, TooLongLine, UnsortedUses
// noinspection-file UnusedParameter
uses
  uAstSpans;   // CollectWithMethodScope (Voll-Review 2026-09-12)

// AContext ist der Kontext-Parameter aus der AddD-Registrierung (B10, 2026-08-16).
// Er wird HIER bewusst noch nicht gelesen: die Umstellung ist ein eigener,
// verhaltensneutraler Schritt VOR der Regelaenderung, die ihn braucht - so
// verlangt es die Fix-Spezifikation, damit im A/B trennbar bleibt, was die
// Zahlen bewegt hat. Die Datei hatte vorher NULL UnusedParameter-Funde,
// der Marker schaltet also nichts Bestehendes mit stumm.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Bekannte VERLUSTBEHAFTETE 8-bit-String-Cast-Praefixe mit oeffnender
  // Klammer.
  //
  // 'utf8string(' stand hier bis 2026-08-16 (FP-Audit Stufe 2) und war
  // schlicht falsch: UTF8String ist 'type AnsiString(CP_UTF8)', der Compiler
  // erzeugt fuer UTF8String(u) exakt System._UStrToLStr(dest, src, CP_UTF8) -
  // denselben Code wie das von der Meldung geforderte UTF8Encode.
  // DefaultSystemCodePage spielt keine Rolle, es geht kein Zeichen verloren.
  // 47 der 523 Korpus-Funde waren utf8string-Casts, keiner davon mit
  // 8-bit-Operand.
  //
  // 'rawbytestring(' bleibt (CP_NONE - die Konversion laeuft ueber
  // DefaultSystemCodePage), 'shortstring(' ebenso (zusaetzlich
  // 255-Byte-Trunkierung).
  //
  // Bewusst als Falschnegativ akzeptiert: UTF8String(<bereits 8-bit>) nimmt
  // den Umweg ueber die ACP und KANN Zeichen verlieren - im Korpus 0 Treffer,
  // eine zweite Typpruefung dafuer waere teurer als der Nutzen.
  CAST_PREFIXES: array of string = [
    'ansistring(', 'rawbytestring(', 'shortstring('
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

// True wenn der Operand ein ZEIGERFELD einer Variant-Record-Sicht ist
// ('TVarData(x).VAny', 'p^.VAny', 'V.VAnsiString'). Diese Felder halten
// eine bereits vorhandene AnsiString-REFERENZ; der Cast fasst deren
// Referenzzaehlung an und wandelt nichts. Codepage-Verlust ist dort
// ausgeschlossen - mormot.core.rtti.pas:6299 sagt es im Code selbst:
// "copy AnsiString with reference counting".
//
// Vollzaehlung 2026-09-04: 11 der 482 Korpusfunde (2,3 %), alle in
// mORMot, alle dieses Muster. Nur die beiden GEMESSENEN Feldnamen
// stehen hier - keine Heuristik ueber das 'V'-Praefix, sonst faenge das
// Gate irgendwann ein echtes String-Feld mit passendem Namen.
function OperandIsVariantPointerField(const Operand: string): Boolean;
const
  ZEIGERFELDER : array[0..1] of string = ('.vany', '.vansistring');
var
  Lower : string;
  F     : string;
begin
  Result := False;
  Lower := LowerCase(TrimRight(Operand));
  for F in ZEIGERFELDER do
    if (Length(Lower) >= Length(F))
       and (Copy(Lower, Length(Lower) - Length(F) + 1, Length(F)) = F) then
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
  if OperandIsVariantPointerField(Operand) then Exit;
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

procedure WalkAndCheck(Node: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Seit Voll-Review 2026-09-12 ueber den zentralen Scope-Walk
// (TAstSpans.CollectWithMethodScope) - Mechanik, Besuchsreihenfolge
// und Hardening v4 (iterative DFS, Audit_jvcl_segfault) identisch
// zur frueheren lokalen Kopie.
var
  P : TNodeScopePair;
begin
  for P in TAstSpans.CollectWithMethodScope(Node, [nkCall, nkAssign]) do
    case P.Node.Kind of
      nkCall:   CheckCastText(P.Node.Name,    P.Node, P.Method, FileName, Results);
      nkAssign: CheckCastText(P.Node.TypeRef, P.Node, P.Method, FileName, Results);
    end;
end;

class procedure TUnicodeToAnsiCastDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
begin
  WalkAndCheck(UnitNode, FileName, Results);
end;

end.
