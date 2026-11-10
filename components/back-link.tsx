import Link from "next/link";
import { ArrowLeft } from "lucide-react";

// "← Volver" de las fichas y pantallas secundarias (ADR-0036): siempre en el mismo lugar, con la flecha y 44 px
// en el celular. No sale en el papel.
export function BackLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex min-h-touch items-center gap-1 self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control print:hidden"
    >
      <ArrowLeft aria-hidden="true" className="size-4" />
      {children}
    </Link>
  );
}
