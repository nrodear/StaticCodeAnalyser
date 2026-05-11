unit uTestDfmBinaryReader;

// Smoke-Tests fuer uDfmBinaryReader.
// Fokus: TPF0-Erkennung, Text-Passthrough, Roundtrip Text->Binary->Text
// via Classes.ObjectTextToBinary (Vergleichs-Hilfe fuer ein synthetisches
// Mini-Form). Echte Embarcadero-Forms muessen wir hier nicht reproduzieren,
// die werden vom Detektor-Test-Set abgedeckt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmBinaryReader = class
  public
    [Test] procedure Test_IsBinary_EmptyBytes_False;
    [Test] procedure Test_IsBinary_ShortBytes_False;
    [Test] procedure Test_IsBinary_TextDfm_False;
    [Test] procedure Test_IsBinary_TPF0_True;

    [Test] procedure Test_ToText_Empty_ReturnsEmpty;
    [Test] procedure Test_ToText_TextDfm_PassesThrough;
    [Test] procedure Test_ToText_BinaryRoundtrip_RestoresObjectKeyword;

    [Test] procedure Test_ReadFile_NotExisting_ReturnsEmpty;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uDfmBinaryReader;

procedure TTestDfmBinaryReader.Test_IsBinary_EmptyBytes_False;
var Bytes: TBytes;
begin
  SetLength(Bytes, 0);
  Assert.IsFalse(TDfmBinaryReader.IsBinary(Bytes));
end;

procedure TTestDfmBinaryReader.Test_IsBinary_ShortBytes_False;
var Bytes: TBytes;
begin
  Bytes := TBytes.Create($54, $50, $46); // 'TPF' - drei Bytes, zu kurz
  Assert.IsFalse(TDfmBinaryReader.IsBinary(Bytes));
end;

procedure TTestDfmBinaryReader.Test_IsBinary_TextDfm_False;
var
  Bytes: TBytes;
const
  S = 'object Form2: TForm2'#13#10'end';
begin
  Bytes := TEncoding.UTF8.GetBytes(S);
  Assert.IsFalse(TDfmBinaryReader.IsBinary(Bytes));
end;

procedure TTestDfmBinaryReader.Test_IsBinary_TPF0_True;
var Bytes: TBytes;
begin
  Bytes := TBytes.Create($54, $50, $46, $30, $00); // 'TPF0' + dummy
  Assert.IsTrue(TDfmBinaryReader.IsBinary(Bytes));
end;

procedure TTestDfmBinaryReader.Test_ToText_Empty_ReturnsEmpty;
var Bytes: TBytes;
begin
  SetLength(Bytes, 0);
  Assert.AreEqual('', TDfmBinaryReader.ToText(Bytes));
end;

procedure TTestDfmBinaryReader.Test_ToText_TextDfm_PassesThrough;
var
  Bytes: TBytes;
  Got  : string;
const
  // Realistisches Mini-Text-DFM. Inhalt darf unveraendert durchgereicht
  // werden - der Lexer/Parser kommt damit klar.
  S = 'object Form2: TForm2'#13#10 +
      '  Caption = ''Test'''#13#10 +
      'end'#13#10;
begin
  Bytes := TEncoding.UTF8.GetBytes(S);
  Got := TDfmBinaryReader.ToText(Bytes);
  Assert.AreEqual(S, Got);
end;

procedure TTestDfmBinaryReader.Test_ToText_BinaryRoundtrip_RestoresObjectKeyword;
// Wir bauen ein synthetisches Binaer-DFM via ObjectTextToBinary (RTL)
// und pruefen, dass uDfmBinaryReader.ToText daraus wieder Text macht,
// der das 'object'-Keyword und den Form-Klassennamen enthaelt.
var
  TextSrc : TStringStream;
  BinDst  : TBytesStream;
  Bytes   : TBytes;
  Got     : string;
const
  S = 'object Form2: TForm2'#13#10 +
      '  Caption = ''Test'''#13#10 +
      '  Left = 100'#13#10 +
      '  Top = 200'#13#10 +
      'end'#13#10;
begin
  TextSrc := TStringStream.Create(S, TEncoding.UTF8);
  try
    BinDst := TBytesStream.Create;
    try
      TextSrc.Position := 0;
      ObjectTextToBinary(TextSrc, BinDst);
      BinDst.Position := 0;
      SetLength(Bytes, BinDst.Size);
      if BinDst.Size > 0 then
        Move(BinDst.Bytes[0], Bytes[0], BinDst.Size);
    finally
      BinDst.Free;
    end;
  finally
    TextSrc.Free;
  end;

  Assert.IsTrue(TDfmBinaryReader.IsBinary(Bytes),
    'Binary roundtrip output should carry TPF0 prefix');

  Got := TDfmBinaryReader.ToText(Bytes);
  Assert.IsTrue(Pos('object', Got) > 0, 'expected "object" keyword in decoded text');
  Assert.IsTrue(Pos('TForm2', Got) > 0, 'expected "TForm2" class name in decoded text');
  Assert.IsTrue(Pos('Test',  Got) > 0, 'expected Caption literal in decoded text');
end;

procedure TTestDfmBinaryReader.Test_ReadFile_NotExisting_ReturnsEmpty;
begin
  Assert.AreEqual('', TDfmBinaryReader.ReadFile('Z:\does\not\exist\nirvana.dfm'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmBinaryReader);

end.
