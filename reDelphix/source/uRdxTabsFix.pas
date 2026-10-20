unit uRdxTabsFix;

// reDelphix - Editorhilfe SCA061 TabulationCharacter (Tab-Zeichen im
// Quelltext): die Tabs EINER Zeile werden durch Leerzeichen ersetzt.
//
// DETEKTOR (uTabulationCharacter): pro Zeile EIN Fund auf den ersten Tab
// ('Tab character at column N - ...'), und zwar unabhaengig davon, ob der
// Tab im Code, in einem String oder in einem Kommentar steht.
//
// UMFORMUNG: jeder Tab im CODE (Code-Sicht der TRdxCodeMap: Einrueckung und
// Leerraum zwischen Token) wird durch so viele Leerzeichen ersetzt, dass die
// Anzeigespalte bis zum naechsten Tabstopp erhalten bleibt (Tabweite
// TAB_WIDTH = 2, Delphi-Standard; die IDE-Einstellung wird NICHT gelesen).
// Ein Tab nach Leerzeichen springt also auf den naechsten Stopp, nicht um
// zwei weitere. Tabs in Strings und Kommentaren bleiben unangetastet (sie
// sind Inhalt, nicht Layout); sie zaehlen in der Spaltenrechnung mit
// derselben Tabweite. Der Planer meldet EINE Ersetzung vom ersten bis zum
// letzten Code-Tab der Zeile; der Text dazwischen bleibt wie er ist.
//
// SPERREN (lieber keine Hilfe als eine falsche): die Spalte der Meldung
// ist kein Tab oder nicht der erste der Zeile (Zeile verschoben), der ERSTE
// Tab der Zeile liegt in einem String oder Kommentar (der Fund bliebe
// stehen). Nur die gemeldete Zeile - der Massenmodus kommt spaeter.
//
// OHNE ToolsAPI. Der Adapter PlanTabs hat die Form von TRdxFixPlanner
// (uRdxFixTable); die Unit bindet uRdxFixTable bewusst nicht ein.

interface

uses
  System.Classes,    // TStrings
  uEngineApi,        // TSourcePlaces
  uMethodd12,        // TLeakFinding
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap,       // TRdxCodeMap
  uRdxRecipeRunner;  // TRdxFixOutcome

const
  // Tabweite der Umrechnung: Delphi-Standard, nicht die der IDE.
  TAB_WIDTH = 2;

type
  TRdxTabsFix = class
  public
    // SCA061: die Tabs im Code von ALine -> Leerzeichen bis zum naechsten
    // Tabstopp. Spalte aus der Meldung ('Tab character at column N').
    class function Tabs(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Adapter fuer FIX_ROWS (Form TRdxFixPlanner); APlaces und AUsesNames
// braucht die Hilfe nicht.
function PlanTabs(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxFixRunner;   // MapFix

const
  TAB = #9;
  SPAN_061 = 'sca061';
  R_TAB_MOVED = 'kein Tab an der gemeldeten Stelle - Zeile verschoben? '
    + 'Datei neu pruefen';
  R_TAB_NOT_CODE = 'der erste Tab der Zeile steht in einem String oder '
    + 'Kommentar - der bleibt unangetastet, die Hilfe liesse den Fund stehen';

class function TRdxTabsFix.Tabs(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L, S        : string;
  Col, First  : Integer;
  Last, i, V  : Integer;
  n           : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  Col := ColumnFromMessage(AMessage);
  if Col <= 0 then
  begin
    AReason := R_NO_COLUMN;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or (L[Col] <> TAB) or (Pos(TAB, L) <> Col) then
  begin
    AReason := R_TAB_MOVED;
    Exit;
  end;
  if not AMap.IsCode(ALine, Col) then
  begin
    AReason := R_TAB_NOT_CODE;
    Exit;
  end;
  // Erster und letzter Code-Tab; der Text dazwischen wird mitgefuehrt.
  First := Col;
  Last := Col;
  for i := Col to Length(L) do
    if (L[i] = TAB) and AMap.IsCode(ALine, i) then
      Last := i;
  // Anzeigespalte (0-basiert) vor First.
  V := 0;
  for i := 1 to First - 1 do
    if L[i] = TAB then
      Inc(V, TAB_WIDTH - (V mod TAB_WIDTH))
    else
      Inc(V);
  S := '';
  for i := First to Last do
    if L[i] <> TAB then
    begin
      S := S + L[i];
      Inc(V);
    end
    else
    begin
      n := TAB_WIDTH - (V mod TAB_WIDTH);
      if AMap.IsCode(ALine, i) then
        S := S + StringOfChar(' ', n)
      else
        S := S + TAB;
      Inc(V, n);
    end;
  AEdit.Span := TRefactorSpan.Make(SPAN_061, ALine, First, ALine, Last + 1);
  AEdit.Expected := Copy(L, First, Last + 1 - First);
  AEdit.NewText := S;
  Result := True;
end;

function PlanTabs(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTabsFix.Tabs);
end;

end.
