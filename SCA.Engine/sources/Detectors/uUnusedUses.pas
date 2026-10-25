unit uUnusedUses;

// AST-basierter Detektor fuer moeglicherweise ungenutzte uses-Eintraege.
//
// Kombiniert zwei Heuristiken:
//
//   H1 - Qualifizierter Bezeichner:
//        Sucht 'unitname.' als Praefix in Bezeichnern.
//        Beispiel: SysUtils.IntToStr  ->  'sysutils.' im Raw-Corpus
//
//   H2 - Bekannte Typen / Funktionen:
//        Prueft ob bekannte Bezeichner aus der Unit als eigenstaendige
//        Woerter im Quelltext vorkommen.
//        Beispiel: TStringList  ->  System.Classes ist benoetigt
//
// Einschraenkungen (keine 100% Sicherheit):
//   - Units mit reinem Initialisierungscode (z.B. Vcl.Themes)
//   - Bedingte Kompilierung ($IFDEF)
//   - Typen aus unbekannten (nicht gemappten) Units
//   Befunde sind daher immer Warnungen, keine Fehler.
//
// OPT-IN: der Detektor laeuft nur mit [Detectors] UsesCheck=1 oder im
// Profil 'strict' (uRepoSettings: "alle + opt-in Detektoren"). Form-GUI
// und IDE-Plugin setzen Req.UsesCheck aus Settings.UsesCheck; der CLI
// seit 2026-09-19 ueber uConsoleRunner.EffektiverUsesCheck (ini-Schalter
// ODER Profil 'strict').
//
// HISTORIE (Review 2026-10-13: der Kopf trug "GEFIXT" und "NICHT HIER
// GEFIXT" zugleich - hier die Reihenfolge):
//   2026-09-15  Befund: im CLI lief der Detektor NIE. uConsoleRunner
//               setzte Req.UsesCheck nicht, TAnalysisRequest.Default
//               laesst es False, uStaticAnalyzer2 schaltet fkUnusedUses
//               damit ab. Drei Belege: Referenzlauf 752.457 Funde mit
//               SCA007 = 0; 27 repo-weise Laeufe mit UsesCheck=1 je 0;
//               --time-detectors fuehrte UnusedUses nicht. Bewusst nicht
//               sofort gefixt: die eine Zeile legt rund 24.000 Funde mit
//               ungemessener FP-Quote frei - ein Recall-Paket mit eigenem
//               Zweig, Bau und FP-Stichprobe (Projektregel; Vorbild
//               AutoDiscoverClasses, uEngineApi BUGFIX 2026-07-15).
//   2026-09-19  Gefixt im Zweig sca007-cli-recall samt FP-Stichprobe am
//               gebauten Stand (C-/D4-/F3-Chargen in dieser Unit).
//
// Die 0 war NICHT die Losbildungsfalle: AnalyzeUnit bekommt keinen
// Projektkontext, CollectText baut den Suchtext allein aus DIESEM AST -
// was in anderen Units steht, kann der Detektor nicht wissen.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnusedUsesDetector = class
  public
    // AContext (Charge P1, 2026-10-25): der Scan-Kontext liefert Zeilen-
    // und Strip-Cache (ein Strip je Datei fuer alle Detektoren statt
    // eines eigenen). nil -> Prozess-Cache und eigener Strip, dieselbe
    // Antwort (Tests, reDelphix).
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);

    // ---- Suchtext-Bausteine (Charge P1, 2026-10-25) ----
    // Tempo-Umbau ohne Verhaltensaenderung. Bis dahin pruefte H1 mit
    // Pos(Praefix + '.', RawText) und H2 mit Pos(' ' + Id + ' ',
    // WordText) - je Bezeichner ein Durchlauf ueber den GANZEN Suchtext
    // (Quelltext + AST-Namen), bei ~25 Bezeichnern je gemappter Unit der
    // groesste Posten des Strict-Laufs (laz ~4 s). Public und static,
    // damit die Aequivalenz zur alten Pos-Form direkt testbar ist
    // (uTestUnusedUsesSuchtext).

    // Die Raw-Sicht eines (lowercase) Textes: jedes Zeichen ausser
    // a..z, 0..9, '_' und '.' wird zu ' ' - zeichengenau die Abbildung,
    // die CollectText und der Quelltext-Kanal frueher Zeichen fuer
    // Zeichen anhingen. Die Laenge bleibt gleich.
    class function RawSicht(const S: string): string; static;

    // 1-basierte Positionen aller '.' in Text, aufsteigend.
    class function PunktPositionen(const Text: string): TArray<Integer>; static;

    // VERTRAG: = (Pos(Praefix + '.', Text) > 0), Punkte =
    // PunktPositionen(Text). Also auch Treffer MITTEN im Wort
    // ('myclasses.x' deckt 'classes') - das ist der alte H1-Vertrag,
    // hier nur ohne Durchlauf je Praefix. Leeres Praefix: True gdw.
    // Text einen Punkt hat.
    class function PraefixVorPunkt(const Text: string;
      const Punkte: TArray<Integer>; const Praefix: string): Boolean; static;

    // Traegt jedes Wort von Text in Woerter ein - Woerter sind die
    // maximalen Laeufe ohne ' ' und '.'. VERTRAG fuer einen Text, der
    // leer ist oder mit ' ' beginnt und endet (der Suchtext in
    // AnalyzeUnit ist das immer), und ein Id ohne Leerzeichen:
    // Woerter.ContainsKey(Id) = (Pos(' ' + Id + ' ',
    // Text.Replace('.', ' ')) > 0) - der alte H2-Vertrag auf dem
    // WordText, der genau diese Ersetzung war. Seit Charge Q5 nur noch
    // das Orakel von WoerterVorhanden (der Detektor ruft es nicht mehr).
    class procedure SammleWoerter(const Text: string;
      Woerter: TDictionary<string, Boolean>); static;

    // Perf Charge Q5 (2026-10-25). VERTRAG: Result[k] = Woerter.
    // ContainsKey(Ids[k]) mit Woerter aus SammleWoerter(Text) - Ids[k] ist
    // ein maximaler Lauf ohne ' ' und '.' in Text. Ohne Kopie und
    // Hash-Eintrag je Wort des Textes: EIN Lauf ueber den Text, je Wort
    // ein Fachvergleich (Laenge, erstes Zeichen) gegen die wenigen Ids;
    // Schluss, sobald alle gefunden sind. '' ist nie ein Wort.
    class function WoerterVorhanden(const Text: string;
      const Ids: TArray<string>): TArray<Boolean>; static;

    // Perf Charge Q5: der AST-Teil des Suchtexts. VERTRAG: die Verkettung
    // von ' ' + RawSicht(OhneLiterale(S).ToLower) + ' ' fuer jedes
    // nichtleere S aus Name und TypeRef jedes Knotens ausser nkUsesItem,
    // in Baumreihenfolge (vorher je Name so angehaengt). Gerechnet mit
    // EINEM ToLower ueber die verkettete Rohform - string.ToLower
    // (LCMapString LCMAP_LOWERCASE) bildet zeichenweise und laengentreu
    // ab, das ' ' bleibt ' ' (Probe ueber alle BMP-Zeichen in sieben
    // Locales, auch tr-TR).
    class function AstSuchtext(Node: TAstNode): string; static;

    // I2 (2026-09-20): der Inhalt der Stringliterale eines AST-Namens
    // geblankt (Begruendung an CollectText). Bis Charge Q5 lokal in
    // CollectText; public fuer den Vertragstest von AstSuchtext.
    class function OhneLiterale(const S: string): string; static;

    // F3 (2026-09-19): blankt jede uses-Klausel (vom Wort 'uses' bis
    // zum naechsten ';') im GESTRIPPTEN lowercase-Text zu Leerzeichen.
    // Vertrag: die uses-Klauseln selbst duerfen im Quelltext-Kanal
    // keinen Verwendungsnachweis liefern - dieselbe Politik, mit der
    // CollectText nkUsesItem-Knoten ausschliesst. Ohne das Blanken
    // naehrt 'uses FMX.Controls.Presentation;' den H1-Praefixtest
    // 'controls.' und deckt faelschlich die Eltern-Unit FMX.Controls
    // (FN-Muster der D4-Abnahme). Fehlt das ';' (abgerissener Text),
    // bleibt die Klausel stehen - lieber ein fehlender Fund als der
    // halbe Suchtext weg. Public und static, damit der Vertrag direkt
    // testbar ist.
    class procedure BlankeUsesKlauseln(var Text: string); static;

    // Public seit 2026-10-10: die SCA007-Editorhilfe (reDelphix) prueft
    // einen Fund vor der Loeschung am AKTUELLEN Editor-Puffer nach - mit
    // denselben Spuren wie H1/H2 hier (der Fund kann aelter sein als der
    // Text).
    //
    // True, wenn der (lowercase) Unit-Name dotless ist ODER sein erstes
    // Segment ein Embarcadero-Unit-Scope-Namespace ist (System, Vcl,
    // FMX, ...). Gate fuer den Kurznamen-Fallback von KnownIdents:
    // NUR dann bezeichnet der Kurzname dieselbe RTL/VCL/FMX-Unit wie
    // der volle Name. C-Charge 2026-09-19 (SCA007-FP-Stichprobe der
    // Recall-Freigabe): ohne das Gate fiel 'Alcinoe.FMX.StdCtrls' auf
    // KnownIdents('stdctrls') - die VCL-Identliste - zurueck, TButton &
    // Co. kommen in der Fremd-Unit natuerlich nicht vor, und die Unit
    // wurde trotz TALButton-Nutzung gemeldet. Gemessen am rw112-Lauf:
    // exakt 374 solcher Funde (mORMot 277, Alcinoe 88, ...).
    class function IstRtlNamespace(const UnitLow: string): Boolean; static;

    // Bekannte oeffentliche Bezeichner einer Unit (fuer H2), lowercase.
    // VERTRAG: UnitLow ist der volle Name in Kleinschrift ('system.
    // classes') ODER ein Kurzname ('classes'); beide Schreibweisen sind
    // je Eintrag gelistet. LEER heisst "Unit nicht gemappt" - nicht
    // "keine Bezeichner": H2 kann dann nichts beweisen und der Detektor
    // schweigt (lieber false negative als false positive). Die Tabelle
    // kennt KEINEN Kurznamen-Rueckfall; den liefert IdentsFor.
    class function KnownIdents(const UnitLow: string): TArray<string>; static;

    // KnownIdents mit dem Kurznamen-Rueckfall fuer RTL-Namespaces: leer
    // fuer den vollen Namen UND IstRtlNamespace -> KnownIdents(Kurzname).
    // 'fmx.styles' -> die 'styles'-Liste; 'alcinoe.fmx.stdctrls' bleibt
    // leer (C-Charge 2026-09-19). Oeffentlich, weil die SCA007-
    // Editorhilfe (reDelphix uRdxRecipeRunner.UnitStillUsed) dieselbe
    // Kette nachbaut - sie soll kuenftig hierher zeigen (Review
    // 2026-10-13; reDelphix in dieser Charge unveraendert).
    class function IdentsFor(const UnitLow: string): TArray<string>; static;
  private
    // Sammelt die Rohform des AST-Teils: ' ' + OhneLiterale(S) + ' ' je
    // nichtleerem Name/TypeRef (ausser nkUsesItem). Klein und Raw-Sicht
    // macht AstSuchtext einmal fuer alles (Perf Charge Q5). Den frueheren
    // zweiten Text WordText (dasselbe mit '.' -> ' ', fuer H2: ' tlist ')
    // ersetzt seit Charge P1 die Wortmenge (heute WoerterVorhanden).
    class procedure CollectText(Node: TAstNode;
      RawSB: TStringBuilder); static;

    // Letzter Namensbestandteil: 'System.Classes' -> 'classes'
    class function ShortName(const QualName: string): string; static;

    // Units die nie gemeldet werden sollen
    class function IsAlwaysNeeded(const UnitLow: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, InsecureCryptoAlgorithm, RedundantJump, TooLongLine, UnsortedUses
// InsecureCryptoAlgorithm: die System.Hash-Klassenliste ('thashmd5','thashsha1'...)
// dient der UnusedUses-Erkennung - Self-Match, kein realer Krypto-Einsatz.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,    // TStringList (Quelltext-Kanal, D4)
  System.StrUtils,   // PosEx (F3: uses-Klauseln blanken)
  uDetectorUtils,    // StripStringsAndCommentsCached (D4)
  uFileTextCache;    // AcquireLines/ReleaseLines (D4)

{ ---- Hilfsmethoden ---- }

class function TUnusedUsesDetector.ShortName(const QualName: string): string;
var
  p: Integer;
begin
  p := LastDelimiter('.', QualName);
  if p > 0 then Result := Copy(QualName, p + 1, MaxInt)
  else          Result := QualName;
end;

class procedure TUnusedUsesDetector.BlankeUsesKlauseln(var Text: string);
// Vertrag siehe Deklaration. Der Text kommt aus StripStringsAndComments
// (Strings/Kommentare/Direktiven bereits weg) und ist lowercase - das
// Wort 'uses' kann dort nur als Klausel-Anfang stehen (reserviert;
// String-Vorkommen sind geblankt). Wortgrenzen links UND rechts: auch
// der Punkt zaehlt als Grenzverletzung, damit ein pathologisches
// 'x.uses' aus kaputtem Quelltext keine Klausel beginnt.
var
  P, E, K : Integer;
  L       : Integer;
begin
  L := Length(Text);
  P := 1;
  while True do
  begin
    P := PosEx('uses', Text, P);
    if P = 0 then Exit;
    if ((P = 1) or
        not CharInSet(Text[P - 1], ['a'..'z', '0'..'9', '_', '.'])) and
       ((P + 4 > L) or
        not CharInSet(Text[P + 4], ['a'..'z', '0'..'9', '_', '.'])) then
    begin
      E := PosEx(';', Text, P + 4);
      if E = 0 then Exit;   // kein Abschluss: Klausel stehen lassen
      for K := P to E do
        Text[K] := ' ';
      P := E + 1;
    end
    else
      Inc(P, 4);
  end;
end;

class function TUnusedUsesDetector.IstRtlNamespace(
  const UnitLow: string): Boolean;
// Vertrag siehe Deklaration. Die Liste sind die Unit-Scope-Namespaces
// der Delphi-RTL/-Frameworks; ein dotless Name liefert True, weil der
// Kurznamen-Fallback dort ohnehin ein No-Op ist (ShortName = Name).
// FMX steht MIT ABSICHT drin: der dokumentierte Nutz-Fall des
// Fallbacks ist FMX.Styles -> KnownIdents('styles') (TStyleManager-
// Nachweis fuer python4delphi/WrapFmxStyles, s. Kommentar an der
// Vcl.Themes-Tabelle).
const
  NAMESPACES: array[0..16] of string = (
    'system', 'winapi', 'vcl', 'fmx', 'data', 'datasnap', 'xml',
    'soap', 'web', 'rest', 'bde', 'ibx', 'firedac', 'posix',
    'androidapi', 'iosapi', 'macapi');
var
  P    : Integer;
  Erst : string;
begin
  P := Pos('.', UnitLow);
  if P = 0 then Exit(True);
  Erst := Copy(UnitLow, 1, P - 1);
  for var NS in NAMESPACES do
    if Erst = NS then Exit(True);
  Result := False;
end;

class function TUnusedUsesDetector.IsAlwaysNeeded(const UnitLow: string): Boolean;
const
  SAFE: array[0..13] of string = (
    // Immer implizit benoetigt
    'system', 'sysinit',
    // Fast immer benoetigt (Basistypen, Exceptions, String-Funktionen)
    'sysutils', 'system.sysutils',
    // Windows-API: sehr haeufig indirekt benoetigt
    'windows', 'winapi.windows',
    'messages', 'winapi.messages',
    // VCL-Basiseinheiten (fast immer transitiv benoetigt)
    'types', 'system.types',
    'uitypes', 'system.uitypes',
    // Interfaces / unbekannte Abhaengigkeiten
    'activex', 'comobj'
  );
begin
  for var S in SAFE do
    if UnitLow = S then Exit(True);
  // Registration-Units (Konvention: enden auf 'reg')
  if UnitLow.EndsWith('reg') then Exit(True);
  Result := False;
end;

class function TUnusedUsesDetector.RawSicht(const S: string): string;
// Vertrag siehe Deklaration. Dieselbe Zeichenmenge wie das fruehere
// CharInSet(Ch, ['a'..'z', '0'..'9', '_', '.']) - CharInSet war fuer
// Zeichen ab #$0100 und fuer #$80..#$FF ebenfalls False.
var
  i   : Integer;
  Src : PChar;
  Dst : PChar;
  Ch  : Char;
begin
  SetLength(Result, Length(S));
  if S = '' then Exit;
  Src := PChar(S);
  Dst := PChar(Result);
  for i := 0 to Length(S) - 1 do
  begin
    Ch := Src[i];
    if ((Ch >= 'a') and (Ch <= 'z')) or ((Ch >= '0') and (Ch <= '9')) or
       (Ch = '_') or (Ch = '.') then
      Dst[i] := Ch
    else
      Dst[i] := ' ';
  end;
end;

class function TUnusedUsesDetector.PunktPositionen(
  const Text: string): TArray<Integer>;
var
  i, n : Integer;
  P    : PChar;
begin
  n := 0;
  P := PChar(Text);
  for i := 0 to Length(Text) - 1 do
    if P[i] = '.' then Inc(n);
  SetLength(Result, n);
  n := 0;
  for i := 0 to Length(Text) - 1 do
    if P[i] = '.' then
    begin
      Result[n] := i + 1;
      Inc(n);
    end;
end;

class function TUnusedUsesDetector.PraefixVorPunkt(const Text: string;
  const Punkte: TArray<Integer>; const Praefix: string): Boolean;
// Pos(Praefix + '.', Text) > 0 heisst: an einer Punktposition d steht
// direkt davor das Praefix, also Text[d - L .. d - 1] = Praefix mit
// L = Length(Praefix) und d > L. Der Vergleich des letzten Zeichens
// vorab spart den CompareMem fuer fast jeden Punkt.
var
  L    : Integer;
  d    : Integer;
  Letz : Char;
begin
  L := Length(Praefix);
  if L = 0 then Exit(Length(Punkte) > 0);
  Letz := Praefix[L];
  for d in Punkte do
    if (d > L) and (Text[d - 1] = Letz) and
       CompareMem(PChar(Text) + (d - L - 1), PChar(Praefix),
         L * SizeOf(Char)) then
      Exit(True);
  Result := False;
end;

class procedure TUnusedUsesDetector.SammleWoerter(const Text: string;
  Woerter: TDictionary<string, Boolean>);
var
  i, n, Start : Integer;
  P           : PChar;
begin
  n := Length(Text);
  P := PChar(Text);
  i := 0;
  while i < n do
  begin
    while (i < n) and ((P[i] = ' ') or (P[i] = '.')) do Inc(i);
    Start := i;
    while (i < n) and (P[i] <> ' ') and (P[i] <> '.') do Inc(i);
    if i > Start then
      Woerter.AddOrSetValue(Copy(Text, Start + 1, i - Start), True);
  end;
end;

class function TUnusedUsesDetector.WoerterVorhanden(const Text: string;
  const Ids: TArray<string>): TArray<Boolean>;
// Vertrag siehe Deklaration. Fach = (Ord(erstes Zeichen) * 7 + Laenge)
// and 255 - fuer Id und Wort dieselbe Rechnung, jede Zeichenfolge hat ihr
// Fach; die Gleichheit prueft danach Laenge und CompareMem.
const
  FAECHER = 256;
var
  Kopf     : array[0..FAECHER - 1] of Integer;
  Naechst  : TArray<Integer>;
  k, b     : Integer;
  Offen    : Integer;   // noch nicht gefundene Ids (ohne '')
  i, n     : Integer;
  Start, L : Integer;
  P        : PChar;
begin
  SetLength(Result, Length(Ids));
  for k := 0 to High(Result) do
    Result[k] := False;
  if Length(Ids) = 0 then Exit;
  for b := 0 to FAECHER - 1 do
    Kopf[b] := -1;
  SetLength(Naechst, Length(Ids));
  Offen := 0;
  for k := 0 to High(Ids) do
  begin
    Naechst[k] := -1;
    if Ids[k] = '' then Continue;   // '' ist nie ein Wort
    b := (Ord(Ids[k][1]) * 7 + Length(Ids[k])) and (FAECHER - 1);
    Naechst[k] := Kopf[b];
    Kopf[b] := k;
    Inc(Offen);
  end;
  n := Length(Text);
  P := PChar(Text);
  i := 0;
  while (i < n) and (Offen > 0) do
  begin
    while (i < n) and ((P[i] = ' ') or (P[i] = '.')) do Inc(i);
    Start := i;
    while (i < n) and (P[i] <> ' ') and (P[i] <> '.') do Inc(i);
    L := i - Start;
    if L = 0 then Continue;
    k := Kopf[(Ord(P[Start]) * 7 + L) and (FAECHER - 1)];
    while k >= 0 do
    begin
      if (not Result[k]) and (Length(Ids[k]) = L) and
         CompareMem(PChar(Ids[k]), @P[Start], L * SizeOf(Char)) then
      begin
        Result[k] := True;
        Dec(Offen);
      end;
      k := Naechst[k];
    end;
  end;
end;

class function TUnusedUsesDetector.OhneLiterale(const S: string): string;
// I2 (2026-09-20): Inhalte von Stringliteralen ausblenden - Begruendung
// an CollectText.
var
  i   : Integer;
  InS : Boolean;
  SB  : TStringBuilder;
begin
  if Pos('''', S) = 0 then Exit(S);   // Normalfall: nichts zu tun
  SB := TStringBuilder.Create;
  try
    InS := False;
    i := 1;
    while i <= Length(S) do
    begin
      if S[i] = '''' then
      begin
        // Verdoppeltes '' INNERHALB eines Literals ist ein Zeichen
        // des Literals, kein Ende - beide blanken und weiter.
        if InS and (i < Length(S)) and (S[i + 1] = '''') then
        begin
          SB.Append('  ');
          Inc(i, 2);
          Continue;
        end;
        InS := not InS;
        SB.Append(' ');
      end
      else if InS then
        SB.Append(' ')
      else
        SB.Append(S[i]);
      Inc(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TUnusedUsesDetector.AstSuchtext(Node: TAstNode): string;
// Vertrag siehe Deklaration.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    CollectText(Node, SB);
    Result := RawSicht(SB.ToString.ToLower);
  finally
    SB.Free;
  end;
end;

class procedure TUnusedUsesDetector.CollectText(Node: TAstNode;
  RawSB: TStringBuilder);

  // I2 (2026-09-20): Inhalte von Stringliteralen ausblenden.
  //
  // Der Parser rekonstruiert Literale in Name/TypeRef in ihrer
  // Pascal-Form (QuoteStrLit: aeussere Hochkommata, inneres '' wieder
  // verdoppelt) - sie sind hier also an der Quotierung erkennbar. Ohne
  // dieses Ausblenden zaehlte der AST-Kanal Literaltext als
  // Verwendungsnachweis: 'Log(''computed-column variant'')' belegte
  // die Unit Variants und unterdrueckte den Fund (an der Exe belegt:
  // mit dem Wort 0 Funde, ohne es 1).
  //
  // Das ist genau die Politik, die der D4-Quelltext-Kanal unten schon
  // fuehrt ('ein Bezeichner IN einem Literal ist kein
  // Verwendungsnachweis') - dessen Begruendung nahm dabei an, "der
  // AST-Weg sah Literale nie". Diese Annahme war falsch; hier wird sie
  // eingeloest, statt zwei Kanaele mit verschiedenen Regeln zu fahren.
  //
  // GEMESSEN (i_messung_sca007): 394 Faelle im Delphi-Korpus, 29 im
  // Lazarus-Korpus, in denen der EINZIGE Nachweis aus einem Literal
  // stammt - sie werden zu Funden. Die Ausblendung selbst steht seit
  // Charge Q5 in OhneLiterale (public, Vertragstest von AstSuchtext).
  //
  // Perf Charge Q5 (2026-10-25): je Name nur noch die Rohform anhaengen;
  // ToLower (ein LCMapString-Aufruf samt Kopie) und RawSicht laufen in
  // AstSuchtext EINMAL ueber den ganzen AST-Teil statt je Name. Die
  // Kinder per Index statt for-in (kein Enumerator-Objekt je Knoten).
  procedure Add(const S: string);
  begin
    if S = '' then Exit;
    RawSB.Append(' ');
    RawSB.Append(OhneLiterale(S));
    RawSB.Append(' ');
  end;

var
  i : Integer;
begin
  if not Assigned(Node) then Exit;
  // nkUsesItem-Knoten NICHT aufnehmen: der Unit-Name selbst soll
  // nicht als "Verwendungsnachweis" gelten.
  if Node.Kind <> nkUsesItem then
  begin
    Add(Node.Name);
    Add(Node.TypeRef);
  end;
  for i := 0 to Node.Children.Count - 1 do
    CollectText(Node.Children[i], RawSB);
end;

{ ---- Bekannte Bezeichner pro Unit (H2) ---- }

class function TUnusedUsesDetector.KnownIdents(
  const UnitLow: string): TArray<string>;
// PFLEGEHINWEIS (Voll-Review 2026-09-12, Major 90): ein Eintrag mit
// Tippfehler ist hier kein kosmetischer Mangel, sondern ein FP-Erzeuger.
// H2 meldet eine gemappte Unit als unused, wenn KEINER der gelisteten
// Bezeichner vorkommt - der Eintrag, der den Nachweis liefern sollte,
// matcht dann nie. Neun solche Eintraege standen in dieser Funktion
// (Doppelungen mitgezaehlt).
//
// Jede Korrektur wurde am Korpus (16.023 Dateien) gegengeprueft, statt
// die Schreibweise zu raten - zwei naheliegende 'Korrekturen' waeren
// selbst tot gewesen (TMultiViewPanel und TThemeManager: je 0 Treffer).
// Wer hier etwas ergaenzt, zaehlt den Bezeichner vorher am Korpus.
begin
  Result := [];

  // == System-Einheiten ===================================================

  if (UnitLow = 'system.classes') or (UnitLow = 'classes') then
    Result := ['tstringlist','tstrings','tmemorystream','tfilestream',
               'tstringstream','tresourcestream','tcomponent','tpersistent',
               'tlist','tobjectlist','tcollection','tthread','tnotifyevent',
               'thandlestream','tcustomstream','tinterfacelist',
               'tbinaryreader','tbinarywriter','tencoding',
               'registerclass','findclass','getclass',
               'tcomponentiterator','tcomponentenumerator',
               'tcollectionitem','townedcollection']

  else if UnitLow = 'system.generics.collections' then
    // TList<T>, TObjectList<T> und TArray<T> sind die haeufigsten Typen;
    // ohne sie wuerde jeder TList<>-Nutzer einen false positive erhalten.
    Result := ['tlist','tobjectlist','tarray',
               'tdictionary','tobjectdictionary',
               'tqueue','tstack','tpair',
               'tsortedlist','tenumerable',
               'tobjectqueue','tobjectstack']

  else if UnitLow = 'system.generics.defaults' then
    Result := ['tcomparer','tstringcomparer','icomparer',
               'iequalitycomparer','tequalitycomparer',
               'tdefaultcomparer','ticomparerref']

  else if (UnitLow = 'system.math') or (UnitLow = 'math') then
    Result := ['floor','ceil','sqrt','power','log10','log2',
               'arctan2','arcsin','arccos','tan','cot',
               'isnan','isinfinite','isinfinitevalue','sign',
               'divmod','max','min','hypot','ldexp','frexp',
               'intpower','lnxp1','sincos','logn']

  else if (UnitLow = 'system.strutils') or (UnitLow = 'strutils') then
    Result := ['posex','containsstr','startsstr','endsstr',
               'splitstring','joinstring','reversestring',
               'dupestring','wraptext','leftstr','rightstr','midstr',
               'countstr','ansicontainsstr','ansistartsstr',
               'ansistartstext','ansicontainstext','ansiindexstr',
               'contractwhitespace','expandwhitespace',
               'ifthen','finddelimiter']

  else if UnitLow = 'system.ioutils' then
    Result := ['tfile','tdirectory','tpath',
               'tcreationdisposition','tfileaccess','tfilesystemattrset',
               'tpathtoounittargettype']

  else if (UnitLow = 'system.inifiles') or (UnitLow = 'inifiles') then
    Result := ['tinifile','tmeminifile','tcustominifile',
               'thashedstringlist','treginifile']

  else if UnitLow = 'system.regularexpressions' then
    Result := ['tregex','tmatch','tmatchcollection','tgroupcollection',
               'tgroup','tregexoptions','isregex','tregexengine']

  else if UnitLow = 'system.json' then
    Result := ['tjsonobject','tjsonarray','tjsonvalue','tjsonstring',
               'tjsonnumber','tjsonbool','tjsonnull','tjsonpair',
               'tjsonserializer','tjsondeserializer','tjsonmarshal',
               'tjsonunmarshal','tjsonparser','tjsonreader']

  else if (UnitLow = 'system.dateutils') or (UnitLow = 'dateutils') then
    Result := ['dateof','timeof','daysbetween','monthsbetween','yearsbetween',
               'incday','incmonth','incyear','isinleapyear','weekof',
               'hoursbetween','minutesbetween','secondsbetween',
               'startoftheday','endoftheday','startofthemonth',
               'endofthemonth','startoftheyear','endoftheyear',
               'dayofweek','dayoftheyear','weekoftheyear',
               'encodedate','encodetime','encodedatetime',
               'decodedatetime','decodedate','decodetime',
               'today','now','yesterday','tomorrow']

  else if UnitLow = 'system.zip' then
    Result := ['tzipfile','tzipmode','tzipcompression',
               'tzipfileentry','tziponprogress']

  else if UnitLow = 'system.diagnostics' then
    Result := ['tstopwatch','ttimespan']

  else if UnitLow = 'system.threading' then
    Result := ['ttask','ittask','ttaskstatus','tparallel',
               'tfuture','tspinlock','tspinwait','tmonitor',
               'tinterlocked','tlightweightevent','tmrewlock']

  else if (UnitLow = 'system.hash') or (UnitLow = 'hash') then
    Result := ['thashmd5','thashsha1','thashsha2_256','thashsha2_512',
               'thashbobjenkins','thashfnv1a32','thash',
               'tbytes','thashsha2']

  else if (UnitLow = 'system.rtti') or (UnitLow = 'rtti') then
    Result := ['trtticontext','trttitype','trttimethod','trttifield',
               'trttiproperty','trttirecordfield','trttiparameter',
               'trttiobjecttype','trttiinstancetype','tvalue',
               'trttinamedargument','trttimethodtype']

  else if (UnitLow = 'system.typinfo') or (UnitLow = 'typinfo') then
    Result := ['getenumname','getenumvalue','getenumordvalue',
               'typeinfo','propinfo','ttypeinfo','ttypedata',
               'tpropinfo','tproplist','getproplist','getpropinfo',
               'getordprop','setordprop','getstrprop','setstrprop',
               'getfloatprop','setfloatprop','getobjectprop',
               'isobjectprop','propcount','tpropcount']

  else if (UnitLow = 'system.variants') or (UnitLow = 'variants') then
    // F2 (2026-09-19): 'variant'/'olevariant' ergaenzt. Der TYP ist
    // zwar ein Compiler-Builtin, aber jede Operation auf ihm (Zuweisung,
    // Vergleich, Konvertierung) braucht die Variants-Unit zur Laufzeit -
    // eine Datei, die Variant-Variablen fuehrt, nutzt die uses-Zeile
    // also real (KnownIdents-Luecke der D-Charge-Stichprobe; Korpus-
    // Zaehlung im F2-Vertrag).
    Result := ['vartype','varastype','varisnull','varisempty',
               'vartostr','tvardata','varclear','varisarray',
               'varislongint','varisstring','vartostrdef',
               'varisordinal','varisfloat','varisdispatched',
               'variant','olevariant']

  else if (UnitLow = 'system.character') or (UnitLow = 'character') then
    Result := ['tcharacter','isletter','isdigit','iswhitespace',
               'isupper','islower','ispunctuation','issymbol',
               'iscontrol','issurrogate','toupperfull','tolowerfull']

  else if (UnitLow = 'system.netencoding') or
          (UnitLow = 'system.net.encoding') then
    Result := ['tnetencoding','tbase64encoding','turlencodings',
               'thtmlencoding','tbase64urlencoding']

  else if (UnitLow = 'system.ansistrings') or (UnitLow = 'ansistrings') then
    Result := ['ansipos','ansicopy','ansicomparestr','ansicomparetext',
               'ansilowercase','ansiuppercase','ansiquotedstr',
               'ansiextractquotedstr','ansimidstr']

  else if (UnitLow = 'system.contnrs') or (UnitLow = 'contnrs') then
    Result := ['tobjectlist','tcomponentlist','tclasslist',
               'tobjectbucketlist','tqueuelist','tstacklist']

  else if UnitLow = 'system.net.httpclient' then
    Result := ['thttpclient','thttpresponse','thttprequest',
               'tcredentials','thttpclientcertificate',
               'tnamevaluepair','tproxysettings','thttprequestitem',
               'thttpclientcomponent','tnetencoding']

  else if (UnitLow = 'system.win.registry') or (UnitLow = 'registry') then
    Result := ['tregistry','tregistryconnection','tregistrydatatype',
               'treginifile','tregistrykey']

  else if (UnitLow = 'xml.xmldoc') or (UnitLow = 'xmldoc') then
    Result := ['txmldocument','ixmldocument','ixmlnode',
               'ixmlelementnode','ixmlnodelist','ixmlattr',
               'ixmlattributecollection','createxmldoc',
               'txmlnodetype','txmloption']

  else if (UnitLow = 'xml.xmlintf') or (UnitLow = 'xmlintf') then
    Result := ['ixmlnode','ixmldocument','ixmlnodelist',
               'ixmlelementnode','ixmlattr','txmlnodetype']

  // == Winapi-Einheiten ===================================================

  else if (UnitLow = 'winapi.shellapi') or (UnitLow = 'shellapi') then
    Result := ['shellexecute','shellexecuteex','shfileinfo',
               'shgetfileinfo','shgetspecialfolderpatha',
               'shgetspecialfolderpath','shbrowseforfolder',
               'tshellfolder','tshfileopstruct']

  else if (UnitLow = 'winapi.shlobj') or (UnitLow = 'shlobj') then
    Result := ['ishellfolder','ishellbrowser','ishellview',
               'titemidlist','pidl','comdlg32','shgetfolder']

  else if (UnitLow = 'winapi.commctrl') or (UnitLow = 'commctrl') then
    Result := ['ttbbutton','timagelist','ttvitem','tlvitem',
               'initcommoncontrols','initcommoncontrolsex']

  // == VCL-Einheiten ======================================================

  else if (UnitLow = 'vcl.controls') or (UnitLow = 'controls') then
    Result := ['tcontrol','twincontrol','tcontainercontrol','tcustomcontrol',
               'tcursor','tdragmode','tcontrolstate','tgraphiccontrol',
               'tdockzone','tanchorstyle','tconstraintsize',
               'tcontrolactionlink','tscrollcontrol']

  else if (UnitLow = 'vcl.forms') or (UnitLow = 'forms') then
    Result := ['tform','tframe','tapplication','tscreen','tmonitor',
               'application','screen','printer',
               'tbordericons','tcloseaction','tformstyle',
               'tposition','twindowstate','tshowaction',
               'tapplicationevents','thintwindow','tformclass',
               'tscrollform','tcustomform']

  else if (UnitLow = 'vcl.stdctrls') or (UnitLow = 'stdctrls') then
    Result := ['tlabel','tbutton','tedit','tmemo','tcombobox','tlistbox',
               'tcheckbox','tgroupbox','tscrollbar','tstatictext',
               'tradiobutton','tcustomlabel','tcustombutton','tcustomedit',
               'tcustommemo','tcustomcombobox','tcustomlistbox',
               'tcustomcheckbox']

  else if (UnitLow = 'vcl.extctrls') or (UnitLow = 'extctrls') then
    Result := ['tpanel','ttimer','timage','tshape','tsplitter','tradiogroup',
               'tscrollbox','tbevel','tpaintbox','tflowpanel',
               'tcolorbox','tcontrolbar','tgridpanel',
               'tcustomgridpanel','tcustomflowpanel']

  else if (UnitLow = 'vcl.grids') or (UnitLow = 'grids') then
    Result := ['tstringgrid','tdrawgrid','tgridoption','tdrawstate',
               'tgridcoord','tcustomgrid','tselection',
               'tgridrowheights','tgridcolwidths']

  else if (UnitLow = 'vcl.dialogs') or (UnitLow = 'dialogs') then
    Result := ['showmessage','showmessagepos','messagedlg','messagedlgpos',
               'inputbox','inputquery',
               'topendialog','tsavedialog','tcolordialog','tfontdialog',
               'tfileopendialog','tfilesavedialog','tprintdialog',
               'tprinterdialog','tpagesetupdialog','tmessagedlg',
               'tfileopenorder','tmsgdlgbtn','tmsgdlgtype']

  else if (UnitLow = 'vcl.graphics') or (UnitLow = 'graphics') then
    Result := ['tbitmap','tcanvas','tfont','tpen','tbrush',
               'tcolor','tgraphic','ticon','tpicture','tmetafile',
               'tpenstyle','tbrushstyle','tfontstyle',
               'clred','clblue','clgreen','clblack','clwhite','clsyscolor',
               'colortostring','stringtocolor','rgbtocolor',
               'gettextextentpoint','tgraphicclass']

  else if (UnitLow = 'vcl.comctrls') or (UnitLow = 'comctrls') then
    Result := ['ttreeview','tlistview','tstatusbar','ttoolbar',
               'tpagecontrol','ttabcontrol','ttabsheet','trichedit',
               'tprogressbar','ttrackbar','tupdown','ttoolbutton',
               'ttreenode','ttreenodes','tlistitem','tlistitems',
               'tlistcolumn','tlistcolumns','tstatuspanel','tstatuspanels',
               'timageoptions']

  else if (UnitLow = 'vcl.menus') or (UnitLow = 'menus') then
    Result := ['tmainmenu','tpopupmenu','tmenuitem','tshortcut',
               'tcheckgroupmenuitem','tcustommenu','tmenuanimations']

  else if (UnitLow = 'vcl.clipbrd') or (UnitLow = 'clipbrd') then
    Result := ['clipboard','tclipboard','tclipboardformat']

  else if (UnitLow = 'vcl.imagelist') or (UnitLow = 'imagelist') then
    Result := ['timagelist','tcustomimagelist','timageindex',
               'timagelistdragobject']

  else if (UnitLow = 'vcl.actnlist') or (UnitLow = 'actnlist') then
    Result := ['tactionlist','taction','tcustomactionlist',
               'tbasicaction','tactionclientitem','tcontainedaction']

  else if (UnitLow = 'vcl.actns') or (UnitLow = 'actns') then
    Result := ['taction','tactionlist','tcustomaction','tcontrolaction',
               'tlistaction','texitaction','tgroupaction']

  else if (UnitLow = 'vcl.buttons') or (UnitLow = 'buttons') then
    Result := ['tbitbtn','tspeedbutton','tglyph',
               'tbitbtnkind']

  else if (UnitLow = 'vcl.checklst') or (UnitLow = 'checklst') then
    Result := ['tchecklistbox','tcheckedstate']

  else if (UnitLow = 'vcl.printing') or (UnitLow = 'printers') then
    Result := ['tprinter','printer','tprintrange','tprinterstatus',
               'tprinterorientation','abortdoc']

  else if (UnitLow = 'vcl.dbctrls') or (UnitLow = 'dbctrls') then
    // F2 (2026-09-19): 'tfielddatalink' ergaenzt - wer eigene
    // DB-Controls baut, nutzt DbCtrls oft NUR fuer diese Klasse und
    // bekam die uses-Zeile als unused gemeldet (KnownIdents-Luecke
    // der D-Charge-Stichprobe). Der Kurzname-Zweig gilt auch fuer
    // die LCL-dbctrls (TFieldDataLink ist dort dieselbe Rolle).
    Result := ['tdbedit','tdblabel','tdbmemo','tdbcombobox','tdblistbox',
               'tdbcheckbox','tdbradiogroup','tdbimage','tdbnavigator',
               'tdbtext','tdbrichtext','tnavbutton','tfielddatalink']

  else if (UnitLow = 'vcl.dbgrids') or (UnitLow = 'dbgrids') then
    Result := ['tdbgrid','tdbgridcolumn','tdbgridcolumns',
               'tcustomdbgrid','tdbgridoption']

  // == Datenbank-Einheiten ================================================

  else if (UnitLow = 'data.db') or (UnitLow = 'db') then
    Result := ['tdataset','tfield','tfieldtype','tparam','tdatasource',
               'tdatalink','tbookmark','tfields','tparams',
               'tstringfield','tintegerfield','tfloatfield',
               'tbooleanfield','tdatetimefield','tblobfield',
               'tcalculatedfield','tlookupdataset','tcursorfield']

  else if (UnitLow = 'data.win.adodb') or (UnitLow = 'adodb') then
    Result := ['tadoconnection','tadoquery','tadocommand',
               'tadodataset','tadotable','tadostoredproc',
               'tconnectionstring','tadorecordset']

  else if (UnitLow = 'firedac.comp.client') then
    Result := ['tfdconnection','tfdquery','tfdcommand','tfdtable',
               'tfdmemtable','tfdstoredproc','tfdschemaadapter',
               'tfdguitransactionlinks']

  else if (UnitLow = 'firedac.stan.intf') then
    Result := ['ifdstanobject','ifdphysconnection','ifdphysdriver',
               'tfdresourceoptions']

  else if (UnitLow = 'firedac.stan.param') then
    Result := ['tfdparam','tfdparams']

  // == VCL - weitere Steuerelemente =======================================

  else if (UnitLow = 'vcl.mask') or (UnitLow = 'mask') then
    Result := ['tmaskedit','tcustommask','teditoption']

  else if (UnitLow = 'vcl.appevnts') or (UnitLow = 'appevnts') then
    Result := ['tapplicationevents']

  else if (UnitLow = 'vcl.filectrl') or (UnitLow = 'filectrl') then
    Result := ['tdirectorylistbox','tfilelistbox','tdrivecombobox',
               'tfilenameedit','tdirectorynameedit','tselectdirectory']

  else if (UnitLow = 'vcl.winxctrls') or (UnitLow = 'winxctrls') then
    Result := ['tsearchbox','tactivityindicator','ttoggleswitch',
               'trelativepanel','twrappanel','tsplitview']

  else if (UnitLow = 'vcl.categorybuttons') or (UnitLow = 'categorybuttons') then
    Result := ['tcategorybuttons','tcategoryitem','tbuttoncategory']

  else if (UnitLow = 'vcl.taskbar') or (UnitLow = 'taskbar') then
    Result := ['ttaskbar','ttaskbarprogress','tthumbnailbutton']

  else if (UnitLow = 'vcl.numberbox') or (UnitLow = 'numberbox') then
    Result := ['tnumberbox']

  else if (UnitLow = 'vcl.colorbutton') or (UnitLow = 'colorbutton') then
    Result := ['tcolorbutton']

  else if (UnitLow = 'vcl.htmlhelpviewer') then
    Result := ['thtmlhelpviewer']

  else if (UnitLow = 'vcl.olectrls') or (UnitLow = 'olectrls') then
    Result := ['tolecontrol','tactivexcontrol','toleinplaceobject']

  else if (UnitLow = 'vcl.shell.shellctrls') then
    Result := ['tshelltreeview','tshelllistview','tshellcombobox']

  // == System - Threading & Synchronisation ===============================

  else if (UnitLow = 'system.syncobjs') or (UnitLow = 'syncobjs') then
    Result := ['tcriticalsection','tmutex','tevent','tsemaphore',
               'tconditionvariablecs','tconditionvariablemres',
               'tlightweightevent','tspinlock']

  else if (UnitLow = 'system.messaging') or (UnitLow = 'messaging') then
    Result := ['tmessagemanager','tmessage','tmsgreceivedevent',
               'tmessagelistener','tmsgsendoreceive']

  else if (UnitLow = 'system.actions') or (UnitLow = 'actions') then
    Result := ['tactionlist','tcustomactionlist','tbasicaction',
               'tcommonactionlink']

  // == System - Netzwerk & Internet =======================================

  else if (UnitLow = 'system.net.urlclient') then
    Result := ['turlclient','turlrequest','turlresponse',
               'tnamevaluepair','tproxysettings','turlscheme']

  else if (UnitLow = 'system.net.mime') then
    Result := ['tmultipartformdata','tmimepart','tformfield']

  else if (UnitLow = 'system.net.httpclientcomponent') then
    Result := ['tnethttpclient','tnethttprequest']

  // == REST / JSON ========================================================

  else if (UnitLow = 'rest.client') then
    Result := ['trestclient','trestrequest','trestresponse',
               'trestcomponent','tauthenticator']

  else if (UnitLow = 'rest.types') then
    Result := ['trestoption','trestcontenttype','trequestparamkind',
               'trestresponsedatatype']

  else if (UnitLow = 'rest.response.adapter') then
    Result := ['trestresponsedatasetadapter','tjsontoobjectadapter']

  else if (UnitLow = 'rest.json') or (UnitLow = 'rest.json.types') then
    Result := ['tjson','tsjsonserializer','tjsonserialize',
               'tjsonunmarshal','tjsonmarshal']

  else if (UnitLow = 'rest.authenticator.oauth') then
    Result := ['toauth1authenticator','toauth2authenticator',
               'toauthaccesstokentype']

  // == Indy (Internet Direct) =============================================

  else if (UnitLow = 'idhttp') then
    Result := ['tidhttp','tidhttprequestinfo','tidhttpresponseinfo',
               'tidcookiemanager']

  else if (UnitLow = 'idtcpclient') or (UnitLow = 'idtcp') then
    Result := ['tidtcpclient','tidtcpserver','tidcontext']

  else if (UnitLow = 'idsmtp') then
    Result := ['tidsmtp','tidmessage','tidattachment']

  else if (UnitLow = 'idftp') then
    Result := ['tidftp','tidftpdirectoryentry']

  else if (UnitLow = 'idpop3') then
    Result := ['tidpop3']

  else if (UnitLow = 'idssliopensslheaders') or
          (UnitLow = 'idssl') or
          (UnitLow = 'idsslopenssl') then
    Result := ['tidssliohandlersocketopenssl','tidsslopenssl']

  else if (UnitLow = 'idiohandler') or (UnitLow = 'idiohandlerstack') then
    Result := ['tidiohandler','tidiohandlerstack','tidiohandlersocket']

  // == FireMonkey (FMX) ===================================================

  else if (UnitLow = 'fmx.types') then
    Result := ['tfmxobject','talignlayout','talign','trotation',
               'tnativeuint','tfmxcontrol']

  else if (UnitLow = 'fmx.controls') then
    Result := ['tcontrol','tcontainercontrol','tstyledcontrol',
               'tcustomcontrol','tgraphiccontrol','tinteractiveobject']

  else if (UnitLow = 'fmx.forms') then
    Result := ['tform','tcommonform','tapplication','tscreen',
               'application','screen','tformstyle','tcloseevent']

  else if (UnitLow = 'fmx.stdctrls') then
    Result := ['tlabel','tbutton','tspeedbutton','tcheckbox',
               'tradiobutton','tgroupbox','tswitch','ttrackbar',
               'tprogressbar','tscrollbar','tsegmentedcontrol',
               'texpander','tcaption','tstatusbar']

  else if (UnitLow = 'fmx.edit') then
    Result := ['tedit','tcustomedit','tcleareditbutton',
               'tpasswordedit','tnumedit']

  else if (UnitLow = 'fmx.memo') then
    Result := ['tmemo','tcustommemo']

  else if (UnitLow = 'fmx.combedit') then
    Result := ['tcomboedit']

  else if (UnitLow = 'fmx.listbox') then
    Result := ['tlistbox','tlistboxitem','tlistboxgroup',
               'tlistboxscrollbar','tcustomlistbox']

  else if (UnitLow = 'fmx.listview') then
    Result := ['tlistview','tlistviewitem','tlistviewitemappearance',
               'tlistviewappearance','tlistitem']

  else if (UnitLow = 'fmx.treeview') then
    Result := ['ttreeview','ttreeviewitem']

  else if (UnitLow = 'fmx.tabcontrol') then
    Result := ['ttabcontrol','ttabitem']

  else if (UnitLow = 'fmx.layouts') then
    Result := ['tlayout','tscaledlayout','tgridlayout','tflowlayout',
               'twraplayout','tvertscrollbox','thorzscrollbox',
               'tscrollbox','tframedscrollbox']

  else if (UnitLow = 'fmx.objects') then
    Result := ['trectangle','tcircle','tellipse','tline','tpath',
               'timage','ttext','tselectionpoint','tcalloutrectangle']

  else if (UnitLow = 'fmx.grid') then
    Result := ['tgrid','tstringgrid','tcolumn','tstringcolumn',
               'tcheckcolumn','tnumbercolumn','tpopupcolumn']

  else if (UnitLow = 'fmx.dialogs') then
    Result := ['showmessage','messagedlg','inputbox','inputquery',
               'topendialog','tsavedialog','tmessagedialog']

  else if (UnitLow = 'fmx.graphics') then
    Result := ['tbitmap','tcanvas','tfill','tstroke','tfont',
               'tbitmapdata','tcolor','talphacolor','talphacolorrec',
               'tgradient','tgradientpoint','tbitmapsurface']

  else if (UnitLow = 'fmx.media') then
    Result := ['tmediaplayer','tcapturesetting','tmicrophonecapturedevice',
               'tcapturedevice','tvideocapturedevice']

  else if (UnitLow = 'fmx.maps') then
    Result := ['tmapview','tmaplocation','tmapdescriptor']

  else if (UnitLow = 'fmx.ani') then
    Result := ['tanimation','tfloatanimation','tcoloranimation',
               'tpathanimation','tbitmapanimation','tintanimation',
               'tanimator']

  else if (UnitLow = 'fmx.effects') then
    Result := ['teffect','tshadoweffect','tgloweffect','tblureffect',
               'treflectioneffect','tembosseffect']

  else if (UnitLow = 'fmx.multiview') then
    Result := ['tmultiview']

  else if (UnitLow = 'fmx.calendars') then
    Result := ['tcalendarview','tdatepicker']

  // == Winapi - weitere Einheiten =========================================

  else if (UnitLow = 'winapi.winsock2') or (UnitLow = 'winsock2') then
    Result := ['tsocket','twsadata','tfd_set','tsockaddr',
               'wsastartup','wsacleanup','gethostbyname']

  else if (UnitLow = 'winapi.tlhelp32') or (UnitLow = 'tlhelp32') then
    Result := ['tprocessentry32','tthreadentry32','tmoduleentry32',
               'createtoolhelp32snapshot','process32first','process32next']

  else if (UnitLow = 'winapi.psapi') or (UnitLow = 'psapi') then
    Result := ['tmoduleinfo','enumprocesses','enumprocessmodules',
               'getmodulefilename','getprocessmemoryinfo']

  else if (UnitLow = 'winapi.wininet') or (UnitLow = 'wininet') then
    Result := ['tinternethandle','internetopen','internetconnect',
               'httpsendrequesta','internetclosehandle']

  else if (UnitLow = 'winapi.activex') or (UnitLow = 'activex') then
    Result := ['iunknown','idispatch','tguid','ioleinplaceobject',
               'ioleobject','ioleclientsite','olecheck',
               'createcomobject','cogettypes']

  else if (UnitLow = 'winapi.taskschd') or (UnitLow = 'taskschd') then
    Result := ['itaskscheduler','itaskservice','itask',
               'itaskfolder','itasktrigger']

  else if (UnitLow = 'winapi.gdiplusgraphics') or
          (UnitLow = 'gdiplusapi') then
    Result := ['tgdiplus','tgraphics','tbitmap','tpen','tbrush',
               'tstringformat','tfont']

  // == IBX / InterBase ====================================================

  else if (UnitLow = 'ibx.ibdatabase') or (UnitLow = 'ibdatabase') then
    Result := ['tibdatabase','tibtransaction','tibsql']

  else if (UnitLow = 'ibx.ibquery') or (UnitLow = 'ibquery') then
    Result := ['tibquery','tibstoredproc']

  else if (UnitLow = 'ibx.ibsql') or (UnitLow = 'ibsql') then
    Result := ['tibsql','tibsqltype','tibxsqlvar']

  // == DBX / SQLExpress ===================================================

  else if (UnitLow = 'data.dbxcommon') or (UnitLow = 'dbxcommon') then
    Result := ['tsqlconnection','tsqlquery','tsqldataset',
               'tsqlstoredproc','tsqlmonitor']

  // == Sonstige ===========================================================

  // 'tthermemanager' stand hier und war tot; die naheliegende Korrektur
  // 'tthememanager' ist es ebenfalls (0 Korpustreffer). Entfernt statt
  // geraten. Die real haeufigen Vcl.Themes-Bezeichner waeren
  // TStyleManager (728 Korpustreffer) und TCustomStyleServices (233) -
  // die AUFZUNEHMEN ist aber keine Tippfehler-Korrektur mehr, sondern
  // eine Whitelist-Erweiterung mit rund 200 betroffenen Dateien. Eigener
  // Posten, eigene Messung (Voll-Review 2026-09-12, Major 90). Der
  // Vcl.Styles-Zweig direkt darunter fuehrt 'tstylemanager' bereits -
  // ein Grund mehr, die beiden Listen bewusst und nicht nebenbei
  // anzugleichen.
  //
  // PAKET 9003 UMGESETZT (2026-09-15): die zwei Namen sind jetzt drin.
  // Es ist eine reine ERGAENZUNG, und die kann per Konstruktion keine
  // neuen Funde erzeugen - ein zusaetzlicher Whitelist-Eintrag liefert
  // nur weitere Verwendungsnachweise, also hoechstens WENIGER Funde.
  // Gemessen (Nachbildung mit Ein-Zweig-IFDEF-Sicht, gegen alle 40
  // Fixturen aus uTestUnusedUses validiert): rund 124 Drops, 0 Adds.
  //
  // NICHT MITGEMACHT, obwohl es naheliegt: 'tstylemanager' aus dem
  // Vcl.Styles-Zweig darunter zu ENTFERNEN. Das erzeugt 4 Adds, und
  // einer davon ist beweisbar falsch - der Zweig wird ueber den
  // Kurznamen-Fallback KnownIdents(ShortLow) (:793) AUCH fuer
  // FMX.Styles gezogen, und FMX.Styles deklariert ein eigenes
  // 'TStyleManager = class sealed'. python4delphi
  // Source/fmx/WrapFmxStyles.pas nutzt genau dieses und haette keinen
  // anderen Nachweis: heute korrekt stumm, nach der Entfernung ein
  // Fehlfund. Die Doppelfuehrung sieht nach Redundanz aus und ist
  // keine.
  //
  // ACHTUNG BEIM NACHMESSEN: im CLI ist diese Regel ABGESCHALTET (siehe
  // Kopfkommentar). Der Referenzlauf zeigt 0 Funde und 0 Bewegung -
  // wer die 124 sehen will, muss ueber Form-GUI oder IDE-Plugin messen.
  //
  // OFFEN, gemessen aber nicht umgesetzt: 'styleservices' (die Funktion
  // aus Vcl.Themes) soll laut Messung der wirksamste fehlende Eintrag
  // ueberhaupt sein. Nicht mit aufgenommen, weil diese Zahl nur aus
  // einer Nachbildung stammt und nicht gegengeprueft ist - eigener
  // Posten, eigene Messung.
  else if (UnitLow = 'vcl.themes') or (UnitLow = 'themes') then
    Result := ['tthemeservices','tstylemanager','tcustomstyleservices']

  else if (UnitLow = 'vcl.styles') or (UnitLow = 'styles') then
    Result := ['tthemeservices','tstylecollection','tstylemanager']

  else if (UnitLow = 'vcl.platformvcl') or
          (UnitLow = 'vcl.platformvclstyles') then
    Result := ['tplatformvclstylesservice']

  else if (UnitLow = 'fmx.platform') then
    Result := ['iinterface','ifdtextinput','ifontmanager',
               'imultitouch','igenericplatformservice']

  else if (UnitLow = 'system.bluetooth') then
    Result := ['tbluetooth','tbluetoothdevice','tbluetoothle',
               'tbluetoothgattcharacteristic','tbluetoothmanager']

  else if (UnitLow = 'system.sensors') or
          (UnitLow = 'system.sensors.components') then
    Result := ['tsensormanager','tsensor','taccelerometersensor',
               'tgyroscopesensor','tlocationsensor',
               'tlocationsensorcomponent']

  else if (UnitLow = 'system.notification') then
    Result := ['tnotificationcenter','tnotification',
               'tnotificationpresentation']

  else if (UnitLow = 'system.tether.manager') or
          (UnitLow = 'system.tether.appprofile') then
    Result := ['ttetheringmanager','ttetheringappprofile',
               'ttetheringresource']

  else if (UnitLow = 'system.pushnotification') then
    Result := ['tpushserviceconnection','tpushservice',
               'tpushnotificationservice'];
end;

class function TUnusedUsesDetector.IdentsFor(
  const UnitLow: string): TArray<string>;
// Vertrag siehe Deklaration. Der Rueckfall bleibt an IstRtlNamespace
// gebunden - dort steht das WARUM (Alcinoe-FP der C-Charge).
// Charge P1 (2026-10-25): fuer einen dotless Namen ist der Kurzname der
// Name selbst - der zweite Durchlauf durch die else-if-Kette lieferte
// dann dasselbe leere Ergebnis noch einmal und entfaellt.
var
  Kurz : string;
begin
  Result := KnownIdents(UnitLow);
  if (Length(Result) = 0) and IstRtlNamespace(UnitLow) then
  begin
    Kurz := ShortName(UnitLow);
    if Kurz <> UnitLow then
      Result := KnownIdents(Kurz);
  end;
end;

{ ---- Oeffentliche API ---- }

class procedure TUnusedUsesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  UsesItems  : TList<TAstNode>;
  RawSB      : TStringBuilder;
  RawText    : string;   // lowercase mit Punkten: fuer H1 und H2
  Punkte     : TArray<Integer>;                // H1, lazy
  PunkteDa   : Boolean;
  Woerter    : TDictionary<string, Boolean>;   // H2, lazy: Id -> ist Wort
  Bedarf     : TList<string>;
  Da         : TArray<Boolean>;
  ItemIdx, j : Integer;
  Reported   : TDictionary<string, Boolean>;
  Item       : TAstNode;
  UnitLow    : string;
  ShortLow   : string;
  Found      : Boolean;
  F          : TLeakFinding;
  SrcLines   : TStringList;
  SrcCached  : Boolean;
  LineFor    : TArray<Integer>;
  Gestript   : string;
begin
  RawSB  := TStringBuilder.Create;
  try
    // Perf Charge Q5: AST-Teil mit EINEM ToLower (Vertrag an AstSuchtext).
    RawSB.Append(AstSuchtext(UnitNode));

    // D4 (2026-09-19, FP-Muster 2 der Recall-Freigabe-Stichprobe):
    // CollectText sieht nur AST-NAMEN (Node.Name/TypeRef) - eine
    // Nutzung, die allein in Rumpf-STATEMENTS lebt (Application.
    // HelpCommand in einer nested procedure, TFieldDataLink.Create,
    // Variant-Zuweisungen), fehlte im Suchtext, und die uses-Zeile
    // wurde trotz Nutzung gemeldet. ADDITIVER Quelltext-Kanal: der
    // kommentar- UND string-gestrippte Dateitext wird an den
    // Suchtext ANGEHAENGT. Strings gestrippt aus derselben Politik,
    // aus der der AST-Weg Literale nie sah: ein Bezeichner IN einem
    // Literal ist kein Verwendungsnachweis. Mehr Suchtext kann Funde
    // nur ENTFERNEN, nie erzeugen - richtungssicher. Ist die Datei
    // nicht lesbar (Test-Harness FindingsOf mit Platzhalter-Namen),
    // bleibt es still beim AST-Text - die Bestandsfixturen behalten
    // ihren Vertrag, und genau dafuer ist der Kanal ADDITIV statt
    // ersetzend.
    //
    // MIT Scan-Kontext seit Charge P1 (2026-10-25; Review 2026-10-13
    // hatte den Umstieg vorgemerkt): registriert ueber AddD, Zeilen aus
    // CtxFileTextCache (im Scan dasselbe Objekt wie der Prozess-Cache,
    // uStaticAnalyzer2: Ctx.FileTextCache := gFileTextCache) und der
    // Strip aus dem Strip-Slot des Kontexts - derselbe
    // StripStringsAndComments(Lines, '~'), den die anderen Ganztext-
    // Detektoren dieser Datei schon gerechnet haben. Ohne Kontext (nil)
    // rechnet der Detektor selbst, mit derselben Antwort.
    SrcLines := AcquireLines(FileName, SrcCached, CtxFileTextCache(AContext));
    if SrcLines <> nil then
    try
      Gestript := TDetectorUtils.StripStringsAndCommentsCached(
        SrcLines, LineFor, AContext, FileName).ToLower;
      // F3 (2026-09-19): uses-Klauseln liefern keinen Nachweis -
      // Vertrag und FN-Muster an der Deklaration von BlankeUsesKlauseln.
      BlankeUsesKlauseln(Gestript);
      RawSB.Append(' ');
      RawSB.Append(RawSicht(Gestript));
      RawSB.Append(' ');
    finally
      ReleaseLines(SrcLines, SrcCached);
    end;

    RawText := RawSB.ToString;
  finally
    RawSB.Free;
  end;

  PunkteDa  := False;
  Woerter   := nil;
  Reported  := TDictionary<string, Boolean>.Create;
  UsesItems := UnitNode.FindAll(nkUsesItem);
  try
    for ItemIdx := 0 to UsesItems.Count - 1 do
    begin
      Item     := UsesItems[ItemIdx];
      UnitLow  := Item.Name.ToLower;
      ShortLow := ShortName(UnitLow);

      // Duplikate (gleiche Unit in Interface + Implementation) einmal melden
      if Reported.ContainsKey(UnitLow) then Continue;

      if IsAlwaysNeeded(UnitLow)  then Continue;
      if IsAlwaysNeeded(ShortLow) then Continue;

      Found := False;

      // -- H1: Qualifizierter Bezeichner ('sysutils.' im Raw-Text) --------
      // = Pos(ShortLow + '.', RawText) > 0 oder Pos(UnitLow + '.', ...)
      // (Vertrag an PraefixVorPunkt), ohne Durchlauf je Praefix.
      if not PunkteDa then
      begin
        Punkte   := PunktPositionen(RawText);
        PunkteDa := True;
      end;
      if PraefixVorPunkt(RawText, Punkte, ShortLow) or
         PraefixVorPunkt(RawText, Punkte, UnitLow) then
        Found := True;

      // -- H2: Bekannte Bezeichner als ganzes Wort -------------------------
      if not Found then
      begin
        // Kurznamen-Fallback NUR fuer RTL-Namespaces (C-Charge
        // 2026-09-19): eine fremde Unit wie 'Alcinoe.FMX.StdCtrls'
        // fiele sonst auf die VCL-'stdctrls'-Identliste zurueck und
        // wuerde trotz Nutzung ihrer EIGENEN Typen gemeldet - das
        // FP-Muster 1 der Recall-Freigabe-Stichprobe. Vertrag und
        // Rueckfall stehen in IdentsFor.
        var Idents := IdentsFor(UnitLow);

        // Unbekannte Unit (kein Mapping): Verwendung nicht bestimmbar.
        // Ohne Mapping wuerden alle unbekannten Units faelschlich als unused
        // gemeldet -> lieber false negative als false positive.
        if Length(Idents) = 0 then Continue;

        // Einmal je Datei: fuer die Bezeichner dieses und aller folgenden
        // Eintraege, ob sie ein Wort des Suchtexts sind (Vertrag an
        // WoerterVorhanden = SammleWoerter-Menge). Perf Charge Q5: statt
        // ALLE Woerter der Datei zu kopieren und zu hashen (Charge P1)
        // nur noch die wenigen gefragten - IdentsFor ist rein, jedes
        // spaeter gefragte Id steht damit in der Tabelle.
        if Woerter = nil then
        begin
          Bedarf := TList<string>.Create;
          try
            for j := ItemIdx to UsesItems.Count - 1 do
              Bedarf.AddRange(IdentsFor(UsesItems[j].Name.ToLower));
            Da := WoerterVorhanden(RawText, Bedarf.ToArray);
            Woerter := TDictionary<string, Boolean>.Create;
            for j := 0 to Bedarf.Count - 1 do
              Woerter.AddOrSetValue(Bedarf[j], Da[j]);
          finally
            Bedarf.Free;
          end;
        end;

        for var Id in Idents do
        begin
          var IstWort : Boolean;
          if Woerter.TryGetValue(Id, IstWort) and IstWort then
          begin
            Found := True;
            Break;
          end;
        end;
      end;

      if Found then Continue;

      // H1 und H2 haben keine Verwendung gefunden -> melden
      Reported.AddOrSetValue(UnitLow, True);
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Item.Line);
      F.MissingVar := Item.Name;
      F.SetKind(fkUnusedUses);
      Results.Add(F);
    end;
  finally
    UsesItems.Free;
    Reported.Free;
    Woerter.Free;
  end;
end;

end.
