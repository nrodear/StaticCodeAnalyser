unit uRefactorInfo;

// Beschreibung einer Quellstelle fuer das Umschreiben (Datentypen des
// Quellstellen-Dienstes TSourcePlaces, s. uSourcePlaces).
//
// WOZU ES DIESE UNIT GIBT
//
// Ein Fund kennt nur Datei, Zeile und Meldetext. Wer die Fundstelle
// UMSCHREIBEN will (das Modul "Source Refactor", reDelphix), braucht
// mehr: den exakten Bereich mit Spalten, die Teilstuecke des Konstrukts,
// was ueber sie bekannt ist und ob die Stelle umschreibbar ist. Der
// Quellstellen-Dienst liest das auf Anfrage aus der Datei - KEIN Detektor
// liefert es, kein Fund traegt es.
//
// Diese Unit haelt NUR die Datentypen. Sie fuellt nichts, liest keine
// Datei und kennt keinen Detektor. Das generische Fuellen (Bereich,
// Flags, Einfuegepunkt, Hash) liegt in uRefactorInfoBuilder, die
// Zerlegung von '+'-Ketten in uRefactorConcat.
//
// DER VERTRAG
//
//   * PULL, NICHT PUSH. Die Beschreibung entsteht erst, wenn ein Konsument
//     danach fragt - ausserhalb des Scans, ohne Detektor, ohne Fund.
//     Fundzahl, FP-Quote, Baselines und SARIF bleiben davon unberuehrt.
//   * FAKTEN, KEIN ERSATZTEXT. Hier steht, was ueber die Stelle BEKANNT
//     ist. Den neuen Code baut der Konsument. Der Core wird nicht zum
//     Code-Generator.
//   * UNBEKANNT BLEIBT UNBEKANNT. rvUnknown und FixSafe = False sind der
//     Normalfall, nicht der Fehlerfall. Es wird nie geraten.
//
// KOORDINATEN
//
//   Zeilen und Spalten sind 1-basiert (wie TAstNode.Line / .Col). EndCol
//   zeigt HINTER das letzte Zeichen des Bereichs, d.h. fuer einen
//   einzeiligen Bereich liefert
//       Copy(Zeile, StartCol, EndCol - StartCol)
//   genau dessen Text. Spalten zaehlen Zeichen der dekodierten Zeile
//   (Delphi-String-Index); ein Tabulator ist EIN Zeichen.

interface

const
  // Rollen der Bereiche. Freier Text, damit ein Detektor eine eigene Rolle
  // vergeben kann, ohne dass diese Unit sie kennen muss - die gaengigen
  // stehen hier, damit Erzeuger und Leser dieselbe Schreibweise benutzen.
  ROLE_STATEMENT = 'statement';  // die ganze Anweisung inkl. ';'
  ROLE_TARGET    = 'target';     // linke Seite einer Zuweisung
  ROLE_TERM      = 'term';       // ein Term einer '+'-Kette
  ROLE_LITERAL   = 'literal';    // String-Literal
  ROLE_OPERAND   = 'operand';    // eingefuegter Nicht-Literal-Operand
  ROLE_UNIT      = 'unit';       // Unit-Bezeichner in einer uses-Klausel
  ROLE_ARGUMENT  = 'argument';   // ein Argument eines Aufrufs (ohne Zerlegung)
  ROLE_IDENT     = 'ident';      // ein Bezeichner in der Code-Sicht

type
  // Was ueber den Wert eines Teilbereichs bekannt ist. rvNonString wird
  // nur vergeben, wenn es BEWIESEN ist - ohne Typaufloesung also nie.
  TRefactorValueType = (rvUnknown, rvString, rvNonString);

  // Kontext, in dem ein Umschreiben aufgeben oder vorsichtig sein muss.
  //   rfInConditional  Fundzeile liegt in einem {$IFDEF}-Bereich
  //   rfHasComment     im Bereich steht ein Kommentar (ginge beim
  //                    Ersetzen verloren)
  //   rfMultiLine      der Bereich umfasst mehr als eine Zeile
  //   rfFromInclude    RESERVIERT - der Core loest {$INCLUDE} nicht auf,
  //                    das Flag wird heute nie gesetzt
  TRefactorFlag  = (rfInConditional, rfHasComment, rfMultiLine,
                    rfFromInclude);
  TRefactorFlags = set of TRefactorFlag;

  TRefactorSpan = record
    Role      : string;
    StartLine : Integer;
    StartCol  : Integer;
    EndLine   : Integer;
    EndCol    : Integer;              // zeigt HINTER das letzte Zeichen
    ValueType : TRefactorValueType;
    Resolved  : string;               // aufgeloester Name, sonst leer
    // True wenn der Bereich wohlgeformt und nicht leer ist.
    function IsValid: Boolean;
    function IsSingleLine: Boolean;
    // Baut einen Bereich mit ValueType = rvUnknown und leerem Resolved.
    class function Make(const ARole: string;
      AStartLine, AStartCol, AEndLine, AEndCol: Integer): TRefactorSpan;
      static;
  end;

  TRefactorInfo = class
  public
    // Der ganze Befund-Bereich (B1).
    Span         : TRefactorSpan;
    // Benannte Teilbereiche samt Fakten (B2 + B3), in Quelltext-Reihenfolge.
    Parts        : TArray<TRefactorSpan>;
    // Der Detektor sichert zu, dass DIESER Fund umschreibbar ist (B4).
    // Default False - wird nur gesetzt, wenn es bewiesen ist.
    FixSafe      : Boolean;
    // Kontext-Flags (B5).
    Flags        : TRefactorFlags;
    // Einfuegepunkt fuer Umschreibungen, die Code HINZUFUEGEN (B6):
    // 1-basierte Zeile, VOR der eingefuegt wird; 0 = kein Einfuegepunkt.
    InsertLine   : Integer;
    // Einrueckung (Anzahl fuehrender Leerraum-Zeichen) fuer die
    // eingefuegte Zeile.
    InsertIndent : Integer;
    // SHA256 ueber den rohen Text von Span (B7). Leer = nicht berechnet.
    // Aendert sich bei JEDER Aenderung im Bereich - bewusst das Gegenteil
    // des drifttoleranten ContextHash der Baseline.
    SpanHash     : string;

    // Haengt einen Teilbereich an (Reihenfolge = Aufrufreihenfolge).
    procedure AddPart(const APart: TRefactorSpan);
    // Anzahl der Teilbereiche mit dieser Rolle.
    function CountOfRole(const ARole: string): Integer;
    // Tiefe Kopie. Der Aufrufer besitzt das Ergebnis. Wer eine
    // Beschreibung laenger haelt als den Dienst, der sie geliefert hat,
    // nimmt diese Funktion und kopiert NIE den Zeiger.
    function Clone: TRefactorInfo;
  end;

implementation

// noinspection-file PublicField, PublicMemberWithoutDoc, UnusedPublicMember
// Reiner Datentraeger nach dem Muster der Fund-Klasse (uMethodd12):
// oeffentliche Felder sind hier die Schnittstelle. Konsument ist
// reDelphix ausserhalb dieses Repos - der Selbstscan sieht ihn nicht.

{ TRefactorSpan }

function TRefactorSpan.IsValid: Boolean;
begin
  Result := (StartLine >= 1) and (StartCol >= 1) and (EndCol >= 1)
    and ((EndLine > StartLine)
      or ((EndLine = StartLine) and (EndCol > StartCol)));
end;

function TRefactorSpan.IsSingleLine: Boolean;
begin
  Result := EndLine = StartLine;
end;

class function TRefactorSpan.Make(const ARole: string;
  AStartLine, AStartCol, AEndLine, AEndCol: Integer): TRefactorSpan;
begin
  Result.Role      := ARole;
  Result.StartLine := AStartLine;
  Result.StartCol  := AStartCol;
  Result.EndLine   := AEndLine;
  Result.EndCol    := AEndCol;
  Result.ValueType := rvUnknown;
  Result.Resolved  := '';
end;

{ TRefactorInfo }

procedure TRefactorInfo.AddPart(const APart: TRefactorSpan);
var
  N : Integer;
begin
  N := Length(Parts);
  SetLength(Parts, N + 1);
  Parts[N] := APart;
end;

function TRefactorInfo.CountOfRole(const ARole: string): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to High(Parts) do
    if Parts[i].Role = ARole then
      Inc(Result);
end;

function TRefactorInfo.Clone: TRefactorInfo;
begin
  Result := TRefactorInfo.Create;
  Result.Span         := Span;
  // Copy() legt ein eigenes Array an. Die Elemente sind Records mit
  // Strings - Strings sind unveraenderlich geteilt, eine Aenderung am
  // Klon beruehrt das Original nicht.
  Result.Parts        := Copy(Parts);
  Result.FixSafe      := FixSafe;
  Result.Flags        := Flags;
  Result.InsertLine   := InsertLine;
  Result.InsertIndent := InsertIndent;
  Result.SpanHash     := SpanHash;
end;

end.
