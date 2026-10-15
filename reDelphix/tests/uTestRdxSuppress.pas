unit uTestRdxSuppress;

// Editorhilfen Stufe 1 (G1, G2, SCA165): die Unterdrueck-Hilfen als
// fertige Ersetzungen. Jeder Fall laeuft durch PlanByteEdits und
// ApplyByteEdits - geprueft wird der Text NACH dem Klick, mit CRLF wie im
// Editor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSuppress = class
  public
    [Test] procedure LineMarker_InsertsAboveWithIndent;
    [Test] procedure LineMarker_AddsKindToMarkerAbove;
    [Test] procedure LineMarker_AlreadyListed_NothingToDo;
    [Test] procedure LineMarker_EmptyLine_NothingToDo;
    [Test] procedure FileMarker_AfterUnitLine;
    [Test] procedure FileMarker_AddsKindToExisting;
    [Test] procedure RemoveMarker_WholeLine;
    [Test] procedure RemoveMarker_LastLine;
    [Test] procedure RemoveMarker_TrailingCommentKeepsCode;
    [Test] procedure RemoveMarker_BraceCommentBeforeMarker;
    [Test] procedure RemoveMarker_InsideBlockComment_NothingToDo;
    [Test] procedure Markers_Recognized;
    // Review reDelphiX nach Bereichen 2026-10-10 (Major 1/2, Minor 9/10)
    [Test] procedure LineMarker_InsideBraceComment_Refused;
    [Test] procedure LineMarker_InsideMultiLineString_Refused;
    [Test] procedure LineMarker_AboveAllMarker_OwnLine;
    [Test] procedure LineMarker_PrevMarkerInComment_OwnLine;
    [Test] procedure FileMarker_AllMarker_NotExtended;
    [Test] procedure FileMarker_HeaderWordsInLicenseComment;
    [Test] procedure RemoveMarker_MultiKind_Refused;
    [Test] procedure RemoveMarker_All_Refused;
    [Test] procedure RemoveMarker_OneKindWithReason;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxSuppress,
  uTestRdxTextKit;   // Apply

const
  CODE = '  L := TStringList';   // Anfang der Fundzeile
  KIND = 'MemoryLeak';
  BASE_SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  L := TStringList.Create;'#13#10 +
    'end;'#13#10 +
    'end.';

function LinesOf(const ASource: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Text := ASource;
end;

procedure TTestRdxSuppress.LineMarker_InsertsAboveWithIndent;
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := LinesOf(BASE_SRC);
  try
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 6, KIND, E, R), R);
    Assert.AreEqual(StringReplace(BASE_SRC, CODE,
      '  // noinspection MemoryLeak'#13#10 + CODE, []), Apply(BASE_SRC, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_AddsKindToMarkerAbove;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection: MissingFinally (Grund steht hier)'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 7, KIND, E, R), R);
    Assert.AreEqual(StringReplace(Src, '// noinspection: MissingFinally',
      '// noinspection: MemoryLeak, MissingFinally', []), Apply(Src, E),
      'die Art kommt hinter den Tag, der Grund bleibt stehen');
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_AlreadyListed_NothingToDo;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection memoryleak, X'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 7, KIND, E, R),
      'gross/klein wie der Core');
    Assert.IsTrue(Pos('schon da', R) > 0, R);
  finally
    L.Free;
  end;
  // ':' direkt hinter dem Tag ohne Leerzeichen (Review Quick-Fix-Units
  // 2026-10-14): die Art steht da - sonst kaeme '// noinspection: X,X'.
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection:MemoryLeak'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 7, KIND, E, R), 'Tag:Art');
    Assert.IsTrue(Pos('schon da', R) > 0, R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_EmptyLine_NothingToDo;
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := LinesOf('unit u;'#13#10#13#10'end.');
  try
    // Jede Ablehnung mit IHREM Grund (Nachbesserung FF, Befundklasse
    // R6-04: bis dahin prueften diese Asserts nur das False).
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 2, 'X', E, R));
    Assert.IsTrue(Pos('Fundzeile ist leer', R) > 0, R);
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 99, 'X', E, R));
    Assert.IsTrue(Pos('keine Fundzeile', R) > 0, R);
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 1, '', E, R));
    Assert.IsTrue(Pos('keine Fundzeile', R) > 0, R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.FileMarker_AfterUnitLine;
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := LinesOf(BASE_SRC);
  try
    Assert.IsTrue(TRdxSuppress.FileMarker(L, 'MagicNumber', E, R), R);
    Assert.AreEqual(StringReplace(BASE_SRC, 'unit u;',
      'unit u;'#13#10'// noinspection-file MagicNumber', []), Apply(BASE_SRC, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.FileMarker_AddsKindToExisting;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, 'implementation',
    'implementation'#13#10'// noinspection-file TooLongLine', []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.FileMarker(L, 'MagicNumber', E, R), R);
    Assert.AreEqual(StringReplace(Src, 'noinspection-file TooLongLine',
      'noinspection-file MagicNumber, TooLongLine', []), Apply(Src, E));
    Assert.IsFalse(TRdxSuppress.FileMarker(L, 'toolongline', E, R),
      'steht schon da');
    Assert.IsTrue(Pos('schon da', R) > 0, R);
  finally
    L.Free;
  end;
  // Auch mit ':' direkt hinter dem Tag.
  Src := StringReplace(BASE_SRC, 'implementation',
    'implementation'#13#10'// noinspection-file:TooLongLine', []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.FileMarker(L, 'TooLongLine', E, R),
      'Tag:Art steht schon da');
    Assert.IsTrue(Pos('schon da', R) > 0, R);
    Assert.IsTrue(TRdxSuppress.FileMarker(L, 'MagicNumber', E, R), R);
    Assert.AreEqual(StringReplace(Src, 'noinspection-file:TooLongLine',
      'noinspection-file: MagicNumber,TooLongLine', []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_WholeLine;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection NilDeref'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 6, E, R), R);
    Assert.AreEqual(BASE_SRC, Apply(Src, E), 'Zeile samt Zeilenende weg');
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_LastLine;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := BASE_SRC + #13#10'// noinspection-file X';
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 9, E, R), R);
    Assert.AreEqual(BASE_SRC, Apply(Src, E), 'das Zeilenende davor geht mit');
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_TrailingCommentKeepsCode;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Ein '//' im String zaehlt nicht als Kommentar.
  Src := StringReplace(BASE_SRC, '  L := TStringList.Create;',
    '  U := ''http://x'';   // noinspection HttpInsteadOfHttps', []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 6, E, R), R);
    Assert.AreEqual(StringReplace(BASE_SRC, '  L := TStringList.Create;',
      '  U := ''http://x'';', []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_BraceCommentBeforeMarker;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // '//' und ein Apostroph in einem {...}-Kommentar VOR dem Marker: der
  // zeilenweise Scan schnitt ab dem inneren '//' (offenes '{' blieb
  // stehen) bzw. hielt den Rest der Zeile fuer einen String.
  Src := StringReplace(BASE_SRC, '  L := TStringList.Create;',
    '  X := 1; { a // b } // noinspection Foo'#13#10
    + '  Y := 2; { it''s } // noinspection Bar', []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 6, E, R), R);
    Src := Apply(Src, E);
  finally
    L.Free;
  end;
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 7, E, R), R);
    Assert.AreEqual(StringReplace(BASE_SRC, '  L := TStringList.Create;',
      '  X := 1; { a // b }'#13#10'  Y := 2; { it''s }', []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_InsideBlockComment_NothingToDo;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Die Zeile liegt IN einem Block-Kommentar, der Zeilen frueher beginnt:
  // dort ist '//' kein Kommentaranfang - lieber keine Hilfe.
  Src := StringReplace(BASE_SRC, '  L := TStringList.Create;',
    '  {'#13#10'  // noinspection Foo'#13#10'  }', []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.RemoveMarker(L, 7, E, R));
    Assert.AreEqual('kein Marker in der Zeile', R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.Markers_Recognized;
begin
  Assert.IsTrue(TRdxSuppress.IsLineMarker('    //noinspection X'));
  Assert.IsTrue(TRdxSuppress.IsLineMarker('// NoInspection: X'));
  Assert.IsFalse(TRdxSuppress.IsLineMarker('// noinspection-file X'));
  Assert.IsTrue(TRdxSuppress.IsFileMarker('// noinspection-file X'));
  Assert.IsFalse(TRdxSuppress.IsLineMarker('x := 1; // noinspection X'),
    'kein reiner Kommentar');
  Assert.IsFalse(TRdxSuppress.IsLineMarker('// Hinweis'));
end;

procedure TTestRdxSuppress.LineMarker_InsideBraceComment_Refused;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // TodoComment meldet auch innere Zeilen eines '{ ... }': ein Marker
  // davor laege im Kommentar und wirkte nicht.
  Src := StringReplace(BASE_SRC, '  L := TStringList.Create;',
    '  {'#13#10'    TODO: aufraeumen'#13#10'  }', []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 7, 'TodoComment', E, R));
    Assert.IsTrue(Pos('Block-Kommentar', R) > 0, R);
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 6, 'TodoComment', E, R),
      'die Zeile mit dem oeffnenden { geht: davor ist Code-Sicht ' + R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_InsideMultiLineString_Refused;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Delphi 12: eine Zeile davor wuerde Teil des String-Werts.
  Src := StringReplace(BASE_SRC, '  L := TStringList.Create;',
    '  S := '''''''#13#10'    sehr lange Zeile'#13#10'    '''''';', []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 7, 'TooLongLine', E, R));
    Assert.IsTrue(Pos('mehrzeiligen String', R) > 0, R);
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 8, 'TooLongLine', E, R),
      'auch die schliessende Zeile liegt noch im String');
    Assert.IsTrue(Pos('mehrzeiligen String', R) > 0, R);
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 6, 'TooLongLine', E, R), R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_AboveAllMarker_OwnLine;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // 'All' wirkt nur als ganze Liste - 'X, All' waere nur noch X. Der
  // Core vereinigt gestapelte Marker, also eine eigene Zeile.
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection All'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 7, 'SQLInjection', E, R), R);
    Assert.AreEqual(StringReplace(BASE_SRC, CODE,
      '  // noinspection All'#13#10'  // noinspection SQLInjection'#13#10
      + CODE, []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.LineMarker_PrevMarkerInComment_OwnLine;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Die Zeile darueber sieht aus wie ein Marker, liegt aber im Kommentar.
  Src := StringReplace(BASE_SRC, CODE,
    '  { Notiz:'#13#10'  // noinspection Foo }'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.LineMarker(L, 8, KIND, E, R), R);
    Assert.AreEqual(StringReplace(Src, CODE,
      '  // noinspection MemoryLeak'#13#10 + CODE, []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.FileMarker_AllMarker_NotExtended;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, 'implementation',
    'implementation'#13#10'// noinspection-file All', []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.FileMarker(L, 'HardcodedSecret', E, R), R);
    Assert.AreEqual(StringReplace(Src, 'unit u;',
      'unit u;'#13#10'// noinspection-file HardcodedSecret', []), Apply(Src, E),
      'der All-Marker bleibt, wie er ist');
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.FileMarker_HeaderWordsInLicenseComment;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Kopfwoerter im Lizenzkommentar zaehlen nicht; Tab nach 'unit' schon.
  Src := '{'#13#10'Unit Name: Foo'#13#10
    + 'library General Public License'#13#10'}'#13#10
    + StringReplace(BASE_SRC, 'unit u;', 'unit'#9'u;', []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.FileMarker(L, 'MagicNumber', E, R), R);
    Assert.AreEqual(StringReplace(Src, 'unit'#9'u;',
      'unit'#9'u;'#13#10'// noinspection-file MagicNumber', []), Apply(Src, E));
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_MultiKind_Refused;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // SCA165 kommt auch, wenn nur die Arten des aktiven Profils nichts
  // unterdrueckt haben - die anderen koennen noch wirken.
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection NilDeref, TooLongLine'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.RemoveMarker(L, 6, E, R));
    Assert.IsTrue(Pos('mehrere Arten', R) > 0, R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_All_Refused;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  Src := StringReplace(BASE_SRC, 'implementation',
    'implementation'#13#10'// noinspection-file: *', []);
  L := LinesOf(Src);
  try
    Assert.IsFalse(TRdxSuppress.RemoveMarker(L, 4, E, R));
    Assert.IsTrue(Pos('alle Arten', R) > 0, R);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppress.RemoveMarker_OneKindWithReason;
var
  Src : string;
  L   : TStringList;
  E   : TRdxEdit;
  R   : string;
begin
  // Ein Grund in Klammern ist keine zweite Art.
  Src := StringReplace(BASE_SRC, CODE,
    '  // noinspection NilDeref (Grund: Altlast, Ticket 12)'#13#10 + CODE, []);
  L := LinesOf(Src);
  try
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, 6, E, R), R);
    Assert.AreEqual(BASE_SRC, Apply(Src, E));
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSuppress);

end.
