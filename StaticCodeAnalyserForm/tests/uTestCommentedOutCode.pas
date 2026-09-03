unit uTestCommentedOutCode;

// Tests fuer TCommentedOutCodeDetector (Heuristik auf Pascal-Marker
// in //- und {}-Kommentaren).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommentedOutCode = class
  public
    [Test] procedure ProseComment_NoFinding;
    [Test] procedure CodeLineComment_Reported;
    [Test] procedure CodeBlockComment_Reported;
    [Test] procedure SinglePascalToken_NoFinding;
    [Test] procedure ProseWithWeakKeywords_NoFinding;
    [Test] procedure CompilerDirective_NoFinding;
    [Test] procedure CommentedOutCode_KindAndSeverity;
    // ---- Adapter-Doku-Header (30%-Audit 2026-07-31) -----------------------
    [Test] procedure AdapterDocHeader_NotReported;
    [Test] procedure CommentedOutOverload_StillReported;
    [Test] procedure HeadOfCommentedBlock_StillReported;
    [Test] procedure ShortNameSubstring_StillReported;
    // ---- Laengenschwelle des Ankers (Klasse C, rw20 2026-08-28) -----------
    [Test] procedure AdapterDocHeaderShortName_NotReported;
    [Test] procedure ShortNameNoAnchor_StillReported;
    [Test] procedure SingleCharName_StillReported;
    // ---- '(*$...*)' als Direktive (AQL-Staffel 1, 2026-08-31) ----
    [Test] procedure ParenStarDirective_NotReported;
    [Test] procedure ParenStarBlockComment_StillReported;
    [Test] procedure CodeAfterParenStarDirective_StillReported;
    // ---- 'function'/'procedure' nur in Deklarationsstellung (rw56) ----
    [Test] procedure ProseWithFunctionNoun_NoFinding;
    [Test] procedure ProseWithFunctionAndParens_NoFinding;
    [Test] procedure CommentedOutSignature_StillReported;
    [Test] procedure CommentedOutAnonymousMethod_StillReported;
    [Test] procedure CommentedOutClassMethod_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCommentedOutCode.ProseComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  '// FreeAndNil is safer than Free for fields'#13#10 +
  '// see DocWiki for details'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeLineComment_Reported;
// Kommentar mit `:=` und trailing `;` -> 2 Marker -> Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // X := 42;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeBlockComment_Reported;
// `{...}` block comment mit `begin`/`end` plus `;` -> 3+ Marker.
const SRC =
  'unit t; implementation'#13#10 +
  '{ if Active then begin DoStuff; end; }'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.SinglePascalToken_NoFinding;
// Nur ein Marker (trailing `;`) - Schwelle = 2.
const SRC =
  'unit t; implementation'#13#10 +
  '// use FreeAndNil instead of Free;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ProseWithWeakKeywords_NoFinding;
// FP-Fix (Real-World 2026-06-28): englische Prosa mit prosa-haeufigen Keywords
// (if/then/for/while/end) traf frueher die 2-Marker-Schwelle und wurde als
// Code geflaggt. Ohne STARKEN Pascal-Marker (:=, trailing ;, begin/procedure/
// function) jetzt kein Treffer. Kommentar steht isoliert zwischen Code-Zeilen,
// damit nicht der Doc-Block-Guard (angrenzende //) das Ergebnis verfaelscht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  // if the value is nil then return for each item while at the end'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Prosa mit if/then/for/while/end ohne starken Marker ist kein Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CompilerDirective_NoFinding;
// `{$...}` ist Compiler-Direktive, kein Kommentar - kein Treffer.
const SRC =
  'unit t;'#13#10 +
  '{$IFDEF DEBUG}'#13#10 +
  '{$DEFINE WITH_LOGGING}'#13#10 +
  '{$ENDIF}'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutCode_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  '// X := 42; if X then begin DoStuff; end;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkCommentedOutCode then
      begin
        Assert.AreEqual<TFindingKind>(fkCommentedOutCode, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkCommentedOutCode finding');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.AdapterDocHeader_NotReported;
// JvInterpreter-Idiom: der Kommentar dokumentiert die ORIGINAL-Signatur
// ueber dem Adapter, der sie umschliesst. Korpus-Beleg jvcl
// JvInterpreter_RegAuto.pas:54. Dominante FP-Klasse des Audits (8/24),
// gemessen 4.515 der 20.354 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  '{ procedure Save; }'#13#10 +
  'procedure TRegAuto_Save(var Value: Variant);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Signatur-Doku ueber dem Adapter ist kein auskommentierter Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutOverload_StillReported;
// WAECHTER: GLEICHER Name heisst auskommentierte Ueberladung, nicht Doku.
// Im Korpus 42 solcher Faelle - die bleiben Funde.
const SRC =
  'unit t; implementation'#13#10 +
  '//procedure init(random: JSecureRandom); cdecl;'#13#10 +
  'procedure init(keysize: Integer); cdecl;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Auskommentierte Ueberladung bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.HeadOfCommentedBlock_StillReported;
// WAECHTER, der teuerste: die ERSTE Zeile eines mehrzeilig
// auskommentierten Blocks sieht aus wie ein Doku-Header. Sie darf nicht
// wegfallen - sonst verliert die Regel den Kopf jedes stillgelegten
// Routinen-Blocks. Schutz: der Kommentar muss auf DERSELBEN Zeile
// schliessen.
const SRC =
  'unit t; implementation'#13#10 +
  '{ procedure OldWorker;'#13#10 +
  '  begin'#13#10 +
  '    DoSomething;'#13#10 +
  '  end; }'#13#10 +
  'procedure TRegAuto_OldWorker(var Value: Variant);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Kopf eines mehrzeilig auskommentierten Blocks bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ShortNameSubstring_StillReported;
// WAECHTER gegen den Zufallstreffer: ohne Unterstrich-Anker und
// Mindestlaenge matchte 'im' in 'ImmedBW' (cnwizards). Der Name im
// Kommentar muss AM UNTERSTRICH im Folgenamen stecken.
const SRC =
  'unit t; implementation'#13#10 +
  '//function im(DS: Integer): Boolean;'#13#10 +
  'function ImmedBW(DS: Integer): Boolean;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Zufaellige Teilzeichenkette ist kein Adapter-Bezug');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.AdapterDocHeaderShortName_NotReported;
// Klasse C (rw20 2026-08-28): die alte Mindestlaenge 4 hat den Anker fuer
// kurze Namen nie erreicht und 155 echte Adapter-Doku-Header als
// auskommentierten Code gemeldet. Korpus-Beleg jvcl
// JvInterpreter_Classes.pas:68 - '{ function Add(...): Integer; }' ueber
// 'TList_Add'. OHNE die Absenkung auf 2 ist dieser Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  '{ procedure Add; }'#13#10 +
  'procedure TList_Add(var Value: Variant);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Signatur-Doku mit kurzem Namen ist kein auskommentierter Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ShortNameNoAnchor_StillReported;
// WAECHTER zur Absenkung: die Arbeit macht der Unterstrich-Anker, nicht
// die Laenge. 'add' passiert die Schwelle jetzt, aber 'AddRange' traegt
// den Namen nicht AM UNTERSTRICH - der stillgelegte Kopf bleibt ein Fund.
// Auch OHNE die Aenderung gruen (dort haelt ihn noch die alte Schwelle);
// rot wird er, sobald jemand den Anker aufweicht.
const SRC =
  'unit t; implementation'#13#10 +
  '//procedure Add(Item: Pointer);'#13#10 +
  'procedure AddRange(Item: Pointer);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Ohne Unterstrich-Anker bleibt der stillgelegte Kopf ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.SingleCharName_StillReported;
// WAECHTER fuer die Untergrenze: bei EINEM Zeichen ist '_' + Name nur ein
// Zwei-Zeichen-Suffix und kein Anker mehr - im Korpus enden 3.761
// Routinennamen auf '_' + ein Zeichen, allein 1.883 auf '_r'. Der
// stillgelegte Kopf bleibt deshalb ein Fund, obwohl 'TFoo_R' den Anker
// formal traegt. Auch OHNE die Aenderung gruen; rot, sobald die
// Untergrenze ganz faellt (Streichen der Zeile = 'Length(Nm) < 1' und
// damit wirkungslos, weil Nm nie leer ist).
const SRC =
  'unit t; implementation'#13#10 +
  '//procedure R(Item: Pointer);'#13#10 +
  'procedure TFoo_R(Item: Pointer);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Ein-Zeichen-Name traegt den Unterstrich-Anker nicht');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ParenStarDirective_NotReported;
// AQL-Staffel 1 (2026-08-31): '(*$...*)' ist Alternate-Syntax derselben
// Compiler-Direktive wie '{$...}'. Korpus-Beleg
// jcl/jcl/source/prototypes/JclHashMaps.pas:82-103 - das JPPEXPANDMACRO
// laeuft ueber 22 Zeilen, sein Rumpf ist Argument des JEDI-Praeprozessors,
// gemeldet wurde daraus Zeile 100.
// Der Kommentar MUSS mehrzeilig sein: ein einzeiliges '(*$..*)' loest im
// Korpus keinen einzigen Fund aus (gemessen 0 von 15.711), ein Test damit
// waere auch OHNE den Fix gruen und wuerde nichts sichern.
// Ohne den Fix ROT mit 2 Funden (SRC-Zeile 3 und 4).
const SRC =
  'unit t; implementation'#13#10 +
  '(*$JPPEXPANDMACRO MAKRO(TFoo,'#13#10 +
  '  function Hash(const AKey: Integer): Integer; virtual; abstract;'#13#10 +
  '  function FreeKey(var Key: Integer): Integer;'#13#10 +
  '  property OwnsKeys: Boolean read FOwnsKeys;)*)'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Rumpf einer (*$..*)-Direktive ist kein auskommentierter Code');
  finally F.Free; end;
end;
procedure TTestCommentedOutCode.ParenStarBlockComment_StillReported;
// WAECHTER: nur '(*$' ist Direktive. Ein mehrzeiliger '(* ... *)'-Kommentar
// mit stillgelegtem Code bleibt ein Fund - sonst nimmt der Fix der Regel die
// ganze Klammer-Stern-Form ab. Gemessen: 3 Funde, vor UND nach dem Fix
// identisch (SRC-Zeilen 2, 4, 5).
const SRC =
  'unit t; implementation'#13#10 +
  '(* procedure OldWorker;'#13#10 +
  '   begin'#13#10 +
  '     X := 42;'#13#10 +
  '   end; *)'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Mehrzeiliger (*..*)-Kommentar bleibt bewertbar');
  finally F.Free; end;
end;
procedure TTestCommentedOutCode.CodeAfterParenStarDirective_StillReported;
// WAECHTER: nach dem Skip ueber '(*$..*)' muss der REST der Zeile weiter
// geprueft werden. Setzt jemand hinter dem Skip falsch auf (i := pClose + 2),
// faellt der echte Kommentar dahinter lautlos weg, ohne dass eine Fundzahl
// im Korpus das zeigt.
// Auch OHNE den Fix gruen - wie ShortNameNoAnchor_StillReported ist er kein
// Beweis fuer die Aenderung, sondern eine Sicherung gegen die naechste.
// Gemessen: 1 Fund in Spalte 11, vor und nach dem Fix.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  (*$R+*) (* X := 42; if X then DoStuff; *)'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Kommentar hinter der Direktive darf nicht mit weggeskippt werden');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ProseWithFunctionNoun_NoFinding;
// rw56 (2026-09-03): 'function'/'procedure' galt als STARKER Marker,
// sobald das Wort irgendwo im Kommentar stand. Damit flaggte der
// Detektor jeden Kommentar, der ueber eine Routine SPRICHT. Am
// Referenzkorpus 821 von 15.688 Funden - 5,2 %, und 18 der 30
// AQL-Fehlalarme vom 31.08. waren genau dieses Muster.
// Wortlaut aus dem Korpus: Dev-Cpp uEditorBrowser.pas:254.
// Ohne den Fix ROT mit 1 Fund ('function' stark + 'if' schwach = 2).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  // This function should notify the user if a file is replaced'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Prosa ueber eine Funktion ist kein auskommentierter Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ProseWithFunctionAndParens_NoFinding;
// Die Stellungspruefung allein reicht NICHT: eine anonyme Methode hat
// keinen Namen und darf deshalb links keinen Deklarationsanfang
// verlangen - sonst faellt 'TProc = procedure (S: TObject)'. Genau
// diese Lockerung laesst aber englische Prosa mit Klammer durch, wenn
// die Parameterliste nicht geprueft wird: "function(s)", "the previous
// function (GetResponse) did its", "reconstruction function (q / 2)".
// Am Korpus waren das 4 der 9 sonst faelschlich gehaltenen Faelle.
// Wortlaut aus dem Korpus: Indy IdReplyIMAP4.pas:368.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  { we can assume, if the previous function (GetResponse) did its }'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Klammer hinter dem Wort macht aus Prosa keine Parameterliste');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutSignature_StillReported;
// WAECHTER gegen einen zu scharfen Fix. Diese Fixture ist vor UND nach
// dem Fix ein Fund - sie bricht, wenn die Stellungspruefung den
// benannten Kopf nicht mehr erkennt.
// Der Kopf traegt bewusst KEIN abschliessendes ';': sonst waere das
// Semikolon der starke Marker und die Fixture pruefte den Fix nicht.
// Wortlaut aus dem Korpus: D3DSettings.pas:72.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  { procedure SetDisplayMode(value: TD3DMode) if IsWindowed }'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommentedOutCode),
    'auskommentierter Routinenkopf bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutAnonymousMethod_StillReported;
// WAECHTER fuer den anonymen Zweig: hier gibt es keinen Namen und links
// steht ein '=', kein Deklarationsanfang. Traegt nur die
// Parameterlisten-Erkennung, bleibt dieser Fund - sonst faellt er
// zusammen mit der Prosa weg.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  { TNotify = procedure (Sender: TObject) of object if needed }'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommentedOutCode),
    'anonyme Methode mit Parameterliste bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutClassMethod_StillReported;
// WAECHTER fuer den dritten Anker der Stellungspruefung. Neben
// "Inhaltsanfang" und "hinter ';'" gibt es "hinter dem Wort 'class'" -
// bei 'class function Foo' steht vor dem Schluesselwort weder ein
// Satzanfang noch ein Semikolon. Ohne diesen Anker faellt jede
// auskommentierte Klassenmethode weg.
// Wie bei CommentedOutSignature_StillReported bewusst ohne
// abschliessendes ';', sonst traegt das Semikolon den starken Marker
// und die Fixture prueft den Anker nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  { class function Berechne: Integer if noetig }'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCommentedOutCode),
    'auskommentierte Klassenmethode bleibt ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommentedOutCode);

end.
