unit uNamingExt;

// Naming-Familie erweitert (SCA118-119).
//
//   * fkExceptionName        - Exception-Descendant ohne E-Prefix
//                              (z.B. MyError statt EMyError)
//   * fkLocalConstantName    - const im Methoden-Body sollte UPPER_SNAKE
//                              (z.B. MAX_RETRIES); PascalCase = Smell
//
// Beide AST-basiert: ExceptionName auf nkClass-Knoten mit Exception-
// Vererbung; LocalConstantName auf nkConst innerhalb von nkMethod.
//
// ---------------------------------------------------------------------------
// SCA118-Praezisierung (Autopsie 2026-08-27, rw16). Alle 85 Korpus-Funde
// einzeln gegen ihre Deklarationszeile geprueft: 63 FP, 22 TP (74 % FP).
// Drei FP-Klassen, zwei Gates - beide reine UNTERDRUECKUNG, kein Fund kommt
// hinzu. GEZAEHLT ueber 13.419 .pas: 86 (Replikat) -> 22, davon 52 Drops
// aus SCA118-Gate 1 und 12 aus SCA118-Gate 2. (Die 'GATE 1..4' weiter unten
// gehoeren zu SCA119 und haben damit nichts zu tun.)
//
//   A) Java-/JNI-Interface-Deklarationen (40 Funde, z.B.
//      Alcinoe.AndroidApi.AndroidX.Media3.pas:250
//      'JPlaybackExceptionClass = interface(JExceptionClass)'). Der Parser
//      fuehrt Interfaces bewusst auf nkClass (uParser2.pas:872-878 und
//      1156-1159) - ein Gate auf den KNOTENTYP gibt es hier deshalb nicht,
//      es waere wirkungslos. Was sie ausschliesst, ist ihre Basis: 'JException'
//      ist keine Exception-Basis.
//   C) Substring-Ueberfang (11 Funde). Die alte Pos-Kette lief quer durch die
//      GANZE Vorfahrenliste und traf jedes Wort, das 'exception'/'eexternal'
//      enthaelt - 'TgoExceptionReport = class(TInterfacedObject,
//      IgoExceptionReport)' (Grijjy.ErrorReporting.pas:215) ueber das
//      Interface, 'TTestSqliteExternal = class(TTestDatabaseExternalAbstract)'
//      (mORMot2 PerfTestCases.pas:301) ueber 'DatabaseExternal' -> 'eExternal'.
//   B) eingebuergerte E-Praefixe mit Kleinbuchstaben-/Ziffern-Tag (12 Funde:
//      EdwsJSONException dwsJSON.pas:525ff, EheFontStockException
//      SynTextDrawer.pas:137, EjimHtmlParserError JimParse.pas:118,
//      EmUTF7Error IdIMAP4.pas:458, E7Zip mormot.lib.win7zip.pas:455). Die
//      tragen den E-Praefix, nur nicht in der Form 'E' + Grossbuchstabe.
//
// PREIS (bewusst, nicht verschwiegen): SCA118-Gate 1 kappt die TRANSITIVE
// Reichweite.
// Erkannt wird nur noch die DIREKTE Basis, und nur wenn sie selbst 'Exception'
// heisst oder E-foermig ist. Im Korpus leiten 31 Klassen von den 22
// verbleibenden TP-Namen ab (19x von 'ExceptionWithProps',
// mormot.core.base.pas:547) - deren eigene Nachkommen sieht SCA118 jetzt
// nicht mehr, weil die Zwischenbasis nicht E-foermig ist. Das sind echte
// FNs. Die Regel ist also nicht 'FP 74 % -> 0 %', sondern: praezise auf der
// ersten Vererbungsstufe, blind ab der zweiten. Ein Vererbungs-Index
// (uTypeIndex.IsDescendantOf) waere die saubere Loesung; er ist hier bewusst
// NICHT verdrahtet, weil er eine projektweite Vorscan-Stufe braucht.
// Zweiter, kleinerer Preis in derselben Richtung: die Monotonie-Wache in
// IsExceptionDescendant laesst 11 nachgeprueft echte Funde liegen - siehe
// dort.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNamingExtDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Laengster akzeptierter Kleinbuchstaben-Tag zwischen dem 'E' und dem
  // ersten Grossbuchstaben. Der Korpus braucht 3 ('Edws', 'Ejim'); mehr
  // waere gefaehrlich: bei 4 wuerde 'EventException' als E-praefixiert
  // durchgehen ('vent' + 'E') und ein echter Fund still verschwinden.
  MAX_LOWER_TAG = 3;

function HasExceptionPrefixShape(const AName: string): Boolean;
// True, wenn AName die E-Praefix-Form eines Delphi-Exception-Typs traegt.
// Drei Auspraegungen, alle im Korpus belegt:
//   'E' + Grossbuchstabe        - EAbort, EMyError (RTL-Konvention)
//   'E' + Ziffer                - E7Zip (mormot.lib.win7zip.pas:455)
//   'E' + kurzer Kleintag + Gross/Ziffer
//                               - EdwsJSONException (dwsJSON.pas:525),
//                                 EheFontStockException (SynTextDrawer.pas:137),
//                                 EjimHtmlParserError (JimParse.pas:118),
//                                 EmUTF7Error (IdIMAP4.pas:458)
// Der Nachfolge-Grossbuchstabe UND die Taglaenge sind beide noetig, und zwar
// gegen verschiedene Gegner: die Laenge haelt 'ExceptionWithProps'
// (mormot.core.base.pas:547, 'xception' = 8) draussen, der Nachfolger haelt
// ein blankes 'Error = class(Exception)' draussen ('rror' hat keinen
// Nachfolger). Beide Faelle sind echte Funde und muessen es bleiben.
// Kein Min() - System.Math steht nicht in der uses-Klausel dieser Unit.
var
  i, TagLen : Integer;
begin
  Result := False;
  if Length(AName) < 2 then Exit;
  if AName[1] <> 'E' then Exit;
  if CharInSet(AName[2], ['A'..'Z']) then Exit(True);
  if CharInSet(AName[2], ['0'..'9']) then Exit(True);
  if not CharInSet(AName[2], ['a'..'z']) then Exit;
  i := 2;
  while (i <= Length(AName)) and CharInSet(AName[i], ['a'..'z']) do Inc(i);
  TagLen := i - 2;
  if TagLen > MAX_LOWER_TAG then Exit;
  if i > Length(AName) then Exit;
  Result := CharInSet(AName[i], ['A'..'Z', '0'..'9']);
end;

function FirstParentToken(const ATypeRef: string): string;
// Der ERSTE Bezeichner der Vorfahrenliste - in Delphi zwingend die
// Basisklasse, alles danach sind Interfaces (ParseClassBody, uParser2.pas:
// 1236-1306, legt sie space-separiert ab, dotted-Namen zusammenhaengend).
// Unit-Qualifier wird gekappt ('Vcl.Forms.TForm' -> 'TForm'), Generic-
// Suffixe defensiv ebenfalls: der Parser legt sie heute in nkGenericArgs ab,
// aber uTypeIndex.BaseClassNameLow:121-139 - dieselbe Schablone - haelt die
// Absicherung vor, und beide sollen sich gleich verhalten.
var
  S : string;
  P : Integer;
begin
  S := Trim(ATypeRef);
  if S = '' then Exit('');
  P := Pos('<', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  P := Pos(' ', S);
  if P > 0 then S := Trim(Copy(S, 1, P - 1));
  P := LastDelimiter('.', S);
  if P > 0 then S := Copy(S, P + 1, MaxInt);
  Result := S;
end;

function IsExceptionDescendant(const TypeRef: string): Boolean;
// SCA118-GATE 1 (52 Drops GEZAEHLT, Klassen A und C im Kopfkommentar).
// Nur noch die DIREKTE Basisklasse zaehlt, und sie muss ZWEI Bedingungen
// erfuellen. Frueher lief hier eine blosse Pos-Kette ueber den GANZEN
// TypeRef und traf damit auch Interfaces der Vorfahrenliste und reine
// Wortbestandteile. Auf den Knotentyp zu pruefen hilft nicht: der Parser
// fuehrt Interfaces als nkClass (uParser2.pas:872-878) - es ist die BASIS,
// die entscheidet.
var
  Base, BaseLow : string;
begin
  Result := False;
  Base   := FirstParentToken(TypeRef);
  if Base = '' then Exit;

  // (1) FORM: die Basis heisst 'Exception' oder traegt den E-Praefix.
  // Das ist die eigentliche Praezisierung - sie wirft 'JExceptionClass',
  // 'TInterfacedObject' und 'TTestDatabaseExternalAbstract' hinaus.
  if not (SameText(Base, 'Exception') or
          HasExceptionPrefixShape(Base)) then Exit;

  // (2) MONOTONIE-WACHE: die alte Marker-Liste, jetzt aber NUR auf der
  // Basis statt auf dem ganzen TypeRef. Ohne sie waere das Gate nicht mehr
  // rein unterdrueckend: jede E-foermige Basis ohne 'Exception' im Namen
  // wuerde neue Funde ERZEUGEN - GEZAEHLT 11 im Korpus
  // ('FormatException = class(EJclError)' JclStrings.pas:412,
  //  'UnicodeEncodeError = class(EPyUnicodeError)' PythonEngine.pas:1255,
  //  'GIFException = class(EInvalidGraphic)' gifimage.pas:375 u.a.).
  // Diese 11 sind nachgeprueft ECHTE Funde, also FNs die wir hier bewusst
  // stehen lassen: ein Gate-Paket senkt FPs, es verschiebt nicht gleich-
  // zeitig die Fundmenge nach oben - sonst ist der A/B-Vergleich wertlos.
  // Genau dieselbe Abwaegung steht schon im Kopf von ConstIsExemptFromNaming
  // ('praeziser, wuerde aber Funde HINZUFUEGEN und die Monotonie brechen').
  // Die 11 gehoeren in ein eigenes Paket mit eigener Messung.
  BaseLow := LowerCase(Base);
  Result :=
    (Pos('exception',         BaseLow) > 0) or
    (Pos('eaborterror',       BaseLow) > 0) or
    (Pos('eaccessviolation',  BaseLow) > 0) or
    (Pos('eexternal',         BaseLow) > 0);
end;

// TypeRef-Format eines Konstanten-nkField (uParser2.ParseVarLikeSection):
//   'Typ=Wert'  bei 'const X: Integer = 5;'
//   '=Wert'     bei 'const X = 5;'
// Liefert False, wenn gar kein '=' vorkommt - siehe Gate 1 unten.
function SplitConstRef(const ATypeRef: string;
  out ATypePartLow, AValue: string): Boolean;
var
  p : Integer;
begin
  ATypePartLow := '';
  AValue       := '';
  p := Pos('=', ATypeRef);
  Result := p > 0;
  if not Result then Exit;
  ATypePartLow := LowerCase(Trim(Copy(ATypeRef, 1, p - 1)));
  AValue       := Trim(Copy(ATypeRef, p + 1, MaxInt));
end;

// KONSTANTEN-GATES (30%-Real-World-Audit 2026-07-31: 5.526 Funde, 71 % FP).
//
// Alle vier Pruefungen unterdruecken nur - der bestehende String/Char-Skip auf
// dem VOLLEN TypeRef bleibt daneben unveraendert stehen (er greift auch, wenn
// der Wert das Wort 'string' enthaelt; ihn auf den Typteil zu verengen waere
// praeziser, wuerde aber Funde HINZUFUEGEN und die Monotonie brechen).
function ConstIsExemptFromNaming(const ATypeRef: string): Boolean;
var
  TypeLow, Val : string;
  i, Depth     : Integer;
begin
  Result := True;

  // GATE 1: kein '=' im TypeRef -> das ist keine Konstanten-Deklaration.
  // Eine gueltige Pascal-Konstante MUSS initialisiert sein, der Parser haengt
  // den Wert also immer an. Fehlt er, stammt der Knoten aus einem
  // Initialisierer: der Wert-Scan in ParseVarLikeSection ist nicht
  // klammerbalanciert und bricht am ersten ';' ab - auch wenn das INNERHALB
  // der Klammern steht. Aus
  //   Zones: array[..] of TZone = ((TimeZone:'NST'; Offset:'-0330'), ...);
  // wird ab dem ';' ein neuer Durchlauf, und 'Offset' landet als eigene
  // "Konstante". Der Parser-Fix dazu liegt bewusst ausserhalb dieser Serie
  // (er veraendert die Sichtweite anderer Detektoren); hier faellt der
  // Phantom-Knoten am fehlenden '=' auf.
  if not SplitConstRef(ATypeRef, TypeLow, Val) then Exit;

  // GATE 2: ueberzaehlige schliessende Klammer im Typteil - zweite Signatur
  // desselben Phantoms, falls der Wert-Scan doch noch ein '=' eingesammelt hat.
  Depth := 0;
  for i := 1 to Length(TypeLow) do
  begin
    if TypeLow[i] = '(' then Inc(Depth)
    else if TypeLow[i] = ')' then
    begin
      Dec(Depth);
      if Depth < 0 then Exit;
    end;
  end;

  // GATE 3: strukturierte Konstante. Die Regel empfiehlt UPPER_SNAKE_CASE
  // ausdruecklich fuer 'numeric constants'; ein Array-/Record-Konstanten-
  // Aggregat ist keine. Erkennbar am Klammer-Aggregat als Wert oder am
  // Typnamen (Tokens stehen ohne Trenner aneinander: 'array[boolean]ofdword').
  if (Val <> '') and (Val[1] = '(') then Exit;
  if (Pos('array',  TypeLow) > 0) or
     (Pos('record', TypeLow) > 0) or
     (Pos('setof',  TypeLow) > 0) then Exit;

  // GATE 4: String-/Char-Konstante OHNE Typannotation. Der bestehende Skip
  // sieht nur den deklarierten Typ; 'cItemField = ''ItemField''' hat keinen,
  // deshalb hier der Literal-Typ des Initialisierers. '#80' ist ein
  // Char-Literal, ''...''' ein String - beides faellt nicht unter die Regel.
  if (Val <> '') and CharInSet(Val[1], ['''', '#']) then Exit;

  Result := False;
end;

function IsUpperSnake(const Name: string): Boolean;
// True wenn Name nur aus A-Z, 0-9, _ besteht (klassisches Konstanten-
// Naming wie MAX_RETRIES).
var
  i : Integer;
begin
  Result := False;
  if Name = '' then Exit;
  for i := 1 to Length(Name) do
    if not CharInSet(Name[i], ['A'..'Z', '0'..'9', '_']) then
      Exit(False);
  Result := True;
end;

class procedure TNamingExtDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes : TList<TAstNode>;
  Methods : TList<TAstNode>;
  C, M, K : TAstNode;
  F       : TLeakFinding;
  i       : Integer;
begin
  // ExceptionName: nkClass mit Exception-Parent, Name ohne E-Prefix
  Classes := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
    begin
      if C.Name = '' then Continue;
      if not IsExceptionDescendant(C.TypeRef) then Continue;
      // SCA118-GATE 2 (12 Drops GEZAEHLT, Klasse B im Kopfkommentar): Eigenname
      // traegt bereits einen E-Praefix. Frueher wurde nur 'E' + GROSSbuchstabe
      // akzeptiert; eingebuergert sind auch 'E' + kurzer Kleintag (EdwsJSON*,
      // Ehe*, Ejim*, EmUTF7Error) und 'E' + Ziffer (E7Zip). Die Regel will
      // den PRAEFIX sehen, nicht eine bestimmte Schreibweise dahinter.
      if HasExceptionPrefixShape(C.Name) then Continue;
      // Skip 'Exception' selbst (Delphi-RTL-Klasse, nicht User-Code).
      // Bleibt noetig: 'xception' ist ein 8 Zeichen langer Kleintag und
      // faellt damit absichtlich durch HasExceptionPrefixShape durch.
      if SameText(C.Name, 'Exception') then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := C.Name;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar :=
        Format('Exception class %s should start with ''E'' prefix ' +
               '(Delphi-RTL convention: EAbort, EDivByZero, EMyError). ' +
               'Suggested: E%s',
               [C.Name, C.Name]);
      F.SetKind(fkExceptionName);
      Results.Add(F);
    end;
  finally
    Classes.Free;
  end;

  // LocalConstantName: nkConstSection-Children (nkField) innerhalb eines
  // nkMethod-Knotens. Der Parser legt lokale const X = Wert; Eintraege
  // als nkField unter einer nkConstSection ab (siehe uParser2.pas:386 +
  // uFormatMismatch.pas:420 fuer das Muster).
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      // NUR die const-Sektion des DEKLARATIONSTEILS (direktes Kind der
      // Methode), nicht rekursiv. Seit der Inline-const-Unterstuetzung
      // (2026-07-26, uParser2.ParseInlineConstStmt) legt der Parser auch
      // 'const X = 42;' MITTEN IM RUMPF als nkConstSection ab - die liegt
      // aber im nkBlock, also tiefer. FindAll haette sie mitgezaehlt:
      // im Real-World-Korpus schlug das mit +523 Funden auf (deltaT,
      // interpolated, CPartBase ...). Inline-Konstanten schreibt man in
      // Delphi 10.3+ wie lokale Variablen (camelCase/PascalCase);
      // UPPER_SNAKE_CASE ist die Konvention der Unit-/Klassen-Ebene, auf
      // die diese Regel zielt. Sie hier zu fordern waere reines Rauschen.
      var Sections := TList<TAstNode>.Create;
      try
        for var Cand in M.Children do
          if Cand.Kind = nkConstSection then Sections.Add(Cand);
        for var Section in Sections do
          for i := 0 to Section.Children.Count - 1 do
          begin
            K := Section.Children[i];
            if K.Kind <> nkField then Continue;
            if K.Name = '' then Continue;
            // Sehr kurze Konst-Namen (z.B. 'i' als Loop-Counter) ueberspringen
            if Length(K.Name) <= 2 then Continue;
            if IsUpperSnake(K.Name) then Continue;
            // Strings / Chars sind oft Localisierte UI-Labels, wo
            // PascalCase OK ist - skip. (Heuristik via TypeRef-Inhalt.)
            if (K.TypeRef <> '') and
               ((Pos('string', LowerCase(K.TypeRef)) > 0) or
                (Pos('char',   LowerCase(K.TypeRef)) > 0)) then Continue;
            // Konstanten-Gates (Audit 2026-07-31): Phantom-Knoten aus
            // Initialisiererlisten, strukturierte Konstanten und
            // String-/Char-Literale ohne Typannotation. Reine Unterdrueckung.
            if ConstIsExemptFromNaming(K.TypeRef) then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := M.Name;
            F.LineNumber := IntToStr(K.Line);
            F.MissingVar :=
              Format('Local const %s in %s - consider UPPER_SNAKE_CASE ' +
                     '(MAX_RETRIES, BUFFER_SIZE) for numeric constants. ' +
                     'Helps reader distinguish constants from variables at ' +
                     'a glance.',
                     [K.Name, M.Name]);
            F.SetKind(fkLocalConstantName);
            Results.Add(F);
          end;
      finally
        Sections.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
