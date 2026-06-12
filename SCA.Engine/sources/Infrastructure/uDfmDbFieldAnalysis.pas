unit uDfmDbFieldAnalysis;

// Gemeinsamer Helper fuer die DB-Field-aware Detektoren (Phase 3):
//   * fkDfmRequiredFieldUnbound
//   * fkDfmRequiredFieldNotVisible
//   * fkDfmFieldTypeMismatch
//
// Funktionen:
//   * Klassen-Klassifizierung: TDataSet, TField, TDataSource, DB-Aware-Control
//   * Field-Kategorie (Boolean / Numeric / String / Memo / Date / ...)
//   * BuildBindingIndex: alle UI-Controls indexieren ueber
//       (LowerCase(DataSourceName), LowerCase(DataField)) -> Liste der Controls
//   * ResolveDataSetForDataSource: zur DataSource-Komponente die DataSet-
//     Komponente liefern (DataSet-Property mit pvkIdent-Wert auf einen
//     Knoten im Graph).

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uComponentGraph;

type
  // Logische Field-Kategorie. Zwischen TField-Subklassen-Namen und
  // erlaubten UI-Klassen vermitteln wir ueber diese Enum-Werte.
  TFieldCategory = (
    fcUnknown,
    fcBoolean,
    fcInteger,
    fcFloat,
    fcString,
    fcMemo,
    fcBlob,
    fcDate,
    fcTime,
    fcDateTime
  );

  TBindingIndex = TObjectDictionary<string, TList<TComponentNode>>;

function IsDataSetClass(const ClassRef: string): Boolean;
function IsFieldClass(const ClassRef: string): Boolean;
function IsDataSourceClass(const ClassRef: string): Boolean;
function IsDbAwareControlClass(const ClassRef: string): Boolean;

function ClassifyFieldType(const ClassRef: string): TFieldCategory;

function BindingKey(const DataSourceName, DataFieldName: string): string;
function BuildBindingIndex(All: TList<TComponentNode>): TBindingIndex;

function ResolveDataSetForDataSource(All: TList<TComponentNode>;
  const DataSourceName: string): TComponentNode;

implementation

// noinspection-file ConcatToFormat, MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Whitelist-Approach: wenn die Klasse mit einem dieser Strings beginnt,
  // gilt sie als DataSet. Pragma genuegt fuer die gaengigen TDataSet-
  // Nachfahren (TADOQuery/TADOTable/TADODataSet/TADOStoredProc/...).
  DATASET_CLASSES: array[0..15] of string = (
    'TADOQuery', 'TADOCommand', 'TADOStoredProc', 'TADOTable', 'TADODataSet',
    'TFDQuery', 'TFDCommand', 'TFDStoredProc', 'TFDTable', 'TFDMemTable',
    'TIBQuery', 'TIBStoredProc', 'TIBTable',
    'TClientDataSet', 'TSQLQuery', 'TSQLDataSet'
  );

  DATASOURCE_CLASSES: array[0..0] of string = ('TDataSource');

  // TField-Subklassen die im DFM als Sub-Object einer DataSet-Komponente
  // auftauchen. Reihenfolge: konkrete Klassen, dann Spezial-Typen.
  FIELD_CLASSES: array[0..16] of string = (
    'TBooleanField',
    'TIntegerField', 'TSmallintField', 'TLargeintField', 'TWordField',
    'TShortintField', 'TByteField',
    'TFloatField', 'TBCDField', 'TFMTBCDField', 'TCurrencyField',
    'TStringField', 'TWideStringField', 'TGuidField',
    'TMemoField', 'TWideMemoField',
    'TBlobField'                         // TGraphicField etc. auch -> nachher
  );

  // Catch-all Erkennung: jede Klasse, die mit 'T' beginnt und mit 'Field'
  // endet, behandeln wir auch als TField - das deckt TGraphicField,
  // TBytesField, ftVarBytes, Drittanbieter ab.
  // (siehe IsFieldClass-Implementierung.)

  // DB-aware UI-Controls. Auch hier konservative Whitelist; weitere koennen
  // ueber die Heuristik 'Has DataSource + DataField property' nachgeschoben
  // werden (siehe BuildBindingIndex).
  DBAWARE_CONTROLS: array[0..9] of string = (
    'TDBEdit', 'TDBMemo', 'TDBRichEdit', 'TDBText',
    'TDBCheckBox', 'TDBComboBox', 'TDBLookupComboBox',
    'TDBImage', 'TDBDateTimePicker', 'TDBNumberEdit'
  );

function InList(const S: string; const Arr: array of string): Boolean;
var X: string;
begin
  for X in Arr do
    if SameText(S, X) then Exit(True);
  Result := False;
end;

function IsDataSetClass(const ClassRef: string): Boolean;
begin
  Result := InList(ClassRef, DATASET_CLASSES);
end;

function IsFieldClass(const ClassRef: string): Boolean;
begin
  if InList(ClassRef, FIELD_CLASSES) then Exit(True);
  // Catch-all: 'T...Field'-Suffix (TGraphicField, TBytesField, ...)
  Result := (Length(ClassRef) > 6)
        and (ClassRef[1] = 'T')
        and EndsText('Field', ClassRef);
end;

function IsDataSourceClass(const ClassRef: string): Boolean;
begin
  Result := InList(ClassRef, DATASOURCE_CLASSES);
end;

function IsDbAwareControlClass(const ClassRef: string): Boolean;
begin
  Result := InList(ClassRef, DBAWARE_CONTROLS);
end;

function ClassifyFieldType(const ClassRef: string): TFieldCategory;
// Klassen-Name -> logische Kategorie. Bei unbekannten Field-Klassen
// fcUnknown - der Detektor sollte dann zurueckhaltend reagieren.
begin
  if SameText(ClassRef, 'TBooleanField') then Exit(fcBoolean);

  if SameText(ClassRef, 'TIntegerField')   or SameText(ClassRef, 'TSmallintField') or
     SameText(ClassRef, 'TLargeintField')  or SameText(ClassRef, 'TWordField')     or
     SameText(ClassRef, 'TShortintField')  or SameText(ClassRef, 'TByteField') then
    Exit(fcInteger);

  if SameText(ClassRef, 'TFloatField')     or SameText(ClassRef, 'TBCDField') or
     SameText(ClassRef, 'TFMTBCDField')    or SameText(ClassRef, 'TCurrencyField') then
    Exit(fcFloat);

  if SameText(ClassRef, 'TStringField')     or SameText(ClassRef, 'TWideStringField') or
     SameText(ClassRef, 'TGuidField') then Exit(fcString);

  if SameText(ClassRef, 'TMemoField')       or SameText(ClassRef, 'TWideMemoField') then
    Exit(fcMemo);

  if SameText(ClassRef, 'TBlobField')       or SameText(ClassRef, 'TGraphicField') or
     SameText(ClassRef, 'TBytesField') then Exit(fcBlob);

  if SameText(ClassRef, 'TDateField')  then Exit(fcDate);
  if SameText(ClassRef, 'TTimeField')  then Exit(fcTime);
  if SameText(ClassRef, 'TDateTimeField') or SameText(ClassRef, 'TSQLTimeStampField') then
    Exit(fcDateTime);

  Result := fcUnknown;
end;

function BindingKey(const DataSourceName, DataFieldName: string): string;
begin
  Result := LowerCase(DataSourceName) + #1 + LowerCase(DataFieldName);
end;

function BuildBindingIndex(All: TList<TComponentNode>): TBindingIndex;
// Indexiert alle Komponenten, die DataSource UND DataField setzen
// (typische DB-Aware-Controls). Liefert pro Schluessel eine Liste der
// gebundenen Controls. Aufrufer hat Ownership (.Free), die inner Lists
// werden bei doOwnsValues mit freigegeben.
//
// DataSource ist ein Identifier (Komponenten-Name), DataField ein
// String. Die typisierten Accessors GetIdent / GetString filtern
// gleich Falsch-Typ-Werte und Whitespace weg.
var
  N      : TComponentNode;
  DsName : string;
  DfName : string;
  Key    : string;
  Bucket : TList<TComponentNode>;
begin
  Result := TBindingIndex.Create([doOwnsValues]);
  for N in All do
  begin
    DsName := N.GetIdent('DataSource', '');
    if DsName = '' then Continue;
    DfName := Trim(N.GetString('DataField', ''));
    if DfName = '' then Continue;

    Key := BindingKey(DsName, DfName);
    if not Result.TryGetValue(Key, Bucket) then
    begin
      Bucket := TList<TComponentNode>.Create;
      Result.Add(Key, Bucket);
    end;
    Bucket.Add(N);
  end;
end;

function ResolveDataSetForDataSource(All: TList<TComponentNode>;
  const DataSourceName: string): TComponentNode;
// Zur Komponente <DataSourceName>: deren DataSet-Property zeigt auf eine
// andere Komponente im selben Graph. Liefert die DataSet-Komponente,
// oder nil wenn die DataSource fehlt, kein DataSet hat, oder das DataSet
// nicht aufloesbar ist.
var
  N, Hit : TComponentNode;
  Target : string;
begin
  Result := nil;
  if Trim(DataSourceName) = '' then Exit;

  Hit := nil;
  for N in All do
    if SameText(N.Name, DataSourceName) then
    begin
      Hit := N;
      Break;
    end;
  if Hit = nil then Exit;
  Target := Hit.GetIdent('DataSet', '');
  if Target = '' then Exit;

  for N in All do
    if SameText(N.Name, Target) then Exit(N);
end;

end.
