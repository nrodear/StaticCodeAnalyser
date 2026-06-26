unit MeineUnit;

{$WARNINGS OFF}{$HINTS OFF}   // absichtliche Bugs (Leak/Uninit/no-Result) - Compiler-Rauschen aus

// noinspection-file All
// Sample-/Fixture-Datei: enthaelt absichtliche Bugs (Leak/Uninit) als Detektor-Demo.

// Testklasse fuer den statischen Speicherleck-Analyser (TStaticAnalyzer2).
// Enthaelt absichtliche Speicherlecks fuer Testzwecke.

interface

uses
  System.SysUtils, System.Classes;

type
  TMeineKlasse = class
  private
    function MethodeMethodeMitSpeicherleck: TStringList;
    function MethodeMethodeTStringListNotFree: TStringList;

  public
    // Methode MIT Speicherleck: test wird erstellt, aber nie freigegeben
    function MethodeMitSpeicherleck: string;

    // Methode OHNE Speicherleck: test wird korrekt per FreeAndNil freigegeben
    function MethodeOhneSpeicherleck: string;

    // Methode mit MEHREREN Speicherlecks
    function MehrereSpeicherlecks: string;

    // Leerer except-Block: Exception wird stillschweigend verschluckt
    procedure LeererExceptBlock;

    // Leerer except-Block mit Kommentar: auch ein Code-Smell
    procedure LeererExceptBlockMitKommentar;
  end;

procedure GetMeineKlasseUseSample;

implementation

function TMeineKlasse.MethodeMitSpeicherleck: string;
var
  test: TStringList;
begin

  test.Add('Eintrag 1');
  Result := test.Text;
  // Fehler: test.Free fehlt -> Speicherleck
end;

function TMeineKlasse.MethodeOhneSpeicherleck: string;
var
  test: TStringList;
begin
  test := TStringList.Create;
  try
    test.Add('Eintrag 1');
    Result := test.Text;
  finally
    FreeAndNil(test);
  end;
end;

function TMeineKlasse.MehrereSpeicherlecks: string;
var
  list1: TStringList;
  list2: TStringList;

begin
  list1 := TStringList.Create;

  list2 := TStringList.Create;
  list1.Add('A');
  list2.Add('B');
  Result := list1.Text + list2.Text;
  // Fehler: list1.Free und list2.Free fehlen -> zwei Speicherlecks
  list1.free;
  list2.free;
end;

function TMeineKlasse.MethodeMethodeMitSpeicherleck: TStringList;
begin
  Result := TStringList.Create;
end;

function TMeineKlasse.MethodeMethodeTStringListNotFree: TStringList;
var
  list1: TStringList;
begin
  list1 := MethodeMethodeMitSpeicherleck;
end;

procedure TMeineKlasse.LeererExceptBlock;
begin
  try
    raise Exception.Create('Test');
  except
    // leer -- Exception wird verschluckt!
  end;
end;

procedure TMeineKlasse.LeererExceptBlockMitKommentar;
var
  i: Integer;
begin
  try
    i := 1 div 2;
  except
  end;
end;

procedure GetMeineKlasseUseSample;
var
  meine: TMeineKlasse;
begin
  meine := TMeineKlasse.Create;
end;

end.
