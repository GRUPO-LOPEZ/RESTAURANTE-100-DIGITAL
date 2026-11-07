import Link from "next/link";
import { Suspense } from "react";
import { BookOpen, ClipboardCheck, History, KeyRound, Users } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { HomeBoardView } from "@/components/home-board";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { pickCostPlace } from "@/lib/costs";
import { first, getActiveRestaurantId, getUser, scopeLabel } from "@/lib/data";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";
import { getQualityPlaces } from "@/lib/quality";

export default function InicioPage({ searchParams }: PageProps<"/">) {
  return (
    <AppShell title="Inicio">
      <Suspense fallback={<Loading />}>
        <Home searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Home({ searchParams }: { searchParams: PageProps<"/">["searchParams"] }) {
  const session = await requireOperable();
  const [me, menus, params] = await Promise.all([
    getUser(session.user_id ?? ""),
    getMenus(),
    searchParams,
  ]);
  // El tablero, para quien entra a la calidad de datos. El cocinero ve el Inicio de siempre.
  const [places, activeId] = menus.quality
    ? await Promise.all([getQualityPlaces(), getActiveRestaurantId(session.user_id)])
    : [[], null];
  const place = pickCostPlace(places, first(params.local), activeId);

  const shortcuts = [
    {
      href: "/recetas",
      label: "Recetas",
      text: "Las recetas vigentes y su ficha de cocina.",
      Icon: BookOpen,
      show: menus.recipes,
    },
    {
      href: "/usuarios",
      label: "Usuarios",
      text: "Quién tiene acceso y qué está pasando.",
      Icon: Users,
      show: menus.users,
    },
    {
      href: "/aprobaciones",
      label: "Aprobaciones",
      text: "Pedidos que esperan una decisión.",
      Icon: ClipboardCheck,
      show: menus.approvals,
    },
    {
      href: "/historial",
      label: "Historial",
      text: "Quién cambió qué, cuándo y por qué.",
      Icon: History,
      show: menus.audit,
    },
    {
      href: "/roles",
      label: "Roles y permisos",
      text: "Qué puede hacer cada rol.",
      Icon: KeyRound,
      show: menus.roles,
    },
  ].filter((s) => s.show);

  return (
    <>
      {places.length > 0 ? (
        <p className="text-base text-ink">
          Hola, {displayName(session)}
          <span className="text-ink-muted">
            {(me?.roles ?? []).map(
              (r) => ` · ${r.role_name}, ${scopeLabel(r.scope_type, r.scope_name)}`,
            )}
          </span>
        </p>
      ) : (
        <Card className="flex flex-col gap-2">
          <CardTitle>Hola, {displayName(session)}</CardTitle>
          <CardDescription>Estos son tus roles y dónde los tenés.</CardDescription>
          <ul className="flex flex-col gap-1">
            {(me?.roles ?? []).map((r) => (
              <li key={r.assignment_id} className="text-base text-ink">
                {r.role_name}{" "}
                <span className="text-ink-muted">· {scopeLabel(r.scope_type, r.scope_name)}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
      {places.length > 0 ? (
        <HomeBoardView places={places} place={place} approvals={menus.approvals} />
      ) : null}
      {shortcuts.length > 0 ? (
        <nav aria-label="Accesos" className="grid gap-4 sm:grid-cols-3">
          {shortcuts.map(({ href, label, text, Icon }) => (
            <Link
              key={href}
              href={href}
              className="flex flex-col gap-2 rounded-lg border border-line bg-surface p-4 hover:bg-line/50"
            >
              <span className="flex items-center gap-2 text-xl font-semibold text-ink">
                <Icon aria-hidden="true" className="size-5" />
                {label}
              </span>
              <span className="text-sm text-ink-muted">{text}</span>
            </Link>
          ))}
        </nav>
      ) : null}
    </>
  );
}
