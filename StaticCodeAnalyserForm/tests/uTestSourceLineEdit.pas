unit uTestSourceLineEdit;

// Byte-Treue des Datei-Zeileneditors (uSourceLineEdit) - der Traeger der
// Suppress-/Quick-Fix-Tasten der Standalone-EXE. Hier gibt es kein
// Editor-Undo: jede Zusicherung ("nichts ausser der Zielzeile aendert
// sich") wird deshalb auf BYTE-Ebene geprueft, nicht auf Zeilen-Ebene.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils;   // TBytes (ReadBytes-Signatur im interface)

type
  [TestFixture]
  TTestSourceLineEdit = class
  strict private
    FTmp : string;
    function WriteBytes(const AName: string; const B: array of Byte): string;
    function ReadBytes(const APath: string): TBytes;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // ---- Einfuegen ----
    [Test] procedure Insert_Crlf_Utf8Bom_OnlyNewLineAdded;
    [Test] procedure Insert_LfOnly_KeepsLf_Everywhere;
    [Test] procedure Insert_AboveLastLine_WithoutTrailingEol;
    [Test] procedure Insert_CopiesIndentation;
    [Test] procedure Insert_MixedEols_UsesTargetLineEol;
    [Test] procedure Insert_Ansi_Umlauts_Preserved;
    [Test] procedure Insert_LineOutOfRange_FailsUntouched;

    // ---- Ersetzen / Lesen ----
    [Test] procedure Replace_KeepsEol_RestByteIdentical;
    [Test] procedure ReadLine_ReturnsContentWithoutEol;
  end;

implementation

uses
  System.Classes, System.IOUtils,
  uSourceLineEdit;

const
  // 5x in Byte-Vergleichen - identischer Wortlaut gewollt.
  SByteLen = 'Bytelaenge';

function TTestSourceLineEdit.WriteBytes(const AName: string;
  const B: array of Byte): string;
var
  Bytes : TBytes;
  i     : Integer;
begin
  Result := TPath.Combine(FTmp, AName);
  SetLength(Bytes, Length(B));
  for i := 0 to High(B) do
  begin
    Bytes[i] := B[i];
  end;
  TFile.WriteAllBytes(Result, Bytes);
end;

function TTestSourceLineEdit.ReadBytes(const APath: string): TBytes;
begin
  Result := TFile.ReadAllBytes(APath);
end;

procedure TTestSourceLineEdit.Setup;
begin
  FTmp := TPath.Combine(TPath.GetTempPath,
    'sca_sle_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FTmp);
end;

procedure TTestSourceLineEdit.TearDown;
begin
  if TDirectory.Exists(FTmp) then
    TDirectory.Delete(FTmp, True);
end;

{ ---- Helfer fuer lesbare Fixtures ---- }

function Ascii(const S: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(S);
end;

{ ---- Einfuegen ---- }

procedure TTestSourceLineEdit.Insert_Crlf_Utf8Bom_OnlyNewLineAdded;
var
  P    : string;
  Err  : string;
  B    : TBytes;
  Want : TBytes;
begin
  // BOM + zwei CRLF-Zeilen. Nach dem Einfuegen ueber Zeile 2 muss die
  // Datei EXAKT aus BOM + Zeile1 + NEU + Zeile2 bestehen.
  P := TPath.Combine(FTmp, 'a.pas');
  TFile.WriteAllBytes(P,
    TBytes.Create($EF, $BB, $BF) + Ascii('one'#13#10'two'#13#10));
  Assert.IsTrue(TSourceLineEdit.InsertLineAbove(P, 2, '// mark', Err), Err);
  B := ReadBytes(P);
  Want := TBytes.Create($EF, $BB, $BF) +
          Ascii('one'#13#10'// mark'#13#10'two'#13#10);
  Assert.AreEqual(Length(Want), Length(B), SByteLen);
  Assert.IsTrue(CompareMem(@Want[0], @B[0], Length(Want)),
    'Bytes weichen ab - mehr als die Zielzeile veraendert');
end;

procedure TTestSourceLineEdit.Insert_LfOnly_KeepsLf_Everywhere;
var
  P, Err : string;
  B      : TBytes;
  Want   : TBytes;
begin
  // Unix-Datei: der neue Umbruch muss LF sein, NIRGENDS darf CRLF
  // entstehen (TStringList haette die ganze Datei auf CRLF gedreht).
  P := WriteBytes('u.pas', [Ord('a'), 10, Ord('b'), 10]);
  Assert.IsTrue(TSourceLineEdit.InsertLineAbove(P, 2, 'x', Err), Err);
  B := ReadBytes(P);
  Want := Ascii('a'#10'x'#10'b'#10);
  Assert.AreEqual(Length(Want), Length(B), SByteLen);
  Assert.IsTrue(CompareMem(@Want[0], @B[0], Length(Want)), 'LF-Erhalt');
end;

procedure TTestSourceLineEdit.Insert_AboveLastLine_WithoutTrailingEol;
var
  P, Err : string;
  B      : TBytes;
  Want   : TBytes;
begin
  // Letzte Zeile OHNE End-Umbruch: die neue Zeile braucht einen
  // (sie steht nicht mehr am Ende), die letzte bleibt umbruchlos.
  P := WriteBytes('n.pas', [Ord('a'), 13, 10, Ord('b')]);
  Assert.IsTrue(TSourceLineEdit.InsertLineAbove(P, 2, 'm', Err), Err);
  B := ReadBytes(P);
  Want := Ascii('a'#13#10'm'#13#10'b');
  Assert.AreEqual(Length(Want), Length(B), SByteLen);
  Assert.IsTrue(CompareMem(@Want[0], @B[0], Length(Want)),
    'End-Umbruch-Zustand muss erhalten bleiben');
end;

procedure TTestSourceLineEdit.Insert_CopiesIndentation;
var
  P, Err : string;
  SL     : TStringList;
begin
  P := WriteBytes('i.pas', []);
  TFile.WriteAllText(P, '  begin'#13#10'    DoIt;'#13#10'  end;'#13#10,
    TEncoding.ASCII);
  Assert.IsTrue(
    TSourceLineEdit.InsertLineAbove(P, 2, '// noinspection X', Err), Err);
  SL := TStringList.Create;
  try
    SL.LoadFromFile(P);
    Assert.AreEqual('    // noinspection X', SL[1],
      'Einrueckung der Zielzeile muss uebernommen werden');
  finally
    SL.Free;
  end;
end;

procedure TTestSourceLineEdit.Insert_MixedEols_UsesTargetLineEol;
var
  P, Err : string;
  B      : TBytes;
  Want   : TBytes;
begin
  // Zeile 1 endet CRLF, Zeile 2 endet LF (gemischte Datei, kommt in
  // alten Repos vor). Einfuegen ueber Zeile 2: neuer Umbruch = der der
  // ZIELZEILE (LF), und die CRLF/LF-Mischung selbst bleibt exakt.
  P := WriteBytes('m.pas', [Ord('a'), 13, 10, Ord('b'), 10, Ord('c'), 10]);
  Assert.IsTrue(TSourceLineEdit.InsertLineAbove(P, 2, 'x', Err), Err);
  B := ReadBytes(P);
  Want := Ascii('a'#13#10'x'#10'b'#10'c'#10);
  Assert.AreEqual(Length(Want), Length(B), SByteLen);
  Assert.IsTrue(CompareMem(@Want[0], @B[0], Length(Want)), 'Misch-Erhalt');
end;

procedure TTestSourceLineEdit.Insert_Ansi_Umlauts_Preserved;
var
  P, Err : string;
  B      : TBytes;
begin
  // ANSI-Datei mit Umlaut ($E4 = ae in Windows-1252, ungueltig als
  // UTF-8-Sequenz -> ANSI-Pfad). Der Umlaut muss als DASSELBE Byte
  // zurueckkommen - eine UTF-8-Umkodierung wuerde 2 Bytes daraus machen.
  P := WriteBytes('ae.pas', [Ord('x'), $E4, Ord('y'), 13, 10, Ord('z'), 13, 10]);
  Assert.IsTrue(TSourceLineEdit.InsertLineAbove(P, 2, 'm', Err), Err);
  B := ReadBytes(P);
  // Beide Seiten explizit Integer: unter dcc64 liefert Length() auf
  // dynamischen Arrays NativeInt, und die generische AreEqual<T>-
  // Ableitung findet fuer (Integer-Literal, NativeInt) keinen
  // gemeinsamen Typ (E2532). Der Integer-Cast trifft die nicht-
  // generische Ueberladung auf beiden Plattformen.
  Assert.AreEqual(Integer($E4), Integer(B[1]),
    'Umlaut-Byte muss identisch bleiben');
  Assert.AreEqual(11, Integer(Length(B)), 'x{E4}y CRLF m CRLF z CRLF');
end;

procedure TTestSourceLineEdit.Insert_LineOutOfRange_FailsUntouched;
var
  P, Err : string;
  Before : TBytes;
  After  : TBytes;
begin
  P := WriteBytes('r.pas', [Ord('a'), 13, 10]);
  Before := ReadBytes(P);
  Assert.IsFalse(TSourceLineEdit.InsertLineAbove(P, 5, 'x', Err));
  Assert.IsTrue(Err <> '', 'Fehlertext muss den Grund nennen');
  After := ReadBytes(P);
  Assert.AreEqual(Length(Before), Length(After),
    'Fehlschlag darf die Datei nicht anfassen');
end;

{ ---- Ersetzen / Lesen ---- }

procedure TTestSourceLineEdit.Replace_KeepsEol_RestByteIdentical;
var
  P, Err : string;
  B      : TBytes;
  Want   : TBytes;
begin
  P := WriteBytes('rep.pas', [Ord('a'), 10, Ord('b'), Ord('b'), 10, Ord('c')]);
  Assert.IsTrue(TSourceLineEdit.ReplaceLine(P, 2, 'XY', Err), Err);
  B := ReadBytes(P);
  Want := Ascii('a'#10'XY'#10'c');
  Assert.AreEqual(Length(Want), Length(B), SByteLen);
  Assert.IsTrue(CompareMem(@Want[0], @B[0], Length(Want)),
    'nur der Zeileninhalt darf sich aendern');
end;

procedure TTestSourceLineEdit.ReadLine_ReturnsContentWithoutEol;
var
  P, Err, Text : string;
begin
  P := WriteBytes('rd.pas', [Ord('a'), 13, 10, Ord('b'), Ord('c'), 10]);
  Assert.IsTrue(TSourceLineEdit.ReadLine(P, 2, Text, Err), Err);
  Assert.AreEqual('bc', Text, False);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSourceLineEdit);

end.
