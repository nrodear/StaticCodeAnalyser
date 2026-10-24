unit uTestRdxIntroEdits;

// reDelphix - Tests fuer uRdxIntroEdits (Code-Aktion "Lokale Konstante
// einfuehren", Refactoring ohne Fund): der Schreibschritt von C1h Ende zu
// Ende. Jeder Fall baut einen kleinen Puffer als UTF-8-Bytes aus den echten
// Zeilen der Demo-Dateien des Labors (VarNameProject\demo, Stand HEAD =
// 41bccb23, samt Kommentaren), holt mit TargetAt das Ziel fuer den Caret
// (Zeile, Zeichenspalte), wendet IntroduceEdits mit ApplyIntroEdits an (der
// IOTAEditWriter nachgestellt) und vergleicht den GANZEN Text danach mit
// einem von Hand geschriebenen Soll-Text. Dazu der Auswahlvertrag (der
// Name steht in Zeile DeclRow ab Plan.NameCol und in Zeile UseRow ab jeder
// Spalte aus Plan.NewCols), TextOf, PrevCodeRow, die Ablehnungen von
// TargetAt und der Vertrag von ApplyIntroEdits.
//
// 1:1 aus dem Labor VarNameProject (uTestVnpEdits, Stand 2026-10-14 nach dem
// Review F/B vom 2026-10-13, Entscheid E24: erst der im Labor gemessene
// Stand, die Zusammenlegung mit uRdxCodeMap/uRdxBufferMath folgt
// spaeter). Dort heisst
// ApplyIntroEdits ApplyByteEdits - daher die Testnamen ApplyByteEdits*.
// README meint hier das des Labors (VarNameProject\README.md).
//
// Vertrag: die Interface-Kommentare von uRdxIntroEdits und uRdxIntroPlan,
// README (Varianten, Grenzen, Messpunkte). Alle Sollwerte sind von Hand
// abgeleitet. Zeilen 1-basiert, Spalten 1-basierte Zeichenspalten (UTF-16),
// Offsets UTF-8-Bytes ab Pufferanfang. Die Quelle ist ASCII: Umlaute als
// #$00FC (ue), #$00DF (ss), #$00F6 (oe), #$20AC (Euro), #$D83D#$DE00
// (Surrogatpaar). Eingaben und Soll-Texte der laengeren Faelle stehen als
// Datenfunktionen vor den Tests; wo ein Test Byte-Offsets aus den Zeilen
// herleitet, stehen die Zeilen im Test.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIntroEdits = class
  public
    // TextOf: Zeilen, Byte-Anfaenge, Zeilenende
    [Test] procedure TextOfCrLfFinalEol;
    [Test] procedure TextOfLfNoFinalEolAndEmpty;
    [Test] procedure TextOfMixedFirstEolWins;
    [Test] procedure TextOfBomStartsInBytes;
    // PrevCodeRow
    [Test] procedure PrevCodeRowSkipsBlankAndComments;
    // TargetAt: Ablehnungen und freier Name
    [Test] procedure TargetAtRefusesRowsAndMissingEol;
    [Test] procedure TargetAtNameSkipsTakenName;
    // C1h Ende zu Ende: Demo-Faelle 1-6, CR LF, LF, BOM
    [Test] procedure C1hFall1CrLfAndLf;
    [Test] procedure C1hFall2IfLineCrLf;
    [Test] procedure C1hFall3WrapCrLf;
    [Test] procedure C1hElseWrapTabsLf;
    [Test] procedure C1hFall4FractionCrLf;
    [Test] procedure C1hFall5TabHexCrLf;
    [Test] procedure C1hFall6UmlautCrLfByteOffsets;
    [Test] procedure C1hFall6BomDemoFile;
    [Test] procedure C1hMultibyteBetweenLiterals;
    [Test] procedure C1hStringAndCommentStay;
    [Test] procedure C1hUnicodeIdentifierDigitStays;
    // ApplyIntroEdits
    [Test] procedure ApplyByteEditsInListOrder;
    [Test] procedure ApplyByteEditsRaises;
  end;

implementation

uses
  System.SysUtils, uRdxIntroEdits;

const
  // Typisiert: ein einzelnes #10 waere sonst eine Char-Konstante.
  CRLF : string = #13#10;
  LF   : string = #10;
  NAME_BASE = 'MagicNr';

// Die Zeilen ab AFrom mit AEol verbunden. Rekursiv statt Verkettung in
// einer Schleife (SCA110) - es sind nur wenige Zeilen.
function JoinFrom(const ALines: array of string; AFrom: Integer;
  const AEol: string): string;
begin
  if AFrom = High(ALines) then
    Result := ALines[AFrom]
  else
    Result := ALines[AFrom] + AEol + JoinFrom(ALines, AFrom + 1, AEol);
end;

// Eingabe bzw. Soll-Text: die Zeilen mit AEol verbinden. Ein leeres letztes
// Element ergibt ein Zeilenende am Pufferende.
function JoinLines(const ALines: array of string; const AEol: string): string;
begin
  Result := '';
  if Length(ALines) > 0 then
    Result := JoinFrom(ALines, 0, AEol);
end;

function Utf8BytesOf(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

function Utf8TextOf(const ABytes: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(ABytes);
end;

function MakeEdit(AOffset, ALen: Integer; const AText: string): TRdxIntroByteEdit;
begin
  Result.Offset := AOffset;
  Result.Len := ALen;
  Result.Text := AText;
end;

// C1h ohne IDE, erster Teil: Text der Pufferbytes, Ziel fuer den Caret
// (ARow, ACol), die Ersetzungen des Writers.
function EditsAt(const ASource: TBytes; ARow, ACol: Integer;
  out ATarget: TRdxIntroTarget): TRdxIntroByteEdits;
var
  T : TRdxIntroText;
begin
  T := TextOf(ASource);
  ATarget := TargetAt(T, ARow, ACol, NAME_BASE);
  Assert.IsTrue(ATarget.Plan.Ok, 'Plan abgelehnt: ' + ATarget.Plan.Reason);
  Result := IntroduceEdits(T, ATarget);
end;

// C1h ohne IDE: die Ersetzungen des Writers der Reihe nach angewandt - die
// Bytes danach.
function RunC1hBytes(const ASource: TBytes; ARow, ACol: Integer;
  out ATarget: TRdxIntroTarget): TBytes;
begin
  Result := ApplyIntroEdits(ASource, EditsAt(ASource, ARow, ACol, ATarget));
end;

// Dasselbe fuer einen Puffer ohne BOM, als Text.
function RunC1h(const ASource: string; ARow, ACol: Integer;
  out ATarget: TRdxIntroTarget): string;
begin
  Result := Utf8TextOf(RunC1hBytes(Utf8BytesOf(ASource), ARow, ACol,
    ATarget));
end;

// Auswahlvertrag nach dem Schreiben: DeclRow/UseRow wie erwartet, der Name
// steht in Zeile DeclRow ab Plan.NameCol und in Zeile UseRow ab jeder
// Spalte aus Plan.NewCols (AUses Stellen). AExpLines ist der Soll-Text
// Zeile fuer Zeile; der Aufrufer hat vorher den GANZEN Ergebnistext gegen
// ihn geprueft - es sind also die Zeilen des Ergebnisses.
procedure CheckSelection(const AExpLines: array of string;
  const ATarget: TRdxIntroTarget; ADeclRow, AUseRow, AUses: Integer);
var
  Col : Integer;
begin
  Assert.AreEqual<Integer>(ADeclRow, ATarget.DeclRow, 'DeclRow');
  Assert.AreEqual<Integer>(AUseRow, ATarget.UseRow, 'UseRow');
  Assert.AreEqual<Integer>(AUses, Length(ATarget.Plan.NewCols),
    'Zahl der Namensstellen in der Anweisung');
  Assert.IsTrue(ATarget.Name <> '', 'Name leer');
  Assert.AreEqual(ATarget.Name, Copy(AExpLines[ADeclRow - 1],
    ATarget.Plan.NameCol, Length(ATarget.Name)),
    Format('Name in Zeile %d ab Spalte %d', [ADeclRow, ATarget.Plan.NameCol]));
  for Col in ATarget.Plan.NewCols do
    Assert.AreEqual(ATarget.Name, Copy(AExpLines[AUseRow - 1], Col,
      Length(ATarget.Name)),
      Format('Name in Zeile %d ab Spalte %d', [AUseRow, Col]));
end;

// Eine Ersetzung des Writers wie erwartet: Offset und Len in Bytes, Text.
procedure CheckEdit(const AEdit: TRdxIntroByteEdit; AOffset, ALen: Integer;
  const AText, AWhat: string);
begin
  Assert.AreEqual<Integer>(AOffset, AEdit.Offset, AWhat + ': Offset');
  Assert.AreEqual<Integer>(ALen, AEdit.Len, AWhat + ': Len');
  Assert.AreEqual(AText, AEdit.Text, AWhat + ': Text');
end;

// Wirft ApplyIntroEdits EArgumentException?
function ApplyRaises(const ABytes: TBytes;
  const AEdits: TRdxIntroByteEdits): Boolean;
begin
  Result := False;
  try
    ApplyIntroEdits(ABytes, AEdits);
  except
    on EArgumentException do
      Result := True;
  end;
end;

// --- Daten: Eingaben und Soll-Texte, von Hand geschrieben ----------------

// Fall 1: Scale aus VarNameDemo.pas (HEAD, Zeilen 17-21).
function ScaleSource: TArray<string>;
begin
  Result := [
    'function Scale(Value: Integer): Integer;',
    'begin',
    '  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.',
    '  Result := Value * 42 + 42;',
    'end;',
    ''];
end;

// Fall 1 danach: beide 42 der Anweisung ersetzt, die im Kommentar nicht.
function ScaleExpected: TArray<string>;
begin
  Result := [
    'function Scale(Value: Integer): Integer;',
    'begin',
    '  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.',
    '  const MagicNr01 = 42;',
    '  Result := Value * MagicNr01 + MagicNr01;',
    'end;',
    ''];
end;

// Fall 2 und 3: Clamp aus VarNameDemo.pas (HEAD, Zeilen 23-31).
function ClampSource: TArray<string>;
begin
  Result := [
    'function Clamp(Value: Integer): Integer;',
    'begin',
    '  Result := Value;',
    '  // Fall 2: Caret auf 1000 in der if-Zeile -> angeboten.',
    '  if Result > 1000 then',
    '    // Fall 3: Caret auf 999 -> ABGELEHNT (die Zeile darueber endet mit',
    '    // then; die Deklaration wuerde zum Zweig).',
    '    Result := 999;',
    'end;',
    ''];
end;

// Fall 2 danach: die Deklaration vor dem if, der Zweig unveraendert.
function ClampFall2Expected: TArray<string>;
begin
  Result := [
    'function Clamp(Value: Integer): Integer;',
    'begin',
    '  Result := Value;',
    '  // Fall 2: Caret auf 1000 in der if-Zeile -> angeboten.',
    '  const MagicNr01 = 1000;',
    '  if Result > MagicNr01 then',
    '    // Fall 3: Caret auf 999 -> ABGELEHNT (die Zeile darueber endet mit',
    '    // then; die Deklaration wuerde zum Zweig).',
    '    Result := 999;',
    'end;',
    ''];
end;

// Fall 3 danach: begin direkt unter der if-Zeile, end; unter der
// Anweisung, beide mit der Einrueckung der if-Zeile; die Kommentare im
// Block.
function ClampFall3Expected: TArray<string>;
begin
  Result := [
    'function Clamp(Value: Integer): Integer;',
    'begin',
    '  Result := Value;',
    '  // Fall 2: Caret auf 1000 in der if-Zeile -> angeboten.',
    '  if Result > 1000 then',
    '  begin',
    '    // Fall 3: Caret auf 999 -> ABGELEHNT (die Zeile darueber endet mit',
    '    // then; die Deklaration wuerde zum Zweig).',
    '    const MagicNr01 = 999;',
    '    Result := MagicNr01;',
    '  end;',
    'end;',
    ''];
end;

// Fall 4: Area aus VarNameDemo.pas (HEAD, Zeilen 33-37).
function AreaSource: TArray<string>;
begin
  Result := [
    'function Area(Width, Height: Double): Double;',
    'begin',
    '  // Fall 4: Bruchzahl.',
    '  Result := Width * Height * 0.5;',
    'end;',
    ''];
end;

function AreaExpected: TArray<string>;
begin
  Result := [
    'function Area(Width, Height: Double): Double;',
    'begin',
    '  // Fall 4: Bruchzahl.',
    '  const MagicNr01 = 0.5;',
    '  Result := Width * Height * MagicNr01;',
    'end;',
    ''];
end;

// Fall 5: Mask aus VarNameDemo.pas (HEAD, Zeilen 39-43), Tab-Einrueckung.
function MaskSource: TArray<string>;
begin
  Result := [
    'function Mask(Value: Cardinal): Cardinal;',
    'begin',
    #9'// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.',
    #9'Result := Value and $FF00;',
    'end;',
    ''];
end;

function MaskExpected: TArray<string>;
begin
  Result := [
    'function Mask(Value: Cardinal): Cardinal;',
    'begin',
    #9'// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.',
    #9'const MagicNr01 = $FF00;',
    #9'Result := Value and MagicNr01;',
    'end;',
    ''];
end;

// Fall 6 mit BOM: demo/VarNameDemoUmlaut.pas (HEAD) ganz, ohne den BOM
// (den setzt der Test davor), Zeilenende LF wie im Repo.
function UmlautDemoSource: TArray<string>;
begin
  Result := [
    'unit VarNameDemoUmlaut;',
    '',
    '// VarNameProject - Fall 6 (Messpunkt M10): Nicht-ASCII VOR dem Literal.',
    '// Diese Datei ist ABSICHTLICH UTF-8 mit BOM und enthaelt Umlaute und das',
    '// Euro-Zeichen (sonst gilt im Repo: Pascal-Quellen nur ASCII) - sie misst,',
    '// ob TOTACharPos.CharIndex Bytes oder Zeichen zaehlt: ''Gr'#$00FC#$00DF
      + 'e '#$20AC''' sind 7',
    '// Zeichen, aber 11 UTF-8-Bytes.',
    '//   1. Caret direkt hinter das Euro-Zeichen setzen,',
    '//      Tools > VarNameProject > Sonde: CharIndex am Caret.',
    '//   2. Caret auf die 42, Varianten wie in VarNameDemo.pas.',
    '',
    'interface',
    '',
    'function Greeting(Count: Integer): string;',
    '',
    'implementation',
    '',
    'uses',
    '  System.SysUtils;',
    '',
    'function Greeting(Count: Integer): string;',
    'begin',
    '  Result := ''Gr'#$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * 42);',
    'end;',
    '',
    'end.',
    ''];
end;

// Soll-Text dazu nach C1h mit dem Caret auf der 42 (Zeile 23): Deklaration
// als neue Zeile 23, die Anweisung rutscht nach 24, sonst alles gleich.
function UmlautDemoExpected: TArray<string>;
begin
  Result := [
    'unit VarNameDemoUmlaut;',
    '',
    '// VarNameProject - Fall 6 (Messpunkt M10): Nicht-ASCII VOR dem Literal.',
    '// Diese Datei ist ABSICHTLICH UTF-8 mit BOM und enthaelt Umlaute und das',
    '// Euro-Zeichen (sonst gilt im Repo: Pascal-Quellen nur ASCII) - sie misst,',
    '// ob TOTACharPos.CharIndex Bytes oder Zeichen zaehlt: ''Gr'#$00FC#$00DF
      + 'e '#$20AC''' sind 7',
    '// Zeichen, aber 11 UTF-8-Bytes.',
    '//   1. Caret direkt hinter das Euro-Zeichen setzen,',
    '//      Tools > VarNameProject > Sonde: CharIndex am Caret.',
    '//   2. Caret auf die 42, Varianten wie in VarNameDemo.pas.',
    '',
    'interface',
    '',
    'function Greeting(Count: Integer): string;',
    '',
    'implementation',
    '',
    'uses',
    '  System.SysUtils;',
    '',
    'function Greeting(Count: Integer): string;',
    'begin',
    '  const MagicNr01 = 42;',
    '  Result := ''Gr'#$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * MagicNr01);',
    'end;',
    '',
    'end.',
    ''];
end;

// Zwei Routinen; MagicNr01 steht schon in der ersten (als Inline-var des
// Anwenders - der Name zaehlt, nicht die Form).
function TakenNameSource: TArray<string>;
begin
  Result := [
    'procedure A;',
    'begin',
    '  var MagicNr01 := 42;',
    'end;',
    '',
    'function B(Value: Integer): Integer;',
    'begin',
    '  Result := Value * 7;',
    'end;',
    ''];
end;

function TakenNameExpected: TArray<string>;
begin
  Result := [
    'procedure A;',
    'begin',
    '  var MagicNr01 := 42;',
    'end;',
    '',
    'function B(Value: Integer): Integer;',
    'begin',
    '  const MagicNr02 = 7;',
    '  Result := Value * MagicNr02;',
    'end;',
    ''];
end;

// Zweig hinter else ohne begin, Tab-Einrueckung.
function ElseBranchSource: TArray<string>;
begin
  Result := [
    'procedure P(Flag: Boolean);',
    'begin',
    #9'if Flag then',
    #9#9'X := 1',
    #9'else',
    #9#9'X := 2 * 60;',
    'end;',
    ''];
end;

// Danach: begin/end; mit dem Tab der else-Zeile, die Deklaration mit den
// zwei Tabs der Anweisung; nur die 60 ersetzt, nicht die 2.
function ElseBranchExpected: TArray<string>;
begin
  Result := [
    'procedure P(Flag: Boolean);',
    'begin',
    #9'if Flag then',
    #9#9'X := 1',
    #9'else',
    #9'begin',
    #9#9'const MagicNr01 = 60;',
    #9#9'X := 2 * MagicNr01;',
    #9'end;',
    'end;',
    ''];
end;

// Zweigzeile, die mit einem Kommentar BEGINNT (danach Code).
function CommentedBranchSource: TArray<string>;
begin
  Result := [
    'procedure P(Flag: Boolean);',
    'begin',
    '  (* Zweig *) if Flag then',
    '    X := 60;',
    'end;',
    ''];
end;

// Danach: der Zweig ist ein Block, begin/end; mit der Einrueckung der
// Zweigzeile (die zwei Leerzeichen vor dem Kommentar).
function CommentedBranchExpected: TArray<string>;
begin
  Result := [
    'procedure P(Flag: Boolean);',
    'begin',
    '  (* Zweig *) if Flag then',
    '  begin',
    '    const MagicNr01 = 60;',
    '    X := MagicNr01;',
    '  end;',
    'end;',
    ''];
end;

{ TTestRdxIntroEdits }

// TextOf, CR LF mit Zeilenende am Pufferende: CR LF gehoert nicht zur
// Zeile, die letzte Zeile ist leer, Starts in Bytes, Eol = #13#10, Text ist
// der ganze Puffer.
procedure TTestRdxIntroEdits.TextOfCrLfFinalEol;
var
  T : TRdxIntroText;
begin
  T := TextOf(Utf8BytesOf('unit A;'#13#10'begin'#13#10'end.'#13#10));
  Assert.AreEqual<Integer>(4, Length(T.Lines), 'Zahl der Zeilen');
  Assert.AreEqual(JoinLines(['unit A;', 'begin', 'end.', ''], '|'),
    JoinLines(T.Lines, '|'), 'Zeilen (die letzte leer)');
  Assert.AreEqual<Integer>(4, Length(T.Starts), 'Zahl der Zeilenanfaenge');
  Assert.AreEqual<Integer>(0, T.Starts[0], 'Start Zeile 1');
  Assert.AreEqual<Integer>(9, T.Starts[1], 'Start Zeile 2');
  Assert.AreEqual<Integer>(16, T.Starts[2], 'Start Zeile 3');
  Assert.AreEqual<Integer>(22, T.Starts[3], 'Start Zeile 4 = Pufferende');
  Assert.AreEqual(CRLF, T.Eol, 'Eol');
  Assert.AreEqual('unit A;'#13#10'begin'#13#10'end.'#13#10, T.Text, 'Text');
end;

// TextOf, nur LF und kein Zeilenende am Pufferende: die letzte Zeile hat
// Text und kein eigenes Ende (Ends ''), Eol = #10 (das erste Zeilenende).
// Leerer Puffer: genau eine leere Zeile ab Byte 0, ohne Zeilenende - Eol
// ist dann CR LF (TRdxIntroText: das Zeilenende der IDE unter Windows).
procedure TTestRdxIntroEdits.TextOfLfNoFinalEolAndEmpty;
var
  T : TRdxIntroText;
begin
  T := TextOf(Utf8BytesOf('a := 1;'#10#10'b'));
  Assert.AreEqual<Integer>(3, Length(T.Lines), 'Zahl der Zeilen');
  Assert.AreEqual(JoinLines(['a := 1;', '', 'b'], '|'),
    JoinLines(T.Lines, '|'), 'Zeilen');
  Assert.AreEqual<Integer>(3, Length(T.Starts), 'Zahl der Zeilenanfaenge');
  Assert.AreEqual<Integer>(0, T.Starts[0], 'Start Zeile 1');
  Assert.AreEqual<Integer>(8, T.Starts[1], 'Start Zeile 2');
  Assert.AreEqual<Integer>(9, T.Starts[2], 'Start Zeile 3');
  Assert.AreEqual(LF, T.Eol, 'Eol ohne CR LF');
  Assert.AreEqual<Integer>(3, Length(T.Ends), 'Zahl der Zeilenenden');
  Assert.AreEqual(LF, T.Ends[0], 'Ende Zeile 1');
  Assert.AreEqual(LF, T.Ends[1], 'Ende Zeile 2');
  Assert.AreEqual('', T.Ends[2], 'Ende Zeile 3: keines');
  Assert.AreEqual(LF, RowEol(T, 3), 'RowEol Zeile 3: Rueckfall Eol');
  T := TextOf(nil);
  Assert.AreEqual<Integer>(1, Length(T.Lines), 'leer: Zahl der Zeilen');
  Assert.AreEqual('', T.Lines[0], 'leer: Zeile 1');
  Assert.AreEqual<Integer>(1, Length(T.Starts),
    'leer: Zahl der Zeilenanfaenge');
  Assert.AreEqual<Integer>(0, T.Starts[0], 'leer: Start Zeile 1');
  Assert.AreEqual(CRLF, T.Eol, 'leer: Eol CR LF (kein Zeilenende im Puffer)');
  Assert.AreEqual('', T.Ends[0], 'leer: kein Zeilenende');
  Assert.AreEqual(CRLF, RowEol(T, 1), 'leer: RowEol Rueckfall');
  Assert.AreEqual('', T.Text, 'leer: Text');
end;

// TextOf gemischt: LF beendet die Zeile, nur EIN CR DIREKT davor gehoert
// zum Zeilenende (ein einzelnes CR bleibt in der Zeile, von CR CR LF das
// erste). Jede Zeile traegt ihr eigenes Ende (Ends/RowEol); Eol ist das
// Ende der ERSTEN Zeile, die eines hat - nicht mehr "CR LF, sobald eines
// vorkommt" (Entscheid 2026-10-13 zu Minor 5: eingefuegte Zeilen folgen
// ihrer Nachbarzeile, Eol ist nur noch Rueckfall, wie
// uRdxBufferMath.BufferEol). Nur einzelne CR: kein Zeilenende, Eol CR LF.
// Ein CR am Pufferende ohne LF gehoert laut Interface zum Zeilenende der
// letzten Zeile (sie endet mit 'x'); Ends traegt dafuer '', RowEol den
// Rueckfall.
procedure TTestRdxIntroEdits.TextOfMixedFirstEolWins;
var
  T : TRdxIntroText;
begin
  T := TextOf(Utf8BytesOf('a'#13#10'b'#10'c'#13'd'#10));
  Assert.AreEqual<Integer>(4, Length(T.Lines), 'Zahl der Zeilen');
  Assert.AreEqual(JoinLines(['a', 'b', 'c'#13'd', ''], '|'),
    JoinLines(T.Lines, '|'), 'Zeilen');
  Assert.AreEqual<Integer>(4, Length(T.Starts), 'Zahl der Zeilenanfaenge');
  Assert.AreEqual<Integer>(3, T.Starts[1], 'Start Zeile 2');
  Assert.AreEqual<Integer>(5, T.Starts[2], 'Start Zeile 3');
  Assert.AreEqual<Integer>(9, T.Starts[3], 'Start Zeile 4');
  Assert.AreEqual(CRLF, T.Eol, 'CR LF zuerst: Eol CR LF');
  Assert.AreEqual(CRLF, RowEol(T, 1), 'Zeile 1 endet mit CR LF');
  Assert.AreEqual(LF, RowEol(T, 2), 'Zeile 2 endet mit LF');
  Assert.AreEqual(LF, RowEol(T, 3), 'Zeile 3: das einzelne CR zaehlt nicht');
  Assert.AreEqual('', T.Ends[3], 'Zeile 4 ohne Ende');
  Assert.AreEqual(CRLF, RowEol(T, 4), 'Zeile 4: Rueckfall Eol');
  T := TextOf(Utf8BytesOf('x'#10'y'#13#10'z'));
  Assert.AreEqual(JoinLines(['x', 'y', 'z'], '|'), JoinLines(T.Lines, '|'),
    'LF zuerst: Zeilen');
  Assert.AreEqual<Integer>(2, T.Starts[1], 'LF zuerst: Start Zeile 2');
  Assert.AreEqual<Integer>(5, T.Starts[2], 'LF zuerst: Start Zeile 3');
  Assert.AreEqual(LF, T.Eol, 'LF zuerst, CR LF danach: das erste gilt');
  Assert.AreEqual(CRLF, RowEol(T, 2), 'LF zuerst: Zeile 2 behaelt CR LF');
  Assert.AreEqual(LF, RowEol(T, 3), 'LF zuerst: Zeile 3 Rueckfall LF');
  T := TextOf(Utf8BytesOf('a'#13'b'));
  Assert.AreEqual<Integer>(1, Length(T.Lines), 'nur CR: eine Zeile');
  Assert.AreEqual('a'#13'b', T.Lines[0], 'nur CR: das CR bleibt in der Zeile');
  Assert.AreEqual(CRLF, T.Eol, 'nur CR: kein Zeilenende, Eol CR LF');
  T := TextOf(Utf8BytesOf('x'#13#13#10'y'));
  Assert.AreEqual(JoinLines(['x'#13, 'y'], '|'), JoinLines(T.Lines, '|'),
    'CR CR LF: nur das CR direkt vor LF gehoert zum Zeilenende');
  Assert.AreEqual<Integer>(4, T.Starts[1], 'CR CR LF: Start Zeile 2');
  Assert.AreEqual(CRLF, T.Eol, 'CR CR LF: Eol');
  Assert.AreEqual(CRLF, RowEol(T, 1), 'CR CR LF: Zeile 1 endet mit CR LF');
  T := TextOf(Utf8BytesOf('x'#13));
  Assert.AreEqual<Integer>(1, Length(T.Lines), 'CR am Ende: eine Zeile');
  Assert.AreEqual('x', T.Lines[0],
    'CR am Ende: als letztes Byte gehoert es zum Zeilenende (TRdxIntroText)');
  Assert.AreEqual('', T.Ends[0], 'CR am Ende: Ends traegt kein LF-Ende');
  Assert.AreEqual(CRLF, T.Eol, 'CR am Ende: Eol CR LF (Rueckfall)');
  Assert.AreEqual(CRLF, RowEol(T, 1), 'CR am Ende: RowEol Rueckfall');
end;

// TextOf mit UTF-8-BOM und Mehrbyte-Zeichen: Starts zaehlen Bytes ab
// Pufferanfang, die drei BOM-Bytes mit; die Zeilen sind Zeichen. Der BOM
// bleibt Teil der ersten Zeile (U+FEFF, Start 0) - so legt es das
// Interface von TRdxIntroText fest, und so liest TEncoding.UTF8.GetString die
// Bytes (Delphi wie FPC; die fruehere Fassung liess beide Lesarten zu).
procedure TTestRdxIntroEdits.TextOfBomStartsInBytes;
var
  T : TRdxIntroText;
begin
  T := TextOf(Utf8BytesOf(#$FEFF'unit U;'#13#10'// Gr'#$00FC#$00DF'e '#$20AC
    + #13#10'end.'));
  Assert.AreEqual<Integer>(3, Length(T.Lines), 'Zahl der Zeilen');
  Assert.AreEqual<Integer>(3, Length(T.Starts), 'Zahl der Zeilenanfaenge');
  Assert.AreEqual<Integer>(0, T.Starts[0], 'Zeile 1 beginnt bei Byte 0');
  Assert.AreEqual(#$FEFF'unit U;', T.Lines[0],
    'Zeile 1 traegt das BOM-Zeichen U+FEFF');
  Assert.AreEqual('// Gr'#$00FC#$00DF'e '#$20AC, T.Lines[1], 'Zeile 2');
  Assert.AreEqual('end.', T.Lines[2], 'Zeile 3');
  // 3 BOM-Bytes + 'unit U;' (7) + CR LF
  Assert.AreEqual<Integer>(12, T.Starts[1], 'Start Zeile 2 in Bytes');
  // 12 + '// Gr..e EUR' (10 Zeichen, 14 Bytes) + CR LF
  Assert.AreEqual<Integer>(28, T.Starts[2], 'Start Zeile 3 in Bytes');
  Assert.AreEqual(CRLF, T.Eol, 'Eol');
end;

// PrevCodeRow: Leerzeilen, reine Leerraumzeilen und reine Kommentarzeilen
// ('//', '{ }', '(* *)') zaehlen nicht; Code mit Kommentar davor oder
// dahinter zaehlt; Zeile 1 selbst wird gefunden; 0, wenn darueber nichts
// mit Code steht (Dateianfang). Folge im Schreibschritt: eine Zweigzeile,
// die mit einem Kommentar beginnt, bleibt die Zweigzeile - der Zweig wird
// zum Block (als Kommentarzeile uebersprungen, liefe die Anweisung danach
// unbedingt).
procedure TTestRdxIntroEdits.PrevCodeRowSkipsBlankAndComments;
var
  T      : TRdxIntroText;
  Target : TRdxIntroTarget;
begin
  T := TextOf(Utf8BytesOf(JoinLines([
    '// Kopf: nur Kommentar',             // 1
    '{ Klammerkommentar }',               // 2
    'begin',                              // 3
    '  X := 1; // Code mit Kommentar',    // 4
    '',                                   // 5
    '  // Zeilenkommentar',               // 6
    '  { Klammerkommentar }',             // 7
    '  (* Sternkommentar *)',             // 8
    #9'  ',                               // 9 nur Leerraum
    '  Y := 2;'], CRLF)));                // 10
  Assert.AreEqual<Integer>(4, PrevCodeRow(T, 10),
    'ueber Leer- und Kommentarzeilen hinweg');
  Assert.AreEqual<Integer>(3, PrevCodeRow(T, 4), 'direkt darueber');
  Assert.AreEqual<Integer>(0, PrevCodeRow(T, 3), 'darueber nur Kommentare');
  Assert.AreEqual<Integer>(0, PrevCodeRow(T, 1), 'erste Zeile');
  T := TextOf(Utf8BytesOf(JoinLines(['begin', '  { Grenze } X := 1;',
    '  Y := 2;'], CRLF)));
  Assert.AreEqual<Integer>(2, PrevCodeRow(T, 3),
    'Kommentar vor Code: die Zeile zaehlt');
  Assert.AreEqual<Integer>(1, PrevCodeRow(T, 2), 'Zeile 1 mit Code');
  Assert.AreEqual(JoinLines(CommentedBranchExpected, CRLF),
    RunC1h(JoinLines(CommentedBranchSource, CRLF), 4, 10, Target),
    'Zweigzeile mit Kommentar davor: Text danach');
  CheckSelection(CommentedBranchExpected, Target, 5, 6, 1);
end;

// TargetAt lehnt ab (Plan.Ok = False mit Grund): Zeile 0 und Zeile 3
// hinter dem Ende. In Zeile 2 steht in derselben Spalte eine 42, die ohne
// Block planbar ist - wer die Caret-Zeile in den Puffer zieht, statt
// abzulehnen, plante sie (Zeile 0 waere auch dann abgelehnt, Zeile 1 hat
// nie Code darueber; sie prueft, dass TargetAt nicht vor den Puffer
// greift). Ohne Block darf die Anweisung die letzte Zeile ohne Zeilenende
// sein: die Deklaration bekommt CR LF, die Anweisung bleibt ohne. Ein
// Zweig ohne begin dort braucht die Zeile danach fuer 'end;' - Abbruch,
// der Grund nennt das Zeilenende; Gegenprobe: mit Zeilenende am
// Pufferende kommt 'end;' ans Pufferende.
procedure TTestRdxIntroEdits.TargetAtRefusesRowsAndMissingEol;
var
  T      : TRdxIntroText;
  Target : TRdxIntroTarget;
  Exp    : TArray<string>;
begin
  T := TextOf(Utf8BytesOf(JoinLines(['begin', '  X := 42;'], CRLF)));
  Target := TargetAt(T, 0, 8, NAME_BASE);
  Assert.IsFalse(Target.Plan.Ok, 'Zeile 0');
  Assert.IsTrue(Target.Plan.Reason <> '', 'Zeile 0: Grund fehlt');
  Target := TargetAt(T, 3, 8, NAME_BASE);
  Assert.IsFalse(Target.Plan.Ok, 'Zeile 3 hinter dem Ende');
  Assert.IsTrue(Target.Plan.Reason <> '', 'Zeile 3: Grund fehlt');
  Exp := ['begin', '  const MagicNr01 = 42;', '  X := MagicNr01;'];
  Assert.AreEqual(JoinLines(Exp, CRLF), RunC1h(JoinLines(['begin',
    '  X := 42;'], CRLF), 2, 8, Target),
    'ohne Block: letzte Zeile ohne Zeilenende');
  CheckSelection(Exp, Target, 2, 3, 1);
  T := TextOf(Utf8BytesOf(JoinLines(['begin', '  if X > 1 then',
    '    Y := 999;'], CRLF)));
  Target := TargetAt(T, 3, 10, NAME_BASE);
  Assert.IsFalse(Target.Plan.Ok, 'Block in der letzten Zeile ohne Zeilenende');
  Assert.IsTrue(Pos('Zeilenende', Target.Plan.Reason) > 0,
    'Grund nennt das Zeilenende: ' + Target.Plan.Reason);
  Exp := [
    'begin',
    '  if X > 1 then',
    '  begin',
    '    const MagicNr01 = 999;',
    '    Y := MagicNr01;',
    '  end;',
    ''];
  Assert.AreEqual(JoinLines(Exp, CRLF), RunC1h(JoinLines(['begin',
    '  if X > 1 then', '    Y := 999;', ''], CRLF), 3, 10, Target),
    'Gegenprobe mit Zeilenende');
  CheckSelection(Exp, Target, 4, 5, 1);
end;

// TargetAt: freier Name im GANZEN Puffer - MagicNr01 steht schon in einer
// anderen Routine, also MagicNr02 (README Lauf 6: "Die Nummer zaehlt hoch").
procedure TTestRdxIntroEdits.TargetAtNameSkipsTakenName;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(TakenNameExpected, CRLF),
    RunC1h(JoinLines(TakenNameSource, CRLF), 8, 21, Target), 'Text danach');
  Assert.AreEqual('MagicNr02', Target.Name, 'Name');
  CheckSelection(TakenNameExpected, Target, 8, 9, 1);
end;

// Fall 1: beide 42 der Zeile werden ersetzt, die 42 im Kommentar darueber
// bleibt; die Deklaration kommt mit derselben Einrueckung direkt ueber die
// Anweisung. CR LF mit dem Caret auf der ersten 42; nur LF (eingefuegte
// Zeilen bekommen LF, kein CR entsteht) mit dem Caret direkt HINTER der
// zweiten 42 (zaehlt laut Vertrag auch).
procedure TTestRdxIntroEdits.C1hFall1CrLfAndLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(ScaleExpected, CRLF),
    RunC1h(JoinLines(ScaleSource, CRLF), 4, 21, Target), 'CR LF: Text danach');
  CheckSelection(ScaleExpected, Target, 4, 5, 2);
  Assert.AreEqual<Integer>(9, Target.Plan.NameCol, 'NameCol');
  Assert.AreEqual<Integer>(21, Target.Plan.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(33, Target.Plan.NewCols[1],
    'NewCols[1]: um 7 Zeichen (9 - 2) verschoben');
  Assert.AreEqual(JoinLines(ScaleExpected, LF),
    RunC1h(JoinLines(ScaleSource, LF), 4, 28, Target), 'LF: Text danach');
  CheckSelection(ScaleExpected, Target, 4, 5, 2);
end;

// Fall 2 (CR LF): Literal in der if-Zeile - die Deklaration kommt vor das
// if; die 1000 im Kommentar darueber bleibt, der Zweig darunter bleibt
// unveraendert.
procedure TTestRdxIntroEdits.C1hFall2IfLineCrLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(ClampFall2Expected, CRLF),
    RunC1h(JoinLines(ClampSource, CRLF), 5, 15, Target), 'Text danach');
  CheckSelection(ClampFall2Expected, Target, 5, 6, 1);
end;

// Fall 3 (CR LF): 999 im then-Zweig ohne begin, zwei Kommentarzeilen
// zwischen if-Zeile und Anweisung. 'begin' direkt unter die if-Zeile,
// 'end;' unter die Anweisung, beide mit der Einrueckung der if-Zeile; die
// Kommentare landen im Block; DeclRow eine Zeile tiefer (README M9).
procedure TTestRdxIntroEdits.C1hFall3WrapCrLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(ClampFall3Expected, CRLF),
    RunC1h(JoinLines(ClampSource, CRLF), 8, 16, Target), 'Text danach');
  Assert.IsTrue(Target.Plan.Wrap, 'Plan.Wrap');
  Assert.AreEqual<Integer>(8, Target.SourceRow, 'SourceRow');
  Assert.AreEqual<Integer>(5, Target.PrevRow,
    'PrevRow: die if-Zeile, ueber die Kommentare hinweg');
  CheckSelection(ClampFall3Expected, Target, 9, 10, 1);
end;

// Zweig hinter else, Tab-Einrueckung, nur LF: 'begin'/'end;' bekommen das
// Tab der else-Zeile, die Deklaration die zwei Tabs der Anweisung. 'begin'
// und Deklaration fallen auf denselben Offset - 'begin' zuerst. Nur die 60
// wird ersetzt, nicht die 2.
procedure TTestRdxIntroEdits.C1hElseWrapTabsLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(ElseBranchExpected, LF),
    RunC1h(JoinLines(ElseBranchSource, LF), 6, 13, Target), 'Text danach');
  CheckSelection(ElseBranchExpected, Target, 7, 8, 1);
  Assert.AreEqual<Integer>(9, Target.Plan.NameCol, 'NameCol: Tab = 1 Spalte');
end;

// Fall 4 (CR LF): Bruchzahl 0.5 als EIN Literal (Caret auf der 5).
procedure TTestRdxIntroEdits.C1hFall4FractionCrLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(AreaExpected, CRLF),
    RunC1h(JoinLines(AreaSource, CRLF), 4, 32, Target), 'Text danach');
  CheckSelection(AreaExpected, Target, 4, 5, 1);
end;

// Fall 5 (CR LF): Tab-Einrueckung und Hex-Literal $FF00 (Caret auf dem $):
// die Deklaration bekommt das Tab, ein Tab ist eine Zeichenspalte
// (README M8).
procedure TTestRdxIntroEdits.C1hFall5TabHexCrLf;
var
  Target : TRdxIntroTarget;
begin
  Assert.AreEqual(JoinLines(MaskExpected, CRLF),
    RunC1h(JoinLines(MaskSource, CRLF), 4, 22, Target), 'Text danach');
  CheckSelection(MaskExpected, Target, 4, 5, 1);
  Assert.AreEqual<Integer>(8, Target.Plan.NameCol, 'NameCol: Tab = 1 Spalte');
  Assert.AreEqual<Integer>(22, Target.Plan.NewCols[0], 'NewCols[0]');
end;

// Fall 6 (CR LF): Umlaute und Euro-Zeichen VOR dem Literal. Caret in
// Zeichenspalte 43, davor 42 Zeichen = 46 Bytes (README M10). Die
// Ersetzungen des Writers stehen aufsteigend in BYTES: Deklaration am
// Zeilenanfang (Byte 51), Literal bei 51 + 46 = 97.
procedure TTestRdxIntroEdits.C1hFall6UmlautCrLfByteOffsets;
var
  Src, Exp : TArray<string>;
  B        : TBytes;
  Target   : TRdxIntroTarget;
  Edits    : TRdxIntroByteEdits;
begin
  Src := [
    'function Greeting(Count: Integer): string;',
    'begin',
    '  Result := ''Gr'#$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * 42);',
    'end;',
    ''];
  Exp := [
    'function Greeting(Count: Integer): string;',
    'begin',
    '  const MagicNr01 = 42;',
    '  Result := ''Gr'#$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * MagicNr01);',
    'end;',
    ''];
  B := Utf8BytesOf(JoinLines(Src, CRLF));
  Edits := EditsAt(B, 3, 43, Target);
  Assert.AreEqual<Integer>(2, Length(Edits), 'Zahl der Ersetzungen');
  CheckEdit(Edits[0], 51, 0, '  const MagicNr01 = 42;'#13#10,
    'Deklaration mit dem Zeilenende vom Puffer (CR LF)');
  CheckEdit(Edits[1], 97, 2, 'MagicNr01',
    'Literal: Offset in Bytes, nicht in Zeichen');
  Assert.AreEqual(JoinLines(Exp, CRLF), Utf8TextOf(ApplyIntroEdits(B, Edits)),
    'Text danach');
  CheckSelection(Exp, Target, 3, 4, 1);
end;

// Fall 6 in der echten Demo-Datei (HEAD): UTF-8 mit BOM, nur LF. Die drei
// BOM-Bytes bleiben unveraendert, die Ersetzungen in Zeile 23 sitzen trotz
// BOM und Mehrbyte-Zeichen richtig. DeclRow 23, UseRow 24 (README Lauf 1:
// Punkte (23,6) und (24,42) als 0-basierte Zeichenindizes).
procedure TTestRdxIntroEdits.C1hFall6BomDemoFile;
var
  Exp    : TArray<string>;
  R      : TBytes;
  Target : TRdxIntroTarget;
begin
  Exp := UmlautDemoExpected;
  R := RunC1hBytes(Utf8BytesOf(#$FEFF + JoinLines(UmlautDemoSource, LF)), 23,
    43, Target);
  Assert.IsTrue(Length(R) > 3, 'Ergebnis zu kurz');
  Assert.AreEqual<Integer>($EF, R[0], 'BOM-Byte 1');
  Assert.AreEqual<Integer>($BB, R[1], 'BOM-Byte 2');
  Assert.AreEqual<Integer>($BF, R[2], 'BOM-Byte 3');
  Assert.AreEqual(JoinLines(Exp, LF), TEncoding.UTF8.GetString(R, 3,
    Length(R) - 3), 'Text hinter dem BOM');
  CheckSelection(Exp, Target, 23, 24, 1);
end;

// Zwei gleiche Literale mit Mehrbyte-Zeichen DAZWISCHEN (CR LF): jedes
// Literal bekommt den Byte-Offset seiner eigenen Stelle (Zeilenanfang +
// UTF-8-Laenge des Zeilenteils davor) - nicht den des ersten plus den
// Abstand in Zeichen (README M10, Lauf 3: Zeichen als Bytes gelesen
// zerstoert den Code). Zeile 3 beginnt bei 27 + 2 + 5 + 2 = 36.
procedure TTestRdxIntroEdits.C1hMultibyteBetweenLiterals;
var
  Src, Exp : TArray<string>;
  B        : TBytes;
  Target   : TRdxIntroTarget;
  Edits    : TRdxIntroByteEdits;
begin
  Src := [
    'procedure R(var S: string);',
    'begin',
    '  S := IntToStr(42) + '''#$00FC#$20AC''' + IntToStr(42);',
    'end;',
    ''];
  Exp := [
    'procedure R(var S: string);',
    'begin',
    '  const MagicNr01 = 42;',
    '  S := IntToStr(MagicNr01) + '''#$00FC#$20AC''' + IntToStr(MagicNr01);',
    'end;',
    ''];
  B := Utf8BytesOf(JoinLines(Src, CRLF));
  Edits := EditsAt(B, 3, 17, Target);
  Assert.AreEqual<Integer>(3, Length(Edits), 'Zahl der Ersetzungen');
  CheckEdit(Edits[0], 36, 0, '  const MagicNr01 = 42;'#13#10, 'Deklaration');
  // erste 42 in Spalte 17: 16 ASCII-Zeichen davor = 16 Bytes
  CheckEdit(Edits[1], 52, 2, 'MagicNr01', 'erste 42');
  // zweite 42 in Spalte 39: 38 Zeichen davor, ue 2 und Euro 3 Bytes = 41
  CheckEdit(Edits[2], 77, 2, 'MagicNr01', 'zweite 42 (74 = Zeichen gezaehlt)');
  Assert.AreEqual(JoinLines(Exp, CRLF), Utf8TextOf(ApplyIntroEdits(B, Edits)),
    'Text danach');
  CheckSelection(Exp, Target, 3, 4, 2);
  Assert.AreEqual<Integer>(17, Target.Plan.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(46, Target.Plan.NewCols[1],
    'NewCols[1]: 39 + 7 Zeichen (9 - 2)');
end;

// Nur die gleichen Literale im CODE werden ersetzt: die 42 in Strings (auch
// in '(* *)' im String), in '{ }' und hinter '//' bleiben. Vor dem Literal
// stehen Umlaute, Euro-Zeichen und ein Surrogatpaar (2 Spalten, 4 Bytes).
procedure TTestRdxIntroEdits.C1hStringAndCommentStay;
var
  Src, Exp : TArray<string>;
  Target   : TRdxIntroTarget;
begin
  Src := [
    'procedure Q(var S: string);',
    'begin',
    '  S := ''Gr'#$00F6#$00DF'e 42 '#$20AC#$D83D#$DE00''' + IntToStr(42) + '
      + '''(* 42 *)''; { 42 } // 42',
    'end;',
    ''];
  Exp := [
    'procedure Q(var S: string);',
    'begin',
    '  const MagicNr01 = 42;',
    '  S := ''Gr'#$00F6#$00DF'e 42 '#$20AC#$D83D#$DE00''' + IntToStr(MagicNr01) + '
      + '''(* 42 *)''; { 42 } // 42',
    'end;',
    ''];
  Assert.AreEqual(JoinLines(Exp, CRLF), RunC1h(JoinLines(Src, CRLF), 3, 35,
    Target), 'Text danach');
  CheckSelection(Exp, Target, 3, 4, 1);
  Assert.AreEqual<Integer>(34, Target.Plan.NewCols[0],
    'NewCols[0]: Surrogatpaar = 2 Spalten');
end;

// Ein Bezeichner mit Nicht-ASCII-Buchstaben (Ma + ss + 2, in Delphi
// erlaubt) enthaelt kein Zahl-Literal: nur die eigenstaendige 2 wird
// ersetzt, die 2 im Bezeichner bleibt (Vertrag: nur Zahl-Literale im Code;
// uRdxIntroPlan.NumberStartsAt: "Davor kein Bezeichner-Zeichen"). Steht der
// Caret auf der Ziffer im Bezeichner, gibt es nichts zu tun. Zeile 1 hat
// 35 Zeichen = 36 Bytes (ss 2 Bytes), Zeile 3 beginnt also bei
// 36 + 2 + 5 + 2 = 45; vor der 2 in Spalte 20 stehen 19 Zeichen = 20 Bytes.
// Befund 2026-10-11: rot, solange IsIdentChar in uRdxIntroPlan nur ASCII kennt
// (die Ziffer nach dem ss gilt dort als Literal).
procedure TTestRdxIntroEdits.C1hUnicodeIdentifierDigitStays;
var
  Src, Exp : TArray<string>;
  B        : TBytes;
  Target   : TRdxIntroTarget;
  Edits    : TRdxIntroByteEdits;
begin
  Src := [
    'function F(Ma'#$00DF'2: Integer): Integer;',
    'begin',
    '  Result := Ma'#$00DF'2 * 2;',
    'end;',
    ''];
  Exp := [
    'function F(Ma'#$00DF'2: Integer): Integer;',
    'begin',
    '  const MagicNr01 = 2;',
    '  Result := Ma'#$00DF'2 * MagicNr01;',
    'end;',
    ''];
  B := Utf8BytesOf(JoinLines(Src, CRLF));
  Edits := EditsAt(B, 3, 20, Target);
  Assert.AreEqual(JoinLines(Exp, CRLF), Utf8TextOf(ApplyIntroEdits(B, Edits)),
    'Text danach: die 2 im Bezeichner bleibt');
  Assert.AreEqual<Integer>(2, Length(Edits), 'Zahl der Ersetzungen');
  CheckEdit(Edits[0], 45, 0, '  const MagicNr01 = 2;'#13#10, 'Deklaration');
  CheckEdit(Edits[1], 65, 1, 'MagicNr01', 'Literal');
  CheckSelection(Exp, Target, 3, 4, 1);
  Assert.AreEqual<Integer>(20, Target.Plan.NewCols[0], 'NewCols[0]');
  Target := TargetAt(TextOf(B), 3, 16, NAME_BASE);
  Assert.IsFalse(Target.Plan.Ok, 'Caret auf der Ziffer im Bezeichner');
end;

// ApplyIntroEdits: leere Liste gibt dieselben Bytes; gleiche Offsets der
// Reihe nach wie in der Liste; Loeschen und Einfuegen in EINER Ersetzung;
// Len zaehlt Bytes, Text kommt als UTF-8 hinein; Einfuegen genau am
// Pufferende ist erlaubt.
procedure TTestRdxIntroEdits.ApplyByteEditsInListOrder;
var
  Src   : TBytes;
  Edits : TRdxIntroByteEdits;
begin
  Src := Utf8BytesOf('a'#$20AC'b');
  Assert.AreEqual<Integer>(5, Length(ApplyIntroEdits(Src, nil)),
    'leere Liste: Laenge');
  Assert.AreEqual('a'#$20AC'b', Utf8TextOf(ApplyIntroEdits(Src, nil)),
    'leere Liste: Inhalt');
  Src := Utf8BytesOf('abcdef');
  Edits := [MakeEdit(2, 0, 'X'), MakeEdit(2, 0, 'Y')];
  Assert.AreEqual('abXYcdef', Utf8TextOf(ApplyIntroEdits(Src, Edits)),
    'gleicher Offset: Listenreihenfolge');
  Edits := [MakeEdit(0, 0, '>'), MakeEdit(1, 2, 'Z'), MakeEdit(5, 1, '')];
  Assert.AreEqual('>aZde', Utf8TextOf(ApplyIntroEdits(Src, Edits)),
    'aufsteigend, Loeschen und Einfuegen');
  Src := Utf8BytesOf('x'#$20AC'y');
  Edits := [MakeEdit(1, 3, #$00FC#$00DF)];
  Assert.AreEqual('x'#$00FC#$00DF'y', Utf8TextOf(ApplyIntroEdits(Src, Edits)),
    'Euro (3 Bytes) durch zwei Umlaute ersetzt');
  Assert.AreEqual<Integer>(6, Length(ApplyIntroEdits(Src, Edits)),
    'Laenge in Bytes: 1 + 2 * 2 + 1');
  Src := Utf8BytesOf('ab');
  Edits := [MakeEdit(2, 0, '!')];
  Assert.AreEqual('ab!', Utf8TextOf(ApplyIntroEdits(Src, Edits)),
    'Einfuegen am Pufferende');
end;

// ApplyIntroEdits: EArgumentException, wenn der Writer zurueck muesste
// (absteigende Offsets, eine Ersetzung, die im verworfenen Bereich der
// vorigen beginnt, eine negative Laenge) und bei einer Ersetzung, die aus
// dem Puffer ragt. Gegenprobe: bis genau ans Pufferende ist erlaubt.
procedure TTestRdxIntroEdits.ApplyByteEditsRaises;
var
  Src   : TBytes;
  Edits : TRdxIntroByteEdits;
begin
  Src := Utf8BytesOf('abcdef');
  Edits := [MakeEdit(3, 0, 'X'), MakeEdit(1, 0, 'Y')];
  Assert.IsTrue(ApplyRaises(Src, Edits), 'absteigende Offsets');
  Edits := [MakeEdit(1, 3, 'X'), MakeEdit(2, 0, 'Y')];
  Assert.IsTrue(ApplyRaises(Src, Edits),
    'beginnt im verworfenen Bereich der vorigen (Writer schon bei 4)');
  Edits := [MakeEdit(2, -1, 'X')];
  Assert.IsTrue(ApplyRaises(Src, Edits), 'negative Laenge');
  Edits := [MakeEdit(4, 3, '')];
  Assert.IsTrue(ApplyRaises(Src, Edits), 'ragt ueber das Ende (4 + 3 > 6)');
  Edits := [MakeEdit(7, 0, 'X')];
  Assert.IsTrue(ApplyRaises(Src, Edits), 'beginnt hinter dem Ende');
  Edits := [MakeEdit(4, 2, '')];
  Assert.IsFalse(ApplyRaises(Src, Edits), 'bis genau ans Ende ist erlaubt');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIntroEdits);
end.
