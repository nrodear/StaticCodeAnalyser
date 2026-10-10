program measure;

// Vorab-Messung (Todo I3.1): laesst die ECHTE Zerlegung (uRefactorConcat)
// ueber die Korpus-Fundstellen laufen. Eingabe: TSV  datei<TAB>zeile<TAB>plus
// (plus = -1: nicht gegenpruefen). Die Spalte kennt nur der AST - hier wird
// ersatzweise jeder Bezeichner-Anfang der Zeile probiert und der erste
// genommen, an dem die Zerlegung gelingt.

uses
  SysUtils, Classes, uRefactorInfo, uRefactorInfoBuilder, uRefactorConcat;

var
  List, Lines, Cols : TStringList;
  CurFile  : string;
  i, c, k  : Integer;
  FileName : string;
  LineNo, Plus : Integer;
  Info     : TRefactorInfo;
  L        : string;
  Total, NoFile, Delivered, Multi, HasCmt, Safe, AllStr : Integer;
  Lits, Ops, OpsStr : Integer;
  OnlyStr  : Boolean;
  Root     : string;
  Dump     : Boolean;
begin
  Root := ParamStr(2);
  Dump := ParamStr(3) = 'dump';
  List := TStringList.Create;
  Lines := TStringList.Create;
  Cols := TStringList.Create;
  Cols.Delimiter := #9;
  Cols.StrictDelimiter := True;
  List.LoadFromFile(ParamStr(1));
  CurFile := '';
  Total := 0; NoFile := 0; Delivered := 0; Multi := 0; HasCmt := 0;
  Safe := 0; AllStr := 0; Lits := 0; Ops := 0; OpsStr := 0;
  for i := 0 to List.Count - 1 do
  begin
    Cols.DelimitedText := List[i];
    if Cols.Count < 3 then Continue;
    FileName := Root + '\' + StringReplace(Cols[0], '/', '\', [rfReplaceAll]);
    LineNo := StrToIntDef(Cols[1], 0);
    Plus := StrToIntDef(Cols[2], -1);
    Inc(Total);
    if FileName <> CurFile then
    begin
      Lines.Clear;
      CurFile := FileName;
      if FileExists(FileName) then
        try Lines.LoadFromFile(FileName); except Lines.Clear; end;
    end;
    if (LineNo < 1) or (LineNo > Lines.Count) then
    begin
      Inc(NoFile);
      Continue;
    end;
    L := Lines[LineNo - 1];
    Info := nil;
    for c := 1 to Length(L) do
      if TRefactorInfoBuilder.IsIdentStart(L[c])
         and ((c = 1) or not TRefactorInfoBuilder.IsIdentChar(L[c - 1])) then
      begin
        Info := TRefactorConcat.TryDescribeAssign(nil, Lines, LineNo, c, Plus);
        if (not Assigned(Info)) and (Plus = -1) then
          Info := TRefactorConcat.TryDescribeCall(nil, Lines, LineNo, c);
        if Assigned(Info) then Break;
      end;
    if not Assigned(Info) then
    begin
      if Dump then Writeln('NIL  ', Cols[0], ':', LineNo, '  ', Trim(L));
      Continue;
    end;
    Inc(Delivered);
    if rfMultiLine in Info.Flags then Inc(Multi);
    if rfHasComment in Info.Flags then Inc(HasCmt);
    if Info.FixSafe then Inc(Safe);
    OnlyStr := True;
    for k := 0 to High(Info.Parts) do
      if Info.Parts[k].Role = ROLE_LITERAL then
        Inc(Lits)
      else if Info.Parts[k].Role = ROLE_OPERAND then
      begin
        Inc(Ops);
        if Info.Parts[k].ValueType = rvString then Inc(OpsStr)
        else OnlyStr := False;
      end;
    if OnlyStr then Inc(AllStr);
    Info.Free;
  end;
  Writeln('Funde gesamt          ', Total);
  Writeln('Zeile nicht lesbar    ', NoFile);
  Writeln('beschrieben (<> nil)  ', Delivered);
  Writeln('  davon mehrzeilig    ', Multi);
  Writeln('  davon mit Kommentar ', HasCmt);
  Writeln('  alle Operanden str  ', AllStr);
  Writeln('  FixSafe             ', Safe);
  Writeln('Literal-Terme         ', Lits);
  Writeln('Operanden             ', Ops, '  davon rvString ', OpsStr);
end.
