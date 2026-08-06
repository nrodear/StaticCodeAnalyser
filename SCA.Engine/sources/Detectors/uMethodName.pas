unit uMethodName;

// Detektor fuer Methoden-Namen, die nicht der PascalCase-Konvention
// (UpperCamel) entsprechen.
//
// SonarDelphi-Aequivalent: communitydelphi:MethodName. Delphi-Konvention:
//   * Methoden, Properties und Routinen heissen `DoSomething` (UpperCamel)
//   * NICHT `doSomething` (lowerCamel) oder `do_something` (snake_case)
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten wird Node.Name geprueft -
// falls qualifiziert (`TFoo.Bar`), wird der Teil hinter dem Punkt
// betrachtet. Erstes Zeichen muss ein Grossbuchstabe sein.
//
// AUSNAHMEN (Hebel A, 30%-Audit 2026-07-31 - 75.604 Funde, 74 % FP im
// Sample; groesster Einzelposten des Korpus). Gemeinsamer Nenner: der
// Methodenname ist NICHT frei gewaehlt, sondern ein ABI-Schluessel.
//   (1) `external`-Routinen - der Bezeichner IST das Link-Symbol der
//       .obj/.dll (`procedure inflate_trees_bits; external;`).
//   (2) `cdecl`-Methoden eines Typs - ObjC-Selektor bzw. Java-Methoden-
//       name, ueber den die Bridge zur Laufzeit marshallt. Bewusst
//       METHODEN-lokal: eine normale Delphi-Klasse mit EINEM C-Callback
//       verliert dadurch nicht die Pruefung ihrer uebrigen Methoden.
//   (3) Methoden eines FFI-Binding-TYPS (ObjC-/JNI-Import-Interface,
//       TJavaLocal-/TOCLocal-Delegate). Noetig zusaetzlich zu (2), weil
//       die IMPLEMENTIERUNG eines Bridge-Callbacks die cdecl-Direktive
//       nicht wiederholt (`procedure TDelegate.onAdLoaded(...);`).
//   (4) generierte COM-Typelib-Importe (`*_TLB.pas`).
// Die Typ-Erkennung liegt in TDetectorUtils.CollectFfiBindingTypes; die
// Kriterien-Auswahl (und was verworfen wurde) ist dort dokumentiert.
//
// EINE MELDUNG JE METHODE (2026-08-01, Backlog-Posten aus dem
// Parser-Gate): FindAll(nkMethod) liefert fuer eine implementierte Methode
// ZWEI Knoten - die Deklaration im Typ und die Implementierung. Beide
// wurden gemeldet, obwohl es EIN Bezeichner ist und EINE Umbenennung.
// Korpus-Zensus auf after126: von 30.925 Funden sind 10.890 (35 %) genau
// solche Zwillinge (Trennung ueber die Lage zur `implementation`-Zeile;
// weitere 5.489 Mehrfachmeldungen stammen von VERSCHIEDENEN Klassen mit
// gleichem Methodennamen und bleiben zu Recht bestehen).
// Der Schluessel ist deshalb (Besitzertyp, Name), nicht (Datei, Name):
// `TFoo.create` und `TBar.create` sind zwei Befunde, die Deklaration und
// die Implementierung von `TFoo.create` sind einer. Gemeldet wird der
// ERSTE Knoten in Dokumentreihenfolge, also die Deklaration - dort
// beginnt die Umbenennung.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12,
  uAnalyzeContext;   // TAnalyzeContext (ScanRootDir-Anker des Testpfad-Gates)

type
  TMethodNameDetector = class
  public
    // AContext optional (Registrierung via AddD reicht den Scan-Ctx
    // durch; Tests/Direktaufrufe laufen mit nil) - gebraucht fuer den
    // ScanRootDir-Anker des Testpfad-Gates.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,      // TStringList (FFI-Typnamen-Set)
  uDetectorUtils;      // Hebel A: FFI-Binding-/Typelib-Gates (2026-07-31)

const
  EMIT_SEVERITY = lsHint;

function LocalName(const FullName: string): string;
var
  pDot : Integer;
begin
  pDot := LastDelimiter('.', FullName);
  if pDot > 0 then
    Result := Copy(FullName, pDot + 1, MaxInt)
  else
    Result := FullName;
end;

function IsEventHandlerSignature(MethodNode: TAstNode): Boolean;
// True wenn die Methode eine DFM-Event-Handler-Signatur hat - mind. 1
// Parameter 'Sender: TObject'. Solche Methoden werden vom Form-Designer
// per DFM gebunden und tragen per IDE-Konvention den Component-Namen als
// kleingeschriebenes Praefix (actSaveExecute, btnSaveClick, qDataAfterScroll).
// Spiegelt die Heuristik aus uCanBeClassMethod (Round-3-Fix); ohne diese
// produzierte Self-Test auf realem VCL-Form-Code ~8 FPs.
var
  Child : TAstNode;
begin
  Result := False;
  for Child in MethodNode.Children do
  begin
    if Child.Kind <> nkParam then Continue;
    if SameText(Child.Name, 'Sender') then Exit(True);
    if Pos('tobject', LowerCase(Child.TypeRef)) > 0 then Exit(True);
    Exit;                              // nur ersten Parameter pruefen
  end;
end;

function BuildMethodOwnerMap(UnitNode: TAstNode)
  : TDictionary<TAstNode, string>;
// Ordnet jeder in einem Typ-RUMPF deklarierten Methode den Namen ihres
// Typs zu. Notwendig, weil der AST keinen Parent-Zeiger hat: eine
// IMPLEMENTIERUNG traegt den Typ im qualifizierten Namen ('TFoo.bar'),
// eine DEKLARATION im Klassen-/Interface-Rumpf nicht.
//
// Verschachtelte Typen haengen als GESCHWISTER in der Typsektion (siehe
// ParseNestedTypeDecl in uParser2), nicht unter dem aeusseren Knoten -
// der Subtree-Walk je Typknoten ordnet also nichts doppelt zu.
// Caller besitzt das Ergebnis (Free).
const
  // Interface-Typen fuehrt der Parser ebenfalls als nkClass; nkRecord
  // deckt record/object mit Methoden ab.
  OWNER_KINDS : array[0..1] of TNodeKind = (nkClass, nkRecord);
var
  Types : TList<TAstNode>;
  Meths : TList<TAstNode>;
  T, M  : TAstNode;
  ki    : Integer;
begin
  Result := TDictionary<TAstNode, string>.Create;
  if UnitNode = nil then Exit;
  for ki := Low(OWNER_KINDS) to High(OWNER_KINDS) do
  begin
    Types := UnitNode.FindAll(OWNER_KINDS[ki]);
    try
      for T in Types do
      begin
        if T.Name = '' then Continue;
        Meths := T.FindAll(nkMethod);
        try
          for M in Meths do
            Result.AddOrSetValue(M, T.Name);
        finally
          Meths.Free;
        end;
      end;
    finally
      Types.Free;
    end;
  end;
end;

class procedure TMethodNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Name    : string;
  F       : TLeakFinding;
  Ch      : Char;
  TypeRefLow : string;
  OwnerName  : string;
  // Hebel A - beide LAZY, erst ab dem ersten Kandidaten gebaut. Der
  // Normalfall (Datei ohne kleingeschriebene Methode) zahlt nichts.
  FfiTypes   : TStringList;
  OwnerMap   : TDictionary<TAstNode, string>;
  // Eine Meldung je Methode: Schluessel ist '<besitzertyp>.<name>',
  // beides lowercase. Wird erst beim ersten Kandidaten gebaut.
  Seen       : TDictionary<string, Boolean>;
  SeenKey    : string;
begin
  // Gate 4 (Hebel A): generierte Typelib-Importe komplett ausnehmen.
  if TDetectorUtils.IsGeneratedTypelibFile(FileName) then Exit;

  // Gate 5 (2026-08-05, Geltungsbereich-Entscheidung des Nutzers): Funde in
  // Test-, Sample- und Demo-Verzeichnissen fallen weg - wie bei SCA001 und
  // SCA058, und mit derselben Ehrlichkeit: das ist KEINE Korrektheits-
  // aussage. Ein schlecht benannter Bezeichner ist auch in Testcode
  // schlecht benannt. Es ist eine Entscheidung darueber, wo die Regel
  // gelten soll - der Nutzer soll Namensverstoesse in seinem
  // Produktionscode sehen, nicht in vendorten Fremdbibliotheken unter
  // bin32/bin64 eines Testprojekts.
  //
  // GEMESSEN vor dem Bau (Korpus after142, 19.504 Funde): 7.801 Treffer
  // = 40 %, davon 'unittests' 6.292, 'tests' 1.334, 'test' 77, 'demos' 64,
  // 'samples' 34. Allein SECHS Kopien von Firebird.pas (generierter
  // Interface-Header, je zweimal unter bin32/ und bin64/ in zwei
  // Repo-Kopien) stellen rund 6.200 davon.
  //
  // Diese Messung hat zugleich die Diagnose des Audits vom 2026-07-31
  // widerlegt: das dort vorgeschlagene FFI-Gate haette nur 10 % getroffen.
  // Der Schwerpunkt sind generierte C-API-Header, nicht ObjC/JNI-Bridges -
  // und deren groesste Posten sind Unit-Level-Funktionen, die ein
  // Typ-basiertes Gate ohnehin nicht sieht.
  //
  // Stufe tplFixtureDir: nur Verzeichnis-Segmente, keine Dateinamen
  // (s. uDetectorUtils - Basename-Muster wuerden Kundendateien wie
  // 'MySample.pas' im Produktivbaum stilllegen und den Test-Harness).
  // Verankert an der Scanwurzel - Begruendung s. uLeakDetector2 (Gate).
  if TDetectorUtils.IsTestFixturePath(FileName,
       CtxScanRoot(AContext), tplFixtureDir) then Exit;
  FfiTypes := nil;
  OwnerMap := nil;
  Seen     := nil;
  Methods  := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      Name := LocalName(Trim(M.Name));
      if Name = '' then Continue;
      Ch := Name[1];
      // Operator-Ueberladungen (z.B. `+`, `-`) und magic methods (mit `_`
      // beginnend) ausnehmen.
      if Ch = '_' then Continue;
      if not CharInSet(Ch, ['A'..'Z','a'..'z']) then Continue;
      // PascalCase = Upper als erstes Zeichen
      if CharInSet(Ch, ['A'..'Z']) then Continue;
      // Event-Handler (Sender: TObject als 1. Param) -> per IDE-Designer
      // benannt (actSaveExecute, btnSaveClick, ...). Style-Regel passt nicht.
      if IsEventHandlerSignature(M) then Continue;

      // --- Hebel A: ABI-gebundene Namen (2026-07-31) ------------------
      // TypeRef traegt die Direktiven case-normalisiert als ';dir'-Kette
      // (ParseMethodDirectives); dieselbe Lesart wie ';abstract' in
      // uAbstractNotImpl oder ';override' in uInheritedMethodEmpty.
      TypeRefLow := LowerCase(M.TypeRef);
      // Gate 1: external -> der Bezeichner ist das Link-Symbol.
      if Pos(';external', TypeRefLow) > 0 then Continue;

      OwnerName := TDetectorUtils.OwnerTypeName(M.Name);
      if OwnerName = '' then
      begin
        if OwnerMap = nil then
          OwnerMap := BuildMethodOwnerMap(UnitNode);
        if not OwnerMap.TryGetValue(M, OwnerName) then
          OwnerName := '';
      end;
      if OwnerName <> '' then
      begin
        // Gate 2: cdecl an einer TYP-Methode = ObjC-Selektor / Java-
        // Methodenname. Freie cdecl-Routinen bleiben BEWUSST gemeldet:
        // deren Name waehlt der Autor (Lua-/SQLite-Callbacks u.ae.), und
        // der Korpus zeigt dort echte 1:1-Ports mit frei waehlbarem
        // Delphi-Namen (siehe Audit-Bewertung Alcinoe-Wrapper).
        if Pos(';cdecl', TypeRefLow) > 0 then Continue;
        // Gate 3: Methode eines FFI-Binding-Typs (traegt auch die
        // Implementierungen, die cdecl nicht wiederholen).
        if FfiTypes = nil then
          FfiTypes := TDetectorUtils.CollectFfiBindingTypes(UnitNode);
        if TDetectorUtils.IsFfiBindingTypeName(FfiTypes, OwnerName) then
          Continue;
      end;

      // Deklaration und Implementierung derselben Methode sind EIN Befund.
      // Ohne aufloesbaren Besitzertyp (freie Routine) bleibt der Praefix
      // leer - zwei gleichnamige freie Routinen kann eine Unit ohnehin nur
      // als Ueberladungen fuehren, und die teilen sich den Bezeichner.
      SeenKey := LowerCase(OwnerName) + '.' + LowerCase(Name);
      if Seen = nil then Seen := TDictionary<string, Boolean>.Create;
      if Seen.ContainsKey(SeenKey) then Continue;
      Seen.Add(SeenKey, True);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        'Method `%s` should be PascalCase (start with uppercase letter).',
        [Name]);
      F.SetKind(fkMethodName);
      Results.Add(F);
    end;
  finally
    Seen.Free;
    OwnerMap.Free;
    FfiTypes.Free;
    Methods.Free;
  end;
end;

end.
