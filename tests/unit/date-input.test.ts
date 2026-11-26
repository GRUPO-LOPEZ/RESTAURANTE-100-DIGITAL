// Fechas en dd/mm/aaaa (criterio 12 de Soy, ADR-0068): lo que se escribe en el campo propio y cómo viaja (ISO).
import { describe, expect, it } from "vitest";

import { dayError, dayToIso, isoToDay, maskDay } from "@/lib/dates";

describe("isoToDay", () => {
  it("pasa ISO a dd/mm/aaaa", () => {
    expect(isoToDay("2026-11-19")).toBe("19/11/2026");
    expect(isoToDay("2026-11-19T10:00:00Z")).toBe("19/11/2026");
  });
  it("sin fecha o algo que no es ISO, vacío", () => {
    expect(isoToDay("")).toBe("");
    expect(isoToDay(null)).toBe("");
    expect(isoToDay(undefined)).toBe("");
    expect(isoToDay("19/11/2026")).toBe("");
  });
});

describe("maskDay", () => {
  it("pone las barras solas al escribir", () => {
    expect(maskDay("1")).toBe("1");
    expect(maskDay("19")).toBe("19");
    expect(maskDay("191")).toBe("19/1");
    expect(maskDay("1911")).toBe("19/11");
    expect(maskDay("19112026")).toBe("19/11/2026");
  });
  it("sigue escribiendo sobre lo que ya tiene barras sin perder números", () => {
    expect(maskDay("19/1")).toBe("19/1");
    expect(maskDay("19/11")).toBe("19/11");
    expect(maskDay("19/112")).toBe("19/11/2");
    expect(maskDay("19/11/20261")).toBe("19/11/2026");
  });
  it("respeta día y mes de un dígito escritos con barras", () => {
    expect(maskDay("1/2/2026")).toBe("1/2/2026");
  });
  it("una fecha ISO pegada pasa a dd/mm/aaaa", () => {
    expect(maskDay("2026-11-19")).toBe("19/11/2026");
  });
  it("saca lo que no son números", () => {
    expect(maskDay("19a11b2026")).toBe("19/11/2026");
  });
});

describe("dayToIso", () => {
  it("dd/mm/aaaa a ISO", () => {
    expect(dayToIso("19/11/2026")).toEqual({ kind: "ok", iso: "2026-11-19" });
    expect(dayToIso("1/2/2026")).toEqual({ kind: "ok", iso: "2026-02-01" });
  });
  it("dos dígitos de año son del 2000", () => {
    expect(dayToIso("19/11/26")).toEqual({ kind: "ok", iso: "2026-11-19" });
  });
  it("bisiestos: el 29/02 vale solo si el año lo tiene", () => {
    expect(dayToIso("29/02/2028")).toEqual({ kind: "ok", iso: "2028-02-29" });
    expect(dayToIso("29/02/2026")).toEqual({ kind: "invalid" });
    expect(dayToIso("29/02/2100")).toEqual({ kind: "invalid" });
    expect(dayToIso("29/02/2000")).toEqual({ kind: "ok", iso: "2000-02-29" });
  });
  it("una fecha que no existe no vale", () => {
    expect(dayToIso("31/02/2026")).toEqual({ kind: "invalid" });
    expect(dayToIso("31/04/2026")).toEqual({ kind: "invalid" });
    expect(dayToIso("00/11/2026")).toEqual({ kind: "invalid" });
    expect(dayToIso("19/13/2026")).toEqual({ kind: "invalid" });
  });
  it("a medio escribir no vale; vacío es vacío", () => {
    expect(dayToIso("19/11")).toEqual({ kind: "invalid" });
    expect(dayToIso("19/11/202")).toEqual({ kind: "invalid" });
    expect(dayToIso("")).toEqual({ kind: "empty" });
    expect(dayToIso("   ")).toEqual({ kind: "empty" });
  });
  it("nunca el formato de Estados Unidos: 11/19/2026 no es una fecha", () => {
    expect(dayToIso("11/19/2026")).toEqual({ kind: "invalid" });
  });
});

describe("dayError", () => {
  it("dice por qué no vale, en castellano", () => {
    expect(dayError("31/02/2026")).toBe("Escribí una fecha que exista, como dd/mm/aaaa.");
    expect(dayError("20/11/2026", undefined, "2026-11-19")).toBe(
      "Tiene que ser hasta el 19/11/2026.",
    );
    expect(dayError("18/11/2026", "2026-11-19")).toBe("Tiene que ser desde el 19/11/2026.");
  });
  it("vacío o dentro del rango: sin error", () => {
    expect(dayError("")).toBeNull();
    expect(dayError("19/11/2026", "2026-11-19", "2026-11-19")).toBeNull();
  });
});
