// Navegación global (ADR-0036): los grupos de la barra lateral y los accesos de la barra inferior del celular.
// Sin acceso a la base: sale de los menús de la sesión (lib/auth/session.ts, getMenus) y se prueba con Vitest.
// La interfaz oculta lo que no corresponde; la seguridad real sigue en la base.

// La barra lateral contraída o expandida se guarda en el navegador (decisión de Joaco, 2026-11-09): un año,
// solo este sitio. Va acá y no en el componente: lo que exporta un archivo "use client" no llega al servidor como texto.
export const SIDEBAR_COOKIE = "lf_sidebar";

export type NavIcon =
  | "home"
  | "panel"
  | "recipes"
  | "ingredients"
  | "suppliers"
  | "priceLists"
  | "orders"
  | "receipts"
  | "inventory"
  | "rubros"
  | "costs"
  | "reports"
  | "quality"
  | "approvals"
  | "users"
  | "roles"
  | "history";

// "also": otras pantallas que cuentan como esta (Control abarca Aprobaciones y Calidad en el celular).
export type NavItem = {
  href: string;
  label: string;
  icon: NavIcon;
  count?: number;
  also?: string[];
};
export type NavGroup = { label: string; items: NavItem[] };

// Los menús que mira la navegación (un subconjunto de Menus, para no depender del servidor).
export type NavMenus = {
  recipes: boolean;
  catalog: boolean;
  rubros: boolean;
  suppliers: boolean;
  priceLists: boolean;
  orders: boolean;
  receive: boolean;
  inventory: boolean;
  costs: boolean;
  reports: boolean;
  quality: boolean;
  approvals: boolean;
  users: boolean;
  roles: boolean;
  audit: boolean;
  panel: boolean;
};

// Los grupos del prompt de rediseño, en su orden. Un grupo sin ítems no se muestra.
export function navGroups(menus: NavMenus, unread: number): NavGroup[] {
  const groups: NavGroup[] = [
    {
      label: "Visión general",
      items: [
        { href: "/", label: "Inicio", icon: "home" },
        ...(menus.panel
          ? [{ href: "/configuracion", label: "Panel de control", icon: "panel" as const }]
          : []),
      ],
    },
    {
      label: "Base de conocimiento",
      items: [
        ...(menus.recipes
          ? [{ href: "/recetas", label: "Recetas", icon: "recipes" as const }]
          : []),
        ...(menus.catalog
          ? [{ href: "/materias-primas", label: "Materias primas", icon: "ingredients" as const }]
          : []),
        ...(menus.rubros ? [{ href: "/rubros", label: "Rubros", icon: "rubros" as const }] : []),
      ],
    },
    {
      // Compras (Fase 3, pedido de Joaco del 2026-11-18, ADR-0057): todo el circuito en un grupo, en el orden en que
      // se trabaja. Facturas y Pagos (Prompts 5 y 6) se suman acá.
      label: "Compras",
      items: [
        // Proveedores (ADR-0050): los ve quien ve su ficha, también el cocinero.
        ...(menus.suppliers
          ? [{ href: "/proveedores", label: "Proveedores", icon: "suppliers" as const }]
          : []),
        // Listas de precios (ADR-0052): Compras y quien controla precios. El cocinero no.
        ...(menus.priceLists
          ? [
              {
                href: "/listas-de-precios",
                label: "Listas de precios",
                icon: "priceLists" as const,
              },
            ]
          : []),
        // Órdenes de compra (ADR-0053): quien pide (también el cocinero) y quien las controla.
        ...(menus.orders
          ? [{ href: "/compras/ordenes", label: "Órdenes de compra", icon: "orders" as const }]
          : []),
        // Recepción e inventario (ADR-0056): quien recibe en un local; el inventario, quien lo controla.
        ...(menus.receive
          ? [{ href: "/compras/recepcion", label: "Recepción", icon: "receipts" as const }]
          : []),
        ...(menus.inventory
          ? [{ href: "/inventario", label: "Inventario", icon: "inventory" as const }]
          : []),
      ],
    },
    {
      label: "Gestión y análisis",
      items: [
        ...(menus.costs ? [{ href: "/costos", label: "Costos", icon: "costs" as const }] : []),
        ...(menus.reports
          ? [{ href: "/reportes", label: "Reportes", icon: "reports" as const }]
          : []),
      ],
    },
    {
      label: "Control",
      items: [
        ...(menus.quality
          ? [{ href: "/calidad", label: "Calidad", icon: "quality" as const }]
          : []),
        ...(menus.approvals
          ? [
              {
                href: "/aprobaciones",
                label: "Aprobaciones",
                icon: "approvals" as const,
                ...(unread > 0 ? { count: unread } : {}),
              },
            ]
          : []),
      ],
    },
    {
      label: "Administración",
      items: [
        ...(menus.users ? [{ href: "/usuarios", label: "Usuarios", icon: "users" as const }] : []),
        ...(menus.roles
          ? [{ href: "/roles", label: "Roles y permisos", icon: "roles" as const }]
          : []),
        ...(menus.audit
          ? [{ href: "/historial", label: "Historial", icon: "history" as const }]
          : []),
      ],
    },
  ];
  return groups.filter((g) => g.items.length > 0);
}

// Grupos plegados (ADR-0057, decisión de Joaco del 2026-11-17): si el menú no entra abierto en la pantalla más baja
// medida (1715 × 843, ADR-0051), los grupos arrancan cerrados salvo el de la pantalla actual. Se cuenta en vez de medir
// en el navegador: el servidor y el navegador muestran lo mismo y no hay salto al cargar. Los altos son los de
// components/sidebar.tsx (medidos en la pantalla): título de grupo 28 px, acceso 36 px y 4 px entre cada cosa.
const NAV_ITEM = 36 + 4;
const NAV_GROUP_TITLE = 28;
// 843 de alto menos la barra de arriba (64), el pie (persona, Mi cuenta, Salir y Contraer: 149), los márgenes (16) y el
// margen del foco alrededor de la lista (8).
const NAV_ROOM = 843 - 64 - 149 - 16 - 8;
// En Linux la letra ocupa un poco más (Actions mide 8 a 10 px de más): se deja margen.
const NAV_MARGIN = 20;

export function navHeight(groups: NavGroup[]): number {
  const items = groups.reduce((n, g) => n + g.items.length, 0);
  return groups.length * NAV_GROUP_TITLE + items * NAV_ITEM - 4;
}

export function navFits(groups: NavGroup[]): boolean {
  return navHeight(groups) <= NAV_ROOM - NAV_MARGIN;
}

// El grupo de la pantalla actual (también en sus pantallas internas), o null si ninguno la tiene.
export function currentGroup(groups: NavGroup[], pathname: string): string | null {
  return (
    groups.find((g) =>
      g.items.some((i) => [i.href, ...(i.also ?? [])].some((h) => isCurrent(pathname, h))),
    )?.label ?? null
  );
}

// Barra inferior del celular: Inicio, Recetas, Reportes y Control (Aprobaciones o, si no, Calidad).
export function mobileItems(menus: NavMenus, unread: number): NavItem[] {
  const control: NavItem | null = menus.approvals
    ? {
        href: "/aprobaciones",
        label: "Control",
        icon: "approvals",
        ...(menus.quality ? { also: ["/calidad"] } : {}),
        ...(unread > 0 ? { count: unread } : {}),
      }
    : menus.quality
      ? { href: "/calidad", label: "Control", icon: "quality" }
      : null;
  return [
    { href: "/", label: "Inicio", icon: "home" },
    ...(menus.recipes ? [{ href: "/recetas", label: "Recetas", icon: "recipes" as const }] : []),
    ...(menus.reports ? [{ href: "/reportes", label: "Reportes", icon: "reports" as const }] : []),
    ...(control ? [control] : []),
  ];
}

// Los módulos, para la ruta de navegación (Grupo LF › módulo › pantalla). Solo nombres: no da acceso.
const MODULES: { href: string; label: string }[] = [
  { href: "/configuracion", label: "Panel de control" },
  { href: "/recetas", label: "Recetas" },
  { href: "/materias-primas", label: "Materias primas" },
  { href: "/rubros", label: "Rubros" },
  { href: "/proveedores", label: "Proveedores" },
  { href: "/costos", label: "Costos" },
  { href: "/listas-de-precios", label: "Listas de precios" },
  { href: "/compras/ordenes", label: "Órdenes de compra" },
  { href: "/reportes", label: "Reportes" },
  { href: "/calidad", label: "Calidad" },
  { href: "/aprobaciones", label: "Aprobaciones" },
  { href: "/usuarios", label: "Usuarios" },
  { href: "/roles", label: "Roles y permisos" },
  { href: "/historial", label: "Historial" },
  { href: "/mi-cuenta", label: "Mi cuenta" },
  { href: "/buscar", label: "Búsqueda" },
  { href: "/", label: "Inicio" },
];

export function moduleOf(pathname: string): { href: string; label: string } | null {
  return MODULES.find((m) => isCurrent(pathname, m.href)) ?? null;
}

// Si un ítem es la pantalla actual: el inicio solo en "/", el resto también en sus pantallas internas.
export function isCurrent(pathname: string, href: string): boolean {
  return href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);
}
