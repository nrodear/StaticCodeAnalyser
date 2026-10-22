unit uRdxFixRunner;

// reDelphix - die Ruempfe der einfachen Hilfen, deren Planer den
// Quellstellen-Dienst brauchen (TRdxFixRunner: Typen, with-Bloecke,
// uses), und die Bausteine der Tabelle uRdxFixTable (MapFix, CastFreeFix,
// EmptyRaiseFix, AppendUses, CondAssignReason, SelfAssignReason). Bis
// Charge B2S-b standen sie in uRdxRecipeRunner neben dem Rezept-Laeufer
// von SCA044, SCA003 und uses, der sie nicht braucht; uRdxRecipeRunner
// band dafuer die Planer-Units ein - uRdxFlowFixes sogar im interface,
// nur fuer CondAssignReason (Code-Review reDelphix, Review R6-12). Der
// Inhalt ist unveraendert umgezogen (Namen, Signaturen, Gruende und
// Hinweise); aufgerufen wird er nur von uRdxFixTable.
//
// OHNE ToolsAPI, in reDelphix.Test uebersetzbar; nicht im FPC-Pruefstand
// - wie uRdxRecipeRunner und uRdxFixTable braucht die Unit den
// Quellstellen-Dienst des Cores (TSourcePlaces), TFindingKind und
// uUnusedUses. Den Ergebnistyp TRdxFixOutcome (samt TRdxEdit), R_NO_FILE
// und die uses-Fragen (PlanUses, ClausesOf, UsesKeywordLine,
// UsesDirectiveLine, SourceLooksFpcAware) liefert uRdxRecipeRunner; die
// Version des Quellstellen-Vertrags prueft die Unit selbst (s.
// implementation).

interface

uses
  System.Classes,    // TStrings
  uEngineApi,        // TSourcePlaces
  uSCAConsts,        // TFindingKind (OperandFix, BlockFix)
  uRdxCodeMap,       // TRdxCodeMap (TRdxMapPlanner, CondAssignReason ...)
  uRdxFlowFixes,     // TRdxFlowPlan (CondAssignReason)
  // TRdxFixOutcome; TRdxEdit (TRdxMapPlanner) als Alias auf
  // uRdxBufferMath.TRdxEdit - derselbe Typ, darum steht uRdxBufferMath
  // nicht in den uses (Gegenpruefung V-B2S-4).
  uRdxRecipeRunner;

type
  // Editorhilfen seit Stufe 2a: die Ruempfe der Hilfen, deren Planer den
  // Quellstellen-Dienst brauchen (Typen, with-Bloecke, uses) - die Planer
  // selbst stehen in uRdxSimpleFixes, uRdxStructFixes, uRdxLineFixes,
  // uRdxRaiseFixes, uRdxFlowFixes und weiteren Planer-Units. Den Einstieg
  // (Handles, FixFor, AlternativeFixFor), Hinweise und Menuetexte fuehrt
  // seit Charge R8 die Tabelle uRdxFixTable: eine weitere Regel ist dort
  // eine Zeile und - wo sie den Dienst braucht - hier eine Routine, kein
  // Zweig in einem Verteiler. ALines ist immer derselbe Text, aus dem
  // APlaces geoeffnet wurde.
  TRdxFixRunner = class
  public
    // SCA075: 'class(TObject)' -> 'class' an der Spalte aus der Meldung
    // (nur die Zeilen, kein Parser noetig).
    class function ExplicitTObjectFix(ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA085: 'X.Free;' (ALine) + 'X := nil;' -> 'FreeAndNil(X);'. X muss
    // in dieser Unit deklariert sein (DeclaredTypeOf): eine Property
    // uebersetzt als Argument nicht, ein geerbtes Feld ist nicht pruefbar -
    // beides keine Hilfe. Dazu dieselbe Typ-Sperre wie SCA139 (seit Review
    // FB, R2-01/R3-01): kein record/object/interface/Zeiger dieser Unit,
    // keine eigene Methode Free in der Unit, kein fremder Zeigertyp nach
    // Namenskonvention. Fehlt SysUtils, kommt die uses-Einfuegung mit.
    class function FreeAndNilFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA126: der Fund traegt keine Spalte - umgeschrieben wird die EINE
    // Anweisung, die auf ALine beginnt und einen nil-Vergleich traegt
    // (NodesAt, Knotentext wie uNilComparison), und zwar mit ALLEN ihren
    // Vergleichen. Zwei solche Anweisungen heissen mehrdeutig. Jeder
    // Operand geht durch TRdxNilFix.NilOperandRisk.
    class function NilComparisonFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer): TRdxFixOutcome; static;

    // SCA074: 'Assert(c)' -> 'Assert(c, ''c'')' an der Spalte aus der
    // Meldung. Keine Hilfe, wenn die Unit selbst eine Routine Assert
    // deklariert oder ein with den Namen an ein Member binden kann.
    class function AssertMessageFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;

    // SCA087: die leere Sichtbarkeitszeile ALine loeschen (nur die Zeilen).
    class function EmptySectionFix(ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA139: 'X.Free' -> 'FreeAndNil(X)', X aus der Meldung. Dieselbe
    // Variablen- und Typ-Pruefung wie SCA085 (kein record/object/interface/
    // Zeiger dieser Unit, keine eigene Methode Free in der Unit - 'X.Free'
    // riefe sie, FreeAndNil nicht -, kein fremder Zeigertyp nach
    // Namenskonvention); dazu kein const-/constref-Parameter (Review FB,
    // R2-03: FPC und Delphi bis 10.3 uebersetzen das nicht, ab 10.4 wird
    // nur die lokale Kopie nil). Fehlt SysUtils, kommt die uses-
    // Einfuegung mit.
    class function FreeWithoutNilFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA066: 'Foo()' -> 'Foo' (TRdxExprFixes.EmptyArgs). Dazu die Typen:
    // ein blosser Name ist keine Variable (Prozedurvariable, CallReason),
    // links von ':=' kein prozeduraler oder unbekannter Typ; kein with-
    // Block. Nicht in einer Datei mit FPC-Weiche oder FPC-Modus: in objfpc
    // ruft erst 'Foo()' eine Prozedurvariable auf.
    class function EmptyArgsFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;

    // SCA072 und SCA084: der Planer liefert die Ersetzung und den Namen X,
    // hier die Pruefung von X - kein with; SCA072: X als Boolean deklariert
    // (bei Variant und LongBool ist 'X = True' nicht dasselbe wie X);
    // SCA084: X als Klasse, Interface oder Zeiger bewiesen (ein Funktionstyp
    // riefe 'X <> nil' auf), keine eigene Routine Assigned.
    class function OperandFix(AKind: TFindingKind; APlaces: TSourcePlaces;
      ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA007: den uses-Eintrag AUnit (die Meldung) auf ALine loeschen
    // (TRdxStructFixes.RemoveUsesEntry). Gesperrt bei Direktiven in einer
    // uses-Klausel. Aendert evtl. das Verhalten: der initialization-
    // Abschnitt der Unit laeuft nicht mehr (Kennzeichnung in uRdxFixTable).
    class function UnusedUsesFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUnit: string): TRdxFixOutcome; static;

    // SCA168: ein leeres else vor das end des case auf ALine
    // (TRdxStructFixes.CaseElse) - bedeutungsgleich.
    class function CaseElseFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer): TRdxFixOutcome; static;
    // SCA168, zweiter Eintrag: else mit RAISE_UNHANDLED - aendert das
    // Verhalten; SysUtils kommt bei Bedarf mit; nicht in Dateien mit
    // FPC-Weiche oder FPC-Modus (FPC kennt EProgrammerError nicht).
    class function CaseRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA101 und SCA099: die Anweisung hinter then/else/do in begin..end
    // (TRdxStructFixes.WrapInBlock) - bedeutungsgleich, nur die Zeilen.
    // SCA101: das Schluesselwort an der Spalte aus der Meldung; SCA099:
    // das else hinter dem 'end else' auf ALine.
    class function BlockFix(AKind: TFindingKind; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;
  end;

  // Bausteine der Tabelle (uRdxFixTable, Charge R8). Die Planer der
  // Zeilen- und Deklarations-Hilfen haben alle diese Form
  // (TRdxLineFixes.DoubleSemicolon, TRdxDeclFixes.DocSkeleton ...); MapFix
  // oeffnet ihnen die Code-Sicht.
  TRdxMapPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
  // FlowFix (SCA098/SCA080/SCA047) mit TRdxFlowPlanner/TRdxFlowReason steht
  // seit Charge H5c als Plan-Form im Geruest der Tabelle (uRdxFixTable,
  // TRdxFixFrame; Gegen-Review H5, Major 2) - hier brauchte es niemand.

// SCA075, SCA087 und die Zeilen-Hilfen SCA082/SCA071/SCA088, SCA020/SCA120/
// SCA122, SCA117/SCA197/SCA149: APlan arbeitet nur auf den Zeilen, ohne
// Parser - Spalte bzw. Abschnitt stehen in der Meldung, die Code-Sicht
// kennt den Kommentar-Zustand der Zeilen davor. Ohne ALines R_NO_FILE; die
// Ersetzung nach Edits[0], sonst der Grund.
function MapFix(ALines: TStrings; ALine: Integer; const AMessage: string;
  APlan: TRdxMapPlanner): TRdxFixOutcome;
// SCA123: 'TFoo(X).Free' -> 'X.Free' - Bedingungen am Rumpf.
function CastFreeFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
// SCA020, zweiter Eintrag: raise ENotImplemented im leeren Rumpf.
function EmptyRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome;
// SCA098: X und (in der Gegenrichtung) die Bedingung als Boolean bewiesen?
// '' oder der Grund.
function CondAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxFlowPlan): string;
// SCA047: ist das Ziel ein Speicherplatz? '' oder der Grund.
function SelfAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const ATarget: string): string;
// Fehlt die Unit AShortName in uses (AUsesNames), haengt die Einfuegung
// (PlanUses, Name nach der Schreibweise der Datei) an AOutcome.Edits und
// ' + uses <Name>' an den Hinweis. False (Edits geleert, Grund gesetzt),
// wenn sie nicht planbar ist. Bis Charge H5 nur fuer SysUtils
// (AppendSysUtils: FreeAndNil, raise ...); seitdem auch fuer Variants
// (SCA196: VarClear(Result)).
function AppendUses(APlaces: TSourcePlaces; const AUsesNames: TArray<string>;
  const AShortName, AQualifiedName: string;
  var AOutcome: TRdxFixOutcome): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,   // IndexText (UnitStillUsed)
  uRefactorInfo,     // TRefactorSpan (FindUsesEntry)
  uRdxRecipes,       // TRdxRecipes (IsPlainIdent, HasUnit)
  uRdxSimpleFixes,   // Planer der einfachen Hilfen (reine Textlogik)
  uRdxTypeProof,     // Typbeweis auf dem Text (bis Folgewelle A4 in uRdxSimpleFixes)
  uRdxStructFixes,   // Planer SCA007/SCA168 (uses-Eintrag, case-else)
  uRdxLineFixes,     // Planer SCA123 (CastFreeFix)
  uRdxRaiseFixes,    // Planer SCA020 mit raise (EmptyRaiseFix)
  uRdxRtlTypes,      // IsRtlClassOrInterface: Klasse 'PDFDocument' ist kein Zeiger
  uRdxText,          // MsgMovedSuffix, MsgStaleSuffix (gemeinsame Texte, C1)
  uUnusedUses,       // KnownIdents: SCA007-Fund am Puffer nachpruefen
  uSourcePlaces;     // SOURCE_PLACES_VERSION (Vertragspruefung unten)

// Diese Ruempfe sind gegen Version 1 des Quellstellen-Vertrags geschrieben
// (uSourcePlaces, Abschnitt VERTRAGSVERSION): ihre Typ- und with-Beweise
// fragen DeclaredTypeOf, InWithBlock und NodesAt (SCA085/SCA139, SCA126,
// SCA066, SCA072/SCA084, SCA074, SCA123, SCA098, SCA047) - seit Charge
// B2S-b stehen die meisten Typ- und with-Fragen an den Vertrag hier.
// Steigt die Version, bricht der Bau hier ab und nennt diese Unit;
// uRdxRecipeRunner prueft dasselbe fuer den Rezept-Laeufer (bis zur
// Gegenpruefung V-B2S-5 stand die Pruefung nur dort und nannte nur ihn).
// Eine zur Laufzeit getauschte BPL erkennt das nicht - das leistet die
// Paketbindung.
{$IF SOURCE_PLACES_VERSION <> 1}
  {$MESSAGE ERROR 'reDelphix: SOURCE_PLACES_VERSION hat sich geaendert - Vertrag in uSourcePlaces (VERTRAGSVERSION) pruefen, uRdxFixRunner anpassen'}
{$IFEND}

const
  R_NIL_TYPE_UNKNOWN = 'Typ von %s unbekannt - bei einem Funktions- oder '
    + 'Methodenzeiger ruft ''= nil'' ihn auf, Assigned() nicht';
  R_NIL_IN_WITH = 'with-Anweisung - ein Operand koennte ein Member des '
    + 'with-Ausdrucks sein';
  // Der Unterschied, den der Benutzer kennen sollte (SCA085, SCA139):
  // FreeAndNil setzt ERST nil, dann laeuft der Destruktor.
  R_FREENIL_HINT = 'FreeAndNil setzt %s auf nil, bevor der Destruktor laeuft';
  // Typ-Sperren von SCA085/SCA139 (FreeTypeReason, Review FB R2-01/R3-01)
  // und der const-Parameter von SCA139 (ConstParamReason, R2-03).
  R_NOT_AN_OBJECT = '%s ist kein Objekt (%s: record, object, interface, '
    + 'Zeiger oder eigener Typ dieser Unit) - Free ist eine eigene Methode, '
    + 'FreeAndNil nimmt nur ein TObject';
  // Was DeclaredTypeKind fuer einen ausformulierten Typ liefert - kein
  // Alias auf einen Typ einer anderen Unit (ForeignTypeName).
  OWN_TYPE_WORDS: array[0..12] of string = ('class', 'record', 'object',
    'interface', 'dispinterface', 'type', 'procedure', 'function',
    'reference', 'set', 'array', 'string', 'file');
  R_OWN_FREE = 'die Unit deklariert eine eigene Methode Free - FreeAndNil '
    + 'riefe sie nicht auf';
  R_POINTER_NAME = '%s hat den Typ %s - nach Delphi-Konvention ein Zeiger aus '
    + 'einer anderen Unit (Free ist dann die des Ziels, FreeAndNil nimmt nur '
    + 'ein TObject)';
  R_CONST_PARAM = '%s ist ein const-Parameter - FreeAndNil erreicht die '
    + 'Variable des Aufrufers nicht (FPC: Fehler, Delphi bis 10.3: E2197)';
  R_WITH_MEMBER  = 'with-Anweisung in der Routine - %s koennte ein Member sein';
  R_NO_HELP      = 'keine Hilfe an dieser Stelle';
  // Hinweise, die der Rumpf selbst setzt - vor dem ' + uses ...' bzw. mit
  // dem Namen; die festen Hinweise je Art fuehrt uRdxFixTable (Charge R8).
  R_CASE_RAISE_HINT = 'unbehandelte Werte loesen EProgrammerError aus';
  R_CAST_HINT   = '%s ist schon als %s deklariert - der Cast aendert nichts';
  R_EMPTY_RAISE_HINT = 'ein Aufruf loest ENotImplemented aus statt nichts zu '
    + 'tun';
  R_PROC_TYPE    = '%s hat einen Prozedurtyp - "%s <> nil" ruft ihn auf, '
    + 'Assigned() nicht';

{ TRdxFixRunner }

function MapFix(ALines: TStrings; ALine: Integer; const AMessage: string;
  APlan: TRdxMapPlanner): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    Result.Enabled := APlan(Map, ALine, AMessage, Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.ExplicitTObjectFix(ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
begin
  Result := MapFix(ALines, ALine, AMessage, TRdxSimpleFixes.ExplicitTObject);
end;

// SCA085: ist AName an ALine sicher eine Variable? FreeAndNil braucht eine;
// eine Property uebersetzt als Argument nicht (vor 10.4) bzw. umgeht ihren
// Setter (const [ref]). Gesperrt: irgendwo in der Unit als Property
// deklariert, ein 'with' davor in der Routine oder ein with-Block um die
// Zeile (auch 'with X do Y.Free;' auf EINER Zeile - InWithBlock; dort
// bindet der Name evtl. an ein Member), weder deklariert (DeclaredTypeOf:
// Parameter, lokal, Result, Feld oder Global der Unit) noch Inline-
// Variable ohne Typ. '' oder der Grund.
function VariableCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AName: string): string;
begin
  Result := '';
  if TRdxTypeProof.DeclaresProperty(AMap, AName) then
    Exit(Format('%s ist in dieser Unit als Property deklariert - FreeAndNil '
      + 'braucht eine Variable', [AName]));
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AName]));
  if (APlaces.DeclaredTypeOf(ALine, AName) = '')
     and not TRdxSimpleFixes.DeclaresInlineVar(AMap, ALine, AName) then
    Result := Format('%s ist hier nicht als Variable bekannt (Property oder '
      + 'Feld aus einer anderen Unit?)', [AName]);
end;

// Ist ATypeLow nach Delphi-Konvention ein Zeigertyp aus einer anderen
// Unit? 'P' und dahinter ein Grossbuchstabe, eine Ziffer oder '_' in einer
// Schreibweise des Quelltexts ('PEVP_PKEY', 'PSSL_CTX'; nicht 'Parser'),
// nicht in dieser Unit deklariert (dort entscheidet DeclaresNonClassType bzw.
// die Deklaration) und keine Klasse der Delphi-Quellen ('PDFDocument' aus
// iOSapi, uRdxRtlTypes). Korpus ab8 (Review FB, R3-01): 8 SCA085-Funde mit
// fremdem P-Typ - alle Zeiger aus mormot.lib.openssl11 auf ein object mit
// eigenem Free -, kein Klassentyp unter den Empfaengern von SCA085/SCA139.
// ASpelling: die gefundene Schreibweise.
function PointerNamedType(AMap: TRdxCodeMap; const ATypeLow: string;
  out ASpelling: string): Boolean;
var
  T : TRdxToken;
  S : string;
begin
  Result := False;
  ASpelling := '';
  if (Length(ATypeLow) < 2) or (ATypeLow[1] <> 'p')
     or (TRdxTypeProof.DeclaredTypeKind(AMap, ATypeLow) <> '')
     or IsRtlClassOrInterface(ATypeLow) then
    Exit;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if T.Low = ATypeLow then
    begin
      S := TokText(AMap, T);
      if (S[1] = 'P') and CharInSet(S[2], ['A'..'Z', '0'..'9', '_']) then
      begin
        ASpelling := S;
        Exit(True);
      end;
    end;
    T := After(AMap, T);
  end;
end;

// Der Name, unter dem der Typ ATypeLow aus einer anderen Unit kommt:
// ATypeLow selbst, wenn diese Unit ihn nicht deklariert; das Ende seiner
// Alias-Kette, wenn sie die Unit verlaesst ('PMyKey = PEVP_PKEY' ->
// 'pevp_pkey', TRdxTypeProof.ResolvedTypeKind; Nachpruefung FB - bis dahin
// galt ein solcher Alias als Typ dieser Unit und behielt die Hilfe); ''
// fuer einen Typ, den die Unit ausformuliert (class, record, '^' ...).
function ForeignTypeName(AMap: TRdxCodeMap; const ATypeLow: string): string;
var
  Kind : string;
begin
  Kind := TRdxTypeProof.ResolvedTypeKind(AMap, ATypeLow);
  if Kind = '' then
    Result := ATypeLow
  else if TRdxRecipes.IsPlainIdent(Kind) and not InList(Kind, OWN_TYPE_WORDS)
     and (TRdxTypeProof.DeclaredTypeKind(AMap, Kind) = '') then
    Result := Kind
  else
    Result := '';
end;

// SCA085/SCA139: ruft 'X.Free' sicher TObject.Free? FreeAndNil(X) uebergeht
// eine eigene Methode Free und nimmt X als TObject. Gesperrt (ATypeLow = der
// deklarierte Typ von X):
//   * ein record/object/interface, Zeiger ('PFoo = ^TFoo') oder eigener Typ
//     ('PFoo = type ^TFoo') dieser Unit, auch ueber Aliasse der Unit
//     (DeclaresNonClassType) - 'X.Free' ist dort eine eigene Methode, beim
//     Zeiger die des Ziels;
//   * eine Routine Free irgendwo in der Unit (eine Klasse, die zurueckgibt
//     statt freizugeben: ein Pool mit 'procedure Free; reintroduce') -
//     ohne Parser auch dann, wenn sie einer anderen Klasse gehoert (Korpus
//     ab8: 1 SCA085-Angebot weniger, Alcinoe dwsUtils);
//   * ein Typ einer anderen Unit, der nach Konvention ein Zeiger ist
//     (PointerNamedType: 'PEVP_PKEY'), auch hinter einem Alias der Unit
//     (ForeignTypeName: 'PMyKey = PEVP_PKEY').
// Bis Review FB (R2-01/R3-01) pruefte das nur SCA139; SCA085 bot
// 'FreeAndNil(result)' fuer 'result: PX509_CRL' an - Delphi 12: E2010, FPC
// und Delphi bis 10.3: TObject.Free auf einer OpenSSL-Struktur. Typen
// anderer Units ohne Konventionsnamen sieht das nicht; ein Record dort
// faellt in Delphi ab 10.4 als Fehler E2010 auf. '' oder der Grund.
function FreeTypeReason(AMap: TRdxCodeMap;
  const AName, ATypeLow: string): string;
var
  Spelling : string;
begin
  Result := '';
  if TRdxTypeProof.DeclaresNonClassType(AMap, ATypeLow) then
    Result := Format(R_NOT_AN_OBJECT, [AName, ATypeLow])
  else if TRdxTypeProof.DeclaresRoutine(AMap, 'Free') then
    Result := R_OWN_FREE
  else if PointerNamedType(AMap, ForeignTypeName(AMap, ATypeLow),
       Spelling) then
    Result := Format(R_POINTER_NAME, [AName, Spelling]);
end;

function FreeMethodReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AName: string): string;
begin
  Result := FreeTypeReason(AMap, AName, APlaces.DeclaredTypeOf(ALine, AName));
end;

function AppendUses(APlaces: TSourcePlaces; const AUsesNames: TArray<string>;
  const AShortName, AQualifiedName: string;
  var AOutcome: TRdxFixOutcome): Boolean;
var
  Plan : TRdxUsesPlan;
begin
  Result := True;
  if TRdxRecipes.HasUnit(AUsesNames, AShortName) then Exit;
  Plan := TRdxRecipeRunner.PlanUses(APlaces, AShortName, AQualifiedName);
  if Plan.Needed and (Plan.Reason <> '') then
  begin
    AOutcome.Reason := AQualifiedName + ' fehlt in uses: ' + Plan.Reason;
    AOutcome.Edits := nil;
    Exit(False);
  end;
  if Plan.Needed then
  begin
    SetLength(AOutcome.Edits, Length(AOutcome.Edits) + 1);
    AOutcome.Edits[High(AOutcome.Edits)] := Plan.Edit;
    AOutcome.Hint := AOutcome.Hint + ' + uses ' + Plan.Name;
  end;
end;

// FreeAndNil steht in SysUtils: fehlt die Unit in uses, haengt die
// Einfuegung an AOutcome.Edits und an den Hinweis (AppendUses). False
// (Edits geleert, Grund gesetzt), wenn die Einfuegung nicht planbar ist.
function AppendSysUtils(APlaces: TSourcePlaces;
  const AUsesNames: TArray<string>; var AOutcome: TRdxFixOutcome): Boolean;
begin
  Result := AppendUses(APlaces, AUsesNames, 'SysUtils', 'System.SysUtils',
    AOutcome);
end;

class function TRdxFixRunner.FreeAndNilFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if not TRdxSimpleFixes.FreeAndNilFix(Map, ALine, Result.Edits,
         Result.Name, Result.Reason) then
      Exit;
    Result.Reason := VariableCheck(APlaces, Map, ALine, Result.Name);
    // Dieselbe Typ-Sperre wie SCA139 (Review FB, R2-01/R3-01).
    if Result.Reason = '' then
      Result.Reason := FreeMethodReason(APlaces, Map, ALine, Result.Name);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := Format(R_FREENIL_HINT, [Result.Name]);
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

class function TRdxFixRunner.AssertMessageFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    // Eine eigene Routine Assert (Methode oder global) bindet vor
    // System.Assert - ihre Parameter kennt hier niemand.
    if TRdxTypeProof.DeclaresRoutine(Map, 'Assert') then
      Result.Reason := 'die Unit deklariert eine eigene Routine Assert'
    else if TRdxSimpleFixes.WithBefore(Map, ALine)
            or APlaces.InWithBlock(ALine) then
      Result.Reason := 'with-Anweisung in der Routine - Assert koennte ein '
        + 'Member sein'
    else
      Result.Enabled := TRdxSimpleFixes.AssertMessage(Map, ALine, AMessage,
        Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.EmptySectionFix(ALines: TStrings; ALine: Integer;
  const AMessage: string): TRdxFixOutcome;
begin
  Result := MapFix(ALines, ALine, AMessage, TRdxSimpleFixes.EmptySection);
end;

// X aus der SCA139-Meldung 'X.Free without subsequent X := nil - ...';
// '' ohne diese Form.
function FreeReceiverOf(const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos('.Free without', AMessage);
  if P > 1 then
    Result := Trim(Copy(AMessage, 1, P - 1));
end;

// Das Kopfwort (procedure, function, constructor, destructor, operator)
// einer Routine, deren Kopf auf ALine beginnt ('class' davor erlaubt, auch
// Attribute auf derselben Zeile: '[Weak] procedure ..' - Nachpruefung FB);
// Low = '' ohne. AFirstCol: die Spalte des ersten Tokens der Zeile.
function RoutineKeywordOn(AMap: TRdxCodeMap; ALine: Integer;
  out AFirstCol: Integer): TRdxToken;
begin
  Result := NextToken(AMap, ALine, 1);
  AFirstCol := Result.Col;
  while (Result.Low = '[') and (Result.Line = ALine) do
    Result := AfterClose(AMap, Result);
  if Result.Low = 'class' then
    Result := After(AMap, Result);
  if (Result.Line <> ALine) or not InList(Result.Low, ['procedure', 'function',
       'constructor', 'destructor', 'operator']) then
    Result := Default(TRdxToken);
end;

type
  // Zustand des Laufs durch eine Parameterliste (ConstNameStep): eckige
  // Klammern (Attribut '[ref]', Mengen-Vorgabe), der Modifizierer der
  // Gruppe und ob der Lauf hinter ihrem ':' steht.
  TRdxParamWalk = record
    Square   : Integer;
    Modifier : string;
    InType   : Boolean;
  end;

// Ein Token auf Klammertiefe 1 einer Parameterliste: True, wenn es ein Name
// einer const- bzw. constref-Gruppe ist. Gruppen trennt ';', vor dem ':'
// stehen Modifizierer, Attribute und die Namen.
function ConstNameStep(var W: TRdxParamWalk; const T: TRdxToken): Boolean;
begin
  Result := False;
  if T.Low = '[' then
    Inc(W.Square)
  else if T.Low = ']' then
    Dec(W.Square)
  else if W.Square > 0 then
    Exit
  else if T.Low = ';' then
  begin
    W.Modifier := '';
    W.InType := False;
  end
  else if T.Low = ':' then
    W.InType := True
  else if W.InType then
    Exit
  else if InList(T.Low, ['const', 'constref', 'var', 'out']) then
    W.Modifier := T.Low
  else
    Result := T.IsWord and ((W.Modifier = 'const') or (W.Modifier = 'constref'));
end;

// Nennt der Kopf ab AKeyword ANameLow (klein) als const- bzw. constref-
// Parameter? Der Name der Routine darf qualifiziert und generisch sein
// ('procedure TFoo.Bar<T>(const A: T)') - TRdxDeclFixes.ReadSignature
// liest nur Deklarationen ohne Punkt.
function HeadHasConstParam(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  const ANameLow: string): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
  W     : TRdxParamWalk;
begin
  Result := False;
  T := After(AMap, AKeyword);
  while T.IsWord do
  begin
    T := After(AMap, T);
    if T.Low = '<' then
      T := AfterClose(AMap, T);
    if T.Low <> '.' then
      Break;
    T := After(AMap, T);
  end;
  if T.Low <> '(' then Exit;
  W := Default(TRdxParamWalk);
  Depth := 0;
  repeat
    if T.Low = '(' then
      Inc(Depth)
    else if T.Low = ')' then
      Dec(Depth)
    else if (Depth = 1) and ConstNameStep(W, T) and (T.Low = ANameLow) then
      Exit(True);
    T := After(AMap, T);
  until (Depth = 0) or (T.Low = '');
end;

// SCA139: ist AName ein const- bzw. constref-Parameter einer Routine um
// ALine? FreeAndNil(X) braucht eine Variable: FPC meldet "Can't assign
// values to const variable", Delphi bis 10.3 (var-Parameter) E2197; ab
// 10.4 uebersetzt es (const [ref]), setzt aber nur die lokale Kopie auf nil
// - beim Aufrufer bleibt der Zeiger haengen, den SCA139 meint (Review FB,
// R2-03; Korpus ab8: 15 von 363 SCA139-Funden, 2 davon in FPC-Dateien von
// doublecmd). Gelesen werden die Koepfe ueber ALine bis zum ersten in
// Spalte 1 (Konvention: Implementierungen stehen am Zeilenanfang) bzw. bis
// 'implementation' - eine lokale Routine sieht die Parameter der
// aeusseren; ein gleichnamiger const-Parameter einer lokalen Routine davor
// sperrt mit (vorsichtig). Eine anonyme Methode im Ausdruck sieht das
// nicht. '' oder der Grund.
function ConstParamReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string): string;
var
  Li, FirstCol : Integer;
  Keyword      : TRdxToken;
begin
  Result := '';
  for Li := ALine downto 1 do
  begin
    Keyword := RoutineKeywordOn(AMap, Li, FirstCol);
    if Keyword.Low = '' then
    begin
      if NextToken(AMap, Li, 1).Low = 'implementation' then
        Exit;
      Continue;
    end;
    if HeadHasConstParam(AMap, Keyword, LowerCase(AName)) then
      Exit(Format(R_CONST_PARAM, [AName]));
    if FirstCol = 1 then
      Exit;
  end;
end;

class function TRdxFixRunner.FreeWithoutNilFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  // X wie in der Meldung - auch fuer Menuetext und Grund, wenn der Planer
  // ablehnt; die Ersetzung schreibt X so, wie es im Quelltext steht.
  Result.Name := FreeReceiverOf(AMessage);
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    if not TRdxSimpleFixes.FreeOnly(Map, ALine, Result.Name,
         Result.Edits[0], Result.Reason) then
    begin
      Result.Edits := nil;
      Exit;
    end;
    Result.Reason := VariableCheck(APlaces, Map, ALine, Result.Name);
    if Result.Reason = '' then
      Result.Reason := FreeMethodReason(APlaces, Map, ALine, Result.Name);
    if Result.Reason = '' then
      Result.Reason := ConstParamReason(Map, ALine, Result.Name);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := Format(R_FREENIL_HINT, [Result.Name]);
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

// SCA066: die Namen um den Aufruf (TRdxCallEdit). Ein blosser Name mit
// deklariertem Typ ist eine Variable - mit () eine Prozedurvariable oder
// Methodenreferenz, die Delphi ohne () nicht ueberall aufruft. Links von
// ':=' entscheidet der Typ (Gegen-Review 2026-10-10, Korpus cnwizards:
// 'Proc := PrevNextProc()' mit prozeduralem Proc). Im with-Block kann ein
// Name an ein Member binden. '' oder der Grund.
function CallReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxCallEdit): string;
var
  TypeLow : string;
begin
  Result := '';
  if (APlan.Callee = '') and (APlan.Target = '') then Exit;
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [APlan.Callee + APlan.Target]));
  if (APlan.Callee <> '')
     and (APlaces.DeclaredTypeOf(ALine, APlan.Callee) <> '') then
    Exit(Format('%s ist eine Variable (Prozedurtyp) - erst () ruft sie '
      + 'sicher auf', [APlan.Callee]));
  if APlan.Target = '' then Exit;
  TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Target);
  if TypeLow = '' then
    Result := Format('Typ von %s unbekannt - ist er prozedural, liest Delphi '
      + 'den Namen ohne () als Zeiger', [APlan.Target])
  else if TRdxTypeProof.ProceduralType(AMap, TypeLow) then
    Result := Format('%s hat einen Prozedurtyp (%s) - ohne () liest Delphi den '
      + 'Namen als Zeiger', [APlan.Target, TypeLow]);
end;

class function TRdxFixRunner.EmptyArgsFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map  : TRdxCodeMap;
  Plan : TRdxCallEdit;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
    Result.Reason := R_NO_FILE
  else if TRdxRecipeRunner.SourceLooksFpcAware(APlaces) then
    Result.Reason := 'Datei mit FPC-Weiche oder FPC-Modus - in objfpc ruft '
      + 'erst Foo() eine Prozedurvariable auf';
  if Result.Reason <> '' then Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    if TRdxExprFixes.EmptyArgs(Map, ALine, AMessage, Plan, Result.Reason) then
      Result.Reason := CallReason(APlaces, Map, ALine, Plan)
    else if Result.Reason = '' then
      Result.Reason := R_NO_HELP;
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  SetLength(Result.Edits, 1);
  Result.Edits[0] := Plan.Edit;
  Result.Enabled := True;
end;

// SCA084: X muss als Klasse, Interface oder Zeiger BEWIESEN sein - ein
// Funktionstyp riefe 'X <> nil' auf, Assigned(X) nicht. Eine Zulassungs-
// liste (Gegen-Review 2026-10-10: die Ausschlussliste liess Aliasse,
// generische und qualifizierte Funktionstypen durch); im Realwelt-Korpus
// meldet SCA084 nur vier Stellen. Derselbe Beweis wie SCA126
// (TRdxNilFix.NilOperandReason): PointerLikeType kennt seit E27 (Charge
// R10) auch die Klassen und Interfaces der Delphi-Quellen (uRdxRtlTypes) -
// GEWOLLT auch hier: 'Assigned(L) and (L <> nil)' mit 'L: TStringList'
// ist derselbe Fall wie bei SCA126, die Gefahr (ein Funktionstyp aus einer
// anderen Unit) dieselbe, also auch der Beweis. '' oder der Grund.
function AssignedNilReason(AMap: TRdxCodeMap;
  const AName, ATypeLow: string): string;
begin
  if TRdxTypeProof.DeclaresRoutine(AMap, 'Assigned') then
    Exit('die Unit deklariert eine eigene Routine Assigned');
  if ATypeLow = '' then
    Exit(Format('Typ von %s unbekannt - bei einem Funktionstyp ruft '
      + '"%s <> nil" ihn auf, Assigned() nicht', [AName, AName]));
  Result := TRdxNilFix.NilOperandRisk(AName, ATypeLow);
  if Result <> '' then Exit;
  if TRdxTypeProof.ProceduralType(AMap, ATypeLow) then
    Exit(Format(R_PROC_TYPE, [AName, AName]));
  if not TRdxTypeProof.PointerLikeType(AMap, ATypeLow) then
    Result := Format('%s: Typ %s ist in dieser Unit nicht als Klasse, '
      + 'Interface oder Zeiger bewiesen und keine Klasse der Delphi-Quellen '
      + '- ein Funktionstyp riefe "%s <> nil" auf', [AName, ATypeLow, AName]);
end;

// SCA072/SCA084: ist X an ALine sicher der Operand, fuer den die Umformung
// gilt (s. OperandFix)? '' oder der Grund.
function OperandReason(AKind: TFindingKind; APlaces: TSourcePlaces;
  AMap: TRdxCodeMap; ALine: Integer; const AName: string): string;
var
  TypeLow : string;
begin
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AName]));
  TypeLow := APlaces.DeclaredTypeOf(ALine, AName);
  if AKind = fkRedundantBoolean then
  begin
    if TypeLow = 'boolean' then
      Exit('');
    if TypeLow = '' then
      TypeLow := 'unbekannt';
    Exit(Format('%s ist hier nicht als Boolean bewiesen (Typ: %s) - bei '
      + 'Variant oder LongBool ist "= True" nicht dasselbe', [AName, TypeLow]));
  end;
  Result := AssignedNilReason(AMap, AName, TypeLow);
end;

class function TRdxFixRunner.OperandFix(AKind: TFindingKind;
  APlaces: TSourcePlaces; ALines: TStrings; ALine: Integer;
  const AMessage: string): TRdxFixOutcome;
var
  Map  : TRdxCodeMap;
  Plan : TRdxOperandEdit;
  Ok   : Boolean;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if AKind = fkRedundantBoolean then
      Ok := TRdxExprFixes.RedundantBool(Map, ALine, AMessage, Plan,
        Result.Reason)
    else
      Ok := TRdxExprFixes.AssignedNil(Map, ALine, AMessage, Plan,
        Result.Reason);
    if Ok then
      Result.Reason := OperandReason(AKind, APlaces, Map, ALine, Plan.Name)
    else if Result.Reason = '' then
      Result.Reason := R_NO_HELP;
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  Result.Name := Plan.Name;
  SetLength(Result.Edits, 1);
  Result.Edits[0] := Plan.Edit;
  Result.Hint := Plan.Edit.NewText;
  Result.Enabled := True;
end;

// SCA007: wird die Unit im AKTUELLEN Text doch benutzt? Der Fund kann
// aus einem aelteren Scan stammen (Gegen-Review 2026-10-10). Dieselben
// Spuren wie uUnusedUses: ein qualifizierter Bezug ('Classes.TList') und
// einer der bekannten Bezeichner der Unit als Code-Wort (KnownIdents, mit
// demselben Kurznamen-Rueckfall fuer RTL-Namespaces). Die uses-Klauseln
// selbst zaehlen nicht: 'uses mormot.core.os, mormot.core.os.security;'
// las das 'os' '.' des Geschwister-Eintrags als Bezug und sperrte die
// Hilfe mit "wird im Text benutzt" (Wochen-Review 2026-10-21).
function UnitStillUsed(AMap: TRdxCodeMap; const AUnit: string): Boolean;
var
  Low, Short : string;
  Idents     : TArray<string>;
  T, N, P    : TRdxToken;
  InUses     : Boolean;
begin
  Result := False;
  Low := LowerCase(AUnit);
  Short := Copy(Low, LastDelimiter('.', Low) + 1, MaxInt);
  Idents := TUnusedUsesDetector.KnownIdents(Low);
  if (Length(Idents) = 0) and TUnusedUsesDetector.IstRtlNamespace(Low) then
    Idents := TUnusedUsesDetector.KnownIdents(Short);
  P := Default(TRdxToken);
  InUses := False;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    N := After(AMap, T);
    if InUses then
      InUses := T.Low <> ';'
    else if (T.Low = 'uses') and IsKeywordAfter(T, P) then
      InUses := True
    else if ((T.Low = Short) and (N.Low = '.'))
       or (IndexText(T.Low, Idents) >= 0) then
      Exit(True);
    P := T;
    T := N;
  end;
end;

// SCA007: die Klausel und der Eintrag zum Unit-Namen AUnit auf ALine.
// '' oder der Grund.
function FindUsesEntry(APlaces: TSourcePlaces; ALine: Integer;
  const AUnit: string; out AClause: TRdxUsesClause; out AIndex: Integer): string;
var
  Clauses : TArray<TArray<TRefactorSpan>>;
  c, k, n : Integer;
begin
  Result := '';
  AClause := Default(TRdxUsesClause);
  AIndex := -1;
  n := 0;
  Clauses := ClausesOf(APlaces);
  for c := 0 to High(Clauses) do
    for k := 0 to High(Clauses[c]) do
      if (Clauses[c][k].StartLine = ALine)
         and SameText(Clauses[c][k].Resolved, AUnit) then
      begin
        Inc(n);
        AClause.Entries := Clauses[c];
        AClause.UsesLine := UsesKeywordLine(APlaces, Clauses[c][0]);
        AIndex := k;
      end;
  if n = 0 then
    Result := MsgMovedSuffix(Format('%s steht nicht mehr auf Zeile %d einer '
      + 'uses-Klausel', [AUnit, ALine]))
  else if n > 1 then
    Result := Format('%s steht mehrmals auf Zeile %d', [AUnit, ALine]);
end;

class function TRdxFixRunner.UnusedUsesFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AUnit: string): TRdxFixOutcome;
var
  Map    : TRdxCodeMap;
  Clause : TRdxUsesClause;
  Index  : Integer;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := Trim(AUnit);
  Index := -1;
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
    Result.Reason := R_NO_FILE
  else if TRdxRecipeRunner.UsesDirectiveLine(APlaces) > 0 then
    Result.Reason := 'Direktive in einer uses-Klausel - ein Eintrag gilt evtl. '
      + 'nur in einem Zweig'
  else
    Result.Reason := FindUsesEntry(APlaces, ALine, Result.Name, Clause, Index);
  if Result.Reason <> '' then Exit;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    if UnitStillUsed(Map, Result.Name) then
      Result.Reason := MsgStaleSuffix(Format('%s wird im Text benutzt',
        [Result.Name]))
    else
      Result.Enabled := TRdxStructFixes.RemoveUsesEntry(Map, Clause, Index,
        Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  // Der Detektor ist heuristisch (Bezeichnerliste je Unit): ein Typ, den
  // er nicht kennt (TDataModule, TStream ...), macht den Fund falsch.
  Result.Hint := Format('heuristischer Fund - danach kompilieren; hat %s einen '
    + 'initialization-Abschnitt (Registrierung), laeuft er nicht mehr',
    [Result.Name]);
end;

// Eingang eines Laeufers mit Quellstellen-Dienst: ohne offene Datei nil
// und R_NO_FILE in AOutcome.Reason; sonst die Code-Sicht (der Aufrufer gibt
// sie frei) und Platz fuer eine Ersetzung in AOutcome.Edits.
function OpenMapFor(APlaces: TSourcePlaces; ALines: TStrings;
  var AOutcome: TRdxFixOutcome): TRdxCodeMap;
begin
  Result := nil;
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    AOutcome.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(AOutcome.Edits, 1);
  Result := TRdxCodeMap.Create(ALines);
end;

// SCA168: TRdxStructFixes.CaseElse mit AStatement ('' = leeres else).
function CaseElseOutcome(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AStatement: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map = nil then Exit;
  try
    Result.Enabled := TRdxStructFixes.CaseElse(Map, ALine, AStatement,
      Result.Edits, Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.CaseElseFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer): TRdxFixOutcome;
begin
  Result := CaseElseOutcome(APlaces, ALines, ALine, '');
end;

class function TRdxFixRunner.CaseRaiseFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  if Assigned(APlaces) and APlaces.IsOpen
     and TRdxRecipeRunner.SourceLooksFpcAware(APlaces) then
  begin
    Result := Default(TRdxFixOutcome);
    Result.Reason := 'Datei mit FPC-Weiche oder FPC-Modus - FPC kennt '
      + 'EProgrammerError nicht';
  end
  else
    Result := CaseElseOutcome(APlaces, ALines, ALine, RAISE_UNHANDLED);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if not Result.Enabled then Exit;
  Result.Hint := R_CASE_RAISE_HINT;
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

class function TRdxFixRunner.BlockFix(AKind: TFindingKind; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
  Kw  : TRdxToken;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if AKind = fkIfElseBegin then
      Result.Enabled := TRdxStructFixes.ElseAfterEndOn(Map, ALine, Kw,
        Result.Reason)
    else
      Result.Enabled := TRdxStructFixes.BranchKeywordAt(Map, ALine,
        ColumnFromMessage(AMessage), Kw, Result.Reason);
    if Result.Enabled then
      Result.Enabled := TRdxStructFixes.WrapInBlock(Map, Kw, Result.Edits,
        Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

// SCA123: ist der Operand AOperand ein blosser Bezeichner, ausserhalb eines
// with-Blocks und als genau ATarget deklariert? '' oder der Grund.
// PFADE (A.B, Self.F) lernt die Pruefung NICHT (Folgewelle A4, geprueft):
// der Weg von SCA126 - das letzte Glied als Feld der Datei
// (TRdxTypeProof.FieldTypeOf) - beweist nur den NAMEN, gleichnamige Felder
// aller Klassen der Unit zaehlen mit, und der Typ des Pfads davor ist
// unbekannt. SCA126 fragt dort nur "Feld oder Methode", hier ist der GENAUE
// Typ der ganze Beweis: 'TStringList(Other.FList).Free' mit einem
// fremden Other, dessen FList ein TRefCountedObject ist (eigenes Free),
// verlore den Cast, wenn nur ein FList dieser Unit TStringList heisst.
// Den Pfad sperrt darum schon der Planer (uRdxLineFixes.OperandReason,
// Review Woche G07-17); die Pruefung hier bleibt als zweite Wand.
function CastTypeReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AOperand, ATarget: string): string;
var
  Declared : string;
begin
  Result := '';
  if Pos('.', AOperand) > 0 then
    Exit(Format('%s ist kein blosser Bezeichner - sein Typ ist nicht '
      + 'pruefbar', [AOperand]));
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AOperand]));
  Declared := APlaces.DeclaredTypeOf(ALine, AOperand);
  if Declared = '' then
    Result := Format('Typ von %s unbekannt - nur ein Cast auf den eigenen Typ '
      + 'ist beweisbar ohne Wirkung', [AOperand])
  else if not SameText(Declared, ATarget) then
    Result := Format('%s ist als %s deklariert, nicht als %s - ein anderer Typ '
      + 'kann Free verdecken, oder der Cast ist zum Uebersetzen noetig',
      [AOperand, Declared, ATarget]);
end;

// SCA123: 'TFoo(X).Free' -> 'X.Free' (TRdxLineFixes.CastFree) - nur, wenn
// X ein blosser Bezeichner ist, ausserhalb eines with-Blocks, und als
// genau TFoo deklariert (DeclaredTypeOf). Nur dann binden beide dasselbe
// Free: ein anderer Typ kann Free verdecken (dwsUtils:
// TRefCountedObject.Free zaehlt nur herunter), und ein Pointer-Operand
// braucht den Cast zum Uebersetzen (Gegen-Review Zeilen-Hilfen).
function CastFreeFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxLineFixes.CastTargetOf(AMessage);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map = nil then Exit;
  try
    Result.Enabled := TRdxLineFixes.CastFree(Map, ALine, AMessage,
      Result.Edits[0], Result.Reason);
    if Result.Enabled then
      Result.Reason := CastTypeReason(APlaces, Map, ALine,
        Result.Edits[0].NewText, Result.Name);
  finally
    Map.Free;
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if Result.Enabled then
    Result.Hint := Format(R_CAST_HINT, [Result.Edits[0].NewText, Result.Name])
  else
    Result.Edits := nil;
end;

// SCA020, zweiter Eintrag: raise ENotImplemented im leeren Rumpf - aendert
// das Verhalten; SysUtils kommt bei Bedarf mit (FPC kennt ENotImplemented
// ebenfalls).
function EmptyRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map <> nil then
  try
    Result.Enabled := TRdxRaiseFixes.EmptyBody(Map, ALine,
      RAISE_NOT_IMPLEMENTED, Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := R_EMPTY_RAISE_HINT;
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

// SCA098: X muss als Boolean BEWIESEN sein - bei Variant bekaeme X den
// Wert der Bedingung statt True/False (wie SCA072: Variant/LongBool sind
// nicht dasselbe). In der Gegenrichtung muss auch C Boolean sein: der Form
// nach (Vergleiche, and/or/xor/not daraus, TRdxFlowPlan.CondBoolean) und
// jeder blosse Bezeichner darin als Boolean deklariert - bei einem Variant
// waere 'not' bitweise ('not 1' ist wieder wahr). Im with-Block kann ein
// Name ein Member sein. '' oder der Grund.
function CondAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxFlowPlan): string;
var
  TypeLow, Ident : string;
begin
  Result := '';
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [APlan.Target]));
  TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Target);
  if TypeLow <> 'boolean' then
  begin
    if TypeLow = '' then
      TypeLow := 'unbekannt';
    Exit(Format('%s ist hier nicht als Boolean bewiesen (Typ: %s) - bei '
      + 'Variant bekaeme %s den Wert der Bedingung statt True/False',
      [APlan.Target, TypeLow, APlan.Target]));
  end;
  if not APlan.Negated then Exit;
  if not APlan.CondBoolean then
    Exit('die Bedingung ist nicht als Boolean bewiesen (ein Aufruf, ein Pfad '
      + 'oder Arithmetik als Operand) - bei einem Variant waere "not" bitweise');
  for Ident in APlan.CondIdents do
    if APlaces.DeclaredTypeOf(ALine, Ident) <> 'boolean' then
      Exit(Format('%s in der Bedingung ist hier nicht als Boolean bewiesen - '
        + 'bei einem Variant waere "not" bitweise', [Ident]));
end;

// SCA047: ist das Ziel ein Speicherplatz? Der Detektor hat es aufgeloest;
// hier am aktuellen Text: kein with-Block (der Name koennte ein Member mit
// Setter sein), kein Pfadteil als Property der Unit deklariert, die Wurzel
// ('Pt' in 'Pt.Y', ohne 'Self.') als Variable bekannt (DeclaredTypeOf oder
// Inline-Variable). '' oder der Grund.
function SelfAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const ATarget: string): string;
var
  Parts : TArray<string>;
  Root  : string;
  i     : Integer;
begin
  Result := '';
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [ATarget]));
  Parts := StringReplace(ATarget, '^', '', [rfReplaceAll]).Split(['.']);
  if Length(Parts) = 0 then
    Exit('Ziel fehlt');
  for i := 0 to High(Parts) do
    if TRdxTypeProof.DeclaresProperty(AMap, Trim(Parts[i])) then
      Exit(Format('%s ist in dieser Unit als Property deklariert - die '
        + 'Zuweisung ruft vielleicht einen Setter', [Trim(Parts[i])]));
  Root := Trim(Parts[0]);
  if SameText(Root, 'Self') and (Length(Parts) > 1) then
    Root := Trim(Parts[1]);
  if (APlaces.DeclaredTypeOf(ALine, Root) = '')
     and not TRdxSimpleFixes.DeclaresInlineVar(AMap, ALine, Root) then
    Result := Format('%s ist hier nicht als Variable bekannt (Property oder '
      + 'Feld aus einer anderen Unit?)', [Root]);
end;

// Der Text, auf dem uNilComparison den Knoten zaehlt (Analyse
// editorhilfen-2a, Tabelle der Knoten): Aufrufe tragen ihn im Namen,
// raise in beiden Feldern, alle anderen Anweisungen in TypeRef.
function NilTextOf(const ANode: TNodeRef): string;
begin
  case ANode.Kind of
    TNodeKind.nkCall, TNodeKind.nkInherited:
      Result := ANode.Name;
    TNodeKind.nkRaise:
      Result := ANode.Name + ' ' + ANode.TypeRef;
  else
    Result := ANode.TypeRef;
  end;
end;

// Die EINE Anweisung auf ALine mit einem nil-Vergleich als SCA126-Stelle.
// '' oder der Grund (keine, mehrdeutig).
function PickNilSite(APlaces: TSourcePlaces; ALine: Integer;
  out ASite: TRdxNilSite): string;
var
  Nodes : TArray<TNodeRef>;
  N     : TNodeRef;
  Hits  : Integer;
begin
  Result := '';
  ASite := Default(TRdxNilSite);
  Nodes := APlaces.NodesAt(ALine, [TNodeKind.nkIfStmt, TNodeKind.nkWhileStmt,
    TNodeKind.nkCaseStmt, TNodeKind.nkAssign, TNodeKind.nkCall,
    TNodeKind.nkExit, TNodeKind.nkInherited, TNodeKind.nkRaise]);
  Hits := 0;
  for N in Nodes do
    if TRdxNilFix.CountNilComparisons(NilTextOf(N)) > 0 then
    begin
      Inc(Hits);
      ASite.Line     := N.Line;
      ASite.Col      := N.Col;
      ASite.NodeText := NilTextOf(N);
      if N.Kind in [TNodeKind.nkIfStmt, TNodeKind.nkWhileStmt,
         TNodeKind.nkCaseStmt] then
        ASite.Anchor := naCondition
      else
        ASite.Anchor := naStatement;
    end;
  if Hits = 0 then
    Result := Format('keine Anweisung mit nil-Vergleich beginnt auf Zeile %d',
      [ALine])
  else if Hits > 1 then
    Result := Format('Zeile %d ist mehrdeutig (%d Anweisungen mit nil-Vergleich)',
      [ALine, Hits]);
end;

// SCA126, je Operand des Plans: nur ein blosser Bezeichner hat einen
// deklarierten Typ (DeclaredTypeOf) - OHNE beweisbaren Typ (geerbt aus
// einer anderen Unit, Vorfahr von ausserhalb) sperrt er: als Funktions-
// oder Methodenzeiger ruft '= nil' ihn auf, Assigned() nicht - lieber
// keine Hilfe als eine falsche (Review reDelphiX nach Bereichen 2026-10-10,
// Minor 6). Alles Weitere - Ereignis-/Getter-Namen, riskante Typnamen,
// Prozedurtypen DIESER Unit und Pfade ohne bewiesenes Feld - prueft
// TRdxNilFix.NilOperandReason auf der Code-Sicht (Review Quick-Fix-Units
// 2026-10-14, Blocker SCA126). '' oder der Grund.
function NilOperandsReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxNilPlan): string;
var
  TypeLow : string;
  i       : Integer;
begin
  Result := '';
  for i := 0 to High(APlan.Operands) do
  begin
    TypeLow := '';
    if TRdxRecipes.IsPlainIdent(APlan.Operands[i]) then
    begin
      TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Operands[i]);
      if TypeLow = '' then
        Exit(Format(R_NIL_TYPE_UNKNOWN, [APlan.Operands[i]]));
    end;
    Result := TRdxNilFix.NilOperandReason(AMap, APlan.Operands[i], TypeLow);
    if Result <> '' then Exit;
  end;
end;

// Der Hint der SCA126-Hilfe: die neuen Ausdruecke, mit ', ' verbunden.
function NilHintOf(const APlan: TRdxNilPlan): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(APlan.Edits) do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(APlan.Edits[i].NewText);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxFixRunner.NilComparisonFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer): TRdxFixOutcome;
var
  Site : TRdxNilSite;
  Map  : TRdxCodeMap;
  Plan : TRdxNilPlan;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Result.Reason := PickNilSite(APlaces, ALine, Site);
  if Result.Reason <> '' then Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    // Im with-Block kann ein Operand an ein Member des with-Ausdrucks
    // binden (ein Funktionszeiger: '= nil' ruft ihn auf) - der deklarierte
    // Typ beweist dort nichts. Dieselbe Sperre wie SCA085 (VariableCheck;
    // Gegen-Review nach Bereichen 2026-10-10).
    if APlaces.InWithBlock(Site.Line)
       or TRdxSimpleFixes.WithBefore(Map, Site.Line) then
    begin
      Result.Reason := R_NIL_IN_WITH;
      Exit;
    end;
    if not TRdxNilFix.NilComparison(Map, Site, Plan) then
    begin
      Result.Reason := Plan.Reason;
      Exit;
    end;
    Result.Reason := NilOperandsReason(APlaces, Map, Site.Line, Plan);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  Result.Hint    := NilHintOf(Plan);
  Result.Edits   := Plan.Edits;
  Result.Enabled := True;
end;

end.
