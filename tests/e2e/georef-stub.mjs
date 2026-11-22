// Georef de mentira para Playwright (ADR-0061): las pruebas no dependen de la API del gobierno. Responde como
// /georef/api/direcciones: encuentra las direcciones que empiezan con «Calle Ficticia» (datos inventados del seed) y
// no encuentra ninguna otra. Uso: node tests/e2e/georef-stub.mjs <puerto>
import { createServer } from "node:http";

const port = Number(process.argv[2] ?? 3190);

createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://127.0.0.1:${port}`);
  res.setHeader("Content-Type", "application/json");
  if (url.pathname === "/health") {
    res.end("{}");
    return;
  }
  if (url.pathname !== "/direcciones") {
    res.statusCode = 404;
    res.end("{}");
    return;
  }
  const address = (url.searchParams.get("direccion") ?? "").trim();
  const found = /^calle ficticia/i.test(address);
  res.end(
    JSON.stringify({
      cantidad: found ? 1 : 0,
      direcciones: found
        ? [
            {
              nomenclatura: `${address.toUpperCase()}, Comuna 1, Ciudad Autónoma de Buenos Aires`,
              ubicacion: { lat: -34.6037, lon: -58.3816 },
              provincia: { id: "02", nombre: "Ciudad Autónoma de Buenos Aires" },
              localidad_censal: { nombre: "Ciudad Autónoma de Buenos Aires" },
              departamento: { nombre: "Comuna 1" },
            },
          ]
        : [],
    }),
  );
}).listen(port, "127.0.0.1");
