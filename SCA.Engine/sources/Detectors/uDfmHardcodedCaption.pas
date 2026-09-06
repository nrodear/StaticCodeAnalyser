unit uDfmHardcodedCaption;

// Detektor: Hardcodierte UI-Strings im DFM.
//
// Findet String-Literale in UI-Text-Properties (Caption, Hint, Text)
// von Komponenten im DFM. Solche Strings umgehen den Lokalisierungs-Layer
// (dxgettext / gnugettext / uLocalization) und sind in mehrsprachigen
// Projekten ein typischer Lokalisierungs-Smell.
//
// Heuristik bewusst pragmatisch:
//   * Nur Properties aus einer kurzen Whitelist (Caption, Hint, Text).
//   * Nur pvkString-Werte (nicht z.B. Ident, der koennte eine Variable
//     oder Konstante sein).
//   * Leerer / nur-Whitespace-Wert ist kein Befund (Designer setzt
//     Caption = '' um Default-Text auszuschalten).
//
// Aktivierung ist heute global: der Detektor laeuft fuer jede DFM-Datei
// im Analyse-Lauf. Wenn ein Projekt komplett ohne Lokalisierung arbeitet,
// koennen die Befunde via Suppression-Kommentar oder ignore.txt
// ausgeschlossen werden.
//
// FP-Gates (AQL 31.08. -> Charge 15, 06.09.2026; alle DREI belegten
// FP-Klassen der 11-%-Messung, am rw70b-Bestand vollgezaehlt = 1.150
// von 26.358):
//   G1 GLYPH (44): Ein-Zeichen-Caption bei Font.Name in einem
//      Symbolfont (Webdings/Wingdings/Marlett/Symbol) ist ein Icon,
//      kein Text.
//   G2 RESOURCESTRING (7): die Nachbar-.pas weist DERSELBEN
//      Komponenten-Property einen resourcestring-Ident zu - der
//      DFM-Wert ist ein toter Platzhalter.
//   G3 UEBERSETZUNGS-REGIME (1.099): die Nachbar-.pas nutzt einen
//      Laufzeit-DFM-Uebersetzer (gnugettext/dxgettext/TranslateComponent,
//      Dev-Cpp MultiLangSupport, cnwizards CnLangMgr, uLocalization*).
//      Dann IST der DFM-Text die msgid-Quelle des i18n-Layers - er
//      umgeht nichts. WICHTIG (Losbildungs-Lehre SCA167): die Einheit
//      ist die FORM-UNIT, nicht das Repository - jvcl TRAEGT gettext
//      als Bibliothek, seine Demos uebersetzen deshalb noch lange
//      nicht. Der alte Phase-2-Plan hier ("nur bei gnugettext-uses
//      MELDEN") ist damit invertiert widerlegt: gerade dort ist die
//      Meldung falsch.
// Marker-/Zuweisungs-Suche laeuft auf gestripptem Quelltext
// (StripStringsAndComments) - Kommentare und String-Literale zaehlen
// nie als Code-Use.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell (siehe KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmHardcodedCaptionDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.Classes,            // TStringList (Nachbar-.pas)
  System.StrUtils,           // ContainsText (Regime-Marker)
  uDetectorUtils,            // StripStringsAndComments (G2/G3-Suche)
  uFileTextCache;            // AcquireLines (Prozess-Cache)

// noinspection-file CanBeClassMethod, ConsecutiveSection, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  // Default-Whitelist der UI-Text-Properties. Konfigurierbar machen in
  // Phase 2 via analyser.ini ([Components] CaptionProperties=...). Aktuell
  // bewusst kurz, damit der Detektor wenige False Positives erzeugt;
  // 'Text' ist bei TEdit auch User-Input, dort aber Designer-typisch leer.
  CAPTION_PROPS: array[0..2] of string = ('Caption', 'Hint', 'Text');

function IsNonTranslatable(const S: string): Boolean;
// True wenn die Caption KEINEN Buchstaben enthaelt und rein ASCII ist - also
// reine Symbole/Ziffern/Interpunktion ('-', '...', '>>', '|', '123', '/').
// Solche Captions umgehen keinen Lokalisierungs-Layer (es gibt nichts zu
// uebersetzen) -> kein i18n-Smell (dominante DfmHardcodedCaption-FP-Klasse,
// Real-World 2026-06-28). Unicode-Zeichen (Ord > 127, z.B. CJK/kyrillisch/
// akzentuiert) werden NICHT geskippt - das ist uebersetzbarer Text.
var
  C : Char;
  HasLetter, AllAscii : Boolean;
begin
  HasLetter := False;
  AllAscii  := True;
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z']) then HasLetter := True;
    if Ord(C) > 127 then AllAscii := False;
  end;
  Result := (not HasLetter) and AllAscii;
end;

const
  // G1: Fonts, deren Zeichen Icons sind, kein uebersetzbarer Text.
  SYMBOL_FONTS: array[0..5] of string =
    ('Webdings', 'Wingdings', 'Wingdings 2', 'Wingdings 3', 'Marlett',
     'Symbol');
  // G3: Marker eines Laufzeit-DFM-Uebersetzers in der Form-Unit
  // (Herleitung + Vollzaehlung im Unit-Kopf).
  REGIME_MARKER: array[0..7] of string =
    ('gnugettext', 'dxgettext', 'uLocalization', 'TranslateComponent',
     'TranslateProperties', 'RetranslateComponent', 'MultiLangSupport',
     'CnLangMgr');

function IsSymbolFont(const AName: string): Boolean;
var
  S : string;
begin
  for S in SYMBOL_FONTS do
    if SameText(S, AName) then Exit(True);
  Result := False;
end;

procedure LadeNachbarPas(const ADfmFile: string; out ARegime: Boolean;
  AResIdents: TStringList; AZuweisungen: TStringList);
// Liest die Nachbar-.pas der DFM EINMAL je Datei: Uebersetzungs-Regime-
// Marker (G3), resourcestring-Identmenge und die 'Comp.Prop := Ident;'-
// Zuweisungen (G2, als 'comp.prop=ident'-Zeilen in AZuweisungen).
// Suche auf gestripptem Text - Kommentare/Strings zaehlen nie.
var
  PasFile   : string;
  Lines     : TStringList;
  Cached    : Boolean;
  LineFor   : TArray<Integer>;
  Code, S   : string;
  M         : string;
  InResBlock: Boolean;
  PosAssign, PosDot, PosSemi : Integer;
  Lhs, Rhs  : string;
begin
  ARegime := False;
  PasFile := ChangeFileExt(ADfmFile, '.pas');
  Lines := AcquireLines(PasFile, Cached);
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
  finally
    if not Cached then Lines.Free;
  end;
  for M in REGIME_MARKER do
    if ContainsText(Code, M) then
    begin
      ARegime := True;
      Break;
    end;
  InResBlock := False;
  for S in Code.Split([#10]) do
  begin
    Lhs := Trim(S);
    if Lhs = '' then Continue;
    if SameText(Lhs, 'resourcestring') then
    begin
      InResBlock := True;
      Continue;
    end;
    if InResBlock then
    begin
      // Abschnittswechsel beendet den Block.
      if StartsText('var', Lhs) or StartsText('const', Lhs)
         or StartsText('type', Lhs) or StartsText('procedure', Lhs)
         or StartsText('function', Lhs) or StartsText('implementation', Lhs)
         or StartsText('begin', Lhs) or StartsText('end', Lhs)
         or StartsText('uses', Lhs) then
        InResBlock := False
      else
      begin
        PosAssign := Pos('=', Lhs);
        if PosAssign > 1 then
          AResIdents.Add(LowerCase(Trim(Copy(Lhs, 1, PosAssign - 1))));
        Continue;
      end;
    end;
    // 'Comp.Prop := Ident;' einsammeln (genau EIN Punkt links, reiner
    // Ident rechts) - O(1)-Lookup je Fund statt Regex je Fund.
    PosAssign := Pos(':=', Lhs);
    if PosAssign = 0 then Continue;
    PosSemi := Pos(';', Lhs);
    if (PosSemi = 0) or (PosSemi < PosAssign) then Continue;
    Rhs := Trim(Copy(Lhs, PosAssign + 2, PosSemi - PosAssign - 2));
    Lhs := Trim(Copy(Lhs, 1, PosAssign - 1));
    if (Rhs = '') or (Lhs = '') then Continue;
    PosDot := Pos('.', Lhs);
    if (PosDot <= 1) or (Pos('.', Lhs, PosDot + 1) > 0) then Continue;
    // System.SysUtils.IsValidIdent - TDetectorUtils hat keins.
    if not (IsValidIdent(Copy(Lhs, 1, PosDot - 1))
            and IsValidIdent(Copy(Lhs, PosDot + 1, MaxInt))
            and IsValidIdent(Rhs)) then Continue;
    AZuweisungen.Add(LowerCase(Lhs) + '=' + LowerCase(Rhs));
  end;
end;

class procedure TDfmHardcodedCaptionDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All        : TList<TComponentNode>;
  N          : TComponentNode;
  V, FontV   : TPropValue;
  P          : string;
  F          : TLeakFinding;
  Regime     : Boolean;
  ResIdents  : TStringList;
  Zuweisungen: TStringList;
  ZuwIdx     : Integer;
  RhsIdent   : string;
begin
  if Graph = nil then Exit;

  ResIdents := TStringList.Create;
  Zuweisungen := TStringList.Create;
  All := Graph.EnumerateAll;
  try
    ResIdents.CaseSensitive := False;
    ResIdents.Sorted := True;
    ResIdents.Duplicates := dupIgnore;
    Zuweisungen.CaseSensitive := False;
    LadeNachbarPas(FileName, Regime, ResIdents, Zuweisungen);

    for N in All do
    begin
      for P in CAPTION_PROPS do
      begin
        if not N.TryGetProperty(P, V) then Continue;
        if V.Kind <> pvkString          then Continue;
        if Trim(V.RawValue) = ''        then Continue;
        // Reine Symbol-/Ziffern-Captions ('-', '...', '123') sind nicht
        // lokalisierbar -> kein i18n-Smell.
        if IsNonTranslatable(Trim(V.RawValue)) then Continue;
        // G1 GLYPH: Ein-Zeichen-"Text" in einem Symbolfont ist ein Icon.
        if (Length(V.RawValue) = 1) and N.TryGetProperty('Font.Name', FontV)
           and (FontV.Kind = pvkString) and IsSymbolFont(FontV.RawValue) then
          Continue;
        // G2 RESOURCESTRING: die .pas ersetzt genau diese Property aus
        // einer resourcestring - der DFM-Wert ist ein toter Platzhalter.
        ZuwIdx := Zuweisungen.IndexOfName(LowerCase(N.Name + '.' + P));
        if ZuwIdx >= 0 then
        begin
          RhsIdent := Zuweisungen.ValueFromIndex[ZuwIdx];
          if ResIdents.IndexOf(RhsIdent) >= 0 then Continue;
        end;
        // G3 UEBERSETZUNGS-REGIME: die Form uebersetzt ihre DFM-Texte
        // zur Laufzeit - der String IST die msgid-Quelle.
        if Regime then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(V.Line);
        F.MissingVar := Format('%s.%s = ''%s''', [N.Name, P, V.RawValue]);
        F.SetKind(fkDfmHardcodedCaption);
        Results.Add(F);
      end;
    end;
  finally
    All.Free;
    Zuweisungen.Free;
    ResIdents.Free;
  end;
end;

end.
