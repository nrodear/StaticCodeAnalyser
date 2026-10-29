unit uTestRdxSimpleFixes;

// Editorhilfen Stufe 2a: die Planer SCA075/SCA085 (dazu Stufe 2, Rest:
// SCA074/SCA087/SCA139) aus uRdxSimpleFixes auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im
// FPC-Pruefstand). Jeder Fall prueft den Text NACH der Ersetzung
// (PlanByteEdits + ApplyByteEdits, CRLF wie im Editor) bzw. die Ablehnung.
// Die Faelle stammen aus dem Analyse-Workflow editorhilfen-2a-analyse
// (2026-10-09): je Regel die gemeldeten Varianten und die Fallen.
//
// SCA126 steht in uTestRdxNilFix. Die Gegenprobe mit dem echten Detektor
// steht in uTestRdxSimpleFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSimpleFixes = class
  public
    // ---- SCA075 ----
    [Test] procedure Sca075_Variants;
    [Test] procedure Sca075_EmptyShortForm_BecomesClassEnd;
    [Test] procedure Sca075_OnlyTheReportedOccurrence;
    [Test] procedure Sca075_Refusals;
    [Test] procedure Sca075_MultiLineString_Untouched;
    // ---- SCA085 ----
    [Test] procedure Sca085_Variants;
    [Test] procedure Sca085_CommentTrap_UsesCodeOccurrence;
    [Test] procedure Sca085_Refusals;
    [Test] procedure Sca085_DirectiveBeforeFree_Refused;
    // Gegen-Review R8 (Major 2): '{$' hinter '//' ist keine Direktive.
    [Test] procedure Sca085_LineCommentDirective_NotADirective;
    [Test] procedure Sca085_VariableContext;
    // ---- SCA085, Realwelt-Test rwE30 (Fix-Runde 2) ----
    [Test] procedure Sca085_DirectiveBranches;
    [Test] procedure Sca085_NilLineComment;
    [Test] procedure Sca085_NameInCaptionWhenRefused;
    [Test] procedure Sca085_WithScope;
    [Test] procedure Sca085_VariableProof_Local;
    [Test] procedure Sca085_VariableProof_FieldAndGlobal;
    [Test] procedure Sca085_VariableProof_Refused;
    [Test] procedure Sca085_OldCompilerBranch;
    // ---- Stufe 2, Rest: SCA074, SCA087, SCA139 ----
    [Test] procedure Sca074_Variants;
    [Test] procedure Sca074_Refusals;
    [Test] procedure Sca074_DeclaresRoutine;
    [Test] procedure Sca087_Variants;
    [Test] procedure Sca087_Refusals;
    [Test] procedure Sca139_Variants;
    [Test] procedure Sca139_Refusals;
    [Test] procedure Sca139_DeclaresNonClassType;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxSimpleFixes,
  uRdxTypeProof,     // DeclaresProperty, DeclaresRoutine ... (Folgewelle A4)
  uTestRdxTextKit;   // Join, Apply

// ---- Helfer ----

// SCA075 auf einer Zeile: liefert den neuen Text der ganzen Quelle oder
// '' bei Ablehnung (AReason).
function Fix075(const ASource: string; ALine, ACol: Integer;
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
    if TRdxSimpleFixes.ExplicitTObject(Map, ALine,
         Format('`class(TObject)` at column %d - drop the parens', [ACol]), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function Fix085(const ASource: string; ALine: Integer; out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
  Name_ : string;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxSimpleFixes.FreeAndNilFix(Map, ALine, Edits, Name_, AReason) then
      Result := Apply(ASource, Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function Fix074(const ASource: string; ALine, ACol: Integer;
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
    if TRdxSimpleFixes.AssertMessage(Map, ALine,
         Format('Assert at column %d has no message - add a "why" string '
           + 'for easier diagnosis.', [ACol]), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA087 mit der Meldung des Detektors fuer den Abschnitt ASection.
function Fix087(const ASource: string; ALine: Integer; const ASection: string;
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
    if TRdxSimpleFixes.EmptySection(Map, ALine,
         Format('Empty `%s` section - delete the section header or add '
           + 'its members.', [ASection]), E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function Fix139(const ASource: string; ALine: Integer; const AReceiver: string;
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
    if TRdxSimpleFixes.FreeOnly(Map, ALine, AReceiver, E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Zeile in einer kleinen Unit (Zeile 4).
function InUnit(const ALine: string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;', ALine,
    'end.']);
end;

// ---- SCA075 ----

procedure TTestRdxSimpleFixes.Sca075_Variants;
const
  CASES: array[0..5, 0..1] of string = (
    ('  TFoo = class(TObject)', '  TFoo = class'),
    ('  TFoo = class ( TObject )', '  TFoo = class'),
    ('  TFoo = class'#9'('#9'TObject'#9')', '  TFoo = class'),
    ('  TFoo = CLASS(tobject)', '  TFoo = CLASS'),
    ('  TFoo = class(TObject) // Basis', '  TFoo = class // Basis'),
    ('type TFoo = class(TObject)end;', 'type TFoo = class end;'));
var
  i : Integer;
  R : string;
begin
  for i := 0 to High(CASES) do
    Assert.AreEqual(InUnit(CASES[i, 1]),
      Fix075(InUnit(CASES[i, 0]), 4, Pos('lass', LowerCase(CASES[i, 0])) - 1, R),
      Format('Fall %d: %s', [i, R]));
end;

procedure TTestRdxSimpleFixes.Sca075_EmptyShortForm_BecomesClassEnd;
var
  R : string;
begin
  // 'class;' waere eine Vorwaertsdeklaration - die Hilfe schreibt 'class end'.
  Assert.AreEqual(InUnit('  EFoo = class end;'),
    Fix075(InUnit('  EFoo = class(TObject);'), 4, 10, R), R);
  // ';' erst in der Folgezeile
  Assert.AreEqual(Join(['unit u;', 'implementation', 'procedure P;',
      '  EFoo = class end', '  ;', 'end.']),
    Fix075(Join(['unit u;', 'implementation', 'procedure P;',
      '  EFoo = class(TObject)', '  ;', 'end.']), 4, 10, R), R);
end;

procedure TTestRdxSimpleFixes.Sca075_OnlyTheReportedOccurrence;
var
  R   : string;
  Src : string;
begin
  // Ein Vorkommen im Kommentar davor bleibt stehen.
  Src := '  { class(TObject) } TFoo = class(TObject)';
  Assert.AreEqual(InUnit('  { class(TObject) } TFoo = class'),
    Fix075(InUnit(Src), 4, 29, R), R);
  // Generic: das zweite 'class' ist das gemeldete.
  Src := '  TFoo<T: class> = class(TObject)';
  Assert.AreEqual(InUnit('  TFoo<T: class> = class'),
    Fix075(InUnit(Src), 4, 20, R), R);
  // Umlaut vor der Stelle: Spalten in UTF-16-Einheiten.
  Src := '  T' + #$00C4 + 'rger = class(TObject)';
  Assert.AreEqual(InUnit('  T' + #$00C4 + 'rger = class'),
    Fix075(InUnit(Src), 4, Pos('class', Src), R), R);
end;

procedure TTestRdxSimpleFixes.Sca075_Refusals;
var
  R : string;
begin
  // Je Ablehnung auch der Grund (Review R6-04): ein Test ohne ihn bliebe
  // gruen, wenn eine andere Sperre greift oder eine Sperre nie erreicht wird.
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject) procedure P; end;'), 4, 10, R),
    'Rumpf in derselben Zeile');
  Assert.IsTrue(Pos('Klassenrumpf beginnt in derselben Zeile', R) > 0, R);
  // 'class(TObject, IFoo)' meldet der Detektor nicht - steht es an der
  // Stelle, hat sich die Zeile seit dem Scan geaendert.
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject, IFoo)'), 4, 10, R),
    'nie class(IFoo)');
  Assert.IsTrue(Pos('nicht mehr an der gemeldeten Stelle', R) > 0, R);
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TComponent)'), 4, 10, R),
    'Puffer geaendert');
  Assert.IsTrue(Pos('nicht mehr an der gemeldeten Stelle', R) > 0, R);
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 11, R),
    'falsche Spalte');
  Assert.IsTrue(Pos('nicht mehr an der gemeldeten Stelle', R) > 0, R);
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 0, R),
    'keine Spalte in der Meldung');
  Assert.IsTrue(Pos('Spalte fehlt in der Meldung', R) > 0, R);
  // Die Spalte liegt hinter dem Ende der (inzwischen gekuerzten) Zeile: die
  // Meldung hat ihre Spalte, die Zeile hat sich geaendert (Review R3,
  // verpasst - bis Charge FC hiess es auch hier 'Spalte fehlt').
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class'), 4, 30, R),
    'Spalte hinter dem Zeilenende');
  Assert.IsTrue(Pos('nicht mehr an der gemeldeten Stelle', R) > 0, R);
end;

// ---- SCA085 ----

function FreeNil(const AFree, ANil: string): string;
begin
  Result := Join(['unit u;', 'procedure P;', 'begin', AFree, ANil, 'end;', 'end.']);
end;

function FreeOnly(const AFree: string): string;
begin
  Result := Join(['unit u;', 'procedure P;', 'begin', AFree, 'end;', 'end.']);
end;

procedure TTestRdxSimpleFixes.Sca085_Variants;
var
  R : string;
begin
  Assert.AreEqual(FreeOnly('  FreeAndNil(L);'),
    Fix085(FreeNil('  L.Free;', '  L := nil;'), 4, R), R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(fObj);'),
    Fix085(FreeNil('  fObj.Free;', '  FOBJ := NIL;'), 4, R), 'Gross/Klein: ' + R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(L) ;'),
    Fix085(FreeNil('  L. Free ;', '  L:=nil'), 4, R), 'Leerraum, ohne ";": ' + R);
  Assert.AreEqual(FreeOnly('  FreeAndNil(L); // weg'),
    Fix085(FreeNil('  L.Free; // weg', '  L := nil;'), 4, R), 'Kommentar bleibt: ' + R);
end;

procedure TTestRdxSimpleFixes.Sca085_CommentTrap_UsesCodeOccurrence;
var
  R   : string;
  Src : string;
begin
  // Das 'Old.Free;' im Kommentar darf NICHT umgeschrieben werden (der
  // alte uQuickFix tat genau das).
  Src := Join(['unit u;', 'procedure P;', 'begin', '  { alt',
    '  Old.Free; }  L.Free;', '  L := nil;', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'procedure P;', 'begin', '  { alt',
    '  Old.Free; }  FreeAndNil(L);', 'end;', 'end.']), Fix085(Src, 5, R), R);
end;

procedure TTestRdxSimpleFixes.Sca075_MultiLineString_Untouched;
const
  Q3 = #39#39#39;   // Delphi 12: mehrzeiliger String
var
  Src, R : string;
begin
  // Der zeilenweise Detektor meldet auch IM String; die Code-Sicht kennt
  // ''' ... ''' und lehnt dort ab - hinter dem String gilt wieder Code.
  Src := Join(['unit u;', 'interface', 'const',
    '  CTemplate = ' + Q3,
    '    TFoo = class(TObject)',
    '    end;',
    '    ' + Q3 + ';',
    'type',
    '  TBar = class(TObject)',
    '  end;',
    'implementation', 'end.']);
  Assert.AreEqual('', Fix075(Src, 5, 12, R), 'im mehrzeiligen String');
  Assert.IsTrue(Pos('String', R) > 0, R);
  Assert.AreEqual(StringReplace(Src, 'TBar = class(TObject)', 'TBar = class', []),
    Fix075(Src, 9, 10, R), R);
end;

procedure TTestRdxSimpleFixes.Sca085_DirectiveBeforeFree_Refused;
var
  R : string;
begin
  // Ohne LOG steht X.Free; allein hinter 'then' - das nil wuerde bedingt.
  Assert.AreEqual('', Fix085(Join(['unit u;', 'procedure P;', 'begin',
    '  if FOwns then',
    '    {$IFDEF LOG}Log(''free'');{$ENDIF}',
    '    X.Free;',
    '  X := nil;', 'end;', 'end.']), 6, R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', Fix085(Join(['unit u;', 'procedure P;', 'begin',
    '  if FOwns then',
    '{$IFDEF LOG}',
    '    Log(''free'');',
    '{$ENDIF}',
    '    X.Free;',
    '  X := nil;', 'end;', 'end.']), 8, R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca085_LineCommentDirective_NotADirective;
var
  R : string;
begin
  // DirectiveBetween prueft seit Charge R8 DirectiveAt (uRdxCodeMap): ein
  // '{$' hinter '//' ist keine Direktive. Bis dahin zaehlte jedes '{$' im
  // Kommentar vor X.Free; mit - ein auskommentiertes IFDEF sperrte die
  // Hilfe (Gegen-Review R8, Major 2).
  Assert.AreEqual(Join(['unit u;', 'procedure P;', 'begin',
      '  // {$IFDEF A}', '  FreeAndNil(X);', 'end;', 'end.']),
    Fix085(Join(['unit u;', 'procedure P;', 'begin',
      '  // {$IFDEF A}', '  X.Free;', '  X := nil;', 'end;', 'end.']), 5, R), R);
  // Hinter X.Free; darf ein //-Kommentar stehen - auch mit '{$' darin.
  Assert.AreEqual(FreeOnly('  FreeAndNil(X); // {$IFDEF A}'),
    Fix085(FreeNil('  X.Free; // {$IFDEF A}', '  X := nil;'), 4, R), R);
  // Gegenprobe: eine echte Blockdirektive davor bleibt gesperrt - seit
  // rwE30 nur, wenn ohne ihren Block 'then' davor stuende
  // (Sca085_DirectiveBranches).
  Assert.AreEqual('', Fix085(Join(['unit u;', 'procedure P;', 'begin',
    '  if A then', '  {$IFDEF A}Log;{$ENDIF}', '  X.Free;', '  X := nil;',
    'end;', 'end.']), 6, R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca085_VariableContext;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',                                          // 1
      'type',                                             // 2
      '  TFoo = class',                                   // 3
      '    property Items: TList read FList write FList;', // 4
      '  end;',                                           // 5
      'implementation',                                   // 6
      'procedure TFoo.A;',                                // 7
      'begin',                                            // 8
      '  var L := TList.Create;',                         // 9
      '  L.Free;',                                        // 10
      'end;',                                             // 11
      'procedure TFoo.B;',                                // 12
      'begin',                                            // 13
      '  with FData do',                                  // 14
      '  begin',                                          // 15
      '    List.Free;',                                   // 16
      '  end;',                                           // 17
      'end;',                                             // 18
      'procedure TFoo.C;',                                // 19
      '  procedure Inner;',                               // 20
      '  begin',                                          // 21
      '  end;',                                           // 22
      'begin',                                            // 23
      '  M.Free;',                                        // 24
      'end;',                                             // 25
      '// with { with } ''with''',                        // 26
      'procedure TFoo.D;',                                // 27
      'begin',                                            // 28
      '  N.Free;',                                        // 29
      'end;',                                             // 30
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxTypeProof.DeclaresProperty(Map, 'Items'));
    Assert.IsTrue(TRdxTypeProof.DeclaresProperty(Map, 'ITEMS'), 'ohne Gross/Klein');
    Assert.IsFalse(TRdxTypeProof.DeclaresProperty(Map, 'FList'));
    Assert.IsTrue(TRdxSimpleFixes.DeclaresInlineVar(Map, 10, 'L'));
    Assert.IsFalse(TRdxSimpleFixes.DeclaresInlineVar(Map, 10, 'M'));
    Assert.IsFalse(TRdxSimpleFixes.DeclaresInlineVar(Map, 24, 'L'),
      'Inline-Variable einer anderen Routine');
    Assert.IsTrue(TRdxSimpleFixes.WithBefore(Map, 16));
    Assert.IsFalse(TRdxSimpleFixes.WithBefore(Map, 24), 'with einer frueheren Routine');
    Assert.IsFalse(TRdxSimpleFixes.WithBefore(Map, 10));
    Assert.IsFalse(TRdxSimpleFixes.WithBefore(Map, 29), 'with nur in Kommentar/String');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- SCA085, Realwelt-Test rwE30 (Fix-Runde 2) ----

// Eine Unit u mit leerem interface-Teil; ALines ist der implementation-Teil.
function InImplementation(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// SCA085 im Rumpf von P (InProc) auf der Zeile mit AFreeText; '' bei
// Ablehnung (AReason).
function Fix085In(const ALines: array of string; const AFreeText: string;
  out AReason: string): string;
var
  Src : string;
begin
  Src := InProc(ALines);
  Result := Fix085(Src, LineOf(Src, AFreeText), AReason);
end;

// Der Text nach der Hilfe: AFreeLine wird AFixed, die Zeile danach (nil)
// entfaellt.
function Fixed085(const ALines: array of string; const AFreeLine,
  AFixed: string): string;
var
  SL : TStringList;
  i  : Integer;
begin
  SL := TStringList.Create;
  try
    SL.Text := InProc(ALines);
    i := SL.IndexOf(AFreeLine);
    SL[i] := AFixed;
    SL.Delete(i + 1);
    Result := TrimRight(SL.Text);
  finally
    SL.Free;
  end;
end;

procedure TTestRdxSimpleFixes.Sca085_DirectiveBranches;
const
  // gexperts GX_EditorEnhancements.pas:287 - ein geschlossener Einzeiler.
  IFOPT_LINE: array[0..3] of string = ('  RemoveToolBar;',
    '  {$IFOPT D+}SendDebug(''Freeing toolbar list''); {$ENDIF}',
    '  FToolBarList.Free;', '  FToolBarList := nil;');
  // GX_ClassBrowser.pas:393 - das ENDIF schliesst den Block davor.
  CLOSED_BLOCK: array[0..5] of string = ('  {$IFNDEF STANDALONE}',
    '  ProjectNotifier.Free;', '  ProjectNotifier := nil;',
    '  {$ENDIF STANDALONE}', '  FClassList.Free;', '  FClassList := nil;');
  // gexperts FileView.pas:131 - Free und nil im selben Zweig.
  SAME_BRANCH: array[0..3] of string = ('  {$IFDEF SYNTAXMEMO}',
    '  FSyntaxEd.Free;', '  FSyntaxEd := nil;', '  {$ENDIF}');
  // Alcinoe.Common.pas:4355 - im ELSE-Zweig, der Zweig davor endet auf end;.
  ELSE_BRANCH: array[0..8] of string = ('  {$IF defined(ALDPK)}',
    '  if Temp <> nil then', '  begin', '    Temp.DisposeOf;',
    '    Temp := nil;', '  end;', '  {$ELSE}', '  Temp.Free;',
    '  Temp := nil;');
var
  R : string;
begin
  Assert.AreEqual(Fixed085(IFOPT_LINE, '  FToolBarList.Free;',
      '  FreeAndNil(FToolBarList);'),
    Fix085In(IFOPT_LINE, 'FToolBarList.Free', R), R);
  Assert.AreEqual(Fixed085(CLOSED_BLOCK, '  FClassList.Free;',
      '  FreeAndNil(FClassList);'),
    Fix085In(CLOSED_BLOCK, 'FClassList.Free', R), R);
  Assert.AreEqual(Fixed085(SAME_BRANCH, '  FSyntaxEd.Free;',
      '  FreeAndNil(FSyntaxEd);'),
    Fix085In(SAME_BRANCH, 'FSyntaxEd.Free', R), R);
  Assert.AreEqual(Fixed085(ELSE_BRANCH, '  Temp.Free;',
      '  FreeAndNil(Temp);'),
    Fix085In(ELSE_BRANCH, 'Temp.Free', R), R);
  // Gegenproben - eine Konfiguration stellt X.Free; hinter then:
  // ohne A (ELSE-Zweig, davor 'if C then' vor dem IFDEF) ...
  Assert.AreEqual('', Fix085In(['  if C then', '{$IFDEF A}', '    Foo;',
    '{$ELSE}', '    X.Free;', '  X := nil;', '{$ENDIF}'], 'X.Free', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  // ... mit A (der Zweig vor dem ELSE-Trenner endet auf then) ...
  Assert.AreEqual('', Fix085In(['  {$IFDEF A}', '  if C then', '  {$ELSE}',
    '  Foo;', '  {$ENDIF}', '  X.Free;', '  X := nil;'], 'X.Free', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  // ... mit A, ohne B (verschachtelt) ...
  Assert.AreEqual('', Fix085In(['  {$IFDEF A}', '  if C then',
    '  {$IFDEF B}Log;{$ENDIF}', '  {$ENDIF}', '  X.Free;', '  X := nil;'],
    'X.Free', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  // ... und ein Include kann Code bringen.
  Assert.AreEqual('', Fix085In(['  if C then Foo;', '  {$I extra.inc}',
    '  X.Free;', '  X := nil;'], 'X.Free', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca085_NilLineComment;
var
  R : string;
begin
  // PascalScript_2009 uPSCompiler.pas:11213 - ein leerer Kommentar geht mit.
  Assert.AreEqual(FreeOnly('  FreeAndNil(FUnitInits); //nvds'),
    Fix085(FreeNil('  FUnitInits.Free; //nvds', '  FUnitInits := nil;    //'),
      4, R), R);
  // HeidiSQL main.pas:2778 - ein Text wandert an die FreeAndNil-Zeile.
  Assert.AreEqual(FreeOnly(
      '  FreeAndNil(frmPreferences); // Important in SetupSynEditors'),
    Fix085(FreeNil('  frmPreferences.Free;',
      '  frmPreferences := nil; // Important in SetupSynEditors'), 4, R), R);
  // Gegenproben: der Kommentar nennt FreeAndNil, die Free-Zeile hat schon
  // einen, ein {..}-Kommentar.
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;',
    '  X := nil; // no FreeAndNil here'), 4, R));
  Assert.IsTrue(Pos('Kommentar oder String in der nil-Zeile', R) > 0, R);
  Assert.AreEqual('', Fix085(FreeNil('  X.Free; // a', '  X := nil; // b'),
    4, R));
  Assert.IsTrue(Pos('Kommentar oder String in der nil-Zeile', R) > 0, R);
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  X := nil; {b}'), 4, R));
  Assert.IsTrue(Pos('Kommentar oder String in der nil-Zeile', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca085_NameInCaptionWhenRefused;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
  Name_ : string;
  R     : string;
begin
  // Auch eine Sperre hinter dem Treffer nennt X (Menuetext 'FreeAndNil(X)'
  // statt 'FreeAndNil(FSelImage)', rwE30).
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := FreeNil('  FSelImage.Free;', '  FSelImage := nil; Y := 0;');
    Map := TRdxCodeMap.Create(SL);
    Assert.IsFalse(TRdxSimpleFixes.FreeAndNilFix(Map, 4, Edits, Name_, R));
    Assert.AreEqual('FSelImage', Name_, R);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// WithBefore an der Zeile mit AText in ASource.
function WithAt(const ASource, AText: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxSimpleFixes.WithBefore(Map, LineOf(ASource, AText));
  finally
    Map.Free;
  end;
end;

procedure TTestRdxSimpleFixes.Sca085_WithScope;
var
  Src : string;
begin
  // uPSCompiler.pas (PascalScript) CheckFurther: die with-Bloecke davor
  // sind zu, eine verschachtelte Routine davor traegt eins - die Zeile
  // liegt in keinem with-Rumpf.
  Src := Join(['unit u;', 'interface', 'implementation',
    'procedure TComp.ProcessSub;',
    '  procedure Sibling;',
    '  begin',
    '    with A do Foo;',
    '  end;',
    '  procedure CheckFurther(var x: TPSValue);',
    '  var',
    '    R: record case Integer of 0: (a: Integer); 1: (b: Byte); end;',
    '  begin',
    '    with tmp3.Parameters.Add do',
    '    begin',
    '      ExpectedType := nil;',
    '    end;',
    '    with B do Bar;',
    '    if x = nil then',
    '    begin',
    '      x.Free; // line A',
    '      x := nil;',
    '    end;',
    '  end;',
    'begin',
    'end;', 'end.']);
  Assert.IsFalse(WithAt(Src, 'line A'), 'with davor geschlossen');
  // Gegenproben: ein with-Rumpf umfasst die Zeile.
  Assert.IsTrue(WithAt(InProc(['  with A do', '  begin', '    Foo;',
    '    X.Free;', '  end;']), 'X.Free'), 'begin..end');
  Assert.IsTrue(WithAt(InProc(['  with A do', '    if C then', '      X.Free;']),
    'X.Free'), 'Einzelanweisung if');
  Assert.IsTrue(WithAt(InProc(['  with A do', '  try', '    Foo;', '    X.Free;',
    '  finally', '  end;']), 'X.Free'), 'try');
  Assert.IsTrue(WithAt(InProc(['  with A do', '  repeat', '    Foo;',
    '    X.Free;', '  until C;']), 'X.Free'), 'repeat');
  Assert.IsTrue(WithAt(InProc(['  with A, B do Foo(procedure(a: Integer; b: Byte)',
    '    begin', '      Bar;', '      X.Free;', '    end);']), 'X.Free'),
    'anonyme Methode mit ; in der Parameterliste');
  Assert.IsTrue(WithAt(InProc(['  with A do X.Free;']), 'X.Free'),
    'with auf der Zeile');
  Assert.IsTrue(WithAt(InProc(['  with A do', '    with B do', '    begin',
    '      Foo;', '      X.Free;', '    end;']), 'X.Free'), 'with in with');
  // Gegenproben zur Gegenprobe: der Rumpf ist zu Ende.
  Assert.IsFalse(WithAt(InProc(['  with A do Foo;', '  X.Free;']), 'X.Free'),
    'Einzelanweisung zu Ende');
  Assert.IsFalse(WithAt(InProc(['  with A do', '  begin', '    Foo;', '  end;',
    '  X.Free;']), 'X.Free'), 'begin..end zu Ende');
  Assert.IsFalse(WithAt(InProc(['  with A do', '  case K of', '    1: Foo;',
    '  end;', '  X.Free;']), 'X.Free'), 'case..end zu Ende');
end;

// VariableProof an der Zeile mit AText.
function ProofAt(const ASource, AText, AName: string): TRdxVarProof;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxSimpleFixes.VariableProof(Map, LineOf(ASource, AText), AName);
  finally
    Map.Free;
  end;
end;

procedure AssertProof(const ASource, AText, AName: string;
  AKind: TRdxVarProofKind; const ATypeLow, AWhat: string);
var
  P : TRdxVarProof;
begin
  P := ProofAt(ASource, AText, AName);
  Assert.IsTrue(P.Kind = AKind, AWhat + ': Art ' + IntToStr(Ord(P.Kind)));
  Assert.AreEqual(ATypeLow, P.TypeLow, AWhat);
end;

procedure TTestRdxSimpleFixes.Sca085_VariableProof_Local;
var
  Src : string;
begin
  // uPSCompiler.pas: var-Parameter einer verschachtelten Routine, auch
  // wenn die Unit eine Property gleichen Namens deklariert (Val).
  Src := Join(['unit u;', 'interface', 'type',
    '  TPSParameter = class', '    property Val: TPSValue read FVal;',
    '  end;', 'implementation',
    'function TPSPascalCompiler.ProcessSub(B: TBlock): Boolean;',
    '  procedure CheckNotificationVariant(var Val: TPSValue);',
    '  begin',
    '    Val.Free; // A',
    '    Val := nil;',
    '  end;',
    '  function GetIdentifier(const FType: Byte): TPSValue;',
    '  var',
    '    tmp3: TPSValue;',
    '    procedure CheckFurther(var x: TPSValue; ImplicitPeriod: Boolean);',
    '    var',
    '      t: TPSType;',
    '    begin',
    '      x.Free; // B',
    '      x := nil;',
    '    end;',
    '  begin',
    '    Result := nil;',
    '    Result.Free; // C',
    '    tmp3.Free; // D',
    '  end;',
    'begin',
    'end;', 'end.']);
  AssertProof(Src, '// A', 'Val', vpLocal, 'tpsvalue', 'Parameter vor Property');
  AssertProof(Src, '// B', 'x', vpLocal, 'tpsvalue', 'var-Parameter, verschachtelt');
  AssertProof(Src, '// C', 'Result', vpLocal, 'tpsvalue', 'Result der function');
  AssertProof(Src, '// D', 'tmp3', vpLocal, 'tpsvalue', 'lokale Variable');
  // MVCFramework.AsyncTask.pas:103 - eine anonyme Methode faengt die
  // lokale Variable (andere Schreibweise).
  Src := InImplementation(['procedure TAsync.Run<T>;', 'var',
    '  LRes: T;', 'begin',
    '  TTask.Run(procedure', '    begin', '      lRes.Free; // E',
    '      lRes := nil;', '    end);', 'end;']);
  AssertProof(Src, '// E', 'lRes', vpLocal, 't', 'gefangen in anonymer Methode');
end;

procedure TTestRdxSimpleFixes.Sca085_VariableProof_FieldAndGlobal;
var
  Src : string;
begin
  // uPSCompiler.pas: ein Feld der Klasse in der verschachtelten Routine
  // Cleanup von TPSPascalCompiler.Compile; gexperts GX_PeInfo.pas: ein
  // lokaler resourcestring-Abschnitt; JvSpin.pas: das Feld unter IFDEF.
  Src := Join(['unit u;', 'interface', 'type',
    '  TPSPascalCompiler = class(TObject)', '  private',
    '    FVars: TPSList;',
    '  {$IFDEF WIN32}', '    FUpDown: TCustomUpDown;', '  {$ENDIF}',
    '    procedure Compile;', '    procedure Load;', '  end;',
    'var', '  fmGrepResults: TfmGrepResults = nil;',
    'implementation', 'threadvar', '  ALStack: TALStack;',
    'procedure TPSPascalCompiler.Compile;',
    '  procedure Cleanup;', '  begin', '    FVars.Free; // A',
    '    FVars := nil;', '  end;', 'begin', 'end;',
    'procedure TPSPascalCompiler.Load;', 'resourcestring',
    '  SCaption = ''x'';', 'var', '  I: Integer;', 'begin',
    '  FUpDown.Free; // B', '  fmGrepResults.Free; // C',
    'end;', 'procedure Done;', 'begin', '  ALStack.Free; // D', 'end;',
    'finalization', '  fmGrepResults.Free; // E', 'end.']);
  AssertProof(Src, '// A', 'FVars', vpField, 'tpslist', 'Feld in verschachtelter Routine');
  AssertProof(Src, '// B', 'FUpDown', vpField, 'tcustomupdown', 'Feld unter IFDEF');
  AssertProof(Src, '// C', 'fmGrepResults', vpGlobal, 'tfmgrepresults',
    'Global mit Anfangswert in einer Methode');
  AssertProof(Src, '// D', 'ALStack', vpGlobal, 'talstack', 'threadvar');
  AssertProof(Src, '// E', 'fmGrepResults', vpGlobal, 'tfmgrepresults',
    'finalization');
  // cnwizards TestProgram.pas: Hauptblock eines Programms.
  Src := Join(['program p;', 'uses SysUtils;', 'var',
    '  CMandalaSettings: TSettings;', 'procedure Run;', 'begin', 'end;',
    'begin', '  Run;', '  CMandalaSettings.Free; // A',
    '  CMandalaSettings := nil;', 'end.']);
  AssertProof(Src, '// A', 'CMandalaSettings', vpGlobal, 'tsettings',
    'Programm-Hauptblock');
end;

procedure TTestRdxSimpleFixes.Sca085_VariableProof_Refused;
var
  Src : string;
begin
  // Pin missed R2(3): ein Global, das wie ein geerbtes Member heisst, ist in
  // einer Methode einer TForm-Ableitung nicht bewiesen.
  Src := Join(['unit u;', 'interface', 'type',
    '  TForm1 = class(TForm)', '    procedure Done;', '  end;', 'var',
    '  Owner: TObject;', 'implementation',
    'procedure TForm1.Done;', 'begin', '  Owner.Free; // A', 'end;', 'end.']);
  AssertProof(Src, '// A', 'Owner', vpNone, '', 'Global in TForm-Ableitung');
  // Review e/HilfeFixI: ein class helper hat keine Vorfahrenliste - Self
  // ist die erweiterte Klasse (TStrings), ihr Member verdeckte das Global.
  // Bis dahin vpGlobal ('class' ohne Vorfahren galt als TObject).
  Src := Join(['unit u;', 'interface', 'type',
    '  TListHelper = class helper for TStrings', '    procedure Done;',
    '  end;', 'var', '  Cache: TObject;', 'implementation',
    'procedure TListHelper.Done;', 'begin', '  Cache.Free; // G', 'end;',
    'end.']);
  AssertProof(Src, '// G', 'Cache', vpNone, '', 'Global im class helper');
  // Gegenprobe: dieselbe Methode einer Klasse ohne Vorfahren beweist es.
  AssertProof(StringReplace(Src, 'class helper for TStrings', 'class', []),
    '// G', 'Cache', vpGlobal, 'tobject', 'Global in Klasse ohne Vorfahren');
  // Eine lokale Variable der aeusseren Routine HINTER der verschachtelten
  // ist dort unsichtbar - der Quellstellen-Dienst saehe sie: offen.
  Src := InImplementation(['procedure Outer;',
    '  procedure Inner;', '  begin', '    X.Free; // B', '  end;',
    'var', '  X: TObject;', 'begin', 'end;']);
  AssertProof(Src, '// B', 'X', vpNone, '', 'spaetere Deklaration');
  // Ein Parameter einer anonymen Methode gleichen Namens.
  Src := InImplementation(['procedure Outer;', 'var', '  X: TObject;',
    'begin', '  Run(procedure(X: TFoo)', '    begin', '      X.Free; // C',
    '    end);', 'end;']);
  AssertProof(Src, '// C', 'X', vpNone, '', 'Parameter der anonymen Methode');
  // Eine Inline-Variable verdeckt den Parameter.
  Src := InImplementation(['procedure Outer(X: TObject);', 'begin',
    '  begin', '    var X: TFoo := nil;', '    X.Free; // D', '  end;',
    'end;']);
  AssertProof(Src, '// D', 'X', vpNone, '', 'Inline-Variable');
  // Eine lokale Konstante ist keine Variable; ein class var kein Global.
  Src := Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    class var Shared: TObject;', '  end;', 'implementation',
    'procedure Done;', 'const', '  K: TObject = nil;', 'begin',
    '  K.Free; // E', '  Shared.Free; // F', 'end;', 'end.']);
  AssertProof(Src, '// E', 'K', vpNone, '', 'lokale Konstante');
  AssertProof(Src, '// F', 'Shared', vpNone, '', 'class var');
end;

procedure TTestRdxSimpleFixes.Sca085_OldCompilerBranch;
const
  FREE_NIL: array[0..1] of string = ('  X.Free;', '  X := nil;');
var
  R : string;

  function Around(const AOpen, AElse: string): string;
  begin
    if AElse = '' then
      Result := Fix085In([AOpen, FREE_NIL[0], FREE_NIL[1], '{$ENDIF}'],
        'X.Free', R)
    else
      Result := Fix085In([AOpen, '  Foo;', AElse, FREE_NIL[0], FREE_NIL[1],
        '{$ENDIF}'], 'X.Free', R);
  end;

begin
  // gexperts GX_Actions.pas:315 (nur Delphi 4) und JvDBCtrl.pas:1089
  // (16-Bit-Delphi 1): FreeAndNil gibt es dort nicht.
  Assert.AreEqual('', Fix085In(['{$IFNDEF GX_VER130_up}', '{$IFDEF GX_VER120_up}',
    FREE_NIL[0], FREE_NIL[1], '{$ENDIF}', '{$ENDIF}'], 'X.Free', R));
  Assert.IsTrue(Pos('{$IFNDEF GX_VER130_up}', R) > 0, R);
  Assert.AreEqual('', Around('{$IFNDEF WIN32}', ''));
  Assert.IsTrue(Pos('WIN32', R) > 0, R);
  Assert.AreEqual('', Around('{$IFDEF COMPILER5_UP}', '{$ELSE}'));
  Assert.IsTrue(Pos('COMPILER5_UP', R) > 0, R);
  Assert.AreEqual('', Around('{$IFDEF VER120}', ''));
  Assert.AreEqual('', Around('{$IF CompilerVersion < 13}', ''));
  // Gegenproben: der Zweig gilt (auch) fuer moderne Compiler - oder nur
  // fuer alte, die FreeAndNil schon kennen (Delphi 6 bis 2007).
  Assert.AreNotEqual('', Around('{$IFNDEF COMPILER12_UP}', ''), R);
  Assert.AreNotEqual('', Around('{$IF CompilerVersion < 14}', ''), R);
  Assert.AreNotEqual('', Around('{$IFDEF COMPILER6_UP}', ''), R);
  Assert.AreNotEqual('', Around('{$IFNDEF COMPILER6_UP}', '{$ELSE}'), R);
  Assert.AreNotEqual('', Around('{$IFDEF VER150}', ''), R);
  Assert.AreNotEqual('', Around('{$IFDEF DEBUG}', ''), R);
  Assert.AreNotEqual('', Around('{$IFNDEF DEBUG}', ''), R);
end;

procedure TTestRdxSimpleFixes.Sca085_Refusals;
const
  // Zeile vor X.Free; - das nil wuerde bedingt
  GUARDS: array[0..4] of string = ('  if FOwns then', '  else',
    '  with FData do', '  for I := 0 to 1 do', '  1:');
  // Je Ablehnung auch der Grund (Review R6-04): ohne ihn blieb gruen, dass
  // die Kommentar-Sperre nie griff - nach einem frischen Scan hiess es
  // 'X.Free; steht nicht mehr an der gemeldeten Stelle'. Spalten:
  // Free-Zeile, nil-Zeile, Grund.
  CASES: array[0..9, 0..2] of string = (
    // Der Detektor liest ohne Kommentare und meldet diese drei Formen.
    ('  X{owned}.Free;', '  X := nil;', 'Kommentar im Ausdruck'),
    ('  X.{c}Free;', '  X := nil;', 'Kommentar im Ausdruck'),
    ('  X.Free {c};', '  X := nil;', 'Kommentar im Ausdruck'),
    // Leerzeichen vor dem Punkt meldet er nicht: Zeile seit dem Scan anders.
    ('  X (*c*).Free;', '  X := nil;', 'nicht mehr an der gemeldeten Stelle'),
    ('  DoSomething;', '  X := nil;', 'nicht mehr an der gemeldeten Stelle'),
    ('  X.Free; Log(''x'');', '  X := nil;', 'hinter X.Free; steht noch etwas'),
    ('  X.Free; {$IFDEF A}', '  X := nil;', 'hinter X.Free; steht noch etwas'),
    ('  X.Free;', '  X := nil; Y := 0;', 'hinter X := nil steht noch etwas'),
    ('  X.Free;', '  Y := nil;', 'ist nicht "X := nil;"'),
    // Ein {..}-Kommentar wandert nicht (ein //-Kommentar schon, rwE30 -
    // Sca085_NilLineComment).
    ('  X.Free;', '  X := nil; { weg }', 'Kommentar oder String in der nil-Zeile'));
var
  R   : string;
  Src : string;
  i   : Integer;
begin
  for i := 0 to High(GUARDS) do
  begin
    Src := Join(['unit u;', 'procedure P;', 'begin', GUARDS[i], '    X.Free;',
      '  X := nil;', 'end;', 'end.']);
    Assert.AreEqual('', Fix085(Src, 5, R), GUARDS[i]);
    Assert.IsTrue(Pos('bedingt', R) > 0, R);
  end;
  for i := 0 to High(CASES) do
  begin
    Assert.AreEqual('', Fix085(FreeNil(CASES[i, 0], CASES[i, 1]), 4, R), CASES[i, 0]);
    Assert.IsTrue(Pos(CASES[i, 2], R) > 0, CASES[i, 0] + ' / ' + CASES[i, 1] + ': ' + R);
  end;
  Assert.AreEqual('', Fix085(Join(['  X.Free;', '  X := nil;']), 1, R),
    'nil-Zeile ist die letzte');
  Assert.IsTrue(Pos('keine Zeile hinter der nil-Zuweisung', R) > 0, R);
end;

// ---- SCA074 ----

procedure TTestRdxSimpleFixes.Sca074_Variants;
const
  Q = #39;
  CASES: array[0..6, 0..1] of string = (
    ('  Assert(X > 0);', '  Assert(X > 0, ''X > 0'');'),
    ('  Assert (X > 0);', '  Assert (X > 0, ''X > 0'');'),
    ('  Assert( F(A, B) );', '  Assert( F(A, B), ''F(A, B)'');'),
    ('  System.Assert(Ok);', '  System.Assert(Ok, ''Ok'');'),
    ('  if A then Assert(B) else Assert(C);',
     '  if A then Assert(B, ''B'') else Assert(C);'),
    ('  Assert(X > 0); // Pruefung', '  Assert(X > 0, ''X > 0''); // Pruefung'),
    ('  ASSERT(x);', '  ASSERT(x, ''x'');'));
var
  i    : Integer;
  R    : string;
  Cond : string;
begin
  for i := 0 to High(CASES) do
    Assert.AreEqual(InUnit(CASES[i, 1]),
      Fix074(InUnit(CASES[i, 0]), 4, Pos('ssert', LowerCase(CASES[i, 0])) - 1, R),
      Format('Fall %d: %s', [i, R]));
  // Apostrophe der Bedingung verdoppelt: S <> '' -> 'S <> '''''
  Assert.AreEqual(InUnit('  Assert(S <> ' + Q + Q + ', ' + Q + 'S <> '
      + Q + Q + Q + Q + Q + ');'),
    Fix074(InUnit('  Assert(S <> ' + Q + Q + ');'), 4, 3, R), R);
  // Grenze: 253 Zeichen Bedingung + zwei Quotes = 255 geht noch.
  Cond := StringOfChar('X', 253);
  Assert.AreEqual(InUnit('  Assert(' + Cond + ', ' + Q + Cond + Q + ');'),
    Fix074(InUnit('  Assert(' + Cond + ');'), 4, 3, R), R);
end;

procedure TTestRdxSimpleFixes.Sca074_Refusals;
const
  // Zeile, Spalte, Teil des Grundes
  CASES: array[0..11, 0..2] of string = (
    ('  Assert(X > 0, ''warum'');', '3', 'Meldung'),
    ('  Assert(X > 0 { warum });', '3', 'Kommentar'),
    ('  Obj.Assert(X);', '7', 'qualifiziert'),
    // Gegen-Review 2026-10-10: ein Vorfahr bzw. die Deklaration selbst.
    ('  inherited Assert(Ok);', '13', 'inherited'),
    ('procedure Assert(B: Boolean);', '11', 'procedure'),
    ('  Assert(X);', '4', 'nicht mehr'),
    ('  Assert(X);', '0', 'Spalte'),
    ('  S := ''Assert(X)'';', '9', 'nicht mehr'),
    ('  Assert();', '3', 'ohne Bedingung'),
    ('  MyAssert(X);', '5', 'nicht mehr'),
    ('  Assert{x}(X);', '3', 'nicht mehr'),
    ('  Assert X;', '3', 'nicht mehr'));
var
  i : Integer;
  R : string;
begin
  for i := 0 to High(CASES) do
  begin
    Assert.AreEqual('', Fix074(InUnit(CASES[i, 0]), 4, StrToInt(CASES[i, 1]), R),
      CASES[i, 0]);
    Assert.IsTrue(Pos(CASES[i, 2], R) > 0, CASES[i, 0] + ': ' + R);
  end;
  // Die Klammer schliesst erst in der Folgezeile.
  Assert.AreEqual('', Fix074(Join(['unit u;', 'implementation', 'procedure P;',
    '  Assert(X >', '    0);', 'end.']), 4, 3, R));
  Assert.IsTrue(Pos('endet nicht', R) > 0, R);
  // 254 Zeichen + zwei Quotes = 256: kein Pascal-Literal mehr.
  Assert.AreEqual('', Fix074(InUnit('  Assert(' + StringOfChar('X', 254) + ');'),
    4, 3, R));
  Assert.IsTrue(Pos('zu lang', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca074_DeclaresRoutine;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',
      'interface',
      'type',
      '  TFoo = class',
      '    procedure Check;',
      '    function Value: Integer;',
      '  end;',
      'implementation',
      '// procedure Gone;',
      'procedure TFoo.Assert(B: Boolean);',
      'begin',
      'end;',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxTypeProof.DeclaresRoutine(Map, 'Assert'),
      'qualifiziert: letztes Segment');
    Assert.IsTrue(TRdxTypeProof.DeclaresRoutine(Map, 'Check'));
    Assert.IsTrue(TRdxTypeProof.DeclaresRoutine(Map, 'VALUE'), 'ohne Gross/Klein');
    Assert.IsFalse(TRdxTypeProof.DeclaresRoutine(Map, 'Gone'), 'nur im Kommentar');
    Assert.IsFalse(TRdxTypeProof.DeclaresRoutine(Map, 'TFoo'), 'nur Qualifizierer');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- SCA087 ----

// Abschnitte einer Klasse ab Zeile 5 (mindestens eine Zeile).
function InClass(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type', '  TFoo = class']) + #13#10
    + Join(ALines) + #13#10 + Join(['  end;', 'implementation', 'end.']);
end;

procedure TTestRdxSimpleFixes.Sca087_Variants;
var
  R : string;
begin
  Assert.AreEqual(InClass(['  private', '    FX: Integer;']),
    Fix087(InClass(['  public', '  private', '    FX: Integer;']), 5, 'public', R), R);
  Assert.AreEqual(InClass(['  public', '    procedure P;']),
    Fix087(InClass(['  strict private', '  public', '    procedure P;']), 5,
      'strict private', R), R);
  Assert.AreEqual(InClass(['  private', '    FX: Integer;']),
    Fix087(InClass(['  PUBLIC', '  private', '    FX: Integer;']), 5, 'public', R),
    'Gross/Klein: ' + R);
  Assert.AreEqual(InClass(['  public', '    FX: Integer;']),
    Fix087(InClass([#9'strict'#9'protected', '  public', '    FX: Integer;']), 5,
      'strict protected', R), 'Tabs: ' + R);
  // Ein Kommentar ZWISCHEN den Abschnitten bleibt stehen.
  Assert.AreEqual(InClass(['  // spaeter', '  private', '    FX: Integer;']),
    Fix087(InClass(['  public', '  // spaeter', '  private', '    FX: Integer;']), 5,
      'public', R), R);
  // Am Ende der Klasse.
  Assert.AreEqual(InClass(['    FX: Integer;']),
    Fix087(InClass(['    FX: Integer;', '  published']), 6, 'published', R), R);
end;

procedure TTestRdxSimpleFixes.Sca087_Refusals;
var
  R : string;
begin
  // 'strict' allein: es gehoert zu 'private' in der naechsten Zeile.
  Assert.AreEqual('', Fix087(InClass(['  strict', '  private', '    FX: Integer;']),
    5, 'strict', R));
  Assert.IsTrue(Pos('allein', R) > 0, R);
  Assert.AreEqual('', Fix087(InClass(['  public // leer', '  private']), 5, 'public', R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Detektor-FP: das erste Wort zaehlt, das Feld dahinter nicht.
  Assert.AreEqual('', Fix087(InClass(['  public FX: Integer;', '  private']), 5,
    'public', R));
  Assert.IsTrue(Pos('nicht nur', R) > 0, R);
  Assert.AreEqual('', Fix087(InClass(['  public', '  private']), 5, 'private', R),
    'anderer Abschnitt');
  Assert.IsTrue(Pos('nicht nur', R) > 0, R);
  // Ohne X ist 'public' der Abschnitt von FX.
  Assert.AreEqual('', Fix087(InClass(['  public', '{$IFDEF X}', '  private',
    '{$ENDIF}', '    FX: Integer;']), 5, 'public', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', Fix087(InClass(['  {', '  public', '  }', '  private']), 6,
    'public', R), 'im Block-Kommentar');
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Gegen-Review 2026-10-10: Member-Zeilen mit '&' oder Umlaut am Anfang
  // sieht der Detektor nicht - der Abschnitt ist trotzdem nicht leer.
  Assert.AreEqual('', Fix087(InClass(['  strict private', '    FText: string;',
    '  public', '    &Type: Integer;']), 7, 'public', R), '&-Bezeichner');
  Assert.IsTrue(Pos('nicht leer', R) > 0, R);
  Assert.AreEqual('', Fix087(InClass(['  public',
    '    ' + #$00C4 + 'nderung: Integer;']), 5, 'public', R), 'Umlaut');
  Assert.IsTrue(Pos('nicht leer', R) > 0, R);
  // 'strict' allein auf der Zeile davor gehoert zu diesem Abschnitt.
  Assert.AreEqual('', Fix087(InClass(['  strict', '  private', '  protected',
    '    FX: Integer;']), 6, 'private', R));
  Assert.IsTrue(Pos('strict', R) > 0, R);
  Assert.AreEqual('', Fix087(Join(['  public']), 1, 'public', R), 'letzte Zeile');
  Assert.IsTrue(Pos('keine Zeile hinter dem Abschnitt', R) > 0, R);
end;

// ---- SCA139 ----

procedure TTestRdxSimpleFixes.Sca139_Variants;
const
  CASES: array[0..6, 0..1] of string = (
    ('    FList.Free;', '    FreeAndNil(FList);'),
    ('  if Assigned(FList) then FList.Free;',
     '  if Assigned(FList) then FreeAndNil(FList);'),
    ('  else FList.Free', '  else FreeAndNil(FList)'),
    ('  FList . Free ;', '  FreeAndNil(FList) ;'),
    ('  FList.Free; // weg', '  FreeAndNil(FList); // weg'),
    ('  { FList.Free; } FList.Free;', '  { FList.Free; } FreeAndNil(FList);'),
    ('  flist.FREE;', '  FreeAndNil(flist);'));  // geschrieben wie im Quelltext
var
  i : Integer;
  R : string;
begin
  for i := 0 to High(CASES) do
    Assert.AreEqual(InUnit(CASES[i, 1]),
      Fix139(InUnit(CASES[i, 0]), 4, 'FList', R),
      Format('Fall %d: %s', [i, R]));
end;

procedure TTestRdxSimpleFixes.Sca139_Refusals;
const
  CASES: array[0..9, 0..1] of string = (
    ('  Self.FList.Free;', 'Pfad'),
    ('  Owner.FList.Free;', 'Pfad'),
    ('  FList.Free();', 'Klammern'),
    ('  FList.Free; FList.Free;', 'mehrmals'),
    ('  FList.Destroy;', 'Destroy'),
    ('  FOther.Free;', 'nicht mehr'),
    ('  FListX.Free;', 'nicht mehr'),
    ('  XFList.Free;', 'nicht mehr'),
    ('  S := ''FList.Free'';', 'nicht mehr'),
    ('  FList.FreeInstance;', 'nicht mehr'));
var
  i : Integer;
  R : string;
begin
  for i := 0 to High(CASES) do
  begin
    Assert.AreEqual('', Fix139(InUnit(CASES[i, 0]), 4, 'FList', R), CASES[i, 0]);
    Assert.IsTrue(Pos(CASES[i, 1], R) > 0, CASES[i, 0] + ': ' + R);
  end;
  Assert.AreEqual('', Fix139(InUnit('  FList.Free;'), 4, '', R), 'ohne Empfaenger');
  Assert.IsTrue(Pos('fehlt', R) > 0, R);
end;

procedure TTestRdxSimpleFixes.Sca139_DeclaresNonClassType;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',
      'type',
      '  TRec = record',
      '    procedure Free;',
      '  end;',
      '  TPacked = packed record end;',
      '  IFoo = interface end;',
      '  TOld = object end;',
      '  TFoo = class end;',
      '  // TGone = record',
      'implementation',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxTypeProof.DeclaresNonClassType(Map, 'trec'));
    Assert.IsTrue(TRdxTypeProof.DeclaresNonClassType(Map, 'TPacked'), 'packed');
    Assert.IsTrue(TRdxTypeProof.DeclaresNonClassType(Map, 'ifoo'));
    Assert.IsTrue(TRdxTypeProof.DeclaresNonClassType(Map, 'told'));
    Assert.IsFalse(TRdxTypeProof.DeclaresNonClassType(Map, 'tfoo'), 'Klasse');
    Assert.IsFalse(TRdxTypeProof.DeclaresNonClassType(Map, 'tgone'), 'nur im Kommentar');
    Assert.IsFalse(TRdxTypeProof.DeclaresNonClassType(Map, 'tstringlist'),
      'aus einer anderen Unit: unbekannt');
    Assert.IsFalse(TRdxTypeProof.DeclaresNonClassType(Map, ''), 'kein Typ');
  finally
    Map.Free;
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixes);

end.
