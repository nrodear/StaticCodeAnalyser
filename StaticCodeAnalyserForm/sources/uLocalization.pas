unit uLocalization;

// Lokalisierungs-Wrapper fuer das Static Code Analysis Tool for Delphi.
//
// Das Plugin instrumentiert UI-Strings mit der _()-Funktion. Diese Unit
// ist ein duenner Adapter, der entweder:
//
//   * als Passthrough laeuft (kein dxgettext installiert)        - Default
//   * an dxgettext (GnuGettext-Port) weiterleitet                - via {$DEFINE USE_GETTEXT}
//
// Damit kompiliert das Plugin auch ohne installiertes dxgettext, und
// die Aktivierung der Uebersetzung ist eine einzige Compiler-Direktive.
//
// dxgettext-Setup (einmalig):
//   1. dxgettext clonen: https://github.com/sjrd/dxgettext
//   2. dxgettext-Sources zu DCC_UnitSearchPath des IDE-Plugins hinzufuegen
//   3. {$DEFINE USE_GETTEXT} in der dpk oder via Project-Options aktivieren
//   4. SetLanguage('de') / 'en' / 'fr' beim Frame-Aufbau aufrufen
//
// Verwendung im Code:
//   Btn.Caption := _('Start analysis');
//   Status := Format(_('%d findings'), [N]);
//
// Nicht-instrumentierte Strings bleiben in der Source-Sprache (English).

interface

uses
  System.SysUtils;

// Uebersetzt einen String. Ohne aktives dxgettext: identitaet.
function _(const S: string): string; overload;

// Format-Variante: erst uebersetzen, dann formatieren.
function _(const FormatStr: string; const Args: array of const): string; overload;

// Setzt die aktive Sprache. Erlaubte Werte: 'de', 'en', 'fr', '' (Default).
// Ohne aktives dxgettext: No-Op.
procedure SetLanguage(const Lang: string);

// Liefert die aktuell gesetzte Sprache zurueck (oder '' wenn Default).
function CurrentLanguage: string;

implementation

{$IFDEF USE_GETTEXT}
uses
  gnugettext;
{$ENDIF}

var
  GCurrentLang: string = '';

function _(const S: string): string;
begin
  {$IFDEF USE_GETTEXT}
  Result := gnugettext.dgettext('default', S);
  {$ELSE}
  Result := S;
  {$ENDIF}
end;

function _(const FormatStr: string; const Args: array of const): string;
begin
  // Fully-qualified Aufruf vermeiden, weil System.SysUtils unter dem Alias
  // 'SysUtils' nicht aufloesbar ist - in modernen Delphi-Versionen muss
  // entweder System.SysUtils.Format oder einfach Format genutzt werden.
  Result := Format(_(FormatStr), Args);
end;

procedure SetLanguage(const Lang: string);
begin
  GCurrentLang := Lang;
  {$IFDEF USE_GETTEXT}
  gnugettext.UseLanguage(Lang);
  {$ENDIF}
end;

function CurrentLanguage: string;
begin
  Result := GCurrentLang;
end;

end.
