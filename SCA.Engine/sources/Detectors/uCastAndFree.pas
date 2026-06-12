unit uCastAndFree;

// Detektor: `<ClassType>(<obj>).Free` (oder `.Destroy`) - Typ-Cast direkt
// vor Free/Destroy.
//
// Pattern (Code-Smell / Verwirrung):
//   var L: TObject;
//   begin
//     L := TStringList.Create;
//     ...
//     TStringList(L).Free;   // <-- Cast hat keinen Effekt - Destroy ist virtual.
//   end;
//
// Korrekt:
//   L.Free;
//
// Warum problematisch:
//   * TObject.Free ist nicht-virtuell, ruft aber intern das virtuelle
//     Destroy auf - der Cast hat KEINEN Einfluss auf die Auflosung der
//     Destruktor-Kette. `L.Free` und `TStringList(L).Free` rufen
//     identisch `L.Destroy` virtuell auf.
//   * Wer den Cast schreibt, glaubt vermutlich der Cast steuert WELCHES
//     Destroy laeuft - klassisches Missverstaendnis. Code-Review-Smell.
//   * Wenn der Cast zu einem FALSCHEN Typ erfolgt (TWrongClass(L).Free),
//     ist das ein latenter Bug - die Variable wird unter falscher
//     Typannahme freigegeben; jeder spaetere Refactor des Codes haengt
//     an dieser Annahme.
//   * Wenn der Cast zum gleichen Typ wie die Variable erfolgt
//     (TStringList(L).Free wo L: TStringList), ist er redundant.
//
// Erkennung (string-pattern auf nkCall.Name):
//   * Call-Name endet auf `.Free` oder `.Destroy` (optional gefolgt von
//     `(`, leeren Args).
//   * Davor: `<Ident>(<expr>)` - ein Identifier gefolgt von einem
//     balancierten Paren-Block.
//   * <Ident> matcht die Delphi-Konvention `T[A-Z]...` (Klassen) oder
//     `I[A-Z]...` (Interfaces). Damit faengt der Detektor `Foo(x).Free`
//     (Funktionsaufruf) nicht und beschraenkt sich auf echte Typ-Casts.
//
// Sonar-Pendant: CastAndFreeCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   CastAndFreeCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCastAndFreeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or
            ((C >= 'a') and (C <= 'z')) or (C = '_');
end;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

function IsUpperLetter(C: Char): Boolean; inline;
begin
  Result := (C >= 'A') and (C <= 'Z');
end;

// True wenn S der Delphi-Konvention fuer einen Klassen-/Interface-Typ folgt:
// 'T' oder 'I' gefolgt von Grossbuchstabe + Restzeichen.
function LooksLikeClassType(const S: string): Boolean;
var
  i : Integer;
begin
  if Length(S) < 2 then Exit(False);
  if (S[1] <> 'T') and (S[1] <> 'I') then Exit(False);
  if not IsUpperLetter(S[2]) then Exit(False);
  // Restliche Zeichen muessen alle Ident-Zeichen sein.
  for i := 3 to Length(S) do
    if not IsIdentChar(S[i]) then Exit(False);
  Result := True;
end;

// Strippt trailing Whitespace, ';', und optional ein leeres '()' (Free()).
function NormalizeCallTail(const S: string): string;
var
  L : Integer;
begin
  Result := TrimRight(S);
  L := Length(Result);
  while (L > 0) and (Result[L] = ';') do
  begin
    SetLength(Result, L - 1);
    Result := TrimRight(Result);
    L := Length(Result);
  end;
  // Optional: Free() mit leeren Klammern.
  if (L >= 2) and (Result[L] = ')') and (Result[L - 1] = '(') then
  begin
    SetLength(Result, L - 2);
    Result := TrimRight(Result);
  end;
end;

// Liefert den Cast-Ziel-Typ wenn S das Muster `<Ident>(<expr>).Free` oder
// `<Ident>(<expr>).Destroy` beschreibt UND <Ident> nach Delphi-Konvention
// ein Klassen-/Interface-Typ ist. Sonst leer.
function ExtractCastBeforeFree(const CallName: string): string;
const
  SUFFIX_FREE    = '.Free';
  SUFFIX_DESTROY = '.Destroy';
var
  Body     : string;
  Stripped : string;
  i, Depth : Integer;
  StartPos : Integer;
  Target   : string;
begin
  Result := '';
  Body := NormalizeCallTail(CallName);

  // Welcher Suffix matched (case-insensitive)?
  if (Length(Body) > Length(SUFFIX_FREE)) and
     SameText(Copy(Body, Length(Body) - Length(SUFFIX_FREE) + 1,
              Length(SUFFIX_FREE)), SUFFIX_FREE) then
    Stripped := Copy(Body, 1, Length(Body) - Length(SUFFIX_FREE))
  else if (Length(Body) > Length(SUFFIX_DESTROY)) and
          SameText(Copy(Body, Length(Body) - Length(SUFFIX_DESTROY) + 1,
                   Length(SUFFIX_DESTROY)), SUFFIX_DESTROY) then
    Stripped := Copy(Body, 1, Length(Body) - Length(SUFFIX_DESTROY))
  else
    Exit;

  Stripped := TrimRight(Stripped);
  if Stripped = '' then Exit;
  // Stripped muss mit ')' enden - Cast-Klammer.
  if Stripped[Length(Stripped)] <> ')' then Exit;

  // Matchende '(' zurueck-zaehlen (Paren-balanciert).
  Depth := 0;
  StartPos := 0;
  for i := Length(Stripped) downto 1 do
  begin
    case Stripped[i] of
      ')': Inc(Depth);
      '(': begin
             Dec(Depth);
             if Depth = 0 then
             begin
               StartPos := i;
               Break;
             end;
           end;
    end;
  end;
  if StartPos <= 1 then Exit;

  // Identifier links von der oeffnenden '('. Zurueck bis zum letzten
  // Nicht-Ident-Zeichen.
  i := StartPos - 1;
  while (i >= 1) and IsIdentChar(Stripped[i]) do
    Dec(i);
  // Falls vor dem Ident ein '.' steht (qualifizierter Bezeichner wie
  // 'Foo.Bar(x)'), ist es kein einfacher Klassen-Cast.
  if (i >= 1) and (Stripped[i] = '.') then Exit;

  Target := Copy(Stripped, i + 1, StartPos - i - 1);
  if not LooksLikeClassType(Target) then Exit;
  Result := Target;
end;

class procedure TCastAndFreeDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls  : TList<TAstNode>;
  N      : TAstNode;
  Target : string;
  F      : TLeakFinding;
begin
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      Target := ExtractCastBeforeFree(N.Name);
      if Target = '' then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        'Type-cast %s(...) before Free/Destroy is redundant (Destroy is virtual)',
        [Target]);
      F.SetKind(fkCastAndFree);
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

class procedure TCastAndFreeDetector.AnalyzeUnit(UnitNode: TAstNode;
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
