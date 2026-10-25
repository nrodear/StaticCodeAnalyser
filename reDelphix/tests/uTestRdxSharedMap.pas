unit uTestRdxSharedMap;

// Charge P5 (Performance): EINE Code-Sicht je Text und ein Plattenblick je
// Menueaufbau - reine Tempo-Umbauten, die Tests pinnen, dass sich nichts
// sonst bewegt.
//
// TTestRdxSharedMap: TRdxMappedLines traegt ihre Map, TRdxCodeMap.Acquire
// liefert sie allen Aufrufern (uRdxCodeMap, GETEILTE SICHT). Gleiche
// Ersetzungen und Gruende der Unterdrueck-Hilfen und gleiche Eintraege des
// Kontext-Laeufers mit geteilter Map wie mit frischer, je Zeile bzw. je
// Caret-Spalte einer Fixture mit Block-Kommentaren, mehrzeiligem String,
// Direktiven und Markern; die geteilte Map wird genau einmal gebaut und
// mit jeder Aenderung der Zeilen verworfen.
//
// TTestRdxDiskReasonCache: der Cache von TRdxMagicFixes.FileReason/
// IncludeReason (UseDiskCache) - ohne Cache sieht jeder Aufruf die Platte
// (wie bisher, alle anderen Tests), mit Cache der erste; Dateiart und
// Netzpfad laufen vor dem Cache; der Schluessel traegt Sprachmittel,
// Sprache und - fuer IncludeReason - die Map (TRdxCodeMap.Serial). Baeume unter TEMP\rdx_p5_<GUID>, die
// Unit drei Ebenen tiefer (wie uTestRdxMagicGuards).
//
// Ohne die Aenderung uebersetzt die Unit nicht (TRdxMappedLines, Acquire,
// TRdxDiskReasonCache fehlen). FPC-tauglich: laeuft in reDelphix.Test UND
// im FPC-Pruefstand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSharedMap = class
  public
    [Test] procedure Acquire_PlainLines_FreshEachTime;
    [Test] procedure Acquire_MappedLines_OneMap;
    [Test] procedure Release_KeepsHeldMap;
    [Test] procedure Serial_NewPerBuild;
    [Test] procedure Change_DropsMap;
    [Test] procedure BeginUpdate_DropsMapAtOnce;
    [Test] procedure SharedMap_EqualsFresh;
    [Test] procedure Suppress_SameAsFresh;
    [Test] procedure Suppress_AfterChange_SeesNewText;
    [Test] procedure Context_SameAsFresh;
  end;

  [TestFixture]
  TTestRdxDiskReasonCache = class
  public
    [Test] procedure NoCache_SeesEveryDiskChange;
    [Test] procedure Cache_KeepsFirstLook_UntilClear;
    [Test] procedure Cache_FirstLookEqualsUncached;
    [Test] procedure Cache_FpcAndNetworkGate_BeforeCache;
    [Test] procedure Cache_IncludeReason_PerMap;
    [Test] procedure Cache_LanguageInKey;
    [Test] procedure UseDiskCache_ReturnsPrevious;
    [Test] procedure Destroy_WhileActive_Unregisters;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uFindingActions,       // TEditorContext
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap, uRdxSuppress, uRdxContextRunner, uRdxMagicFixes,
  uRdxText,              // RdxLanguageOverride, SetRdxLanguageOverride
  uTestRdxTextKit;       // Join, TempName, NewTempDir, WriteText, RemoveTree

// ---- Fixture: alles, was die Code-Sicht unterscheidet ----

function FixtureSource: string;
begin
  Result := Join([
    'unit u;',
    '// noinspection-file TodoComment',
    'interface',
    '{ Block-Kommentar',
    '  ueber zwei Zeilen // kein Zeilenkommentar }',
    'uses SysUtils; // noinspection UnusedUses',
    'implementation',
    '(* Klammer-',
    '   Kommentar *)',
    'const',
    '  S = ''''''',
    '    mehrzeilig { kein Kommentar',
    '    '''''';',
    '  T = ''a // b'';',
    'procedure P;',
    'var',
    '  L: TStringList;',
    '  X, Y: Integer;',
    'begin',
    '  // noinspection MemoryLeak',
    '  L := TStringList.Create;',
    '  {$IFDEF DEBUG} X := 1; {$ENDIF}',
    '  if X > 300 then Y := 42;',
    '  // TODO: aufraeumen',
    '',
    '  L := TStringList.Create; // noinspection MemoryLeak, NilDeref',
    'end;',
    'end.']);
end;

function PlainOf(const AText: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Text := AText;
end;

function MappedOf(const AText: string): TRdxMappedLines;
begin
  Result := TRdxMappedLines.Create;
  Result.Text := AText;
end;

// Eine Ersetzung als Text - Bereich, Erwartung, neuer Text.
function EditText(const AEdit: TRdxEdit): string;
begin
  Result := Format('%s %d:%d-%d:%d %d %s [%s] -> [%s]', [AEdit.Span.Role,
    AEdit.Span.StartLine, AEdit.Span.StartCol, AEdit.Span.EndLine,
    AEdit.Span.EndCol, Ord(AEdit.Span.ValueType), AEdit.Span.Resolved,
    AEdit.Expected, AEdit.NewText]);
end;

// Ergebnis einer Unterdrueck-Hilfe als Text.
function SuppressText(AOk: Boolean; const AEdit: TRdxEdit;
  const AReason: string): string;
begin
  Result := BoolToStr(AOk, True) + ' ' + EditText(AEdit) + ' / ' + AReason;
end;

// Die Eintraege des Kontext-Laeufers als Text.
function OutcomesText(const AList: TArray<TRdxContextOutcome>): string;
var
  i, k : Integer;
begin
  Result := IntToStr(Length(AList));
  for i := 0 to High(AList) do
  begin
    Result := Result + Format(' | %d %s %s [%s] [%s] %s', [Ord(AList[i].Kind),
      BoolToStr(AList[i].Enabled, True), AList[i].Name, AList[i].Hint,
      AList[i].Reason, BoolToStr(AList[i].ChangesBehavior, True)]);
    for k := 0 to High(AList[i].Edits) do
      Result := Result + ' ' + EditText(AList[i].Edits[k]);
  end;
end;

// Gleiche Klassen, Kommentarspalten, Innen-Zeilen und Direktiven-Anfaenge.
procedure AssertSameMap(AExpected, AActual: TRdxCodeMap; const AWhat: string);
var
  Li, Co : Integer;
begin
  Assert.AreEqual<Integer>(AExpected.LineCount, AActual.LineCount,
    AWhat + ': Zeilen');
  for Li := 0 to AExpected.LineCount + 1 do
  begin
    Assert.AreEqual<Integer>(AExpected.LineCommentCol(Li),
      AActual.LineCommentCol(Li), Format('%s: //-Spalte Zeile %d', [AWhat, Li]));
    Assert.IsTrue(AExpected.StartsInside(Li) = AActual.StartsInside(Li),
      Format('%s: StartsInside Zeile %d', [AWhat, Li]));
    for Co := 0 to Length(AExpected.Raw(Li)) + 1 do
    begin
      Assert.AreEqual(string(AExpected.ClassAt(Li, Co)),
        string(AActual.ClassAt(Li, Co)),
        Format('%s: Klasse %d:%d', [AWhat, Li, Co]));
      Assert.IsTrue(AExpected.DirectiveStartsAt(Li, Co)
        = AActual.DirectiveStartsAt(Li, Co),
        Format('%s: Direktive %d:%d', [AWhat, Li, Co]));
    end;
  end;
end;

{ TTestRdxSharedMap }

procedure TTestRdxSharedMap.Acquire_PlainLines_FreshEachTime;
var
  SL     : TStringList;
  M1, M2 : TRdxCodeMap;
begin
  // Ohne TRdxMappedLines wie bisher: je Aufruf eine eigene Map.
  SL := PlainOf(FixtureSource);
  M1 := nil;
  M2 := nil;
  try
    M1 := TRdxCodeMap.Acquire(SL);
    M2 := TRdxCodeMap.Acquire(SL);
    Assert.IsTrue(M1 <> M2, 'zwei Maps');
    Assert.AreEqual<Integer>(SL.Count, M1.LineCount);
  finally
    TRdxCodeMap.Release(M2);
    TRdxCodeMap.Release(M1);
    SL.Free;
  end;
  Assert.IsTrue(M1 = nil, 'Release setzt nil');
end;

procedure TTestRdxSharedMap.Acquire_MappedLines_OneMap;
var
  ML     : TRdxMappedLines;
  M1, M2 : TRdxCodeMap;
begin
  ML := MappedOf(FixtureSource);
  try
    Assert.AreEqual<Integer>(0, ML.Builds, 'erst beim ersten Acquire');
    M1 := TRdxCodeMap.Acquire(ML);
    M2 := TRdxCodeMap.Acquire(ML);
    Assert.IsTrue(M1 = M2, 'dieselbe Map');
    Assert.IsTrue(M1 = ML.Map, 'die der Zeilen');
    Assert.AreEqual<Integer>(1, ML.Builds);
    TRdxCodeMap.Release(M1);
    TRdxCodeMap.Release(M2);
  finally
    ML.Free;   // gibt die Map mit frei
  end;
end;

procedure TTestRdxSharedMap.Release_KeepsHeldMap;
var
  ML   : TRdxMappedLines;
  M, N : TRdxCodeMap;
begin
  ML := MappedOf(FixtureSource);
  try
    M := TRdxCodeMap.Acquire(ML);
    N := M;
    TRdxCodeMap.Release(M);
    Assert.IsTrue(M = nil, 'Release setzt nil');
    // Die Map der Zeilen lebt weiter und ist dieselbe.
    Assert.IsTrue(N = ML.Map, 'nicht freigegeben');
    Assert.AreEqual<Integer>(ML.Count, N.LineCount);
    Assert.AreEqual<Integer>(1, ML.Builds);
    M := nil;
    TRdxCodeMap.Release(M);   // nil ist erlaubt
    Assert.IsTrue(M = nil);
  finally
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.Serial_NewPerBuild;
var
  SL     : TStringList;
  ML     : TRdxMappedLines;
  M1, M2 : TRdxCodeMap;
  S      : Int64;
begin
  // Je Aufbau eine neue Nummer - auch fuer denselben Text; die geteilte
  // Map behaelt ihre, bis die Zeilen sich aendern.
  SL := PlainOf(FixtureSource);
  ML := MappedOf(FixtureSource);
  M1 := TRdxCodeMap.Create(SL);
  M2 := TRdxCodeMap.Create(SL);
  try
    Assert.IsTrue(M1.Serial > 0);
    Assert.IsTrue(M2.Serial > M1.Serial, 'neue Nummer');
    S := ML.Map.Serial;
    Assert.IsTrue(S > M2.Serial);
    Assert.IsTrue(TRdxCodeMap.Acquire(ML).Serial = S, 'geteilt: dieselbe');
    ML.Add('');
    Assert.IsTrue(ML.Map.Serial > S, 'nach Aenderung neu');
  finally
    M2.Free;
    M1.Free;
    ML.Free;
    SL.Free;
  end;
end;

procedure TTestRdxSharedMap.Change_DropsMap;
const
  STEPS = 8;
var
  ML    : TRdxMappedLines;
  SL    : TStringList;
  Fresh : TRdxCodeMap;
  i     : Integer;
begin
  ML := MappedOf(FixtureSource);
  try
    for i := 1 to STEPS do
    begin
      ML.Map;   // gebaut
      case i of
        1: ML[3] := '{ jetzt offen';             // Put
        2: ML.Add('{ angehaengt');               // Add
        3: ML.Insert(0, '(* vorn');              // Insert
        4: ML.Delete(0);                         // Delete
        5: ML.Exchange(1, 2);                    // Exchange
        6: ML.Text := FixtureSource;             // Text
        7: ML.Clear;                             // Clear
        8: ML.Text := '  X := ''a'' // b';      // aus leer
      end;
      Assert.AreEqual<Integer>(i, ML.Builds, Format('Schritt %d: verworfen', [i]));
      SL := TStringList.Create;
      Fresh := nil;
      try
        SL.Assign(ML);
        Fresh := TRdxCodeMap.Create(SL);
        AssertSameMap(Fresh, ML.Map, Format('Schritt %d', [i]));
      finally
        Fresh.Free;
        SL.Free;
      end;
      Assert.AreEqual<Integer>(i + 1, ML.Builds,
        Format('Schritt %d: neu gebaut', [i]));
    end;
  finally
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.BeginUpdate_DropsMapAtOnce;
var
  ML : TRdxMappedLines;
begin
  // Changed kaeme erst mit EndUpdate - Changing verwirft schon vorher.
  ML := MappedOf(Join(['a;', 'b;']));
  try
    Assert.IsFalse(ML.Map.StartsInside(2));
    ML.BeginUpdate;
    try
      ML[0] := '{ a;';
      Assert.IsTrue(ML.Map.StartsInside(2), 'neue Map schon in BeginUpdate');
    finally
      ML.EndUpdate;
    end;
    Assert.IsTrue(ML.Map.StartsInside(2));
  finally
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.SharedMap_EqualsFresh;
var
  ML    : TRdxMappedLines;
  SL    : TStringList;
  Fresh : TRdxCodeMap;
begin
  ML := MappedOf(FixtureSource);
  SL := PlainOf(FixtureSource);
  Fresh := TRdxCodeMap.Create(SL);
  try
    AssertSameMap(Fresh, ML.Map, 'Fixture');
    // Gegenprobe der Fixture: sie traegt, was die Sicht unterscheidet.
    Assert.IsTrue(Fresh.StartsInside(5), 'Block-Kommentar');
    Assert.IsTrue(Fresh.StartsInside(12), 'mehrzeiliger String');
    Assert.AreEqual<Integer>(0, Fresh.LineCommentCol(5), '// im Kommentar');
    Assert.IsTrue(Fresh.DirectiveStartsAt(22, 3), '{$IFDEF}');
  finally
    Fresh.Free;
    SL.Free;
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.Suppress_SameAsFresh;
const
  KINDS: array[0..2] of string = ('MemoryLeak', 'TodoComment', 'NilDeref');
var
  ML       : TRdxMappedLines;
  SL       : TStringList;
  Li, k    : Integer;
  E1, E2   : TRdxEdit;
  R1, R2   : string;
  Ok1, Ok2 : Boolean;
  Offered  : Integer;
begin
  ML := MappedOf(FixtureSource);
  SL := PlainOf(FixtureSource);
  Offered := 0;
  try
    for k := Low(KINDS) to High(KINDS) do
    begin
      for Li := 0 to SL.Count + 1 do
      begin
        Ok1 := TRdxSuppress.LineMarker(SL, Li, KINDS[k], E1, R1);
        Ok2 := TRdxSuppress.LineMarker(ML, Li, KINDS[k], E2, R2);
        Assert.AreEqual(SuppressText(Ok1, E1, R1), SuppressText(Ok2, E2, R2),
          Format('LineMarker %s Zeile %d', [KINDS[k], Li]));
        if Ok1 then Inc(Offered);
        Ok1 := TRdxSuppress.RemoveMarker(SL, Li, E1, R1);
        Ok2 := TRdxSuppress.RemoveMarker(ML, Li, E2, R2);
        Assert.AreEqual(SuppressText(Ok1, E1, R1), SuppressText(Ok2, E2, R2),
          Format('RemoveMarker Zeile %d', [Li]));
      end;
      Ok1 := TRdxSuppress.FileMarker(SL, KINDS[k], E1, R1);
      Ok2 := TRdxSuppress.FileMarker(ML, KINDS[k], E2, R2);
      Assert.AreEqual(SuppressText(Ok1, E1, R1), SuppressText(Ok2, E2, R2),
        'FileMarker ' + KINDS[k]);
    end;
    Assert.IsTrue(Offered > 10, 'die Fixture bietet Marker an');
    // Alle Aufrufe auf EINER Map (bis Charge P5 je Aufruf eine).
    Assert.AreEqual<Integer>(1, ML.Builds);
  finally
    SL.Free;
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.Suppress_AfterChange_SeesNewText;
var
  ML     : TRdxMappedLines;
  SL     : TStringList;
  E1, E2 : TRdxEdit;
  R1, R2 : string;
  Line   : Integer;
begin
  // Eine Aenderung der Zeilen erreicht die naechste Hilfe: nach einem
  // offenen '{' darueber liegt die Fundzeile im Kommentar.
  ML := MappedOf(FixtureSource);
  SL := PlainOf(FixtureSource);
  try
    Line := 23;   // '  if X > 300 then Y := 42;'
    Assert.IsTrue(TRdxSuppress.LineMarker(ML, Line, 'MagicNumber', E2, R2), R2);
    ML[21] := '  { offen';
    SL[21] := '  { offen';
    Assert.IsFalse(TRdxSuppress.LineMarker(ML, Line, 'MagicNumber', E2, R2),
      'jetzt im Kommentar');
    TRdxSuppress.LineMarker(SL, Line, 'MagicNumber', E1, R1);
    Assert.AreEqual(R1, R2, 'wie mit frischer Map');
    Assert.AreEqual<Integer>(2, ML.Builds);
  finally
    SL.Free;
    ML.Free;
  end;
end;

procedure TTestRdxSharedMap.Context_SameAsFresh;
var
  ML      : TRdxMappedLines;
  SL      : TStringList;
  Li, Co  : Integer;
  F, A, B : string;
  Found   : Integer;
begin
  // Ein Dateiname ohne Verzeichnis auf der Platte: der Plattenblick findet
  // nichts (wie uTestRdxContextRunner.NoDiskFile).
  F := TempName('rdx_p5_', PathDelim) + 'u.pas';
  ML := MappedOf(FixtureSource);
  SL := PlainOf(FixtureSource);
  Found := 0;
  try
    for Li := 1 to SL.Count do
      for Co := 1 to Length(SL[Li - 1]) + 2 do
      begin
        A := OutcomesText(TRdxContextRunner.Run(SL,
          TEditorContext.At(F, Li, Co)));
        B := OutcomesText(TRdxContextRunner.Run(ML,
          TEditorContext.At(F, Li, Co)));
        Assert.AreEqual(A, B, Format('Caret %d:%d', [Li, Co]));
        if A <> '0' then Inc(Found);
      end;
    Assert.IsTrue(Found > 0, 'die Fixture hat Kandidaten');
    Assert.AreEqual<Integer>(1, ML.Builds);
  finally
    SL.Free;
    ML.Free;
  end;
end;

{ ---- TTestRdxDiskReasonCache ---- }

type
  // Root\a\b\c\u.pas - das Fenster von FileReason (c, b, a) bleibt im
  // eigenen Baum.
  TTree = record
    Root, A, B, C, U : string;
  end;

function NewTree: TTree;
begin
  Result.Root := NewTempDir('rdx_p5_');
  Result.A := Result.Root + 'a' + PathDelim;
  Result.B := Result.A + 'b' + PathDelim;
  Result.C := Result.B + 'c' + PathDelim;
  Result.U := Result.C + 'u.pas';
  ForceDirectories(Result.C);
end;

// Die Unit mit den Includes AIncs als Zeilen.
function UnitLines(const AIncs: array of string): TStringList;
var
  i : Integer;
begin
  Result := TStringList.Create;
  Result.Add('unit u;');
  for i := Low(AIncs) to High(AIncs) do
    Result.Add('{$I ' + AIncs[i] + '}');
  Result.Add('interface');
  Result.Add('implementation');
  Result.Add('end.');
end;

procedure TTestRdxDiskReasonCache.NoCache_SeesEveryDiskChange;
var
  T : TTree;
begin
  // Die Vorgabe (kein Cache) - wie bisher: jeder Aufruf sieht die Platte.
  Assert.IsTrue(TRdxMagicFixes.UseDiskCache(nil) = nil, 'kein Cache aktiv');
  T := NewTree;
  try
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst));
    WriteText(T.C + 'P.lpi', '<x/>');
    Assert.IsTrue(Pos('P.lpi', TRdxMagicFixes.FileReason(T.U,
      lfInlineConst)) > 0, 'neue Projektdatei gesehen');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxDiskReasonCache.Cache_KeepsFirstLook_UntilClear;
var
  T    : TTree;
  C    : TRdxDiskReasonCache;
  Prev : TRdxDiskReasonCache;
begin
  T := NewTree;
  C := TRdxDiskReasonCache.Create;
  Prev := TRdxMagicFixes.UseDiskCache(C);
  try
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst));
    Assert.AreEqual<Integer>(1, C.Count);
    WriteText(T.C + 'P.lpi', '<x/>');
    // Innerhalb der Charge gilt der erste Blick.
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst),
      'aus dem Cache');
    Assert.AreEqual<Integer>(1, C.Count);
    C.Clear;
    Assert.IsTrue(Pos('P.lpi', TRdxMagicFixes.FileReason(T.U,
      lfInlineConst)) > 0, 'nach Clear neu gesehen');
  finally
    TRdxMagicFixes.UseDiskCache(Prev);
    C.Free;
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxDiskReasonCache.Cache_FirstLookEqualsUncached;
const
  FILES: array[0..3] of string = ('', 'Old.dof', 'P.lpi', 'P.dproj');
var
  T        : TTree;
  C, Prev  : TRdxDiskReasonCache;
  i        : Integer;
  F        : TRdxLateFeature;
  Expected : string;
begin
  T := NewTree;
  C := TRdxDiskReasonCache.Create;
  try
    for i := Low(FILES) to High(FILES) do
    begin
      if FILES[i] = 'P.dproj' then
        WriteText(T.B + FILES[i], '<Project><PropertyGroup/></Project>')
      else if FILES[i] <> '' then
        WriteText(T.A + FILES[i], '[x]');
      for F := Low(TRdxLateFeature) to High(TRdxLateFeature) do
      begin
        Expected := TRdxMagicFixes.FileReason(T.U, F);
        Prev := TRdxMagicFixes.UseDiskCache(C);
        try
          C.Clear;
          Assert.AreEqual(Expected, TRdxMagicFixes.FileReason(T.U, F),
            Format('%s, Sprachmittel %d: erster Blick', [FILES[i], Ord(F)]));
          Assert.AreEqual(Expected, TRdxMagicFixes.FileReason(T.U, F),
            Format('%s, Sprachmittel %d: aus dem Cache', [FILES[i], Ord(F)]));
        finally
          TRdxMagicFixes.UseDiskCache(Prev);
        end;
      end;
      if FILES[i] = 'Old.dof' then
        DeleteFile(T.A + FILES[i]);
    end;
  finally
    C.Free;
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxDiskReasonCache.Cache_FpcAndNetworkGate_BeforeCache;
var
  C, Prev : TRdxDiskReasonCache;
  Net     : string;
  R       : string;
begin
  Net := PathDelim + PathDelim + 'rdx-p5-gibt-es-nicht' + PathDelim + 'share'
    + PathDelim + 'u.pas';
  C := TRdxDiskReasonCache.Create;
  Prev := TRdxMagicFixes.UseDiskCache(C);
  try
    R := TRdxMagicFixes.FileReason(Net, lfInlineConst);
    Assert.IsTrue(R <> '', 'Netzpfad gesperrt');
    Assert.AreEqual(R, TRdxMagicFixes.FileReason(Net, lfInlineConst));
    Assert.IsTrue(TRdxMagicFixes.FileReason('u.pp', lfInlineConst) <> '',
      'FPC-Datei gesperrt');
    Assert.AreEqual<Integer>(0, C.Count, 'beide vor dem Cache, kein Eintrag');
    TRdxMagicFixes.UseDiskCache(nil);
    Assert.AreEqual(R, TRdxMagicFixes.FileReason(Net, lfInlineConst),
      'derselbe Grund wie ohne Cache');
  finally
    TRdxMagicFixes.UseDiskCache(Prev);
    C.Free;
  end;
end;

procedure TTestRdxDiskReasonCache.Cache_IncludeReason_PerMap;
var
  T          : TTree;
  C, Prev    : TRdxDiskReasonCache;
  SA, SB     : TStringList;
  MA, MB     : TRdxCodeMap;
  RA, RB, R0 : string;
begin
  T := NewTree;
  SA := UnitLines(['a.inc']);
  SB := UnitLines(['b.inc']);
  MA := TRdxCodeMap.Create(SA);
  MB := TRdxCodeMap.Create(SB);
  C := TRdxDiskReasonCache.Create;
  try
    WriteText(T.C + 'a.inc', '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}');
    WriteText(T.C + 'b.inc', '{$DEFINE FAST}');
    RA := TRdxMagicFixes.IncludeReason(T.U, MA, lfInlineConst);
    RB := TRdxMagicFixes.IncludeReason(T.U, MB, lfInlineConst);
    Assert.IsTrue(Pos('a.inc', RA) > 0, RA);
    Assert.AreEqual('', RB);
    Prev := TRdxMagicFixes.UseDiskCache(C);
    try
      Assert.AreEqual(RA, TRdxMagicFixes.IncludeReason(T.U, MA, lfInlineConst));
      // Eine andere Map (andere Includes) ist ein eigener Eintrag.
      Assert.AreEqual(RB, TRdxMagicFixes.IncludeReason(T.U, MB, lfInlineConst));
      Assert.AreEqual<Integer>(2, C.Count);
      WriteText(T.C + 'a.inc', '{$DEFINE FAST}');
      Assert.AreEqual(RA, TRdxMagicFixes.IncludeReason(T.U, MA, lfInlineConst),
        'aus dem Cache');
      C.Clear;
      R0 := TRdxMagicFixes.IncludeReason(T.U, MA, lfInlineConst);
      Assert.AreEqual('', R0, 'nach Clear neu gelesen');
    finally
      TRdxMagicFixes.UseDiskCache(Prev);
    end;
  finally
    C.Free;
    MB.Free;
    MA.Free;
    SB.Free;
    SA.Free;
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxDiskReasonCache.Cache_LanguageInKey;
var
  T        : TTree;
  C, Prev  : TRdxDiskReasonCache;
  Old      : string;
  RDe, REn : string;
begin
  T := NewTree;
  C := TRdxDiskReasonCache.Create;
  Old := RdxLanguageOverride;
  try
    WriteText(T.C + 'P.lpi', '<x/>');
    SetRdxLanguageOverride('de');
    RDe := TRdxMagicFixes.FileReason(T.U, lfInlineConst);
    SetRdxLanguageOverride('en');
    REn := TRdxMagicFixes.FileReason(T.U, lfInlineConst);
    Assert.IsTrue(RDe <> REn, 'zwei Sprachen, zwei Texte');
    Prev := TRdxMagicFixes.UseDiskCache(C);
    try
      SetRdxLanguageOverride('de');
      Assert.AreEqual(RDe, TRdxMagicFixes.FileReason(T.U, lfInlineConst));
      SetRdxLanguageOverride('en');
      Assert.AreEqual(REn, TRdxMagicFixes.FileReason(T.U, lfInlineConst),
        'nicht der deutsche aus dem Cache');
      Assert.AreEqual<Integer>(2, C.Count);
    finally
      TRdxMagicFixes.UseDiskCache(Prev);
    end;
  finally
    SetRdxLanguageOverride(Old);
    C.Free;
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxDiskReasonCache.UseDiskCache_ReturnsPrevious;
var
  C1, C2, Prev : TRdxDiskReasonCache;
begin
  C1 := TRdxDiskReasonCache.Create;
  C2 := TRdxDiskReasonCache.Create;
  try
    Prev := TRdxMagicFixes.UseDiskCache(C1);
    Assert.IsTrue(Prev = nil, 'vorher keiner');
    Assert.IsTrue(TRdxMagicFixes.UseDiskCache(C2) = C1);
    Assert.IsTrue(TRdxMagicFixes.UseDiskCache(C1) = C2);
    Assert.IsTrue(TRdxMagicFixes.UseDiskCache(Prev) = C1);
    Assert.IsTrue(TRdxMagicFixes.UseDiskCache(nil) = nil, 'wiederhergestellt');
  finally
    TRdxMagicFixes.UseDiskCache(nil);
    C2.Free;
    C1.Free;
  end;
end;

procedure TTestRdxDiskReasonCache.Destroy_WhileActive_Unregisters;
var
  C : TRdxDiskReasonCache;
begin
  C := TRdxDiskReasonCache.Create;
  TRdxMagicFixes.UseDiskCache(C);
  C.Free;
  // Kein Zugriff auf freigegebenen Speicher: der Cache hat sich abgemeldet.
  Assert.IsTrue(TRdxMagicFixes.UseDiskCache(nil) = nil, 'abgemeldet');
  Assert.AreEqual('', TRdxMagicFixes.FileReason('', lfInlineConst));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSharedMap);
  TDUnitX.RegisterTestFixture(TTestRdxDiskReasonCache);

end.
