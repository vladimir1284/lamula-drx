# Resultado — P-01, barrido del resto del árbol de ORPG

**Brief de origen:** [`p-01-barrido-cpc0xx.md`](p-01-barrido-cpc0xx.md).
**Complementa:** [`p-01-RESULTADO.md`](p-01-RESULTADO.md).
**Fecha:** 30 de agosto de 2026.

## Procedencia

Mismo árbol `rpg_b24_0r1_20_pub_src` (paquete CODE del ROC, build 24), en la máquina que lo tiene
montado. Sin compilar ni ejecutar nada. Cobertura: greps dirigidos sobre todo `src/` más lectura de
contexto en cada hit no trivial — **no** lectura línea a línea de los ~35 `cpc0xx`.

Igual que el resultado anterior, **las citas no son reverificables desde la máquina de
desarrollo**. La diferencia importante: la Tarea 0 de este barrido reverificó las cuatro citas
decisivas del resultado anterior y **las cuatro coinciden, mismos números de línea**. Eso sube la
confianza en toda la cadena, aunque no sustituya a tener el árbol a mano.

---

## Tarea 0 — las cuatro citas decisivas: coinciden

`include/generic_basedata.h:198-204`, `include/basedata.h:1010-1020`,
`src/cpc102/tsk033/pbd.c:2925-2942` y `src/cpc102/tsk033/pbd.c:3115-3130` dicen exactamente lo que
afirmaba `p-01-RESULTADO.md`, sin desplazamiento de líneas. **Sin cuarentena.**

## Tarea 1 — veredicto binario: sí aparece, en tres subsistemas independientes

Y el hallazgo es **más duro** de lo que se buscaba. El brief pedía encontrar re-derivaciones
cableadas de rango, que degradan el dato en silencio. Lo que apareció son **listas blancas de
espaciado que descartan el dato entero**.

### 1. Recombinación azimutal de super-res — `src/cpc004/tsk009/combine_radials.c:427-431`

```c
if (bh1->surv_bin_size != bh2->surv_bin_size ||
    (bh1->n_dop_bins > 0 && bh1->dop_bin_size != 250) ||
    (bh2->n_dop_bins > 0 && bh2->dop_bin_size != 250) ||
    (bh1->surv_bin_size != 250 && bh1->surv_bin_size != 1000)) {
    LE_send_msg (GL_INFO, "Unexpected bin size - discard two radials");
    return (bh2->status);
}
```

Reflectividad admite `{250, 1000}` y nada más; **Doppler admite solo 250**, sin siquiera fallback a
1000. Cualquier otro entero —249, 208, 416— descarta la recombinación del split-cut. El aviso es
`GL_INFO`, no `GL_ERROR`: se pierde en el log.

Refuerzos del mismo patrón: `combine_radials.c:193` (`Azi_only || surv_bin_size != 250` corta la
recombinación de radial único, con un mensaje engañoso que dice «not super res» cuando lo que pasa
es que no cuadra con 250 exacto), `:497` y `:713` (el camino legado exige el literal 1000), `:422`
(`R0 = .001f * (bh1->range_beg_dop + 125.f)`, la mitad de 250 cableada).

### 2. Validación de moments dual-pol — `src/cpc023/tsk002/qia_process.c:707` y `src/cpc004/tsk011/dpp_format.c:547`

Dos copias casi idénticas de `Verify_gm_hd()`:

```c
if ( gm->bin_size != 250 ||
    (gm->data_word_size != 8 && gm->data_word_size != 16)) {
    LE_send_msg (GL_ERROR, "Header of field %s inconsistent ...", ...);
    return (-1);
}
```

Se aplica a todos los moments dual-pol (ZDR, PHI, RHO, KDP, SNR). Aquí no hay fallback: dual-pol
solo existe en alta resolución, así que **el único valor aceptado es 250 exacto**, y lo que no
cuadra se rechaza con `GL_ERROR`. Esto contesta la pregunta de lista blanca del brief: sí existe, y
para dual-pol es de valor único.

### 3. Re-derivación literal en el producto de capa de fusión — `src/cpc024/tsk008/armlprod.c:366-370`

```c
for (bin = 0; bin < Arml.num_bins; bin ++){
    RPGCS_height((bin*250.), elang, &bin_height[bin]);
}
```

Es el patrón `range = i * 250` que el brief pedía buscar, sin ningún chequeo de `bin_size` en la
propia función. **Contexto, no exculpación:** ARML consume moments dual-pol, que ya pasaron por
`Verify_gm_hd()`, así que en el diseño actual no debería recibir datos no-250 — la consecuencia
práctica de un espaciado distinto no es «altura mal calculada» sino «ARML no recibe nada». Pero el
patrón existe, y si el chequeo de aguas arriba cambia sin tocar este, el error pasa entero.

Misma familia, con `HALF_BIN_SIZE = 0.125` incluso como `#define` en cabecera:
`src/cpc017/tsk004/mda2d_acl.c:53`, `src/cpc017/tsk004/mda2d_set_table.c:38`,
`src/cpc017/tsk010/mda3d_msi.c:36`, `src/cpc017/tsk010/mda3d_set_table.c:40`. Mismo razonamiento, y
tampoco verificado de forma independiente.

### 4. Señalado, sin cerrar — recombinación SZ2 y clutter

`include/recclalg_arrays.h:18-19` fija `MAX_DOP_BIN = 4`, una razón 4:1 cableada entre bin de
reflectividad (asumido 1 km) y bin Doppler (asumido 250 m), usada para dimensionar
`MAX_QTRKMBINS`. `src/cpc004/tsk006/recclalg_main.c:244` solo comprueba `dop_bin_size != 0`, no
`== 250`. No se cerró si hay chequeo de valor exacto en otro punto antes de indexar con esa razón.
**Es la pieza de menor confianza del barrido.**

### Hallazgo lateral — dos copias de la cadena `pbd`

El árbol tiene `src/cpc102/tsk033/pbd*.c` (la revisada) y `src/cpc004/tsk002/pbd*.c`, una variante
de build más antigua con la misma estructura `Bintbl[460]` / `Bintbl_sr[1840]` seleccionada por
`surv_bin_size == 250` (`cpc004/tsk002/pbd.h:483-484`, `pbd.c:5439`,
`pbd_process_header.c:969`). Todas las conclusiones aplican a las dos copias. **No se sabe cuál
corre en el ORPG de destino** — depende del build instalado. Preguntar.

## Tarea 2 — lectura fuera de arreglo: confirmada por lógica, con dos condiciones

**¿Puede `n_surv_bins` superar 460 con `surv_bin_size != 250`?** Sí. El clip de
`pbd_process_header.c:2149-2156` decide el tope según el propio `n_surv_bins`, no según el
espaciado:

```c
if( rpg_hd->n_surv_bins <= BASEDATA_REF_SIZE )      /* <=460: tope 460 */
    ...
else if( max_surv_bins > MAX_BASEDATA_REF_SIZE )    /* >460: tope 1840, NO 460 */
    max_surv_bins = MAX_BASEDATA_REF_SIZE;
```

Un radial de alta resolución que declare 249 con más de 460 gates conserva un `n_surv_bins` de
hasta 1840, y en `pbd.c:2570-2584` selecciona `Bintbl[460]` porque no es 250, iterando hasta 1840.

**¿Corre AVSET con esos datos?** `AVSET_compute_area()` (`pbd.c:2537-2560`) sale temprano solo por
`!Avset_enabled`, `target_elev < 50` (elevaciones bajo 5,0°) y `n_surv_bins == 0`. Ninguna guarda
bloquea alta resolución con espaciado no-250.

El hallazgo sube de «plausible» a **confirmado por lógica de código**, condicionado a
`Avset_enabled` y a que la VCP use resolución no-250 en tilts ≥5°. Ninguna de las dos es código:
son adaptación de sitio y VCP, no verificables desde el árbol.

**Salvedad que este barrido no resolvió:** los hallazgos 1 y 2 pueden ser mutuamente excluyentes
según el orden del pipeline. Si `combine_radials.c` descarta el radial antes de que llegue a la
ruta AVSET de `pbd`, la lectura fuera de límites es inalcanzable en la práctica y el modo de fallo
real es «el dato desaparece», no «el dato corrompe memoria». No se rastreó ese orden. **No cambia
la recomendación** —los dos caminos exigen declarar 250— pero sí cambia qué se puede afirmar sobre
el modo de fallo.

## Tarea 3 — las dos preguntas baratas, contestadas

**Lista blanca:** sí, existe. `Verify_gm_hd()` exige 250 exacto para dual-pol;
`combine_radials.c:430` exige `{250, 1000}` para reflectividad y 250 para Doppler.

**Tope Doppler:** `BASEDATA_RHO_SIZE = 1200` (`include/basedata.h:1017`) son 300 km a 250 m. El
barrido dejó abierto si LAMULA cabe, por no tener el número de gates de velocidad. **Está en este
repositorio:** `docs/referencia/project-plan-zu9.md:47` da «Doppler default 150 km, extendable to
230 km», o sea 600 gates por defecto y 920 en el extendido, contra un tope de 1200. **Cabe con
margen; la pregunta queda cerrada.** Lo que sí impone el hallazgo 1 es que el modo Doppler tiene
que declarar 250 igual que reflectividad — no puede usar otra cadena de diezmado.

---

## Consecuencia para D-04

**Refuerza la Opción B, y cambia la naturaleza del argumento.** Antes se sostenía que declarar 249
metía el dato en una ruta con la corrección de rango mal escalada: degradación silenciosa. Ahora se
sabe que declarar 249 hace que el dato **se descarte**: pierde la recombinación azimutal de
super-res y todos los moments dual-pol. No es un error del 0,24 %, es no tener producto.

Dicho de otra forma: **ORPG no tiene tolerancia al tamaño de celda. Tiene una lista blanca.** La
pregunta original de P-01 —«¿tolera ORPG un error del 0,24 %?»— resulta estar mal planteada de una
forma que el brief solo intuía: no hay una banda de tolerancia que medir, hay dos valores legales.

R₂ = 417 declara 250 y entra en la lista. R₂ = 416 declara 249 y no.

**Salvo que se mueva `fs`.** Los convertidores son de 250 MSPS pero no hay obligación de operarlos
a esa frecuencia: con `fs` = 143,9 MHz, R₁ = 120 y R₂ = 240 dan celdas de 125,00033 m y 250,00066 m
—1,2 m de error acumulado a 460 km, el 0,5 % de una celda—, la cadena única con etapa ÷2 se
conserva y el reloj sale por integer-N desde la referencia de 10 MHz. Eso disuelve P-01 en vez de
sortearlo. Ver [P-08](../docs/alcance/pendientes.md#p-08).

## Consecuencia más amplia, que no estaba en ningún documento

Si ORPG valida el espaciado contra una lista cerrada, es razonable esperar que valide **el resto de
la geometría igual**: conteo de gates, rango al primer gate, resolución azimutal, tamaño de palabra
de dato (`data_word_size` ya aparece en el mismo `if` de `Verify_gm_hd()`, admitiendo solo 8 ó 16).
El requisito para LAMULA no es «acercarse a 250 m», es **declarar valores legales de NEXRAD en
todos los campos de geometría**. Eso excede P-01 y **no es un pendiente del DRx**: el DRx no habla con ORPG, y el DSP tampoco
(`lamula-dsp/docs/dsp-plan.md:71`). Vive en el proyecto que posee la emulación RDA, como
`PEND-RCP-12` en `lamula-rcp/docs/alcance/pendientes.md`; en este repositorio queda solo el puntero
en [P-07](../docs/alcance/pendientes.md#p-07).

## Qué sigue sin revisar

- Los subdirectorios `cpc0xx` donde los greps no dieron hits: composición geográfica y mosaico
  entre radares, VAD/VWP, y el remuestreo final a rejilla Level-III de 1 km / 0,25 km. El brief los
  marcaba como el daño potencial número uno. **Ausencia de hits no es ausencia de código**: puede
  que ese remuestreo use nombres de campo distintos a los buscados.
- El subsistema SZ2 y clutter (`cpc004/tsk006`, `cpc005/tsk003`, `cpc005/tsk004`).
- El orden del pipeline entre `combine_radials` y la ruta AVSET de `pbd`.
- Cuál de las dos copias de `pbd` corre en el ORPG de destino.
- `Avset_enabled` y la asignación de resolución por tilt en la VCP real — adaptación de sitio, no
  código.
- `RDA_Backend_Py` — sigue sin localizar. Ver [P-05](../docs/alcance/pendientes.md#p-05).
