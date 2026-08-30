# research/

Briefs de investigación y sus resultados, para hallazgos abiertos que se cierran con evidencia
externa al repositorio — código legacy, fuentes de terceros, especificaciones de interfaz.

No es documentación de producto: `research/` no se publica en el sitio mkdocs. Cuando una
investigación concluye, su **conclusión** pasa a `docs/` (una decisión en
`docs/alcance/decisiones.md`, o el cierre del pendiente correspondiente en
`docs/alcance/pendientes.md`) y el brief queda aquí como rastro de cómo se llegó a ella.

Convención de nombres: `<id-del-pendiente>-<tema>.md` para el brief, y
`<id-del-pendiente>-RESULTADO.md` para lo que devuelva la investigación.

| Brief | Pendiente | Estado |
|---|---|---|
| [p-01-orpg-gate-spacing.md](p-01-orpg-gate-spacing.md) | P-01 — tolerancia del tamaño de celda | Ejecutado en parte sobre el árbol de ORPG build 24; resultado en [p-01-RESULTADO.md](p-01-RESULTADO.md). Sigue abierto: citas no reverificables en esta máquina, cobertura de un solo subdirectorio, y `RDA_Backend_Py` (P-05) aún sin localizar |
| [p-01-barrido-cpc0xx.md](p-01-barrido-cpc0xx.md) | P-01 — barrido del resto del árbol de ORPG | Listo para ejecutar en la máquina que tiene montado `rpg_b24_0r1_20_pub_src`. Es lo único pendiente que puede tumbar la recomendación de R₂ = 417 |
