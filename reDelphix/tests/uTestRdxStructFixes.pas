unit uTestRdxStructFixes;

// Editorhilfen der Stufe 3 (uRdxStructFixes) auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA007 einen uses-Eintrag loeschen (erster, mittlerer, letzter,
//          einziger, 'in'-Pfad, Kommentar im Bereich),
//   SCA168 else vor das end des case (leer, mit raise, Einrueckung mit
//          Tabs, verschachtelt, inline, schon ein else, Direktive).
// SCA101/SCA099 (begin..end) stehen in uTestRdxBlockFixes - der FPC-
// Pruefstand kennt nur eine Fixture je Unit.
// Die Bereiche der uses-Eintraege baut der Test so, wie
// TSourcePlaces.UsesEntries sie liefert (Name, EndCol hinter dem Namen).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxStructFixes = class
  public
    // ---- SCA007 ----
    [Test] procedure Sca007_RemoveFirstAndMiddle;
    [Test] procedure Sca007_RemoveLast;
    [Test] procedure Sca007_RemoveOnly;
    [Test] procedure Sca007_InPath;
    [Test] procedure Sca007_Refusals;
    // ---- SCA168 ----
    [Test] procedure Sca168_EmptyElse;
    [Test] procedure Sca168_RaiseElse;
    [Test] procedure Sca168_NestedAndInline;
    [Test] procedure Sca168_Refusals;
    // Gegen-Review 2026-10-10: letzter Arm ohne ';' (sonst bindet das else
    // an ein if), Einrueckung nach den Armen, '&End'.
    [Test] procedure Sca168_LastArmWithoutSemicolon;
    [Test] procedure Sca168_IndentAndEscapedEnd;
    [Test] procedure Sca007_OwnLineAndSkippedEntry;
    // Review R3-04 (Charge FC): ein verschobener Fund auf dem Variantenteil
    // eines Records bekommt kein else.
    [Test] procedure Sca168_VariantRecord_Refused;
    // rwE29 (delphimvcframework MainFormU.pas:30): ein Eintrag am
    // Zeilenende zog beim Loeschen die Folgezeile herauf.
    [Test] procedure Sca007_LastOnLine_KeepsLineBreak;
    // rwE29 (skia4delphi Vcl.Styles.UxTheme.pas:1098): die raise-Zeile
    // rueckte wie die letzte Zeile des letzten Arms ein.
    [Test] procedure Sca168_RaiseIndent_FollowsArms;
    // rwE30 (cnwizards mwBCBTokenList.pas:1518, SynHighlighter*): case ueber
    // Zeichen - kein raise fuer jedes andere Zeichen.
    [Test] procedure Sca168_CharSelector_RaiseRefused;
    // rwE30 (Todo_SCA168 "verpasst-direktive"): bedingte Bereiche ohne
    // Blockwort im case sperren nicht mehr.
    [Test] procedure Sca168_HarmlessDirective_Helps;
    // rwE31 Stufe 3 (JsonDataObjects.pas:7695): Marken 'Ord('-'):' auf einem
    // Byte-Zeiger sind Zeichen - kein raise.
    [Test] procedure Sca168_OrdCharLabels_RaiseRefused;
    // rwE31 Stufe 3 (vier Fehler): raise nur in die Gluehbirne, wenn jeder
    // Wert eines Aufzaehlungstyps der Datei einen Arm hat.
    [Test] procedure Sca168_RaiseMenuReason_ValuesWithoutArm;
    [Test] procedure Sca168_RaiseMenuReason_AllValuesCovered;
    // rwE31 Stufe 3: EInvalidOpException gibt es vor Delphi 2009 nicht.
    [Test] procedure Sca168_RaiseOldCompiler_Refused;
    // rwE30 Stufe 2 (21 Fehler): der Bezeichner-Beweis (ForeignIdent) -
    // Aufzaehlungswert, Typ, Konstante, Aufruf ohne Quelle ...
    [Test] procedure Sca007_ForeignIdent_Found;
    // ... und was die Datei selbst deklariert oder eine andere Unit kennt.
    [Test] procedure Sca007_ForeignIdent_DeclaredOrKnown;
    // ... eine case-Marke im Anweisungsteil ist keine Deklaration.
    [Test] procedure Sca007_ForeignIdent_CaseLabelNotADecl;
    // rwE30 Stufe 2: Eintrag mitten in einem $IFDEF-Zweig (CEF4Delphi
    // uChildForm.pas:10) - der Zweig behaelt seine Kommafolge, der andere
    // bleibt unberuehrt; am Zweigrand lehnt RangeReason ab.
    [Test] procedure Sca007_EntryInBranch_CommaLogic;
    // rwE30 Stufe 2 (Indy indyprotocolsfpc.pas:189): die Sammel-Unit eines
    // Pakets besteht nur aus uses-Klauseln.
    [Test] procedure Sca007_UsesOnlyUnit;
    // rwE31 Stufe 3 (CEF4Delphi uChildForm.pas:10, uSimpleServer.pas:9 ...):
    // den Eintrag im Zweig eines Defines aus einer Include-Datei liefert der
    // Quellstellen-Dienst nicht - die Klausel kommt aus dem Text, alle
    // Zweige in Folge.
    [Test] procedure Sca007_TextUsesEntry_AllBranches;
    // rwE31 Stufe 3 (gexperts mPasLex.pas:80 UpperCase, issrc BidiUtils.pas:15
    // TRect): SysUtils und Types haben keine Liste im Detektor - ihre
    // Exporte schliessen den Beweis (AlwaysNeededIdents).
    [Test] procedure Sca007_ForeignIdent_SysUtilsAndTypes;
    // rwE32 Stufe 4, Nico-Entscheid E5: SCA168.2 gesperrt, wenn das case
    // nicht nach einer Aufzaehlung waehlt (Selektor-Typ, Konstanten oder
    // Zahlen als Marken) oder das Ergebnis vorbelegt ist ...
    [Test] procedure Sca168_RaiseLock_SelectorNotEnum;
    [Test] procedure Sca168_RaiseLock_ConstOrNumberLabels;
    [Test] procedure Sca168_RaiseLock_PresetResult;
    // ... die Aufzaehlung in einer Unit daneben (bis zwei Ebenen hoeher)
    // beweist die volle Abdeckung, und ohne Beweis nennt der Hinweis die
    // Marke nicht mehr "Aufzaehlung".
    [Test] procedure Sca168_RaiseMenu_NeighbourUnits;
    [Test] procedure Sca168_RaiseMenu_NeutralHint;
    // Review e/HilfeFixR: der Selektor wandelt eine Zahl in die Aufzaehlung
    // um - nur im Menue, auch wenn jeder Wert einen Arm hat.
    [Test] procedure Sca168_RaiseMenu_CastSelector;
    // Fix-Runde 4 nach rwE32 (CEF4Delphi TabbedBrowser uMainForm.pas:18
    // WM_APP): auch Messages hat im Detektor keine Liste.
    [Test] procedure Sca007_ForeignIdent_Messages;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap, uRdxStructFixes,
  uRdxText,          // _() (Gruende in der Sprache des Laufs)
  uTestRdxTextKit;   // Join, Apply

// ---- Helfer ----

// Ein uses-Eintrag wie aus TSourcePlaces.UsesEntries.
function Entry(ALine, ACol: Integer; const AName: string): TRefactorSpan;
begin
  Result := TRefactorSpan.Make('unit', ALine, ACol, ALine, ACol + Length(AName));
  Result.Resolved := AName;
end;

function Clause(AUsesLine: Integer;
  const AEntries: array of TRefactorSpan): TRdxUsesClause;
var
  i : Integer;
begin
  Result.UsesLine := AUsesLine;
  SetLength(Result.Entries, Length(AEntries));
  for i := 0 to High(AEntries) do
    Result.Entries[i] := AEntries[i];
end;

// SCA007: neuer Text oder '' bei Ablehnung (AReason).
function FixUses(const ASource: string; const AClause: TRdxUsesClause;
  AIndex: Integer; out AReason: string): string;
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
    if TRdxStructFixes.RemoveUsesEntry(Map, AClause, AIndex, E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA168: neuer Text oder '' bei Ablehnung (AReason); AStatement = ''
// fuer das leere else.
function FixCase(const ASource: string; ALine: Integer;
  const AStatement: string; out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxStructFixes.CaseElse(Map, ALine, AStatement, Edits, AReason) then
      Result := Apply(ASource, Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Anweisungen ab Zeile 4 in einer Routine.
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;']) + #13#10
    + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// SCA168, raise-Variante: der Grund fuer "nur im Menue" (CaseRaiseMenuReason)
// am case auf ALine; '' heisst Gluehbirne. ALock: der Grund der Sperre (E5,
// rwE32 Stufe 4), '' ohne; AUnitFile: die Datei (Units daneben), '' ohne.
function CaseMenuLock(const ASource: string; ALine: Integer;
  const AUnitFile: string; out ALock: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxStructFixes.CaseRaiseMenuReason(Map, ALine, AUnitFile, ALock);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function CaseMenu(const ASource: string; ALine: Integer): string;
var
  Lock : string;
begin
  Result := CaseMenuLock(ASource, ALine, '', Lock);
end;

// Der Grund der Sperre (E5) am case auf ALine; '' ohne Sperre.
function CaseLock(const ASource: string; ALine: Integer;
  const AUnitFile: string = ''): string;
begin
  CaseMenuLock(ASource, ALine, AUnitFile, Result);
end;

// Eine Unit mit den Typzeilen ATypes im interface und einer Routine, deren
// Rumpf AStmts traegt; das erste Statement steht auf Zeile
// 7 + Length(ATypes).
function WithTypes(const ATypes, AStmts: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ATypes)
    + #13#10 + Join(['implementation', 'procedure P;', 'begin']) + #13#10
    + Join(AStmts) + #13#10 + Join(['end;', 'end.']);
end;

// ---- SCA007 ----

procedure TTestRdxStructFixes.Sca007_RemoveFirstAndMiddle;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['unit u;', 'interface', 'uses', '  A,', '  B,', '  C;',
    'implementation', 'end.']);
  C := Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B'), Entry(6, 3, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  A,', '  C;',
    'implementation', 'end.']), FixUses(Src, C, 1, R), 'B mittig: ' + R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  B,', '  C;',
    'implementation', 'end.']), FixUses(Src, C, 0, R), 'A vorn: ' + R);
  // Auf einer Zeile.
  Src := Join(['unit u;', 'interface', 'uses A, B, C;', 'implementation', 'end.']);
  C := Clause(3, [Entry(3, 6, 'A'), Entry(3, 9, 'B'), Entry(3, 12, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses A, C;', 'implementation',
    'end.']), FixUses(Src, C, 1, R), R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses B, C;', 'implementation',
    'end.']), FixUses(Src, C, 0, R), R);
end;

procedure TTestRdxStructFixes.Sca007_RemoveLast;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['unit u;', 'interface', 'uses', '  A,', '  B,', '  C;',
    'implementation', 'end.']);
  C := Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B'), Entry(6, 3, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  A,', '  B;',
    'implementation', 'end.']), FixUses(Src, C, 2, R), R);
  Src := Join(['unit u;', 'interface', 'uses A, B, C;', 'implementation', 'end.']);
  C := Clause(3, [Entry(3, 6, 'A'), Entry(3, 9, 'B'), Entry(3, 12, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses A, B;', 'implementation',
    'end.']), FixUses(Src, C, 2, R), R);
end;

procedure TTestRdxStructFixes.Sca007_RemoveOnly;
var
  R, Src : string;
begin
  // 'uses' allein am Zeilenanfang: die ganzen Zeilen.
  Src := Join(['unit u;', 'interface', 'uses', '  System.Classes;',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    FixUses(Src, Clause(3, [Entry(4, 3, 'System.Classes')]), 0, R), R);
  // Hinter 'interface' auf derselben Zeile: nur der Text, samt Leerraum
  // davor (Review Woche G07-23 b: bis dahin blieb 'interface ').
  Src := Join(['unit u;', 'interface uses A;', 'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    FixUses(Src, Clause(2, [Entry(2, 16, 'A')]), 0, R), R);
  // Ein '//'-Kommentar hinter dem ';' beschrieb den Eintrag: er geht mit
  // den Zeilen (Review Woche G07-23 a: bis dahin blieb ' // TStringList').
  Src := Join(['unit u;', 'interface', 'uses', '  System.Classes; // TStringList',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    FixUses(Src, Clause(3, [Entry(4, 3, 'System.Classes')]), 0, R), R);
  // Ein Marker dahinter bleibt (er gilt der naechsten Zeile).
  Src := Join(['unit u;', 'interface', 'uses', '  System.Classes; // noinspection X',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', ' // noinspection X',
    'implementation', 'end.']),
    FixUses(Src, Clause(3, [Entry(4, 3, 'System.Classes')]), 0, R), R);
end;

procedure TTestRdxStructFixes.Sca007_InPath;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['program p;', 'uses', '  A in ''a.pas'',', '  B in ''b.pas'';',
    'begin', 'end.']);
  C := Clause(2, [Entry(3, 3, 'A'), Entry(4, 3, 'B')]);
  Assert.AreEqual(Join(['program p;', 'uses', '  B in ''b.pas'';', 'begin',
    'end.']), FixUses(Src, C, 0, R), 'erster mit Pfad: ' + R);
  Assert.AreEqual(Join(['program p;', 'uses', '  A in ''a.pas'';', 'begin',
    'end.']), FixUses(Src, C, 1, R), 'letzter mit Pfad: ' + R);
end;

procedure TTestRdxStructFixes.Sca007_Refusals;
var
  R, Src : string;
begin
  // Ein Kommentar im geloeschten Bereich ginge verloren.
  Src := Join(['unit u;', 'interface', 'uses', '  A, { wichtig }', '  B;',
    'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B')]),
    0, R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Formular-Unit im Programm: '{Form1}' hinter dem Pfad.
  Src := Join(['program p;', 'uses', '  Forms,', '  Unit1 in ''Unit1.pas'' {Form1};',
    'begin', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(2, [Entry(3, 3, 'Forms'),
    Entry(4, 3, 'Unit1')]), 1, R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Kein Komma hinter dem Eintrag (Bereich passt nicht mehr).
  Src := Join(['unit u;', 'interface', 'uses A B;', 'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A'), Entry(3, 8, 'B')]),
    0, R));
  Assert.IsTrue(Pos('","', R) > 0, R);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A')]), 2, R),
    'Index ausserhalb');
  Assert.IsTrue(Pos('kein solcher uses-Eintrag', R) > 0, R);
end;

// ---- SCA168 ----

procedure TTestRdxStructFixes.Sca168_EmptyElse;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: A;', '  end;']), 5, '', R), R);
  // Gross geschriebenes END bleibt, wie es war.
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  END;']),
    FixCase(InProc(['  case X of', '    1: A;', '  END;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca168_RaiseElse;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '    1: A;', '  end;']), 5, RAISE_UNHANDLED, R), R);
  // Tabs: eine Stufe tiefer ist ein Tab.
  Assert.AreEqual(InProc([#9'case X of', #9#9'1: A;', #9'else',
      #9#9 + RAISE_UNHANDLED, #9'end;']),
    FixCase(InProc([#9'case X of', #9#9'1: A;', #9'end;']), 5, RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_NestedAndInline;
var
  R, Src : string;
begin
  Src := InProc(['  case X of', '    1: begin', '      case Y of', '        2: B;',
    '      end;', '    end;', '  end;']);
  Assert.AreEqual(InProc(['  case X of', '    1: begin', '      case Y of',
      '        2: B;', '      end;', '    end;', '  else', '  end;']),
    FixCase(Src, 5, '', R), 'aeusseres case: ' + R);
  Assert.AreEqual(InProc(['  case X of', '    1: begin', '      case Y of',
      '        2: B;', '      else', '      end;', '    end;', '  end;']),
    FixCase(Src, 7, '', R), 'inneres case: ' + R);
  // if-else in einem Arm ist kein else des case; try zaehlt mit.
  Assert.AreEqual(InProc(['  case X of', '    1: if A then B else C;',
      '    2: try D; finally E; end;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: if A then B else C;',
      '    2: try D; finally E; end;', '  end;']), 5, '', R), R);
  // end auf derselben Zeile: inline.
  Assert.AreEqual(InProc(['  case X of 1: A; else end;']),
    FixCase(InProc(['  case X of 1: A; end;']), 5, '', R), R);
  Assert.AreEqual(InProc(['  case X of 1: A; else ' + RAISE_UNHANDLED + ' end;']),
    FixCase(InProc(['  case X of 1: A; end;']), 5, RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '  else',
    '    B;', '  end;']), 5, '', R), 'schon ein else');
  Assert.IsTrue(Pos('else-Zweig', R) > 0, R);
  // Das else des case auch OHNE ';' vor ihm (Review Quick-Fix-Units
  // 2026-10-14): es gehoert zum case, nicht zu einem if.
  Assert.AreEqual('', FixCase(InProc(['  case K of 1: Foo else Bar end;']), 5,
    '', R), 'else ohne ; davor');
  Assert.IsTrue(Pos('else-Zweig', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case K of', '    1: begin Foo end',
    '  else', '    Bar;', '  end;']), 5, '', R), 'else hinter end ohne ;');
  Assert.IsTrue(Pos('else-Zweig', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '{$IFDEF Y}', '    1: A;',
    '{$ENDIF}', '  end;']), 5, '', R), 'Direktive');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of 1: case Y of 2: A; end; end;']),
    5, '', R), 'zwei case auf der Zeile');
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  A;']), 5, '', R), 'kein case');
  Assert.IsTrue(Pos('kein case', R) > 0, R);
  Assert.AreEqual('', FixCase(Join(['  case X of', '    1: A;']), 1, '', R),
    'kein end');
  Assert.IsTrue(Pos('kein end', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '  otherwise',
    '    B;', '  end;']), 5, '', R), 'FPC otherwise');
  Assert.IsTrue(Pos('otherwise', R) > 0, R);
  // Auch OHNE ';' davor (Review Woche G07-06): FPC liest es wie die
  // else-Form - sonst kaeme 'otherwise B; else end', zwei Default-Zweige.
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A', '  otherwise',
    '    B;', '  end;']), 5, '', R), 'FPC otherwise ohne ;');
  Assert.IsTrue(Pos('otherwise', R) > 0, R);
  // 'Obj.&Case(1)' ist ein Bezeichner, keine case-Anweisung (Review Woche
  // G07-24: ein verschobener Fund schrieb sonst ein else vor das end der
  // Routine).
  Assert.AreEqual('', FixCase(InProc(['  Obj.&Case(1);']), 5, '', R),
    '&Case als Bezeichner');
  Assert.IsTrue(Pos('kein case', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '  end;']), 5, '', R),
    'ohne Zweige');
  Assert.IsTrue(Pos('keine Zweige', R) > 0, R);
end;

procedure TTestRdxStructFixes.Sca168_LastArmWithoutSemicolon;
var
  R : string;
begin
  // Ohne das ';' bande das else an das if des Arms.
  Assert.AreEqual(InProc(['  case X of', '    1: if B then DoA;', '  else',
      '  end;']),
    FixCase(InProc(['  case X of', '    1: if B then DoA', '  end;']), 5, '', R), R);
  Assert.AreEqual(InProc(['  case X of', '    1: if B then DoA;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '    1: if B then DoA', '  end;']), 5,
      RAISE_UNHANDLED, R), R);
  // Der Arm endet auf einem String - das ';' kommt hinter das Quote.
  Assert.AreEqual(InProc(['  case X of', '    1: S := ''x'';', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: S := ''x''', '  end;']), 5, '', R), R);
  // Ein Kommentar dahinter bleibt hinter dem ';'.
  Assert.AreEqual(InProc(['  case X of', '    1: DoA; // weg', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: DoA // weg', '  end;']), 5, '', R), R);
  // Inline: das ';' vor das else.
  Assert.AreEqual(InProc(['  case X of 1: if B then A; else end;']),
    FixCase(InProc(['  case X of 1: if B then A end;']), 5, '', R), R);
  // Ein if-else im letzten Arm ohne ';': das else gehoert dem if, das
  // case bekommt seines.
  Assert.AreEqual(InProc(['  case X of 1: if B then A else C; else end;']),
    FixCase(InProc(['  case X of 1: if B then A else C end;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca168_IndentAndEscapedEnd;
var
  R : string;
begin
  // Vier Leerzeichen je Stufe: die raise-Zeile folgt den Armen.
  Assert.AreEqual(InProc(['    case X of', '        1: A;', '    else',
      '        ' + RAISE_UNHANDLED, '    end;']),
    FixCase(InProc(['    case X of', '        1: A;', '    end;']), 5,
      RAISE_UNHANDLED, R), R);
  // '&End' ist ein Bezeichner, kein end.
  Assert.AreEqual(InProc(['  case X of', '    1: &End := 1;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: &End := 1;', '  end;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca007_OwnLineAndSkippedEntry;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  // Allein auf seiner Zeile: die ganze Zeile samt '//'-Kommentar.
  Src := Join(['unit u;', 'interface', 'uses', '  System.SysUtils,',
    '  System.Classes,   // TStringList', '  System.Math;', 'implementation',
    'end.']);
  C := Clause(3, [Entry(4, 3, 'System.SysUtils'), Entry(5, 3, 'System.Classes'),
    Entry(6, 3, 'System.Math')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  System.SysUtils,',
    '  System.Math;', 'implementation', 'end.']), FixUses(Src, C, 1, R), R);
  // Ein Eintrag, den UsesEntries ausliess (hier X), ginge mit - Sperre.
  Src := Join(['unit u;', 'interface', 'uses A, X, C;', 'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A'), Entry(3, 12, 'C')]),
    0, R));
  Assert.IsTrue(Pos('mehr als dieser Eintrag', R) > 0, R);
end;

// Eine Unit, deren Typabschnitt ALines traegt (ab Zeile 4).
function InTypes(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ALines)
    + #13#10 + Join(['implementation', 'end.']);
end;

procedure TTestRdxStructFixes.Sca168_VariantRecord_Refused;
var
  R, Src : string;
begin
  // Fixture a04 des Pruefers: bis Charge FC schloss das end des Records
  // die Bilanz, und das else landete in der Typdeklaration ('1: (B: Byte);
  // else end;' - uebersetzt nicht).
  Assert.AreEqual('', FixCase(InTypes(['  TRec = record', '    case Integer of',
    '      0: (A: Integer);', '      1: (B: Byte);', '  end;']), 5, '', R),
    'Variantenteil');
  Assert.IsTrue(Pos('Variantenteil', R) > 0, R);
  // Mit Feld davor, Tag-Feld und packed - die raise-Variante ebenso.
  Assert.AreEqual('', FixCase(InTypes(['  TRec = packed record', '    Kind: Byte;',
    '    case Tag: Integer of', '      0: (A: Integer);', '  end;']), 6,
    RAISE_UNHANDLED, R), 'packed, Tag-Feld, raise');
  Assert.IsTrue(Pos('Variantenteil', R) > 0, R);
  // Geschachtelter Variantenteil in der Feldliste eines Zweigs.
  Assert.AreEqual('', FixCase(InTypes(['  TRec = record', '    case Integer of',
    '      0: (A: Integer;', '        case B: Byte of', '          1: (C: Byte));',
    '  end;']), 7, '', R), 'geschachtelt');
  Assert.IsTrue(Pos('Variantenteil', R) > 0, R);
  // Gegenproben: case-Anweisungen bleiben Hilfen - im initialization-
  // Abschnitt, im Arm eines aeusseren case, im Rumpf einer anonymen
  // Methode in einem Aufruf und hinter einem lokalen Record-Typ mit
  // Variantenteil (dessen case bleibt gesperrt).
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
      'initialization', '  case X of', '    1: A;', '  else', '  end;', 'end.']),
    FixCase(Join(['unit u;', 'interface', 'implementation', 'initialization',
      '  case X of', '    1: A;', '  end;', 'end.']), 5, '', R), R);
  Assert.AreEqual(InProc(['  case X of', '    1: case Y of', '         2: A;',
      '       else', '       end;', '  end;']),
    FixCase(InProc(['  case X of', '    1: case Y of', '         2: A;',
      '       end;', '  end;']), 6, '', R), R);
  Assert.AreEqual(InProc(['  Run(procedure', '    begin', '      case X of',
      '        1: A;', '      else', '      end;', '    end);']),
    FixCase(InProc(['  Run(procedure', '    begin', '      case X of',
      '        1: A;', '      end;', '    end);']), 7, '', R), R);
  Src := Join(['unit u;', 'implementation', 'procedure P;', 'type',
    '  TR = record', '    case Integer of', '      0: (A: Integer);', '  end;',
    'begin', '  case X of', '    1: A;', '  end;', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, '    1: A;'#13#10'  end;',
      '    1: A;'#13#10'  else'#13#10'  end;', []), FixCase(Src, 10, '', R), R);
  Assert.AreEqual('', FixCase(Src, 6, '', R), 'lokaler Record');
  Assert.IsTrue(Pos('Variantenteil', R) > 0, R);
  // Je Zweig einer Direktive ein 'Foo(' vor einer case-Anweisung (Fixture
  // s08 der Nachpruefung FC): die offene '(' ist kein Variantenteil, die
  // Lage ist unklar - gesperrt, aber nicht mehr mit dem Grund
  // 'Variantenteil'.
  Assert.AreEqual('', FixCase(InProc(['  {$IFDEF A} Foo( {$ELSE} Bar( {$ENDIF} 1);',
    '  case X of', '    1: ;', '  end;']), 6, '', R), 'Direktive vor dem case');
  Assert.IsTrue(Pos('offenen ( und dem case', R) > 0, R);
  Assert.IsTrue(Pos('Variantenteil', R) = 0, R);
end;

procedure TTestRdxStructFixes.Sca007_LastOnLine_KeepsLineBreak;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  // Muster der Fundstelle (minimiert): 'Vcl.Graphics,' steht als letzter
  // Eintrag am Ende von Zeile 4, die Klausel geht auf Zeile 5 weiter. Bis
  // rwE29 reichte der Schnitt bis vor 'Vcl.Controls' und frass Umbruch und
  // Einrueckung: 'uses' / '  System.Classes, Vcl.Controls, Vcl.Forms;'.
  Src := Join(['unit u;', 'interface', 'uses',
    '  System.Classes, Vcl.Graphics,', '  Vcl.Controls, Vcl.Forms;',
    'implementation', 'end.']);
  C := Clause(3, [Entry(4, 3, 'System.Classes'), Entry(4, 19, 'Vcl.Graphics'),
    Entry(5, 3, 'Vcl.Controls'), Entry(5, 17, 'Vcl.Forms')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  System.Classes,',
    '  Vcl.Controls, Vcl.Forms;', 'implementation', 'end.']),
    FixUses(Src, C, 1, R), 'Zeilenende: ' + R);
  // Leerraum hinter dem Komma geht mit (keine Leerzeichen am Zeilenende).
  Src := Join(['unit u;', 'interface', 'uses',
    '  System.Classes, Vcl.Graphics,   ', '  Vcl.Controls, Vcl.Forms;',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  System.Classes,',
    '  Vcl.Controls, Vcl.Forms;', 'implementation', 'end.']),
    FixUses(Src, C, 1, R), 'Zeilenende mit Leerraum: ' + R);
  // Gegenproben: der erste Eintrag der Folgezeile und der erste der
  // Klausel bleiben beim Schnitt bis vor den naechsten Eintrag.
  Src := Join(['unit u;', 'interface', 'uses',
    '  System.Classes, Vcl.Graphics,', '  Vcl.Controls, Vcl.Forms;',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses',
    '  System.Classes, Vcl.Graphics,', '  Vcl.Forms;', 'implementation',
    'end.']), FixUses(Src, C, 2, R), 'Zeilenanfang: ' + R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  Vcl.Graphics,',
    '  Vcl.Controls, Vcl.Forms;', 'implementation', 'end.']),
    FixUses(Src, C, 0, R), 'erster der Klausel: ' + R);
  // Ein Kommentar hinter dem Komma: der neue Schnitt greift nicht, der
  // alte bis vor den naechsten Eintrag sperrt wie bisher.
  Src := Join(['unit u;', 'interface', 'uses',
    '  System.Classes, Vcl.Graphics, // TBitmap', '  Vcl.Controls, Vcl.Forms;',
    'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, C, 1, R), 'Kommentar dahinter');
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
end;

procedure TTestRdxStructFixes.Sca168_RaiseIndent_FollowsArms;
var
  R : string;
begin
  // Muster der Fundstelle (minimiert): der letzte Arm endet tief in einem
  // begin..end. Bis rwE29 nahm die raise-Zeile die Einrueckung der Zeile
  // vor dem end ('         end;' -> sieben Stufen statt einer).
  Assert.AreEqual(InProc(['  case X of', '    1:', '       begin',
      '         if A then', '           Exit(1);', '       end;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '    1:', '       begin',
      '         if A then', '           Exit(1);', '       end;', '  end;']),
      5, RAISE_UNHANDLED, R), R);
  // Leerzeile und Kommentar vor dem ersten Arm zaehlen nicht.
  Assert.AreEqual(InProc(['  case X of', '', '    // erster', '    1: A;',
      '    2: begin', '          B;', '       end;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '', '    // erster', '    1: A;',
      '    2: begin', '          B;', '       end;', '  end;']), 5,
      RAISE_UNHANDLED, R), R);
  // Gegenprobe: erster Arm auf der case-Zeile - wie bisher die Zeile vor
  // dem end.
  Assert.AreEqual(InProc(['  case X of 1: A;', '    2: B;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of 1: A;', '    2: B;', '  end;']), 5,
      RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_CharSelector_RaiseRefused;
var
  R, Src : string;
begin
  // cnwizards mwBCBTokenList.pas:1518 (minimiert): die Schleife liest
  // Ziffern und '.', jedes andere Zeichen ist Normalfall - mit raise waere
  // der Tokenizer kaputt. Bis rwE30 angeboten, dazu vier Spalten unter dem
  // else statt zwei (rot ohne Fix).
  Src := InProc(['        case FOrigin[Running] of', '          ''.'':',
    '            if FOrigin[Running + 1] <> ''.'' then Result := ctkfloat '
    + 'else break;', '        end;']);
  Assert.AreEqual('', FixCase(Src, 5, RAISE_UNHANDLED, R), 'Zeichen-Arm');
  Assert.IsTrue(Pos('Zeichen', R) > 0, R);
  // Das leere else bleibt (bedeutungsgleich).
  Assert.AreEqual(InProc(['        case FOrigin[Running] of', '          ''.'':',
      '            if FOrigin[Running + 1] <> ''.'' then Result := ctkfloat '
      + 'else break;', '        else', '        end;']),
    FixCase(Src, 5, '', R), R);
  // '#13'-Marken ebenso.
  Assert.AreEqual('', FixCase(InProc(['  case S[i] of', '    #13, #10: Inc(L);',
    '  end;']), 5, RAISE_UNHANDLED, R), '#13');
  Assert.IsTrue(Pos('Zeichen', R) > 0, R);
  // Gegenprobe: Zahl-Marken - raise bleibt.
  Assert.AreEqual(InProc(['  case K of', '    1: A;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case K of', '    1: A;', '  end;']), 5, RAISE_UNHANDLED,
      R), R);
end;

procedure TTestRdxStructFixes.Sca168_HarmlessDirective_Helps;
var
  R, Src : string;
begin
  // delphimvcframework dmustache mormot.core.rtti.pas:7170 (minimiert): ein
  // ganzer Arm unter {$ifdef} - bis rwE30 gesperrt (rot ohne Fix).
  Src := InProc(['  case Value.Kind of', '    rkLString:', '      A;',
    '    {$ifdef HASVARUSTRING}', '    rkUString:', '      B;',
    '    {$endif HASVARUSTRING}', '    rkVariant:', '      begin', '        C;',
    '      end;', '  end;']);
  Assert.AreEqual(StringReplace(Src, '      end;'#13#10'  end;',
    '      end;'#13#10'  else'#13#10'  end;', []), FixCase(Src, 5, '', R), R);
  // mORMot2 mormot.db.rad.pas:1074: je eine Zuweisung in {$ifdef}..{$else}
  // ..{$endif}, auch in einem begin..end-Arm.
  Src := InProc(['  case aParam.VType of', '    ftInt64:', '      {$ifdef UNICODE}',
    '      V := par.AsLargeInt;', '      {$else}', '      V := trunc(par.AsFloat);',
    '      {$endif UNICODE}', '    ftBlob:', '      begin', '        {$ifdef UNICODE}',
    '        tmp := par.AsBlob;', '        {$else}', '        D := par.AsString;',
    '        {$endif UNICODE}', '      end;', '  end;']);
  Assert.AreEqual(StringReplace(Src, '      end;'#13#10'  end;',
    '      end;'#13#10'  else'#13#10'  end;', []), FixCase(Src, 5, '', R), R);
  // jvcl JvRegAuto.pas:615: ein Label in der Liste.
  Src := InProc(['  case PropTyp of', '    tkFloat:', '      LoadFloatPrp;',
    '    tkString, tkLString {$IFDEF COMPILER3_UP}, tkWString {$ENDIF}:',
    '      LoadStrPrp;', '  end;']);
  Assert.AreEqual(StringReplace(Src, '      LoadStrPrp;'#13#10'  end;',
    '      LoadStrPrp;'#13#10'  else'#13#10'  end;', []), FixCase(Src, 5, '', R),
    R);
  // Gegenproben - gesperrt bleiben: ein Blockwort im Bereich, ein Bereich
  // ueber das case hinaus, ein Include, ein letzter Arm, dessen ';' nur in
  // einem Zweig steht (das else binde sonst an das if).
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '    {$IFDEF Y}',
    '    2: begin B; end;', '    {$ENDIF}', '  end;']), 5, '', R), 'begin');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '    {$IFDEF Y}',
    '    2: B;', '  end;', '  {$ENDIF}']), 5, '', R), 'offen');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;',
    '    {$I arms.inc}', '  end;']), 5, '', R), 'Include');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: if A then B',
    '    {$IFDEF Y};{$ENDIF}', '  end;']), 5, '', R), 'Semikolon im Zweig');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

// SCA007, Bezeichner-Beweis: der erste Bezeichner ohne Quelle und seine
// Zeile; '' = vollstaendig.
function Foreign(const ASource: string; const AKnown: array of string;
  out ALine: Integer): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Known : TArray<string>;
  i     : Integer;
begin
  SetLength(Known, Length(AKnown));
  for i := 0 to High(AKnown) do
    Known[i] := AKnown[i];
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxStructFixes.ForeignIdent(Map, Known, ALine);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Formular-Unit wie CnSelectMaskFrm.pas (rwE30, minimiert): AUses als
// uses-Klausel, AField als Feld, ABody im Rumpf von TForm1.Check.
function FormUnit(const AUses, AField, ABody: string): string;
begin
  Result := Join(['unit Form1U;', 'interface', 'uses ' + AUses + ';', 'type',
    '  TForm1 = class(TForm)', '    ' + AField, '  public',
    '    function Check: Boolean;', '  end;', 'implementation',
    'function TForm1.Check: Boolean;', 'begin', '  ' + ABody, 'end;',
    'end.']);
end;

procedure TTestRdxStructFixes.Sca007_ForeignIdent_Found;
var
  Li : Integer;
begin
  // CnSelectMaskFrm.pas:106 - mrOk kam aus Controls, der Fund nannte
  // Controls ungenutzt; ohne Beweis nur im Menue.
  Assert.AreEqual('mrOk', Foreign(FormUnit('Classes, Forms, Controls',
    'Edit1: TEdit;', 'Result := ModalResult = mrOk;'), ['tform', 'tedit'],
    Li));
  Assert.AreEqual<Integer>(13, Li, 'Zeile');
  // CnTestNtaCurrLineWizard.pas:66 - TShortCut (Classes) als Ergebnistyp.
  Assert.AreEqual('TShortCut', Foreign(Join(['unit W;', 'interface',
    'uses Classes, Menus;', 'type', '  TWiz = class(TComponent)',
    '    function GetDefShortCut: TShortCut;', '  end;', 'implementation',
    'end.']), ['tcomponent', 'tmenu'], Li));
  // dlgAboutPyScripter.pas:31 - Konstante einer message-Direktive.
  Assert.AreEqual('CN_NOTIFY', Foreign(FormUnit('Vcl.Forms, Vcl.Controls',
    'procedure CNNotify(var Message: TWMNotify); message CN_NOTIFY;',
    'Result := True;'), ['tform', 'twmnotify'], Li));
  // Vcl.Styles.DbGrid.pas:239 - eine freie Funktion (Vcl.Forms).
  Assert.AreEqual('ValidParentForm', Foreign(FormUnit('Vcl.Forms',
    'Edit1: TEdit;', 'Result := ValidParentForm(Self) <> nil;'),
    ['tform', 'tedit'], Li));
  // JvToolBar.pas:70 - Mengenwert im Ausdruck.
  Assert.AreEqual('csAcceptsControls', Foreign(FormUnit('Forms, Controls',
    'Edit1: TEdit;', 'Result := csAcceptsControls in ControlStyle;'),
    ['tform', 'tedit'], Li));
end;

procedure TTestRdxStructFixes.Sca007_ForeignIdent_DeclaredOrKnown;
var
  Li  : Integer;
  Src : string;
begin
  // Gegenprobe zu Found: was die Datei deklariert oder eine andere Unit
  // kennt, beweist nichts gegen die entfernte Unit - '' (Gluehbirne).
  Assert.AreEqual('', Foreign(FormUnit('Classes, Forms, Variants',
    'btnOK: TButton;', 'Result := btnOK.Caption = '''';'),
    ['tform', 'tbutton'], Li), 'Feld im Ungarn-Stil, Typ bekannt');
  Src := Join(['unit U;', 'interface', 'uses Classes, Math;', 'type',
    '  TMode = (mdFast, mdSlow);', '  EMyError = class(Exception);',
    'const', '  MAX_ITEMS = 10;', '  cDefault: TMode = mdFast;',
    'function Twice(A: Integer): Integer;', 'implementation',
    'function Twice(A: Integer): Integer;', 'var', '  lCount: Integer;',
    'begin', '  lCount := MAX_ITEMS;', '  if cDefault = mdSlow then',
    '    Result := Integer(A) * 2', '  else', '    Result := Length(''x'');',
    '  try', '    Exit;', '  except', '    on E: EMyError do', '      Exit;',
    '  end;', '  var lValue := Round(1.5);', 'end;', 'end.']);
  Assert.AreEqual('', Foreign(Src, ['tcomponent'], Li),
    'Aufzaehlung, Klasse, Konstanten, Inline-Variable, System');
  // Member hinter '.' und die uses-Klausel zaehlen nicht.
  Assert.AreEqual('', Foreign(FormUnit('Vcl.Forms, System.UITypes',
    'Edit1: TEdit;', 'Result := Self.ModalResult = Self.ModalResult;'),
    ['tform', 'tedit'], Li), 'Member und uses');
end;

procedure TTestRdxStructFixes.Sca007_ForeignIdent_CaseLabelNotADecl;
var
  Li : Integer;
begin
  // 'mrOk:' als Marke eines case-Zweigs deklariert nichts - im
  // Deklarationsteil hiesse 'X: T' ein Feld bzw. eine Variable.
  Assert.AreEqual('mrOk', Foreign(FormUnit('Forms, Controls',
    'Edit1: TEdit;', 'case ModalResult of mrOk: Result := True; else '
    + 'Result := False; end;'), ['tform', 'tedit'], Li));
  // Review e/HilfeFixH: dieselbe Marke in einer anonymen Methode als
  // Argument (FMX-Muster TDialogService.MessageDialog) - die Klammer des
  // Aufrufs macht sie nicht zur Parameterliste; der Parameter der anonymen
  // Methode (im Stil eines Typs: EResult) ist dagegen deklariert. Vorher ''
  // (mrYes galt als deklariert, die Hilfe stand in der Gluehbirne).
  Assert.AreEqual('mrYes', Foreign(FormUnit('FMX.Forms, FMX.DialogService',
    'Edit1: TEdit;', 'TDialogService.MessageDialog(''?'', '
    + 'TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes], TMsgDlgBtn.mbNo, 0, '
    + 'procedure(const EResult: TModalResult) begin case EResult of mrYes: '
    + 'Close; end; end); Result := True;'), ['tform', 'tedit',
    'tdialogservice', 'tmsgdlgtype', 'tmsgdlgbtn', 'tmodalresult'], Li),
    'anonyme Methode als Argument');
  Assert.AreEqual<Integer>(13, Li, 'Zeile');
  // Der Variantenteil eines records ist kein Anweisungsteil: 'fkA:' ist dort
  // ein Feld.
  Assert.AreEqual('', Foreign(Join(['unit U;', 'interface', 'type',
    '  TRec = record', '    case Integer of', '      0: (vxAlpha: Integer);',
    '      1: (vxBeta: Byte);', '  end;', 'implementation',
    'procedure P(var R: TRec);', 'begin', '  R.vxAlpha := vxBeta;', 'end;',
    'end.']), [], Li), 'Variantenteil');
end;

procedure TTestRdxStructFixes.Sca007_EntryInBranch_CommaLogic;
var
  R, Src, L : string;
  C         : TRdxUsesClause;
begin
  // uChildForm.pas:10 (minimiert): Vcl.ClipBrd mitten im Zweig - nur er
  // und sein Komma gehen, der {$ELSE}-Zweig bleibt Zeichen fuer Zeichen.
  Src := Join(['unit u;', 'interface', 'uses', '  {$IFDEF D16}',
    '  Vcl.Forms, Vcl.ClipBrd, Vcl.Menus,', '  {$ELSE}',
    '  Forms, ClipBrd, Menus,', '  {$ENDIF}', '  uCEF;', 'implementation',
    'end.']);
  C := Clause(3, [Entry(5, 3, 'Vcl.Forms'), Entry(5, 14, 'Vcl.ClipBrd'),
    Entry(5, 27, 'Vcl.Menus'), Entry(9, 3, 'uCEF')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  {$IFDEF D16}',
    '  Vcl.Forms, Vcl.Menus,', '  {$ELSE}', '  Forms, ClipBrd, Menus,',
    '  {$ENDIF}', '  uCEF;', 'implementation', 'end.']),
    FixUses(Src, C, 1, R), 'mitten im Zweig: ' + R);
  // Der letzte des Zweigs am Zeilenende: ab dem Komma davor - das Komma
  // vor {$ELSE} bleibt, der Zweig endet weiter mit einem.
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  {$IFDEF D16}',
    '  Vcl.Forms, Vcl.ClipBrd,', '  {$ELSE}', '  Forms, ClipBrd, Menus,',
    '  {$ENDIF}', '  uCEF;', 'implementation', 'end.']),
    FixUses(Src, C, 2, R), 'Zeilenende im Zweig: ' + R);
  // Gegenprobe: der Bereich bis zum naechsten Eintrag reichte ueber
  // {$ELSE}..{$ENDIF} - gesperrt.
  L := '  {$IFDEF D16} Vcl.Forms, {$ELSE} Forms, {$ENDIF} uCEF;';
  Src := Join(['unit u;', 'interface', 'uses', L, 'implementation', 'end.']);
  C := Clause(3, [Entry(4, Pos('Vcl.Forms', L), 'Vcl.Forms'),
    Entry(4, Pos('uCEF', L), 'uCEF')]);
  Assert.AreEqual('', FixUses(Src, C, 0, R), 'Bereich ueber die Direktive');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

procedure TTestRdxStructFixes.Sca168_OrdCharLabels_RaiseRefused;
var
  R, Src : string;
begin
  // JsonDataObjects.pas:7695 (minimiert): der Exponent einer Zahl, P ist ein
  // PByte - jedes Zeichen ohne Vorzeichen ('1e5') ist Normalfall. Bis rwE31
  // sah die Zeichen-Sperre nur ein Literal am Anfang der Marke: raise
  // angeboten (rot ohne Fix).
  Src := InProc(['  case P^ of', '    Ord(''-''):', '      begin',
    '        {$IFNDEF KEEP_BIGDECIMAL_PRECISION}', '        NegE := True;',
    '        {$ENDIF ~KEEP_BIGDECIMAL_PRECISION}', '        Inc(P);', '      end;',
    '    Ord(''+''):', '      Inc(P);', '  end;']);
  Assert.AreEqual('', FixCase(Src, 5, RAISE_UNHANDLED, R), 'Ord-Zeichen');
  Assert.IsTrue(Pos('Zeichen', R) > 0, R);
  // Das leere else bleibt (bedeutungsgleich).
  Assert.AreEqual(StringReplace(Src, '      Inc(P);'#13#10'  end;',
    '      Inc(P);'#13#10'  else'#13#10'  end;', []), FixCase(Src, 5, '', R), R);
  // 'Chr(13):' ist immer ein Zeichen, 'Byte(#10):' ebenso.
  Assert.AreEqual('', FixCase(InProc(['  case C of', '    Chr(13): Inc(L);',
    '  end;']), 5, RAISE_UNHANDLED, R), 'Chr');
  Assert.AreEqual('', FixCase(InProc(['  case B of', '    Byte(#10): Inc(L);',
    '  end;']), 5, RAISE_UNHANDLED, R), 'Byte(#10)');
  // Gegenprobe: Ord um einen Namen ist kein Zeichen - die Sperre greift
  // nicht (ob raise in die Gluehbirne kommt, sagt CaseRaiseMenuReason).
  Assert.AreNotEqual('', FixCase(InProc(['  case K of', '    Ord(kA): A;',
    '  end;']), 5, RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_RaiseMenuReason_ValuesWithoutArm;
var
  R : string;
begin
  // abziptyp.pas:2343 (minimiert): aaFailed hat keinen Arm und ist in der
  // Routine ein erwarteter Wert. Der Typ steht hier in der Datei - der Grund
  // nennt den Wert. Bis rwE31 gab es keinen Grund: raise in der Gluehbirne
  // (rot ohne Fix).
  R := CaseMenu(WithTypes(['  TAbArchiveAction = (aaFailed, aaNone, aaAdd, '
    + 'aaDelete, aaFreshen, aaMove, aaReplace, aaStreamAdd);'],
    ['  case CurrItem.Action of', '    aaNone, aaMove: CopyIt;',
    '    aaDelete: begin', '      end;',
    '    aaAdd, aaFreshen, aaReplace, aaStreamAdd: AddIt;', '  end;']), 8);
  Assert.IsTrue(Pos('aaFailed', R) > 0, R);
  Assert.IsTrue(Pos('TAbArchiveAction', R) > 0, R);
  // Im Korpus steht TAbArchiveAction in abutils.pas - der Typ ist hier
  // unbekannt.
  R := CaseMenu(InProc(['  case CurrItem.Action of', '    aaNone, aaMove: CopyIt;',
    '    aaAdd, aaFreshen: AddIt;', '  end;']), 5);
  Assert.IsTrue(Pos('aaNone', R) > 0, R);
  // mormot.orm.mongodb.pas:1596 (minimiert): ein Arm, mDELETE kommt
  // regulaer vor; TUriMethod steht in einer anderen Unit.
  Assert.AreNotEqual('', CaseMenu(InProc(['  case fBatchMethod of',
    '    mPOST:', '      begin', '        fBatchWriter := TBsonWriter.Create(S);',
    '      end;', '  end;']), 5));
  // mormot.orm.core.pas:5897 (minimiert, Typ in der Datei): der aeussere
  // Arm laesst oftID und oftSet durch, der innere case nennt sie nicht.
  R := CaseMenu(WithTypes(['  TOrmFieldType = (oftUnknown, oftEnumerate, '
    + 'oftSet, oftID, oftTimeLog);'], ['  case result of',
    '    oftEnumerate, oftSet, oftID, oftTimeLog:', '      begin',
    '        if err <> 0 then', '          result := oftUnknown', '        else',
    '          case result of', '            oftEnumerate: Exit;',
    '            oftTimeLog: goto dt;', '          end;', '      end;', '  end;']),
    14);
  Assert.IsTrue(Pos('oftUnknown, oftSet, oftID', R) > 0, R);
  // Zahlen als Marken: nicht beweisbar.
  Assert.AreNotEqual('', CaseMenu(InProc(['  case X of', '    1: A;', '  end;']),
    5));
  // Ein Typ mit eigenen Zahlen hat Werte ohne Namen; zwei Deklarationen in
  // Zweigen; eine Direktive im case - je nicht beweisbar.
  Assert.AreNotEqual('', CaseMenu(WithTypes(['  TE = (eA = 1, eB = 5);'],
    ['  case E of', '    eA: A;', '    eB: B;', '  end;']), 8), 'eigene Zahlen');
  Assert.AreNotEqual('', CaseMenu(WithTypes(['{$IFDEF X}', '  TE = (eA, eB);',
    '{$ELSE}', '  TE = (eA, eB, eC);', '{$ENDIF}'], ['  case E of', '    eA: A;',
    '    eB: B;', '  end;']), 12), 'zwei Deklarationen');
  Assert.AreNotEqual('', CaseMenu(WithTypes(['  TE = (eA, eB);'], ['  case E of',
    '    eA: A;', '    {$IFDEF X}', '    eB: B;', '    {$ENDIF}', '  end;']), 8),
    'Direktive');
end;

procedure TTestRdxStructFixes.Sca168_RaiseMenuReason_AllValuesCovered;
begin
  // Jeder Wert hat einen Arm (auch ueber einen Bereich, qualifiziert, mit
  // einem verschachtelten case im Arm): das else erreicht nur ein Wert
  // ausserhalb des Typs - raise sichert ab, die Gluehbirne bleibt.
  Assert.AreEqual('', CaseMenu(WithTypes(['  TE = (eA, eB, eC, eD);'],
    ['  case E of', '    eA: begin', '        case F of 1: X; end;', '      end;',
    '    eB..eC: Y;', '    TE.eD: if Z then Exit else Y;', '  end;']), 8));
  // False und True.
  Assert.AreEqual('', CaseMenu(InProc(['  case Ok of', '    False: A;',
    '    True: B;', '  end;']), 5));
  // Gegenprobe: der Bereich laesst eD aus.
  Assert.IsTrue(Pos('eD', CaseMenu(WithTypes(['  TE = (eA, eB, eC, eD);'],
    ['  case E of', '    eA..eC: Y;', '  end;']), 8)) > 0);
end;

procedure TTestRdxStructFixes.Sca168_RaiseOldCompiler_Refused;
var
  R, Src : string;
begin
  // Eine Unit, die nach Delphi 7 fragt (VER150): EInvalidOpException steht
  // in SysUtils erst ab Delphi 2009 - der Klick braeche dort den Bau. Bis
  // rwE31 angeboten (rot ohne Fix).
  Src := Join(['unit u;', '{$IFDEF VER150}', '{$DEFINE OLD}', '{$ENDIF}',
    'implementation', 'procedure P;', 'begin', '  case X of', '    1: A;',
    '  end;', 'end;', 'end.']);
  Assert.AreEqual('', FixCase(Src, 8, RAISE_UNHANDLED, R), 'Delphi 7');
  Assert.IsTrue(Pos('VER150', R) > 0, R);
  Assert.IsTrue(Pos('EInvalidOpException', R) > 0, R);
  // Das leere else bleibt.
  Assert.AreNotEqual('', FixCase(Src, 8, '', R), R);
  // Gegenprobe: ein RTL-Namensraum ausserhalb der Weiche beweist Delphi
  // ab XE2.
  Src := Join(['unit u;', '{$IFDEF VER150}', '{$DEFINE OLD}', '{$ENDIF}',
    'implementation', 'uses System.SysUtils;', 'procedure P;', 'begin',
    '  case X of', '    1: A;', '  end;', 'end;', 'end.']);
  Assert.AreNotEqual('', FixCase(Src, 9, RAISE_UNHANDLED, R), R);
end;

function UsesOnly(const ASource: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxStructFixes.UsesOnlyUnit(Map);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxStructFixes.Sca007_UsesOnlyUnit;
begin
  // indyprotocolsfpc.pas (minimiert): uses, leeres implementation mit
  // Kommentar und {$hints off}.
  Assert.IsTrue(UsesOnly(Join(['unit indyprotocolsfpc;', 'interface', 'uses',
    '  IdSMTP,', '  IdPOP3;', 'implementation', '{ compile the units }',
    '{$hints off}', 'end.'])), 'Paket-Unit');
  // Gegenproben: ein Typ, eine Routine, ein Programm.
  Assert.IsFalse(UsesOnly(Join(['unit u;', 'interface', 'uses A;', 'type',
    '  TFoo = class end;', 'implementation', 'end.'])), 'Typ');
  Assert.IsFalse(UsesOnly(Join(['unit u;', 'interface', 'uses A;',
    'implementation', 'procedure P; begin end;', 'end.'])), 'Routine');
  Assert.IsFalse(UsesOnly(Join(['program p;', 'uses A;', 'begin', 'end.'])),
    'Programm');
end;

// SCA007: TRdxStructFixes.TextUsesEntry auf ASource - die Zahl der Treffer.
function TextEntry(const ASource: string; ALine: Integer; const AUnit: string;
  out AClause: TRdxUsesClause; out AIndex: Integer): Integer;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxStructFixes.TextUsesEntry(Map, ALine, AUnit, AClause,
      AIndex);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxStructFixes.Sca007_TextUsesEntry_AllBranches;
var
  Src, R, L : string;
  C         : TRdxUsesClause;
  Ix        : Integer;
begin
  // uChildForm.pas:10 (minimiert): DELPHI16_UP kommt aus cef.inc, der Dienst
  // liefert nur den {$ELSE}-Zweig - Vcl.ClipBrd fehlte, der Grund war
  // "steht nicht mehr auf Zeile 5".
  Src := Join(['unit u;', 'interface', 'uses', '  {$IFDEF DELPHI16_UP}',
    '  Vcl.Forms, Vcl.ClipBrd, Vcl.Menus,', '  {$ELSE}',
    '  Forms, ClipBrd, Menus,', '  {$ENDIF}', '  uCEF;', 'implementation',
    'end.']);
  Assert.AreEqual<Integer>(1, TextEntry(Src, 5, 'Vcl.ClipBrd', C, Ix));
  Assert.AreEqual<Integer>(3, C.UsesLine, 'Zeile von uses');
  Assert.AreEqual<Integer>(7, Length(C.Entries), 'beide Zweige und uCEF');
  Assert.AreEqual<Integer>(1, Ix, 'Index');
  Assert.AreEqual('ClipBrd', C.Entries[4].Resolved, 'Zwilling im ELSE');
  Assert.AreEqual<Integer>(14, C.Entries[1].StartCol, 'Spalte');
  Assert.AreEqual<Integer>(25, C.Entries[1].EndCol, 'hinter dem Namen');
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses',
    '  {$IFDEF DELPHI16_UP}', '  Vcl.Forms, Vcl.Menus,', '  {$ELSE}',
    '  Forms, ClipBrd, Menus,', '  {$ENDIF}', '  uCEF;', 'implementation',
    'end.']), FixUses(Src, C, Ix, R), 'mitten im Zweig: ' + R);
  // Der Zwilling im {$ELSE}-Zweig ist ein eigener Eintrag; ein anderer
  // Name oder eine andere Zeile trifft nichts.
  Assert.AreEqual<Integer>(1, TextEntry(Src, 7, 'ClipBrd', C, Ix), 'ELSE');
  Assert.AreEqual<Integer>(0, TextEntry(Src, 7, 'Vcl.ClipBrd', C, Ix),
    'andere Zeile');
  // Gegenprobe: am Zweigrand reicht der Bereich ueber {$ELSE} - gesperrt.
  L := '  {$IFDEF D16} Vcl.Forms, {$ELSE} Forms, {$ENDIF} uCEF;';
  Src := Join(['unit u;', 'interface', 'uses', L, 'implementation', 'end.']);
  Assert.AreEqual<Integer>(1, TextEntry(Src, 4, 'Vcl.Forms', C, Ix));
  Assert.AreEqual('', FixUses(Src, C, Ix, R), 'Bereich ueber die Direktive');
  Assert.IsTrue(Pos(_('comment or directive in the range to be deleted'),
    R) > 0, R);
  // Zweige mit eigener Kommafolge ergeben keine Folge 'Name, Name ;' - der
  // Text liefert nichts.
  Src := Join(['unit u;', 'interface', 'uses',
    '  {$IFDEF X} A, B {$ELSE} C {$ENDIF};', 'implementation', 'end.']);
  Assert.AreEqual<Integer>(0, TextEntry(Src, 4, 'B', C, Ix), 'Kommafolge');
end;

procedure TTestRdxStructFixes.Sca007_ForeignIdent_SysUtilsAndTypes;
var
  Li  : Integer;
  Src : string;
begin
  // mPasLex.pas (minimiert): UpperCase kommt aus SysUtils, Controls ist
  // ungenutzt. Vorher nannte der Hinweis UpperCase - nur im Menue.
  Src := Join(['unit mPasLex;', 'interface', 'uses',
    '  SysUtils, Windows, Classes, Controls;', 'function Up(const S: string): '
    + 'string;', 'implementation', 'function Up(const S: string): string;',
    'begin', '  Result := UpperCase(S);', 'end;', 'end.']);
  Assert.AreEqual('UpperCase', Foreign(Src, [], Li), 'ohne Liste');
  Assert.AreEqual('', Foreign(Src,
    TRdxStructFixes.AlwaysNeededIdents('sysutils'), Li), 'SysUtils');
  // BidiUtils.pas:15 (minimiert): TRect aus Types.
  Src := Join(['unit BidiUtils;', 'interface', 'uses Classes, Types;',
    'procedure FlipRect(var Rect: TRect);', 'implementation',
    'procedure FlipRect(var Rect: TRect);', 'begin', 'end;', 'end.']);
  Assert.AreEqual('TRect', Foreign(Src, [], Li), 'ohne Liste');
  Assert.AreEqual('', Foreign(Src,
    TRdxStructFixes.AlwaysNeededIdents('system.types'), Li), 'Types');
  // Nur die beiden Units: andere bleiben leer (die Listen des Detektors).
  Assert.AreEqual<Integer>(0,
    Length(TRdxStructFixes.AlwaysNeededIdents('classes')), 'Classes');
  Assert.AreEqual<Integer>(0,
    Length(TRdxStructFixes.AlwaysNeededIdents('windows')), 'Windows');
end;

// ---- SCA168.2, Nico-Entscheid E5 (rwE32 Stufe 4) ----

procedure TTestRdxStructFixes.Sca168_RaiseLock_SelectorNotEnum;
var
  R, Src : string;
begin
  // vcl-styles-utils Vcl.Styles.UxTheme.pas:2330 (minimiert): iStateId ist
  // Integer, TUS_NORMAL eine Integer-Konstante aus Winapi.UxTheme - jeder
  // andere Zustand faellt zum Trampolin durch. Bis rwE32 nur im Menue, der
  // Hinweis nannte "die Aufzaehlung von TUS_NORMAL" (rot ohne Fix: keine
  // Sperre).
  Src := Join(['unit u;', 'interface', 'implementation',
    'function Hook(hTheme: THandle; iPartId, iStateId: Integer): HRESULT;',
    'begin', '  case iStateId of', '    TUS_NORMAL:', '      Exit(S_OK);',
    '  end;', '  Result := Trampoline(hTheme, iPartId, iStateId);', 'end;',
    'end.']);
  R := CaseLock(Src, 6);
  Assert.IsTrue(Pos('iStateId', R) > 0, R);
  Assert.IsTrue(Pos('integer', R) > 0, R);
  // Das Ergebnis traegt denselben Grund (nie Gluehbirne).
  Assert.AreEqual(R, CaseMenu(Src, 6));
  // doublecmd ufileview.pas:997: 'var Key: Word', VK_BACK aus LCLType.
  Src := Join(['unit u;', 'interface', 'implementation',
    'procedure TFileView.DoHandleKeyDownWhenLoading(var Key: Word; '
    + 'Shift: TShiftState);', 'begin', '  case Key of', '    VK_BACK:',
    '      begin', '        ChangePathToParent(True);', '        Key := 0;',
    '      end;', '  end;', 'end;', 'end.']);
  R := CaseLock(Src, 6);
  Assert.IsTrue(Pos('word', R) > 0, R);
  // HeidiSQL Vcl.Styles.Hooks.pas:446: eine Umwandlung als Selektor.
  R := CaseLock(InProc(['  case NativeUInt(lpIconName) of', '    78:',
    '      DrawIcon(1);', '    81:', '      DrawIcon(2);', '  end;']), 5);
  Assert.IsTrue(Pos('NativeUInt(lpIconName)', R) > 0, R);
  // jvcl cbDSMixer.pas:1488: Msg.Msg in einer WndProc (Konstante nicht in
  // der Datei).
  Src := Join(['unit u;', 'interface', 'implementation',
    'procedure TC.WndProc(var Msg: TMessage);', 'begin', '  case Msg.Msg of',
    '    WM_TRIGGER_X:', '      DoIt;', '  end;', 'end;', 'end.']);
  R := CaseLock(Src, 6);
  Assert.IsTrue(Pos('Msg.Msg', R) > 0, R);
  Assert.IsTrue(Pos('cardinal', R) > 0, R);
  // Gegenprobe: ein Parameter mit Aufzaehlungstyp, jeder Wert hat einen
  // Arm - keine Sperre, Gluehbirne.
  Src := StringReplace(WithTypes(['  TKind = (kA, kB);'], ['  case K of',
    '    kA: A;', '    kB: B;', '  end;']), 'procedure P;',
    'procedure P(K: TKind);', []);
  Assert.AreEqual('', CaseLock(Src, 8), 'Aufzaehlung');
  Assert.AreEqual('', CaseMenu(Src, 8), 'Gluehbirne');
  // Gegenprobe: ein Selektor ohne Typbeweis sperrt nicht.
  Assert.AreEqual('', CaseLock(InProc(['  case Obj.Kind of', '    kA: A;',
    '  end;']), 5), 'ohne Beweis');
end;

procedure TTestRdxStructFixes.Sca168_RaiseLock_ConstOrNumberLabels;
var
  R, Src : string;
begin
  // jvcl cbDSMixer.pas:331/1488 (minimiert): die Marke ist eine Integer-
  // Konstante der Datei ('WM_USER + 1') - bis rwE32 "die Aufzaehlung von
  // conWMUSER_ENDPLAY" im Menue (rot ohne Fix).
  Src := Join(['unit u;', 'interface', 'const',
    '  conWMUSER_ENDPLAY = WM_USER + 1;', '  conWMUSER_ENDFADE = WM_USER + 2;',
    'implementation', 'procedure P;', 'begin', '  case Ev.Code of',
    '    conWMUSER_ENDPLAY: A;', '    conWMUSER_ENDFADE: B;', '  end;', 'end;',
    'end.']);
  R := CaseLock(Src, 9);
  Assert.IsTrue(Pos('conWMUSER_ENDPLAY', R) > 0, R);
  Assert.IsTrue(Pos('4', R) > 0, 'Zeile: ' + R);
  // HeidiSQL main.pas:76/14530: Klassenkonstanten, qualifiziert.
  Src := Join(['unit u;', 'interface', 'type', '  TQueryTab = class(TObject)',
    '  public', '    const', '      HelperNodeColumns = 0;',
    '      HelperNodeHistory = 1;', '  end;', 'implementation', 'procedure P;',
    'begin', '  case Node.Index of', '    TQueryTab.HelperNodeColumns: A;',
    '    TQueryTab.HelperNodeHistory: B;', '  end;', 'end;', 'end.']);
  R := CaseLock(Src, 13);
  Assert.IsTrue(Pos('HelperNodeColumns', R) > 0, R);
  // CEF4Delphi uHelperProcessDom.pas:15/101: eine String-Konstante.
  Src := Join(['unit u;', 'interface', 'const',
    '  MSG_REQUEST_DOM = ''MSG_REQUEST_DOM'';', 'implementation', 'procedure P;',
    'begin', '  case message.Name of', '    MSG_REQUEST_DOM: A;', '  end;',
    'end;', 'end.']);
  Assert.IsTrue(Pos('MSG_REQUEST_DOM', CaseLock(Src, 8)) > 0, 'String');
  // Dev-Cpp main.pas:3822, HeidiSQL main.pas:14255: Zahlen als Marken.
  R := CaseLock(InProc(['  case MessageControl.ActivePageIndex of',
    '    2: LogOutput.SelectAll;', '    3: EvaluateInput.SelectAll;',
    '  end;']), 5);
  Assert.AreNotEqual('', R, 'Zahlen');
  Assert.AreNotEqual('', CaseLock(InProc(['  case GetACP of',
    '    437: R := ''cp850'';', '  end;']), 5), 'GetACP');
  // Ganzzahl-Konstanten der RTL (Korpus: 'case MessageDlg(..) of mrYes').
  R := CaseLock(InProc(['  case MessageDlg(S, mtConfirmation, mbYesNo, 0) of',
    '    mrYes: Save;', '  end;']), 5);
  Assert.IsTrue(Pos('mrYes', R) > 0, R);
  // Gegenprobe: eine Konstante, die nur einen Namen nennt, kann ein
  // Aufzaehlungswert sein - keine Sperre.
  Src := Join(['unit u;', 'interface', 'const', '  cDefault = eA;',
    'implementation', 'procedure P;', 'begin', '  case E of', '    cDefault: A;',
    '  end;', 'end;', 'end.']);
  Assert.AreEqual('', CaseLock(Src, 8), 'Name als Wert');
  // Gegenprobe: ein Typ 'T = 1' ist keine Konstante (Abschnitt type).
  Src := Join(['unit u;', 'interface', 'type', '  TSmall = 1..5;',
    'implementation', 'procedure P;', 'begin', '  case E of', '    TSmall: A;',
    '  end;', 'end;', 'end.']);
  Assert.AreEqual('', CaseLock(Src, 8), 'Typ');
end;

procedure TTestRdxStructFixes.Sca168_RaiseLock_PresetResult;
var
  R, Src : string;
begin
  // issrc ISPP.IdentMan.pas:945/953 (minimiert): Result := TYPE_ERROR am
  // Anfang, das case im else-Zweig eines Arms - jeder andere Typ behaelt
  // den Fehlerwert. Bis rwE32 nur im Menue (rot ohne Fix).
  Src := InProc(['  Result := TYPE_ERROR;', '  P := Find(Name);',
    '  if P <> nil then', '    case P.IdentType of', '      itVariable:',
    '        if P.Dim > 0 then', '          Result := TYPE_ARRAY', '        else',
    '          case P.Typ of', '            evNull: Result := TYPE_NULL;',
    '            evInt: Result := TYPE_INTEGER', '          end;',
    '      itMacro: Result := TYPE_MACRO', '    end;']);
  R := CaseLock(Src, LineOf(Src, 'case P.Typ'));
  Assert.IsTrue(Pos('Result', R) > 0, R);
  Assert.IsTrue(Pos('5', R) > 0, 'Zeile: ' + R);
  // HeidiSQL main.pas:14676/14677: die Vorbelegung vor 'if .. then case'.
  Src := InProc(['  ChildCount := 0;', '  if Obj <> nil then case Obj.NodeType of',
    '    lntTable, lntView:', '      ChildCount := Columns.Count;', '  end;']);
  R := CaseLock(Src, 6);
  Assert.IsTrue(Pos('ChildCount', R) > 0, R);
  // Gegenprobe: die Zuweisung steht im then-Zweig daneben - sie erreicht
  // das case nicht.
  Src := InProc(['  if C then', '    Result := 0', '  else',
    '    case E of', '      eA: Result := 1;', '    end;']);
  Assert.AreEqual('', CaseLock(Src, 8), 'then-Zweig');
  // Gegenprobe: ein ganzer Block davor zaehlt nicht.
  Src := InProc(['  if C then', '  begin', '    Result := 0;', '  end;',
    '  case E of', '    eA: Result := 1;', '  end;']);
  Assert.AreEqual('', CaseLock(Src, 9), 'Block');
  // Gegenprobe: die Laufvariable eines Arms ist keine Ergebnis-Variable.
  Src := InProc(['  I := 0;', '  case E of',
    '    eA: for I := 0 to 3 do A;', '  end;']);
  Assert.AreEqual('', CaseLock(Src, 6), 'for-Variable');
  // Gegenprobe: jeder Wert der Aufzaehlung hat einen Arm - die Vorbelegung
  // aendert nichts, Gluehbirne.
  Src := WithTypes(['  TE = (eA, eB);'], ['  Result := 0;', '  case E of',
    '    eA: Result := 1;', '    eB: Result := 2;', '  end;']);
  Assert.AreEqual('', CaseLock(Src, 9), 'voll abgedeckt');
  Assert.AreEqual('', CaseMenu(Src, 9), 'Gluehbirne');
end;

procedure TTestRdxStructFixes.Sca168_RaiseMenu_NeighbourUnits;
var
  Root, Sub, Deep, U, R, Src : string;
begin
  // doublecmd src\frames\foptionsfileoperations.pas:126 (Aufzaehlung in
  // src\uglobs.pas, eine Ebene hoeher), src\filesources\shellfolder\
  // ushellfilesourceutil.pas:146 (src\ulog.pas, zwei Ebenen), HeidiSQL
  // dbconnection.pas:1677 (dbstructures.pas daneben): jeder Wert hat einen
  // Arm - raise ist unerreichbar. Bis rwE32 nur im Menue "nicht in dieser
  // Datei deklariert" (rot ohne Fix).
  Root := NewTempDir('rdx_sca168_');
  try
    Sub := Root + 'src' + PathDelim + 'frames' + PathDelim;
    Deep := Root + 'src' + PathDelim + 'fs' + PathDelim + 'shell' + PathDelim;
    ForceDirectories(Sub);
    ForceDirectories(Deep);
    WriteText(Root + 'src' + PathDelim + 'uglobs.pas', Join(['unit uGlobs;',
      'interface', 'type', '  TProgressKind = (pkSeparate, pkPanel, pkBoth);',
      '  TLogMsgType = (lmtInfo, lmtSuccess, lmtError);', 'const',
      '  wpLicense = 2;', 'implementation', 'type',
      '  THidden = (hA, hB);', 'end.']));
    WriteText(Sub + 'ustructs.pas', Join(['unit uStructs;', 'interface',
      'type', '  TNetGroup = (ngMySQL, ngMSSQL, ngPgSQL);', 'implementation',
      'end.']));
    // Eine Ebene hoeher, alle Werte.
    U := Sub + 'fopts.pas';
    Src := Join(['unit fOpts;', 'interface', 'implementation', 'uses uGlobs;',
      'procedure P;', 'begin', '  case gKind of', '    pkSeparate: A;',
      '    pkPanel: B;', '    pkBoth: C;', '  end;', 'end;', 'end.']);
    Assert.AreEqual('', CaseMenuLock(Src, 7, U, R), 'eine Ebene');
    Assert.AreEqual('', R);
    // Gegenprobe: ein Wert ohne Arm - Menue mit dem Wert.
    Src := StringReplace(Src, '    pkBoth: C;'#13#10, '', []);
    Assert.IsTrue(Pos('pkBoth', CaseMenuLock(Src, 7, U, R)) > 0, 'pkBoth');
    Assert.AreEqual('', R);
    // Daneben (gleiches Verzeichnis).
    Src := Join(['unit fOpts;', 'interface', 'uses uStructs;', 'implementation',
      'procedure P;', 'begin', '  case NetGroup of', '    ngMySQL: A;',
      '    ngMSSQL, ngPgSQL: B;', '  end;', 'end;', 'end.']);
    Assert.AreEqual('', CaseMenuLock(Src, 7, U, R), 'daneben');
    // Zwei Ebenen hoeher.
    Src := Join(['unit uShell;', 'interface', 'implementation', 'uses uGlobs;',
      'procedure P;', 'begin', '  case MsgType of', '    lmtInfo: A;',
      '    lmtSuccess: B;', '    lmtError: C;', '  end;', 'end;', 'end.']);
    Assert.AreEqual('', CaseMenuLock(Src, 7, Deep + 'ushell.pas', R),
      'zwei Ebenen');
    // Gegenprobe: ohne uses-Eintrag kein Beweis (neutraler Text).
    Assert.AreNotEqual('', CaseMenuLock(StringReplace(Src, 'uses uGlobs;',
      '', []), 7, Deep + 'ushell.pas', R), 'ohne uses');
    // Gegenprobe: im implementation-Teil der Nachbar-Unit - nicht sichtbar.
    Src := Join(['unit uX;', 'interface', 'implementation', 'uses uGlobs;',
      'procedure P;', 'begin', '  case H of', '    hA: A;', '    hB: B;',
      '  end;', 'end;', 'end.']);
    Assert.AreNotEqual('', CaseMenuLock(Src, 7, U, R), 'implementation-Teil');
    // issrc Setup.WizardForm.pas:2534: die Marke ist eine Konstante der
    // Unit daneben - gesperrt.
    Src := Join(['unit uX;', 'interface', 'implementation', 'uses uGlobs;',
      'procedure P;', 'begin', '  case CurPageID of', '    wpLicense: A;',
      '  end;', 'end;', 'end.']);
    CaseMenuLock(Src, 7, U, R);
    Assert.IsTrue(Pos('uGlobs', R) > 0, R);
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxStructFixes.Sca168_RaiseMenu_NeutralHint;
var
  R, Lock : string;
begin
  // HeidiSQL Vcl.Styles.UxTheme.pas:1181 (Rest ohne Typbeweis): eine Marke,
  // die weder die Datei noch eine Unit daneben deklariert - der Hinweis
  // nennt sie nicht mehr "Aufzaehlung" (bis rwE32 "die Aufzaehlung von
  // MBI_NORMAL ist nicht in dieser Datei deklariert" - MBI_NORMAL ist eine
  // Integer-Konstante der RTL). Nur im Menue, keine Sperre.
  R := CaseMenuLock(InProc(['  case Details.State of', '    MBI_NORMAL: A;',
    '  end;']), 5, '', Lock);
  Assert.AreEqual('', Lock);
  Assert.IsTrue(Pos('MBI_NORMAL', R) > 0, R);
  Assert.AreEqual(_('%s is declared neither in this file nor in a unit next to '
    + 'it - whether the values without an arm occur normally is not provable',
    ['MBI_NORMAL']), R);
end;

procedure TTestRdxStructFixes.Sca168_RaiseMenu_CastSelector;
var
  R, Src : string;
begin
  // doublecmd foptionshotkeys.pas:759 (minimiert): 'case THotKeySortOrder(
  // cbCommandSortOrder.ItemIndex) of' nennt jeden Wert - ItemIndex ist ohne
  // Auswahl aber -1, das else ist dort ein gewoehnlicher Weg. Bis zum
  // Review in der Gluehbirne (rot ohne Fix: '').
  Src := WithTypes(['  TKind = (kA, kB);'], ['  case TKind(Combo.ItemIndex) of',
    '    kA: A;', '    kB: B;', '  end;']);
  R := CaseMenu(Src, 8);
  Assert.IsTrue(Pos('TKind(Combo.ItemIndex)', R) > 0, R);
  Assert.AreEqual('', CaseLock(Src, 8), 'nur Menue, keine Sperre');
  // Ein Alias der Datei vor der Klammer ist ebenso eine Umwandlung.
  Src := WithTypes(['  TKind = (kA, kB);', '  TKindAlias = TKind;'],
    ['  case TKindAlias(Tag) of', '    kA: A;', '    kB: B;', '  end;']);
  Assert.IsTrue(Pos('TKindAlias(Tag)', CaseMenu(Src, 9)) > 0, 'Alias');
  // Gegenprobe: ein Funktionsaufruf liefert einen Wert des Typs -
  // Gluehbirne.
  Src := WithTypes(['  TKind = (kA, kB);'], ['  case KindOf(Obj) of',
    '    kA: A;', '    kB: B;', '  end;']);
  Assert.AreEqual('', CaseMenu(Src, 8), 'Funktion');
  // Gegenprobe: die Umwandlung eines Objekts, danach ein Feld - Gluehbirne.
  Src := WithTypes(['  TKind = (kA, kB);'], ['  case TItem(P).Kind of',
    '    kA: A;', '    kB: B;', '  end;']);
  Assert.AreEqual('', CaseMenu(Src, 8), 'Feld nach Umwandlung');
end;

// ---- SCA007, Fix-Runde 4 (rwE32) ----

procedure TTestRdxStructFixes.Sca007_ForeignIdent_Messages;
var
  Li  : Integer;
  Src : string;
begin
  // TabbedBrowser uMainForm.pas:7-18/69 (minimiert): WM_APP und TWMMove
  // kommen aus (Winapi.)Messages. Bis dahin nannte der Hinweis WM_APP
  // ("kann aus System.Variants kommen") - rot ohne Fix: 'WM_APP'.
  Src := Join(['unit uMainForm;', 'interface', 'uses',
    '  Windows, Messages, SysUtils, Variants, Classes;', 'const',
    '  CEFBROWSER_DESTROYTAB = WM_APP + $101;', 'type',
    '  TMainForm = class(TObject)', '  private',
    '    procedure WMMove(var aMessage: TWMMove); message WM_MOVE;', '  end;',
    'implementation', 'procedure TMainForm.WMMove(var aMessage: TWMMove);',
    'begin', '  if aMessage.Msg = WM_USER then Exit;', 'end;', 'end.']);
  Assert.AreEqual('WM_APP', Foreign(Src, [], Li), 'ohne Liste');
  Assert.AreEqual<Integer>(6, Li);
  Assert.AreEqual('', Foreign(Src,
    TRdxStructFixes.AlwaysNeededIdents('messages'), Li), 'Messages');
  Assert.AreEqual('', Foreign(Src,
    TRdxStructFixes.AlwaysNeededIdents('winapi.messages'), Li),
    'Winapi.Messages');
  // Gegenprobe: eine eigene Botschaft einer anderen Unit (keine
  // Praefix-Regel WM_*) bleibt ohne Quelle.
  Src := StringReplace(Src, 'WM_APP + $101', 'WM_CEFDESTROY + 1', []);
  Assert.AreEqual('WM_CEFDESTROY', Foreign(Src,
    TRdxStructFixes.AlwaysNeededIdents('messages'), Li), 'eigene Botschaft');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxStructFixes);

end.
