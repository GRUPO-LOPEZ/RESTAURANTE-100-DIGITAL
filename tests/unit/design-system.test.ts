// Rediseño (ADR-0036): navegación global, parámetros de los listados y métricas confiables.
import { describe, expect, it } from "vitest";

import { internalHref } from "@/lib/internal-href";
import { listHref, pageCount, parseList, rangeLabel, sortPatch } from "@/lib/list-params";
import { metricView } from "@/lib/metrics";
import {
  currentGroup,
  isCurrent,
  mobileItems,
  navFits,
  collapsedIconSize,
  navGroups,
  navHeight,
  type NavGroup,
  type NavMenus,
} from "@/lib/nav";

const none: NavMenus = {
  recipes: false,
  catalog: false,
  rubros: false,
  suppliers: false,
  priceLists: false,
  orders: false,
  receive: false,
  invoices: false,
  payments: false,
  purchasingBoard: false,
  inventory: false,
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
  it("arma los seis grupos, en orden (Compras, pedido de Joaco del 2026-11-18)", () => {
    const groups = navGroups(all, 3);
    expect(groups.map((g) => g.label)).toEqual([
      "Visión general",
      "Base de conocimiento",
      "Compras",
      "Gestión y análisis",
      "Control",
      "Administración",
    ]);
    expect(groups.flatMap((g) => g.items.map((i) => i.label))).toEqual([
      "Inicio",
      "Panel de control",
      "Recetas",
      "Materias primas",
      "Rubros",
      "Tablero de compras",
      "Proveedores",
      "Listas de precios",
      "Órdenes de compra",
      "Recepción",
      "Facturas",
      "Pagos",
      "Inventario",
      "Costos",
      "Reportes",
      "Calidad",
      "Aprobaciones",
      "Usuarios",
      "Roles y permisos",
      "Historial",
    ]);
    const control = groups.find((g) => g.label === "Control");
    expect(control?.items.find((i) => i.label === "Aprobaciones")?.count).toBe(3);
  });

  it("muestra solo lo que la persona puede usar, sin grupos vacíos", () => {
    // El cocinero ve las recetas y, sin editarlos, los rubros (ADR-0038) y los proveedores (ADR-0050).
    const cook = navGroups({ ...none, recipes: true, rubros: true, suppliers: true }, 0);
    expect(cook.map((g) => g.label)).toEqual(["Visión general", "Base de conocimiento", "Compras"]);
    expect(cook.flatMap((g) => g.items.map((i) => i.label))).toEqual([
      "Inicio",
      "Recetas",
      "Rubros",
      "Proveedores",
    ]);
  });

  it("sin avisos, Aprobaciones no lleva contador", () => {
    const item = navGroups(all, 0)
      .find((g) => g.label === "Control")
      ?.items.find((i) => i.label === "Aprobaciones");
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
    // El Tablero de compras está arriba de Pagos y Facturas: no se marca junto con ellos.
    expect(isCurrent("/compras", "/compras")).toBe(true);
    expect(isCurrent("/compras/pagos", "/compras")).toBe(false);
    expect(isCurrent("/compras/pagos", "/compras/pagos")).toBe(true);
  });
});

// Un menú de prueba con tantos grupos y accesos (los nombres no importan para el alto).
function menuOf(sizes: number[]): NavGroup[] {
  return sizes.map((n, g) => ({
    label: `Grupo ${g}`,
    items: Array.from({ length: n }, (_, i) => ({
      href: `/g${g}/${i}`,
      label: "x",
      icon: "home" as const,
    })),
  }));
}

describe("los grupos plegados (ADR-0057)", () => {
  it("el alto contado es el que se midió en la pantalla (1440 × 843)", () => {
    // Medidas reales de la barra lateral, 2026-11-17: Dirección 5 grupos y 15 accesos, Controller 5 y 13, Compras 4 y 10.
    expect(navHeight(menuOf([2, 4, 5, 2, 2]))).toBe(736);
    expect(navHeight(menuOf([1, 4, 5, 2, 1]))).toBe(656);
    expect(navHeight(menuOf([1, 4, 4, 1]))).toBe(508);
  });

  it("con pocos menús todo queda abierto; con muchos, se pliega", () => {
    // El cocinero, el jefe de cocina, los chefs y Compras entran abiertos en 843 de alto.
    expect(navFits(navGroups({ ...none, recipes: true, rubros: true, suppliers: true }, 0))).toBe(
      true,
    );
    expect(navFits(menuOf([1, 4, 4, 1]))).toBe(true);
    expect(navFits(menuOf([1, 4, 5, 1]))).toBe(true);
    // El Controller (656 px) ya no entra en 843; el superadmin, menos.
    expect(navFits(menuOf([1, 4, 5, 2, 1]))).toBe(false);
    expect(navFits(navGroups(all, 0))).toBe(false);
  });

  it("contraída, los íconos van de 36, 32 o 28 px según lo que entre (2026-11-18)", () => {
    // 15 accesos en 5 grupos: 15 × 36 + 4 = 544 px, entran en 634 con margen.
    expect(collapsedIconSize(menuOf([1, 4, 5, 2, 3]))).toBe(36);
    // 18 accesos (con Facturas): 18 × 36 + 5 = 653 px no entran; 18 × 32 + 5 = 581, sí.
    expect(collapsedIconSize(menuOf([2, 3, 6, 2, 2, 3]))).toBe(32);
    // El superadmin, con 20 (Pagos y el Tablero de compras): 20 × 32 + 5 = 645 no entran; 20 × 28 + 5 = 565, sí.
    expect(navGroups(all, 0).flatMap((g) => g.items)).toHaveLength(20);
    expect(collapsedIconSize(navGroups(all, 0))).toBe(28);
  });

  it("el grupo actual es el de la pantalla, también en sus pantallas internas", () => {
    const groups = navGroups(all, 0);
    expect(currentGroup(groups, "/compras/recepcion/abc")).toBe("Compras");
    expect(currentGroup(groups, "/costos")).toBe("Gestión y análisis");
    expect(currentGroup(groups, "/")).toBe("Visión general");
    expect(currentGroup(groups, "/usuarios/123")).toBe("Administración");
    expect(currentGroup(groups, "/mi-cuenta")).toBeNull();
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

  it("un dato vencido que además es crítico dice «Crítico», con su fecha", () => {
    expect(
      metricView({
        ...base,
        value: 3,
        total: 5,
        stale: true,
        asOf: "01/10/2026",
        status: "bad",
        statusLabel: "Crítico",
      }),
    ).toEqual({ value: "3", status: "bad", statusLabel: "Crítico", detail: "Dato del 01/10/2026" });
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
