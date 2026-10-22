"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu } from "lucide-react";

export type NavLink = { href: string; label: string; count?: number };

function isCurrent(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);
}

function Links({ links, pathname }: { links: NavLink[]; pathname: string }) {
  return links.map((l) => {
    const current = isCurrent(pathname, l.href);
    return (
      <Link
        key={l.href}
        href={l.href}
        aria-current={current ? "page" : undefined}
        className={`flex min-h-touch items-center gap-2 rounded-sm px-3 text-base text-ink hover:bg-line/50 ${
          current ? "bg-line/50 font-medium" : ""
        }`}
      >
        {l.label}
        {l.count ? (
          <span className="rounded-sm bg-info px-2 text-sm font-medium text-info-ink tabular-nums">
            {l.count}
            <span className="sr-only"> avisos sin leer</span>
          </span>
        ) : null}
      </Link>
    );
  });
}

// Menú principal. En el celular va detrás de un botón "Menú" para que el contenido quede a la vista
// (celular primero); en pantallas más anchas se ve completo. La pantalla actual va marcada.
export function MainNav({ links }: { links: NavLink[] }) {
  const pathname = usePathname();
  return (
    <>
      <details className="group w-full sm:hidden">
        <summary className="flex min-h-touch cursor-pointer list-none items-center gap-2 rounded-sm px-3 text-base font-medium text-ink hover:bg-line/50">
          <Menu aria-hidden="true" className="size-5" />
          Menú
        </summary>
        <nav aria-label="Menú principal" className="flex flex-col gap-1 py-2">
          <Links links={links} pathname={pathname} />
        </nav>
      </details>
      <nav aria-label="Menú principal" className="hidden flex-wrap items-center gap-1 sm:flex">
        <Links links={links} pathname={pathname} />
      </nav>
    </>
  );
}
