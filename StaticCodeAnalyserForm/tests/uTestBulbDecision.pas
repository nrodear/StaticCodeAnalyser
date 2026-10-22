unit uTestBulbDecision;

// Tests fuer uBulbDecision (SCA.SharedUI): ob die Editor-Gluehbirne an der
// Caret-Zeile erscheint - zwei Stufen (Funde, dann Anbieter), Ruhezeit
// des Carets, ein Fingerabdruck je Zeile, Nachziehen nach einem Scan
// (Review 2026-10-14: vorher ungetestet in uIDEFindingBulb.WantsBulb).
//
// Die Uhr ist ein Parameter: die Tests spielen Sekunden in Millisekunden
// durch, ohne Sleep. "Funde holen" und "Anbieter fragen" tut hier der Test
// selbst (NoteFindings / NoteProviderAnswer) - genau wie der Aufrufer in
// der IDE, dessen Seite (ToolsAPI, Fundquelle, reDelphix) ungedeckt bleibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBulbDecision = class
  public
    [Test] procedure FreshLine_WantsFindings_NoFindings_NoBulb;
    [Test] procedure Findings_ProvidersAskedOnlyAfterSettle;
    [Test] procedure AnsweredKey_IsNotAskedAgain;
    [Test] procedure TypingOnLine_KeepsOldAnswer_ThenAsksAgain;
    [Test] procedure OtherLine_StartsWithoutBulb;
    [Test] procedure SameLine_FindingsRecheckedAfterOneSecond;
    [Test] procedure NewScan_NewSignature_AsksAgain_KeepsBulbMeanwhile;
    [Test] procedure QuestionWithoutAnswer_NotRepeated_NoBulb;
    [Test] procedure HiddenLine_StampsAndRevisitsOnlyAfterExpiry;
    [Test] procedure NeedsRevisit_WhileProviderQuestionWaitsForSettle;
    [Test] procedure MenuAnswer_CorrectsDecision;
    [Test] procedure ClockBackwards_CountsAsExpired;
    // Gegen-Review Welle 1, Minor 6: Birne an -> Zeile unsichtbar -> wieder
    // sichtbar: die Antwort bleibt, keine neue Anbieterfrage.
    [Test] procedure HiddenThenVisible_KeepsAnsweredKey;
    // Review Woche G04-04: die Uebergaenge, die nur der Prefix-Vergleich und
    // das Leeren von FKey ohne Funde tragen - "FChecked and FHasFixes"
    // allein liesse in allen dreien die alte Antwort wiederaufleben.
    [Test] procedure FindingsGoneAndBack_NoOldAnswer;
    [Test] procedure HiddenOnOtherLine_ThenFindings_NoOldAnswer;
    [Test] procedure OtherFileSameLine_StartsWithoutBulb_UntilAnswered;
  end;

implementation

uses
  uBulbDecision;

const
  FILE_A = 'UnitA.pas';
  FILE_B = 'UnitB.pas';
  SIG_1  = '12:10:Obj';
  SIG_2  = '12:10:Obj' + #1 + '44:10:Fmt';
  TEXT_1 = '  Obj := TObject.Create;';
  TEXT_2 = '  Obj := TObject.Create; // x';

// Eine Zeile mit Funden, Anbieter gefragt und bejaht - der haeufigste
// Ausgangszustand der Tests. Rueckgabe: die Uhr nach der Antwort.
function BulbOn(var D: TBulbDecision; ANow: UInt64): UInt64;
begin
  D.Reset;
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, ANow));
  D.NoteFindings(FILE_A, 10, SIG_1, ANow);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, ANow), 'noch nicht geruht');
  Result := ANow + BULB_SETTLE_MS;
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, Result), 'nach der Ruhezeit');
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb);
end;

procedure TTestBulbDecision.FreshLine_WantsFindings_NoFindings_NoBulb;
var
  D : TBulbDecision;
begin
  D.Reset;
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, 1000), 'neue Zeile: Funde holen');
  D.NoteFindings(FILE_A, 10, '', 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 5000),
    'ohne Funde werden die Anbieter nie gefragt');
  Assert.IsFalse(D.ShowsBulb);
  Assert.IsFalse(D.WantsFindings(FILE_A, 10, 1500), 'Stempel frisch');
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, 1500), 'kein Takt noetig');
end;

procedure TTestBulbDecision.Findings_ProvidersAskedOnlyAfterSettle;
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1000));
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1000 + BULB_SETTLE_MS - 1),
    'eine Millisekunde zu frueh');
  Assert.IsFalse(D.ShowsBulb, 'vor der Antwort keine Birne');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, 1000 + BULB_SETTLE_MS));
  Assert.IsFalse(D.ShowsBulb, 'gefragt heisst noch nicht bejaht');
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb);
end;

procedure TTestBulbDecision.AnsweredKey_IsNotAskedAgain;
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 5000),
    'derselbe Schluessel wird nur einmal gefragt');
  Assert.IsTrue(D.ShowsBulb, 'die Antwort gilt weiter');
end;

procedure TTestBulbDecision.TypingOnLine_KeepsOldAnswer_ThenAsksAgain;
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  // Tippen: anderer Zeilentext, gleiche Zeile.
  Assert.IsFalse(D.BeginProviderCheck(TEXT_2, T + 10), 'Ruhezeit beginnt neu');
  Assert.IsTrue(D.ShowsBulb, 'die alte Antwort gilt vorlaeufig - kein Blinken');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_2, T + 10 + BULB_SETTLE_MS));
  D.NoteProviderAnswer(False);
  Assert.IsFalse(D.ShowsBulb, 'die neue Antwort ersetzt die alte');
end;

procedure TTestBulbDecision.OtherLine_StartsWithoutBulb;
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  Assert.IsTrue(D.WantsFindings(FILE_A, 11, T + 10), 'andere Zeile');
  D.NoteFindings(FILE_A, 11, SIG_1, T + 10);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 10));
  Assert.IsFalse(D.ShowsBulb, 'eine andere Zeile beginnt ohne Birne');
  // Andere Datei, gleiche Zeilennummer: ebenso.
  Assert.IsTrue(D.WantsFindings(FILE_B, 11, T + 20), 'andere Datei');
end;

procedure TTestBulbDecision.SameLine_FindingsRecheckedAfterOneSecond;
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 1000);
  Assert.IsFalse(D.WantsFindings(FILE_A, 10, 1000 + BULB_FINDINGS_RECHECK_MS - 1));
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, 1000 + BULB_FINDINGS_RECHECK_MS),
    'ein neuer Scan zieht spaetestens nach einer Sekunde nach');
  Assert.IsTrue(D.NeedsRevisit(FILE_A, 10, 1000 + BULB_FINDINGS_RECHECK_MS));
end;

procedure TTestBulbDecision.NewScan_NewSignature_AsksAgain_KeepsBulbMeanwhile;
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  T := T + BULB_FINDINGS_RECHECK_MS;
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, T));
  D.NoteFindings(FILE_A, 10, SIG_2, T);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T), 'neuer Schluessel, Ruhezeit');
  Assert.IsTrue(D.ShowsBulb, 'bis zur neuen Antwort gilt die alte');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, T + BULB_SETTLE_MS));
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb);
end;

procedure TTestBulbDecision.QuestionWithoutAnswer_NotRepeated_NoBulb;
// Ein werfender Anbieter (Stapelueberlauf im Parse) antwortet nie - die
// Frage darf trotzdem nicht alle 250 ms wiederholt werden.
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1000), 'Ankunft: Ruhezeit beginnt');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, 1000 + BULB_SETTLE_MS));
  Assert.IsFalse(D.ShowsBulb);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1800), 'gilt als gefragt');
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, 1900), 'keine offene Frage mehr');
end;

procedure TTestBulbDecision.HiddenLine_StampsAndRevisitsOnlyAfterExpiry;
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteLineHidden(FILE_A, 10, 1000);
  Assert.IsFalse(D.ShowsBulb);
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, 1500),
    'unsichtbare Zeile: kein Takt alle 250 ms');
  Assert.IsTrue(D.NeedsRevisit(FILE_A, 10, 1000 + BULB_FINDINGS_RECHECK_MS));
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, 1200),
    'wird die Zeile sichtbar, sind die Funde unbekannt - holen');
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1200),
    'ohne bekannte Funde keine Anbieter-Frage');
end;

procedure TTestBulbDecision.NeedsRevisit_WhileProviderQuestionWaitsForSettle;
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1000));
  Assert.IsTrue(D.NeedsRevisit(FILE_A, 10, 1100),
    'die Frage wartet auf die Ruhezeit - der Takt muss wiederkommen');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, 1000 + BULB_SETTLE_MS));
  D.NoteProviderAnswer(False);
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, 1500), 'beantwortet, Stempel frisch');
end;

procedure TTestBulbDecision.MenuAnswer_CorrectsDecision;
var
  D : TBulbDecision;
begin
  BulbOn(D, 1000);
  // Das Menue fragt beim Oeffnen frisch: nichts mehr da.
  D.NoteProviderAnswer(False);
  Assert.IsFalse(D.ShowsBulb, 'die frische Antwort korrigiert die gemerkte');
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb);
end;

procedure TTestBulbDecision.ClockBackwards_CountsAsExpired;
var
  D : TBulbDecision;
begin
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 5000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 5000), 'Ruhezeit beginnt bei 5000');
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, 100),
    'rueckwaerts laufende Uhr: lieber einmal zu frueh als nie');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, 100),
    'auch die Ruhezeit gilt dann als abgelaufen');
end;

procedure TTestBulbDecision.HiddenThenVisible_KeepsAnsweredKey;
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  D.NoteLineHidden(FILE_A, 10, T + 10);
  Assert.IsFalse(D.ShowsBulb, 'unsichtbar: keine Birne');
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, T + 20), 'unsichtbar: kein Takt');
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, T + 30), 'sichtbar: Funde holen');
  D.NoteFindings(FILE_A, 10, SIG_1, T + 30);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 30 + BULB_SETTLE_MS),
    'gleiche Funde, gleicher Schluessel: die Antwort gilt - reDelphix '
    + 'parst nicht erneut');
  Assert.IsTrue(D.ShowsBulb, 'die Birne ist wieder da');
  // Andere Funde nach dem Verstecken: neuer Schluessel, Frage nach der
  // Ruhezeit - bis dahin gilt die alte Antwort (wie beim Tippen).
  D.NoteLineHidden(FILE_A, 10, T + 40);
  D.NoteFindings(FILE_A, 10, SIG_2, T + 50);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 50), 'Ruhezeit beginnt');
  Assert.IsTrue(D.ShowsBulb, 'bis zur neuen Antwort gilt die alte');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, T + 50 + BULB_SETTLE_MS));
  // Eine noch OFFENE Frage beim Verstecken wird verworfen - kein Takt.
  D.Reset;
  D.NoteFindings(FILE_A, 10, SIG_1, 1000);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, 1000), 'Ruhezeit beginnt');
  D.NoteLineHidden(FILE_A, 10, 1100);
  Assert.IsFalse(D.NeedsRevisit(FILE_A, 10, 1200),
    'offene Frage verworfen: kein Takt alle 250 ms');
end;

procedure TTestBulbDecision.FindingsGoneAndBack_NoOldAnswer;
// Birne an -> neuer Scan ohne Funde -> derselbe Fund wieder: die Antwort
// von vor dem Verschwinden gilt nicht mehr (FKey wurde ohne Funde geleert).
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000) + BULB_FINDINGS_RECHECK_MS;
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, T), 'Stempel abgelaufen');
  D.NoteFindings(FILE_A, 10, '', T);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T), 'ohne Funde keine Frage');
  Assert.IsFalse(D.ShowsBulb, 'Funde weg: keine Birne');
  T := T + BULB_FINDINGS_RECHECK_MS;
  Assert.IsTrue(D.WantsFindings(FILE_A, 10, T));
  D.NoteFindings(FILE_A, 10, SIG_1, T);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T), 'Ruhezeit beginnt neu');
  Assert.IsFalse(D.ShowsBulb,
    'Funde wieder da: die alte Antwort lebt nicht wieder auf');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, T + BULB_SETTLE_MS),
    'die Anbieter werden neu gefragt');
end;

procedure TTestBulbDecision.HiddenOnOtherLine_ThenFindings_NoOldAnswer;
// NoteLineHidden auf einer ANDEREN Zeile laesst FKey (Zeile 10) beantwortet
// stehen; die Funde der neuen Zeile 11 duerfen die Antwort nicht erben.
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  D.NoteLineHidden(FILE_A, 11, T + 10);
  Assert.IsFalse(D.ShowsBulb, 'unsichtbar: keine Birne');
  Assert.IsTrue(D.WantsFindings(FILE_A, 11, T + 20), 'sichtbar: Funde holen');
  D.NoteFindings(FILE_A, 11, SIG_1, T + 20);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 20), 'Ruhezeit beginnt');
  Assert.IsFalse(D.ShowsBulb, 'Zeile 11 erbt die Antwort von Zeile 10 nicht');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, T + 20 + BULB_SETTLE_MS));
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb);
end;

procedure TTestBulbDecision.OtherFileSameLine_StartsWithoutBulb_UntilAnswered;
// Andere Datei, GLEICHE Zeilennummer und gleicher Text: der Prefix traegt
// die Datei, die Antwort fuer UnitA gilt fuer UnitB nicht.
var
  D : TBulbDecision;
  T : UInt64;
begin
  T := BulbOn(D, 1000);
  Assert.IsTrue(D.WantsFindings(FILE_B, 10, T + 10), 'andere Datei');
  D.NoteFindings(FILE_B, 10, SIG_1, T + 10);
  Assert.IsFalse(D.BeginProviderCheck(TEXT_1, T + 10), 'Ruhezeit beginnt');
  Assert.IsFalse(D.ShowsBulb, 'eine andere Datei beginnt ohne Birne');
  Assert.IsTrue(D.BeginProviderCheck(TEXT_1, T + 10 + BULB_SETTLE_MS));
  D.NoteProviderAnswer(True);
  Assert.IsTrue(D.ShowsBulb, 'nach der eigenen Antwort erscheint sie');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBulbDecision);

end.
