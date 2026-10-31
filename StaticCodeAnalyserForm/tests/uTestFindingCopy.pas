unit uTestFindingCopy;

// Tests fuer TLeakFinding.CopyFrom/Clone (uMethodd12): die EINE Kopie eines
// Funds. Bis 2026-10-28 stand sie dreimal feldweise von Hand
// (uFindingsPropertiesFrame, uIDEFindingsPropertiesForm, uEditorFindingStore)
// und verlor Felder - der Silent-Kopie fehlte LeakVariant, reDelphix sperrte
// dort den SCA001-Fix "Free ausserhalb finally" (Befund B1).
//
// WARUM PER RTTI: eine Feldliste im Test waere eine vierte Handkopie und
// vergaesse dasselbe Feld wie CopyFrom. Der Test nimmt stattdessen die
// Felder, die der Compiler kennt (erweiterte RTTI; Vorgabe: Felder ALLER
// Sichtbarkeiten, TLeakFinding hat nur public-Felder), fuellt jedes mit
// einem Wert ungleich dem eines frischen Funds und vergleicht die Kopie. Ein
// neues Feld ohne Zeile in CopyFrom bleibt in der Kopie auf dem
// Vorgabewert - rot. Ein Feld eines Typs, den FillEveryField nicht kennt
// (Objekt, dynamisches Array, Record), ist sofort rot: es braucht in
// CopyFrom eine eigene, womoeglich tiefe Kopie und hier einen eigenen Zweig.
// FINDING_FIELD_COUNT sichert, dass die RTTI ueberhaupt Felder liefert -
// ohne sie waere jeder Vergleich leer und gruen.
//
// Ordinale ruecken je Feld unterschiedlich weit (Schritt nach Feldindex):
// zwei Felder desselben Typs (Severity, SavedDetectorSeverity) bekommen so
// verschiedene Werte, eine Verwechslung in CopyFrom faellt auf.

interface

uses
  DUnitX.TestFramework,
  uMethodd12;                   // TLeakFinding

const
  // Felder von TLeakFinding. Neues Feld: erst CopyFrom ergaenzen, dann
  // diese Zahl.
  FINDING_FIELD_COUNT = 14;

type
  [TestFixture]
  TTestFindingCopy = class
  public
    [Test] procedure FieldCount_MatchesCopyFromContract;
    [Test] procedure Fill_ChangesEveryField;
    [Test] procedure CopyFrom_CopiesEveryField;
    [Test] procedure CopyFrom_OverwritesWithDefaults;
    [Test] procedure Clone_CopiesEveryFieldIntoOwnObject;
    [Test] procedure Clone_OfSubclass_IsPlainLeakFinding;
    [Test] procedure Clone_KeepsLeakVariantAndDetectorSeverity;
  end;

// Fuellt JEDES Feld von AFinding per RTTI mit einem Wert ungleich dem eines
// frischen TLeakFinding. Unbekannter Feldtyp: Assert.Fail. Auch fuer
// uTestEditorFindingStore.
procedure FillEveryField(AFinding: TLeakFinding);
// Namen der Felder, in denen A und B sich unterscheiden, komma-getrennt;
// '' = alle gleich.
function DifferingFields(A, B: TLeakFinding): string;
// Anzahl der Felder von TLeakFinding laut RTTI.
function FindingFieldCount: Integer;

implementation

uses
  System.Rtti,                  // TRttiContext, TRttiField, TValue
  System.TypInfo,               // tkUString, tkEnumeration, tkInteger
  uSCAConsts;                   // fkMemoryLeak, lsError, lsWarning

const
  FOF = 'freed-outside-finally';

type
  // Unterklasse - Clone liefert trotzdem einen schlichten TLeakFinding.
  TSubFinding = class(TLeakFinding);

function IsStringKind(AKind: TTypeKind): Boolean;
begin
  Result := AKind in [tkUString, tkLString, tkWString, tkString];
end;

function IsOrdinalKind(AKind: TTypeKind): Boolean;
begin
  Result := AKind in [tkEnumeration, tkInteger];
end;

// Der naechste Wert im Bereich von AType, AIndex + 1 Schritte weiter
// (zyklisch, nie wieder AOld, solange der Bereich zwei Werte hat).
function ShiftedOrdinal(AType: TRttiOrdinalType; AOld: Int64;
  AIndex: Integer): Int64;
var
  Count : Int64;
  Step  : Int64;
begin
  Count := Int64(AType.MaxValue) - AType.MinValue + 1;
  if Count < 2 then
    Exit(AOld);
  Step := 1 + (AIndex mod (Count - 1));
  Result := AType.MinValue + (AOld - AType.MinValue + Step) mod Count;
end;

procedure FillEveryField(AFinding: TLeakFinding);
var
  Ctx   : TRttiContext;
  Field : TRttiField;
  Index : Integer;
  Old   : TValue;
  N     : Int64;
begin
  Index := 0;
  for Field in Ctx.GetType(TLeakFinding).GetFields do
  begin
    if Field.FieldType = nil then
      Assert.Fail('Feld ' + Field.Name + ': Typ ohne RTTI');
    Old := Field.GetValue(AFinding);
    if IsStringKind(Field.FieldType.TypeKind) then
      Field.SetValue(AFinding, Old.AsString + '<' + Field.Name + '>')
    else if IsOrdinalKind(Field.FieldType.TypeKind) then
    begin
      N := ShiftedOrdinal(Field.FieldType as TRttiOrdinalType, Old.AsOrdinal,
        Index);
      if Field.FieldType.TypeKind = tkInteger then
        Field.SetValue(AFinding, TValue.From<Integer>(Integer(N)))
      else
        Field.SetValue(AFinding, TValue.FromOrdinal(Field.FieldType.Handle, N));
    end
    else
      Assert.Fail('Feld ' + Field.Name + ' (' + Field.FieldType.Name
        + '): Typ kennt der Test nicht - CopyFrom (Kopie, ggf. tief) und '
        + 'FillEveryField/DifferingFields erweitern');
    Inc(Index);
  end;
end;

function SameField(AField: TRttiField; A, B: TLeakFinding): Boolean;
var
  VA, VB : TValue;
begin
  VA := AField.GetValue(A);
  VB := AField.GetValue(B);
  if IsStringKind(AField.FieldType.TypeKind) then
    Result := VA.AsString = VB.AsString
  else if IsOrdinalKind(AField.FieldType.TypeKind) then
    Result := VA.AsOrdinal = VB.AsOrdinal
  else
  begin
    Assert.Fail('Feld ' + AField.Name + ': Typ kennt der Vergleich nicht');
    Result := False;
  end;
end;

function DifferingFields(A, B: TLeakFinding): string;
var
  Ctx   : TRttiContext;
  Field : TRttiField;
begin
  Result := '';
  for Field in Ctx.GetType(TLeakFinding).GetFields do
    if not SameField(Field, A, B) then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Field.Name;
    end;
end;

function FindingFieldCount: Integer;
var
  Ctx : TRttiContext;
begin
  Result := Length(Ctx.GetType(TLeakFinding).GetFields);
end;

// Wie viele Felder von A und B sich unterscheiden.
function DifferingCount(A, B: TLeakFinding): Integer;
var
  Ctx   : TRttiContext;
  Field : TRttiField;
begin
  Result := 0;
  for Field in Ctx.GetType(TLeakFinding).GetFields do
    if not SameField(Field, A, B) then
      Inc(Result);
end;

procedure TTestFindingCopy.FieldCount_MatchesCopyFromContract;
begin
  Assert.AreEqual<Integer>(FINDING_FIELD_COUNT, FindingFieldCount,
    'Feldzahl von TLeakFinding geaendert: neues Feld in '
    + 'TLeakFinding.CopyFrom uebernehmen, dann FINDING_FIELD_COUNT anpassen');
end;

procedure TTestFindingCopy.Fill_ChangesEveryField;
var
  Fresh, Filled : TLeakFinding;
begin
  // Gegenprobe der Fuellung: sonst bewiese der Kopie-Vergleich nichts fuer
  // ein Feld, das schon auf dem Vorgabewert stuende.
  Fresh := nil;
  Filled := nil;
  try
    Fresh := TLeakFinding.Create;
    Filled := TLeakFinding.Create;
    FillEveryField(Filled);
    Assert.AreEqual<Integer>(FindingFieldCount, DifferingCount(Fresh, Filled),
      'jedes Feld traegt einen Nicht-Vorgabewert');
  finally
    Filled.Free;
    Fresh.Free;
  end;
end;

procedure TTestFindingCopy.CopyFrom_CopiesEveryField;
var
  Src, Dst : TLeakFinding;
begin
  Src := nil;
  Dst := nil;
  try
    Src := TLeakFinding.Create;
    Dst := TLeakFinding.Create;
    FillEveryField(Src);
    Dst.CopyFrom(Src);
    Assert.AreEqual('', DifferingFields(Src, Dst),
      'fehlt in TLeakFinding.CopyFrom');
  finally
    Dst.Free;
    Src.Free;
  end;
end;

procedure TTestFindingCopy.CopyFrom_OverwritesWithDefaults;
var
  Src, Dst : TLeakFinding;
begin
  // Auch ein schon gefuelltes Ziel wird ganz ueberschrieben - Vorgabewerte
  // der Quelle eingeschlossen (CopyFrom ist kein "nur Gesetztes mischen").
  Src := nil;
  Dst := nil;
  try
    Src := TLeakFinding.Create;
    Dst := TLeakFinding.Create;
    FillEveryField(Dst);
    Dst.CopyFrom(Src);
    Assert.AreEqual('', DifferingFields(Src, Dst),
      'CopyFrom laesst den alten Wert stehen');
  finally
    Dst.Free;
    Src.Free;
  end;
end;

procedure TTestFindingCopy.Clone_CopiesEveryFieldIntoOwnObject;
var
  Src, C : TLeakFinding;
begin
  Src := nil;
  C := nil;
  try
    Src := TLeakFinding.Create;
    FillEveryField(Src);
    C := Src.Clone;
    Assert.IsTrue(C <> Src, 'eigenes Objekt');
    Assert.AreEqual('', DifferingFields(Src, C), 'fehlt im Clone');
  finally
    C.Free;
    Src.Free;
  end;
end;

procedure TTestFindingCopy.Clone_OfSubclass_IsPlainLeakFinding;
var
  Src : TSubFinding;
  C   : TLeakFinding;
begin
  Src := nil;
  C := nil;
  try
    Src := TSubFinding.Create;
    FillEveryField(Src);
    C := Src.Clone;
    Assert.IsTrue(C.ClassType = TLeakFinding, C.ClassName);
    Assert.AreEqual('', DifferingFields(Src, C));
  finally
    C.Free;
    Src.Free;
  end;
end;

procedure TTestFindingCopy.Clone_KeepsLeakVariantAndDetectorSeverity;
var
  Src, C : TLeakFinding;
begin
  // B1 mit den Werten des Falls: SCA001 freed-outside-finally, Detektor-
  // Schwere lsError, von der Evidenz-Politik auf lsWarning gedeckelt.
  // PlanMemoryLeak (reDelphix) verzweigt auf LeakVariant.
  Src := nil;
  C := nil;
  try
    Src := TLeakFinding.New('C:\p\a.pas', 'TFoo.Bar', 12, 'L', fkMemoryLeak);
    Src.Severity := lsError;
    Src.LeakVariant := FOF;
    Src.OverrideSeverity(lsWarning);
    C := Src.Clone;
    Assert.AreEqual(FOF, C.LeakVariant);
    Assert.AreEqual(FOF, C.MemoryLeakVariant);
    Assert.AreEqual<Integer>(Ord(lsWarning), Ord(C.Severity));
    Assert.IsTrue(C.SeverityWasOverridden);
    Assert.AreEqual<Integer>(Ord(lsError), Ord(C.OriginalSeverity),
      'die Detektor-Schwere reist mit');
  finally
    C.Free;
    Src.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingCopy);

end.
