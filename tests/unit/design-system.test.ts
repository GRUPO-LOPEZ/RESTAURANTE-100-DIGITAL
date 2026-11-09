// Rediseño (ADR-0036): navegación global, parámetros de los listados y métricas confiables.
import { describe, expect, it } from "vitest";

import { internalHref } from "@/lib/internal-href";
import { listHref, pageCount, parseList, rangeLabel, sortPatch } from "@/lib/list-params";
import { metricView } from "@/lib/metrics";
import { isCurrent, mobileItems, navGroups, type NavMenus } from "@/lib/nav";

const none: NavMenus = {
  recipes: false,
  catalog: false,
  costs: false,
  reports: false,
  quality: false,
  approvals: false,
  users: false,
  roles: false,
  audit: false,
  panel: false,
};
const all: NavMenus = Object.fromEntries(Object.keys(none).map((k) => [k, true])) as NavMenus;

describe("la navegación global", () => {
  it("arma los cinco grupos del prompt, en orden", () => {
    const groups = navGroups(all, 3);
    expect(groups.map((g) => g.label)).toEqual([
      "Visión general",
      "Base de conocimiento",
      "Gestión y análisis",
      "Control",
      "Administración",
    ]);
    expect(groups.flatMap((g) => g.items.map((i) => i.label))).toEqual([
      "Inicio",
      "Panel de control",
      "Recetas",
      "Materias primas",
      "Costos",
      "Reportes",
      "Calidad",
      "Aprobaciones",
      "Usuarios",
      "Roles y permisos",
      "Historial",
    ]);
    expect(groups[3]?.items.find((i) => i.label === "Aprobaciones")?.count).toBe(3);
  });

  it("muestra solo lo que la persona puede usar, sin grupos vacíos", () => {
    const cook = navGroups({ ...none, recipes: true }, 0);
    expect(cook.map((g) => g.label)).toEqual(["Visión general", "Base de conocimiento"]);
    expect(cook.flatMap((g) => g.items.map((i) => i.label))).toEqual(["Inicio", "Recetas"]);
  });

  it("sin avisos, Aprobaciones no lleva contador", () => {
    const item = navGroups(all, 0)[3]?.items.find((i) => i.label === "Aprobaciones");
    expect(item && "count" in item).toBe(false);
  });

  it("en el celular: Inicio, Recetas, Reportes y Control", () => {
    expect(mobileItems(all, 2).map((i) => [i.label, i.href])).toEqual([
      ["Inicio", "/"],
      ["Recetas", "/recetas"],
      ["Reportes", "/reportes"],
      ["Control", "/aprobaciones"],
    ]);
    // Sin aprobaciones, Control lleva a Calidad; sin ninguna de las dos, no aparece.
    expect(mobileItems({ ...all, approvals: false }, 0).at(-1)?.href).toBe("/calidad");
    expect(mobileItems(none, 0).map((i) => i.label)).toEqual(["Inicio"]);
  });

  it("marca la pantalla actual, también en sus pantallas internas", () => {
    expect(isCurrent("/", "/")).toBe(true);
    expect(isCurrent("/recetas", "/")).toBe(false);
    expect(isCurrent("/recetas/123/cocina", "/recetas")).toBe(true);
    expect(isCurrent("/recetasx", "/recetas")).toBe(false);
  });
});

describe("los parámetros de un listado", () => {
  it("lee página, filas y orden, y vuelve a lo de siempre si no se entienden", () => {
    expect(parseList({}, ["nombre"])).toEqual({ page: 1, size: 15, sort: null, dir: "asc" });
    expect(parseList({ pagina: "3", filas: "25", orden: "-nombre" }, ["nombre"])).toEqual({
      page: 3,
      size: 25,
      sort: "nombre",
      dir: "desc",
    });
    expect(
      parseList({ pagina: "-2", filas: "7", orden: "inventado" }, ["nombre"], "-fecha"),
    ).toEqual({
      page: 1,
      size: 15,
      sort: "fecha",
      dir: "desc",
    });
  });

  it("al ordenar por la misma columna, invierte; y vuelve a la primera página", () => {
    const asc = parseList({ orden: "nombre", pagina: "4" }, ["nombre", "fecha"]);
    expect(sortPatch(asc, "nombre")).toEqual({ orden: "-nombre", pagina: undefined });
    expect(sortPatch(asc, "fecha")).toEqual({ orden: "fecha", pagina: undefined });
  });

  it("arma la dirección conservando los filtros", () => {
    expect(listHref("/recetas", { q: "salsa", pagina: "2" }, { pagina: "3" })).toBe(
      "/recetas?q=salsa&pagina=3",
    );
    expect(listHref("/recetas", { q: "salsa" }, { q: undefined })).toBe("/recetas");
  });

  it("cuenta páginas y dice qué filas se ven", () => {
    expect(pageCount(0, 15)).toBe(1);
    expect(pageCount(31, 15)).toBe(3);
    expect(rangeLabel(parseList({ pagina: "2" }, []), 42, 15)).toBe("Filas 16 a 30 de 42");
    expect(rangeLabel(parseList({}, []), 0, 0)).toBe("Sin registros");
  });
});

describe("las métricas confiables", () => {
  const base = {
    emptyLabel: "Sin recetas con costo calculado",
    status: "ok",
    statusLabel: "Al día",
  } as const;

  it("sin denominador nunca dice «al día» ni 0 %", () => {
    expect(metricView({ ...base, value: 0, total: 0 })).toEqual({
      value: "—",
      status: "none",
      statusLabel: "Sin datos",
      detail: "Sin recetas con costo calculado",
    });
  });

  it("un dato que falta se muestra con «—» y el motivo", () => {
    expect(metricView({ ...base, value: null, missingReason: "Falta el precio." })).toMatchObject({
      value: "—",
      status: "none",
      detail: "Falta el precio.",
    });
  });

  it("un cero real se muestra como cero, con el estado de la regla", () => {
    expect(metricView({ ...base, value: 0, total: 12 })).toMatchObject({
      value: "0",
      status: "ok",
    });
  });

  it("un dato vencido muestra el valor, su fecha y «Desactualizado»", () => {
    expect(metricView({ ...base, value: 1234, total: 5, stale: true, asOf: "01/10/2026" })).toEqual(
      {
        value: "1.234",
        status: "warn",
        statusLabel: "Desactualizado",
        detail: "Dato del 01/10/2026",
      },
    );
  });
});

describe("los enlaces de los componentes", () => {
  it("solo van a rutas internas", () => {
    expect(internalHref("/costos?local=1")).toBe("/costos?local=1");
    expect(internalHref("//sitio-malo.com")).toBe("/");
    // "/\" también: algunos navegadores lo leen como "//".
    expect(internalHref("/\\sitio-malo.com")).toBe("/");
    expect(internalHref("https://sitio-malo.com")).toBe("/");
    expect(listHref("//sitio-malo.com", {}, { pagina: "2" })).toBe("/?pagina=2");
  });
});
