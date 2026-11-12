unit uRdxDfmDeadEventFix;

// reDelphix - Editorhilfe SCA028 DfmDeadEvent: eine Event-Bindung im DFM
// ('OnClick = btnGoClick'), deren benannte Methode in der Form-Klasse WEDER
// als Signatur noch als Implementation existiert (uDfmDeadEvent.pas) -
// zur Laufzeit ein Streaming-Crash. Der Fix loescht GENAU die eine
// gemeldete Zeile; anders als SCA037/184 keine Blockgrenzen-Logik noetig,
// da eine Event-Property immer eine einzelne Zeile ist (DFM kennt keine
// mehrzeiligen 'Key = Value'-Properties ausser Collections/Binaerdaten,
// die hier nicht vorkommen).
//
// Gesperrt, wenn die Zeile nicht mehr exakt 'EventName = HandlerName'
// traegt (Fund veraltet - Zeile verschoben, Bindung schon geaendert, o.ae.):
// das Loeschen einer falschen Zeile waere schlimmer als gar kein Fix.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  TRdxDfmDeadEventFix = class
  public
    // SCA028: s. Unit-Kopf. Gesperrt, wenn aus der Meldung keine
    // Event/Handler-Bindung gelesen werden kann, ALine ausser Bereich liegt,
    // oder die Zeile nicht mehr exakt 'EventName = HandlerName' traegt.
    class function DeleteDeadEvent(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRdxText;        // _(), nie uLocalization (E29)

const
  SPAN_028 = 'sca028';
  MSG_TAIL = ' (handler missing in ';

// Liest EventName/HandlerName aus 'Component.EventName = HandlerName
// (handler missing in FormClass)' (uDfmDeadEvent.TDfmDeadEventDetector.
// Analyze, F.MissingVar). Der Komponentenname vor dem ersten '.' wird nicht
// gebraucht - die Zeile im DFM traegt ihn nicht, nur Event und Handler.
function ParseBinding(const AMessage: string; out AEvent, AHandler: string): Boolean;
var
  TailPos, DotPos, EqPos : Integer;
  Head                   : string;
begin
  Result := False;
  AEvent := '';
  AHandler := '';
  TailPos := Pos(MSG_TAIL, AMessage);
  if TailPos <= 1 then Exit;
  Head := Copy(AMessage, 1, TailPos - 1);          // 'Component.Event = Handler'
  DotPos := Pos('.', Head);
  if DotPos = 0 then Exit;
  Head := Copy(Head, DotPos + 1, MaxInt);          // 'Event = Handler'
  EqPos := Pos(' = ', Head);
  if EqPos = 0 then Exit;
  AEvent := Trim(Copy(Head, 1, EqPos - 1));
  AHandler := Trim(Copy(Head, EqPos + 3, MaxInt));
  Result := (AEvent <> '') and (AHandler <> '');
end;

class function TRdxDfmDeadEventFix.DeleteDeadEvent(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  WantEvent, WantHandler, LineEvent, LineHandler, TL : string;
  EqPos                                               : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if not ParseBinding(AMessage, WantEvent, WantHandler) then
  begin
    AReason := _('could not read the event binding from the finding');
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := _('line %d is out of range (declaration moved?)', [ALine]);
    Exit;
  end;
  TL := Trim(AMap.Raw(ALine));
  EqPos := Pos('=', TL);
  if EqPos = 0 then
  begin
    AReason := _('line %d is no longer an event binding (moved or already '
      + 'changed?)', [ALine]);
    Exit;
  end;
  LineEvent := Trim(Copy(TL, 1, EqPos - 1));
  LineHandler := Trim(Copy(TL, EqPos + 1, MaxInt));
  if not SameText(LineEvent, WantEvent) or not SameText(LineHandler, WantHandler) then
  begin
    AReason := _('line %d no longer binds %s to %s (moved or already '
      + 'changed?)', [ALine, WantEvent, WantHandler]);
    Exit;
  end;

  AReason := WholeLinesEdit(AMap, ALine, ALine, SPAN_028, AEdit);
  Result := AReason = '';
end;

end.
