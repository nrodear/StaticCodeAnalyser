unit uDfmRepoIndex;

// Repo-weiter Index fuer Cross-Unit-Auflosung. Notwendig fuer Detektoren,
// die auf Form-Variablen aus einer fremden Unit verweisen
// (z.B. fkDfmCrossFormCoupling: 'Form1.Edit1.Text' in Form2-Code).
//
// Aufbau-Modell:
//   * Aufrufer (typisch TStaticAnalyzer2.ParseLeaks) ruft Build(FileList)
//     einmal pro Scan.
//   * Build geht ueber alle .pas-Dateien, parst sie mit TParser2 und
//     sammelt aus den interface-/unit-level Var-Sections globale Variablen
//     mit T-Praefix-Typ. Das deckt das Delphi-Standard-Pattern
//       var Form2: TForm2;
//     ab, in dem die IDE Auto-Created-Form-Variablen anlegt.
//   * Pro Form-Klasse wird zusaetzlich die zugehoerige Unit gemerkt -
//     damit Detektoren bei Bedarf den FormBinder fuer fremde Forms
//     aufbauen koennen (lazy via Bind-Methode).
//
// Single-File-Pfad: wenn Build nie aufgerufen wird, sind die Lookups
// leer und der Cross-Form-Detektor schweigt. Das ist absichtlich -
// Single-File-Analyse hat keinen Repo-Kontext.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode;

type
  TFormVarInfo = record
    VarName   : string;     // Original-Schreibweise: 'Form2'
    ClassRef  : string;     // 'TForm2'
    Unitname  : string;     // Pfad zur .pas, in der die Var deklariert ist
    Line      : Integer;
  end;

  TDfmRepoIndex = class
  private
    // Lookup case-insensitive ueber den Var-Namen.
    FVars   : TDictionary<string, TFormVarInfo>;
    // Klassen-Name (case-insensitive) -> Pfad zur .pas, die diese Klasse
    // deklariert. Nicht jede Klasse hat einen Var-Eintrag (z.B. selten
    // gebrauchte Frame-Klassen ohne globalen Singleton).
    FClassUnit : TDictionary<string, string>;
    procedure ScanUnit(const PasFileName: string);
    procedure CollectVarsAt(Section: TAstNode; const Unitname: string);
    procedure CollectClassesAt(Section: TAstNode; const Unitname: string);
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Build(FileList: TStringList);

    // Lookup: liefert ClassRef und Unitname zur gegebenen Var (z.B. 'Form2'
    // -> 'TForm2' / 'C:\repo\uForm2.pas'). False wenn unbekannt.
    function TryGetVarType(const VarName: string;
      out Info: TFormVarInfo): Boolean;

    // Lookup: Klasse -> Unit-Datei (oder '', wenn nicht gefunden).
    function GetUnitForClass(const ClassRef: string): string;

    // Anzahl der erfassten Form-Variablen - praktisch fuer "Pipeline ready?"
    // Checks im Detektor.
    function VarCount: Integer;
  end;

implementation

uses
  uParser2, uAstFileCache;

constructor TDfmRepoIndex.Create;
begin
  inherited;
  FVars      := TDictionary<string, TFormVarInfo>.Create;
  FClassUnit := TDictionary<string, string>.Create;
end;

destructor TDfmRepoIndex.Destroy;
begin
  FClassUnit.Free;
  FVars.Free;
  inherited;
end;

procedure TDfmRepoIndex.Build(FileList: TStringList);
var
  I: Integer;
  FN: string;
begin
  FVars.Clear;
  FClassUnit.Clear;
  if FileList = nil then Exit;

  for I := 0 to FileList.Count - 1 do
  begin
    FN := FileList[I];
    if FN = '' then Continue;
    if not SameText(ExtractFileExt(FN), '.pas') then Continue;
    ScanUnit(FN);
  end;
end;

procedure TDfmRepoIndex.ScanUnit(const PasFileName: string);
// Parst eine einzelne .pas und sammelt globale Variablen + Klassen-
// Deklarationen. Parse-Fehler werden geschluckt - eine kaputte .pas
// darf den Repo-Index-Lauf nicht stoppen.
//
// Cache-Pfad: wenn gAstFileCache assigned ist, wird die .pas dort
// einmal geparst und das Root spaeter im Main-Loop wiederverwendet
// (perf_analyse.md Hot-Spot 🅐). Cache besitzt das Root - NICHT free.
var
  Parser  : TParser2;
  Root    : TAstNode;
  IFace   : TAstNode;
  OwnsRoot: Boolean;
begin
  Root := nil;
  OwnsRoot := False;

  if Assigned(gAstFileCache) then
    Root := gAstFileCache.Acquire(PasFileName)
  else
  begin
    try
      Parser := TParser2.Create;
      try
        Root := Parser.ParseFile(PasFileName);
        OwnsRoot := True;
      finally
        Parser.Free;
      end;
    except
      Exit;
    end;
  end;

  try
    if Root = nil then Exit;
    IFace := Root.FindFirst(nkInterface);
    // Wenn die Unit keine getrennte Interface-Section hat (eigentlich
    // ungewoehnlich, aber zur Sicherheit), nutzen wir den Root direkt.
    if IFace = nil then IFace := Root;

    CollectVarsAt(IFace, PasFileName);
    CollectClassesAt(IFace, PasFileName);
  finally
    if OwnsRoot then Root.Free;
  end;
end;

procedure TDfmRepoIndex.CollectVarsAt(Section: TAstNode;
  const Unitname: string);
// Sucht alle nkVarSection-Knoten in der gegebenen Section. Jeder Child
// ist typisch ein nkField (Variable) mit Name + TypeRef.
//
// Wir registrieren NUR Variablen, deren TypeRef mit 'T' beginnt -
// damit fangen wir Form/Frame/Datamodule-Singletons ab und ignorieren
// triviale Strings/Integers. Doppel-Registrierung (z.B. zwei Forms mit
// gleichem Var-Namen in unterschiedlichen Units) gewinnt die erste -
// das ist im echten Code ein Naming-Konflikt, hier nur Bookkeeping.
var
  Sections : TList<TAstNode>;
  Sec      : TAstNode;
  V        : TAstNode;
  Info     : TFormVarInfo;
  I, J     : Integer;
begin
  Sections := Section.FindAll(nkVarSection);
  try
    for I := 0 to Sections.Count - 1 do
    begin
      Sec := Sections[I];
      for J := 0 to Sec.Children.Count - 1 do
      begin
        V := Sec.Children[J];
        if V.Kind <> nkField then Continue;
        if V.Name = '' then Continue;
        if (V.TypeRef = '') or (V.TypeRef[1] <> 'T') then Continue;

        if FVars.ContainsKey(LowerCase(V.Name)) then Continue;

        Info.VarName  := V.Name;
        Info.ClassRef := V.TypeRef;
        Info.Unitname := Unitname;
        Info.Line     := V.Line;
        FVars.Add(LowerCase(V.Name), Info);
      end;
    end;
  finally
    Sections.Free;
  end;
end;

procedure TDfmRepoIndex.CollectClassesAt(Section: TAstNode;
  const Unitname: string);
var
  Classes : TList<TAstNode>;
  C       : TAstNode;
  I       : Integer;
  Key     : string;
begin
  Classes := Section.FindAll(nkClass);
  try
    for I := 0 to Classes.Count - 1 do
    begin
      C := Classes[I];
      if C.Name = '' then Continue;
      Key := LowerCase(C.Name);
      if FClassUnit.ContainsKey(Key) then Continue;
      FClassUnit.Add(Key, Unitname);
    end;
  finally
    Classes.Free;
  end;
end;

function TDfmRepoIndex.TryGetVarType(const VarName: string;
  out Info: TFormVarInfo): Boolean;
begin
  Result := FVars.TryGetValue(LowerCase(VarName), Info);
end;

function TDfmRepoIndex.GetUnitForClass(const ClassRef: string): string;
begin
  if not FClassUnit.TryGetValue(LowerCase(ClassRef), Result) then
    Result := '';
end;

function TDfmRepoIndex.VarCount: Integer;
begin
  Result := FVars.Count;
end;

end.
