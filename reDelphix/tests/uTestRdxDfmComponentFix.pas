unit uTestRdxDfmComponentFix;

// SCA184 DfmComponentUnused (uRdxDfmComponentFix) auf Text - ohne Parser,
// ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand). Die
// Meldung selbst traegt den Komponentennamen (uDfmComponentUnused.Analyze,
// F.MissingVar) - der Fix liest ihn daraus und prueft ihn gegen die
// Fund-Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDfmComponentFix = class
  public
    [Test] procedure LeafComponent_DeletesWholeBlock;
    [Test] procedure MultipleSiblings_OnlyTheReportedOneGoes;
    [Test] procedure ComponentWithChild_Refused;
    [Test] procedure ItemListProperty_NotCountedAsChild_Deletes;
    [Test] procedure Refusals;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxDfmComponentFix,
  uTestRdxTextKit;   // Join, Apply

function Msg(const AName, AClassRef: string): string;
begin
  Result := Format('DFM component %s (%s) is never referenced in code, '
    + 'other units or the DFM (possibly leftover after refactoring)',
    [AName, AClassRef]);
end;

// Die Hilfe fuer die Fund-Zeile ALine: neuer Text oder '' bei Ablehnung.
function Fix184(const ASource: string; ALine: Integer;
  const AName, AClassRef: string; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxDfmComponentFix.DeleteUnusedComponent(Map, ALine,
         Msg(AName, AClassRef), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxDfmComponentFix.LeafComponent_DeletesWholeBlock;
var
  R : string;
begin
  Assert.AreEqual(Join(['object Form1: TForm1', 'end']),
    Fix184(Join(['object Form1: TForm1', '  object btnOld: TButton',
      '    Left = 8', '    Caption = ''Old''', '  end', 'end']),
      2, 'btnOld', 'TButton', R), R);
end;

procedure TTestRdxDfmComponentFix.MultipleSiblings_OnlyTheReportedOneGoes;
var
  R : string;
begin
  // Drei Geschwister, nur das mittlere (btnOld) ist der Fund - die anderen
  // beiden muessen byte-identisch stehen bleiben.
  Assert.AreEqual(Join(['object Form1: TForm1',
      '  object Edit1: TEdit', '    Left = 8', '  end',
      '  object Button2: TButton', '    Left = 100', '  end', 'end']),
    Fix184(Join(['object Form1: TForm1',
      '  object Edit1: TEdit', '    Left = 8', '  end',
      '  object btnOld: TButton', '    Left = 50', '  end',
      '  object Button2: TButton', '    Left = 100', '  end', 'end']),
      5, 'btnOld', 'TButton', R), R);
end;

procedure TTestRdxDfmComponentFix.ComponentWithChild_Refused;
var
  R : string;
begin
  // Panel1 ist selbst unbenutzt, enthaelt aber btnInside - eine Loeschung
  // wuerde das Kind mitreissen. Gesperrt, egal ob das Kind selbst benutzt
  // ist oder nicht (die Hilfe kennt nur den Text, nicht den Code-Bezug).
  Assert.AreEqual('', Fix184(Join(['object Form1: TForm1',
    '  object Panel1: TPanel', '    object btnInside: TButton',
    '      Left = 8', '    end', '  end', 'end']),
    2, 'Panel1', 'TPanel', R));
  Assert.AreNotEqual('', R);
end;

procedure TTestRdxDfmComponentFix.ItemListProperty_NotCountedAsChild_Deletes;
var
  R : string;
begin
  // ListView1 traegt eine Collection-Item-Liste (Columns = <item .. end
  // item .. end>) - das sind Property-WERTE (pvkItemList), keine
  // TComponentNode-Kinder. Die Hilfe darf trotzdem loeschen.
  Assert.AreEqual(Join(['object Form1: TForm1', 'end']),
    Fix184(Join(['object Form1: TForm1',
      '  object ListView1: TListView',
      '    Columns = <',
      '      item',
      '        Caption = ''Name''',
      '      end',
      '      item',
      '        Caption = ''Value''',
      '      end>',
      '  end', 'end']),
      2, 'ListView1', 'TListView', R), R);
end;

procedure TTestRdxDfmComponentFix.Refusals;
var
  R : string;
begin
  // ALine ist keine object/inherited/inline-Zeile mehr (Fund veraltet).
  Assert.AreEqual('', Fix184(Join(['object Form1: TForm1',
    '  object btnOld: TButton', '  end', 'end']), 3, 'btnOld', 'TButton', R));
  Assert.AreNotEqual('', R);
  // Name passt nicht mehr zur Fund-Zeile (verschoben/umbenannt).
  Assert.AreEqual('', Fix184(Join(['object Form1: TForm1',
    '  object btnNew: TButton', '  end', 'end']), 2, 'btnOld', 'TButton', R));
  Assert.AreNotEqual('', R);
  // Kein zugehoeriges 'end' - Start ohne Ende.
  Assert.AreEqual('', Fix184(Join(['object Form1: TForm1',
    '  object btnOld: TButton']), 2, 'btnOld', 'TButton', R));
  Assert.AreNotEqual('', R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDfmComponentFix);

end.
