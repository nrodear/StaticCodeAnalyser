unit uTestRdxCleanupFixes;

// Quick-Fixes "Aufraeumen" (uRdxCleanupFixes, Charge H3a) auf Text - ohne
// Parser, ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA070 auskommentierten Code loeschen: '//'-Zeile, Kommentar hinter
//          Code, Inhaltszeilen eines Blockkommentars (Begrenzer nur bei
//          leerem Rest, Oeffner/Schliesser bleiben bei Prosa), mehrere
//          Kommentare, letzte Zeile der Datei; Sperren (Direktive, Doku,
//          Kopfkommentar, Absichts-/Unterdrueck-Marker, Code daneben,
//          Spalte mitten im Kommentar, Mehrzeilenstring, kein Code-Merkmal).
//   SCA053 ungenutzte Variable loeschen: Einzeldeklaration (mit '//'
//          dahinter), leer werdende Section samt var, Gruppen (erstes,
//          mittleres, letztes Element, ueber Zeilen), Inline-var; Sperren
//          (Verwendung auch unter {$IFDEF}/asm/lokaler Routine, for var,
//          resourcestring, const-Section, Initialisierer, absolute, record,
//          Attribut, Aufrufkonvention, with, Direktive, Kommentar, operator
//          Initialize, globale Variable).
//   CutEdit, der gemeinsame Baustein "loeschen und aufraeumen".
// Die Gegenprobe mit den echten Detektoren steht in uTestRdxCleanupDetector
// (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCleanupFixes = class
  public
    [Test] procedure Sca070_LineComment;
    [Test] procedure Sca070_CommentBehindCode;
    [Test] procedure Sca070_ContentLines_EmptyCommentGoes;
    [Test] procedure Sca070_ContentLines_ProseStays;
    [Test] procedure Sca070_OpenerOrCloserStays;
    [Test] procedure Sca070_SeveralComments;
    [Test] procedure Sca070_LastLineOfFile;
    [Test] procedure Sca070_KindRefusals;
    [Test] procedure Sca070_MarkerRefusals;
    [Test] procedure Sca070_StaleRefusals;
    [Test] procedure Sca053_SingleDeclaration;
    [Test] procedure Sca053_SectionBecomesEmpty;
    [Test] procedure Sca053_Groups;
    [Test] procedure Sca053_GroupsOverLines;
    [Test] procedure Sca053_InlineVar;
    [Test] procedure Sca053_UseRefusals;
    [Test] procedure Sca053_ShapeRefusals;
    [Test] procedure Sca053_ContextRefusals;
    [Test] procedure CutEdit_Lines;
    [Test] procedure CutEdit_InsideLines;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxCleanupFixes,
  uTestRdxTextKit;   // Join, Apply

type
  TCleanKind = (ckComment, ckVar);

// ---- Helfer ----

// Die Hilfe AKind fuer Zeile ALine: neuer Text oder '' bei Ablehnung
// (AReason).
function Fix(AKind: TCleanKind; const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if AKind = ckComment then
      Ok := TRdxCleanupFixes.CommentedOutCode(Map, ALine, AMessage, E, AReason)
    else
      Ok := TRdxCleanupFixes.UnusedLocalVar(Map, ALine, AMessage, E, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Keine Hilfe, und APart steht im Grund.
procedure AssertRefused(AKind: TCleanKind; const ASource: string;
  ALine: Integer; const AMessage, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(AKind, ASource, ALine, AMessage, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// Die Meldungen des Detektors uCommentedOutCode (Einzeiler / Block).
function OneMsg(ACol: Integer): string;
begin
  Result := Format('Comment at column %d looks like commented-out code - '
    + 'delete or extract into a TODO if still relevant.', [ACol]);
end;

function BlockMsg(ALines, ACol: Integer): string;
begin
  Result := Format('Commented-out code block of %d lines starting at column '
    + '%d - delete or extract into a TODO if still relevant.', [ALines, ACol]);
end;

// Die Meldung des Detektors uUnusedLocal.
function VarMsg(const AName: string): string;
begin
  Result := Format('Unused local variable: %s (declared but never read or '
    + 'written)', [AName]);
end;

// Eine Unit mit Routine P; ALines ist ihr Rumpf (ab Zeile 6).
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Eine Unit, deren implementation ALines traegt (ab Zeile 4).
function InImpl(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// CutEdit auf ASource: neuer Text oder '' bei Ablehnung.
function Cut(const ASource: string; AL1, AC1, AL2, AC2: Integer): string;
var
  SL     : TStringList;
  Map    : TRdxCodeMap;
  E      : TRdxEdit;
  Reason : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Reason := CutEdit(Map, TextPos(AL1, AC1), TextPos(AL2, AC2), 'test', E);
  finally
    Map.Free;
    SL.Free;
  end;
  Assert.AreEqual('', Reason, 'CutEdit');
  Result := Apply(ASource, E);
end;

// ---- SCA070 ----

procedure TTestRdxCleanupFixes.Sca070_LineComment;
var
  R : string;
begin
  // Die ganze Zeile samt Zeilenende, auch eingerueckt.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(ckComment, InProc(['  Foo;', '  // X := 1;', '  Bar;']), 7, OneMsg(3),
      R), R);
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(ckComment, InProc(['//Bar(1);', '  Foo;']), 6, OneMsg(1), R), R);
  // Zwei Zeilen einer Region ('//' und '{ }' - der Detektor fasst sie
  // zusammen).
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(ckComment, InProc(['  { X := 1; }', '  // Y := 2;', '  Foo;']), 6,
      BlockMsg(2, 3), R), R);
end;

procedure TTestRdxCleanupFixes.Sca070_CommentBehindCode;
var
  R : string;
begin
  // Ab der Spalte bis zum Zeilenende, der Leerraum davor geht mit.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(ckComment, InProc(['  Foo;   { X := 1; }', '  Bar;']), 6, OneMsg(10),
      R), R);
  // Der Kommentar reicht in die naechste Zeile, sein Rest ist leer: alles
  // bis hinter den Schliesser.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(ckComment, InProc(['  Foo; (* X := 1;', '  *)', '  Bar;']), 6,
      OneMsg(8), R), R);
  // Code hinter dem Schliesser auf der Folgezeile rueckt heran.
  Assert.AreEqual(InProc(['  Foo; Bar;']),
    Fix(ckComment, InProc(['  Foo; { X := 1;', '  } Bar;']), 6, OneMsg(8), R),
    R);
end;

procedure TTestRdxCleanupFixes.Sca070_ContentLines_EmptyCommentGoes;
var
  R : string;
begin
  // Der Fund zeigt auf die Inhaltszeilen (Spalte 1); danach ist der
  // Kommentar leer - die Begrenzerzeilen gehen mit.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(ckComment, InProc(['  Foo;', '  {', '    X := 1;', '    Y := 2;', '  }',
      '  Bar;']), 8, BlockMsg(2, 1), R), R);
  // Leerzeilen im leeren Rest gehen mit.
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(ckComment, InProc(['  (*', '', '    X := 1;', '', '  *)', '  Foo;']),
      8, OneMsg(1), R), R);
end;

procedure TTestRdxCleanupFixes.Sca070_ContentLines_ProseStays;
var
  R : string;
begin
  // Prosa vor und hinter der Region bleibt - nur die Region geht.
  Assert.AreEqual(InProc(['  { Alte Fassung:', '    noch offen }', '  Foo;']),
    Fix(ckComment, InProc(['  { Alte Fassung:', '    X := 1;', '    Y := 2;',
      '    noch offen }', '  Foo;']), 7, BlockMsg(2, 1), R), R);
  // Eine Leerzeile zwischen Oeffner und Region bleibt (der Bereich beginnt
  // nie hinter einem Zeilenende oder auf einer leeren Zeile).
  Assert.AreEqual(InProc(['(*', '', 'noch offen *)', '  Foo;']),
    Fix(ckComment, InProc(['(*', '', 'X := 1;', 'noch offen *)', '  Foo;']), 8,
      OneMsg(1), R), R);
end;

procedure TTestRdxCleanupFixes.Sca070_OpenerOrCloserStays;
var
  R : string;
begin
  // Der Kommentar beginnt an der Spalte und traegt hinter der Region
  // Prosa: der Oeffner bleibt.
  Assert.AreEqual(InProc(['  Foo; {', '  Prosa }', '  Bar;']),
    Fix(ckComment, InProc(['  Foo; { X := 1;', '  Prosa }', '  Bar;']), 6,
      OneMsg(8), R), R);
  // Prosa davor, die Region endet am Schliesser: er bleibt, eingerueckt
  // wie die Zeile.
  Assert.AreEqual(InProc(['  { Prosa', '    }', '  Bar;']),
    Fix(ckComment, InProc(['  { Prosa', '    X := 1; }', '  Bar;']), 7,
      OneMsg(1), R), R);
  // Steht der Schliesser allein auf seiner Zeile, bleibt die Zeile ganz.
  Assert.AreEqual(InProc(['  { Prosa', '  }', '  Bar;']),
    Fix(ckComment, InProc(['  { Prosa', '    X := 1;', '  }', '  Bar;']), 7,
      OneMsg(1), R), R);
end;

procedure TTestRdxCleanupFixes.Sca070_SeveralComments;
var
  R : string;
begin
  // Zwei Kommentare in einer Region: beide gehen.
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(ckComment, InProc(['  { X := 1; } (* Y := 2; *)', '  Foo;']), 6,
      OneMsg(3), R), R);
  // Der zweite reicht mit Prosa ueber die Region hinaus: kein
  // zusammenhaengender Schnitt.
  AssertRefused(ckComment, InProc(['  // X := 1;', '  { Y := 2;', '  Prosa }',
    '  Foo;']), 6, BlockMsg(2, 3), 'mehrere Kommentare');
end;

procedure TTestRdxCleanupFixes.Sca070_LastLineOfFile;
var
  R : string;
begin
  // Hinter 'end.' in der letzten Zeile: das Zeilenende davor geht mit.
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    Fix(ckComment, Join(['unit u;', 'interface', 'implementation', 'end.',
      '// X := 1;']), 5, OneMsg(1), R), R);
  // Mit Leerzeile davor und Zeilenende dahinter: die Leerzeile bleibt.
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.', '',
    '']),
    Fix(ckComment, Join(['unit u;', 'interface', 'implementation', 'end.', '',
      '// X := 1;', '']), 6, OneMsg(1), R), R);
end;

procedure TTestRdxCleanupFixes.Sca070_KindRefusals;
begin
  AssertRefused(ckComment, InProc(['  { Y := 2; } {$ENDIF}', '  Foo;']), 6,
    OneMsg(3), 'Direktive');
  AssertRefused(ckComment, InProc(['  Foo;', '  /// X := 1;', '  Bar;']), 7,
    OneMsg(3), 'Doku-Kommentar');
  AssertRefused(ckComment, InProc(['  {** X := 1; }', '  Foo;']), 6,
    OneMsg(3), 'Doku-Kommentar');
  // '{*' ist die Doku der CnPack-Quellen (Prosa mit Schluesselwoertern).
  AssertRefused(ckComment, InProc(['  Foo;',
    '  {* Liefert die function zu begin; }', '  Bar;']), 7, OneMsg(3),
    'Doku-Kommentar');
  // Vor dem ersten Code der Datei: Lizenz- oder Kopfkommentar.
  AssertRefused(ckComment, Join(['{ Beispiel:', '  X := 1;', '}', 'unit u;',
    'interface', 'implementation', 'end.']), 2, OneMsg(1), 'Kopfkommentar');
  // PasDoc '(**' (Review Woche G07-25: bis dahin nur '///', '{*', '{**').
  AssertRefused(ckComment, InProc(['  (** X := 1; *)', '  Foo;']), 6,
    OneMsg(3), 'Doku-Kommentar');
  // Ein Kommentar ohne Schliesser bis zum Dateiende.
  AssertRefused(ckComment, InProc(['  { X := 1;', '  Foo;']), 6, OneMsg(3),
    'Kommentar ohne Ende');
end;

procedure TTestRdxCleanupFixes.Sca070_MarkerRefusals;
begin
  AssertRefused(ckComment, InProc(['  { TODO: X := 1; }', '  Foo;']), 6,
    OneMsg(3), 'TODO im Bereich');
  AssertRefused(ckComment, InProc(['  { X := 1; // FixMe }', '  Foo;']), 6,
    OneMsg(3), 'FIXME im Bereich');
  AssertRefused(ckComment, InProc(['  { XXX X := 1; }', '  Foo;']), 6,
    OneMsg(3), 'XXX im Bereich');
  // Ein Unterdrueck-Marker als Brueckenzeile der Region.
  AssertRefused(ckComment, InProc(['  { X := 1; }', '  // noinspection All',
    '  { Y := 2; }', '  Foo;']), 6, BlockMsg(3, 3), 'noinspection');
end;

procedure TTestRdxCleanupFixes.Sca070_StaleRefusals;
begin
  // An der Spalte steht Code - Zeile verschoben.
  AssertRefused(ckComment, InProc(['  X := 1;', '  Foo;']), 6, OneMsg(3),
    'steht kein Kommentar');
  // Neben dem Kommentar steht Code.
  AssertRefused(ckComment, InProc(['  {X := 1;} Y := 2;']), 6, OneMsg(3),
    'neben dem Kommentar Code');
  // Die Spalte zeigt mitten in einen Kommentar der Zeile.
  AssertRefused(ckComment, InProc(['  { X := 1; }']), 6, OneMsg(5),
    'mitten in einen Kommentar');
  // Kein Code-Merkmal (Prosa) - der Fund meint andere Zeilen.
  AssertRefused(ckComment, InProc(['  // Prosa ohne Merkmal', '  Foo;']), 6,
    OneMsg(3), 'nicht nach Code');
  // Ein Delphi-12-Mehrzeilenstring ist kein Kommentar (der Detektor kennt
  // ihn nicht und meldet '{ ... }' darin).
  AssertRefused(ckComment, InProc(['  S := ''''''', '    { c = 1; }', '    ''''''',
    '  ;']), 7, OneMsg(5), 'steht kein Kommentar');
  // Review Woche G07-25 - die Zweige ohne Test bis dahin: eine Meldung ohne
  // Spalte bzw. Zeilenzahl, eine Region ueber das Dateiende hinaus, Code in
  // Backticks (Doku zitiert ihn - kein Merkmal, wie im Detektor) und die
  // LETZTE Zeile einer Region ohne Code-Merkmal.
  AssertRefused(ckComment, InProc(['  // X := 1;', '  Foo;']), 6,
    'kaputte Meldung', 'Spalte oder Zeilenzahl fehlt');
  AssertRefused(ckComment, InProc(['  // X := 1;', '  Foo;']), 6,
    BlockMsg(50, 3), 'der Fund reicht bis Zeile 55');
  AssertRefused(ckComment, InProc(['  // siehe `X := 1;` oben', '  Foo;']), 6,
    OneMsg(3), 'nicht nach Code');
  AssertRefused(ckComment, InProc(['  // X := 1;', '  // Prosa', '  Foo;']), 6,
    BlockMsg(2, 3), 'Zeile 7 sieht nicht nach Code aus');
end;

// ---- SCA053 ----

procedure TTestRdxCleanupFixes.Sca053_SingleDeclaration;
var
  R : string;
begin
  // Die Zeile geht, die Section bleibt (ein Eintrag davor und dahinter).
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;',
    '  B: string;', 'begin', '  A := Length(B);', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A: Integer;', '  X: TObject;',
      '  B: string;', 'begin', '  A := Length(B);', 'end;']), 7, VarMsg('X'),
      R), R);
  // Ein '//'-Kommentar hinter der allein stehenden Deklaration geht mit.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A: Integer;',
      '  X: Integer;   // Zaehler', 'begin', '  A := 1;', 'end;']), 7,
      VarMsg('X'), R), R);
  // Neben einer anderen Deklaration auf der Zeile: nur sie.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A: Integer; X: Integer;',
      'begin', '  A := 1;', 'end;']), 6, VarMsg('X'), R), R);
  // Ein Member gleichen Namens (hinter '.') ist keine Verwendung.
  Assert.AreEqual(InImpl(['procedure P(L: TList);', 'begin', '  L.Count := 1;',
    'end;']),
    Fix(ckVar, InImpl(['procedure P(L: TList);', 'var', '  Count: Integer;',
      'begin', '  L.Count := 1;', 'end;']), 6, VarMsg('Count'), R), R);
  // Ein with im Gueltigkeitsbereich sperrt nicht: kommt X nirgends vor, kann
  // with es nicht binden (die frueher vorhandene with-Sperre war wirkungslos).
  Assert.AreEqual(InImpl(['procedure P(L: TList);', 'begin', '  with L do',
    '    Clear;', 'end;']),
    Fix(ckVar, InImpl(['procedure P(L: TList);', 'var', '  X: Integer;',
      'begin', '  with L do', '    Clear;', 'end;']), 6, VarMsg('X'), R), R);
  // 'procedure of object' und 'class of' auf einer Zeile: kein Typ ueber
  // mehrere Zeilen (Review Woche G07-10 (a) - bis dahin abgelehnt).
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A: Integer;',
      '  Ev: procedure of object;', 'begin', '  A := 1;', 'end;']), 7,
      VarMsg('Ev'), R), R);
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A: Integer;',
      '  C: class of TObject;', 'begin', '  A := 1;', 'end;']), 7,
      VarMsg('C'), R), R);
end;

procedure TTestRdxCleanupFixes.Sca053_SectionBecomesEmpty;
var
  R : string;
begin
  // Katalogbeispiel: var und die Deklaration samt Kommentar.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', '  DoStuff;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  Tmp: Integer;   // never used',
      'begin', '  DoStuff;', 'end;']), 6, VarMsg('Tmp'), R), R);
  // 'var X: T;' auf einer Zeile.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var X: Integer;', 'begin', 'end;']), 5,
      VarMsg('X'), R), R);
  // 'var' hinter dem Kopf auf derselben Zeile: der Kopf bleibt.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', 'end;']),
    Fix(ckVar, InImpl(['procedure P; var', '  X: Integer;', 'begin', 'end;']), 5,
      VarMsg('X'), R), R);
  // Folgt noch ein Eintrag, bleibt var.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  Y: Integer;', 'begin',
    '  Y := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var X: Integer;', '  Y: Integer;',
      'begin', '  Y := 1;', 'end;']), 5, VarMsg('X'), R), R);
  // Ein weiterer Eintrag mit Attribut bzw. '&'-Namen dahinter: var bleibt
  // (MoreItems; Review Woche G07-25).
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  [Weak] Y: IFoo;', 'begin',
    '  Y := nil;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var X: Integer;', '  [Weak] Y: IFoo;',
      'begin', '  Y := nil;', 'end;']), 5, VarMsg('X'), R), R);
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  &Type: Integer;', 'begin',
    '  &Type := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var X: Integer;', '  &Type: Integer;',
      'begin', '  &Type := 1;', 'end;']), 5, VarMsg('X'), R), R);
end;

procedure TTestRdxCleanupFixes.Sca053_Groups;
var
  R : string;
begin
  // Erstes, mittleres, letztes Element.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  B, C: Integer;', 'begin',
    '  B := C;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  X, B, C: Integer;', 'begin',
      '  B := C;', 'end;']), 6, VarMsg('X'), R), R);
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A, C: Integer;', 'begin',
    '  A := C;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A, X, C: Integer;', 'begin',
      '  A := C;', 'end;']), 6, VarMsg('X'), R), R);
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A, B: Integer;', 'begin',
    '  A := B;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A, B, X: Integer;', 'begin',
      '  A := B;', 'end;']), 6, VarMsg('X'), R), R);
  // Ohne Leerzeichen geschrieben: der letzte Name ohne neues Leerzeichen.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A:Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A,X:Integer;', 'begin',
      '  A := 1;', 'end;']), 6, VarMsg('X'), R), R);
end;

procedure TTestRdxCleanupFixes.Sca053_GroupsOverLines;
var
  R : string;
begin
  // Der Name allein auf seiner Zeile (der Detektor meldet die Zeile des
  // ersten Namens): die Zeile geht.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A,', '  C: Integer;',
    'begin', '  A := C;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A,', '  X,', '  C: Integer;',
      'begin', '  A := C;', 'end;']), 6, VarMsg('X'), R), R);
  // Am Ende der Zeile: ab dem Komma davor.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A,', '  C: Integer;',
    'begin', '  A := C;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A, X,', '  C: Integer;',
      'begin', '  A := C;', 'end;']), 6, VarMsg('X'), R), R);
  // Der letzte Name auf der Folgezeile: das Komma der Zeile davor geht mit.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  A: Integer;', 'begin',
    '  A := 1;', 'end;']),
    Fix(ckVar, InImpl(['procedure P;', 'var', '  A,', '  X: Integer;', 'begin',
      '  A := 1;', 'end;']), 6, VarMsg('X'), R), R);
end;

procedure TTestRdxCleanupFixes.Sca053_InlineVar;
var
  R : string;
begin
  // Inline-Deklaration als ganze Anweisung.
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(ckVar, InProc(['  Foo;', '  var X: Integer;', '  Bar;']), 7,
      VarMsg('X'), R), R);
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(ckVar, InProc(['  var X: Integer;', '  Foo;']), 6, VarMsg('X'), R), R);
  // In einer Gruppe nur der Name.
  Assert.AreEqual(InProc(['  var A: Integer;', '  A := 1;']),
    Fix(ckVar, InProc(['  var A, X: Integer;', '  A := 1;']), 6, VarMsg('X'),
      R), R);
  // Einzige Anweisung des Blocks: es bliebe ein leerer Block.
  AssertRefused(ckVar, InProc(['  var X: Integer;']), 6, VarMsg('X'),
    'leerer Block');
  // Initialisierer.
  AssertRefused(ckVar, InProc(['  var X := Foo;', '  Bar;']), 6, VarMsg('X'),
    'Initialisierer');
end;

procedure TTestRdxCleanupFixes.Sca053_UseRefusals;
begin
  // Verwendung im Rumpf, in einer lokalen Routine, unter einer inaktiven
  // Direktive und in asm - die Code-Sicht liest alles als Code.
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer;', 'begin',
    '  X := 1;', 'end;']), 6, VarMsg('X'), 'noch vor');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer;',
    '  procedure Q;', '  begin', '    X := 1;', '  end;', 'begin', '  Q;',
    'end;']), 6, VarMsg('X'), 'noch vor');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer;', 'begin',
    '  {$IFDEF NEVER}', '  X := 1;', '  {$ENDIF}', 'end;']), 6, VarMsg('X'),
    'noch vor');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer;', 'begin',
    '  asm', '    MOV EAX, X', '  end;', 'end;']), 6, VarMsg('X'), 'noch vor');
  // Inline: Verwendung im Block.
  AssertRefused(ckVar, InProc(['  var X: Integer;', '  X := 1;']), 6,
    VarMsg('X'), 'noch vor');
end;

procedure TTestRdxCleanupFixes.Sca053_ShapeRefusals;
begin
  AssertRefused(ckVar, InProc(['  for var I := 1 to 3 do', '    Foo;']), 6,
    VarMsg('I'), 'for var');
  AssertRefused(ckVar, InImpl(['procedure P;', 'resourcestring',
    '  SX = ''x'';', 'begin', 'end;']), 5, VarMsg('resourcestring'),
    'Schluesselwort');
  AssertRefused(ckVar, InImpl(['procedure P;', 'const', '  C: Integer = 1;',
    '  X: Integer = 2;', 'begin', 'end;']), 7, VarMsg('X'), 'const-Section');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer = 2;',
    'begin', 'end;']), 6, VarMsg('X'), 'initialisierte Variable');
  AssertRefused(ckVar, InImpl(['procedure P(A: Integer);', 'var',
    '  X: Cardinal absolute A;', 'begin', 'end;']), 6, VarMsg('X'), 'absolute');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: record',
    '    A: Integer;', '  end;', 'begin', 'end;']), 6, VarMsg('X'),
    'mehrere Zeilen');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  [Weak] X: IFoo;',
    'begin', 'end;']), 6, VarMsg('X'), 'Attribut');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var',
    '  X: procedure(A: Integer);', '  stdcall;', 'begin', 'end;']), 6,
    VarMsg('X'), 'stdcall');
  // Review Woche G07-25: der Name zweimal auf der Zeile (der Name aus der
  // Meldung als Argument des Musters, G07-09), class var, ein Typ ohne ';'
  // bis zum Dateiende und eine Klammer ohne Gegenstueck.
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer; X: Integer;',
    'begin', 'end;']), 6, VarMsg('X'), 'Zeile 6 traegt 2-mal "x"');
  AssertRefused(ckVar, InImpl(['type', '  TFoo = class', '  class var X: Integer;',
    '  end;', 'procedure P;', 'begin', 'end;']), 6, VarMsg('X'), 'class var');
  AssertRefused(ckVar, Join(['unit u;', 'interface', 'implementation',
    'procedure P;', 'var', '  X: Integer']), 6, VarMsg('X'),
    'kein ";" hinter dem Typ');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer);', 'begin',
    'end;']), 6, VarMsg('X'), 'Klammer ohne Gegenstueck');
end;

procedure TTestRdxCleanupFixes.Sca053_ContextRefusals;
begin
  // Die Section liegt (teils) unter einer Direktive: ein Zweig koennte leer
  // werden.
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X: Integer;',
    '{$IFDEF A}', '  Y: Integer;', '{$ENDIF}', 'begin', 'end;']), 6,
    VarMsg('X'), 'Direktive');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  X {alt}: Integer;',
    '  Y: Integer;', 'begin', '  Y := 1;', 'end;']), 6, VarMsg('X'),
    'Kommentar in der Deklaration');
  AssertRefused(ckVar, InImpl(['type', '  TGuard = record',
    '    class operator Initialize(out R: TGuard);', '  end;', 'procedure P;',
    'var', '  X: TGuard;', 'begin', 'end;']), 10, VarMsg('X'),
    'Initialize/Finalize');
  AssertRefused(ckVar, InImpl(['var', '  X: Integer;']), 5, VarMsg('X'),
    'keine Routine');
  AssertRefused(ckVar, InImpl(['procedure P;', 'var', '  A: Integer;',
    'begin', 'end;']), 6, VarMsg('X'), 'Zeile verschoben');
  // Review Woche G07-25: ein FPC-Makro '{$DEFINEC M := X}' vor der Routine
  // (zweites Wort aus MACRO_WORDS - der Vorfilter je Zeile, G07-02, sucht
  // beide).
  AssertRefused(ckVar, InImpl(['{$DEFINEC M := X}', 'procedure P;', 'var',
    '  X: Integer;', 'begin', '  M;', 'end;']), 7, VarMsg('X'), 'Makro');
  // Review Woche G07-10 (b): ein lokaler Record mit Variantenteil vor der
  // var-Section - sein case hat kein eigenes end; die Hilfe lehnt ab, nennt
  // aber nicht mehr 'globale Variable?'.
  AssertRefused(ckVar, InImpl(['procedure P;', 'type',
    '  TR = record case B: Boolean of True: (A: Integer); end;', 'var',
    '  X: Integer;', 'begin', 'end;']), 8, VarMsg('X'), 'Variantenteil');
end;

// ---- CutEdit ----

procedure TTestRdxCleanupFixes.CutEdit_Lines;
begin
  // Ganze Zeilen; endet der Schnitt am Zeilenanfang, bleibt dessen Zeile.
  Assert.AreEqual(Join(['a', 'd']), Cut(Join(['a', '  b', '  c', 'd']), 2, 3, 3, 4));
  Assert.AreEqual(Join(['a', '  }', 'd']),
    Cut(Join(['a', '  b', '  }', 'd']), 2, 1, 3, 1));
  // Letzte Zeile: das Zeilenende davor; leere Zeilen davor bleiben.
  Assert.AreEqual(Join(['a', '']), Cut(Join(['a', '', 'x']), 3, 1, 3, 2));
  // Beginn hinter einem Zeilenende bzw. auf leerer Zeile: naechste Zeile.
  Assert.AreEqual(Join(['a{', '', 'c}']),
    Cut(Join(['a{', '', 'b', 'c}']), 1, 3, 3, 2));
end;

procedure TTestRdxCleanupFixes.CutEdit_InsideLines;
begin
  // Nur Leerraum davor: der Rest rueckt an die Einrueckung.
  Assert.AreEqual('  Foo;', Cut('  {x} Foo;', 1, 3, 1, 6));
  // Nur Leerraum dahinter: ab dem Ende des Codes.
  Assert.AreEqual('  Foo;', Cut('  Foo;  {x}  ', 1, 9, 1, 12));
  // Code auf beiden Seiten: ein Leerzeichen, wo eines stand oder zwei Token
  // verschmoelzen.
  Assert.AreEqual('begin end', Cut('begin{x}end', 1, 6, 1, 9));
  Assert.AreEqual('Foo; Bar;', Cut('Foo; {x} Bar;', 1, 6, 1, 9));
  Assert.AreEqual('( *P)', Cut('({x}*P)', 1, 2, 1, 5));
  Assert.AreEqual('A: T;', Cut('A, X: T;', 1, 2, 1, 5));
  Assert.AreEqual('Foo(a);', Cut('Foo(a{x});', 1, 6, 1, 9));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCleanupFixes);

end.
