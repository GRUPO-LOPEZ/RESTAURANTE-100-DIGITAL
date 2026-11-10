import { Suspense } from "react";
import { MonitorSmartphone, ShieldCheck } from "lucide-react";

import {
  changePasswordAction,
  signOutOthersAction,
  updateMyProfileAction,
} from "@/app/mi-cuenta/actions";
import { FactorChange } from "@/app/mi-cuenta/factor-change";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import Link from "next/link";

import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { ErrorState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { FormInput } from "@/components/ui/form";
import { requireOperable } from "@/lib/auth/session";
import { first, formatDateTime, getMyAccount } from "@/lib/data";

// Mi cuenta (sección 9; pestañas del rediseño, ADR-0036): datos propios, contraseña, doble verificación y
// sesiones abiertas. La pestaña va en la dirección (?seccion=).
export default function MiCuentaPage({ searchParams }: PageProps<"/mi-cuenta">) {
  return (
    <AppShell
      title="Mi cuenta"
      description="Tus datos, tu contraseña y dónde tenés la sesión abierta."
    >
      <Suspense fallback={<Loading />}>
        <Account searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// "Chrome en Windows", "Safari en iPhone"... en lugar del texto técnico del navegador.
function deviceName(userAgent: string | null): string {
  if (!userAgent) return "Dispositivo sin identificar";
  const browser = /Edg\//.test(userAgent)
    ? "Edge"
    : /Chrome\//.test(userAgent)
      ? "Chrome"
      : /Firefox\//.test(userAgent)
        ? "Firefox"
        : /Safari\//.test(userAgent)
          ? "Safari"
          : "Navegador";
  const system = /iPhone|iPad/.test(userAgent)
    ? "iPhone o iPad"
    : /Android/.test(userAgent)
      ? "Android"
      : /Windows/.test(userAgent)
        ? "Windows"
        : /Mac OS X/.test(userAgent)
          ? "Mac"
          : /Linux/.test(userAgent)
            ? "Linux"
            : "otro sistema";
  return `${browser} en ${system}`;
}

const SECTIONS = [
  { key: "datos", label: "Mis datos" },
  { key: "seguridad", label: "Contraseña y doble verificación" },
  { key: "sesiones", label: "Sesiones" },
] as const;
type Section = (typeof SECTIONS)[number]["key"];

async function Account({
  searchParams,
}: {
  searchParams: PageProps<"/mi-cuenta">["searchParams"];
}) {
  // Primero la sesión (que sea operable); después los datos de la cuenta.
  const session = await requireOperable();
  const [account, query] = await Promise.all([getMyAccount(), searchParams]);
  const wanted = first(query.seccion);
  const section: Section = SECTIONS.find((t) => t.key === wanted)?.key ?? "datos";
  const show = (key: Section) => section === key;
  if (!account)
    return (
      <ErrorState
        title="No pudimos cargar tu cuenta."
        action={
          <Link
            href="/mi-cuenta"
            className="inline-flex min-h-touch items-center font-medium underline underline-offset-4"
          >
            Probá de nuevo
          </Link>
        }
      />
    );
  const verified = account.mfa_factors.filter((f) => f.status === "verified");
  const others = account.sessions.filter((s) => !s.is_current).length;

  return (
    <>
      <Tabs
        label="Secciones de mi cuenta"
        items={SECTIONS.map((t) => ({
          href: t.key === "datos" ? "/mi-cuenta" : `/mi-cuenta?seccion=${t.key}`,
          label: t.label,
          current: show(t.key),
        }))}
      />

      {show("datos") ? (
        <Card className="flex max-w-3xl flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Mis datos</CardTitle>
            <CardDescription className="break-all">
              {account.email}
              {account.job_title ? ` · ${account.job_title}` : ""}
              {account.last_seen_at
                ? ` · Último acceso: ${formatDateTime(account.last_seen_at)}`
                : ""}
            </CardDescription>
          </div>
          <ActionForm
            action={updateMyProfileAction}
            schema="profile"
            submitLabel="Guardar mis datos"
            pendingLabel="Guardando…"
            className="grid gap-4 sm:grid-cols-2 sm:items-start"
            warnUnsaved
          >
            <FormInput
              id="first_name"
              label="Nombre"
              name="first_name"
              defaultValue={account.first_name ?? ""}
              autoComplete="given-name"
              required
            />
            <FormInput
              id="last_name"
              label="Apellido"
              name="last_name"
              defaultValue={account.last_name ?? ""}
              autoComplete="family-name"
              required
            />
          </ActionForm>
          <p className="text-sm text-ink-muted">
            El correo, el puesto y el área los cambia quien administra tu local.
          </p>
        </Card>
      ) : null}

      {show("seguridad") ? (
        <Card className="flex max-w-3xl flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Contraseña</CardTitle>
          </div>
          <ActionForm
            action={changePasswordAction}
            schema="changePassword"
            submitLabel="Cambiar la contraseña"
            pendingLabel="Cambiando…"
          >
            <FormInput
              id="current"
              label="Contraseña actual"
              name="current"
              type="password"
              maxLength={200}
              autoComplete="current-password"
              required
            />
            <FormInput
              id="password-new"
              label="Contraseña nueva"
              hint="Mínimo 12 caracteres, con letras y números."
              name="password"
              type="password"
              maxLength={200}
              autoComplete="new-password"
              required
            />
            <FormInput
              id="repeat"
              label="Repetí la contraseña nueva"
              name="repeat"
              type="password"
              maxLength={200}
              autoComplete="new-password"
              required
            />
          </ActionForm>
        </Card>
      ) : null}

      {show("seguridad") ? (
        <Card className="flex max-w-3xl flex-col gap-4">
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>Doble verificación</CardTitle>
            {verified.length > 0 ? (
              <Badge status="ok">
                <ShieldCheck aria-hidden="true" />
                Activa
              </Badge>
            ) : session.requires_mfa ? (
              <Badge status="warn">Falta registrarla</Badge>
            ) : (
              <Badge status="neutral">No la usás</Badge>
            )}
          </div>
          {verified.length > 0 ? (
            <>
              <ul className="flex flex-col gap-1 text-base text-ink">
                {verified.map((f) => (
                  <li key={f.id}>
                    {f.friendly_name ?? "App de autenticación"}{" "}
                    <span className="text-sm text-ink-muted">
                      · desde {formatDateTime(f.created_at)}
                    </span>
                  </li>
                ))}
              </ul>
              <FactorChange />
            </>
          ) : (
            <p className="text-base text-ink-muted">
              {session.requires_mfa
                ? "Tu rol la exige: la vas a registrar la próxima vez que ingreses."
                : "Tu rol no la exige."}
            </p>
          )}
        </Card>
      ) : null}

      {show("sesiones") ? (
        <Card className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <CardTitle>Sesiones abiertas</CardTitle>
            <CardDescription>
              Dónde está abierta tu cuenta. Si ves algo que no reconocés, cerrá las demás y cambiá
              tu contraseña.
            </CardDescription>
          </div>
          <ul className="flex flex-col gap-2">
            {account.sessions.map((s) => (
              <li
                key={s.id}
                className="flex flex-wrap items-center gap-2 border-b border-line pb-2 last:border-0 last:pb-0"
              >
                <MonitorSmartphone aria-hidden="true" className="size-5 text-ink-muted" />
                <span className="text-base text-ink">{deviceName(s.user_agent)}</span>
                {s.is_current ? <Badge status="info">Esta sesión</Badge> : null}
                <span className="text-sm text-ink-muted">
                  · Usada el {formatDateTime(s.last_used_at ?? s.created_at)}
                </span>
              </li>
            ))}
          </ul>
          {others > 0 ? (
            <ActionForm
              action={signOutOthersAction}
              submitLabel={
                others === 1 ? "Cerrar la otra sesión" : `Cerrar las otras ${others} sesiones`
              }
              pendingLabel="Cerrando…"
              variant="outline"
            />
          ) : (
            <p className="text-sm text-ink-muted">No tenés otras sesiones abiertas.</p>
          )}
        </Card>
      ) : null}
    </>
  );
}
