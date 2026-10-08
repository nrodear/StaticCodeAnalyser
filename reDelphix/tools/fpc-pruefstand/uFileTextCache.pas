unit uFileTextCache;

// Stub fuer den FPC-Pruefstand: nur LoadFileSmart. Dieselben Stufen wie
// im Core (uFileTextCache.LoadFileSmart): UTF-8-BOM -> striktes UTF-8 ->
// ANSI. Ohne die mittlere Stufe las der Stub eine BOM-lose UTF-8-Datei
// als ANSI - genau den Fehler, den Review reDelphiX Major 1 im Parser-Pfad
// fand (uTestSourcePlaces.Open_Utf8WithoutBom_ColumnsMatchLineText).

interface

uses
  Classes;

function LoadFileSmart(const FileName: string; SL: TStringList): Boolean;

implementation

uses
  SysUtils;

// Wohlgeformt, wenn Dekodieren und Wieder-Kodieren dieselben Bytes ergibt.
function IsStrictUtf8(const ABytes: TBytes): Boolean;
var
  U    : UnicodeString;
  Back : TBytes;
  i    : Integer;
begin
  U := TEncoding.UTF8.GetString(ABytes);
  Back := TEncoding.UTF8.GetBytes(U);
  Result := Length(Back) = Length(ABytes);
  if Result then
    for i := 0 to High(ABytes) do
      if Back[i] <> ABytes[i] then
        Exit(False);
end;

function LoadFileSmart(const FileName: string; SL: TStringList): Boolean;
var
  FS    : TFileStream;
  Bytes : TBytes;
  Body  : TBytes;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        FS.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
    if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB)
       and (Bytes[2] = $BF) then
    begin
      Body := Copy(Bytes, 3, Length(Bytes) - 3);
      SL.Text := TEncoding.UTF8.GetString(Body);
    end
    else if IsStrictUtf8(Bytes) then
      SL.Text := TEncoding.UTF8.GetString(Bytes)
    else
      SL.Text := TEncoding.ANSI.GetString(Bytes);
    Result := True;
  except
    Result := False;
  end;
end;

end.
