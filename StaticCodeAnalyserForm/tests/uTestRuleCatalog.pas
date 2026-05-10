unit uTestRuleCatalog;

// Tests fuer TRuleCatalog (rules/sca-rules.json).
// Konsistenz-Suite: stellt sicher dass jeder TFindingKind einen Catalog-
// Eintrag hat. Wenn jemand einen neuen Detector + TFindingKind hinzufuegt
// ohne JSON zu pflegen, faellt der Test sofort auf.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uSCAConsts, uRuleCatalog;

type
  [TestFixture]
  TTestRuleCatalog = class
  public
    [Setup] procedure Setup;

    // Pro TFindingKind muss eine Rule existieren mit nicht-leerer ID.
    [Test] procedure EveryFindingKindHasRule;
    // ID-Konvention: 'SCA' + 3-stellige Nummer.
    [Test] procedure RuleIDsFollowConvention;
    // IDs muessen unique sein.
    [Test] procedure RuleIDsAreUnique;
    // Kind-Name in JSON muss zu KindName(K) matchen.
    [Test] procedure KindNameMatchesCatalog;
    // Tool-Info muss gesetzt sein (fuer SARIF tool.driver-Block).
    [Test] procedure ToolInfoIsPopulated;
    // Lookup ueber ID muss alle Kinds zurueckliefern koennen.
    [Test] procedure GetRuleByIDRoundtrip;
  end;

implementation

uses
  System.Generics.Collections, System.RegularExpressions;

procedure TTestRuleCatalog.Setup;
begin
  TRuleCatalog.Reload; // garantiert frischen Zustand pro Test
end;

procedure TTestRuleCatalog.EveryFindingKindHasRule;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.IsNotEmpty(Meta.ID,
      Format('Kind %s hat keine Rule-ID im Catalog', [KindName(K)]));
    Assert.AreEqual(K, Meta.Kind,
      Format('Kind-Mismatch fuer %s', [KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.RuleIDsFollowConvention;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  Rx   : TRegEx;
begin
  Rx := TRegEx.Create('^SCA\d{3}$');
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.IsTrue(Rx.IsMatch(Meta.ID),
      Format('Rule-ID "%s" matcht nicht SCAxxx-Konvention', [Meta.ID]));
  end;
end;

procedure TTestRuleCatalog.RuleIDsAreUnique;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  Seen : TDictionary<string, Boolean>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRule(K);
      Assert.IsFalse(Seen.ContainsKey(Meta.ID),
        Format('Doppelte Rule-ID: %s', [Meta.ID]));
      Seen.Add(Meta.ID, True);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TTestRuleCatalog.KindNameMatchesCatalog;
// Catalog-JSON kind-Feld muss exakt zu KindName(K) passen, sonst stimmt
// die Zuordnung nicht.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    // Meta.Kind muss bereits korrekt zum Lookup-K passen
    Assert.AreEqual(K, Meta.Kind,
      Format('Catalog-Kind %s sollte %s sein',
        [KindName(Meta.Kind), KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.ToolInfoIsPopulated;
begin
  Assert.IsNotEmpty(TRuleCatalog.ToolName,
    'tool.driver.name fehlt in rules/sca-rules.json');
  Assert.IsNotEmpty(TRuleCatalog.ToolVersion,
    'tool.driver.version fehlt');
  // Uri ist optional, aber wenn vorhanden sollte sie kein Bullshit sein
end;

procedure TTestRuleCatalog.GetRuleByIDRoundtrip;
var
  K       : TFindingKind;
  M1, M2  : TRuleMeta;
  Found   : Boolean;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    M1 := TRuleCatalog.GetRule(K);
    Found := TRuleCatalog.GetRuleByID(M1.ID, M2);
    Assert.IsTrue(Found,
      Format('GetRuleByID("%s") nicht gefunden', [M1.ID]));
    Assert.AreEqual(M1.Kind, M2.Kind,
      Format('Roundtrip Kind-Mismatch fuer %s', [M1.ID]));
  end;
end;

end.
