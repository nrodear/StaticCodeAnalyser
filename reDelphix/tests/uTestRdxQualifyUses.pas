unit uTestRdxQualifyUses;

// TRdxRecipeRunner.QualifyUses - die Planung von 'uses: X -> Scope.X',
// bis 2026-10-10 im Anbieter und ungetestet (Review reDelphiX nach
// Bereichen, Minor 11-14). Echter Parser ueber TSourcePlaces.OpenSource,
// eine kleine Scope-Tabelle aus Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxQualifyUses = class
  public
    [Test] procedure ItemsOnLine_AndAll;
    [Test] procedure OutsideClause_Nothing;
    // Minor 14: eine sortierte Klausel bleibt sortiert (SCA142-Regel).
    [Test] procedure SortedClause_StaysSorted;
    // Minor 12: FPC-Modus am Dateikopf, ausserhalb der Klausel.
    [Test] procedure FpcSwitch_Blocks;
    [Test] procedure Directives_Block;
    [Test] procedure NoTable_Blocks;
    [Test] procedure OwnUnit_NotOffered;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uEngineApi, uRdxScopeTable, uRdxRecipeRunner,
  uTestRdxTextKit;   // LineOf

const
  SCOPES: array[0..4] of string = (
    'classes=System.Classes',
    'messages=Winapi.Messages',
    'sysutils=System.SysUtils',
    'windows=Winapi.Windows',
    'variants=System.Variants');

function NewScopes: TRdxScopeTable;
var
  SL : TStringList;
  S  : string;
begin
  Result := TRdxScopeTable.Create;
  SL := TStringList.Create;
  try
    for S in SCOPES do
      SL.Add(S);
    Result.LoadFromStrings(SL);
  finally
    SL.Free;
  end;
end;

// Plan fuer die Zeile mit AMarker in ASource.
function PlanFor(const ASource, AMarker: string; AScopes: TRdxScopeTable;
  const AOwn: TRdxOwnUnitCheck): TRdxQualifyPlan;
var
  P : TSourcePlaces;
begin
  P := TSourcePlaces.Create;
  try
    Assert.IsTrue(P.OpenSource('q.pas', ASource));
    Result := TRdxRecipeRunner.QualifyUses(P, AScopes, LineOf(ASource, AMarker),
      AOwn);
  finally
    P.Free;
  end;
end;

function Src(const AHead, AUses: string): string;
begin
  Result := AHead + 'unit q;'#13#10'interface'#13#10 + AUses + #13#10
    + 'implementation'#13#10'end.';
end;

procedure TTestRdxQualifyUses.ItemsOnLine_AndAll;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    // Schon unsortiert (Windows vor Classes): keine Sortiersperre.
    Plan := PlanFor(Src('', 'uses Windows, Classes, Foo;'), 'uses', S, nil);
    Assert.IsTrue(Plan.InClause);
    Assert.IsTrue(Plan.Block = qbNone);
    Assert.AreEqual<Integer>(3, Length(Plan.Items));
    Assert.AreEqual('Winapi.Windows', Plan.Items[0].Qualified);
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[0].Why);
    Assert.AreEqual('Windows', Plan.Items[0].Edit.Expected);
    Assert.AreEqual('Winapi.Windows', Plan.Items[0].Edit.NewText);
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[1].Why);
    Assert.AreEqual<TRdxQualifyWhy>(qwScopeTable, Plan.Items[2].Why,
      'Foo kennt die Tabelle nicht');
    Assert.IsTrue(Plan.Items[2].ScopeReason <> '');
    Assert.AreEqual<Integer>(2, Length(Plan.All));
    Assert.AreEqual('Winapi.Windows, System.Classes', Plan.AllPreview);
    Assert.IsFalse(Plan.AllUnsorts);
    // Mehr Ziele als MAX_QUALIFY_PREVIEW (3): die Vorschau nennt drei und
    // ', ...' (bis zum Wochen-Review 2026-10-21 ohne Test - die groesste
    // Fixture hatte drei Eintraege).
    Plan := PlanFor(Src('', 'uses Windows, Classes, Variants, Messages;'),
      'uses', S, nil);
    Assert.AreEqual<Integer>(4, Length(Plan.All));
    Assert.AreEqual('Winapi.Windows, System.Classes, System.Variants, ...',
      Plan.AllPreview);
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.OutsideClause_Nothing;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    Plan := PlanFor(Src('', 'uses Windows, Classes;'), 'implementation', S, nil);
    Assert.IsFalse(Plan.InClause);
    Assert.AreEqual<Integer>(0, Length(Plan.Items));
    Assert.AreEqual<Integer>(0, Length(Plan.All));
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.SortedClause_StaysSorted;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    // Classes < Messages < SysUtils: 'System.Classes' vor 'Messages' und
    // 'Winapi.Messages' vor 'SysUtils' braechen die Ordnung,
    // 'System.SysUtils' am Ende nicht.
    Plan := PlanFor(Src('', 'uses Classes, Messages, SysUtils;'), 'uses', S, nil);
    Assert.AreEqual<Integer>(3, Length(Plan.Items));
    Assert.AreEqual<TRdxQualifyWhy>(qwUnsorts, Plan.Items[0].Why, 'Classes');
    Assert.AreEqual<TRdxQualifyWhy>(qwUnsorts, Plan.Items[1].Why, 'Messages');
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[2].Why, 'SysUtils');
    Assert.AreEqual<Integer>(3, Length(Plan.All),
      'alle bleiben qualifizierbar - gesperrt ist nur das Ergebnis');
    Assert.IsTrue(Plan.AllUnsorts, 'Winapi.Messages vor System.SysUtils');
    // Gegenprobe: System.Classes, System.SysUtils bleibt sortiert.
    Plan := PlanFor(Src('', 'uses Classes, SysUtils;'), 'uses', S, nil);
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[0].Why);
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[1].Why);
    Assert.IsFalse(Plan.AllUnsorts);
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.FpcSwitch_Blocks;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    Plan := PlanFor(Src('{$mode objfpc}{$H+}'#13#10, 'uses Windows, Classes;'),
      'uses', S, nil);
    Assert.IsTrue(Plan.InClause);
    Assert.IsTrue(Plan.Block = qbFpcSwitch, 'FPC 3.2 kennt keine Unit-Scopes');
    Assert.AreEqual<Integer>(0, Length(Plan.Items));
    Assert.AreEqual<Integer>(0, Length(Plan.All));
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.Directives_Block;
var
  S    : TRdxScopeTable;
  SrcT : string;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    SrcT := Src('', 'uses'#13#10'  {$IFDEF X}Windows,{$ENDIF}'#13#10'  Classes;');
    Plan := PlanFor(SrcT, 'Classes;', S, nil);
    Assert.IsTrue(Plan.Block = qbDirectives);
    Assert.AreEqual<Integer>(LineOf(SrcT, '{$IFDEF X}'), Plan.BlockLine);
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.NoTable_Blocks;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := TRdxScopeTable.Create;
  try
    Plan := PlanFor(Src('', 'uses Windows, Classes;'), 'uses', S, nil);
    Assert.IsTrue(Plan.Block = qbNoTable);
    Plan := PlanFor(Src('', 'uses Windows, Classes;'), 'uses', nil, nil);
    Assert.IsTrue(Plan.Block = qbNoTable, 'ohne Tabelle');
  finally
    S.Free;
  end;
end;

procedure TTestRdxQualifyUses.OwnUnit_NotOffered;
var
  S    : TRdxScopeTable;
  Plan : TRdxQualifyPlan;
begin
  S := NewScopes;
  try
    Plan := PlanFor(Src('', 'uses Windows, Classes;'), 'uses', S,
      function(const AShortName: string): Boolean
      begin
        Result := SameText(AShortName, 'Classes');
      end);
    Assert.AreEqual<TRdxQualifyWhy>(qwOk, Plan.Items[0].Why);
    Assert.AreEqual<TRdxQualifyWhy>(qwOwnUnit, Plan.Items[1].Why,
      'eigene Unit Classes im Projekt');
    Assert.AreEqual<Integer>(1, Length(Plan.All));
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxQualifyUses);

end.
