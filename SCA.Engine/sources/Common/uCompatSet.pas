unit uCompatSet;

// Delphi-11-Kompatibilitaet: THashSet<T> gibt es erst seit Delphi 12
// (System.Generics.Collections). Unter D11 (CompilerVersion 35) stellt
// diese Unit einen minimalen Ersatz mit exakt der im Projekt genutzten
// Oberflaeche bereit: Create / Free / Add / Contains / for-in.
// Unter D12+ deklariert die Unit NICHTS - die Konsumenten (uCanBeClassMethod,
// uConstructorWithoutInherited, uConstStringParameter, uSymbolReferenceIndex)
// binden dann das native THashSet aus System.Generics.Collections; das
// uses uCompatSet ist dort ein No-op. So bleiben die Call-Sites in beiden
// Versionen unveraendert.

interface

{$IF CompilerVersion < 36}
uses
  System.Generics.Collections;

type
  // Duenner Wrapper um TDictionary<T,Boolean> (Werte ignoriert).
  // Add-Semantik wie D12-THashSet: True wenn der Wert NEU aufgenommen wurde.
  // for-in laeuft ueber den Keys-Enumerator (Klassen-Enumeratoren werden
  // vom Compiler-generierten for-in automatisch freigegeben).
  THashSet<T> = class
  private
    FItems: TDictionary<T, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const Value: T): Boolean;
    function Contains(const Value: T): Boolean;
    function GetEnumerator: TDictionary<T, Boolean>.TKeyEnumerator;
  end;
{$IFEND}

implementation

{$IF CompilerVersion < 36}

constructor THashSet<T>.Create;
begin
  inherited Create;
  FItems := TDictionary<T, Boolean>.Create;
end;

destructor THashSet<T>.Destroy;
begin
  FItems.Free;
  inherited;
end;

function THashSet<T>.Add(const Value: T): Boolean;
begin
  Result := not FItems.ContainsKey(Value);
  if Result then
    FItems.Add(Value, True);
end;

function THashSet<T>.Contains(const Value: T): Boolean;
begin
  Result := FItems.ContainsKey(Value);
end;

function THashSet<T>.GetEnumerator: TDictionary<T, Boolean>.TKeyEnumerator;
begin
  Result := FItems.Keys.GetEnumerator;
end;

{$IFEND}

end.
