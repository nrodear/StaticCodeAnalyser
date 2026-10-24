unit uTestIpAddressScanKit;

// Gemeinsame Helfer der vier uIpAddressScan-Fixtures (Grammar, Classes,
// Pascal, Ini): die Treffer einer Routine als EIN String, damit jeder
// Fall mit einem AreEqual geprueft wird und die Meldung den Fall nennt.
// Keine Fixture - wird nicht registriert. Laeuft wie die Unit selbst im
// FPC-Pruefstand (kein AST, keine Engine).

interface

uses
  System.SysUtils, System.Classes,
  uIpAddressScan;

type
  // Ein Fall: Eingabe und erwartete Treffer-Kette.
  TTextCase = record
    Input    : string;
    Expected : string;
  end;

const
  // Klassennamen fuer Meldungen (Reihenfolge = TIpClass).
  CLS_NAMES : array[TIpClass] of string = ('private', 'cgnat', 'public',
    'loopback', 'unspecified', 'broadcast', 'netmask', 'linklocal',
    'documentation', 'protocol', 'benchmark', 'multicast', 'reserved');

// FindAll: die Adress-Texte mit '|' verkettet ('' = kein Treffer).
function HitsText(const S: string): string;

// ScanPascalCode einer Zeile: 'Text=Grund|...' ('' als Grund = melden).
function PascalGot(const ACode: string): string;

// ScanIniLines: 'Sektion/Schluessel:Text=Grund|...'.
function IniGot(const ALines: array of string): string;

// ClassLabel des ersten Treffers in S ('<kein Treffer>' sonst).
function LabelOf(const S: string): string;

// Klassenname einer IPv4 bzw. IPv6 (ganzer String); '<parse>' wenn die
// Form nicht parst.
function ClassNameV4(const S: string): string;
function ClassNameV6(const S: string): string;

implementation

// Ein Glied der '|'-Kette (TStringBuilder statt Result + ..., SCA110).
procedure AppendPart(ASB: TStringBuilder; const APart: string);
begin
  if ASB.Length > 0 then
    ASB.Append('|');
  ASB.Append(APart);
end;

function HitsText(const S: string): string;
var
  SB : TStringBuilder;
  H  : TIpHit;
begin
  SB := TStringBuilder.Create;
  try
    for H in TIpAddressScan.FindAll(S) do
      AppendPart(SB, H.Text);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function PascalGot(const ACode: string): string;
var
  SB : TStringBuilder;
  CH : TCodeIpHit;
begin
  SB := TStringBuilder.Create;
  try
    for CH in TIpAddressScan.ScanPascalCode(ACode) do
      AppendPart(SB, CH.Hit.Text + '=' + CH.Reason);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function IniGot(const ALines: array of string): string;
var
  L  : TStringList;
  SB : TStringBuilder;
  i  : Integer;
  IH : TIniIpHit;
begin
  L := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
      L.Add(ALines[i]);
    for IH in TIpAddressScan.ScanIniLines(L) do
      AppendPart(SB, IH.Section + '/' + IH.Key + ':' + IH.Hit.Text + '=' + IH.Reason);
    Result := SB.ToString;
  finally
    SB.Free;
    L.Free;
  end;
end;

function LabelOf(const S: string): string;
var
  H : TArray<TIpHit>;
begin
  H := TIpAddressScan.FindAll(S);
  if Length(H) = 0 then
    Exit('<kein Treffer>');
  Result := TIpAddressScan.ClassLabel(H[0]);
end;

function ClassNameV4(const S: string): string;
var
  V : Cardinal;
begin
  if TIpAddressScan.TryParseIPv4(S, V) then
    Result := CLS_NAMES[TIpAddressScan.ClassifyV4(V)]
  else
    Result := '<parse>';
end;

function ClassNameV6(const S: string): string;
var
  W : TIpv6Words;
begin
  if TIpAddressScan.TryParseIPv6(S, W) then
    Result := CLS_NAMES[TIpAddressScan.ClassifyV6(W)]
  else
    Result := '<parse>';
end;

end.
