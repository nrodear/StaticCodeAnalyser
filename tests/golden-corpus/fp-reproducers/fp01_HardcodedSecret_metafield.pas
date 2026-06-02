unit fp01_HardcodedSecret_metafield;

// Regression-Test fuer Round 1 (commit 0d752f3):
// Meta-Felder wie 'SourceToken' / 'TokenRef' / 'PasswordChar' duerfen
// NICHT von uHardcodedSecret als hardcoded credential geflaggt werden -
// das sind beschreibende Felder ueber die Quelle/Referenz/Anzeige eines
// Secrets, nicht das Secret selbst.

interface

type
  TSonarConfig = record
    Token       : string;
    SourceToken : string;    // Meta-Feld: woher kommt der Token
    TokenRef    : string;    // Meta-Feld: Referenz/Header-Name
  end;

implementation

procedure ConfigureSonar;
var
  Cfg : TSonarConfig;
begin
  Cfg.SourceToken := 'env SONAR_TOKEN';      // <- MUST NOT trigger SCA004
  Cfg.TokenRef    := 'X-Sonar-Token';        // <- MUST NOT trigger SCA004
end;

end.
