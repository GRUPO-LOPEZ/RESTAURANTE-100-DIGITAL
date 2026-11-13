import Link from "next/link";
import { Suspense, cache } from "react";
import { BookOpen, ClipboardCheck, History, KeyRound, Users } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { DataLine, HomeBoardView } from "@/components/home-board";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { pickCostPlace } from "@/lib/costs";
import { first, getActiveRestaurantId, getUser, scopeLabel } from "@/lib/data";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";
import { getQualityPlaces } from "@/lib/quality";

type Params = PageProps<"/">["searchParams"];

// Inicio (ADR-0045, pedido de Soy del 2026-11-13): un tablero que entra entero en una pantalla de computadora y se
// entiende en 5 segundos. Quien no ve la calidad de datos (el cocinero) sigue con el Inicio simple.
export default function InicioPage({ searchParams }: PageProps<"/">) {
  return (
    <AppShell
      title="Inicio"
      fill
      heading={
        <Suspense fallback="Inicio">
          <Greeting searchParams={searchParams} />
        </Suspense>
      }
      description={
        <Suspense fallback={null}>
          <Description searchParams={searchParams} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <Actions searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Home searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// El local del tablero: el de ?local= o el del selector global. Sin calidad de datos, ninguno. Lo usan el saludo, la
// línea de datos, la acción y el tablero: se lee una sola vez por pedido.
const boardPlace = cache(async (searchParams: Params) => {
  const session = await requireOperable();
  const menus = await getMenus();
  if (!menus.quality)
    return { session, menus, places: [], place: null, params: await searchParams };
  const [places, activeId, params] = await Promise.all([
    getQualityPlaces(),
    getActiveRestaurantId(session.user_id),
    searchParams,
  ]);
  return {
    session,
    menus,
    places,
    place: pickCostPlace(places, first(params.local), activeId),
    params,
  };
});

// «Hola, Sofía · Demo Pastas Centro»: el h1 de la pantalla.
async function Greeting({ searchParams }: { searchParams: Params }) {
  const { session, place } = await boardPlace(searchParams);
  return (
    <>
      Hola, {displayName(session)}
      {place ? <span className="font-normal text-ink-muted"> · {place.name}</span> : null}
    </>
  );
}

async function Description({ searchParams }: { searchParams: Params }) {
  const { place } = await boardPlace(searchParams);
  return place ? <DataLine placeId={place.id} /> : null;
}

// La única acción del encabezado: ir a lo que falta corregir en el local elegido.
async function Actions({ searchParams }: { searchParams: Params }) {
  const { place } = await boardPlace(searchParams);
  if (!place) return null;
  return (
    <Button asChild>
      <Link href={`/calidad?local=${place.id}`}>Ver qué falta corregir</Link>
    </Button>
  );
}

async function Home({ searchParams }: { searchParams: Params }) {
  const { session, menus, places, place, params } = await boardPlace(searchParams);

  if (places.length > 0) {
    return (
      <HomeBoardView
        places={places}
        place={place}
        ranking={first(params.ranking) ?? ""}
        menus={{
          recipes: menus.recipes,
          ingredients: menus.catalog,
          costs: menus.costs,
          approvals: menus.approvals,
          quality: menus.quality,
          reports: menus.reports,
        }}
      />
    );
  }

  // El Inicio simple: los roles de la persona y sus accesos.
  const me = await getUser(session.user_id ?? "");
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
      <Card className="flex flex-col gap-2">
        <CardTitle>Tus roles</CardTitle>
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
      {shortcuts.length > 0 ? (
        <nav aria-label="Accesos" className="grid gap-4 sm:grid-cols-3">
          {shortcuts.map(({ href, label, text, Icon }) => (
            <Link
              key={href}
              href={href}
              className="flex flex-col gap-2 rounded-md border border-line bg-surface p-4 hover:border-primary"
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
