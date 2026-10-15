unit uTestRdxFreeGatesDetector;

// Charge FB (Code-Review reDelphix, Bereich R2/R3) gegen die ECHTEN
// Detektoren und den Einstieg des Anbieters (TRdxFixTable.FixFor): die
// Sperren, die im Laeufer bzw. in der Tabelle sitzen und den Quellstellen-
// Dienst (Resolver) brauchen - deshalb nur Delphi (reDelphix.Test), nicht
// im FPC-Pruefstand (dort loest der Stub-Resolver nichts auf). Die reinen
// Textteile pruefen uTestRdxFreeTypes (DeclaresValueType mit Zeiger) und
// die Korpus-Harness der Charge (die Sperr-Funktionen woertlich unter FPC).
//   * SCA085 bekommt die Typ-Sperre von SCA139 (R2-01/R3-01): Zeiger auf
//     ein object mit eigenem Free (mORMot), eine Klasse mit eigener Free
//     (Pool), ein fremder Zeigertyp nach Namenskonvention (PEVP_PKEY).
//   * SCA139: Zeiger-Alias der Unit (missed R2(4)/R3(2)), fremder
//     P-Typ, const-Parameter (R2-03) - ein var-Parameter bleibt Hilfe.
//   * SCA147/SCA164 auf einem Netzpfad lesen keine Form-/Include-Dateien
//     (R2-07).
//   * Pin (missed R2(3)): ein Unit-Global, das wie ein geerbtes Member
//     heisst, ist in einer Methode einer TForm-Ableitung nicht bewiesen -
//     das leistet der strenge Resolver (StrictMemberType) schon.
// Jeder Test ausser den beiden Hilfe-Gegenproben (Sca139_VarParam_Helps,
// Sca072_*) war gegen den Stand 4358b769 rot: dort bot der Laeufer die
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
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts,
  uFreeAndNilHint, uFreeWithoutNil, uUnusedRoutine, uUnusedPrivateMethod,
  uRedundantBoolean,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit;   // TSeen, Join, Detect-/Plan-/Apply-Helfer

const
  // Eine Freigabe, die es nicht gibt: die Hilfen duerfen dort nichts lesen.
  // noinspection HardcodedPath (Testdaten: der Netzpfad IST der Testfall)
  UNC_FILE = '\\rdx-fb-nohost\share\src\t.pas';

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

// Die erste Zeile (1-basiert), die AText enthaelt.
function LineOf(const ASource, AText: string): Integer;
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

{ ---- SCA139 ---- }

procedure TTestRdxFreeGatesDetector.Sca139_PointerAlias_NoHelp;
begin
  // 'PFoo = ^TFoo' in dieser Unit, TFoo aus einer anderen: bis Charge FB
  // wertete DeclaresValueType den Zeiger nicht (keine eigene Free in der
  // Unit) - FreeAndNil(FFoo) haette angeboten werden.
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
  AssertNoHelp(BucketsUnit('const ABucket'), fkFreeWithoutNil,
    'const-Parameter');
end;

procedure TTestRdxFreeGatesDetector.Sca139_VarParam_Helps;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Gegenprobe: ein var-Parameter IST die Variable des Aufrufers -
  // FreeAndNil(ABucket) bleibt die Hilfe.
  Src := BucketsUnit('var ABucket');
  O := PlanAt(Src, 't.pas', fkFreeWithoutNil, LineOf(Src, 'ABucket.Free;'));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(StringReplace(Src, 'ABucket.Free;', 'FreeAndNil(ABucket);',
    []), Apply(Src, O.Edits));
end;

{ ---- SCA147/SCA164 (R2-07) ---- }

procedure TTestRdxFreeGatesDetector.Sca147_UncPath_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Bis Charge FB las die Hilfe auf jeder Unit .dfm/.fmx/.lfm daneben
  // (FormReason: dreimal FileExists im Hauptthread) - auch auf einer
  // Freigabe, die nicht antwortet.
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  private',
    '    procedure Dead;', '  public', '    procedure Run;', '  end;',
    'implementation', 'procedure TFoo.Dead;', 'begin', 'end;',
    'procedure TFoo.Run;', 'begin', 'end;', 'end.']);
  O := PlanAt(Src, UNC_FILE, fkUnusedPrivateMethod,
    LineOf(Src, '    procedure Dead;'));
  Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzpfad');
  Assert.IsTrue(Pos('Netzpfad', O.Reason) > 0, O.Reason);
  // Dieselbe Unit lokal: die Hilfe bleibt.
  O := PlanAt(Src, 't.pas', fkUnusedPrivateMethod,
    LineOf(Src, '    procedure Dead;'));
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
  O := PlanAt(Src, UNC_FILE, fkUnusedRoutine, LineOf(Src, 'procedure Dead;'));
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
  O := PlanAt(Src, 't.pas', fkRedundantBoolean, LineOf(Src, '// method'));
  Assert.IsFalse(O.Enabled, 'Methode einer TForm-Ableitung');
  Assert.IsTrue(Pos('nicht als Boolean bewiesen', O.Reason) > 0, O.Reason);
  O := PlanAt(Src, 't.pas', fkRedundantBoolean, LineOf(Src, '// free'));
  Assert.IsTrue(O.Enabled, O.Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFreeGatesDetector);

end.
