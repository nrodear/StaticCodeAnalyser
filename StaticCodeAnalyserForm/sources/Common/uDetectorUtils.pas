unit uDetectorUtils;

// Gemeinsame Helfer fuer Detektoren. Vor allem Pattern-Matching mit echten
// Wortgrenzen statt naivem Pos() - mehrere Detektoren hatten False-Positives
// weil 'sql' auch 'sqlnot' und 'assigned MyVar' auch 'assigned MyVarOld'
// matchen wuerde.
//
// Konvention:
//   - "Lower" als Suffix bedeutet: Aufrufer hat bereits ToLower angewendet,
//     wir sparen die Konvertierung pro Aufruf.
//   - "WholeWord" bedeutet: links und rechts vom Match steht KEIN Identifier-
//     Zeichen (Buchstabe, Ziffer, Underscore, Punkt-Qualifier).

interface

uses
  System.Classes; // TStrings

type
  // Mitgefuehrter Block-Kommentar-Zustand fuer ScanCodeLine. Zeilenstrings
  // und `//`-Zeilenkommentare beginnen/enden IMMER innerhalb einer Zeile -
  // nur `{ ... }` und `(* ... *)` koennen ueber Zeilengrenzen laufen, daher
  // wird nur deren Zustand zwischen ScanCodeLine-Aufrufen getragen.
  TCommentScanState = record
    InBraceComment : Boolean;   // innerhalb { ... }
    InParenComment : Boolean;   // innerhalb (* ... *)
  end;

  TDetectorUtils = class
     public
      // True, wenn Ch zu einem Identifier gehoert (a..z, 0..9, _).
    // Punkt zaehlt NICHT mit - 'sql' in 'mytable.sql' soll trotzdem als
    // Wortgrenze rechts vom Punkt erkannt werden.
    class function IsIdentChar(Ch: Char): Boolean; static; inline;

    // Sucht Needle in Haystack, beide bereits lower-case, mit Wortgrenzen-
    // Pruefung links UND rechts. Liefert 1-basierte Position oder 0.
    // Beispiele:
    //   FindWholeWordLower('sql', '.sqlnot') -> 0  (rechts steht 'n')
    //   FindWholeWordLower('sql', 'my.sql=') -> 4  (rechts steht '=')
    //   FindWholeWordLower('assigned x', 'assigned xa') -> 0
    class function FindWholeWordLower(const Needle, HaystackLower: string)
      : Integer; static;


    // True, wenn Needle als ganzes Wort in HaystackLower vorkommt.
    class function ContainsWholeWordLower(const Needle, HaystackLower: string)
      : Boolean; static; inline;

    // Entfernt Pascal-String-Literale aus einem Ausdrucks-Text.
    // Pascal escaped einfache Apostrophe in Strings durch Verdoppelung
    // (`'don''t'`), aber der Parser-AST hat sie bereits als zusammenhaengen-
    // den Literal-Token konsumiert; die Funktion arbeitet daher auf einer
    // Toggle-Logik: jedes Apostrophe schaltet "in-string"-Modus um.
    // Verwendet von Detektoren, die nach Operator-Pattern (z.B. `= nil`,
    // `IfThen(...,A(),B())`) suchen und dabei Treffer in String-Literalen
    // ('= nil als String') ausschliessen muessen.
    class function StripStringLiterals(const S: string): string; static;

    // === ZEILEN-SCANNER (Strings + Kommentare) =========================
    // Single source of truth fuer die String-/Kommentar-Zustandsmaschine.
    // Frueher hatten uFloatEquality und uNoSonarMarker je eine eigene Kopie
    // mit subtilen Abweichungen - jede Abweichung = potenzieller
    // False-Positive (Match im String-Literal / Kommentar).

    // Verarbeitet GENAU EINE Zeile. Liefert den Code-Anteil zurueck, wobei:
    //   * String-Literal-Inhalte (inkl. der Quotes) durch FillCh ersetzt
    //     werden - Position bleibt erhalten, aber `\w`/`\s`-Regex matchen
    //     nicht mehr ueber den Ex-String hinweg (Default '~': weder \w noch \s).
    //   * `{ ... }` / `(* ... *)`-Kommentar-Inhalte ENTFERNT werden.
    //   * bei einem `//`-Zeilenkommentar der Rest der Zeile abgeschnitten und
    //     LineCommentCol auf die 1-basierte Spalte des ersten `/` gesetzt wird
    //     (0 wenn kein Zeilenkommentar).
    // State traegt offene `{`/`(*`-Bloecke ueber Zeilengrenzen.
    class function ScanCodeLine(const Line: string; var State: TCommentScanState;
      out LineCommentCol: Integer; FillCh: Char = '~'): string; static;

    // Strippt Strings + Kommentare ueber den GESAMTEN Quelltext (Mehrzeilen-
    // Bloecke korrekt). Ergebnis ist EIN String, Zeilen mit #10 getrennt.
    // LineForChar[k] liefert den 0-basierten Quell-Zeilenindex des Zeichens
    // Result[k+1] - damit kann ein Detektor von einer Match-Position im
    // gestrippten Text auf die Quellzeile zurueckrechnen.
    class function StripStringsAndComments(Lines: TStrings;
      out LineForChar: TArray<Integer>; FillCh: Char = '~'): string; static;
  end;


implementation

uses
  System.SysUtils,               // TStringBuilder
  System.Generics.Collections,   // TList<Integer>
  System.StrUtils;               // PosEx

class function TDetectorUtils.IsIdentChar(Ch: Char): Boolean;
begin
  Result := ((Ch >= 'a') and (Ch <= 'z'))
         or ((Ch >= 'A') and (Ch <= 'Z'))
         or ((Ch >= '0') and (Ch <= '9'))
         or (Ch = '_');
end;

class function TDetectorUtils.FindWholeWordLower(const Needle,
  HaystackLower: string): Integer;
var
  Start, NLen, HLen, i: Integer;
  LeftOK, RightOK     : Boolean;
begin
  Result := 0;
  NLen   := Length(Needle);
  HLen   := Length(HaystackLower);
  if (NLen = 0) or (HLen < NLen) then Exit;

  // Pos() ist die Schleife - wir starten ab Position 1 und springen weiter
  // wenn der Match keine echten Wortgrenzen hat.
  Start := 1;
  while True do
  begin
    i := PosEx(Needle, HaystackLower, Start);
    if i = 0 then Exit;

    // Linke Grenze: Zeichen vor dem Match darf KEIN Identifier-Char sein.
    LeftOK := (i = 1) or not IsIdentChar(HaystackLower[i - 1]);

    // Rechte Grenze: Zeichen nach dem Match darf KEIN Identifier-Char sein.
    RightOK := (i + NLen - 1 >= HLen)
            or not IsIdentChar(HaystackLower[i + NLen]);

    if LeftOK and RightOK then Exit(i);

    Inc(Start, 1); // weiter suchen
    if Start > HLen - NLen + 1 then Exit;
  end;
end;

class function TDetectorUtils.ContainsWholeWordLower(const Needle,
  HaystackLower: string): Boolean;
begin
  Result := FindWholeWordLower(Needle, HaystackLower) > 0;
end;

class function TDetectorUtils.StripStringLiterals(const S: string): string;
var
  i     : Integer;
  C     : Char;
  InStr : Boolean;
begin
  Result := '';
  InStr := False;
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C = '''' then
      InStr := not InStr
    else if not InStr then
      Result := Result + C;
  end;
end;

class function TDetectorUtils.ScanCodeLine(const Line: string;
  var State: TCommentScanState; out LineCommentCol: Integer;
  FillCh: Char): string;
var
  Buf    : TStringBuilder;
  j, n   : Integer;
  c      : Char;
  InStr  : Boolean;   // String-Literale spannen nie ueber Zeilen -> lokal
  pClose : Integer;
begin
  LineCommentCol := 0;
  InStr := False;
  n := Length(Line);
  Buf := TStringBuilder.Create;
  try
    j := 1;
    while j <= n do
    begin
      if State.InBraceComment then
      begin
        pClose := PosEx('}', Line, j);
        if pClose = 0 then Break;             // Block laeuft in naechste Zeile
        State.InBraceComment := False;
        j := pClose + 1; Continue;
      end;
      if State.InParenComment then
      begin
        pClose := PosEx('*)', Line, j);
        if pClose = 0 then Break;
        State.InParenComment := False;
        j := pClose + 2; Continue;
      end;
      c := Line[j];
      if InStr then
      begin
        Buf.Append(FillCh);
        if c = '''' then
        begin
          // Verdoppeltes Apostroph = escaptes Quote, bleibt im String.
          if (j < n) and (Line[j + 1] = '''') then
          begin Buf.Append(FillCh); Inc(j, 2); end
          else begin InStr := False; Inc(j); end;
        end
        else Inc(j);
        Continue;
      end;
      if c = '''' then
      begin Buf.Append(FillCh); InStr := True; Inc(j); Continue; end;
      if (c = '/') and (j < n) and (Line[j + 1] = '/') then
      begin LineCommentCol := j; Break; end;  // Rest = Zeilenkommentar
      if c = '{' then
      begin
        pClose := PosEx('}', Line, j + 1);
        if pClose = 0 then begin State.InBraceComment := True; Break; end;
        j := pClose + 1; Continue;
      end;
      if (c = '(') and (j < n) and (Line[j + 1] = '*') then
      begin
        pClose := PosEx('*)', Line, j + 2);
        if pClose = 0 then begin State.InParenComment := True; Break; end;
        j := pClose + 2; Continue;
      end;
      Buf.Append(c);
      Inc(j);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

class function TDetectorUtils.StripStringsAndComments(Lines: TStrings;
  out LineForChar: TArray<Integer>; FillCh: Char): string;
var
  Buf   : TStringBuilder;
  Chars : TList<Integer>;
  State : TCommentScanState;
  i, k  : Integer;
  Part  : string;
  Dummy : Integer;
begin
  Buf   := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      Part := ScanCodeLine(Lines[i], State, Dummy, FillCh);
      Buf.Append(Part);
      for k := 1 to Length(Part) do
        Chars.Add(i);
      // Zeilenumbruch ebenfalls auf die Quellzeile mappen, damit `\s`-Regex
      // ueber das Zeilenende hinweg konsistent positioniert bleibt.
      Buf.Append(#10);
      Chars.Add(i);
    end;
    Result      := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free;
    Buf.Free;
  end;
end;

end.
