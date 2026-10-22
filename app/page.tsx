import Link from "next/link";
import { Suspense } from "react";
import { ClipboardCheck, FileText, History, KeyRound, Users } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { SCOPE_LABELS, getUser } from "@/lib/data";
import { displayName, getMenus, requireOperable } from "@/lib/auth/session";

export default function InicioPage() {
  return (
    <AppShell title="Inicio">
      <Suspense fallback={<Loading />}>
        <Home />
      </Suspense>
    </AppShell>
  );
}

async function Home() {
  const session = await requireOperable();
  const [me, menus] = await Promise.all([getUser(session.user_id ?? ""), getMenus()]);

  const shortcuts = [
    {
      href: "/usuarios",
      label: "Usuarios",
      text: "Quién tiene acceso y qué está pasando.",
      Icon: Users,
      show: menus.users,
    },
    {
      href: "/aprobaciones",
      label: "Aprobaciones",
      text: "Pedidos que esperan una decisión.",
      Icon: ClipboardCheck,
      show: menus.approvals,
    },
    {
      href: "/historial",
      label: "Historial",
      text: "Quién cambió qué, cuándo y por qué.",
      Icon: History,
      show: menus.audit,
    },
    {
      href: "/roles",
      label: "Roles y permisos",
      text: "Qué puede hacer cada rol.",
      Icon: KeyRound,
      show: menus.roles,
    },
    {
      href: "/ensayo",
      label: "Ensayo",
      text: "Documentos de prueba de la Fase 1.",
      Icon: FileText,
      show: menus.testDocuments,
    },
  ].filter((s) => s.show);

  return (
    <>
      <Card className="flex flex-col gap-2">
        <CardTitle>Hola, {displayName(session)}</CardTitle>
        <CardDescription>Estos son tus roles y dónde los tenés.</CardDescription>
        <ul className="flex flex-col gap-1">
          {(me?.roles ?? []).map((r) => (
            <li key={r.assignment_id} className="text-base text-ink">
              {r.role_name}{" "}
              <span className="text-ink-muted">
                · {SCOPE_LABELS[r.scope_type]} {r.scope_name}
              </span>
            </li>
          ))}
        </ul>
      </Card>
      {shortcuts.length > 0 ? (
        <nav aria-label="Accesos" className="grid gap-4 sm:grid-cols-3">
          {shortcuts.map(({ href, label, text, Icon }) => (
            <Link
              key={href}
              href={href}
              className="flex flex-col gap-2 rounded-lg border border-line bg-surface p-4 hover:bg-line/50"
            >
              <span className="flex items-center gap-2 text-xl font-semibold text-ink">
                <Icon aria-hidden="true" className="size-5" />
                {label}
              </span>
              <span className="text-sm text-ink-muted">{text}</span>
            </Link>
          ))}
        </nav>
      ) : null}
    </>
  );
}
