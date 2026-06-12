unit uInstanceInvokedConstructor;

// Detektor: `<instance>.Create(...)` - Constructor auf einer Instance statt
// auf der Klasse.
//
// Pattern (Bug):
//   var Obj: TStringList;
//   begin
//     Obj := TStringList.Create;
//     ...
//     Obj.Create;          // <-- BUG: ruft Ctor-Code aber allokiert KEIN
//                          //     neues Objekt; das vorhandene Obj wird
//                          //     undefiniert (zweite Ctor-Ausfuehrung
//                          //     ueber dem schon initialisierten Speicher).
//   end;
//
// Korrekt:
//   Obj := TStringList.Create;
//
// Folge: Delphi laesst `Instance.Create` syntaktisch zu - der Compiler
// betrachtet einen Constructor als eine spezielle Klassen-Methode, die
// auch wie eine Instance-Methode aufgerufen werden kann. Die Allokations-
// Pfad-Logik (TObject.NewInstance + Klass-VMT-Setup) laeuft dann aber
// NICHT. Stattdessen werden Instanzvariablen ein zweites Mal initialisiert,
// Field-Defaults ueberschreiben gesetzte Werte, Refs auf gemanagte Typen
// werden ohne Freigabe ueberbuegelt - klassischer Memory-Corruption-
// Vorbote.
//
// Erkennung (heuristisch, kein Type-Resolver verfuegbar):
//   * Pattern `<Ident>.Create(...)` in nkCall.Name extrahieren.
//   * Wenn <Ident> mit Kleinbuchstaben beginnt -> eindeutig Variable/Field
//     (Delphi-Konvention: Typen sind T<Upper>... oder I<Upper>...,
//     Variablen/Fields oft lowercase oder f-Praefix).
//   * Skip: `Self`, `Result`, `Inherited` - reserviert / in Constructor
//     legitim.
//   * Skip: Multi-dot receivers (`Foo.Bar.Create`) - unklar ob Foo.Bar
//     Class oder Property.
//   * Skip: Cast-Form `T(...).Create` - faengt CastAndFreeCheck/andere.
//
// Bewusste False-Negatives (Praezisions-Trade-off ohne Typ-Info):
//   * `MyList.Create` (uppercase-Variable) wird NICHT gemeldet - zu hohe
//     Verwechslungsgefahr mit Klassennamen die keine T-Prefix-Konvention
//     einhalten.
//
// Bewusste False-Positives (akzeptabel selten):
//   * `cls.Create` wenn `cls: TFooClass` (class-reference Typ) -> dann
//     ist der Aufruf legitim. Class-reference-Typen sind in Delphi-Code
//     sehr selten; Trade-off zugunsten der Lesbarkeit der Heuristik.
//
// Sonar-Pendant: InstanceInvokedConstructorCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   InstanceInvokedConstructorCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInstanceInvokedConstructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or
            ((C >= 'a') and (C <= 'z')) or
            ((C >= '0') and (C <= '9')) or (C = '_');
end;

// Extrahiert den Receiver-Identifier aus `<Ident>.Create[(<args>)][;]`.
// Liefert leer, wenn Form nicht passt (z.B. Multi-Dot, Cast, kein .Create).
function ExtractCreateReceiver(const CallName: string): string;
const
  SUFFIX = '.Create';
var
  S        : string;
  i        : Integer;
  Depth    : Integer;
  ParenEnd : Integer;
  Ch       : Char;
begin
  Result := '';
  S := TrimRight(CallName);
  // Trailing ';' entfernen.
  while (S <> '') and (S[Length(S)] = ';') do
  begin
    SetLength(S, Length(S) - 1);
    S := TrimRight(S);
  end;
  if S = '' then Exit;

  // Wenn auf `Create(args)`-Form: balancierte Parens hinten abschneiden.
  if S[Length(S)] = ')' then
  begin
    Depth    := 0;
    ParenEnd := 0;
    for i := Length(S) downto 1 do
    begin
      case S[i] of
        ')': Inc(Depth);
        '(': begin
               Dec(Depth);
               if Depth = 0 then
               begin
                 ParenEnd := i;
                 Break;
               end;
             end;
      end;
    end;
    if ParenEnd = 0 then Exit;       // unbalanced
    SetLength(S, ParenEnd - 1);
    S := TrimRight(S);
  end;

  // Pruefe Suffix `.Create` (case-insensitive).
  if Length(S) <= Length(SUFFIX) then Exit;
  if not SameText(
    Copy(S, Length(S) - Length(SUFFIX) + 1, Length(SUFFIX)), SUFFIX) then
    Exit;
  SetLength(S, Length(S) - Length(SUFFIX));
  S := TrimRight(S);
  if S = '' then Exit;

  // Receiver muss EIN einzelner Identifier sein - kein '.', keine Klammern,
  // kein Whitespace mitten drin. Damit fangen wir Multi-Dot
  // (Owner.Sub.Create) und Cast-Form (T(L).Create) aus.
  for i := 1 to Length(S) do
  begin
    Ch := S[i];
    if not IsIdentChar(Ch) then Exit;
  end;
  Result := S;
end;

function LooksLikeInstance(const Ident: string): Boolean;
// True wenn Ident mit Lowercase beginnt UND keiner der reservierten Bezeichner
// (Self/Result/Inherited) ist. Konservative Heuristik - faengt die
// haeufigste Bug-Form ohne Type-Resolver-Aufwand.
begin
  if Ident = '' then Exit(False);
  if SameText(Ident, 'Self')      then Exit(False);
  if SameText(Ident, 'Result')    then Exit(False);
  if SameText(Ident, 'Inherited') then Exit(False);
  Result := (Ident[1] >= 'a') and (Ident[1] <= 'z');
end;

class procedure TInstanceInvokedConstructorDetector.AnalyzeMethod(
  MethodNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Calls : TList<TAstNode>;
  N     : TAstNode;
  Recv  : string;
  F     : TLeakFinding;
begin
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      Recv := ExtractCreateReceiver(N.Name);
      if not LooksLikeInstance(Recv) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        'Constructor invoked on instance "%s" - no allocation happens, fields get re-initialised',
        [Recv]);
      F.SetKind(fkInstanceInvokedConstructor);
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

class procedure TInstanceInvokedConstructorDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
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

