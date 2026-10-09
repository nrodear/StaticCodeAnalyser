unit uHardcodedIpAddress;

// SCA200 HardcodedIpAddress: IPv4-/IPv6-Adressen in Pascal-String-Literalen.
//
// Grammatik, Klassen und Gates stehen in uIpAddressScan (rein, FPC-
// getestet); hier nur: Datei lesen, Kommentare entfernen (Kommentare
// zaehlen nie als Code), Testunits auslassen, melden.
//
// Testunits schweigen (Stufe tplSecret wie SCA016): Testdaten duerfen feste
// Adressen haben - Sonar S1313 prueft ebenfalls nur Main-Code. Demo- und
// Sample-Units melden weiter; der Fixture-Filter des CLI blendet sie im
// Default-Profil aus.
//
// Korpus (FPC-Nachlauf 2026-10-09, Konzept_HardcodedIp 4.4): im
// Pascal-Produktivcode der drei Korpora 38 Funde, alle echte feste
// Adressen (Indy-Root-DNS, mORMot '8.8.8.8' und DHCP-Default, ACBr-
// Drucker-IP). Ohne die Gates waeren es rund 500 gewesen (OIDs,
// Versionen, Multicast-Tabellen, Loopback).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  THardcodedIpAddressDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil); static;
  end;

implementation

uses
  uFileTextCache, uDetectorUtils, uIpAddressScan;

class procedure THardcodedIpAddressDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines   : TStringList;
  Cached  : Boolean;
  Code    : string;
  LineFor : TArray<Integer>;
  H       : TCodeIpHit;
begin
  if TDetectorUtils.IsTestFixturePath(FileName, CtxScanRoot(AContext),
       tplSecret) then
    Exit;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Kommentare ersatzlos weg, Literale und Zeilen bleiben (geteilter
    // Strip-Cache des Kontexts, wie SCA115/SCA152).
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor,
      AContext, FileName);
    for H in TIpAddressScan.ScanPascalCode(Code) do
      if H.Reason = '' then
        Results.Add(TLeakFinding.NewAtPos(FileName, LineFor, H.Pos,
          TIpAddressScan.CodeMessage(H.Hit), fkHardcodedIpAddress));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
