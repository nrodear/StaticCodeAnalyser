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

// noinspection-file ConsecutiveSection, GroupedDeclaration, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;

class function TMagicNumberDetector.IsTrivial(const NumStr: string): Boolean;
// Trivial-Liste kommt aus uSCAConsts.DetectorMagicTrivials (analyser.ini ->
// MagicNumberTrivials). Wenn die globale Liste nil ist, fallen wir auf die
// historischen Defaults zurueck. Zusaetzlich: Powers of 2 bis 1024 werden
// immer als trivial betrachtet (Bit-/Byte-/Buffer-Konstanten).
var
  N: Integer;
begin
  if Assigned(DetectorMagicTrivials) and (DetectorMagicTrivials.Count > 0) then
  begin
    if DetectorMagicTrivials.IndexOf(NumStr) >= 0 then Exit(True);
  end
  else if (NumStr = '0') or (NumStr = '1') or (NumStr = '2') or
          (NumStr = '-1') or (NumStr = '10') or (NumStr = '100') then
    Exit(True);
  // Powers of 2 bis 1024 sind idiomatische Bit-/Byte-Konstanten.
  Result := TryStrToInt(NumStr, N) and (N > 0) and (N <= 1024) and
            ((N and (N - 1)) = 0);
end;

// Steht an Position i - direkt hinter einer Ziffernfolge - die Fortsetzung
// eines FLOAT-Literals? Das ist ein '.' mit Ziffer dahinter oder ein
// Exponent ('e' plus Ziffer, mit optionalem Vorzeichen). ACondLow ist
// bereits lowercase, 'E' braucht also keine eigene Behandlung.
function IstFloatFortsetzung(const ACondLow: string; i: Integer): Boolean;
var
  n : Integer;
begin
  n := Length(ACondLow);
  if i >= n then Exit(False);
  if (ACondLow[i] = '.') and CharInSet(ACondLow[i + 1], ['0'..'9']) then
    Exit(True);
  if ACondLow[i] <> 'e' then Exit(False);
  if CharInSet(ACondLow[i + 1], ['0'..'9']) then Exit(True);
  Result := (i + 1 < n) and CharInSet(ACondLow[i + 1], ['+', '-'])
            and CharInSet(ACondLow[i + 2], ['0'..'9']);
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

      // Nur Integer-Zahl, kein Float / Hex.
      //
      // Hex faellt schon vorher heraus: '$' ist keine Ziffer, Digits bleibt
      // leer. Float dagegen NICHT - der Ziffern-Scan haelt am Dezimalpunkt
      // an und meldete den so entstandenen Ganzzahl-Torso ungeprueft
      // weiter. 'if X > 3.5' ergab bis 2026-09-13 'Magic number "3"'.
      // Der Kommentar beschrieb die Absicht, es gab nur keine Wache, die
      // sie durchsetzt.
      //
      // Sichtbar wurde die Willkuer an der Trivial-Pruefung: sie griff am
      // Torso, also verschwand '2.5' (als '2' trivial) und '3.5' wurde
      // gemeldet.
      //
      // Folgt auf die Ziffernfolge '.'+Ziffer oder ein Exponent
      // ('e'+Ziffer bzw. 'e'+Vorzeichen+Ziffer - CondLow ist bereits
      // lowercase), ist es ein Float-Literal und dieses Vorkommen wird
      // uebersprungen. Korpus, am A/B des Referenzlaufs 2026-09-13
      // nachgemessen: -70 von 5.084 SCA014-Funden (64 Dezimalpunkte, 6
      // Exponenten), 0 Adds. Die frueher hier stehenden -67 / 4.494 kamen
      // aus einem anders zugeschnittenen Lauf.
      //
      // WAS DAS KOSTET, damit es niemand fuer einen reinen FP-Fix haelt:
      // die Regel ist damit fuer JEDES Float-Literal blind, nicht nur fuer
      // den Torso. Unter den 70 Wegfaellen sind 44x '255.0', 9x '3.0' und
      // 6x '-9E18' - '255.0' in einer if-Bedingung IST eine Magic Number,
      // sie wird jetzt nicht mehr gemeldet. Die Alternative waere gewesen,
      // das VOLLE Literal zu melden statt es zu ueberspringen; das ist ein
      // eigenes Paket (Meldetext, Trivial-Pruefung auf Floats, FP-Messung)
      // und kein Nebenprodukt dieser Korrektur.
      if (Digits <> '') and (Digits <> '-') and not IsTrivial(Digits)
         and not IstFloatFortsetzung(CondLow, i) then
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
      // Review-MEDIUM 2026-08-09: Literale blanken - Vergleichsoperator+Zahl
      // INNERHALB eines String-Literals zaehlt nicht als Magic Number.
      CondLow := TDetectorUtils.BlankStringLiterals(IfN.TypeRef.ToLower);
      if CondLow = '' then Continue;

      if ExtractMagicNumber(CondLow, NumStr) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(IfN.Line);
        F.MissingVar := Format('Magic number "%s" in if condition - use a constant',
                               [NumStr]);
        F.SetKind(fkMagicNumber);
        Results.Add(F);
      end;
    end;
  finally
    Ifs.Free;
  end;
end;

end.
