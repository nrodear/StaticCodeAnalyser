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
    // Struktur, damit FormBinder/FrameResolver unberuehrt bleiben. Die
    // Pfade liegen normalisiert vor (NormalizeUnitPath), damit die Abfrage
    // je Komponente nur noch vergleicht.
    FClassDeclUnits : TObjectDictionary<string, TStringList>;
    // Per-Scan-AST-Cache (D.2.3 Infra): von Build reingereicht statt
    // gAstFileCache-Global -> ein Index-Lauf nutzt genau einen Cache.
    FAstCache : TAstFileCache;
    procedure ScanUnit(const PasFileName: string);
    procedure CollectVarsAt(Section: TAstNode; const Unitname: string);
    procedure CollectClassesAt(Section: TAstNode; const Unitname: string);
    // SCA184/S4: Klassen der Unit in FClassDeclUnits eintragen. Der
    // Aufrufer ruft das nur fuer Units, die kein Header-Stub sind.
    procedure CollectVisibleClassDecls(Section: TAstNode;
      const Unitname: string);
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
    // Sichtbar = die Form-Unit selbst (AOwnUnitFull, Pfadvergleich) oder
    // eine Unit, deren Name in AUsedUnits steht (uses-Eintraege, klein).
    // Ein Eintrag ohne Unit-Scope-Praefix ('stdctrls') trifft auch die
    // Datei 'Vcl.StdCtrls.pas'. Header-Stubs zaehlen nie.
    // AOwnUnitFull MUSS durch NormalizeUnitPath gelaufen sein - der
    // Aufrufer rechnet das einmal je Form, nicht je Komponente.
    function IsClassDeclaredInVisibleUnit(const ClassRef, AOwnUnitFull: string;
      AUsedUnits: THashSet<string>): Boolean;
    // Pfadform, in der FClassDeclUnits die Units fuehrt (ExpandFileName;
    // '' bleibt '').
    class function NormalizeUnitPath(const APath: string): string; static;

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

function DirectiveIsInclude(const AUp: string; AFrom: Integer): Boolean;
// AUp = gross geschriebene Zeile, AFrom = erstes Zeichen hinter dem '$'.
// Include ist '$I' oder '$INCLUDE', gefolgt von Whitespace (Leerzeichen,
// Tab) oder einem Apostroph ({$I'datei.inc'}). Die Bedingung an das
// Folgezeichen haelt {$IF}, {$IFDEF}, {$IFNDEF}, {$IFEND}, {$IFOPT},
// {$IMPORTEDDATA} und die I/O-Pruefung {$I+}/{$I-} heraus.
var
  After : Integer;
begin
  if Copy(AUp, AFrom, 7) = 'INCLUDE' then
    After := AFrom + 7
  else
    After := AFrom + 1;
  Result := (Copy(AUp, AFrom, 1) = 'I') and (After <= Length(AUp)) and
            ((AUp[After] <= ' ') or (AUp[After] = ''''));
end;

function HasIncludeAfter(const AUp, AOpener: string): Boolean;
// Prueft jede Direktive der Zeile, die mit AOpener ('{$' oder '(*$')
// beginnt - '{$IFDEF X}{$I a.inc}' traegt das Include an zweiter Stelle.
var
  P : Integer;
begin
  Result := False;
  P := Pos(AOpener, AUp);
  while (P > 0) and not Result do
  begin
    Result := DirectiveIsInclude(AUp, P + Length(AOpener));
    P := Pos(AOpener, AUp, P + 1);
  end;
end;

function LineHasIncludeDirective(const ALine: string): Boolean;
// {$I datei}, {$INCLUDE datei}, (*$I datei*) - Gross-/Kleinschreibung egal.
// Wie bisher ein reiner Zeilen-Textvergleich: ein Include in einem
// Kommentar oder String zaehlt mit - die sichere Seite (dann kein Stub,
// alte S4-Wirkung).
var
  Up : string;
begin
  Up := UpperCase(ALine);
  Result := HasIncludeAfter(Up, '{$') or HasIncludeAfter(Up, '(*$');
end;

function ImplHasIncludeDirective(const PasFileName: string;
  FromLine: Integer): Boolean;
// Steht ab der implementation-Zeile eine Include-Direktive?
// Der Parser expandiert Includes nicht - die Lazarus-LCL legt ganze
// Implementierungen in .inc-Dateien (lcl/toolwin.pp, spinex.pp). Solche
// Units sind uebersetzbar und KEIN Header-Stub. Lesefehler -> True: im
// Zweifel kein Stub (alte S4-Wirkung).
var
  Lines : TStringList;
  I     : Integer;
begin
  Result := True;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(PasFileName);
    except
      // Nur, was LoadFromFile an Dateiproblemen wirft: EFOpenError und
      // EReadError (beide EStreamError) sowie EEncodingError (ungueltiges
      // UTF-8 hinter einer BOM). Alles andere (EOutOfMemory ...) ist kein
      // Dateiproblem und laeuft weiter.
      on EStreamError do Exit;
      on EEncodingError do Exit;
    end;
    I := FromLine - 1;
    if I < 0 then I := 0;
    while I < Lines.Count do
    begin
      if LineHasIncludeDirective(Lines[I]) then Exit;
      Inc(I);
    end;
    Result := False;
  finally
    Lines.Free;
  end;
end;

function MethodNeedsBody(M: TAstNode): Boolean;
// Braucht diese interface-Deklaration einen Rumpf im implementation-Teil?
// Direktiven stehen klein in TypeRef ('proc;virtual;abstract'), external
// auch bei Routinen auf Unit-Ebene ('proc;external').
// GRENZEN (bekannt, bewusst nicht behoben):
// - Interface-Typen (IFoo = interface): ihre Methoden brauchen keinen
//   Rumpf, zaehlen hier aber mit. Der Parser fuehrt sie als nkClass ohne
//   jedes Unterscheidungsmerkmal (Kopf-Keyword, GUID und Elternliste gehen
//   nicht in den Knoten) - aus dem AST nicht verlaesslich erkennbar.
// - 'dynamic; abstract;': 'dynamic' steht nicht in IsMethodDirectiveTok,
//   ParseMethodDirectives bricht dort ab, ';abstract' fehlt im TypeRef.
//   Den Parser dafuer anzufassen haette Folgewirkungen auf viele Detektoren.
// Beide Faelle machen eine Unit nur dann faelschlich zum Stub, wenn ihr
// implementation-Teil GAR KEINE Routine hat; ihre Klassen verlieren dann
// nur den S4-Skip.
begin
  Result := (M.Kind = nkMethod) and
            (Pos(';abstract', M.TypeRef) = 0) and
            (Pos(';external', M.TypeRef) = 0);
end;

function SectionNeedsBody(ASection: TAstNode): Boolean;
// Deklariert der Abschnitt (rekursiv, auch in Klassen) eine Routine, die
// einen Rumpf braucht?
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Result := False;
  Methods := ASection.FindAll(nkMethod);
  try
    for M in Methods do
      if MethodNeedsBody(M) then Exit(True);
  finally
    Methods.Free;
  end;
end;

function IsHeaderStubUnit(Root: TAstNode; const PasFileName: string): Boolean;
// Header-Stub (SCA184/S4, 2026-10-26): die Unit deklariert im interface-
// Teil Routinen, die einen Rumpf brauchen (MethodNeedsBody), hat aber im
// implementation-Teil KEINE einzige Routine und kein Include. So eine Unit
// ist nicht uebersetzbar (E2065) und kann nicht die Klasse einer
// gestreamten Komponente liefern. Korpus-Anlass: cnwizards/Bin/PSDecl -
// Pascal-Script-Deklarationskoepfe namens StdCtrls.pas/Menus.pas/
// ExtCtrls.pas mit leerem implementation-Teil; per Unit-Name sind sie von
// jeder alten Form mit 'uses StdCtrls' aus "sichtbar".
// Ohne interface- oder implementation-Abschnitt: kein Stub (konservativ).
var
  IFace, Impl : TAstNode;
begin
  Result := False;
  if Root = nil then Exit;
  IFace := Root.FindFirstChild(nkInterface);
  Impl  := Root.FindFirstChild(nkImplementation);
  if (IFace = nil) or (Impl = nil) then Exit;
  // Schneller Ausgang fuer fast alle Units: es gibt einen Rumpf.
  if Impl.FindFirst(nkMethod) <> nil then Exit;
  if not SectionNeedsBody(IFace) then Exit;
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
    CollectClassesAt(IFace, PasFileName);
    if not IsHeaderStubUnit(Root, PasFileName) then
      CollectVisibleClassDecls(IFace, PasFileName);
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
  Key      : string;
  Existing : string;
begin
  Classes := Section.FindAll(nkClass);
  try
    for I := 0 to Classes.Count - 1 do
    begin
      C := Classes[I];
      if C.Name = '' then Continue;
      Key := LowerCase(C.Name);
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

function IsTypeHelperAt(Lines: TStringList; R: TAstNode): Boolean;
// Steht an (R.Line, R.Col) das Schluesselwort 'type'? (s. FirstTypeHelperLine)
begin
  Result := (R.Line >= 1) and (R.Line <= Lines.Count) and
            SameText(Copy(Lines[R.Line - 1], R.Col, 4), 'type');
end;

function FirstTypeHelperLine(Section: TAstNode;
  const PasFileName: string): Integer;
// Zeile der ersten FPC-'type helper'-Deklaration einer .pp-Unit, 0 = keine
// (oder keine .pp-Unit). TParser2 fuehrt den type helper seit der Parser-
// Charge P1 (2026-10-27) als nkRecord an der Position des 'type'-Tokens;
// ein gewoehnlicher record steht auf 'record'. Der Quelltext an (Zeile,
// Spalte) entscheidet also - Kommentare und Strings erzeugen keinen Knoten.
// Lesefehler -> 0 (Klassen zaehlen wie bei jeder anderen Unit).
var
  Recs  : TList<TAstNode>;
  R     : TAstNode;
  Lines : TStringList;
begin
  Result := 0;
  if not SameText(ExtractFileExt(PasFileName), '.pp') then Exit;
  Recs := Section.FindAll(nkRecord);
  try
    if Recs.Count = 0 then Exit;
    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(PasFileName);
      except
        // wie ImplHasIncludeDirective: nur Dateiprobleme abfangen
        on EStreamError do Exit;
        on EEncodingError do Exit;
      end;
      for R in Recs do
        if IsTypeHelperAt(Lines, R) and ((Result = 0) or (R.Line < Result)) then
          Result := R.Line;
    finally
      Lines.Free;
    end;
  finally
    Recs.Free;
  end;
end;

procedure TDfmRepoIndex.CollectVisibleClassDecls(Section: TAstNode;
  const Unitname: string);
// S4-Sicht: ALLE deklarierenden Units je Klasse (FClassUnit behaelt nur
// den ersten Treffer). Der Pfad wird hier EINMAL je Unit normalisiert.
//
// Was als Projekt-Unit zaehlt (Nico, 2026-10-27): LCL-Klassen sind fuer S4
// NICHT projekteigen - die SCA184-Funde zu TLabel/TButton/... im Lazarus-
// Korpus bleiben. Bis zur Parser-Charge P1 sorgte dafuer ein Parserfehler:
// hinter einem FPC-'type helper' fehlten alle Klassen der Unit im AST
// (lcl/stdctrls.pp). Seit P1 sieht der Parser sie; damit S4 sein bisheriges
// Ergebnis behaelt, zaehlen in einer .pp-Unit (FPC-/LCL-Bibliotheksform)
// nur die Klassen VOR der ersten 'type helper'-Deklaration. Alle anderen
// Sichten (FClassUnit, FormBinder, Detektoren) sehen die Klassen voll.
var
  Classes : TList<TAstNode>;
  C       : TAstNode;
  Key     : string;
  FullFn  : string;
  Decls   : TStringList;
  HelperLine : Integer;
begin
  FullFn  := NormalizeUnitPath(Unitname);
  HelperLine := FirstTypeHelperLine(Section, Unitname);
  Classes := Section.FindAll(nkClass);
  try
    for C in Classes do
    begin
      if C.Name = '' then Continue;
      if (HelperLine > 0) and (C.Line > HelperLine) then Continue;
      Key := LowerCase(C.Name);
      if not FClassDeclUnits.TryGetValue(Key, Decls) then
      begin
        Decls := TStringList.Create;
        FClassDeclUnits.Add(Key, Decls);
      end;
      if Decls.IndexOf(FullFn) < 0 then
        Decls.Add(FullFn);
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

function IsUnitNameUsed(const AUnitFile: string;
  AUsedUnits: THashSet<string>): Boolean;
// Steht der Unit-Name (Dateistamm) von AUnitFile in den uses-Eintraegen?
// Unit-Scope-Suffixe zaehlen mit: 'vcl.styles.colortabs' wird auch als
// 'styles.colortabs' und 'colortabs' gesucht - ein uses-Eintrag darf das
// Scope-Praefix weglassen.
var
  UnitLow : string;
  P       : Integer;
begin
  UnitLow := LowerCase(ChangeFileExt(ExtractFileName(AUnitFile), ''));
  Result  := AUsedUnits.Contains(UnitLow);
  P := Pos('.', UnitLow);
  while (P > 0) and not Result do
  begin
    Result := AUsedUnits.Contains(Copy(UnitLow, P + 1, MaxInt));
    P := Pos('.', UnitLow, P + 1);
  end;
end;

function TDfmRepoIndex.IsClassDeclaredInVisibleUnit(const ClassRef,
  AOwnUnitFull: string; AUsedUnits: THashSet<string>): Boolean;
var
  Decls   : TStringList;
  DeclFn  : string;
begin
  Result := False;
  if not FClassDeclUnits.TryGetValue(LowerCase(ClassRef), Decls) then Exit;
  for DeclFn in Decls do
  begin
    // Eigene Unit: Interposer 'TButton = class(Vcl.StdCtrls.TButton)'.
    // Pfad statt Name - 'MainFrm'/'Unit1' gibt es in jedem zweiten
    // Projekt eines Sammel-Scans. Beide Seiten sind normalisiert.
    if (AOwnUnitFull <> '') and SameText(DeclFn, AOwnUnitFull) then
      Exit(True);
    if (AUsedUnits <> nil) and IsUnitNameUsed(DeclFn, AUsedUnits) then
      Exit(True);
  end;
end;

class function TDfmRepoIndex.NormalizeUnitPath(const APath: string): string;
begin
  if APath = '' then
    Result := ''
  else
    Result := ExpandFileName(APath);
end;

function TDfmRepoIndex.VarCount: Integer;
begin
  Result := FVars.Count;
end;

end.
