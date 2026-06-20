unit uAttributeDuplicate;

// Detektor: zweimal das gleiche Attribute vor demselben Member.
//
// Pattern (Code-Smell, Copy-Paste-Rest):
//   [Test]
//   [Test]                  // <-- Duplikat
//   procedure Foo;
//
//   [Inject][Inject]        // <-- gleiche Zeile
//   FFoo: IFoo;
//
// Erkennung: pro File alle Attribute-Lines sammeln (Pattern
// `\[\s*([A-Za-z_]\w*)`), gruppieren nach (nextNonBlankLine, AttrName).
// Wenn pro Member dieselbe Attr-Klasse > 1 mal -> Finding (auf der
// 2./n. Stelle).
//
// FP-Reduktion: Attribute mit unterschiedlichen Args (z.B.
// `[TestCase('A','1')][TestCase('B','2')]`) sind LEGITIM mehrfach.
// Dieser Detektor MELDET nur wenn die Args identisch sind ODER beide
// keine Args haben.
//
// Severity: lsWarning, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAttributeDuplicateDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  // Match attribute. Optional group fuer Args -> defensiv check auf
  // Groups.Count + Success damit Delphi-RegEx kein "Index exceeds maximum"
  // wirft.
  ATTR_RE = '\[\s*([A-Za-z_]\w*)([^\]]*)\]';

type
  TAttrHit = record
    Line   : Integer;
    Name   : string;     // canonical lowercase
    Args   : string;     // raw text incl parens, '' if no args
  end;

class procedure TAttributeDuplicateDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  Cached : Boolean;
  i, j   : Integer;
  RE     : TRegEx;
  M      : TMatch;
  Hits   : TList<TAttrHit>;
  Hit    : TAttrHit;
  Seen   : TDictionary<string, Integer>;  // 'name|args' -> firstLine
  Key    : string;
  FirstLine : Integer;
  F      : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  Hits := TList<TAttrHit>.Create;
  try
    RE := TRegEx.Create(ATTR_RE);
    // Pass 1: alle Attribute-Hits sammeln. WICHTIG: RAW-Line nutzen
    // (NICHT ScanCodeLine), weil ScanCodeLine String-Inhalte mit FillCh
    // ersetzt - aus '[TestCase(''A'')]' und '[TestCase(''B'')]' wuerde
    // beide Mal '[TestCase(   )]', und der Args-Vergleich liefert
    // false-positive Duplikat.
    // Comment-Protection: simpler `//`-Position-Check (Block-Kommentare
    // sind in Attribute-Naehe extrem selten, FP-Risk akzeptiert).
    for i := 0 to Lines.Count - 1 do
    begin
      var Raw := Lines[i];
      var CommentPos := Pos('//', Raw);
      try
        for M in RE.Matches(Raw) do
        begin
          // Match innerhalb Zeilen-Kommentar? -> skippen.
          if (CommentPos > 0) and (M.Index > CommentPos) then Continue;
          if M.Groups.Count < 2 then Continue;
          Hit.Line := i + 1;
          Hit.Name := LowerCase(M.Groups[1].Value);
          if M.Groups.Count >= 3 then
            Hit.Args := Trim(M.Groups[2].Value)
          else
            Hit.Args := '';
          Hits.Add(Hit);
        end;
      except
        // Defekte Zeile -> skip; Detector bleibt funktional fuer Rest.
      end;
    end;

    // Pass 2: konsekutive Sequenzen (Lines duerfen max. 1 Line auseinander
    // sein - Attribute vor demselben Member; '<= 1' damit `[A][B]` plus
    // `[C]` auf naechster Zeile noch als Gruppe zaehlt).
    Seen := TDictionary<string, Integer>.Create;
    try
      for i := 0 to Hits.Count - 1 do
      begin
        Hit := Hits[i];
        Key := Hit.Name + '|' + Hit.Args;
        // Schau in Hits[0..i-1] - gleiche Gruppe (Line-Diff <= 2)?
        FirstLine := -1;
        for j := i - 1 downto 0 do
        begin
          if Hits[j].Line < Hit.Line - 2 then Break;
          if (LowerCase(Hits[j].Name) = Hit.Name) and
             (Hits[j].Args = Hit.Args) then
          begin
            FirstLine := Hits[j].Line;
            Break;
          end;
        end;
        if FirstLine < 0 then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(Hit.Line);
        F.MissingVar := 'Duplicate attribute [' + Hit.Name + Hit.Args +
                        '] (first seen at line ' + IntToStr(FirstLine) +
                        '). Identical attribute applied twice has no effect ' +
                        'and is usually a copy-paste artefact.';
        F.SetKind(fkAttributeDuplicate);
        Results.Add(F);
      end;
    finally
      Seen.Free;
    end;
  finally
    Hits.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
