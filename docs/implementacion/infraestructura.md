# Infraestructura del proyecto

Estado de lo que ya está montado, para no volver a averiguarlo. Todo lo de esta página está
verificado en funcionamiento salvo donde se dice lo contrario.

## Repositorio

| | |
|---|---|
| Remoto | `https://github.com/vladimir1284/lamula-drx` (**privado**) |
| Rama principal | `main` |
| Ruta local de trabajo | `/home/node/workspace/lamula-drx` |
| Origen | Escindido del repositorio `lamula-dsp`, que era un repositorio de planificación de los tres proyectos LAMULA |

Los commits llevan `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` cuando los
escribe un agente.

## Sitio de documentación

`docs/` se construye con **mkdocs-material 9.x** y se despliega a **Cloudflare Pages** en cada push
a `main` que toque `docs/**`, `mkdocs.yml` o el propio workflow.

| | |
|---|---|
| Workflow | `.github/workflows/docs.yml` |
| Proyecto Pages | `lamula-drx-docs` (rama de producción `main`) |
| URL | <https://lamula-drx-docs.pages.dev> |
| Secrets | `CLOUDFLARE_API_TOKEN` y `CLOUDFLARE_ACCOUNT_ID`, **a nivel de repositorio** |

Los secrets van por repositorio y no por organización porque `vladimir1284` es una cuenta de usuario
de GitHub, no una Organization, y GitHub solo ofrece secrets compartidos de Actions a las
Organizations. Se poblaron reusando las credenciales de Cloudflare de `lamula-process`, que apuntan a
la misma cuenta.

!!! warning "Deuda conocida del scaffold de CI"
    Dos avisos no bloqueantes en cada run, heredados de la plantilla:

    - `actions/checkout@v4`, `astral-sh/setup-uv@v5` y `cloudflare/wrangler-action@v3` apuntan a
      Node.js 20, que está deprecado en los runners y se fuerza a Node.js 24.
    - `setup-uv` no encuentra `uv.lock` ni `requirements*.txt`, así que su caché nunca se invalida —
      y tampoco sirve de nada, porque la build usa `uvx` con la versión fijada en la línea de
      comandos.

    Ninguno rompe la build. Si algún día se toca el workflow, arreglar los dos de paso.

### Construir el sitio localmente

```sh
cd /home/node/workspace/lamula-drx
uvx --with 'mkdocs-material==9.*' mkdocs serve     # servidor con recarga
uvx --with 'mkdocs-material==9.*' mkdocs build --strict   # lo que corre el CI
```

**`--strict` tiene que pasar limpio antes de commitear.** El CI lo ejecuta con `--strict`, así que un
enlace roto o un ancla inexistente tumba el deploy.

## Convenciones de la documentación

- **Anclas explícitas.** Los títulos que se enlazan desde otras páginas llevan un ancla explícita —
  `## D-04 · … { #d-04 }`, `## Z0 — … { #z0 }`, `### P-01 · … { #p-01 }` — habilitada por la
  extensión `attr_list`. Los slugs automáticos de mkdocs sobre títulos en español con guiones
  largos, paréntesis y subíndices son frágiles y se rompen al reescribir un título. **Al añadir un
  título enlazable, ponerle ancla explícita.**
- **Los documentos de `docs/referencia/` van verbatim.** Se conservan sin editar, con una nota de
  admonición al principio que dice que las páginas derivadas mandan sobre ellos. Si una decisión
  cambia, se actualiza la página derivada, **nunca** el documento de referencia.
- **`research/` está fuera de `docs_dir`** y no se publica. Contiene briefs de investigación para
  hallazgos que se cierran con evidencia externa al repositorio; las conclusiones graduan a `docs/`.
  Ver `research/README.md`.
- Los enlaces desde `docs/` hacia `research/` se escriben como ruta en `code span`, no como enlace
  markdown: un enlace a un fichero fuera de `docs_dir` rompe `--strict`.

## Repositorios hermanos en este workspace

| Ruta | Qué es | Por qué te va a hacer falta |
|---|---|---|
| `/home/node/workspace/lamula-dsp` | Repositorio de planificación de los tres proyectos LAMULA, con su propio sitio de docs | Contiene `docs/algorithms/` (pulse-pair, GMAP, dual-PRF, SZ, calibración de reflectividad) y los planes de DSP y RCP |
| `/home/node/workspace/lamula-rcp` | Radar Control Processor y MMI, en Python | **`spike-fase0/` tiene trabajo real sobre la interfaz RDA↔ORPG**: `rda_orpg_handshake_spike.py`, `README-rda-orpg.md` y `RESULTADO-rda-orpg.md`. Es el punto de partida de la investigación P-01 |
| `/home/node/workspace/nexrad-l3-pipeline` | Pipeline de productos Level-III | Referencia de formatos NEXRAD |
| `/home/node/workspace/radar_emulator` | Emulador de radar configurable | El RCP lo usa como HAL simulado |

!!! note "URL derivada, sin verificar"
    Los enlaces de `docs/referencia/project-plan-zu9.md` hacia las páginas de algoritmos apuntan a
    `https://lamula-dsp-docs.pages.dev/algorithms/…`. Ese dominio se **derivó** del nombre del
    proyecto Pages declarado en `lamula-dsp/.github/workflows/docs.yml`; no se comprobó que resuelva
    ni que el sitio DSP no tenga un dominio propio. Verificarlo y corregirlo si hace falta.
