-- Fase 2: se retira el documento de ensayo de la Fase 1 (ADR-0023). Las pruebas 2, 3 y 7 pasaron a las recetas reales
-- (238_fase1_recetas_reales). Nada se borra de audit: los eventos viejos guardan su módulo y se siguen leyendo en el
-- historial. core.enforce_version_rules queda: la usan las recetas.

drop function core.create_test_document_draft(uuid, text, text, uuid, text, numeric, uuid);
drop function core.request_test_document_review(uuid, text);
drop function core.publish_test_document(uuid, text);
drop view core.v_test_documents;
drop table core.test_documents;

-- Los permisos se dan de baja: primero en los roles, porque la base no deja borrar un permiso que un rol tiene.
do $$
begin
  perform core.set_change_context('Se retira el documento de ensayo de la Fase 1', 'maintenance');
  update core.role_permissions rp set deleted_at = now()
    from core.permissions p
   where p.id = rp.permission_id and p.module = 'test_documents' and rp.deleted_at is null;
  update ai.integration_permissions ip set deleted_at = now()
    from core.permissions p
   where p.id = ip.permission_id and p.module = 'test_documents' and ip.deleted_at is null;
  update core.permissions set deleted_at = now() where module = 'test_documents' and deleted_at is null;
end
$$;
