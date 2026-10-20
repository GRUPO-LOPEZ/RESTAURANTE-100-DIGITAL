# Agentes de IA (prompt maestro, sección 11)

**Los agentes proponen y la gente decide.** Ningún agente modifica datos oficiales sin pasar por el flujo de aprobación que corresponda.

- Cada agente tiene su propia cuenta técnica en `core.service_accounts`, con permisos mínimos y explícitos.
- Toda corrida queda en `ai.agent_runs`: agente, versión, quién la pidió, datos usados, resultado, duración y errores.
- Lo que el agente quiere cambiar queda como propuesta en `ai.agent_proposals`, vinculada a una solicitud de aprobación (`workflow.approval_requests`).
- Cada propuesta muestra el valor actual, el propuesto, la diferencia y la fuente (por ejemplo, la factura escaneada).
- Los agentes leen del esquema `reporting` y escriben **solo** en `ai`. **Nunca tocan `audit` ni `core`.**
- Las claves de los modelos de IA viven en funciones de servidor, nunca en el navegador.

| Agente | Lee | Propone |
|---|---|---|
| Facturas | Facturas en Storage, proveedores | Precios nuevos de materias primas |
| Costos | Recetas, precios vigentes | Alertas de desvío de costo y margen |
| Inventario | Movimientos y conteos | Diferencias de stock y pedidos sugeridos |
| Producción | Ventas y planes | Plan de producción del día |
| Reputación | Reseñas públicas | Resumen semanal y alertas |
| Dirección | Todo reporting | Resumen ejecutivo para Soy |

**Los agentes se construyen recién en la Fase 5**, cuando los datos que leen ya son confiables. Antes de eso no se crea código de agentes.
