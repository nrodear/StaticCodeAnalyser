unit uTestUninitVarUnicodeIdent;

// Tests fuer SCA166 (TUninitVarDetector) mit Unicode-Bezeichnern
// (Charge D1, 2026-10-24, Ausloeser ShowcaseDemo uLegacyImport.pas).
//
// Delphi erlaubt Unicode-Buchstaben in Bezeichnern, der geteilte TLexer
// liest aber nur A..Z/a..z/0..9/_ und zerlegt 'Am<U+043E>unt' in 'Am' +
// tkUnknown + 'unt'. SCA166 meldete das Bruchstueck 'Am' als Error-Tier-
// Fund "Am is read ... but never assigned". Der Detektor ueberspringt
// solche Bruchstuecke jetzt (uUninitVar.IsUnicodeIdentFragment).
//
// Jede Quelle traegt eine POSITIVE Wache (echte ASCII-Variable, die
// gemeldet werden MUSS); die Tests verlangen GENAU einen Fund - ohne die
// Aenderung sind es zwei (Wache + Bruchstueck), also rot.
//
// Die Testdatei bleibt ASCII: die Nicht-ASCII-Zeichen entstehen ueber
// #$nnnn-Literale. FindingsOfFile schreibt UTF-8 mit BOM (SCA166 ist nur
// dort registriert und liest die Quellzeilen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUninitVarUnicodeIdent = class
  public
    // ---- Bruchstueck nicht melden (je mit Wache) --------------------------
    [Test] procedure CyrillicInsideName_ShowcasePattern_NotReported;
    [Test] procedure LatinUmlautAtNameEnd_NotReported;
    // ---- Echte Variablen bleiben gemeldet ---------------------------------
    [Test] procedure RealVarBeforeFragmentInNameList_StillReported;
    [Test] procedure AsciiTwinOfFragment_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

const
  CRLF   = #13#10;
  CYR_O  = #$043E;   // kyrillisches o (Homoglyph zu lateinisch o)
  LAT_AE = #$00E4;   // lateinisches a mit Trema

  // Wache: 'Amount' (ASCII) wird gelesen, aber nie geschrieben - MUSS
  // gemeldet werden.
  GUARD =
    'function Guard(const S: string): Integer;' + CRLF +
    'var' + CRLF +
    '  Amount: Integer;' + CRLF +
    'begin' + CRLF +
    '  if S = '''' then' + CRLF +
    '    Result := Amount' + CRLF +
    '  else' + CRLF +
    '    Result := 0;' + CRLF +
    'end;' + CRLF;

function WrapUnit(const ABody: string): string;
begin
  Result := 'unit u;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    ABody + 'end.' + CRLF;
end;

// Alle SCA166-Funde; der einzige erwartete muss AExpectedText enthalten.
procedure AssertSingleFinding(const ASrc, AExpectedText, AWhy: string);
var
  L : TObjectList<TLeakFinding>;
  F : TLeakFinding;
  N : Integer;
  Msgs : string;
begin
  L := TFindingHelper.FindingsOfFile(ASrc);
  try
    N := 0;
    Msgs := '';
    for F in L do
      if F.Kind = fkUninitVar then
      begin
        Inc(N);
        Msgs := Msgs + ' | ' + F.LineNumber + ': ' + F.MissingVar;
      end;
    Assert.AreEqual<Integer>(1, N, AWhy + ' - Funde:' + Msgs);
    Assert.IsTrue(Pos(AExpectedText, Msgs) > 0,
      'Der Fund muss die echte Variable nennen (' + AExpectedText + '):' + Msgs);
  finally
    L.Free;
  end;
end;

procedure TTestUninitVarUnicodeIdent.CyrillicInsideName_ShowcasePattern_NotReported;
var
  A : string;
begin
  // Muster aus ShowcaseDemo uLegacyImport.ParseLine: zugewiesen, dann
  // gelesen - korrekt initialisiert, also kein Fund. Vorher: "Am is read
  // on line 8 but never assigned" (Error).
  A := 'Am' + CYR_O + 'unt';
  AssertSingleFinding(WrapUnit(
    'function ParseIt(const S: string): Integer;' + CRLF +
    'var' + CRLF +
    '  ' + A + ': Integer;' + CRLF +
    'begin' + CRLF +
    '  ' + A + ' := StrToIntDef(S, 0);' + CRLF +
    '  if ' + A + ' <> 0 then' + CRLF +
    '    Result := ' + A + CRLF +
    '  else' + CRLF +
    '    Result := 1;' + CRLF +
    'end;' + CRLF +
    GUARD),
    'Uninitialised variable: Amount ',
    'Das Bruchstueck "Am" eines Unicode-Bezeichners ist keine Variable');
end;

procedure TTestUninitVarUnicodeIdent.LatinUmlautAtNameEnd_NotReported;
var
  W : string;
begin
  // Nicht-ASCII-Buchstabe am Namensende: der Lexer liefert 'Wert'.
  W := 'Wert' + LAT_AE;
  AssertSingleFinding(WrapUnit(
    'function Calc: Integer;' + CRLF +
    'var' + CRLF +
    '  ' + W + ': Integer;' + CRLF +
    'begin' + CRLF +
    '  ' + W + ' := 5;' + CRLF +
    '  Result := ' + W + ' * 2;' + CRLF +
    'end;' + CRLF +
    GUARD),
    'Uninitialised variable: Amount ',
    'Das Bruchstueck "Wert" eines Unicode-Bezeichners ist keine Variable');
end;

procedure TTestUninitVarUnicodeIdent.RealVarBeforeFragmentInNameList_StillReported;
var
  A : string;
begin
  // 'X, Am<o>unt: Integer' - der Parser legt X und das Bruchstueck an;
  // X wird vor der Zuweisung gelesen und bleibt ein Fund, das Bruchstueck
  // nicht.
  A := 'Am' + CYR_O + 'unt';
  AssertSingleFinding(WrapUnit(
    'function P: Integer;' + CRLF +
    'var' + CRLF +
    '  X, ' + A + ': Integer;' + CRLF +
    'begin' + CRLF +
    '  Result := X;' + CRLF +
    '  ' + A + ' := 2;' + CRLF +
    '  X := ' + A + ';' + CRLF +
    'end;' + CRLF),
    ': X read on line',
    'X ist eine echte Variable und wird vor der Zuweisung gelesen');
end;

procedure TTestUninitVarUnicodeIdent.AsciiTwinOfFragment_StillReported;
var
  A : string;
begin
  // Echtes ASCII-'Am' neben 'Am<o>unt' in derselben Methode: das saubere
  // Vorkommen haelt die Variable in der Inventur (Fund bleibt). Die zweite
  // Routine enthaelt nur das Bruchstueck (kein Fund).
  A := 'Am' + CYR_O + 'unt';
  AssertSingleFinding(WrapUnit(
    'function Q: Integer;' + CRLF +
    'var' + CRLF +
    '  Am: Integer;' + CRLF +
    '  ' + A + ': Integer;' + CRLF +
    'begin' + CRLF +
    '  Result := Am;' + CRLF +
    '  ' + A + ' := 1;' + CRLF +
    '  Am := ' + A + ';' + CRLF +
    'end;' + CRLF +
    'function ParseIt(const S: string): Integer;' + CRLF +
    'var' + CRLF +
    '  ' + A + ': Integer;' + CRLF +
    'begin' + CRLF +
    '  ' + A + ' := StrToIntDef(S, 0);' + CRLF +
    '  Result := ' + A + ';' + CRLF +
    'end;' + CRLF),
    ': Am read on line',
    'Das echte ASCII-Am bleibt gemeldet, das Bruchstueck in ParseIt nicht');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUninitVarUnicodeIdent);

end.
