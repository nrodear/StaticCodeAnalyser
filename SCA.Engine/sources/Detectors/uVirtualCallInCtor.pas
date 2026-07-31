unit uVirtualCallInCtor;

// Detektor: Aufruf einer `virtual`-Methode im Constructor.
//
// Wenn ein Constructor in einer Basisklasse eine virtual-Methode ruft,
// laeuft die ueberschriebene Variante in der abgeleiteten Klasse - aber
// zu einem Zeitpunkt, wo der Sub-Klassen-Constructor noch nicht durch
// ist. Felder sind eventuell null/0, der Override greift auf halb-
// initialisiertes Self zu -> NullPointerException / Subtle-Bug.
//
// Beispiel:
//   type
//     TBase = class
//       constructor Create;
//       procedure Init; virtual;
//     end;
//     TDerived = class(TBase)
//       FCache: TList;
//       procedure Init; override;
//     end;
//
//   constructor TBase.Create;
//   begin
//     Init;            // <-- ruft TDerived.Init, FCache ist noch nil!
//   end;
//
// Algorithmus (single-unit):
//   1. Sammle alle Klassen + ihre Methoden mit Virtual-Markierung
//      (uParser2 haengt 'virtual'/'override'/'dynamic' an TypeRef an).
//   2. Fuer jeden Constructor: alle nkCall-Nodes durchgehen.
//   3. Wenn der Call-Name zu einer Methode der gleichen Klasse passt,
//      die virtual/override/dynamic ist -> Treffer.
//
// Heuristik:
//   * inherited Create / inherited Init: kein Treffer (geht hoch, nicht
//     runter; keine Override-Reflektion).
//   * Self.MyVirtual: Treffer (so wie ohne Self.).
//   * MyVirtual(args): Treffer.
//   * Andere Objekt-Calls (FFoo.DoSomething): kein Treffer.
//   * 'inherited <Event> := <Handler>;': der ZUGEWIESENE Handler ist kein
//     Treffer (2026-07-31, Event-Zuweisung ist keine Call-Kante - siehe
//     IsInheritedEventAssignPhantom). Jeder ANDERE Aufruf auf derselben
//     Zeile bleibt ein Treffer.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TVirtualCallInCtorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

// ---------------------------------------------------------------------------
// FP-Gate (2026-07-31, 30%-Real-World-Audit sca-rw-after119)
// FP-Klasse: Event-Handler-ZUWEISUNG wird als Aufruf gewertet.
// Belege: jvcl/tests/p3/source/JvPageListTreeView.pas:1614
//         ('inherited OnGetSelectedIndex := DoGetSelectedIndex;') und
//         jvcl/jvcl/run/JvThread.pas:409 ('inherited OnShow := ReplaceFormShow;').
//
// Mechanismus (an uParser2 verifiziert): fuer 'inherited <Ident> := <Ident>;'
// laeuft ParseStatement in den tkKwInherited-Zweig, ParsePrimary bricht am
// ':=' ab und legt nkInherited('OnShow') an. Das uebrig gebliebene ':=' faellt
// in den else-Zweig (Next; Eat(tkSemicolon), kein Knoten), und der RHS-
// Bezeichner wird danach als eigenstaendige Anweisung geparst -> Phantom-
// nkCall('ReplaceFormShow'). Der Reachability-Walk haelt dieses Phantom fuer
// einen Aufruf aus dem Ctor; tatsaechlich ist es eine Methodenzeiger-
// Zuweisung, der Handler laeuft erst beim Event-Feuern nach der Konstruktion.
//
// Gate: Quellzeile des nkCall auf das Muster '^inherited <Ident> := <RhsId>'
// pruefen (Strings/Kommentare vorher entfernt). Trifft es zu, wird GENAU der
// Knoten verworfen, dessen Name dem zugewiesenen RHS-Bezeichner entspricht -
// alle anderen nkCall derselben Zeile bleiben Treffer.
//
// Praezisierung 2026-07-31 (Pre-Build-Review, Fund uVirtualCallInCtor.pas:426
// "Zeilen-basiertes Gate stellt JEDEN Aufruf auf einer 'inherited <Ident> :='-
// Zeile still"): das erste Gate war rein zeilenbasiert und verwarf auf einer
// Treffer-Zeile pauschal alles. Damit gingen belegte TPs verloren:
//   'inherited Value := ComputeIt(Self);'   (echter Aufruf MIT Klammern)
//   'inherited OnShow := Foo; Init;'        (nachgestellter echter Aufruf)
// Jetzt gilt: nur ein RHS OHNE Klammern ist ein Methodenzeiger (= keine
// Call-Kante); sobald der RHS eine Argumentliste hat, ist es ein echter
// Aufruf und die Zeile wird gar nicht erst in den Cache aufgenommen.
//
// BEWUSST eng (Praezision vor Masse - 626 Error-Funde mit nur 8% FP, die TPs
// muessen alle bleiben):
//   * 'inherited Create; Init;' enthaelt kein ':=' -> Treffer bleibt.
//   * mehrfach-Zuweisung auf einer Zeile ('inherited A := X; inherited B := Y;')
//     nimmt nur den ERSTEN RHS auf; der zweite Handler bleibt ein Fund
//     (bewusster Rest-FP statt TP-Risiko).
//   * 'inherited Caption := GetDefaultCaption;' mit virtuellem parameterlosem
//     GetDefaultCaption ist vom Methodenzeiger-Idiom textuell NICHT
//     unterscheidbar (der Parser liefert in beiden Faellen denselben blanken
//     Phantom-nkCall). Hier wird bewusst die haeufigere Lesart (Zuweisung)
//     gewaehlt - der Fund faellt weg.
// Lazy: die Datei wird erst gelesen, wenn ein Fund anstuende.
// ---------------------------------------------------------------------------

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

// Entfernt String-Literale und Kommentare aus EINER Quellzeile; InBrace /
// InParenStar tragen den Block-Kommentar-Zustand ueber Zeilengrenzen.
function StripCodeLine(const Line: string; var InBrace, InParenStar: Boolean): string;
var
  i, N  : Integer;
  InStr : Boolean;
begin
  Result := '';
  InStr  := False;
  N      := Length(Line);
  i      := 1;
  while i <= N do
  begin
    if InBrace then
    begin
      if Line[i] = '}' then InBrace := False;
      Inc(i);
      Continue;
    end;
    if InParenStar then
    begin
      if (Line[i] = '*') and (i < N) and (Line[i + 1] = ')') then
      begin
        InParenStar := False;
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      Continue;
    end;
    if InStr then
    begin
      if Line[i] = '''' then InStr := False;
      Inc(i);
      Continue;
    end;
    if Line[i] = '''' then begin InStr := True; Inc(i); Continue; end;
    if Line[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
    if (Line[i] = '(') and (i < N) and (Line[i + 1] = '*') then
    begin
      InParenStar := True;
      Inc(i, 2);
      Continue;
    end;
    if (Line[i] = '/') and (i < N) and (Line[i + 1] = '/') then Break;
    Result := Result + Line[i];
    Inc(i);
  end;
end;

// True fuer 'inherited <Ident> := <RhsIdent>' (Code bereits gestrippt).
// ARhsLow liefert den zugewiesenen RHS-Bezeichner (lowercase) - aber NUR wenn
// der RHS bis zum ersten ';' ein reiner, ggf. qualifizierter Bezeichner OHNE
// Klammern ist ('ReplaceFormShow', 'Self.ReplaceFormShow'). Alles andere
// ('ComputeIt(Self)', zusammengesetzte Ausdruecke, RHS auf der Folgezeile) ist
// entweder ein echter Aufruf oder nicht sicher zuzuordnen -> Result=False und
// die Zeile wird nicht gegatet (Review 2026-07-31).
function LineIsInheritedPropertyAssign(const Code: string;
  out ARhsLow: string): Boolean;
const
  INH = 'inherited';
var
  S    : string;
  i, N : Integer;
  Rhs  : string;
begin
  Result  := False;
  ARhsLow := '';
  S := LowerCase(TrimLeft(Code));
  if not S.StartsWith(INH) then Exit;
  N := Length(S);
  i := Length(INH) + 1;                       // erstes Zeichen NACH 'inherited'
  if (i > N) or IsIdentChar(S[i]) then Exit;  // 'inheritedfoo := ...'
  while (i <= N) and CharInSet(S[i], [' ', #9]) do Inc(i);
  if (i > N) or not CharInSet(S[i], ['a'..'z', '_']) then Exit;
  while (i <= N) and IsIdentChar(S[i]) do Inc(i);
  while (i <= N) and CharInSet(S[i], [' ', #9]) do Inc(i);
  if not ((i < N) and (S[i] = ':') and (S[i + 1] = '=')) then Exit;

  // RHS = Text hinter ':=' bis zum ersten ';' (bzw. Zeilenende).
  Inc(i, 2);
  Rhs := '';
  while (i <= N) and (S[i] <> ';') do
  begin
    Rhs := Rhs + S[i];
    Inc(i);
  end;
  Rhs := Trim(Rhs);
  if Rhs = '' then Exit;
  if not CharInSet(Rhs[1], ['a'..'z', '_']) then Exit;   // Literal/Ausdruck
  for i := 1 to Length(Rhs) do
    if not (IsIdentChar(Rhs[i]) or (Rhs[i] = '.')) then
      Exit;                                              // Klammern/Operatoren
  ARhsLow := Rhs;
  Result  := True;
end;

// Zeilen-Map der Datei: Zeilennummer -> zugewiesener RHS-Bezeichner des
// 'inherited <Ident> := <RhsIdent>'-Musters. ACache wird beim ersten Aufruf
// gefuellt (nil = noch nicht gelesen) und vom Aufrufer freigegeben.
// AContext steht hier nicht zur Verfuegung (SCA048 ist als 3-Parameter-Detektor
// registriert) -> Prozess-Cache bzw. Direkt-Load; ist die Datei nicht lesbar
// (In-Memory-Pfad), bleibt die Map leer und der Gate ist inert (fail-open).
//
// True nur, wenn ACallName GENAU der zugewiesene RHS-Bezeichner ist. Damit
// bleibt ein echter Aufruf auf derselben Zeile ('inherited OnShow := Foo; Init;'
// oder 'inherited Value := ComputeIt(Self);') ein Treffer (Review 2026-07-31).
function IsInheritedEventAssignPhantom(const FileName: string; LineNo: Integer;
  const ACallName: string; var ACache: TDictionary<Integer, string>): Boolean;
var
  Lines            : TStringList;
  Cached           : Boolean;
  i                : Integer;
  InBrace, InParen : Boolean;
  RhsLow, NameLow  : string;
begin
  Result := False;
  if ACache = nil then
  begin
    ACache := TDictionary<Integer, string>.Create;
    Lines := AcquireLines(FileName, Cached, nil);
    if Lines <> nil then
    try
      InBrace := False;
      InParen := False;
      for i := 0 to Lines.Count - 1 do
        if LineIsInheritedPropertyAssign(
             StripCodeLine(Lines[i], InBrace, InParen), RhsLow) then
          // Genau ein Eintrag je Zeile: geprueft wird nur das zeilenfuehrende
          // 'inherited'; eine zweite Zuweisung derselben Zeile bleibt ungegatet.
          ACache.AddOrSetValue(i + 1, RhsLow);
    finally
      ReleaseLines(Lines, Cached);
    end;
  end;
  if not ACache.TryGetValue(LineNo, RhsLow) then Exit;
  NameLow := LowerCase(Trim(ACallName));
  // Argumentliste im Knotennamen = echter Aufruf, nie die Phantom-Kante.
  if Pos('(', NameLow) > 0 then Exit;
  Result := NameLow = RhsLow;
end;

function IsConstructor(MethodNode: TAstNode): Boolean;
begin
  Result := LowerCase(Trim(MethodNode.TypeRef)).StartsWith('constructor');
end;

function HasDirective(MethodNode: TAstNode; const Dir: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(MethodNode.TypeRef);
  Result := (Pos(';' + Dir, Lower) > 0);
end;

function IsVirtualLike(MethodNode: TAstNode): Boolean;
// `dynamic` ist semantisch ebenfalls virtual-like, der Lexer kennt das
// Keyword aktuell aber nicht (kein tkKwDynamic, kommt als tkIdent durch
// und wird von IsMethodDirective nicht als Direktive konsumiert). Wenn
// der Lexer um `dynamic` erweitert wird, hier die Liste ergaenzen.
begin
  Result := HasDirective(MethodNode, 'virtual')
         or HasDirective(MethodNode, 'override');
end;

function ExtractCallTarget(const CallName: string): string;
// Aus `Self.Init` -> `Init`, aus `Init(x)` -> `Init`, aus `FFoo.Bar` -> ''
// (Object-Call - nicht relevant).
var
  Trimmed : string;
  DotPos  : Integer;
  Lhs, Rhs: string;
  ParenPos: Integer;
begin
  Result  := '';
  Trimmed := Trim(CallName);
  if Trimmed = '' then Exit;

  // Argument-Liste wegschneiden
  ParenPos := Pos('(', Trimmed);
  if ParenPos > 0 then
    Trimmed := Copy(Trimmed, 1, ParenPos - 1);

  DotPos := Pos('.', Trimmed);
  if DotPos = 0 then Exit(Trim(Trimmed));   // einfacher Call

  Lhs := LowerCase(Trim(Copy(Trimmed, 1, DotPos - 1)));
  Rhs := Trim(Copy(Trimmed, DotPos + 1, MaxInt));
  if Lhs = 'self' then Exit(Rhs);
  // Anderes Objekt - nicht relevant
end;

// Folgt rekursiv den Calls einer non-virtual Methode bis ein virtual
// erreicht wird oder das Depth-Limit greift. ChainOut akkumuliert die
// Call-Kette (lowercase-Method-Namen) damit das Finding den vollen
// Pfad "Init -> DoSetup -> DoStuff" zeigen kann.
//
// 2026-06-18 (Audit_ErrorDetectors E-6 P1): Cross-Method-Helper-
// Detection. Vorher fand der Detector nur direkte Virtual-Calls im
// Ctor. Helper-Pattern ueberging er:
//   constructor TFoo.Create; begin Init; end;   // Init = non-virtual
//   procedure TFoo.Init;     begin DoStuff; end; // DoStuff = virtual!
// → Bug, weil aufrufende Subklasse DoStuff overriden kann.
const
  MAX_CHAIN_DEPTH = 5;   // bei deeper Helpers wird's pathologisch

function FindVirtualInChain(StartName: string;
  MethodByName: TDictionary<string, TAstNode>;
  VirtualByName: TDictionary<string, TAstNode>;
  Visited, ChainOut: TList<string>;
  Depth: Integer): TAstNode;
var
  Method      : TAstNode;
  CallList    : TList<TAstNode>;
  Call        : TAstNode;
  Target, Low : string;
  VMethod     : TAstNode;
  RecurResult : TAstNode;
begin
  Result := nil;
  if Depth > MAX_CHAIN_DEPTH then Exit;
  if Visited.IndexOf(StartName) >= 0 then Exit;   // Zyklus
  Visited.Add(StartName);

  // Method existiert in dieser Klasse? Sonst koennen wir nicht weiter folgen.
  if not MethodByName.TryGetValue(StartName, Method) then Exit;

  CallList := Method.FindAll(nkCall);
  try
    for Call in CallList do
    begin
      Target := ExtractCallTarget(Call.Name);
      if Target = '' then Continue;
      Low := LowerCase(Target);
      if Low.StartsWith('inherited') then Continue;

      // Direkt-Hit: Helper ruft virtual-Method.
      if VirtualByName.TryGetValue(Low, VMethod) then
      begin
        ChainOut.Add(Low);
        Exit(VMethod);
      end;
      // Nicht-virtual, aber in der Klasse - rekursiv folgen.
      if MethodByName.ContainsKey(Low) then
      begin
        ChainOut.Add(Low);
        RecurResult := FindVirtualInChain(Low, MethodByName, VirtualByName,
          Visited, ChainOut, Depth + 1);
        if Assigned(RecurResult) then Exit(RecurResult);
        // Sackgasse - Element aus Chain wieder rausnehmen.
        ChainOut.Delete(ChainOut.Count - 1);
      end;
    end;
  finally
    CallList.Free;
  end;
end;

class procedure TVirtualCallInCtorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  ClassList       : TList<TAstNode>;   // 2026-07-31 umbenannt (war 'Classes') -
                                        // die Unit zieht jetzt System.Classes,
                                        // ein gleichnamiger Local verdeckte den
                                        // Unit-Namensraum.
  ClassNode       : TAstNode;
  VirtualByName   : TDictionary<string, TAstNode>;
  MethodByName    : TDictionary<string, TAstNode>;
  Methods         : TList<TAstNode>;
  M, Ctor, Call   : TAstNode;
  CtorList        : TList<TAstNode>;
  CallList        : TList<TAstNode>;
  Target, LowName : string;
  VMethod         : TAstNode;
  AlreadyReported : TList<string>;
  RepKey, Msg     : string;
  ClassImplCtors  : TList<TAstNode>;
  Visited, Chain  : TList<string>;
  // FP-Gate 2026-07-31 (Event-Zuweisung): Zeile -> zugewiesener RHS-Bezeichner,
  // lazy befuellt.
  InhAssignLines  : TDictionary<Integer, string>;
begin
  InhAssignLines := nil;
  ClassList := UnitNode.FindAll(nkClass);
  try
    for ClassNode in ClassList do
    begin
      VirtualByName := TDictionary<string, TAstNode>.Create;
      MethodByName  := TDictionary<string, TAstNode>.Create;
      try
        // Alle virtuellen + ALLE Methoden der Klasse einsammeln.
        // MethodByName brauchen wir fuer den Cross-Helper-Walk.
        Methods := ClassNode.FindAll(nkMethod);
        try
          for M in Methods do
          begin
            LowName := LowerCase(M.Name);
            if not MethodByName.ContainsKey(LowName) then
              MethodByName.Add(LowName, M);
            if IsVirtualLike(M) and not VirtualByName.ContainsKey(LowName) then
              VirtualByName.Add(LowName, M);
          end;
        finally
          Methods.Free;
        end;
        if VirtualByName.Count = 0 then Continue;

        // ABER: MethodByName muss auch die Top-Level-Impls enthalten
        // (Methods werden im Klassen-Subtree gefunden - meist nur Headers).
        // Wir nehmen Top-Level-nkMethod und matchen via "<Klasse>.<Name>"-Prefix.
        CtorList := UnitNode.FindAll(nkMethod);
        try
          for M in CtorList do
            if LowerCase(M.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
            begin
              var DotPos := LastDelimiter('.', M.Name);
              LowName := LowerCase(Copy(M.Name, DotPos + 1, MaxInt));
              // Overwrite OK - wir wollen das Impl (mit Body) statt der
              // Klassen-Subtree-Header-Node.
              MethodByName.AddOrSetValue(LowName, M);
            end;
        finally
          CtorList.Free;
        end;

        // Constructor-Impls finden.
        ClassImplCtors := TList<TAstNode>.Create;
        try
          CtorList := UnitNode.FindAll(nkMethod);
          try
            for Ctor in CtorList do
              if IsConstructor(Ctor) and
                 LowerCase(Ctor.Name).StartsWith(LowerCase(ClassNode.Name) + '.') then
                ClassImplCtors.Add(Ctor);
          finally
            CtorList.Free;
          end;

          AlreadyReported := TList<string>.Create;
          try
            for Ctor in ClassImplCtors do
            begin
              var CtorSimpleLow := LowerCase(Ctor.Name);
              var CtorDotPos := LastDelimiter('.', CtorSimpleLow);
              if CtorDotPos > 0 then
                CtorSimpleLow := Copy(CtorSimpleLow, CtorDotPos + 1, MaxInt);

              CallList := Ctor.FindAll(nkCall);
              try
                for Call in CallList do
                begin
                  Target := ExtractCallTarget(Call.Name);
                  if Target = '' then Continue;
                  LowName := LowerCase(Target);
                  if LowName.StartsWith('inherited') then Continue;
                  if LowName = CtorSimpleLow then Continue;

                  // Direkt-Hit (alter Pfad)
                  if VirtualByName.TryGetValue(LowName, VMethod) then
                  begin
                    // FP-Guard (2026-06-29): Ziel ist selbst ein Konstruktor
                    // (delegating-ctor `CreateFrom; begin Create; ... end`) - ein
                    // virtueller Konstruktor-Aufruf konstruiert VOLLSTAENDIG, kein
                    // half-init-Self. Nur virtuelle PROZEDUREN sind der Anti-Pattern.
                    if IsConstructor(VMethod) then Continue;
                    // FP-Gate (2026-07-31): Phantom-nkCall aus
                    // 'inherited <Event> := <Handler>;' - keine Call-Kante.
                    // Nur der zugewiesene Handler selbst wird verworfen
                    // (Call.Name, nicht Call.Line allein - Review 2026-07-31).
                    if IsInheritedEventAssignPhantom(FileName, Call.Line,
                         Call.Name, InhAssignLines) then Continue;
                    RepKey := Ctor.Name + '|' + LowName + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Format('Virtual method "%s" called from constructor "%s" ' +
                             '- override runs on half-initialized Self',
                        [VMethod.Name, Ctor.Name]),
                      fkVirtualCallInCtor));
                    Continue;
                  end;

                  // Cross-Helper-Hit: non-virtual Call, aber in dieser Klasse.
                  // Folge der Kette bis virtual oder Depth/Cycle-Limit.
                  if not MethodByName.ContainsKey(LowName) then Continue;
                  Visited := TList<string>.Create;
                  Chain   := TList<string>.Create;
                  try
                    Chain.Add(LowName);   // Erster Helper im Chain
                    VMethod := FindVirtualInChain(LowName, MethodByName,
                      VirtualByName, Visited, Chain, 1);
                    if not Assigned(VMethod) then Continue;
                    if IsConstructor(VMethod) then Continue;  // delegating-ctor, kein half-init
                    // FP-Gate (2026-07-31): Phantom-nkCall aus
                    // 'inherited <Event> := <Handler>;' - der Handler laeuft
                    // erst beim Event-Feuern, nicht im Ctor (JvThread.pas:409:
                    // 'inherited OnShow := ReplaceFormShow' -> Helper-Kette
                    // ReplaceFormShow -> CreateFormControls). Nur der
                    // zugewiesene Handler selbst wird verworfen (Review
                    // 2026-07-31: Call.Name statt Call.Line allein).
                    if IsInheritedEventAssignPhantom(FileName, Call.Line,
                         Call.Name, InhAssignLines) then Continue;

                    RepKey := Ctor.Name + '|' + LowerCase(VMethod.Name) + '|' +
                              IntToStr(Call.Line);
                    if AlreadyReported.IndexOf(RepKey) >= 0 then Continue;
                    AlreadyReported.Add(RepKey);

                    Msg := Format('Virtual method "%s" reachable from ' +
                                  'constructor "%s" via helper chain: %s',
                      [VMethod.Name, Ctor.Name, string.Join(' -> ', Chain.ToArray)]);
                    Results.Add(TLeakFinding.New(FileName, Ctor.Name, Call.Line,
                      Msg, fkVirtualCallInCtor));
                  finally
                    Visited.Free;
                    Chain.Free;
                  end;
                end;
              finally
                CallList.Free;
              end;
            end;
          finally
            AlreadyReported.Free;
          end;
        finally
          ClassImplCtors.Free;
        end;
      finally
        VirtualByName.Free;
        MethodByName.Free;
      end;
    end;
  finally
    ClassList.Free;
    InhAssignLines.Free;   // nil-sicher (TObject.Free prueft Self)
  end;
end;

end.
