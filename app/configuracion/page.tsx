import Link from "next/link";
import { Suspense } from "react";
import { Building2, ChevronRight, FileText, Settings, ShieldCheck, Tag, Users } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { getRestaurants } from "@/lib/org";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Panel de control (ADR-0031; respuesta 2 de Soy, ADR-0030): ¿qué puedo administrar? Cada tarjeta
// aparece solo si la persona puede usarla; la base vuelve a controlar cada cambio.
export default function PanelPage() {
  return (
    <AppShell
      title="Panel de control"
      description="Marcas, locales y razones sociales del grupo, y lo demás que podés administrar."
    >
      <Suspense fallback={<Loading />}>
        <Panel />
      </Suspense>
    </AppShell>
  );
}

function Entry({
  href,
  title,
  description,
  Icon,
}: {
  href: string;
  title: string;
  description: string;
  Icon: typeof Building2;
}) {
  return (
    <li>
      <Link
        href={href}
        className="flex min-h-touch items-center gap-3 rounded-md border border-line bg-surface p-4 hover:border-primary"
      >
        <Icon aria-hidden="true" className="size-6 shrink-0 text-primary" />
        <span className="flex min-w-0 flex-1 flex-col gap-1">
          <span className="text-base font-medium text-ink">{title}</span>
          <span className="text-sm text-ink-muted">{description}</span>
        </span>
        <ChevronRight aria-hidden="true" className="size-5 shrink-0 text-ink-muted" />
      </Link>
    </li>
  );
}

async function Panel() {
  await requireMenu("panel");
  const menus = await getMenus();
  const restaurants = menus.orgManageGroup ? await getRestaurants() : [];
  const withoutEntity = restaurants.filter((r) => !r.legalEntityId).length;
  return (
    <>
      {withoutEntity > 0 ? (
        <Notice status="warn">
          {withoutEntity === 1
            ? "Hay 1 local sin razón social: su costo sin IVA queda incompleto."
            : `Hay ${withoutEntity} locales sin razón social: su costo sin IVA queda incompleto.`}{" "}
          <Link
            href="/configuracion/razones-sociales"
            className="inline-flex min-h-touch items-center font-medium underline underline-offset-4"
          >
            Ver razones sociales
          </Link>
        </Notice>
      ) : null}
      {menus.orgManage ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Estructura del grupo</CardTitle>
          <CardDescription>
            Lo que se carga una vez y usan todas las pantallas. Cada cambio pide un motivo y queda
            en el historial.
          </CardDescription>
          <ul className="flex flex-col gap-2">
            <Entry
              href="/configuracion/marcas"
              title="Marcas y locales"
              description="Altas, datos, tipo y estado de cada marca y local, y las áreas de cada local."
              Icon={Building2}
            />
            {menus.orgManageGroup ? (
              <Entry
                href="/configuracion/razones-sociales"
                title="Razones sociales"
                description="Las sociedades con su CUIT y su condición frente al IVA, y qué locales usa cada una."
                Icon={FileText}
              />
            ) : null}
          </ul>
        </Card>
      ) : null}
      {menus.pricesConfigure ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Precios</CardTitle>
          <ul className="flex flex-col gap-2">
            <Entry
              href="/configuracion/precios"
              title="Configuración de precios"
              description="Desde qué variación aprueba también Dirección, contra cuántos días atrás se compara y cuándo un precio está desactualizado."
              Icon={Tag}
            />
          </ul>
        </Card>
      ) : null}
      {menus.users || menus.roles || menus.catalogSettings ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Personas y listas</CardTitle>
          <ul className="flex flex-col gap-2">
            {menus.users ? (
              <Entry
                href="/usuarios"
                title="Usuarios"
                description="Invitar personas, darles un rol y un lugar, suspender o dar de baja."
                Icon={Users}
              />
            ) : null}
            {menus.roles ? (
              <Entry
                href="/roles"
                title="Roles y permisos"
                description="Qué puede hacer cada rol. Los cambios pasan por aprobación."
                Icon={ShieldCheck}
              />
            ) : null}
            {menus.catalogSettings ? (
              <Entry
                href="/materias-primas/configuracion"
                title="Configuración del catálogo"
                description="Categorías de materias primas y de recetas, y procesos de rendimiento."
                Icon={Settings}
              />
            ) : null}
          </ul>
        </Card>
      ) : null}
    </>
  );
}
