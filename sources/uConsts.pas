unit uConsts;

interface

uses
  System.Classes;

var
  LeakyClasses: array [0 .. 20] of string = (
    'TStringList',
    'TList',
    'TOracleQuery',
    'TOracleSession',
    'TQuery',
    'TSQLQuery',
    'TKSQLQuery',
    'TFileStream',
    'TMemoryStream',
    'TStringStream',
    'TBitmap',
    'TFont',
    'TThread',
    'TComponent',
    'TDataSet',
    'TSocket',
    'TRegistry',
    'TResourceStream',
    'TXMLDocument',
    'THTTPClient',
    'TTimer'
  );

type
  TConsts = record
    class function GetLeakyClasses: TStringList; static;
  end;

implementation

{ TConsts }

class function TConsts.GetLeakyClasses: TStringList;
var
  myLeakyClasses: TStringList;
begin
  myLeakyClasses := TStringList.Create;
  myLeakyClasses.AddStrings(LeakyClasses);
  Result := myLeakyClasses;
end;

end.
