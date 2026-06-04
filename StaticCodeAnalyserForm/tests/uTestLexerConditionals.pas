unit uTestLexerConditionals;

// A.5 Tests: Conditional-Compilation-Awareness im TLexer.
// Verifiziert Phase 1a (Stack-Infrastruktur), Phase 1b (Defines + Skip),
// Phase 2.1 (Expression-Parser), Phase 2.2 (Alternate-Syntax).
// Default-OFF-Garantie: Tests laufen mit EnableConditionalSkipping
// nur dort wo der Skip-Effekt verifiziert wird.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uLexer;

type
  [TestFixture]
  TTestLexerConditionals = class
  public
    // Phase 1a: Stack-Infrastruktur
    [Test] procedure Phase1a_NoIfdef_DepthZero;
    [Test] procedure Phase1a_IfdefEndif_DepthBalanced;
    [Test] procedure Phase1a_NestedIfdef_MaxDepthTracked;
    [Test] procedure Phase1a_OrphanEndif_NoCrash;

    // Phase 1b: Defines + Skip (Default OFF Garantie)
    [Test] procedure Phase1b_DefaultOff_NoTokenSkip;
    [Test] procedure Phase1b_IfdefDefined_KeepsIfBranch;
    [Test] procedure Phase1b_IfdefUndefined_KeepsElseBranch;
    [Test] procedure Phase1b_IfndefUndefined_KeepsIfBranch;
    [Test] procedure Phase1b_NestedSkip_ParentDominates;
    [Test] procedure Phase1b_DefinesCaseInsensitive;

    // Phase 2.1: Expression-Parser
    [Test] procedure Phase2_IfDefinedX_Evaluated;
    [Test] procedure Phase2_IfDefinedAndDefined_BothMustMatch;
    [Test] procedure Phase2_IfDefinedOrDefined_EitherEnough;
    [Test] procedure Phase2_IfNotDefined_Inverts;
    [Test] procedure Phase2_IfCompilerVersion_ConservativelyTrue;
    [Test] procedure Phase2_IfMalformed_FallsBackToTrue;

    // Phase 2.2: Alternate-Syntax (*$IFDEF*)
    [Test] procedure Phase2_AlternateSyntax_IfdefRecognized;
  end;

implementation

{ === Hilfsfunktionen ============================================== }

// Konsumiert alle Tokens und liefert die Liste der Identifier-Werte
// (case-insensitiv lower). Mit EnableConditionalSkipping prueft das,
// welche Idents im aktiven Branch landen.
function CollectIdents(const Source: string;
  const Defines: array of string; SkipEnabled: Boolean): TStringList;
var
  Lex : TLexer;
  Tok : TToken;
begin
  Result := TStringList.Create;
  Lex := TLexer.Create(Source);
  try
    for var D in Defines do
      Lex.AddDefine(D);
    if SkipEnabled then Lex.EnableConditionalSkipping;
    repeat
      Tok := Lex.Next;
      if Tok.Kind = tkIdent then
        Result.Add(LowerCase(Tok.Value));
    until Tok.Kind = tkEof;
  finally
    Lex.Free;
  end;
end;

function MaxDepthAfterScan(const Source: string): Integer;
var
  Lex : TLexer;
  Tok : TToken;
begin
  Lex := TLexer.Create(Source);
  try
    repeat Tok := Lex.Next; until Tok.Kind = tkEof;
    Result := Lex.ConditionalMaxDepth;
  finally
    Lex.Free;
  end;
end;

{ === Phase 1a ===================================================== }

procedure TTestLexerConditionals.Phase1a_NoIfdef_DepthZero;
var
  Lex : TLexer;
  Tok : TToken;
begin
  Lex := TLexer.Create('procedure Foo; begin x := 1; end;');
  try
    repeat Tok := Lex.Next; until Tok.Kind = tkEof;
    Assert.AreEqual(0, Lex.ConditionalDepth, 'Depth ohne IFDEF muss 0 sein');
    Assert.AreEqual(0, Lex.ConditionalMaxDepth, 'MaxDepth ohne IFDEF muss 0 sein');
  finally
    Lex.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1a_IfdefEndif_DepthBalanced;
var
  Lex : TLexer;
  Tok : TToken;
begin
  Lex := TLexer.Create('{$IFDEF DEBUG} x {$ENDIF}');
  try
    repeat Tok := Lex.Next; until Tok.Kind = tkEof;
    Assert.AreEqual(0, Lex.ConditionalDepth, 'IFDEF + ENDIF -> Depth 0');
    Assert.AreEqual(1, Lex.ConditionalMaxDepth, 'MaxDepth haette 1 erreichen muessen');
  finally
    Lex.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1a_NestedIfdef_MaxDepthTracked;
begin
  Assert.AreEqual(3,
    MaxDepthAfterScan('{$IFDEF A}{$IFDEF B}{$IFDEF C}x{$ENDIF}{$ENDIF}{$ENDIF}'),
    'Nested IFDEF muss MaxDepth=3 ergeben');
end;

procedure TTestLexerConditionals.Phase1a_OrphanEndif_NoCrash;
var
  Lex : TLexer;
  Tok : TToken;
begin
  // Defekter Source: ENDIF ohne IFDEF darf den Lexer nicht crashen
  Lex := TLexer.Create('{$ENDIF} x := 1;');
  try
    repeat Tok := Lex.Next; until Tok.Kind = tkEof;
    Assert.AreEqual(0, Lex.ConditionalDepth, 'Orphan-ENDIF silent skip');
  finally
    Lex.Free;
  end;
end;

{ === Phase 1b ===================================================== }

procedure TTestLexerConditionals.Phase1b_DefaultOff_NoTokenSkip;
var
  Idents : TStringList;
begin
  // OHNE EnableConditionalSkipping muss IfBranch UND ElseBranch in der
  // Token-Liste sein - kein Skip-Verhalten.
  Idents := CollectIdents(
    '{$IFDEF UNDEFINED_X} ifbranch {$ELSE} elsebranch {$ENDIF}',
    [], False);
  try
    Assert.IsTrue(Idents.IndexOf('ifbranch') >= 0,
      'Default-OFF: ifbranch muss durchkommen');
    Assert.IsTrue(Idents.IndexOf('elsebranch') >= 0,
      'Default-OFF: elsebranch muss durchkommen');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1b_IfdefDefined_KeepsIfBranch;
var
  Idents : TStringList;
begin
  Idents := CollectIdents(
    '{$IFDEF MSWINDOWS} winbranch {$ELSE} linbranch {$ENDIF}',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(Idents.IndexOf('winbranch') >= 0,
      'MSWINDOWS defined -> if-branch aktiv');
    Assert.IsTrue(Idents.IndexOf('linbranch') < 0,
      'MSWINDOWS defined -> else-branch geskippt');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1b_IfdefUndefined_KeepsElseBranch;
var
  Idents : TStringList;
begin
  Idents := CollectIdents(
    '{$IFDEF NOT_SET} ifbranch {$ELSE} elsebranch {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(Idents.IndexOf('ifbranch') < 0,
      'NOT_SET undefined -> if-branch geskippt');
    Assert.IsTrue(Idents.IndexOf('elsebranch') >= 0,
      'NOT_SET undefined -> else-branch aktiv');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1b_IfndefUndefined_KeepsIfBranch;
var
  Idents : TStringList;
begin
  Idents := CollectIdents(
    '{$IFNDEF NOT_SET} ifbranch {$ELSE} elsebranch {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(Idents.IndexOf('ifbranch') >= 0,
      'IFNDEF NOT_SET -> if-branch aktiv (NOT_SET nicht defined)');
    Assert.IsTrue(Idents.IndexOf('elsebranch') < 0,
      'IFNDEF NOT_SET -> else-branch geskippt');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1b_NestedSkip_ParentDominates;
var
  Idents : TStringList;
begin
  // Parent-Branch skipped -> auch nested IFDEFs werden geskippt,
  // egal ob die Defines des Inner-IFDEFs gesetzt sind.
  Idents := CollectIdents(
    '{$IFDEF PARENT_OFF}' +
    '  {$IFDEF MSWINDOWS} should_skip {$ELSE} also_skip {$ENDIF}' +
    '{$ENDIF} after',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(Idents.IndexOf('should_skip') < 0,
      'Parent skip dominates - inner if branch geskippt');
    Assert.IsTrue(Idents.IndexOf('also_skip') < 0,
      'Parent skip dominates - inner else branch geskippt');
    Assert.IsTrue(Idents.IndexOf('after') >= 0,
      'Nach ENDIF normal weiter');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase1b_DefinesCaseInsensitive;
var
  Idents : TStringList;
begin
  // Defines sind case-insensitive: MSWINDOWS == mswindows == MsWindows
  Idents := CollectIdents(
    '{$IFDEF mswindows} branch {$ENDIF}',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(Idents.IndexOf('branch') >= 0,
      'Defines case-insensitive');
  finally
    Idents.Free;
  end;
end;

{ === Phase 2.1: Expression-Parser ================================= }

procedure TTestLexerConditionals.Phase2_IfDefinedX_Evaluated;
var
  Idents : TStringList;
begin
  Idents := CollectIdents(
    '{$IF Defined(MSWINDOWS)} winbranch {$ELSE} otherbranch {$ENDIF}',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(Idents.IndexOf('winbranch') >= 0,
      'Defined(MSWINDOWS) -> True');
    Assert.IsTrue(Idents.IndexOf('otherbranch') < 0,
      'Else-branch geskippt');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase2_IfDefinedAndDefined_BothMustMatch;
var
  IdentsBoth, IdentsHalfA, IdentsHalfB : TStringList;
begin
  // Beide Defines gesetzt -> aktiv
  IdentsBoth := CollectIdents(
    '{$IF Defined(MSWINDOWS) and Defined(WIN64)} active {$ENDIF}',
    ['MSWINDOWS', 'WIN64'], True);
  try
    Assert.IsTrue(IdentsBoth.IndexOf('active') >= 0,
      'AND mit beiden Defines -> aktiv');
  finally
    IdentsBoth.Free;
  end;

  // Nur ein Define gesetzt -> NICHT aktiv
  IdentsHalfA := CollectIdents(
    '{$IF Defined(MSWINDOWS) and Defined(WIN64)} active {$ENDIF}',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(IdentsHalfA.IndexOf('active') < 0,
      'AND mit nur einem Define -> inaktiv');
  finally
    IdentsHalfA.Free;
  end;

  IdentsHalfB := CollectIdents(
    '{$IF Defined(MSWINDOWS) and Defined(WIN64)} active {$ENDIF}',
    ['WIN64'], True);
  try
    Assert.IsTrue(IdentsHalfB.IndexOf('active') < 0,
      'AND mit nur anderem Define -> inaktiv');
  finally
    IdentsHalfB.Free;
  end;
end;

procedure TTestLexerConditionals.Phase2_IfDefinedOrDefined_EitherEnough;
var
  IdentsA, IdentsB, IdentsNone : TStringList;
begin
  IdentsA := CollectIdents(
    '{$IF Defined(A) or Defined(B)} active {$ENDIF}',
    ['A'], True);
  try
    Assert.IsTrue(IdentsA.IndexOf('active') >= 0, 'OR mit A -> aktiv');
  finally
    IdentsA.Free;
  end;

  IdentsB := CollectIdents(
    '{$IF Defined(A) or Defined(B)} active {$ENDIF}',
    ['B'], True);
  try
    Assert.IsTrue(IdentsB.IndexOf('active') >= 0, 'OR mit B -> aktiv');
  finally
    IdentsB.Free;
  end;

  IdentsNone := CollectIdents(
    '{$IF Defined(A) or Defined(B)} active {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(IdentsNone.IndexOf('active') < 0,
      'OR ohne Defines -> inaktiv');
  finally
    IdentsNone.Free;
  end;
end;

procedure TTestLexerConditionals.Phase2_IfNotDefined_Inverts;
var
  IdentsFpcAbsent, IdentsFpcPresent : TStringList;
begin
  IdentsFpcAbsent := CollectIdents(
    '{$IF not Defined(FPC)} delphi_branch {$ELSE} fpc_branch {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(IdentsFpcAbsent.IndexOf('delphi_branch') >= 0,
      'not Defined(FPC) -> Delphi-Branch wenn FPC nicht gesetzt');
  finally
    IdentsFpcAbsent.Free;
  end;

  IdentsFpcPresent := CollectIdents(
    '{$IF not Defined(FPC)} delphi_branch {$ELSE} fpc_branch {$ENDIF}',
    ['FPC'], True);
  try
    Assert.IsTrue(IdentsFpcPresent.IndexOf('fpc_branch') >= 0,
      'not Defined(FPC) -> FPC-Branch wenn FPC gesetzt');
  finally
    IdentsFpcPresent.Free;
  end;
end;

procedure TTestLexerConditionals.Phase2_IfCompilerVersion_ConservativelyTrue;
var
  Idents : TStringList;
begin
  // {$IF CompilerVersion >= 36} ist nicht im Mini-Parser implementiert -
  // Default-True (konservativ). Soll NICHT crashen, soll aktiv lassen.
  Idents := CollectIdents(
    '{$IF CompilerVersion >= 36} modern_code {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(Idents.IndexOf('modern_code') >= 0,
      'Unbekannter Ausdruck CompilerVersion>=36 -> konservativ True');
  finally
    Idents.Free;
  end;
end;

procedure TTestLexerConditionals.Phase2_IfMalformed_FallsBackToTrue;
var
  Idents : TStringList;
begin
  // Pathologische Direktive darf nicht crashen + soll konservativ True
  Idents := CollectIdents(
    '{$IF ((((((((( malformed} should_still_emit {$ENDIF}',
    [], True);
  try
    Assert.IsTrue(Idents.IndexOf('should_still_emit') >= 0,
      'Malformed expression -> Crash-safe + True');
  finally
    Idents.Free;
  end;
end;

{ === Phase 2.2: Alternate-Syntax (*$IFDEF*) ======================== }

procedure TTestLexerConditionals.Phase2_AlternateSyntax_IfdefRecognized;
var
  IdentsWith, IdentsWithout : TStringList;
begin
  IdentsWith := CollectIdents(
    '(*$IFDEF MSWINDOWS*) winbranch (*$ELSE*) other (*$ENDIF*)',
    ['MSWINDOWS'], True);
  try
    Assert.IsTrue(IdentsWith.IndexOf('winbranch') >= 0,
      'Alternate-Syntax IFDEF erkannt + aktiv');
    Assert.IsTrue(IdentsWith.IndexOf('other') < 0,
      'Alternate-Syntax ELSE erkannt + geskippt');
  finally
    IdentsWith.Free;
  end;

  IdentsWithout := CollectIdents(
    '(*$IFDEF NOT_SET*) ifbranch (*$ELSE*) elsebranch (*$ENDIF*)',
    [], True);
  try
    Assert.IsTrue(IdentsWithout.IndexOf('ifbranch') < 0,
      'Alternate-Syntax mit undefined-X -> if geskippt');
    Assert.IsTrue(IdentsWithout.IndexOf('elsebranch') >= 0,
      'Alternate-Syntax mit undefined-X -> else aktiv');
  finally
    IdentsWithout.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLexerConditionals);

end.
