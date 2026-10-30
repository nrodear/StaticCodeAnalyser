unit uRdxMagicFixes;

// reDelphix - Quick-Fix SCA014 MagicNumber "Lokale Konstante einfuehren"
// (Charge Q14, Entscheid E28), OHNE ToolsAPI und ohne Parser (laeuft auch
// im FPC-Pruefstand). Aus 'if Count > 200 then' wird
//     const MagicNr01 = 200;
//     if Count > MagicNr01 then
// - die Inline-Konstante als eigene Anweisung direkt vor der Anweisung mit
// dem Literal (E26), ein Zweig ohne begin bekommt begin..end (Nico, Fall
// 3). WAS geschrieben wird, rechnet die Code-Aktion "Lokale Konstante
// einfuehren" (uRdxIntroPlan/uRdxIntroEdits, 1:1 aus dem Labor
// VarNameProject): TargetAt mit dem Literal als Caret, IntroduceEdits.
// Anders als im Labor (E28): KEINE Sync-Edit-Sitzung - die Hilfe schreibt
// nur die Ersetzung, ueber den Schreibweg der Tabelle (PlanByteEdits, ein
// Undo-Schritt); umbenennen kann man danach selbst, von Hand oder mit
// Refactor > Rename (Strg+Umschalt+E) - nicht Sync Edit: Esc zerstoert
// dort Text (UI-Test 2026-10-11), und Strg+Umschalt+J braucht eine
// Markierung (Gegen-Review Q14, Minor 13). Und nur DAS eine Literal des
// Funds, nicht alle gleichen der Zeile (E28: "nur eines, sonst sperren").
//
// WAS DER DETEKTOR MELDET (uMagicNumbers gelesen): nur in if-Bedingungen,
// je if hoechstens EINEN Fund, auf der Zeile des 'if'. Er sucht im
// Bedingungstext (Token mit Leerzeichen getrennt, ohne Kommentare, Strings
// geblankt) einen Vergleich ('>=', '<=', '<>', '>', '<', '=' - in dieser
// Reihenfolge, nicht nach Spalte) und dahinter eine Ganzzahl, die nicht
// trivial ist. Nie: Hex ('$FF' - keine Ziffer), Float ('3.5', '1e3' -
// uebersprungen), ein Vorzeichen ('-5': der Lexer trennt '-' ab, im
// Bedingungstext steht '- 5') und ein Literal in Klammern ('> (200)').
// Bei '200_000' (auch '200_000.5') meldet er "200" (der Lexer liest
// '_000' als Bezeichner) - ein Fehlalarm: das Literal heisst anders, die
// Hilfe findet es nicht.
//
// ZIEL AUS DEM FUND (der Planer prueft nach, statt dem Detektor zu
// glauben): die Zahl aus der Meldung; auf der Fundzeile jede if-Bedingung
// vom 'if' bis zu ihrem 'then' (auch ueber Folgezeilen); darin die
// Zahl-Token mit genau diesem Text, direkt hinter einem Vergleich (kein
// Teil von '200.5', '$200', '#200', '-200', '200_000'). Genau einer: das
// Ziel. Keiner: Zeile verschoben - ausser es steht dort ein Vergleichswert
// mit Zifferntrennern, dessen erster Block die Zahl ist (auch mit
// Bruchteil): dann nennt der Grund den Fehlalarm (Review R6-05;
// Korpus: 1 von 5.036, ISSigFunc.pas).
// Mehrere - oder einer neben einem solchen Trennerwert: mehrdeutig
// (gesperrt - der Detektor meldete danach den naechsten, und welches er
// meinte, sagt die Meldung nicht). Steht der
// eine in einer Folgezeile der Bedingung: die
// Konstante gehoerte vor die if-Zeile, die Code-Aktion setzt sie vor die
// Zeile des Literals - gesperrt.
//
// SPERREN dazu: alle der Code-Aktion (TargetAt: mehrzeilige Strings und
// Kommentare, asm, initialization, FPC-Weiche, Direktiven, Kopf-
// Fortsetzungen, case-Zweig/Sprungmarke/on-Handler, 'else if' u. a. -
// was der Zeilen-Leser nicht sicher abgrenzt). Dazu, weil eine Inline-
// Konstante erst ab Delphi 10.3 uebersetzt und FPC 3.2 sie gar nicht
// kennt - eine Datei, die ein anderer Compiler baut, braeche:
//   * Skript-Units ohne implementation-Teil (xEdit, JvInterpreter),
//     Spuren von Compilern vor 10.3 in der Datei (uRdxCompilerTraces,
//     FLOOR_INLINE_DECL) und der Hauptblock eines Programms bzw. einer
//     Bibliothek (ob dort eine Inline-Deklaration gilt, ist ohne Delphi
//     nicht gemessen; Gegen-Review Q14, Verdacht d) - hier im Planer;
//   * was nur die Platte weiss, im Check der Tabelle (MagicCheck): eine
//     Lazarus-Dateiart bzw. ein Lazarus-Projekt oder -Paket neben der Unit,
//     eine alte Delphi-Projektdatei (.dof, .bdsproj, .bpr, .bpg) oder eine
//     .dproj vor 10.3 (ProjectVersion < 18.5) - Major 3: CnWizards, JVCL
//     und GExperts tragen keine Versionsweiche in der Unit, die Version
//     steht im Projekt (FileReason), seit rwE29 auch ein Paket (.dpk) im
//     Unterordner packages, das die Unit enthaelt und nach Ordnername bzw.
//     LIBSUFFIX fuer ein aelteres Delphi ist (PackagesReason) - und
//     FPC-Weichen oder alte Spuren in
//     den Includes, auch ein Include, das nicht neben der Unit liegt
//     (IncludeReason). Auf einem Netzpfad (UNC) bzw. Netzlaufwerk liest die
//     Hilfe nichts von der Platte - der Menueaufbau laeuft im Hauptthread
//     (Verdacht e): sie lehnt ab; seit Charge B1-FD gilt das auch fuer
//     ein Include auf einem Netzpfad in einer lokalen Unit
//     ('{$I \\server\share\defs.inc}' wartete 9 bis 16 s, Gegen-Review
//     R4-03; Regel uRdxPaths.IsNetworkPath, geprueft vor jedem
//     FileExists). Zwischengespeichert wird nichts: je
//     Aufruf liest FileReason hoechstens drei Verzeichnisse und die Koepfe
//     ihrer .dproj (Korpus-Harness, FPC: 1.010 Aufrufe in 231 ms, 0,2 ms
//     je Fund; IncludeReason mit den Includes rund 7 ms) - ein Cache
//     braechte veralteten Zustand, wenn eine Projektdatei dazukommt.
//   Den Plattenblick nutzt auch SCA069 (Zifferntrenner, ab Delphi 11):
//     FileReason und IncludeReason nehmen seit der Integration QFI2 das
//     Sprachmittel (TRdxLateFeature) - es waehlt die Schwelle
//     (FLOOR_INLINE_DECL bzw. FLOOR_DIGIT_SEP) und den Grundtext; fuer
//     SCA014 (lfInlineConst) bleiben Schwelle und Texte, wie sie waren.
//     Seit der Integration QFI3 auch SCA111/SCA112 (lfInlineVar: die
//     Inline-Variable vor der Schleife - dieselbe Schwelle 10.3, ein
//     eigener Grundtext).
// Korpus Q14 (5.036 Funde): FPC-Weiche in der Datei 1.724, alte Spur 1.275,
// in einem Include 63 + 108, Include fehlt 55, Lazarus-Projekt 88, Skript
// 18 - ohne Skript- und Plattenpruefung waeren es 1.024 statt 696
// Angebote gewesen; die alten Delphi-Projekte (Charge SQc) nehmen davon
// noch 120 weg (alte Projektdatei ohne .dproj 111 - CnWizards 72, JVCL
// 37 -, .dproj vor 10.3 9): 576 Angebote.
// GANZE DATEI ODER STELLE (Entscheid Nico 2026-10-24, nur die Code-Aktion
// ohne Fund): FPC-Weiche, Skript, Spuren alter Compiler (FileWideReason)
// und der ganze Plattenblick sperren die Datei - dort zeigt das
// Kontextmenue keinen Eintrag; alle anderen Sperren (Zeilen-Leser,
// Hauptblock, Binaer-/Oktal-Literal) haengen an der Stelle und stehen
// ausgegraut mit Grund da. Die Fund-Hilfe SCA014 nennt weiter jeden Grund
// in der bisherigen Reihenfolge.
// TRIVIALE LITERALE (Entscheid Nico 2026-10-24, nur die Code-Aktion ohne
// Fund): ein Literal, das SCA014 als trivial durchliesse, bekommt keinen
// Eintrag - wie "kein Kandidat" (Korpus B3: 148 von 226 Angeboten waren
// 0, 1 oder 2). Dieselbe Menge wie TMagicNumberDetector.IsTrivial
// (SCA.Engine\sources\Detectors\uMagicNumbers.pas): die Liste
// [Detectors] MagicNumberTrivials mit ihrem Vorgabewert 0,1,2,-1,10,100
// (TRepoSettings, SCA.Engine\sources\Infrastructure\uRepoSettings.pas)
// und immer die Zweierpotenzen bis 1024. reDelphix liest die
// Engine-Konfiguration nicht: hier steht der VORGABEWERT gespiegelt
// (SCA014_TRIVIALS) - eine eigene Liste in der analyser.ini sieht die
// Code-Aktion nicht. Wie SCA014 nur dezimale Ganzzahlen ('0', '16'):
// Hex, Binaer, Bruch, Exponent und Zifferntrenner sieht der Detektor nie
// als Zahl, sie bleiben Kandidaten ('$1', '1.0', '1_000'). Ein '-' direkt
// vor dem Literal, wo ein Operand beginnt ('X := -1', '(-1)'), gehoert zum
// Wert - '-1' ist trivial, '-10' nicht (IsTrivial vergleicht den Text mit
// Vorzeichen; Zweierpotenzen nur positiv). Die Fund-Hilfe SCA014 laeuft
// nur, wo SCA014 meldete - dort ist das Literal nie trivial.
//
// NAME: MagicNr01, MagicNr02 ... - der erste, der in der Datei nicht als
// ganzes Wort vorkommt (uRdxIntroPlan.NextFreeName, wie im Labor; auch
// Kommentare und Strings zaehlen - strenger als noetig).

interface

uses
  System.Generics.Collections,   // TDictionary (TRdxDiskReasonCache)
  uRdxBufferMath, uRdxCodeMap;

const
  // Der Name der Konstante ohne Nummer (wie im Labor: MagicNr01 ...).
  MAGIC_NAME_BASE = 'MagicNr';
  // So viele .dpk-Koepfe liest FileReason je Aufruf hoechstens (Pakete,
  // die die Unit enthalten, rwE29). Bleibt danach eine .dpk in einem alten
  // oder unbekannten Paketordner ungelesen, sperrt FileReason - lieber keine
  // Hilfe als eine falsche (Review e/HilfeFixB: in JVCL frass packages\c6
  // mit 59 .dpk den Deckel, und d6/d7/d10 wurden nie gelesen).
  MAX_PACKAGE_READS = 64;

type
  // Was die Hilfe schreibt, die den Plattenblick braucht (FileReason,
  // IncludeReason): es waehlt die Schwelle und den Grundtext.
  //   lfInlineConst     SCA014 Inline-Konstante, ab Delphi 10.3
  //                     (FLOOR_INLINE_DECL)
  //   lfDigitSeparator  SCA069 Zifferntrenner, ab Delphi 11
  //                     (FLOOR_DIGIT_SEP; Integration QFI2)
  //   lfInlineVar       SCA111/SCA112 Inline-Variable, ab Delphi 10.3
  //                     wie die Inline-Konstante (FLOOR_INLINE_DECL;
  //                     Integration QFI3 - bis dahin haetten ihre Gruende
  //                     die Inline-Konstante genannt)
  //   lfFormatInvariant SCA128.2/SCA059.2 ', TFormatSettings.Invariant' -
  //                     geprueft ab Delphi 10.3 (FLOOR_INLINE_DECL, wie im
  //                     Planer uRdxFormatSettingsFix); Realworld-Test rwE29:
  //                     Units aus Lazarus-Projekten (Rechnung.lpi), FPC-
  //                     Weichen im Include (Img32.inc), Delphi-1-6-Projekte
  //                     (GExperts)
  //   lfFormatSettingsVar  SCA128/SCA059 ', FormatSettings' - die globale
  //                     Variable ab Delphi XE (FLOOR_SETTINGS_VAR); FPC
  //                     kennt sie (ab 2.6): Lazarus-Dateiart, -Projekt und
  //                     FPC-Weiche im Include sperren hier NICHT (FpcKnows),
  //                     nur alte Delphi-Projekte (rwE29: GExperts mit
  //                     GExpert4.dof). IncludeReason fragt der Adapter fuer
  //                     den Hauptweg seit dem Nico-Entscheid M1b
  //                     (2026-10-30) ueber ProjectReason - nur ohne
  //                     Projekt der Unit ab XE, nur Delphi-Weichen bis XE
  //                     (R_INC_OLD), kein Grund fuer ein fehlendes Include.
  //   lfExceptionClasses SCA127 EArgumentException/EInvalidOpException, seit
  //                     dem Nachzug zu e/HilfeFixJ auch SCA020.2
  //                     (ENotImplemented) und SCA168.2 (EInvalidOpException)
  //                     - ab Delphi 2009 (FLOOR_DEFAULT_FN; Realworld-Test
  //                     rwE30 Stufe 2, Nico-Entscheid "Sperre bei Beleg":
  //                     GExperts fuer Delphi 3-6 mit .dof, CnWizards_D5..
  //                     D2007 in Source\, CnDebugViewer.dpr mit .dof). FPC
  //                     kennt alle drei. Hier ist der Normalfall modern: ein Deckel,
  //                     der Pakete ungelesen laesst, und ein nicht
  //                     gefundenes Include sind KEIN Beleg (MissingBlocks) -
  //                     anders als fuer die Sprachmittel ab 10.3/11.
  // FPC 3.2 kennt keines davon ausser lfFormatSettingsVar und
  // lfExceptionClasses.
  TRdxLateFeature = (lfInlineConst, lfDigitSeparator, lfInlineVar,
    lfFormatInvariant, lfFormatSettingsVar, lfExceptionClasses);

  // Ergebnis des Planers (uRdxFixTable: MagicForm im Geruest TRdxFixFrame).
  //   Value  die Zahl aus der Meldung - Name im Menuetext; schon gesetzt,
  //          wenn der Planer danach ablehnt
  //   Name   der Name der Konstante (MagicNr01 ...) - fuer den Hinweis
  //   Line, Col  das ersetzte Literal (1-basiert, Zeichen)
  //   Wrap   der Zweig bekommt begin..end
  //   Edits  genau eine Ersetzung: von Spalte 1 der ersten geaenderten
  //          Zeile bis hinter das Literal bzw. (Wrap) bis zum Anfang der
  //          Zeile nach der Anweisung
  //   FileWide  abgelehnt wegen der GANZEN Datei (FPC-Weiche, Skript,
  //          Spuren alter Compiler - FileWideReason), nicht wegen der
  //          Stelle; setzt nur IntroduceAt (Entscheid Nico 2026-10-24: die
  //          Code-Aktion ohne Fund zeigt dann keinen Eintrag). MagicNumber
  //          laesst es False - die Fund-Hilfe SCA014 nennt jeden Grund.
  TRdxMagicPlan = record
    Value    : string;
    Name     : string;
    Line     : Integer;
    Col      : Integer;
    Wrap     : Boolean;
    Edits    : TArray<TRdxEdit>;
    FileWide : Boolean;
  end;

  // Plattenblick je Menueaufbau (Charge P5, Performance): FileReason liest
  // je Aufruf bis zu PROJECT_LEVELS + 1 Verzeichnisse samt .dproj-Koepfen,
  // IncludeReason jedes Include der Unit - und ein Menue fragt bis zu
  // MAX_FINDINGS_PER_MENU Funde derselben Datei, dazu die Code-Aktion am
  // Caret. Ist ein Cache aktiv (TRdxMagicFixes.UseDiskCache), merken sich
  // beide darin ihr Ergebnis: FileReason den Teil hinter Dateiart und
  // Netzpfad (beide Pruefungen laufen weiter je Aufruf, vor jedem Blick in
  // den Cache) je Dateiname - genau so geschrieben, der Grund nennt das
  // Verzeichnis -, Sprachmittel und reDelphix-Sprache; IncludeReason dazu
  // je Code-Sicht (TRdxCodeMap.Serial: dieselbe Map, dieselben Includes -
  // eine neue Map, auch nach einer Aenderung der Zeilen, ist ein neuer
  // Eintrag). Ohne aktiven Cache (Vorgabe; alle Tests
  // ausser denen des Caches) fragt jeder Aufruf die Platte wie bisher. Wie
  // lange ein Ergebnis gilt, bestimmt der Besitzer mit Clear (uRdxProvider:
  // ein Menueaufbau) - eine Aenderung auf der Platte innerhalb dieser Zeit
  // sieht erst der naechste.
  TRdxDiskReasonCache = class
  private
    FItems : TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
  end;

  // Der Planer der Charge Q14 und seine Bausteine (s. Kopf).
  TRdxMagicFixes = class
  public
    // Macht ACache zum Cache von FileReason und IncludeReason (nil: keiner,
    // die Vorgabe) und liefert den bisherigen - der Aufrufer stellt ihn im
    // finally wieder her. ACache bleibt im Besitz des Aufrufers.
    class function UseDiskCache(
      ACache: TRdxDiskReasonCache): TRdxDiskReasonCache; static;

    // Die Zahl aus der Meldung 'Magic number "200" in if condition - ...'
    // (zwischen den ersten beiden '"'): Ziffern, hoechstens ein '-' davor;
    // '' sonst.
    class function NumberOf(const AMessage: string): string; static;

    // Das Literal AValue als Vergleichswert in den if-Bedingungen, die auf
    // ALine beginnen (s. Kopf "Ziel aus dem Fund"): '' und seine Spalte in
    // ACol, sonst der Grund.
    class function LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
      const AValue: string; out ACol: Integer): string; static;

    // SCA014: der Plan zum Fund auf ALine mit der Meldung AMessage - True,
    // oder False mit dem Grund. Form TRdxPlannerOf<TRdxMagicPlan>.
    class function MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxMagicPlan;
      out AReason: string): Boolean; static;

    // Code-Aktion ohne Fund (Charge B, uRdxContextRunner): der Plan fuer das
    // Zahl-Literal, das Zeichenspalte ACol auf ALine enthaelt oder direkt
    // vor ACol endet (uRdxCodeMap.LiteralContaining = lkNumber; die
    // Caret-Regel von PlanIntroduce) - dieselbe Kette wie MagicNumber hinter
    // LiteralAt: nur DIESES Literal (E28), dieselben Sperren der Code-Aktion
    // und der Datei. Value ist das Literal wie im Quelltext ('$FF', '1.5',
    // '1_000'). True mit dem Plan; False mit dem Grund; False mit AReason
    // = '', wenn an ACol kein Zahl-Literal steht (kein Kandidat - die
    // Aktion entfaellt, Entscheid F4), ebenso fuer ein triviales Literal
    // (IsTrivialLiteral, die Menge von SCA014; APlan leer - Entscheid Nico
    // 2026-10-24, s. Kopf "Triviale Literale"). Die Sperren der GANZEN Datei
    // (FPC-Weiche, Skript, Spuren alter Compiler) prueft IntroduceAt VOR
    // denen der Stelle: False mit dem Grund und APlan.FileWide = True
    // (Entscheid Nico 2026-10-24). Was nur die Platte weiss (FileReason,
    // IncludeReason - ebenfalls die ganze Datei), fragt der Aufrufer.
    class function IntroduceAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out APlan: TRdxMagicPlan; out AReason: string): Boolean; static;

    // Ist das Zahl-Literal in den Zeichenspalten [AFirst, AStop) der Zeile
    // ALine eines, das SCA014 als trivial durchliesse (s. Kopf "Triviale
    // Literale")? Ein '-' direkt davor, wo ein Operand beginnt, zaehlt mit.
    class function IsTrivialLiteral(AMap: TRdxCodeMap; ALine, AFirst,
      AStop: Integer): Boolean; static;

    // Was nur die Platte weiss (der Check in uRdxFixTable, nach dem
    // Planer): eine Lazarus-/FPC-Dateiart (.pp, .lpr) oder ein Lazarus-
    // Projekt bzw. -Paket (.lpi, .lpk, .lpr) im Verzeichnis der Unit oder
    // bis PROJECT_LEVELS darueber - die Unit baut dann wohl auch mit FPC
    // (Korpus: doublecmd ohne jede FPC-Weiche in der Unit, der Modus steht
    // im Projekt); im selben Fenster das NAECHSTE Verzeichnis mit Delphi-
    // Projektdateien: eine .dproj mit ProjectVersion unter der Schwelle
    // von AFeature (FLOOR_INLINE_DECL.ProjectVersion 18.5 = Delphi 10.3,
    // FLOOR_DIGIT_SEP 19.3 = Delphi 11; ohne lesbare Version zaehlt sie
    // als alt) bzw. - ohne .dproj dort - eine alte Projektdatei (.dof,
    // .bdsproj, .bpr, .bpg). Auf jeder dieser Ebenen dazu die .dpk im
    // Unterordner packages (bzw. package) und eine Ebene darin, die die
    // Unit enthalten: ist eine nach Ordnername ('d104', 'Sydney') bzw.
    // {$LIBSUFFIX} fuer ein Delphi unter der Schwelle, sperrt sie (rwE29,
    // PackagesReason; Ordner, deren Name schon eine Version ab der Schwelle
    // belegt, liest sie nicht, alte vor unbekannten; hoechstens
    // MAX_PACKAGE_READS Koepfe je Aufruf - bleibt danach eine .dpk in einem
    // alten oder unbekannten Ordner ungelesen, sperrt sie auch). Ein
    // Netzpfad (UNC oder Netzlaufwerk, IsNetworkPath) wird nicht gelesen.
    // '' oder der Grund - er nennt AFeature. Die FPC-Weiche IN der Datei
    // prueft schon TargetAt.
    // Seit rwE30 Stufe 2 dazu je Projekt (PairsIn): ein Programm/Paket mit
    // .dof, .cfg bzw. .bdsproj gleichen Namens ohne eigene .dproj zaehlt
    // als alt, auch neben neuen .dproj anderer Projekte (CnDebugViewer.dpr
    // neben CnDebugViewer64.dproj), und ein Programm ganz ohne Projektdatei
    // neben einem Lazarus-Projekt als Doppel-Compiler-Projekt fuer altes
    // Delphi (RechnungDelphi.dpr neben Rechnung.lpi). Fuer lfFormatInvariant
    // widerlegt ein Paket, dessen Units Invariant ohne Weiche nutzen, seine
    // Version (PackageUsesInvariant, loggerproRT.dpk in d100), und ein
    // Programm, das die Unit enthaelt und die globale FormatSettings fuer
    // Datum/Uhrzeit selbst einstellt, sperrt (SettingsProgramReason,
    // HeidiSQL heidisql.dpr).
    class function FileReason(const AFileName: string;
      AFeature: TRdxLateFeature): string; static;

    // Die Include-Dateien der Unit AFileName (alle {$I} in AMap, auch die
    // im Kopf - dort stehen die Compiler-Weichen: jvcl.inc,
    // mormot.defines.inc ...; uRdxBlocks.AllIncludes, bis zur
    // Nachpruefung der Charge B1-FD hier kopiert) lesen, verschachtelte ebenso
    // (uRdxBlocks.IncludeChainReason): '' oder der Grund - eine
    // FPC-Weiche oder Spur aelterer Compiler (bis zur Schwelle von
    // AFeature) darin, oder ein Include, das nicht neben der Unit liegt
    // oder auf einem Netzpfad (nicht gelesen) - seine Weichen sieht die
    // Hilfe dann nicht.
    class function IncludeReason(const AFileName: string; AMap: TRdxCodeMap;
      AFeature: TRdxLateFeature): string; static;

    // Kennt FPC 3.2 das Sprachmittel? Dann sperren Lazarus-Dateiart,
    // Lazarus-Projekt und FPC-Weiche im Include nicht (lfFormatSettingsVar
    // und lfExceptionClasses).
    class function FpcKnows(AFeature: TRdxLateFeature): Boolean; static;

    // Ist ein ungelesener Rest ein Grund - der erschoepfte Paket-Deckel
    // (R_PACKAGES_UNREAD), ein nicht gefundenes oder nicht lesbares Include
    // (R_INC_UNSEEN), ein Netzpfad in ProjectReason? Ja, ausser fuer
    // lfExceptionClasses: dort ist der Normalfall modern, und nur ein Beleg
    // sperrt (Nico-Entscheid rwE30 Stufe 2, "Sperre bei Beleg").
    class function MissingBlocks(AFeature: TRdxLateFeature): Boolean; static;

    // Der Einstieg der Adapter (uRdxFixTable: SCA128/SCA059 und SCA127,
    // rwE30 Stufe 2): der Plattenblick einer Unit samt Gegenbeweis. Beweist
    // die Datei einen Compiler ab der Schwelle von AFeature
    // (uRdxCompilerTraces.ModernProof - fuer ein Sprachmittel, das FPC nicht
    // kennt, nur die Inline-Variable, die auch FPC ausschliesst) bzw. nutzt
    // sie fuer lfFormatInvariant TFormatSettings.Invariant selbst ohne
    // Weiche, fragt er die Platte nicht nach Compilern - fuer
    // lfFormatInvariant aber weiter nach Programmen, die die globale
    // FormatSettings selbst einstellen (SettingsWalkReason, Review
    // e/HilfeFixG). Sonst - fuer lfFormatSettingsVar seit rwE31 Stufe 3
    // zuerst ein Kit-Include der Unit (KitIncludeReason; widerlegt nur durch
    // ein Programm mit .dproj ab XE, das die Unit enthaelt, auch ohne
    // Dateinamen geprueft) - FileReason und, mit AIncludes bzw. seit dem
    // Nico-Entscheid M1b fuer lfFormatSettingsVar ohne Projekt der Unit ab
    // XE, IncludeReason
    // (fuer lfFormatInvariant widerlegt durch ein Paket der Unit, das
    // Invariant nutzt, bzw. seit rwE31 Stufe 3 bei einer FMX-Unit durch
    // Pakete nur ab 10.3 - PackageFloorProof).
    // Netzpfad: fuer lfExceptionClasses kein Grund (MissingBlocks), sonst
    // wie FileReason. '' oder der Grund.
    class function ProjectReason(const AFileName: string; AMap: TRdxCodeMap;
      AFeature: TRdxLateFeature; AIncludes: Boolean): string; static;
  end;

  // Die Delphi-Version eines Pakets als CompilerVersion (Delphi 7 = 15,
  // 2009 = 20, XE = 22, 10.0 = 30, 10.4 = 34, 11 = 35, 13 = 37), -1 ohne
  // Beleg - fuer FileReason (Pakete, die die Unit enthalten, rwE29); reine
  // Textlogik, oeffentlich fuer die Tests (FPC-Pruefstand). Hat ein Beleg
  // zwei Lesarten, gilt die HOECHSTE: alt ist ein Paket nur, wenn jede
  // Lesart alt ist.
  TRdxPackageVersion = class
  public
    // JEDI-Nummer J (DELPHIn; Paketversion J * 10): 5..10 = Delphi 5 bis
    // 2006, 11 = 2007, 12 = 2009, 14..29 = 2010 bis 12, 37 = 13.
    class function Jedi(J: Integer): Integer; static;
    // Produktversion AMajor.AMinor: 10.0..10.4, 11, 12, 13.
    class function Product(AMajor, AMinor: Integer): Integer; static;
    // Eine Zahl wie in 'd104', 'D110', {$LIBSUFFIX '270'}: Paketversion
    // (nur volle Zehner) oder Produkt ('104' = 10.4).
    class function Number(N: Integer): Integer; static;
    // Jahreszahl hinter 'D'/'Delphi' (2005, 2006, 2007, 2009, 2010).
    class function Year(N: Integer): Integer; static;
    // Der Name eines Paketordners: 'd104', 'D10_4', 'Delphi12.3',
    // 'Delphi 11', 'Delphi_12', 'D2007', 'D7', 'DXE6', 'XE', 'c6'/'bcb6'
    // (C++Builder 6 baut .pas mit dem Compiler von Delphi 6), 'RAD Studio
    // 10.4', die Codenamen ('Sydney'). Eine Zahl zaehlt nur hinter 'd',
    // 'delphi' (auch durch ' ', '_', '-' getrennt), 'xe', 'c'/'cb'/'bcb'
    // bzw. als Haupt- und Unterversion hinter 'Studio' oder am
    // Namensanfang - nicht 'v10.2', nicht 'Deluxe'. Mehrere Belege: der
    // hoechste.
    class function Folder(const AName: string): Integer; static;
    // {$LIBSUFFIX 'nnn'} im Kopf einer .dpk (ALowText klein geschrieben),
    // zwei oder drei Ziffern wie Number; -1 ohne oder bei 'AUTO',
    // '$(Auto)'. AValue: der Wert.
    class function LibSuffix(const ALowText: string;
      out AValue: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,       // TStrings (TRdxIncludeTest)
  uRefactorInfo,        // TRefactorSpan.Make
  uRdxIntroPlan,        // CharColOfByte, LineLooksFpcAware
  uRdxIntroEdits,       // TextOf, TargetAt, IntroduceEdits, ApplyIntroEdits,
                        // FpcFileReason
  uRdxPaths,            // IsNetworkPath
  uRdxBlocks,           // IncludeChainReason, AllIncludes
  uRdxCompilerTraces,   // OldCompilerTrace, ScriptReason, FLOOR_INLINE_DECL,
                        // FLOOR_DIGIT_SEP, FLOOR_SETTINGS_VAR
  uRdxText;             // _, MsgMovedSuffix, MsgByHand (E29)

const
  SPAN_MAGIC = 'magic';
  KW_IF   = 'if';
  KW_THEN = 'then';
  KW_END  = 'end';
  // Davor steht der Vergleichswert (uMagicNumbers.ExtractMagicNumber).
  COMPARE_OPS: array[0..5] of string = ('>=', '<=', '<>', '>', '<', '=');
  // So weit liest die Hilfe eine Bedingung ueber Folgezeilen (der
  // Detektor bis zum 'then'; ein fehlendes 'then' heisst kaputter Text).
  MAX_COND_LINES = 40;
  // Lazarus-/FPC-Dateiarten - Delphi oeffnet sie nicht als Unit.
  FPC_EXTENSIONS: array[0..1] of string = ('.pp', '.lpr');
  // Lazarus-Projekt, -Paket, -Programm (FileReason) ...
  LAZARUS_EXTENSIONS: array[0..2] of string = ('.lpi', '.lpk', '.lpr');
  // ... Projektdateien aelterer Delphi bzw. des C++Builder: Delphi 1-7,
  // BDS 2005/2006, C++Builder-Projekt und -Projektgruppe (Major 3) ...
  LEGACY_EXTENSIONS: array[0..3] of string = ('.dof', '.bdsproj', '.bpr',
    '.bpg');
  DPROJ_EXTENSION = '.dproj';
  // ... je Projekt (rwE30 Stufe 2, PairsIn): das Programm und seine
  // Optionsdateien aelterer Delphi - .dof (Delphi 1-7), .cfg (dcc32-
  // Optionen, die die IDE bis Delphi 2007 schrieb; neuere legen sie nur
  // neben eine .dproj gleichen Namens), .bdsproj (BDS 2005/2006).
  DPR_EXTENSION = '.dpr';
  // FPC-Programme (FpcOnlyProgram, rwE32 Stufe 4): ein Lazarus-Projekt
  // nennt seine Dateien so ('<Filename Value="Zip.dpr"/>', klein) ...
  LPI_EXTENSION = '.lpi';
  LPI_FILE_TAG = '<filename value="';
  // ... und Units, die nur FPC bzw. Lazarus mitbringen (klein).
  FPC_ONLY_UNITS: array[0..7] of string = ('fpcadds', 'cmem', 'cthreads',
    'cwstring', 'lazutf8', 'lazfileutils', 'lclintf', 'lcltype');
  PAIR_OPTION_EXTENSIONS: array[0..2] of string = ('.dof', '.cfg',
    '.bdsproj');
  // ... im Verzeichnis der Unit und so vielen darueber (Korpus: doublecmd-
  // Plugins eine Ebene, CnWizards_L4.lpk zwei Ebenen ueber den Units).
  PROJECT_LEVELS = 2;
  // So viel einer .dproj liest die Hilfe - ProjectVersion steht in der
  // ersten PropertyGroup.
  DPROJ_HEAD_BYTES = 65536;
  PROJECT_VERSION_TAG = '<ProjectVersion>';
  // Pakete, die die Unit enthalten (PackagesReason, rwE29: DMVC baut
  // sources\*.pas auch ueber packages\d100..d104\dmvcframeworkRT.dpk fuer
  // Delphi 10.0-10.4; die .dproj dort tragen ProjectVersion 20.3, neu
  // gespeichert - der Ordner und LIBSUFFIX nennen die Version). Gesucht
  // wird je Ebene der Suche in einem Unterordner dieses Namens und eine
  // Ebene tiefer; je Aufruf hoechstens MAX_PACKAGE_READS Koepfe (s.
  // interface). Ordner, deren Name schon eine Version ab der Schwelle
  // belegt, liest die Hilfe nicht; alte zuerst, dann unbekannte.
  PACKAGE_DIRS: array[0..1] of string = ('packages', 'package');
  DPK_EXTENSION = '.dpk';
  LIBSUFFIX_TAG = '{$libsuffix ''';
  // Die Units eines alten Pakets (PackageUsesInvariant, rwE30 Stufe 2):
  // die in-Klausel im Kopf (klein), der gesuchte Text und wie viel ein Lauf
  // davon liest (DMVC: 143 Units, 3,9 MB - die Invariant-Nutzer stehen ab
  // der 39. Unit; erschoepft: keine Widerlegung, die Sperre bleibt).
  DPK_IN_TAG = ' in ''';
  INVARIANT_TEXT = 'tformatsettings.invariant';
  MAX_PACKAGE_UNIT_BYTES = 8 * 1024 * 1024;
  // So viele .dpr liest SettingsProgramReason je Lauf (erschoepft: kein
  // Beleg).
  MAX_PROGRAM_READS = 16;
  // Codenamen in Ordnernamen, CompilerVersion = 30 + Index (Seattle = 10.0
  // = 30 ... Florence = 13 = 37).
  CODE_NAMES: array[0..7] of string = ('seattle', 'berlin', 'tokyo', 'rio',
    'sydney', 'alexandria', 'athens', 'florence');
  // Woerter vor einer Versionszahl im Ordnernamen (TRdxPackageVersion.
  // Folder): Delphi, XE, C++Builder ('c6' = C++Builder 6), Studio vor
  // Haupt- und Unterversion.
  DELPHI_WORDS: array[0..1] of string = ('d', 'delphi');
  XE_WORDS: array[0..2] of string = ('xe', 'dxe', 'delphixe');
  CBUILDER_WORDS: array[0..2] of string = ('c', 'cb', 'bcb');
  STUDIO_WORD = 'studio';
  // Programm und Bibliothek haben einen Hauptblock (MainBlockReason).
  MAIN_BLOCK_WORDS: array[0..1] of string = ('program', 'library');
  // Die Gruende sind englische msgids, uebersetzt mit _() in DIESER Unit
  // (Entscheid E29; tools/i18n_extract.py loest nur Konstanten und
  // String-Array-Konstanten derselben Unit auf). Jede msgid ist ein GANZER
  // Satz: ein %s am Satzende hinter '; ' ist MsgByHand (uRdxText) - der
  // Trenner bleibt im Satz.
  // Was nur der Compiler kennt (ScriptReason): uebersetzt uebergeben - der
  // Aufrufer uebersetzt, ScriptReason setzt es als %s in seinen Satz.
  FEATURE_INLINE = 'an inline constant';
  // MissingFmt fuer IncludeChainReason (uRdxBlocks): %s das Include, %s die
  // Ursache ('nicht neben der Unit gefunden' ...). Geht als uebersetztes
  // MUSTER hinaus (_() ohne Argumente formatiert nicht), Include und
  // Ursache setzt uRdxBlocks ein.
  R_INC_UNSEEN = 'include %s %s - the quick fix does not see its compiler '
    + 'switches (FPC, older Delphi)';
  // Die Gruende des Plattenblicks nennen das Sprachmittel (TRdxLateFeature):
  // bis zur Integration QFI2 stand dort fest die Inline-Konstante und
  // Delphi 10.3 - fuer SCA014 ergibt sich derselbe Text. Je Sprachmittel
  // EIN ganzer Satz (Charge G9, Entscheid E29): Geschlecht, Zahl und
  // Verneinung ('keine Inline-Konstante', 'keine Zifferntrenner') stellt
  // jede Sprache selbst - ein Satz aus Stuecken ('%s gibt es in FPC 3.2
  // nicht' mit 'Zifferntrenner') liesse sich nicht uebersetzen. Die
  // Versionsnummer des Sprachmittels (10.3, 11) steht im Satz; die
  // ProjectVersion der Schwelle kommt aus FloorOf (%s).
  // Reihenfolge je Array: lfInlineConst, lfDigitSeparator, lfInlineVar,
  // lfFormatInvariant, lfFormatSettingsVar. Die FPC-Saetze (R_FPC_FILE,
  // R_LAZARUS, R_INC_FPC) zeigt lfFormatSettingsVar nie (FpcKnows) - dort
  // steht derselbe Satz wie bei lfFormatInvariant (keine eigene msgid).
  R_FPC_FILE: array[TRdxLateFeature] of string = (
    'Lazarus/FPC file (%s) - FPC 3.2 has no inline constants',
    'Lazarus/FPC file (%s) - FPC 3.2 has no digit separators',
    'Lazarus/FPC file (%s) - FPC 3.2 has no inline variables',
    'Lazarus/FPC file (%s) - FPC 3.2 has no TFormatSettings.Invariant',
    'Lazarus/FPC file (%s) - FPC 3.2 has no TFormatSettings.Invariant',
    'Lazarus/FPC file (%s) - FPC 3.2 has no TFormatSettings.Invariant');
  R_LAZARUS: array[TRdxLateFeature] of string = (
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no inline constants',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no digit separators',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no inline variables',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no TFormatSettings.Invariant',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no TFormatSettings.Invariant',
    'Lazarus project/package %s in the directory %s - the unit probably also '
      + 'builds with FPC, and FPC 3.2 has no TFormatSettings.Invariant');
  R_LEGACY: array[TRdxLateFeature] of string = (
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 10.3, which has no inline constants; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 11, which has no digit separators; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 10.3, which has no inline variables; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 10.3, and TFormatSettings.Invariant is only '
      + 'checked from there on; %s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before XE, which has no global variable FormatSettings; '
      + '%s',
    'old project file %s in the directory %s - the unit probably also builds '
      + 'with a Delphi before 2009, which lacks the exception classes '
      + 'EArgumentException, EInvalidOpException and ENotImplemented; %s');
  R_OLD_DPROJ: array[TRdxLateFeature] of string = (
    'project %s in the directory %s with ProjectVersion %s (before Delphi 10.3 '
      + '= %s) - there are no inline constants there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 11 '
      + '= %s) - there are no digit separators there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 10.3 '
      + '= %s) - there are no inline variables there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 10.3 '
      + '= %s) - TFormatSettings.Invariant is only checked from there on; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi XE '
      + '= %s) - there is no global variable FormatSettings there; %s',
    'project %s in the directory %s with ProjectVersion %s (before Delphi 2009 '
      + '= %s) - the exception classes EArgumentException, EInvalidOpException '
      + 'and ENotImplemented do not exist there; %s');
  R_NO_VERSION: array[TRdxLateFeature] of string = (
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '10.3, which has no inline constants; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '11, which has no digit separators; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '10.3, which has no inline variables; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '10.3, and TFormatSettings.Invariant is only checked from there on; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + 'XE, which has no global variable FormatSettings; %s',
    'project %s in the directory %s without a readable ProjectVersion (Delphi '
      + '2007 wrote none) - the unit probably also builds with a Delphi before '
      + '2009, which lacks the exception classes EArgumentException, '
      + 'EInvalidOpException and ENotImplemented; %s');
  // Ein Paket, das die Unit enthaelt (PackagesReason, rwE29): %s Paket,
  // %s Verzeichnis, %s der Beleg (Ordnername 'd104' bzw. "LIBSUFFIX '104'"),
  // %s MsgByHand.
  R_OLD_PACKAGE: array[TRdxLateFeature] of string = (
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before 10.3 (%s), which has no inline constants; %s',
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before 11 (%s), which has no digit separators; %s',
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before 10.3 (%s), which has no inline variables; %s',
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before 10.3 (%s), and TFormatSettings.Invariant is only '
      + 'checked from there on; %s',
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before XE (%s), which has no global variable FormatSettings; '
      + '%s',
    'package %s in the directory %s contains the unit and is meant for a '
      + 'Delphi before 2009 (%s), which lacks the exception classes '
      + 'EArgumentException, EInvalidOpException and ENotImplemented; %s');
  // Der Deckel MAX_PACKAGE_READS ist erschoepft, in einem alten oder
  // unbekannten Paketordner bleibt eine .dpk ungelesen (Review
  // e/HilfeFixB): %s der Ordner, %d der Deckel, %s MsgByHand. Fuer
  // lfExceptionClasses nie gezeigt (MissingBlocks: kein Beleg) - dort
  // steht der Satz von lfFormatSettingsVar (keine eigene msgid).
  R_PACKAGES_UNREAD: array[TRdxLateFeature] of string = (
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before 10.3, which has '
      + 'no inline constants; %s',
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before 11, which has '
      + 'no digit separators; %s',
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before 10.3, which has '
      + 'no inline variables; %s',
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before 10.3, and '
      + 'TFormatSettings.Invariant is only checked from there on; %s',
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before XE, which has no '
      + 'global variable FormatSettings; %s',
    'package files in %s remain unread (the quick fix reads at most %d) - '
      + 'one of them may build the unit with a Delphi before XE, which has no '
      + 'global variable FormatSettings; %s');
  R_INC_FPC: array[TRdxLateFeature] of string = (
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no inline '
      + 'constants',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no digit '
      + 'separators',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no inline '
      + 'variables',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no '
      + 'TFormatSettings.Invariant',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no '
      + 'TFormatSettings.Invariant',
    'the include %s carries an FPC switch (line %d) - FPC 3.2 has no '
      + 'TFormatSettings.Invariant');
  R_INC_OLD: array[TRdxLateFeature] of string = (
    'the include %s shows traces of older compilers (%s, line %d) - an inline '
      + 'constant exists only from Delphi 10.3 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - digit '
      + 'separators exist only from Delphi 11 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - an inline '
      + 'variable exists only from Delphi 10.3 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - '
      + 'TFormatSettings.Invariant is only checked from Delphi 10.3 on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - the global '
      + 'variable FormatSettings exists only from Delphi XE on; %s',
    'the include %s shows traces of older compilers (%s, line %d) - the '
      + 'exception classes EArgumentException, EInvalidOpException and '
      + 'ENotImplemented exist only from Delphi 2009 on; %s');
  // Ein Programm ohne Projektdatei neben einem Lazarus-Projekt (rwE30 Stufe
  // 2, PairsIn: RechnungDelphi.dpr neben Rechnung.lpi - ausdruecklich fuer
  // Delphi 7 und FPC geschrieben): %s das Programm, %s das Lazarus-Projekt,
  // %s das Verzeichnis, %s MsgByHand. Nur die Sprachmittel, die FPC kennt,
  // sehen den Satz (sonst sperrt das Lazarus-Projekt zuerst) - die anderen
  // tragen den von lfFormatSettingsVar (keine eigene msgid).
  R_DUAL_PROJECT: array[TRdxLateFeature] of string = (
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which has no '
      + 'global variable FormatSettings; %s',
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which has no '
      + 'global variable FormatSettings; %s',
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which has no '
      + 'global variable FormatSettings; %s',
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which has no '
      + 'global variable FormatSettings; %s',
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which has no '
      + 'global variable FormatSettings; %s',
    'Delphi program %s without .dproj next to the Lazarus project %s in the '
      + 'directory %s - written for FPC and an older Delphi, which lacks the '
      + 'exception classes EArgumentException, EInvalidOpException and '
      + 'ENotImplemented; %s');
  // Ein Programm, das die Unit enthaelt, setzt die globale FormatSettings
  // selbst (rwE30 Stufe 2, HeidiSQL packages\Delphi12.3\heidisql.dpr:
  // 'FormatSettings.ShortDateFormat := ''yyyy/mm/dd'''): Invariant liefe
  // daran vorbei - %s Programm, %s Verzeichnis, %s Feld, %d Zeile, %s
  // MsgByHand. Nur lfFormatInvariant (SettingsProgramReason).
  R_PROGRAM_SETTINGS = 'the program %s in the directory %s contains the unit '
    + 'and sets the global FormatSettings itself (%s, line %d) - '
    + 'TFormatSettings.Invariant would bypass these settings; %s';
  // UNC und Netzlaufwerk (uRdxPaths.IsNetworkPath, seit Charge B1-FD).
  // Hauptweg SCA128/SCA059 (KitIncludeReason, rwE31 Stufe 3): derselbe Satz
  // wie R_FS_OLD_VAR in uRdxFormatSettingsFix (eine msgid) - %s das
  // Kit-Include, %d seine Zeile.
  R_KIT_OLD_VAR = 'the file asks for old compilers (%s, line %d) - the global '
    + 'variable FormatSettings exists from Delphi XE on';
  R_NETWORK = 'network path %s - the quick fix reads no project or include '
    + 'files there (the menu is built in the main thread); %s';
  R_MAIN_BLOCK = 'the line is in the main block of the program or library '
    + '(begin from line %d) - whether an inline declaration is valid there '
    + 'has not been measured; %s';

// Die Schwelle des Sprachmittels (uRdxCompilerTraces; lfInlineConst und
// lfInlineVar teilen FLOOR_INLINE_DECL) - eine Funktion,
// weil ein typisierter Record nicht in einer typisierten Konstante stehen
// kann.
function FloorOf(AFeature: TRdxLateFeature): TRdxCompilerFloor;
begin
  if AFeature = lfDigitSeparator then
    Result := FLOOR_DIGIT_SEP
  else if AFeature = lfFormatSettingsVar then
    Result := FLOOR_SETTINGS_VAR
  else if AFeature = lfExceptionClasses then
    Result := FLOOR_DEFAULT_FN
  else
    Result := FLOOR_INLINE_DECL;
end;

{ ---- Ziel aus dem Fund ---- }

// Die Zahl zwischen den ersten beiden '"' (QuotedText, uRdxCodeMap; bis
// Charge B2S-a hier ausgeschrieben), dann die Ziffern-Probe.
class function TRdxMagicFixes.NumberOf(const AMessage: string): string;
var
  Digits : string;
  C      : Char;
begin
  Result := QuotedText(AMessage, '"');
  if Result = '' then Exit;
  Digits := Result;
  if Digits[1] = '-' then
    Delete(Digits, 1, 1);
  if Digits = '' then
    Exit('');
  for C in Digits do
    if not CharInSet(C, ['0'..'9']) then
      Exit('');
end;

// Die Spalte hinter dem Zahl-Literal an T samt einem direkt folgenden
// Bruchteil ('200.5', '200_000.5': das Token endet am '.'); ohne
// Bruchteil T.EndCol.
function NumberEnd(AMap: TRdxCodeMap; const T: TRdxToken): Integer;
var
  L : string;
begin
  L := AMap.Raw(T.Line);
  Result := T.EndCol;
  if (Result < Length(L)) and (L[Result] = '.')
     and CharInSet(L[Result + 1], ['0'..'9']) then
  begin
    Inc(Result);
    while (Result <= Length(L)) and IsIdentChar(L[Result]) do
      Inc(Result);
  end;
end;

// Ist T ein Vergleichswert - davor ein Vergleich, dahinter kein Bruchteil?
function IsComparedValue(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := InList(Before(AMap, T).Low, COMPARE_OPS)
    and (NumberEnd(AMap, T) = T.EndCol);
end;

// Ein Schluesselwort AWord an T (nicht '&If', 'X.Then')? Bis zur Folgewelle
// des Wochen-Reviews IsKeyword - der Name gehoert seitdem der Wortliste
// KEYWORDS in uRdxCodeMap.
function IsKeywordToken(AMap: TRdxCodeMap; const T: TRdxToken;
  const AWord: string): Boolean;
begin
  Result := (T.Low = AWord) and IsKeywordAfter(T, Before(AMap, T));
end;

// Ein Vergleichswert mit Zifferntrennern (ab Delphi 11), dessen erster
// Block AValue ist ('200_000', auch '200_000.5', zu "200"): sein Text wie
// in der Zeile, sonst ''. Der Detektor liest '_000' als Bezeichner und
// meldet den ersten Block - ein Fehlalarm (Review R6-05), mit Bruchteil
// ebenso (Nachbesserung FF). Davor muss ein Vergleich stehen: nur dort
// liest der Detektor einen Wert ('Foo(200_000) > X' meldet er nicht).
function SeparatedValue(AMap: TRdxCodeMap; const T: TRdxToken;
  const AValue: string): string;
var
  C : Char;
begin
  Result := '';
  if (Copy(T.Low, 1, Length(AValue) + 1) <> AValue + '_')
     or not InList(Before(AMap, T).Low, COMPARE_OPS) then
    Exit;
  for C in T.Low do
    if not CharInSet(C, ['0'..'9', '_']) then
      Exit;
  Result := Copy(AMap.Raw(T.Line), T.Col, NumberEnd(AMap, T) - T.Col);
end;

// Die Vergleichswerte AValue in der Bedingung hinter AIf bis zu ihrem
// 'then' (bzw. 'end', Dateiende, MAX_COND_LINES): ihre Zahl, der letzte
// in AHit; der erste Vergleichswert mit Zifferntrennern, dessen erster
// Block AValue ist, in ASeparated (SeparatedValue; nur, solange noch
// keiner gesetzt ist).
function CountInCondition(AMap: TRdxCodeMap; const AIf: TRdxToken;
  const AValue: string; var AHit: TRdxToken; var ASeparated: string): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := After(AMap, AIf);
  while (T.Low <> '') and (T.Line <= AIf.Line + MAX_COND_LINES)
     and not IsKeywordToken(AMap, T, KW_THEN) and not IsKeywordToken(AMap, T, KW_END) do
  begin
    if (T.Low = AValue) and IsComparedValue(AMap, T) then
    begin
      Inc(Result);
      AHit := T;
    end
    else if ASeparated = '' then
      ASeparated := SeparatedValue(AMap, T, AValue);
    T := After(AMap, T);
  end;
end;

class function TRdxMagicFixes.LiteralAt(AMap: TRdxCodeMap; ALine: Integer;
  const AValue: string; out ACol: Integer): string;
var
  T, Hit : TRdxToken;
  Ifs, N : Integer;
  Sep    : string;
begin
  ACol := 0;
  Ifs := 0;
  N := 0;
  Sep := '';
  Hit := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsKeywordToken(AMap, T, KW_IF) then
    begin
      Inc(Ifs);
      Inc(N, CountInCondition(AMap, T, AValue, Hit, Sep));
    end;
    T := After(AMap, T);
  end;
  if Ifs = 0 then
    Result := MsgMovedSuffix(_('line %d carries no if', [ALine]))
  else if (N > 0) and (Sep <> '') then
    // Beides in einer Bedingung ('(X > 200_000) or (Y > 200)'): die Meldung
    // "200" passt auf beide, und der Detektor nimmt den ersten Vergleich in
    // Op-Reihenfolge - vorher ersetzte die Hilfe das exakte Literal, und
    // der Fund blieb (Wochen-Review 2026-10-21).
    Result := _('the if condition on line %d compares with %s and with %s - '
      + 'ambiguous (with digit separators the detector reads only the first '
      + 'block); the quick fix replaces exactly one literal',
      [ALine, Sep, AValue])
  else if (N = 0) and (Sep <> '') then
    // Der Fund ist frisch, nur falsch gelesen - 'Zeile verschoben?' liesse
    // den Nutzer neu scannen und denselben Fund wiederfinden.
    Result := _('the if condition on line %d compares with %s - with digit '
      + 'separators the detector reads only the first block %s (false '
      + 'alarm); no literal to replace', [ALine, Sep, AValue])
  else if N = 0 then
    Result := MsgMovedSuffix(_('no if condition on line %d compares with %s',
      [ALine, AValue]))
  else if N > 1 then
    Result := _('the if condition on line %d compares %d times with %s - '
      + 'ambiguous; the quick fix replaces exactly one literal',
      [ALine, N, AValue])
  else if Hit.Line <> ALine then
    Result := _('%s is in line %d, a continuation line of the if condition - '
      + 'the constant would belong before the if line (not supported)',
      [AValue, Hit.Line])
  else
  begin
    Result := '';
    ACol := Hit.Col;
  end;
end;

{ ---- Der Text fuer die Code-Aktion und zurueck ---- }

// Die Zeilen der Code-Sicht als Puffer der Code-Aktion (uRdxIntroEdits.
// TextOf): mit LF verbunden - die Zeilen sind dieselben wie in ALines
// (ein einzelnes CR trennt dort schon), Zeilenenden setzt erst
// PlanByteEdits (das des Puffers).
function IntroTextOf(AMap: TRdxCodeMap): TRdxIntroText;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to AMap.LineCount do
    begin
      if i > 1 then SB.Append(#10);
      SB.Append(AMap.Raw(i));
    end;
    Result := TextOf(TEncoding.UTF8.GetBytes(SB.ToString));
  finally
    SB.Free;
  end;
end;

// Nur das Literal in Spalte ACol der Anweisungszeile (E28) - der Plan der
// Code-Aktion nennt alle gleichen Literale der Zeile. False, wenn ACol
// nicht darunter ist.
function KeepOnlyLiteral(const AText: TRdxIntroText;
  var ATarget: TRdxIntroTarget; ACol: Integer): Boolean;
var
  C : Integer;
  L : string;
begin
  Result := False;
  for C in ATarget.Plan.OldCols do
    Result := Result or (C = ACol);
  if not Result then Exit;
  L := AText.Lines[ATarget.SourceRow - 1];
  ATarget.Plan.OldCols := [ACol];
  ATarget.Plan.NewCols := [ACol];
  ATarget.Plan.NewUseLine := Copy(L, 1, ACol - 1) + ATarget.Name
    + Copy(L, ACol + Length(ATarget.Plan.Literal), MaxInt);
end;

// Die Zeile (1-basiert), in der Byte AOffset liegt.
function RowOfByte(const AText: TRdxIntroText; AOffset: Integer): Integer;
begin
  Result := Length(AText.Starts);
  while (Result > 1) and (AText.Starts[Result - 1] > AOffset) do
    Dec(Result);
end;

// Die Ersetzungen der Code-Aktion (Bytes, aufsteigend) als EINE Ersetzung
// fuer PlanByteEdits: von Spalte 1 der Zeile der ersten bis hinter die
// letzte; Expected und NewText aus den Bytes vor und nach ApplyIntroEdits
// (Zeilenenden #10 wie SpanText). Ein Bereich beginnt auf einem Zeichen
// (TRefactorInfoBuilder.SpanFits): ist die erste Zeile LEER - eine
// Leerzeile zwischen Zweigzeile und Anweisung, vor die IntroduceEdits
// 'begin' setzt -, beginnt er am Anfang der naechsten nicht leeren Zeile
// davor, die unveraendert in Expected und NewText steht. Bis Charge B1-FD
// begann er auf der Leerzeile: der Eintrag stand freigegeben im Menue, und
// jeder Klick scheiterte mit "Menue neu oeffnen" (Gegen-Review R4-02).
function AsOneEdit(const AText: TRdxIntroText;
  const AEdits: TRdxIntroByteEdits): TRdxEdit;
var
  OldBytes, NewBytes : TBytes;
  First, Last, E     : Integer;
  Row1, Row2         : Integer;
  Delta              : Integer;
  B                  : TRdxIntroByteEdit;
begin
  OldBytes := TEncoding.UTF8.GetBytes(AText.Text);
  NewBytes := ApplyIntroEdits(OldBytes, AEdits);
  First := MaxInt;
  Last := 0;
  for B in AEdits do
  begin
    if B.Offset < First then First := B.Offset;
    E := B.Offset + B.Len;
    if E > Last then Last := E;
  end;
  Row1 := RowOfByte(AText, First);
  Row2 := RowOfByte(AText, Last);
  while (Row1 > 1) and (AText.Lines[Row1 - 1] = '') do
    Dec(Row1);
  First := AText.Starts[Row1 - 1];
  Delta := Length(NewBytes) - Length(OldBytes);
  Result.Span := TRefactorSpan.Make(SPAN_MAGIC, Row1, 1, Row2,
    CharColOfByte(AText.Lines[Row2 - 1], Last - AText.Starts[Row2 - 1]));
  Result.Expected := TEncoding.UTF8.GetString(OldBytes, First, Last - First);
  Result.NewText := TEncoding.UTF8.GetString(NewBytes, First,
    Last + Delta - First);
end;

{ ---- Der Planer ---- }

// Das 'begin' des Hauptblocks einer Datei, die mit program bzw. library
// beginnt: von ihrem letzten 'end.' rueckwaerts bis zu dem Oeffner, der
// die end-Bilanz schliesst (END_OPENERS); Low = '' ohne. Ein end bzw.
// Oeffner mit ':=' dahinter ist ein benanntes Argument ('Doc.Range(Start
// := 0, End := 1)') und zaehlt nicht (IsKeywordAt) - bis Charge B1-FD
// verdeckte es den Hauptblock, und die Hilfe bot dort an (Gegen-Review R4,
// missed 3; wie H4c). Das 'end.' ist das ERSTE Schluesselwort-'end' mit
// '.' dahinter: Delphi liest hinter ihm nichts mehr, und Text dort (alte
// Notizen ohne Kommentarklammern) liess die Suche vom letzten Token aus
// still ohne Hauptblock enden (Wochen-Review 2026-10-21).
function MainBlockBegin(AMap: TRdxCodeMap): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  if not InList(NextToken(AMap, 1, 1).Low, MAIN_BLOCK_WORDS) then Exit;
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '')
     and not ((T.Low = KW_END) and (After(AMap, T).Low = '.')
              and IsKeywordAt(AMap, T, Before(AMap, T))) do
    T := After(AMap, T);
  if T.Low = '' then Exit;
  Depth := 1;
  while Depth > 0 do
  begin
    T := Before(AMap, T);
    if T.Low = '' then Exit;
    P := Before(AMap, T);
    if not IsKeywordAt(AMap, T, P) then Continue;
    if T.Low = KW_END then
      Inc(Depth)
    else if IsEndOpener(T.Low) then
      Dec(Depth);
  end;
  if T.Low = 'begin' then
    Result := T;
end;

// Die Zeile im Hauptblock eines Programms bzw. einer Bibliothek (Verdacht
// d: m22 des Pruefers bot dort an)? '' oder der Grund.
function MainBlockReason(AMap: TRdxCodeMap; ALine: Integer): string;
var
  B : TRdxToken;
begin
  Result := '';
  B := MainBlockBegin(AMap);
  if (B.Low <> '') and (ALine >= B.Line) then
    Result := _(R_MAIN_BLOCK, [B.Line, MsgByHand]);
end;

// Was die Datei als Ganzes verbietet: Spuren von Compilern vor Delphi 10.3.
function CompilerReason(AMap: TRdxCodeMap): string;
var
  Li : Integer;
  S  : string;
begin
  Result := '';
  S := OldCompilerTrace(AMap, FLOOR_INLINE_DECL, Li);
  if S <> '' then
    Result := _('an inline constant exists only from Delphi 10.3 on - the '
      + 'file shows traces of older compilers (%s, line %d); %s',
      [S, Li, MsgByHand]);
end;

// Der Plan fuer das Literal APlan.Value in Spalte ACol der Zeile ALine -
// der Teil von MagicNumber hinter LiteralAt, seit Charge B auch der von
// IntroduceAt (Code-Aktion ohne Fund): TargetAt mit dem Literal als Caret,
// nur dieses Literal (E28), dann Skript, Hauptblock und Spuren alter
// Compiler. True mit Name, Line, Col, Wrap und der einen Ersetzung, sonst
// False mit dem Grund (APlan.Value bleibt). AText = IntroTextOf(AMap) -
// IntroduceAt baut ihn schon fuer FileWideReason.
function PlanLiteral(AMap: TRdxCodeMap; const AText: TRdxIntroText;
  ALine, ACol: Integer; var APlan: TRdxMagicPlan;
  out AReason: string): Boolean;
var
  Target : TRdxIntroTarget;
begin
  Result := False;
  Target := TargetAt(AText, ALine, ACol, MAGIC_NAME_BASE);
  if not Target.Plan.Ok then
    AReason := Target.Plan.Reason
  else if (Target.Plan.Literal <> APlan.Value)
     or not KeepOnlyLiteral(AText, Target, ACol) then
    AReason := MsgMovedSuffix(_('at the literal in column %d the code action '
      + 'reads "%s" instead of %s', [ACol, Target.Plan.Literal, APlan.Value]))
  else
    AReason := ScriptReason(AMap, _(FEATURE_INLINE));
  if AReason = '' then
    AReason := MainBlockReason(AMap, ALine);
  if AReason = '' then
    AReason := CompilerReason(AMap);
  if AReason <> '' then Exit;
  APlan.Name := Target.Name;
  APlan.Line := ALine;
  APlan.Col := ACol;
  APlan.Wrap := Target.Plan.Wrap;
  AddEdit(APlan.Edits, AsOneEdit(AText, IntroduceEdits(AText, Target)));
  Result := True;
end;

class function TRdxMagicFixes.MagicNumber(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxMagicPlan;
  out AReason: string): Boolean;
var
  Col : Integer;
begin
  Result := False;
  Col := 0;
  APlan := Default(TRdxMagicPlan);
  APlan.Value := NumberOf(AMessage);
  if APlan.Value = '' then
    AReason := _('the message names no number ("Magic number "N" ...")')
  else if APlan.Value[1] = '-' then
    AReason := _('the message names %s - the detector does not report signed '
      + 'numbers, the literal has no sign; not supported', [APlan.Value])
  else
    AReason := LiteralAt(AMap, ALine, APlan.Value, Col);
  if AReason <> '' then Exit;
  Result := PlanLiteral(AMap, IntroTextOf(AMap), ALine, Col, APlan, AReason);
end;

// Die Sperren der GANZEN Datei aus der Kette von PlanLiteral - dieselben
// Pruefungen, nur ohne die Stelle: die FPC-Weiche irgendwo in der Datei
// (uRdxIntroEdits.FpcFileReason, sonst in TargetAt), Skript
// (ScriptReason) und Spuren alter Compiler (CompilerReason). Der
// Hauptblock haengt an der Zeile (die Routinen eines Programms davor sind
// frei) und gehoert nicht dazu. '' oder der Grund.
function FileWideReason(AMap: TRdxCodeMap; const AText: TRdxIntroText): string;
begin
  Result := FpcFileReason(AText);
  if Result = '' then
    Result := ScriptReason(AMap, _(FEATURE_INLINE));
  if Result = '' then
    Result := CompilerReason(AMap);
end;

const
  // Der Vorgabewert von [Detectors] MagicNumberTrivials - gespiegelt aus
  // TRepoSettings.Create (SCA.Engine\sources\Infrastructure\
  // uRepoSettings.pas, FMagicTrivials); reDelphix liest die Engine-
  // Konfiguration nicht (s. Kopf "Triviale Literale"). Zieht der
  // Vorgabewert dort um, muss er hier mit. Die laengere Liste
  // uSCAConsts.DEFAULT_MAGIC_TRIVIALS gilt nur ohne geladene Einstellungen
  // (ResetEngineConfigDefaults) - TRepoSettings ueberschreibt sie.
  SCA014_TRIVIALS: array[0..5] of string = ('0', '1', '2', '-1', '10', '100');
  // Zweierpotenzen bis hierher sind immer trivial
  // (TMagicNumberDetector.IsTrivial, uMagicNumbers.pas).
  SCA014_POW2_MAX = 1024;

// Steht ATok fuer das Ende eines Operanden - dann ist ein '-' dahinter
// binaer ('A -1', 'F(X)-1', 'P^-1')? Ein Bezeichner (kein
// Schluesselwort), eine Zahl, ')', ']' oder '^'.
function EndsOperand(AMap: TRdxCodeMap; const ATok: TRdxToken): Boolean;
begin
  if ATok.Low = '' then
    Result := False
  else if ATok.IsWord then
    Result := not (IsKeyword(ATok.Low)
      and IsKeywordAfter(ATok, Before(AMap, ATok)))
  else
    Result := CharInSet(ATok.Low[1], ['0'..'9', ')', ']', '^']);
end;

class function TRdxMagicFixes.IsTrivialLiteral(AMap: TRdxCodeMap; ALine,
  AFirst, AStop: Integer): Boolean;
var
  Value : string;
  Minus : TRdxToken;
  i, N  : Integer;
begin
  Result := False;
  Value := Copy(AMap.Raw(ALine), AFirst, AStop - AFirst);
  if Value = '' then Exit;
  // Wie SCA014 nur eine dezimale Ganzzahl (der Detektor liest Ziffern).
  for i := 1 to Length(Value) do
    if not CharInSet(Value[i], ['0'..'9']) then Exit;
  // Ein unaeres '-' direkt davor gehoert zum Wert.
  Minus := PrevToken(AMap, ALine, AFirst);
  if (Minus.Low = '-') and (Minus.Line = ALine) and (Minus.EndCol = AFirst)
     and not EndsOperand(AMap, Before(AMap, Minus)) then
    Value := '-' + Value;
  for i := Low(SCA014_TRIVIALS) to High(SCA014_TRIVIALS) do
    if Value = SCA014_TRIVIALS[i] then Exit(True);
  Result := TryStrToInt(Value, N) and (N > 0) and (N <= SCA014_POW2_MAX)
    and ((N and (N - 1)) = 0);
end;

class function TRdxMagicFixes.IntroduceAt(AMap: TRdxCodeMap; ALine,
  ACol: Integer; out APlan: TRdxMagicPlan; out AReason: string): Boolean;
var
  First, Stop : Integer;
  Text        : TRdxIntroText;
begin
  Result := False;
  AReason := '';
  APlan := Default(TRdxMagicPlan);
  if LiteralContaining(AMap, ALine, ACol, First, Stop) <> lkNumber then
    Exit;   // kein Kandidat (F4): kein Eintrag
  // Ein triviales Literal (die Menge von SCA014): wie kein Kandidat
  // (Entscheid Nico 2026-10-24).
  if IsTrivialLiteral(AMap, ALine, First, Stop) then
    Exit;
  APlan.Value := Copy(AMap.Raw(ALine), First, Stop - First);
  // Erst die ganze Datei, dann die Stelle: eine FPC-Unit mit dem Literal
  // in einer Deklarationszeile ist zuerst eine FPC-Unit (Entscheid Nico
  // 2026-10-24: dort kein Eintrag, auch kein gesperrter).
  Text := IntroTextOf(AMap);
  AReason := FileWideReason(AMap, Text);
  if AReason <> '' then
  begin
    APlan.FileWide := True;
    Exit;
  end;
  // Die Code-Aktion liest nur dezimale und hexadezimale Zahlen
  // (uRdxIntroPlan.NumbersOf); ein Delphi-11-Binaer- bzw. Oktal-Literal
  // fiele dort als "kein Zahl-Literal am Caret" durch - der Satz sagt,
  // warum.
  if CharInSet(APlan.Value[1], ['%', '&']) then
  begin
    AReason := _('%s is a binary or octal literal - the code action only '
      + 'handles decimal and hexadecimal numbers', [APlan.Value]);
    Exit;
  end;
  Result := PlanLiteral(AMap, Text, ALine, First, APlan, AReason);
end;

{ ---- Was nur die Platte weiss ---- }

type
  // Die Projektdateien EINES Verzeichnisses (ProjectFilesIn): die erste
  // Lazarus- und die erste alte Delphi-Projektdatei, die .dproj mit der
  // kleinsten ProjectVersion (Zehntel; -1 ohne lesbare Version) - bzw.
  // die erste vor 10.3, danach liest NoteProjectFile keine .dproj mehr.
  // Seit rwE30 Stufe 2 dazu je Projekt (gleicher Name ohne Endung, PairsIn):
  //   OldPair  die Optionsdatei (.dof, .cfg, .bdsproj) eines Projekts
  //            (.dpr/.dpk) OHNE .dproj gleichen Namens - auch neben .dproj
  //            anderer Projekte (CnDebugViewer.dpr/.dof/.cfg neben
  //            CnDebugViewer64.dproj: der eine Bau ist Delphi 5-7);
  //   LoneDpr  ein Programm (.dpr) ganz ohne Projektdatei gleichen Namens -
  //            neben einem Lazarus-Projekt ein Doppel-Compiler-Projekt fuer
  //            altes Delphi (RechnungDelphi.dpr neben Rechnung.lpi); seit
  //            rwE32 Stufe 4 nicht, wenn es ein FPC-Programm ist
  //            (FpcOnlyProgram: Hauptdatei einer .lpi, FPC-only-Units);
  //   Programs die .dpr des Verzeichnisses (SettingsProgramReason).
  // Bases/OptBases/DprojBases sammeln die Namen fuer PairsIn (klein),
  // LazProjects die .lpi (FpcOnlyProgram).
  TRdxProjectFiles = record
    Lazarus    : string;
    Legacy     : string;
    Dproj      : string;
    DprojVer   : Integer;
    OldPair    : string;
    LoneDpr    : string;
    Programs   : TArray<string>;
    Bases      : TArray<string>;
    Opts       : TArray<string>;
    DprojBases : TArray<string>;
    LazProjects: TArray<string>;
  end;

// Die ersten DPROJ_HEAD_BYTES der Datei APath als ANSI-Text; False, wenn
// sie nicht lesbar ist. Bis rwE29 in ProjectVersionOf; seitdem liest auch
// PackagesReason so die .dpk.
function HeadText(const APath: string; out AText: string): Boolean;
var
  FS    : TFileStream;
  Bytes : TBytes;
begin
  Result := False;
  AText := '';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, DPROJ_HEAD_BYTES);
      SetLength(Bytes, FS.Read(Bytes[0], DPROJ_HEAD_BYTES));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  AText := TEncoding.ANSI.GetString(Bytes);
  Result := True;
end;

// Die ProjectVersion der .dproj APath in Zehnteln ('18.5' -> 185; nur die
// erste Nachkommastelle); -1, wenn die Datei nicht lesbar ist oder keine
// traegt (Delphi 2007 schrieb noch keine).
function ProjectVersionOf(const APath: string): Integer;
var
  Text  : string;
  P, i  : Integer;
begin
  Result := -1;
  if not HeadText(APath, Text) then Exit;
  P := Pos(PROJECT_VERSION_TAG, Text);
  if P = 0 then Exit;
  i := P + Length(PROJECT_VERSION_TAG);
  P := i;
  while (i <= Length(Text)) and CharInSet(Text[i], ['0'..'9']) do
    Inc(i);
  if i = P then Exit;
  Result := StrToIntDef(Copy(Text, P, i - P), -1);
  if Result < 0 then Exit;
  Result := Result * 10;
  if (i < Length(Text)) and (Text[i] = '.') and CharInSet(Text[i + 1], ['0'..'9']) then
    Inc(Result, Ord(Text[i + 1]) - Ord('0'));
end;

// Die Datei AName des Verzeichnisses ADir in AFiles eintragen; AMinVersion
// die ProjectVersion der Schwelle (TRdxCompilerFloor.ProjectVersion).
procedure NoteProjectFile(const ADir, AName: string; AMinVersion: Integer;
  var AFiles: TRdxProjectFiles);
var
  Ext : string;
  Ver : Integer;
begin
  Ext := LowerCase(ExtractFileExt(AName));
  // Die Namen fuer PairsIn (jede Datei, vor jedem Exit).
  if (Ext = DPR_EXTENSION) or (Ext = DPK_EXTENSION) then
    AddText(AFiles.Bases, LowerCase(ChangeFileExt(AName, '')));
  if Ext = DPR_EXTENSION then
    AddText(AFiles.Programs, AName);
  if InList(Ext, PAIR_OPTION_EXTENSIONS) then
    AddText(AFiles.Opts, AName);
  if Ext = DPROJ_EXTENSION then
    AddText(AFiles.DprojBases, LowerCase(ChangeFileExt(AName, '')));
  if Ext = LPI_EXTENSION then
    AddText(AFiles.LazProjects, AName);
  if InList(Ext, LAZARUS_EXTENSIONS) then
  begin
    if AFiles.Lazarus = '' then
      AFiles.Lazarus := AName;
  end
  else if InList(Ext, LEGACY_EXTENSIONS) then
  begin
    if AFiles.Legacy = '' then
      AFiles.Legacy := AName;
  end
  else if Ext = DPROJ_EXTENSION then
  begin
    // Eine .dproj vor der Schwelle (oder ohne Version) steht schon fest:
    // sie sperrt ohnehin, weitere Koepfe zu lesen kostete im Hauptthread je
    // Datei 64 KB (Paketordner mit vielen .dproj; Wochen-Review
    // 2026-10-21). Der Grund nennt dann die erste alte statt der aeltesten.
    if (AFiles.Dproj <> '') and (AFiles.DprojVer < AMinVersion) then
      Exit;
    Ver := ProjectVersionOf(IncludeTrailingPathDelimiter(ADir) + AName);
    if (AFiles.Dproj = '') or (Ver < AFiles.DprojVer) then
    begin
      AFiles.Dproj := AName;
      AFiles.DprojVer := Ver;
    end;
  end;
end;

// Ist das Programm APrg in ADir ein FPC-Programm (rwE32 Stufe 4, Nico-
// Entscheid: ein FPC-only-Projekt ist kein Beleg fuer ein altes Delphi)?
// Ja, wenn eine .lpi des Verzeichnisses (ALazProjects) es als Datei nennt
// ('<Filename Value="Zip.dpr"/>' - in einem Lazarus-Projekt die
// Hauptdatei; doublecmd plugins\wcx\zip\src, wdx\deb_wdx\src,
// wcx\sevenzip\src) oder es eine Unit nur von FPC/Lazarus ausserhalb jeder
// Weiche einbindet (FPC_ONLY_UNITS: 'FPCAdds', 'CMem' ...). PairsIn fragt
// es nur fuer ein Programm ohne eigene Projektdatei.
function FpcOnlyProgram(const ADir, APrg: string;
  const ALazProjects: TArray<string>): Boolean;
var
  Lpi, Text, Key : string;
  SL             : TStringList;
  Map            : TRdxCodeMap;
begin
  Result := False;
  Key := LPI_FILE_TAG + LowerCase(APrg) + '"';
  for Lpi in ALazProjects do
    if HeadText(IncludeTrailingPathDelimiter(ADir) + Lpi, Text)
       and (Pos(Key, LowerCase(Text)) > 0) then
      Exit(True);
  if not HeadText(IncludeTrailingPathDelimiter(ADir) + APrg, Text) then
    Exit;
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Text;
    Map := TRdxCodeMap.Create(SL);
    Result := UnconditionalUsesOf(Map, FPC_ONLY_UNITS) <> '';
  finally
    Map.Free;
    SL.Free;
  end;
end;

// OldPair und LoneDpr aus den gesammelten Namen (s. TRdxProjectFiles): je
// Projekt der erste Treffer in der Reihenfolge der Platte. ADir: das
// Verzeichnis (FpcOnlyProgram liest dort .lpi und .dpr).
procedure PairsIn(var AFiles: TRdxProjectFiles; const ADir: string);
var
  Base, Opt, Prg : string;
  Paired         : Boolean;
begin
  for Opt in AFiles.Opts do
  begin
    Base := LowerCase(ChangeFileExt(Opt, ''));
    if InList(Base, AFiles.Bases) and not InList(Base, AFiles.DprojBases) then
    begin
      AFiles.OldPair := Opt;
      Break;
    end;
  end;
  for Prg in AFiles.Programs do
  begin
    Base := LowerCase(ChangeFileExt(Prg, ''));
    Paired := InList(Base, AFiles.DprojBases);
    for Opt in AFiles.Opts do
      Paired := Paired or (LowerCase(ChangeFileExt(Opt, '')) = Base);
    if not Paired and not ((AFiles.Lazarus <> '')
       and FpcOnlyProgram(ADir, Prg, AFiles.LazProjects)) then
    begin
      AFiles.LoneDpr := Prg;
      Break;
    end;
  end;
end;

// Die Projektdateien in ADir (EIN Durchlauf ueber das Verzeichnis).
function ProjectFilesIn(const ADir: string;
  AMinVersion: Integer): TRdxProjectFiles;
var
  SR : TSearchRec;
begin
  Result := Default(TRdxProjectFiles);
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        NoteProjectFile(ADir, SR.Name, AMinVersion, Result);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  PairsIn(Result, ADir);
end;

// Die ProjectVersion in Zehnteln als Text ('185' -> '18.5').
function VersionText(AVersion: Integer): string;
begin
  Result := Format('%d.%d', [AVersion div 10, AVersion mod 10]);
end;

// Die Delphi-Projektdateien eines Verzeichnisses als Grund: eine .dproj
// vor der Schwelle von AFeature bzw. - ohne .dproj - eine alte
// Projektdatei; seit rwE30 Stufe 2 auch ein Projekt mit alter
// Optionsdatei ohne eigene .dproj (OldPair, auch neben neuen .dproj) und
// ein Programm ohne Projektdatei neben einem Lazarus-Projekt (LoneDpr);
// '' sonst.
function DelphiProjectReason(const AFiles: TRdxProjectFiles;
  const ADir: string; AFeature: TRdxLateFeature): string;
var
  MinVer : Integer;
begin
  Result := '';
  MinVer := FloorOf(AFeature).ProjectVersion;
  if AFiles.Dproj <> '' then
  begin
    if AFiles.DprojVer < 0 then
      Result := _(R_NO_VERSION[AFeature], [AFiles.Dproj, ADir, MsgByHand])
    else if AFiles.DprojVer < MinVer then
      Result := _(R_OLD_DPROJ[AFeature], [AFiles.Dproj, ADir,
        VersionText(AFiles.DprojVer), VersionText(MinVer), MsgByHand]);
  end
  else if AFiles.Legacy <> '' then
    Result := _(R_LEGACY[AFeature], [AFiles.Legacy, ADir, MsgByHand]);
  if (Result = '') and (AFiles.OldPair <> '') then
    Result := _(R_LEGACY[AFeature], [AFiles.OldPair, ADir, MsgByHand]);
  if (Result = '') and (AFiles.LoneDpr <> '') and (AFiles.Lazarus <> '') then
    Result := _(R_DUAL_PROJECT[AFeature], [AFiles.LoneDpr, AFiles.Lazarus,
      ADir, MsgByHand]);
end;

// Traegt das Verzeichnis Delphi-Projektdateien, die DelphiProjectReason
// liest (das NAECHSTE solche Verzeichnis entscheidet, ProjectWalkReason)?
function HasDelphiProject(const AFiles: TRdxProjectFiles): Boolean;
begin
  Result := (AFiles.Dproj <> '') or (AFiles.Legacy <> '')
    or (AFiles.OldPair <> '')
    or ((AFiles.LoneDpr <> '') and (AFiles.Lazarus <> ''));
end;

{ ---- Pakete, die die Unit enthalten (rwE29) ---- }

function MaxOf(A, B: Integer): Integer;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

{ TRdxPackageVersion }

class function TRdxPackageVersion.Jedi(J: Integer): Integer;
begin
  case J of
    5..10:  Result := J + 8;    // Delphi 5 = 13 ... Delphi 2006 = 18
    11:     Result := 18;       // Delphi 2007 (18.5)
    12:     Result := 20;       // Delphi 2009
    14..29: Result := J + 7;    // Delphi 2010 = 21 ... 11 = 35, 12 = 36
    37:     Result := 37;       // Delphi 13 (Paketversion 370)
  else
    Result := -1;
  end;
end;

class function TRdxPackageVersion.Product(AMajor, AMinor: Integer): Integer;
begin
  if (AMajor = 10) and (AMinor >= 0) and (AMinor <= 4) then
    Result := 30 + AMinor
  else if (AMajor >= 11) and (AMajor <= 13) then
    Result := 24 + AMajor
  else
    Result := -1;
end;

// Zwei Lesarten - die hoechste zaehlt ('d110' ist bei DMVC Delphi 11, als
// Paketversion Delphi 2007).
class function TRdxPackageVersion.Number(N: Integer): Integer;
begin
  Result := -1;
  if N mod 10 = 0 then
    Result := Jedi(N div 10);
  if N >= 100 then
    Result := MaxOf(Result, Product(N div 10, N mod 10));
end;

class function TRdxPackageVersion.Year(N: Integer): Integer;
begin
  case N of
    2005: Result := 17;
    2006, 2007: Result := 18;
    2009: Result := 20;
    2010: Result := 21;
  else
    Result := -1;
  end;
end;

// Die Buchstaben (a..z) direkt vor S[AAt], '' ohne.
function LettersBefore(const S: string; AAt: Integer): string;
var
  j : Integer;
begin
  j := AAt - 1;
  while (j >= 1) and CharInSet(S[j], ['a'..'z']) do
    Dec(j);
  Result := Copy(S, j + 1, AAt - j - 1);
end;

class function TRdxPackageVersion.Folder(const AName: string): Integer;
var
  S, Adj, Sep         : string;
  i, j, k, Start      : Integer;
  Digits, N1, N2, V   : Integer;
  HasMinor, IsDelphi  : Boolean;
begin
  Result := -1;
  S := LowerCase(AName);
  i := 1;
  while i <= Length(S) do
  begin
    if CharInSet(S[i], ['a'..'z']) then
    begin
      j := i;
      while (j <= Length(S)) and CharInSet(S[j], ['a'..'z']) do
        Inc(j);
      Adj := Copy(S, i, j - i);
      for k := 0 to High(CODE_NAMES) do
        if Adj = CODE_NAMES[k] then
          Result := MaxOf(Result, 30 + k);
      // 'XE' als ganzes Wort ohne Ziffer dahinter: Delphi XE (22) - nicht
      // das Ende von 'Deluxe'.
      if InList(Adj, XE_WORDS)
         and not ((j <= Length(S)) and CharInSet(S[j], ['0'..'9'])) then
        Result := MaxOf(Result, 22);
      i := j;
      Continue;
    end;
    if not CharInSet(S[i], ['0'..'9']) then
    begin
      Inc(i);
      Continue;
    end;
    // Das Wort davor: direkt anliegend (Adj) oder durch ' ', '_', '-'
    // getrennt (Sep: 'Delphi 11', 'Delphi_12', 'RAD Studio 10.4').
    Start := i;
    Adj := LettersBefore(S, i);
    Sep := '';
    if (Adj = '') and (i > 2) and CharInSet(S[i - 1], [' ', '_', '-']) then
      Sep := LettersBefore(S, i - 1);
    N1 := 0;
    Digits := 0;
    while (i <= Length(S)) and CharInSet(S[i], ['0'..'9']) do
    begin
      if Digits < 4 then
        N1 := N1 * 10 + Ord(S[i]) - Ord('0');
      Inc(Digits);
      Inc(i);
    end;
    N2 := 0;
    HasMinor := (i < Length(S)) and CharInSet(S[i], ['.', '_'])
      and CharInSet(S[i + 1], ['0'..'9']);
    if HasMinor then
    begin
      Inc(i);
      N2 := Ord(S[i]) - Ord('0');
      while (i <= Length(S)) and CharInSet(S[i], ['0'..'9']) do
        Inc(i);
    end;
    IsDelphi := InList(Adj, DELPHI_WORDS) or (Sep = DELPHI_WORDS[1]);
    V := -1;
    if InList(Adj, XE_WORDS) then
    begin
      if not HasMinor and (Digits = 1) and (N1 >= 2) and (N1 <= 8) then
        V := 21 + N1;                    // XE2 = 23 ... XE8 = 29
    end
    else if InList(Adj, CBUILDER_WORDS) then
    begin
      if not HasMinor and (Digits = 1) and (N1 >= 5) and (N1 <= 6) then
        V := N1 + 8;                     // C++Builder 5/6 = Delphi 5/6
    end
    else if HasMinor then
    begin
      if IsDelphi or (Sep = STUDIO_WORD)
         or ((Adj = '') and (Sep = '') and (Start = 1)) then
        V := Product(N1, N2);
    end
    else if IsDelphi then
      case Digits of
        1, 2: V := MaxOf(Jedi(N1), Product(N1, 0));
        3:    V := Number(N1);
        4:    V := Year(N1);
      end;
    Result := MaxOf(Result, V);
  end;
end;

class function TRdxPackageVersion.LibSuffix(const ALowText: string;
  out AValue: string): Integer;
var
  P, i : Integer;
begin
  Result := -1;
  AValue := '';
  P := Pos(LIBSUFFIX_TAG, ALowText);
  if P = 0 then Exit;
  i := P + Length(LIBSUFFIX_TAG);
  while (i <= Length(ALowText)) and CharInSet(ALowText[i], ['0'..'9']) do
    Inc(i);
  AValue := Copy(ALowText, P + Length(LIBSUFFIX_TAG),
    i - P - Length(LIBSUFFIX_TAG));
  if (Length(AValue) >= 2) and (Length(AValue) <= 3)
     and (i <= Length(ALowText)) and (ALowText[i] = '''') then
    Result := Number(StrToInt(AValue));
end;

// Nennt die .dpk (Kopf klein geschrieben) die Unit-Datei ALowFile
// ('mvcframework.objectpool.pas')? Gesucht wird die Form der in-Klausel
// ('..\..\sources\X.pas'' bzw. ''X.pas'''): davor '\', '/' oder ''''.
function DpkContains(const ALowText, ALowFile: string): Boolean;
var
  Key  : string;
  P, i : Integer;
begin
  Result := False;
  Key := ALowFile + '''';
  i := 1;
  while i + Length(Key) - 1 <= Length(ALowText) do
  begin
    P := Pos(Key, Copy(ALowText, i, MaxInt));
    if P = 0 then Exit;
    P := P + i - 1;
    if (P = 1) or CharInSet(ALowText[P - 1], ['\', '/', '''']) then
      Exit(True);
    i := P + 1;
  end;
end;

type
  // Was ein Lauf des Plattenblicks liest (ProjectWalkReason), je mit
  // Deckel: Paketkoepfe (MAX_PACKAGE_READS - erschoepft ein Grund, ausser
  // fuer lfExceptionClasses), Programme (MAX_PROGRAM_READS) und die Units
  // eines alten Pakets (MAX_PACKAGE_UNIT_BYTES; beides erschoepft: kein
  // Beleg bzw. keine Widerlegung). Seen/Proven: die schon gelesenen Units
  // (klein) und die davon mit TFormatSettings.Invariant - DMVC nennt
  // dieselben Units in d100, d101 und d102.
  TRdxWalkBudget = record
    Packages  : Integer;
    Programs  : Integer;
    UnitBytes : Int64;
    Seen      : TArray<string>;
    Proven    : TArray<string>;
  end;

// Die Units einer .dpk ('X in ''..\src\X.pas''' im Kopf, klein): je der
// Pfad relativ zu ADir aufgeloest.
function DpkUnitPaths(const ADir, ALowText: string): TArray<string>;
var
  i, P, Q : Integer;
  Path    : string;
begin
  Result := nil;
  i := 1;
  while True do
  begin
    P := Pos(DPK_IN_TAG, Copy(ALowText, i, MaxInt));
    if P = 0 then Exit;
    P := P + i - 1 + Length(DPK_IN_TAG);
    Q := P;
    while (Q <= Length(ALowText)) and (ALowText[Q] <> '''') do
      Inc(Q);
    Path := Copy(ALowText, P, Q - P);
    if LowerCase(ExtractFileExt(Path)) = '.pas' then
      AddText(Result, ExpandFileName(IncludeTrailingPathDelimiter(ADir) + Path));
    i := Q + 1;
  end;
end;

// Nutzt die Unit APath TFormatSettings.Invariant ausserhalb jedes
// Bedingungsblocks (UnconditionalInvariantLine)? Gelesen nur bis zum
// Deckel ABudget.UnitBytes; was nicht gelesen ist, beweist nichts.
function UnitUsesInvariant(const APath: string;
  var ABudget: TRdxWalkBudget): Boolean;
var
  Key   : string;
  FS    : TFileStream;
  Bytes : TBytes;
  Text  : string;
  SL    : TStringList;
  Map   : TRdxCodeMap;
begin
  Key := LowerCase(APath);
  if InList(Key, ABudget.Seen) then
    Exit(InList(Key, ABudget.Proven));
  Result := False;
  if not FileExists(APath) then Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if ABudget.UnitBytes + FS.Size > MAX_PACKAGE_UNIT_BYTES then Exit;
      Inc(ABudget.UnitBytes, FS.Size);
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        SetLength(Bytes, FS.Read(Bytes[0], Length(Bytes)));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  AddText(ABudget.Seen, Key);
  Text := TEncoding.ANSI.GetString(Bytes);
  if Pos(INVARIANT_TEXT, LowerCase(Text)) = 0 then Exit;
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Text;
    Map := TRdxCodeMap.Create(SL);
    Result := UnconditionalInvariantLine(Map) > 0;
  finally
    Map.Free;
    SL.Free;
  end;
  if Result then
    AddText(ABudget.Proven, Key);
end;

// Widerlegt eine Unit der .dpk (Kopf klein ALowText im Ordner ADir) die
// Versionssperre des Invariant-Wegs - nutzt sie TFormatSettings.Invariant
// ohne Weiche, baut das Paket auf seinem alten Delphi mit Invariant
// (rwE30 Stufe 2: loggerproRT.dpk in d100 mit LoggerPro.Renderers.pas,
// dmvcframeworkRT.dpk mit MVCFramework.Serializer.Commons.pas)?
function PackageUsesInvariant(const ADir, ALowText: string;
  var ABudget: TRdxWalkBudget): Boolean;
var
  Path : string;
begin
  Result := False;
  for Path in DpkUnitPaths(ADir, ALowText) do
    if UnitUsesInvariant(Path, ABudget) then
      Exit(True);
end;

// Die .dpk im Paketordner ADir (AFolderVersion: die Version aus seinem
// Namen, -1 ohne), die die Unit ALowFile enthalten: ist eine fuer ein
// aelteres Delphi als die Schwelle (Ordnername, LIBSUFFIX - der hebt nur
// an; ohne beides die Projektdateien des Ordners wie DelphiProjectReason),
// der Grund - fuer den Invariant-Weg nur, wenn keine Unit des Pakets
// Invariant ohne Weiche nutzt (PackageUsesInvariant, rwE30 Stufe 2). Ist
// der Deckel erschoepft und steht hier noch eine .dpk, auch - sie bleibt
// ungelesen (R_PACKAGES_UNREAD; nicht fuer lfExceptionClasses,
// MissingBlocks). '' sonst.
function DpkDirReason(const ADir: string; AFolderVersion: Integer;
  const ALowFile: string; AFeature: TRdxLateFeature;
  var ABudget: TRdxWalkBudget): string;
var
  SR               : TSearchRec;
  Text, Lib, Proof : string;
  V, LibV          : Integer;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*' + DPK_EXTENSION,
       faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0)
         or (LowerCase(ExtractFileExt(SR.Name)) <> DPK_EXTENSION) then
        Continue;
      if ABudget.Packages >= MAX_PACKAGE_READS then
      begin
        if TRdxMagicFixes.MissingBlocks(AFeature) then
          Result := _(R_PACKAGES_UNREAD[AFeature], [ADir, MAX_PACKAGE_READS,
            MsgByHand]);
        Exit;
      end;
      Inc(ABudget.Packages);
      if not HeadText(IncludeTrailingPathDelimiter(ADir) + SR.Name, Text) then
        Continue;
      Text := LowerCase(Text);
      if not DpkContains(Text, ALowFile) then Continue;
      V := AFolderVersion;
      Proof := ExtractFileName(ExcludeTrailingPathDelimiter(ADir));
      LibV := TRdxPackageVersion.LibSuffix(Text, Lib);
      if LibV > V then
      begin
        V := LibV;
        Proof := 'LIBSUFFIX ''' + Lib + '''';
      end;
      if V < 0 then
        Result := DelphiProjectReason(ProjectFilesIn(ADir,
          FloorOf(AFeature).ProjectVersion), ADir, AFeature)
      else if V < FloorOf(AFeature).Version then
        Result := _(R_OLD_PACKAGE[AFeature], [SR.Name, ADir, Proof,
          MsgByHand]);
      if (Result <> '') and (AFeature = lfFormatInvariant)
         and PackageUsesInvariant(ADir, Text, ABudget) then
        Result := '';
      if Result <> '' then Exit;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Die Paketordner unter APkg (APkg selbst und seine Unterordner), die
// gelesen werden: ohne die, deren Name schon eine Version ab AFloor belegt
// (Review e/HilfeFixB - sie koennen nur neu sein, LIBSUFFIX hebt nur an);
// alte (AOld, Version im Namen) und unbekannte (AUnknown) getrennt, je in
// der Reihenfolge der Platte. AAll: alle, auch die neuen (die Programme
// darin, SettingsProgramReason).
procedure CollectPackageDirs(const APkg: string; AFloor: Integer;
  var AOld, AUnknown: TArray<string>; var AOldVer: TArray<Integer>;
  var AAll: TArray<string>);
var
  SR   : TSearchRec;
  Path : string;
  V    : Integer;

  procedure Note(const ADir: string; AVersion: Integer);
  begin
    AddText(AAll, ADir);
    if AVersion >= AFloor then Exit;
    if AVersion >= 0 then
    begin
      SetLength(AOld, Length(AOld) + 1);
      AOld[High(AOld)] := ADir;
      SetLength(AOldVer, Length(AOldVer) + 1);
      AOldVer[High(AOldVer)] := AVersion;
    end
    else
    begin
      SetLength(AUnknown, Length(AUnknown) + 1);
      AUnknown[High(AUnknown)] := ADir;
    end;
  end;

begin
  Note(APkg, TRdxPackageVersion.Folder(ExtractFileName(
    ExcludeTrailingPathDelimiter(APkg))));
  if FindFirst(IncludeTrailingPathDelimiter(APkg) + '*', faDirectory,
       SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) = 0) or (SR.Name = '.')
         or (SR.Name = '..') then
        Continue;
      Path := IncludeTrailingPathDelimiter(APkg) + SR.Name;
      V := TRdxPackageVersion.Folder(SR.Name);
      Note(Path, V);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Die .dpr in ADir (Dateinamen).
function ProgramsIn(const ADir: string): TArray<string>;
var
  SR : TSearchRec;
begin
  Result := nil;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*' + DPR_EXTENSION,
       faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) = 0)
         and (LowerCase(ExtractFileExt(SR.Name)) = DPR_EXTENSION) then
        AddText(Result, SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Ein Programm APrograms in ADir, das die Unit AFileName enthaelt (in-
// Klausel wie DpkContains) und die globale FormatSettings selbst setzt
// (uRdxCompilerTraces.GlobalSettingsWriteLine im Kopf der .dpr): der Grund
// fuer den Invariant-Weg, '' sonst. Hoechstens MAX_PROGRAM_READS je Lauf;
// danach: kein Beleg.
function SettingsProgramReason(const ADir: string;
  const APrograms: TArray<string>; const AFileName: string;
  var ABudget: TRdxWalkBudget): string;
var
  Prg, Text, Field : string;
  SL               : TStringList;
  Map              : TRdxCodeMap;
  Li               : Integer;
begin
  Result := '';
  for Prg in APrograms do
  begin
    if ABudget.Programs >= MAX_PROGRAM_READS then Exit;
    Inc(ABudget.Programs);
    if not HeadText(IncludeTrailingPathDelimiter(ADir) + Prg, Text) then
      Continue;
    if not DpkContains(LowerCase(Text),
         LowerCase(ExtractFileName(AFileName))) then
      Continue;
    SL := TStringList.Create;
    Map := nil;
    try
      SL.Text := Text;
      Map := TRdxCodeMap.Create(SL);
      Li := GlobalSettingsWriteLine(Map, Field);
    finally
      Map.Free;
      SL.Free;
    end;
    if Li > 0 then
      Exit(_(R_PROGRAM_SETTINGS, [Prg, ADir, Field, Li, MsgByHand]));
  end;
end;

// Pakete unter ADir (Unterordner PACKAGE_DIRS und eine Ebene darin), die
// die Unit AFileName enthalten und fuer ein aelteres Delphi sind - bzw. ein
// alter oder unbekannter Paketordner, den der Deckel nicht mehr liest. ''
// oder der Grund. Erst die alten Ordner, dann die unbekannten. Fuer den
// Invariant-Weg dazu die Programme in JEDEM dieser Ordner
// (SettingsProgramReason; HeidiSQL packages\Delphi12.3\heidisql.dpr).
function PackagesReason(const ADir, AFileName: string;
  AFeature: TRdxLateFeature; var ABudget: TRdxWalkBudget): string;
var
  Pkg, LowFile      : string;
  Old, Unknown, All : TArray<string>;
  OldVer            : TArray<Integer>;
  i, k              : Integer;
begin
  Result := '';
  LowFile := LowerCase(ExtractFileName(AFileName));
  for i := 0 to High(PACKAGE_DIRS) do
  begin
    Pkg := IncludeTrailingPathDelimiter(ADir) + PACKAGE_DIRS[i];
    if not DirectoryExists(Pkg) then Continue;
    Old := nil;
    Unknown := nil;
    OldVer := nil;
    All := nil;
    CollectPackageDirs(Pkg, FloorOf(AFeature).Version, Old, Unknown, OldVer,
      All);
    for k := 0 to High(Old) do
    begin
      Result := DpkDirReason(Old[k], OldVer[k], LowFile, AFeature, ABudget);
      if Result <> '' then Exit;
    end;
    for k := 0 to High(Unknown) do
    begin
      Result := DpkDirReason(Unknown[k], -1, LowFile, AFeature, ABudget);
      if Result <> '' then Exit;
    end;
    if AFeature = lfFormatInvariant then
      for k := 0 to High(All) do
      begin
        Result := SettingsProgramReason(All[k], ProgramsIn(All[k]), AFileName,
          ABudget);
        if Result <> '' then Exit;
      end;
  end;
end;

// Netzpfad: uRdxPaths.IsNetworkPath (UNC und Netzlaufwerk, seit Charge
// B1-FD die eine Regel fuer Unit und Includes - bis dahin stand hier eine
// eigene Kopie nur fuer UNC; seit Charge B2S-a ist '\\?\C:\..' lokal).
// Die Projektdateien im Verzeichnis der Unit und bis PROJECT_LEVELS
// darueber (der Plattenteil von FileReason, s. dort), je Ebene dazu die
// Pakete in ihrem Unterordner packages (PackagesReason, rwE29) - '' oder
// der Grund.
function ProjectWalkReason(const AFileName: string;
  AFeature: TRdxLateFeature): string;
var
  Dir, Up    : string;
  Level      : Integer;
  Files      : TRdxProjectFiles;
  DelphiSeen : Boolean;
  Budget     : TRdxWalkBudget;
begin
  Result := '';
  Dir := ExtractFileDir(AFileName);
  DelphiSeen := False;
  Budget := Default(TRdxWalkBudget);
  for Level := 0 to PROJECT_LEVELS do
  begin
    if Dir = '' then Exit;
    Files := ProjectFilesIn(Dir, FloorOf(AFeature).ProjectVersion);
    if (Files.Lazarus <> '') and not TRdxMagicFixes.FpcKnows(AFeature) then
      Exit(_(R_LAZARUS[AFeature], [Files.Lazarus, Dir]));
    // Das NAECHSTE Verzeichnis mit Delphi-Projektdateien entscheidet
    // (eine .dproj ab der Schwelle dort macht alte Dateien weiter oben
    // stumm).
    if not DelphiSeen then
    begin
      Result := DelphiProjectReason(Files, Dir, AFeature);
      if Result <> '' then Exit;
      DelphiSeen := HasDelphiProject(Files);
    end;
    // Ein Programm, das die Unit enthaelt und die globale FormatSettings
    // selbst setzt (nur Invariant; rwE30 Stufe 2) - in jedem Verzeichnis
    // des Fensters.
    if AFeature = lfFormatInvariant then
    begin
      Result := SettingsProgramReason(Dir, Files.Programs, AFileName, Budget);
      if Result <> '' then Exit;
    end;
    // Ein Paket, das die Unit enthaelt, baut sie - auf jeder Ebene, auch
    // hinter einer .dproj ab der Schwelle (DMVC: sources\ ohne Projekt,
    // packages\d100..d104 eine Ebene hoeher).
    Result := PackagesReason(Dir, AFileName, AFeature, Budget);
    if Result <> '' then Exit;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Exit;
    Dir := Up;
  end;
end;

var
  // Der aktive Cache des Plattenblicks (UseDiskCache), nil = keiner. Ohne
  // Sperre: Anmelden, Nachschlagen und Abmelden laufen nur im
  // IDE-Hauptthread (Gluehbirne, Menueaufbau; reDelphix startet keine
  // Threads). Ein Aufruf von FileReason/IncludeReason aus einem anderen
  // Thread braucht zuerst eine Sperre oder einen Cache je Thread.
  GDiskCache : TRdxDiskReasonCache = nil;

// Der Schluessel eines Eintrags: Art ('F' FileReason, 'I' IncludeReason),
// Sprachmittel, reDelphix-Sprache (die Gruende sind uebersetzt), Dateiname
// und - fuer IncludeReason - die Serial der Map, je mit #0 getrennt (in
// keinem Dateinamen).
function DiskKey(AKind: Char; AFeature: TRdxLateFeature;
  const AFileName, ARest: string): string;
begin
  Result := AKind + IntToStr(Ord(AFeature)) + #0 + RdxLanguage + #0
    + AFileName + #0 + ARest;
end;

class function TRdxMagicFixes.FileReason(const AFileName: string;
  AFeature: TRdxLateFeature): string;
var
  Ext, Key : string;
begin
  Result := '';
  if AFileName = '' then Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if InList(Ext, FPC_EXTENSIONS) and not FpcKnows(AFeature) then
    Exit(_(R_FPC_FILE[AFeature], [Ext]));
  // Das Netzpfad-Gate laeuft je Aufruf, vor dem Cache (Charge P5).
  if IsNetworkPath(AFileName) then
    Exit(_(R_NETWORK, [ExtractFileDir(AFileName), MsgByHand]));
  if GDiskCache = nil then
    Exit(ProjectWalkReason(AFileName, AFeature));
  Key := DiskKey('F', AFeature, AFileName, '');
  if GDiskCache.FItems.TryGetValue(Key, Result) then Exit;
  Result := ProjectWalkReason(AFileName, AFeature);
  GDiskCache.FItems.AddOrSetValue(Key, Result);
end;

class function TRdxMagicFixes.FpcKnows(AFeature: TRdxLateFeature): Boolean;
begin
  Result := (AFeature = lfFormatSettingsVar)
    or (AFeature = lfExceptionClasses);
end;

class function TRdxMagicFixes.MissingBlocks(
  AFeature: TRdxLateFeature): Boolean;
begin
  Result := AFeature <> lfExceptionClasses;
end;

// Die .dpk in ADir, die die Unit ALowFile enthalten und eine Unit, die
// TFormatSettings.Invariant ohne Weiche nutzt (PackageUsesInvariant)?
// Hoechstens bis zum Deckel ABudget.Packages - danach: nein.
function DirProvesInvariant(const ADir, ALowFile: string;
  var ABudget: TRdxWalkBudget): Boolean;
var
  SR   : TSearchRec;
  Text : string;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*' + DPK_EXTENSION,
       faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0)
         or (LowerCase(ExtractFileExt(SR.Name)) <> DPK_EXTENSION) then
        Continue;
      if ABudget.Packages >= MAX_PACKAGE_READS then Exit;
      Inc(ABudget.Packages);
      if not HeadText(IncludeTrailingPathDelimiter(ADir) + SR.Name, Text) then
        Continue;
      Text := LowerCase(Text);
      if DpkContains(Text, ALowFile)
         and PackageUsesInvariant(ADir, Text, ABudget) then
        Exit(True);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Enthaelt ein Paket im Fenster der Unit (Unterordner packages bzw.
// package und eine Ebene darin, im Verzeichnis der Unit und bis
// PROJECT_LEVELS darueber - wie PackagesReason, jede Version) die Unit UND
// eine Unit, die TFormatSettings.Invariant ohne Weiche nutzt? Dann kennt
// jeder Compiler, der das Paket baut, Invariant - das widerlegt fuer den
// Invariant-Weg auch die Spuren im Include (rwE30 Stufe 2: MVCFramework.
// HttpSys.Response.pas:335 - dmvcframework.inc fragt 'CompilerVersion <=
// 29', dmvcframeworkRT.dpk enthaelt MVCFramework.Serializer.Commons.pas mit
// Invariant). Mit Cache (GDiskCache, Art 'V').
function PackageInvariantProof(const AFileName: string): Boolean;
var
  Dir, Up, Pkg, LowFile, Key, Cached : string;
  Level, i                          : Integer;
  Old, Unknown, All                 : TArray<string>;
  OldVer                            : TArray<Integer>;
  Budget                            : TRdxWalkBudget;
  D                                 : string;
begin
  Key := DiskKey('V', lfFormatInvariant, AFileName, '');
  if (GDiskCache <> nil) and GDiskCache.FItems.TryGetValue(Key, Cached) then
    Exit(Cached <> '');
  Result := False;
  Budget := Default(TRdxWalkBudget);
  LowFile := LowerCase(ExtractFileName(AFileName));
  Dir := ExtractFileDir(AFileName);
  for Level := 0 to PROJECT_LEVELS do
  begin
    if (Dir = '') or Result then Break;
    for i := 0 to High(PACKAGE_DIRS) do
    begin
      Pkg := IncludeTrailingPathDelimiter(Dir) + PACKAGE_DIRS[i];
      if Result or not DirectoryExists(Pkg) then Continue;
      Old := nil;
      Unknown := nil;
      OldVer := nil;
      All := nil;
      CollectPackageDirs(Pkg, MaxInt, Old, Unknown, OldVer, All);
      for D in All do
        if not Result then
          Result := DirProvesInvariant(D, LowFile, Budget);
    end;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Break;
    Dir := Up;
  end;
  if GDiskCache <> nil then
  begin
    Cached := '';
    if Result then
      Cached := 'V';
    GDiskCache.FItems.AddOrSetValue(Key, Cached);
  end;
end;

// Nur die Programme im Fenster von ProjectWalkReason (Verzeichnis der Unit
// und bis PROJECT_LEVELS darueber, je dazu ihre Paketordner), die die Unit
// enthalten und die globale FormatSettings selbst einstellen
// (SettingsProgramReason) - '' oder der Grund. Fuer den Invariant-Weg auch
// dann, wenn die Datei einen neueren Compiler beweist (ProjectReason; Review
// e/HilfeFixG): der Gegenbeweis widerlegt Compiler, nicht die
// Einstellungen eines Programms. Netzpfad: R_NETWORK wie FileReason. Mit
// Cache (GDiskCache, Art 'P').
function SettingsWalkReason(const AFileName: string): string;
var
  Dir, Up, Pkg, Key : string;
  Level, i, k       : Integer;
  Old, Unknown, All : TArray<string>;
  OldVer            : TArray<Integer>;
  Budget            : TRdxWalkBudget;
begin
  Result := '';
  if IsNetworkPath(AFileName) then
    Exit(_(R_NETWORK, [ExtractFileDir(AFileName), MsgByHand]));
  Key := DiskKey('P', lfFormatInvariant, AFileName, '');
  if (GDiskCache <> nil) and GDiskCache.FItems.TryGetValue(Key, Result) then
    Exit;
  Budget := Default(TRdxWalkBudget);
  Dir := ExtractFileDir(AFileName);
  Level := 0;
  while (Result = '') and (Dir <> '') and (Level <= PROJECT_LEVELS) do
  begin
    Result := SettingsProgramReason(Dir, ProgramsIn(Dir), AFileName, Budget);
    for i := 0 to High(PACKAGE_DIRS) do
    begin
      Pkg := IncludeTrailingPathDelimiter(Dir) + PACKAGE_DIRS[i];
      if (Result <> '') or not DirectoryExists(Pkg) then Continue;
      Old := nil;
      Unknown := nil;
      OldVer := nil;
      All := nil;
      CollectPackageDirs(Pkg, MaxInt, Old, Unknown, OldVer, All);
      for k := 0 to High(All) do
        if Result = '' then
          Result := SettingsProgramReason(All[k], ProgramsIn(All[k]),
            AFileName, Budget);
    end;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Break;
    Dir := Up;
    Inc(Level);
  end;
  if GDiskCache <> nil then
    GDiskCache.FItems.AddOrSetValue(Key, Result);
end;


// Hauptweg SCA128/SCA059 (lfFormatSettingsVar, rwE31 Stufe 3): ist die
// Unit Teil eines Delphi-Projekts ab der Schwelle? Das NAECHSTE Verzeichnis
// im Fenster mit Delphi-Projektdateien (wie ProjectWalkReason) traegt keine
// alte (DelphiProjectReason leer: jede .dproj ab der Schwelle, kein .dof-
// Paar, kein Doppel-Compiler-Projekt), und ein Programm dort mit .dproj
// gleichen Namens enthaelt die Unit (in-Klausel, DpkContains). Das
// widerlegt ein Kit-Include der Unit: mORMot2 ex\ThirdPartyDemos\dmvc-ai\
// 01-basicdemo_server\src\api.impl.pas:50 bindet mormot.defines.inc ein
// (mORMot baut ab Delphi 7), gebaut wird sie aber nur von
// 01-basicdemo_server.dpr mit .dproj (ProjectVersion 20.3, Delphi 12) -
// der mORMot-Kern unter src\ hat kein solches Projekt und bleibt gesperrt.
// Netzpfad: nein (die Hilfe liest dort nichts). Mit Cache (GDiskCache, Art
// 'K').
function ModernProjectProof(const AFileName: string;
  AFeature: TRdxLateFeature): Boolean;
var
  Dir, Up, LowFile, Prg, Text, Key, Cached : string;
  Level                                     : Integer;
  Files                                     : TRdxProjectFiles;
begin
  Result := False;
  if (AFileName = '') or IsNetworkPath(AFileName) then Exit;
  Key := DiskKey('K', AFeature, AFileName, '');
  if (GDiskCache <> nil) and GDiskCache.FItems.TryGetValue(Key, Cached) then
    Exit(Cached <> '');
  LowFile := LowerCase(ExtractFileName(AFileName));
  Dir := ExtractFileDir(AFileName);
  for Level := 0 to PROJECT_LEVELS do
  begin
    if Dir = '' then Break;
    Files := ProjectFilesIn(Dir, FloorOf(AFeature).ProjectVersion);
    if HasDelphiProject(Files) then
    begin
      if DelphiProjectReason(Files, Dir, AFeature) = '' then
        for Prg in Files.Programs do
          if not Result
             and InList(LowerCase(ChangeFileExt(Prg, '')), Files.DprojBases)
             and HeadText(IncludeTrailingPathDelimiter(Dir) + Prg, Text) then
            Result := DpkContains(LowerCase(Text), LowFile);
      Break;
    end;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Break;
    Dir := Up;
  end;
  if GDiskCache <> nil then
  begin
    Cached := '';
    if Result then
      Cached := 'K';
    GDiskCache.FItems.AddOrSetValue(Key, Cached);
  end;
end;

// Hauptweg SCA128/SCA059: ein Kit-Include der Unit (mormot.defines.inc,
// jvcl.inc .. - uRdxCompilerTraces.OldCompilerTraceOf; der Planer prueft
// seit rwE31 Stufe 3 nur die Bedingungen der Datei) sperrt, ausser ein
// Projekt der Unit ab Delphi XE widerlegt es (AModern: ModernProjectProof).
// '' oder der Grund.
function KitIncludeReason(AMap: TRdxCodeMap; AModern: Boolean): string;
var
  Kit : string;
  Li  : Integer;
begin
  Result := '';
  Kit := OldCompilerTraceOf(AMap, FLOOR_SETTINGS_VAR, False, True, Li);
  if (Kit = '') or AModern then
    Exit;
  Result := _(R_KIT_OLD_VAR, [Kit, Li]);
end;


// Der Ausgang von DirFloorVerdict: keine .dpk mit der Unit, nur solche ab
// der Schwelle, mindestens eine alte bzw. unbekannte (oder der Deckel ist
// erschoepft - keine Aussage).
type
  TRdxFloorVerdict = (fvNone, fvNew, fvOld);

// Nennt der Ordnername eine Obergrenze ('Delphi 10.3-': 10.3 und davor)?
// Dann belegt seine Zahl keine Mindestversion.
function NamesUpperBound(const AName: string): Boolean;
var
  S : string;
begin
  S := Trim(AName);
  Result := (S <> '') and (S[Length(S)] = '-');
end;

// Die .dpk in ADir, die die Unit ALowFile enthalten, gegen die Version
// AFloor: ihre Version aus dem Ordnernamen bzw. {$LIBSUFFIX} (wie
// DpkDirReason; ohne Beleg oder mit Obergrenze unbekannt).
function DirFloorVerdict(const ADir, ALowFile: string; AFloor: Integer;
  var ABudget: TRdxWalkBudget): TRdxFloorVerdict;
var
  SR        : TSearchRec;
  Text, Lib : string;
  V, LibV   : Integer;
begin
  Result := fvNone;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*' + DPK_EXTENSION,
       faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0)
         or (LowerCase(ExtractFileExt(SR.Name)) <> DPK_EXTENSION) then
        Continue;
      if ABudget.Packages >= MAX_PACKAGE_READS then
        Exit(fvOld);
      Inc(ABudget.Packages);
      if not HeadText(IncludeTrailingPathDelimiter(ADir) + SR.Name, Text) then
        Exit(fvOld);
      Text := LowerCase(Text);
      if not DpkContains(Text, ALowFile) then Continue;
      V := -1;
      if not NamesUpperBound(ExtractFileName(
           ExcludeTrailingPathDelimiter(ADir))) then
        V := TRdxPackageVersion.Folder(ExtractFileName(
          ExcludeTrailingPathDelimiter(ADir)));
      LibV := TRdxPackageVersion.LibSuffix(Text, Lib);
      if LibV > V then
        V := LibV;
      if V < AFloor then
        Exit(fvOld);
      Result := fvNew;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Die Unterordner von ADir (eine Ebene).
function SubDirsOf(const ADir: string): TArray<string>;
var
  SR : TSearchRec;
begin
  Result := nil;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faDirectory,
       SR) <> 0 then
    Exit;
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.')
         and (SR.Name <> '..') then
        AddText(Result, IncludeTrailingPathDelimiter(ADir) + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Invariant-Weg (rwE31 Stufe 3): bauen NUR Pakete ab der Schwelle von
// AFeature die Unit? Gesucht wird wie PackagesReason im Fenster (Verzeichnis
// der Unit und bis PROJECT_LEVELS darueber, je Unterordner packages bzw.
// package), aber zwei Ebenen tief (python4delphi Packages\Delphi\Delphi
// 10.4+\PythonFmx.dpk - PackagesReason sieht nur eine). Ja, wenn
// mindestens eine .dpk die Unit enthaelt und jede davon ab der Schwelle ist
// (Ordnername, LIBSUFFIX; ohne Beleg, mit Obergrenze 'Delphi 10.3-' oder
// mit erschoepftem Deckel: nein). Mit Cache (GDiskCache, Art 'L').
function PackageFloorProof(const AFileName: string;
  AFeature: TRdxLateFeature): Boolean;
var
  Dir, Up, Pkg, LowFile, Key, Cached, D1, D2 : string;
  Level, i                                   : Integer;
  Budget                                     : TRdxWalkBudget;
  Floor                                      : Integer;
  Found, Old                                 : Boolean;

  procedure Judge(const ADir: string);
  begin
    if Old then Exit;
    case DirFloorVerdict(ADir, LowFile, Floor, Budget) of
      fvNew: Found := True;
      fvOld: Old := True;
    end;
  end;

begin
  Result := False;
  if (AFileName = '') or IsNetworkPath(AFileName) then Exit;
  Key := DiskKey('L', AFeature, AFileName, '');
  if (GDiskCache <> nil) and GDiskCache.FItems.TryGetValue(Key, Cached) then
    Exit(Cached <> '');
  Budget := Default(TRdxWalkBudget);
  Floor := FloorOf(AFeature).Version;
  LowFile := LowerCase(ExtractFileName(AFileName));
  Found := False;
  Old := False;
  Dir := ExtractFileDir(AFileName);
  for Level := 0 to PROJECT_LEVELS do
  begin
    if (Dir = '') or Old then Break;
    for i := 0 to High(PACKAGE_DIRS) do
    begin
      Pkg := IncludeTrailingPathDelimiter(Dir) + PACKAGE_DIRS[i];
      if Old or not DirectoryExists(Pkg) then Continue;
      Judge(Pkg);
      for D1 in SubDirsOf(Pkg) do
      begin
        Judge(D1);
        for D2 in SubDirsOf(D1) do
          Judge(D2);
      end;
    end;
    Up := ExtractFileDir(Dir);
    if Up = Dir then Break;
    Dir := Up;
  end;
  Result := Found and not Old;
  if GDiskCache <> nil then
  begin
    Cached := '';
    if Result then
      Cached := 'L';
    GDiskCache.FItems.AddOrSetValue(Key, Cached);
  end;
end;

class function TRdxMagicFixes.ProjectReason(const AFileName: string;
  AMap: TRdxCodeMap; AFeature: TRdxLateFeature; AIncludes: Boolean): string;
var
  Proof  : TRdxModernProof;
  Modern : Boolean;
begin
  Result := '';
  Modern := False;
  // Kein Beleg auf einem Netzpfad: SCA127 liest dort nichts und sperrt
  // nicht (die anderen Sprachmittel sperren dort, FileReason).
  if not MissingBlocks(AFeature) and IsNetworkPath(AFileName) then Exit;
  Proof := ModernProof(AMap);
  // Der Gegenbeweis (bzw. Invariant ohne Weiche) widerlegt nur die
  // Compiler-Spuren; ein Programm, das die globale FormatSettings selbst
  // einstellt, sperrt den Invariant-Weg weiter (Review e/HilfeFixG).
  if (ProofCovers(Proof, FloorOf(AFeature))
      and (FpcKnows(AFeature) or Proof.NoFpc))
     or ((AFeature = lfFormatInvariant)
         and (UnconditionalInvariantLine(AMap) > 0)) then
  begin
    if (AFeature = lfFormatInvariant) and (AFileName <> '') then
      Result := SettingsWalkReason(AFileName);
    Exit;
  end;
  // Hauptweg: ein Kit-Include der Unit (seit rwE31 Stufe 3 hier statt im
  // Planer) - auch ohne Dateinamen (dann ohne Widerlegung).
  if AFeature = lfFormatSettingsVar then
  begin
    Modern := ModernProjectProof(AFileName, AFeature);
    Result := KitIncludeReason(AMap, Modern);
    if Result <> '' then Exit;
  end;
  if AFileName = '' then Exit;
  Result := FileReason(AFileName, AFeature);
  // Nico-Entscheid M1b (2026-10-30, ersetzt M1 fuer diesen Fall): auch der
  // Hauptweg liest die Includes - aber nur ohne Projekt der Unit ab XE
  // (Modern). Es sperrt nur eine Delphi-Weiche bis XE (OldCompilerTrace mit
  // FLOOR_SETTINGS_VAR); FPC-Weichen nicht (FpcKnows), ein nicht gefundenes
  // oder nicht lesbares Include auch nicht (IncludeReason: kein Beleg).
  // doublecmd Image32\source\Clipper2\Clipper.pas:657 - Clipper.inc fragt
  // 'COMPILERVERSION < 14' (Delphi 6+), die globale FormatSettings gibt es
  // erst ab XE.
  if (Result = '') and (AIncludes
     or ((AFeature = lfFormatSettingsVar) and not Modern)) then
  begin
    Result := IncludeReason(AFileName, AMap, AFeature);
    // Die Spuren im Include widerlegt ein Paket der Unit, das Invariant
    // nutzt (die Projekt-Nachbarschaft nicht: ein Lazarus-Projekt oder
    // eine .dof baut die Unit ohne das Paket).
    if (Result <> '') and (AFeature = lfFormatInvariant)
       and PackageInvariantProof(AFileName) then
      Result := '';
    // Eine FMX-Unit (kein FPC, ModernProof.NoFpc), die nur Pakete ab der
    // Schwelle bauen: weder die FPC-Weiche noch die alten Versionen des
    // Includes treffen sie (rwE31 Stufe 3, python4delphi WrapFmxTypes.pas -
    // Definition.Inc, nur in Packages\Delphi\Delphi 10.4+\PythonFmx.dpk).
    if (Result <> '') and (AFeature = lfFormatInvariant) and Proof.NoFpc
       and PackageFloorProof(AFileName, AFeature) then
      Result := '';
  end;
end;

class function TRdxMagicFixes.UseDiskCache(
  ACache: TRdxDiskReasonCache): TRdxDiskReasonCache;
begin
  Result := GDiskCache;
  GDiskCache := ACache;
end;

{ TRdxDiskReasonCache }

constructor TRdxDiskReasonCache.Create;
begin
  inherited Create;
  FItems := TDictionary<string, string>.Create;
end;

destructor TRdxDiskReasonCache.Destroy;
begin
  // Noch aktiv (ein vergessenes Wiederherstellen): abmelden, sonst laese
  // der naechste FileReason freigegebenen Speicher.
  if GDiskCache = Self then
    GDiskCache := nil;
  FItems.Free;
  inherited;
end;

procedure TRdxDiskReasonCache.Clear;
begin
  FItems.Clear;
end;

function TRdxDiskReasonCache.Count: Integer;
begin
  Result := FItems.Count;
end;

// Die Pruefung eines Includes (TRdxIncludeTest): eine FPC-Weiche oder eine
// Spur aelterer Compiler darin - '' oder der Grund. AArg ist das
// Sprachmittel als Zahl (Ord(TRdxLateFeature), IncludeReason) - der Test
// ist ein schlichter Funktionszeiger mit Text-Argument.
function CompilerInInclude(const AFile: string; ALines: TStrings;
  AMap: TRdxCodeMap; const AArg: string): string;
var
  Li      : Integer;
  S       : string;
  Feature : TRdxLateFeature;
begin
  Result := '';
  Feature := TRdxLateFeature(StrToIntDef(AArg, Ord(lfInlineConst)));
  if not TRdxMagicFixes.FpcKnows(Feature) then
    for Li := 0 to ALines.Count - 1 do
      if LineLooksFpcAware(ALines[Li]) then
        Exit(_(R_INC_FPC[Feature], [AFile, Li + 1]));
  S := OldCompilerTrace(AMap, FloorOf(Feature), Li);
  if S <> '' then
    Result := _(R_INC_OLD[Feature], [AFile, S, Li, MsgByHand]);
end;

class function TRdxMagicFixes.IncludeReason(const AFileName: string;
  AMap: TRdxCodeMap; AFeature: TRdxLateFeature): string;
var
  Check : TRdxIncludeCheck;
  Incs  : TArray<string>;
  Key   : string;
begin
  // Die Map bestimmt die Includes (AllIncludes liest jedes Zeichen der
  // Datei - im Messgeruest teurer als der Blick auf die Platte); dieselbe
  // Map heisst dieselbe Serial.
  if GDiskCache <> nil then
  begin
    Key := DiskKey('I', AFeature, AFileName, IntToStr(AMap.Serial));
    if GDiskCache.FItems.TryGetValue(Key, Result) then Exit;
  end;
  Incs := AllIncludes(AMap);
  Check.Test := CompilerInInclude;
  Check.Arg := IntToStr(Ord(AFeature));
  // Ein Include, das nicht zu lesen ist, ist fuer lfExceptionClasses kein
  // Beleg (MissingBlocks): das leere Muster gibt keinen Grund. Ebenso fuer
  // lfFormatSettingsVar (Nico-Entscheid M1b: nur eine gelesene Weiche
  // sperrt den Hauptweg).
  if MissingBlocks(AFeature) and (AFeature <> lfFormatSettingsVar) then
    Check.MissingFmt := _(R_INC_UNSEEN)
  else
    Check.MissingFmt := '';
  Result := IncludeChainReason(AFileName, Incs, Check);
  if GDiskCache <> nil then
    GDiskCache.FItems.AddOrSetValue(Key, Result);
end;

end.
