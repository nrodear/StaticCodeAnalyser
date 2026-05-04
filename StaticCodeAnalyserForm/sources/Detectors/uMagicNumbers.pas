unit uMagicNumbers;

// Detektor fuer Magic Numbers in if-Bedingungen.
// Erkennt Zahlenliterale > 1 in Vergleichen, die nicht via Konstante
// benannt sind. Beispiel: 'if Count > 100 then' sollte 'MAX_COUNT' nutzen.
//
// Akzeptierte (nicht-magische) Zahlen: 0, 1, 2, -1
// (sehr haeufige Indizes/Defaults und schwer durch Konstanten ersetzbar)

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections,
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
// Trivial-Liste kommt aus uSCAConsts.DetectorMagicTrivials (analyser.ini ->
// MagicNumberTrivials). Defaults 0,1,2,-1,10,100. Wenn die globale Liste
// nil sein sollte (Initialisierungs-Race), fallen wir auf die historischen
// Defaults zurueck damit der Detektor immer funktioniert.
begin
  if Assigned(DetectorMagicTrivials) and (DetectorMagicTrivials.Count > 0) then
    Result := DetectorMagicTrivials.IndexOf(NumStr) >= 0
  else
    Result := (NumStr = '0') or (NumStr = '1') or (NumStr = '2') or
              (NumStr = '-1') or (NumStr = '10') or (NumStr = '100');
end;

class function TMagicNumberDetector.ExtractMagicNumber(
  const CondLow: string; out NumStr: string): Boolean;
// Sucht Vergleichsoperator gefolgt von Zahl: '> 100', '<50', '(Count>=5)', etc.
//
// Vorher: Pos(' ' + Op, CondLow) verlangte ein Leerzeichen vor dem Operator -
// damit wurde '(Count>100)' uebersehen. Jetzt: explizite Boundary-Pruefung
// (Whitespace, '(', ',', '[' oder String-Anfang sind erlaubte Vorgaenger).
//
// Reihenfolge wichtig: 2-Zeichen-Operatoren (>=, <=, <>) VOR den 1-Zeichen-
// Operatoren, sonst wird '>=' faelschlich als '>' erkannt.
const
  OPS : array[0..5] of string = (
    '>=', '<=', '<>', '>', '<', '='
  );
  PRECEDER_CHARS = [' ', #9, '(', ',', '[', #0];

  function IsValidLeftBoundary(P: Integer): Boolean;
  begin
    if P <= 1 then Exit(True); // String-Anfang
    Result := CharInSet(CondLow[P - 1], PRECEDER_CHARS);
  end;

var
  Op            : string;
  p, OpEnd, i   : Integer;
  Digits        : string;
begin
  Result := False;
  NumStr := '';

  for Op in OPS do
  begin
    p := PosEx(Op, CondLow, 1);
    while p > 0 do
    begin
      // Linke Wortgrenze: vor dem Op darf nichts sein, das den Op zu Teil
      // eines Bezeichners macht oder zu einem laengeren Op (z.B. '<' in '<>').
      if not IsValidLeftBoundary(p) then
      begin
        p := PosEx(Op, CondLow, p + 1);
        Continue;
      end;

      // Wenn 1-Zeichen-Op und das Folgezeichen erweitert ihn zu 2-Zeichen-Op
      // -> ueberspringen (wird vom anderen Pattern erfasst).
      OpEnd := p + Length(Op);
      if (Length(Op) = 1)
         and (OpEnd <= Length(CondLow))
         and CharInSet(CondLow[OpEnd], ['=', '>']) then
      begin
        p := PosEx(Op, CondLow, p + 1);
        Continue;
      end;

      // Optional Whitespace zwischen Op und Zahl ueberspringen
      i := OpEnd;
      while (i <= Length(CondLow)) and CharInSet(CondLow[i], [' ', #9]) do
        Inc(i);

      // Optional negatives Vorzeichen
      Digits := '';
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
        NumStr := Digits;
        Exit(True);
      end;
      p := PosEx(Op, CondLow, p + 1);
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
        F.MissingVar := Format('Magic number "%s" in if condition - use a constant',
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
