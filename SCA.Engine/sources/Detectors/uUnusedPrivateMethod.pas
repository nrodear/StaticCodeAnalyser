unit uUnusedPrivateMethod;

// Detektor: private Methode wird in der Unit nie aufgerufen.
//
// Pattern (Code Smell, Sonar-50 #37):
//   TFoo = class
//   private
//     procedure HelperA;            // <-- nie gerufen, alter Refactoring-Rest
//   public
//     procedure DoStuff;
//   end;
//
// Erkennung (AST + lexisch):
//   * Phase 1: walke nkClass -> nkVisibilitySection mit Name='private' oder
//     'strict private'. Sammle alle nkMethod-Children -> Method-Namen
//     (unqualifiziert) als Kandidaten.
//   * Phase 2: lese den File-Text, strippe Strings + Kommentare. Suche
//     pro Kandidaten-Namen nach `\bMethodName\b` als ganzes Wort.
//     Ein Treffer = Aufruf irgendwo. Skip-Pattern:
//        - Die Deklaration selbst (TypeRef-Zeile im class-body).
//        - Die Implementation `procedure TFoo.MethodName;` - der Identifier
//          taucht da auch auf, ist aber kein "Aufruf".
//     Heuristik: wir zaehlen ALLE Vorkommen. Wenn Count > 2 (Deklaration +
//     ggf. Implementation-Header) -> als verwendet markieren.
//     Damit bleiben TRUE-Unused-Methoden klar identifizierbar; FPs koennen
//     bei super-kurzen Namen entstehen (`Init`, `Get`) - in der Praxis aber
//     selten weil Pascal-Code unterschiedliche Klassen mit eigenen Methoden
//     selten ueber die gleiche Schreibweise verteilt.
//
// Limitierungen:
//   * Cross-unit-Aufrufe von public Methoden sind kein Problem - wir
//     analysieren nur PRIVATE Methoden, die ohnehin nur in der eigenen
//     Unit aufgerufen werden duerfen.
//   * Property-Getter/Setter (`Get*` / `Set*` private Methoden) werden
//     zwar als Methoden gesehen, ihre Verwendung via Property-Block
//     `read FGetSomething` zaehlt aber als Treffer in der Text-Suche -
//     also kein FP.
//   * RTTI / interfaces via TypeInfo werden NICHT erkannt.
//     Suppression-Marker `// noinspection UnusedPrivateMethod` als
//     Escape-Hatch.
//
// DFM-EVENT-BINDINGS (seit 2026-06-20):
//   Wenn neben der .pas eine gleichnamige .dfm liegt (Standard-VCL-
//   Konvention), wird sie mitgescannt: alle Event-Property-Werte
//   (`OnClick = btnGoClick`) sind Implicit-Callers fuer den Pascal-
//   Code. Private Methoden die als Handler eingetragen sind werden
//   damit nicht mehr als unused gemeldet.
//   Implementierung: Regex `^\s*On\w+\s*=\s*(\w+)\s*$` pro DFM-Zeile;
//   Match per case-insensitive HashSet<string>. Skript-only DFMs ohne
//   bekanntes File-Extension-Mapping bleiben unentdeckt - akzeptabel.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnusedPrivateMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NestedTry, NilComparison, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.IOUtils,
  uDetectorUtils, uFileTextCache;

// Liest die zur PAS-Datei gehoerende DFM (gleicher Pfad mit .dfm-Extension)
// und extrahiert alle Event-Handler-Werte. Pattern:
//   ^<whitespace>On<word> = <handlerName>$
// Beispiel: `  OnClick = btnGoClick` -> 'btngoclick'
//
// Result-Dict ist owned by Caller (FreeAndNil oder try-finally). Wenn die
// DFM nicht existiert oder nicht lesbar ist, kommt ein leeres Dict zurueck -
// Detector behandelt das wie "keine DFM-Bindings".
function BuildDfmHandlerSet(const PasFileName: string): TDictionary<string, Boolean>;
const
  HANDLER_RE = '^\s*On\w+\s*=\s*(\w+)\s*$';
var
  DfmPath : string;
  DfmText : string;
  RE      : TRegEx;
  M       : TMatch;
  Name    : string;
begin
  Result := TDictionary<string, Boolean>.Create;
  if PasFileName = '' then Exit;
  DfmPath := ChangeFileExt(PasFileName, '.dfm');
  if not TFile.Exists(DfmPath) then Exit;
  try
    DfmText := TFile.ReadAllText(DfmPath);
  except
    // Datei-IO-Fehler -> wie "keine DFM"
    Exit;
  end;
  RE := TRegEx.Create(HANDLER_RE, [roMultiLine]);
  for M in RE.Matches(DfmText) do
  begin
    Name := LowerCase(M.Groups[1].Value);
    if Name <> '' then Result.AddOrSetValue(Name, True);
  end;
end;

function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

function IsPrivateSection(const Name: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(Name));
  Result := (Low = 'private') or (Low = 'strict private');
end;

class procedure TUnusedPrivateMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Classes    : TList<TAstNode>;
  C          : TAstNode;
  S, Mth     : TAstNode;
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  RE         : TRegEx;
  Count      : Integer;
  M          : TMatch;
  MethName   : string;
  MethLow    : string;
  F          : TLeakFinding;
  DfmHandlers: TDictionary<string, Boolean>;
  LineFor    : TArray<Integer>; // von der zentralen Strip-Fassung, hier ungenutzt
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // 2026-07-04: lokale Strip-Kopie durch zentrale TDetectorUtils-Fassung
    // ersetzt (Audit Duplikations-Rest). Verhaltensgleich zur alten Variante:
    // FillCh=' ' wie frueher (String-Inhalte -> Space, nicht Tilde-Default),
    // und LowerCase auf dem Gesamtergebnis ist aequivalent zum frueheren
    // Inline-LowerCase pro Code-Zeichen (LowerCase(' ')=' ', #10 invariant).
    Code := LowerCase(TDetectorUtils.StripStringsAndComments(Lines, LineFor, ' '));
    // DFM-Event-Handler-Set fuer diese .pas/.dfm-Paarung.
    DfmHandlers := BuildDfmHandlerSet(FileName);
    try
      Classes := UnitNode.FindAll(nkClass);
      try
        for C in Classes do
        begin
          // Direkte Children der Klasse durchgehen, Visibility-Sections
          // mit Name 'private' / 'strict private' aufspueren.
          for S in C.Children do
          begin
            if S.Kind <> nkVisibilitySection then Continue;
            if not IsPrivateSection(S.Name) then Continue;

            // Methoden in dieser Section sammeln.
            for Mth in S.Children do
            begin
              if Mth.Kind <> nkMethod then Continue;
              MethName := UnqualifiedName(Mth.Name);
              if MethName = '' then Continue;
              MethLow := LowerCase(MethName);

              // DFM-Binding-Check: ist die Methode als Event-Handler in
              // der gleichnamigen .dfm eingetragen? Dann ist sie laufzeit-
              // referenziert und kein Unused-Kandidat.
              if DfmHandlers.ContainsKey(MethLow) then Continue;

              // Text-Scan: wie oft taucht das Wort im File-Body auf?
              RE := TRegEx.Create('\b' + MethLow + '\b');
              Count := 0;
              for M in RE.Matches(Code) do
              begin
                Inc(Count);
                if Count > 2 then Break; // genug Belege fuer Use
              end;
              if Count > 2 then Continue;

              F            := TLeakFinding.Create;
              F.FileName   := FileName;
              F.MethodName := Mth.Name;
              F.LineNumber := IntToStr(Mth.Line);
              F.MissingVar := Format(
                'Private method %s.%s appears unused (no call within the unit)',
                [C.Name, MethName]);
              F.SetKind(fkUnusedPrivateMethod);
              Results.Add(F);
            end;
          end;
        end;
      finally
        Classes.Free;
      end;
    finally
      DfmHandlers.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
