unit uTestVnpTemplate;

// VarNameProject - Variante D1 (Live Template) ohne IDE: der Template-Code
// (uVnpPlan.TemplateCode), LoneLfCount, die Template-Datei
// (uVnpEdits.TemplateXml), das eigene Template in der Liste der IDE
// (IsOwnTemplate, TPL_*), Loeschen und Zurueckschreiben der Anweisung
// (StatementDeleteEdit, StatementRestoreEdit).
//
// Vertrag: die Interface-Kommentare von uVnpPlan und uVnpEdits, README
// (Varianten, Grenzen, Messpunkte), die Demo-Dateien im Stand HEAD und das
// mitgelieferte Template ObjRepos\en\Code_Templates\Delphi\ifnil.xml. Alle
// Erwartungen sind von Hand abgeleitet.
//
// Die Faelle stammen aus demo/VarNameDemo.pas (Fall 1, 3, 5) und
// demo/VarNameDemoUmlaut.pas (Fall 6) - Auszuege, die Zeilen wortgleich
// (ohne die BOM der Umlaut-Demo). Jeder Fall ist ein Puffer mit festem
// Zeilenende; TextOf und TargetAt liefern daraus Plan und Namen wie im
// IDE-Teil, ApplyByteEdits stellt den IOTAEditWriter nach.
//
// Model_D1_LikeC1h prueft gegen ein MODELL der Template-Expansion der IDE
// (Annahme D-M3, README "Messpunkte" - in der IDE noch zu bestaetigen,
// Testplan Schritt 12), NICHT gegen die IDE selbst.
//
// Quelltext nur ASCII: #$00FC ue, #$00DF ss, #$00F6 oe, #$20AC Euro.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVnpTemplate = class
  public
    // TemplateCode: Demo-Faelle, die ganze Zeile, Ablehnungen
    [Test] procedure TemplateCode_Fall1_CrLf;
    [Test] procedure TemplateCode_Fall5_TabHexLf;
    [Test] procedure TemplateCode_Fall6_Umlaut;
    [Test] procedure TemplateCode_WholeLine_CodeLiteralsOnly;
    [Test] procedure TemplateCode_Branch_Refused;
    [Test] procedure TemplateCode_Pipe_Refused;
    [Test] procedure TemplateCode_CdataEnd_Refused;
    // Template-Datei und eigenes Template
    [Test] procedure TemplateXml_Structure;
    [Test] procedure TemplateXml_CodeAndNameVerbatim;
    [Test] procedure IsOwnTemplate_Accepts;
    [Test] procedure IsOwnTemplate_Rejects;
    [Test] procedure TplConstants_Values;
    // Anweisung loeschen und zurueckschreiben
    [Test] procedure Delete_Fall1_KeepsSpacesCrLf;
    [Test] procedure Delete_Fall5_KeepsTabLf;
    [Test] procedure Delete_Fall6_Utf8;
    [Test] procedure Delete_RestOfLine_Gone;
    [Test] procedure Delete_LfLineInCrLfFile;
    [Test] procedure Restore_RoundTrip_Bytes;
    // Zeilenenden
    [Test] procedure LoneLfCount_Cases;
    // MODELL der Template-Expansion (D-M3)
    [Test] procedure Model_D1_LikeC1h;
  end;

implementation

uses
  System.SysUtils, uVnpPlan, uVnpEdits;

const
  // Fall 6: 'Gruesse Euro' - 7 Zeichen, 11 UTF-8-Bytes (README M10).
  GREET = 'Gr' + #$00FC + #$00DF + 'e ' + #$20AC;
  // Das String-Literal der Anweisung von Fall 6 samt Quotes, wie in der
  // Demo MIT dem Leerzeichen vor dem schliessenden Quote: 10 Zeichen, 14
  // Bytes.
  QGREET = '''' + GREET + ' ''';
  // Fall 6, Kommentarzeile der Demo (Nicht-ASCII ueber der Anweisung).
  FALL6_NOTE = '// ob TOTACharPos.CharIndex Bytes oder Zeichen zaehlt: '''
    + GREET + ''' sind 7';
  // Fall 6, die Anweisung der Demo: 46 Zeichen, 50 Bytes, die 42 in Spalte
  // 43 (README Lauf 1: CharIndex 42, 0-basiert; Lauf 3: Byte 42 = Zeichen
  // 39).
  FALL6_LINE = '  Result := ' + QGREET + ' + IntToStr(Count * 42);';
  // Eine Anweisung mit Kommentar dahinter (LineCase, die 42 in Spalte 21).
  LINE_NOTE = '  Result := Value * 42; // Hinweis';

  // Erwarteter Template-Code (von Hand): Deklaration und Anweisung OHNE
  // Einrueckung, jede Namensstelle |vnpname|, |end| am Ende, dazwischen
  // das Zeilenende des Puffers.
  CODE_FALL1 = 'var |vnpname| := 42;' + #13#10
    + 'Result := Value * |vnpname| + |vnpname|;|end|';
  CODE_FALL5 = 'var |vnpname| := $FF00;' + #10
    + 'Result := Value and |vnpname|;|end|';
  CODE_FALL6 = 'var |vnpname| := 42;' + #13#10
    + 'Result := ' + QGREET + ' + IntToStr(Count * |vnpname|);|end|';

type
  // Ein Fall: Pufferbytes, Text beim Start und Ziel am Caret - so wie der
  // IDE-Teil sie bildet.
  TTplCase = record
    Bytes  : TBytes;
    Text   : TVnpText;
    Target : TVnpTarget;
  end;

// Die Zeilen ab AFrom, jede mit AEol abgeschlossen - rekursiv statt mit
// einer Schleife (SCA110; TStringBuilder ist unter FPC 3.2.2 nur
// AnsiString).
function JoinedFrom(const ALines: array of string; AFrom: Integer;
  const AEol: string): string;
begin
  Result := '';
  if AFrom <= High(ALines) then
    Result := ALines[AFrom] + AEol + JoinedFrom(ALines, AFrom + 1, AEol);
end;

// Die Zeilen, jede mit AEol abgeschlossen (die Datei endet mit einem
// Zeilenende).
function Joined(const ALines: array of string; const AEol: string): string;
begin
  Result := JoinedFrom(ALines, 0, AEol);
end;

// Der Fall zum ganzen Puffertext: Puffer als UTF-8, Text, Ziel fuer den
// Caret in Zeile ARow, Zeichenspalte ACol (Namensbasis MagicNr wie im
// IDE-Teil).
function CaseOf(const ABuffer: string; ARow, ACol: Integer): TTplCase;
begin
  Result := Default(TTplCase);
  Result.Bytes := TEncoding.UTF8.GetBytes(ABuffer);
  Result.Text := TextOf(Result.Bytes);
  Result.Target := TargetAt(Result.Text, ARow, ACol, 'MagicNr');
end;

// Der Fall zu den Zeilen, alle mit demselben Zeilenende.
function MakeCase(const ALines: array of string; const AEol: string;
  ARow, ACol: Integer): TTplCase;
begin
  Result := CaseOf(Joined(ALines, AEol), ARow, ACol);
end;

// Fall 1 (demo/VarNameDemo.pas), CR LF: Caret auf der ersten 42.
function Fall1: TTplCase;
begin
  Result := MakeCase(['function Scale(Value: Integer): Integer;', 'begin',
    '  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.',
    '  Result := Value * 42 + 42;', 'end;'], #13#10, 4, 21);
end;

// Fall 3 (demo/VarNameDemo.pas), CR LF: Caret auf 999 - die einzige
// Anweisung hinter then.
function Fall3: TTplCase;
begin
  Result := MakeCase(['function Clamp(Value: Integer): Integer;', 'begin',
    '  Result := Value;',
    '  // Fall 2: Caret auf 1000 in der if-Zeile -> angeboten.',
    '  if Result > 1000 then',
    '    // Fall 3: Caret auf 999 -> ABGELEHNT (die Zeile darueber endet mit',
    '    // then; die Deklaration wuerde zum Zweig).',
    '    Result := 999;', 'end;'], #13#10, 8, 15);
end;

// Fall 5 (demo/VarNameDemo.pas), LF: Tab-Einrueckung, Caret auf $FF00.
function Fall5: TTplCase;
begin
  Result := MakeCase(['function Mask(Value: Cardinal): Cardinal;', 'begin',
    #9'// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.',
    #9'Result := Value and $FF00;', 'end;'], #10, 4, 22);
end;

// Fall 6 (demo/VarNameDemoUmlaut.pas), CR LF: Umlaute und Euro-Zeichen vor
// der 42 (Spalte 43); darueber die Kommentarzeile der Demo mit
// Nicht-ASCII - die Zeilenanfaenge zaehlen dann Bytes, nicht Zeichen.
function Fall6: TTplCase;
begin
  Result := MakeCase([FALL6_NOTE,
    'function Greeting(Count: Integer): string;', 'begin', FALL6_LINE,
    'end;'], #13#10, 4, 43);
end;

// Eine Anweisung als einzige Zeile in einem Block aus begin und end (CR
// LF), Caret in Spalte ACol.
function LineCase(const ALine: string; ACol: Integer): TTplCase;
begin
  Result := MakeCase(['begin', ALine, 'end;'], #13#10, 2, ACol);
end;

// Gemischte Zeilenenden: CR LF-Datei, nur die Anweisung (Zeile 2, Caret
// auf der 42) endet mit LF allein.
function MixedCase: TTplCase;
begin
  Result := CaseOf('begin' + #13#10 + '  Result := Value * 42;' + #10
    + 'end;' + #13#10, 2, 21);
end;

// TemplateCode so, wie der IDE-Teil ihn nach dieser Annahme ruft: Plan und
// Name des Ziels, Punkt TPL_POINT, Zeilenende des Puffers.
function CodeOf(const ACase: TTplCase; out AReason: string): string;
begin
  Result := TemplateCode(ACase.Target.Plan, ACase.Target.Name, TPL_POINT,
    ACase.Text.Eol, AReason);
end;

// TemplateCode lehnt den Fall ab: der Plan ist in Ordnung, aber es gibt
// keinen Code und einen Grund mit AKeyword.
procedure AssertRefused(const ACase: TTplCase; const AKeyword, AMsg: string);
var
  Code, Reason : string;
begin
  Assert.IsTrue(ACase.Target.Plan.Ok, AMsg + ': Vorbedingung Plan - '
    + ACase.Target.Plan.Reason);
  Code := CodeOf(ACase, Reason);
  Assert.AreEqual('', Code, AMsg + ': kein Template-Code');
  Assert.IsTrue(Pos(AKeyword, Reason) > 0, AMsg + ': Grund nennt '
    + AKeyword + ' - war "' + Reason + '"');
end;

// Genau diese eine Ersetzung.
function OneEdit(const AEdit: TVnpByteEdit): TVnpByteEdits;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := AEdit;
end;

// Der Puffer nach StatementDeleteEdit.
function DeletedBytes(const ACase: TTplCase): TBytes;
begin
  Result := ApplyByteEdits(ACase.Bytes,
    OneEdit(StatementDeleteEdit(ACase.Text, ACase.Target)));
end;

// Der Puffertext nach StatementDeleteEdit.
function DeletedText(const ACase: TTplCase): string;
begin
  Result := TEncoding.UTF8.GetString(DeletedBytes(ACase));
end;

// Die Bytes als Zeichen 0..255: ein Vergleich darauf ist bytegenau, ASCII
// bleibt lesbar.
function RawOf(const ABytes: TBytes): string;
var
  i : Integer;
begin
  Result := '';
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

// Wie oft ASub in AText steht (ohne Ueberlappung).
function CountOf(const ASub, AText: string): Integer;
var
  P : Integer;
begin
  Result := 0;
  P := Pos(ASub, AText);
  while P > 0 do
  begin
    Inc(Result);
    P := Pos(ASub, AText, P + Length(ASub));
  end;
end;

// Der Text zwischen dem ersten '<![CDATA[' und dem ersten ']]>' danach
// ('' ohne).
function CdataOf(const AXml: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('<![CDATA[', AXml);
  if P = 0 then
    Exit;
  Q := Pos(']]>', AXml, P);
  if Q > 0 then
    Result := Copy(AXml, P + 9, Q - P - 9);
end;

// Der Start-Tag ab dem ersten AOpen bis einschliesslich '>' ('' ohne).
function TagOf(const AXml, AOpen: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AOpen, AXml);
  if P = 0 then
    Exit;
  Q := Pos('>', AXml, P);
  if Q > 0 then
    Result := Copy(AXml, P, Q - P + 1);
end;

// Jedes Stueck aus AParts steht in AText, jedes hinter dem vorigen.
procedure AssertInOrder(const AText: string; const AParts: array of string;
  const AMsg: string);
var
  i, At, P : Integer;
begin
  At := 1;
  for i := 0 to High(AParts) do
  begin
    P := Pos(AParts[i], AText, At);
    Assert.IsTrue(P > 0, AMsg + ': "' + AParts[i]
      + '" fehlt oder steht vor dem vorigen Stueck');
    At := P + Length(AParts[i]);
  end;
end;

// Jedes AOld in S durch ANew, von links; Eingesetztes wird nicht erneut
// durchsucht. Eigene Routine: StringReplace ist unter FPC 3.2.2 nur
// AnsiString; rekursiv statt mit einer Schleife (SCA110).
function ReplaceAll(const S, AOld, ANew: string): string;
var
  P : Integer;
begin
  P := Pos(AOld, S);
  if P = 0 then
    Exit(S);
  Result := Copy(S, 1, P - 1) + ANew
    + ReplaceAll(Copy(S, P + Length(AOld), MaxInt), AOld, ANew);
end;

// MODELL der Template-Expansion der IDE - Annahme D-M3 (README
// "Messpunkte"), in der IDE noch zu bestaetigen: jede Stelle |TPL_POINT|
// wird zum Punkttext, |end| faellt weg (nur die Caret-Marke), jede Zeile
// nach der ersten bekommt die Einrueckung der Einfuegestelle vorangestellt,
// jeder Zeilenumbruch (CR LF wie LF) wird zum Zeilenende der Datei. Auch
// das Zeilenende ist Annahme: ein XML-Leser macht aus CR LF im CDATA ein LF
// (XML 1.0, 2.11); ob die IDE beim Einfuegen mischt, zeigt LoneLfCount.
function ExpandModel(const ACode, APointText, AIndent, AEol: string): string;
begin
  Result := ReplaceAll(ACode, '|' + TPL_POINT + '|', APointText);
  Result := ReplaceAll(Result, '|end|', '');
  Result := ReplaceAll(Result, #13#10, #10);
  Result := ReplaceAll(Result, #10, AEol + AIndent);
end;

// D1 nach dem MODELL: die Anweisung loeschen (StatementDeleteEdit +
// ApplyByteEdits) und den expandierten Template-Code an der Einfuegestelle
// hinter der stehengebliebenen Einrueckung einsetzen - der Stelle, an die
// StatementRestoreEdit schreibt; der Puffertext danach.
function ModelText(const ACase: TTplCase; const AIndent,
  AEol: string): string;
var
  Code, Reason : string;
  Ins          : TVnpByteEdit;
begin
  Code := CodeOf(ACase, Reason);
  Assert.AreEqual('', Reason, 'TemplateCode lehnt den Fall ab');
  Ins := StatementRestoreEdit(ACase.Text, ACase.Target);
  Ins.Len := 0;
  Ins.Text := ExpandModel(Code, ACase.Target.Name, AIndent, AEol);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(DeletedBytes(ACase),
    OneEdit(Ins)));
end;

// Loeschen, dann Zurueckschreiben auf dem geloeschten Puffer: dieselben
// Bytes wie vorher.
procedure AssertRoundTrip(const ACase: TTplCase; const AMsg: string);
var
  Back : TBytes;
begin
  Back := ApplyByteEdits(DeletedBytes(ACase),
    OneEdit(StatementRestoreEdit(ACase.Text, ACase.Target)));
  Assert.AreEqual(RawOf(ACase.Bytes), RawOf(Back), AMsg
    + ': Bytes nach Loeschen und Zurueckschreiben');
end;

{ TTestVnpTemplate }

// TemplateCode, Fall 1 (CR LF): Deklaration und Anweisung OHNE
// Einrueckung, beide 42 als |vnpname|, |end| am Ende, CR LF dazwischen.
// Jede Namensstelle wird zur Marke |APoint|, gleich wie lang Name und
// Punkt sind: MagicNr01 und |vnpname| sind beide 9 Zeichen lang und
// verdecken Verschiebungen - darum auch ein kurzer Punkt (|p|) und ein
// kurzer Name (N01, Code wie mit MagicNr01).
procedure TTestVnpTemplate.TemplateCode_Fall1_CrLf;
var
  C      : TTplCase;
  T      : TVnpTarget;
  Reason : string;
begin
  C := Fall1;
  Assert.IsTrue(C.Target.Plan.Ok, 'Vorbedingung Plan: '
    + C.Target.Plan.Reason);
  Assert.AreEqual(CODE_FALL1, CodeOf(C, Reason), 'Fall 1');
  Assert.AreEqual('', Reason, 'Fall 1: kein Ablehnungsgrund');
  Assert.AreEqual('var |p| := 42;' + #13#10
    + 'Result := Value * |p| + |p|;|end|', TemplateCode(C.Target.Plan,
    C.Target.Name, 'p', C.Text.Eol, Reason), 'Fall 1, kurzer Punkt p');
  T := TargetAt(C.Text, 4, 21, 'N');
  Assert.AreEqual('N01', T.Name, 'Vorbedingung: Name N01');
  Assert.IsTrue(T.Plan.Ok, 'Vorbedingung Plan mit N01: ' + T.Plan.Reason);
  Assert.AreEqual(CODE_FALL1, TemplateCode(T.Plan, T.Name, TPL_POINT,
    C.Text.Eol, Reason), 'Fall 1, kurzer Name N01');
end;

// TemplateCode, Fall 5 (LF): der Tab faellt weg (die IDE rueckt selbst
// ein), $FF00 als Literal, LF zwischen den Zeilen.
procedure TTestVnpTemplate.TemplateCode_Fall5_TabHexLf;
var
  C      : TTplCase;
  Reason : string;
begin
  C := Fall5;
  Assert.IsTrue(C.Target.Plan.Ok, 'Vorbedingung Plan: '
    + C.Target.Plan.Reason);
  Assert.AreEqual(CODE_FALL5, CodeOf(C, Reason), 'Fall 5');
  Assert.AreEqual('', Reason, 'Fall 5: kein Ablehnungsgrund');
end;

// TemplateCode, Fall 6: Umlaute und Euro-Zeichen VOR dem Literal - die
// Namensstelle sitzt in Zeichen richtig, der String davor bleibt heil.
procedure TTestVnpTemplate.TemplateCode_Fall6_Umlaut;
var
  C      : TTplCase;
  Reason : string;
begin
  C := Fall6;
  Assert.IsTrue(C.Target.Plan.Ok, 'Vorbedingung Plan: '
    + C.Target.Plan.Reason);
  Assert.AreEqual(CODE_FALL6, CodeOf(C, Reason), 'Fall 6');
  Assert.AreEqual('', Reason, 'Fall 6: kein Ablehnungsgrund');
end;

// TemplateCode nimmt die GANZE Zeile mit den Ersetzungen: ein Kommentar
// hinter der Anweisung kommt genau einmal mit (D1 loescht die ganze Zeile,
// Delete_RestOfLine_Gone). Marken nur an den Namensstellen: gleiche
// Literale in String und Kommentar bleiben (nur Code wird ersetzt), ein
// laengerer Bezeichner, der mit dem Namen beginnt, bleibt unberuehrt.
procedure TTestVnpTemplate.TemplateCode_WholeLine_CodeLiteralsOnly;
var
  C      : TTplCase;
  Reason : string;
begin
  Assert.AreEqual('var |vnpname| := 42;' + #13#10
    + 'Result := Value * |vnpname|; // Hinweis|end|',
    CodeOf(LineCase(LINE_NOTE, 21), Reason), 'Kommentar hinter der Anweisung');
  Assert.AreEqual('var |vnpname| := 42;' + #13#10
    + 'S := ''42'' + IntToStr(|vnpname|); // 42|end|',
    CodeOf(LineCase('  S := ''42'' + IntToStr(42); // 42', 24), Reason),
    '42 in String und Kommentar bleibt');
  C := LineCase('  Result := MagicNr01Max * 42;', 28);
  Assert.AreEqual('MagicNr01', C.Target.Name,
    'Vorbedingung: MagicNr01Max belegt MagicNr01 nicht');
  Assert.AreEqual('var |vnpname| := 42;' + #13#10
    + 'Result := MagicNr01Max * |vnpname|;|end|', CodeOf(C, Reason),
    'MagicNr01Max bleibt');
end;

// TemplateCode lehnt Fall 3 ab: 999 ist die einzige Anweisung hinter then,
// der Zweig braucht begin..end - das kann nur C1h (README Grenzen, M9).
// Ein abgelehnter Plan ergibt ebenfalls keinen Code, der Grund nennt den
// des Plans (Interface TemplateCode).
procedure TTestVnpTemplate.TemplateCode_Branch_Refused;
var
  C      : TTplCase;
  P      : TVnpPlan;
  Reason : string;
begin
  C := Fall3;
  Assert.IsTrue(C.Target.Plan.Wrap, 'Vorbedingung: Plan mit begin..end - '
    + C.Target.Plan.Reason);
  AssertRefused(C, 'begin..end', 'Fall 3');
  // Caret auf dem Y (Spalte 8): kein Literal, der Plan ist abgelehnt.
  P := PlanIntroduce('  X := Y;', 'begin', 8, 'N01');
  Assert.IsFalse(P.Ok, 'Vorbedingung: Plan abgelehnt');
  Assert.AreEqual('', TemplateCode(P, 'N01', TPL_POINT, #13#10, Reason),
    'abgelehnter Plan: kein Code');
  Assert.IsTrue(Pos('kein gueltiger Plan', Reason) > 0,
    'abgelehnter Plan, Grund: ' + Reason);
  Assert.IsTrue(Pos('kein Zahl-Literal', Reason) > 0,
    'abgelehnter Plan, Grund vom Plan: ' + Reason);
end;

// TemplateCode lehnt '|' ab (Trennzeichen des Templates, README Grenzen) -
// auch in einem Kommentar hinter der Anweisung und in einem String.
procedure TTestVnpTemplate.TemplateCode_Pipe_Refused;
begin
  AssertRefused(LineCase('  Result := Value * 42; // Spalte|Zeile', 21),
    '"|"', '| im Kommentar');
  AssertRefused(LineCase('  Result := ''a|b'' + IntToStr(42);', 30), '"|"',
    '| im String');
end;

// TemplateCode lehnt ']]>' ab (Ende des CDATA-Abschnitts, README Grenzen):
// im Code (geschachtelter Index vor '>'), im String und im Kommentar - der
// Kommentar kommt mit der Zeile ins Template.
procedure TTestVnpTemplate.TemplateCode_CdataEnd_Refused;
begin
  AssertRefused(LineCase('  Result := M[I[42]]>0;', 17), 'CDATA',
    ']]> im Code');
  AssertRefused(LineCase('  S := '']]>'' + IntToStr(42);', 25), 'CDATA',
    ']]> im String');
  AssertRefused(LineCase('  Result := Value * 42; // ]]> Ende', 21),
    'CDATA', ']]> im Kommentar');
end;

// TemplateXml wie ifnil.xml: XML-Deklaration ganz vorn; codetemplate mit
// xmlns und version; template vnpintro mit invoke="none" (expandiert nie
// per Tab oder Leertaste); genau EIN Punkt vnpname mit dem Namen als
// <text>; code mit language/context/delimiter; der Code unveraendert in
// genau einem CDATA-Abschnitt.
procedure TTestVnpTemplate.TemplateXml_Structure;
var
  Xml, Tag, T : string;
begin
  Xml := TemplateXml(CODE_FALL1, 'MagicNr01');
  Assert.AreEqual<Integer>(1, Pos('<?xml version="1.0" encoding="utf-8" ?>',
    Xml), 'XML-Deklaration ganz vorn');
  Tag := TagOf(Xml, '<codetemplate');
  Assert.IsTrue(Pos('xmlns="http://schemas.borland.com/Delphi/2005/'
    + 'codetemplates"', Tag) > 0, 'codetemplate mit xmlns: ' + Tag);
  Assert.IsTrue(Pos('version="1.0.0"', Tag) > 0,
    'codetemplate mit version: ' + Tag);
  AssertInOrder(Xml, ['<codetemplate',
    '<template name="vnpintro" invoke="none">', '<point name="vnpname">',
    '<text>MagicNr01</text>', '</point>',
    '<code language="Delphi" context="methodbody" delimiter="|"><![CDATA[',
    ']]>', '</code>', '</template>', '</codetemplate>'], 'Aufbau');
  Assert.AreEqual<Integer>(1, CountOf('<point ', Xml), 'genau ein Punkt');
  Assert.AreEqual<Integer>(1, CountOf('<![CDATA[', Xml),
    'genau ein CDATA-Anfang');
  Assert.AreEqual<Integer>(1, CountOf(']]>', Xml), 'genau ein CDATA-Ende');
  Assert.AreEqual(CODE_FALL1, CdataOf(Xml), 'Code unveraendert im CDATA');
  T := TrimRight(Xml);
  Assert.AreEqual('</codetemplate>', Copy(T, Length(T) - 14, 15),
    'nichts hinter </codetemplate>');
end;

// TemplateXml uebernimmt Code und Namen unveraendert in den String (Vertrag:
// "ACode steht unveraendert im CDATA-Abschnitt") - keine Entities, kein
// Escaping: Fall 6 mit Umlauten und Euro-Zeichen, ein Name mit Umlauten als
// <text>, Code mit < > & " (sonst stuende 'A &lt; B' im Editor). Ob die
// DATEI die Umlaute heil traegt (Kodierung, BOM - D-M4), misst die IDE.
procedure TTestVnpTemplate.TemplateXml_CodeAndNameVerbatim;
const
  NAME_UML = 'Gr' + #$00F6 + #$00DF + 'e01';
  CODE_MARKUP = 'var |vnpname| := 42;' + #13#10
    + 'B := (A < |vnpname|) and (C > 0) and (S = ''&"'');|end|';
var
  Xml : string;
begin
  Xml := TemplateXml(CODE_FALL6, NAME_UML);
  Assert.AreEqual(CODE_FALL6, CdataOf(Xml), 'Fall 6 im CDATA');
  Assert.AreEqual<Integer>(1, CountOf('<![CDATA[', Xml),
    'genau ein CDATA-Abschnitt');
  Assert.IsTrue(Pos('<text>' + NAME_UML + '</text>', Xml) > 0,
    'Name mit Umlauten als Vorgabetext');
  Assert.AreEqual(CODE_MARKUP, CdataOf(TemplateXml(CODE_MARKUP,
    'MagicNr01')), '< > & " unveraendert im CDATA');
end;

// IsOwnTemplate erkennt das eigene Template: Kuerzel TPL_NAME und Datei
// TPL_FILE, Gross/Klein egal, noch ohne Dateiname, Datei mit Verzeichnissen
// (README: %TEMP%\VarNameProject\tpl und Rueckfall B-b code_templates).
procedure TTestVnpTemplate.IsOwnTemplate_Accepts;
begin
  Assert.IsTrue(IsOwnTemplate('vnpintro', 'vnpintro.xml'), 'genau so');
  Assert.IsTrue(IsOwnTemplate('VnpIntro', 'VNPINTRO.XML'),
    'Gross/Klein egal');
  Assert.IsTrue(IsOwnTemplate('vnpintro', ''), 'noch ohne Dateiname');
  Assert.IsTrue(IsOwnTemplate('VNPINTRO', ''),
    'ohne Dateiname, Kuerzel gross');
  Assert.IsTrue(IsOwnTemplate('vnpintro', 'C:\Users\Nico\AppData\Local\Temp'
    + '\VarNameProject\tpl\vnpintro.xml'), 'voller Pfad unter %TEMP%');
  Assert.IsTrue(IsOwnTemplate('vnpintro', 'C:\Users\Nico\Documents'
    + '\Embarcadero\Studio\code_templates\VarNameProject\VnpIntro.Xml'),
    'voller Pfad Rueckfall B-b, Gross/Klein egal');
end;

// IsOwnTemplate lehnt fremde Eintraege ab: andere Datei (auch ein
// gleichnamiges Kuerzel in fremder Datei), nur aehnlicher Dateiname
// (Anhang, Vorsilbe, andere oder keine Endung), unser Name nur als
// Verzeichnis, anderes oder leeres Kuerzel - ein Fehlgriff liesse das
// Aufraeumen von D1 ein fremdes Template entfernen.
procedure TTestVnpTemplate.IsOwnTemplate_Rejects;
begin
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'other.xml'), 'andere Datei');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'C:\Program Files (x86)'
    + '\Embarcadero\Studio\23.0\ObjRepos\en\Code_Templates\Delphi'
    + '\ifnil.xml'), 'mitgelieferte Datei');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'C:\tpl\vnpintro.xml.bak'),
    'Dateiname mit Anhang');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'C:\tpl\xvnpintro.xml'),
    'Dateiname endet nur auf vnpintro.xml');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'C:\tpl\vnpintro.txt'),
    'andere Endung');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'vnpintro'), 'ohne Endung');
  Assert.IsFalse(IsOwnTemplate('vnpintro', 'C:\vnpintro.xml\ifnil.xml'),
    'unser Name nur als Verzeichnis');
  Assert.IsFalse(IsOwnTemplate('ifnil', 'vnpintro.xml'), 'anderes Kuerzel');
  Assert.IsFalse(IsOwnTemplate('ifnil', ''),
    'anderes Kuerzel ohne Dateiname');
  Assert.IsFalse(IsOwnTemplate('vnpintro2', 'vnpintro.xml'),
    'Kuerzel nur aehnlich');
  Assert.IsFalse(IsOwnTemplate('', ''), 'leeres Kuerzel');
end;

// TPL_*: Kuerzel vnpintro (README D1 und D-M7 - so steht es in Strg+J),
// Punkt vnpname, Datei vnpintro.xml.
procedure TTestVnpTemplate.TplConstants_Values;
begin
  Assert.AreEqual('vnpintro', TPL_NAME, 'Kuerzel');
  Assert.AreEqual('vnpname', TPL_POINT, 'Punktname');
  Assert.AreEqual('vnpintro.xml', TPL_FILE, 'Dateiname');
end;

// StatementDeleteEdit, Fall 1: von der Anweisungszeile bleiben genau die
// zwei Leerzeichen und CR LF stehen; die anderen Zeilen unveraendert.
procedure TTestVnpTemplate.Delete_Fall1_KeepsSpacesCrLf;
begin
  Assert.AreEqual(Joined(['function Scale(Value: Integer): Integer;',
    'begin',
    '  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.',
    '  ', 'end;'], #13#10), DeletedText(Fall1), 'Fall 1 nach dem Loeschen');
end;

// StatementDeleteEdit, Fall 5: es bleiben genau der Tab und das LF.
procedure TTestVnpTemplate.Delete_Fall5_KeepsTabLf;
begin
  Assert.AreEqual(Joined(['function Mask(Value: Cardinal): Cardinal;',
    'begin',
    #9'// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.',
    #9, 'end;'], #10), DeletedText(Fall5), 'Fall 5 nach dem Loeschen');
end;

// StatementDeleteEdit, Fall 6: die Zeile mit Umlauten und Euro-Zeichen
// (46 Zeichen, 50 Bytes) verschwindet bis auf die zwei Leerzeichen und
// CR LF - Laenge in Bytes, kein Rest, kein zerrissenes Zeichen; die
// Nicht-ASCII-Zeile darueber bleibt heil.
procedure TTestVnpTemplate.Delete_Fall6_Utf8;
begin
  Assert.AreEqual(Joined([FALL6_NOTE,
    'function Greeting(Count: Integer): string;', 'begin', '  ', 'end;'],
    #13#10), DeletedText(Fall6), 'Fall 6 nach dem Loeschen');
end;

// StatementDeleteEdit loescht alles zwischen Einrueckung und Zeilenende
// (Vertrag: "Einrueckung und Zeilenende bleiben stehen") - auch einen
// Kommentar und Leerraum hinter der Anweisung. Das Template bringt die
// ganze Zeile zurueck; ein Rest stuende danach doppelt da.
procedure TTestVnpTemplate.Delete_RestOfLine_Gone;
begin
  Assert.AreEqual(Joined(['begin', '  ', 'end;'], #13#10),
    DeletedText(LineCase(LINE_NOTE, 21)), 'Kommentar hinter der Anweisung');
  Assert.AreEqual(Joined(['begin', '  ', 'end;'], #13#10),
    DeletedText(LineCase('  Result := Value * 42;'#9'  ', 21)),
    'Tab und Leerzeichen hinter der Anweisung');
end;

// Gemischte Zeilenenden (README Testplan 0): in einer CR LF-Datei endet die
// Anweisungszeile mit LF allein. StatementDeleteEdit laesst die Einrueckung
// und GENAU dieses LF stehen - die Laenge kommt aus der Zeile, nicht aus
// dem Zeilenende des Puffers. Der Template-Code nimmt das Zeilenende des
// Puffers (TVnpText.Eol: CR LF, sobald eines vorkommt).
procedure TTestVnpTemplate.Delete_LfLineInCrLfFile;
var
  C      : TTplCase;
  Reason : string;
begin
  C := MixedCase;
  Assert.AreEqual('begin' + #13#10 + '  ' + #10 + 'end;' + #13#10,
    DeletedText(C), 'LF-Zeile nach dem Loeschen');
  Assert.AreEqual('var |vnpname| := 42;' + #13#10
    + 'Result := Value * |vnpname|;|end|', CodeOf(C, Reason),
    'Template-Code mit dem CR LF des Puffers');
end;

// StatementRestoreEdit auf dem Puffer nach StatementDeleteEdit ergibt genau
// die urspruenglichen Bytes - der Rueckweg, wenn InsertCode False liefert
// (README D1): Fall 1 CR LF, Fall 5 Tab und LF, Fall 6 UTF-8, ein Kommentar
// hinter der Anweisung, eine LF-Zeile in einer CR LF-Datei.
procedure TTestVnpTemplate.Restore_RoundTrip_Bytes;
begin
  AssertRoundTrip(Fall1, 'Fall 1');
  AssertRoundTrip(Fall5, 'Fall 5');
  AssertRoundTrip(Fall6, 'Fall 6');
  AssertRoundTrip(LineCase(LINE_NOTE, 21), 'Kommentar hinter der Anweisung');
  AssertRoundTrip(MixedCase, 'LF-Zeile in CR LF-Datei');
end;

// LoneLfCount zaehlt LF ohne CR direkt davor: nur CR LF 0, nur LF jedes,
// gemischt nur die LF-Enden, ein LF ganz vorn zaehlt, leer 0; dazu eine
// LF-Leerzeile hinter CR LF und ein einsames CR (ist kein LF).
procedure TTestVnpTemplate.LoneLfCount_Cases;
begin
  Assert.AreEqual<Integer>(0, LoneLfCount('a'#13#10'b'#13#10), 'nur CR LF');
  Assert.AreEqual<Integer>(2, LoneLfCount('a'#10'b'#10), 'nur LF');
  Assert.AreEqual<Integer>(2, LoneLfCount('a'#13#10'b'#10'c'#13#10'd'#10),
    'gemischt');
  Assert.AreEqual<Integer>(1, LoneLfCount(#10'a'#13#10'b'), 'LF ganz vorn');
  Assert.AreEqual<Integer>(0, LoneLfCount(''), 'leer');
  Assert.AreEqual<Integer>(1, LoneLfCount('a'#13#10#10'b'),
    'LF-Leerzeile hinter CR LF');
  Assert.AreEqual<Integer>(0, LoneLfCount('a'#13'b'#13), 'einsames CR');
end;

// MODELL (D-M3, in der IDE zu bestaetigen - Testplan Schritt 12): D1
// ergibt denselben Text wie C1h. Fall 1: Deklaration ueber der Anweisung,
// beide mit zwei Leerzeichen, beide 42 ersetzt, nur CR LF. Fall 5: beide
// Zeilen mit Tab, nur LF. Fall 6: Umlaute und Euro-Zeichen unversehrt, die
// 42 dahinter ersetzt. Kommentar hinter der Anweisung: genau einmal.
procedure TTestVnpTemplate.Model_D1_LikeC1h;
begin
  Assert.AreEqual(Joined(['function Scale(Value: Integer): Integer;',
    'begin',
    '  // Fall 1: zwei gleiche Literale auf der Zeile - Caret auf eine 42.',
    '  var MagicNr01 := 42;', '  Result := Value * MagicNr01 + MagicNr01;',
    'end;'], #13#10), ModelText(Fall1, '  ', #13#10), 'Fall 1 im Modell');
  Assert.AreEqual(Joined(['function Mask(Value: Cardinal): Cardinal;',
    'begin',
    #9'// Fall 5: Tab-Einrueckung und Hex-Literal - prueft die Spalten.',
    #9'var MagicNr01 := $FF00;', #9'Result := Value and MagicNr01;',
    'end;'], #10), ModelText(Fall5, #9, #10), 'Fall 5 im Modell');
  Assert.AreEqual(Joined([FALL6_NOTE,
    'function Greeting(Count: Integer): string;', 'begin',
    '  var MagicNr01 := 42;',
    '  Result := ' + QGREET + ' + IntToStr(Count * MagicNr01);', 'end;'],
    #13#10), ModelText(Fall6, '  ', #13#10), 'Fall 6 im Modell');
  Assert.AreEqual(Joined(['begin', '  var MagicNr01 := 42;',
    '  Result := Value * MagicNr01; // Hinweis', 'end;'], #13#10),
    ModelText(LineCase(LINE_NOTE, 21), '  ', #13#10),
    'Kommentar hinter der Anweisung im Modell');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVnpTemplate);
end.
