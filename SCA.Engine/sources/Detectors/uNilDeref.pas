unit uNilDeref;

// Detektor fuer potentielle Nil-Dereferenzierungen (Sonar-Regel #3).
//
// Erkennt Variablen, die explizit auf nil gesetzt werden und danach
// ohne zwischenzeitliche Neuzuweisung oder Guard-Pruefung mit einem
// Punkt-Zugriff (Methode/Property) verwendet werden.
//
// Erkannte Guards:
//   - obj := TFoo.Create;        (Neuzuweisung)
//   - if Assigned(obj) then ...  (in If-Bedingung)
//   - if obj <> nil then ...     (in If-Bedingung)
//   - if obj = nil then Exit;    (Early-Exit-Guard)
//   - .Free / .Destroy           (TObject.Free ist nil-safe)
//
// Nicht erkannt (bewusst):
//   - obj.field := nil           (Cleanup-Muster)
//   - Selbstreferenzen (Self.X)

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TNilDerefDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Pruefung ob ein If-Block der Methode einen Guard fuer VarLow enthaelt
    class function HasGuardingIf(MethodNode: TAstNode;
      const VarLow: string; AfterLine, BeforeLine: Integer): Boolean; static;
    // Erkennt ob ein Call ein nil-sicherer Aufruf ist (.Free, .Destroy)
    class function IsNilSafeCall(const CallNameLow,
      VarLow: string): Boolean; static;
  end;

implementation

// noinspection-file ConcatToFormat
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{ Hilfsfunktion: prueft ob in der Bedingung ein Guard fuer varname steht.
  Verwendet TDetectorUtils.ContainsWholeWordLower fuer korrekte Wortgrenzen -
  vorher matchten 'assigned MyVar' faelschlich auch 'assigned MyVarOld'. }
function CondHasGuard(const CondLow, VarLow: string): Boolean;
const
  PATTERNS: array[0..7] of string = (
    // Assigned-Varianten
    'assigned(%s)',
    'assigned( %s )',
    'assigned (%s)',
    'assigned ( %s )',
    'assigned %s',
    // Vergleich mit nil (links und rechts)
    '%s <> nil',
    '%s<>nil',
    'nil <> %s'
  );
var
  Pat: string;
begin
  Result := False;
  for Pat in PATTERNS do
    if TDetectorUtils.ContainsWholeWordLower(Format(Pat, [VarLow]), CondLow) then
      Exit(True);
  // Sonderfall ohne Whitespaces - 'nil<>' braucht keine eigene Wortgrenze rechts
  // weil VarLow direkt folgt; ContainsWholeWord prueft trotzdem den Rand am Ende.
  if TDetectorUtils.ContainsWholeWordLower('nil<>' + VarLow, CondLow) then
    Result := True;
end;

class function TNilDerefDetector.HasGuardingIf(MethodNode: TAstNode;
  const VarLow: string; AfterLine, BeforeLine: Integer): Boolean;
var
  Ifs : TList<TAstNode>;
  IfN : TAstNode;
  Low : string;
begin
  Result := False;
  Ifs := MethodNode.FindAll(nkIfStmt);
  try
    for IfN in Ifs do
    begin
      // Nur If-Statements zwischen den relevanten Zeilen
      if IfN.Line < AfterLine then Continue;
      if IfN.Line > BeforeLine then Continue;
      Low := IfN.TypeRef.ToLower;
      if Low = '' then Continue;
      if CondHasGuard(Low, VarLow) then Exit(True);
    end;
  finally
    Ifs.Free;
  end;
end;

class function TNilDerefDetector.IsNilSafeCall(
  const CallNameLow, VarLow: string): Boolean;
// .Free und .Destroy sind nil-sicher (TObject.Free prueft Self <> nil)
// FreeAndNil(varname) ist ebenfalls nil-sicher.
// Wortgrenzen wichtig: 'x.free' soll NICHT 'x.freedom' matchen.
begin
  Result :=
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.free',         CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower(VarLow + '.destroy',      CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil(' + VarLow,   CallNameLow) or
    TDetectorUtils.ContainsWholeWordLower('freeandnil( ' + VarLow,  CallNameLow);
end;

class procedure TNilDerefDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Assigns : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  NA      : TAstNode;
  VarLow  : string;
  F       : TLeakFinding;
begin
  Assigns := nil;
  Calls   := nil;
  try
    Assigns := MethodNode.FindAll(nkAssign);
    Calls   := MethodNode.FindAll(nkCall);
    for NA in Assigns do
    begin
      // Nur direkte nil-Zuweisungen: 'varname := nil'
      if NA.TypeRef.ToLower <> 'nil' then Continue;
      // Feldwerte (obj.field := nil) ueberspringen – Cleanup-Muster
      if Pos('.', NA.Name) > 0 then Continue;

      VarLow := NA.Name.ToLower;
      if VarLow = '' then Continue;
      // Self oder Result als Variablenname ueberspringen
      if (VarLow = 'self') or (VarLow = 'result') then Continue;

      for var C in Calls do
      begin
        if C.Line <= NA.Line then Continue;

        var NameLow := C.Name.ToLower;
        // Punkt-Zugriff 'varname.' im Call-Namen?
        // Wortgrenze pruefen: muss am Anfang oder nach Nicht-Bezeichner stehen
        var p := Pos(VarLow + '.', NameLow);
        if p = 0 then Continue;
        if p > 1 then
        begin
          var Prev := NameLow[p - 1];
          if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
        end;

        // .Free / .Destroy sind nil-sicher
        if IsNilSafeCall(NameLow, VarLow) then Continue;

        // Neuzuweisung zwischen nil und Zugriff?
        var Reassigned := False;
        for var A in Assigns do
        begin
          if A = NA then Continue;
          if A.Line <= NA.Line then Continue;
          if A.Line >= C.Line  then Break;
          if A.Name.ToLower <> VarLow then Continue;
          if A.TypeRef.ToLower <> 'nil' then
          begin
            Reassigned := True;
            Break;
          end;
        end;
        if Reassigned then Continue;

        // Guard via If-Bedingung zwischen nil und Zugriff?
        if HasGuardingIf(MethodNode, VarLow, NA.Line, C.Line) then Continue;

        // Befund: nil-Zuweisung ohne Guard, dann Punkt-Zugriff
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(C.Line);
        F.MissingVar := NA.Name + ' := nil (line ' + IntToStr(NA.Line) + ')';
        F.SetKind(fkNilDeref);
        Results.Add(F);
        Break; // Pro nil-Zuweisung nur einmal melden
      end;
    end;
  finally
    Assigns.Free;
    Calls.Free;
  end;
end;

class procedure TNilDerefDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
