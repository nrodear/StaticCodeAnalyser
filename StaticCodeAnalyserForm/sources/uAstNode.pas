unit uAstNode;

// Delphi-AST: Knotentypen und Baumstruktur.
// Jeder TAstNode repräsentiert ein syntaktisches Konstrukt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TNodeKind = (
    // --- Kompilationseinheit ---
    nkUnit, nkInterface, nkImplementation,
    // --- Klauseln ---
    nkUses, nkUsesItem,
    nkTypeSection, nkVarSection, nkConstSection,
    // --- Typdeklarationen ---
    nkClass, nkRecord, nkEnumType, nkTypeAlias,
    nkVisibilitySection,            // public / private / protected / published
    // --- Klassen-Member ---
    nkField, nkProperty, nkMethod,
    nkParam,
    // --- Methodenrumpf ---
    nkLocalVar,
    nkBlock,                        // begin ... end
    // --- Anweisungen ---
    nkAssign,
    nkCall,
    nkIfStmt, nkElseBranch,
    nkCaseStmt, nkCaseArm,
    nkForStmt, nkWhileStmt, nkRepeatStmt,
    nkTryExcept, nkTryFinally,
    nkExceptBlock, nkOnHandler,
    nkFinallyBlock,
    nkRaise, nkExit, nkBreak, nkContinue,
    nkInherited,
    // --- Ausdrücke (vereinfacht) ---
    nkIdent, nkLiteral, nkBinaryOp, nkUnaryOp,
    nkIndex, nkDot, nkDeref,
    // --- Sonstiges ---
    nkUnknown
  );

  TNodeKindName = record
    class function ToString(AKind: TNodeKind): string; static;
  end;

  TAstNode = class
  public
    Kind     : TNodeKind;
    Name     : string;     // Bezeichner, Operator oder Literal-Text
    TypeRef  : string;     // Typname bei Var, Param, Field, Method
    Line     : Integer;
    Col      : Integer;
    Children : TObjectList<TAstNode>;

    constructor Create(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0);
    destructor Destroy; override;

    function Add(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0): TAstNode;
    function AddChild(ANode: TAstNode): TAstNode;

    // Suche – gibt Liste ohne Ownership zurück (Caller muss Free aufrufen)
    function FindAll(AKind: TNodeKind): TList<TAstNode>;
    function FindFirst(AKind: TNodeKind): TAstNode;
    function HasChild(AKind: TNodeKind): Boolean;
    function ChildCount(AKind: TNodeKind): Integer;

  private
    procedure CollectAll(AKind: TNodeKind; const AList: TList<TAstNode>);
  end;

implementation

{ TNodeKindName }

class function TNodeKindName.ToString(AKind: TNodeKind): string;
const
  Names: array[TNodeKind] of string = (
    'Unit','Interface','Implementation',
    'Uses','UsesItem',
    'TypeSection','VarSection','ConstSection',
    'Class','Record','EnumType','TypeAlias',
    'VisibilitySection',
    'Field','Property','Method',
    'Param',
    'LocalVar',
    'Block',
    'Assign','Call',
    'IfStmt','ElseBranch',
    'CaseStmt','CaseArm',
    'ForStmt','WhileStmt','RepeatStmt',
    'TryExcept','TryFinally',
    'ExceptBlock','OnHandler',
    'FinallyBlock',
    'Raise','Exit','Break','Continue',
    'Inherited',
    'Ident','Literal','BinaryOp','UnaryOp',
    'Index','Dot','Deref',
    'Unknown'
  );
begin
  Result := Names[AKind];
end;

{ TAstNode }

constructor TAstNode.Create(AKind: TNodeKind; const AName: string;
  ALine, ACol: Integer);
begin
  inherited Create;
  Kind     := AKind;
  Name     := AName;
  Line     := ALine;
  Col      := ACol;
  Children := TObjectList<TAstNode>.Create(True);
end;

destructor TAstNode.Destroy;
begin
  Children.Free;
  inherited;
end;

function TAstNode.Add(AKind: TNodeKind; const AName: string;
  ALine, ACol: Integer): TAstNode;
begin
  Result := TAstNode.Create(AKind, AName, ALine, ACol);
  Children.Add(Result);
end;

function TAstNode.AddChild(ANode: TAstNode): TAstNode;
begin
  Children.Add(ANode);
  Result := ANode;
end;

procedure TAstNode.CollectAll(AKind: TNodeKind; const AList: TList<TAstNode>);
var
  Child: TAstNode;
begin
  for Child in Children do
  begin
    if Child.Kind = AKind then
      AList.Add(Child);
    Child.CollectAll(AKind, AList);
  end;
end;

function TAstNode.FindAll(AKind: TNodeKind): TList<TAstNode>;
begin
  Result := TList<TAstNode>.Create;
  CollectAll(AKind, Result);
end;

function TAstNode.FindFirst(AKind: TNodeKind): TAstNode;
var
  Child: TAstNode;
begin
  for Child in Children do
  begin
    if Child.Kind = AKind then
      Exit(Child);
    Result := Child.FindFirst(AKind);
    if Assigned(Result) then
      Exit;
  end;
  Result := nil;
end;

function TAstNode.HasChild(AKind: TNodeKind): Boolean;
begin
  Result := Assigned(FindFirst(AKind));
end;

function TAstNode.ChildCount(AKind: TNodeKind): Integer;
var
  List: TList<TAstNode>;
begin
  List := FindAll(AKind);
  try
    Result := List.Count;
  finally
    List.Free;
  end;
end;

end.
