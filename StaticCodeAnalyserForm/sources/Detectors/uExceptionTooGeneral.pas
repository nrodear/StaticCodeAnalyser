unit uExceptionTooGeneral;

// Detektor: `except on E: Exception do ...` mit Basisklasse Exception.
//
// Pattern (Code Smell, Sonar-50 #11):
//   try
//     DoStuff;
//   except
//     on E: Exception do           // <-- faengt ALLES, inklusive
//       Log(E.Message);             //     EOutOfMemory, EAbort, ...
//   end;
//
// Korrekt:
//   try
//     DoStuff;
//   except
//     on E: EDatabaseError do      // spezifische Subklasse
//       Log(E.Message);
//     on E: EArgumentException do
//       Log(E.Message);
//   end;
//
// Warum schaedlich: das Basis-Exception faengt jeden Fehler, auch solche
// die normalerweise NICHT vom User-Code behandelt werden sollten (z.B.
// EOutOfMemory, EAccessViolation, EAbort als Steuerflusssignal). Der
// Aufrufer denkt, er habe alles im Griff - in Wirklichkeit verschluckt
// er System-Fehler die abgebrochen werden sollten.
//
// Erkennung (AST):
//   Parser legt 'on E: T do ...' als nkOnHandler ab. Dabei:
//     OnNode.Name    = Exception-Variablen-Name (z.B. 'E') oder leer
//     OnNode.TypeRef = Typ-Identifier (z.B. 'Exception', 'EFoo')
//   Befund wenn SameText(TypeRef, 'Exception').
//
// Bewusst NICHT als Finding:
//   * `except ... end;` ohne `on`-Klausel - faengt zwar auch alles, das
//     ist aber Pattern fuer Top-Level-Crash-Handler. Eigener Detector
//     (fkEmptyExcept fuer leere Variante) deckt das ab.
//   * `on E: EAbort do ... raise;` mit re-raise - dort wuerde Filter
//     greifen, aber TypeRef='EAbort' nicht 'Exception'.
//
// Sonar-Pendant: ExceptionTooGeneral / "java:S2221" (Java)
//                S110 Pattern bezogen auf Delphi-Hierarchie.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TExceptionTooGeneralDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TExceptionTooGeneralDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Handlers : TList<TAstNode>;
  N        : TAstNode;
  F        : TLeakFinding;
begin
  Handlers := MethodNode.FindAll(nkOnHandler);
  try
    for N in Handlers do
    begin
      if not SameText(N.TypeRef, 'Exception') then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar :=
        'except on E: Exception catches every error - prefer a specific subclass';
      F.SetKind(fkExceptionTooGeneral);
      Results.Add(F);
    end;
  finally
    Handlers.Free;
  end;
end;

class procedure TExceptionTooGeneralDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
