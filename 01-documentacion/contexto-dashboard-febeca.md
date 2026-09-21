# Dashboard de Compras · Febeca — Documento de contexto

> Para retomar el proyecto en una conversación nueva. Contiene el encargo, la estructura
> real de los datos, los hallazgos del análisis, la arquitectura de base de datos y el
> modelo de permisos.
> Última actualización: 14 de septiembre de 2026.

---

## 1. El encargo

**Febeca** es una distribuidora mayorista de artículos de ferretería. Su cliente objetivo son
ferreterías. Opera en Venezuela, Colombia, Costa Rica y Panamá.

El proyecto es para el **departamento de compras**. Cada comprador lleva una cartera de marcas
(nacionales e internacionales) y semanalmente debe presentarle a gerencia cómo van sus marcas,
según parámetros que la gerencia exige.

**El problema:** toda esa información sale del **SIM**, un sistema de reportería lento e incómodo.
Armar la presentación semanal consume muchísimo tiempo del comprador.

**La solución pedida:** un dashboard que reemplace ese trabajo manual y que además calcule cosas
que el SIM no da (pronósticos, pedidos sugeridos, rankings).

La marca usada como piloto es **PCP** (plomería: llaves, canillas, uniones PVC, aspersores).

---

## 2. Qué pidieron los compradores

Jose entrevistó a los compradores. Lo que más les interesa:

| # | Requerimiento | Origen |
|---|---|---|
| 1 | Venta en dólares | SIM |
| 2 | Venta en unidades | SIM |
| 3 | Venta en toneladas | SIM |
| 4 | Margen de ganancia | SIM |
| 5 | Inventario | SIM |
| 6 | Tránsito (OC por recibir) | SIM |
| 7 | Pronóstico de ventas | calculado |
| 8 | Promedio de ventas | calculado |
| 9 | Alcance de la demanda mensual | calculado |
| 10 | Alcance del presupuesto y cómo va | SIM + calculado |
| 11 | Rotación | SIM |
| 12 | Contribución | SIM |
| 13 | Artículos, venta por artículo y su movimiento | SIM |
| 14 | Top de venta por artículo | calculado |
| 15 | Vista por estado y región | SIM |
| 16 | Top de clientes que más compran | SIM |
| 17 | Top de vendedores que más venden | SIM |
| 18 | Clientes activos vs. inactivos | SIM |
| 19 | SKU de inventario y SKU activados | SIM (parcial) |
| 20 | GM ROI | SIM |
| 21 | Tiempo estimado de llegada de mercancía | SIM (OC por mes) |
| 22 | **Botón para incluir/excluir al cliente EPA** | calculado |
| 23 | Pedidos sugeridos en función de las ventas | calculado |

**Sobre el punto 22:** EPA (Ferretería EPA) compra muchísimo y distorsiona todos los rankings.
Piden poder quitarlo y ponerlo con un botón.

---

## 3. Las descargas del SIM

### Regla fundamental

El SIM arma **el producto cartesiano de todas las dimensiones que pidas**, existan o no las
combinaciones. Pedir `Estado › Vendedor` genera 64 × 739 = 47.296 filas, de las cuales ~1.500
tienen datos. El resto son filas vacías que consumen el cupo de exportación y provocan el aviso
*"Exported data exceeded the allowed volume"*.

> **Las dimensiones grandes van solas.** Vendedor (739) y Cliente (33.000) son grandes.
> Estado (64), Región (19), Supervisor (50) y Categoría (5) son chicas y pueden ir juntas.

El cupo parece estar alrededor de **1 a 2 millones de celdas** (filas × columnas). Como cada mes
genera una columna por indicador, hay que controlar **ambos extremos del rango de fechas**: si
dejas la fecha final abierta, el SIM trae meses futuros de presupuesto hasta 2028 y revienta.

### Las descargas definitivas

| # | `Parameter` | Máscara | Meses | Notas |
|---|---|---|---|---|
| 1 | Marca, Categoría, Artículo | Miles de dólares | 48 | Corazón del sistema |
| 2 | Marca, Artículo | Unidad | 48 | Sin esto no hay pedido sugerido |
| 3 | Marca, Artículo | Toneladas | 1 basta | Solo para el factor kg/unidad |
| 4 | Marca, Artículo | — | mes actual | Indicador `OC por recibir` |
| 5 | Marca, Estado, Supervisor, Región | Miles de dólares | 48 | No se trunca, las 3 dims son chicas |
| 6 | Marca, Vendedor | Miles de dólares | 48 | **Plano, sin Estado** |
| 7 | Marca, Cliente | Miles de dólares | 12 | **Plano, sin Estado, con fecha de fin** |
| 8 | Marca, Artículo, filtrado a EPA | Miles de dólares | 48 | Para el botón de EPA |
| 9 | Marca, Artículo, filtrado a EPA | Unidad | 48 | Idem, en unidades |

M�s el **infocompras** (archivo `MARCAS_FEBECA_MASTER`), que Febeca ya mantiene aparte.

### Indicadores a pedir

`Venta Neta`, `Venta Bruta`, `Contribución`, `Margen`, `Inventario`, `Rotación`,
`Clientes activados`, `Clientes Inactivos`, `SKU activados`, `GM ROI`,
`Presupuesto bruto`, `Presupuesto neto`, `Presupuesto de contribución`.

**No pedir** (son derivados, el dashboard los recalcula y solo inflan el archivo):
`Devolución %`, `Clientes activados %`, `SKU activados %`, `Dif. Margen`, `Dif. Contribución`,
`Presupuesto de inventario`, `Artículos`.

**`SKU de inventario` no existe en el SIM.** Se obtiene contando los artículos con `DISP > 0`
en el infocompras.

### Frecuencia

La historia de 48 meses se baja **una sola vez**. Cada semana el comprador baja únicamente el
**mes corriente**, que son archivos de ~20 KB, y el dashboard los fusiona con lo ya guardado.

---

## 4. Estructura de los archivos del SIM

Cada exportación es una hoja llamada `Export` con formato de tabla cruzada:

```
Fila 0:  Mes  | (vacío) | (vacío) | 8-2023 | 8-2023 | 8-2023 | 9-2023 | ...
Fila 1:  Categoría | Articulo | Marca | Contribución | Inventario | Venta Neta | ...
Fila 2+: datos, con filas "Total" intercaladas en cada nivel
Al pie:  bloque "Filtros aplicados" con marca, máscara, Parameter y rango de fechas
```

- Las **columnas de dimensión** son las que están antes de la primera columna con mes.
- El **bloque de filtros al pie** permite autodetectar qué es cada archivo (`Parameter`,
  `Mascara`, `U_MARCA`, `RazonSocial`). *Algunas exportaciones no lo traen* — el parser necesita
  un plan B por estructura de encabezado.

### Trampas confirmadas del parser

1. **Filas "Total" intercaladas.** Hay subtotales en cada nivel de la jerarquía. La regla correcta
   es: **ninguna columna de dimensión puede valer "Total"**. Verificar solo la última dimensión
   infla los totales (estados salían ×3 y supervisores ×2).

2. **Escalas mezcladas.** La máscara dice "Miles de dólares", pero **`Presupuesto bruto` viene en
   dólares absolutos** (141.751,03 contra Venta Neta 145,696). Hay que dividirlo entre 1.000.
   `Presupuesto de contribución` sí viene en miles.
   → En la base de datos esto se resuelve con `indicadores.factor_escala`: **todo se normaliza a
   dólares en la ingesta**, para que nunca haya ambigüedad de escala al consultar.

3. **Métricas no aditivas repetidas.** `Inventario`, `Rotación` y `Artículos` aparecen idénticos
   en todas las filas de los cortes por vendedor o cliente: son valores de marca, no del vendedor.
   Los ratios (`Margen`, `GM ROI`, todos los `%`) se recalculan, nunca se suman —
   **y recalcularlos es la única forma de que sigan siendo correctos al excluir EPA.**
   → En la base se declara con `indicadores.agregacion` (`suma` / `ultimo` / `ratio` / `conteo`).

4. **Meses futuros sin venta.** El archivo trae oct/nov/dic 2026 solo con presupuesto. Los meses
   válidos son los que tienen `Venta Neta`, no los que aparecen en el encabezado.

5. **El último mes con venta va incompleto.** Todo cálculo de promedio, pronóstico y cobertura se
   hace contra **meses cerrados**. El mes corriente se muestra aparte, proyectado por días hábiles.
   (Sin esto, 26 de 73 artículos mostraban "cobertura de −295 meses".)
   → En la base es la tabla `periodos (marca_id, periodo, cerrado, corte_al)`.

6. **Tablas pegadas al lado.** Si alguien pega manualmente la OC en las columnas 435+, el parser
   debe cortar el bloque de meses al primer hueco. Mejor: no pegar nada a mano.

7. **EPA por coincidencia exacta, nunca por texto contenido.** Buscar "EPA" atrapa 22 clientes
   falsos (FERREPACA, FERREPAPEL, AREPA HOUSE, DEPARCA...). Los nombres reales son:
   `FERRETERIA EPA, C.A.` (el que tiene datos), `FERRETERIA EPA S.A`, `FERRETERIA EPA, S.A.`
   → En la base está generalizado: `entidades.excluir_de_analisis`. Nunca hardcodear EPA.

8. **Códigos de artículo.** El SIM entrega `"22-13-007 Canilla plástica 1/2 x 1/2\" 40 cm PCP"`.
   El código es el primer token. Cruza limpio con `CODIGO SOFTLAND` del infocompras.

---

## 5. El infocompras

Archivo `MARCAS_FEBECA_MASTER__11-09-2026_.xlsx` que Febeca ya mantiene. Una hoja por marca
(PCP, BOSCH, DAEWOO, EMTOP, PEDROLLO, RCA, EAGLE, GLADIATOR, ITALGRIF, AQUA NUOVA, TEZZA...),
con el encabezado en la fila 3.

Aporta lo que al SIM le falta:

- **`DISP`** — stock disponible **en unidades** (el SIM solo da inventario en dólares)
- **`TRANSITO`** — en camino, en unidades
- **`Costo`, `PV`, `Margen`, `Mejor precio`, `MARGEN FINAL`** — por artículo
- **`ULT_COM`** — fecha de última compra; con su histórico se deduce la frecuencia de pedido
- **`SUB CATEGORIAS`** — el SIM solo tiene 7 categorías
- **`REF PROVEEDOR`**, **`BDF`** (activo/descontinuado)
- 6 meses de venta en unidades

Otras hojas útiles: **`PRESUPUESTO`** (12 meses por marca) y **`DATA MODAyMEDIANA`** (5.485 filas
con mediana y moda de cantidad por artículo — sirve para redondear el pedido sugerido a
cantidades que de verdad se venden).

En PCP cruzan **80 de 80** artículos del infocompras con el SIM.

> En la base esto va a `inventario_snapshot`, con fecha de toma. No es mensual: es una foto del
> momento en que se bajó el archivo, y se guarda con fecha para poder reconstruir por qué se
> sugirió un pedido determinado.

---

## 6. Reglas de negocio

### Lead time y cobertura

- PCP se compra **mensualmente** y la mercancía llega **a los 45 días**.
- Cobertura objetivo = **1,5 meses de tránsito + 1 mes de ciclo + 0,5 de seguridad = 3 meses**.
- Estos parámetros **varían por marca** y viven en `parametros_marca`, versionados por
  `vigente_desde`: cambiar el lead time no debe reescribir la historia de los pedidos ya
  calculados.

### Pedido sugerido

```
sugerido = max(0, demanda_pronosticada × cobertura_objetivo − stock − tránsito)
```

Demanda en **unidades**, no en dólares. Se calcula **sin EPA**.

### Pronóstico adaptado a la historia disponible

Cada marca tiene distinta profundidad de historia (algunas llevan 3 meses en Febeca). El motor
elige método solo y **siempre declara cuál usó y con cuántos meses**:

| Historia | Método |
|---|---|
| 24 meses o más | Holt-Winters aditivo, estacionalidad 12 |
| 12 a 23 meses | Tendencia + índice estacional de la categoría |
| 3 a 11 meses | Promedio móvil ponderado, sin estacionalidad |
| Menos de 3 meses | No pronostica. Muestra "historia insuficiente" |

Los pronósticos se persisten en la tabla `pronosticos` con su método, su RMSE y su horizonte en
JSON, para poder auditar qué se proyectó y no recalcular Holt-Winters en cada carga de página.

### Toneladas

Solo hay un mes de data en toneladas, y **no es problema**: el peso por unidad es una constante
física. En PCP: 210 t ÷ 87.863 u = **2,39 kg por unidad**. Con ese factor se calcula el peso de
cualquier pedido. Lo único imposible es graficar toneladas en el tiempo.

*(Pendiente de verificar: 2,39 kg para un artículo promedio de $1,66 parece alto.)*

---

## 7. Hallazgos importantes sobre PCP

### EPA distorsiona el pronóstico, no solo los rankings

EPA pesa **19,7%** de la marca en agosto ($28.716 de $145.696). Pero lo grave es el patrón:

| oct-25 | nov-25 | dic-25 | ene-26 | feb-26 | mar-26 | abr-26 | may-26 | jun-26 | jul-26 | ago-26 |
|---|---|---|---|---|---|---|---|---|---|---|
| 5,5 | **50,5** | 0 | 23,9 | 24,1 | 0 | 0 | 10,5 | **45,0** | 28,8 | 28,7 |

Compra a saltos: tres meses en cero y después $50.000 de golpe. El modelo lee esos picos como
estacionalidad y proyecta demanda inexistente. Por eso **el pronóstico y el pedido sugerido se
calculan sin EPA por defecto**.

### La venta de PCP no está asignada a vendedor

Desde 2025 toda la venta aparece bajo **`NO CLASIFICADO`** ($157,65K en agosto). Antes de 2025 el
SIM repetía el total de la marca idéntico en los 739 vendedores.

**Consecuencia:** el ranking de vendedores no funciona para PCP. Se usa **supervisores**, que sí
tiene datos reales y suma exacto.

### Los clientes tienen un estado; los vendedores, varios

- Cada cliente pertenece a **un solo estado** (179 de 179 verificados).
- **597 de 739 vendedores** venden en más de un estado.

### Cifras de referencia (agosto 2026, último mes cerrado)

Sirven para validar que el parser está leyendo bien. Si estos números no cuadran, algo se rompió.

| Métrica | Valor |
|---|---|
| Venta neta | $145.696 (con EPA) · $117.020 (sin EPA) |
| Unidades | 87.863 |
| Toneladas | 210 |
| Precio promedio | $1,66 por unidad |
| Contribución | $38.175 |
| Margen | 26,2% |
| Rotación | 10,9x |
| Inventario | $118.727 |
| OC por recibir | $390.080 (~2,7 meses de cobertura) |
| Presupuesto bruto | $141.751 → cumplimiento **102,8%** |
| Clientes activados | 728 · inactivos 7.905 |
| SKU activados | 74 |
| Artículos con movimiento | 93 (de 173 en el catálogo) |
| Historia disponible | 38 meses con venta (ago-2023 a sep-2026) |

Crecimiento: ago-2024 $58.840 → ago-2025 $140.980 → ago-2026 $145.696.

**Regiones** (agosto): Centro $56.570 · Oriente $35.880 · Occidente $32.630 · Capital $20.610.
**Estados**: Carabobo $39.180 lidera.
**Supervisores**: Charly Bello $36.210 · Luis Landaeta $17.310 · Carlos Lagares $16.070.
**Top clientes**: Ferretería EPA $28.720 · Ferre KSA JH $5.090 · Ferrocerámica Valcro $4.640.

**Concentración de la OC:** 5 artículos son el 48,6% de los $390.080.

---

## 8. Arquitectura

El proyecto arrancó como web estática con los datos en el navegador, y evolucionó a
**base de datos con control de usuarios y roles**.

| Capa | Decisión |
|---|---|
| Base de datos | Postgres. El esquema está escrito para Supabase (usa `auth.users` y RLS) |
| Descarga | Instructivo fijo de 9 exportaciones, con los filtros exactos para copiar y pegar |
| Carga | Una sola zona de *drag & drop*. Todos los archivos juntos, en cualquier orden |
| Detección | Automática, leyendo el bloque "Filtros aplicados"; plan B por estructura de encabezado |
| Parseo | **En el navegador**, Web Worker con SheetJS. Manda lotes normalizados a la API |
| Ingesta | Función `ingerir_hechos(carga_id, jsonb)`: resuelve entidades y hace upsert de hechos |
| Archivo crudo | Se guarda en object storage para poder reprocesar |
| Agregados | Vistas materializadas refrescadas al terminar cada carga |
| Seguridad | Row Level Security en todas las tablas |

**Por qué el parseo va en el cliente:** un xlsx de 30 MB dentro de una Edge Function es dolor
innecesario. La contra es que la lógica de parseo vive en el cliente y puede quedar
desincronizada entre usuarios con caché vieja.

---

## 9. Modelo de datos

### Decisiones de fondo

**Una sola tabla de hechos, no un star schema.** El SIM puede sumar indicadores en cualquier
momento y cada marca tiene dimensiones distintas disponibles. Con
`hechos(entidad, periodo, indicador, mascara, valor)` un indicador nuevo es un INSERT en el
catálogo, no una migración. El precio es que las consultas necesitan `filter (where codigo=...)`,
por eso van las vistas materializadas encima.

**La clave única `(entidad, periodo, indicador, mascara)` resuelve el problema de fondo.**
El SIM corrige cifras hacia atrás, así que recargar un mes tiene que sobreescribir, no duplicar.
El `on conflict do update` lo hace gratis, y como cada hecho guarda su `carga_id`, revertir una
carga equivocada es un DELETE acotado.

**Las escalas se normalizan en la ingesta, no en la consulta.** Si dejas esa conversión en la capa
de aplicación, alguien la va a olvidar.

**Las dimensiones son una sola tabla.** Un artículo, un cliente, un vendedor y un estado son todos
`entidades`, con `grano` y `atributos jsonb`. Evita siete tablas casi idénticas.

### Tablas principales

| Tabla | Para qué |
|---|---|
| `perfiles` | Usuarios, extiende `auth.users`. Rol y estado activo |
| `marcas` | Código, nombre y **origen** (nacional / internacional) |
| `usuario_marca` | Asignación comprador ↔ marca, **con vigencia temporal** |
| `jefaturas` | Jefe de compras ↔ origen, **con vigencia temporal** |
| `parametros_marca` | Lead time, ciclo, seguridad, kg/unidad. Versionado |
| `indicadores` | Catálogo: código, etiqueta del SIM, agregación, factor de escala |
| `entidades` | Dimensiones unificadas. Incluye `excluir_de_analisis` (el caso EPA) |
| `hechos` | La tabla larga. Upsert idempotente |
| `periodos` | Marca si un mes está cerrado o va parcial |
| `ajustes` | Correcciones manuales, en capa aparte (ver abajo) |
| `inventario_snapshot` | Stock, tránsito y costo del infocompras, con fecha |
| `pronosticos` | Método, RMSE y horizonte calculado |
| `cargas` | Auditoría de ingesta: quién, qué archivo, hash, si vino truncado |
| `auditoria` | Rastro de cambios deliberados |

### Ajustes manuales: por qué van en capa aparte

Si un comprador corrige un número directamente sobre `hechos` y la semana siguiente recarga ese
mes, el upsert le borra la corrección **en silencio**. Por eso:

- Los datos del SIM quedan intactos en `hechos`.
- Las correcciones viven en `ajustes`, con motivo obligatorio y autor.
- La aplicación consulta **siempre `v_hechos`**, que devuelve el valor efectivo, el valor original
  del SIM, y una bandera de si viene corregido.
- Anular un ajuste es un UPDATE, no un DELETE: el rastro no se borra.

### Auditoría

**No se audita `hechos` fila por fila.** Una carga normal escribe decenas de miles de filas y
generaría un volumen inútil. Las cargas masivas ya quedan en `cargas` con su hash, autor y
conteo. Los triggers cubren solo lo deliberado: usuarios, asignaciones, jefaturas, parámetros,
ajustes y marcas.

`v_actividad` es el feed que ve gerencia, ya traducido a lenguaje humano: en vez de
`update en perfiles` dice *"Cambió el rol de María: comprador → gerencia"*. Trae una bandera
`requiere_atencion` que se enciende sola cuando alguien sube una exportación truncada.

---

## 10. Roles y permisos

### Los cinco roles

| Rol | Alcance | Puede cargar y corregir | Gestiona usuarios |
|---|---|---|---|
| `admin` | todas las marcas | sí | sí |
| `gerencia` | todas las marcas | **no** | sí |
| `jefe_compras` | todas las marcas de **su origen** | sí, en su ámbito | asigna marcas en su ámbito |
| `comprador` | solo sus marcas asignadas | sí, en sus marcas | no |
| `lectura` | solo sus marcas asignadas | no | no |

Hay exactamente **dos jefes de compras**: uno de marcas nacionales y otro de internacionales.

### Los cuatro alcances

No conviene confundirlos al escribir la aplicación:

| Función | Devuelve |
|---|---|
| `marcas_asignadas()` | las que lleva directamente el comprador, **hoy** |
| `marcas_en_ambito()` | las del origen que supervisa el jefe |
| `marcas_escribibles()` | dónde puede cargar y corregir |
| `marcas_visibles()` | dónde puede mirar |

Las políticas de lectura usan `marcas_visibles()`; las de escritura, `marcas_escribibles()`.
Gerencia no aparece en ninguna de las de escritura, así que **no puede tocar datos aunque los
vea todos**.

### El ámbito del jefe se deriva, no se enumera

El alcance del jefe es `origen = 'internacional'`, no una lista de marcas. Cuando Febeca meta una
marca nueva, cae sola bajo el jefe que corresponde sin que nadie toque permisos. Con 169 marcas,
eso importa.

Un comprador puede llevar marcas de ambos orígenes; en ese caso responde ante un jefe por unas
marcas y ante el otro por las demás. El modelo lo soporta sin nada especial.

### Notas de rendimiento de RLS

- Las funciones de seguridad son **`STABLE`**. Si fueran `VOLATILE`, la política se evaluaría
  fila por fila sobre una tabla de millones de registros.
- **`marca_id` está denormalizado** en `hechos` a propósito, para que la política no tenga que
  unir contra `entidades` en cada consulta.
- Las **vistas materializadas no respetan RLS**: se exponen mediante vistas normales con
  `security_invoker = true`, que sí la aplican.

---

## 11. Vigencias temporales

Las asignaciones de marca y las jefaturas tienen **rango de fechas**, no son relaciones planas.

**El permiso caduca solo, sin ningún job programado.** La vigencia se evalúa en cada consulta
contra `current_date`, así que una suplencia registrada hoy para diciembre se activa el día 1 y
se apaga el 16 sin que corra nada. No hay cron que se pueda caer.

**Nada se borra.** `terminar_asignacion` pone fecha de fin; `desactivar_usuario` cierra rangos en
vez de eliminar filas. Por eso `responsables(marca, fecha)` puede contestar quién llevaba PCP el
15 de agosto.

**Restricción de exclusión GiST:** impide que la misma persona tenga dos asignaciones solapadas
sobre la misma marca, pero deja que dos personas distintas se solapen — eso es exactamente una
suplencia. Como el rango es `[)`, una asignación que cierra el día 30 y otra que abre el 30 no
chocan: el traspaso queda sin hueco ni solape.

### Funciones de operación

```sql
app.asignar_marca(marca, usuario, desde, hasta, titular, motivo)
app.terminar_asignacion(id, hasta, motivo)
app.reasignar_marca(marca, nuevo, quitar_al, desde, motivo)   -- traspaso permanente
app.programar_suplencia(marca, suplente, desde, hasta, motivo, suspender_titular)
app.nombrar_jefe(usuario, origen, desde, hasta, motivo)
app.cubrir_jefatura(suplente, origen, desde, hasta, motivo)
app.desactivar_usuario(usuario)
app.ajustar_hecho(entidad, periodo, indicador, mascara, valor, motivo)
app.ingerir_hechos(carga_id, filas_jsonb)
app.revertir_carga(carga_id)
app.refrescar_agregados()
```

`programar_suplencia` tiene dos modos: por defecto el titular conserva el acceso durante la
ausencia; con `suspender_titular = true` se le parte el rango en dos y el acceso le vuelve solo
el día que regresa.

### Vistas de administración

| Vista | Para qué |
|---|---|
| `v_actividad` | Feed de cargas y cambios, en lenguaje humano |
| `v_asignaciones` | Asignaciones con estado: programada / vigente / suplencia / terminada |
| `v_jefaturas` | Jefes por origen, con estado y conteo de marcas |
| `v_equipo` | Tablero del jefe: su equipo y quién no cargó esta semana |
| `v_cumplimiento_carga` | Al día / pendiente / atrasado, por comprador y marca |
| `v_suplencias_por_vencer` | Avisa 7 días antes de que caduque un acceso |
| `v_marcas_sin_responsable` | Marcas huérfanas (pasa solo al vencer una suplencia) |
| `v_origenes_sin_jefe` | Orígenes que se quedaron sin jefe vigente |
| `v_pedido_sugerido` | Demanda, stock, tránsito, cobertura y sugerido por artículo |
| `v_hechos` | Hechos con ajustes manuales aplicados encima |

---

## 12. Migraciones

| Archivo | Contenido |
|---|---|
| `febeca-schema.sql` | Esquema base: tablas, indicadores, RLS, ingesta, agregados |
| `febeca-migracion-002-roles.sql` | Roles, gestión de usuarios por gerencia, ajustes manuales, auditoría |
| `febeca-migracion-003-vigencias.sql` | Asignaciones con rango de fechas y suplencias |
| `febeca-migracion-004-jefaturas.sql` | Jefe de compras con ámbito por origen |

> **Aviso sobre la 002:** cambia el enum `app.rol` teniendo funciones y vistas que dependen de él,
> y Postgres rechaza el `drop type` y el `alter column type`. La 004 incluye el patrón correcto
> (soltar dependencias → cambiar el tipo → reconstruir) y lo deja corregido. Si vas a aplicar
> las migraciones desde cero sobre una base limpia, conviene consolidar 002 con esa corrección.

---

## 13. Estructura del dashboard

Modo oscuro ejecutivo, siete pestañas, cuatro controles globales en la barra superior.

### Controles globales

| Control | Qué hace |
|---|---|
| `excluirEPA` | Quita a EPA de venta, pronósticos y rankings |
| `periodo` | Mes, último trimestre o año actual |
| `coberturaObjetivo` | Deslizador de 1 a 8 meses, recalcula pedidos en vivo |
| `filtroArticulo` | Selecciona un SKU para abrir su ficha |

### Las siete pestañas

1. **Resumen ejecutivo** — seis KPIs (venta, margen, contribución, activación, rotación, GMROI),
   gráfico de histórico más pronóstico, y un panel que interpreta los números en lenguaje de
   negocio.
2. **Top rankings** — artículos, supervisores y clientes con barras de participación.
3. **Ficha 360° por producto** — buscador de SKU; venta, stock, tránsito, cobertura, pedido
   sugerido con peso, desglose del cálculo y gráfico de tendencia propio.
4. **Sugerido de compra y cobertura** — tabla con semáforo: rojo bajo 1,5 meses, verde en meta,
   ámbar por encima del objetivo.
5. **Motor de pronósticos** — compara la proyección con y sin EPA, muestra el método en uso.
6. **Exportador de cierre mensual** — cinco láminas con el formato de gerencia. El plan de acción
   se arma solo contando artículos en riesgo y dormidos.
7. **Estado de carga del SIM** — qué archivos entraron, con qué corte y si vinieron truncados.
   Sin un aviso visible, un archivo truncado muestra ceros en silencio.

---

## 14. Estado actual

### Hecho

- Análisis completo de los archivos reales del SIM y del infocompras.
- Definición de las nueve descargas, validadas contra los totales de la marca.
- Prototipo con parser funcional: lee los .xlsx, los detecta solo, normaliza y calcula.
- Prototipo ejecutivo de siete pestañas con los datos reales de PCP y Holt-Winters en el navegador.
- Esquema completo de base de datos con roles, RLS, vigencias, ajustes y auditoría.

### Falta

1. Conectar el frontend a la base de datos (hoy los prototipos tienen los datos embebidos).
2. Pantallas de administración: usuarios, asignaciones, jefaturas, feed de actividad.
3. Flujo de autenticación. Si Febeca tiene Microsoft 365, conviene SSO con Azure AD.
4. Modo multimarca: hoy el piloto es solo PCP.
5. Generación de `.pptx` nativo con pptxgenjs (los prototipos entregan HTML apaisado).
6. Definir quién refresca los agregados y cuándo: con 169 marcas y varios compradores subiendo el
   mismo lunes, `refrescar_agregados()` al final de cada carga produce refrescos concurrentes.
   Alternativa: cola con *debounce*, o tablas de agregado incrementales por marca.

---

## 15. Pendientes por confirmar con Febeca

1. **Los vendedores suman de más.** Los 739 vendedores dan $157.550 en agosto contra $145.696 del
   total de la marca (8% de exceso). Podrían ser transferencias o notas de crédito aparte.

2. **Verificar `DISP` y `TRANSITO`.** En PCP suman 18.242 y 379.608 unidades — veinte veces más en
   camino que en almacén. En dólares el ratio da parecido, pero conviene confirmar la unidad de
   medida antes de montar alertas encima.

3. **Confirmar el factor kg/unidad** (ver sección 6).

4. **Lead time del resto de las marcas.** Solo está confirmado el de PCP.

5. **Artículos sin movimiento.** El SIM lista 173 y el infocompras 80. ¿Se muestran o se esconden?

6. **Duplicados en el maestro de clientes.** EPA aparece con tres razones sociales.

7. **¿El problema de `NO CLASIFICADO` afecta a otras marcas** además de PCP?

### Decisiones de permisos tomadas por defecto

Todas son reversibles con un cambio de una o dos líneas:

- **El jefe puede cargar y corregir en todo su ámbito**, no solo ver. Para que sea estrictamente
  supervisor, se quita `jefe_compras` de `puede_cargar()`.
- **El jefe no ve la auditoría completa del sistema**, solo la de su ámbito.
- **Al terminar una asignación, el comprador pierde también el acceso de lectura** al histórico de
  esa marca. Para que conserve lectura, cambiar `marcas_asignadas()` por `marcas_historicas()`
  dentro de `marcas_visibles()`.
- **El lead time lo cambia el comprador**, no gerencia, porque es quien habla con el proveedor.
  Si debe requerir aprobación, se convierte en una solicitud con estado.
- **Gerencia puede asignarse marcas a sí misma.** Hoy no le sirve de nada porque igual no puede
  escribir, y queda en auditoría.
- **Un comprador con marcas de ambos orígenes aparece en el equipo de los dos jefes.** Si en
  Febeca los compradores son estrictamente de un departamento, conviene validarlo.
