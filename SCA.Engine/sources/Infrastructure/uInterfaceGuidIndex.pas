unit uInterfaceGuidIndex;

// Scan-weiter Index der Interface-GUIDs (SCA197 / SCA198).
//
// WOFUER
//   Eine Interface-GUID muss im ganzen Programm eindeutig sein. Steht
//   dieselbe an zwei Interfaces - der klassische Copy-Paste beim Anlegen
//   des naechsten Interface -, dann liefert `Supports(Obj, IZweites, X)`
//   das ERSTE, ohne Compilerfehler und ohne Laufzeitfehler. Das ist genau
//   die Sorte Fehler, die man an der Fundstelle nicht sehen kann: sichtbar
//   wird sie erst im Vergleich zweier Dateien.
//
//   Deshalb ein Index. Ein Detektor sieht immer nur seine eine Datei; die
//   Frage "gibt es diese GUID noch woanders" kann er allein nicht
//   beantworten.
//
// WARUM LEXIKALISCH UND NICHT AM AST
//   Der Parser wirft die GUID weg. `IFoo = interface ['{...}']` laeuft in
//   ParseClassBody durch denselben Zweig, der Member-Attribute
//   ueberspringt (uParser2, Kommentar bei Z.1305) - im AST bleibt ein
//   nkClass-Knoten ohne jede Spur der GUID. Interfaces sind dort ausserdem
//   nicht von Klassen unterscheidbar (uParser2 Z.874).
//
//   Den Parser dafuer zu erweitern waere der sauberere Weg, aber ein
//   Eingriff in die gemeinsame Grundlage aller Detektoren fuer eine
//   einzige Regelfamilie - und Parser-Aenderungen machen im Haus
//   erfahrungsgemaess bestehende Gates erst wirksam, also weitab messbar.
//   Der lexikalische Weg ist derselbe, den uEmptyInterface und
//   uInterfaceName schon gehen.
//
// AUFBAU-MODELL (analog uTypeIndex / uSymbolReferenceIndex)
//   TStaticAnalyzer2 ruft Build einmal je Scan mit der Indexdatei-Liste.
//   Im Einzeldatei-Modus wird nie gebaut (IsEmpty) - dann meldet der
//   Detektor nur die fehlenden GUIDs, Duplikate bleiben unentdeckt. Das
//   ist die richtige Vorsicht: mit einer Datei im Blick ist "einmalig"
//   keine Aussage.
//
// SCOPE
//   Was "das ganze Programm" ist, entscheidet der Aufrufer ueber die
//   Datei-Liste - Verzeichnis, Projekt (.dproj) oder Projektgruppe
//   (.groupproj). Diese Auswahl gibt es bereits (ssProject/ssProjectGroup
//   in uEngineApi); der Index setzt nur darauf auf.
//
// KEIN uAnalyzeContext IM INTERFACE
//   uAnalyzeContext fuehrt den Index als Feld und muss diese Unit deshalb
//   kennen. Umgekehrt darf sie hier nur in der implementation stehen -
//   sonst ist der Ring geschlossen. Praktische Folge: Build benutzt den
//   UNGECACHTEN Kommentar-Strip. Das kostet nichts: der Cache im Context
//   hat genau einen Slot pro Datei, und ein Lauf ueber ALLE Dateien
//   verdraengt ihn bei jedem Schritt selbst.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  /// <summary>Eine Interface-Deklaration, so wie sie im Quelltext steht.</summary>
  TInterfaceDecl = record
    FileName : string;
    Line     : Integer;   // 1-basiert, Zeile des Interface-Namens
    Name     : string;    // 'IFoo' (ohne generische Argumente)
    Guid     : string;    // normalisiert, GROSS, ohne Klammern; '' = keine
    /// <summary>True, wenn eckige Klammern da waren, ihr Inhalt aber keine
    /// GUID-Form hatte (z.B. eine Konstante). Dann ist weder "fehlt" noch
    /// "doppelt" entscheidbar - der Fall wird still uebergangen.</summary>
    GuidUnparsed : Boolean;
  end;

  TInterfaceGuidIndex = class
  strict private
    // GUID -> alle Stellen, an denen sie steht. Auch die einfachen
    // Vorkommen werden gefuehrt: der Detektor fragt je Fundstelle nach,
    // und "genau eine Stelle" ist die Antwort "in Ordnung".
    FByGuid : TObjectDictionary<string, TList<TInterfaceDecl>>;
    FCount  : Integer;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Liest alle Dateien und sammelt ihre Interface-GUIDs.
    /// Lesefehler einzelner Dateien werden uebergangen - ein Index, der
    /// wegen einer unlesbaren Datei komplett ausfaellt, waere schlechter
    /// als ein unvollstaendiger.</summary>
    /// <remarks>Laedt bewusst OHNE den Text-Cache, s. Kommentar an der
    /// Implementierung.</remarks>
    procedure Build(AFiles: TStringList);

    /// <summary>Alle Stellen zu einer normalisierten GUID. Leer, wenn
    /// unbekannt.</summary>
    function SitesOf(const AGuid: string): TArray<TInterfaceDecl>;

    /// <summary>True, solange kein Build gelaufen ist oder keine einzige
    /// GUID gefunden wurde. Der Detektor faellt dann auf den Vergleich
    /// innerhalb der eigenen Datei zurueck.</summary>
    function IsEmpty: Boolean;

    /// <summary>Zahl der erfassten Fundstellen - nicht der GUIDs: eine
    /// mehrfach vergebene GUID zaehlt so oft, wie sie vorkommt.</summary>
    property Count: Integer read FCount;

    /// <summary>Die Interface-Deklarationen EINER Datei. Auch der Detektor
    /// benutzt das - damit gibt es genau eine Stelle, die entscheidet, was
    /// als Interface-Deklaration gilt.</summary>
    class function ScanFile(const AFileName: string;
      ALines: TStrings): TArray<TInterfaceDecl>; static;

    /// <summary>Wie ScanFile, aber auf bereits kommentar-bereinigtem Text.
    /// Der Detektor hat den Strip ueber seinen Context-Cache schon; ihn
    /// hier ein zweites Mal zu rechnen waere je Datei ein voller
    /// Durchlauf umsonst.</summary>
    class function ScanCode(const AFileName, ACode: string;
      const ALineFor: TArray<Integer>): TArray<TInterfaceDecl>; static;

    /// <summary>'{a1b2...}' -> 'A1B2...' (Form 8-4-4-4-12 vorausgesetzt).
    /// Leerstring, wenn es keine GUID ist.</summary>
    class function NormalizeGuid(const ARaw: string): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, IfElseBegin, TooLongLine, UnsortedUses
// Lexikalischer Scanner - der Stil folgt uEmptyInterface, damit die beiden
// Laeufe nebeneinander lesbar bleiben.

uses
  System.StrUtils,
  uFileTextCache,   // TryLoadLinesWithFallback - Laden ohne Cache-Eintrag
  uDetectorUtils;

function IstLeerraum(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', #9, #10, #13]);
end;

function UeberLeerraumRueckwaerts(const ACode: string; k: Integer): Integer;
begin
  while (k >= 1) and IstLeerraum(ACode[k]) do Dec(k);
  Result := k;
end;

function UeberLeerraumVorwaerts(const ACode: string; j: Integer): Integer;
begin
  while (j <= Length(ACode)) and IstLeerraum(ACode[j]) do Inc(j);
  Result := j;
end;

function LiesNamenLinks(const ACode: string; APosGleich: Integer;
  out AStart: Integer): string;
// Der Interface-Name steht links vom '='. Generische Argumente werden
// abgeschnitten: bei `IList<T> = interface` sucht die Klammer-
// Rueckwaertszaehlung ueber `<T>` hinweg, sonst waere der Name 'T'.
var
  k     : Integer;
  Tiefe : Integer;
begin
  Result := '';
  AStart := 0;
  k := UeberLeerraumRueckwaerts(ACode, APosGleich - 1);
  if (k >= 1) and (ACode[k] = '>') then
  begin
    Tiefe := 1;
    Dec(k);
    while (k >= 1) and (Tiefe > 0) do
    begin
      if ACode[k] = '>' then Inc(Tiefe)
      else if ACode[k] = '<' then Dec(Tiefe);
      Dec(k);
    end;
    k := UeberLeerraumRueckwaerts(ACode, k);
  end;
  AStart := k;
  while (AStart >= 1) and TDetectorUtils.IsIdentChar(ACode[AStart]) do Dec(AStart);
  Inc(AStart);
  if AStart > k then Exit;   // kein Bezeichner - Aufrufer ueberspringt
  Result := Copy(ACode, AStart, k - AStart + 1);
end;

function UeberVorfahren(const ACode: string; j: Integer): Integer;
// Ueberspringt die optionale `(IBase, IWeitere)`-Liste hinter dem
// Schluesselwort und liefert die naechste bedeutsame Position.
var
  Tiefe : Integer;
begin
  Result := UeberLeerraumVorwaerts(ACode, j);
  if (Result > Length(ACode)) or (ACode[Result] <> '(') then Exit;
  Tiefe := 1;
  Inc(Result);
  while (Result <= Length(ACode)) and (Tiefe > 0) do
  begin
    if ACode[Result] = '(' then Inc(Tiefe)
    else if ACode[Result] = ')' then Dec(Tiefe);
    Inc(Result);
  end;
  Result := UeberLeerraumVorwaerts(ACode, Result);
end;

function LiesGuidKlammer(const ACode: string; var j: Integer;
  out AGuid: string): Boolean;
// True, wenn an j eine eckige Klammer steht. AGuid ist dann die
// normalisierte GUID - oder leer, wenn der Inhalt keine war.
var
  pAnfang : Integer;
begin
  AGuid  := '';
  Result := (j <= Length(ACode)) and (ACode[j] = '[');
  if not Result then Exit;
  Inc(j);
  pAnfang := j;
  while (j <= Length(ACode)) and (ACode[j] <> ']') do Inc(j);
  AGuid := TInterfaceGuidIndex.NormalizeGuid(Copy(ACode, pAnfang, j - pAnfang));
  if j <= Length(ACode) then Inc(j);
end;

class function TInterfaceGuidIndex.NormalizeGuid(const ARaw: string): string;
// Erwartet den Inhalt der eckigen Klammern, also etwa
//   '{2A3B4C5D-1111-2222-3333-444455556666}'
// samt Anfuehrungszeichen und Leerraum drumherum.
//
// Geprueft wird die FORM, nicht nur die Laenge: 32 Hexziffern in der
// Gruppierung 8-4-4-4-12. Alles andere ist keine GUID - eine Konstante,
// ein Ausdruck, ein Tippfehler - und darf weder als "vorhanden" noch als
// vergleichbar gelten.
const
  LAENGEN : array[0..4] of Integer = (8, 4, 4, 4, 12);
var
  S    : string;
  C    : Char;
  Teil : TArray<string>;
  i    : Integer;
begin
  Result := '';
  S := '';
  for C in ARaw do
    if not CharInSet(C, [' ', #9, #10, #13, '''', '"', '{', '}']) then
      S := S + C;
  if S = '' then Exit;

  Teil := S.Split(['-']);
  if Length(Teil) <> 5 then Exit;
  for i := 0 to 4 do
  begin
    if Length(Teil[i]) <> LAENGEN[i] then Exit;
    for C in Teil[i] do
      if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  end;
  Result := UpperCase(S);
end;

class function TInterfaceGuidIndex.ScanFile(const AFileName: string;
  ALines: TStrings): TArray<TInterfaceDecl>;
var
  Code    : string;
  LineFor : TArray<Integer>;
begin
  Result := nil;
  if ALines = nil then Exit;
  Code := TDetectorUtils.StripFileCommentsKeepStrings(ALines, LineFor);
  Result := ScanCode(AFileName, Code, LineFor);
end;

class function TInterfaceGuidIndex.ScanCode(const AFileName, ACode: string;
  const ALineFor: TArray<Integer>): TArray<TInterfaceDecl>;
// Die Schleife sucht jedes Wort "interface" und beantwortet vier Fragen:
// steht es frei, steht links ein '=', wie heisst der Typ, und folgt eine
// GUID. Jede davon hat ihren eigenen Helfer - der Rumpf hier ist nur noch
// die Reihenfolge (Review: die fruehere Fassung kam auf kognitive
// Komplexitaet 75 bei Grenze 15, waehrend uEmptyInterface mit derselben
// Aufgabe darunter bleibt).
var
  Lwr     : string;
  Treffer : TList<TInterfaceDecl>;
  p, j, k : Integer;
  pName   : Integer;
  Decl    : TInterfaceDecl;
begin
  Result := nil;
  if ACode = '' then Exit;
  Lwr := LowerCase(ACode);

  Treffer := TList<TInterfaceDecl>.Create;
  try
    p := 1;
    while True do
    begin
      p := PosEx('interface', Lwr, p);
      if p = 0 then Break;

      // Freies Wort? Die linke Grenze faengt zugleich 'dispinterface' ab -
      // eine Automations-Schnittstelle hat eigene Regeln.
      if (p > 1) and TDetectorUtils.IsIdentChar(ACode[p - 1]) then
      begin Inc(p); Continue; end;
      if (p + 9 <= Length(ACode)) and TDetectorUtils.IsIdentChar(ACode[p + 9]) then
      begin Inc(p); Continue; end;
      // Nicht in einem String-Literal - siehe InStringLiteral.
      if TDetectorUtils.InStringLiteral(ACode, p) then
      begin Inc(p, 9); Continue; end;

      // Links ein '='? Sonst ist es das Unit-Schluesselwort oder eine
      // Variablendeklaration (`X: IFoo`).
      k := UeberLeerraumRueckwaerts(ACode, p - 1);
      if (k < 1) or (ACode[k] <> '=') then
      begin Inc(p, 9); Continue; end;

      Decl := Default(TInterfaceDecl);
      Decl.Name := LiesNamenLinks(ACode, k, pName);
      if Decl.Name = '' then
      begin Inc(p, 9); Continue; end;
      Decl.FileName := AFileName;
      Decl.Line     := TDetectorUtils.LineForPos(ALineFor, pName);
      // LineForPos liefert 0 ausserhalb der Map; Zeile 0 ist in SARIF
      // unzulaessig, 1 ist die konservative Antwort.
      if Decl.Line < 1 then Decl.Line := 1;

      j := UeberVorfahren(ACode, p + 9);

      if (j <= Length(ACode)) and (ACode[j] = ';') then
      begin
        // `IFoo = interface;` ist eine VORWAERTSDEKLARATION. Sie darf gar
        // keine GUID tragen - der Compiler laesst es nicht zu -, also
        // waere "GUID fehlt" hier falsch.
        Inc(p, 9);
        Continue;
      end;

      Decl.GuidUnparsed := LiesGuidKlammer(ACode, j, Decl.Guid) and
                           (Decl.Guid = '');

      Treffer.Add(Decl);
      // Nie zurueck, sonst laeuft die Schleife auf derselben Deklaration.
      if j > p then p := j else Inc(p, 9);
    end;
    Result := Treffer.ToArray;
  finally
    Treffer.Free;
  end;
end;

constructor TInterfaceGuidIndex.Create;
begin
  inherited Create;
  FByGuid := TObjectDictionary<string, TList<TInterfaceDecl>>.Create([doOwnsValues]);
end;

destructor TInterfaceGuidIndex.Destroy;
begin
  FByGuid.Free;
  inherited;
end;

function TInterfaceGuidIndex.IsEmpty: Boolean;
begin
  Result := FByGuid.Count = 0;
end;

procedure TInterfaceGuidIndex.Build(AFiles: TStringList);
// BEWUSST OHNE TEXT-CACHE (Review 2026-08-25, Blocker).
//
// AcquireLines legt jede gelesene Datei im prozessweiten Cache ab, und
// ReleaseLines gibt einen Cache-Eintrag nicht wieder frei. Ein Lauf ueber
// ALLE Dateien haette damit den gesamten Quelltext gleichzeitig im
// Speicher gehalten - der Hauptlauf leert den Cache nach JEDER Datei
// (uStaticAnalyzer2, gFileTextCache.Clear), genau um den Spitzenwert bei
// einer Datei zu halten. Auf dem Referenzkorpus mit 12.821 Dateien waere
// das die Groessenordnung Gigabyte gewesen, fuer einen Index, der am Ende
// nur ein paar hundert GUIDs fuehrt.
//
// TryLoadLinesWithFallback ist genau dafuer da; sein eigener Kommentar
// nennt "Pre-Index-Scans" als Zweck. Der Aufrufer besitzt die Liste und
// gibt sie nach jeder Datei frei.
var
  i     : Integer;
  Lines : TStringList;
  Decls : TArray<TInterfaceDecl>;
  D     : TInterfaceDecl;
  Liste : TList<TInterfaceDecl>;
begin
  if AFiles = nil then Exit;
  for i := 0 to AFiles.Count - 1 do
  begin
    if not SameText(ExtractFileExt(AFiles[i]), '.pas') then Continue;
    Decls := nil;
    Lines := TStringList.Create;
    try
      try
        if not TryLoadLinesWithFallback(AFiles[i], Lines) then Continue;
        Decls := ScanFile(AFiles[i], Lines);
      except
        // Eine Datei, die sich nicht lesen laesst, kostet ihre GUIDs -
        // nicht den Index. Den Lesefehler meldet fkFileReadError im
        // Hauptlauf ohnehin.
        Continue;
      end;
    finally
      Lines.Free;
    end;

    for D in Decls do
    begin
      if D.Guid = '' then Continue;
      if not FByGuid.TryGetValue(D.Guid, Liste) then
      begin
        Liste := TList<TInterfaceDecl>.Create;
        FByGuid.Add(D.Guid, Liste);
      end;
      Liste.Add(D);
      Inc(FCount);
    end;
  end;
end;

function TInterfaceGuidIndex.SitesOf(const AGuid: string): TArray<TInterfaceDecl>;
var
  Liste : TList<TInterfaceDecl>;
begin
  Result := nil;
  if AGuid = '' then Exit;
  if FByGuid.TryGetValue(AGuid, Liste) then
    Result := Liste.ToArray;
end;

end.
