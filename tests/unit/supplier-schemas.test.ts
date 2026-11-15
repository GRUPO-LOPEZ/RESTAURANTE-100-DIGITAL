// Ficha de proveedor (Fase 3, Prompt 1, ADR-0050): CUIT, días, el borrador y el esquema de la ficha. La base vuelve a
// controlar todo (pgTAP 320); estas reglas son las mismas en el navegador y en el servidor.
import { describe, expect, it } from "vitest";

import { supplierSheetSchema, validChannelTarget } from "@/lib/forms/schemas";
import {
  countSupplierChanges,
  daysLabel,
  daysLongLabel,
  emptyAccount,
  formatCuit,
  normalizeCuit,
  paymentLabel,
  supplierChanges,
  supplierPayload,
  toggleDay,
  validCuit,
  type SupplierSheetDraft,
} from "@/lib/suppliers";

describe("el CUIT", () => {
  it("valida el dígito verificador (casos 1 y 2 del plan de la Fase 3)", () => {
    expect(validCuit("20-12345678-6")).toBe(true);
    expect(validCuit("20123456786")).toBe(true);
    expect(validCuit("20-12345678-7")).toBe(false);
  });

  it("resuelve los bordes: resto 11 da 0 y resto 10 da 9", () => {
    // 20-00000006: la suma da 22, 22 mod 11 = 0 → 11 → verificador 0.
    expect(validCuit("20000000060")).toBe(true);
    expect(validCuit("20000000061")).toBe(false);
    // 20-00000001: la suma da 12, 12 mod 11 = 1 → 10 → verificador 9 (como los validadores de uso común).
    expect(validCuit("20000000019")).toBe(true);
    expect(validCuit("20000000010")).toBe(false);
  });

  it("rechaza lo que no son 11 números", () => {
    expect(validCuit("")).toBe(false);
    expect(validCuit("2012345678")).toBe(false);
    expect(validCuit("20-1234567A-6")).toBe(false);
  });

  it("se normaliza y se muestra con guiones", () => {
    expect(normalizeCuit(" 20.12345678-6 ")).toBe("20123456786");
    expect(formatCuit("20123456786")).toBe("20-12345678-6");
    // Un CUIT viejo con otro formato queda como vino.
    expect(formatCuit("12-34")).toBe("12-34");
    expect(formatCuit(null)).toBe("");
  });
});

describe("los días de la semana", () => {
  it("arma la etiqueta corta y la larga", () => {
    expect(daysLabel([5, 1, 3])).toBe("Lu Mi Vi");
    expect(daysLabel([2, 3])).toBe("Ma Mi");
    expect(daysLabel([])).toBe("Sin días");
    expect(daysLabel([1, 2, 3, 4, 5, 6, 7])).toBe("Todos los días");
    expect(daysLongLabel([1, 3, 5])).toBe("lunes, miércoles y viernes");
    expect(daysLongLabel([7])).toBe("domingo");
  });

  it("un clic prende o apaga un día, sin repetir y en orden", () => {
    expect(toggleDay([1, 5], 3)).toEqual([1, 3, 5]);
    expect(toggleDay([1, 3, 5], 3)).toEqual([1, 5]);
  });

  it("la condición de pago, en palabras", () => {
    expect(paymentLabel("account", 30)).toBe("Cuenta corriente a 30 días");
    expect(paymentLabel("cash_on_delivery", 0)).toBe("Contra entrega");
    expect(paymentLabel(null, null)).toBe("Sin cargar");
  });
});

function draft(): SupplierSheetDraft {
  return {
    supplier: {
      name: "Frigorífico Demo S.A.",
      trade_name: "Frigorífico Demo",
      tax_id: "30500000029",
      vat_condition: "registered",
      address: "",
      city: "",
      phone: "",
      whatsapp: "",
      email: "",
      sales_contact: "",
      admin_contact: "",
      notes: "",
    },
    terms: {
      orderDays: [1, 3, 5],
      deliveryDays: [2, 4, 6],
      receivingFrom: "08:00",
      receivingTo: "12:00",
      poChannel: "email",
      poChannelTarget: "pedidos@ejemplo.test",
      billingModes: ["invoice_remito"],
      priceListFrequency: "biweekly",
      requiresPoApproval: true,
    },
    payment: { paymentTerms: "account", paymentDays: "30", minimumOrderAmount: "150000" },
    accounts: [
      {
        ...emptyAccount("a1"),
        id: "00000000-0000-4000-8000-0000000000a1",
        alias: "frigorifico.demo",
      },
    ],
    categories: ["00000000-0000-4000-8000-000000000702"],
    customerNumbers: [{ restaurantId: "00000000-0000-4000-8000-000000000201", number: "CLI-0101" }],
  };
}

describe("el borrador de la ficha", () => {
  it("sin cambios no cuenta nada", () => {
    expect(countSupplierChanges(supplierChanges(draft(), draft()))).toBe(0);
  });

  it("un día cambia la operativa y el contador suma uno", () => {
    const next = draft();
    next.terms.deliveryDays = toggleDay(next.terms.deliveryDays, 1);
    const c = supplierChanges(draft(), next);
    expect(c.terms).toEqual(["deliveryDays"]);
    expect(countSupplierChanges(c)).toBe(1);
    expect(supplierPayload(draft(), next)).toEqual({ terms: { delivery_days: [1, 2, 4, 6] } });
  });

  it("el canal y su dato viajan juntos", () => {
    const next = draft();
    next.terms.poChannelTarget = "otro@ejemplo.test";
    expect(supplierPayload(draft(), next).terms).toEqual({
      po_channel: "email",
      po_channel_target: "otro@ejemplo.test",
    });
  });

  it("una cuenta nueva viaja sin id; una que se quita, solo con su id", () => {
    const next = draft();
    next.accounts = [
      { ...next.accounts![0]!, remove: true },
      { ...emptyAccount("nueva"), method: "electronic_code", electronicCode: "0000-1234" },
    ];
    expect(supplierPayload(draft(), next).accounts).toEqual([
      { id: "00000000-0000-4000-8000-0000000000a1", remove: true },
      {
        method: "electronic_code",
        cbu: "",
        alias: "",
        bank: "",
        holder_name: "",
        holder_tax_id: "",
        electronic_code: "0000-1234",
        is_active: true,
      },
    ]);
  });

  it("sin permiso de pago no viaja nada del pago", () => {
    const saved = { ...draft(), payment: null, accounts: null };
    const next = { ...saved, categories: [] };
    const payload = supplierPayload(saved, next);
    expect(payload.payment_terms).toBeUndefined();
    expect(payload.accounts).toBeUndefined();
    expect(payload.categories).toEqual([]);
  });

  it("los números de cliente vacíos se quitan", () => {
    const next = draft();
    next.customerNumbers = [{ restaurantId: "00000000-0000-4000-8000-000000000201", number: " " }];
    expect(supplierPayload(draft(), next).customer_numbers).toEqual([]);
  });
});

describe("el esquema de la ficha", () => {
  const base = {
    supplierId: "00000000-0000-4000-8000-000000000902",
    expectedStamp: "2026-11-15T12:00:00Z",
    reason: "Ajuste",
  };
  const firstMessage = (changes: unknown) => {
    const r = supplierSheetSchema.safeParse({ ...base, changes });
    return r.success ? null : r.error.issues[0]?.message;
  };

  it("acepta un cambio válido y pide al menos uno", () => {
    expect(firstMessage({ terms: { delivery_days: [1, 3] } })).toBeNull();
    expect(firstMessage({})).toBe("No hay cambios para guardar.");
  });

  it("controla el CUIT, los días y el horario (caso 3)", () => {
    expect(firstMessage({ supplier: { tax_id: "20-12345678-7" } })).toBe(
      "El CUIT no es válido: revisá los números.",
    );
    expect(firstMessage({ terms: { order_days: [0] } })).toBe("Los días van de lunes a domingo.");
    expect(firstMessage({ terms: { order_days: [2, 2] } })).toBe("Los días van sin repetir.");
    expect(firstMessage({ terms: { receiving_from: "10:00", receiving_to: "08:00" } })).toBe(
      "El horario de recepción va con «desde» y «hasta», y «desde» es antes que «hasta».",
    );
  });

  it("el dato tiene que corresponder al canal (caso 4)", () => {
    expect(validChannelTarget("supplier_portal", "https://pedidos.ejemplo.test")).toBe(true);
    expect(validChannelTarget("supplier_portal", "no es una URL")).toBe(false);
    expect(validChannelTarget("whatsapp", "+54 11 5000-0001")).toBe(true);
    expect(validChannelTarget("email", "pedidos@ejemplo.test")).toBe(true);
    expect(
      firstMessage({
        terms: { po_channel: "supplier_portal", po_channel_target: "no es una URL" },
      }),
    ).toBe(
      "El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.",
    );
  });

  it("controla el pago y las cuentas", () => {
    expect(
      firstMessage({
        payment_terms: { payment_terms: "cash", payment_days: "10", minimum_order_amount: "" },
      }),
    ).toBe("En cuenta corriente, los días van de 1 a 180.");
    expect(
      firstMessage({
        payment_terms: { payment_terms: "account", payment_days: "30", minimum_order_amount: "" },
      }),
    ).toBeNull();
    const account = {
      method: "transfer",
      cbu: "",
      alias: "",
      bank: "",
      holder_name: "",
      holder_tax_id: "",
      electronic_code: "",
      is_active: true,
    };
    expect(firstMessage({ accounts: [account] })).toBe("La transferencia necesita CBU o alias.");
    expect(firstMessage({ accounts: [{ ...account, cbu: "123" }] })).toBe(
      "El CBU tiene 22 números.",
    );
    expect(firstMessage({ accounts: [{ ...account, alias: "ab" }] })).toBe(
      "El alias va de 6 a 20 caracteres: letras, números, puntos o guiones.",
    );
    expect(firstMessage({ accounts: [{ ...account, method: "electronic_code" }] })).toBe(
      "El pago electrónico necesita su código.",
    );
    expect(firstMessage({ accounts: [{ ...account, alias: "frigorifico.demo" }] })).toBeNull();
  });
});
