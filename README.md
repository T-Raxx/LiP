# LiP

Loader para **Life in Prison** (place `72659788689464`, v50).

## Cheat (loadstring directo)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/T-Raxx/LiP/main/LiP.lua"))()
```

> El bundle pesa ~3.9 MB → el `HttpGet` tarda unos segundos en bajar/compilar. Es normal.

## Calibrador de firerate (correr SOLO, sin el cheat)

Observador puro: mide el firerate real por arma de tus disparos y lo guarda a `LiP_firerates.json`. El autofire del cheat lee ese archivo. HUD interactivo (Drawing API): lista de armas, botones Save/Reset, click-fila=reset, drag, `INSERT` oculta.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/T-Raxx/LiP/main/Calibrator.lua"))()
```

**Uso:** corré el calibrador solo, sostené M1 (dispará) con cada arma un rato (full-auto = mantené apretado; semi = clickeá rápido). Cuando junte data, `getgenv().__LIP_CAL_STOP()`. Después rejoineá y cargá el cheat.

## Notas v50

- **AutoFire** dispara al firerate exacto por arma (del archivo del calibrador) → nunca excede = AC-safe (checks `rps`/`nc`). Sin calibrar = 2/s seguro.
- **Reload** simula la tecla `R` = el reload real del juego (sin unequip).
- No spamees fuera de esos límites (Timer / rapidfire manual = riesgo de ban).
