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
    Line       : Integer;
    Name       : string;     // canonical lowercase
    Args       : string;     // raw text incl parens, '' if no args
    TargetLine : Integer;    // resolved member-decl line that this
                             // attribute attaches to (1-based). Zwei Hits
                             // mit gleicher TargetLine attachen am SELBEN
                             // Member -> Duplikat-Kandidat. Verschiedene
                             // TargetLine = verschiedene Member -> OK.
  end;

function LineLooksLikeMemberDecl(const S: string): Boolean;
var
  Tr, Lo: string;
begin
  Tr := Trim(S);
  if Tr = '' then Exit(False);
  Lo := LowerCase(Tr);
  if (Pos('procedure ', Lo) = 1) or (Lo = 'procedure') then Exit(True);
  if (Pos('function ', Lo) = 1) or (Lo = 'function') then Exit(True);
  if (Pos('constructor ', Lo) = 1) or (Lo = 'constructor') then Exit(True);
  if (Pos('destructor ', Lo) = 1) or (Lo = 'destructor') then Exit(True);
  if (Pos('operator ', Lo) = 1) then Exit(True);
  if (Pos('property ', Lo) = 1) then Exit(True);
  if (Pos('class procedure', Lo) = 1) or (Pos('class function', Lo) = 1) or
     (Pos('class constructor', Lo) = 1) or (Pos('class destructor', Lo) = 1) or
     (Pos('class property', Lo) = 1) or (Pos('class var', Lo) = 1) or
     (Pos('class operator', Lo) = 1) then Exit(True);
  if TRegEx.IsMatch(Tr,
       '^[A-Za-z_]\w*\s*=\s*(class|interface|record|object)\b',
       [roIgnoreCase]) then Exit(True);
  if TRegEx.IsMatch(Tr,
       '^[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*:\s*[A-Za-z_<]',
       [roIgnoreCase]) then Exit(True);
  Result := False;
end;

function ResolveTargetLine(Lines: TStringList; AttrLineIdx: Integer): Integer;
// Liefert die 1-basierte Zeile des Member-Decls dass die Attribute-Linie
// AttrLineIdx attached. Wenn Attribute und Member auf der GLEICHEN Zeile
// stehen -> selbe Zeile zurueck. Wenn nichts gefunden -> -1.
var
  i, ClosePos : Integer;
  Tail : string;
begin
  Result := -1;
  if (Lines = nil) or (AttrLineIdx < 0) or (AttrLineIdx >= Lines.Count) then Exit;
  // Same-line tail nach letztem `]` ?
  var ThisLine := Lines[AttrLineIdx];
  ClosePos := 0;
  for i := Length(ThisLine) downto 1 do
    if ThisLine[i] = ']' then begin ClosePos := i; Break; end;
  if ClosePos > 0 then
  begin
    Tail := Trim(Copy(ThisLine, ClosePos + 1, MaxInt));
    if (Tail <> '') and (Tail[1] <> '[') and LineLooksLikeMemberDecl(Tail) then
      Exit(AttrLineIdx + 1);
  end;
  // Sonst: erstes nicht-Attribute / nicht-leeres Line das Member-Decl ist.
  i := AttrLineIdx + 1;
  while i < Lines.Count do
  begin
    var NL := Trim(Lines[i]);
    if NL <> '' then
    begin
      if (NL[1] = '[') then begin Inc(i); Continue; end;  // chain of attributes
      if LineLooksLikeMemberDecl(NL) then Exit(i + 1);
      Exit; // andere Zeile (visibility, type-Section, garbage) -> abbruch
    end;
    Inc(i);
  end;
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
    // FP-Fix 2026-06-21: Vor jedem Regex-Scan IsLikelyAttributePosition
    // pruefen - sonst werden Array-Indices (`pd[x*3]`), Set-Literale
    // (`[ecvValidSigned]`) und Type-Param-Listen als Attribute fehl-
    // erkannt (Real-World-Scan: 53779 Findings, ~99% FP).
    for i := 0 to Lines.Count - 1 do
    begin
      if not TDetectorUtils.IsLikelyAttributePosition(Lines, i) then Continue;
      var Raw := Lines[i];
      var CommentPos := Pos('//', Raw);
      var Target := ResolveTargetLine(Lines, i);
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
          Hit.TargetLine := Target;
          Hits.Add(Hit);
        end;
      except
        // Defekte Zeile -> skip; Detector bleibt funktional fuer Rest.
      end;
    end;

    // Pass 2: Duplikat = zwei Hits mit gleichem Name+Args und gleichem
    // TargetLine (= attachen am selben Member).
    // FP-Fix 2026-06-21: `[MVCInheritable] function A; [MVCInheritable]
    // function B;` ist KEIN Duplikat (verschiedene TargetLine). Vorher
    // wurde es per 2-Zeilen-Fenster falsch geflagged.
    Seen := TDictionary<string, Integer>.Create;
    try
      for i := 0 to Hits.Count - 1 do
      begin
        Hit := Hits[i];
        if Hit.TargetLine <= 0 then Continue; // kein Target -> kein Dup
        Key := Hit.Name + '|' + Hit.Args;
        FirstLine := -1;
        for j := i - 1 downto 0 do
        begin
          if Hits[j].TargetLine <> Hit.TargetLine then Continue;
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
