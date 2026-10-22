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
// TAB_WIDTH = 2 - eine ANNAHME: die Option 'Tab stops' der IDE ist je
// Installation anders und wird NICHT gelesen; eine Datei, die mit Weite 4
// oder 8 ausgerichtet wurde, verliert die Ausrichtung von Fortsetzungs-
// zeilen und Kommentarspalten - nur Optik, keine Semantik; der Hinweis nennt
// die 2). Ein Tab nach Leerzeichen springt also auf den naechsten Stopp,
// nicht um zwei weitere. Tabs in Strings und Kommentaren bleiben
// unangetastet (sie sind Inhalt, nicht Layout); zwischen dem ersten und dem
// letzten Code-Tab zaehlen sie in der Spaltenrechnung mit derselben
// Tabweite. Der Planer meldet EINE Ersetzung vom ersten bis zum
// letzten Code-Tab der Zeile; der Text dazwischen bleibt wie er ist.
//
// SPERREN (lieber keine Hilfe als eine falsche): die Spalte der Meldung
// ist kein Tab oder nicht der erste der Zeile (Zeile verschoben), der ERSTE
// Tab der Zeile liegt in einem String oder Kommentar (der Fund bliebe
// stehen). Nur die gemeldete Zeile - der Massenmodus kommt spaeter.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanTabs (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  // Tabweite der Umrechnung: eine feste Annahme, nicht die der IDE (s. Kopf).
  TAB_WIDTH = 2;

type
  // Der Planer von SCA061 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxTabsFix = class
  public
    // SCA061: die Tabs im Code von ALine -> Leerzeichen bis zum naechsten
    // Tabstopp. Spalte aus der Meldung ('Tab character at column N').
    class function Tabs(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(), MsgNoColumn, MsgMovedSuffix (E29)

const
  TAB = #9;
  SPAN_061 = 'sca061';
  // Die Gruende als englische msgids (E29), uebersetzt mit _() aus
  // uRdxText; Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po. Das
  // Ende ' - Zeile verschoben? ...' haengt MsgMovedSuffix an.
  R_TAB_MOVED = 'no tab at the reported place';
  R_TAB_NOT_CODE = 'the first tab of the line is inside a string or comment '
    + '- it stays untouched, the help would leave the finding in place';

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
    AReason := MsgNoColumn;
    Exit;
  end;
  L := AMap.Raw(ALine);
  if (Col > Length(L)) or (L[Col] <> TAB) or (Pos(TAB, L) <> Col) then
  begin
    AReason := MsgMovedSuffix(_(R_TAB_MOVED));
    Exit;
  end;
  if not AMap.IsCode(ALine, Col) then
  begin
    AReason := _(R_TAB_NOT_CODE);
    Exit;
  end;
  // Erster und letzter Code-Tab; der Text dazwischen wird mitgefuehrt.
  First := Col;
  Last := Col;
  for i := Col to Length(L) do
    if (L[i] = TAB) and AMap.IsCode(ALine, i) then
      Last := i;
  // Anzeigespalte (0-basiert) vor First: davor steht kein Tab (First ist
  // der erste Tab der Zeile, s. oben), jedes Zeichen zaehlt eine Spalte.
  V := First - 1;
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

end.
