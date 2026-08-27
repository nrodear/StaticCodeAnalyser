unit uConstantReturn;

// Detektor: Function weist `Result` mehrfach denselben Literal-Wert zu.
//
// Pattern (Code Smell, Sonar-50 #43):
//   function GetTimeout: Integer;
//   begin
//     if SlowMode then
//       Result := 30
//     else
//       Result := 30;             // <-- alle Pfade -> immer 30
//   end;
//
// Korrekt:
//   const DEFAULT_TIMEOUT = 30;
//   ...
//   function GetTimeout: Integer;
//   begin
//     Result := DEFAULT_TIMEOUT;  // oder: einfach die Konstante direkt nutzen
//   end;
//
// Folge: zwei oder mehr `Result := ...` mit IDENTISCHEM Literal sind
// entweder ein Refactoring-Rest (eines wurde nie angepasst) oder dead
// branching (das `if` hat keinen Effekt). Beides ist ein Smell.
//
// Erkennung (AST):
//   * nkMethod der Function ist (TypeRef enthaelt ':').
//   * Sammle ALLE nkAssign mit LHS = `result` oder `<FnName>`, dazu die
//     Literal-Argumente aller nkExit (`Exit(30)` ist eine Rueckgabe wie
//     eine Zuweisung).
//   * Mindestens 2 solche Werte vorhanden.
//   * Die Werte sind ALLE identisch UND sehen aus wie Literale (Zahl,
//     String-Literal, True/False/nil).
//   * KEINE andere Beruehrung von `Result` im Rumpf (Escape-Scan, s.u.).
//   * -> Finding am Method-Header.
//
// ESCAPE-SCAN (FP-Paket SCA151, 2026-08-27)
//
// Bis dahin zaehlte der Detektor NUR `Result := <Literal>` und war fuer
// jede andere Mutation blind - er behauptete "always returns X" bei
// Funktionen, die Result sehr wohl veraendern. Belegte Klassen:
//
//   * var/out-Argument bzw. Adress-Uebergabe:
//     mormot.core.text.pas:3010 GetNextItemHexa hat zweimal `result := 0`
//     und dazwischen `HexDisplayToBin(@tmp, @result, L shr 1)` - der
//     Rueckgabewert wird ueber den Zeiger gefuellt. Gleiche Klasse:
//     `Supports(X, IFoo, Result)` (CnWizUtils.pas:4450), `SetLength(Result,
//     N)`, `Inc(Result)`, `pointer(Result)^`.
//   * Lese-Zugriff in einer Bedingung: wer Result in `if`/`while`/`case`
//     abfragt, benutzt ihn als Akkumulator - "immer X" ist dann unbelegt.
//   * Suchidiom `for Result := 0 to Count - 1 do` (Alcinoe.QuickSortList.pas:726):
//     der Schleifenkopf ist KEIN nkAssign, die Laufvariable ist trotzdem
//     Result.
//   * Indizierte Zuweisung `Result[i] := x`: faellt still durch IsResultLhs.
//
// Der Scan sucht dazu ein BARE-WORD `result` (bzw. den Funktionsnamen) im
// Text von nkCall.Name (traegt seit uParser2 den vollen Argumenttext),
// nkIfStmt/nkWhileStmt/nkForStmt/nkCaseStmt.TypeRef und in der LHS
// indizierter nkAssign. 128 der 180 Korpus-Funde fallen darueber weg.
//
// Bewusst NICHT im Scan (beides am Parser gemessen, waere tote Zeile):
//   * nkRepeatStmt.TypeRef ist IMMER leer - ParseRepeatStmt verwirft den
//     until-Ausdruck per SkipToSemicolon (uParser2.pas:2582-2583).
//   * `LFoo: Integer absolute Result` ist ueber nkLocalVar.TypeRef nicht
//     findbar: der Parser konkateniert die Typ-Tokens OHNE Worttrenner.
//
// TP-Kollateral (genau 1, akzeptiert): IdStackVCLPosix.pas:1169 ReceiveMsg
// hat zweimal `Result := 0` und in Zeile 1170 `CheckForSocketError(
// RecvMsg(ASocket, LMsg, Result))` - dort ist Result das BY-VALUE-Argument
// `flags`, also kein Escape. Ohne Signaturwissen ist das vom var-Fall nicht
// trennbar; wir nehmen den Verlust in Kauf, weil die Gegenrichtung (128 FP)
// zwei Groessenordnungen schwerer wiegt.
//
// Limitierungen:
//   * Mit Variablen-Referenzen statt Literalen: nicht erfasst (waere
//     ggf. legitim, z.B. `Result := DEFAULT_TIMEOUT;` zweimal).
//   * Nur die nkAssign-Children werden geprueft - komplexere RHS-Sub-
//     trees mit gleichem strukturellem Wert (`Result := 30 + 0` vs
//     `Result := 30`) werden NICHT als identisch erkannt.
//   * `Exit('x')` und `Result := 'x'` gelten als VERSCHIEDENE Werte: der
//     Exit-Argument-Scanner des Parsers (uParser2.pas:2149-2168) ruft
//     KEIN QuoteStrLit, das Literal kommt also ohne Apostrophe an. Kostet
//     im schlimmsten Fall einen Fund - nie einen falschen.
//
// Schweregrad: lsHint - Refactoring-Empfehlung.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConstantReturnDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file LongMethod, NestedTry, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uDetectorUtils;  // UnqualifiedNameLast (Restschulden-Audit 2026-07-26)

// Restschulden-Audit 2026-07-26: lokale UnqualifiedName-Kopie entfernt -
// jetzt TDetectorUtils.UnqualifiedNameLast (war in 8 Detektoren dupliziert,
// eine Kopie mit abweichender Semantik). Verhalten hier unveraendert.

function IsFunctionMethod(const TypeRef: string): Boolean;
// Parser legt MethKind + optional Returntyp + Direktiven in TypeRef ab:
//   procedure         -> 'procedure'
//   function: Integer -> 'function:Integer'
//   function: T; virtual -> 'function:T;virtual'
// Wir wollen alle Varianten matchen die mit 'function' beginnen.
begin
  Result := StartsText('function', Trim(TypeRef));
end;

function IsResultLhs(const LhsLow, FnNameLow: string): Boolean;
begin
  Result := (LhsLow = 'result') or (LhsLow = FnNameLow);
end;

function IsIndexedResultLhs(const LhsLow, FnNameLow: string): Boolean;
// `Result[i] := x` erreicht IsResultLhs nie: ParsePrimary haengt fuer jeden
// Index-Suffix ein '[]' an (uParser2.pas:3052-3058), die LHS heisst also
// 'result[]' bzw. 'result[].feld'. Diese Zuweisung fiel bis 2026-08-27
// STILL durch - eine Funktion, die ihr Array-Ergebnis elementweise fuellt
// und daneben zweimal denselben Literal-Default setzt, galt als
// "always returns X".
// Praefix-Vergleich statt Wortsuche: 'resultmap[' faengt NICHT an mit
// 'result[', die Wortgrenze steckt also schon in der eckigen Klammer.
begin
  Result := StartsStr('result[', LhsLow) or
            ((FnNameLow <> '') and StartsStr(FnNameLow + '[', LhsLow));
end;

function HasBareWordUse(const HaystackLow, WordLow: string): Boolean;
// Wortgrenze links UND rechts, PLUS: links darf KEIN '.' stehen.
// TDetectorUtils.FindWholeWordLower kann das nicht ersetzen - dort ist der
// Punkt eine gueltige linke Grenze ('mytable.sql' matcht 'sql'), hier muss
// er der Ausschluss sein: 'FMsg.Result' ist ein fremdes Member (TMessage
// hat ein Feld dieses Namens), kein Zugriff auf den eigenen Rueckgabewert.
var
  P, L, H : Integer;
  LeftOK  : Boolean;
  RightOK : Boolean;
begin
  Result := False;
  L := Length(WordLow);
  H := Length(HaystackLow);
  if (L = 0) or (H < L) then Exit;
  P := PosEx(WordLow, HaystackLow, 1);
  while P > 0 do
  begin
    LeftOK := (P = 1) or
              ((not TDetectorUtils.IsIdentChar(HaystackLow[P - 1])) and
               (HaystackLow[P - 1] <> '.'));
    RightOK := (P + L > H) or
               (not TDetectorUtils.IsIdentChar(HaystackLow[P + L]));
    if LeftOK and RightOK then Exit(True);
    P := PosEx(WordLow, HaystackLow, P + 1);
  end;
end;

function MentionsResultBare(const S, FnNameLow: string): Boolean;
// Hausinvariante: Strings zaehlen NIE als Code-Use. Der Parser legt
// Stringliterale in QUELLTEXT-Form (inkl. Apostrophe, uParser2.pas:190
// QuoteStrLit) in Name/TypeRef ab - ohne das Strippen waere
// `Log('no result yet')` ein Result-Zugriff und wuerde einen echten Fund
// verschlucken. Kommentare erreichen den Tokenstrom gar nicht erst.
var
  Txt : string;
begin
  Result := False;
  if S = '' then Exit;
  Txt := LowerCase(TDetectorUtils.StripStringLiterals(S));
  Result := HasBareWordUse(Txt, 'result') or
            ((FnNameLow <> '') and HasBareWordUse(Txt, FnNameLow));
end;

function MethodUsesResultOutsidePlainAssign(M: TAstNode;
  const FnNameLow: string): Boolean;
// Siehe ESCAPE-SCAN im Unit-Kopf. FindAllRef statt FindAll: rein lesende
// Iteration, kein Free, keine Mutation - genau der auditierte Kontrakt aus
// uAstNode.pas:145-151, und damit ohne Listen-Kopie pro Kind.
const
  // nkCall traegt seinen Text im Name (ParsePrimary baut '<Fn>(<Args>)',
  // uParser2.pas:3149), die Statement-Koepfe tragen ihn im TypeRef.
  COND_KINDS: array[0..3] of TNodeKind =
    (nkIfStmt, nkWhileStmt, nkForStmt, nkCaseStmt);
var
  Lst : TList<TAstNode>;
  N   : TAstNode;
  k   : Integer;
begin
  Result := False;

  Lst := M.FindAllRef(nkCall);
  for N in Lst do
    if MentionsResultBare(N.Name, FnNameLow) then Exit(True);

  for k := Low(COND_KINDS) to High(COND_KINDS) do
  begin
    Lst := M.FindAllRef(COND_KINDS[k]);
    for N in Lst do
      if MentionsResultBare(N.TypeRef, FnNameLow) then Exit(True);
  end;

  Lst := M.FindAllRef(nkAssign);
  for N in Lst do
    if IsIndexedResultLhs(LowerCase(Trim(N.Name)), FnNameLow) then Exit(True);
end;

function LooksLikeLiteral(const S: string): Boolean;
// Schmale Heuristik: Zahl, String-Literal, True/False/nil.
var
  T : string;
  Low : string;
  i : Integer;
  HexOk : Boolean;
begin
  T := Trim(S);
  if T = '' then Exit(False);
  Low := LowerCase(T);
  if (Low = 'true') or (Low = 'false') or (Low = 'nil') then Exit(True);
  // String-Literal: beginnt + endet mit ''.
  if (T[1] = '''') and (T[Length(T)] = '''') then Exit(True);
  // Numerisches Literal (optional Vorzeichen + Ziffern, evtl. Punkt).
  //
  // 2026-08-27: Hex-Ziffern a..f NUR nach '$'-Praefix. Ohne diese Klammer
  // ist jeder Bezeichner aus a..f ein Pseudo-Literal - belegt an
  // JclRegistry.pas:1015 RegReadIntegerDef (`Result := Def` in beiden
  // Zweigen -> "always returns Def", 10 Schwestern in derselben Unit) und
  // mormot.core.buffers.pas:9408 EscapeBuffer (`result := d`, d ist der
  // PAnsiChar-Parameter). 13 Faelle im Korpus, alle FP.
  HexOk := (T[1] = '$') or
           ((Length(T) > 1) and CharInSet(T[1], ['-', '+']) and (T[2] = '$'));
  for i := 1 to Length(T) do
  begin
    if CharInSet(T[i], ['0'..'9', '-', '+', '.', '$']) then Continue;
    if HexOk and CharInSet(T[i], ['a'..'f', 'A'..'F']) then Continue;
    Exit(False);
  end;
  Result := True;
end;

function ExtractRhs(N: TAstNode): string;
// Parser legt RHS-Text in nkAssign.TypeRef ab (uParser2.pas Z. 1618:
// "Node.TypeRef := FullRHS"). Children sind in der Regel leer.
// Defensiv: erstes Child als Fallback fuer aeltere AST-Formen.
begin
  if N.TypeRef <> '' then
    Result := Trim(N.TypeRef)
  else if N.Children.Count > 0 then
    Result := Trim(N.Children[0].Name)
  else
    Result := '';
end;

function ExtractExitArg(N: TAstNode): string;
// `Exit(<arg>)` legt den Argumenttext in nkExit.TypeRef ab - aber mit einem
// BLANKO-Leerzeichen zwischen JEDEN zwei Tokens (uParser2.pas:2163), nicht
// mit dem wortgrenzen-bewussten JoinTokInto des RHS-Scanners. `Exit(-1)`
// kommt darum als '- 1' an, waehrend dieselbe Rueckgabe als `Result := -1`
// '-1' liefert. Ohne die Normalisierung waere das erstens kein Literal und
// zweitens ungleich zum Assign-Zwilling - beides Fund-Verlust ohne Grund.
begin
  Result := StringReplace(Trim(N.TypeRef), ' ', '', [rfReplaceAll]);
end;

class procedure TConstantReturnDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods   : TList<TAstNode>;
  M         : TAstNode;
  Assigns   : TList<TAstNode>;
  Exits     : TList<TAstNode>;
  N         : TAstNode;
  FnNameLow : string;
  LhsLow    : string;
  Rhs       : string;
  RhsSet    : TList<string>;
  Same      : Boolean;
  Skip      : Boolean;
  S         : string;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not IsFunctionMethod(M.TypeRef) then Continue;
      FnNameLow := LowerCase(TDetectorUtils.UnqualifiedNameLast(M.Name));

      // nil-init vor dem try (uDuplicateString-Muster): wirft M.FindAll,
      // gibt das finally ein bereits erzeugtes RhsSet sauber frei statt es
      // zu lecken.
      RhsSet  := nil;
      Assigns := nil;
      Exits   := nil;
      try
        RhsSet  := TList<string>.Create;
        Assigns := M.FindAll(nkAssign);
        Skip    := False;
        for N in Assigns do
        begin
          LhsLow := LowerCase(Trim(N.Name));
          if not IsResultLhs(LhsLow, FnNameLow) then Continue;
          Rhs := ExtractRhs(N);
          if not LooksLikeLiteral(Rhs) then
          begin
            // Wenn eine RHS NICHT-literal ist, koennen wir nicht
            // entscheiden -> Method skippen.
            Skip := True;
            Break;
          end;
          RhsSet.Add(Rhs);
        end;

        // `Exit(<Literal>)` ist eine Rueckgabe wie eine Zuweisung und gehoert
        // in dieselbe Menge: ein ABWEICHENDES Literal disqualifiziert dann
        // ueber den Same-Check weiter unten. Belegfall
        // Alcinoe.FMX.Controls.pas:1902 IsAncestorOf - zweimal
        // `Result := False`, dazwischen `Exit(True)`; bis 2026-08-27 als
        // "always returns False" gemeldet.
        //
        // *** LEERER TypeRef IST NEUTRAL. *** Ein argumentloses `Exit;`
        // erzeugt denselben nkExit-Knoten, nur ohne TypeRef
        // (uParser2.pas:2124-2171 - das Eat(tkLParen) schlaegt fehl, TypeRef
        // bleibt unberuehrt). Wer es als Skip ODER als RhsSet-Eintrag
        // wertet, loescht 35 der 48 verbleibenden echten Funde - der
        // Fruehausstieg `if AFlag then Exit;` steht in fast jeder von ihnen.
        if not Skip then
        begin
          Exits := M.FindAll(nkExit);
          for N in Exits do
          begin
            Rhs := ExtractExitArg(N);
            if Rhs = '' then Continue;
            if not LooksLikeLiteral(Rhs) then
            begin
              Skip := True;
              Break;
            end;
            RhsSet.Add(Rhs);
          end;
        end;
        if Skip then Continue;

        if RhsSet.Count < 2 then Continue;
        // Pruefen ob alle gleich.
        Same := True;
        for S in RhsSet do
          if S <> RhsSet[0] then
          begin
            Same := False;
            Break;
          end;
        if not Same then Continue;

        // Escape-Scan als LETZTES Gate, nicht vor der Zaehlschleife: er ist
        // seiteneffektfrei und haengt nur an (M, FnNameLow), das Ergebnis ist
        // an beiden Stellen dasselbe. Hier laeuft er nur fuer die Handvoll
        // Methoden, die den Same-Literal-Test ueberhaupt bestehen (Korpus:
        // 180), statt fuer JEDE Function im Scan - das sind sechs
        // Subtree-Walks und sechs Cache-Listen pro Function, die wir uns
        // sparen.
        if MethodUsesResultOutsidePlainAssign(M, FnNameLow) then Continue;

        Results.Add(TLeakFinding.New(FileName, M.Name, M.Line,
          Format('Function %s always returns %s on every code path - use ' +
                 'a named constant',
            [TDetectorUtils.UnqualifiedNameLast(M.Name), RhsSet[0]]),
          fkConstantReturn));
      finally
        Exits.Free;
        Assigns.Free;
        RhsSet.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
