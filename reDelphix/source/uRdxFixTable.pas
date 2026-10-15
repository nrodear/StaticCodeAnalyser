unit uRdxFixTable;

// reDelphix - die Tabelle der einfachen Editorhilfen: je Fundart EINE
// Zeile mit Planer, Hinweis, Kennzeichnung (E2), zweitem Eintrag und
// Menuetext. Der Laeufer-Einstieg (FixFor, AlternativeFixFor, Handles) und
// der Anbieter (CaptionFor) lesen aus derselben Zeile.
//
// WARUM (Wochen-Review 2026-10-13, Bereich B, Major 4; Charge R8): bis
// dahin lag das Wissen je Regel in zwei Units in parallelen case-Ketten -
// uRdxRecipeRunner FixFor -> LaterFixFor -> LineFixFor -> LineFix ->
// LinePlan -> DeclPlan (dazu LineHint -> DeclHint, FlowHint) und
// uRdxProvider SimpleFixCaption -> LaterFixCaption -> LineFixCaption ->
// DeclFixCaption -> FlowFixCaption -, nur zerteilt, um SCA091 (grosses
// case) zu unterbieten. Eine Art ohne Menuetext zeigte still ihren internen
// Namen (KindName), und kein Test fiel. Hier faellt uTestRdxFixTable: jede
// Zeile hat Planer, Hinweis (oder der Planer setzt ihn) und Menuetext.
//
// OHNE ToolsAPI: in reDelphix.Test uebersetzbar. Nicht im FPC-Pruefstand -
// die Unit braucht uRdxRecipeRunner, der den Quellstellen-Dienst braucht.
// Die Rumpf-Routinen der Hilfen bleiben, wo sie sind (uRdxRecipeRunner,
// die Planer-Units); hier stehen nur die Adapter auf eine gemeinsame Form
// (TRdxFixPlanner), das EINE Geruest der Planer mit Plan-Record
// (TRdxFixFrame, Charge H5c) und die Zeilen.
//
// MENUETEXTE: englische msgids, uebersetzt ueber i18n/*.po (Editorhilfen
// E6) in die reDelphix-Sprache (uRdxText._, Entscheid E29 - wie die
// SCA-Oberflaeche oder redelphix.ini [UI] Language; uRdxText nennt den
// Weg). Sie stehen in FIX_CAPTIONS und FIX_ALT_CAPTIONS - zwei String-
// Arrays parallel zu FIX_ROWS, nicht als Feld der Zeile: tools/
// i18n_extract.py liest nur _('..'), _(KONSTANTE) und _(ARRAY[i]); ein
// Record-Feld bliebe fuer template.pot unsichtbar, und msgmerge markierte
// die Uebersetzungen als obsolet. uTestRdxFixTable haelt die drei Arrays
// zusammen (gleicher Index, kein leerer Menuetext, zweiter Menuetext genau
// mit zweitem Planer).

interface

uses
  System.Classes,
  uEngineApi,          // TSourcePlaces
  uMethodd12,          // TLeakFinding
  uSCAConsts,          // TFindingKind
  uRdxRecipeRunner;    // TRdxFixOutcome

type
  // Ein Planer der Tabelle - die Form von TRdxFixRunner.FixFor fuer EINE
  // Art: Zeile und Meldung kommen aus AFinding, die uses-Namen fuer eine
  // Einfuegung (SysUtils) aus AUsesNames.
  TRdxFixPlanner = function(APlaces: TSourcePlaces; ALines: TStrings;
    AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

  // Eine Zeile der Tabelle (FIX_ROWS).
  //   Hint           Hinweis des aktiven Eintrags (deutsch, wie die
  //                  Gruende); '' nur mit HintByPlanner: der Planer setzt
  //                  ihn selbst (aus Name oder Ersetzung, bei SCA085/SCA139
  //                  vor dem ' + uses ...'). Genau eines von beiden.
  //   Changes        Kennzeichnung '(aendert Verhalten)' (E2), soweit sie
  //                  nicht vom Fund abhaengt - SCA149 (override oder
  //                  reintroduce) entscheidet der Planer.
  //   Alt            der zweite Eintrag derselben Art (Variant = 1: SCA168
  //                  else mit raise, SCA020 raise ENotImplemented), nil
  //                  ohne. Er setzt Variant, Hinweis und Kennzeichnung
  //                  selbst (der Hinweis bekommt noch ' + uses ...').
  TRdxFixRow = record
    Kind          : TFindingKind;
    Plan          : TRdxFixPlanner;
    Hint          : string;
    HintByPlanner : Boolean;
    Changes       : Boolean;
    Alt           : TRdxFixPlanner;
  end;

  // Der Einstieg des Anbieters und der Tests. Eine weitere Regel ist eine
  // Zeile mehr in FIX_ROWS samt Menuetext in FIX_CAPTIONS - kein Zweig
  // mehr in einem Verteiler.
  TRdxFixTable = class
  public
    // True, wenn die Tabelle fuer diese Art eine Hilfe kennt.
    class function Handles(AKind: TFindingKind): Boolean; static;

    // Die Hilfe fuer einen Fund: der Planer seiner Art, danach der Hinweis
    // der Zeile (wenn der Planer keinen setzte) und die Kennzeichnung.
    // Ohne Fund: Reason 'kein Fund'; ohne Zeile: 'keine einfache Hilfe
    // fuer diese Regel'.
    class function FixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Der zweite Eintrag fuer denselben Fund (Variant = 1), sonst ein
    // leeres Ergebnis (Variant = 0).
    class function AlternativeFixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Menuetext einer Hilfe, uebersetzt in die reDelphix-Sprache
    // (uRdxText): der Eintrag nach AOutcome.Variant, '%s' durch
    // AOutcome.Name ('X', wenn der Planer abgelehnt hat, bevor der Name
    // feststand), dahinter die Kennzeichnung bei ChangesBehavior. '' ohne
    // Zeile - dann entsteht KEIN Eintrag (bis Charge R8 stand dann
    // KindName im Menue).
    class function CaptionFor(AKind: TFindingKind;
      const AOutcome: TRdxFixOutcome): string; static;

    // Fuer uTestRdxFixTable: die Zeilen und ihre Menuetexte (msgids,
    // unuebersetzt; AVariant 0 oder 1).
    class function RowCount: Integer; static;
    class function Row(AIndex: Integer): TRdxFixRow; static;
    class function RawCaption(AIndex, AVariant: Integer): string; static;
  end;

implementation

uses
  // Vor System.SysUtils, damit deren Namen gelten (FindClose u. a.):
  // GetDriveType fuer den Netzlaufwerk-Check von SCA014.
  Winapi.Windows,
  System.SysUtils,
  uRdxText,          // _(): in die reDelphix-Sprache (E29), nie uLocalization
  uRdxRecipes,       // AsciiOnly (SCA085-Gegenprobe)
  uRdxCodeMap,       // TRdxCodeMap (Adapter auf die Code-Sicht)
  uRdxBufferMath,    // TRdxEdit
  uRdxSimpleFixes,   // SCA075, SCA087 (ExplicitTObject, EmptySection)
  uRdxLineFixes,     // SCA082, SCA071, SCA088
  uRdxRaiseFixes,    // SCA020, SCA120, SCA122
  uRdxDeclFixes,     // SCA117, SCA197, SCA149
  uRdxFlowFixes,     // SCA098, SCA080, SCA047
  uRdxRoutineFixes,  // SCA164, SCA147
  uRdxCleanupFixes,  // SCA070, SCA053
  uRdxTryFixes,      // SCA009, SCA001, SCA109, SCA153, SCA156
  uRdxResultFixes,   // SCA096, SCA097, SCA121, SCA196
  uRdxMagicFixes;    // SCA014

const
  // Hinweise der Hilfen (deutsch wie die Gruende; Pruefstand und Tests
  // pruefen sie woertlich). Bis Charge R8 in uRdxRecipeRunner (LineHint,
  // DeclHint, FlowHint und je Rumpf) - bis auf die ersten vier: SCA075,
  // SCA074, SCA087 und SCA066 bekommen mit der Tabelle ERSTMALS einen
  // festen Hinweis; bis dahin blieb ihr Hint leer, und der Eintrag stand
  // ohne Erklaerung im Menue (Gegen-Review R8, Major 1; uTestRdxFixTable
  // pinnt R_TOBJECT_HINT woertlich).
  R_TOBJECT_HINT  = 'TObject ist ohnehin der Vorfahr - gleiche Bedeutung';
  R_ASSERT_HINT   = 'die Bedingung als Text - so nennt die Meldung, was '
    + 'fehlschlug';
  R_EMPTYSEC_HINT = 'der Abschnitt war leer - gleiche Bedeutung';
  R_NOARGS_HINT   = 'gleiche Bedeutung - Delphi ruft die Routine auch ohne '
    + 'Klammern auf';
  R_CASE_ELSE_HINT = 'alle anderen Werte: nichts tun (wie bisher)';
  R_BLOCK_HINT     = 'gleiche Bedeutung - nur die Form; eine weitere '
    + 'Anweisung gehoert danach sichtbar in den Zweig';
  R_SEMI_HINT   = 'das zweite ";" war eine leere Anweisung';
  R_INDENT_HINT = 'nur Leerraum';
  R_INIT_HINT   = 'gleiche Bedeutung - der Abschnitt kann danach ein '
    + 'finalization bekommen';
  R_EMPTY_HINT  = 'die Absicht steht im Rumpf - ein Grund dahinter hilft dem '
    + 'naechsten Leser';
  R_MISSING_RAISE_HINT = 'die Exception wird jetzt ausgeloest - der Code '
    + 'dahinter laeuft im Fehlerfall nicht mehr';
  R_RERAISE_HINT = 'dieselbe Exception - der Original-Stack-Trace bleibt '
    + 'erhalten';
  R_DOC_HINT     = 'das Geruest ist leer - summary, param und returns '
    + 'ausfuellen';
  R_GUID_HINT    = 'eine neue GUID - nur fuer eigene Interfaces, nie fuer '
    + 'COM-Importe';
  R_OVERRIDE_HINT = 'der virtuelle Aufruf landet danach in dieser Methode';
  R_REINTRODUCE_HINT = 'nur die Warnung W1010 entfaellt - die Methode '
    + 'verdeckt die geerbten weiterhin';
  R_COND_HINT = 'gleiche Bedeutung - eine Zuweisung statt zweier Zweige';
  R_JUMP_HINT = 'gleiche Bedeutung - der Ablauf verlaesst den Block ohnehin';
  R_SELF_HINT = 'die Zuweisung bewirkt nichts - war ein anderer Wert gemeint '
    + '(Tippfehler), fehlt er weiterhin';
  R_ROUTINE_HINT = 'gleiche Bedeutung - der Name steht sonst nirgends im '
    + 'Code der Datei; Doku und ein Kommentar darueber, der die Routine nennt, '
    + 'gehen mit';
  R_METHOD_HINT  = 'gleiche Bedeutung - Deklaration und Implementierung '
    + 'gehen, der Name steht sonst nirgends im Code der Datei';
  R_FORM_UNREADABLE = 'Formdatei %s nicht lesbar (%s) - eine Ereignis-'
    + 'Bindung ist nicht auszuschliessen';
  // SCA147: Formdateien, die eine Methode per Name an ein Ereignis binden.
  FORM_EXTENSIONS: array[0..2] of string = ('.dfm', '.fmx', '.lfm');
  R_COMMENTED_HINT = 'gleiche Bedeutung - nur Kommentar faellt weg; die '
    + 'Versionsverwaltung kennt ihn noch';
  R_UNUSED_VAR_HINT = 'gleiche Bedeutung - die Variable kommt nirgends sonst '
    + 'vor';
  // Charge H4 (try/finally): alle gekennzeichnet (E2) - B laeuft danach
  // auch dort, wo es bisher uebersprungen wurde; das ist der Fix.
  R_TRY_OBJECT_HINT = 'Free laeuft jetzt auch bei einer Ausnahme und bei Exit '
    + '- die Zeilen dazwischen ruecken in den try-Teil';
  R_TRY_LOCK_HINT   = 'die Sperre wird jetzt auch bei einer Ausnahme '
    + 'freigegeben - die Zeilen dazwischen ruecken in den try-Teil';
  R_TRY_BUFFER_HINT = 'FreeMem laeuft jetzt auch bei einer Ausnahme und bei '
    + 'Exit - die Zeilen dazwischen ruecken in den try-Teil';
  // Charge H5 (Ergebnis und Konstruktoren): SCA096/SCA097 je nach Fund -
  // direkter TObject-Erbe bedeutungsgleich, sonst gekennzeichnet; SCA121/
  // SCA196 immer gekennzeichnet (Result ist danach definiert).
  R_CTOR_TOBJECT_HINT = 'TObject.Create ist leer - gleiche Bedeutung; der '
    + 'Konstruktor folgt danach der Konvention';
  R_CTOR_OVERRIDE_HINT = 'der ueberschriebene Elternkonstruktor laeuft jetzt '
    + 'zuerst, mit denselben Argumenten';
  R_DTOR_TOBJECT_HINT = 'TObject.Destroy ist leer - gleiche Bedeutung; der '
    + 'Destruktor folgt danach der Konvention';
  R_DTOR_HINT = 'der Elterndestruktor laeuft jetzt am Ende und gibt die '
    + 'geerbten Felder frei';
  // SCA121: der Wert ist ein Literal (0, False, '''', nil ...) oder
  // Default(T) (Charge H5c); der Menuetext nennt ihn. Bis Charge FB hiess es
  // '(wie Default(T))' - das stimmt nicht, wenn ein Member wie der erste
  // Aufzaehlungswert heisst (Gegen-Review R5-06, Fall 2; Absprache mit FE:
  // der Text muss fuer Literal UND Default(T) stimmen).
  R_RESULT_DEFAULT_HINT = 'Result beginnt jetzt mit dem genannten Wert statt '
    + 'zufaellig - spaetere Zuweisungen gelten weiter';
  R_RESULT_INIT_HINT = 'Result beginnt jetzt leer statt mit dem alten Inhalt '
    + 'der Zielvariable des Aufrufers';
  // SCA014 (Charge Q14, E28): die Inline-Konstante haelt die Bedeutung des
  // Literals (E26); den vorlaeufigen Namen benennt der Benutzer selbst um -
  // keine Sync-Edit-Sitzung der Hilfe, und auch kein Rat dazu: Esc
  // zerstoert im Sync Edit Text (UI-Test 2026-10-11), Strg+Umschalt+J
  // braucht eine Markierung (Gegen-Review Q14, Minor 13).
  R_MAGIC_HINT = 'gleiche Bedeutung - die Konstante %s haelt das Literal; '
    + 'umbenennen von Hand oder mit Refactor > Rename (Strg+Umschalt+E)';
  // SCA014 auf einem Netzlaufwerk: die Hilfe liest dort keine Projekt- und
  // Include-Dateien (Gegen-Review Q14, Verdacht e; UNC prueft FileReason).
  R_MAGIC_REMOTE = 'Netzlaufwerk %s - die Hilfe liest dort keine Projekt- '
    + 'und Include-Dateien (Menueaufbau im Hauptthread); von Hand';
  // SCA147/SCA164 auf einem Netzpfad bzw. Netzlaufwerk (Review FB, R2-07):
  // dieselbe Regel wie SCA014 - FileExists auf einer nicht erreichbaren
  // Freigabe blockierte den IDE-Hauptthread (Gegen-Review R4-03: 2,5 bis
  // 16 s je Aufruf).
  R_REMOTE_FILES = 'Netzpfad %s - die Hilfe liest dort keine %s '
    + '(Menueaufbau im Hauptthread); von Hand';
  WHAT_FORMS    = 'Formdateien';
  WHAT_INCLUDES = 'Include-Dateien';
  // Win32-Namensraum vor einem Pfad (WithoutNamespacePrefix): '\\?\' (lange
  // Pfade) und '\\.\' (Geraete-Namensraum); dahinter 'UNC\' = Netzpfad.
  WIN32_NS_PREFIXES: array[0..1] of string = ('\\?\', '\\.\');
  WIN32_NS_UNC = 'UNC\';
  UNC_LEAD     = '\\';
  // SCA001: nur diese Variante bekommt die Hilfe (Feld TLeakFinding.
  // LeakVariant, das uLeakDetector2 setzt; properties.variant im SARIF).
  LEAK_VARIANT_FOF = 'freed-outside-finally';
  R_NO_FINDING = 'kein Fund';
  R_NO_ROW     = 'keine einfache Hilfe fuer diese Regel';
  // Entscheid E2: eine Hilfe, die das Verhalten aendern kann, sagt es.
  CAP_CHANGES  = '(changes behavior)';
  NAME_UNKNOWN = 'X';

{ ---- Das Geruest der Planer-Adapter (Charge H5c) ----
  Gegen-Review H5, Major 2: bis Charge H5c stand das Geruest - Code-Sicht
  oeffnen, Planer rufen, Name, Grund und Ersetzungen uebernehmen, gesperrt
  ohne Ersetzungen - je Plan-Form einmal: FlowFix (uRdxRecipeRunner),
  RoutineFix, TryFix und ResultFix (hier). Jetzt EIN Geruest
  (TRdxFixFrame.Run); je Plan-Form steht nur noch, was sie unterscheidet
  (TRdxPlanForm): wie Name und Ersetzungen aus dem Plan kommen (Parts),
  eine Pruefung nach dem Angebot (Check) und ob der Quellstellen-Dienst
  offen sein muss (NeedsOpen). Generisch, weil die Planer-Units ihre
  Plan-Records behalten (sie laufen im FPC-Pruefstand); diese Unit
  uebersetzt nur Delphi (reDelphix.Test), nicht der Pruefstand. Bewusst
  NICHT im Geruest: MapFix (uRdxRecipeRunner) - der Laeufer braucht es
  selbst (ExplicitTObjectFix, EmptySectionFix), und seine Planer liefern
  genau eine Ersetzung ohne Plan-Record.
  Delphi-Regeln dazu: freie generische Funktionen gibt es nicht - Run ist
  eine generische Klassenmethode; die Typen stehen im implementation-Teil
  (E2506: ein Generic des interface-Teils duerfte keine Symbole des
  implementation-Teils nutzen); Planer, Parts und Check sind schlichte
  Funktionszeiger (kein 'of object', keine anonyme Methode, die etwas
  einfaengt) - die statischen Klassenmethoden der Planer-Units passen
  unmittelbar hinein. ---- }

type
  // Die Form eines Planers auf der Code-Sicht: ein Plan oder der Grund;
  // True genau dann, wenn AReason = '' (so alle Planer der Tabelle).
  TRdxPlannerOf<TPlan> = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TPlan; out AReason: string): Boolean;
  // Name (Menuetext) und Ersetzungen eines Plans in das Ergebnis.
  TRdxPlanPartsOf<TPlan> = procedure(const APlan: TPlan;
    var AOutcome: TRdxFixOutcome);
  // Die Pruefung nach einem Angebot, solange die Code-Sicht offen ist; ''
  // oder der Grund.
  TRdxPlanCheckOf<TPlan> = function(APlaces: TSourcePlaces;
    AMap: TRdxCodeMap; AFinding: TLeakFinding; const APlan: TPlan): string;

  // Eine Plan-Form: Planer, Parts, Check (nil = keiner) und ob der
  // Quellstellen-Dienst offen sein muss (SCA098/SCA080/SCA047 - bis Charge
  // H5c OpenMapFor in FlowFix).
  TRdxPlanForm<TPlan> = record
    Planner   : TRdxPlannerOf<TPlan>;
    Parts     : TRdxPlanPartsOf<TPlan>;
    Check     : TRdxPlanCheckOf<TPlan>;
    NeedsOpen : Boolean;
  end;

  // Das Geruest.
  TRdxFixFrame = class
  public
    // Ohne Zeilen bzw. (NeedsOpen) ohne offenen Quellstellen-Dienst:
    // R_NO_FILE. Sonst der Planer auf der Code-Sicht, Name und Ersetzungen
    // per Parts, nach einem Angebot der Check; gesperrt ohne Ersetzungen.
    // Den Plan bekommt der Aufrufer in APlan (Kennzeichnung, Variants).
    class function Run<TPlan>(const AForm: TRdxPlanForm<TPlan>;
      APlaces: TSourcePlaces; ALines: TStrings; AFinding: TLeakFinding;
      out APlan: TPlan): TRdxFixOutcome; static;
  end;

class function TRdxFixFrame.Run<TPlan>(const AForm: TRdxPlanForm<TPlan>;
  APlaces: TSourcePlaces; ALines: TStrings; AFinding: TLeakFinding;
  out APlan: TPlan): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  APlan := Default(TPlan);
  Result.Reason := R_NO_FILE;
  if not Assigned(ALines) then Exit;
  if AForm.NeedsOpen and not (Assigned(APlaces) and APlaces.IsOpen) then
    Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    Result.Enabled := AForm.Planner(Map, AFinding.LineInt, AFinding.Message,
      APlan, Result.Reason);
    AForm.Parts(APlan, Result);
    if Result.Enabled and Assigned(AForm.Check) then
      Result.Reason := AForm.Check(APlaces, Map, AFinding, APlan);
  finally
    Map.Free;
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if not Result.Enabled then
    Result.Edits := nil;
end;

// Parts je Plan-Form: der Name fuer den Menuetext und die Ersetzungen
// (gesperrt leert Run sie wieder).
procedure FlowParts(const APlan: TRdxFlowPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Target;
  AOutcome.Edits := TArray<TRdxEdit>.Create(APlan.Edit);
end;

procedure RoutineParts(const APlan: TRdxRoutinePlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

procedure TryParts(const APlan: TRdxTryPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := TArray<TRdxEdit>.Create(APlan.Edit);
end;

procedure ResultParts(const APlan: TRdxResultPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA014: der Menuetext nennt die Zahl (schon, wenn der Planer ablehnt),
// den Namen der Konstante nennt der Hinweis.
procedure MagicParts(const APlan: TRdxMagicPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Value;
  AOutcome.Edits := APlan.Edits;
end;

// SCA098: X und (in der Gegenrichtung) die Bedingung als Boolean bewiesen
// (CondAssignReason, uRdxRecipeRunner).
function CondCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxFlowPlan): string;
begin
  Result := CondAssignReason(APlaces, AMap, AFinding.LineInt, APlan);
end;

// SCA047 prueft das Ziel des Plans (SelfAssignReason nimmt den Namen).
function SelfAssignCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxFlowPlan): string;
begin
  Result := SelfAssignReason(APlaces, AMap, AFinding.LineInt, APlan.Target);
end;

// Liegt AFileName auf einem Netzlaufwerk ('Z:' ueber GetDriveType)?
function IsRemoteDrive(const AFileName: string): Boolean;
var
  Drive : string;
begin
  Drive := ExtractFileDrive(AFileName);
  Result := (Length(Drive) = 2) and (Drive[2] = ':')
    and (GetDriveType(PChar(Drive + PathDelim)) = DRIVE_REMOTE);
end;

// SCA014: liegt die Datei auf einem Netzlaufwerk? Dann liest die Hilfe
// nichts von der Platte - der Menueaufbau laeuft im Hauptthread
// (Gegen-Review Q14, Verdacht e; UNC prueft TRdxMagicFixes.FileReason).
function RemoteDriveReason(const AFileName: string): string;
begin
  Result := '';
  if IsRemoteDrive(AFileName) then
    Result := Format(R_MAGIC_REMOTE, [ExtractFileDrive(AFileName)]);
end;

// AFileName ohne den Vorsatz des Win32-Namensraums: '\\?\C:\src\t.pas' ->
// 'C:\src\t.pas' (ein lokaler Pfad, lang geschrieben; ebenso '\\.\'),
// '\\?\UNC\srv\share\t.pas' -> '\\srv\share\t.pas'. Ohne Vorsatz
// unveraendert.
function WithoutNamespacePrefix(const AFileName: string): string;
var
  i : Integer;
begin
  Result := AFileName;
  for i := 0 to High(WIN32_NS_PREFIXES) do
    if Copy(AFileName, 1, Length(WIN32_NS_PREFIXES[i])) = WIN32_NS_PREFIXES[i] then
    begin
      Result := Copy(AFileName, Length(WIN32_NS_PREFIXES[i]) + 1, MaxInt);
      if SameText(Copy(Result, 1, Length(WIN32_NS_UNC)), WIN32_NS_UNC) then
        Result := UNC_LEAD + Copy(Result, Length(WIN32_NS_UNC) + 1, MaxInt);
      Exit;
    end;
end;

// SCA147/SCA164 (Review FB, R2-07): liegt die Unit auf einem Netzpfad
// ('\\server\share\..', auch mit '/') oder einem Netzlaufwerk? Dann liest
// die Hilfe dort nichts (AWhat: was sie lesen wollte) - dieselbe Regel wie
// SCA014; die UNC-Form ist die von uRdxMagicFixes.FileReason (dort
// privat, zweite Kopie - die gemeinsamen Helfer legt eine spaetere Charge
// zusammen). Der Win32-Namensraum zaehlt ohne Vorsatz
// (WithoutNamespacePrefix; Nachpruefung FB: '\\?\C:\..' hiess bis dahin
// "Netzpfad"). '' oder der Grund.
function NetworkPathReason(const AFileName, AWhat: string): string;
var
  Path : string;
begin
  Result := '';
  Path := WithoutNamespacePrefix(AFileName);
  if (Length(Path) > 2) and CharInSet(Path[1], ['\', '/'])
     and CharInSet(Path[2], ['\', '/']) then
    Result := Format(R_REMOTE_FILES, [ExtractFileDir(Path), AWhat])
  else if IsRemoteDrive(Path) then
    Result := Format(R_REMOTE_FILES, [ExtractFileDrive(Path), AWhat]);
end;

// SCA164: die Include-Dateien vor implementation liest die Hilfe von der
// Platte neben der Unit (Gegen-Review H3, Minor 4) - sie koennen die
// Routine deklarieren oder rufen; nicht gefunden heisst keine Hilfe. Nur,
// wenn der Plan welche nennt (SCA147 nennt keine), und nicht auf einem
// Netzpfad (NetworkPathReason, R2-07).
function IncludeCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxRoutinePlan): string;
begin
  Result := '';
  if Length(APlan.Includes) = 0 then Exit;
  Result := NetworkPathReason(AFinding.FileName, WHAT_INCLUDES);
  if Result = '' then
    Result := TRdxRoutineFixes.IncludeReason(AFinding.FileName,
      APlan.Includes, APlan.Name);
end;

// SCA014: was nur die Platte weiss - Netzlaufwerk, Lazarus-Dateiart oder
// -Projekt bzw. altes Delphi-Projekt neben der Unit, die Compiler-Weichen
// ihrer Includes (TRdxMagicFixes).
function MagicCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxMagicPlan): string;
begin
  Result := RemoteDriveReason(AFinding.FileName);
  if Result = '' then
    Result := TRdxMagicFixes.FileReason(AFinding.FileName);
  if Result = '' then
    Result := TRdxMagicFixes.IncludeReason(AFinding.FileName, AMap);
end;

// Die Plan-Formen der Tabelle.
// SCA098, SCA080, SCA047 (Charge H2): mit offenem Quellstellen-Dienst,
// ACheck danach (nil = keiner) - Typen, with-Bloecke. Name ist das Ziel
// bzw. Exit/Continue.
function FlowForm(APlanner: TRdxPlannerOf<TRdxFlowPlan>;
  ACheck: TRdxPlanCheckOf<TRdxFlowPlan>): TRdxPlanForm<TRdxFlowPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := FlowParts;
  Result.Check := ACheck;
  Result.NeedsOpen := True;
end;

// SCA164, SCA147 (Charge H3b): alle Ersetzungen (Deklaration und
// Implementierung bzw. forward und Rumpf) in EINEM Undo-Schritt, Name die
// Routine bzw. Methode, danach die Include-Dateien (IncludeCheck).
function RoutineForm(
  APlanner: TRdxPlannerOf<TRdxRoutinePlan>): TRdxPlanForm<TRdxRoutinePlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := RoutineParts;
  Result.Check := IncludeCheck;
  Result.NeedsOpen := False;
end;

// SCA009, SCA001, SCA109, SCA153, SCA156 (Charge H4): eine Ersetzung von
// der Zeile von A bis zur Freigabe; Name X, die Sperre bzw. der Puffer -
// schon aus der Meldung, auch wenn der Planer ablehnt.
function TryForm(
  APlanner: TRdxPlannerOf<TRdxTryPlan>): TRdxPlanForm<TRdxTryPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := TryParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA096, SCA097, SCA121, SCA196 (Charge H5): eine Ersetzung (SCA097: zwei,
// wenn der letzten Anweisung das ';' fehlt); Kennzeichnung nach dem Fund
// und der Bedarf an Variants kommen mit dem Plan.
function ResultForm(
  APlanner: TRdxPlannerOf<TRdxResultPlan>): TRdxPlanForm<TRdxResultPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := ResultParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA014 (Charge Q14): eine Ersetzung (Deklaration davor, das Literal
// ersetzt, bei einem Zweig begin..end), Name die Zahl, danach MagicCheck.
function MagicForm(
  APlanner: TRdxPlannerOf<TRdxMagicPlan>): TRdxPlanForm<TRdxMagicPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := MagicParts;
  Result.Check := MagicCheck;
  Result.NeedsOpen := False;
end;

{ ---- Die Planer je Art: Adapter auf die Rumpf-Routinen, alle in der Form
  TRdxFixPlanner (Zeile und Meldung aus dem Fund). ---- }

function PlanExplicitTObject(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.ExplicitTObjectFix(ALines, AFinding.LineInt,
    AFinding.Message);
end;

// X aus der SCA085-Meldung '`X.Free; X := nil;` - prefer ...'; '' ohne
// diese Form.
function FreeTargetOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('`', AMessage);
  if P = 0 then Exit;
  Q := Pos('.Free', AMessage, P + 1);
  if Q = 0 then Exit;
  Result := Trim(Copy(AMessage, P + 1, Q - P - 1));
end;

function PlanFreeAndNil(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Named : string;
begin
  Result := TRdxFixRunner.FreeAndNilFix(APlaces, ALines, AFinding.LineInt,
    AUsesNames);
  // Gegenprobe gegen den Fund wie bei SCA044/SCA003 (Minor 20, hier Nit
  // 26): die Meldung nennt X ('`X.Free; X := nil;` - ...'). Steht nach
  // Einfuegungen oberhalb ein anderes Paar auf der Zeile, nicht umschreiben.
  Named := FreeTargetOf(AFinding.Message);
  if Result.Enabled and (Named <> '')
     and not SameText(TRdxRecipes.AsciiOnly(Named),
                      TRdxRecipes.AsciiOnly(Result.Name)) then
  begin
    Result.Enabled := False;
    Result.Edits   := nil;
    Result.Reason  := Format('Zeile %d traegt %s.Free, der Fund nennt %s - '
      + 'Zeile verschoben? Datei neu pruefen',
      [AFinding.LineInt, Result.Name, Named]);
  end;
end;

function PlanNilComparison(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.NilComparisonFix(APlaces, ALines, AFinding.LineInt);
end;

function PlanAssertMessage(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.AssertMessageFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanEmptySection(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.EmptySectionFix(ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanFreeWithoutNil(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.FreeWithoutNilFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message, AUsesNames);
end;

function PlanEmptyArgs(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.EmptyArgsFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

// SCA072 und SCA084 - OperandFix unterscheidet die Art selbst.
function PlanOperand(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.OperandFix(AFinding.Kind, APlaces, ALines,
    AFinding.LineInt, AFinding.Message);
end;

function PlanUnusedUses(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.UnusedUsesFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanCaseElse(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.CaseElseFix(APlaces, ALines, AFinding.LineInt);
end;

function PlanCaseRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.CaseRaiseFix(APlaces, ALines, AFinding.LineInt,
    AUsesNames);
end;

// SCA101 und SCA099 - BlockFix unterscheidet die Art selbst.
function PlanBlock(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.BlockFix(AFinding.Kind, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanDoubleSemicolon(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxLineFixes.DoubleSemicolon);
end;

function PlanKeywordIndent(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxLineFixes.KeywordIndent);
end;

// LegacyInit braucht die Meldung nicht - die Form von TRdxMapPlanner schon.
function LegacyInitOnMap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
begin
  Result := TRdxLineFixes.LegacyInit(AMap, ALine, AEdit, AReason);
end;

function PlanLegacyInit(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message, LegacyInitOnMap);
end;

function PlanCastFree(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := CastFreeFix(APlaces, ALines, AFinding.LineInt, AFinding.Message);
end;

// SCA020, erster Eintrag: der Absichtskommentar (EmptyBody ohne Anweisung).
function EmptyIntentOnMap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
begin
  Result := TRdxRaiseFixes.EmptyBody(AMap, ALine, '', AEdit, AReason);
end;

function PlanEmptyIntent(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message, EmptyIntentOnMap);
end;

function PlanEmptyRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := EmptyRaiseFix(APlaces, ALines, AFinding.LineInt, AUsesNames);
end;

function PlanMissingRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRaiseFixes.MissingRaise);
end;

function PlanReRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRaiseFixes.ReRaise);
end;

function PlanDocSkeleton(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.DocSkeleton);
end;

function PlanInterfaceGuid(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.InterfaceGuid);
end;

// SCA149 nach dem Rat der Meldung (TRdxDeclFixes.DirectiveFor): Name traegt
// die Direktive (Menuetext); nur override aendert das Verhalten (E2) und
// bekommt den Hinweis dazu - nie reintroduce als zweiter Eintrag:
// Strg+Alt+F liesse das gekennzeichnete override aus und deckte den
// Polymorphie-Fehler mit reintroduce still zu.
function PlanMissingOverride(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.MethodDirective);
  Result.Name := TRdxDeclFixes.DirectiveFor(AFinding.Message);
  Result.ChangesBehavior := Result.Name = DIRECTIVE_OVERRIDE;
  if not Result.Enabled then Exit;
  if Result.ChangesBehavior then
    Result.Hint := R_OVERRIDE_HINT
  else
    Result.Hint := R_REINTRODUCE_HINT;
end;

function PlanRedundantConditional(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.RedundantConditional, CondCheck),
    APlaces, ALines, AFinding, P);
end;

function PlanRedundantJump(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.RedundantJump, nil),
    APlaces, ALines, AFinding, P);
end;

function PlanSelfAssignment(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.SelfAssignment, SelfAssignCheck),
    APlaces, ALines, AFinding, P);
end;

function PlanUnusedRoutine(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxRoutinePlan;
begin
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(
    RoutineForm(TRdxRoutineFixes.UnusedRoutine),
    APlaces, ALines, AFinding, P);
end;

// SCA147: bindet die Formdatei neben der Unit (.dfm/.fmx/.lfm) die Methode
// per Name an ein Ereignis ('OnClick = AName')? Die Hilfe sieht sonst nur
// den Puffer; der Detektor prueft nur .dfm (und .lfm im FPC-Dialekt).
// Gelesen wird die Platte - ein im Designer neu gesetztes Ereignis traegt
// die IDE in den published-Teil ein, nicht unter private. Auf einem
// Netzpfad liest die Hilfe nichts (der Aufrufer prueft NetworkPathReason
// vorher, R2-07). '' oder Grund.
function FormReason(const AUnitFile, AName: string): string;
var
  Ext, Form : string;
  SL        : TStringList;
begin
  Result := '';
  if AUnitFile = '' then Exit;
  for Ext in FORM_EXTENSIONS do
  begin
    Form := ChangeFileExt(AUnitFile, Ext);
    if not FileExists(Form) then Continue;
    SL := TStringList.Create;
    try
      // Oeffnen/Lesen (EStreamError: EFOpenError, EReadError) und die
      // Kodierung (EEncodingError) - alles andere ist kein Lesefehler.
      try
        SL.LoadFromFile(Form);
      except
        on E: EStreamError do
          Exit(Format(R_FORM_UNREADABLE, [ExtractFileName(Form), E.Message]));
        on E: EEncodingError do
          Exit(Format(R_FORM_UNREADABLE, [ExtractFileName(Form), E.Message]));
      end;
      if TRdxRoutineFixes.FormNamesMethod(SL.Text, AName) then
        Exit(Format('die Formdatei %s nennt %s - per Name an ein Ereignis '
          + 'gebunden', [ExtractFileName(Form), AName]));
    finally
      SL.Free;
    end;
  end;
end;

function PlanUnusedPrivateMethod(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxRoutinePlan;
begin
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(
    RoutineForm(TRdxRoutineFixes.UnusedPrivateMethod),
    APlaces, ALines, AFinding, P);
  if not Result.Enabled then Exit;
  Result.Reason := NetworkPathReason(AFinding.FileName, WHAT_FORMS);
  if Result.Reason = '' then
    Result.Reason := FormReason(AFinding.FileName, Result.Name);
  if Result.Reason = '' then Exit;
  Result.Enabled := False;
  Result.Edits := nil;
end;

// SCA070 (Charge H3a): die Region der Meldung (Zeilen, Spalte).
function PlanCommentedOut(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCleanupFixes.CommentedOutCode);
end;

// SCA053 (Charge H3a): Name fuer den Menuetext aus der Meldung - auch,
// wenn der Planer ablehnt.
function PlanUnusedVar(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCleanupFixes.UnusedLocalVar);
  Result.Name := TRdxCleanupFixes.UnusedVarName(AFinding.Message);
end;

function PlanMissingFinally(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.MissingFinally),
    APlaces, ALines, AFinding, P);
end;

// SCA001: nur freed-outside-finally - das Free ist da, liegt aber neben dem
// finally. proven-leak (Konzept: eigene Hilfe, Aufwand L), never-freed und
// return-value-not-freed (Weitergabe bzw. Besitz unbekannt) bekommen keine;
// der Eintrag steht dann gesperrt mit der Variante da. Massgeblich ist das
// FELD LeakVariant (uLeakDetector2), nicht die Ableitung MemoryLeakVariant:
// die raet ohne Feld nach der Schwere (uFieldLeak hat lsError: never-freed)
// - heute liefern beide dasselbe (Gegen-Review H4, Minor 8).
function PlanMemoryLeak(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  LeakVar : string;
  P       : TRdxTryPlan;
begin
  if AFinding.LeakVariant = LEAK_VARIANT_FOF then
    Exit(TRdxFixFrame.Run<TRdxTryPlan>(
      TryForm(TRdxTryFixes.FreedOutsideFinally),
      APlaces, ALines, AFinding, P));
  LeakVar := AFinding.MemoryLeakVariant;
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxTryFixes.NameOf(AFinding.Message);
  Result.Reason := Format('keine Hilfe fuer die Variante %s - nur fuer %s '
    + '(Free vorhanden, aber neben dem finally)', [LeakVar, LEAK_VARIANT_FOF]);
end;

function PlanLockWithoutFinally(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.LockWithoutFinally),
    APlaces, ALines, AFinding, P);
end;

function PlanUnpairedLock(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.UnpairedLock),
    APlaces, ALines, AFinding, P);
end;

function PlanGetMemWithoutFree(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.GetMemWithoutFree),
    APlaces, ALines, AFinding, P);
end;

// SCA096: 'inherited Create;' (direkter TObject-Erbe, bedeutungsgleich)
// bzw. 'inherited;' (override, gekennzeichnet) - wie SCA149 entscheidet der
// Planer, die Zeile traegt Hinweis und Kennzeichnung nicht fest.
function PlanCtorInherited(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ConstructorInherited),
    APlaces, ALines, AFinding, P);
  Result.ChangesBehavior := P.Changes;
  if not Result.Enabled then Exit;
  if P.Changes then
    Result.Hint := R_CTOR_OVERRIDE_HINT
  else
    Result.Hint := R_CTOR_TOBJECT_HINT;
end;

// SCA097: 'inherited;' am Ende - gekennzeichnet, ausser bei direktem
// TObject-Erben (TObject.Destroy ist leer).
function PlanDtorInherited(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.DestructorInherited),
    APlaces, ALines, AFinding, P);
  Result.ChangesBehavior := P.Changes;
  if not Result.Enabled then Exit;
  if P.Changes then
    Result.Hint := R_DTOR_HINT
  else
    Result.Hint := R_DTOR_TOBJECT_HINT;
end;

// SCA121: 'Result := <Wert>;' als erste Anweisung - ein Literal oder
// Default(T), Name ist der Wert (Menuetext 'Initialize Result with %s').
// Hinweis und Kennzeichnung setzt die Zeile fest (immer gekennzeichnet:
// Result ist danach definiert statt zufaellig); den Plan selbst braucht
// der Adapter nicht.
function PlanResultDefault(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ResultDefault),
    APlaces, ALines, AFinding, P);
end;

// SCA196: VarClear (Variant/OleVariant) braucht unter FPC die Unit Variants
// (Delphi kennt es auch ohne; die Unit bringt ohnehin jede Variant-
// Operation mit) - fehlt sie in uses, kommt sie mit (AppendUses, wie
// SysUtils bei FreeAndNil).
function PlanManagedResult(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ManagedResultInit),
    APlaces, ALines, AFinding, P);
  if not Result.Enabled then Exit;
  Result.Hint := R_RESULT_INIT_HINT;
  if P.NeedsVariants then
    Result.Enabled := AppendUses(APlaces, AUsesNames, 'Variants',
      'System.Variants', Result);
end;

// SCA014: 'const MagicNr01 = 200;' vor der Anweisung, das Literal der
// if-Bedingung durch den Namen; der Hinweis nennt den Namen.
function PlanMagicNumber(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxMagicPlan;
begin
  Result := TRdxFixFrame.Run<TRdxMagicPlan>(
    MagicForm(TRdxMagicFixes.MagicNumber),
    APlaces, ALines, AFinding, P);
  if Result.Enabled then
    Result.Hint := Format(R_MAGIC_HINT, [P.Name]);
end;

{ ---- Die Tabelle ---- }

const
  FIX_ROW_HIGH = 39;

  // Je Art eine Zeile; die Reihenfolge ist die der Chargen (Stufe 2a,
  // Stufe 2 Rest, uQuickFix-Umzug/Stufe 3, Zeilen, Ausnahmen, Deklarationen
  // H1, Anweisungen H2, Routinen H3b, Aufraeumen H3a, try/finally H4,
  // Ergebnis und Konstruktoren H5, Magic Number Q14). Der Menuetext steht
  // unter demselben Index in FIX_CAPTIONS (s. Kopf).
  FIX_ROWS: array[0..FIX_ROW_HIGH] of TRdxFixRow = (
    (Kind: fkExplicitTObjectInheritance; Plan: PlanExplicitTObject;
     Hint: R_TOBJECT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeAndNilHint; Plan: PlanFreeAndNil;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkNilComparison; Plan: PlanNilComparison;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssertMessage; Plan: PlanAssertMessage;
     Hint: R_ASSERT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkEmptyVisibilitySection; Plan: PlanEmptySection;
     Hint: R_EMPTYSEC_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeWithoutNil; Plan: PlanFreeWithoutNil;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyArgumentList; Plan: PlanEmptyArgs;
     Hint: R_NOARGS_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantBoolean; Plan: PlanOperand;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssignedAndAssignedNil; Plan: PlanOperand;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    // SCA007: der initialization-Abschnitt der Unit laeuft nicht mehr (E2).
    (Kind: fkUnusedUses; Plan: PlanUnusedUses;
     Hint: ''; HintByPlanner: True; Changes: True; Alt: nil),
    (Kind: fkDefaultCaseInCaseStatement; Plan: PlanCaseElse;
     Hint: R_CASE_ELSE_HINT; HintByPlanner: False; Changes: False;
     Alt: PlanCaseRaise),
    (Kind: fkBeginEndRequired; Plan: PlanBlock;
     Hint: R_BLOCK_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkIfElseBegin; Plan: PlanBlock;
     Hint: R_BLOCK_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSuperfluousSemicolon; Plan: PlanDoubleSemicolon;
     Hint: R_SEMI_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnitLevelKeywordIndent; Plan: PlanKeywordIndent;
     Hint: R_INDENT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkLegacyInitializationSection; Plan: PlanLegacyInit;
     Hint: R_INIT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkCastAndFree; Plan: PlanCastFree;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyMethod; Plan: PlanEmptyIntent;
     Hint: R_EMPTY_HINT; HintByPlanner: False; Changes: False;
     Alt: PlanEmptyRaise),
    // SCA120: die Exception wird jetzt ausgeloest - das ist der Fix (E2).
    (Kind: fkMissingRaise; Plan: PlanMissingRaise;
     Hint: R_MISSING_RAISE_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkReRaiseException; Plan: PlanReRaise;
     Hint: R_RERAISE_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkPublicMemberWithoutDoc; Plan: PlanDocSkeleton;
     Hint: R_DOC_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkInterfaceWithoutGuid; Plan: PlanInterfaceGuid;
     Hint: R_GUID_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkMissingOverride; Plan: PlanMissingOverride;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkRedundantConditional; Plan: PlanRedundantConditional;
     Hint: R_COND_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantJump; Plan: PlanRedundantJump;
     Hint: R_JUMP_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSelfAssignment; Plan: PlanSelfAssignment;
     Hint: R_SELF_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedRoutine; Plan: PlanUnusedRoutine;
     Hint: R_ROUTINE_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedPrivateMethod; Plan: PlanUnusedPrivateMethod;
     Hint: R_METHOD_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkCommentedOutCode; Plan: PlanCommentedOut;
     Hint: R_COMMENTED_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedLocalVar; Plan: PlanUnusedVar;
     Hint: R_UNUSED_VAR_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    // Charge H4: alle gekennzeichnet (E2) - Strg+Alt+F laesst sie aus.
    (Kind: fkMissingFinally; Plan: PlanMissingFinally;
     Hint: R_TRY_OBJECT_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkMemoryLeak; Plan: PlanMemoryLeak;
     Hint: R_TRY_OBJECT_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkLockWithoutTryFinally; Plan: PlanLockWithoutFinally;
     Hint: R_TRY_LOCK_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkUnpairedLock; Plan: PlanUnpairedLock;
     Hint: R_TRY_LOCK_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkGetMemWithoutFreeMem; Plan: PlanGetMemWithoutFree;
     Hint: R_TRY_BUFFER_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    // Charge H5: SCA096/SCA097 kennzeichnet der Planer nach dem Fund (wie
    // SCA149), SCA121/SCA196 immer.
    (Kind: fkConstructorWithoutInherited; Plan: PlanCtorInherited;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkDestructorWithoutInherited; Plan: PlanDtorInherited;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkRoutineResultUnassigned; Plan: PlanResultDefault;
     Hint: R_RESULT_DEFAULT_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkManagedResultUninit; Plan: PlanManagedResult;
     Hint: ''; HintByPlanner: True; Changes: True; Alt: nil),
    // Charge Q14: bedeutungsgleich (E26), den Hinweis setzt der Adapter
    // (Name der Konstante).
    (Kind: fkMagicNumber; Plan: PlanMagicNumber;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil)
  );

  // Menuetexte (msgids) unter dem Index der Zeile; '%s' = Name der Hilfe
  // (X bei SCA085/SCA139, die Unit bei SCA007, der Cast-Typ bei SCA123, die
  // Direktive bei SCA149, das Ziel bzw. Exit/Continue bei SCA098/SCA047/
  // SCA080, die Routine bzw. Methode bei SCA164/SCA147, die Variable bei SCA053,
  // X bzw. die Sperre bzw. der Puffer bei SCA009/SCA001/SCA109/SCA153/SCA156,
  // die Anweisung bei SCA096/SCA196, der Wert bei SCA121 - ein Literal oder
  // Default(T), Charge H5c; die Zahl bei SCA014, Charge Q14).
  FIX_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    'Remove (TObject) from the class declaration',
    'Use FreeAndNil(%s)',
    'Use Assigned() instead of comparing with nil',
    'Use the condition as the Assert message',
    'Remove the empty visibility section',
    'Use FreeAndNil(%s)',
    'Remove the empty parentheses',
    'Remove the redundant comparison with True/False',
    'Remove the redundant comparison with nil',
    'Remove unit %s from uses',
    'Add an empty else branch',
    'Put the branch in begin..end',
    'Put the branch in begin..end',
    'Remove the extra semicolon',
    'Move the keyword to column 1',
    'Replace begin with initialization',
    'Remove the cast to %s before Free',
    'Mark the empty body as intentional',
    'Raise the exception',
    'Use raise; to keep the original stack trace',
    'Insert a documentation skeleton',
    'Insert a new GUID',
    'Add "%s;" to the declaration',
    'Assign the condition to %s directly',
    'Remove the redundant %s',
    'Remove the self-assignment of %s',
    'Delete unused routine %s',
    'Delete unused private method %s',
    'Delete commented-out code',
    'Remove unused variable %s',
    'Free %s in a try/finally block',
    'Free %s in a try/finally block',
    'Release the lock %s in a try/finally block',
    'Release the lock %s in a try/finally block',
    'Free the buffer %s in a try/finally block',
    'Call %s first in the constructor',
    'Call inherited last in the destructor',
    'Initialize Result with %s',
    'Initialize Result first: %s',
    'Introduce local constant for %s'
  );

  // Menuetexte des zweiten Eintrags (Alt), '' ohne.
  FIX_ALT_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    '', '', '', '', '', '', '', '', '', '',
    'Add an else branch that raises an exception',
    '', '', '', '', '', '',
    'Raise ENotImplemented in the empty body',
    '', '', '', '', '', '', '', '', '', '', '', '',
    '', '', '', '', '', '', '', '', '', ''
  );

var
  // Index der Zeile je Art, -1 ohne - einmal in der initialization gebaut.
  GRowIndex : array[TFindingKind] of Integer;

{ TRdxFixTable }

class function TRdxFixTable.Handles(AKind: TFindingKind): Boolean;
begin
  Result := GRowIndex[AKind] >= 0;
end;

class function TRdxFixTable.RowCount: Integer;
begin
  Result := Length(FIX_ROWS);
end;

class function TRdxFixTable.Row(AIndex: Integer): TRdxFixRow;
begin
  Result := FIX_ROWS[AIndex];
end;

class function TRdxFixTable.RawCaption(AIndex, AVariant: Integer): string;
begin
  if AVariant = 1 then
    Result := FIX_ALT_CAPTIONS[AIndex]
  else
    Result := FIX_CAPTIONS[AIndex];
end;

class function TRdxFixTable.FixFor(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Idx : Integer;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(AFinding) then
  begin
    Result.Reason := R_NO_FINDING;
    Exit;
  end;
  Idx := GRowIndex[AFinding.Kind];
  if Idx < 0 then
  begin
    Result.Reason := R_NO_ROW;
    Exit;
  end;
  Result := FIX_ROWS[Idx].Plan(APlaces, ALines, AFinding, AUsesNames);
  if Result.Enabled and (Result.Hint = '') then
    Result.Hint := FIX_ROWS[Idx].Hint;
  // Auch gesperrt gekennzeichnet (wie bisher): der Eintrag steht mit Grund
  // im Menue und sagt, was er taete.
  Result.ChangesBehavior := Result.ChangesBehavior or FIX_ROWS[Idx].Changes;
end;

class function TRdxFixTable.AlternativeFixFor(APlaces: TSourcePlaces;
  ALines: TStrings; AFinding: TLeakFinding;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Idx : Integer;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(AFinding) then Exit;
  Idx := GRowIndex[AFinding.Kind];
  if (Idx < 0) or not Assigned(FIX_ROWS[Idx].Alt) then Exit;
  Result := FIX_ROWS[Idx].Alt(APlaces, ALines, AFinding, AUsesNames);
end;

class function TRdxFixTable.CaptionFor(AKind: TFindingKind;
  const AOutcome: TRdxFixOutcome): string;
var
  Idx  : Integer;
  Name : string;
begin
  Result := '';
  Idx := GRowIndex[AKind];
  if Idx < 0 then Exit;
  // Nie _('') - die msgid '' ist der Kopf der .po.
  if RawCaption(Idx, AOutcome.Variant) = '' then Exit;
  if AOutcome.Variant = 1 then
    Result := _(FIX_ALT_CAPTIONS[Idx])
  else
    Result := _(FIX_CAPTIONS[Idx]);
  Name := AOutcome.Name;
  if Name = '' then Name := NAME_UNKNOWN;
  if Pos('%s', Result) > 0 then
    Result := Format(Result, [Name]);
  if AOutcome.ChangesBehavior then
    Result := Result + ' ' + _(CAP_CHANGES);
end;

procedure BuildRowIndex;
var
  K : TFindingKind;
  i : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
    GRowIndex[K] := -1;
  for i := 0 to High(FIX_ROWS) do
    GRowIndex[FIX_ROWS[i].Kind] := i;
end;

initialization
  BuildRowIndex;

end.
