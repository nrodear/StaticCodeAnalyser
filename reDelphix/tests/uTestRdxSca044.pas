unit uTestRdxSca044;

// Ende-zu-Ende-Tests fuer das Rezept 5.1 (Verkettung -> Format) gegen den
// ECHTEN Core: Parser, Detektor SCA044, TSourcePlaces, Rezept-Laeufer.
// Jeder Test schreibt eine Temp-Datei, laesst den Detektor laufen und
// fragt den Laeufer - derselbe Weg wie im IDE-Package, nur ohne ToolsAPI.
//
// Die Varianten folgen der Heuristik von uConcatToFormat:
//   1. mindestens drei '+' auf oberster Klammertiefe (MIN_NON_LITERAL_PLUS)
//   2. mindestens ein Literal UND ein Nicht-Literal in der Kette
//   3. ein SQL-Ziel (.SQL.Text, .CommandText) gehoert SCA003
//   4. kein Fund, wenn im Ausdruck schon Format( steht
// und den Term-Arten, die Zerleger und Typaufloesung kennen: Literal,
// Steuerzeichen, bekannter RTL-Aufruf, .ToString, Bezeichner mit
// deklariertem Typ (Parameter, lokale Variable, Feld, Char), Integer,
// unbekannter Ausdruck - dazu Kommentar, $IFDEF, SQL-Text, fehlendes
// SysUtils, mehrdeutige Zeile und die Idempotenz nach dem Umschreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSca044 = class
  public
    // ---- Detektor-Heuristik ----
    [Test] procedure Detector_ThreePlus_Mixed_Finds;
    [Test] procedure Detector_TwoPlus_NoFinding;
    [Test] procedure Detector_OnlyLiterals_NoFinding;
    [Test] procedure Detector_SqlTarget_NoFinding;
    [Test] procedure Detector_AlreadyFormat_NoFinding;
    [Test] procedure Detector_PlusInsideParens_NotCounted;

    // ---- Rezept: aktiv ----
    [Test] procedure Rewrite_StringLocalsAndCalls_Enabled;
    [Test] procedure Rewrite_ParamsAndField_Enabled;
    [Test] procedure Rewrite_ToStringOperand_Enabled;
    [Test] procedure Rewrite_CharOperand_Enabled;
    [Test] procedure Rewrite_MultiLineChain_Enabled;
    [Test] procedure Rewrite_ControlCharsAndQuotes_Encoded;
    [Test] procedure Rewrite_PercentInLiteral_Escaped;
    [Test] procedure Rewrite_ThenBranchWithoutSemicolon_Enabled;

    // ---- Rezept: ausgegraut mit Grund ----
    [Test] procedure Rewrite_IntegerOperand_Disabled;
    [Test] procedure Rewrite_UnknownOperand_Disabled;
    [Test] procedure Rewrite_CommentInChain_Disabled;
    [Test] procedure Rewrite_InsideIfdef_Disabled;
    [Test] procedure Rewrite_SqlText_Disabled;
    [Test] procedure Rewrite_MissingSysUtils_Disabled;
    [Test] procedure Rewrite_TwoAssignsOnLine_Disabled;

    // ---- Idempotenz ----
    [Test] procedure Rewrite_AppliedOnce_NoSecondFinding;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts, uConcatToFormat,
  uEngineApi, uRefactorInfo, uRdxRecipes, uRdxRecipeRunner;

const
  // Eine Unit mit allem, was die Varianten brauchen: Feld, Parameter
  // (auch const), lokale Strings, ein Integer, ein Char, ein Objekt.
  HEAD =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.SysUtils;'#13#10 +
    'type TFoo = class'#13#10 +
    '  FName: string;'#13#10 +
    '  procedure Run(Id: Integer; const Tag: string);'#13#10 +
    'end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Run(Id: Integer; const Tag: string);'#13#10 +
    'var Marker, Text: string; n: Integer; c: Char; Obj: TObject;'#13#10 +
    'begin'#13#10;
  FOOT =
    #13#10'end;'#13#10 +
    'end.';

function UnitWith(const ABody: string): string;
begin
  Result := HEAD + ABody + FOOT;
end;

// Schreibt ASource in eine Temp-Datei und liefert deren Pfad.
function WriteTemp(const ASource: string): string;
var
  SL : TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_sca044_' + FormatDateTime('hhnnsszzz', Now)
    + IntToStr(Random(1000000)) + '.pas';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Result);
  finally
    SL.Free;
  end;
end;

// Zeile (1-basiert) der ersten Quellzeile, die AMarker enthaelt.
function LineOf(const ASource, AMarker: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

// Funde des Detektors SCA044 in der Datei - der echte Detektor auf dem
// echten AST.
function DetectorFindings(const ASource: string): Integer;
var
  Path    : string;
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
begin
  Result := 0;
  Path := WriteTemp(ASource);
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
        TConcatToFormatDetector.AnalyzeUnit(Root, Path, Results);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    for F in Results do
      if F.Kind = fkConcatToFormat then Inc(Result);
  finally
    Results.Free;
    DeleteFile(Path);
  end;
end;

// Der volle Weg des Moduls: Datei oeffnen, die Fundzeile (Zeile mit
// AMarker) ueber den Anker 'assign' beschreiben, Rezept ausfuehren.
function RunRecipe(const ASource, AMarker: string;
  out AOutcome: TRdxFormatOutcome): Boolean;
var
  Path   : string;
  Places : TSourcePlaces;
  Info   : TRefactorInfo;
  IsCall : Boolean;
  Why    : string;
begin
  Result   := False;
  AOutcome := Default(TRdxFormatOutcome);
  Path := WriteTemp(ASource);
  Places := TSourcePlaces.Create;
  try
    if not Places.Open(Path) then Exit;
    Info := TRdxRecipeRunner.DescribeAnchor(Places, LineOf(ASource, AMarker),
      'assign', IsCall, Why);
    try
      AOutcome := TRdxRecipeRunner.FormatRewrite(Places, Info, Why,
        TRdxRecipeRunner.UsesNamesOf(Places));
      Result := AOutcome.Enabled;
    finally
      Info.Free;
    end;
  finally
    Places.Free;
    DeleteFile(Path);
  end;
end;

{ ---- Detektor-Heuristik ---- }

procedure TTestRdxSca044.Detector_ThreePlus_Mixed_Finds;
begin
  Assert.AreEqual<Integer>(1, DetectorFindings(UnitWith(
    '  Text := Marker + ''id:'' + IntToStr(Id) + '' Milli: '' + IntToStr(n);')));
end;

procedure TTestRdxSca044.Detector_TwoPlus_NoFinding;
begin
  // Drei Terme sind Idiom-Code - unter der Schwelle MIN_NON_LITERAL_PLUS.
  Assert.AreEqual<Integer>(0, DetectorFindings(UnitWith(
    '  Text := ''a'' + Marker + ''b'';')));
end;

procedure TTestRdxSca044.Detector_OnlyLiterals_NoFinding;
begin
  // Reine Literal-Verkettung (mehrzeiliger Text) ist kein Format-Kandidat.
  Assert.AreEqual<Integer>(0, DetectorFindings(UnitWith(
    '  Text := ''a'' + ''b'' + ''c'' + ''d'';')));
end;

procedure TTestRdxSca044.Detector_SqlTarget_NoFinding;
begin
  // SQL-Ziel: uSQLInjection ist zustaendig, kein Doppelbefund.
  Assert.AreEqual<Integer>(0, DetectorFindings(UnitWith(
    '  Query.SQL.Text := ''SELECT '' + Marker + '' FROM '' + Tag;')));
end;

procedure TTestRdxSca044.Detector_AlreadyFormat_NoFinding;
begin
  Assert.AreEqual<Integer>(0, DetectorFindings(UnitWith(
    '  Text := ''a'' + Format(''%d'', [n]) + ''b'' + Marker + ''c'';')));
end;

procedure TTestRdxSca044.Detector_PlusInsideParens_NotCounted;
begin
  // Das arithmetische '+' in der Klammer zaehlt nicht zur Kette.
  Assert.AreEqual<Integer>(0, DetectorFindings(UnitWith(
    '  Text := ''a'' + IntToStr(n + Id + 1) + ''b'';')));
end;

{ ---- Rezept: aktiv ---- }

procedure TTestRdxSca044.Rewrite_StringLocalsAndCalls_Enabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := Marker + ''id:'' + IntToStr(Id) + '' Milli: '' + IntToStr(n);'),
    'Text := Marker', O), O.Reason);
  Assert.AreEqual('Format(''%sid:%s Milli: %s'', [Marker, IntToStr(Id), IntToStr(n)])',
    O.NewText);
  Assert.AreEqual('Marker + ''id:'' + IntToStr(Id) + '' Milli: '' + IntToStr(n)',
    O.Expected, 'ersetzt wird vom ersten bis zum letzten Term');
  Assert.IsTrue(O.Span.IsSingleLine);
  Assert.IsTrue(Pos('5 Terme', O.Hint) > 0, O.Hint);
end;

procedure TTestRdxSca044.Rewrite_ParamsAndField_Enabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := Tag + '' / '' + FName + '' / '' + Marker;'),
    'Text := Tag', O), O.Reason);
  Assert.AreEqual('Format(''%s / %s / %s'', [Tag, FName, Marker])', O.NewText);
end;

procedure TTestRdxSca044.Rewrite_ToStringOperand_Enabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := ''id='' + Id.ToString + '', n='' + n.ToString;'),
    'Text := ''id=''', O), O.Reason);
  Assert.AreEqual('Format(''id=%s, n=%s'', [Id.ToString, n.ToString])', O.NewText);
end;

procedure TTestRdxSca044.Rewrite_CharOperand_Enabled;
var
  O : TRdxFormatOutcome;
begin
  // Format nimmt ein Char fuer %s - der deklarierte Typ genuegt.
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := ''x'' + c + ''y'' + Marker;'),
    'Text := ''x''', O), O.Reason);
  Assert.AreEqual('Format(''x%sy%s'', [c, Marker])', O.NewText);
end;

procedure TTestRdxSca044.Rewrite_MultiLineChain_Enabled;
var
  O : TRdxFormatOutcome;
begin
  // Ein Zeilenumbruch hat keine Bedeutung; der Ersatz ist einzeilig.
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := Marker + '' a '''#13#10 +
    '    + IntToStr(Id) + '' b '''#13#10 +
    '    + Tag;'),
    'Text := Marker', O), O.Reason);
  Assert.AreEqual('Format(''%s a %s b %s'', [Marker, IntToStr(Id), Tag])', O.NewText);
  Assert.IsFalse(O.Span.IsSingleLine);
  Assert.AreEqual<Integer>(O.Span.StartLine + 2, O.Span.EndLine);
  Assert.IsTrue(Pos(#10, O.Expected) > 0, 'Expected traegt die Umbrueche');
end;

procedure TTestRdxSca044.Rewrite_ControlCharsAndQuotes_Encoded;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := ''it''''s '' + Marker + #13#10 + ''b'' + Tag;'),
    'Text := ''it', O), O.Reason);
  Assert.AreEqual('Format(''it''''s %s''#13#10''b%s'', [Marker, Tag])', O.NewText);
end;

procedure TTestRdxSca044.Rewrite_PercentInLiteral_Escaped;
var
  O : TRdxFormatOutcome;
begin
  // Ein '%' im Literal wuerde Format zur Laufzeit stolpern lassen.
  Assert.IsTrue(RunRecipe(UnitWith(
    '  Text := ''Rabatt 5% '' + Marker + '' fuer '' + Tag;'),
    'Text := ''Rabatt', O), O.Reason);
  Assert.AreEqual('Format(''Rabatt 5%% %s fuer %s'', [Marker, Tag])', O.NewText);
end;

procedure TTestRdxSca044.Rewrite_ThenBranchWithoutSemicolon_Enabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsTrue(RunRecipe(UnitWith(
    '  if n > 0 then'#13#10 +
    '    Text := ''a'' + Marker + ''b'' + Tag'#13#10 +
    '  else'#13#10 +
    '    Text := '''';'),
    'Text := ''a''', O), O.Reason);
  Assert.AreEqual('''a'' + Marker + ''b'' + Tag', O.Expected,
    'der Bereich endet vor dem else, ohne Semikolon');
  Assert.AreEqual('Format(''a%sb%s'', [Marker, Tag])', O.NewText);
end;

{ ---- Rezept: ausgegraut mit Grund ---- }

procedure TTestRdxSca044.Rewrite_IntegerOperand_Disabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsFalse(RunRecipe(UnitWith(
    '  Text := ''a'' + n + ''b'' + Marker;'), 'Text := ''a''', O));
  Assert.IsTrue(Pos('kein String', O.Reason) > 0, O.Reason);
  Assert.IsTrue(Pos('integer', O.Reason) > 0, 'der deklarierte Typ steht im Grund: ' + O.Reason);
end;

procedure TTestRdxSca044.Rewrite_UnknownOperand_Disabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsFalse(RunRecipe(UnitWith(
    '  Text := ''a'' + Obj.ClassName + ''b'' + Marker;'), 'Text := ''a''', O));
  Assert.IsTrue(Pos('Typ unbekannt', O.Reason) > 0, O.Reason);
end;

procedure TTestRdxSca044.Rewrite_CommentInChain_Disabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsFalse(RunRecipe(UnitWith(
    '  Text := ''a'' + {alt} Marker + ''b'' + Tag;'), 'Text := ''a''', O));
  Assert.IsTrue(Pos('Kommentar', O.Reason) > 0, O.Reason);
end;

procedure TTestRdxSca044.Rewrite_InsideIfdef_Disabled;
var
  O : TRdxFormatOutcome;
begin
  // IFNDEF eines nie definierten Symbols: der Zweig ist aktiv, ob der
  // Lexer inaktive Zweige ueberspringt oder nicht - die Anweisung liegt
  // so oder so in einem bedingten Bereich.
  Assert.IsFalse(RunRecipe(UnitWith(
    '  {$IFNDEF RDX_NEVER_DEFINED}'#13#10 +
    '  Text := ''a'' + Marker + ''b'' + Tag;'#13#10 +
    '  {$ENDIF}'), 'Text := ''a''', O));
  Assert.IsTrue(Pos('IFDEF', O.Reason) > 0, O.Reason);
end;

procedure TTestRdxSca044.Rewrite_SqlText_Disabled;
var
  O : TRdxFormatOutcome;
begin
  // Lokale Variable als SQL-Puffer: SCA044 meldet, SCA003 auch - die
  // Umformung bleibt gesperrt (Vertrag im Kopf von uRefactorConcat).
  Assert.IsFalse(RunRecipe(UnitWith(
    '  Text := ''SELECT * FROM t WHERE id='' + IntToStr(Id) + '' AND n='' + QuotedStr(Tag);'),
    'Text := ''SELECT', O));
  Assert.IsTrue(Pos('SCA003', O.Reason) > 0, O.Reason);
end;

procedure TTestRdxSca044.Rewrite_MissingSysUtils_Disabled;
var
  Src : string;
  O   : TRdxFormatOutcome;
begin
  Src := StringReplace(UnitWith(
    '  Text := Marker + ''a'' + Tag + ''b'' + FName;'),
    'uses System.SysUtils;', 'uses System.Classes;', []);
  Assert.IsFalse(RunRecipe(Src, 'Text := Marker', O));
  Assert.IsTrue(Pos('SysUtils', O.Reason) > 0, O.Reason);
end;

procedure TTestRdxSca044.Rewrite_TwoAssignsOnLine_Disabled;
var
  O : TRdxFormatOutcome;
begin
  Assert.IsFalse(RunRecipe(UnitWith(
    '  Marker := ''x''; Text := ''a'' + Marker + ''b'' + Tag;'),
    'Text := ''a''', O));
  Assert.IsTrue(Pos('mehrdeutig', O.Reason) > 0, O.Reason);
end;

{ ---- Idempotenz ---- }

procedure TTestRdxSca044.Rewrite_AppliedOnce_NoSecondFinding;
var
  Src   : string;
  O, O2 : TRdxFormatOutcome;
  After : string;
begin
  Src := UnitWith(
    '  Text := Marker + ''id:'' + IntToStr(Id) + '' Milli: '' + IntToStr(n);');
  Assert.IsTrue(RunRecipe(Src, 'Text := Marker', O), O.Reason);
  // Die Ersetzung so anwenden, wie es der Editor taete: Bereichstext
  // durch den neuen Text.
  After := StringReplace(Src, O.Expected, O.NewText, []);
  Assert.IsTrue(Pos('Format(', After) > 0);
  Assert.AreEqual<Integer>(0, DetectorFindings(After),
    'nach dem Umschreiben meldet SCA044 nichts mehr');
  Assert.IsFalse(RunRecipe(After, 'Text := Format', O2),
    'ein zweiter Lauf hat nichts mehr umzuformen');
end;

initialization
  Randomize;
  TDUnitX.RegisterTestFixture(TTestRdxSca044);

end.
