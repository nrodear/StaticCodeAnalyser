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
  uCompatSet,  // D11: THashSet<T>-Ersatz (D12: leere Unit, natives THashSet)
  uAstNode, uAstFileCache;

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
    // Klassennamen, die in MEHR ALS EINER Unit deklariert sind.
    // FClassUnit behaelt den ersten Treffer und verwirft den Rest
    // stillschweigend - fuer die Ahnen-Aufloesung ist das eine Wette.
    // Belegt am Korpus: skia4delphi fuehrt TfrmBase zweimal (VCL und
    // FMX); der VCL-Splash wurde gegen die FMX-Basis gebunden, die den
    // Handler nicht kennt - SCA028 meldete einen Load-Crash, den es
    // nicht gibt. Wer auf GetUnitForClass baut, muss wissen, ob die
    // Antwort eindeutig war.
    FClassAmbig : TDictionary<string, Boolean>;
    // SCA184/S4 (2026-10-26): Klassenname -> Pfade ALLER Units, die die
    // Klasse im interface-Teil deklarieren, Header-Stubs ausgenommen
    // (s. IsHeaderStubUnit). FClassUnit behaelt nur den ersten Treffer
    // und kennt keine Sichtbarkeit - S4 muss aber wissen, ob EINE der
    // Deklarationen fuer die Form-Unit ueberhaupt sichtbar ist. Eigene
    // Struktur, damit FormBinder/FrameResolver unberuehrt bleiben.
    FClassDeclUnits : TObjectDictionary<string, TStringList>;
    // Per-Scan-AST-Cache (D.2.3 Infra): von Build reingereicht statt
    // gAstFileCache-Global -> ein Index-Lauf nutzt genau einen Cache.
    FAstCache : TAstFileCache;
    procedure ScanUnit(const PasFileName: string);
    procedure CollectVarsAt(Section: TAstNode; const Unitname: string);
    procedure CollectClassesAt(Section: TAstNode; const Unitname: string;
      AIsHeaderStub: Boolean);
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Build(FileList: TStringList; ACache: TAstFileCache = nil);

    // Lookup: liefert ClassRef und Unitname zur gegebenen Var (z.B. 'Form2'
    // -> 'TForm2' / 'C:\repo\uForm2.pas'). False wenn unbekannt.
    function TryGetVarType(const VarName: string;
      out Info: TFormVarInfo): Boolean;

    // Lookup: Klasse -> Unit-Datei (oder '', wenn nicht gefunden).
    function GetUnitForClass(const ClassRef: string): string;
    // True, wenn der Name in mehreren Units deklariert ist -
    // GetUnitForClass hat dann GERATEN. Aufrufer, die aus dem
    // Ergebnis auf Abwesenheit schliessen, muessen das pruefen.
    function IsClassAmbiguous(const ClassRef: string): Boolean;

    // SCA184/S4: True, wenn eine fuer die Form-Unit SICHTBARE Unit die
    // Klasse deklariert - so loest auch der Compiler den Feldtyp auf.
    // Sichtbar = die Form-Unit selbst (AOwnUnitPath, Pfadvergleich) oder
    // eine Unit, deren Name in AUsedUnits steht (uses-Eintraege, klein).
    // Ein Eintrag ohne Unit-Scope-Praefix ('stdctrls') trifft auch die
    // Datei 'Vcl.StdCtrls.pas'. Header-Stubs zaehlen nie.
    function IsClassDeclaredInVisibleUnit(const ClassRef, AOwnUnitPath: string;
      AUsedUnits: THashSet<string>): Boolean;

    // Anzahl der erfassten Form-Variablen - praktisch fuer "Pipeline ready?"
    // Checks im Detektor.
    function VarCount: Integer;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, FreeWithoutNil, GroupedDeclaration, NestedTry, NilComparison, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uParser2,
  uStaticFiles;   // IsUnitLikeFile - Dialekt-Endungen (Lazarus A3)

constructor TDfmRepoIndex.Create;
begin
  inherited;
  FVars      := TDictionary<string, TFormVarInfo>.Create;
  FClassUnit := TDictionary<string, string>.Create;
  FClassAmbig := TDictionary<string, Boolean>.Create;
  FClassDeclUnits := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
end;

destructor TDfmRepoIndex.Destroy;
begin
  FClassDeclUnits.Free;
  FClassUnit.Free;
  FClassAmbig.Free;
  FVars.Free;
  inherited;
end;

procedure TDfmRepoIndex.Build(FileList: TStringList; ACache: TAstFileCache);
var
  I: Integer;
  FN: string;
begin
  FAstCache := ACache;
  FVars.Clear;
  FClassUnit.Clear;
  FClassAmbig.Clear;
  FClassDeclUnits.Clear;
  if FileList = nil then Exit;

  for I := 0 to FileList.Count - 1 do
  begin
    FN := FileList[I];
    if FN = '' then Continue;
    // Lazarus A3: .pp/.lpr sind bei dlFpc vollwertige Units fuer den
    // Index - das harte '.pas'-Gate hielt sie draussen (dokumentierte
    // A2-Degradation). Bei dlDelphi identisches Verhalten wie zuvor.
    if not TStaticFiles.IsUnitLikeFile(FN) then Continue;
    ScanUnit(FN);
  end;
end;

function ImplHasIncludeDirective(const PasFileName: string;
  FromLine: Integer): Boolean;
// Steht ab der implementation-Zeile ein {$I datei} / {$INCLUDE datei}?
// Der Parser expandiert Includes nicht - die Lazarus-LCL legt ganze
// Implementierungen in .inc-Dateien (lcl/toolwin.pp, spinex.pp). Solche
// Units sind uebersetzbar und KEIN Header-Stub. '{$I+}'/'{$I-}' (I/O-
// Pruefung) und '{$IFDEF' tragen kein Leerzeichen nach dem I und zaehlen
// nicht. Lesefehler -> True: im Zweifel kein Stub (alte S4-Wirkung).
var
  Lines : TStringList;
  I     : Integer;
  Up    : string;
begin
  Result := True;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(PasFileName);
    except
      Exit;
    end;
    I := FromLine - 1;
    if I < 0 then I := 0;
    while I < Lines.Count do
    begin
      Up := UpperCase(Lines[I]);
      if (Pos('{$I ', Up) > 0) or (Pos('{$INCLUDE ', Up) > 0) then Exit;
      Inc(I);
    end;
    Result := False;
  finally
    Lines.Free;
  end;
end;

function IsHeaderStubUnit(Root: TAstNode; const PasFileName: string): Boolean;
// Header-Stub (SCA184/S4, 2026-10-26): die Unit deklariert im interface-
// Teil Routinen, die einen Rumpf brauchen (nicht abstract/external), hat
// aber im implementation-Teil KEINE einzige Routine. So eine Unit ist
// nicht uebersetzbar (E2065) und kann nicht die Klasse einer gestreamten
// Komponente liefern. Korpus-Anlass: cnwizards/Bin/PSDecl - Pascal-
// Script-Deklarationskoepfe namens StdCtrls.pas/Menus.pas/ExtCtrls.pas
// mit leerem implementation-Teil; per Unit-Name sind sie von jeder alten
// Form mit 'uses StdCtrls' aus "sichtbar".
// Ohne interface- oder implementation-Abschnitt: kein Stub (konservativ).
// Grenze: eine Unit, die NUR Interface-Typen mit Methoden und rumpflose
// Klassen traegt, gilt ebenfalls als Stub (der Parser fuehrt Interfaces als
// nkClass) - ihre Klassen verlieren nur den S4-Skip.
var
  IFace, Impl, Cur : TAstNode;
  Stack            : TList<TAstNode>;
  I                : Integer;
  NeedsBody        : Boolean;
begin
  Result := False;
  if Root = nil then Exit;
  IFace := Root.FindFirstChild(nkInterface);
  Impl  := Root.FindFirstChild(nkImplementation);
  if (IFace = nil) or (Impl = nil) then Exit;
  // Schneller Ausgang fuer fast alle Units: es gibt einen Rumpf.
  if Impl.FindFirst(nkMethod) <> nil then Exit;

  NeedsBody := False;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(IFace);
    while (Stack.Count > 0) and (not NeedsBody) do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      // Direktiven stehen klein in TypeRef ('proc;virtual;abstract').
      if (Cur.Kind = nkMethod) and
         (Pos(';abstract', Cur.TypeRef) = 0) and
         (Pos(';external', Cur.TypeRef) = 0) then
        NeedsBody := True;
      for I := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[I]);
    end;
  finally
    Stack.Free;
  end;
  if not NeedsBody then Exit;
  Result := not ImplHasIncludeDirective(PasFileName, Impl.Line);
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
  OwnsRoot := False;

  if Assigned(FAstCache) then
    Root := FAstCache.Acquire(PasFileName)
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
    CollectClassesAt(IFace, PasFileName, IsHeaderStubUnit(Root, PasFileName));
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
  const Unitname: string; AIsHeaderStub: Boolean);
var
  Classes : TList<TAstNode>;
  C       : TAstNode;
  I       : Integer;
  Key      : string;
  Existing : string;
  Decls    : TStringList;
begin
  Classes := Section.FindAll(nkClass);
  try
    for I := 0 to Classes.Count - 1 do
    begin
      C := Classes[I];
      if C.Name = '' then Continue;
      Key := LowerCase(C.Name);
      // S4-Sicht: alle deklarierenden Units ausser Header-Stubs. Laeuft
      // VOR dem FClassUnit-Zweig, weil der bei Mehrfachdeklaration per
      // Continue aussteigt.
      if not AIsHeaderStub then
      begin
        if not FClassDeclUnits.TryGetValue(Key, Decls) then
        begin
          Decls := TStringList.Create;
          FClassDeclUnits.Add(Key, Decls);
        end;
        if Decls.IndexOf(Unitname) < 0 then
          Decls.Add(Unitname);
      end;
      if FClassUnit.TryGetValue(Key, Existing) then
      begin
        // Nur ueber UNIT-Grenzen hinweg mehrdeutig. Zwei nkClass mit
        // gleichem Namen in DERSELBEN Unit sind der IFDEF-Zwilling -
        // beide beschreiben dieselbe Klasse, die Wahl ist harmlos.
        if not SameText(Existing, Unitname) then
          FClassAmbig.AddOrSetValue(Key, True);
        Continue;
      end;
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

function TDfmRepoIndex.IsClassAmbiguous(const ClassRef: string): Boolean;
begin
  Result := FClassAmbig.ContainsKey(LowerCase(ClassRef));
end;

function TDfmRepoIndex.IsClassDeclaredInVisibleUnit(const ClassRef,
  AOwnUnitPath: string; AUsedUnits: THashSet<string>): Boolean;
var
  Decls   : TStringList;
  DeclFn  : string;
  OwnFull : string;
  UnitLow : string;
  P       : Integer;
begin
  Result := False;
  if not FClassDeclUnits.TryGetValue(LowerCase(ClassRef), Decls) then Exit;
  OwnFull := '';
  if AOwnUnitPath <> '' then OwnFull := ExpandFileName(AOwnUnitPath);
  for DeclFn in Decls do
  begin
    // Eigene Unit: Interposer 'TButton = class(Vcl.StdCtrls.TButton)'.
    // Pfad statt Name - 'MainFrm'/'Unit1' gibt es in jedem zweiten
    // Projekt eines Sammel-Scans.
    if (OwnFull <> '') and SameText(ExpandFileName(DeclFn), OwnFull) then
      Exit(True);
    if AUsedUnits = nil then Continue;
    UnitLow := LowerCase(ChangeFileExt(ExtractFileName(DeclFn), ''));
    if AUsedUnits.Contains(UnitLow) then Exit(True);
    // Unit-Scope-Suffixe: 'vcl.styles.colortabs' -> 'styles.colortabs',
    // 'colortabs' - ein uses-Eintrag darf das Scope-Praefix weglassen.
    P := Pos('.', UnitLow);
    while P > 0 do
    begin
      if AUsedUnits.Contains(Copy(UnitLow, P + 1, MaxInt)) then Exit(True);
      P := Pos('.', UnitLow, P + 1);
    end;
  end;
end;

function TDfmRepoIndex.VarCount: Integer;
begin
  Result := FVars.Count;
end;

end.
