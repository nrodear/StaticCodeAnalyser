unit uLocalization;

// Lokalisierung fuer das Static Code Analysis Tool for Delphi.
//
// i18n-Scharfschaltung 2026-07-26:
//   Bis dahin lag die deutsche Uebersetzung als hartcodiertes GDeMap
//   (~800 Zeilen BuildDeMap) in dieser Unit, WAEHREND i18n\de.po unbenutzt
//   danebenlag - beide sind auseinandergedriftet (47,9 % der gemeinsamen
//   Keys hatten verschiedene Texte). Die {$IFDEF USE_GETTEXT}-Huelle war ein
//   toter Pfad: USE_GETTEXT war nirgends definiert und gnugettext (dxgettext)
//   existiert weder im Repo noch auf den Build-Maschinen.
//   Seit dem Cutover ist die .po die EINZIGE Quelle der Wahrheit, gelesen von
//   einem eigenen, schlanken Parser (KEINE Fremd-Dependency - Projekt-Ethos:
//   minimale Abhaengigkeiten).
//
// Funktionsweise:
//   * Source-Strings sind in Englisch und mit _('...') instrumentiert.
//   * Default (keine SetLanguage-Aktivierung): Pass-Through, Englisch bleibt
//     Englisch.
//   * SetLanguage('de') / ('fr') / ... laedt die passende .po in ein
//     TDictionary. Strings ohne Eintrag fallen auf die englische Original-
//     Version zurueck (kein Crash, kein leerer String).
//   * SetLanguage('en') / ('') / unbekanntes Kuerzel -> Identity (Englisch).
//
// Woher die .po kommt (in dieser Reihenfolge):
//   1. <Verzeichnis des eigenen Moduls>\i18n\<lang>.po - optionaler
//      Uebersetzer-Workflow: .po neben die EXE/BPL legen, kein Recompile
//      noetig. Fehlt sie, ist sie unlesbar oder parst sie nicht -> 2.
//      ("eigenes Modul" heisst im IDE-Plugin die BPL, nicht bds.exe.)
//   2. Eingebettete Kopie aus uLocalizationPo.inc (generiert von
//      tools\gen_po_inc.py aus i18n\*.po). Damit funktioniert Deutsch aus
//      einer nackt kopierten .exe heraus - ohne jede lose Datei.
//   Beides geht durch denselben Parser, also identisches Verhalten.
//
// WICHTIG bei .po-Aenderungen:
//   python tools\gen_po_inc.py   (regeneriert uLocalizationPo.inc)
//   danach in der IDE Clean + Build - die IDE trackt .inc-Abhaengigkeiten
//   nicht zuverlaessig, sonst gibt es einen stillen Stale-Build.
//
// Verwendung im Code:
//   Btn.Caption := _('Start analysis');
//   Status := Format(_('%d findings'), [N]);

interface

uses
  System.SysUtils, System.Generics.Collections;

// Uebersetzt einen String nach aktiver Sprache. Nicht gefundene Strings
// werden unveraendert zurueckgegeben (Identity-Fallback).
// Hot-Path (uFixHint ruft das pro Finding): ein einziger Dictionary-Lookup,
// keine Sperre, keine Allokation im Miss-Fall.
function _(const S: string): string; overload;

// Format-Variante: erst uebersetzen, dann formatieren.
function _(const FormatStr: string; const Args: array of const): string; overload;

// Setzt die aktive Sprache, z.B. 'de', 'fr', 'en', '' (Default = Englisch).
// Beliebige Kuerzel sind erlaubt; ohne passende .po bleibt es bei Englisch.
// Regionale Varianten werden auf die Basissprache verkuerzt ('de-DE' -> 'de').
// Idempotent: ein zweiter Aufruf mit derselben Sprache parst nicht erneut.
procedure SetLanguage(const Lang: string);

// Liefert die zuletzt gesetzte Sprache unveraendert zurueck (oder '').
function CurrentLanguage: string;

// Alle auswaehlbaren UI-Sprachen als normalisierte Kuerzel, sortiert und
// dublettenfrei (Backlog-Welle 1, 2026-07-26 - Speisung der Sprachauswahl
// in den Optionen). Zusammengesetzt aus:
//   * den eingebetteten .po aus uLocalizationPo.inc (EmbeddedLanguages -
//     generiert, driftet also nicht gegen i18n\*.po)
//   * jeder zusaetzlichen i18n\<code>.po neben dem eigenen Modul
//     (Uebersetzer-Workflow ohne Recompile - dieselbe Quelle die
//     ReadExternalPo im Ladepfad bevorzugt)
//   * 'en' als Quellsprache, die auch ohne jede .po immer waehlbar ist
// Reine Verzeichnis-/Konstanten-Abfrage: laedt oder parst nichts.
function AvailableLanguages: TArray<string>;

// Anzahl der aktuell geladenen Uebersetzungspaare (0 = Identity/Englisch).
// Diagnose- und Test-Hilfe, kein Hot-Path.
function TranslationCount: Integer;

// Parst .po-Text (msgid/msgstr) in ADict. Result = False bei strukturell
// kaputter Datei; ADict kann dann teilbefuellt sein und ist zu verwerfen.
// Oeffentlich fuer Tests und Tooling - der Normalpfad ist SetLanguage.
function ParsePo(const APoText: string; ADict: TDictionary<string, string>): Boolean;

implementation

// noinspection-file BeginEndRequired, IfElseBegin, LongMethod, MultipleExit, NestedRoutines, RedundantConditional, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes;

var
  // Zuletzt gesetztes Kuerzel, unveraendert wie uebergeben (CurrentLanguage).
  GCurrentLang : string = '';

  // Aktive Uebersetzungstabelle oder nil (= Identity/Englisch).
  // Wird von _() OHNE Sperre gelesen: der Zeiger-Read ist atomar, und eine
  // einmal veroeffentlichte Tabelle wird nie mehr veraendert oder freigegeben
  // (erst in der finalization). Ein paralleler SetLanguage-Aufruf laesst den
  // Leser also entweder die alte oder die neue Tabelle sehen - beide gueltig.
  GActiveMap   : TDictionary<string, string> = nil;

  // lang -> Tabelle. Auch ergebnislose Sprachen landen als LEERE Tabelle im
  // Cache, damit ein wiederholtes SetLanguage weder erneut parst noch erneut
  // auf die Platte greift (und damit hier nie ein nil liegt, das doOwnsValues
  // freigeben muesste). Eine leere Tabelle verhaelt sich wie Identity.
  // Besitzt die Tabellen; dient gleichzeitig als Sperrobjekt (TMonitor).
  GLangCache   : TObjectDictionary<string, TDictionary<string, string>> = nil;

// Obergrenze fuer eine extern gelegte .po - schuetzt gegen versehentlich
// hingelegte Riesendateien. Die groesste eigene .po liegt bei ~60 KB.
const
  CMaxExternalPoBytes = 4 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Eingebettete .po-Kopien
// ---------------------------------------------------------------------------

// Fuegt die Zeilen einer eingebetteten .po wieder zu einem Textblock zusammen.
// Wird pro Sprache genau einmal ausgefuehrt (danach greift der Cache).
function JoinPoLines(const ALines: array of string): string;
var
  SB  : TStringBuilder;
  I   : Integer;
  Cap : Integer;
begin
  Cap := 0;
  for I := Low(ALines) to High(ALines) do
    Inc(Cap, Length(ALines[I]) + 1);
  SB := TStringBuilder.Create(Cap);
  try
    for I := Low(ALines) to High(ALines) do
    begin
      if I > Low(ALines) then
        SB.Append(#10);
      SB.Append(ALines[I]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Definiert CPoLines_<lang> und EmbeddedPoText(). GENERIERT - nicht von Hand
// aendern, sondern tools\gen_po_inc.py laufen lassen.
{$I uLocalizationPo.inc}

// ---------------------------------------------------------------------------
// .po-Parser (eigener Code, bewusst schlank - kein gnugettext)
// ---------------------------------------------------------------------------

type
  // In welchen Puffer laufen Fortsetzungszeilen ("...") gerade hinein?
  TPoSection = (psNone, psCtx, psId, psStr);

// Holt das erste "..."-Literal einer Zeile und loest die Backslash-Escapes
// auf. False = Syntaxfehler (kein Literal oder kein schliessendes Quote).
function PoExtractLiteral(const ALine: string; out AValue: string): Boolean;
var
  I, N : Integer;
  SB   : TStringBuilder;
  C    : Char;
begin
  Result := False;
  AValue := '';
  N := Length(ALine);
  I := 1;
  while (I <= N) and (ALine[I] <> '"') do
    Inc(I);
  if I > N then
    Exit;
  Inc(I);
  SB := TStringBuilder.Create;
  try
    while I <= N do
    begin
      C := ALine[I];
      if C = '"' then
      begin
        AValue := SB.ToString;
        Exit(True);
      end;
      if C = '\' then
      begin
        Inc(I);
        if I > N then
          Break;                       // Backslash am Zeilenende -> kaputt
        case ALine[I] of
          'n' : SB.Append(#10);
          't' : SB.Append(#9);
          'r' : SB.Append(#13);
          '"' : SB.Append('"');
          '\' : SB.Append('\');
          'a' : SB.Append(#7);
          'b' : SB.Append(#8);
          'f' : SB.Append(#12);
          'v' : SB.Append(#11);
          '0' : SB.Append(#0);
        else
          SB.Append(ALine[I]);         // unbekanntes Escape: Zeichen roh
        end;
      end
      else
        SB.Append(C);
      Inc(I);
    end;
  finally
    SB.Free;
  end;
  // Schleifenende ohne schliessendes Quote -> Result bleibt False.
end;

// Prueft, ob ALine mit dem .po-Schluesselwort AKeyword beginnt. .po-Keywords
// sind per Spezifikation klein geschrieben, daher case-sensitiv.
function PoStartsWith(const ALine, AKeyword: string): Boolean;
begin
  Result := (Length(ALine) >= Length(AKeyword)) and
            (Copy(ALine, 1, Length(AKeyword)) = AKeyword);
end;

function ParsePo(const APoText: string; ADict: TDictionary<string, string>): Boolean;
var
  Text    : string;
  Lines   : TArray<string>;
  I       : Integer;
  Line    : string;
  Lit     : string;
  Section : TPoSection;
  MsgId   : string;
  MsgStr  : string;
  Skip    : Boolean;

  // Schreibt den gepufferten Eintrag weg und leert die Puffer. Skip bleibt
  // absichtlich unberuehrt (msgctxt gilt fuer den gerade laufenden Eintrag).
  procedure Flush;
  begin
    if (not Skip) and (MsgId <> '') and (MsgStr <> '') then
    begin
      // Erster Treffer gewinnt. Doppelte msgid sind ein .po-Defekt (msgfmt
      // wuerde sie ablehnen); wir bleiben deterministisch statt zu crashen.
      if not ADict.ContainsKey(MsgId) then
        ADict.Add(MsgId, MsgStr);
    end;
    MsgId   := '';
    MsgStr  := '';
    Section := psNone;
  end;

  // Harte Eintragsgrenze (Leerzeile, Kommentar, unbekanntes Schluesselwort).
  procedure EndEntry;
  begin
    Flush;
    Skip := False;
  end;

begin
  Result := False;
  if ADict = nil then
    Exit;

  // Zeilenenden vereinheitlichen - .po darf CRLF, LF oder CR benutzen.
  Text := StringReplace(APoText, #13#10, #10, [rfReplaceAll]);
  Text := StringReplace(Text, #13, #10, [rfReplaceAll]);
  Lines := Text.Split([#10]);

  Section := psNone;
  MsgId   := '';
  MsgStr  := '';
  Skip    := False;

  for I := 0 to High(Lines) do
  begin
    Line := Trim(Lines[I]);

    // Leerzeile: Eintragsgrenze.
    if Line = '' then
    begin
      EndEntry;
      Continue;
    end;

    // Kommentare (#, #., #:, #,) und auskommentierte Eintraege (#~) werden
    // ignoriert - inklusive ihrer Fortsetzungszeilen, die ebenfalls mit '#'
    // beginnen.
    if Line[1] = '#' then
    begin
      EndEntry;
      Continue;
    end;

    // Fortsetzungs-Literal einer mehrzeiligen msgid/msgstr.
    if Line[1] = '"' then
    begin
      if Section = psNone then
        Exit(False);                   // Literal ohne Kontext -> kaputt
      if not PoExtractLiteral(Line, Lit) then
        Exit(False);
      case Section of
        // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
        // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
        // noinspection StringConcatInLoop
        psId  : MsgId  := MsgId + Lit;
        // Kurz-Akkumulator (<100 Zeichen) - Concat schlaegt hier den
        // TStringBuilder-Objekt-Overhead (Review-HIGH-Nachlese 2026-08-08).
        // noinspection StringConcatInLoop
        psStr : MsgStr := MsgStr + Lit;
        psCtx : ;                      // Kontext interessiert uns nicht
      end;
      Continue;
    end;

    // Kontext-Eintraege (msgctxt) haben einen zusammengesetzten Schluessel,
    // den _() nicht kennt - Eintrag wird komplett verworfen.
    if PoStartsWith(Line, 'msgctxt') then
    begin
      if Section <> psNone then
        EndEntry;
      Skip    := True;
      Section := psCtx;
      Continue;
    end;

    // Pluralformen kann _() nicht abbilden -> Eintrag verwerfen. Section wird
    // trotzdem gesetzt, damit Fortsetzungszeilen nicht als Fehler gelten.
    if PoStartsWith(Line, 'msgid_plural') then
    begin
      Skip    := True;
      Section := psId;
      Continue;
    end;
    if PoStartsWith(Line, 'msgstr[') then
    begin
      Skip    := True;
      Section := psStr;
      Continue;
    end;

    if PoStartsWith(Line, 'msgid') then
    begin
      // Nach msgctxt gehoert das msgid zum SELBEN Eintrag: Skip erhalten.
      if Section in [psId, psStr] then
        EndEntry;
      if not PoExtractLiteral(Line, Lit) then
        Exit(False);
      MsgId   := Lit;
      Section := psId;
      Continue;
    end;

    if PoStartsWith(Line, 'msgstr') then
    begin
      if not PoExtractLiteral(Line, Lit) then
        Exit(False);
      MsgStr  := Lit;
      Section := psStr;
      Continue;
    end;

    // Unbekanntes Schluesselwort: tolerant behandeln, Eintrag beenden.
    EndEntry;
  end;

  EndEntry;

  // Der Header-Eintrag hat msgid "" und wird von Flush ohnehin verworfen -
  // ebenso jeder Eintrag mit leerem msgstr: der faellt damit automatisch auf
  // die msgid (= englischer Originaltext) zurueck.
  Result := True;
end;

// ---------------------------------------------------------------------------
// Laden
// ---------------------------------------------------------------------------

// 'de-DE' / ' DE ' / 'de_AT' -> 'de'. Liefert '' fuer alles, was kein reines
// Sprachkuerzel ist; das schuetzt zugleich den Dateipfad unten gegen
// Fremdeingaben aus den Settings (kein '..', kein Backslash).
function NormalizeLangCode(const ALang: string): string;
var
  S : string;
  I : Integer;
begin
  Result := '';
  S := LowerCase(Trim(ALang));
  I := 1;
  while (I <= Length(S)) and (S[I] <> '-') and (S[I] <> '_') do
    Inc(I);
  S := Copy(S, 1, I - 1);
  if S = '' then
    Exit;
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['a'..'z', '0'..'9']) then
      Exit;
  Result := S;
end;

// Optionale externe .po neben dem eigenen Modul (EXE bzw. BPL). Liefert ''
// wenn nichts Brauchbares da ist - jeder Fehler ist hier ein Nicht-Ereignis.
function ReadExternalPo(const ALang: string): string;
var
  FileName : string;
  SS       : TStringStream;
  FS       : TFileStream;
begin
  Result := '';
  try
    FileName := IncludeTrailingPathDelimiter(
                  ExtractFilePath(GetModuleName(HInstance))) +
                'i18n' + PathDelim + ALang + '.po';
    if not FileExists(FileName) then
      Exit;
    // GROESSE VOR DEM LADEN pruefen (2026-08-01, T3-Backlog): vorher zog
    // LoadFromFile die Datei erst KOMPLETT in den Speicher und verwarf sie
    // danach wegen Ueberlaenge - der Schutz kam zu spaet. Eine fehlerhafte
    // oder feindliche .po neben der Exe konnte so beliebig viel Speicher
    // binden. Jetzt entscheidet die Dateigroesse, bevor ein Byte kopiert
    // wird.
    SS := TStringStream.Create('', TEncoding.UTF8);
    try
      FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        if FS.Size > CMaxExternalPoBytes then
          Exit;
        SS.CopyFrom(FS, 0);
      finally
        FS.Free;
      end;
      Result := SS.DataString;
    finally
      SS.Free;
    end;
    // BOM taucht als U+FEFF im dekodierten Text auf - wegschneiden.
    if (Result <> '') and (Result[1] = #$FEFF) then
      Delete(Result, 1, 1);
  except
    // Kaputte/gesperrte/fremde Datei darf die Anwendung nie stoppen.
    Result := '';
  end;
end;

// Baut die Tabelle fuer ein normalisiertes Kuerzel. nil = keine Uebersetzung
// (Aufrufer faellt auf Englisch zurueck). Wirft nie.
function LoadLanguage(const ALang: string): TDictionary<string, string>;
var
  Dict : TDictionary<string, string>;
  Text : string;
  Ok   : Boolean;
begin
  Result := nil;
  if ALang = '' then
    Exit;
  Dict := nil;
  try
    Dict := TDictionary<string, string>.Create(512);

    // 1. externe .po (Uebersetzer-Workflow ohne Recompile)
    Ok   := False;
    Text := ReadExternalPo(ALang);
    if Text <> '' then
    begin
      Ok := ParsePo(Text, Dict);
      if Ok and (Dict.Count = 0) then
        Ok := False;                   // leere/nutzlose Datei -> eingebettet
      if not Ok then
        Dict.Clear;
    end;

    // 2. eingebettete Kopie aus uLocalizationPo.inc
    if not Ok then
    begin
      Text := EmbeddedPoText(ALang);
      if Text = '' then
      begin
        FreeAndNil(Dict);
        Exit;
      end;
      if not ParsePo(Text, Dict) then
      begin
        FreeAndNil(Dict);
        Exit;
      end;
    end;
  except
    // Auch OutOfMemory/unerwartete Parserfehler enden still auf Englisch.
    Dict.Free;
    Exit(nil);
  end;
  Result := Dict;
end;

// ---------------------------------------------------------------------------
// Oeffentliche API
// ---------------------------------------------------------------------------

function _(const S: string): string;
var
  Map   : TDictionary<string, string>;
  Value : string;
begin
  Map := GActiveMap;                   // atomarer Zeiger-Read, siehe var-Block
  if (Map <> nil) and Map.TryGetValue(S, Value) then
    Result := Value
  else
    Result := S;
end;

function _(const FormatStr: string; const Args: array of const): string;
begin
  Result := Format(_(FormatStr), Args);
end;

procedure SetLanguage(const Lang: string);
var
  Norm : string;
  Map  : TDictionary<string, string>;
begin
  GCurrentLang := Lang;
  Norm := NormalizeLangCode(Lang);
  if Norm = '' then
  begin
    GActiveMap := nil;                 // Default/unbrauchbar -> Englisch
    Exit;
  end;

  // Lazy + idempotent: erst beim ersten Bedarf parsen, danach nur Cache.
  TMonitor.Enter(GLangCache);
  try
    if not GLangCache.TryGetValue(Norm, Map) then
    begin
      Map := LoadLanguage(Norm);
      GLangCache.Add(Norm, Map);       // auch nil cachen (kein Re-Parse)
    end;
  finally
    TMonitor.Exit(GLangCache);
  end;

  GActiveMap := Map;
end;

function CurrentLanguage: string;
begin
  Result := GCurrentLang;
end;

function AvailableLanguages: TArray<string>;
var
  List     : TStringList;
  Dir      : string;
  SR       : TSearchRec;
  I        : Integer;
  Embedded : TArray<string>;

  // Normalisiert und sammelt ein Kuerzel ein. Sorted+dupIgnore uebernimmt
  // Sortierung und Dublettenschutz (eine externe de.po neben der EXE
  // erzeugt denselben Eintrag wie die eingebettete - genau einmal).
  procedure AddCode(const ACode: string);
  var
    Norm : string;
  begin
    Norm := NormalizeLangCode(ACode);
    if Norm <> '' then
      List.Add(Norm);
  end;

begin
  List := TStringList.Create;
  try
    List.Sorted     := True;
    List.Duplicates := dupIgnore;

    // 1. eingebettete Sprachen (generiert aus i18n\*.po)
    Embedded := EmbeddedLanguages;
    for I := Low(Embedded) to High(Embedded) do
      AddCode(Embedded[I]);

    // 2. externe i18n\*.po neben dem eigenen Modul (EXE bzw. BPL). Kein
    //    try/except noetig: DirectoryExists liefert bei jedem Problem
    //    False, FindFirst einen Fehlercode - beides ist hier ein
    //    Nicht-Ereignis und endet in "keine zusaetzliche Sprache".
    Dir := IncludeTrailingPathDelimiter(
             ExtractFilePath(GetModuleName(HInstance))) + 'i18n';
    if DirectoryExists(Dir) then
      if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.po',
                   faAnyFile, SR) = 0 then
        try
          repeat
            // Verzeichnisse mit .po-Endung ausschliessen - FindFirst
            // liefert sie bei faAnyFile mit.
            if (SR.Attr and faDirectory) = 0 then
              AddCode(ChangeFileExt(SR.Name, ''));
          until FindNext(SR) <> 0;
        finally
          FindClose(SR);
        end;

    // 3. Englisch ist die Quellsprache der _()-Aufrufe und braucht kein
    //    Dictionary - darf daher nie aus der Auswahl fallen.
    AddCode('en');

    SetLength(Result, List.Count);
    for I := 0 to List.Count - 1 do
      Result[I] := List[I];
  finally
    List.Free;
  end;
end;

function TranslationCount: Integer;
var
  Map : TDictionary<string, string>;
begin
  Map := GActiveMap;
  if Map = nil then
    Result := 0
  else
    Result := Map.Count;
end;

initialization
  GLangCache := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);

finalization
  // Erst abmelden, dann freigeben: ab hier laeuft kein _() mehr.
  GActiveMap := nil;
  FreeAndNil(GLangCache);

end.
