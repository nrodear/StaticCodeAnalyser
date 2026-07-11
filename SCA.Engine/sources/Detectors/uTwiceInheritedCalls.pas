unit uTwiceInheritedCalls;

// Detektor fuer Methoden mit mehrfachem `inherited;` Aufruf.
//
// SonarDelphi-Aequivalent: communitydelphi:TwiceInheritedCalls. Mehrere
// `inherited`-Aufrufe in derselben Methode sind fast immer ein Bug:
// jeder Aufruf invoked die Parent-Implementierung ein weiteres Mal,
// was Side-Effekte verdoppelt (z.B. zweimal `OnChange` feuern).
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten zaehle `nkInherited`-
// Vorkommen im Body-Block. Bei >= 2 wird auf der Methoden-Zeile gemeldet.
//
// Schweregrad: lsWarning.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTwiceInheritedCallsDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsWarning;

// Maximale Anzahl `inherited`-Calls die DIREKTE Kinder EINES nkBlock sind
// (= sequenziell im selben begin..end-Block, laufen also garantiert beide).
// Der Methoden-Rumpf selbst ist ein nkBlock (ParseBlock) -> der Kanonik-Bug
// `procedure X; begin inherited; inherited; end;` wird erfasst.
//
// inherited-Calls die ueber verschiedene Branches verteilt sind (if/else,
// case-Arme, except/on-Handler) haengen an nkIfStmt/nkCase/nkExceptBlock/
// nkOnHandler - NICHT an einem nkBlock - und werden NICHT zusammengezaehlt.
// Damit faellt der dominante FP weg: mutual-exklusive `inherited` (z.B.
// message-/WndProc-Handler mit if-Kaskade), wo pro Aufruf nur EINER laeuft
// (~90% FP, Welle 3, 2026-06-28).
//
// Bewusster (seltener) FN: 2 sequenzielle `inherited` direkt im try-Rumpf
// (`try inherited; inherited; finally`), in einem repeat-Rumpf oder im
// finally-Block - dort sind die Statements direkte Kinder von nkTryFinally/
// nkTryExcept/nkRepeat/nkFinallyBlock statt nkBlock. Akzeptiert zugunsten
// der FP-Reduktion; ggf. spaeter den Container-Kind-Set erweitern.
// Real-World-FP-Audit 2026-07-10: Liefert den fuehrenden Bezeichner eines
// `inherited`-CallExpr (bis zum ersten '.', '(', '[' oder '^'). Beispiele:
// 'Bitmap.Assign' -> 'Bitmap', 'Create(self.f)' -> 'Create', '' -> ''.
function LeadingInheritedIdent(const CallExpr: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 1 to Length(CallExpr) do
  begin
    if CharInSet(CallExpr[i], ['.', '(', '[', '^', ' ']) then Break;
    Result := Result + CallExpr[i];
  end;
end;

// Kurzer (unqualifizierter) Methoden-Name: nkMethod.Name ist 'TFoo.Bar'.
function ShortMethodName(const AName: string): string;
var p: Integer;
begin
  p := LastDelimiter('.', AName);
  if p > 0 then Result := Copy(AName, p + 1, MaxInt) else Result := AName;
end;

// Real-World-FP-Audit 2026-07-10: Nur `inherited` das die GLEICHE
// Parent-Methode ERNEUT aufruft verdoppelt deren Side-Effekte:
//   (a) bare `inherited;` (leerer CallExpr) oder
//   (b) `inherited <SelbeMethode>(...)` mit passendem Methoden-Namen.
// Bisher zaehlte DirectChildCount(nkInherited) JEDES `inherited`-Token und
// meldete damit qualifizierte Parent-Member-Zugriffe als Doppelaufruf:
//   `inherited TabStop := False`, `inherited Bitmap.Assign`,
//   `inherited ReadOnly := True`, oder verschiedene Parent-Methoden
//   nebeneinander (`inherited Lock` + `inherited Unlock`). Keiner davon
//   ruft die eigene Parent-Methode zweimal -> alle 30 gesampelten Funde FP.
function QualifyingInheritedInBlock(Block: TAstNode;
  const MethShortName: string): Integer;
var
  Child : TAstNode;
begin
  Result := 0;
  for Child in Block.Children do
  begin
    if Child.Kind <> nkInherited then Continue;
    if (Child.Name = '') or
       SameText(LeadingInheritedIdent(Child.Name), MethShortName) then
      Inc(Result);
  end;
end;

function MaxSequentialInheritedInBlock(MethodNode: TAstNode): Integer;
var
  Blocks  : TList<TAstNode>;
  B       : TAstNode;
  C       : Integer;
  ShortNm : string;
begin
  Result  := 0;
  ShortNm := ShortMethodName(MethodNode.Name);
  Blocks  := MethodNode.FindAll(nkBlock);
  try
    for B in Blocks do
    begin
      C := QualifyingInheritedInBlock(B, ShortNm);
      if C > Result then Result := C;
    end;
  finally
    Blocks.Free;
  end;
end;

// Liefert den Body-Block oder nil bei Forward-Deklarationen
// (Class-Body-Signatur). Konsistent mit uConstructor/uDestructor-
// WithoutInherited, deren False-Positive-Fix wir hier mitziehen.
function FindBodyBlock(MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then Exit(Child);
end;

class procedure TTwiceInheritedCallsDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Count   : Integer;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      // Nur echte Implementierungen - Forward-Decls haben keinen Body.
      if FindBodyBlock(M) = nil then Continue;
      Count := MaxSequentialInheritedInBlock(M);
      if Count < 2 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        '%d sequential `inherited` calls in the same block - parent ' +
        'side-effects run twice. Keep one call or extract helpers.', [Count]);
      F.SetKind(fkTwiceInheritedCalls);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
