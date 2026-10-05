unit uAstNode;

// Stub fuer den FPC-Pruefstand: nur was uRefactorInfoBuilder, uSourcePlaces
// und die Tests von TAstNode benutzen. Feldnamen und Add-Signatur wie im
// echten uAstNode; die Knotenarten sind eine Teilmenge.

interface

uses
  Generics.Collections;

type
  TNodeKind = (nkUnit, nkInterface, nkImplementation, nkUses, nkUsesItem,
    nkMethod, nkAssign, nkCall, nkConditionalRange);

  TAstNode = class
  public
    Kind     : TNodeKind;
    Name     : string;
    TypeRef  : string;
    Line     : Integer;
    Col      : Integer;
    Children : TObjectList<TAstNode>;
    constructor Create(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0);
    destructor Destroy; override;
    function Add(AKind: TNodeKind; const AName: string = '';
      ALine: Integer = 0; ACol: Integer = 0): TAstNode;
  end;

implementation

constructor TAstNode.Create(AKind: TNodeKind; const AName: string;
  ALine, ACol: Integer);
begin
  inherited Create;
  Kind := AKind;
  Name := AName;
  Line := ALine;
  Col  := ACol;
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

end.
