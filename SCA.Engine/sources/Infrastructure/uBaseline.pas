unit uBaseline;

// Baseline-Filter fuer CI-Adoption. Schreibt / liest eine JSON-Datei
// mit den AKZEPTIERTEN Findings, damit ein laufender Lauf NEUE Findings
// vs. Baseline klar abhebt.
//
// ZU DEN ZAHLEN IN DIESER UNIT: die Kommentare belegen ihre
// Entscheidungen mit Messwerten vom Referenzkorpus D:/git-sca-realworld
// (Laeufe rw20 bis rw23, August 2026). Sie begruenden, WARUM etwas so
// gebaut ist - etwa dass eine globale Ziffern-Normalisierung allein in
// SCA101 rund 94.000 Identitaeten kostet. Als Groessenordnung bleiben
// sie gueltig, als exakte Zahl altern sie mit jedem Detektor-Gate.
// Wer sie neu braucht, rechnet sie nach; wer sie zitiert, nennt den
// Lauf dazu. Ein Kommentar ist kein Messprotokoll - das steht in der
// Commit-Historie (git log --grep=Fingerprint).
//
// Anwendung (typisch in CI):
//   Erst-Lauf:  analyser.exe --full --path repo --write-baseline sca.baseline.json
//   Folge-Lauf: analyser.exe --branch --path repo --baseline sca.baseline.json
//
// Mit --baseline werden alle Findings entfernt, deren Fingerprint im
// Baseline-Set vorkommt. Was uebrig bleibt sind die "neu seit Baseline"-
// Findings - das ist was die CI zaehlen soll.
//
// Fingerprint-Stabilitaet:
//   - Pfad: nur Dateiname (kein Verzeichnis - umgeht checkout-Variationen)
//   - Kind: Catalog-Token (z.B. 'MemoryLeak')
//   - MethodName: stabilisiert gegen Zeilen-Drift
//   - MissingVar (Detail): unterscheidet mehrere Findings im selben Method
//   Line wird BEWUSST NICHT in den Fingerprint genommen - Insert/Delete
//   einer Zeile verschiebt jedes Finding sonst. Trade-off: zwei Findings
//   gleichen Detektor-Typs in derselben Methode mit identischem Detail
//   matchen denselben Fingerprint -> Baseline matched einen davon (fine).
//   AUSNAHME fuer vier Metrik-Regeln: dort werden Ziffernfolgen im Detail
//   vor dem Hashen ersetzt, weil dort der SCHWELLWERT mit im Text steht -
//   Begruendung und Kosten bei METRIC_DETAIL_KINDS in der Implementation.
//
// ZWEITE MATCH-QUELLE - contextHash (seit v0.9.8, QUALIFIZIERT seit
// 2026-08-28): jeder Eintrag traegt zusaetzlich einen Hash ueber die
// +/- CONTEXT_HASH_RADIUS normalisierten Quellzeilen rund um die
// Fundstelle. Er ueberlebt Zeilen-Drift, Re-Indent, Methoden-Rename und
// jede Aenderung am Detailtext - alles, woran der Fingerprint zerbricht.
// Er identifiziert dafuer ein CODE-FENSTER und KEINE Fundstelle: zwei
// textgleiche Fenster teilen ihn, auch in verschiedenen Dateien. Deshalb
// geht er nirgends nackt in eine Match-Menge, sondern nur mit Datei UND
// Regel qualifiziert - die Zahlen dazu stehen bei BaselineContextKey.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Hash,
  uSCAConsts, uMethodd12;

type
  // Zuschnitt des Baseline-Fingerprints: Modus UND Wurzel als EIN Wert.
  //
  // WARUM ES DEN TYP GIBT (Review 2026-08-18, Befund A): beides lag bisher
  // in zwei unabhaengig setzbaren Prozess-Globals
  // (uSCAConsts.BaselinePathFingerprint / BaselineFingerprintRoot). Genau
  // diese Trennung war der Fehler - ApplyDetectorThresholds setzte den
  // MODUS, die WURZEL setzte nur RefreshBaselineSet, und die steigt aus,
  // solange "nur neue Funde" aus ist. Beim Schreiben einer Baseline stand
  // die Wurzel damit auf Leerstring, der Token fiel still auf den
  // Dateinamen zurueck - gelesen wurde danach mit Relativpfad-Tokens. Das
  // Feature meldete Erfolg und filterte nichts.
  //
  // Ein Wert kann nicht halb gesetzt sein. Wer ihn uebergibt, uebergibt
  // beides.
  TBaselineScope = record
  strict private
    // Rohe Stack-Deklaration ('var S: TBaselineScope;') laesst FPathMode
    // UNINITIALISIERT - Delphi nullt Records nur, wenn sie verwaltete
    // Felder haben und der Compiler sie anfasst. Deshalb setzt jede der
    // vier Fabriken BEIDE Felder, und Initialize legt den sicheren
    // Ausgangszustand fest: Dateiname-Modus, also das Bestandsverhalten.
    // Ein halb gesetzter Zuschnitt ist genau der Fehler, gegen den es
    // diesen Typ gibt.
    FPathMode : Boolean;
    FRoot     : string;
  public
    // noinspection AvoidOut
    // 'out' ist hier nicht gewaehlt, sondern vorgeschrieben: die Signatur
    // von class operator Initialize gibt der Compiler vor. Der Detektor
    // meint aufrufer-sichtbare out-Parameter, die einen Rueckgabewert
    // verstecken - hier ruft niemand auf.
    class operator Initialize(out Dest: TBaselineScope);
    // Bestandsverhalten: nur der Dateiname, checkout-tolerant.
    class function ByFileName: TBaselineScope; static;
    // Relativpfad ab ARoot. Leeres ARoot ist zulaessig und verhaelt sich
    // wie ByFileName - Effective meldet dann False.
    class function ByPath(const ARoot: string): TBaselineScope; static;
    // Pfad-Modus mit der WURZEL-REGEL: Verzeichnis der Projekt-/
    // Gruppendatei, sonst die Scan-Wurzel.
    //
    // Kein Boolean-Parameter fuer "Pfad-Modus ja/nein": das waere eine
    // verdeckte Strategie-Wahl am Aufrufer (SCA146). Wer den Schalter aus
    // der INI liest, schreibt die zwei Zeilen selbst - die Regel, um die
    // es ging, ist trotzdem nur hier.
    //
    // STAND (Schritte 2-6, 2026-08-19): CLI, EXE und Plugin bauen den
    // Zuschnitt hierueber und reichen ihn an Write/Apply/LoadFromFile
    // durch. Die Prozess-Globals existieren nur noch als Grenze fuer die
    // verbliebenen FromGlobals-Leser (s. dort).
    class function ForProject(const AProjectOrGroupFile,
      AScanRoot: string): TBaselineScope; static;

    // DIE ENTSCHEIDUNGSREGEL fuer den Zuschnitt, an EINER Stelle.
    // Beide Wirte - EXE und IDE-Plugin - beantworten dieselbe Frage:
    // steht [Baseline] PathInFingerprint, dann Relativpfad ab der
    // Scanwurzel, sonst blosser Dateiname. Nur WOHER die beiden Werte
    // kommen, unterscheidet sich (Prozess-Global gegen
    // Frame-Settings, Projektpfad-Feld gegen ScanRootDir) - und das ist
    // Wirt-Sache, die Regel nicht.
    //
    // WARUM ZENTRAL: die Regel stand zweimal fast gleich in den
    // Consumern, samt derselben achtzeiligen Begruendung. Bei zwei
    // Kopien faellt eine einseitige Aenderung nicht auf - und genau
    // hier ist sie teuer: ein falscher Zuschnitt laesst den
    // Baseline-Filter still ins Leere laufen (Review 2026-08-18,
    // Befund A: die Wurzel blieb leer, der Snapshot fiel auf
    // Dateinamen-Tokens zurueck, der naechste Filter matchte nichts).
    class function FromSettings(APathInFingerprint: Boolean;
      const AProjectOrGroupFile, AScanRoot: string): TBaselineScope; static;
    // Nur die Wurzel derselben Regel, als String - fuer die Aufrufer, die
    // (noch) uSCAConsts.BaselineFingerprintRoot direkt beschreiben.
    // Bewusst kein zweiter Regel-Ort: ForProject ruft dieselbe Funktion.
    class function RootForProject(const AProjectOrGroupFile,
      AScanRoot: string): string; static;
    // UEBERGANG: liest die beiden Globals. Verbliebene Aufrufer (Stand
    // Schritte 2-6, 2026-08-19): die parameterlose Fingerprint-Fassung
    // (der HTML-Export zieht seinen Fingerprint noch aus dem Prozess-
    // Zustand, bis TExporterHtml.Run einen Zuschnitt-Parameter traegt)
    // und die uEngineApi-Facade (bis TScanRequest einen traegt). Faellt
    // mit dem letzten von ihnen weg.
    class function FromGlobals: TBaselineScope; static;

    // Datei-Token fuer den Fingerprint.
    function FileToken(const AFileName: string): string;
    // Wirkt der Pfad-Modus TATSAECHLICH? Nur wenn Modus UND Wurzel gesetzt
    // sind. Der Unterschied zu IsPathMode ist der Kern von Befund A: der
    // blosse Wunsch nach Pfad-Modus aendert ohne Wurzel gar nichts.
    function Effective: Boolean;

    property IsPathMode : Boolean read FPathMode;
    property Root       : string  read FRoot;
  end;

  TBaseline = class
  public
    // Schreibt die aktuelle Findings-Liste als JSON in DestFile.
    // ueberschreibt eine vorhandene Datei.
    // Liefert die Anzahl der TATSAECHLICH geschriebenen Eintraege. Die ist
    // kleiner als Findings.Count, weil Lesefehler bewusst nicht
    // baseline-faehig sind (s. Rumpf). Bis 2026-08-08 meldeten alle fuenf
    // Aufrufer stattdessen Findings.Count - "Baseline written: ... (5
    // findings)" bei 4 Eintraegen in der Datei.
    // AScope bestimmt die Datei-Tokens UND den pathFingerprint-Marker
    // (Schritte 2-6, 2026-08-19): der Zuschnitt kommt als EIN Wert vom
    // Aufrufer statt aus zwei unabhaengig setzbaren Prozess-Globals -
    // genau deren Halb-Zustand war Befund A. Der Marker meldet die
    // WIRKUNG (Effective), nicht den Wunsch (IsPathMode): bisher schrieb
    // er den blossen Wunsch, weshalb die Mismatch-Warnung beim Lesen im
    // halb gesetzten Fall schwieg.
    class function Write(Findings: TObjectList<TLeakFinding>;
      const DestFile: string; const AScope: TBaselineScope): Integer; static;

    // Liest BaselineFile und filtert aus Findings alle Eintraege heraus
    // deren Fingerprint in der Baseline ist (vorhandene "akzeptierte"
    // Befunde). Idempotent; fehlende/leere Datei = no-op.
    // Liefert die Anzahl der GEDROPPTEN Findings (fuer Reporting).
    // AScope ist der Zuschnitt DIESES Lesers - er muss zum Zuschnitt des
    // Schreibers passen, sonst matcht die Legacy-Stufe nichts.
    // AWarnings (optional) sammelt Diagnose-Meldungen (z.B. Fingerprint-
    // Modus der Datei passt nicht zum uebergebenen Zuschnitt - dann
    // matcht seit 2026-08-28 GAR NICHTS mehr, denn der Datei-Token
    // steckt jetzt in BEIDEN Strecken; frueher trug der contextHash
    // ueber die Modus-Differenz hinweg, und genau das war das Loch).
    class function Apply(Findings: TObjectList<TLeakFinding>;
      const BaselineFile: string; const AScope: TBaselineScope;
      AWarnings: TStrings = nil): Integer; static;

    // Ist die Datei ueberhaupt eine Baseline? Apply ist bewusst
    // fehlertolerant und liefert bei allem, was es nicht versteht,
    // stillschweigend 0 - richtig fuer eine leere oder halb geschriebene
    // Datei, FALSCH fuer eine verwechselte. Ein versehentlich
    // uebergebener SARIF-Report filterte so nichts, und das Gate meldete
    // den kompletten Bestand als neu (Audit 2026-08-08). Der Aufrufer
    // kann damit hart abbrechen, statt ein falsch-gruenes Ergebnis zu
    // liefern. AReason traegt eine Klartext-Begruendung.
    class function IsBaselineFile(const FileName: string;
      out AReason: string): Boolean; static;

    // Fingerprint einer einzelnen Finding-Instanz mit dem Zuschnitt aus
    // den Prozess-Globals (FromGlobals). GRENZE der Schritte 2-6: bleibt,
    // solange der HTML-Export (uExportHtml) keinen Zuschnitt-Parameter
    // durchgereicht bekommt - er ist der letzte Produktions-Aufrufer.
    // Alle Baseline-Operationen dieser Unit nehmen den Zuschnitt explizit.
    class function Fingerprint(const F: TLeakFinding): string; overload; static;
    // Gleiche Berechnung, aber mit explizitem Zuschnitt statt aus den
    // Globals. Die parameterlose Fassung delegiert hierher.
    class function Fingerprint(const F: TLeakFinding;
      const AScope: TBaselineScope): string; overload; static;

    // Aufloesung des .sca-Standardorts (Konzept_BaselineSca 2026-08-08):
    //   Gruppe (.groupproj): <GroupDir>\.sca\<Name>.baseline.json
    //   Projekt (.dproj):    <ProjDir>\.sca\<Name>.baseline.json,
    //                        Fallback <ProjDir>\..\.sca\<Name>.baseline.json
    //                        (Projekt liegt typisch eine Ebene unter der
    //                        Gruppe, Baseline zentral gepflegt)
    //   Pfad-Scan:           <AScanRoot>\.sca\sca.baseline.json
    // AProjectOrGroupFile leer -> Pfad-Modus ueber AScanRoot. Liefert ''
    // wenn keiner der Kandidaten existiert; AProbed (optional) sammelt
    // ALLE geprueften Pfade fuer die Fehlermeldung des Aufrufers
    // (CLI-harter-Fehler bei --baseline-scan y ohne Datei).
    // Praezedenz insgesamt regelt der AUFRUFER: expliziter --baseline-
    // Pfad > [Baseline] File= > diese Aufloesung.
    class function ResolveBaselinePath(const AProjectOrGroupFile,
      AScanRoot: string; AProbed: TStrings = nil): string; static;

    // Standard-ZIEL fuer '--write-baseline auto' bzw. UI 'Write
    // baseline': der jeweils ERSTE .sca-Kandidat der Aufloesung, OHNE
    // Existenz-Pruefung ('' wenn weder Projekt/Gruppe noch Root
    // bekannt). Den .sca-Ordner legt der Schreiber bei Bedarf an.
    class function DefaultBaselineTarget(const AProjectOrGroupFile,
      AScanRoot: string): string; static;
  end;

  // Non-destruktiver Baseline-Filter fuer Live-Consumer (IDE-Editor, EXE):
  // laedt die Baseline einmalig und beantwortet pro Finding, ob es bereits
  // darin steht - OHNE die Findings-Liste zu veraendern. TBaseline.Apply
  // LOESCHT matchende Findings; das eignet sich nicht fuer einen
  // umschaltbaren "nur neue Funde"-Filter, bei dem die Vollmenge fuer
  // Export/Toggle erhalten bleiben muss.
  //
  // ZWEI MATCH-QUELLEN (seit 2026-08-28, Befund Baseline-Identitaet):
  // contextHash ODER Legacy-Fingerprint - dieselbe EITHER/OR-Regel, die
  // TBaseline.Apply auf dem CLI-Pfad seit v0.9.8 anwendet. Bis dahin kannte
  // Contains NUR den Fingerprint, und der hasht MissingVar mit. Aendert
  // ein Metrik-Detektor seinen Score, oder dreht der Nutzer an dem
  // dokumentierten INI-Knopf CyclomaticMax, wechselt damit die IDENTITAET
  // des Fundes: er erscheint in EXE und Plugin einmalig wieder als "neu",
  // ohne Warnung und ohne dass sich am Code etwas geaendert haette
  // (gemessen 37.987 Funde = 4,8 % des Referenzkorpus). Der CLI-Pfad war
  // dagegen abgesichert - genau diese Luecke schliesst der Umbau.
  //
  // Die Rettungsdaten lagen bereits bei den Nutzern: TBaseline.Write legt
  // den contextHash seit v0.9.8 in JEDEN Eintrag (s. BuildBaselineArray),
  // LoadFromFile hat ihn beim Laden nur weggeworfen. Dieser Umbau hoert
  // damit auf.
  //
  // WARUM DER HASH NICHT LAZY IM FILTER GERECHNET WIRD: er braucht die
  // Quelldatei, und der Anzeige-Filter laeuft im Editor-Pfad. Seit dem
  // G2-5-Hook (TAnalysisSession.ReleaseTransientCaches am Ende JEDES
  // Scans) ist der Text-Cache beim ersten Filterlauf garantiert KALT -
  // gemessen p50 252 und max 5.728 Dateien, die neu von der Platte kaemen,
  // plus rund 27.000 Syscalls je Durchlauf, und der eben freigegebene
  // halbe Gigabyte Cache fuellte sich sofort wieder auf. Deshalb rechnet
  // der CONSUMER die Hashes EINMAL im Scan-Nachlauf, solange die Bytes
  // noch warm sind (PrepareContextHashes), und Contains schlaegt nur noch
  // nach: zwei Dictionary-Zugriffe, kein I/O.
  //
  // EHRLICHE GRENZEN:
  //   * Baselines aelter als v0.9.8 tragen keinen contextHash. Dort bleibt
  //     alles wie bisher - PrepareContextHashes rechnet dann gar nicht
  //     erst, es gaebe nichts, wogegen zu matchen waere.
  //   * Funde ohne berechenbaren Hash (Datei nicht lesbar, Zeile 0) fallen
  //     wie bisher auf den Fingerprint zurueck.
  //   * Der contextHash bindet an +/- CONTEXT_HASH_RADIUS Zeilen Code
  //     RINGSUM. Das hat ZWEI Richtungen, und benannt gehoeren beide:
  //       - Aendert sich der Code ringsum, hilft der Hash nicht. Diese
  //         Richtung MERKT der Nutzer - der Fund taucht als "neu" auf.
  //       - Der Hash identifiziert ein CODE-FENSTER, keine Fundstelle.
  //         Textgleiche Fenster TEILEN ihn, und davon gibt es viele:
  //         782.832 Funde des Referenzkorpus tragen nur 480.268
  //         VERSCHIEDENE Hashes. Diese Richtung merkt der Nutzer NICHT -
  //         sie blendet aus. Deshalb geht der Hash nicht nackt in die
  //         Match-Menge, sondern mit Datei UND Regel qualifiziert
  //         (BaselineContextKey, dort die vollen Zahlen). Was bleibt: zwei
  //         Funde DERSELBEN Regel im selben Fenster DERSELBEN Datei sind
  //         weiter nicht zu trennen - das kann der Legacy-Fingerprint
  //         ebenso wenig (s. Unit-Kopf).
  //   * Der vorab gerechnete Speicher ist gross: 705.617 Schluessel a rund
  //     320 Byte, gemessen ~220 MB auf dem Referenzkorpus. Er faellt beim
  //     naechsten PrepareContextHashes und ueber ReleaseContextHashes -
  //     NICHT bei Clear und nicht bei LoadFromFile (s. dort, mit Grund).
  //   * Wer die Baseline erst NACH einem Scan einschaltet, hat keinen
  //     Hash-Speicher: der Filter arbeitet dann wie frueher allein ueber
  //     den Fingerprint, bis der naechste Scan laeuft. Nachrechnen waere
  //     genau das Datei-Lesen, das oben ausgeschlossen ist.
  //   * Contains wird dadurch TOLERANTER: ein Fund, der heute als "neu"
  //     angezeigt wird, kann kuenftig ausgeblendet werden. Das ist die
  //     Absicht des Umbaus - aber es ist eine Verhaltensaenderung fuer
  //     bestehende Baselines, und sie gehoert benannt.
  TBaselineSet = class
  private
    FFingerprints : TDictionary<string, Boolean>;
    // contextHash-Werte AUS DER BASELINE-DATEI - die zweite Match-Quelle.
    // Der Schluessel ist NICHT der blosse Hash, sondern Datei + Regel +
    // Hash (BaselineContextKey), gebildet aus den Feldern desselben
    // Eintrags. Ein nackter Hash blendete jeden Fund mit textgleichem
    // Code-Fenster aus, quer ueber Dateien und Regeln.
    FContextHashes: TDictionary<string, Boolean>;
    // contextHash JE FUND, im Scan-Nachlauf vorab gerechnet. Der Key ist
    // der Memo-Schluessel aus TFindingFingerprint (Datei + Zeile), dieses
    // Dictionary IST also zugleich das Memo, mit dem gerechnet wurde -
    // deshalb kostet der Vorablauf keine Extra-Runde.
    // Leer heisst "nicht gerechnet", nicht "kein Hash": Contains
    // entscheidet dann allein ueber den Fingerprint.
    FCtxByLine    : TDictionary<string, string>;
    // Ergebnis des LETZTEN PrepareContextHashes - nur fuer die Anzeige,
    // s. PreparedContextHashes.
    FPreparedCtx  : Integer;
    // Zuschnitt, mit dem geladen wurde (Schritte 2-6): Contains rechnet
    // die Anfrage-Fingerprints mit DIESEM Wert statt mit den Prozess-
    // Globals - der Anzeige-Filter haengt damit nicht mehr am globalen
    // Zustand zum Abfragezeitpunkt.
    FScope        : TBaselineScope;
    // Gemeinsamer Rumpf von PrepareContextHashes und
    // RefreshContextHashesForFile.
    function ComputeContextHashes(AFindings: TObjectList<TLeakFinding>;
      AForceStat: Boolean): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // Ersetzt den Inhalt durch die Match-Werte aus BaselineFile
    // (fingerprint UND contextHash). Tolerant gegen beide Formate
    // ({..,"findings":[{"fingerprint"..}]} ODER ein bare Array) - exakt
    // das was TBaseline.Write / CLI --write-baseline schreibt und der
    // HTML-Export liest. Fehlende/leere/kaputte Datei -> leeres Set
    // (Result 0), kein Fehler. Liefert die Anzahl geladener Fingerprints.
    // AScope wird gespeichert und gilt fuer alle folgenden Contains-
    // Abfragen - er muss zum Zuschnitt des Schreibers der Datei passen.
    // Der vorab gerechnete Hash-Speicher bleibt UNANGETASTET: er gehoert
    // zum Scan, nicht zur Datei, und die EXE laedt bei jedem Filterwechsel
    // neu (s. TForm2.ApplyFilter).
    function LoadFromFile(const BaselineFile: string;
      const AScope: TBaselineScope): Integer;
    procedure Clear;
    function IsEmpty: Boolean;
    // True wenn F bereits in der Baseline steht (= KEIN neuer Fund).
    function Contains(const F: TLeakFinding): Boolean;

    // SCAN-NACHLAUF, vor TAnalysisSession.ReleaseTransientCaches
    // aufzurufen: rechnet den contextHash jedes Fundes EINMAL, solange die
    // Quelldateien noch im Text-Cache liegen. Liefert die Anzahl der Funde
    // mit nicht-leerem Hash.
    // Verwirft den vorigen Stand IMMER - auch wenn nichts gerechnet wird.
    // Ein stehengebliebener Eintrag gehoerte zum LETZTEN Scan und waere
    // nach einer Quelltext-Aenderung schlicht falsch: er verglich einen
    // frischen Fund mit dem Hash des alten Codes.
    // Rechnet nur, wenn die geladene Baseline ueberhaupt contextHashes
    // enthaelt (dieselbe Ersparnis, die Apply mit seinem HasCtx-Zweig
    // macht) - Speicher rund 70 Zeichen je Fund.
    function PrepareContextHashes(
      AFindings: TObjectList<TLeakFinding>): Integer;
    // Wie PrepareContextHashes, aber fuer einen WATCH-Lauf: verwirft die
    // Eintraege der Dateien, die in AFindings VORKOMMEN (plus AFileName
    // selbst, falls die jetzt fundfrei ist), und rechnet sie neu. Ohne das
    // waeren die Eintraege dieser Dateien nach der Aenderung, die den
    // Watch-Lauf ausgeloest hat, veraltet und koennten einen frischen Fund
    // faelschlich ausblenden.
    //
    // WARUM NICHT NUR AFileName (Gegenpruefung 2026-08-28): ein Watch-Lauf
    // liefert auch Funde FREMDER Dateien. TDfmAnalysisRunner meldet seine
    // Detektoren mit dem .dfm-Pfad, und uIDEWatchMode leitet eine
    // .dfm-Aenderung ausdruecklich auf die .pas-Analyse um
    // (TWatchModeManager.MapToWatchedFile). Geloescht wurde nach der .pas,
    // gerechnet ueber ALLE Funde - die .dfm-Eintraege des letzten
    // Voll-Scans blieben stehen, Contains bekam sie per TryGetValue weiter
    // zurueck, und der frische DFM-Fund wurde gegen den ALTEN Code
    // geprueft und still ausgeblendet.
    // Loesch- und Rechenschluessel stammen jetzt aus DERSELBEN Quelle
    // (AFindings). Damit faellt zugleich die Abhaengigkeit von der
    // Pfadschreibweise des Parameters weg - der Aufrufer musste bisher
    // exakt die Schreibweise liefern, in der die Funde ihre Datei tragen.
    //
    // NICHT GEDECKT (Gegenpruefung 2026-08-28): liefert eine geaenderte
    // Datei GAR KEINE Funde mehr, steht ihr Pfad in keinem Fund und ihre
    // Eintraege bleiben im Speicher stehen. Das bleibt heute folgenlos,
    // weil OnWatchFindings Schritt 1 die alten Funde derselben Datei
    // ebenfalls stehenlaesst (uIDEAnalyserForm - eigener Fehler, eigener
    // Fix); wer den behebt, muss diese Loesch-Menge mitziehen.
    function RefreshContextHashesForFile(const AFileName: string;
      AFindings: TObjectList<TLeakFinding>): Integer;

    // Gibt den vorab gerechneten Hash-Speicher zurueck. Fuer den Moment,
    // in dem der Anwender ausdruecklich Speicher zurueckfordert.
    //
    // WARUM ES DIE METHODE BRAUCHT: FCtxByLine ist der mit Abstand
    // groesste Posten dieser Klasse - 705.617 Schluessel a rund 320 Byte,
    // gemessen ~220 MB auf dem Referenzkorpus (die Schaetzung "~2 MB" im
    // ersten Baubericht zaehlte nur den WERT, nicht den Schluessel). Weder
    // Clear noch LoadFromFile fassen ihn an (beides mit Grund, s. dort),
    // und der Menuepunkt "Reset All Findings" tat es bis 2026-08-28
    // ebenfalls nicht: wer nach einem Scan zurueckstellte und nicht neu
    // scannte, trug die 220 MB bis zum Prozessende mit.
    // TDictionary.Clear gibt das Bucket-Array wirklich frei (RTL:
    // SetLength(FItems, 0) + InternalSetCapacity(0)) - es braucht also
    // kein Neuanlegen des Dictionaries.
    procedure ReleaseContextHashes;

    // Wie viele Funde beim letzten Scan-Nachlauf einen nicht-leeren
    // contextHash bekommen haben. 0 heisst "die zweite Match-Quelle ist
    // AUS" - und genau das war von "sie wirkt" bisher nicht zu
    // unterscheiden, weil beide Aufrufer den Rueckgabewert von
    // PrepareContextHashes verwarfen. Die Statuszeile von EXE und Plugin
    // zeigt die Zahl, solange der Baseline-Filter aktiv ist.
    // Der Watch-Nachzug (RefreshContextHashesForFile) rechnet sie NICHT
    // fort: er betrifft die Funde einer einzelnen Datei, die Zahl bleibt
    // die des letzten Voll-Laufs.
    property PreparedContextHashes: Integer read FPreparedCtx;
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.JSON, System.IOUtils,
  uJsonFormat,             // JsonFormatEscaped - Format(2) escaped keine
                           // Steuerzeichen (s. TBaseline.Write)
  uFindingFingerprint;

// Zielverzeichnis einer zu schreibenden Datei bei Bedarf anlegen - so,
// wie es der Kontrakt am Unit-Kopf fuer den .sca-Ordner zusagt. Bis
// 2026-08-08 stand das nur im Kommentar: drei Aufrufer kompensierten es
// mit eigenem ForceDirectories, der vierte (Plugin) waere in eine
// EInOutError gelaufen.
procedure EnsureTargetDir(const AFileName: string);
var
  Dir : string;
begin
  Dir := ExtractFilePath(AFileName);
  if (Dir <> '') and not DirectoryExists(Dir) then
    ForceDirectories(Dir);
end;

// UTF-8 OHNE BOM schreiben (2026-08-08, RFC 8259 par.8.1 verbietet die
// Praeambel fuer JSON-Austausch). TStringList.SaveToFile mit
// TEncoding.UTF8 haette sie geschrieben. Bestehende Baselines MIT BOM
// bleiben lesbar - TFile.ReadAllText erkennt die Praeambel und
// ueberspringt sie.
procedure SaveTextNoBom(SL: TStringList; const DestFile: string);
var
  Enc : TEncoding;
begin
  Enc := TUTF8Encoding.Create(False);
  try
    SL.SaveToFile(DestFile, Enc);
  finally
    Enc.Free;
  end;
end;

{ ---- TBaselineScope ---- }

class function TBaselineScope.ByFileName: TBaselineScope;
begin
  Result.FPathMode := False;
  Result.FRoot     := '';
end;

class function TBaselineScope.ByPath(const ARoot: string): TBaselineScope;
begin
  Result.FPathMode := True;
  Result.FRoot     := ARoot;
end;

// noinspection AvoidOut
// Signatur vom Compiler vorgegeben, s. Deklaration.
class operator TBaselineScope.Initialize(out Dest: TBaselineScope);
// Sicherer Ausgangszustand fuer rohe Deklarationen, s. Feld-Kommentar.
begin
  Dest.FPathMode := False;
  Dest.FRoot     := '';
end;

class function TBaselineScope.RootForProject(const AProjectOrGroupFile,
  AScanRoot: string): string;
// DIE Wurzel-Regel: Verzeichnis der Projekt-/Gruppendatei, sonst die
// Scan-Wurzel. Stand bis 2026-08-19 viermal kopiert in CLI (zweimal), EXE
// und Plugin - alle vier rufen jetzt hierher.
begin
  if AProjectOrGroupFile <> '' then
  begin
    Result := ExtractFilePath(AProjectOrGroupFile);
  end
  else
  begin
    Result := AScanRoot;
  end;
end;

class function TBaselineScope.ForProject(const AProjectOrGroupFile,
  AScanRoot: string): TBaselineScope;
begin
  Result := ByPath(RootForProject(AProjectOrGroupFile, AScanRoot));
end;

class function TBaselineScope.FromSettings(APathInFingerprint: Boolean;
  const AProjectOrGroupFile, AScanRoot: string): TBaselineScope;
// s. Deklaration - die Regel, die beide Wirte teilen.
begin
  if APathInFingerprint then
  begin
    Result := ForProject(AProjectOrGroupFile, AScanRoot);
  end
  else
  begin
    Result := ByFileName;
  end;
end;

class function TBaselineScope.FromGlobals: TBaselineScope;
begin
  Result.FPathMode := BaselinePathFingerprint;
  Result.FRoot     := BaselineFingerprintRoot;
end;

function TBaselineScope.Effective: Boolean;
begin
  Result := FPathMode and (FRoot <> '');
end;

function TBaselineScope.FileToken(const AFileName: string): string;
// Default: nur der Dateiname (checkout-tolerant). Im Pfad-Modus mit
// gesetzter Wurzel: normalisierter Relativpfad ab der Wurzel
// (lowercase, '/'), damit gleichnamige Dateien in verschiedenen
// Ordnern getrennte Fingerprints bekommen. Wurzel leer oder Datei
// nicht unterhalb -> Fallback Dateiname.
var
  RootLow, FullLow : string;
begin
  Result := LowerCase(ExtractFileName(AFileName));
  if not Effective then
  begin
    Exit;
  end;
  RootLow := LowerCase(StringReplace(
    IncludeTrailingPathDelimiter(ExpandFileName(FRoot)),
    '\', '/', [rfReplaceAll]));
  FullLow := LowerCase(StringReplace(
    ExpandFileName(AFileName), '\', '/', [rfReplaceAll]));
  if Copy(FullLow, 1, Length(RootLow)) = RootLow then
    Result := Copy(FullLow, Length(RootLow) + 1, MaxInt);
end;

const
  // DIE VIER METRIK-REGELN, die der Zweig aufnimmt. Ihr Detailtext traegt
  // neben dem gemessenen Wert auch den KONFIGURIERTEN SCHWELLWERT
  // (Format-Strings WOERTLICH aus den Detektoren, inkl. Prosa-Schwanz - der
  // ist es, der den Fund nach der Normalisierung noch unterscheidet):
  //   SCA022 uCyclomaticComplexity
  //     'Cyclomatic complexity %d (limit: %d) - viele Verzweigungen, '
  //     'schwer zu testen'
  //   SCA018 uDeepNesting
  //     'Depth %d (%s from line %d, limit: %d)'
  //   SCA176 uCognitiveComplexity
  //     'Cognitive complexity %d (limit: %d) - nested control flow is '
  //     'hard to follow. Refactor by extracting helper methods or '
  //     'inverting guard conditions.'
  //   SCA012 uLongMethod
  //     '%d body lines, %d statements (limit: %d / %d)'
  //
  // SIE SIND NICHT DIE EINZIGEN REGELN MIT SCHWELLWERT IM TEXT - siehe den
  // Absatz "NICHT AUFGENOMMEN, OBWOHL SCHWELLWERT IM TEXT" weiter unten.
  //
  // WARUM DER ZWEIG UEBERHAUPT EXISTIERT: die fuenf Schwellen dieser vier
  // Regeln sind DOKUMENTIERTE Nutzer-Knoepfe in [Detectors]
  // (docs/configuration.md) - CyclomaticMax, DeepNestingMaxDepth,
  // CognitiveLimit, LongMethodMaxBodyLines, LongMethodMaxStatements; es
  // sind fuenf von NEUN Schwellen-Knoepfen, die die Datei dort auflistet.
  // Wer eine von 10 auf 12 dreht, aendert KEINEN einzigen Fund - aber jeden
  // Fingerprint dieser Regeln, weil die 10 im Meldetext steht und der
  // Meldetext gehasht wird.
  // Gemessen an rw20 (783.105 Funde, 27 Repos): 37.990 Funde = 4,85 % des
  // Korpus haengen mit ihrer Baseline-Identitaet an einem INI-Wert, zu
  // dessen Aenderung die Doku ausdruecklich einlaedt. Das passiert heute
  // schon, ohne jedes Update von uns. Derselbe Grund gilt fuer den SCORE:
  // ein Detektor- oder Parserfix, der den McCabe-Wert um 1 verschiebt,
  // entwertet den Eintrag ebenso - siehe uMethodd12.RelatedLines, wo das
  // Projekt genau diesen Fehlermodus schon einmal vermieden hat.
  //
  // ALLE IDENTITAETS-ZAHLEN IN DIESEM BLOCK GELTEN IM PFAD-MODUS
  // (PathInFingerprint=1), sofern nicht ausdruecklich anders gesagt - im
  // Default ist der Datei-Token der BASISNAME (s. TBaselineScope.FileToken),
  // und gleichnamige Dateien in verschiedenen Ordnern teilen ihn. Wo die
  // Unterscheidung die Groessenordnung aendert, stehen BEIDE Zahlen. Es ist
  // dieselbe Unterscheidung, die BaselineContextKey weiter unten fuer die
  // 6,11 % macht. Gezaehlt wird je Baseline, und eine Baseline gehoert zu
  // EINEM Repository - die Korpuszahlen sind also je Repo gruppiert.
  //
  // WARUM NICHT GLOBAL UEBER ALLE REGELN - BITTE NICHT "AUFRAEUMEN":
  // Eine Normalisierung ohne diese Einschraenkung kostet an rw20
  // ausgezaehlt 140.703 verschmolzene Identitaeten im Pfad-Modus, 114.577
  // im Default (nachgemessen; das ist die Obergrenze ohne Namensmodell,
  // s.u.); GESCHAETZT bleiben davon nach Abzug der Regeln, die MethodName
  // setzen, rund 120.700 = etwa 15 % ALLER Funde - die 140.703 sind
  // gezaehlt, die 120.700 sind es NICHT.
  // Der Killer ist SCA101 BeginEndRequired (285.942 Funde, groesste Regel
  // im Korpus, allein 94.254 verlorene Identitaeten):
  //   'Branch at column 5 uses a single statement without begin..end'
  //   'Branch at column 42 uses a single statement without begin..end'
  // Die SPALTENNUMMER ist dort der EINZIGE Unterscheider zwischen zwei
  // Funden derselben Datei - MethodName setzt der Detektor nicht. Nach
  // einer globalen Normalisierung legt EIN Baseline-Eintrag alle Branches
  // einer Datei still, und zwar unsichtbar: die Funde verschwinden
  // einfach, es gibt keine Meldung. Dasselbe Muster bei SCA090 NestedTry
  // (1.490) und SCA066 EmptyArgumentList (2.141), beide 'at column %d',
  // dazu SCA024 (5.158) und SCA021 (7.374).
  // uTestBaselineMetricFingerprint.SCA101_Spalte_BleibtUnterscheider ist
  // der Waechter dagegen - wer die Menge hier aufweicht, macht ihn rot;
  // DuplicateBlock_Zeilen_BleibenUnterscheider haelt dieselbe Grenze fuer
  // SCA021.
  //
  // WAS ES KOSTET (an rw20 methodengenau nachgemessen, nicht geschaetzt):
  // 183 BIS 185 verlorene Identitaeten im Pfad-Modus - SCA022 61,
  // SCA176 60, SCA018 33 bis 35, SCA012 29 -, das sind 0,49 % der vier
  // Regeln (0,482 bis 0,487 %) und 0,024 % des Korpus.
  // IM DEFAULT (Basisname) sind es rund 1.450 = 3,8 % der vier Regeln und
  // 0,19 % des Korpus, also der ACHTFACHE Wert: dort teilen gleichnamige
  // Dateien verschiedener Ordner den Token, und gleichnamige Methoden
  // darin fallen nach der Normalisierung zusammen (rw20 enthaelt vier
  // Kopien mancher JVCL-Units und sechs einer CEF4Delphi-Unit; 1.320 der
  // 1.450 stammen aus solchen Datei-Verschmelzungen, nur 130 aus einer
  // einzelnen Datei).
  // Ursache ist im Pfad-Modus ausschliesslich, dass jede dieser Regeln
  // hoechstens EINEN Fund je Methode erzeugt: kollidieren koennen nur
  // GLEICHNAMIGE Methoden derselben Datei mit verschiedenen Werten
  // (Overloads, gleicher Name in zwei Klassen einer Unit). Festgenagelt am
  // echten Weg Write -> Apply in uTestBaselineMetricFingerprint.
  // EinBaselineEintrag_BlendetGleichnamigeMethodeMit.
  //
  // WARUM EINE SPANNE UND KEINE PUNKTZAHL - die Streuung ist ehrlich und
  // ihre Ursache ist bekannt: der Methodenname steht NICHT im SARIF, er
  // muss aus der Kopfzeile des Quelltexts gelesen werden, und jede
  // Nachmessung braucht dafuer eine Heuristik. Drei unabhaengige
  // Auszaehlungen ergaben 222, 185 und 183:
  //   222 - Regex brach am '<' ab, las aus 'procedure TFoo<T>.Bar' nur
  //         'TFoo' und warf ALLE Methoden einer generischen Klasse in
  //         einen Topf. Schlicht falsch.
  //   185 - bildet die Namensregel des Parsers nach
  //         (uParser2.ParseMethodSignature: SkipGenericParams nach jedem
  //         Qualifizierer, 'TFoo<T>.TInner<U>.Baz' -> 'TFoo.TInner.Baz'),
  //         liest aber ROHZEILEN.
  //   183 - dasselbe auf KOMMENTAR- UND LITERALBEREINIGTEM Text.
  // WER NACHRECHNET, MUSS BEREINIGEN. Auf Rohzeilen zaehlen Prosa-Woerter
  // als Methodenkoepfe: 82 Funde der vier Regeln bekamen so einen falschen
  // Namen, und zwei davon kosteten eine Identitaet - 'you' aus dem
  // MessageDlg-Text 'To use this function you need to apply a filter ...'
  // (xeMainForm.pas:11360) und 'to' aus dem Kommentar 'Just a simple
  // procedure to increase ...' (JvThumbImage.pas:616). Jeder dieser
  // Phantomkoepfe warf zwei echte Methoden in einen Topf.
  // ZUM ZWEITEN MAL DERSELBE FEHLER: bei der SCA091-Arbeit
  // (uCaseStatementSize, Zweig sca091-sca070) waren die Zahlen zu
  // &-maskierten Bezeichnern ebenfalls auf ROHEM Quelltext gemessen, und
  // der einzige vermeintliche Treffer '&try' war der Windows-Accelerator
  // in 'Re&try', also ein Stringliteral. Eine Textsuche ueber
  // Delphi-Quelltext ist ohne Kommentar- und Literal-Strip keine
  // Codeanalyse - genau die Hausinvariante, die jeder Detektor dieses
  // Projekts einhaelt und die beide Messskripte gerissen haben.
  //
  // Wer die Zahl nicht nachrechnen will, braucht sie auch nicht: OHNE JEDES
  // NAMENSMODELL, also unter der (falschen) Annahme, alle Funde einer Datei
  // und Regel steckten in derselben Methode, liegt die Obergrenze bei
  // 20.194 fuer diese vier Regeln - gegen 140.703 bei globaler
  // Normalisierung. Faktor 7 zugunsten der Einschraenkung, ganz ohne
  // Heuristik. Im Default lauten dieselben zwei Zahlen 18.346 gegen
  // 114.577, Faktor 6 - das Argument haengt also nicht am Modus.
  //
  // BEKANNTE GRENZE - LEERER MethodName: die 183 bis 185 setzen voraus,
  // dass der Parser einen Namen liefert. Traegt ein Fund MethodName = '',
  // bleibt nach der Normalisierung gar kein Unterscheider mehr uebrig, und
  // alle Funde dieser Regel in dieser Datei fallen auf EINEN Fingerprint
  // zusammen - dann gilt genau die Obergrenze 20.194 von oben.
  // Beobachtet ist das nicht: in rw20 hat kein einziger Fund der vier
  // Regeln einen leeren Namen, und er ist auch schwer zu erreichen, weil
  // alle vier einen RUMPF brauchen (Score, Statements, Verschachtelung) -
  // das Headless-Method-Muster (uParser2.pas:178) erzeugt nkMethod OHNE
  // nkBlock, also gar keinen Fund, und laesst den Namen ohnehin intakt.
  // Festgehalten in uTestBaselineMetricFingerprint.
  // LeererMethodName_LaesstNurNochEineIdentitaetJeDatei.
  //
  // ZUGABE - der Zeilennummern-Vertragsbruch von SCA018 faellt mit:
  // 'Depth 8 (if from line 1456, limit: 4)' trug die Zeilennummer im
  // Text und brach damit die Zusage am Unit-Kopf, Line gehe NICHT in den
  // Fingerprint. Alle 3.707 SCA018-Funde in rw20 (= 100 % der Regel)
  // verloren ihre Baseline-Zuordnung schon bei reiner Zeilenverschiebung.
  // Ab hier nicht mehr - der Kind-Name ('if'/'for'/'while'/'repeat'/
  // 'case') ist ziffernfrei und bleibt als Unterscheider erhalten.
  // NICHT mitgeloest, weil andere Regel: SCA021 DuplicateBlock
  // ('lines 248-272', 9.150 Funde) traegt denselben Bruch und ist hier
  // bewusst NICHT drin - bei ihr sind die Zeilennummern das Einzige, was
  // zwei Duplikat-Gruppen derselben Datei unterscheidet.
  //
  // NICHT AUFGENOMMEN, OBWOHL SCHWELLWERT IM TEXT:
  // Vier weitere Regeln drucken einen dokumentierten [Detectors]-Knopf in
  // ihre Meldung. Fuer sie gilt der Schutz dieses Zweiges NICHT: wer dort
  // dreht, bekommt fuer jeden Fund der Regel einen NEUEN FINGERPRINT.
  //
  // WAS DAS FUER DEN NUTZER HEISST - PRAEZISE, weil docs/configuration.md
  // hier bis 2026-08-28 zu scharf formulierte ("surfaces once as new") und
  // damit zu einem ueberfluessigen --write-baseline einlud, das ALLE
  // aktuellen Funde uebernimmt: der Fingerprint ist nur EINE der beiden
  // Match-Quellen. TBaseline.Apply und TBaselineSet.Contains pruefen beide
  // "contextHash ODER Fingerprint", und der contextHash haengt an den
  // +/- CONTEXT_HASH_RADIUS Quellzeilen um die Fundstelle, nicht am
  // Meldetext (s. Unit-Kopf: "ueberlebt ... jede Aenderung am
  // Detailtext"). Ein gedrehter Schwellwert aendert nur den Meldetext -
  // Fundzeile und umgebender Code bleiben, der contextHash trifft weiter.
  // SICHTBAR wird der Bruch also nur dort, wo die zweite Quelle nicht
  // greift: Baseline aelter als v0.9.8 (kein contextHash), Code innerhalb
  // von drei Zeilen um den Fund ebenfalls geaendert, oder Baseline im
  // anderen PathInFingerprint-Modus geschrieben (dann matcht ohnehin
  // nichts, s. Mismatch-Warnung in Apply).
  // Umgekehrt ist genau das der Wert dieses Zweiges fuer die VIER
  // aufgenommenen Regeln: ihre Zusage haelt auch dann noch, wenn der
  // contextHash NICHT mehr trifft.
  //
  //   SCA013 uLongParamList, LongParamListMaxParams, 10.099 Funde
  //     '%d parameters (limit: %d)'
  //     Strukturell fast wie die vier: setzt MethodName, verankert auf
  //     M.Line. Trotzdem draussen, und zwar auf den ZAHLEN, nicht aus
  //     Vergesslichkeit - an rw20 methodengenau nachgemessen kostete die
  //     Aufnahme 455 verlorene Identitaeten auf 10.099 Funde = 4,5 % im
  //     Pfad-Modus (448 = 4,4 % im Default).
  //     Grund: der Detektor dedupliziert je Datei auf (Name, ParamCount),
  //     Overloads unterscheiden sich also genau in der Zahl, die
  //     wegnormalisiert wuerde. Beispiel Alcinoe.FBX.Client.pas, 'Create':
  //     sechs Funde von '7 parameters' bis '12 parameters' fielen nach
  //     der Normalisierung in EINEN Baseline-Eintrag zusammen.
  //     Im Pfad-Modus ist das das NEUNFACHE der Rate der vier
  //     (183-185/37.990 = 0,49 %); im Default schrumpft der Abstand auf
  //     4,4 % gegen 3,8 %, dort traegt der strukturelle Grund und nicht
  //     die Rate.
  //     443 STAND HIER BIS 2026-08-28 und war um 12 zu niedrig: das
  //     Messskript liess &-maskierte Bezeichner als "kein Methodenkopf"
  //     liegen. Der Lexer dieses Projekts verwirft das '&' und liefert
  //     tkIdent (uLexer.pas:677), 'function &set(...)' heisst also
  //     wirklich 'set'. Betroffen sind zwei JNI-Header aus Kastri:
  //     DW.Androidapi.JNI.AndroidX.Media3.Common.pas mit zwei '&set'-
  //     Overloads (+1) und DW.Androidapi.JNI.Guava.pas mit zwoelf
  //     '&of'-Overloads, die auf EINEN Eintrag fielen (+11).
  //
  //   SCA091 uCaseStatementSize, MaxCaseBranches, 1.944 Funde
  //     '`case` statement with %d branches (>= %d) - consider '
  //     'polymorphism, a dispatch table, or split into smaller cases.'
  //     Das ist der SCA101-Fall, nur kleiner: der Detektor setzt
  //     MethodName := '' und meldet mehrere case-Statements je Datei. Nach
  //     der Normalisierung ist der Meldetext KORPUSWEIT KONSTANT - an rw20
  //     genau ein einziger normalisierter Text -, es bliebe also nichts
  //     mehr, was zwei Funde einer Datei trennt: 621 von 1.944
  //     Identitaeten weg = 31,9 % der Regel im Pfad-Modus (546 = 28,1 %
  //     im Default), 886 Dateien schrumpfen auf je einen Eintrag.
  //
  //   SCA062 uTooLongLine, MaxLineLength
  //     'Line is %d characters (max %d) - wrap or extract subexpression.'
  //     MethodName leer, ein Fund je zu langer Zeile - dieselbe Lage wie
  //     SCA091. Steht als Style-Regel auf fcLow und faellt damit unter der
  //     Default-Schwelle MinConfidence=medium heraus: 0 Funde in rw20,
  //     der Bruch ist deshalb nicht beziffert, aber vorhanden.
  //
  //   SCA021 uDuplicateBlock, DuplicateBlockMinLines, 9.150 Funde
  //     'Code block (lines %d-%d, %d matched lines) appears %dx in file - '
  //     'consider extracting a method'
  //     Schon oben begruendet; zur Groessenordnung: 7.374 der 9.150
  //     Identitaeten fielen weg = 80,6 % im Pfad-Modus (7.119 = 77,8 %
  //     im Default).
  METRIC_DETAIL_KINDS : TFindingKinds =
    [fkCyclomaticComplexity, fkDeepNesting, fkCognitiveComplexity,
     fkLongMethod];

function DigitRunsToPlaceholder(const AText: string): string;
// Jede zusammenhaengende Ziffernfolge wird EIN '#'. '(limit: 10)' und
// '(limit: 12)' fallen damit auf '(limit: #)' zusammen, 'Depth 8' und
// 'Depth 9' auf 'Depth #'.
//
// Handgeschrieben statt TRegEx: die Funktion laeuft je Fund und je
// Filterdurchlauf, und TRegEx-Instanzen sind in diesem Projekt
// nachweislich nicht nebenlaeufig benutzbar (uStaticAnalyzer2,
// TRegExMatches.FCache traegt deshalb die Thread-ID im Schluessel).
var
  I, Len, Dst : Integer;
  Buf         : string;
  InRun       : Boolean;
begin
  Len := Length(AText);
  SetLength(Buf, Len);
  Dst   := 0;
  InRun := False;
  for I := 1 to Len do
  begin
    if (AText[I] >= '0') and (AText[I] <= '9') then
    begin
      // Nur der ERSTE Treffer eines Laufs schreibt - sonst haette
      // '(limit: 10)' zwei Platzhalter und bliebe von '(limit: 9)'
      // unterscheidbar, also genau der Fehler, gegen den es den Zweig gibt.
      if not InRun then
      begin
        Inc(Dst);
        Buf[Dst] := '#';
        InRun := True;
      end;
    end
    else
    begin
      InRun := False;
      Inc(Dst);
      Buf[Dst] := AText[I];
    end;
  end;
  SetLength(Buf, Dst);
  Result := Buf;
end;

class function TBaseline.Fingerprint(const F: TLeakFinding): string;
// GRENZE (Schritte 2-6): letzter FromGlobals-Pfad neben der Facade,
// s. Deklaration.
begin
  Result := Fingerprint(F, TBaselineScope.FromGlobals);
end;

class function TBaseline.Fingerprint(const F: TLeakFinding;
  const AScope: TBaselineScope): string;
var
  Detail : string;
begin
  // Genau EIN Zweig, und er haengt am Kind - nicht am Text. Eine
  // Text-Heuristik ("enthaelt 'limit:'") waere billiger zu schreiben und
  // wuerde bei der naechsten Uebersetzung der Meldung still umkippen.
  if F.Kind in METRIC_DETAIL_KINDS then
  begin
    Detail := DigitRunsToPlaceholder(F.MissingVar);
  end
  else
  begin
    Detail := F.MissingVar;
  end;
  Result := THashSHA2.GetHashString(
    AScope.FileToken(F.FileName) + '|' + KindName(F.Kind) + '|' +
    F.MethodName + '|' + Detail);
end;

function BuildBaselineArray(Findings: TObjectList<TLeakFinding>;
  const AScope: TBaselineScope): TJSONArray;
// Baut das findings[]-Array. Lesefehler bleiben BEWUSST draussen: ein
// I/O-Fehler ist kein akzeptierbarer Befund, sondern eine Aussage ueber
// die Vollstaendigkeit des Laufs - Apply filtert ihn symmetrisch ebenfalls.
var
  Obj     : TJSONObject;
  F       : TLeakFinding;
  CtxMemo : TDictionary<string, string>;
begin
  Result := TJSONArray.Create;
  // Perf (2026-07-05): P3 ContextHash-Memo - caller-scoped Memo fuer diesen
  // Write-Lauf (kein Global): identische (Datei,Zeile) wird nur einmal
  // gelesen + gehasht. Hash-Werte bleiben identisch (deterministisch).
  CtxMemo := TDictionary<string, string>.Create;
  try
    if Assigned(Findings) then
      for F in Findings do
      begin
        if F.Kind = fkFileReadError then Continue; // I/O-Fehler nicht baseline'n
        Obj := TJSONObject.Create;
        Obj.AddPair('file',        AScope.FileToken(F.FileName));
        Obj.AddPair('kind',        KindName(F.Kind));
        Obj.AddPair('method',      F.MethodName);
        Obj.AddPair('detail',      F.MissingVar);
        Obj.AddPair('line',        F.LineNumber);
        Obj.AddPair('fingerprint', TBaseline.Fingerprint(F, AScope));
        // C.2: zusaetzlich Code-Snippet-Hash. Leer wenn Datei nicht lesbar -
        // dann faellt Apply auf den legacy fingerprint zurueck.
        var Ctx := TFindingFingerprint.ContextHashMemo(F, CtxMemo);
        if Ctx <> '' then
          Obj.AddPair('contextHash', Ctx);
        Result.AddElement(Obj);
      end;
  finally
    CtxMemo.Free;
  end;
end;

class function TBaseline.Write(Findings: TObjectList<TLeakFinding>;
  const DestFile: string; const AScope: TBaselineScope): Integer;
var
  Arr  : TJSONArray;
  Root : TJSONObject;
  SL   : TStringList;
begin
  Result := 0;
  if DestFile = '' then Exit;
  Arr := BuildBaselineArray(Findings, AScope);
  // Was wirklich in der Datei landet - NICHT Findings.Count (die
  // Lesefehler sind beim Aufbau uebersprungen worden).
  Result := Arr.Count;

  Root := TJSONObject.Create;
  Root.AddPair('version',     '1');
  // Format-Marker gegen STILLE Vollinvalidierung: liest ein Consumer im
  // anderen Fingerprint-Modus, matcht sonst einfach nichts. Apply
  // erkennt den Mismatch und meldet ihn (AWarnings). Der Marker meldet
  // die WIRKUNG (Effective), nicht den Wunsch (IsPathMode) - bisher
  // stand hier das Modus-Global, und im halb gesetzten Fall (Modus ja,
  // Wurzel leer, Tokens = Dateinamen) log die Datei ueber sich selbst.
  Root.AddPair('pathFingerprint', TJSONBool.Create(AScope.Effective));
  Root.AddPair('createdAt',   FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
  Root.AddPair('count',       TJSONNumber.Create(Arr.Count));
  Root.AddPair('findings',    Arr);

  SL := TStringList.Create;
  try
    // NICHT Root.Format(2) (2026-08-28): Format ruft ToChars mit LEEREN
    // Optionen (System.JSON.pas:1609), und ohne EncodeBelow32 gehen
    // #0..#7, #11 und #14..#31 ROH in die Datei. RFC 8259 par.7 verlangt
    // fuer U+0000..U+001F ein \uXXXX - eine Baseline mit einem einzigen
    // solchen Zeichen ist als GANZES kein gueltiges JSON mehr.
    //
    // Gemessen am Referenzkorpus rw21: 3 von 783.104 Eintraegen trugen
    // die Bytes 0x00/0x04 im detail-Text (zwei JVCL-LED-Demos, ein
    // mORMot-Escaping-Test). Fehlerrate 0,00038 % - Ausfallrate 100 %:
    // python json.load, jq und JSON.parse brechen an der ersten solchen
    // Zeile ab, und damit sind alle 371 MB unbrauchbar. Unser EIGENER
    // Leser merkte davon nichts (Delphis Parser ist toleranter als die
    // Spezifikation und nimmt Bytes < 0x20 unbeanstandet an), weshalb
    // der Defekt vom ersten Commit dieser Unit an (50858f7) unentdeckt
    // blieb. Getroffen hat es jedes FREMDE Werkzeug - und den
    // "Baseline laden"-Knopf im HTML-Report.
    //
    // Der Sonar-Export (fb18279) und der SARIF-Emitter haben denselben
    // Defekt 2026-08-05/06 je fuer sich behoben; hier war er stehen
    // geblieben. JsonFormatEscaped ist die gemeinsame Stelle: gleiches
    // Layout wie Format(2), aber jedes Blatt geht mit EncodeBelow32
    // durch die RTL. Fuer Baeume ohne Steuerzeichen ist die Ausgabe
    // byte-identisch - bestehende Baselines aendern sich also nicht.
    //
    // ESCAPEN, NICHT ERSETZEN: die Escape-Sequenz u0000 liest jeder
    // Parser wieder als das Original-Zeichen zurueck; ein Platzhalter
    // wie <0x00> waere dagegen eine stille Textaenderung. Der
    // Fingerprint haengt an F.MissingVar und wird VOR dieser Zeile
    // berechnet - er bleibt in beiden Faellen gleich, aber nur beim
    // Escapen bleibt auch das detail-Feld die Wahrheit ueber den
    // gescannten Quelltext.
    SL.Text := JsonFormatEscaped(Root, 2);
    EnsureTargetDir(DestFile);
    SaveTextNoBom(SL, DestFile);
  finally
    SL.Free;
    Root.Free; // -> Arr + Objs werden mit befreit
  end;
end;

const
  // Hardening gegen manipulierte Baseline-Dateien:
  //   * MAX_BASELINE_ENTRIES bremst OOM-Angriffe via riesige JSON-Files
  //   * MAX_FINGERPRINT_LEN kappt absurd lange Hash-Strings
  // Werte grosszuegig genug, um realistische Repos zu erfassen (191k
  // Findings sind machbar). Bei Ueberschreitung werden weitere Eintraege
  // ignoriert + Warnung in ErrOutput.
  MAX_BASELINE_ENTRIES = 1_000_000;
  MAX_FINGERPRINT_LEN  = 256;
  // Der contextHash-Schluessel traegt seit 2026-08-28 zusaetzlich den
  // Datei-Token und den Regelnamen AUS DER DATEI - beide waeren sonst
  // ungekappt, waehrend der Hash selbst bei 256 endet. Grosszuegig genug
  // fuer tiefe Relativpfade (MAX_PATH ist 260), eng genug gegen eine
  // praeparierte Datei. Ein laengerer Eintrag wird uebersprungen; sein
  // Fund faellt damit auf den Fingerprint zurueck (fail-open).
  MAX_CONTEXT_KEY_LEN  = 2048;

function TryReadBaselineText(const FileName: string; var AText,
  AReason: string): Boolean;
// Datei einlesen oder den Grund benennen, warum es nicht geht.
begin
  Result  := False;
  AText   := '';
  AReason := '';
  if FileName = '' then
  begin
    AReason := 'no file given';
  end
  else if not FileExists(FileName) then
  begin
    AReason := 'file not found';
  end
  else
  begin
    try
      AText  := TFile.ReadAllText(FileName, TEncoding.UTF8);
      Result := True;
    except
      // noinspection ExceptionTooGeneral
      // Jede Lesefehlerart fuehrt zur selben Antwort ("keine Baseline");
      // die konkrete Ursache steht im Klartext in AReason.
      on E: Exception do
      begin
        AReason := 'unreadable: ' + E.Message;
      end;
    end;
  end;
end;

class function TBaseline.IsBaselineFile(const FileName: string;
  out AReason: string): Boolean;
// Akzeptiert beide Formate, die Apply versteht: Objekt mit 'findings'-
// Array oder das blosse Array (Alt-Format). Alles andere ist keine
// Baseline - mit moeglichst konkreter Begruendung, damit der Nutzer die
// Verwechslung sofort sieht.
var
  Raw  : string;
  Root : TJSONValue;
  Obj  : TJSONObject;
begin
  Result := False;
  if not TryReadBaselineText(FileName, Raw, AReason) then
  begin
    Exit;
  end;
  Root := TJSONObject.ParseJSONValue(Raw);
  if not Assigned(Root) then
  begin
    AReason := 'not valid JSON';
    Exit;
  end;
  try
    if Root is TJSONArray then
    begin
      Result := True;                    // Alt-Format: blosses Array
    end
    else if not (Root is TJSONObject) then
    begin
      AReason := 'JSON root is neither object nor array';
    end
    else
    begin
      Obj := TJSONObject(Root);
      if Obj.Values['findings'] is TJSONArray then
      begin
        Result := True;
      end
      else if Assigned(Obj.Values['runs']) then
      begin
        // Haeufigste Verwechslung beim Namen nennen - ein SARIF-Report
        // sieht einer Baseline auf den ersten Blick aehnlich genug.
        AReason := 'this looks like a SARIF report, not a baseline ' +
                   '(no "findings" array). Baselines are written by ' +
                   '--write-baseline.';
      end
      else
      begin
        AReason := 'no "findings" array - not a baseline written by ' +
                   '--write-baseline';
      end;
    end;
  finally
    Root.Free;
  end;
end;

function BaselineContextKey(const AFileToken, AKindName,
  AContextHash: string): string;
// DER SCHLUESSEL DER CONTEXTHASH-STRECKE. Eine Stelle, drei Nutzer:
// CollectBaselineEntry baut ihn beim LADEN aus den Feldern des Eintrags,
// TBaseline.Apply und TBaselineSet.Contains bauen ihn beim FRAGEN aus dem
// Fund. Waeren es zwei Regeln, traefen sie still daneben - der Filter
// meldete "matcht halt nicht", und niemand saehe warum.
//
// WARUM NICHT DER BLOSSE HASH (Gegenpruefung 2026-08-28, am Korpus rw19
// AUSGEZAEHLT): TFindingFingerprint.ContextHashFor hasht ausschliesslich
// die +/- CONTEXT_HASH_RADIUS normalisierten Quellzeilen - kein Pfad,
// keine Regel, keine Spalte. Er identifiziert ein CODE-FENSTER, keine
// Fundstelle. 782.832 Funde tragen nur 480.268 VERSCHIEDENE Hashes;
// 148.292 Hashes haengen an mehr als einem Fund (57,5 % aller Funde),
// 105.806 davon DATEIUEBERGREIFEND (44,0 %), 42.589 sogar
// REGELUEBERGREIFEND (17,3 %).
// Kollateral eines EINZELNEN Baseline-Eintrags:
//   flacher Schluessel (der Bestand)  : 302.564 Funde = 38,59 %
//   mit Datei im Schluessel           : 115.299       = 14,71 %
//   mit Datei UND Regel, Datei = RELATIVPFAD
//     (nur bei PathInFingerprint=1)   :  47.933       =  6,11 %
//   mit Datei UND Regel, Datei = DATEINAME
//     (DEF_BASELINE_PATH_FINGERPRINT=False, also der DEFAULT):
//                                       214.545       = 27,41 %
//                     davon aus einer FREMDEN Datei: 173.544 = 22,17 %
// 239.018 Funde (30,48 %) waren durch EINEN Eintrag aus einer ANDEREN
// Datei ausblendbar. Belege: eine Vorlagen-Kopfzeile traegt einen
// SCA189-Hash ueber 486 Funde, 1.779 SCA101-Funde haengen an einem Hash,
// und vendorte Kopien (uMain.pas:24 in zwei Baeumen) teilen ihren.
//
// DIE 6,11 % GELTEN NUR IM PFAD-MODUS - im Default ist FileToken der
// BASISNAME (s. TBaselineScope.FileToken), gleichnamige Dateien in
// verschiedenen Baeumen fallen also zusammen: synhighlighterjscript.pas
// haengt mit 604 SCA101-Funden an EINEM Schluessel, verteilt ueber
// Dev-Cpp und HeidiSQL. Das ist KEINE Verschlechterung durch diesen
// Zweig - der Legacy-Fingerprint traegt denselben Basename-Token und
// zieht die Grenze im Default ebensowenig. Ueber ihn HINAUS neu
// ausblendbar sind gemessen 14.015 Funde (1,79 %), davon 4.277 (0,55 %)
// dateiuebergreifend. Wer die Grenze scharf braucht, setzt
// PathInFingerprint=1; dann gelten die 6,11 %.
//
// DIE DATEN LIEGEN IM EINTRAG: BuildBaselineArray schreibt 'file'
// (= AScope.FileToken) und 'kind' (= KindName) in JEDE Zeile; der Frager
// rechnet beides mit seinem Zuschnitt nach.
//
// PREIS "Toleranz gegen Regel-Umbenennung" - GEPRUEFT, kein Verlust: der
// Kind-Name ist im Projekt ein oeffentlicher Bezeichner. Er steht als
// 'kind' in rules/sca-rules.json (uRuleCatalog liest ihn ueber
// KindFromName), in den Profilen und im Baseline-Feld selbst. Vor allem
// aber steckt er BEREITS im Legacy-Fingerprint (s. TBaseline.Fingerprint).
// Eine Umbenennung entwertet also heute schon jede bestehende Baseline auf
// der Fingerprint-Strecke; dass der contextHash sie bisher ueberlebte, war
// kein Vorteil, sondern genau die regeluebergreifende Toleranz aus den
// 17,3 % oben. Wer einen Kind-Namen umbenennt, schreibt die Baselines neu -
// mit oder ohne diesen Schluessel.
begin
  Result := AFileToken + '|' + AKindName + '|' + AContextHash;
end;

function JsonFieldStr(AObj: TJSONObject; const AName: string): string;
// Feldwert als String; '' wenn das Feld fehlt oder null ist. Fehlende
// Felder sind der Normalfall bei handgepflegten Dateien, kein Fehler.
var
  V : TJSONValue;
begin
  Result := '';
  V := AObj.Values[AName];
  if (V <> nil) and not V.Null then
  begin
    Result := V.Value;
  end;
end;

procedure CollectBaselineEntry(AObj: TJSONObject;
  AFpSet, ACtxSet: TDictionary<string, Boolean>);
// Einen Baseline-Eintrag in die beiden Match-Mengen einsortieren, inkl.
// der Hardening-Kappung. Gemeinsam fuer TBaseline.Apply und
// TBaselineSet.LoadFromFile: bis 2026-08-28 stand die Feldregel zweimal
// im File, und genau die zweite Kopie holte den contextHash nicht - der
// Anzeige-Filter warf beim Laden weg, was Write hineingeschrieben hatte.
// Ein einzelnes Set darf nil sein (Aufrufer, der nur eines fuellt).
//
// Der Unterschied zwischen den beiden Zweigen ist kein Versehen: ein
// leerer contextHash bedeutet "nicht berechenbar" (Datei nicht lesbar)
// und darf nie als Match-Wert in die Menge, waehrend beim Fingerprint
// die Bestandsform ohne Leer-Pruefung erhalten bleibt.
//
// Der contextHash geht QUALIFIZIERT hinein - Datei und Regel aus DEMSELBEN
// Eintrag (BaselineContextKey). Fehlt eines der beiden Felder (nur von
// Hand moeglich; TBaseline.Write schreibt immer beide), bleibt der
// jeweilige Teil leer und der Eintrag trifft praktisch keinen Fund mehr.
// Das ist die fail-open-Richtung: er blendet dann nichts aus, statt zu
// viel - die gefaehrliche Richtung ist die andere.
var
  V      : TJSONValue;
  CtxKey : string;
begin
  if Assigned(AFpSet) then
  begin
    V := AObj.Values['fingerprint'];
    if (V <> nil) and not V.Null
       and (Length(V.Value) <= MAX_FINGERPRINT_LEN) then
      AFpSet.AddOrSetValue(V.Value, True);
  end;
  if Assigned(ACtxSet) then
  begin
    V := AObj.Values['contextHash'];
    if (V <> nil) and not V.Null
       and (V.Value <> '')
       and (Length(V.Value) <= MAX_FINGERPRINT_LEN) then
    begin
      CtxKey := BaselineContextKey(JsonFieldStr(AObj, 'file'),
                                   JsonFieldStr(AObj, 'kind'), V.Value);
      if Length(CtxKey) <= MAX_CONTEXT_KEY_LEN then
        ACtxSet.AddOrSetValue(CtxKey, True);
    end;
  end;
end;

class function TBaseline.Apply(Findings: TObjectList<TLeakFinding>;
  const BaselineFile: string; const AScope: TBaselineScope;
  AWarnings: TStrings): Integer;
// Match-Strategie (C.2):
//   1. Wenn Finding einen contextHash hat UND der - mit Datei und Regel
//      qualifiziert - in der Baseline ist -> Drop (stabilster Pfad,
//      ueberlebt Line-Drift + Re-Indent).
//   2. Sonst: legacy fingerprint pruefen (File+Kind+Method+Detail).
//   Backward-compat: alte Baselines ohne contextHash matchen weiter via 2.
//
// VERHALTENSAENDERUNG 2026-08-28 - AUSDRUECKLICH DEKLARIERT. Stufe 1
// verglich bis dahin den NACKTEN Hash. Das ist ein BESTANDSFEHLER, seit
// v0.9.8 auf dem CI-Pfad produktiv, und er entsteht nicht erst durch den
// Anzeige-Filter-Umbau. Ein einzelner Baseline-Eintrag blendete damit
// jeden Fund im ganzen Scan aus, dessen 7-Zeilen-Fenster textgleich ist -
// quer ueber Dateien und Regeln. Am Korpus rw19 ausgezaehlt: 302.564 Funde
// (38,59 %) waren Kollateral eines einzelnen Eintrags, 239.018 davon
// (30,48 %) aus einer ANDEREN Datei; mit Datei und Regel im Schluessel
// bleiben 47.933 (6,11 %). Zahlen und Herleitung: BaselineContextKey.
//
// WAS DAS FUER BESTEHENDE BASELINES HEISST: bisher zu tolerante Matches
// fallen weg, es koennen also Funde ERSCHEINEN, die vorher ausgeblendet
// waren - der Zaehler eines CI-Gates kann steigen, ohne dass sich am Code
// etwas geaendert hat. Das ist die Korrektur des Fehlers, kein Regress.
// Zusaetzlich ausgeblendet wird NICHTS.
// Zweite Folge: der contextHash traegt jetzt den Datei-Token und ueberlebt
// damit einen Fingerprint-MODUS-Wechsel nicht mehr. Bisher rettete er in
// diesem Fall die ganze Datei; jetzt matcht bei Modus-Differenz gar
// nichts - genau das sagt die Mismatch-Warnung unten.
var
  Raw       : string;
  Root      : TJSONValue;
  Arr       : TJSONArray;
  Obj       : TJSONValue;
  FpSet     : TDictionary<string, Boolean>;
  CtxSet    : TDictionary<string, Boolean>;
  CtxMemo   : TDictionary<string, string>;
  i         : Integer;
  F         : TLeakFinding;
  FCtx      : string;
begin
  Result := 0;
  CtxMemo := nil;
  if (Findings = nil) or (BaselineFile = '') then Exit;
  if not FileExists(BaselineFile) then Exit;

  Raw := TFile.ReadAllText(BaselineFile, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Raw);
  if Root = nil then Exit;

  FpSet  := TDictionary<string, Boolean>.Create;
  CtxSet := TDictionary<string, Boolean>.Create;
  try
    if Root is TJSONObject then
    begin
      // Fingerprint-Modus-Marker pruefen: Datei im anderen Modus
      // geschrieben -> die Datei-Tokens der Datei passen nicht zu denen,
      // die dieser Leser bildet. Verglichen wird mit der WIRKUNG des
      // uebergebenen Zuschnitts (Effective), symmetrisch zu dem, was Write
      // in den Marker stellt.
      // Der Satz "nur contextHash greift noch" stimmte bis 2026-08-28 und
      // ist seither FALSCH: der Datei-Token steckt jetzt auch im
      // contextHash-Schluessel (BaselineContextKey). Bei Modus-Differenz
      // matcht gar nichts mehr - und das muss die Meldung sagen, sonst
      // wiegt sie den Leser in Sicherheit.
      var MarkerVal := TJSONObject(Root).Values['pathFingerprint'];
      if (MarkerVal is TJSONBool) and Assigned(AWarnings) and
         (TJSONBool(MarkerVal).AsBoolean <> AScope.Effective) then
        AWarnings.Add(Format(
          'baseline fingerprint mode mismatch: file written with ' +
          'PathInFingerprint=%s, current setting is %s - NOTHING will ' +
          'match (both the legacy fingerprint and the context hash carry ' +
          'the file token). Re-write the baseline in the current mode.',
          [BoolToStr(TJSONBool(MarkerVal).AsBoolean, True),
           BoolToStr(AScope.Effective, True)]));
      // Weicher Cast: 'findings' kann fehlen (Values liefert nil) ODER falsch
      // typisiert sein (manuell editiert / Merge-Konflikt: "findings": {}).
      // Hartes 'as TJSONArray' wuerfe dann EInvalidCast und deaktivierte die
      // Baseline still komplett - stattdessen als "kein Array" behandeln.
      var FindingsVal := TJSONObject(Root).Values['findings'];
      if FindingsVal is TJSONArray then
        Arr := TJSONArray(FindingsVal)
      else
        Arr := nil;
    end
    else if Root is TJSONArray then
      Arr := TJSONArray(Root)            // Alt-Format: rein das Array
    else
      Arr := nil;

    if Arr <> nil then
    begin
      var Loaded := 0;
      var Truncated := False;
      for Obj in Arr do
      begin
        if Loaded >= MAX_BASELINE_ENTRIES then
        begin
          Truncated := True;
          Break;
        end;
        if not (Obj is TJSONObject) then Continue;
        Inc(Loaded);
        CollectBaselineEntry(TJSONObject(Obj), FpSet, CtxSet);
      end;
      if Truncated then
        try
          WriteLn(ErrOutput, Format(
            'Baseline warning: file %s has more than %d entries - '
            + 'subsequent entries ignored (truncated). Hardening cap, '
            + 'see MAX_BASELINE_ENTRIES in uBaseline.pas.',
            [BaselineFile, MAX_BASELINE_ENTRIES]));
        except
          // stdout/stderr nicht erreichbar (GUI ohne AttachConsole) -
          // silent OK, Hardening greift trotzdem.
        end;
    end;

    // Rueckwaerts iterieren wegen Delete.
    // Perf: ContextHash nur berechnen wenn die Baseline ueberhaupt
    // contextHash-Eintraege hat. Bei Legacy-Baselines (nur fingerprint)
    // spart das ein SHA256 + File-Read pro Finding (= ~191k vermiedene
    // Operationen bei einem Real-World-Scan).
    // Perf (2026-07-05): P3 ContextHash-Memo - zusaetzlich wird innerhalb
    // dieses Apply-Laufs jede (Datei,Zeile) nur einmal gehasht (CtxMemo,
    // caller-scoped, im finally freigegeben).
    var HasCtx: Boolean := CtxSet.Count > 0;
    if HasCtx then
      CtxMemo := TDictionary<string, string>.Create;
    for i := Findings.Count - 1 downto 0 do
    begin
      F := Findings[i];
      if F.Kind = fkFileReadError then Continue;
      if HasCtx then
        FCtx := TFindingFingerprint.ContextHashMemo(F, CtxMemo)
      else
        FCtx := '';
      // Qualifiziert nachschlagen - Datei und Regel dieses Fundes, mit dem
      // Zuschnitt DIESES Lesers gerechnet (s. BaselineContextKey).
      if ((FCtx <> '') and CtxSet.ContainsKey(BaselineContextKey(
            AScope.FileToken(F.FileName), KindName(F.Kind), FCtx)))
         or FpSet.ContainsKey(Fingerprint(F, AScope)) then
      begin
        Findings.Delete(i);     // owns - F wird freigegeben
        Inc(Result);
      end;
    end;
  finally
    FpSet.Free;
    CtxSet.Free;
    CtxMemo.Free;
    Root.Free;
  end;
end;

{ TBaselineSet }

constructor TBaselineSet.Create;
begin
  inherited Create;
  FFingerprints  := TDictionary<string, Boolean>.Create;
  FContextHashes := TDictionary<string, Boolean>.Create;
  FCtxByLine     := TDictionary<string, string>.Create;
  FPreparedCtx   := 0;
end;

destructor TBaselineSet.Destroy;
begin
  FCtxByLine.Free;
  FContextHashes.Free;
  FFingerprints.Free;
  inherited;
end;

procedure TBaselineSet.Clear;
// Leert die Match-Mengen AUS DER DATEI. Der vorab gerechnete Hash-Speicher
// bleibt bewusst stehen: er gehoert zum Scan, nicht zur Baseline-Datei.
// Beide Consumer rufen Clear auch dann, wenn der Filter nur voruebergehend
// aus ist (Haken weg, Datei gerade nicht auffindbar) - wuerde der Speicher
// hier mitfallen, verloere ein Aus-und-wieder-Ein-Schalten die
// contextHash-Strecke bis zum naechsten Scan. Weg ist er beim naechsten
// PrepareContextHashes, das ihn immer zuerst verwirft - oder auf
// ausdrueckliche Anforderung ueber ReleaseContextHashes.
begin
  FFingerprints.Clear;
  FContextHashes.Clear;
end;

procedure TBaselineSet.ReleaseContextHashes;
// Siehe Deklaration: das ist der Weg, ueber den die gemessenen ~220 MB
// zurueckkommen. TDictionary.Clear gibt das Bucket-Array frei, ein
// Neuanlegen waere ueberfluessig.
begin
  FCtxByLine.Clear;
  FPreparedCtx := 0;
end;

function TBaselineSet.IsEmpty: Boolean;
// Beide Match-Quellen zaehlen. Praktisch entscheidet weiter die
// Fingerprint-Menge (Write legt in JEDEN Eintrag einen Fingerprint); eine
// handgepflegte Datei mit ausschliesslich contextHashes soll aber nicht
// als "nichts geladen" gelten und den Filter still abschalten.
begin
  Result := (FFingerprints.Count = 0) and (FContextHashes.Count = 0);
end;

function TBaselineSet.Contains(const F: TLeakFinding): Boolean;
var
  Ctx : string;
begin
  // Lesefehler sind nie baseline-faehig - dieselbe Regel, die Write (:209)
  // und Apply (:459) schon befolgen. Dem ANZEIGE-Filter in EXE und Plugin
  // fehlte sie bis 2026-08-08: eine handgepflegte oder aeltere Baseline mit
  // einem FileReadError-Fingerprint konnte dort einen unlesbaren Dateipfad
  // ausblenden, waehrend die CLI ihn weiter meldete. Ein Lauf, der Dateien
  // nicht lesen konnte, darf nirgends vollstaendig aussehen.
  if F.Kind = fkFileReadError then Exit(False);
  // 1. contextHash - die stabilere Quelle, sie ueberlebt Zeilen-Drift,
  //    Re-Indent, Methoden-Rename UND jede Aenderung am Detailtext (Score,
  //    Schwellwert). Ausschliesslich aus dem vorab gefuellten Speicher:
  //    kein Treffer heisst "nicht gerechnet", NICHT "kein Hash" - hier
  //    wird niemals eine Datei gelesen, s. Klassenkommentar. Die beiden
  //    Count-Guards halten den heissen ApplyFilter-Loop frei von der
  //    Schluesselbildung, solange eine der beiden Seiten leer ist.
  //    Nachgeschlagen wird QUALIFIZIERT (Datei + Regel + Hash, s.
  //    BaselineContextKey): der blosse Hash blendete jeden Fund mit
  //    textgleichem Code-Fenster aus, auch in fremden Dateien und unter
  //    fremden Regeln. Der Datei-Token kommt aus FScope - demselben
  //    Zuschnitt, mit dem LoadFromFile die Eintraege eingelesen hat.
  if (FContextHashes.Count > 0) and (FCtxByLine.Count > 0)
     and FCtxByLine.TryGetValue(TFindingFingerprint.MemoKey(F), Ctx)
     and (Ctx <> '')
     and FContextHashes.ContainsKey(BaselineContextKey(
           FScope.FileToken(F.FileName), KindName(F.Kind), Ctx)) then
  begin
    Exit(True);
  end;
  // 2. Legacy-Fingerprint wie bisher - dieselbe EITHER/OR-Reihenfolge, die
  //    TBaseline.Apply anwendet.
  // Count-Guard spart bei leerem Set (Filter aus / Datei fehlt) das SHA2-
  // Hashing pro Finding im heissen ApplyFilter-Loop.
  // Fingerprint mit dem in LoadFromFile gespeicherten Zuschnitt - nicht
  // mit den Prozess-Globals: die Abfrage muss zum LADEZEITPUNKT passen,
  // egal was ein spaeterer Lauf an den Globals gedreht hat.
  Result := (FFingerprints.Count > 0)
            and FFingerprints.ContainsKey(TBaseline.Fingerprint(F, FScope));
end;

function TBaselineSet.ComputeContextHashes(
  AFindings: TObjectList<TLeakFinding>; AForceStat: Boolean): Integer;
// Gemeinsamer Rumpf der beiden Vorab-Rechnungen. ContextHashMemo legt das
// Ergebnis selbst in FCtxByLine ab - auch das leere, damit eine unlesbare
// Datei nicht bei jedem Fund erneut angefasst wird.
var
  F : TLeakFinding;
begin
  Result := 0;
  if not Assigned(AFindings) then Exit;
  for F in AFindings do
  begin
    // Symmetrisch zu Write/Apply/Contains: ein Lesefehler ist kein
    // akzeptierbarer Befund und bekommt hier gar keinen Hash.
    if F.Kind = fkFileReadError then Continue;
    if TFindingFingerprint.ContextHashMemo(F, FCtxByLine, AForceStat) <> '' then
      Inc(Result);
  end;
end;

function TBaselineSet.PrepareContextHashes(
  AFindings: TObjectList<TLeakFinding>): Integer;
begin
  Result := 0;
  // IMMER zuerst verwerfen, auch wenn gleich ausgestiegen wird - s.
  // Deklaration: ein Eintrag aus dem letzten Scan vergliche einen frischen
  // Fund mit dem Hash von altem Code. Das gibt zugleich den Speicher
  // zurueck, sobald ein Scan ohne Baseline laeuft.
  ReleaseContextHashes;
  // Keine contextHashes in der Datei (Baseline aelter als v0.9.8, oder
  // Alt-Format): es gaebe nichts, wogegen zu matchen waere. Dann auch
  // nicht rechnen - dieselbe Ersparnis wie der HasCtx-Zweig in Apply.
  if FContextHashes.Count = 0 then Exit;
  // AForceStat=False: die Bytes liegen noch im Text-Cache des gerade
  // beendeten Scans, und seither hat sie niemand ueberschrieben. Genau die
  // Annahme, die der SARIF-Export im selben Nachlauf schon macht - sie
  // spart zwei Syscalls je Fund.
  Result := ComputeContextHashes(AFindings, False);
  FPreparedCtx := Result;
end;

function TBaselineSet.RefreshContextHashesForFile(const AFileName: string;
  AFindings: TObjectList<TLeakFinding>): Integer;
var
  F     : TLeakFinding;
  Key   : string;
  Stale : TDictionary<string, Boolean>;
  Dead  : TList<string>;
begin
  Result := 0;
  // Nie gerechnet -> nichts zu pflegen. Contains faellt dann ohnehin auf
  // den Fingerprint zurueck, und ein Teil-Nachtrag waere irrefuehrend.
  if (FCtxByLine.Count = 0) or (FContextHashes.Count = 0) then Exit;
  // WELCHE Dateien geleert werden, sagen DIE FUNDE - nicht der Parameter.
  // Ein Watch-Lauf liefert auch Funde fremder Dateien (DFM-Detektoren
  // melden mit dem .dfm-Pfad, s. Deklaration); deren Eintraege stammen
  // ebenso aus dem Stand VOR der Aenderung. Weil Loesch- und
  // Rechenschluessel damit aus derselben Quelle kommen, kann die
  // Schreibweise gar nicht mehr auseinanderlaufen.
  // AFileName kommt zusaetzlich hinein: liefert der Lauf fuer die
  // ausloesende Datei jetzt GAR keine Funde mehr, stuenden ihre alten
  // Eintraege sonst weiter im Speicher.
  Stale := TDictionary<string, Boolean>.Create;
  Dead  := TList<string>.Create;
  try
    Stale.AddOrSetValue(TFindingFingerprint.MemoKeyFile(AFileName), True);
    if Assigned(AFindings) then
    begin
      for F in AFindings do
      begin
        Stale.AddOrSetValue(
          TFindingFingerprint.MemoKeyFile(F.FileName), True);
      end;
    end;
    for Key in FCtxByLine.Keys do
    begin
      if Stale.ContainsKey(TFindingFingerprint.FileOfMemoKey(Key)) then
        Dead.Add(Key);
    end;
    for Key in Dead do
    begin
      FCtxByLine.Remove(Key);
    end;
  finally
    Dead.Free;
    Stale.Free;
  end;
  // AForceStat=True, anders als im Scan-Nachlauf: diese Datei hat sich
  // gerade geaendert, ein Cache-Snapshot koennte veraltet sein. Es geht um
  // die Funde EINER Datei - zwei Syscalls je Fund fallen hier nicht ins
  // Gewicht.
  Result := ComputeContextHashes(AFindings, True);
end;

function TBaselineSet.LoadFromFile(const BaselineFile: string;
  const AScope: TBaselineScope): Integer;
// Parst dieselbe Struktur wie TBaseline.Apply (Objekt-mit-'findings' ODER bare
// Array) + dieselben Hardening-Caps, aber non-destruktiv: sammelt nur die
// Match-Werte. Bewusst als eigener Parse gehalten statt Apply umzubauen -
// Apply ist der verifizierte CI-Gating-Pfad. Die FELDREGEL teilen sich
// beide seit 2026-08-28 in CollectBaselineEntry: genau ihre Verdopplung war
// der Grund, warum hier der contextHash fehlte, waehrend Apply ihn seit
// v0.9.8 auswertete. Weil die Regel jetzt geteilt ist, gilt auch die
// Schluessel-Qualifizierung (Datei + Regel) fuer BEIDE Leser - deshalb ist
// Apply diesmal NICHT verhaltensneutral geblieben, s. dort.
var
  Raw    : string;
  Root   : TJSONValue;
  Arr    : TJSONArray;
  Obj    : TJSONValue;
  Loaded : Integer;
begin
  // Nur die Datei-Seite zuruecksetzen. Der vorab gerechnete Hash-Speicher
  // ueberlebt: die EXE ruft RefreshBaselineSet bei JEDEM Filterwechsel,
  // und ein Verwerfen hier haette die Vorab-Rechnung schon beim ersten
  // ApplyFilter nach dem Scan wieder entwertet. Wer ihn wirklich los
  // werden will, ruft ReleaseContextHashes (s. dort).
  FFingerprints.Clear;
  FContextHashes.Clear;
  // Zuschnitt VOR den Ausstiegen speichern: auch ein leeres Set (Datei
  // fehlt/kaputt) antwortet danach konsistent mit dem Zuschnitt dieses
  // Ladeversuchs statt mit dem eines frueheren.
  FScope := AScope;
  Result := 0;
  if BaselineFile = '' then Exit;
  if not FileExists(BaselineFile) then Exit;

  try
    Raw := TFile.ReadAllText(BaselineFile, TEncoding.UTF8);
  except
    Exit;   // nicht lesbar -> leeres Set (kein Fehler)
  end;
  Root := TJSONObject.ParseJSONValue(Raw);
  if Root = nil then Exit;
  try
    if Root is TJSONObject then
    begin
      var FindingsVal := TJSONObject(Root).Values['findings'];
      if FindingsVal is TJSONArray then
        Arr := TJSONArray(FindingsVal)
      else
        Arr := nil;
    end
    else if Root is TJSONArray then
      Arr := TJSONArray(Root)
    else
      Arr := nil;

    if Arr <> nil then
    begin
      Loaded := 0;
      for Obj in Arr do
      begin
        if Loaded >= MAX_BASELINE_ENTRIES then Break;
        if not (Obj is TJSONObject) then Continue;
        Inc(Loaded);
        CollectBaselineEntry(TJSONObject(Obj), FFingerprints, FContextHashes);
      end;
    end;
  finally
    Root.Free;
  end;
  Result := FFingerprints.Count;
end;

const
  SCA_DIR      = '.sca';
  BASELINE_EXT = '.baseline.json';

// Kandidat pruefen + fuer die Fehlermeldung protokollieren.
function ProbeBaselineCandidate(const Candidate: string;
  AProbed: TStrings): Boolean;
begin
  if Assigned(AProbed) then
    AProbed.Add(Candidate);
  Result := FileExists(Candidate);
end;

class function TBaseline.ResolveBaselinePath(const AProjectOrGroupFile,
  AScanRoot: string; AProbed: TStrings): string;
var
  Dir, BaseName, Cand : string;
begin
  Result := '';
  if AProjectOrGroupFile <> '' then
  begin
    Dir      := ExtractFilePath(ExpandFileName(AProjectOrGroupFile));
    BaseName := ChangeFileExt(ExtractFileName(AProjectOrGroupFile), '');
    Cand := Dir + SCA_DIR + PathDelim + BaseName + BASELINE_EXT;
    if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
    // Projekt-Fallback: zentrale Gruppen-.sca eine Ebene hoeher.
    if SameText(ExtractFileExt(AProjectOrGroupFile), '.dproj') then
    begin
      Cand := ExpandFileName(Dir + '..' + PathDelim + '.sca' + PathDelim +
        BaseName + '.baseline.json');
      if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
    end;
    Exit;
  end;
  if AScanRoot <> '' then
  begin
    Cand := IncludeTrailingPathDelimiter(ExpandFileName(AScanRoot)) +
      SCA_DIR + PathDelim + 'sca' + BASELINE_EXT;
    if ProbeBaselineCandidate(Cand, AProbed) then Exit(Cand);
  end;
end;

class function TBaseline.DefaultBaselineTarget(const AProjectOrGroupFile,
  AScanRoot: string): string;
begin
  Result := '';
  if AProjectOrGroupFile <> '' then
    Result := ExtractFilePath(ExpandFileName(AProjectOrGroupFile)) +
      SCA_DIR + PathDelim +
      ChangeFileExt(ExtractFileName(AProjectOrGroupFile), '') +
      BASELINE_EXT
  else if AScanRoot <> '' then
    Result := IncludeTrailingPathDelimiter(ExpandFileName(AScanRoot)) +
      SCA_DIR + PathDelim + 'sca' + BASELINE_EXT;
end;

end.
