unit uTestRdxDfmDeadEventFix;

// SCA028 DfmDeadEvent (uRdxDfmDeadEventFix) auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand). Die Meldung
// selbst traegt Event und Handler (uDfmDeadEvent.TDfmDeadEventDetector.
// Analyze, F.MissingVar) - der Fix liest sie daraus und prueft sie gegen
// die Fund-Zeile, bevor er genau diese eine Zeile loescht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDfmDeadEventFix = class
  public
    [Test] procedure DeadEvent_DeletesTheOneLine;
    [Test] procedure OtherLinesUntouched;
    [Test] procedure Refusals;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxDfmDeadEventFix,
  uTestRdxTextKit;   // Join, Apply

function Msg(const AComponent, AEvent, AHandler, AFormClass: string): string;
begin
  Result := Format('%s.%s = %s (handler missing in %s)',
    [AComponent, AEvent, AHandler, AFormClass]);
end;

// Die Hilfe fuer die Fund-Zeile ALine: neuer Text oder '' bei Ablehnung.
function Fix028(const ASource: string; ALine: Integer;
  const AComponent, AEvent, AHandler, AFormClass: string;
  out AReason: string): string;
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
    if TRdxDfmDeadEventFix.DeleteDeadEvent(Map, ALine,
         Msg(AComponent, AEvent, AHandler, AFormClass), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxDfmDeadEventFix.DeadEvent_DeletesTheOneLine;
var
  R : string;
begin
  Assert.AreEqual(Join(['object Form1: TForm1',
      '  object btnGo: TButton', '    Left = 8', '  end', 'end']),
    Fix028(Join(['object Form1: TForm1',
      '  object btnGo: TButton', '    Left = 8',
      '    OnClick = btnGoClick', '  end', 'end']),
      4, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R), R);
end;

procedure TTestRdxDfmDeadEventFix.OtherLinesUntouched;
var
  R : string;
begin
  // Zwei Event-Bindungen auf verschiedenen Komponenten - nur die gemeldete
  // (OnClick auf btnGo) geht, OnClick auf btnOther bleibt stehen.
  Assert.AreEqual(Join(['object Form1: TForm1',
      '  object btnGo: TButton', '  end',
      '  object btnOther: TButton', '    OnClick = btnOtherClick', '  end',
      'end']),
    Fix028(Join(['object Form1: TForm1',
      '  object btnGo: TButton', '    OnClick = btnGoClick', '  end',
      '  object btnOther: TButton', '    OnClick = btnOtherClick', '  end',
      'end']),
      3, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R), R);
end;

procedure TTestRdxDfmDeadEventFix.Refusals;
var
  R : string;
begin
  // Zeile ausser Bereich.
  Assert.AreEqual('', Fix028(Join(['object Form1: TForm1', 'end']),
    5, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R));
  Assert.AreNotEqual('', R);
  // Zeile traegt keine '=' mehr (verschoben/schon geaendert).
  Assert.AreEqual('', Fix028(Join(['object Form1: TForm1',
    '  object btnGo: TButton', '    Left = 8', '  end', 'end']),
    3, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R));
  Assert.AreNotEqual('', R);
  // Zeile bindet ein anderes Event/Handler-Paar als gemeldet.
  Assert.AreEqual('', Fix028(Join(['object Form1: TForm1',
    '  object btnGo: TButton', '    OnEnter = btnGoEnter', '  end', 'end']),
    3, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R));
  Assert.AreNotEqual('', R);
  // Handler hat sich geaendert (Umbenennung) - Zeile bindet noch, aber auf
  // einen anderen Namen als gemeldet.
  Assert.AreEqual('', Fix028(Join(['object Form1: TForm1',
    '  object btnGo: TButton', '    OnClick = btnGoClickNew', '  end', 'end']),
    3, 'btnGo', 'OnClick', 'btnGoClick', 'TForm1', R));
  Assert.AreNotEqual('', R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDfmDeadEventFix);

end.
