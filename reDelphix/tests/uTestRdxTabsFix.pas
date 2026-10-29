unit uTestRdxTabsFix;

// Editorhilfe SCA061 TabulationCharacter (uRdxTabsFix): Tabs der gemeldeten
// Zeile -> Leerzeichen bis zum naechsten Tabstopp, im Code und in
// Kommentaren; Tabs am Zeilenende entfallen. Tabweite aus den Nachbarzeilen
// (rwE29) und der ganzen Datei (rwE30), ohne Beweis 2. Erste Fixture auf
// Text (FPC-tauglich; Gegenproben: String, Direktive, mehrzeiliger String,
// verschobene Zeile, zwei Weiten); zweite - nur Delphi, reDelphix.Test - der
// Adapter der Tabelle (Hinweise) und der ECHTE Detektor (Rundlauf,
// Katalog-Beispiel). Tabs im Quelltext dieser Unit stehen als TAB = #9, in
// den Mustern aus Fundstellen als '~' (Tb).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTabsFix = class
  public
    [Test] procedure Indent_OneAndTwoTabs;
    [Test] procedure Indent_MixedWithSpaces;
    [Test] procedure Between_Tokens_NextTabStop;
    [Test] procedure StringTab_Stays_IndentFixed;
    [Test] procedure CodeTabsAroundStringTab;
    [Test] procedure FirstTabInString_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure NoColumn_NoHelp;
    [Test] procedure OnlyReportedLine_Changes;
    // rwE29: Tabweite aus den Nachbarzeilen.
    [Test] procedure Width8_ReasonCodeTable;
    [Test] procedure Width8_DirectiveBetweenSpaceLines;
    [Test] procedure Width8_SpaceTableAfterTab;
    [Test] procedure Width8_VarBlock;
    [Test] procedure TieWithDefault_KeepsDefault;
    // rwE30: Struktur, Datei, Weite 3, gleiches Ergebnis.
    [Test] procedure Width4_BlockBodyBelowBeginHead;
    [Test] procedure Width2_RoutineAlignsOnlyThere;
    [Test] procedure Width3_ProvenByFile;
    [Test] procedure Width3_NotByChance;
    [Test] procedure Width8_FileDecidesNeighbourTie;
    [Test] procedure Width8_FileBeyondNeighbours;
    [Test] procedure Width8_PureTabFile;
    [Test] procedure Width8_DeclColonNotAssignment;
    [Test] procedure TwoWidthsSameResult_Help;
    [Test] procedure TwoWidthsDiffer_NoHelp;
    [Test] procedure FileProfile_OncePerMap;
    // rwE30: Kommentare und Zeilenende.
    [Test] procedure BlockCommentIndent_Replaced;
    [Test] procedure LineCommentTab_Replaced;
    [Test] procedure CommentTable_DerivedWidth;
    [Test] procedure TrailingTab_Removed;
    [Test] procedure BlankLineWithTabs_Emptied;
    [Test] procedure DirectiveTab_NoHelp;
    [Test] procedure MultiLineStringTab_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxTabsDetector = class
  public
    [Test] procedure Plan_Hint_NamesWidth;
    [Test] procedure Plan_Hint_File;
    [Test] procedure Plan_Hint_LineEnd;
    [Test] procedure Plan_Adapter;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CommentsAndLineEnd_RoundTrip;
    [Test] procedure Detector_StringOnly_NoHelp;
    [Test] procedure Detector_CatalogExample;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uTabulationCharacter,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxTabsFix,
  uRdxText,              // _(), MsgNoColumn, MsgByHand (E29)
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  TAB = #9;
  // Teil des Grundes 'Zeile verschoben' (MsgMovedSuffix, seit rwE29 gleich).
  RS_MOVED = 'kein Tab an der gemeldeten Stelle';

// ---- Helfer ----

// Die Meldung wie der Detektor sie schreibt.
function TabMsg(ACol: Integer): string;
begin
  Result := Format('Tab character at column %d - use spaces for indentation '
    + '(consistency across editors).', [ACol]);
end;

// '~' als Tab: die Muster aus den Fundstellen bleiben lesbar.
function Tb(const S: string): string;
begin
  Result := StringReplace(S, '~', TAB, [rfReplaceAll]);
end;

// Die Zeilen mit '~' als Tab.
function TbJoin(const ALines: array of string): string;
begin
  Result := Tb(Join(ALines));
end;

// Die Hilfe fuer Zeile ALine: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxTabsFix.Tabs(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer Zeile ALine mit der Spalte ihres ersten Tabs.
function FixAt(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := Fix(ASource, ALine, TabMsg(Pos(TAB, SL[ALine - 1])), AReason);
  finally
    SL.Free;
  end;
end;

// Eine Zeile als Quelltext, Hilfe auf Zeile 1 mit der Spalte des ersten Tabs.
function FixLine(const ALine: string; out AReason: string): string;
begin
  Result := Fix(ALine, 1, TabMsg(Pos(TAB, ALine)), AReason);
end;

// Zeile ALine (1-basiert) von ASource.
function LineAt(const ASource: string; ALine: Integer): string;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := SL[ALine - 1];
  finally
    SL.Free;
  end;
end;

// Weite und Quelle von TabWidth fuer Zeile ALine von ASource.
function WidthOf(const ASource: string; ALine: Integer;
  out AFrom: TRdxTabWidthSource): Integer;
var
  Map   : TRdxCodeMap;
  Other : Integer;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxTabsFix.TabWidth(Map, ALine, AFrom, Other);
  finally
    Map.Free;
  end;
end;

// ---- Text ----

procedure TTestRdxTabsFix.Indent_OneAndTwoTabs;
var
  R : string;
begin
  Assert.AreEqual('  DoStuff;', FixLine(TAB + 'DoStuff;', R), R);
  Assert.AreEqual('    DoStuff;', FixLine(TAB + TAB + 'DoStuff;', R), R);
end;

procedure TTestRdxTabsFix.Indent_MixedWithSpaces;
var
  R : string;
begin
  // Ein Tab nach einem Leerzeichen springt nur bis zum naechsten Stopp.
  Assert.AreEqual('  X;', FixLine(' ' + TAB + 'X;', R), R);
  Assert.AreEqual('    X;', FixLine('  ' + TAB + 'X;', R), R);
  Assert.AreEqual('    X;', FixLine(TAB + ' ' + TAB + 'X;', R), R);
end;

procedure TTestRdxTabsFix.Between_Tokens_NextTabStop;
var
  R : string;
begin
  Assert.AreEqual('XY:=  1;', FixLine('XY:=' + TAB + '1;', R), R);
  Assert.AreEqual('abc d;', FixLine('abc' + TAB + 'd;', R), R);
end;

procedure TTestRdxTabsFix.StringTab_Stays_IndentFixed;
var
  R : string;
begin
  Assert.AreEqual('  S := ''a' + TAB + 'b'';',
    FixLine(TAB + 'S := ''a' + TAB + 'b'';', R), R);
end;

procedure TTestRdxTabsFix.CodeTabsAroundStringTab;
var
  R : string;
begin
  Assert.AreEqual('X ''a' + TAB + 'b''  ;',
    FixLine('X' + TAB + '''a' + TAB + 'b''' + TAB + ';', R), R);
end;

// Gegenprobe (rwE30): ein Tab in einem String bleibt Inhalt - steht er als
// erster in der Zeile, bliebe der Fund stehen; Sperre wie bisher.
procedure TTestRdxTabsFix.FirstTabInString_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', FixLine('S := ''a' + TAB + 'b'';', R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
  // Auch mit einem Tab am Zeilenende dahinter.
  Assert.AreEqual('', FixLine('S := ''a' + TAB + 'b'';' + TAB, R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
end;

procedure TTestRdxTabsFix.MovedLine_NoHelp;
var
  R : string;
begin
  // Spalte 1 ist kein Tab mehr; Zeile nicht mehr vorhanden; der Tab steht
  // weiter hinten, nicht an der gemeldeten Spalte.
  Assert.AreEqual('', Fix('  X;', 1, TabMsg(1), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(TAB + 'X;', 5, TabMsg(1), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
  Assert.AreEqual('', Fix(TAB + 'X;' + TAB, 1, TabMsg(4), R));
  Assert.IsTrue(Pos(RS_MOVED, R) > 0, R);
end;

procedure TTestRdxTabsFix.NoColumn_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(TAB + 'X;', 1, 'Tab character', R));
  Assert.AreEqual(MsgNoColumn, R);
end;

procedure TTestRdxTabsFix.OnlyReportedLine_Changes;
var
  R : string;
begin
  Assert.AreEqual(Join(['begin', '  A;', TAB + 'B;', 'end;']),
    Fix(Join(['begin', TAB + 'A;', TAB + 'B;', 'end;']), 2, TabMsg(1), R), R);
end;

// ---- Tabweite aus den Nachbarzeilen (rwE29) ----

// Indy IdSSLOpenSSLHeaders.pas:10183 (minimiert): die Tabelle ist fuer
// Tabweite 8 ausgerichtet - Namen verschiedener Laenge mit 3, 4 bzw. 5 Tabs
// enden alle mit '=' in Spalte 48. Gegenprobe: mit fester Weite 2 (bis
// rwE29) stuende '=' der Zeile in Spalte 24 (9 statt 33 Leerzeichen).
procedure TTestRdxTabsFix.Width8_ReasonCodeTable;
const
  T3 = TAB + TAB + TAB;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  {$EXTERNALSYM TS_R_BAD_PKCS7_TYPE}',
      '  TS_R_BAD_PKCS7_TYPE' + T3 + TAB + '= 132;',
      '  {$EXTERNALSYM TS_R_BAD_TYPE}',
      '  TS_R_BAD_TYPE' + StringOfChar(' ', 33) + '= 133;',
      '  {$EXTERNALSYM TS_R_CERTIFICATE_VERIFY_ERROR}',
      '  TS_R_CERTIFICATE_VERIFY_ERROR' + T3 + '= 100;',
      '  TS_R_COULD_NOT_SET_ENGINE' + T3 + '= 127;']),
    Fix(Join([
      '  {$EXTERNALSYM TS_R_BAD_PKCS7_TYPE}',
      '  TS_R_BAD_PKCS7_TYPE' + T3 + TAB + '= 132;',
      '  {$EXTERNALSYM TS_R_BAD_TYPE}',
      '  TS_R_BAD_TYPE' + T3 + TAB + TAB + '= 133;',
      '  {$EXTERNALSYM TS_R_CERTIFICATE_VERIFY_ERROR}',
      '  TS_R_CERTIFICATE_VERIFY_ERROR' + T3 + '= 100;',
      '  TS_R_COULD_NOT_SET_ENGINE' + T3 + '= 127;']), 4, TabMsg(16), R), R);
end;

// PascalScript uPSRuntime.pas:6469 (minimiert): '<TAB>      {$else}' steht
// bei Tabweite 8 in Spalte 14 wie die mit 14 Leerzeichen eingerueckten
// Code-Zeilen. Gegenprobe: mit fester Weite 2 rutschte '{$else}' auf
// Spalte 8.
procedure TTestRdxTabsFix.Width8_DirectiveBetweenSpaceLines;
var
  I14, R : string;
begin
  I14 := StringOfChar(' ', 14);
  Assert.AreEqual(Join([
      I14 + 'S := unaligned(P^);',
      TAB + '      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}',
      I14 + 'S := unaligned(Q^);',
      I14 + '{$else}',
      I14 + 'S := Q^;',
      TAB + '      {$endif}',
      I14 + 'Inc(N, SizeOf(Single));']),
    Fix(Join([
      I14 + 'S := unaligned(P^);',
      TAB + '      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}',
      I14 + 'S := unaligned(Q^);',
      TAB + '      {$else}',
      I14 + 'S := Q^;',
      TAB + '      {$endif}',
      I14 + 'Inc(N, SizeOf(Single));']), 4, TabMsg(1), R), R);
end;

// JVCL DirectShow9.pas:6829 (minimiert): Tab + 17 Leerzeichen bringen '='
// bei Tabweite 8 genau in Spalte 41 der mit Leerzeichen ausgerichteten
// Nachbarn. Gegenprobe: mit fester Weite 2 stuende '=' in Spalte 35.
procedure TTestRdxTabsFix.Width8_SpaceTableAfterTab;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
      '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
      '  ED_EDIT_PREREAD' + StringOfChar(' ', 24) + '= ED_BASE+815;',
      '//']),
    Fix(Join([
      '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
      '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
      '  ED_EDIT_PREREAD' + TAB + StringOfChar(' ', 17) + '= ED_BASE+815;',
      '//']), 3, TabMsg(18), R), R);
end;

// JVCL gifimage.pas:8067 (minimiert): der var-Block ist fuer Tabweite 8
// ausgerichtet (':' in Spalte 24 hinter 2 bzw. 3 Tabs). Gegenprobe: mit
// fester Weite 2 stuende ':' der Zeile in Spalte 12.
procedure TTestRdxTabsFix.Width8_VarBlock;
const
  T2 = TAB + TAB;
var
  R : string;
begin
  Assert.AreEqual(Join([
      '  var',
      '    i' + T2 + TAB + ': integer;',
      '    Cache' + StringOfChar(' ', 15)
        + ': array[0..CacheSize-1] of TCacheEntry;',
      '    LastEntry' + T2 + ': integer;',
      '    Scanline' + T2 + ': PRGBTriple;']),
    Fix(Join([
      '  var',
      '    i' + T2 + TAB + ': integer;',
      '    Cache' + T2 + ': array[0..CacheSize-1] of TCacheEntry;',
      '    LastEntry' + T2 + ': integer;',
      '    Scanline' + T2 + ': PRGBTriple;']), 3, TabMsg(10), R), R);
end;

// Passt die Nachbarzeile zur Vorgabe 2 und zu 4 gleich ('=' in Spalte 4),
// bleibt es bei 2. Pinnt die Regel; auch vor rwE29 gruen (immer 2).
procedure TTestRdxTabsFix.TieWithDefault_KeepsDefault;
var
  R : string;
begin
  Assert.AreEqual(Join(['AB  = 1;', 'ABC = 2;']),
    Fix(Join(['AB  = 1;', 'ABC' + TAB + '= 2;']), 2, TabMsg(4), R), R);
end;

// ---- Tabweite aus Struktur und Datei (rwE30) ----

// JVCL MainFm.pas:290/292 (minimiert): der Rumpf unter
// '  if .. then begin' ist mit Tabs eingerueckt, die Datei rueckt sonst in
// 2er-Stufen ein. Weite 2 legte ihn auf die Spalte des Kopfes (bis rwE30
// die Wahl: Anker in Spalte 2 bei den Koepfen), 8 springt um 6; nur 4 steht
// eine Stufe tiefer. Gegenprobe: bis rwE30 '  ctrl := ...' (Weite 2).
procedure TTestRdxTabsFix.Width4_BlockBodyBelowBeginHead;
var
  Src, R : string;
begin
  Src := TbJoin(['procedure P;', 'begin', '  if A then', '    B;',
    '  while C do', '    D;', '  if E then', '    F;',
    '  if tbDockRightSide.Checked then begin',
    '~ctrl := DockServer.RightDockPanel;', '~adef := alClient;',
    '  end else begin', '~ctrl := DockServer.CustomDockPanel;', '  end;',
    'end;']);
  Assert.AreEqual('    ctrl := DockServer.RightDockPanel;',
    LineAt(FixAt(Src, 10, R), 10), R);
  Assert.AreEqual('    ctrl := DockServer.CustomDockPanel;',
    LineAt(FixAt(Src, 13, R), 13), R);
end;

// JVCL JvaScrollText.pas:206 (die Routine): nur Weite 2 richtet sie aus
// ('  <TAB>if' gegen '    else', '    <TAB>with .. do' ueber
// '      begin', '    <TAB>end'); bei 4 und 8 stuende 'begin' links von
// seinem 'with .. do', bei 8 die Folgezeile von 'then' nicht tiefer.
// Gegenprobe: bis rwE30 Weite 8 ('Size' in Spalte 16) - Zufallstreffer
// '  <TAB><TAB>' gegen '    <TAB><TAB>'.
procedure TTestRdxTabsFix.Width2_RoutineAlignsOnlyThere;
var
  Src, R : string;
begin
  Src := TbJoin([
      '  function ChangeFont(S : string) : boolean;',
      '  var',
      '  ~msec : string[10];',
      '  begin',
      '  ~Result := true;',
      '  ~if StrLComp(''$Font:'', PChar(S), 6) = 0 then',
      '    ~with imageFont.Canvas.Font do',
      '      begin',
      '    ~~S := PChar(S)+6;',
      '    ~~Name := SubStr(S, 0, '';'');',
      '    ~~Size := StrToInt(SubStr(S, 1, '';''));',
      '    ~~Style := IntToStyle[StrToInt(SubStr(S, 2, '';''))];',
      '    ~end',
      '    else',
      '    if StrLComp(''$Pause'', PChar(S), 6) = 0 then',
      '    begin',
      '  ~~msec := Copy(S, 7, 16);',
      '  ~~try',
      '  ~~~Delay(StrToInt(msec));',
      '  ~~except',
      '  ~~end',
      '  ~end else',
      '      Result := false;',
      '  ~FontHeight := -imageFont.Canvas.Font.Height +3;',
      '  end;']);
  Assert.AreEqual('        Size := StrToInt(SubStr(S, 1, '';''));',
    LineAt(FixAt(Src, 11, R), 11), R);
end;

// GExperts ODRegExp.pas:121 (die Routinen, ohne Kommentarzeilen): die Datei
// rueckt mit Weite 3 ein ('<TAB>if' gegen '   else', '   <TAB>result' eine
// Stufe darunter). Gegenprobe: bis rwE30 gab es 3 nicht - Sperre (4 und 8
// legen 'result' unter das 'if', die Weite blieb offen).
procedure TTestRdxTabsFix.Width3_ProvenByFile;
var
  Src, R : string;
begin
  Src := TbJoin([
      'function ToUpper( c : char ) : char;',
      'begin',
      '~if (( c >= ''a'' ) and (c <=''z'')) then',
      '   ~result := char(integer(c) - 32)',
      '   else',
      '   ~result := c;',
      'end;',
      'function CmpChar( c1, c2 : char; csense : boolean ) : boolean;',
      'begin',
      '~if ( csense ) then',
      '   ~result := c1 = c2',
      '   else',
      '   ~result := ToUpper(c1) = ToUpper(c2);',
      'end;',
      'function IsAlphaNum( c : char ) : boolean;',
      'begin',
      '~result := ((c>= ''A'') and (c<=''Z''))',
      '   ~~~~or ((c >=''a'') and (c<=''z''))',
      '               or ((c>=''0'') and (c<=''9''));',
      'end;',
      'function AtEnd( const str : string; index : integer ) : boolean;',
      'begin',
      '~result := index > Length( str );',
      'end;']);
  Assert.AreEqual('      result := char(integer(c) - 32)',
    LineAt(FixAt(Src, 4, R), 4), R);
end;

// doublecmd dcxxhash.pas:298 (asm, minimiert): bei Weite 3 enden
// 'pxor<TAB>' und 'movdqu<TAB>' beide in Spalte 9 - ein Zufall, keine
// Einrueckung. Ohne Beleg der Datei bleibt 3 aussen vor, es gilt die
// Vorgabe 2. Gegenprobe: 3 als gewoehnlicher Kandidat (RARE-Regel in
// TabWidth entfernt) waehlt 3 ('movdqu %xmm5'); bis rwE30 ebenfalls 2.
procedure TTestRdxTabsFix.Width3_NotByChance;
var
  R : string;
begin
  Assert.AreEqual(Join(['  pxor' + TAB + '%xmm3, %xmm0',
      '  movdqu  %xmm5, %xmm2']),
    Fix(Join(['  pxor' + TAB + '%xmm3, %xmm0',
      '  movdqu' + TAB + '%xmm5, %xmm2']), 2, TabMsg(9), R), R);
end;

// Indy IdSSLOpenSSLHeaders.pas:10568: die Nachbarn der Zeile passen zu 4
// wie zu 8, der Rest der Tabelle (hier: der Datei) nur zu 8. Gegenprobe:
// bis rwE30 Sperre (zwei Weiten gleich gut).
procedure TTestRdxTabsFix.Width8_FileDecidesNeighbourTie;
var
  Src, R : string;
  From   : TRdxTabWidthSource;
begin
  Src := TbJoin([
      '  CMS_R_SMIME_TEXT_ERROR~~~~= 140;',
      '  {$EXTERNALSYM CMS_R_STORE_INIT_ERROR}',
      '  CMS_R_STORE_INIT_ERROR~~~~= 141;',
      '  {$EXTERNALSYM CMS_R_TYPE_NOT_COMPRESSED_DATA}',
      '  CMS_R_TYPE_NOT_COMPRESSED_DATA~~~= 142;',
      '  {$EXTERNALSYM CMS_R_TYPE_NOT_DATA}',
      '  CMS_R_TYPE_NOT_DATA~~~~= 143;',
      '  {$EXTERNALSYM CMS_R_TYPE_NOT_DIGESTED_DATA}',
      '  CMS_R_TYPE_NOT_DIGESTED_DATA~~~= 144;',
      '  {$EXTERNALSYM CMS_R_TYPE_NOT_ENCRYPTED_DATA}',
      '  CMS_R_TYPE_NOT_ENCRYPTED_DATA~~~= 145;',
      '  {$EXTERNALSYM CMS_R_TYPE_NOT_ENVELOPED_DATA}',
      '  CMS_R_TYPE_NOT_ENVELOPED_DATA~~~= 146;',
      '  {$EXTERNALSYM CMS_R_UNABLE_TO_FINALIZE_CONTEXT}',
      '  CMS_R_UNABLE_TO_FINALIZE_CONTEXT~~= 147;',
      '  {$EXTERNALSYM CMS_R_UNKNOWN_CIPHER}',
      '  CMS_R_UNKNOWN_CIPHER~~~~= 148;']);
  Assert.AreEqual('  CMS_R_TYPE_NOT_DIGESTED_DATA' + StringOfChar(' ', 18)
    + '= 144;', LineAt(FixAt(Src, 9, R), 9), R);
  Assert.AreEqual<Integer>(8, WidthOf(Src, 9, From));
  Assert.IsTrue(From = twFile, 'die Datei entscheidet');
end;

// JVCL gifimage.pas:1008: um '(ooCrop,<TAB><TAB><TAB>//' passen 4 und 8;
// nur 'dmNearest,<TAB><TAB><TAB>//' gegen 'dmFloydSteinberg,<TAB><TAB>//'
// zwoelf Zeilen darueber - ausserhalb der Nachbarzeilen - zeigt 8.
// Gegenprobe: bis rwE30 Sperre (zwei Weiten gleich gut).
procedure TTestRdxTabsFix.Width8_FileBeyondNeighbours;
var
  Src, R : string;
begin
  Src := TbJoin([
      '  TDitherMode =',
      '    (dmNearest,~~~// Nearest color matching w/o error correction',
      '     dmFloydSteinberg,~~// Floyd Steinberg Error Diffusion dithering',
      '     dmStucki,~~~// Stucki Error Diffusion dithering',
      '     dmSierra,~~~// Sierra Error Diffusion dithering',
      '     dmJaJuNI,~~~// Jarvis, Judice & Ninke Error Diffusion dithering',
      '     dmSteveArche,~~// Stevenson & Arche Error Diffusion dithering',
      '     dmBurkes~~~// Burkes Error Diffusion dithering',
      '     // dmOrdered,~~// Ordered dither',
      '    );',
      '',
      '  // Optimization options',
      '  TGIFOptimizeOption =',
      '    (ooCrop,~~~// Crop animated GIF frames',
      '     ooMerge,~~~// Merge pixels of same color',
      '     ooCleanup,~~~// Remove comments and application extensions',
      '     ooColorMap,~~// Sort color map by usage and remove unused entries',
      '     ooReduceColors~~// Reduce color depth ***NOT IMPLEMENTED***',
      '    );']);
  Assert.AreEqual('    (ooCrop,' + StringOfChar(' ', 20)
    + '// Crop animated GIF frames', LineAt(FixAt(Src, 14, R), 14), R);
end;

// Firebird.pas:3577 (minimiert): reine Tab-Datei; die Zeile und ihre
// Nachbarn ruecken mit genau einem Tab ein (kein Beleg), die Tabelle oben
// ('isc_arg_interpreted<TAB>=' gegen 'isc_arg_end<TAB><TAB>=') beweist 8.
// Gegenprobe: bis rwE30 die Vorgabe 2 ('  isc_io_error').
procedure TTestRdxTabsFix.Width8_PureTabFile;
var
  Src, R : string;
begin
  Src := TbJoin([
      '~isc_facility~~= 20;',
      '~isc_err_base~~= 335544320;',
      '~isc_err_factor~~= 1;',
      '~isc_arg_end~~= 0;~(* end of argument list *)',
      '~isc_arg_gds~~= 1;~(* generic DSRI status value *)',
      '~isc_arg_string~~= 2;~(* string argument *)',
      '~isc_arg_cstring~~= 3;~(* count & string argument *)',
      '~isc_arg_number~~= 4;~(* numeric argument (long) *)',
      '~isc_arg_interpreted~= 5;~(* interpreted status code (string) *)',
      '~isc_arg_vms~~= 6;~(* VAX/VMS status code (long) *)',
      '~isc_arg_unix~~= 7;~(* UNIX error code *)',
      '~isc_arg_domain~~= 8;~(* Apollo/Domain error code *)',
      '~isc_arg_dos~~= 9;~(* MSDOS/OS2 error code *)',
      '~isc_x0 = 0;', '~isc_x1 = 1;', '~isc_x2 = 2;', '~isc_x3 = 3;',
      '~isc_x4 = 4;', '~isc_x5 = 5;', '~isc_x6 = 6;', '~isc_x7 = 7;',
      '~isc_x8 = 8;',
      '~isc_io_error                         = 335544344;']);
  Assert.AreEqual('        isc_io_error                         = 335544344;',
    LineAt(FixAt(Src, 23, R), 23), R);
end;

// JVCL gifimage.pas:12280 (minimiert): '  i<TAB><TAB><TAB>: integer;' trifft
// bei Weite 4 das ':' von '      for i := 0' - ein Zufall; die Anker
// vergleichen darum zwei Zeichen (': ' gegen ':='). Die Datei (der
// var-Block oben, ausserhalb der Nachbarzeilen) zeigt 8. Gegenprobe: bis
// rwE30 Weite 4 ('  i         :'), ebenso mit nur einem Zeichen je Anker.
procedure TTestRdxTabsFix.Width8_DeclColonNotAssignment;
var
  Src, R : string;
begin
  Src := TbJoin(['procedure TGIFCache.Lookup;', '  var',
      '    i~~~: integer;',
      '    Cache~~: array[0..CacheSize-1] of TCacheEntry;',
      '    LastEntry~~: integer;', '    Scanline~~: PRGBTriple;', '  begin',
      '  end;', '', '', '', '', '', '', '', '', '', '',
      'procedure TGIFImage.PaintStart;', 'var', '  i~~~: integer;', 'begin',
      '  with FPainters.LockList do', '    try',
      '      for i := 0 to Count-1 do',
      '        TGIFPainter(Items[i]).Start;', '    finally',
      '      FPainters.UnLockList;', '    end;', 'end;']);
  Assert.AreEqual('  i' + StringOfChar(' ', 21) + ': integer;',
    LineAt(FixAt(Src, 21, R), 21), R);
end;

// JVCL JvUIBLib.pas:686 (minimiert): '  CLASS_ERROR<TAB>=' passt zu 4 wie zu
// 8 - beide setzen '=' in Spalte 16 wie die Nachbarn; dasselbe Ergebnis,
// also keine Sperre. Gegenprobe: bis rwE30 Sperre (zwei Weiten gleich gut;
// bis rwE30 als TwoWidthsAlike_NoHelp gepinnt).
procedure TTestRdxTabsFix.TwoWidthsSameResult_Help;
var
  R : string;
begin
  Assert.AreEqual(Join(['  CODE_MASK     = $0000FFFF;',
      '  CLASS_ERROR   = 0; // Code represents an error',
      '  CLASS_WARNING' + TAB + '= 1;']),
    Fix(Join(['  CODE_MASK     = $0000FFFF;',
      '  CLASS_ERROR' + TAB + '= 0; // Code represents an error',
      '  CLASS_WARNING' + TAB + '= 1;']), 2, TabMsg(14), R), R);
  Assert.AreEqual(Join(['X       = 1;', 'ABCDE   = 2;']),
    Fix(Join(['X       = 1;', 'ABCDE' + TAB + '= 2;']), 2, TabMsg(6), R), R);
end;

// Gegenprobe zu TwoWidthsSameResult_Help: eine Nachbarzeile passt zu 4
// ('=' in Spalte 12), eine zu 8 (Spalte 16), und die Ergebnisse
// unterscheiden sich - Sperre.
procedure TTestRdxTabsFix.TwoWidthsDiffer_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(Join(['X' + StringOfChar(' ', 11) + '= 1;',
    'ABCDE' + TAB + TAB + '= 2;', 'Y' + StringOfChar(' ', 15) + '= 3;']), 2,
    TabMsg(6), R));
  Assert.AreEqual(_(R_TAB_AMBIGUOUS, [4, 8, MsgByHand]), R);
end;

// LAUFZEIT: die Belege der Datei je Code-Sicht einmal - zwei Zeilen
// derselben Map rechnen sie einmal, eine neue Map neu.
procedure TTestRdxTabsFix.FileProfile_OncePerMap;
var
  Map, Map2 : TRdxCodeMap;
  N, Other  : Integer;
  Source    : TRdxTabWidthSource;
begin
  Map := NewMap(Join(['begin', TAB + 'A;', TAB + 'B;', 'end;']));
  Map2 := nil;
  try
    N := TRdxTabsFix.FileScans;
    TRdxTabsFix.TabWidth(Map, 2, Source, Other);
    TRdxTabsFix.TabWidth(Map, 3, Source, Other);
    Assert.AreEqual<Integer>(N + 1, TRdxTabsFix.FileScans);
    Map2 := NewMap(Join(['begin', TAB + 'A;', 'end;']));
    TRdxTabsFix.TabWidth(Map2, 2, Source, Other);
    Assert.AreEqual<Integer>(N + 2, TRdxTabsFix.FileScans);
  finally
    Map2.Free;
    Map.Free;
  end;
end;

// ---- Kommentare und Zeilenende (rwE30) ----

// Alcinoe.FBX.Base.pas:1117 und Setup.MainFunc.pas:2035 (minimiert): die
// Einrueckung einer Zeile im Blockkommentar wird ersetzt wie im Code; der
// Fund verschwindet (kein Tab mehr). Gegenprobe: bis rwE30 Sperre ('der
// erste Tab ... in einem String oder Kommentar').
procedure TTestRdxTabsFix.BlockCommentIndent_Replaced;
var
  R, S : string;
begin
  S := Fix(Join(['{ Kommentar', TAB + 'innen', '}']), 2, TabMsg(1), R);
  Assert.AreEqual(Join(['{ Kommentar', '  innen', '}']), S, R);
  S := FixAt(Join(['            except on E: ESevenZipError do',
    '              { Ignore archive errors for now, will show up with',
    TAB + '                installation }', '            end;']), 3, R);
  Assert.AreEqual('                  installation }', LineAt(S, 3), R);
  Assert.AreEqual<Integer>(0, Pos(TAB, S), 'der Fund verschwindet');
end;

// Alcinoe.FMX.Common.pas:6022, Xml.VerySimple.pas:156 (minimiert): ein Tab
// in einem Zeilenkommentar ohne Spaltenbezug wird ersetzt. Gegenprobe: bis
// rwE30 Sperre.
procedure TTestRdxTabsFix.LineCommentTab_Replaced;
var
  R, S : string;
begin
  Assert.AreEqual('X; // a b', FixLine('X; // a' + TAB + 'b', R), R);
  S := FixAt(Join([
      '      TFontWeight.Regular: LfontWeightInt := 400; //' + TAB + 'Normal',
      '      TFontWeight.Medium: LfontWeightInt := 500; //' + TAB + 'Medium',
      '      TFontWeight.Semibold: LfontWeightInt := 600; //' + TAB
        + 'Semi Bold']), 2, R);
  Assert.AreEqual('      TFontWeight.Medium: LfontWeightInt := 500; // Medium',
    LineAt(S, 2), R);
  // Ein Tab, der bei jeder Weite zu einem Leerzeichen wird.
  Assert.AreEqual('    /// <summary> Returns last child </summary>',
    FixLine('    ///' + TAB + '<summary> Returns last child </summary>', R), R);
end;

// Indy IdCoderTNEF.pas:359 (minimiert): eine Tabelle im Blockkommentar;
// die Nachbarn richten 'PROP_TAG(' nur bei Weite 4 aus (Spalte 52) - die
// Hilfe ersetzt mit 4. Gegenprobe: bis rwE30 Sperre (Kommentar).
procedure TTestRdxTabsFix.CommentTable_DerivedWidth;
var
  Src, R : string;
begin
  Src := TbJoin(['(*',
      '#define PR_CONVERTED_EITS~~~~~~~PROP_TAG( PT_BINARY,~0x000E)',
      '#define PR_DEFERRED_DELIVERY_TIME~~~~~PROP_TAG( PT_SYSTIME,~0x000F)',
      '#define PR_DELIVER_TIME~~~~~~~~PROP_TAG( PT_SYSTIME,~0x0010)',
      '#define PR_DISCARD_REASON~~~~~~~PROP_TAG( PT_LONG,~~0x0011)',
      '#define PR_DISCLOSURE_OF_RECIPIENTS~~~~~PROP_TAG( PT_BOOLEAN,~0x0012)',
      '#define PR_DL_EXPANSION_HISTORY~~~~~~PROP_TAG( PT_BINARY,~0x0013)',
      '#define PR_DL_EXPANSION_PROHIBITED~~~~~PROP_TAG( PT_BOOLEAN,~0x0014)',
      '*)']);
  Assert.AreEqual('#define PR_DISCARD_REASON' + StringOfChar(' ', 27)
    + 'PROP_TAG( PT_LONG,      0x0011)', LineAt(FixAt(Src, 5, R), 5), R);
end;

// MVCFramework.Nullables.pas:752/1368/1352, JvExExtCtrls.pas:1012: der Tab
// am Zeilenende entfaellt samt Leerraum davor, statt zu Leerzeichen zu
// werden (die blieben als Leerraum am Zeilenende stehen). Gegenprobe: bis
// rwE30 Sperre (Kommentar) bzw. 'X;  ' (Code).
procedure TTestRdxTabsFix.TrailingTab_Removed;
var
  R : string;
begin
  Assert.AreEqual('  ///</summary>', FixLine('  ///</summary>' + TAB, R), R);
  Assert.AreEqual('X;', FixLine('X;' + TAB, R), R);
  Assert.AreEqual('X;', FixLine('X; ' + TAB + ' ', R), R);
  Assert.AreEqual('  {$ENDIF}', FixLine('  {$ENDIF}' + TAB, R), R);
  // Mit Tab davor: der wird ersetzt, das Ende entfaellt.
  Assert.AreEqual('  X; // a', FixLine(TAB + 'X; // a' + TAB, R), R);
end;

// Assets manager.pas:1707: eine Zeile nur aus Tabs wird leer, nicht zu
// Leerzeichen. Gegenprobe: bis rwE30 zwei Leerzeichen je Tab.
procedure TTestRdxTabsFix.BlankLineWithTabs_Emptied;
var
  R : string;
begin
  Assert.AreEqual(Join(['begin', '', 'end;']),
    Fix(Join(['begin', TAB + TAB, 'end;']), 2, TabMsg(1), R), R);
end;

// Gegenprobe: ein Tab in einer Compiler-Direktive bleibt (Inhalt wie
// '{$MESSAGE ..}'); steht er als erster, Sperre - auch in der Folgezeile
// einer mehrzeiligen Direktive. Ein Tab davor wird ersetzt, der in der
// Direktive bleibt.
procedure TTestRdxTabsFix.DirectiveTab_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', FixLine('{$IFDEF' + TAB + 'DEBUG}', R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
  Assert.AreEqual('', Fix(Join(['{$IF Defined(A)', TAB + 'or Defined(B)}']),
    2, TabMsg(1), R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
  Assert.AreEqual('  A := 1; {$IFDEF' + TAB + 'X}',
    FixLine(TAB + 'A := 1; {$IFDEF' + TAB + 'X}', R), R);
end;

// Gegenprobe: eine Zeile in einem mehrzeiligen String (Delphi 12) ist
// Inhalt - Sperre, auch fuer den Tab am Zeilenende.
procedure TTestRdxTabsFix.MultiLineStringTab_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', Fix(Join(['  S := ''''''', TAB + 'abc', '  '''''';']),
    2, TabMsg(1), R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
  Assert.AreEqual('', Fix(Join(['  S := ''''''', 'abc' + TAB, '  '''''';']),
    2, TabMsg(4), R));
  Assert.AreEqual(_(R_TAB_IN_TEXT), R);
end;

{$IFNDEF FPC}

// ---- Adapter der Tabelle und echter Detektor ----

procedure RunTabs(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TTabulationCharacterDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('tabs', ASource, fkTabulationCharacter, RunTabs);
end;

// Dasselbe in der Form von TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := Detect(ASource);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber den Einstieg des Anbieters
// (uTestRdxDetectorKit.FixAllWith, TRdxFixTable.FixFor; bis zur Review
// Woche G06 eine eigene Schleife).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkTabulationCharacter, DetectKind);
end;

function InUnit(const ABody: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', ABody, 'end.']);
end;

// Die Hilfe der Tabelle fuer Zeile ALine von ASource (Spalte des ersten
// Tabs).
function Plan(const ASource: string; ALine: Integer): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := nil;
  try
    SL.Text := ASource;
    F := TLeakFinding.New('t.pas', '', ALine,
      TabMsg(Pos(TAB, SL[ALine - 1])), fkTabulationCharacter);
    Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Der Hinweis nennt die Weite und woher sie kommt. Gegenprobe: bis rwE29
// stand fest 'Tabweite 2 (Annahme)' (FIX_HINTS) - auch bei der Tabelle.
procedure TTestRdxTabsDetector.Plan_Hint_NamesWidth;
var
  O : TRdxFixOutcome;
begin
  O := Plan(Join([
    '  ED_EDIT_SEEK_PREROLL' + StringOfChar(' ', 19) + '= ED_BASE+683;',
    '  ED_EDIT_SEEK_BOOKMARK' + StringOfChar(' ', 18) + '= ED_BASE+685;',
    '  ED_EDIT_PREREAD' + TAB + StringOfChar(' ', 17) + '= ED_BASE+815;']), 3);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(_(R_TABS_LOCAL_HINT, [8]), O.Hint);
end;

// rwE30: entscheidet erst die Datei, sagt der Hinweis das. Gegenprobe: bis
// rwE30 die Annahme 2 (Firebird.pas).
procedure TTestRdxTabsDetector.Plan_Hint_File;
var
  O : TRdxFixOutcome;
begin
  O := Plan(TbJoin([
      '~isc_arg_end~~= 0;~(* end of argument list *)',
      '~isc_arg_gds~~= 1;~(* generic DSRI status value *)',
      '~isc_arg_string~~= 2;~(* string argument *)',
      '~isc_arg_cstring~~= 3;~(* count & string argument *)',
      '~isc_arg_interpreted~= 5;~(* interpreted status code (string) *)',
      '~isc_arg_vms~~= 6;~(* VAX/VMS status code (long) *)',
      '~isc_x0 = 0;', '~isc_x1 = 1;', '~isc_x2 = 2;', '~isc_x3 = 3;',
      '~isc_x4 = 4;', '~isc_x5 = 5;', '~isc_x6 = 6;', '~isc_x7 = 7;',
      '~isc_x8 = 8;',
      '~isc_io_error = 335544344;']), 16);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(_(R_TABS_FILE_HINT, [8]), O.Hint);
  Assert.AreEqual('        ', O.Edits[0].NewText);
end;

// rwE30: nur Tabs am Zeilenende - der Hinweis sagt, dass sie entfallen.
procedure TTestRdxTabsDetector.Plan_Hint_LineEnd;
var
  O : TRdxFixOutcome;
begin
  O := Plan(Join(['  ///</summary>' + TAB]), 1);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(_(R_TABS_TRAIL_HINT), O.Hint);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
  Assert.AreEqual(TAB, O.Edits[0].Expected);
  Assert.AreEqual('', O.Edits[0].NewText);
end;

procedure TTestRdxTabsDetector.Plan_Adapter;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', 2, TabMsg(1), fkTabulationCharacter);
    SL.Text := Join(['begin', TAB + 'A;', 'end;']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual<Integer>(1, Length(O.Edits));
    Assert.AreEqual(TAB, O.Edits[0].Expected);
    Assert.AreEqual('  ', O.Edits[0].NewText);
    // Ohne Beweis in der Datei: die Annahme 2 (rwE29).
    Assert.AreEqual(_(R_TABS_DEFAULT_HINT, [2]), O.Hint);
    // Ohne Datei keine Hilfe.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual<Integer>(0, Length(O.Edits));
    Assert.AreNotEqual('', O.Reason);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxTabsDetector.Detector_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := InUnit(Join(['procedure P;', 'begin', TAB + 'A;',
    TAB + TAB + 'B;', ' ' + TAB + 'C := 1;', 'end;']));
  Good := InUnit(Join(['procedure P;', 'begin', '  A;', '    B;',
    '  C := 1;', 'end;']));
  Assert.AreEqual<Integer>(3, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

// rwE30: Kommentare und Zeilenende - nach der Hilfe meldet der Detektor
// nichts mehr (Wirkung 'same', der Fund verschwindet). Gegenprobe: bis
// rwE30 blieben die drei Kommentar-Funde gesperrt stehen.
procedure TTestRdxTabsDetector.Detector_CommentsAndLineEnd_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := InUnit(Join(['{ Kopf', TAB + 'eingerueckt }', '///</summary>' + TAB,
    'procedure P;', 'begin', '  A; //' + TAB + 'Notiz', 'end;']));
  Good := InUnit(Join(['{ Kopf', '  eingerueckt }', '///</summary>',
    'procedure P;', 'begin', '  A; // Notiz', 'end;']));
  Assert.AreEqual<Integer>(3, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

procedure TTestRdxTabsDetector.Detector_StringOnly_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  Src := InUnit(Join(['procedure P;', 'begin', '  S := ''a' + TAB + 'b'';',
    'end;']));
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
      fkTabulationCharacter);
    SL.Text := Src;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(_(R_TAB_IN_TEXT), O.Reason);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxTabsDetector.Detector_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkTabulationCharacter);
  // Das Beispiel nennt den Tab als '<TAB>'.
  Bad := StringReplace(Meta.BadExample, '<TAB>', TAB, [rfReplaceAll]);
  Assert.IsTrue(Pos(TAB, Bad) > 0, Meta.BadExample);
  Bad := InUnit(CatalogText(Bad));
  Good := InUnit(CatalogText(Meta.GoodExample));
  Assert.IsTrue(Length(Detect(Bad)) > 0, 'der Detektor meldet das Beispiel');
  Assert.AreEqual(Good, FixAll(Bad));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTabsFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxTabsDetector);
  {$ENDIF}

end.
