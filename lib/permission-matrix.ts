// Borrador de la matriz de permisos (ADR-0039): la pantalla guarda solo lo que cambió respecto de la base.
// Volver una celda a su valor original la saca del borrador. La base decide todo al guardar.

export type MatrixCell = { roleCode: string; permissionCode: string };

export type MatrixChange = { role_id: string; permission_code: string; granted: boolean };

export function cellKey(roleCode: string, permissionCode: string): string {
  return `${roleCode}|${permissionCode}`;
}

// Cambia una celda: si vuelve a lo que dice la base, sale del borrador.
export function toggleCell(
  draft: ReadonlyMap<string, boolean>,
  original: ReadonlySet<string>,
  key: string,
): Map<string, boolean> {
  const next = new Map(draft);
  const current = next.has(key) ? next.get(key) === true : original.has(key);
  const value = !current;
  if (value === original.has(key)) next.delete(key);
  else next.set(key, value);
  return next;
}

// Lo que se ve en una celda: el borrador si la cambiaron, si no, la base.
export function cellValue(
  draft: ReadonlyMap<string, boolean>,
  original: ReadonlySet<string>,
  key: string,
): boolean {
  return draft.has(key) ? draft.get(key) === true : original.has(key);
}

// El lote para la base, con el id de cada rol.
export function buildChanges(
  draft: ReadonlyMap<string, boolean>,
  roleIds: ReadonlyMap<string, string>,
): MatrixChange[] {
  const changes: MatrixChange[] = [];
  for (const [key, granted] of draft) {
    const [roleCode, permissionCode] = key.split("|");
    const roleId = roleCode ? roleIds.get(roleCode) : undefined;
    if (!roleId || !permissionCode) continue;
    changes.push({ role_id: roleId, permission_code: permissionCode, granted });
  }
  return changes;
}

// Cuántos permisos sensibles se están dando (para la confirmación al guardar).
export function sensitiveGrants(
  draft: ReadonlyMap<string, boolean>,
  sensitive: ReadonlySet<string>,
): number {
  let n = 0;
  for (const [key, granted] of draft) {
    const permissionCode = key.split("|")[1];
    if (granted && permissionCode && sensitive.has(permissionCode)) n += 1;
  }
  return n;
}

export function pendingLabel(n: number): string {
  return n === 1 ? "1 cambio sin guardar" : `${n} cambios sin guardar`;
}
