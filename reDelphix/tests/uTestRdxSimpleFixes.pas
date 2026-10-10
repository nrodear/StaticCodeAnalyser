unit uTestRdxSimpleFixes;

// Editorhilfen Stufe 2a: die Planer SCA075/SCA085 aus uRdxSimpleFixes auf
// Text - ohne Parser, ohne Detektor (laeuft in reDelphix.Test UND im
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
    [Test] procedure Sca085_VariableContext;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxSimpleFixes;

// ---- Helfer ----

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
  Ok    : Boolean;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Ok := PlanByteEdits(Bytes, AEdits, Plan, Err);
  Assert.IsTrue(Ok, Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

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
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject) procedure P; end;'), 4, 10, R),
    'Rumpf in derselben Zeile');
  Assert.IsTrue(R <> '');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject, IFoo)'), 4, 10, R),
    'nie class(IFoo)');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TComponent)'), 4, 10, R),
    'Puffer geaendert');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 11, R),
    'falsche Spalte');
  Assert.AreEqual('', Fix075(InUnit('  TFoo = class(TObject)'), 4, 0, R),
    'keine Spalte in der Meldung');
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
    Assert.IsTrue(TRdxSimpleFixes.DeclaresProperty(Map, 'Items'));
    Assert.IsTrue(TRdxSimpleFixes.DeclaresProperty(Map, 'ITEMS'), 'ohne Gross/Klein');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresProperty(Map, 'FList'));
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

procedure TTestRdxSimpleFixes.Sca085_Refusals;
const
  // Zeile vor X.Free; - das nil wuerde bedingt
  GUARDS: array[0..4] of string = ('  if FOwns then', '  else',
    '  with FData do', '  for I := 0 to 1 do', '  1:');
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
  Assert.AreEqual('', Fix085(FreeNil('  X.Free; Log(''x'');', '  X := nil;'), 4, R),
    'Code nach Free;');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free; {$IFDEF A}', '  X := nil;'), 4, R),
    'Direktive nach Free;');
  Assert.AreEqual('', Fix085(FreeNil('  X{owned}.Free;', '  X := nil;'), 4, R),
    'Kommentar im Ausdruck');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  X := nil; Y := 0;'), 4, R),
    'Code nach nil');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  Y := nil;'), 4, R),
    'andere Variable');
  Assert.AreEqual('', Fix085(FreeNil('  X.Free;', '  X := nil; // weg'), 4, R),
    'Kommentar in der nil-Zeile');
  Assert.AreEqual('', Fix085(Join(['  X.Free;', '  X := nil;']), 1, R),
    'nil-Zeile ist die letzte');
  Assert.AreEqual('', Fix085(FreeNil('  DoSomething;', '  X := nil;'), 4, R),
    'kein Free');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixes);

end.
