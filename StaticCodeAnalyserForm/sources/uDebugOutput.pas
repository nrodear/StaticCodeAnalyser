unit uDebugOutput;

// Detektor fuer Debug-Ausgaben in Produktionscode.
// Erkennt Aufrufe von:
//   WriteLn / Write           (Console-Output – meist vergessen)
//   ShowMessage / MessageDlg  (Dialog-Popups – stoeren in Produktion)
//   OutputDebugString         (Debug-Ausgabe)
//   InputBox / InputQuery     (modale Eingabe – nicht in Bibliotheken)

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDebugOutputDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  DEBUG_CALLS : array[0..7] of string = (
    'writeln(', 'writeln ',
    'showmessage(', 'showmessagepos(',
    'messagedlg(', 'messagedlgpos(',
    'outputdebugstring(',
    'inputbox('
  );

class procedure TDebugOutputDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls   : TList<TAstNode>;
  N       : TAstNode;
  NameLow : string;
  Found   : string;
  F       : TLeakFinding;
begin
  Calls := UnitNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      NameLow := N.Name.ToLower;
      Found   := '';

      for var Kw in DEBUG_CALLS do
      begin
        var p := Pos(Kw, NameLow);
        if p = 0 then Continue;
        // Wortgrenze pruefen: davor darf kein Bezeichner-Zeichen stehen
        // (sonst matcht 'WriteLn' auch 'MyWriteLn')
        if p > 1 then
        begin
          var Prev := NameLow[p - 1];
          if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
        end;
        // Name extrahieren bis zur Klammer
        var EndPos := p;
        while (EndPos <= Length(Kw)) and
              CharInSet(Kw[EndPos], ['a'..'z']) do
          Inc(EndPos);
        Found := Copy(Kw, 1, Length(Kw) - 1); // ohne '('
        Break;
      end;

      if Found = '' then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := 'Debug-Ausgabe: ' + Found.Trim;
      F.Severity   := lsWarning;
      F.Kind       := fkDebugOutput;
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

end.
