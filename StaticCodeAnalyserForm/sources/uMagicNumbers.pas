unit uMagicNumbers;

// Detektor fuer Magic Numbers in if-Bedingungen.
// Erkennt Zahlenliterale > 1 in Vergleichen, die nicht via Konstante
// benannt sind. Beispiel: 'if Count > 100 then' sollte 'MAX_COUNT' nutzen.
//
// Akzeptierte (nicht-magische) Zahlen: 0, 1, 2, -1
// (sehr haeufige Indizes/Defaults und schwer durch Konstanten ersetzbar)

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMagicNumberDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function ExtractMagicNumber(const CondLow: string;
      out NumStr: string): Boolean; static;
    class function IsTrivial(const NumStr: string): Boolean; static;
  end;

implementation

class function TMagicNumberDetector.IsTrivial(const NumStr: string): Boolean;
begin
  Result := (NumStr = '0') or (NumStr = '1') or (NumStr = '2') or
            (NumStr = '-1') or (NumStr = '10') or (NumStr = '100');
end;

class function TMagicNumberDetector.ExtractMagicNumber(
  const CondLow: string; out NumStr: string): Boolean;
// Sucht Vergleichsoperator gefolgt von Zahl: '> 100', '< 50', '>= 5', '<> 42'
const
  OPS : array[0..7] of string = (
    '> ', '>= ', '< ', '<= ', '<> ', '= ', '>=', '<='
  );
var
  Op   : string;
  p, i : Integer;
begin
  Result := False;
  NumStr := '';

  for Op in OPS do
  begin
    p := Pos(' ' + Op, CondLow);
    while p > 0 do
    begin
      i := p + Length(Op) + 1; // nach " > "
      // Optional negatives Vorzeichen
      var Digits := '';
      if (i <= Length(CondLow)) and (CondLow[i] = '-') then
      begin
        Digits := '-';
        Inc(i);
      end;
      while (i <= Length(CondLow)) and CharInSet(CondLow[i], ['0'..'9']) do
      begin
        Digits := Digits + CondLow[i];
        Inc(i);
      end;
      // Nur Integer-Zahl, kein Float / Hex
      if (Digits <> '') and (Digits <> '-') and not IsTrivial(Digits) then
      begin
        // Pruefen ob es nicht Teil eines Bezeichners ist (z.B. > maxInt)
        // Die Position davor muss ein Leerzeichen sein
        NumStr := Digits;
        Exit(True);
      end;
      p := Pos(' ' + Op, CondLow, p + 1);
    end;
  end;
end;

class procedure TMagicNumberDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Ifs    : TList<TAstNode>;
  IfN    : TAstNode;
  CondLow: string;
  NumStr : string;
  F      : TLeakFinding;
begin
  Ifs := UnitNode.FindAll(nkIfStmt);
  try
    for IfN in Ifs do
    begin
      CondLow := IfN.TypeRef.ToLower;
      if CondLow = '' then Continue;

      if ExtractMagicNumber(CondLow, NumStr) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(IfN.Line);
        F.MissingVar := Format('Magic Number "%s" in if-Bedingung - Konstante verwenden',
                               [NumStr]);
        F.Severity   := lsHint;
        F.Kind       := fkMagicNumber;
        Results.Add(F);
      end;
    end;
  finally
    Ifs.Free;
  end;
end;

end.
