unit uTestRdxSuppressCore;

// Die Unterdrueck-Hilfen (uRdxSuppress) gegen den ECHTEN Core - der Drift-
// Waechter zu uTestRdxSuppressTargets (Pruefer der Charge B1-FA,
// new_issue 4). uRdxSuppress bildet die Marker-Regeln von uSuppression nach
// (Ziele: naechste nicht-leere und naechste Code-Zeile; SCA165 nur ueber das
// Code-Ziel), und der FPC-Pruefstand prueft diese Nachbildung nur als
// ANNAHME. Hier laufen die Ergebnisse von LineMarker und RemoveMarker durch
// TSuppression - Marker einsammeln wie der Scan (CollectMarkersForScan),
// Funde filtern und wirkungslose Marker melden (ApplyToFindings) -, so wie
// uTestRdxCodeMap die Code-Sicht gegen ScanCodeLine haelt:
//   * LineMarker setzt einen Marker, der den Fund wirklich unterdrueckt -
//     auf einer Code-Zeile, auf einer Kommentarzeile, beim Erweitern ueber
//     eine Leerzeile (R1-03), und eine neue Zeile unter einem Marker einer
//     Code-Art hinter Code nimmt diesem nichts (Nachbesserung);
//   * RemoveMarker sperrt mit Kommentar-Ziel GENAU DANN, wenn der Core einen
//     Fund der Markerart auf einer Zeile hinter dem Marker unterdrueckt und
//     den Marker trotzdem als wirkungslos meldet (R1-01) - je Form;
//   * einen Marker einer Code-Art mit Warum-Kommentar, den der Core meldet,
//     entfernt die Hilfe, und kein Fund kommt zurueck (new_issue 1).
// Die Funde sind gesetzt, nicht von Detektoren gemeldet: geprueft wird die
// Unterdrueckung. Behebt eine Core-Charge den Fehlalarm (BuildMarkers wertet
// auch das Kommentar-Ziel als verbraucht), wird
// RemoveMarker_RefusesExactlyOnCoreFalseAlarm rot - dann entfaellt die
// Sperre in RemoveMarker (CommentTargetReason), und der Test dreht sich mit.
// Nur Delphi: uSuppression uebersetzt unter FPC 3.2 nicht (Inline-
// Variablen), der Pruefstand kennt diese Unit deshalb nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSuppressCore = class
  public
    [Test] procedure LineMarker_CodeLine_CoreSuppresses;
    [Test] procedure LineMarker_TodoLine_CoreSuppresses;
    [Test] procedure LineMarker_ExtendAcrossBlank_CoreKeepsBothKinds;
    [Test] procedure LineMarker_BelowTrailingCodeKind_CoreKeepsIt;
    [Test] procedure RemoveMarker_RefusesExactlyOnCoreFalseAlarm;
    [Test] procedure RemoveMarker_CodeKindWarum_NothingComesBack;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts,          // TFindingKind, TFindingKinds, TSuppressionMarker
  uMethodd12,          // TLeakFinding
  uSuppression,        // TSuppression
  uFileTextCache,      // gFileTextCache
  uRdxBufferMath,      // TRdxEdit
  uRdxSuppress,
  uTestRdxDetectorKit, // WriteTemp
  uTestRdxTextKit;     // Apply

const
  EOL  = #13#10;
  // Zeilen 1..6 jeder Fixture; die Faelle folgen ab Zeile 7.
  HEAD = 'unit u;' + EOL + 'interface' + EOL + 'implementation' + EOL
    + 'procedure P(var X: Integer);' + EOL + 'begin' + EOL + '  X := 0;' + EOL;
  TAIL = 'end;' + EOL + 'end.';
  TODO_LINE = '  // TODO: Grenzwert pruefen';

type
  // Ein Fund nach dem Filter des Cores.
  TFound = record
    Kind : TFindingKind;
    Line : Integer;
  end;

// HEAD + die Zeilen ab 7 (je mit EOL) + TAIL.
function Src(const ALines: array of string): string;
var
  L : TStringList;
  i : Integer;
begin
  L := TStringList.Create;
  try
    L.LineBreak := EOL;
    for i := 0 to High(ALines) do
      L.Add(ALines[i]);
    Result := HEAD + L.Text + TAIL;
  finally
    L.Free;
  end;
end;

// Der Core auf ASource: Datei schreiben, Marker einsammeln wie der Scan,
// die gesetzten Funde (AKinds[i] in Zeile ALines[i]) filtern. Ergebnis: was
// bleibt, samt der Meldungen wirkungsloser Marker (fkUnusedSuppression auf
// der Markerzeile). Ohne Profil-Gate (leere Artenmenge): jeder wirkungslose
// Marker wird gemeldet.
function CoreRun(const ASource: string; const AKinds: array of TFindingKind;
  const ALines: array of Integer): TArray<TFound>;
var
  Path     : string;
  Findings : TObjectList<TLeakFinding>;
  Pre      : TObjectDictionary<string, TList<TSuppressionMarker>>;
  Gate     : TFindingKinds;
  i        : Integer;
begin
  Assert.AreEqual<Integer>(Length(AKinds), Length(ALines), 'Arten und Zeilen');
  Path := WriteTemp('rdx_supcore_', ASource);
  Findings := nil;
  Pre := nil;
  try
    Findings := TObjectList<TLeakFinding>.Create(True);
    Pre := TObjectDictionary<string, TList<TSuppressionMarker>>.Create(
      [doOwnsValues]);
    for i := 0 to High(AKinds) do
      Findings.Add(TLeakFinding.New(Path, '', ALines[i], 'gesetzt', AKinds[i]));
    TSuppression.CollectMarkersForScan(Path, Pre);
    Gate := [];
    TSuppression.ApplyToFindings(Findings, Pre, @Gate);
    SetLength(Result, Findings.Count);
    for i := 0 to Findings.Count - 1 do
    begin
      Result[i].Kind := Findings[i].Kind;
      Result[i].Line := Findings[i].LineInt;
    end;
  finally
    Pre.Free;
    Findings.Free;
    if Assigned(gFileTextCache) then
      gFileTextCache.RemoveFile(Path);
    DeleteFile(Path);
  end;
end;

function Has(const AFound: TArray<TFound>; AKind: TFindingKind;
  ALine: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AFound) do
    if (AFound[i].Kind = AKind) and (AFound[i].Line = ALine) then
      Exit(True);
end;

// LineMarker fuer ALine von ASource: angeboten, liefert den neuen Text.
function LineMarked(const ASource: string; ALine: Integer;
  const AKind: string): string;
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Assert.IsTrue(TRdxSuppress.LineMarker(L, ALine, AKind, E, R), R);
    Result := Apply(ASource, E);
  finally
    L.Free;
  end;
end;

// RemoveMarker fuer AMarkerLine: True mit dem neuen Text, sonst False mit
// dem Grund.
function TryRemove(const ASource: string; AMarkerLine: Integer;
  out ANewSource, AReason: string): Boolean;
var
  L : TStringList;
  E : TRdxEdit;
begin
  ANewSource := '';
  L := TStringList.Create;
  try
    L.Text := ASource;
    Result := TRdxSuppress.RemoveMarker(L, AMarkerLine, E, AReason);
    if Result then
      ANewSource := Apply(ASource, E);
  finally
    L.Free;
  end;
end;

// Der Vertrag von R1-01 an einer Form mit einem TodoComment-Marker in
// AMarkerLine: RemoveMarker sperrt mit Kommentar-Ziel genau dann, wenn der
// Core einen TodoComment-Fund auf einer Zeile hinter dem Marker
// unterdrueckt und den Marker dabei als wirkungslos meldet (der Fehlalarm
// von SCA165, den die Sperre abfaengt).
procedure CheckShape(const AName, ASource: string; AMarkerLine: Integer);
var
  L          : TStringList;
  Count      : Integer;
  NewSource  : string;
  Reason     : string;
  Refused    : Boolean;
  AlarmLine  : Integer;
  Found      : TArray<TFound>;
  j          : Integer;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Count := L.Count;
  finally
    L.Free;
  end;
  Refused := not TryRemove(ASource, AMarkerLine, NewSource, Reason)
    and (Pos('Kommentarzeile', Reason) > 0);
  // Die erste Zeile, auf der der Core unterdrueckt UND den Marker meldet.
  AlarmLine := 0;
  for j := AMarkerLine + 1 to Count do
  begin
    Found := CoreRun(ASource, [fkTodoComment], [j]);
    if (AlarmLine = 0) and not Has(Found, fkTodoComment, j)
       and Has(Found, fkUnusedSuppression, AMarkerLine) then
      AlarmLine := j;
  end;
  Assert.IsTrue((AlarmLine > 0) = Refused, Format('%s: Core-Fehlalarm ueber '
    + 'Zeile %d (0 = keiner), RemoveMarker: %s', [AName, AlarmLine, Reason]));
end;

procedure TTestRdxSuppressCore.LineMarker_CodeLine_CoreSuppresses;
var
  S     : string;
  Found : TArray<TFound>;
begin
  S := LineMarked(Src(['  X := 2;']), 7, 'MagicNumber');
  Found := CoreRun(S, [fkMagicNumber], [8]);
  Assert.AreEqual<Integer>(0, Length(Found), 'unterdrueckt, Marker verbraucht');
end;

procedure TTestRdxSuppressCore.LineMarker_TodoLine_CoreSuppresses;
var
  S     : string;
  Found : TArray<TFound>;
begin
  // "Hier unterdruecken" auf einer TODO-Zeile wirkt ueber das Kommentar-
  // Ziel des Cores (dass er den Marker trotzdem meldet, prueft
  // RemoveMarker_RefusesExactlyOnCoreFalseAlarm).
  S := LineMarked(Src([TODO_LINE, '  X := 2;']), 7, 'TodoComment');
  Found := CoreRun(S, [fkTodoComment], [8]);
  Assert.IsFalse(Has(Found, fkTodoComment, 8), 'TODO-Fund unterdrueckt');
end;

procedure TTestRdxSuppressCore.LineMarker_ExtendAcrossBlank_CoreKeepsBothKinds;
var
  S     : string;
  Found : TArray<TFound>;
begin
  // R1-03 (Fixture sup_before des Pruefers): der Marker ueber der
  // Leerzeile traegt TodoComment der TODO-Zeile; "Hier unterdruecken" fuer
  // CommentedOutCode derselben Zeile erweitert ihn. Bis R1-03 kam eine
  // neue Zeile dazwischen, und der TodoComment-Fund kam zurueck.
  S := LineMarked(Src(['  // noinspection TodoComment', '',
    '  // TODO: X := X + 1; Inc(X); Foo(X);', '  X := 2;']), 9,
    'CommentedOutCode');
  Found := CoreRun(S, [fkTodoComment, fkCommentedOutCode], [9, 9]);
  Assert.IsFalse(Has(Found, fkTodoComment, 9), 'TodoComment bleibt unterdrueckt');
  Assert.IsFalse(Has(Found, fkCommentedOutCode, 9), 'CommentedOutCode unterdrueckt');
end;

procedure TTestRdxSuppressCore.LineMarker_BelowTrailingCodeKind_CoreKeepsIt;
var
  S     : string;
  Found : TArray<TFound>;
begin
  // Nachbesserung: ueber der Kommentarzeile ein Marker einer Code-Art
  // hinter Code - die neue Markerzeile (9) nimmt ihm nichts, sein Code-Ziel
  // bleibt die Code-Zeile (11). Dass der Core die neue Zeile selbst als
  // wirkungslos meldet, ist der Fehlalarm aus R1-01 (s. Kopf).
  S := LineMarked(Src(['  X := 1; // noinspection ExceptionTooGeneral', '',
    '  // TODO: X := 1;', '  X := 2;']), 9, 'CommentedOutCode');
  Found := CoreRun(S, [fkCommentedOutCode, fkExceptionTooGeneral], [10, 11]);
  Assert.IsFalse(Has(Found, fkCommentedOutCode, 10), 'Kommentarzeile unterdrueckt');
  Assert.IsFalse(Has(Found, fkExceptionTooGeneral, 11), 'Code-Zeile unterdrueckt');
  Assert.IsFalse(Has(Found, fkUnusedSuppression, 7),
    'der Marker hinter Code bleibt verbraucht');
end;

procedure TTestRdxSuppressCore.RemoveMarker_RefusesExactlyOnCoreFalseAlarm;
begin
  CheckShape('Kommentarzeile', Src(['  // noinspection TodoComment', TODO_LINE,
    '  X := 2;']), 7);
  CheckShape('ueber Leerzeile', Src(['  // noinspection TodoComment', '',
    TODO_LINE, '  X := 2;']), 7);
  CheckShape('{-Zeile', Src(['  // noinspection TodoComment',
    '  { TODO: Grenzwert pruefen }', '  X := 2;']), 7);
  CheckShape('hinter Code', Src(['  X := 1; // noinspection TodoComment',
    TODO_LINE, '  X := 2;']), 7);
  CheckShape('gestapelt', Src(['  // noinspection TodoComment',
    '  // noinspection CommentedOutCode', '  X := 2;']), 7);
  CheckShape('direkt ueber Code', Src(['  // noinspection TodoComment',
    '  X := 2;']), 7);
  CheckShape('Dateiende', 'unit u;' + EOL + 'end.' + EOL
    + '// noinspection TodoComment', 3);
end;

procedure TTestRdxSuppressCore.RemoveMarker_CodeKindWarum_NothingComesBack;
var
  S, S2  : string;
  Reason : string;
  Found  : TArray<TFound>;
begin
  // new_issue 1: Marker einer Code-Art, Warum-Kommentar, Code ohne Fund
  // dieser Art - der Core meldet den Marker (SCA165, echt). Die Hilfe
  // entfernt ihn; der Fund auf der Code-Zeile (MagicNumber, eine Zeile
  // hoeher) bleibt, wie er war, und nichts kommt dazu.
  S := Src(['  // noinspection ExceptionTooGeneral',
    '  // Aktionsgrenze: jeder Fehler geht als Meldung an den Aufrufer',
    '  X := 2;']);
  Found := CoreRun(S, [fkMagicNumber], [9]);
  Assert.IsTrue(Has(Found, fkUnusedSuppression, 7), 'der Core meldet den Marker');
  Assert.IsTrue(Has(Found, fkMagicNumber, 9), 'MagicNumber ist nicht betroffen');
  Assert.IsTrue(TryRemove(S, 7, S2, Reason), Reason);
  Found := CoreRun(S2, [fkMagicNumber], [8]);
  Assert.AreEqual<Integer>(1, Length(Found), 'nur der MagicNumber-Fund');
  Assert.IsTrue(Has(Found, fkMagicNumber, 8), 'MagicNumber, eine Zeile hoeher');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSuppressCore);

end.
