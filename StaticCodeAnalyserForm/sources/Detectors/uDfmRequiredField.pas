unit uDfmRequiredField;

// Detektoren fuer Pflichtfeld-Probleme im DFM (Phase 3).
//
// Datengrundlage:
//   * TField-Subkomponenten unter einer TDataSet-Komponente
//     (TIntegerField, TStringField, ...) mit FieldName-Property und
//     optionaler Required-Property.
//   * UI-Bindungen (DataSource + DataField) auf DB-aware Controls.
//
// Zwei Detektoren (gepaart, weil Daten-Sammlung identisch):
//
//   fkDfmRequiredFieldUnbound        (lsWarning, ftBug)
//     Required=True, KEINE UI-Komponente bindet (DataSource->DataSet,
//     DataField). User kann das Feld ueberhaupt nicht eingeben - Post
//     scheitert.
//
//   fkDfmRequiredFieldNotVisible     (lsWarning, ftBug)
//     Required=True, ALLE bindenden UI-Komponenten haben Visible=False.
//     Pflichtfeld ist eingebbar, aber dem User nicht sichtbar.
//
// Phase-1-Vereinfachung: Visible wird nur auf der Komponente selbst
// geprueft, nicht ueber Parent-Hierarchie (Tab-Sheet collapse,
// versteckter Panel etc.). Das deckt den Hauptfall ab; Parent-
// Sichtbarkeit kommt in Phase 2 dieses Detektors.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uComponentGraph, uDfmDbFieldAnalysis;

type
  TDfmRequiredFieldDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

function IsRequired(Field: TComponentNode): Boolean;
var V: TPropValue;
begin
  Result := Field.TryGetProperty('Required', V)
        and (V.Kind = pvkBool)
        and SameText(V.RawValue, 'True');
end;

function IsExplicitlyInvisible(Ctrl: TComponentNode): Boolean;
// Visible-Default in der VCL ist True - der DFM-Streamer speichert nur,
// wenn der Default verlassen wird. 'Visible = False' ist also explizit.
var V: TPropValue;
begin
  Result := Ctrl.TryGetProperty('Visible', V)
        and (V.Kind = pvkBool)
        and SameText(V.RawValue, 'False');
end;

function FieldName(Field: TComponentNode): string;
var V: TPropValue;
begin
  Result := '';
  if Field.TryGetProperty('FieldName', V) and (V.Kind = pvkString) then
    Result := Trim(V.RawValue);
  if Result = '' then
    Result := Field.Name;       // Fallback: Komponentenname als Field-Hint
end;

function FindDataSourceForDataSet(All: TList<TComponentNode>;
  DataSet: TComponentNode): TComponentNode;
// DataSet -> DataSource: irgendeine TDataSource-Komponente, deren
// DataSet-Property auf den DataSet zeigt. Es kann mehrere geben; wir
// nehmen die erste, die wir finden (typisch ist 1:1 - eine DataSource
// pro DataSet).
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

class procedure TDfmRequiredFieldDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(Field: TComponentNode; const Why: string;
    Kind: TFindingKind);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Field.Line);
    F.MissingVar := Why;
    F.Severity   := lsWarning;
    F.Kind       := Kind;
    Results.Add(F);
  end;

var
  All       : TList<TComponentNode>;
  Bindings  : TBindingIndex;
  DataSet   : TComponentNode;
  Field     : TComponentNode;
  DS        : TComponentNode;
  Bucket    : TList<TComponentNode>;
  Ctrl      : TComponentNode;
  Key       : string;
  I, J      : Integer;
  AllInvis  : Boolean;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    Bindings := BuildBindingIndex(All);
    try
      // Pro DataSet-Komponente die TField-Children durchgehen.
      for I := 0 to All.Count - 1 do
      begin
        DataSet := All[I];
        if not IsDataSetClass(DataSet.ClassRef) then Continue;

        DS := FindDataSourceForDataSet(All, DataSet);
        // Ohne DataSource kann KEINE UI-Komponente das DataSet erreichen.
        // Wir behandeln das im Bindings-Lookup transparent: ohne DS gibt es
        // keinen Bucket - das fuehrt automatisch zu "unbound".

        for J := 0 to DataSet.Children.Count - 1 do
        begin
          Field := DataSet.Children[J];
          if not IsFieldClass(Field.ClassRef) then Continue;
          if not IsRequired(Field)            then Continue;

          if DS = nil then
          begin
            AddFinding(Field,
              Format('%s (%s.%s) is Required=True but the dataset has no '
                  + 'TDataSource - field is unreachable from any control',
                  [FieldName(Field), DataSet.Name, FieldName(Field)]),
              fkDfmRequiredFieldUnbound);
            Continue;
          end;

          Key := BindingKey(DS.Name, FieldName(Field));
          if not Bindings.TryGetValue(Key, Bucket) or (Bucket.Count = 0) then
          begin
            AddFinding(Field,
              Format('%s.%s is Required=True but no DB-control binds it '
                  + '(DataSource=%s)',
                  [DataSet.Name, FieldName(Field), DS.Name]),
              fkDfmRequiredFieldUnbound);
            Continue;
          end;

          // Wenn ALLE bindenden Controls explizit unsichtbar sind - Befund.
          AllInvis := True;
          for Ctrl in Bucket do
            if not IsExplicitlyInvisible(Ctrl) then
            begin
              AllInvis := False; Break;
            end;
          if AllInvis then
            AddFinding(Field,
              Format('%s.%s is Required=True but every binding control '
                  + 'has Visible=False - user cannot reach it',
                  [DataSet.Name, FieldName(Field)]),
              fkDfmRequiredFieldNotVisible);
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
