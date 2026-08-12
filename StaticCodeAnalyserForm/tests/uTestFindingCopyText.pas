unit uTestFindingCopyText;

// Tests fuer uFindingCopyText (SCA.Engine, Output-Schicht): das
// Jira-Mini-Issue-Format und die Mode-Weiche hinter [UI] ClipboardOnClick.
//
// Assertion-Strategie wie in uTestFixHint dokumentiert: geprueft wird
// gegen Inhalte, die NICHT durch _() laufen (Regel-ID, Pfad, Methode,
// Meldetext, explizit uebergebene Hint-Description) - die Tests bleiben
// damit sprachunabhaengig. Findings via TLeakFinding.New, Hint als
// explizites Record: kein INI-, kein Clipboard-, kein Datei-Zugriff.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uSCAConsts, uMethodd12, uFixHint, uFindingCopyText;

type
  [TestFixture]
  TTestFindingCopyText = class
  strict private
    function MakeFinding(const AMessage: string): TLeakFinding;
    function JiraFor(F: TLeakFinding; const AHintDesc: string): string;
    function CountBullets(const AText: string): Integer;
  public
    [Test] procedure Headline_CarriesRuleFileLineAndMessage;
    [Test] procedure Description_CarriesAllFiveFacts;
    [Test] procedure EmptyMethodAndHint_YieldDashButKeepFiveBullets;
    [Test] procedure MultilineMessage_IsFlattenedToOneLine;
    [Test] procedure OverlongMessage_IsCroppedWithEllipsis;
    [Test] procedure MultilineFinding_ShowsLineRange;
    [Test] procedure ModeFromInt_MapsOneTwoThree_InvalidFallsToNone;
    [Test] procedure Dispatch_NoneEmpty_JiraStartsWithRule_ClaudeNonEmpty;
  end;

implementation

const
  PROBE_FILE   = 'C:\src\Demo.pas';
  PROBE_METHOD = 'TBar.DoWork';
  PROBE_LINE   = 42;
  PROBE_MSG    = 'list1 wird nie freigegeben';
  PROBE_HINT   = 'Free in try..finally verschieben';

function TTestFindingCopyText.MakeFinding(
  const AMessage: string): TLeakFinding;
begin
  Result := TLeakFinding.New(PROBE_FILE, PROBE_METHOD, PROBE_LINE,
    AMessage, fkMemoryLeak);
end;

function TTestFindingCopyText.JiraFor(F: TLeakFinding;
  const AHintDesc: string): string;
var
  Hint : TFixHint;
begin
  Hint := Default(TFixHint);
  Hint.Description := AHintDesc;
  Result := TFindingCopyText.Build(F, fcmJiraMini, Hint);
end;

function TTestFindingCopyText.CountBullets(const AText: string): Integer;
var
  Line : string;
  SL   : TStringList;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    for Line in SL do
    begin
      if Line.StartsWith('* ') then
      begin
        Inc(Result);
      end;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestFindingCopyText.Headline_CarriesRuleFileLineAndMessage;
var
  F        : TLeakFinding;
  Headline : string;
  Text     : string;
begin
  F := MakeFinding(PROBE_MSG);
  try
    Text := JiraFor(F, PROBE_HINT);
    Headline := Text.Split([sLineBreak])[0];
    Assert.IsTrue(Headline.Contains('[' + F.ResolvedRuleId + ']'),
      'Headline traegt die Regel-ID in eckigen Klammern');
    Assert.IsTrue(Headline.Contains('Demo.pas:42'),
      'Headline traegt Dateiname:Zeile');
    Assert.IsTrue(Headline.Contains(PROBE_MSG),
      'Headline traegt den Meldetext');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.Description_CarriesAllFiveFacts;
var
  F    : TLeakFinding;
  Text : string;
begin
  F := MakeFinding(PROBE_MSG);
  try
    Text := JiraFor(F, PROBE_HINT);
    Assert.AreEqual<Integer>(5, CountBullets(Text),
      'Beschreibung hat exakt fuenf Fakten-Bullets');
    Assert.IsTrue(Text.Contains(F.ResolvedRuleId),  'Fakt Regel-ID');
    Assert.IsTrue(Text.Contains(PROBE_FILE + ':42'), 'Fakt Datei:Zeile');
    Assert.IsTrue(Text.Contains(PROBE_METHOD),       'Fakt Methode');
    Assert.IsTrue(Text.Contains(PROBE_MSG),          'Fakt Meldetext');
    Assert.IsTrue(Text.Contains(PROBE_HINT),         'Fakt Fix-Hint');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.EmptyMethodAndHint_YieldDashButKeepFiveBullets;
var
  F    : TLeakFinding;
  Text : string;
begin
  F := TLeakFinding.New(PROBE_FILE, '', PROBE_LINE, PROBE_MSG,
    fkMemoryLeak);
  try
    Text := JiraFor(F, '');
    Assert.AreEqual<Integer>(5, CountBullets(Text),
      'Auch mit leeren Fakten bleiben es fuenf Bullets');
    Assert.IsTrue(Text.Contains(': -'),
      'Leere Fakten erscheinen als Strich-Platzhalter');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.MultilineMessage_IsFlattenedToOneLine;
var
  F    : TLeakFinding;
  Text : string;
begin
  F := MakeFinding('erste Zeile' + sLineBreak + 'zweite   Zeile');
  try
    Text := JiraFor(F, PROBE_HINT);
    Assert.IsTrue(Text.Contains('erste Zeile zweite Zeile'),
      'Zeilenumbrueche und Mehrfach-Leerzeichen werden geglaettet');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.OverlongMessage_IsCroppedWithEllipsis;
var
  F    : TLeakFinding;
  Text : string;
begin
  F := MakeFinding(StringOfChar('x', 500));
  try
    Text := JiraFor(F, PROBE_HINT);
    Assert.IsTrue(Text.Contains('...'),
      'Ueberlange Fakten werden mit ... gekuerzt');
    Assert.IsFalse(Text.Contains(StringOfChar('x', 200)),
      'Der Rohtext darf nicht in voller Laenge auftauchen');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.MultilineFinding_ShowsLineRange;
var
  F    : TLeakFinding;
  Text : string;
begin
  F := MakeFinding(PROBE_MSG);
  try
    F.EndLine := 47;
    Text := JiraFor(F, PROBE_HINT);
    Assert.IsTrue(Text.Contains('Demo.pas:42-47'),
      'Mehrzeilige Befunde zeigen den Zeilenbereich');
  finally
    F.Free;
  end;
end;

procedure TTestFindingCopyText.ModeFromInt_MapsOneTwoThree_InvalidFallsToNone;
begin
  Assert.IsTrue(FindingCopyModeFromInt(1) = fcmNone,         'ini-Wert 1');
  Assert.IsTrue(FindingCopyModeFromInt(2) = fcmJiraMini,     'ini-Wert 2');
  Assert.IsTrue(FindingCopyModeFromInt(3) = fcmClaudePrompt, 'ini-Wert 3');
  Assert.IsTrue(FindingCopyModeFromInt(0) = fcmNone,   'ungueltig: 0');
  Assert.IsTrue(FindingCopyModeFromInt(4) = fcmNone,   'ungueltig: 4');
  Assert.IsTrue(FindingCopyModeFromInt(-7) = fcmNone,  'ungueltig: -7');
  Assert.IsTrue(FindingCopyModeFromInt(99) = fcmNone,  'ungueltig: 99');
end;

procedure TTestFindingCopyText.Dispatch_NoneEmpty_JiraStartsWithRule_ClaudeNonEmpty;
var
  F      : TLeakFinding;
  Text   : string;
  Hint   : TFixHint;
begin
  F := MakeFinding(PROBE_MSG);
  try
    Hint := Default(TFixHint);
    Hint.Description := PROBE_HINT;

    Assert.AreEqual('', TFindingCopyText.Build(F, fcmNone, Hint),
      'fcmNone liefert den Leerstring - Zwischenablage bleibt unberuehrt');

    Text := TFindingCopyText.Build(F, fcmJiraMini, Hint);
    Assert.IsTrue(Text.StartsWith('[' + F.ResolvedRuleId + ']'),
      'fcmJiraMini beginnt mit der Regel-ID');

    // Claude-Prompt: kein Vergleich lokalisierter Ueberschriften - nur
    // dass er nicht leer ist und die unlokalisierten Kerndaten traegt.
    Text := TFindingCopyText.Build(F, fcmClaudePrompt, Hint);
    Assert.IsTrue(Text <> '', 'fcmClaudePrompt liefert Text');
    Assert.IsTrue(Text.Contains(KindName(F.Kind)),
      'fcmClaudePrompt traegt den Regel-Kind-Namen');
    Assert.IsTrue(Text.Contains(PROBE_FILE),
      'fcmClaudePrompt traegt den Dateipfad');
  finally
    F.Free;
  end;
end;

end.
