unit uRdxText;

// reDelphix - die Sprache seiner Texte (Entscheid E29, Nico 2026-10-15):
// Menuetexte, Hinweise, Ablehnungsgruende und Statuszeile der Quick-Fixes
// erscheinen in der Sprache der SCA-Oberflaeche (en/de/fr), solange
// redelphix.ini nichts anderes sagt. Englische msgids, Uebersetzungen in
// i18n/de.po und i18n/fr.po - derselbe Weg wie in der SCA (uLocalization).
//
// WARUM EIN EIGENES _()
//
// uLocalization._() uebersetzt in die AKTIVE Sprache der SCA. reDelphix
// haengt in derselben BPL (requires SCA.Engine) und teilt diesen Zustand -
// die SCA setzt ihn aber erst mit dem Analyser-Fenster (uIDEAnalyserForm:
// SetLanguage(FRepoSettings.Language)) bzw. beim Speichern der Optionen
// (uIDESCAOptions). Die Gluehbirne kann vorher kommen, dann waeren die
// Menuetexte englisch. Umstellen darf reDelphix die globale Sprache auch
// nicht: das stellte die ganze SCA-Oberflaeche um. Deshalb uebersetzt
// dieses _() ueber uLocalization.TranslateTo in die reDelphix-Sprache
// (RdxLanguage) - ohne den globalen Zustand anzufassen, ueber denselben
// .po-Cache.
//
// DER NAME _ IST ABSICHT: tools/i18n_extract.py findet die msgids an
// _('..'), an _(KONSTANTE) einer Konstante DERSELBEN Unit und an
// _(ARRAY[i]) eines String-Arrays derselben Unit - gleich, welche Unit das
// _ liefert. Eine reDelphix-Unit bindet uRdxText STATT uLocalization:
// stuenden beide im uses, hinge _ an der Reihenfolge der Eintraege (oder
// waere mehrdeutig) - und eine falsche Reihenfolge zeigte still die
// SCA-Sprache statt der aus redelphix.ini. Wer beide braucht (Tests),
// schreibt uRdxText._ aus.
//
// WIE DIE SPRACHE ERMITTELT WIRD (RdxLanguage, bei jedem Aufruf)
//
//   1. SetRdxLanguageOverride (Tests) ersetzt den Wert aus redelphix.ini;
//      die Datei wird dann weder gelesen noch angelegt.
//   2. redelphix.ini [UI] Language (RdxIniPath, neben analyser.ini):
//        auto (Vorgabe; auch leer, Schluessel oder Datei fehlt)
//          a) uLocalization.CurrentLanguage, wenn die SCA ihre Sprache
//             gesetzt hat - stellt der Nutzer sie in den Optionen um, gilt
//             das beim naechsten Menue;
//          b) sonst analyser.ini [UI] Language, direkt gelesen (vor dem
//             Analyser-Fenster ist (a) leer);
//          c) sonst 'en'.
//        jedes andere Kuerzel fest (NormalizeLangCode: 'de-DE' -> 'de');
//        kein Kuerzel (Muell) -> 'en'. Ein Kuerzel ohne Uebersetzung ('xx')
//        zeigt Englisch - wie SetLanguage in der SCA.
//   Eine ini wird nur neu gelesen, wenn sich ihre Dateizeit geaendert hat
//   (je Aufruf EIN FileAge; die Gluehbirne fragt bei jeder Caret-Zeile),
//   analyser.ini nur im Fall (b). Kommentarzeilen (';', '#') zaehlen nie:
//   ';Language=de' ist in beiden Vorlagen ein Beispiel, kein Wert.
//
// redelphix.ini legt der erste Zugriff mit RDX_INI_TEMPLATE an, wenn sie
// fehlt - wie analyser.ini (TRepoSettings.EnsureConfigExists): UTF-8 mit
// BOM, englische Kommentare, die Vorgabe aktiv, Beispiele auskommentiert.
// Ein Schreibfehler (Schreibschutz, Ordner nicht anlegbar) wirft NIE ins
// Menue; dann gilt die Vorgabe auto. Versucht wird es je Verzeichnis
// einmal.
//
// OHNE ToolsAPI, laeuft im FPC-Pruefstand: dort steht ein Stub
// uLocalization (die echte Unit uebersetzt unter FPC 3.2.2 nicht), der die
// echten i18n/*.po liest, und der Runner setzt wie reDelphix.Test die
// Sprache 'de' (SetRdxLanguageOverride).
//
// Threadsicher: Override, Verzeichnis und ini-Cache liegen hinter GLock;
// TranslateTo laeuft ausserhalb (eigene Sperre in uLocalization). NICHT
// gedeckt ist uLocalization.CurrentLanguage: GCurrentLang liest und
// schreibt die SCA ohne Sperre (ein String, nicht atomar), GLock bindet
// SetLanguage nicht. Das traegt, weil beide Seiten im IDE-Hauptthread
// laufen - SetLanguage (uIDESCAOptions, uIDEAnalyserForm) wie die Texte
// von reDelphix (Gluehbirne, Kontextmenue, Raster); reDelphix startet
// keinen Thread (Review Woche G05-02). Wer _() aus einem Hintergrund-Thread
// ruft, braucht vorher eine Sperre um GCurrentLang in uLocalization.
//
// GEMEINSAME TEXTE (Charge C1, Msg...)
//
// Gruende und Hinweise, die mehr als eine Unit braucht, haben hier EINE
// msgid und eine Funktion - dazu ein Satz, den EINE Unit mit wechselndem
// Code-Stueck fuenfmal schrieb (MsgNoLongerAtReportedPlace, nur
// uRdxSimpleFixes: ein Satz mit dem Code als %s statt fuenf msgids, die
// Ausnahme laut Auftrag C1). Legten zwei Units dieselbe msgid selbst an,
// stuende sie in de.po/fr.po doppelt (die erste gewinnt, msgfmt meldet
// einen Fehler); schrieben sie zwei englische Saetze fuer denselben
// deutschen, liefen die Uebersetzungen auseinander. Jede msgid ist ein
// GANZER englischer Satz, variable Teile sind Format-Platzhalter - so
// stellt de/fr die Wortstellung selbst. Ein Argument AReason ist ein schon
// uebersetzter ganzer Satz, AWhose eine schon uebersetzte Ergaenzung des
// Aufrufers ('of a destructor'); ACode, AKeyword, APrevToken und AName
// sind Quelltext und bleiben, wie sie sind. Ausnahmen vom ganzen Satz
// (Nachpruefung C1, V-C1-12 und Runde 3): die Satzenden MsgByHand,
// MsgCheckByHand, MsgDeleteByHand und MsgDecideByHand stehen als %s im
// Satz der Unit, nie allein als Grund; MsgNoHeader ist eine Nominalphrase
// fuer TRdxLineSearch.What, die uRdxCodeMap.OneTokenReason zum Satz
// ergaenzt; MsgHeadersFmt ist ein MUSTER fuer TRdxLineSearch.ManyFmt, das
// OneTokenReason mit Zahl und Ergaenzung fuellt (die Kopf-Suche steht in
// uRdxResultFixes UND uRdxRoutineFixes - dieselbe msgid aus zwei Gruppen
// stuende sonst doppelt in de.po/fr.po). Die deutsche Fassung ist der bisherige Wortlaut der
// Planer, mit echten Umlauten (uTestRdxTextMsgs pinnt ihn in de, en und
// fr). Wann welche Funktion gilt und wie ein zusammengesetzter Grund
// entsteht: reDelphix/README.md, Abschnitt "Texte umstellen".

interface

// Uebersetzt S in die reDelphix-Sprache (RdxLanguage); ohne Eintrag in der
// .po bleibt S (Englisch).
function _(const S: string): string; overload;

// Format-Variante: erst uebersetzen, dann formatieren (wie uLocalization._).
function _(const Fmt: string; const Args: array of const): string; overload;

// Die Sprache der reDelphix-Texte als Kuerzel ('en', 'de', 'fr', ...) nach
// den Regeln im Kopf. Nie ''.
function RdxLanguage: string;

// Fuer Tests: ein fester Wert anstelle von redelphix.ini [UI] Language
// ('de', 'en', 'auto' ...); '' hebt ihn auf. Mit Override wird
// redelphix.ini weder gelesen noch angelegt - ein Testlauf beschreibt nie
// %APPDATA%.
procedure SetRdxLanguageOverride(const ALang: string);
function RdxLanguageOverride: string;

// Das Verzeichnis von redelphix.ini UND analyser.ini, mit Trenner. '' =
// Vorgabe %APPDATA%\StaticCodeAnalyser\ (ohne APPDATA das Temp-
// Verzeichnis; uScaConfigDir, wie TIgnoreList.ConfigDir). Tests lenken es
// in ein eigenes Temp-Verzeichnis um; jeder Aufruf verwirft den ini-Cache
// und erlaubt einen neuen Versuch, die Vorlage anzulegen.
procedure SetRdxConfigDir(const ADir: string);
function RdxConfigDir: string;

// <RdxConfigDir>redelphix.ini
function RdxIniPath: string;

// Ein Wert aus redelphix.ini, [ASection] AKey ('' ohne Treffer) - ueber
// denselben Cache wie RdxLanguage; fehlt die Datei, wird die Vorlage
// angelegt. Der Leser fuer kuenftige reDelphix-Einstellungen;
// tools/config_doc_gate.py nimmt seine Aufrufe als die Schluessel, die der
// Code liest (Vorlage und reDelphix/README.md muessen sie nennen).
function RdxIniValue(const ASection, AKey: string): string;

// Die Vorlage von redelphix.ini (ohne BOM, Zeilen mit CRLF).
function RdxIniTemplate: string;

// Der Wert von [ASection] AKey im Text einer ini - wie TMemIniFile: Namen
// ohne Gross-/Kleinschreibung, Leerraum um '=' entfernt, der erste Treffer
// gilt, kein Inline-Kommentar. Eine Zeile mit ';' oder '#' am Anfang ist
// Kommentar (wie TCommentPreservingIni.KeyOf). '' ohne Treffer.
function IniTextValue(const AText, ASection, AKey: string): string;

// Die Sprache aus den drei Quellen (Regeln im Kopf, Schritt 2): ARdxValue
// der Wert aus redelphix.ini bzw. der Override, AScaLanguage
// uLocalization.CurrentLanguage, AAnalyserValue analyser.ini [UI]
// Language. Rein - liest nichts.
function ResolveRdxLanguage(const ARdxValue, AScaLanguage,
  AAnalyserValue: string): string;

{ ---- Gemeinsame Texte (Charge C1, siehe Kopf) ---- }

// 'line moved? Analyse the file again' - die gemeldete Zeile traegt nicht
// mehr, was der Fund nennt. Allein als Grund oder als %s im eigenen Satz,
// wenn ein anderer Trenner als ' - ' davor steht; sonst MsgMovedSuffix.
function MsgLineMoved: string;

// '<AReason> - line moved? Analyse the file again' - der haeufigste
// zusammengesetzte Grund ('... - Zeile verschoben? Datei neu pruefen').
function MsgMovedSuffix(const AReason: string): string;

// '<AReason> - finding outdated? Analyse the file again' (deutsch '... -
// Fund veraltet? Datei neu pruefen'): der Code widerspricht dem Fund - er
// traegt schon, was die Hilfe einsetzen wuerde, oder benutzt, was der Fund
// ungenutzt nennt.
function MsgStaleSuffix(const AReason: string): string;

// 'the message has no column' - die Meldung nennt keine Spalte, die
// Hilfe braucht eine.
function MsgNoColumn: string;

// 'end of the statement not found'.
function MsgStatementEndNotFound: string;

// 'no valid range' - ein Bereich ohne gueltige Grenzen bzw. ohne
// erwarteten Text (Editor und Byte-Rechnung).
function MsgNoValidRange: string;

// 'end of the header not found' - das ';' hinter einem Routinenkopf fehlt.
function MsgHeaderEndNotFound: string;

// 'the line starts inside a comment or string' - der Zeilenanfang liegt in
// einem mehrzeiligen Kommentar bzw. String.
function MsgLineStartsInCommentOrString: string;

// 'no file open' - keine Quelle zum Fund (Laeufer, Tabelle).
function MsgNoFileOpen: string;

// 'by hand' - Schluss eines Grundes: das bleibt Handarbeit. Kein eigener
// Satz: steht als %s im Satz der Unit, die den Trenner davor ('; ',
// ' - ', ', ') selbst traegt.
function MsgByHand: string;

// 'check by hand' - wie MsgByHand ('von Hand pruefen').
function MsgCheckByHand: string;

// 'delete by hand' - wie MsgByHand ('von Hand loeschen').
function MsgDeleteByHand: string;

// 'decide by hand' - wie MsgByHand ('von Hand entscheiden').
function MsgDecideByHand: string;

// 'only statement after <AKeyword> - an empty block would remain (SCA077)';
// AKeyword ist das Wort davor (begin, try, repeat ...).
function MsgOnlyStatementEmptyBlock(const AKeyword: string): string;

// 'unclear what the statement belongs to ("<APrevToken>" before it)' -
// das Token vor der Anweisung passt zu keiner Anweisungsliste.
function MsgUnclearStatementOwner(const APrevToken: string): string;

// 'literal not readable: <ACode>' - ACode ist der Quelltext des Literals
// (vom Aufrufer gekuerzt bzw. zusammengezogen).
function MsgLiteralUnreadable(const ACode: string): string;

// 'no operand in the chain' - eine Verkettung ohne Operanden (nur
// Literale). Wer auf diesen Grund verzweigt, prueft vor der Uebersetzung
// (eine Kennung), nie auf den Text.
function MsgNoOperandInChain: string;

// '<ACount> declarations of <AName> in classes of this name - overload?' -
// welche Deklaration zur Implementierung gehoert, bleibt offen.
function MsgDeclsInClassesOfName(ACount: Integer; const AName: string): string;

// '<ACode> is no longer at the reported place' - ACode ist das Code-Stueck
// des Funds ('Assert(', 'class(TObject)', 'X.Free;'), kein Satzteil.
// Einziger Nutzer ist uRdxSimpleFixes (fuenf Code-Stuecke) - die Ausnahme
// vom Kopfvertrag "mehr als eine Unit" (Auftrag C1).
function MsgNoLongerAtReportedPlace(const ACode: string): string;

// 'no header <AWhose>' - die Kopf-Suche fand auf der gemeldeten Zeile
// keinen Routinenkopf (TRdxLineSearch.What in uRdxResultFixes.RoutineOnLine
// und uRdxRoutineFixes.HeadOn; deutsch bisher 'kein Kopf ' + Ergaenzung).
// AWhose ist die schon uebersetzte Ergaenzung des Aufrufers ('of a
// destructor', 'of the routine Foo' - de 'eines Destruktors', 'der Routine
// Foo'), kein Quelltext; OneTokenReason haengt 'auf der gemeldeten Zeile'
// an.
function MsgNoHeader(const AWhose: string): string;

// '%d headers %s' - das MUSTER fuer TRdxLineSearch.ManyFmt derselben Suche
// (deutsch bisher '%d Koepfe ' + Ergaenzung): %d die Zahl der Koepfe, %s
// das Feld ManyArg mit derselben Ergaenzung wie bei MsgNoHeader. Es geht
// unformatiert an OneTokenReason - die Ergaenzung nie ins Muster haengen
// (ein '%' darin warf EConvertError).
function MsgHeadersFmt: string;

implementation

uses
  System.SysUtils,
  System.Classes,       // TFileStream
  System.SyncObjs,      // TCriticalSection
  uScaConfigDir,        // ScaConfigDir - dieselbe Ablage wie
                        // TIgnoreList.ConfigDir (Review Woche G05-21)
  uLocalization;        // TranslateTo, CurrentLanguage, NormalizeLangCode

const
  RDX_INI_NAME      = 'redelphix.ini';
  ANALYSER_INI_NAME = 'analyser.ini';
  SECTION_UI        = 'UI';
  KEY_LANGUAGE      = 'Language';
  LANG_AUTO         = 'auto';
  LANG_FALLBACK     = 'en';
  // Schutz gegen eine versehentlich riesige Datei: analyser.ini hat rund
  // 30 KB, redelphix.ini zwei.
  MAX_INI_BYTES     = 1024 * 1024;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);

  // Die msgids der gemeinsamen Texte (Charge C1). Uebersetzt wird mit
  // _(KONSTANTE) HIER: tools/i18n_extract.py loest nur Konstanten derselben
  // Unit auf - ein _(MSG_X) in einer anderen Unit fehlte in template.pot.
  MSG_LINE_MOVED     = 'line moved? Analyse the file again';
  MSG_MOVED_SUFFIX   = '%s - line moved? Analyse the file again';
  MSG_STALE_SUFFIX   = '%s - finding outdated? Analyse the file again';
  MSG_NO_COLUMN      = 'the message has no column';
  MSG_STMT_END       = 'end of the statement not found';
  MSG_NO_RANGE       = 'no valid range';
  MSG_HEADER_END     = 'end of the header not found';
  MSG_STARTS_INSIDE  = 'the line starts inside a comment or string';
  MSG_NO_FILE        = 'no file open';
  MSG_BY_HAND        = 'by hand';
  MSG_CHECK_BY_HAND  = 'check by hand';
  MSG_DELETE_BY_HAND = 'delete by hand';
  MSG_DECIDE_BY_HAND = 'decide by hand';
  MSG_EMPTY_BLOCK    = 'only statement after %s - an empty block would '
    + 'remain (SCA077)';
  MSG_UNCLEAR_OWNER  = 'unclear what the statement belongs to ("%s" before '
    + 'it)';
  MSG_LITERAL        = 'literal not readable: %s';
  MSG_NO_OPERAND     = 'no operand in the chain';
  MSG_DECLS_IN_CLASS = '%d declarations of %s in classes of this name - '
    + 'overload?';
  MSG_NOT_AT_PLACE   = '%s is no longer at the reported place';
  MSG_NO_HEADER      = 'no header %s';
  MSG_HEADERS_FMT    = '%d headers %s';

  // Die Vorlage - Aufbau und Ton wie DEFAULT_INI_CONTENT in uRepoSettings
  // (englisch, je Option ein Erklaerblock, die Vorgabe aktiv, Beispiele
  // auskommentiert). Jede Zeile ein Literal mit #13#10: so liest
  // tools/config_doc_gate.py die Schluessel der Vorlage.
  RDX_INI_TEMPLATE =
    '; ============================================================'#13#10 +
    ';  reDelphix (Static Code Analysis Tool for Delphi) - redelphix.ini'#13#10 +
    '; ============================================================'#13#10 +
    ';'#13#10 +
    '; Settings of reDelphix, the code actions of the IDE plugin'#13#10 +
    '; (quick fixes in the light bulb, the editor context menu and the'#13#10 +
    '; findings grid). The file lives next to analyser.ini:'#13#10 +
    ';   %APPDATA%\StaticCodeAnalyser\redelphix.ini'#13#10 +
    '; reDelphix creates it with these defaults when it is missing -'#13#10 +
    '; delete it to get the template back with the next IDE start.'#13#10 +
    ';'#13#10 +
    '; This file lists ALL available options with their default values.'#13#10 +
    '; Layout per option:'#13#10 +
    ';   A comment explains what the option does.'#13#10 +
    ';   OPTION=<default>           <- active, set to its default'#13#10 +
    ';   ;OPTION=<example>          <- commented-out example variant'#13#10 +
    ';'#13#10 +
    '; Changes take effect the next time a menu or the light bulb opens.'#13#10 +
    '; No IDE restart needed.'#13#10 +
    ';'#13#10 +
    ';'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ';  [UI] - user-interface settings'#13#10 +
    '; ------------------------------------------------------------'#13#10 +
    ''#13#10 +
    '[UI]'#13#10 +
    ''#13#10 +
    '; Language (string, default: auto)'#13#10 +
    '; Language of the reDelphix texts: menu entries, hints, the reasons'#13#10 +
    '; of greyed-out entries and status messages.'#13#10 +
    ';   auto = like the SCA user interface (analyser.ini [UI] Language,'#13#10 +
    ';          also Tools > Options > Third Party > Static Code'#13#10 +
    ';          Analyser); a change there takes effect at once (default)'#13#10 +
    ';   en   = English'#13#10 +
    ';   de   = German'#13#10 +
    ';   fr   = French'#13#10 +
    '; An empty value counts as auto; a code without a translation'#13#10 +
    '; shows English.'#13#10 +
    'Language=auto'#13#10 +
    ';Language=de'#13#10 +
    ';Language=en'#13#10;

type
  // Eine ini-Datei mit dem Text des letzten Lesens (Refresh) und dem
  // zuletzt gefragten Wert: RdxLanguage fragt bei jedem _() denselben
  // Schluessel, der Text wird dann nicht jedes Mal zerlegt.
  TRdxIniFile = record
    Path      : string;     // '' = noch nie (erfolgreich) gelesen
    Exists    : Boolean;
    Stamp     : TDateTime;  // Dateizeit beim Lesen
    Text      : string;     // '' wenn die Datei fehlt
    MemoValid : Boolean;
    MemoSect  : string;
    MemoKey   : string;
    MemoValue : string;
  end;

var
  GLock          : TCriticalSection = nil;
  GOverride      : string = '';
  GConfigDir     : string = '';      // '' = ScaConfigDir
  GRdxIni        : TRdxIniFile;
  GAnalyserIni   : TRdxIniFile;
  GTemplateTried : Boolean = False;

{ ---- Pfade ---- }

// Nur unter GLock. Die Vorgabe %APPDATA%\StaticCodeAnalyser\ kommt aus
// uScaConfigDir - bis zur Folgewelle des Wochen-Reviews (G05-21) stand
// hier die dritte Kopie der Formel neben TIgnoreList.ConfigDir und
// TRuleCatalog.UserProfilesFilePath. uScaConfigDir bindet nur SysUtils
// und uebersetzt im FPC-Pruefstand.
function ConfigDirLocked: string;
begin
  if GConfigDir <> '' then
    Result := IncludeTrailingPathDelimiter(GConfigDir)
  else
    Result := ScaConfigDir;
end;

{ ---- ini lesen ---- }

// UTF-8 (ein BOM wird uebersprungen), bei ungueltigem UTF-8 ANSI - die
// Stufen von TMemIniFile ueber LoadFromFile.
function DecodeIniBytes(const ABytes: TBytes): string;
var
  Start : Integer;
begin
  Start := 0;
  if (Length(ABytes) >= Length(UTF8_BOM)) and (ABytes[0] = UTF8_BOM[0])
     and (ABytes[1] = UTF8_BOM[1]) and (ABytes[2] = UTF8_BOM[2]) then
    Start := Length(UTF8_BOM);
  if Length(ABytes) <= Start then
    Exit('');
  try
    Result := TEncoding.UTF8.GetString(ABytes, Start, Length(ABytes) - Start);
  except
    on EEncodingError do
      Result := TEncoding.ANSI.GetString(ABytes, Start, Length(ABytes) - Start);
  end;
end;

// Der Text der Datei APath; False, wenn sie nicht lesbar oder groesser als
// MAX_INI_BYTES ist.
function ReadIniText(const APath: string; out AText: string): Boolean;
var
  FS    : TFileStream;
  Bytes : TBytes;
begin
  Result := False;
  AText := '';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size > MAX_INI_BYTES then
        Exit;
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        FS.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
  except
    // Gesperrt, verschwunden, kein Zugriff: wie "fehlt" - der naechste
    // Aufruf versucht es wieder (Refresh merkt sich nur Gelesenes).
    on EStreamError do
      Exit;
  end;
  AText := DecodeIniBytes(Bytes);
  Result := True;
end;

// Liest APath in AFile, wenn sich Pfad, Existenz oder Dateizeit seit dem
// letzten Lesen geaendert haben - sonst bleiben Text und Memo. Grenze:
// eine zweite Aenderung schneller als die Aufloesung der Dateizeit faellt
// erst mit der naechsten auf (von Hand editiert nie so schnell).
procedure Refresh(var AFile: TRdxIniFile; const APath: string);
var
  Stamp  : TDateTime;
  Exists : Boolean;
  Text   : string;
begin
  Stamp := 0;
  Exists := FileAge(APath, Stamp);
  if not Exists then
    Stamp := 0;
  if (AFile.Path = APath) and (AFile.Exists = Exists)
     and (AFile.Stamp = Stamp) then
    Exit;
  AFile := Default(TRdxIniFile);
  if Exists and not ReadIniText(APath, Text) then
    Exit;                         // Path bleibt '': naechstes Mal neu
  AFile.Path := APath;
  AFile.Exists := Exists;
  AFile.Stamp := Stamp;
  AFile.Text := Text;
end;

// [ASection] AKey aus dem gelesenen Text, ueber das Memo.
function MemoValue(var AFile: TRdxIniFile; const ASection,
  AKey: string): string;
begin
  if not (AFile.MemoValid and SameText(AFile.MemoSect, ASection)
          and SameText(AFile.MemoKey, AKey)) then
  begin
    AFile.MemoSect := ASection;
    AFile.MemoKey := AKey;
    AFile.MemoValue := IniTextValue(AFile.Text, ASection, AKey);
    AFile.MemoValid := True;
  end;
  Result := AFile.MemoValue;
end;

{ ---- Vorlage ---- }

// Legt APath mit der Vorlage an (UTF-8 mit BOM wie analyser.ini), wenn die
// Datei fehlt. Je Verzeichnis EIN Versuch (GTemplateTried): misslingt er,
// geht nicht jeder Menueaufbau erneut auf die Platte.
procedure EnsureRdxIni(const APath: string);
var
  Body : TBytes;
  FS   : TFileStream;
begin
  if GTemplateTried then
    Exit;
  GTemplateTried := True;
  if FileExists(APath) then
    Exit;
  Body := TEncoding.UTF8.GetBytes(RDX_INI_TEMPLATE);
  try
    // Ein nicht anlegbarer Ordner meldet sich hier mit False und spaetestens
    // beim Create als EFCreateError.
    ForceDirectories(ExtractFilePath(APath));
    FS := TFileStream.Create(APath, fmCreate);
    try
      FS.WriteBuffer(UTF8_BOM[0], Length(UTF8_BOM));
      FS.WriteBuffer(Body[0], Length(Body));
    finally
      FS.Free;
    end;
  except
    // GRENZE (Entscheid E29): die Vorlage ist Komfort wie bei analyser.ini.
    // Schreibschutz, ein nicht anlegbarer Ordner (EInOutError aus
    // ForceDirectories), eine gesperrte Datei (EStreamError) - nichts davon
    // darf als Ausnahme in ein Menue oder die Gluehbirne laufen. Ohne
    // Datei gilt die Vorgabe auto.
    on EInOutError do
      Exit;
    on EStreamError do
      Exit;
  end;
end;

{ ---- Werte ---- }

// [ASection] AKey aus redelphix.ini; legt die Vorlage an. Nur unter GLock.
function ReadRdxIni(const ASection, AKey: string): string;
var
  Path : string;
begin
  Path := ConfigDirLocked + RDX_INI_NAME;
  EnsureRdxIni(Path);
  Refresh(GRdxIni, Path);
  Result := MemoValue(GRdxIni, ASection, AKey);
end;

// [ASection] AKey aus analyser.ini - nur lesen, nie anlegen (das ist
// Sache der SCA). Nur unter GLock.
function ReadAnalyserIni(const ASection, AKey: string): string;
begin
  Refresh(GAnalyserIni, ConfigDirLocked + ANALYSER_INI_NAME);
  Result := MemoValue(GAnalyserIni, ASection, AKey);
end;

// 'auto', leer (oder nur Leerraum) - Gross-/Kleinschreibung egal.
function IsAutoLanguage(const AValue: string): Boolean;
begin
  Result := (Trim(AValue) = '') or SameText(Trim(AValue), LANG_AUTO);
end;

{ ---- ini-Text ---- }

// Die Zeile ab APos (ohne Zeilenende, getrimmt); APos steht danach hinter
// dem Zeilenende (CRLF, LF oder CR).
function NextLine(const AText: string; var APos: Integer): string;
var
  Start : Integer;
begin
  Start := APos;
  while (APos <= Length(AText)) and (AText[APos] <> #13)
        and (AText[APos] <> #10) do
    Inc(APos);
  Result := Trim(Copy(AText, Start, APos - Start));
  if (APos <= Length(AText)) and (AText[APos] = #13) then
    Inc(APos);
  if (APos <= Length(AText)) and (AText[APos] = #10) then
    Inc(APos);
end;

// True fuer eine Kopfzeile '[Name]' (getrimmt), ASection ihr Name.
function IsSectionLine(const ALine: string; out ASection: string): Boolean;
begin
  Result := (Length(ALine) >= 2) and (ALine[1] = '[')
    and (ALine[Length(ALine)] = ']');
  if Result then
    ASection := Trim(Copy(ALine, 2, Length(ALine) - 2))
  else
    ASection := '';
end;

// True, wenn ALine 'AKey=Wert' ist (kein Kommentar), AValue der Wert.
function IsKeyLine(const ALine, AKey: string; out AValue: string): Boolean;
var
  Eq : Integer;
begin
  AValue := '';
  Eq := Pos('=', ALine);
  Result := (Eq > 1) and (ALine[1] <> ';') and (ALine[1] <> '#')
    and SameText(Trim(Copy(ALine, 1, Eq - 1)), AKey);
  if Result then
    AValue := Trim(Copy(ALine, Eq + 1, MaxInt));
end;

function IniTextValue(const AText, ASection, AKey: string): string;
var
  P         : Integer;
  Line      : string;
  Name      : string;
  InSection : Boolean;
begin
  Result := '';
  InSection := False;
  P := 1;
  while P <= Length(AText) do
  begin
    Line := NextLine(AText, P);
    if IsSectionLine(Line, Name) then
      InSection := SameText(Name, ASection)
    else if InSection and IsKeyLine(Line, AKey, Result) then
      Exit;
  end;
end;

function ResolveRdxLanguage(const ARdxValue, AScaLanguage,
  AAnalyserValue: string): string;
begin
  if IsAutoLanguage(ARdxValue) then
  begin
    Result := NormalizeLangCode(AScaLanguage);
    if Result = '' then
      Result := NormalizeLangCode(AAnalyserValue);
  end
  else
    Result := NormalizeLangCode(ARdxValue);
  if Result = '' then
    Result := LANG_FALLBACK;
end;

{ ---- oeffentlich ---- }

function RdxLanguage: string;
var
  RdxValue, Sca, Analyser : string;
begin
  GLock.Enter;
  try
    if GOverride <> '' then
      RdxValue := GOverride
    else
      RdxValue := ReadRdxIni(SECTION_UI, KEY_LANGUAGE);
    Sca := CurrentLanguage;
    Analyser := '';
    // analyser.ini nur, wenn sie entscheidet (auto, und die SCA hat noch
    // keine Sprache gesetzt) - sonst kein zweiter Plattenzugriff.
    if IsAutoLanguage(RdxValue) and (NormalizeLangCode(Sca) = '') then
      Analyser := ReadAnalyserIni(SECTION_UI, KEY_LANGUAGE);
    Result := ResolveRdxLanguage(RdxValue, Sca, Analyser);
  finally
    GLock.Leave;
  end;
end;

function _(const S: string): string;
begin
  Result := TranslateTo(RdxLanguage, S);
end;

function _(const Fmt: string; const Args: array of const): string;
begin
  Result := TranslateTo(RdxLanguage, Fmt, Args);
end;

procedure SetRdxLanguageOverride(const ALang: string);
begin
  GLock.Enter;
  try
    GOverride := Trim(ALang);
  finally
    GLock.Leave;
  end;
end;

function RdxLanguageOverride: string;
begin
  GLock.Enter;
  try
    Result := GOverride;
  finally
    GLock.Leave;
  end;
end;

procedure SetRdxConfigDir(const ADir: string);
begin
  GLock.Enter;
  try
    GConfigDir := Trim(ADir);
    // Neues Verzeichnis: der alte Text gilt nicht mehr, und die Vorlage
    // bekommt dort ihren eigenen Versuch.
    GRdxIni := Default(TRdxIniFile);
    GAnalyserIni := Default(TRdxIniFile);
    GTemplateTried := False;
  finally
    GLock.Leave;
  end;
end;

function RdxConfigDir: string;
begin
  GLock.Enter;
  try
    Result := ConfigDirLocked;
  finally
    GLock.Leave;
  end;
end;

function RdxIniPath: string;
begin
  Result := RdxConfigDir + RDX_INI_NAME;
end;

function RdxIniValue(const ASection, AKey: string): string;
begin
  GLock.Enter;
  try
    Result := ReadRdxIni(ASection, AKey);
  finally
    GLock.Leave;
  end;
end;

function RdxIniTemplate: string;
begin
  Result := RDX_INI_TEMPLATE;
end;

{ ---- Gemeinsame Texte ---- }

function MsgLineMoved: string;
begin
  Result := uRdxText._(MSG_LINE_MOVED);
end;

function MsgMovedSuffix(const AReason: string): string;
begin
  Result := uRdxText._(MSG_MOVED_SUFFIX, [AReason]);
end;

function MsgStaleSuffix(const AReason: string): string;
begin
  Result := uRdxText._(MSG_STALE_SUFFIX, [AReason]);
end;

function MsgNoColumn: string;
begin
  Result := uRdxText._(MSG_NO_COLUMN);
end;

function MsgStatementEndNotFound: string;
begin
  Result := uRdxText._(MSG_STMT_END);
end;

function MsgNoValidRange: string;
begin
  Result := uRdxText._(MSG_NO_RANGE);
end;

function MsgHeaderEndNotFound: string;
begin
  Result := uRdxText._(MSG_HEADER_END);
end;

function MsgLineStartsInCommentOrString: string;
begin
  Result := uRdxText._(MSG_STARTS_INSIDE);
end;

function MsgNoFileOpen: string;
begin
  Result := uRdxText._(MSG_NO_FILE);
end;

function MsgByHand: string;
begin
  Result := uRdxText._(MSG_BY_HAND);
end;

function MsgCheckByHand: string;
begin
  Result := uRdxText._(MSG_CHECK_BY_HAND);
end;

function MsgDeleteByHand: string;
begin
  Result := uRdxText._(MSG_DELETE_BY_HAND);
end;

function MsgDecideByHand: string;
begin
  Result := uRdxText._(MSG_DECIDE_BY_HAND);
end;

function MsgOnlyStatementEmptyBlock(const AKeyword: string): string;
begin
  Result := uRdxText._(MSG_EMPTY_BLOCK, [AKeyword]);
end;

function MsgUnclearStatementOwner(const APrevToken: string): string;
begin
  Result := uRdxText._(MSG_UNCLEAR_OWNER, [APrevToken]);
end;

function MsgLiteralUnreadable(const ACode: string): string;
begin
  Result := uRdxText._(MSG_LITERAL, [ACode]);
end;

function MsgNoOperandInChain: string;
begin
  Result := uRdxText._(MSG_NO_OPERAND);
end;

function MsgDeclsInClassesOfName(ACount: Integer; const AName: string): string;
begin
  Result := uRdxText._(MSG_DECLS_IN_CLASS, [ACount, AName]);
end;

function MsgNoLongerAtReportedPlace(const ACode: string): string;
begin
  Result := uRdxText._(MSG_NOT_AT_PLACE, [ACode]);
end;

function MsgNoHeader(const AWhose: string): string;
begin
  Result := uRdxText._(MSG_NO_HEADER, [AWhose]);
end;

function MsgHeadersFmt: string;
begin
  // _() ohne Argumente formatiert nicht: %d und %s bleiben fuer
  // OneTokenReason stehen.
  Result := uRdxText._(MSG_HEADERS_FMT);
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  FreeAndNil(GLock);

end.
