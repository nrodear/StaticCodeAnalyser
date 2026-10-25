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
//
// WANN EIN EINTRAG ENTSTEHT (F4): nur, wenn am Caret ein Kandidat steht -
// ein Zahl-Literal bzw. eine Zeile 'X := ..Create..', die noch nicht
// geschuetzt ist. Dann freigegeben mit Ersetzungen, oder gesperrt mit dem
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
//
// CARET: Zeichenspalte wie im Kontext (1-basiert, UTF-16, vor dem Zeichen
// Col); ein Caret im virtuellen Raum hinter dem Zeilenende (Col > Laenge +
// 1) zaehlt als Zeilenende (Plan B1, V3). Die Auswahl des Kontexts nutzt
// keine Aktion (F8).

interface

uses
  System.Classes,    // TStrings
  uFindingActions,   // TEditorContext
  uRdxBufferMath;    // TRdxEdit

type
  TRdxContextKind = (ckIntroduceConst, ckTryFinallyCreate);

  // Ein Eintrag am Caret.
  //   Kind     die Aktion
  //   Enabled  freigegeben (Edits gesetzt) bzw. gesperrt (Reason gesetzt)
  //   Name     fuer '%s' im Menuetext: das Literal wie im Quelltext bzw. X
  //            - auch, wenn gesperrt ist, soweit schon bekannt
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
    // eine Zeile ausserhalb des Texts: nil.
    class function Run(ALines: TStrings;
      const AContext: TEditorContext): TArray<TRdxContextOutcome>; static;
  end;

implementation

uses
  uRdxCodeMap,     // TRdxCodeMap
  uRdxMagicFixes,  // IntroduceAt, FileReason, IncludeReason
  uRdxTryFixes,    // CreateAt
  uRdxText;        // _ (Texte in der Sprache der SCA, E29)

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

class function TRdxContextRunner.Run(ALines: TStrings;
  const AContext: TEditorContext): TArray<TRdxContextOutcome>;
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
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

end.
