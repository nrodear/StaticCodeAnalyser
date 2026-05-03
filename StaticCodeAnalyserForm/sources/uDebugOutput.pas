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
        // Wortgrenze LINKS pruefen: davor darf kein Bezeichner-Zeichen
        // stehen (sonst matcht 'WriteLn' auch 'MyWriteLn').
        // Wortgrenze RECHTS ist implizit: alle DEBUG_CALLS-Patterns enden
        // auf '(' oder ' ' - beides Nicht-Identifier-Chars. Daher kann
        // 'writeln(' nicht in 'writeln_debug()' matchen (das '_' nach
        // 'writeln' verhindert den Pos-Match an 'writeln(' bereits).
        if p > 1 then
        begin
          var Prev := NameLow[p - 1];
          if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
        end;
        // Name aus dem TATSAECHLICHEN Source extrahieren (vorher: Found
        // kopierte aus dem Pattern Kw, EndPos wurde gegen Length(Kw)
        // gemessen statt Length(NameLow) - beides falsch).
        var EndPos := p;
        while (EndPos <= Length(NameLow)) and
              CharInSet(NameLow[EndPos], ['a'..'z']) do
          Inc(EndPos);
        Found := Copy(NameLow, p, EndPos - p);
        Break;
      end;

      if Found = '' then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := 'Debug output: ' + Found.Trim;
      F.Severity   := lsWarning;
      F.Kind       := fkDebugOutput;
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

end.
