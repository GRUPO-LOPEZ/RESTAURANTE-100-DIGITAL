import { describe, expect, it } from "vitest";
import { brandCode, codeWord, restaurantCode, restaurantName } from "@/lib/org-codes";
import { documentStatus } from "@/lib/legal-entity";

describe("códigos de marca y de local (ADR-0061)", () => {
  it("la palabra va en mayúsculas, sin tildes ni espacios", () => {
    expect(codeWord("Ragú")).toBe("RAGU");
    expect(codeWord("  Casa Ñandú ")).toBe("CASANANDU");
    expect(codeWord("Café & Co.")).toBe("CAFECO");
    expect(codeWord("Una marca con un nombre larguísimo")).toHaveLength(16);
  });

  it("la marca lleva su número de dos cifras, así la 10 no va antes que la 2", () => {
    expect(brandCode(1, "Ragú")).toBe("01-RAGU");
    expect(brandCode(2, "Padella")).toBe("02-PADELLA");
    expect(brandCode(10, "Nonnos")).toBe("10-NONNOS");
    expect([brandCode(10, "B"), brandCode(2, "A")].sort()).toEqual(["02-A", "10-B"]);
  });

  it("el local usa la palabra de su marca y un número de tres cifras", () => {
    expect(restaurantCode("01-RAGU", 1)).toBe("RAGU-001");
    expect(restaurantCode("02-PADELLA", 12)).toBe("PADELLA-012");
    // Una marca con el código de antes lo usa entero.
    expect(restaurantCode("PASTAS", 2)).toBe("PASTAS-002");
  });

  it("el nombre del local es el nombre corto de la marca y la zona", () => {
    expect(restaurantName("Ragú", "Leloir")).toBe("Ragú Leloir");
    expect(restaurantName(" Padella ", " Palermo ")).toBe("Padella Palermo");
  });
});

describe("constancia de ARCA (ADR-0061)", () => {
  it("sin constancia, no hay estado positivo", () => {
    expect(documentStatus(null, "2026-11-22")).toBe("missing");
  });

  it("al día hasta 12 meses, vencida después", () => {
    expect(documentStatus("2026-11-01", "2026-11-22")).toBe("current");
    expect(documentStatus("2025-11-22", "2026-11-22")).toBe("current");
    expect(documentStatus("2025-11-21", "2026-11-22")).toBe("stale");
  });

  it("el 29 de febrero cuenta como en la base", () => {
    expect(documentStatus("2027-02-28", "2028-02-29")).toBe("current");
    expect(documentStatus("2027-02-27", "2028-02-29")).toBe("stale");
  });
});
