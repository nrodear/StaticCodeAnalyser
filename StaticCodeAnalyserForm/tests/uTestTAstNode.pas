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
    [Test]
    procedure Test_Create_SetsKindAndName;
    [Test]
    procedure Test_Add_AddsChild;
    [Test]
    procedure Test_FindFirst_ReturnsCorrectNode;
    [Test]
    procedure Test_FindAll_ReturnsAllNodes;
    [Test]
    procedure Test_ChildCount_CountsCorrectly;
  end;

implementation

procedure TTestAstNode.Test_Create_SetsKindAndName;
var
  Node: TAstNode;
begin
  Node := TAstNode.Create(nkUnit, 'MyUnit', 1, 1);
  try
    Assert.AreEqual(nkUnit, Node.Kind);
    Assert.AreEqual('MyUnit', Node.Name);
    Assert.AreEqual(1, Node.Line);
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
      Assert.AreEqual(2, All.Count);
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

initialization
  TDUnitX.RegisterTestFixture(TTestAstNode);

end.
