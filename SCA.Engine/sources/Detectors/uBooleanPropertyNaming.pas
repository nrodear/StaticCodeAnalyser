unit uBooleanPropertyNaming;

// Detektor: Boolean-Property ohne aussagekraeftiges Verb-Praefix.
//
// Konvention (Sonar / Delphi-Style-Guide):
//   property IsActive  : Boolean;   // gut
//   property HasItems  : Boolean;   // gut
//   property CanClose  : Boolean;   // gut
//   property ShouldRun : Boolean;   // gut
//   property Visible   : Boolean;   // OK (etabliert, VCL-Convention)
//   property Enabled   : Boolean;   // OK (etabliert)
//   property Active    : Boolean;   // grenzwertig (alias akzeptiert)
//   property Foo       : Boolean;   // SCHLECHT
//
// Erkennung (File-Text-Scan, weil uParser2 nkProperty ohne TypeRef
// emittiert):
//   * Pro Source-Zeile: Regex `\bproperty\s+(\w+)\s*:\s*(\w+)\b`
//     extrahiert Name und Type.
//   * Wenn Type case-insensitive 'Boolean' und Name nicht mit
//     {is, has, can, should} beginnt UND nicht in der ETABLIERTEN
//     Whitelist (Enabled, Visible, Active, Checked, Modified, ...)
//     -> Finding.
//
// FP-Tradeoff:
//   * Multi-Line-Property-Deklarationen (`property Foo:\n  Boolean`)
//     werden nicht erkannt. Selten in der Praxis.
//   * `class property` vs `property` werden identisch behandelt.
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TBooleanPropertyNamingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

const
  PROP_RE = '\bproperty\s+(\w+)\s*:\s*(\w+)\b';

  // Etablierte Boolean-Property-Namen ohne Is/Has-Prefix (VCL-Tradition).
  ESTABLISHED : array[0..12] of string = (
    'enabled', 'visible', 'active', 'checked', 'modified',
    'readonly', 'expanded', 'collapsed', 'selected', 'focused',
    'dirty', 'loaded', 'updated'
  );

  VERB_PREFIXES : array[0..4] of string = (
    'is', 'has', 'can', 'should', 'will'
  );

function StartsWithVerbPrefix(const NameLow: string): Boolean;
var
  P : string;
begin
  Result := False;
  for P in VERB_PREFIXES do
    // 'is' + Folge-Buchstabe muss Upper sein (CamelCase) - sonst matcht
    // 'island', 'issue' etc. Heuristik: NameLow ist immer lower; wir
    // pruefen Original-Name in Aufrufer.
    if NameLow.StartsWith(P) and (Length(NameLow) > Length(P)) then
      Exit(True);
end;

function IsEstablishedName(const NameLow: string): Boolean;
var
  E : string;
begin
  Result := False;
  for E in ESTABLISHED do
    if NameLow = E then Exit(True);
end;

class procedure TBooleanPropertyNamingDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i        : Integer;
  Code     : string;
  State    : TCommentScanState;
  Dummy    : Integer;
  RE       : TRegEx;
  M        : TMatch;
  PName    : string;
  PNameLow : string;
  PType    : string;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    RE := TRegEx.Create(PROP_RE, [roIgnoreCase]);
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      // ScanCodeLine strippt //, {...}, (*...*), ''-Strings -
      // auskommentierte `property Foo: Boolean;` matched dann NICHT.
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Dummy);
      for M in RE.Matches(Code) do
      begin
        PType := LowerCase(M.Groups[2].Value);
        if PType <> 'boolean' then Continue;
        PName    := M.Groups[1].Value;
        PNameLow := LowerCase(PName);

        if IsEstablishedName(PNameLow) then Continue;
        if StartsWithVerbPrefix(PNameLow) then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := 'Boolean property "' + PName + '" should start with ' +
                        'Is / Has / Can / Should (e.g. IsActive, HasItems) - ' +
                        'reads naturally at the call site (if X.IsActive).';
        F.SetKind(fkBooleanPropertyNaming);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
