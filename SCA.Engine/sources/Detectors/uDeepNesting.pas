unit uDeepNesting;

// Detektor fuer zu tiefe Verschachtelung von Kontrollstrukturen.
//
// Gezaehlte Strukturen (kognitiver Aufwand):
//   if / else   → erhoehen die Tiefe
//   for / while / repeat → Schleifen
//   case        → Verzweigung
//
// NICHT gezaehlt (Resource-Management, kein logischer Bruch):
//   try / except / finally
//
// Beispiel der Rationalisierung: Eine korrekt geschriebene Methode mit
//   try
//     for ... do
//       if ... then ...
//   finally
//     ...
//   end;
// hat Tiefe 2 (for + if), nicht 3.
//
// Schwelle: > MAX_DEPTH (Default: 4) bedeutet >= 5 verschachtelte Ebenen.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDeepNestingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class procedure Walk(Node: TAstNode; Depth: Integer;
      var DeepestLine, DeepestDepth: Integer;
      var DeepestKind: TNodeKind); static;
    class function KindName(Kind: TNodeKind): string; static;
  end;

implementation

// Schwellwert kommt aus uSCAConsts.DetectorMaxNesting (analyser.ini ->
// DeepNestingMaxDepth). Default 4 (also wird ab 5 verschachtelten
// Ebenen gemeldet).

const
  // Nur logische Verschachtelung – keine Exception-Handler
  COUNTING_KINDS : set of TNodeKind =
    [nkIfStmt, nkForStmt, nkWhileStmt, nkRepeatStmt, nkCaseStmt];

class function TDeepNestingDetector.KindName(Kind: TNodeKind): string;
begin
  case Kind of
    nkIfStmt     : Result := 'if';
    nkForStmt    : Result := 'for';
    nkWhileStmt  : Result := 'while';
    nkRepeatStmt : Result := 'repeat';
    nkCaseStmt   : Result := 'case';
  else
    Result := '?';
  end;
end;

class procedure TDeepNestingDetector.Walk(Node: TAstNode; Depth: Integer;
  var DeepestLine, DeepestDepth: Integer;
  var DeepestKind: TNodeKind);
var
  Child    : TAstNode;
  NewDepth : Integer;
begin
  for Child in Node.Children do
  begin
    NewDepth := Depth;
    if Child.Kind in COUNTING_KINDS then
    begin
      Inc(NewDepth);
      if NewDepth > DeepestDepth then
      begin
        DeepestDepth := NewDepth;
        DeepestLine  := Child.Line;
        DeepestKind  := Child.Kind;
      end;
    end;
    Walk(Child, NewDepth, DeepestLine, DeepestDepth, DeepestKind);
  end;
end;

class procedure TDeepNestingDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods       : TList<TAstNode>;
  M             : TAstNode;
  DeepestLine   : Integer;
  DeepestDepth  : Integer;
  DeepestKind   : TNodeKind;
  F             : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      DeepestLine  := 0;
      DeepestDepth := 0;
      DeepestKind  := nkUnknown;
      Walk(M, 0, DeepestLine, DeepestDepth, DeepestKind);

      if DeepestDepth > DetectorMaxNesting then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(DeepestLine);
        F.MissingVar := Format(
          'Depth %d (%s from line %d, limit: %d)',
          [DeepestDepth, KindName(DeepestKind),
           DeepestLine, DetectorMaxNesting]);
        F.SetKind(fkDeepNesting);
        Results.Add(F);
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
