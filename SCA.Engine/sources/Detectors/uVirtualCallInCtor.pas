unit uVirtualCallInCtor;

// Detektor: Aufruf einer `virtual`-Methode im Constructor.
//
// Wenn ein Constructor in einer Basisklasse eine virtual-Methode ruft,
// laeuft die ueberschriebene Variante in der abgeleiteten Klasse - aber
// zu einem Zeitpunkt, wo der Sub-Klassen-Constructor noch nicht durch
// ist. Felder sind eventuell null/0, der Override greift auf halb-
// initialisiertes Self zu -> NullPointerException / Subtle-Bug.
//
// Beispiel:
//   type
//     TBase = class
//       constructor Create;
//       procedure Init; virtual;
//     end;
//     TDerived = class(TBase)
//       FCache: TList;
//       procedure Init; override;
//     end;
//
//   constructor TBase.Create;
//   begin
//     Init;            // <-- ruft TDerived.Init, FCache ist noch nil!
//   end;
//
// Algorithmus (single-unit):
//   1. Sammle alle Klassen + ihre Methoden mit Virtual-Markierung
//      (uParser2 haengt 'virtual'/'override'/'dynamic' an TypeRef an).
//   2. Fuer jeden Constructor: alle nkCall-Nodes durchgehen.
//   3. Wenn der Call-Name zu einer Methode der gleichen Klasse passt,
//      die virtual/override/dynamic ist -> Treffer.
//
// Heuristik:
//   * inherited Create / inherited Init: kein Treffer (geht hoch, nicht
//     runter; keine Override-Reflektion).
//   * Self.MyVirtual: Treffer (so wie ohne Self.).
//   * MyVirtual(args): Treffer.
//   * Andere Objekt-Calls (FFoo.DoSomething): kein Treffer.
//   * 'inherited <Event> := <Handler>;': der ZUGEWIESENE Handler ist kein
//     Treffer (2026-07-31, Event-Zuweisung ist keine Call-Kante - siehe
//     IsInheritedEventAssignPhantom). Jeder ANDERE Aufruf auf derselben
//     Zeile bleibt ein Treffer.
//   * 'inherited <Wert-Property> := <parameterlose Funktion>;': das IST ein
//     Aufruf und bleibt ein Treffer (2026-07-31 Nachschaerfung, JvCombos.pas:672
//     'inherited ItemHeight := MinItemHeight;').

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TVirtualCallInCtorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

// ---------------------------------------------------------------------------
// FP-Gate (2026-07-31, 30%-Real-World-Audit sca-rw-after119)
// FP-Klasse: Event-Handler-ZUWEISUNG wird als Aufruf gewertet.
// Belege: jvcl/tests/p3/source/JvPageListTreeView.pas:1614
//         ('inherited OnGetSelectedIndex := DoGetSelectedIndex;') und
//         jvcl/jvcl/run/JvThread.pas:409 ('inherited OnShow := ReplaceFormShow;').
//
// Mechanismus (an uParser2 verifiziert): fuer 'inherited <Ident> := <Ident>;'
// laeuft ParseStatement in den tkKwInherited-Zweig, ParsePrimary bricht am
// ':=' ab und legt nkInherited('OnShow') an. Das uebrig gebliebene ':=' faellt
// in den else-Zweig (Next; Eat(tkSemicolon), kein Knoten), und der RHS-
// Bezeichner wird danach als eigenstaendige Anweisung geparst -> Phantom-
// nkCall('ReplaceFormShow'). Der Reachability-Walk haelt dieses Phantom fuer
// einen Aufruf aus dem Ctor; tatsaechlich ist es eine Methodenzeiger-
// Zuweisung, der Handler laeuft erst beim Event-Feuern nach der Konstruktion.
//
// Gate: Quellzeile des nkCall auf das Muster '^inherited <Ident> := <RhsId>'
// pruefen (Strings/Kommentare vorher entfernt). Trifft es zu, wird GENAU der
// Knoten verworfen, dessen Name dem zugewiesenen RHS-Bezeichner entspricht -
// alle anderen nkCall derselben Zeile bleiben Treffer.
//
// Praezisierung 2026-07-31 (Pre-Build-Review, Fund uVirtualCallInCtor.pas:426
// "Zeilen-basiertes Gate stellt JEDEN Aufruf auf einer 'inherited <Ident> :='-
// Zeile still"): das erste Gate war rein zeilenbasiert und verwarf auf einer
// Treffer-Zeile pauschal alles. Damit gingen belegte TPs verloren:
//   'inherited Value := ComputeIt(Self);'   (echter Aufruf MIT Klammern)
//   'inherited OnShow := Foo; Init;'        (nachgestellter echter Aufruf)
// Jetzt gilt: nur ein RHS OHNE Klammern ist ein Methodenzeiger (= keine
// Call-Kante); sobald der RHS eine Argumentliste hat, ist es ein echter
// Aufruf und die Zeile wird gar nicht erst in den Cache aufgenommen.
//
// BEWUSST eng (Praezision vor Masse - 626 Error-Funde mit nur 8% FP, die TPs
// muessen alle bleiben):
//   * 'inherited Create; Init;' enthaelt kein ':=' -> Treffer bleibt.
//   * mehrfach-Zuweisung auf einer Zeile ('inherited A := X; inherited B := Y;')
//     nimmt nur den ERSTEN RHS auf; der zweite Handler bleibt ein Fund
//     (bewusster Rest-FP statt TP-Risiko).
// Lazy: die Datei wird erst gelesen, wenn ein Fund anstuende.
//
// ===========================================================================
// NACHSCHAERFUNG 2026-07-31 (Drop-Sampling des Gates after119->after120:
// 3 TP-VERLUSTE bei nur 8 Drops = 37,5 % Fehlerquote des Gates)
//
// Belegter TP-Verlust (drei byte-gleiche Kopien):
//   jvcl/tests/RxLib/Source/JvCombos.pas:672
//   jvcl/tests/archive/jvcl/Archive/JvCombos.pas:672
//   jvcl/tests/restructured/Archive/JvCombos.pas:672
//     Z. 59  function MinItemHeight: Integer; virtual;    // TJvOwnerDrawComboBox
//     Z.196  function MinItemHeight: Integer; override;   // TJvxFontComboBox
//     Z.665  constructor TJvxFontComboBox.Create(AOwner: TComponent);
//     Z.672    inherited ItemHeight := MinItemHeight;     // <-- echter Virtual-Call
//
// Die urspruengliche Fassung akzeptierte JEDEN blanken RHS-Bezeichner als
// Methodenzeiger; einzige Rueckfalltuer war 'Pos(''('') > 0'. Eine PARAMETERLOSE
// virtuelle Funktion auf der RHS hat aber exakt dieselbe lexikalische Form
// wie eine Methodenreferenz - der Klammer-Test kann sie nicht trennen. Die
// Entscheidung wird deshalb nicht mehr lexikalisch, sondern ueber die
// DEKLARATION getroffen. Das Gate ist jetzt ein UND aus drei Huerden:
//
//   H0 (unveraendert) Zeile matcht 'inherited <Lhs> := <RhsIdent>' und der
//                     Knotenname ist GENAU dieser RhsIdent (ohne Klammern).
//   H1 ZIEL-KRITERIUM Lhs sieht aus wie ein Event: Name 'On' + Grossbuchstabe
//                     ('OnShow', 'OnGetImageIndex'). Ein Wert-Property wie
//                     'ItemHeight' oder 'Caption' faellt raus -> Treffer bleibt.
//   H2 RHS-KRITERIUM  Der RHS-Bezeichner ist in dieser Klasse NICHT als
//                     parameterlose FUNKTION deklariert. Eine parameterlose
//                     Funktion liefert einen WERT; sie kann per Konstruktion
//                     kein Handler eines Event-Typs sein (jeder gaengige
//                     Event-Typ ist eine Prozedur-Signatur, TNotifyEvent
//                     'procedure(Sender: TObject) of object'). RHS-Shape kommt
//                     aus MethodByName/VirtualByName (TypeRef 'function...'
//                     + Zahl der nkParam-Kinder).
//
// Beide Huerden ziehen den Gate ENGER (weniger Drops). Kontrollrechnung am
// Korpus - die 8 Drops des Gates:
//   JvCombos.pas:672 (x3)  'inherited ItemHeight := MinItemHeight'
//                          H1 nein (ItemHeight), H2 nein (function, 0 Params)
//                          -> Gate AUS, TP kehrt zurueck.
//   jvcl/run/JvPageListTreeView.pas:726/727
//   jvcl/tests/p3/source/JvPageListTreeView.pas:1613/1614
//                          'inherited OnGetImageIndex := DoGetImageIndex'
//                          H1 ja, H2 ja (procedure(Sender; Node), 2 Params)
//                          -> Gate AN, FP bleibt gedroppt.
//   jvcl/run/JvThread.pas:409
//                          'inherited OnShow := ReplaceFormShow'
//                          H1 ja, H2 ja (procedure(Sender), 1 Param)
//                          -> Gate AN, FP bleibt gedroppt.
//
// BEWUSST NICHT uebernommen: 'RHS ist eine bekannte VIRTUELLE Methode =>
// echter Aufruf'. Am Korpus haette das dieselben 8 Drops getroffen (keiner
// der fuenf FP-Handler ist virtual), es ist aber semantisch verkehrt herum:
// 'inherited OnShow := Foo;' mit 'procedure Foo(Sender: TObject); virtual;'
// ist weiterhin eine ZUWEISUNG, Foo laeuft nicht im Ctor. Zwei bestehende
// Regressionstests pinnen genau das (InheritedEventAssign_NoFinding,
// InheritedEventAssign_TrailingCall_StillReported). Virtualitaet sagt nichts
// darueber aus, ob ein RHS Zeiger oder Aufruf ist - die SIGNATURFORM (H2) tut
// es, und sie trennt den belegten TP sauber ab.
// ===========================================================================
// ---------------------------------------------------------------------------

type
  // Ergebnis der Zeilen-Analyse von 'inherited <Lhs> := <RhsIdent>'.
  TInhAssignInfo = record
    Lhs    : string;   // Zuweisungsziel in ORIGINALSCHREIBWEISE ('OnShow')
    RhsLow : string;   // zugewiesener Bezeichner, lowercase ('replaceformshow')
  end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

// Entfernt String-Literale und Kommentare aus EINER Quellzeile; InBrace /
// InParenStar tragen den Block-Kommentar-Zustand ueber Zeilengrenzen.
function StripCodeLine(const Line: string; var InBrace, InParenStar: Boolean): string;
var
  i, N  : Integer;
  InStr : Boolean;
begin
  Result := '';
  InStr  := False;
  N      := Length(Line);
  i      := 1;
  while i <= N do
  begin
    if InBrace then
    begin
      if Line[i] = '}' then InBrace := False;
      Inc(i);
      Continue;
    end;
    if InParenStar then
    begin
      if (Line[i] = '*') and (i < N) and (Line[i + 1] = ')') then
      begin
        InParenStar := False;
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      Continue;
    end;
    if InStr then
    begin
      if Line[i] = '''' then InStr := False;
      Inc(i);
      Continue;
    end;
    if Line[i] = '''' then begin InStr := True; Inc(i); Continue; end;
    if Line[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
    if (Line[i] = '(') and (i < N) and (Line[i + 1] = '*') then
    begin
      InParenStar := True;
      Inc(i, 2);
      Continue;
    end;
    if (Line[i] = '/') and (i < N) and (Line[i + 1] = '/') then Break;
    Result := Result + Line[i];
    Inc(i);
  end;
end;

// True fuer 'inherited <Ident> := <RhsIdent>' (Code bereits gestrippt).
// AInfo.RhsLow liefert den zugewiesenen RHS-Bezeichner (lowercase) - aber NUR
// wenn der RHS bis zum ersten ';' ein reiner, ggf. qualifizierter Bezeichner
// OHNE Klammern ist ('ReplaceFormShow', 'Self.ReplaceFormShow'). Alles andere
// ('ComputeIt(Self)', zusammengesetzte Ausdruecke, RHS auf der Folgezeile) ist
// entweder ein echter Aufruf oder nicht sicher zuzuordnen -> Result=False und
// die Zeile wird nicht gegatet (Review 2026-07-31).
// AInfo.Lhs liefert das Zuweisungsziel in ORIGINALSCHREIBWEISE - Huerde H1
// braucht die Gross-/Kleinschreibung ('OnShow' vs. 'Only'), deshalb wird
// parallel zur lowercase-Arbeitskopie der Originaltext mitgefuehrt (LowerCase
// ist fuer UTF-16 laengentreu, die Indizes gelten in beiden Strings).
function LineIsInheritedPropertyAssign(const Code: string;
  out AInfo: TInhAssignInfo): Boolean;
const
  INH = 'inherited';
var
  Orig     : string;
  S        : string;
  i, N     : Integer;
  LhsStart : Integer;
  Rhs      : string;
begin
  Result       := False;
  AInfo.Lhs    := '';
  AInfo.RhsLow := '';
  Orig := TrimLeft(Code);
  S    := LowerCase(Orig);
  if not S.StartsWith(INH) then Exit;
  N := Length(S);
  i := Length(INH) + 1;                       // erstes Zeichen NACH 'inherited'
  if (i > N) or IsIdentChar(S[i]) then Exit;  // 'inheritedfoo := ...'
  while (i <= N) and CharInSet(S[i], [' ', #9]) do Inc(i);
  if (i > N) or not CharInSet(S[i], ['a'..'z', '_']) then Exit;
  LhsStart := i;
  while (i <= N) and IsIdentChar(S[i]) do Inc(i);
  AInfo.Lhs := Copy(Orig, LhsStart, i - LhsStart);
  while (i <= N) and CharInSet(S[i], [' ', #9]) do Inc(i);
  if not ((i < N) and (S[i] = ':') and (S[i + 1] = '=')) then Exit;

  // RHS = Text hinter ':=' bis zum ersten ';' (bzw. Zeilenende).
  Inc(i, 2);
  Rhs := '';
  while (i <= N) and (S[i] <> ';') do
  begin
    Rhs := Rhs + S[i];
    Inc(i);
  end;
  Rhs := Trim(Rhs);
  if Rhs = '' then Exit;
  if not CharInSet(Rhs[1], ['a'..'z', '_']) then Exit;   // Literal/Ausdruck
  for i := 1 to Length(Rhs) do
    if not (IsIdentChar(Rhs[i]) or (Rhs[i] = '.')) then
      Exit;                                              // Klammern/Operatoren
  AInfo.RhsLow := Rhs;
  Result       := True;
end;

// Huerde H1 - sieht das Zuweisungsziel wie ein Event aus?
// Der Typ des Ziels ist hier grundsaetzlich NICHT verfuegbar: 'inherited X'
// adressiert eine Property der VORFAHREN-Klasse, die praktisch immer in einer
// anderen Unit (VCL/FMX) deklariert ist. Bleibt die Delphi-Namenskonvention:
// Events heissen 'On' + Grossbuchstabe. 'ItemHeight'/'Caption' erfuellen das
// nicht, 'Only...' wegen des Kleinbuchstabens ebenfalls nicht - beides ist die
// gewollte Richtung (kein Event erkannt => Gate aus => Fund bleibt).
function TargetLooksLikeEvent(const ALhs: string): Boolean;
begin
  Result := (Length(ALhs) >= 3)
        and (ALhs[1] = 'O') and (ALhs[2] = 'n')
        and CharInSet(ALhs[3], ['A'..'Z', '_']);
end;

function DirectParamCount(AMethod: TAstNode): Integer;
// nkParam-Kinder haengen direkt unter nkMethod (uParser2.ParseMethodSignature).
// Bewusst KEIN FindAll - das wuerde in Bodies/nested routines absteigen.
var
  i : Integer;
begin
  Result := 0;
  if AMethod = nil then Exit;
  for i := 0 to AMethod.Children.Count - 1 do
    if AMethod.Children[i].Kind = nkParam then Inc(Result);
end;

// Huerde H2 - ist der RHS-Bezeichner als parameterlose FUNKTION deklariert?
// Dann liefert er einen Wert und kann kein Event-Handler sein; die Zeile ist
// ein echter Aufruf ('inherited ItemHeight := MinItemHeight').
// Unbekannter RHS -> False (nicht als Aufruf belegbar, Gate bleibt zustaendig).
// In der Praxis unerreichbar: damit ueberhaupt ein Fund anstuende, muss der
// Name in VirtualByName (Direkt-Pfad) oder MethodByName (Helper-Pfad) stehen.
function RhsIsValueProducingCall(const ARhsLow: string;
  AMethodByName, AVirtualByName: TDictionary<string, TAstNode>): Boolean;
var
  Key : string;
  M   : TAstNode;
begin
  Result := False;
  Key := ARhsLow;
  if Key.StartsWith('self.') then Key := Copy(Key, 6, MaxInt);
  if Pos('.', Key) > 0 then Exit;       // Fremdobjekt-Qualifizierer: keine Aussage
  M := nil;
  if AMethodByName <> nil then AMethodByName.TryGetValue(Key, M);
  if (M = nil) and (AVirtualByName <> nil) then AVirtualByName.TryGetValue(Key, M);
  if M = nil then Exit;
  // TypeRef-Format: 'kind[:ret][;dir1;dir2]' (uParser2.ParseMethodDirectives).
  if not LowerCase(Trim(M.TypeRef)).StartsWith('function') then Exit;
  Result := DirectParamCount(M) = 0;
end;

// Zeilen-Map der Datei: Zeilennummer -> (Zuweisungsziel, zugewiesener
// RHS-Bezeichner) des 'inherited <Lhs> := <RhsIdent>'-Musters. Das Ziel wird
// mitgefuehrt, weil Huerde H1 es braucht. ACache wird beim ersten Aufruf
// gefuellt (nil = noch nicht gelesen) und vom Aufrufer freigegeben.
// AContext steht hier nicht zur Verfuegung (SCA048 ist als 3-Parameter-Detektor
// registriert) -> Prozess-Cache bzw. Direkt-Load; ist die Datei nicht lesbar
// (In-Memory-Pfad), bleibt die Map leer und der Gate ist inert (fail-open).
//
// True nur, wenn ACallName GENAU der zugewiesene RHS-Bezeichner ist. Damit
// bleibt ein echter Aufruf auf derselben Zeile ('inherited OnShow := Foo; Init;'
// oder 'inherited Value := ComputeIt(Self);') ein Treffer (Review 2026-07-31).
// Zusaetzlich muessen H1 (Ziel sieht aus wie ein Event) und H2 (RHS ist keine
// parameterlose Funktion) gelten - siehe Nachschaerfungs-Block oben.
function IsInheritedEventAssignPhantom(const FileName: string; LineNo: Integer;
  const ACallName: string;
  AMethodByName, AVirtualByName: TDictionary<string, TAstNode>;
  var ACache: TDictionary<Integer, TInhAssignInfo>): Boolean;
var
  Lines            : TStringList;
  Cached           : Boolean;
  i                : Integer;
  InBrace, InParen : Boolean;
  Info             : TInhAssignInfo;
  NameLow          : string;
begin
  Result := False;
  if ACache = nil then
  begin
    ACache := TDictionary<Integer, TInhAssignInfo>.Create;
    Lines := AcquireLines(FileName, Cached, nil);
    if Lines <> nil then
    try
      InBrace := False;
      InParen := False;
      for i := 0 to Lines.Count - 1 do
        if LineIsInheritedPropertyAssign(
             StripCodeLine(Lines[i], InBrace, InParen), Info) then
          // Genau ein Eintrag je Zeile: geprueft wird nur das zeilenfuehrende
          // 'inherited'; eine zweite Zuweisung derselben Zeile bleibt ungegatet.
          ACache.AddOrSetValue(i + 1, Info);
    finally
      ReleaseLines(Lines, Cached);
    end;
  end;
  if not ACache.TryGetValue(LineNo, Info) then Exit;
  NameLow := LowerCase(Trim(ACallName));
  // Argumentliste im Knotennamen = echter Aufruf, nie die Phantom-Kante.
  if Pos('(', NameLow) > 0 then Exit;
  if NameLow <> Info.RhsLow then Exit;
  // H1: nur ein Event-artiges Ziel darf ueberhaupt gegatet werden.
  // 'inherited ItemHeight := MinItemHeight' (JvCombos.pas:672) faellt hier raus.
  if not TargetLooksLikeEvent(Info.Lhs) then Exit;
  // H2: eine parameterlose Funktion auf der RHS ist ein Wert-Aufruf, kein
  // Methodenzeiger - doppelte Absicherung desselben TP-Musters.
  if RhsIsValueProducingCall(Info.RhsLow, AMethodByName, AVirtualByName) then Exit;
  Result := True;
end;

function IsConstructor(MethodNode: TAstNode): Boolean;
begin
  Result := LowerCase(Trim(MethodNode.TypeRef)).StartsWith('constructor');
end;

function HasDirective(MethodNode: TAstNode; const Dir: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(MethodNode.TypeRef);
  Result := (Pos(';' + Dir, Lower) > 0);
end;

function IsVirtualLike(MethodNode: TAstNode): Boolean;
// `dynamic` ist semantisch ebenfalls virtual-like, der Lexer kennt das
// Keyword aktuell aber nicht (kein tkKwDynamic, kommt als tkIdent durch
// und wird von IsMethodDirective nicht als Direktive konsumiert). Wenn
// der Lexer um `dynamic` erweitert wird, hier die Liste ergaenzen.
begin
  Result := HasDirective(MethodNode, 'virtual')
         or HasDirective(MethodNode, 'override');
end;

function ExtractCallTarget(const CallName: string): string;
// Aus `Self.Init` -> `Init`, aus `Init(x)` -> `Init`, aus `FFoo.Bar` -> ''
// (Object-Call - nicht relevant).
var
  Trimmed : string;
  DotPos  : Integer;
  Lhs, Rhs: string;
  ParenPos: Integer;
begin
  Result  := '';
  Trimmed := Trim(CallName);
  if Trimmed = '' then Exit;

  // Argument-Liste wegschneiden
  ParenPos := Pos('(', Trimmed);
  if ParenPos > 0 then
    Trimmed := Copy(Trimmed, 1, ParenPos - 1);

  DotPos := Pos('.', Trimmed);
  if DotPos = 0 then Exit(Trim(Trimmed));   // einfacher Call

  Lhs := LowerCase(Trim(Copy(Trimmed, 1, DotPos - 1)));
  Rhs := Trim(Copy(Trimmed, DotPos + 1, MaxInt));
  if Lhs = 'self' then Exit(Rhs);
  // Anderes Objekt - nicht relevant
end;

// Folgt rekursiv den Calls einer non-virtual Methode bis ein virtual
// erreicht wird oder das Depth-Limit greift. ChainOut akkumuliert die
// Call-Kette (lowercase-Method-Namen) damit das Finding den vollen
// Pfad "Init -> DoSetup -> DoStuff" zeigen kann.
//
// 2026-06-18 (Audit_ErrorDetectors E-6 P1): Cross-Method-Helper-
// Detection. Vorher fand der Detector nur direkte Virtual-Calls im
// Ctor. Helper-Pattern ueberging er:
//   constructor TFoo.Create; begin Init; end;   // Init = non-virtual
//   procedure TFoo.Init;     begin DoStuff; end; // DoStuff = virtual!
// → Bug, weil aufrufende Subklasse DoStuff overriden kann.
const
  MAX_CHAIN_DEPTH = 5;   // bei deeper Helpers wird's pathologisch

function FindVirtualInChain(StartName: string;
  MethodByName: TDictionary<string, TAstNode>;
  VirtualByName: TDictionary<string, TAstNode>;
  Visited, ChainOut: TList<string>;
  Depth: Integer): TAstNode;
var
  Method      : TAstNode;
  CallList    : TList<TAstNode>;
  Call        : TAstNode;
  Target, Low : string;
  VMethod     : TAstNode;
  RecurResult : TAstNode;
begin
  Result := nil;
  if Depth > MAX_CHAIN_DEPTH then Exit;
  if Visited.IndexOf(StartName) >= 0 then Exit;   // Zyklus
  Visited.Add(StartName);

  // Method existiert in dieser Klasse? Sonst koennen wir nicht weiter folgen.
  if not MethodByName.TryGetValue(StartName, Method) then Exit;

  CallList := Method.FindAll(nkCall);
  try
    for Call in CallList do
    begin
      Target := ExtractCallTarget(Call.Name);
      if Target = '' then Continue;
      Low := LowerCase(Target);
      if Low.StartsWith('inherited') then Continue;

      // Direkt-Hit: Helper ruft virtual-Method.
      if VirtualByName.TryGetValue(Low, VMethod) then
      begin
        ChainOut.Add(Low);
        Exit(VMethod);
      end;
      // Nicht-virtual, aber in der Klasse - rekursiv folgen.
      if MethodByName.ContainsKey(Low) then
      begin
        ChainOut.Add(Low);
        RecurResult := FindVirtualInChain(Low, MethodByName, VirtualByName,
          Visited, ChainOut, Depth + 1);
        if Assigned(RecurResult) then Exit(RecurResult);
        // Sackgasse - Element aus Chain wieder rausnehmen.
        ChainOut.Delete(ChainOut.Count - 1);
      end;
    end;
  finally
    CallList.Free;
  end;
end;

class procedure TVirtualCallInCtorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  ClassList       : TList<TAstNode>;   // 2026-07-31 umbenannt (war 'Classes') -
                                        // die Unit zieht jetzt System.Classes,
                                        // ein gleichnamiger Local verdeckte den
                                        // Unit-Namensraum.
  ClassNode       : TAstNode;
  VirtualByName   : TDictionary<string, TAstNode>;
  MethodByName    : TDictionary<string, TAstNode>;
  Methods         : TList<TAstNode>;
  M, Ctor, Call   : TAstNode;
  CtorList        : TList<TAstNode>;
  CallList        : TList<TAstNode>;
  Target, LowName : string;
  VMethod         : TAstNode;
  AlreadyReported : TList<string>;
  RepKey, Msg     : string;
  ClassImplCtors  : TList<TAstNode>;
  Visited, Chain  : TList<string>;
  // FP-Gate 2026-07-31 (Event-Zuweisung): Zeile -> Zuweisungsziel + zugewiesener
  // RHS-Bezeichner, lazy befuellt.
  InhAssignLines  : TDictionary<Integer, TInhAssignInfo>;
begin
  InhAssignLines := nil;
  ClassList := UnitNode.FindAll(nkClass);
  try
    for ClassNode in ClassList do
    begin
      VirtualByName := TDictionary<string, TAstNode>.Create;
      MethodByName  := TDictionary<string, TAstNode>.Create;
      try
        // Alle virtuellen + ALLE Methoden der Klasse einsammeln.
        // MethodByName brauchen wir fuer den Cross-Helper-Walk.
        Methods := ClassNode.FindAll(nkMethod);
        try
          for M in Methods do
          begin
            LowName := LowerCase(M.Name);
            if not MethodByName.ContainsKey(LowName) then
              MethodByName.Add(LowName, M);
            if IsVirtualLike(M) and not VirtualByName.ContainsKey(LowName) then
              VirtualByName.Add(LowName, M);
          end;
        finally
          Methods.Free;
        end;
        if VirtualByName.Count = 0 then Continue;

        // ABER: MethodByName muss auch die Top-Level-Impls enthalten
        // (Methods werden im Klassen-Subtree gefunden - meist nur Headers).
        // Wir nehmen Top-Level-nkMethod und matchen via "<Klasse>.<Name>"-Prefix.
        CtorList := UnitNode.FindAll(nkMethod);
        try
          for M in CtorList do
            if LowerCase(M.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
            begin
              var DotPos := LastDelimiter('.', M.Name);
              LowName := LowerCase(Copy(M.Name, DotPos + 1, MaxInt));
              // Overwrite OK - wir wollen das Impl (mit Body) statt der
              // Klassen-Subtree-Header-Node.
              MethodByName.AddOrSetValue(LowName, M);
            end;
        finally
          CtorList.Free;
        end;

        // Constructor-Impls finden.
        ClassImplCtors := TList<TAstNode>.Create;
        try
          CtorList := UnitNode.FindAll(nkMethod);
          try
            for Ctor in CtorList do
              if IsConstructor(Ctor) and
                 LowerCase(Ctor.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
                ClassImplCtors.Add(Ctor);
          finally
            CtorList.Free;
          end;

          AlreadyReported := TList<string>.Create;
          try
            for Ctor in ClassImplCtors do
            begin
              var CtorSimpleLow := LowerCase(Ctor.Name);
              var CtorDotPos := LastDelimiter('.', CtorSimpleLow);
              if CtorDotPos > 0 then
                CtorSimpleLow := Copy(CtorSimpleLow, CtorDotPos + 1, MaxInt);

              CallList := Ctor.FindAll(nkCall);
              try
                for Call in CallList do
                begin
                  Target := ExtractCallTarget(Call.Name);
                  if Target = '' then Continue;
                  LowName := LowerCase(Target);
                  if LowName.StartsWith('inherited') then Continue;
                  if LowName = CtorSimpleLow then Continue;

                  // Direkt-Hit (alter Pfad)
                  if VirtualByName.TryGetValue(LowName, VMethod) then
                  begin
                    // FP-Guard (2026-06-29): Ziel ist selbst ein Konstruktor
                    // (delegating-ctor `CreateFrom; begin Create; ... end`) - ein
                    // virtueller Konstruktor-Aufruf konstruiert VOLLSTAENDIG, kein
                    // half-init-Self. Nur virtuelle PROZEDUREN sind der Anti-Pattern.
                    if IsConstructor(VMethod) then Continue;
                    // FP-Gate (2026-07-31): Phantom-nkCall aus
                    // 'inherited <Event> := <Handler>;' - keine Call-Kante.
                    // Nur der zugewiesene Handler selbst wird verworfen
                    // (Call.Name, nicht Call.Line allein - Review 2026-07-31),
                    // und nur wenn Ziel wie ein Event aussieht UND der RHS
                    // keine parameterlose Funktion ist (Nachschaerfung).
                    if IsInheritedEventAssignPhantom(FileName, Call.Line,
                         Call.Name, MethodByName, VirtualByName,
                         InhAssignLines) then Continue;
                    RepKey := Ctor.Name + '|' + LowName + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Format('Virtual method "%s" called from constructor "%s" ' +
                             '- override runs on half-initialized Self',
                        [VMethod.Name, Ctor.Name]),
                      fkVirtualCallInCtor));
                    Continue;
                  end;

                  // Cross-Helper-Hit: non-virtual Call, aber in dieser Klasse.
                  // Folge der Kette bis virtual oder Depth/Cycle-Limit.
                  if not MethodByName.ContainsKey(LowName) then Continue;
                  Visited := TList<string>.Create;
                  Chain   := TList<string>.Create;
                  try
                    Chain.Add(LowName);   // Erster Helper im Chain
                    VMethod := FindVirtualInChain(LowName, MethodByName,
                      VirtualByName, Visited, Chain, 1);
                    if not Assigned(VMethod) then Continue;
                    if IsConstructor(VMethod) then Continue;  // delegating-ctor, kein half-init
                    // FP-Gate (2026-07-31): Phantom-nkCall aus
                    // 'inherited <Event> := <Handler>;' - der Handler laeuft
                    // erst beim Event-Feuern, nicht im Ctor (JvThread.pas:409:
                    // 'inherited OnShow := ReplaceFormShow' -> Helper-Kette
                    // ReplaceFormShow -> CreateFormControls). Nur der
                    // zugewiesene Handler selbst wird verworfen (Review
                    // 2026-07-31: Call.Name statt Call.Line allein), und nur
                    // unter H1+H2 (Nachschaerfung 2026-07-31).
                    if IsInheritedEventAssignPhantom(FileName, Call.Line,
                         Call.Name, MethodByName, VirtualByName,
                         InhAssignLines) then Continue;

                    RepKey := Ctor.Name + '|' + LowerCase(VMethod.Name) + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);

                    Msg := Format('Virtual method "%s" reachable from ' +
                                  'constructor "%s" via helper chain: %s',
                      [VMethod.Name, Ctor.Name, string.Join(' -> ', Chain.ToArray)]);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Msg, fkVirtualCallInCtor));
                  finally
                    Visited.Free;
                    Chain.Free;
                  end;
                end;
              finally
                CallList.Free;
              end;
            end;
          finally
            AlreadyReported.Free;
          end;
        finally
          ClassImplCtors.Free;
        end;
      finally
        VirtualByName.Free;
        MethodByName.Free;
      end;
    end;
  finally
    ClassList.Free;
    InhAssignLines.Free;   // nil-sicher (TObject.Free prueft Self)
  end;
end;

end.
