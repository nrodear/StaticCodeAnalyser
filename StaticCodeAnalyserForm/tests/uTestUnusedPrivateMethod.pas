unit uTestUnusedPrivateMethod;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedPrivateMethod = class
  public
    [Test] procedure UnusedPrivate_Reported;
    [Test] procedure UsedPrivate_NotReported;
    [Test] procedure PublicMethod_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // 2026-06-20: DFM-Event-Handler in private-Section nicht als FP melden.
    [Test] procedure DfmBoundPrivateHandler_NotReported;
    // 2026-07-04: Strip-Konsolidierung (lokale Kopie -> TDetectorUtils).
    // Nagelt die Ist-Semantik fest: Vorkommen in //-Kommentar, Block-
    // Kommentar (mit Quote drin), String-Literal und {$IFDEF}-Direktive
    // zaehlen NICHT als Verwendung.
    [Test] procedure StripSemantics_CommentAndStringUsesDontCount;
    // 2026-07-04: `//` INNERHALB eines String-Literals (inkl. verdoppeltem
    // Quote) darf die Zeile nicht abschneiden - der echte Call dahinter
    // muss weiterhin als Verwendung zaehlen.
    [Test] procedure StripSemantics_CallAfterUrlString_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uAstNode, uParser2,
  uUnusedPrivateMethod,
  uTestFindingHelper;

procedure TTestUnusedPrivateMethod.UnusedPrivate_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UnusedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UnusedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPrivateMethod) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.UsedPrivate_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UsedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UsedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin UsedHelper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.PublicMethod_NotReported;
// Public-Methoden werden NICHT von diesem Detector geprueft - die koennen
// von anderen Units verwendet werden.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure PublicMaybeUnused;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.PublicMaybeUnused;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure Dead;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Dead;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedPrivateMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnusedPrivateMethod finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.DfmBoundPrivateHandler_NotReported;
// Private Methode Button1Click ist Event-Handler im DFM (OnClick = Button1Click).
// Im Pascal-Code wird sie nirgends explizit aufgerufen - klassisches FP-Szenario
// vor dem DFM-Scan-Fix (siehe uUnusedPrivateMethod). Muss jetzt sauber ignoriert
// werden.
const PAS_SRC =
  'unit t; interface'#13#10 +
  'uses Classes, Controls, StdCtrls, Forms;'#13#10 +
  'type'#13#10 +
  '  TFooForm = class(TForm)'#13#10 +
  '    Button1: TButton;'#13#10 +
  '  private'#13#10 +
  '    procedure Button1Click(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  '{$R *.dfm}'#13#10 +
  'procedure TFooForm.Button1Click(Sender: TObject);'#13#10 +
  'begin end;'#13#10 +
  'end.';
const DFM_SRC =
  'object FooForm: TFooForm'#13#10 +
  '  Caption = ''Foo'''#13#10 +
  '  object Button1: TButton'#13#10 +
  '    OnClick = Button1Click'#13#10 +
  '  end'#13#10 +
  'end';
var
  Dir, PasPath, DfmPath : string;
  Parser  : TParser2;
  Root    : TAstNode;
  F       : TObjectList<TLeakFinding>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca_dfmtest_' +
    TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-',''));
  TDirectory.CreateDirectory(Dir);
  try
    PasPath := TPath.Combine(Dir, 'fooform.pas');
    DfmPath := TPath.Combine(Dir, 'fooform.dfm');
    TFile.WriteAllText(PasPath, PAS_SRC, TEncoding.UTF8);
    TFile.WriteAllText(DfmPath, DFM_SRC, TEncoding.UTF8);

    F := TObjectList<TLeakFinding>.Create(True);
    Parser := TParser2.Create;
    try
      Root := Parser.ParseSource(PAS_SRC);
      try
        TUnusedPrivateMethodDetector.AnalyzeUnit(Root, PasPath, F);
      finally
        Root.Free;
      end;
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod),
        'DFM-bound Button1Click darf nicht als unused gemeldet werden');
    finally
      Parser.Free;
      F.Free;
    end;
  finally
    try TDirectory.Delete(Dir, True); except end;
  end;
end;

procedure TTestUnusedPrivateMethod.StripSemantics_CommentAndStringUsesDontCount;
// DeadHelper taucht im Roh-Text 6x auf: Deklaration, Impl-Header,
// //-Kommentar (mit 'Quote'), Block-Kommentar (mit 'Quote), String-Literal,
// {$IFDEF}-Direktive. Nur Deklaration + Impl-Header ueberleben das Strippen
// -> Count 2 (nicht > 2) -> MUSS gemeldet werden. Wuerde irgendeine der
// vier gestrippten Fundstellen faelschlich mitzaehlen, kippte der Test.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure DeadHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  '{$IFDEF DEADHELPER}'#13#10 +
  '{$ENDIF}'#13#10 +
  'procedure TFoo.DeadHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  '// DeadHelper wird nicht mehr gerufen (''legacy'')'#13#10 +
  'begin'#13#10 +
  '  Writeln(''call DeadHelper now'');'#13#10 +
  '  { DeadHelper im Block-Kommentar mit ''Quote }'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPrivateMethod) >= 1,
    'Kommentar-/String-/Direktiven-Vorkommen duerfen nicht als Use zaehlen');
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.StripSemantics_CallAfterUrlString_NotReported;
// Der String ''don''t // stop'' enthaelt ein verdoppeltes Quote UND `//`.
// Wuerde der Stripper das `//` im String als Zeilenkommentar deuten, fiele
// der echte Call `UsedHelper;` dahinter weg -> Count 2 -> False Positive.
// Korrekte Semantik: Call zaehlt, Count 3 (> 2) -> KEIN Fund.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UsedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UsedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  Writeln(''don''''t // stop''); UsedHelper;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod),
    '`//` im String-Literal darf den echten Call dahinter nicht abschneiden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedPrivateMethod);

end.
