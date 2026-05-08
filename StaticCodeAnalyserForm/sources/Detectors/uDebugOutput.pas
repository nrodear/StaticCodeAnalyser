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
  Calls : TList<TAstNode>;
  N     : TAstNode;

  // Helper - prueft einen Call-/RHS-String gegen die DEBUG_CALLS-Liste
  // und emittiert ggf. einen Befund. Wird sowohl fuer nkCall.Name als
  // auch nkAssign.TypeRef aufgerufen (z.B. 's := InputBox(...)' hat
  // den InputBox-Aufruf in nkAssign.TypeRef, nicht als eigene nkCall).
  procedure CheckCallText(const CallText: string; Line: Integer);
  var
    NameLow : string;
    Found   : string;
    F       : TLeakFinding;
  begin
    NameLow := CallText.ToLower;
    Found   := '';
    for var Kw in DEBUG_CALLS do
    begin
      var p := Pos(Kw, NameLow);
      if p = 0 then Continue;
      if p > 1 then
      begin
        var Prev := NameLow[p - 1];
        if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
      end;
      var EndPos := p;
      while (EndPos <= Length(NameLow)) and
            CharInSet(NameLow[EndPos], ['a'..'z']) do
        Inc(EndPos);
      Found := Copy(NameLow, p, EndPos - p);
      Break;
    end;
    if Found = '' then Exit;
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Line);
    F.MissingVar := 'Debug output: ' + Found.Trim;
    F.Severity   := lsWarning;
    F.Kind       := fkDebugOutput;
    Results.Add(F);
  end;

var
  Assigns : TList<TAstNode>;
begin
  Calls := UnitNode.FindAll(nkCall);
  try
    for N in Calls do
      CheckCallText(N.Name, N.Line);
  finally
    Calls.Free;
  end;
  // Auch nkAssign-RHS pruefen - Aufrufe wie 's := InputBox(...)' oder
  // 'Result := WriteLnHelper(...)' leben im TypeRef der Zuweisung.
  Assigns := UnitNode.FindAll(nkAssign);
  try
    for N in Assigns do
      CheckCallText(N.TypeRef, N.Line);
  finally
    Assigns.Free;
  end;
end;

end.
