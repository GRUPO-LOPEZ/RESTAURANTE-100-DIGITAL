// Genera docs/modulos/diccionario-datos.md desde los `comment on` de la base LOCAL
// (database.md: "un diccionario de datos generado desde la base").
// Uso: npm run db:dictionary (con `npm run db:start` corriendo). Solo lee: no cambia la base.
// Con argumentos, otros esquemas y otro archivo:
//   node scripts/data-dictionary.mjs catalog,recipes docs/modulos/02-recetario-diccionario.md
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const SCHEMAS = process.argv[2]?.split(",") ?? ["core", "org", "audit", "workflow", "ai"];
const OUT = process.argv[3] ?? "docs/modulos/diccionario-datos.md";
// Contenedor de la base local de Supabase (project_id de supabase/config.toml).
const CONTAINER = "supabase_db_grupo-lf";

const query = `
with rels as (
  select c.oid, n.nspname as schema, c.relname as name, c.relkind as kind,
         obj_description(c.oid, 'pg_class') as comment
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = any (array['${SCHEMAS.join("','")}']) and c.relkind in ('r', 'p', 'v')
),
cols as (
  select r.oid, jsonb_agg(jsonb_build_object(
           'name', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
           'nullable', not a.attnotnull, 'comment', col_description(r.oid, a.attnum)) order by a.attnum) as columns
    from rels r join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
   group by r.oid
),
types as (
  select jsonb_agg(jsonb_build_object('name', n.nspname || '.' || t.typname,
           'values', (select string_agg(e.enumlabel, ', ' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid),
           'comment', obj_description(t.oid, 'pg_type')) order by n.nspname, t.typname) as list
    from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where t.typtype = 'e' and n.nspname = any (array['${SCHEMAS.join("','")}'])
)
select jsonb_build_object(
  'relations', (select jsonb_agg(jsonb_build_object('schema', r.schema, 'name', r.name, 'kind', r.kind,
                  'comment', r.comment, 'columns', c.columns) order by r.schema, r.name)
                  from rels r join cols c on c.oid = r.oid),
  'types', (select list from types))`;

const raw = execFileSync(
  "docker",
  ["exec", CONTAINER, "psql", "-U", "postgres", "-At", "-c", query],
  {
    encoding: "utf8",
  },
);
const data = JSON.parse(raw.trim());

const cell = (v) =>
  String(v ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\r?\n/g, " ");
const table = (header, rows) => {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => cell(r[i]).length)));
  const line = (r) => `| ${r.map((v, i) => cell(v).padEnd(widths[i])).join(" | ")} |`;
  return [
    line(header),
    `| ${widths.map((w) => "-".repeat(w)).join(" | ")} |`,
    ...rows.map(line),
  ].join("\n");
};

const today = new Date().toISOString().slice(0, 10);
const out = [
  `# Diccionario de datos — ${SCHEMAS.join(", ")}`,
  "",
  `> Generado desde los \`comment on\` de la base local el ${today} con \`npm run db:dictionary\`. No editar a mano: regenerar después de cada migración.`,
  "",
];
for (const r of data.relations) {
  out.push(
    `## \`${r.schema}.${r.name}\`${r.kind === "v" ? " (vista)" : ""}`,
    "",
    r.comment ?? "_Sin comentario._",
    "",
  );
  out.push(
    table(
      ["Columna", "Tipo", "Nulo", "Qué guarda"],
      r.columns.map((c) => [
        `\`${c.name}\``,
        `\`${c.type}\``,
        c.nullable ? "sí" : "no",
        c.comment ?? "",
      ]),
    ),
    "",
  );
}
out.push("## Tipos", "");
out.push(
  table(
    ["Tipo", "Valores", "Qué significa"],
    (data.types ?? []).map((t) => [
      `\`${t.name}\``,
      t.values
        .split(", ")
        .map((v) => `\`${v}\``)
        .join(", "),
      t.comment ?? "",
    ]),
  ),
  "",
);
writeFileSync(OUT, out.join("\n"));
console.log(
  `Diccionario: ${data.relations.length} tablas y vistas, ${(data.types ?? []).length} tipos.`,
);
