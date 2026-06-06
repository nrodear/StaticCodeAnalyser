unit uTestTAstNode;

interface

uses
  System.Generics.Collections,
  uAstNode,
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAstNode = class
  public
    [Test] procedure Test_Create_SetsKindAndName;
    [Test] procedure Test_Add_AddsChild;
    [Test] procedure Test_FindFirst_ReturnsCorrectNode;
    [Test] procedure Test_FindAll_ReturnsAllNodes;
    [Test] procedure Test_ChildCount_CountsCorrectly;

    // --- Erweiterte Tests (Direct-Child API, Aliase, Edge-Cases) ---
    [Test] procedure FindFirstChild_OnlyDirectChildren_NotSubtree;
    [Test] procedure HasDirectChild_FalseForGrandchild;
    [Test] procedure DirectChildCount_CountsOnlyImmediate;
    [Test] procedure HasDescendant_SameAsHasChild;
    [Test] procedure DescendantCount_SameAsChildCount;
    [Test] procedure ChildCount_ZeroWhenAbsent;
    [Test] procedure NodeKindName_ReturnsReadable;
    [Test] procedure NodeKindNameRecord_DelegatesToFunction;
    [Test] procedure AdoptChildrenFrom_TransfersAndEmpties;
    [Test] procedure FindAll_PreOrderTraversal;
  end;

implementation

uses
  System.SysUtils;

procedure TTestAstNode.Test_Create_SetsKindAndName;
var
  Node: TAstNode;
begin
  Node := TAstNode.Create(nkUnit, 'MyUnit', 1, 1);
  try
    Assert.AreEqual(nkUnit, Node.Kind);
    Assert.AreEqual('MyUnit', Node.Name);
    Assert.AreEqual<Integer>(1, Node.Line);
  finally
    Node.Free;
  end;
end;

procedure TTestAstNode.Test_Add_AddsChild;
var
  Root: TAstNode;
begin
  Root := TAstNode.Create(nkUnit, 'root');
  try
    Root.Add(nkUses, 'uses');
    Root.Add(nkInterface, 'interface');
    Assert.AreEqual(2, Root.Children.Count);
    Assert.AreEqual(nkUses,      Root.Children[0].Kind);
    Assert.AreEqual(nkInterface, Root.Children[1].Kind);
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.Test_FindFirst_ReturnsCorrectNode;
var
  Root: TAstNode;
  Found: TAstNode;
begin
  Root := TAstNode.Create(nkUnit, 'root');
  try
    Root.Add(nkInterface, 'interface').Add(nkUses, 'uses');
    Found := Root.FindFirst(nkUses);
    Assert.IsNotNull(Found);
    Assert.AreEqual(nkUses, Found.Kind);
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.Test_FindAll_ReturnsAllNodes;
var
  Root : TAstNode;
  All  : TList<TAstNode>;
  IFace: TAstNode;
  Impl : TAstNode;
begin
  Root  := TAstNode.Create(nkUnit, 'root');
  try
    IFace := Root.Add(nkInterface, 'interface');
    IFace.Add(nkUses, 'uses1').Add(nkUsesItem, 'System.SysUtils');
    Impl  := Root.Add(nkImplementation, 'implementation');
    Impl.Add(nkUses, 'uses2').Add(nkUsesItem, 'Vcl.Forms');

    All := Root.FindAll(nkUsesItem);
    try
      Assert.AreEqual<Integer>(2, All.Count);
    finally
      All.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.Test_ChildCount_CountsCorrectly;
var
  Root: TAstNode;
begin
  Root := TAstNode.Create(nkUnit, 'root');
  try
    Root.Add(nkMethod, 'm1');
    Root.Add(nkMethod, 'm2');
    Root.Add(nkField,  'f1');
    Assert.AreEqual(2, Root.ChildCount(nkMethod));
    Assert.AreEqual(1, Root.ChildCount(nkField));
    Assert.AreEqual(0, Root.ChildCount(nkBlock));
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.FindFirstChild_OnlyDirectChildren_NotSubtree;
// FindFirstChild darf NICHT in den Subtree absteigen. Wenn nkUses nur
// als Enkel existiert, muss FindFirstChild nil liefern.
var
  Root, Mid : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, 'root');
  try
    Mid := Root.Add(nkInterface, 'interface');
    Mid.Add(nkUses, 'uses');                       // Enkel von Root

    Assert.IsNull(Root.FindFirstChild(nkUses),     'Enkel darf nicht treffen');
    Assert.IsNotNull(Root.FindFirstChild(nkInterface), 'direktes Kind muss treffen');
    Assert.IsNotNull(Mid.FindFirstChild(nkUses),       'direktes Kind von Mid muss treffen');
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.HasDirectChild_FalseForGrandchild;
var
  Root, Mid : TAstNode;
begin
  Root := TAstNode.Create(nkUnit, 'root');
  try
    Mid := Root.Add(nkInterface);
    Mid.Add(nkMethod, 'tiefer');

    Assert.IsFalse(Root.HasDirectChild(nkMethod),
      'HasDirectChild darf nicht in Subtree absteigen');
    Assert.IsTrue(Root.HasChild(nkMethod),
      'HasChild (subtree-wide) muss den Enkel finden');
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.DirectChildCount_CountsOnlyImmediate;
var
  Root, Mid : TAstNode;
begin
  Root := TAstNode.Create(nkUnit);
  try
    Root.Add(nkMethod, 'a');
    Root.Add(nkMethod, 'b');
    Mid := Root.Add(nkClass);
    Mid.Add(nkMethod, 'tief1');
    Mid.Add(nkMethod, 'tief2');
    Mid.Add(nkMethod, 'tief3');

    // 2 direkte Methods, 5 Methods im gesamten Subtree.
    Assert.AreEqual(2, Root.DirectChildCount(nkMethod));
    Assert.AreEqual(5, Root.ChildCount(nkMethod));
    Assert.AreEqual(5, Root.DescendantCount(nkMethod));
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.HasDescendant_SameAsHasChild;
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit);
  try
    Root.Add(nkInterface).Add(nkMethod);
    Assert.AreEqual(Root.HasChild(nkMethod), Root.HasDescendant(nkMethod));
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.DescendantCount_SameAsChildCount;
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit);
  try
    Root.Add(nkMethod);
    Root.Add(nkClass).Add(nkMethod);
    Assert.AreEqual(Root.ChildCount(nkMethod), Root.DescendantCount(nkMethod));
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.ChildCount_ZeroWhenAbsent;
var
  Root : TAstNode;
begin
  Root := TAstNode.Create(nkUnit);
  try
    Assert.AreEqual(0, Root.ChildCount(nkBlock));
    Assert.AreEqual(0, Root.DirectChildCount(nkBlock));
  finally
    Root.Free;
  end;
end;

procedure TTestAstNode.NodeKindName_ReturnsReadable;
begin
  Assert.AreEqual('Unit',        NodeKindName(nkUnit));
  Assert.AreEqual('Method',      NodeKindName(nkMethod));
  Assert.AreEqual('Unknown',     NodeKindName(nkUnknown));
  Assert.AreEqual('TryFinally',  NodeKindName(nkTryFinally));
end;

procedure TTestAstNode.NodeKindNameRecord_DelegatesToFunction;
// TNodeKindName.ToString ist deprecated, muss aber weiterhin das
// gleiche liefern wie die globale Funktion.
begin
  Assert.AreEqual(NodeKindName(nkAssign), TNodeKindName.ToString(nkAssign));
  Assert.AreEqual(NodeKindName(nkUnknown), TNodeKindName.ToString(nkUnknown));
end;

procedure TTestAstNode.AdoptChildrenFrom_TransfersAndEmpties;
var
  Source, Dest : TAstNode;
begin
  Source := TAstNode.Create(nkBlock, 'src');
  Dest   := TAstNode.Create(nkBlock, 'dst');
  try
    Source.Add(nkAssign, 'a');
    Source.Add(nkAssign, 'b');
    Source.Add(nkCall,   'c');

    Dest.AdoptChildrenFrom(Source);

    Assert.AreEqual(0, Source.Children.Count, 'Source muss leer sein');
    Assert.AreEqual(3, Dest.Children.Count,   'Dest muss alle 3 haben');
    Assert.AreEqual('a', Dest.Children[0].Name);
    Assert.AreEqual('b', Dest.Children[1].Name);
    Assert.AreEqual('c', Dest.Children[2].Name);
  finally
    Source.Free;
    Dest.Free;     // gibt die uebernommenen Children frei
  end;
end;

procedure TTestAstNode.FindAll_PreOrderTraversal;
// FindAll soll Pre-Order liefern: Parent vor Children, Children
// links-vor-rechts. Mit zwei nkMethod-Knoten in unterschiedlichen
// Tiefen testen wir die Reihenfolge.
var
  Root, Cls : TAstNode;
  All       : TList<TAstNode>;
begin
  Root := TAstNode.Create(nkUnit);
  try
    Root.Add(nkMethod, 'first-toplevel');
    Cls := Root.Add(nkClass);
    Cls.Add(nkMethod, 'inside-class');
    Root.Add(nkMethod, 'second-toplevel');

    All := Root.FindAll(nkMethod);
    try
      Assert.AreEqual<Integer>(3, All.Count);
      // Pre-Order DFS: first-toplevel, dann nkClass-Subtree (inside-
      // class), dann second-toplevel.
      Assert.AreEqual('first-toplevel',  All[0].Name);
      Assert.AreEqual('inside-class',    All[1].Name);
      Assert.AreEqual('second-toplevel', All[2].Name);
    finally
      All.Free;
    end;
  finally
    Root.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAstNode);

end.
