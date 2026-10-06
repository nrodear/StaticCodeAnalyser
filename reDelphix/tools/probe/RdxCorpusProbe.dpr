program RdxCorpusProbe;

// reDelphix - Korpus-Probe fuer Rezept 5.1 (Verkettung -> Format).
//
// Faehrt fuer jede Stelle einer Liste (Datei<TAB>Zeile; z. B. alle
// SCA044-Funde eines Referenzlaufs, s. sites_from_sarif.py) denselben Weg
// wie das IDE-Package, nur ohne ToolsAPI: TSourcePlaces.Open,
// DescribeAnchor, FormatRewrite. Je Stelle eine CSV-Zeile, am Ende eine
// Zusammenfassung nach stdout. Das sind die ECHTEN Zahlen zur Python-
// Nachbildung (Audit_SCA044_Realworld_2026-10-06.md), die nur eine
// Obergrenze liefert.
//
//   RdxCorpusProbe <sites.txt> <out.csv>
//
// CSV (;-getrennt): Datei;Zeile;aktiv;Kategorie;Grund;Operanden;bewiesen;
// Kompilat;numerisch;SelfAppend;uses;NewText

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  uEngineApi,
  uRefactorInfo,
  uRdxRecipes in '..\..\source\uRdxRecipes.pas',
  uRdxScopeTable in '..\..\source\uRdxScopeTable.pas',
  uRdxRecipeRunner in '..\..\source\uRdxRecipeRunner.pas';

function Csv(const S: string): string;
begin
  Result := StringReplace(TRdxRecipes.CollapseWhitespace(S), ';', ',',
    [rfReplaceAll]);
end;

// Grund -> Kategorie fuer die Zusammenfassung: der Operandenname faellt
// weg, der Typ in Klammern auch.
function CategoryOf(const AReason: string): string;
var
  P : Integer;
begin
  Result := AReason;
  if Copy(Result, 1, 8) = 'Operand ' then
  begin
    P := Pos(''': ', Result);
    if P > 0 then Result := Copy(Result, P + 3, MaxInt);
    P := Pos(' (', Result);
    if P > 0 then Result := Copy(Result, 1, P - 1);
    Result := 'Operand: ' + Result;
  end
  else if Copy(Result, 1, 5) = 'Ziel ' then
    Result := 'Ziel: Nicht-Unicode-String'
  else if Copy(Result, 1, 7) = 'hinter ' then
    Result := 'Selbst-Anhaengen: nur Literale'
  else
  begin
    P := Pos(':', Result);
    if P > 0 then Result := Copy(Result, 1, P - 1);
  end;
end;

var
  Sites     : TStringList;
  Output    : TStringList;
  Places    : TSourcePlaces;
  Reasons   : TDictionary<string, Integer>;
  Pairs     : TArray<TPair<string, Integer>>;
  Pair      : TPair<string, Integer>;
  i, P      : Integer;
  LineNo    : Integer;
  Row, Path : string;
  CurFile   : string;
  Opened    : Boolean;
  UsesNames : TArray<string>;
  Info      : TRefactorInfo;
  IsCall    : Boolean;
  Why       : string;
  O         : TRdxFormatOutcome;
  Cat       : string;
  Total     : Integer;
  Active    : Integer;
  SelfApp   : Integer;
  NeedUses  : Integer;
  ByComp    : Integer;
begin
  if ParamCount < 2 then
  begin
    Writeln('RdxCorpusProbe <sites.txt> <out.csv>');
    Halt(2);
  end;
  Sites   := TStringList.Create;
  Output  := TStringList.Create;
  Reasons := TDictionary<string, Integer>.Create;
  Places  := TSourcePlaces.Create;
  try
    Sites.LoadFromFile(ParamStr(1), TEncoding.UTF8);
    Output.Add('Datei;Zeile;aktiv;Kategorie;Grund;Operanden;bewiesen;'
      + 'Kompilat;numerisch;SelfAppend;uses;NewText');
    CurFile  := '';
    Opened   := False;
    Total    := 0;
    Active   := 0;
    SelfApp  := 0;
    NeedUses := 0;
    ByComp   := 0;
    for i := 0 to Sites.Count - 1 do
    begin
      Row := Sites[i];
      P := Pos(#9, Row);
      if P = 0 then Continue;
      Path   := Copy(Row, 1, P - 1);
      LineNo := StrToIntDef(Trim(Copy(Row, P + 1, MaxInt)), 0);
      if LineNo = 0 then Continue;
      Inc(Total);
      if not SameText(Path, CurFile) then
      begin
        CurFile := Path;
        Opened  := FileExists(Path) and Places.Open(Path);
        if Opened then
          UsesNames := TRdxRecipeRunner.UsesNamesOf(Places)
        else
          UsesNames := nil;
      end;
      O := Default(TRdxFormatOutcome);
      if not Opened then
        O.Reason := 'Datei nicht lesbar'
      else
      begin
        Info := TRdxRecipeRunner.DescribeAnchor(Places, LineNo, 'assign',
          IsCall, Why);
        try
          O := TRdxRecipeRunner.FormatRewrite(Places, Info, Why, UsesNames);
        finally
          Info.Free;
        end;
      end;
      if O.Enabled then
        Cat := 'aktiv'
      else
        Cat := CategoryOf(O.Reason);
      if Reasons.ContainsKey(Cat) then
        Reasons[Cat] := Reasons[Cat] + 1
      else
        Reasons.Add(Cat, 1);
      if O.Enabled then Inc(Active);
      if O.Enabled and O.SelfAppend then Inc(SelfApp);
      if O.Enabled and O.NeedsUses then Inc(NeedUses);
      if O.Enabled and (Length(O.ByCompiler) > 0) then Inc(ByComp);
      Output.Add(Format('%s;%d;%d;%s;%s;%d;%d;%d;%d;%d;%d;%s',
        [Path, LineNo, Ord(O.Enabled), Csv(Cat), Csv(O.Reason), O.Operands,
         O.Proven, Length(O.ByCompiler), O.Numeric, Ord(O.SelfAppend),
         Ord(O.NeedsUses), Csv(O.NewText)]));
    end;
    Output.SaveToFile(ParamStr(2), TEncoding.UTF8);
    Writeln(Format('Stellen: %d  aktiv: %d (%.1f %%)  davon Selbst-Anhaengen: %d'
      + '  mit Kompilat-Operanden: %d  uses noetig: %d',
      [Total, Active, 100.0 * Active / Max(Total, 1), SelfApp, ByComp, NeedUses]));
    Pairs := Reasons.ToArray;
    TArray.Sort<TPair<string, Integer>>(Pairs,
      TComparer<TPair<string, Integer>>.Construct(
        function(const L, R: TPair<string, Integer>): Integer
        begin
          Result := R.Value - L.Value;
        end));
    for Pair in Pairs do
      Writeln(Format('  %5d  %s', [Pair.Value, Pair.Key]));
  finally
    Places.Free;
    Reasons.Free;
    Output.Free;
    Sites.Free;
  end;
end.
