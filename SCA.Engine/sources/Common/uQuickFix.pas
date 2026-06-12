unit uQuickFix;

// Quick-Fix-Engine: liefert pro Finding eine MODIFIZIERTE Code-Zeile,
// die der Aufrufer dem User vorlegen (oder via IDE-Editor-Writer direkt
// anwenden) kann.
//
// Bewusst pure-text + AST-frei + unit-testbar - die IDE-/Editor-Integration
// (IOTAEditWriter / Clipboard) liegt im konsumierenden Layer (IDE-Plugin
// bzw. Standalone-Form), damit sich der Engine auch CLI-headless triggern
// laesst.
//
// Erweiterung um neue Quick-Fixes:
//   1. Eine `TQuickFixProvider`-Funktion definieren (signature siehe unten)
//   2. Im `initialization`-Block via `RegisterProvider(Kind, Provider)` registrieren
//   3. Tests in tests/uTestQuickFix.pas
//
// MVP enthaelt einen Provider: RedundantBoolean
//   X = True   -> X
//   X <> False -> X
//   X = False  -> not X
//   X <> True  -> not X
//
// Folgende Erweiterungen sind angedacht (TODO):
//   - FreeAndNilHint:        X.Free; X := nil;   -> FreeAndNil(X);
//   - EmptyArgumentList:     Foo()               -> Foo
//   - AssignedAndAssignedNil: Assigned(X) and (X <> nil) -> Assigned(X)
//   - EmptyExcept:           except end          -> except on E: Exception do LogError(E); end
//   - LockWithoutTryFinally: Lock.Enter; body; Lock.Leave -> Lock.Enter; try body finally Lock.Leave end

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TQuickFixResult = record
    Applied   : Boolean;   // True wenn eine Replacement berechnet werden konnte
    Original  : string;    // Original-Zeilen-Inhalt (zur Diff-Anzeige)
    Fixed     : string;    // Fixed-Zeilen-Inhalt (das was der User reinpasten/einspielen soll)
    Description : string;  // Kurze Beschreibung der Aktion ("Replaced 'X = True' with 'X'")
  end;

  // Provider-Signatur: bekommt das Finding + die Original-Zeile als
  // Source-of-Truth, liefert das Replacement. False wenn kein Fix moeglich
  // (z.B. unerwartetes Pattern - der Provider gibt ehrlich auf).
  TQuickFixProvider = reference to function(
    const F: TLeakFinding;
    const OriginalLine: string;
    out FixedLine: string;
    out Description: string): Boolean;

  TQuickFix = class
  public
    // Liefert das Quick-Fix-Result fuer ein Finding. Result.Applied=False
    // wenn kein Provider fuer den Kind registriert ist oder das Pattern
    // auf der Zeile nicht matched.
    class function ProposeFix(const F: TLeakFinding;
      const OriginalLine: string): TQuickFixResult; static;

    // Provider-Registry. Public fuer Tests + Erweiterungen.
    class procedure RegisterProvider(Kind: TFindingKind;
      Provider: TQuickFixProvider); static;

    // True wenn fuer Kind ein Provider registriert ist.
    class function HasProviderFor(Kind: TFindingKind): Boolean; static;
  end;

implementation

// noinspection-file ConcatToFormat, ConsecutiveSection, DuplicateBlock, DuplicateString, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter, UnusedPublicMember
// QuickFix-Templates bauen lange Hint-Texte durch String-Concat zusammen -
// Format() wuerde die Templates uebersichtlicher machen, aber das Refactor
// ist wert-arm (statische Strings, kein Hot-Path, kein Locale-Risiko).

uses
  System.RegularExpressions;

var
  GProviders : TDictionary<TFindingKind, TQuickFixProvider> = nil;

{ ---- Built-in Provider: RedundantBoolean ---- }

function RedundantBooleanProvider(const F: TLeakFinding;
  const OriginalLine: string; out FixedLine: string;
  out Description: string): Boolean;
// Matched Patterns (case-insensitive, mit Wortgrenzen):
//   <expr> = True   -> <expr>
//   <expr> <> False -> <expr>
//   <expr> = False  -> not <expr>
//   <expr> <> True  -> not <expr>
//
// `expr` ist ein einzelner Identifier oder Property-Pfad (Foo, FFoo,
// Self.Bar, Obj.Prop). Komplexere Ausdruecke (Funktionsaufrufe mit
// Parens, Klammer-Hierarchien) werden konservativ nicht angefasst -
// dann gibt der Provider auf und der User macht es manuell.
const
  // Identifier ODER Property-Pfad. Bewusst KEINE Klammern oder Operatoren
  // im Ausdruck, damit wir Side-Effects nicht doppelt aufrufen.
  EXPR = '([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)';
var
  Re : TRegEx;
  M  : TMatch;
begin
  Result := False;
  FixedLine := OriginalLine;
  Description := '';

  // 1) <expr> = True  ->  <expr>
  Re := TRegEx.Create('(?i)\b' + EXPR + '\s*=\s*True\b');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) + M.Groups[1].Value +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Removed redundant ''= True'' from %s', [M.Groups[1].Value]);
    Exit(True);
  end;

  // 2) <expr> <> False  ->  <expr>
  Re := TRegEx.Create('(?i)\b' + EXPR + '\s*<>\s*False\b');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) + M.Groups[1].Value +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Removed redundant ''<> False'' from %s', [M.Groups[1].Value]);
    Exit(True);
  end;

  // 3) <expr> = False  ->  not <expr>
  Re := TRegEx.Create('(?i)\b' + EXPR + '\s*=\s*False\b');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) + 'not ' + M.Groups[1].Value +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Replaced ''= False'' with ''not'' on %s', [M.Groups[1].Value]);
    Exit(True);
  end;

  // 4) <expr> <> True  ->  not <expr>
  Re := TRegEx.Create('(?i)\b' + EXPR + '\s*<>\s*True\b');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) + 'not ' + M.Groups[1].Value +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Replaced ''<> True'' with ''not'' on %s', [M.Groups[1].Value]);
    Exit(True);
  end;

  // Kein passendes Pattern auf der Zeile - kein Fix.
end;

{ ---- Built-in Provider: FreeAndNilHint ---- }

function FreeAndNilProvider(const F: TLeakFinding;
  const OriginalLine: string; out FixedLine: string;
  out Description: string): Boolean;
// Matched Pattern (auf der "Free"-Zeile - der Detector zeigt typisch auf die
// erste der beiden Zeilen):
//   X.Free;   ->  FreeAndNil(X);
// Auf der FOLGE-Zeile darf der User dann die "X := nil;" Zeile loeschen,
// aber das ist eine Multiline-Aktion die ueber den OriginalLine-Skop
// hinausgeht. Dieser Provider macht den Single-Line-Teil und beschreibt
// den Folge-Schritt in Description.
const
  EXPR = '([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)';
var
  Re : TRegEx;
  M  : TMatch;
begin
  Result := False;
  FixedLine := OriginalLine;
  Description := '';
  Re := TRegEx.Create('(?i)\b' + EXPR + '\s*\.\s*Free\s*;');
  M := Re.Match(OriginalLine);
  if not M.Success then Exit;
  FixedLine := Copy(OriginalLine, 1, M.Index - 1) +
               Format('FreeAndNil(%s);', [M.Groups[1].Value]) +
               Copy(OriginalLine, M.Index + M.Length, MaxInt);
  Description := Format('Replaced ''%s.Free;'' with ''FreeAndNil(%s);'' - ' +
                        'also remove the following ''%s := nil;'' line.',
                        [M.Groups[1].Value, M.Groups[1].Value, M.Groups[1].Value]);
  Result := True;
end;

{ ---- Built-in Provider: EmptyArgumentList ---- }

function EmptyArgumentListProvider(const F: TLeakFinding;
  const OriginalLine: string; out FixedLine: string;
  out Description: string): Boolean;
// Foo()  ->  Foo
// Ident gefolgt von ungewichteten "()" - kein Inhalt zwischen den Klammern.
const
  EXPR = '([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)';
var
  Re : TRegEx;
  M  : TMatch;
begin
  Result := False;
  FixedLine := OriginalLine;
  Description := '';
  Re := TRegEx.Create('\b' + EXPR + '\s*\(\s*\)');
  M := Re.Match(OriginalLine);
  if not M.Success then Exit;
  FixedLine := Copy(OriginalLine, 1, M.Index - 1) + M.Groups[1].Value +
               Copy(OriginalLine, M.Index + M.Length, MaxInt);
  Description := Format('Dropped empty argument list on %s', [M.Groups[1].Value]);
  Result := True;
end;

{ ---- Built-in Provider: AssignedAndAssignedNil ---- }

function AssignedAndAssignedNilProvider(const F: TLeakFinding;
  const OriginalLine: string; out FixedLine: string;
  out Description: string): Boolean;
// Assigned(X) and (X <> nil)  ->  Assigned(X)
// auch:
// (X <> nil) and Assigned(X)  ->  Assigned(X)
const
  EXPR = '([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)';
var
  Re : TRegEx;
  M  : TMatch;
begin
  Result := False;
  FixedLine := OriginalLine;
  Description := '';

  Re := TRegEx.Create('(?i)Assigned\s*\(\s*' + EXPR + '\s*\)\s+and\s+\(\s*\1\s*<>\s*nil\s*\)');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) +
                 Format('Assigned(%s)', [M.Groups[1].Value]) +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Dropped redundant nil-check after Assigned(%s)', [M.Groups[1].Value]);
    Exit(True);
  end;

  Re := TRegEx.Create('(?i)\(\s*' + EXPR + '\s*<>\s*nil\s*\)\s+and\s+Assigned\s*\(\s*\1\s*\)');
  M := Re.Match(OriginalLine);
  if M.Success then
  begin
    FixedLine := Copy(OriginalLine, 1, M.Index - 1) +
                 Format('Assigned(%s)', [M.Groups[1].Value]) +
                 Copy(OriginalLine, M.Index + M.Length, MaxInt);
    Description := Format('Dropped redundant nil-check before Assigned(%s)', [M.Groups[1].Value]);
    Exit(True);
  end;
end;

{ ---- TQuickFix-Klassenmethoden ---- }

class procedure TQuickFix.RegisterProvider(Kind: TFindingKind;
  Provider: TQuickFixProvider);
begin
  if GProviders = nil then
    GProviders := TDictionary<TFindingKind, TQuickFixProvider>.Create;
  GProviders.AddOrSetValue(Kind, Provider);
end;

class function TQuickFix.HasProviderFor(Kind: TFindingKind): Boolean;
begin
  Result := (GProviders <> nil) and GProviders.ContainsKey(Kind);
end;

class function TQuickFix.ProposeFix(const F: TLeakFinding;
  const OriginalLine: string): TQuickFixResult;
var
  Provider    : TQuickFixProvider;
  FixedLine   : string;
  Description : string;
begin
  Result.Applied     := False;
  Result.Original    := OriginalLine;
  Result.Fixed       := OriginalLine;
  Result.Description := '';

  if (GProviders = nil) or not GProviders.TryGetValue(F.Kind, Provider) then Exit;
  if not Provider(F, OriginalLine, FixedLine, Description) then Exit;

  Result.Applied     := True;
  Result.Fixed       := FixedLine;
  Result.Description := Description;
end;

initialization
  GProviders := TDictionary<TFindingKind, TQuickFixProvider>.Create;
  // Built-in Provider registrieren
  TQuickFix.RegisterProvider(fkRedundantBoolean,       RedundantBooleanProvider);
  TQuickFix.RegisterProvider(fkFreeAndNilHint,         FreeAndNilProvider);
  TQuickFix.RegisterProvider(fkEmptyArgumentList,      EmptyArgumentListProvider);
  TQuickFix.RegisterProvider(fkAssignedAndAssignedNil, AssignedAndAssignedNilProvider);

finalization
  FreeAndNil(GProviders);

end.
