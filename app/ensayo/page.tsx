import { Suspense } from "react";

import { createDraftAction, publishAction, requestReviewAction } from "@/app/ensayo/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import {
  formatDateTime,
  formatMoney,
  getBrandsAndRestaurants,
  getTestDocuments,
  type TestDocument,
} from "@/lib/data";
import { requireMenu } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

// Documentos de ensayo (sección 10 del documento de Soy): imitan una receta para la demo de
// cierre (pruebas 2, 3 y 7). Se borran al cerrar la Fase 1; en la Fase 2 llegan las recetas reales.
export default function EnsayoPage() {
  return (
    <AppShell
      title="Documentos de ensayo"
      description="Imitan una receta para probar quién ve qué: el costo, los borradores y las versiones. Se borran al terminar la Fase 1."
    >
      <Suspense fallback={<Loading />}>
        <Documents />
      </Suspense>
    </AppShell>
  );
}

const STATUS: Record<TestDocument["status"], { label: string; status: BadgeStatus }> = {
  draft: { label: "Borrador", status: "draft" },
  in_review: { label: "En revisión", status: "review" },
  approved: { label: "Aprobada", status: "ok" },
  published: { label: "Vigente", status: "ok" },
  archived: { label: "Archivada", status: "neutral" },
};

function Reason({ id }: { id: string }) {
  return (
    <Field id={id} label="Motivo" hint="Queda en el historial.">
      <Textarea name="reason" required maxLength={500} />
    </Field>
  );
}

async function Documents() {
  await requireMenu("testDocuments");
  const supabase = await createClient();
  const can = async (permission: string) =>
    (await supabase.schema("core").rpc("has_permission_anywhere", { p_permission: permission }))
      .data === true;
  // Solo para mostrar u ocultar botones: cada paso lo vuelve a validar la base.
  const [docs, places, canEdit, canPublish, canSeeCosts] = await Promise.all([
    getTestDocuments(),
    getBrandsAndRestaurants(),
    can("test_documents.edit"),
    can("test_documents.publish"),
    can("test_documents.view_costs"),
  ]);
  const brandName = new Map(places.brands.map((b) => [b.id, b.name]));
  const restaurantName = new Map(places.restaurants.map((r) => [r.id, r.name]));

  return (
    <>
      {docs.length === 0 ? (
        <EmptyState title="No hay documentos de ensayo para mostrar." />
      ) : (
        <ul className="flex flex-col gap-4">
          {docs.map((d) => (
            <li key={d.id}>
              <Card className="flex flex-col gap-2">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-xl text-ink">{d.title}</h2>
                  <Badge status={STATUS[d.status].status}>{STATUS[d.status].label}</Badge>
                  <span className="text-sm text-ink-muted">Versión {d.version_number}</span>
                </div>
                <CardDescription>
                  {d.restaurant_id
                    ? `Local ${restaurantName.get(d.restaurant_id) ?? ""}`
                    : `Toda la marca ${brandName.get(d.brand_id) ?? ""}`}{" "}
                  · Actualizado el {formatDateTime(d.updated_at)}
                </CardDescription>
                {d.content ? (
                  <p className="text-base whitespace-pre-line text-ink">{d.content}</p>
                ) : null}
                <p className="text-base text-ink">
                  Costo:{" "}
                  {d.cost !== null ? (
                    <span className="font-medium tabular-nums">
                      {formatMoney(d.cost, d.currency)}
                    </span>
                  ) : (
                    <span className="text-ink-muted">
                      {canSeeCosts ? "sin cargar" : "no lo podés ver con tu rol"}
                    </span>
                  )}
                </p>
                {canEdit && d.status === "draft" ? (
                  <details>
                    <summary className="flex min-h-touch cursor-pointer items-center text-base text-primary underline-offset-4 hover:underline">
                      Pedir la revisión
                    </summary>
                    <ActionForm
                      action={requestReviewAction}
                      submitLabel="Pedir la revisión"
                      variant="outline"
                    >
                      <input type="hidden" name="id" value={d.id} />
                      <Reason id={`motivo-revision-${d.id}`} />
                    </ActionForm>
                  </details>
                ) : null}
                {canPublish && d.status === "in_review" ? (
                  <details>
                    <summary className="flex min-h-touch cursor-pointer items-center text-base text-primary underline-offset-4 hover:underline">
                      Aprobar y publicar
                    </summary>
                    <ActionForm action={publishAction} submitLabel="Publicar" variant="outline">
                      <input type="hidden" name="id" value={d.id} />
                      <Reason id={`motivo-publicar-${d.id}`} />
                    </ActionForm>
                  </details>
                ) : null}
                {canEdit && d.status === "published" ? (
                  <details>
                    <summary className="flex min-h-touch cursor-pointer items-center text-base text-primary underline-offset-4 hover:underline">
                      Corregir (crea una versión nueva)
                    </summary>
                    <ActionForm
                      action={createDraftAction}
                      submitLabel="Crear la versión nueva"
                      variant="outline"
                    >
                      <p className="text-sm text-ink-muted">
                        Una versión publicada no se modifica: la corrección queda como versión{" "}
                        {d.version_number + 1}, en borrador.
                      </p>
                      <input type="hidden" name="documentKey" value={d.document_key} />
                      <input
                        type="hidden"
                        name="place"
                        value={`${d.brand_id}:${d.restaurant_id ?? ""}`}
                      />
                      <input type="hidden" name="title" value={d.title} />
                      <Field id={`contenido-${d.id}`} label="Contenido corregido">
                        <Textarea name="content" defaultValue={d.content ?? ""} maxLength={4000} />
                      </Field>
                      <Reason id={`motivo-version-${d.id}`} />
                    </ActionForm>
                  </details>
                ) : null}
              </Card>
            </li>
          ))}
        </ul>
      )}

      {canEdit ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Nuevo borrador</CardTitle>
            <CardDescription>
              Nace como borrador. Para que lo vea el resto, alguien con permiso lo tiene que
              publicar.
            </CardDescription>
          </div>
          <ActionForm
            action={createDraftAction}
            submitLabel="Crear el borrador"
            pendingLabel="Creando…"
          >
            <Field id="lugar" label="Dónde">
              <Select name="place" required defaultValue="">
                <option value="" disabled>
                  Elegí la marca o el local
                </option>
                {places.brands.map((b) => (
                  <option key={b.id} value={`${b.id}:`}>
                    Toda la marca · {b.name}
                  </option>
                ))}
                {places.restaurants.map((r) => (
                  <option key={r.id} value={`${r.brand_id}:${r.id}`}>
                    Local · {r.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="titulo" label="Título">
              <Input name="title" required maxLength={120} />
            </Field>
            <Field id="contenido" label="Contenido">
              <Textarea name="content" maxLength={4000} />
            </Field>
            {canSeeCosts ? (
              <Field
                id="costo"
                label="Costo (ARS)"
                hint="Opcional. Solo lo ven quienes pueden ver costos."
              >
                <Input name="cost" inputMode="decimal" placeholder="1520,50" />
              </Field>
            ) : null}
            <Reason id="motivo-nuevo" />
          </ActionForm>
        </Card>
      ) : null}
    </>
  );
}
