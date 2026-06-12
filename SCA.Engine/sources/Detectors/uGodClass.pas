unit uGodClass;

// Detektor: God-Klasse - Klasse mit zu vielen Methoden oder Feldern.
//
// Pattern (Code Smell, Sonar-50 #31):
//   type
//     TFoo = class
//       FA, FB, FC, FD, ..., FZ: Integer;     // viele Felder
//       procedure One;
//       procedure Two;
//       ...
//       procedure Twenty;
//       procedure TwentyOne;                   // > Schwellwert
//     end;
//
// Folge: Klasse haelt zu viel Verantwortung, ist schwer testbar / unter
// Versionskontrolle, zieht Refactoring-Aufwand. Klassiker:
// Composite-Roots in UI-Frames, "AllInOne"-Manager-Klassen.
//
// Erkennung (AST):
//   * Walk nkClass-Knoten.
//   * Zaehle direkte Children:
//       - nkMethod  -> MethodCount
//       - nkField   -> FieldCount
//     (Properties zaehlen nicht - sie sind syntactic sugar.)
//   * Schwelle: MethodCount > MAX_METHODS  OR FieldCount > MAX_FIELDS.
//
// Schwellwerte default 20 / 15 (Sonar-Konvention). Falls projektweit
// strenger / lockerer noetig, koennen die Konstanten ueber das uSCAConsts-
// Globals-Pattern konfigurierbar gemacht werden (analog LongMethod).
// Aktuell fest verdrahtet - die meisten realen God-Klassen ueberschreiten
// die Schwelle eh deutlich (3-5x), so dass die Schwelle nicht hyper-
// sensitiv sein muss.
//
// Bewusst NICHT geflaggt:
//   * Records, Interfaces, Class-Helpers - sind keine Klassen mit Daten +
//     Verhalten (Record hat nur Daten, Interface nur Verhalten, Class-
//     Helper extends ohne State).
//   * Forward-Deklarationen (kein Body) - keine Children, kein Count.
//   * Klassen mit `class abstract` - sind Designintent, kein Refactoring-
//     Bedarf. (Heuristik: TypeRef enthaelt ';abstract'.)
//
// Sonar-Pendant: Sonar-50 #31 / Java "S2972".

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TGodClassDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeClassMethod, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  MAX_METHODS = 20;
  MAX_FIELDS  = 15;

class procedure TGodClassDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes : TList<TAstNode>;
  C, Child : TAstNode;
  MethodCount, FieldCount : Integer;
  F : TLeakFinding;
  Detail : string;
  TR : string;
begin
  Classes := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
    begin
      // Forward-Decls / Interfaces / abstract-Klassen skippen.
      if C.Children.Count = 0 then Continue;
      TR := LowerCase(C.TypeRef);
      // Parser legt `class abstract` aktuell nicht in nkClass.TypeRef ab -
      // ;abstract-Check bleibt aber defensiv, falls die TypeRef-Befuellung
      // in Zukunft erweitert wird.
      if Pos(';abstract', TR) > 0 then Continue;

      MethodCount := 0;
      FieldCount  := 0;
      var AbstractMethCount := 0;
      // FindAll nkMethod/nkField waere bequemer, aber wir wollen NUR
      // direkte Children der Klasse zaehlen - keine Methoden in nested
      // Records oder verschachtelten Klassen.
      // VisibilitySection ist Direct-Child von nkClass, ihre Methoden/
      // Felder zaehlen als Klassen-Mitglieder.
      for Child in C.Children do
      begin
        case Child.Kind of
          nkMethod :
            begin
              Inc(MethodCount);
              if Pos(';abstract', LowerCase(Child.TypeRef)) > 0 then
                Inc(AbstractMethCount);
            end;
          nkField  : Inc(FieldCount);
          nkVisibilitySection:
            for var Inner in Child.Children do
              case Inner.Kind of
                nkMethod :
                  begin
                    Inc(MethodCount);
                    if Pos(';abstract', LowerCase(Inner.TypeRef)) > 0 then
                      Inc(AbstractMethCount);
                  end;
                nkField  : Inc(FieldCount);
              end;
        end;
      end;

      // All-abstract-Klasse (Framework-Pattern): kein Refactoring noetig,
      // die Klasse IST die abstrakte API. Skip.
      if (MethodCount > 0) and (AbstractMethCount = MethodCount) then
        Continue;

      if (MethodCount <= MAX_METHODS) and (FieldCount <= MAX_FIELDS) then
        Continue;

      Detail := Format('Class %s is a god class (%d methods, %d fields; ' +
                       'thresholds %d / %d) - split into focused units',
                       [C.Name, MethodCount, FieldCount,
                        MAX_METHODS, MAX_FIELDS]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := C.Name;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar := Detail;
      F.SetKind(fkGodClass);
      Results.Add(F);
    end;
  finally
    Classes.Free;
  end;
end;

end.
