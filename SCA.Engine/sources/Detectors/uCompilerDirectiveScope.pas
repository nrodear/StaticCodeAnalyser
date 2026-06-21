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
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

const
  // Generischer Direktiven-Match: Name + optional ON/OFF. Dispatch im
  // Loop nach Name - so faengt der Detektor jetzt auch {$PUSH}/{$POP}
  // (State-Save/Restore) und ignoriert alle anderen ({$DEFINE}, {$I ...}).
  DIRECTIVE_RE = '\{\$([A-Za-z]+)\s*(ON|OFF)?\}';

  // Switch-Direktiven deren OFF/ON-Balance wir tracken (lower-case).
  TRACKED : array[0..4] of string = (
    'warnings', 'hints', 'rangechecks', 'booleval', 'overflowchecks');

function IsTracked(const Name: string): Boolean;
var T: string;
begin
  for T in TRACKED do
    if Name = T then Exit(True);
  Result := False;
end;

// Flache Kopie eines OFF-Dict (Name -> 1-based OFF-Line) fuer {$PUSH}.
function CloneOffDict(Src: TDictionary<string, Integer>)
  : TDictionary<string, Integer>;
var P: TPair<string, Integer>;
begin
  Result := TDictionary<string, Integer>.Create;
  for P in Src do
    Result.Add(P.Key, P.Value);
end;

// Strippt Non-Direktive-Kommentare: `//`-Zeilen + `{...}`-Blocks die NICHT
// mit `{$` beginnen + `(*...*)`-Blocks. Wichtig: `{$...}`-Direktiven
// BLEIBEN als-ist im Ergebnis, weil der Detector sie braucht.
// Block-Comment-State spannt nicht ueber Zeilen (Pragma); Compiler-
// Direktiven sind in der Praxis immer single-line, FP-Edge-Case
// akzeptiert.
function StripNonDirectiveComments(const Line: string): string;
var
  Buf  : TStringBuilder;
  j, n : Integer;
  c    : Char;
  pClose : Integer;
begin
  n := Length(Line);
  Buf := TStringBuilder.Create;
  try
    j := 1;
    while j <= n do
    begin
      c := Line[j];
      // //-Kommentar bis Zeilen-Ende
      if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
      // (*...*)-Block - immer Kommentar
      if (c = '(') and (j < n) and (Line[j + 1] = '*') then
      begin
        pClose := PosEx('*)', Line, j + 2);
        if pClose = 0 then Break;
        j := pClose + 2; Continue;
      end;
      // {...}-Block - ABER {$...} ist Direktive und bleibt!
      if c = '{' then
      begin
        if (j < n) and (Line[j + 1] = '$') then
        begin
          // Direktive - vollstaendig uebernehmen (bis '}')
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then Break;
          Buf.Append(Copy(Line, j, pClose - j + 1));
          j := pClose + 1; Continue;
        end
        else
        begin
          // Normaler Block-Comment - skippen
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then Break;
          j := pClose + 1; Continue;
        end;
      end;
      Buf.Append(c);
      Inc(j);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

class procedure TCompilerDirectiveScopeDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i        : Integer;
  Code     : string;
  RE       : TRegEx;
  M        : TMatch;
  Name     : string;
  IsOff    : Boolean;
  // Pro Direktiv: Last-OFF-Zeile (-1 wenn nicht offen), Last-OFF-Token.
  LastOff  : TDictionary<string, Integer>;
  // {$PUSH}-Snapshots des aktuellen OFF-Zustands; {$POP} restauriert.
  PushStack: TStack<TDictionary<string, Integer>>;
  Tok      : TPair<string, Integer>;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  LastOff := TDictionary<string, Integer>.Create;
  PushStack := TStack<TDictionary<string, Integer>>.Create;
  try
    RE := TRegEx.Create(DIRECTIVE_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 1 do
    begin
      // StripNonDirectiveComments behaelt {$...} aber strippt
      // //-Kommentare + {...}-Blocks. Damit zaehlt `// {$WARNINGS OFF}`
      // NICHT mehr als echte Direktive.
      Code := StripNonDirectiveComments(Lines[i]);
      for M in RE.Matches(Code) do
      begin
        Name := LowerCase(M.Groups[1].Value);
        if Name = 'push' then
          // Aktuellen Zustand sichern - alle bis hier offenen OFFs werden
          // beim korrespondierenden {$POP} exakt so wiederhergestellt.
          PushStack.Push(CloneOffDict(LastOff))
        else if Name = 'pop' then
        begin
          if PushStack.Count > 0 then
          begin
            LastOff.Free;
            LastOff := PushStack.Pop;   // gesicherten Zustand uebernehmen
          end
          else
            // {$POP} ohne {$PUSH} - tolerant: Zustand leeren statt FP.
            LastOff.Clear;
        end
        else if IsTracked(Name) and M.Groups[2].Success then
        begin
          IsOff := SameText(M.Groups[2].Value, 'OFF');
          if IsOff then
            LastOff.AddOrSetValue(Name, i + 1)   // 1-based line
          else
            LastOff.Remove(Name);                // ON closes scope
        end;
      end;
    end;

    // Was uebrig bleibt = OFF ohne folgendes ON (PUSH/POP beruecksichtigt).
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
    // Nicht-balancierte {$PUSH} ohne {$POP}: Snapshots noch freigeben.
    while PushStack.Count > 0 do
      PushStack.Pop.Free;
    PushStack.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
