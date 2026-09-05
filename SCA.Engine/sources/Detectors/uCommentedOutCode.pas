unit uCommentedOutCode;

// Detektor fuer "auskommentierten Code".
//
// SonarDelphi-Aequivalent: communitydelphi:CommentedOutCode. Heuristik:
// ein Kommentar (//- oder Block-) ist verdaechtig, wenn sein Inhalt
// Pascal-syntaktische Marker enthaelt, die typisch fuer Code sind und
// nicht fuer Prosa:
//   * Semikolon am Zeilenende (`...;`)
//   * Zuweisungs-Operator `:=`
//   * `begin`/`end`-Schluesselwoerter als ganzes Wort
//   * `procedure`/`function`-Deklaration
//
// Die Heuristik ist bewusst konservativ (zwei oder mehr Marker pro
// Kommentar) - eine Kommentar-Zeile wie "use FreeAndNil; clearer than
// Free" hat nur ein `;` und ist Prosa, nicht Code. Wenn zusaetzlich `:=`
// oder `end`/`begin` drinsteht, ist es ziemlich sicher Code.
//
// Schweregrad: lsHint - kein Bug, aber tote Wartungsschuld (commented-
// out Code rottet weg, niemand traut sich es zu loeschen).
//
// ---------------------------------------------------------------------
// AUDIT rw20 (2026-08-28, alle 15.863 SCA070-Funde nachgezaehlt)
//
// Gebaut wurde daraus NUR Klasse C - die Laengenschwelle im Adapter-
// Doku-Header (Begruendung an Ort und Stelle in IsAdapterDocHeader).
// A/B-Erwartung: SCA070 15.863 -> 15.708, also 155 Drops, 0 Adds und
// keine verschobene Spalte.
//
// EIN-REPO-GEWINN, und das steht hier bewusst so: 155 Drops sind keine
// 155 unabhaengigen Belege. Alle liegen in EINEM Repo (jvcl) und EINER
// Dateifamilie (JvInterpreter_*), verteilt auf 53 Dateien - das sind
// 13 Unit-Namen in je vier nahezu identischen Kopien desselben
// Quellbaums (jvcl/run, tests/RALib/interpreter/Source,
// tests/archive/jvcl/source, tests/restructured/source) plus einmalig
// JvInterpreter_iMTracer.pas. Rechnet man die Kopien heraus, bleiben
// 40 VERSCHIEDENE Faelle (Paare Kommentarname -> Routinenname, etwa
// 'add' -> 'tstrings_add') auf 20 verschiedenen kurzen Namen; 'add'
// allein stellt 76 der 155. Beide Zahlen gehoeren nebeneinander: die
// Korrektur ist richtig, weil die 4 willkuerlich war, aber wer aus 155
// einen Korpus-Hebel liest, verrechnet sich um den Faktor der Kopien.
//
// Drei weitere gezaehlte Klassen wurden NICHT mitgebaut - aus drei
// VERSCHIEDENEN Gruenden. Wer eine davon aufgreift, muss den fuer sie
// zutreffenden Grund entkraeften, nicht irgendeinen:
//
//   * Klasse A "Prosa, die das Wort function/procedure enthaelt"
//     (792 Funde, korrigiert ~790): WIDERLEGT. Die Groesse stimmt, das
//     tragende Versprechen "0 von 792 sind echte Treffer" nicht.
//     Gegenbefund: mindestens zwei echte Funde sind belegt -
//     JclMetadata.pas:1993, das einzige Signal einer 40 Zeilen langen
//     stillgelegten Region, und Win64SEH.pas:76 -, und die Stichprobe
//     deckte nur 25 % der Klasse ab; die dabei uebersehene Gestalt
//     (Deklaration mit //-Trailer) ist die haeufigste Form
//     auskommentierten Codes ueberhaupt. Dazu zwei Bau-Blocker in der
//     vorgeschlagenen Fassung: Content/Lower/Trimmed sind an der
//     Einbaustelle nicht im Scope, und Trimmed[Length(Trimmed)] ohne
//     Leerstring-Wache ist eine AV bei jedem nackten '//' (3,7 % der
//     Aufrufe).
//
//   * Klasse B "Prosa-Satz ohne Pascal-Syntax" (140 Funde, 508 falls A
//     nie gebaut wird): NICHT widerlegt, nur zurueckgestellt. Die
//     Gegenpruefung fuehrt B unter den BESTANDENEN Klassen: Groesse und
//     FP-Urteil exakt reproduziert, TP-Risiko im Korpus 0, benannt ist
//     allein eine Luecke (Bezeichner-Kopf plus schwaches Keyword).
//     Zurueckgestellt, weil B kein reines Gate ist: es braucht einen
//     Vorfix in diesem File - in FindCommentedOutCode schreibt der
//     //-Zweig Result ohne die (Result = 0)-Wache, die die vier
//     Block-Zweige haben, und ueberschreibt damit eine auf derselben
//     Zeile bereits gefundene Spalte. Und die Groesse haengt an A: 140
//     mit A, 508 ohne, nicht additiv.
//     Die Vorlage ist an einer Stelle uneins, das gehoert hierher: ihr
//     strukturiertes Feld sagt "haelt = False" mit der Begruendung "die
//     Drop-only-Zusage nicht", ihr Tabellenkoerper sagt "haelt = ja"
//     und schraenkt nur die Spalte drop-only ein ("nein - Wache fehlt;
//     korpusweit 0 Adds gemessen"). Beide Lesarten treffen sich darin,
//     dass drop-only strukturell offen ist und empirisch bei 0 Adds
//     liegt. Einen Gegenbefund gegen die KLASSE gibt es in keiner der
//     beiden.
//
//   * Klasse G "Block-Kommentar hinter Code" (40 Funde): WIDERLEGT.
//     Gemessen mindestens 10 echt stillgelegte Statements und 12
//     Grenzfaelle gegen 27 FPs; die verengte Fassung braechte noch 9
//     Drops von 15.863. Schon der Zaehler selbst hat "nicht bauen"
//     empfohlen.
//
// Ein falscher Nichtbau-Grund ist schaedlicher als gar keiner: er haelt
// jemanden davon ab, eine zu Recht liegengebliebene Klasse spaeter
// aufzugreifen.
// ---------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TCommentedOutCodeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, IfElseBegin, LowercaseKeyword, NestedRoutine, RedundantJump, SQLInjection, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// SQLInjection: Fix-Template-Strings ('Results.Add()' o.ae.) via String-Concat
// werden faelschlich als SQL-Concat gematcht - Self-Scan-Artefakt, kein Bug.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdentChar(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Strippt Markdown-Inline-Code-Spans (`code`) aus dem Kommentar-Inhalt.
// Doc-Kommentare zitieren Pascal-Code via Backticks ('`for i := 1 do`')
// als Beispiel, nicht als commented-out Code. Ohne Strip schlaegt der
// Marker-Score in solchen Kommentaren immer den Threshold (`for`, `:=`, ...).
function StripBacktickCodeSpans(const S: string): string;
var
  i, n  : Integer;
  InBT  : Boolean;
  Buf   : TStringBuilder;
begin
  Buf := TStringBuilder.Create;
  try
    InBT := False;
    n := Length(S);
    i := 1;
    while i <= n do
    begin
      if S[i] = '`' then
      begin
        InBT := not InBT;
        Inc(i);
        Continue;
      end;
      if not InBT then Buf.Append(S[i]);
      Inc(i);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

// Wortgrenz-Match (case-insensitive) eines Keywords im (lowercase) Inhalt.
function ContainsWordCI(const Lower, W: string): Boolean;
var k, lenW, lenS : Integer;
begin
  Result := False;
  lenW := Length(W); lenS := Length(Lower);
  if lenW = 0 then Exit;
  k := 1;
  while k <= lenS - lenW + 1 do
  begin
    if Copy(Lower, k, lenW) = W then
      if ((k = 1) or not IsIdentChar(Lower[k - 1])) and
         ((k + lenW > lenS) or not IsIdentChar(Lower[k + lenW])) then
        Exit(True);
    Inc(k);
  end;
end;

// Position des naechsten Vorkommens von W als GANZES Wort ab AVon
// (1-basiert), 0 wenn keines mehr folgt. ContainsWordCI beantwortet nur
// die Ja/Nein-Frage; die Stellungspruefung unten braucht die Stelle.
function WortPosAb(const Lower, W: string; AVon: Integer): Integer;
var k, lenW, lenS : Integer;
begin
  Result := 0;
  lenW := Length(W); lenS := Length(Lower);
  if (lenW = 0) or (AVon < 1) then Exit;
  k := AVon;
  while k <= lenS - lenW + 1 do
  begin
    if (Copy(Lower, k, lenW) = W)
       and ((k = 1) or not IsIdentChar(Lower[k - 1]))
       and ((k + lenW > lenS) or not IsIdentChar(Lower[k + lenW])) then
      Exit(k);
    Inc(k);
  end;
end;

// Erste Position ab AVon, die kein Leerraum ist (Length+1, wenn keine folgt).
function NachLeerraum(const S: string; AVon: Integer): Integer;
begin
  Result := AVon;
  while (Result <= Length(S)) and CharInSet(S[Result], [' ', #9]) do
    Inc(Result);
end;

// Erste Position hinter dem Bezeichner, der bei AVon beginnt - oder AVon
// selbst, wenn dort keiner beginnt. Punkte gehoeren dazu, damit die
// qualifizierte Form 'TFoo.Bar' als ein Name zaehlt.
function NachBezeichner(const S: string; AVon: Integer): Integer;
begin
  Result := AVon;
  if (Result > Length(S))
     or not CharInSet(S[Result], ['a'..'z', 'A'..'Z', '_']) then
    Exit;
  while (Result <= Length(S))
        and (IsIdentChar(S[Result]) or (S[Result] = '.')) do
    Inc(Result);
end;

// True wenn links von AKw ein Deklarationsanfang steht: Inhaltsanfang,
// ';', '{' oder das Wort 'class'. In Prosa steht dort ein Artikel oder
// ein Verb ("the function", "this procedure", "to function").
function LinksIstDeklarationsanfang(const Lower: string; AKw: Integer): Boolean;
var i : Integer;
begin
  i := AKw - 1;
  while (i >= 1) and CharInSet(Lower[i], [' ', #9]) do Dec(i);
  if i < 1 then Exit(True);
  if CharInSet(Lower[i], [';', '{']) then Exit(True);
  // 'class procedure' / 'class function'
  Result := (i >= 5) and (Copy(Lower, i - 4, 5) = 'class')
            and ((i = 5) or not IsIdentChar(Lower[i - 5]));
end;

// True wenn ab AVon ein BENANNTER Kopf folgt: Bezeichner und danach
// '(', ':', ';' oder '=' - also 'Foo(', 'Foo;', 'Foo: Integer', 'Foo ='.
// Englische Prosa scheitert hier am Folgezeichen: auf "function should"
// folgt ein weiteres Wort, kein Signaturzeichen.
function RechtsIstBenannteSignatur(const Lower: string; AVon: Integer): Boolean;
var i, j : Integer;
begin
  i := NachLeerraum(Lower, AVon);
  j := NachBezeichner(Lower, i);
  if j = i then Exit(False);
  j := NachLeerraum(Lower, j);
  Result := (j <= Length(Lower)) and CharInSet(Lower[j], ['(', ':', ';', '=']);
end;

// True wenn ab AVon eine ANONYME Methode folgt: '(' mit erkennbarer
// Parameterliste ('(Sender: TObject', '(const A, B') oder leerer Liste
// mit Ergebnis ('(): Integer').
//
// Die Parameterlisten-Schranke ist nicht Kosmetik: ohne sie faengt die
// Regel englische Prosa, die zufaellig eine Klammer traegt -
// "function(s)", "the function (GetResponse) did its", "reconstruction
// function (q / (2^N-1))". Am Korpus waren das 4 der 9 Faelle, die die
// Stellungspruefung sonst faelschlich als Code durchgelassen haette.
function RechtsIstAnonymeSignatur(const Lower: string; AVon: Integer): Boolean;
var i, j : Integer;
begin
  i := NachLeerraum(Lower, AVon);
  if (i > Length(Lower)) or (Lower[i] <> '(') then Exit(False);
  i := NachLeerraum(Lower, i + 1);
  if (i <= Length(Lower)) and (Lower[i] = ')') then
  begin
    i := NachLeerraum(Lower, i + 1);
    Exit((i <= Length(Lower)) and CharInSet(Lower[i], [':', ';']));
  end;
  j := NachBezeichner(Lower, i);
  if j = i then Exit(False);
  // 'const'/'var'/'out' steht vor dem Parameternamen, nicht statt seiner.
  if MatchStr(Copy(Lower, i, j - i), ['const', 'var', 'out']) then
  begin
    i := NachLeerraum(Lower, j);
    j := NachBezeichner(Lower, i);
    if j = i then Exit(False);
  end;
  j := NachLeerraum(Lower, j);
  Result := (j <= Length(Lower)) and CharInSet(Lower[j], [':', ',']);
end;

// True wenn 'procedure'/'function' im Inhalt eine DEKLARATION eroeffnet,
// statt als englisches Substantiv in Prosa zu stehen.
//
// Ohne diese Unterscheidung ist das blosse Wort ein starker Marker, und
// damit flaggt der Detektor jeden Kommentar, der ueber eine Routine
// SPRICHT: "This function should notify the user", "callback function
// for WinHttpSetStatusCallback", "Function result will be erDeferred".
// Am Referenzkorpus gezaehlt (rw56, alle 15.688 Funde nachgebildet):
// 821 Funde entstehen ALLEIN so - 5,2 %. Die AQL-Stichprobe vom 31.08.
// hat SCA070 mit 15 % zurueckgewiesen, und 18 der 30 geprueften
// Fehlalarme waren genau dieses Muster.
//
// Code erkennt man an der STELLUNG, nicht am Wort:
//   benannt - das Wort eroeffnet den Inhalt oder folgt auf ';'/'{'/
//             'class', und ein Bezeichner samt Signaturzeichen folgt
//   anonym  - 'procedure('/'function(' mit Parameterliste; das steht
//             mitten im Ausdruck ('TProc = procedure (S: TObject)') und
//             darf deshalb KEINEN Deklarationsanfang links verlangen
function KeywordEroeffnetDeklaration(const Lower: string): Boolean;
const
  KWS : array[0..1] of string = ('procedure', 'function');
var
  w, p, q : Integer;
begin
  for w := Low(KWS) to High(KWS) do
  begin
    p := WortPosAb(Lower, KWS[w], 1);
    while p > 0 do
    begin
      q := p + Length(KWS[w]);
      if (LinksIstDeklarationsanfang(Lower, p)
          and RechtsIstBenannteSignatur(Lower, q))
         or RechtsIstAnonymeSignatur(Lower, q) then
        Exit(True);
      p := WortPosAb(Lower, KWS[w], p + 1);
    end;
  end;
  Result := False;
end;

// True wenn der Inhalt einen UNZWEIDEUTIGEN Pascal-Marker traegt, der in
// englischer Prosa praktisch nie vorkommt: ':=', Inhalt endet mit ';', oder
// 'begin' als Wort bzw. 'procedure'/'function' in DEKLARATIONSSTELLUNG
// (das blosse Wort reicht nicht - s. KeywordEroeffnetDeklaration).
// Die schwachen Keywords
// (if/then/for/while/end) sind prosa-haeufig und reichen ALLEIN nicht -
// sonst flaggt z.B. "if the value is nil then return" reine Prosa als Code
// (dominante SCA070-FP-Klasse, Real-World 2026-06-28).
function HasStrongCodeMarker(const Raw: string): Boolean;
var Content, Lower, Trimmed : string;
begin
  Content := StripBacktickCodeSpans(Raw);
  Lower   := LowerCase(Content);
  Trimmed := Trim(Content);
  Result := ((Trimmed <> '') and (Trimmed[Length(Trimmed)] = ';'))
            or (Pos(':=', Content) > 0)
            or ContainsWordCI(Lower, 'begin')
            or KeywordEroeffnetDeklaration(Lower);
end;

// Zaehlt code-typische Marker im Kommentar-Inhalt (starke + schwache).
function ScoreCodeMarkers(const Raw: string): Integer;
var
  Content : string;
  Lower   : string;
  Trimmed : string;
begin
  Result := 0;
  // Backtick-Code-Spans entfernen BEVOR die Marker gezaehlt werden.
  Content := StripBacktickCodeSpans(Raw);
  Lower := LowerCase(Content);
  Trimmed := Trim(Content);
  if (Trimmed <> '') and (Trimmed[Length(Trimmed)] = ';') then Inc(Result);
  if Pos(':=', Content) > 0 then Inc(Result);
  if ContainsWordCI(Lower, 'begin')     then Inc(Result);
  if ContainsWordCI(Lower, 'end')       then Inc(Result);
  if ContainsWordCI(Lower, 'procedure') then Inc(Result);
  if ContainsWordCI(Lower, 'function')  then Inc(Result);
  if ContainsWordCI(Lower, 'if')        then Inc(Result);
  if ContainsWordCI(Lower, 'then')      then Inc(Result);
  if ContainsWordCI(Lower, 'for')       then Inc(Result);
  if ContainsWordCI(Lower, 'while')     then Inc(Result);
end;

// True wenn der Kommentar-Inhalt nach Code aussieht: >=2 Marker UND mind. ein
// STARKER (Pascal-spezifischer) Marker. Der Strong-Zwang killt die dominante
// FP-Klasse (englische Prosa mit if/then/for/while/end). Echter commented-out
// Code hat fast immer ':=', ';' oder begin/procedure/function.
//
// GEMESSEN 2026-09-05 (rw62, Los 14.034 nach Dedup, AQL-Stichprobe
// n=125, Seed 20260905, spaltengefuehrt - die Spalte im Meldetext
// macht den bewerteten Kommentar seit der Stellungs-Charge eindeutig
// lokalisierbar, die aeltere Notiz "Restklasse nicht messbar" war
// damit ueberholt): 124/125 Anspruch bestaetigt = 0,8 % FP (31.08.
// noch 15 %, vor den Stellungs-Fixes). Der EINZIGE Fehlalarm ist die
// vermutete Prosa-Restklasse: ein englischer Prosa-Blockkommentar in
// JvVCLUtils.pas:1719, der die Schluesselwoerter fuer Blockanfang und
// -ende als normale WOERTER des Satzes traegt ("Calculate the
// difference between ... RGB values"). Bewusst PARAPHRASIERT statt
// zitiert: das woertliche Zitat liess diese Regel auf ihre eigene
// Doku feuern (Selbstscan der Charge 6). Hochgerechnet
// bleibt die Klasse unter ~1 % des Loses - ein Prosa-Gate lohnt den
// Eingriff nicht und wuerde an 'begin'/'end'-Zeilen echte Treffer
// gefaehrden. Bewusst NICHT gebaut.
function LooksLikeCommentedCode(const Raw: string): Boolean;
begin
  Result := (ScoreCodeMarkers(Raw) >= 2) and HasStrongCodeMarker(Raw);
end;

// Pro Zeile: extrahiert den //-Kommentar-Inhalt (rest nach `//`) und
// gibt Spalte des `//` zurueck wenn der Inhalt Code-Marker hat, sonst 0.
// Was ein Zweig der Zeilenschleife zurueckmeldet.
//   szFertig - die Zeile ist abgeschlossen (frueher: Exit)
//   szWeiter - der Zweig hat die Leseposition gesetzt, Schleife von vorn
//              (frueher: Continue)
type
  TScanZweig = (szFertig, szWeiter);

  // Die offene '(*'-Region und ob sie mit '(*$' begann. Die beiden Bits
  // werden IMMER gemeinsam gesetzt und gemeinsam zurueckgenommen -
  // getrennt gefuehrt haben sie zwei Zweig-Helfer auf sechs Parameter
  // gebracht (SCA013 im Selbst-Scan vom 02.09.).
  TParenStarLage = record
    Offen        : Boolean;
    IstDirektive : Boolean;
  end;

// --- Die sechs Zweige des Kommentar-Scanners ------------------------
//
// FindCommentedOutCode ist ein Zustandsautomat ueber EINE Zeile, mit
// drei zeilenuebergreifenden Bits. Er lag am 01.09. bei Cognitive 98
// (Grenze 15), und das war keine Grenzverletzung mehr, sondern eine
// Groessenordnung. Die Clean-Code-Kalibrierung laesst State Machines
// begruendet darueber liegen - aber nicht unbegrenzt und nicht ohne
// die Begruendung im Code.
//
// Zerlegt ist er entlang der Faelle, die er ohnehin unterscheidet. Was
// dabei NICHT angetastet wurde: die Zweige setzen den Fund
// uneinheitlich - die Exit-Pfade unbedingt, die Weiter-Pfade nur bei
// noch leerem Fund. In einer Zeile mit MEHREREN Kommentaren
// entscheidet das ueber die gemeldete Spalte. Eine Vereinheitlichung
// waere eine Verhaltensaenderung, kein Refactor, und gehoert deshalb
// nicht hierher.

// Fortsetzungszeile eines offenen '{'-Kommentars.
function ZweigBlockFortsetzung(const ALine: string; ALaenge: Integer;
  var APos: Integer; var AInBlockComm: Boolean; var AFund: Integer): TScanZweig;
var
  pClose : Integer;
  Inhalt : string;
begin
  pClose := PosEx('}', ALine, APos);
  if pClose = 0 then
  begin
    Inhalt := Copy(ALine, APos, ALaenge - APos + 1);
    if LooksLikeCommentedCode(Inhalt) then AFund := APos;
    Exit(szFertig);
  end;
  Inhalt := Copy(ALine, APos, pClose - APos);
  if (AFund = 0) and (LooksLikeCommentedCode(Inhalt)) then AFund := APos;
  AInBlockComm := False;
  APos := pClose + 1;
  Result := szWeiter;
end;

// Fortsetzungszeile eines offenen '(*'-Kommentars.
function ZweigParenStarFortsetzung(const ALine: string; ALaenge: Integer;
  var APos: Integer; var ALage: TParenStarLage;
  var AFund: Integer): TScanZweig;
var
  pClose : Integer;
  Inhalt : string;
begin
  pClose := PosEx('*)', ALine, APos);
  if pClose = 0 then
  begin
    // Fortsetzungszeile einer mehrzeiligen '(*$...*)'-Direktive traegt
    // keinen Kommentar-Inhalt. HIER entstehen die Fehlalarme, nicht im
    // Oeffner-Zweig: Beleg jcl/jcl/source/prototypes/JclHashMaps.pas:100
    // ('function GetOwnsKeys: Boolean;' ist Argument des
    // '(*$JPPEXPANDMACRO' aus Zeile 82) - im rw45-SARIF gemeldet mit
    // Spalte 1, level note.
    if ALage.IstDirektive then Exit(szFertig);
    Inhalt := Copy(ALine, APos, ALaenge - APos + 1);
    if LooksLikeCommentedCode(Inhalt) then AFund := APos;
    Exit(szFertig);
  end;
  if not ALage.IstDirektive then
  begin
    Inhalt := Copy(ALine, APos, pClose - APos);
    if (AFund = 0) and (LooksLikeCommentedCode(Inhalt)) then AFund := APos;
  end;
  ALage.Offen        := False;
  ALage.IstDirektive := False;
  APos := pClose + 2;
  Result := szWeiter;
end;

// Innerhalb eines String-Literals: nur die Leseposition weiterruecken.
// '' ist das verdoppelte Hochkomma und beendet den String NICHT.
procedure ZweigInString(const ALine: string; ALaenge: Integer;
  var APos: Integer; var AInStr: Boolean);
begin
  if ALine[APos] <> '''' then
  begin
    Inc(APos);
    Exit;
  end;
  if (APos < ALaenge) and (ALine[APos + 1] = '''') then
    Inc(APos, 2)
  else
  begin
    AInStr := False;
    Inc(APos);
  end;
end;

// Oeffnendes '{'. '{$...}' sind Compiler-Direktiven, nicht Kommentare -
// Sonder-Skip.
function ZweigBlockOeffner(const ALine: string; ALaenge: Integer;
  var APos: Integer; var AInBlockComm: Boolean; var AFund: Integer): TScanZweig;
var
  pClose : Integer;
  Inhalt : string;
begin
  if (APos + 1 <= ALaenge) and (ALine[APos + 1] = '$') then
  begin
    pClose := PosEx('}', ALine, APos + 2);
    if pClose = 0 then
    begin
      AInBlockComm := True;
      Exit(szFertig);
    end;
    APos := pClose + 1;
    Exit(szWeiter);
  end;
  pClose := PosEx('}', ALine, APos + 1);
  if pClose = 0 then
  begin
    AInBlockComm := True;
    Inhalt := Copy(ALine, APos + 1, ALaenge - APos);
    if LooksLikeCommentedCode(Inhalt) then AFund := APos;
    Exit(szFertig);
  end;
  Inhalt := Copy(ALine, APos + 1, pClose - APos - 1);
  if (AFund = 0) and (LooksLikeCommentedCode(Inhalt)) then AFund := APos;
  APos := pClose + 1;
  Result := szWeiter;
end;

// Oeffnendes '(*'.
//
// '(*$...*)' ist dieselbe Compiler-/Praeprozessor-Direktive wie '{$...}',
// nur in Alternate-Syntax - deshalb hier derselbe Sonder-Skip wie im
// '{'-Zweig. Der Lexer stellt beide Formen laengst gleich
// (uLexer.pas:431 fuer '{$', uLexer.pas:463 fuer '(*$', beide rufen
// HandleConditionalDirective; uLexer.pas:636-639 liefert fuer '(*'
// ueberhaupt keinen Kommentar-Token). Dieser Detektor liest die Quelle
// ueber AcquireLines zeilenweise selbst - nur deshalb hat die Ausnahme
// hier gefehlt. Die MEHRZEILIGEN Vorkommen im Korpus sind durchweg
// JEDI-Praeprozessor-Makros (22x '(*$JPPEXPANDMACRO', 69x '(*$JPPLOOP'),
// deren Rumpf jpp in die erzeugte Unit expandiert: aktiver Meta-Code,
// kein stillgelegter. Die einzeiligen sind ueberwiegend '(*$HPPEMIT'
// (896x) und schon heute stumm.
function ZweigParenStarOeffner(const ALine: string; ALaenge: Integer;
  var APos: Integer; var ALage: TParenStarLage;
  var AFund: Integer): TScanZweig;
var
  pClose : Integer;
  Inhalt : string;
begin
  if (APos + 2 <= ALaenge) and (ALine[APos + 2] = '$') then
  begin
    pClose := PosEx('*)', ALine, APos + 3);
    if pClose = 0 then
    begin
      // Bewusst ZWEI Bits statt einem - hier ist der Fix gruendlicher
      // als der '{'-Zweig, und das ist der Grund: der merkt sich beim
      // Zeilenueberlauf nur "Block offen" und bewertet die
      // Fortsetzungszeilen einer mehrzeiligen Direktive wieder als
      // Kommentar. Genau daran waere ein reiner Oeffner-Skip hier
      // wirkungslos geblieben (am Korpus gemessen: 0 Drops) - die 91
      // MEHRZEILIGEN '(*$'-Regionen sind bis zu 21 Zeilen lang
      // (JclHashMaps.pas:82-103) und liegen zwar alle im Repo jcl, aber
      // in ZWEI Verzeichnissen: 79 in jcl/jcl/source/prototypes/ (13
      // Dateien) und 12 in
      // jcl/donations/dcl/bucket_arrays/JclBucketArraySets.pas (z.B.
      // Region 52-54, dort ohne Fund - Zeile 54 endet auf ')', nicht auf
      // ';'). Der '{'-Zweig bleibt trotzdem unangetastet: dieselbe
      // Luecke ist dort korpusweit genau EINEN Fund wert
      // (JclHashMaps.pas:248 in der Direktive aus Zeile 246) und
      // rechtfertigt den Eingriff in den haeufigsten Pfad des Detektors
      // nicht.
      ALage.Offen        := True;
      ALage.IstDirektive := True;
      Exit(szFertig);
    end;
    APos := pClose + 2;
    Exit(szWeiter);
  end;
  pClose := PosEx('*)', ALine, APos + 2);
  if pClose = 0 then
  begin
    ALage.Offen := True;
    Inhalt := Copy(ALine, APos + 2, ALaenge - APos - 1);
    if LooksLikeCommentedCode(Inhalt) then AFund := APos;
    Exit(szFertig);
  end;
  Inhalt := Copy(ALine, APos + 2, pClose - APos - 2);
  if (AFund = 0) and (LooksLikeCommentedCode(Inhalt)) then AFund := APos;
  APos := pClose + 2;
  Result := szWeiter;
end;

function FindCommentedOutCode(const Line: string; var InBlockComm: Boolean;
  var AParenStar: TParenStarLage): Integer;
// AParenStar.IstDirektive gehoert zu .Offen und sagt, ob die offene
// '(*'-Region mit '(*$' begann. Ohne dieses zweite Bit bliebe der
// '(*$'-Sonder-Skip wirkungslos: von den 1.087 '(*$'-Vorkommen der 13.419
// .pas laufen nur 91 ueber mehrere Zeilen, und NUR die tragen Fehlalarme -
// die einzeiligen (896 davon '(*$HPPEMIT') melden schon heute nichts, ein
// reiner Oeffner-Skip ist am Korpus gemessen ein No-Op. Der Fehlalarm
// entsteht erst auf einer Fortsetzungszeile
// (jcl/jcl/source/prototypes/JclHashMaps.pas:100 zur Direktive aus Zeile 82,
// die erst in Zeile 103 schliesst) - und die liest der
// Fortsetzungs-Zweig, nicht der Oeffner-Zweig.
//
// Der Rumpf ist nur noch die Fallunterscheidung; jeder Fall steht als
// eigener Zweig darueber. Die REIHENFOLGE der Faelle traegt Bedeutung:
// eine offene Kommentarregion schlaegt alles andere, und der
// String-Test kommt vor den Kommentar-Oeffnern, weil '{' und '(*' in
// einem String-Literal keine Kommentare oeffnen.
var
  i, n : Integer;
  InStr: Boolean;
  c    : Char;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      if ZweigBlockFortsetzung(Line, n, i, InBlockComm, Result) = szFertig then Exit;
      Continue;
    end;
    if AParenStar.Offen then
    begin
      if ZweigParenStarFortsetzung(Line, n, i, AParenStar, Result) = szFertig then Exit;
      Continue;
    end;
    if InStr then
    begin
      ZweigInString(Line, n, i, InStr);
      Continue;
    end;
    c := Line[i];
    if c = '''' then
    begin
      InStr := True;
      Inc(i);
      Continue;
    end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then
    begin
      // Ein //-Kommentar laeuft bis Zeilenende - danach ist nichts mehr
      // zu pruefen.
      if LooksLikeCommentedCode(Copy(Line, i + 2, MaxInt)) then Result := i;
      Exit;
    end;
    if c = '{' then
    begin
      if ZweigBlockOeffner(Line, n, i, InBlockComm, Result) = szFertig then Exit;
      Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      if ZweigParenStarOeffner(Line, n, i, AParenStar, Result) = szFertig then Exit;
      Continue;
    end;
    Inc(i);
  end;
end;

function IsPrevLineLineComment(Lines: TStringList; CurIdx: Integer): Boolean;
// True wenn die unmittelbar vorangehende Quelltext-Zeile mit '//' beginnt
// (nach Whitespace-Strip). Indikator fuer Multi-Line-Doc-Block - dort sind
// Pascal-Code-Beispiele typisch ('// Pattern: \n // procedure X; \n ...').
// Single-Line-Comments zwischen echtem Code (= isolierte //-Zeile) bleiben
// flag-faehig - das sind die echten commented-out-Kandidaten.
var
  S : string;
begin
  Result := False;
  if (CurIdx <= 0) or (CurIdx >= Lines.Count) then Exit;
  S := TrimLeft(Lines[CurIdx - 1]);
  Result := (Length(S) >= 2) and (S[1] = '/') and (S[2] = '/');
end;

function IsNextLineLineComment(Lines: TStringList; CurIdx: Integer): Boolean;
// Symmetrisch zu IsPrevLineLineComment: True wenn die naechste Zeile auch
// mit '//' beginnt. Faengt den Doc-Block-Start (erste //-Zeile, Vorzeile
// ist Code, naechste Zeile ist auch //) der von IsPrevLineLineComment nicht
// erkannt wird.
var
  S : string;
begin
  Result := False;
  if (CurIdx < 0) or (CurIdx >= Lines.Count - 1) then Exit;
  S := TrimLeft(Lines[CurIdx + 1]);
  Result := (Length(S) >= 2) and (S[1] = '/') and (S[2] = '/');
end;

function IsInlineComment(const Line: string; CommentCol: Integer): Boolean;
// True wenn vor CommentCol non-whitespace steht (Inline-Kommentar nach
// Code-Statement, z.B. 'fkXxx,  // Pascal-Keyword nicht...'). In Praxis
// fast immer Doku-Hint, nicht auskommentierter Code.
var
  i : Integer;
begin
  Result := False;
  if CommentCol <= 1 then Exit;
  for i := 1 to CommentCol - 1 do
    if not CharInSet(Line[i], [' ', #9]) then Exit(True);
end;

// ===========================================================================
// ADAPTER-DOKU-HEADER (30%-Real-World-Audit 2026-07-31, dominante FP-Klasse
// mit 8 von 24 Stichproben).
//
// Das JvInterpreter-Idiom dokumentiert die ORIGINAL-Signatur ueber dem
// Adapter, der sie fuer den Interpreter umschliesst:
//
//   { procedure Save; }
//   procedure TRegAuto_Save(var Value: Variant; Args: TJvInterpreterArgs);
//
// Der Kommentar enthaelt 'procedure' und endet auf ';' - zwei starke
// Marker, also ein Fund. Er ist aber Dokumentation, kein stillgelegter Code.
//
// DREI BEDINGUNGEN, alle noetig. Jede einzeln weggelassen kostet echte
// Funde - am Korpus (after126, 20.354 Funde) durchgemessen:
//   * NUR ein Routinenkopf im Kommentar (kein ':=', kein begin/end).
//     Ohne diese Bedingung faellt der KOPF eines mehrzeilig
//     auskommentierten Blocks mit weg - dessen erste Zeile sieht genauso
//     aus. Deshalb zusaetzlich:
//   * der Kommentar muss auf DERSELBEN Zeile schliessen. Eine
//     Fortsetzungszeile eines mehrzeiligen Blocks ist nie Doku.
//   * die naechste Code-Zeile ist ein Routinenkopf, dessen Name den Namen
//     aus dem Kommentar AM UNTERSTRICH umschliesst ('Save' ->
//     'TRegAuto_Save'). Nur Namensgleichheit oder blosse Teilzeichenkette
//     reicht NICHT: gleicher Name ist eine auskommentierte UEBERLADUNG
//     (42 Faelle im Korpus, bleiben Funde), und ohne Unterstrich-Anker
//     matchte 'im' in 'ImmedBW' (cnwizards).
// Gemessene Wirkung: 4.515 der 20.354 Funde (22,2 %).
//
// Nachtrag rw20 (2026-08-28): die drei Bedingungen sind bestaetigt, die
// zusaetzliche Mindestlaenge des Namens war es nicht - sie stand quer zum
// Unterstrich-Anker und kostete 155 Doku-Header. Details unten am Gate.
// ===========================================================================

function SelfContainedComment(const Line: string; out Content: string): Boolean;
// Kommentar, der auf DERSELBEN Zeile beginnt und schliesst. '//' zaehlt
// dazu (endet mit der Zeile), '{$...}' nicht (Direktive).
var
  p, q : Integer;
begin
  Result  := False;
  Content := '';
  p := Pos('//', Line);
  if p > 0 then
  begin
    Content := Copy(Line, p + 2, MaxInt);
    Exit(True);
  end;
  p := Pos('{', Line);
  if (p > 0) and ((p + 1 > Length(Line)) or (Line[p + 1] <> '$')) then
  begin
    q := PosEx('}', Line, p + 1);
    if q = 0 then Exit(False);
    Content := Copy(Line, p + 1, q - p - 1);
    Exit(True);
  end;
  p := Pos('(*', Line);
  if p > 0 then
  begin
    q := PosEx('*)', Line, p + 2);
    if q = 0 then Exit(False);
    Content := Copy(Line, p + 2, q - p - 2);
    Exit(True);
  end;
end;

function RoutineNameOf(const S: string): string;
// Name hinter [class] procedure|function|constructor|destructor, ohne
// Qualifizierer. '' wenn die Zeile kein Routinenkopf ist.
const
  KW : array[0..3] of string = ('procedure', 'function', 'constructor',
                                'destructor');
var
  T, K : string;
  p    : Integer;
begin
  Result := '';
  T := TrimLeft(LowerCase(S));
  if Copy(T, 1, 6) = 'class ' then T := TrimLeft(Copy(T, 7, MaxInt));
  for K in KW do
  begin
    if Copy(T, 1, Length(K)) <> K then Continue;
    p := Length(K) + 1;
    if (p > Length(T)) or not CharInSet(T[p], [' ', #9]) then Continue;
    while (p <= Length(T)) and CharInSet(T[p], [' ', #9]) do Inc(p);
    while (p <= Length(T)) and
          CharInSet(T[p], ['a'..'z', '0'..'9', '_', '.']) do
    begin
      // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
      // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
      // noinspection StringConcatInLoop
      Result := Result + T[p];
      Inc(p);
    end;
    // Qualifizierer abschneiden: 'tfoo.save' -> 'save'
    p := LastDelimiter('.', Result);
    if p > 0 then Result := Copy(Result, p + 1, MaxInt);
    Exit;
  end;
end;

function IsRoutineHeaderOnly(const Content: string): Boolean;
// Nur ein Kopf: kein ':=', kein begin/end, endet auf ';'.
var
  T, L : string;
begin
  Result := False;
  T := Trim(Content);
  if T = '' then Exit;
  if T[Length(T)] <> ';' then Exit;
  if Pos(':=', T) > 0 then Exit;
  L := LowerCase(T);
  if ContainsWordCI(L, 'begin') then Exit;
  if ContainsWordCI(L, 'end')   then Exit;
  Result := RoutineNameOf(T) <> '';
end;

function IsAdapterDocHeader(Lines: TStringList; CurIdx: Integer): Boolean;
var
  Content, Nm, Nxt, S : string;
  j : Integer;
begin
  Result := False;
  if (Lines = nil) or (CurIdx < 0) or (CurIdx >= Lines.Count) then Exit;
  if not SelfContainedComment(Lines[CurIdx], Content) then Exit;
  if not IsRoutineHeaderOnly(Content) then Exit;
  Nm := RoutineNameOf(Trim(Content));
  // Untergrenze 2, nicht 4 (Klasse C, Korpus rw20 2026-08-28). Die
  // Trennschaerfe leistet NICHT die Laenge, sondern der Unterstrich-Anker
  // weiter unten: bei 'add' -> 'tlist_add' ist er genauso scharf wie bei
  // 'save' -> 'tregauto_save'. Die alte 4 war willkuerlich und hat 155
  // Fundstellen echter Adapter-Doku-Header ('add', 'pop', 'run', 'arc',
  // 'pie', 'cmp', 'ln') als auskommentierten Code gemeldet - das sind
  // allerdings nur 40 verschiedene Faelle, alle im Repo jvcl und dort in
  // der Dateifamilie JvInterpreter_*, die ueberwiegend in vier Kopien
  // desselben Quellbaums liegt; die Einordnung steht im Unit-Kopf.
  // Aufgeschluesselt: 151 der 155 haben einen Dreizeichen-Namen, 4 einen
  // Zweizeichen-Namen ('ln', ein einziger Fall in vier Kopien). Die 2
  // ist also nicht die ertragreichste Grenze, sondern die strukturell
  // begruendete - eine 3 haette 151 geholt und genau einen Fall
  // verfehlt.
  //
  // Eine Untergrenze bleibt aber noetig: bei EINEM Zeichen ist '_' + Nm
  // nur noch ein Zwei-Zeichen-Suffix und damit kein Anker mehr. Im
  // Korpus enden 3.761 Routinennamen auf '_' + ein Zeichen, verteilt auf
  // gerade 34 verschiedene Endstuecke - 110,6 Namen je Endstueck, allein
  // 1.883 auf '_r'. Bei zwei Zeichen sind es 3,0 Namen je Endstueck. Ein
  // stillgelegtes '{ procedure R; }' ueber irgendeinem 'Foo_R' fiele
  // sonst lautlos weg.
  //
  // Das gilt fuer BEIDE Zweige des Gates - es akzeptiert
  // Nxt.EndsWith('_' + Nm) ODER Nxt.StartsWith(Nm + '_'), die Rechnung
  // oben ist die des Suffix-Zweigs. Der Praefix-Zweig, selbst
  // nachgerechnet: 1.937 Routinennamen beginnen mit einem Zeichen + '_',
  // auf nur 12 verschiedene Anfangsstuecke - 161,4 Namen je Stueck,
  // allein 1.835 auf 'g_' aus den GLib-Bindungen. Bei einem Zeichen
  // bricht er also aus demselben Grund zusammen wie der Suffix-Zweig;
  // die Untergrenze 2 deckt beide.
  // Gleich verhaelt er sich damit aber NICHT: bei zwei Zeichen stehen
  // 1.583 Namen auf 64 Anfangsstuecken, 24,7 je Stueck (679 davon
  // 'cm_') - der Praefix-Zweig ist bei jeder Laenge unschaerfer als der
  // Suffix-Zweig, weil vorangestellte Kuerzel Bibliotheks-Praefixe sind
  // (g_, cm_, nw_, js_, get_, sk4d_) und keine Routinennamen. Getragen
  // wird die Absenkung dort nicht von dieser Dichte, sondern davon,
  // dass der Zweig im Korpus ueberhaupt nicht feuert: ueber alle 13.419
  // .pas-Dateien liefert das Gate an 4.821 Stellen True, davon 4.821
  // ueber den Suffix-Zweig und 0 ueber den Praefix-Zweig, bei JEDER
  // Namenslaenge. Auch die 155 Drops kommen samt und sonders aus dem
  // Suffix-Zweig. Am Praefix-Zweig bewegt die Absenkung gemessen nichts
  // - wer ihn spaeter scharf stellt, muss neu rechnen.
  //
  // Deshalb absenken statt streichen: IsRoutineHeaderOnly hat oben schon
  // RoutineNameOf(Trim(Content)) <> '' auf DEMSELBEN String verlangt, Nm
  // ist hier also nie leer. 'Length(Nm) < 1' waere toter Code - die
  // Zeile wegzulassen ist gleichbedeutend damit, die Ein-Zeichen-Namen
  // zuzulassen.
  if Length(Nm) < 2 then Exit;

  for j := CurIdx + 1 to Lines.Count - 1 do
  begin
    S := TrimLeft(Lines[j]);
    if S = '' then Continue;
    if S.StartsWith('//') or S.StartsWith('{') or S.StartsWith('(*') then
      Continue;
    Nxt := RoutineNameOf(S);
    if Nxt = '' then Exit;                       // naechste Zeile kein Kopf
    Result := (Nxt <> Nm) and
              (Nxt.EndsWith('_' + Nm) or Nxt.StartsWith(Nm + '_'));
    Exit;
  end;
end;

class procedure TCommentedOutCodeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk    : Boolean;
  // Zeilenuebergreifender Zustand: eine offene '(*'-Region und ob sie
  // als '(*$'-Direktive begann. Fortsetzungszeilen einer Direktive
  // duerfen nicht als Kommentar bewertet werden; Begruendung samt
  // Korpuszahlen steht an FindCommentedOutCode.
  ParenStar: TParenStarLage;
  Cached   : Boolean;
  // Region-Sammler (s. Kommentar in der Schleife). RegStart = 0
  // heisst: keine offene Region.
  RegStart : Integer;
  RegEnd   : Integer;
  RegCol   : Integer;

  procedure FlushRegion;
  var
    F : TLeakFinding;
  begin
    if RegStart = 0 then Exit;
    if RegEnd = RegStart then
      // Einzeiler: WOERTLICH die alte Meldung - Identitaet bleibt.
      Results.Add(TLeakFinding.New(FileName, '', RegStart,
        Format('Comment at column %d looks like commented-out code - ' +
               'delete or extract into a TODO if still relevant.', [RegCol]),
        fkCommentedOutCode))
    else
    begin
      F := TLeakFinding.New(FileName, '', RegStart,
        Format('Commented-out code block of %d lines starting at column %d - ' +
               'delete or extract into a TODO if still relevant.',
               [RegEnd - RegStart + 1, RegCol]),
        fkCommentedOutCode);
      F.EndLine := RegEnd;
      Results.Add(F);
    end;
    RegStart := 0;
  end;

begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk      := False;
    ParenStar.Offen        := False;
    ParenStar.IstDirektive := False;
    RegStart := 0; RegEnd := 0; RegCol := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindCommentedOutCode(Lines[i], InBlk, ParenStar);
      if Col <= 0 then Continue;
      // FP-Schutz 1: Multi-Line-Doc-Block per '//' - Doc-Pattern mit
      // Pascal-Code-Beispielen, nicht commented-out Code. Echte
      // commented-out Zeilen stehen einzeln zwischen echtem Code.
      // Aktiv wenn die Zeile selbst mit '//' beginnt UND mind. eine
      // angrenzende Zeile auch '//' ist (Vorzeile ODER Folgezeile).
      // Look-Ahead deckt den Block-Start ab (vorher Code, danach '//').
      if (Col > 0) and Lines[i].TrimLeft.StartsWith('//') and
         (IsPrevLineLineComment(Lines, i) or
          IsNextLineLineComment(Lines, i)) then
        Continue;
      // FP-Schutz 2: Inline-Kommentar nach Code (Doku-Hint hinter Statement
      // wie 'fkXxx,  // Pascal-Keyword nicht...'). Echtes auskommentiertes
      // Code-Statement steht typischerweise allein auf seiner Zeile.
      // Pruefung nur fuer //-Kommentare; Block-Kommentare bleiben strikt.
      if (Col > 0) and Lines[i].Contains('//') and
         IsInlineComment(Lines[i], Col) then
        Continue;
      // FP-Schutz 3 (Audit 2026-07-31): Adapter-Doku-Header - der Kommentar
      // dokumentiert die Signatur der Routine, die direkt darunter steht.
      if IsAdapterDocHeader(Lines, i) then Continue;
      // Region-Granularitaet (Produktentscheidung Nico 2026-09-05):
      // direkt aufeinanderfolgende gemeldete Zeilen bilden EINEN Fund.
      // Luecke 0 ist die strengste Lesart von "zusammenhaengend" -
      // eine luecken-tolerante Bildung wuerde ungemeldete Prosa- oder
      // Leerkommentarzeilen mit beanspruchen. Einzeiler behalten
      // WOERTLICH die alte Meldung (77 % der Regionen, rw63: 7.964
      // von 10.317) - deren Fund-Identitaet und Baselines bleiben
      // stehen; nur Mehrzeilen-Bloecke wechseln auf die Block-Meldung
      // mit endLine-Spanne. Anker = erste Blockzeile, Spalte = deren
      // Spalte. Suppression wirkt damit am ANKER fuer den ganzen
      // Block; ein Marker auf einer Folgezeile unterdrueckt nicht
      // mehr einzeln (dokumentierte Folge der Entscheidung).
      if (RegStart > 0) and (i + 1 = RegEnd + 1) then
        RegEnd := i + 1
      else
      begin
        FlushRegion;
        RegStart := i + 1;
        RegEnd   := i + 1;
        RegCol   := Col;
      end;
    end;
    FlushRegion;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
