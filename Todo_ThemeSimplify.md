# Todo — IDE-Theme Vereinfachung

> Branch: `setTheme` · Stand: 2026-05-22
>
> Ziel: Theme im IDE-Plugin in **allen** Situationen fehlerfrei setzen, mit
> möglichst wenig Code. Ein zentraler Mechanismus statt der heutigen
> Parallel-Pfade (CMStyleChanged + Notifier + SetParent-Override +
> One-Shot-Helper + 11x `Color := clBtnFace`).

---

## 1. Ist-Zustand (Kurzbestand)

### Trigger-Quellen — heute drei parallele Pfade

| Pfad | Datei / Zeile | Wann feuert er |
|---|---|---|
| `INTAIDEThemingServicesNotifier.ChangedTheme` | [uIDEThemeIntegration.pas:136](StaticCodeAnalyserIDE/uIDEThemeIntegration.pas#L136) | IDE-Theme wechselt (Tools→Options→User Interface→IDE Style) |
| `CMStyleChanged`-Message | [uIDEAnalyserForm.pas:2821](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L2821) | VCL-Style-Wechsel global (= IDE-Theme-Wechsel auch) |
| `SetParent`-Override | [uIDEAnalyserForm.pas:2831](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L2831) | Dock↔Float-Wechsel, erstes Hosting |

Alle drei landen am Ende in `RefreshFromIDETheme` — der Notifier ist also
**dual** zur CMStyleChanged-Message und der SetParent-Override macht
denselben Refresh + zusätzlich Layout-Refit.

### APIs für Theme-Anwendung — heute zwei

| API | Wo |
|---|---|
| `TIDEThemeIntegration` (mit Notifier, Lifecycle, Detach-Tanz) | Dock-Frame [uIDEAnalyserForm.pas:556](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L556) |
| `ApplyIDETheme(AComponent)` (One-Shot, kein Notifier) | Tools→Options-Pages [uIDESCAOptions.pas:642](StaticCodeAnalyserIDE/uIDESCAOptions.pas#L642), [uIDESonarOptions.pas:445](StaticCodeAnalyserIDE/uIDESonarOptions.pas#L445) |

### Farbquellen — heute drei

1. **Frame-Theme**: `StyleServices.GetSystemColor(clWindow/clBtnFace)` — IDE-Style.
2. **Editor-Theme**: `INTACodeEditorServices.Options.BackgroundColor[atWhiteSpace]` — kann vom Frame-Theme abweichen (heller Editor, dunkle IDE).
3. **Hardcoded `clBtnFace`** auf 11 Panels im Frame ([uIDEAnalyserForm.pas:561, 618, 676, 697, 818, 825, 868, 905, 947, 1014, 1133](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L561)).

### Sonderfälle

- `TStringGrid` ignoriert das rekursive Invalidate → expliziter `Repaint`
  via `RepaintGridAfterTheme`-Callback ([uIDEAnalyserForm.pas:1281](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L1281)).
- `Floating`-Mode: `TopForm` (Host-TForm) muss separat `ApplyTheme` bekommen,
  sonst bleibt die Titelzeile im alten Theme ([uIDEThemeIntegration.pas:213](StaticCodeAnalyserIDE/uIDEThemeIntegration.pas#L213)).
- `TAnnotationOverlay` opted **per `StyleElements := []`** komplett aus dem
  VCL-Theming aus und mischt eigene Akzentfarben über
  `StyleServices.GetSystemColor(clWindow)` + `BlendColor` ([uIDEAnnotationOverlay.pas:236-365](StaticCodeAnalyserIDE/uIDEAnnotationOverlay.pas#L236)) —
  eigener Render-Pfad parallel zum Standard-Theme.

---

## 2. Bekannte / vermutete Fehlerszenarien

| # | Szenario | Wo es bricht | Symptom |
|---|---|---|---|
| F1 | IDE-Start im Dark-Theme, Frame docked beim ersten Open | `FrameCreated` vs. `Attach`-Race | Kurzer hellgrauer Flash im Frame |
| F2 | Float↔Dock-Wechsel | `SetParent`-Override fängt es; ohne Override bliebe Titelzeile alt | Titelzeile alt-themed |
| F3 | IDE-Theme-Wechsel zur Laufzeit | Beide Trigger feuern (Notifier + CMStyleChanged) | Doppelarbeit (harmlos, aber Indiz) |
| F4 | Tools→Options offen, IDE-Theme wechselt im Hintergrund | Options-Frame hat **keinen** Notifier (One-Shot-API) | Options-Page bleibt im alten Theme bis Reopen |
| F5 | `TStringGrid` nach Theme-Wechsel | Invalidate reicht nicht | Grid-Header/-Zeilen alt-coloured |
| F6 | `TAnnotationOverlay`-Wiederanzeige nach Theme-Wechsel | Cache-Key `WindowBase` triggert Re-Render | OK in der Praxis |
| F7 | Statusbar / Progressbar / Combobox nach Wechsel | `clBtnFace` re-resolved durch ApplyTheme | OK |
| F8 | Custom-Style "Mountain Mist" / "Carbon" / 3rd-party | `clBtnFace` wird vom Style remapped | OK durch ApplyTheme |
| F9 | Detach-Race im Frame-Destroy | Notifier-`Detach` setzt `FOwner := nil` vor RemoveNotifier | OK (heute robust gelöst) |

**Priorität:** F1, F4 und F5 sind die User-sichtbaren Brüche; F3 ist
Code-Geruch ohne sichtbares Symptom.

---

## 3. Vereinfachungs-Konzepte

Reihenfolge = **Empfehlung zur Umsetzung** (von hoher Wirkung → niedriger
Aufwand). Jedes Konzept ist ein eigenständig commit-barer Schritt.

### K1 — Ein zentraler `TIDETheme`-Singleton mit `Apply(Control)` und `Subscribe(Callback)`

**Statt** `TIDEThemeIntegration` + `ApplyIDETheme` + lose CMStyleChanged-Hooks.

```pascal
TIDETheme = class
  class procedure Apply(AControl: TWinControl); static;
  class function  Subscribe(ACallback: TThemeChangedProc): IInterface; static;
  class function  FrameBg: TColor; static;
  class function  EditorBg: TColor; static;
  class function  IsDark: Boolean; static;
end;
```

- `Apply(Control)`: macht ApplyTheme auf Control **und** TopForm (Float-Mode),
  Invalidate rekursiv, Grid-Repaint forciert.
- `Subscribe(cb)`: registriert einen Callback, der bei Theme-Wechsel gerufen
  wird. Returned `IInterface` — beim Free der Refcount-Hülle wird
  automatisch deregistriert (RAII statt manueller Detach).
- Genau **ein** Notifier global, im Singleton beim ersten Subscribe registriert.

**Effekt:** Frame, Options-Pages, Annotation-Overlay, Line-Highlighter
benutzen **dieselbe** API. Kein Frame-spezifischer Notifier mehr.

**Risiko:** Notifier muss bei Plugin-Unload entfernt werden — über
`finalization` des Singletons.

---

### K2 — Notifier ODER CMStyleChanged, nicht beides

Beide Trigger lösen denselben Refresh aus. Empfehlung: **Notifier behalten,
CMStyleChanged-Override löschen.**

- Notifier ist die ToolsAPI-vorgesehene Quelle, CMStyleChanged-Broadcast
  ist VCL-Implementation-Detail.
- Spart den Message-Handler + den Frame-Field-Zugriff während Teardown.

**Falls** in Tests CMStyleChanged-only-Fälle auftauchen (z.B. modal child
ohne Notifier-Reach): Notifier-Singleton aus K1 hängt sich an die
**Application** statt an einzelne Frames — dann fehlt nichts.

---

### K3 — `Color := clBtnFace` durch `ParentColor := True` ersetzen

11 Panels im Frame setzen explizit `Color := clBtnFace`. Mit
`ParentBackground := True; ParentColor := True` erben sie vom Frame, der
selbst `clBtnFace` hat. **Resultat:** ApplyTheme auf den Frame propagiert
automatisch — keine 11 Touch-Points mehr.

**Pflicht-Check:** jedes Panel das aktuell `Color := clBtnFace` setzt
muss zusätzlich keine eigene Akzentfarbe brauchen (z.B. PanelStats hat
sonarisch-eingefärbte Tiles drauf — die Tile-Kinder hängen am Panel mit
eigener Color, also OK).

---

### K4 — `SetParent`-Override entkoppeln: Theme- und Layout-Refit getrennt

Heute mixt `SetParent` Theme-Refresh + WM_SCA_REFIT. Nach K1 wird Theme
über das Subscribe-Modell gehandhabt → SetParent-Override **nur noch**
für Layout (WM_SCA_REFIT + DockRefitTimer). Klare Trennung der
Verantwortlichkeiten.

**Edge-Case Float↔Dock:** ToolsAPI feuert dabei kein
`ChangedTheme`. Daher zusätzlich beim Dock-State-Wechsel ein
`TIDETheme.Apply(Self)` aus dem Layout-Refit-Pfad rufen.

---

### K5 — Singleton-Color-Cache statt wiederholter Service-Lookups

Heute fragt `GetEditorThemeBgColor` bei jedem ShowAt der Annotation-
Overlay den `INTACodeEditorServices.Options.BackgroundColor`-Service ab.
Mit `TIDETheme.EditorBg` als gecachtem Wert:

- Cache wird invalidiert im `ChangedTheme`-Callback (`Notifier`).
- Consumers lesen synchron ohne Service-Call.
- Auch `StyleServices.GetSystemColor(clWindow)`-Lookups landen im Cache.

**Performance:** Annotation-Overlay rendert pro Hover-Move neu —
Service-Lookup einsparen ist messbar (~µs, aber kostet kein Strom).

---

### K6 — Grid-Repaint-Callback in `TIDETheme.Apply` einbauen

`RepaintGridAfterTheme` ist eine Frame-spezifische Sonderlocke, die
nur einen TStringGrid betrifft. `TIDETheme.Apply(Control)` walked
ohnehin rekursiv — für `is TCustomGrid` zusätzlich `Repaint` rufen.
**Callback-Argument** im Subscribe-Modell entfällt; das Standard-Apply
deckt es ab.

---

### K7 — Annotation-Overlay-StyleElements-Audit

Der Overlay macht aktuell `StyleElements := []` auf **9** Sub-Controls,
um VCL-Theming zu unterdrücken. Davon notwendig:

- `FBorderPanel`, `FPanelTitle`, `FLblBadge`, `FLblTitle` — tragen
  Severity-Akzentfarbe, **müssen** opt-out bleiben (sonst übermalt VCL
  unsere Custom-Color).
- `FContentArea`, `FPanelDesc`, `FLblDesc`, `FPanelFix`, `FLblFix` —
  liegen auf Editor-BG, **könnten** vom Theme erben. Audit:
  - Wenn der Editor-BG nicht via `StyleServices.GetSystemColor(clWindow)`
    kommt (Editor-Theme ≠ Frame-Theme), bleibt opt-out richtig.
  - Status quo: Editor-BG kommt via `INTACodeEditorServices`, das ist
    korrekt unabhängig vom Frame-Theme → opt-out **muss** bleiben.

**Ergebnis K7:** keine Code-Änderung, aber Dokumentation in einem
Kommentar-Header verdichten. (Ehrlich: kein Vereinfachungs-Win — eher
Klarheit.)

---

### K8 — Options-Pages an `TIDETheme.Subscribe` koppeln (F4)

Heute kriegen die Options-Frames den Theme-Wechsel nicht mit. Mit K1
hängen sie sich beim Create per `TIDETheme.Subscribe` ein und beim
Destroy entlässt die Refcount-Hülle den Slot. **Damit ist F4 gefixt** —
Options-Page folgt einem IDE-Theme-Switch live.

---

### K9 — `TIDEThemeIntegration`-Unit ersatzlos streichen

Nach K1+K2+K6 ist `TIDEThemeIntegration` redundant. Frame-Field
`FThemeIntegration` weg, Helper-Datei löschen, `FreeAndNil`-Call im
Destruktor weg, `Attach`-Aufruf in `FrameCreated` weg.

**Netto-Loss:** ~240 Zeilen `uIDEThemeIntegration.pas` + ~30 Zeilen
Frame-Plumbing.

---

## 4. Empfohlene Reihenfolge & Aufwand

| Schritt | Konzept | Aufwand | Wirkung |
|---|---|---|---|
| 1 | K1 (Singleton + Subscribe) anlegen, **noch ohne** Notifier-Switch | 1.5h | Infrastruktur |
| 2 | K6 (Grid-Repaint in Apply integrieren) | 15min | – |
| 3 | K3 (`ParentColor := True` Sweep) | 30min | F1 (Flash reduziert) |
| 4 | K8 (Options-Pages subscriben) | 20min | F4 gefixt |
| 5 | K2 (CMStyleChanged-Override löschen) | 10min | Code-Geruch weg |
| 6 | K4 (SetParent-Override entkoppeln) | 30min | Klarheit |
| 7 | K9 (`uIDEThemeIntegration.pas` entfernen) | 20min | -240 LOC |
| 8 | K5 (Color-Cache füllen) | 30min | Perf-Detail |
| 9 | K7 (Overlay-StyleElements-Audit-Kommentar) | 10min | Doku |

**Gesamt:** ~4h Code + Test, inkl. Build/Smoke-Test in der IDE.

---

## 5. Akzeptanz-Tests (manuell, IDE-Plugin)

Pro Schritt verifizieren, am Ende **alle** Tests durchlaufen lassen:

- [ ] **T1** IDE-Cold-Start im Dark-Theme → Frame öffnet ohne Light-Flash.
- [ ] **T2** Frame docken, dann via Tools→Options→IDE Style Light→Dark
      umschalten → Frame folgt **live**, Grid-Header neu eingefärbt.
- [ ] **T3** Float-Modus aktivieren → Titelzeile dark, Frame-Inhalt dark.
- [ ] **T4** Tools→Options offen, parallel IDE-Theme wechseln → Options-Page
      folgt live (war F4, heute kaputt).
- [ ] **T5** Annotation-Overlay erscheinen lassen, Theme wechseln,
      Overlay schließen, neu anzeigen → Title-BG = neu gemischte Akzent-
      Theme-Kombination.
- [ ] **T6** Line-Highlighter-Stripe → Stripe-Farbe vor/nach Theme-Wechsel
      identisch (Severity-Akzent fix), aber Editor-BG-Kontext neu.
- [ ] **T7** Plugin-Reload (Component→Install Packages→Uncheck/Check) →
      kein Notifier-Leak (TIDETheme-Singleton sauber unregistered).
- [ ] **T8** 3rd-party-Style ("Carbon", "Mountain Mist") → Frame-Chrome
      folgt, keine `clBtnFace`-Reste sichtbar.

---

## 6. Off-Limit / Bewusst nicht angefasst

- **Standalone-GUI**: hat keine IDE-ToolsAPI, kein Notifier nötig.
  `TIDETheme`-Singleton bleibt IDE-Only-Unit.
- **HTML-Export**: hat sein eigenes Theme (CSS), unabhängig.
- **CLI**: kein UI.
- **Editor-Stripe-Farben** (`uIDELineHighlighter.pas`): Severity-Akzente
  sind designt um auf jedem Editor-BG sichtbar zu sein — keine Theme-
  Empfindlichkeit, kein Refactor nötig.

---

## 7. Offene Fragen / Klärung beim User

- **Q1:** Soll der Singleton ein `TIDETheme = class` mit Klassen-Methoden
  sein, oder eine Unit-globale Procedure-Sammlung `procedure ApplyTheme(...)` +
  `procedure SubscribeTheme(...)`? Klassen-Lösung bietet bessere
  Auto-Complete-Discovery, prozedurale Lösung ist 30 Zeilen kürzer.
- **Q2:** Soll K8 (Options-Pages live-Subscribe) Priorität haben — oder
  reicht es, dass die Options-Page beim nächsten Open das frische Theme
  bekommt (heutiger Zustand)? Wenn nie jemand mid-options-page das Theme
  wechselt, K8 streichbar.
- **Q3:** K3 (ParentColor-Sweep) — soll der Sweep auch `Font.Color`
  einschließen oder nur Hintergrund?
