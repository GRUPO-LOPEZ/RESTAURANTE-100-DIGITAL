"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronDown, LogOut, PanelLeftClose, PanelLeftOpen, UserRound } from "lucide-react";

import { signOut } from "@/app/ingresar/actions";
import { NavIconGlyph } from "@/components/nav-icon";
import { SIDEBAR_COOKIE, isCurrent, type NavGroup } from "@/lib/nav";
import { cn } from "@/lib/utils";

// Barra lateral fija (ADR-0036), desde 800 px: 240 px expandida o 68 px solo con íconos. Logo arriba;
// grupos plegables (antes que scroll); usuario, Mi cuenta y Salir abajo. El activo va marcado.
export function Sidebar({
  groups,
  collapsedInitial,
  person,
}: {
  groups: NavGroup[];
  collapsedInitial: boolean;
  person: string;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(collapsedInitial);
  const toggle = () => {
    const next = !collapsed;
    setCollapsed(next);
    document.cookie = `${SIDEBAR_COOKIE}=${next ? "collapsed" : "expanded"}; path=/; max-age=31536000; samesite=lax${location.protocol === "https:" ? "; secure" : ""}`;
  };
  const item = (current: boolean) =>
    cn(
      "flex min-h-control-sm items-center gap-3 rounded-sm px-3 text-sm",
      current
        ? "bg-nav-active font-medium text-nav-active-ink"
        : "text-nav-ink hover:bg-nav-ink/10",
      collapsed && "justify-center px-0",
    );

  return (
    <aside
      data-sidebar={collapsed ? "collapsed" : "expanded"}
      className={cn(
        // El foco usa el color claro: el azul principal no llega a 3:1 sobre la barra oscura (WCAG 1.4.11).
        "fixed inset-y-0 left-0 z-30 hidden flex-col bg-nav text-nav-ink desk:flex print:hidden [&_*:focus-visible]:outline-nav-active",
        collapsed ? "w-sidebar-collapsed" : "w-sidebar",
      )}
    >
      <div
        className={cn(
          "flex h-topbar shrink-0 items-center gap-2 px-4",
          collapsed && "justify-center px-0",
        )}
      >
        <Link
          href="/"
          className="flex min-h-control items-center gap-2 rounded-sm font-semibold text-nav-active"
        >
          <span
            aria-hidden="true"
            className="flex size-8 items-center justify-center rounded-sm bg-nav-active text-sm text-nav-active-ink"
          >
            LF
          </span>
          <span className={collapsed ? "sr-only" : "text-base"}>Grupo LF</span>
        </Link>
      </div>
      <nav aria-label="Menú principal" className="flex min-h-0 flex-1 flex-col gap-1 px-3 pb-3">
        <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto">
          {groups.map((g) =>
            collapsed ? (
              <ul
                key={g.label}
                className="flex flex-col gap-1 border-t border-nav-ink/15 pt-2 first:border-0 first:pt-0"
              >
                {g.items.map((i) => (
                  <li key={i.href}>
                    <Link
                      href={i.href}
                      aria-current={isCurrent(pathname, i.href) ? "page" : undefined}
                      aria-label={i.count ? `${i.label} (${i.count} avisos sin leer)` : i.label}
                      title={i.label}
                      className={cn(item(isCurrent(pathname, i.href)), "relative")}
                    >
                      <NavIconGlyph icon={i.icon} />
                      {i.count ? (
                        <span
                          aria-hidden="true"
                          className="absolute top-1 right-2 size-2 rounded-full bg-warn"
                        />
                      ) : null}
                    </Link>
                  </li>
                ))}
              </ul>
            ) : (
              <details key={g.label} open className="group/navgroup">
                <summary className="flex min-h-control-sm cursor-pointer list-none items-center justify-between rounded-sm px-3 text-xs font-medium tracking-wide text-nav-ink/80 uppercase hover:text-nav-active [&::-webkit-details-marker]:hidden">
                  {g.label}
                  <ChevronDown
                    aria-hidden="true"
                    className="size-4 transition-transform group-open/navgroup:rotate-180"
                  />
                </summary>
                <ul className="flex flex-col gap-1">
                  {g.items.map((i) => (
                    <li key={i.href}>
                      <Link
                        href={i.href}
                        aria-current={isCurrent(pathname, i.href) ? "page" : undefined}
                        className={item(isCurrent(pathname, i.href))}
                      >
                        <NavIconGlyph icon={i.icon} />
                        <span className="flex-1">{i.label}</span>
                        {i.count ? (
                          <span className="rounded-sm bg-warn px-1.5 text-xs font-medium text-warn-ink tabular-nums">
                            {i.count}
                            <span className="sr-only"> avisos sin leer</span>
                          </span>
                        ) : null}
                      </Link>
                    </li>
                  ))}
                </ul>
              </details>
            ),
          )}
        </div>
        <div className="flex flex-col gap-1 border-t border-nav-ink/15 pt-3">
          {collapsed ? null : (
            <p className="truncate px-3 text-xs text-nav-ink/80" title={person}>
              {person}
            </p>
          )}
          <Link
            href="/mi-cuenta"
            aria-current={isCurrent(pathname, "/mi-cuenta") ? "page" : undefined}
            aria-label={collapsed ? "Mi cuenta" : undefined}
            title={collapsed ? "Mi cuenta" : undefined}
            className={item(isCurrent(pathname, "/mi-cuenta"))}
          >
            <UserRound aria-hidden="true" className="size-5 shrink-0" />
            {collapsed ? null : "Mi cuenta"}
          </Link>
          <form action={signOut}>
            <button
              type="submit"
              aria-label={`Salir (${person})`}
              title={collapsed ? "Salir" : undefined}
              className={cn(item(false), "w-full")}
            >
              <LogOut aria-hidden="true" className="size-5 shrink-0" />
              {collapsed ? null : "Salir"}
            </button>
          </form>
          <button
            type="button"
            onClick={toggle}
            aria-label={collapsed ? "Expandir el menú" : "Contraer el menú"}
            title={collapsed ? "Expandir el menú" : "Contraer el menú"}
            className={cn(item(false), "w-full")}
          >
            {collapsed ? (
              <PanelLeftOpen aria-hidden="true" className="size-5 shrink-0" />
            ) : (
              <PanelLeftClose aria-hidden="true" className="size-5 shrink-0" />
            )}
            {collapsed ? null : "Contraer"}
          </button>
        </div>
      </nav>
    </aside>
  );
}
