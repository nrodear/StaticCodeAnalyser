unit uDfmFrameResolver;

// Cross-Unit-Resolver fuer Frame-Composition. Wenn ein DFM eine
// Frame-Instance enthaelt
//
//   inline Frame1: TFrame1
//     Left = 0
//     Top = 0
//   end
//
// dann hat der Knoten 'Frame1' im TComponentGraph **keine** Kinder -
// die echten Komponenten leben in 'uFrame1.dfm' der Frame-Klasse
// 'TFrame1'. Detektoren, die ueber die volle Komponenten-Hierarchie
// laufen wollen (Tab-Order-Conflict, Layer-Violation, God-Handler,
// Cross-Form-Coupling), brauchen einen Resolver, der die Frame-DFM auf
// Bedarf nachlaedt.
//
// Diese Unit liefert genau das: gegeben eine Frame-Class-Ref liefert
// ResolveFrameGraph das Component-Graph der Frame-Klasse. Caller
// uebernimmt Ownership ueber den zurueckgegebenen Graph - typischer
// Pattern ist "build, walk, free" innerhalb des Detektor-Aufrufs.
//
// Memory-Disziplin: Wir CACHEN bewusst NICHT auf der Repo-Index-Ebene.
// Frame-DFMs sind in echten Apps eher wenige (typisch < 20 Frames pro
// Repo), und ein Detektor-Lauf, der den Resolver pro Frame-Instance
// einmal anruft, parst denselben Frame mehrfach - das ist OK gegen
// die alternativen Komplikationen einer globalen Cache-Lifetime-
// Verwaltung. Wenn das spaeter zur Hot-Loop wird, kann eine
// Cache-Schicht ueber RepoIndex nachgereicht werden.

interface

uses
  System.Generics.Collections,
  uComponentGraph, uDfmRepoIndex;

type
  TFrameResolver = class
  public
    // Findet die .dfm zur FrameClass via RepoIndex.GetUnitForClass +
    // ChangeFileExt(.pas->.dfm), liest sie ein (binaer-Reader durchlauft
    // automatisch), parst sie und liefert das frische TComponentGraph
    // zurueck. Caller-Owned (Free aufrufen).
    //
    // Rueckgabewerte:
    //   * nil  - RepoIndex ist nil oder kennt FrameClass nicht, oder
    //            die zugehoerige .dfm existiert nicht, oder Parse-
    //            Fehler.
    //   * sonst - Graph mit den Frame-Komponenten. Roots[0] traegt die
    //            Frame-Klassen-Wurzel.
    class function ResolveFrameGraph(const FrameClassRef: string;
      RepoIndex: TDfmRepoIndex): TComponentGraph; static;

    // Convenience: gibt eine flache Liste aller Komponenten innerhalb
    // einer Frame-Instance zurueck (Roots inkl. Children rekursiv).
    // Die LIST gehoert dem Caller (Free) - die KNOTEN gehoeren weiter
    // dem _ausgegebenen_ FrameGraph, der ebenfalls Caller-Owned ist.
    // Typische Reihenfolge:
    //   var Comps := TFrameResolver.EnumerateFrameComponents(..., G);
    //   try
    //     for N in Comps do ...
    //   finally
    //     Comps.Free;
    //     G.Free;
    //   end;
    class function EnumerateFrameComponents(const FrameClassRef: string;
      RepoIndex: TDfmRepoIndex;
      out FrameGraph: TComponentGraph): TList<TComponentNode>; static;

    // Heuristik: hat dieser Knoten Frame-Composition-Semantik?
    // Aktuell: 'IsInline=True'. Hilft Detektoren, ohne die Klassen-
    // Hierarchie zu kennen, Frame-Instanzen von normalen Komponenten
    // zu unterscheiden.
    class function IsFrameInstance(Node: TComponentNode): Boolean; static;
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.IOUtils,
  uDfmParser, uDfmBinaryReader;

class function TFrameResolver.IsFrameInstance(Node: TComponentNode): Boolean;
begin
  Result := (Node <> nil) and Node.IsInline;
end;

class function TFrameResolver.ResolveFrameGraph(const FrameClassRef: string;
  RepoIndex: TDfmRepoIndex): TComponentGraph;
var
  PasFile : string;
  DfmFile : string;
  Source  : string;
  Parser  : TDfmParser;
begin
  Result := nil;
  if RepoIndex = nil then Exit;
  if FrameClassRef = '' then Exit;

  PasFile := RepoIndex.GetUnitForClass(FrameClassRef);
  if (PasFile = '') or not TFile.Exists(PasFile) then Exit;

  DfmFile := TPath.ChangeExtension(PasFile, '.dfm');
  if not TFile.Exists(DfmFile) then Exit;

  try
    Source := TDfmBinaryReader.ReadFile(DfmFile);
    if Source = '' then Exit;
    Parser := TDfmParser.Create;
    try
      Result := Parser.ParseSource(Source);
    finally
      Parser.Free;
    end;
  except
    // Parse-/IO-Fehler einer Frame-DFM darf den umgebenden Detektor-
    // Lauf nicht reissen. Result bleibt nil, Detektor faellt
    // konservativ auf "kann den Frame nicht aufloesen" zurueck.
    if Assigned(Result) then
    begin
      Result.Free;
      Result := nil;
    end;
  end;
end;

class function TFrameResolver.EnumerateFrameComponents(
  const FrameClassRef: string; RepoIndex: TDfmRepoIndex;
  out FrameGraph: TComponentGraph): TList<TComponentNode>;
begin
  Result    := nil;
  FrameGraph := ResolveFrameGraph(FrameClassRef, RepoIndex);
  if FrameGraph = nil then Exit;
  // EnumerateAll liefert eine Caller-Owned Liste mit allen Knoten
  // (depth-first inklusive Roots). Genau das was Detektoren brauchen.
  Result := FrameGraph.EnumerateAll;
end;

end.
