unit uTypeResolver;

// Stub fuer den FPC-Pruefstand: uSourcePlaces (AH12) nutzt den
// Typ-Resolver des Cores fuer P9. Hier loest er nichts auf ('') - die
// Typtests laufen nur unter Delphi gegen den echten Parser.

interface

uses
  uAstNode;

type
  TTypeResolver = class
  public
    // Signatur wie im Core (Review reDelphiX 2026-10-07, Minor 11; nach
    // Bereichen 2026-10-10, Minor 3: AStrict).
    constructor Create(UnitNode: TAstNode; AShortStringAware: Boolean = False;
      AStrict: Boolean = False);
    procedure ForgetClass(const AName: string);
    function ResolveTypeAt(const IdentLow: string; Line: Integer): string;
  end;

function IsStringTypeName(const TypeLow: string): Boolean;
function IsNumericTypeName(const TypeLow: string): Boolean;

implementation

constructor TTypeResolver.Create(UnitNode: TAstNode;
  AShortStringAware: Boolean; AStrict: Boolean);
begin
  inherited Create;
end;

procedure TTypeResolver.ForgetClass(const AName: string);
begin
end;

function TTypeResolver.ResolveTypeAt(const IdentLow: string;
  Line: Integer): string;
begin
  Result := '';
end;

function IsStringTypeName(const TypeLow: string): Boolean;
begin
  Result := (TypeLow = 'string') or (TypeLow = 'ansistring')
    or (TypeLow = 'unicodestring') or (TypeLow = 'widestring');
end;

function IsNumericTypeName(const TypeLow: string): Boolean;
begin
  Result := (TypeLow = 'integer') or (TypeLow = 'double')
    or (TypeLow = 'boolean') or (TypeLow = 'char');
end;

end.
