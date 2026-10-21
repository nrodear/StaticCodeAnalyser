unit uRdxEmptyOnHandlerFix;

// reDelphix - Editorhilfe SCA159 EmptyOnHandler, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'on E: T do ;'          -> 'on E: T do raise;'
//   'on E: T do begin end;' -> 'on E: T do begin raise; end;'
//   (begin und end auf eigenen Zeilen: 'raise;' kommt als eigene Zeile eine
//   Stufe tiefer dazwischen).
// Der leere Handler schluckt die Ausnahme still; mit 'raise;' laeuft sie
// weiter nach aussen. Das AENDERT das Verhalten (Changes: True, der Hinweis
// nennt die Folge). Der Detektor bleibt unveraendert (Entscheid E9).
//
// WAS DER DETEKTOR MELDET (uEmptyOnHandler): auf der Text-Sicht OHNE
// Kommentare und Strings 'on [E:] T do' mit ';' oder 'begin end [;]'
// dahinter, Zeilen und Leerraum beliebig; die Meldung 'Typed exception
// handler on T has empty body - silent failure' traegt Zeile des 'on', aber
// keine Spalte. EAbort meldet er nie. Weil er Kommentare ausblendet, meldet
// er auch 'on E: T do ; // darf ignoriert werden' - die Hilfe nicht.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * auf der gemeldeten Zeile steht kein Handler 'on [E:] T do' mit leerem
//     Rumpf (Zeile verschoben, Rumpf inzwischen gefuellt) - oder der Typ
//     heisst anders als in der Meldung;
//   * mehr als ein 'on'-Handler auf der Zeile (der Fund koennte jeden
//     meinen);
//   * das 'on' steht nicht am Anfang eines Handlers (davor weder except
//     noch ';');
//   * Kommentar oder Direktive im Handler - von 'on' bis hinter das ';'
//     bzw. end, davor auf der Zeile oder dahinter auf der Zeile: ein
//     Kommentar ist Absicht ('// Abbruch ist hier gewollt');
//   * der Kopf 'on E: T do' steht nicht auf einer Zeile, das ';' nicht auf
//     der Zeile des 'do';
//   * der Typ ist EAbort (stilles Abbruchsignal der VCL).
// Der Rumpf 'begin end' darf ueber Zeilen gehen, wenn dazwischen nur
// Leerraum steht.

interface

uses
  System.Classes,    // TStrings
  uEngineApi,        // TSourcePlaces
  uMethodd12,        // TLeakFinding
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap,       // TRdxCodeMap
  uRdxRecipeRunner;  // TRdxFixOutcome

const
  // Die Gruende als englische msgids (die Tests pruefen sie mit _()).
  R_EOH_MOVED     = 'no empty "on ... do" handler at the reported place';
  R_EOH_MANY      = 'several "on ... do" handlers on this line - the '
    + 'finding could mean any of them';
  R_EOH_CONTEXT   = 'the "on" does not start a handler of an except block';
  R_EOH_COMMENT   = 'comment or directive in or beside the handler - '
    + 'intent, no help';
  R_EOH_LAYOUT    = 'the handler head is not on one line, or the ";" is not '
    + 'on the line of "do"';
  R_EOH_ABORT     = 'EAbort is swallowed on purpose - "raise;" would show '
    + 'the abort';

type
  // Der Planer von SCA159 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxEmptyOnHandlerFix = class
  public
    // ALine ist die Zeile des 'on' (die Meldung traegt keine Spalte); aus
    // AMessage wird nur der Typname gelesen, falls vorhanden. Liefert die
    // eine Ersetzung oder den Grund.
    class function Reraise(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

// Der Adapter der Tabelle (uRdxFixTable.TRdxFixPlanner): Zeile und Meldung
// aus dem Fund, der Planer ueber MapFix. APlaces und AUsesNames braucht die
// Hilfe nicht.
function PlanEmptyOnHandler(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText,          // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxFixRunner;     // MapFix

const
  SPAN_159 = 'sca159';
  // Davor beginnt ein Handler.
  HANDLER_PREV: array[0..1] of string = ('except', ';');
  KEY_ON   = 'on';
  KEY_HAND = 'handler on ';
  KEY_HAS  = ' has empty body';
  RAISE_INLINE = ' raise;';
  RAISE_BLOCK  = ' raise; ';
  RAISE_STMT   = 'raise;';

type
  // Ein Handler-Kopf 'on [E:] T do' auf einer Zeile.
  TOnHead = record
    OnTok   : TRdxToken;
    TypeTok : TRdxToken;
    DoTok   : TRdxToken;
  end;

  // Der leere Rumpf hinter 'do': Form A (';') oder Form B ('begin end').
  TEmptyBody = record
    IsBlock : Boolean;
    First   : TRdxToken;   // ';' bzw. begin
    Last    : TRdxToken;   // ';' bzw. end
  end;

// Der Typname aus der Meldung ('Typed exception handler on EFoo has empty
// body - ...'); '' ohne.
function TypeFromMessage(const AMessage: string): string;
var
  p, q : Integer;
begin
  Result := '';
  p := Pos(KEY_HAND, AMessage);
  if p = 0 then Exit;
  Inc(p, Length(KEY_HAND));
  q := Pos(KEY_HAS, AMessage);
  if q > p then
    Result := Copy(AMessage, p, q - p);
end;

// Beginnt an T ein Handler-Kopf 'on [E:] T do' - alles auf der Zeile von T?
// Die Form, die der Detektor liest (nur ein einfacher Typname).
function ReadHead(AMap: TRdxCodeMap; const T: TRdxToken;
  out AHead: TOnHead): Boolean;
var
  N1, N2, N3 : TRdxToken;
begin
  Result := False;
  AHead := Default(TOnHead);
  if (T.Low <> KEY_ON) or not IsKeywordAfter(T, Before(AMap, T)) then Exit;
  N1 := After(AMap, T);
  if not N1.IsWord or (N1.Line <> T.Line) then Exit;
  N2 := After(AMap, N1);
  if N2.Line <> T.Line then Exit;
  if N2.Low = ':' then
  begin
    N3 := After(AMap, N2);
    if not N3.IsWord or (N3.Line <> T.Line) then Exit;
    AHead.TypeTok := N3;
    AHead.DoTok := After(AMap, N3);
  end
  else
  begin
    AHead.TypeTok := N1;
    AHead.DoTok := N2;
  end;
  AHead.OnTok := T;
  Result := (AHead.DoTok.Low = 'do') and (AHead.DoTok.Line = T.Line);
end;

// Genau ein Handler-Kopf auf ALine. '' oder der Grund.
function FindHead(AMap: TRdxCodeMap; ALine: Integer;
  out AHead: TOnHead): string;
var
  T    : TRdxToken;
  H    : TOnHead;
  n    : Integer;
begin
  AHead := Default(TOnHead);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if ReadHead(AMap, T, H) then
    begin
      Inc(n);
      AHead := H;
    end;
    T := After(AMap, T);
  end;
  Result := '';
  if n = 0 then
    Result := MsgMovedSuffix(_(R_EOH_MOVED))
  else if n > 1 then
    Result := _(R_EOH_MANY);
end;

// Der leere Rumpf hinter dem 'do'. '' oder der Grund.
function ReadBody(AMap: TRdxCodeMap; const AHead: TOnHead;
  out ABody: TEmptyBody): string;
var
  Nx, En : TRdxToken;
begin
  Result := '';
  ABody := Default(TEmptyBody);
  Nx := After(AMap, AHead.DoTok);
  if Nx.Low = ';' then
  begin
    if Nx.Line <> AHead.DoTok.Line then
      Exit(_(R_EOH_LAYOUT));
    ABody.First := Nx;
    ABody.Last := Nx;
    Exit;
  end;
  En := After(AMap, Nx);
  if (Nx.Low = 'begin') and (En.Low = 'end')
     and IsKeywordAfter(Nx, AHead.DoTok) and IsKeywordAfter(En, Nx) then
  begin
    ABody.IsBlock := True;
    ABody.First := Nx;
    ABody.Last := En;
  end
  else
    Result := MsgMovedSuffix(_(R_EOH_MOVED));
end;

// Steht 'on' am Anfang eines Handlers, und ist der Typ der gemeldete?
function ContextReason(AMap: TRdxCodeMap; const AHead: TOnHead;
  const AMessage: string): string;
var
  Named : string;
begin
  Result := '';
  Named := TypeFromMessage(AMessage);
  if (Named <> '') and not SameText(Named, TokText(AMap, AHead.TypeTok)) then
    Exit(MsgMovedSuffix(_(R_EOH_MOVED)));
  if SameText(AHead.TypeTok.Low, 'eabort') then
    Exit(_(R_EOH_ABORT));
  if not InList(Before(AMap, AHead.OnTok).Low, HANDLER_PREV) then
    Result := _(R_EOH_CONTEXT);
end;

// Kommentar oder Direktive von 'on' bis zum Ende des Handlers, vor dem 'on'
// auf seiner Zeile oder hinter dem Ende auf der Zeile?
function CommentReason(AMap: TRdxCodeMap; const AHead: TOnHead;
  const ABody: TEmptyBody): string;
var
  Span : TRefactorSpan;
  Last : TRdxToken;
begin
  Result := '';
  Last := ABody.Last;
  Span := TRefactorSpan.Make(SPAN_159, AHead.OnTok.Line, AHead.OnTok.Col,
    Last.Line, Last.EndCol);
  if CommentInRange(AMap, Span)
     or DirectiveInLines(AMap, AHead.OnTok.Line, Last.Line)
     or AMap.HasComment(AHead.OnTok.Line, 1, AHead.OnTok.Col - 1)
     or AMap.HasComment(Last.Line, Last.EndCol, Length(AMap.Raw(Last.Line))) then
    Result := _(R_EOH_COMMENT);
end;

// Die Ersetzung: Form A hinter dem 'do', Form B in 'begin end'.
function BuildEdit(AMap: TRdxCodeMap; const AHead: TOnHead;
  const ABody: TEmptyBody; out AEdit: TRdxEdit): string;
var
  Bg, En           : TRdxToken;
  EndIndent, Inner : string;
  Last1            : string;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  if not ABody.IsBlock then
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_159, AHead.DoTok.Line,
      AHead.DoTok.EndCol, ABody.Last.Line, ABody.Last.EndCol);
    AEdit.NewText := RAISE_INLINE;
  end
  else
  begin
    Bg := ABody.First;
    En := ABody.Last;
    if Bg.Line = En.Line then
    begin
      AEdit.Span := TRefactorSpan.Make(SPAN_159, Bg.Line, Bg.EndCol, En.Line,
        En.Col);
      AEdit.NewText := RAISE_BLOCK;
    end
    else
    begin
      // Der Start liegt auf dem letzten Zeichen von begin: eine Spanne darf
      // nicht hinter dem Zeilenende beginnen.
      EndIndent := Copy(AMap.Raw(En.Line), 1, En.Col - 1);
      if not FirstOnLine(AMap, En) then
        Exit(_(R_EOH_LAYOUT));
      Inner := EndIndent + IndentStep(EndIndent, '');
      Last1 := Copy(AMap.Raw(Bg.Line), Bg.EndCol - 1, 1);
      AEdit.Span := TRefactorSpan.Make(SPAN_159, Bg.Line, Bg.EndCol - 1,
        En.Line, En.Col);
      AEdit.NewText := Last1 + #10 + Inner + RAISE_STMT + #10 + EndIndent;
    end;
  end;
  AEdit.Expected := RangeText(AMap, AEdit.Span);
end;

{ TRdxEmptyOnHandlerFix }

class function TRdxEmptyOnHandlerFix.Reraise(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Head : TOnHead;
  Body : TEmptyBody;
begin
  AEdit := Default(TRdxEdit);
  AReason := FindHead(AMap, ALine, Head);
  if AReason = '' then
    AReason := ReadBody(AMap, Head, Body);
  if AReason = '' then
    AReason := ContextReason(AMap, Head, AMessage);
  if AReason = '' then
    AReason := CommentReason(AMap, Head, Body);
  if AReason = '' then
    AReason := BuildEdit(AMap, Head, Body, AEdit);
  Result := AReason = '';
  if not Result then
    AEdit := Default(TRdxEdit);
end;

function PlanEmptyOnHandler(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxEmptyOnHandlerFix.Reraise);
end;

end.
