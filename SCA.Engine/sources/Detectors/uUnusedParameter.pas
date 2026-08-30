unit uUnusedParameter;

// Detector: Method-Parameter, der im Body nirgendwo referenziert wird.
//
// Skip-Regeln (sonst zu viel Rauschen):
//   * Methode ist `override`/`virtual`/`abstract` -> Signature-Konformitaet
//     wichtig, Param-Existenz kann von Basisklasse vorgegeben sein.
//   * Methode hat genau einen `Sender: TObject`-Param (Event-Handler-Pattern).
//   * Body enthaelt bare `inherited;` oder klammerloses `inherited Foo;` ->
//     Delphi reicht die aktuellen Parameter implizit an die Elternmethode weiter
//     (Signatur vom Parent vorgegeben, Param nicht wirklich ungenutzt).
//   * Param-Name beginnt mit `_` (intentional convention).
//   * Body ist asm-Block oder leer.
//
// KORREKTHEITS-GATES aus der SCA054-Autopsie 2026-08-27 (13.959 Funde). Alle
// vier nehmen Meldungen weg, die sachlich FALSCH sind - nicht bloss
// unerwuenscht. Gezaehlt auf dem Autopsie-Korpus:
//   * GATE A `message`-Handler (-1.019): 'procedure WMFoo(var M: TMsg);
//     message WM_FOO;' MUSS in Delphi genau einen var-Parameter tragen
//     (E2190). Der Parameter ist Teil des Vertrags, streichen bricht die
//     Uebersetzung. Siehe DeclHasMessageDirective - der alte Kommentar an
//     IsInheritanceHook, das brauche einen Parser-Followup, war nur fuer
//     HasModifier richtig (der Parser kennt 'message' nicht als Direktive
//     und legt sie als zwei Phantom-Felder ab); ueber den Deklarations-
//     SCHWANZ in der gestrippten Quelle ist der Fall entscheidbar.
//   * GATE B 'absolute'-Alias (-414): 'var X: T absolute Param;' legt X auf
//     die Storage von Param. Jeder Zugriff ueber X IST ein Zugriff auf
//     Param - 'never read in method body' ist dort schlicht unwahr.
//     Hausvorlage: uUninitVar.pas (AbsAliases).
//   * GATE C FPC-Marker '{%H-}' am Parameter (-29): expliziter Autor-Intent
//     ('Hint hier unterdruecken'). SCA166/uUninitVar respektiert denselben
//     Marker an Deklarationen; hier gilt dieselbe Zusage.
//   * GATE F 'constref'-Phantom (-48): 'constref' ist ein FPC-Parameter-
//     modifier, den der Parser nicht kennt - er landet als eigener nkParam
//     mit leerem Typ. Gemeldet wird also ein Parameter, der gar keiner ist.
//
// BEKANNTER REST (nicht behoben, damit er nicht verloren geht): 78 Funde
// (0,56 % der Autopsie) behaupten 'never read', obwohl der Parametername
// im ECHTEN Rumpf wortgebunden dasteht. Weder die AST-Zaehlung noch die
// Quell-Rueckfrage sehen ihn - eine offene, echte FP-Klasse mit noch
// unbekannter Ursache (Verdacht: Rumpf-Zeilenbereich BodyFrom..BodyTo zu
// eng, s. BodyLineRangeFound). Eigenes Paket, eigene Messung.
//
// Erkennung:
//   * MethodNode.FindAll(nkParam) → Liste der Param-Knoten
//   * Body-Tokens einsammeln (rekursiv Name+TypeRef aller Children)
//   * Pro Param: zaehle case-insensitive Wortgrenzen-Vorkommen im Body
//   * Wenn 0 -> Finding
//
// Severity: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils, uFileTextCache;

type
  // Gestrippte Quelle EINER Datei, ueber alle Methoden hinweg geteilt.
  // Ready wird gesetzt, sobald der Versuch gelaufen ist - auch wenn er
  // scheiterte, damit eine unlesbare Datei nicht je Methode erneut
  // geoeffnet wird.
  TStrippedUnit = record
    Ready : Boolean;
    Lines : TArray<string>;
    // ROHE Quellzeilen, zeilengleich zu Lines indiziert. Gebraucht von
    // GATE C: '{%H-}' IST ein Kommentar und ist in Lines weggeblankt - die
    // Autor-Suppression waere dort unsichtbar. Der Zusatz kostet praktisch
    // nichts: Delphi-Strings sind refgezaehlt, kopiert werden nur Zeiger.
    Raw   : TArray<string>;
  end;

  TUnusedParameterDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(UnitNode, MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      var AStripped: TStrippedUnit);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, GroupedDeclaration, NestedRoutine, NestedTry, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions;   // GATE E - Prozedurwert-Muster

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

// Modifier-Check via TypeRef-Format aus Parser (siehe 🅳-Fix):
//   'kind[:ret];dir1;dir2'
function HasModifier(MethodNode: TAstNode; const Dir: string): Boolean;
begin
  Result := Pos(';' + LowerCase(Dir), LowerCase(MethodNode.TypeRef)) > 0;
end;

// Methodennamen `TFoo.Bar` -> Klasse `TFoo`, MethodenName `Bar`.
//
// Bis 2026-07-27 wurde am ERSTEN Punkt getrennt. Bei nested types
// ('TOuter.TInner.PaintBackground') ergab das Klasse='TOuter' und Name=
// 'TInner.PaintBackground'; FindDeclaration suchte danach in der AEUSSEREN
// Klasse nach einer woertlich so heissenden Methode und fand nie etwas. Der
// override/virtual-Skip in IsInheritanceHook lief damit ins Leere - still,
// ohne Fehler. Sauberer A/B-Beleg im selben File (Vcl.Styles.Utils.ComCtrls):
// die Methode mit zwei Qualifizierern wurde gemeldet, die daneben liegende
// mit einem und identisch leerem Rumpf nicht.
function SplitQualified(const MethodName: string;
  out ClassName, BareName: string): Boolean;
begin
  ClassName := TDetectorUtils.OwnerTypeName(MethodName);
  BareName  := TDetectorUtils.UnqualifiedNameLast(MethodName);
  Result    := ClassName <> '';
end;

// Sucht im Unit-Tree die Class-Declaration, die zu einer Implementation
// gehoert. Liefert deren nkMethod-Knoten (die HAT die Modifier in TypeRef)
// oder nil.
function FindDeclaration(UnitNode: TAstNode; const ClassName,
  BareName: string): TAstNode;
var
  Classes : TList<TAstNode>;
  Cls : TAstNode;
  Methods : TList<TAstNode>;
  M : TAstNode;
  LowClassWanted, LowBareWanted : string;
begin
  Result := nil;
  if (UnitNode = nil) or (ClassName = '') then Exit;
  LowClassWanted := LowerCase(ClassName);
  LowBareWanted  := LowerCase(BareName);
  Classes := UnitNode.FindAll(nkClass);
  try
    for Cls in Classes do
    begin
      if LowerCase(Cls.Name) <> LowClassWanted then Continue;
      Methods := Cls.FindAll(nkMethod);
      try
        for M in Methods do
          if LowerCase(M.Name) = LowBareWanted then
            Exit(M);
      finally
        Methods.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

// Deklarationsknoten zu einer Implementation - oder nil.
//
// 2026-08-27 aus IsInheritanceHook herausgezogen: seit GATE A gibt es einen
// ZWEITEN Leser derselben Deklaration. FindDeclaration laeuft ueber
// UnitNode.FindAll(nkClass), also ueber den ganzen Datei-Baum mit
// Listen-Allokation - ihn zweimal je Methode zu bezahlen waere Verschwendung.
// AnalyzeMethod holt ihn einmal und reicht ihn durch.
function FindDeclarationFor(UnitNode, MethodNode: TAstNode): TAstNode;
var
  ClassName, BareName : string;
begin
  Result := nil;
  if SplitQualified(MethodNode.Name, ClassName, BareName) then
    Result := FindDeclaration(UnitNode, ClassName, BareName);
end;

// T2 (2026-07-29): Besitzertyp einer nested-type-Methode im Unit-Baum
// finden (nkClass ODER nkRecord - nested records mit Methoden existieren).
// Liefert False, wenn KEIN Typknoten mit dem Besitzernamen existiert -
// oder MEHRERE (Review 2026-07-29): nested types existieren gerade,
// damit Namen wiederverwendbar sind; ein Top-Level-Homonym wuerde den
// echten Besitzer shadowen und den Interface-Skip fehlleiten (FP auf
// compiler-erzwungenen Delegate-Parametern). Ambiguitaet -> defensiv
// False, der Aufrufer schweigt dann wie beim Nicht-Finden.
function TryFindOwnerType(UnitNode: TAstNode; const MethName: string;
  out OwnerCls: TAstNode): Boolean;
var
  OwnerLow : string;
  Kind     : TNodeKind;
  L        : TList<TAstNode>;
  C        : TAstNode;
begin
  Result   := False;
  OwnerCls := nil;
  OwnerLow := TDetectorUtils.OwnerTypeNameLower(MethName);
  if OwnerLow = '' then Exit;
  for Kind in [nkClass, nkRecord] do
  begin
    L := UnitNode.FindAllRef(Kind);
    for C in L do
      if LowerCase(C.Name) = OwnerLow then
      begin
        if OwnerCls <> nil then
        begin
          OwnerCls := nil;          // Homonym - nicht entscheidbar
          Exit(False);
        end;
        OwnerCls := C;
      end;
  end;
  Result := OwnerCls <> nil;
end;

// True wenn die class(...)-Liste des Knotens Interfaces traegt.
// ParseClassBody legt die Eltern space-getrennt in TypeRef ab (gepunktete
// Namen bleiben EIN Eintrag; Generic-Argumente werden seit T2b
// balanciert uebersprungen - 'class(TObjectList<TItem>)' ist wieder EIN
// Eintrag 'TObjectList', die fruehere Generics-FN-Restklasse aus
// Review 2026-07-29 ist damit geschlossen). VERBLIEBENE UNSCHAERFE
// (bewusste FN-Restklasse): IFDEF-Twins emittieren beide Zweige
// ('TX TY') und werden hier faelschlich als Basis+Interface gelesen
// -> Skip (kein Fund). Nur-FN-Richtung, nie FP; Twin-Adoption ist ein
// T3-Backlog-Posten (Twin-Kopf mergen statt skippen). Gleiches gilt fuer
// die I-Gross-Konvention beim Ein-Eintrag-Fall (IPCServer/IOThread
// waeren falsch-positiv fuer den SKIP, also ebenfalls nur-FN). Zusaetzlich der
// Ein-Eintrag-Fall 'class(IFoo)' (implizite TObject-Basis): dort
// entscheidet die I-Grossbuchstabe-Konvention - 'IdFtp...' (Indy) faellt
// durch das Kleinbuchstaben-d nicht darauf herein.
function OwnerHasInterfaceParents(OwnerCls: TAstNode): Boolean;
var
  P : string;
begin
  Result := False;
  if OwnerCls = nil then Exit;
  P := Trim(OwnerCls.TypeRef);
  if P = '' then Exit;
  if Pos(' ', P) > 0 then Exit(True);      // Basis + mind. ein Interface
  // Einziger Eintrag: Interface nach Namenskonvention I<Gross>?
  // Unit-Qualifizierer abstreifen (System.IInterface -> IInterface).
  P := TDetectorUtils.UnqualifiedNameLast(P);
  Result := (Length(P) >= 2) and (P[1] = 'I') and
            CharInSet(P[2], ['A'..'Z']);
end;

// True wenn der Rumpf AUSSCHLIESSLICH aus einem `raise` besteht
// ('raise ENotImplemented.Create(...)', 'raise ENotSupportedException...').
//
// 30%-Real-World-Audit 2026-07-31: solche Ruempfe koennen ihre Parameter
// gar nicht lesen - die Signatur stammt von aussen (Interface, Vorfahr,
// Framework-Vertrag), der Rumpf ist bewusst leer. 'Unused parameter' ist
// dort nicht behebbar: den Parameter zu streichen bricht die Signatur.
// Korpus-Messung after126: 1.021 der 19.402 Funde (5,3 %).
function BodyIsRaiseOnly(MethodNode: TAstNode): Boolean;
var
  Blk, Ch : TAstNode;
  Cnt     : Integer;
begin
  Result := False;
  Blk := nil;
  for Ch in MethodNode.Children do
    if Ch.Kind = nkBlock then
    begin
      Blk := Ch;
      Break;
    end;
  if Blk = nil then Exit;
  Cnt := 0;
  for Ch in Blk.Children do
  begin
    Inc(Cnt);
    if Cnt > 1 then Exit;
    if Ch.Kind <> nkRaise then Exit;
  end;
  Result := Cnt = 1;
end;

// Inheritance-Hook-Check: an der Implementation selbst (selten) ODER an
// ihrer zugehoerigen Class-Declaration (Default-Fall - Parser legt die
// Modifier nur an der Declaration ab). ADecl kommt aus FindDeclarationFor
// und darf nil sein.
function IsInheritanceHook(MethodNode, ADecl: TAstNode): Boolean;

  function CheckOne(N: TAstNode): Boolean;
  begin
    // 'message' steht hier bewusst NICHT: der Parser kennt sie nicht als
    // Direktive (IsMethodDirective/IsMethodDirectiveIdent fuehren sie nicht),
    // sie erreicht TypeRef nie und HasModifier(N, 'message') ist konstant
    // False. Der Fall wird stattdessen aus dem Deklarations-SCHWANZ der
    // Quelle entschieden - s. DeclHasMessageDirective (GATE A). Die
    // Vorfassung dieses Kommentars behauptete, das brauche einen
    // Parser-Followup; das stimmte nur fuer den HasModifier-Weg.
    Result := (N <> nil) and
              (HasModifier(N, 'override')
            or HasModifier(N, 'virtual')
            or HasModifier(N, 'abstract')
            or HasModifier(N, 'dynamic'));
  end;

begin
  Result := CheckOne(MethodNode) or CheckOne(ADecl);
end;

// Event-Handler-Konvention: der ERSTE Parameter ist 'Sender' (bzw. *Sender)
// oder vom Typ TObject. Solche Methoden bindet der Form-Designer per DFM an
// Component-Events; ihre Signatur ist durch den Event-Typ vorgegeben, daher
// sind ungenutzte Parameter unvermeidbar (kein Finding).
//
// Erfasst BEWUSST auch Multi-Param-Handler (OnKeyPress(Sender; var Key),
// OnDrawCell(Sender; ACol, ARow, Rect, State), OnFilter(Sender; Item; Accept)).
// Frueher nur Single-`Sender` -> FP bei jedem Mehr-Param-Handler mit einem
// ungenutzten Pflicht-Param (Real-World 2026-06-28: dominante SCA054-FP-Klasse).
function IsLikelyEventHandler(MethodNode: TAstNode): Boolean;
var
  Params : TList<TAstNode>;
  LowName, LowType : string;
begin
  Result := False;
  Params := MethodNode.FindAll(nkParam);
  try
    if Params.Count = 0 then Exit;
    LowName := LowerCase(Trim(Params[0].Name));   // Modifier-Prefix stoert EndsWith nicht
    LowType := LowerCase(Params[0].TypeRef);
    Result := (LowName = 'sender') or LowName.EndsWith('sender')
              or (Pos('tobject', LowType) > 0);
  finally
    Params.Free;
  end;
end;

// True, wenn der Body ein parameter-implizit-weiterreichendes 'inherited'
// enthaelt. Delphi reicht die AKTUELLEN Methodenparameter automatisch an die
// Elternmethode weiter bei
//   * bare  'inherited;'      -> Parser: nkInherited mit LEEREM Name
//   * klammerlos 'inherited Foo;' -> nkInherited.Name = 'Foo' (kein '(')
// In beiden Formen ist ein "ungenutzter" Parameter in Wahrheit weitergeleitet
// (Signatur vom Parent vorgegeben) -> KEIN echter unused-Param. Nur
// 'inherited Foo(args)' (Name enthaelt '(') reicht NICHT implizit weiter, dort
// kann ein Param genuin ungenutzt sein -> nicht skippen.
// Wichtig: der Parser konsumiert das Keyword 'inherited' und speichert nur den
// Call-Ausdruck als Name; ein Text-Scan nach "inherited" wuerde daher genau den
// dominanten bare-Fall (leerer Name) verfehlen -> Erkennung MUSS ueber den
// nkInherited-Knotentyp laufen. (Core-Audit 2026-07-18, Welle 1 5%-FP-Konzept:
// ~7.950 FP, groesste absolute FP-Klasse, monoton + TP-safe.)
function ForwardsParamsViaInherited(MethodNode: TAstNode): Boolean;
var
  Inh : TList<TAstNode>;
  N : TAstNode;
begin
  Result := False;
  Inh := MethodNode.FindAll(nkInherited);
  try
    for N in Inh do
      if Pos('(', N.Name) = 0 then   // '' (bare) oder 'Name' ohne Klammern
        Exit(True);
  finally
    Inh.Free;
  end;
end;

procedure EnsureUnitStripped(var AStripped: TStrippedUnit;
  const AFileName: string);
// Einmal je DATEI, nicht je Methode - das ist der ganze Gewinn dieser
// Funktion: das Zeilen-Split lief frueher je METHODE ueber die ganze
// Datei.
//
// Der Strip selbst ist hier UNGECACHT: beide Aufrufe unten uebergeben
// AContext=nil, und bei nil rechnet StripStringsAndCommentsCached immer
// direkt (die Detektor-API dieser Unit fuehrt gar keinen Context). Die
// Vorfassung dieses Kommentars behauptete "ohnehin gecacht" - wer ihr
// glaubte, suchte Performance-Probleme an der falschen Stelle (G4-3).
// Den Context durchzureichen waere ein API-Umbau ueber AnalyzeUnit und
// AnalyzeMethod; er lohnt erst, wenn eine Messung diesen Strip als
// heiss ausweist.
var
  Code    : string;
  LineFor : TArray<Integer>;
  Src     : TStringList;
  Owned   : Boolean;
  i       : Integer;
begin
  if AStripped.Ready then Exit;
  AStripped.Ready := True;
  Src := AcquireLines(AFileName, Owned, nil);
  if Src = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Src, LineFor, nil, AFileName, ' ');
    AStripped.Lines := Code.Split([#10]);
    // Rohzeilen fuer GATE C mitnehmen (s. TStrippedUnit.Raw). Der Cache
    // besitzt Src; die Kopie hier haelt nur Referenzen auf dieselben
    // String-Puffer, es wird kein Zeichen dupliziert.
    SetLength(AStripped.Raw, Src.Count);
    for i := 0 to Src.Count - 1 do
      AStripped.Raw[i] := Src[i];
  finally
    ReleaseLines(Src, Owned);
  end;
end;

// ---------------------------------------------------------------------------
// GATE A - 'message'-Handler (SCA054-Autopsie 2026-08-27, -1.019 Funde)
// ---------------------------------------------------------------------------

function IsIdentStartChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsDeclTailDirective(const AWordLow: string): Boolean;
// Woerter, die im Direktiven-Schwanz einer Methoden-Deklaration VOR einem
// 'message' stehen duerfen. Die Liste ist bewusst eine ERLAUBNIS, keine
// Verbotsliste: alles, was hier nicht steht, beendet den Schwanz und damit
// die Suche - so kann das Fenster nie in eine folgende Deklaration
// hineinlesen (dort steht immer procedure/function/property/end).
const
  TAIL_DIRECTIVES : array[0..33] of string = (
    'abstract',    'assembler',   'cdecl',      'dcpcall',   'delphicall',
    'deprecated',  'dispid',      'dynamic',    'experimental', 'export',
    'external',    'far',         'final',      'forward',   'inline',
    'library',     'local',       'mwpascal',   'near',      'noreturn',
    'overload',    'override',    'pascal',     'platform',  'register',
    'reintroduce', 'safecall',    'sealed',     'static',    'stdcall',
    'unsafe',      'varargs',     'virtual',    'winapi');
var
  i : Integer;
begin
  for i := Low(TAIL_DIRECTIVES) to High(TAIL_DIRECTIVES) do
    if AWordLow = TAIL_DIRECTIVES[i] then Exit(True);
  Result := False;
end;

// GEGENPRUEFUNG 2026-08-27, bewusst nicht zusammengelegt: eine
// Zweitfassung derselben Frage steht als Sca147DeclHasMessageDirective
// in uUnusedPrivateMethod.pas:292. Sie arbeitet auf dem STRING 'Code'
// mit Startoffset, diese hier auf dem ZEILEN-Array mit Deklarations-
// zeile - eine Vereinigung braucht eine gemeinsame Signatur und
// beruehrt dann zwei Detektoren gleichzeitig. Das ist die teurere
// Aenderung; wer sie angeht, sollte beide Direktiven-Erlaubnislisten
// mitnehmen, die heute schon auseinanderlaufen.
// BEKANNTE REICHWEITE (gezaehlt): Gate C sieht nur den Implementierungs-
// kopf; 354 der 424 Korpus-Marker '{%H-}' stehen an der DEKLARATION und
// werden damit nicht erreicht. Das ist eine Luecke, kein Fehler - die
// erreichten 29 sind korrekt unterdrueckt.
function DeclHasMessageDirective(const ALines: TArray<string>;
  AFirstLine: Integer): Boolean;
// True, wenn die Deklaration ab AFirstLine die Direktive 'message <Arg>'
// traegt.
//
// WARUM AUS DER QUELLE UND NICHT AUS DEM AST: der Parser fuehrt 'message'
// nicht in IsMethodDirectiveIdent. ParseMethodDirectives bricht davor ab,
// und der Klassenrumpf-Loop verdaut 'message' und die Konstante als ZWEI
// Phantom-Felder. Im TypeRef steht davon nichts - HasModifier kann den Fall
// prinzipiell nicht sehen.
//
// GELESEN WIRD DIE GESTRIPPTE QUELLE: ein 'message' in einem Kommentar oder
// String zaehlt nicht (durchgaengige Zusage des Werkzeugs).
//
// Ablauf in zwei Phasen, damit kein Bezeichner aus der Signatur mitzaehlt:
//   Phase 1 laeuft bis zum ';', das die Signatur schliesst. Die Semikolons
//     der Parameterliste liegen auf Klammertiefe > 0 und zaehlen nicht.
//   Phase 2 liest den Direktiven-Schwanz Wort fuer Wort. 'message' mit
//     folgendem Argument -> True; ein bekanntes Direktivenwort -> weiter
//     hinter dessen ';'; alles andere -> Ende, False.
//
// Das Fenster ist auf MAX_DECL_LINES begrenzt: eine laengere Parameterliste
// liefert False, also hoechstens einen verbleibenden Fund (nie einen neuen).
const
  MAX_DECL_LINES = 6;
var
  Buf  : string;
  W    : string;
  Ch   : Char;
  i, p, e, q, L, Depth : Integer;
begin
  Result := False;
  if (AFirstLine < 1) or (AFirstLine > Length(ALines)) then Exit;
  Buf := '';
  for i := AFirstLine to AFirstLine + MAX_DECL_LINES - 1 do
  begin
    if i > Length(ALines) then Break;
    // Trenner-Space: sonst klebte das letzte Wort einer Zeile an das erste
    // der naechsten und der Wortvergleich unten liefe ins Leere.
    Buf := Buf + ' ' + LowerCase(ALines[i - 1]);
  end;
  L := Length(Buf);

  Depth := 0;
  p     := 1;
  while p <= L do
  begin
    Ch := Buf[p];
    if (Ch = '(') or (Ch = '[') then Inc(Depth)
    else if (Ch = ')') or (Ch = ']') then Dec(Depth)
    else if (Ch = ';') and (Depth <= 0) then Break;
    Inc(p);
  end;
  if p > L then Exit;
  Inc(p);                        // hinter das Signatur-';'

  while True do
  begin
    while (p <= L) and (Buf[p] <= ' ') do Inc(p);
    if p > L then Exit;
    if not IsIdentStartChar(Buf[p]) then Exit;
    e := p;
    while (e <= L) and IsIdentChar(Buf[e]) do Inc(e);
    W := Copy(Buf, p, e - p);
    if W = 'message' then
    begin
      // 'message' OHNE Argument gibt es nicht - ohne diese Pruefung wuerde
      // ein Feld namens 'Message' hinter der Signatur den Gate ausloesen.
      q := e;
      while (q <= L) and (Buf[q] <= ' ') do Inc(q);
      Result := (q <= L) and
                (IsIdentStartChar(Buf[q]) or CharInSet(Buf[q], ['0'..'9']));
      Exit;
    end;
    if not IsDeclTailDirective(W) then Exit;
    p     := e;
    Depth := 0;
    while p <= L do
    begin
      Ch := Buf[p];
      if (Ch = '(') or (Ch = '[') then Inc(Depth)
      else if (Ch = ')') or (Ch = ']') then Dec(Depth)
      else if (Ch = ';') and (Depth <= 0) then Break;
      Inc(p);
    end;
    if p > L then Exit;
    Inc(p);
  end;
end;

function IsMessageHandler(ADecl: TAstNode; AParams: TList<TAstNode>;
  var AStripped: TStrippedUnit; const AFileName: string): Boolean;
// Message-Handler: der Parameter ist compiler-erzwungen, 'unused' ist dort
// nicht behebbar (Streichen ergibt E2190 'Message methods must have exactly
// one var parameter').
//
// Der Signatur-Vorfilter ist zugleich der Perf-Schutz und der Waechter gegen
// eine Fehl-Lesung der Quelle: nur bei GENAU EINEM var-Parameter - also der
// vom Compiler erzwungenen Form - wird ueberhaupt in die Datei geschaut.
// Ein Parser- oder Textfehler kann so hoechstens eine einparametrige
// Methode stumm schalten, nie eine beliebige.
//
// GEERBTE UNSCHAERFE: FindDeclaration nimmt bei gleichnamigen Overloads die
// ERSTE Deklaration - dieselbe Grenze, die IsInheritanceHook seit jeher hat.
// Praktisch folgenlos: ein Message-Handler hat eine feste Signatur und wird
// nicht ueberladen, und der Ein-var-Parameter-Vorfilter deckelt den Schaden.
var
  P0 : string;
begin
  Result := False;
  if ADecl = nil then Exit;
  if AParams.Count <> 1 then Exit;
  // Der Parser legt den Modifier als Namens-Praefix ab ('var Msg').
  P0 := LowerCase(Trim(AParams[0].Name));
  if Copy(P0, 1, 4) <> 'var ' then Exit;
  EnsureUnitStripped(AStripped, AFileName);
  if Length(AStripped.Lines) = 0 then Exit;
  Result := DeclHasMessageDirective(AStripped.Lines, ADecl.Line);
end;

// ---------------------------------------------------------------------------
// GATE B - 'absolute'-Alias auf einen Parameter (-414 Funde)
// ---------------------------------------------------------------------------

function CollectAbsoluteAliasTargets(MethodNode: TAstNode;
  var AStripped: TStrippedUnit; const AFileName: string): string;
// Liefert die Ziel-Bezeichner aller 'absolute'-Aliase der lokalen
// var-Sektion, kleingeschrieben und in ' a b '-Form (Lookup per
// Pos(' name ', ...) - kein Container, keine Freigabe).
//
// 'var P: Byte absolute Buf;' macht P zum zweiten Namen fuer die Storage von
// Buf. Jeder Zugriff ueber P ist ein Zugriff auf Buf; 'never read in method
// body' ist dort sachlich falsch. Hausvorlage: uUninitVar.pas (AbsAliases)
// behandelt denselben Fall auf der Init-Seite.
//
// WARUM DIE ZAEHLUNG DAS NICHT SCHON SIEHT: ParseLocalVarSection konkateniert
// den Typ-Schwanz OHNE Trenner ('Byte'+'absolute'+'Buf' -> 'ByteabsoluteBuf').
// Im AST-Flachtext steht 'buf' damit mitten in einem Wort und faellt durch
// die Wortgrenzen-Pruefung. Die Quell-Rueckfrage greift auch nicht: sie
// beginnt erst am 'begin', die var-Sektion liegt davor.
//
// Entschieden wird auf der GESTRIPPTEN QUELLZEILE, nicht auf dem TypeRef:
// im konkatenierten TypeRef gaebe es keine Wortgrenzen mehr, und ein Typ
// namens 'TAbsolutePos' waere von einem echten 'absolute' nicht zu
// unterscheiden.
var
  Ch       : TAstNode;
  L        : string;
  p, e, LL : Integer;
begin
  Result := '';
  for Ch in MethodNode.Children do
  begin
    if Ch.Kind <> nkLocalVar then Continue;
    if Pos('absolute', LowerCase(Ch.TypeRef)) = 0 then Continue;
    EnsureUnitStripped(AStripped, AFileName);
    if (Ch.Line < 1) or (Ch.Line > Length(AStripped.Lines)) then Continue;
    L  := LowerCase(AStripped.Lines[Ch.Line - 1]);
    LL := Length(L);
    p  := Pos('absolute', L);
    while p > 0 do
    begin
      if ((p = 1) or not IsIdentChar(L[p - 1])) and
         ((p + 8 > LL) or not IsIdentChar(L[p + 8])) then
      begin
        e := p + 8;
        while (e <= LL) and (L[e] <= ' ') do Inc(e);
        p := e;
        while (e <= LL) and IsIdentChar(L[e]) do Inc(e);
        if e > p then
          Result := Result + ' ' + Copy(L, p, e - p);
        Break;                       // ein Alias je Deklarationszeile
      end;
      p := Pos('absolute', L, p + 1);
    end;
  end;
  if Result <> '' then Result := Result + ' ';
end;

// ---------------------------------------------------------------------------
// GATE C - FPC-Suppressionsmarker '{%H-}' am Parameter (-29 Funde)
// ---------------------------------------------------------------------------

function HeaderLastLine(const ALines: TArray<string>;
  AFirstLine: Integer): Integer;
// Letzte Zeile des Methodenkopfes: ab AFirstLine Klammern bilanzieren, bis
// die Parameterliste wieder geschlossen ist. Gebraucht, weil der Parser ALLEN
// nkParam-Knoten die Zeile des Methoden-Schluesselworts gibt - bei umbrochener
// Parameterliste steht der Marker aber auf der Zeile SEINES Parameters.
// Bilanziert wird auf der GESTRIPPTEN Quelle, damit Klammern in Kommentaren
// und Strings nicht mitzaehlen. Harte Obergrenze, und ohne '(' auf der
// Kopfzeile bleibt es bei AFirstLine - beides nur FN-Richtung.
const
  MAX_HEADER_LINES = 12;
var
  i, j, Depth : Integer;
  Opened      : Boolean;
  L           : string;
begin
  Result := AFirstLine;
  if (AFirstLine < 1) or (AFirstLine > Length(ALines)) then Exit;
  Depth  := 0;
  Opened := False;
  for i := AFirstLine to AFirstLine + MAX_HEADER_LINES - 1 do
  begin
    if i > Length(ALines) then Break;
    L := ALines[i - 1];
    for j := 1 to Length(L) do
      if L[j] = '(' then
      begin
        Inc(Depth);
        Opened := True;
      end
      else if L[j] = ')' then
        Dec(Depth);
    Result := i;
    if not Opened then Exit;         // Parameterliste beginnt nicht hier
    if Depth <= 0 then Exit;
  end;
end;

function HasAdjacentFpcHideMarker(const ARawLine, ANameLow: string): Boolean;
// '{%H-}' direkt vor oder hinter dem Parameternamen = der Autor hat den Hint
// an genau dieser Stelle abgeschaltet (Lazarus-/FPC-Konvention).
//
// BEWUSSTE AUSNAHME von der Regel 'Kommentare zaehlen nie': '{%H-}' IST ein
// Kommentar - genau deshalb wird die ROHE Zeile geprueft, in der gestrippten
// ist der Marker weggeblankt. Identische Begruendung und identisches
// Adjazenz-Gebot wie in uUninitVar.HasAdjacentFpcHideMarker (SCA166): ein
// Marker an einem ANDEREN Parameter derselben Zeile suppresst nicht mit.
var
  L : string;
  P, NL, LL, q : Integer;
begin
  Result := False;
  if (ARawLine = '') or (ANameLow = '') then Exit;
  L := LowerCase(ARawLine);
  if Pos('{%h-}', L) = 0 then Exit;
  NL := Length(ANameLow);
  LL := Length(L);
  P  := 1;
  while True do
  begin
    P := Pos(ANameLow, L, P);
    if P = 0 then Exit;
    if ((P = 1) or not IsIdentChar(L[P - 1])) and
       ((P + NL > LL) or not IsIdentChar(L[P + NL])) then
    begin
      q := P - 1;                                  // Marker VOR dem Namen
      while (q >= 1) and (L[q] = ' ') do Dec(q);
      if (q >= 5) and (Copy(L, q - 4, 5) = '{%h-}') then Exit(True);
      q := P + NL;                                 // Marker NACH dem Namen
      while (q <= LL) and (L[q] = ' ') do Inc(q);
      if Copy(L, q, 5) = '{%h-}' then Exit(True);
    end;
    P := P + NL;
  end;
end;

function ParamHasFpcHideMarker(var AStripped: TStrippedUnit;
  const AFileName: string; AHeaderFirst: Integer;
  const ANameLow: string): Boolean;
var
  i, LastL : Integer;
begin
  Result := False;
  EnsureUnitStripped(AStripped, AFileName);
  if Length(AStripped.Raw) = 0 then Exit;
  LastL := HeaderLastLine(AStripped.Lines, AHeaderFirst);
  for i := AHeaderFirst to LastL do
  begin
    if (i < 1) or (i > Length(AStripped.Raw)) then Continue;
    if HasAdjacentFpcHideMarker(AStripped.Raw[i - 1], ANameLow) then
      Exit(True);
  end;
end;

procedure CollectAllTokens(Root: TAstNode; SB: TStringBuilder);
var
  Stack : TStack<TAstNode>;
  Cur : TAstNode;
  i : Integer;
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

function RoutineUsedAsProcValue(var AStripped: TStrippedUnit;
  const ARoutineName: string): Boolean;
// GATE E (Stichprobe 2026-08-30, 200 SCA054-Funde aus dem Referenzkorpus):
// die Routine wird nicht GERUFEN, sondern als WERT weitergereicht - als
// Argument, per := an ein Event, oder ueber @. Dann gibt der Empfaenger
// die Signatur vor, und ein ungelesener Parameter ist Vertragserfuellung,
// kein Defekt. Ihn zu streichen bricht die Uebersetzung.
//
// GEMESSEN: 123 der 200 Stichprobenfunde (62 %) tragen dieses Muster.
// Die dichtesten Stellen sind Registrierungs-Units mit einheitlichen
// Callback-Signaturen -
//   AddGet(TAnimate, 'Reset', TAnimate_Reset, 0, [varEmpty], varEmpty);
//   FServer.OnParseAuthentication := ParseAuthenticationHandler;
// - beide am Quelltext verifiziert.
//
// ABGRENZUNG zu den bestehenden Gates: die decken Faelle ab, in denen die
// Signatur von OBEN kommt (override/virtual, inherited, message) oder der
// Autor sie markiert (_-Praefix, {%H-}). Hier kommt sie von der
// AUFRUFSEITE - dieselbe Ursache, andere Richtung.
//
// KONSERVATIV in zwei Punkten:
//  * Namen unter 4 Zeichen werden NICHT gegatet. Ein Treffer auf 'Get',
//    'Add' oder 'Run' waere zu leicht zufaellig, und ein
//    verpasstes Gate kostet nur einen Fund - ein falsches kostet einen
//    echten Befund.
//  * Gesucht wird im GESTRIPPTEN Text: ein Name in einem String oder
//    Kommentar zaehlt nicht als Verwendung.
var
  i     : Integer;
  Zeile : string;
  N     : string;
begin
  Result := False;
  N := LowerCase(Trim(ARoutineName));
  if Length(N) < 4 then Exit;
  for i := 0 to High(AStripped.Lines) do
  begin
    Zeile := LowerCase(AStripped.Lines[i]);
    if Pos(N, Zeile) = 0 then Continue;   // billiger Vorfilter
    // (1) als Argument:  Foo(..., Name, ...)  /  Foo(Name)
    if TRegEx.IsMatch(Zeile, '[(,]\s*' + TRegEx.Escape(N)
                      + '\s*[,)]') then Exit(True);
    // (2) an ein Event gehaengt, Form  X.OnFoo := Name
    if TRegEx.IsMatch(Zeile, ':=\s*' + TRegEx.Escape(N)
                      + '\s*;') then Exit(True);
    // (3) Adresse:  @Name
    if TRegEx.IsMatch(Zeile, '@\s*' + TRegEx.Escape(N)
                      + '\b') then Exit(True);
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeMethod(UnitNode, MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  var AStripped: TStrippedUnit);
var
  Params : TList<TAstNode>;
  P : TAstNode;
  Name, LowName : string;
  BodySB : TStringBuilder;
  BodyLow : string;
  RefCount : Integer;
  F : TLeakFinding;
  OwnerCls : TAstNode;   // T2: Besitzertyp fuer den Interface-Skip
  Decl : TAstNode;       // Class-Declaration dieser Implementation (oder nil)
  // GATE B: Ziele der 'absolute'-Aliase dieser Methode als ' a b '-String.
  AbsTargets : string;
  // GATE E: Ergebnis von RoutineUsedAsProcValue, LAZY. -1 = noch nicht
  //   geprueft. Die Pruefung liest ALLE Unit-Zeilen und soll nur die
  //   Methoden kosten, bei denen tatsaechlich ein Fund ansteht.
  ProcValueState : Integer;
  // Ist-Messung 2026-07-18 (SCA054-FP-Klasse 'nested-routine-Nutzung', 3/5 der
  // Sample-FPs): der Parser verwirft nested-routine-Bodies aus dem Method-AST
  // (nur nkNestedRange-Marker bleiben, Line=Start/TypeRef=EndLine) -> ein Param,
  // der NUR in einer nested proc gelesen wird, war unsichtbar. Lazy-Fallback:
  // die Quell-Zeilen der Marker-Ranges (kommentar-/string-gestrippt - Kommentare
  // zaehlen NIE als Use) wort-gebunden nach dem Param-Namen scannen. Monoton
  // (nur zusaetzlicher Skip). Rest-Risiko Shadowing (gleichnamige nested-lokale
  // Var) unterdrueckt einen echten Fund - akzeptiert fuer lsHint, konsistent
  // mit der Text-Zaehlung des Detektors.
  NestedMarks   : TList<TAstNode>;
  // Rumpf-Zeilenbereich fuer die Quell-Rueckfrage. Bewusst Locals der
  // umschliessenden Routine statt out-Parameter: der eigene Analyser
  // meldet out zu Recht als schwer lesbar (AvoidOut), und die
  // verschachtelte Funktion sieht die Locals ohnehin.
  BodyFrom      : Integer;
  BodyTo        : Integer;

  function BodyLineRangeFound: Boolean;
  // Von 'begin' bis zur groessten Zeilennummer im Teilbaum.
  //
  // ANFANG bewusst am nkBlock und nicht am Methodenkopf: in der SIGNATUR
  // steht der Parametername ja - von dort zu scannen hiesse, jeden
  // Parameter als benutzt zu sehen und die Regel abzuschalten.
  //
  // ENDE ueber max(Line) des Teilbaums. Das traegt, weil die Luecke im
  // INHALT der Knoten liegt, nicht in ihrer Existenz: jede Anweisung ist
  // ein Knoten mit Zeilennummer, auch wenn ihr Text unvollstaendig
  // abgelegt wurde. Genau das ist der Fall bei den beiden gemessenen
  // Formen (Index-Ausdruck links einer Zuweisung, Argumente hinter einem
  // as-Cast).
  var
    Blk   : TAstNode;
    Stack : TStack<TAstNode>;
    Cur   : TAstNode;
    I     : Integer;
  begin
    Result := False;
    Blk := MethodNode.FindFirstChild(nkBlock);
    if Blk = nil then Exit;
    BodyFrom := Blk.Line;
    BodyTo   := Blk.Line;
    Stack := TStack<TAstNode>.Create;
    try
      Stack.Push(MethodNode);
      while Stack.Count > 0 do
      begin
        Cur := Stack.Pop;
        if Cur.Line > BodyTo then BodyTo := Cur.Line;
        for I := 0 to Cur.Children.Count - 1 do
          Stack.Push(Cur.Children[I]);
      end;
    finally
      Stack.Free;
    end;
    Result := (BodyFrom > 0) and (BodyTo >= BodyFrom);
  end;

  function UsedInMethodSource(const NameLow: string): Boolean;
  // Letzte Rueckfrage vor dem Melden: steht der Name ueberhaupt im
  // Rumpf-QUELLTEXT? Strings und Kommentare sind gestrippt - ein Name im
  // Kommentar zaehlt NIE als Nutzung.
  //
  // MONOTON: kann nur Funde wegnehmen, nie welche erzeugen.
  //
  // RESTRISIKO Shadowing - eine gleichnamige lokale Variable laesst den
  // Parameter benutzt aussehen und unterdrueckt einen echten Fund. Exakt
  // dasselbe Risiko traegt UsedInNestedRanges seit 2026-07-18, dort
  // ausdruecklich akzeptiert: fuer einen Hint ist ein verschwiegener Fund
  // billiger als ein falscher.
  var
    li, q, NL_ : Integer;
    L : string;
  begin
    Result := False;
    if not BodyLineRangeFound then Exit;
    EnsureUnitStripped(AStripped, FileName);
    if Length(AStripped.Lines) = 0 then Exit;
    NL_ := Length(NameLow);
    for li := BodyFrom to BodyTo do
    begin
      if (li < 1) or (li > Length(AStripped.Lines)) then Continue;
      L := LowerCase(AStripped.Lines[li - 1]);
      // STARTZEILE NUR AB DEM begin-TOKEN (Review 2026-08-04): teilt die
      // SIGNATUR die Zeile mit dem begin - Einzeiler wie
      //   procedure TFoo.Bar(Sender: TObject); begin end;
      // oder eine umgebrochene Parameterliste mit '); begin' am Ende -
      // stuende der Parametername sonst im gescannten Bereich, und die
      // DEKLARATION zaehlte als Nutzung: echter Fund still unterdrueckt.
      // Der Strip ersetzt positions-erhaltend mit ' ', die Spalten der
      // gestrippten Zeile stimmen also mit der Quelle ueberein.
      if li = BodyFrom then
      begin
        q := Pos('begin', L);
        while (q > 0) and not
              (((q = 1) or not IsIdentChar(L[q - 1])) and
               ((q + 5 > Length(L)) or not IsIdentChar(L[q + 5]))) do
          q := Pos('begin', L, q + 1);
        if q > 0 then
          L := Copy(L, q + 5, MaxInt)
        else
          Continue;   // begin nicht auf dieser Zeile auffindbar - defensiv
      end;
      q := Pos(NameLow, L);
      while q > 0 do
      begin
        if ((q = 1) or not IsIdentChar(L[q - 1])) and
           ((q + NL_ > Length(L)) or not IsIdentChar(L[q + NL_])) then
          Exit(True);
        q := Pos(NameLow, L, q + 1);
      end;
    end;
  end;

  function UsedInNestedRanges(const NameLow: string): Boolean;
  var
    M : TAstNode;
    li, EndL, q, NL : Integer;
    L : string;
  begin
    Result := False;
    if NestedMarks.Count = 0 then Exit;
    EnsureUnitStripped(AStripped, FileName);
    if Length(AStripped.Lines) = 0 then Exit;
    NL := Length(NameLow);
    for M in NestedMarks do
    begin
      EndL := StrToIntDef(M.TypeRef, M.Line);
      for li := M.Line to EndL do
      begin
        if (li < 1) or (li > Length(AStripped.Lines)) then Continue;
        L := LowerCase(AStripped.Lines[li - 1]);
        q := Pos(NameLow, L);
        while q > 0 do
        begin
          if ((q = 1) or not IsIdentChar(L[q - 1])) and
             ((q + NL > Length(L)) or not IsIdentChar(L[q + NL])) then
            Exit(True);
          q := Pos(NameLow, L, q + 1);
        end;
      end;
    end;
  end;

begin
  ProcValueState := -1;   // GATE E: lazy, s. Deklaration
  // Declarations (in nkClass) skippen - die haben keinen Body und keine
  // sinnvolle Reference-Count. Ihre Modifier konsultieren wir aber von
  // der zugehoerigen Implementation aus (siehe IsInheritanceHook).
  if not MethodNode.HasChild(nkBlock) then Exit;

  Decl := FindDeclarationFor(UnitNode, MethodNode);
  if IsInheritanceHook(MethodNode, Decl) then Exit;

  // Methoden verschachtelter Typen (T2-Guards-Ruecknahme 2026-07-29):
  // Seit der Parser nested types als eigene nkClass-/nkRecord-Knoten fuehrt
  // (tkKwType-Zweig, 8d36052), ist die Vorfahrenliste auswertbar und der
  // fruehere Blanket-Exit einem PRAEZISEN Skip gewichen:
  //
  //   * Besitzertyp implementiert Interfaces (2.+ Eintrag der
  //     class(...)-Liste - Delphi kennt keine Klassen-Mehrfachvererbung,
  //     alles nach dem ersten Eintrag ist ein Interface): Signatur ist
  //     potenziell compiler-erzwungen (E2291), 'unused parameter' dort
  //     nicht behebbar. Das ist das Bridge-Delegate-Muster
  //     (class(TOCLocal, WKNavigationDelegate) / class(TJavaLocal,
  //     JALWebViewListener)) - 259 von 282 FPs der Korpus-Messung
  //     2026-07-27.
  //   * Besitzertyp nicht auffindbar: defensiv schweigen (sollte seit dem
  //     tkKwType-Zweig nicht mehr vorkommen).
  //   * Sonst - nested class ohne Interfaces, nested record - laeuft die
  //     normale Analyse: das holt die bewusst geopferten ECHTEN Funde
  //     zurueck (3x Shift-Parameter in Alcinoe.FMX.Dynamic.ListBox,
  //     TP-belegt in der ADD-Stichprobe).
  //
  // BEWUSST nur fuer nested-type-Methoden: ein Interface-Skip fuer ALLE
  // Klassen wuerde bestehende Funde normaler Klassen korpusweit droppen -
  // eigenes Vorhaben mit eigenem A/B, nicht Beifang dieser Ruecknahme.
  if TDetectorUtils.IsNestedTypeMethodName(MethodNode.Name) then
  begin
    if not TryFindOwnerType(UnitNode, MethodNode.Name, OwnerCls) then Exit;
    if (OwnerCls.Kind = nkClass) and OwnerHasInterfaceParents(OwnerCls) then
      Exit;
  end
  // ---- 2026-08-01: derselbe Skip fuer NICHT-verschachtelte Klassen ------
  // Der Kommentar oben kuendigt genau das als eigenes Vorhaben mit eigenem
  // A/B an - hier ist es. Das Audit vom 31.07. hat die Luecke als eigene
  // FP-Klasse belegt (4 von 24 Stichproben): der Interface-Skip griff nur
  // bei nested types, waehrend IMVCSerializer / IOTADebuggerNotifier /
  // IJclSingleList / IMVCAuthenticationHandler an ganz gewoehnlichen
  // Klassen haengen. Deren Signatur ist genauso compiler-erzwungen (E2291),
  // 'unused parameter' dort genauso wenig behebbar.
  //
  // UNTERSCHIED zum nested-Zweig: wird der Besitzertyp NICHT gefunden,
  // laeuft die Analyse normal weiter statt zu schweigen. Bei nested types
  // ist Nicht-Finden ein Hinweis auf ein Homonym (dort ist Schweigen
  // richtig); bei einer gewoehnlichen Klasse MUSS die Deklaration in
  // derselben Unit stehen, Nicht-Finden heisst also Parser-Aerger - und
  // daraus einen Blanket-Skip zu machen waere zu viel.
  //
  // BEWUSST NICHT umgesetzt: die Audit-Zusatzbedingung "und die Methode ist
  // public/protected". Die Sichtbarkeit haengt am nkVisibilitySection der
  // DEKLARATION, nicht an der Implementierung; der Weg dorthin ist ein
  // eigener Lookup. Ohne die Bedingung faellt auch die private Methode
  // einer interface-tragenden Klasse weg - Ueberreichweite, die als
  // FN-Restklasse hier notiert ist.
  else if TryFindOwnerType(UnitNode, MethodNode.Name, OwnerCls) and
          (OwnerCls.Kind = nkClass) and
          OwnerHasInterfaceParents(OwnerCls) then
    Exit;

  // Rumpf ist nur ein `raise` - die Parameter KOENNEN nicht gelesen werden.
  if BodyIsRaiseOnly(MethodNode) then Exit;

  if IsLikelyEventHandler(MethodNode) then Exit;
  if ForwardsParamsViaInherited(MethodNode) then Exit;
  // Track B1 (2026-07-12): der SCA028-Follow-up-Guard (IsKeywordRoutineName)
  // ist entfernt - der Parser-Fix (Write/Read-Statement-Dispatch) haengt jetzt
  // die Bodies keyword-benannter Methoden korrekt an, Param-Uses sind sichtbar.

  NestedMarks   := TList<TAstNode>.Create;
  Params := MethodNode.FindAll(nkParam);
  BodySB := TStringBuilder.Create;
  try
    if Params.Count = 0 then Exit;
    // ---- GATE A (2026-08-27): message-Handler --------------------------
    // Vor der Rumpf-Auswertung, weil der Vertrag den Parameter erzwingt -
    // was im Rumpf steht, aendert daran nichts (Begruendung s.
    // IsMessageHandler / DeclHasMessageDirective).
    if IsMessageHandler(Decl, Params, AStripped, FileName) then Exit;
    // nkNestedRange-Marker der verworfenen nested routines einsammeln
    // (direkte MethodNode-Children, siehe uParser2 ~Z.1319).
    for var NR in MethodNode.Children do
      if NR.Kind = nkNestedRange then NestedMarks.Add(NR);
    CollectAllTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);

    // ---- GATE B (2026-08-27): 'absolute'-Aliase einsammeln --------------
    // Vorfilter auf dem ohnehin vorhandenen Flachtext: ohne das Wort
    // 'absolute' irgendwo im Methoden-Teilbaum kann es keinen Alias geben,
    // und keine Methode zahlt einen Kind-Durchlauf oder Quellzugriff.
    AbsTargets := '';
    if Pos('absolute', BodyLow) > 0 then
      AbsTargets := CollectAbsoluteAliasTargets(MethodNode, AStripped,
                                                FileName);

    for P in Params do
    begin
      // Parser legt Modifier `var/const/out` als Name-Praefix ab
      // ('const X' statt nur 'X'); Param-Name = letztes Wort.
      Name := Trim(P.Name);
      if Name = '' then Continue;
      var SpaceIdx := LastDelimiter(' ', Name);
      if SpaceIdx > 0 then
        Name := Copy(Name, SpaceIdx + 1, MaxInt);
      if Name.StartsWith('_') then Continue;
      // ---- GATE F (2026-08-27): 'constref'-Phantom --------------------
      // 'constref' ist ein FPC-Parametermodifier. Der Parser kennt nur
      // var/const/out (uParser2 ~Z.1580); 'constref' wird deshalb als
      // eigener Parameter mit LEEREM Typ eingesammelt und der echte
      // Parameter dahinter separat. Gemeldet wuerde also ein Parameter,
      // den die Quelle gar nicht deklariert. Bewusst nur die woertliche
      // Ebene: ein ECHTER Parameter dieses Namens ist ausgeschlossen,
      // weil 'constref' in FPC reserviert ist.
      if SameText(Name, 'constref') then Continue;

      LowName := LowerCase(Name);

      // ---- GATE B (2026-08-27): Parameter traegt einen 'absolute'-Alias -
      // Ueber den Alias wird die Storage DIESES Parameters gelesen und
      // geschrieben; 'never read in method body' waere unwahr.
      if (AbsTargets <> '') and (Pos(' ' + LowName + ' ', AbsTargets) > 0) then
        Continue;

      // Param-Deklaration ist EIN Vorkommen. Mindestens 2 noetig fuer "genutzt".
      RefCount := 0;
      var Pos1 := 1;
      while True do
      begin
        Pos1 := Pos(LowName, BodyLow, Pos1);
        if Pos1 = 0 then Break;
        var Before : Char := #0;
        if Pos1 > 1 then Before := BodyLow[Pos1 - 1];
        var After  : Char := #0;
        if Pos1 + Length(LowName) - 1 < Length(BodyLow) then
          After := BodyLow[Pos1 + Length(LowName)];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
          Inc(RefCount);
        Pos1 := Pos1 + Length(LowName);
      end;

      if RefCount <= 1 then
      begin
        // Nested-Routine-Fallback (s. Kommentar oben): Param wird in einer vom
        // Parser verworfenen nested proc gelesen -> benutzt, kein Fund.
        if UsedInNestedRanges(LowName) then Continue;
        // Quell-Rueckfrage fuer den eigenen Rumpf (2026-08-03): der
        // AST-Flachtext ist eine Teilmenge der Quelle. Bevor wir Abwesenheit
        // BEHAUPTEN, fragen wir die Quelle. Am gebauten Stand reproduziert:
        // 'SystemPath[Kind] := x' und '(Obj as T).M(Index, 1)' - in beiden
        // Faellen fehlt der Bezeichner im AST-Text, steht aber im Rumpf.
        if UsedInMethodSource(LowName) then Continue;
        // ---- GATE C (2026-08-27): FPC-'{%H-}' am Parameter --------------
        // Letzter Halt vor dem Melden: der Autor hat den Hint an genau
        // diesem Parameter abgeschaltet. Absichtlich hier unten - die
        // Pruefung liest die ROHE Quelle und soll nur die wenigen
        // Kandidaten kosten, die es bis zur Meldung schaffen.
        if ParamHasFpcHideMarker(AStripped, FileName, MethodNode.Line,
                                 LowName) then Continue;
        // ---- GATE E (2026-08-30): die Routine wird als WERT
        // weitergereicht (Argument, := an ein Event, @Adresse). Dann gibt
        // der Empfaenger die Signatur vor - den Parameter zu streichen
        // braeche die Uebersetzung. Gemessen an 200 Stichprobenfunden aus
        // dem Referenzkorpus: 62 % tragen dieses Muster. Lazy, weil die
        // Pruefung die ganze Unit liest.
        if ProcValueState < 0 then
        begin
          if RoutineUsedAsProcValue(AStripped,
               TDetectorUtils.UnqualifiedNameLast(MethodNode.Name)) then
            ProcValueState := 1
          else
            ProcValueState := 0;
        end;
        if ProcValueState = 1 then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.Line);
        F.MissingVar := Format(
          'Unused parameter: %s (never read in method body)', [Name]);
        F.SetKind(fkUnusedParameter);
        Results.Add(F);
      end;
    end;
  finally
    BodySB.Free;
    Params.Free;
    NestedMarks.Free;
  end;
end;

class procedure TUnusedParameterDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods  : TList<TAstNode>;
  M        : TAstNode;
  Stripped : TStrippedUnit;
begin
  // EINE gestrippte Fassung fuer alle Methoden dieser Datei. Wird erst
  // gefuellt, wenn die erste Methode sie wirklich braucht - Dateien ohne
  // Kandidaten zahlen gar nichts.
  Stripped.Ready := False;
  Stripped.Lines := nil;
  Stripped.Raw   := nil;
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(UnitNode, M, FileName, Results, Stripped);
  finally
    Methods.Free;
  end;
end;

end.
