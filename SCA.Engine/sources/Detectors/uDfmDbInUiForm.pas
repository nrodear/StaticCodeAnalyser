unit uDfmDbInUiForm;

// Detektor: DB-Komponente liegt direkt auf einer TForm/TFrame statt im
// dafuer vorgesehenen TDataModule.
//
// Architektur-Smell: Verbindungen, Queries, StoredProcs gehoeren in ein
// DataModule, das von allen Forms gemeinsam genutzt wird. Direkt auf der
// Form liegende DB-Komponenten erschweren das Test-Setup, machen
// Connection-Pooling unmoeglich und fuehren dazu, dass das Schliessen der
// Form die Verbindung beendet.
//
// Ist die Wurzel ein DataModule?
//   1. VORRANG: die aufgeloeste Klassenkette der zugehoerigen .pas. Endet
//      sie in TDataModule, ist die Wurzel eines - egal wie sie heisst.
//   2. RUECKFALL, wenn keine Kette da ist (keine .pas, Parse-Fehler,
//      Single-File-Lauf): Klassenname endet auf 'DataModule'.
// Sonst: alle DB-Komponenten (TADOConnection, TFDQuery, ...) im
// Komponenten-Baum melden.
//
// WARUM DER NAME NUR NOCH RUECKFALL IST (Voll-Review 2026-09-12,
// Verdacht 297 - am Korpus BESTAETIGT): der Suffix-Test allein erkannte
// 6 von 41 direkten TDataModule-Nachfahren, also 15 %. Durchgefallen sind
// unter anderem die verbreitete Praefix-Konvention (TdmMain, TdmodURI),
// abgekuerzte Formen (TDM, TDMDS, TCustomersDM), sprechende Namen
// (TEntitiesModule, TGlobalModule, TImagesModule), die JVCL-Action-Module
// (TJvPlugIn, TJvDBActions) - und sogar der IDE-Vorgabename TDataModule1,
// weil der auf '1' endet. Auf 36 Korpusdateien standen dadurch 72 Funde,
// deren Meldetext sich selbst widerspricht: "lives on dmMain (TdmMain) -
// move to a TDataModule", wo TdmMain bereits eines IST.
//
// Erkennung der DB-Klassen ueber die bestehende Whitelist aus
// uDfmDbFieldAnalysis (DataSetClass / DataSourceClass) plus ein paar
// zusaetzliche Connection-Klassen.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uComponentGraph, uDfmDbFieldAnalysis, uFormBinder;

type
  TDfmDbInUiFormDetector = class
  public
    // ABinding darf nil sein (Single-File-Lauf, fehlende .pas): dann
    // entscheidet allein der Klassenname wie vor dem 2026-09-12.
    class procedure Analyze(Graph: TComponentGraph; ABinding: TFormBinding;
      const FileName: string; Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils, uDetectorUtils;   // FirstParentToken (Ahnen-Token)

const
  // Connection-Klassen, die auch nicht auf eine UI-Form gehoeren - durch
  // die Whitelist hier ergaenzt, weil uDfmDbFieldAnalysis nur DataSet/
  // DataSource kennt.
  CONNECTION_CLASSES: array[0..6] of string = (
    'TADOConnection', 'TFDConnection', 'TIBDatabase',
    'TSQLConnection', 'TZConnection', 'TUniConnection',
    'TOracleSession'
  );

function IsConnectionClass(const ClassRef: string): Boolean;
var X: string;
begin
  for X in CONNECTION_CLASSES do
    if SameText(ClassRef, X) then Exit(True);
  Result := False;
end;

function IsDbComponent(const ClassRef: string): Boolean;
begin
  Result := IsDataSetClass(ClassRef)
         or IsDataSourceClass(ClassRef)
         or IsConnectionClass(ClassRef);
end;

function IsDataModuleRootByName(const ClassRef: string): Boolean;
// RUECKFALL-Heuristik: Klassen-Name endet auf 'DataModule' (eine der
// Delphi-Konventionen fuer TDataModule-Nachfahren). Deckt 'TDataModule',
// 'TMainDataModule', 'TPersonsDataModule' ab - und sonst wenig, siehe
// die Zahlen im Unit-Kopf. Bleibt nur fuer Laeufe ohne aufgeloeste
// Klassenkette; alleinstehend war sie die Ursache von 72 Korpus-FPs.
begin
  Result := EndsText('DataModule', ClassRef);
end;

function IsDataModuleRootByAncestry(ABinding: TFormBinding): Boolean;
// VORRANG-Pruefung: die Klassenkette der zugehoerigen .pas hochlaufen und
// sehen, ob sie in TDataModule endet.
//
// Warum die SPITZE der Kette und nicht die eigene Klasse: der Binder
// stoppt die Aufloesung an den VCL-Wurzeln (TForm/TFrame/TDataModule/...).
// Bei 'TdmMain = class(TDataModule)' ist Parent deshalb nil und der Ahn
// steht direkt in FormClass.TypeRef; bei 'TdmKunden = class(TdmBasis)'
// haengt eine Bindung dazwischen, und erst deren TypeRef nennt
// TDataModule. Dasselbe Muster benutzt IsAncestorChainResolved in
// uDfmDeadEvent.
//
// Mehrdeutige Ahnen (derselbe Klassenname in mehreren Units) werden NICHT
// gesondert behandelt: anders als bei uDfmDeadEvent, wo aus einer
// geratenen Kette ein behaupteter Absturz wurde, kostet ein Fehlgriff hier
// hoechstens einen unterdrueckten Hinweis auf eine fremde, gleichnamigen
// Klasse - und in die sichere Richtung.
var
  Top : TFormBinding;
begin
  Result := False;
  if ABinding = nil then Exit;
  Top := ABinding;
  while Top.Parent <> nil do
    Top := Top.Parent;
  if Top.FormClass = nil then Exit;
  Result := SameText(TDetectorUtils.FirstParentToken(Top.FormClass.TypeRef),
                     'TDataModule');
end;

class procedure TDfmDbInUiFormDetector.Analyze(Graph: TComponentGraph;
  ABinding: TFormBinding; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  All  : TList<TComponentNode>;
  Root : TComponentNode;
  N    : TComponentNode;
  F    : TLeakFinding;
begin
  if Graph = nil then Exit;
  if Graph.Roots.Count = 0 then Exit;

  Root := Graph.Roots[0];
  // Reihenfolge ist Absicht: die Kette schlaegt den Namen. Der Name bleibt
  // als zweite Chance stehen, damit ein Lauf ohne .pas nicht SCHLECHTER
  // wird als vorher.
  if IsDataModuleRootByAncestry(ABinding) then Exit;
  if IsDataModuleRootByName(Root.ClassRef) then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if N = Root then Continue;        // Root selbst nie melden
      if not IsDbComponent(N.ClassRef) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format('%s (%s) lives on %s (%s) - move to a TDataModule',
                              [N.Name, N.ClassRef, Root.Name, Root.ClassRef]);
      F.SetKind(fkDfmDbInUiForm);
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
