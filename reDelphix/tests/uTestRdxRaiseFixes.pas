unit uTestRdxRaiseFixes;

// Editorhilfen an Ausnahmen und leeren Rumpfen (uRdxRaiseFixes) auf Text -
// ohne Parser, ohne Detektor (laeuft in reDelphix.Test UND im FPC-
// Pruefstand):
//   SCA020 leerer Rumpf: Absichtskommentar bzw. raise ENotImplemented
//          (eigene Zeile, inline, lokale Variablen, Tabs; lokale Routine,
//          asm, constructor, nicht leer),
//   SCA120 'raise ' vor 'EFoo.Create(..)' (Arme, mehrzeilige Argumente;
//          Ausdruck, '.Free' dahinter, zwei auf der Zeile),
//   SCA122 'raise E;' -> 'raise;' (Handler mit Block, einzeilig; inneres
//          try, fremder Handler, anonyme Methode).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (Fixture 7, nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxRaiseFixes = class
  public
    [Test] procedure Sca020_IntentComment;
    [Test] procedure Sca020_RaiseNotImplemented;
    [Test] procedure Sca020_Refusals;
    [Test] procedure Sca120_MissingRaise;
    [Test] procedure Sca120_Refusals;
    [Test] procedure Sca122_ReRaise;
    [Test] procedure Sca122_Refusals;
    // Gegen-Review 2026-10-11: with, bedingter Ausdruck, zwei Koepfe auf
    // einer Zeile, Kommentar im Rumpf, Kopf ueber zwei Zeilen.
    [Test] procedure Review_Refusals;
    [Test] procedure Review_Forms;
    // Review R3, verpasst (Charge FC): 'E := ..' zwischen Handler und raise.
    [Test] procedure Sca122_BoundReassigned_Refused;
    // rwE29: raise ENotImplemented nicht in einen Haken (virtual/override,
    // per inherited bzw. vom Framework gerufen) und nicht in einen Callback.
    [Test] procedure Sca020_RaiseInHookOrCallback_Refused;
    // rwE29: ein Kommentar nennt das fehlende raise - der Autor kennt es.
    [Test] procedure Sca120_KnownMissingRaise_Refused;
    // rwE30: ein Kommentar ohne Inhalt ('//') bzw. eine Leerzeile im Rumpf
    // wird ersetzt statt zu sperren bzw. stehen zu bleiben.
    [Test] procedure Sca020_EmptyCommentOrBlankLine_Replaced;
    // rwE30: kein raise in einer Methode, die ein Interface implementieren
    // kann (Klasse mit Interface-Liste).
    [Test] procedure Sca020_RaiseInInterfaceMethod_Refused;
    // rwE30: kein raise in einem Callback fremden Codes (cdecl), in einer
    // als Wert uebergebenen Prozedur und in einem Setter.
    [Test] procedure Sca020_RaiseInValueCallbackOrSetter_Refused;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxRaiseFixes,
  uTestRdxTextKit;   // Join, Apply, InProc

type
  TRdxRaiseKind = (rkEmpty, rkMissing, rkReRaise);

const
  EMPTY_MSG = 'Method body is empty';

// ---- Helfer ----

// Die Hilfe AKind fuer Zeile ALine: neuer Text oder '' bei Ablehnung.
// AArg ist bei rkEmpty das Anweisungsformat ('' = Kommentar), sonst die
// Meldung.
function Fix(AKind: TRdxRaiseKind; const ASource: string; ALine: Integer;
  const AArg: string; out AReason: string): string;
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
    case AKind of
      rkEmpty:
        Ok := TRdxRaiseFixes.EmptyBody(Map, ALine, AArg, E, AReason);
      rkMissing:
        Ok := TRdxRaiseFixes.MissingRaise(Map, ALine, AArg, E, AReason);
    else
      Ok := TRdxRaiseFixes.ReRaise(Map, ALine, AArg, E, AReason);
    end;
    if Ok then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

function MissingMsg(const AType: string): string;
begin
  Result := Format('Exception %s.Create(...) is constructed but never raised',
    [AType]);
end;

function ReRaiseMsg(const AName: string): string;
begin
  Result := Format('Re-raise of bound variable "%s" loses the original stack '
    + 'trace - use bare `raise;` instead', [AName]);
end;

// Eine Unit, deren implementation ALines traegt (ab Zeile 4).
function InImpl(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// ---- SCA020 ----

procedure TTestRdxRaiseFixes.Sca020_IntentComment;
var
  R : string;
begin
  Assert.AreEqual(InImpl(['procedure TFoo.DoStuff;', 'begin',
      '  ' + INTENT_LINE, 'end;']),
    Fix(rkEmpty, InImpl(['procedure TFoo.DoStuff;', 'begin', 'end;']), 4, '', R), R);
  // Rumpf auf einer Zeile: der Kommentar inline.
  Assert.AreEqual(InImpl(['procedure P; begin ' + INTENT_INLINE + ' end;']),
    Fix(rkEmpty, InImpl(['procedure P; begin end;']), 4, '', R), R);
  // Lokale Variablen, class procedure, Tabs.
  Assert.AreEqual(InImpl(['class function TFoo.F(A: Integer): Integer;', 'var',
      '  X: Integer;', #9'begin', #9#9 + INTENT_LINE, #9'end;']),
    Fix(rkEmpty, InImpl(['class function TFoo.F(A: Integer): Integer;', 'var',
      '  X: Integer;', #9'begin', #9'end;']), 4, '', R), R);
  // Ein constructor darf den Kommentar bekommen.
  Assert.AreEqual(InImpl(['constructor TFoo.Create;', 'begin', '  ' + INTENT_LINE,
      'end;']),
    Fix(rkEmpty, InImpl(['constructor TFoo.Create;', 'begin', 'end;']), 4, '', R),
      R);
end;

procedure TTestRdxRaiseFixes.Sca020_RaiseNotImplemented;
var
  R : string;
begin
  Assert.AreEqual(InImpl(['procedure TFoo.DoStuff;', 'begin',
      '  raise ENotImplemented.Create(''TFoo.DoStuff'');', 'end;']),
    Fix(rkEmpty, InImpl(['procedure TFoo.DoStuff;', 'begin', 'end;']), 4,
      RAISE_NOT_IMPLEMENTED, R), R);
  Assert.AreEqual(InImpl(['procedure P; begin raise ENotImplemented.Create(''P''); '
      + 'end;']),
    Fix(rkEmpty, InImpl(['procedure P; begin end;']), 4, RAISE_NOT_IMPLEMENTED, R),
      R);
end;

procedure TTestRdxRaiseFixes.Sca020_Refusals;
var
  R : string;
begin
  // Lokale Routine zwischen Kopf und Rumpf.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', '  procedure Inner;',
    '  begin', '  end;', 'begin', 'end;']), 4, '', R));
  Assert.IsTrue(Pos('lokale Routine', R) > 0, R);
  // Kein raise in constructor/destructor.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['destructor TFoo.Destroy;', 'begin',
    'end;']), 4, RAISE_NOT_IMPLEMENTED, R));
  Assert.IsTrue(Pos('destructor', R) > 0, R);
  // asm-Rumpf; nicht leer; kein Kopf auf der Zeile.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'asm', 'end;']), 4, '',
    R));
  Assert.IsTrue(Pos('asm', R) > 0, R);
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin', '  X;', 'end;']),
    4, '', R));
  Assert.IsTrue(Pos('nicht leer', R) > 0, R);
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin', 'end;']), 5, '',
    R));
  Assert.IsTrue(Pos('kein Methodenkopf', R) > 0, R);
  // Hinter dem begin steht ein Kommentar ohne Absicht.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin //', 'end;']), 4,
    '', R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
end;

// ---- SCA120 ----

procedure TTestRdxRaiseFixes.Sca120_MissingRaise;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  raise EFoo.Create(''x'');']),
    Fix(rkMissing, InProc(['  EFoo.Create(''x'');']), 6, MissingMsg('EFoo'), R), R);
  // Im then-Zweig vor else, CreateFmt, Gross/klein wie im Code.
  Assert.AreEqual(InProc(['  if A then raise efoo.CreateFmt(''%d'', [1]) else B;']),
    Fix(rkMissing, InProc(['  if A then efoo.CreateFmt(''%d'', [1]) else B;']), 6,
      MissingMsg('EFoo'), R), R);
  // Argumente ueber zwei Zeilen; ohne Klammern.
  Assert.AreEqual(InProc(['  raise EFoo.Create(', '    ''x'');']),
    Fix(rkMissing, InProc(['  EFoo.Create(', '    ''x'');']), 6, MissingMsg('EFoo'),
      R), R);
  Assert.AreEqual(InProc(['  raise EFoo.Create;']),
    Fix(rkMissing, InProc(['  EFoo.Create;']), 6, MissingMsg('EFoo'), R), R);
end;

procedure TTestRdxRaiseFixes.Sca120_Refusals;
var
  R : string;
begin
  // Teil eines Ausdrucks bzw. mit '.Free' dahinter.
  Assert.AreEqual('', Fix(rkMissing, InProc(['  X := EFoo.Create(''x'');']), 6,
    MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('ganze Anweisung', R) > 0, R);
  Assert.AreEqual('', Fix(rkMissing, InProc(['  EFoo.Create(''x'').Free;']), 6,
    MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('ganze Anweisung', R) > 0, R);
  Assert.AreEqual('', Fix(rkMissing, InProc(['  EFoo.Create(''a''); '
    + 'EFoo.Create(''b'');']), 6, MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', Fix(rkMissing, InProc(['  X;']), 6, MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
end;

// ---- SCA122 ----

procedure TTestRdxRaiseFixes.Sca122_ReRaise;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  try', '    X;', '  except', '    on E: EFoo do',
      '    begin', '      Log(E.Message);', '      raise;', '    end;', '  end;']),
    Fix(rkReRaise, InProc(['  try', '    X;', '  except', '    on E: EFoo do',
      '    begin', '      Log(E.Message);', '      raise E;', '    end;', '  end;']),
      12, ReRaiseMsg('E'), R), R);
  // Einzeilig, qualifizierter Typ, Kommentar dahinter.
  Assert.AreEqual(InProc(['  try X; except on Ex: SysUtils.EFoo do raise; end; // x']),
    Fix(rkReRaise, InProc(['  try X; except on Ex: SysUtils.EFoo do raise Ex; end; '
      + '// x']), 6, ReRaiseMsg('Ex'), R), R);
  // Ein inneres try im try-Teil und ein ganzer Block davor zaehlen nicht.
  Assert.AreEqual(InProc(['  try X; except on E: EFoo do begin try Y; finally Z; '
      + 'end; if A then raise; end; end;']),
    Fix(rkReRaise, InProc(['  try X; except on E: EFoo do begin try Y; finally Z; '
      + 'end; if A then raise E; end; end;']), 6, ReRaiseMsg('E'), R), R);
end;

procedure TTestRdxRaiseFixes.Sca122_Refusals;
var
  R : string;
begin
  // Im except eines inneren try waere 'raise;' die innere Exception.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try', '    X;', '  except',
    '    on E: EFoo do', '      try', '        Y;', '      except',
    '        raise E;', '      end;', '  end;']), 13, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('inneren try', R) > 0, R);
  // Im Handler einer anderen Variablen.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do try Y; '
    + 'except on F: EBar do raise E; end; end;']), 6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('Handler von "F"', R) > 0, R);
  // In einer anonymen Methode.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do '
    + 'TThread.Queue(nil, procedure begin raise E; end); end;']), 6,
    ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('anonyme Methode', R) > 0, R);
  // 'raise E at Addr' ist kein blosses 'raise E'.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do '
    + 'raise E at A; end;']), 6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('raise E', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Review_Refusals;
var
  R : string;
begin
  // SCA122: 'with H do raise E' - E koennte H.E sein.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: Exception do '
    + 'with H do raise E; end;']), 6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('with', R) > 0, R);
  // SCA120: then-Zweig eines bedingten Ausdrucks (Delphi 13) - raise ist dort
  // kein Ausdruck.
  Assert.AreEqual('', Fix(rkMissing, InProc(['  Foo(if C then EFoo.Create(''a'') '
    + 'else nil);']), 6, MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('ganze Anweisung', R) > 0, R);
  // SCA120: nur die Create-Varianten des Detektors.
  Assert.AreEqual('', Fix(rkMissing, InProc(['  EFoo.CreateAndRaise(1);']), 6,
    MissingMsg('EFoo'), R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
  // SCA020: zwei Koepfe auf einer Zeile.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure TFoo.P1; begin end; '
    + 'procedure TFoo.P2; begin end;']), 4, '', R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  // SCA020: auskommentierter Code im Rumpf - beide Eintraege lehnen ab (der
  // Kommentar verdeckte SCA070, ein zweiter Lauf schriebe doppelt).
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin',
    '  //X := 1;', 'end;']), 4, '', R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin',
    '  ' + INTENT_LINE, 'end;']), 4, RAISE_NOT_IMPLEMENTED, R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // SCA020: kein raise im constructor.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['constructor TFoo.Create;', 'begin',
    'end;']), 4, RAISE_NOT_IMPLEMENTED, R));
  Assert.IsTrue(Pos('constructor', R) > 0, R);
  // SCA020: ein veralteter Fund auf einer Prozedurtyp-Zeile ist kein
  // Methodenkopf (IsRoutineHeadAfter; Review Woche G07-18 - bis dahin
  // 'lokale Routine zwischen Kopf und Rumpf').
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['type', '  TCb = procedure of object;',
    'procedure P;', 'begin', 'end;']), 5, '', R));
  Assert.IsTrue(Pos('kein Methodenkopf', R) > 0, R);
  // SCA122: ein veralteter Fund ohne Handler - die Suche erreicht den Kopf
  // der Routine (Review Woche G07-11 (2) - bis dahin 'anonyme Methode').
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  raise E;']), 6, ReRaiseMsg('E'),
    R));
  Assert.IsTrue(Pos('in dieser Routine', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Review_Forms;
var
  R : string;
begin
  // Kopf ueber zwei Zeilen: der Name endet am Zeilenende.
  Assert.AreEqual(InImpl(['procedure TFoo.Bar', '  (A: Integer);', 'begin',
      '  raise ENotImplemented.Create(''TFoo.Bar'');', 'end;']),
    Fix(rkEmpty, InImpl(['procedure TFoo.Bar', '  (A: Integer);', 'begin', 'end;']),
      4, RAISE_NOT_IMPLEMENTED, R), R);
  // Kopf und Rumpfbeginn auf einer Zeile: Einrueckung der Schlusszeile.
  Assert.AreEqual(InImpl(['procedure P; begin', '  ' + INTENT_LINE, 'end;']),
    Fix(rkEmpty, InImpl(['procedure P; begin', 'end;']), 4, '', R), R);
  // Ein Kopf hinter dem end der Routine davor.
  Assert.AreEqual(InImpl(['end; procedure P;', 'begin', '  ' + INTENT_LINE,
      'end;']),
    Fix(rkEmpty, InImpl(['end; procedure P;', 'begin', 'end;']), 4, '', R), R);
  // Ein Blockkommentar hinter dem Namen bleibt aus dem Text (Review Woche
  // G07-11 (3): bis dahin 'TFoo.Bar { alt }').
  Assert.AreEqual(InImpl(['procedure TFoo.Bar { alt }', '  (A: Integer);', 'begin',
      '  raise ENotImplemented.Create(''TFoo.Bar'');', 'end;']),
    Fix(rkEmpty, InImpl(['procedure TFoo.Bar { alt }', '  (A: Integer);', 'begin',
      'end;']), 4, RAISE_NOT_IMPLEMENTED, R), R);
end;

procedure TTestRdxRaiseFixes.Sca122_BoundReassigned_Refused;
var
  R : string;
begin
  // Die Probe des Pruefers (onvar.pas, FPC 3.2.2 -Mdelphi): mit 'raise E'
  // kommt aussen 'ersetzt' an, mit 'raise;' 'innen' - eine andere
  // Exception, nicht nur ein anderer Stack-Trace. Bis Charge FC bot die
  // Hilfe 'raise;' an (bedeutungsgleich gekennzeichnet).
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try', '    X;', '  except',
    '    on E: Exception do', '    begin',
    '      E := Exception.Create(''ersetzt'');', '      raise E;', '    end;',
    '  end;']), 12, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('neu zugewiesen', R) > 0, R);
  // Auch in einem Block zwischen Handler und raise, Gross/klein egal.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do '
    + 'begin if A then begin e := EBar.Create(''x''); end; raise E; end; end;']),
    6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('neu zugewiesen', R) > 0, R);
  // Gegenprobe: ein Member von E oder ein gleichnamiges Feld eines anderen
  // Objekts aendert E nicht - die Hilfe bleibt.
  Assert.AreEqual(InProc(['  try X; except on E: EFoo do begin E.Message := '
      + '''x''; Self.E := nil; raise; end; end;']),
    Fix(rkReRaise, InProc(['  try X; except on E: EFoo do begin E.Message := '
      + '''x''; Self.E := nil; raise E; end; end;']), 6, ReRaiseMsg('E'), R), R);
  // Review Woche G07-19: E als ganzes Argument - ein var-Parameter kann es
  // ersetzen ('procedure Wrap(var AErr: Exception)'); bis dahin bot die
  // Hilfe 'raise;' als bedeutungsgleich an. Ein Member als Argument
  // ('Log(E.Message)', Sca122_ReRaise) bleibt erlaubt.
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do '
    + 'begin Wrap(E); raise E; end; end;']), 6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('als Argument', R) > 0, R);
  Assert.AreEqual('', Fix(rkReRaise, InProc(['  try X; except on E: EFoo do '
    + 'begin Replace(A, E, B); raise E; end; end;']), 6, ReRaiseMsg('E'), R));
  Assert.IsTrue(Pos('als Argument', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Sca020_RaiseInHookOrCallback_Refused;
var
  R, Src : string;
begin
  // doublecmd kascrypt dcpcrypt2.pas:307 (minimiert): TDCP_hash.Init ist
  // 'virtual' und leer, die Nachfahren rufen 'inherited Init;' - mit raise
  // scheiterte jedes Hashing. Ohne Fix angeboten (rot).
  Src := Join(['unit u;', 'interface', 'type', '  TDCP_hash = class',
    '    procedure Init; virtual;', '    procedure Burn;', '  end;',
    'implementation', 'procedure TDCP_hash.Init;', 'begin', 'end;',
    'procedure TDCP_hash.Burn;', 'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 9, RAISE_NOT_IMPLEMENTED, R), 'virtual');
  Assert.IsTrue(Pos('virtual', R) > 0, R);
  // Der Absichtskommentar bleibt (bedeutungsgleich).
  Assert.IsTrue(Fix(rkEmpty, Src, 9, '', R) <> '', R);
  // Gegenprobe: dieselbe Klasse, Methode ohne Direktive.
  Assert.IsTrue(Fix(rkEmpty, Src, 12, RAISE_NOT_IMPLEMENTED, R) <> '', R);
  // Ein leerer override schaltet den Vorfahren bewusst ab (cnwizards
  // LoadSettings, doublecmd Finalize).
  Src := Join(['unit u;', 'interface', 'type', '  TWiz = class(TBase)',
    '    procedure LoadSettings(Ini: TObject); override;', '  end;',
    'implementation', 'procedure TWiz.LoadSettings(Ini: TObject);', 'begin',
    'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 8, RAISE_NOT_IMPLEMENTED, R), 'override');
  Assert.IsTrue(Pos('override', R) > 0, R);
  // doublecmd multithreadprocslaz.pas:15 (minimiert): Register geht per
  // '@Register' an RegisterPackage - das raise braeche die Installation.
  Src := InImpl(['procedure Register;', 'begin', 'end;', 'initialization',
    '  RegisterPackage(''MultiThreadProcsLaz'', @Register);']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R), 'Callback');
  Assert.IsTrue(Pos('@Register', R) > 0, R);
  // Auch qualifiziert ('@Self.Bar').
  Src := InImpl(['procedure TFoo.Bar;', 'begin', 'end;',
    'procedure TFoo.Hook;', 'begin', '  SetHandler(@Self.Bar);', 'end;']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R),
    '@Self.Bar');
  Assert.IsTrue(Pos('@Bar', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Sca120_KnownMissingRaise_Refused;
var
  R : string;
begin
  // Indy IdHTTPWebBrokerBridge.pas:741 (minimiert): Arm eines Setters, der
  // Kommentar fragt nach dem raise - der eigene Konstruktor ruft den Setter,
  // mit raise scheiterte jede Antwort. Ohne Fix angeboten (rot).
  Assert.AreEqual('', Fix(rkMissing, InProc(['  case Index of',
    '    1: EFoo.Create(''x''); // shouldn''t this be calling ''raise''?',
    '    2: S := V;', '  end;']), 7, MissingMsg('EFoo'), R), 'Kommentar');
  Assert.IsTrue(Pos('raise', R) > 0, R);
  // Ebenso auf der Zeile darueber.
  Assert.AreEqual('', Fix(rkMissing, InProc(['  // no raise here: called while '
    + 'constructing', '  EFoo.Create(''x'');']), 7, MissingMsg('EFoo'), R),
    'Kommentar darueber');
  // Gegenprobe: 'raised' ist ein anderes Wort (Katalog: '// never raised!'),
  // 'raise' in einem String zaehlt nicht.
  Assert.AreEqual(InProc(['  raise EFoo.Create(''x''); // never raised!']),
    Fix(rkMissing, InProc(['  EFoo.Create(''x''); // never raised!']), 6,
      MissingMsg('EFoo'), R), R);
  Assert.AreEqual(InProc(['  raise EFoo.Create(''raise'');']),
    Fix(rkMissing, InProc(['  EFoo.Create(''raise'');']), 6, MissingMsg('EFoo'),
      R), R);
end;

procedure TTestRdxRaiseFixes.Sca020_EmptyCommentOrBlankLine_Replaced;
var
  R, Src : string;
begin
  // CEF4Delphi uCEFAccessibilityHandler.pas:80 (minimiert): im Rumpf nur
  // ein nacktes '//' - bis rwE30 gesperrt als 'auskommentierter Code
  // (SCA070)?' (rot ohne Fix). Die Zeile wird ersetzt.
  Src := InImpl(['procedure TCEFAccessibilityHandlerOwn.OnAccessibilityTreeChange'
    + '(const value: ICefValue);', 'begin', '  //', 'end;']);
  Assert.AreEqual(InImpl(['procedure TCEFAccessibilityHandlerOwn.'
      + 'OnAccessibilityTreeChange(const value: ICefValue);', 'begin',
      '  ' + INTENT_LINE, 'end;']), Fix(rkEmpty, Src, 4, '', R), R);
  // jcl StackTraceViewerHelloWorldExampleReg.pas:321: '//' in Spalte 1, die
  // neue Zeile eine Stufe unter dem end.
  Assert.AreEqual(InImpl(['procedure TTestLocationInfo.SetFileName(AValue: '
      + 'string);', 'begin', '  ' + INTENT_LINE, 'end;']),
    Fix(rkEmpty, InImpl(['procedure TTestLocationInfo.SetFileName(AValue: '
      + 'string);', 'begin', '//', 'end;']), 4, '', R), R);
  // Die raise-Variante bleibt beim leeren '//' gesperrt - es kann die Marke
  // "nichts zu tun" sein (HeidiSQL main.pas:4641) -, jetzt mit diesem Grund
  // statt 'SCA070?'; eine Leerzeile ersetzt sie.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin', '  //',
    'end;']), 4, RAISE_NOT_IMPLEMENTED, R), 'raise und //');
  Assert.IsTrue(Pos('SCA070', R) = 0, R);
  Assert.AreEqual(InImpl(['procedure P;', 'begin',
      '  raise ENotImplemented.Create(''P'');', 'end;']),
    Fix(rkEmpty, InImpl(['procedure P;', 'begin', '', 'end;']), 4,
      RAISE_NOT_IMPLEMENTED, R), R);
  // Leere Blockkommentare ebenso.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', '  ' + INTENT_LINE, 'end;']),
    Fix(rkEmpty, InImpl(['procedure P;', 'begin', '  { }', 'end;']), 4, '', R), R);
  // cnwizards CnWizIdeUtils.pas:1226 (minimiert): eine Leerzeile im Rumpf -
  // bis rwE30 kam der Kommentar hinter das begin, die Leerzeile blieb
  // darunter stehen (rot ohne Fix).
  Src := InImpl(['procedure TCnEditControlWrapper.AddEditorMouseMoveNotifier(',
    '  Notifier: TEditorMouseMoveNotifier);', 'begin', '', 'end;']);
  Assert.AreEqual(InImpl(['procedure TCnEditControlWrapper.'
      + 'AddEditorMouseMoveNotifier(', '  Notifier: TEditorMouseMoveNotifier);',
      'begin', '  ' + INTENT_LINE, 'end;']), Fix(rkEmpty, Src, 4, '', R), R);
  // Leerzeilen und '//' gemischt, eingerueckt (Tabs).
  Assert.AreEqual(InImpl(['procedure P;', #9'begin', #9#9 + INTENT_LINE,
      #9'end;']),
    Fix(rkEmpty, InImpl(['procedure P;', #9'begin', '', #9#9'//', '   ',
      #9'end;']), 4, '', R), R);
  // Gegenproben: ein Kommentar MIT Text bleibt gesperrt (SCA070?), eine
  // Direktive ebenso, ein '//' hinter dem begin ebenso.
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin', '  //',
    '  // X := 1;', 'end;']), 4, '', R));
  Assert.IsTrue(Pos('SCA070', R) > 0, R);
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin', '  {$R-}',
    'end;']), 4, '', R));
  Assert.IsTrue(Pos('SCA070', R) > 0, R);
  Assert.AreEqual('', Fix(rkEmpty, InImpl(['procedure P;', 'begin //', '',
    'end;']), 4, '', R));
  Assert.IsTrue(Pos('SCA070', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Sca020_RaiseInInterfaceMethod_Refused;
var
  R, Src : string;
begin
  // jvcl JvDynControlEngineJVCL.pas:1567 (minimiert): ControlSetOnClick
  // gehoert zu IJvDynControl (eine andere Unit), die Engine ruft es fuer
  // jedes Steuerelement - ohne Fix angeboten (rot).
  Src := Join(['unit u;', 'interface', 'type',
    '  TJvDynControlJVCLDateEdit = class(TJvDateTimePicker, IUnknown,',
    '    IJvDynControl, IJvDynControlData)', '  public',
    '    procedure ControlSetOnClick(Value: TNotifyEvent);', '  end;',
    'implementation',
    'procedure TJvDynControlJVCLDateEdit.ControlSetOnClick(Value: TNotifyEvent);',
    'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 10, RAISE_NOT_IMPLEMENTED, R), 'extern');
  Assert.IsTrue(Pos('IJvDynControl', R) > 0, R);
  // Der Absichtskommentar bleibt (bedeutungsgleich).
  Assert.IsTrue(Fix(rkEmpty, Src, 10, '', R) <> '', R);
  // skia4delphi Skia.Tests.Foundation.Runner.pas:370: unter protected,
  // ITestLogger aus DUnitX.
  Src := Join(['unit u;', 'interface', 'type',
    '  TAsyncTestRunner = class(TInterfacedObject, ITestLogger, IAsyncTestRunner)',
    '  protected', '    procedure OnEndSetupTest(const ATest: ITestInfo);',
    '  end;', 'implementation',
    'procedure TAsyncTestRunner.OnEndSetupTest(const ATest: ITestInfo);',
    'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 9, RAISE_NOT_IMPLEMENTED, R), 'skia');
  Assert.IsTrue(Pos('ITestLogger', R) > 0, R);
  // Das Interface steht in der Datei und deklariert die Methode - auch ueber
  // seinen Vorfahren.
  Src := Join(['unit u;', 'interface', 'type',
    '  IBase = interface', '    [''{8A3B2C10-0000-0000-0000-000000000001}'']',
    '    procedure Changed;', '  end;', '  INotify = interface(IBase)',
    '    procedure Other;', '  end;',
    '  TFoo = class(TInterfacedObject, INotify)', '    procedure Changed;',
    '    procedure Helper;', '  end;', 'implementation',
    'procedure TFoo.Changed;', 'begin', 'end;',
    'procedure TFoo.Helper;', 'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 16, RAISE_NOT_IMPLEMENTED, R), 'Vorfahr');
  Assert.IsTrue(Pos('INotify.Changed', R) > 0, R);
  // Gegenprobe: Helper steht in keinem Interface der Kette (alle in der
  // Datei, die Wurzel IInterface) - die Hilfe bleibt.
  Assert.IsTrue(Fix(rkEmpty, Src, 19, RAISE_NOT_IMPLEMENTED, R) <> '', R);
  // Eine Methodenzuordnung leitet ein Interface auf die Methode um.
  Src := Join(['unit u;', 'interface', 'type',
    '  IFoo = interface', '    procedure Bar;', '  end;',
    '  TFoo = class(TInterfacedObject, IFoo)',
    '    procedure IFoo.Bar = DoBar;', '    procedure DoBar;', '  end;',
    'implementation', 'procedure TFoo.DoBar;', 'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 12, RAISE_NOT_IMPLEMENTED, R), 'Zuordnung');
  Assert.IsTrue(Pos('DoBar', R) > 0, R);
  // Ein Interface-Vorfahr ausserhalb der Datei: nicht zu beweisen.
  Src := Join(['unit u;', 'interface', 'type',
    '  IMine = interface(IOTANotifier)', '    procedure Other;', '  end;',
    '  TFoo = class(TInterfacedObject, IMine)', '    procedure Modified;',
    '  end;', 'implementation', 'procedure TFoo.Modified;', 'begin', 'end;',
    'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 11, RAISE_NOT_IMPLEMENTED, R),
    'Vorfahr extern');
  Assert.IsTrue(Pos('IMine', R) > 0, R);
end;

procedure TTestRdxRaiseFixes.Sca020_RaiseInValueCallbackOrSetter_Refused;
var
  R, Src : string;
begin
  // mORMot2 mormot.db.sql.postgres.pas:494 (minimiert): ein cdecl-Callback
  // an libpq - ohne Fix angeboten (rot).
  Src := InImpl(['procedure DummyNoticeProcessor(arg: pointer; message: '
    + 'PUtf8Char); cdecl;', 'begin', 'end;']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R), 'cdecl');
  Assert.IsTrue(Pos('cdecl', R) > 0, R);
  Assert.IsTrue(Fix(rkEmpty, Src, 4, '', R) <> '', R);
  // mORMot2 mormot.orm.storage.pas:4483 (minimiert): DoNothingEvent geht
  // als Argument an SearchEvent (rot ohne Fix).
  Src := InImpl(['function TRestStorageInMemory.Count: integer;', 'begin',
    '  result := SearchEvent(FieldName, FieldValue, DoNothingEvent,',
    '    nil, 0, 0);', 'end;', '',
    'class procedure TRestStorageInMemory.DoNothingEvent(', '  aDest: pointer; '
    + 'aRec: TOrm; aIndex: integer);', 'begin', 'end;']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 10, RAISE_NOT_IMPLEMENTED, R), 'Argument');
  Assert.IsTrue(Pos('DoNothingEvent', R) > 0, R);
  Assert.IsTrue(Pos('6', R) > 0, R);
  // Indy IdFIPS.pas:169: Vorgabe einer Prozedurvariablen.
  Src := InImpl(['procedure DefUpdateHashInst(ACtx: TIdHashIntCtx);', 'begin',
    'end;', 'initialization', '  UpdateHashInst := DefUpdateHashInst;']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R),
    'Zuweisung');
  Assert.IsTrue(Pos('DefUpdateHashInst', R) > 0, R);
  // Gegenproben: als Anweisung aufgerufen (mit und ohne Klammern) - die
  // Hilfe bleibt. Eine Funktion als Wert sieht der Planer nicht (GRENZE).
  Src := InImpl(['procedure Init;', 'begin', 'end;', 'procedure Run;', 'begin',
    '  Init;', '  if X then Init else Init();', 'end;']);
  Assert.IsTrue(Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R) <> '', R);
  Src := InImpl(['function GetFoo: Integer;', 'begin', 'end;',
    'procedure Run;', 'begin', '  X := GetFoo;', 'end;']);
  Assert.IsTrue(Fix(rkEmpty, Src, 4, RAISE_NOT_IMPLEMENTED, R) <> '', R);
  // jvcl JvAppStorage.pas:1504 (minimiert): der leere Schreibzugriff einer
  // Eigenschaft ignoriert Zuweisungen mit Absicht.
  Src := Join(['unit u;', 'interface', 'type', '  TStore = class',
    '    procedure SetSubStorages(Value: TObject);',
    '    function GetName: string;',
    '    property SubStorages: TObject read FSub write SetSubStorages;',
    '    property Name: string read GetName;', '  end;', 'implementation',
    'procedure TStore.SetSubStorages(Value: TObject);', 'begin', 'end;',
    'function TStore.GetName: string;', 'begin', 'end;', 'end.']);
  Assert.AreEqual('', Fix(rkEmpty, Src, 11, RAISE_NOT_IMPLEMENTED, R), 'Setter');
  Assert.IsTrue(Pos('7', R) > 0, R);
  // Gegenprobe: ein leerer Lesezugriff liefert nichts - raise bleibt.
  Assert.IsTrue(Fix(rkEmpty, Src, 14, RAISE_NOT_IMPLEMENTED, R) <> '', R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRaiseFixes);

end.
