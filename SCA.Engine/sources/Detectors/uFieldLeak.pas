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

class function TFieldLeakDetector.IsCreatedWithComponentOwner(
  MethodNode: TAstNode; const FieldNameLow: string): Boolean;
// Sucht im Konstruktor 'FField := X.Create(Self|AOwner|Owner[, ...])'.
// Whitespace-tolerant - der Lexer normalisiert ohnehin Whitespace, aber
// die Pattern-Pruefung schaut auf das exakte Token nach '.create('.
const
  OWNER_PATS : array[0..5] of string = (
    '.create(self)',   '.create(self,',
    '.create(aowner)', '.create(aowner,',
    '.create(owner)',  '.create(owner,'
  );
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  LHSLow  : string;
  TypeLow : string;
  i       : Integer;
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
      for i := Low(OWNER_PATS) to High(OWNER_PATS) do
        if Pos(OWNER_PATS[i], TypeLow) > 0 then
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

class procedure TFieldLeakDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Classes      : TList<TAstNode>;
  ClassNode    : TAstNode;
  Fields       : TList<TAstNode>;
  Field        : TAstNode;
  Ctor, Dtor   : TAstNode;
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
          // Alias-Free-Idiom (L := FField; FField := nil; L.Free) erkennen.
          if not FreeFound then
            FreeFound := IsFreedViaAlias(Dtor, FieldNameLow);

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
