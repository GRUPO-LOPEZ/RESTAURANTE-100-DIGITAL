"use client";

import { Bar, BarChart, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

type Slice = { label: string; count: number };

// Cuántas recetas hay en cada estado del costo. Una sola serie: el nombre de cada estado está al lado
// de su barra, así que no hace falta leyenda, y el color no dice nada que el texto no diga. Barras en
// el tono fuerte de gráficos (3:1 sobre el fondo, ADR-0015). La misma información va en una tabla.
export function ReliabilityChart({ data }: { data: Slice[] }) {
  const total = data.reduce((sum, d) => sum + d.count, 0);
  return (
    <figure className="flex flex-col gap-2">
      <figcaption className="text-sm text-ink-muted">
        Recetas según qué tan confiable es su costo ({total} en total)
      </figcaption>
      <div className="h-56 w-full" aria-hidden="true">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={data}
            layout="vertical"
            margin={{ top: 0, right: 32, bottom: 0, left: 0 }}
            barCategoryGap={12}
            accessibilityLayer={false}
          >
            <XAxis type="number" hide allowDecimals={false} />
            <YAxis
              type="category"
              dataKey="label"
              width={136}
              tickLine={false}
              axisLine={false}
              tick={{ fill: "var(--color-ink)", fontSize: 14 }}
            />
            <Tooltip
              cursor={{ fill: "var(--color-line)", opacity: 0.4 }}
              contentStyle={{
                background: "var(--color-surface)",
                border: "1px solid var(--color-line)",
                borderRadius: 8,
                color: "var(--color-ink)",
                fontSize: 14,
              }}
              labelStyle={{ color: "var(--color-ink)", fontWeight: 500 }}
              itemStyle={{ color: "var(--color-ink)" }}
              formatter={(value) => [value === 1 ? "1 receta" : `${String(value)} recetas`, ""]}
              separator=""
            />
            <Bar
              dataKey="count"
              name="Recetas"
              fill="var(--color-chart-strong-1)"
              radius={[0, 4, 4, 0]}
              isAnimationActive={false}
            >
              <LabelList
                dataKey="count"
                position="right"
                style={{ fill: "var(--color-ink)", fontSize: 14 }}
              />
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <details className="text-sm text-ink">
        <summary className="inline-flex min-h-touch cursor-pointer items-center text-primary">
          Ver los números
        </summary>
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">Recetas en cada estado del costo</caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className="py-2 font-medium text-ink-muted">
                Estado
              </th>
              <th scope="col" className="py-2 font-medium text-ink-muted">
                Recetas
              </th>
            </tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.label} className="border-b border-line last:border-0">
                <th scope="row" className="py-2 font-normal">
                  {d.label}
                </th>
                <td className="py-2 tabular-nums">{d.count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </figure>
  );
}
