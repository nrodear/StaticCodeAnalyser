unit uTestRdxFreeGatesDetector;

// Charge FB (Code-Review reDelphix, Bereich R2/R3) gegen die ECHTEN
// Detektoren und den Einstieg des Anbieters (TRdxFixTable.FixFor): die
// Sperren, die im Laeufer bzw. in der Tabelle sitzen und den Quellstellen-
// Dienst (Resolver) brauchen - deshalb nur Delphi (reDelphix.Test), nicht
// im FPC-Pruefstand (dort loest der Stub-Resolver nichts auf). Die reinen
// Textteile pruefen uTestRdxFreeTypes (TRdxTypeProof.DeclaresNonClassType
// mit Zeiger; bis zur Folgewelle A4 TRdxSimpleFixes.DeclaresValueType) und
// die Korpus-Harness der Charge (die Sperr-Funktionen woertlich unter FPC).
//   * SCA085 bekommt die Typ-Sperre von SCA139 (R2-01/R3-01): Zeiger auf
//     ein object mit eigenem Free (mORMot), eine Klasse mit eigener Free
//     (Pool), ein fremder Zeigertyp nach Namenskonvention (PEVP_PKEY).
//   * SCA139: Zeiger-Alias der Unit (missed R2(4)/R3(2)), fremder
//     P-Typ, const-Parameter (R2-03) - ein var-Parameter bleibt Hilfe.
//     Einen const-Parameter meldet der Detektor seit 2026-10-22 nicht mehr
//     (lokale Kopie wie ohne Modifier); die Sperre der Hilfe bleibt fuer
//     Funde aus aelteren Laeufen (Baseline, SARIF) und wird mit einem
//     nachgebildeten Fund geprueft (AssertConstParamNoHelp).
//   * SCA147/SCA164 auf einem Netzpfad lesen keine Form-/Include-Dateien
//     (R2-07).
//   * Pin (missed R2(3)): ein Unit-Global, das wie ein geerbtes Member
//     heisst, ist in einer Methode einer TForm-Ableitung nicht bewiesen -
//     das leistet der strenge Resolver (StrictMemberType) schon.
//   * Nachpruefung: ein fremder Zeiger hinter einem Alias der Unit
//     (PMyKey = PEVP_PKEY), ein Attribut vor dem Kopf auf derselben Zeile,
//     der Win32-Namensraum ('\\?\C:\..' lokal, '\\?\UNC\..' Netzpfad).
//   * Gegenpruefung V-B2S-3 (Charge B2S-a): SCA147 auf einem Netzlaufwerk,
//     auch lang geschrieben - der Grund nennt das Laufwerk (Naht
//     SetRdxRemoteDriveTest statt GetDriveType).
//   * Realwelt-Test rwE29 (SCA085, drei Fehler): Erben des alten Open
//     Tools API (VirtIntf.TInterface: Free ruft Release) - in der Unit
//     ueber die Vorfahrenkette und als fremder Typ - und ein Kommentar,
//     der FreeAndNil an der Stelle verbietet. Die drei Sperrtests waren
//     gegen 7d5de210 rot (angeboten); die Gegenprobe
//     Sca085_PlainHeritageAndComment_Helps war dort schon gruen.
// Jeder Test ausser den beiden Hilfe-Gegenproben (Sca139_VarParam_Helps,
// Sca072_*) und dem Netzlaufwerk-Test (die Naht gibt es erst seit Charge
// B2S-a) war gegen den Stand 4358b769 rot: dort bot der Laeufer die
// Hilfe an bzw. lehnte mit einem anderen Grund ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFreeGatesDetector = class
  public
    // ---- SCA085 (R2-01/R3-01) ----
    [Test] procedure Sca085_PointerToObjectWithFree_NoHelp;
    [Test] procedure Sca085_OwnFreeMethod_NoHelp;
    [Test] procedure Sca085_ForeignPointerName_NoHelp;
    // ---- SCA085, Realwelt-Test rwE29 ----
    [Test] procedure Sca085_OtaAncestorInUnit_NoHelp;
    [Test] procedure Sca085_OtaForeignType_NoHelp;
    [Test] procedure Sca085_CommentNamesFreeAndNil_NoHelp;
    [Test] procedure Sca085_PlainHeritageAndComment_Helps;
    // ---- SCA139 ----
    [Test] procedure Sca139_PointerAlias_NoHelp;
    [Test] procedure Sca139_ForeignPointerName_NoHelp;
    [Test] procedure Sca139_ConstParam_NoHelp;
    [Test] procedure Sca139_VarParam_Helps;
    // ---- SCA147/SCA164 (R2-07) ----
    [Test] procedure Sca147_UncPath_NoHelp;
    [Test] procedure Sca164_UncPathWithInclude_NoHelp;
    // ---- Pin des strengen Resolvers (missed R2(3)) ----
    [Test] procedure Sca072_UnitGlobalShadowedByInherited_NoHelp;
    // ---- Nachpruefung FB (Pruefer FB_verify, gprobe F4/C21/N1) ----
    [Test] procedure Sca139_ForeignPointerBehindUnitAlias_NoHelp;
    [Test] procedure Sca139_ConstParam_AttributeOnHeadLine_NoHelp;
    [Test] procedure Sca147_Win32NamespacePaths;
    // ---- Gegenpruefung V-B2S-3 ----
    [Test] procedure Sca147_RemoteDrive_NoHelp;
  end;

  // rwE33 Stufe 5 (Sperre unnoetig, Dev-Cpp InstallWizards.pas:684): System.
  // SysUtils nur in zwei getrennten Bloecken ohne {$ELSE}, FreeAndNil aber
  // schon unqualifiziert im Code - die Hilfe kommt ohne uses-Ergaenzung
  // (uRdxFixRunner.FreeAndNilCalledLine). Eigene Fixture: die erste waere
  // sonst ueber 20 Tests (SCA138).
  [TestFixture]
  TTestRdxFreeKnownDetector = class
  public
    // Das Muster der Fundstelle: frei, uses bleibt.
    [Test] procedure Sca085_FreeAndNilCalled_Helps;
    // Aufruf und Stelle im selben Zweig: frei.
    [Test] procedure Sca085_FreeAndNilCalledInSiteBranch_Helps;
    // Gegenproben: nur in einem anderen Zweig, nur im Kommentar, nur
    // qualifiziert, eigene FreeAndNil der Unit - gesperrt wie bisher; seit
    // dem Review-Nachzug auch: nur in einer anderen Klasse, Variable
    // FreeAndNil.
    [Test] procedure Sca085_FreeAndNilNotProven_Locked;
    // SCA139 nimmt denselben Beweis.
    [Test] procedure Sca139_FreeAndNilCalled_Helps;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts,
  uFreeAndNilHint, uFreeWithoutNil, uUnusedRoutine, uUnusedPrivateMethod,
  uRedundantBoolean,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxPaths,             // SetRdxRemoteDriveTest (Naht fuer das Netzlaufwerk)
  uRdxPlacesRunner,      // R_USES_ONLY_CONDITIONAL (TTestRdxFreeKnownDetector)
  uRdxText,              // _, MsgByHand (TTestRdxFreeKnownDetector)
  uTestRdxDetectorKit,   // TSeen, Detect-/Plan-/FixAll-Helfer
  uTestRdxTextKit;       // Join, Apply, TempName

const
  // Eine Freigabe, die es nicht gibt: die Hilfen duerfen dort nichts lesen.
  // noinspection HardcodedPath (Testdaten: der Netzpfad IST der Testfall)
  UNC_FILE = '\\rdx-fb-nohost\share\src\t.pas';
  // Derselbe Netzpfad im Win32-Namensraum ('\\?\UNC\..').
  UNC_NS_FILE = '\\?\UNC\rdx-fb-nohost\share\src\t.pas';
  // Vorsatz fuer lange lokale Pfade ('\\?\C:\..').
  LONG_PATH_PREFIX = '\\?\';
  // Das Netzlaufwerk der Attrappe (FakeRemoteDrive).
  DRIVE_Q = 'Q:';

// ---- Helfer ----

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkFreeAndNilHint:
      TFreeAndNilHintDetector.AnalyzeUnit(Root, Path, Results);
    fkFreeWithoutNil:
      TFreeWithoutNilDetector.AnalyzeUnit(Root, Path, Results);
    fkUnusedRoutine:
      TUnusedRoutineDetector.AnalyzeUnit(Root, Path, Results);
    fkUnusedPrivateMethod:
      TUnusedPrivateMethodDetector.AnalyzeUnit(Root, Path, Results);
    fkRedundantBoolean:
      TRedundantBooleanDetector.AnalyzeUnit(Root, Path, Results);
  else
    Assert.Fail('kein Detektor fuer diese Art');
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_freegates_', ASource, AKind, RunDetector);
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
end;

// Die Hilfe zum Fund auf Zeile ALine, geplant fuer die Datei AFile.
function PlanAt(const ASource, AFile: string; AKind: TFindingKind;
  ALine: Integer): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
  S    : TSeen;
begin
  Result := Default(TRdxFixOutcome);
  Seen := Detect(ASource, AKind);
  for S in Seen do
    if S.Line = ALine then
      Exit(PlanFixIn(ASource, AFile, AKind, S));
  Assert.Fail(Format('kein Fund auf Zeile %d', [ALine]));
end;

// Die erste Zeile (1-basiert), die AText enthaelt; ohne Treffer scheitert
// der Test. Eigener Name: uTestRdxTextKit.LineOf liefert dann 0 und trennt
// auch an LF und CR (Review R6-08).
function LineOfOrFail(const ASource, AText: string): Integer;
var
  Lines : TArray<string>;
  i     : Integer;
begin
  Lines := ASource.Split([#13#10]);
  for i := 0 to High(Lines) do
    if Pos(AText, Lines[i]) > 0 then
      Exit(i + 1);
  Result := 0;
  Assert.Fail('Zeile fehlt: ' + AText);
end;

// SCA139 auf 'ABucket.Free;' eines const-Parameters: der Detektor meldet ihn
// nicht (mehr), die Hilfe lehnt einen Fund aus einem aelteren Lauf ab - der
// Fund wird deshalb nachgebildet (Zeile und Meldung wie der Detektor sie
// bis 2026-10-22 schrieb).
procedure AssertConstParamNoHelp(const ASource: string);
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  Assert.AreEqual<Integer>(0, Length(Detect(ASource, fkFreeWithoutNil)),
    'der Detektor meldet einen const-Parameter nicht');
  S := Default(TSeen);
  S.Line := LineOfOrFail(ASource, 'ABucket.Free;');
  S.Msg := 'ABucket.Free without subsequent ABucket := nil - prefer ' +
    'FreeAndNil(ABucket)';
  O := PlanFixIn(ASource, 't.pas', fkFreeWithoutNil, S);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.IsTrue(Pos('const-Parameter', O.Reason) > 0, O.Reason);
end;

// Attrappe fuer GetDriveType in der Netzpfad-Regel (uRdxPaths): nur Q: ist
// ein Netzlaufwerk.
function FakeRemoteDrive(const ADrive: string): Boolean;
begin
  Result := SameText(ADrive, DRIVE_Q);
end;

// Eine Klasse THolder mit dem Feld AField und der Methode Reset, deren
// Rumpf AStatement traegt (danach ein Aufruf - sonst meldet SCA139 nicht:
// ein Free als letzter Aufruf der Methode gilt als Methodenende); ADecls
// stehen vor der Klasse.
function HolderUnit(const ADecls, AField, AStatement: string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses System.SysUtils, uOther;',
    'type', ADecls, '  THolder = class', '  private', '    ' + AField,
    '  public', '    procedure Reset;', '    procedure Changed;', '  end;',
    'implementation', 'procedure THolder.Reset;', 'begin', '  ' + AStatement,
    '  Changed;', 'end;', 'procedure THolder.Changed;', 'begin', 'end;',
    'end.']);
end;

// TBuckets.Add mit einem Parameter AParam (samt Modifizierer), der frei-
// gegeben wird.
function BucketsUnit(const AParam: string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses System.SysUtils, System.Classes;',
    'type', '  TBuckets = class', '  public',
    '    procedure Add(' + AParam + ': TStringList);', '    procedure Changed;',
    '  end;', 'implementation',
    'procedure TBuckets.Add(' + AParam + ': TStringList);', 'begin',
    '  if ABucket.Count = 0 then', '  begin', '    ABucket.Free;',
    '    Changed;', '  end;', 'end;', 'procedure TBuckets.Changed;', 'begin',
    'end;', 'end.']);
end;

{ ---- SCA085 ---- }

procedure TTestRdxFreeGatesDetector.Sca085_PointerToObjectWithFree_NoHelp;
begin
  // mORMot2 mormot.lib.openssl11.pas:8922 (X509_STORE.MainCrlAcquired):
  // 'result.Free; result := nil;' mit result: PX509_CRL = ^X509_CRL, einem
  // object mit eigenem Free. FreeAndNil(result): Delphi 12 E2010, FPC
  // TObject.Free auf der OpenSSL-Struktur (Zugriffsverletzung).
  AssertNoHelp(Join(['unit t;', 'interface', 'uses System.SysUtils;', 'type',
    '  PX509_CRL = ^X509_CRL;', '  X509_CRL = object', '  public',
    '    procedure Free;', '  end;', 'function NewCrl(AOk: Boolean): PX509_CRL;',
    'implementation', 'procedure X509_CRL.Free;', 'begin', 'end;',
    'function NewCrl(AOk: Boolean): PX509_CRL;', 'begin', '  result := nil;',
    '  if not AOk then', '  begin', '    result.Free;', '    result := nil;',
    '  end;', 'end;', 'end.']), fkFreeAndNilHint, 'kein Objekt');
end;

procedure TTestRdxFreeGatesDetector.Sca085_OwnFreeMethod_NoHelp;
begin
  // Gegenpruefer R3, v02: 'FBuf.Free' gibt das Objekt an den Pool zurueck;
  // FreeAndNil(FBuf) zerstoerte es (uebersetzt in Delphi 12 still).
  AssertNoHelp(Join(['unit t;', 'interface', 'uses System.SysUtils;', 'type',
    '  TPooled = class', '  public', '    procedure Free; reintroduce;',
    '  end;', '  TOwner = class', '  private', '    FBuf: TPooled;',
    '  public', '    procedure Done;', '  end;', 'implementation',
    'procedure TPooled.Free;', 'begin', 'end;', 'procedure TOwner.Done;',
    'begin', '  FBuf.Free;', '  FBuf := nil;', 'end;', 'end.']),
    fkFreeAndNilHint, 'eigene Methode Free');
end;

procedure TTestRdxFreeGatesDetector.Sca085_ForeignPointerName_NoHelp;
begin
  // mORMot2 mormot.crypt.openssl.pas:2354 ff.: fPrivKey: PEVP_PKEY aus
  // mormot.lib.openssl11 - in dieser Unit unbekannt, nach Konvention ein
  // Zeiger (Korpus: 7 Angebote, alle Zeiger auf ein object mit Free).
  AssertNoHelp(Join(['unit t;', 'interface',
    'uses System.SysUtils, mormot.lib.openssl11;', 'type', '  TCert = class',
    '  protected', '    fPrivKey: PEVP_PKEY;', '  public',
    '    procedure Clear;', '  end;', 'implementation', 'procedure TCert.Clear;',
    'begin', '  fPrivKey.Free;', '  fPrivKey := nil;', 'end;', 'end.']),
    fkFreeAndNilHint, 'Zeiger');
end;

{ ---- SCA085, Realwelt-Test rwE29 ---- }

// Eine Unit mit der Klasse TOwner, deren Feld AField in Done freigegeben
// wird: davor die Zeilen AAbove, ADecls vor TOwner.
function OwnerUnit(const AUses, ADecls, AField: string;
  const AAbove: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses ' + AUses + ';', 'type',
    ADecls, '  TOwner = class', '  private', '    ' + AField + ';', '  public',
    '    procedure Done;', '  end;', 'implementation', 'procedure TOwner.Done;',
    'begin', '  Assert(True);']) + #13#10 + Join(AAbove) + #13#10
    + Join(['  FX.Free;', '  FX := nil;', 'end;', 'end.']);
end;

procedure TTestRdxFreeGatesDetector.Sca085_OtaAncestorInUnit_NoHelp;
begin
  // GExperts GX_PriorityBoost.pas:187 (rwE29, Fehler): 'TGxBoostNotifier =
  // class(TIAddInNotifier)' - TIAddInNotifier (ToolIntf) erbt von
  // VirtIntf.TInterface, dessen nicht-virtuelles Free Release ruft.
  // FreeAndNil(FCompileNotifier) riefe TObject.Free und zerstoerte sofort.
  // Ohne Fix gruen angeboten (keine eigene Free IN der Unit, kein P-Typ).
  AssertNoHelp(OwnerUnit('System.SysUtils, ToolIntf',
    '  TGxBoostNotifier = class(TIAddInNotifier)' + #13#10 + '  end;',
    'FX: TGxBoostNotifier', []), fkFreeAndNilHint, 'Open Tools API');
end;

procedure TTestRdxFreeGatesDetector.Sca085_OtaForeignType_NoHelp;
begin
  // GExperts GX_Search.pas:315 (rwE29, Fehler): 'FModuleIntf:
  // TIModuleInterface' aus EditIntf direkt - ToolServices liefert ein
  // referenzgezaehltes Modul-Interface, Free ist dort Release.
  AssertNoHelp(OwnerUnit('System.SysUtils, EditIntf', '',
    'FX: TIModuleInterface', []), fkFreeAndNilHint, 'Open Tools API');
end;

procedure TTestRdxFreeGatesDetector.Sca085_CommentNamesFreeAndNil_NoHelp;
begin
  // HeidiSQL SynEdit.pas:1592 (rwE29, Fehler): der Kommentar direkt ueber
  // der Freigabe verbietet FreeAndNil - Code liest das Feld waehrend der
  // Zerstoerung. Ohne Fix angeboten (der Kommentar zaehlt nie als Code).
  AssertNoHelp(OwnerUnit('System.SysUtils, System.Classes', '',
    'FX: TList', ['', '  // do not use FreeAndNil, it first nils and then '
    + 'frees causing problems with', '  // code accessing FX while '
    + 'destruction']), fkFreeAndNilHint, 'Kommentar in Zeile');
end;

procedure TTestRdxFreeGatesDetector.Sca085_PlainHeritageAndComment_Helps;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Gegenprobe zu den drei Sperren: eine Vorfahrenkette DIESER Unit ohne
  // Open-Tools-Klasse (TB = class(TA), TA = class) und ein Kommentar ohne
  // FreeAndNil darueber - die Hilfe bleibt.
  Src := OwnerUnit('System.SysUtils', '  TA = class' + #13#10 + '  end;'
    + #13#10 + '  TB = class(TA)' + #13#10 + '  end;', 'FX: TB',
    ['  // free the helper']);
  O := PlanAt(Src, 't.pas', fkFreeAndNilHint, LineOfOrFail(Src, '  FX.Free;'));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(StringReplace(Src, '  FX.Free;' + #13#10 + '  FX := nil;',
    '  FreeAndNil(FX);', []), Apply(Src, O.Edits));
end;

{ ---- SCA139 ---- }

procedure TTestRdxFreeGatesDetector.Sca139_PointerAlias_NoHelp;
begin
  // 'PFoo = ^TFoo' in dieser Unit, TFoo aus einer anderen: bis Charge FB
  // wertete die Typ-Sperre (damals DeclaresValueType, heute
  // TRdxTypeProof.DeclaresNonClassType) den Zeiger nicht (keine eigene Free
  // in der Unit) - FreeAndNil(FFoo) haette angeboten werden.
  AssertNoHelp(HolderUnit('  PFoo = ^TFoo;', 'FFoo: PFoo;', 'FFoo.Free;'),
    fkFreeWithoutNil, 'kein Objekt');
end;

procedure TTestRdxFreeGatesDetector.Sca139_ForeignPointerName_NoHelp;
begin
  // Gegenpruefer R3 (2): PSSL_CTX aus mormot.lib.openssl11.
  AssertNoHelp(HolderUnit('', 'FCtx: PSSL_CTX;', 'FCtx.Free;'),
    fkFreeWithoutNil, 'Zeiger');
end;

procedure TTestRdxFreeGatesDetector.Sca139_ConstParam_NoHelp;
begin
  // doublecmd us3client.pas:616 ('procedure TS3Buckets.add(const bucket:
  // TS3Bucket); .. bucket.Free;'): FPC 'Can''t assign values to const
  // variable', Delphi bis 10.3 E2197; ab 10.4 nur die lokale Kopie nil.
  AssertConstParamNoHelp(BucketsUnit('const ABucket'));
end;

procedure TTestRdxFreeGatesDetector.Sca139_VarParam_Helps;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Gegenprobe: ein var-Parameter IST die Variable des Aufrufers -
  // FreeAndNil(ABucket) bleibt die Hilfe.
  Src := BucketsUnit('var ABucket');
  O := PlanAt(Src, 't.pas', fkFreeWithoutNil,
    LineOfOrFail(Src, 'ABucket.Free;'));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(StringReplace(Src, 'ABucket.Free;', 'FreeAndNil(ABucket);',
    []), Apply(Src, O.Edits));
end;

{ ---- SCA147/SCA164 (R2-07) ---- }

// Eine Klasse mit einer unbenutzten privaten Methode Dead (SCA147).
function DeadMethodUnit: string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  private', '    procedure Dead;', '  public', '    procedure Run;',
    '  end;', 'implementation', 'procedure TFoo.Dead;', 'begin', 'end;',
    'procedure TFoo.Run;', 'begin', 'end;', 'end.']);
end;

procedure TTestRdxFreeGatesDetector.Sca147_UncPath_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Bis Charge FB las die Hilfe auf jeder Unit .dfm/.fmx/.lfm daneben
  // (FormReason: dreimal FileExists im Hauptthread) - auch auf einer
  // Freigabe, die nicht antwortet.
  Src := DeadMethodUnit;
  O := PlanAt(Src, UNC_FILE, fkUnusedPrivateMethod,
    LineOfOrFail(Src, '    procedure Dead;'));
  Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzpfad');
  Assert.IsTrue(Pos('Netzpfad', O.Reason) > 0, O.Reason);
  // Dieselbe Unit lokal: die Hilfe bleibt.
  O := PlanAt(Src, 't.pas', fkUnusedPrivateMethod,
    LineOfOrFail(Src, '    procedure Dead;'));
  Assert.IsTrue(O.Enabled, O.Reason);
end;

procedure TTestRdxFreeGatesDetector.Sca164_UncPathWithInclude_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Mit einem Include vor implementation liest die Hilfe es neben der Unit
  // (IncludeCheck) - bis Charge FB auch auf einem Netzpfad.
  Src := Join(['unit t;', 'interface', 'uses System.SysUtils;',
    '{$I defs.inc}', 'procedure Run;', 'implementation', 'procedure Dead;',
    'begin', 'end;', 'procedure Run;', 'begin', 'end;', 'end.']);
  O := PlanAt(Src, UNC_FILE, fkUnusedRoutine,
    LineOfOrFail(Src, 'procedure Dead;'));
  Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzpfad');
  Assert.IsTrue(Pos('Netzpfad', O.Reason) > 0, O.Reason);
end;

{ ---- Pin: strenger Resolver (missed R2(3)) ---- }

procedure TTestRdxFreeGatesDetector.Sca072_UnitGlobalShadowedByInherited_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // In TForm1.Check bindet 'Visible' an Self.Visible (TControl, andere
  // Unit), nicht an das Unit-Global: DeclaredTypeOf liefert dort '' (ein
  // Vorfahr von ausserhalb kann jeden Namen verdecken) - kein Beweis. In
  // der freien Routine gilt das Global.
  Src := Join(['unit t;', 'interface', 'uses Vcl.Forms;', 'type',
    '  TForm1 = class(TForm)', '  public', '    procedure Check;', '  end;',
    'var', '  Visible: Boolean;', 'procedure Free2;', 'implementation',
    'procedure TForm1.Check;', 'begin', '  if Visible = True then // method',
    '    Close;', 'end;', 'procedure Free2;', 'begin',
    '  if Visible = True then // free', '    Exit;', 'end;', 'end.']);
  O := PlanAt(Src, 't.pas', fkRedundantBoolean, LineOfOrFail(Src, '// method'));
  Assert.IsFalse(O.Enabled, 'Methode einer TForm-Ableitung');
  Assert.IsTrue(Pos('nicht als Boolean bewiesen', O.Reason) > 0, O.Reason);
  O := PlanAt(Src, 't.pas', fkRedundantBoolean, LineOfOrFail(Src, '// free'));
  Assert.IsTrue(O.Enabled, O.Reason);
end;

{ ---- Nachpruefung FB ----
  Gegen den ersten Stand der Charge (3d753de6) rot: dort bot der Laeufer
  die Hilfe an (F4, C21) bzw. nannte '\\?\C:\..' einen Netzpfad (N1). Die
  Textteile laufen woertlich extrahiert auch unter FPC (Nachbesserung,
  gprobe: F4/F9/F11/F12, C21/C22/C23, N1/N7/N8/N9). }

procedure TTestRdxFreeGatesDetector.Sca139_ForeignPointerBehindUnitAlias_NoHelp;
begin
  // gprobe F4: 'PMyKey = PEVP_PKEY' - der Alias steht in dieser Unit, sein
  // Ziel ist ein fremder Zeiger. Bis dahin galt PMyKey als Typ der Unit,
  // nach dem Konventionsnamen wurde nicht gefragt.
  AssertNoHelp(HolderUnit('  PMyKey = PEVP_PKEY;', 'FKey: PMyKey;',
    'FKey.Free;'), fkFreeWithoutNil, 'Typ PEVP_PKEY');
end;

procedure TTestRdxFreeGatesDetector.Sca139_ConstParam_AttributeOnHeadLine_NoHelp;
begin
  // gprobe C21: ein Attribut vor dem Kopf auf DERSELBEN Zeile - die Zeile
  // galt nicht als Kopf, FreeAndNil(ABucket) blieb die Hilfe.
  AssertConstParamNoHelp(StringReplace(BucketsUnit('const ABucket'),
    'procedure TBuckets.Add(', '[Weak] procedure TBuckets.Add(', []));
end;

procedure TTestRdxFreeGatesDetector.Sca147_Win32NamespacePaths;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // gprobe N1: '\\?\C:\..' (lange Pfade) ist lokal - die Hilfe bleibt; bis
  // dahin hiess er "Netzpfad". '\\?\UNC\srv\..' ist der Netzpfad '\\srv\..'.
  Src := DeadMethodUnit;
  O := PlanAt(Src, LONG_PATH_PREFIX + TempName('rdx_fb_ns_', '.pas'),
    fkUnusedPrivateMethod, LineOfOrFail(Src, '    procedure Dead;'));
  Assert.IsTrue(O.Enabled, O.Reason);
  O := PlanAt(Src, UNC_NS_FILE, fkUnusedPrivateMethod,
    LineOfOrFail(Src, '    procedure Dead;'));
  Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzpfad');
  Assert.IsTrue(Pos('Netzpfad \\rdx-fb-nohost\share\src', O.Reason) > 0,
    O.Reason);
end;

{ ---- Gegenpruefung V-B2S-3 ---- }

procedure TTestRdxFreeGatesDetector.Sca147_RemoteDrive_NoHelp;
var
  Src, QFile : string;
  O          : TRdxFixOutcome;
begin
  // Der Laufwerks-Zweig von NetworkPathReason (uRdxFixTable, seit Charge
  // B2S-a ueber uRdxPaths.RemoteDriveOf; seit Charge G7 je Dateiart ein
  // Satz in R_REMOTE_READS): auf einem Netzlaufwerk liest die
  // Hilfe keine Formdatei neben der Unit, und der Grund nennt das
  // Laufwerk - auch lang geschrieben ('\\?\Q:\..'), dort ohne den Vorsatz.
  // Q: ist eines nur ueber die Naht; der Pfad besteht aus Teilen (ein
  // Literal waere ein SCA016-Fund im Selbstscan).
  Src := DeadMethodUnit;
  QFile := DRIVE_Q + PathDelim + 'src' + PathDelim + 't.pas';
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    O := PlanAt(Src, QFile, fkUnusedPrivateMethod,
      LineOfOrFail(Src, '    procedure Dead;'));
    Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzlaufwerk');
    Assert.IsTrue(Pos('Netzpfad Q: - die Hilfe liest dort keine Formdateien',
      O.Reason) > 0, O.Reason);
    O := PlanAt(Src, LONG_PATH_PREFIX + QFile, fkUnusedPrivateMethod,
      LineOfOrFail(Src, '    procedure Dead;'));
    Assert.IsFalse(O.Enabled, 'keine Hilfe, auch lang geschrieben');
    Assert.IsTrue(Pos('Netzpfad Q: - die Hilfe liest dort keine Formdateien',
      O.Reason) > 0, O.Reason);
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

{ ---- rwE33 Stufe 5: FreeAndNil schon im Code ---- }

const
  // Dev-Cpp InstallWizards.pas (minimiert; RDX_W/RDX_L statt WIN32/LINUX,
  // die die Ein-Zweig-Sicht nicht setzt - der Baum sieht keinen der
  // Bloecke): System.SysUtils steht in uses nur unter zwei Bloecken ohne
  // {$ELSE}, der erste Eintrag in Zeile KNOWN_USES_LINE. %s: vor den
  // Methoden, Rumpf von TFoo.Drop, Rumpf von TFoo.Done (die Stelle), vor
  // 'end.'.
  UNIT_KNOWN =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  System.Classes'#13#10 +
    '{$IFDEF RDX_W}'#13#10 +
    '  , Winapi.Windows, System.SysUtils'#13#10 +
    '{$ENDIF}'#13#10 +
    '{$IFDEF RDX_L}'#13#10 +
    '  , System.SysUtils'#13#10 +
    '{$ENDIF}'#13#10 +
    '  ;'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FList: TList;'#13#10 +
    '  public'#13#10 +
    '    procedure Done;'#13#10 +
    '    procedure Drop(var AObj: TObject);'#13#10 +
    '    procedure Changed;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '%s'#13#10 +
    'procedure TFoo.Drop(var AObj: TObject);'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'procedure TFoo.Done;'#13#10 +
    'begin'#13#10 +
    '%s'#13#10 +
    'end;'#13#10 +
    'procedure TFoo.Changed;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    '%s'#13#10 +
    'end.';
  KNOWN_USES_LINE = 6;
  // Der Rumpf von TFoo.Done fuer SCA085 bzw. SCA139.
  DONE_085 = '  FList.Free;'#13#10'  FList := nil;';
  DONE_139 = '  FList.Free;'#13#10'  Changed;';
  // Ein unqualifizierter Aufruf im Rumpf von TFoo.Drop.
  DROP_CALL = '  FreeAndNil(AObj);';

// Die Hilfe zum ersten Fund der Art AKind in ASource.
function PlanKnown(const ASource: string; AKind: TFindingKind): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet: ' + ASource);
  Result := PlanFixIn(ASource, 't.pas', AKind, Seen[0]);
end;

// Die Hilfe ist frei, schreibt AFrom -> ATo und fasst uses nicht an.
procedure AssertKnownHelps(const ASource: string; AKind: TFindingKind;
  const AFrom, ATo: string);
var
  O : TRdxFixOutcome;
begin
  O := PlanKnown(ASource, AKind);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, Pos(' + uses', O.Hint), O.Hint);
  Assert.AreEqual(StringReplace(ASource, AFrom, ATo, []), Apply(ASource,
    O.Edits));
end;

// Gesperrt wie vor rwE33: "steht nur unter bedingter Uebersetzung".
procedure AssertKnownLocked(const ASource: string; const AWhy: string);
var
  O : TRdxFixOutcome;
begin
  O := PlanKnown(ASource, fkFreeAndNilHint);
  Assert.IsFalse(O.Enabled, AWhy);
  Assert.AreEqual(_(R_USES_ONLY_CONDITIONAL, ['System.SysUtils',
    KNOWN_USES_LINE, MsgByHand]), O.Reason, AWhy);
  Assert.AreEqual<Integer>(0, Length(O.Edits), AWhy);
end;

procedure TTestRdxFreeKnownDetector.Sca085_FreeAndNilCalled_Helps;
begin
  // Vor dem Fix gesperrt: "System.SysUtils steht in uses nur unter
  // bedingter Uebersetzung (Zeile 6), nicht in jedem Zweig um diese
  // Stelle" - obwohl TFoo.Drop FreeAndNil schon aufruft (im Korpus
  // cleanup, Zeile 265, und Zeile 476/738).
  AssertKnownHelps(Format(UNIT_KNOWN, ['', DROP_CALL, DONE_085, '']),
    fkFreeAndNilHint, DONE_085, '  FreeAndNil(FList);');
end;

procedure TTestRdxFreeKnownDetector.Sca085_FreeAndNilCalledInSiteBranch_Helps;
begin
  // Aufruf und Stelle im selben Zweig ('{$IFNDEF RDX_Y}' um alle Methoden
  // - die Ein-Zweig-Sicht liest ihn, der Detektor meldet): wo die Stelle
  // uebersetzt wird, auch der Aufruf. Vor dem Fix gesperrt wie oben.
  AssertKnownHelps(Format(UNIT_KNOWN, ['{$IFNDEF RDX_Y}', DROP_CALL, DONE_085,
    '{$ENDIF}']), fkFreeAndNilHint, DONE_085, '  FreeAndNil(FList);');
end;

procedure TTestRdxFreeKnownDetector.Sca085_FreeAndNilNotProven_Locked;
begin
  // Gegenproben (auch vor dem Fix gesperrt, mit demselben Grund): kein
  // Aufruf, der dort uebersetzt wird, wo die Stelle steht, bzw. keiner,
  // der sicher die Routine auf Unit-Ebene meint.
  AssertKnownLocked(Format(UNIT_KNOWN, ['', '', DONE_085, '']),
    'kein Aufruf');
  AssertKnownLocked(Format(UNIT_KNOWN, ['', '{$IFDEF RDX_D}'#13#10 + DROP_CALL
    + #13#10'{$ENDIF}', DONE_085, '']), 'Aufruf nur in einem anderen Zweig');
  AssertKnownLocked(Format(UNIT_KNOWN, ['', '  // FreeAndNil(AObj);'#13#10
    + '  { FreeAndNil(AObj); }', DONE_085, '']), 'Aufruf nur im Kommentar');
  AssertKnownLocked(Format(UNIT_KNOWN, ['', '  Self.FreeAndNil(AObj);',
    DONE_085, '']), 'Aufruf nur qualifiziert');
  AssertKnownLocked(Format(UNIT_KNOWN, ['procedure FreeAndNil(var AObj);'
    + #13#10'begin'#13#10'end;', DROP_CALL, DONE_085, '']),
    'eigene FreeAndNil der Unit');
  // Review e/HilfeFixU (MINOR 1/2): der Aufruf nur in einer Methode einer
  // ANDEREN Klasse (TOther koennte ein geerbtes Member FreeAndNil haben)
  // bzw. eine Variable FreeAndNil in der Unit - vor dem Nachzug frei.
  AssertKnownLocked(Format(UNIT_KNOWN, [Join(['type', '  TOther = class',
    '    procedure Run(var AObj: TObject);', '  end;',
    'procedure TOther.Run(var AObj: TObject);', 'begin', DROP_CALL, 'end;']),
    '', DONE_085, '']), 'Aufruf nur in einer anderen Klasse');
  AssertKnownLocked(Format(UNIT_KNOWN, [Join(['var',
    '  FreeAndNil: procedure(var AObj);']), DROP_CALL, DONE_085, '']),
    'Variable FreeAndNil der Unit');
end;

procedure TTestRdxFreeKnownDetector.Sca139_FreeAndNilCalled_Helps;
begin
  // Vor dem Fix gesperrt wie SCA085 (dieselbe uses-Ergaenzung).
  AssertKnownHelps(Format(UNIT_KNOWN, ['', DROP_CALL, DONE_139, '']),
    fkFreeWithoutNil, '  FList.Free;', '  FreeAndNil(FList);');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFreeGatesDetector);
  TDUnitX.RegisterTestFixture(TTestRdxFreeKnownDetector);

end.
