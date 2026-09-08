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

    // ---- Wert-Schalter nehmen weiter beide Schreibweisen ----
    [Test] procedure WertSchalter_MitGleichheitszeichen;
    [Test] procedure WertSchalter_MitLeerzeichen;
    [Test] procedure FailOn_MitGleichheitszeichen;
  end;

implementation

uses
  System.SysUtils,
  uConsoleRunner;

// Jeder Aufruf braucht eine Eingabe-Quelle, sonst setzt ParseArgs den
// ParseError 'Keine Eingabe-Quelle' - und der Test praefte dann den
// falschen Fehler. Der Pfad muss nicht existieren; ParseArgs prueft das
// nur fuer --index-root.
const
  QUELLE_A = '--path';
  QUELLE_B = 'C:\nicht-vorhanden';

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
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--full', '--quiet']);
  Assert.AreEqual('', A.ParseError,
    'die normale Schreibweise darf keinen Fehler erzeugen');
  Assert.IsTrue(A.Full, '--full muss wirken');
  Assert.IsTrue(A.Quiet, '--quiet muss wirken');
end;

procedure TTestConsoleParseArgs.WertSchalter_MitGleichheitszeichen;
// Die dritte Richtung: der Fix darf nicht ueberschiessen. Schalter, die
// einen Wert NEHMEN, muessen die '='-Form weiter akzeptieren.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--profile=strict']);
  Assert.AreEqual('', A.ParseError, 'kein Fehler erwartet');
  Assert.AreEqual('strict', A.Profile,
    'die =-Form muss bei Wert-Schaltern weiter greifen');
end;

procedure TTestConsoleParseArgs.WertSchalter_MitLeerzeichen;
// Und die getrennte Schreibweise ebenso - beide Formen sind dokumentiert.
var
  A : TCliArgs;
begin
  A := TConsoleRunner.ParseArgs([QUELLE_A, QUELLE_B, '--profile', 'strict']);
  Assert.AreEqual('', A.ParseError, 'kein Fehler erwartet');
  Assert.AreEqual('strict', A.Profile,
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
  Assert.AreEqual('', A.ParseError, 'kein Fehler erwartet');
  Assert.AreEqual('error', A.FailOn,
    '--fail-on=error muss weiter ankommen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleParseArgs);

end.
