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
//     (nur der kolon-adjazente Ident; Komma-Listen sind bewusste FN-Klasse,
//     Entscheid 2026-07-25 - Begruendung am Pattern RE_FLOAT_DECL).
//   * Phase 2: scanne nach ` <ident> = <expr> ` oder ` <expr> = <ident> `
//     in if-/while-/until-Kontexten, wo <ident> aus der Float-Var-Liste
//     stammt. Operator-Match auch fuer `<>`.
//   * Zusatz-Gates (ADD-Sampling Welle 1b, 2026-07-25): drei rein
//     suppressive Nachweise - Integer-Wertedomaene, Comparator-Primitiv,
//     Max/Min-Selektions-Identitaet (Details an den Gates). Historisch
//     gegen die ADD-FP-Klassen des Komma-Listen-FN-Close gebaut; der
//     FN-Close selbst wurde zurueckgebaut (Entscheid 2026-07-25), die
//     Gates bleiben und wirken auch auf Einzel-Decl-Vars.
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
  uFileTextCache, uDetectorUtils, uTypeResolver, uRegExMatches;

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

  // ADD-Sampling Welle 1b, 2026-07-25 (Gate 1 - Integer-Wertedomaene):
  // Typen, deren Werte beweisbar GANZZAHLIG sind. Bewusst ENGER als
  // NONFLOAT_ORDINAL_TYPES: Boolean/Char/String/Pointer sind zwar keine
  // Floats, taugen aber nicht als Beweis fuer eine ganzzahlige
  // Wertedomaene in arithmetischen Zuweisungs-RHS.
  PROVABLE_INT_TYPES : array[0..18] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'int8',
    'int16', 'int32', 'uint8', 'uint16', 'uint32', 'dword');

const
  // Thread-Fix (2026-08-19): die frueheren unit-vars (CachedReX + Init-Flag)
  // teilten EINE kompilierte TPerlRegEx-Instanz ueber alle Threads; ein
  // paralleles Match mutierte deren Subject/Offsets. Die Patterns kommen
  // jetzt pro Thread aus TRegExMatches.CachedEx; [roNotEmpty] entspricht
  // exakt dem Default des alten Ein-Arg-TRegEx.Create.
  //
  // Bewusste FN-Klasse (Entscheid 2026-07-25): Komma-Listen-Decls werden
  // NICHT erfasst - Gruppe 1 faengt nur den kolon-adjazenten Ident ('var
  // Best, Seed: Double;' liefert nur 'Seed'). Der FN-Close (Capture der
  // ganzen Ident-Liste + Komma-Split in Phase 1) erzeugte +222 Korpus-Funde
  // mit 0/16 Hart-TP-Sample und 69% Klassik-FP; die Grauzonen-Flutung
  // verschlechterte die Praezision messbar (Kette after88 440 -> after89 662
  // -> after90 654, Gates holten nur -8). Re-Oeffnung nur mit Wertedomaenen-
  // Analyse, die die ADD-Population auf Bestands-TP-Niveau hebt.
  RE_FLOAT_DECL = '(?im)\b(\w+)\s*:\s*(Single|Double|Extended|Real|Currency)\b';
  RE_FLOAT_EQUAL = '(?i)\b(\w+(?:\.\w+)?)\s*(=|<>)\s*([\w.]+)';

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

// ADD-Sampling Welle 1b, 2026-07-25 (Gate 1): TypeLow ist bereits
// lowercased/getrimmt - True nur fuer beweisbar ganzzahlige Basistypen.
function IsProvableIntTypeName(const TypeLow: string): Boolean;
var T : string;
begin
  for T in PROVABLE_INT_TYPES do
    if TypeLow = T then Exit(True);
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

// Bausteine-Extraktion (ADD-Sampling Welle 1b, 2026-07-25): Routinen-Spanne,
// Body-offen-Check und geblankter Deklarations-Kopf stammen UNVERAENDERT aus
// der Sentinel-Haertung (G-Sent-2) und werden jetzt auch von den Zusatz-Gates
// (Integer-Wertedomaene, Comparator-Primitiv, Max/Min-Identitaet) genutzt.
// Liefert True nur, wenn die Fundstelle beweisbar im noch OFFENEN Body einer
// function/procedure liegt; dann sind gefuellt:
//   * Routine       - Spanne von der letzten Routinen-Signatur VOR der
//                     Fundstelle bis zur naechsten Routinen-/Sektions-Grenze
//                     (initialization/finalization/constructor/destructor
//                     als Grenzen, wie bei G-Sent-2 begruendet),
//   * RelPos        - Fundstelle relativ zur Spanne,
//   * BeginPos      - erstes begin (= Ende des Deklarations-Kopfs),
//   * RawHeader     - Kopf INKLUSIVE Parameter-Klammern (fuer lesende
//                     Parameter-Nachweise wie Gate 1),
//   * BlankedHeader - Kopf mit geblankten Parameter-Klammern: Parameter
//                     zaehlen dort NIE als lokaler var-Block (HART: fuer
//                     Parameter wird nie demotet/unterdrueckt).
// Block-Tiefen-Check: die Fundstelle muss im noch OFFENEN Body der Routine
// liegen (Tiefe >= 1); faellt die Tiefe nach dem ersten Opener ZWISCHEN-
// ZEITLICH auf 0 zurueck, ist der Body der Routine, deren Kopf als Nachweis
// dient, VOR der Fundstelle bereits GESCHLOSSEN (nested-routine-Grenzfall,
// Shadowing-Fehlattribution) -> False. Zaehlung erst AB dem ersten begin:
// Tokens davor gehoeren zum Deklarations-Kopf (lokale record-Typen etc.).
function TryRoutineSpanWithOpenBody(const Code: string; AtPos: Integer;
  out Routine: string; out RelPos, BeginPos: Integer;
  out RawHeader, BlankedHeader: string): Boolean;
var
  MC         : TMatchCollection;
  Mm         : TMatch;
  i          : Integer;
  SpanStart  : Integer;
  SpanEnd    : Integer;
  Depth      : Integer;
  BodyOpen   : Boolean;
  ParenDepth : Integer;
  KwLow      : string;
begin
  Result := False;
  Routine := ''; RelPos := 0; BeginPos := 0;
  RawHeader := ''; BlankedHeader := '';
  if (AtPos < 1) or (AtPos > Length(Code)) then Exit;

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
  // schliesst) - Begruendung siehe Funktionskopf-Kommentar.
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

  // Kopf = alles vor dem ersten begin; Parameter-Klammern blanken, damit
  // '(var X: Double)' NIE als lokaler var-Block durchgeht.
  RawHeader     := Copy(Routine, 1, BeginPos - 1);
  BlankedHeader := RawHeader;
  ParenDepth := 0;
  for i := 1 to Length(BlankedHeader) do
    case BlankedHeader[i] of
      '(': begin Inc(ParenDepth); BlankedHeader[i] := ' '; end;
      ')': begin if ParenDepth > 0 then Dec(ParenDepth); BlankedHeader[i] := ' '; end;
    else
      if ParenDepth > 0 then BlankedHeader[i] := ' ';
    end;

  Result := True;
end;

function IsLocalFloatVarInHeader(const Header, IdentLow: string): Boolean;
// SPOT-Extraktion (2026-07-26, Befund des eigenen Self-Scans - SCA021 meldete
// den Block 4x in dieser Unit): der Nachweis "IdentLow ist eine LOKALE
// Float-Variable der umschliessenden Routine" stand wortgleich an drei
// Stellen (G-Sent-2-Demote, Integer-Wertedomaenen-Gate, MaxMin-Identitaets-
// Gate). Ein Regex an einem Ort statt drei - driftet sonst beim naechsten
// Typ-Zusatz auseinander.
//
// Header ist der GEBLANKTE Routinen-Kopf aus TryRoutineSpanWithOpenBody:
// die Parameter-Klammern sind dort ausgeblankt, ein Treffer kann also nur
// aus einem var-Block stammen. Genau darauf beruht die harte Projektregel
// "NIE fuer Parameter" (deren Wert-Herkunft ist nur beim Caller sichtbar).
begin
  Result := TRegEx.IsMatch(Header,
    '(?i)\bvar\b[\s\S]*?(?<![\w.])' + IdentLow +
    '\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:\s*(Single|Double|Extended|Real|Currency)\b');
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
function IstNullWaechter(const Code: string; AtPos: Integer;
  const IdentLow: string): Boolean;
// Erkennt das Waechter-Idiom  "if <v> = 0 then <v> := <etwas>"  -  die
// Variable wird im then-Zweig SOFORT ueberschrieben.
//
// WARUM DAS KEIN BEFUND IST: hier wird nicht auf ein Rechenergebnis
// geprueft, sondern ein Vorgabewert gesetzt, wenn der Aufrufer nichts
// angegeben hat. Null ist in IEEE-754 exakt darstellbar, der Test also
// verlaesslich - und ein Epsilon-Vergleich waere hier sogar FALSCH: er
// wuerde 0.0001 mitfangen und stillschweigend auf den Vorgabewert
// setzen. Beleg aus dem Kundenkorpus SVGIconImageList (29.08.),
// Clipper.Core.pas:842:
//     if sx = 0 then sx := 1;
//     if sy = 0 then sy := 1;
//
// ABGRENZUNG, und sie ist der Grund fuer die enge Form: von 135
// SCA144-Funden dieses Korpus tragen nur 19 dieses Muster. Die uebrigen
// pruefen BERECHNETE Werte  ("if d = 0 then Exit",
// "Result := (cp <> 0.0)" fuer Kollinearitaet)  -  und dort ist die
// Warnung berechtigt, weil Rundung aus einer erwarteten Null eine
// 1e-17 macht. Deshalb greift dieses Gate NUR, wenn dieselbe Variable
// unmittelbar zugewiesen wird.
//
// Ergaenzt SentinelZeroLocalDemote unten: der demotet nur LOKALE
// Variablen und laesst Parameter bewusst aus (Herkunft beim Caller
// unbekannt). Beim Waechter-Idiom spielt die Herkunft keine Rolle - die
// ABSICHT steht in der Zeile selbst.
var
  ZeilenAnfang, ZeilenEnde : Integer;
  Zeile : string;
  Re    : TRegEx;
begin
  Result := False;
  if IdentLow = '' then Exit;
  ZeilenAnfang := AtPos;
  while (ZeilenAnfang > 1) and not CharInSet(Code[ZeilenAnfang - 1], [#10, #13]) do
    Dec(ZeilenAnfang);
  ZeilenEnde := AtPos;
  while (ZeilenEnde <= Length(Code)) and not CharInSet(Code[ZeilenEnde], [#10, #13]) do
    Inc(ZeilenEnde);
  Zeile := LowerCase(Copy(Code, ZeilenAnfang, ZeilenEnde - ZeilenAnfang));
  // Der Rueckverweis \1 erzwingt DIESELBE Variable links und im
  // then-Zweig - ohne ihn faengt das Muster jede Zuweisung.
  Re := TRegEx.Create('\bif\s+(' + TRegEx.Escape(IdentLow) + ')\s*(=|<>)\s*0(\.0+)?\s*then\s+\1\s*:=');
  Result := Re.IsMatch(Zeile);
end;

function SentinelZeroLocalDemote(const Code: string; AtPos: Integer;
  const IdentLow: string): Boolean;
var
  Mm        : TMatch;
  RelPos    : Integer;
  BeginPos  : Integer;
  Routine   : string;
  RawHeader : string;
  Header    : string;
  RhsTrim   : string;
  HasAssign : Boolean;
begin
  Result := False;
  if IdentLow = '' then Exit;

  // Routinen-Spanne + Body-offen-Check + geblankter Kopf: seit dem
  // ADD-Sampling Welle 1b (2026-07-25) nach TryRoutineSpanWithOpenBody
  // extrahiert (Verhalten UNVERAENDERT), damit die Zusatz-Gates dieselben
  // konservativen Nachweise nutzen.
  if not TryRoutineSpanWithOpenBody(Code, AtPos, Routine, RelPos, BeginPos,
       RawHeader, Header) then Exit;

  // Lokaler var-Block-Nachweis im geblankten Kopf (HART: Parameter demoten
  // wir niemals - die Parameter-Klammern sind geblankt).
  if not IsLocalFloatVarInHeader(Header, IdentLow) then Exit;

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

// =========================================================================
// ADD-Sampling Welle 1b, 2026-07-25: Zusatz-Gates fuer den Komma-Listen-
// FN-Close (+222 ADDs). Alle Gates sind REIN SUPPRESSIV bzw. demotierend
// (monoton relativ zur ADD-Population): sie koennen Funde nur unterdruecken,
// nie erzeugen.
// ABGELEHNT (bewusst NICHT gebaut): Parameter-Sentinel-Demote - kollidiert
// mit der harten Projektregel G-Sent-2 'NIE fuer Parameter' (die Wert-
// Herkunft eines Parameters ist ausschliesslich beim Caller sichtbar,
// lokal ist nichts beweisbar).
// =========================================================================

// Gate-1-Baustein (ADD-Sampling Welle 1b, 2026-07-25): ersetzt jeden
// erlaubten ordinal-wertigen Call (Trunc/Round/Ord/Length/High/Low - der
// Rueckgabetyp ist unabhaengig von den Argumenten ganzzahlig; High/Low auf
// Float-Typen waeren kein gueltiger Float-Zuweisungs-Code) samt balancierter
// Argument-Klammern durch das Integer-Literal '0'. False bei unbalancierten
// Klammern (unklar -> der Aufrufer darf dann NICHT unterdruecken).
function BlankAllowedIntCalls(var Work: string): Boolean;
var
  Mm : TMatch;
  OpenPos, Depth, i : Integer;
begin
  Result := False;
  repeat
    Mm := TRegEx.Match(Work, '(?i)\b(trunc|round|ord|length|high|low)\s*\(');
    if not Mm.Success then Break;
    OpenPos := Mm.Index + Mm.Length - 1;   // Position der oeffnenden '('
    Depth := 0;
    i := OpenPos;
    while i <= Length(Work) do
    begin
      case Work[i] of
        '(': Inc(Depth);
        ')': begin
               Dec(Depth);
               if Depth = 0 then Break;
             end;
      end;
      Inc(i);
    end;
    if (i > Length(Work)) or (Depth <> 0) then Exit;   // unbalanciert
    Work := Copy(Work, 1, Mm.Index - 1) + '0' + Copy(Work, i + 1, MaxInt);
  until False;
  Result := True;
end;

// Gate-1-Baustein (ADD-Sampling Welle 1b, 2026-07-25): prueft, ob die RHS
// einer Zuweisung NUR aus beweisbar integer-wertigen Bestandteilen besteht:
// Integer-Literale, Idents aus AIntIdents (Integer-deklarierte Locals/Params
// der Routine), Operatoren +, -, *, div, mod sowie Gruppierungs-Klammern.
// '/' (ergibt in Pascal IMMER Float), Float-Literale, Feld-Zugriffe ('.'),
// Indexierung ('['), Adressnahme ('@') und alle nicht geblankten Calls ->
// nicht beweisbar, False.
function RhsIsProvablyIntegerValued(const Rhs: string;
  AIntIdents: TStringList): Boolean;
var
  Work   : string;
  Mm     : TMatch;
  TokLow : string;
  i      : Integer;
begin
  Result := False;
  Work := Trim(Rhs);
  if Work = '' then Exit;
  if not BlankAllowedIntCalls(Work) then Exit;
  // Nach dem Blanken ist JEDER verbliebene Call ('ident(') unbekannt.
  if TRegEx.IsMatch(Work, '(?i)[a-z_]\w*\s*\(') then Exit;
  // Zeichen-Whitelist: alles ausserhalb (insbesondere '.', '/', '@', '[',
  // ',', String-Reste) ist kein beweisbar ganzzahliger Ausdruck.
  for i := 1 to Length(Work) do
    if not CharInSet(Work[i], ['A'..'Z', 'a'..'z', '0'..'9', '_',
                               '+', '-', '*', '(', ')',
                               ' ', #9, #10, #13]) then Exit;
  // Token-Pruefung: reine Ziffernfolgen sind Integer-Literale ('.'/','
  // sind durch die Whitelist raus, '5e3' zerfaellt in '5' + Ident 'e3' und
  // faellt unten durch); Woerter muessen div/mod oder beweisbare
  // Integer-Idents sein.
  for Mm in TRegEx.Matches(Work, '[A-Za-z_]\w*|\d+') do
  begin
    TokLow := LowerCase(Mm.Value);
    if CharInSet(TokLow[1], ['0'..'9']) then Continue;
    if (TokLow = 'div') or (TokLow = 'mod') then Continue;
    if AIntIdents.IndexOf(TokLow) < 0 then Exit;
  end;
  Result := True;
end;

// GATE 1 (ADD-Sampling Welle 1b, 2026-07-25): Integer-Wertedomaene
// (~44% der gesampelten ADDs, JvDrawImage-Klasse). Eine LOKALE Float-Var,
// deren SAEMTLICHE Zuweisungen in der Routine rechts nur aus beweisbar
// integer-wertigen Operanden bestehen ('dx := X - Y' mit X, Y: Integer),
// traegt zur Vergleichszeit einen exakt darstellbaren Ganzzahlwert -
// '='/'<>' darauf ist zuverlaessig, kein IEEE-754-Rundungsrisiko ->
// Suppress (kein Demote noetig, der Vergleich ist dort korrekt).
// HART konservativ (lieber weniger Drops als ein maskierter TP):
//   * Nachweis 'lokale Var' wie bei G-Sent-2 ueber den geblankten Kopf -
//     Parameter/Felder/Globals unterdrueckt dieses Gate NIE.
//   * Feld-Zugriffe sind NICHT beweisbar: 'dx := X - myorigin.X' hat einen
//     '.' in der RHS -> kein Suppress, der Fund bleibt (Record-/Objekt-
//     Feldtypen sind lexikalisch nicht nachweisbar - das Feld koennte
//     selbst Single sein).
//   * beweisbar integer-wertig sind NUR Integer-deklarierte Locals/Params
//     DIESER Routine (PROVABLE_INT_TYPES, Scan im UNgeblankten Kopf -
//     lesender Parameter-Zugriff ist hier ausdruecklich ok), Integer-
//     Literale, +, -, *, div, mod und Trunc/Round/Ord/Length/High/Low.
//   * jede unklare Zuweisung, Var-Arg-Uebergabe ('F(v)'), Adressnahme
//     ('@v') oder ein with-Block in der Routine (Feld-Shadowing der
//     Ident-Aufloesung) -> kein Suppress.
//   * mind. 1 Zuweisung noetig - 0 Zuweisungen waeren nur vakuum-wahr
//     (eine uninitialisierte Var traegt beliebige Bits).
function IntegerValueDomainSuppress(const Code: string; AtPos: Integer;
  const IdentLow: string): Boolean;
var
  Routine, RawHeader, Header : string;
  RelPos, BeginPos : Integer;
  IntIdents : TStringList;
  Mm : TMatch;
  HasAssign : Boolean;
begin
  Result := False;
  if IdentLow = '' then Exit;
  if not TryRoutineSpanWithOpenBody(Code, AtPos, Routine, RelPos, BeginPos,
       RawHeader, Header) then Exit;

  // Lokaler var-Block-Nachweis (geblankter Kopf, wie G-Sent-2).
  if not IsLocalFloatVarInHeader(Header, IdentLow) then Exit;

  // with-Block: Feld-Aufloesung kann Kopf-Idents shadowen ('with myorigin
  // do dx := X' liest das FELD X, nicht den Integer-Param X) -> unklar.
  if TRegEx.IsMatch(Routine, '(?i)\bwith\b') then Exit;

  // Var-Arg-Uebergabe/Adressnahme -> Wert-Herkunft unklar (wie G-Sent-2).
  if TRegEx.IsMatch(Routine, '(?i)[(,]\s*' + IdentLow + '\s*[,)]')
     or TRegEx.IsMatch(Routine, '(?i)@\s*' + IdentLow + '\b') then Exit;

  IntIdents := TStringList.Create;
  try
    IntIdents.CaseSensitive := False;
    IntIdents.Sorted := True;
    IntIdents.Duplicates := dupIgnore;
    // Integer-deklarierte Locals/Params: 'ident[, weitere]: IntTyp' im
    // UNgeblankten Kopf (Parameter-Klammern inklusive - Parameter werden
    // hier nur LESEND als Beweis genutzt, nie unterdrueckt).
    for Mm in TRegEx.Matches(RawHeader,
        '(?i)\b([a-z_]\w*(?:\s*,\s*[a-z_]\w*)*)\s*:\s*([a-z_]\w*)') do
      if IsProvableIntTypeName(LowerCase(Mm.Groups[2].Value)) then
        for var IdentPart in Mm.Groups[1].Value.Split([',']) do
        begin
          var NmLow := LowerCase(Trim(IdentPart));
          if (NmLow <> '') and CharInSet(NmLow[1], ['a'..'z', '_']) then
            IntIdents.Add(NmLow);
        end;

    HasAssign := False;
    for Mm in TRegEx.Matches(Routine,
                '(?i)(?<![\w.])' + IdentLow + '\s*:=\s*([^;]*)') do
    begin
      if not RhsIsProvablyIntegerValued(Mm.Groups[1].Value, IntIdents) then Exit;
      HasAssign := True;
    end;
    Result := HasAssign;
  finally
    IntIdents.Free;
  end;
end;

// GATE 2a (ADD-Sampling Welle 1b, 2026-07-25): Comparator-Primitiv
// (JclAlgorithms-Klasse). Der Aufrufer hat bereits geprueft, dass die
// umschliessende Routine eine function mit Compare/Same/Equal im Namen ist;
// hier wird der BODY-Nachweis gefuehrt: der '='/'<>'-Vergleich ist die RHS
// einer 'Result :='-Zuweisung und der Body ist im Kern genau dieses
// Primitiv (1-2 Statements). Gleichheit ist dann die SEMANTIK der Funktion
// (bewusster Vertrag) - kein versehentlicher IEEE-754-Bug -> Suppress.
// Der 'Result :='-Anker ist load-bearing: 'if a = b then ...' in Compare*-
// Funktionen bleibt Fund (Bestandstest
// NestedDoubleShadowsVariantParam_StillReported).
// Review-Fix Gate 2a, 2026-07-25: ein Toleranz-Parameter in der
// Parameterliste (Epsilon/Tol/Delta/Prec...) widerlegt den bewussten
// Exakt-Vergleichs-Vertrag - kaputte SameValue-Nachbauten bleiben Fund.
function ComparatorPrimitiveBody(const Code: string; AtPos: Integer): Boolean;
var
  Routine, RawHeader, Header, Body, ParamList : string;
  RelPos, BeginPos, StartAt, i, Semis, ParenDepth : Integer;
begin
  Result := False;
  if not TryRoutineSpanWithOpenBody(Code, AtPos, Routine, RelPos, BeginPos,
       RawHeader, Header) then Exit;
  // Review-Fix Gate 2a, 2026-07-25: traegt die PARAMETERLISTE einen
  // Toleranz-Parameter (eps*/epsilon/tol*/tolerance/delta/prec* als ganzes
  // Wort), dann WOLLTE der Autor beweisbar toleranten Vergleich - ein Body
  // 'Result := A = B', der diesen Parameter IGNORIERT, ist ein kaputter
  // SameValue-Nachbau (Kernbeute des Detektors) -> KEIN Suppress.
  // Nur der Klammer-Inhalt des Kopfs zaehlt (Parameterliste), damit lokale
  // Deklarationen im var-Block das Gate nicht faelschlich blockieren.
  ParamList  := '';
  ParenDepth := 0;
  for i := 1 to Length(RawHeader) do
    case RawHeader[i] of
      '(': Inc(ParenDepth);
      ')': if ParenDepth > 0 then Dec(ParenDepth);
    else
      if ParenDepth > 0 then ParamList := ParamList + RawHeader[i];
    end;
  if TRegEx.IsMatch(ParamList,
       '(?i)\b(eps\w*|epsilon|tol\w*|tolerance|delta|prec\w*)\b') then Exit;
  // Der Vergleich muss unmittelbar die RHS von 'Result :=' sein
  // (Fenster-Scan rueckwaerts, 64 Zeichen reichen fuer 'Result :=').
  StartAt := AtPos - 64;
  if StartAt < 1 then StartAt := 1;
  if not TRegEx.IsMatch(Copy(Code, StartAt, AtPos - StartAt),
       '(?i)\bresult\s*:=\s*$') then Exit;
  // Kern-Body-Nachweis ueber Statement-Zaehlung ab dem ersten begin:
  // 'Result := A = B; end;' hat 2 Semikolons, EIN weiteres Statement
  // (Guard o.ae.) noch 3 - mehr ist kein Primitiv mehr.
  Body := Copy(Routine, BeginPos, MaxInt);
  Semis := 0;
  for i := 1 to Length(Body) do
    if Body[i] = ';' then Inc(Semis);
  Result := Semis <= 3;
end;

// Gate-2b-Baustein (ADD-Sampling Welle 1b, 2026-07-25): Expr ist ein REINER
// Max(...)/Min(...)-Call (optional Math.-qualifiziert), dessen zugehoerige
// schliessende Klammer das LETZTE Zeichen ist - balanciert gezaehlt, damit
// 'Max(a, b) - Min(c, d)' oder 'Max(a, b) * 0.5' durchfallen (das waere
// wieder Arithmetik, keine Selektion). Args erhaelt die unzerlegte Argliste.
function IsPureMaxMinCall(const Expr: string; out Args: string): Boolean;
var
  Mm : TMatch;
  OpenPos, ClosePos, D, i : Integer;
  Work : string;
begin
  Result := False;
  Args := '';
  Work := Trim(Expr);
  Mm := TRegEx.Match(Work, '(?i)^(?:math\s*\.\s*)?(?:max|min)\s*\(');
  if not Mm.Success then Exit;
  OpenPos := Mm.Length;   // '^'-verankert: die '(' ist das letzte Match-Zeichen
  D := 0;
  ClosePos := 0;
  for i := OpenPos to Length(Work) do
    case Work[i] of
      '(': Inc(D);
      ')': begin
             Dec(D);
             if D = 0 then begin ClosePos := i; Break; end;
           end;
    end;
  if (ClosePos = 0) or (ClosePos <> Length(Work)) then Exit;
  Args := Copy(Work, OpenPos + 1, ClosePos - OpenPos - 1);
  Result := True;
end;

// Gate-2b-Baustein: enthaelt die Max/Min-Argliste den Operanden als NACKTES
// Top-Level-Argument - direkt oder in geschachtelten Max/Min-Calls
// ('Max(r, Max(g, b))', max. 3 Ebenen)? Bewusst KEIN Substring-Match:
// 'Max(r + 1, g)' enthaelt 'r' nur als Teilausdruck, die Selektions-
// Identitaet 'cmax = r' gilt dort NICHT (cmax truege r+1, nicht r).
function MaxMinArgsContainBareIdent(const Args, OtherLow: string;
  ADepth: Integer): Boolean;
var
  Parts    : TStringList;
  Part     : string;
  SubArgs  : string;
  D, i, StartIdx : Integer;
begin
  Result := False;
  if ADepth <= 0 then Exit;
  Parts := TStringList.Create;
  try
    // Top-Level-Komma-Split (Klammer-Tiefe zaehlen).
    D := 0;
    StartIdx := 1;
    for i := 1 to Length(Args) do
      case Args[i] of
        '(': Inc(D);
        ')': Dec(D);
        ',': if D = 0 then
             begin
               Parts.Add(Copy(Args, StartIdx, i - StartIdx));
               StartIdx := i + 1;
             end;
      end;
    Parts.Add(Copy(Args, StartIdx, MaxInt));
    for Part in Parts do
    begin
      if SameText(Trim(Part), OtherLow) then Exit(True);
      if IsPureMaxMinCall(Part, SubArgs)
         and MaxMinArgsContainBareIdent(SubArgs, OtherLow, ADepth - 1) then
        Exit(True);
    end;
  finally
    Parts.Free;
  end;
end;

// GATE 2b (ADD-Sampling Welle 1b, 2026-07-25): Max/Min-Selektions-
// Identitaet (HSL/HSV-Klasse, 'cmax = r'). Max/Min SELEKTIEREN eines ihrer
// Argumente bit-identisch (keine Arithmetik, kein Runden). Sind SAEMTLICHE
// Zuweisungen des Operanden reine Max/Min-Calls, deren Argliste den ANDEREN
// Operanden als nacktes Argument enthaelt, fragt '<var> = <other>' exakt
// 'wurde <other> selektiert?' - das ist zuverlaessig -> Suppress.
// HART konservativ (wie Gate 1): lokaler var-Block-Nachweis (Parameter/
// Felder nie), keine Var-Arg-Uebergabe/Adressnahme (damit faellt auch
// inkrementelles 'cmax := Max(cmax, g)' bewusst durch - cmax steht dort
// selbst in einer Argliste), kein with-Block, mind. 1 Zuweisung. Der andere
// Operand muss ein nackter Ident sein (kein Literal, kein Feld-Zugriff).
function MaxMinIdentitySuppress(const Code: string; AtPos: Integer;
  const IdentLow, OtherLow: string): Boolean;
var
  Routine, RawHeader, Header, Args : string;
  RelPos, BeginPos : Integer;
  Mm : TMatch;
  HasAssign : Boolean;
begin
  Result := False;
  if (IdentLow = '') or (OtherLow = '') then Exit;
  // Nackter Ident: kein Literal, kein qualifizierter Zugriff.
  if not CharInSet(OtherLow[1], ['a'..'z', '_']) then Exit;
  if Pos('.', OtherLow) > 0 then Exit;
  if not TryRoutineSpanWithOpenBody(Code, AtPos, Routine, RelPos, BeginPos,
       RawHeader, Header) then Exit;
  if not IsLocalFloatVarInHeader(Header, IdentLow) then Exit;
  if TRegEx.IsMatch(Routine, '(?i)\bwith\b') then Exit;
  if TRegEx.IsMatch(Routine, '(?i)[(,]\s*' + IdentLow + '\s*[,)]')
     or TRegEx.IsMatch(Routine, '(?i)@\s*' + IdentLow + '\b') then Exit;
  HasAssign := False;
  for Mm in TRegEx.Matches(Routine,
              '(?i)(?<![\w.])' + IdentLow + '\s*:=\s*([^;]*)') do
  begin
    if not IsPureMaxMinCall(Mm.Groups[1].Value, Args) then Exit;
    if not MaxMinArgsContainBareIdent(Args, OtherLow, 3) then Exit;
    HasAssign := True;
  end;
  if not HasAssign then Exit;
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

// Nearest-decl-Gate (Welle 1, 2026-07-25): True wenn TypeLow beweisbar ein
// FLOAT-Typ ist - direkt (IsFloatTypeName) oder ueber eine in-Unit-Alias-
// Kette ('TFloat = type Double', max. 3 Hops; gleiche zeilen-anfaengige
// Decl-Regex wie TypeChainProvesOrdinalAliasOrVariant). Unaufgeloest ->
// False (das Gate soll nur BEWEISBARE Floats vor dem Drop schuetzen).
function TypeChainResolvesToFloat(const Code: string; TypeLow: string): Boolean;
var
  Target : string;
  Hop : Integer;
  Mm  : TMatch;
begin
  Result := False;
  for Hop := 1 to 3 do
  begin
    if TypeLow = '' then Exit;
    if IsFloatTypeName(TypeLow) then Exit(True);
    Mm := TRegEx.Match(Code, '(?im)^[ \t]*(?:type\s+)?' + TypeLow +
          '\s*=\s*(?:type\s+)?([A-Za-z_]\w*)\s*;');
    if not Mm.Success then Exit;             // kein in-Unit-Alias -> kein Beweis
    Target := LowerCase(Mm.Groups[1].Value);
    if Target = TypeLow then Exit;           // Selbstbezug-Schutz
    TypeLow := Target;
  end;
end;

// Nearest-decl-Gate (Welle 1, 2026-07-25): dieselbe nested-Shadowing-
// Blindheit wie beim Variant-Gate (Korpus dwsUtils.pas:2776) trifft auch
// die Resolver-Disjunkte ResolvesToKnownNonFloat/ResolvesToLocalClassOrRecord:
// uParser2 verwirft nested routines aus dem AST (nur nkNestedRange bleibt),
// der TTypeResolver loest fuer deren Params/Locals die AEUSSERE Deklaration
// auf (z.B. einen Integer-Param der Outer-Routine) und droppte damit echte
// Float-TPs der nested Routine. Der Drop wird deshalb BLOCKIERT, wenn die
// textuell naechstgelegene Deklaration des Idents VOR der Fundstelle
// (nested-Signatur/innerer var-Block gewinnt per Shadowing) beweisbar ein
// FLOAT ist - direkt oder als in-Unit-Float-Alias-Kette. Nearest-Decl
// unauffindbar oder nicht-Float -> Resolver-Verdikt gilt weiter (bewusst
// LAXER als das Variant-Gate: die Resolver-Disjunkte tragen Bestandsfaelle
// wie QWord/class-Referenz, deren Nearest-Decl-Typ lexikalisch nicht als
// Nicht-Float beweisbar ist). Das Result-Signatur-Bewusstsein von
// NearestDeclTypeLowBefore sorgt dafuer, dass 'Result' in einer Ordinal-
// function trotz frueherer 'var Result: Double'-Vergiftung weiter
// unterdrueckt wird. Streng: das Gate kann Drops nur verhindern, nie neue
// erzeugen (nur ADDs moeglich, kein Monotonie-Bruch).
function ResolverNonFloatWithNearestDeclGate(const Code: string;
  TR: TTypeResolver; const IdentLow: string; LineNo, AtPos: Integer): Boolean;
var
  Low : string;
begin
  Result := False;
  if TR = nil then Exit;
  Low := LowerCase(Trim(IdentLow));
  if not (TR.ResolvesToKnownNonFloat(Low, LineNo)
          or TR.ResolvesToLocalClassOrRecord(Low, LineNo)) then Exit;
  Result := not TypeChainResolvesToFloat(Code,
    NearestDeclTypeLowBefore(Code, Low, AtPos));
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
  ReDecl    : TRegEx;
  ReEqual   : TRegEx;
begin
  ReDecl  := TRegExMatches.CachedEx(RE_FLOAT_DECL, [roNotEmpty]);
  ReEqual := TRegExMatches.CachedEx(RE_FLOAT_EQUAL, [roNotEmpty]);
  TR := nil;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName);

    // Phase 1: Float-Variablen sammeln. Single-Ident pro Deklaration -
    // eine Komma-Liste `A, B: Double` faengt nur den kolon-adjazenten
    // Ident. Bewusste FN-Klasse (Entscheid 2026-07-25), Begruendung am
    // Decl-Pattern RE_FLOAT_DECL.
    FloatVars := TStringList.Create;
    try
      FloatVars.CaseSensitive := False;
      FloatVars.Sorted := True;
      FloatVars.Duplicates := dupIgnore;
      for M in ReDecl.Matches(Code) do
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
      for M in ReEqual.Matches(Code) do
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
        // Nearest-decl-Gate (Welle 1, 2026-07-25): die Resolver-Disjunkte
        // KnownNonFloat/LocalClassOrRecord laufen jetzt durch dasselbe
        // nearest-decl-wins-Gate wie das Variant-Disjunkt - eine beweisbar
        // Float-typisierte Naechst-Deklaration (nested-Signatur/innerer
        // var-Block) blockiert den Drop (Shadowing maskierte sonst Float-TPs).
        if (FloatVars.IndexOf(LhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Lhs, M.Index)
                or ResolverNonFloatWithNearestDeclGate(Code, TR, LhsLow, LineNo, M.Index)
                or ResolvesToInUnitOrdinalAliasOrVariant(Code, TR, LhsLow, LineNo, M.Index)) then Continue;
        if (FloatVars.IndexOf(RhsLow) >= 0)
           and (OperandDeclaredNonFloat(Code, Rhs, M.Index)
                or ResolverNonFloatWithNearestDeclGate(Code, TR, RhsLow, LineNo, M.Index)
                or ResolvesToInUnitOrdinalAliasOrVariant(Code, TR, RhsLow, LineNo, M.Index)) then Continue;

        // ===============================================================
        // ADD-Sampling Welle 1b, 2026-07-25: Zusatz-Gates fuer den Komma-
        // Listen-FN-Close (+222 ADDs). Alle REIN SUPPRESSIV - monoton
        // relativ zur ADD-Population, koennen nie neue Funde erzeugen.
        // ABGELEHNT und bewusst NICHT gebaut: Parameter-Sentinel-Demote -
        // kollidiert mit der harten Projektregel G-Sent-2 'NIE fuer
        // Parameter' (Wert-Herkunft nur beim Caller sichtbar).
        // ===============================================================

        // GATE 1: Integer-Wertedomaene (~44% der gesampelten ADDs,
        // JvDrawImage-Klasse). BEIDE Seiten muessen exakt-zuverlaessig
        // sein: eine Float-Var-Seite via beweisbarer Integer-Wertedomaene
        // (IntegerValueDomainSuppress), eine Literal-Seite als REINES
        // Integer-Literal (der Praezisions-Guard oben garantiert bereits:
        // jede Seite ist Float-Var oder numerisches Literal). '0.5' o.ae.
        // faellt durch -> kein Suppress.
        if (LhsIsFloat or TRegEx.IsMatch(LhsLow, '^\d+$'))
           and (RhsIsFloat or TRegEx.IsMatch(RhsLow, '^\d+$'))
           and ((not LhsIsFloat) or IntegerValueDomainSuppress(Code, M.Index, LhsLow))
           and ((not RhsIsFloat) or IntegerValueDomainSuppress(Code, M.Index, RhsLow)) then
          Continue;

        // GATE 2a: Comparator-Primitiv (JclAlgorithms-Klasse) - eine
        // function, deren Name Compare/Same/Equal enthaelt und deren Body
        // im Kern 'Result := A = B' ist (1-2 Statements), IMPLEMENTIERT
        // Gleichheit als vertragliche Semantik. Der '='-Vergleich ist dort
        // die bewusste Leistung der Funktion, kein versehentlicher
        // IEEE-754-Bug -> Suppress.
        // Review-Fix Gate 2a, 2026-07-25: Namen mit approx/near/fuzzy sind
        // vom Keyword-Match ausgenommen - solche Funktionen VERSPRECHEN
        // toleranten Vergleich, exaktes '=' dort ist gerade der Bug.
        if RoutIsFunc
           and ((Pos('compare', RoutLow) > 0) or (Pos('same', RoutLow) > 0)
                or (Pos('equal', RoutLow) > 0))
           and (Pos('approx', RoutLow) = 0) and (Pos('near', RoutLow) = 0)
           and (Pos('fuzzy', RoutLow) = 0)
           and ComparatorPrimitiveBody(Code, M.Index) then Continue;

        // GATE 2b: Max/Min-Selektions-Identitaet (HSL/HSV-Klasse,
        // 'cmax = r'): SAEMTLICHE Zuweisungen des einen Operanden sind
        // reine Max(...)/Min(...)-Calls, deren Argliste den ANDEREN
        // Operanden als nacktes Argument enthaelt. Max/Min selektieren
        // bit-identisch (keine Arithmetik) - der Vergleich fragt exakt
        // 'wurde <other> selektiert?' und ist zuverlaessig -> Suppress.
        if (LhsIsFloat and MaxMinIdentitySuppress(Code, M.Index, LhsLow, RhsLow))
           or (RhsIsFloat and MaxMinIdentitySuppress(Code, M.Index, RhsLow, LhsLow)) then
          Continue;

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
          DemoteLow := SentinelZeroLocalDemote(Code, M.Index, SentVar)
                       // Waechter-Idiom: gilt auch fuer Parameter, weil
                       // die Absicht in der Zeile selbst steht.
                       or IstNullWaechter(Code, M.Index, SentVar);

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
