# d4rk_prop_tool

Gegenstände (Props) an einen Knochen des Spielers hängen, im Spiel ausrichten
und die Werte übernehmen: zwei Plätze, 21 Knochen, Verschieben und Drehen per
Maus und Numpad, Drehreihenfolge wählbar, Animation dazu abspielen.

Ursprünglich ein eigenständiges Entwicklerwerkzeug (v2.1.0). Seit dem
29.09.2026 auf dem d4rk-RP-Server und an den **Animationskatalog**
(`d4rk_animation`) angebunden.

## Benutzen

| Weg | was passiert |
|---|---|
| `/ptool` | das Tool öffnen (leer) |
| Adminpanel → Dev → „Prop-Tool" | dasselbe, ohne zu tippen |
| Animationsmenü → Eintrag → **„Im Prop-Tool einstellen"** | öffnet das Tool **mit dem Katalogeintrag**: Animation läuft, beide Plätze tragen die Katalogwerte, oben steht „Katalog: …" |
| `/propeinstellen <key>` (aus `d4rk_animation`) | wie der Menüknopf |

Mit einem Katalogeintrag geöffnet, schreibt **„In Katalog übernehmen"** beide
Plätze über `exports.d4rk_animation:PropSetzen` zurück. Wirksam ab dem
nächsten Abspielen.

## Rechte

| Recht | wofür |
|---|---|
| `d4rk_prop_tool.use` | das Tool öffnen, Presets speichern, exportieren. Bei `d4rk_perms` angemeldet, Bereich **animationen** |
| `d4rk_animation.admin` | in den Katalog schreiben — prüft `d4rk_animation` selbst |

Geprüft wird über `DarfAkteur` aus `d4rk_lib` (`@d4rk_lib/server/akteur_shared.lua`),
nicht über ein nacktes `IsPlayerAceAllowed`: das liefert auf diesem Server `1`
statt `true`, und der Client vergleicht mit `== true` — so meldete das Tool
„Kein Zugriff" trotz Recht.

## Abhängigkeiten

- `ox_lib`
- `d4rk_lib` (nur die Rechtefrage, eingebunden als Datei)
- `d4rk_animation` — optional; ohne sie gibt es keinen Katalog, das Tool läuft
  trotzdem
- `d4rk_admin` — optional; ohne es fehlt nur der Eintrag im Dev-Reiter

In der `server.cfg` **nach** `d4rk_animation`.

## Exporte und Callbacks

| | |
|---|---|
| `exports.d4rk_prop_tool:KatalogOeffnen(eintrag)` (Client) | `{ key, label, dict, clip, flag, plaetze = { [1] = {model, boneId, rotOrder, offset, rotation}, [2] = … } }` |
| `d4rk_prop_tool:katalogSpeichern` (lib.callback) | prüft `d4rk_prop_tool.use` und eine Bremse, reicht an `PropSetzen` weiter |

## Config

| Schlüssel | Wert |
|---|---|
| `Command` | `ptool` |
| `RequireAce` | `true` — **nicht abschalten**: die Callbacks schreiben Dateien auf den Server |
| `AcePermission` | `d4rk_prop_tool.use` |
| `DefaultMoveSpeed`, `DefaultRotateSpeed` | Schrittweiten beim Start |

## Bekannt und hingenommen

- Die NUI ist Vanilla-HTML/JS, nicht der Projekt-Stack (ADR-0013) — ein
  Entwicklerwerkzeug, nicht umgebaut.
- Meldungen laufen über `lib.notify` im ox-Design, nicht über das
  d4rk-Meldungsdesign.
- **Zwei Fäden laufen auch im Leerlauf** (`client/main.lua`): die
  Kamera-Nachführung prüft alle 250 ms, ob die UI offen ist, die
  Tastensteuerung alle 150 ms, ob eine Taste gehalten wird. Klein, aber nicht
  die 0,00 ms, die das Projekt verlangt. Sauber wäre: beide Fäden erst beim
  Öffnen bzw. beim ersten Tastendruck starten und danach enden lassen.
  **Nicht gemessen** (`resmon`) — offen.
