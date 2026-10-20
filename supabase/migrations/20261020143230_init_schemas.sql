-- Fase 0: esquemas por tema (prompt maestro, sección 5).
-- Solo crea los esquemas vacíos. Las tablas llegan desde la Fase 1.
-- Denegar por defecto: ningún rol de la API (anon, authenticated) recibe permisos acá.
-- Cada tabla nueva tendrá sus GRANT y políticas RLS explícitas en su propia migración.

create schema if not exists core;
comment on schema core is 'Identidad, roles y permisos: perfiles, roles, permisos, membresías, asignaciones con alcance y cuentas técnicas.';

create schema if not exists org;
comment on schema org is 'Estructura del grupo: grupos, marcas, restaurantes y áreas.';

create schema if not exists audit;
comment on schema audit is 'Historia inalterable: eventos de auditoría (solo inserción) y eventos de seguridad de autenticación.';

create schema if not exists workflow;
comment on schema workflow is 'Aprobaciones: flujos, solicitudes y decisiones.';

create schema if not exists catalog;
comment on schema catalog is 'Materias primas y proveedores: ingredientes, proveedores, unidades, conversiones y precios de proveedor.';

create schema if not exists recipes;
comment on schema recipes is 'Recetario y fichas técnicas: recetas, versiones, líneas, pasos y fotos.';

create schema if not exists costing;
comment on schema costing is 'Costos: fotos de costo, costos de receta e historial de precios.';

create schema if not exists purchasing;
comment on schema purchasing is 'Compras: órdenes de compra, sus líneas, facturas y sus líneas.';

create schema if not exists inventory;
comment on schema inventory is 'Stock: ubicaciones, movimientos y conteos.';

create schema if not exists production;
comment on schema production is 'Producción: planes y lotes de producción.';

create schema if not exists ai;
comment on schema ai is 'Agentes de IA: corridas, propuestas y permisos de integración. Los agentes escriben solo acá.';

create schema if not exists reporting;
comment on schema reporting is 'Lectura para tableros: solo vistas y vistas materializadas, nunca datos propios.';
