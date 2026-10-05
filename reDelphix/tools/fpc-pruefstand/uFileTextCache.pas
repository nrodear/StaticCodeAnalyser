unit uFileTextCache;

// Stub fuer den FPC-Pruefstand: nur LoadFileSmart (ohne Encoding-Stufen).

interface

uses
  Classes;

function LoadFileSmart(const FileName: string; SL: TStringList): Boolean;

implementation

uses
  SysUtils;

function LoadFileSmart(const FileName: string; SL: TStringList): Boolean;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    SL.LoadFromFile(FileName);
    Result := True;
  except
    Result := False;
  end;
end;

end.
