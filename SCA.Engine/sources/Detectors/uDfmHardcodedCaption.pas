unit uDfmHardcodedCaption;

// Detektor: Hardcodierte UI-Strings im DFM.
//
// Findet String-Literale in UI-Text-Properties (Caption, Hint, Text)
// von Komponenten im DFM. Solche Strings umgehen den Lokalisierungs-Layer
// (dxgettext / gnugettext / uLocalization) und sind in mehrsprachigen
// Projekten ein typischer Lokalisierungs-Smell.
//
// Heuristik bewusst pragmatisch:
//   * Nur Properties aus einer kurzen Whitelist (Caption, Hint, Text).
//   * Nur pvkString-Werte (nicht z.B. Ident, der koennte eine Variable
//     oder Konstante sein).
//   * Leerer / nur-Whitespace-Wert ist kein Befund (Designer setzt
//     Caption = '' um Default-Text auszuschalten).
//
// Aktivierung ist heute global: der Detektor laeuft fuer jede DFM-Datei
// im Analyse-Lauf. Wenn ein Projekt komplett ohne Lokalisierung arbeitet,
// koennen die Befunde via Suppression-Kommentar oder ignore.txt
// ausgeschlossen werden.
//
// FP-Gates (AQL 31.08. -> Charge 15, 06.09.2026; alle DREI belegten
// FP-Klassen der 11-%-Messung, am rw70b-Bestand vollgezaehlt = 1.379
// von 26.358; Zaehlung v5 nach der rw71-Nachschaerfung):
//   G1 GLYPH (44): Ein-Zeichen-Caption bei Font.Name in einem
//      Symbolfont (Webdings/Wingdings/Marlett/Symbol) ist ein Icon,
//      kein Text.
//   G2 RESOURCESTRING (7): die Nachbar-.pas weist DERSELBEN
//      Komponenten-Property einen resourcestring-Ident zu - der
//      DFM-Wert ist ein toter Platzhalter.
//   G3 UEBERSETZUNGS-REGIME (1.328): die Nachbar-.pas nutzt einen
//      Laufzeit-DFM-Uebersetzer (gnugettext/dxgettext/TranslateComponent,
//      Dev-Cpp MultiLangSupport, cnwizards CnLangMgr, uLocalization*).
//      Dann IST der DFM-Text die msgid-Quelle des i18n-Layers - er
//      umgeht nichts. WICHTIG (Losbildungs-Lehre SCA167): die Einheit
//      ist die FORM-UNIT, nicht das Repository - jvcl TRAEGT gettext
//      als Bibliothek, seine Demos uebersetzen deshalb noch lange
//      nicht. Der alte Phase-2-Plan hier ("nur bei gnugettext-uses
//      MELDEN") ist damit invertiert widerlegt: gerade dort ist die
//      Meldung falsch.
//   G4 INIT-UEBERSCHREIBEN (2026-09-16, an BEIDEN Korpora vermessen
//      und adversarisch geprueft): die Nachbar-Unit weist DERSELBEN
//      Komponenten-Property in einem INIT-Kontext einen neuen Wert zu
//      (constructor/FormCreate/FormShow/Loaded/AfterConstruction/
//      DFM-gebundene OnCreate-/OnShow-Handler, plus EINE Aufrufstufe).
//      Delphi: 467 von 24.980 Funden; Lazarus traegt zusaetzlich die
//      frei benannten CREATE-Handler. BEWUSST NICHT jede Zuweisung:
//      im Event-/if-Kontext ist der DFM-Text der korrekte GRUNDZUSTAND
//      (Handpruefung: 56 % Fehlskips grosszuegig vs. 9 % Init).
//      RHS-Selbstreferenz ('Caption := Format(Caption, ...)') skippt
//      nie - dort ist der DFM-Wert das Template. TAction ist KEIN
//      G4-Kanal: eine im DFM GESPEICHERTE Caption weicht per
//      VCL-/LCL-Semantik bewusst von der Action ab und ueberlebt sie.
// Marker-/Zuweisungs-Suche laeuft auf gestripptem Quelltext
// (StripStringsAndComments) - Kommentare und String-Literale zaehlen
// nie als Code-Use.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell (siehe KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmHardcodedCaptionDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uStaticFiles,   // Formdatei-Paarung (Lazarus A4)
  System.Classes,            // TStringList (Nachbar-.pas)
  System.StrUtils,           // StartsText (resourcestring-Blockenden)
  uDetectorUtils,            // StripStringsAndComments (G2/G3-Suche)
  uFileTextCache;            // AcquireLines (Prozess-Cache)

// noinspection-file NilComparison
// "= nil" ist hier idiomatisch (Projektlinie). Die vier weiteren Kinds des
// frueheren Stil-Clusters (CanBeClassMethod, ConsecutiveSection, TooLongLine,
// UnsortedUses) treffen seit dem G4-Umbau nichts mehr - Marker reduziert
// (UnusedSuppression-Bestandsfund, 2026-09-16).

const
  // Default-Whitelist der UI-Text-Properties. Konfigurierbar machen in
  // Phase 2 via analyser.ini ([Components] CaptionProperties=...). Aktuell
  // bewusst kurz, damit der Detektor wenige False Positives erzeugt;
  // 'Text' ist bei TEdit auch User-Input, dort aber Designer-typisch leer.
  CAPTION_PROPS: array[0..2] of string = ('Caption', 'Hint', 'Text');

function IsNonTranslatable(const S: string): Boolean;
// True wenn die Caption KEINEN Buchstaben enthaelt und rein ASCII ist - also
// reine Symbole/Ziffern/Interpunktion ('-', '...', '>>', '|', '123', '/').
// Solche Captions umgehen keinen Lokalisierungs-Layer (es gibt nichts zu
// uebersetzen) -> kein i18n-Smell (dominante DfmHardcodedCaption-FP-Klasse,
// Real-World 2026-06-28). Unicode-Zeichen (Ord > 127, z.B. CJK/kyrillisch/
// akzentuiert) werden NICHT geskippt - das ist uebersetzbarer Text.
var
  C : Char;
  HasLetter, AllAscii : Boolean;
begin
  HasLetter := False;
  AllAscii  := True;
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z']) then HasLetter := True;
    if Ord(C) > 127 then AllAscii := False;
  end;
  Result := (not HasLetter) and AllAscii;
end;

const
  // G1: Fonts, deren Zeichen Icons sind, kein uebersetzbarer Text.
  SYMBOL_FONTS: array[0..5] of string =
    ('Webdings', 'Wingdings', 'Wingdings 2', 'Wingdings 3', 'Marlett',
     'Symbol');
  // G3: Marker eines Laufzeit-DFM-Uebersetzers in der Form-Unit
  // (Herleitung + Vollzaehlung im Unit-Kopf). Nachschaerfung nach dem
  // rw71-A/B (06.09.): ContainsText traf auch KONFIG-Bezeichner wie
  // 'CheckBoxDxgettextSupport' (der JVCL-Installer REDET ueber
  // dxgettext, uebersetzt aber nicht) - jetzt Ident-Grenzen-Match.
  // 'JvGnugettext' steht explizit dabei: der jvcl-Wrapper ist ein
  // ECHTES Uebersetzungs-uses (pyscripter-Muster), trifft aber wegen
  // des 'v' davor keine Grenze von 'gnugettext'.
  REGIME_MARKER: array[0..8] of string =
    ('gnugettext', 'dxgettext', 'JvGnugettext', 'TranslateComponent',
     'TranslateProperties', 'RetranslateComponent', 'MultiLangSupport',
     'CnLangMgr', 'uLocalization');
  // 'uLocalization' ist ein PREFIX (uLocalizationPo etc.): links
  // Ident-Grenze Pflicht, rechts darf der Ident weiterlaufen.
  REGIME_PREFIX_AB = 8;

function IsSymbolFont(const AName: string): Boolean;
var
  S : string;
begin
  for S in SYMBOL_FONTS do
    if SameText(S, AName) then Exit(True);
  Result := False;
end;

function IstIdentZeichen(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function HatRegimeMarker(const ACodeLow: string): Boolean;
// Ident-Grenzen-Suche der REGIME_MARKER im (bereits lowercased)
// gestrippten Quelltext: links IMMER Nicht-Ident, rechts Nicht-Ident
// ausser bei den Prefix-Markern (ab REGIME_PREFIX_AB).
var
  i, P, Start : Integer;
  MkLow       : string;
  Prefix      : Boolean;
begin
  for i := Low(REGIME_MARKER) to High(REGIME_MARKER) do
  begin
    MkLow  := LowerCase(REGIME_MARKER[i]);
    Prefix := i >= REGIME_PREFIX_AB;
    Start  := 1;
    repeat
      P := Pos(MkLow, ACodeLow, Start);
      if P = 0 then Break;
      if ((P = 1) or not IstIdentZeichen(ACodeLow[P - 1]))
         and (Prefix
              or (P + Length(MkLow) > Length(ACodeLow))
              or not IstIdentZeichen(ACodeLow[P + Length(MkLow)])) then
        Exit(True);
      Start := P + 1;
    until False;
  end;
  Result := False;
end;

{ ---- Helfer der .pas-Lektuere (LadeNachbarPas) ----
  Freie Funktionen statt verschachtelter Routinen und statt eines
  Haupt-Passes mit allem drin (SCA176): die Zeilenlogik je Fall steht
  fuer sich, LadeNachbarPas behaelt den Rahmen. Vertrag und Grenzen der
  Gates stehen am Kopf von LadeNachbarPas. }

function KopfName(const AKopf: string; AKeyLen: Integer): string;
// Routinenname aus einer Kopfzeile: Rest nach dem Keyword, Spaces um
// Punkte entfernen (die Stichprobe fand 'TMainForm .FormCreate' -
// real existierender jvcl-Code), dann das Segment nach dem letzten
// Punkt bis '(' / ';' / ':'.
var
  R : string;
  P : Integer;
begin
  R := Trim(Copy(AKopf, AKeyLen + 1, MaxInt));
  R := R.Replace(' .', '.').Replace('. ', '.');
  for P := 1 to Length(R) do
    if CharInSet(R[P], ['(', ';', ':']) then
    begin
      R := Copy(R, 1, P - 1);
      Break;
    end;
  R := Trim(R);
  // TStringHelper.LastDelimiter ist 0-BASIERT (anders als die
  // gleichnamige globale SysUtils-Funktion), Copy 1-basiert: +2 ist
  // die Position NACH dem Punkt; ohne Punkt wird -1+2=1 der ganze
  // Name. Mit +1 lieferte KopfName '.formcreate' - jeder
  // Namensvergleich schlug fehl, das Gate lief im ersten Bau leer
  // (3 rote Tests), nur der namenslose constructor-Kanal trug.
  P := R.LastDelimiter('.') + 2;
  Result := LowerCase(Trim(Copy(R, P, MaxInt)));
end;

function EnthaeltWort(const AText, AWort: string): Boolean;
// Ident-Grenzen-Suche (case-insensitiv); '.' im Wort ist erlaubt
// (comp.prop). Fuer den Selbstreferenz-Check.
var
  TL, WL : string;
  P, St  : Integer;
begin
  Result := False;
  TL := LowerCase(AText);
  WL := LowerCase(AWort);
  St := 1;
  repeat
    P := Pos(WL, TL, St);
    if P = 0 then Exit;
    if ((P = 1) or not IstIdentZeichen(TL[P - 1]))
       and ((P + Length(WL) > Length(TL))
            or not IstIdentZeichen(TL[P + Length(WL)])) then
      Exit(True);
    St := P + 1;
  until False;
end;

procedure SammleAufrufe(const AZeileLow: string; AInitCalls: TStringList);
// Idents, denen '(' oder ';' folgt, aus einer Init-Basis-Rumpfzeile
// in AInitCalls - die EINE Aufrufstufe. Grosszuegig: ein gesammelter
// Nicht-Routinen-Name schadet nicht, weil nur Namen zaehlen, unter
// denen auch Zuweisungen haengen. Eigene Routine, damit die
// Zeichen-Schleife den Haupt-Pass nicht verschachtelt (Selbstscan).
var
  i, j, k : Integer;
begin
  i := 1;
  while i <= Length(AZeileLow) do
  begin
    if not IstIdentZeichen(AZeileLow[i]) then
    begin
      Inc(i);
      Continue;
    end;
    j := i;
    while (j <= Length(AZeileLow)) and IstIdentZeichen(AZeileLow[j]) do
      Inc(j);
    k := j;
    while (k <= Length(AZeileLow)) and (AZeileLow[k] = ' ') do
      Inc(k);
    if (k <= Length(AZeileLow))
       and CharInSet(AZeileLow[k], ['(', ';']) then
      AInitCalls.Add(Copy(AZeileLow, i, j - i));
    i := j;
  end;
end;

// Das erste Wort der Zeile (klein) eroeffnet eine Routine.
function IstRoutinenKopf(const AWortLow: string): Boolean;
begin
  Result := (AWortLow = 'procedure') or (AWortLow = 'function')
    or (AWortLow = 'constructor') or (AWortLow = 'destructor');
end;

// Abschnittswechsel, der einen resourcestring-Block beendet - wortgenau
// (Voll-Review 2026-09-12, Major 56; s. LadeNachbarPas).
function BeendetResBlock(const AWortLow: string): Boolean;
begin
  Result := (AWortLow = 'var') or (AWortLow = 'const') or (AWortLow = 'type')
    or (AWortLow = 'procedure') or (AWortLow = 'function')
    or (AWortLow = 'implementation') or (AWortLow = 'begin')
    or (AWortLow = 'end') or (AWortLow = 'uses');
end;

// Routine mit Init-Basis-Kontext (G4, Vertrag am Kopf von
// LadeNachbarPas): constructor, die bekannten Namen oder ein im DFM an
// der Wurzel gebundener OnCreate-/OnShow-Handler (AInitHandler).
function IstInitRoutine(const AWortLow, ARoutineLow: string;
  AInitHandler: TStrings): Boolean;
begin
  Result := (AWortLow = 'constructor')
    or (ARoutineLow = 'formcreate') or (ARoutineLow = 'formshow')
    or (ARoutineLow = 'loaded') or (ARoutineLow = 'afterconstruction')
    or ((AInitHandler <> nil)
        and (AInitHandler.IndexOf(ARoutineLow) >= 0));
end;

// Res-Ident einer resourcestring-Zeile ('SFoo = ...', auch der Rest
// eines Einzeilers) nach AResIdents - nur, wenn vor dem '=' etwas
// steht; eine leere oder '='-lose Zeile traegt nichts bei.
procedure SammleResIdent(const AZeile: string; AResIdents: TStringList);
var
  PosAssign : Integer;
begin
  PosAssign := Pos('=', AZeile);
  if PosAssign > 1 then
    AResIdents.Add(LowerCase(Trim(Copy(AZeile, 1, PosAssign - 1))));
end;

// 'Comp.Prop := ...' einer Zeile einsammeln (genau EIN Punkt links,
// valide Idents). G2 verlangt zusaetzlich einen reinen Ident vor ';'
// rechts (AZuweisungen: 'comp.prop=ident'); G4 nimmt jede RHS ausser
// der Selbstreferenz (AZuwJeRout: 'routine|comp.prop', nur innerhalb
// einer Routine ARoutineLow <> '').
procedure VerarbeiteZuweisung(const ALine, ARoutineLow: string;
  AZuwJeRout, AZuweisungen: TStringList);
var
  PosAssign, PosDot, PosSemi : Integer;
  Lhs, Rhs, RhsVoll, LhsKey  : string;
begin
  PosAssign := Pos(':=', ALine);
  if PosAssign = 0 then Exit;
  RhsVoll := Trim(Copy(ALine, PosAssign + 2, MaxInt));
  Lhs := Trim(Copy(ALine, 1, PosAssign - 1));
  if Lhs = '' then Exit;
  PosDot := Pos('.', Lhs);
  if (PosDot <= 1) or (Pos('.', Lhs, PosDot + 1) > 0) then Exit;
  // System.SysUtils.IsValidIdent - TDetectorUtils hat keins.
  if not (IsValidIdent(Copy(Lhs, 1, PosDot - 1))
          and IsValidIdent(Copy(Lhs, PosDot + 1, MaxInt))) then Exit;
  LhsKey := LowerCase(Lhs);
  // G4-Kandidat: in einer Routine, ohne RHS-Selbstreferenz.
  if (ARoutineLow <> '') and (not EnthaeltWort(RhsVoll, LhsKey)) then
    AZuwJeRout.Add(ARoutineLow + '|' + LhsKey);
  // G2 unveraendert: reiner Ident bis ';'.
  PosSemi := Pos(';', RhsVoll);
  if PosSemi = 0 then Exit;
  Rhs := Trim(Copy(RhsVoll, 1, PosSemi - 1));
  if (Rhs = '') or not IsValidIdent(Rhs) then Exit;
  AZuweisungen.Add(LhsKey + '=' + LowerCase(Rhs));
end;

// G4 aufloesen: Zuweisungen aus Init-Basis-Routinen direkt, dazu aus
// Routinen, die eine Init-Basis-Routine ruft (eine Stufe). AZuwJeRout
// traegt 'routine|comp.prop', AUeberschrieben bekommt die 'comp.prop'.
procedure LoeseInitZuweisungen(AZuwJeRout, AInitNamen, AInitCalls,
  AUeberschrieben: TStringList);
var
  i, j         : Integer;
  S, Rout, Key : string;
begin
  for i := 0 to AZuwJeRout.Count - 1 do
  begin
    S := AZuwJeRout[i];
    j := Pos('|', S);
    Rout := Copy(S, 1, j - 1);          // Routinenname
    Key  := Copy(S, j + 1, MaxInt);     // comp.prop
    if (AInitNamen.IndexOf(Rout) >= 0) or (AInitCalls.IndexOf(Rout) >= 0) then
      AUeberschrieben.Add(Key);
  end;
end;

type
  // Zustand der .pas-Lektuere ueber die Zeilen hinweg (LadeNachbarPas
  // legt die Listen an und gibt sie frei). Ein Record statt einzelner
  // var-Parameter: der Blockzustand ist kein Schalter, der eine Routine
  // verzweigt (SCA146), sondern Teil des Lesezustands.
  TPasLektuere = record
    InResBlock : Boolean;
    AktRoutine : string;              // lowercase, '' = vor der ersten Routine
    AktIstInit : Boolean;
    InitNamen  : TStringList;         // Routinen mit Init-Basis-Kontext
    InitCalls  : TStringList;         // aus Init-Basis-Ruempfen gerufene Idents
    ZuwJeRout  : TStringList;         // 'routine|comp.prop' je G4-Kandidat
  end;

// Eine Zeile des gestrippten Quelltexts (ALine getrimmt, nicht leer)
// durch alle Faelle, in derselben Reihenfolge wie zuvor im Haupt-Pass
// von LadeNachbarPas: Routinenkopf (G4-Kontext), Aufrufe in einem
// Init-Rumpf, resourcestring-Block (G2), Zuweisung (G2/G4).
procedure VerarbeiteZeile(const ALine: string; AInitHandler: TStrings;
  var St: TPasLektuere; AResIdents, AZuweisungen: TStringList);
var
  W, W2       : string;
  WCol, W2Col : Integer;
begin
  // Erstes WORT der Zeile (wortgenau, Voll-Review 2026-09-12, Major
  // 56): der fruehere Praefix-Match (StartsText) beendete den
  // resourcestring-Block schon bei Res-Idents mit Keyword-PRAEFIX
  // ('typeCaption = ...', 'endUserNote = ...') - dieser und alle
  // folgenden Res-Idents fehlten im G2-Gate, und die Caption wurde
  // gemeldet, obwohl die .pas sie nachweislich zur Laufzeit ersetzt.
  W := LowerCase(TDetectorUtils.ExtractFirstWord(ALine, WCol));
  // G4: Routinen-Tracking. Der Kopf bestimmt, in welchem Kontext
  // die folgenden Zuweisungen liegen.
  //
  // Klassenmethode ('class procedure TForm1.Setup;', auch class
  // function/constructor/destructor/operator; Review Woche G03-12): das
  // erste Wort ist 'class', der Kopf wurde frueher nicht erkannt - stand die
  // Klassenmethode direkt hinter FormCreate, blieb AktIstInit True, ihre
  // Aufrufe zaehlten als Init-Aufrufe, und die Captions einer so
  // 'gerufenen' Instanzmethode fielen still aus dem Bericht. Eine
  // Klassenmethode hat keine Instanz, also nie Init-Kontext.
  if W = 'class' then
  begin
    W2 := LowerCase(TDetectorUtils.ExtractFirstWord(
      Copy(ALine, WCol + Length(W), MaxInt), W2Col));
    if IstRoutinenKopf(W2) or (W2 = 'operator') then
    begin
      St.AktRoutine := KopfName(ALine,
        WCol + Length(W) + W2Col - 2 + Length(W2));
      St.AktIstInit := False;
    end;
  end
  else if IstRoutinenKopf(W) then
  begin
    St.AktRoutine := KopfName(ALine, WCol - 1 + Length(W));
    St.AktIstInit := IstInitRoutine(W, St.AktRoutine, AInitHandler);
    if St.AktIstInit and (St.AktRoutine <> '') then
      St.InitNamen.Add(St.AktRoutine);
    // faellt durch: die resourcestring-Blockende-Logik (BeendetResBlock)
    // kennt 'procedure'/'function' ebenfalls.
  end
  else if St.AktIstInit then
    SammleAufrufe(LowerCase(ALine), St.InitCalls);
  if W = 'resourcestring' then
  begin
    St.InResBlock := True;
    // Einzeiler 'resourcestring SFoo = ...' (vorher matchte nur die
    // alleinstehende Zeile): den Rest der Zeile gleich einsammeln.
    SammleResIdent(TrimLeft(Copy(ALine, WCol + Length('resourcestring'),
      MaxInt)), AResIdents);
    Exit;
  end;
  if St.InResBlock and not BeendetResBlock(W) then
  begin
    SammleResIdent(ALine, AResIdents);
    Exit;
  end;
  // Ein Abschnittswechsel beendet den Block - wortgenau (s.o.) - und
  // die Zeile selbst kann noch eine Zuweisung tragen; ausserhalb eines
  // Blocks ist das Zuruecksetzen ein No-op.
  St.InResBlock := False;
  VerarbeiteZuweisung(ALine, St.AktRoutine, St.ZuwJeRout, AZuweisungen);
end;

// noinspection LongParamList - interner Ein-Aufrufer-Helfer, der die
// EINE .pas-Lektuere auf vier Gates verteilt (G2/G3/G4/Res). Ein
// Parameter-Record fuer genau einen Aufrufer verdoppelte nur die
// Deklarationen; die sechs Parameter SIND der Vertrag der Funktion.
procedure LadeNachbarPas(const ADfmFile: string;
  AInitHandler: TStrings; out ARegime: Boolean;
  AResIdents: TStringList; AZuweisungen: TStringList;
  AUeberschrieben: TStringList);
// Liest die Nachbar-.pas der DFM EINMAL je Datei: Uebersetzungs-Regime-
// Marker (G3), resourcestring-Identmenge und die 'Comp.Prop := Ident;'-
// Zuweisungen (G2, als 'comp.prop=ident'-Zeilen in AZuweisungen).
// Suche auf gestripptem Text - Kommentare/Strings zaehlen nie.
//
// G4 INIT-UEBERSCHREIB-GATE (2026-09-16, vermessen an beiden Korpora):
// AUeberschrieben bekommt die 'comp.prop'-Schluessel, deren Property
// die Unit in einem INIT-KontEXT zuweist - dann ist der DFM-Wert ein
// toter Designer-Platzhalter, der den Nutzer nie erreicht.
//
// Init-Kontext heisst: constructor, FormCreate, FormShow, Loaded,
// AfterConstruction, die im DFM an der WURZEL gebundenen OnCreate-/
// OnShow-Handler (AInitHandler, aus dem Graph), oder eine Routine, die
// aus so einem Kontext heraus GERUFEN wird (EINE Stufe -
// LoadLocale-/SetLabels-Muster). BEWUSST NICHT jede Zuweisung: die
// grosszuegige Variante hatte in der Handpruefung 56 % Fehlskips
// (14 von 25) - eine Zuweisung im Event-Handler oder if-Zweig heisst,
// der DFM-Text ist der korrekte GRUNDZUSTAND bis zum Ereignis
// (btnTest 'Run' -> 'Stop' erst beim Klick). Die Init-Variante hatte
// 1 Fehlskip von 11.
//
// Der eine Restfehler war die RHS-SELBSTREFERENZ
// ('Caption := Format(Caption, ...)' - der DFM-Wert ist das Template
// und erreicht den Nutzer als Textbasis doch, 33 Faelle im
// Delphi-Korpus): solche Zuweisungen skippen nicht.
//
// Der LHS-Vertrag (genau EIN Punkt, valide Idents) schliesst
// Fremdklassen-Zuweisungen ('Frame.edPath.Text := ...') von selbst
// aus - die belegte False-Drop-Klasse der Qualifier-Variante.
var
  PasFile : string;
  Lines   : TStringList;
  Cached  : Boolean;
  LineFor : TArray<Integer>;
  Code, S : string;
  Zeile   : string;                 // die getrimmte Zeile
  St      : TPasLektuere;
begin
  ARegime := False;
  // Lazarus A4: die Schwester-Unit einer .lfm kann eine .pp sein
  // (149 der 1.010 Lazarus-.lfm). PairedUnitFile prueft Existenz;
  // '' heisst: kein Regime-Gate moeglich, wie bisher bei fehlender .pas.
  PasFile := TStaticFiles.PairedUnitFile(ADfmFile);
  if PasFile = '' then Exit;
  Lines := AcquireLines(PasFile, Cached);
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
  finally
    // ReleaseLines statt 'if not Cached then Free': seit dem Nutzerzaehler
    // des Text-Caches (2026-10-14) ist die Rueckgabe geliehener Zeilen
    // Pflicht, sonst bleibt der Eintrag bis zum Prozessende stehen.
    ReleaseLines(Lines, Cached);
  end;
  ARegime := HatRegimeMarker(LowerCase(Code));
  St := Default(TPasLektuere);   // kein Block, vor der ersten Routine
  St.InitNamen := TStringList.Create;
  St.InitCalls := TStringList.Create;
  St.ZuwJeRout := TStringList.Create;
  try
    St.InitNamen.Sorted := True; St.InitNamen.Duplicates := dupIgnore;
    St.InitNamen.CaseSensitive := False;
    St.InitCalls.Sorted := True; St.InitCalls.Duplicates := dupIgnore;
    St.InitCalls.CaseSensitive := False;
    for S in Code.Split([#10]) do
    begin
      Zeile := Trim(S);
      if Zeile = '' then Continue;
      VerarbeiteZeile(Zeile, AInitHandler, St, AResIdents, AZuweisungen);
    end;
    LoeseInitZuweisungen(St.ZuwJeRout, St.InitNamen, St.InitCalls,
      AUeberschrieben);
  finally
    St.ZuwJeRout.Free;
    St.InitCalls.Free;
    St.InitNamen.Free;
  end;
end;

type
  // Wissen aus der Nachbar-.pas (LadeNachbarPas) fuer die Gates G2-G4.
  // Die Listen gehoeren Analyze (angelegt und freigegeben dort); der
  // Record buendelt nur die Verweise, damit die Gate-Kette eine Funktion
  // mit vier Parametern bleibt.
  TNachbarWissen = record
    Regime         : Boolean;       // G3: Laufzeit-Uebersetzer in der Unit
    ResIdents      : TStringList;   // G2: resourcestring-Idents
    Zuweisungen    : TStringList;   // G2: 'comp.prop=ident'
    Ueberschrieben : TStringList;   // G4: 'comp.prop' aus Init-Kontext
  end;

// G4: die an der DFM-WURZEL gebundenen Create-/Show-Handler zaehlen
// als Init-Kontext - Lazarus bindet OnCreate oft an frei benannte
// Handler (CondFormCREATE-Klasse der Vermessung), die die
// Namensliste (FormCreate/...) nicht traefe.
procedure SammleInitHandler(Graph: TComponentGraph; AInitHandler: TStringList);
var
  N  : TComponentNode;
  Ev : string;
  V  : TPropValue;
begin
  for N in Graph.Roots do
    for Ev in ['OnCreate', 'OnShow'] do
      if N.TryGetProperty(Ev, V) and (V.Kind = pvkIdent)
         and (Trim(V.RawValue) <> '') then
        AInitHandler.Add(LowerCase(Trim(V.RawValue)));
end;

// True, wenn die Property P von N eine zu meldende Caption traegt: ein
// nicht-leerer String-Wert (V), den keines der Gates G1-G4 deckt. Die
// Pruefungen stehen in der Reihenfolge, in der sie zuvor in Analyze
// lagen - jede ist ein reiner Nachschlag ohne Nebenwirkung.
function MeldbareCaption(N: TComponentNode; const P: string;
  const AWissen: TNachbarWissen; out V: TPropValue): Boolean;
var
  FontV    : TPropValue;
  ZuwIdx   : Integer;
  RhsIdent : string;
begin
  Result := False;
  if not N.TryGetProperty(P, V) then Exit;
  if V.Kind <> pvkString          then Exit;
  if Trim(V.RawValue) = ''        then Exit;
  // Reine Symbol-/Ziffern-Captions ('-', '...', '123') sind nicht
  // lokalisierbar -> kein i18n-Smell.
  if IsNonTranslatable(Trim(V.RawValue)) then Exit;
  // G1 GLYPH: Ein-Zeichen-"Text" in einem Symbolfont ist ein Icon.
  if (Length(V.RawValue) = 1) and N.TryGetProperty('Font.Name', FontV)
     and (FontV.Kind = pvkString) and IsSymbolFont(FontV.RawValue) then
    Exit;
  // G2 RESOURCESTRING: die .pas ersetzt genau diese Property aus
  // einer resourcestring - der DFM-Wert ist ein toter Platzhalter.
  ZuwIdx := AWissen.Zuweisungen.IndexOfName(LowerCase(N.Name + '.' + P));
  if ZuwIdx >= 0 then
  begin
    RhsIdent := AWissen.Zuweisungen.ValueFromIndex[ZuwIdx];
    if AWissen.ResIdents.IndexOf(RhsIdent) >= 0 then Exit;
  end;
  // G3 UEBERSETZUNGS-REGIME: die Form uebersetzt ihre DFM-Texte
  // zur Laufzeit - der String IST die msgid-Quelle.
  if AWissen.Regime then Exit;
  // G4 INIT-UEBERSCHREIBEN: die Unit setzt genau diese Property
  // in einem Init-Kontext neu - der DFM-Wert erreicht den Nutzer
  // nie (Vertrag und Grenzen im Kommentar an LadeNachbarPas;
  // Delphi-Vermessung: 467 von 24.980, Fehlskip-Quote 1/11 in
  // der Handpruefung gegen 14/25 der grosszuegigen Variante).
  if AWissen.Ueberschrieben.IndexOf(LowerCase(N.Name + '.' + P)) >= 0 then
    Exit;
  Result := True;
end;

// G5 DESIGNER-DEFAULT (D3 2026-09-19, Nico-Entscheid "mach
// 1-4"): Caption ist EXAKT der Komponentenname ('Form1') oder
// der Klassenname mit/ohne fuehrendes T ('TButton'/'Button') -
// der Vorschlagswert des Designers, nie ein getexteter
// UI-String. Die Meldung waere nicht FALSCH (objektiv
// hardcodiert), aber fuer den i18n-Zweck der Regel ohne
// Nutzwert (rw76-Vollzaehlung: 1.838 von 24.980 = 7,4 %;
// rw114-Nachzaehlung der Namens-Klasse: 1.373 exakt).
// DEMOTE statt Skip: fcLow faellt unterm fcMedium-Default aus
// dem Lauf, --min-confidence low holt die Designer-Reste
// zurueck - wer unfertige UIs jagt, kann das gezielt.
function IstDesignerDefault(N: TComponentNode; const V: TPropValue): Boolean;
begin
  Result := SameText(V.RawValue, N.Name)
    or SameText(V.RawValue, N.ClassRef)
    or ((Length(N.ClassRef) > 1) and (N.ClassRef[1] = 'T')
        and SameText(V.RawValue, Copy(N.ClassRef, 2, MaxInt)));
end;

class procedure TDfmHardcodedCaptionDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All         : TList<TComponentNode>;
  N           : TComponentNode;
  V           : TPropValue;
  P           : string;
  F           : TLeakFinding;
  Wissen      : TNachbarWissen;
  InitHandler : TStringList;
begin
  if Graph = nil then Exit;

  // Regime kommt erst aus LadeNachbarPas; Default() haelt den Record auch
  // dann definiert, wenn ein spaeterer Ausstieg vor dem Aufruf liegt.
  Wissen := Default(TNachbarWissen);
  Wissen.ResIdents      := TStringList.Create;
  Wissen.Zuweisungen    := TStringList.Create;
  Wissen.Ueberschrieben := TStringList.Create;
  InitHandler := TStringList.Create;
  All := Graph.EnumerateAll;
  try
    Wissen.ResIdents.CaseSensitive := False;
    Wissen.ResIdents.Sorted := True;
    Wissen.ResIdents.Duplicates := dupIgnore;
    Wissen.Zuweisungen.CaseSensitive := False;
    Wissen.Ueberschrieben.CaseSensitive := False;
    Wissen.Ueberschrieben.Sorted := True;
    Wissen.Ueberschrieben.Duplicates := dupIgnore;
    InitHandler.CaseSensitive := False;
    InitHandler.Sorted := True;
    InitHandler.Duplicates := dupIgnore;
    SammleInitHandler(Graph, InitHandler);
    LadeNachbarPas(FileName, InitHandler, Wissen.Regime, Wissen.ResIdents,
      Wissen.Zuweisungen, Wissen.Ueberschrieben);

    for N in All do
    begin
      for P in CAPTION_PROPS do
      begin
        if not MeldbareCaption(N, P, Wissen, V) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(V.Line);
        F.MissingVar := Format('%s.%s = ''%s''', [N.Name, P, V.RawValue]);
        F.SetKind(fkDfmHardcodedCaption);
        if IstDesignerDefault(N, V) then
          F.Confidence := fcLow;
        Results.Add(F);
      end;
    end;
  finally
    All.Free;
    InitHandler.Free;
    Wissen.Ueberschrieben.Free;
    Wissen.Zuweisungen.Free;
    Wissen.ResIdents.Free;
  end;
end;

end.
