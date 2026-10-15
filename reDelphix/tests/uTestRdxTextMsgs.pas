unit uTestRdxTextMsgs;

// Die gemeinsamen Texte aus uRdxText (Charge C1, Entscheid E29): je
// Funktion ein Test in en, de und fr - nur die beiden Texte der Kopf-Suche
// (MsgNoHeader, MsgHeadersFmt; Nachpruefung C1) teilen einen, die Fixture
// hat damit die Grenze von 20 Tests erreicht. en ist die msgid samt
// Argumenten woertlich. de ist der bisherige Wortlaut der Planer (Stand
// 9713942b) mit echten Umlauten - verglichen wird die gefaltete Fassung
// (Umlaute als ae/oe/ue/ss) mit dem alten Text, dazu die Zahl der echten
// Umlaute; so bleibt die Quelle ASCII, ohne '#$00FC'-Escapes, und ein
// vergessener Umlaut ('pruefen' in de.po) faellt ebenso auf wie ein
// falscher (ein Umlaut in 'Queue'). fr wird mit gefalteten Akzenten
// verglichen.
// Laeuft in reDelphix.Test (echte uLocalization, eingebettete .po) UND im
// FPC-Pruefstand (Stub uLocalization liest die echten i18n/*.po, build.sh
// kopiert alle Sprachen) - jeder Test stellt die Sprache des Laufs ('de')
// wieder her.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTextMsgs = class
  public
    [Test] procedure LineMoved_ThreeLanguages;
    [Test] procedure MovedSuffix_ThreeLanguages;
    [Test] procedure StaleSuffix_ThreeLanguages;
    [Test] procedure NoColumn_ThreeLanguages;
    [Test] procedure StatementEndNotFound_ThreeLanguages;
    [Test] procedure NoValidRange_ThreeLanguages;
    [Test] procedure HeaderEndNotFound_ThreeLanguages;
    [Test] procedure LineStartsInCommentOrString_ThreeLanguages;
    [Test] procedure NoFileOpen_ThreeLanguages;
    [Test] procedure ByHand_ThreeLanguages;
    [Test] procedure CheckByHand_ThreeLanguages;
    [Test] procedure DeleteByHand_ThreeLanguages;
    [Test] procedure DecideByHand_ThreeLanguages;
    [Test] procedure OnlyStatementEmptyBlock_ThreeLanguages;
    [Test] procedure UnclearStatementOwner_ThreeLanguages;
    [Test] procedure LiteralUnreadable_ThreeLanguages;
    [Test] procedure NoOperandInChain_ThreeLanguages;
    [Test] procedure DeclsInClassesOfName_ThreeLanguages;
    [Test] procedure NoLongerAtReportedPlace_ThreeLanguages;
    [Test] procedure HeaderSearch_ThreeLanguages;
  end;

implementation

uses
  uRdxText;

type
  // Ein gemeinsamer Text, aufgerufen mit festen Probe-Argumenten.
  TMsgFunc = function: string;

const
  // Ein Grund mit Format-Zeichen: er muss woertlich durchgehen - die
  // Funktionen setzen ihn als Argument ein, nie als Muster.
  PROBE_REASON = 'R%d';
  // Das letzte ASCII-Zeichen (NonAscii).
  MAX_ASCII = 127;
  // Zeichen jenseits von ASCII und ihre Faltung (Folded): deutsche Umlaute
  // und ss wie in den Pascal-Quellen, franzoesische Akzente ohne Zeichen,
  // die Anfuehrungszeichen << >> als '"', geschuetzte Leerzeichen als ' ',
  // der typografische Apostroph als '''.
  FOLD_CODES: array[0..24] of Word = ($E4, $F6, $FC, $C4, $D6, $DC, $DF,
    $E0, $E2, $E7, $E8, $E9, $EA, $EB, $EE, $EF, $F4, $F9, $FB, $C9, $AB,
    $BB, $A0, $202F, $2019);
  FOLD_TEXTS: array[0..24] of string = ('ae', 'oe', 'ue', 'Ae', 'Oe', 'Ue',
    'ss', 'a', 'a', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'o', 'u', 'u', 'E',
    '"', '"', ' ', ' ', '''');

// ---- Helfer ----

// Die Faltung eines Zeichens nach FOLD_CODES/FOLD_TEXTS, sonst C selbst.
function FoldOf(C: Char): string;
var
  i : Integer;
begin
  for i := Low(FOLD_CODES) to High(FOLD_CODES) do
    if Ord(C) = FOLD_CODES[i] then
      Exit(FOLD_TEXTS[i]);
  Result := C;
end;

// S als ASCII (FoldOf je Zeichen) - der Vergleich mit dem bisherigen,
// umlautfreien Wortlaut der Pascal-Quellen. Jede Faltung hat hoechstens
// zwei Zeichen: der Puffer wird einmal angelegt, nicht je Zeichen verlaengert.
function Folded(const S: string): string;
var
  i, k, n : Integer;
  Rep     : string;
begin
  SetLength(Result, 2 * Length(S));
  n := 0;
  for i := 1 to Length(S) do
  begin
    Rep := FoldOf(S[i]);
    for k := 1 to Length(Rep) do
    begin
      Inc(n);
      Result[n] := Rep[k];
    end;
  end;
  SetLength(Result, n);
end;

// Zahl der Zeichen jenseits von ASCII - in den deutschen Texten genau die
// echten Umlaute.
function NonAscii(const S: string): Integer;
var
  C : Char;
begin
  Result := 0;
  for C in S do
    if Ord(C) > MAX_ASCII then
      Inc(Result);
end;

// AFunc unter en, de und fr: en woertlich gleich AEn, de gefaltet gleich
// ADe (der alte Wortlaut) mit genau AUmlauts echten Umlauten, fr gefaltet
// gleich AFr. Danach gilt wieder die Sprache des Laufs.
procedure Check3(AFunc: TMsgFunc; const AEn, ADe: string; AUmlauts: Integer;
  const AFr: string);
var
  Old, Got : string;
begin
  Old := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('en');
    Got := AFunc;
    Assert.AreEqual(AEn, Got, 'en: die msgid');
    SetRdxLanguageOverride('de');
    Got := AFunc;
    Assert.AreEqual(ADe, Folded(Got), 'de: der bisherige Wortlaut');
    Assert.AreEqual<Integer>(AUmlauts, NonAscii(Got), 'de: echte Umlaute in ' + Got);
    SetRdxLanguageOverride('fr');
    Got := AFunc;
    Assert.AreEqual(AFr, Folded(Got), 'fr');
  finally
    SetRdxLanguageOverride(Old);
  end;
end;

// ---- Probe-Aufrufe (TMsgFunc) ----

function ProbeMovedSuffix: string;
begin
  Result := MsgMovedSuffix(PROBE_REASON);
end;

function ProbeStaleSuffix: string;
begin
  Result := MsgStaleSuffix(PROBE_REASON);
end;

function ProbeEmptyBlock: string;
begin
  Result := MsgOnlyStatementEmptyBlock('begin');
end;

function ProbeUnclearOwner: string;
begin
  Result := MsgUnclearStatementOwner('then');
end;

function ProbeLiteral: string;
begin
  Result := MsgLiteralUnreadable('''a''#');
end;

function ProbeDecls: string;
begin
  Result := MsgDeclsInClassesOfName(2, 'Create');
end;

function ProbeNotAtPlace: string;
begin
  Result := MsgNoLongerAtReportedPlace('Assert(');
end;

function ProbeNoHeader: string;
begin
  Result := MsgNoHeader(PROBE_REASON);
end;

// ---- Tests: ADe ist woertlich der Text der genannten Planer ----

procedure TTestRdxTextMsgs.LineMoved_ThreeLanguages;
// R_MOVED in uRdxCleanupFixes, uRdxFlowFixes, uRdxMagicFixes,
// uRdxResultFixes und uRdxTryFixes.
begin
  Check3(MsgLineMoved, 'line moved? Analyse the file again',
    'Zeile verschoben? Datei neu pruefen', 1,
    'ligne deplacee ? Analysez a nouveau le fichier');
end;

procedure TTestRdxTextMsgs.MovedSuffix_ThreeLanguages;
// '... - ' + R_MOVED bzw. '... - Zeile verschoben? Datei neu pruefen' in
// 12 Units; der Grund geht woertlich durch (kein Muster).
begin
  Check3(ProbeMovedSuffix, 'R%d - line moved? Analyse the file again',
    'R%d - Zeile verschoben? Datei neu pruefen', 1,
    'R%d - ligne deplacee ? Analysez a nouveau le fichier');
end;

procedure TTestRdxTextMsgs.StaleSuffix_ThreeLanguages;
// '... - Fund veraltet? Datei neu pruefen' in uRdxDeclFixes (2x),
// uRdxRoutineFixes und uRdxStructFixes.
begin
  Check3(ProbeStaleSuffix, 'R%d - finding outdated? Analyse the file again',
    'R%d - Fund veraltet? Datei neu pruefen', 1,
    'R%d - resultat perime ? Analysez a nouveau le fichier');
end;

procedure TTestRdxTextMsgs.NoColumn_ThreeLanguages;
// R_NO_COLUMN in uRdxLineFixes und uRdxSimpleFixes, uRdxStructFixes.
begin
  Check3(MsgNoColumn, 'the message has no column',
    'Spalte fehlt in der Meldung', 0, 'la colonne manque dans le message');
end;

procedure TTestRdxTextMsgs.StatementEndNotFound_ThreeLanguages;
// uRdxSimpleFixes, uRdxStructFixes (2x).
begin
  Check3(MsgStatementEndNotFound, 'end of the statement not found',
    'Ende der Anweisung nicht gefunden', 0,
    'fin de l''instruction introuvable');
end;

procedure TTestRdxTextMsgs.NoValidRange_ThreeLanguages;
// uRdxBufferMath, uRdxEditor.
begin
  Check3(MsgNoValidRange, 'no valid range', 'kein gueltiger Bereich', 1,
    'aucune plage valide');
end;

procedure TTestRdxTextMsgs.HeaderEndNotFound_ThreeLanguages;
// uRdxDeclFixes, uRdxRoutineFixes.
begin
  Check3(MsgHeaderEndNotFound, 'end of the header not found',
    'Ende des Kopfs nicht gefunden', 0, 'fin de l''en-tete introuvable');
end;

procedure TTestRdxTextMsgs.LineStartsInCommentOrString_ThreeLanguages;
// uRdxDeclFixes, uRdxLineFixes.
begin
  Check3(MsgLineStartsInCommentOrString,
    'the line starts inside a comment or string',
    'die Zeile beginnt in einem Kommentar oder String', 0,
    'la ligne commence dans un commentaire ou une chaine');
end;

procedure TTestRdxTextMsgs.NoFileOpen_ThreeLanguages;
// R_NO_FILE in uRdxRecipeRunner (auch von uRdxFixTable benutzt).
begin
  Check3(MsgNoFileOpen, 'no file open', 'keine Datei geoeffnet', 1,
    'aucun fichier ouvert');
end;

procedure TTestRdxTextMsgs.ByHand_ThreeLanguages;
// R_BY_HAND in uRdxResultFixes; '; von Hand' in uRdxFixTable,
// uRdxMagicFixes, uRdxSqlTemplate, ' - von Hand' in uRdxScopeTable.
begin
  Check3(MsgByHand, 'by hand', 'von Hand', 0, 'a la main');
end;

procedure TTestRdxTextMsgs.CheckByHand_ThreeLanguages;
// R_BY_HAND in uRdxTryFixes; uRdxDeclFixes, uRdxFlowFixes, uRdxRoutineFixes.
begin
  Check3(MsgCheckByHand, 'check by hand', 'von Hand pruefen', 1,
    'a verifier a la main');
end;

procedure TTestRdxTextMsgs.DeleteByHand_ThreeLanguages;
// uRdxCleanupFixes (6x), uRdxRoutineFixes (3x).
begin
  Check3(MsgDeleteByHand, 'delete by hand', 'von Hand loeschen', 1,
    'a supprimer a la main');
end;

procedure TTestRdxTextMsgs.DecideByHand_ThreeLanguages;
// uRdxCleanupFixes, uRdxFlowFixes.
begin
  Check3(MsgDecideByHand, 'decide by hand', 'von Hand entscheiden', 0,
    'a decider a la main');
end;

procedure TTestRdxTextMsgs.OnlyStatementEmptyBlock_ThreeLanguages;
// uRdxCleanupFixes (InlineContextReason), uRdxFlowFixes (ContextReason).
begin
  Check3(ProbeEmptyBlock,
    'only statement after begin - an empty block would remain (SCA077)',
    'einzige Anweisung hinter begin - es bliebe ein leerer Block (SCA077)', 0,
    'seule instruction apres begin - il resterait un bloc vide (SCA077)');
end;

procedure TTestRdxTextMsgs.UnclearStatementOwner_ThreeLanguages;
// uRdxFlowFixes (ContextReason), uRdxTryFixes.
begin
  Check3(ProbeUnclearOwner,
    'unclear what the statement belongs to ("then" before it)',
    'unklar, wozu die Anweisung gehoert ("then" davor)', 1,
    'impossible de savoir a quoi appartient l''instruction (" then " devant)');
end;

procedure TTestRdxTextMsgs.LiteralUnreadable_ThreeLanguages;
// uRdxRecipes, R_LITERAL in uRdxSqlTemplate.
begin
  Check3(ProbeLiteral, 'literal not readable: ''a''#',
    'Literal nicht lesbar: ''a''#', 0, 'litteral illisible : ''a''#');
end;

procedure TTestRdxTextMsgs.NoOperandInChain_ThreeLanguages;
// uRdxRecipes, R_NO_OPERAND in uRdxSqlTemplate.
begin
  Check3(MsgNoOperandInChain, 'no operand in the chain',
    'kein Operand in der Kette', 0, 'aucun operande dans la concatenation');
end;

procedure TTestRdxTextMsgs.DeclsInClassesOfName_ThreeLanguages;
// uRdxResultFixes, uRdxRoutineFixes.
begin
  Check3(ProbeDecls,
    '2 declarations of Create in classes of this name - overload?',
    '2 Deklarationen von Create in Klassen dieses Namens - Overload?', 0,
    '2 declarations de Create dans des classes de ce nom - overload ?');
end;

procedure TTestRdxTextMsgs.NoLongerAtReportedPlace_ThreeLanguages;
// R_ASSERT_MOVED, R_TOBJECT_MOVED, R_ARGS_MOVED, R_FREE_MOVED und
// 'Assigned(X) ...' in uRdxSimpleFixes.
begin
  Check3(ProbeNotAtPlace, 'Assert( is no longer at the reported place',
    'Assert( steht nicht mehr an der gemeldeten Stelle', 0,
    'Assert( n''est plus a l''endroit signale');
end;

procedure TTestRdxTextMsgs.HeaderSearch_ThreeLanguages;
// Die Kopf-Suche (TRdxLineSearch) in uRdxResultFixes.RoutineOnLine und
// uRdxRoutineFixes.HeadOn: What 'kein Kopf ' + Ergaenzung, ManyFmt
// '%d Koepfe ' + Ergaenzung. Die Ergaenzung geht woertlich durch; das
// Muster kommt unformatiert - %d und %s stehen in allen drei Sprachen.
begin
  Check3(ProbeNoHeader, 'no header R%d', 'kein Kopf R%d', 0,
    'aucun en-tete R%d');
  Check3(MsgHeadersFmt, '%d headers %s', '%d Koepfe %s', 1, '%d en-tetes %s');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTextMsgs);

end.
