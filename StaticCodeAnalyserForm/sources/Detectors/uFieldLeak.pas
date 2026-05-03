unit uFieldLeak;

// Detektor fuer Klassen-Feld-Leaks im Create/Destroy-Pattern.
//
// Erkennt:
//   FField := TLeakyClass.Create im Konstruktor + KEIN Free im Destruktor
//   -> Feld lebt so lange wie das Objekt der Klasse, wird aber nicht aufgeraeumt
//      = Speicherleck pro Instanz der Klasse
//
// Beispiel:
//   TFoo = class
//   private FList: TStringList;
//   public  constructor Create; destructor Destroy; override;
//   end;
//
//   constructor TFoo.Create;       // <-- FList wird hier erzeugt
//   begin
//     FList := TStringList.Create;
//   end;
//
//   destructor TFoo.Destroy;       // <-- FList.Free FEHLT
//   begin
//     inherited;
//   end;
//
// Begrenzungen:
//   - Nur direkt im Konstruktor erzeugte Felder werden geprueft
//   - "Freigeben" akzeptiert: FField.Free, FField.Destroy, FreeAndNil(FField)
//   - Wird das Feld an einen ObjectList-Owner uebergeben, koennen wir das
//     nicht erkennen (-> potenziell False-Positive). Per // noinspection
//     unterdrueckbar.

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uLeakDetector2;

type
  TFieldLeakDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function FindMethod(UnitNode: TAstNode; const Kind: string;
      const ClassName: string): TAstNode; static;
    class function HasFieldCreate(MethodNode: TAstNode;
      const FieldNameLow: string): Boolean; static;
  end;

implementation

class function TFieldLeakDetector.FindMethod(UnitNode: TAstNode;
  const Kind, ClassName: string): TAstNode;
// Sucht eine Implementations-Methode mit gegebenem TypeRef ('constructor' bzw.
// 'destructor') und Name 'ClassName.<Methodenname>'. nil wenn nicht da.
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  ClsLow  : string;
begin
  Result := nil;
  ClsLow := ClassName.ToLower + '.';
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      if SameText(M.TypeRef, Kind) and
         M.Name.ToLower.StartsWith(ClsLow) then
        Exit(M);
  finally
    Methods.Free;
  end;
end;

class function TFieldLeakDetector.HasFieldCreate(MethodNode: TAstNode;
  const FieldNameLow: string): Boolean;
// Sucht im Konstruktor eine Zuweisung der Form 'FField := <Typ>.Create(...)'.
// Akzeptiert sowohl 'FField' als auch 'Self.FField' als LHS.
var
  Assigns : TList<TAstNode>;
  A       : TAstNode;
  LHSLow  : string;
  TypeLow : string;
  p       : Integer;
begin
  Result := False;
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      LHSLow := A.Name.ToLower;
      // Match auf 'fname' oder 'self.fname'
      if (LHSLow <> FieldNameLow) and
         (LHSLow <> 'self.' + FieldNameLow) then Continue;

      TypeLow := A.TypeRef.ToLower;
      p := Pos('.create', TypeLow);
      if p > 0 then
      begin
        var pRight := p + 7;
        if (pRight > Length(TypeLow)) or
           not TLeakDetector2.IsIdentChar(TypeLow[pRight]) then
          Exit(True);
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

class procedure TFieldLeakDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes      : TList<TAstNode>;
  ClassNode    : TAstNode;
  Fields       : TList<TAstNode>;
  Field        : TAstNode;
  Ctor, Dtor   : TAstNode;
  FieldNameLow : string;
  FreeFound    : Boolean;
  FreeInFin    : Boolean;
  F            : TLeakFinding;
begin
  Classes := UnitNode.FindAll(nkClass);
  try
    for ClassNode in Classes do
    begin
      if ClassNode.Name = '' then Continue;

      // Konstruktor + Destruktor der Klasse suchen.
      Ctor := FindMethod(UnitNode, 'constructor', ClassNode.Name);
      if Ctor = nil then Continue; // ohne Konstruktor nichts zu pruefen

      Dtor := FindMethod(UnitNode, 'destructor', ClassNode.Name);

      Fields := ClassNode.FindAll(nkField);
      try
        for Field in Fields do
        begin
          if not TLeakDetector2.IsLeakyType(Field.TypeRef) then Continue;
          FieldNameLow := Field.Name.ToLower;

          // Feld muss im Konstruktor per .Create zugewiesen werden,
          // sonst ist es kein Konstruktor-erzeugtes Feld.
          if not HasFieldCreate(Ctor, FieldNameLow) then Continue;

          // Pruefen ob im Destruktor ein .Free / .Destroy / FreeAndNil
          // fuer das Feld vorkommt. Reuse von SearchFree aus uLeakDetector2.
          FreeFound := False;
          if Dtor <> nil then
            FreeFound := TLeakDetector2.SearchFree(Dtor, FieldNameLow,
                                                   False, FreeInFin);

          if not FreeFound then
          begin
            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := ClassNode.Name + '.Destroy';
            F.LineNumber := IntToStr(Field.Line);
            if Dtor = nil then
              F.MissingVar := Format(
                '%s: created in constructor but no destructor exists',
                [Field.Name])
            else
              F.MissingVar := Format(
                '%s: created in %s.Create but not freed in Destroy',
                [Field.Name, ClassNode.Name]);
            F.Severity   := lsError;
            F.Kind       := fkMemoryLeak;
            Results.Add(F);
          end;
        end;
      finally
        Fields.Free;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

end.
