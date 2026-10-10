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
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxSuppress;

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

// Wendet AEdit auf ASource an (wie der Editor) und liefert den neuen Text.
function Apply(const ASource: string; const AEdit: TRdxEdit): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
  Ok    : Boolean;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Ok := PlanByteEdits(Bytes, [AEdit], Plan, Err);
  Assert.IsTrue(Ok, Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

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
    Assert.IsTrue(R <> '');
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
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 2, 'X', E, R));
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 99, 'X', E, R));
    Assert.IsFalse(TRdxSuppress.LineMarker(L, 1, '', E, R));
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSuppress);

end.
