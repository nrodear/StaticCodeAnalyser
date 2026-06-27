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
  // Vorheriges Zeichen pruefen:
  //   '.'      -> Owner.Class.Create (kein atomarer Klassen-Ident) - skip
  //   '(' / ',' -> der Create steht als ARGUMENT in einem anderen Call
  //               (Func(EFoo.Create(...))) - die Exception wird weitergereicht
  //               (Handler/Logger/raise-Helper), kein statement-level
  //               Missing-Raise. Real-World 2026-06-27 (praeventiv).
  if (i >= 1) and CharInSet(CallName[i], ['.', '(', ',']) then Exit;
  Result := Copy(CallName, i + 1, PosDot - i - 1);
end;

function IsCreateDefinitionSignature(const CallName: string): Boolean;
// True wenn der '.Create(...)'-Match in Wahrheit eine KONSTRUKTOR-DEFINITION
// ist. Bei komplexen Custom-Exception-Konstruktoren (mORMot/JVCL, mehrzeilige
// Signatur mit const-Params + Typen wie RawUtf8/array of const) laeuft die
// Signatur-Parse in den Statement-Fallback - der qualifizierte Header
// 'EFoo.Create(const aMsg: RawUtf8; aConn: TConn)' landet als nkCall-Statement
// (Name inkl. Klammer-Inhalt). Attributions-UNABHAENGIGES Signal: die
// Argumente enthalten eine TYP-ANNOTATION (':') AUSSERHALB von Stringliteralen
// - das gibt es nur in Parameter-Deklarationen, NIE in einem echten raise-losen
// 'EFoo.Create(''msg'')'-Aufruf (Message-Strings mit ':' werden weggestrippt).
// Real-World 2026-06-27: EInterfaceStub.Create, EMongo*Exception.Create.
var
  Low   : string;
  p, i  : Integer;
  InStr : Boolean;
begin
  Result := False;
  Low := LowerCase(CallName);
  p := Pos('.create', Low);
  if p = 0 then Exit;
  while (p <= Length(CallName)) and (CallName[p] <> '(') do Inc(p);  // '(' nach .Create
  if p > Length(CallName) then Exit;
  InStr := False;
  for i := p + 1 to Length(CallName) do
  begin
    if CallName[i] = '''' then
      InStr := not InStr
    else if (not InStr) and (CallName[i] = ':') then
      Exit(True);
  end;
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
      // Die eigene 'constructor EFoo.Create(...)'-Definition ist kein
      // Missing-Raise. Zwei Wege, je nachdem wie der Parser den Header ablegt:
      //  (1) als nkMethod -> die umschliessende Methode IST <Target>.Create.
      //  (2) als Statement-nkCall (Signatur-Fallback bei komplexen Custom-
      //      Konstruktoren) -> erkennbar an der Parameter-Typ-Annotation.
      // Real-World 2026-06-27: EInterfaceStub.Create, EMongo*Exception.Create.
      if SameText(MethodNode.Name, Target + '.Create') then Continue;
      if IsCreateDefinitionSignature(N.Name) then Continue;

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
