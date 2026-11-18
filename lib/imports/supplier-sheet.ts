import ExcelJS from "exceljs";
import { validChannelTarget } from "@/lib/forms/schemas";
import { findSheet, norm, openWorkbook, text, value, type Cell } from "@/lib/imports/xlsx";
import {
  CHANNEL_LABELS,
  PAYMENT_TERMS_LABELS,
  VAT_LABELS,
  VAT_SHORT,
  WEEK_DAYS,
  normalizeCuit,
  sortDays,
  validCuit,
  type Channel,
  type PaymentTerms,
  type VatCondition,
} from "@/lib/suppliers";

// Planilla de proveedores para la carga inicial (ADR-0055, P1). Una hoja «Proveedores», una fila por proveedor, con las
// columnas de la plantilla que se baja de la pantalla. El lector traduce los valores con nombre (condición IVA, días,
// canal, condición de pago, Sí/No) con las mismas etiquetas que la ficha (lib/suppliers.ts) y marca los errores de cada
// fila. Los rubros van por nombre: los busca la base, que además vuelve a controlar todo antes de crear nada.
// No entran las cuentas de pago (CBU, alias) ni los números de cliente: se cargan a mano en la ficha.

export const MAX_SUPPLIER_FILE_BYTES = 1024 * 1024;
export const MAX_SUPPLIER_ROWS = 200;
// Filas que se recorren, aunque el Excel diga que tiene más (las vacías no cuentan para el tope).
const MAX_SHEET_ROWS = 2_000;
export const SUPPLIER_SHEET_NAME = "Proveedores";

type Key =
  | "name"
  | "tax_id"
  | "trade_name"
  | "vat_condition"
  | "address"
  | "city"
  | "phone"
  | "whatsapp"
  | "email"
  | "sales_contact"
  | "admin_contact"
  | "categories"
  | "order_days"
  | "delivery_days"
  | "po_channel"
  | "po_channel_target"
  | "requires_po_approval"
  | "payment_terms"
  | "payment_days"
  | "minimum_order_amount";

// Las columnas de la plantilla, en orden. `also` son otros encabezados que se aceptan.
export const SUPPLIER_COLUMNS: { key: Key; header: string; required?: true; also?: string[] }[] = [
  { key: "name", header: "Razón social", required: true },
  { key: "tax_id", header: "CUIT", required: true },
  { key: "trade_name", header: "Nombre de fantasía" },
  { key: "vat_condition", header: "Condición IVA", also: ["Condición frente al IVA"] },
  { key: "address", header: "Domicilio" },
  { key: "city", header: "Localidad" },
  { key: "phone", header: "Teléfono" },
  { key: "whatsapp", header: "WhatsApp" },
  { key: "email", header: "Correo", also: ["Mail", "Email"] },
  { key: "sales_contact", header: "Contacto de ventas" },
  { key: "admin_contact", header: "Contacto de pagos" },
  { key: "categories", header: "Rubros" },
  { key: "order_days", header: "Días de pedido" },
  { key: "delivery_days", header: "Días de entrega" },
  { key: "po_channel", header: "Canal de la OC" },
  { key: "po_channel_target", header: "Destino de la OC", also: ["Destino"] },
  { key: "requires_po_approval", header: "Requiere aprobación de la OC" },
  { key: "payment_terms", header: "Condición de pago" },
  { key: "payment_days", header: "Días de pago", also: ["Días"] },
  { key: "minimum_order_amount", header: "Pedido mínimo" },
];

// Lo que viaja a la base por cada fila: los mismos bloques que guarda la ficha (purchasing.save_supplier_sheet), más
// los rubros por nombre.
export type SupplierImportRow = {
  row: number;
  name: string | null;
  tax_id: string | null;
  supplier: Record<string, string>;
  terms: {
    order_days?: number[];
    delivery_days?: number[];
    po_channel?: Channel;
    po_channel_target?: string;
    requires_po_approval?: boolean;
  };
  payment_terms: {
    payment_terms: PaymentTerms;
    payment_days: string;
    minimum_order_amount: string;
  } | null;
  categories: string[];
  errors: string[];
};

export type SupplierSheetResult =
  { ok: true; rows: SupplierImportRow[] } | { ok: false; message: string };

// ---------------------------------------------------------------------------
// Valores con nombre
// ---------------------------------------------------------------------------
function lookup<T extends string>(labels: Record<T, string>[], extra: Record<string, T> = {}) {
  const map = new Map<string, T>();
  for (const l of labels)
    for (const [k, v] of Object.entries(l) as [T, string][]) {
      map.set(norm(v), k);
      map.set(norm(k), k);
    }
  for (const [k, v] of Object.entries(extra)) map.set(norm(k), v);
  return (v: string) => map.get(norm(v)) ?? null;
}

const vatOf = lookup<VatCondition>([VAT_LABELS, VAT_SHORT], {
  "Resp. inscripto": "registered",
  Monotributista: "monotax",
});
const channelOf = lookup<Channel>([CHANNEL_LABELS], {
  Correo: "email",
  Email: "email",
  Portal: "supplier_portal",
  Web: "supplier_portal",
});
const paymentOf = lookup<PaymentTerms>([PAYMENT_TERMS_LABELS], {
  "Contado contra entrega": "cash_on_delivery",
  "Cuenta corriente a N días": "account",
});

const DAY_NAMES = new Map<string, number>();
for (const d of WEEK_DAYS) {
  DAY_NAMES.set(norm(d.name), d.day);
  DAY_NAMES.set(norm(d.letter), d.day);
  DAY_NAMES.set(norm(d.name).slice(0, 3), d.day);
}

// «lun, mié, vie», «lunes y jueves», «Lu Mi Vi». Lo que no es un día da error.
export function parseDays(v: string): { days: number[]; unknown: string[] } {
  const parts = norm(v)
    .split(/[,;/\s]+|\by\b/)
    .map((p) => p.replace(/\.$/, "").trim())
    .filter((p) => p !== "" && p !== "y");
  const days: number[] = [];
  const unknown: string[] = [];
  for (const p of parts) {
    const d = DAY_NAMES.get(p);
    if (d) days.push(d);
    else unknown.push(p);
  }
  return { days: sortDays(days), unknown };
}

function yesNo(v: string): boolean | null {
  const n = norm(v);
  if (["si", "s", "x", "true", "1"].includes(n)) return true;
  if (["no", "n", "false", "0"].includes(n)) return false;
  return null;
}

// Un monto o una cantidad como se escribe acá: «150.000», «150000», «1.500,50».
function amount(v: Cell): string | null {
  if (typeof v === "number")
    return Number.isFinite(v) && v >= 0 ? String(Math.round(v * 100) / 100) : null;
  const s = (v ?? "").toString().replace(/\$|\s/g, "");
  if (s === "") return "";
  const plain = /,\d{1,2}$/.test(s) ? s.replace(/\./g, "").replace(",", ".") : s.replace(/\./g, "");
  return /^[0-9]{1,12}(\.[0-9]{1,2})?$/.test(plain) ? plain : null;
}

const PHONE = /^[0-9 +()-]{6,30}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// ---------------------------------------------------------------------------
// Una fila
// ---------------------------------------------------------------------------
function readRow(row: number, get: (k: Key) => Cell): SupplierImportRow {
  const errors: string[] = [];
  const header = (k: Key) => SUPPLIER_COLUMNS.find((c) => c.key === k)?.header ?? k;
  const str = (k: Key, max = 200) => {
    const v = get(k);
    return typeof v === "number" ? String(v) : text(v, max);
  };

  const name = str("name", 200);
  if (!name) errors.push("Falta la razón social.");
  // La fila de ejemplo de la plantilla no se crea aunque se olviden de borrarla (su CUIT es inventado).
  else if (name.includes(EXAMPLE_MARK))
    errors.push("Es la fila de ejemplo de la plantilla: borrala antes de subir.");
  const rawCuit = str("tax_id", 20);
  let taxId: string | null = null;
  if (!rawCuit) errors.push("Falta el CUIT.");
  else if (!validCuit(rawCuit)) errors.push(`CUIT: «${rawCuit}» no es un CUIT válido.`);
  else taxId = normalizeCuit(rawCuit);

  const supplier: Record<string, string> = {};
  for (const k of ["trade_name", "address", "city", "sales_contact", "admin_contact"] as const) {
    const v = str(k, k === "address" ? 200 : 120);
    if (v) supplier[k] = v;
  }
  for (const k of ["phone", "whatsapp"] as const) {
    const v = str(k, 40);
    if (!v) continue;
    if (PHONE.test(v)) supplier[k] = v;
    else errors.push(`${header(k)}: «${v}» no es un teléfono (números, espacios, +, guiones).`);
  }
  const email = str("email", 320);
  if (email) {
    if (EMAIL.test(email)) supplier.email = email.toLowerCase();
    else errors.push(`Correo: «${email}» no es un correo.`);
  }
  const vat = str("vat_condition");
  if (vat) {
    const v = vatOf(vat);
    if (v) supplier.vat_condition = v;
    else
      errors.push(
        `Condición IVA: «${vat}» no es una opción (Responsable inscripto, Monotributo o Exento).`,
      );
  }

  const terms: SupplierImportRow["terms"] = {};
  for (const k of ["order_days", "delivery_days"] as const) {
    const v = str(k);
    if (!v) continue;
    const { days, unknown } = parseDays(v);
    if (unknown.length > 0)
      errors.push(`${header(k)}: «${unknown.join(", ")}» no es un día de la semana.`);
    else terms[k] = days;
  }
  const channelText = str("po_channel");
  const target = str("po_channel_target", 320);
  if (channelText) {
    const c = channelOf(channelText);
    if (!c)
      errors.push(
        `Canal de la OC: «${channelText}» no es una opción (WhatsApp, Mail o Sistema propio).`,
      );
    else if (!target)
      errors.push("Destino de la OC: falta el número, el correo o la dirección del canal.");
    else if (!validChannelTarget(c, target))
      errors.push(
        `Destino de la OC: «${target}» no corresponde al canal (un teléfono para WhatsApp, un correo para Mail o una dirección https:// para Sistema propio).`,
      );
    else {
      terms.po_channel = c;
      terms.po_channel_target = target;
    }
  } else if (target) errors.push("Canal de la OC: falta el canal del destino que cargaste.");
  const approval = str("requires_po_approval");
  if (approval) {
    const b = yesNo(approval);
    if (b === null) errors.push(`Requiere aprobación de la OC: «${approval}» va como Sí o No.`);
    else terms.requires_po_approval = b;
  }

  let payment: SupplierImportRow["payment_terms"] = null;
  const payText = str("payment_terms");
  const payDaysCell = get("payment_days");
  const minimumCell = get("minimum_order_amount");
  if (payText) {
    const p = paymentOf(payText);
    const days = payDaysCell === null ? "" : amount(payDaysCell);
    const minimum = minimumCell === null ? "" : amount(minimumCell);
    if (!p)
      errors.push(
        `Condición de pago: «${payText}» no es una opción (Contado, Contra entrega, Transferencia en el día o Cuenta corriente).`,
      );
    else if (days === null || (days !== "" && !/^[0-9]{1,3}$/.test(days)))
      errors.push("Días de pago: van en números enteros, por ejemplo 30.");
    else if (p === "account" && (days === "" || Number(days) < 1 || Number(days) > 180))
      errors.push("Días de pago: la cuenta corriente va con los días, de 1 a 180.");
    else if (minimum === null) errors.push("Pedido mínimo: va en pesos, por ejemplo 150000.");
    else
      payment = {
        payment_terms: p,
        payment_days: p === "account" ? days : "0",
        minimum_order_amount: minimum,
      };
  } else if (payDaysCell !== null || minimumCell !== null)
    errors.push(
      "Condición de pago: falta la condición de los días o el pedido mínimo que cargaste.",
    );

  const cat = str("categories", 2000);
  const categories = cat
    ? [
        ...new Set(
          cat
            .split(/[,;]/)
            .map((c) => c.trim())
            .filter((c) => c !== ""),
        ),
      ]
    : [];

  return { row, name, tax_id: taxId, supplier, terms, payment_terms: payment, categories, errors };
}

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------
export async function readSupplierSheet(file: ArrayBuffer): Promise<SupplierSheetResult> {
  const opened = await openWorkbook(file, {
    maxBytes: MAX_SUPPLIER_FILE_BYTES,
    maxUnzipped: 20 * 1024 * 1024,
    tooBig: "El archivo pasa 1 MB. Usá la plantilla, sin otras hojas ni imágenes.",
    tooBigInside: "El Excel es demasiado grande por dentro. Usá la plantilla, sin otras hojas.",
  });
  if (!opened.ok) return opened;
  const sheet = findSheet(opened.wb, norm(SUPPLIER_SHEET_NAME)) ?? opened.wb.worksheets[0];
  if (!sheet) return { ok: false, message: "El Excel no tiene hojas." };

  // Encabezados: la primera fila con «Razón social» y «CUIT», en las primeras 10.
  let headerRow = 0;
  const columns = new Map<Key, number>();
  for (let r = 1; r <= Math.min(10, sheet.rowCount) && headerRow === 0; r++) {
    const row = sheet.getRow(r);
    const found = new Map<Key, number>();
    for (let c = 1; c <= Math.min(row.cellCount, 60); c++) {
      const h = norm(value(row.getCell(c)));
      const col = SUPPLIER_COLUMNS.find(
        (x) => norm(x.header) === h || (x.also ?? []).some((a) => norm(a) === h),
      );
      if (col && !found.has(col.key)) found.set(col.key, c);
    }
    if (found.has("name") && found.has("tax_id")) {
      headerRow = r;
      for (const [k, c] of found) columns.set(k, c);
    }
  }
  if (headerRow === 0)
    return {
      ok: false,
      message: "No encontramos los encabezados «Razón social» y «CUIT». Usá la plantilla.",
    };

  const rows: SupplierImportRow[] = [];
  const last = Math.min(sheet.rowCount, MAX_SHEET_ROWS);
  for (let r = headerRow + 1; r <= last; r++) {
    const row = sheet.getRow(r);
    const get = (k: Key): Cell => {
      const c = columns.get(k);
      if (!c) return null;
      const raw: unknown = row.getCell(c).value;
      if (typeof raw === "boolean") return raw ? "Sí" : "No";
      return value(row.getCell(c));
    };
    if (SUPPLIER_COLUMNS.every((c) => get(c.key) === null)) continue;
    rows.push(readRow(r, get));
    if (rows.length > MAX_SUPPLIER_ROWS)
      return {
        ok: false,
        message: `La planilla tiene más de ${MAX_SUPPLIER_ROWS} proveedores. Partila en dos archivos.`,
      };
  }
  if (rows.length === 0)
    return { ok: false, message: "La planilla no tiene proveedores cargados." };

  // El mismo CUIT dos veces en el archivo: error en las dos filas.
  const byCuit = new Map<string, number[]>();
  for (const r of rows)
    if (r.tax_id) byCuit.set(r.tax_id, [...(byCuit.get(r.tax_id) ?? []), r.row]);
  for (const r of rows) {
    const same = r.tax_id ? (byCuit.get(r.tax_id) ?? []) : [];
    if (same.length > 1)
      r.errors.push(`CUIT repetido en la planilla (filas ${same.join(", ")}): dejá uno solo.`);
  }
  return { ok: true, rows };
}

// ---------------------------------------------------------------------------
// Plantilla
// ---------------------------------------------------------------------------
// Un .xlsx con los encabezados, una fila de ejemplo inventada y una hoja «Valores» con las opciones y los rubros del grupo.
const EXAMPLE_MARK = "(borrá esta fila)";

export async function buildSupplierTemplate(categoryNames: string[]): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(SUPPLIER_SHEET_NAME);
  ws.addRow(SUPPLIER_COLUMNS.map((c) => c.header));
  ws.getRow(1).font = { bold: true };
  ws.addRow([
    `Ejemplo Verduras SRL ${EXAMPLE_MARK}`,
    "30-12345678-1",
    "Verdulería Ejemplo",
    "Responsable inscripto",
    "Calle Inventada 123",
    "Ciudad de Ejemplo",
    "011 4000-0000",
    "+54 9 11 4000-0000",
    "pedidos@ejemplo.test",
    "Ana Ventas",
    "Luis Pagos",
    categoryNames.slice(0, 2).join(", "),
    "lun, mié, vie",
    "mar, jue, sáb",
    "WhatsApp",
    "+54 9 11 4000-0000",
    "No",
    "Cuenta corriente",
    30,
    150000,
  ]);
  SUPPLIER_COLUMNS.forEach((c, i) => {
    ws.getColumn(i + 1).width = Math.max(14, c.header.length + 4);
  });
  ws.views = [{ state: "frozen", ySplit: 1 }];

  const values = wb.addWorksheet("Valores");
  const lists: [string, string[]][] = [
    ["Obligatorias", SUPPLIER_COLUMNS.filter((c) => c.required).map((c) => c.header)],
    ["Condición IVA", Object.values(VAT_LABELS)],
    ["Días (separados por coma)", WEEK_DAYS.map((d) => d.name)],
    ["Canal de la OC", Object.values(CHANNEL_LABELS)],
    [
      "Destino de la OC",
      ["WhatsApp: el número", "Mail: el correo", "Sistema propio: la dirección https://"],
    ],
    ["Requiere aprobación de la OC", ["Sí", "No"]],
    ["Condición de pago", Object.values(PAYMENT_TERMS_LABELS)],
    ["Días de pago", ["Solo con Cuenta corriente: de 1 a 180"]],
    ["Rubros (separados por coma)", categoryNames],
    [
      "No van en la planilla",
      [
        "Cuentas de pago (CBU, alias): se cargan en la ficha",
        "Números de cliente por local: se cargan en la ficha",
      ],
    ],
  ];
  lists.forEach(([title, items], i) => {
    const col = values.getColumn(i + 1);
    col.width = Math.max(18, title.length + 2, ...items.map((t) => Math.min(t.length + 2, 60)));
    values.getCell(1, i + 1).value = title;
    values.getCell(1, i + 1).font = { bold: true };
    items.forEach((t, j) => {
      values.getCell(j + 2, i + 1).value = t;
    });
  });
  return Buffer.from(await wb.xlsx.writeBuffer());
}
