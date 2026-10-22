unit uBulbDecision;

{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}

// Ob die Editor-Gluehbirne an der Caret-Zeile erscheint - reine Logik,
// ohne VCL und ohne ToolsAPI (Review 2026-10-14, MAJOR "Logik ohne
// Tests"; vorher TFindingBulbManager.WantsBulb in uIDEFindingBulb).
// Getestet in TestProject (uTestBulbDecision) und im FPC-Pruefstand
// (SCA.SharedUI/tools/run_fpc_pure.sh). Der FPC-Modus ist delphiUNICODE
// wie in uHitCacheRepair: string ist hier derselbe Typ wie unter Delphi.
//
// ZWEI STUFEN (Konzept GluehbirneAnzeige 2026-10-08, Weg C):
//   1. billig - gibt es Funde auf der Zeile (und einen Anbieter)? Das
//      fragt der Aufrufer bei seiner Fundquelle (WantsFindings ->
//      NoteFindings mit dem Fingerabdruck der Funde). Je Zeile hoechstens
//      einmal je BULB_FINDINGS_RECHECK_MS neu, damit ein neuer Scan
//      nachzieht, ohne dass jede Runde die Fundliste durchsucht.
//   2. teuer - bieten die Anbieter eine verfuegbare Hilfe an? reDelphix
//      parst dafuer die ganze Datei. Deshalb erst, wenn der Caret
//      BULB_SETTLE_MS auf derselben Zeile ruht (Durchpfeilen fragt nie),
//      und je Schluessel Datei+Zeile+Zeilentext+Funde nur EINMAL
//      (BeginProviderCheck -> NoteProviderAnswer). Tippen auf der Zeile
//      aendert den Schluessel; bis zur neuen Antwort gilt die alte weiter
//      (sonst blinkte die Birne bei jedem Tastendruck); eine andere Zeile
//      beginnt ohne Birne.
//   BeginProviderCheck merkt die Frage als GESTELLT, bevor der Aufrufer
//   fragt: wirft ein Anbieter (Stapelueberlauf im Parse), fragte der
//   250-ms-Takt dieselbe Zeile sonst sofort wieder - ohne Schutzseite
//   endet der zweite Ueberlauf hart.
//
// UNSICHTBARE ZEILE (NoteLineHidden): liegt die Caret-Zeile ausserhalb des
// sichtbaren Bereichs, fragt der Aufrufer weder Funde noch Anbieter -
// stempelt aber den Stand, damit der Takt (NeedsRevisit) nicht alle
// 250 ms neu plant, bis die Zeile wieder sichtbar ist (Review 2026-10-14,
// Minor "Caret ausserhalb -> 250-ms-Neuplanung"). Wird sie sichtbar, holt
// WantsFindings die Funde nach (der Fingerabdruck gilt als unbekannt); eine
// schon beantwortete Anbieter-Frage bleibt dabei beantwortet - gleiche
// Funde, gleicher Schluessel, keine neue Frage (Gegen-Review Welle 1,
// Minor 6: sonst parste reDelphix nach jedem Raus- und Reinscrollen).
//
// Zeitbasis UInt64 (GetTickCount64): kein Abschneiden nach 49,7 Tagen. Die
// Uhr kommt als Parameter herein - die Tests laufen ohne Sleep.

interface

const
  // Ein neuer Scan zieht die Birne spaetestens so nach.
  BULB_FINDINGS_RECHECK_MS = 1000;
  // So lange ruht der Caret, bevor die Anbieter gefragt werden.
  BULB_SETTLE_MS = 400;

type
  // Entscheidung je Editor. Als Wert in einem Dictionary ist der
  // Nullzustand gueltig und gleich dem nach Reset; eine lokale Variable
  // braucht Reset, weil Delphi dort nur die verwalteten Felder vorbelegt.
  TBulbDecision = record
  private
    FFileName  : string;
    FLine      : Integer;
    FSigKnown  : Boolean;   // FFindSig wurde fuer FFileName/FLine bestimmt
    FFindSig   : string;    // Fingerabdruck der Funde; '' = keine (oder kein Anbieter)
    FFindStamp : UInt64;    // Uhr, als FFindSig bestimmt bzw. die Zeile gestempelt wurde
    FKey       : string;    // Datei, Zeile, Zeilentext, FFindSig - wofuer FHasFixes gilt
    FKeySince  : UInt64;    // seit wann der Caret auf FKey ruht
    FChecked   : Boolean;   // die Anbieter wurden fuer FKey gefragt
    FHasFixes  : Boolean;   // ... und boten eine verfuegbare Hilfe an
    function SameLine(const AFile: string; ALine: Integer): Boolean;
    function StampExpired(ANowMs: UInt64): Boolean;
    procedure BeginLine(const AFile: string; ALine: Integer; ANowMs: UInt64);
  public
    // Ausgangszustand: keine Zeile, nichts gefragt.
    procedure Reset;
    // Stufe 1: True heisst "jetzt die Funde der Zeile holen und mit
    // NoteFindings melden" - andere Zeile oder Datei, Fingerabdruck
    // unbekannt (nach NoteLineHidden) oder aelter als
    // BULB_FINDINGS_RECHECK_MS.
    function WantsFindings(const AFile: string; ALine: Integer;
      ANowMs: UInt64): Boolean;
    // Die Funde der Zeile als Fingerabdruck ('' = keine); setzt die Zeile
    // und stempelt die Uhr.
    procedure NoteFindings(const AFile: string; ALine: Integer;
      const ASignature: string; ANowMs: UInt64);
    // Die Caret-Zeile ist nicht sichtbar: Zeile und Uhr stempeln, den
    // Fingerabdruck als unbekannt merken; keine Birne.
    procedure NoteLineHidden(const AFile: string; ALine: Integer;
      ANowMs: UInt64);
    // Stufe 2: True heisst "jetzt die Anbieter fragen und mit
    // NoteProviderAnswer antworten"; die Frage gilt ab hier als gestellt
    // (ohne Antwort: keine Hilfe). Ein Verb, keine Frage (bis 2026-10-22
    // WantsProviderCheck; Review Woche G04-03): jeder Aufruf schreibt den
    // Zustand fort - Schluessel, Ruhezeit-Beginn, "gefragt" -, ist also
    // je Runde EINMAL zu rufen, nie "nur zum Nachsehen". False ohne Funde, vor Ablauf von
    // BULB_SETTLE_MS oder wenn der Schluessel schon beantwortet ist. Die
    // Ruhezeit beginnt mit der ERSTEN Bewertung eines Schluessels (dem
    // Aufruf, der ihn zum ersten Mal sieht) - also mit der Ankunft des
    // Carets auf der Zeile, nicht mit NoteFindings.
    function BeginProviderCheck(const ALineText: string;
      ANowMs: UInt64): Boolean;
    // Antwort der Anbieter fuer den aktuellen Schluessel - auch vom Menue,
    // das beim Oeffnen frisch fragt und die gemerkte Antwort korrigiert.
    procedure NoteProviderAnswer(AHasFixes: Boolean);
    // Die Birne erscheint: Funde da, Anbieter gefragt, Hilfe verfuegbar.
    function ShowsBulb: Boolean;
    // Fuer den Takt (PollCaret): neu bewerten, wenn Zeile oder Datei
    // wechselten, der Stempel alt ist oder eine Anbieter-Frage darauf
    // wartet, dass der Caret lange genug ruht.
    function NeedsRevisit(const AFile: string; ALine: Integer;
      ANowMs: UInt64): Boolean;
  end;

implementation

uses
  System.SysUtils;

const
  // Typisiert, damit FPC die Verkettung nicht ueber AnsiString fuehrt.
  KEY_SEP : string = #1;

function ElapsedMs(ASince, ANow: UInt64): UInt64;
// Laeuft die Uhr rueckwaerts (GetTickCount64 tut das nicht, eine fremde
// Uhr vielleicht), gilt die Frist als abgelaufen: lieber einmal zu frueh
// fragen als eine Birne, die nie kommt. Ohne den Vergleich liefe die
// Subtraktion unter $Q+ in eine Ausnahme.
begin
  if ANow < ASince then
    Result := High(UInt64)
  else
    Result := ANow - ASince;
end;

procedure TBulbDecision.Reset;
begin
  FFileName  := '';
  FLine      := 0;
  FSigKnown  := False;
  FFindSig   := '';
  FFindStamp := 0;
  FKey       := '';
  FKeySince  := 0;
  FChecked   := False;
  FHasFixes  := False;
end;

function TBulbDecision.SameLine(const AFile: string;
  ALine: Integer): Boolean;
begin
  Result := (FLine = ALine) and SameText(FFileName, AFile);
end;

function TBulbDecision.StampExpired(ANowMs: UInt64): Boolean;
begin
  Result := ElapsedMs(FFindStamp, ANowMs) >= BULB_FINDINGS_RECHECK_MS;
end;

procedure TBulbDecision.BeginLine(const AFile: string; ALine: Integer;
  ANowMs: UInt64);
begin
  FFileName  := AFile;
  FLine      := ALine;
  FFindStamp := ANowMs;
end;

function TBulbDecision.WantsFindings(const AFile: string; ALine: Integer;
  ANowMs: UInt64): Boolean;
begin
  Result := not FSigKnown or not SameLine(AFile, ALine)
    or StampExpired(ANowMs);
end;

procedure TBulbDecision.NoteFindings(const AFile: string; ALine: Integer;
  const ASignature: string; ANowMs: UInt64);
begin
  BeginLine(AFile, ALine, ANowMs);
  FSigKnown := True;
  FFindSig  := ASignature;
end;

procedure TBulbDecision.NoteLineHidden(const AFile: string; ALine: Integer;
  ANowMs: UInt64);
begin
  BeginLine(AFile, ALine, ANowMs);
  FSigKnown := False;
  FFindSig  := '';
  // Eine beantwortete Anbieter-Frage bleibt beantwortet: wird die Zeile
  // wieder sichtbar und sind die Funde dieselben, gilt der Schluessel
  // weiter, und niemand parst neu (vorher: FKey immer leer - reDelphix
  // parste nach jedem Raus- und Reinscrollen die Datei erneut; Gegen-
  // Review Welle 1, Minor 6). Nur eine noch OFFENE Frage wird verworfen -
  // sie hielte NeedsRevisit sonst alle 250 ms wach, obwohl niemand fragt.
  if not FChecked then
    FKey := '';
end;

function TBulbDecision.BeginProviderCheck(const ALineText: string;
  ANowMs: UInt64): Boolean;
var
  Prefix : string;
  Key    : string;
begin
  Result := False;
  if not FSigKnown or (FFindSig = '') then
  begin
    FKey := '';
    Exit;
  end;
  Prefix := FFileName + KEY_SEP + IntToStr(FLine) + KEY_SEP;
  Key    := Prefix + ALineText + KEY_SEP + FFindSig;
  if Key <> FKey then
  begin
    // Dieselbe Zeile, nur Text oder Funde anders (Tippen): die alte
    // Antwort gilt vorlaeufig weiter. Eine andere Zeile beginnt ohne Birne.
    FHasFixes := FChecked and FHasFixes
      and (Copy(FKey, 1, Length(Prefix)) = Prefix);
    FKey      := Key;
    FKeySince := ANowMs;
    FChecked  := False;
  end;
  if FChecked then Exit;
  if ElapsedMs(FKeySince, ANowMs) < BULB_SETTLE_MS then Exit;
  // ERST als gefragt merken, dann fragen lassen (s. Kopf).
  FChecked  := True;
  FHasFixes := False;
  Result    := True;
end;

procedure TBulbDecision.NoteProviderAnswer(AHasFixes: Boolean);
begin
  FChecked  := True;
  FHasFixes := AHasFixes;
end;

function TBulbDecision.ShowsBulb: Boolean;
// FHasFixes ohne FChecked: beim Tippen auf der Zeile ist die Frage fuer den
// neuen Schluessel offen, die alte Antwort gilt aber weiter (s. Kopf).
begin
  Result := FSigKnown and (FFindSig <> '') and FHasFixes;
end;

function TBulbDecision.NeedsRevisit(const AFile: string; ALine: Integer;
  ANowMs: UInt64): Boolean;
begin
  Result := not SameLine(AFile, ALine) or StampExpired(ANowMs)
    or ((FKey <> '') and not FChecked);
end;

end.
