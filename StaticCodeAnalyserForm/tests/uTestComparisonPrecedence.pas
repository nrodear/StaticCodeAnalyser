unit uTestComparisonPrecedence;

// Tests fuer SCA202 ComparisonPrecedence (uComparisonPrecedence +
// uComparisonPrecedenceScan).
//
// Alle Tests laufen ueber FindingsOfFile (der Detektor liest die Datei,
// den AST nur fuer den Typ-Resolver). Ergebnis je Test als kompakte
// Beschreibung 'E8,W9' = Error auf Zeile 8, Warning auf Zeile 9.
// Jeder Schweige-Test traegt einen Waechter (eine Zeile, die gemeldet
// werden MUSS) - ohne Detektor ist er rot, ohne das jeweilige Gate auch.
//
// Der Scanner-Teil jedes Falls lief vor dem ersten Delphi-Bau im FPC-
// Pruefstand (2026-10-23, scratchpad chargeA\A2\fpc); die Typ-Faelle
// (Resolver) nur unter Delphi.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestComparisonPrecedence = class
  public
    // --- K1: not vor einem Vergleich ---------------------------------------
    [Test] procedure NotCountGreater_ErrorByMember;
    [Test] procedure NotLiteralSetAndIntCall_Error;
    [Test] procedure NotIntegerVariable_ErrorByResolvedType;
    [Test] procedure NotUnknownOperand_Warning;
    [Test] procedure NotBooleanOperand_NoFinding;
    [Test] procedure NotBooleanLiteralOrMember_NoFinding;
    [Test] procedure NotInAssignmentAndArgument_Reported;
    [Test] procedure NotInMultiLineCondition_LineOfNot;
    // --- K2: Vergleichskette ueber and/or/xor -------------------------------
    [Test] procedure ChainWithBooleanLiteral_Error;
    [Test] procedure ChainWithoutLiteral_Warning;
    [Test] procedure ParenthesizedComparisons_NoFinding;
    [Test] procedure GenericTypeArguments_NoFinding;
    // --- Idiome, Kommentare, Meldung ----------------------------------------
    [Test] procedure BitTestIdioms_NoFinding;
    [Test] procedure CommentsAndStrings_NoFinding;
    [Test] procedure Message_ShowsHowItIsEvaluated;
    [Test] procedure Confidence_ErrorHigh_WarningMedium;
    // --- Perf Charge P4: Wortnachschlag ohne Kopie --------------------------
    [Test] procedure KeywordsInAnyCase_SameAsLowerCase;
    [Test] procedure AsmBlockInAnyCase_Skipped;
    [Test] procedure AmpersandIdentifier_KeepsItsText;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// Unit mit EINER Routine: Zeile 6 traegt die Deklarationen, der Rumpf
// beginnt auf Zeile 8.
function Quelltext(const ADecl: string; const ABody: array of string): string;
var
  i : Integer;
begin
  Result := 'unit sample;'#13#10 +            // 1
            'interface'#13#10 +               // 2
            'implementation'#13#10 +          // 3
            'procedure Probe;'#13#10 +        // 4
            'var'#13#10 +                     // 5
            '  ' + ADecl + #13#10 +           // 6
            'begin'#13#10;                    // 7
  for i := 0 to High(ABody) do                // 8 ...
    Result := Result + ABody[i] + #13#10;
  Result := Result + 'end;'#13#10'end.'#13#10;
end;

// 'E8,W9': Schwere und Zeile jedes SCA202-Funds in Fundreihenfolge.
function Funde(const ADecl: string; const ABody: array of string): string;
var
  F : TObjectList<TLeakFinding>;
  i : Integer;
begin
  Result := '';
  F := TFindingHelper.FindingsOfFile(Quelltext(ADecl, ABody));
  try
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkComparisonPrecedence then
      begin
        if Result <> '' then Result := Result + ',';
        if F[i].Severity = lsError then
          Result := Result + 'E'
        else
          Result := Result + 'W';
        Result := Result + F[i].LineNumber;
      end;
  finally
    F.Free;
  end;
end;

procedure TTestComparisonPrecedence.NotCountGreater_ErrorByMember;
begin
  // (not L.Count) ist fuer jedes Count >= 0 negativ - rechts steht nur ein
  // unbekannter Bezeichner, .Count als letztes Glied belegt die Ganzzahl.
  Assert.AreEqual('E8', Funde('L: TStringList;',
    ['  if not L.Count > Limit then Exit;']));
end;

procedure TTestComparisonPrecedence.NotLiteralSetAndIntCall_Error;
begin
  // Zahl rechts, Zahlmenge rechts, Pos() als Operand (rechts nur ein
  // Bezeichner): der Operand kann nicht Boolean sein (Boolean = 0
  // kompiliert nicht).
  Assert.AreEqual('E8,E9,E10', Funde('X: Integer; B: Byte; S: string;',
    ['  if not X = 0 then Exit;',
     '  if not B in [1, 2] then Exit;',
     '  while not Pos(''a'', S) > Start do Exit;']));
end;

procedure TTestComparisonPrecedence.NotIntegerVariable_ErrorByResolvedType;
begin
  // Lexikalisch offen (Bezeichner gegen Bezeichner) - der Resolver belegt
  // A als Integer.
  Assert.AreEqual('E8', Funde('A, B: Integer;',
    ['  if not A < B then Exit;']));
end;

procedure TTestComparisonPrecedence.NotUnknownOperand_Warning;
begin
  Assert.AreEqual('W8', Funde('R: TRec;',
    ['  if not R.Status = cOk then Exit;']));
end;

procedure TTestComparisonPrecedence.NotBooleanOperand_NoFinding;
begin
  // (not Flag) = Other ist fuer Boolean gleichwertig zu not (Flag = Other).
  // Zeile 9 ist der Waechter.
  Assert.AreEqual('E9', Funde('Flag, Other: Boolean; N: Integer;',
    ['  if not Flag = Other then Exit;',
     '  if not N = 0 then Exit;']));
end;

procedure TTestComparisonPrecedence.NotBooleanLiteralOrMember_NoFinding;
begin
  // True/False rechts und ein bekanntes Boolean-Glied (Checked) mit =
  // sind gleichwertig; Zeile 10 ist der Waechter.
  Assert.AreEqual('E10', Funde('N: Integer;',
    ['  if not Obj.Ready = True then Exit;',
     '  if not CheckBox1.Checked = Ini.ReadBool(''a'', ''b'', False) then Exit;',
     '  if not N > 0 then Exit;']));
end;

procedure TTestComparisonPrecedence.NotInAssignmentAndArgument_Reported;
begin
  // 'not' am Anfang eines Operanden auch hinter := und in Argumenten;
  // .IndexOf/.Count belegen die Ganzzahl.
  Assert.AreEqual('E8,E9', Funde('S: TStringList; R: Boolean;',
    ['  R := not S.IndexOf(''x'') >= First;',
     '  Check(not S.Count = Wanted);']));
end;

procedure TTestComparisonPrecedence.NotInMultiLineCondition_LineOfNot;
begin
  // Gemeldet wird die Zeile des 'not'; die geklammerten Vergleiche um das
  // 'and' sind keine Kette.
  Assert.AreEqual('E9', Funde('X, Y: Integer;',
    ['  if (X > 1) and',
     '     (not Y in [1, 2]) then Exit;']));
end;

procedure TTestComparisonPrecedence.ChainWithBooleanLiteral_Error;
begin
  // (A = (True or B)) = False - True/False belegt Boolean.
  Assert.AreEqual('E8', Funde('A, B: Boolean;',
    ['  if A = True or B = False then Exit;']));
end;

procedure TTestComparisonPrecedence.ChainWithoutLiteral_Warning;
begin
  Assert.AreEqual('W8', Funde('A, B, C, D: Boolean;',
    ['  while A = B and C <> D do Exit;']));
end;

procedure TTestComparisonPrecedence.ParenthesizedComparisons_NoFinding;
begin
  // Geklammerte Vergleiche und ein Vergleich gegen einen geklammerten
  // Vergleich sind richtig; Zeile 11 ist der Waechter.
  Assert.AreEqual('E11', Funde('X, Y, Z: Integer; A, B: Boolean;',
    ['  if (X = 1) or (Y = 2) then Exit;',
     '  if (X < Y) and (Y < Z) then Exit;',
     '  A := (X > 0) = B;',
     '  if A = True or B = True then Exit;']));
end;

procedure TTestComparisonPrecedence.GenericTypeArguments_NoFinding;
begin
  // '<' und '>' einer Typargumentliste sind keine Vergleiche; Zeile 11
  // ist der Waechter.
  Assert.AreEqual('E11', Funde('V: TValue; L: TList<Integer>; A: Boolean;',
    ['  if V.IsType<Extended> or V.IsType<Double> then Exit;',
     '  L := TList<Integer>.Create;',
     '  if not V.IsType<string> then Exit;',
     '  if A = False or V.IsEmpty = True then Exit;']));
end;

procedure TTestComparisonPrecedence.BitTestIdioms_NoFinding;
begin
  // (Flags and not Mask) <> 0, (Flags and Mask) = 0 und X = (A or B)
  // sind gewollt bzw. offen; not (X = 0) ist geklammert. Zeile 12 ist der
  // Waechter.
  Assert.AreEqual('E12', Funde('Flags, Mask, X, A, B: Integer;',
    ['  if Flags and not Mask <> 0 then Exit;',
     '  if Flags and Mask = 0 then Exit;',
     '  if X = A or B then Exit;',
     '  if not (X = 0) then Exit;',
     '  if not X = 0 then Exit;']));
end;

procedure TTestComparisonPrecedence.CommentsAndStrings_NoFinding;
begin
  // Kommentare und Strings zaehlen nie als Code; Zeile 12 ist der Waechter.
  Assert.AreEqual('E12', Funde('X: Integer; S: string;',
    ['  // if not X = 0 then',
     '  { if A = True or B = False then }',
     '  S := ''if not X = 0 then'';',
     '  (* while not X > 0 do *)',
     '  if not X > 0 then Exit;']));
end;

procedure TTestComparisonPrecedence.Message_ShowsHowItIsEvaluated;
var
  F : TObjectList<TLeakFinding>;
  K1, K2 : string;
  i : Integer;
begin
  F := TFindingHelper.FindingsOfFile(Quelltext('L: TStringList; A, B: Boolean;',
    ['  if not L.Count > 0 then Exit;',
     '  if A = True or B = False then Exit;']));
  try
    K1 := '';
    K2 := '';
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkComparisonPrecedence then
        if F[i].LineNumber = '8' then
          K1 := F[i].MissingVar
        else if F[i].LineNumber = '9' then
          K2 := F[i].MissingVar;
    Assert.IsTrue(Pos('''(not L.Count) > ...''', K1) > 0, K1);
    Assert.IsTrue(Pos('''not (L.Count > ...)''', K1) > 0, K1);
    Assert.IsTrue(Pos('(True or B)', K2) > 0, K2);
  finally
    F.Free;
  end;
end;

procedure TTestComparisonPrecedence.Confidence_ErrorHigh_WarningMedium;
var
  F : TObjectList<TLeakFinding>;
  CE, CW : Integer;
  i : Integer;
begin
  // Wie SCA203: Error (Typ belegt) traegt fcHigh, Warning (ohne Beleg)
  // fcMedium - im Default (FindingMinConfidence = fcMedium) sichtbar.
  // Ohne die Konfidenz im else-Zweig erbte die Warning fcHigh.
  F := TFindingHelper.FindingsOfFile(Quelltext('N: Integer; R: TRec;',
    ['  if not N = 0 then Exit;',
     '  if not R.Status = cOk then Exit;']));
  try
    CE := -1;
    CW := -1;
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkComparisonPrecedence then
        if F[i].LineNumber = '8' then
          CE := Ord(F[i].Confidence)
        else if F[i].LineNumber = '9' then
          CW := Ord(F[i].Confidence);
    Assert.AreEqual<Integer>(Ord(fcHigh), CE, 'Error Zeile 8');
    Assert.AreEqual<Integer>(Ord(fcMedium), CW, 'Warning Zeile 9');
  finally
    F.Free;
  end;
end;

// Perf Charge P4 (2026-10-25): der Lexer kopiert Bezeichner nicht mehr,
// sondern schlaegt sie case-insensitiv in der Wort-Tabelle nach. Die drei
// Tests pinnen die Randfaelle dieses Nachschlags; sie waren vor dem Umbau
// gruen und werden rot, wenn der Nachschlag Gross-/Kleinschreibung
// beachtet, Praefixe gelten laesst ('Counter' als 'count') oder '&Name'
// als Schluesselwort liest.

procedure TTestComparisonPrecedence.KeywordsInAnyCase_SameAsLowerCase;
begin
  // Zeile 8: IF/NOT/COUNT gross - .Count belegt die Ganzzahl (Error).
  // Zeile 9: .Counter ist KEIN Tabellenwort, nur 'count' ist sein Praefix
  //          - kein Beleg, Warning.
  // Zeile 10: TRUE und 'Or' gemischt - Kette mit Boolean-Literal (Error).
  Assert.AreEqual('E8,W9,E10', Funde('L: TStringList; X: TFoo; A, B: Boolean;',
    ['  IF NOT L.COUNT > Limit THEN Exit;',
     '  If Not X.Counter > Limit Then Exit;',
     '  if A = TRUE Or B = False then Exit;']));
end;

procedure TTestComparisonPrecedence.AsmBlockInAnyCase_Skipped;
begin
  // ASM ... End ueberspringt der Lexer in jeder Schreibweise: Zeile 9
  // liegt im asm-Block und zaehlt nicht, Zeile 11 dahinter schon.
  Assert.AreEqual('E11', Funde('N: Integer;',
    ['  ASM',
     '    if not N = 1 then',
     '  End;',
     '  if not N = 0 then Exit;']));
end;

procedure TTestComparisonPrecedence.AmpersandIdentifier_KeepsItsText;
var
  F : TObjectList<TLeakFinding>;
  Msg : string;
  i, N : Integer;
begin
  // '&Type' ist ein Bezeichner, kein Schluesselwort (als 'type' gelesen
  // waere er kein Operand und der Fund fiele weg); die Meldung zeigt ihn
  // wie geschrieben.
  F := TFindingHelper.FindingsOfFile(Quelltext('&Type: Integer;',
    ['  if not &Type > 0 then Exit;']));
  try
    Msg := '';
    N := 0;
    for i := 0 to F.Count - 1 do
      if F[i].Kind = fkComparisonPrecedence then
      begin
        Inc(N);
        if F[i].LineNumber = '8' then
          Msg := F[i].MissingVar;
      end;
    Assert.AreEqual<Integer>(1, N, 'nur Zeile 8');
    Assert.IsTrue(Pos('''not &Type > ...''', Msg) > 0, Msg);
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestComparisonPrecedence);

end.
