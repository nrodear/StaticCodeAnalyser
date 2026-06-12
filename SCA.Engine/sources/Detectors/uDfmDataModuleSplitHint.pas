unit uDfmDataModuleSplitHint;

// Detektor: aggregiert mehrere fkDfmDbInUiForm-Befunde auf derselben Form
// zu einem einzigen "extract to data module"-Refactor-Hint, sobald die
// Anzahl ueber DetectorMaxDbInUiFormHint (Default 3) liegt.
//
// Warum aggregieren:
//   Eine Form mit 12 DB-Komponenten erzeugt aktuell 12 fkDfmDbInUiForm-
//   Findings im Grid - laut + repetitiv, der User scrollt drueber hinweg.
//   Ein aggregierter Hint mit Count + Liste der Komponenten ist besser
//   actionable: "Form X enthaelt 12 DB-Komponenten - extrahier in
//   TXxxDataModule".
//
// Heuristik:
//   * Wir gucken NICHT noch einmal in den Graph - stattdessen zaehlen wir
//     fkDfmDbInUiForm-Findings, die bereits in der Results-Liste sind,
//     pro DFM-Datei. Sobald N >= DetectorMaxDbInUiFormHint, emittieren wir
//     EINEN zusaetzlichen Aggregat-Hint (die einzelnen Findings bleiben
//     bestehen - der Aggregat-Hint ist zusaetzliche UX, kein Ersatz).
//
//   Reihenfolge in uDfmAnalysisRunner ist entscheidend: dieser Detektor
//   muss NACH TDfmDbInUiFormDetector laufen.
//
// Severity: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TDfmDataModuleSplitHintDetector = class
  public
    // Konsumiert die schon-gesammelte Results-Liste, sucht nach
    // fkDfmDbInUiForm-Findings im gleichen FileName und emittiert bei
    // Schwellwert-Ueberschreitung einen Aggregat-Hint.
    class procedure Aggregate(const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TDfmDataModuleSplitHintDetector.Aggregate(const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  i, Count : Integer;
  Threshold : Integer;
  Names : TStringList;
  F : TLeakFinding;
  DisplayList : string;
  ExtractName : string;
begin
  if Results = nil then Exit;
  Threshold := DetectorMaxDbInUiFormHint;
  if Threshold < 1 then Threshold := 3;

  // Zaehle Findings mit Kind=fkDfmDbInUiForm fuer DIESE Datei.
  // Komponenten-Namen werden aus MissingVar extrahiert (Format ist
  // '<Name> (<Class>) lives on <Root> ...' - wir nehmen alles vor ' ').
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    Count := 0;
    for i := 0 to Results.Count - 1 do
    begin
      F := Results[i];
      if F.Kind <> fkDfmDbInUiForm then Continue;
      if not SameText(F.FileName, FileName) then Continue;
      Inc(Count);
      var SpacePos := Pos(' ', F.MissingVar);
      if SpacePos > 1 then
        Names.Add(Copy(F.MissingVar, 1, SpacePos - 1));
    end;
    if Count < Threshold then Exit;

    // Display-Liste: max 5 Namen, dann "..." wenn mehr.
    if Names.Count > 5 then
    begin
      DisplayList := '';
      for i := 0 to 4 do
      begin
        if i > 0 then DisplayList := DisplayList + ', ';
        DisplayList := DisplayList + Names[i];
      end;
      DisplayList := DisplayList + Format(', ... (+%d more)',
        [Names.Count - 5]);
    end
    else
      DisplayList := Names.CommaText;

    // Refactor-Name vorschlagen aus dem File-Basename. Wenn Datei
    // 'uMainForm.dfm' heisst -> 'TMainFormDataModule' als Default-Vorschlag.
    ExtractName := ExtractFileName(FileName);
    if EndsText('.dfm', ExtractName) then
      ExtractName := Copy(ExtractName, 1, Length(ExtractName) - 4);
    if StartsText('u', ExtractName) and (Length(ExtractName) > 1) then
      ExtractName := Copy(ExtractName, 2, MaxInt);
    if ExtractName = '' then ExtractName := 'Db';

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := '1';
    F.MissingVar := Format(
      '%d DB components on this form (%s) - extract them into a TDataModule '
      + '(e.g., T%sDataModule). Aggregate hint, single instances reported separately.',
      [Count, DisplayList, ExtractName]);
    F.SetKind(fkDfmDataModuleSplitHint);
    Results.Add(F);
  finally
    Names.Free;
  end;
end;

end.
