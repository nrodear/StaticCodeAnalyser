unit uDateFormatSettings;

// Detektor: `StrToDate(s)` / `DateToStr(d)` / `StrToFloat(s)` / `FloatToStr(d)`
// ohne explizite TFormatSettings - haengt am System-Locale, crasht bei
// Maschine mit anderem DateSeparator/DecimalSeparator als die Test-Box.
//
// Pattern (Bug):
//   d := StrToDate(UserInput);           // <-- locale-abhaengig
//   s := DateToStr(Now);                 // <-- locale-abhaengig
//
// Korrekt:
//   d := StrToDate(UserInput, FormatSettings);
//   s := DateToStr(Now, FormatSettings);
//
// Folge: Auf einem Entwickler-Rechner mit DE-Locale (DateSeparator='.')
// wird '01.05.2026' geparsed; auf einem Production-Server mit EN-Locale
// (DateSeparator='/') schlaegt der gleiche String mit EConvertError fehl.
// Ueblicher silent-Bug-Pfad fuer Datenbank-/JSON-Pipelines mit gemischter
// Locale-Umgebung.
//
// Erkennung (AST-basiert):
//   * Walker iteriert nkCall-Knoten.
//   * Match wenn der Call-Name das Muster `<FuncName>(<args>)` hat mit
//     <FuncName> in der Bekannten-Liste (StrToDate, StrToTime,
//     StrToDateTime, DateToStr, TimeToStr, DateTimeToStr,
//     StrToFloat, FloatToStr, StrToInt-NICHT - Integer hat kein Locale).
//   * Pruefen ob in der Argument-Liste ein 'FormatSettings'-Identifier
//     vorkommt. Falls ja -> kein Finding. Falls nicht -> Finding.
//
// Bewusst NICHT Finding:
//   * `StrToDate(s, MyFormatSettings)` - hat explizites Settings.
//   * `StrToInt(s)` - Integer-Parsing hat keine Locale-Abhaengigkeit
//     (Vorzeichen + Ziffern).
//
// Sonar-Pendant: DateFormatSettingsCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   DateFormatSettingsCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDateFormatSettingsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  // Locale-abhaengige RTL-Funktionen. Klein-geschrieben fuer Lookup.
  LOCALE_DEPENDENT: array of string = [
    'strtodate', 'strtotime', 'strtodatetime',
    'datetostr', 'timetostr', 'datetimetostr',
    'strtofloat', 'strtocurr', 'floattostr', 'currtostr',
    'formatdatetime', 'formatfloat', 'formatcurr'
  ];

// Extrahiert den Function-Namen aus einem nkCall-Namen.
// 'Foo(a, b)' -> 'Foo'; 'Foo' -> 'Foo'.
function CallFuncName(const CallName: string): string;
var
  i : Integer;
  C : Char;
begin
  Result := '';
  for i := 1 to Length(CallName) do
  begin
    C := CallName[i];
    if ((C >= 'A') and (C <= 'Z')) or
       ((C >= 'a') and (C <= 'z')) or
       ((C >= '0') and (C <= '9')) or (C = '_') then
      Result := Result + C
    else
      Exit;
  end;
end;

function IsLocaleDependentCall(const FuncName: string): Boolean;
var
  i : Integer;
  Low : string;
begin
  Result := False;
  Low := LowerCase(FuncName);
  for i := 0 to High(LOCALE_DEPENDENT) do
    if Low = LOCALE_DEPENDENT[i] then Exit(True);
end;

// True wenn der Call-Ausdruck einen Identifier mit 'formatsettings' (case-
// insensitive) in seiner Argument-Liste hat.
function MentionsFormatSettings(const CallName: string): Boolean;
begin
  Result := Pos('formatsettings', LowerCase(CallName)) > 0;
end;

// Pruefen ob `Text` (nkCall.Name oder nkAssign.TypeRef) einen locale-
// abhaengigen Call ohne explizite TFormatSettings enthaelt. Wird fuer
// beide Node-Sorten gerufen - bei nkAssign liegt die RHS in TypeRef,
// dort koennen Calls wie `dt := StrToDate('1.1.2025')` stehen.
procedure CheckCallText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  F        : TLeakFinding;
  MethName : string;
  FuncName : string;
begin
  FuncName := CallFuncName(Text);
  if not IsLocaleDependentCall(FuncName) then Exit;
  if MentionsFormatSettings(Text) then Exit;
  if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
  else MethName := '';
  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := MethName;
  F.LineNumber := IntToStr(Node.Line);
  F.MissingVar := Format(
    '%s called without explicit TFormatSettings - depends on system locale',
    [FuncName]);
  F.SetKind(fkDateFormatSettings);
  Results.Add(F);
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  i        : Integer;
  NextMeth : TAstNode;
begin
  if Node = nil then Exit;
  case Node.Kind of
    nkCall:
      // Bare call, z.B. `Writeln(DateToStr(d));`
      CheckCallText(Node.Name, Node, CurrentMethod, FileName, Results);
    nkAssign:
      // `s := DateToStr(d);` - der Parser legt die RHS in TypeRef ab und
      // erzeugt KEINEN separaten nkCall-Knoten. Sonst silent miss
      // (Audit V5, 2026-05-30).
      CheckCallText(Node.TypeRef, Node, CurrentMethod, FileName, Results);
  end;
  if Node.Kind = nkMethod then NextMeth := Node else NextMeth := CurrentMethod;
  for i := 0 to Node.Children.Count - 1 do
    WalkAndCheck(Node.Children[i], NextMeth, FileName, Results);
end;

class procedure TDateFormatSettingsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
