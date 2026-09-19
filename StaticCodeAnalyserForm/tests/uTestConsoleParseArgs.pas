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
    // --dialect (Lazarus A2): Wertemenge hart, auto mit eigenem Text
    [Test] procedure Dialect_FpcMitGleichheitszeichen;
    [Test] procedure Dialect_FpcMitLeerzeichen;
    [Test] procedure Dialect_NichtAngegeben_BleibtLeer;
    [Test] procedure Dialect_UngueltigerWert_ParseError;
    [Test] procedure Dialect_Auto_ParseErrorMitHinweis;
    // ---- FixtureFilterAnker (Blocker-Fix, Audit 2026-09-15 P1) ----
    [Test] procedure Anker_PathGewinnt;
    [Test] procedure Anker_FileModus_IstDateiVerzeichnis;
    [Test] procedure Anker_ProjektModus_IstProjektVerzeichnis;
    [Test] procedure Anker_GruppenModus_IstGruppenVerzeichnis;
    [Test] procedure Anker_OhneZiel_BleibtLeer;
  end;

implementation

// noinspection-file HardcodedPath
// Die woertlichen Laufwerkspfade SIND die Testdaten dieser Fixtures
// (ParseArgs-Argumente, FixtureFilterAnker-Kaskade) - gleiche
// Einordnung wie in uTestDetectorUtils. Der fruehere Kommentar an
// dieser Stelle begruendete das FEHLEN des Markers mit einer Messung
// vom 08.09. ("Detektor gated auf Assertionen, const faellt nicht
// darunter") - der Selbstscan vom 19.09. widerlegt sie: SCA016 feuert
// inzwischen auch auf QUELLE_B und auf Argument-Literale. Messungen
// altern; der Marker unterdrueckt jetzt real Funde und ist damit kein
// SCA165-Kandidat mehr.

uses
  System.SysUtils,   // TStringHelper.ToLower (Dialect_Auto-Test) - ohne
                     // die Unit expandiert der Inline-Helper nicht (H2443)
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

{ --- --dialect (Lazarus A2) -------------------------------------- }
//
// Der Schalter waehlt den Quelltext-Dialekt; fpc sammelt beim
// Verzeichnis-Walk zusaetzlich *.pp ein. Die Wertemenge wird HART
// geprueft: ein Tippfehler, der still auf den Delphi-Default
// fiele, waere der wirkungslose Schalter aus der SCA007-Lehre.

procedure TTestConsoleParseArgs.Dialect_FpcMitGleichheitszeichen;
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--dialect=fpc']);
  Assert.AreEqual<string>('', A.ParseError,
    '--dialect=fpc ist gueltig: ' + A.ParseError);
  Assert.AreEqual<string>('fpc', A.Dialect,
    'der Wert muss ankommen, nicht im ''=''-Splitter verschwinden');
end;

procedure TTestConsoleParseArgs.Dialect_FpcMitLeerzeichen;
// Beide Schreibweisen muessen dasselbe ergeben - GetValue nimmt
// bei fehlendem = das Folgeargument.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--dialect', 'fpc']);
  Assert.AreEqual<string>('', A.ParseError);
  Assert.AreEqual<string>('fpc', A.Dialect);
end;

procedure TTestConsoleParseArgs.Dialect_NichtAngegeben_BleibtLeer;
// DIE KLAMMER: ohne den Schalter bleibt das Feld leer - nur so
// bleibt nicht angegeben von explizit delphi unterscheidbar
// (wichtig, sobald in A6 der ini-Schluessel dazukommt und die
// Praezedenz CLI-gewinnt-gegen-ini gebaut wird).
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B]);
  Assert.AreEqual<string>('', A.ParseError);
  Assert.AreEqual<string>('', A.Dialect,
    'ohne Schalter bleibt Dialect leer (= Engine-Default dlDelphi)');
end;

procedure TTestConsoleParseArgs.Dialect_UngueltigerWert_ParseError;
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--dialect=lazarus']);
  Assert.IsTrue(A.ParseError <> '',
    'ein unbekannter Dialekt muss ein Parse-Fehler sein, nicht still der Delphi-Default');
  Assert.IsTrue(Pos('--dialect', A.ParseError) > 0,
    'die Meldung muss den Schalter nennen: ' + A.ParseError);
end;

procedure TTestConsoleParseArgs.Dialect_Auto_ParseErrorMitHinweis;
// UMGEWIDMET (A6/C2, 2026-09-18): auto ist jetzt IMPLEMENTIERT
// (V1: Aufloesung an der Scan-Wurzel, Vertrag an ErmittleAutoDialekt
// in uConsoleRunner) - ParseArgs akzeptiert den Wert ohne Fehler.
// Der Name des Tests bleibt, damit die Historie der Umwidmung im
// Blame sichtbar ist; er prueft jetzt die AKZEPTANZ. Vor C2 war
// dieser Inhalt rot (auto lieferte einen ParseError).
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--dialect=auto']);
  Assert.AreEqual('', A.ParseError,
    'auto ist seit C2 ein gueltiger Wert');
  Assert.AreEqual('auto', A.Dialect.ToLower,
    'der Wert kommt roh im Args-Feld an');
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

{ ---- FixtureFilterAnker (Blocker-Fix, Audit 2026-09-15 P1) ---- }
// Der Test-Fixture-Filter braucht eine Scanwurzel als Anker. In
// --file/--project/--project-group war er leer (Args.Path-Exklusivitaet)
// und der Filter warf explizit benannte Ziele unter .../tests/...
// komplett weg. Diese Tests pinnen die Anker-Kaskade.

procedure TTestConsoleParseArgs.Anker_PathGewinnt;
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs(['--path', 'C:\repo\src']);
  Assert.AreEqual('C:\repo\src', FixtureFilterAnker(A));
end;

procedure TTestConsoleParseArgs.Anker_FileModus_IstDateiVerzeichnis;
// GENAU das Minimalpaar des Audits: --file auf eine Datei unter
// .../tests/... muss denselben Anker ergeben wie --path auf ihr
// Verzeichnis - vorher war der Anker leer und der Filter matchte
// '/tests/' im Absolutpfad.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs(
    ['--file', 'D:\korpus\tests\examples\ArrowButton\Unit1.pas']);
  Assert.AreEqual('D:\korpus\tests\examples\ArrowButton',
    FixtureFilterAnker(A));
end;

procedure TTestConsoleParseArgs.Anker_ProjektModus_IstProjektVerzeichnis;
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs(
    ['--project', 'D:\korpus\Samples\Demo\App.dproj']);
  Assert.AreEqual('D:\korpus\Samples\Demo', FixtureFilterAnker(A));
end;

procedure TTestConsoleParseArgs.Anker_GruppenModus_IstGruppenVerzeichnis;
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs(
    ['--project-group', 'D:\korpus\All.groupproj']);
  Assert.AreEqual('D:\korpus', FixtureFilterAnker(A));
end;

procedure TTestConsoleParseArgs.Anker_OhneZiel_BleibtLeer;
// Der Fehlwert '' heisst "kein Anker" und laesst dem Filter sein
// dokumentiertes Alt-Verhalten. GetCurrentDir waere ein STILLER
// Verhaltenswechsel, der vom Aufrufort abhinge. Real erreichen ihn
// nur Grenzfaelle - --diff/--branch erzwingen --path schon im Parser
// (ihr Anker ist also immer gesetzt); der Test pinnt den Fehlwert
// trotzdem, damit niemand ihn "hilfreich" auf CWD umbiegt.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([]);
  Assert.AreEqual('', FixtureFilterAnker(A));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleParseArgs);

end.
