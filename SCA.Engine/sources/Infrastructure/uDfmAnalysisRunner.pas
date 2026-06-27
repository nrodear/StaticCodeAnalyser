unit uDfmAnalysisRunner;

// Orchestriert die DFM-basierte Analyse fuer eine einzelne Form-/Frame-/
// DataModule-Unit:
//   1. zur gegebenen .pas die passende .dfm suchen (Filename-Konvention -
//      Phase 1: gleicher Basename, gleicher Ordner).
//   2. .dfm einlesen und mit TDfmParser zu einem TComponentGraph parsen.
//   3. alle DFM-Detektoren (Phase 1 startet mit TDfmDefaultNameDetector)
//      ueber den Graph laufen lassen und Findings in die uebergebene
//      Results-Liste einhaengen.
//
// Wenn keine .dfm existiert, ist der Aufruf ein No-Op (kein Befund, kein
// Fehler). Parser-/IO-Fehler werden geschluckt - der Aufrufer
// (TStaticAnalyzer2.RunAllDetectors) hat einen eigenen OnError-Mechanismus,
// aber DFM-Probleme einer einzelnen Unit duerfen den Detektor-Lauf der
// anderen Units nicht stoppen.

interface

uses
  System.Generics.Collections,
  uMethodd12,
  uDfmRepoIndex, uAnalyzeContext;

type
  TDfmAnalysisRunner = class
  public
    class procedure AnalyzePasFile(const PasFileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file EmptyExcept, LongMethod, NestedTry, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.IOUtils,
  uDfmParser, uComponentGraph, uDfmBinaryReader,
  uParser2, uAstNode, uFormBinder,
  uDfmDefaultName,
  uDfmHardcodedCaption,
  uDfmHardcodedDbCreds,
  uDfmDuplicateBinding,
  uDfmDeadEvent,
  uDfmOrphanHandler,
  uDfmEmptyBoundEvent,
  uDfmSchemaMismatch,
  uDfmCircularDataSource,
  uDfmSqlFromUserInput,
  uDfmRequiredField,
  uDfmFieldTypeMismatch,
  uDfmTabOrderConflict,
  uDfmForbiddenClass,
  uDfmDbInUiForm,
  uDfmCrossFormCoupling,
  uDfmLayerViolation,
  uDfmGodHandler,
  uDfmActionMismatch,
  uDfmMasterDetailUnlinked,
  uDfmDataModuleSplitHint;

class procedure TDfmAnalysisRunner.AnalyzePasFile(const PasFileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  DfmFileName : string;
  Source      : string;
  Parser      : TDfmParser;
  Graph       : TComponentGraph;
  PasParser   : TParser2;
  UnitNode    : TAstNode;
  Binding     : TFormBinding;
  RepoIdx     : TDfmRepoIndex;
begin
  RepoIdx := CtxDfmRepoIndex(AContext);
  if PasFileName = '' then Exit;

  // Phase-1-Filename-Konvention: u<X>.pas -> u<X>.dfm im gleichen Ordner.
  DfmFileName := TPath.ChangeExtension(PasFileName, '.dfm');
  if not TFile.Exists(DfmFileName) then Exit;

  try
    // TDfmBinaryReader transparent: liefert Text-DFMs unveraendert
    // zurueck, konvertiert binaere DFMs (TPF0-Praefix) via
    // Classes.ObjectBinaryToText. Vor v0.10.x hat hier ein
    // TFile.ReadAllText(.., UTF8) auf binaere DFMs einen
    // Decode-Fehler geworfen, der vom aeusseren try/except STUMM
    // verschluckt wurde -> binaer-gespeicherte Forms hatten gar
    // keine DFM-Befunde.
    Source := TDfmBinaryReader.ReadFile(DfmFileName);
  except
    Exit;
  end;

  UnitNode := nil;
  Graph    := nil;
  Binding  := nil;
  try
    // 1) DFM parsen
    Parser := TDfmParser.Create;
    try
      Graph := Parser.ParseSource(Source);
    finally
      Parser.Free;
    end;

    // 2) Detektoren, die nur den DFM-Graph brauchen
    TDfmDefaultNameDetector.Analyze(Graph, DfmFileName, Results);
    TDfmHardcodedCaptionDetector.Analyze(Graph, DfmFileName, Results);
    TDfmHardcodedDbCredsDetector.Analyze(Graph, DfmFileName, Results);
    TDfmDuplicateBindingDetector.Analyze(Graph, DfmFileName, Results);
    TDfmCircularDataSourceDetector.Analyze(Graph, DfmFileName, Results);
    TDfmRequiredFieldDetector.Analyze(Graph, DfmFileName, Results);
    TDfmFieldTypeMismatchDetector.Analyze(Graph, DfmFileName, Results);
    TDfmTabOrderConflictDetector.Analyze(Graph, DfmFileName, Results);
    TDfmForbiddenClassDetector.Analyze(Graph, DfmFileName, Results);
    TDfmDbInUiFormDetector.Analyze(Graph, DfmFileName, Results);
    // Aggregat-Hint NACH DbInUiForm (verbraucht dessen Findings als Input)
    TDfmDataModuleSplitHintDetector.Aggregate(DfmFileName, Results);
    TDfmLayerViolationDetector.Analyze(Graph, DfmFileName, Results);
    TDfmActionMismatchDetector.Analyze(Graph, DfmFileName, Results);
    TDfmMasterDetailUnlinkedDetector.Analyze(Graph, DfmFileName, Results);
    TDfmGodHandlerDetector.Analyze(Binding, DfmFileName, Results);

    // Cross-Unit-Detektoren: brauchen den Repo-Index. Wenn er nicht
    // befuellt ist (Single-File-Analyse), schweigen sie selbst.
    TDfmCrossFormCouplingDetector.Analyze(Binding, RepoIdx,
      DfmFileName, Results);

    // 3) Pascal-AST der zugehoerigen .pas parsen (Iteration 3). Fehler
    //    werden geschluckt - DFM-only Detektoren haben bereits gefeuert,
    //    AST-basierte Detektoren skippen wenn UnitNode=nil.
    if TFile.Exists(PasFileName) then
    begin
      try
        PasParser := TParser2.Create;
        try
          UnitNode := PasParser.ParseFile(PasFileName);
        finally
          PasParser.Free;
        end;
      except
        UnitNode := nil;
      end;
    end;

    // 4) Bindung zwischen Graph und Pascal-Klasse aufbauen. Wenn der
    //    Repo-Index gefuellt ist (Multi-File-Scan), versuchen wir die
    //    Klassen-Vererbungs-Kette aufzubauen, damit DeadEvent /
    //    OrphanHandler / SchemaMismatch bei inherited Forms nicht
    //    falsch-positiv ueber geerbte Member feuern.
    if RepoIdx <> nil then
      Binding := TFormBinder.BindWithParents(Graph, UnitNode, RepoIdx)
    else
      Binding := TFormBinder.Bind(Graph, UnitNode);

    // 5) Binder-basierte Detektoren (Iteration 3+)
    TDfmDeadEventDetector.Analyze(Binding, DfmFileName, Results);
    TDfmOrphanHandlerDetector.Analyze(Binding, DfmFileName, Results);
    TDfmEmptyBoundEventDetector.Analyze(Binding, DfmFileName, Results);
    TDfmSchemaMismatchDetector.Analyze(Binding, DfmFileName, Results);
    TDfmSqlFromUserInputDetector.Analyze(Binding, DfmFileName, Results);
  except
    // Parser-/Lookup-Crash bei degenerierten Eingaben nicht propagieren.
    // Der Pascal-Detektor-Lauf laeuft danach sauber weiter.
  end;

  Binding.Free;
  UnitNode.Free;
  Graph.Free;
end;

end.
