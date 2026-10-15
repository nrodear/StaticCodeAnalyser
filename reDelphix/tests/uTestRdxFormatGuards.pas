unit uTestRdxFormatGuards;

// Tests fuer die Nacharbeit des Code-Reviews an der Format()-Umformung
// (Charge FB, uRdxRecipes): kein Literal ueber 255 Elemente im
// Formatstring (R2-02 - E2056 bis Delphi 11, SplitLongLiteral) und kein
// Zeiger am Kettenanfang (R2-04 - 'P + N' rechnet Zeiger-Arithmetik). Reine
// Textlogik - laeuft in reDelphix.Test UND im FPC-Pruefstand. Die Tests
// gegen BuildFormatCall waren gegen den Stand 4358b769 rot (402 Zeichen in
// einem Literal; P + FOffset angeboten), die Split_*-Tests pruefen den neuen
// Baustein. Gezaehlt wird hier unabhaengig von ihm: zerlegt an ' + '
// ausserhalb von Quotes, dekodiert mit DecodeLiteral.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFormatGuards = class
  public
    // R2-02: zwei Literale von je 200 Zeichen - einzeln gueltig, im
    // Formatstring bis dahin EIN Literal von 402 Zeichen.
    [Test] procedure Format_LongChain_NoLiteralOver255;
    // Eine kurze Kette bleibt EIN Literal (keine Teilung ohne Not).
    [Test] procedure Format_ShortChain_OneLiteral;
    // Der Baustein: Wert gleich, Teilung hinter einem Leerzeichen, #-Codes
    // und '' zaehlen mit, nie im Surrogat-Paar, Nicht-ASCII zaehlt zwei.
    [Test] procedure Split_KeepsValue_PrefersBlank;
    [Test] procedure Split_CodesAndQuotesCount;
    [Test] procedure Split_SurrogatesAndNonAscii;
    [Test] procedure Split_OtherForms_Unchanged;
    // R2-04: Zeiger am Kettenanfang.
    [Test] procedure Format_PointerStart_Blocked;
    [Test] procedure Format_PointerThenString_Allowed;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxRecipes;

const
  // Elemente eines String-Literals bis Delphi 11 (E2056).
  LIMIT = 255;

function Lit(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_LITERAL, AText, rvString);
end;

function Op(const AText: string; AType: TRefactorValueType;
  const AResolved: string = ''): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_OPERAND, AText, AType, AResolved);
end;

function Target(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_TARGET, AText);
end;

// ACount-mal AWord gefolgt von einem Leerzeichen.
// (TStringBuilder - unter FPC 3.2.2 ein AnsiString-Bauer: nur fuer ASCII.)
function Words(ACount: Integer; const AWord: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to ACount do
      SB.Append(AWord + ' ');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Das Glied ASource dekodiert an AValues anhaengen - es muss ein Literal sein.
procedure AddDecoded(var AValues: TArray<string>; const ASource: string);
var
  V : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral(ASource, V), 'kein Literal: ' + ASource);
  SetLength(AValues, Length(AValues) + 1);
  AValues[High(AValues)] := V;
end;

// Die Glieder eines mit ' + ' verbundenen Literal-Ausdrucks, je dekodiert -
// zerlegt an ' + ' AUSSERHALB von Quotes.
function PiecesOf(const AExpr: string): TArray<string>;
var
  i, Start : Integer;
  InQuote  : Boolean;
begin
  Result := nil;
  InQuote := False;
  Start := 1;
  i := 1;
  while i <= Length(AExpr) do
  begin
    if AExpr[i] = '''' then
      InQuote := not InQuote
    else if not InQuote and (Copy(AExpr, i, 3) = ' + ') then
    begin
      AddDecoded(Result, Copy(AExpr, Start, i - Start));
      Start := i + 3;
      Inc(i, 2);
    end;
    Inc(i);
  end;
  AddDecoded(Result, Copy(AExpr, Start, MaxInt));
end;

// Die Werte aneinander (TStringBuilder wie Words: nur ASCII).
function Joined(const AValues: TArray<string>): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AValues) do
      SB.Append(AValues[i]);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der Formatstring aus 'Format(<Fmt>, [<AArgs>])'.
function FmtOf(const ANewText, AArgs: string): string;
var
  Tail : string;
begin
  Tail := ', [' + AArgs + '])';
  Assert.AreEqual('Format(', Copy(ANewText, 1, 7), ANewText);
  Assert.AreEqual(Tail, Copy(ANewText, Length(ANewText) - Length(Tail) + 1,
    MaxInt), ANewText);
  Result := Copy(ANewText, 8, Length(ANewText) - 7 - Length(Tail));
end;

{ ---- R2-02: Formatstring ---- }

procedure TTestRdxFormatGuards.Format_LongChain_NoLiteralOver255;
var
  A, B, Fmt : string;
  NewText   : string;
  Reason    : string;
  Values    : TArray<string>;
  i         : Integer;
begin
  // GExperts GX_uProjSubDir.pas:505, HeidiSQL exportgrid.pas:756 ...: jedes
  // Literal fuer sich kurz, zusammen ueber 255.
  A := Words(40, 'aaaa');
  B := Words(40, 'bbbb');
  Assert.AreEqual<Integer>(200, Length(A));
  Assert.IsTrue(TRdxRecipes.BuildFormatCall([Target('S'), Lit('''' + A + ''''),
    Op('X', rvString), Lit('''' + B + '''')], NewText, Reason), Reason);
  Fmt := FmtOf(NewText, 'X');
  Values := PiecesOf(Fmt);
  Assert.IsTrue(Length(Values) >= 2, Fmt);
  for i := 0 to High(Values) do
    Assert.IsTrue(Length(Values[i]) <= LIMIT,
      Format('Glied %d: %d Zeichen', [i, Length(Values[i])]));
  Assert.AreEqual(A + '%s' + B, Joined(Values));
end;

procedure TTestRdxFormatGuards.Format_ShortChain_OneLiteral;
var
  NewText : string;
  Reason  : string;
begin
  Assert.IsTrue(TRdxRecipes.BuildFormatCall([Target('S'), Lit('''Hallo '''),
    Op('Name', rvString), Lit('''!''')], NewText, Reason), Reason);
  Assert.AreEqual('Format(''Hallo %s!'', [Name])', NewText);
end;

{ ---- R2-02: der Baustein SplitLongLiteral ---- }

procedure TTestRdxFormatGuards.Split_KeepsValue_PrefersBlank;
var
  V, Res : string;
  Values : TArray<string>;
begin
  V := Words(60, 'wxyz');   // 300 Zeichen, alle 5 ein Leerzeichen
  Res := SplitLongLiteral(TRdxRecipes.EncodeLiteral(V));
  Values := PiecesOf(Res);
  Assert.AreEqual<Integer>(2, Length(Values), Res);
  Assert.IsTrue(Length(Values[0]) <= LIMIT, IntToStr(Length(Values[0])));
  Assert.AreEqual(' ', Copy(Values[0], Length(Values[0]), 1),
    'geteilt hinter einem Leerzeichen: ' + Res);
  Assert.AreEqual(V, Joined(Values));
end;

procedure TTestRdxFormatGuards.Split_CodesAndQuotesCount;
var
  V, Res : string;
  Values : TArray<string>;
  i      : Integer;
begin
  // #13#10 zwischen zwei Quote-Teilen: ein Literal, die Codes zaehlen mit.
  V := StringOfChar('a', 250) + #13#10 + StringOfChar('b', 10);
  Res := SplitLongLiteral(TRdxRecipes.EncodeLiteral(V));
  Values := PiecesOf(Res);
  Assert.IsTrue(Length(Values) >= 2, Res);
  for i := 0 to High(Values) do
    Assert.IsTrue(Length(Values[i]) <= LIMIT, Res);
  Assert.AreEqual(V, Joined(Values));
  // 300 Apostrophe: '' ist EIN Element und wird nie zerschnitten.
  V := StringOfChar('''', 300);
  Values := PiecesOf(SplitLongLiteral(TRdxRecipes.EncodeLiteral(V)));
  Assert.AreEqual<Integer>(2, Length(Values));
  Assert.AreEqual<Integer>(LIMIT, Length(Values[0]));
  Assert.AreEqual(V, Joined(Values));
end;

procedure TTestRdxFormatGuards.Split_SurrogatesAndNonAscii;
const
  PAIR = #$D83D#$DE00;
  AE   = #$00E4;
begin
  // Ohne EncodeLiteral/DecodeLiteral: unter FPC 3.2.2 baut TStringBuilder
  // AnsiStrings und machte aus dem Paar '??' (Pruefstand-Grenze, README).
  // Ein Surrogat-Paar an der Grenze geht ganz ins naechste Literal.
  Assert.AreEqual('''' + StringOfChar('a', 254) + ''' + ''' + PAIR + 'b''',
    SplitLongLiteral('''' + StringOfChar('a', 254) + PAIR + 'b'''));
  // Zeichen ueber ASCII zaehlen vorsichtig zwei (DBCS einer ANSI-Datei):
  // 127 je Literal.
  Assert.AreEqual('''' + StringOfChar(AE, 127) + ''' + ''' + StringOfChar(AE, 73)
    + '''', SplitLongLiteral('''' + StringOfChar(AE, 200) + ''''));
end;

procedure TTestRdxFormatGuards.Split_OtherForms_Unchanged;
begin
  Assert.AreEqual('''abc''#13#10''d''',
    SplitLongLiteral('''abc''#13#10''d'''), 'kurz');
  Assert.AreEqual('Name', SplitLongLiteral('Name'), 'kein Literal');
  Assert.AreEqual('''a'' + ''b''', SplitLongLiteral('''a'' + ''b'''),
    'schon ein Ausdruck');
  Assert.AreEqual('''offen', SplitLongLiteral('''offen'),
    'ohne schliessendes Quote');
  Assert.AreEqual('', SplitLongLiteral(''), 'leer');
end;

{ ---- R2-04: Zeiger am Kettenanfang ---- }

procedure TTestRdxFormatGuards.Format_PointerStart_Blocked;
var
  NewText : string;
  Reason  : string;
begin
  // 'S := P + FOffset + ''.txt''' mit P: PChar - Delphi rechnet P + FOffset
  // als Zeiger; Format('%s%s.txt', [P, FOffset]) wuerfe EConvertError.
  Assert.IsFalse(TRdxRecipes.BuildFormatCall([Target('S'),
    Op('P', rvString, 'pchar'), Op('FOffset', rvUnknown), Lit('''.txt''')],
    NewText, Reason), NewText);
  Assert.IsTrue(Pos('Zeiger', Reason) > 0, Reason);
  // Der Cast ganz ohne Typaufloesung (Gegenpruefer, v04 Fall 2).
  Assert.IsFalse(TRdxRecipes.BuildFormatCall([Target('S'),
    Op('PChar(S)', rvUnknown), Op('Ofs', rvUnknown), Lit('''.txt''')],
    NewText, Reason), NewText);
  Assert.IsTrue(Pos('Zeiger', Reason) > 0, Reason);
end;

procedure TTestRdxFormatGuards.Format_PointerThenString_Allowed;
var
  NewText : string;
  Reason  : string;
begin
  // Hinter dem Zeiger ein Literal bzw. ein bewiesener String: Delphi
  // verkettet - die Umformung bleibt.
  Assert.IsTrue(TRdxRecipes.BuildFormatCall([Target('S'),
    Op('P', rvString, 'pchar'), Lit('''x'''), Op('N', rvUnknown)],
    NewText, Reason), Reason);
  Assert.AreEqual('Format(''%sx%s'', [P, N])', NewText);
  Assert.IsTrue(TRdxRecipes.BuildFormatCall([Target('S'),
    Op('P', rvString, 'pchar'), Op('Name', rvString, 'string'), Lit('''x''')],
    NewText, Reason), Reason);
  Assert.AreEqual('Format(''%s%sx'', [P, Name])', NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFormatGuards);

end.
