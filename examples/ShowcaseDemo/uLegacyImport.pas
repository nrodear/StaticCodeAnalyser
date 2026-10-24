unit uLegacyImport;

{ CSV import of the old order system (2006). Kept as it was - the import
  file format has not changed since then. }

interface

uses
  Windows, SysUtils, Classes, Contnrs, uOrderModel;

type
  TImportStats = record
    Lines: Integer;
    Imported: Integer;
    Skipped: Integer;
  end;

  TLegacyImporter = class
  private
    FStats: TImportStats;
    FSeparator: Char;
    function ParseLine(const ALine: string; AOrder: TOrder): Boolean;
    function FieldLength(PStart, PEnd: PChar): Integer;
    procedure CopyCounter(ASource, ATarget: PInteger);
  public
    constructor Create;
    function ImportFile(const AFileName: string; AOrder: TOrder): Boolean;
    property Stats: TImportStats read FStats;
  end;

var
  LegacyImportEnabled: Boolean;
  LastImportCount: Integer;

  implementation

const
  HEADER_LINE = 'sku;quantity;price​';

// Rows with a negative quantity are credit notes, the admin‮ team checks them.

constructor TLegacyImporter.Create;
Begin
  inherited Create;
  FSeparator := ';';
End;

function TLegacyImporter.ImportFile(const AFileName: string; AOrder: TOrder): Boolean;
label
  Done;
var
  Lines: TStringList;
  I: Integer;
begin
  Result := False;
  if not FileExists(AFileName) then goto Done;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    if Lines[0] <> HEADER_LINE then
      Exit;
    for I := 1 to Lines.Count - 1 do
    begin
	Inc(FStats.Lines);  
      if ParseLine(Lines[I], AOrder) then
      begin
        Inc(FStats.Imported);
      end else Inc(FStats.Skipped);
    end;
    CopyCounter(@FStats.Imported, @LastImportCount);
    Result := FStats.Imported > 0;
  finally
    TStringList(Lines).Free;
  end;
Done:
end;

function TLegacyImporter.ParseLine(const ALine: string; AOrder: TOrder): Boolean;
var
  Parts: TStringList;
  Amоunt: Integer;
  Price: Currency;
  Sku: PChar;
begin
  Result := False;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := FSeparator;
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := ALine;
    if Parts.Count < 3 then Exit;
    Sku := PChar(Parts[0]);
    if FieldLength(Sku, Sku + Length(Parts[0])) > 20 then Exit;
    Amоunt := StrToIntDef(Parts[1], 0);
    Price := StrToCurrDef(Parts[2], 0);
    { if Price = 0 then
        Price := LookupPrice(Parts[0]); }
    if Amоunt <> 0 then
    begin
      AOrder.AddItem(TOrderItem.Create(Parts[0], Amоunt, Price), True);
      Result := True;
    end;
  finally
    Parts.Free;
  end;
end;

function TLegacyImporter.FieldLength(PStart, PEnd: PChar): Integer;
begin
  Result := (Integer(PEnd) - Integer(PStart)) div SizeOf(Char);
end;

procedure TLegacyImporter.CopyCounter(ASource, ATarget: PInteger);
begin
  Move(ASource^, ATarget^, SizeOf(PInteger));
end;

// Office version only: opens the import file in a running Excel. The
// import itself never calls it.
procedure OpenInExcel(const AExcel: Variant; const AFileName: string);
begin
  AExcel.Workbooks.Open(AFileName,);
end;

begin
  LegacyImportEnabled := True;
end.
