"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, Search, UserRound } from "lucide-react";

import { NavIconGlyph } from "@/components/nav-icon";
import { isCurrent, type NavGroup, type NavItem } from "@/lib/nav";
import { cn } from "@/lib/utils";

// Celular (menos de 800 px, ADR-0036). "Menú" abre la navegación completa debajo de la barra superior;
// al cambiar de pantalla se cierra, y Escape la cierra y devuelve el foco al botón.
export function MobileMenu({ groups, search }: { groups: NavGroup[]; search: boolean }) {
  const pathname = usePathname();
  const menu = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    if (menu.current) menu.current.open = false;
  }, [pathname]);
  return (
    <details
      ref={menu}
      className="group desk:hidden"
      onKeyDown={(event) => {
        if (event.key !== "Escape" || !menu.current?.open) return;
        menu.current.open = false;
        menu.current.querySelector("summary")?.focus();
      }}
    >
      <summary className="flex min-h-touch cursor-pointer list-none items-center gap-2 rounded-sm px-3 text-base font-medium text-ink hover:bg-line/50 [&::-webkit-details-marker]:hidden">
        <Menu aria-hidden="true" className="size-5" />
        Menú
      </summary>
      <div className="absolute inset-x-0 top-full z-40 max-h-[calc(100dvh-8rem)] overflow-y-auto border-b border-line bg-surface px-4 py-3">
        {search ? (
          <form
            action="/buscar"
            method="get"
            role="search"
            aria-label="Búsqueda global"
            className="mb-3 flex gap-2"
          >
            <input
              aria-label="Búsqueda global de recetas y materias primas"
              type="search"
              name="q"
              enterKeyHint="search"
              placeholder="Buscar recetas y materias primas"
              className="min-h-touch min-w-0 flex-1 rounded-sm border border-line bg-surface px-3 text-base text-ink placeholder:text-ink-muted"
            />
            <button
              type="submit"
              aria-label="Hacer la búsqueda"
              className="flex min-h-touch w-touch items-center justify-center rounded-sm border border-line bg-surface text-ink"
            >
              <Search aria-hidden="true" className="size-5" />
            </button>
          </form>
        ) : null}
        <nav aria-label="Menú principal" className="flex flex-col gap-3">
          {groups.map((g) => (
            <div key={g.label} className="flex flex-col gap-1">
              <p className="px-3 text-xs font-medium tracking-wide text-ink-muted uppercase">
                {g.label}
              </p>
              <ul className="flex flex-col gap-1">
                {g.items.map((i) => (
                  <li key={i.href}>
                    <MenuLink item={i} current={isCurrent(pathname, i.href)} />
                  </li>
                ))}
              </ul>
            </div>
          ))}
          <ul className="flex flex-col gap-1 border-t border-line pt-3">
            <li>
              <Link
                href="/mi-cuenta"
                aria-current={isCurrent(pathname, "/mi-cuenta") ? "page" : undefined}
                className={linkClass(isCurrent(pathname, "/mi-cuenta"))}
              >
                <UserRound aria-hidden="true" className="size-5 shrink-0" />
                Mi cuenta
              </Link>
            </li>
          </ul>
        </nav>
      </div>
    </details>
  );
}

function linkClass(current: boolean) {
  return cn(
    "flex min-h-touch items-center gap-3 rounded-sm px-3 text-base text-ink hover:bg-line/50",
    current && "bg-nav-active font-medium text-nav-active-ink",
  );
}

function MenuLink({ item, current }: { item: NavItem; current: boolean }) {
  return (
    <Link
      href={item.href}
      aria-current={current ? "page" : undefined}
      className={linkClass(current)}
    >
      <NavIconGlyph icon={item.icon} />
      <span className="flex-1">{item.label}</span>
      {item.count ? (
        <span className="rounded-sm bg-warn px-2 text-sm font-medium text-warn-ink tabular-nums">
          {item.count}
          <span className="sr-only"> avisos sin leer</span>
        </span>
      ) : null}
    </Link>
  );
}

// Barra inferior del celular: 4 accesos (Inicio, Recetas, Reportes, Control), al alcance del pulgar.
export function BottomNav({ items }: { items: NavItem[] }) {
  const pathname = usePathname();
  return (
    <nav
      aria-label="Navegación del celular"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface pb-[env(safe-area-inset-bottom)] desk:hidden print:hidden"
    >
      <ul className="flex">
        {items.map((i) => {
          const current = [i.href, ...(i.also ?? [])].some((h) => isCurrent(pathname, h));
          return (
            <li key={i.href} className="flex-1">
              <Link
                href={i.href}
                aria-current={current ? "page" : undefined}
                className={cn(
                  "relative flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs",
                  // La actual lleva una barra arriba y el ícono sobre fondo: no solo el color (WCAG 1.4.1).
                  current
                    ? "font-medium text-primary before:absolute before:inset-x-4 before:top-0 before:h-0.5 before:rounded-sm before:bg-primary"
                    : "text-ink-muted",
                )}
              >
                <span className={cn("rounded-sm px-3 py-0.5", current && "bg-nav-active")}>
                  <NavIconGlyph icon={i.icon} />
                </span>
                {i.label}
                {i.count ? (
                  <span className="absolute top-1 left-1/2 ml-2 rounded-sm bg-warn px-1 text-xs font-medium text-warn-ink tabular-nums">
                    {i.count}
                    <span className="sr-only"> avisos sin leer</span>
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
