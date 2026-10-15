unit uTestRdxFixTable;

// Die Tabelle der einfachen Editorhilfen (uRdxFixTable, Charge R8): jede
// Zeile vollstaendig - Planer, Hinweis (fest oder vom Planer), Menuetext,
// zweiter Eintrag genau mit zweitem Menuetext -, die Arten eindeutig und
// gleich Handles, Menuetexte mit Name, Variante und Kennzeichnung, der
// Einstieg ohne Fund und ohne Zeile, Hinweis und Kennzeichnung aus der
// Zeile. Bis Charge R8 zeigte eine Art ohne Menuetext still ihren internen
// Namen, und kein Test fiel (Wochen-Review 2026-10-13, Bereich B, Major 4).
// Nur in reDelphix.Test (die Tabelle braucht den Laeufer, nicht im
// FPC-Pruefstand).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFixTable = class
  public
    [Test] procedure EveryRow_HasPlanHintAndCaption;
    [Test] procedure Rows_UniqueAndEqualHandles;
    [Test] procedure CaptionFor_NameVariantChanges;
    [Test] procedure FixFor_NoFindingOrRow;
    [Test] procedure FixFor_TableHintAndChanges;
    // Charge FB (missed R5(5), Absprache mit FE zu R5-06): der feste
    // Hinweis von SCA121 stimmt fuer jeden eingesetzten Wert.
    [Test] procedure ResultDefaultHint_NamesShownValue;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uMethodd12, uSCAConsts, uRdxRecipeRunner, uRdxFixTable;

// Zeilen mit CRLF verbunden - wie in den uebrigen Testunits.
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TTestRdxFixTable.EveryRow_HasPlanHintAndCaption;
var
  i : Integer;
  R : TRdxFixRow;
  K : string;
begin
  Assert.IsTrue(TRdxFixTable.RowCount > 20, 'die Tabelle ist gefuellt');
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    R := TRdxFixTable.Row(i);
    K := KindName(R.Kind);
    Assert.IsTrue(Assigned(R.Plan), K + ': Planer');
    Assert.IsTrue((R.Hint <> '') <> R.HintByPlanner,
      K + ': Hinweis fest ODER vom Planer, nicht beides und nicht keins');
    Assert.AreNotEqual('', TRdxFixTable.RawCaption(i, 0), K + ': Menuetext');
    Assert.AreNotEqual(K, TRdxFixTable.RawCaption(i, 0),
      K + ': der Menuetext ist nicht der interne Name');
    Assert.IsTrue(Assigned(R.Alt) = (TRdxFixTable.RawCaption(i, 1) <> ''),
      K + ': zweiter Eintrag genau mit zweitem Menuetext');
  end;
end;

procedure TTestRdxFixTable.Rows_UniqueAndEqualHandles;
var
  Seen : array[TFindingKind] of Boolean;
  K    : TFindingKind;
  i, n : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
    Seen[K] := False;
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    K := TRdxFixTable.Row(i).Kind;
    Assert.IsFalse(Seen[K], KindName(K) + ' steht zweimal in der Tabelle');
    Seen[K] := True;
  end;
  n := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Assert.AreEqual(Seen[K], TRdxFixTable.Handles(K), 'Handles: ' + KindName(K));
    if Seen[K] then Inc(n);
  end;
  Assert.AreEqual<Integer>(TRdxFixTable.RowCount, n);
end;

procedure TTestRdxFixTable.CaptionFor_NameVariantChanges;
// Seit Charge C0 (Entscheid E29) uebersetzt CaptionFor in die reDelphix-
// Sprache, und der Testlauf steht auf Deutsch (reDelphix.Test.dpr): die
// Erwartungen sind die msgstr aus i18n/de.po - so prueft der Test auch,
// dass die msgids dort stehen. Die englische msgid selbst liefert
// RawCaption.
var
  O : TRdxFixOutcome;
  i : Integer;
begin
  O := Default(TRdxFixOutcome);
  O.Name := 'Obj';
  Assert.AreEqual('FreeAndNil(Obj) verwenden',
    TRdxFixTable.CaptionFor(fkFreeAndNilHint, O));
  O.Name := '';
  Assert.AreEqual('FreeAndNil(X) verwenden',
    TRdxFixTable.CaptionFor(fkFreeWithoutNil, O), 'ohne Namen steht X');
  Assert.AreEqual('Assigned() statt Vergleich mit nil verwenden',
    TRdxFixTable.CaptionFor(fkNilComparison, O));
  O.Variant := 1;
  Assert.AreEqual('else-Zweig mit Exception erg'#$00E4'nzen',
    TRdxFixTable.CaptionFor(fkDefaultCaseInCaseStatement, O));
  Assert.AreEqual('ENotImplemented im leeren Rumpf ausl'#$00F6'sen',
    TRdxFixTable.CaptionFor(fkEmptyMethod, O));
  Assert.AreEqual('', TRdxFixTable.CaptionFor(fkSuperfluousSemicolon, O),
    'ohne zweiten Eintrag kein Menuetext');
  O.Variant := 0;
  O.ChangesBehavior := True;
  O.Name := 'System.Classes';
  Assert.AreEqual('Unit System.Classes aus uses entfernen ('#$00E4'ndert '
    + 'Verhalten)', TRdxFixTable.CaptionFor(fkUnusedUses, O));
  Assert.AreEqual('', TRdxFixTable.CaptionFor(fkConcatToFormat, O),
    'ohne Zeile kein Menuetext (und kein KindName)');
  for i := 0 to TRdxFixTable.RowCount - 1 do
    if TRdxFixTable.Row(i).Kind = fkFreeAndNilHint then
      Assert.AreEqual('Use FreeAndNil(%s)', TRdxFixTable.RawCaption(i, 0),
        'die msgid bleibt englisch');
end;

procedure TTestRdxFixTable.FixFor_NoFindingOrRow;
var
  O : TRdxFixOutcome;
  F : TLeakFinding;
begin
  O := TRdxFixTable.FixFor(nil, nil, nil, nil);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual('kein Fund', O.Reason);
  Assert.AreEqual<Integer>(0, TRdxFixTable.AlternativeFixFor(nil, nil, nil, nil).Variant);
  F := TLeakFinding.New('t.pas', '', 1, 'x', fkConcatToFormat);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual('keine einfache Hilfe fuer diese Regel', O.Reason);
    Assert.AreEqual<Integer>(0, TRdxFixTable.AlternativeFixFor(nil, nil, F, nil).Variant);
  finally
    F.Free;
  end;
end;

procedure TTestRdxFixTable.FixFor_TableHintAndChanges;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  // SCA082 plant nur auf den Zeilen (kein Dienst noetig): aktiv, und den
  // Hinweis setzt die Zeile der Tabelle.
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', 4, 'Superfluous semicolon at column 7',
    fkSuperfluousSemicolon);
  try
    SL.Text := Join(['unit u;', 'implementation', 'procedure P;',
      'begin ; ;', 'end;', 'end.']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual('das zweite ";" war eine leere Anweisung', O.Hint);
    Assert.IsFalse(O.ChangesBehavior);
  finally
    F.Free;
    SL.Free;
  end;
  // SCA120 ist nach E2 gekennzeichnet - auch gesperrt (hier: keine Datei).
  F := TLeakFinding.New('t.pas', '', 1, 'Exception EFoo.Create(...) is '
    + 'constructed but never raised', fkMissingRaise);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual('keine Datei geoeffnet', O.Reason);
    Assert.IsTrue(O.ChangesBehavior, 'SCA120 aendert das Verhalten');
  finally
    F.Free;
  end;
  // SCA149: der Planer setzt Name und Kennzeichnung nach dem Rat der
  // Meldung - override im Menuetext und gekennzeichnet.
  F := TLeakFinding.New('t.pas', '', 1, 'Method TD.X shadows virtual TB.X - '
    + 'missing `override`', fkMissingOverride);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.AreEqual('override', O.Name);
    Assert.IsTrue(O.ChangesBehavior);
    Assert.AreEqual('"override;" an die Deklaration anf'#$00FC'gen ('#$00E4
      + 'ndert Verhalten)', TRdxFixTable.CaptionFor(fkMissingOverride, O));
  finally
    F.Free;
  end;
  // SCA075 bekam mit der Tabelle ERSTMALS einen festen Hinweis - wie
  // SCA074, SCA087 und SCA066 (bis Charge R8 leer; Gegen-Review R8,
  // Major 1): woertlich gepinnt. Der Planer plant nur auf den Zeilen.
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', 3, '`class(TObject)` at column 10 - drop '
    + 'the parens (TObject is the implicit base class).',
    fkExplicitTObjectInheritance);
  try
    SL.Text := Join(['unit u;', 'type', '  TFoo = class(TObject)', '  end;',
      'implementation', 'end.']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual('TObject ist ohnehin der Vorfahr - gleiche Bedeutung',
      O.Hint);
    Assert.IsFalse(O.ChangesBehavior);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxFixTable.ResultDefaultHint_NamesShownValue;
var
  i : Integer;
  R : TRdxFixRow;
begin
  // Der Menuetext nennt den Wert (ein Literal oder Default(T)); bis Charge
  // FB versprach der Hinweis '(wie Default(T))' - falsch, wenn ein Member
  // wie der erste Aufzaehlungswert heisst (Gegen-Review R5-06, Fall 2).
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    R := TRdxFixTable.Row(i);
    if R.Kind <> fkRoutineResultUnassigned then
      Continue;
    Assert.IsFalse(R.HintByPlanner, 'SCA121: fester Hinweis der Zeile');
    Assert.AreEqual('Result beginnt jetzt mit dem genannten Wert statt '
      + 'zufaellig - spaetere Zuweisungen gelten weiter', R.Hint);
    Exit;
  end;
  Assert.Fail('keine Zeile fuer SCA121');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFixTable);

end.
