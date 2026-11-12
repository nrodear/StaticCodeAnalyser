unit uTestRdxDfmTabOrderFix;

// SCA037 DfmTabOrderConflict (uRdxDfmTabOrderFix) auf Text - ohne Parser,
// ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand). Die
// Meldung selbst wertet die Hilfe nicht aus (reine Positions-/Struktur-
// pruefung ab der Fund-Zeile) - ein Platzhaltertext reicht in jedem Fall.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDfmTabOrderFix = class
  public
    [Test] procedure TwoSiblings_GetsNextFreeValue;
    [Test] procedure ThreeSiblings_SkipsBothUsedValues;
    [Test] procedure NestedGrandchild_NotCountedAsSibling;
    [Test] procedure Refusals;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxDfmTabOrderFix,
  uTestRdxTextKit;   // Join, Apply

// Die Hilfe fuer die Fund-Zeile ALine: neuer Text oder '' bei Ablehnung.
function Fix037(const ASource: string; ALine: Integer;
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
    if TRdxDfmTabOrderFix.FixTabOrder(Map, ALine, '', E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxDfmTabOrderFix.TwoSiblings_GetsNextFreeValue;
var
  R : string;
begin
  // Beide Geschwister teilen TabOrder=0 - der Fund (Panel1, Zeile 2)
  // bekommt den naechsten freien Wert (1); Panel2 bleibt unveraendert und
  // ist danach wieder eindeutig.
  Assert.AreEqual(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 1', '  end', '  object Panel2: TPanel',
      '    TabOrder = 0', '  end', 'end']),
    Fix037(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 0', '  end', '  object Panel2: TPanel',
      '    TabOrder = 0', '  end', 'end']), 2, R), R);
end;

procedure TTestRdxDfmTabOrderFix.ThreeSiblings_SkipsBothUsedValues;
var
  R : string;
begin
  // 0, 0, 1 belegt - der Fund (erstes Panel, TabOrder=0) bekommt 2 (0 und
  // 1 sind schon vergeben, auch vom eigenen alten Wert unabhaengig).
  Assert.AreEqual(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 2', '  end', '  object Panel2: TPanel',
      '    TabOrder = 0', '  end', '  object Panel3: TPanel',
      '    TabOrder = 1', '  end', 'end']),
    Fix037(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 0', '  end', '  object Panel2: TPanel',
      '    TabOrder = 0', '  end', '  object Panel3: TPanel',
      '    TabOrder = 1', '  end', 'end']), 2, R), R);
end;

procedure TTestRdxDfmTabOrderFix.NestedGrandchild_NotCountedAsSibling;
var
  R : string;
begin
  // Panel1 enthaelt selbst ein Button1 mit TabOrder=0 - das ist ein Enkel
  // von Form1, kein Geschwister von Panel1/Panel2, und darf deren
  // Wertemenge nicht beeinflussen. Panel1 (Fund) und Panel2 teilen
  // TabOrder=0; Panel1 bekommt 1 (Button1s 0 zaehlt nicht fuer die
  // Form1-Ebene, aber 0 ist ohnehin schon durch Panel2 belegt).
  Assert.AreEqual(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 1', '    object Button1: TButton', '      TabOrder = 0',
      '    end', '  end', '  object Panel2: TPanel', '    TabOrder = 0',
      '  end', 'end']),
    Fix037(Join(['object Form1: TForm1', '  object Panel1: TPanel',
      '    TabOrder = 0', '    object Button1: TButton', '      TabOrder = 0',
      '    end', '  end', '  object Panel2: TPanel', '    TabOrder = 0',
      '  end', 'end']), 2, R), R);
end;

procedure TTestRdxDfmTabOrderFix.Refusals;
var
  R : string;
begin
  // ALine ist keine object/inherited/inline-Zeile mehr (Fund veraltet).
  Assert.AreEqual('', Fix037(Join(['object Form1: TForm1',
    '  object Panel1: TPanel', '    TabOrder = 0', '  end', 'end']), 3, R));
  Assert.AreNotEqual('', R);
  // Keine eigene TabOrder-Zeile (mehr).
  Assert.AreEqual('', Fix037(Join(['object Form1: TForm1',
    '  object Panel1: TPanel', '  end', '  object Panel2: TPanel',
    '    TabOrder = 0', '  end', 'end']), 2, R));
  Assert.AreNotEqual('', R);
  // Keine Elter-Komponente (die Fund-Zeile ist schon die DFM-Wurzel).
  Assert.AreEqual('', Fix037(Join(['object Form1: TForm1',
    '  TabOrder = 0', 'end']), 1, R));
  Assert.AreNotEqual('', R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDfmTabOrderFix);

end.
