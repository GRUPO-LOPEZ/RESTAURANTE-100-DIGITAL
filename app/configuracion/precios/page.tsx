import Link from "next/link";
import { Suspense } from "react";

import { setCategoryStaleDaysAction, updatePriceSettingsAction } from "@/app/configuracion/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { getPriceSettings } from "@/lib/prices";
import { createClient } from "@/lib/supabase/server";
import { requireMenu } from "@/lib/auth/session";

// Configuración de precios del grupo (ADR-0029; respuestas 6 y 8 de Soy, ADR-0030): desde qué variación
// aprueba también Dirección, contra cuántos días atrás se compara y cuándo un precio está desactualizado.
// La cambia solo quien tiene prices.configure para todo el grupo (Dirección General).
export default function PreciosConfigPage() {
  return (
    <AppShell
      title="Configuración de precios"
      description="Cuándo un precio necesita también la aprobación de Dirección y cuándo está desactualizado."
    >
      <Suspense fallback={<Loading />}>
        <PriceSettingsPanel />
      </Suspense>
    </AppShell>
  );
}

function Reason({ id }: { id: string }) {
  return (
    <FormTextarea
      id={id}
      label="Motivo"
      hint="Queda en el historial."
      name="reason"
      required
      maxLength={500}
    />
  );
}

async function PriceSettingsPanel() {
  await requireMenu("pricesConfigure");
  const supabase = await createClient();
  const { data: groups } = await supabase
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: "prices.configure" });
  // Hoy hay un solo grupo. Si se suman otros, la pantalla va a tener que elegir el grupo.
  const groupId = Array.isArray(groups) && typeof groups[0] === "string" ? groups[0] : null;
  if (!groupId)
    return <Notice status="warn">No encontramos el grupo para configurar. Probá de nuevo.</Notice>;
  const [settings, categories] = await Promise.all([
    getPriceSettings(groupId),
    supabase
      .schema("catalog")
      .from("ingredient_categories")
      .select("id, name, parent_id, stale_price_days")
      .eq("group_id", groupId)
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (categories.error) throw new Error("No pudimos cargar las categorías.");
  const byId = new Map((categories.data ?? []).map((c) => [c.id, c]));
  const rows = (categories.data ?? [])
    .map((c) => {
      const parent = c.parent_id ? byId.get(c.parent_id) : undefined;
      return { ...c, label: parent ? `${parent.name} › ${c.name}` : c.name };
    })
    .sort((a, b) => a.label.localeCompare(b.label, "es"));

  return (
    <>
      <Link
        href="/configuracion"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver al panel de control
      </Link>
      <Card className="flex flex-col gap-4">
        <CardTitle>Aprobación de precios</CardTitle>
        <CardDescription>
          Compras propone y el Controller aprueba. Si el costo sube o baja más que este porcentaje
          contra el de hoy, o contra el de hace los días que elijas (así varias subas chicas
          seguidas también llegan), aprueba además Dirección General.
        </CardDescription>
        <dl className="grid gap-2 text-base sm:grid-cols-3">
          <div className="flex flex-col">
            <dt className="text-sm text-ink-muted">Variación que pide a Dirección</dt>
            <dd className="text-ink tabular-nums">
              Más de {settings.approvalVariationPct.toLocaleString("es-AR")} %
            </dd>
          </div>
          <div className="flex flex-col">
            <dt className="text-sm text-ink-muted">Se compara también contra</dt>
            <dd className="text-ink tabular-nums">Hace {settings.lookbackDays} días</dd>
          </div>
          <div className="flex flex-col">
            <dt className="text-sm text-ink-muted">Desactualizado después de</dt>
            <dd className="text-ink tabular-nums">{settings.staleDays} días</dd>
          </div>
        </dl>
        <Disclosure summary="Cambiar la configuración">
          <ActionForm
            action={updatePriceSettingsAction}
            schema="priceSettings"
            submitLabel="Guardar configuración"
          >
            <input type="hidden" name="groupId" value={groupId} />
            <div className="grid gap-4 sm:grid-cols-3">
              <FormInput
                id="precios-variacion"
                label="Variación (%)"
                hint="Por ejemplo, 15."
                name="approval_variation_pct"
                required
                inputMode="decimal"
                defaultValue={String(settings.approvalVariationPct).replace(".", ",")}
              />
              <FormInput
                id="precios-hacia-atras"
                label="Comparar contra hace (días)"
                hint="Por ejemplo, 30."
                name="lookback_days"
                required
                inputMode="numeric"
                defaultValue={String(settings.lookbackDays)}
              />
              <FormInput
                id="precios-desactualizado"
                label="Desactualizado después de (días)"
                hint="Si la categoría no dice otro plazo."
                name="stale_days"
                required
                inputMode="numeric"
                defaultValue={String(settings.staleDays)}
              />
            </div>
            <Reason id="precios-motivo" />
          </ActionForm>
        </Disclosure>
      </Card>

      <Card className="flex flex-col gap-4">
        <CardTitle>Días por categoría</CardTitle>
        <CardDescription>
          Algunas materias primas cambian de precio más rápido (por ejemplo, verduras). Si una
          categoría no tiene plazo propio, vale el del grupo.
        </CardDescription>
        {rows.length === 0 ? (
          <EmptyState title="Todavía no hay categorías.">
            Se cargan en la configuración del catálogo.
          </EmptyState>
        ) : (
          <ul aria-label="Días por categoría" className="flex flex-col gap-2">
            {rows.map((c) => (
              <li key={c.id} className="flex flex-col gap-2 rounded-sm border border-line p-3">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <span className="font-medium text-ink">{c.label}</span>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {c.stale_price_days
                      ? `${c.stale_price_days} días`
                      : `El del grupo (${settings.staleDays} días)`}
                  </span>
                </div>
                <Disclosure summary={`Cambiar los días de «${c.label}»`}>
                  <ActionForm
                    action={setCategoryStaleDaysAction}
                    schema="categoryStaleDays"
                    submitLabel="Guardar días"
                  >
                    <input type="hidden" name="categoryId" value={c.id} />
                    <FormInput
                      id={`precios-cat-${c.id}`}
                      label="Días"
                      hint="Vacío: vale el plazo del grupo."
                      name="stale_price_days"
                      inputMode="numeric"
                      defaultValue={c.stale_price_days ? String(c.stale_price_days) : ""}
                    />
                    <Reason id={`precios-cat-motivo-${c.id}`} />
                  </ActionForm>
                </Disclosure>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
