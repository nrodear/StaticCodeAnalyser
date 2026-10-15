unit uTestRdxMagicGuards;

// Nacharbeit des Gegen-Reviews der Charge Q14 (Charge SQc) am Quick-Fix
// SCA014 "Lokale Konstante einfuehren" (uRdxMagicFixes): alte Delphi-
// Projektdateien neben der Unit (Major 3 - .dof/.bdsproj/.bpr/.bpg, .dproj
// mit ProjectVersion < 18.5, das naechste Verzeichnis mit Delphi-Projekt
// entscheidet), Netzpfade (Verdacht e) und der Hauptblock eines Programms
// (Verdacht d, m22 des Pruefers). Ohne Parser und Detektor - laeuft in
// reDelphix.Test UND im FPC-Pruefstand. Jeder Test war gegen den Stand
// b1d16991 rot. Die Verzeichnisse liegen unter TEMP\rdx_sqc_<GUID>, die
// Unit drei Ebenen tiefer: das Fenster von FileReason (Verzeichnis der Unit
// und zwei darueber) bleibt im eigenen Baum, und eine fremde Projektdatei
// in TEMP kippt keinen Test (Gegen-Review Q14, Minor 14); jeder Test raeumt
// seinen Baum ab.
// Charge B1-FD (Code-Review reDelphix, Bereich R4; je gegen 4358b769 rot,
// Fixtures des Pruefers rc/r402.txt, rmain.txt, vunc.pas): Leerzeile
// zwischen Zweigzeile und Anweisung (R4-02 - die eine Ersetzung begann auf
// der Leerzeile, PlanByteEdits lehnte jeden Klick ab), 'End := 1' im
// Hauptblock (missed 3) und ein Include auf einem Netzpfad in einer
// lokalen Unit (R4-03 - ohne Plattenzugriff abgelehnt).
// Charge G9 (Entscheid E29): die Gruende folgen der reDelphix-Sprache,
// auch zusammengesetzte (Reasons_FollowRdxLanguage).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMagicGuards = class
  public
    [Test] procedure Disk_LegacyProjectFile_Refused;
    [Test] procedure Disk_DprojVersion_Threshold;
    [Test] procedure Disk_NearestDelphiProjectDecides;
    [Test] procedure Disk_LazarusBeforeDelphi;
    [Test] procedure Disk_NetworkPath_Refused;
    [Test] procedure MainBlock_ProgramAndLibrary_Refused;
    [Test] procedure Wrap_BlankLineBeforeStatement_Writes;
    [Test] procedure MainBlock_NamedEndArg_Refused;
    [Test] procedure Disk_IncludeOnNetworkPath_NoDiskAccess;
    [Test] procedure Reasons_FollowRdxLanguage;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxMagicFixes,
  uRdxText,          // SetRdxLanguageOverride, MsgByHand
  uTestRdxTextKit;   // Join, LineOf, WriteText, NewTempDir, RemoveTree

const
  MSG = 'Magic number "%s" in if condition - use a constant';
  DPROJ_FMT = '<?xml version="1.0" encoding="utf-8"?>' + #13#10
    + '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    + #13#10 + '  <PropertyGroup>' + #13#10
    + '    <ProjectVersion>%s</ProjectVersion>' + #13#10
    + '  </PropertyGroup>' + #13#10 + '</Project>';

// ---- Helfer ----

// Ein frischer Baum TEMP\rdx_sqc_<GUID>\ (mit Trenner).
function FreshRoot: string;
begin
  Result := NewTempDir('rdx_sqc_');
end;

// Der Baum fuer einen Test: Root\a\b\c\u.pas - C das Verzeichnis der Unit,
// B und A die beiden darueber, Root die dritte Ebene (nicht mehr im
// Fenster).
type
  TTree = record
    Root, A, B, C, U : string;
  end;

function NewTree: TTree;
begin
  Result.Root := FreshRoot;
  Result.A := Result.Root + 'a' + PathDelim;
  Result.B := Result.A + 'b' + PathDelim;
  Result.C := Result.B + 'c' + PathDelim;
  Result.U := Result.C + 'u.pas';
  ForceDirectories(Result.C);
end;

procedure WriteDproj(const APath, AVersion: string);
begin
  if AVersion = '' then
    WriteText(APath, '<Project><PropertyGroup/></Project>')
  else
    WriteText(APath, Format(DPROJ_FMT, [AVersion]));
end;

procedure AssertReason(const AFile, APart: string);
var
  R : string;
begin
  R := TRdxMagicFixes.FileReason(AFile);
  Assert.IsTrue(Pos(APart, R) > 0, APart + ' <> ' + R);
end;

// Der Plan fuer den Fund "AValue" auf der ersten Zeile mit AOnLine, gegen
// die UTF-8-Bytes von ASource geprueft und angewendet wie der Editor
// (PlanByteEdits, ApplyByteEdits): der neue Text. Bewusst nicht Apply aus
// uTestRdxTextKit: scheitert das Schreiben, meldet der Test 'Schreiben: '
// mit dem Grund - getrennt vom Scheitern des Planers ('Plan: ').
function FixText(const ASource, AOnLine, AValue: string): string;
var
  SL     : TStringList;
  Map    : TRdxCodeMap;
  Plan   : TRdxMagicPlan;
  Reason : string;
  Ok     : Boolean;
  Bytes  : TBytes;
  BPlan  : TArray<TRdxByteEdit>;
  Err    : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Ok := TRdxMagicFixes.MagicNumber(Map, LineOf(ASource, AOnLine),
      Format(MSG, [AValue]), Plan, Reason);
  finally
    Map.Free;
    SL.Free;
  end;
  Assert.IsTrue(Ok, 'Plan: ' + Reason);
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  // Erst das Ergebnis: die Meldung soll Err NACH dem Aufruf zeigen (die
  // Reihenfolge der Argumente ist nicht festgelegt).
  Ok := PlanByteEdits(Bytes, Plan.Edits, BPlan, Err);
  Assert.IsTrue(Ok, 'Schreiben: ' + Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, BPlan));
end;

// Der Planer fuer den Fund "AValue" auf der ersten Zeile mit AOnLine: ''
// mit Plan oder der Grund.
function PlanReason(const ASource, AOnLine, AValue: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Plan : TRdxMagicPlan;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if not TRdxMagicFixes.MagicNumber(Map, LineOf(ASource, AOnLine),
         Format(MSG, [AValue]), Plan, Result) then
      Assert.IsTrue(Result <> '', 'Grund fehlt');
  finally
    Map.Free;
    SL.Free;
  end;
end;

{ ---- Major 3: alte Delphi-Projekte ---- }

procedure TTestRdxMagicGuards.Disk_LegacyProjectFile_Refused;
const
  EXTS: array[0..3] of string = ('.dof', '.bdsproj', '.bpr', '.bpg');
var
  T   : TTree;
  Ext : string;
begin
  // CnWizards (.dof), JVCL, GExperts (GExpert3_bcb.bpr): ohne Weiche in der
  // Unit, die Version steht im Projekt - im Fenster bis zwei Ebenen.
  T := NewTree;
  try
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), 'leer');
    for Ext in EXTS do
    begin
      WriteText(T.C + 'Prj' + Ext, '[x]');
      AssertReason(T.U, 'alte Projektdatei Prj' + Ext);
      DeleteFile(T.C + 'Prj' + Ext);
    end;
    WriteText(T.A + 'Old.dof', '[x]');
    AssertReason(T.U, 'alte Projektdatei Old.dof');
    DeleteFile(T.A + 'Old.dof');
    // Drei Ebenen hoeher zaehlt nicht mehr.
    WriteText(T.Root + 'Far.dof', '[x]');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), 'drei Ebenen');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_DprojVersion_Threshold;
var
  T : TTree;
begin
  // JvChartDemo.dproj 12.3, SynGen.dproj 18.4 (10.2 Tokyo) - vor 10.3.
  T := NewTree;
  try
    WriteDproj(T.C + 'P.dproj', '18.4');
    AssertReason(T.U, 'Projekt P.dproj im Verzeichnis');
    AssertReason(T.U, 'ProjectVersion 18.4');
    WriteDproj(T.C + 'P.dproj', '18.5');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), '18.5 = 10.3');
    WriteDproj(T.C + 'P.dproj', '20.1');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), '20.1');
    // Die kleinste Version im Verzeichnis zaehlt.
    WriteDproj(T.C + 'Q.dproj', '12.3');
    AssertReason(T.U, 'Projekt Q.dproj im Verzeichnis');
    DeleteFile(T.C + 'Q.dproj');
    // Ohne lesbare Version (Delphi 2007 schrieb keine): alt.
    WriteDproj(T.C + 'P.dproj', '');
    AssertReason(T.U, 'ohne lesbare ProjectVersion');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_NearestDelphiProjectDecides;
var
  T : TTree;
begin
  T := NewTree;
  try
    // Eine .dproj ab 10.3 neben der Unit macht die alte Datei darueber
    // stumm ...
    WriteDproj(T.C + 'New.dproj', '19.5');
    WriteText(T.B + 'Old.dof', '[x]');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), 'naechstes Projekt neu');
    // ... und auch eine alte im selben Verzeichnis (die .dproj zaehlt).
    WriteText(T.C + 'Old.dof', '[x]');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), 'dproj vor dof');
    // Ohne Projekt neben der Unit entscheidet das darueber.
    DeleteFile(T.C + 'New.dproj');
    DeleteFile(T.C + 'Old.dof');
    AssertReason(T.U, 'alte Projektdatei Old.dof');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_LazarusBeforeDelphi;
var
  T : TTree;
begin
  // Ein Lazarus-Paket zwei Ebenen hoeher sperrt weiter, auch wenn neben der
  // Unit eine neue .dproj liegt (die Unit baut dann mit beiden).
  T := NewTree;
  try
    WriteDproj(T.C + 'New.dproj', '19.5');
    WriteText(T.A + 'pkg.lpk', '<?xml?>');
    AssertReason(T.U, 'Lazarus-Projekt/-Paket pkg.lpk');
    // Die alte .dproj neben der Unit sperrt ebenso - mit ihrem Grund.
    DeleteFile(T.A + 'pkg.lpk');
    WriteDproj(T.C + 'New.dproj', '15.4');
    AssertReason(T.U, 'ProjectVersion 15.4');
  finally
    RemoveTree(T.Root);
  end;
end;

{ ---- Verdacht e: Netzpfad ---- }

procedure TTestRdxMagicGuards.Disk_NetworkPath_Refused;
var
  Unc : string;
begin
  // Der Menueaufbau laeuft im Hauptthread - ein Netzpfad wird nicht
  // gelesen. Den Pfad setzt der Test aus Teilen zusammen (ein Pfad als
  // Literal waere ein SCA016-Fund im Selbstscan).
  Unc := PathDelim + PathDelim + 'rdx-sqc-gibt-es-nicht' + PathDelim + 'share'
    + PathDelim;
  AssertReason(Unc + 'src' + PathDelim + 'u.pas', 'Netzpfad');
  AssertReason(StringReplace(Unc, PathDelim, '/', [rfReplaceAll]) + 'u.pas',
    'Netzpfad');
  // Die Dateiart geht vor.
  AssertReason(Unc + 'u.pp', 'Lazarus-/FPC-Datei');
end;

{ ---- Verdacht d: Hauptblock ---- }

procedure TTestRdxMagicGuards.MainBlock_ProgramAndLibrary_Refused;
var
  R : string;
begin
  // m22 des Pruefers: im Hauptblock eines Programms bot die Hilfe an.
  R := PlanReason(Join(['program p;', 'begin', '  if ParamCount > 200 then Halt;',
    'end.']), 'ParamCount', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms (begin ab Zeile 2)', R) > 0, R);
  R := PlanReason(Join(['library l;', 'uses SysUtils;', 'begin', '  try',
    '    if X > 200 then Y;', '  finally', '  end;', 'end.']), 'X > 200', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms (begin ab Zeile 3)', R) > 0, R);
  // In einer Routine des Programms gilt die Inline-Konstante.
  Assert.AreEqual('', PlanReason(Join(['program p;', 'procedure Q;', 'begin',
    '  if ParamCount > 200 then Halt;', 'end;', 'begin', '  Q;', 'end.']),
    'ParamCount', '200'));
end;

{ ---- Charge B1-FD (Code-Review reDelphix, R4) ---- }

procedure TTestRdxMagicGuards.Wrap_BlankLineBeforeStatement_Writes;
const
  HEAD: array[0..4] of string = ('unit u;', 'interface', 'implementation',
    'procedure P(A: Boolean; X: Integer);', 'begin');
var
  Src, Want : string;
begin
  // R4-02, Pruefer-Fall r402 (1): zwischen Zweigzeile und Anweisung steht
  // eine Leerzeile. 'begin' kommt an ihren Anfang - die eine Ersetzung
  // begann dort, auf einer LEEREN Zeile (SpanFits), und jeder Klick
  // meldete "Menue neu oeffnen". Jetzt beginnt sie an der Zweigzeile.
  Src := Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], '  if A then', '',
    '    if X > 200 then Foo;', 'end;', 'end.']);
  Want := Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], '  if A then',
    '  begin', '', '    const MagicNr01 = 200;', '    if X > MagicNr01 then Foo;',
    '  end;', 'end;', 'end.']);
  Assert.AreEqual(Want, FixText(Src, 'X > 200', '200'), 'Leerzeile, CRLF');
  // r402 (2): LF, 'for var' als Zweig.
  Src := StringReplace(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4],
    '  for var I := 0 to 3 do', '', '    if X > 200 then Foo;', 'end;', 'end.']),
    #13#10, #10, [rfReplaceAll]);
  Want := StringReplace(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4],
    '  for var I := 0 to 3 do', '  begin', '', '    const MagicNr01 = 200;',
    '    if X > MagicNr01 then Foo;', '  end;', 'end;', 'end.']), #13#10, #10,
    [rfReplaceAll]);
  Assert.AreEqual(Want, FixText(Src, 'X > 200', '200'), 'Leerzeile, LF');
  // r402 (3): Leerzeile und Kommentarzeile davor; zwei Leerzeilen.
  Assert.AreEqual(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4],
      '  if A then', '  begin', '', '    // Grenze', '    const MagicNr01 = 200;',
      '    if X > MagicNr01 then Foo;', '  end;', 'end;', 'end.']),
    FixText(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], '  if A then',
      '', '    // Grenze', '    if X > 200 then Foo;', 'end;', 'end.']),
      'X > 200', '200'), 'Leer- und Kommentarzeile');
  Assert.AreEqual(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4],
      '  if A then', '  begin', '', '', '    const MagicNr01 = 200;',
      '    if X > MagicNr01 then Foo;', '  end;', 'end;', 'end.']),
    FixText(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], '  if A then',
      '', '', '    if X > 200 then Foo;', 'end;', 'end.']), 'X > 200', '200'),
    'zwei Leerzeilen');
  // Gegenprobe (r402 (4)): eine Zeile nur aus Leerzeichen ging schon vorher.
  Assert.AreEqual(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4],
      '  if A then', '  begin', '    ', '    const MagicNr01 = 200;',
      '    if X > MagicNr01 then Foo;', '  end;', 'end;', 'end.']),
    FixText(Join([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], '  if A then',
      '    ', '    if X > 200 then Foo;', 'end;', 'end.']), 'X > 200', '200'),
    'Leerzeichen-Zeile');
end;

procedure TTestRdxMagicGuards.MainBlock_NamedEndArg_Refused;
var
  R : string;
begin
  // missed 3, Pruefer-Fall rmain (1): 'End' als benanntes Argument im
  // Hauptblock - die end-Bilanz rueckwaerts zaehlte es als end und fand
  // den Hauptblock nicht; die Hilfe bot dort an.
  R := PlanReason(Join(['program p;', 'var', '  Doc: Variant;', '  X: Integer;',
    'begin', '  Doc.Range(Start := 0, End := 1);',
    '  if X > 200 then Writeln(''a'');', 'end.']), 'X > 200', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms (begin ab Zeile 5)', R) > 0, R);
  // 'Begin' als Name schloss die Bilanz zu frueh (Zeile 3 statt 2).
  R := PlanReason(Join(['library l;', 'begin', '  Foo(Begin := 1);',
    '  if X > 200 then Y;', 'end.']), 'X > 200', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms (begin ab Zeile 2)', R) > 0, R);
end;

procedure TTestRdxMagicGuards.Disk_IncludeOnNetworkPath_NoDiskAccess;
var
  T        : TTree;
  Unc, R   : string;
  SL       : TStringList;
  Map      : TRdxCodeMap;
  T0       : TDateTime;
  Ms       : Integer;
  i        : Integer;
begin
  // R4-03, Pruefer-Fall vunc: eine LOKALE Unit bindet ein Include auf einem
  // Netzpfad ein. FileReason prueft nur den Pfad der Unit; IncludeReason
  // fragte FileExists auf dem Netzpfad - bei einem nicht erreichbaren
  // Server 9 bis 16 s im Hauptthread, bei jedem Menueaufbau. Jetzt lehnt sie
  // ohne Plattenzugriff ab. Den Pfad setzt der Test aus Teilen zusammen (ein
  // Pfad als Literal waere ein SCA016-Fund im Selbstscan).
  T := NewTree;
  SL := TStringList.Create;
  Map := nil;
  try
    for i := 0 to 1 do
    begin
      Unc := PathDelim + PathDelim + 'rdx-b1fd-gibt-es-nicht' + PathDelim
        + 'share' + PathDelim;
      if i = 1 then
        Unc := StringReplace(Unc, PathDelim, '/', [rfReplaceAll]);
      SL.Text := Join(['unit u;', 'interface', '{$I ' + Unc + 'defs.inc}',
        'implementation', 'end.']);
      Map.Free;
      Map := TRdxCodeMap.Create(SL);
      Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U), 'die Unit ist lokal');
      T0 := Now;
      R := TRdxMagicFixes.IncludeReason(T.U, Map);
      Ms := Round((Now - T0) * MSecsPerDay);
      Assert.IsTrue(Pos('auf einem Netzpfad', R) > 0, R);
      Assert.IsTrue(Ms < 2000, Format('ohne Plattenzugriff: %d ms', [Ms]));
    end;
  finally
    Map.Free;
    SL.Free;
    RemoveTree(T.Root);
  end;
end;

{ ---- Charge G9 (Entscheid E29): Sprache der Gruende ---- }

// Endet S mit ATail?
function EndsWithText(const S, ATail: string): Boolean;
begin
  Result := (Length(S) >= Length(ATail))
    and (Copy(S, Length(S) - Length(ATail) + 1, MaxInt) = ATail);
end;

// Die Gruende folgen der reDelphix-Sprache (en/de/fr), auch zusammen-
// gesetzte: der Aufrufer uebersetzt, was er weitergibt (FEATURE_INLINE an
// uRdxCompilerTraces.ScriptReason, das Muster R_INC_UNSEEN an
// uRdxBlocks.IncludeChainReason - die Ursache darin setzt uRdxBlocks ein,
// sie bleibt hier offen), und 'von Hand' steht als MsgByHand hinter '; '.
// Geprueft wird je Sprache das Satzende in ASCII (die Umlaute und Akzente
// der .po liegen davor), in en dazu der ganze Satz. Danach gilt wieder die
// Sprache des Laufs.
procedure TTestRdxMagicGuards.Reasons_FollowRdxLanguage;
const
  LANGS: array[0..2] of string = ('en', 'de', 'fr');
  // Skript ('unit' ohne implementation): das uebersetzte FEATURE_INLINE an
  // seiner Stelle im Satz von ScriptReason.
  SCRIPT_TAIL: array[0..2] of string = ('(script?) - only the compiler knows '
    + 'an inline constant', '(Skript?) - eine Inline-Konstante kennt nur der '
    + 'Compiler', ' une constante inline');
  // Netzpfad: der Satz vor MsgByHand.
  NET_TAIL: array[0..2] of string = ('(the menu is built in the main thread); ',
    'im Hauptthread); ', 'dans le thread principal); ');
  // Fehlendes Include: das Muster R_INC_UNSEEN hinter der Ursache.
  INC_TAIL: array[0..2] of string = (' - the quick fix does not see its '
    + 'compiler switches (FPC, older Delphi)', ' Delphi) sieht die Hilfe nicht',
    ' - le Quick-Fix ne voit pas ses aiguillages de compilation (FPC, Delphi '
    + 'plus anciens)');
var
  T        : TTree;
  SL       : TStringList;
  Map      : TRdxCodeMap;
  Old, Src : string;
  Net, R   : string;
  i        : Integer;
begin
  Src := Join(['unit userscript;', '', 'procedure P(X: Integer);', 'begin',
    '  Foo;', '  if X > 300 then Bar;', 'end;', '', 'end.']);
  // Den Netzpfad setzt der Test aus Teilen zusammen (SCA016, s. o.).
  Net := PathDelim + PathDelim + 'rdx-g9-gibt-es-nicht' + PathDelim + 'share'
    + PathDelim + 'u.pas';
  T := NewTree;
  SL := TStringList.Create;
  Map := nil;
  Old := RdxLanguageOverride;
  try
    SL.Text := Join(['unit u;', 'interface', '{$I defs.inc}', 'implementation',
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    for i := 0 to High(LANGS) do
    begin
      SetRdxLanguageOverride(LANGS[i]);
      R := PlanReason(Src, 'X > 300', '300');
      Assert.IsTrue(EndsWithText(R, SCRIPT_TAIL[i]), LANGS[i] + ', Skript: ' + R);
      R := TRdxMagicFixes.FileReason(Net);
      Assert.IsTrue(EndsWithText(R, NET_TAIL[i] + MsgByHand),
        LANGS[i] + ', Netzpfad: ' + R);
      R := TRdxMagicFixes.IncludeReason(T.U, Map);
      Assert.IsTrue(EndsWithText(R, INC_TAIL[i]), LANGS[i] + ', Include: ' + R);
    end;
    SetRdxLanguageOverride('en');
    Assert.AreEqual('unit without an implementation part (script?) - only the '
      + 'compiler knows an inline constant', PlanReason(Src, 'X > 300', '300'));
    Assert.AreEqual('network path (' + ExtractFileDir(Net) + ') - the quick fix '
      + 'reads no project or include files there (the menu is built in the '
      + 'main thread); by hand', TRdxMagicFixes.FileReason(Net));
  finally
    SetRdxLanguageOverride(Old);
    Map.Free;
    SL.Free;
    RemoveTree(T.Root);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMagicGuards);

end.
