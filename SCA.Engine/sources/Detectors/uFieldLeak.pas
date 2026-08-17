unit uFieldLeak;

// Detektor fuer Klassen-Feld-Leaks im Create/Destroy-Pattern.
//
// Erkennt:
//   FField := TLeakyClass.Create im Konstruktor + KEIN Free im Destruktor
//   -> Feld lebt so lange wie das Objekt der Klasse, wird aber nicht aufgeraeumt
//      = Speicherleck pro Instanz der Klasse
//
// Beispiel:
//   TFoo = class
//   private FList: TStringList;
//   public  constructor Create; destructor Destroy; override;
//   end;
//
//   constructor TFoo.Create;       // <-- FList wird hier erzeugt
//   begin
//     FList := TStringList.Create;
//   end;
//
//   destructor TFoo.Destroy;       // <-- FList.Free FEHLT
//   begin
//     inherited;
//   end;
//
// Begrenzungen:
//   - Nur direkt im Konstruktor erzeugte Felder werden geprueft
//   - "Freigeben" akzeptiert: FField.Free, FField.Destroy, FreeAndNil(FField)
//   - Wird das Feld an einen ObjectList-Owner uebergeben, koennen wir das
//     nicht erkennen (-> potenziell False-Positive). Per // noinspection
//     unterdrueckbar.
//
// Ownership-Transfer (kein Befund):
//   FField := X.Create(Self|AOwner|Owner)
//     -> TComponent-Tree: Owner.DestroyComponents gibt das Feld frei.
//        Standard-VCL-Pattern (TTimer, TAction, TPanel, TButton, etc.
//        die im Konstruktor erstellt und dem Owning-Component zugeordnet
//        werden). Free im Destruktor waere redundant.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uLeakDetector2, uAnalyzeContext,
  uDetectorUtils;   // ContainsWholeWordLower fuer IsHandedToOwner

type
  TFieldLeakDetector = class
  public
    // AContext (TD-1 2c): an TLeakDetector2.IsLeakyType durchgereicht, damit
    // FieldLeak dieselbe (Auto-Discovery-erweiterte) LeakyClasses-Liste sieht
    // wie der Haupt-Leak-Detektor. Default =nil -> Global-Fallback (Single-File).
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    class function FindMethod(UnitNode: TAstNode; const Kind: string;
      const ClassName: string): TAstNode; static;
    // Parser-Gate-Backlog 2026-07-31 (4e/1): Freigabe in 'BeforeDestruction'
    // statt in 'Destroy'. Delphi ruft BeforeDestruction GARANTIERT vor Destroy
    // (TObject.Free -> BeforeDestruction -> Destroy), ein dort freigegebenes
    // Feld ist also genauso aufgeraeumt. Sucht die Implementierung
    // '<Klasse>.<MethodNameLow>' ueber EXAKTEN Namensvergleich (nicht ueber
    // TypeRef, denn BeforeDestruction ist eine procedure, kein destructor).
    class function FindMethodNamed(UnitNode: TAstNode;
      const ClassName, MethodNameLow: string): TAstNode; static;
    class function HasFieldCreate(MethodNode: TAstNode;
      const FieldNameLow: string): Boolean; static;
    // True wenn das Feld via TComponent-Owner-Pattern erzeugt wird:
    //   FField := SomeClass.Create(Self)
    //   FField := SomeClass.Create(AOwner)
    //   FField := SomeClass.Create(Owner)
    // In allen Faellen registriert SomeClass.Create() das neue Objekt in der
    // FComponents-Liste des Owners; inherited Destroy => DestroyComponents
    // gibt es automatisch frei. Free im Destruktor waere redundant.
    class function IsCreatedWithComponentOwner(MethodNode: TAstNode;
      const FieldNameLow: string): Boolean; static;
    // True wenn das Feld im Konstruktor als ARGUMENT an einen Call uebergeben
    // wird ('AddAttribute(FField)', 'FList.Add(FField)', 'Register(FField)').
    // Der Empfaenger kann die Ownership uebernehmen und das Feld in SEINEM
    // Destruktor freigeben - ein fehlendes Free im eigenen Destroy ist dann
    // kein Leck. Genau die im Unit-Kopf dokumentierte FP-Quelle
    // ("Wird das Feld an einen ObjectList-Owner uebergeben, koennen wir das
    // nicht erkennen").
    class function IsHandedToOwner(MethodNode: TAstNode;
      const FieldNameLow: string): Boolean; static;
  end;

implementation

uses
  // Pre-Build-Review 2026-07-31 (Fund uFieldLeak.pas:333): Stufe 1 des
  // Schwester-Feld-Owner-Gates braucht den Cross-Unit-Typindex, um eine
  // TComponent-Ahnenlinie zu BEWEISEN bzw. zu WIDERLEGEN. Nur implementation-
  // uses, damit die Interface-Abhaengigkeiten der Unit unveraendert bleiben.
  uTypeIndex;

// noinspection-file ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function TFieldLeakDetector.FindMethod(UnitNode: TAstNode;
  const Kind, ClassName: string): TAstNode;
// Sucht eine Implementations-Methode mit gegebenem TypeRef ('constructor' bzw.
// 'destructor') und Name 'ClassName.<Methodenname>'. nil wenn nicht da.
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  ClsLow  : string;
begin
  Result := nil;
  ClsLow := ClassName.ToLower + '.';
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      if SameText(M.TypeRef, Kind) and
         M.Name.ToLower.StartsWith(ClsLow) then
        Exit(M);
  finally
    Methods.Free;
  end;
end;

class function TFieldLeakDetector.FindMethodNamed(UnitNode: TAstNode;
  const ClassName, MethodNameLow: string): TAstNode;
// Implementations-Methode '<ClassName>.<MethodNameLow>' (exakter Name,
// case-insensitiv). nil wenn nicht vorhanden. Gegenstueck zu FindMethod, das
// ueber den TypeRef ('constructor'/'destructor') sucht - fuer
// BeforeDestruction gibt es keinen eigenen TypeRef.
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Target  : string;
begin
  Result := nil;
  if (UnitNode = nil) or (ClassName = '') then Exit;
  Target := ClassName.ToLower + '.' + MethodNameLow;
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      if M.Name.ToLower = Target then
        Exit(M);
  finally
    Methods.Free;
  end;
end;

class function TFieldLeakDetector.IsCreatedWithComponentOwner(
  MethodNode: TAstNode; const FieldNameLow: string): Boolean;
// Sucht im Konstruktor 'FField := X.Create(<Owner-Ausdruck>[, ...])' und
// prueft, ob das ERSTE Argument im Component-Tree wurzelt.
//
// Bis 2026-08-17 stand hier eine Liste aus sechs festen Mustern
// ('.create(self)', '.create(aowner,' ...). Sie traf nur den nackten
// Bezeichner und liess jede PFADFORM durch, obwohl sie denselben Baum
// bezeichnet - kanonisch 'TPopupMenu.Create(AOwner.Owner)'. Ein Owner ist
// ein Owner, egal ueber wieviele Punkte man ihn erreicht: der Empfaenger
// traegt das Kind in seine Components-Liste ein und gibt es in seinem
// Destruktor frei.
//
// Geprueft wird deshalb der WURZELBEZEICHNER des ersten Arguments, nicht
// der ganze Text. Die sechs Altmuster sind darin exakt enthalten (bei
// '(self)' ist die Wurzel 'self'); neu dazu kommen nur Pfade.
//
// Bewusst ENG gehalten - das ist eine Unterdrueckung im Error-Tier:
//   * nur die drei Wurzeln self/aowner/owner, keine Namensheuristik auf
//     '*owner*' (sonst faengt 'ownerless' oder 'FOwnerForm' mit),
//   * nur das ERSTE Argument (das ist die Owner-Position von
//     TComponent.Create),
//   * Feldwurzeln wie 'TTimer.Create(FPanel)' bleiben ausdruecklich
//     DRAUSSEN - ob FPanel selbst freigegeben wird, entscheidet
//     IsOwnedByFreedSiblingField bzw. IsOwnedByComponentChain, und diese
//     Frage gehoert nicht hierher.
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  LHSLow  : string;
  TypeLow : string;
  RootLow : string;

  function FirstArgRootLow(const RhsLow: string): string;
  // Wurzelbezeichner des ersten Arguments von '.create(' - also alles bis
  // zum ersten '.', '[', '^', ',' oder ')'. Leer, wenn es kein '.create('
  // gibt oder die Klammer sofort schliesst (parameterloser Ctor).
  var
    p, i : Integer;
  begin
    Result := '';
    p := Pos('.create(', RhsLow);
    if p = 0 then Exit;
    i := p + Length('.create(');
    while (i <= Length(RhsLow)) and (RhsLow[i] = ' ') do Inc(i);
    p := i;
    while (i <= Length(RhsLow)) and
          (TLeakDetector2.IsIdentChar(RhsLow[i])) do Inc(i);
    Result := Copy(RhsLow, p, i - p);
  end;

begin
  Result := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      LHSLow := A.Name.ToLower;
      if (LHSLow <> FieldNameLow) and
         (LHSLow <> 'self.' + FieldNameLow) then Continue;
      TypeLow := A.TypeRef.ToLower;
      RootLow := FirstArgRootLow(TypeLow);
      if (RootLow = 'self') or (RootLow = 'aowner') or (RootLow = 'owner') then
        Exit(True);
    end;
  finally
    Assigns.Free;
  end;
end;

class function TFieldLeakDetector.IsHandedToOwner(
  MethodNode: TAstNode; const FieldNameLow: string): Boolean;
// Ownership-Transfer im Konstruktor. Wird das erzeugte Feld an einen Call
// UEBERGEBEN, kann der Empfaenger die Ownership nehmen und es selbst freigeben;
// dann ist ein fehlendes Free im eigenen Destruktor KEIN Leak. Der Unit-Kopf
// fuehrt genau das als bekannte FP-Quelle ("an einen ObjectList-Owner
// uebergeben ... koennen wir nicht erkennen") - bislang unvermeidbar.
//
// Real-World-Beleg (Recall-Messung 2026-07-15, tools/recall_mutate.py): mit
// aktiver Custom-Class-Discovery ([Detectors]/AutoDiscoverClasses=1) explodierte
// genau diese Klasse auf +2410 SCA001-Funde. Kanonisch die SynEdit-Highlighter:
//   fSpaceAttri := TSynHighlighterAttributes.Create(...);
//   AddAttribute(fSpaceAttri);          // -> fAttributes.AddObject(Name, Attri)
// und TSynCustomHighlighter.Destroy raeumt via FreeHighlighterAttributes auf.
// Kein Leck - der Fund war ein FP.
//
// NUR Argument-Vorkommen zaehlen, NICHT der Receiver: 'FField.Style := x' oder
// 'FField.DoIt(y)' sind keine Uebergabe. Darum wird ausschliesslich der Text AB
// der ersten '(' geprueft. Wortgrenzen-Match, damit 'FList' nicht in
// 'FListView' trifft.
//
// KONSERVATIV (precision-first, konsistent mit dem restlichen Detektor): wir
// koennen nicht beweisen, DASS der Empfaenger die Ownership nimmt - aber wir
// koennen das Leak dann auch nicht mehr beweisen. Im Zweifel nicht melden.
// Preis: ein echtes Leck, dessen Feld zufaellig irgendwo als Arg auftaucht,
// entgeht uns (FN). Das ist derselbe Handel wie bei IsCreatedWithComponentOwner.
var
  Calls  : TList<TAstNode>;
  C      : TAstNode;
  ArgsLow: string;
  P      : Integer;
begin
  Result := False;
  if FieldNameLow = '' then Exit;
  Calls := MethodNode.FindAll(nkCall);
  try
    for C in Calls do
    begin
      ArgsLow := C.Name.ToLower;
      P := Pos('(', ArgsLow);
      if P = 0 then Continue;                        // Call ohne Klammer -> kein Arg
      ArgsLow := Copy(ArgsLow, P + 1, MaxInt);       // nur die Argument-Seite
      if TDetectorUtils.ContainsWholeWordLower(FieldNameLow, ArgsLow) then
        Exit(True);
    end;
  finally
    Calls.Free;
  end;
end;

class function TFieldLeakDetector.HasFieldCreate(MethodNode: TAstNode;
  const FieldNameLow: string): Boolean;
// Sucht im Konstruktor eine Zuweisung der Form 'FField := <Typ>.Create(...)'.
// Akzeptiert sowohl 'FField' als auch 'Self.FField' als LHS.
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  LHSLow  : string;
  TypeLow : string;
  p       : Integer;
begin
  Result := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      LHSLow := A.Name.ToLower;
      // Match auf 'fname' oder 'self.fname'
      if (LHSLow <> FieldNameLow) and
         (LHSLow <> 'self.' + FieldNameLow) then Continue;

      TypeLow := A.TypeRef.ToLower;
      p := Pos('.create', TypeLow);
      if p > 0 then
      begin
        var pRight := p + 7;
        if (pRight > Length(TypeLow)) or
           not TLeakDetector2.IsIdentChar(TypeLow[pRight]) then
          Exit(True);
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

function IsFreedViaAlias(Dtor: TAstNode; const FieldNameLow: string): Boolean;
// Erkennt das Alias-Free-Idiom im Destruktor:
//   L := FField;  FField := nil;  L.Free;
// (haeufig um Re-Entrancy beim Teardown zu vermeiden - RemoveSubscriber-
// Callbacks greifen sonst in freed-Speicher). SearchFree findet nur ein
// direktes FField.Free; hier wird ueber die lokale Alias-Var L freigegeben.
// Heuristik: nkAssign `<bare-local> := FField` (RHS exakt das Feld), dann
// SearchFree auf die Alias-Var. Self-Scan-FP 2026-06-21 (uIDEWatchMode
// FSubscribers).
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  RhsLow, AliasLow : string;
  Dummy   : Boolean;
begin
  Result := False;
  if Dtor = nil then Exit;
  Assigns := Dtor.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      RhsLow := LowerCase(Trim(A.TypeRef));
      if (RhsLow = FieldNameLow) or (RhsLow = 'self.' + FieldNameLow) then
      begin
        AliasLow := LowerCase(Trim(A.Name));
        if (AliasLow <> '') and (Pos('.', AliasLow) = 0) and
           TLeakDetector2.SearchFree(Dtor, AliasLow, False, Dummy) then
          Exit(True);
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

function IsFreedViaPropertyAlias(Dtor, ClassNode: TAstNode;
  const FieldNameLow: string): Boolean;
// Erkennt die Freigabe ueber den PROPERTY-Alias:
//   property BlueElements: TList read FBlueElements write SetBlueElements;
//   destructor ... begin BlueElements.Free; end;
// Dieselbe Instanz, nur ueber den oeffentlichen Namen angesprochen -
// SearchFree sucht aber nach 'FBlueElements.Free' und findet nichts.
// Belegt im Korpus (JvExplorerBar und Verwandte), 8 Funde derselben Bauart.
//
// Warum ueber die NAMENSKONVENTION und nicht ueber den read-Spezifizierer:
// der Parser verwirft die read/write-Klausel (uParser2 ParseProperty ruft
// SkipToSemicolon), nkProperty traegt nur den Namen. Die Zuordnung
// 'FFoo' <-> 'Foo' ist damit die einzige verfuegbare - sie ist in Delphi
// aber so fest, dass die RTL selbst darauf aufbaut.
//
// Eng gehalten, es ist eine Unterdrueckung im Error-Tier - ALLE DREI
// Bedingungen muessen zutreffen:
//   1. der Feldname beginnt mit 'F' (sonst kein Alias-Kandidat),
//   2. die Klasse deklariert wirklich eine Property mit exakt dem
//      Restnamen - geraten wird nichts,
//   3. der Destruktor gibt genau diesen Namen frei.
// Restrisiko, bewusst getragen: eine Property 'Foo', die NICHT 'FFoo'
// liest, waehrend 'FFoo' leckt und der Destruktor 'Foo.Free' ruft. Dafuer
// muesste jemand die Konvention brechen UND den falschen Namen freigeben.
var
  PropLow : string;
  Props   : TList<TAstNode>;
  Pr      : TAstNode;
  Dummy   : Boolean;
begin
  Result := False;
  if (Dtor = nil) or (ClassNode = nil) then Exit;
  if (Length(FieldNameLow) < 2) or (FieldNameLow[1] <> 'f') then Exit;
  PropLow := Copy(FieldNameLow, 2, MaxInt);

  Props := ClassNode.FindAll(nkProperty);
  try
    for Pr in Props do
    begin
      if LowerCase(Trim(Pr.Name)) = PropLow then
      begin
        Result := TLeakDetector2.SearchFree(Dtor, PropLow, False, Dummy);
        Exit;
      end;
    end;
  finally
    Props.Free;
  end;
end;

{ ---- FP-Gates 30%-Real-World-Audit 2026-07-31 (FP-Klasse 3) ---------------- }
//
// "Ctor/Dtor-Paarung uebersieht indirekte Freigabe" (2/24 im Sample). Beide
// Gates sind MONOTON - sie koennen einen Fund nur unterdruecken.

// Erstes Top-Level-Argument eines '<Typ>.Create(...)'-Aufrufs (lowercase),
// '' wenn die RHS kein Konstruktoraufruf MIT Klammern ist. Klammer-Tiefe wird
// gezaehlt, damit 'Create(TFoo.Create(a,b), c)' nicht am inneren Komma splittet.
function FirstCreateArgLow(const ATypeRefLow: string): string;
var
  p, i, depth : Integer;
begin
  Result := '';
  p := Pos('.create(', ATypeRefLow);
  if p = 0 then Exit;
  i := p + 8;                       // hinter '.create('
  depth := 0;
  while i <= Length(ATypeRefLow) do
  begin
    if ATypeRefLow[i] = '(' then Inc(depth)
    else if ATypeRefLow[i] = ')' then
    begin
      if depth = 0 then Break;
      Dec(depth);
    end
    else if (ATypeRefLow[i] = ',') and (depth = 0) then Break;
    Inc(i);
  end;
  Result := Trim(Copy(ATypeRefLow, p + 8, i - (p + 8)));
  // ATypeRefLow ist bereits lowercase -> direkter Vergleich statt StartsText
  // (haelt die uses-Liste dieser Unit unveraendert).
  if Copy(Result, 1, 5) = 'self.' then Result := Trim(Copy(Result, 6, MaxInt));
end;

// Datenklassen-Sperrliste (Pre-Build-Review 2026-07-31, Fund uFieldLeak.pas:333).
// 1:1 uebernommen aus uLeakDetector2.IsComponentOwnerCreate (Stufe-2-Liste),
// ergaenzt um die Basisklasse 'tstream'. Zwei Rollen:
//   * als ERZEUGTE Klasse: das erste Ctor-Argument sind DATEN (Quellstream,
//     Dateiname, Text), nie ein Owner - 'TStreamReader.Create(FStream)' macht
//     FStream NICHT zum Besitzer des Readers.
//   * als OWNER-Feldtyp: eine Datenklasse besitzt niemals einen Component-Tree
//     und gibt beim Free nichts mit frei.
const
  FL_DATA_CLASSES : array[0..19] of string = (
    'tfilestream', 'tstringstream', 'tmemorystream', 'tbytesstream',
    'tresourcestream', 'tbufferedfilestream', 'thandlestream', 'tstream',
    'tstringlist', 'tstringbuilder', 'tinifile', 'tmeminifile',
    'tregistryinifile', 'tstreamreader', 'tstreamwriter',
    'tbinaryreader', 'tbinarywriter', 'tzipfile', 'tencoding',
    'tregistry');

function IsDataClassLow(const ATypeLow: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if ATypeLow = '' then Exit;
  for i := Low(FL_DATA_CLASSES) to High(FL_DATA_CLASSES) do
    if ATypeLow = FL_DATA_CLASSES[i] then Exit(True);
end;

// Nackter Typname (lowercase) ohne Unit-Qualifier und ohne Generic-Suffix.
// 'Vcl.ExtCtrls.TPanel' -> 'tpanel', 'TObjectList<TFoo>' -> 'tobjectlist'.
// Generics werden ZUERST gekappt, damit ein Punkt INNERHALB der Typargumente
// ('TDictionary<string, System.TObject>') nicht als Unit-Trenner zaehlt.
function BareTypeLow(const ATypeRef: string): string;
var
  p : Integer;
begin
  Result := Trim(ATypeRef).ToLower;
  p := Pos('<', Result);
  if p > 0 then Result := Trim(Copy(Result, 1, p - 1));
  p := LastDelimiter('.', Result);
  if p > 0 then Result := Trim(Copy(Result, p + 1, MaxInt));
end;

// Klassenname eines '<Typ>.Create(...)'-Aufrufs (lowercase, normalisiert),
// '' wenn die RHS kein Konstruktoraufruf MIT Klammern ist. Gegenstueck zu
// FirstCreateArgLow; erwartet ebenfalls eine bereits lowercase RHS.
function CreateClassLow(const ATypeRefLow: string): string;
var
  p : Integer;
begin
  Result := '';
  p := Pos('.create(', ATypeRefLow);
  if p = 0 then Exit;
  Result := BareTypeLow(Copy(ATypeRefLow, 1, p - 1));
end;

// True, wenn der Cross-Unit-Typindex den Typ AUFLOEST und er dabei KEIN
// TComponent-Nachfahre ist. Unbekannte Typen liefern False (kein Veto) -
// dann entscheidet die Datenklassen-Sperrliste.
function ResolvedNonComponent(ATypeIndex: TTypeIndex;
  const ATypeLow: string): Boolean;
begin
  Result := False;
  if (ATypeIndex = nil) or (ATypeLow = '') then Exit;
  if ATypeIndex.IsDescendantOf(ATypeLow, 'tcomponent') then Exit;
  Result := (ATypeIndex.TypeKindOf(ATypeLow) <> tkiUnknown) or
            (ATypeIndex.ParentOf(ATypeLow) <> '');
end;

// FP-Klasse 3a: 'FEndTimer := TTimer.Create(FPanel)' - Owner ist ein ANDERES
// Feld derselben Klasse, das im Destroy freigegeben wird ('FreeAndNil(FPanel)',
// HeidiSQL grideditlinks.pas:130). Der Owner raeumt seinen Component-Tree beim
// Free mit ab; ein eigenes Free waere redundant. IsCreatedWithComponentOwner
// kennt nur die kanonischen Bezeichner Self/AOwner/Owner.
// STRENG: der Owner-Ausdruck muss ein blanker Identifier sein UND im Destroy
// NACHWEISLICH freigegeben werden. Ohne diesen Nachweis bleibt der Fund stehen
// (kein Blanket-Gate auf "irgendein Argument").
//
// NACHGESCHAERFT 2026-07-31 (Pre-Build-Review, Fund uFieldLeak.pas:333
// "keine Datenklassen-Sperrliste"): 'FReader := TStreamReader.Create(FStream)'
// mit 'FStream.Free' im Destroy ist KEINE Owner-Beziehung - TStreamReader,
// TStreamWriter, TBinaryReader/Writer und TZipFile KONSUMIEREN den Stream, sie
// werden von ihm nicht besessen. Ohne Sperre stellte das Gate dort ein echtes
// Leak (lsError) still. Das Schwestergate uLeakDetector2.IsComponentOwnerCreate
// hat genau dafuer eine DATA_CLASSES-Sperrliste UND verlangt zusaetzlich ein
// DOTTED erstes Argument. Das dotted-Kriterium ist hier nicht uebertragbar (der
// Schwester-Feld-Owner IST per Definition ein blanker Identifier); an seine
// Stelle treten drei gleichwertig strenge Nachweise:
//   (1) der Owner-Bezeichner muss ein FELD DERSELBEN Klasse sein (erst damit
//       ist sein deklarierter Typ ueberhaupt bekannt),
//   (2) weder die erzeugte Klasse noch der Owner-Feldtyp darf eine bekannte
//       Datenklasse sein (FL_DATA_CLASSES),
//   (3) loest der Cross-Unit-Typindex einen der beiden Typen auf und ist er
//       KEIN TComponent-Nachfahre, greift das Gate nicht.
// Alle drei Zusaetze koennen das Gate nur ENGER machen - Monotonie bleibt
// gewahrt (weniger Unterdrueckungen, niemals zusaetzliche Funde).
function IsOwnedByFreedSiblingField(Ctor, Dtor, ClassNode: TAstNode;
  const FieldNameLow: string; AContext: TAnalyzeContext): Boolean;
var
  Assigns, Fields : TList<TAstNode>;
  A, Fld  : TAstNode;
  LHSLow, OwnerLow, ClassLow, OwnerTypeLow : string;
  i       : Integer;
  Dummy   : Boolean;
  Clean   : Boolean;
  OwnerIsField : Boolean;
  TI      : TTypeIndex;
begin
  Result := False;
  if (Ctor = nil) or (Dtor = nil) or (ClassNode = nil) then Exit;
  TI := CtxTypeIndex(AContext);      // nil im Single-File-/Testpfad
  Assigns := Ctor.FindAll(nkAssign);
  Fields  := nil;
  try
    Fields := ClassNode.FindAll(nkField);
    for A in Assigns do
    begin
      LHSLow := A.Name.ToLower;
      if (LHSLow <> FieldNameLow) and
         (LHSLow <> 'self.' + FieldNameLow) then Continue;
      OwnerLow := FirstCreateArgLow(A.TypeRef.ToLower);
      if (OwnerLow = '') or (OwnerLow = 'nil') then Continue;
      if OwnerLow = FieldNameLow then Continue;
      Clean := True;
      for i := 1 to Length(OwnerLow) do
        if not TLeakDetector2.IsIdentChar(OwnerLow[i]) then
        begin Clean := False; Break; end;
      if not Clean then Continue;

      // (2a) Erzeugte Klasse: Datenklassen nehmen DATEN als erstes Argument,
      //      keinen Owner. Ein leerer Klassenkopf beweist nichts -> kein Gate.
      ClassLow := CreateClassLow(A.TypeRef.ToLower);
      if (ClassLow = '') or IsDataClassLow(ClassLow) then Continue;

      // (1) Owner muss ein FELD derselben Klasse sein - sonst ist er kein
      //     Schwester-Feld und sein Typ nicht bestimmbar.
      OwnerIsField := False;
      OwnerTypeLow := '';
      for Fld in Fields do
        if Fld.Name.ToLower = OwnerLow then
        begin
          OwnerIsField := True;
          OwnerTypeLow := BareTypeLow(Fld.TypeRef);
          Break;
        end;
      if not OwnerIsField then Continue;

      // (2b) Owner-Feldtyp: eine Datenklasse besitzt keinen Component-Tree.
      if IsDataClassLow(OwnerTypeLow) then Continue;

      // (3) Typindex-Veto: aufloesbar UND kein TComponent -> keine Ownership.
      if (TI <> nil) and not TI.IsEmpty then
      begin
        if ResolvedNonComponent(TI, ClassLow) then Continue;
        if ResolvedNonComponent(TI, OwnerTypeLow) then Continue;
      end;

      if TLeakDetector2.SearchFree(Dtor, OwnerLow, False, Dummy) then
        Exit(True);                  // finally gibt Fields/Assigns frei
    end;
  finally
    Fields.Free;
    Assigns.Free;
  end;
end;

{ ---- FP-Gate Parser-Gate-Backlog 2026-07-31 (4e/1, FP-Klasse 4) ------------ }
//
// "Transitive Component-Ownership OHNE Destruktor".
//   FPanel1 := TPanel.Create(Self);      // Wurzel = Self
//   FPanel2 := TPanel.Create(FPanel1);   // haengt unter FPanel1
//   FGamma  := TImage.Create(FPanel2);   // haengt unter FPanel2
// (jvcl JvGammaPanel.pas 61/63/64; die Klasse hat GAR KEINEN Destruktor, das
// Schwester-Feld-Gate IsOwnedByFreedSiblingField kann dort strukturell nie
// feuern, weil es Dtor <> nil verlangt.)
// Zweiter belegter Fall ohne Feld-Bezug: jvcl JvCombobox.pas:261
//   FPopup   := TJvPrivForm.Create(Self);       // FPopup ist ein GEERBTES Feld
//   FListBox := TJvCheckListBox.Create(FPopup); // Owner nicht in dieser Klasse
// Die Kette braucht deshalb KEINE Feldzugehoerigkeit - der Beweis steckt
// vollstaendig in den Zuweisungen DESSELBEN Konstruktors: wer unter einem
// Objekt haengt, das seinerseits Self (bzw. AOwner/Owner/Application) als
// Owner hat, wird vom Component-Tree der Wurzel mit freigegeben.
//
// STRENGE (jede Huerde hat einen belegten Grund):
//   (H1) mindestens EIN Zwischenobjekt - der direkte Fall
//        'F := X.Create(Self)' gehoert IsCreatedWithComponentOwner und bleibt
//        unveraendert (keine Bewegung ausserhalb des belegten Mechanismus),
//   (H2) jedes Kettenglied muss ein '<Typ>.Create(<barer Ident>)' sein,
//   (H3) keine bekannte Datenklasse in der Kette (FL_DATA_CLASSES) -
//        'TStreamReader.Create(FStream)' ist Konsum, keine Ownership,
//   (H4) keine Klasse, die die Unit selbst als DIREKTEN TObject-Nachfahren
//        deklariert ('TFoo = class' ohne Elternliste) - ein TObject kann in
//        keinem Component-Tree haengen. TP-Schutz, belegt an gexperts
//        EII/D3/EIPanel.pas:238: 'TSplitterControl = class' mit
//        'Create(ASplitControl, ATargetControl: TControl)' sieht wie ein
//        Owner-Ctor aus, das Feld wird aber NIRGENDS freigegeben = echtes Leck,
//   (H5) kein Typ, den der Cross-Unit-Typindex BEWEISBAR ausserhalb der
//        TComponent-Linie fuehrt (TPersistent/TStream/TInterfacedObject/
//        TThread ohne TComponent). Ein bloss unbekannter Typ vetot NICHT -
//        die VCL-Basisklassen liegen ueblicherweise ausserhalb des Scan-Scope.

const
  // Beweisbar NICHT-Component-Wurzeln. Nur POSITIVE Treffer vetoen; eine
  // abgerissene Ahnenkette (Basisklasse ausserhalb des Scan-Scope) darf das
  // Gate nicht abschalten - sonst faellt es real nie an.
  FL_NON_COMPONENT_ROOTS : array[0..3] of string = (
    'tpersistent', 'tstream', 'tinterfacedobject', 'tthread');

function ProvablyNonComponent(ATypeIndex: TTypeIndex;
  const ATypeLow: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if (ATypeIndex = nil) or ATypeIndex.IsEmpty or (ATypeLow = '') then Exit;
  if ATypeIndex.IsDescendantOf(ATypeLow, 'tcomponent') then Exit;
  for i := Low(FL_NON_COMPONENT_ROOTS) to High(FL_NON_COMPONENT_ROOTS) do
    if ATypeIndex.IsDescendantOf(ATypeLow, FL_NON_COMPONENT_ROOTS[i]) then
      Exit(True);
end;

// True wenn die Unit AClassLow deklariert UND jede ihrer Deklarationen ohne
// Elternliste auskommt ('TFoo = class;' Forward + 'TFoo = class' Rumpf).
// Dann ist die Klasse ein direkter TObject-Nachfahre - sie kann nie Teil
// eines Component-Trees sein (Huerde H4).
function UnitDeclaresPlainObjectClass(UnitNode: TAstNode;
  const AClassLow: string): Boolean;
var
  Classes : TList<TAstNode>;
  N       : TAstNode;
  Seen    : Boolean;
begin
  Result := False;
  if (UnitNode = nil) or (AClassLow = '') then Exit;
  Seen := False;
  Classes := UnitNode.FindAll(nkClass);
  try
    for N in Classes do
      if N.Name.ToLower = AClassLow then
      begin
        Seen := True;
        if Trim(N.TypeRef) <> '' then Exit;   // Elternliste vorhanden -> kein Veto
      end;
  finally
    Classes.Free;
  end;
  Result := Seen;
end;

// Huerden H3-H5 gebuendelt: darf ATypeLow ueberhaupt ein Kettenglied sein?
function ChainClassIsIneligible(ATypeIndex: TTypeIndex; UnitNode: TAstNode;
  const AClassLow: string): Boolean;
begin
  Result := (AClassLow = '') or
            IsDataClassLow(AClassLow) or
            UnitDeclaresPlainObjectClass(UnitNode, AClassLow) or
            ProvablyNonComponent(ATypeIndex, AClassLow);
end;

// Kanonische Owner-Bezeichner (identisch zu IsCreatedWithComponentOwner bzw.
// TLeakDetector2.IsOwnerParamCreate). 'self.owner' kommt hier nie an -
// FirstCreateArgLow streift das 'self.'-Praefix bereits ab.
function IsCanonicalOwnerLow(const S: string): Boolean;
begin
  Result := (S = 'self') or (S = 'owner') or (S = 'aowner') or
            (S = 'application');
end;

// Erste '<Typ>.Create(...)'-Zuweisung an TargetLow im Konstruktor.
function CtorCreateOf(Ctor: TAstNode; const TargetLow: string;
  out AClassLow, AOwnerLow: string): Boolean;
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  LHSLow, RhsLow : string;
begin
  Result    := False;
  AClassLow := '';
  AOwnerLow := '';
  if (Ctor = nil) or (TargetLow = '') then Exit;
  Assigns := Ctor.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      LHSLow := A.Name.ToLower;
      if (LHSLow <> TargetLow) and
         (LHSLow <> 'self.' + TargetLow) then Continue;
      RhsLow := A.TypeRef.ToLower;
      if Pos('.create(', RhsLow) = 0 then Continue;
      AClassLow := CreateClassLow(RhsLow);
      AOwnerLow := FirstCreateArgLow(RhsLow);
      Exit(True);                    // finally gibt Assigns frei
    end;
  finally
    Assigns.Free;
  end;
end;

function IsOwnedByComponentChain(UnitNode, Ctor: TAstNode;
  const FieldNameLow: string; AContext: TAnalyzeContext): Boolean;
const
  MAX_HOPS = 8;
var
  TI      : TTypeIndex;
  // Zyklus-Schutz ohne TStringList - die Unit soll ihre uses-Liste behalten
  // (kein System.Classes) und die Kette ist per MAX_HOPS ohnehin winzig.
  Visited : array[0..MAX_HOPS] of string;
  Cur, ClassLow, OwnerLow : string;
  Hops, i : Integer;
  Clean, Seen : Boolean;
begin
  Result := False;
  if (Ctor = nil) or (FieldNameLow = '') then Exit;
  TI := CtxTypeIndex(AContext);      // nil im Single-File-/Testpfad
  Cur  := FieldNameLow;
  Hops := 0;
  while Hops < MAX_HOPS do
  begin
    Seen := False;
    for i := 0 to Hops - 1 do
      // noinspection UninitVar
      // Falschmeldung der eigenen Regel: beim ersten Durchlauf ist Hops = 0,
      // die Schleife laeuft also gar nicht und liest nichts. Visited[Hops]
      // wird zwei Zeilen spaeter geschrieben - VOR jedem moeglichen Lesen.
      // SCA166 ist als konservativer MVP dokumentiert, nicht pfad-sensitiv.
      if Visited[i] = Cur then begin Seen := True; Break; end;
    if Seen then Exit;                                   // Zyklus
    Visited[Hops] := Cur;
    if not CtorCreateOf(Ctor, Cur, ClassLow, OwnerLow) then Exit;
    if ChainClassIsIneligible(TI, UnitNode, ClassLow) then Exit;
    if (OwnerLow = '') or (OwnerLow = 'nil') then Exit;
    if IsCanonicalOwnerLow(OwnerLow) then
    begin
      Result := Hops >= 1;           // H1: mindestens ein Zwischenobjekt
      Exit;
    end;
    Clean := True;
    for i := 1 to Length(OwnerLow) do
      if not TLeakDetector2.IsIdentChar(OwnerLow[i]) then
      begin Clean := False; Break; end;
    if not Clean then Exit;          // H2: nur bare Identifier
    Cur := OwnerLow;
    Inc(Hops);
  end;
end;

// FP-Klasse 3b: das Free steckt in einer Helper-Methode DERSELBEN Klasse, die
// der Destruktor aufruft ('FreeBlockList;' -> 'FreeAndNil(FBlocks)', pyscripter
// JvDockVSNetStyle.pas:180). Der Dtor-Scan prueft sonst nur direkte Frees im
// Destroy-Rumpf. GENAU EINE Ebene Methoden-Inlining, und nur fuer
// unqualifizierte bzw. 'Self.'-qualifizierte Aufrufe, die sich eindeutig auf
// '<DieseKlasse>.<Callee>' aufloesen lassen - fremde Receiver ('FList.Clear')
// bleiben aussen vor.
function IsFreedViaOwnHelper(UnitNode, Dtor: TAstNode;
  const ClassNameLow, FieldNameLow: string): Boolean;
var
  Calls, Methods : TList<TAstNode>;
  C, M    : TAstNode;
  CalLow, Target : string;
  Dummy   : Boolean;
begin
  Result := False;
  if (UnitNode = nil) or (Dtor = nil) or (ClassNameLow = '') then Exit;
  Calls   := Dtor.FindAll(nkCall);
  Methods := nil;
  try
    Methods := UnitNode.FindAll(nkMethod);
    for C in Calls do
    begin
      CalLow := Trim(C.Name.ToLower);
      if (Length(CalLow) >= 2) and
         (Copy(CalLow, Length(CalLow) - 1, 2) = '()') then
        CalLow := Trim(Copy(CalLow, 1, Length(CalLow) - 2));
      if Copy(CalLow, 1, 5) = 'self.' then
        CalLow := Trim(Copy(CalLow, 6, MaxInt));
      // Nur blanke Methodennamen: alles mit Klammern (Argumente) oder Punkt
      // (fremder Receiver) ist kein Self-Helper-Aufruf.
      if (CalLow = '') or (Pos('(', CalLow) > 0) or (Pos('.', CalLow) > 0) then
        Continue;
      Target := ClassNameLow + '.' + CalLow;
      for M in Methods do
        if (M.Name.ToLower = Target) and
           TLeakDetector2.SearchFree(M, FieldNameLow, False, Dummy) then
          Exit(True);            // finally gibt Methods/Calls frei
    end;
  finally
    Methods.Free;
    Calls.Free;
  end;
end;

class procedure TFieldLeakDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Classes      : TList<TAstNode>;
  ClassNode    : TAstNode;
  Fields       : TList<TAstNode>;
  Field        : TAstNode;
  Ctor, Dtor   : TAstNode;
  // Parser-Gate-Backlog 2026-07-31 (4e/1): zweiter Aufraeum-Ort. BEWUSST eine
  // eigene Variable statt einer Zuweisung an Dtor - der Befundtext haengt an
  // 'Dtor = nil' ("no destructor exists" vs. "not freed in Destroy"). Wuerde
  // BeforeDestruction den Destruktor ersetzen, aenderte sich der Text
  // ueberlebender Funde (= Identitaetswechsel im SARIF-Diff).
  Cleanup      : TAstNode;
  FieldNameLow : string;
  FreeFound    : Boolean;
  FreeInFin    : Boolean;
  F            : TLeakFinding;
begin
  Classes := UnitNode.FindAll(nkClass);
  try
    for ClassNode in Classes do
    begin
      if ClassNode.Name = '' then Continue;

      // Konstruktor + Destruktor der Klasse suchen.
      Ctor := FindMethod(UnitNode, 'constructor', ClassNode.Name);
      if Ctor = nil then Continue; // ohne Konstruktor nichts zu pruefen

      Dtor := FindMethod(UnitNode, 'destructor', ClassNode.Name);
      // BeforeDestruction laeuft garantiert VOR Destroy (TObject.Free ->
      // BeforeDestruction -> Destroy). jvcl JvInspector/JvInspExtraEditors
      // raeumen ihre Felder ausschliesslich dort auf.
      Cleanup := FindMethodNamed(UnitNode, ClassNode.Name, 'beforedestruction');

      Fields := ClassNode.FindAll(nkField);
      try
        for Field in Fields do
        begin
          if not TLeakDetector2.IsLeakyType(Field.TypeRef, AContext) then Continue;
          FieldNameLow := Field.Name.ToLower;

          // Feld muss im Konstruktor per .Create zugewiesen werden,
          // sonst ist es kein Konstruktor-erzeugtes Feld.
          if not HasFieldCreate(Ctor, FieldNameLow) then Continue;

          // TComponent-Ownership-Pattern: FField := X.Create(Self) etc.
          // Owner gibt das Feld via DestroyComponents automatisch frei -
          // explicit Free im Destruktor waere redundant. Beispiele:
          //   FTimer  := TTimer.Create(Self);    -- VCL TComponent-Tree
          //   FAction := TAction.Create(AOwner); -- weitergereichter Owner
          if IsCreatedWithComponentOwner(Ctor, FieldNameLow) then Continue;

          // Ownership-Transfer: Feld wird im Ctor als ARG weitergereicht
          // ('AddAttribute(FField)', 'FList.Add(FField)') -> der Empfaenger kann
          // es freigeben, ein fehlendes Free hier ist dann kein Leak. Die im
          // Unit-Kopf dokumentierte FP-Quelle; mit Custom-Class-Discovery
          // dominierte sie die Funde (Recall-Messung 2026-07-15: +2410).
          if IsHandedToOwner(Ctor, FieldNameLow) then Continue;

          // Pruefen ob im Destruktor ein .Free / .Destroy / FreeAndNil
          // fuer das Feld vorkommt. Reuse von SearchFree aus uLeakDetector2.
          FreeFound := False;
          if Dtor <> nil then
            FreeFound := TLeakDetector2.SearchFree(Dtor, FieldNameLow,
                                                   False, FreeInFin);
          // FP-Gate (2026-07-31, Parser-Gate-Backlog 4e/1): dieselbe
          // Freigabe-Pruefung auf BeforeDestruction. Reine Erweiterung des
          // Suchraums - kann einen Fund nur unterdruecken.
          if not FreeFound and (Cleanup <> nil) then
            FreeFound := TLeakDetector2.SearchFree(Cleanup, FieldNameLow,
                                                   False, FreeInFin);
          // Alias-Free-Idiom (L := FField; FField := nil; L.Free) erkennen.
          if not FreeFound then
            FreeFound := IsFreedViaAlias(Dtor, FieldNameLow);
          // Zweiter Alias-Weg: die Freigabe laeuft ueber den
          // Property-Namen statt ueber das Feld.
          if not FreeFound then
          begin
            FreeFound := IsFreedViaPropertyAlias(Dtor, ClassNode, FieldNameLow);
          end;
          if not FreeFound then
            FreeFound := IsFreedViaAlias(Cleanup, FieldNameLow);
          if not FreeFound and (Cleanup <> nil) then
          begin
            FreeFound := IsFreedViaPropertyAlias(Cleanup, ClassNode,
                                                 FieldNameLow);
          end;

          // FP-Gate (2026-07-31, FP-Klasse 3b): Free steckt in einer vom
          // Destroy gerufenen Helper-Methode DERSELBEN Klasse (FreeBlockList).
          if not FreeFound then
            FreeFound := IsFreedViaOwnHelper(UnitNode, Dtor,
                           ClassNode.Name.ToLower, FieldNameLow);
          if not FreeFound then
            FreeFound := IsFreedViaOwnHelper(UnitNode, Cleanup,
                           ClassNode.Name.ToLower, FieldNameLow);

          // FP-Gate (2026-07-31, FP-Klasse 3a): Owner ist ein Schwester-FELD,
          // das im Destroy freigegeben wird (FEndTimer mit Owner FPanel) - der
          // Owner raeumt das Component-Tree mit ab. ClassNode/AContext seit dem
          // Pre-Build-Review 2026-07-31 (Fund uFieldLeak.pas:333) noetig: das
          // Gate prueft jetzt Owner-Feldzugehoerigkeit, Datenklassen-Sperrliste
          // und - falls verfuegbar - die TComponent-Ahnenlinie im Typindex.
          if not FreeFound and
             IsOwnedByFreedSiblingField(Ctor, Dtor, ClassNode, FieldNameLow,
                                        AContext) then Continue;
          // Dasselbe Gate mit BeforeDestruction als Freigabe-Ort.
          if not FreeFound and (Cleanup <> nil) and
             IsOwnedByFreedSiblingField(Ctor, Cleanup, ClassNode, FieldNameLow,
                                        AContext) then Continue;

          // FP-Gate (2026-07-31, Parser-Gate-Backlog 4e/1, FP-Klasse 4):
          // transitive Component-Ownership. Der Owner-Ausdruck ist selbst ein
          // im SELBEN Konstruktor erzeugtes Objekt, dessen Kette bei
          // Self/AOwner/Owner/Application endet - der Component-Tree der
          // Wurzel raeumt alles mit ab. Braucht KEINEN Destruktor (jvcl
          // JvGammaPanel hat gar keinen) und KEINE Feldzugehoerigkeit des
          // Owners (jvcl JvCombobox: FPopup ist in der Vorfahrenklasse
          // deklariert).
          if not FreeFound and
             IsOwnedByComponentChain(UnitNode, Ctor, FieldNameLow,
                                     AContext) then Continue;

          // FP-Gate (2026-08-17): das Feld wird im Konstruktor an ein
          // INTERFACE uebergeben - 'FIntf := FObj as IFoo;' oder
          // 'FIntf := IFoo(FObj);'. Dann traegt der Refcount die Ownership;
          // freigegeben wird ueber das Nil-Setzen des Interface-Feldes im
          // Destruktor, und ein zusaetzlicher Free waere ein DOUBLE-FREE.
          //
          // Das Praedikat ist seit 2026-07-19 fuer lokale Variablen erprobt
          // (TLeakDetector2.IsHandedToInterface, dort zwei Aufrufstellen);
          // uFieldLeak hat es nie gerufen, deshalb war die Klasse fuer FELDER
          // bis heute offen. Kein zweiter Nachbau: die Unit haengt ohnehin
          // schon an TLeakDetector2 (IsIdentChar, :259/:461).
          //
          // Eng gehalten wie das Original: der Cast muss im KONSTRUKTOR
          // stehen, und der Interface-Ident muss der 'I'+Grossbuchstabe-
          // Konvention folgen (schliesst 'IntToStr(FFoo)' aus).
          if not FreeFound and
             TLeakDetector2.IsHandedToInterface(Ctor, FieldNameLow) then Continue;

          if not FreeFound then
          begin
            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := ClassNode.Name + '.Destroy';
            F.LineNumber := IntToStr(Field.Line);
            if Dtor = nil then
              F.MissingVar := Format(
                '%s: created in constructor but no destructor exists',
                [Field.Name])
            else
              F.MissingVar := Format(
                '%s: created in %s.Create but not freed in Destroy',
                [Field.Name, ClassNode.Name]);
            F.SetKind(fkMemoryLeak);
            Results.Add(F);
          end;
        end;
      finally
        Fields.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

end.
