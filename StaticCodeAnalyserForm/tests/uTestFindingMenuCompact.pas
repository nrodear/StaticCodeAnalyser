unit uTestFindingMenuCompact;

// Tests fuer das Aktionsmenue nach Vorschlag 2 (Konzept 2026-10-24, mit
// Nicos Aenderungen "2b" vom selben Tag) in uFindingActionMenu: kurze
// Menuetexte mit Kennzeichnung hinter #9 ('=' bedeutungsgleich, sonst der
// Kopf des Hints), voller Hint samt Meldung im Hint, kurze Kopfzeilen
// (Regelname), EIN Untermenue 'Unterdruecken' am Ende der Fund-Gruppen mit
// Kopfzeile 'SCAnnn  Art' je Fund, Bilder je Eintrag (Entry.Icon), Dedup
// von Fund- und Kontextaktion ueber die Caption VOR #9. Die Erwartungen
// sind ausgeschriebene Zeichenketten - vor Vorschlag 2 stand dort
// 'Caption  (Hint)' und je Fund ein flacher Unterdrueck-Block.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindingMenuCompact = class
  public
    [Test] procedure HintHead_CutBeforeDash;
    [Test] procedure HintHead_LongCutAtWordWithEllipsis;
    [Test] procedure ShortMenuText_HardCutAndPunctuation;
    [Test] procedure Caption_SameMeaning_EqualsInColumn;
    [Test] procedure Caption_ChangesBehavior_HintHeadInColumn;
    [Test] procedure Caption_Disabled_ReasonHeadInColumn;
    [Test] procedure Caption_NoMark_NoTab;
    [Test] procedure Hint_JoinsActionHintAndFindingMessage;
    [Test] procedure Header_CatalogNameNotMessage;
    [Test] procedure Header_CustomRule_MessageCut;
    [Test] procedure SuppressHeader_RuleIdAndKind;
    [Test] procedure Suppress_OneSubmenuAtEnd_GroupPerFinding;
    [Test] procedure Suppress_OnlyFindingsWithSuppress_InSubmenu;
    [Test] procedure Suppress_NoneAtAll_NoSubmenuNoTrailingSeparator;
    [Test] procedure Submenu_DisabledWhenNoChildAvailable;
    [Test] procedure Submenu_BeforeContextSection;
    [Test] procedure Dedup_ContextActionDifferentMark_Dropped;
    [Test] procedure Dedup_SameActionSameEntryCaption;
    [Test] procedure Icons_BulbOnlyForAvailableFixAndContext;
    [Test] procedure KeyPolicy_SuppressInSubmenu_IndexUnchanged;
  end;

implementation

uses
  System.SysUtils,
  uMethodd12, uSCAConsts, uFindingActions, uFindingActionMenu,
  uRuleCatalog,    // Regelname der Kopfzeile
  uLocalization;   // _('Suppress'), CurrentLanguage

type
  TExecOwner = class
    procedure DoExecute(Sender: TObject);
  end;

var
  GExec : TExecOwner = nil;

const
  ELLIPSIS = #$2026;
  TAB      = #9;

procedure TExecOwner.DoExecute(Sender: TObject);
begin
end;

function Act(const ACaption, AHint: string; AKind: TFindingActionKind;
  AEnabled: Boolean = True): TFindingAction;
begin
  Result := Default(TFindingAction);
  Result.Caption := ACaption;
  Result.Hint    := AHint;
  Result.Kind    := AKind;
  Result.Enabled := AEnabled;
  if AEnabled then
    Result.Execute := GExec.DoExecute;
end;

function Finding(const AMsg: string): TLeakFinding;
begin
  Result := TLeakFinding.New('C:\t.pas', 'Run', 10, AMsg, fkConcatToFormat);
end;

// Ein bzw. zwei Funde mit ihren Aktionen (keine geschachtelten Array-
// Literale: die Listen entstehen hier).
function Model1(F: TLeakFinding; const AActs: TArray<TFindingAction>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  Lists : TArray<TArray<TFindingAction>>;
begin
  SetLength(Lists, 1);
  Lists[0] := AActs;
  Result := BuildFindingMenuModelFrom([F], Lists, AOptions);
end;

function Model2(F1, F2: TLeakFinding; const AActs1, AActs2: TArray<TFindingAction>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  Lists : TArray<TArray<TFindingAction>>;
begin
  SetLength(Lists, 2);
  Lists[0] := AActs1;
  Lists[1] := AActs2;
  Result := BuildFindingMenuModelFrom([F1, F2], Lists, AOptions);
end;

function CountKind(const M: TFindingMenuModel; AKind: TFindingMenuEntryKind): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to High(M.Entries) do
    if M.Entries[i].Kind = AKind then
      Inc(Result);
end;

procedure TTestFindingMenuCompact.HintHead_CutBeforeDash;
begin
  Assert.AreEqual('same meaning',
    FindingHintHead('same meaning - only the form; a further statement'));
  Assert.AreEqual('gleiche Bedeutung',
    FindingHintHead('gleiche Bedeutung - nur die Form'));
  Assert.AreEqual('Zeile 10', FindingHintHead('Zeile 10'), 'ohne " - " ganz');
  Assert.AreEqual('', FindingHintHead(''));
end;

procedure TTestFindingMenuCompact.HintHead_LongCutAtWordWithEllipsis;
begin
  Assert.AreEqual('Free now also runs on an' + ELLIPSIS,
    FindingHintHead('Free now also runs on an exception and on Exit'));
  Assert.AreEqual('independent of the system' + ELLIPSIS,
    FindingHintHead('independent of the system: period as decimal separator '
      + '- for files'), 'Doppelpunkt am Schnitt faellt weg');
end;

procedure TTestFindingMenuCompact.ShortMenuText_HardCutAndPunctuation;
begin
  Assert.AreEqual(StringOfChar('m', 40) + ELLIPSIS,
    ShortMenuText(StringOfChar('m', 70), 40), 'ohne Leerzeichen hart');
  Assert.AreEqual('kurz', ShortMenuText('  kurz  ', 40));
  Assert.AreEqual('aaaa bbbb' + ELLIPSIS,
    ShortMenuText('aaaa bbbb, cccc dddd', 10));
end;

procedure TTestFindingMenuCompact.Caption_SameMeaning_EqualsInColumn;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('Branch at column 31');
  try
    M := Model1(F, [Act('Zweig in begin..end setzen',
      'gleiche Bedeutung - nur die Form', fakFix)], []);
    Assert.AreEqual<Integer>(1, Length(M.Entries));
    Assert.AreEqual('Zweig in begin..end setzen' + TAB + '=', M.Entries[0].Caption);
    Assert.IsTrue(Pos('gleiche Bedeutung - nur die Form', M.Entries[0].Hint) = 1,
      'der volle Hint steht im Hint: ' + M.Entries[0].Hint);
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Caption_ChangesBehavior_HintHeadInColumn;
var
  A : TFindingAction;
begin
  A := Act('try/finally (aendert Verhalten)',
    'die Sperre wird freigegeben - auch bei Exit', fakFix);
  A.ChangesBehavior := True;
  Assert.AreEqual('try/finally (aendert Verhalten)' + TAB
    + 'die Sperre wird freigegeben', FindingActionCaption(A),
    'verfuegbar, aber verhaltensaendernd: der Kopf des Hints, kein "="');
end;

procedure TTestFindingMenuCompact.Caption_Disabled_ReasonHeadInColumn;
begin
  Assert.AreEqual('Konstante' + TAB + 'kein Literal am Caret',
    FindingActionCaption(Act('Konstante',
      'kein Literal am Caret - Caret auf eine Zahl setzen', fakFix, False)),
    'gesperrt: der Grund, nicht "="');
end;

procedure TTestFindingMenuCompact.Caption_NoMark_NoTab;
begin
  Assert.AreEqual('Stelle zeigen',
    FindingActionCaption(Act('Stelle zeigen', '', fakNavigate)));
  Assert.AreEqual('Stelle zeigen' + TAB + 'Zeile 10',
    FindingActionCaption(Act('Stelle zeigen', 'Zeile 10', fakNavigate)),
    'Navigieren aendert nichts - kein "="');
end;

procedure TTestFindingMenuCompact.Hint_JoinsActionHintAndFindingMessage;
var
  F : TLeakFinding;
  A : TFindingAction;
begin
  F := Finding('Branch at column 31');
  try
    A := Act('Zweig setzen', 'gleiche Bedeutung - nur die Form', fakFix);
    Assert.AreEqual('gleiche Bedeutung - nur die Form' + MENU_HINT_JOIN
      + F.ResolvedRuleId + ': Branch at column 31', FindingActionHint(A, F));
    Assert.AreEqual('gleiche Bedeutung - nur die Form', FindingActionHint(A, nil),
      'ohne Fund (Code-Aktion) nur der Hint');
    A.Hint := '';
    Assert.AreEqual(F.ResolvedRuleId + ': Branch at column 31',
      FindingActionHint(A, F));
    Assert.IsTrue(Pos('|', MENU_HINT_JOIN) = 0, 'GetLongHint schnitte am |');
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Header_CatalogNameNotMessage;
var
  F    : TLeakFinding;
  Name : string;
begin
  F := Finding('xyzzy message text');
  try
    Name := TRuleCatalog.GetRule(F.Kind, CurrentLanguage).Name;
    Assert.IsTrue(Name <> '', 'der Katalog kennt die Regel');
    Assert.AreEqual(F.ResolvedRuleId + '  ' + ShortMenuText(Name,
      MENU_HEADER_TITLE_CHARS), FindingHeaderCaption(F));
    Assert.IsTrue(Pos('xyzzy', FindingHeaderCaption(F)) = 0,
      'die Meldung steht im Hint, nicht im Kopf');
    Assert.AreEqual('', FindingHeaderCaption(nil));
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Header_CustomRule_MessageCut;
var
  F : TLeakFinding;
begin
  F := Finding(StringOfChar('m', 70));
  try
    F.RuleID := 'CUSTOM01';
    Assert.AreEqual('CUSTOM01  ' + StringOfChar('m', 40) + ELLIPSIS,
      FindingHeaderCaption(F));
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.SuppressHeader_RuleIdAndKind;
var
  F : TLeakFinding;
begin
  F := Finding('Branch at column 31');
  try
    Assert.AreEqual(F.ResolvedRuleId + '  ' + KindName(F.Kind),
      FindingSuppressHeaderCaption(F));
    Assert.AreEqual('', FindingSuppressHeaderCaption(nil));
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Suppress_OneSubmenuAtEnd_GroupPerFinding;
var
  F1, F2 : TLeakFinding;
  M      : TFindingMenuModel;
  i      : Integer;
begin
  F1 := Finding('A'); F2 := Finding('B');
  try
    M := Model2(F1, F2,
      [Act('Fix A', 'same meaning - a', fakFix),
       Act('Hier', '// noinspection ConcatToFormat', fakSuppress),
       Act('Datei', '// noinspection-file ConcatToFormat', fakSuppress)],
      [Act('Fix B', 'same meaning - b', fakFix),
       Act('Hier', '// noinspection ConcatToFormat', fakSuppress),
       Act('Datei', '// noinspection-file ConcatToFormat', fakSuppress)],
      [moLeadingSeparator, moHeaders]);
    // Trenner, Kopf A, Fix A, Trenner, Kopf B, Fix B, Trenner,
    // Unterdruecken > [Kopf A, Hier, Datei, Trenner, Kopf B, Hier, Datei]
    Assert.AreEqual<Integer>(15, Length(M.Entries));
    Assert.AreEqual<Integer>(1, CountKind(M, mkSubmenu), 'EIN Untermenue');
    Assert.IsTrue(M.Entries[3].Kind = mkSeparator, 'Trenner nach Gruppe A');
    Assert.IsTrue(M.Entries[6].Kind = mkSeparator, 'Trenner vor Unterdruecken');
    Assert.IsTrue(M.Entries[7].Kind = mkSubmenu);
    Assert.AreEqual(_('Suppress'), M.Entries[7].Caption);
    Assert.IsTrue(M.Entries[7].Enabled);
    Assert.AreEqual<Integer>(-1, M.Entries[7].ActionIndex);
    Assert.IsTrue(M.Entries[7].Icon = miSuppress);
    for i := 0 to 7 do
      Assert.AreEqual<Integer>(-1, M.Entries[i].Parent, 'oben: ' + IntToStr(i));
    for i := 8 to 14 do
      Assert.AreEqual<Integer>(7, M.Entries[i].Parent, 'im Untermenue: ' + IntToStr(i));
    Assert.IsTrue(M.Entries[8].Kind = mkHeader);
    Assert.AreEqual(FindingSuppressHeaderCaption(F1), M.Entries[8].Caption);
    Assert.IsTrue(M.Entries[8].Icon = miRule, 'Eule vor der Kopfzeile im Untermenue');
    Assert.IsTrue(M.Entries[1].Icon = miNone, 'oben keine Eule');
    Assert.AreEqual('Hier', M.Entries[9].Caption, 'nur die Aktion, kein Marker');
    Assert.AreEqual('// noinspection ConcatToFormat', M.Entries[9].Hint);
    Assert.AreEqual<Integer>(1, M.Entries[9].ActionIndex);
    Assert.IsTrue(M.Entries[11].Kind = mkSeparator, 'Trenner zwischen den Funden');
    Assert.AreEqual<Integer>(5, M.Entries[14].ActionIndex);
    Assert.AreEqual<Integer>(6, M.ActionCount);
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingMenuCompact.Suppress_OnlyFindingsWithSuppress_InSubmenu;
var
  F1, F2 : TLeakFinding;
  M      : TFindingMenuModel;
begin
  F1 := Finding('nur Hilfe'); F2 := Finding('nur Unterdruecken');
  try
    M := Model2(F1, F2, [Act('Fix', '', fakFix)],
      [Act('Hier', '// m', fakSuppress)], [moHeaders]);
    // Kopf 1, Fix, Trenner, Unterdruecken > [Kopf 2, Hier]
    Assert.AreEqual<Integer>(6, Length(M.Entries));
    Assert.IsTrue(M.Entries[2].Kind = mkSeparator);
    Assert.IsTrue(M.Entries[3].Kind = mkSubmenu);
    Assert.AreEqual(FindingSuppressHeaderCaption(F2), M.Entries[4].Caption);
    Assert.AreEqual<Integer>(1, CountKind(M, mkHeader) - 1,
      'oben nur der Kopf des Funds mit Hilfe');
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingMenuCompact.Suppress_NoneAtAll_NoSubmenuNoTrailingSeparator;
var
  F1, F2 : TLeakFinding;
  M      : TFindingMenuModel;
begin
  F1 := Finding('a'); F2 := Finding('b');
  try
    M := Model2(F1, F2, [Act('A', '', fakFix)], [Act('B', '', fakFix)],
      [moHeaders]);
    Assert.AreEqual<Integer>(5, Length(M.Entries), 'Kopf, A, Trenner, Kopf, B');
    Assert.AreEqual<Integer>(0, CountKind(M, mkSubmenu));
    Assert.IsTrue(M.Entries[High(M.Entries)].Kind = mkAction, 'kein Trenner am Ende');
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingMenuCompact.Submenu_DisabledWhenNoChildAvailable;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('x');
  try
    M := Model1(F, [Act('Hier', 'gesperrt', fakSuppress, False)], []);
    Assert.AreEqual<Integer>(2, Length(M.Entries), 'Untermenue und Eintrag');
    Assert.IsTrue(M.Entries[0].Kind = mkSubmenu);
    Assert.IsFalse(M.Entries[0].Enabled);
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Submenu_BeforeContextSection;
var
  F   : TLeakFinding;
  M   : TFindingMenuModel;
  Sub : Integer;
  i   : Integer;
begin
  F := Finding('x');
  try
    M := Model1(F, [Act('Fix', '', fakFix), Act('Hier', '// m', fakSuppress)],
      [moLeadingSeparator, moHeaders]);
    AppendContextActions(M, [Act('Konstante', '', fakFix)],
      [moLeadingSeparator, moHeaders], 'Code actions');
    Sub := -1;
    for i := 0 to High(M.Entries) do
      if M.Entries[i].Kind = mkSubmenu then Sub := i;
    Assert.IsTrue(Sub >= 0);
    Assert.AreEqual<Integer>(3, M.ContextEntryCount, 'Trenner, Kopf, Aktion');
    Assert.IsTrue(Sub < Length(M.Entries) - M.ContextEntryCount,
      'Unterdruecken vor dem Abschnitt der Code-Aktionen');
    Assert.AreEqual('Konstante' + TAB + '=', M.Entries[High(M.Entries)].Caption);
    Assert.AreEqual<Integer>(-1, M.Entries[High(M.Entries)].Parent);
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Dedup_ContextActionDifferentMark_Dropped;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
  C : TFindingAction;
begin
  F := Finding('Magic number');
  try
    M := Model1(F, [Act('Lokale Konstante einfuehren',
      'gleiche Bedeutung - die Konstante haelt das Literal', fakFix)], []);
    C := Act('lokale konstante einfuehren', 'anderer Hint - x', fakFix);
    C.ChangesBehavior := True;
    AppendContextActions(M, [C], [], '');
    Assert.AreEqual<Integer>(0, M.ContextActionCount,
      'Dedup ueber die Caption vor #9 - die Kennzeichnung zaehlt nicht');
    Assert.AreEqual<Integer>(1, M.ActionCount);
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.Dedup_SameActionSameEntryCaption;
var
  A, C : TFindingAction;
begin
  A := Act('Lokale Konstante einfuehren', 'gleiche Bedeutung - x', fakFix);
  C := A;
  C.Kind := fakContext;
  Assert.AreEqual(FindingActionCaption(A), FindingActionCaption(C),
    'Fund-Hilfe und Code-Aktion: derselbe Menuetext samt #9-Teil');
  Assert.AreEqual('Lokale Konstante einfuehren' + TAB + '=',
    FindingActionCaption(C));
end;

procedure TTestFindingMenuCompact.Icons_BulbOnlyForAvailableFixAndContext;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('x');
  try
    M := Model1(F, [Act('Fix', '', fakFix), Act('Gesperrt', 'nein', fakFix, False),
      Act('Zeigen', '', fakNavigate), Act('Umbau', '', fakRefactor)], [moHeaders]);
    Assert.IsTrue(M.Entries[0].Icon = miNone, 'Kopfzeile oben ohne Bild');
    Assert.IsTrue(M.Entries[1].Icon = miBulb, 'verfuegbare Hilfe');
    Assert.IsTrue(M.Entries[2].Icon = miNone, 'gesperrt');
    Assert.IsTrue(M.Entries[3].Icon = miNone, 'Navigieren');
    Assert.IsTrue(M.Entries[4].Icon = miNone, 'Umbau');
    AppendContextActions(M, [Act('Konstante', '', fakFix)], [], '');
    Assert.IsTrue(M.Entries[High(M.Entries)].Icon = miBulb, 'Code-Aktion');
  finally
    F.Free;
  end;
end;

procedure TTestFindingMenuCompact.KeyPolicy_SuppressInSubmenu_IndexUnchanged;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
  C : TFindingKeyChoice;
  i : Integer;
begin
  F := Finding('x');
  try
    M := Model1(F, [Act('Hier', '// m', fakSuppress), Act('Fix', '', fakFix)],
      [moHeaders]);
    C := M.FirstRunnable(fakSuppress);
    Assert.IsTrue(C.Verdict = kvRun);
    Assert.AreEqual<Integer>(0, C.Index, 'Actions in der Reihenfolge des Anbieters');
    for i := 0 to High(M.Entries) do
      if (M.Entries[i].Kind = mkAction) and (M.Entries[i].ActionIndex = 0) then
        Assert.IsTrue(M.Entries[i].Parent >= 0, 'der Eintrag steht im Untermenue');
    Assert.IsTrue(M.Entries[1].Kind = mkAction, 'oben zuerst die Hilfe');
    Assert.AreEqual<Integer>(1, M.Entries[1].ActionIndex);
  finally
    F.Free;
  end;
end;

initialization
  GExec := TExecOwner.Create;
  TDUnitX.RegisterTestFixture(TTestFindingMenuCompact);

finalization
  FreeAndNil(GExec);

end.
