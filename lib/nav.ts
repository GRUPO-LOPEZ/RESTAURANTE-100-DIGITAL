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
  { href: "/costos", label: "Costos" },
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
