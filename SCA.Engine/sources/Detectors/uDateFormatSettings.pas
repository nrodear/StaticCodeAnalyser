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
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TDateFormatSettingsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedRoutine
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

// True wenn der Call-Ausdruck einen Identifier mit 'formatsettings' bzw. der
// gaengigen Abkuerzung 'fmtsettings' (case-insensitive) in seiner Argument-
// Liste hat. Erfasst 'FormatSettings', 'FFormatSettings', 'AFormatSettings',
// 'LFmtSettings', 'FmtSettings' usw. - alle benennen ein explizit
// uebergebenes TFormatSettings -> kein Locale-Bug.
// 'TFormatSettings.Invariant' / 'DefaultFormatSettings' sind ueber das
// 'formatsettings'-Teilwort ebenfalls abgedeckt.
function MentionsFormatSettings(const CallName: string): Boolean;
var Low : string;
begin
  Low := LowerCase(CallName);
  Result := (Pos('formatsettings', Low) > 0) or (Pos('fmtsettings', Low) > 0);
end;

// Pruefen ob `Text` (nkCall.Name oder nkAssign.TypeRef) IRGENDWO einen
// locale-abhaengigen Call ohne explizite TFormatSettings enthaelt. Frueher
// wurde nur der aeusserste Call-Name (`CallFuncName`) geprueft - damit
// fielen verschachtelte Calls wie `LogIt(StrToDate(s))` durch, weil der
// Outer-Name "LogIt" nicht in der LOCALE_DEPENDENT-Liste steht. Jetzt
// wird mit Wortgrenzen-Suche im gesamten Text gescannt.
procedure CheckCallText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  MethName : string;
  LowText  : string;
  Name     : string;
  HitName  : string;
begin
  if Text = '' then Exit;
  LowText := LowerCase(Text);
  HitName := '';
  for Name in LOCALE_DEPENDENT do
    if TDetectorUtils.ContainsWholeWordLower(Name, LowText) then
    begin
      HitName := Name;
      Break;
    end;
  if HitName = '' then Exit;
  // Defense gegen False-Positive: User reicht explizit TFormatSettings
  // durch ('strtodate(s, FormatSettings)' ist sicher).
  if MentionsFormatSettings(Text) then Exit;
  if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
  else MethName := '';
  Results.Add(TLeakFinding.New(FileName, MethName, Node.Line,
    Format('%s called without explicit TFormatSettings - depends on ' +
           'system locale', [HitName]),
    fkDateFormatSettings));
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS - siehe Audit_jvcl_segfault.
type
  TFrame = record N, M: TAstNode; end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
  NextMeth : TAstNode;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.M := CurrentMethod;
    Stack.Add(F);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case Cur.N.Kind of
        nkCall:   CheckCallText(Cur.N.Name,    Cur.N, Cur.M, FileName, Results);
        nkAssign: CheckCallText(Cur.N.TypeRef, Cur.N, Cur.M, FileName, Results);
      end;
      if Cur.N.Kind = nkMethod then NextMeth := Cur.N else NextMeth := Cur.M;
      for i := Cur.N.Children.Count - 1 downto 0 do
      begin
        F.N := Cur.N.Children[i]; F.M := NextMeth;
        Stack.Add(F);
      end;
    end;
  finally
    Stack.Free;
  end;
end;
{$IF False}
// Original-Recursive-Code zur Referenz - falls Bug im Iterativ.
procedure WalkAndCheckRec(Node, CurrentMethod: TAstNode; const FileName: string;
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
      CheckCallText(Node.TypeRef, Node, CurrentMethod, FileName, Results);
  end;
  if Node.Kind = nkMethod then NextMeth := Node else NextMeth := CurrentMethod;
  for i := 0 to Node.Children.Count - 1 do
    WalkAndCheckRec(Node.Children[i], NextMeth, FileName, Results);
end;
{$IFEND}

class procedure TDateFormatSettingsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
