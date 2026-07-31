unit uUnusedPrivateMethod;

// Detektor: private Methode wird in der Unit nie aufgerufen.
//
// Pattern (Code Smell, Sonar-50 #37):
//   TFoo = class
//   private
//     procedure HelperA;            // <-- nie gerufen, alter Refactoring-Rest
//   public
//     procedure DoStuff;
//   end;
//
// Erkennung (AST + lexisch):
//   * Phase 1: walke nkClass -> nkVisibilitySection mit Name='private' oder
//     'strict private'. Sammle alle nkMethod-Children -> Method-Namen
//     (unqualifiziert) als Kandidaten.
//   * Phase 2: lese den File-Text, strippe Strings + Kommentare. Suche
//     pro Kandidaten-Namen nach `\bMethodName\b` als ganzes Wort.
//     Ein Treffer = Aufruf irgendwo. Skip-Pattern:
//        - Die Deklaration selbst (TypeRef-Zeile im class-body).
//        - Die Implementation `procedure TFoo.MethodName;` - der Identifier
//          taucht da auch auf, ist aber kein "Aufruf".
//     Heuristik: wir zaehlen ALLE Vorkommen. Wenn Count > 2 (Deklaration +
//     ggf. Implementation-Header) -> als verwendet markieren.
//     Damit bleiben TRUE-Unused-Methoden klar identifizierbar; FPs koennen
//     bei super-kurzen Namen entstehen (`Init`, `Get`) - in der Praxis aber
//     selten weil Pascal-Code unterschiedliche Klassen mit eigenen Methoden
//     selten ueber die gleiche Schreibweise verteilt.
//
// Limitierungen:
//   * Cross-unit-Aufrufe von public Methoden sind kein Problem - wir
//     analysieren nur PRIVATE Methoden, die ohnehin nur in der eigenen
//     Unit aufgerufen werden duerfen.
//   * Property-Getter/Setter (`Get*` / `Set*` private Methoden) werden
//     zwar als Methoden gesehen, ihre Verwendung via Property-Block
//     `read FGetSomething` zaehlt aber als Treffer in der Text-Suche -
//     also kein FP.
//   * RTTI / interfaces via TypeInfo werden NICHT erkannt.
//     Suppression-Marker `// noinspection UnusedPrivateMethod` als
//     Escape-Hatch.
//
// KEIN FFI-GATE (gemessen, Backlog 4e-3 / 30%-Audit 2026-07-31):
//   SCA138 GodClass und SCA141 LargeClass haben ein Gate gegen ObjC-/JNI-
//   Bridge-Typen bekommen (TDetectorUtils.CollectFfiBindingTypes). Fuer
//   SCA147 waere es WIRKUNGSLOS und wurde deshalb bewusst NICHT gebaut:
//   von 3.325 Korpusfunden (sca-rw-after123) liegt genau EINER auf einem
//   FFI-Typ - TToast.DestroyClass in Kastri/Core/DW.Toast.Android.pas.
//   Der Mechanismus dahinter ist strukturell und kein Zufall der
//   Stichprobe: generierte Bridge-Interfaces haben ueberhaupt keine
//   Visibility-Sections (Phase 1 findet dort nichts), und die
//   TJavaGenericImport-/TOCGenericImport-Begleitklassen sind leere
//   Einzeiler. Der eine Treffer ist zudem ein FP AUS ANDEREM GRUND
//   (`class destructor` wird nie namentlich gerufen) - ein FFI-Gate wuerde
//   ihn nur zufaellig mit erwischen und die echte Ursache verdecken.
//   NACHTRAG 2026-07-31: genau dieser Fund (TToast.DestroyClass,
//   Kastri/Core/DW.Toast.Android.pas:24) faellt jetzt unter Gate C - also
//   ueber seine echte Ursache statt ueber die FFI-Zufallskorrelation.
//
// DFM-EVENT-BINDINGS (seit 2026-06-20):
//   Wenn neben der .pas eine gleichnamige .dfm liegt (Standard-VCL-
//   Konvention), wird sie mitgescannt: alle Event-Property-Werte
//   (`OnClick = btnGoClick`) sind Implicit-Callers fuer den Pascal-
//   Code. Private Methoden die als Handler eingetragen sind werden
//   damit nicht mehr als unused gemeldet.
//   Implementierung: Regex `^\s*On\w+\s*=\s*(\w+)\s*$` pro DFM-Zeile;
//   Match per case-insensitive HashSet<string>. Skript-only DFMs ohne
//   bekanntes File-Extension-Mapping bleiben unentdeckt - akzeptabel.
//
// REFERENZ-SICHTBARKEITS-GATES (30%-Real-World-Audit 2026-07-31):
//   Die Regel lag im Audit bei 100% FP (24/24 im Detailsample). Gemeinsamer
//   Nenner: der 2-Treffer-Toleranz-Scan sieht NUR namentliche Aufrufe im
//   Unit-Text. Fuenf Aufruf-Mechanismen laufen strukturell an ihm vorbei;
//   fuer die wird jetzt VOR dem Melden abgebrochen (reine Unterdrueckung,
//   kein neuer Meldepfad, kein Anker-/Severity-Wechsel):
//     A message-Direktive  -> VCL-Dispatch (TObject.Dispatch)
//     B Method-Resolution  -> 'procedure IFace.Name = Impl;' ist gar keine
//                             Methode, nur ein Alias-Eintrag
//     C class constructor/destructor -> RTL ruft sie beim Unit-Init/-Final
//     D override           -> VMT-Dispatch aus dem Vorfahren
//     E Interface-Impl     -> Interface-Dispatch, meist cross-unit
//   Korpus-Messung (sca-rw-after124, 3.325 Funde): A 2.792 / B 9 / C 36 /
//   D 19 / E 276+ -> erwarteter Drop ~3.132 (94%), Rest ~193.
//
// GATE C UND DIE PARSER-LUECKE (2026-08-01):
//   Gate C las urspruenglich NUR den ';class'-Marker aus dem TypeRef. Der
//   fehlt aber genau dann, wenn 'class' direkt hinter dem Sichtbarkeits-
//   Keyword steht - uParser2.ParseClassBody frisst das Token dort schon im
//   Visibility-Zweig weg (unbedingtes Eat(tkKwClass), gedacht fuer
//   'private class var'). Betroffen ist immer nur der ERSTE Member einer
//   Section. Deshalb liegt hinter der TypeRef-Pruefung jetzt ein Quell-
//   Anker (Sca147DeclIsClassPrefixed).
//   Korpus-Wirkung: KEINE. Alle 36 Gate-C-Funde aus sca-rw-after124 tragen
//   den Marker (sie stehen ausnahmslos hinter 'class var'-Zeilen), die
//   Prognose von 36 Drops bleibt also unveraendert. Der Anker schliesst
//   eine latente Luecke: korpusweit sind 44 von 485 class-ctor/dtor-
//   Deklarationen erstes Section-Member (16 davon in private) - die
//   entgehen SCA147 heute nur, weil ihre Namen ('Create'/'Destroy') im
//   Unit-Text ohnehin ueber der 2-Treffer-Toleranz liegen.
//   Gegenprobe ueber alle 3.325 Funde: der Anker gatet dieselben 36 auch
//   allein (beide Pfade sind auf Echtcode deckungsgleich) und KEINEN der
//   2 gewoehnlichen privaten ctor/dtor-Funde - 0 Regressionen.
//
// GRENZEN DER GATES (bewusst so):
//   * 'virtual'/'dynamic' OHNE 'override' wird NICHT gegated - eine neu
//     eingefuehrte private virtuelle Methode, die niemand in der Unit ruft,
//     ist ein legitimer Fund.
//   * Gate E schaltet die ganze Klasse still, sobald EIN implementiertes
//     Interface nicht in dieser Unit deklariert ist (der Regelfall - im
//     Korpus gibt es KEINE Klasse, deren Interfaces alle lokal sind). Sind
//     sie alle lokal aufloesbar, werden nur die namensgleichen Member
//     stillgeschaltet; echte tote Helfer der Klasse bleiben dann Funde.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnusedPrivateMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NestedTry, NilComparison, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.IOUtils,
  uDetectorUtils, uFileTextCache;

// Liest die zur PAS-Datei gehoerende DFM (gleicher Pfad mit .dfm-Extension)
// und extrahiert alle Event-Handler-Werte. Pattern:
//   ^<whitespace>On<word> = <handlerName>$
// Beispiel: `  OnClick = btnGoClick` -> 'btngoclick'
//
// Result-Dict ist owned by Caller (FreeAndNil oder try-finally). Wenn die
// DFM nicht existiert oder nicht lesbar ist, kommt ein leeres Dict zurueck -
// Detector behandelt das wie "keine DFM-Bindings".
function BuildDfmHandlerSet(const PasFileName: string): TDictionary<string, Boolean>;
const
  HANDLER_RE = '^\s*On\w+\s*=\s*(\w+)\s*$';
var
  DfmPath : string;
  DfmText : string;
  RE      : TRegEx;
  M       : TMatch;
  Name    : string;
begin
  Result := TDictionary<string, Boolean>.Create;
  if PasFileName = '' then Exit;
  DfmPath := ChangeFileExt(PasFileName, '.dfm');
  if not TFile.Exists(DfmPath) then Exit;
  try
    DfmText := TFile.ReadAllText(DfmPath);
  except
    // Datei-IO-Fehler -> wie "keine DFM"
    Exit;
  end;
  RE := TRegEx.Create(HANDLER_RE, [roMultiLine]);
  for M in RE.Matches(DfmText) do
  begin
    Name := LowerCase(M.Groups[1].Value);
    if Name <> '' then Result.AddOrSetValue(Name, True);
  end;
end;

// Restschulden-Audit 2026-07-26: lokale UnqualifiedName-Kopie entfernt -
// jetzt TDetectorUtils.UnqualifiedNameLast (war in 8 Detektoren dupliziert,
// eine Kopie mit abweichender Semantik). Verhalten hier unveraendert.

function IsPrivateSection(const Name: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(Name));
  Result := (Low = 'private') or (Low = 'strict private');
end;

// ===========================================================================
// Referenz-Sichtbarkeits-Gates (Audit 2026-07-31) - alles nur Unterdrueckung.
// ===========================================================================

const
  // Obergrenzen fuer den Deklarations-Scan (Gate A). Eine reale Methoden-
  // Deklaration inklusive Parameterliste und Direktiven-Kette bleibt weit
  // darunter; die Grenzen verhindern nur, dass ein fehlplatzierter Anker
  // (kaputte Quelle, IFDEF-Zwilling) ueber die halbe Datei laeuft.
  SCA147_MAX_DECL_CHARS   = 4000;
  SCA147_MAX_DIR_SEGMENTS = 12;
  // Schutz gegen zyklische / absurd tiefe Interface-Ketten (Gate E).
  SCA147_MAX_IFACES       = 64;

type
  // Auswertungsstand des Interface-Gates fuer die AKTUELLE Klasse. Wird
  // erst beim ersten Melde-Kandidaten der Klasse berechnet (ifsUnknown),
  // damit Klassen ohne Fund keinen Aufwand erzeugen.
  TSca147IfaceState = (ifsUnknown, ifsNone, ifsBlanket, ifsNames);

function Sca147IsIdentCh(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

// Naechstes Token ab APos (exklusive Obergrenze ALimit). Liefert entweder
// einen kompletten Identifier-Run oder ein einzelnes Sonderzeichen; '' am
// Puffer-Ende. Whitespace umfasst auch #10 - der gestrippte Code haelt pro
// Quellzeile genau ein #10, Strings/Kommentare sind mit Space geblankt.
function Sca147NextTok(const Code: string; var APos: Integer;
  ALimit: Integer): string;
var
  S : Integer;
begin
  while (APos <= ALimit) and (Code[APos] <= ' ') do Inc(APos);
  if APos > ALimit then Exit('');
  if Sca147IsIdentCh(Code[APos]) then
  begin
    S := APos;
    while (APos <= ALimit) and Sca147IsIdentCh(Code[APos]) do Inc(APos);
    Result := Copy(Code, S, APos - S);
  end
  else
  begin
    Result := Code[APos];
    Inc(APos);
  end;
end;

function Sca147IsDirectiveWord(const AWordLow: string): Boolean;
// Methoden-Direktiven, die zwischen dem Kopf-Semikolon und einer eventuellen
// 'message'-Direktive stehen duerfen. BEWUSST OHNE 'message' - das Wort
// beendet den Kettenlauf mit dem Treffer.
const
  DIRS: array[0..35] of string = (
    'abstract',   'assembler',  'cdecl',      'dcpcall',    'delayed',
    'delphicall', 'deprecated', 'dispid',     'dynamic',    'experimental',
    'export',     'external',   'far',        'final',      'forward',
    'index',      'inline',     'library',    'local',      'mwpascal',
    'name',       'near',       'noreturn',   'overload',   'override',
    'pascal',     'platform',   'register',   'reintroduce','safecall',
    'static',     'stdcall',    'unsafe',     'varargs',    'virtual',
    'winapi');
var
  i : Integer;
begin
  Result := False;
  for i := Low(DIRS) to High(DIRS) do
    if DIRS[i] = AWordLow then Exit(True);
end;

// 1-basierter Index in Code, an dem die 1-basierte Quellzeile ALine1
// beginnt. LineFor stammt aus TDetectorUtils.StripStringsAndComments und ist
// monoton steigend (pro Quellzeile ein Block plus das #10) -> Binaersuche.
// 0 = Zeile nicht abbildbar (dann kein Gate, wie bisher melden).
function Sca147LineStart(const LineFor: TArray<Integer>;
  ALine1: Integer): Integer;
var
  Lo, Hi, Mid, Target : Integer;
begin
  Result := 0;
  Target := ALine1 - 1;
  if (Target < 0) or (Length(LineFor) = 0) then Exit;
  if Target > LineFor[High(LineFor)] then Exit;
  Lo := 0;
  Hi := High(LineFor);
  while Lo < Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if LineFor[Mid] < Target then Lo := Mid + 1 else Hi := Mid;
  end;
  if LineFor[Lo] <> Target then Exit;
  Result := Lo + 1;
end;

// GATE A: traegt die Deklaration ab AStart eine 'message'-Direktive?
//
// 'message' ist KEINE Parser-Direktive (uParser2.IsMethodDirectiveTok kennt
// sie nicht), steht also nirgends im AST - deshalb der Quelltext-Scan auf
// dem bereits gestrippten, lowercase Code.
//
// Zwingend auf Klammertiefe 0 pruefen: der Parameter heisst in fast jedem
// VCL-Handler selbst 'Message' ('procedure WMPaint(var Message: TWMPaint);
// message WM_PAINT;'). Ohne Tiefen-Test wuerde jede Handler-artige Signatur
// matchen, auch ohne Direktive.
//
// Der Scan startet mit einer Identitaets-Pruefung (Routine-Keyword +
// erwarteter Methodenname). Passt der Anker nicht, wird NICHT gegated -
// lieber ein FP behalten als auf gut Glueck unterdruecken.
function Sca147DeclHasMessageDirective(const Code: string; AStart: Integer;
  const AMethNameLow: string): Boolean;
var
  P, Limit, Depth, Seg, Guard : Integer;
  Tk : string;
begin
  Result := False;
  if (AStart <= 0) or (AStart > Length(Code)) then Exit;
  Limit := AStart + SCA147_MAX_DECL_CHARS;
  if Limit > Length(Code) then Limit := Length(Code);
  P := AStart;

  // 1) Kopf-Praeambel: vor dem Routine-Keyword duerfen auf derselben Zeile
  //    noch ein Sichtbarkeits-Keyword und/oder 'class' stehen (kompakt
  //    geschriebene Klassenrumpfe: 'private procedure Foo; message WM_X;').
  Tk    := Sca147NextTok(Code, P, Limit);
  Guard := 0;
  while (Guard < 8) and
        ((Tk = 'strict') or (Tk = 'private') or (Tk = 'protected') or
         (Tk = 'public') or (Tk = 'published') or (Tk = 'class')) do
  begin
    Tk := Sca147NextTok(Code, P, Limit);
    Inc(Guard);
  end;
  if (Tk <> 'procedure') and (Tk <> 'function') and
     (Tk <> 'constructor') and (Tk <> 'destructor') and
     (Tk <> 'operator') then Exit;

  // 2) Der Name muss der des AST-Knotens sein - sonst zeigt der Anker
  //    woanders hin und der Rest des Scans waere geraten.
  Tk := Sca147NextTok(Code, P, Limit);
  if Tk <> AMethNameLow then Exit;

  // 3) Kopf bis zum ';' auf Klammertiefe 0 ueberlesen.
  Depth := 0;
  repeat
    Tk := Sca147NextTok(Code, P, Limit);
    if Tk = '' then Exit;
    if (Tk = '(') or (Tk = '[') then
      Inc(Depth)
    else if (Tk = ')') or (Tk = ']') then
      Dec(Depth)
    else if Depth <= 0 then
    begin
      if Tk = ';' then Break;
      // Sichtbarkeits-Keywords / 'end' koennen in einem gueltigen Kopf nicht
      // vorkommen - hier ist der Scan aus dem Tritt geraten.
      if (Tk = 'end') or (Tk = 'private') or (Tk = 'public') or
         (Tk = 'protected') or (Tk = 'published') then Exit;
    end;
  until False;

  // 4) Direktiven-Kette abschreiten. In allen 2.792 Korpusfaellen ist
  //    'message' das ERSTE Kettenglied; die Schleife deckt zusaetzlich
  //    Reihenfolgen wie '; overload; message WM_X;' ab.
  for Seg := 1 to SCA147_MAX_DIR_SEGMENTS do
  begin
    repeat
      Tk := Sca147NextTok(Code, P, Limit);
    until Tk <> ';';
    if Tk = '' then Exit;
    if Tk = 'message' then Exit(True);
    if not Sca147IsDirectiveWord(Tk) then Exit;
    // Rest dieses Direktiven-Segments bis zum ';' auf Tiefe 0 verwerfen
    // ('deprecated ''text'';', 'external ''dll'' name ''fn'';').
    Depth := 0;
    repeat
      Tk := Sca147NextTok(Code, P, Limit);
      if Tk = '' then Exit;
      if (Tk = '(') or (Tk = '[') then
        Inc(Depth)
      else if (Tk = ')') or (Tk = ']') then
        Dec(Depth)
      else if (Depth <= 0) and (Tk = ';') then
        Break;
    until False;
  end;
end;

// TypeRef-Format aus uParser2.ParseMethodSignature/ParseMethodDirectives:
//   'kind[:rueckgabetyp];dir1;dir2'   (Direktiven bereits lowercase)
// Segment 0 (kind + Rueckgabetyp) ist KEINE Direktive und wird ausgelassen.
function Sca147TypeRefHasDirective(const ATypeRef, ADirLow: string): Boolean;
var
  i, Start : Integer;
  IsFirst  : Boolean;
begin
  Result  := False;
  IsFirst := True;
  Start   := 1;
  for i := 1 to Length(ATypeRef) do
    if ATypeRef[i] = ';' then
    begin
      if IsFirst then
        IsFirst := False
      else if LowerCase(Trim(Copy(ATypeRef, Start, i - Start))) = ADirLow then
        Exit(True);
      Start := i + 1;
    end;
  // letztes Segment (kein abschliessendes ';' im TypeRef)
  if (not IsFirst) and (Start <= Length(ATypeRef)) and
     (LowerCase(Trim(Copy(ATypeRef, Start, MaxInt))) = ADirLow) then
    Result := True;
end;

// Routine-Art aus dem TypeRef: alles vor dem ersten ';' bzw. ':'.
function Sca147TypeRefKind(const ATypeRef: string): string;
var
  i : Integer;
begin
  Result := ATypeRef;
  for i := 1 to Length(ATypeRef) do
    if CharInSet(ATypeRef[i], [';', ':']) then
    begin
      Result := Copy(ATypeRef, 1, i - 1);
      Break;
    end;
  Result := LowerCase(Trim(Result));
end;

// GATE C, Quell-Anker: steht vor dem Routine-Keyword der Deklaration in
// Zeile Mth.Line ein 'class'-Praefix?
//
// WARUM NOETIG (empirisch belegt, nicht vermutet): uParser2.ParseClassBody
// haengt das ';class'-Suffix an den TypeRef nur im tkKwClass-Zweig an. Steht
// das 'class' aber DIREKT hinter dem Sichtbarkeits-Keyword, frisst der
// Sichtbarkeits-Zweig das Token schon vorher weg - dort steht ein
// unbedingtes Eat(tkKwClass), das fuer 'private class var'/'public class
// const' gedacht ist. Der tkKwClass-Zweig laeuft dann nie, und der TypeRef
// des ERSTEN Members einer Section lautet nur 'destructor' statt
// 'destructor;class'.
//   private                          -> TypeRef 'destructor'        (Marker weg)
//     class destructor DestroyClass;
//   private                          -> TypeRef 'destructor;class'  (Marker da)
//     FDummy: Integer;
//     class destructor DestroyClass;
// A/B mit der CLI auf genau diesem Paar: ohne Feld feuert SCA147, mit Feld
// nicht. Betroffen ist ausschliesslich der jeweils erste Member einer
// Visibility-Section - und genau so schreibt man einen class destructor
// ueblicherweise hin. Der Parser ist gesperrt, deshalb faengt der Detektor
// die Luecke am Quelltext ab (gleiches Muster wie SCA097
// IsClassDestructorByLine).
//
// Anker-Identitaet wie bei Gate A: passen Routine-Keyword oder Name nicht,
// wird NICHT gegatet - lieber ein FP behalten als blind unterdruecken.
function Sca147DeclIsClassPrefixed(const Code: string; AStart: Integer;
  const AMethNameLow, AKindLow: string): Boolean;
var
  P, Limit, Guard : Integer;
  Tk       : string;
  SawClass : Boolean;
begin
  Result := False;
  // Harte Reichweiten-Grenze DIESER Routine: sie darf ausschliesslich
  // class constructor / class destructor stillschalten. Eine private
  // 'class procedure'/'class function' ist ein legitimer Fund und muss
  // gemeldet bleiben - der Aufrufer prueft das schon, hier steht es
  // nochmal, damit die Zusicherung an der Funktion selbst haengt.
  if (AKindLow <> 'constructor') and (AKindLow <> 'destructor') then Exit;
  if (AStart <= 0) or (AStart > Length(Code)) then Exit;
  Limit := AStart + SCA147_MAX_DECL_CHARS;
  if Limit > Length(Code) then Limit := Length(Code);
  P        := AStart;
  SawClass := False;

  // Kopf-Praeambel: Sichtbarkeits-Keywords und 'class' vor dem Routine-
  // Keyword ueberlesen und dabei merken, ob 'class' dabei war.
  Tk    := Sca147NextTok(Code, P, Limit);
  Guard := 0;
  while (Guard < 8) and
        ((Tk = 'strict') or (Tk = 'private') or (Tk = 'protected') or
         (Tk = 'public') or (Tk = 'published') or (Tk = 'class')) do
  begin
    if Tk = 'class' then SawClass := True;
    Tk := Sca147NextTok(Code, P, Limit);
    Inc(Guard);
  end;
  if not SawClass then Exit;
  // Routine-Art muss die des AST-Knotens sein ('constructor'/'destructor').
  // Schuetzt gegen 'private class var FX: Integer; destructor Foo;' - dort
  // steht zwar ein 'class' voran, es gehoert aber zur var-Sektion.
  if Tk <> AKindLow then Exit;
  Tk := Sca147NextTok(Code, P, Limit);
  Result := Tk = AMethNameLow;
end;

// 'IFoo' -> True, 'Item'/'I'/'i18n' -> False. Original-Case ist Absicht:
// die Delphi-Konvention ist I + Grossbuchstabe; ein case-insensitiver Test
// wuerde 'Item', 'Info', 'Interval' mitnehmen (Lehre aus der SCA001-Runde).
function Sca147IsInterfaceStyleName(const S: string): Boolean;
begin
  Result := (Length(S) >= 2) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
end;

// Space-getrennte Namensliste (uParser2 legt Elternlisten so in TypeRef ab)
// in unqualifizierte Einzelnamen zerlegen: 'Vcl.Forms.TForm IFoo' -> TForm, IFoo.
procedure Sca147SplitNames(const AText: string; ADest: TStringList);
var
  i    : Integer;
  Cur  : string;
  Name : string;
begin
  ADest.Clear;
  Cur := '';
  for i := 1 to Length(AText) do
    if AText[i] <= ' ' then
    begin
      if Cur <> '' then
      begin
        Name := TDetectorUtils.UnqualifiedNameLast(Cur);
        if Name <> '' then ADest.Add(Name);
        Cur := '';
      end;
    end
    else
      Cur := Cur + AText[i];
  if Cur <> '' then
  begin
    Name := TDetectorUtils.UnqualifiedNameLast(Cur);
    if Name <> '' then ADest.Add(Name);
  end;
end;

// GATE E, Teil 1: welche Interfaces implementiert diese Klasse?
//
// Delphi-Grammatik: in 'TFoo = class(TBase, I1, I2)' ist Eintrag 0 die
// Basisklasse, ab Eintrag 1 stehen ausschliesslich Interfaces. Zusaetzlich
// wird die I-Konvention verlangt - Schutz gegen IFDEF-Zwillinge, bei denen
// der Lexer beide Zweige emittiert und so eine zweite "Basisklasse" in die
// Liste rutscht ('class({$IFDEF X}TA{$ELSE}TB{$ENDIF})' -> 'TA TB').
function Sca147CollectImplementedInterfaces(C: TAstNode;
  ADest: TStringList; AScratch: TStringList): Boolean;
var
  i : Integer;
begin
  ADest.Clear;
  Result := False;
  if C.TypeRef = '' then Exit;
  Sca147SplitNames(C.TypeRef, AScratch);
  for i := 1 to AScratch.Count - 1 do
    if Sca147IsInterfaceStyleName(AScratch[i]) then
      ADest.Add(AScratch[i]);
  Result := ADest.Count > 0;
end;

// Namens-Index aller Typknoten der Unit. uParser2 fuehrt Interfaces als
// nkClass - ein eigener Knotentyp existiert nicht, der Lookup deckt daher
// Klassen wie Interfaces ab. Gefuettert wird die bereits eingesammelte
// nkClass-Liste des Aufrufers (kein zweiter FindAll-Durchlauf).
function Sca147BuildTypeIndex(AClasses: TList<TAstNode>)
  : TDictionary<string, TAstNode>;
var
  N : TAstNode;
begin
  Result := TDictionary<string, TAstNode>.Create;
  try
    for N in AClasses do
      if N.Name <> '' then
        Result.AddOrSetValue(LowerCase(N.Name), N);
  except
    Result.Free;
    raise;
  end;
end;

// GATE E, Teil 2: Member-Namen aller implementierten Interfaces sammeln.
// False, sobald EIN Interface in dieser Unit nicht deklariert ist - der
// Aufrufer schaltet dann die ganze Klasse still, weil er nicht unterscheiden
// kann, welche private Methode das fremde Interface bedient.
function Sca147TryResolveIfaceMembers(
  ATypeIdx: TDictionary<string, TAstNode>; ANames: TStringList;
  AMembers: TDictionary<string, Boolean>): Boolean;
var
  Work    : TStringList;
  Seen    : TDictionary<string, Boolean>;
  Parents : TStringList;
  Idx, i  : Integer;
  NameLow : string;
  Node    : TAstNode;
  Sec, M  : TAstNode;
begin
  Result  := True;
  Work    := TStringList.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  Parents := TStringList.Create;
  try
    Work.Assign(ANames);
    Idx := 0;
    while Idx < Work.Count do
    begin
      NameLow := LowerCase(Work[Idx]);
      Inc(Idx);
      if Seen.ContainsKey(NameLow) then Continue;
      Seen.Add(NameLow, True);
      if Seen.Count > SCA147_MAX_IFACES then Exit(False);

      // RTL-Wurzeln: nie lokal deklariert, Member trotzdem bekannt.
      if (NameLow = 'iinterface') or (NameLow = 'iunknown') or
         (NameLow = 'idispatch') then
      begin
        AMembers.AddOrSetValue('queryinterface', True);
        AMembers.AddOrSetValue('_addref', True);
        AMembers.AddOrSetValue('_release', True);
        if NameLow = 'idispatch' then
        begin
          AMembers.AddOrSetValue('gettypeinfocount', True);
          AMembers.AddOrSetValue('gettypeinfo', True);
          AMembers.AddOrSetValue('getidsofnames', True);
          AMembers.AddOrSetValue('invoke', True);
        end;
        Continue;
      end;

      if not ATypeIdx.TryGetValue(NameLow, Node) then Exit(False);

      // Member haengen unter nkVisibilitySection (Enkel des Typknotens).
      for Sec in Node.Children do
      begin
        if Sec.Kind <> nkVisibilitySection then Continue;
        for M in Sec.Children do
          if ((M.Kind = nkMethod) or (M.Kind = nkProperty)) and (M.Name <> '') then
            AMembers.AddOrSetValue(
              LowerCase(TDetectorUtils.UnqualifiedNameLast(M.Name)), True);
      end;

      // Basis-Interfaces mitnehmen (bei Interfaces sind ALLE Eintraege der
      // Elternliste Interfaces, deshalb ab Index 0).
      Sca147SplitNames(Node.TypeRef, Parents);
      for i := 0 to Parents.Count - 1 do
        Work.Add(Parents[i]);
    end;
  finally
    Parents.Free;
    Seen.Free;
    Work.Free;
  end;
end;

class procedure TUnusedPrivateMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Classes    : TList<TAstNode>;
  C          : TAstNode;
  S, Mth     : TAstNode;
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  // Perf P1 (Konzept_Performance25, 2026-07-19): Wort-Positions-Index einmal
  // pro File statt TRegEx-Volltext-Scan PRO Private-Methode.
  WordIdx    : TObjectDictionary<string, TList<Integer>>;
  PosList    : TList<Integer>;
  Count      : Integer;
  MethName   : string;
  MethLow    : string;
  MethKind   : string;
  F          : TLeakFinding;
  DfmHandlers: TDictionary<string, Boolean>;
  // Gate A (message-Direktive): Zeichen-Position jeder Quellzeile im
  // gestrippten Code. Frueher ungenutzt.
  LineFor    : TArray<Integer>;
  DeclPos    : Integer;
  // Gate E (Interface-Implementierung): pro Klasse lazy ausgewertet.
  TypeIdx    : TDictionary<string, TAstNode>;
  IfaceNames : TStringList;
  IfaceScrat : TStringList;
  IfaceMemb  : TDictionary<string, Boolean>;
  IfaceState : TSca147IfaceState;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  WordIdx := nil;   // Perf P1: nil-sicher im finally
  TypeIdx := nil;   // Gate E: erst beim ersten Melde-Kandidaten gebaut
  try
    // 2026-07-04: lokale Strip-Kopie durch zentrale TDetectorUtils-Fassung
    // ersetzt (Audit Duplikations-Rest). Verhaltensgleich zur alten Variante:
    // FillCh=' ' wie frueher (String-Inhalte -> Space, nicht Tilde-Default),
    // und LowerCase auf dem Gesamtergebnis ist aequivalent zum frueheren
    // Inline-LowerCase pro Code-Zeichen (LowerCase(' ')=' ', #10 invariant).
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := LowerCase(TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineFor, AContext, FileName, ' '));
    // Perf P1: einmaliger Index (Code ist bereits lowercase -> Keys identisch
    // zum frueheren case-sensitiven '\b'+methlow+'\b'-Match).
    WordIdx := TDetectorUtils.BuildWordPositionIndex(Code);
    // DFM-Event-Handler-Set fuer diese .pas/.dfm-Paarung.
    DfmHandlers := BuildDfmHandlerSet(FileName);
    IfaceNames  := nil;   // nil-sicher im finally (Muster wie WordIdx)
    IfaceScrat  := nil;
    IfaceMemb   := nil;
    try
      IfaceNames := TStringList.Create;
      IfaceScrat := TStringList.Create;
      IfaceMemb  := TDictionary<string, Boolean>.Create;
      Classes := UnitNode.FindAll(nkClass);
      try
        for C in Classes do
        begin
          // Gate E wird pro Klasse hoechstens einmal ausgewertet - und erst,
          // wenn tatsaechlich ein Fund anstuende.
          IfaceState := ifsUnknown;
          // Direkte Children der Klasse durchgehen, Visibility-Sections
          // mit Name 'private' / 'strict private' aufspueren.
          for S in C.Children do
          begin
            if S.Kind <> nkVisibilitySection then Continue;
            if not IsPrivateSection(S.Name) then Continue;

            // Methoden in dieser Section sammeln.
            for Mth in S.Children do
            begin
              if Mth.Kind <> nkMethod then Continue;
              MethName := TDetectorUtils.UnqualifiedNameLast(Mth.Name);
              if MethName = '' then Continue;
              MethLow := LowerCase(MethName);

              // DFM-Binding-Check: ist die Methode als Event-Handler in
              // der gleichnamigen .dfm eingetragen? Dann ist sie laufzeit-
              // referenziert und kein Unused-Kandidat.
              if DfmHandlers.ContainsKey(MethLow) then Continue;

              // Text-Scan via Wort-Index (Perf P1): Vorkommens-Anzahl ist
              // die Laenge der Positions-Liste - identisch zur frueheren
              // Regex-Zaehlung ('\b'+methlow+'\b' auf lowercase-Code).
              if WordIdx.TryGetValue(MethLow, PosList) then
                Count := PosList.Count
              else
                Count := 0;
              if Count > 2 then Continue;

              // ---- Referenz-Sichtbarkeits-Gates (Audit 2026-07-31) ----
              // Ab hier stuende ein Fund an. Alle folgenden Pruefungen
              // BRECHEN NUR AB - kein neuer Meldepfad, kein veraenderter
              // Anker, keine Severity-Aenderung fuer ueberlebende Funde.

              // GATE B: Method-Resolution-Clause. In einem Klassenrumpf ist
              // ein qualifizierter Methodenname ('IFileCommands.ExecClose =
              // Close;') nie eine Deklaration, sondern nur ein Alias-Eintrag
              // - die "Methode" existiert unter diesem Namen gar nicht.
              if Pos('.', Mth.Name) > 0 then Continue;

              // GATE C: class constructor / class destructor. Die RTL ruft
              // sie beim Unit-Init bzw. -Finalize, nie namentlich.
              // Zwei Quellen fuer den class-Marker: der TypeRef des Parsers,
              // und - wenn der ihn verschluckt hat (siehe
              // Sca147DeclIsClassPrefixed) - der Quelltext der Deklarations-
              // zeile. Eine gewoehnliche private 'class procedure'/'class
              // function' hat Kind 'procedure'/'function' und laeuft an
              // beiden Pruefungen vorbei - sie bleibt ein Fund.
              MethKind := Sca147TypeRefKind(Mth.TypeRef);
              if (MethKind = 'constructor') or (MethKind = 'destructor') then
              begin
                if Sca147TypeRefHasDirective(Mth.TypeRef, 'class') then Continue;
                DeclPos := Sca147LineStart(LineFor, Mth.Line);
                if (DeclPos > 0) and
                   Sca147DeclIsClassPrefixed(Code, DeclPos, MethLow, MethKind) then
                  Continue;
              end;

              // GATE D: override. Der Aufruf kommt per VMT aus dem Vorfahren
              // - eine namentliche Referenz in dieser Unit ist nicht noetig.
              // Bewusst NUR override: 'virtual'/'dynamic' ohne Vorfahren-
              // Aufrufer bleibt ein legitimer Fund.
              if Sca147TypeRefHasDirective(Mth.TypeRef, 'override') then Continue;

              // GATE E: Interface-Implementierung (Interface-Dispatch).
              if IfaceState = ifsUnknown then
              begin
                if Sca147CollectImplementedInterfaces(C, IfaceNames, IfaceScrat) then
                begin
                  if TypeIdx = nil then TypeIdx := Sca147BuildTypeIndex(Classes);
                  IfaceMemb.Clear;
                  if Sca147TryResolveIfaceMembers(TypeIdx, IfaceNames, IfaceMemb) then
                    IfaceState := ifsNames
                  else
                    IfaceState := ifsBlanket;
                end
                else
                  IfaceState := ifsNone;
              end;
              if IfaceState = ifsBlanket then Continue;
              if (IfaceState = ifsNames) and IfaceMemb.ContainsKey(MethLow) then
                Continue;

              // GATE A: message-Direktive (VCL-Dispatch). Zuletzt, weil als
              // einziges Gate ein Quelltext-Scan noetig ist - 'message' steht
              // nicht im AST.
              DeclPos := Sca147LineStart(LineFor, Mth.Line);
              if (DeclPos > 0) and
                 Sca147DeclHasMessageDirective(Code, DeclPos, MethLow) then
                Continue;

              F            := TLeakFinding.Create;
              F.FileName   := FileName;
              F.MethodName := Mth.Name;
              F.LineNumber := IntToStr(Mth.Line);
              F.MissingVar := Format(
                'Private method %s.%s appears unused (no call within the unit)',
                [C.Name, MethName]);
              F.SetKind(fkUnusedPrivateMethod);
              Results.Add(F);
            end;
          end;
        end;
      finally
        Classes.Free;
      end;
    finally
      IfaceMemb.Free;
      IfaceScrat.Free;
      IfaceNames.Free;
      DfmHandlers.Free;
    end;
  finally
    TypeIdx.Free;
    WordIdx.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
