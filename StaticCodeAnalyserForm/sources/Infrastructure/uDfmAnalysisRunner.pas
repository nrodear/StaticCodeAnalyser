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
  uDfmRepoIndex;

var
  // Optionaler Repo-Index fuer Cross-Unit-Detektoren. Wird von
  // TStaticAnalyzer2.ParseLeaks einmal pro Scan befuellt und am Ende
  // freigegeben. Bei Single-File-Analyse bleibt der Index nil und
  // Cross-Unit-Detektoren (z.B. fkDfmCrossFormCoupling) schweigen.
  gDfmRepoIndex: TDfmRepoIndex = nil;

type
  TDfmAnalysisRunner = class
  public
    class procedure AnalyzePasFile(const PasFileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uDfmParser, uComponentGraph,
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
  uDfmActionMismatch;

class procedure TDfmAnalysisRunner.AnalyzePasFile(const PasFileName: string;
  Results: TObjectList<TLeakFinding>);
var
  DfmFileName : string;
  Source      : string;
  Parser      : TDfmParser;
  Graph       : TComponentGraph;
  PasParser   : TParser2;
  UnitNode    : TAstNode;
  Binding     : TFormBinding;
begin
  if PasFileName = '' then Exit;

  // Phase-1-Filename-Konvention: u<X>.pas -> u<X>.dfm im gleichen Ordner.
  DfmFileName := TPath.ChangeExtension(PasFileName, '.dfm');
  if not TFile.Exists(DfmFileName) then Exit;

  try
    // DFM ist im Repo standardmaessig ASCII-Text - explizit als UTF-8 mit
    // ASCII-Fallback. Binaer-DFM laesst den Parser unten knallen; das
    // faengt der aeussere try/except ab.
    Source := TFile.ReadAllText(DfmFileName, TEncoding.UTF8);
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
    TDfmLayerViolationDetector.Analyze(Graph, DfmFileName, Results);
    TDfmActionMismatchDetector.Analyze(Graph, DfmFileName, Results);
    TDfmGodHandlerDetector.Analyze(Binding, DfmFileName, Results);

    // Cross-Unit-Detektoren: brauchen den Repo-Index. Wenn er nicht
    // befuellt ist (Single-File-Analyse), schweigen sie selbst.
    TDfmCrossFormCouplingDetector.Analyze(Binding, gDfmRepoIndex,
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

    // 4) Bindung zwischen Graph und Pascal-Klasse aufbauen
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
