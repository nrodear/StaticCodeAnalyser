unit uTestRdxCodeMap;

// Die Code-Sicht des Moduls (uRdxCodeMap) gegen die Regel des Cores
// (TDetectorUtils.ScanCodeLine): an Eingaben OHNE mehrzeilige Strings
// muessen die Spalte des '//'-Kommentars und der offene Block-Kommentar am
// Zeilenanfang uebereinstimmen - der Drift-Waechter fuer die zwei Kopien
// derselben Regel (Review reDelphiX nach Bereichen 2026-10-10, Minor 7).
// Dazu StartsInside, auf dem die Unterdrueck-Hilfen bauen (Major 1).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCodeMap = class
  public
    [Test] procedure AgreesWithScanCodeLine;
    [Test] procedure StartsInside_BlockComments;
    [Test] procedure StartsInside_MultiLineString;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils, uRdxCodeMap;

const
  // Je Eintrag eine Datei; keine ''' am Zeilenende (die kennt nur die
  // Code-Sicht).
  SAMPLES: array[0..9] of string = (
    'x := 1; // a'#13#10'y := ''//no''; // b',
    '{ a // b'#13#10'  c // d }'#13#10'e; // f',
    '(* x'#13#10' // y *) z // w',
    'a { b } c // d { e'#13#10'f',
    'S := ''it''''s // no'';  // yes',
    '{$IFDEF X} a // b'#13#10'{ multi'#13#10'line } c',
    'x := ''{''; // c'#13#10'y;',
    '// { oeffnet nicht'#13#10'code',
    '(* { *) a // b'#13#10'{ (* } x // y',
    'p(''a'', { k } ''b''); (* u'#13#10#13#10'v *) // w'
  );

procedure TTestRdxCodeMap.AgreesWithScanCodeLine;
var
  s, i    : Integer;
  SL      : TStringList;
  Map     : TRdxCodeMap;
  State   : TCommentScanState;
  Col     : Integer;
  Inside  : Boolean;
  Where   : string;
begin
  for s := Low(SAMPLES) to High(SAMPLES) do
  begin
    SL := TStringList.Create;
    try
      SL.Text := SAMPLES[s];
      Map := TRdxCodeMap.Create(SL);
      try
        State := Default(TCommentScanState);
        for i := 0 to SL.Count - 1 do
        begin
          Where := Format('Beispiel %d, Zeile %d: %s', [s, i + 1, SL[i]]);
          Inside := State.InBraceComment or State.InParenComment;
          TDetectorUtils.ScanCodeLine(SL[i], State, Col);
          Assert.AreEqual<Integer>(Col, Map.LineCommentCol(i + 1), Where);
          Assert.IsTrue(Inside = Map.StartsInside(i + 1), Where);
        end;
      finally
        Map.Free;
      end;
    finally
      SL.Free;
    end;
  end;
end;

procedure TTestRdxCodeMap.StartsInside_BlockComments;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := 'a; { b'#13#10'c'#13#10'} d;'#13#10'(* e'#13#10'*) f;'#13#10'g;';
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsFalse(Map.StartsInside(1));
      Assert.IsTrue(Map.StartsInside(2));
      Assert.IsTrue(Map.StartsInside(3), 'die schliessende Zeile beginnt noch darin');
      Assert.IsFalse(Map.StartsInside(4));
      Assert.IsTrue(Map.StartsInside(5));
      Assert.IsFalse(Map.StartsInside(6));
      Assert.IsFalse(Map.StartsInside(0), 'ausserhalb der Datei');
      Assert.IsFalse(Map.StartsInside(7), 'ausserhalb der Datei');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.StartsInside_MultiLineString;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := 'S := '''''''#13#10'  // kein Kommentar'#13#10'  '''''';'#13#10'x;';
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsFalse(Map.StartsInside(1));
      Assert.IsTrue(Map.StartsInside(2));
      Assert.AreEqual<Integer>(0, Map.LineCommentCol(2), 'String, kein Kommentar');
      Assert.IsTrue(Map.StartsInside(3));
      Assert.IsFalse(Map.StartsInside(4));
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCodeMap);

end.
