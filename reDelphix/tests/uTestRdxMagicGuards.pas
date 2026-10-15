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
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxMagicFixes;

const
  MSG = 'Magic number "%s" in if condition - use a constant';
  DPROJ_FMT = '<?xml version="1.0" encoding="utf-8"?>' + #13#10
    + '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    + #13#10 + '  <PropertyGroup>' + #13#10
    + '    <ProjectVersion>%s</ProjectVersion>' + #13#10
    + '  </PropertyGroup>' + #13#10 + '</Project>';

// ---- Helfer ----

procedure WriteText(const APath, AText: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

// Ein frischer Baum TEMP\rdx_sqc_<GUID>\ (mit Trenner).
function FreshRoot: string;
var
  G : TGUID;
begin
  CreateGUID(G);
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_sqc_' + GUIDToString(G) + PathDelim;
  ForceDirectories(Result);
end;

// Loescht den Baum ADir (mit Trenner) samt Inhalt.
procedure RemoveTree(const ADir: string);
var
  SR : TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(ADir + SR.Name + PathDelim)
      else
        DeleteFile(ADir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ADir);
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

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der Planer fuer den Fund "AValue" auf der ersten Zeile mit AOnLine: ''
// mit Plan oder der Grund.
function PlanReason(const ASource, AOnLine, AValue: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Plan : TRdxMagicPlan;
  i, L : Integer;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    L := 0;
    for i := 0 to SL.Count - 1 do
      if (L = 0) and (Pos(AOnLine, SL[i]) > 0) then
        L := i + 1;
    Map := TRdxCodeMap.Create(SL);
    if not TRdxMagicFixes.MagicNumber(Map, L, Format(MSG, [AValue]), Plan,
         Result) then
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

end.
