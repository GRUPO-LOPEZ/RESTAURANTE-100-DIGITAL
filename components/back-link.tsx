import Link from "next/link";
import { ArrowLeft } from "lucide-react";

// "← Volver" de las fichas y pantallas secundarias (ADR-0036): siempre en el mismo lugar, con la flecha y 44 px
// en el celular. No sale en el papel.
// label: el nombre para los lectores de pantalla cuando el texto visible es corto («Materias primas» se anuncia como
// «Volver a materias primas»; contiene lo que se ve, WCAG 2.5.3).
export function BackLink({
  href,
  label,
  children,
}: {
  href: string;
  label?: string;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      aria-label={label}
      className="inline-flex min-h-touch items-center gap-1 self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control print:hidden"
    >
      <ArrowLeft aria-hidden="true" className="size-4" />
      {children}
    </Link>
  );
}
