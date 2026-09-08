unit uTestConsoleParseArgs;

// Tests fuer TConsoleRunner.ParseArgs - die Zerlegung der Kommandozeile.
//
// WARUM ES DIESE UNIT ERST SEIT 08.09. GIBT: ParseArgs ist laut eigenem
// Kommentar ausdruecklich public gemacht worden, damit Tests die
// Parse-Logik isoliert pruefen koennen. Es gab trotzdem keinen einzigen
// Test dafuer - getestet war nur die Exit-Code-Haelfte der CLI
// (uTestConsoleExitCode). Der Modul-Codereview hat beides zugleich
// gefunden: die fehlende Abdeckung und den Fehler, den sie verdeckte -
// '--full=false' setzte den Schalter auf TRUE.
//
// Diese Fixture ist die Schwester von uTestConsoleExitCode: dort die
// Ausgangsseite der CLI, hier die Eingangsseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleParseArgs = class
  public
    // ---- Boolean-Schalter nehmen keinen Wert ----
    [Test] procedure BooleanSchalterMitWert_IstEinFehler;
    [Test] procedure BooleanSchalterMitWert_SetztDenSchalterNicht;
    [Test] procedure BooleanSchalterOhneWert_Greift;
    // Der Waechter darf nicht an einem einzigen Schalter haengen.
    [Test] procedure ZweiterBooleanSchalterMitWert_IstEinFehler;

    // ---- Wert-Schalter nehmen weiter beide Schreibweisen ----
    [Test] procedure WertSchalter_MitGleichheitszeichen;
    [Test] procedure WertSchalter_MitLeerzeichen;
    [Test] procedure FailOn_MitGleichheitszeichen;
    [Test] procedure FailOn_GrossgeschriebenKommtRohAn;
  end;

implementation

// KEIN noinspection HardcodedPath, obwohl QUELLE_B ein Laufwerksliteral
// ist und die Schwester-Fixtures den Marker fuehren: gemessen (Selbstscan
// 08.09.) feuert der Detektor hier gar nicht - er gated in Test-Units auf
// Argumente von Assertionen und Test-Vektorhelfern, eine const-Deklaration
// faellt nicht darunter. Ein Marker, der nichts unterdrueckt, ist selbst
// ein Fund (SCA165), und den hat der eigene Scan prompt gemeldet.

uses
  uConsoleRunner;

// WARUM --file UND NICHT --path: bei --path setzt ParseArgs am Ende
//     if (Result.Path <> '') and not Result.Full and not Result.Branch
//       then Result.Full := True;
// den Schalter selbst. Ein Assert.IsTrue(A.Full) waere damit auch dann
// gruen, wenn der '--full'-Zweig gar nichts mehr tut - der Chargen-
// Review 08.09. hat genau diesen toten Test gefunden. An --file haengt
// die Regel nicht, Full ist dort ausschliesslich Folge von --full.
//
// Die Datei muss nicht existieren: ParseArgs prueft das nicht (die
// Existenzpruefung sitzt in Run, Zeile 1137), und SourceCount wird
// genauso 1.
const
  QUELLE_A = '--file';
  QUELLE_B = 'C:\nicht-vorhanden\u.pas';
  // Wiederholte Pruefwerte als Konstante - der eigene Scan meldet sie
  // sonst als DuplicateString (SCA015), und in einer Fixture, die immer
  // wieder denselben Wert erwartet, ist die Konstante ohnehin die
  // ehrlichere Schreibweise.
  KEIN_FEHLER = 'kein Fehler erwartet';
  PROFILWERT  = 'strict';

procedure TTestConsoleParseArgs.BooleanSchalterMitWert_IstEinFehler;
// DER Waechter des MAJOR vom 08.09.: die '='-Zerlegung laeuft ueber ALLE
// Argumente, auch ueber reine Schalter. '--full=false' wurde in '--full'
// und ein stillschweigend verworfenes 'false' zerlegt.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--full=false']);
  Assert.IsTrue(A.ParseError <> '',
    'ein Wert an einem Boolean-Schalter muss ein Parse-Fehler sein - '
    + 'stillschweigend zu verwerfen liefert dem Aufrufer das Gegenteil '
    + 'dessen, was er geschrieben hat');
  Assert.IsTrue(Pos('--full', A.ParseError) > 0,
    'die Meldung muss den Schalter nennen, sonst sucht der Aufrufer in '
    + 'einer langen Kommandozeile: ' + A.ParseError);
end;

procedure TTestConsoleParseArgs.BooleanSchalterMitWert_SetztDenSchalterNicht;
// Die zweite Haelfte desselben Fehlers, und die wichtigere: der Fehler
// darf nicht gemeldet UND der Schalter trotzdem gesetzt werden. Genau so
// war es vorher - nur ohne die Meldung.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--full=false']);
  Assert.IsFalse(A.Full,
    '--full=false darf --full nicht einschalten');
end;

procedure TTestConsoleParseArgs.BooleanSchalterOhneWert_Greift;
// Gegenprobe: die normale Schreibweise muss unveraendert wirken. Ohne
// diesen Test waere auch eine Aenderung gruen, die Boolean-Schalter
// generell abwuergt.
//
// Traegt nur mit --file als Quelle - an --path haengt eine
// Auto-Default-Regel fuer Full, siehe den Kommentar bei QUELLE_A.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--full', '--quiet']);
  Assert.AreEqual('', A.ParseError,
    'die normale Schreibweise darf keinen Fehler erzeugen');
  Assert.IsTrue(A.Full, '--full muss wirken');
  Assert.IsTrue(A.Quiet, '--quiet muss wirken');
end;

procedure TTestConsoleParseArgs.ZweiterBooleanSchalterMitWert_IstEinFehler;
// Der Waechter darf nicht an --full haengen. Von den 21 Eintraegen in
// CLI_SCHALTER_OHNE_WERT beruehrte bis 08.09. genau einer einen Test -
// die Vollzaehligkeit der Liste haengt am Gate, ihre WIRKSAMKEIT muss
// an mehr als einem Beispiel haengen.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--quiet=0']);
  Assert.IsTrue(A.ParseError <> '',
    'auch --quiet nimmt keinen Wert');
  Assert.IsFalse(A.Quiet,
    '--quiet=0 darf --quiet nicht einschalten');
end;

procedure TTestConsoleParseArgs.WertSchalter_MitGleichheitszeichen;
// Die dritte Richtung: der Fix darf nicht ueberschiessen. Schalter, die
// einen Wert NEHMEN, muessen die '='-Form weiter akzeptieren.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--profile=strict']);
  Assert.AreEqual('', A.ParseError, KEIN_FEHLER);
  Assert.AreEqual(PROFILWERT, A.Profile,
    'die =-Form muss bei Wert-Schaltern weiter greifen');
end;

procedure TTestConsoleParseArgs.WertSchalter_MitLeerzeichen;
// Und die getrennte Schreibweise ebenso - beide Formen sind dokumentiert.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B,
    '--profile', PROFILWERT]);
  Assert.AreEqual('', A.ParseError, KEIN_FEHLER);
  Assert.AreEqual(PROFILWERT, A.Profile,
    'die getrennte Form muss weiter greifen');
end;

procedure TTestConsoleParseArgs.FailOn_MitGleichheitszeichen;
// Am 08.09. ist ein unerreichbarer Zweig auf A.StartsWith('--fail-on=')
// entfernt worden. Dieser Test haelt fest, dass die '='-Form dadurch
// nichts verloren hat - sie lief schon vorher ueber den regulaeren Weg.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--fail-on=error']);
  Assert.AreEqual('', A.ParseError, KEIN_FEHLER);
  Assert.AreEqual('error', A.FailOn,
    '--fail-on=error muss weiter ankommen');
end;

procedure TTestConsoleParseArgs.FailOn_GrossgeschriebenKommtRohAn;
// Die eigentliche Frage hinter dem entfernten Zweig, die der erste
// Test NICHT beantwortet: der tote Zweig haette LowerCase angewandt,
// bei 'error' ist das ein No-op. Erst ein grossgeschriebener Wert
// zeigt, was das Entfernen wirklich bedeutet - der Wert kommt ROH an,
// und die Normalisierung passiert stromabwaerts (Wertpruefung und
// ApplyFailOnPolicy, beide LowerCase(Trim(...))).
//
// Dieser Test haelt damit die Zusage des Commits fest, dass nichts
// verloren ging: verlaesst sich kuenftig jemand darauf, dass FailOn
// schon kleingeschrieben ANKOMMT, wird er hier rot.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--fail-on=ERROR']);
  Assert.AreEqual('', A.ParseError, KEIN_FEHLER);
  Assert.AreEqual('ERROR', A.FailOn, False,
    'der Wert kommt roh an - kleingeschrieben wird er erst bei der '
    + 'Auswertung. AreEqual steht hier bewusst case-SENSITIV, sonst '
    + 'prueft der Fall gar nichts');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleParseArgs);

end.
