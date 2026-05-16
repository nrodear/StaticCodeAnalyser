unit uMethodName;

// Detektor fuer Methoden-Namen, die nicht der PascalCase-Konvention
// (UpperCamel) entsprechen.
//
// SonarDelphi-Aequivalent: communitydelphi:MethodName. Delphi-Konvention:
//   * Methoden, Properties und Routinen heissen `DoSomething` (UpperCamel)
//   * NICHT `doSomething` (lowerCamel) oder `do_something` (snake_case)
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten wird Node.Name geprueft -
// falls qualifiziert (`TFoo.Bar`), wird der Teil hinter dem Punkt
// betrachtet. Erstes Zeichen muss ein Grossbuchstabe sein.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMethodNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsHint;

function LocalName(const FullName: string): string;
var
  pDot : Integer;
begin
  pDot := LastDelimiter('.', FullName);
  if pDot > 0 then
    Result := Copy(FullName, pDot + 1, MaxInt)
  else
    Result := FullName;
end;

class procedure TMethodNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Name    : string;
  F       : TLeakFinding;
  Ch      : Char;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Name := LocalName(Trim(M.Name));
      if Name = '' then Continue;
      Ch := Name[1];
      // Operator-Ueberladungen (z.B. `+`, `-`) und magic methods (mit `_`
      // beginnend) ausnehmen.
      if Ch = '_' then Continue;
      if not CharInSet(Ch, ['A'..'Z','a'..'z']) then Continue;
      // PascalCase = Upper als erstes Zeichen
      if CharInSet(Ch, ['A'..'Z']) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        'Method `%s` should be PascalCase (start with uppercase letter).',
        [Name]);
      F.SetKind(fkMethodName);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
