// Listas cortadas de las pantallas sin scroll (ADR-0046): cuántas filas se muestran antes de «Ver los N».
import { describe, expect, it } from "vitest";

import { shownCount } from "@/components/ui/short-list";

describe("lista cortada", () => {
  it("muestra hasta el límite y nunca más", () => {
    expect(shownCount(5, 3)).toBe(3);
    expect(shownCount(3, 3)).toBe(3);
    expect(shownCount(2, 3)).toBe(2);
  });

  it("sin filas no muestra nada, y un límite raro no rompe", () => {
    expect(shownCount(0, 3)).toBe(0);
    expect(shownCount(4, 0)).toBe(0);
    expect(shownCount(-1, 3)).toBe(0);
  });
});
