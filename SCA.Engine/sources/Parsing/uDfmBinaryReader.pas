unit uDfmBinaryReader;

// Konvertiert binaer-gespeicherte DFM-Dateien (Header 'TPF0') in das
// Text-Format, das TDfmLexer/TDfmParser erwarten. Im Standard-Fall
// (kein binaeres DFM) ist der ToText-Aufruf transparent: der Input
// kommt unveraendert als String zurueck.
//
// Hintergrund: bis v0.10.0 hat TDfmAnalysisRunner einen TFile.ReadAllText
// auf das DFM gemacht. Binaer-DFMs (TPF0-Praefix) liefern dabei UTF-8-
// Decode-Fehler und werden durch das aeussere try/except STUMM
// uebersprungen - keine DFM-Befunde, keine Diagnose. Repos, in denen
// Forms historisch binaer gespeichert sind (CodeGear-Default <= D2007,
// oder per Project-Options-Wechsel umgestellt), bekamen dadurch _gar
// keine_ DFM-Analyse.
//
// Implementations-Stand:
// Heute delegieren wir auf Classes.ObjectBinaryToText aus der RTL -
// das ist die Standard-Embarcadero-Implementierung, in jeder Delphi-
// Version >= 7 vorhanden. Vorteil: kein eigener TWriter-Format-Parser
// noetig, alle Value-Types (vaInt8/16/32/64, vaWString, vaUTF8String,
// vaSingle, vaExtended, vaDate, vaCurrency, vaBinary, vaSet, vaList,
// vaCollection, vaNil, vaTrue/False, vaIdent, vaString, vaLString)
// werden korrekt serialisiert.
//
// Vollstaendige eigene TWriter-Implementierung steht als Phase-4-Item
// in TODO.md - relevant nur wenn das Plugin auf einer RTL-Variante
// ohne ObjectBinaryToText laufen soll (FreePascal/Lazarus,
// embedded-RTL). Schnittstelle dieser Unit (IsBinary, ToText) ist so
// gehalten, dass der Eigen-Reader ohne Caller-Aenderung hineingetauscht
// werden kann.

interface

uses
  System.SysUtils, System.Classes;

type
  TDfmBinaryReader = class
  public
    // Prueft ob die Bytes mit dem TPF0-Praefix beginnen (binaeres DFM).
    // Zwei Varianten werden als "binaer" erkannt:
    //   * 'TPF0' = $54 $50 $46 $30 (4 Bytes) - alle Delphi-Versionen ab 4
    //   * $FF $0A $00 - Resource-Wrapper-Header (in der Praxis bei
    //     IDE-Plugins/GExperts noch im Einsatz; enthaelt einen eingebetteten
    //     TPF0-Block).
    class function IsBinary(const ABytes: TBytes): Boolean; overload; static;
    class function IsBinary(AStream: TStream): Boolean; overload; static;

    // Liefert den Inhalt einer DFM-Datei als Text-DFM-Repraesentation.
    //   * Wenn ABytes mit 'TPF0' beginnt: konvertiert via
    //     Classes.ObjectBinaryToText. Bei Konvertierungs-Fehler wird
    //     EDfmBinaryReaderError geworfen.
    //   * Sonst: bytes werden als UTF-8 dekodiert (mit Latin-1 als
    //     Fallback bei Decoding-Fehlern) und unveraendert zurueckgegeben.
    //
    // Convenience-Overload ReadFile: liest die Datei und delegiert.
    // Wirft EDfmBinaryReaderError wenn die Datei nicht lesbar ist oder
    // die Binaer-Konvertierung scheitert.
    class function ToText(const ABytes: TBytes): string; overload; static;
    class function ToText(AStream: TStream): string; overload; static;
    class function ReadFile(const APath: string): string; static;
  end;

  EDfmBinaryReaderError = class(Exception);

implementation

// noinspection-file ExceptOnException, GodClass
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.IOUtils;

const
  // 'TPF0' - Standard-DFM-Binaer-Praefix ab Delphi 4
  TPF0_SIGNATURE: array[0..3] of Byte = ($54, $50, $46, $30);
  // Resource-Wrapper-Header (z.B. GExperts, alte Delphi-IDE-Plugins).
  // Format: $FF $0A $00 [ResName] [padding] TPF0 [DFM-Daten]
  RES_WRAPPER_SIG: array[0..2] of Byte = ($FF, $0A, $00);

// Sucht TPF0-Signatur ab StartOffset. -1 wenn nicht gefunden.
function FindTPF0(const ABytes: TBytes; StartOffset: Integer = 0): Integer;
var
  i, Last: Integer;
begin
  Result := -1;
  Last := Length(ABytes) - Length(TPF0_SIGNATURE);
  if StartOffset < 0 then StartOffset := 0;
  for i := StartOffset to Last do
    if (ABytes[i  ] = TPF0_SIGNATURE[0]) and
       (ABytes[i+1] = TPF0_SIGNATURE[1]) and
       (ABytes[i+2] = TPF0_SIGNATURE[2]) and
       (ABytes[i+3] = TPF0_SIGNATURE[3]) then
      Exit(i);
end;

function HasResWrapperPrefix(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= Length(RES_WRAPPER_SIG))
        and (ABytes[0] = RES_WRAPPER_SIG[0])
        and (ABytes[1] = RES_WRAPPER_SIG[1])
        and (ABytes[2] = RES_WRAPPER_SIG[2]);
end;

class function TDfmBinaryReader.IsBinary(const ABytes: TBytes): Boolean;
var
  i: Integer;
begin
  // TPF0 direkt am Anfang
  if Length(ABytes) >= Length(TPF0_SIGNATURE) then
  begin
    Result := True;
    for i := 0 to High(TPF0_SIGNATURE) do
      if ABytes[i] <> TPF0_SIGNATURE[i] then begin Result := False; Break; end;
    if Result then Exit;
  end;
  // Resource-Wrapper $FF $0A $00 (mit eingebettetem TPF0)
  Result := HasResWrapperPrefix(ABytes);
end;

class function TDfmBinaryReader.IsBinary(AStream: TStream): Boolean;
var
  Buf : array[0..3] of Byte;
  Pos : Int64;
  Got : Integer;
begin
  Result := False;
  if not Assigned(AStream) then Exit;
  Pos := AStream.Position;
  try
    Got := AStream.Read(Buf, SizeOf(Buf));
    if Got < 3 then Exit;
    // TPF0 direkt
    if (Got >= 4) and
       (Buf[0] = TPF0_SIGNATURE[0]) and
       (Buf[1] = TPF0_SIGNATURE[1]) and
       (Buf[2] = TPF0_SIGNATURE[2]) and
       (Buf[3] = TPF0_SIGNATURE[3]) then
      Exit(True);
    // Resource-Wrapper
    Result := (Buf[0] = RES_WRAPPER_SIG[0]) and
              (Buf[1] = RES_WRAPPER_SIG[1]) and
              (Buf[2] = RES_WRAPPER_SIG[2]);
  finally
    AStream.Position := Pos; // Position fuer den Caller wiederherstellen
  end;
end;

class function TDfmBinaryReader.ToText(const ABytes: TBytes): string;
var
  BinSrc : TBytesStream;
  TxtDst : TStringStream;
  TPFOffset : Integer;
  Slice : TBytes;
begin
  if Length(ABytes) = 0 then Exit('');

  if not IsBinary(ABytes) then
  begin
    // Text-DFM: UTF-8 mit ASCII-Fallback. DFMs sind im Repo praktisch
    // immer reines ASCII; UTF-8 deckt zusaetzlich Captions mit Umlauten
    // korrekt ab. Bei harten Decode-Fehlern (z.B. CP1252) fallback auf
    // Default-Encoding der Plattform - das stimmt mit dem alten
    // TFile.ReadAllText-Verhalten ueberein.
    try
      Exit(TEncoding.UTF8.GetString(ABytes));
    except
      Exit(TEncoding.Default.GetString(ABytes));
    end;
  end;

  // Resource-Wrapper $FF $0A $00 [ResName ...] TPF0 [DFM] -> eingebettetes
  // TPF0 extrahieren. Sonst nehmen wir die Bytes wie sie sind (TPF0 direkt).
  if HasResWrapperPrefix(ABytes) then
  begin
    TPFOffset := FindTPF0(ABytes, Length(RES_WRAPPER_SIG));
    if TPFOffset < 0 then
      raise EDfmBinaryReaderError.Create(
        'Resource-Wrapper-DFM ohne eingebettetes TPF0 - unbekanntes Format');
    SetLength(Slice, Length(ABytes) - TPFOffset);
    if Length(Slice) > 0 then
      Move(ABytes[TPFOffset], Slice[0], Length(Slice));
    BinSrc := TBytesStream.Create(Slice);
  end
  else
    BinSrc := TBytesStream.Create(ABytes);

  try
    TxtDst := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        // Unqualifizierter Aufruf: ObjectBinaryToText lebt in
        // System.Classes (siehe uses oben). Eine Qualifizierung mit
        // 'Classes.' funktioniert nur mit Unit-Alias auf 'Classes',
        // den Delphi 12 ohne Compat-Alias nicht setzt - daher E2003.
        ObjectBinaryToText(BinSrc, TxtDst);
      except
        on E: Exception do
          raise EDfmBinaryReaderError.CreateFmt(
            'Binary DFM conversion failed (%s): %s',
            [E.ClassName, E.Message]);
      end;
      Result := TxtDst.DataString;
    finally
      TxtDst.Free;
    end;
  finally
    BinSrc.Free;
  end;
end;

class function TDfmBinaryReader.ToText(AStream: TStream): string;
var
  Bytes : TBytes;
  N     : Int64;
  Pos   : Int64;
begin
  if not Assigned(AStream) then Exit('');
  Pos := AStream.Position;
  N := AStream.Size - Pos;
  if N <= 0 then Exit('');
  SetLength(Bytes, N);
  try
    AStream.ReadBuffer(Bytes[0], N);
  except
    on E: Exception do
      raise EDfmBinaryReaderError.CreateFmt(
        'Stream read failed (%s): %s', [E.ClassName, E.Message]);
  end;
  Result := ToText(Bytes);
end;

class function TDfmBinaryReader.ReadFile(const APath: string): string;
var
  Bytes: TBytes;
begin
  if (APath = '') or (not TFile.Exists(APath)) then Exit('');
  try
    Bytes := TFile.ReadAllBytes(APath);
  except
    on E: Exception do
      raise EDfmBinaryReaderError.CreateFmt(
        'Cannot read DFM file %s (%s): %s',
        [APath, E.ClassName, E.Message]);
  end;
  Result := ToText(Bytes);
end;

end.
