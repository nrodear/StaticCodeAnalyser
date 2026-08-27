unit uLegacyInitializationSection;

// Detektor fuer Legacy-Initialization mit `begin..end.` statt
// `initialization..end.`.
//
// SonarDelphi-Aequivalent: communitydelphi:LegacyInitializationSection.
// Vor Delphi 2 wurde der Unit-Init-Block mit `begin..end.` markiert.
// Seit Delphi 2 ist `initialization..end.` (und optional `finalization`)
// der idiomatische Weg - er erlaubt einen separaten Finalization-Block
// fuer Cleanup beim Unit-Unload.
//
// FP-Paket SCA088, 2026-08-27. Gemessen ueber D:/git-sca-realworld
// (13.419 .pas-Dateien): die alte Erkennung war ein Rueckwaerts-Scan ueber
// ZEILEN, der pro Zeile nur das ERSTE Wort wertete - 168 Funde, davon 153
// falsch. Drei Defekte, drei Gates; die Zahlen sind Drops an den 168:
//
//   GATE A (80 Drops). `program`/`library`/`package`-Hauptbloecke wurden
//     als Unit-Init gemeldet. Dort IST `begin..end.` der Programmrumpf und
//     `initialization` an der Stelle syntaktisch unzulaessig - der Hint war
//     also nicht bloss falsch, sondern unbefolgbar. Der AST hilft nicht:
//     uParser2 unterscheidet unit/program/library nicht. Deshalb das erste
//     CODE-Wort der Datei selbst bestimmen; Praezedenz fuer den
//     First-Word-Keyword-Check ist uRedundantJump.pas:142.
//
//   GATE B+C (73 Drops). Die Erste-Wort-Heuristik zaehlte pro Zeile
//     hoechstens EIN Blockwort. Einzeiler `begin DoIt; end;` lieferten nur
//     das `begin` (Tiefe -1, das `end` fiel unter den Tisch), und
//     `begin`/`end` in mehrzeiligen Blockkommentaren zaehlten als Code.
//     Beides deflationiert die Tiefe, bis irgendein Routinen-`begin` als
//     Unit-Init durchgeht. Ersetzt durch einen Rueckwaerts-TOKEN-Walk ueber
//     den kommentar- UND string-bereinigten Text.
//
//   GATE D (1 Drop, LittleTest43.pas:39). Ein echtes Legacy-Init ist immer
//     das LETZTE Element der Datei. Liegt zwischen Kandidaten-`begin` und
//     `end.` noch ein Routinen-Header, war der Kandidat ein Routinenrumpf.
//
// Ergebnis 168 -> 21. Die 15 Ueberlebenden der alten Menge sind verifizierte
// Legacy-Init-Sektionen (Stichprobe: unzip.pas:4098, uPSC_dll.pas:155,
// synautil.pas:2059, rgconst.pas:76). Dazu kommen 6 echte Funde, die der
// Zeilenscan UEBERSAH und der Token-Walk zurueckholt:
//   * `end .` mit Leerzeichen vor dem Punkt (DCU32/op.pas:2277,
//     DCU32_110/op.pas:2275, x86Dasm.pas:673) - CharAfterFirstWord sah dort
//     das Leerzeichen statt des Punktes und hielt den Unit-Terminator fuer
//     ein gewoehnliches Routinen-`end;`.
//   * `begin` am ZEILENENDE hinter `with .. do` (sha1.pas:882,
//     sha3_512.pas:336) bzw. hinter `else` (sha3.pas:544) - das erste Wort
//     der Zeile war `with`/`else`, das zugehoerige `end;` stand dagegen
//     allein auf seiner Zeile und wurde gezaehlt. Die Tiefe stieg also und
//     kam nie zurueck auf 0.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TLegacyInitializationSectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := TDetectorUtils.IsIdentChar(C);
end;

// GATE A: erstes CODE-Wort der Datei, klein geschrieben ('' wenn keins).
//
// Der Strip hat Kommentare UND `{$..}`-Direktiven schon entfernt, also ist
// das erste Wort im Ergebnistext genau das erste Wort, das der Compiler
// sieht - `unit`, `program`, `library` oder `package`. Ein Blick auf Zeile 1
// taete das NICHT: 11 der 21 Ueberlebenden fangen mit einem mehrzeiligen
// Lizenz-Blockkommentar an (ziptypes.pas mit `{`, ssl_openssl_ver.pas mit
// `{===...`), das Schluesselwort steht dort erst Dutzende Zeilen spaeter.
function FirstCodeWordLower(const Code: string): string;
var
  i, n, s : Integer;
begin
  Result := '';
  n := Length(Code);
  i := 1;
  // Bis zum ersten Buchstaben/Unterstrich vorlaufen - ein Pascal-Bezeichner
  // faengt nie mit einer Ziffer an, und ein Sprung mitten in eine Zahl waere
  // ein anderes erstes Wort als das, was der Compiler liest.
  while (i <= n) and not CharInSet(Code[i], ['A'..'Z', 'a'..'z', '_']) do
    Inc(i);
  if i > n then Exit;
  s := i;
  while (i <= n) and IsIdent(Code[i]) do Inc(i);
  Result := LowerCase(Copy(Code, s, i - s));
end;

// Liefert das Token, das bei oder vor APos endet, klein geschrieben, und
// setzt APos auf das Zeichen davor. AStart = 1-basierte Startposition des
// Tokens. Result = '' wenn keins mehr kommt.
function PrevTokenLower(const Code: string; var APos: Integer;
  out AStart: Integer): string;
var
  s, e : Integer;
begin
  Result := '';
  AStart := 0;
  while (APos >= 1) and not IsIdent(Code[APos]) do Dec(APos);
  if APos < 1 then Exit;
  e := APos;
  s := APos;
  while (s > 1) and IsIdent(Code[s - 1]) do Dec(s);
  APos   := s - 1;
  AStart := s;
  Result := LowerCase(Copy(Code, s, e - s + 1));
end;

// Startpunkt des Rueckwaerts-Walks: das `end` des abschliessenden `end.`
// (0 wenn die Datei keines hat - abgeschnittene Dateien und Include-
// Fragmente bekommen dann gar kein Verdikt).
//
// Die Suche geht ueber TOKEN, nicht ueber Zeilen: `end .` mit Leerzeichen
// vor dem Punkt ist im Korpus real (op.pas:2277, x86Dasm.pas:673) und war
// dem alten CharAfterFirstWord genau ein Zeichen zu frueh.
function FindUnitTerminator(const Code: string): Integer;
var
  p, s, q, n : Integer;
  W          : string;
begin
  Result := 0;
  n := Length(Code);
  p := n;
  while True do
  begin
    W := PrevTokenLower(Code, p, s);
    if W = '' then Exit;
    if W = 'end' then
    begin
      q := s + Length(W);
      while (q <= n) and CharInSet(Code[q], [' ', #9, #10, #13]) do Inc(q);
      if (q <= n) and (Code[q] = '.') then Exit(s);
    end;
  end;
end;

// GATE B+C: Rueckwaerts-TOKEN-Walk ab dem Unit-Terminator.
//   * `end`                                   -> Tiefe +1
//   * `begin`/`case`/`try`/`record`/`asm`     -> Tiefe -1
//   * ein `begin` auf Tiefe 0                 -> Legacy-Init-Kopf
//
// `object` gehoert bewusst NICHT in die Oeffnerliste: `procedure .. of
// object` oeffnet keinen Block, wuerde die Tiefe aber in jedem
// Deklarationsteil deflationieren - und Deflation ist die Richtung, die
// FALSCH meldet. Umgekehrt ist Inflation harmlos: eine `class`/`interface`-
// Deklaration liefert ein `end` ohne Gegenstueck in der Oeffnerliste, der
// Walk findet dann eben keinen Kandidaten mehr.
//
// Abbruch auf Tiefe 0 bei `initialization`/`finalization` (moderne Sektion,
// der Massenfall) sowie bei Routinen- und Sektions-Schluesselwoertern. Der
// zweite Abbruch ist ergebnisneutral gemessen (mit und ohne exakt dieselben
// 21 Fundstellen im Korpus; was er durchlaesst, faengt GATE D), er begrenzt
// aber den Walk: ohne ihn liefe er in JEDER der 13.419 Dateien bis zum
// Dateianfang zurueck, statt am letzten Routinenkopf zu enden.
function FindLegacyInitBegin(const Code: string; ATermPos: Integer;
  out ABeginPos: Integer): Boolean;
var
  p, s, pv : Integer;
  Depth    : Integer;
  W        : string;
begin
  Result    := False;
  ABeginPos := 0;
  Depth     := 0;
  p := ATermPos - 1;
  while True do
  begin
    W := PrevTokenLower(Code, p, s);
    if W = '' then Exit;

    // Qualifizierter Bezeichner (`Rec.Case`) oder escapter (`&begin`) ist
    // kein Keyword - dieselbe Wache wie uRedundantJump.pas:119-122.
    pv := s - 1;
    while (pv >= 1) and CharInSet(Code[pv], [' ', #9, #10, #13]) do Dec(pv);
    if (pv >= 1) and CharInSet(Code[pv], ['.', '&']) then Continue;

    if W = 'end' then
    begin
      Inc(Depth);
      Continue;
    end;

    if (W = 'begin') or (W = 'case') or (W = 'try') or (W = 'record')
       or (W = 'asm') then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
        Continue;
      end;
      // Auf Tiefe 0 ist nur `begin` ein Init-Kopf. Ein `case`/`try`/
      // `record`/`asm` ohne passendes `end` heisst, dass die Bilanz nicht
      // aufgeht - dann lieber kein Verdikt (MONOTONIE: nur unterdruecken).
      if W <> 'begin' then Exit;
      ABeginPos := s;
      Exit(True);
    end;

    if Depth > 0 then Continue;

    if (W = 'initialization') or (W = 'finalization') then Exit;
    if (W = 'procedure') or (W = 'function') or (W = 'constructor')
       or (W = 'destructor') or (W = 'operator')
       or (W = 'implementation') or (W = 'interface')
       or (W = 'unit') then Exit;
  end;
end;

// GATE D: Routinen-Header-Wache. Zwischen Kandidaten-`begin` und `end.`
// darf kein `procedure`/`function`/`constructor`/`destructor`/`operator`
// stehen - ein echtes Legacy-Init ist das letzte Element der Datei.
function HasRoutineHeaderBetween(const Code: string;
  AFrom, ATo: Integer): Boolean;
var
  p, s : Integer;
  W    : string;
begin
  Result := False;
  p := AFrom;
  while p < ATo do
  begin
    if not IsIdent(Code[p]) then
    begin
      Inc(p);
      Continue;
    end;
    s := p;
    while (p < ATo) and IsIdent(Code[p]) do Inc(p);
    W := LowerCase(Copy(Code, s, p - s));
    if (W = 'procedure') or (W = 'function') or (W = 'constructor')
       or (W = 'destructor') or (W = 'operator') then Exit(True);
  end;
end;

class procedure TLegacyInitializationSectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  Term     : Integer;
  BeginPos : Integer;
  LineNo   : Integer;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Default-FillCh '~' bewusst beibehalten: das teilt den Strip-Cache mit
    // den anderen ~16 Ganztext-Strippern desselben Scans, und '~' ist -
    // anders als ein Leerzeichen - kein Whitespace. Ein geblanktes
    // String-Literal kann so beim Rueckwaerts-Blick nicht "durchsichtig"
    // werden und den Punkt eines davorstehenden Ausdrucks freilegen.
    Code := TDetectorUtils.StripStringsAndCommentsCached(Lines, LineFor,
      AContext, FileName);

    if FirstCodeWordLower(Code) <> 'unit' then Exit;         // GATE A
    Term := FindUnitTerminator(Code);
    if Term = 0 then Exit;
    if not FindLegacyInitBegin(Code, Term, BeginPos) then Exit;   // GATE B+C
    if HasRoutineHeaderBetween(Code, BeginPos, Term) then Exit;   // GATE D

    LineNo := TDetectorUtils.LineForPos(LineFor, BeginPos);
    if LineNo <= 0 then Exit;
    Results.Add(TLeakFinding.New(FileName, '', LineNo,
      'Legacy unit-init `begin..end.` - migrate to ' +
      '`initialization..end.` for explicit init/finalization separation.',
      fkLegacyInitializationSection));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
