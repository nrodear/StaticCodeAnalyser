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

uses
  System.Classes, uFileTextCache;

// noinspection-file CanBeClassMethod, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  MAX_METHODS = 20;
  MAX_FIELDS  = 15;

// Real-World-FP-Audit 2026-07-10: Erkennt die leere Einzeiler-Klassen-
// deklaration `EFoo = class(EBar);` (typische Exception-/Forward-Klasse
// ohne Body). Der Parser kennt fuer `class(...)` KEINEN Semikolon-Abbruch
// (nur `class;` / `class of` sind als Forward gefuehrt), schluckt daher
// mangels `end` die nachfolgenden Unit-Level-Routinen und Typ-/Enum-
// Deklarationen faelschlich als Member -> absurde God-Class-Counts
// (EALOpenOfficeException 22m/23f, EALExprEvalError 17m/42f usw.).
// Kennzeichen: die Quellzeile der Klasse endet - nach Strippen eines
// Zeilenkommentars - auf `);`. Echte God-Klassen haben immer einen
// mehrzeiligen Body (private/protected/public) vor `end;`, ihre
// Header-Zeile endet auf `)` bzw. dem Klassennamen, nie auf `);`.
function IsEmptyClassDeclLine(const AFileName: string; ALine: Integer): Boolean;
var
  Lines  : TStringList;
  Cached : Boolean;
  S      : string;
  P      : Integer;
begin
  Result := False;
  if ALine <= 0 then Exit;
  Lines := AcquireLines(AFileName, Cached);
  if Lines = nil then Exit;
  try
    if ALine > Lines.Count then Exit;
    S := Lines[ALine - 1];
    P := Pos('//', S);
    if P > 0 then S := Copy(S, 1, P - 1);
    S := TrimRight(S);
    Result := (Length(S) >= 2) and (Copy(S, Length(S) - 1, 2) = ');');
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

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

      // Real-World-FP-Audit 2026-07-10: leere `class(...);`-Einzeiler
      // ueberspringen - deren Counts sind reine Parser-Slurp-Artefakte
      // (siehe IsEmptyClassDeclLine). Erst nach dem Schwellwert-Check, damit
      // der Source-Lookup nur fuer die wenigen Schwellwert-Ueberschreiter laeuft.
      if IsEmptyClassDeclLine(FileName, C.Line) then Continue;

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
