unit uCompilerDirectiveScope;

// Detektor: Compiler-Switch-Direktive (OFF) ohne korrespondierende ON-
// Direktive im selben File. Damit wuerden alle nachfolgenden Compile-
// Units (kette uses-haengt-an) die Switches verloren haben.
//
// Pattern (jeweils OFF muss spaeter ON haben):
//   {$WARNINGS OFF}    ... {$WARNINGS ON}
//   {$HINTS OFF}       ... {$HINTS ON}
//   {$RANGECHECKS OFF} ... {$RANGECHECKS ON}
//   {$BOOLEVAL OFF}    ... {$BOOLEVAL ON}
//   {$OVERFLOWCHECKS OFF} ... {$OVERFLOWCHECKS ON}
//
// Bekannte Falle: {$WARNINGS OFF} am Anfang einer Unit ohne ON am Ende ->
// alle Units die diese Unit verwenden + ihr eigenes uses-File haben
// keine Warnings mehr (die Compiler-State wird zwischen Compilation-Units
// vererbt wenn ohne {$IFDEF}-Schutz).
//
// Erkennung (File-Text-Scan, kein AST):
//   * Pro Zeile per Regex `\{\$(WARNINGS|HINTS|RANGECHECKS|BOOLEVAL|OVERFLOWCHECKS)\s+(ON|OFF)\}` matchen.
//   * Pro Direktiven-Name OFF-Count und ON-Count zaehlen. Wenn OFF > ON
//     beim File-Ende -> Finding (eine Zeile pro unbalanced Direktive,
//     gemeldet auf der LETZTEN OFF-Line ohne folgendes ON).
//
// Limitierungen:
//   * Cross-Unit-INI-Builds (Build-Config-File-Settings) werden nicht
//     gesehen - der File-lokale Push/Pop ist die einzige Quelle.
//   * Direktiven die mit IFDEF gewrappt sind, werden nicht ausgewertet -
//     im worst case False-Positive bei {$IFDEF DEBUG}{$WARNINGS OFF}{$ENDIF}
//     ohne {$WARNINGS ON}. Akzeptabel - Suppression-Marker.
//
// Severity: lsWarning, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCompilerDirectiveScopeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.Classes, System.RegularExpressions,
  uFileTextCache;

const
  DIRECTIVE_RE = '\{\$(WARNINGS|HINTS|RANGECHECKS|BOOLEVAL|OVERFLOWCHECKS)\s+(ON|OFF)\}';

class procedure TCompilerDirectiveScopeDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i        : Integer;
  Line     : string;
  RE       : TRegEx;
  M        : TMatch;
  Name     : string;
  IsOff    : Boolean;
  // Pro Direktiv: Last-OFF-Zeile (-1 wenn nicht offen), Last-OFF-Token.
  LastOff  : TDictionary<string, Integer>;
  Tok      : TPair<string, Integer>;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  LastOff := TDictionary<string, Integer>.Create;
  try
    RE := TRegEx.Create(DIRECTIVE_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      for M in RE.Matches(Line) do
      begin
        Name  := LowerCase(M.Groups[1].Value);
        IsOff := SameText(M.Groups[2].Value, 'OFF');
        if IsOff then
          LastOff.AddOrSetValue(Name, i + 1)   // 1-based line
        else
          LastOff.Remove(Name);                // ON closes scope
      end;
    end;

    // Was uebrig bleibt = OFF ohne folgendes ON.
    for Tok in LastOff do
    begin
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Tok.Value);
      F.MissingVar := '{$' + UpperCase(Tok.Key) + ' OFF} without matching ' +
                      '{$' + UpperCase(Tok.Key) + ' ON} - the switch leaks ' +
                      'into all units compiled after this one.';
      F.SetKind(fkCompilerDirectiveScope);
      Results.Add(F);
    end;
  finally
    LastOff.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
