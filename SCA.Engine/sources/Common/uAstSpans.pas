unit uAstSpans;

// Quell-Spannen ueber AST-Teilbaeume. Genau eine Frage, genau eine Antwort:
// welche ist die groesste Zeilennummer in einem Knoten und allen seinen
// Nachfahren.
//
// WARUM ES DIESE UNIT GIBT
//
// Die Frage war im Kernpaket ACHTFACH beantwortet, jedes Mal neu.
// Stand 2026-08-19 - sechs Kopien abgeloest, zwei bleiben mit Grund:
//   uLeakDetector2.pas         SubtreeMaxLine    - ABGELOEST
//   uUninitVar.pas             CalcMethodEndLine - ABGELOEST
//   uUnusedRoutine.pas         MaxLineOf         - ABGELOEST
//   uTypeResolver.pas          DeepMaxLine       - ABGELOEST
//   uLargeClass.pas            DeepMaxLine       - ABGELOEST (2 Stellen)
//   uLongMethod.pas            FindLastLine      - ABGELOEST 2026-08-19
//     (die achte Kopie; fehlte in dieser Liste, weil sie erst beim
//     Backlog-Sweep auffiel - rekursiv, jetzt der iterative Walk hier)
//   uParser2.pas:1624          MaxSubtreeLine    - BLEIBT: Hot-Path des
//     Parsers, iterativ, bewusst ohne Unit-Abhaengigkeit nach aussen
//   uUseAfterFree.pas:180      CalcMethodEndLine - BLEIBT: traegt eine
//     Degenerationsheuristik (Z.227-232), ist also KEINE reine Kopie
//
// Nach Normalisierung bleiben davon zwei Algorithmen uebrig, und die beiden
// rekursiven Fassungen sind zeichengleich zueinander. Das ist - anders als
// die Argument-Zerleger aus derselben Kampagne - eine echte Dublette ohne
// tragende Unterschiede: keine der sieben ueberspringt einen Knoten, eine
// Knotenart oder einen Zweig.
//
// DER VERTRAG VON SubtreeMaxLine
//
//   * ANode = nil liefert 0. Kein Zugriff, keine AV. Drei der Bestands-
//     kopien lesen als erste Anweisung die Zeile des Knotens und wuerden
//     bei nil abstuerzen; ihre Aufrufer reichen nie nil herein, die
//     nil-Behandlung hier ist also eine Haertung, keine Verhaltensaenderung.
//   * Das Ergebnis startet bei 0 und waechst nur, wenn eine besuchte Zeile
//     STRIKT groesser ist. Damit ist 0 zugleich die Antwort fuer nil und
//     fuer einen Baum, dessen Knoten alle die Default-Zeile 0 tragen.
//   * Der Knoten selbst zaehlt mit. Er wird als erster besucht, nicht als
//     Startwert vorbelegt. FUENF Bestandskopien belegen stattdessen mit der
//     Knotenzeile vor; die drei iterativen davon (uUseAfterFree.pas:183,
//     uUninitVar.pas:3316, uUnusedRoutine.pas:244) besuchen den Knoten
//     zusaetzlich - doppelt gezaehltes Maximum, ergebnisgleich -, die zwei
//     rekursiven (uTypeResolver.pas:165, uLargeClass.pas:87) nicht.
//     Bei Form B (Start 0) stehen nur uParser2.pas:1624 und die hier
//     abgeloeste Fassung. Ein Unterschied zwischen beiden Formen entstuende nur
//     bei NEGATIVEN Zeilennummern, und die gibt es nicht: der Lexer setzt
//     die Zeile auf 1 (uLexer.pas:315) und erhoeht sie ausschliesslich
//     (uLexer.pas:357), der Wurzelknoten entsteht mit Zeile 1
//     (uParser2.pas:266), und TAstNode.Line ist ein reines Konstruktor-Feld
//     mit Default 0 (uAstNode.pas:110-111, :248). Auf jedem geparsten Baum
//     gilt Line >= 1.
//   * Zwischenknoten mit Zeile 0 (synthetische Knoten, die ohne Zeilen-
//     argument entstehen) werden durchlaufen und ihre Kinder gepusht. Sie
//     senken das Maximum nie, sie schneiden aber auch keinen Teilbaum ab.
//     Wer sie wegfiltern wuerde, verloere bei allen Aufrufern Teilbaeume.
//
// KEIN GATE
//
// Diese Unit enthaelt keine Schwelle, keine Toleranz, keinen Filter und
// keine Knotenart-Ausnahme. Die Aufrufer haben solche Regeln - die '+2'-
// Toleranz fuer die schliessende end-Zeile in uUnusedRoutine.pas:367, die
// Kappung auf die Dateilaenge in uLeakDetector2.pas:2082, die Degeneriert-
// Korrektur in uUseAfterFree.pas:228 - und die bleiben dort. Die Projekt-
// lehre vom 2026-08-05 lautet: nie ein Gate in einen geteilten Helfer.
//
// WARUM ITERATIV UND WARUM OHNE HEAP-OBJEKT
//
// Zwei Bestandskopien rekursieren pro Kind ueber komplette Klassen- und
// Methoden-Teilbaeume. Genau diese Tiefe hat das Projekt schon einmal
// gezwungen, den Stapel der Anwendung im PE-Header zu vergroessern; die
// iterative Destruktion in uAstNode.pas:253 hat dieselbe Ursache. Der Walk
// hier fuehrt seinen eigenen Stapel.
//
// Der Stapel ist ein lokales dynamisches Feld mit Fuellstands-Index, kein
// Listen- oder Stack-Objekt. Grund: die beiden rekursiven Bestandskopien
// allozieren heute NICHTS, und sie laufen einmal je Klasse bzw. je Methode.
// Wuerde das Primitiv pro Aufruf ein Objekt erzeugen, waere ihre spaetere
// Umstellung ein Perf-Rueckschritt gegen die Stufe-1-Ergebnisse.
//
// Der Stapel darf ausserdem NIE eine besitzende Liste sein: TAstNode haelt
// seine Kinder in einer TObjectList mit OwnsObjects=True (uAstNode.pas:108,
// :250). Ein besitzender Arbeitsstapel gaebe beim Aufraeumen den halben AST
// frei. Ein dynamisches Feld besitzt nichts.

interface

uses
  uAstNode;

type
  TAstSpans = class
  public
    /// Groesste Zeilennummer ueber ANode und alle seine Nachfahren.
    /// ANode = nil liefert 0. Kein Filter, kein Gate, keine Toleranz.
    class function SubtreeMaxLine(ANode: TAstNode): Integer; static;
    /// Start-/Endzeilen aller nkNestedRange-Kinder der Methode - die
    /// Spannen der GESCHACHTELTEN Routinen. Was der Aufrufer damit tut,
    /// bleibt seine Politik: uRoutineResultAssigned schliesst die
    /// Spannen AUS (Result der inneren Routine ist nicht das eigene),
    /// uUnusedLocal schliesst sie EIN (ein Use im Nested zaehlt fuer
    /// die aeussere Variable). Ein Ende vor dem Start wird auf den
    /// Start geklemmt (StrToIntDef-Rueckfall).
    ///
    /// Bis 2026-09-04 lag die Logik byte-identisch in BEIDEN Detektoren;
    /// O6.2 (SCA001 K-nested) haette die dritte Kopie gebraucht und war
    /// genau daran zurueckgestellt (Rule of Three).
    class procedure CollectNestedSpans(AMethod: TAstNode;
      var AStarts, AEnds: TArray<Integer>); static;
  end;

implementation

// System.Generics.Collections wegen TAstNode.Children
// (TObjectList<TAstNode>): der Zugriff ueber die Default-Array-Property
// laeuft in TList<T>.GetItem, und ohne die deklarierende Unit im uses
// meldet der Compiler H2443/H2445 (inline nicht expandiert).
uses
  System.SysUtils,   // StrToIntDef (CollectNestedSpans)
  System.Generics.Collections;

const
  // Anfangsgroesse des Arbeitsstapels. Deckt die Verzweigungsbreite
  // typischer Methoden- und Klassenknoten ohne Nachwachsen ab; darueber
  // hinaus verdoppelt der Walk selbst.
  INITIAL_STACK_CAPACITY = 64;

class function TAstSpans.SubtreeMaxLine(ANode: TAstNode): Integer;
var
  Stack : TArray<TAstNode>;
  Top   : Integer;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := 0;
  if not Assigned(ANode) then Exit;

  // Pre-Order-Tiefensuche. Die Besuchsreihenfolge ist fuer ein Maximum
  // ohne Belang - die Bestandskopien laufen teils vorwaerts, teils
  // rueckwaerts, teils rekursiv und liefern denselben Wert.
  //
  // Der Stapel waechst ERST beim ersten Kind. Ein Blattknoten laeuft damit
  // wirklich ohne jede Allokation durch - sonst waere die Begruendung im
  // Kopf ('die rekursiven Bestandskopien allozieren heute nichts') beim
  // ersten Aufruf schon widerlegt.
  Top := 0;
  Cur := ANode;
  repeat
    if Cur.Line > Result then
    begin
      Result := Cur.Line;
    end;
    for i := 0 to Cur.Children.Count - 1 do
    begin
      if Top = Length(Stack) then
      begin
        if Length(Stack) = 0 then
        begin
          SetLength(Stack, INITIAL_STACK_CAPACITY);
        end
        else
        begin
          SetLength(Stack, Length(Stack) * 2);
        end;
      end;
      Stack[Top] := Cur.Children[i];
      Inc(Top);
    end;
    if Top = 0 then Break;
    Dec(Top);
    Cur := Stack[Top];
  until False;
end;

class procedure TAstSpans.CollectNestedSpans(AMethod: TAstNode;
  var AStarts, AEnds: TArray<Integer>);
var
  Ch  : TAstNode;
  Cnt : Integer;
begin
  AStarts := nil;
  AEnds   := nil;
  if AMethod = nil then Exit;
  Cnt := 0;
  for Ch in AMethod.Children do
    if Ch.Kind = nkNestedRange then
    begin
      Inc(Cnt);
      SetLength(AStarts, Cnt);
      SetLength(AEnds,   Cnt);
      AStarts[Cnt - 1] := Ch.Line;
      AEnds[Cnt - 1]   := StrToIntDef(Ch.TypeRef, Ch.Line);
      if AEnds[Cnt - 1] < AStarts[Cnt - 1] then
        AEnds[Cnt - 1] := AStarts[Cnt - 1];
    end;
end;

end.