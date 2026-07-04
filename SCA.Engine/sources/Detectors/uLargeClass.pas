unit uLargeClass;

// Detektor: Klasse mit > 500 Zeilen Implementierung.
//
// Pattern (Code Smell, Sonar-50 #35):
//   Eine Klasse, deren gesamte Implementierung (Class-Body in der
//   interface-Section UND alle implementation-Methoden zusammen) ueber
//   500 Zeilen lang ist. Indikator fuer zu viele Verantwortungen,
//   schwer testbar / lesbar.
//
// Erkennung (AST + Line-Span):
//   * Walk nkClass.
//   * Sammle alle nkMethod-Descendants der Klasse (inkl. solche in
//     anderen Bereichen der Datei, die TClassName.Method als Owner
//     deklarieren - die Method-Knoten leben dann unter nkImplementation,
//     ihre Name beginnt mit `TClassName.`).
//   * Schaetze Implementation-Span: max(Method.Line) - min(Method.Line)
//     der Methoden mit ClassName-Prefix; plus die Class-Deklarations-
//     Span im interface-Block.
//
// Vereinfachung: Wir messen pro Klasse die SUMME der Methoden-Body-
// Linien (anhand Min/Max-Line jedes Method-Nodes); plus die Spanne der
// Class-Deklaration. Schwellwert konstant 500. Komplettes LOC-Counting
// waere genauer, aber unnoetig fuer einen Smell-Detektor.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLargeClassDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  MAX_LINES = 500;

function ClassPrefix(const MethodName: string): string;
// 'TFoo.Bar' -> 'TFoo';  'Bar' -> ''
var
  Dot : Integer;
begin
  Dot := Pos('.', MethodName);
  if Dot > 0 then
    Result := Copy(MethodName, 1, Dot - 1)
  else
    Result := '';
end;

function DeepMaxLine(N: TAstNode): Integer;
// Recursive max Line ueber ALLE Descendants. TAstNode hat nur Start-Line,
// kein EndLine - der Method-Body ist als Children-Tree gespeichert, die
// letzte Statement-Line approximiert das Method-End. Notwendig damit
// 600-Zeilen-Methoden auch wirklich als 600 Zeilen erkannt werden.
var
  Child : TAstNode;
  Sub   : Integer;
begin
  Result := N.Line;
  for Child in N.Children do
  begin
    Sub := DeepMaxLine(Child);
    if Sub > Result then Result := Sub;
  end;
end;

class procedure TLargeClassDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes  : TList<TAstNode>;
  AllMeths : TList<TAstNode>;
  C, M     : TAstNode;
  MinLine, MaxLine, Span : Integer;
  ClassName : string;
  F        : TLeakFinding;
begin
  Classes := UnitNode.FindAll(nkClass);
  AllMeths := UnitNode.FindAll(nkMethod);
  try
    for C in Classes do
    begin
      if C.Children.Count = 0 then Continue;
      ClassName := C.Name;
      if ClassName = '' then Continue;

      MinLine := C.Line;
      MaxLine := DeepMaxLine(C);  // Class-Body voll abdecken

      // Implementation-Methoden mit `TClassName.`-Prefix mitzaehlen -
      // jeweils inkl. Method-Body via DeepMaxLine.
      for M in AllMeths do
        if SameText(ClassPrefix(M.Name), ClassName) then
        begin
          if M.Line < MinLine then MinLine := M.Line;
          var MethEnd := DeepMaxLine(M);
          if MethEnd > MaxLine then MaxLine := MethEnd;
        end;

      Span := MaxLine - MinLine + 1;
      if Span <= MAX_LINES then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := ClassName;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar := Format(
        'Class %s spans %d lines (threshold %d) - split responsibilities',
        [ClassName, Span, MAX_LINES]);
      F.SetKind(fkLargeClass);
      Results.Add(F);
    end;
  finally
    AllMeths.Free;
    Classes.Free;
  end;
end;

end.
