unit uVnpProbe;

// VarNameProject - Sonden OHNE Sync-Sitzung (Recherche 2026-10-11, Mess-
// punkte M10 und M21), damit die Varianten auf gesicherten Grundlagen
// stehen:
//   ProbeCaret        In welcher Einheit zaehlt TOTACharPos.CharIndex -
//                     UTF-8-Bytes oder Zeichen? Die ToolsAPI sagt es nicht,
//                     GExperts rechnet in Bytes, andere Quellen legen
//                     Zeichen nahe. Caret hinter das Euro-Zeichen in
//                     demo/VarNameDemoUmlaut.pas setzen und die beiden
//                     Lesarten im Protokoll vergleichen.
//   ProbeCreateClass  Welche Interfaces liefert IOTACodeTemplateServices.
//                     CreateClass(GUID) - undokumentiert; Variante A setzt
//                     voraus, dass Sync-Punkte darunter sind.

interface

uses
  ToolsAPI;

procedure ProbeCaret;
procedure ProbeCreateClass;
// Zeile ARow frisch aus dem Puffer (UTF-8 gelesen) - fuer den Abgleich
// "was steht wirklich da" nach dem Schreiben und nach dem Sitzungsstart.
function ReadRow(const AView: IOTAEditView; ARow: Integer): string;

implementation

uses
  System.SysUtils, CodeTemplateAPI, uVnpPlan, uVnpLog;

// Die Zeile ab der Pufferposition AStart (bis vor CR/LF), UTF-8 gelesen.
function ReadLineAt(const ABuffer: IOTAEditBuffer; AStart: Integer): string;
const
  MAX_LINE = 4096;
var
  Reader : IOTAEditReader;
  Bytes  : TBytes;
  Got, n : Integer;
begin
  Reader := ABuffer.CreateReader;
  SetLength(Bytes, MAX_LINE);
  Got := Reader.GetText(AStart, PAnsiChar(@Bytes[0]), MAX_LINE);
  Reader := nil;
  n := 0;
  while (n < Got) and not (Bytes[n] in [10, 13]) do
    Inc(n);
  Result := TEncoding.UTF8.GetString(Bytes, 0, n);
end;

function ReadRow(const AView: IOTAEditView; ARow: Integer): string;
var
  LineStart : TOTACharPos;
begin
  // CharIndex 0 ist in Bytes und Zeichen dasselbe - CharPosToPos liefert
  // den Zeilenanfang hier richtig.
  LineStart.CharIndex := 0;
  LineStart.Line := ARow;
  Result := ReadLineAt(AView.Buffer, AView.CharPosToPos(LineStart));
end;

procedure ProbeCaret;
var
  Svc       : IOTAEditorServices;
  View      : IOTAEditView;
  EdPos     : TOTAEditPos;
  Back      : TOTAEditPos;
  CharPos   : TOTACharPos;
  LineStart : TOTACharPos;
  Linear    : Integer;
  Start     : Integer;
  Line      : string;
begin
  VnpLog('=== Sonde Caret (M10: CharIndex Bytes oder Zeichen?) ===');
  if not Supports(BorlandIDEServices, IOTAEditorServices, Svc)
     or (Svc.TopView = nil) then
  begin
    VnpLog('Abbruch: keine Editoransicht');
    Exit;
  end;
  View := Svc.TopView;
  EdPos := View.CursorPos;
  CharPos.CharIndex := 0;
  CharPos.Line := EdPos.Line;
  View.ConvertPos(True, EdPos, CharPos);
  LineStart.CharIndex := 0;
  LineStart.Line := CharPos.Line;
  Linear := View.CharPosToPos(CharPos);
  Start := View.CharPosToPos(LineStart);
  Line := ReadLineAt(View.Buffer, Start);
  Back.Col := 1;
  Back.Line := CharPos.Line;
  View.ConvertPos(False, Back, CharPos);
  VnpLog('Anzeige %d:%d -> CharPos (Zeile %d, CharIndex %d) -> zurueck '
    + 'Anzeige %d:%d', [EdPos.Line, EdPos.Col, CharPos.Line,
    CharPos.CharIndex, Back.Line, Back.Col]);
  VnpLog('Puffer: Caret %d, Zeilenanfang %d, Differenz %d Bytes',
    [Linear, Start, Linear - Start]);
  VnpLog('Zeile: "%s"', [Line]);
  VnpLog('Vor dem Caret, CharIndex als ZEICHEN gelesen: "%s"',
    [Copy(Line, 1, CharPos.CharIndex)]);
  VnpLog('Vor dem Caret, CharIndex als BYTES gelesen:   "%s"',
    [Copy(Line, 1, CharColOfByte(Line, CharPos.CharIndex) - 1)]);
  VnpLog('Vor dem Caret, Pufferdifferenz als Bytes:     "%s"',
    [Copy(Line, 1, CharColOfByte(Line, Linear - Start) - 1)]);
  VnpLog('-> Die Zeile, die genau bis zum Caret reicht, nennt die Einheit.');
end;

// CreateClass(AIID): nil, Ausnahme oder welche bekannten Interfaces?
procedure TryClass(const ASvc: IOTACodeTemplateServices; const AName: string;
  const AIID: TGUID);
var
  Obj : IInterface;
  S   : string;
begin
  try
    Obj := ASvc.CreateClass(AIID);
  except
    // Messung: jede Ausnahme gehoert ins Protokoll.
    on E: Exception do
    begin
      VnpLog('  %s: Ausnahme %s: %s', [AName, E.ClassName, E.Message]);
      Exit;
    end;
  end;
  if Obj = nil then
  begin
    VnpLog('  %s: nil', [AName]);
    Exit;
  end;
  S := '';
  if Supports(Obj, IOTASyncEditPoints) then S := S + ' IOTASyncEditPoints';
  if Supports(Obj, IOTASyncEditPoint) then S := S + ' IOTASyncEditPoint';
  if Supports(Obj, IOTASyncEditPoint100) then S := S + ' IOTASyncEditPoint100';
  if Supports(Obj, IOTACodeTemplate) then S := S + ' IOTACodeTemplate';
  if Supports(Obj, IOTACodeTemplatePoint) then S := S + ' IOTACodeTemplatePoint';
  if Supports(Obj, IOTACodeTemplateObject) then
    S := S + ' IOTACodeTemplateObject';
  VnpLog('  %s: Objekt, unterstuetzt:%s', [AName, S]);
end;

procedure ProbeCreateClass;
var
  Svc : IOTACodeTemplateServices;
begin
  VnpLog('=== Sonde CreateClass (M21) ===');
  if not Supports(BorlandIDEServices, IOTACodeTemplateServices, Svc) then
  begin
    VnpLog('BorlandIDEServices kennt IOTACodeTemplateServices nicht');
    Exit;
  end;
  TryClass(Svc, 'IOTASyncEditPoints', IOTASyncEditPoints);
  TryClass(Svc, 'IOTASyncEditPoint', IOTASyncEditPoint);
  TryClass(Svc, 'IOTASyncEditPoint100', IOTASyncEditPoint100);
  TryClass(Svc, 'IOTACodeTemplate', IOTACodeTemplate);
  TryClass(Svc, 'IOTACodeTemplatePoint', IOTACodeTemplatePoint);
  TryClass(Svc, 'IOTACodeTemplateObject', IOTACodeTemplateObject);
end;

end.
