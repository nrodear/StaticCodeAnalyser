unit uJsonFormat;

// EINGERUECKTES JSON, DAS DIE SPEZIFIKATION EINHAELT.
//
// WARUM ES DIESE UNIT GIBT
//
// System.JSON kann eingerueckt schreiben (TJSONValue.Format) ODER
// spezifikationstreu escapen (ToJSON mit EncodeBelow32) - aber nicht
// beides. Der Grund steht in der RTL-Quelle
// (C:\Program Files (x86)\Embarcadero\Studio\23.0\source\rtl\common\
// System.JSON.pas):
//
//   * TJSONAncestor.Format(Builder, ParentIdent, Ident) :1609 ruft
//     ToChars(Builder, []) - mit LEEREN Optionen, hart verdrahtet.
//   * TJSONString.ToChars :2605 escaped daraufhin nur " \ / #8 #9 #10
//     #12 #13. Die \uXXXX-Behandlung haengt an :2629
//     "if (EncodeBelow32 in Options) and (UnicodeValue < 32)" - ohne die
//     Option gehen #0..#7, #11 und #14..#31 ROH heraus.
//   * RFC 8259 par.7 verlangt fuer U+0000..U+001F aber genau dieses
//     Escaping. Format(2) kann also UNGUELTIGES JSON erzeugen.
//
// Das ist kein theoretischer Fall. Ein Detektor zitiert den Quelltext,
// den er gelesen hat; der Lexer loest Char-Literale in echte Zeichen auf
// (uLexer.pas:531). Aus 'edToken.PasswordChar := #0;' wird eine Meldung
// mit einem echten #0 darin - und aus einer DFM-Zeile mit
// "sldCharsetSpec.Text = #0#4..." entsprechend.
//
// DER DEFEKT WURDE IM PROJEKT DREIMAL GEFUNDEN, AN DREI AUSGAENGEN:
//   * Sonar-Export, fb18279 (2026-08-05): schreibt seither
//     ToJSON([EncodeBelow32]) statt Format(2)
//     (uExportSonarGeneric.pas:399-401).
//   * SARIF-Emitter (2026-08-06): weicht in TSarifJsonEmitter.
//     AppendEscaped bewusst vom RTL-Vorbild ab und schreibt \u00XX
//     (uExportSARIF.pas:262-265).
//   * Baseline-Writer (2026-08-28): TBaseline.Write stand seit dem
//     ersten Commit der Unit (50858f7, 2026-05-18) auf Format(2). Auf
//     dem Referenzkorpus rw21 trugen 3 von 783.104 Eintraegen rohe
//     Bytes 0x00/0x04 - und machten die 371-MB-Datei fuer JEDEN
//     strikten Parser (python json, jq, JSON.parse) komplett
//     unlesbar. Fehlerrate 0,00038 %, Ausfallrate 100 %.
//
// Zweimal wurde nur der eigene Ausgang repariert und der Schwesterpfad
// stehen gelassen. Deshalb steht der dritte Fix hier und nicht dort:
// eine Stelle, die jeder Schreiber eingerueckten JSONs benutzen kann.
//
// WAS DIESE UNIT AUSDRUECKLICH NICHT TUT
//
// Sie bringt KEINE eigene Escape-Tabelle mit. Im Projekt gibt es davon
// schon zwei (TExporter.JsonEscape in uExport.pas:162 fuer den
// HTML-Meta-Block, TSarifJsonEmitter.AppendEscaped fuer den
// SARIF-Stream) plus die der RTL - eine dritte waere genau der Fehler,
// der zu diesem Befund gefuehrt hat. Hier entsteht nur das LAYOUT;
// jeder Blattwert und jeder Paar-NAME geht durch dieselbe
// RTL-Serialisierung, auf die sich der Sonar-Export seit fb18279
// verlaesst - ToChars mit EncodeBelow32.
//
// NUR EncodeBelow32, NICHT EncodeAbove127: Steuerzeichen sind nicht
// dasselbe wie Nicht-ASCII. Umlaute, Akzente und CJK-Zeichen sind in
// einem UTF-8-JSON roh voellig gueltig; sie zu \uXXXX aufzublasen
// machte die Datei groesser und die Meldungen unlesbar, ohne ein
// einziges Problem zu loesen.
//
// ZUSAGE AN DEN BESTAND: fuer jeden Baum OHNE Zeichen unter 0x20 ist
// die Ausgabe BYTE-IDENTISCH zu TJSONValue.Format(AIndent) - gleiche
// Einrueckung, gleiches ': ' nach dem Namen, gleiches CRLF, gleiches
// '\/' fuer den Schraegstrich. Eine bestehende Baseline sieht nach dem
// Fix also exakt aus wie vorher, nur die kaputten Stellen aendern sich.
// Der Test Layout_MatchesRtlFormatWhenNoControlChars vergleicht genau
// das gegen die RTL.

interface

uses
  System.JSON;

// Wie TJSONValue.Format(AIndent), aber RFC-8259-treu: Zeichen unter
// 0x20 ohne Kurz-Escape gehen als \u00XX heraus statt roh.
// AValue = nil liefert '' (die RTL laeuft dort in eine AV).
function JsonFormatEscaped(AValue: TJSONValue;
  AIndent: Integer = 2): string;

implementation

uses
  System.SysUtils,              // TStringBuilder, StringOfChar
  // H2443: Pairs[] und Items[] sind inline und greifen intern auf
  // TList<T> zu - ohne diese Unit expandiert der Compiler sie nicht
  // und meldet es je Aufrufstelle. Nur implementation-uses: die
  // interface-Sektion braucht den Typ nicht (E2003-Falle).
  System.Generics.Collections;

const
  // DER Unterschied zur RTL-Vorlage - ein Options-Wert.
  JSON_ESCAPE_OPTIONS : TJSONAncestor.TJSONOutputOptions =
    [TJSONAncestor.TJSONOutputOption.EncodeBelow32];
  // Startkapazitaet des Puffers wie in TJSONAncestor.Format :1595.
  INITIAL_BUFFER_CHARS = 256;

procedure AppendFormatted(ASb: TStringBuilder; AValue: TJSONValue;
  const AParentIndent, AIndent: string);
// Spiegelt TJSONObject.Format :3213 und TJSONArray.Format :3608 Zeile
// fuer Zeile - inklusive der Reihenfolge "Einrueckung, Inhalt, Komma
// wenn nicht letztes, Zeilenumbruch" und der schliessenden Klammer auf
// Parent-Einrueckung. Blaetter gehen an die RTL, nur mit Optionen.
var
  i           : Integer;
  ChildIndent : string;
  Obj         : TJSONObject;
  Arr         : TJSONArray;
begin
  if not Assigned(AValue) then
  begin
    // Kommt in einem selbst gebauten Baum nicht vor; die RTL laeuft an
    // dieser Stelle in eine AV. 'null' ist die einzige Antwort, die das
    // Dokument gueltig laesst.
    ASb.Append('null');
    Exit;
  end;

  if AValue is TJSONObject then
  begin
    Obj         := TJSONObject(AValue);
    ChildIndent := AParentIndent + AIndent;
    ASb.Append('{').AppendLine;
    for i := 0 to Obj.Count - 1 do
    begin
      ASb.Append(ChildIndent);
      // Der Paar-NAME wird genauso escaped wie ein Wert. Die RTL macht
      // das an :3223 ueber JsonString.Format, also ebenfalls mit leeren
      // Optionen - ein Steuerzeichen im Namen (z.B. ein Profilname in
      // profiles.json) waere dort derselbe Defekt.
      Obj.Pairs[i].JsonString.ToChars(ASb, JSON_ESCAPE_OPTIONS);
      ASb.Append(': ');
      AppendFormatted(ASb, Obj.Pairs[i].JsonValue, ChildIndent, AIndent);
      if i < Obj.Count - 1 then
      begin
        ASb.Append(',');
      end;
      ASb.AppendLine;
    end;
    ASb.Append(AParentIndent).Append('}');
  end
  else if AValue is TJSONArray then
  begin
    Arr         := TJSONArray(AValue);
    ChildIndent := AParentIndent + AIndent;
    ASb.Append('[').AppendLine;
    for i := 0 to Arr.Count - 1 do
    begin
      ASb.Append(ChildIndent);
      AppendFormatted(ASb, Arr.Items[i], ChildIndent, AIndent);
      if i < Arr.Count - 1 then
      begin
        ASb.Append(',');
      end;
      ASb.AppendLine;
    end;
    ASb.Append(AParentIndent).Append(']');
  end
  else
  begin
    // Blatt: String, Zahl, Bool, Null - alle koennen ToChars, und genau
    // hier wirkt die Option.
    AValue.ToChars(ASb, JSON_ESCAPE_OPTIONS);
  end;
end;

function JsonFormatEscaped(AValue: TJSONValue; AIndent: Integer): string;
var
  Sb   : TStringBuilder;
  Wide : Integer;
begin
  Result := '';
  if not Assigned(AValue) then
  begin
    Exit;
  end;
  Wide := AIndent;
  if Wide < 0 then
  begin
    Wide := 0;
  end;
  Sb := TStringBuilder.Create(INITIAL_BUFFER_CHARS);
  try
    AppendFormatted(Sb, AValue, '', StringOfChar(' ', Wide));
    Result := Sb.ToString(True);
  finally
    Sb.Free;
  end;
end;

end.
