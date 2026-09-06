unit uTestFilterComboReduce;

// Tests fuer TFindingFilter.ReduceSeverityItems + CountForTag mit
// Type-Sicht (uFindingFilter, SCA.SharedUI) - die geteilte Zaehl- und
// Reduktionslogik der Severity-Combo beider Wirte.
//
// Nutzerentscheid 2026-09-06: ein Combo-Eintrag ohne Funde in der
// AKTUELLEN Sicht (inkl. Type-Filter) ist nicht waehlbar; leere
// Gruppen-Eintraege und verwaiste Trenner fliegen mit. Vorher lebte
// die Trenner-Logik nur im Plugin (die EXE warf ALLE Trenner weg),
// und keiner der Wirte kannte die Type-Sicht.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uFindingFilter;

type
  [TestFixture]
  TTestFilterComboReduce = class
  strict private
    FFindings : TObjectList<TLeakFinding>;
    function KindTag(AKind: TFindingKind): Integer;
    function MakeItem(const ADisplay: string;
      AModeOrd: Integer): TFilterComboItem;
    procedure AddFinding(AKind: TFindingKind);
    function TagsOf(const AItems: TArray<TFilterComboItem>): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure KindWithoutHits_IsRemoved;
    [Test] procedure TypeView_KeepsOnlyKindsOfThatType;
    [Test] procedure EmptyFindings_LeaveOnlyAllAndDetectorReview;
    [Test] procedure OrphanSeparator_IsRemoved_FollowedSectionStays;
    [Test] procedure TrailingSeparator_IsRemoved;
    [Test] procedure GroupEntries_FollowTheHits;
    [Test] procedure CountForTagWithAllView_MatchesLegacyCount;
  end;

implementation

// noinspection-file DuplicateString
// Die Katalog-Labels ('All', 'sep', ...) wiederholen sich absichtlich -
// sie sind der Pruefgegenstand der Fixtures.

{ TTestFilterComboReduce }

procedure TTestFilterComboReduce.Setup;
begin
  FFindings := TObjectList<TLeakFinding>.Create(True);
end;

procedure TTestFilterComboReduce.TearDown;
begin
  FreeAndNil(FFindings);
end;

function TTestFilterComboReduce.KindTag(AKind: TFindingKind): Integer;
begin
  Result := TFindingFilter.KIND_TAG_BASE + Ord(AKind);
end;

function TTestFilterComboReduce.MakeItem(const ADisplay: string;
  AModeOrd: Integer): TFilterComboItem;
begin
  Result.Display := ADisplay;
  Result.ModeOrd := AModeOrd;
end;

procedure TTestFilterComboReduce.AddFinding(AKind: TFindingKind);
// New setzt Severity/Confidence aus KIND_META - FindingType kommt als
// Funktion ebenfalls von dort. Die Tests waehlen Kinds mit bekannt
// verschiedenen Typen: fkNilDeref = ftBug, fkTodoComment = ftCodeSmell.
begin
  FFindings.Add(TLeakFinding.New('C:\src\Probe.pas', 'TFoo.Bar', 10,
    'probe', AKind));
end;

function TTestFilterComboReduce.TagsOf(
  const AItems: TArray<TFilterComboItem>): string;
// Kompakte Tag-Folge fuer sprechende Assertions ('0|-1|10042|...').
var
  It : TFilterComboItem;
begin
  Result := '';
  for It in AItems do
  begin
    if Result <> '' then Result := Result + '|';
    Result := Result + IntToStr(It.ModeOrd);
  end;
end;

procedure TTestFilterComboReduce.KindWithoutHits_IsRemoved;
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  AddFinding(fkNilDeref);
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('sep', -1),
              MakeItem('NilDeref', KindTag(fkNilDeref)),
              MakeItem('TodoComment', KindTag(fkTodoComment))];
  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|-1|%d', [Ord(fmAll), KindTag(fkNilDeref)]), TagsOf(R),
    'TodoComment hat keine Funde und muss aus der Liste fallen');
end;

procedure TTestFilterComboReduce.TypeView_KeepsOnlyKindsOfThatType;
// Der Screenshot-Fall vom 06.09.: ein Detektor, der unter dem aktiven
// Type-Filter nichts hat, darf nicht waehlbar sein.
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  AddFinding(fkNilDeref);      // ftBug
  AddFinding(fkTodoComment);   // ftCodeSmell
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('NilDeref', KindTag(fkNilDeref)),
              MakeItem('TodoComment', KindTag(fkTodoComment))];

  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfBug);
  Assert.AreEqual(
    Format('%d|%d', [Ord(fmAll), KindTag(fkNilDeref)]), TagsOf(R),
    'unter Type=Bug bleibt nur der Bug-Detektor');

  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfCodeSmell);
  Assert.AreEqual(
    Format('%d|%d', [Ord(fmAll), KindTag(fkTodoComment)]), TagsOf(R),
    'unter Type=Code Smell bleibt nur der Smell-Detektor');

  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|%d|%d',
      [Ord(fmAll), KindTag(fkNilDeref), KindTag(fkTodoComment)]), TagsOf(R),
    'unter Type=All bleiben beide');
end;

procedure TTestFilterComboReduce.EmptyFindings_LeaveOnlyAllAndDetectorReview;
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('Review', Ord(fmDetectorReview)),
              MakeItem('sep', -1),
              MakeItem('NilDeref', KindTag(fkNilDeref))];
  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|%d', [Ord(fmAll), Ord(fmDetectorReview)]), TagsOf(R),
    'ohne Funde bleiben nur die statischen Eintraege - kein Trenner');
end;

procedure TTestFilterComboReduce.OrphanSeparator_IsRemoved_FollowedSectionStays;
// Der Orphan-Pass (vorher nur im Plugin): ein Trenner, dessen Sektion
// leer wurde, faellt; der Trenner der ueberlebenden Sektion bleibt.
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  AddFinding(fkTodoComment);
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('sep1', -1),
              MakeItem('NilDeref', KindTag(fkNilDeref)),      // faellt
              MakeItem('sep2', -1),
              MakeItem('TodoComment', KindTag(fkTodoComment))];
  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|-1|%d', [Ord(fmAll), KindTag(fkTodoComment)]), TagsOf(R),
    'sep1 ist verwaist (Trenner vor Trenner) und faellt, sep2 bleibt');
  Assert.AreEqual('sep2', R[1].Display,
    'der ueberlebende Trenner ist der VOR der vollen Sektion');
end;

procedure TTestFilterComboReduce.TrailingSeparator_IsRemoved;
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  AddFinding(fkNilDeref);
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('NilDeref', KindTag(fkNilDeref)),
              MakeItem('sep', -1),
              MakeItem('TodoComment', KindTag(fkTodoComment))]; // faellt
  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|%d', [Ord(fmAll), KindTag(fkNilDeref)]), TagsOf(R),
    'der Trenner am Listenende (Sektion leer) faellt mit');
end;

procedure TTestFilterComboReduce.GroupEntries_FollowTheHits;
// fkTodoComment traegt DefaultSeverity lsHint (Hint wird von der
// Evidenz-Politik nie angehoben): nur 'Hints (all)' darf bleiben.
var
  Katalog, R : TArray<TFilterComboItem>;
begin
  AddFinding(fkTodoComment);
  Katalog := [MakeItem('All', Ord(fmAll)),
              MakeItem('Errors', Ord(fmErrors)),
              MakeItem('Warnings', Ord(fmWarnings)),
              MakeItem('Hints', Ord(fmHints))];
  R := TFindingFilter.ReduceSeverityItems(Katalog, FFindings, tfAll);
  Assert.AreEqual(
    Format('%d|%d', [Ord(fmAll), Ord(fmHints)]), TagsOf(R),
    'leere Severity-Gruppen fallen, die getroffene bleibt');
end;

procedure TTestFilterComboReduce.CountForTagWithAllView_MatchesLegacyCount;
// Aequivalenz-Gegenprobe: die neue Matches-basierte Zaehlung muss unter
// tfAll exakt die alte Zaehlung liefern - fuer Kind-Tags, Gruppen-Tags
// und den Trenner.
var
  Tags : TArray<Integer>;
  T    : Integer;
begin
  AddFinding(fkNilDeref);
  AddFinding(fkNilDeref);
  AddFinding(fkTodoComment);
  Tags := [KindTag(fkNilDeref), KindTag(fkTodoComment),
           Ord(fmErrors), Ord(fmWarnings), Ord(fmHints), Ord(fmAll), -1];
  for T in Tags do
    Assert.AreEqual<Integer>(
      TFindingFilter.CountForTag(FFindings, T),
      TFindingFilter.CountForTag(FFindings, T, tfAll),
      Format('Tag %d: Type-Sicht tfAll muss der Alt-Zaehlung entsprechen', [T]));
end;

end.
