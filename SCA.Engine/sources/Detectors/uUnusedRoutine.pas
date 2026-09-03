unit uUnusedRoutine;

// Detektor: top-level Procedure/Function in einer Unit wird nirgendwo
// aufgerufen (SCA164).
//
// Schliesst die Luecke zwischen SCA147 (UnusedPrivateMethod - nur class
// private) und SCA148+ (Visibility-Check - nur class public). Beispiel das
// vorher durch alle Maschen fiel:
//
//   unit u;
//   interface
//     procedure ExportedHelper;     // ggf. cross-unit gerufen
//   implementation
//     procedure InternalHelper;     // <- nur impl, kein Aufruf => DEAD
//     begin
//       ShowMessage('hi');
//     end;
//   end.
//
// Erkennung (analog SonarDelphi UnusedRoutineCheck, Single-File-Scope):
//   1. Walk alle nkMethod-Direct-Children von nkImplementation.
//   2. Filter: nur Standalone-Routinen (kein '.' im Namen). Klassen-
//      Methoden-Implementierungen (TFoo.Bar) sind durch SCA147 / SCA148+
//      abgedeckt, oder durch zukuenftige v2-Erweiterung dieses Detektors.
//   3. FP-Guards (in dieser Reihenfolge):
//        a) Konstruktor / Destruktor (nicht direkt callbar)
//        b) override / virtual; abstract / message / dynamic - Direktive
//           in TypeRef impliziert cross-class oder system dispatch
//        c) 'register' als Top-Level (IDE-Plugin-Bootstrap)
//        d) Enumerator-Trio (MoveNext / GetEnumerator / Current) -
//           implizit via for-in-Loop gerufen
//        e) Forward-Decl im interface-Teil der eigenen Unit (potenzieller
//           Cross-Unit-Konsument)
//   4. Wortgrenz-Match im stripped File-Text via TDetectorUtils.
//      StripStringsAndComments. Matches innerhalb der eigenen Routine
//      zaehlen NICHT (self-/recursive-Call != Use). Routine-Range:
//      [Mth.Line .. NextStandaloneRoutineStart-1].
//
// Severity: lsHint, Type: ftCodeSmell, Confidence: fcHigh fuer pure
// implementation-only Routinen (keine interface-Forward-Decl).
//
// Bekannte Limitierungen (MVP, dokumentiert in Konzept_SCA164_UnusedRoutine.md):
//   * Interface-Forward-Deklarierte Routinen werden NICHT geflagged - sie
//     koennten cross-unit gerufen werden, und der vorhandene gSymbolRefIndex
//     indexiert keine Bare-Calls auf top-level Routinen.
//   * `forward;`-Direktive innerhalb des implementation-Teils + spaeterer
//     Impl-Block der gleichen Routine: aktuell False-Negative (Forward-Decl-
//     Line zaehlt als externer Caller des Impls und umgekehrt). Selten in
//     modernem Code; Suppression-Marker als Escape.
//   * RTTI- und [Attribute]-Konsumenten werden nicht erkannt - Escape via
//     `// noinspection UnusedRoutine` an der Routine.
//   * DFM-Event-Handler werden in v1 nicht via DFM-Index gegengeprueft (die
//     sind ohnehin Klassen-Methoden und damit unter Klassenname qualifiziert
//     - dieses Detektor flaggt sie also gar nicht erst).
//   * Interface-Implementierungen sind ebenfalls Klassen-Methoden und werden
//     daher in v1 nicht beruehrt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TUnusedRoutineDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    // True wenn der Methoden-Direktiven-String einen der Modifier enthaelt
    // die Routine "von aussen referenziert" implizieren (override, abstract,
    // message, virtual). Match auf das von ParseMethodDirectives erzeugte
    // TypeRef-Format: 'procedure[:ret];dir1;dir2'.
    class function HasExternalReferenceDirective(const TypeRef: string): Boolean; static;
    // Link-Gates (Audit 2026-07-31), siehe Implementations-Kommentar.
    class function IsExternalImport(const TypeRef: string): Boolean; static;
    class function UnitLinksObjectFile(Lines: TStringList): Boolean; static;
    // Text aller '{$I datei}'-Includes AUS DEM IMPLEMENTATION-TEIL,
    // aneinandergehaengt; '' wenn es keine gibt. Geschwister-Gate zu
    // UnitLinksObjectFile: dort loest der Linker die Aufrufer auf, hier
    // der Praeprozessor - in beiden Faellen steht der Aufrufer nicht im
    // Unit-Text, und die Aussage "kein Aufrufer in der Unit" ist nicht
    // belegbar. Siehe Implementations-Kommentar.
    class function ImplIncludeText(Lines: TStringList; const FileName: string;
      AContext: TAnalyzeContext): string; static;
    class function IsLinkAnchorCandidate(const TypeRef: string): Boolean; static;
    // True wenn die Routine ein Konstruktor oder Destruktor ist - nicht
    // wie eine normale Procedure gerufen. Match an TypeRef-Praefix.
    class function IsCtorOrDtor(const TypeRef: string): Boolean; static;
    // True wenn der Name in der Enumerator-Whitelist liegt (MoveNext /
    // GetEnumerator / Current) - implizit via `for X in Y do` gerufen.
    class function IsEnumeratorRoutine(const Name: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, ConcatToFormat, ConsecutiveSection, GroupedDeclaration, NestedTry, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  System.IOUtils,   // TPath - Include-Pfad relativ zur Unit aufloesen
  uFileTextCache, uDetectorUtils, uAstSpans;

const
  // Routinen-Namen die per Konvention implizit gerufen werden.
  ENUMERATOR_NAMES : array[0..2] of string = (
    'movenext', 'getenumerator', 'current'
  );

class function TUnusedRoutineDetector.HasExternalReferenceDirective(
  const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  // ';dir' Pattern damit 'override' im Method-Body (unwahrscheinlich aber
  // moeglich bei Custom-Attributes) nicht matched. ';dynamic' verhaelt sich
  // identisch zu ';virtual' fuer Subclass-Dispatch.
  Result := (Pos(';override', Low)  > 0) or
            (Pos(';virtual',  Low)  > 0) or
            (Pos(';abstract', Low)  > 0) or
            (Pos(';message',  Low)  > 0) or
            (Pos(';dynamic',  Low)  > 0) or
            (Pos(';forward',  Low)  > 0); // ;forward: Decl ohne Body - der
                                          // spaetere Impl wird separat geprueft.
end;

// ===========================================================================
// LINK-GATES (30%-Real-World-Audit 2026-07-31: 1.791 Funde, 50 % FP im Sample)
//
// Ein "unused"-Hinweis auf einer link-tragenden Deklaration ist besonders
// schaedlich: wer ihm folgt, bricht den Build. Zwei Mechanismen, beide ohne
// jeden Pascal-Aufrufer BY DESIGN.
// ===========================================================================

class function TUnusedRoutineDetector.IsExternalImport(
  const TypeRef: string): Boolean;
// Rumpflose `external`-Deklaration = Import, keine Implementation. Die Regel
// zielt laut eigenem Text auf "standalone routine in the implementation
// section" - ein Import ist keine. Deckt zugleich die Link-Anker ab, deren
// EINZIGER Zweck es ist, eine Library in die Binary zu ziehen
// (Kastri DW.Biometric.iOS.pas:407 'LocalAuthenticationLoader; cdecl;
// external libLocalAuthentication;').
begin
  Result := Pos(';external', LowerCase(TypeRef)) > 0;
end;

class function TUnusedRoutineDetector.UnitLinksObjectFile(
  Lines: TStringList): Boolean;
// True, wenn die Unit ein C-Objekt statisch dazulinkt ({$L foo.obj} bzw.
// {$LINK foo.o}). Dann loest der Linker die Externals des C-Codes gegen die
// hier deklarierten Routinen auf - ein Pascal-Aufrufer existiert per
// Definition nicht (mORMot mormot.lib.quickjs.pas: 'function acosh(...):
// double; cdecl;' fuer quickjs.obj).
//
// ROHZEILEN, nicht die gestrippte Fassung: der Strip entfernt bzw. blankt
// Compiler-Direktiven mitsamt den geschweiften Klammern.
var
  i   : Integer;
  T   : string;
  p   : Integer;
begin
  Result := False;
  if Lines = nil then Exit;
  for i := 0 to Lines.Count - 1 do
  begin
    T := LowerCase(Lines[i]);
    p := Pos('{$l', T);
    while p > 0 do
    begin
      // '{$link ' oder '{$l ' - NICHT '{$libprefix', '{$legacyifend', ...
      if Copy(T, p, 6) = '{$link' then
      begin
        if (p + 6 > Length(T)) or not TDetectorUtils.IsIdentChar(T[p + 6]) then
          Exit(True);
      end
      else if (p + 3 <= Length(T)) and CharInSet(T[p + 3], [' ', #9, '''']) then
        Exit(True);
      p := Pos('{$l', T, p + 3);
    end;
  end;
end;

// Dateiname aus einer Include-Direktive ab APos ('{$i foo.inc}' /
// '{$include foo.inc}'), '' wenn die Zeile dort keine ist.
//
// Die Abgrenzung gegen '{$I+}' / '{$I-}' ist der ganze Witz: das ist die
// IO-Pruefung und kein Include. Deshalb muss auf das 'i' ein LEERRAUM
// oder ein Quote folgen, nie ein Vorzeichen.
function IncludeTargetAt(const ALow, ARaw: string; APos: Integer): string;
var
  n, e : Integer;
begin
  Result := '';
  n := APos + 2;                                   // hinter '{$'
  if Copy(ALow, n, 7) = 'include' then
    Inc(n, 7)
  else if Copy(ALow, n, 1) = 'i' then
    Inc(n)
  else
    Exit;
  if (n > Length(ALow)) or not CharInSet(ALow[n], [' ', #9, '''']) then Exit;
  while (n <= Length(ALow)) and CharInSet(ALow[n], [' ', #9, '''']) do Inc(n);
  e := n;
  while (e <= Length(ALow)) and not CharInSet(ALow[e], ['}', '''']) do Inc(e);
  // ARaw, nicht ALow: Dateisysteme sind hier zwar unempfindlich, aber der
  // Pfad gehoert unveraendert weitergereicht.
  Result := Trim(Copy(ARaw, n, e - n));
end;

class function TUnusedRoutineDetector.ImplIncludeText(Lines: TStringList;
  const FileName: string; AContext: TAnalyzeContext): string;
// Steht im implementation-Teil ein '{$I datei}', ist der Unit-Text
// UNVOLLSTAENDIG - der Praeprozessor setzt dort Code ein, den weder
// Parser noch Wort-Index dieser Unit je sehen. Eine dort stehende
// Aufrufstelle ist fuer SCA164 unsichtbar, und die Meldung "kein
// Aufrufer innerhalb der Unit" wird zur Falschaussage.
//
// Selbst gefunden am eigenen Code (Selbstscan 03.09.):
// uLocalization.pas:137 meldet 'JoinPoLines' als ungenutzt - die drei
// Aufrufer stehen in uLocalizationPo.inc, eingebunden 26 Zeilen weiter
// unten. Am Referenzkorpus sind es 13 weitere Faelle (uPSRuntime mit
// x86.inc/x64.inc, mormot.core.os mit der posix-Variante, JclWin32).
//
// NUR der implementation-Teil, und der Inhalt wird WIRKLICH gelesen
// statt die blosse Existenz zu werten. Beides ist noetig, sonst kostet
// das Gate mehr als es bringt: Includes gibt es korpusweit in 742 der
// 1.233 Fundstellen - fast alle sind Defines-Dateien im Unit-Kopf
// (jcl.inc, mormot.defines.inc), die nie einen Aufrufer tragen. Ein
// Gate auf die blosse Existenz haette 729 richtige Funde vernichtet.
//
// Eine Ebene, keine Rekursion: ein Include, das selbst wieder
// einbindet, ist im Korpus nicht belegt, und die Aufloesung braucht
// dann Suchpfade, die die Engine nicht kennt.
var
  i, p, ImplZeile : Integer;
  Low, Ziel, Voll : string;
  SB              : TStringBuilder;
  IncLines        : TStringList;
  IncCached       : Boolean;
begin
  Result := '';
  if Lines = nil then Exit;
  ImplZeile := -1;
  for i := 0 to Lines.Count - 1 do
  begin
    Low := LowerCase(Trim(Lines[i]));
    if (Low = 'implementation') or StartsStr('implementation ', Low)
       or StartsStr('implementation'#9, Low) then
    begin
      ImplZeile := i;
      Break;
    end;
  end;
  if ImplZeile < 0 then Exit;

  SB := TStringBuilder.Create;
  try
    for i := ImplZeile + 1 to Lines.Count - 1 do
    begin
      Low := LowerCase(Lines[i]);
      p   := Pos('{$', Low);
      while p > 0 do
      begin
        Ziel := IncludeTargetAt(Low, Lines[i], p);
        if Ziel <> '' then
        begin
          if TPath.IsPathRooted(Ziel) then
            Voll := Ziel
          else
            Voll := TPath.GetFullPath(ExtractFilePath(FileName) + Ziel);
          IncLines := AcquireLines(Voll, IncCached,
                                   CtxFileTextCache(AContext));
          // nil = nicht auffindbar (Suchpfad des Compilers, generierte
          // Datei). Dann liegt KEIN Beleg vor, und ohne Beleg wird nicht
          // unterdrueckt - sonst stillte ein toter Include-Verweis die
          // ganze Unit.
          if IncLines <> nil then
          try
            SB.AppendLine(IncLines.Text);
          finally
            ReleaseLines(IncLines, IncCached);
          end;
        end;
        p := Pos('{$', Low, p + 2);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TUnusedRoutineDetector.IsLinkAnchorCandidate(
  const TypeRef: string): Boolean;
// In einer obj-linkenden Unit sind das die Kandidaten, die der C-Code rufen
// kann: alles mit C-Aufrufkonvention (und die Importe selbst). Reine
// Pascal-Helfer OHNE Aufrufkonvention bleiben pruefbar - sonst waere in so
// einer Unit gar nichts mehr meldbar.
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  Result := (Pos(';cdecl',    Low) > 0) or
            (Pos(';stdcall',  Low) > 0) or
            (Pos(';varargs',  Low) > 0) or
            (Pos(';external', Low) > 0);
end;

class function TUnusedRoutineDetector.IsCtorOrDtor(
  const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  // TypeRef beginnt mit dem MethKind aus dem Parser - 'constructor' /
  // 'destructor' / 'procedure' / 'function' / 'operator'.
  Result := StartsText('constructor', Low) or
            StartsText('destructor',  Low);
end;

class function TUnusedRoutineDetector.IsEnumeratorRoutine(
  const Name: string): Boolean;
var
  Low, EN : string;
begin
  Low := LowerCase(Name);
  for EN in ENUMERATOR_NAMES do
    if Low = EN then Exit(True);
  Result := False;
end;

class procedure TUnusedRoutineDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Impls       : TList<TAstNode>;
  Impl        : TAstNode;
  Mth         : TAstNode;
  Standalones : TList<TAstNode>;
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;
  LineForChar : TArray<Integer>;  // Char-Pos -> 0-basierter Quell-Zeilenindex
  // Perf P1 (Konzept_Performance25, 2026-07-19): EIN Wort-Positions-Index
  // pro File statt TRegEx-Volltext-Scan PRO Routine (O(Kandidaten x N) -> O(N)).
  WordIdx     : TObjectDictionary<string, TList<Integer>>;
  // Wort-Index ueber den Text der '{$I}'-Includes des implementation-
  // Teils; nil, wenn die Unit keine hat (der Normalfall).
  IncWords    : TObjectDictionary<string, TList<Integer>>;
  IncText     : string;
  InterfaceMethods : TStringList; // alle nkMethod-Namen unter nkInterface
  i           : Integer;
  IFList      : TList<TAstNode>;
  IFNode      : TAstNode;
  Fwd         : TAstNode;

  function HasExternalCaller(const MethName: string;
    const OwnStart, OwnEnd: Integer): Boolean;
  // Perf P1: Lookup im per-File-Wort-Index statt '\b'+Name+'\b'-Regex ueber
  // den Volltext PRO Routine. Positionen sind 1-basiert (wie M.Index frueher),
  // Semantik identisch (ASCII-\w-Grenzen, case-insensitiv via lowercase-Key).
  var
    PosList   : TList<Integer>;
    p         : Integer;
    MatchLine : Integer;
  begin
    Result := False;
    if MethName = '' then Exit;
    if not WordIdx.TryGetValue(LowerCase(MethName), PosList) then Exit;
    for p in PosList do
    begin
      // O(1) Zeilen-Lookup ueber das TDetectorUtils-LineForChar-Array.
      // p ist 1-basiert, Array 0-basiert, Source-Line 0-basiert -> +1.
      MatchLine := LineForChar[p - 1] + 1;
      // Match in der eigenen Routine (Header- oder Body-Zeile) = self-Call,
      // nicht als Verwendung zaehlen.
      if (MatchLine >= OwnStart) and (MatchLine < OwnEnd) then Continue;
      Exit(True);
    end;
  end;

var
  MethName : string;
  Modifiers: string;
  RoutineEnd: Integer;
  LinksObj : Boolean;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  // Einmal je Datei - die Direktive steht typischerweise im Kopf, der Scan
  // laeuft aber ueber alle Zeilen (mORMot setzt sie mitten in die Unit).
  LinksObj := UnitLinksObjectFile(Lines);
  WordIdx := nil;   // Perf P1: erst nach dem Strip gebaut; nil-sicher im finally
  IncWords := nil;
  try
    // Einmal je Datei, nicht je Routine: das Lesen der Include-Datei
    // laeuft ueber denselben Text-Cache wie die Unit selbst.
    IncText := ImplIncludeText(Lines, FileName, AContext);
    if IncText <> '' then
      IncWords := TDetectorUtils.BuildWordPositionIndex(IncText);

    // Strippt Strings + Kommentare und liefert die Char->Quellzeile-Map mit -
    // ersetzt den Zwilling von uUnusedPrivateMethod und sparte das O(n)-pro-
    // Match LineOfPos durch direkten Array-Lookup.
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    Code := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineForChar, AContext, FileName);

    // Perf P1: einmaliger Wort-Positions-Index ueber den gestrippten Code -
    // HasExternalCaller macht danach nur noch O(Vorkommen)-Lookups.
    WordIdx := TDetectorUtils.BuildWordPositionIndex(Code);

    // Interface-Method-Namen EINMAL einsammeln statt pro Routine die ganze
    // AST mit FindAll(nkInterface) zu traversieren.
    InterfaceMethods := TStringList.Create;
    try
      InterfaceMethods.CaseSensitive := False;
      InterfaceMethods.Sorted        := True;
      InterfaceMethods.Duplicates    := dupIgnore;
      IFList := UnitNode.FindAll(nkInterface);
      try
        for IFNode in IFList do
          for Fwd in IFNode.Children do
            if (Fwd.Kind = nkMethod) and (Fwd.Name <> '') then
              InterfaceMethods.Add(Fwd.Name);
      finally
        IFList.Free;
      end;

      Standalones := TList<TAstNode>.Create;
      try
        // Phase 1: Standalone-Kandidaten sammeln. Multiple nkImplementation-
        // Sektionen waeren ungewoehnlich, FindAll deckt es ab.
        Impls := UnitNode.FindAll(nkImplementation);
        try
          for Impl in Impls do
            for Mth in Impl.Children do
              if (Mth.Kind = nkMethod) and (Pos('.', Mth.Name) = 0) then
                Standalones.Add(Mth);
        finally
          Impls.Free;
        end;

        // Phase 2: pro Kandidat FP-Guards + External-Caller-Check.
        for i := 0 to Standalones.Count - 1 do
        begin
          Mth       := Standalones[i];
          MethName  := Mth.Name;
          Modifiers := Mth.TypeRef;

          // FP-Guards
          // Namenloses Parser-Phantom (IFDEF-geteilter Kopf, 'Operator' als
          // Bezeichner): die Meldung lautete "Top-level routine  appears
          // unused" - mit Leerstelle. Nie melden (Audit 2026-07-31).
          if MethName = ''                            then Continue;
          if IsCtorOrDtor(Modifiers)                  then Continue;
          if HasExternalReferenceDirective(Modifiers) then Continue;
          if IsExternalImport(Modifiers)              then Continue;
          // In einer obj-linkenden Unit ruft der C-Code die Pascal-Symbole.
          if LinksObj and IsLinkAnchorCandidate(Modifiers) then Continue;
          if SameText(MethName, 'register')           then Continue;
          if IsEnumeratorRoutine(MethName)            then Continue;
          if InterfaceMethods.IndexOf(MethName) >= 0  then Continue;

          // Routinen-Ende = tiefste Quell-Zeile im AST-Subtree der Routine,
          // PLUS eine kleine Toleranz fuer das 'end;'-Closing. KEIN Fallback
          // auf NextStartAfter mehr - der schloss Caller in zwischenliegenden
          // Helper-Routinen faelschlich als 'self-call' aus (SCA164 FP).
          RoutineEnd := TAstSpans.SubtreeMaxLine(Mth) + 2;
          if HasExternalCaller(MethName, Mth.Line, RoutineEnd) then Continue;
          // Der Aufrufer kann in einem '{$I}' des implementation-Teils
          // stehen - dort sieht ihn weder Parser noch WordIdx.
          if (IncWords <> nil)
             and IncWords.ContainsKey(LowerCase(MethName)) then Continue;

          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := MethName;
          F.LineNumber := IntToStr(Mth.Line);
          F.MissingVar := Format(
            'Top-level routine %s appears unused (no caller within the unit, ' +
            'no interface forward-declaration)', [MethName]);
          F.SetKind(fkUnusedRoutine);
          // Phase 1 ist hochkonfident: kein cross-unit-Confound (kein
          // interface-Decl), self-Calls sind ausgenommen.
          F.Confidence := fcHigh;
          Results.Add(F);
        end;
      finally
        Standalones.Free;
      end;
    finally
      InterfaceMethods.Free;
    end;
  finally
    WordIdx.Free;
    IncWords.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
