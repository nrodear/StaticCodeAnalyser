unit uMissingRaise;

// Detektor: Exception-Klasse via .Create instanziiert, aber nicht 'raise'd.
//
// Pattern (Bug):
//   begin
//     ...
//     EConvertError.Create('Bad input');   // <-- erzeugt, nie geraised
//     ...
//   end;
//
// Korrekt:
//   raise EConvertError.Create('Bad input');
//
// Folge: Objekt wird allokiert und sofort vom Garbage-Pfad/ARC eingesammelt
// (bzw. leakt bei klassischen TObject). Aufrufer denkt, der Fehlerpfad
// wurde ausgeloest - er laeuft aber weiter. Klassischer Copy-Paste-Bug
// nach Refactoring von raise-Ketten.
//
// Erkennung: Parser legt 'raise X.Create(...)' als nkRaise-Knoten ab und
// konsumiert den Call darin als String (siehe uParser2.ParseRaiseStmt).
// Dadurch existiert KEIN nkCall-Subtree fuer geraisete Exceptions. Also:
//   * Iteriere alle nkCall in Method-Bodies
//   * Wenn Call-Name dem Muster `<Identifier>.Create(...)` entspricht und
//     <Identifier> eine Exception-Klasse ist -> Finding.
//
// Exception-Klassen-Heuristik (kein Type-Resolver verfuegbar):
//   * Name = 'Exception' (RTL-Basis)
//   * ODER Name beginnt mit 'E' + Grossbuchstabe (Delphi-Konvention:
//     EConvertError, EAccessViolation, EMyDomainError ...)
//
// Bewusst NICHT als Finding:
//   * 'Edit.Create', 'Encoding.Create' - 2. Zeichen klein, keine Exception.
//   * 'MyException.Create' - kein E-Prefix, Konvention verletzt; eigener
//     Naming-Detector fkExceptionName meldet das schon.
//
// Sonar-Pendant: MissingRaiseCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   MissingRaiseCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TMissingRaiseDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeStrictPrivate, CyclomaticComplexity, GroupedDeclaration, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsUpperAsciiLetter(C: Char): Boolean; inline;
begin
  Result := (C >= 'A') and (C <= 'Z');
end;

// Liefert True wenn S eine Exception-Klasse nach Delphi-Konvention ist:
// 'Exception' direkt, oder 'E' + Grossbuchstabe + weitere Zeichen.
function LooksLikeExceptionClass(const S: string): Boolean;
begin
  if S = '' then Exit(False);
  if SameText(S, 'Exception') then Exit(True);
  Result := (Length(S) >= 2) and (S[1] = 'E') and IsUpperAsciiLetter(S[2]);
end;

// Extrahiert den Klassen-Identifier aus einem Call-Namen, wenn die Form
// '<Ident>.Create(...)' (case-insensitive) vorliegt. Sonst leerer String.
//
// Beispiele:
//   'Exception.Create('foo')'  -> 'Exception'
//   'EConvertError.Create()'   -> 'EConvertError'
//   'Self.DoSomething(...)'    -> ''     (kein .Create)
//   'X.Y.Create(...)'          -> ''     (nicht atomarer Klassen-Ident -
//                                         Owner.Member.Create faengt das aus,
//                                         haetten wir kein Bug-Pattern)
function ExtractCreateTarget(const CallName: string): string;
const
  DOT_CREATE = '.Create';
var
  L, PosDot : Integer;
  Ch        : Char;
  i         : Integer;
begin
  Result := '';
  L := Length(CallName);
  if L < Length(DOT_CREATE) + 1 then Exit;
  // Index des Punkts vor 'Create'. Wir nehmen das LETZTE '.' im Namen
  // bis vor 'Create' - so faengt 'TFoo.Bar.Create()' nicht.
  PosDot := 0;
  i := 1;
  while i <= L - Length(DOT_CREATE) do
  begin
    if (CallName[i] = '.') and
       SameText(Copy(CallName, i, Length(DOT_CREATE)), DOT_CREATE) then
    begin
      // Verify: hinter '.Create' folgt '(' oder Ende oder Whitespace.
      if i + Length(DOT_CREATE) > L then
      begin
        PosDot := i;
        Break;
      end;
      Ch := CallName[i + Length(DOT_CREATE)];
      if (Ch = '(') or (Ch = ' ') or (Ch = ';') then
      begin
        PosDot := i;
        Break;
      end;
    end;
    Inc(i);
  end;
  if PosDot = 0 then Exit;

  // Identifier links vom Punkt holen (zurueck bis Whitespace/Operator).
  // Nur reine Ident-Zeichen. Wenn wir auf '.' stossen, ist es kein
  // atomarer Klassen-Ident (TFoo.Bar.Create) - skip.
  i := PosDot - 1;
  while i >= 1 do
  begin
    Ch := CallName[i];
    if (Ch = '_') or
       ((Ch >= 'A') and (Ch <= 'Z')) or
       ((Ch >= 'a') and (Ch <= 'z')) or
       ((Ch >= '0') and (Ch <= '9')) then
      Dec(i)
    else
      Break;
  end;
  // Falls das vorherige Zeichen ein '.' war: Owner.Class.Create - skip.
  if (i >= 1) and (CallName[i] = '.') then Exit;
  Result := Copy(CallName, i + 1, PosDot - i - 1);
end;

class procedure TMissingRaiseDetector.AnalyzeMethod(MethodNode: TAstNode;
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
      Target := ExtractCreateTarget(N.Name);
      if not LooksLikeExceptionClass(Target) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        'Exception %s.Create(...) is constructed but never raised', [Target]);
      F.SetKind(fkMissingRaise);
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

class procedure TMissingRaiseDetector.AnalyzeUnit(UnitNode: TAstNode;
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
