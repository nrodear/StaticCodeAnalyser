unit uFloatEquality;

// Detektor: `=` oder `<>` zwischen Float-Operanden (Single/Double/Extended/
// Real/Currency).
//
// Pattern (Bug, Sonar-50 #19):
//   var Ratio: Double;
//   begin
//     ...
//     if Ratio = 0.5 then           // <- IEEE-754 macht das fast nie wahr
//       DoStuff;
//   end;
//
// Korrekt:
//   if SameValue(Ratio, 0.5, 1e-9) then DoStuff;
//   // oder Math.IsZero / Math.IsZero(Ratio - 0.5)
//
// Folge: bei Float-Arithmetik garantiert IEEE-754 keine exakte Gleichheit -
// `0.1 + 0.2 = 0.3` ergibt False. Equality-Checks sind silent-bug, weil sie
// in 99% der Faelle plausibel aussehen aber gelegentlich falsch laufen.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Phase 1: sammle Float-Variablen aus Deklarationen.
//     Pattern: `<ident>: Single|Double|Extended|Real|Currency;`
//   * Phase 2: scanne nach ` <ident> = <expr> ` oder ` <expr> = <ident> `
//     in if-/while-/until-Kontexten, wo <ident> aus der Float-Var-Liste
//     stammt. Operator-Match auch fuer `<>`.
//
// FP-Schutz fuer Scope-Blindheit:
//   Wenn 'Value' in einer Float-Record-Felddeklaration vorkommt UND
//   gleichzeitig ein anderer Pointer-/Boolean-Parameter den gleichen
//   Namen hat, wuerde der Detector ohne Filter `Value = nil` flaggen.
//   NEVER_FLOAT_TOKENS (nil/true/false) wird als Operand explizit
//   ausgeschlossen - das sind nie Floats.
//
// Limitierungen:
//   * Keine Type-Inferenz fuer Function-Returns oder Parameter
//   * Konstante Literale (`0.5`, `1.0`) auf einer Seite werden korrekt
//     erkannt wenn die andere Seite eine Float-Var ist.
//   * Komplexere Ausdruecke (`a + b = c + d`) muessen mindestens EINEN
//     Float-Var-Operanden enthalten damit der Detector triggert.
//
// Schweregrad: lsWarning - Sonar-50 #19.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TFloatEqualityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils, uTypeResolver;

const
  FLOAT_TYPES : array[0..4] of string =
    ('single', 'double', 'extended', 'real', 'currency');

  // Tokens die syntaktisch ein Operand sein koennen, semantisch aber NIE
  // ein Float-Wert sind. Wenn eine Seite des '='-Vergleichs eines davon
  // ist, ist es kein Float-Equality - egal ob die andere Seite zufaellig
  // mit einer Float-Var-Namens-Kollision matched.
  //
  // Realer FP-Trigger: NullableString.Implicit(const Value: Pointer) hat
  //   if Value = nil then ...
  // Detector hat in FloatVars ein 'value' von NullableSingle.Value: Single
  // -> Lhs.IndexOf('value') matched, ohne Scope-Awareness flaggt er. Mit
  // dieser Liste wird 'nil' rausgefiltert bevor das Finding generiert wird.
  NEVER_FLOAT_TOKENS : array[0..2] of string =
    ('nil', 'true', 'false');

  // Real-World-FP-Audit 2026-07-10: bekannte NICHT-Float-Typen (Ordinal/
  // Integer/Boolean/String/Pointer). Wenn ein Float-benannter Operand zur
  // Nutzung NAECHSTLIEGEND als einer dieser Typen deklariert ist, ist der
  // FloatVars-Namenstreffer scope-blind (Kollision) und der '='/'<>'-Fund
  // ein FP.
  NONFLOAT_ORDINAL_TYPES : array[0..29] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'int8',
    'int16', 'int32', 'uint8', 'uint16', 'uint32', 'dword', 'boolean',
    'bytebool', 'wordbool', 'longbool', 'char', 'ansichar', 'widechar',
    'string', 'ansistring', 'widestring', 'pointer');

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedReDecl  : TRegEx;
  CachedReEqual : TRegEx;
  CachedReInit  : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReDecl  := TRegEx.Create('(?im)\b(\w+)\s*:\s*(Single|Double|Extended|Real|Currency)\b');
  CachedReEqual := TRegEx.Create('(?i)\b(\w+(?:\.\w+)?)\s*(=|<>)\s*([\w.]+)');
  CachedReInit  := True;
end;

function IsFloatType(const TypeText: string): Boolean;
var
  Low : string;
  T   : string;
begin
  Low := LowerCase(Trim(TypeText));
  for T in FLOAT_TYPES do
    if Low = T then Exit(True);
  Result := False;
end;

function IsNeverFloatToken(const TokenLow: string): Boolean;
// TokenLow ist bereits lowercased - direkter Vergleich.
var T : string;
begin
  for T in NEVER_FLOAT_TOKENS do
    if TokenLow = T then Exit(True);
  Result := False;
end;

// Real-World-FP-Audit 2026-07-10: klassifiziert einen aufgeloesten
// Deklarationstyp. Exakter Float-Typ -> False (weiter melden). Bekannter
// Ordinal-/Boolean-/String-/Pointer-Typ ODER Delphi-Namenskonvention T*
// (Klasse/Record) / I* (Interface) / P* (Pointer) -> True (unterdruecken).
// Unbekannt (z.B. Nutzertyp-Alias) -> False, damit kein TP verlorengeht.
function ResolvedTypeIsNonFloat(const TypeName: string): Boolean;
var
  Low, T : string;
begin
  Result := False;
  Low := LowerCase(Trim(TypeName));
  if Low = '' then Exit;
  for T in FLOAT_TYPES do
    if Low = T then Exit(False);
  for T in NONFLOAT_ORDINAL_TYPES do
    if Low = T then Exit(True);
  // Review-Fix 2026-07-11: die T/I/P-Praefix-Heuristik ENTFERNT - sie
  // unterdrueckte auch Float-Aliase wie 'TFloat' (T-Praefix) -> FN auf echter
  // Float-Gleichheit. Nur exakte NONFLOAT_ORDINAL_TYPES gelten jetzt als
  // Nicht-Float; unaufgeloest/sonstiges -> weiter melden (kein TP-Verlust).
end;

// Real-World-FP-Audit 2026-07-10: FloatVars ist ein reiner Namensindex und
// damit scope-blind - eine Kennung die IRGENDWO als Single/Double deklariert
// ist matcht auch dort, wo dieselbe Kennung lokal als Integer/Cardinal/Int32,
// als Klassen-/Interface-Feld (z.B. TdwsJSONValue) oder als Result eines
// Ordinaltyps auftritt. Wir loesen den zur Nutzung NAECHSTLIEGENDEN
// deklarierten Typ auf (Muster 'name[, more]: Typ'; fuer 'Result' den
// Rueckgabetyp der umschliessenden function). Loest er zu einem
// NICHT-Float-Typ auf -> unterdruecken. Nicht aufloesbar oder exakter
// Float-Typ -> weiter melden (kein TP-Verlust / kein FN).
function OperandDeclaredNonFloat(const Code, VarName: string;
  BeforePos: Integer): Boolean;
var
  Before, TypeStr : string;
  RE : TRegEx;
  MC : TMatchCollection;
begin
  Result := False;
  if (VarName = '') or (BeforePos <= 1) or (Pos('.', VarName) > 0) then Exit;
  if not CharInSet(VarName[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  if BeforePos > Length(Code) then BeforePos := Length(Code);
  Before := Copy(Code, 1, BeforePos);   // Deklaration steht VOR der Nutzung
  TypeStr := '';
  // 1) var/param/Feld-Deklaration 'VarName[, weitere]: Typ' - naechstliegende.
  RE := TRegEx.Create('(?i)\b' + VarName +
        '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*([A-Za-z_][A-Za-z0-9_]*)');
  MC := RE.Matches(Before);
  if MC.Count > 0 then
    TypeStr := MC[MC.Count - 1].Groups[1].Value
  else if SameText(VarName, 'result') then
  begin
    // 2) Result -> Rueckgabetyp der naechstliegenden function-Signatur.
    RE := TRegEx.Create(
      '(?i)\bfunction\s+[\w.]+\s*(?:\([^)]*\))?\s*:\s*([A-Za-z_][A-Za-z0-9_]*)');
    MC := RE.Matches(Before);
    if MC.Count > 0 then
      TypeStr := MC[MC.Count - 1].Groups[1].Value;
  end;
  if TypeStr = '' then Exit;   // nicht aufloesbar -> weiter melden (kein FN)
  Result := ResolvedTypeIsNonFloat(TypeStr);
end;

// Real-World-FP-Audit 2026-07-10: liefert True wenn direkt vor der Kennung
// an IdentStart das Keyword 'const' steht. Eine Inline-/Sektions-Konstante
// 'const deltaT = 1/(...)' bindet einen Wert und ist KEIN '='-Vergleich.
function PrecededByConstKeyword(const Code: string; IdentStart: Integer): Boolean;
var
  p, wEnd : Integer;
begin
  Result := False;
  p := IdentStart - 1;
  while (p >= 1) and CharInSet(Code[p], [' ', #9, #10, #13]) do Dec(p);
  if p < 1 then Exit;
  wEnd := p;
  while (p >= 1) and CharInSet(Code[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(p);
  Result := SameText(Copy(Code, p + 1, wEnd - p), 'const');
end;


// Triage 2026-07-24 (Inkrement A1): Name der zur Position naechstliegend
// DAVOR deklarierten Routine (lowercase, letztes Namens-Segment ohne
// Klassen-Qualifier); '' wenn keine. Fuer die Idiom-Gates IsStored/Set*.
function EnclosingRoutineSigLow(const Code: string; BeforePos: Integer;
  out AIsFunction: Boolean): string;
var
  RE : TRegEx;
  MC : TMatchCollection;
  p  : Integer;
begin
  Result := '';
  AIsFunction := False;
  if BeforePos > Length(Code) then BeforePos := Length(Code);
  if BeforePos < 1 then Exit;
  RE := TRegEx.Create('(?i)\b(function|procedure)\s+([\w.]+)');
  MC := RE.Matches(Copy(Code, 1, BeforePos));
  if MC.Count = 0 then Exit;
  Result := LowerCase(MC[MC.Count - 1].Groups[2].Value);
  AIsFunction := SameText(MC[MC.Count - 1].Groups[1].Value, 'function');
  p := LastDelimiter('.', Result);
  if p > 0 then Result := Copy(Result, p + 1, MaxInt);
end;

// G-Sent-2 (Triage 2026-07-25): Literal-0-Erkennung fuer den Sentinel-Zero-
// DEMOTE ('0', '00', '0.0', '0.00' - auch die 0.0-Schreibweise zaehlt).
function IsZeroLiteralToken(const TokLow: string): Boolean;
begin
  Result := (TokLow <> '') and TRegEx.IsMatch(TokLow, '^0+(\.0+)?$');
end;

// G-Sent-2 (Triage 2026-07-25): Sentinel-Zero-DEMOTE. Vergleich '<var> = 0' /
// '<var> <> 0', wobei <var> BEWEISBAR ein LOKALES var der umschliessenden
// Routine ist (Float-Decl im var-Block des Routinen-Kopfs) und SAEMTLICHE
// Zuweisungen an <var> in der Routinen-Spanne DIREKTE einfache Zuweisungen
// sind ('v := 0;', 'v := 1.5;', 'v := beweisbarAnderesLokal;' - KEINE
// Berechnung, kein Call, keine Arithmetik auf der RHS; ein Ident als RHS
// zaehlt nur, wenn er selbst im var-Block des Kopfs deklariert ist, s.u.).
// Sentinel-Semantik: der exakte Vergleich gegen den direkt zugewiesenen
// Wert ist dort korrekt -> Fund NICHT droppen, sondern nur auf fcLow
// demoten (monoton).
// HART konservativ:
//   * NIE fuer Parameter/Felder/Globals (Herkunft nur beim Caller sichtbar) -
//     der Nachweis verlangt die Decl im var-Block des Kopfs; die Parameter-
//     Klammern werden vorher geblankt und zaehlen damit nie als var-Block.
//   * mind. 1 Zuweisung; jede nicht klar klassifizierbare Zuweisung sowie
//     eine Arg-Uebergabe der Var an einen Call ('F(v)', 'F(a, v)' - var/out
//     ist lexikalisch nicht unterscheidbar) oder Adressnahme '@v' -> KEIN
//     Demote.
//   * Block-Tiefen-Check: die Fundstelle muss im noch OFFENEN Body der
//     Routine liegen (Tiefe >= 1) - sonst gehoert sie z.B. zum Outer-Body
//     NACH einer nested routine, deren var-Block nicht der der Fundstelle
//     ist -> KEIN Demote.
// Arbeitet auf dem gestrippten Code (Kommentare/Strings zaehlen NIE).
function SentinelZeroLocalDemote(const Code: string; AtPos: Integer;
  const IdentLow: string): Boolean;
var
  MC         : TMatchCollection;
  Mm         : TMatch;
  i          : Integer;
  SpanStart  : Integer;
  SpanEnd    : Integer;
  RelPos     : Integer;
  BeginPos   : Integer;
  Depth      : Integer;
  BodyOpen   : Boolean;
  ParenDepth : Integer;
  KwLow      : string;
  Routine    : string;
  Header     : string;
  RhsTrim    : string;
  HasAssign  : Boolean;
begin
  Result := False;
  if (IdentLow = '') or (AtPos < 1) or (AtPos > Length(Code)) then Exit;

  // Routinen-Spanne: letzte function/procedure-Signatur VOR der Fundstelle
  // bis zur naechsten Routinen-/Sektions-Grenze danach. initialization/
  // finalization als Grenzen, damit Unit-Level-Code nie in die Spanne faellt;
  // constructor/destructor als Grenzen, damit deren Fundstellen nicht dem
  // var-Block einer davorstehenden Routine zugeschlagen werden.
  MC := TRegEx.Matches(Code,
    '(?i)\b(function|procedure|constructor|destructor|initialization|finalization)\b');
  SpanStart := 0;
  SpanEnd   := Length(Code) + 1;
  KwLow     := '';
  for i := 0 to MC.Count - 1 do
    if MC[i].Index <= AtPos then
    begin
      SpanStart := MC[i].Index;
      KwLow     := LowerCase(MC[i].Groups[1].Value);
    end
    else
    begin
      SpanEnd := MC[i].Index;
      Break;
    end;
  if (SpanStart = 0) or ((KwLow <> 'function') and (KwLow <> 'procedure')) then Exit;
  Routine := Copy(Code, SpanStart, SpanEnd - SpanStart);
  RelPos  := AtPos - SpanStart + 1;

  // Erstes begin = Ende des Deklarations-Kopfs; Fundstelle muss danach liegen.
  Mm := TRegEx.Match(Routine, '(?i)\bbegin\b');
  if (not Mm.Success) or (Mm.Index >= RelPos) then Exit;
  BeginPos := Mm.Index;

  // Block-Tiefe an der Fundstelle (begin/case/try/asm/record oeffnen, end
  // schliesst). Tiefe 0 = die Routine ist vor der Fundstelle bereits zu Ende
  // (nested-routine-Grenzfall) -> kein sicherer var-Block-Bezug, kein Demote.
  // Scoping-Fix (2026-07-25, analog dwsUtils nearest-decl-wins): faellt die
  // Tiefe nach dem ersten Opener ZWISCHENZEITLICH auf 0 zurueck, ist der Body
  // der Routine, deren Kopf/var-Block unten als Nachweis dient, VOR der
  // Fundstelle bereits GESCHLOSSEN - typisch: die Spanne beginnt an einer
  // nested routine, deren begin/end endet, und die Fundstelle liegt im danach
  // wieder oeffnenden OUTER-Body (Tiefe erneut 1). Der var-Block der nested
  // routine gilt dort NICHT (Shadowing-Fehlattribution: an der Fundstelle
  // kann derselbe Name ein Outer-Param/Feld sein) -> kein Demote.
  // Zaehlung erst AB dem ersten begin: Tokens davor gehoeren zum
  // Deklarations-Kopf (lokale record-Typen etc.); balancierte Paare dort
  // netto 0, unbalancierte (variant-record-'case') verzerrten frueher nur
  // die Tiefe nach oben - beide duerfen den Body-geschlossen-Check nicht
  // ausloesen.
  Depth    := 0;
  BodyOpen := False;
  for Mm in TRegEx.Matches(Routine, '(?i)\b(begin|case|try|asm|record|end)\b') do
  begin
    if Mm.Index >= RelPos then Break;
    if Mm.Index < BeginPos then Continue;   // Deklarations-Kopf: nicht zaehlen
    if SameText(Mm.Groups[1].Value, 'end') then
    begin
      if Depth > 0 then Dec(Depth);
      if BodyOpen and (Depth = 0) then Exit;   // Body vor Fundstelle geschlossen
    end
    else
    begin
      Inc(Depth);
      BodyOpen := True;
    end;
  end;
  if Depth < 1 then Exit;

  // Lokaler var-Block-Nachweis: Kopf = alles vor dem ersten begin; Parameter-
  // Klammern blanken, damit '(var X: Double)' NIE als lokaler var-Block
  // durchgeht (HART: Parameter demoten wir niemals).
  Header := Copy(Routine, 1, BeginPos - 1);
  ParenDepth := 0;
  for i := 1 to Length(Header) do
    case Header[i] of
      '(': begin Inc(ParenDepth); Header[i] := ' '; end;
      ')': begin if ParenDepth > 0 then Dec(ParenDepth); Header[i] := ' '; end;
    else
      if ParenDepth > 0 then Header[i] := ' ';
    end;
  if not TRegEx.IsMatch(Header,
       '(?i)\bvar\b[\s\S]*?(?<![\w.])' + IdentLow +
       '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*(Single|Double|Extended|Real|Currency)\b') then
    Exit;

  // Saemtliche Zuweisungen an die Var in der Spanne muessen DIREKT und
  // einfach sein: numerisches Literal (auch negativ/Exponent) oder ein
  // nackter Ident. Alles andere (Arithmetik, Call, Index, Cast) -> unklar,
  // Exit.
  // Korpus-Fix (jvcl JvgUtils.pas:1516, 2026-07-25): ein nackter Ident als
  // RHS ist textuell NICHT von einem PARAMETERLOSEN Function-Call zu
  // unterscheiden - 'Denominator := DigitsToValue;' ruft die SIBLING-nested
  // 'function DigitsToValue: Single' auf, der Wert ist BERECHNET, und
  // 'Denominator <> 0' als Divisions-Guard ist genau die Kernklasse des
  // Detektors (echter TP, darf nicht demotet werden). Bare-Ident-RHS wird
  // deshalb nur noch akzeptiert, wenn der Ident BEWEISBAR eine lokale
  // Variable DERSELBEN Routine ist: Decl im (geblankten) var-Block des
  // Kopfs. Der Header enthaelt nie nested-var-Bloecke (die Spanne startet
  // an der innersten Routine vor der Fundstelle) und keine Parameter
  // (Klammern geblankt) - Funktionsnamen/Properties/Parameter/Felder sind
  // dort nicht auffindbar -> KEIN Demote. Numerische Literale wie bisher.
  HasAssign := False;
  for Mm in TRegEx.Matches(Routine,
              '(?i)(?<![\w.])' + IdentLow + '\s*:=\s*([^;]*)') do
  begin
    RhsTrim := Trim(Mm.Groups[1].Value);
    if not TRegEx.IsMatch(RhsTrim, '(?i)^-?\d+(\.\d+)?(e[+-]?\d+)?$') then
    begin
      if not TRegEx.IsMatch(RhsTrim, '(?i)^[a-z_]\w*$') then Exit;
      if not TRegEx.IsMatch(Header,
           '(?i)\bvar\b[\s\S]*?(?<![\w.])' + LowerCase(RhsTrim) +
           '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*[A-Za-z_]\w*') then Exit;
    end;
    HasAssign := True;
  end;
  if not HasAssign then Exit;   // nie zugewiesen -> keine Sentinel-Semantik

  // Arg-Uebergabe an Calls (var/out lexikalisch nicht unterscheidbar) oder
  // Adressnahme -> Wert-Herkunft unklar, kein Demote.
  if TRegEx.IsMatch(Routine, '(?i)[(,]\s*' + IdentLow + '\s*[,)]')
     or TRegEx.IsMatch(Routine, '(?i)@\s*' + IdentLow + '\b') then Exit;

  Result := True;
end;

// Typluecken (Triage 2026-07-25, Massnahme 2): Alias-Ketten-Walk, als eigener
// Baustein extrahiert (Scoping-Fix 2026-07-25, unveraenderte Regeln). True nur
// wenn TypeLow beweisbar Variant/OleVariant oder bekannter Nicht-Float-Typ ist
// - ggf. ueber eine in-Unit-Alias-Kette ('TColor32 = type Cardinal;', max.
// 3 Hops; nur zeilen-anfaengige Typ-Decls, damit kein '='-VERGLEICH im Code
// als Decl missdeutet wird). Float-Aliase (TFloat = Double) und alles
// Unaufgeloeste -> False (Fund bleibt, kein TP-Verlust).
function TypeChainProvesOrdinalAliasOrVariant(const Code: string;
  TypeLow: string): Boolean;
var
  Target : string;
  Hop : Integer;
  Mm  : TMatch;
begin
  Result := False;
  for Hop := 1 to 3 do
  begin
    if TypeLow = '' then Exit;
    if IsFloatTypeName(TypeLow) then Exit;   // Float(-Alias) -> Fund bleibt
    if (TypeLow = 'variant') or (TypeLow = 'olevariant') then Exit(True);
    if IsKnownNonFloatTypeName(TypeLow) then Exit(True);
    Mm := TRegEx.Match(Code, '(?im)^[ \t]*(?:type\s+)?' + TypeLow +
          '\s*=\s*(?:type\s+)?([A-Za-z_]\w*)\s*;');
    if not Mm.Success then Exit;             // kein in-Unit-Alias -> Fund bleibt
    Target := LowerCase(Mm.Groups[1].Value);
    if Target = TypeLow then Exit;           // Selbstbezug-Schutz
    TypeLow := Target;
  end;
end;

// Scoping-Fix (Korpus dwsUtils.pas:2776, 2026-07-25): Typtext der NAECHST-
// GELEGENEN Deklarationsstelle des Idents VOR AtPos (lower; '' wenn keine
// auffindbar). Sucht das Param-Listen-/var-Block-/Feld-Muster
// 'ident[, weitere]: Typ'; fuer 'Result' zaehlt auch die naechstliegende
// function-Signatur als Deklarationsstelle (Result ist dort implizit
// deklariert) - es gewinnt die textuell LETZTE Stelle vor der Fundstelle.
// Nearest-decl-wins: nested-Routinen-Signaturen und innere var-Bloecke
// SHADOWEN aeussere Deklarationen; weil die Rueckwaertssuche die LETZTE
// Deklaration nimmt, kann zwischen dem gelieferten Beweis und der Fundstelle
// per Konstruktion keine andere Deklaration desselben Idents mehr liegen.
function NearestDeclTypeLowBefore(const Code, IdentLow: string;
  AtPos: Integer): string;
var
  Before  : string;
  MC      : TMatchCollection;
  BestPos : Integer;
begin
  Result := '';
  if (IdentLow = '') or (AtPos <= 1) then Exit;
  if AtPos > Length(Code) then AtPos := Length(Code);
  Before := Copy(Code, 1, AtPos);   // Deklaration steht VOR der Nutzung
  BestPos := 0;
  MC := TRegEx.Matches(Before, '(?i)\b' + IdentLow +
          '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*([A-Za-z_][A-Za-z0-9_]*)');
  if MC.Count > 0 then
  begin
    BestPos := MC[MC.Count - 1].Index;
    Result  := LowerCase(MC[MC.Count - 1].Groups[1].Value);
  end;
  if SameText(IdentLow, 'result') then
  begin
    // Result ist durch die function-Signatur deklariert; liegt eine Signatur
    // NAEHER an der Fundstelle als eine explizite 'Result: Typ'-Zeile (etwa
    // die Vergiftung durch 'var Result: Double' einer FRUEHEREN Routine),
    // gewinnt die Signatur - nearest-decl-wins auch hier.
    MC := TRegEx.Matches(Before,
      '(?i)\bfunction\s+[\w.]+\s*(?:\([^)]*\))?\s*:\s*([A-Za-z_][A-Za-z0-9_]*)');
    if (MC.Count > 0) and (MC[MC.Count - 1].Index > BestPos) then
      Result := LowerCase(MC[MC.Count - 1].Groups[1].Value);
  end;
end;

// Typluecken (Triage 2026-07-25, Massnahme 2): der Operand loest scope-genau
// zu einem Typnamen auf, der kein Basistyp ist (z.B. 'TColor32'). Ist dieser
// Typ IN DIESER UNIT beweisbar als Ordinal-/String-Alias deklariert
// ('TColor32 = type Cardinal;') oder ist er Variant/OleVariant, dann ist
// '='/'<>' darauf kein IEEE-754-Float-Vergleich -> unterdruecken.
// KONSERVATIV: Float-Aliase (TFloat = Double) und alles Unaufgeloeste
// bleiben Fund (kein TP-Verlust).
//
// Scoping-Fix (Korpus dwsUtils.pas:2776, 2026-07-25): die fruehere Annahme
// "die scope-genaue Decl an der Nutzung ist Variant, also nicht die Float-Var
// selbst" war fuer GESCHACHTELTE Routinen falsch. uParser2 verwirft nested
// routines aus dem AST (nur nkNestedRange bleibt), der TTypeResolver kennt
// deren Params/Locals also NICHT und loeste fuer die nested
// 'function CompareDoubles(const left, right: Double)' die AEUSSERE
// Variant-Deklaration von 'VarCompareSafe(const left, right: Variant)' auf
// -> der ECHTE Double-Vergleich 'left = right' wurde gedroppt (Shadowing
// kann so ueberall Float-TPs maskieren). Deshalb nearest-decl-wins-Gate:
// der Drop ist nur zulaessig, wenn ZUSAETZLICH die textuell naechstgelegene
// Deklaration des Idents VOR der Fundstelle (nested-Signatur / innerer
// var-Block gewinnt per Shadowing) beweisbar Ordinal-Alias/Variant ist.
// Keine Deklaration auffindbar oder Kette nicht beweisbar -> im Zweifel
// KEIN Drop (Fund bleibt). Streng monoton: das Gate kann Drops nur
// verhindern, nie neue erzeugen.
function ResolvesToInUnitOrdinalAliasOrVariant(const Code: string;
  TR: TTypeResolver; const IdentLow: string; LineNo, AtPos: Integer): Boolean;
var
  NearestLow : string;
begin
  Result := False;
  if TR = nil then Exit;
  // 1) Resolver-Pfad wie bisher: der laut AST aufgeloeste Typ muss beweisbar
  //    Ordinal-Alias/Variant sein.
  if not TypeChainProvesOrdinalAliasOrVariant(Code,
       TR.ResolveTypeAt(LowerCase(Trim(IdentLow)), LineNo)) then Exit;
  // 2) Nearest-decl-wins-Gate (Scoping-Fix): auch die naechstgelegene
  //    lexikalische Deklaration muss den Beweis liefern.
  NearestLow := NearestDeclTypeLowBefore(Code, LowerCase(Trim(IdentLow)), AtPos);
  if NearestLow = '' then Exit;
  Result := TypeChainProvesOrdinalAliasOrVariant(Code, NearestLow);
end;

class procedure TFloatEqualityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines     : TStringList;
  Cached    : Boolean;
  Code      : string;
  LineFor   : TArray<Integer>;
  FloatVars : TStringList;
  M         : TMatch;
  Lhs, Op, Rhs : string;
  LhsLow, RhsLow : string;
  IdentName : string;
  LineNo    : Integer;
  F         : TLeakFinding;
  TR        : TTypeResolver;   // Welle 1: scope-genaue Typ-Aufloesung (SCA144-Opt-in)
begin
  EnsureRegexCacheBuilt;
  TR := nil;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName);

    // Phase 1: Float-Variablen sammeln. Single-Ident pro Deklaration
    // (Vereinfachung; Komma-Liste `A, B: Double` faengt nur den ersten Ident).
    FloatVars := TStringList.Create;
    try
      FloatVars.CaseSensitive := False;
      FloatVars.Sorted := True;
      FloatVars.Duplicates := dupIgnore;
      for M in CachedReDecl.Matches(Code) do
        if IsFloatType(M.Groups[2].Value) then
          FloatVars.Add(LowerCase(M.Groups[1].Value));
      if FloatVars.Count = 0 then Exit;
      // Welle 1 (Core-Detektoren-Architektur): scope-genauer Typ-Resolver aus dem
      // AST. FloatVars ist ein reiner Namensindex und scope-BLIND - ein Name, der
      // IRGENDWO als Float deklariert ist, matcht auch dort, wo er lokal ein
      // Ordinal/String/anderer Typ ist. Der Resolver loest den Operanden zur
      // Nutzungs-Zeile scope-genau auf und unterdrueckt bei nachgewiesenem
      // Nicht-Float-Skalar (ergaenzt die lexikalische OperandDeclaredNonFloat).
      TR := TTypeResolver.Create(UnitNode);

      // Phase 2: scanne nach `<ident> = <token>` oder `<token> = <ident>`
      // sowie `<>`-Variante. Beide Operanden simple Identifier oder Zahlen.
      for M in CachedReEqual.Matches(Code) do
      begin
        Lhs := M.Groups[1].Value;
        Op  := M.Groups[2].Value;
        Rhs := M.Groups[3].Value;
        // Zuweisungen ausschliessen: ` := ` haette den Op `:=` und nicht `=`.
        // Unser Regex matched nur ` = ` exakt - aber Pascal hat `:=` was
        // mit `=` enden kann. Sicherheit: vorhergehendes Zeichen darf nicht
        // ':' sein.
        if (M.Index > 1) and (Code[M.Index - 1] = ':') then Continue;
        // Mindestens EINE Seite muss eine bekannte Float-Var sein.
        // Nur einfacher Identifier (kein '.') gepruefte Seite, sonst
        // koennte 'Self.X = Other.Y' Field-Lookups treffen die wir nicht
        // aufloesen koennen.
        LhsLow := LowerCase(Lhs);
        RhsLow := LowerCase(Rhs);
        // Qualified Identifier (`Self.X`, `Obj.Field`) ausschliessen - aber
        // NICHT numerische Literale wie `0.5` (haben Punkt + Ziffern).
        if (Pos('.', Lhs) > 0) and not CharInSet(Lhs[1], ['0'..'9']) then Continue;
        if (Pos('.', Rhs) > 0) and not CharInSet(Rhs[1], ['0'..'9']) then Continue;
        // FP-Schutz: 'nil'/'true'/'false' sind nie Float - selbst wenn die
        // andere Seite eine Identifier-Kollision mit einer Float-Var hat
        // (Scope-Blindheit). Beispiel real-world:
        //   if Value = nil   im Pointer-Operator
        // wo FloatVars 'value' aus NullableSingle.Value: Single enthaelt.
        if IsNeverFloatToken(LhsLow) or IsNeverFloatToken(RhsLow) then Continue;
        if (FloatVars.IndexOf(LhsLow) < 0) and (FloatVars.IndexOf(RhsLow) < 0) then
          Continue;
        // Praezisions-Guard (Welle 3, 2026-06-28): ein echter Float-Equality-Bug
        // braucht den ANDEREN Operanden ebenfalls float-kompatibel - numerisches
        // Literal (Ziffer-Start: 0.5, 100, 1e9) ODER selbst eine Float-Var. Ein
        // gewoehnlicher Identifier (Boolean-/String-/Pointer-Feld, das nur
        // NAMENSGLEICH zu einer Float-Var ist = Scope-Blindheit) ist KEIN Float-
        // Vergleich -> FP. Dominante SCA144-FP-Klasse (Real-World: 88% FP, z.B.
        // 'FJavascriptEnabled <> aValue', 'Value <> ShowSeconds'). compare-to-0
        // wird bewusst NICHT geskippt ('a-b = 0' kann echter Bug sein).
        var LhsIsFloat := FloatVars.IndexOf(LhsLow) >= 0;
        var RhsIsFloat := FloatVars.IndexOf(RhsLow) >= 0;
        if not (LhsIsFloat and RhsIsFloat) then
        begin
          var OtherLow : string;
          if LhsIsFloat then OtherLow := RhsLow else OtherLow := LhsLow;
          if (OtherLow <> '') and not CharInSet(OtherLow[1], ['0'..'9'])
             and (FloatVars.IndexOf(OtherLow) < 0) then
            Continue;
        end;
        // Const-Deklaration ist kein Vergleich (Real-World-FP-Audit
        // 2026-07-10): 'const deltaT = 1/(...)' bindet eine Konstante -
        // es gibt hier keinen '='-Operator.
        if PrecededByConstKeyword(Code, M.Index) then Continue;

        // G-Sent-1 (Triage 2026-07-24, Inkrement A1): DFM-IsStored-Idiom.
        // 'function Is<Prop>Stored: Boolean' vergleicht die Property gegen
        // ihren EXAKTEN Literal-Default - das DFM-Streaming vergleicht
        // selbst exakt, der Vergleich ist dort semantisch korrekt und kein
        // IEEE-754-Bug. Gate: umschliessende Routine ist eine function mit
        // Namens-Suffix 'stored' UND eine Seite ist ein numerisches Literal.
        var RoutIsFunc := False;
        var RoutLow := EnclosingRoutineSigLow(Code, M.Index, RoutIsFunc);
        var LhsIsLit := (LhsLow <> '') and CharInSet(LhsLow[1], ['0'..'9']);
        var RhsIsLit := (RhsLow <> '') and CharInSet(RhsLow[1], ['0'..'9']);
        if RoutIsFunc and RoutLow.EndsWith('stored')
           and (LhsIsLit or RhsIsLit) then Continue;

        // Setter-Change-Guard (Triage 2026-07-24, Inkrement A1): das
        // universelle VCL-Idiom 'if FXxx <> Value then ... FXxx := Value'
        // in 'procedure Set*'. Beide Seiten werden nur direkt zugewiesen,
        // der exakte Vergleich ist gewollt (Worst Case: ein redundantes
        // Invalidate). Bedingungen ENG: procedure Set*, eine Seite ist
        // Value/NewValue/AValue, die andere ein F-Feld, und das Feld wird
        // kurz danach zugewiesen (Change-Detection-Beleg).
        if (not RoutIsFunc) and RoutLow.StartsWith('set') then
        begin
          var ParamSide := '';
          var FieldSide := '';
          if (LhsLow = 'value') or (LhsLow = 'newvalue') or (LhsLow = 'avalue') then
          begin
            ParamSide := LhsLow;
            FieldSide := RhsLow;
          end
          else if (RhsLow = 'value') or (RhsLow = 'newvalue') or (RhsLow = 'avalue') then
          begin
            ParamSide := RhsLow;
            FieldSide := LhsLow;
          end;
          if (ParamSide <> '') and (Length(FieldSide) > 1)
             and (FieldSide[1] = 'f') then
          begin
            var Tail := LowerCase(Copy(Code, M.Index, 400));
            if (Pos(FieldSide + ' :=', Tail) > 0)
               or (Pos(FieldSide + ':=', Tail) > 0) then Continue;
          end;
        end;

        // Typ-Aufloesung (Real-World-FP-Audit 2026-07-10): wenn der zum
        // Float-Namen passende Operand zur Nutzung NAECHSTLIEGEND als
        // Nicht-Float-Typ deklariert ist (Integer/Cardinal/Int32-Param,
        // lokales Integer, Klassen-Feld TdwsJSONValue, Ordinal-Result),
        // ist der FloatVars-Treffer scope-blind -> FP unterdruecken.
        LineNo := TDetectorUtils.LineForPos(LineFor, M.Index);
        if LineNo <= 0 then LineNo := 1;
        // Union (Welle 1): lexikalische Regex-Aufloesung ODER scope-genauer
        // AST-Resolver. Der Resolver faengt Scope-Kollisionen, die die Regex-
        // Naechstdeklaration verfehlt; TP-sicher (unbekannter Alias wie
        // TFloat=Double -> ResolvesToKnownNonFloat=False -> keine Unterdrueckung).
        // Auto-Runde 2026-07-19 (Fix A): Operand loest scope-genau zu einem in
        // DIESER Unit deklarierten class/record-Typ auf -> Referenz-/Werttyp-
        // Vergleich, kein IEEE-754-Float (dwsJSON 'FItems^[i].Value = aValue',
        // beide TdwsJSONValue, nur namensgleich zu Double-Params anderswo).
        // Typluecken (Triage 2026-07-25): 4. Disjunkt - Operand loest scope-
        // genau zu einem in-Unit-Ordinal-/String-Alias ('TColor32 = type
        // Cardinal') oder Variant/OleVariant auf -> beweisbar kein Float,
        // reiner FloatVars-Namenskollisions-FP. Unbekannte Typen bleiben Fund.
        if (FloatVars.IndexOf(LhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Lhs, M.Index)
                or TR.ResolvesToKnownNonFloat(LhsLow, LineNo)
                or TR.ResolvesToLocalClassOrRecord(LhsLow, LineNo)
                or ResolvesToInUnitOrdinalAliasOrVariant(Code, TR, LhsLow, LineNo, M.Index)) then Continue;
        if (FloatVars.IndexOf(RhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Rhs, M.Index)
                or TR.ResolvesToKnownNonFloat(RhsLow, LineNo)
                or TR.ResolvesToLocalClassOrRecord(RhsLow, LineNo)
                or ResolvesToInUnitOrdinalAliasOrVariant(Code, TR, RhsLow, LineNo, M.Index)) then Continue;

        // Welche Seite ist die Float-Var (fuer Detail-Text).
        if FloatVars.IndexOf(LhsLow) >= 0 then IdentName := Lhs
                                          else IdentName := Rhs;

        // G-Sent-2 (Triage 2026-07-25): Sentinel-Zero-DEMOTE - '<var> = 0' /
        // '<> 0' auf einem LOKALEN var, das in der Routine ausschliesslich
        // DIREKT einfach zugewiesen wird ('v := 0;'). Exakter Vergleich gegen
        // den direkt zugewiesenen Sentinel ist korrekt -> Fund bleibt, aber
        // Confidence fcLow (monoton, kein Drop). Parameter/Felder/Globals
        // werden NIE demotet (Herkunft nur beim Caller sichtbar).
        var DemoteLow := False;
        var SentVar := '';
        if IsZeroLiteralToken(RhsLow) and (FloatVars.IndexOf(LhsLow) >= 0) then
          SentVar := LhsLow
        else if IsZeroLiteralToken(LhsLow) and (FloatVars.IndexOf(RhsLow) >= 0) then
          SentVar := RhsLow;
        if SentVar <> '' then
          DemoteLow := SentinelZeroLocalDemote(Code, M.Index, SentVar);

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNo);
        F.MissingVar := Format(
          'Float equality (%s %s %s) is unreliable due to IEEE-754 rounding - use SameValue/Math.IsZero',
          [Lhs, Op, Rhs]);
        if DemoteLow then
          F.SetKind(fkFloatEquality, fcLow)   // G-Sent-2: DEMOTE statt Drop
        else
          F.SetKind(fkFloatEquality);
        Results.Add(F);
      end;
    finally
      FloatVars.Free;
    end;
  finally
    TR.Free;   // nil-safe; nil bei FloatVars.Count=0-Exit
    ReleaseLines(Lines, Cached);
  end;
end;

end.
