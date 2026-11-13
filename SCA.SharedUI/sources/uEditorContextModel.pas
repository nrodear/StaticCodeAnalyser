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
//
// Schliessen aus der Fund-Navigation (2026-11-13): DecideModuleClose
// entscheidet, ob uIDEEditorIntegration ein Modul OHNE die Rueckfrage der
// IDE schliessen darf. Die IDE fuehrt eine Unit auch dann als geaendert,
// wenn nur sie selbst Units des Formulars in die uses-Klausel eingetragen
// hat - wer dann nur einen Fund anklickt, soll nicht gefragt werden. Ohne
// Rueckfrage geht es NUR, wenn fuer jeden als geaendert gefuehrten Editor
// die Inhaltsgleichheit bewiesen ist (mit der Datei oder mit dem
// Vergleichsstand, den die Navigation direkt nach ihrem Sprung festhaelt);
// jeder Zweifel heisst fragen. Der Host liest Puffer und Platte, diese Unit
// vergleicht nur (BufferMatchesDisk) und entscheidet.

interface

uses
  System.SysUtils,   // TBytes
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

  // Art eines Datei-Editors eines Moduls: Quelltext (IOTASourceEditor - die
  // Unit, oder eine DFM in der Textansicht), Formular-Designer
  // (IOTAFormEditor) oder etwas, das der Host nicht kennt.
  TModuleEditorKind = (mekSource, mekForm, mekOther);

  // Ein Datei-Editor, wie der Host ihn unmittelbar vor dem Schliessen
  // gelesen hat. Die Vergleichsfelder zaehlen nur fuer einen GEAENDERTEN
  // Quelltext-Editor; der Host fuellt sie nur, wenn er sie belegt hat
  // (Default(TModuleEditorState) heisst: nichts belegt).
  TModuleEditorState = record
    Kind               : TModuleEditorKind;
    // IOTAEditor.Modified - die IDE fragte beim Schliessen nach.
    Modified           : Boolean;
    // Der Puffertext wurde gelesen (ein leerer Puffer ist gelesen).
    BufferRead         : Boolean;
    // Puffer inhaltsgleich mit der Datei auf der Platte (BufferMatchesDisk).
    EqualsDisk         : Boolean;
    // Es gibt einen Vergleichsstand: Puffertext und Dateiinhalt zu einem
    // Zeitpunkt, an dem der Puffer nachweislich nichts vom Nutzer trug,
    // aber schon alles, was die IDE selbst eintraegt.
    HasBaseline        : Boolean;
    // Puffer bytegleich mit dem Puffertext des Vergleichsstands.
    EqualsBaseline     : Boolean;
    // Die Datei auf der Platte ist bytegleich mit der zum Vergleichsstand.
    // Ohne das bewiese EqualsBaseline nichts mehr: nach einem Speichern
    // dazwischen waere ein von Hand zurueckgenommener Stand Nutzerarbeit.
    DiskAsAtBaseline   : Boolean;
  end;

  TModuleCloseDecision = (
    // Kein Editor gilt als geaendert: normal schliessen, die IDE fragt nicht.
    mcdPlain,
    // Geaendert gefuehrt, aber nachweislich nichts vom Nutzer: ohne
    // Rueckfrage schliessen, die Aenderungen der IDE verfallen.
    mcdForce,
    // Eine Nutzeraenderung ist nicht ausgeschlossen: die IDE fragt.
    mcdAsk);

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

// Bytegleich, gleiche Laenge. Zwei leere Folgen sind gleich.
function SameBytes(const A, B: TBytes): Boolean;

// Ist der Editor-Puffer (UTF-8-Bytes ohne BOM, wie IOTAEditReader sie
// liefert) inhaltsgleich mit den ROHEN Bytes der Datei? Geprueft wird jede
// Lesart, in der die IDE die Datei geladen haben kann:
//   UTF-8-BOM            die Bytes hinter dem BOM
//   UTF-16-BOM (LE/BE)   dekodiert und nach UTF-8 gewandelt
//   ohne BOM             die Bytes selbst (UTF-8, ASCII), sonst als ANSI
//                        (Codepage des Systems) dekodiert und nach UTF-8
// True nur bei Gleichheit unter einer dieser Lesarten. Eine falsche Lesart
// kann nur zu False fuehren (dann fragt die IDE) - fuer ein falsches True
// muesste der Puffer zufaellig genau die Fehldekodierung der Datei tragen.
function BufferMatchesDisk(const ABufferUtf8, ADiskBytes: TBytes): Boolean;

// Darf das Modul ohne Rueckfrage zu? AEditors: alle Datei-Editoren des
// Moduls. mcdForce nur, wenn mindestens einer als geaendert gilt und JEDER
// geaenderte ein gelesener Quelltext-Editor ist, dessen Puffer der Datei
// gleicht (EqualsDisk) oder dem Vergleichsstand bei unveraenderter Datei
// (HasBaseline, EqualsBaseline, DiskAsAtBaseline). Ein geaenderter
// Formular-Designer, ein unbekannter Editor, ein nicht gelesener Puffer
// oder ein fehlender Beleg: mcdAsk. Nichts geaendert (auch: keine
// Editoren): mcdPlain.
function DecideModuleClose(
  const AEditors: array of TModuleEditorState): TModuleCloseDecision;

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

function SameBytes(const A, B: TBytes): Boolean;
begin
  // Kurzschluss: @A[0] wird bei leeren Folgen nicht gebildet.
  Result := (Length(A) = Length(B))
    and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function HasPrefix(const ABytes: TBytes; const APrefix: array of Byte): Boolean;
var
  i : Integer;
begin
  Result := Length(ABytes) >= Length(APrefix);
  if Result then
    for i := 0 to High(APrefix) do
      if ABytes[i] <> APrefix[i] then
        Exit(False);
end;

function Utf8OfDecoded(AEncoding: TEncoding; const ABytes: TBytes;
  AOffset: Integer): TBytes;
// Die Bytes ab AOffset in AEncoding gelesen, als UTF-8 ohne BOM. Nichts
// hinter AOffset (eine Datei nur aus dem BOM): leer.
begin
  Result := nil;
  if Length(ABytes) <= AOffset then Exit;
  Result := TEncoding.UTF8.GetBytes(
    AEncoding.GetString(ABytes, AOffset, Length(ABytes) - AOffset));
end;

function BufferMatchesDisk(const ABufferUtf8, ADiskBytes: TBytes): Boolean;
const
  BOM_UTF8    : array[0..2] of Byte = ($EF, $BB, $BF);
  BOM_UTF16LE : array[0..1] of Byte = ($FF, $FE);
  BOM_UTF16BE : array[0..1] of Byte = ($FE, $FF);
begin
  if HasPrefix(ADiskBytes, BOM_UTF8) then
    Exit(SameBytes(ABufferUtf8,
      Copy(ADiskBytes, Length(BOM_UTF8), Length(ADiskBytes))));
  if HasPrefix(ADiskBytes, BOM_UTF16LE) or HasPrefix(ADiskBytes, BOM_UTF16BE) then
  begin
    // Eine halbe Code-Einheit am Ende: keine Lesart, die die IDE gehabt
    // haben kann.
    if Odd(Length(ADiskBytes)) then Exit(False);
    if HasPrefix(ADiskBytes, BOM_UTF16LE) then
      Exit(SameBytes(ABufferUtf8, Utf8OfDecoded(TEncoding.Unicode, ADiskBytes, 2)));
    Exit(SameBytes(ABufferUtf8,
      Utf8OfDecoded(TEncoding.BigEndianUnicode, ADiskBytes, 2)));
  end;
  if SameBytes(ABufferUtf8, ADiskBytes) then Exit(True);
  // Leere Datei, aber nicht leerer Puffer (oder umgekehrt): ungleich - und
  // GetString auf einer leeren Folge braucht es nicht.
  if (Length(ADiskBytes) = 0) or (Length(ABufferUtf8) = 0) then Exit(False);
  Result := SameBytes(ABufferUtf8, Utf8OfDecoded(TEncoding.ANSI, ADiskBytes, 0));
end;

function ProvenUnedited(const AEditor: TModuleEditorState): Boolean;
// Nur fuer einen geaenderten Editor gefragt.
begin
  Result := (AEditor.Kind = mekSource) and AEditor.BufferRead
    and (AEditor.EqualsDisk
      or (AEditor.HasBaseline and AEditor.EqualsBaseline
        and AEditor.DiskAsAtBaseline));
end;

function DecideModuleClose(
  const AEditors: array of TModuleEditorState): TModuleCloseDecision;
var
  i : Integer;
begin
  Result := mcdPlain;
  for i := 0 to High(AEditors) do
    if AEditors[i].Modified then
    begin
      if not ProvenUnedited(AEditors[i]) then Exit(mcdAsk);
      Result := mcdForce;
    end;
end;

end.
