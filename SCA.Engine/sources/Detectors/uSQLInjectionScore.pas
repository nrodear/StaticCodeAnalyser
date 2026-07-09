unit uSQLInjectionScore;

// Bewertet den Behebungs-Aufwand einer SQL-Injection.
//
// Eingabe: TypeRef des nkAssign-Knotens (vollständiger RHS-Ausdruck,
//          Stringliterale ohne Anführungszeichen, z. B.
//          "SELECT * FROM users WHERE id = +UserId")
//
// Ausgabe: TFixEstimate mit Punktzahl 1–5, Label und Handlungsempfehlung.
//
// Bewertungslogik:
//   Für jeden '+' im RHS wird geprüft, in welchem SQL-Kontext er steht:
//     - Strukturell (FROM+, JOIN+, TABLE+, …) → schwerer zu beheben
//     - Wert-Kontext (= +, <> +, LIKE +, …)  → einfach zu parametrisieren
//     - Funktionsaufruf (+(   …              → mittlerer Aufwand
//   Die Summe der gewichteten Punkte ergibt den Gesamt-Score.
//
// Skala:
//   1 = Trivial  – 1 Wert-Parameter, direkt durch :Param ersetzen
//   2 = Einfach  – 2–3 Wert-Parameter
//   3 = Mittel   – Funktionsaufruf oder 4+ Parameter
//   4 = Schwer   – mindestens ein struktureller Teil (Tabellenname etc.)
//   5 = Sehr schwer – alles dynamisch oder mehrere strukturelle Teile

interface

uses
  System.SysUtils;

type
  TFixDifficulty = (fdTrivial, fdEasy, fdMedium, fdHard, fdVeryHard);

  TFixEstimate = record
    Score      : Integer;         // 1..5
    Difficulty : TFixDifficulty;
    Label_     : string;          // "Trivial" … "Sehr schwer"
    Reason     : string;          // Begründung
    Suggestion : string;          // Handlungsempfehlung
  end;

  TSQLFixScorer = class
  public
    // Analysiert den RHS-Text eines SQL-Befehls und schätzt den Behebungsaufwand.
    class function Estimate(const RHS: string): TFixEstimate; static;

    // Formatiert die Schätzung als einzeilige Zusammenfassung.
    class function FormatShort(const E: TFixEstimate): string; static;
  private
    class function CountPlus(const S: string): Integer; static;
    class function HasStructuralConcat(const Low: string): Boolean; static;
    class function HasFunctionCallConcat(const Low: string): Boolean; static;
    class function DifficultyLabel(D: TFixDifficulty): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, LongMethod, MagicNumber, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{ ---- Hilfsfunktionen ---- }

class function TSQLFixScorer.CountPlus(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if S[i] = '+' then Inc(Result);
end;

// Prüft ob ein '+' direkt nach einem strukturellen SQL-Schlüsselwort steht.
// Hinweis: Stringliterale werden vom Parser ohne Anführungszeichen übergeben,
// sodass 'SELECT * FROM '+tbl als "SELECT * FROM +tbl" vorliegt.
class function TSQLFixScorer.HasStructuralConcat(const Low: string): Boolean;
const
  STRUCTURAL: array[0..8] of string = (
    'from ''+', 'join ''+', 'inner join ''+', 'left join ''+',
    'into ''+', 'table ''+', 'update ''+', 'select ''+', 'order by ''+'
  );
var
  P: string;
begin
  for P in STRUCTURAL do
    if Pos(P, Low) > 0 then Exit(True);
  Result := False;
end;

// Prüft ob nach einem '+' ein Funktionsaufruf folgt (erkennbar an '+(').
class function TSQLFixScorer.HasFunctionCallConcat(const Low: string): Boolean;
begin
  Result := Pos('+(', Low) > 0;
end;


class function TSQLFixScorer.DifficultyLabel(D: TFixDifficulty): string;
begin
  case D of
    fdTrivial  : Result := 'Trivial';
    fdEasy     : Result := 'Einfach';
    fdMedium   : Result := 'Mittel';
    fdHard     : Result := 'Schwer';
    fdVeryHard : Result := 'Sehr schwer';
  else
    Result := '?';
  end;
end;

{ ---- Haupt-Scoring ---- }

class function TSQLFixScorer.Estimate(const RHS: string): TFixEstimate;
var
  Low         : string;
  TotalPlus   : Integer;
  IsStructural: Boolean;
  HasFuncCall : Boolean;
  Score       : Integer;
  Difficulty  : TFixDifficulty;
  Reason      : string;
  Suggestion  : string;
begin
  // Reason/Suggestion default leer - die unten folgenden Branches setzen
  // sie alle, aber so ist der Out-Pfad bei spaeterem Code-Refactor
  // (neuer Branch ohne explizites Reason) defensiv abgedeckt.
  // Score/Difficulty werden in jedem Branch ueberschrieben + von der
  // case Score-Klausel am Ende abgeleitet, daher hier KEIN Default
  // (vermeidet H2077 "value never used").
  Reason     := '';
  Suggestion := '';

  Low         := RHS.ToLower;
  TotalPlus   := CountPlus(Low);
  IsStructural := HasStructuralConcat(Low);
  HasFuncCall := HasFunctionCallConcat(Low);
  // ── Score-Berechnung (alle Branches setzen Score explizit) ───────────────
  if IsStructural then
  begin
    // Strukturelle SQL-Teile (Tabellen-/Spaltennamen) → schwer
    Score := 4;
    if (TotalPlus > 2) or HasFuncCall then
      Score := 5;

    Reason     := Format('Struktureller SQL-Teil verkettet (%d "+")', [TotalPlus]);
    Suggestion := 'Tabellenname/Spaltenname per Whitelist validieren; ' +
                  'Wert-Parameter durch :Param ersetzen.';
  end
  else if HasFuncCall then
  begin
    Score      := 3;
    Reason     := 'Funktionsaufruf in der Verkettung erschwert Refactoring';
    Suggestion := 'Rückgabewert der Funktion zuerst in Variable speichern, ' +
                  'dann als Parameter übergeben.';
  end
  else
  begin
    // Nur Wert-Verkettungen
    case TotalPlus of
      0:
        begin
          // Sollte nicht vorkommen (Detektor wuerde nicht triggern ohne '+'),
          // aber falls doch: defensive Defaults beschreiben den Zustand.
          Score      := 1;
          Reason     := 'Keine erkennbare Konkatenation';
          Suggestion := 'Pr'#$FC'fen ob hier wirklich ein SQL-Injection-Risiko vorliegt.';
        end;
      1:
        begin
          Score      := 1;
          Reason     := 'Einfache Wert-Verkettung (1 Parameter)';
          Suggestion := 'Ersetze durch parametrisiertes Query: "WHERE id = :Id".';
        end;
      2, 3:
        begin
          Score      := 2;
          Reason     := Format('%d Wert-Verkettungen', [TotalPlus]);
          Suggestion := Format('Ersetze %d String-Konkatenationen durch benannte ' +
                               'Parameter (:Param1, :Param2, …).', [TotalPlus]);
        end;
    else
      // 4+
      Score      := 3;
      Reason     := Format('Viele Verkettungen (%d "+"), aber nur Wert-Kontext',
                           [TotalPlus]);
      Suggestion := 'Query schrittweise refactoren: zuerst WHERE-Bedingungen ' +
                    'parametrisieren, dann restliche Teile.';
    end;
  end;

  // Score auf 1..5 begrenzen
  if Score < 1 then Score := 1;
  if Score > 5 then Score := 5;

  case Score of
    1: Difficulty := fdTrivial;
    2: Difficulty := fdEasy;
    3: Difficulty := fdMedium;
    4: Difficulty := fdHard;
  else
    Difficulty := fdVeryHard;
  end;

  Result.Score      := Score;
  Result.Difficulty := Difficulty;
  Result.Label_     := DifficultyLabel(Difficulty);
  Result.Reason     := Reason;
  Result.Suggestion := Suggestion;
end;

class function TSQLFixScorer.FormatShort(const E: TFixEstimate): string;
const
  BARS: array[1..5] of string = ('[*    ]','[**   ]','[***  ]','[**** ]','[*****]');
var
  BarStr: string;
begin
  if (E.Score >= 1) and (E.Score <= 5) then
    BarStr := BARS[E.Score]
  else
    BarStr := '';
  Result := Format('Fix %d/5 %s (%s)', [E.Score, BarStr, E.Label_]);
end;

end.
