unit uExceptionTooGeneral;

// Detektor: `except on E: Exception do ...` mit Basisklasse Exception.
//
// Pattern (Code Smell, Sonar-50 #11):
//   try
//     DoStuff;
//   except
//     on E: Exception do           // <-- faengt ALLES, inklusive
//       Log(E.Message);             //     EOutOfMemory, EAbort, ...
//   end;
//
// Korrekt:
//   try
//     DoStuff;
//   except
//     on E: EDatabaseError do      // spezifische Subklasse
//       Log(E.Message);
//     on E: EArgumentException do
//       Log(E.Message);
//   end;
//
// Warum schaedlich: das Basis-Exception faengt jeden Fehler, auch solche
// die normalerweise NICHT vom User-Code behandelt werden sollten (z.B.
// EOutOfMemory, EAccessViolation, EAbort als Steuerflusssignal). Der
// Aufrufer denkt, er habe alles im Griff - in Wirklichkeit verschluckt
// er System-Fehler die abgebrochen werden sollten.
//
// Erkennung (AST):
//   Parser legt 'on E: T do ...' als nkOnHandler ab. Dabei:
//     OnNode.Name    = Exception-Variablen-Name (z.B. 'E') oder leer
//     OnNode.TypeRef = Typ-Identifier (z.B. 'Exception', 'EFoo')
//   Befund wenn SameText(TypeRef, 'Exception').
//
// Bewusst NICHT als Finding:
//   * `except ... end;` ohne `on`-Klausel - faengt zwar auch alles, das
//     ist aber Pattern fuer Top-Level-Crash-Handler. Eigener Detector
//     (fkEmptyExcept fuer leere Variante) deckt das ab.
//   * `on E: EAbort do ... raise;` mit re-raise - dort wuerde Filter
//     greifen, aber TypeRef='EAbort' nicht 'Exception'.
//   * Legit Top-Level-Handler die LOGGEN und beenden:
//       `on E: Exception do begin WriteLn(ErrOutput, 'Fatal: ', E.Message);`
//       `Exit(Integer(cecToolError)); end;`
//     Diese Pattern faengt zwar 'Exception' breit, ist aber bewusst die
//     defensive Schutzschicht am Top-Level (CLI-Runner, Worker-Threads).
//     Heuristik: Body enthaelt einen Log-Call (WriteLn/Write/Log/Output*)
//     UND einen Exit/Halt - dann ist es kein Swallow, sondern saubere
//     Crash-Translation.
//   * Catch-all an einer ABI-Grenze (cdecl/stdcall/safecall/winapi), der E
//     an einen Konverter durchreicht. Die Aufrufkonvention wird dabei an
//     der DEKLARATION gelesen, nicht nur am Implementierungs-Kopf: Delphi
//     verlangt die Direktive nur dort, generierte Wrapper (python4delphi)
//     schreiben sie ausschliesslich dort.
//
// Sonar-Pendant: ExceptionTooGeneral / "java:S2221" (Java)
//                S110 Pattern bezogen auf Delphi-Hierarchie.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TExceptionTooGeneralDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      AContext: TAnalyzeContext = nil);
    // ADeclAbi: Aufrufkonventionen aus den Klassen-DEKLARATIONEN der Unit
    // (Key 'klasse.methode' lower -> TypeRef der Deklaration). Optional; ohne
    // die Map faellt der ABI-Guard auf den Implementierungs-Kopf zurueck, wie
    // bis 2026-08-16. AnalyzeUnit baut sie einmal je Unit.
    class procedure AnalyzeMethod(MethodNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      ADeclAbi: TDictionary<string, string> = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, CyclomaticComplexity, TooLongLine, UnsortedUses
// noinspection-file UnusedParameter
// AContext ist der Kontext-Parameter aus der AddD-Registrierung (B10, 2026-08-16).
// Er wird HIER bewusst noch nicht gelesen: die Umstellung ist ein eigener,
// verhaltensneutraler Schritt VOR der Regelaenderung, die ihn braucht - so
// verlangt es die Fix-Spezifikation, damit im A/B trennbar bleibt, was die
// Zahlen bewegt hat. Die Datei hatte vorher NULL UnusedParameter-Funde,
// der Marker schaltet also nichts Bestehendes mit stumm.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes, uDetectorUtils;

function CallIdLooksLikeLogger(const NameLow: string): Boolean;
// True wenn der Callee-Identifier (der Teil VOR der Klammer) auf 'log'
// endet - deckt praefigierte Logger ab, die StartsWith('log') NICHT
// erwischt: Alcinoe 'ALLog', sowie 'WriteLog'/'AppLog'/'TraceLog'/...
// Nur der Identifier wird geprueft (Argumente abgeschnitten), damit ein
// 'log'-Vorkommen im Argument (z.B. DoWork(catalog)) kein HasLog setzt.
// Bekannte Nicht-Logger-Woerter, die zufaellig auf 'log' enden (Dialog,
// Catalog, Backlog, ...), werden ausgeschlossen, damit kein echter
// Swallow-Handler faelschlich als 'legitim' unterdrueckt wird (TP-safe).
const
  NonLoggers: array[0..7] of string =
    ('dialog', 'catalog', 'backlog', 'analog', 'prolog', 'blog', 'epilog', 'weblog');
var
  Id : string;
  p  : Integer;
  nl : string;
begin
  Result := False;
  Id := NameLow;
  p  := Pos('(', Id);
  if p > 0 then Id := Copy(Id, 1, p - 1);
  Id := Trim(Id);
  if not Id.EndsWith('log') then Exit;
  for nl in NonLoggers do
    if Id.EndsWith(nl) then Exit(False);
  Result := True;
end;

function IsLegitTopLevelHandler(OnNode: TAstNode): Boolean;
// True wenn der Handler-Body sowohl LOGGT (WriteLn/Write/Log*/OutputDebug*)
// als auch BEENDET/RAISE'T (Exit/Halt/raise). Dann ist es kein blindes
// Swallow, sondern saubere Crash-Translation am Top-Level.
//
// Heuristik scannt nur die DIREKTEN Calls im Subtree des OnHandlers - kein
// Daten-Fluss, kein Symbol-Lookup. Schmal genug um nur die klare 'log+exit'
// und 'log+raise' Pattern zu treffen.
var
  Stack    : TList<TAstNode>;
  Cur      : TAstNode;
  i        : Integer;
  NameLow  : string;
  HasLog   : Boolean;
  HasLeave : Boolean;
begin
  Result   := False;
  HasLog   := False;
  HasLeave := False;
  Stack    := TList<TAstNode>.Create;
  try
    Stack.Add(OnNode);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);

      // Bare Re-Raise (`raise;` ohne Exception-Operand) IRGENDWO im
      // Handler-Subtree - inklusive `if cond then raise;`. Bedeutet: der
      // Handler gibt die urspruengliche Exception unveraendert WEITER und
      // verschluckt nichts. Damit trifft die Detektor-Praemisse ("catches
      // every error / swallows system errors") nicht mehr zu -> eigen-
      // staendiges Suppress-Kriterium, UNABHAENGIG von HasLog. Deckt beide
      // dominanten FP-Klassen ab: reraise-cleanup (`Rollback; raise;`) und
      // log-reraise-helper (`if Helper(...) then raise;`, CEF-WndProc-Idiom).
      // Parser legt bare `raise;` als nkRaise mit Name='raise' ab; ein
      // `raise ENew.Create(...)` (echte Translation zu neuer Exception, KEIN
      // Weitergeben) ueberschreibt Name mit dem Ausdruck und faellt hier
      // NICHT durch - dessen Swallow-Semantik bleibt via HasLog+HasLeave.
      if (Cur.Kind = nkRaise) and SameText(Trim(Cur.Name), 'raise') then
        Exit(True);
      // raise <expr>; (Translation) ist Leave-Pattern, aber kein Weitergeben
      // der Original-Exception - nur zusammen mit HasLog akzeptieren.
      if Cur.Kind = nkRaise then HasLeave := True;
      if Cur.Kind = nkExit  then HasLeave := True;
      // Result := exit-code im Handler ist auch Leave-Pattern: Funktion
      // gibt Fehler-Code zurueck und faellt natuerlich durch ans Method-End.
      // Klassische CLI-Runner-/Worker-Translation:
      //   `except on E: Exception do begin WriteLn(...); Result := cecToolError; end;`
      // Wir akzeptieren auch `Result.Field`/`Result[i]`/`Result^`-Zuweisungen.
      if Cur.Kind = nkAssign then
      begin
        NameLow := LowerCase(Trim(Cur.Name));
        if (NameLow = 'result') or
           NameLow.StartsWith('result.') or
           NameLow.StartsWith('result[') or
           NameLow.StartsWith('result^') then
          HasLeave := True;
      end;

      if Cur.Kind = nkCall then
      begin
        NameLow := LowerCase(Cur.Name);
        // Log-Pattern: WriteLn/Write/Log*/OutputDebugString/ShowMessage
        if NameLow.StartsWith('writeln(')      or
           NameLow.StartsWith('write(')        or
           NameLow.StartsWith('outputdebug')   or
           NameLow.StartsWith('log')           or
           NameLow.StartsWith('showmessage(')  or
           NameLow.StartsWith('savetofile(')   or
           CallIdLooksLikeLogger(NameLow)       then
          HasLog := True;
        // Leave-Pattern: Halt(...) / Exit(...)
        if NameLow.StartsWith('halt(')         or
           NameLow.StartsWith('halt;')         or
           NameLow.StartsWith('exit(')         or
           NameLow.StartsWith('exit;')         then
          HasLeave := True;
      end;
      if HasLog and HasLeave then Exit(True);

      for i := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

// ===========================================================================
// SEMANTIK-SCHAERFUNG (30%-Real-World-Audit 2026-07-31: 4.609 Warnings,
// 82 % FP im Sample; User-Entscheidung 2026-08-01: schaerfen statt demoten).
//
// Die Praemisse der Regel ist "faengt alles und VERSCHLUCKT es". Zwei
// Konstellationen erfuellen den ersten Teil, aber nicht den zweiten - und
// genau in ihnen waere der Rat "prefer a specific subclass" ein Bug.
// ===========================================================================

function IsIdentCh(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

function MentionsWord(const AHayLow, ANeedleLow: string): Boolean;
var
  P, NL, HL     : Integer;
  Before, After : Char;
begin
  Result := False;
  NL := Length(ANeedleLow);
  HL := Length(AHayLow);
  if (NL = 0) or (HL < NL) then Exit;
  P := 1;
  repeat
    P := Pos(ANeedleLow, AHayLow, P);
    if P = 0 then Exit;
    Before := #0;
    if P > 1 then Before := AHayLow[P - 1];
    After := #0;
    if P + NL - 1 < HL then After := AHayLow[P + NL];
    if not IsIdentCh(Before) and not IsIdentCh(After) then Exit(True);
    P := P + NL;
  until False;
end;

// FP-KLASSE 2 des Audits (Wrap-und-Re-Raise, 'raise EFoo.Create(E.Message)')
// wurde BEWUSST NICHT gegatet. Sie kollidiert frontal mit einer frueheren,
// belegten Entscheidung: uTestExceptionTooGeneral.
// TranslateToNewException_StillReported haelt fest, dass die Uebersetzung in
// einen neuen Typ weiterhin ein Fund ist - der breite Catch nimmt dabei auch
// EAbort und EOutOfMemory mit und macht ein EMyError daraus, Originaltyp und
// -Stack sind weg. Der Test ist in einem Audit-TP geerdet
// ('Uebersetzung in Error-Callbacks'), die Gegenposition steht auf 2 von 24
// Stichproben. Zwei belegte Positionen, die aeltere und breitere gewinnt.
// Das nackte 'raise;' (echtes Weitergeben) bleibt wie bisher ueber
// IsLegitTopLevelHandler ausgenommen.

function RoutineHasForeignAbi(const ATypeRef: string): Boolean;
// Fremde Aufrufkonvention = die Routine ist ein Callback/Dispatcher an einer
// ABI-Grenze. Eine Delphi-Exception darf ueber diese Grenze NICHT
// propagieren (undefiniertes Verhalten im C-Code), der Catch-all ist dort
// Pflicht. 'safecall' gehoert dazu: der Compiler baut den Handler dort sogar
// selbst, ein expliziter ist die dokumentierte Ergaenzung.
var
  Low : string;
begin
  Low := LowerCase(ATypeRef);
  Result := (Pos(';cdecl',    Low) > 0) or
            (Pos(';stdcall',  Low) > 0) or
            (Pos(';safecall', Low) > 0) or
            (Pos(';winapi',   Low) > 0);
end;

function ExprPassesWordInParens(const AExprLow, AWordLow: string): Boolean;
// True, wenn AWordLow im Ausdruck INNERHALB einer Klammer vorkommt. Nur die
// Argumente zaehlen - ein Callee oder eine linke Seite, die zufaellig 'e'
// heisst, ist kein Durchreichen.
var
  p : Integer;
begin
  p := Pos('(', AExprLow);
  Result := (p > 0) and MentionsWord(Copy(AExprLow, p, MaxInt), AWordLow);
end;

function HandlerForwardsExcToCall(OnNode: TAstNode;
  const AExcVarLow: string): Boolean;
// FP-KLASSE 1, zweite Haelfte: der Rumpf reicht E an eine Konverter-Routine
// durch ('FbException.catchException(nil, e)'). Zusammen mit der fremden
// Aufrufkonvention ist das der generierte ABI-Dispatcher - im Korpus
// stammten 14 von 16 Sample-FPs aus EINER generierten Datei (Firebird.pas),
// die 4-6x vendored vorliegt.
//
// Beide Bedingungen zusammen, nicht einzeln: eine cdecl-Routine, die nur
// loggt und weitermacht, verschluckt weiterhin - und bleibt ein Fund.
//
// ZWEI ABLAGEFORMEN, beide noetig (Testfund 2026-08-01,
// SafecallDispatcherForwardingExc_NotReported war rot):
//   * nkCall  - der Aufruf steht als ANWEISUNG da, Name traegt den ganzen
//               Aufruf inklusive Argumenten.
//   * nkAssign - der Aufruf steht RECHTS von ':=' ('Result := ToHResult(E)').
//               Der Parser legt die rechte Seite in TypeRef ab (uParser2
//               Z. 2720 f.), Name traegt nur das Ziel. Genau die Form
//               benutzt jeder safecall-Dispatcher, der einen HResult
//               zurueckgibt - ohne diesen Zweig lief das Gate dort ins Leere.
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := False;
  if AExcVarLow = '' then Exit;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(OnNode);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if (Cur.Kind = nkCall) and
         ExprPassesWordInParens(LowerCase(Cur.Name), AExcVarLow) then
        Exit(True);
      if (Cur.Kind = nkAssign) and
         ExprPassesWordInParens(LowerCase(Cur.TypeRef), AExcVarLow) then
        Exit(True);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

// Aufrufkonvention aus der DEKLARATION der Methode (nil-Map: '').
// Delphi verlangt cdecl/stdcall/safecall nur an der Deklaration; python4delphi
// & Co. schreiben sie ausschliesslich dort, der Implementierungs-Kopf traegt
// sie dann nicht. Ohne diesen Nachschlag lief das ABI-Gate bei genau diesen
// generierten Wrappern leer (FP-Audit Stufe 2, 2026-08-16).
function DeclTypeRefOf(ADeclAbi: TDictionary<string, string>;
  const AMethodName: string): string;
var
  Owner, Unq, Ref : string;
begin
  Result := '';
  if not Assigned(ADeclAbi) or (AMethodName = '') then Exit;
  Owner := TDetectorUtils.OwnerTypeNameLower(AMethodName);
  Unq   := TDetectorUtils.UnqualifiedNameLastLower(AMethodName);
  if Unq = '' then Exit;
  if (Owner <> '') and ADeclAbi.TryGetValue(Owner + '.' + Unq, Ref) then
  begin
    Result := Ref;
    Exit;
  end;
  // Fallback nur ueber den blossen Methodennamen - und nur, wenn er in der
  // ganzen Unit eindeutig deklariert ist (der Aufbau in AnalyzeUnit legt
  // mehrdeutige Namen gar nicht erst ab). Faengt nested types, deren innerer
  // Typ keinen eigenen AST-Knoten hat.
  if ADeclAbi.TryGetValue('.' + Unq, Ref) then
    Result := Ref;
end;

class procedure TExceptionTooGeneralDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  ADeclAbi: TDictionary<string, string>);
var
  Handlers : TList<TAstNode>;
  N        : TAstNode;
  ExcVar   : string;
  ForeignAbi : Boolean;
begin
  Handlers := MethodNode.FindAll(nkOnHandler);
  ForeignAbi := RoutineHasForeignAbi(MethodNode.TypeRef) or
                RoutineHasForeignAbi(DeclTypeRefOf(ADeclAbi, MethodNode.Name));
  try
    for N in Handlers do
    begin
      if not SameText(N.TypeRef, 'Exception') then Continue;
      if IsLegitTopLevelHandler(N) then Continue;
      ExcVar := LowerCase(Trim(N.Name));
      // Semantik-Schaerfung 2026-08-01, reine Unterdrueckung: Catch-all an
      // einer ABI-Grenze, der E an einen Konverter durchreicht.
      if ForeignAbi and HandlerForwardsExcToCall(N, ExcVar) then Continue;
      Results.Add(TLeakFinding.New(FileName, MethodNode.Name, N.Line,
        'except on E: Exception catches every error - prefer a specific subclass',
        fkExceptionTooGeneral));
    end;
  finally
    Handlers.Free;
  end;
end;

procedure CollectDeclAbiOfClass(ClassNode: TAstNode;
  AMap: TDictionary<string, string>; ASeenNames: TStringList);
// Traegt die Methoden-Deklarationen EINER Klasse in die Map ein.
var
  Decls    : TList<TAstNode>;
  D        : TAstNode;
  Unq      : string;
begin
  Decls := ClassNode.FindAll(nkMethod);
  try
    for D in Decls do
    begin
      // Ein Punkt im Namen waere ein Implementierungsknoten - der traegt die
      // Direktiven gerade NICHT und hat hier nichts zu suchen.
      if Pos('.', D.Name) > 0 then Continue;
      Unq := LowerCase(Trim(D.Name));
      if Unq = '' then Continue;
      AMap.AddOrSetValue(LowerCase(Trim(ClassNode.Name)) + '.' + Unq, D.TypeRef);
      // Bare-Fallback nur bei Eindeutigkeit: der zweite Traeger desselben
      // Namens loescht den Eintrag wieder, statt eine fremde Konvention zu
      // vererben.
      if ASeenNames.IndexOf(Unq) >= 0 then
        AMap.Remove('.' + Unq)
      else
      begin
        ASeenNames.Add(Unq);
        AMap.AddOrSetValue('.' + Unq, D.TypeRef);
      end;
    end;
  finally
    Decls.Free;
  end;
end;

function BuildDeclAbiMap(UnitNode: TAstNode): TDictionary<string, string>;
// Key 'klasse.methode' (lower) -> TypeRef der DEKLARATION, plus '.methode'
// fuer Namen, die in der Unit nur EINMAL deklariert sind.
//
// Bewusst method-lokal: NICHT auf 'die Klasse hat irgendeine cdecl-Methode'
// erweitern - genau diese Ausweitung wurde fuer SCA106 schon gemessen und
// verworfen.
var
  Classes   : TList<TAstNode>;
  SeenNames : TStringList;
  C         : TAstNode;
begin
  Result := TDictionary<string, string>.Create;
  // nil-Init vor dem try: wirft die zweite Allokation, gibt das finally die
  // erste sauber frei (uDuplicateString-/uMissingOverride-Muster).
  Classes   := nil;
  SeenNames := nil;
  try
    SeenNames := TStringList.Create;
    SeenNames.CaseSensitive := False;
    SeenNames.Sorted        := True;
    SeenNames.Duplicates    := dupIgnore;
    Classes := UnitNode.FindAll(nkClass);
    for C in Classes do
      CollectDeclAbiOfClass(C, Result, SeenNames);
  finally
    Classes.Free;
    SeenNames.Free;
  end;
end;

class procedure TExceptionTooGeneralDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  DeclAbi : TDictionary<string, string>;
begin
  Methods := nil;
  DeclAbi := nil;
  try
    DeclAbi := BuildDeclAbiMap(UnitNode);
    Methods := UnitNode.FindAll(nkMethod);
    for M in Methods do
      AnalyzeMethod(M, FileName, Results, DeclAbi);
  finally
    Methods.Free;
    DeclAbi.Free;
  end;
end;

end.
