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
//     Unit ist sonst unbekannt: '' bzw. False, nie geraten. Ausnahme seit
//     rwE31 (Fix-Runde 3): NeighbourVarType/NeighbourTypeBase lesen den
//     interface-Teil der Units der uses-Klauseln, die NEBEN der Datei
//     liegen (gleiches Verzeichnis bzw. 'in'-Pfad der Programmdatei) - nur
//     auf Frage des Aufrufers, nie aus dem Netz, unter Deckeln.
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
// BINDUNGSFRAGEN (Realwelt-Test rwE30, Fix-Runde 2): seitdem auch hier,
// weil SCA085/SCA139 (uRdxSimpleFixes, uRdxFixRunner) und SCA144
// (uRdxFloatEqualityFix, das die Planer-Unit uRdxSimpleFixes bewusst
// nicht bindet) dieselben brauchen - der with-Rumpf um eine Stelle
// (InWithBody/EnclosingWiths), die Deklarationen der Routinen um sie
// (LocalBinding, auch verschachtelt: der Quellstellen-Dienst kennt
// verschachtelte Routinen nicht), Variablen auf Unit-Ebene (UnitVarType),
// Felder der eigenen Klasse (OwnFieldType), Felder eines Records
// (RecordFields), geerbte Member (RtlAncestorOrUnknown) und Zweige nur
// alter Compiler (OldCompilerBranchReason). NICHT hier: DeclaresInlineVar
// (uRdxSimpleFixes, teilt RoutineStartLine mit dem SCA066-Planer) und die
// Typen, die der Quellstellen-Dienst beweist (TSourcePlaces.
// DeclaredTypeOf, nur im Laeufer).
//
// FPC-tauglich wie uRdxSimpleFixes, das sie bindet: uRdxCodeMap,
// uRdxRtlTypes, seit rwE30 uRdxBlocks (Routinengrenzen) und uRdxText (der
// Grund von OldCompilerBranchReason); keine Generics, keine Helper - die
// Unit laeuft im FPC-Pruefstand mit.

interface

uses
  uRdxCodeMap;   // TRdxCodeMap

type
  // Wie ein Name an einer Stelle gebunden ist, nach dem Text der Routinen
  // um die Stelle (TRdxTypeProof.LocalBinding, Realwelt-Test rwE30).
  TRdxLocalKind = (
    lkNone,     // keine umschliessende Routine deklariert ihn (vollstaendig gelesen)
    lkVar,      // Parameter, lokale Variable oder Result einer umschliessenden Routine
    lkOther,    // lokal als Konstante, Typ, Marke oder Routine deklariert
    lkUnsure);  // Grenzen unsicher, Inline-Deklaration, anonyme Methode, IFDEF-Doppel

  TRdxLocalFind = record
    Kind      : TRdxLocalKind;
    TypeLow   : string;    // lkVar: der deklarierte Typ, klein ('' = untypisiert)
    Routines  : Integer;   // Zahl der umschliessenden (benannten) Routinen
    OuterName : string;    // Name der aeussersten ('TFoo.Bar'), '' ohne
  end;

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

    // ---- Bindungsfragen (Realwelt-Test rwE30, Fix-Runde 2) ----

    // Liegt ATok im Rumpf einer with-Anweisung? Rueckwaerts bis zum Kopf
    // der Routine (IsRoutineHead) bzw. einem Abschnittswort der Unit: ein
    // 'with' zaehlt nur, wenn zwischen ihm und ATok auf seiner Ebene kein
    // ';' steht - Bloecke dazwischen (begin..end, repeat..until,
    // Typruempfe) werden als Ganzes uebersprungen, ein Block, IN dem ATok
    // steht (sein Oeffner kommt ohne end), beginnt eine neue Ebene. 'with A
    // do begin .. X .. end' und 'with A do if C then X' umfassen X, 'with A
    // do B; X' und 'with A do begin .. end; X' nicht. Bis rwE30 sperrte
    // JEDES with davor in der Routine (TRdxSimpleFixes.WithBefore, auch
    // eines in einer verschachtelten Routine davor; uPSCompiler.pas: 40
    // unnoetige SCA085-Sperren). Im Zweifel True: eine Bilanz, die nicht
    // aufgeht (IFDEF-Zweige mit je einem begin), mehr als MAX_WITH_BACK
    // Token. 'else' beendet keinen Rumpf ('if C then with A do B else X'
    // gilt als umfasst - vorsichtig).
    class function InWithBody(AMap: TRdxCodeMap;
      const ATok: TRdxToken): Boolean; static;
    // Dasselbe mit den with-Token, deren Rumpf ATok umfasst - das innerste
    // zuerst. False, wenn die Bilanz unsicher ist (dann sperren).
    class function EnclosingWiths(AMap: TRdxCodeMap; const ATok: TRdxToken;
      out AWiths: TArray<TRdxToken>): Boolean; static;
    // Die Felder des Records ATypeLow, wenn ihn DIESE Datei genau einmal als
    // 'ATypeLow = [packed] record .. end' deklariert und er nur Felder
    // traegt (keine Methode, Property, Konstante, kein Klassen-Member, kein
    // varianter Teil, kein geschachtelter Typ): Namen klein, je mit Typ
    // (klein, wie FieldTypeOf). False sonst. Fuer with-Ziele (SCA144,
    // rwE30): an einen solchen Record bindet nur ein Feld.
    class function RecordFields(AMap: TRdxCodeMap; const ATypeLow: string;
      out ANames, ATypes: TArray<string>): Boolean; static;

    // Woran bindet AName an der Stelle AAt nach den Deklarationen der
    // BENANNTEN Routinen um sie (TRdxBlocks.HeadBefore, innerste zuerst)?
    // Je Routine: Parameter, Result (nur die innerste, und nur eine
    // function/operator), der Deklarationsteil vor der verschachtelten
    // Routine, in der AAt steht (spaeter Deklariertes sieht sie nicht -
    // lkUnsure, wenn der Name nur dort steht: der Quellstellen-Dienst saehe
    // ihn). Im Rumpf vor AAt: eine Inline-Deklaration ('var X', 'const X',
    // 'for var X') oder eine anonyme Methode, die den Namen nennt (Parameter,
    // lokale Variable) - lkUnsure. Ein Kopf mit unsicheren Grenzen
    // (ReadRoutine) ebenso. with prueft der Aufrufer (InWithBody). Der
    // Quellstellen-Dienst (DeclaredTypeOf) kennt verschachtelte Routinen
    // nicht (uParser2 verwirft sie) - das ist der Text-Ersatz dafuer.
    class function LocalBinding(AMap: TRdxCodeMap; const AAt: TRdxToken;
      const AName: string): TRdxLocalFind; static;

    // Der Typ von AName, wenn die Datei ihn als Variable auf Unit-Ebene
    // deklariert ('var'/'threadvar' im interface- oder implementation-Teil
    // bzw. im Programm, auch mit Anfangswert 'X: T = nil'): klein, '' ohne
    // oder bei verschiedenen Typen (IFDEF-Zweige). Nicht: class var, Felder,
    // lokale Variablen (der Abschnitt steht in einem Typrumpf bzw. im
    // Deklarationsteil einer Routine), typisierte Konstanten.
    class function UnitVarType(AMap: TRdxCodeMap;
      const AName: string): string; static;

    // Der Typ des Feldes AName im Rumpf der Klasse AClassPath ('TFoo',
    // 'TOuter.TInner'; genau ein Klassenkopf mit Rumpf in der Datei,
    // TRdxBlocks.FindClassHeads) auf ihrer obersten Ebene - nicht in einem
    // geschachtelten Typ, nicht Property oder Methode; auch in bedingten
    // Abschnitten ({$IFDEF}), dann mit gleichem Typ. Klein, '' ohne.
    // Vorfahren zaehlen nicht (der Aufrufer sperrt dann).
    class function OwnFieldType(AMap: TRdxCodeMap;
      const AClassPath, AName: string): string; static;

    // Kann ein geerbtes Member der Klasse AClassPath (in dieser Datei)
    // einen Unit-Bezeichner AName verdecken (Pin missed R2(3): TControl.
    // Visible, TComponent.Owner ...)? True, wenn die Vorfahrenkette in der
    // Datei bei einer Klasse der Delphi-Quellen (uRdxRtlTypes) ausser
    // TObject endet, bei TObject (auch 'class' ohne Vorfahren) nur, wenn
    // AName ein Member von TObject ist, wenn die Klasse selbst nicht
    // (eindeutig) in der Datei steht und bei einem class helper (Self ist
    // die erweiterte Klasse). False bei einer fremden Kundenklasse
    // als Vorfahr (deren Member kennt niemand - GRENZE, s. Aufrufer).
    class function RtlAncestorOrUnknown(AMap: TRdxCodeMap;
      const AClassPath, AName: string): Boolean; static;

    // ---- Zweige alter Compiler (rwE30, Fix-Runde 2) ----

    // Liegt ALine in einem Zweig der bedingten Uebersetzung, den nur
    // Compiler VOR Delphi AFeatureDelphi uebersetzen? Gelesen werden die
    // offenen Bedingungen von Dateianfang bis ALine (nur die Datei, keine
    // Includes): ein {$IFNDEF X_UP} bzw. der {$ELSE}-Zweig eines
    // {$IFDEF X_UP}, wenn X_UP eine Version bis AFeatureDelphi nennt
    // (COMPILER6_UP, DELPHI5_UP, GX_VER130_up, RTL140_UP ..), ein
    // {$IFNDEF WIN32} bzw. {$IFDEF WIN16} (16-Bit-Delphi 1), ein
    // {$IFDEF VERnnn}/COMPILERn/DELPHIn einer Version davor, ein
    // {$IF CompilerVersion|RTLVersion < n} bzw. '<=' mit n bis dahin.
    // Ein Zweig nur fuer spaetere alte Compiler ({$IFNDEF COMPILER12_UP})
    // sperrt nicht - die kennen das Sprachmittel.
    // Moderne Compiler sehen den Code dort nie, und gerade der alte, der
    // ihn sieht, kennt das neue Sprachmittel oft nicht (FreeAndNil ab
    // Delphi 5, Math.IsZero/SameValue ab Delphi 6 - JvSimpleXml.pas:252
    // unter {$IFNDEF COMPILER6_UP}, Realwelt-Test rwE30). '' oder der Grund
    // (msgid in dieser Unit), mit der Bedingung und ihrer Zeile.
    class function OldCompilerBranchReason(AMap: TRdxCodeMap;
      ALine, AFeatureDelphi: Integer): string; static;

    // ---- Aliasse und Units neben der Datei (rwE31, Fix-Runde 3) ----

    // Der Typ hinter ATypeName nach der Alias-Kette der Datei ('TFloat =
    // Single' -> 'single'; bis drei Stufen, wie ResolvedTypeKind) - nur,
    // wenn jede Stufe in der Datei genau EINE Deklaration hat oder alle
    // gleich lauten: '{$IFDEF X} TSynExtended = extended; {$ELSE}
    // TSynExtended = double;' (mormot.core.base) gibt ''. Verlaesst die
    // Kette die Datei, der letzte Name; '' wenn die Datei ATypeName nicht
    // deklariert. Klein.
    class function UniqueAliasBase(AMap: TRdxCodeMap;
      const ATypeName: string): string; static;

    // Der Typ von AName, wenn eine Unit der uses-Klauseln von AMap, die
    // neben der Datei AUnitFile liegt, AName in ihrem interface-Teil als
    // Variable deklariert (UnitVarType auf diesem Teil; rwE31: HeidiSQL
    // main.pas:2778 'frmPreferences' aus preferences.pas, jvcl
    // JvDockControlForm.pas:5273 'JvGlobalDockManager' aus JvDockGlobals).
    // Wie beim Compiler gilt die LETZTE Unit der uses-Reihenfolge, die den
    // Namen nennt: nennt eine spaetere lesbare ihn im interface-Teil anders
    // als als Variable, ''. Klein; '' ohne Beweis. GRENZE: eine spaetere
    // Unit, die nicht neben der Datei liegt (RTL, Suchpfad), koennte den
    // Namen ebenfalls deklarieren - sie ist nicht lesbar. Der Aufrufer
    // fragt nur, wenn die Datei selbst den Namen nicht deklariert.
    class function NeighbourVarType(AMap: TRdxCodeMap;
      const AUnitFile, AName: string): string; static;

    // Der Typ hinter ATypeName (UniqueAliasBase) aus der letzten Unit der
    // uses-Klauseln neben AUnitFile, deren interface-Teil ATypeName
    // deklariert (rwE31: Dev-Cpp SVG.pas:3988 'TFloat = single' aus
    // SVGTypes.pas); '' ohne oder bei mehrdeutiger Deklaration. Klein.
    // GRENZE wie NeighbourVarType.
    class function NeighbourTypeBase(AMap: TRdxCodeMap;
      const AUnitFile, ATypeName: string): string; static;
  end;

implementation

uses
  System.SysUtils,   // LowerCase
  System.Classes,    // TStringList, TFileStream (Units neben der Datei, rwE31)
  System.StrUtils,   // EndsText
  uRdxBlocks,        // TRdxBlocks.HeadBefore/ReadRoutine/FindClassHeads (rwE30)
  uRdxPaths,         // IsNetworkPath (Units neben der Datei nie aus dem Netz)
  uRdxRtlTypes,      // IsRtlClassOrInterface (zweiter Beweisweg, E27)
  uRdxText;          // _(): der Grund von OldCompilerBranchReason (E29)

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
// Alias-Aufloesung (ResolvedTypeKind): IsKeyword aus uRdxCodeMap, dieselbe
// Liste wie fuer uRdxSimpleFixes (bis zur Folgewelle des Wochen-Reviews je
// eine Kopie hier und dort). Fuer uebersetzbaren Code aendert der Halt kein
// Ergebnis (ein reserviertes Wort wird nie als 'K =' deklariert), er spart
// die Suche.

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

// Das erste Wort hinter JEDER Deklaration 'ATypeName =' der Datei, in
// ihrer Reihenfolge (DeclaredTypeKind nimmt das erste; UniqueAliasBase
// prueft, ob alle gleich sind - rwE31). AFirstOnly: nach dem ersten
// Treffer aufhoeren.
function DeclaredTypeKinds(AMap: TRdxCodeMap; const ATypeName: string;
  AFirstOnly: Boolean): TArray<string>;
var
  T, K    : TRdxToken;
  TypeLow : string;
begin
  Result := nil;
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
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := K.Low;
      if AFirstOnly then
        Exit;
    end;
    T := NextTokenOnLineWith(AMap, T, TypeLow);
  end;
end;

class function TRdxTypeProof.DeclaredTypeKind(AMap: TRdxCodeMap;
  const ATypeName: string): string;
var
  Kinds : TArray<string>;
begin
  Kinds := DeclaredTypeKinds(AMap, ATypeName, True);
  if Length(Kinds) = 0 then
    Result := ''
  else
    Result := Kinds[0];
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

{ ---- Bindungsfragen (rwE30) ---- }

const
  // So weit liest InWithBody rueckwaerts; darueber hinaus: True (sperrt).
  MAX_WITH_BACK = 200000;
  // Woerter, die in einer Typangabe eines var-Eintrags stehen koennen -
  // sie beenden die Suche nach dem Abschnittswort nicht (SectionWordOf).
  TYPE_EXPR_WORDS: array[0..18] of string = ('array', 'of', 'set', 'string',
    'file', 'packed', 'nil', 'absolute', 'procedure', 'function',
    'reference', 'to', 'object', 'const', 'not', 'and', 'or', 'in', 'class');
  // Die Member von TObject (Delphi 12 System.pas, dazu FPC) - ein Global
  // gleichen Namens verdeckte in jeder Methode das Member
  // (RtlAncestorOrUnknown).
  TOBJECT_MEMBERS: array[0..33] of string = ('create', 'free', 'destroy',
    'disposeof', 'disposed', 'initinstance', 'cleanupinstance', 'classtype',
    'classname', 'classnameis', 'classparent', 'classinfo', 'instancesize',
    'inheritsfrom', 'methodaddress', 'methodname', 'qualifiedclassname',
    'fieldaddress', 'getinterface', 'getinterfaceentry', 'getinterfacetable',
    'unitname', 'unitscope', 'equals', 'gethashcode', 'tostring',
    'safecallexception', 'afterconstruction', 'beforedestruction',
    'dispatch', 'defaulthandler', 'newinstance', 'freeinstance',
    'checkdisposed');
  // Abschnittswoerter eines Deklarationsteils.
  SECTION_WORDS: array[0..5] of string = ('var', 'threadvar', 'const',
    'resourcestring', 'type', 'label');
  // Davor steht der Name eines Abschnittseintrags.
  ENTRY_PREV: array[0..7] of string = ('var', 'threadvar', 'const',
    'resourcestring', 'type', 'label', ';', ',');
  // Davor steht der Name eines Parameters.
  PARAM_PREV: array[0..7] of string = ('(', ';', ',', 'const', 'var', 'out',
    'constref', ']');
  MAX_DECL_TOKENS = 100000;
  MAX_HERITAGE_STEPS = 16;

// Oeffnet T (rueckwaerts gelesen) einen Block, dessen end der Lauf schon
// gezaehlt hat: begin, case, try, asm, repeat (zu until) als
// Schluesselwort, ein Typrumpf (OpensTypeBody - auch 'record' nur so: nicht
// die generische Einschraenkung '<T: record>').
function OpensBlockBack(AMap: TRdxCodeMap; const T, P: TRdxToken): Boolean;
begin
  if T.Low = 'record' then
    Exit(OpensTypeBody(AMap, T, P));
  Result := (IsKeywordAfter(T, P)
             and (InList(T.Low, END_OPENERS) or (T.Low = 'repeat')))
    or OpensTypeBody(AMap, T, P);
end;

// Beendet T (rueckwaerts) die Suche nach einem umfassenden with: der Kopf
// einer benannten Routine (nicht 'Operator := ..') oder ein Abschnittswort
// der Unit ('interface' hinter '=' ist ein Typrumpf, den OpensBlockBack
// vorher nimmt).
function EndsWithSearch(AMap: TRdxCodeMap; const T, P: TRdxToken): Boolean;
begin
  if InList(T.Low, UNIT_BOUNDS) and IsKeywordAfter(T, P) then
    Exit(True);
  Result := IsRoutineHeadAfter(T, P) and (After(AMap, T).Low <> ':=');
end;

class function TRdxTypeProof.EnclosingWiths(AMap: TRdxCodeMap;
  const ATok: TRdxToken; out AWiths: TArray<TRdxToken>): Boolean;
var
  T, P    : TRdxToken;
  Depth   : Integer;   // Bloecke, deren end rueckwaerts schon gezaehlt ist
  Paren   : Integer;   // ')' bzw. ']' auf Tiefe 0 ohne ihre Oeffnung
  Steps   : Integer;
  Crossed : Boolean;   // ein ';' auf der Ebene von ATok gekreuzt
begin
  Result := False;
  AWiths := nil;
  Depth := 0;
  Paren := 0;
  Steps := 0;
  Crossed := False;
  T := Before(AMap, ATok);
  while T.Low <> '' do
  begin
    Inc(Steps);
    if Steps > MAX_WITH_BACK then
      Exit;
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) and ((T.Low = 'end') or (T.Low = 'until')) then
      Inc(Depth)
    else if OpensBlockBack(AMap, T, P) then
    begin
      if Depth > 0 then
        Dec(Depth)
      else
      begin
        // Ein Block um ATok: dessen Anweisung ist die naechste Ebene.
        Crossed := False;
        Paren := 0;
      end;
    end
    else if Depth = 0 then
    begin
      if (T.Low = 'with') and IsKeywordAfter(T, P) then
      begin
        // Umfasst ATok; ein with davor in derselben Anweisung ('with A do
        // with B do') ebenso - weiter suchen.
        if not Crossed then
        begin
          SetLength(AWiths, Length(AWiths) + 1);
          AWiths[High(AWiths)] := T;
        end;
      end
      else if EndsWithSearch(AMap, T, P) then
        Break
      else if (T.Low = ')') or (T.Low = ']') then
        Inc(Paren)
      else if (T.Low = '(') or (T.Low = '[') then
      begin
        if Paren > 0 then
          Dec(Paren);
      end
      else if (T.Low = ';') and (Paren = 0) then
        Crossed := True;
    end;
    T := P;
  end;
  // Geht die Bilanz nicht auf, ist die Ebene unsicher.
  Result := Depth = 0;
end;

class function TRdxTypeProof.InWithBody(AMap: TRdxCodeMap;
  const ATok: TRdxToken): Boolean;
var
  Withs : TArray<TRdxToken>;
begin
  Result := not EnclosingWiths(AMap, ATok, Withs) or (Length(Withs) > 0);
end;

class function TRdxTypeProof.RecordFields(AMap: TRdxCodeMap;
  const ATypeLow: string; out ANames, ATypes: TArray<string>): Boolean;
var
  T, K, P, Colon, N : TRdxToken;
  Found             : Integer;
  Depth, Steps      : Integer;
  Scan              : TFieldScan;
begin
  Result := False;
  ANames := nil;
  ATypes := nil;
  if ATypeLow = '' then
    Exit;
  // Genau eine Deklaration 'ATypeLow = [packed] record' (wie
  // DeclaredTypeKind: hinter ';', 'type', ']' oder 'generic').
  Found := 0;
  K := Default(TRdxToken);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ATypeLow);
  while T.Low <> '' do
  begin
    if (T.Low = ATypeLow) and (After(AMap, T).Low = '=')
       and InList(Before(AMap, T).Low, TYPE_DECL_PREV) then
    begin
      Inc(Found);
      K := After(AMap, After(AMap, T));
      if K.Low = 'packed' then
        K := After(AMap, K);
    end;
    T := NextTokenOnLineWith(AMap, T, ATypeLow);
  end;
  if (Found <> 1) or (K.Low <> 'record') then
    Exit;
  Depth := 1;
  Steps := 0;
  P := K;
  T := After(AMap, K);
  while (T.Low <> '') and (Steps < MAX_DECL_TOKENS) do
  begin
    Inc(Steps);
    if (T.Low = '(') or (T.Low = '[') then
    begin
      // Array-Grenzen, Typargumente in Klammern
      N := MatchClose(AMap, T);
      if N.Low = '' then
        Exit;
      P := N;
      T := After(AMap, N);
      Continue;
    end;
    if OpensTypeBody(AMap, T, P) then
      Exit;   // geschachtelter Rumpf (record im record ...) - nicht gelesen
    if IsKeywordAfter(T, P) and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(True);
    end
    else if IsKeywordAfter(T, P) and InList(T.Low, ['procedure', 'function',
       'property', 'constructor', 'destructor', 'operator', 'class', 'case',
       'const', 'type', 'var', 'begin', 'implementation']) then
      Exit   // ein Member, das kein Feld ist (oder die Bilanz ist verloren)
    else if T.IsWord and InList(P.Low, [';', 'record', ',', 'private',
       'public', 'strict', ']']) and InList(After(AMap, T).Low, [',', ':']) then
    begin
      Colon := GroupColon(AMap, T);
      if Colon.Low <> ':' then
        Exit;
      Scan := Default(TFieldScan);
      TakeFieldType(AMap, Colon, Scan);
      SetLength(ANames, Length(ANames) + 1);
      ANames[High(ANames)] := T.Low;
      SetLength(ATypes, Length(ATypes) + 1);
      ATypes[High(ATypes)] := Scan.Found;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Der Typ hinter dem ':' AColon (Regel wie FieldTypeOf, TakeFieldType),
// 'packed' uebersprungen.
function TypeAfterColon(AMap: TRdxCodeMap; const AColon: TRdxToken): string;
var
  Scan : TFieldScan;
  C    : TRdxToken;
begin
  Scan := Default(TFieldScan);
  C := AColon;
  if After(AMap, C).Low = 'packed' then
    C := After(AMap, C);
  TakeFieldType(AMap, C, Scan);
  Result := Scan.Found;
end;

// Ist T der Name ANameLow eines Parameters im Kopf von R? ATypeLow: sein
// Typ ('' untypisiert: 'var Buf').
function ParamOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ANameLow: string; out ATypeLow: string): Boolean;
var
  T, P, Close, Colon : TRdxToken;
begin
  Result := False;
  ATypeLow := '';
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low <> '(' then
    Exit;
  Close := MatchClose(AMap, T);
  if Close.Low = '' then
    Exit;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and TokBefore(T, Close) do
  begin
    if ((T.Low = '(') or (T.Low = '[')) and (P.Low <> ';') then
    begin
      // Klammern in einem Typ oder Vorgabewert ('P: procedure(X: Integer)',
      // '= [a, b]') - ihr Inhalt ist kein Parameter dieses Kopfs.
      P := MatchClose(AMap, T);
      if P.Low = '' then
        Exit;
      T := After(AMap, P);
      Continue;
    end;
    if T.IsWord and (T.Low = ANameLow) and InList(P.Low, PARAM_PREV)
       and InList(After(AMap, T).Low, [',', ':', ';', ')']) then
    begin
      Colon := GroupColon(AMap, T);
      if Colon.Low = ':' then
        ATypeLow := TypeAfterColon(AMap, Colon);
      Exit(True);
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Result einer function/operator R: True mit dem Rueckgabetyp.
function ResultOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out ATypeLow: string): Boolean;
var
  T : TRdxToken;
begin
  ATypeLow := '';
  Result := InList(R.Keyword.Low, ['function', 'operator']);
  if not Result then
    Exit;
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low = '(' then
    T := AfterClose(AMap, T);
  if T.Low = ':' then
    ATypeLow := TypeAfterColon(AMap, T);
end;

// Ein Typrumpf ab dem Oeffner T (OpensTypeBody) bis zu seinem end - T
// wird das end; False, wenn keines kommt oder ein begin bzw. ein
// Abschnittswort der Unit dazwischen steht (Bilanz verloren).
function SkipTypeBody(AMap: TRdxCodeMap; var T: TRdxToken): Boolean;
var
  P     : TRdxToken;
  Depth : Integer;
  Steps : Integer;
begin
  Result := False;
  Depth := 1;
  Steps := 0;
  P := T;
  T := After(AMap, T);
  while (T.Low <> '') and (Steps < MAX_DECL_TOKENS) do
  begin
    Inc(Steps);
    if OpensTypeBody(AMap, T, P) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and (T.Low = 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(True);
    end
    else if IsKeywordAfter(T, P)
       and ((T.Low = 'begin') or InList(T.Low, UNIT_BOUNDS)) then
      Exit;
    P := T;
    T := After(AMap, T);
  end;
end;

// Der Eintrag ANameLow im Deklarationsteil von R (zwischen dem ';' des
// Kopfs und dem Rumpf): lkVar (var/threadvar, mit Typ), lkOther (const,
// resourcestring, type, label oder eine lokale Routine dieses Namens),
// lkNone, lkUnsure (Grenzen einer lokalen Routine unsicher, zwei Eintraege
// mit verschiedenem Typ). ALater: der Name steht erst HINTER der lokalen
// Routine, in der AAt steht - dort unsichtbar, nicht gezaehlt.
function DeclOf(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AAt: TRdxToken; const ANameLow: string; out ATypeLow: string;
  out ALater: Boolean): TRdxLocalKind;
var
  T, P, Colon : TRdxToken;
  Sub         : TRdxRoutine;
  Sec, Ty     : string;
  Passed      : Boolean;   // die lokale Routine mit AAt liegt hinter uns
  Steps       : Integer;
  Kind        : TRdxLocalKind;
begin
  Result := lkNone;
  ATypeLow := '';
  ALater := False;
  Passed := False;
  Sec := '';
  Steps := 0;
  P := R.HeaderEnd;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, R.Body) do
  begin
    Inc(Steps);
    if Steps > MAX_DECL_TOKENS then
      Exit(lkUnsure);
    if IsKeywordAfter(T, P) and InList(T.Low, SECTION_WORDS) then
      Sec := T.Low
    else if (P.Low = ';') and IsKeywordAfter(T, P)
       and (InList(T.Low, ROUTINE_WORDS) or (T.Low = 'class')) then
    begin
      if TRdxBlocks.ReadRoutine(AMap, T, Sub) <> '' then
        Exit(lkUnsure);
      if Sub.NameTok.Low = ANameLow then
      begin
        if Passed then
          ALater := True
        else
          Exit(lkOther);
      end;
      if TokBefore(AAt, Sub.Last) then
        Passed := True;
      Sec := '';
      P := Sub.Last;
      T := After(AMap, P);
      Continue;
    end
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      P := MatchClose(AMap, T);
      if P.Low = '' then
        Exit(lkUnsure);
      T := After(AMap, P);
      Continue;
    end
    else if OpensTypeBody(AMap, T, P) then
    begin
      if not SkipTypeBody(AMap, T) then
        Exit(lkUnsure);
    end
    else if (Sec <> '') and T.IsWord and (T.Low = ANameLow)
       and InList(P.Low, ENTRY_PREV)
       and InList(After(AMap, T).Low, [',', ':', '=', ';', '<']) then
    begin
      if Passed then
        ALater := True
      else
      begin
        Ty := '';
        if (Sec = 'var') or (Sec = 'threadvar') then
        begin
          Kind := lkVar;
          Colon := GroupColon(AMap, T);
          if Colon.Low = ':' then
            Ty := TypeAfterColon(AMap, Colon);
        end
        else
          Kind := lkOther;
        if Result = lkNone then
        begin
          Result := Kind;
          ATypeLow := Ty;
        end
        else if (Result <> Kind) or (ATypeLow <> Ty) then
          Exit(lkUnsure);   // zwei Eintraege (IFDEF-Zweige), verschieden
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Beginnt die Namensliste vor T ('A, B, T') mit 'var' bzw. 'const'? P ist
// das Token vor T.
function InlineDeclList(AMap: TRdxCodeMap; const P: TRdxToken): Boolean;
var
  Q, W : TRdxToken;
  n    : Integer;
begin
  Q := P;
  n := 0;
  while (Q.Low = ',') and (n < 64) do
  begin
    W := Before(AMap, Q);
    if not W.IsWord then
      Exit(False);
    Q := Before(AMap, W);
    Inc(n);
  end;
  Result := InList(Q.Low, INLINE_DECLS)
    and IsKeywordAfter(Q, Before(AMap, Q));
end;

// Nennt der Rumpf von R vor AAt den Namen als Inline-Deklaration ('var X',
// 'const X', 'var A, X', 'for var X') oder im Kopf bzw. Deklarationsteil
// einer anonymen Methode (bis zu ihrem begin)?
function BodyShadows(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AAt: TRdxToken; const ANameLow: string): Boolean;
var
  T, P, A : TRdxToken;
  Steps   : Integer;
begin
  Result := True;
  Steps := 0;
  P := R.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, AAt) do
  begin
    Inc(Steps);
    if Steps > MAX_DECL_TOKENS then
      Exit;
    if T.IsWord and (T.Low = ANameLow)
       and InList(After(AMap, T).Low, [':', ',', ':='])
       and InlineDeclList(AMap, P) then
      Exit;
    if IsKeywordAfter(T, P) and InList(T.Low, ['procedure', 'function']) then
    begin
      // Anonyme Methode: Kopf und lokale Abschnitte bis zu ihrem begin.
      A := After(AMap, T);
      while (A.Low <> '') and (A.Low <> 'begin') and TokBefore(A, AAt) do
      begin
        if A.IsWord and (A.Low = ANameLow) then
          Exit;
        A := After(AMap, A);
      end;
    end;
    P := T;
    T := After(AMap, T);
  end;
  Result := False;
end;

class function TRdxTypeProof.LocalBinding(AMap: TRdxCodeMap;
  const AAt: TRdxToken; const AName: string): TRdxLocalFind;
var
  T       : TRdxToken;
  S       : TRdxHeadStep;
  R       : TRdxRoutine;
  NameLow : string;
  Ty      : string;
  Kind    : TRdxLocalKind;
  Later   : Boolean;
  AnyLate : Boolean;
  TopCol  : Integer;   // Spalte des Kopfs der zuletzt gefundenen Routine
begin
  Result := Default(TRdxLocalFind);
  Result.Kind := lkUnsure;
  NameLow := LowerCase(Trim(AName));
  if (NameLow = '') or (AAt.Low = '') then
    Exit;
  AnyLate := False;
  TopCol := 0;
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) do
  begin
    if S.Stop then
      Break;
    if S.Reason <> '' then
    begin
      // Diese Routine koennte AAt umfassen - ausser die zuletzt gefundene
      // umfassende beginnt in Spalte 1 (Konvention: eine Routine auf
      // Unit-Ebene; lokale sind eingerueckt, wie RoutineStartLine in
      // uRdxSimpleFixes). Sonst lkUnsure.
      if TopCol = 1 then
        Break;
      Exit;
    end;
    R := S.Routine;
    if (R.Body.Low = '') or not TokBefore(AAt, R.EndTok) then
      Continue;   // endet vor AAt (oder ohne Rumpf)
    Inc(Result.Routines);
    Result.OuterName := R.Name;
    if TokBefore(R.Body, AAt) and BodyShadows(AMap, R, AAt, NameLow) then
      Exit;
    if ParamOf(AMap, R, NameLow, Ty) then
    begin
      Result.Kind := lkVar;
      Result.TypeLow := Ty;
      Exit;
    end;
    if (NameLow = 'result') and (Result.Routines = 1)
       and ResultOf(AMap, R, Ty) then
    begin
      Result.Kind := lkVar;
      Result.TypeLow := Ty;
      Exit;
    end;
    Kind := DeclOf(AMap, R, AAt, NameLow, Ty, Later);
    if Kind <> lkNone then
    begin
      Result.Kind := Kind;
      if Kind = lkVar then
        Result.TypeLow := Ty;
      Exit;
    end;
    AnyLate := AnyLate or Later;
    // Eine Methode ('TFoo.Bar') steht immer auf Unit-Ebene - weiter
    // aussen gibt es keine Routine; die Koepfe davor zu lesen kostet nur
    // (und eine unsichere davor machte den Befund unsicher).
    if Pos('.', R.Name) > 0 then
      Break;
    TopCol := R.Head.Col;
  end;
  if AnyLate then
    Result.Kind := lkUnsure
  else
    Result.Kind := lkNone;
end;

// Das Abschnittswort, unter dem der Eintragsname T steht: rueckwaerts ueber
// die Eintraege davor (Typruempfe, Klammern, Typwoerter) bis zum ersten
// anderen Schluesselwort; Low = '' wenn vorher eine offene Klammer kommt
// (ein Parameter) oder ein Rumpf, in dem T steht.
function SectionWordOf(AMap: TRdxCodeMap; const T: TRdxToken): TRdxToken;
var
  X, P         : TRdxToken;
  Depth, Paren : Integer;
  Steps        : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Paren := 0;
  Steps := 0;
  X := Before(AMap, T);
  while (X.Low <> '') and (Steps < MAX_DECL_TOKENS) do
  begin
    Inc(Steps);
    P := Before(AMap, X);
    if (X.Low = ')') or (X.Low = ']') then
      Inc(Paren)
    else if (X.Low = '(') or (X.Low = '[') then
    begin
      Dec(Paren);
      if Paren < 0 then
        Exit;
    end
    // In Klammern zaehlt nichts (Vorgabewerte, Array-Grenzen).
    else if (Paren = 0) and IsKeywordAfter(X, P) and (X.Low = 'end') then
      Inc(Depth)
    else if (Paren = 0) and OpensTypeBody(AMap, X, P) then
    begin
      if Depth = 0 then
        Exit;
      Dec(Depth);
    end
    else if (Paren = 0) and (Depth = 0) and IsKeywordAfter(X, P)
       and InList(X.Low, RESERVED) and not InList(X.Low, TYPE_EXPR_WORDS) then
      Exit(X);
    X := P;
  end;
end;

// Steht das Abschnittswort AVar auf Unit-Ebene? Ein Lauf von vorn ueber
// die Unit-Ebene: Typruempfe zaehlen (OpensTypeBody/end, wie FieldTypeOf -
// darin steht ein class var bzw. ein var-Abschnitt der Klasse); eine
// Routine mit Rumpf (ausserhalb des interface-Teils, auf Rumpftiefe 0)
// liest TRdxBlocks.ReadRoutine als Ganzes und springt dahinter - umfasst
// sie AVar, ist es ein lokaler Abschnitt; sind ihre Grenzen unsicher,
// bleibt es offen (False). Nicht hinter 'class' (class var).
function AtUnitLevel(AMap: TRdxCodeMap; const AVar: TRdxToken): Boolean;
var
  T, P   : TRdxToken;
  Body   : Integer;
  InIntf : Boolean;
  R      : TRdxRoutine;
begin
  Result := False;
  if Before(AMap, AVar).Low = 'class' then
    Exit;
  Body := 0;
  InIntf := False;
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while (T.Low <> '') and TokBefore(T, AVar) do
  begin
    if OpensTypeBody(AMap, T, P) then
      Inc(Body)
    else if IsKeywordAfter(T, P) and InList(T.Low, UNIT_BOUNDS) then
    begin
      Body := 0;
      InIntf := T.Low = 'interface';
    end
    else if (Body > 0) and IsKeywordAfter(T, P) and (T.Low = 'end') then
      Dec(Body)
    else if (Body = 0) and not InIntf and IsRoutineHeadAfter(T, P)
       and (After(AMap, T).Low <> ':=') then
    begin
      if TRdxBlocks.ReadRoutine(AMap, T, R) <> '' then
        Exit;
      if TokBefore(AVar, R.Last) then
        Exit;   // AVar steht im Deklarationsteil dieser Routine
      P := R.Last;
      T := After(AMap, P);
      Continue;
    end;
    P := T;
    T := After(AMap, T);
  end;
  Result := Body = 0;
end;

class function TRdxTypeProof.UnitVarType(AMap: TRdxCodeMap;
  const AName: string): string;
var
  T, Sec, Colon : TRdxToken;
  NameLow, Ty   : string;
  Found         : Boolean;
begin
  Result := '';
  NameLow := LowerCase(Trim(AName));
  if NameLow = '' then
    Exit;
  Found := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), NameLow);
  while T.Low <> '' do
  begin
    if (T.Low = NameLow) and InList(Before(AMap, T).Low, ['var', 'threadvar',
         ';', ',']) then
    begin
      Colon := GroupColon(AMap, T);
      if Colon.Low = ':' then
      begin
        Sec := SectionWordOf(AMap, T);
        if InList(Sec.Low, ['var', 'threadvar']) and AtUnitLevel(AMap, Sec) then
        begin
          Ty := TypeAfterColon(AMap, Colon);
          if Ty = '' then
            Exit('');
          if Found and (Ty <> Result) then
            Exit('');   // IFDEF-Zweige mit verschiedenen Typen
          Result := Ty;
          Found := True;
        end;
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, NameLow);
  end;
end;

class function TRdxTypeProof.OwnFieldType(AMap: TRdxCodeMap;
  const AClassPath, AName: string): string;
var
  Heads   : TArray<TRdxToken>;
  T, P    : TRdxToken;
  Scan    : TFieldScan;
  NameLow : string;
  Steps   : Integer;
  Colon   : TRdxToken;
begin
  Result := '';
  NameLow := LowerCase(Trim(AName));
  if (NameLow = '') or (AClassPath = '') then
    Exit;
  Heads := TRdxBlocks.FindClassHeads(AMap, AClassPath);
  if Length(Heads) <> 1 then
    Exit;
  Scan := Default(TFieldScan);
  Steps := 0;
  P := Before(AMap, Heads[0]);
  T := Heads[0];
  while (T.Low <> '') and (Steps < MAX_DECL_TOKENS) do
  begin
    Inc(Steps);
    if OpensTypeBody(AMap, T, P) then
      Inc(Scan.Body)
    else if Scan.Body = 0 then
      Exit
    else if IsKeywordAfter(T, P)
       and ((T.Low = 'begin') or InList(T.Low, UNIT_BOUNDS)) then
      Exit   // Bilanz verloren
    else if IsKeywordAfter(T, P) and (T.Low = 'end') then
    begin
      Dec(Scan.Body);
      Scan.Paren := 0;
      if Scan.Body = 0 then
        Break;
    end
    else if T.Low = '(' then
      Inc(Scan.Paren)
    else if T.Low = ')' then
      Dec(Scan.Paren)
    else if (Scan.Body = 1) and (Scan.Paren = 0) and (T.Low = NameLow)
       and InList(P.Low, FIELD_PREV) then
    begin
      Colon := GroupColon(AMap, T);
      if Colon.Low = ':' then
        TakeFieldType(AMap, Colon, Scan);
    end;
    P := T;
    T := After(AMap, T);
  end;
  if not Scan.Multi then
    Result := Scan.Found;
end;

class function TRdxTypeProof.RtlAncestorOrUnknown(AMap: TRdxCodeMap;
  const AClassPath, AName: string): Boolean;
var
  Heads   : TArray<TRdxToken>;
  Parents : TArray<string>;
  Name    : string;
  i       : Integer;
  ObjRisk : Boolean;   // AName ist ein Member von TObject
begin
  Result := True;
  ObjRisk := InList(LowerCase(Trim(AName)), TOBJECT_MEMBERS);
  Name := AClassPath;
  for i := 1 to MAX_HERITAGE_STEPS do
  begin
    Heads := TRdxBlocks.FindClassHeads(AMap, Name);
    if Length(Heads) <> 1 then
    begin
      // Nicht (eindeutig) in der Datei: TObject kennt man, eine andere
      // Klasse der Delphi-Quellen verdeckt Namen, eine fremde Kundenklasse
      // gilt als nicht (GRENZE, s. TRdxSimpleFixes.VariableProof).
      if i = 1 then
        Exit;
      if SameText(Name, 'TObject') then
        Exit(ObjRisk);
      Exit(IsRtlClassOrInterface(LowerCase(Name)));
    end;
    // 'class helper for TStrings': Self ist die erweiterte Klasse, deren
    // Member (auch einer fremden Unit) ein Global verdecken; HeritageOf
    // saehe keine Vorfahren und hielte sie fuer TObject (Review
    // e/HilfeFixI).
    if After(AMap, Heads[0]).Low = 'helper' then
      Exit;
    Parents := TRdxBlocks.HeritageOf(AMap, Heads[0]);
    if Length(Parents) = 0 then
      Exit(ObjRisk);   // 'class' ohne Vorfahren: TObject
    Name := Parents[0];
  end;
end;

{ ---- Zweige alter Compiler (rwE30) ---- }

const
  R_OLD_BRANCH = 'the place lies in a branch only old compilers translate '
    + '(%s, line %d) - the help would not compile there, and current '
    + 'compilers never see the code';
  // VERnnn je Delphi-Version 1..8 (VER80 = Delphi 1 .. VER160 = Delphi 8).
  DELPHI_VER: array[1..8] of Integer = (80, 90, 100, 120, 130, 140, 150, 160);
  MAX_COND_STACK = 64;

// Die Delphi-Version, ab der ein Versionssymbol ASym (gross, auf '_UP')
// gilt: COMPILERn_UP/DELPHIn_UP/BCBn_UP -> n, ..VERnnn_UP/RTLnnn_UP
// (GX_VER130_UP) -> die Delphi-Version zu VERnnn (VER130 = 5); 99 fuer eine
// Version nach Delphi 8 (DELPHI2009_UP, VER200_UP), -1 ohne solches Symbol.
function UpSymDelphi(const ASym: string): Integer;
var
  i, n, Num, d : Integer;
  Pre          : string;
begin
  Result := -1;
  n := Length(ASym);
  if (n < 5) or (Copy(ASym, n - 2, 3) <> '_UP') then
    Exit;
  i := n - 3;
  if not CharInSet(ASym[i], ['0'..'9']) then
    Exit;
  while (i > 0) and CharInSet(ASym[i], ['0'..'9']) do
    Dec(i);
  if i = 0 then
    Exit;
  Num := StrToIntDef(Copy(ASym, i + 1, n - 3 - i), -1);
  Pre := Copy(ASym, 1, i);
  if (Pre = 'COMPILER') or (Pre = 'DELPHI') or (Pre = 'BCB') then
  begin
    if Num > 8 then
      Exit(99);
    Exit(Num);
  end;
  if (Copy(Pre, Length(Pre) - 2, 3) = 'VER') or (Pre = 'RTL') then
  begin
    for d := Low(DELPHI_VER) to High(DELPHI_VER) do
      if DELPHI_VER[d] = Num then
        Exit(d);
    if Num > DELPHI_VER[High(DELPHI_VER)] then
      Result := 99;
  end;
end;

// Die Zahl hinter APrefix, wenn ASym genau APrefix + Ziffern ist; -1 sonst.
function NumberAfter(const ASym, APrefix: string): Integer;
var
  Rest : string;
begin
  Result := -1;
  if Pos(APrefix, ASym) <> 1 then
    Exit;
  Rest := Copy(ASym, Length(APrefix) + 1, MaxInt);
  if (Rest = '') or not CharInSet(Rest[1], ['0'..'9']) then
    Exit;
  Result := StrToIntDef(Rest, -1);
end;

// Nennt ASym (gross) genau eine Version vor Delphi AFeature (VER130,
// COMPILER5, DELPHI5) oder 16-Bit (WIN16)?
function IsOldExactSym(const ASym: string; AFeature: Integer): Boolean;
var
  n : Integer;
begin
  if ASym = 'WIN16' then
    Exit(True);
  n := NumberAfter(ASym, 'VER');
  if (n >= 80) and (AFeature >= 2) and (AFeature <= 8) then
    Exit(n < DELPHI_VER[AFeature]);
  n := NumberAfter(ASym, 'COMPILER');
  if n < 0 then
    n := NumberAfter(ASym, 'DELPHI');
  Result := (n >= 1) and (n < AFeature) and (n <= 8);
end;

// Das Symbol einer Bedingung, gross: das erste Wort von AArgs;
// 'defined(X)' -> X, 'not defined(X)' -> X mit ANot.
function CondSymbol(const AArgs: string; out ANot: Boolean): string;
var
  S : string;
  i : Integer;
begin
  ANot := False;
  S := UpperCase(Trim(AArgs));
  if Pos('NOT ', S) = 1 then
  begin
    ANot := True;
    S := Trim(Copy(S, 5, MaxInt));
  end;
  if Pos('DEFINED(', S) = 1 then
    S := Copy(S, 9, MaxInt);
  i := 1;
  while (i <= Length(S)) and CharInSet(S[i], ['A'..'Z', '0'..'9', '_']) do
    Inc(i);
  Result := Copy(S, 1, i - 1);
end;

// '{$IF CompilerVersion < n}' bzw. '<= n' (auch RTLVersion), allein: gilt
// der Zweig nur fuer Versionen vor Delphi AFeature (CompilerVersion 13 =
// Delphi 5, 14 = Delphi 6 - je Delphi-Version bis 7 die Nummer + 8)?
function IsOldVersionBound(const AArgs: string; AFeature: Integer): Boolean;
var
  S, U, Num : string;
  Le        : Boolean;
  i, n      : Integer;
begin
  Result := False;
  U := UpperCase(AArgs);
  if (Pos(' AND ', U) > 0) or (Pos(' OR ', U) > 0) then
    Exit;
  S := StringReplace(U, ' ', '', [rfReplaceAll]);
  if Pos('COMPILERVERSION<', S) = 1 then
    S := Copy(S, Length('COMPILERVERSION<') + 1, MaxInt)
  else if Pos('RTLVERSION<', S) = 1 then
    S := Copy(S, Length('RTLVERSION<') + 1, MaxInt)
  else
    Exit;
  Le := (S <> '') and (S[1] = '=');
  if Le then
    S := Copy(S, 2, MaxInt);
  i := 1;
  while (i <= Length(S)) and CharInSet(S[i], ['0'..'9']) do
    Inc(i);
  Num := Copy(S, 1, i - 1);
  n := StrToIntDef(Num, -1);
  if n < 0 then
    Exit;
  if Le then
    Result := n < AFeature + 8
  else
    Result := n <= AFeature + 8;
end;

// Gilt der gerade aktive Zweig einer Bedingung (AWord, AArgs, im ELSE-Teil
// AInElse) nur fuer alte Compiler?
function OldOnlyBranch(const AWord, AArgs: string; AInElse: Boolean;
  AFeature: Integer): Boolean;
var
  Sym     : string;
  Neg     : Boolean;
  Defined : Boolean;   // der Zweig gilt, wenn Sym definiert ist
  n       : Integer;
begin
  Result := False;
  if (AWord = 'if') or (AWord = 'elseif') then
  begin
    if not AInElse and IsOldVersionBound(AArgs, AFeature) then
      Exit(True);
    // Sonst nur die Formen 'defined(X)' und 'not defined(X)'.
    if Pos('DEFINED', UpperCase(AArgs)) = 0 then
      Exit;
    Sym := CondSymbol(AArgs, Neg);
    Defined := not Neg;
  end
  else if AWord = 'ifdef' then
  begin
    Sym := CondSymbol(AArgs, Neg);
    Defined := True;
  end
  else if AWord = 'ifndef' then
  begin
    Sym := CondSymbol(AArgs, Neg);
    Defined := False;
  end
  else
    Exit;
  if AInElse then
    Defined := not Defined;
  if Defined then
    Result := IsOldExactSym(Sym, AFeature)
  else
  begin
    // Der Zweig gilt nur VOR der Version des Symbols: alt, wenn schon
    // diese Version das Sprachmittel kennt; ohne WIN32 ist es Delphi 1.
    n := UpSymDelphi(Sym);
    Result := ((n >= 1) and (n <= AFeature)) or (Sym = 'WIN32');
  end;
end;

class function TRdxTypeProof.OldCompilerBranchReason(AMap: TRdxCodeMap;
  ALine, AFeatureDelphi: Integer): string;
var
  Words, Args, Texts : array of string;
  Lines              : array of Integer;
  InElse             : array of Boolean;
  n, i, Li, Co       : Integer;
  W                  : string;
  Arg                : Boolean;
begin
  Result := '';
  SetLength(Words, MAX_COND_STACK);
  SetLength(Args, MAX_COND_STACK);
  SetLength(Texts, MAX_COND_STACK);
  SetLength(Lines, MAX_COND_STACK);
  SetLength(InElse, MAX_COND_STACK);
  n := 0;
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) and (Li < ALine) do
  begin
    W := DirectiveWord(AMap, Li, Co, Arg);
    if InList(W, COND_OPENERS) then
    begin
      if n = MAX_COND_STACK then
        Exit;   // zu tief verschachtelt - keine Aussage
      Words[n] := W;
      Args[n] := DirectiveArgs(AMap, Li, Co);
      Texts[n] := Copy(AMap.Raw(Li), Co, MaxInt);
      Lines[n] := Li;
      InElse[n] := False;
      Inc(n);
    end
    else if (W = 'else') and (n > 0) then
      InElse[n - 1] := True
    else if (W = 'elseif') and (n > 0) then
    begin
      Words[n - 1] := W;
      Args[n - 1] := DirectiveArgs(AMap, Li, Co);
      Texts[n - 1] := Copy(AMap.Raw(Li), Co, MaxInt);
      Lines[n - 1] := Li;
      InElse[n - 1] := False;
    end
    else if InList(W, COND_CLOSERS) and (n > 0) then
      Dec(n);
    Inc(Co);
  end;
  for i := 0 to n - 1 do
    if OldOnlyBranch(Words[i], Args[i], InElse[i], AFeatureDelphi) then
    begin
      // Die Direktive selbst ('{$IFNDEF COMPILER6_UP}'), ohne den Rest
      // der Zeile.
      W := Texts[i];
      if Pos('}', W) > 0 then
        W := Copy(W, 1, Pos('}', W));
      if InElse[i] then
        W := W + ' {$ELSE}';
      Exit(_(R_OLD_BRANCH, [W, Lines[i]]));
    end;
end;

{ ---- Aliasse und Units neben der Datei (rwE31, Fix-Runde 3) ---- }

const
  // Deckel des Plattenblicks je Frage (Hauptthread, Menueaufbau): so viele
  // Units der uses-Klauseln, so viele Bytes je Unit und insgesamt.
  MAX_NEIGHBOUR_UNITS = 128;
  MAX_NEIGHBOUR_BYTES = 4 * 1024 * 1024;
  MAX_NEIGHBOUR_TOTAL = 32 * 1024 * 1024;
  // Bis so viele Stufen loest UniqueAliasBase auf (wie ResolvedTypeKind).
  MAX_ALIAS_STEPS = 3;

class function TRdxTypeProof.UniqueAliasBase(AMap: TRdxCodeMap;
  const ATypeName: string): string;
var
  Kinds : TArray<string>;
  i, k  : Integer;
begin
  Result := '';
  Kinds := DeclaredTypeKinds(AMap, ATypeName, False);
  if Length(Kinds) = 0 then
    Exit;
  Result := LowerCase(ATypeName);
  for i := 1 to MAX_ALIAS_STEPS do
  begin
    if i > 1 then
    begin
      Kinds := DeclaredTypeKinds(AMap, Result, False);
      if Length(Kinds) = 0 then
        Exit;   // die Kette verlaesst die Datei: deren Name
    end;
    for k := 1 to High(Kinds) do
      if Kinds[k] <> Kinds[0] then
        Exit('');   // Zweige mit verschiedenen Typen
    Result := Kinds[0];
    if (Result = '') or not IsIdentStart(Result[1]) or IsKeyword(Result)
       or InList(Result, TYPE_KIND_WORDS) then
      Exit;
  end;
end;

// Der String hinter 'in' (ATok) einer uses-Klausel ('Main in ''Main.pas''')
// ohne Quotes; '' ohne.
function InPathAfter(AMap: TRdxCodeMap; const ATok: TRdxToken): string;
var
  L    : string;
  c, e : Integer;
begin
  Result := '';
  L := AMap.Raw(ATok.Line);
  c := SkipBlanks(L, ATok.EndCol);
  if (c > Length(L)) or (L[c] <> '''') then
    Exit;
  e := PosEx('''', L, c + 1);
  if e > c then
    Result := Copy(L, c + 1, e - c - 1);
end;

// Haengt die Datei der Unit AName (bzw. ihren 'in'-Pfad AInPath) an AFiles,
// wenn sie neben der Datei liegt (Verzeichnis ADir) und keine schon
// genannte oder die Datei selbst (AUnitFile) ist.
procedure AddNeighbour(var AFiles: TArray<string>; const ADir, AUnitFile,
  AName, AInPath: string);
var
  P : string;
  i : Integer;
begin
  if AInPath <> '' then
  begin
    if ExtractFileDrive(AInPath) <> '' then
      P := AInPath
    else
      P := ExpandFileName(ADir + AInPath);
  end
  else
  begin
    P := ADir + AName + '.pas';
    if not FileExists(P) then
      P := ADir + AName + '.pp';
  end;
  if IsNetworkPath(P) or not FileExists(P) or SameText(P, AUnitFile) then
    Exit;
  for i := 0 to High(AFiles) do
    if SameText(AFiles[i], P) then
      Exit;
  SetLength(AFiles, Length(AFiles) + 1);
  AFiles[High(AFiles)] := P;
end;

// Die Dateien der Units aus den uses-Klauseln von AMap (in deren
// Reihenfolge: interface vor implementation), die neben AUnitFile liegen;
// leer fuer eine Datei ohne Verzeichnis oder im Netz.
function NeighbourFiles(AMap: TRdxCodeMap;
  const AUnitFile: string): TArray<string>;
var
  T, N           : TRdxToken;
  Dir            : string;
  Name, InPath   : string;
begin
  Result := nil;
  Dir := ExtractFilePath(AUnitFile);
  if (Dir = '') or IsNetworkPath(Dir) then
    Exit;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while (T.Low <> '') and (Length(Result) < MAX_NEIGHBOUR_UNITS) do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      Name := '';
      InPath := '';
      N := After(AMap, T);
      while N.Low <> '' do
      begin
        if (N.Low = ',') or (N.Low = ';') then
        begin
          if Name <> '' then
            AddNeighbour(Result, Dir, AUnitFile, Name, InPath);
          Name := '';
          InPath := '';
          if N.Low = ';' then
            Break;
        end
        else if N.Low = 'in' then
          InPath := InPathAfter(AMap, N)
        else if InPath = '' then
          Name := Name + TokText(AMap, N);
        N := After(AMap, N);
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
end;

// Der Text der Datei APath nach ALines, wenn er ANameLow (klein, irgendwo)
// enthaelt - unter den Deckeln (ABytes zaehlt ueber alle Dateien einer
// Frage). Die Bytes als ANSI: die Namen sind ASCII. False, wenn die Datei
// den Namen nicht enthaelt oder sich nicht lesen laesst.
function ReadNeighbour(const APath, ANameLow: string; var ABytes: Int64;
  ALines: TStringList): Boolean;
var
  FS    : TFileStream;
  Bytes : TBytes;
  Text  : string;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if (FS.Size > MAX_NEIGHBOUR_BYTES)
         or (ABytes + FS.Size > MAX_NEIGHBOUR_TOTAL) then
        Exit;
      Inc(ABytes, FS.Size);
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        SetLength(Bytes, FS.Read(Bytes[0], Length(Bytes)));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  Text := TEncoding.ANSI.GetString(Bytes);
  if Pos(ANameLow, LowerCase(Text)) = 0 then
    Exit;
  ALines.Text := Text;
  Result := True;
end;

// Die Code-Sicht des interface-Teils von ALines (bis vor das erste
// 'implementation'); ALines wird dafuer gekuerzt. Der Aufrufer gibt die
// Map frei.
function InterfaceMap(ALines: TStringList): TRdxCodeMap;
var
  T    : TRdxToken;
  Cut  : Integer;
begin
  Cut := 0;
  Result := TRdxCodeMap.Create(ALines);
  T := NextTokenOnLineWith(Result, Default(TRdxToken), 'implementation');
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, Before(Result, T)) then
    begin
      Cut := T.Line;
      Break;
    end;
    T := NextTokenOnLineWith(Result, T, 'implementation');
  end;
  if Cut = 0 then
    Exit;
  Result.Free;
  while ALines.Count >= Cut do
    ALines.Delete(ALines.Count - 1);
  Result := TRdxCodeMap.Create(ALines);
end;

// Nennt die Code-Sicht AMap den Namen ANameLow als Token?
function NamesToken(AMap: TRdxCodeMap; const ANameLow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ANameLow);
  while T.Low <> '' do
  begin
    if T.Low = ANameLow then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, ANameLow);
  end;
end;

class function TRdxTypeProof.NeighbourVarType(AMap: TRdxCodeMap;
  const AUnitFile, AName: string): string;
var
  Files   : TArray<string>;
  NameLow : string;
  Bytes   : Int64;
  i       : Integer;
  SL      : TStringList;
  M       : TRdxCodeMap;
  Ty      : string;
begin
  Result := '';
  NameLow := LowerCase(Trim(AName));
  if (NameLow = '') or (AUnitFile = '') then
    Exit;
  Files := NeighbourFiles(AMap, AUnitFile);
  Bytes := 0;
  for i := 0 to High(Files) do
  begin
    SL := TStringList.Create;
    try
      if not ReadNeighbour(Files[i], NameLow, Bytes, SL) then
        Continue;
      M := InterfaceMap(SL);
      try
        Ty := UnitVarType(M, NameLow);
        // Die letzte Unit, die den Namen nennt, gilt; nennt sie ihn anders
        // als als Variable, ist nichts bewiesen.
        if Ty <> '' then
          Result := Ty
        else if NamesToken(M, NameLow) then
          Result := '';
      finally
        M.Free;
      end;
    finally
      SL.Free;
    end;
  end;
end;

class function TRdxTypeProof.NeighbourTypeBase(AMap: TRdxCodeMap;
  const AUnitFile, ATypeName: string): string;
var
  Files   : TArray<string>;
  TypeLow : string;
  Bytes   : Int64;
  i       : Integer;
  SL      : TStringList;
  M       : TRdxCodeMap;
begin
  Result := '';
  TypeLow := LowerCase(Trim(ATypeName));
  if (TypeLow = '') or (AUnitFile = '') then
    Exit;
  Files := NeighbourFiles(AMap, AUnitFile);
  Bytes := 0;
  for i := 0 to High(Files) do
  begin
    SL := TStringList.Create;
    try
      if not ReadNeighbour(Files[i], TypeLow, Bytes, SL) then
        Continue;
      M := InterfaceMap(SL);
      try
        // Nur eine Deklaration verdeckt - eine Unit, die den Typ nur
        // benutzt (Parameter, Felder), nicht.
        if Length(DeclaredTypeKinds(M, TypeLow, True)) > 0 then
          Result := UniqueAliasBase(M, TypeLow);
      finally
        M.Free;
      end;
    finally
      SL.Free;
    end;
  end;
end;

end.
