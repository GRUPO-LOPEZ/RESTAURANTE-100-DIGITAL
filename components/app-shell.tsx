import * as React from "react";
import Link from "next/link";
import { cookies } from "next/headers";
import { Suspense } from "react";
import { Bell, LogOut, Search } from "lucide-react";

import { signOut } from "@/app/ingresar/actions";
import { Breadcrumbs } from "@/components/breadcrumbs";
import { BottomNav, MobileMenu } from "@/components/mobile-nav";
import { PageHeader } from "@/components/ui/page-header";
import { LoadingState } from "@/components/ui/states";
import { RestaurantSelector } from "@/components/restaurant-selector";
import { Sidebar } from "@/components/sidebar";
import { Button } from "@/components/ui/button";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";
import { getActiveRestaurantId, getMyScopes, getUnreadCount } from "@/lib/data";
import { SIDEBAR_COOKIE, mobileItems, navGroups } from "@/lib/nav";

// Layout global (ADR-0036), un solo componente para todo el sistema:
// - barra lateral fija desde 800 px (240 o 68 px), con los grupos según los permisos;
// - barra superior fija de 64 px: ruta, selector global de local, búsqueda, avisos y perfil;
// - área principal fluida, sin ancho máximo, con márgenes de 32 px (45 px desde 1700 px);
// - en el celular, "Menú" arriba y una barra inferior con 4 accesos.
// Lo que lee la sesión va detrás de Suspense (Cache Components): el resto se arma de antemano.
export function AppShell({
  title,
  heading,
  description,
  actions,
  children,
}: {
  title: string;
  // El h1 de una ficha: el nombre del registro (el título queda en la ruta de navegación).
  heading?: React.ReactNode;
  description?: string;
  // La acción principal de la pantalla, a la derecha del título (mismo lugar en todo el sistema).
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-col">
      <Suspense fallback={<SidebarPlaceholder />}>
        <SessionSidebar />
      </Suspense>
      <div className="lf-main flex min-h-full flex-1 flex-col">
        <header className="sticky top-0 z-40 border-b border-line bg-surface print:hidden">
          <div className="relative flex min-h-topbar flex-wrap items-center gap-2 px-4 py-2 desk:flex-nowrap desk:px-gutter desk:py-0 wide:px-gutter-wide">
            <Link
              href="/"
              className="mr-auto flex min-h-touch items-center text-base font-semibold text-ink desk:hidden"
            >
              Grupo LF
            </Link>
            <div className="hidden min-w-0 flex-1 desk:block">
              {/* La ruta lee la dirección: en las pantallas con parámetros llega después del resto. */}
              <Suspense
                fallback={
                  <p className="truncate text-sm text-ink-muted">
                    Grupo LF › <span className="font-medium text-ink">{title}</span>
                  </p>
                }
              >
                <Breadcrumbs title={title} />
              </Suspense>
            </div>
            <Suspense fallback={<span className="text-sm text-ink-muted">Cargando…</span>}>
              <SessionTopbar />
            </Suspense>
          </div>
        </header>
        <main className="flex w-full flex-1 flex-col gap-6 px-4 pt-6 pb-24 desk:px-gutter desk:pb-8 wide:px-gutter-wide print:p-0">
          <PageHeader title={title} heading={heading} description={description} actions={actions} />
          {children}
        </main>
      </div>
      <Suspense>
        <SessionBottomNav />
      </Suspense>
    </div>
  );
}

// Mientras llega la sesión: el lugar de la barra lateral, para que la pantalla no salte.
function SidebarPlaceholder() {
  return (
    <div
      aria-hidden="true"
      className="fixed inset-y-0 left-0 z-30 hidden w-sidebar bg-nav desk:block print:hidden"
    />
  );
}

async function SessionSidebar() {
  const session = await requireOperable();
  const [menus, unread, jar] = await Promise.all([getMenus(), getUnreadCount(), cookies()]);
  return (
    <Sidebar
      groups={navGroups(menus, unread)}
      collapsedInitial={jar.get(SIDEBAR_COOKIE)?.value === "collapsed"}
      person={displayName(session)}
    />
  );
}

async function SessionBottomNav() {
  await requireOperable();
  const [menus, unread] = await Promise.all([getMenus(), getUnreadCount()]);
  return <BottomNav items={mobileItems(menus, unread)} />;
}

async function SessionTopbar() {
  const session = await requireOperable();
  const [menus, scopes, activeId, unread] = await Promise.all([
    getMenus(),
    getMyScopes(),
    getActiveRestaurantId(session.user_id),
    getUnreadCount(),
  ]);
  const search = menus.recipes || menus.catalog;
  const person = displayName(session);
  return (
    <>
      {/* Celular: "Menú" arriba, con Mi cuenta y "Salir" adentro (design.md); el selector de local, a todo
          el ancho debajo. */}
      <MobileMenu
        groups={navGroups(menus, unread)}
        search={search}
        signOut={
          <form action={signOut}>
            <Button
              type="submit"
              variant="ghost"
              aria-label={`Salir (${person})`}
              className="w-full justify-start gap-3 px-3 text-base font-normal"
            >
              <LogOut aria-hidden="true" className="size-5" />
              Salir
            </Button>
          </form>
        }
      />
      {scopes.length > 1 ? (
        <RestaurantSelector
          value={scopes.some((s) => s.restaurant_id === activeId) ? activeId : null}
          options={scopes.map((s) => ({
            id: s.restaurant_id,
            label: `${s.restaurant_name} · ${s.brand_code}`,
          }))}
        />
      ) : null}
      {search ? (
        <form
          action="/buscar"
          method="get"
          role="search"
          aria-label="Búsqueda global"
          className="hidden min-w-0 items-center xl:flex"
        >
          <div className="relative">
            <Search
              aria-hidden="true"
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-ink-muted"
            />
            <input
              aria-label="Búsqueda global de recetas y materias primas"
              type="search"
              name="q"
              enterKeyHint="search"
              placeholder="Buscar recetas y materias primas"
              className="min-h-control w-72 min-w-0 rounded-sm border border-line bg-app pr-3 pl-9 text-sm text-ink placeholder:text-ink-muted"
            />
          </div>
        </form>
      ) : null}
      {search ? (
        <Link
          href="/buscar"
          title="Buscar"
          className="hidden min-h-control w-control shrink-0 items-center justify-center rounded-sm text-ink hover:bg-line/50 desk:flex xl:hidden"
        >
          <Search aria-hidden="true" className="size-5" />
          <span className="sr-only">Ir a la búsqueda global</span>
        </Link>
      ) : null}
      {menus.approvals ? (
        <Link
          href="/aprobaciones"
          title="Avisos"
          className="relative hidden min-h-control w-control shrink-0 items-center justify-center rounded-sm text-ink hover:bg-line/50 desk:flex"
        >
          <Bell aria-hidden="true" className="size-5" />
          {/* El nombre va como texto para lectores de pantalla (WCAG 2.5.3): el número visible es decorativo. */}
          <span className="sr-only">{unread > 0 ? `Avisos (${unread} sin leer)` : "Avisos"}</span>
          {unread > 0 ? (
            <span
              aria-hidden="true"
              className="absolute top-0.5 right-0.5 rounded-sm bg-warn px-1 text-xs font-medium text-warn-ink tabular-nums"
            >
              {unread > 99 ? "99+" : unread}
            </span>
          ) : null}
        </Link>
      ) : null}
      <Link
        href="/mi-cuenta"
        title={person}
        className="hidden min-h-control shrink-0 items-center gap-2 rounded-sm px-2 text-sm text-ink hover:bg-line/50 desk:flex"
      >
        <span
          aria-hidden="true"
          className="flex size-8 items-center justify-center rounded-full bg-nav-active text-xs font-medium text-nav-active-ink"
        >
          {initials(person)}
        </span>
        <span className="sr-only">Perfil de {person}</span>
      </Link>
    </>
  );
}

function initials(name: string): string {
  const parts = name.split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase() || "LF";
}

// Lo de siempre de las pantallas: el mismo estado de carga de la biblioteca.
export function Loading({ label = "Cargando…" }: { label?: string }) {
  return <LoadingState label={label} />;
}
