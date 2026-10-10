unit uTestRefactorInfo;

// Tests fuer uRefactorInfo (Datentypen des Quellstellen-Dienstes,
// Konzept_SourceRefactor_Quellstellen 2026-10-02).
//
// WAS HIER FESTGEPINNT WIRD
//
//   1. Die Koordinaten-Konvention: EndCol zeigt HINTER das letzte Zeichen,
//      Copy(Zeile, StartCol, EndCol - StartCol) liefert den Text.
//   2. IsValid lehnt leere, verdrehte und nie gefuellte Bereiche ab.
//   3. Clone ist TIEF: ein Konsument, der eine Beschreibung laenger haelt
//      als den Dienst, der sie geliefert hat, aendert mit dem Klon nie das
//      Original - und umgekehrt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRefactorInfo = class
  public
    // ---- TRefactorSpan ----
    [Test] procedure Span_Make_SetsDefaults;
    [Test] procedure Span_IsValid_SingleLine;
    [Test] procedure Span_IsValid_MultiLine;
    [Test] procedure Span_IsValid_RejectsEmptyAndZero;
    [Test] procedure Span_EndColIsExclusive_CopyYieldsText;

    // ---- TRefactorInfo ----
    [Test] procedure Info_AddPart_KeepsOrder;
    [Test] procedure Info_CountOfRole_CountsOnlyThatRole;
    [Test] procedure Clone_CopiesAllFields;
    [Test] procedure Clone_IsDeep_PartsAreIndependent;
    [Test] procedure Clone_SurvivesFreeOfOriginal;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;

function SampleInfo: TRefactorInfo;
var
  P : TRefactorSpan;
begin
  Result := TRefactorInfo.Create;
  Result.Span := TRefactorSpan.Make(ROLE_STATEMENT, 10, 3, 11, 20);
  P := TRefactorSpan.Make(ROLE_TARGET, 10, 3, 10, 4);
  Result.AddPart(P);
  P := TRefactorSpan.Make(ROLE_TERM, 10, 8, 10, 16);
  P.ValueType := rvString;
  Result.AddPart(P);
  P := TRefactorSpan.Make(ROLE_TERM, 11, 5, 11, 19);
  P.Resolved := 'System.SysUtils';
  Result.AddPart(P);
  Result.FixSafe      := True;
  Result.Flags        := [rfMultiLine, rfHasComment];
  Result.InsertLine   := 12;
  Result.InsertIndent := 2;
  Result.SpanHash     := 'abc123';
end;

{ ---- TRefactorSpan ---- }

procedure TTestRefactorInfo.Span_Make_SetsDefaults;
var
  S : TRefactorSpan;
begin
  S := TRefactorSpan.Make(ROLE_TERM, 4, 7, 4, 12);
  Assert.AreEqual(ROLE_TERM, S.Role);
  Assert.AreEqual<Integer>(4, S.StartLine);
  Assert.AreEqual<Integer>(7, S.StartCol);
  Assert.AreEqual<Integer>(4, S.EndLine);
  Assert.AreEqual<Integer>(12, S.EndCol);
  Assert.IsTrue(S.ValueType = rvUnknown, 'unbekannt ist der Default');
  Assert.AreEqual('', S.Resolved);
end;

procedure TTestRefactorInfo.Span_IsValid_SingleLine;
var
  S : TRefactorSpan;
begin
  S := TRefactorSpan.Make(ROLE_TERM, 4, 7, 4, 8);
  Assert.IsTrue(S.IsValid, 'ein Zeichen breit ist gueltig');
  Assert.IsTrue(S.IsSingleLine);
end;

procedure TTestRefactorInfo.Span_IsValid_MultiLine;
var
  S : TRefactorSpan;
begin
  // Mehrzeilig darf EndCol kleiner als StartCol sein.
  S := TRefactorSpan.Make(ROLE_STATEMENT, 4, 30, 5, 3);
  Assert.IsTrue(S.IsValid);
  Assert.IsFalse(S.IsSingleLine);
end;

procedure TTestRefactorInfo.Span_IsValid_RejectsEmptyAndZero;
var
  S : TRefactorSpan;
begin
  S := TRefactorSpan.Make(ROLE_TERM, 4, 7, 4, 7);
  Assert.IsFalse(S.IsValid, 'leerer Bereich (EndCol = StartCol)');
  S := TRefactorSpan.Make(ROLE_TERM, 4, 7, 3, 9);
  Assert.IsFalse(S.IsValid, 'Ende vor dem Anfang');
  S := TRefactorSpan.Make(ROLE_TERM, 0, 1, 0, 5);
  Assert.IsFalse(S.IsValid, 'Zeile 0 gibt es nicht');
  S := TRefactorSpan.Make(ROLE_TERM, 4, 0, 4, 5);
  Assert.IsFalse(S.IsValid, 'Spalte 0 gibt es nicht');
  S := Default(TRefactorSpan);
  Assert.IsFalse(S.IsValid, 'ein nie gefuellter Bereich ist ungueltig');
end;

procedure TTestRefactorInfo.Span_EndColIsExclusive_CopyYieldsText;
const
  LINE = '  r := Name + Age;';
var
  S : TRefactorSpan;
begin
  // 'Name' steht an Spalte 8..11, EndCol zeigt auf 12.
  S := TRefactorSpan.Make(ROLE_TERM, 1, 8, 1, 12);
  Assert.AreEqual('Name', Copy(LINE, S.StartCol, S.EndCol - S.StartCol));
end;

{ ---- TRefactorInfo ---- }

procedure TTestRefactorInfo.Info_AddPart_KeepsOrder;
var
  I : TRefactorInfo;
begin
  I := SampleInfo;
  try
    Assert.AreEqual<Integer>(3, Length(I.Parts));
    Assert.AreEqual(ROLE_TARGET, I.Parts[0].Role);
    Assert.AreEqual<Integer>(8, I.Parts[1].StartCol);
    Assert.AreEqual<Integer>(11, I.Parts[2].StartLine);
  finally
    I.Free;
  end;
end;

procedure TTestRefactorInfo.Info_CountOfRole_CountsOnlyThatRole;
var
  I : TRefactorInfo;
begin
  I := SampleInfo;
  try
    Assert.AreEqual<Integer>(2, I.CountOfRole(ROLE_TERM));
    Assert.AreEqual<Integer>(1, I.CountOfRole(ROLE_TARGET));
    Assert.AreEqual<Integer>(0, I.CountOfRole(ROLE_UNIT));
  finally
    I.Free;
  end;
end;

procedure TTestRefactorInfo.Clone_CopiesAllFields;
var
  I, C : TRefactorInfo;
begin
  I := SampleInfo;
  try
    C := I.Clone;
    try
      Assert.AreNotSame(I, C, 'Clone liefert ein eigenes Objekt');
      Assert.AreEqual(ROLE_STATEMENT, C.Span.Role);
      Assert.AreEqual<Integer>(10, C.Span.StartLine);
      Assert.AreEqual<Integer>(20, C.Span.EndCol);
      Assert.AreEqual<Integer>(3, Length(C.Parts));
      Assert.IsTrue(C.Parts[1].ValueType = rvString);
      Assert.AreEqual('System.SysUtils', C.Parts[2].Resolved);
      Assert.IsTrue(C.FixSafe);
      Assert.IsTrue(C.Flags = [rfMultiLine, rfHasComment]);
      Assert.AreEqual<Integer>(12, C.InsertLine);
      Assert.AreEqual<Integer>(2, C.InsertIndent);
      Assert.AreEqual('abc123', C.SpanHash);
    finally
      C.Free;
    end;
  finally
    I.Free;
  end;
end;

procedure TTestRefactorInfo.Clone_IsDeep_PartsAreIndependent;
var
  I, C : TRefactorInfo;
begin
  I := SampleInfo;
  try
    C := I.Clone;
    try
      C.Parts[0].Role     := 'changed';
      C.Parts[0].StartCol := 99;
      C.AddPart(TRefactorSpan.Make(ROLE_TERM, 12, 1, 12, 2));
      Assert.AreEqual(ROLE_TARGET, I.Parts[0].Role,
        'eine Aenderung am Klon beruehrt das Original nicht');
      Assert.AreEqual<Integer>(3, I.Parts[0].StartCol);
      Assert.AreEqual<Integer>(3, Length(I.Parts));
    finally
      C.Free;
    end;
  finally
    I.Free;
  end;
end;

procedure TTestRefactorInfo.Clone_SurvivesFreeOfOriginal;
var
  I : TRefactorInfo;
  C : TRefactorInfo;
begin
  // Der Ablauf eines Konsumenten, der die Beschreibung laenger haelt als
  // den Dienst: der Klon ueberlebt das Original.
  I := SampleInfo;
  C := I.Clone;
  try
    I.Free;
    Assert.AreEqual<Integer>(3, Length(C.Parts));
    Assert.AreEqual('System.SysUtils', C.Parts[2].Resolved);
  finally
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRefactorInfo);

end.
