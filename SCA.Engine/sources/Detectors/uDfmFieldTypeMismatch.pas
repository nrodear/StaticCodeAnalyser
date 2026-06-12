unit uDfmFieldTypeMismatch;

// Detektor: UI-DB-Control-Klasse passt nicht zum TField-Datentyp.
//
// Typische Fehler nach Auto-Generierung mit TFields-Editor und
// nachtraeglichem Daten-Modell-Umbau:
//   * TDBEdit gebunden an TBooleanField (sollte TDBCheckBox sein)
//   * TDBEdit gebunden an TMemoField/TBlobField (sollte TDBMemo sein)
//   * TDBEdit gebunden an TDateField (sollte TDBDateTimePicker sein)
//   * TDBCheckBox gebunden an TIntegerField (eigentlich falsch herum)
//
// Mapping (konservativ - bei fcUnknown wird nichts gemeldet):
//
//   Field-Kategorie          erlaubte Controls
//   fcBoolean              { TDBCheckBox }
//   fcMemo, fcBlob         { TDBMemo, TDBRichEdit, TDBImage }
//   fcDate, fcDateTime,
//   fcTime                 { TDBDateTimePicker, TDBEdit (mit
//                            Designer-Format-String akzeptiert) }
//   fcInteger, fcFloat,
//   fcString               { TDBEdit, TDBNumberEdit, TDBComboBox,
//                            TDBLookupComboBox, TDBText }
//
// Phase 1 dieses Detektors meldet nur die zwei klaren Smell-Klassen:
//   * Boolean-Feld an Non-Checkbox
//   * Memo/Blob-Feld an Plain-Edit
// Die Date-Heuristik ist zu false-positive-anfaellig (legitime Format-
// Strings) und wird in Phase 2 nachgeschoben.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uComponentGraph, uDfmDbFieldAnalysis;

type
  TDfmFieldTypeMismatchDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, NestedTry, TooLongLine, UnsortedUses, UnusedRoutine
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsBooleanFieldOk(Ctrl: TComponentNode): Boolean;
begin
  Result := SameText(Ctrl.ClassRef, 'TDBCheckBox');
end;

function IsMemoBlobOk(Ctrl: TComponentNode): Boolean;
begin
  Result := SameText(Ctrl.ClassRef, 'TDBMemo')
         or SameText(Ctrl.ClassRef, 'TDBRichEdit')
         or SameText(Ctrl.ClassRef, 'TDBImage');
end;

function FieldName(Field: TComponentNode): string;
var V: TPropValue;
begin
  Result := '';
  if Field.TryGetProperty('FieldName', V) and (V.Kind = pvkString) then
    Result := Trim(V.RawValue);
  if Result = '' then
    Result := Field.Name;
end;

function FindDataSourceForDataSet(All: TList<TComponentNode>;
  DataSet: TComponentNode): TComponentNode;
var
  N: TComponentNode;
  V: TPropValue;
begin
  Result := nil;
  for N in All do
    if IsDataSourceClass(N.ClassRef)
       and N.TryGetProperty('DataSet', V)
       and (V.Kind = pvkIdent)
       and SameText(Trim(V.RawValue), DataSet.Name) then
      Exit(N);
end;

class procedure TDfmFieldTypeMismatchDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(Ctrl: TComponentNode; const Why: string);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Ctrl.Line);
    F.MissingVar := Why;
    F.SetKind(fkDfmFieldTypeMismatch);
    Results.Add(F);
  end;

var
  All      : TList<TComponentNode>;
  Bindings : TBindingIndex;
  DataSet  : TComponentNode;
  Field    : TComponentNode;
  DS       : TComponentNode;
  Bucket   : TList<TComponentNode>;
  Ctrl     : TComponentNode;
  Category : TFieldCategory;
  I, J     : Integer;
  Key      : string;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    Bindings := BuildBindingIndex(All);
    try
      for I := 0 to All.Count - 1 do
      begin
        DataSet := All[I];
        if not IsDataSetClass(DataSet.ClassRef) then Continue;

        DS := FindDataSourceForDataSet(All, DataSet);
        if DS = nil then Continue;

        for J := 0 to DataSet.Children.Count - 1 do
        begin
          Field := DataSet.Children[J];
          if not IsFieldClass(Field.ClassRef) then Continue;

          Category := ClassifyFieldType(Field.ClassRef);
          if Category = fcUnknown then Continue;

          Key := BindingKey(DS.Name, FieldName(Field));
          if not Bindings.TryGetValue(Key, Bucket) then Continue;

          for Ctrl in Bucket do
          begin
            case Category of
              fcBoolean:
                if not IsBooleanFieldOk(Ctrl) then
                  AddFinding(Ctrl,
                    Format('%s (%s) is bound to %s.%s (TBooleanField) - use TDBCheckBox',
                      [Ctrl.Name, Ctrl.ClassRef, DataSet.Name, FieldName(Field)]));

              fcMemo, fcBlob:
                // Plain TDBEdit/TDBText auf Memo/Blob -> Smell. Andere
                // db-aware Controls (z.B. TDBComboBox) sind hier konservativ
                // toleriert (Phase 2 kann verengen).
                if SameText(Ctrl.ClassRef, 'TDBEdit')
                   or SameText(Ctrl.ClassRef, 'TDBText') then
                  AddFinding(Ctrl,
                    Format('%s (%s) is bound to %s.%s (%s) - use TDBMemo/TDBRichEdit/TDBImage',
                      [Ctrl.Name, Ctrl.ClassRef, DataSet.Name, FieldName(Field),
                       Field.ClassRef]));
            else
              // fcInteger/fcFloat/fcString/fcDate/...: Phase 1 schweigt
              // (zu viele legitime Konstellationen).
            end;
          end;
        end;
      end;
    finally
      Bindings.Free;
    end;
  finally
    All.Free;
  end;
end;

end.
