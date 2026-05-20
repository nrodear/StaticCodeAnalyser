unit uNilComparison;

// Detektor: `x = nil` oder `x <> nil` statt `Assigned(x)` / `not Assigned(x)`.
//
// Pattern (Style-/Convention-Smell):
//   if Foo = nil then ...        // BAD
//   if Foo <> nil then ...       // BAD
//
// Korrekt:
//   if not Assigned(Foo) then ...
//   if Assigned(Foo) then ...
//
// Warum: `Assigned` ist die kanonische Delphi-Form fuer nil-Checks und
// hat den Vorteil dass sie auch fuer Methoden-Pointer und Variant-Typen
// funktioniert (wo `= nil` nicht definiert ist). Konsistenz erleichtert
// das Lesen und vermeidet Spezialfaelle.
//
// Erkennung (text-basiert auf gespeicherten Expressions im AST):
//   * Walker iteriert alle Nodes
//   * Pro Node: scanne Name und TypeRef (= Condition-Text / RHS-Text)
//   * Pattern: '= nil' oder '<> nil' wobei nil als Standalone-Token
//   * Skip: ':= nil' (Zuweisung, kein Vergleich), '<= nil', '>= nil'
//     (semantisch ungewoehnlich, aber kein nil-Compare-Pattern)
//   * Skip: String-Literale ('nil' in Anfuehrungszeichen)
//
// Sonar-Pendant: NilComparisonCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   NilComparisonCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TNilComparisonDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// True wenn Text das Muster `<op>nil` enthaelt, mit op in {`=`, `<>`}
// und 'nil' als ganzes Token (kein Identifier-Suffix). ':=', '<=', '>='
// + nil werden NICHT als Compare gezaehlt.
function ContainsNilCompare(const Text: string): Boolean;
var
  Cleaned, Lower : string;
  L, P, j        : Integer;
  Aft, Prev      : Char;
begin
  Result  := False;
  Cleaned := TDetectorUtils.StripStringLiterals(Text);
  Lower   := LowerCase(Cleaned);
  L       := Length(Lower);
  if L < 4 then Exit;            // 'a=nil' Minimum

  P := 1;
  repeat
    P := Pos('nil', Lower, P);
    if P = 0 then Exit;

    // Word-boundary rechts: nach 'nil' darf kein Ident-Zeichen kommen
    // (sonst ist's 'nilable' o.ae.).
    if P + 3 <= L then
    begin
      Aft := Lower[P + 3];
      if TDetectorUtils.IsIdentChar(Aft) then
      begin
        Inc(P, 3);
        Continue;
      end;
    end;

    // Word-boundary links: muss whitespace / '=' / '>' davor stehen
    // (sonst 'foonil').
    if (P > 1) and TDetectorUtils.IsIdentChar(Lower[P - 1]) then
    begin
      Inc(P, 3);
      Continue;
    end;

    // Zurueck-walk ueber Whitespace zum eigentlichen Operator.
    j := P - 1;
    while (j >= 1) and (Lower[j] = ' ') do Dec(j);
    if j < 1 then
    begin
      Inc(P, 3);
      Continue;
    end;

    // Operator-Erkennung:
    if Lower[j] = '=' then
    begin
      // ':=' (Zuweisung), '<=', '>=' aussortieren.
      if j >= 2 then
      begin
        Prev := Lower[j - 1];
        if (Prev = ':') or (Prev = '<') or (Prev = '>') then
        begin
          Inc(P, 3);
          Continue;
        end;
      end;
      Exit(True);            // '= nil' Vergleich gefunden
    end
    else if (Lower[j] = '>') and (j >= 2) and (Lower[j - 1] = '<') then
      Exit(True);            // '<> nil' Vergleich gefunden;

    Inc(P, 3);
  until P > L;
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  i         : Integer;
  F         : TLeakFinding;
  MethName  : string;
  NextMeth  : TAstNode;
begin
  if Node = nil then Exit;
  if ContainsNilCompare(Node.Name) or ContainsNilCompare(Node.TypeRef) then
  begin
    if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
    else MethName := '';
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethName;
    F.LineNumber := IntToStr(Node.Line);
    F.MissingVar :=
      'Use Assigned() instead of "= nil" / "<> nil" for nil checks';
    F.SetKind(fkNilComparison);
    Results.Add(F);
  end;
  // Wenn der aktuelle Node eine Methode ist: ab hier als CurrentMethod
  // weitergeben, damit verschachtelte Nodes den Method-Kontext kennen.
  if Node.Kind = nkMethod then NextMeth := Node else NextMeth := CurrentMethod;
  for i := 0 to Node.Children.Count - 1 do
    WalkAndCheck(Node.Children[i], NextMeth, FileName, Results);
end;

class procedure TNilComparisonDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
