unit uTestDfmPropValue;

// Smoke-Tests fuer die typisierten Accessors von TPropValue +
// TComponentNode.Get*. Wir fuettern den DFM-Parser direkt mit kleinen
// Inline-Quelltexten - das ist robuster als TPropValue-Records direkt
// zu fingern, weil Kind+RawValue dann garantiert konsistent gesetzt
// sind.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmPropValue = class
  public
    [Test] procedure Test_AsBoolean_True;
    [Test] procedure Test_AsBoolean_False;
    [Test] procedure Test_AsBoolean_Missing_ReturnsDefault;
    [Test] procedure Test_AsBoolean_WrongKind_ReturnsDefault;

    [Test] procedure Test_AsInteger_Positive;
    [Test] procedure Test_AsInteger_Negative;
    [Test] procedure Test_AsInteger_Hex;

    [Test] procedure Test_AsString_Literal;
    [Test] procedure Test_AsString_NotAString_ReturnsDefault;

    [Test] procedure Test_AsIdent_Trimmed;
    [Test] procedure Test_AsIdent_NotAnIdent_ReturnsDefault;

    [Test] procedure Test_SetContains_Found;
    [Test] procedure Test_SetContains_NotFound;
    [Test] procedure Test_SetContains_Empty;
    [Test] procedure Test_SetContains_CaseAndWhitespaceInsensitive;

    [Test] procedure Test_GetBoolean_VclDefault_VisibleTrue;
    [Test] procedure Test_GetBoolean_OverriddenFalse;

    [Test] procedure Test_SetPropertyContains_NoProperty_False;
  end;

implementation

uses
  System.SysUtils, uDfmParser, uComponentGraph;

function ParseRoot(const S: string): TComponentGraph;
var P: TDfmParser;
begin
  P := TDfmParser.Create;
  try
    Result := P.ParseSource(S);
  finally
    P.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsBoolean_True;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Visible = True'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.GetBoolean('Visible', False));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsBoolean_False;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Visible = False'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsFalse(N.GetBoolean('Visible', True));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsBoolean_Missing_ReturnsDefault;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.GetBoolean('Visible', True));   // VCL-Default
    Assert.IsFalse(N.GetBoolean('Enabled', False)); // explizit gewaehlt
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsBoolean_WrongKind_ReturnsDefault;
var G: TComponentGraph; N: TComponentNode;
begin
  // Caption ist String - nicht als Bool lesbar. Default greift.
  G := ParseRoot('object Form1: TForm'#10'  Caption = ''Hi'''#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.GetBoolean('Caption', True));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsInteger_Positive;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Width = 800'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual(800, N.GetInteger('Width', 0));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsInteger_Negative;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Left = -10'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual(-10, N.GetInteger('Left', 0));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsInteger_Hex;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Color = $00FF00FF'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual($00FF00FF, N.GetInteger('Color', 0));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsString_Literal;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Caption = ''Hello'''#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual('Hello', N.GetString('Caption', ''));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsString_NotAString_ReturnsDefault;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Width = 800'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual('fallback', N.GetString('Width', 'fallback'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsIdent_Trimmed;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Color = clRed'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual('clRed', N.GetIdent('Color', ''));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_AsIdent_NotAnIdent_ReturnsDefault;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Caption = ''X'''#10'end'#10);
  try
    N := G.Roots[0];
    Assert.AreEqual('na', N.GetIdent('Caption', 'na'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_SetContains_Found;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot(
    'object Form1: TForm'#10 +
    '  Anchors = [akLeft, akTop, akRight]'#10 +
    'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.SetPropertyContains('Anchors', 'akLeft'));
    Assert.IsTrue(N.SetPropertyContains('Anchors', 'akRight'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_SetContains_NotFound;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot(
    'object Form1: TForm'#10 +
    '  Anchors = [akLeft]'#10 +
    'end'#10);
  try
    N := G.Roots[0];
    Assert.IsFalse(N.SetPropertyContains('Anchors', 'akBottom'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_SetContains_Empty;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot(
    'object Form1: TForm'#10 +
    '  Anchors = []'#10 +
    'end'#10);
  try
    N := G.Roots[0];
    Assert.IsFalse(N.SetPropertyContains('Anchors', 'akLeft'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_SetContains_CaseAndWhitespaceInsensitive;
// Robustness test: extra whitespace + case variation must not trip up
// the membership check.
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot(
    'object Form1: TForm'#10 +
    '  Style = [   FSBOLD   ,  fsItalic ]'#10 +
    'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.SetPropertyContains('Style', 'fsBold'));
    Assert.IsTrue(N.SetPropertyContains('Style', 'FSITALIC'));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_GetBoolean_VclDefault_VisibleTrue;
var G: TComponentGraph; N: TComponentNode;
begin
  // Visible nicht serialisiert -> VCL-Default True wirkt ueber ADefault.
  G := ParseRoot('object Form1: TForm'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsTrue(N.GetBoolean('Visible', True));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_GetBoolean_OverriddenFalse;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'  Visible = False'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsFalse(N.GetBoolean('Visible', True));
  finally
    G.Free;
  end;
end;

procedure TTestDfmPropValue.Test_SetPropertyContains_NoProperty_False;
var G: TComponentGraph; N: TComponentNode;
begin
  G := ParseRoot('object Form1: TForm'#10'end'#10);
  try
    N := G.Roots[0];
    Assert.IsFalse(N.SetPropertyContains('Anchors', 'akLeft'));
  finally
    G.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmPropValue);

end.
