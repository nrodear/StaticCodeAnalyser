unit uAttributeMisalignment;

// Detektor: Attribute-Zeile mit Leerzeile zwischen Attribute und Member.
//
// Pattern (visual maintainability):
//   [Test]
//                         // <-- Leerzeile dazwischen
//   procedure Foo;
//
// Compiler-Verhalten: Attribute haengt am NACHFOLGENDEN Member - eine
// Leerzeile gilt nicht als Trennung. Trotzdem visuell verlierbar, oft
// Indikator dass der Attribute beim Refactoring vergessen wurde umzu-
// haengen.
//
// Erkennung: pro Attribute-Zeile pruefen ob Line+1 leer ist UND Line+2
// nichtleer + Member-Decl-Pattern. Bei Mehrfach-Leerzeilen
// (Line+1 leer + Line+2 leer) noch deutlicher Verdacht.
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TAttributeMisalignmentDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.RegularExpressions,
  uFileTextCache, uDetectorUtils;

const
  ATTR_LINE_RE = '^\s*\[\s*[A-Za-z_]\w*';

class procedure TAttributeMisalignmentDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  i      : Integer;
  Code, Next : string;
  State  : TCommentScanState;
  Dummy  : Integer;
  RE     : TRegEx;
  F      : TLeakFinding;
  AttrName : string;
  M      : TMatch;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    State := Default(TCommentScanState);
    RE := TRegEx.Create(ATTR_LINE_RE, [roIgnoreCase]);
    for i := 0 to Lines.Count - 2 do
    begin
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);
      try
        M := RE.Match(Code);
        if not M.Success then Continue;
      except
        Continue;
      end;
      // FP-Fix 2026-06-21: Set-Literale in const-Decls
      // (`ECC_VALIDSIGN = [ecvValidSigned, ecvValidSelfSigned];`) wurden
      // als misalignierte Attribute fehl-erkannt - IsLikelyAttributePosition
      // schaut auf vorherige Zeile (`=` -> Expression-Continuation).
      if not TDetectorUtils.IsLikelyAttributePosition(Lines, i) then Continue;
      // FP-Fix 2026-06-21: `[Test]     procedure Foo;` (Attribute + Member
      // auf GLEICHER Zeile) ist bereits korrekt attached - die Blank-Line
      // danach ist nur Code-Block-Trenner, keine Misalignment.
      var TailRaw : string := Trim(Lines[i]);
      var ClosePos : Integer := 0;
      for var k := Length(TailRaw) downto 1 do
        if TailRaw[k] = ']' then begin ClosePos := k; Break; end;
      if ClosePos > 0 then
      begin
        var Tail : string := Trim(Copy(TailRaw, ClosePos + 1, MaxInt));
        if Tail <> '' then Continue; // Member auf gleicher Zeile -> OK
      end;
      // Naechste Zeile leer?
      if i + 1 >= Lines.Count then Continue;
      Next := Trim(Lines[i + 1]);
      if Next <> '' then Continue;
      // Pruefen ob NACH der Leerzeile noch ein Member kommt (eine
      // freistehende Attribute-Zeile am File-Ende ist ein anderes
      // Problem - hier nicht relevant).
      var HasFollowing := False;
      var j : Integer;
      for j := i + 2 to Lines.Count - 1 do
        if Trim(Lines[j]) <> '' then begin HasFollowing := True; Break; end;
      if not HasFollowing then Continue;
      // Attribute-Name extrahieren fuer aussagekraeftige Message.
      AttrName := '';
      try
        var Mn := TRegEx.Match(Code, '\[\s*([A-Za-z_]\w*)');
        if Mn.Success and (Mn.Groups.Count >= 2) then
          AttrName := Mn.Groups[1].Value;
      except
        AttrName := '?';
      end;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := 'Attribute [' + AttrName + '] with blank line ' +
                      'before target member - visually loose, often a sign ' +
                      'the attribute should have been removed or attached ' +
                      'to a different member.';
      F.SetKind(fkAttributeMisalignment);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
