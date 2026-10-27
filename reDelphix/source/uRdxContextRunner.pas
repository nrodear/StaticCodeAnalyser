unit uRdxContextRunner;

// reDelphix - Code-Aktionen OHNE Fund (Charge B, V5; Konzept
// Editorhilfen ohne Fund 2026-10-11, Abschnitt 3): was am Caret des
// Editor-Kontextmenues angeboten wird, OHNE ToolsAPI und ohne Parser (laeuft
// auch im FPC-Pruefstand, tools\fpc-pruefstand\build.sh). Das Gegenstueck
// zu uRdxFixRunner/uRdxFixTable, die zu einem FUND planen - hier gibt es
// nur Datei, Zeile und Zeichenspalte (uFindingActions.TEditorContext, V1).
// Den Text liest der Anbieter (uRdxProvider.ProvideContext: Editor-Puffer),
// die Menuetexte setzt uRdxFixTable.ContextCaption - dieselben wie die der
// Fund-Hilfen, damit eine Kontextaktion auf einer Fundzeile hinter der
// Fund-Hilfe wegfaellt (Entscheid F2, Dedup per Caption in
// uFindingActionMenu).
//
// DIE AKTIONEN (Entscheide Nico 2026-10-23)
//   ckIntroduceConst   "Lokale Konstante einfuehren" fuer das Zahl-Literal
//                      am Caret (F5: nur Zahlen): TRdxMagicFixes.
//                      IntroduceAt - dieselbe Kette wie der Quick-Fix SCA014
//                      (Name MagicNr01, erster freier, F3; Inline-Konstante
//                      E26; nur dieses Literal E28; kein Sync Edit, kein
//                      Dialog), danach was nur die Platte weiss
//                      (FileReason, IncludeReason - wie MagicCheck der
//                      Tabelle). Bedeutungsgleich. Sperren der ganzen
//                      Datei: kein Eintrag (s. "Wann ein Eintrag entsteht").
//   ckTryFinallyCreate C3 "try/finally um Create": TRdxTryFixes.CreateAt -
//                      die Kette des Quick-Fixes SCA009 mit X aus der Zeile;
//                      die Freigabe muss schon dastehen (F6). Gekennzeichnet
//                      (E2): die Freigabe laeuft danach auch bei einer
//                      Ausnahme.
//   ckConcatToFormat   C16 "Format() aus Verkettung bilden" (Charge N,
//                      2026-10-25): die '+'-Kette am Caret - einer
//                      Zuweisung oder des einen Arguments eines Aufrufs -
//                      ueber TRdxPlacesRunner.DescribeAnchor/FormatRewrite,
//                      dieselbe Kette wie die Fund-Hilfe SCA044 (Kompilat-
//                      Regel, IntToStr(x) -> %d/%u nur mit bewiesenem Typ,
//                      FloatToStr(x) bleibt Argument von %s, '%' im Literal
//                      wird '%%', System.SysUtils kommt notfalls mit).
//                      Braucht den Quellstellen-Dienst (Run mit APlaces;
//                      ohne ihn kein Eintrag). Bedeutungsgleich.
//   ckInvertIf         C7 "if umkehren" (Charge C78, 2026-10-27): Caret auf
//                      'if'/'then' eines if MIT else - Bedingung verneint,
//                      Zweige getauscht (uRdxIfFixes.InvertIf).
//   ckGuardClause      C7 Waechter-Klausel: Caret auf 'if'/'then' des
//                      LETZTEN 'if A then begin B end' der Routine -
//                      dieselbe Kette wie die Fund-Hilfe SCA018
//                      (uRdxDeepNestingFix.GuardAt), Menuetext und Hinweis
//                      wie dort (Dedup F2).
//   ckDeMorgan         C8 De Morgan: Caret auf 'and'/'or' einer Kette bzw.
//                      'not' vor '( .. )' in der Bedingung von if, while,
//                      until (uRdxCondFixes.DeMorgan).
//   ckFlipCompare      C8 Vergleich drehen: Caret auf einem
//                      Vergleichsoperator (uRdxCondFixes.FlipCompare).
//   ckSplitIf          C8 if teilen: Caret auf einem obersten 'and' der
//                      Bedingung (uRdxIfFixes.SplitIf).
//                      Alle sechs bedeutungsgleich (Annahmen in den Units:
//                      'not' logisch, {$B-} fuer Teilen/Zusammenfuegen);
//                      ein Kandidat entsteht nur am ausloesenden Token,
//                      nicht auf der ganzen Bedingung (wenig Rauschen).
//
// WANN EIN EINTRAG ENTSTEHT (F4): nur, wenn am Caret ein Kandidat steht -
// ein Zahl-Literal bzw. eine Zeile 'X := ..Create..', die noch nicht
// geschuetzt ist, bzw. eine Kette mit mindestens zwei Literalen oder einem
// Literal und einer Umwandlung nach String (IntToStr, FloatToStr,
// DateToStr, x.ToString ... - CONVERSION_FUNCS; das triviale 'a' + B nicht). Dann freigegeben mit Ersetzungen, oder gesperrt mit dem
// Grund. Sonst gar nichts - kein Rauschen auf jedem Rechtsklick. Ein
// triviales Zahl-Literal (0, 1, 2, -1, 10, 100, Zweierpotenzen bis 1024 -
// die Menge von SCA014, TRdxMagicFixes.IsTrivialLiteral) ist kein
// Kandidat (Entscheid Nico 2026-10-24).
// Sperrt ckIntroduceConst die GANZE Datei - FPC-Weiche, Skript, Spuren
// alter Compiler (TRdxMagicPlan.FileWide) oder der Plattenblick (Lazarus-
// bzw. altes Delphi-Projekt, Includes, Netzpfad) -, entfaellt der Eintrag
// ebenso, auch wenn zugleich die Stelle sperrte (Entscheid Nico
// 2026-10-24: in einer solchen Unit ist die Inline-Konstante nirgends
// sicher, ein ausgegrauter Eintrag auf jedem Zahl-Literal waere Rauschen).
// Sperren der Stelle (Ausdrucksfortsetzung, else-if, Deklarationszeile,
// Hauptblock ...) bleiben ausgegraut mit Grund. Die Fund-Hilfe SCA014 nennt
// weiter jeden Grund.
// Ebenso bei ckConcatToFormat: fehlt System.SysUtils und laesst sich nicht
// einfuegen (TRdxFormatOutcome.FileWide - Direktive in der Klausel, keine
// Klausel), gilt das jeder Kette der Datei: kein Eintrag. Eine Kette nur aus
// Literalen (NoOperand) ist kein Kandidat. Die Gruende der Stelle
// (Kommentar im Bereich, Variant-Anzeichen, Zahl, Klammerausdruck, SQL,
// AnsiString ...) stehen ausgegraut da. Keine Kette am Caret - der Caret
// steht nicht zwischen dem ersten und dem letzten Term (bzw. direkt
// dahinter), die Zeile traegt mehrere Anweisungen, ein Aufruf hat mehrere
// Argumente, die Kette zerfaellt anders, als der Parser sie sieht -:
// kein Eintrag. Auf einer Fortsetzungszeile einer mehrzeiligen Kette wird
// die Anweisung bis zu MAX_CHAIN_LINES Zeilen aufwaerts gesucht, solange
// die Zeile darueber nicht mit ';' endet.
//
// CARET: Zeichenspalte wie im Kontext (1-basiert, UTF-16, vor dem Zeichen
// Col); ein Caret im virtuellen Raum hinter dem Zeilenende (Col > Laenge +
// 1) zaehlt als Zeilenende (Plan B1, V3). Die Auswahl des Kontexts nutzt
// keine Aktion (F8).

interface

uses
  System.Classes,    // TStrings
  uFindingActions,   // TEditorContext
  uSourcePlaces,     // TSourcePlaces (ckConcatToFormat, C16)
  uRdxBufferMath;    // TRdxEdit

type
  TRdxContextKind = (ckIntroduceConst, ckTryFinallyCreate, ckConcatToFormat,
    ckInvertIf, ckGuardClause, ckDeMorgan, ckFlipCompare, ckSplitIf);

  // Ein Eintrag am Caret.
  //   Kind     die Aktion
  //   Enabled  freigegeben (Edits gesetzt) bzw. gesperrt (Reason gesetzt)
  //   Name     fuer '%s' im Menuetext: das Literal wie im Quelltext bzw. X
  //            - auch, wenn gesperrt ist, soweit schon bekannt; bei
  //            ckConcatToFormat das Ziel bzw. der Aufrufkopf (der Menuetext
  //            hat kein '%s'); ckDeMorgan 'and'/'or', ckFlipCompare der
  //            Operator; die anderen C7/C8-Arten ''
  //   Hint     freigegeben: was passiert (uebersetzt, uRdxText)
  //   Reason   gesperrt: warum nicht (uebersetzt)
  //   Edits    die Ersetzungen (ein Undo-Schritt, uRdxEditor.ReplaceSpans)
  //   ChangesBehavior  E2: ckTryFinallyCreate immer True
  TRdxContextOutcome = record
    Kind            : TRdxContextKind;
    Enabled         : Boolean;
    Name            : string;
    Hint            : string;
    Reason          : string;
    Edits           : TArray<TRdxEdit>;
    ChangesBehavior : Boolean;
  end;

  TRdxContextRunner = class
  public
    // ALines = derselbe Text, den der Anbieter fuer AContext.FileName las
    // (die Code-Sicht LEIHT ihn, uRdxCodeMap). Je Aktion, die am Caret in
    // Frage kommt, ein Eintrag, in der Reihenfolge von TRdxContextKind;
    // kein Kandidat -> kein Eintrag. Ungueltiger Kontext (IsValid) oder
    // eine Zeile ausserhalb des Texts: nil. APlaces: der Quellstellen-
    // Dienst, geoeffnet auf DEMSELBEN Text (ckConcatToFormat); nil oder
    // nicht offen = kein Format-Eintrag, die anderen bleiben.
    class function Run(ALines: TStrings; const AContext: TEditorContext;
      APlaces: TSourcePlaces = nil): TArray<TRdxContextOutcome>; static;
    // Lohnt sich der Quellstellen-Dienst (ein Parse) am Caret? True, wenn
    // auf der Caret-Zeile oder einer Nachbarzeile ein '+' als Code steht -
    // ohne das steht am Caret keine Kette (C16). Dieselbe Vorprobe macht
    // Run selbst; der Anbieter oeffnet den Dienst nur dann.
    class function WantsPlaces(ALines: TStrings;
      const AContext: TEditorContext): Boolean; static;
    // Menuetext der Arten ohne Fund-Hilfe (C7/C8 ausser ckGuardClause),
    // uebersetzt; '' fuer die anderen - deren Text baut
    // uRdxFixTable.ContextCaption aus der Fund-Hilfe (F2).
    class function CaptionOf(const AOutcome: TRdxContextOutcome): string;
      static;
  end;

const
  // Menuetext von ckConcatToFormat - die msgid von CAP_FORMAT des SCA044-
  // Rezepts in uRdxProvider (Dedup per Caption, F2). Uebersetzt wird er in
  // uRdxFixTable.ContextCaption (eigene Konstante dort: der Extraktor loest
  // Konstanten nur in ihrer Unit auf); uTestRdxContextFormat prueft, dass
  // alle drei gleich lauten.
  CONTEXT_FORMAT_CAPTION = 'Build Format() from concatenation';

implementation

uses
  System.SysUtils,   // LowerCase, Trim, LastDelimiter, FreeAndNil
  uAstNode,          // TNodeKind
  uRefactorInfo,     // TRefactorInfo, TRefactorSpan, ROLE_*
  uRdxCodeMap,       // TRdxCodeMap
  uRdxMagicFixes,    // IntroduceAt, FileReason, IncludeReason
  uRdxTryFixes,      // CreateAt
  uRdxRecipes,       // CollapseWhitespace
  uRdxPlacesRunner,  // DescribeAnchor, FormatRewrite, UsesNamesOf (C16)
  uRdxIfFixes,       // InvertIf, SplitIf, MergeIf (C7/C8)
  uRdxCondFixes,     // DeMorgan, FlipCompare (C8)
  uRdxDeepNestingFix, // GuardAt (C7, Kette von SCA018)
  uRdxText;          // _ (Texte in der Sprache der SCA, E29)

const
  // Die Hinweise sind dieselben msgids wie die der Fund-Hilfen - die
  // Uebersetzung steht schon in i18n/*.po: R_MAGIC_HINT (uRdxFixTable,
  // SCA014) und FIX_HINTS der Zeile MissingFinally (SCA009). Zieht dort
  // ein Wortlaut um, muss er hier mit (sonst nur ein anderer Hinweis, die
  // Dedup haengt am Menuetext).
  R_CONST_HINT = 'same meaning - the constant %s holds the literal; rename '
    + 'it by hand or with Refactor > Rename (Ctrl+Shift+E)';
  R_TRY_HINT = 'Free now also runs on an exception and on Exit - the lines '
    + 'in between move into the try part';
  // C7: der Hinweis der Fund-Hilfe SCA018 (FIX_HINTS, Zeile DeepNesting).
  R_GUARD_HINT = 'same meaning - the condition is evaluated once as before; '
    + 'if it is false, the routine ends as before; the body moves out one '
    + 'level';
  // C7/C8 (Charge C78): Menuetexte und Hinweise der Arten ohne Fund-Hilfe.
  CAP_INVERT_IF = 'Invert the if (swap then and else)';
  CAP_DEMORGAN = 'Apply De Morgan to "%s"';
  CAP_FLIP = 'Swap the sides of "%s"';
  CAP_SPLIT_IF = 'Split the if at "and"';
  R_INVERT_HINT = 'same meaning - the condition is negated once, then and '
    + 'else swap places';
  R_DEMORGAN_HINT = 'same meaning - the same terms in the same order, each '
    + 'negated; the evaluation stops at the same term';
  R_FLIP_HINT = 'same meaning - the comparison is mirrored; neither side '
    + 'calls a routine';
  R_ANDIF_HINT = 'same meaning with short-circuit evaluation ({$B-}): the '
    + 'second condition is evaluated only if the first one is true, as '
    + 'before';

// Haengt AOutcome an AList an.
procedure AddOutcome(var AList: TArray<TRdxContextOutcome>;
  const AOutcome: TRdxContextOutcome);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AOutcome;
end;

// "Lokale Konstante einfuehren" fuer das Zahl-Literal an ACol.
procedure AddIntroduceConst(var AList: TArray<TRdxContextOutcome>;
  AMap: TRdxCodeMap; const AFileName: string; ALine, ACol: Integer);
var
  Plan : TRdxMagicPlan;
  Why  : string;
  O    : TRdxContextOutcome;
begin
  // Kein Kandidat (F4; auch ein triviales Literal) bzw. eine Sperre der
  // ganzen Datei (Plan.FileWide: FPC-Weiche, Skript, Spuren alter
  // Compiler): kein Eintrag.
  if not TRdxMagicFixes.IntroduceAt(AMap, ALine, ACol, Plan, Why)
     and ((Why = '') or Plan.FileWide) then
    Exit;
  // Was nur die Platte weiss, wie MagicCheck der Tabelle (FileReason
  // prueft den Netzpfad selbst, vor jedem Plattenzugriff) - auch das gilt
  // der ganzen Datei: kein Eintrag, auch vor einer Sperre der Stelle.
  if (TRdxMagicFixes.FileReason(AFileName, lfInlineConst) <> '')
     or (TRdxMagicFixes.IncludeReason(AFileName, AMap, lfInlineConst) <> '') then
    Exit;
  O := Default(TRdxContextOutcome);
  O.Kind := ckIntroduceConst;
  O.Name := Plan.Value;
  O.Enabled := Why = '';
  if O.Enabled then
  begin
    O.Edits := Plan.Edits;
    O.Hint := _(R_CONST_HINT, [Plan.Name]);
  end
  else
    O.Reason := Why;
  AddOutcome(AList, O);
end;

// C3 "try/finally um Create" fuer die Erzeugung auf ALine.
procedure AddTryFinallyCreate(var AList: TArray<TRdxContextOutcome>;
  AMap: TRdxCodeMap; ALine, ACol: Integer);
var
  Plan : TRdxTryPlan;
  Why  : string;
  O    : TRdxContextOutcome;
begin
  if not TRdxTryFixes.CreateAt(AMap, ALine, ACol, Plan, Why)
     and (Why = '') then
    Exit;   // kein Kandidat oder schon geschuetzt
  O := Default(TRdxContextOutcome);
  O.Kind := ckTryFinallyCreate;
  O.Name := Plan.Name;
  O.Enabled := Why = '';
  O.ChangesBehavior := True;
  if O.Enabled then
  begin
    AddEdit(O.Edits, Plan.Edit);
    O.Hint := _(R_TRY_HINT);
  end
  else
    O.Reason := Why;
  AddOutcome(AList, O);
end;

const
  // So viele Zeilen sucht ckConcatToFormat von einer Fortsetzungszeile
  // aufwaerts nach dem Anfang der Anweisung (C16).
  MAX_CHAIN_LINES = 30;
  // Umwandlungen nach String (C16): mit einem Literal daneben ist die
  // Kette ein Kandidat - 'Anzahl: ' + IntToStr(N). Unqualifiziert oder
  // hinter einem Unit-Namen der RTL (CONVERSION_UNITS); dazu x.ToString.
  CONVERSION_FUNCS: array[0..15] of string = ('inttostr', 'uinttostr',
    'inttohex', 'floattostr', 'floattostrf', 'formatfloat', 'currtostr',
    'currtostrf', 'formatcurr', 'booltostr', 'datetostr', 'timetostr',
    'datetimetostr', 'formatdatetime', 'vartostr', 'guidtostring');
  CONVERSION_UNITS: array[0..3] of string = ('sysutils', 'system.sysutils',
    'variants', 'system.variants');

// True, wenn ALine auf ';' endet (das letzte Zeichen, das kein Leerraum
// und kein Kommentar ist, ist ein ';' im Code): dort endet eine
// Anweisung, die Zeile darunter setzt sie nicht fort.
function EndsStatement(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  S : string;
  c : Integer;
begin
  Result := False;
  S := AMap.Raw(ALine);
  for c := Length(S) downto 1 do
    if (S[c] > ' ') and (AMap.ClassAt(ALine, c) <> 'k') then
      Exit((S[c] = ';') and AMap.IsCode(ALine, c));
end;

// Die Vorprobe von WantsPlaces: ein '+' als Code auf ALine oder einer
// Nachbarzeile.
function PlusNear(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L, c : Integer;
  S    : string;
begin
  Result := False;
  for L := ALine - 1 to ALine + 1 do
  begin
    if (L < 1) or (L > AMap.LineCount) then Continue;
    S := AMap.Raw(L);
    for c := 1 to Length(S) do
      if (S[c] = '+') and AMap.IsCode(L, c) then
        Exit(True);
  end;
end;

// True fuer AName in AList.
function InList(const AName: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(AList) to High(AList) do
    if AName = AList[i] then
      Exit(True);
end;

// True fuer eine Umwandlung nach String als ganzen Term: 'IntToStr(N)',
// 'SysUtils.FloatToStr(X)', 'N.ToString', 'N.ToString()'.
function IsConversionTerm(const AText: string): Boolean;
var
  T, Head, Qual : string;
  P, i          : Integer;
begin
  Result := False;
  T := LowerCase(Trim(AText));
  if (Copy(T, Length(T) - 8, 9) = '.tostring')
     or (Copy(T, Length(T) - 10, 11) = '.tostring()') then
    Exit(True);
  P := Pos('(', T);
  if (P < 2) or (T[Length(T)] <> ')') then Exit;
  Head := Trim(Copy(T, 1, P - 1));
  Qual := '';
  i := LastDelimiter('.', Head);
  if i > 0 then
  begin
    Qual := Copy(Head, 1, i - 1);
    Head := Copy(Head, i + 1, MaxInt);
  end;
  Result := InList(Head, CONVERSION_FUNCS)
    and ((Qual = '') or InList(Qual, CONVERSION_UNITS));
end;

// Die Beschreibung ist eine '+'-Kette: Ziel (bzw. Aufrufkopf) und
// mindestens zwei Terme, jeder Literal oder Operand (kein ROLE_ARGUMENT -
// ein Aufruf mit mehreren Argumenten).
function IsChainShape(AInfo: TRefactorInfo): Boolean;
var
  i : Integer;
begin
  Result := (Length(AInfo.Parts) >= 3)
    and (AInfo.Parts[0].Role = ROLE_TARGET);
  if not Result then Exit;
  for i := 1 to High(AInfo.Parts) do
    if (AInfo.Parts[i].Role <> ROLE_LITERAL)
       and (AInfo.Parts[i].Role <> ROLE_OPERAND) then
      Exit(False);
end;

// Der Caret steht zwischen dem ersten und dem letzten Term der Kette oder
// direkt dahinter (EndCol zeigt hinter das letzte Zeichen).
function CaretInChain(AInfo: TRefactorInfo; ALine, ACol: Integer): Boolean;
var
  First, Last : TRefactorSpan;
begin
  First := AInfo.Parts[1];
  Last  := AInfo.Parts[High(AInfo.Parts)];
  Result := ((ALine > First.StartLine)
      or ((ALine = First.StartLine) and (ACol >= First.StartCol)))
    and ((ALine < Last.EndLine)
      or ((ALine = Last.EndLine) and (ACol <= Last.EndCol)));
end;

// Kandidat (F4, C16): mindestens zwei Literale, oder ein Literal und eine
// Umwandlung nach String.
function IsConcatCandidate(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo): Boolean;
var
  i, Lits : Integer;
  Conv    : Boolean;
begin
  Lits := 0;
  Conv := False;
  for i := 1 to High(AInfo.Parts) do
    if AInfo.Parts[i].Role = ROLE_LITERAL then
      Inc(Lits)
    else if IsConversionTerm(APlaces.TextOf(AInfo.Parts[i])) then
      Conv := True;
  Result := (Lits >= 2) or ((Lits >= 1) and Conv);
end;

// Die Zeile der Anweisung am Caret: ALine selbst, wenn dort ein Knoten
// steht, auf einer Fortsetzungszeile die erste Zeile darueber mit einem
// Knoten (hoechstens MAX_CHAIN_LINES, nicht ueber ein ';' hinweg). Die
// Knoten sind die Zuweisungen der Zeile, ohne eine die Aufrufe (AAnchor
// 'assign' bzw. 'call'). 0 ohne Knoten.
function StatementLineAt(AMap: TRdxCodeMap; APlaces: TSourcePlaces;
  ALine: Integer; out ANodes: TArray<TNodeRef>; out AAnchor: string): Integer;
begin
  Result := ALine;
  repeat
    AAnchor := 'assign';
    ANodes := APlaces.NodesAt(Result, [TNodeKind.nkAssign]);
    if Length(ANodes) = 0 then
    begin
      AAnchor := 'call';
      ANodes := APlaces.NodesAt(Result, [TNodeKind.nkCall]);
    end;
    if Length(ANodes) > 0 then Exit;
    if (Result = 1) or (ALine - Result + 1 >= MAX_CHAIN_LINES)
       or EndsStatement(AMap, Result - 1) then
      Exit(0);
    Dec(Result);
  until False;
end;

// Die Kette am Caret (ALine, ACol): genau EINE Zuweisung (sonst genau ein
// Aufruf) auf der Zeile der Anweisung (StatementLineAt), beschrieben wie
// bei SCA044 (DescribeAnchor: ChainOf mit der '+'-Zahl des Knotens bzw.
// CallOf), als Kette, die den Caret enthaelt. nil sonst; der Aufrufer
// besitzt das Ergebnis.
function ChainAt(AMap: TRdxCodeMap; APlaces: TSourcePlaces;
  ALine, ACol: Integer): TRefactorInfo;
var
  L      : Integer;
  Nodes  : TArray<TNodeRef>;
  Anchor : string;
  IsCall : Boolean;
  Why    : string;
begin
  Result := nil;
  L := StatementLineAt(AMap, APlaces, ALine, Nodes, Anchor);
  // Mehrere Anweisungen auf der Zeile: wie bei SCA044 mehrdeutig.
  if (L = 0) or (Length(Nodes) <> 1) then Exit;
  Result := TRdxPlacesRunner.DescribeAnchor(APlaces, L, Anchor, IsCall, Why);
  // Why neben einer Beschreibung: die Kette zerfaellt anders, als der
  // Parser sie sieht - keine Kette.
  if Assigned(Result) and ((Why <> '') or not IsChainShape(Result)
     or not CaretInChain(Result, ALine, ACol)) then
    FreeAndNil(Result);
end;

// Der Eintrag zu einem Ergebnis von FormatRewrite; ATarget fuer Name.
function FormatOutcomeOf(const AOutcome: TRdxFormatOutcome;
  const ATarget: string): TRdxContextOutcome;
var
  Edit : TRdxEdit;
begin
  Result := Default(TRdxContextOutcome);
  Result.Kind := ckConcatToFormat;
  Result.Name := ATarget;
  Result.Enabled := AOutcome.Enabled;
  if not Result.Enabled then
  begin
    Result.Reason := AOutcome.Reason;
    Exit;
  end;
  Edit := Default(TRdxEdit);
  Edit.Span     := AOutcome.Span;
  Edit.Expected := AOutcome.Expected;
  Edit.NewText  := AOutcome.NewText;
  AddEdit(Result.Edits, Edit);
  // Zweite Ersetzung: System.SysUtils in die uses-Klausel (wie das Rezept
  // des Anbieters; ReplaceSpans sortiert selbst).
  if AOutcome.NeedsUses then
    AddEdit(Result.Edits, AOutcome.UsesEdit);
  Result.Hint := AOutcome.Hint;
end;

// C16 "Format() aus Verkettung bilden" fuer die Kette am Caret.
procedure AddConcatToFormat(var AList: TArray<TRdxContextOutcome>;
  AMap: TRdxCodeMap; APlaces: TSourcePlaces; ALine, ACol: Integer);
var
  Info    : TRefactorInfo;
  Outcome : TRdxFormatOutcome;
begin
  if not Assigned(APlaces) or not APlaces.IsOpen
     or not PlusNear(AMap, ALine) then
    Exit;
  Info := ChainAt(AMap, APlaces, ALine, ACol);
  if not Assigned(Info) then Exit;
  try
    if not IsConcatCandidate(APlaces, Info) then Exit;
    Outcome := TRdxPlacesRunner.FormatRewrite(APlaces, Info, '',
      TRdxPlacesRunner.UsesNamesOf(APlaces));
    // Nur Literale (hinter 'X +'): kein Kandidat; die Datei vertraegt die
    // uses-Ergaenzung nicht: gilt jeder Kette - beides kein Eintrag.
    if not Outcome.Enabled and (Outcome.NoOperand or Outcome.FileWide) then
      Exit;
    AddOutcome(AList, FormatOutcomeOf(Outcome,
      TRdxRecipes.CollapseWhitespace(APlaces.TextOf(Info.Parts[0]))));
  finally
    Info.Free;
  end;
end;

// Ein Eintrag aus dem Ergebnis eines C7/C8-Planers: kein Kandidat (False,
// AWhy leer) -> nichts; sonst freigegeben mit AEdits und AHint bzw.
// gesperrt mit AWhy.
procedure AddPlanned(var AList: TArray<TRdxContextOutcome>;
  AKind: TRdxContextKind; AOk: Boolean; const AWhy, AName, AHint: string;
  const AEdits: TArray<TRdxEdit>);
var
  O : TRdxContextOutcome;
begin
  if not AOk and (AWhy = '') then
    Exit;
  O := Default(TRdxContextOutcome);
  O.Kind := AKind;
  O.Name := AName;
  O.Enabled := AOk;
  if AOk then
  begin
    O.Edits := AEdits;
    O.Hint := AHint;
  end
  else
    O.Reason := AWhy;
  AddOutcome(AList, O);
end;

// Die sechs C7/C8-Aktionen am Caret, in der Reihenfolge von TRdxContextKind.
procedure AddIfActions(var AList: TArray<TRdxContextOutcome>;
  AMap: TRdxCodeMap; ALine, ACol: Integer);
var
  Ok    : Boolean;
  Why   : string;
  Op    : string;
  Edit  : TRdxEdit;
  Edits : TArray<TRdxEdit>;
begin
  Ok := TRdxIfFixes.InvertIf(AMap, ALine, ACol, Edits, Why);
  AddPlanned(AList, ckInvertIf, Ok, Why, '', _(R_INVERT_HINT), Edits);
  Edits := nil;
  Ok := TRdxDeepNestingFix.GuardAt(AMap, ALine, ACol, Edit, Why);
  if Ok then
    AddEdit(Edits, Edit);
  AddPlanned(AList, ckGuardClause, Ok, Why, '', _(R_GUARD_HINT), Edits);
  Edits := nil;
  Ok := TRdxCondFixes.DeMorgan(AMap, ALine, ACol, Edit, Op, Why);
  if Ok then
    AddEdit(Edits, Edit);
  AddPlanned(AList, ckDeMorgan, Ok, Why, Op, _(R_DEMORGAN_HINT), Edits);
  Edits := nil;
  Ok := TRdxCondFixes.FlipCompare(AMap, ALine, ACol, Edit, Op, Why);
  if Ok then
    AddEdit(Edits, Edit);
  AddPlanned(AList, ckFlipCompare, Ok, Why, Op, _(R_FLIP_HINT), Edits);
  Edits := nil;
  Ok := TRdxIfFixes.SplitIf(AMap, ALine, ACol, Edit, Why);
  if Ok then
    AddEdit(Edits, Edit);
  AddPlanned(AList, ckSplitIf, Ok, Why, '', _(R_ANDIF_HINT), Edits);
end;

class function TRdxContextRunner.CaptionOf(
  const AOutcome: TRdxContextOutcome): string;
begin
  case AOutcome.Kind of
    ckInvertIf:    Result := _(CAP_INVERT_IF);
    ckDeMorgan:    Result := _(CAP_DEMORGAN, [AOutcome.Name]);
    ckFlipCompare: Result := _(CAP_FLIP, [AOutcome.Name]);
    ckSplitIf:     Result := _(CAP_SPLIT_IF);
  else
    Result := '';
  end;
end;

class function TRdxContextRunner.WantsPlaces(ALines: TStrings;
  const AContext: TEditorContext): Boolean;
var
  Map : TRdxCodeMap;
begin
  Result := False;
  if not Assigned(ALines) or not AContext.IsValid
     or (AContext.Line > ALines.Count) then
    Exit;
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result := PlusNear(Map, AContext.Line);
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

class function TRdxContextRunner.Run(ALines: TStrings;
  const AContext: TEditorContext;
  APlaces: TSourcePlaces): TArray<TRdxContextOutcome>;
var
  Map : TRdxCodeMap;
  Col : Integer;
begin
  Result := nil;
  if not Assigned(ALines) or not AContext.IsValid
     or (AContext.Line > ALines.Count) then
    Exit;
  Map := TRdxCodeMap.Acquire(ALines);
  try
    // Virtueller Raum hinter dem Zeilenende: wie das Zeilenende.
    Col := AContext.Col;
    if Col > Length(Map.Raw(AContext.Line)) + 1 then
      Col := Length(Map.Raw(AContext.Line)) + 1;
    AddIntroduceConst(Result, Map, AContext.FileName, AContext.Line, Col);
    AddTryFinallyCreate(Result, Map, AContext.Line, Col);
    AddConcatToFormat(Result, Map, APlaces, AContext.Line, Col);
    AddIfActions(Result, Map, AContext.Line, Col);
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

end.
