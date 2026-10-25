unit uInheritedMethodEmpty;

// Detektor SCA125: override-Methode, deren gesamter Rumpf nur den
// Vorfahren mit denselben Argumenten ruft.
//
// Pattern (Code-Smell):
//   type TFoo = class(TBar)
//   protected
//     procedure Paint; override;
//   end;
//   procedure TFoo.Paint;
//   begin
//     inherited;   // <-- nichts weiter
//   end;
//
// Korrekt: Override komplett LOESCHEN (Deklaration + Implementierung). Die
// virtuelle Bindung ruft ohne Override ohnehin die Methode des Vorfahren.
//
// REPARATUR Q14 (2026-10-23): der Detektor verlangte ';override' im
// TypeRef des Knotens MIT Rumpf. Delphi-Implementierungskoepfe wiederholen
// 'override' aber nicht - die Direktive steht nur an der Deklaration in
// der Klasse. Korpus: genau EIN Implementierungskopf mit 'override' (Indy
// IdStackLibc.pas:679, Rumpf kein inherited) -> 0 Funde ueber Monate. Die
// Tests nutzten dieselbe ungueltige Form und prueften Selbstkonsistenz.
// Jetzt liest der Detektor die DEKLARATION (Bewegungsvertrag A4: Python-
// Nachbildung 1.400 fcHigh + 264 fcLow im Korpus, Stichprobe 20/20 echt).
//
// Erkennung (je Implementierungsknoten 'TKlasse.Name'):
//   * keine Klassenmethode, keine lokalen Deklarationen, GENAU EINE
//     Anweisung:
//       inherited;                     (nicht in Funktionen)
//       inherited Name;                (nur ohne Parameter)
//       inherited Name(p1, .., pn);    (Parameter 1:1, gleiche Reihenfolge)
//       Result := inherited [Name[(p1, .., pn)]];   (nur Funktionen)
//   * genau EIN Klassenknoten dieses Namens in der Unit und darin genau
//     EINE Deklaration des Methodennamens (sonst Ueberladung oder
//     {$IFDEF}-Zwilling - nicht eindeutig);
//   * Deklaration mit 'override' und KEINER weiteren Direktive (message,
//     final, overload, reintroduce, deprecated, Aufrufkonvention ...),
//     ohne Attribut, ohne Default-Parameter (Deklaration und Kopf);
//   * keine Compilerdirektive zwischen Implementierungskopf und 'end'.
//   Die letzten beiden Punkte liest der Detektor aus dem Quelltext (der
//   Parser verwirft Attribute und 'final'/'message'); ohne lesbare Datei
//   meldet er nichts.
//
// Sichtbarkeit (Loeschen eines Overrides in einem SICHTBAREREN Abschnitt
// als der Vorfahr bricht Aufrufer - dann ist das Override nicht leer):
//   * Vorfahr mit gleichnamiger Methode in derselben Unit: Override
//     sichtbarer als Vorfahr -> kein Fund; sonst Fund (fcHigh).
//   * Vorfahr ausserhalb der Unit: private/protected -> fcHigh; public
//     und eine bekannte public-Methode aus TObject/TPersistent/TComponent
//     (Destroy, Create, AfterConstruction, ...) -> fcHigh; sonst
//     (public/published ohne Beleg) fcLow - im Auslieferungs-Default
//     unsichtbar. Beleg: DMVC TBaseController.OnBeforeAction hebt protected
//     nach public an.
//
// Sonar-Pendant: InheritedMethodWithNoCodeCheck

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TInheritedMethodEmptyDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file CanBeStrictPrivate, MultipleExit, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - Guard-Ketten mit Exit sind hier die Lesart.

uses
  System.StrUtils,
  uFileTextCache, uDetectorUtils;

const
  // Woerter, die hinter einer Methodendeklaration als Direktive stehen
  // koennen. Jede davon ausser 'override' sperrt den Fund: sie aendert
  // Bindung, Aufruf oder Compilerverhalten und ginge mit dem Loeschen
  // verloren. Kleinbuchstaben.
  DIREKTIV_WOERTER: array[0..27] of string = (
    'virtual', 'dynamic', 'abstract', 'overload', 'reintroduce', 'static',
    'inline', 'final', 'message', 'dispid', 'deprecated', 'platform',
    'experimental', 'library', 'stdcall', 'cdecl', 'register', 'pascal',
    'safecall', 'varargs', 'winapi', 'export', 'assembler', 'noreturn',
    'unsafe', 'external', 'forward', 'far');

  // Bekannte public-virtuelle Methoden der Wurzelklassen (TObject,
  // TPersistent, TComponent) als 'art:name'. Ein public-Override dieser
  // Namen hebt keine Sichtbarkeit an.
  BEKANNT_PUBLIC: array[0..7] of string = (
    'destructor:destroy', 'constructor:create',
    'procedure:afterconstruction', 'procedure:beforedestruction',
    'procedure:assign', 'function:tostring', 'function:equals',
    'function:gethashcode');

  MAX_KOPF_ZEILEN = 60;   // Suchgrenze fuer Deklarationsende / Rumpf-'end'

type
  // Spaltentreue Code-Sicht der Unit: Kommentare und Strings geblankt.
  //
  // Perf Charge Q4 (2026-10-25): FAUL gebaut. Code hat von Anfang an
  // Roh.Count Eintraege (alle Laengen-Grenzen bleiben gleich), gefuellt
  // werden aber nur die Zeilen 1..Gebaut - CodeZeile zieht bei Bedarf nach,
  // mit denselben ScanCodeLine-Aufrufen in derselben Reihenfolge und dem
  // fortgetragenen State. Vorher wurde beim ersten Kandidaten die GANZE
  // Datei geblankt; gelesen wird hoechstens bis zur letzten Kandidaten-
  // Anweisung + MAX_KOPF_ZEILEN (Schaetzung laz: ~69 % der Zeilen der
  // Kandidaten-Dateien, jvcl ~80 %).
  TCodeSicht = record
    Roh    : TStrings;
    Code   : TArray<string>;
    Gebaut : Integer;              // Zeilen 1..Gebaut sind gefuellt
    State  : TCommentScanState;    // Kommentarzustand hinter Zeile Gebaut
  end;

function IstWortZeichen(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function InListe(const S: string; const Liste: array of string): Boolean;
var
  W : string;
begin
  for W in Liste do
    if S = W then Exit(True);
  Result := False;
end;

function SichtRang(const Abschnitt: string): Integer;
var
  L : string;
begin
  L := LowerCase(Abschnitt);
  if L = 'private' then Result := 0
  else if L = 'protected' then Result := 1
  else if L = 'public' then Result := 2
  else Result := 3;   // published (auch der implizite Anfangsabschnitt)
end;

// 'procedure'/'function'/'constructor'/'destructor' aus dem TypeRef.
function MethodenArt(const TypeRef: string): string;
var
  i : Integer;
begin
  Result := LowerCase(TypeRef);
  for i := 1 to Length(Result) do
    if not CharInSet(Result[i], ['a'..'z']) then
      Exit(Copy(Result, 1, i - 1));
end;

function HatTypeRefMarke(const TypeRef, Marke: string): Boolean;
begin
  Result := Pos(Marke, LowerCase(TypeRef)) > 0;
end;

// Parameternamen ohne Modifier ('const S' -> 'S').
function ParamNamen(M: TAstNode): TArray<string>;
var
  Kn : TAstNode;
  N    : string;
  P    : Integer;
begin
  Result := nil;
  for Kn in M.Children do
  begin
    if Kn.Kind <> nkParam then Continue;
    N := Kn.Name;
    P := LastDelimiter(' ', N);
    if P > 0 then N := Copy(N, P + 1, MaxInt);
    Result := Result + [N];
  end;
end;

function HatDefaultParam(M: TAstNode): Boolean;
var
  Kn : TAstNode;
begin
  for Kn in M.Children do
    if (Kn.Kind = nkParam) and (Pos('=', Kn.TypeRef) > 0) then
      Exit(True);
  Result := False;
end;

// Die einzige Anweisung des Rumpfs, sonst nil. Lokale Deklarationen und
// jede zweite Anweisung fuehren zu nil.
function EinzigeAnweisung(M: TAstNode): TAstNode;
var
  Kn, Block : TAstNode;
begin
  Result := nil;
  Block  := nil;
  for Kn in M.Children do
  begin
    if Kn.Kind = nkParam then Continue;
    if Assigned(Block) then Exit;     // mehr als ein Nicht-Parameter-Kind
    Block := Kn;
  end;
  if not Assigned(Block) then Exit;
  if Block.Kind <> nkBlock then Exit(Block);
  for Kn in Block.Children do
  begin
    if Assigned(Result) then Exit(nil);
    Result := Kn;
  end;
end;

// Zerlegt 'Name', 'Name(args)' oder '' (nacktes inherited). False bei
// allem anderen ('Name.Member', 'Name(a) and X', ...).
function ZerlegeAufruf(const Ausdruck: string; out Name, Args: string;
  out MitKlammer: Boolean): Boolean;
var
  S    : string;
  i, T : Integer;
begin
  S := Trim(Ausdruck);
  Name := ''; Args := ''; MitKlammer := False;
  i := 1;
  while (i <= Length(S)) and IstWortZeichen(S[i]) do Inc(i);
  Name := Copy(S, 1, i - 1);
  S := Trim(Copy(S, i, MaxInt));
  if S = '' then Exit(True);
  if (Name = '') or (S[1] <> '(') then Exit(False);
  T := 0;
  for i := 1 to Length(S) do
  begin
    if S[i] = '(' then Inc(T)
    else if S[i] = ')' then
    begin
      Dec(T);
      if (T = 0) and (i < Length(S)) then Exit(False);  // Rest hinter ')'
    end;
  end;
  if (T <> 0) or (S[Length(S)] <> ')') then Exit(False);
  Args := Copy(S, 2, Length(S) - 2);
  MitKlammer := True;
  Result := True;
end;

function ArgsGleichParams(const Args: string;
  const Params: TArray<string>): Boolean;
var
  Teile : TArray<string>;
  k     : Integer;
begin
  Teile := TDetectorUtils.SplitTopLevelArgs(Args);
  if (Length(Teile) = 1) and (Trim(Teile[0]) = '') then
    Exit(Length(Params) = 0);
  if Length(Teile) <> Length(Params) then Exit(False);
  for k := 0 to High(Teile) do
    if not SameText(Trim(Teile[k]), Params[k]) then Exit(False);
  Result := True;
end;

// Reicht die Anweisung den Aufruf 1:1 an den Vorfahren durch?
function IstDurchreichung(Anw: TAstNode; const Art, MethName: string;
  const Params: TArray<string>): Boolean;
var
  Ausdruck, Name, Args, Rhs : string;
  MitKlammer : Boolean;
begin
  Result := False;
  if Anw.Kind = nkInherited then
  begin
    // In einer Funktion verwirft der Aufruf ohne Zuweisung das Ergebnis.
    if Art = 'function' then Exit;
    Ausdruck := Anw.Name;
  end
  else if Anw.Kind = nkAssign then
  begin
    if (Art <> 'function') or not SameText(Anw.Name, 'Result') then Exit;
    Rhs := Trim(Anw.TypeRef);
    if not SameText(Copy(Rhs, 1, 9), 'inherited') then Exit;
    if (Length(Rhs) > 9) and IstWortZeichen(Rhs[10]) then Exit;
    Ausdruck := Copy(Rhs, 10, MaxInt);
  end
  else
    Exit;
  if not ZerlegeAufruf(Ausdruck, Name, Args, MitKlammer) then Exit;
  if Name = '' then Exit(True);                  // nacktes inherited
  if not SameText(Name, MethName) then Exit;     // andere Methode
  if not MitKlammer then Exit(Length(Params) = 0);
  Result := ArgsGleichParams(Args, Params);
end;

// Einzige Deklaration MethName in der Klasse (nil bei 0 oder >1) samt
// Sichtbarkeitsabschnitt.
function DeklarationIn(Klasse: TAstNode; const MethName: string;
  out Abschnitt: string): TAstNode;
var
  Sek, M : TAstNode;
begin
  Result := nil;
  Abschnitt := '';
  for Sek in Klasse.Children do
  begin
    if Sek.Kind <> nkVisibilitySection then Continue;
    for M in Sek.Children do
      if (M.Kind = nkMethod) and SameText(M.Name, MethName) then
      begin
        if Assigned(Result) then Exit(nil);
        Result := M;
        Abschnitt := Sek.Name;
      end;
  end;
end;

function ErsteBasis(Klasse: TAstNode): string;
var
  P : Integer;
begin
  Result := Trim(Klasse.TypeRef);
  P := Pos(' ', Result);
  if P > 0 then Result := Copy(Result, 1, P - 1);
  Result := TDetectorUtils.UnqualifiedNameLast(Result);
end;

function EinzigeKlasse(Klassen: TObjectDictionary<string, TList<TAstNode>>;
  const Name: string): TAstNode;
var
  L : TList<TAstNode>;
begin
  Result := nil;
  if (Name <> '') and Klassen.TryGetValue(LowerCase(Name), L) and
     (L.Count = 1) then
    Result := L[0];
end;

// Sichtbarkeitsrang der gleichnamigen Methode des naechsten Vorfahren in
// DIESER Unit, -1 wenn die Kette die Unit verlaesst oder nichts findet.
function VorfahrRang(Klassen: TObjectDictionary<string, TList<TAstNode>>;
  Klasse: TAstNode; const MethName: string): Integer;
var
  Vorfahr, Decl : TAstNode;
  Abschnitt     : string;
  Schritte      : Integer;
begin
  Result := -1;
  Vorfahr := EinzigeKlasse(Klassen, ErsteBasis(Klasse));
  Schritte := 0;
  while Assigned(Vorfahr) and (Vorfahr <> Klasse) and (Schritte < 32) do
  begin
    Decl := DeklarationIn(Vorfahr, MethName, Abschnitt);
    if Assigned(Decl) then Exit(SichtRang(Abschnitt));
    Vorfahr := EinzigeKlasse(Klassen, ErsteBasis(Vorfahr));
    Inc(Schritte);
  end;
end;

// ---- Quelltext-Pruefungen (spaltentreue Code-Sicht) -----------------------

// Einziger Lesezugang zu Sicht.Code - baut faul bis Zeile nach.
function CodeZeile(var Sicht: TCodeSicht; Zeile: Integer): string;
var
  Dummy : Integer;
begin
  if (Zeile >= 1) and (Zeile <= Length(Sicht.Code)) then
  begin
    while Sicht.Gebaut < Zeile do
    begin
      Sicht.Code[Sicht.Gebaut] := TDetectorUtils.ScanCodeLine(
        Sicht.Roh[Sicht.Gebaut], Sicht.State, Dummy, ' ', True);
      Inc(Sicht.Gebaut);
    end;
    Result := Sicht.Code[Zeile - 1];
  end
  else
    Result := '';
end;

// Steht an (Zeile, Spalte) das Methoden-Schluesselwort der Deklaration?
// Schuetzt vor Spaltenversatz (Parser liest UTF-8 ohne BOM als ANSI).
function KopfwortPasst(var Sicht: TCodeSicht; Zeile, Spalte: Integer;
  const Art: string): Boolean;
begin
  Result := (Art <> '') and
    SameText(Copy(CodeZeile(Sicht, Zeile), Spalte, Length(Art)), Art);
end;

// Steht vor der Deklaration (ggf. vor 'class') ein Attribut ']'?
function HatAttribut(var Sicht: TCodeSicht; Zeile, Spalte: Integer): Boolean;
var
  S       : string;
  i, Ende : Integer;
  Wort    : string;
begin
  i := Spalte - 1;
  S := CodeZeile(Sicht, Zeile);
  while Zeile >= 1 do
  begin
    while (i >= 1) and (S[i] <= ' ') do Dec(i);
    if i >= 1 then
    begin
      if S[i] = ']' then Exit(True);
      if not IstWortZeichen(S[i]) then Exit(False);
      Ende := i;
      while (i >= 1) and IstWortZeichen(S[i]) do Dec(i);
      Wort := LowerCase(Copy(S, i + 1, Ende - i));
      if Wort <> 'class' then Exit(False);
      Continue;
    end;
    Dec(Zeile);
    S := CodeZeile(Sicht, Zeile);
    i := Length(S);
  end;
  Result := False;
end;

// Code ab (Zeile, Spalte) ueber hoechstens MAX_KOPF_ZEILEN Zeilen, mit #10
// getrennt. ZeileVon[k] = Quellzeile des Zeichens k (1-basiert).
function CodeAb(var Sicht: TCodeSicht; Zeile, Spalte: Integer;
  out ZeileVon: TArray<Integer>): string;
var
  z, k, Bis : Integer;
  Teil      : string;
  Teile     : TArray<string>;
  Gesamt, P : Integer;
begin
  Bis := Zeile + MAX_KOPF_ZEILEN;
  if Bis > Length(Sicht.Code) then Bis := Length(Sicht.Code);
  Teile := nil;
  Gesamt := 0;
  for z := Zeile to Bis do
  begin
    if z = Zeile then Teil := Copy(CodeZeile(Sicht, z), Spalte, MaxInt)
    else Teil := CodeZeile(Sicht, z);
    Teile := Teile + [Teil + #10];
    Inc(Gesamt, Length(Teil) + 1);
  end;
  Result := string.Join('', Teile);
  SetLength(ZeileVon, Gesamt);
  P := 0;
  for z := 0 to High(Teile) do
    for k := 1 to Length(Teile[z]) do
    begin
      ZeileVon[P] := Zeile + z;
      Inc(P);
    end;
end;

// Prueft die Direktiven hinter der Deklaration: nur 'override' erlaubt.
// DeklEnde = Zeile des letzten Direktiven-';'. False, wenn eine andere
// Direktive folgt oder das Ende nicht gefunden wird.
function NurOverride(var Sicht: TCodeSicht; Zeile, Spalte: Integer;
  out DeklEnde: Integer): Boolean;
var
  S         : string;
  ZeileVon  : TArray<Integer>;
  i, Tiefe  : Integer;
  Start     : Integer;
  Folge     : Integer;
  Wort      : string;
  Override_ : Boolean;
begin
  Result := False;
  DeklEnde := Zeile;
  S := CodeAb(Sicht, Zeile, Spalte, ZeileVon);
  // Signatur bis zum ersten ';' auf Klammertiefe 0
  Tiefe := 0;
  i := 1;
  while i <= Length(S) do
  begin
    case S[i] of
      '(': Inc(Tiefe);
      ')': Dec(Tiefe);
      ';': if Tiefe = 0 then Break;
    end;
    Inc(i);
  end;
  if i > Length(S) then Exit;
  DeklEnde := ZeileVon[i - 1];
  Override_ := False;
  Inc(i);
  while True do
  begin
    while (i <= Length(S)) and (S[i] <= ' ') do Inc(i);
    Start := i;
    while (i <= Length(S)) and IstWortZeichen(S[i]) do Inc(i);
    Wort := LowerCase(Copy(S, Start, i - Start));
    Folge := i;
    while (Folge <= Length(S)) and (S[Folge] <= ' ') do Inc(Folge);
    // Feld, das wie eine Direktive heisst ('Message: string;')
    if (Folge <= Length(S)) and CharInSet(S[Folge], [':', ',']) then
      Exit(Override_);
    if (Wort <> 'override') and not InListe(Wort, DIREKTIV_WOERTER) then
      Exit(Override_);                       // naechstes Member: fertig
    if Wort <> 'override' then Exit(False);  // fremde Direktive
    Override_ := True;
    while (i <= Length(S)) and (S[i] <> ';') do Inc(i);
    if i > Length(S) then Exit(False);
    DeklEnde := ZeileVon[i - 1];
    Inc(i);
  end;
end;

// Zeile des 'end' nach der einzigen Anweisung (0 = nicht gefunden).
function RumpfEnde(var Sicht: TCodeSicht; AbZeile: Integer): Integer;
var
  z, P : Integer;
  S    : string;
begin
  for z := AbZeile to AbZeile + MAX_KOPF_ZEILEN do
  begin
    if z > Length(Sicht.Code) then Break;
    S := LowerCase(CodeZeile(Sicht, z));
    P := Pos('end', S);
    while P > 0 do
    begin
      if ((P = 1) or not IstWortZeichen(S[P - 1])) and
         ((P + 3 > Length(S)) or not IstWortZeichen(S[P + 3])) then
        Exit(z);
      P := PosEx('end', S, P + 1);
    end;
  end;
  Result := 0;
end;

// Steht in den Rohzeilen Von..Bis eine Compilerdirektive?
function HatDirektive(const Sicht: TCodeSicht; Von, Bis: Integer): Boolean;
var
  z : Integer;
  S : string;
begin
  for z := Von to Bis do
  begin
    if (z < 1) or (z > Sicht.Roh.Count) then Continue;
    S := Sicht.Roh[z - 1];
    if (Pos('{$', S) > 0) or (Pos('(*$', S) > 0) then Exit(True);
  end;
  Result := False;
end;

// Legt die Sicht an; gefuellt wird sie erst ueber CodeZeile.
procedure BaueCodeSicht(var Sicht: TCodeSicht);
begin
  Sicht.State  := Default(TCommentScanState);
  Sicht.Gebaut := 0;
  SetLength(Sicht.Code, Sicht.Roh.Count);
end;

function KlassenIndex(UnitNode: TAstNode)
  : TObjectDictionary<string, TList<TAstNode>>;
var
  Alle : TList<TAstNode>;
  K    : TAstNode;
  L    : TList<TAstNode>;
begin
  Result := TObjectDictionary<string, TList<TAstNode>>.Create([doOwnsValues]);
  Alle := UnitNode.FindAll(nkClass);
  try
    for K in Alle do
    begin
      if not Result.TryGetValue(LowerCase(K.Name), L) then
      begin
        L := TList<TAstNode>.Create;
        Result.Add(LowerCase(K.Name), L);
      end;
      L.Add(K);
    end;
  finally
    Alle.Free;
  end;
end;

class procedure TInheritedMethodEmptyDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methoden  : TList<TAstNode>;
  M, Anw    : TAstNode;
  Klasse    : TAstNode;
  Decl      : TAstNode;
  Klassen   : TObjectDictionary<string, TList<TAstNode>>;
  Sicht     : TCodeSicht;
  Lines     : TStringList;
  Cached    : Boolean;
  Teile     : TArray<string>;
  MethName  : string;
  Art       : string;
  Abschnitt : string;
  Params    : TArray<string>;
  DeklEnde  : Integer;
  EndZeile  : Integer;
  Rang      : Integer;
  Konf      : TFindingConfidence;
  F         : TLeakFinding;
begin
  Klassen := nil;
  Lines   := nil;
  Cached  := False;
  Sicht   := Default(TCodeSicht);
  Methoden := UnitNode.FindAll(nkMethod);
  try
    for M in Methoden do
    begin
      // ---- AST: Implementierung mit genau einer Anweisung ----------------
      // Perf Charge Q4: die allokierenden Pruefungen (Split, LowerCase im
      // TypeRef) laufen erst NACH den reinen AST-Pruefungen - vorher
      // zahlte jede Methode der Unit (auch jede Deklaration in der Klasse)
      // beide. Alle Pruefungen sind seiteneffektfreie Filter, die
      // Reihenfolge aendert die Treffermenge nicht. Ohne '.' liefert
      // Split hoechstens einen Teil - dieselbe Ablehnung wie unten.
      if Pos('.', M.Name) = 0 then Continue;       // keine Methode
      Anw := EinzigeAnweisung(M);
      if not Assigned(Anw) then Continue;
      if not (Anw.Kind in [nkInherited, nkAssign]) then Continue;
      Teile := M.Name.Split(['.']);
      if Length(Teile) < 2 then Continue;          // keine Methode
      if HatTypeRefMarke(M.TypeRef, ';class') then Continue;
      MethName := Teile[High(Teile)];

      // ---- Deklaration in der Klasse -------------------------------------
      if not Assigned(Klassen) then Klassen := KlassenIndex(UnitNode);
      Klasse := EinzigeKlasse(Klassen, Teile[High(Teile) - 1]);
      if not Assigned(Klasse) then Continue;
      Decl := DeklarationIn(Klasse, MethName, Abschnitt);
      if not Assigned(Decl) then Continue;
      if not HatTypeRefMarke(Decl.TypeRef, ';override') then Continue;
      if HatTypeRefMarke(Decl.TypeRef, ';class') then Continue;
      if HatDefaultParam(Decl) or HatDefaultParam(M) then Continue;
      Art := MethodenArt(Decl.TypeRef);

      Params := ParamNamen(M);
      if Length(Params) = 0 then
        Params := ParamNamen(Decl)              // Kopf ohne Parameterliste
      else if Length(Params) <> Length(ParamNamen(Decl)) then
        Continue;
      if not IstDurchreichung(Anw, Art, MethName, Params) then Continue;

      // ---- Quelltext: Attribute, Direktiven ------------------------------
      if not Assigned(Lines) then
      begin
        Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
        if Lines = nil then Exit;               // ohne Quelltext kein Fund
        Sicht.Roh := Lines;
        BaueCodeSicht(Sicht);
      end;
      if not KopfwortPasst(Sicht, Decl.Line, Decl.Col, Art) then Continue;
      if HatAttribut(Sicht, Decl.Line, Decl.Col) then Continue;
      if not NurOverride(Sicht, Decl.Line, Decl.Col, DeklEnde) then Continue;
      if HatDirektive(Sicht, Decl.Line, DeklEnde) then Continue;
      EndZeile := RumpfEnde(Sicht, Anw.Line);
      if EndZeile = 0 then Continue;
      if HatDirektive(Sicht, M.Line, EndZeile) then Continue;

      // ---- Sichtbarkeit --------------------------------------------------
      Rang := VorfahrRang(Klassen, Klasse, MethName);
      if Rang >= 0 then
      begin
        if SichtRang(Abschnitt) > Rang then Continue;   // hebt Sichtbarkeit an
        Konf := fcHigh;
      end
      else if SichtRang(Abschnitt) <= 1 then
        Konf := fcHigh
      else if (SichtRang(Abschnitt) = 2) and
              InListe(Art + ':' + LowerCase(MethName), BEKANNT_PUBLIC) then
        Konf := fcHigh
      else
        Konf := fcLow;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      if Konf = fcHigh then
        F.MissingVar := Format(
          'Override %s contains only "inherited" - remove the override entirely',
          [MethName])
      else
        F.MissingVar := Format(
          'Override %s contains only "inherited" - remove it unless it widens ' +
          'the visibility of the ancestor method (ancestor not in this unit)',
          [MethName]);
      F.SetKind(fkInheritedMethodEmpty, Konf);
      Results.Add(F);
    end;
  finally
    Methoden.Free;
    Klassen.Free;
    if Assigned(Lines) then ReleaseLines(Lines, Cached);
  end;
end;

end.
