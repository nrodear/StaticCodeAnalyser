unit uRdxTypeProof;

// reDelphix - der Typbeweis auf dem Text der Datei: was die Unit selbst
// ueber einen Typ- oder Feldnamen sagt, ohne Parser und ohne
// Quellstellen-Dienst. Bis zur Folgewelle A4 des Wochen-Reviews (G07-04,
// G07-20) stand er in uRdxSimpleFixes, verteilt auf zwei Planer-Klassen,
// die sich dafuer gegenseitig riefen (TRdxSimpleFixes.DeclaredTypeKind/
// DeclaresValueType/FieldTypeOf, TRdxExprFixes.ResolvedTypeKind/
// ProceduralType/PointerLikeType); uRdxFixRunner band die Planer-Unit an
// sieben Stellen nur fuer diese Fragen ein. Der Inhalt ist unveraendert
// umgezogen (Regeln, Listen, Reihenfolge der Pruefungen) - bis auf den
// Namen DeclaresNonClassType (bis A4 DeclaresValueType, G07-20); die
// Feldsuche ruft MatchClose direkt (dieselbe Grenze wie MatchForward in
// uRdxSimpleFixes), und der Halt der Alias-Aufloesung traegt eine Kopie
// der Schluesselwortliste (s. IsKeyword).
//
// VERTRAG:
//   * Eingabe ist die Code-Sicht der Datei (TRdxCodeMap); Kommentare und
//     Strings zaehlen nie. Typnamen gehen klein oder in beliebiger
//     Schreibweise hinein (je Funktion angegeben), heraus kommt klein.
//   * Bewiesen wird NUR, was diese Datei deklariert - plus, als zweiter
//     Beweisweg fuer PointerLikeType, die Klassen und Interfaces der
//     Delphi-Quellen (uRdxRtlTypes, Entscheid E27). Ein Typ einer anderen
//     Unit ist sonst unbekannt: '' bzw. False, nie geraten.
//   * Die Antworten sind "lieber keine Hilfe als eine falsche" gerichtet:
//     wer True/'' falsch deutet, bekommt eine Sperre, keine falsche Hilfe -
//     die Richtung steht je Funktion.
//   * Kein Zustand, keine Zuweisung an die Code-Sicht; jede Frage liest
//     die Datei neu (die Vorfilter aus uRdxCodeMap halten das billig).
//
// Wer fragt: die Planer in uRdxSimpleFixes (SCA066 DeclaresProperty,
// SCA126 TRdxNilFix ueber NamesProcType/FieldTypeOf/ProceduralType/
// PointerLikeType) und der Laeufer uRdxFixRunner (SCA085/SCA139
// DeclaresNonClassType/DeclaresProperty/DeclaresRoutine/DeclaredTypeKind/
// ResolvedTypeKind, SCA066 ProceduralType, SCA084 DeclaresRoutine/
// ProceduralType/PointerLikeType, SCA074 DeclaresRoutine, SCA047
// DeclaresProperty).
//
// NICHT hier: die Bindungsfragen einer Routine (TRdxSimpleFixes.WithBefore,
// DeclaresInlineVar - ob ein Name an ein with-Member oder eine Inline-
// Variable bindet, keine Typfrage; sie teilen RoutineStartLine mit dem
// SCA066-Planer) und die Typen, die der Quellstellen-Dienst beweist
// (TSourcePlaces.DeclaredTypeOf, nur im Laeufer).
//
// FPC-tauglich wie uRdxSimpleFixes, das sie bindet: nur uRdxCodeMap und
// uRdxRtlTypes, keine Generics, keine Helper - die Unit laeuft im
// FPC-Pruefstand mit.

interface

uses
  uRdxCodeMap;   // TRdxCodeMap

type
  // Der Typbeweis: Fragen an die ganze Datei, ohne Zustand.
  TRdxTypeProof = class
  public
    // Das erste Wort hinter 'ATypeName =' in der Datei ('record', 'class',
    // 'procedure', 'reference' ...; 'packed' uebersprungen), klein; '' wenn
    // die Datei den Typ nicht deklariert. 'X: ATypeName = nil' (Variable
    // oder Parameter mit Anfangswert) ist keine Deklaration (Charge R10),
    // ein Yoda-Vergleich 'if TBitmap = Sender.ClassType' auch nicht (Review
    // Woche G07-21: eine Deklaration nur hinter ';', 'type', einem Attribut
    // oder FPC-'generic'). ATypeName in beliebiger Schreibweise.
    class function DeclaredTypeKind(AMap: TRdxCodeMap;
      const ATypeName: string): string; static;

    // Art des Typs ATypeLow nach seiner Deklaration in der Datei
    // (DeclaredTypeKind), Aliasse bis drei Stufen aufgeloest ('TLookup =
    // TObjFunc' -> 'function'); bei einem Typ aus einer anderen Unit der
    // letzte Name der Kette, '' wenn die Datei ihn nicht deklariert.
    class function ResolvedTypeKind(AMap: TRdxCodeMap;
      const ATypeLow: string): string; static;

    // Nennt ATypeLow nach seinem NAMEN einen Prozedurtyp? Genau 'procedure',
    // 'function', 'reference', TMethod, TThreadMethod, TPredicate,
    // TThreadProcedure, Func, Proc oder eine Endung event/proc/func/
    // callback/procedure/function (TNotifyEvent, Spring4D Func<T>) - nicht
    // die Synchronisationsklassen TEvent & Co. (System.SyncObjs). Ohne Blick
    // in die Datei; geteilt von SCA066, SCA084 und SCA126.
    class function NamesProcType(const ATypeLow: string): Boolean; static;

    // Ein Prozedurtyp (procedure/function/reference to, auch ueber Alias),
    // oder ein Name wie TNotifyEvent, TProc, Func (NamesProcType)? Typen
    // aus anderen Units mit unauffaelligem Namen sieht das nicht (False).
    class function ProceduralType(AMap: TRdxCodeMap;
      const ATypeLow: string): Boolean; static;

    // Als Klasse, Interface oder Zeiger BEWIESEN: TObject, Pointer,
    // IInterface/IUnknown, in dieser Unit so deklariert (auch ueber Alias)
    // oder - zweiter Beweisweg, Entscheid E27 (Nico 2026-10-14) - eine
    // Klasse oder ein Interface der Delphi-Quellen (uRdxRtlTypes, Liste
    // aus RTL/VCL/FMX/Data/...). Eine Zulassungsliste - Kundentypen
    // anderer Units fallen heraus (False).
    class function PointerLikeType(AMap: TRdxCodeMap;
      const ATypeLow: string): Boolean; static;

    // True, wenn die Datei ATypeName als etwas ANDERES als eine Klasse
    // deklariert, auf der FreeAndNil uebersetzt und das Richtige tut:
    // record, object, interface, dispinterface, Zeiger ('PFoo = ^TFoo') oder
    // eigenen Typ ('PFoo = type ^TFoo' - was hinter 'type' steht, liest
    // DeclaredTypeKind nicht; meist ein Zeiger oder Werttyp, eine Klasse
    // dort ist selten und zaehlt vorsichtig mit), auch ueber ihre Aliasse
    // ('TA = TB', ResolvedTypeKind; Nachpruefung FB). 'X.Free' ist dann eine
    // eigene Methode (Record, object - auch ueber den Zeiger, den Delphi
    // dereferenziert) bzw. ein Interface-Aufruf, FreeAndNil(X) waere falsch
    // (Review FB, R2-01/R3-01: mORMot 'PX509_CRL = ^X509_CRL', ein object
    // mit eigenem Free - FPC rief TObject.Free auf der OpenSSL-Struktur,
    // Zugriffsverletzung). Bis zur Folgewelle A4 hiess die Funktion
    // DeclaresValueType - der Vertrag war weiter als der Name (G07-20).
    // Ein Typ aus einer anderen Unit (auch ein Alias oder ein generischer
    // Record 'TRec<T>') ist hier unbekannt (False) - in Delphi ab 10.4
    // faellt ein Record dort als Fehler E2010 auf (FreeAndNil nimmt const
    // [ref] TObject); einen fremden Zeiger mit Konventionsnamen
    // ('PEVP_PKEY') sperrt der Laeufer selbst. ATypeName in beliebiger
    // Schreibweise.
    class function DeclaresNonClassType(AMap: TRdxCodeMap;
      const ATypeName: string): Boolean; static;

    // Typ des Feldes AName, wenn die Datei es als Feld eines Klassen-,
    // Record- oder Objektrumpfs deklariert ('FOwner: TObject;' auf
    // Klammertiefe 0 - nicht Parameter, lokale Variable, Property, Methode
    // oder Konstante): der Typname klein ('tobject'; 'System.TObject' ->
    // 'tobject', 'TList<T>' -> 'tlist', ein Typ in einer generischen Klasse
    // nach seinem eigenen Namen: 'TList<Integer>.TEnumerator' ->
    // 'tenumerator'), '^' fuer einen Zeigertyp, bei
    // procedure/function/reference/array/set/string das Wort selbst. ''
    // ohne Feld oder bei Feldern dieses Namens mit VERSCHIEDENEN Typen
    // (mehrdeutig). Ein gleichnamiges Feld einer ANDEREN Klasse derselben
    // Unit zaehlt mit - ohne Parser ist der Typ des Pfads davor unbekannt,
    // der Name ist der Beweis (SCA126, Pfad-Operanden: dort ist nur die
    // Frage Feld oder Methode). AName in beliebiger Schreibweise.
    class function FieldTypeOf(AMap: TRdxCodeMap;
      const AName: string): string; static;

    // True, wenn AName irgendwo in der Datei als Property deklariert ist
    // ('property AName'). SCA085 (uRdxFixRunner): FreeAndNil braucht eine
    // Variable, eine Property uebersetzt als Argument nicht; seit Charge FC
    // auch SCA066 (uRdxSimpleFixes.EmptyArgsContext): ob Delphi eine
    // Property mit Prozedurtyp ohne () aufruft, ist nicht belegt; SCA047
    // (uRdxFixRunner.SelfAssignReason): die Zuweisung ruft vielleicht einen
    // Setter.
    class function DeclaresProperty(AMap: TRdxCodeMap;
      const AName: string): Boolean; static;

    // True, wenn die Datei eine Routine AName deklariert ('procedure
    // Assert' / 'function Assert', auch als Methode) - dann bindet der
    // Name nicht an die RTL (SCA074 Assert, SCA084 Assigned, SCA085/SCA139
    // Free). Ruft uRdxCodeMap.DeclaresRoutine (dort seit Charge B2S-a,
    // Review R3-07); der Einstieg der Klasse bleibt fuer den Laeufer und
    // die Tests.
    class function DeclaresRoutine(AMap: TRdxCodeMap;
      const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,   // LowerCase
  System.StrUtils,   // EndsText
  uRdxRtlTypes;      // IsRtlClassOrInterface (zweiter Beweisweg, E27)

const
  // Davor beginnt die Deklaration eines Typs 'TName = ..' (DeclaredTypeKind).
  TYPE_DECL_PREV: array[0..3] of string = (';', 'type', ']', 'generic');
  // Prozedurtypen nach Name: genau diese bzw. diese Endungen (TNotifyEvent,
  // TProc, TFunc, Spring4D Func<T> ...). NICHT 'handler' oder 'method':
  // TIdIOHandler, TRttiMethod sind Klassen. 'tmethod' ist der Record hinter
  // 'of object'. Geteilt von SCA066, SCA084 und SCA126.
  PROC_TYPE_NAMES: array[0..8] of string = ('procedure', 'function',
    'reference', 'tmethod', 'tthreadmethod', 'tpredicate', 'tthreadprocedure',
    'func', 'proc');
  PROC_TYPE_SUFFIXES: array[0..5] of string = ('event', 'proc', 'func',
    'callback', 'procedure', 'function');
  // Klassen der RTL, deren Name auf eine Endung oben passt (System.SyncObjs:
  // Synchronisationsobjekte, keine Ereignisse) - ohne die Ausnahme hiesse
  // 'X = nil' bei einem TEvent "Prozedurtyp", ein falscher Grund (Review
  // Quick-Fix-Units 2026-10-14).
  NOT_PROC_TYPES: array[0..3] of string = ('tevent', 'tsimpleevent',
    'tlightweightevent', 'tcountdownevent');
  // Arten, bei denen die Alias-Aufloesung stehen bleibt.
  TYPE_KIND_WORDS: array[0..9] of string = ('class', 'record', 'object',
    'interface', 'dispinterface', 'reference', 'set', 'array', 'string',
    'file');
  // Sicher nil-vergleichbar und nicht prozedural (SCA084).
  POINTER_TYPES: array[0..3] of string = ('tobject', 'pointer', 'iinterface',
    'iunknown');
  // Wie weit die Vorfahrenliste eines Typrumpfs ('class(TBase, IFoo)')
  // reichen darf (OpensTypeBody) - dieselbe Grenze wie MAX_REGION_LINES in
  // uRdxSimpleFixes, ueber deren MatchForward die Feldsuche bis zur
  // Folgewelle A4 lief.
  MAX_ANCESTOR_LINES = 25;

// Reservierte Woerter, die kein Typname sind - hier nur der Halt der
// Alias-Aufloesung (ResolvedTypeKind). DIESELBE Liste wie
// uRdxSimpleFixes.IsKeyword (dort: Woerter, die keinen Operanden beginnen);
// bis zur Folgewelle A4 teilten beide eine Funktion. Der Platz fuer die
// eine Liste ist uRdxCodeMap (Folgewunsch) - bis dahin beide gleich halten.
// Fuer uebersetzbaren Code aendert der Halt kein Ergebnis (ein reserviertes
// Wort wird nie als 'K =' deklariert), er spart die Suche.
function IsKeyword(const ALow: string): Boolean;
const
  KEYWORDS: array[0..37] of string = (
    'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as',
    'if', 'then', 'else', 'while', 'do', 'for', 'to', 'downto', 'repeat',
    'until', 'case', 'of', 'begin', 'end', 'with', 'try', 'except',
    'finally', 'raise', 'nil', 'var', 'const', 'procedure', 'function',
    'inherited', 'out', 'type');
var
  K : string;
begin
  for K in KEYWORDS do
    if ALow = K then Exit(True);
  Result := False;
end;

{ ---- Deklarationen der Datei ---- }

class function TRdxTypeProof.DeclaresProperty(AMap: TRdxCodeMap;
  const AName: string): Boolean;
begin
  Result := DeclaresAfter(AMap, ['property'], AName);
end;

// Die Regel steht seit Charge B2S-a in uRdxCodeMap (Review R3-07); der
// Einstieg der Klasse bleibt fuer uRdxFixRunner und die Tests.
class function TRdxTypeProof.DeclaresRoutine(AMap: TRdxCodeMap;
  const AName: string): Boolean;
begin
  Result := uRdxCodeMap.DeclaresRoutine(AMap, AName);
end;

{ ---- Typen der Datei ---- }

// Das Token hinter dem Typnamen ATok, generische Parameter uebersprungen
// ('TFactory<T> = ...' -> '=').
function AfterTypeParams(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
var
  Depth : Integer;
begin
  Result := After(AMap, ATok);
  if Result.Low <> '<' then Exit;
  Depth := 0;
  repeat
    if Result.Low = '<' then
      Inc(Depth)
    else if Result.Low = '>' then
      Dec(Depth);
    Result := After(AMap, Result);
  until (Depth = 0) or (Result.Low = '') or (Result.Low = ';');
end;

class function TRdxTypeProof.DeclaredTypeKind(AMap: TRdxCodeMap;
  const ATypeName: string): string;
var
  T, K    : TRdxToken;
  TypeLow : string;
begin
  Result := '';
  TypeLow := LowerCase(ATypeName);
  if TypeLow = '' then Exit;
  // Nur die Token der Zeilen, die den Namen nennen (Review R3-03, Charge
  // FC) - in der Reihenfolge der Datei, also derselbe erste Treffer wie im
  // Lauf ueber jedes Token.
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), TypeLow);
  while T.Low <> '' do
  begin
    // ':' oder '.' davor: 'var X: TBitmap = nil;', ein Default-Parameter
    // 'Exclude: TControl = nil' oder 'C: Vcl.Graphics.TBitmap = nil' - das
    // ist der Typ einer Variablen mit Anfangswert, keine Deklaration des
    // Typs. Bis Charge R10 kam hier 'nil' heraus, und eine RTL-Klasse wie
    // TBitmap galt in der ganzen Unit als unbewiesen (Messung R10: 431
    // SCA126-Angebote mehr, die die Liste aus E27 sonst nicht erreicht).
    // Seit der Review Woche G07-21 eine Positivliste (TYPE_DECL_PREV): ein
    // Typ wird nur hinter ';', 'type', einem Attribut (']') bzw. FPC-
    // 'generic' deklariert - die Negativliste ':'/'.' las einen Yoda-
    // Vergleich 'if TBitmap = Sender.ClassType' als Deklaration ('sender'),
    // und die RTL-Liste (E27) wurde dann mit 'sender' gefragt.
    if (T.Low = TypeLow) and (AfterTypeParams(AMap, T).Low = '=')
       and InList(Before(AMap, T).Low, TYPE_DECL_PREV) then
    begin
      K := After(AMap, AfterTypeParams(AMap, T));
      if K.Low = 'packed' then
        K := After(AMap, K);
      Exit(K.Low);
    end;
    T := NextTokenOnLineWith(AMap, T, TypeLow);
  end;
end;

class function TRdxTypeProof.ResolvedTypeKind(AMap: TRdxCodeMap;
  const ATypeLow: string): string;
const
  MAX_ALIAS = 3;
var
  i    : Integer;
  Next : string;
begin
  Result := DeclaredTypeKind(AMap, ATypeLow);
  for i := 1 to MAX_ALIAS do
  begin
    if (Result = '') or not IsIdentStart(Result[1]) or IsKeyword(Result)
       or InList(Result, TYPE_KIND_WORDS) then
      Exit;
    Next := DeclaredTypeKind(AMap, Result);
    if Next = '' then
      Exit;   // Alias auf einen Typ einer anderen Unit: dessen Name
    Result := Next;
  end;
end;

class function TRdxTypeProof.DeclaresNonClassType(AMap: TRdxCodeMap;
  const ATypeName: string): Boolean;
var
  Kind : string;
begin
  // Durch die Aliasse der Unit ('TA = TB; TB = record', Nachpruefung FB).
  Kind := ResolvedTypeKind(AMap, LowerCase(ATypeName));
  // '^': 'PFoo = ^TFoo' (Review FB, R2-01) - FreeAndNil(P) nimmt den Zeiger
  // als TObject, 'P.Free' meint das Ziel. 'type': ein eigener Typ ('PFoo =
  // type ^TFoo', Nachpruefung FB) - was hinter 'type' steht, liest
  // DeclaredTypeKind nicht; meist ein Zeiger oder Werttyp, eine Klasse dort
  // ist selten und bleibt vorsichtig mitgezaehlt.
  Result := (Kind = 'record') or (Kind = 'object') or (Kind = 'interface')
    or (Kind = 'dispinterface') or (Kind = '^') or (Kind = 'type');
end;

{ ---- Prozedur- und Zeigertypen ---- }

class function TRdxTypeProof.NamesProcType(const ATypeLow: string): Boolean;
var
  T : string;
begin
  if InList(ATypeLow, NOT_PROC_TYPES) then Exit(False);
  Result := InList(ATypeLow, PROC_TYPE_NAMES);
  if not Result then
    for T in PROC_TYPE_SUFFIXES do
      if (Length(ATypeLow) > Length(T)) and EndsText(T, ATypeLow) then
        Exit(True);
end;

class function TRdxTypeProof.ProceduralType(AMap: TRdxCodeMap;
  const ATypeLow: string): Boolean;
var
  Kind : string;
begin
  Kind := ResolvedTypeKind(AMap, ATypeLow);
  Result := NamesProcType(ATypeLow) or NamesProcType(Kind);
end;

class function TRdxTypeProof.PointerLikeType(AMap: TRdxCodeMap;
  const ATypeLow: string): Boolean;
var
  Kind : string;
begin
  // '^' allein: ein Feld mit anonymem Zeigertyp ('FX: ^Integer'), so
  // liefert es FieldTypeOf (SCA126, Charge R8).
  Kind := ResolvedTypeKind(AMap, ATypeLow);
  Result := (ATypeLow = '^') or InList(ATypeLow, POINTER_TYPES)
    or InList(Kind, POINTER_TYPES)
    or InList(Kind, ['class', 'interface', 'dispinterface', '^']);
  if Result then Exit;
  // Zweiter Beweisweg, Entscheid E27 (Nico 2026-10-14): NACH dem Beweis
  // dieser Unit - eine Klasse oder ein Interface der Delphi-Quellen gilt
  // als bewiesen (uRdxRtlTypes, erzeugt aus Delphi 12 und 13). Das holt
  // 'FList: TStringList', 'Form: TForm' zurueck, die seit Charge R8 ohne
  // Hilfe blieben (im Korpus 58,8 % der SCA126-Angebote, Messung R9);
  // Kundentypen bleiben R_NOT_PROVEN. Gefragt wird der Name, den diese
  // Unit NICHT selbst deklariert: ATypeLow, wenn die Unit ihn nicht kennt
  // (Kind = ''), sonst das Ende der Alias-Kette ('TMyList = TStringList'
  // -> 'tstringlist'). Deklariert die Unit den Namen als etwas anderes
  // ('record', 'procedure', ein Aufzaehlungstyp), ist Kind ein Typwort
  // oder kein Bezeichner - fuer die steht nichts in der Liste, die Unit
  // behaelt das letzte Wort. Einen Kunden-Prozedurtyp mit RTL-Namen in
  // derselben Unit faengt ProceduralType vorher ab (beide Aufrufer).
  if Kind = '' then
    Kind := ATypeLow;
  Result := IsRtlClassOrInterface(Kind);
end;

{ ---- Felder der Datei (FieldTypeOf) ---- }

type
  // Zustand der Feldsuche: offene Typruempfe, Klammern darin, der Typ des
  // ersten Treffers und ob ein zweiter davon abweicht.
  TFieldScan = record
    Body  : Integer;
    Paren : Integer;
    Found : string;
    Multi : Boolean;
  end;

const
  // Vor dem Namen eines Feldes auf Klammertiefe 0 eines Typrumpfs: ';',
  // ',' (Feldgruppe 'FA, FB: T'), ein Sichtbarkeitswort, 'var' (class var,
  // var-Abschnitt der Klasse), das Rumpfwort selbst (erstes Feld), ')'
  // hinter den Vorfahren, ']' hinter einem Attribut. NICHT function/
  // procedure/property/const - deren Name traegt ebenfalls einen ':'.
  FIELD_PREV: array[0..12] of string = (';', ',', 'private', 'protected',
    'public', 'published', 'automated', 'var', 'class', 'record', 'object',
    ')', ']');
  TYPE_BODY_WORDS: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');

// Oeffnet T einen Typrumpf mit eigenem 'end'? 'record' immer - ausser als
// generische Einschraenkung ('<T: record>': dahinter '>', ',', ';' oder
// ')'); class/object/interface/dispinterface nur hinter '=' oder 'packed'
// und nicht als Vorwaertsdeklaration ('class;'), Metaklasse ('class of')
// oder Kurzform ('class(TBar);'). Das 'interface' der Unit steht nie
// hinter '='.
function OpensTypeBody(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  if InList(APrev.Low, IDENT_PREFIXES) then Exit(False);
  if T.Low = 'record' then
    Exit(not InList(After(AMap, T).Low, ['>', ',', ';', ')']));
  if not InList(T.Low, TYPE_BODY_WORDS)
     or not InList(APrev.Low, ['=', 'packed']) then
    Exit(False);
  N := After(AMap, T);
  while InList(N.Low, ['abstract', 'sealed']) do
    N := After(AMap, N);
  if N.Low = '(' then
  begin
    N := MatchClose(AMap, N, MAX_ANCESTOR_LINES);
    if N.Low = '' then Exit(False);
    N := After(AMap, N);
  end;
  Result := not InList(N.Low, [';', 'of']);
end;

// Das ':' hinter dem Feldnamen AName - auch hinter den Nachbarn einer
// Feldgruppe ('FA, FB: T' fuer FA); Low = '' ohne ':'.
function GroupColon(AMap: TRdxCodeMap; const AName: TRdxToken): TRdxToken;
begin
  Result := After(AMap, AName);
  while (Result.Low = ',') and After(AMap, Result).IsWord do
    Result := After(AMap, After(AMap, Result));
  if Result.Low <> ':' then
    Result := Default(TRdxToken);
end;

// Der Typ hinter dem ':' AColon als Wort fuer die Typpruefungen (s.
// FieldTypeOf): qualifiziert das letzte Glied, generisch der Name vor '<'.
// Ein Typ IN einer generischen Klasse ('TList<Integer>.TEmptyFunc') ist
// das Glied hinter den Typargumenten - bis Charge FC kam hier der aeussere
// Name heraus ('tlist'), und die Namensregel (NilOperandRisk) sah
// 'temptyfunc' nie (Review R6-13, verpasst). Ein zweiter Treffer mit
// anderem Typ macht das Ergebnis mehrdeutig.
procedure TakeFieldType(AMap: TRdxCodeMap; const AColon: TRdxToken;
  var AScan: TFieldScan);
var
  K, N : TRdxToken;
begin
  K := After(AMap, AColon);
  while K.Low <> '' do
  begin
    N := After(AMap, K);
    if N.Low = '<' then
      N := AfterClose(AMap, N);   // hinter den Typargumenten
    if N.Low <> '.' then
      Break;
    K := After(AMap, N);
  end;
  if K.Low = '' then Exit;
  if AScan.Found = '' then
    AScan.Found := K.Low
  else if AScan.Found <> K.Low then
    AScan.Multi := True;
end;

// Ein Token der Feldsuche: Ruempfe und Klammern zaehlen; auf Klammertiefe 0
// eines Rumpfs ist ein Wort ANameLow mit ':' dahinter (GroupColon) und
// FIELD_PREV davor ein Feld. Ein 'begin' oder 'implementation' in einem
// Rumpf gibt es nicht - dort ist die Bilanz verloren (etwa durch ein
// ungezaehltes end), und die Suche faengt ausserhalb neu an, statt lokale
// Variablen als Felder zu lesen.
procedure FieldScanStep(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const ANameLow: string; var AScan: TFieldScan);
var
  IsWord : Boolean;   // nicht 'Word': verdeckte System.Word (Gegen-Review R8)
  Colon  : TRdxToken;
begin
  IsWord := not InList(APrev.Low, IDENT_PREFIXES);
  if OpensTypeBody(AMap, T, APrev) then
    Inc(AScan.Body)
  else if IsWord and ((T.Low = 'begin') or (T.Low = 'implementation')) then
    AScan.Body := 0
  else if AScan.Body = 0 then
    Exit
  else if IsWord and (T.Low = 'end') then
  begin
    Dec(AScan.Body);
    AScan.Paren := 0;
  end
  else if T.Low = '(' then
    Inc(AScan.Paren)
  else if T.Low = ')' then
    Dec(AScan.Paren)
  else if (AScan.Paren = 0) and (T.Low = ANameLow)
     and InList(APrev.Low, FIELD_PREV) then
  begin
    Colon := GroupColon(AMap, T);
    if Colon.Low = ':' then
      TakeFieldType(AMap, Colon, AScan);
  end;
end;

// Nennt der Text der Zeile ALine ein Wort, mit dem ein Typrumpf beginnt
// (OpensTypeBody: 'record' und TYPE_BODY_WORDS)? Gross/klein egal, auch in
// Kommentar oder String; als Wort und ohne Kopie der Zeile wie die
// Vorfilter in uRdxCodeMap (HasWordNoCase).
function MentionsTypeBody(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L, W : string;
begin
  L := AMap.Raw(ALine);
  Result := HasWordNoCase(L, 'record');
  if not Result then
    for W in TYPE_BODY_WORDS do
      if HasWordNoCase(L, W) then
        Exit(True);
end;

class function TRdxTypeProof.FieldTypeOf(AMap: TRdxCodeMap;
  const AName: string): string;
var
  T, Prev  : TRdxToken;
  Scan     : TFieldScan;
  NameLow  : string;   // nicht 'Low': verdeckte System.Low (Gegen-Review R8)
  Li, Last : Integer;
begin
  Result := '';
  NameLow := LowerCase(AName);
  if NameLow = '' then Exit;
  Scan := Default(TFieldScan);
  // Derselbe Lauf wie bis Charge FC, aber mit Spruengen (Review R3-03):
  // ausserhalb eines Rumpfs (Body = 0) aendert nur ein Token, das einen
  // Rumpf oeffnet, den Zustand (FieldScanStep: begin/implementation setzen
  // 0 auf 0, alles andere endet dort) - am Anfang einer Zeile ohne
  // Rumpfwort (MentionsTypeBody) springt der Lauf darum zur naechsten Zeile
  // mit einem; Prev ist dort wie im Lauf das Token davor. Hinter der letzten
  // Zeile mit dem Namen aendert kein Token mehr Found oder Multi.
  Last := LastLineWith(AMap, NameLow);
  Prev := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '') and (T.Line <= Last) do
  begin
    if (Scan.Body = 0) and (T.Line <> Prev.Line)
       and not MentionsTypeBody(AMap, T.Line) then
    begin
      Li := T.Line + 1;
      while (Li <= Last) and not MentionsTypeBody(AMap, Li) do
        Inc(Li);
      if Li > Last then
        Break;
      T := NextToken(AMap, Li, 1);
      Prev := Before(AMap, T);
      Continue;
    end;
    FieldScanStep(AMap, T, Prev, NameLow, Scan);
    Prev := T;
    T := After(AMap, T);
  end;
  if not Scan.Multi then
    Result := Scan.Found;
end;

end.
