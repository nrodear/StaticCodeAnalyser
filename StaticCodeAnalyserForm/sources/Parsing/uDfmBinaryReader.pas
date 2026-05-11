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
    // 'TPF0' = $54 $50 $46 $30 (4 Bytes) - alle Delphi-Versionen ab 4
    // (frueher: $FF $0A $00 - hier nicht behandelt, kommt im realen
    // Code praktisch nicht mehr vor).
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

uses
  System.IOUtils;

const
  // 'TPF0' - Standard-DFM-Binaer-Praefix ab Delphi 4
  TPF0_SIGNATURE: array[0..3] of Byte = ($54, $50, $46, $30);

class function TDfmBinaryReader.IsBinary(const ABytes: TBytes): Boolean;
var
  i: Integer;
begin
  if Length(ABytes) < Length(TPF0_SIGNATURE) then Exit(False);
  for i := 0 to High(TPF0_SIGNATURE) do
    if ABytes[i] <> TPF0_SIGNATURE[i] then Exit(False);
  Result := True;
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
    if Got < SizeOf(Buf) then Exit;
    Result := (Buf[0] = TPF0_SIGNATURE[0]) and
              (Buf[1] = TPF0_SIGNATURE[1]) and
              (Buf[2] = TPF0_SIGNATURE[2]) and
              (Buf[3] = TPF0_SIGNATURE[3]);
  finally
    AStream.Position := Pos; // Position fuer den Caller wiederherstellen
  end;
end;

class function TDfmBinaryReader.ToText(const ABytes: TBytes): string;
var
  BinSrc : TBytesStream;
  TxtDst : TStringStream;
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

  // Binaer: durch RTL-ObjectBinaryToText durchschleifen.
  BinSrc := TBytesStream.Create(ABytes);
  try
    TxtDst := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        Classes.ObjectBinaryToText(BinSrc, TxtDst);
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
