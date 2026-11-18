"use client";

import { useActionState, useId } from "react";
import { PackageCheck } from "lucide-react";

import { startReceiptAction, startWithoutOrderAction } from "@/app/compras/recepcion/actions";
import { Button } from "@/components/ui/button";
import { Field, Select } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import type { ActionState } from "@/lib/auth/results";

// «Recibir» (o «Retomar») una OC: abre su recepción en la base y lleva a los pasos. Si la base dice que no, se ve acá.
export function StartReceiptButton({
  orderId,
  number,
  resume,
}: {
  orderId: string;
  number: string;
  resume: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(startReceiptAction, {});
  return (
    <form action={action} className="flex flex-col items-stretch gap-2 desk:items-end">
      <input type="hidden" name="orderId" value={orderId} />
      <Button
        type="submit"
        disabled={pending}
        variant={resume ? "outline" : "default"}
        aria-label={`${resume ? "Retomar" : "Recibir"} la orden ${number}`}
      >
        <PackageCheck aria-hidden="true" />
        {pending ? "Abriendo…" : resume ? "Retomar" : "Recibir"}
      </Button>
      {state.status === "bad" ? <Notice status="bad">{state.message}</Notice> : null}
    </form>
  );
}

// «Recibir sin OC»: el proveedor y listo. Lo que llegó se anota renglón por renglón.
export function StartWithoutOrder({
  restaurantId,
  suppliers,
}: {
  restaurantId: string;
  suppliers: { id: string; name: string }[];
}) {
  const id = useId();
  const [state, action, pending] = useActionState<ActionState, FormData>(
    startWithoutOrderAction,
    {},
  );
  const error = state.fieldErrors?.supplierId;
  return (
    <form action={action} className="flex flex-col gap-3 desk:flex-row desk:items-end">
      <input type="hidden" name="restaurantId" value={restaurantId} />
      <Field id={`${id}-proveedor`} label="Proveedor" error={error} className="desk:w-80">
        <Select name="supplierId" defaultValue="" required>
          <option value="" disabled>
            Elegí el proveedor
          </option>
          {suppliers.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
      </Field>
      <Button type="submit" variant="outline" disabled={pending}>
        {pending ? "Abriendo…" : "Recibir sin OC"}
      </Button>
      {state.status === "bad" && !error ? <Notice status="bad">{state.message}</Notice> : null}
    </form>
  );
}
