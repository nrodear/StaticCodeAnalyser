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
    // ---- Stufe 2, Rest: SCA074, SCA087, SCA139 ----
    [Test] procedure Sca074_Variants;
    [Test] procedure Sca074_Refusals;
    [Test] procedure Sca074_DeclaresRoutine;
    [Test] procedure Sca087_Variants;
    [Test] procedure Sca087_Refusals;
    [Test] procedure Sca139_Variants;
    [Test] procedure Sca139_Refusals;
    [Test] procedure Sca139_DeclaresValueType;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxSimpleFixes,
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
  // Gegenprobe: eine Blockdirektive davor bleibt gesperrt.
  Assert.AreEqual('', Fix085(Join(['unit u;', 'procedure P;', 'begin',
    '  {$IFDEF A}{$ENDIF}', '  X.Free;', '  X := nil;', 'end;', 'end.']), 5, R));
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
    ('  X.Free;', '  X := nil; // weg', 'Kommentar oder String in der nil-Zeile'));
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
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Assert'),
      'qualifiziert: letztes Segment');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'Check'));
    Assert.IsTrue(TRdxSimpleFixes.DeclaresRoutine(Map, 'VALUE'), 'ohne Gross/Klein');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresRoutine(Map, 'Gone'), 'nur im Kommentar');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresRoutine(Map, 'TFoo'), 'nur Qualifizierer');
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

procedure TTestRdxSimpleFixes.Sca139_DeclaresValueType;
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
    Assert.IsTrue(TRdxSimpleFixes.DeclaresValueType(Map, 'trec'));
    Assert.IsTrue(TRdxSimpleFixes.DeclaresValueType(Map, 'TPacked'), 'packed');
    Assert.IsTrue(TRdxSimpleFixes.DeclaresValueType(Map, 'ifoo'));
    Assert.IsTrue(TRdxSimpleFixes.DeclaresValueType(Map, 'told'));
    Assert.IsFalse(TRdxSimpleFixes.DeclaresValueType(Map, 'tfoo'), 'Klasse');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresValueType(Map, 'tgone'), 'nur im Kommentar');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresValueType(Map, 'tstringlist'),
      'aus einer anderen Unit: unbekannt');
    Assert.IsFalse(TRdxSimpleFixes.DeclaresValueType(Map, ''), 'kein Typ');
  finally
    Map.Free;
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSimpleFixes);

end.
