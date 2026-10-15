unit uTestRdxFreeTypes;

// Charge FB (Code-Review reDelphix, R2-01/R3-01, missed R2(4)/R3(2); die
// Nachpruefung: Aliasse der Unit und 'type'): der
// Textteil der Typ-Sperre von SCA085/SCA139 - TRdxSimpleFixes.
// DeclaresValueType zaehlt einen Zeigertyp der Unit ('PFoo = ^TFoo') mit:
// 'P.Free' meint das Ziel (Delphi dereferenziert), FreeAndNil(P) naehme den
// Zeiger als TObject. Reine Textlogik - laeuft in reDelphix.Test UND im
// FPC-Pruefstand; gegen den Stand 4358b769 rot (der Zeiger galt als
// unbekannt). Die Sperren im Laeufer (eigene Free, fremder P-Typ,
// const-Parameter) prueft uTestRdxFreeGatesDetector gegen die echten
// Detektoren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFreeTypes = class
  public
    // mORMot-Form: 'PX509_CRL = ^X509_CRL' mit X509_CRL = object.
    [Test] procedure PointerToObject_IsNoObject;
    // Ein Zeiger auf einen fremden Typ, auch auf eine Klasse - Klassen und
    // Aliase bleiben unberuehrt.
    [Test] procedure PointerAlias_IsNoObject_ClassStays;
    // Nachpruefung FB (Pruefer gprobe F9): Aliasse der Unit werden
    // verfolgt, ein eigener Typ ('= type ..') zaehlt mit.
    [Test] procedure UnitAliasAndDistinctType_AreNoObject;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxSimpleFixes;

// Zeilen mit CRLF verbunden (string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then
        SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// DeclaresValueType(ATypeName) in einer Unit mit den Typen ATypes.
function ValueTypeIn(const ATypes: array of string;
  const ATypeName: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ATypes)
      + #13#10 + Join(['implementation', 'end.']);
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxSimpleFixes.DeclaresValueType(Map, ATypeName);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxFreeTypes.PointerToObject_IsNoObject;
const
  TYPES: array[0..4] of string = ('  PX509_CRL = ^X509_CRL;',
    '  X509_CRL = object', '  public', '    procedure Free;', '  end;');
begin
  Assert.IsTrue(ValueTypeIn(TYPES, 'px509_crl'), 'Zeiger auf object');
  Assert.IsTrue(ValueTypeIn(TYPES, 'X509_CRL'), 'das object selbst');
end;

procedure TTestRdxFreeTypes.PointerAlias_IsNoObject_ClassStays;
const
  TYPES: array[0..4] of string = ('  PFoo = ^TFoo;', '  PObj = ^TObj;',
    '  TObj = class', '  end;', '  TAlias = TObj;');
begin
  Assert.IsTrue(ValueTypeIn(TYPES, 'pfoo'), 'Zeiger auf fremden Typ');
  Assert.IsTrue(ValueTypeIn(TYPES, 'PObj'), 'Zeiger auf eine Klasse');
  Assert.IsFalse(ValueTypeIn(TYPES, 'tobj'), 'Klasse');
  Assert.IsFalse(ValueTypeIn(TYPES, 'talias'), 'Alias auf eine Klasse');
  // Eine Variable mit Zeigertyp ist keine Typdeklaration.
  Assert.IsFalse(ValueTypeIn(['  TRec = record', '    P: PFoo;', '  end;'],
    'p'), 'Feld');
end;

procedure TTestRdxFreeTypes.UnitAliasAndDistinctType_AreNoObject;
const
  TYPES: array[0..8] of string = ('  TA = TB;', '  TB = record', '  end;',
    '  PMy = PFoo;', '  PFoo = ^TFoo;', '  PDist = type ^TFoo;',
    '  TOwn = TObj;', '  TObj = class', '  end;');
begin
  // Gegen den ersten Stand der Charge (3d753de6) rot: DeclaresValueType las
  // nur das erste Wort hinter '=' - 'tb', 'pfoo', 'type'.
  Assert.IsTrue(ValueTypeIn(TYPES, 'ta'), 'Alias auf einen Record der Unit');
  Assert.IsTrue(ValueTypeIn(TYPES, 'pmy'), 'Alias auf einen Zeiger der Unit');
  Assert.IsTrue(ValueTypeIn(TYPES, 'pdist'), 'eigener Zeigertyp (type ^)');
  // Gegenproben: ein Alias auf eine Klasse - der Unit oder fremd - bleibt.
  Assert.IsFalse(ValueTypeIn(TYPES, 'town'), 'Alias auf eine Klasse');
  Assert.IsFalse(ValueTypeIn(['  TMyList = TObjectList;'], 'tmylist'),
    'Alias auf einen fremden Typ');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFreeTypes);

end.
