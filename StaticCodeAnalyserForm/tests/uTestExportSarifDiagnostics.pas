unit uTestExportSarifDiagnostics;

// Tests fuer runs[0].invocations[].toolExecutionNotifications im
// SARIF-Export.
//
// Ein Lesefehler sagt etwas ueber die VOLLSTAENDIGKEIT des Laufs, nicht
// ueber den Quelltext. Seit 2026-08-08 steht er zusaetzlich an dem Ort,
// den SARIF dafuer vorsieht - das result bleibt bewusst daneben bestehen.
//
// Eigene Unit statt weiterer Tests in uTestExportSARIF: die Fixture dort
// war mit diesen fuenf Faellen auf ueber zwanzig Methoden gewachsen und
// schlug im eigenen GodClass-Detektor auf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExportSarifDiagnostics = class
  public
    [Test] procedure ReadError_AppearsAsNotificationAndAsResult;
    [Test] procedure ExecutionSuccessfulStaysTrueWithReadErrors;
    [Test] procedure NoRunDiagnostics_NotificationsArrayIsEmpty;
    [Test] procedure EncodingFindingIsNotARunDiagnostic;
    [Test] procedure DocumentStaysParseableWithNotificationsAndResults;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.JSON,
  uMethodd12, uSCAConsts, uExportSARIF;

const
  // Wiederholte Literale als Konstanten - sonst zaehlt sie der eigene
  // DuplicateString-Detektor.
  VER      = '0.9.9';
  TOOL     = 'TestTool';
  FILE_BAD = 'src\Kaputt.pas';
  FILE_OK  = 'src\Gut.pas';
  MSG_BAD  = 'Datei nicht lesbar';
  KEY_RUNS = 'runs';
  KEY_RES  = 'results';
  KEY_NOTE = 'toolExecutionNotifications';
  MSG_PARSE = 'SARIF parst nicht';
  MSG_LEAK  = 'leak';

function MakeFinding(K: TFindingKind; const AFile: string;
  ALine: Integer; const AMsg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(K);
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := AMsg;
end;

function RunObj(Root: TJSONObject): TJSONObject;
begin
  Result := Root.GetValue<TJSONArray>(KEY_RUNS).Items[0] as TJSONObject;
end;

function Invocation(Root: TJSONObject): TJSONObject;
var
  Invs : TJSONArray;
begin
  Invs := RunObj(Root).GetValue<TJSONArray>('invocations');
  Assert.IsNotNull(Invs, 'runs[0].invocations[] fehlt');
  Assert.IsTrue(Invs.Count > 0, 'invocations[] ist leer');
  Result := Invs.Items[0] as TJSONObject;
end;

function Notifications(Root: TJSONObject): TJSONArray;
begin
  Result := Invocation(Root).GetValue<TJSONArray>(KEY_NOTE);
  Assert.IsNotNull(Result, 'toolExecutionNotifications[] fehlt');
end;

function ResultCount(Root: TJSONObject): Integer;
begin
  Result := RunObj(Root).GetValue<TJSONArray>(KEY_RES).Count;
end;

{ ---- Tests ---- }

procedure TTestExportSarifDiagnostics.ReadError_AppearsAsNotificationAndAsResult;
// Die Doppelmeldung ist gewollt: das result bleibt, die Notification kommt
// hinzu. Wer eines davon "aufraeumt", faellt hier auf.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Note     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, FILE_BAD, 0, MSG_BAD));
    Root := TJSONObject.ParseJSONValue(
      TSARIFWriter.ToJsonString(Findings, '', VER, TOOL)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_PARSE);
    Assert.AreEqual<Integer>(1, Notifications(Root).Count);
    Note := Notifications(Root).Items[0] as TJSONObject;
    Assert.AreEqual('error', Note.GetValue<string>('level', ''));
    Assert.AreEqual(MSG_BAD,
      (Note.GetValue<TJSONObject>('message')).GetValue<string>('text', ''));
    // Keine erfundene Zeile: region wird bewusst weggelassen, weil alle
    // Erzeuger LineNumber '0' setzen und SARIF dort keine 0 erlaubt.
    Assert.IsFalse(Assigned(Note.GetValue('region')),
      'Notification darf keine region tragen');
    Assert.AreEqual<Integer>(1, ResultCount(Root),
      'das result muss ZUSAETZLICH bestehen bleiben');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSarifDiagnostics.ExecutionSuccessfulStaysTrueWithReadErrors;
// False faerbt bei GitHub Code Scanning den GANZEN Lauf als fehlgeschlagen.
// Eine einzelne unlesbare Datei rechtfertigt das nicht.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Val      : TJSONValue;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, FILE_BAD, 0, MSG_BAD));
    Findings.Add(MakeFinding(fkMemoryLeak, FILE_OK, 12, MSG_LEAK));
    Root := TJSONObject.ParseJSONValue(
      TSARIFWriter.ToJsonString(Findings, '', VER, TOOL)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_PARSE);
    Val := Invocation(Root).GetValue('executionSuccessful');
    // Ueber TJSONBool: der Test nagelt auch fest, dass es ein echtes
    // JSON-Boolean ist und kein String "true".
    Assert.IsTrue(Val is TJSONBool, 'executionSuccessful muss Boolean sein');
    Assert.IsTrue((Val as TJSONBool).AsBoolean,
      'executionSuccessful muss True bleiben');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSarifDiagnostics.NoRunDiagnostics_NotificationsArrayIsEmpty;
// Faengt eine Fehl-Verschachtelung, bei der die Notifications-Schleife
// versehentlich ALLE Findings aufnimmt.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, FILE_OK, 12, MSG_LEAK));
    Root := TJSONObject.ParseJSONValue(
      TSARIFWriter.ToJsonString(Findings, '', VER, TOOL)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_PARSE);
    Assert.AreEqual<Integer>(0, Notifications(Root).Count);
    Assert.AreEqual<Integer>(1, ResultCount(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSarifDiagnostics.EncodingFindingIsNotARunDiagnostic;
// SCA186 traegt denselben FindingType (ftFileError) wie der Lesefehler, ist
// aber ein echter Inhaltsbefund mit Position. Ein Praedikat ueber
// FindingType statt ueber den Kind wuerde ihn hier faelschlich duplizieren -
// genau die Falle in dieser Aenderung.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkSourceInvalidUtf8, FILE_OK, 3, 'utf8'));
    Root := TJSONObject.ParseJSONValue(
      TSARIFWriter.ToJsonString(Findings, '', VER, TOOL)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_PARSE);
    Assert.AreEqual<Integer>(0, Notifications(Root).Count,
      'Encoding-Befund ist KEINE Lauf-Diagnose');
    Assert.AreEqual<Integer>(1, ResultCount(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSarifDiagnostics.DocumentStaysParseableWithNotificationsAndResults;
// Balance-Beweis fuer die Begin/End-Paare des neuen Blocks: der Emitter
// verschluckt ein ueberzaehliges End still und schreibt dafuer kaputtes
// JSON - das faellt erst beim Reparsen auf.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, FILE_BAD, 0, MSG_BAD));
    Findings.Add(MakeFinding(fkMemoryLeak, FILE_OK, 12, MSG_LEAK));
    Findings.Add(MakeFinding(fkFileReadError, 'src\Kaputt2.pas', 0, MSG_BAD));
    Findings.Add(MakeFinding(fkNilDeref, FILE_OK, 7, 'nil'));
    Root := TJSONObject.ParseJSONValue(
      TSARIFWriter.ToJsonString(Findings, '', VER, TOOL)) as TJSONObject;
    Assert.IsNotNull(Root, 'Dokument mit Notifications parst nicht');
    Assert.AreEqual<Integer>(2, Notifications(Root).Count);
    Assert.AreEqual<Integer>(4, ResultCount(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSarifDiagnostics);

end.
