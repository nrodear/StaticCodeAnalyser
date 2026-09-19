unit uDetectorUtils;

// Gemeinsame Helfer fuer Detektoren. Vor allem Pattern-Matching mit echten
// Wortgrenzen statt naivem Pos() - mehrere Detektoren hatten False-Positives
// weil 'sql' auch 'sqlnot' und 'assigned MyVar' auch 'assigned MyVarOld'
// matchen wuerde.
//
// Konvention:
//   - "Lower" als Suffix bedeutet: Aufrufer hat bereits ToLower angewendet,
//     wir sparen die Konvertierung pro Aufruf.
//   - "WholeWord" bedeutet: links und rechts vom Match steht KEIN Identifier-
//     Zeichen (Buchstabe, Ziffer, Underscore, Punkt-Qualifier).

interface

uses
  System.Classes, System.Generics.Collections, // TStrings, TList<>
  System.SysUtils,                             // TStringBuilder und CharInSet
    // CharInSet ist eine Inline-Funktion. Die inline deklarierten Routinen
    // dieser Unit koennen sie nur expandieren, wenn System.SysUtils
    // interface-seitig sichtbar ist - sonst H2445, siehe ParseCallsInExpr.
  uAnalyzeContext,                             // Perf (2026-07-05): P1-strip-cache
  uAstNode;                                    // Hebel A: CollectFfiBindingTypes
    // uAstNode haengt nur an System-Units - kein Zyklus. uAnalyzeContext
    // zieht den Knotentyp ueber uAstFileCache ohnehin schon in die
    // Abhaengigkeits-Huelle dieser Unit.

type
  // Container fuer extrahierte Function-Calls aus Expression-Strings
  // (siehe TDetectorUtils.ParseCallsInExpr).
  TExprCall = record
    FuncNameLow : string;
    ArgsRaw     : string;
  end;

  // Mitgefuehrter Block-Kommentar-Zustand fuer ScanCodeLine. Zeilenstrings
  // und `//`-Zeilenkommentare beginnen/enden IMMER innerhalb einer Zeile -
  // nur `{ ... }` und `(* ... *)` koennen ueber Zeilengrenzen laufen, daher
  // wird nur deren Zustand zwischen ScanCodeLine-Aufrufen getragen.
  // Zeilen-uebergreifender Zustand fuer BlankNonCode: ein '{' oder '(*'
  // kann ueber Zeilengrenzen offen bleiben.
  //
  // Delphi-12-Multi-Line-Strings ('''...''') werden bewusst NICHT
  // getrackt - rare Edge-Case, FN akzeptabel.
  TBlankScanState = record
    InBrace : Boolean;   // True wenn vorige Zeile mit offenem '{' endete
    InParen : Boolean;   // True wenn vorige Zeile mit offenem '(*' endete
  end;

  TCommentScanState = record
    InBraceComment : Boolean;   // innerhalb { ... }
    InParenComment : Boolean;   // innerhalb (* ... *)
  end;

  // === TEST-PFAD-ERKENNUNG: Strenge-Stufe ==============================
  // Fund 3 (Restschulden-Audit 2026-07-26): es gab DREI konkurrierende
  // "ist Testdatei"-Definitionen mit disjunkten Musterlisten, sodass
  // dieselbe Datei je nach Konsument anders bewertet wurde. Die Muster
  // liegen jetzt in EINER Liste (TEST_PATH_RULES, Implementation) und
  // jede Regel traegt die Stufen, in denen sie gilt. Die Stufe steuert
  // NUR die Auswahl aus dieser Liste - nicht mehr eine eigene Kopie.
  //
  //   tplFixture - Post-Filter-Sicht (Console-Runner, uUninitVar):
  //                Test-Files UND Demo-/Sample-/Resources-Fixtures.
  //                Breit, weil dort nur Heuristik-Befunde ausgeblendet
  //                werden. = das bisherige IsTestFixturePath-Verhalten.
  //   tplSecret  - Secret-Sicht (THardcodedSecretDetector): NUR Test-/
  //                Spec-Konventionen. Bewusst ENGER als tplFixture: in
  //                einem Demo-/Sample-File ist ein echtes hardcodiertes
  //                Secret weiterhin meldepflichtig.
  //
  // NICHT hierher gehoert TIgnoreList.IsTestPath (uIgnoreList.pas): das
  // steuert, WAS ueberhaupt gescannt wird - eine Erweiterung dort loescht
  // Funde aus dem Korpus. Bewusst separat gelassen.
  //   tplFixtureDir - wie tplFixture, aber NUR Verzeichnis-Segmente; der
  //                   Dateiname wird ignoriert. Fuer Gates INNERHALB von
  //                   Detektoren gedacht (s. Kommentar bei
  //                   IsTestFixturePath).
  TTestPathLevel = (tplFixture, tplSecret, tplFixtureDir);

  TDetectorUtils = class
     public
      // True, wenn Ch zu einem Identifier gehoert (a..z, 0..9, _).
    // Punkt zaehlt NICHT mit - 'sql' in 'mytable.sql' soll trotzdem als
    // Wortgrenze rechts vom Punkt erkannt werden.
    class function IsIdentChar(Ch: Char): Boolean; static; inline;

    // Erstes Zeichen eines Pascal-Bezeichners (A..Z, a..z, _ - OHNE
    // Ziffern). Voll-Review 2026-09-12: die Klasse stand 15x
    // byte-gleich in den Detektoren (inkl. einer nested Kopie in
    // dieser Unit); jetzt zentral wie IsIdentChar seit der
    // Backlog-Welle 1.
    class function IsIdentStartChar(Ch: Char): Boolean; static; inline;

    // True wenn FileName auf ein bekanntes Test-/Demo-Fixture-Pattern
    // matched. Konsumenten (CLI, IDE-Filter) koennen Findings aus solchen
    // Files optional ausblenden - die enthalten meist absichtliche Bugs
    // fuer Detektor-Tests bzw. Demo-Code mit nicht-produktiven Patterns.
    //
    // SINGLE SOURCE OF TRUTH fuer "ist Testdatei" auf der Auswerte-Seite
    // (Fund 3, Restschulden-Audit 2026-07-26). Alle Muster stehen in
    // TEST_PATH_RULES (Implementation); Level waehlt daraus aus.
    //
    // Level = tplFixture (Default, unveraendertes Alt-Verhalten):
    //   * Basename matched 'uTest*.pas', '*_Test.pas', '*_Tests.pas',
    //     '*TestSuite*.pas', '*Sample.pas', '*Demo.pas', '*_Sample_*.pas',
    //     '*_Demo_*.pas', 'MeineUnit.pas', '*Demo.dfm'
    //   * Pfad-Segment ist 'test', 'tests', 'unittest', 'unittests',
    //     'samples', 'demos', 'resources'
    // Level = tplSecret (THardcodedSecretDetector):
    //   * Basename matched 'uTest*.pas', '*test.pas', '*tests.pas',
    //     '*testu.pas', '*testsu.pas', '*spec.pas'
    //   * Pfad-Segment ist 'test', 'tests', 'spec', 'fixtures', 'utest',
    //     'utests' bzw. beginnt mit 'unittest'
    //   KEINE Demo-/Sample-Muster: ein echtes Secret in einer Demo-Unit
    //   bleibt meldepflichtig.
    //
    // Pfad-Anchoring: mit BaseDir werden NUR Segmente RELATIV zu BaseDir
    // geprueft - so wird '/test/' in einem externen Repo-Pfad wie
    // 'D:\projects\company-tests\src\auth.pas' nicht mehr als Fixture
    // erkannt. Ohne BaseDir gilt die konservative Substring-Suche mit
    // diesem dokumentierten Caveat.
    //
    // Komplementaer zu TIgnoreList.IsTestPath (uIgnoreList.pas): das ist
    // der SCAN-EXCLUSION-Mechanismus (entscheidet, was ueberhaupt geparst
    // wird) und bleibt bewusst getrennt - siehe Kommentar dort.
    class function IsTestFixturePath(const FileName: string;
      const BaseDir: string = '';
      Level: TTestPathLevel = tplFixture): Boolean; static;

    /// <summary>
    ///   Engste gemeinsame Wurzel einer Dateiliste - oder '', wenn es
    ///   keine belastbare gibt (leere Liste, Cross-Drive, Ergebnis
    ///   waere die Laufwerkswurzel).
    /// </summary>
    /// <remarks>
    ///   Anker fuer IsTestFixturePath auf Stufe tplFixtureDir: nur
    ///   Segmente UNTERHALB der Scanwurzel duerfen als Testverzeichnis
    ///   zaehlen. Ohne Anker lief das Gate als Substring ueber den
    ///   ganzen Absolutpfad und legte fuer ein Produktionsrepo unter
    ///   C:/Users/test/... die gategebundenen Detektoren still.
    ///
    ///   Verwandt, aber bewusst NICHT geteilt: uEngineApi hat ein
    ///   lokales CommonRootOf mit anderer Fallback-Semantik (Verzeichnis
    ///   der Projektdatei) fuer Export-Pfade/IndexRoot. Hier ist ''
    ///   der richtige Fehlwert - er heisst 'kein Anker moeglich', und
    ///   der Aufrufer behaelt dann das dokumentierte Alt-Verhalten.
    /// </remarks>
    class function CommonDirOf(AFiles: TStrings): string; static;

    // Vergleicht Datei-Pfade case-insensitiv und mit normalisierten
    // Trennern: der kuerzere Pfad muss ein Suffix des laengeren sein,
    // AN EINER TRENNERGRENZE (sonst waere 'D:/xsrc/uMain.pas' gleich
    // 'src/uMain.pas'). Fehlt einer Seite jeder Verzeichnisanteil,
    // bleibt es beim Basisnamen-Vergleich. D1-Umzug 2026-09-19 aus
    // TExporter (dort bleibt eine Delegation): der Vergleich ist
    // Querschnitt fuer Infrastructure UND Output. Historie und
    // ExtractFileName-Falle im Implementations-Kommentar.
    class function SameSourceFile(const A, B: string): Boolean; static;

    // Sucht Needle in Haystack, beide bereits lower-case, mit Wortgrenzen-
    // Pruefung links UND rechts. Liefert 1-basierte Position oder 0.
    // Beispiele:
    //   FindWholeWordLower('sql', '.sqlnot') -> 0  (rechts steht 'n')
    //   FindWholeWordLower('sql', 'my.sql=') -> 4  (rechts steht '=')
    //   FindWholeWordLower('assigned x', 'assigned xa') -> 0
    class function FindWholeWordLower(const Needle, HaystackLower: string)
      : Integer; overload; static;

    // Wie oben, Suche ab AFrom (1-basiert; AFrom < 1 liefert 0 -
    // Kontrakt der WortPosAb-Kopie aus uCommentedOutCode, deren
    // Hebung diese Overload ist; Voll-Review 2026-09-12).
    class function FindWholeWordLower(const Needle, HaystackLower: string;
      AFrom: Integer): Integer; overload; static;


    // True, wenn Needle als ganzes Wort in HaystackLower vorkommt.
    class function ContainsWholeWordLower(const Needle, HaystackLower: string)
      : Boolean; static; inline;

    // Wie FindWholeWordLower, aber die Wortgrenzen-Pruefung erfolgt nur an
    // den Seiten, an denen das Needle selbst auf einem Identifier-Zeichen
    // endet/beginnt. Damit matchen Tokens mit fuehrender/abschliessender
    // Interpunktion korrekt:
    //   FindTokenBoundedLower('.text', 'edpath.text')      -> 7   (links '.', rechts Ende)
    //   FindTokenBoundedLower('.text', 'mediatype.text_a') -> 0   (rechts '_' = Ident)
    //   FindTokenBoundedLower('paramstr(', 'x:=paramstr(0)')-> 4   (rechts '(' = Non-Ident)
    // Beide Argumente muessen bereits lower-case sein.
    class function FindTokenBoundedLower(const Needle, HaystackLower: string)
      : Integer; static;

    // ENTFERNT Pascal-String-Literale aus einem Ausdrucks-Text - die
    // Zeichen fallen WEG, alle Positionen dahinter VERSCHIEBEN sich.
    // Pascal escaped einfache Apostrophe in Strings durch Verdoppelung
    // (`'don''t'`), aber der Parser-AST hat sie bereits als zusammenhaengen-
    // den Literal-Token konsumiert; die Funktion arbeitet daher auf einer
    // Toggle-Logik: jedes Apostrophe schaltet "in-string"-Modus um.
    // Verwendet von Detektoren, die nach Operator-Pattern (z.B. `= nil`,
    // `IfThen(...,A(),B())`) suchen und dabei Treffer in String-Literalen
    // ('= nil als String') ausschliessen muessen.
    //
    // ACHTUNG - NAMENSFALLE (Fund 4, Restschulden-Audit 2026-07-26):
    // Das Gegenstueck BlankStringLiterals (siehe unten) heisst fast gleich,
    // tut aber das GEGENTEIL beim Layout: es ERHAELT die Laenge. Wer einen
    // Aufruf blind gegen den anderen tauscht, bekommt still falsche
    // Zeilen-/Spalten-Rueckrechnungen. Auswahlregel:
    //   Positionen egal (reine Pos()-Suche im Ergebnis) -> diese Funktion
    //   Positionen zaehlen (Spalten/Offsets)            -> BlankStringLiterals
    class function StripStringLiterals(const S: string): string; static;

    // --- Weitere Fundstellen EINER Duplikat-Gruppe (SCA015/SCA021) ----
    // Baut den Inhalt von TLeakFinding.RelatedLines: aufsteigende,
    // komma-getrennte Zeilennummern OHNE die Ankerzeile (die steht schon
    // in LineNumber) und ohne Wiederholungen. Genau EIN Formatierer fuer
    // beide Detektoren, damit die Anzeige nur ein Format kennen muss.
    class function JoinSitesExceptAnchor(ASites: TList<Integer>;
      AAnchor: Integer): string; static;

    // Deckel fuer RelatedLines - GEMEINSAM fuer SCA015 und SCA021,
    // damit beide dasselbe Versprechen geben. Die Anzeige zeigt nur
    // die ersten paar Nummern; die exakte Gesamtzahl steht im
    // Meldetext ('26x' bzw. 'appears 3x').
    const MAX_RELATED_SITES = 50;

    // POSITIONSERHALTENDE Schwester von StripStringLiterals: ersetzt jedes
    // Zeichen ZWISCHEN einfachen Anfuehrungszeichen durch ein Leerzeichen
    // (inkl. ''-Escape-Handling), laesst die Quotes selbst stehen. Laenge
    // und damit JEDE Zeichenposition bleiben 1:1 erhalten.
    //
    // Fuer Detektoren, die Match-Positionen auf Spalten/Offsets der Quelle
    // zurueckrechnen (uDivByZero) - dort waere das entfernende
    // StripStringLiterals ein stiller Positions-Versatz.
    // Hochgezogen aus uDivByZero (Fund 4, Restschulden-Audit 2026-07-26);
    // die Kopien waren namensgleich, aber semantisch gegensaetzlich.
    class function BlankStringLiterals(const S: string): string; static;

    // Splittet einen Argumentlisten-Text an TOP-LEVEL-Kommas: nested
    // Parens und String-Literale werden respektiert.
    // 'cond, a, b' -> ['cond', ' a', ' b'] (Teile UNGETRIMMT, wie die
    // Ursprungsfassung).
    // Zentralisiert aus uIfThenShortCircuit (Voll-Review 2026-09-12,
    // Posten 71: dritte Kopie stand an - uInheritedMethodEmpty braucht
    // denselben Split fuer den 1:1-Durchreichungs-Vergleich). NICHT
    // verwechseln mit uLeakDetector2.SinkSplitTopLevelArgs - der
    // Balancierer dort hat einen eigenen, dokumentierten Vertrag
    // (Namensvetter, bewusst getrennt).
    class function SplitTopLevelArgs(const Args: string): TArray<string>; static;

    // Kuerzt S auf hoechstens AMaxUnits UTF-16-Code-Units, OHNE ein
    // Surrogatpaar zu durchschneiden: endet der Schnitt auf einem
    // High-Surrogat (erste Haelfte eines non-BMP-Zeichens, z. B. Emoji),
    // faellt auch dieses weg - ein blankes Copy(S,1,N) liesse sonst
    // kaputtes UTF-16 im Meldetext zurueck (Prueferbefund 2026-09-15:
    // acht Abschnitt-Stellen in fuenf Detektoren). Gleiche Zusicherung
    // wie Crop in uFindingCopyText (Jira-Befund). Die Ellipse haengt
    // der Aufrufer an - ihre Form ist je Detektor verschieden.
    class function TruncateSurrogateSafe(const S: string;
      AMaxUnits: Integer): string; static;

    // === ZEILEN-SCANNER (Strings + Kommentare) =========================
    // Single source of truth fuer die String-/Kommentar-Zustandsmaschine.
    // Frueher hatten uFloatEquality und uNoSonarMarker je eine eigene Kopie
    // mit subtilen Abweichungen - jede Abweichung = potenzieller
    // False-Positive (Match im String-Literal / Kommentar).

    // Verarbeitet GENAU EINE Zeile. Liefert den Code-Anteil zurueck, wobei:
    //   * String-Literal-Inhalte (inkl. der Quotes) durch FillCh ersetzt
    //     werden - Position bleibt erhalten, aber `\w`/`\s`-Regex matchen
    //     nicht mehr ueber den Ex-String hinweg (Default '~': weder \w noch \s).
    //   * `{ ... }` / `(* ... *)`-Kommentar-Inhalte ENTFERNT werden.
    //   * bei einem `//`-Zeilenkommentar der Rest der Zeile abgeschnitten und
    //     LineCommentCol auf die 1-basierte Spalte des ersten `/` gesetzt wird
    //     (0 wenn kein Zeilenkommentar).
    // State traegt offene `{`/`(*`-Bloecke ueber Zeilengrenzen.
    // Ersetzt JEDES Nicht-Code-Zeichen einer Zeile durch ein LEERZEICHEN -
    // Kommentarinhalte ('//', '{..}', '(*..*)') ebenso wie String-Literale
    // samt ihrer Apostrophe. Die Zeilenlaenge bleibt dabei erhalten, jede
    // Spalte zeigt weiterhin auf dieselbe Quellspalte.
    //
    // Unterschied zu ScanCodeLine: die ENTFERNT Klammerkommentare und
    // schneidet Zeilenkommentare ab, verschiebt also Positionen. Wer nach
    // dem Strippen noch mit Spalten rechnet - Klammertiefe, Wortgrenzen,
    // Label-Erkennung - braucht diese Variante.
    //
    // 2026-08-21 aus uUninitVar hierher gezogen (Code-Review-Rest 12).
    // Der Posten verlangte woertlich eine Erweiterung von ScanCodeLine um
    // einen Fuell-Modus; das haette eine Verzweigung in deren Zeilen-
    // schleife bedeutet, die pro Quellzeile pro Strip laeuft und einen
    // eigenen Perf-Kommentar traegt. Der Ortswechsel erreicht dasselbe
    // Ziel - eine Implementierung statt mehrerer - ohne den Hot-Path
    // anzufassen und ohne ein A/B zu brauchen.
    class function BlankNonCode(const Line: string;
      var State: TBlankScanState): string; static;

    // AKeepColumns: Inline-Kommentare werden mit FillCh AUSGEFUELLT statt
    // entfernt, der Rueckgabewert ist dann spaltengleich zur Eingabe.
    // BEWUSST opt-in und NICHT Vorgabe: 40 Units lesen diesen Helfer, und
    // mindestens uNestedRoutines verlaesst sich schriftlich auf das
    // Gegenteil (dort :223 - "Kommentare sind ENTFERNT"). Gemessen an
    // rw29 kostete die Umstellung als Vorgabe 506 SCA102-Funde, darunter
    // nachweislich echte (Alcinoe.FMX.Dialogs.pas verlor alle neun,
    // obwohl die geschachtelte Routine dort steht). Wer Spalten braucht,
    // fordert sie an - s. uQuickFix.CodeOnly.
    class function ScanCodeLine(const Line: string; var State: TCommentScanState;
      out LineCommentCol: Integer; FillCh: Char = '~';
      AKeepColumns: Boolean = False): string; static;

    // Strippt Strings + Kommentare ueber den GESAMTEN Quelltext (Mehrzeilen-
    // Bloecke korrekt). Ergebnis ist EIN String, Zeilen mit #10 getrennt.
    // LineForChar[k] liefert den 0-basierten Quell-Zeilenindex des Zeichens
    // Result[k+1] - damit kann ein Detektor von einer Match-Position im
    // gestrippten Text auf die Quellzeile zurueckrechnen.
    class function StripStringsAndComments(Lines: TStrings;
      out LineForChar: TArray<Integer>; FillCh: Char = '~'): string; static;

    // Perf (2026-07-05): P1-strip-cache - wie StripStringsAndComments, aber
    // mit per-Scan-Cache im TAnalyzeContext (Key = FileName + FillCh).
    // RunAllDetectors laesst alle Detektoren nacheinander ueber DIESELBE
    // Datei laufen - die ~16 Ganztext-Strip-Aufrufer teilen sich so EIN
    // Ergebnis pro FillCh-Variante statt jeder selbst zu strippen.
    // AContext = nil -> exakt heutiges Verhalten (direkt rechnen, kein
    // Cache; Tests/Single-File-Modus).
    class function StripStringsAndCommentsCached(Lines: TStrings;
      out LineForChar: TArray<Integer>; AContext: TAnalyzeContext;
      const FileName: string; FillCh: Char = '~'): string; static;

    // Perf P7 (Konzept_Performance25, 2026-07-19): string-ERHALTENDER
    // Kommentar-Strip - Strings bleiben verbatim (inkl. ''-Escape),
    // //-, {..}- und (*..*)-Kommentare (auch {$-Direktiven) werden
    // ERSATZLOS entfernt, pro Quellzeile genau ein #10, LineForChar =
    // 0-basierter Quellzeilen-Index pro Ergebnis-Zeichen.
    // Byte-identische Zentralisierung der bis dahin in 9 Detektoren
    // kopierten lokalen StripFileComments-Routine (uPerfHotspots-Familie;
    // MD5-Beweis der Zwillinge, siehe Konzept §6-Follow-up). NICHT
    // verwechseln mit StripStringsAndComments (blankt Strings mit FillCh).
    class function StripFileCommentsKeepStrings(Lines: TStrings;
      out LineForChar: TArray<Integer>): string; static;

    // Cached-Variante analog StripStringsAndCommentsCached, eigener
    // Ein-Datei-Slot im Context (TryGetKeepStringsText). AContext=nil ->
    // direkt rechnen (Tests/Single-File).
    class function StripFileCommentsKeepStringsCached(Lines: TStrings;
      out LineForChar: TArray<Integer>; AContext: TAnalyzeContext;
      const FileName: string): string; static;

    /// <summary>True, wenn APos INNERHALB eines Pascal-String-Literals
    /// liegt.</summary>
    /// <remarks>
    ///   Pflichtpruefung fuer JEDEN Detektor auf
    ///   StripFileCommentsKeepStrings: der Strip laesst Literale
    ///   ABSICHTLICH stehen (uInterfaceGuid braucht die GUID, die als
    ///   Literal in eckigen Klammern steht). Damit steht aber auch jedes
    ///   andere Pascal in Strings noch da - Testfixtures, Hint-Beispiele,
    ///   Code-Generator-Vorlagen.
    ///
    ///   Gemessen am 2026-08-25 im eigenen tests-Verzeichnis:
    ///   EmptyInterface 6 von 6 Funden, RedundantConditional 3 von 3,
    ///   IfElseBegin 1 von 1 - alles Text aus Fixtures.
    ///
    ///   Gezaehlt werden Anfuehrungszeichen ab Zeilenanfang; ein
    ///   Pascal-Literal endet spaetestens am Zeilenende. Das verdoppelte
    ///   '' innerhalb eines Literals zaehlt als zwei und laesst die
    ///   Paritaet unveraendert - richtig, es steht ja weiter drin.
    /// </remarks>
    class function InStringLiteral(const ACode: string;
      APos: Integer): Boolean; static;

    // Rueckrechnung Match-Position -> 1-basierte Quellzeile ueber die
    // LineForChar-Map aus StripStringsAndComments (dort: 0-basierter
    // Zeilenindex pro Zeichen). 0 wenn APos ausserhalb der Map liegt.
    // Audit 2026-07: war in 17 Detektor-Units byte-identisch kopiert -
    // hier zentralisiert (Konsumenten rufen TDetectorUtils.LineForPos).
    class function LineForPos(const LineFor: TArray<Integer>;
      APos: Integer): Integer; static;

    // === QUALIFIZIERTE NAMEN ==========================================
    // Letztes Segment eines gepunkteten Bezeichners:
    //   'TFoo.Bar'           -> 'Bar'
    //   'TOuter.TInner.DoIt' -> 'DoIt'   (nested type: der LETZTE Punkt zaehlt)
    //   'Bar'                -> 'Bar'    (kein Punkt -> unveraendert)
    //   'TFoo.'              -> ''       (Punkt am Ende -> leeres Segment)
    //   ''                   -> ''
    //
    // Restschulden-Audit 2026-07-26: die Routine war in ACHT Detektoren
    // lokal kopiert - siebenmal als Rueckwaerts-Scan auf den LETZTEN Punkt
    // (uMissingOverride, uAbstractNotImpl, uConstantReturn,
    //  uInheritedMethodEmpty, uRoutineResultAssigned, uUnusedPrivateMethod,
    //  uConstStringParameter via LastDelimiter) und EINMAL abweichend in
    // uCanBeClassMethod als Pos('.') = ERSTER Punkt. Die Pos-Fassung liefert
    // bei mehr als einem Punkt 'TInner.DoIt' statt 'DoIt'; der Decl<->Impl-
    // Abgleich in SCA148 (CanBeClassMethod) scheitert dann STILL - kein
    // Fehler, nur ein nicht gefundener Partner. Diese zentrale Fassung ist
    // die Rueckwaerts-Semantik; uCanBeClassMethod folgt ihr jetzt ebenfalls.
    class function UnqualifiedNameLast(const AName: string): string; static;

    // Wie UnqualifiedNameLast, zusaetzlich lowercase - fuer Detektoren, die
    // das Ergebnis ausschliesslich als case-insensitiven Match-Key nutzen
    // (uConstStringParameter: Decl<->Impl-Matching ueber ein TStringList-Set).
    class function UnqualifiedNameLastLower(const AName: string)
      : string; static;

    // Der TYP, dem eine Methoden-Implementierung gehoert - das vorletzte
    // Segment ihres qualifizierten Namens:
    //   'TFoo.Bar'              -> 'TFoo'
    //   'TOuter.TInner.DoIt'    -> 'TInner'      <- der innere Typ, nicht der aeussere
    //   'FreeRoutine'           -> ''            (kein Qualifizierer)
    //
    // Nicht zu verwechseln mit 'alles vor dem letzten Punkt': das liefert bei
    // nested types 'TOuter.TInner' - einen gepunkteten String, der als
    // Klassen-Key nirgends matcht und den betreffenden Guard STILL ausfallen
    // laesst (2026-07-27 in uLeakDetector2, uInstanceInvokedConstructor und
    // uCanBeClassMethod gefunden, nachdem der Parser mehrfach qualifizierte
    // Namen zu liefern begann).
    class function OwnerTypeName(const AName: string): string; static;

    // Wie OwnerTypeName, zusaetzlich lowercase (Match-Key-Nutzung).
    class function OwnerTypeNameLower(const AName: string): string; static;

    // Ordnet jeder in einem Typ-RUMPF deklarierten Methode den Namen
    // ihres Typs zu. Notwendig, weil der AST keinen Parent-Zeiger hat:
    // eine IMPLEMENTIERUNG traegt den Typ im qualifizierten Namen
    // ('TFoo.bar'), eine DEKLARATION im Klassen-/Interface-Rumpf nicht.
    // Caller besitzt das Ergebnis (Free).
    // Byte-identische Zentralisierung aus uMethodName (Voll-Review
    // 2026-09-12, Posten 74: uLongParamList ist der zweite Konsument -
    // dessen Dedup-Schluessel brauchte denselben Besitzertyp).
    class function BuildMethodOwnerMap(UnitNode: TAstNode)
      : TDictionary<TAstNode, string>; static;

    // Haengt Name und TypeRef JEDES Knotens des Teilbaums space-getrennt
    // an SB an - der Flachtext, auf dem uUnusedLocal, uUnusedParameter
    // und uUninitVar ihr Ganzwort-Matching fahren.
    //
    // Iterativ (eigener Stack), damit tiefe ASTs keinen Stack-Overflow
    // ausloesen. Besuchsreihenfolge ist die der bisherigen drei Kopien
    // (Pop/Push-DFS) - fuer eine Konkatenation ohne Positionsbezug
    // ohnehin unerheblich, aber so bleibt der Flachtext byte-gleich.
    //
    // Zentralisiert aus drei byte-gleichen Kopien (Voll-Review
    // 2026-09-12, Posten 89): uUnusedLocal.CollectAllTokens,
    // uUnusedParameter.CollectAllTokens und uUninitVar.CollectBodyTokens
    // (letztere trug den Hinweis 'Iterativ analog
    // uUnusedLocal.CollectAllTokens' bereits im Kopf). Der Vertrag ist
    // damit an EINER Stelle aenderbar - das war der Punkt: der
    // KnownGap-Test Local_NameOnlyInStringLiteral_KnownGap kuendigt ein
    // Literal-Blanking an, das sonst drei Units synchron braeuchte.
    class procedure CollectNameTypeTokens(Root: TAstNode;
      SB: TStringBuilder); static;

    // Der ERSTE Bezeichner der Vorfahrenliste eines nkClass.TypeRef -
    // in Delphi zwingend die Basisklasse, alles danach sind
    // Interfaces. Der Parser legt die Liste SPACE-separiert ab
    // (uParser2, ParseClassBody: tkComma wird verworfen und landet nie
    // im TypeRef) - ein Komma-Split greift dort NIE. Unit-Qualifier
    // wird gekappt ('Vcl.Forms.TForm' -> 'TForm'), Generic-Suffixe
    // defensiv ebenfalls; gleiche Schablone wie
    // uTypeIndex.BaseClassNameLow - beide sollen sich gleich
    // verhalten. Gehoben aus uNamingExt (Voll-Review 2026-09-12): die
    // lokalen ExtractParentName-Kopien in uMissingOverride und
    // uAbstractNotImpl splitteten am Komma und liessen
    // 'class(TBase, IThing)'-Subklassen komplett ungeprueft.
    class function FirstParentToken(const ATypeRef: string)
      : string; static;

    // True, wenn der Methodenname zwei oder mehr Qualifizierer traegt, die
    // Methode also einem in einem anderen Typ deklarierten Typ gehoert
    // ('TOuter.TInner.DoIt'). Solange ParseClassBody keinen tkKwType-Zweig
    // hat, existiert fuer diesen inneren Typ KEIN eigener AST-Knoten - jeder
    // Guard, der ueber den Typnamen aufloest, laeuft dort ins Leere. Mehrere
    // Detektoren schweigen deshalb bewusst fuer solche Methoden.
    class function IsNestedTypeMethodName(const AName: string)
      : Boolean; static;

    // Perf P1 (Konzept_Performance25, 2026-07-19): EIN O(N)-Scan ueber den
    // (gestrippten) Code sammelt fuer jedes Ident-Wort ([A-Za-z0-9_]+-Run)
    // die 1-basierten STARTPOSITIONEN unter dem lowercase-Key. Ersetzt in
    // uUnusedRoutine/uUnusedPrivateMethod das O(Kandidaten x Filegroesse)-
    // Muster 'TRegEx pro Kandidat + Volltext-Matches'. Semantik-identisch zu
    // '\b<ident>\b' (roIgnoreCase): PCRE-\w ohne UCP = ASCII [A-Za-z0-9_] =
    // IsIdentChar; ein Ganzwort-Match == ein kompletter Run gleichen (lower)
    // Texts; Woerter ueberlappen nicht. Caller besitzt das Dictionary
    // ([doOwnsValues] gibt die Positions-Listen frei).
    class function BuildWordPositionIndex(const Code: string):
      TObjectDictionary<string, TList<Integer>>; static;

    // Faltet Pascal-Konkatenations-Sequenzen von String-Literalen zu einem
    // einzigen virtuellen Literal zusammen:
    //   'foo' + 'bar'       -> 'foobar'
    //   'foo'+'bar'         -> 'foobar'
    //   'foo' + 'bar' + 'b' -> 'foobarb'  (Ketten)
    // Verdoppelte Apostrophen ('') innerhalb eines Literals bleiben als
    // Escape erhalten; alles ausserhalb der Literale wird unveraendert
    // durchgereicht.
    //
    // Zweck: Pattern-basierte SQL-Detektoren (uSqlDangerousStatement,
    // uSQLInjection) scannen String-Literale via Substring-Suche
    // (z.B. ' WHERE '). Wenn das SQL ueber Pascal-'+' konkateniert ist
    // (`'UPDATE ... ' + 'WHERE ...'`), trennt zwischen Daten und WHERE
    // ein `'+'`-Block die Suche - der Match schlaegt fehl, obwohl das
    // Statement zur Laufzeit ein valides WHERE hat. Nach diesem Merge
    // sieht der Detektor das SQL so, wie der Compiler es zusammenfuegt.
    class function MergeAdjacentStringLiterals(const S: string): string;
      static;

    // === EXPRESSION-CALL-EXTRAKTION ===================================
    // Aus einem Pascal-Expression-String (z.B. nkIfStmt.TypeRef oder
    // nkAssign.TypeRef oder nkCall.Name) alle Function-Call-Pattern
    // 'name(args)' extrahieren. Nested-paren-aware via Depth-Counting.
    // Whitespace zwischen 'name' und '(' wird toleriert - der Parser
    // packt Conditions oft mit JoinTokInto + Space-Separator.
    //
    // Verwendung: uUninitVar Phase 2.2-2.6 (Call-Detection in TypeRef-
    // Strings die der Parser NICHT als nkCall-Knoten abgelegt hat).
    // Bewusst List-basiert statt anonymous-method-Callback - anonymous
    // procs in Delphi koennen Nested-Procedures der enclosing Method
    // nicht erfassen (E2555).
    class procedure ParseCallsInExpr(const Expr: string;
      Calls: TList<TExprCall>); static;

    // Funktions-Name aus nkCall.Name extrahieren ('ReadLn(n)' -> 'readln').
    // Greift den Teil rechts vom letzten Punkt vor '(' (oder den ganzen
    // Ident wenn kein Punkt vorhanden).
    class function ExtractCallFunctionName(const CallExpr: string):
      string; static;

    // Roh-Args-String zwischen erster '(' und matching ')'.
    // Nested-paren-aware; Result leer wenn keine '(' vorhanden.
    class function ExtractCallArgsRaw(const CallExpr: string):
      string; static;

    // True wenn Lines[Idx] in einem Kontext steht in dem `[X]` ein
    // Delphi-Attribute waere (vor einer Member-Deklaration), und NICHT
    // ein Array-Index, Set-Literal oder Type-Parameter-Liste.
    //
    // Heuristik (drei Gates - alle muessen passen):
    //   1) Trim(Lines[Idx]) beginnt mit '['  (Attribute-Line-Start)
    //   2) Vorherige nicht-leere Zeile endet NICHT mit Expression-
    //      Continuation-Tokens (`=`, `:=`, `,`, `+`, `(`, `[`,
    //      Operator-Keywords wie `or`/`and`/`xor`/`of`/`then`/`else`).
    //   3) Diese Zeile (nach letztem `]`) ODER die naechste nicht-leere
    //      Zeile matched ein Member-Decl-Pattern:
    //        procedure|function|constructor|destructor|operator|property
    //        |class|interface|record|object
    //        |strict private/protected/public/published
    //        |[A-Za-z_]\w*\s*:   (Field-Decl `Name: Type;`)
    //
    // Adressiert den Real-World-FP-Storm der Attribute-Detektoren
    // (SCA180/181/183) wo `pd[x*3]`, `[ecvValidSigned]` etc. als
    // Attribute fehl-erkannt wurden.
    class function IsLikelyAttributePosition(Lines: TStringList;
      Idx: Integer): Boolean; static;

    // === FFI-BINDING-ERKENNUNG (Hebel A, 30%-Audit 2026-07-31) =========
    // Die zwei groessten Hint-Berge des Real-World-Korpus haben EINE
    // gemeinsame Ursache: SCA105 InterfaceName (15.707 Funde, 100 % FP im
    // Sample) und SCA106 MethodName (75.604 Funde, 74 % FP) melden fast
    // ausschliesslich ObjC-/JNI-Bridge-Importe (Kastri DW.iOSapi.*/
    // DW.Androidapi.*, Androidapi.JNI.*, Macapi.*, Alcinoe.AndroidApi.*)
    // und generierte COM-Typelib-Importe. Dort IST der Bezeichner der
    // native Klassenname / ObjC-Selektor / Java-Methodenname bzw. das
    // Link-Symbol - die Delphi-Namenskonventionen sind bewusst ausser
    // Kraft und eine Umbenennung braeche die Laufzeit-Bindung.
    //
    // KONSUMENTEN: ausschliesslich uInterfaceName (SCA105) und
    // uMethodName (SCA106). Rein additiv - kein bestehender Aufrufer
    // einer anderen Funktion dieser Unit aendert sein Verhalten.

    // True wenn AFileName dem Namensmuster des Delphi-Typelib-Importers
    // folgt ('*_TLB.pas'). Solche Units sind MASCHINELL erzeugt; der
    // Importer uebernimmt die COM-Originalnamen (`_StackFrameDisp`,
    // `IWMPCore3`) und regeneriert die Datei bei jedem Refresh - jede
    // Namens-Empfehlung darin ist unumsetzbar.
    //
    // GEWAEHLT: Dateiname. VERWORFEN: der Typelib-Header-Kommentar
    // ('The types declared in this file were generated ... Type Library').
    // Er ist zwar noch spezifischer, braucht aber Quelltext-Zugriff -
    // den hat SCA106 (rein AST-basiert) nicht. Korpus-Gegenprobe: alle
    // 2.290 SCA105- und 714 SCA106-Typelib-Funde tragen das Dateimuster,
    // der Header-Test haette KEINEN zusaetzlichen Fund erklaert.
    class function IsGeneratedTypelibFile(const AFileName: string)
      : Boolean; static;

    // Namen (lowercase, unqualifiziert) aller Typen der Unit, die ein
    // FFI-Binding sind. Ergebnis gehoert dem AUFRUFER (Free); nie nil,
    // bei AUnitNode = nil eine leere Liste.
    //
    // GEWAEHLTE KRITERIEN (in dieser Reihenfolge ausgewertet):
    //   (1) ANKER-VERERBUNG - die Elternliste (nkClass.TypeRef) enthaelt
    //       eine der 15 Bridge-Wurzeln der RTL (JObject/JObjectClass,
    //       IJavaInstance/IJavaClass, TJavaLocal, NSObject/NSObjectClass,
    //       IObjectiveC*, TOCLocal, ...). Empirisch aus dem Korpus
    //       gewonnen: diese 15 decken die Wurzeln von 99 % aller
    //       Bridge-Typen ab.
    //   (2) GENERIC-IMPORT-ARGUMENTE - `T<X> = class(TJavaGenericImport<
    //       XClass, X>)` bzw. TOCGenericImport benennt seine beiden
    //       Import-Interfaces als Generic-Argumente. Die stehen dank T2b
    //       (Commit 627e0ce) als nkGenericArgs-Marker am Klassenknoten.
    //       Dieses Kriterium traegt die Masse: es loest auch die Typen
    //       auf, deren Elternteil in einer ANDEREN Unit steht
    //       (`JKeyGenParameterSpec = interface(JAlgorithmParameterSpec)`).
    //   (3) TRANSITIVE VERERBUNG innerhalb der Unit (Fixpunkt ueber (1)
    //       und (2)).
    //
    // VERWORFEN:
    //   * [JavaSignature('...')]-Attribut am Typ: als Kriterium
    //     BELASTBAR, aber im Korpus zu 100 % REDUNDANT - jeder Typ mit
    //     dem Attribut wird bereits von (2) erfasst (Messung 2026-07-31:
    //     Abdeckung mit und ohne Attribut-Kriterium identisch, SCA105
    //     15.698 Drops, SCA106 unveraendert). Es steht ausserdem nicht
    //     im AST; SCA106 muesste dafuer die Quelldatei lesen.
    //   * uses-Vor-Gate (Androidapi.JNIBridge / Macapi.ObjectiveC):
    //     kostet Drops (gemessen 4 bzw. 8 im Korpus) und bringt nichts -
    //     beide Konsumenten bauen das Set erst beim ERSTEN Kandidaten
    //     (Lazy), Dateien ohne Kandidaten zahlen ohnehin nichts.
    //   * "Typ hat irgendeine cdecl-Methode" als TYP-Kriterium: haette
    //     korpusweit nur 796 zusaetzliche SCA106-Funde erklaert, wuerde
    //     aber in einer normalen Delphi-Klasse mit EINEM C-Callback alle
    //     Geschwister-Methoden mit stummschalten. Die cdecl-Evidenz wird
    //     deshalb in SCA106 METHODEN-LOKAL ausgewertet, nicht hier.
    class function CollectFfiBindingTypes(AUnitNode: TAstNode)
      : TStringList; static;

    // Nachschlag in dem von CollectFfiBindingTypes gelieferten Set.
    // ATypeName darf qualifiziert sein ('TOuter.TInner') - verglichen
    // wird das letzte Segment.
    class function IsFfiBindingTypeName(AFfiTypes: TStringList;
      const ATypeName: string): Boolean; static;

    /// <summary>Typnamen (lowercase) einer Unit, die mit einer
    /// FPC-Fremdsprachen-Klassenart deklariert sind - objcclass,
    /// objccategory, objcprotocol (Objective-C) oder cppclass (C++).
    /// Ergebnis ist sortiert und wird mit IsFfiBindingTypeName
    /// abgefragt; der Aufrufer gibt die Liste frei.</summary>
    /// <remarks>
    ///   H1 (2026-09-20). Solche Typen SPIEGELN eine fremde API: ihre
    ///   Methodennamen sind Selektoren, ihre Parameterzahl, ihr
    ///   Methodenumfang und ihre Laenge sind vom Framework vorgegeben.
    ///   Strukturregeln (SCA013/138/141/147) beschreiben dort nicht die
    ///   Entwurfsqualitaet des AUTORS - sie sind nicht behebbar.
    ///
    ///   Der Nachweis laeuft ueber den GESTRIPPTEN Quelltext und nicht
    ///   ueber den AST: der Parser fuehrt die vier Arten seit G1 zwar
    ///   als nkClass, vermerkt aber nirgends, WELCHES Schluesselwort
    ///   die Deklaration eroeffnet hat (TAstNode hat kein Feld dafuer).
    ///   Strings und Kommentare zaehlen deshalb nicht mit - die
    ///   Lazarus-Codetools fuehren 'objcclass' als Schluesselwort-
    ///   Literal, dort darf das Gate NICHT greifen.
    ///
    ///   WARUM TYPGENAU und nicht dateiweit wie das SCA106-Gate 8:
    ///   gemessen am Laz-Korpus (h_messung1) liegen in den
    ///   Kandidaten-Dateien 86 Funde dieser vier Regeln, aber nur 27
    ///   INNERHALB eines Binding-Typs - ein dateiweites Gate haette 59
    ///   Funde an gewoehnlichen Nachbarklassen mitgerissen.
    /// </remarks>
    class function CollectFpcBindingTypeNames(ALines: TStrings;
      AContext: TAnalyzeContext; const AFileName: string)
      : TStringList; static;

    // True wenn die Methode eine Event-Handler-Signatur hat - erster
    // nkParam heisst 'Sender' (case-insensitive) oder sein TypeRef
    // enthaelt 'tobject'. Solche Methoden werden vom Form-Designer per
    // DFM zur Laufzeit an Komponenten-Events gebunden. Gehoben aus
    // uCanBeClassMethod/uMethodName (Voll-Review 2026-09-12) - die
    // zweite Kopie war woertlich als 'Spiegel' dokumentiert und beide
    // trugen denselben tobject-Substring-Defekt; der ist nach der
    // Hebung genau EINMAL zu fixen (separater, fundbewegender
    // Schritt).
    class function IsEventHandlerSignature(MethodNode: TAstNode)
      : Boolean; static;

    // Zaehlt and/or/xor als ganze Woerter (case-insensitive,
    // Wort-Boundary per Pre-/Post-Zeichen) im literal-geblankten
    // Text - and/or/xor INNERHALB eines String-Literals
    // (Pos(' and ', SQL)) sind keine Boolean-Operatoren. Gehoben aus
    // uCognitiveComplexity/uCyclomaticComplexity (Voll-Review
    // 2026-09-12): die dokumentierte Kopier-Begruendung ('Detektoren
    // unabhaengig halten') war am Code erodiert - beide Kopien hingen
    // laengst an TDetectorUtils (IsIdentChar, BlankStringLiterals)
    // und mussten zweimal synchron nachgezogen werden (Backlog-Welle
    // 1; Literal-Blanking 2026-08-09).
    class function CountBooleanOpsLower(const ACondText: string)
      : Integer; static;

    // Erstes Wort einer Zeile (nach fuehrendem Whitespace), leer bei
    // Leerzeilen und wenn die Zeile mit einem Kommentar-Opener
    // ('{', '//', '(*') beginnt; StartCol = 1-basierte Spalte des
    // Wortes (0 wenn keins). Gehoben aus 8 Detektor-Kopien
    // (Voll-Review 2026-09-12; vor dem Umzug alle acht gedifft:
    // 7 identischer Kern, dazu die '['-Variante darunter).
    // KEIN Blockkommentar-Zustand ueber Zeilen - der Opener wird nur
    // an der ERSTEN Nicht-Whitespace-Position erkannt; die Nachruestung
    // ist ein separater, fundbewegender Schritt.
    class function ExtractFirstWord(const Line: string;
      out StartCol: Integer): string; static;

    // Wie ExtractFirstWord, aber eine '['-Zeile liefert das
    // Pseudo-Wort '[' - Attribut-Zeilen ('[Test]', '[Weak]') zaehlen
    // als Inhalt (der 226-DUnitX-FP-Fix von uEmptyVisibilitySection,
    // Baseline 2026-08-04). Eigene benannte Funktion statt eines
    // Boolean-Schalters - der eigene fkBooleanParam-Detektor haette
    // das Flag zu Recht geruegt.
    class function ExtractFirstWordOrBracket(const Line: string;
      out StartCol: Integer): string; static;

    // ------- Method-TypeRef-Vertrag (kind[:ret][;dir...]) -----------
    // Der Parser legt Methodenart, Rueckgabetyp und Direktiven als
    // flachen Text in nkMethod.TypeRef ab:
    //   'procedure' / 'function:Integer' / 'function:T;virtual'.
    // Diese Sektion buendelt die Leser dieses PARSER-Vertrags - kommt
    // eine neue Direktive dazu, zieht genau EINE Stelle nach
    // (Voll-Review 2026-09-12; vorher 3x IsBodyless + 2x
    // IsFunctionMethod + 2er-Paare woertlich in den Detektoren).

    // True wenn der TypeRef eine FUNKTION beschreibt: ':' vor dem
    // ersten ';'-Direktiv-Trenner. ACHTUNG: uConstantReturn nutzt
    // absichtlich eine ANDERE Praefix-Heuristik
    // (StartsText('function', ...)) und bleibt lokal - die zwei
    // Fassungen unterscheiden sich fuer 'function' ohne
    // Rueckgabetyp-Segment; Vereinheitlichung waere fundbewegend.
    class function IsFunctionTypeRef(const ATypeRef: string)
      : Boolean; static;

    // True wenn die Deklaration keinen eigenen Rumpf hat:
    // ;abstract / ;forward / ;external / ;dispid.
    class function IsBodylessTypeRef(const ATypeRef: string)
      : Boolean; static;

    // Rueckgabetyp aus dem TypeRef ('function:T;virtual' -> 'T');
    // leer fuer Prozeduren.
    class function ExtractReturnType(const ATypeRef: string)
      : string; static;

    // True wenn eine lokale Variable per 'absolute Result' die
    // Storage des Funktionsergebnisses aliast - jeder Zugriff ueber
    // sie IST ein Result-Zugriff.
    class function HasAbsoluteResultAlias(AMethodNode: TAstNode)
      : Boolean; static;

    // Whitespace raus + lowercase - normalisiert eine
    // Zuweisungs-LHS fuer Vergleiche ('Result .X' -> 'result.x').
    class function NormalizeLhsLower(const S: string): string; static;
  end;


implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NoSonarMarker, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Masks,                  // MatchesMask fuer Test-Fixture-Patterns
  System.StrUtils,               // PosEx
  System.Generics.Defaults,      // Default-Comparer fuer TArray.Sort<Integer>
  System.RegularExpressions;     // TRegEx fuer IsLikelyAttributePosition

type
  // Match-Modus einer Regel der zentralen Test-Pfad-Liste (Fund 3,
  // Restschulden-Audit 2026-07-26) - Bedeutung siehe TEST_PATH_RULES
  // im Kopf von IsTestFixturePath.
  TTestPathMatchMode = (tmBaseName, tmDirSegment, tmSegmentStart);
  TTestPathLevels    = set of TTestPathLevel;
  TTestPathRule = record
    Pattern : string;
    Mode    : TTestPathMatchMode;
    Levels  : TTestPathLevels;
  end;

class function TDetectorUtils.IsIdentChar(Ch: Char): Boolean;
begin
  // Bewusst CharInSet und nicht die Vergleichskette: 56 der 59 lokalen
  // Rumpffassungen, die diese Funktion 2026-07-26 abgeloest hat, waren
  // genau dieses Mengen-Konstrukt (nur uCastAndFree, uSelfAssignment und
  // uInstanceInvokedConstructor hatten eine Kette). Die Zentralisierung war
  // als verhaltens- UND codegen-neutral gedacht; eine Kette waere eine
  // dritte Variante gewesen, die so nie irgendwo stand. Semantisch sind
  // beide identisch (Ch > #255 faellt in beiden Faellen raus).
  Result := CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TDetectorUtils.IsIdentStartChar(Ch: Char): Boolean;
begin
  Result := CharInSet(Ch, ['A'..'Z', 'a'..'z', '_']);
end;

class function TDetectorUtils.IsTestFixturePath(const FileName: string;
  const BaseDir: string; Level: TTestPathLevel): Boolean;
// Fund 3 (Restschulden-Audit 2026-07-26): EINE Musterliste fuer alle
// Auswerte-Konsumenten. Jede Regel traegt (a) ihren Match-Modus und (b)
// die Strenge-Stufen, in denen sie gilt - die Stufen bleiben damit
// unterschiedlich streng, lesen aber aus derselben Quelle.
//
// Match-Modi (bewusst getrennt, weil die Herkunftslisten unterschiedlich
// scharf waren und ein Vereinheitlichen Funde verschoben haette):
//   tmBaseName     - Glob gegen den Dateinamen OHNE Pfad (MatchesMask ist
//                    laut System.Masks case-insensitiv: die Masken-Literale
//                    und das Eingabezeichen laufen beide durch UpCase).
//   tmDirSegment   - VOLLES Pfad-Segment: '/<pattern>/' bzw. Segment-
//                    Gleichheit im BaseDir-relativen Teil. Beidseitig
//                    verankert.
//   tmSegmentStart - Segment-ANFANG: '/<pattern>'. Bewusst unscharf und
//                    nur noch fuer das Alt-Muster '/unittest' (deckt
//                    '/unittest/' + '/unittests/' + '/unittesting/' ab).
//                    Neue Regeln bitte NICHT in diesem Modus anlegen.
const
  TEST_PATH_RULES : array[0..32] of TTestPathRule = (
    // ---- Basename ----------------------------------------------------
    (Pattern: 'uTest*.pas';      Mode: tmBaseName;     Levels: [tplFixture, tplSecret]),
    // Lazarus A3 - .pp/.lpr-Pendants, und zwar NUR die mit gemessener
    // Wirkung: von 14 denkbaren Pendant-Mustern treffen im ganzen
    // Lazarus-Baum genau DREI Dateien etwas, das nicht ohnehin unter
    // einer Pfad-Segment-Regel (test/, demos/, ... - endungsunabhaengig!)
    // liegt: clienttest.lpr, iprotest.lpr, ContextHelpDemo.lpr. Die
    // uebrigen Pendants waeren tote Eintraege - und tote Whitelist-
    // Eintraege waren ein eigener Review-Major (SCA007-Whitelist).
    // Die drei .pp-Secret-Muster kommen dazu, weil Secrets in
    // Testdateien die teuerste FP-Klasse sind und die Muster im
    // Segment-Fall bereits dieselbe Politik fahren.
    (Pattern: 'uTest*.pp';       Mode: tmBaseName;     Levels: [tplFixture, tplSecret]),
    (Pattern: '*test.pp';        Mode: tmBaseName;     Levels: [tplSecret]),
    (Pattern: '*tests.pp';       Mode: tmBaseName;     Levels: [tplSecret]),
    (Pattern: '*test.lpr';       Mode: tmBaseName;     Levels: [tplFixture, tplSecret]),
    (Pattern: '*Demo.lpr';       Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*_Test.pas';      Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*_Tests.pas';     Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*TestSuite*.pas'; Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*Sample.pas';     Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*_Sample_*.pas';  Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*Demo.pas';       Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*_Demo_*.pas';    Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: 'MeineUnit.pas';   Mode: tmBaseName;     Levels: [tplFixture]),
    (Pattern: '*Demo.dfm';       Mode: tmBaseName;     Levels: [tplFixture]),
    // aus uHardcodedSecret.IsTestFilePath (dort frueher EndsWith auf dem
    // normalisierten Gesamtpfad - basename-aequivalent, weil '.pas' nie
    // einen Pfadtrenner enthaelt):
    (Pattern: '*test.pas';       Mode: tmBaseName;     Levels: [tplSecret]),
    (Pattern: '*tests.pas';      Mode: tmBaseName;     Levels: [tplSecret]),
    (Pattern: '*testu.pas';      Mode: tmBaseName;     Levels: [tplSecret]),   // DUnit(X) *TestU.pas
    (Pattern: '*testsu.pas';     Mode: tmBaseName;     Levels: [tplSecret]),   // *TestsU.pas
    (Pattern: '*spec.pas';       Mode: tmBaseName;     Levels: [tplSecret]),
    // Delta-Vermeidung zum alten Pos('/utest'): das traf auch 'uTestX.dfm'.
    // Praktisch irrelevant (der Secret-Detektor sieht nur geparste .pas),
    // aber so bleibt die Aenderung auf die utestimonials-Klasse begrenzt.
    (Pattern: 'uTest*.dfm';      Mode: tmBaseName;     Levels: [tplSecret]),
    // ---- Pfad-Segmente -----------------------------------------------
    (Pattern: 'test';            Mode: tmDirSegment;   Levels: [tplFixture, tplSecret, tplFixtureDir]),
    (Pattern: 'tests';           Mode: tmDirSegment;   Levels: [tplFixture, tplSecret, tplFixtureDir]),
    (Pattern: 'unittest';        Mode: tmDirSegment;   Levels: [tplFixture, tplFixtureDir]),
    (Pattern: 'unittests';       Mode: tmDirSegment;   Levels: [tplFixture, tplFixtureDir]),
    (Pattern: 'samples';         Mode: tmDirSegment;   Levels: [tplFixture, tplFixtureDir]),
    (Pattern: 'demos';           Mode: tmDirSegment;   Levels: [tplFixture, tplFixtureDir]),
    // BEWUSST OHNE tplFixtureDir (2026-08-05): 'Resources\' ist in
    // Delphi-Projekten ein gewoehnliches PRODUKTIONSverzeichnis.
    // Fuer den Post-Filter (tplFixture) ist die Regel weiterhin
    // richtig; ein Detektor-Gate wuerde damit aber echten
    // Kundencode stillegen. Die Vormessung der beiden Gates konnte
    // das nicht sehen - unter 386 Treffern war kein einziger
    // resources-Fall, der Korpus enthaelt die Struktur nicht.
    (Pattern: 'resources';       Mode: tmDirSegment;   Levels: [tplFixture]),  // Form-Templates
    (Pattern: 'spec';            Mode: tmDirSegment;   Levels: [tplSecret]),
    (Pattern: 'fixtures';        Mode: tmDirSegment;   Levels: [tplSecret]),
    // FP-Fix Fund 3: frueher Pos('/utest', Norm) - das traf auch
    // '/utestimonials/'. Die Konvention meint (a) das Verzeichnis 'utest'/
    // 'utests' und (b) den Dateinamen 'uTestXxx.pas' (Regel 0). Beide sind
    // jetzt an Pfadgrenzen verankert.
    (Pattern: 'utest';           Mode: tmDirSegment;   Levels: [tplSecret]),
    (Pattern: 'utests';          Mode: tmDirSegment;   Levels: [tplSecret]),
    // ---- Segment-Anfang (Alt-Semantik, siehe Kopf) --------------------
    (Pattern: 'unittest';        Mode: tmSegmentStart; Levels: [tplSecret])
  );
var
  Bare, FullLow, BaseLow, RelLow : string;
  Segment                        : string;
  Segments                       : TArray<string>;
  Rule                           : TTestPathRule;
begin
  Result := False;
  if FileName = '' then Exit;
  Bare := ExtractFileName(FileName);

  // 1. Basename-Pattern matched unabhaengig vom Pfad-Anchoring -
  //    'uTest*.pas' ist projekt-uebergreifend ein Test-File-Indikator.
  //    tplFixtureDir fuehrt KEINE Basename-Regel, ueberspringt diesen
  //    Schritt also von selbst - kein Sonderfall noetig.
  for Rule in TEST_PATH_RULES do
    if (Rule.Mode = tmBaseName) and (Level in Rule.Levels)
       and MatchesMask(Bare, Rule.Pattern) then Exit(True);

  // 2. Pfad-Komponenten-Match. Wenn BaseDir gegeben, matchen wir NUR
  //    Segmente des Pfads RELATIV zu BaseDir - so wird '/test/' in einem
  //    externen Repo-Pfad wie 'D:\projects\company-tests\src\auth.pas'
  //    nicht mehr als Fixture erkannt. Ohne BaseDir fallen wir auf die
  //    alte volle Pfad-Substring-Suche zurueck (mit dem dokumentierten
  //    Caveat).
  FullLow := FileName.Replace('\', '/').ToLower;
  if BaseDir <> '' then
  begin
    BaseLow := IncludeTrailingPathDelimiter(BaseDir)
                 .Replace('\', '/').ToLower;
    if FullLow.StartsWith(BaseLow) then
      RelLow := Copy(FullLow, Length(BaseLow) + 1, MaxInt)
    else
      RelLow := '';
    if RelLow <> '' then
    begin
      Segments := RelLow.Split(['/']);
      for Segment in Segments do
        for Rule in TEST_PATH_RULES do
        begin
          if not (Level in Rule.Levels) then Continue;
          if (Rule.Mode = tmDirSegment) and (Segment = Rule.Pattern) then
            Exit(True);
          if (Rule.Mode = tmSegmentStart) and Segment.StartsWith(Rule.Pattern) then
            Exit(True);
        end;
    end;
  end
  else
  begin
    for Rule in TEST_PATH_RULES do
    begin
      if not (Level in Rule.Levels) then Continue;
      if (Rule.Mode = tmDirSegment)
         and (Pos('/' + Rule.Pattern + '/', FullLow) > 0) then Exit(True);
      if (Rule.Mode = tmSegmentStart)
         and (Pos('/' + Rule.Pattern, FullLow) > 0) then Exit(True);
    end;
  end;
end;

class function TDetectorUtils.CommonDirOf(AFiles: TStrings): string;
var
  Root, Dir, Prev : string;
  i               : Integer;
begin
  Result := '';
  if (not Assigned(AFiles)) or (AFiles.Count = 0) then Exit;
  Root := ExtractFilePath(AFiles[0]);
  for i := 1 to AFiles.Count - 1 do
  begin
    Dir := ExtractFilePath(AFiles[i]);
    while (Root <> '') and
          not SameText(Copy(Dir, 1, Length(Root)), Root) do
    begin
      Prev := Root;
      // eine Ebene hoch (Root endet immer mit Trenner)
      Root := ExtractFilePath(ExcludeTrailingPathDelimiter(Root));
      // Fixpunkt = Laufwerkswurzel bzw. drive-relatives 'C:' - dann
      // gibt es keine gemeinsame Wurzel.
      if SameText(Root, Prev) then Exit;
    end;
    if Root = '' then Exit;
  end;
  // Die LAUFWERKSWURZEL ist kein brauchbarer Anker ('C:/' hat Laenge 3):
  // relativ zu ihr waere wieder fast der ganze Absolutpfad Segment-
  // Material - genau das soll der Anker ja verhindern.
  if Length(ExcludeTrailingPathDelimiter(Root)) <= 2 then Exit;
  Result := Root;
end;

class function TDetectorUtils.FindWholeWordLower(const Needle,
  HaystackLower: string): Integer;
begin
  Result := FindWholeWordLower(Needle, HaystackLower, 1);
end;

class function TDetectorUtils.FindWholeWordLower(const Needle,
  HaystackLower: string; AFrom: Integer): Integer;
var
  Start, NLen, HLen, i: Integer;
  LeftOK, RightOK     : Boolean;
begin
  Result := 0;
  NLen   := Length(Needle);
  HLen   := Length(HaystackLower);
  if (NLen = 0) or (HLen < NLen) or (AFrom < 1) then Exit;

  // Pos() ist die Schleife - wir starten ab AFrom und springen weiter
  // wenn der Match keine echten Wortgrenzen hat.
  Start := AFrom;
  while True do
  begin
    i := PosEx(Needle, HaystackLower, Start);
    if i = 0 then Exit;

    // Linke Grenze: Zeichen vor dem Match darf KEIN Identifier-Char sein.
    LeftOK := (i = 1) or not IsIdentChar(HaystackLower[i - 1]);

    // Rechte Grenze: Zeichen nach dem Match darf KEIN Identifier-Char sein.
    RightOK := (i + NLen - 1 >= HLen)
            or not IsIdentChar(HaystackLower[i + NLen]);

    if LeftOK and RightOK then Exit(i);

    Inc(Start, 1); // weiter suchen
    if Start > HLen - NLen + 1 then Exit;
  end;
end;

class function TDetectorUtils.ContainsWholeWordLower(const Needle,
  HaystackLower: string): Boolean;
begin
  Result := FindWholeWordLower(Needle, HaystackLower) > 0;
end;

class function TDetectorUtils.FindTokenBoundedLower(const Needle,
  HaystackLower: string): Integer;
var
  Start, NLen, HLen, i : Integer;
  CheckLeft, CheckRight: Boolean;
  LeftOK, RightOK      : Boolean;
begin
  Result := 0;
  NLen   := Length(Needle);
  HLen   := Length(HaystackLower);
  if (NLen = 0) or (HLen < NLen) then Exit;

  // Nur dort eine Wortgrenze verlangen, wo das Needle auf einem Identifier-
  // Zeichen endet/beginnt. '.text' hat links den Punkt als natuerliche
  // Grenze - der Vorgaenger ('e' in 'mediatype') darf ein Ident-Char sein.
  CheckLeft  := IsIdentChar(Needle[1]);
  CheckRight := IsIdentChar(Needle[NLen]);

  Start := 1;
  while True do
  begin
    i := PosEx(Needle, HaystackLower, Start);
    if i = 0 then Exit;

    LeftOK  := (not CheckLeft)  or (i = 1)
            or not IsIdentChar(HaystackLower[i - 1]);
    RightOK := (not CheckRight) or (i + NLen - 1 >= HLen)
            or not IsIdentChar(HaystackLower[i + NLen]);

    if LeftOK and RightOK then Exit(i);

    Inc(Start);
    if Start > HLen - NLen + 1 then Exit;
  end;
end;

class function TDetectorUtils.JoinSitesExceptAnchor(ASites: TList<Integer>;
  AAnchor: Integer): string;
var
  Sortiert : TArray<Integer>;
  SB       : TStringBuilder;
  i        : Integer;
  Vorher   : Integer;
begin
  Result := '';
  if not Assigned(ASites) or (ASites.Count = 0) then Exit;
  Sortiert := ASites.ToArray;
  TArray.Sort<Integer>(Sortiert);
  SB := TStringBuilder.Create;
  try
    Vorher := -1;
    for i := Low(Sortiert) to High(Sortiert) do
    begin
      // Anker und Dubletten ueberspringen: dieselbe Zeile kann mehrfach
      // im Vorkommensstrom stehen (zwei Treffer in einer Zeile), fuer die
      // Anzeige ist sie EINE Stelle.
      if (Sortiert[i] = AAnchor) or (Sortiert[i] = Vorher) then Continue;
      if SB.Length > 0 then SB.Append(',');
      SB.Append(Sortiert[i]);
      Vorher := Sortiert[i];
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TDetectorUtils.StripStringLiterals(const S: string): string;
// ENTFERNEND: Literal-Inhalt UND Quotes fallen weg, Length(Result) < Length(S).
// Positionsempfindliche Aufrufer brauchen BlankStringLiterals (siehe dort).
var
  i     : Integer;
  C     : Char;
  InStr : Boolean;
begin
  Result := '';
  InStr := False;
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C = '''' then
      InStr := not InStr
    else if not InStr then
      Result := Result + C;
  end;
end;

class function TDetectorUtils.BlankStringLiterals(const S: string): string;
// POSITIONSERHALTEND: ersetzt jeden Char zwischen einfachen Anfuehrungs-
// zeichen (inkl. ''-Escape-Handling) durch ein Leerzeichen. Die Quotes
// selbst bleiben stehen, damit Length(Result) = Length(S) gilt und JEDE
// Position 1:1 auf die Eingabe zurueckrechenbar bleibt.
//
// Gegenstueck zu StripStringLiterals (ENTFERNT die Zeichen und verschiebt
// alles dahinter) - die beiden sind NICHT austauschbar. Herkunft: lokale
// Kopie in uDivByZero; hochgezogen mit Fund 4 (Restschulden-Audit
// 2026-07-26), weil die namensgleiche, aber gegensaetzliche Kopie zum
// stillen Loeschen "der Redundanz" einlud.
var
  i     : Integer;
  inStr : Boolean;
begin
  Result := S;
  inStr  := False;
  i := 1;
  while i <= Length(Result) do
  begin
    if Result[i] = '''' then
    begin
      if inStr and (i < Length(Result)) and (Result[i + 1] = '''') then
      begin
        Result[i]     := ' ';
        Result[i + 1] := ' ';
        Inc(i, 2);
        Continue;
      end;
      inStr := not inStr;
    end
    else if inStr then
      Result[i] := ' ';
    Inc(i);
  end;
end;

class function TDetectorUtils.SplitTopLevelArgs(
  const Args: string): TArray<string>;
// Byte-identische Zentralisierung der uIfThenShortCircuit-Fassung
// (Voll-Review 2026-09-12, Posten 71) - Vertrag siehe interface.
var
  parts : TList<string>;
  i, depth, start : Integer;
  inStr : Boolean;
  c : Char;
begin
  parts := TList<string>.Create;
  try
    depth := 0; inStr := False; start := 1;
    for i := 1 to Length(Args) do
    begin
      c := Args[i];
      if inStr then
      begin
        if c = '''' then inStr := False;
      end
      else if c = '''' then inStr := True
      else if c = '(' then Inc(depth)
      else if c = ')' then Dec(depth)
      else if (c = ',') and (depth = 0) then
      begin
        parts.Add(Copy(Args, start, i - start));
        start := i + 1;
      end;
    end;
    parts.Add(Copy(Args, start, Length(Args) - start + 1));
    Result := parts.ToArray;
  finally
    parts.Free;
  end;
end;

class function TDetectorUtils.TruncateSurrogateSafe(const S: string;
  AMaxUnits: Integer): string;
// Direkter Bereichstest statt Char-Helper - haelt uDetectorUtils frei
// von System.Character. Ein Low-Surrogat am Schnittende bleibt stehen:
// dann liegt das PAAR vollstaendig im Ergebnis (oder die Quelle war
// schon vorher kaputt - das repariert eine Kuerzung nicht).
begin
  Result := Copy(S, 1, AMaxUnits);
  if (Result <> '') and (Result[Length(Result)] >= #$D800) and
     (Result[Length(Result)] <= #$DBFF) then
    SetLength(Result, Length(Result) - 1);
end;

class function TDetectorUtils.SameSourceFile(const A, B: string): Boolean;
// Vergleicht Datei-Pfade case-insensitiv und mit normalisierten Trennern.
//
// BIS 08.09. verglich diese Funktion NUR den Basisnamen. In einer
// Projektgruppe mit mehreren Ordnern galten damit D:\projA\uMain.pas und
// D:\projB\uMain.pas als dieselbe Datei, und der Einzeldatei-Export zog
// die Befunde beider zusammen - ohne dass der Leser es sehen konnte
// (Modul-Codereview, MAJOR). Gleichnamige Units sind in Delphi-
// Projektgruppen der Normalfall, nicht die Ausnahme.
//
// Warum kein schlichter Volltextvergleich: der Aufrufer haelt mal einen
// absoluten, mal einen relativen Pfad, je nachdem woher der Befund kommt.
// Deshalb der TAIL-Vergleich - der kuerzere Pfad muss ein Suffix des
// laengeren sein, UND ZWAR AN EINER TRENNERGRENZE. Ohne diese Bedingung
// waere 'D:\xsrc\uMain.pas' dasselbe wie 'src\uMain.pas'.
//
// Fehlt einer Seite der Verzeichnisanteil ganz, bleibt es beim
// Basisnamen - mehr Information liegt dann schlicht nicht vor.

  // NICHT ExtractFileName verwenden. Es schneidet unter Windows nur an
  // '\' und ':' ab (System.SysUtils: LastDelimiter([PathDelim,
  // DriveDelim]), PathDelim = '\'), der Vorwaerts-Schraegstrich ist dort
  // KEIN Trenner. Auf dem oben zu '/' normalisierten Pfad findet es also
  // nichts mehr und liefert aus 'D:/a/uMain.pas' ein '/a/uMain.pas' -
  // der Basisnamen-Vergleich waere damit immer falsch.
  //
  // Genau daran ist der erste Anlauf dieses Umbaus gescheitert, und die
  // Python-Nachbildung hat es VERDECKT: dort kennt split('/') den
  // Trenner sehr wohl. Eine Nachbildung muss die Pfad-Semantik der
  // Zielsprache nachbilden, nicht die der eigenen.
  function Basisname(const S: string): string;
  var
    i : Integer;
  begin
    for i := Length(S) downto 1 do
      if CharInSet(S[i], ['/', ':']) then
        Exit(Copy(S, i + 1, MaxInt));
    Result := S;
  end;

var
  NA, NB, Kurz, Lang : string;
begin
  Result := False;
  if (A = '') or (B = '') then Exit;

  NA := StringReplace(A, '\', '/', [rfReplaceAll]);
  NB := StringReplace(B, '\', '/', [rfReplaceAll]);

  if (Pos('/', NA) = 0) or (Pos('/', NB) = 0) then
    Exit(SameText(Basisname(NA), Basisname(NB)));

  if Length(NA) < Length(NB) then
  begin
    Kurz := NA;
    Lang := NB;
  end
  else
  begin
    Kurz := NB;
    Lang := NA;
  end;

  if Length(Kurz) = Length(Lang) then
    Exit(SameText(Kurz, Lang));

  Result := SameText(Copy(Lang, Length(Lang) - Length(Kurz) + 1, MaxInt),
                     Kurz)
    and (Lang[Length(Lang) - Length(Kurz)] = '/');
end;

class function TDetectorUtils.BlankNonCode(const Line: string;
  var State: TBlankScanState): string;
// Stripper mit Zeilen-uebergreifendem State - State.InBrace/InParen
// werden VOR der Zeile aus dem Caller-State gelesen und NACH der Zeile
// zurueckgeschrieben. So funktionieren auch Multi-Line-Comments wie
//   { Foo bar
//     baz }
// als Stripping ueber alle drei Zeilen.
var
  Buf : array of Char;
  i, L : Integer;
  InString : Boolean;
  C, Next : Char;
begin
  L := Length(Line);
  if L = 0 then Exit('');
  SetLength(Buf, L);
  InString := False;       // Strings koennen sich nicht ueber Zeilen ziehen
  i := 1;
  while i <= L do
  begin
    C := Line[i];
    if i < L then Next := Line[i + 1] else Next := #0;

    if State.InBrace then
    begin
      Buf[i - 1] := ' ';
      if C = '}' then State.InBrace := False;
      Inc(i);
    end
    else if State.InParen then
    begin
      Buf[i - 1] := ' ';
      if (C = '*') and (Next = ')') then
      begin
        Buf[i] := ' ';
        Inc(i, 2);
        State.InParen := False;
      end
      else
        Inc(i);
    end
    else if InString then
    begin
      Buf[i - 1] := ' ';
      if C = '''' then
      begin
        if Next = '''' then    // '' Escape innerhalb String
        begin
          Buf[i] := ' ';
          Inc(i, 2);
        end
        else
        begin
          InString := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
    end
    else
    begin
      if (C = '/') and (Next = '/') then
      begin
        // Line-Comment: Rest der Zeile zu Spaces.
        while i <= L do
        begin
          Buf[i - 1] := ' ';
          Inc(i);
        end;
        Break;
      end
      else if C = '{' then
      begin
        Buf[i - 1] := ' ';
        State.InBrace := True;
        Inc(i);
      end
      else if (C = '(') and (Next = '*') then
      begin
        Buf[i - 1] := ' ';
        Buf[i]     := ' ';
        Inc(i, 2);
        State.InParen := True;
      end
      else if C = '''' then
      begin
        Buf[i - 1] := ' ';
        InString := True;
        Inc(i);
      end
      else
      begin
        Buf[i - 1] := C;
        Inc(i);
      end;
    end;
  end;
  SetString(Result, PChar(Buf), L);
end;

class function TDetectorUtils.ScanCodeLine(const Line: string;
  var State: TCommentScanState; out LineCommentCol: Integer;
  FillCh: Char; AKeepColumns: Boolean): string;
var
  j, n   : Integer;
  c      : Char;
  InStr  : Boolean;   // String-Literale spannen nie ueber Zeilen -> lokal
  pClose : Integer;
  Dst    : PChar;     // Schreibcursor in Result (0-basiert)
  OutLen : Integer;
begin
  // Perf (2026-07-05): P1-strip-cache - TStringBuilder-Allokation pro Zeile
  // vermeiden (Hot-Path: laeuft pro Quellzeile pro Strip). Der Output ist
  // nie laenger als der Input -> einmal SetLength(n), per PChar-Cursor
  // schreiben, am Ende exakt auf OutLen trimmen.
  //
  // UPSTREAM-BEFUND 8 (GITLAK, 28.08.), behoben 2026-08-29: INLINE-
  // Kommentare wurden UEBERSPRUNGEN statt geblankt, waehrend Strings 1:1
  // ersetzt wurden. Damit war der Output kuerzer als der Input, und jede
  // Spalte hinter einem Inline-Kommentar verschob sich nach links - in
  // genau dem Helfer, auf dessen Spaltentreue die Aufrufer bauen.
  // Sichtbar an zusammenwachsenden Bezeichnern:
  //   X := Alpha{note}Beta;   ->   X := AlphaBeta;
  // FindWholeWordLower('alpha') verfehlte so ein echtes Vorkommen, und
  // eine Suche nach 'alphabeta' traf einen Bezeichner, den es nicht gibt
  // - ein falsch Negatives und ein falsch Positives aus derselben Zeile.
  // GEMESSEN (rw29) und deshalb OPT-IN: als Vorgabe kostete das Blanken
  // 506 SCA102-Funde. uNestedRoutines schreibt bei sich (:223), dass
  // Kommentare ENTFERNT sind und '~' als Token-Trenner wirkt - mit
  // geblankten Kommentaren trennt es dort, wo Zusammenhang gebraucht
  // wird. In Alcinoe.FMX.Dialogs.pas fielen alle neun Funde weg, obwohl
  // die geschachtelte Routine dort steht. Ians Suite blieb gruen, weil
  // sein Fork diesen Vertrag nicht kennt - unserer schon.
  //
  // AUSNAHME: laeuft ein Kommentar bis Zeilenende (die Break-Zweige),
  // bleibt der Rest abgeschnitten - das verschiebt keine fruehere Spalte.

  // am Ende exakt auf OutLen trimmen. Ergebnis byte-identisch zum Builder.
  LineCommentCol := 0;
  InStr := False;
  n := Length(Line);
  SetLength(Result, n);
  if n = 0 then Exit;
  Dst := PChar(Result);
  OutLen := 0;
  j := 1;
  while j <= n do
  begin
    if State.InBraceComment then
    begin
      pClose := PosEx('}', Line, j);
      if pClose = 0 then Break;             // Block laeuft in naechste Zeile
      State.InBraceComment := False;
      if AKeepColumns then
        while j <= pClose do
        begin Dst[OutLen] := FillCh; Inc(OutLen); Inc(j); end
      else
        j := pClose + 1;
      Continue;
    end;
    if State.InParenComment then
    begin
      pClose := PosEx('*)', Line, j);
      if pClose = 0 then Break;
      State.InParenComment := False;
      if AKeepColumns then
        while j <= pClose + 1 do
        begin Dst[OutLen] := FillCh; Inc(OutLen); Inc(j); end
      else
        j := pClose + 2;
      Continue;
    end;
    c := Line[j];
    if InStr then
    begin
      Dst[OutLen] := FillCh; Inc(OutLen);
      if c = '''' then
      begin
        // Verdoppeltes Apostroph = escaptes Quote, bleibt im String.
        if (j < n) and (Line[j + 1] = '''') then
        begin Dst[OutLen] := FillCh; Inc(OutLen); Inc(j, 2); end
        else begin InStr := False; Inc(j); end;
      end
      else Inc(j);
      Continue;
    end;
    if c = '''' then
    begin
      Dst[OutLen] := FillCh; Inc(OutLen);
      InStr := True; Inc(j); Continue;
    end;
    if (c = '/') and (j < n) and (Line[j + 1] = '/') then
    begin LineCommentCol := j; Break; end;  // Rest = Zeilenkommentar
    if c = '{' then
    begin
      pClose := PosEx('}', Line, j + 1);
      if pClose = 0 then begin State.InBraceComment := True; Break; end;
      if AKeepColumns then
        while j <= pClose do
        begin Dst[OutLen] := FillCh; Inc(OutLen); Inc(j); end
      else
        j := pClose + 1;
      Continue;
    end;
    if (c = '(') and (j < n) and (Line[j + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, j + 2);
      if pClose = 0 then begin State.InParenComment := True; Break; end;
      if AKeepColumns then
        while j <= pClose + 1 do
        begin Dst[OutLen] := FillCh; Inc(OutLen); Inc(j); end
      else
        j := pClose + 2;
      Continue;
    end;
    Dst[OutLen] := c; Inc(OutLen);
    Inc(j);
  end;
  SetLength(Result, OutLen);
end;

class function TDetectorUtils.StripStringsAndComments(Lines: TStrings;
  out LineForChar: TArray<Integer>; FillCh: Char): string;
// Perf (2026-07-05): P1-strip-cache - LineForChar per SetLength+Index statt
// TList<Integer>.Add pro Zeichen (+ ToArray-Kopie), Result einmal exakt
// allokiert statt TStringBuilder. Zwei Phasen: erst alle Zeilen strippen
// (Gesamtlaenge dann bekannt), dann in EINEM Durchlauf Text kopieren und
// Zeilen-Map fuellen. Ergebnis byte-identisch zum alten Buf/Chars-Aufbau:
// pro Zeile Part + #10, Map-Eintrag i fuer jedes Part-Zeichen UND das #10.
var
  Parts : TArray<string>;
  State : TCommentScanState;
  i, k  : Integer;
  Total : Integer;
  P, L  : Integer;
  Dummy : Integer;
  Dst   : PChar;
begin
  SetLength(Parts, Lines.Count);
  State := Default(TCommentScanState);
  Total := 0;
  for i := 0 to Lines.Count - 1 do
  begin
    Parts[i] := ScanCodeLine(Lines[i], State, Dummy, FillCh);
    Inc(Total, Length(Parts[i]) + 1);   // +1 fuer #10 pro Zeile
  end;

  SetLength(Result, Total);
  SetLength(LineForChar, Total);
  if Total = 0 then Exit;               // 0 Zeilen -> '' + leere Map
  Dst := PChar(Result);
  P   := 0;                             // 0-basierter Schreibcursor
  for i := 0 to High(Parts) do
  begin
    L := Length(Parts[i]);
    if L > 0 then
      Move(PChar(Parts[i])^, Dst[P], L * SizeOf(Char));
    // Part-Zeichen UND den #10-Zeilenumbruch auf Quellzeile i mappen, damit
    // `\s`-Regex ueber das Zeilenende hinweg konsistent positioniert bleibt.
    for k := P to P + L do
      LineForChar[k] := i;
    Inc(P, L);
    Dst[P] := #10;
    Inc(P);
  end;
end;

class function TDetectorUtils.StripStringsAndCommentsCached(Lines: TStrings;
  out LineForChar: TArray<Integer>; AContext: TAnalyzeContext;
  const FileName: string; FillCh: Char): string;
begin
  // Perf (2026-07-05): P1-strip-cache - Cache-Lookup im per-Scan-Context;
  // ohne Context exakt das heutige Verhalten (direkt rechnen).
  if (AContext <> nil) and
     AContext.TryGetStrippedText(FileName, FillCh, Result, LineForChar) then
    Exit;
  Result := StripStringsAndComments(Lines, LineForChar, FillCh);
  if AContext <> nil then
    AContext.PutStrippedText(FileName, FillCh, Result, LineForChar);
end;

class function TDetectorUtils.StripFileCommentsKeepStrings(Lines: TStrings;
  out LineForChar: TArray<Integer>): string;
// Perf P7: EXAKTE Kopie der uPerfHotspots.StripFileComments-Familie
// (9 MD5-identische Zwillinge) - jede Abweichung hier waere Ergebnis-Drift
// in 9 Detektoren. Semantik siehe Interface-Kommentar.
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      InStr := False;
      j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end
          else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free; Buf.Free;
  end;
end;

class function TDetectorUtils.StripFileCommentsKeepStringsCached(
  Lines: TStrings; out LineForChar: TArray<Integer>;
  AContext: TAnalyzeContext; const FileName: string): string;
begin
  // Perf P7: Cache-Lookup im per-Scan-Context; ohne Context direkt rechnen.
  if (AContext <> nil) and
     AContext.TryGetKeepStringsText(FileName, Result, LineForChar) then
    Exit;
  Result := StripFileCommentsKeepStrings(Lines, LineForChar);
  if AContext <> nil then
    AContext.PutKeepStringsText(FileName, Result, LineForChar);
end;

class function TDetectorUtils.InStringLiteral(const ACode: string;
  APos: Integer): Boolean;
var
  i      : Integer;
  Anzahl : Integer;
begin
  Anzahl := 0;
  i := APos - 1;
  while (i >= 1) and (ACode[i] <> #10) do
  begin
    if ACode[i] = '''' then Inc(Anzahl);
    Dec(i);
  end;
  Result := Odd(Anzahl);
end;

class function TDetectorUtils.LineForPos(const LineFor: TArray<Integer>;
  APos: Integer): Integer;
begin
  if (APos >= 1) and (APos - 1 < Length(LineFor)) then
    Result := LineFor[APos - 1] + 1
  else
    Result := 0;
end;

class function TDetectorUtils.UnqualifiedNameLast(const AName: string): string;
// Byte-identische Uebernahme der 7-fach gleichen Detektor-Fassung:
// rueckwaerts bis zum ersten gefundenen Punkt (= der LETZTE im String),
// danach alles ab Punkt+1. Ohne Punkt bleibt der Name unveraendert.
var
  i : Integer;
begin
  Result := AName;
  for i := Length(AName) downto 1 do
    if AName[i] = '.' then
    begin
      Result := Copy(AName, i + 1, MaxInt);
      Exit;
    end;
end;

class function TDetectorUtils.UnqualifiedNameLastLower(
  const AName: string): string;
begin
  Result := LowerCase(UnqualifiedNameLast(AName));
end;

class function TDetectorUtils.OwnerTypeName(const AName: string): string;
// Vorletztes Segment: vom LETZTEN Punkt aus weiter rueckwaerts bis zum
// vorletzten. Bei genau einem Punkt ist das Ergebnis identisch mit
// 'alles vor dem Punkt' - der Normalfall (268570 von 271521 Headern im
// Korpus) verhaelt sich also unveraendert.
var
  i, LastDot : Integer;
begin
  Result  := '';
  LastDot := 0;
  for i := Length(AName) downto 1 do
    if AName[i] = '.' then
    begin
      LastDot := i;
      Break;
    end;
  if LastDot = 0 then Exit;                 // unqualifiziert
  for i := LastDot - 1 downto 1 do
    if AName[i] = '.' then
      Exit(Copy(AName, i + 1, LastDot - i - 1));
  Result := Copy(AName, 1, LastDot - 1);    // genau ein Punkt
end;

class function TDetectorUtils.OwnerTypeNameLower(const AName: string): string;
begin
  Result := LowerCase(OwnerTypeName(AName));
end;

class procedure TDetectorUtils.CollectNameTypeTokens(Root: TAstNode;
  SB: TStringBuilder);
// Vertrag siehe interface.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class function TDetectorUtils.BuildMethodOwnerMap(UnitNode: TAstNode)
  : TDictionary<TAstNode, string>;
// Vertrag siehe interface. Verschachtelte Typen haengen als GESCHWISTER
// in der Typsektion (siehe ParseNestedTypeDecl in uParser2), nicht
// unter dem aeusseren Knoten - der Subtree-Walk je Typknoten ordnet
// also nichts doppelt zu.
const
  // Interface-Typen fuehrt der Parser ebenfalls als nkClass; nkRecord
  // deckt record/object mit Methoden ab.
  OWNER_KINDS : array[0..1] of TNodeKind = (nkClass, nkRecord);
var
  Types : TList<TAstNode>;
  Meths : TList<TAstNode>;
  T, M  : TAstNode;
  ki    : Integer;
begin
  Result := TDictionary<TAstNode, string>.Create;
  if UnitNode = nil then Exit;
  for ki := Low(OWNER_KINDS) to High(OWNER_KINDS) do
  begin
    Types := UnitNode.FindAll(OWNER_KINDS[ki]);
    try
      for T in Types do
      begin
        if T.Name = '' then Continue;
        Meths := T.FindAll(nkMethod);
        try
          for M in Meths do
            Result.AddOrSetValue(M, T.Name);
        finally
          Meths.Free;
        end;
      end;
    finally
      Types.Free;
    end;
  end;
end;

class function TDetectorUtils.FirstParentToken(const ATypeRef: string): string;
// Byte-identische Hebung der uNamingExt-Fassung (Voll-Review
// 2026-09-12): Generic-Kappung, Space-Split (erster Eltern-Ident),
// Unit-Qualifier-Kappung - in dieser Reihenfolge.
var
  S : string;
  P : Integer;
begin
  S := Trim(ATypeRef);
  if S = '' then Exit('');
  P := Pos('<', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  P := Pos(' ', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  P := LastDelimiter('.', S);
  if P > 0 then S := Copy(S, P + 1, MaxInt);
  Result := S;
end;

class function TDetectorUtils.IsNestedTypeMethodName(
  const AName: string): Boolean;
var
  i, Dots : Integer;
begin
  Dots := 0;
  for i := 1 to Length(AName) do
    if AName[i] = '.' then
    begin
      Inc(Dots);
      if Dots >= 2 then Exit(True);
    end;
  Result := False;
end;

class function TDetectorUtils.BuildWordPositionIndex(const Code: string):
  TObjectDictionary<string, TList<Integer>>;
var
  i, n, ws : Integer;
  W : string;
  L : TList<Integer>;
begin
  Result := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  n := Length(Code);
  i := 1;
  while i <= n do
  begin
    if IsIdentChar(Code[i]) then
    begin
      ws := i;
      while (i <= n) and IsIdentChar(Code[i]) do Inc(i);
      W := LowerCase(Copy(Code, ws, i - ws));
      if not Result.TryGetValue(W, L) then
      begin
        L := TList<Integer>.Create;
        Result.Add(W, L);
      end;
      L.Add(ws);
    end
    else
      Inc(i);
  end;
end;

class function TDetectorUtils.MergeAdjacentStringLiterals(
  const S: string): string;
// State-Machine: ausserhalb eines String-Literals durchreichen, am
// schliessenden Apostroph LOOKAHEAD - wenn Whitespace + '+' + Whitespace
// + Apostroph folgen, sind beide Literale eine logische Konkatenation;
// wir ueberspringen das Schliess-Quote, den '+'-Block und das Oeffnungs-
// Quote und bleiben "in-string". Doppelte '' innerhalb des Literals
// werden als Escape behandelt (nicht das Ende).
var
  Sb   : TStringBuilder;
  i, n : Integer;
  j, k : Integer;
  InStr: Boolean;
begin
  Sb := TStringBuilder.Create;
  try
    n := Length(S);
    InStr := False;
    i := 1;
    while i <= n do
    begin
      if not InStr then
      begin
        Sb.Append(S[i]);
        if S[i] = '''' then InStr := True;
        Inc(i);
        Continue;
      end;
      // InStr: pruefen ob '' (Escape) oder echtes End.
      if S[i] = '''' then
      begin
        if (i < n) and (S[i + 1] = '''') then
        begin
          // Verdoppeltes Apostroph: Escape, beide Zeichen ausgeben, im
          // String bleiben.
          Sb.Append(S[i]); Sb.Append(S[i + 1]);
          Inc(i, 2);
          Continue;
        end;
        // Lookahead: Whitespace* '+' Whitespace* ''' ?
        j := i + 1;
        while (j <= n) and CharInSet(S[j], [' ', #9, #13, #10]) do
          Inc(j);
        if (j <= n) and (S[j] = '+') then
        begin
          k := j + 1;
          while (k <= n) and CharInSet(S[k], [' ', #9, #13, #10]) do
            Inc(k);
          if (k <= n) and (S[k] = '''') then
          begin
            // Konkatenation - Schliess-Quote, '+'-Block, Oeffnungs-Quote
            // ueberspringen, InStr beibehalten.
            i := k + 1;
            Continue;
          end;
        end;
        // Echtes Literal-Ende.
        Sb.Append(S[i]);
        InStr := False;
        Inc(i);
        Continue;
      end;
      // Normales String-Zeichen.
      Sb.Append(S[i]);
      Inc(i);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

// === EXPRESSION-CALL-EXTRAKTION ===========================================

class function TDetectorUtils.ExtractCallFunctionName(
  const CallExpr: string): string;
var
  S : string;
  ParenPos, DotPos : Integer;
begin
  S := Trim(CallExpr);
  ParenPos := Pos('(', S);
  if ParenPos > 0 then
    S := Trim(Copy(S, 1, ParenPos - 1));
  DotPos := LastDelimiter('.', S);
  if DotPos > 0 then
    S := Trim(Copy(S, DotPos + 1, MaxInt));
  Result := S;
end;

class function TDetectorUtils.ExtractCallArgsRaw(
  const CallExpr: string): string;
var
  S : string;
  ParenPos, Depth, i : Integer;
begin
  Result := '';
  S := CallExpr;
  ParenPos := Pos('(', S);
  if ParenPos = 0 then Exit;
  Depth := 1;
  for i := ParenPos + 1 to Length(S) do
  begin
    if S[i] = '(' then Inc(Depth)
    else if S[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Result := Copy(S, ParenPos + 1, i - ParenPos - 1);
        Exit;
      end;
    end;
  end;
  // Kein matching ')' - alles ab '(' nehmen.
  Result := Copy(S, ParenPos + 1, MaxInt);
end;

class procedure TDetectorUtils.ParseCallsInExpr(const Expr: string;
  Calls: TList<TExprCall>);

var
  T          : string;
  i, NameStart, NameEnd, Depth, ArgsStart : Integer;
  Entry      : TExprCall;
begin
  if Calls = nil then Exit;
  T := Expr;
  i := 1;
  while i <= Length(T) do
  begin
    if not IsIdentStartChar(T[i]) then
    begin
      Inc(i);
      Continue;
    end;
    NameStart := i;
    while (i <= Length(T)) and IsIdentChar(T[i]) do Inc(i);
    NameEnd := i - 1;
    while (i <= Length(T)) and (T[i] = ' ') do Inc(i);
    // Generic-Type-Parameter '<T>' bzw. '<K, V>' zwischen Name und '('
    // ueberspringen. Pattern: 'TryGet<TestFixtureAttribute>(attrib)'.
    // Disambiguation gegen '<' als Operator (z.B. 'x < 5'): wir
    // versuchen einen balancierten Skip und rollen zurueck wenn danach
    // KEIN '(' folgt (dann war's tatsaechlich ein Operator).
    if (i <= Length(T)) and (T[i] = '<') then
    begin
      var SaveI : Integer := i;
      var GDepth : Integer := 1;
      Inc(i);
      while (i <= Length(T)) and (GDepth > 0) do
      begin
        if T[i] = '<' then Inc(GDepth)
        else if T[i] = '>' then Dec(GDepth);
        Inc(i);
      end;
      while (i <= Length(T)) and (T[i] = ' ') do Inc(i);
      if (i > Length(T)) or (T[i] <> '(') then
      begin
        // War kein Generic-Call - Rewind, der Outer-Loop wird das
        // '<' als Non-IdentStart skippen.
        i := SaveI;
        Continue;
      end;
    end;
    if (i > Length(T)) or (T[i] <> '(') then Continue;
    // OK - 'name(' Pattern; Args bis matching ')' extrahieren.
    Inc(i);                                   // hinter '('
    ArgsStart := i;
    Depth := 1;
    while (i <= Length(T)) and (Depth > 0) do
    begin
      if T[i] = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Break;
      end;
      Inc(i);
    end;
    Entry.FuncNameLow := LowerCase(Copy(T, NameStart, NameEnd - NameStart + 1));
    Entry.ArgsRaw     := Copy(T, ArgsStart, i - ArgsStart);
    Calls.Add(Entry);
    if (i <= Length(T)) and (T[i] = ')') then Inc(i);
  end;
end;

class function TDetectorUtils.IsLikelyAttributePosition(
  Lines: TStringList; Idx: Integer): Boolean;
// siehe interface-Kommentar fuer Strategie.
var
  ThisLine, Prev, Tail : string;
  i : Integer;
  LastBracketPos : Integer;
const
  // Expression-Continuation: vorherige Zeile endet so -> diese `[` ist
  // Fortsetzung eines Ausdrucks, kein Attribute.
  EXPR_CONT_CHARS = ['=', ',', '+', '-', '*', '/', '(', '[', '&', '|', '^', ':', '@'];
  // Lower-cased Operator-Keywords die eine Continuation andeuten.
  EXPR_CONT_WORDS : array[0..14] of string = (
    'or', 'and', 'xor', 'not', 'in', 'is', 'of',
    'then', 'else', 'do', 'mod', 'div', 'shl', 'shr', 'as');

  function EndsWithOpKeyword(const Lower: string): Boolean;
  var
    W: string;
    L: Integer;
  begin
    L := Length(Lower);
    for W in EXPR_CONT_WORDS do
      if (L >= Length(W)) and (Copy(Lower, L - Length(W) + 1, Length(W)) = W) then
      begin
        // Wortgrenze links: Zeichen vor W darf KEIN Identifier-Char sein
        // (sonst matched 'as' am Ende von 'class' / 'pos' am Ende von '...').
        if (L = Length(W)) or
           (not IsIdentChar(Lower[L - Length(W)])) then
          Exit(True);
      end;
    Result := False;
  end;

  function LooksLikeMemberDecl(const S: string): Boolean;
  var
    Tr, Lo: string;
  begin
    Tr := Trim(S);
    if Tr = '' then Exit(False);
    Lo := LowerCase(Tr);
    // Decl-Keywords am Anfang.
    if (Pos('procedure ', Lo) = 1) or (Lo = 'procedure') then Exit(True);
    if (Pos('function ', Lo) = 1) or (Lo = 'function') then Exit(True);
    if (Pos('constructor ', Lo) = 1) or (Lo = 'constructor') then Exit(True);
    if (Pos('destructor ', Lo) = 1) or (Lo = 'destructor') then Exit(True);
    if (Pos('operator ', Lo) = 1) then Exit(True);
    if (Pos('property ', Lo) = 1) then Exit(True);
    if (Pos('class procedure', Lo) = 1) or (Pos('class function', Lo) = 1) or
       (Pos('class constructor', Lo) = 1) or (Pos('class destructor', Lo) = 1) or
       (Pos('class property', Lo) = 1) or (Pos('class var', Lo) = 1) or
       (Pos('class operator', Lo) = 1) then Exit(True);
    // Klassen-/Record-/Interface-Decl  `TFoo = class(...)` etc.
    if TRegEx.IsMatch(Tr,
         '^[A-Za-z_]\w*\s*=\s*(class|interface|record|object)\b',
         [roIgnoreCase]) then Exit(True);
    // Field-Decl `Name[, Name2]: Type;`. Sehr breit - aber nach
    // attribute-Zeile ist es das uebliche Pattern. Mehrere Namen
    // mit Komma getrennt, dann `:`, danach Type-Name.
    if TRegEx.IsMatch(Tr,
         '^[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*:\s*[A-Za-z_<]',
         [roIgnoreCase]) then Exit(True);
    // Weitere Attribute-Line direkt darunter -> zaehlt auch als
    // Attribute-Kontext (Member kommt erst danach).
    if (Length(Tr) > 0) and (Tr[1] = '[') then Exit(True);
    Result := False;
  end;

begin
  Result := False;
  if (Lines = nil) or (Idx < 0) or (Idx >= Lines.Count) then Exit;
  ThisLine := Trim(Lines[Idx]);
  if (ThisLine = '') or (ThisLine[1] <> '[') then Exit;

  // Gate 2: vorherige nicht-leere Zeile - mit `//`-Kommentar-Tail-Strip
  // damit `[cauNegotiate], // wraNegotiate` als `,`-Continuation erkannt
  // wird statt als `e`-Endung (mormot.net.client.pas:5238 Set-Literal-FP).
  i := Idx - 1;
  Prev := '';
  while i >= 0 do
  begin
    var Raw := Lines[i];
    var CmtP := Pos('//', Raw);
    if CmtP > 0 then Raw := Copy(Raw, 1, CmtP - 1);
    Prev := Trim(Raw);
    if Prev <> '' then Break;
    Dec(i);
  end;
  if Prev <> '' then
  begin
    var Last := Prev[Length(Prev)];
    if CharInSet(Last, EXPR_CONT_CHARS) then Exit;
    if EndsWithOpKeyword(LowerCase(Prev)) then Exit;
  end;

  // Gate 3: Member-Decl auf gleicher Zeile (nach letztem `]`) ODER
  // auf naechster nicht-leerer Zeile.
  LastBracketPos := 0;
  for i := Length(ThisLine) downto 1 do
    if ThisLine[i] = ']' then begin LastBracketPos := i; Break; end;
  if LastBracketPos > 0 then
  begin
    Tail := Trim(Copy(ThisLine, LastBracketPos + 1, MaxInt));
    if (Tail <> '') and LooksLikeMemberDecl(Tail) then Exit(True);
  end;
  // Naechste nicht-leere Zeile.
  i := Idx + 1;
  while i < Lines.Count do
  begin
    var NL := Trim(Lines[i]);
    if NL <> '' then
    begin
      if LooksLikeMemberDecl(NL) then Exit(True);
      // Auch leere Sections wie 'private', 'public' direkt nach
      // Attribute zaehlen NICHT als Member -> aber typisch ist der
      // Attribute steht VOR der Visibility-Section, nicht danach.
      // Hier konservativ False zurueck.
      Exit(False);
    end;
    Inc(i);
  end;
end;

// === FFI-BINDING-ERKENNUNG (Hebel A, 30%-Audit 2026-07-31) ================
// Strategie und Kriterien-Auswahl: siehe Interface-Kommentar.

class function TDetectorUtils.IsGeneratedTypelibFile(
  const AFileName: string): Boolean;
const
  TLB_SUFFIX = '_TLB.pas';
begin
  // EndsText ist case-insensitiv - im Korpus kommen '_TLB.pas' (jcl
  // mscorlib_TLB.pas) und '_tlb.pas' (doublecmd wmplib_1_0_tlb.pas) vor.
  Result := (AFileName <> '')
        and EndsText(TLB_SUFFIX, ExtractFileName(AFileName));
end;

class function TDetectorUtils.CollectFfiBindingTypes(
  AUnitNode: TAstNode): TStringList;
const
  // Bridge-Wurzeln der RTL. Empirisch aus dem Korpus gezogen (Haeufigkeit
  // als Elternteil eines belegten Bridge-Typs): nsobject/nsobjectclass
  // 1730/1728, jobject/jobjectclass 734/734, ijavainstance/ijavaclass
  // 278/274, tocgenericimport 3073, tjavagenericimport 1433, toclocal 86,
  // tjavalocal 88, iobjectivec 711. Die restlichen Wurzeln (juiview,
  // uiviewcontroller, ...) sind selbst Bridge-Typen aus FREMDEN Units -
  // sie werden nicht als Anker gefuehrt, sondern ueber Kriterium (2)
  // aufgeloest, damit die Liste keine offene Namensmenge wird.
  FFI_ANCHORS : array[0..14] of string = (
    'ijavaclass',   'ijavainstance', 'iobjectivec',  'iobjectivecclass',
    'iobjectivecinstance',           'javaarray',    'jobject',
    'jobjectclass', 'nsobject',      'nsobjectclass','tjavaarray',
    'tjavagenericimport',            'tjavalocal',   'tocgenericimport',
    'toclocal');
  // Nur DIESE beiden Basisklassen benennen ihre Import-Interfaces als
  // Generic-Argumente. nkGenericArgs haengt an JEDEM generischen Elternteil
  // (auch 'class(TObjectList<TCustomer>)') - ohne diese Einschraenkung
  // wuerde jedes Generic-Argument des Korpus als FFI-Typ gelten.
  GENERIC_IMPORT_BASES : array[0..1] of string = (
    'tjavagenericimport', 'tocgenericimport');
  // Vererbungstiefe innerhalb einer Unit; der Fixpunkt konvergiert real
  // nach 2-3 Runden, die Schranke schuetzt nur gegen zyklische Ketten
  // aus kaputtem/IFDEF-verdoppeltem Quelltext.
  MAX_INHERIT_ROUNDS = 32;
var
  Nodes       : TList<TAstNode>;
  Node        : TAstNode;
  TypeNames   : TArray<string>;
  TypeParents : TArray<TArray<string>>;
  Resolved    : TArray<Boolean>;
  i, k, Rnd   : Integer;
  Seg         : string;
  Changed     : Boolean;
  IsImport    : Boolean;

  // Letztes Segment eines (evtl. unit-qualifizierten) Bezeichners,
  // lowercase. 'Androidapi.JNI.GraphicsContentViewText.JWindowClass'
  // -> 'jwindowclass'. Bewusst NICHT UnqualifiedNameLast: die Eingabe
  // hier kann Whitespace und einen leeren Rest tragen.
  function LastSegLower(const AIdent: string): string;
  var
    p : Integer;
  begin
    Result := Trim(AIdent);
    for p := Length(Result) downto 1 do
      if Result[p] = '.' then
      begin
        Result := Copy(Result, p + 1, MaxInt);
        Break;
      end;
    Result := LowerCase(Result);
  end;

  // Die space-getrennte Eltern-/Generic-Argument-Liste des Parsers in
  // normalisierte Segmente zerlegen. Leere Teile (Trailing-Punkt aus
  // kaputtem Quelltext) fallen weg.
  function SplitLower(const AList: string): TArray<string>;
  var
    Parts : TArray<string>;
    j, n  : Integer;
    S     : string;
  begin
    SetLength(Result, 0);
    if AList = '' then Exit;
    Parts := AList.Split([' ']);
    SetLength(Result, Length(Parts));
    n := 0;
    for j := 0 to High(Parts) do
    begin
      S := LastSegLower(Parts[j]);
      if S = '' then Continue;
      Result[n] := S;
      Inc(n);
    end;
    SetLength(Result, n);
  end;

  function IsAnchor(const ASeg: string): Boolean;
  var
    j : Integer;
  begin
    for j := Low(FFI_ANCHORS) to High(FFI_ANCHORS) do
      if FFI_ANCHORS[j] = ASeg then Exit(True);
    Result := False;
  end;

  function IsGenericImportBase(const ASeg: string): Boolean;
  var
    j : Integer;
  begin
    for j := Low(GENERIC_IMPORT_BASES) to High(GENERIC_IMPORT_BASES) do
      if GENERIC_IMPORT_BASES[j] = ASeg then Exit(True);
    Result := False;
  end;

begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Duplicates    := dupIgnore;
  Result.Sorted        := True;          // IndexOf = Binaersuche
  if AUnitNode = nil then Exit;

  // Interface-Typen fuehrt der Parser ebenfalls als nkClass (siehe
  // ParseTypeSection); verschachtelte Typen haengen als GESCHWISTER in
  // der Typsektion und werden von FindAll damit ebenfalls erfasst.
  // Exception-Sicherheit: solange die Funktion nicht normal zurueckkehrt,
  // gehoert die Ergebnisliste noch UNS - der Aufrufer bekommt seine
  // Variable nie zugewiesen und koennte sie nicht freigeben.
  Nodes := nil;
  try
   try
    Nodes := AUnitNode.FindAll(nkClass);
    SetLength(TypeNames,   Nodes.Count);
    SetLength(TypeParents, Nodes.Count);
    SetLength(Resolved,    Nodes.Count);

    // --- Runde 0: Anker-Vererbung (1) + Generic-Import-Argumente (2) ---
    for i := 0 to Nodes.Count - 1 do
    begin
      Node           := Nodes[i];
      TypeNames[i]   := LastSegLower(Node.Name);
      TypeParents[i] := SplitLower(Node.TypeRef);
      Resolved[i]    := False;
      IsImport       := False;

      for Seg in TypeParents[i] do
      begin
        if IsAnchor(Seg) then Resolved[i] := True;
        if IsGenericImportBase(Seg) then IsImport := True;
      end;
      if Resolved[i] and (TypeNames[i] <> '') then
        Result.Add(TypeNames[i]);

      if IsImport then
        for k := 0 to Node.Children.Count - 1 do
          if Node.Children[k].Kind = nkGenericArgs then
            for Seg in SplitLower(Node.Children[k].Name) do
              Result.Add(Seg);
    end;

    // --- Fixpunkt: transitive Vererbung (3) ---------------------------
    Rnd := 0;
    repeat
      Changed := False;
      Inc(Rnd);
      for i := 0 to High(TypeNames) do
      begin
        if Resolved[i] or (TypeNames[i] = '') then Continue;
        // ueber (2) bereits eingetragen (Import-Argument) - nur den
        // Merker nachziehen, das kostet keine weitere Runde.
        if Result.IndexOf(TypeNames[i]) >= 0 then
        begin
          Resolved[i] := True;
          Continue;
        end;
        for Seg in TypeParents[i] do
          if Result.IndexOf(Seg) >= 0 then
          begin
            Resolved[i] := True;
            Result.Add(TypeNames[i]);
            Changed     := True;
            Break;
          end;
      end;
    until (not Changed) or (Rnd >= MAX_INHERIT_ROUNDS);
   finally
    Nodes.Free;
   end;
  except
    Result.Free;
    raise;
  end;
end;

class function TDetectorUtils.IsFfiBindingTypeName(AFfiTypes: TStringList;
  const ATypeName: string): Boolean;
var
  Seg : string;
begin
  Result := False;
  if (AFfiTypes = nil) or (AFfiTypes.Count = 0) or (ATypeName = '') then Exit;
  Seg := LowerCase(UnqualifiedNameLast(Trim(ATypeName)));
  if Seg = '' then Exit;
  Result := AFfiTypes.IndexOf(Seg) >= 0;
end;

class function TDetectorUtils.CollectFpcBindingTypeNames(ALines: TStrings;
  AContext: TAnalyzeContext; const AFileName: string): TStringList;
// Vertrag siehe Deklaration. Gesucht wird die Typdeklaration
//   <name> = [packed] objcclass|objccategory|objcprotocol|cppclass ...
// im gestrippten, lowercase gelesenen Quelltext. Bewusst zeilenweise:
// FPC schreibt Klassenart und Typnamen immer auf dieselbe Zeile (im
// Korpus ausnahmslos), und eine Zeilenregel kann keine fremde
// Deklaration einfangen.
const
  ARTEN : array[0..3] of string = (
    'objcclass', 'objccategory', 'objcprotocol', 'cppclass');
var
  LineFor : TArray<Integer>;
  Code    : string;
  Zeilen  : TArray<string>;
  Z, Rest : string;
  pEq, i  : Integer;
  Name    : string;

  // True, wenn Rest mit einer der vier Arten als WORT beginnt.
  function BeginntMitArt(const S: string): Boolean;
  var
    j, L : Integer;
  begin
    Result := False;
    for j := Low(ARTEN) to High(ARTEN) do
    begin
      L := Length(ARTEN[j]);
      if (Length(S) >= L) and (Copy(S, 1, L) = ARTEN[j]) and
         ((Length(S) = L) or
          not CharInSet(S[L + 1], ['a'..'z', '0'..'9', '_'])) then
        Exit(True);
    end;
  end;

begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Duplicates    := dupIgnore;
  Result.Sorted        := True;      // IndexOf = Binaersuche
  if ALines = nil then Exit;
  try
    Code := LowerCase(StripStringsAndCommentsCached(
      ALines, LineFor, AContext, AFileName));
    Zeilen := Code.Split([#10]);
    for i := 0 to High(Zeilen) do
    begin
      Z := Zeilen[i];
      pEq := Pos('=', Z);
      if pEq = 0 then Continue;
      Rest := TrimLeft(Copy(Z, pEq + 1, MaxInt));
      // 'packed' ist vor record/class erlaubt und schadet hier nicht.
      if Copy(Rest, 1, 7) = 'packed ' then Rest := TrimLeft(Copy(Rest, 8, MaxInt));
      if not BeginntMitArt(Rest) then Continue;
      Name := Trim(Copy(Z, 1, pEq - 1));
      // Generics abschneiden ('tfoo<t>' -> 'tfoo') und Rest pruefen:
      // uebrig bleiben muss ein reiner Bezeichner, sonst ist es keine
      // Typdeklaration (z. B. eine Zuweisung im Rumpf).
      var pLt := Pos('<', Name);
      if pLt > 0 then Name := Trim(Copy(Name, 1, pLt - 1));
      if Name = '' then Continue;
      if not CharInSet(Name[1], ['a'..'z', '_']) then Continue;
      var Ok := True;
      for var k := 1 to Length(Name) do
        if not CharInSet(Name[k], ['a'..'z', '0'..'9', '_']) then
        begin
          Ok := False;
          Break;
        end;
      if Ok then Result.Add(Name);
    end;
  except
    // Exception-Sicherheit: die Liste gehoert noch UNS, solange die
    // Funktion nicht normal zurueckkehrt (gleiche Politik wie
    // CollectFfiBindingTypes).
    Result.Free;
    raise;
  end;
end;

class function TDetectorUtils.ExtractFirstWord(const Line: string;
  out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z', 'a'..'z', '_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

class function TDetectorUtils.ExtractFirstWordOrBracket(const Line: string;
  out StartCol: Integer): string;
// Reihenfolge unerheblich: eine Zeile, die mit '[' beginnt, faellt in
// keinen Kommentar-Opener - fuer alle anderen entscheidet der Kern.
var
  i, n : Integer;
begin
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if (i <= n) and (Line[i] = '[') then
  begin
    StartCol := i;
    Exit('[');
  end;
  Result := ExtractFirstWord(Line, StartCol);
end;

class function TDetectorUtils.CountBooleanOpsLower(
  const ACondText: string): Integer;
// Byte-identische Hebung der beiden Detektor-Fassungen (Kern-Schleife
// samt Wort-Boundary-Helfern; Begruendung an der Deklaration).
var
  Lo : string;
  i  : Integer;
  function IsBoundaryAt(Pos: Integer): Boolean;
  begin
    Result := (Pos < 1) or (Pos > Length(Lo)) or (not IsIdentChar(Lo[Pos]));
  end;
  function MatchAt(Pos: Integer; const W: string): Boolean;
  var j: Integer;
  begin
    if Pos + Length(W) - 1 > Length(Lo) then Exit(False);
    for j := 1 to Length(W) do
      if Lo[Pos + j - 1] <> W[j] then Exit(False);
    Result := IsBoundaryAt(Pos - 1) and IsBoundaryAt(Pos + Length(W));
  end;
begin
  Result := 0;
  // Literale blanken - and/or/xor in einem String-Literal zaehlen nicht.
  Lo := LowerCase(BlankStringLiterals(ACondText));
  i  := 1;
  while i <= Length(Lo) do
  begin
    case Lo[i] of
      'a': if MatchAt(i, 'and') then begin Inc(Result); Inc(i, 3); Continue; end;
      'o': if MatchAt(i, 'or')  then begin Inc(Result); Inc(i, 2); Continue; end;
      'x': if MatchAt(i, 'xor') then begin Inc(Result); Inc(i, 3); Continue; end;
    else
      ;   // jedes andere Zeichen: kein Operator-Anfang, einfach weiter
    end;
    Inc(i);
  end;
end;

class function TDetectorUtils.IsEventHandlerSignature(
  MethodNode: TAstNode): Boolean;
// Hebung der uCanBeClassMethod-/uMethodName-Fassungen (Voll-Review
// 2026-09-12): erster nkParam entscheidet - 'Sender' als Name oder
// der Typ TObject. Faengt FormCreate(Sender: TObject),
// btnClick(Sender: TObject), OnFilter(Sender: TObject; ...) etc.
//
// Der TYP-Vergleich ist EXAKT (letztes Namenssegment, Generic-Suffix
// gekappt - FirstParentToken-Schablone), nicht Substring: die
// fruehere Pos('tobject', ...)-Fassung erklaerte JEDE Methode zum
// Event-Handler, deren erster Parameter TObjectList<T>/
// TObjectDictionary & Co. war - reale, haeufige Signaturen, deren
// Funde still verschwanden (Gruppen-Finding des Voll-Reviews; die
// Kopf-Doku beider Kopien deckte nur den exakten Typ TObject).
// 'System.TObject' matcht weiter (Qualifier-Kappung).
var
  Child : TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
  begin
    if Child.Kind <> nkParam then Continue;
    if SameText(Child.Name, 'Sender') then Exit(True);
    if SameText(FirstParentToken(Child.TypeRef), 'TObject') then
      Exit(True);
    Exit;                              // nur ersten Parameter pruefen
  end;
end;

class function TDetectorUtils.IsFunctionTypeRef(
  const ATypeRef: string): Boolean;
var
  ColonPos, SemiPos : Integer;
begin
  ColonPos := Pos(':', ATypeRef);
  if ColonPos = 0 then Exit(False);
  SemiPos := Pos(';', ATypeRef);
  Result := (SemiPos = 0) or (ColonPos < SemiPos);
end;

class function TDetectorUtils.IsBodylessTypeRef(
  const ATypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(ATypeRef);
  Result := (Pos(';abstract',  Low) > 0) or
            (Pos(';forward',   Low) > 0) or
            (Pos(';external',  Low) > 0) or
            (Pos(';dispid',    Low) > 0);
end;

class function TDetectorUtils.ExtractReturnType(
  const ATypeRef: string): string;
var
  c, s : Integer;
begin
  Result := '';
  c := Pos(':', ATypeRef);
  if c = 0 then Exit;
  Result := Copy(ATypeRef, c + 1, MaxInt);
  s := Pos(';', Result);
  if s > 0 then Result := Copy(Result, 1, s - 1);
  Result := Trim(Result);
end;

class function TDetectorUtils.HasAbsoluteResultAlias(
  AMethodNode: TAstNode): Boolean;
var
  LocalVars : TList<TAstNode>;
  LV  : TAstNode;
  Low : string;
  p, j : Integer;
begin
  Result := False;
  LocalVars := AMethodNode.FindAll(nkLocalVar);
  try
    for LV in LocalVars do
    begin
      Low := LowerCase(LV.TypeRef);
      p := Pos('absolute', Low);
      if p = 0 then Continue;
      j := p + 8;                                  // hinter 'absolute'
      while (j <= Length(Low)) and (Low[j] <= ' ') do Inc(j);
      if (Copy(Low, j, 6) = 'result')
         and ((j + 6 > Length(Low))
              or not CharInSet(Low[j + 6], ['a'..'z', '0'..'9', '_'])) then
        Exit(True);
    end;
  finally
    LocalVars.Free;
  end;
end;

class function TDetectorUtils.NormalizeLhsLower(const S: string): string;
var
  i, o : Integer;
begin
  SetLength(Result, Length(S));
  o := 0;
  for i := 1 to Length(S) do
    if S[i] > ' ' then
    begin
      Inc(o);
      Result[o] := S[i];
    end;
  SetLength(Result, o);
  Result := LowerCase(Result);
end;

end.
