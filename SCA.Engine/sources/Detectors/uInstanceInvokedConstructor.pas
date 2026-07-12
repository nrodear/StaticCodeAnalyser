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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TInstanceInvokedConstructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil;
      AFieldTypes: TDictionary<string, string> = nil);
  end;

implementation

uses
  uTypeIndex;

// noinspection-file CanBeStrictPrivate, CyclomaticComplexity, LongMethod, MultipleExit, RedundantJump, TooLongLine, UnsortedUses
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
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext;
  AFieldTypes: TDictionary<string, string>);
var
  Calls    : TList<TAstNode>;
  Decls    : TList<TAstNode>;
  N, D     : TAstNode;
  Recv     : string;
  RecvType : string;
  ClassKey : string;
  F        : TLeakFinding;
  Idx      : TTypeIndex;
  VarTypes : TDictionary<string, string>;

  function BareIdent(const AName: string): string;
  // nkParam-Namen koennen einen Modifier tragen ('const r' -> 'r'); nkLocalVar
  // nie. Das letzte space-getrennte Token ist der eigentliche Bezeichner.
  var
    P : Integer;
  begin
    Result := Trim(AName);
    P := LastDelimiter(' ', Result);
    if P > 0 then Result := Copy(Result, P + 1, MaxInt);
  end;

  function IsRecordType(const ATypeRef: string): Boolean;
  // Zentraler Werttyp-Test: nur wenn der Cross-Unit-Index den Typ BEWEISBAR als
  // record kennt. tkiRecord ist ein direkter Fakt (record/Seed), keine Ketten-
  // Ambiguitaet -> kein FN-Risiko. Idx=nil -> immer False (bisheriges Verhalten).
  begin
    Result := (Idx <> nil) and (Idx.TypeKindOf(ATypeRef) = tkiRecord);
  end;

begin
  // Klassen-Praefix der aktuellen Methode ('TFoo.Bar' -> 'tfoo'); leer bei
  // freistehenden Routinen. Nur fuer die Feld-Receiver-Aufloesung (Track C).
  ClassKey := '';
  var DotP := LastDelimiter('.', MethodNode.Name);
  if DotP > 1 then ClassKey := LowerCase(Copy(MethodNode.Name, 1, DotP - 1));
  // Track C Opt-in (Konzept_StrukturellePhase, Runde 3): Cross-Unit-Typ-Index-
  // Gegenprobe. Nur wenn der repo-weite TTypeIndex verfuegbar & nicht leer ist,
  // bauen wir eine Empfaenger-Typ-Map (lokale Vars + Params dieser Methode) auf.
  // Damit unterscheiden wir WERTTYP-RECORDS (TRegEx/TRttiContext/TStopwatch/...,
  // Seed oder in-source 'record'-Deklaration) von echten Klassen-Instanzen:
  // `r.Create` auf einem Record allokiert nichts und ist kein Instanz-statt-
  // Klassen-Ctor-Bug. nil/leerer Index (Tests/Single-File, AContext=nil) ->
  // Map bleibt nil -> bisheriges Verhalten, byte-identisch.
  Idx      := CtxTypeIndex(AContext);
  VarTypes := nil;
  Calls := MethodNode.FindAll(nkCall);
  try
    if (Idx <> nil) and (not Idx.IsEmpty) then
    begin
      VarTypes := TDictionary<string, string>.Create;
      Decls := MethodNode.FindAll(nkLocalVar);
      try
        for D in Decls do
          if Trim(D.TypeRef) <> '' then
            VarTypes.AddOrSetValue(LowerCase(BareIdent(D.Name)), Trim(D.TypeRef));
      finally
        Decls.Free;
      end;
      Decls := MethodNode.FindAll(nkParam);
      try
        for D in Decls do
          if Trim(D.TypeRef) <> '' then
            VarTypes.AddOrSetValue(LowerCase(BareIdent(D.Name)), Trim(D.TypeRef));
      finally
        Decls.Free;
      end;
    end;

    for N in Calls do
    begin
      Recv := ExtractCreateReceiver(N.Name);
      if not LooksLikeInstance(Recv) then Continue;

      // Track C Opt-in: Empfaenger-Typ ueber den Cross-Unit-Index aufloesen und
      // WERTTYP-RECORDS unterdruecken (`r.Create` auf einem Record allokiert
      // nichts, ist kein Instanz-statt-Klassen-Ctor-Bug). Praezedenz:
      //   1) Lokale Var / Parameter dieser Methode (VarTypes) - shadowt gleich-
      //      namiges Feld. Ist der Empfaenger eine bekannte Var/Param, entscheidet
      //      NUR deren Typ (record -> weg; Klasse/unbekannt -> Fund bleibt); es
      //      wird NICHT auf ein Feld zurueckgefallen (sonst FN durch Shadowing).
      //   2) Nur wenn der Empfaenger KEINE Var/Param ist: Klassen-Feld der
      //      besitzenden Klasse (AFieldTypes, gekeyt per Klassenname -> kein
      //      cross-class-Homonym-FN). nkField liegt getrennt vom Methoden-Body,
      //      daher die vom Aufrufer (AnalyzeUnit) vorgebaute Map.
      // nil-Map / unbekannt / Klasse -> Fund bleibt (bisheriges Verhalten,
      // byte-identisch ohne gueltigen Index).
      if (VarTypes <> nil) and
         VarTypes.TryGetValue(LowerCase(Recv), RecvType) then
      begin
        if IsRecordType(RecvType) then Continue;
      end
      else if (AFieldTypes <> nil) and (ClassKey <> '') and
              AFieldTypes.TryGetValue(ClassKey + '.' + LowerCase(Recv), RecvType) and
              IsRecordType(RecvType) then
        Continue;

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
    VarTypes.Free;
  end;
end;

class procedure TInstanceInvokedConstructorDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods    : TList<TAstNode>;
  Classes    : TList<TAstNode>;
  Fields     : TList<TAstNode>;
  M, C, Fld  : TAstNode;
  Idx        : TTypeIndex;
  FieldTypes : TDictionary<string, string>;
  Key        : string;
begin
  // Feld-Receiver-Map (Track C, Feld-Erweiterung): nur wenn der Cross-Unit-
  // Index verfuegbar & nicht leer ist (AContext gesetzt, echte Pipeline). Ohne
  // gueltigen Index bleibt die Map nil -> AnalyzeMethod verhaelt sich byte-
  // identisch. Struktur: nkClass(Name) -> nkVisibilitySection -> nkField.
  // Gekeyt 'klassenname.feldname' (beide lower) -> kein cross-class-Homonym.
  Idx        := CtxTypeIndex(AContext);
  FieldTypes := nil;
  if (Idx <> nil) and (not Idx.IsEmpty) then
  begin
    FieldTypes := TDictionary<string, string>.Create;
    Classes := UnitNode.FindAll(nkClass);
    try
      for C in Classes do
      begin
        if Trim(C.Name) = '' then Continue;
        Fields := C.FindAll(nkField);
        try
          for Fld in Fields do
            if Trim(Fld.TypeRef) <> '' then
            begin
              Key := LowerCase(Trim(C.Name)) + '.' + LowerCase(Trim(Fld.Name));
              FieldTypes.AddOrSetValue(Key, Trim(Fld.TypeRef));
            end;
        finally
          Fields.Free;
        end;
      end;
    finally
      Classes.Free;
    end;
  end;

  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results, AContext, FieldTypes);
  finally
    Methods.Free;
    FieldTypes.Free;
  end;
end;

end.

