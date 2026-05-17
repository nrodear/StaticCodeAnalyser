unit uTestPublicMemberWithoutDoc;

// Tests fuer TPublicMemberWithoutDocDetector (SCA117).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPublicMemberWithoutDoc = class
  public
    [Test] procedure PublicMethodWithoutDoc_Reported;
    [Test] procedure PublicMethodWithXmlDoc_NotReported;
    [Test] procedure PublicMethodWithBraceComment_NotReported;
    [Test] procedure PublicMethodWithLineComment_NotReported;
    [Test] procedure PrivateMethodWithoutDoc_NotReported;
    [Test] procedure CreateDestroy_AlwaysSkipped;
    [Test] procedure PublishedMethod_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPublicMemberWithoutDoc.PublicMethodWithoutDoc_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPublicMemberWithoutDoc) >= 1);
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.PublicMethodWithXmlDoc_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    /// <summary>Starts the worker.</summary>'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc));
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.PublicMethodWithBraceComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    { Startet den Worker }'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc));
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.PublicMethodWithLineComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    // Startet den Worker - idempotent'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc));
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.PrivateMethodWithoutDoc_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure InternalRun;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc));
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.CreateDestroy_AlwaysSkipped;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc));
  finally F.Free; end;
end;

procedure TTestPublicMemberWithoutDoc.PublishedMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TForm1 = class'#13#10 +
  '  published'#13#10 +
  '    procedure Button1Click(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkPublicMemberWithoutDoc),
    'published-Methoden sind DFM-Streaming, kein Doku-Befund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPublicMemberWithoutDoc);

end.
