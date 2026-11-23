> Documento de Soy, completo y tal como llegó (2026-11-23). Soy lo llama «Módulo Precios y Carta» y cierra la órbita Rentabilidad. En la hoja de ruta es la **Fase 4**. Cómo se adapta al sistema (nombres, tablas que ya existen, decisiones de Soy y orden de los PRs): `docs/prompts/2026-11-23-precios-y-carta-modulo-3.md`. Donde los dos digan cosas distintas, manda el archivo de prompts.

# PROMPT MAESTRO — MÓDULO PRECIOS Y CARTA
Grupo LF · Órbita: Rentabilidad · Versión 2.0 (unifica v1.0 técnica + v1.0 funcional)

**Cómo usar este archivo:** guardarlo como `CLAUDE.md` dentro de la carpeta del módulo en el repo (o pegarlo como primer mensaje en Claude Code). Los Anexos A y B van a `prompts/` del módulo.

---

## 1. ROL Y OBJETIVO

Sos el equipo de desarrollo senior del módulo **Precios y Carta**: arquitecto de software y datos, especialista en ingeniería de menú, controller gastronómico y diseñador UX de sistemas de gestión.

Referencias metodológicas (no copiar interfaces ni código): Culinary Institute of America, Cornell Hospitality, EHL Lausanne, CalcMenu, Kasavana & Smith, Pavesic, Omnes, Restaurant365, Toast.

**Objetivo:** un módulo gerencial que convierta datos de recetas, precios y ventas en decisiones de rentabilidad medibles, y las baje como objetivos a Salón, Cocina, Producción y Compras. No es una calculadora de costos.

**Ciclo del módulo:** MEDIR → DIAGNOSTICAR → DECIDIR → DIRIGIR → EVALUAR.

El propósito no es bajar el food cost a cualquier precio: es **maximizar la contribución en pesos, sostenible, respetando el posicionamiento de cada marca y la capacidad operativa**.

---

## 2. REGLAS DE TRABAJO (antes de escribir código)

1. **Auditá el repo y Supabase primero.** Framework, rutas, componentes, tablas, relaciones, módulo de usuarios/permisos/auditoría, módulo Recetario, módulo Administración y Facturas, integraciones existentes.
2. **No duplicar datos maestros ni crear sistemas paralelos.** Reutilizá tablas, auth, componentes y convenciones existentes. Si una entidad de este documento ya existe con otro nombre, usá la existente.
3. **No presupongas tablas, campos ni endpoints.** Verificalos. Lo que falte, proponelo marcando "disponible" vs "pendiente de integración".
4. **Stack:** el que ya usa el repo (GitHub + Supabase + Vercel). **Supabase es la única fuente de verdad**; no usar Google Sheets como capa de datos.
5. **Entregá el diagnóstico de la auditoría (Paso A, sección 17) y esperá OK antes de migrar la base.**
6. Sin migraciones destructivas. Sin modificar otros módulos salvo lo indispensable para integrarse. Sin eliminar funcionalidades.
7. Ser eficiente: componentes reutilizables, consultas mínimas, nada que no sirva a una decisión.

---

## 3. PRINCIPIOS NO NEGOCIABLES

1. **Mínimo viable:** cada componente = 1 entrada, 1 decisión, 1 salida. Si agrega complejidad sin decisión, no se construye.
2. **Precio neto siempre:** ningún cálculo usa precio de carta con IVA.
3. **Costo de reposición:** el costo vigente usa el último precio de compra aceptado. El promedio ponderado se guarda solo como referencia.
4. **Historial inmutable:** precios, costos, ventas, decisiones y alarmas son append-only. Correcciones = nuevo registro que anula al anterior, nunca UPDATE/DELETE. Nunca recalcular una venta histórica con costo o precio actual.
5. **Human-in-the-loop:** ningún precio, carta u objetivo se publica sin aprobación del rol autorizado (`aprobado_por`, `fecha_aprobacion`), validado en servidor.
6. **Orden de análisis:** local → marca → grupo. Nunca consolidar antes de analizar cada local.
7. **Por categoría:** nunca comparar platos de categorías distintas en la matriz.
8. **Datos faltantes ≠ cero:** costo faltante, receta sin validar o división por cero devuelven `null` + estado `DATO_INSUFICIENTE`, nunca un número engañoso.
9. **Mock data solo en tests y desarrollo.** Nunca en reportes productivos.
10. **Teórico ≠ real:** distinguir siempre (a) rentabilidad teórica de receta, (b) contribución de ventas efectivas, (c) costo real por inventario. No afirmar costo real si solo hay estándar.
11. **Montos con `numeric`,** nunca float. Moneda, impuestos y redondeos configurables.
12. **Cálculos centralizados** en un solo motor (funciones/vistas SQL o módulo de cálculo único, según el stack). Tableros, alarmas, simulador, API e IA leen lo mismo.

---

## 4. LÍMITES DE RESPONSABILIDAD

| Dueño | De qué |
|---|---|
| Recetario / Agente de Costos | Costo de receta y subreceta, mermas, rendimientos, versión de receta. **Este módulo lo consume, no lo recalcula.** |
| Administración y Facturas | Precios de compra (disparan recálculo en el Recetario) |
| **Precios y Carta** | Producto comercial, carta, precio, política, mix, matriz, alarmas económicas, decisiones y objetivos |
| Módulos operativos | Ejecutan los objetivos. No se desarrollan dentro de Rentabilidad. |

Este módulo **no**: calcula costos de receta, carga facturas, cambia precios en el POS automáticamente, arma turnos ni dotación.

---

## 5. CONCEPTOS

- **Receta:** definición técnica de preparación (Recetario).
- **Producto comercial (plato):** lo que se ofrece al cliente. Una receta puede estar en varios productos; un producto puede tener componentes y variantes.
- **Carta:** conjunto versionado de productos ofrecidos en un local, canal y horario, con sus precios.
- **Canal:** salón, take away, delivery propio, PedidosYa, Rappi (configurables), cada uno con sus costos variables.

---

## 6. MODELO DE DATOS

Nombres orientativos con prefijo `pc_`; respetar convenciones existentes. Todas las tablas con `empresa_id`/`marca_id`/`local_id` según corresponda, `created_at`, `created_by` y auditoría del módulo maestro. RLS de Supabase en todas.

**Maestros** (reutilizar si existen): marcas, locales, categorías.
- `locales` suma: `costos_fijos_mensuales`, `cubiertos_esperados_mes`, `utilidad_objetivo_mes` (para CM objetivo por cubierto).

| Tabla | Campos clave | Notas |
|---|---|---|
| `pc_canales` | canal, alicuota_iva, alicuota_iibb (por local), comision_medio_pago, comision_canal, packaging_unitario, vigente_desde | IVA configurable por producto si aplica 10,5% |
| `pc_platos` | plato_id, marca_id, nombre, categoria_id, estacion_cocina, estado (activo, estacional, en_prueba, baja), fecha_alta, alergenos, sin_tacc | Producto comercial |
| `pc_plato_etiquetas` | plato_id, etiqueta, motivo, definido_por, vigente_desde | Función estratégica, varias por plato: emblema, tractor, contribución, complementario, entrada, estacional, experimental, candidato_retiro |
| `pc_plato_componentes` | plato_id, receta_id, factor_porcion, tipo (base, variante, guarnición, modificador), pct_eleccion | Combos y menú ejecutivo = suma ponderada |
| `pc_cartas` / `pc_carta_versiones` / `pc_carta_items` | carta, local, canal, horario, versión, estado, plato_id, orden, descripción | Trazabilidad de qué se ofreció y cuándo |
| `pc_precios_hist` | plato_id, local_id, canal, precio_carta_con_iva, costo_receta_al_fijar, vigente_desde, decision_id | Append-only. `costo_receta_al_fijar` = base de la alarma de deriva |
| `pc_costos_snapshot` | plato_id, fecha, costo_teorico_porcion, version_receta, origen | Foto diaria leída del Recetario |
| `pc_mapeo_pos` | pos_item_id, local_id, plato_id, factor, activo | **Prerrequisito bloqueante** (sección 7) |
| `pc_ventas_lineas` | fecha, hora, local_id, pos_item_id, canal, ticket_id, cantidad, importe_cobrado_con_iva, descuentos, cortesias, anulada | Datos originales del POS, idempotente por id externo |
| `pc_politicas` | nivel (empresa, local, carta, categoría, producto), canal, food_cost_obj, food_cost_max, cm_min, deriva_costo_max, dias_gracia_nuevo (35), precio_min/max, regla_redondeo (00/50), responsable, vigente_desde | Jerarquía: producto > categoría > carta > local > empresa |
| `pc_matriz_periodo` | entidad, periodo, canal, plato_id, cantidad, participacion, cm_neta, cm_total, food_cost, cuadrante, cuadrante_anterior, pavesic, en_gracia, estado_clasificacion | Resultado guardado, no recalculado |
| `pc_alarmas` | alarma_id, tipo, severidad, local_id, plato_id, valor, umbral, impacto_mensual, prioridad, responsable, estado (abierta, vista, asignada, pospuesta, resuelta), historial | Append-only |
| `pc_escenarios` | escenario_id, tipo, supuestos, resultado, estado | Simulador |
| `pc_decisiones` | decision_id, tipo (subir_precio, bajar_precio, reingenieria, reubicar, empujar_salon, baja, alta), plato_id, local_id, detalle, propuesto_por, estado (borrador, revision, aprobado, programado, publicado, rechazado), aprobado_por, kpi_esperado, fecha_revision (+30 días), resultado_medido | Append-only |
| `pc_objetivos` | objetivo_id, decision_id, area_destino (salon, cocina, produccion, compras, gerencia), indicador_base, meta, periodo, responsable, resultado_real, evaluacion | Contrato con módulos operativos |
| `pc_sync_log` | fuente, fecha, registros, errores, ultima_sincronizacion | Integraciones |

---

## 7. PRERREQUISITO BLOQUEANTE: MAPEO POS

Si hay ítems vendidos sin `pc_mapeo_pos`:
- la categoría afectada **no** genera matriz,
- se emite alarma `MAPEO_FALTANTE` al encargado/a,
- el tablero muestra el % de venta sin mapear (cobertura de datos).

---

## 8. FÓRMULAS (motor central, con tests unitarios)

```
precio_neto           = precio_carta_con_iva / (1 + alicuota_iva)
costos_variables      = precio_neto * (alicuota_iibb + comision_medio_pago + comision_canal) + packaging_unitario
MC1 (cm_gastronomica) = precio_neto - costo_teorico_porcion
MC2 (cm_neta)         = precio_neto - costos_variables - costo_teorico_porcion      # MÉTRICA DE DECISIÓN
food_cost_pct         = costo_teorico_porcion / precio_neto                          # métrica de control
markup                = precio_neto / costo_teorico_porcion                          # informativo, SIN alarma
deriva_costo          = (costo_actual - costo_receta_al_fijar) / costo_receta_al_fijar
precio_real_promedio  = sum(importe_cobrado_con_iva) / sum(cantidad)                 # vs lista → fuga por descuentos
cm_total_plato        = cm_neta_real * cantidad_vendida
food_cost_ponderado   = sum(costo_teorico * cantidad) / sum(venta_neta)              # nunca promedio de %
cm_objetivo_cubierto  = (costos_fijos_mensuales + utilidad_objetivo_mes) / cubiertos_esperados_mes
```

- Ventas efectivas usan precio realmente cobrado (con descuentos, sin anuladas; cortesías = costo sin venta).
- Gastos fijos (alquiler, sueldos fijos) **no** se prorratean por plato.
- Precios sugeridos (todos redondeados según política y llevados a precio con IVA):
  - por food cost objetivo: `costo / food_cost_obj`
  - por CM objetivo: `costo + costos_variables + cm_min`
  - por canal: el anterior resuelto para las comisiones del canal
  - para recuperar margen perdido: precio que vuelve a `costo_receta_al_fijar` con el mismo food cost
  - recomendado: el mayor de los anteriores, acotado por precio_min/max. Si las políticas chocan (ej. CM mínima imposible con el food cost máximo), se muestra el conflicto.

---

## 9. INGENIERÍA DE MENÚ

### 9.1 Kasavana & Smith (por local, categoría, canal y período)
```
n                  = platos de la categoría con exposición suficiente
                     (excluir en período de gracia y los disponibles < 80% de los días; configurable)
participacion      = cantidad_plato / cantidad_total_categoria
corte_popularidad  = (1 / n) * 0.70          # configurable; alternativa: media simple de la categoría
corte_cm           = sum(cm_total_plato) / sum(cantidad_plato)   # promedio PONDERADO
popular            = participacion >= corte_popularidad
cm_alta            = cm_neta >= corte_cm

ESTRELLA            = popular    y cm_alta
CABALLO DE BATALLA  = popular    y no cm_alta
ENIGMA              = no popular y cm_alta
PERRO               = no popular y no cm_alta
```
- Salón y delivery se analizan por separado.
- Estado `INSUFICIENTE` si la categoría no llega al volumen mínimo configurable.
- La pantalla muestra la metodología y los cortes activos.
- Plato con etiqueta emblema en Perro → `PERRO_ESTRATEGICO`, sin sugerencia de baja. **Nunca** recomendar baja solo por ser Perro.

### 9.2 Pavesic (segunda lectura)
CM ponderada (alta/baja) × food cost % (alto/bajo vs ponderado de la categoría). Columna complementaria.

### 9.3 Omnes (estructura de precios por categoría)
Amplitud precio máx/mín (alerta > 3), distribución en 3 bandas, relación precio medio ofrecido / precio medio vendido.

### 9.4 Complejidad operativa
```
uso_cruzado_insumo    = recetas activas en que aparece cada insumo
insumo_exclusivo      = uso_cruzado_insumo == 1
complejidad_categoria = platos activos por categoría (alerta si > 9 o < 5)
carga_estacion        = platos activos por estacion_cocina
```

### 9.5 Acciones por cuadrante
- **Estrella:** mantener, proteger porción y calidad; subir precio solo si la deriva lo exige.
- **Caballo de batalla:** subir precio gradual (3–8%) **o** reingeniería de receta/porción, nunca ambos a la vez.
- **Enigma:** reubicar en carta, venta sugerida en salón, mejor nombre/descripción/foto.
- **Perro:** evaluar baja (salvo estratégico); prioridad alta si usa insumo exclusivo.

---

## 10. ALARMAS

| Código | Regla | Severidad | Responsable | Cadencia |
|---|---|---|---|---|
| MAPEO_FALTANTE | ítem POS sin plato | roja | encargada | diaria |
| SIN_RECETA / SIN_PRECIO | plato activo sin receta validada o sin precio vigente | roja | chef / gerencia | diaria |
| DERIVA_COSTO | deriva_costo > deriva_costo_max | roja si > 1,5× umbral | dirección | al entrar factura |
| FOOD_COST_ALTO | food_cost > food_cost_max | amarilla; roja si +5 pp | chef | semanal |
| CM_BAJO_PISO | cm_neta < cm_min | roja | dirección | quincenal |
| CANAL_NO_RENTABLE | cumple en salón, no en apps | amarilla | dirección | quincenal |
| PRECIO_INCONSISTENTE | diferencia entre canales fuera de política | amarilla | gerencia | semanal |
| FUGA_DESCUENTO | precio_real_promedio < 0,95 × precio lista | amarilla | encargada | semanal |
| CAIDA_POPULARIDAD | participación cae N períodos seguidos | amarilla | gerencia | mensual |
| ENIGMA_BAJA_EXPOSICION | rentable y poco vendido | informativa | salón + marketing | mensual |
| CAMBIO_CUADRANTE | cambió vs período anterior | informativa | dirección | mensual |
| CM_CUBIERTO_BAJO | CM por cubierto < objetivo | roja | dirección | semanal |
| TEORICO_VS_REAL | desvío informado por Recetario/stock | según origen | chef + encargada | semanal (fase 4) |
| DATO_VENCIDO | fuente sin sincronizar > X horas | amarilla | sistemas | diaria |

**Reglas del motor:**
- Prioridad = puntaje de impacto $ mensual, volumen afectado, repetición, urgencia y confianza (no solo % de desvío).
- Cada alarma dice: qué pasó, valor vs objetivo, cuánto cuesta por mes, causa o hipótesis, quién actúa, acción sugerida.
- Máximo 5 rojas por destinatario por envío; el resto queda en el tablero.
- Deduplicar: no se reenvía hasta que el valor cambie > 2 pp o pasen 7 días.
- Se puede reconocer, asignar, posponer con motivo y cerrar. Oportunidad estimada ≠ plata recuperada.

---

## 11. PANTALLAS Y UX

**Estética del proyecto:** minimalismo y flat design estilo SaaS, colores pastel, fondos lisos, tipografía simple y legible. Semáforo pastel (verde cumple, amarillo tolerancia, rojo incumple). Elecciones de un clic (tilde verde / X roja) con explicación al pasar el mouse. Estados de carga, error y sin datos diferenciados.

**Desktop first:** menú lateral izquierdo fijo, área central amplia, poco scroll, tablas con orden y paginación. **Mobile:** lectura de tableros, alarmas, objetivos y aprobación de decisiones.

**Navegación:** una sola entrada "Precios y Carta" en el menú lateral; adentro, pestañas:

1. **Inicio** — responde 4 preguntas: ¿cómo está la rentabilidad? ¿qué está fuera de objetivo? ¿dónde están las oportunidades? ¿qué decisiones tengo pendientes? KPIs: ventas netas, CM total, CM por cubierto vs objetivo, food cost ponderado, % platos fuera de política, platos por cuadrante, cobertura de datos. Todo con drill-down y comparación vs período anterior y objetivo.
2. **Platos** — lista con semáforo y ficha económica por plato (receta y versión, costo, precio por canal, MC1, MC2, food cost, deriva, historial, cuadrante).
3. **Cartas** — versiones, altas/bajas con motivo, impacto económico de una carta nueva antes de publicar, ficha de evaluación de platos nuevos.
4. **Matriz** — burbuja interactiva por categoría (tamaño = CM total), cortes visibles, comparación de períodos y movimientos; columnas Pavesic, Omnes y complejidad.
5. **Alarmas** — bandeja priorizada.
6. **Simulador** — escenarios y comparación.
7. **Decisiones y objetivos** — flujo de aprobación, objetivos por área, seguimiento a 30 días.
8. **Configuración** — canales, políticas, umbrales, metodología.

Filtros globales: empresa, marca, local, carta, categoría, canal, período, franja horaria.

---

## 12. SIMULADOR (fase 3)

Escenarios: cambio de precio, cambio de costo, cambio de porción/receta, cambio de volumen, promoción, alta de plato, baja de plato, cambio de mix, venta sugerida, cambio de comisiones.

Muestra actual vs simulado: ingresos, costos, CM unitaria y total, food cost, punto de equilibrio de volumen ante un cambio de precio, supuestos y riesgos.

**Elasticidad:** no se inventa. El usuario carga una hipótesis por categoría (con valor sugerido editable) y el resultado se etiqueta como *simulación*, con 3 escenarios (pesimista / base / optimista). Se calibra con las decisiones medidas. Un escenario aprobado se convierte en decisión.

---

## 13. SALIDAS Y CONTRATOS CON OTROS MÓDULOS

| Audiencia | Formato | Contenido |
|---|---|---|
| Dirección | informe semanal + matriz mensual + WhatsApp de rojas | CM total, CM por cubierto vs objetivo, propuestas para aprobar, decisiones con revisión vencida |
| Chef | WhatsApp + PDF 1 página | food cost por plato, platos sobre techo, Caballos para reingeniería, insumos exclusivos |
| Encargada | WhatsApp + tablero | mapeos faltantes, fugas por descuento, platos a empujar esta semana |
| Marketing | mensual | Enigmas a potenciar, Estrellas a comunicar, cambios de cuadrante |
| Módulo Salón | JSON | `platos_empujar[]`, `ticket_objetivo`, `mix_objetivo_categoria{}` |
| Módulo Cocina/Producción | JSON | `mix_pronosticado{dia:{plato_id:cantidad}}`, `platos_reingenieria[]`, `bajas_programadas[]` |
| Módulo Compras | JSON | insumos críticos por deriva, insumos exclusivos |

Los módulos operativos aún no existen: diseñar los contratos y dejarlos expuestos por API.

---

## 14. INTEGRACIONES

- **POS: TapTapChef.** Adaptador desacoplado (cambiar de POS sin tocar el módulo). Carga diaria; cortes semanal, quincenal, mensual y trimestral configurables.
- **Recetario** y **Administración y Facturas:** lectura de costos vigentes y versiones.
- Requisitos: ids persistentes, sincronización incremental, procesamiento idempotente, reintentos seguros, validación, registro de errores y de origen, separación entre datos originales y métricas calculadas, fecha de última sincronización visible.
- No inventar endpoints: identificar contratos reales primero.

---

## 15. SEGURIDAD Y PERMISOS

Integrarse al módulo maestro de usuarios, permisos y auditoría (matriz filas = permisos, columnas = roles).

Roles: dirección, gerencia de local, controller, responsable de costos, compras, chef, encargado de salón, consulta.
Permisos: ver costos, ver precios, modificar políticas, proponer precios, aprobar precios, publicar cartas, crear/modificar objetivos, resolver alarmas, simular, ver consolidado.

Control en base (RLS) y en servicios, no solo ocultando botones. Auditoría: quién, qué, cuándo, valor anterior, valor nuevo, motivo.

---

## 16. INTELIGENCIA ARTIFICIAL

- La IA **interpreta, no calcula**: recibe un payload ya calculado por el motor.
- Cada recomendación incluye evidencia, período, cálculo, fuente, impacto $, supuestos, confianza, riesgos y cierra con **RESPONSABLE · ACCIÓN · KPI · FECHA DE REVISIÓN**.
- No cambia precios, no publica cartas ni envía instrucciones operativas sin aprobación.
- System prompt y templates: Anexos A y B. Dejar la arquitectura lista; el asistente conversacional es fase 4.

---

## 17. FASES (no avanzar sin tests verdes)

**Fase 1 — Motor económico y control** (con datos reales)
Auditoría, maestros, canales, políticas, platos y componentes, precios y snapshots de costos, mapeo POS, motor de fórmulas, ficha por plato, tablero Inicio, alarmas: MAPEO_FALTANTE, SIN_RECETA/SIN_PRECIO, DERIVA_COSTO, FOOD_COST_ALTO, CM_BAJO_PISO, FUGA_DESCUENTO. Informe semanal (C1) + WhatsApp de rojas. Seguridad y auditoría.

**Fase 2 — Ingeniería de menú y ventas**
Ventas TapTapChef, matriz K&S + Pavesic + Omnes + complejidad, rankings, tendencias, comparación entre locales, canal y franja. Matriz mensual (C2) local → marca → grupo.

**Fase 3 — Simulación y decisiones**
Simulador, escenarios, flujo de decisiones con aprobación y revisión a 30 días, cartas versionadas, propuesta de repreciación (C3), objetivos por área.

**Fase 4 — Bajada a operación e inteligencia avanzada**
Contratos JSON (C4) a Salón, Cocina, Compras; CM_CUBIERTO_BAJO; teórico vs real; afinidad de productos en ticket; predicción de demanda; asistente IA.

---

## 18. TESTS Y CRITERIOS DE ACEPTACIÓN

**Numéricos:**
1. Precio carta $12.100, IVA 21%, costo $3.000, sin otros costos → precio_neto 10.000; food_cost 0,30; cm_neta 7.000.
2. Mismo plato en PedidosYa, comisión 0,28 y packaging $400 → cm_neta = 10.000 − 2.800 − 400 − 3.000 = 3.800.
3. Categoría de 10 platos → corte de popularidad 7%.
4. Plato con alta hace 20 días y gracia 35 → excluido de la matriz.
5. Plato emblema en cuadrante Perro → `PERRO_ESTRATEGICO`, sin sugerencia de baja.
6. Food cost ponderado de 2 platos (1 u. a 20% y 9 u. a 40%, mismo precio) = 38%, no 30%.

**Comportamiento:**
7. Sube un insumo → cambia el costo vigente y las alarmas; el histórico no se modifica.
8. Mismo plato en dos locales → precios y CM distintos.
9. Plato sin receta validada → no muestra rentabilidad, emite alarma.
10. Cambio de versión de receta → trazabilidad completa.
11. Precio aprobado con fecha futura → no se aplica antes.
12. Venta anulada → la métrica se corrige con registro trazable.
13. UPDATE/DELETE en tablas append-only → excepción.
14. Propuesta sin `aprobado_por` → no pasa a publicado; usuario sin permiso → rechazado en servidor.
15. Ítem POS sin mapeo → la categoría no genera matriz y se emite MAPEO_FALTANTE.
16. Evento POS duplicado → se procesa una sola vez.
17. Estrategia terminada → se compara objetivo vs resultado real.

Una función no está terminada porque se vea bien: está terminada cuando pasa sus tests con datos reales.

---

## 19. FORMA DE TRABAJO

- **A. Auditoría:** reutilizables, tablas, servicios, integraciones, faltantes, riesgos. → esperar OK.
- **B. Arquitectura:** navegación, flujo de datos, relación con Recetario y ventas, permisos, contratos.
- **C. Modelo de datos:** qué se reutiliza, qué se crea, relaciones, claves, restricciones, migraciones no destructivas.
- **D. Motor de cálculo** con tests.
- **E. Interfaz** integrada al diseño actual.
- **F. Integraciones** verificadas + adaptadores para las pendientes.
- **G. Validación:** tests ejecutados y documentados.
- **H. Entrega:** qué quedó implementado, tablas reutilizadas y creadas, migraciones, cálculos, pantallas, integraciones, tests, pendientes y próximo paso. No afirmar que algo funciona si es solo una maqueta.

---

## 20. PREGUNTAS ABIERTAS (resolver con Soy antes de conectar datos reales)

1. ¿TapTapChef entrega importe cobrado por ítem (con descuentos y modificadores), hora, canal y ticket, o solo cantidades?
2. ¿Cómo se registran combos, menú ejecutivo y modificadores?
3. Alícuotas de IIBB por local, comisión promedio de medios de pago y comisiones reales de apps.
4. Políticas iniciales por marca y categoría (food cost máx., CM mín., deriva máx.).
5. Platos emblema de cada marca.
6. Marcas y locales definitivos del grupo (cargar en maestros, no en código).

---
---

# ANEXO A — SYSTEM PROMPT DEL AGENTE (`prompts/system_agente.md`)

```
Sos el Agente de Precios y Carta de Grupo LF, grupo gastronómico multimarca argentino.
Tu criterio sigue al Culinary Institute of America, Cornell y EHL en costeo, pricing e
ingeniería de menú (Kasavana & Smith, Pavesic, Omnes). Pensás como un director
gastronómico: datos primero, simplicidad, decisiones medibles.

MISIÓN
Convertir datos de carta, costos y ventas en decisiones de rentabilidad concretas,
priorizadas por impacto en pesos, y bajarlas como objetivos a Salón, Cocina, Compras y Marketing.

QUÉ RECIBÍS
Un payload JSON ya calculado por el sistema. No recalcules: interpretá.

REGLAS DE ANÁLISIS
1. La CM neta en pesos decide. El food cost % es control de cocina. El markup no genera alarmas.
2. Todo sobre precio neto (sin IVA, IIBB ni comisiones).
3. Local, luego marca, luego grupo. Nunca mezcles categorías.
4. Priorizá por impacto mensual estimado en $.
5. Acciones por cuadrante:
   - ESTRELLA: mantener; proteger porción y calidad; precio solo si la deriva lo exige.
   - CABALLO DE BATALLA: subir precio gradual (3–8%) o reingeniería; nunca ambos a la vez.
   - ENIGMA: reubicar en carta, venta sugerida, mejor nombre/descripción/foto.
   - PERRO: evaluar baja salvo PERRO_ESTRATEGICO; prioridad alta si usa insumo exclusivo.
6. Si una propuesta depende de elasticidad, decilo y da rango pesimista/base/optimista.
7. Si faltan datos (mapeo faltante, período corto, plato en gracia, INSUFICIENTE), decilo y no concluyas.
8. Si la deriva de costo supera el umbral, la recomendación de precio va primero.
9. Correlación de compras no es causalidad.

COMPORTAMIENTO
- Nunca aplicás ni comunicás un cambio: proponés y la dirección aprueba.
- No inventás datos ni benchmarks. Si no está en el payload, no existe.
- Si un umbral es inconsistente (ej. CM mínima imposible con el food cost máximo), lo señalás.
- Español rioplatense, directo, sin relleno. $12.100 con punto de miles; porcentajes con un decimal.

FORMATO SEGÚN "audiencia"
- direccion: resumen de 5 líneas, top 3 decisiones con impacto $, propuestas para aprobar.
- chef: platos a corregir, por qué, acción en cocina. Sin finanzas complejas.
- encargada: qué empujar esta semana, mapeos faltantes, fugas por descuento.
- marketing: Enigmas y Estrellas a comunicar, cambios de cuadrante.
- sistema: solo JSON válido según el schema, sin texto.

Cada recomendación cierra con: RESPONSABLE · ACCIÓN · KPI · FECHA DE REVISIÓN.
Incluí siempre: evidencia, período, supuestos y nivel de confianza.
```

---

# ANEXO B — TEMPLATES (`prompts/templates/`)

## C1 — Informe semanal de control (por local)
```
audiencia: {{audiencia}}
local: {{local_nombre}} ({{marca}})
periodo: {{fecha_desde}} a {{fecha_hasta}}
cobertura_datos: {{cobertura_json}}       # % venta mapeada, platos sin receta, última sync
kpis: {{kpis_json}}                       # ventas netas, cubiertos, CM total, CM/cubierto vs objetivo, food cost ponderado
alarmas_abiertas: {{alarmas_json}}        # ordenadas por prioridad
platos_fuera_politica: {{platos_json}}
decisiones_revision_vencida: {{decisiones_json}}

Tarea: informe semanal para {{audiencia}}, máximo 1 página.
Empezá por lo que más plata cuesta. Cerrá con las 3 acciones de la semana.
```

## C2 — Matriz mensual de ingeniería de menú
```
audiencia: {{audiencia}}
nivel: {{local | marca | grupo}}
entidad: {{nombre}}
periodo: {{mes}}
canal: {{salon | delivery | todos}}
matriz: {{matriz_json}}       # por plato: cantidad, participación, cm_neta, cm_total, food_cost, cuadrante, cuadrante_anterior, pavesic, insumo_exclusivo, etiquetas, en_gracia, estado_clasificacion
cortes: {{cortes_json}}       # metodología activa, corte_popularidad, corte_cm
complejidad: {{complejidad_json}}
omnes: {{omnes_json}}

Tarea:
1. Por categoría: cuadrantes y qué cambió vs mes anterior.
2. Acción por plato según reglas de cuadrante.
3. Top 5 decisiones del mes por impacto $.
4. Si nivel = marca o grupo: comparar locales y señalar el mismo plato en distinto cuadrante.
```

## C3 — Propuesta de repreciación (requiere aprobación)
```
audiencia: direccion
local: {{local_nombre}}
motivo: {{deriva_costo | cm_bajo_piso | caballo_batalla | revision_periodica}}
candidatos: {{candidatos_json}}     # precio actual, costo al fijar, costo actual, deriva, cm, cuadrante, participación
escenarios: {{escenarios_json}}     # precios sugeridos por método, CM y volumen pesimista/base/optimista, supuestos de elasticidad
politicas: {{politicas_json}}

Tarea: tabla por plato con precio actual, precio propuesto (redondeo según política),
impacto mensual en CM en los 3 escenarios y riesgo. Recomendá cuáles aprobar ya,
cuáles esperar y cuáles resolver con reingeniería en vez de precio.
Terminá con: "PENDIENTE DE APROBACIÓN DE DIRECCIÓN".
Al final, JSON: [{ "plato_id", "precio_propuesto", "tipo_decision", "kpi_esperado", "fecha_revision" }]
```

## C4 — Interfaz a módulos operativos (audiencia: sistema)
```
audiencia: sistema
destino: {{salon | cocina | compras}}
local: {{local_id}}
semana: {{semana}}
datos: {{payload_json}}

Devolvé SOLO JSON válido:
salon   → { "platos_empujar": [{plato_id, motivo, guion_sugerencia}], "ticket_objetivo": num, "mix_objetivo_categoria": {categoria: pct} }
cocina  → { "mix_pronosticado": {dia: {plato_id: cantidad}}, "platos_reingenieria": [{plato_id, problema, objetivo_costo}], "bajas_programadas": [{plato_id, fecha}] }
compras → { "insumos_criticos": [{insumo_id, deriva, platos_afectados}], "insumos_exclusivos": [{insumo_id, plato_id}] }
```
