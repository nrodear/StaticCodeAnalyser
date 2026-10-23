unit uEditorContextModel;

{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}

// Reine Logik des Editor-Kontextmenues mit Code-Aktionen ohne Fund
// (Charge B, V2/V3; Entscheide Nico 2026-10-23 E14/E16, F1/F7/F8) - ohne
// VCL und ohne ToolsAPI, getestet in TestProject (uTestEditorContextModel).
//
// V3 Caret und Auswahl: uIDEEditorIntegration.TIDEEditor.ViewContext liest
// Caret (IOTAEditView.CursorPos) und Block (IOTAEditView.Block) in
// ANZEIGE-Spalten und rechnet sie per IOTAEditView.ConvertPos in
// TOTACharPos um. Dessen CharIndex zaehlt ZEICHEN der Zeile, 0-basiert, ein
// Tabulator ist EIN Zeichen - gemessen 2026-10-11 (VarNameProject, Sonde
// M10; reDelphix uRdxEditor.DisplayPosOf ist die Rueckrichtung). Diese Unit
// bekommt nur noch die Zeichen-Spalten (CharIndex + 1) und macht daraus die
// Auswahl des TEditorContext: KEINE Byte-Rechnung, kein Puffertext. Byte-
// Offsets braucht nur, wer den Puffer liest und schreibt (reDelphix,
// uRdxBufferMath.Utf8PrefixLength/OffsetOf) - der Host nicht.
//
// V2 Menue: EditorMenuWanted entscheidet, ob das Kontextmenue ueberhaupt
// Anbieter fragt; BuildEditorPopupModel baut das Modell (mit Kontext-
// aktionen ueber uFindingActionMenu.BuildEditorMenuModel, sonst wie bis
// Charge B nur die Fund-Aktionen); OmittedLineIndex sagt dem Zeichner
// (uIDEFindingActionMenu), wo die Hinweiszeile "%d weitere Funde" hingehoert
// - vor den Kontextteil, nicht ans Ende.

interface

uses
  uFindingActions, uFindingActionMenu;

type
  // Spiegel von ToolsAPI.TOTABlockType in DERSELBEN Reihenfolge
  // (btInclusive, btLine, btColumn, btNonInclusive, btUnknown; ToolsAPI.pas
  // Studio 23.0) - die Unit kennt die ToolsAPI nicht, der Host bildet per
  // case ab (uIDEEditorIntegration, BlockStyleOf).
  TEditorBlockStyle = (ebsInclusive, ebsLine, ebsColumn, ebsNonInclusive,
    ebsUnknown);

  // Ein Editor-Block, wie der Host ihn gelesen hat: Zeilen 1-basiert,
  // Spalten als ZEICHEN-Spalten 1-basiert (CharIndex + 1 aus ConvertPos).
  // EndCol ist das Blockende, wie der Block es meldet - ob es das letzte
  // Zeichen einschliesst, sagt Style (ApplyEditorBlock).
  TEditorBlockChars = record
    Style     : TEditorBlockStyle;
    StartLine : Integer;
    StartCol  : Integer;
    EndLine   : Integer;
    EndCol    : Integer;
  end;

const
  // Die Form des Editor-Kontextmenues (seit AH13): Trenner vor dem ersten
  // Eintrag, Kopfzeilen je Fund und vor den Kontextaktionen.
  EDITOR_MENU_OPTIONS : TFindingMenuOptions = [moLeadingSeparator, moHeaders];

// TOTACharPos.CharIndex (0-basiert) -> Zeichen-Spalte (1-basiert). Ein
// negativer Wert (unbelegt; SmallInt-Ueberlauf) ergibt 1, damit der Kontext
// gueltig bleibt.
function CharColOfIndex(ACharIndex: Integer): Integer;

// Setzt die Auswahl von ACtx aus ABlock (TEditorContext.SetSelection: Ende
// exklusiv). Liefert ACtx.HasSelection.
//   ebsNonInclusive  Ende wie gemeldet (zeigt hinter das letzte Zeichen)
//   ebsInclusive     Ende + 1 (das gemeldete Endzeichen gehoert dazu)
//   ebsLine          ganze Zeilen: (StartLine, 1) bis (EndLine + 1, 1)
//   ebsColumn        keine Auswahl (ein Spaltenblock ist kein Zeichen-
//                    bereich; F8: abgelehnt)
//   ebsUnknown       keine Auswahl
// Ein Ende vor dem Anfang (unbelegt, defensiv) wird vorher getauscht. Keine
// Auswahl -> SetSelection(0, 0, 0, 0): HasSelection False, Felder 0.
// Nicht geprueft: ob die Spalten hinter dem Zeilenende liegen (virtueller
// Raum) - der Kontext traegt keinen Text; der Anbieter, der die Datei liest,
// behandelt eine Spalte hinter dem Ende als Zeilenende.
function ApplyEditorBlock(var ACtx: TEditorContext;
  const ABlock: TEditorBlockChars): Boolean;

// Fragt das Editor-Kontextmenue ueberhaupt Anbieter? Ja, wenn ein Fund-
// Anbieter angemeldet ist oder - nur mit AContextActionsOn (Not-Aus
// [UI] Element.EditorContextActions) - ein Kontext-Anbieter.
function EditorMenuWanted(AContextActionsOn: Boolean): Boolean;

// Das Modell des Editor-Kontextmenues zur Caret-Stelle ACtx (Findings vom
// Aufrufer gesetzt). AContextActionsOn: Fund-Aktionen, dahinter die
// Kontextaktionen mit Kopfzeile AHeader (BuildEditorMenuModel - auch ohne
// Fund); sonst nur die Fund-Aktionen (BuildFindingMenuModel), wie bis
// Charge B. Leeres Modell, wenn EditorMenuWanted False ist (dann wird kein
// Anbieter gefragt). Form: EDITOR_MENU_OPTIONS. Fehler werfender Anbieter
// stehen in Errors (EStackExhausted/EAbort laufen durch).
function BuildEditorPopupModel(const ACtx: TEditorContext;
  AContextActionsOn: Boolean; const AHeader: string): TFindingMenuModel;

// Wo die Hinweiszeile zu Omitted (nicht gefragte Funde) eingefuegt wird:
// als Index in Entries, VOR dem Kontextteil (die Zeile gehoert zu den
// Funden). Ohne Kontextteil = Length(Entries), also ans Ende wie bisher.
function OmittedLineIndex(const AModel: TFindingMenuModel): Integer;

implementation

function CharColOfIndex(ACharIndex: Integer): Integer;
begin
  if ACharIndex < 0 then
    Result := 1
  else
    Result := ACharIndex + 1;
end;

function ApplyEditorBlock(var ACtx: TEditorContext;
  const ABlock: TEditorBlockChars): Boolean;
var
  SL, SC, EL, EC : Integer;
  T              : Integer;
begin
  SL := ABlock.StartLine;
  SC := ABlock.StartCol;
  EL := ABlock.EndLine;
  EC := ABlock.EndCol;
  if (EL < SL) or ((EL = SL) and (EC < SC)) then
  begin
    T  := SL;
    SL := EL;
    EL := T;
    T  := SC;
    SC := EC;
    EC := T;
  end;
  case ABlock.Style of
    ebsNonInclusive:
      Result := ACtx.SetSelection(SL, SC, EL, EC);
    ebsInclusive:
      Result := ACtx.SetSelection(SL, SC, EL, EC + 1);
    ebsLine:
      Result := ACtx.SetSelection(SL, 1, EL + 1, 1);
  else
    // ebsColumn, ebsUnknown: keine Auswahl
    Result := ACtx.SetSelection(0, 0, 0, 0);
  end;
end;

function EditorMenuWanted(AContextActionsOn: Boolean): Boolean;
begin
  Result := (TFindingActions.ProviderCount > 0)
    or (AContextActionsOn and (TFindingActions.ContextProviderCount > 0));
end;

// noinspection BooleanParam
// Der Schalter ist der Not-Aus des Hosts (GContextActionsOn) und waehlt
// nur zwischen zwei Modell-Erzeugern - zwei Funktionen verdoppelten den
// Aufrufer.
function BuildEditorPopupModel(const ACtx: TEditorContext;
  AContextActionsOn: Boolean; const AHeader: string): TFindingMenuModel;
begin
  if not EditorMenuWanted(AContextActionsOn) then
    Exit(Default(TFindingMenuModel));
  if AContextActionsOn then
    Result := BuildEditorMenuModel(ACtx, EDITOR_MENU_OPTIONS, AHeader)
  else
    Result := BuildFindingMenuModel(ACtx.Findings, EDITOR_MENU_OPTIONS);
end;

function OmittedLineIndex(const AModel: TFindingMenuModel): Integer;
begin
  Result := Length(AModel.Entries) - AModel.ContextEntryCount;
  if Result < 0 then
    Result := 0;
end;

end.
