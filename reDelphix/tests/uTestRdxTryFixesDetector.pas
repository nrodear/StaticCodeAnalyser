unit uTestRdxTryFixesDetector;

// Quick-Fixes try/finally (uRdxTryFixes, Charge H4) gegen die ECHTEN
// Detektoren (nur Delphi, reDelphix.Test): Parser, uMissingFinally
// (SCA009), uLeakDetector2 (SCA001), uLockWithoutTryFinally (SCA109),
// uUnpairedLock (SCA153), uGetMemWithoutFreeMem (SCA156), TSourcePlaces und
// TRdxFixTable.FixFor - derselbe Einstieg wie im Anbieter, bei SCA001 mit
// der Variante des Funds (TSeen.Variant, uTestRdxDetectorKit). Je Fall
// meldet der Detektor, die Hilfe plant aus dem Fund, die Ersetzung wird
// angewandt - und derselbe Detektor meldet danach nichts mehr. Dazu die
// Katalog-Beispiele (SCA109/SCA153/SCA156: aus 'bad' wird genau 'good';
// SCA009: 'good' ist einzeilig - verglichen wird die mehrzeilige Form der
// Hilfe; SCA001: 'bad' ist never-freed, keine Hilfe) und Funde, die der
// Detektor meldet und die Hilfe ablehnt (bedingtes Free, never-freed,
// fremde Freigabe, ReallocMem).
//
// Ohne Delphi gegengeprueft (Charge H4): dieselben Quellen mit der CLI-Exe
// gescannt und ueber den FPC-Planer (Korpus-Harness) behoben; ebenso der
// Fall der Charge H4c (Suffix mit umschliessendem try/except) und das
// SCA156-Katalogbeispiel der Charge B1-FE mit 'var P: Pointer;' (die Hilfe
// verlangt seitdem einen lokalen Puffer - Gegen-Review R5, R5-02).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTryFixesDetector = class
  public
    [Test] procedure Sca009_RoundTrip;
    [Test] procedure Sca009_CatalogExample;
    [Test] procedure Sca009_Suffix_RoundTrip;
    [Test] procedure Sca009_SuffixEnclosingExcept_RoundTrip;
    [Test] procedure Sca009_ConditionalFree_NoHelp;
    [Test] procedure Sca001_FreedOutsideFinally_RoundTrip;
    [Test] procedure Sca001_Outcome_MarkedWithCaption;
    [Test] procedure Sca001_NeverFreed_NoHelp;
    [Test] procedure Sca153_CatalogExample;
    [Test] procedure Sca153_ForeignRelease_NoHelp;
    [Test] procedure Sca109_CatalogExample;
    [Test] procedure Sca109_Monitor_RoundTrip;
    [Test] procedure Sca156_CatalogExample;
    [Test] procedure Sca156_Realloc_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uMissingFinally, uLeakDetector2, uLockWithoutTryFinally, uUnpairedLock,
  uGetMemWithoutFreeMem,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor
  uTestRdxDetectorKit,   // TSeen, Detect-/Plan-/FixAll-Helfer
  uTestRdxTextKit;       // Join, Apply

// ---- Helfer ----

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkMissingFinally:
      TMissingFinallyDetector.AnalyzeUnit(Root, Path, Results);
    fkMemoryLeak:
      TLeakDetector2.AnalyzeUnit(Root, Path, Results);
    fkLockWithoutTryFinally:
      TLockWithoutTryFinallyDetector.AnalyzeUnit(Root, Path, Results);
    fkUnpairedLock:
      TUnpairedLockDetector.AnalyzeUnit(Root, Path, Results);
  else
    TGetMemWithoutFreeMemDetector.AnalyzeUnit(Root, Path, Results);
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_try_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund, bis der Detektor schweigt. Der Detektor muss mindestens
// einmal melden - sonst prueft der Fall nichts.
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Assert.IsTrue(Length(Detect(ASource, AKind)) > 0, 'der Detektor meldet');
  Result := FixAllWith(ASource, AKind, Detect);
end;

procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
end;

// Eine Unit mit Routine P, ihren Variablen AVars (Zeilen) und dem Rumpf
// ABody (Zeilen).
function InProc(const AVars, ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', '',
    'procedure P;', 'var']) + #13#10 + Join(AVars) + #13#10 + 'begin' + #13#10
    + Join(ABody) + #13#10 + Join(['end;', '', 'end.']);
end;

// Der Rumpf aus einem Katalog-Beispiel (Zeilen ab Spalte 1).
function InRoutine(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', '',
    'procedure P;', 'begin']) + #13#10 + AText + #13#10
    + Join(['end;', '', 'end.']);
end;

// Dasselbe mit dem lokalen Puffer P: SCA156 hilft seit Charge B1-FE nur bei
// einer lokalen Variable (Gegen-Review R5, R5-02 - ein Feld oder eine
// globale Variable kennte den Puffer nach finally weiter).
function InBufferRoutine(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', '',
    'procedure Run;', 'var', '  P: Pointer;', 'begin']) + #13#10 + AText
    + #13#10 + Join(['end;', '', 'end.']);
end;

// AText ohne die '//'-Kommentare am Zeilenende (samt Leerraum davor): das
// Katalog-Beispiel 'bad' von SCA109 erklaert eine Zeile, 'good' nicht - die
// Hilfe laesst den Kommentar stehen.
function WithoutLineComments(const AText: string): string;
var
  Lines : TArray<string>;
  i, P  : Integer;
begin
  Lines := AText.Split([#13#10]);
  for i := 0 to High(Lines) do
  begin
    P := Pos('//', Lines[i]);
    if P > 0 then
      Lines[i] := TrimRight(Copy(Lines[i], 1, P - 1));
  end;
  Result := string.Join(#13#10, Lines);
end;

// Die SCA001-Quelle der Variante freed-outside-finally (wie
// uTestLeakDetector, Leak_FofVariant_SurvivesErrorSeverity): ein
// try/finally fuer S, das Free von L daneben.
function FofSource: string;
begin
  Result := InProc(['  L, S: TStringList;'], ['  L := TStringList.Create;',
    '  S := TStringList.Create;', '  try', '    L.Add(S.Text);', '  finally',
    '    S.Free;', '  end;', '  L.Free;']);
end;

{ ---- SCA009 ---- }

procedure TTestRdxTryFixesDetector.Sca009_RoundTrip;
begin
  // Ein fremder Aufruf zwischen Create und Free - sonst haelt der
  // Detektor die Spanne fuer harmlos (SafeSpan).
  Assert.AreEqual(InProc(['  L: TStringList;'], ['  L := TStringList.Create;',
    '  try', '    L.Add(''a'');', '    ShowMessage(L.Text);', '  finally',
    '    L.Free;', '  end;']),
    FixAll(InProc(['  L: TStringList;'], ['  L := TStringList.Create;',
      '  L.Add(''a'');', '  ShowMessage(L.Text);', '  L.Free;']),
      fkMissingFinally));
end;

procedure TTestRdxTryFixesDetector.Sca009_CatalogExample;
var
  Meta   : TRuleMeta;
  Seen   : TSeen;
  O      : TRdxFixOutcome;
  Source : string;
begin
  // 'good' steht einzeilig da ('try obj.DoStuff finally obj.Free end;') -
  // die Hilfe setzt try/finally/end in eigene Zeilen. TFoo kennt der
  // Detektor nicht als freizugebende Klasse; geplant wird deshalb aus einem
  // Fund, wie der Detektor ihn schriebe (Zeile des Create, Name).
  Meta := TRuleCatalog.GetRuleCanonical(fkMissingFinally);
  Assert.IsTrue(Pos('obj.Free', Meta.GoodExample) > 0, Meta.GoodExample);
  Source := InRoutine(CatalogText(Meta.BadExample));
  Seen := Default(TSeen);
  Seen.Line := 7;
  Seen.Msg := 'obj';
  O := PlanFixIn(Source, 't.pas', fkMissingFinally, Seen);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(InRoutine(Join(['obj := TFoo.Create;', 'try',
    '  obj.DoStuff;', 'finally', '  obj.Free;', 'end;'])),
    Apply(Source, O.Edits));
end;

procedure TTestRdxTryFixesDetector.Sca009_Suffix_RoundTrip;
var
  Seen : TArray<TSeen>;
  Src  : string;
begin
  // try/except statt try/finally (Meldungs-Suffix): es liegt ganz im
  // Bereich und kommt mit in den try-Teil.
  Src := InProc(['  L: TStringList;'], ['  L := TStringList.Create;', '  try',
    '    L.LoadFromFile(''x.txt'');', '  except', '    ShowMessage(''x'');',
    '  end;', '  ShowMessage(L.Text);', '  L.Free;']);
  Seen := Detect(Src, fkMissingFinally);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.IsTrue(Pos('(try/except instead of try/finally)', Seen[0].Msg) > 0,
    Seen[0].Msg);
  Assert.AreEqual(InProc(['  L: TStringList;'], ['  L := TStringList.Create;',
    '  try', '    try', '      L.LoadFromFile(''x.txt'');', '    except',
    '      ShowMessage(''x'');', '    end;', '    ShowMessage(L.Text);',
    '  finally', '    L.Free;', '  end;']),
    FixAll(Src, fkMissingFinally));
end;

procedure TTestRdxTryFixesDetector.Sca009_SuffixEnclosingExcept_RoundTrip;
var
  Seen : TArray<TSeen>;
  Src  : string;
begin
  // Das Suffix sagt nur, dass die Methode irgendwo ein try/except hat
  // (Gegen-Review H4, Major 1): hier umschliesst es den Bereich und nennt L
  // nicht - nach dem Fix laeuft erst das finally, dann der Handler. Bis
  // Charge H4c gesperrt; Korpus: 41 solche Funde.
  Src := InProc(['  L: TStringList;'], ['  try', '    L := TStringList.Create;',
    '    L.LoadFromFile(''x.txt'');', '    ShowMessage(L.Text);', '    L.Free;',
    '  except', '    ShowMessage(''x'');', '  end;']);
  Seen := Detect(Src, fkMissingFinally);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.IsTrue(Pos('(try/except instead of try/finally)', Seen[0].Msg) > 0,
    Seen[0].Msg);
  Assert.AreEqual(InProc(['  L: TStringList;'], ['  try',
    '    L := TStringList.Create;', '    try', '      L.LoadFromFile(''x.txt'');',
    '      ShowMessage(L.Text);', '    finally', '      L.Free;', '    end;',
    '  except', '    ShowMessage(''x'');', '  end;']),
    FixAll(Src, fkMissingFinally));
end;

procedure TTestRdxTryFixesDetector.Sca009_ConditionalFree_NoHelp;
begin
  // Der Detektor sieht ein Free; es ist bedingt - mit finally liefe es
  // jetzt immer.
  AssertNoHelp(InProc(['  L: TStringList;'], ['  L := TStringList.Create;',
    '  ShowMessage(L.Text);', '  if L.Count = 0 then', '    L.Free;']),
    fkMissingFinally, 'bedingte');
end;

{ ---- SCA001 ---- }

procedure TTestRdxTryFixesDetector.Sca001_FreedOutsideFinally_RoundTrip;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(FofSource, fkMemoryLeak);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.AreEqual('freed-outside-finally', Seen[0].Variant);
  Assert.AreEqual(InProc(['  L, S: TStringList;'], ['  L := TStringList.Create;',
    '  try', '    S := TStringList.Create;', '    try', '      L.Add(S.Text);',
    '    finally', '      S.Free;', '    end;', '  finally', '    L.Free;',
    '  end;']),
    FixAll(FofSource, fkMemoryLeak));
end;

procedure TTestRdxTryFixesDetector.Sca001_Outcome_MarkedWithCaption;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Gekennzeichnet (E2), mit Namen und Hinweis der Tabelle.
  Seen := Detect(FofSource, fkMemoryLeak);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanFixIn(FofSource, 't.pas', fkMemoryLeak, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'aendert Verhalten');
  // Menuetext deutsch: der Testlauf steht auf 'de' (Charge C0, E29).
  Assert.AreEqual('L in einem try/finally-Block freigeben ('#$00E4'ndert '
    + 'Verhalten)', TRdxFixTable.CaptionFor(fkMemoryLeak, O));
  Assert.IsTrue(Pos('auch bei einer Ausnahme', O.Hint) > 0, O.Hint);
end;

procedure TTestRdxTryFixesDetector.Sca001_NeverFreed_NoHelp;
var
  Meta : TRuleMeta;
begin
  // Ohne Free (Katalog-Beispiel 'bad', never-freed bzw. proven-leak):
  // keine Hilfe, der Grund nennt die Variante.
  Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Assert.IsTrue(Pos('list.Free', Meta.BadExample) = 0, Meta.BadExample);
  AssertNoHelp(InProc(['  L: TStringList;'], ['  L := TStringList.Create;',
    '  ShowMessage(L.Text);']), fkMemoryLeak, 'keine Hilfe fuer die Variante');
end;

{ ---- SCA153 ---- }

procedure TTestRdxTryFixesDetector.Sca153_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkUnpairedLock);
  Assert.AreEqual(InRoutine(CatalogText(Meta.GoodExample)),
    FixAll(InRoutine(CatalogText(Meta.BadExample)), fkUnpairedLock));
end;

procedure TTestRdxTryFixesDetector.Sca153_ForeignRelease_NoHelp;
begin
  // Der Detektor nimmt jedes 'release' im Fenster als Partner - die Hilfe
  // sucht FLock.UnLock.
  AssertNoHelp(InRoutine(Join(['  FLock.Lock;', '  DoStuff;',
    '  FOther.Release;'])), fkUnpairedLock, 'keine Freigabe FLock.UnLock');
end;

{ ---- SCA109 ---- }

procedure TTestRdxTryFixesDetector.Sca109_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // 'bad' traegt einen Kommentar hinter DoWork - er rueckt mit in den
  // try-Teil; 'good' hat ihn nicht.
  Meta := TRuleCatalog.GetRuleCanonical(fkLockWithoutTryFinally);
  Assert.IsTrue(Pos('//', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreEqual(InRoutine(CatalogText(Meta.GoodExample)),
    WithoutLineComments(FixAll(InRoutine(CatalogText(Meta.BadExample)),
      fkLockWithoutTryFinally)));
end;

procedure TTestRdxTryFixesDetector.Sca109_Monitor_RoundTrip;
begin
  Assert.AreEqual(InRoutine(Join(['  TMonitor.Enter(FList);', '  try',
    '    FList.Add(1);', '  finally', '    TMonitor.Exit(FList);', '  end;'])),
    FixAll(InRoutine(Join(['  TMonitor.Enter(FList);', '  FList.Add(1);',
      '  TMonitor.Exit(FList);'])), fkLockWithoutTryFinally));
end;

{ ---- SCA156 ---- }

procedure TTestRdxTryFixesDetector.Sca156_CatalogExample;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkGetMemWithoutFreeMem);
  Assert.AreEqual(InBufferRoutine(CatalogText(Meta.GoodExample)),
    FixAll(InBufferRoutine(CatalogText(Meta.BadExample)),
      fkGetMemWithoutFreeMem));
end;

procedure TTestRdxTryFixesDetector.Sca156_Realloc_NoHelp;
begin
  AssertNoHelp(InRoutine(Join(['  ReallocMem(P, 2048);', '  DoStuff(P);',
    '  FreeMem(P);'])), fkGetMemWithoutFreeMem, 'ReallocMem');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTryFixesDetector);

end.
