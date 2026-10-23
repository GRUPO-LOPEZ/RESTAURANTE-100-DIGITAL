"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

type Day = { day: string; succeeded: number; failed: number };

function shortDay(day: string): string {
  const [, m, d] = day.slice(0, 10).split("-");
  return `${d}/${m}`;
}

// Gráfico principal del tablero: accesos por día (sección 9). Dos series con leyenda de texto, y
// los valores al pasar el dedo o el mouse. Las barras usan los tonos fuertes de gráficos (3:1 sobre
// el fondo, ADR-0015); la leyenda va en el color de texto, y la misma información va en una tabla
// (visible con "Ver los números") y para lectores de pantalla.
// Con períodos largos, una barra por día no se distingue en el celular: se agrupa por semana.
const WEEKLY_AFTER_DAYS = 45;

export function LoginsByDayChart({ data }: { data: Day[] }) {
  const weekly = data.length > WEEKLY_AFTER_DAYS;
  const rows = weekly
    ? Array.from({ length: Math.ceil(data.length / 7) }, (_, i) => {
        const week = data.slice(i * 7, i * 7 + 7);
        return {
          day: week[0]?.day ?? "",
          label: `Semana del ${shortDay(week[0]?.day ?? "")}`,
          succeeded: week.reduce((s, d) => s + d.succeeded, 0),
          failed: week.reduce((s, d) => s + d.failed, 0),
        };
      })
    : data.map((d) => ({ ...d, label: shortDay(d.day) }));
  return (
    <figure className="flex flex-col gap-2">
      <figcaption className="text-sm text-ink-muted">
        Ingresos {weekly ? "por semana" : "por día"}: buenos y fallidos (contraseña o código
        incorrectos, o cuenta bloqueada)
      </figcaption>
      <div className="h-64 w-full" aria-hidden="true">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={rows} margin={{ top: 8, right: 8, bottom: 8, left: 0 }} barGap={2}>
            <CartesianGrid vertical={false} stroke="var(--color-line)" />
            <XAxis
              dataKey="label"
              tickLine={false}
              axisLine={{ stroke: "var(--color-line)" }}
              tick={{ fill: "var(--color-ink-muted)", fontSize: 14 }}
              interval="preserveStartEnd"
              minTickGap={24}
            />
            <YAxis
              allowDecimals={false}
              tickLine={false}
              axisLine={false}
              width={40}
              tick={{ fill: "var(--color-ink-muted)", fontSize: 14 }}
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
            />
            <Legend
              verticalAlign="top"
              align="left"
              iconType="square"
              wrapperStyle={{ color: "var(--color-ink)", fontSize: 14, paddingBottom: 8 }}
              // Los tonos fuertes son solo para las barras: el texto va en el color de texto.
              formatter={(value: string) => <span className="text-ink">{value}</span>}
            />
            <Bar
              dataKey="succeeded"
              name="Ingresos buenos"
              fill="var(--color-chart-strong-1)"
              radius={[4, 4, 0, 0]}
              isAnimationActive={false}
            />
            <Bar
              dataKey="failed"
              name="Ingresos fallidos"
              fill="var(--color-chart-strong-4)"
              radius={[4, 4, 0, 0]}
              isAnimationActive={false}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <details className="text-sm">
        <summary className="flex min-h-touch cursor-pointer items-center text-primary underline-offset-4 hover:underline">
          Ver los números
        </summary>
        <div className="max-h-72 overflow-y-auto">
          <table className="w-full text-left tabular-nums">
            <thead>
              <tr className="border-b border-line text-ink-muted">
                <th scope="col" className="py-1 font-medium">
                  {weekly ? "Semana" : "Día"}
                </th>
                <th scope="col" className="py-1 text-right font-medium">
                  Buenos
                </th>
                <th scope="col" className="py-1 text-right font-medium">
                  Fallidos
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.day} className="border-b border-line last:border-0">
                  <th scope="row" className="py-1 font-normal text-ink">
                    {r.label}
                  </th>
                  <td className="py-1 text-right text-ink">{r.succeeded}</td>
                  <td className="py-1 text-right text-ink">{r.failed}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </figure>
  );
}
