"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronRight } from "lucide-react";

import { moduleOf } from "@/lib/nav";

// Ruta de navegación (ADR-0036): Grupo LF › módulo › pantalla. El módulo sale de la dirección; la
// pantalla, del título que le pasa cada página a AppShell.
export function Breadcrumbs({ title }: { title: string }) {
  const pathname = usePathname();
  const mod = moduleOf(pathname);
  const crumbs: { href?: string; label: string }[] = [{ href: "/", label: "Grupo LF" }];
  if (mod && mod.href !== "/") {
    crumbs.push(
      pathname === mod.href ? { label: mod.label } : { href: mod.href, label: mod.label },
    );
  }
  if (!mod || pathname !== mod.href || title !== mod.label) {
    if (pathname !== "/" || title !== "Inicio") crumbs.push({ label: title });
  }
  // La última siempre es la pantalla actual, sin enlace.
  const last = crumbs.length - 1;
  return (
    <nav aria-label="Ruta" className="hidden min-w-0 desk:block">
      <ol className="flex min-w-0 items-center gap-1 text-sm">
        {crumbs.map((c, i) => (
          <li key={`${c.label}-${i}`} className="flex min-w-0 items-center gap-1">
            {i > 0 ? (
              <ChevronRight aria-hidden="true" className="size-4 shrink-0 text-ink-muted" />
            ) : null}
            {c.href && i !== last ? (
              <Link
                href={c.href}
                className="truncate text-ink-muted underline-offset-4 hover:text-ink hover:underline"
              >
                {c.label}
              </Link>
            ) : (
              <span
                aria-current={i === last ? "page" : undefined}
                className="truncate font-medium text-ink"
              >
                {c.label}
              </span>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}
