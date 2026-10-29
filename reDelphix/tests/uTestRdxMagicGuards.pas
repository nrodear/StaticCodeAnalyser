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
    // ---- Realworld-Test rwE30 Stufe 2 ----
    [Test] procedure Disk_OldProjectPair_Refused;
    [Test] procedure Disk_DualCompilerProject_Refused;
    [Test] procedure Disk_ExceptionClasses_OnlyEvidence;
    [Test] procedure Disk_ModernProof_SkipsDisk;
    [Test] procedure Disk_PackageUsesInvariant_Refutes;
    [Test] procedure Disk_ProgramSetsSettings_Refused;
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
  R := TRdxMagicFixes.FileReason(AFile, lfInlineConst);
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
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), 'leer');
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
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), 'drei Ebenen');
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
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), '18.5 = 10.3');
    WriteDproj(T.C + 'P.dproj', '20.1');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), '20.1');
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
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), 'naechstes Projekt neu');
    // ... und auch eine alte im selben Verzeichnis (die .dproj zaehlt).
    WriteText(T.C + 'Old.dof', '[x]');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), 'dproj vor dof');
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
  Assert.IsTrue(Pos('Hauptblock des Programms bzw. der Bibliothek (begin ab '
    + 'Zeile 2)', R) > 0, R);
  R := PlanReason(Join(['library l;', 'uses SysUtils;', 'begin', '  try',
    '    if X > 200 then Y;', '  finally', '  end;', 'end.']), 'X > 200', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms bzw. der Bibliothek (begin ab '
    + 'Zeile 3)', R) > 0, R);
  // Text hinter 'end.' (Delphi liest ihn nicht): der Hauptblock endet am
  // ersten 'end.', nicht am letzten Token - vorher fiel die Sperre still
  // weg (Wochen-Review 2026-10-21).
  R := PlanReason(Join(['program p;', 'begin', '  if ParamCount > 200 then Halt;',
    'end.', 'Altes Zeug ohne Kommentarklammern']), 'ParamCount', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms bzw. der Bibliothek (begin ab '
    + 'Zeile 2)', R) > 0, 'Text hinter end.: ' + R);
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
  Assert.IsTrue(Pos('Hauptblock des Programms bzw. der Bibliothek (begin ab '
    + 'Zeile 5)', R) > 0, R);
  // 'Begin' als Name schloss die Bilanz zu frueh (Zeile 3 statt 2).
  R := PlanReason(Join(['library l;', 'begin', '  Foo(Begin := 1);',
    '  if X > 200 then Y;', 'end.']), 'X > 200', '200');
  Assert.IsTrue(Pos('Hauptblock des Programms bzw. der Bibliothek (begin ab '
    + 'Zeile 2)', R) > 0, R);
end;

procedure TTestRdxMagicGuards.Disk_IncludeOnNetworkPath_NoDiskAccess;
var
  T        : TTree;
  Unc, R   : string;
  SL       : TStringList;
  Map      : TRdxCodeMap;
  i        : Integer;
begin
  // R4-03, Pruefer-Fall vunc: eine LOKALE Unit bindet ein Include auf einem
  // Netzpfad ein. FileReason prueft nur den Pfad der Unit; IncludeReason
  // fragte FileExists auf dem Netzpfad - bei einem nicht erreichbaren
  // Server 9 bis 16 s im Hauptthread, bei jedem Menueaufbau. Jetzt lehnt sie
  // ohne Plattenzugriff ab. Den Pfad setzt der Test aus Teilen zusammen (ein
  // Pfad als Literal waere ein SCA016-Fund im Selbstscan).
  T := NewTree;
  SL := nil;
  Map := nil;
  try
    SL := TStringList.Create;
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
      Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfInlineConst), 'die Unit ist lokal');
      // Der Grund ist die Probe: IncludeFileReason (uRdxBlocks) prueft den
      // Netzpfad VOR FindInclude. Die Wanduhr (bis zum Wochen-Review
      // 2026-10-21: < 2000 ms) bewies keinen fehlenden Plattenzugriff und
      // wurde unter Last rot.
      R := TRdxMagicFixes.IncludeReason(T.U, Map, lfInlineConst);
      Assert.IsTrue(Pos('auf einem Netzpfad', R) > 0, R);
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
// Die Gruende des Plattenblicks sind je Sprachmittel (TRdxLateFeature) ein
// ganzer Satz - stellvertretend die Lazarus-/FPC-Datei fuer alle drei.
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
  // Lazarus-/FPC-Datei je Sprachmittel (TRdxLateFeature): je Sprache und
  // Sprachmittel ein eigener ganzer Satz - Geschlecht und Zahl ('eine
  // Inline-Konstante', 'Zifferntrenner') stellt die Sprache selbst. Die
  // globale FormatSettings und die Ausnahmeklassen von SCA127 kennt FPC
  // (FpcKnows): dort kein Grund ('').
  FPC_TAIL: array[0..2, TRdxLateFeature] of string = (
    ('FPC 3.2 has no inline constants', 'FPC 3.2 has no digit separators',
     'FPC 3.2 has no inline variables',
     'FPC 3.2 has no TFormatSettings.Invariant', '', ''),
    ('eine Inline-Konstante gibt es in FPC 3.2 nicht',
     'Zifferntrenner gibt es in FPC 3.2 nicht',
     'eine Inline-Variable gibt es in FPC 3.2 nicht',
     'FPC 3.2 kennt kein TFormatSettings.Invariant', '', ''),
    (' constantes inline', ' de chiffres', ' variables inline',
     ' TFormatSettings.Invariant', '', ''));
var
  T        : TTree;
  SL       : TStringList;
  Map      : TRdxCodeMap;
  Old, Src : string;
  Net, R   : string;
  i        : Integer;
  F        : TRdxLateFeature;
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
      R := TRdxMagicFixes.FileReason(Net, lfInlineConst);
      Assert.IsTrue(EndsWithText(R, NET_TAIL[i] + MsgByHand),
        LANGS[i] + ', Netzpfad: ' + R);
      R := TRdxMagicFixes.IncludeReason(T.U, Map, lfInlineConst);
      Assert.IsTrue(EndsWithText(R, INC_TAIL[i]), LANGS[i] + ', Include: ' + R);
      for F := Low(TRdxLateFeature) to High(TRdxLateFeature) do
      begin
        R := TRdxMagicFixes.FileReason('u.pp', F);
        if TRdxMagicFixes.FpcKnows(F) then
          Assert.AreEqual('', R, LANGS[i] + ', FPC-Datei (FPC kennt es) '
            + IntToStr(Ord(F)))
        else
          Assert.IsTrue(EndsWithText(R, FPC_TAIL[i, F]),
            LANGS[i] + ', FPC-Datei ' + IntToStr(Ord(F)) + ': ' + R);
      end;
    end;
    SetRdxLanguageOverride('en');
    Assert.AreEqual('unit without an implementation part (script?) - only the '
      + 'compiler knows an inline constant', PlanReason(Src, 'X > 300', '300'));
    Assert.AreEqual('network path ' + ExtractFileDir(Net) + ' - the quick fix '
      + 'reads no project or include files there (the menu is built in the '
      + 'main thread); by hand', TRdxMagicFixes.FileReason(Net, lfInlineConst));
    Assert.AreEqual('Lazarus/FPC file (.pp) - FPC 3.2 has no digit separators',
      TRdxMagicFixes.FileReason('u.pp', lfDigitSeparator));
  finally
    SetRdxLanguageOverride(Old);
    Map.Free;
    SL.Free;
    RemoveTree(T.Root);
  end;
end;

{ ---- Realworld-Test rwE30 Stufe 2 ---- }

// ProjectReason fuer die Unit AFile mit dem Text ASource.
function ProjectReasonOf(const AFile, ASource: string; AFeature: TRdxLateFeature;
  AIncludes: Boolean): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxMagicFixes.ProjectReason(AFile, Map, AFeature, AIncludes);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure AssertNames(const AReason: string; const AParts: array of string);
var
  i : Integer;
begin
  Assert.IsTrue(AReason <> '', 'Grund erwartet');
  for i := Low(AParts) to High(AParts) do
    Assert.IsTrue(Pos(AParts[i], AReason) > 0, AParts[i] + ' <> ' + AReason);
end;

procedure TTestRdxMagicGuards.Disk_OldProjectPair_Refused;
var
  T : TTree;
  F : TRdxLateFeature;
begin
  // cnwizards Tool\CnDebugViewer: CnDebugViewer.dpr mit .dof/.cfg (Delphi
  // 5-7) neben CnDebugViewer64.dpr/.dproj. Bis dahin machte die neue .dproj
  // jede alte Projektdatei im Verzeichnis stumm - CnMdiView.pas:751 bekam
  // ', FormatSettings' (E2003 in Delphi 5-7).
  T := NewTree;
  try
    WriteText(T.C + 'CnDebugViewer.dpr', 'program CnDebugViewer;');
    WriteText(T.C + 'CnDebugViewer.dof', '[Compiler]');
    WriteText(T.C + 'CnDebugViewer.cfg', '-$A8');
    WriteText(T.C + 'CnDebugViewer64.dpr', 'program CnDebugViewer64;');
    WriteDproj(T.C + 'CnDebugViewer64.dproj', '19.5');
    for F := Low(TRdxLateFeature) to High(TRdxLateFeature) do
      AssertNames(TRdxMagicFixes.FileReason(T.U, F), ['CnDebugViewer.']);
    // Gegenproben: das Projekt hat seine eigene .dproj (die IDE schreibt
    // die .cfg weiter daneben) ...
    WriteDproj(T.C + 'CnDebugViewer.dproj', '19.5');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar),
      'Projekt mit eigener .dproj');
    // ... bzw. eine .cfg ohne Programm gleichen Namens.
    DeleteFile(T.C + 'CnDebugViewer.dproj');
    DeleteFile(T.C + 'CnDebugViewer.dpr');
    DeleteFile(T.C + 'CnDebugViewer.dof');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar),
      '.cfg ohne Programm');
    // Ohne jede .dproj: Programm mit .cfg (Delphi bis 2007) ist alt.
    DeleteFile(T.C + 'CnDebugViewer64.dproj');
    WriteText(T.C + 'Tool.dpr', 'program Tool;');
    WriteText(T.C + 'Tool.cfg', '-$A8');
    AssertNames(TRdxMagicFixes.FileReason(T.U, lfExceptionClasses), ['.cfg']);
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_DualCompilerProject_Refused;
var
  T : TTree;
begin
  // mORMot2 ...\10-InvoiceExample\src: RechnungDelphi.dpr ohne .dproj neben
  // Rechnung.lpi - fuer Delphi 7 und FPC geschrieben; rgInvoiceItemEdit.pas
  // :217 bekam ', FormatSettings' (Delphi 7 kennt die Variable nicht). FPC
  // allein sperrt den Hauptweg nicht (FpcKnows).
  T := NewTree;
  try
    WriteText(T.C + 'Rechnung.lpi', '<CONFIG/>');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar),
      'nur Lazarus');
    WriteText(T.C + 'RechnungDelphi.dpr', 'program RechnungDelphi;');
    AssertNames(TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar),
      ['RechnungDelphi.dpr', 'Rechnung.lpi']);
    AssertNames(TRdxMagicFixes.FileReason(T.U, lfExceptionClasses),
      ['RechnungDelphi.dpr', 'Rechnung.lpi']);
    // Gegenprobe: mit eigener .dproj ist das Programm neu.
    WriteDproj(T.C + 'RechnungDelphi.dproj', '19.5');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar),
      'Programm mit .dproj');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_ExceptionClasses_OnlyEvidence;
const
  SRC_INC = 'unit u;' + #13#10 + 'interface' + #13#10 + '{$I %s}' + #13#10
    + 'implementation' + #13#10 + 'end.';
var
  T   : TTree;
  Net : string;
begin
  // SCA127: nur ein Beleg sperrt (Nico-Entscheid rwE30 Stufe 2). Ein nicht
  // gefundenes Include und ein Netzpfad sind keiner - fuer die Sprachmittel
  // ab 10.3 bleiben sie Gruende.
  T := NewTree;
  try
    Assert.AreEqual('', ProjectReasonOf(T.U, Format(SRC_INC, ['fehlt.inc']),
      lfExceptionClasses, True), 'Include fehlt');
    Assert.IsTrue(ProjectReasonOf(T.U, Format(SRC_INC, ['fehlt.inc']),
      lfFormatInvariant, True) <> '', 'Include fehlt, Invariant');
    // GExperts Extras\NewEditor\GX_eAlign.pas: '{$I GX_CondDefine.inc}'
    // fragt nur nach VER100..VER140 (Delphi 3-6).
    WriteText(T.C + 'GX_CondDefine.inc', '{$IFDEF VER140}' + #13#10
      + '  {$DEFINE GX_VER140}' + #13#10 + '{$ENDIF}');
    AssertNames(ProjectReasonOf(T.U, Format(SRC_INC, ['GX_CondDefine.inc']),
      lfExceptionClasses, True), ['GX_CondDefine.inc', 'VER140']);
    // Gegenprobe: ein Include nur mit neuen Versionen.
    WriteText(T.C + 'GX_CondDefine.inc', '{$IFDEF VER350}' + #13#10
      + '  {$DEFINE D11}' + #13#10 + '{$ENDIF}');
    Assert.AreEqual('', ProjectReasonOf(T.U, Format(SRC_INC,
      ['GX_CondDefine.inc']), lfExceptionClasses, True), 'neues Include');
    // GExperts: die alte Projektdatei zwei Ebenen hoeher.
    WriteText(T.A + 'GExpert4.dof', '[Compiler]');
    AssertNames(ProjectReasonOf(T.U, 'unit u; implementation end.',
      lfExceptionClasses, True), ['GExpert4.dof']);
    // Netzpfad: kein Beleg (SCA127), Grund fuer die anderen.
    Net := PathDelim + PathDelim + 'rdx-e30-gibt-es-nicht' + PathDelim
      + 'share' + PathDelim + 'u.pas';
    Assert.AreEqual('', ProjectReasonOf(Net, 'unit u; implementation end.',
      lfExceptionClasses, True), 'Netzpfad');
    Assert.IsTrue(ProjectReasonOf(Net, 'unit u; implementation end.',
      lfFormatSettingsVar, False) <> '', 'Netzpfad, FormatSettings');
    Assert.IsFalse(TRdxMagicFixes.MissingBlocks(lfExceptionClasses));
    Assert.IsTrue(TRdxMagicFixes.MissingBlocks(lfFormatSettingsVar));
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_ModernProof_SkipsDisk;
const
  INLINE_SRC = 'unit u;' + #13#10 + 'interface' + #13#10 + 'implementation'
    + #13#10 + 'procedure P;' + #13#10 + 'begin' + #13#10
    + '  for var i := 1 to 3 do ;' + #13#10 + 'end;' + #13#10 + 'end.';
  SCOPE_SRC = 'unit u;' + #13#10 + 'interface' + #13#10
    + 'uses System.SysUtils;' + #13#10 + 'implementation' + #13#10 + 'end.';
var
  T : TTree;
begin
  // Die Datei beweist selbst einen neueren Compiler: die alte Projektdatei
  // daneben ist nicht ihr Bau (rwE30 Stufe 2, ModernProof).
  T := NewTree;
  try
    WriteText(T.C + 'Old.dof', '[Compiler]');
    Assert.IsTrue(TRdxMagicFixes.FileReason(T.U, lfFormatSettingsVar) <> '',
      'ohne Beweis');
    Assert.AreEqual('', ProjectReasonOf(T.U, INLINE_SRC, lfFormatSettingsVar,
      False), 'Inline-Variable, FormatSettings');
    Assert.AreEqual('', ProjectReasonOf(T.U, INLINE_SRC, lfFormatInvariant,
      True), 'Inline-Variable, Invariant');
    Assert.AreEqual('', ProjectReasonOf(T.U, SCOPE_SRC, lfExceptionClasses,
      True), 'Namensraum, SCA127');
    // Gegenprobe: XE2 (Namensraum) beweist Invariant (10.3) nicht.
    AssertNames(ProjectReasonOf(T.U, SCOPE_SRC, lfFormatInvariant, True),
      ['Old.dof']);
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_PackageUsesInvariant_Refutes;
var
  T        : TTree;
  Pkg, Dpk : string;
begin
  // delphimvcframework\lib\loggerpro\LoggerPro.HTMLFileAppender.pas:354:
  // loggerproRT.dpk in packages\d100 (Delphi 10.0) enthaelt die Unit - und
  // LoggerPro.Renderers.pas, die 'fFormatSettings :=
  // TFormatSettings.Invariant' ohne Weiche setzt: das Paket baut auf 10.0
  // mit Invariant, die Versionssperre ist widerlegt.
  T := NewTree;
  try
    Pkg := T.B + 'packages' + PathDelim + 'd100' + PathDelim;
    ForceDirectories(Pkg);
    Dpk := 'package pkg;' + #13#10 + 'contains' + #13#10
      + '  u in ''..\..\c\u.pas'',' + #13#10
      + '  w in ''..\..\c\w.pas'';' + #13#10 + 'end.';
    WriteText(Pkg + 'pkg.dpk', Dpk);
    WriteText(T.C + 'w.pas', 'unit w;' + #13#10 + 'implementation' + #13#10
      + 'procedure P;' + #13#10 + 'begin' + #13#10
      + '  {$IFDEF X} F := TFormatSettings.Invariant; {$ENDIF}' + #13#10
      + 'end;' + #13#10 + 'end.');
    AssertNames(TRdxMagicFixes.FileReason(T.U, lfFormatInvariant),
      ['pkg.dpk', 'd100']);
    WriteText(T.C + 'w.pas', 'unit w;' + #13#10 + 'implementation' + #13#10
      + 'procedure P;' + #13#10 + 'begin' + #13#10
      + '  F := TFormatSettings.Invariant;' + #13#10 + 'end;' + #13#10
      + 'end.');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(T.U, lfFormatInvariant),
      'Paket nutzt Invariant');
    // Die globale FormatSettings beweist es nicht.
    AssertNames(TRdxMagicFixes.FileReason(T.U, lfInlineConst), ['pkg.dpk']);
    // MVCFramework.HttpSys.Response.pas:335: dasselbe Paket widerlegt die
    // Spur im Include (dmvcframework.inc 'CompilerVersion <= 29') - ein
    // Paket in einem neuen Ordner (d110) reicht.
    RemoveTree(Pkg);
    Pkg := T.B + 'packages' + PathDelim + 'd110' + PathDelim;
    ForceDirectories(Pkg);
    WriteText(T.C + 'defs.inc', '{$IF CompilerVersion <= 29}' + #13#10
      + '  {$DEFINE OLD}' + #13#10 + '{$IFEND}');
    AssertNames(ProjectReasonOf(T.U, 'unit u;' + #13#10 + '{$I defs.inc}'
      + #13#10 + 'implementation' + #13#10 + 'end.', lfFormatInvariant,
      True), ['defs.inc']);
    WriteText(Pkg + 'pkg.dpk', Dpk);
    Assert.AreEqual('', ProjectReasonOf(T.U, 'unit u;' + #13#10
      + '{$I defs.inc}' + #13#10 + 'implementation' + #13#10 + 'end.',
      lfFormatInvariant, True), 'Paket widerlegt das Include');
  finally
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxMagicGuards.Disk_ProgramSetsSettings_Refused;
const
  PROOF_SRC = 'unit u;' + #13#10 + 'interface' + #13#10 + 'implementation'
    + #13#10 + 'procedure P;' + #13#10 + 'begin' + #13#10
    + '  for var i := 1 to 3 do ;' + #13#10 + 'end;' + #13#10 + 'end.';
  INVARIANT_SRC = 'unit u;' + #13#10 + 'interface' + #13#10
    + 'implementation' + #13#10 + 'procedure P;' + #13#10 + 'begin' + #13#10
    + '  F := TFormatSettings.Invariant;' + #13#10 + 'end;' + #13#10 + 'end.';
var
  T, Prg : string;
  Tr     : TTree;
begin
  // HeidiSQL: packages\Delphi12.3\heidisql.dpr enthaelt source\main.pas und
  // setzt 'FormatSettings.ShortDateFormat := ''yyyy/mm/dd'''. Mit Invariant
  // schriebe DateToStr MM/dd/yyyy, der Editor (EditMask 0000-00-00) und
  // StrToDate des Programms lesen ISO (main.pas:11246/11252).
  Tr := NewTree;
  try
    Prg := Tr.B + 'packages' + PathDelim + 'Delphi12.3' + PathDelim;
    ForceDirectories(Prg);
    T := 'program heidisql;' + #13#10 + 'uses' + #13#10
      + '  main in ''..\..\c\u.pas'';' + #13#10 + 'begin' + #13#10
      + '  // ShortDateFormat := nur ein Kommentar' + #13#10;
    WriteText(Prg + 'heidisql.dpr', T + 'end.');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(Tr.U, lfFormatInvariant),
      'nur Kommentar');
    WriteText(Prg + 'heidisql.dpr', T
      + '  FormatSettings.ShortDateFormat := ''yyyy/mm/dd'';' + #13#10
      + 'end.');
    AssertNames(TRdxMagicFixes.FileReason(Tr.U, lfFormatInvariant),
      ['heidisql.dpr', 'ShortDateFormat']);
    Assert.AreEqual('', TRdxMagicFixes.FileReason(Tr.U, lfFormatSettingsVar),
      'Hauptweg (gleiche Bedeutung)');
    // Review e/HilfeFixG: der Gegenbeweis der Unit (Inline-Variable bzw.
    // Invariant ohne Weiche) widerlegt nur Compiler - das Programm sperrt
    // weiter (bis dahin liess ProjectReason es ungelesen).
    AssertNames(ProjectReasonOf(Tr.U, PROOF_SRC, lfFormatInvariant, True),
      ['heidisql.dpr', 'ShortDateFormat']);
    AssertNames(ProjectReasonOf(Tr.U, INVARIANT_SRC, lfFormatInvariant, True),
      ['heidisql.dpr', 'ShortDateFormat']);
    Assert.AreEqual('', ProjectReasonOf(Tr.U, PROOF_SRC, lfFormatSettingsVar,
      False), 'Hauptweg mit Gegenbeweis');
    // Gegenprobe: ein Programm, das die Unit nicht enthaelt.
    WriteText(Prg + 'heidisql.dpr', StringReplace(T, 'u.pas', 'v.pas', [])
      + '  FormatSettings.ShortDateFormat := ''yyyy/mm/dd'';' + #13#10
      + 'end.');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(Tr.U, lfFormatInvariant),
      'anderes Programm');
    Assert.AreEqual('', ProjectReasonOf(Tr.U, PROOF_SRC, lfFormatInvariant,
      True), 'anderes Programm, Gegenbeweis');
  finally
    RemoveTree(Tr.Root);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMagicGuards);

end.
