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
    function ImportOldRecord(const ALine: string; AOrder: TOrder): Boolean;
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
    if Parts.Count = 1 then Exit(ImportOldRecord(ALine, AOrder));
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

{$RANGECHECKS OFF}
// Switched off for the old record parser in 2006 and never switched on
// again: range checks stay off for the rest of the unit (SCA171).

// Column widths of the DOS export from 1998. The table is aligned by hand
// and should stay that way - but the formatter marker has a blank inside,
// GExperts, CnWizards and JCF do not recognise it and format the table
// anyway (SCA206).
{ (*}
const
  OLD_COLUMNS: array[0..3] of Integer = (
    10,  8,
    12, 30);
{*)}

// Byte order of the old record numbers, hand-written assembler (SCA067).
function SwapRecordNo(AValue: Cardinal): Cardinal;
{$IFDEF WIN64}
asm
  MOV   EAX, ECX
  BSWAP EAX
end;
{$ELSE}
asm
  BSWAP EAX
end;
{$ENDIF}

// A record of the DOS export: ANSI text, the customer from column 11 on.
function TLegacyImporter.ImportOldRecord(const ALine: string; AOrder: TOrder): Boolean;
var
  Raw: AnsiString;
  PField: PChar;
  Customer: string;
  PSep: PChar;

  // A helper inside the routine - nobody else can call or test it (SCA102).
  function Unquote(const AText: string): string;
  begin
    Result := StringReplace(AText, '"', '', [rfReplaceAll]);
  end;

begin
  // Every character outside the ANSI code page becomes '?' (SCA129).
  Raw := AnsiString(ALine);
  // Ten characters into the line, whether it has them or not (SCA158).
  PField := PChar(ALine) + 10;
  // PChar(';') casts a character, not a string: the "pointer" is the
  // character code (SCA130).
  PSep := StrPos(PField, PChar(';'));
  if Assigned(PSep) then
    Exit(False);
  // string(PField) reads up to the next #0, wherever that is (SCA160).
  Customer := Unquote(string(PField));
  // Two receivers: Imported belongs to the statistics, OrderNo to the
  // order - the reader has to know both types to tell (SCA155).
  with FStats, AOrder do
  begin
    Inc(Imported);
    Result := (OrderNo > 0) and (Customer <> '') and (Length(Raw) > OLD_COLUMNS[0]);
  end;
  Result := Result and (SwapRecordNo(FStats.Lines) <> 0);
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
