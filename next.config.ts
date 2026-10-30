import type { NextConfig } from "next";

// Encabezados de seguridad para todas las pantallas (revisión de seguridad de la Fase 1).
// Las pantallas de desactivar o aprobar no se pueden mostrar dentro de otro sitio (clickjacking).
// Pendiente antes de producción: una Content-Security-Policy completa, probada con Next.
const securityHeaders = [
  { key: "Content-Security-Policy", value: "frame-ancestors 'none'" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
];

const nextConfig: NextConfig = {
  // Las fotos de las recetas viajan por una acción de servidor: llegan achicadas desde el navegador
  // (hasta 1.600 px, JPEG) y el bucket acepta hasta 3 MB; el resto es margen del formulario.
  experimental: {
    serverActions: { bodySizeLimit: "4mb" },
  },
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
