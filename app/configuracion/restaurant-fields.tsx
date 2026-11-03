import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import {
  RESTAURANT_STATUS_LABELS,
  SITE_TYPE_LABELS,
  VAT_CONDITION_LABELS,
  formatTaxId,
  type LegalEntityRow,
  type RestaurantDetail,
  type SiteType,
  type UnitStatus,
} from "@/lib/org";

// Los datos de un local, iguales en el alta y en la edición (ADR-0031). El tipo y el estado los cambia
// quien administra la marca; la razón social, quien administra todo el grupo: si la persona no puede,
// el campo no se muestra (y la base igual lo controla).
export function RestaurantFields({
  prefix,
  restaurant,
  showSiteType,
  showStatus,
  legalEntities,
}: {
  prefix: string;
  restaurant?: RestaurantDetail;
  showSiteType: boolean;
  showStatus: boolean;
  // Solo en el alta y con org.manage de todo el grupo.
  legalEntities?: LegalEntityRow[];
}) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id={`${prefix}-nombre`}
          label="Nombre"
          name="name"
          required
          maxLength={120}
          defaultValue={restaurant?.name}
        />
        <FormInput
          id={`${prefix}-codigo`}
          label="Código (opcional)"
          hint="Corto y único en el grupo, por ejemplo NON-PALERMO."
          name="code"
          maxLength={20}
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck={false}
          defaultValue={restaurant?.code ?? ""}
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id={`${prefix}-direccion`}
          label="Dirección (opcional)"
          name="address"
          maxLength={200}
          autoComplete="street-address"
          defaultValue={restaurant?.address ?? ""}
        />
        <FormInput
          id={`${prefix}-localidad`}
          label="Localidad (opcional)"
          name="locality"
          maxLength={120}
          defaultValue={restaurant?.locality ?? ""}
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormInput
          id={`${prefix}-telefono`}
          label="Teléfono (opcional)"
          name="phone"
          type="tel"
          inputMode="tel"
          maxLength={30}
          defaultValue={restaurant?.phone ?? ""}
        />
        <FormInput
          id={`${prefix}-apertura`}
          label="Fecha de apertura (opcional)"
          name="opened_on"
          type="date"
          defaultValue={restaurant?.openedOn ?? ""}
        />
      </div>
      {showSiteType || showStatus ? (
        <div className="grid gap-4 sm:grid-cols-2">
          {showSiteType ? (
            <FormSelect
              id={`${prefix}-tipo`}
              label="Tipo"
              name="site_type"
              defaultValue={restaurant?.siteType ?? "restaurant"}
            >
              {(Object.keys(SITE_TYPE_LABELS) as SiteType[]).map((t) => (
                <option key={t} value={t}>
                  {SITE_TYPE_LABELS[t]}
                </option>
              ))}
            </FormSelect>
          ) : null}
          {showStatus && restaurant ? (
            <FormSelect
              id={`${prefix}-estado`}
              label="Estado"
              hint="Un local cerrado no se borra: su historia se conserva."
              name="status"
              defaultValue={restaurant.status}
            >
              {(Object.keys(RESTAURANT_STATUS_LABELS) as UnitStatus[]).map((s) => (
                <option key={s} value={s}>
                  {RESTAURANT_STATUS_LABELS[s]}
                </option>
              ))}
            </FormSelect>
          ) : null}
        </div>
      ) : null}
      {legalEntities ? (
        <FormSelect
          id={`${prefix}-razon-social`}
          label="Razón social"
          hint="Decide si el costo va con o sin IVA. Si todavía no está cargada, la podés elegir después."
          name="legal_entity_id"
          defaultValue=""
        >
          <option value="">Elegirla después</option>
          {legalEntities.map((l) => (
            <option key={l.id} value={l.id}>
              {l.name} · {formatTaxId(l.taxId)} · {VAT_CONDITION_LABELS[l.vatCondition]}
            </option>
          ))}
        </FormSelect>
      ) : null}
      <FormTextarea
        id={`${prefix}-motivo`}
        label="Motivo"
        hint="Queda en el historial."
        name="reason"
        required
        maxLength={500}
      />
    </>
  );
}
