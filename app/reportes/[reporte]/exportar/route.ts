import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { UUID, formatDate, formatDateTime } from "@/lib/data";
import { reportCsv, reportXlsx } from "@/lib/report-files";
import {
  REPORT_EXPORT_LIMIT,
  allergenLine,
  argentinaDay,
  reportDefinition,
  reportFileName,
  reportPeriod,
} from "@/lib/report-labels";
import { getReportPlaces, getReportRows, logReport } from "@/lib/reports";
import { createClient } from "@/lib/supabase/server";

// Un reporte en Excel o CSV (ADR-0034). Con la sesión de la persona: la base pide reports.export y el
// permiso de cada dato, y lo que sale queda en el registro de seguridad. Si algo falla, vuelve al reporte.
export async function GET(request: NextRequest, ctx: RouteContext<"/reportes/[reporte]/exportar">) {
  const { reporte } = await ctx.params;
  const report = reportDefinition(reporte);
  const p = request.nextUrl.searchParams;
  const local = p.get("local");
  const format = p.get("formato");
  // Una descarga deja un registro a nombre de la persona: no la dispara otro sitio.
  if (request.headers.get("sec-fetch-site") === "cross-site") {
    return new NextResponse("No encontrado", { status: 404 });
  }
  if (!report || !local || !UUID.test(local) || (format !== "xlsx" && format !== "csv")) {
    return new NextResponse("No encontrado", { status: 404 });
  }
  // Las redirecciones usan el host del pedido (detrás de un proxy, request.url puede ser otro).
  const host = request.headers.get("host") ?? request.nextUrl.host;
  const proto =
    request.headers.get("x-forwarded-proto") ?? request.nextUrl.protocol.replace(":", "");
  const base = `${proto}://${host}`;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.redirect(new URL("/ingresar", base));

  const back = new URL(`/reportes/${report.key}`, base);
  back.searchParams.set("local", local);
  back.searchParams.set("aviso", "no-se-pudo");
  const now = new Date();
  const period = reportPeriod(p.get("desde") ?? undefined, p.get("hasta") ?? undefined, now);
  const recipe = p.get("receta");
  if (report.recipe && (!recipe || !UUID.test(recipe))) {
    return new NextResponse("No encontrado", { status: 404 });
  }
  if (report.recipe && recipe) back.searchParams.set("receta", recipe);
  if (report.period) {
    back.searchParams.set("desde", period.from);
    back.searchParams.set("hasta", period.to);
  }
  try {
    const [places, result] = await Promise.all([
      getReportPlaces(),
      getReportRows(report.key, {
        restaurantId: local,
        ...period,
        recipeId: report.recipe ? (recipe ?? undefined) : undefined,
      }),
    ]);
    const place = places.find((x) => x.id === local);
    if (!place || !result) return new NextResponse("No encontrado", { status: 404 });
    // Sin registro no sale nada: lo que se exporta tiene que quedar anotado.
    const logged = await logReport(
      report.key,
      local,
      format,
      result.rows.length,
      report.period ? period : undefined,
      report.recipe ? (recipe ?? undefined) : undefined,
    );
    if (!logged) {
      return NextResponse.redirect(back);
    }
    const header = {
      place: place.name,
      generated: formatDateTime(now.toISOString()),
      period: report.period ? `${formatDate(period.from)} a ${formatDate(period.to)}` : undefined,
      summary: result.summary ? [...result.summary, ...allergenLine(result.alerts)] : undefined,
      note:
        result.total > result.rows.length
          ? `Se exportan las primeras ${REPORT_EXPORT_LIMIT.toLocaleString("es-AR")} de ${result.total.toLocaleString("es-AR")} filas.`
          : undefined,
    };
    const name = reportFileName(report.key, place.name, argentinaDay(now));
    if (format === "csv") {
      return new NextResponse(reportCsv(report, header, result.rows), {
        headers: {
          "Content-Type": "text/csv; charset=utf-8",
          "Content-Disposition": `attachment; filename="${name}.csv"`,
          "Cache-Control": "no-store",
        },
      });
    }
    return new NextResponse(await reportXlsx(report, header, result.rows), {
      headers: {
        "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="${name}.xlsx"`,
        "Cache-Control": "no-store",
      },
    });
  } catch {
    return NextResponse.redirect(back);
  }
}
