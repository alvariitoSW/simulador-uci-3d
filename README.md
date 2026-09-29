# Simulador UCI 3D

Evolución en 3D de [`simulador-UCI-`](https://github.com/alvariitoSW/simulador-UCI-)
(el simulador 2D hecho con Python/Pygame). La idea grande: un hospital/UCI
navegable en 3D donde cada escenario clínico se resuelve con un minijuego
inmersivo distinto, en vez de un panel de botones. Este repo empieza por
**un solo prototipo** para validar el concepto antes de construir el resto.

## Prototipo actual: Arsenal Farmacológico

Un minijuego de disparo en tercera persona (torreta fija, estilo "helicóptero
de guerra") donde **el arma equipada representa el antibiótico elegido**:

- Aciertas la cobertura correcta contra el microorganismo → arma potente y
  precisa (lo matas de un disparo).
- Fallas la cobertura → arma débil, apenas hace daño, y cada vez que un
  microorganismo "gana" por mal tratamiento, baja la estabilidad del paciente.

La lógica de qué antibiótico cubre a qué microorganismo no es arbitraria:
es una simplificación de la lógica real de tratamiento empírico del proyecto
hermano [`fiebres-neutropenias`](https://github.com/alvariitoSW/fiebres-neutropenias)
(protocolo SEIMC-SEHH 2020): monoterapia ahorradora de carbapenems para bajo
riesgo, carbapenem para BGN multirresistente, cobertura anti-Gram+ específica
cuando toca.

### Controles

- **Ratón**: apuntar (cámara tipo torreta).
- **Click izquierdo**: disparar.
- **1 / 2 / 3**: cambiar de antibiótico (arma).
- **ESC**: liberar el cursor del ratón.

## Requisitos

[Godot Engine 4.3](https://godotengine.org/download) (o superior dentro de la
serie 4.x). No hace falta instalar nada más: abre la carpeta del proyecto con
Godot y pulsa "Play".

## Estado y estilo visual

Prototipo funcional pero deliberadamente low-poly (formas geométricas básicas,
sin assets externos) para poder iterar rápido sobre la mecánica antes de
invertir en arte. Si el concepto funciona, el plan es evolucionar el estilo
visual hacia algo más realista y construir alrededor: un hub navegable con
varias salas/casos, y un minijuego distinto por escenario (compresiones de
RCP como ritmo, ajuste de ventilador como equilibrio, etc.), reutilizando el
contenido clínico ya validado en `simulador-UCI-`.

## Estructura del proyecto

```
project.godot            Configuracion del proyecto y autoload
scenes/
  main.tscn               Escena raiz (un Node3D con scripts/main.gd)
scripts/
  game_manager.gd          Autoload: puntuacion, arma actual, estabilidad del paciente,
                           datos de antibioticos/microorganismos
  main.gd                  Entorno 3D, camara, generacion de oleadas, disparo (raycast)
  target.gd                Un microorganismo objetivo (clase PathogenTarget)
  hud.gd                   Interfaz (clase GameHUD): puntuacion, arma, barra de estabilidad,
                           pantalla de resultados
```

Todo el árbol de nodos (mallas, colisiones, UI) se construye por código en
`_ready()`/`setup()` en vez de diseñarse a mano en el editor — así cada pieza
es fácil de ajustar por texto y de versionar en git.
