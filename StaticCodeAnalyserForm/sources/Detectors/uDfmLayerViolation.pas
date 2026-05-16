unit uDfmLayerViolation;

// Detektor: Eingabe-Control liegt direkt auf einer TForm statt eingebettet
// in einem TPanel / TGroupBox / TPageControl.
//
// Anti-Pattern: eine Form mit btnSave, edName, edEmail, ... als direkte
// Children ist nicht wiederverwendbar und schwer umzulayouten. Sobald die
// Form auch nur ein bisschen waechst, wird das ein unstrukturierter Haufen.
// Best Practice: logische Bloecke in Container-Komponenten gruppieren.
//
// Heuristik:
//   * Root ist eine Form/Frame (Suffix 'Form'/'Frame', kein 'DataModule').
//   * Direkte Children der Root sind in einer Input-Control-Whitelist
//     (TEdit, TMemo, TComboBox, TButton, ...).
//   * Action/Image/Menu-Listen sind Container-frei OK (TActionList,
//     TImageList, TMainMenu, TPopupMenu, TTimer, ...).
//
// Phase-1-Vereinfachung: Whitelist konservativ - lieber wenig False
// Positives als penibel jede direkt platzierte Komponente melden.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmLayerViolationDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils;

const
  // Input-Controls, die im Designer typisch in einem Panel landen sollten.
  // Konservativ gewaehlt - zu breite Whitelist liefert False Positives bei
  // typischen Mini-Forms (Login-Dialog mit zwei Edits + zwei Buttons).
  INPUT_CONTROLS: array[0..7] of string = (
    'TEdit', 'TLabeledEdit', 'TMemo', 'TRichEdit',
    'TComboBox', 'TListBox', 'TCheckListBox', 'TValueListEditor'
  );

  DB_INPUTS: array[0..5] of string = (
    'TDBEdit', 'TDBMemo', 'TDBComboBox', 'TDBRichEdit',
    'TDBLookupComboBox', 'TDBGrid'
  );

function IsInputControl(const ClassRef: string): Boolean;
var X: string;
begin
  for X in INPUT_CONTROLS do if SameText(ClassRef, X) then Exit(True);
  for X in DB_INPUTS       do if SameText(ClassRef, X) then Exit(True);
  Result := False;
end;

function IsFormOrFrame(const ClassRef: string): Boolean;
begin
  // Klassen-Suffix-Heuristik (Phase-1-konsistent mit uDfmDbInUiForm):
  // 'TMainForm', 'TOrderFrame'. DataModule explizit ausgenommen.
  if EndsText('DataModule', ClassRef) then Exit(False);
  Result := EndsText('Form', ClassRef) or EndsText('Frame', ClassRef);
end;

class procedure TDfmLayerViolationDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Root  : TComponentNode;
  Child : TComponentNode;
  F     : TLeakFinding;
  I     : Integer;
begin
  if Graph = nil then Exit;
  if Graph.Roots.Count = 0 then Exit;

  Root := Graph.Roots[0];
  if not IsFormOrFrame(Root.ClassRef) then Exit;

  for I := 0 to Root.Children.Count - 1 do
  begin
    Child := Root.Children[I];
    if not IsInputControl(Child.ClassRef) then Continue;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Child.Line);
    F.MissingVar := Format('%s (%s) sits directly on %s - wrap inputs in a TPanel/TGroupBox',
                            [Child.Name, Child.ClassRef, Root.Name]);
    F.SetKind(fkDfmLayerViolation);
    Results.Add(F);
  end;
end;

end.
